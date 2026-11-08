# State — 2026-11-04

A snapshot, not a contract. Anything here can be stale; the code wins. Server
behaviour lives in `server-contract.md`, conventions in `../AGENTS.md`, work in
`../TODO.md`.

## Git

- Local only, **no remote**. `6444916` is the checkpoint (three months of work,
  platform regen, docs, Linux target).
- On top of it, **uncommitted**: the file-download fixes listed below.
- `flutter test`: 108 pass, 2 fail — both pre-existing in
  `test/image_meta_store_test.dart` (the test records a `pawchive.pw/files/...`
  URL while the helper looks up `img.pawchive.pw/thumbnail/data/...`).

## Implemented (uncommitted, needs device verification)

- **UA identity** — `KemonoBrowserProject-dev (+discord: foxyz)` on every
  client, including the video player. Browser UAs are blocked by DDoS-Guard.
- **File URLs** — `FileInfo.previewOnly/tempUrl/tempDownloadUrl/tempExpires` and
  `downloadUrl(hasFull:)`. Returns the signed URL, else the file host, else
  `null` when the post is `has_full: false`.
- **Error capture** — `ErrorDescriptorInterceptor`, 1 KB error-body read in
  `DioFileService`, `AppErrors` log, Diagnostics sheet (mobile: tune menu;
  desktop: long-press "Kemono") with **Copy all**.
- **Viewer** — thumbnail first; pill for `Load full · N MB` (20 MB gate, video
  exempt), `Preview · retry`, `Original not available`; one post re-fetch on
  `link expired` / `bad signature`, matched by `path`.
- **Pagination** — offset pages, total scraped from the creator HTML, responsive
  pager top and bottom.
- **Flags** — note per post plus a per-file state snapshot, JSON in the Android
  app-private documents dir, clipboard export via Diagnostics.
- **Fanbox-only** rule for "first attachment is the banner".
- **Unavailable posts** open in the viewer and show thumbnails.
- **Micro-perf** — grid `shouldRelayout` compares fields; removed a
  `debugPrint` from a build path.

## Decisions (don't re-litigate without new evidence)

- Never spoof a browser UA on download hosts. `-dev` becomes a repo URL when one
  exists.
- `temp_url` is the only discriminator between file states; `preview_only` is
  not (it has false negatives and false positives).
- Never persist a `temp_url`. Cache keys strip the query string.
- Pages, not load-more — for now. Any redesign must be one state machine.
- The 20 MB gate covers viewer files except video.
- No PSD layer compositor. If a PSD ever shows up, decode the merged composite
  with `psdkit`. (0 of 2,019 sampled files were PSD.)
- Archive range listing is deferred; solid RAR/7z make it a near-full download
  anyway, and it needs the download queue to be worth anything.
- Download manager waits until after the media unification (post files + archive
  contents in one grid/pager). Shape per-URL transfer state now if it helps.
- One-line fixes get fixed, never tracked.
- A file can flip temporary → stored during backfill: its URL and cache key
  change, and that's expected.

## Traps

- Download-host 403 bodies: `link expired`, `bad signature`, or the DDoS-Guard
  bot paragraph. Classify by body; only retry the first two.
- `temp_expires` is now+15 days and meaningless; the URL's `e=` is now+6 hours.
- The JSON API has no post count; it is scraped from the creator page HTML and
  degrades to prev/next.
- Server asks for ≤1 req/s and ≤5 concurrent downloads. **Not implemented yet.**
- HLS videos exist (`/v/{id}/master.m3u8` + `temp_download_url`), unhandled.
- `path_provider`'s documents dir is app-private on Android — export via
  clipboard, not files.
- `problems.md` is an untrusted 2026-07-27 snapshot. It contains at least one
  claim the user says is false (#1, card tap) and several describing deleted
  code. Don't act on it without checking the code.
