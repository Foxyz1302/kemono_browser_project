# App Problems & Improvement Opportunities

Compiled from a comprehensive code review on 2026-07-27. Findings are grouped by severity. Each item includes the file location and enough context to reproduce or act on the issue.

---

## 🔴 Critical Bugs

### 1. Dead card tap on post tiles
**File:** `lib/src/screens/creator_posts_screen.dart:273-279`
**Severity:** Users can't open post details by tapping the card body.

A childless `InkWell` is placed inside a `Stack` with the default `StackFit.loose`. With no child and loose constraints, the InkWell sizes to **zero** — the card-wide tap target doesn't exist. Tapping the text/column area of a post does nothing; only the 48px thumbnail row at the bottom opens the viewer.

The fix must also ensure the overlay does not *swallow* thumbnail taps: the preview-thumbnail `GestureDetector`s (line 240) are laid out after the overlay in the children list, so they render on top, but a `Positioned.fill` on the overlay would spread it over them too. Either:
- Move the overlay before the thumbnails in the children list, or
- Use `Positioned.fill` on the overlay and restack the thumbnails above it (with a higher z-index child after the overlay).

### 2. Login success detection accepts failed logins
**File:** `lib/src/api/pawchive_client.dart:62-68`
**Severity:** Bad credentials get saved to Hive and poison every cold start.

The method treats any 302 that has a `Location` or `Set-Cookie` header as login success. Kemono-style backends also 302-redirect on *failed* logins — back to `/account/login`. The check must verify the `location` contains `logged_in=yes` (or at minimum does not point back to `/account/login`).

