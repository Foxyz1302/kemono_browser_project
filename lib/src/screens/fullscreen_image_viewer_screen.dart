import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show instantiateImageCodec;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/archive/archive_service.dart';
import 'package:kemono_browser_project/src/cache/image_cache_service.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';
import 'package:kemono_browser_project/src/cache/kemono_image_provider.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_flutter.dart';

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

/// Mixin that provides full-screen zoom/pan/clamp for any page widget via
/// raw [Listener] pointer events (no gesture-arena delay or competition).
/// Only double-tap uses a [GestureDetector] / [DoubleTapGestureRecognizer].
///
/// Requires [TickerProvider] (provided by [TickerProviderStateMixin]) for
/// the fling animation and [AnimationController].
mixin _ZoomableMixin<T extends StatefulWidget> on State<T>, TickerProvider {
  // -----------------------------------------------------------------------
  // Zoom / pan state
  // -----------------------------------------------------------------------
  double _zoomScale = 1.0;
  Offset _zoomOffset = Offset.zero;

  // -----------------------------------------------------------------------
  // Animation (double-tap smooth zoom)
  // -----------------------------------------------------------------------
  AnimationController? _animController;
  bool _animating = false;
  int _animId = 0;

  // -----------------------------------------------------------------------
  // Fling / inertia
  // -----------------------------------------------------------------------
  Ticker? _flingTicker;
  double _flingVx = 0, _flingVy = 0;
  int _flingId = 0;

  // -----------------------------------------------------------------------
  // Raw pointer tracking (all touch zoom/pan, no gesture arena)
  // -----------------------------------------------------------------------
  final Map<int, Offset> _pointerPositions = {};
  final Map<int, Offset> _previousPositions = {};
  int _prevPointerCount = 0;
  double? _pinchStartDist;
  double _pinchStartScale = 1.0;

  // Velocity samples for fling computation.
  final List<_VelocitySample> _velocitySamples = [];
  static const int _maxVelocitySamples = 4;

  // Stashed viewport/image dims — set in build() so raw handlers can clamp.
  double _vpW = 0, _vpH = 0, _imgW = 0, _imgH = 0;

  // -----------------------------------------------------------------------
  // External callback — fires on every scale change so parent toggles physics.
  // -----------------------------------------------------------------------
  ValueChanged<double>? onZoomChanged;

  /// Fires when a quick tap (no drag) lands outside the image bounds.
  VoidCallback? onTapOutsideImage;

  /// Fires when the dismiss fling animation completes — the page pops itself.
  VoidCallback? onDismissed;

  /// Reports dismiss drag progress (0..1) so the parent can fade the backdrop.
  ValueChanged<double>? onDismissProgress;

  // Swipe-to-dismiss state (image-only — the route chrome stays put).
  AnimationController? _dismissCtrl;
  bool _dismissing = false;

  // Tap / dismiss-drag tracking.
  Offset? _downPos;
  Offset? _downLocal;
  Duration _downTime = Duration.zero;
  double _dragAccum = 0;
  bool _dismissDragging = false;
  bool _dismissLocked = false;

  double get dismissOffset => _dismissCtrl?.value ?? 0;

  double get dismissProgress => _vpH > 0 ? (dismissOffset.abs() / (_vpH * 0.5)).clamp(0.0, 1.0) : 0.0;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  void initZoomAnimation(TickerProvider vsync) {
    _animController = AnimationController(duration: const Duration(milliseconds: 200), vsync: vsync);
    _dismissCtrl = AnimationController.unbounded(vsync: vsync)
      ..addListener(() {
        if (!mounted) return;
        setState(() {});
        onDismissProgress?.call(dismissProgress);
      });
  }

  void disposeZoomAnimation() {
    _cancelAnimation();
    _cancelFling();
    _animController?.dispose();
    _dismissCtrl?.dispose();
  }

  // -----------------------------------------------------------------------
  // Build helper
  // -----------------------------------------------------------------------

  Matrix4 buildZoomTransform(double vw, double vh, double iw, double ih) {
    return Matrix4.identity()
      ..setEntry(0, 3, _zoomOffset.dx)
      ..setEntry(1, 3, _zoomOffset.dy)
      ..setEntry(0, 0, _zoomScale)
      ..setEntry(1, 1, _zoomScale);
  }

  // -----------------------------------------------------------------------
  // Mouse-wheel zoom
  // -----------------------------------------------------------------------

  void zoomOnScroll(double scrollDy, Offset cursorPos, Size viewport, double iw, double ih) {
    _cancelFling();
    final oldScale = _zoomScale;
    final newScale = (_zoomScale * (1 - scrollDy * 0.001)).clamp(1.0, 5.0);
    if (newScale == oldScale) return;
    final vpc = Offset(viewport.width / 2, viewport.height / 2);
    _zoomOffset = (cursorPos - vpc) + (_zoomOffset - (cursorPos - vpc)) * (newScale / oldScale);
    _zoomScale = newScale;
    _zoomClampPosition(viewport, iw, ih);
    _checkHaptic(oldScale, _zoomScale);
    onZoomChanged?.call(_zoomScale);
  }

  // -----------------------------------------------------------------------
  // Raw pointer handlers (pan + pinch, zero arena delay)
  // -----------------------------------------------------------------------

  void handlePointerDown(PointerDownEvent event) {
    _cancelFling();
    _pointerPositions[event.pointer] = event.position;
    _previousPositions[event.pointer] = event.position;
    _velocitySamples.clear();
    _prevPointerCount = _pointerPositions.length;

    if (_pointerPositions.length == 1) {
      _downPos = event.position;
      _downLocal = event.localPosition;
      _downTime = event.timeStamp;
      _dragAccum = 0;
      _dismissDragging = false;
      _dismissLocked = false;
    } else {
      _dismissDragging = false;
      _dismissLocked = true;
    }

    if (_pointerPositions.length == 2) {
      _pinchStartDist = _distanceBetweenPoints();
      _pinchStartScale = _zoomScale;
    }
  }

  void handlePointerMove(PointerMoveEvent event) {
    final prev = _previousPositions[event.pointer] ?? event.position;
    final delta = event.position - prev;
    _pointerPositions[event.pointer] = event.position;
    _previousPositions[event.pointer] = event.position;
    final pointerCount = _pointerPositions.length;

    if (pointerCount >= 2) {
      // Pinch zoom.
      final dist = _distanceBetweenPoints();
      if (_pinchStartDist != null && _pinchStartDist! > 0 && dist > 0) {
        final oldScale = _zoomScale;
        final newScale = (_pinchStartScale * dist / _pinchStartDist!).clamp(1.0, 5.0);
        if (newScale != oldScale) {
          setState(() {
            _zoomScale = newScale;
            _zoomClampPosition(Size(_vpW, _vpH), _imgW, _imgH);
          });
          _checkHaptic(oldScale, _zoomScale);
          onZoomChanged?.call(_zoomScale);
        }
      }
    } else if (pointerCount == 1 && _zoomScale > 1.0) {
      // Single-finger pan (only when zoomed in).
      setState(() {
        _zoomOffset += delta;
        _zoomClampPosition(Size(_vpW, _vpH), _imgW, _imgH);
      });
      _recordVelocitySample(event.position);
    } else if (pointerCount == 1) {
      // At 1× zoom: track movement for tap detection + dismiss drag.
      _dragAccum += delta.distance;
      final down = _downPos;
      final downLocal = _downLocal;
      if (!_dismissing && down != null && downLocal != null && !_dismissLocked) {
        final total = event.position - down;
        if (!_dismissDragging && total.distance > 12) {
          // Lock in the gesture direction once past slop: vertical drag that
          // started on the image = dismiss, anything else = page swipe / none.
          if (_isOnImage(downLocal) && total.dy.abs() > total.dx.abs()) {
            _dismissDragging = true;
          } else {
            _dismissLocked = true;
          }
        }
        if (_dismissDragging && _dismissCtrl != null) {
          _dismissCtrl!.value += delta.dy;
          _recordVelocitySample(event.position);
        }
      }
    }
  }

  void handlePointerUp(PointerUpEvent event) {
    _pointerPositions.remove(event.pointer);
    _previousPositions.remove(event.pointer);

    if (_pointerPositions.length < 2) _pinchStartDist = null;

    final wasSingle = _prevPointerCount == 1 && _pointerPositions.isEmpty;

    // If a single finger was just lifted while zoomed, start fling.
    if (wasSingle && _zoomScale > 1.0) {
      final vel = _computePanVelocity();
      if (vel.distance > 300) {
        _startFling(vel.dx, vel.dy);
      }
    }

    if (wasSingle && _zoomScale <= 1.0 + 0.01) {
      if (_dismissDragging) {
        _endDismissDrag(_computePanVelocity().dy);
      } else if (!_dismissing &&
          !_dismissLocked &&
          _dragAccum < 12 &&
          event.timeStamp - _downTime < const Duration(milliseconds: 400) &&
          !_isOnImage(event.localPosition)) {
        // Quick tap on the dark background outside the image → dismiss.
        onTapOutsideImage?.call();
      }
    }

    _dismissDragging = false;
    _dismissLocked = false;
    _prevPointerCount = _pointerPositions.length;

    // Notify parent of any zoom state change.
    if (_pointerPositions.isEmpty) {
      onZoomChanged?.call(_zoomScale);
    }
  }

  /// Whether [local] (page-local coords) falls inside the centered image rect.
  bool _isOnImage(Offset local) {
    final imgLeft = (_vpW - _imgW) / 2;
    final imgTop = (_vpH - _imgH) / 2;
    return local.dx >= imgLeft && local.dx <= imgLeft + _imgW && local.dy >= imgTop && local.dy <= imgTop + _imgH;
  }

  /// End of a dismiss drag: fling the image off-screen and pop, or spring back.
  void _endDismissDrag(double velocity) {
    final ctrl = _dismissCtrl;
    if (_dismissing || ctrl == null) return;
    final screenH = _vpH;
    final offset = ctrl.value;

    if (velocity.abs() > 800 || offset.abs() > screenH * 0.25) {
      _dismissing = true;
      // Use drag direction when fling velocity is negligible.
      final dir = velocity.abs() > 50 ? velocity.sign : (offset.sign == 0 ? 1.0 : offset.sign);
      ctrl.animateTo(dir * screenH * 1.5, duration: const Duration(milliseconds: 200), curve: Curves.easeIn).then((_) {
        onDismissed?.call();
      });
    } else {
      ctrl.animateWith(
        SpringSimulation(const SpringDescription(mass: 1, stiffness: 600, damping: 50), offset, 0, velocity),
      );
    }
  }

  // -----------------------------------------------------------------------
  // Double‑tap zoom
  // -----------------------------------------------------------------------

  void zoomOnDoubleTapDown(Offset tapPos, Size viewport, double iw, double ih) {
    if (_animating) {
      _cancelAnimation();
      return;
    }
    if (_zoomScale > 1.0 + 0.01) {
      _animateZoomTo(1.0, Offset.zero, viewport, iw, ih);
    } else {
      const targetScale = 2.5;
      final vpc = Offset(viewport.width / 2, viewport.height / 2);
      final targetOffset = (tapPos - vpc) + (_zoomOffset - (tapPos - vpc)) * (targetScale / _zoomScale);
      _animateZoomTo(targetScale, targetOffset, viewport, iw, ih);
    }
  }

  // -----------------------------------------------------------------------
  // Fling / inertia
  // -----------------------------------------------------------------------

  void _startFling(double vx, double vy) {
    _cancelFling();
    final speed = Offset(vx, vy).distance;
    if (speed < 50) return;

    _flingVx = vx;
    _flingVy = vy;
    _flingId++;
    final id = _flingId;
    const friction = 0.92;

    _flingTicker = createTicker((elapsed) {
      if (_flingId != id || !mounted) {
        _cancelFling();
        return;
      }
      final speed = Offset(_flingVx, _flingVy).distance;
      if (speed < 5) {
        _cancelFling();
        if (mounted) setState(() {});
        return;
      }
      setState(() {
        _zoomOffset += Offset(_flingVx / 60, _flingVy / 60);
        _flingVx *= friction;
        _flingVy *= friction;
        _zoomClampPosition(Size(_vpW, _vpH), _imgW, _imgH);
        onZoomChanged?.call(_zoomScale);
      });
    });
    _flingTicker!.start();
  }

  void _cancelFling() {
    _flingTicker?.stop();
    _flingTicker?.dispose();
    _flingTicker = null;
    _flingVx = 0;
    _flingVy = 0;
  }

  // -----------------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------------

  double _distanceBetweenPoints() {
    final positions = _pointerPositions.values.toList();
    if (positions.length < 2) return 0;
    return (positions[0] - positions[1]).distance;
  }

  void _recordVelocitySample(Offset position) {
    final now = DateTime.now().microsecondsSinceEpoch;
    _velocitySamples.add(_VelocitySample(now, position));
    while (_velocitySamples.length > _maxVelocitySamples) {
      _velocitySamples.removeAt(0);
    }
  }

  Offset _computePanVelocity() {
    if (_velocitySamples.length < 2) return Offset.zero;
    final first = _velocitySamples.first;
    final last = _velocitySamples.last;
    final dt = (last.timeUs - first.timeUs) / 1000000.0;
    if (dt <= 0) return Offset.zero;
    return (last.position - first.position) / dt;
  }

  void _cancelAnimation() {
    if (_animating && _animController != null) {
      _animController!.stop();
      _animating = false;
    }
  }

  /// Smoothly animate zoom/pan to [targetScale] / [targetOffset].
  void _animateZoomTo(double targetScale, Offset targetOffset, Size viewport, double iw, double ih) {
    if (_animController == null) return;
    _cancelAnimation();

    // Clamp the target first.
    final savedScale = _zoomScale;
    final savedOffset = _zoomOffset;
    _zoomScale = targetScale;
    _zoomOffset = targetOffset;
    _zoomClampPosition(viewport, iw, ih);
    final clampedScale = _zoomScale;
    final clampedOffset = _zoomOffset;
    _zoomScale = savedScale;
    _zoomOffset = savedOffset;

    final begin = buildZoomTransform(viewport.width, viewport.height, iw, ih);

    _zoomScale = clampedScale;
    _zoomOffset = clampedOffset;
    final end = buildZoomTransform(viewport.width, viewport.height, iw, ih);
    _zoomScale = savedScale;
    _zoomOffset = savedOffset;

    final tween = Matrix4Tween(begin: begin, end: end);
    final anim = tween.animate(CurvedAnimation(parent: _animController!, curve: Curves.easeOut));
    final currentAnimId = ++_animId;

    _animating = true;
    anim.addListener(() {
      if (_animId != currentAnimId) return;
      setState(() {
        _zoomScale = anim.value.getMaxScaleOnAxis();
        _zoomOffset = Offset(anim.value.getTranslation().x, anim.value.getTranslation().y);
        _zoomClampPosition(viewport, iw, ih);
      });
    });

    _animController!.addStatusListener((status) {
      if (_animId != currentAnimId) return;
      if (status == AnimationStatus.completed) {
        _animating = false;
        onZoomChanged?.call(_zoomScale);
      }
    });

    _animController!.forward(from: 0);
  }

  /// Trigger [HapticFeedback.mediumImpact] when hitting a zoom limit.
  void _checkHaptic(double oldScale, double newScale) {
    if (oldScale == newScale) return;
    if ((newScale == 1.0 && oldScale != 1.0) || (newScale == 5.0 && oldScale != 5.0)) {
      HapticFeedback.mediumImpact();
    }
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

/// Timestamped position sample used to compute pan velocity for fling.
class _VelocitySample {
  final int timeUs;
  final Offset position;
  const _VelocitySample(this.timeUs, this.position);
}

// =============================================================================
// _ZoomReporter — InheritedWidget that carries the onZoomChanged callback
// down to each page so it can toggle PageView physics.
// =============================================================================

class _ZoomReporter extends InheritedWidget {
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<double> onDismissProgress;

  const _ZoomReporter({
    required this.onZoomChanged,
    required this.onDismissProgress,
    required super.child,
  });

  static _ZoomReporter? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ZoomReporter>();
  }

  @override
  bool updateShouldNotify(_ZoomReporter old) =>
      onZoomChanged != old.onZoomChanged || onDismissProgress != old.onDismissProgress;
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
  /// Toggled between [PageScrollPhysics] and [NeverScrollableScrollPhysics]
  /// based on whether the current page is zoomed beyond 1×.
  ScrollPhysics _pagePhysics = const PageScrollPhysics();

  /// Backdrop opacity (1 = fully dimmed). Fades as the image is dragged away.
  double _bgOpacity = 1.0;

  void _onPageZoomChanged(double scale) {
    setState(() {
      _pagePhysics = scale > 1.0 ? const NeverScrollableScrollPhysics() : const PageScrollPhysics();
    });
  }

  void _onPageChanged(int index) {
    widget.currentIndex.value = index;
    setState(() => _pagePhysics = const PageScrollPhysics());
  }

  void _onDismissProgress(double progress) {
    setState(() => _bgOpacity = 1.0 - progress);
  }

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
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ---- Backdrop (fades as the image is dragged away) ----
        Container(color: Colors.black.withValues(alpha: 0.87 * _bgOpacity)),

        // ---- PageView ----
        SignalBuilder(
          builder: (context) {
            return _ZoomReporter(
              onZoomChanged: _onPageZoomChanged,
              onDismissProgress: _onDismissProgress,
              child: PageView.builder(
                controller: widget.pageController,
                physics: _pagePhysics,
                itemCount: widget.itemCount,
                onPageChanged: _onPageChanged,
                itemBuilder: widget.pageBuilder,
              ),
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

class _FullscreenPageState extends State<_FullscreenPage> with TickerProviderStateMixin, _ZoomableMixin<_FullscreenPage> {
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
    initZoomAnimation(this);
    onTapOutsideImage = () {
      if (mounted) Navigator.of(context).pop();
    };
    onDismissed = () {
      if (mounted) Navigator.of(context).pop();
    };
    _imageProvider = KemonoImageProvider(widget.url, creatorId: widget.creatorId, postId: widget.postId);
    _loadThumbnail();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reporter = _ZoomReporter.maybeOf(context);
    if (reporter != null) {
      onZoomChanged = reporter.onZoomChanged;
      onDismissProgress = reporter.onDismissProgress;
    }
    if (!_resolved) {
      _resolved = true;
      _resolveImage();
    }
  }

  @override
  void dispose() {
    disposeZoomAnimation();
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

        // Stash for raw-pointer handlers.
        _vpW = vw;
        _vpH = vh;
        _imgW = iw;
        _imgH = ih;

        return SizedBox(
          width: vw,
          height: vh,
          child: Listener(
            // Opaque so pointer events land here across the whole viewport —
            // the child chain is only hittable on the image itself, which
            // would swallow background taps/drags before they reach us.
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && _imageInfo != null && _hasLoaded) {
                setState(() => zoomOnScroll(event.scrollDelta.dy, event.localPosition, Size(vw, vh), iw, ih));
              }
            },
            onPointerDown: handlePointerDown,
            onPointerMove: handlePointerMove,
            onPointerUp: handlePointerUp,
            child: GestureDetector(
              onDoubleTapDown: (details) {
                if (_imageInfo != null && _hasLoaded) {
                  setState(() => zoomOnDoubleTapDown(details.localPosition, Size(vw, vh), iw, ih));
                }
              },
              child: Transform.translate(
                offset: Offset(0, dismissOffset),
                child: Transform.scale(
                  scale: 1.0 - dismissProgress * 0.15,
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
                      // Always present so AnimatedOpacity's state persists across the
                      // _hasLoaded transition.  Child is SizedBox.shrink() until the
                      // image resolves, then swaps to the zoomable RawImage.
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
                                child: Transform(
                                  transform: buildZoomTransform(vw, vh, iw, ih),
                                  alignment: Alignment.center,
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

class _ArchivePageState extends State<_ArchivePage> with TickerProviderStateMixin, _ZoomableMixin<_ArchivePage> {
  Uint8List? _data;
  bool _errored = false;
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    initZoomAnimation(this);
    onTapOutsideImage = () {
      if (mounted) Navigator.of(context).pop();
    };
    onDismissed = () {
      if (mounted) Navigator.of(context).pop();
    };
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reporter = _ZoomReporter.maybeOf(context);
    if (reporter != null) {
      onZoomChanged = reporter.onZoomChanged;
      onDismissProgress = reporter.onDismissProgress;
    }
  }

  @override
  void dispose() {
    disposeZoomAnimation();
    super.dispose();
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
      } catch (e, st) {
        debugPrint('ArchivePage: codec decode failed for ${widget.entryPath}: $e\n$st');
        // Fallback: use 1:1 ratio.
        ar = null;
      }

      setState(() {
        _data = data;
        _aspectRatio = ar;
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
        final ratio = _aspectRatio ?? 1.0;
        final (double iw, double ih) = FullscreenImageViewerScreen._containSize(vw, vh, ratio);

        // Stash for raw-pointer handlers.
        _vpW = vw;
        _vpH = vh;
        _imgW = iw;
        _imgH = ih;

        return SizedBox(
          width: vw,
          height: vh,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                setState(() => zoomOnScroll(event.scrollDelta.dy, event.localPosition, Size(vw, vh), iw, ih));
              }
            },
            onPointerDown: handlePointerDown,
            onPointerMove: handlePointerMove,
            onPointerUp: handlePointerUp,
            child: GestureDetector(
              onDoubleTapDown: (details) {
                setState(() => zoomOnDoubleTapDown(details.localPosition, Size(vw, vh), iw, ih));
              },
              child: Transform.translate(
                offset: Offset(0, dismissOffset),
                child: Transform.scale(
                  scale: 1.0 - dismissProgress * 0.15,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Zoomable image.
                      Center(
                        child: Transform(
                          transform: buildZoomTransform(vw, vh, iw, ih),
                          alignment: Alignment.center,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: SizedBox(
                              width: iw,
                              height: ih,
                              child: Image.memory(_data!, fit: BoxFit.contain, filterQuality: FilterQuality.high),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
