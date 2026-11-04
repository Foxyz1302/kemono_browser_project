# Downloads Portal — Design

Planning doc for the downloads portal + the cache/downloads line-drawing that
underlies it. Status: **design in progress — model agreed, no code yet.**

Related: `photo-view-evaluation.md` (viewer refactor, done), `problems.md`
(#7/#8/#14/#15/#21), the post/archive file-view unification (separate thread,
this doc builds on its seams).

---

## 1. Goal

Preview-first browsing where nothing forces the user to sit on a screen while
a large file transfers:

- Preview images, files, posts — already possible (thumbs, fullscreen pager,
  post dialog). **Archives are the gap**: previewing a zip requires the whole
  download, and today that download's progress UI dies with the tile
  (`_ArchiveTileState.dispose` is empty, `creator_posts_screen.dart:1345` —
  dio keeps running, `onProgress` drops `if (!mounted)`).
- A bottom-left floating button → downloads popover: track transfers in the
  background, open the finished artifact, cancel, delete, go to the source post.
- Future payload (Phase 3 storage): save individual images/files/posts for
  real — same manager, new destination.

## 2. The line: cache vs downloads

They look like the same thing because `ArchiveCache` both **stores** archives
and **performs** the download. Separate the axes:

| Axis | Question | Owned by |
|------|----------|----------|
| **Storage** | Where do bytes live? When are they evicted? | Image cache (ephemeral, `flutter_cache_manager`), `ArchiveCache` (ephemeral **preview** store, LRU 10, `archive_cache.dart:21`), favorites tree (persistent **saves** store — *not implemented*, `app_state.dart` has only API-level favorites `:269,:289`) |
| **Transfers** | What is transferring right now? Progress, cancel, what happens when it lands? | `DownloadManager` (new) — runtime task registry, single-flight dedup, completion events → portal + tiles |

A **task is not a cache entry** (transient process) and a **cache entry is not
a task** (stored artifact). The same URL is both while downloading: task in
flight → lands as an ArchiveCache entry. Folding tasks into ArchiveCache would
conflate LRU eviction with the user's download list — previewing 11 archives
would silently evict #1 out from under "delete" semantics. Keep them separate.

Consequence for "preview": **for archives, preview = download**. The download
must be backgroundable: tile starts a task → user navigates away → manager
continues → archive is ready globally (tiles already check
`ArchiveCache.getFileSize` on init, `creator_posts_screen.dart:1350`).

## 3. Task model

```dart
enum DownloadKind { archivePreview, saveFile, savePost }  // v1: archivePreview only

enum DownloadState { queued, downloading, done, error, cancelled }

class DownloadTask {
  final String url;                       // dedup key
  final String fileName;
  final DownloadKind kind;
  final String? service, creatorId, postId;   // go-to-post
  final Signal<DownloadState> state;
  final Signal<int> received, total;
  final CancelToken cancelToken;          // ArchiveCache already threads one through (`archive_cache.dart:51`)
  final DateTime createdAt;
}
```

### DownloadManager

```dart
class DownloadManager {
  static final instance = DownloadManager._();
  final Signal<List<DownloadTask>> tasks = signal([]);   // newest last; reactive via SignalBuilder
  DownloadTask? taskFor(String url);

  DownloadTask startArchivePreview({required String url, required String fileName,
      required ArchiveService service, String? creatorId, String? postId});
  Future<void> cancel(DownloadTask task);    // token.cancel() → dio throws → ArchiveCache cleans partial → state=cancelled
  Future<void> delete(DownloadTask task);    // done/error → ArchiveCache.remove(url) (`archive_cache.dart:127`) + drop from list
  void dismiss(DownloadTask task);           // just drop from the list
}
```

