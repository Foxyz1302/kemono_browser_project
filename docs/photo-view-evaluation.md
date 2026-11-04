# PhotoView Evaluation — Fullscreen Viewer Refactor

Planning doc for the fullscreen viewer refactor (video support made
`fullscreen_image_viewer_screen.dart` a ~1900-line mess with duplicated
dismiss + video code). Question: adopt `photo_view`, fork it, or write our own
adapting its principles. Status: **evaluation done — decisions locked (§6),
refactor not yet implemented.**

Related: `future-boundary-aware-gestures.md` (earlier research on the same
gesture-arena topic), `problems.md`.

---

## 1. Current viewer anatomy (the mess)

`lib/src/screens/fullscreen_image_viewer_screen.dart` — 4 page types:

| Page | Zoom | Dismiss | Notes |
|------|------|---------|-------|
| `_FullscreenPage` (API image) | `_ZoomableMixin` | in mixin | skeleton + thumbnail + progress border |
| `_ArchivePage` (archive image) | `_ZoomableMixin` | in mixin | reads entry bytes, pre-decodes for aspect |
| `_VideoPage` (API video) | none | ~65 lines copy #1 | media_kit player |
| `_ArchiveVideoPage` (archive video) | none | ~65 lines copy #2 | extracts to temp file first |

`_ZoomableMixin` (raw-`Listener` input, no gesture arena):

- Wheel zoom: `× (1 - scrollDy * 0.001)`, clamp 1.0–5.0
- Pinch (multi-pointer distance ratio), single-finger pan when `scale > 1.0`
- Fling: hand-rolled `Ticker`, friction `0.92`/frame, velocity from ≤4 timestamped samples, starts if velocity > 300
- Double-tap: **zooms to the tapped point** (target 2.5×), second tap resets to 1×
- Dismiss: slop 12px locks direction; vertical drag on image → translate; release: velocity > 800 **or** offset > 25% screen → fling off + pop, else spring back (`SpringDescription(mass 1, stiffness 600, damping 50)`)
- Tap outside the image rect → pop; haptics at zoom limits
- `_ZoomReporter` InheritedWidget carries `onZoomChanged` (→ `NeverScrollableScrollPhysics` when >1×) + `onDismissProgress` (→ backdrop fade) up to the viewer

Video pages: identical dismiss code (velocity sampling, thresholds, spring),
identical player lifecycle + stream listeners; controls UI currently commented
out in both (bare `Video` widget); seek uses `onZoomChanged(2.0)/(1.0)` as a
physics-lock hack.

---

## 2. Test harness

`lib/src/screens/photo_view_demo_screen.dart` — entry: photo icon button in the
home top bar (desktop layout, right of Settings). Dev tool, remove before ship.

- `PhotoViewGallery.builder`, 3 real **cached** full-size images loaded through
  the real `KemonoImageProvider` stack (cache hits, instant):
  - portrait 1457×2048 — `.../data/82/91/829126892beebd0a7ff5b5a398e63a760b53162b15323ce900d944d126aa69ec.png`
  - landscape 8500×6000 — `.../data/09/f4/09f4e606de27786cf633282b8d3e194b62a0b6859368f8ac38d28300972f763c.jpeg`
  - ultra-wide 3267×1634 — `.../data/79/e9/79e996f02a2700dbc38c590057d027b7566608be8e87e49950cec165d6f8b525.png`
  (URLs recovered from `{temp}/kemono_cache/kemono_image_meta.json` by matching
  dims — the ImageMetaStore records w/h per URL.)
- Scale lock bridge: `scaleStateChangedCallback` → physics toggle (same as ours)
- `ScrollConfiguration` with `PointerDeviceKind.mouse` added to `dragDevices`
  (see §4 finding 6)
- **No Dismissible** — deliberately removed: stock photo_view structurally can't
  do "pan while zoomed" + "viewer-level vertical dismiss" at once (see §4
  finding 4). Dismiss will be ours regardless, so it only polluted the zoom test.

---

## 3. Findings (feel test 2026-07-31, Windows desktop)

