# AGENTS.md — Kemono Browser

## Overview

Flutter app (Windows + Android) for browsing a Kemono spiritual successor (`pawchive.pw`). Focuses on UI/UX — comfortable browsing with lazy-loaded images via custom ImageProvider, archive management, favorites synced with server, and filesystem-based storage with no database.

## Commands

```bash
flutter run -d windows
flutter run -d android
dart analyze lib/
dart run build_runner build --delete-conflicting-outputs
```

## Testing Convention

Every feature is developed through unit and/or integration tests. Tests are only ever run when any actual change was made to the tested code — never on unrelated changes. There is no requirement to run the full suite before every commit or PR.

## Tech Stack

| Layer | Choice |
|-------|--------|
| **State** | `signals` + `signals_flutter` |
| **HTTP** | `dio` |
| **Image loading** | Custom `ImageProvider` (Dio + `flutter_cache_manager` with custom `DioFileService`) |
| **Serialization** | `dart_mappable` |
| **ZIP extraction** | `koni_archive` |
| **HTML rendering** | `flutter_widget_from_html` |
| **Settings** | `hive_ce` (saved credentials, UI prefs only — NOT favorites data) |
| **Lints** | `flutter_lints: ^6.0.0` |
| **Build runner** | `build_runner: ^2.4.0` |
| **Favorites state** | Pure filesystem (no database) |
| **Cookie management** | Manual `Cookie` header via interceptor, session value stored in Hive |
| **Storage paths** | `path_provider` |
| **Hive adapter** | `hive_ce_flutter` |
| **Link handling** | `url_launcher` |
| **Clipboard** | `pasteboard` |
| **Sticky headers** | `persistent_header_adaptive` |
| **Dropdown** | `dropdown_button2` |
| **Visibility** | `visibility_detector` |
| **Dev: File ops** | `file` |
| **Dev: Code gen** | `dart_mappable_builder` + `hive_ce_generator` |

## Conventions

- No comments in code unless asked
- All API calls from Flutter directly
- Errors logged via debugPrint with stack traces
- Use `SignalBuilder(builder: ...)` for reactivity (NOT deprecated `Watch`)
- Use `@MappableClass(caseStyle: CaseStyle.snakeCase)` for dart_mappable models
- hive_ce is for settings ONLY (saved credentials, theme prefs) — never favorites data
- **Always check package docs before using a library** — see signals_flutter at https://dartsignals.dev/, dio at https://pub.dev/packages/dio, etc. Do not guess API signatures.
- **Never swallow errors silently** — every catch block must either debugPrint the error with stack trace, set an error signal, or rethrow. No empty catch blocks. Users must always be able to see what went wrong.
- **Skip dart analyze on every change** — user resolves bracket/formatting issues faster than the tool. Only run analyze when explicitly asked or when tests fail for unknown reasons.

## CRITICAL: Always Read Package Documentation
- dart_mappable: https://dart-mappable.schultek.de/
- signals_flutter: https://dartsignals.dev/
- dio: https://pub.dev/packages/dio
- flutter_cache_manager: https://pub.dev/packages/flutter_cache_manager

## CRITICAL: Search for Existing Solutions
Before implementing any feature, search:
1. GitHub issues for the package + problem
2. StackOverflow for Flutter solutions
3. Existing projects in `S:\G_drive_backup\.Projects\SoyDev\Flutter\` for patterns

## Architecture

### Auth (Cookie-based)

```
POST /account/login
  body: username=foxyz&password=****&location=/artists
  → 302 redirect to /artists?logged_in=yes&role=consumer
  → Set-Cookie: session=<Flask signed cookie>
```

- Cookie persisted in Hive alongside credentials (survives app restart)
- Login screen: username + password fields, call POST, check for redirect
- No OAuth, no token refresh — cookie just works until server expiry
- Credentials saved in hive_ce for auto-login on cold start
- Images are public — no auth headers needed in ImageProvider

### Server Favorites

> Status: implemented (API calls + in-memory id set). The local filesystem
> mirror described under "Favorites Merge Strategy" / "Storage" does **not**
> exist yet.

All verified working (cookie auth):

| Method | Endpoint | Response |
|--------|----------|----------|
| `GET` | `/account/favorites?type=creator` | List followed creators (id, name, service, updated, ever_imported, last_imported, kemono_favorited) |
| `GET` | `/account/favorites?type=post` | List favorited posts |
| `POST` | `/favorites/post/{service}/{creator_id}/{post_id}` | 204 No Content |
| `DELETE` | `/favorites/post/{service}/{creator_id}/{post_id}` | 204 No Content |
| `POST` | `/favorites/creator/{service}/{creator_id}` | 204 No Content |
| `DELETE` | `/favorites/creator/{service}/{creator_id}` | 204 No Content |

Creator `updated` field is an ISO 8601 string — this is the timestamp to diff against `lastChecked` for new post detection.

### New Post Detection

> Status: implemented for the creator page only (`lastChecked` persisted in
> `{documents}/last_checked.json`). The favorites-tab "New" badge below is not
> built, and `_meta.json` is not used anywhere.

```
On favorites tab open:
  GET /account/favorites?type=creator
  → for each creator: compare updated > local lastChecked (from _meta.json)
  → if newer → show "New" badge on creator tile

