import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show instantiateImageCodec;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/archive/archive_service.dart';
import 'package:kemono_browser_project/src/cache/image_cache_service.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';
import 'package:kemono_browser_project/src/cache/kemono_image_provider.dart';
import 'package:kemono_browser_project/src/utils.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_flutter.dart';

// =============================================================================
// FullscreenImageViewerScreen — entry points
// =============================================================================

/// Fullscreen pager built on [LeafViewer] (see the `leaf_widgets` package for
/// the gesture/zoom/dismiss machinery).
///
/// Both [open] and [openArchive] delegate to [_FullscreenPageViewInner] so
/// they share the same dark-overlay chrome (nav arrows, keyboard nav, page
/// counter). Pages are plain content: zoomable images wrapped in
/// [LeafZoomable], videos as a bare media_kit surface.
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
  static void open(
    BuildContext context, {
    required List<FileInfo> files,
    required int index,
    required String creatorId,
    required String postId,
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
        final ext = (f.name ?? '').split('.').last.toLowerCase();
        final fullUrl = '${FileHelpers.fileDataBase}${f.path}${f.name != null ? '?f=${Uri.encodeComponent(f.name!)}' : ''}';
        if (FileHelpers.videoExtensions.contains(ext)) {
          return _VideoPage(key: ValueKey('vid_$i'), url: fullUrl, creatorId: creatorId, postId: postId);
        }
        final thumbUrl = '${FileHelpers.imgThumbBase}${f.path}';
        return _FullscreenPage(key: ValueKey('img_$i'), url: fullUrl, thumbUrl: thumbUrl, creatorId: creatorId, postId: postId);
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
      child: KeyboardListener(
        focusNode: widget.focusNode,
        onKeyEvent: (event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
          switch (event.logicalKey) {
            case LogicalKeyboardKey.arrowLeft:
              widget.onGoTo(widget.currentIndex.value - 1);
            case LogicalKeyboardKey.arrowRight:
              widget.onGoTo(widget.currentIndex.value + 1);
            case LogicalKeyboardKey.escape:
              Navigator.of(context).pop();
          }
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
              backgroundBuilder: (context, progress) =>
                  Container(color: Colors.black.withValues(alpha: 0.87 * (1 - progress))),
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
  final String url;
  final String thumbUrl;
  final String creatorId;
  final String postId;

  const _FullscreenPage({super.key, required this.url, required this.thumbUrl, required this.creatorId, required this.postId});

  @override
  State<_FullscreenPage> createState() => _FullscreenPageState();
}

class _FullscreenPageState extends State<_FullscreenPage> {
  /// Cached image provider — same instance across rebuilds prevents
  /// re-resolving the image on every build.
  late final ImageProvider _imageProvider;

  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  ImageInfo? _imageInfo;

  File? _thumbnailFile;
  bool _hasLoaded = false;
  bool _fadeCompleted = false;
  bool _errored = false;
  double? _aspectRatio;
  bool _resolved = false;

  // Reactive progress signals — read in SignalBuilder inside the skeleton so
  // progress text / border repaint live-update without a full state rebuild.
  final _loadedBytes = signal<int>(0);
  final _totalBytes = signal<int>(0);

  @override
  void initState() {
    super.initState();
    _imageProvider = KemonoImageProvider(widget.url, creatorId: widget.creatorId, postId: widget.postId);
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
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    super.dispose();
  }

  void _resolveImage() {
    final config = createLocalImageConfiguration(context);
    final stream = _imageProvider.resolve(config);
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
      onError: (exception, stackTrace) {
        debugPrint('Fullscreen image error for ${widget.url}:\n$exception');
        if (mounted) setState(() => _errored = true);
      },
    );
    stream.addListener(listener);
    _imageStream = stream;
    _imageListener = listener;
  }

  Future<void> _loadThumbnail() async {
    try {
      final fileInfo = await ImageCacheService.instance.cache.getFileFromCache(widget.thumbUrl);
      if (fileInfo != null && mounted) {
        setState(() => _thumbnailFile = fileInfo.file);
      }
    } catch (e, st) {
      debugPrint('FullscreenImageViewer: thumbnail load failed: $e\n$st');
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
            Text('Image unavailable', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final vh = constraints.maxHeight;

        // Subscribe to metaReady for reactive aspect-ratio changes.
        ImageMetaStore.instance.metaReady.value;
        final meta = ImageMetaStore.instance.lookup(widget.thumbUrl);
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
// _VideoPage — a single page for API-sourced videos
// =============================================================================

class _VideoPage extends StatefulWidget {
  final String url;
  final String creatorId;
  final String postId;

  const _VideoPage({super.key, required this.url, required this.creatorId, required this.postId});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final Player _player;
  late final VideoController _videoController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _openMedia();
    _setupListeners();
  }

  void _openMedia() {
    _player.open(
      Media(
        widget.url,
        httpHeaders: {
          'Referer': 'https://pawchive.pw/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ),
    );
  }

  void _setupListeners() {
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _togglePlayPause,
      child: Video(alignment: .center, fit: .contain, fill: Colors.transparent, controller: _videoController),
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
