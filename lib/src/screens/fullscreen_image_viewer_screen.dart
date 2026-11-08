import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show instantiateImageCodec;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kemono_browser_project/src/api/api_constants.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/api/pawchive_client.dart';
import 'package:kemono_browser_project/src/archive/archive_service.dart';
import 'package:kemono_browser_project/src/cache/file_errors.dart';
import 'package:kemono_browser_project/src/cache/file_size_gate.dart';
import 'package:kemono_browser_project/src/cache/image_cache_service.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';
import 'package:kemono_browser_project/src/cache/kemono_image_provider.dart';
import 'package:kemono_browser_project/src/state/app_state.dart';
import 'package:kemono_browser_project/src/utils.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_flutter.dart';
import 'package:video_adapter_media_kit/video_adapter_media_kit.dart';

// =============================================================================
// FullscreenImageViewerScreen — entry points
// =============================================================================

/// Fullscreen pager built on [LeafViewer] (see the `leaf_widgets` package for
/// the gesture/zoom/dismiss machinery).
///
/// Both [open] and [openArchive] delegate to [_FullscreenPageViewInner] so
/// they share the same dark-overlay chrome (nav arrows, keyboard nav, page
/// counter). Pages are plain content: zoomable images wrapped in
/// [LeafZoomable], videos via [LeafVideoPage] over [MediaKitAdapter].
class FullscreenImageViewerScreen extends StatelessWidget {
  const FullscreenImageViewerScreen({super.key});

  /// Compute the display size for `BoxFit.contain` given container dimensions
  /// and an aspect ratio (width/height).
  static (double, double) _containSize(double containerW, double containerH, double aspectRatio) {
    if (aspectRatio <= 0) aspectRatio = 1.0;
    if (containerW / containerH > aspectRatio) {
      return (containerH * aspectRatio, containerH);
    } else {
      return (containerW, containerW / aspectRatio);
    }
  }

  // ---------------------------------------------------------------------------
  // Shared core
  // ---------------------------------------------------------------------------

  /// Push a fullscreen PageView route.
  static void _openCore(
    BuildContext context, {
    required int itemCount,
    required int initialIndex,
    String? subtitle,
    required Widget Function(BuildContext, int index) pageBuilder,
  }) {
    final pageController = PageController(initialPage: initialIndex);
    final focusNode = FocusNode();
    final currentIndex = signal(initialIndex);

    void goTo(int target) {
      if (target < 0 || target >= itemCount) return;
      pageController.animateToPage(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }

    Navigator.of(context)
        .push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.transparent,
            barrierDismissible: true,
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            pageBuilder: (context, animation, secondaryAnimation) => _FullscreenPageViewInner(
              itemCount: itemCount,
              currentIndex: currentIndex,
              subtitle: subtitle,
              pageController: pageController,
              focusNode: focusNode,
              onGoTo: goTo,
              pageBuilder: pageBuilder,
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
              child: child,
            ),
          ),
        )
        .then((_) {
          pageController.dispose();
          focusNode.dispose();
        });

    focusNode.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // open() — API-sourced images
  // ---------------------------------------------------------------------------