- **Single-flight by URL** — a second request for an in-flight URL joins the
  existing task instead of starting a second dio download. This **is** the fix
  for the missing in-flight dedup in `ArchiveCache.getOrDownload` (problems.md
  #8).
- `startArchivePreview` drives `ArchiveCache.getOrDownload(url, service,
  onProgress: task.received/total, cancelToken: task.cancelToken)`. On
  completion the ArchiveCache manifest is the persistence — the task list
  itself is **runtime-only** (a restart shows completed previews via the
  manifest, not via the portal history).
- **Cancel semantics (v1): cancel = discard.** `getOrDownload` already deletes
  the partial file on error (`archive_cache.dart:83`). No resume via Range
  requests. (If a resume feature ever lands, the task model gains a
  `partialBytes` — out of scope.)

## 4. Flows

### Archive preview (v1 payload)

- `_ArchiveTile._start()` → `DownloadManager.instance.startArchivePreview(...)`.
  The tile becomes a **view of the task**: progress bars read task signals,
  cancel calls `manager.cancel(task)`. Local `_downloadedBytes/_totalBytes/`
  `_downloadProgress` state is deleted.
- Navigate away mid-download: task lives on in the manager; download continues.
- Done: portal row shows "Open" → archive media pager
  (`FullscreenImageViewerScreen.openArchive`) and "Go to post". Revisiting the
  post's tile shows the ready grid instantly (manifest hit).
- Delete: `manager.delete(task)` → `ArchiveCache.remove(url)` — file + manifest
  entry gone, task dropped.

### Save flows (future — Phase 3 storage)

- "Save image / save file / save post": favorite API call (exists) **plus**
  copy into `favorites/{service}/{creator}/{post}/files/` + `_meta.json`
  (does not exist — to be built). Long copies (big files, post batches) become
  tasks through the same manager, same portal, same cancel.
- Saved artifacts live in the favorites tree, **outside** ArchiveCache's LRU —
  the destination difference is what keeps "cache" and "downloads" distinct.

### Go to post

- Portal row → `Navigator.push(MaterialPageRoute(builder: (_) =>
  CreatorPostsScreen(creator)))` (pattern: `home_screen.dart:495`) then open
  `PostDetailDialog` after a frame. Requires resolving `Creator` from
  `service/creatorId` (creator store / cached `creators` list).

## 5. Portal UI

- **Button**: root-mounted overlay (downloads start from pushed routes and
  dialogs, so a per-screen FAB won't do). Mounted in `main.dart` above the
  `_AuthRouter` output (or the home scaffold's `Stack`). Bottom-left; visible
  while any task exists; badge = active count (`SignalBuilder` over `tasks`).
- **Popover**: anchored panel via the existing `LeafPopover`/OverlayPortal
  pattern (`lib/src/widgets/popover.dart`). Rows:
  - kind icon + fileName (ellipsis), archive size when known
  - downloading: progress bar + `x / y` + % (reactive via signals)
  - state chip: Downloading / Done / Error / Cancelled
  - actions: **Cancel** (downloading), **Delete** (done/error/cancelled →
    `manager.delete`), **Open** (done → archive pager), **Go to post** (done)
  - Empty state: "No downloads"
- Close on outside-tap / Esc (same as context menu & popover conventions;
  fixes the stale-position concern by re-anchoring, `problems.md` #28).
- Desktop-first: mouse click opens, no touch-only paths.

## 6. Integration & ordering

This doc's portal lands **after** the post/archive file-view unification (tile
refactored once, not twice). Order:

1. **`leaf_widgets`**: add `cacheWidth`/`cacheHeight` passthrough to `LeafImage`
   (missing today — `leaf_image.dart:321` forwards fit/alignment/width/height
   but not those). Needed for downscaled archive thumbs (`Image.file(File(path),
   cacheWidth: …)`) and grid thumbs (fixes #14).
2. **Unification** (separate thread): shared `MediaSource`, one media grid for
   post attachments + archive contents, one `openMedia` pager entry, lazy
   extract-to-temp thumbs, delete `image_viewer_screen.dart` +
   `archive_browser_screen.dart`. `_ArchiveTile`'s ready state renders the
   unified grid; its download state machine is rewritten **once** into the
   manager-backed shape.
3. **This portal**: `DownloadManager` + root overlay + popover; ArchiveCache
   gains in-flight dedup (#8) via manager single-flight.

## 7. Open questions

- **Archive preview browser**: the dead `ArchiveBrowserDialog`
  (`archive_browser_screen.dart`) is a natural full-archive *preview* view
  (grid + filenames + per-file open). Revive it as the portal's "Open" target,
  or keep the media pager only? (Deletion is already planned in the
  unification — decision affects whether it's deleted or moved.)
- **Completed-task lifetime**: keep done tasks until explicit dismiss/delete
  (current intent) vs auto-clear after N — portal stays meaningful as "recent
  downloads".
- **Badge scope**: count only `downloading`, or also show done-but-not-dismissed?
- **Save-flows scope**: build Phase 3 favorites storage first, or land the
  portal on archive previews and add saves when storage exists?
