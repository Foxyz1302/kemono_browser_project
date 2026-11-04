# Future: Boundary-Aware Gesture Disambiguation (photo_view style)

## Current approach (implemented)

Binary physics toggle — PageView freezes (`NeverScrollableScrollPhysics`) when zoomed >1×.
Simple, predictable, matches Google Photos basic behavior.

## Why this doc exists

The boundary-aware approach (used by `photo_view`) is more sophisticated: it allows the user
to swipe to the next page even while zoomed in, by releasing the gesture to the PageView
when the image's pan boundary is reached. This was researched but deferred for simplicity.

## How it works (photo_view architecture)

### Custom `ScaleGestureRecognizer`

Replace `GestureDetector` with `RawGestureDetector` using a custom recognizer
that extends `ScaleGestureRecognizer`:

```dart
class _BoundaryScaleGestureRecognizer extends ScaleGestureRecognizer {
  bool Function()? shouldReleaseToParent;
  Axis? parentScrollAxis; // Axis.horizontal for PageView

  @override
  void handleEvent(PointerEvent event) {
    // After tracking initial focal point, check at PointerMoveEvent:
    // if the image has reached its pan boundary AND the user continues
    // dragging in the same direction → DON'T call acceptGesture(),
    // letting the PageView's HorizontalDragGestureRecognizer win.
    super.handleEvent(event);
  }
}
```

### HitCornersDetector

Tracks which edges of the zoomed image are at the viewport boundary:

```dart
class _HitCorners {
  final bool left;
  final bool right;
  // (or top/bottom for vertical scroll)
  bool get hasHitBoth => left && right;
}
```

- If the image fits entirely within the viewport on the scroll axis → both corners hit
  → gesture should go to PageView (no panning possible).
- If the image is larger than the viewport → check dragging direction:
  - Dragging inward (away from edge) → image panning wins.
  - Dragging outward (past the edge) → PageView wins.

### Flow

1. `_BoundaryScaleGestureRecognizer.handleEvent()` receives `PointerMoveEvent`.
2. Computes move delta from initial focal point.
3. Calls `hitDetector.shouldMove(move, parentScrollAxis)`.
4. If `shouldMove == false` AND only 1 pointer → recognizer does NOT accept the gesture.
   The PageView's `HorizontalDragGestureRecognizer` wins the arena instead.
5. If 2+ pointers (pinch/zoom) → always accept (zoom takes priority over page swipe).

### Implementation steps (when revisited)

1. Create `lib/src/widgets/boundary_scale_recognizer.dart` with the custom recognizer.
2. Create `lib/src/widgets/hit_corners.dart` with the corner-detection logic.
3. Modify `_ZoomableMixin` in `fullscreen_image_viewer_screen.dart`:
   - Replace `GestureDetector` with `RawGestureDetector` using the new recognizer.
   - Expose image boundary state (has the pan hit the viewport edges?).
   - Remove the binary physics toggle (PageView stays scrollable even when zoomed).
4. The `_FullscreenPageViewInner` or its parent provides the scroll axis via
   an `InheritedWidget` (like `PhotoViewGestureDetectorScope`).

### Reference

- `photo_view` package: `PhotoViewGestureRecognizer` + `HitCornersDetector`
  (`lib/src/core/photo_view_gesture_detector.dart`,
   `lib/src/core/photo_view_hit_corners.dart`)
- `extended_image` package: `ExtendedImageGesturePageView` + `movePage()` boundary check
  (`lib/src/gesture/gesture.dart`, `lib/src/gesture/utils.dart`)
- Flutter source: `ScaleGestureRecognizer` (`handleEvent`, `acceptGesture`, `_checkEnd`)