On creator page open:
  GET /{service}/user/{creator_id}
  → filter posts where published > lastChecked (exact diff)
  → show "New" pill on each unseen post
  → update lastChecked in creator's _meta.json after viewing
```

### Favorites Merge Strategy

> Status: **not implemented.** No `_meta.json`, no favorites tree, no
> `viewedAt`/`archived` fields exist in `lib/`. This section is the intended
> design, not current behaviour.

- **Server** is source of truth for "which creators/posts are favorited" (the set)
- **Local filesystem** (_meta.json) stores state metadata (viewedAt, archived, notes)
- On login sync: fetch server favorites, reconcile with local tree (delete local favorites not on server, add local _meta for server favorites that exist but have no local entry)
- Favorites tree is always a subset of server favorites + extra local metadata

### Storage

> Status: **not implemented** beyond the cache directory. Favorites/`_meta.json`
> is a design target; the app currently stores only image cache, archive cache,
> Hive settings and `last_checked.json`.

```
{appDocDir}/
  cache/                          # flutter_cache_manager (30-day stale, max 1000 objects)
  favorites/
    patreon/
      {creatorId}/
        _meta.json                # {name, service, favoritedAt, lastChecked}
        {postId}/
          files/                  # downloaded attachments (images, zips)
            Akochi.jpg
            archive.zip
          _meta.json              # {title, published, viewedAt, archived, notes}
    fanbox/
      {creatorId}/
        ...
  creators.json                   # Cached /creators endpoint response
```

Startup: scan `favorites/` tree for `_meta.json` → build in-memory `Signal<Map>` index. Writes go to filesystem → update signals → widgets rebuild. Corrupted `_meta.json` = at most one post's metadata lost.

### Image Loading (KemonoImageProvider + DioFileService)

Custom `KemonoImageProvider` extends `ImageProvider<KemonoImageProvider>`:

```
Image(image: KemonoImageProvider(url, creatorId: ..., postId: ...))
  → obtainKey() → SynchronousFuture(this)
  → loadImage() → MultiFrameImageStreamCompleter
  → _loadAsync() → cache.getFileStream(url, withProgress: true)
    → flutter_cache_manager checks disk
      → Hit (not stale): FileInfo → ImmutableBuffer.fromFilePath → decode → Codec
      → Miss/stale: DioFileService downloads → writes cache → FileInfo → decode
    → Progress events → chunkEvents (for loading indicators)
    → ImageMetaStore.record() with creatorId/postId for per-creator tracking
  → On error: evict from memory cache + disk cache, rethrow
  → On last listener removed: cancel in-flight download via CancelToken
```

`DioFileService` extends `FileService`:
- Uses Dio for networking (consistent with rest of app)
- Default headers: `Referer: https://pawchive.pw/` + browser User-Agent (required by `img.pawchive.pw` and `file.pawchive.pw`)
- `CancelToken` for cancellation
- `ResponseType.stream` for efficient downloads
- Derives `validTill` from `Cache-Control: max-age`
- Derives `fileExtension` from `Content-Type` or URL extension

### URL Patterns

| Content | URL |
|---------|-----|
| Thumbnails | `https://img.pawchive.pw/thumbnail/data{path}` |
| Original file | `temp_url` when the file is **temporary**; otherwise `https://file.pawchive.pw/data{path}`; `null` when the post `has_full == false` |
| Banners | `https://pawchive.pw/banners/{service}/{id}` |
| Icons | `https://pawchive.pw/icons/{service}/{id}` |

All paths from API start with `/`. Use `FileInfo.downloadUrl(hasFull: post.hasFull)`
— never build the file host URL by hand. Three file states and the UA rules are
in [`docs/server-contract.md`](docs/server-contract.md).

`Referer` is sent but **not currently enforced** by any host; the browser-style
User-Agent that `file.*` used to want is now actively blocked — see the contract doc.

### ImageMetaStore