| # | Finding | Verdict | Cause (source-verified) |
|---|---------|---------|-------------------------|
| 1 | Zoom feel | ✅ **better than ours** — "biggest concern, passed" | photo_view controller math (scale boundaries, pan clamp, contained/covered) |
| 2 | Double-tap | ⚠️ different → plan: combine both | ours zooms to tapped point (2.5×), 200ms easeOut; photo_view: 1st tap → contained→covered-ish fit, 2nd → zooms to **center**, not tap point; animation = `AnimationController.fling(velocity: 0.4)` → FrictionSimulation with a **multi-second front-loaded tail** ("weird curve with long duration") |
| 3 | Fling | ✅ **keep ours** (user preference) | ours: velocity-proportional ticker fling (friction 0.92/frame), cancels on pointer-down ("fling fast, tap to stop"); photo_view: fixed **+100px glide target** (not velocity-proportional), friction curve, only when no scale change + velocity ≥ 400 |
| 4 | Dismiss fires while panning zoomed image | 🔴 broken in stock | 0.15.0 gallery scope validates **one axis only** (`axis: scrollDirection`); vertical drag → `mainAxisMove == 0` → photo_view declines → parent Dismissible wins at any zoom. **The exact bug LoliSnatcher forked to fix** |
| 5 | No wheel zoom | 🔴 absent | verified: gesture detector registers only Tap/DoubleTap/Scale recognizers — zero `PointerScrollEvent` handling anywhere |
| 6 | Mouse swipe didn't page | 🟡 not photo_view's fault | **Flutter 3.47 removed `PointerDeviceKind.mouse` from default `ScrollBehavior.dragDevices`** (`_kTouchLikeDeviceTypes`, `scroll_configuration.dart:29`) — PageViews ignore mouse drags app-wide. One-line `ScrollConfiguration.copyWith(dragDevices: +mouse)` fix. **Our own viewer has the same issue** (nav arrows/keyboard only) |
| 7 | Touch swiping feel | ✅ tested — see §3.5 | Android phone test 2026-07-31 |

### 3.5 Phone findings (2026-07-31, Android touch)

| # | Finding | Verdict |
|---|---------|---------|
| 8 | Zoom / pan / page switching | ✅ "feels really good" — photo_view's arbitration wins hard. The PageView itself is **stock Flutter** (`PhotoViewGallery` builds a plain `PageView.builder` inside its gesture scope) — same widget class as ours; the feel difference is the boundary-release logic + controller math, not the PageView |
| 9 | Fast consecutive actions | ⚠️ double-tap-to-unzoom then immediate swipe → the swipe **stops the unzoom and pans instead of switching page**: the friction-tail animation is still running, scale is still >1 when the swipe starts, so the drag is claimed as a pan. Ours has the same flaw in milder form — `handlePointerDown` cancels only the fling, not the 200ms zoom animation |
| 10 | Two-finger pan+zoom | 🔴 **gap in ours**: pinch branch scales around the focal point but ignores focal-point *movement* — can't zoom and pan simultaneously. photo_view does it natively (ScaleGestureRecognizer) |
| 11 | Fling mindset | ✅ **ours preferred**: "fling really fast, then tap to stop" vs photo_view's weak fixed-distance glide ("having to pan several times") |
| 12 | Perceived lag | ⚠️ demo felt slightly laggier on phone. Suspects: 8500×6000 (51MP) decode + `filterQuality: high` during transforms. Both viewers render full-res; a decode-size cap would help both (and the real viewer also has skeleton/thumbnail/backdrop layers burning GPU) |

---

## 4. photo_view internals (verified from installed 0.15.0 source)

### Gesture arena decision (`src/core/photo_view_gesture_detector.dart`)

`PhotoViewGestureRecognizer` extends `ScaleGestureRecognizer`. On every
`PointerMoveEvent`:

```dart
if (validateAxis != null) {
  _computeEvent(event); _updateDistances();
  _decideIfWeAcceptEvent(event);
}
// _decideIfWeAcceptEvent:
final move = initialFocalPoint - currentFocalPoint;
final shouldMove = hitDetector.shouldMove(move, validateAxis);
if (shouldMove || pointerCount > 1) acceptGesture(pointer);
```

Declining = the parent's recognizer (PageView / Dismissible) wins the arena.

### HitCornersDetector (`src/core/photo_view_hit_corners.dart`) — the release logic

```dart
// child (scaled) fits on screen → HitCorners(true, true) → fully clamped
bool _shouldMoveAxis(corners, mainAxisMove, crossAxisMove) {
  if (mainAxisMove == 0) return false;             // cross-axis drag → don't claim
  if (!corners.hasHitAny) return true;             // free pan → claim
  final blocked = corners.hasHitBoth ||
      (corners.hasHitMax ? mainAxisMove > 0 : mainAxisMove < 0);
  return !blocked;                                 // edge-hit → release to parent
}
```

Behavior produced: at 1× → never claims (PageView swipes / Dismissible
dismisses); zoomed → claims pans; **zoomed + clamped at edge → releases →
dismiss/page-swipe works even while zoomed** (iOS-like). Our current mixin does
NOT have the edge-release (dismiss only at exactly 1×) — a real behavioral
difference to decide on.

### The single-axis flaw (finding 4)

`PhotoViewGallery` wraps itself in
`PhotoViewGestureDetectorScope(axis: widget.scrollDirection)` — horizontal for
us, so vertical drags always decline → dismiss fires mid-pan. LoliSnatcher's
fork accepts `axis: Axis.values` (validate both axes: claim if the move can pan
in *either* axis, release only when fully clamped) — that's the entire fork.

