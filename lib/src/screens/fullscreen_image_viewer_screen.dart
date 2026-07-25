import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:custom_interactive_viewer/custom_interactive_viewer.dart';
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

/// Fullscreen image viewer with per-page [InteractiveViewer] and
/// PageView–InteractiveViewer gesture conflict resolution.
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
    // Avoid division by zero.
    if (aspectRatio <= 0) aspectRatio = 1.0;
    if (containerW / containerH > aspectRatio) {
      // Container is wider → image constrained by height.
      return (containerH * aspectRatio, containerH);
    } else {
      // Container is taller or equal → image constrained by width.
      return (containerW, containerW / aspectRatio);
    }
  }

  // ---------------------------------------------------------------------------
  // Shared core
  // ---------------------------------------------------------------------------

  /// Push a fullscreen PageView route.
  ///
  /// [itemCount] and [pageBuilder] define the pages.  [subtitle] is an optional
  /// label prefixed to the "N / M" counter in the bottom overlay (e.g.
  /// "archive.zip — 3 / 24").
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

    final thumbBase = _thumbBase;
    final fullBase = _fullBase;

    _openCore(
      context,
      itemCount: imageFiles.length,
      initialIndex: adjustedIndex,
      pageBuilder: (context, i) {
        final f = imageFiles[i];
        final fullUrl = '$fullBase${f.path}${f.name != null ? '?f=${Uri.encodeComponent(f.name!)}' : ''}';
        final thumbUrl = '$thumbBase${f.path}';
        return _FullscreenPage(key: ValueKey('img_$i'), url: fullUrl, thumbUrl: thumbUrl, creatorId: creatorId, postId: postId);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // openArchive() — archive images (lazy-loaded from disk)
  // ---------------------------------------------------------------------------

  /// Open the fullscreen multi-image viewer for archive-sourced images.
  ///
  /// Each page lazy-loads its image via [archiveService.readEntry] so no
  /// upfront extraction is needed.
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
// FullscreenPageViewInner — the shared route page (extracted so the mixin
// doesn't fight with StatelessWidget).
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
// ZoomableImageMixin — shared InteractiveViewer gesture handling
// =============================================================================

mixin ZoomableImageMixin<T extends StatefulWidget> on State<T> {
  final TransformationController _transformController = TransformationController();
  bool _isZoomed = false;

  void initZoomable() {
    _transformController.addListener(_onTransformChanged);
  }

  void disposeZoomable() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
  }

  void resetZoom() {
    _transformController.value = Matrix4.identity();
    _isZoomed = false;
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  Widget wrapZoomable(Widget imageWidget) {
    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.5,
      maxScale: 5.0,
      boundaryMargin: EdgeInsets.zero,
      child: Center(child: imageWidget),
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

class _FullscreenPageState extends State<_FullscreenPage> with ZoomableImageMixin, SingleTickerProviderStateMixin {
  double _progress = 0;
  int _loadedBytes = 0;
  int _totalBytes = 0;
  ImageStream? _imageStream;
  ImageStreamListener? _listener;
  ImageInfo? _imageInfo;
  bool _errored = false;
  File? _thumbnailFile;
  AnimationController? _fadeController;

  @override
  void initState() {
    super.initState();
    initZoomable();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _loadThumbnail();
    _load();
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

  void _load() {
    final provider = KemonoImageProvider(widget.url, creatorId: widget.creatorId, postId: widget.postId);
    final stream = provider.resolve(const ImageConfiguration());
    _imageStream = stream;
    _listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (mounted) {
          setState(() {
            _imageInfo = info;
            _errored = false;
          });
          _fadeController?.forward();
        }
      },
      onChunk: (chunk) {
        if (mounted) {
          setState(() {
            _loadedBytes = chunk.cumulativeBytesLoaded;
            if (chunk.expectedTotalBytes != null && chunk.expectedTotalBytes! > 0) {
              _totalBytes = chunk.expectedTotalBytes!;
              _progress = (_loadedBytes / _totalBytes).clamp(0.0, 1.0);
            }
          });
        }
      },
      onError: (error, stack) {
        if (mounted) {
          setState(() => _errored = true);
          debugPrint('FullscreenImageViewer error for ${widget.url}:\n$error\n$stack');
        }
      },
    );
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    disposeZoomable();
    _imageStream?.removeListener(_listener!);
    _imageInfo?.dispose();
    _fadeController?.dispose();
    super.dispose();
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
        final containerW = constraints.maxWidth;
        final containerH = constraints.maxHeight;

        if (_imageInfo != null) {
          final img = _imageInfo!.image;
          final ratio = img.width / img.height;
          final (w, h) = FullscreenImageViewerScreen._containSize(containerW, containerH, ratio);

          final imageWidget = ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              width: w,
              height: h,
              child: RawImage(image: img, fit: BoxFit.contain),
            ),
          );

          // Fade in over skeleton if animation hasn't completed.
          if (_fadeController != null && _fadeController!.value < 1.0) {
            return wrapZoomable(
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: SizedBox(width: w, height: h, child: _buildSkeletonContent(w, h)),
                  ),
                  FadeTransition(opacity: _fadeController!, child: imageWidget),
                ],
              ),
            );
          }

          return wrapZoomable(imageWidget);
        }

        // Loading — reactive skeleton that resizes when metadata arrives.
        return SignalBuilder(
          builder: (context) {
            // Subscribe to metaReady for reactive aspect-ratio updates.
            ImageMetaStore.instance.metaReady.value;
            final meta = ImageMetaStore.instance.lookup(widget.thumbUrl);
            final ratio = meta?.aspectRatio;

            if (ratio != null) {
              final (w, h) = FullscreenImageViewerScreen._containSize(containerW, containerH, ratio);
              return Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: SizedBox(width: w, height: h, child: _buildSkeletonContent(w, h)),
                ),
              );
            }

            // No metadata yet — skeleton fills available space.
            return Center(
              child: ClipRRect(borderRadius: BorderRadius.circular(15), child: _buildSkeletonContent(containerW, containerH)),
            );
          },
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
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(15)),
          ),

        // Dark overlay when using blurred thumbnail for readability.
        if (_thumbnailFile != null) Container(width: w, height: h, color: Colors.black.withValues(alpha: 0.3)),

        // Clockwise border progress.
        CustomPaint(
          size: Size(w, h),
          painter: _ClockwiseBorderPainter(progress: _progress),
        ),

        // Progress label: file size or percentage.
        // Centered in the skeleton area to avoid overlap with the page
        // counter overlay at the bottom of the screen.
        Positioned(
          top: shortest * 0.06,
          child: Text(
            _buildProgressLabel(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: shortest * 0.04,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  String _buildProgressLabel() {
    if (_totalBytes > 0) {
      return '${ImageMetaStore.formatBytes(_loadedBytes)} / ${ImageMetaStore.formatBytes(_totalBytes)}';
    }
    return '${(_progress * 100).toInt()}%';
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

class _ArchivePageState extends State<_ArchivePage> with ZoomableImageMixin {
  Uint8List? _data;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    initZoomable();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.archiveService.readEntry(widget.localPath, widget.entryPath);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      debugPrint('ArchivePage load error for ${widget.entryPath}:\n$e');
      if (mounted) setState(() => _errored = true);
    }
  }

  @override
  void dispose() {
    disposeZoomable();
    super.dispose();
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

    if (_data != null) {
      return wrapZoomable(
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.memory(_data!, fit: BoxFit.contain),
        ),
      );
    }

    return Center(
      child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white.withValues(alpha: 0.6))),
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
