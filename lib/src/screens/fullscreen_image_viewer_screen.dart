import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, instantiateImageCodec;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/archive/archive_service.dart';
import 'package:kemono_browser_project/src/cache/image_cache_service.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';
import 'package:kemono_browser_project/src/cache/kemono_image_provider.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';

// =============================================================================
// FullscreenImageViewerScreen — entry points
// =============================================================================

/// Fullscreen image viewer with per-page custom zoom/pan via
/// [Listener] (mouse wheel) + [GestureDetector] (drag/pinch) +
/// [Transform] (visual zoom) + [ClipRRect] (image-only rounded corners).
///
/// Both [open] and [openArchive] delegate to [FullscreenPageViewInner] so
/// they share the same dark-overlay chrome (nav arrows, keyboard nav,
/// tap-to-dismiss, page counter).
class FullscreenImageViewerScreen extends StatelessWidget {
  const FullscreenImageViewerScreen({super.key});

  static const _fullBase = 'https://file.pawchive.pw/data';
  static const _thumbBase = 'https://img.pawchive.pw/thumbnail/data';
  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'};

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
            barrierColor: Colors.black87,
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

    final imageFiles = files.where((f) {
      final ext = f.name?.split('.').last.toLowerCase() ?? '';
      return _imageExts.contains(ext);
    }).toList();
    if (imageFiles.isEmpty) return;

    final imageIndex = imageFiles.indexOf(files[index]);
    final adjustedIndex = imageIndex >= 0 ? imageIndex : 0;