### Gallery page options — 0.15.0 vs main

| Capability | 0.15.0 (published) | GitHub main (unreleased) |
|---|---|---|
| Per-page `imageProvider` | ✅ | ✅ |
| Per-page `child` / `childSize` (custom widget) | ❌ | ✅ (`PhotoViewGalleryPageOptions(child: ...)`) |
| Per-page `disableGestures` (zoom off for videos) | ❌ | ✅ |
| `PhotoView.customChild` standalone | ✅ | ✅ |

→ Video pages inside a gallery require the unreleased main or a fork.
Relevant to the fork-vs-own decision.

### Other API bits

- `PhotoViewComputedScale.contained / covered` (+ double multipliers)
- `scaleStateChangedCallback(PhotoViewScaleState)` — initial/zoomingIn/zoomingOut/zoomedIn
- `minScale/maxScale/initialScale`, `scaleStateCycle` (double-tap cycle), `enableRotation`, `tightMode`, `strictScale`, `enablePanAlways`
- Fling: `_positionAnimationController..fling(velocity: 0.4)` (FrictionSimulation) gliding to a **fixed +100px target** (`clampPosition(position + direction * 100)`), guarded by "no scale change + magnitude ≥ 400" — weak and distance-fixed, hence "panning several times" (finding 11)
- Double-tap: `nextScaleState()` → `animateScale` + `animatePosition(→ zero)` + `animateRotation(→ 0)` all driven by `_scaleAnimationController..fling(velocity: 0.4)` — the friction-tail animation behind findings 2 & 9
- License: MIT (`bluefireteam/photo_view`) — porting the math is legally fine

---

## 5. LoliSnatcher reference architecture (`gallery_view_page.dart`)

Local copy: `C:\Users\timka\AppData\Local\Temp\loli_gallery_view_page.dart`
(898 lines). The architecture lesson — **dismiss lives in the viewer, pages are
dumb content**:

- `Dismissible` wraps the **entire** `PreloadPageView`; direction = perpendicular
  to scroll axis (vertical gallery → horizontal dismiss); `dismissThresholds`
  0.2 up/down, 0.3 start/end; `resizeDuration: null`
- `onUpdate` → `dismissProgress` ValueNotifier → `Transform.scale(1 → 0.75)` +
  backdrop `Color.lerp(black → transparent)` + `BorderRadius.lerp(0 → 16)`;
  toolbars hide while dragging; vibration at full progress
- **Opening animation is the reverse**: dismissProgress starts at 1, animates to
  0 over 420ms after push — the route "opens" scaled/rounded and settles
- `onDismissed` → `Navigator.pop()`
- Videos (`VideoViewer`) are **plain children — zero zoom, zero dismiss code**
- Per-item dispatch: ImageViewer / VideoViewer / GuessExtensionViewer /
  LoadItemViewer; only images get zoom
- Guard: `ViewerHandler.maxActiveViewers` — render ≤ ~3 videos at once, others
  get a black placeholder (crash prevention)
- Desktop quirk: comment at the item wrapper — "pageview only scrollable on like
  2px at edges of screen, Windows bug", worked around with ClipRect + GestureDetector
- Their photo_view fork: `github.com/NANI-SORE/photo_view` @
  `410b4c26d7b4747e88ca2227a88fe7ad707679f1` (the `Axis.values` fix)

---

## 6. Direction & open questions

User's leaning: **write our own, adapting photo_view's principles** (not fork,
not adopt stock). Shape of the refactor:

1. **Input shell stays raw `Listener`** — wheel zoom works, mouse works, no
   gesture arena at all. `_ZoomableMixin` keeps its input handling.
2. **Port photo_view's controller math** into a plain Dart controller class
   (MIT): scale/pan boundary computation (contained/covered), pan clamping,
   fling via `AnimationController.fling` (decide vs current ticker), double-tap
   cycle (decide tap-point vs center), and `HitCornersDetector` edge-release
   ("claim pan only when the move can move the image, else hand off").
3. **Dismiss at viewer level** (`_FullscreenPageViewInner`): LoliSnatcher
   pattern — one gesture, whole-PageView transform + backdrop fade; gated by
   the edge-release logic so dismiss fires when zoomed-and-clamped.
4. **One shared video surface** (source seam: remote URL vs archive-extract →
   temp file) — kills both the 2× dismiss copies and 2× player/controls copies.
5. **`ScrollConfiguration` mouse fix** on the viewer's PageView (also fixes the
   current viewer's mouse paging).

Open decisions (updated after the phone test):

- Double-tap behavior: **combine** — photo_view's contained→covered→… cycle, but
  targeting the tap point (extended_image behavior), driven by a short timed
  curve (200–250ms easeOut) instead of photo_view's friction tail
