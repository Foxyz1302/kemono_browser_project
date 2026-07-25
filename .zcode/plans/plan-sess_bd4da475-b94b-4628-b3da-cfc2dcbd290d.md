## Plan: Unify image viewer + archive cache

### Problems to solve

1. **`open()` and `openArchive()` share almost nothing** — one is a pure dark overlay with PageView, the other is a Scaffold with AppBar for a single image. Both should be: dark overlay + fullscreen PageView + InteractiveViewer per page + lazy load + tap-to-dismiss.
2. **Archive images can't be swiped** — `openArchive()` receives a single `Uint8List`, not a list. The archive is already fully downloaded on disk with all entries accessible.
3. **Archive downloads are ephemeral** — temp dir, deleted on `_ArchiveTile.dispose()`. Accidentally navigate away? Redownload the entire archive.
4. **Duplicated helper widgets** — `_NavArrow`, `_ClockwiseBorderPainter` are copied between files.

---

### Architecture (post-refactor)

```
FullscreenImageViewerScreen
│
├── _openCore()  ← private, shared by both
│   ├── PageRouteBuilder(dark overlay)
│   ├── KeyboardListener (← → Esc)
│   ├── GestureDetector (tap to dismiss)
│   ├── Stack(StackFit.expand)
│   │   ├── PageView(initialPage)
│   │   │   └── pageBuilder(index) → page widget
│   │   ├── Nav arrows (if >1 item)
│   │   └── Page counter overlay (bottom center: "archive.zip — 3 / 24")
│   └── FadeTransition
│
├── open() ──→ pageBuilder = _FullscreenPage(url, thumbUrl, ...)
│                 loads via KemonoImageProvider (URL → stream → ImageInfo)
│
├── openArchive() ──→ pageBuilder = _ArchiveArchivePage(service, localPath, path)
│                       loads via archiveService.readEntry() (disk → Uint8List)
│
└── (future sources use the same _openCore)
```

Both page widgets share a `ZoomableImageMixin` for InteractiveViewer gesture handling:

```dart
mixin ZoomableImageMixin<T extends StatefulWidget> on State<T> {
  TransformationController _transformController;
  bool _isZoomed;
  
  void initZoomable() { ... listener ... }
  void disposeZoomable() { ... }
  void resetZoom() { _transformController.value = Matrix4.identity(); }
  
  Widget wrapZoomable(Widget imageWidget) {
    return InteractiveViewer(
      transformationController: _transformController,
      panEnabled: _isZoomed,    // ← dynamic, from controller listener
      minScale: 0.5, maxScale: 5.0,
      boundaryMargin: EdgeInsets.zero,
      child: Center(
        child: ClipRRect(borderRadius: 15, child: imageWidget),
      ),
    );
  }
}
```

---

### File changes

| File | Action |
|------|--------|
| `lib/src/screens/fullscreen_image_viewer_screen.dart` | **Rewrite** — extract `_openCore()`, add `_ArchiveArchivePage`, remove old `openArchive()` |
| `lib/src/archive/archive_cache.dart` | **New** — persistent archive cache (max 10, LRU eviction) |
| `lib/src/archive/archive_service.dart` | **Minor** — no functional change needed |
| `lib/src/screens/creator_posts_screen.dart` | **Update** — `_ArchiveTile` uses cache + new `openArchive()` API |
| `lib/src/screens/archive_browser_screen.dart` | **Update** — dead code? Check if it can be removed or updated |

---

### Detailed: `_openCore()` (extracted shared method)

```dart
static void _openCore(
  BuildContext context, {
  required int itemCount,
  required int initialIndex,
  String? subtitle,     // e.g. "archive.zip — " — shown before page counter
  required Widget Function(BuildContext, int index) pageBuilder,
}) {
  // PageController, FocusNode, signals for currentIndex
  // goTo() helper
  // Navigator.push(PageRouteBuilder):
  //   Material(transparency)
  //     KeyboardListener(← → Esc)
  //       GestureDetector(onTap → pop)
  //         Stack(StackFit.expand)
  //           SignalBuilder > PageView.builder(pageBuilder)
  //           if >1: Positioned nav arrows left/right
  //           Positioned(bottom: overlay with subtitle + page counter)
  // .then → dispose controller + focus
}
```

Differences from current `open()`:
- Adds `subtitle` parameter for archive name prefix
- Adds page counter overlay (bottom center, semi-transparent)
- `pageBuilder` replaces hardcoded `_FullscreenPage` creation
- No `currentAspectRatio` signal (it was unused for display anyway)

---

### Detailed: New `openArchive()` → delegates to `_openCore()`

```dart
static void openArchive(
  BuildContext context, {
  required ArchiveService archiveService,
  required String localPath,
  required List<String> entries,    // all image entry paths, ordered
  required int initialIndex,
  String? archiveName,
}) {
  final imageEntries = entries.where((e) {
    final ext = p.extension(e).toLowerCase();
    return _imageExts.contains(ext);
  }).toList();
  if (imageEntries.isEmpty) return;

  _openCore(
    context,
    itemCount: imageEntries.length,
    initialIndex: initialIndex.clamp(0, imageEntries.length - 1),
    subtitle: archiveName != null ? '$archiveName — ' : null,
    pageBuilder: (context, index) {
      final entryPath = imageEntries[index];
      return _ArchivePage(
        key: ValueKey('archive_$index'),
        archiveService: archiveService,
        localPath: localPath,
        entryPath: entryPath,
      );
    },
  );
}
```

---

### Detailed: `_ArchivePage` widget

