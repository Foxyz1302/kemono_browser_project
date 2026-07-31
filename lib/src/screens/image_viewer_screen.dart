import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';
import 'package:kemono_browser_project/src/cache/kemono_image_provider.dart';
import 'package:kemono_browser_project/src/utils.dart';
import 'package:signals/signals_flutter.dart';

class MyImageViewerScreen extends StatelessWidget {
  final List<FileInfo> files;
  final int initialIndex;
  final String creatorId;
  final String postId;

  const MyImageViewerScreen({required this.files, required this.initialIndex, required this.creatorId, required this.postId, super.key});

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
      return {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'}.contains(ext);
    }).toList();

    final imageIndex = imageFiles.indexOf(files[index]);
    final adjustedIndex = imageIndex >= 0 ? imageIndex : 0;
    final pageController = PageController(initialPage: adjustedIndex);
    final focusNode = FocusNode();
    final loadedRatios = <int, double>{};

    double aspectRatioFor(int index) {
      final url = '${FileHelpers.imgThumbBase}${imageFiles[index].path}';
      final meta = ImageMetaStore.instance.lookup(url);
      if (meta != null) return meta.aspectRatio;
      return loadedRatios[index] ?? 1.0;
    }

    final currentIndex = signal(adjustedIndex);
    final currentAspectRatio = signal(aspectRatioFor(adjustedIndex));

    void goTo(int target) {
      if (target < 0 || target >= imageFiles.length) return;
      pageController.animateToPage(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => Material(
          type: MaterialType.transparency,
          child: KeyboardListener(
            focusNode: focusNode,
            onKeyEvent: (event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
              switch (event.logicalKey) {
                case LogicalKeyboardKey.arrowLeft:
                  goTo(currentIndex.value - 1);
                case LogicalKeyboardKey.arrowRight:
                  goTo(currentIndex.value + 1);
                case LogicalKeyboardKey.escape:
                  Navigator.of(context).pop();
              }
            },
            child: Stack(
              children: [
                Center(
                  child: SignalBuilder(
                    builder: (context) {
                      return AnimatedAspectRatio(
                        duration: const Duration(milliseconds: 200),
                        aspectRatio: currentAspectRatio.value,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          clipBehavior: Clip.antiAlias,
                          child: PageView.builder(
                            controller: pageController,
                            itemCount: imageFiles.length,
                            onPageChanged: (i) {
                              currentIndex.value = i;
                              currentAspectRatio.value = aspectRatioFor(i);
                            },
                            itemBuilder: (context, i) {
                              final f = imageFiles[i];
                              final fullUrl = '${FileHelpers.fileDataBase}${f.path}${f.name != null ? '?f=${Uri.encodeComponent(f.name!)}' : ''}';
                              final thumbUrl = '${FileHelpers.imgThumbBase}${f.path}';
                              return _ImageViewerPage(
                                url: fullUrl,
                                thumbUrl: thumbUrl,
                                creatorId: creatorId,
                                postId: postId,
                                onImageLoaded: (ratio) {
                                  loadedRatios[i] = ratio;
                                  if (currentIndex.value == i && currentAspectRatio.value != ratio) {
                                    currentAspectRatio.value = ratio;
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (imageFiles.length > 1) ...[
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: SignalBuilder(
                        builder: (context) => _NavArrow(
                          icon: Icons.chevron_left,
                          visible: currentIndex.value > 0,
                          onTap: () => goTo(currentIndex.value - 1),
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
                          visible: currentIndex.value < imageFiles.length - 1,
                          onTap: () => goTo(currentIndex.value + 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    ).then((_) {
      pageController.dispose();
      focusNode.dispose();
    });

    focusNode.requestFocus();
  }

  static void openArchive(
    BuildContext context, {
    required Uint8List data,
    required String fileName,
    String? archiveName,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(archiveName != null ? '$archiveName / $fileName' : fileName, style: const TextStyle(color: Colors.white, fontSize: 14)),
            leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ),
          body: Center(
            child: InteractiveViewer(child: Image.memory(data, fit: BoxFit.contain)),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _ImageViewerBody(files: files, initialIndex: initialIndex, creatorId: creatorId, postId: postId);
}

class AnimatedAspectRatio extends ImplicitlyAnimatedWidget {
  final double aspectRatio;
  final Widget child;

  const AnimatedAspectRatio({
    super.key,
    required this.aspectRatio,
    required this.child,
    super.curve = Curves.linear,
    required super.duration,
    super.onEnd,
  });

  @override
  ImplicitlyAnimatedWidgetState<AnimatedAspectRatio> createState() => _AnimatedAspectRatioState();
}

class _AnimatedAspectRatioState extends AnimatedWidgetBaseState<AnimatedAspectRatio> {
  Tween<double>? _aspectRatioTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _aspectRatioTween =
        visitor(_aspectRatioTween, widget.aspectRatio, (dynamic value) => Tween<double>(begin: value as double)) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _aspectRatioTween!.evaluate(animation),
      child: widget.child,
    );
  }
}

class ImageViewerScreen extends StatelessWidget {
  final List<FileInfo> files;
  final int initialIndex;
  final String creatorId;
  final String postId;

  const ImageViewerScreen({required this.files, required this.initialIndex, required this.creatorId, required this.postId, super.key});

  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width > 900;

  static void open(
    BuildContext context, {
    required List<FileInfo> files,
    required int index,
    required String creatorId,
    required String postId,
  }) {
    final imageFiles = files.where((f) {
      final ext = f.name?.split('.').last.toLowerCase() ?? '';
      return {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'}.contains(ext);
    }).toList();

    final imageIndex = imageFiles.indexOf(files[index]);
    final adjustedIndex = imageIndex >= 0 ? imageIndex : 0;

    if (isDesktop(context)) {
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          barrierDismissible: true,
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) =>
              _ImageViewerBody(files: imageFiles, initialIndex: adjustedIndex, creatorId: creatorId, postId: postId),
          transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
      return;
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _ImageViewerBody(files: imageFiles, initialIndex: adjustedIndex, creatorId: creatorId, postId: postId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _ImageViewerBody(files: files, initialIndex: initialIndex, creatorId: creatorId, postId: postId);
}

class _ImageViewerBody extends StatefulWidget {
  final List<FileInfo> files;
  final int initialIndex;
  final String creatorId;
  final String postId;

  const _ImageViewerBody({required this.files, required this.initialIndex, required this.creatorId, required this.postId});

  @override
  State<_ImageViewerBody> createState() => _ImageViewerBodyState();
}

class _ImageViewerBodyState extends State<_ImageViewerBody> {
  late final PageController _controller;
  late int _currentIndex;
  final _focusNode = FocusNode();

  final _loadedRatios = <int, double>{};

  double _aspectRatioFor(int index) {
    final url = '${FileHelpers.imgThumbBase}${widget.files[index].path}';
    final meta = ImageMetaStore.instance.lookup(url);
    if (meta != null) return meta.aspectRatio;
    return _loadedRatios[index] ?? 1.0;
  }

  double _displayAspectRatio = 1.0;
  late final ValueNotifier<double> _aspectRatioNotifier;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
    _currentIndex = widget.initialIndex;
    _displayAspectRatio = _aspectRatioFor(_currentIndex);
    _aspectRatioNotifier = ValueNotifier(_displayAspectRatio);
    _focusNode.requestFocus();

    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final page = _controller.page;
    if (page == null) return;

    final a = _aspectRatioFor((page.floor()).clamp(0, widget.files.length - 1));
    final b = _aspectRatioFor((page.ceil()).clamp(0, widget.files.length - 1));
    final t = page - page.floorToDouble();
    _displayAspectRatio = a + (b - a) * t;
    _aspectRatioNotifier.value = _displayAspectRatio;
  }

  void _onImageLoaded(int index, double aspectRatio) {
    _loadedRatios[index] = aspectRatio;

    if (_currentIndex != index) return;

    _displayAspectRatio = aspectRatio;
    _aspectRatioNotifier.value = aspectRatio;
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _aspectRatioNotifier.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.files.length) return;
    _controller.animateToPage(index, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _displayAspectRatio = _aspectRatioFor(index);
      _aspectRatioNotifier.value = _displayAspectRatio;
    });
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _goTo(_currentIndex - 1);
      case LogicalKeyboardKey.arrowRight:
        _goTo(_currentIndex + 1);
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ImageViewerScreen.isDesktop(context);
    final hasMultiple = widget.files.length > 1;
    final screenWidth = MediaQuery.sizeOf(context).width * 0.85;
    final screenHeight = MediaQuery.sizeOf(context).height * 0.85;

    final content = ValueListenableBuilder<double>(
      valueListenable: _aspectRatioNotifier,
      builder: (context, aspectRatio, _) {
        final dialogWidth = screenWidth;
        var dialogHeight = dialogWidth / aspectRatio;
        if (dialogHeight > screenHeight) {
          dialogHeight = screenHeight;
        }

        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: widget.files.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, i) {
                      final f = widget.files[i];
                      final fullUrl = '${FileHelpers.fileDataBase}${f.path}${f.name != null ? '?f=${Uri.encodeComponent(f.name!)}' : ''}';
                      final thumbUrl = '${FileHelpers.imgThumbBase}${f.path}';
                      return _ImageViewerPage(
                        url: fullUrl,
                        thumbUrl: thumbUrl,
                        creatorId: widget.creatorId,
                        postId: widget.postId,
                        onImageLoaded: (ratio) => _onImageLoaded(i, ratio),
                      );
                    },
                  ),
                  if (isDesktop && hasMultiple) ...[
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _NavArrow(icon: Icons.chevron_left, visible: _currentIndex > 0, onTap: () => _goTo(_currentIndex - 1)),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _NavArrow(
                          icon: Icons.chevron_right,
                          visible: _currentIndex < widget.files.length - 1,
                          onTap: () => _goTo(_currentIndex + 1),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );

    if (isDesktop) {
      return KeyboardListener(focusNode: _focusNode, onKeyEvent: _onKey, child: content);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.files.length}', style: const TextStyle(fontSize: 16)),
      ),
      body: KeyboardListener(focusNode: _focusNode, onKeyEvent: _onKey, child: content),
    );
  }
}

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

class _ImageViewerPage extends StatefulWidget {
  final String url;
  final String thumbUrl;
  final String creatorId;
  final String postId;
  final ValueChanged<double>? onImageLoaded;

  const _ImageViewerPage({required this.url, required this.thumbUrl, required this.creatorId, required this.postId, this.onImageLoaded});

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  double _progress = 0;
  ImageStream? _imageStream;
  ImageStreamListener? _listener;
  ImageInfo? _imageInfo;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    _load();
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
          final ratio = info.image.width / info.image.height;
          widget.onImageLoaded?.call(ratio.isFinite ? ratio : 1.0);
        }
      },
      onChunk: (chunk) {
        if (chunk.expectedTotalBytes != null && chunk.expectedTotalBytes! > 0) {
          final p = chunk.cumulativeBytesLoaded / chunk.expectedTotalBytes!;
          if (mounted) setState(() => _progress = p.clamp(0.0, 1.0));
        }
      },
      onError: (error, stack) {
        if (mounted) {
          setState(() => _errored = true);
          debugPrint('ImageViewer load error for ${widget.url}: $error\n$stack');
        }
      },
    );
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_listener!);
    _imageInfo?.dispose();
    super.dispose();
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

    final meta = ImageMetaStore.instance.lookup(widget.thumbUrl);
    final aspectRatio = meta?.aspectRatio;

    if (_imageInfo != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: RawImage(image: _imageInfo!.image, fit: BoxFit.contain),
        ),
      );
    }

    return Center(
      child: aspectRatio != null ? AspectRatio(aspectRatio: aspectRatio, child: _buildSkeleton()) : _buildSkeleton(),
    );
  }

  Widget _buildSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final shortest = math.min(w, h);

        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: w,
              height: h,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(15)),
            ),
            CustomPaint(
              size: Size(w, h),
              painter: _ClockwiseBorderPainter(progress: _progress),
            ),
            Positioned(
              bottom: shortest * 0.06,
              child: Text(
                '${(_progress * 100).toInt()}%',
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
      },
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
