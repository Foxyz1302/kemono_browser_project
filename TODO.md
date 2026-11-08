# TODO

Human-owned. Agents may add a `Superseded` entry or a `Now` line when asked;
nobody deletes without the user. Design docs exist only for `Now` items that
need one.

## Now

- [ ] Rate limit download hosts: 1 req/s, 5 concurrent, cancel must dequeue
      (currently not implemented at all)
- [ ] Cancel-vs-shared-download: losing one image listener cancels the download
      other widgets use and deletes the partial file
- [ ] Archive: in-flight dedup, atomic manifest writes, decompression off the UI
      isolate
- [ ] Meta store: reconcile with cache evictions; batch `metaReady` instead of
      one bump per image (likely the idle battery cost)
- [ ] Cold start: `restoreSession()` blocks `runApp()` on a network login even
      with a valid saved cookie
- [ ] Creator screen error state (a network failure currently renders
      "No posts found")
- [ ] Media unification: one grid + one pager for post files and archive
      contents, archive folders, delete the dead viewers
- [ ] Settings: cache stats, clear thumbnails/full, purge stale, storage path
      (the popover currently has one toggle)
- [ ] Password-protected archives: detect, prompt, remember per creator.
      Unverified — no real example yet; guess from post content or a `.txt`
      inside the archive
- [ ] Other file types: view as text / open externally
- [ ] In-app link resolution (same-creator post ids) + text selection in posts
- [ ] Download manager: cache-aware, single-flight, progress, cancel, state
      signals; progress must survive leaving the screen
- [ ] Save flow: images/files/archives from a post. Prefer the API layout over a
      flat downloads folder — and decide whether a plain folder stays an option
- [ ] HLS videos
- [ ] Perf pass on device: idle vs scroll, one screen at a time

## Ideas

- Load-more with page markers, or a horizontally scrollable page strip
- PSD merged-composite preview (only if PSDs actually show up)
- Archive preview by HTTP range (verified possible: 18 entries in 4 requests)
- In-app profiling probe that writes aggregates instead of traces

## Superseded

- Save system → download manager (2026-11). Local favorites tree still deferred.
- photo_view refactor → `LeafViewer` in `leaf_widgets` (done)
- Boundary-aware gestures → implemented in `leaf_widgets` edge-release
- `problems.md` → this list + `docs/state.md`