Tracks cached image metadata (dims, bytes, creator/post association) in `{tempDir}/kemono_cache/kemono_image_meta.json`.

- `metaReady` signal — increments on record/remove, drives reactive UI updates
- `record(url, file, {creatorId, postId})` — parses dims from header (primary) or codec (fallback), persists to JSON
- `bytesForCreator(creatorId)` / `fileCountForCreator(creatorId)` — per-creator cache stats
- `postsForCreator(creatorId)` — returns `List<PostCacheInfo>` with per-post file counts and bytes
- `purgeCreator(creatorId)` — removes all entries for a creator, returns freed bytes map
- `purgeStale()` — drops entries older than 30 days
- JSON keys use short names: `w/h/b/t/c/p` (width/height/bytes/cachedAt/creatorId/postId)

### Data Flow

- `GET /creators` → all 89K in one response, no pagination needed, cached as `creators.json`
- Creator search is local on name only (API only returns `name`, not source URL)
- `GET /{service}/user/{creator_id}` → fetch posts per-creator, cache in memory
- Post sorting/filtering is local (date, title, tags, file types)
- Pull-to-refresh → re-fetch creator's posts, diff with cached, merge
- Favorites: sync with server on login, write `_meta.json` + update signals
- Archive: copy from `cache/` to `favorites/.../files/`; unarchive = delete from favorites tree

## Project Structure

```
lib/
  main.dart                         # App entry, init signals + theme + hive
  src/
    api/
      pawchive_client.dart          # Dio-based API client (singleton or static methods)
      models.dart                   # dart_mappable: Post, Creator, FavoriteCreator, FileInfo
      models.mapper.dart            # (generated)
      creator_store.dart            # Persistent 89K-creator index (line-delimited JSON)
    archive/
      archive_cache.dart            # LRU cache for downloaded archives (max 10, JSON manifest)
      archive_service.dart          # Dio + koni_archive: download, list, extract entries
    cache/
      kemono_image_provider.dart    # Custom ImageProvider (extends ImageProvider)
      image_cache_service.dart      # Singleton wrapping flutter_cache_manager
      dio_file_service.dart         # DioFileService (FileService for cache manager)
      image_size_parser.dart        # PNG/GIF/JPEG/WebP header dimension parser
      image_meta_store.dart         # Signal-driven metadata store (dims, bytes, creatorId/postId tracking)
    state/
      app_state.dart                # Global signals: favorites index, creator cache, filters
      auth_state.dart               # Login state, session management
    screens/
      home_screen.dart              # CreatorTile grid with search, sort, cache badges
      creator_posts_screen.dart     # Single creator's posts (attachment carousel, PostDetailDialog)
      image_viewer_screen.dart      # Full-size image viewer (PageView, progress skeleton, desktop nav)
      fullscreen_image_viewer_screen.dart # Archive-image viewer (InteractiveViewer, AppBar)
      archive_browser_screen.dart   # Browse extracted archive files (grid/list)
      login_screen.dart             # Username + password, saves credentials to hive_ce
    widgets/
      context_menu.dart             # FContextMenu — Material-styled right-click/long-press menu
      popover.dart                  # FPopover — anchored overlay popover (OverlayPortal)
      search_bar.dart               # Debounced search bar with signals integration
```

## Pawchive API (Kemono v1 format)

Base URL: `https://pawchive.pw/api/v1`

### Creators
`GET /creators?o={offset}`
- id: String, name: String, service: String, indexed: number (unix), updated: number (unix), favorited: int, ever_imported: bool

### Posts Feed
`GET /posts?o={offset}&q={query}`
- id, user, service, title, substring (truncated preview, NOT full content), published, file, attachments, preview_state ("scraped"|"pending"), has_full: bool, origin: String

### Creator Posts (full detail)
`GET /{service}/user/{user_id}`
- Full posts: id, user, service, title, content (HTML body), embed, tags ("{Tag1,Tag2}"), shared_file, added, edited, poll, captions, published, file, attachments

### Single Post
`GET /{service}/user/{user_id}/post/{post_id}`
- Same as full post + next/prev navigation fields

### Comments
`GET /{service}/user/{user_id}/post/{post_id}/comments`

### Favorites (cookie auth required)
- `GET /account/favorites?type=creator` — returns creator objects with `updated` (ISO 8601), `last_imported`, `ever_imported`, `kemono_favorited`
- `GET /account/favorites?type=post` — returns post objects
- `POST/DELETE /favorites/post/{service}/{creator_id}/{post_id}` — 204
- `POST/DELETE /favorites/creator/{service}/{creator_id}` — 204