Same bones as `_FullscreenPage` but loads from disk instead of URL:

```dart
class _ArchivePageState extends State<_ArchivePage> with ZoomableImageMixin {
  Uint8List? _data;
  bool _errored = false;
  
  void initState() {
    super.initState();
    initZoomable();
    _load();
  }
  
  Future<void> _load() async {
    try {
      final data = await widget.archiveService.readEntry(widget.localPath, widget.entryPath);
      if (mounted) setState(() { _data = data; });
    } catch (e) {
      debugPrint('Archive page load error: $e');
      if (mounted) setState(() => _errored = true);
    }
  }
  
  Widget build(BuildContext context) {
    if (_errored) return errorWidget;
    if (_data != null) {
      return wrapZoomable(Image.memory(_data!, fit: BoxFit.contain));
    }
    return Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38));
  }
}
```

No progress skeleton needed — archive reads are local disk operations, typically < 500ms.

---

### Detailed: Archive cache

**New file:** `lib/src/archive/archive_cache.dart`

```
{appDocDir}/archive_cache/
  manifest.json   ← List<{url, localPath, cachedAt, lastAccessedAt, fileSize, entryCount}>
  archive_0.zip
  archive_1.zip
  ...
```

```dart
class ArchiveCache {
  static final ArchiveCache instance = ArchiveCache._();
  
  static const _maxArchives = 10;
  
  String? _cachePath;
  List<CacheEntry> _entries = [];
  
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _cachePath = p.join(appDir.path, 'archive_cache');
    await Directory(_cachePath!).create(recursive: true);
    await _loadManifest();
  }
  
  /// Returns local path. Downloads if not cached.
  Future<String> getOrDownload(String url, ArchiveService service, {void Function(int, int)? onProgress}) async {
    // 1. Check manifest for url
    // 2. If found and file exists → touch lastAccessedAt, return localPath
    // 3. If file missing → remove from manifest, fall through to download
    // 4. Download to cache dir with unique name
    // 5. Add to manifest, save manifest
    // 6. If count > _maxArchives, evict LRU
    // 7. Return localPath
  }
  
  void touch(String url) { ... update lastAccessedAt, save ... }
  
  Future<void> evictLRU() async { ... remove oldest, delete file, save manifest ... }
  
  Future<void> clearAll() async { ... delete all files, reset manifest ... }
}
```

**Integration with `_ArchiveTile`:**
- Constructor no longer takes `tempDir` (replaced by cache)
- `_start()` calls `ArchiveCache.instance.getOrDownload(url, service)` instead of `service.downloadArchive(url, tempDir)`
- `dispose()` no longer calls `deleteArchivedFile` — cache manages lifecycle
- On app start: `ArchiveCache.instance.init()` is called once (e.g. in `main.dart` or `PawchiveClient.init`)

---

### Detailed: Updated `_ArchiveTile` onTap

**Old** (reads entry → passes Uint8List → single-image viewer):
```dart
onTap: () async {
  final data = await archiveService.readEntry(_localPath, path);
  widget.onTapImage!(data, path);  // → openArchive(data, fileName, archiveName)
}
```

**New** (passes full entry list → PageView viewer):
```dart
onTap: () {
  final imageEntries = _entries.where((e) => _isImageExt(e)).toList();
  final index = imageEntries.indexOf(path);
  FullscreenImageViewerScreen.openArchive(
    context,
    archiveService: widget.archiveService,
    localPath: _localPath,
    entries: imageEntries,
    initialIndex: index >= 0 ? index : 0,
    archiveName: widget.fileName,
  );
}
```

The `onTapImage` callback on `_ArchiveTile` can be **removed** since the tile now opens the viewer directly. This simplifies the constructor.

---

### Detailed: Updated caller in post detail

```dart
// Before:
_ArchiveTile(
  fileUrl: fileUrl,
  fileName: f.name ?? 'archive',
  archiveService: ArchiveService(PawchiveClient.instance.dio),
  tempDir: Directory.systemTemp.createTempSync('archive_').path,
  onTapImage: ...
)

// After:
_ArchiveTile(
  fileUrl: fileUrl,
  fileName: f.name ?? 'archive',
  archiveService: ArchiveService(PawchiveClient.instance.dio),
  // no tempDir, no onTapImage — tile handles it internally
)
```

---

### Folder structure in archives

Not handled in this pass. The plan doesn't block it:
- Preview grid: currently flat (first 8 entries). Could be sectioned later (group by top-level folder with headers).
- PageView: always flat, overlay shows `"folder/image.jpg"` as the page subtitle. The entry path is already available.
- Any future folder-aware logic would be in `_ArchiveTile` and the PageView's overlay rendering — not in the core viewer.

---

### Files to keep untouched

- `lib/src/screens/image_viewer_screen.dart` — original `MyImageViewerScreen` / `ImageViewerScreen`, left as-is
- `lib/src/cache/image_meta_store.dart` — unchanged
- `lib/src/cache/kemono_image_provider.dart` — unchanged
- `lib/src/state/app_state.dart`, `auth_state.dart` — unchanged

---

### Migration / testing

1. After implementing, update `main.dart` or `PawchiveClient.init()` to call `ArchiveCache.instance.init()`
2. Run `dart analyze` on all modified files
3. Test flow: open post → tap archive → download → see grid → tap thumbnail → swipe through all archive images → close
4. Test cache: close post → reopen → archive should load from cache instantly
5. Test eviction: download 11+ archives → oldest should be evicted

### Allowed permissions
- `Bash` for `dart analyze`