Consequence: a mistyped password returns 302 → credentials saved → `restoreSession()` loops forever into `AuthStatus.error` on every launch, and the error is invisible (see #22).

### 3. Logout does not clear the session cookie
**File:** `lib/src/state/auth_state.dart:70-75`
**Severity:** "Logged out" user is still authenticated to all cookie-guarded endpoints.

```dart
Future<void> logout() async {
  await _box.delete('username');
  await _box.delete('password');
  authStatus.value = AuthStatus.loggedOut;
  errorMsg.value = null;
}
```

The `PersistCookieJar` still holds the `session` cookie and `CookieManager` keeps attaching it to every request. After "logout", all favorite/account API calls still return data.

Fix: add `await PawchiveClient.instance.cookieJar?.deleteAll()` (and ideally a server-side logout call).

### 4. Login/logout race — stale login can re-save credentials after logout
**File:** `lib/src/state/auth_state.dart:25-58` + `lib/src/screens/home_screen.dart:157`
**Severity:** User can end up re-authenticated after explicitly logging out.

`login()` has no cancellation token or generation counter. If the user taps logout while `restoreSession()`/`login()` is in-flight, the completion handler at lines 31-35 will `put` username/password back into Hive and set `authStatus = loggedIn` *after* logout deleted them.

### 5. Cross-creator post race — posts from one creator shown under another
**File:** `lib/src/state/app_state.dart:97-113`
**Severity:** Stale/incorrect data visible to user.

`loadCreatorPosts` has no concurrency guard or request token. `CreatorPostsScreen.initState` fires it on every navigation. Rapidly opening creator A then creator B lets A's slower response overwrite `creatorPosts` after B was selected — the screen shows A's posts under B's name.

Fix: capture the `Creator` at call time; only assign `creatorPosts` if the same creator is still selected when the response arrives.

### 6. Download cancellation kills shared downloads (same URL used by multiple widgets)
**Files:**
- `lib/src/cache/kemono_image_provider.dart:48-50` (cancel callback)
- `lib/src/cache/kemono_image_provider.dart:88-95` (error path)
- `lib/src/cache/dio_file_service.dart:24-25,36-38` (token map)

`flutter_cache_manager`'s `WebHelper` dedupes concurrent downloads per cache key — all widgets requesting the same URL share one `FileService.get` call and one `CancelToken`. When *any one* `ImageStreamCompleter` loses its last listener (e.g. a grid tile scrolls off-screen), `cancelRequest(url)` cancels the token that other still-visible widgets depend on.

Worse, the cancellation error flows into the catch block at line 88 which always evicts from memory cache, deletes the partially-downloaded file from disk (`removeFile`), and rethrows — all without checking whether the error was a benign cancel.

The token map in `DioFileService` is a `Map<String, CancelToken>`; two concurrent requests for the same URL would clobber the first token, and the first `finally` block would remove the second's token — the wrong request gets cancelled.

### 7. FutureBuilder futures created inside build() — archive entries re-decompress on every rebuild
**Files:**
- `lib/src/screens/creator_posts_screen.dart:1245-1247` (`_ArchiveTile._buildReady`)
- `lib/src/screens/archive_browser_screen.dart:186-187`

```dart
future: widget.archiveService.readEntry(_localPath, path)
```

A new `Future` is created every build. `FutureBuilder` goes back to `ConnectionState.waiting` on each rebuild, flashing spinners and re-decompressing the archive entry from scratch. Scrolling the grid away and back re-reads every visible entry.

Fix: cache futures in state (e.g. `Map<String, Future<Uint8List>>`).

### 8. Archive cache has no in-flight dedup — concurrent downloads of the same URL race
**File:** `lib/src/archive/archive_cache.dart:47-107`

`getOrDownload` checks the manifest, then downloads. Two callers pointing at the same file (or one retry racing a still-running first attempt) both miss the manifest and both call `dio.download` to the **same** `localPath` concurrently → interleaved writes/corrupted zip, and duplicate manifest entries (`_entries.add` at line 94 runs twice).

### 9. Archive manifest + meta store writes are non-atomic
**Files:**
- `lib/src/archive/archive_cache.dart:110-116, 192-199`
- `lib/src/cache/image_meta_store.dart:248-258`

Both write via `writeAsString` (truncate-then-write). A crash midway corrupts the file. On next launch:
- Archive cache reads the truncated JSON, catch-block sets `_entries = []`, **all** downloaded archives are orphaned forever (no recovery scan).
- Image meta store reads the truncated JSON, catch-block starts with an empty `_entries`, all per-creator/per-post cache stats are lost.

Archive filenames also use `url.hashCode` (`archive_cache.dart:206`), which is not stable across VM runs — after a manifest loss, the same URL downloads to a *different* filename and orphans the old file.

### 10. Meta store `record()` first-writer-wins prevents creator/post association from being set
**File:** `lib/src/cache/image_meta_store.dart:88`

```dart
if (_entries.containsKey(url) || !_inFlight.add(url)) return _entries[url];
```

First writer wins, and first writer often has no context: `prefetchDims` loads without creatorId/postId, and banner/icons are loaded bare. Once recorded, later loads *with* creatorId/postId hit the early-return and the association is never set. All stats (`bytesForCreator`, `fileCountForCreator`, `postsForCreator`, purge functions, "cached only" filter) silently undercount.

---

## 🟠 Performance

### 11. Full 89K-creator filter+sort on every signal change — no memoization
**File:** `lib/src/state/app_state.dart:37-76`

`filteredCreators` is a plain getter, not a `computed()`:
- Every signal change (including `metaReady` from a single image finishing) runs the O(n log n) sort over ~89K items on the UI thread.
- When `showCachedOnly` or `SortBy.cacheSize` is active, it reads `metaReady.value` — see #12 — so every image caching event triggers a full re-sort.
- The `SearchBar` writes `searchQuery` on every keystroke, with the 150ms debounce gating only the unused `onSearch` callback.

Additionally, `FixedHeightGridDelegate.shouldRelayout` (`home_screen.dart:412-413`) unconditionally returns `true`, forcing grid relayout on every build.

### 12. `metaReady` signal incremented per-record causes O(n²) rebuilds while scrolling
**File:** `lib/src/cache/image_meta_store.dart:106`

Every single image record increments `metaReady.value++`. Subscribers iterate all entries on each increment: `app_state.dart:45-63` rebuilds per-creator cache maps; `home_screen.dart:533-536` similar. Scrolling a fresh feed with N images × M stored entries = N×M work on the UI isolate.

### 13. Provider key equality includes creatorId/postId — memory-cache duplication
**File:** `lib/src/cache/kemono_image_provider.dart:99-108`

The same image URL with different `creatorId`/`postId` (grid tile vs. banner vs. viewer) produces different `ImageProvider` keys → separate `ImageCache` entries → the same bytes decoded and held in memory multiple times. `creatorId`/`postId` don't affect the decoded image; they should be excluded from `==`/`hashCode`.

### 14. Full-resolution image decoding for small rendering targets
**Files:**
- `home_screen.dart:437-438` — banners decoded at full size for a ~360×120 tile.
- `creator_posts_screen.dart:1265` — archive thumbnails use `Image.memory` with no `cacheWidth`/`cacheHeight` for a ~90px grid cell.
- `creator_posts_screen.dart:256` — grid preview images decoded at full res.

No call site wraps with `ResizeImage` or `cacheWidth`. Combined, this thrashes the default 100MB/1000-image `ImageCache` on scroll-heavy feeds.

### 15. Archive decompression on the UI isolate
**File:** `lib/src/archive/archive_service.dart:57-96`

`openArchiveFile`/`readBytes` (koni_archive) decompress synchronously on the caller's isolate. `_ArchiveTile._buildReady` fires up to 8 concurrent `readEntry` calls, each opening and closing the archive independently. A large zip visibly janks/freezes the UI. Should wrap in `Isolate.run` and reuse one archive handle for multi-entry reads.

### 16. `DioFileService` has no timeouts + `_activeTokens` overwrite
**File:** `lib/src/cache/dio_file_service.dart:9-16, 24-25, 36-38`
- No `connectTimeout`/`receiveTimeout` — a stalled socket hangs the download slot forever.
- Token map is `Map<String, CancelToken>`; concurrent requests overwrite the active token (see #6).

### 17. Bogus request header on creators endpoint
**File:** `lib/src/api/pawchive_client.dart:89`

```dart
options: Options(headers: {'Accept': 'text/css'}),
```

A copy-paste error; should be `application/json` or omitted.

### 18. Meta store never reconciled with cache-manager evictions
**File:** `lib/src/cache/image_meta_store.dart`

The cache manager evicts at 1000 objects / 30-day stale (configured in `image_cache_service.dart:41-46`), but nothing removes those URLs from `ImageMetaStore._entries`. `bytesForCreator`/`fileCountForCreator`/`postsForCreator` count bytes for files that no longer exist on disk. The documented `purgeStale()` method (from AGENTS.md) **does not exist** — only a load-time cutoff filter runs at startup.

### 19. `prefetchDims` uses a different cache key than the provider
**File:** `lib/src/cache/image_cache_service.dart:72-88`

`getSingleFile(url)` stores under the full URL (including `?f={filename}`), while `KemonoImageProvider` keys by `url.split('?').first`. A prefetched full-size image gets stored under a key the provider never looks up → duplicate disk entry + guaranteed re-download on view. (Latent — `prefetchDims` has no callers, but it's a landmine.)

### 20. JPEG header parser boundary off-by-one + 64KB EXIF limit
**File:** `lib/src/cache/image_size_parser.dart:56`

```dart
while (i + 9 < d.length) {
```

When `i + 9 == d.length` exactly, a valid SOF at the buffer end is skipped (needs `<=`). More critically, camera JPEGs frequently carry APP1/EXIF segments >64KB before the SOF marker, so `parse` returns null and every such image triggers a full-decode fallback that loads the whole file into the UI isolate heap (`image_meta_store.dart:117-129`) without the `codec.dispose()` in a `finally` block.

---

## 🟡 Code-Architecture Disconnects

### 21. ~1,000 lines of dead code
| File | Lines | What |
|------|-------|------|
| `lib/src/screens/image_viewer_screen.dart` | 697 | **Two** full viewer implementations (`MyImageViewerScreen` + `ImageViewerScreen`/`_ImageViewerBody`), both unreferenced from any other file |
| `lib/src/screens/archive_browser_screen.dart` | 280 | Standalone archive browser dialog, unreferenced, duplicates `_ArchiveTile` flow with different download semantics |
| `lib/src/api/creator_store.dart` | ~110 | Full creator index with line-delimited JSON streaming, intended to avoid 72MB memory spike — but the app sidesteps it entirely and does `response.data as List` on 12MB JSON directly |
| `lib/src/screens/creator_posts_screen.dart:348-388` | ~40 | `ExpandOnLoadImage` widget — unused |
| `lib/src/archive/archive_service.dart:98-115` | ~18 | `extractAll`/`extractEntry`/`deleteArchivedFile` — unused |
| `lib/src/cache/image_cache_service.dart:72-88` | ~16 | `prefetchDims`/`purgeUrls`/`bytesForUrls` — unused |
| `lib/src/cache/image_meta_store.dart:143-195` | ~50 | `postCachedBytes`/`postHasMeta`/`totalTrackedBytes`/`entryCount` — unused |
| `lib/src/state/app_state.dart:28` | 1 | `selectedCreator` signal — written but never read (screens use `widget.creator`) |

Total: ~1,200 lines of drifting duplicate or dead code.

### 22. AGENTS.md documents Phase 3 features that don't exist
The following sections in AGENTS.md describe code that is **not implemented**:

- **Server Favorites** — the endpoint table and the full merge sync flow
- **Favorites Merge Strategy** — login-time reconciliation
- **New Post Detection** — `updated` vs `lastChecked` comparison, badges
- **Storage** — `_meta.json` tree, favorites directory structure
- `creators.json` disk caching — the app re-downloads 12MB every cold start
- `purgeStale()` in ImageMetaStore — documented but never coded

The docs should mark these as *planned* rather than *implemented*, or the code should be written.

### 23. Cache storage path mismatch
**File:** `lib/src/cache/image_cache_service.dart:50` vs AGENTS.md line 127

AGENTS.md says cache lives at `{appDocDir}/cache/`. The actual code uses `getTemporaryDirectory()`. On Windows, temp can be cleaned by the OS independently, and the meta store dies with it.

### 24. `restoreSession()` blocks startup on a network login despite persisted cookie
**Files:** `lib/main.dart:16`, `lib/src/state/auth_state.dart:60-68`

AGENTS.md says "Cookie persisted via dio_cookie_manager + cookie_jar (survives app restart)" — but `restoreSession` ignores the persisted cookie and does a *fresh blocking login* before `runApp()`. Consequences:
- Cold start while offline/slow: user stares at a blank window for up to ~10-25s (10s send + 10s receive timeouts), even though a valid cookie may be on disk.
- If the login POST fails transiently, `authStatus = error` even though the persisted session cookie might still be valid — the app degrades a working session to an error state.
- The error state isn't surfaced because `_AuthRouter` (main.dart:52-57) maps all statuses to `HomeScreen`, and `errorMsg` is only rendered inside `LoginScreen` which is never pushed automatically. A failed cold-start login is invisible to the user.

### 25. `CreatorPostsScreen` has no error state
**File:** `lib/src/screens/creator_posts_screen.dart:105-113`
**Contrast:** `home_screen.dart:235-246`

HomeScreen has a proper error state with retry button. CreatorPostsScreen maps both "empty" and "error" to "No posts found" — a network failure is indistinguishable from a creator with zero posts, and there's no retry affordance. (`AppState.loadCreatorPosts` sets `creatorPosts.value = []` on failure, line 109.)

### 26. `PawchiveClient.dio` double-initialization and public mutable field
**File:** `lib/src/api/pawchive_client.dart:16-37`

Line 16 eagerly builds a Dio instance that is thrown away and replaced in `init()`. Any call before `init()` completes uses the cookie-less instance. The field is public and non-final — any code can swap it. Should be `late final`, constructed once in `init()`.

### 27. Context menu doesn't move on second right-click
**File:** `lib/src/widgets/context_menu.dart:160-165, 287`

`_adjustedPos` is computed in `initState` post-frame callback and **never** recomputed in `didUpdateWidget`. Right-clicking a different spot keeps the menu at the old location.

### 28. Popover position captured once, goes stale on scroll
**File:** `lib/src/widgets/popover.dart:158-168`

`_show()` snapshots the child's global position. The filter popovers live inside a *floating* `SliverPersistentHeader` (`home_screen.dart:250`), so scrolling while the popover is open leaves the popover floating at a stale screen position.

### 29. Escape shortcuts need focus that's never requested
**Files:**
- `lib/src/widgets/popover.dart:398-401`
- `lib/src/widgets/context_menu.dart:309-312`

`CallbackShortcuts` + `FocusScope`, but no `autofocus: true` — Escape only works after clicking inside the menu.

### 30. LoginScreen is undismissable without logging in
**File:** `lib/src/screens/login_screen.dart:46-129`

Plain `Scaffold` with no `AppBar`/back button. On desktop there is no system back affordance — the user is trapped unless login succeeds (`Navigator.pop` only on success, line 37-39).

### 31. Three parallel image-viewer implementations, one used
**File:** `lib/src/screens/image_viewer_screen.dart` (two implementations, neither referenced) vs `fullscreen_image_viewer_screen.dart` (the one actually used). This bred a number of minor bugs unique to the dead code (#6-#8 in the screens agent review), and an inconsistency: `image_viewer_screen.dart:565` disposes `_imageInfo` while `fullscreen_image_viewer_screen.dart:682-688` never does.

### 32. Plaintext password storage in Hive
**File:** `lib/src/state/auth_state.dart:32-33`

```dart
await _box.put('password', password);
```

The box is unencrypted on disk. The cookie jar already persists the session; storing the password at all is only needed for the re-login flow that shouldn't be necessary (#24).

### 33. Fake signal subscription in fullscreen viewer
**File:** `lib/src/screens/fullscreen_image_viewer_screen.dart:748-751`

```dart
// Subscribe to metaReady for reactive aspect-ratio changes.
ImageMetaStore.instance.metaReady.value;
```

Reads the signal inside a `LayoutBuilder`, **not** a `SignalBuilder`, so nothing subscribes — the comment lies and the aspect ratio stays stale after page build.

### 34. `debugPrint` in hot build paths
- `main.dart:51` — on every `_AuthRouter.build()`.
- `creator_posts_screen.dart:114, 131-135` — inside the grid `itemBuilder`, dumping every post's full attachment list.
- `creator_posts_screen.dart:519-524, 551` — inside dialog builds.

Measurable scroll-perf cost in debug builds, log spam regardless.

---

## 🟢 Minor / Maintainability

### 35. `url_launcher` imported but state isn't picked up
`creator_posts_screen.dart:1134` — `launchUrl` uses `LaunchMode.externalApplication` which works, but the import's presence suggests open/embed links feature is intended; the `origin` field on posts is never surfaced in the UI.

### 36. `ArchiveService` allocated on every build
**File:** `lib/src/screens/creator_posts_screen.dart:819-824`

```dart
ArchiveService(PawchiveClient.instance.dio)
```

Allocated in every `_buildContent` rebuild. Hoist to field/`initState`.

### 37. `models.dart:51` — `Map?` loses type safety
Should be `Map<String, dynamic>?` for the `embed` field.

### 38. `EmptyObjectAsNullHook` applied inconsistently
Applied to `file` in models but not to elements of `attachments`. If the API ever returns `{}` inside attachments, decoding throws.

### 39. `loadCreators` clears the list before the network call succeeds
**File:** `lib/src/state/app_state.dart:83`

```dart
if (refresh) creators.value = [];
```

A failed refresh leaves the home screen on the error state with no data instead of keeping the stale list.

### 40. `restoreSession` blocking login prevents loading slow on first launch
**File:** `lib/main.dart:14-17`
Since `restoreSession()` blocks `runApp()`, and `loadCreators()` hits the network for 12MB, the app starts with all systems loading at once — could show a loading indicator before materializing the route tree.

---

## Summary of Recommended Fix Priority

| Priority | Items | Effort |
|----------|-------|--------|
| **P0 — Fix now** | #1 (dead tap), #2 (login false-positive), #3 (logout cookie), #5 (cross-creator race), #6 (cancel kills shared download), #7 (FutureBuilder churn), #8 (archive download race) | 1-2 days |
| **P1 — Fix soon** | #11 (memoize creator list), #9/#10 (atomic writes), #14 (image downscaling), #15 (isolate decompression), #13 (provider key equality), #12 (metaReady batching) | 2-3 days |
| **P2 — Clean up** | #21 (delete dead code), #22 (sync docs), #16 (DioFileService timeouts), #17 (Accept header), #26 (client init) | 1 day |
| **P3 — Polish** | #24 (remove blocking restoreSession), #25 (error state), #27 (context menu), #28 (popover), #29 (autofocus), #30 (login dismiss), #33 (dead subscription), #34 (debugPrint) | 1 day |
| **Deferred** | #2#1 — Phase 3 favorites implementation | 3-5 days when scoped |