    _openCore(
      context,
      itemCount: imageFiles.length,
      initialIndex: adjustedIndex,
      pageBuilder: (context, i) {
        final f = imageFiles[i];
        final fullUrl = '$_fullBase${f.path}${f.name != null ? '?f=${Uri.encodeComponent(f.name!)}' : ''}';
        final thumbUrl = '$_thumbBase${f.path}';
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
    final imageEntries = entries.where((e) {
      final ext = p.extension(e).toLowerCase();
      if (ext.startsWith('.')) return _imageExts.contains(ext.substring(1));
      return _imageExts.contains(ext);
    }).toList();
    if (imageEntries.isEmpty) return;

    _openCore(
      context,
      itemCount: imageEntries.length,
      initialIndex: initialIndex.clamp(0, imageEntries.length - 1),
      subtitle: archiveName,
      pageBuilder: (context, i) {
        final entryPath = imageEntries[i];
        return _ArchivePage(key: ValueKey('archive_$i'), archiveService: archiveService, localPath: localPath, entryPath: entryPath);
      },
    );
  }

  @override
  Widget build(BuildContext context) => throw UnimplementedError('Use FullscreenImageViewerScreen.open() / openArchive() instead');
}

// =============================================================================
// Zoomable image mixin — shared zoom/pan/clamp logic
// =============================================================================

/// Mixin that provides full-screen zoom/pan/clamp for any page widget.
///
/// The state's build method should include a [Listener] for mouse wheel,
/// a [GestureDetector] for drag/pinch, and use [buildZoomTransform] in a
/// [Transform] widget.  A [ClipRRect] wrapping the actual image (inside
/// the gesture layer) provides rounded corners at the image bounds only.
mixin _ZoomableMixin<T extends StatefulWidget> on State<T> {
  double _zoomScale = 1.0;
  Offset _zoomOffset = Offset.zero;
  double _zoomStartScale = 1.0;
  Offset _zoomStartOffset = Offset.zero;

  /// Build the transform matrix for the image.
  ///
  /// [Center] already places the image at the viewport centre, so the
  /// matrix only handles zoom and pan — no centering translation.
  Matrix4 buildZoomTransform(double vw, double vh, double iw, double ih) {
    return Matrix4.identity()
      ..setEntry(0, 3, _zoomOffset.dx)
      ..setEntry(1, 3, _zoomOffset.dy)
      ..setEntry(0, 0, _zoomScale)
      ..setEntry(1, 1, _zoomScale);
  }

  void zoomOnScaleStart(ScaleStartDetails details) {
    _zoomStartScale = _zoomScale;
    _zoomStartOffset = _zoomOffset;
  }

  /// Handle mouse‑wheel scroll event (zoom at cursor).
  void zoomOnScroll(double scrollDy, Offset cursorPos, Size viewport, double iw, double ih) {
    final oldScale = _zoomScale;
    final newScale = (_zoomScale * (1 - scrollDy * 0.001)).clamp(1.0, 5.0);
    if (newScale == oldScale) return;
    final vpc = Offset(viewport.width / 2, viewport.height / 2);
    _zoomOffset = (cursorPos - vpc) + (_zoomOffset - (cursorPos - vpc)) * (newScale / oldScale);
    _zoomScale = newScale;
    _zoomClampPosition(viewport, iw, ih);
  }

  /// Handle [ScaleUpdateDetails] — drag (1 pointer) or pinch (2+ pointers).
  void zoomOnScaleUpdate(ScaleUpdateDetails details, Size viewport, double iw, double ih) {
    if (details.pointerCount <= 1) {
      _zoomOffset += details.focalPointDelta;
    } else {
      final newScale = (_zoomStartScale * details.scale).clamp(1.0, 5.0);
      final vpc = Offset(viewport.width / 2, viewport.height / 2);
      final focal = details.localFocalPoint;
      _zoomOffset = (focal - vpc) + (_zoomStartOffset - (focal - vpc)) * (newScale / _zoomStartScale);
      _zoomScale = newScale;
    }
    _zoomClampPosition(viewport, iw, ih);
  }

  /// Handle double‑tap: toggle between 1.0× and 2.5× at the tap point.
  void zoomOnDoubleTapDown(Offset tapPos, Size viewport, double iw, double ih) {
    if (_zoomScale > 1.0 + 0.01) {
      _zoomScale = 1.0;
      _zoomOffset = Offset.zero;
    } else {
      const targetScale = 2.5;
      final vpc = Offset(viewport.width / 2, viewport.height / 2);
      _zoomOffset = (tapPos - vpc) + (_zoomOffset - (tapPos - vpc)) * (targetScale / _zoomScale);
      _zoomScale = targetScale;
    }
    _zoomClampPosition(viewport, iw, ih);
  }

  /// Clamp [zoomOffset] so the image stays within the viewport.
  void _zoomClampPosition(Size viewport, double iw, double ih) {
    final vpc = Offset(viewport.width / 2, viewport.height / 2);
    final imgCenter = vpc + _zoomOffset;
    final halfW = iw * _zoomScale / 2;
    final halfH = ih * _zoomScale / 2;

    final left = imgCenter.dx - halfW;
    final right = imgCenter.dx + halfW;
    final top = imgCenter.dy - halfH;
    final bottom = imgCenter.dy + halfH;

    double dx = _zoomOffset.dx;
    double dy = _zoomOffset.dy;

    // Horizontal clamp
    if (iw * _zoomScale <= viewport.width) {
      dx = 0;
    } else {
      if (left > 0) dx -= left;
      if (right < viewport.width) dx += viewport.width - right;
    }

    // Vertical clamp
    if (ih * _zoomScale <= viewport.height) {
      dy = 0;
    } else {
      if (top > 0) dy -= top;
      if (bottom < viewport.height) dy += viewport.height - bottom;
    }

    _zoomOffset = Offset(dx, dy);
  }
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
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.translucent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ---- PageView ----
              SignalBuilder(
                builder: (context) {
                  return PageView.builder(
                    controller: widget.pageController,
                    itemCount: widget.itemCount,
                    onPageChanged: (i) => widget.currentIndex.value = i,
                    itemBuilder: widget.pageBuilder,
                  );
                },
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

class _FullscreenPageState extends State<_FullscreenPage> with _ZoomableMixin<_FullscreenPage> {
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

  @override
  void dispose() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    try {
      final fileInfo = await ImageCacheService.instance.cache.getFileFromCache(widget.thumbUrl);
      if (fileInfo != null && mounted) {
        setState(() => _thumbnailFile = fileInfo.file);
      }
    } catch (_) {
      // Non-critical — skeleton appears without blur.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errored) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white.withValues(alpha: 0.4), size: 48),
            const SizedBox(height: 8),
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

	        return ClipRRect(
	          borderRadius: BorderRadius.circular(15),
	          child: SizedBox(
	            width: vw,
	            height: vh,
	            child: Listener(
	              onPointerSignal: (event) {
	                if (event is PointerScrollEvent && _imageInfo != null && _hasLoaded) {
	                  setState(() => zoomOnScroll(
	                    event.scrollDelta.dy,
	                    event.localPosition,
	                    Size(vw, vh),
	                    iw, ih,
	                  ));
	                }
	              },
	              child: GestureDetector(
	                onScaleStart: zoomOnScaleStart,
	                onScaleUpdate: (details) {
	                  if (_imageInfo != null) {
	                    setState(() => zoomOnScaleUpdate(details, Size(vw, vh), iw, ih));
	                  }
	                },
	                onDoubleTapDown: (details) {
	                  if (_imageInfo != null && _hasLoaded) {
	                    setState(() => zoomOnDoubleTapDown(details.localPosition, Size(vw, vh), iw, ih));
	                  }
	                },
	                child: Stack(
	                  fit: StackFit.expand,
	                  children: [
	                    // ---- Background fill ----
	                    Container(color: Colors.black),

	                    // ---- Skeleton (behind the image) ----
	                    if (!_fadeCompleted)
	                      Center(
	                        child: SizedBox(width: iw, height: ih, child: _buildSkeletonContent(iw, ih)),
	                      ),

	                    // ---- Zoomable image (fades in over skeleton) ----
	                    if (_imageInfo != null)
	                      AnimatedOpacity(
	                        opacity: _hasLoaded ? 1.0 : 0.0,
	                        duration: const Duration(milliseconds: 300),
	                        onEnd: () {
	                          if (_hasLoaded && mounted) {
	                            setState(() => _fadeCompleted = true);
	                          }
	                        },
	                        child: Center(
	                          child: Transform(
	                            transform: buildZoomTransform(vw, vh, iw, ih),
	                            alignment: Alignment.center,
	                            child: SizedBox(
	                              width: iw,
	                              height: ih,
	                              child: RawImage(
	                                image: _imageInfo!.image,
	                                fit: BoxFit.contain,
	                                isAntiAlias: true,
	                              ),
	                            ),
	                          ),
	                        ),
	                      ),
              ],
            ),
          ),
        ),
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
        // Background: blurred cached thumbnail or dark container.
        if (_thumbnailFile != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Image.file(_thumbnailFile!, width: w, height: h, fit: BoxFit.contain),
          )
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
              painter: _ClockwiseBorderPainter(progress: progress),
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
              final label = total > 0
                  ? '${ImageMetaStore.formatBytes(loaded)} / ${ImageMetaStore.formatBytes(total)}'
                  : '0%';
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

class _ArchivePageState extends State<_ArchivePage> with _ZoomableMixin<_ArchivePage> {
  Uint8List? _data;
  bool _errored = false;
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.archiveService.readEntry(widget.localPath, widget.entryPath);
      if (!mounted) return;

      // Pre-decode first frame to get aspect ratio for bounds clamping.
      double? ar;
      try {
        final codec = await instantiateImageCodec(data);
        final frameInfo = await codec.getNextFrame();
        final img = frameInfo.image;
        ar = img.width / img.height;
        img.dispose();
        codec.dispose();
      } catch (_) {
        // Fallback: use 1:1 ratio.
        ar = null;
      }

      setState(() {
        _data = data;
        _aspectRatio = ar;
      });
    } catch (e) {
      debugPrint('ArchivePage load error for ${widget.entryPath}:\n$e');
      if (mounted) setState(() => _errored = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errored) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white.withValues(alpha: 0.4), size: 48),
            const SizedBox(height: 8),
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
        final ratio = _aspectRatio ?? 1.0;
        final (double iw, double ih) = FullscreenImageViewerScreen._containSize(vw, vh, ratio);

	    return ClipRRect(
	      borderRadius: BorderRadius.circular(15),
	      child: SizedBox(
	        width: vw,
	        height: vh,
	        child: Listener(
	          onPointerSignal: (event) {
	            if (event is PointerScrollEvent) {
	              setState(() => zoomOnScroll(
	                event.scrollDelta.dy,
	                event.localPosition,
	                Size(vw, vh),
	                iw, ih,
	              ));
	            }
	          },
	          child: GestureDetector(
	            onScaleStart: zoomOnScaleStart,
	            onScaleUpdate: (details) {
	              setState(() => zoomOnScaleUpdate(details, Size(vw, vh), iw, ih));
	            },
	            onDoubleTapDown: (details) {
	              setState(() => zoomOnDoubleTapDown(details.localPosition, Size(vw, vh), iw, ih));
	            },
	            child: Stack(
	              fit: StackFit.expand,
	              children: [
	                // Black fill behind image.
	                Container(color: Colors.black),

	                // Zoomable image.
	                Center(
	                  child: Transform(
	                    transform: buildZoomTransform(vw, vh, iw, ih),
	                    alignment: Alignment.center,
	                    child: SizedBox(
	                      width: iw,
	                      height: ih,
	                      child: Image.memory(
	                        _data!,
	                        fit: BoxFit.contain,
	                        filterQuality: FilterQuality.high,
	                      ),
	                    ),
	                  ),
	                ),
		      ],
		    ),
		  ),
		),
	      ),
	    );
	  },
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

class _ClockwiseBorderPainter extends CustomPainter {
  final double progress;

  _ClockwiseBorderPainter({required this.progress});

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
  bool shouldRepaint(_ClockwiseBorderPainter old) => old.progress != progress;
}