  /// Open the fullscreen multi-image viewer for API-sourced images.
  ///
  /// [hasFull] mirrors [Post.hasFull]: when false the post has no stored or
  /// proxied originals and only thumbnails exist.
  static void open(
    BuildContext context, {
    required List<FileInfo> files,
    required int index,
    required String service,
    required String creatorId,
    required String postId,
    bool hasFull = true,
    bool pending = false,
  }) {
    if (pending) return;

    final mediaFiles = files.where((f) => FileHelpers.isImage(f.name) || FileHelpers.isVideo(f.name)).toList();
    if (mediaFiles.isEmpty) return;

    final mediaIndex = mediaFiles.indexOf(files[index]);
    final adjustedIndex = mediaIndex >= 0 ? mediaIndex : 0;

    _openCore(
      context,
      itemCount: mediaFiles.length,
      initialIndex: adjustedIndex,
      pageBuilder: (context, i) {
        final f = mediaFiles[i];
        final url = f.downloadUrl(hasFull: hasFull) ?? f.tempDownloadUrl;
        if (f.isVideo) {
          return url == null
              ? _UnavailablePage(file: f)
              : LeafVideoPage(
                  key: ValueKey('vid_$i'),
                  createAdapter: () => MediaKitAdapter(
                    initialVolume: AppState.instance.getPlayerVolume(),
                    onVolumeChanged: AppState.instance.setPlayerVolume,
                  ),
                  url: url,
                  headers: const {
                    'Referer': ApiConstants.referer,
                    'User-Agent': ApiConstants.userAgent,
                  },
                );
        }
        return _FullscreenPage(
          key: ValueKey('img_$i'),
          file: f,
          service: service,
          hasFull: hasFull,
          creatorId: creatorId,
          postId: postId,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // openArchive() — archive images (lazy-loaded from disk)
  // ---------------------------------------------------------------------------

  /// Open the fullscreen multi-image viewer for archive-sourced images.
  static void openArchive(
    BuildContext context, {
    required ArchiveService archiveService,
    required String localPath,
    required List<String> entries,
    required int initialIndex,
    String? archiveName,
  }) {
    final dottedVideo = FileHelpers.dottedVideoExtensions;
    final mediaEntries = entries.where((e) {
      final ext = p.extension(e).toLowerCase();
      return FileHelpers.dottedImageExtensions.contains(ext) || dottedVideo.contains(ext);
    }).toList();
    if (mediaEntries.isEmpty) return;

    _openCore(
      context,
      itemCount: mediaEntries.length,
      initialIndex: initialIndex.clamp(0, mediaEntries.length - 1),
      subtitle: archiveName,
      pageBuilder: (context, i) {
        final entryPath = mediaEntries[i];
        final ext = p.extension(entryPath).toLowerCase();
        if (dottedVideo.contains(ext)) {
          return _ArchiveVideoPage(
            key: ValueKey('archive_vid_$i'),
            archiveService: archiveService,
            localPath: localPath,
            entryPath: entryPath,
            tempDir: p.dirname(localPath),
          );
        }
        return _ArchivePage(key: ValueKey('archive_$i'), archiveService: archiveService, localPath: localPath, entryPath: entryPath);
      },
    );
  }

  @override
  Widget build(BuildContext context) => throw UnimplementedError('Use FullscreenImageViewerScreen.open() / openArchive() instead');
}

// =============================================================================
// FullscreenPageViewInner — the shared route page
// =============================================================================

class _FullscreenPageViewInner extends StatefulWidget {
  final int itemCount;
  final Signal<int> currentIndex;
  final String? subtitle;
  final PageController pageController;
  final FocusNode focusNode;
  final void Function(int) onGoTo;
  final Widget Function(BuildContext, int) pageBuilder;

  const _FullscreenPageViewInner({
    required this.itemCount,
    required this.currentIndex,
    required this.subtitle,
    required this.pageController,
    required this.focusNode,
    required this.onGoTo,
    required this.pageBuilder,
  });

  @override
  State<_FullscreenPageViewInner> createState() => _FullscreenPageViewInnerState();
}

class _FullscreenPageViewInnerState extends State<_FullscreenPageViewInner> {
  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
          switch (event.logicalKey) {
            case LogicalKeyboardKey.arrowLeft:
              widget.onGoTo(widget.currentIndex.value - 1);
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowRight:
              widget.onGoTo(widget.currentIndex.value + 1);
              return KeyEventResult.handled;
            case LogicalKeyboardKey.escape:
              Navigator.of(context).pop();
              return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ---- Pager (gestures, zoom, dismiss, edge-release) ----
            LeafViewer(
              pageCount: widget.itemCount,
              pageController: widget.pageController,
              onPageChanged: (index) => widget.currentIndex.value = index,
              onDismissed: () => Navigator.of(context).pop(),
              onTapOutside: () => Navigator.of(context).pop(),
              backgroundBuilder: (context, progress) => Container(color: Colors.black.withValues(alpha: 0.87 * (1 - progress))),
              // The app has its own chrome below (arrows, counter, keyboard).
              controlsBuilder: (context, controls) => const SizedBox.shrink(),
              pageBuilder: widget.pageBuilder,
            ),

            // ---- Nav arrows ----
            if (widget.itemCount > 1) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SignalBuilder(
                    builder: (context) => _NavArrow(
                      icon: Icons.chevron_left,
                      visible: widget.currentIndex.value > 0,
                      onTap: () => widget.onGoTo(widget.currentIndex.value - 1),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SignalBuilder(
                    builder: (context) => _NavArrow(
                      icon: Icons.chevron_right,
                      visible: widget.currentIndex.value < widget.itemCount - 1,
                      onTap: () => widget.onGoTo(widget.currentIndex.value + 1),
                    ),
                  ),
                ),
              ),
            ],

            // ---- Page counter overlay ----
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: SignalBuilder(
                builder: (context) {
                  final label = widget.subtitle != null ? '${widget.subtitle} — ' : '';
                  return Text(
                    '$label${widget.currentIndex.value + 1} / ${widget.itemCount}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      decoration: TextDecoration.none,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _FullscreenPage — a single page for API-sourced images
// =============================================================================

class _FullscreenPage extends StatefulWidget {
  final FileInfo file;
  final String service;
  final bool hasFull;
  final String creatorId;
  final String postId;

  const _FullscreenPage({
    super.key,
    required this.file,
    required this.service,
    required this.hasFull,
    required this.creatorId,
    required this.postId,
  });

  @override
  State<_FullscreenPage> createState() => _FullscreenPageState();
}

class _FullscreenPageState extends State<_FullscreenPage> {
  /// Cached image provider — same instance across rebuilds prevents
  /// re-resolving the image on every build.
  ImageProvider? _imageProvider;

  String? _url;
  String? _thumbUrl;

  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  ImageInfo? _imageInfo;

  File? _thumbnailFile;
  bool _hasLoaded = false;
  bool _fadeCompleted = false;
  bool _failed = false;
  bool _refreshedOnce = false;
  bool _refreshing = false;
  int? _tooLargeBytes;
  double? _aspectRatio;
  bool _resolved = false;

  // Reactive progress signals — read in SignalBuilder inside the skeleton so
  // progress text / border repaint live-update without a full state rebuild.
  final _loadedBytes = signal<int>(0);
  final _totalBytes = signal<int>(0);

  @override
  void initState() {
    super.initState();
    _thumbUrl = widget.file.thumbnailUrl;
    _url = widget.file.downloadUrl(hasFull: widget.hasFull);
    final url = _url;
    if (url != null) {
      _imageProvider = KemonoImageProvider(url, creatorId: widget.creatorId, postId: widget.postId);
    }
    _loadThumbnail();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_resolved) {
      _resolved = true;
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _detachStream();
    _imageInfo?.dispose();
    super.dispose();
  }

  void _detachStream() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  void _resolveImage() {
    final provider = _imageProvider;
    if (provider == null) return;
    final config = createLocalImageConfiguration(context);
    final stream = provider.resolve(config);
    final listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        if (!mounted) return;
        _imageInfo = imageInfo;
        _aspectRatio = imageInfo.image.width / imageInfo.image.height;
        _hasLoaded = true;
        setState(() {});
      },
      onChunk: (chunk) {
        _loadedBytes.value = chunk.cumulativeBytesLoaded;
        if (chunk.expectedTotalBytes != null && chunk.expectedTotalBytes! > 0) {
          _totalBytes.value = chunk.expectedTotalBytes!;
        }
      },
      onError: _onImageError,
    );
    stream.addListener(listener);
    _imageStream = stream;
    _imageListener = listener;
  }

  void _onImageError(Object exception, StackTrace? stackTrace) {
    debugPrint('Fullscreen image error for $_url:\n$exception');
    if (!mounted) return;

    if (exception is FileTooLargeException) {
      setState(() {
        _tooLargeBytes = exception.bytes;
        _failed = false;
      });
      return;
    }

    // A temporary URL expired or lost its signature: re-fetch the post once and
    // retry with the fresh URL.
    if (exception is PawchiveFileException && exception.isExpiredSignature && !_refreshedOnce) {
      _refreshUrls();
      return;
    }

    setState(() => _failed = true);
  }

  Future<void> _refreshUrls() async {
    if (_refreshing) return;
    _refreshing = true;
    _refreshedOnce = true;
    try {
      final post = await PawchiveClient.instance.getSinglePost(
        service: widget.service,
        creatorId: widget.creatorId,
        postId: widget.postId,
      );

      FileInfo? match;
      for (final f in post.allFiles) {
        if (f.path != null && f.path == widget.file.path) {
          match = f;
          break;
        }
      }
      final fresh = match ?? widget.file;
      final url = fresh.downloadUrl(hasFull: post.hasFull);
      if (url == null) {
        if (mounted) setState(() => _failed = true);
        return;
      }

      _detachStream();
      if (!mounted) return;
      setState(() {
        _url = url;
        _imageProvider = KemonoImageProvider(url, creatorId: widget.creatorId, postId: widget.postId);
        _failed = false;
        _imageInfo?.dispose();
        _imageInfo = null;
        _hasLoaded = false;
        _fadeCompleted = false;
      });
      _resolveImage();
    } catch (e, st) {
      debugPrint('Fullscreen image URL refresh failed: $e\n$st');
      if (mounted) setState(() => _failed = true);
    } finally {
      _refreshing = false;
    }
  }

  void _retry() {
    final url = _url;
    final provider = _imageProvider;
    if (url == null || provider == null) return;
    _detachStream();
    PaintingBinding.instance.imageCache.evict(provider);
    ImageCacheService.instance.removeFile(url);
    setState(() {
      _failed = false;
      _tooLargeBytes = null;
      _refreshedOnce = false;
      _imageInfo?.dispose();
      _imageInfo = null;
      _hasLoaded = false;
      _fadeCompleted = false;
    });
    _resolveImage();
  }

  void _allowLarge() {
    final url = _url;
    if (url == null) return;
    FileSizeGate.allow(url);
    _retry();
  }

  Future<void> _loadThumbnail() async {
    final thumb = _thumbUrl;
    if (thumb == null) return;
    try {
      final fileInfo = await ImageCacheService.instance.cache.getFileFromCache(thumb);
      if (fileInfo != null && mounted) {
        setState(() => _thumbnailFile = fileInfo.file);
      }
    } catch (e, st) {
      debugPrint('FullscreenImageViewer: thumbnail load failed: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_url == null) {
      return _PreviewPane(thumbUrl: _thumbUrl, label: 'Original not available');
    }

    if (_tooLargeBytes != null) {
      return _PreviewPane(
        thumbUrl: _thumbUrl,
        label: 'Load full · ${ImageMetaStore.formatBytes(_tooLargeBytes!)}',
        onAction: _allowLarge,
        actionIcon: Icons.download_outlined,
      );
    }

    if (_failed) {
      return _PreviewPane(
        thumbUrl: _thumbUrl,
        label: 'Preview · retry',
        onAction: _retry,
        actionIcon: Icons.refresh,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final vh = constraints.maxHeight;

        // Subscribe to metaReady for reactive aspect-ratio changes.
        ImageMetaStore.instance.metaReady.value;
        final meta = _thumbUrl == null ? null : ImageMetaStore.instance.lookup(_thumbUrl!);
        final ratio = meta?.aspectRatio ?? _aspectRatio ?? 1.0;
        final (double iw, double ih) = FullscreenImageViewerScreen._containSize(vw, vh, ratio);

        return SizedBox(
          width: vw,
          height: vh,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ---- Skeleton (always behind the image) ----
              if (!_fadeCompleted)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: SizedBox(width: iw, height: ih, child: _buildSkeletonContent(iw, ih)),
                  ),
                ),

              // ---- Zoomable image (fades in over skeleton) ----
              AnimatedOpacity(
                opacity: _hasLoaded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                onEnd: () {
                  if (_hasLoaded && mounted) {
                    setState(() => _fadeCompleted = true);
                  }
                },
                child: _imageInfo != null
                    ? Center(
                        child: LeafZoomable(
                          childSize: Size(iw, ih),
                          originalSize: Size(_imageInfo!.image.width.toDouble(), _imageInfo!.image.height.toDouble()),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: SizedBox(
                              width: iw,
                              height: ih,
                              child: RawImage(image: _imageInfo!.image, fit: BoxFit.contain, isAntiAlias: true),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeletonContent(double w, double h) {
    final shortest = math.min(w, h);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Background: cached thumbnail while full-res loads.
        if (_thumbnailFile != null)
          Image.file(_thumbnailFile!, width: w, height: h, fit: BoxFit.contain)
        else
          Container(
            width: w,
            height: h,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03)),
          ),

        // Dark overlay when using blurred thumbnail for readability.
        if (_thumbnailFile != null) Container(width: w, height: h, color: Colors.black.withValues(alpha: 0.3)),

        // Clockwise border progress (reactive via signal).
        SignalBuilder(
          builder: (context) {
            final loaded = _loadedBytes();
            final total = _totalBytes();
            final progress = total > 0 ? (loaded / total).clamp(0.0, 1.0) : 0.0;

            return CustomPaint(
              size: Size(w, h),
              painter: ClockwiseBorderPainter(progress: progress),
            );
          },
        ),

        // Progress label: file size or percentage (reactive via signal).
        Positioned(
          top: shortest * 0.06,
          child: SignalBuilder(
            builder: (context) {
              final loaded = _loadedBytes();
              final total = _totalBytes();
              final label = total > 0 ? '${ImageMetaStore.formatBytes(loaded)} / ${ImageMetaStore.formatBytes(total)}' : '0%';
              return Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: shortest * 0.04,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// _PreviewPane — thumbnail fallback with an out-of-the-way action pill
// =============================================================================

class _PreviewPane extends StatefulWidget {
  final String? thumbUrl;
  final String label;
  final VoidCallback? onAction;
  final IconData actionIcon;

  const _PreviewPane({
    required this.thumbUrl,
    required this.label,
    this.onAction,
    this.actionIcon = Icons.refresh,
  });

  @override
  State<_PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<_PreviewPane> {
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  bool _resolved = false;
  double _ratio = 1;

  @override
  void initState() {
    super.initState();
    final thumb = widget.thumbUrl;
    if (thumb != null) {
      _provider = KemonoImageProvider(thumb);
      _ratio = ImageMetaStore.instance.lookup(thumb)?.aspectRatio ?? 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    final provider = _provider;
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _info = info;
          final r = info.image.width / info.image.height;
          if (r.isFinite && r > 0) _ratio = r;
        });
      },
      onError: (e, _) => debugPrint('PreviewPane thumbnail failed for ${widget.thumbUrl}: $e'),
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final vh = constraints.maxHeight;
        final (double iw, double ih) = FullscreenImageViewerScreen._containSize(vw, vh, _ratio);
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: SizedBox(
                  width: iw,
                  height: ih,
                  child: _info == null
                      ? Container(color: Colors.white.withValues(alpha: 0.03))
                      : RawImage(image: _info!.image, fit: BoxFit.contain, isAntiAlias: true),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: widget.onAction,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(widget.onAction == null ? 14 : 12, 8, 14, 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onAction != null) ...[
                            Icon(widget.actionIcon, size: 16, color: Colors.white70),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UnavailablePage extends StatelessWidget {
  final FileInfo file;

  const _UnavailablePage({required this.file});

  @override
  Widget build(BuildContext context) => _PreviewPane(
        thumbUrl: file.thumbnailUrl,
        label: 'Original not available',
      );
}

// =============================================================================
// _ArchivePage — a single page for archive-sourced images
// =============================================================================

class _ArchivePage extends StatefulWidget {
  final ArchiveService archiveService;
  final String localPath;
  final String entryPath;

  const _ArchivePage({super.key, required this.archiveService, required this.localPath, required this.entryPath});

  @override
  State<_ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<_ArchivePage> {
  Uint8List? _data;
  bool _errored = false;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.archiveService.readEntry(widget.localPath, widget.entryPath);
      if (!mounted) return;

      // Pre-decode first frame to get dimensions for the contained size and
      // the 1:1 double-tap step.
      Size? size;
      try {
        final codec = await instantiateImageCodec(data);
        final frameInfo = await codec.getNextFrame();
        final img = frameInfo.image;
        size = Size(img.width.toDouble(), img.height.toDouble());
        img.dispose();
        codec.dispose();
      } catch (e, st) {
        debugPrint('ArchivePage: codec decode failed for ${widget.entryPath}: $e\n$st');
        size = null;
      }

      setState(() {
        _data = data;
        _imageSize = size;
      });
    } catch (e, st) {
      debugPrint('ArchivePage load error for ${widget.entryPath}:\n$e\n$st');
      if (mounted) setState(() => _errored = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errored) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white.withValues(alpha: 0.4), size: 48),
            Text(p.basename(widget.entryPath), style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14)),
          ],
        ),
      );
    }

    if (_data == null) {
      return Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final vh = constraints.maxHeight;
        final ratio = _imageSize != null ? _imageSize!.width / _imageSize!.height : 1.0;
        final (double iw, double ih) = FullscreenImageViewerScreen._containSize(vw, vh, ratio);

        return Center(
          child: LeafZoomable(
            childSize: Size(iw, ih),
            originalSize: _imageSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: SizedBox(
                width: iw,
                height: ih,
                child: Image.memory(_data!, fit: BoxFit.contain, filterQuality: FilterQuality.high),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// _ArchiveVideoPage — a single page for archive-sourced videos
// =============================================================================

class _ArchiveVideoPage extends StatefulWidget {
  final ArchiveService archiveService;
  final String localPath;
  final String entryPath;
  final String tempDir;

  const _ArchiveVideoPage({
    super.key,
    required this.archiveService,
    required this.localPath,
    required this.entryPath,
    required this.tempDir,
  });

  @override
  State<_ArchiveVideoPage> createState() => _ArchiveVideoPageState();
}

class _ArchiveVideoPageState extends State<_ArchiveVideoPage> {
  late final Player _player;
  late final VideoController _videoController;

  String? _extractedPath;
  bool _extracting = true;
  bool _errored = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _extractAndPlay();
    _setupListeners();
  }

  Future<void> _extractAndPlay() async {
    try {
      final path = await widget.archiveService.extractEntryToFile(widget.localPath, widget.entryPath, widget.tempDir);
      if (!mounted) return;
      _extractedPath = path;
      _extracting = false;
      setState(() {});
      _player.open(Media('file://${Uri.encodeFull(path.replaceAll('\\', '/'))}'));
    } catch (e, st) {
      debugPrint('ArchiveVideoPage extract error: $e\n$st');
      if (mounted) setState(() => _errored = true);
    }
  }

  void _setupListeners() {
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    if (_extractedPath != null) {
      try {
        File(_extractedPath!).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errored) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(Icons.videocam_off_outlined, color: Colors.white.withValues(alpha: 0.4), size: 48),
            Text(p.basename(widget.entryPath), style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14)),
          ],
        ),
      );
    }

    if (_extracting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white.withValues(alpha: 0.6))),
            Text('Extracting video…', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _togglePlayPause,
      child: Video(alignment: .center, fit: .contain, fill: Colors.transparent, controller: _videoController),
    );
  }
}

// =============================================================================
// Reusable widgets
// =============================================================================

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool visible;
  final VoidCallback onTap;

  const _NavArrow({required this.icon, required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: GestureDetector(
        onTap: visible ? onTap : null,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class ClockwiseBorderPainter extends CustomPainter {
  final double progress;

  ClockwiseBorderPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const borderWidth = 2.0;
    const trackColor = Color(0x33FFFFFF);
    const progressColor = Color(0xCCFFFFFF);

    final rect = Rect.fromLTWH(borderWidth / 2, borderWidth / 2, size.width - borderWidth, size.height - borderWidth);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(15));

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawRRect(rrect, trackPaint);

    if (progress <= 0) return;

    final path = _clockwisePath(rrect);
    final metrics = path.computeMetrics().first;
    final totalLen = metrics.length;
    final progressLen = totalLen * progress;

    final progressPath = metrics.extractPath(0, progressLen);
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(progressPath, progressPaint);
  }

  Path _clockwisePath(RRect rrect) {
    final path = Path();
    final rect = rrect.outerRect;
    final tl = rrect.tlRadius.x;

    path.moveTo(rect.left + tl, rect.top);
    path.lineTo(rect.right - rrect.trRadius.x, rect.top);
    path.arcToPoint(Offset(rect.right, rect.top + rrect.trRadius.y), radius: rrect.trRadius);
    path.lineTo(rect.right, rect.bottom - rrect.brRadius.y);
    path.arcToPoint(Offset(rect.right - rrect.brRadius.x, rect.bottom), radius: rrect.brRadius);
    path.lineTo(rect.left + rrect.blRadius.x, rect.bottom);
    path.arcToPoint(Offset(rect.left, rect.bottom - rrect.blRadius.y), radius: rrect.blRadius);
    path.lineTo(rect.left, rect.top + tl);
    path.arcToPoint(Offset(rect.left + tl, rect.top), radius: rrect.tlRadius);
    path.close();

    return path;
  }

  @override
  bool shouldRepaint(ClockwiseBorderPainter old) => old.progress != progress;
}