### Auth
- `POST /account/login` — form body: username, password, location; → 302 redirect + Set-Cookie

### Files
- `https://pawchive.pw{path}` — publicly accessible (banners, icons)
- `https://img.pawchive.pw/thumbnail/data{path}` — thumbnails (Referer required)
- `https://file.pawchive.pw/data{path}?f={filename}` — full-size (Referer required)

## Models (dart_mappable)

```dart
// Creator
id: String
name: String
service: String
indexed: int          // unix timestamp
updated: int           // unix timestamp
favorited: int
ever_imported: bool

// Post (feed endpoint)
id: String
user: String
service: String
title: String
substring: String?     // truncated preview
published: String      // ISO 8601
file: FileInfo?
attachments: List<FileInfo>
preview_state: String? // "scraped" | "pending"
has_full: bool
origin: String?

// Post (detail endpoint — additional fields)
content: String?       // full HTML body
embed: Map?
tags: String?          // "{Tag1,Tag2}" format
added: String?         // ISO 8601
edited: String?

// FileInfo
name: String?          // nullable — some attachments have no name
path: String           // relative to https://pawchive.pw
deferred: bool?

// FavoriteCreator (from server)
id: String
name: String
service: String
updated: String        // ISO 8601
ever_imported: bool
last_imported: String? // ISO 8601
kemono_favorited: int

// Local-only (filesystem _meta.json — raw JSON maps, no Dart class)
// Creator _meta.json:
//   {name, service, favoritedAt (ISO 8601), lastChecked (ISO 8601)?}
//
// Post _meta.json:
//   {title, published (ISO 8601), viewedAt (ISO 8601)?, archived (bool), notes (String)}
```

## Key Behaviors

### Image Loading
- Custom `KemonoImageProvider` wrapping `flutter_cache_manager` with `DioFileService`
- Thumbnails load from `img.pawchive.pw/thumbnail/data{path}`; on tap, the original comes from `FileInfo.downloadUrl()` (signed `temp_url` or `file.pawchive.pw/data{path}`)
- `DioFileService` sends the app UA (browser UAs are blocked), reads 1 KB of any error body into `AppErrors`, and rejects files above `FileSizeGate.thresholdBytes` (default 20 MB) before the body transfers
- The image viewer falls back to the thumbnail with a small pill when the original is unavailable, too large, or still loading; a signature/expiry 403 triggers one post re-fetch and retry
- Favorites/files tree does not exist yet (see Storage above)
- `MyImageViewerScreen` — two static entry points:
  - `open(context, files, index, service, creatorId, postId, hasFull)` — URL-based images from API, dark overlay, PageView, nav arrows, progress skeleton
  - `openArchive(context, data, fileName, archiveName?)` — raw `Uint8List` images from archive extraction, dark overlay, InteractiveViewer, AppBar with filename

### Archive Management
- Detect `.zip`, `.rar`, `.7z` attachments → inline `_ArchiveTile` (idle→downloading→ready|error) with tap-to-download-and-extract
- `MyImageViewerScreen.openArchive()` for viewing archive images (reuses the same dark-overlay viewer pattern)
- Uses `koni_archive` package (pure Dart, no FFI) — supports zip/7z/rar/tar/gzip on all platforms

### Favorites (server + local merge)
- "Favorite creator" → POST to server + create local `_meta.json`
- "Unfavorite" → DELETE from server + remove local tree
- "Favorite post" → POST to server + create local `_meta.json` + copy files
- On login: sync server favorites → reconcile local tree (remove orphans, add missing)
- "Viewed" → update local `_meta.json.viewedAt` only
- "Archive" → set local `_meta.json.archived = true`, files already saved
- "Clear unneeded" → delete local favorited posts where `archived == false` (server favorites remain)

### New Post Detection
- On favorites tab: `GET /account/favorites?type=creator`, compare `updated` to local `lastChecked`
- On creator page: `GET /{service}/user/{creator_id}`, filter by `published > lastChecked`
- `lastChecked` updated in `_meta.json` after navigating through the creator's feed

## Milestones (phased approach)

1. **Phase 1**: API client (Dio with auth), Creator (KemonoImageProvider), Post (dart_mappable) models, login screen, creator list with local search, creator posts feed, post detail with HTML body + lazy images
2. **Phase 2**: ImageProvider + cache layer, archive detection + ZIP extraction + browsing
3. **Phase 3**: Server favorites sync, local _meta.json management, new post detection, favorites screen
4. **Phase 4**: "Clear unneeded" batch ops, sorting/filtering polish, pull-to-refresh merge logic