- Animation interruption: on pointer-down **cancel any running zoom/fling
  animation** (ours currently cancels only the fling, not the 200ms zoom anim);
  if the cancelled animation was heading to 1× and a swipe starts, **snap to 1×
  immediately** so the swipe pages instead of panning (fixes finding 9)
- Fling physics: **keep ours** — velocity-proportional ticker, tap-to-stop
  (finding 11; confirmed user preference)
- Two-finger pan+zoom: **add** focal-point panning to the 2-pointer pinch
  branch (finding 10)
- Edge-release (HitCornersDetector): **adopt** — phone test confirmed the
  zoomed-at-edge page-swipe feel (finding 8); also gates the viewer-level
  dismiss. See `future-boundary-aware-gestures.md`
- Decode-size cap: 51MP images (finding 12) — evaluate a max-dimension cap
  (e.g. ~2× screen resolution) at decode; applies to both viewers
- Touch pan/slop thresholds: keep current values until the port lands, then
  re-tune on phone
- Whether to keep the demo screen until the port lands, then delete

### 6.1 Package extraction (2026-07-31, updated)

The app's reusable widgets become **one umbrella package** — `leaf_widgets`
(checked 2026-07-31: free on pub.dev). Rationale: every leaf widget is pure
Flutter with zero external deps, so the package adds no transitive
dependencies and no meaningful size (tree-shaking drops unused widgets). The
"one widget per package" split only pays off with real dependency weight —
there is none here. Not `leaf_photo_view` (reads as a fork of photo_view,
undersells scope — pages are arbitrary widgets).

- **Location**: `S:\G_drive_backup\.Projects\SoyDev\Flutter\leaf_widgets\`,
  own git repo, package root at repo root; app depends via pubspec `path:`
  dependency.
- **Contents** (moved from `lib/src/widgets/` + the new viewer):
  - viewer: `LeafViewer` + `LeafZoomController` (the refactor)
  - `LeafContextMenu` (from `FContextMenu`), `LeafPopover` (from `FPopover`)
  - `animated_favorite_button`, `animated_star`, `leaf_image`
  - Structure: `lib/src/{viewer, context_menu, popover, misc}/` + barrel
    `lib/leaf_widgets.dart`
  - **Prefix unification at extraction time**: F* → Leaf* (FContextMenu →
    LeafContextMenu, FPopover → LeafPopover; rename app call sites)
- **Stays in the app**: `search_bar.dart` (coupled to `signals` — would break
  zero-dep purity), screens, providers, chrome.
- **API sketch**: `LeafViewer.builder(pageCount, pageBuilder,
  scrollDirection, initialPage, onPageChanged, dismissEnabled, onDismissed,
  backgroundBuilder, chromeBuilder)` + per-page `LeafZoomController`; state
  via ValueNotifier / InheritedWidget (our `_ZoomReporter` pattern).
- **Package keeps**: zoom controller math (ported, MIT header), HitCorners
  edge-release, viewer-level dismiss, wheel zoom, double-tap cycle with
  tap-point targeting, velocity fling, two-finger focal pan, animation-cancel
  + snap-to-1×, ScrollConfiguration mouse fix.
- **App keeps**: KemonoImageProvider, ImageMetaStore, skeleton/thumbnail
  chrome, archives, media_kit video surface, arrows/counter, keyboard nav.
  `_ZoomableMixin`, `_FullscreenPageViewInner` and the dismiss logic get
  deleted; pages become plain content widgets.
- **`example/` app** = widget gallery + feel-test harness (replaces the demo
  screen); also isolates viewer cost from app overhead (finding 12).

---

## 7. References

- photo_view (upstream): https://github.com/bluefireteam/photo_view · https://pub.dev/packages/photo_view (0.15.0 installed)
- Key sources: `lib/photo_view_gallery.dart`, `lib/src/core/photo_view_gesture_detector.dart`, `lib/src/core/photo_view_hit_corners.dart`, `lib/src/core/photo_view_core.dart`, `lib/src/photo_view_computed_scale.dart`, `lib/src/photo_view_scale_state.dart`
- LoliSnatcher: https://github.com/NO-ob/LoliSnatcher_Droid — `lib/src/pages/gallery_view_page.dart`
- LoliSnatcher's photo_view fork: https://github.com/NANI-SORE/photo_view @ `410b4c2`
- Flutter `dragDevices`: `Z:\.Programs\flutter\packages\flutter\lib\src\widgets\scroll_configuration.dart` (`_kTouchLikeDeviceTypes`, line 29)
- Our history: `f1da53c` (ExtendedImage → custom viewer, "replicates extended_image's calculateFinalDestinationRect"), `5354834`, `387368e` (raw-pointer viewer milestone)
- This project: `docs/future-boundary-aware-gestures.md`, `docs/problems.md`, `lib/src/screens/photo_view_demo_screen.dart`
