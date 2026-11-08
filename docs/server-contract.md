# pawchive.pw — verified server contract

Everything here was verified against the live server (last full pass:
2026-11-04). If something stops matching, re-verify before trusting the app's
assumptions.

Base URL: `https://pawchive.pw`. API prefix: `/api/v1`.

---

## Hosts

| Host | Serves | Notes |
|---|---|---|
| `pawchive.pw` | HTML pages, `/api/v1`, banners (`/banners/{service}/{id}`), icons (`/icons/{service}/{id}`) | Cloudflare in front |
| `img.pawchive.pw` | thumbnails at `/thumbnail/data{path}` | Cloudflare; `Referer` not currently enforced |
| `file.pawchive.pw` | original files at `/data{path}` | **DDoS-Guard** |
| `t1.pawchive.pw` | signed temporary file links at `/f/{hash}/{name}`, HLS at `/v/{id}/master.m3u8` | **DDoS-Guard** |
| `n{node}.pawchive.pw` | mirror of `file.pawchive.pw` for files with a `node` field | Not needed; `file.` routes correctly |

Both download hosts support `HEAD` and `Range` (`accept-ranges: bytes`,
`206` + `content-range`). Verified against a 213 MB zip and a 55 MB gif.

## User-Agent — the one real "bot protection"

DDoS-Guard on `file.` / `t1.` rejects **browser-like User-Agents** with `403`,
regardless of `Referer`:

```
Are you a bot or using download tools? Please show respect and use reasonable
rate limits with downloading (no more than 1 request per second, and 5 active
downloads), along with an identifiable user agent, preferably with a way to
contact you. Excessive downloading or pretending to be a browser will result
in a block.
```

| UA | Result |
|---|---|
| Chrome / Firefox UA | **403** |
| `KemonoBrowserProject-dev (+discord: foxyz)` | 200 |
| `Dart/3.x (dart:io)`, `curl/…`, `python-requests`, no UA at all | 200 |

The API host and `img.` accept any UA, including browser ones. The app sends
`ApiConstants.userAgent` everywhere. **Do not spoof a browser.** When a repo
exists, replace `-dev` with the repo URL.

Rate limits requested by the server: ≤ 1 request/second, ≤ 5 concurrent
downloads. Implemented for download hosts via `DioFileService` + the queue;
thumbnails are not paced.

## File states — three, not two

Every `FileInfo` is in exactly one of these states:

| State | JSON | Where the bytes are | Site label |
|---|---|---|---|
| **stored** | `path` (± `node`), no `temp_url`, post `has_full: true` | `https://file.pawchive.pw/data{path}` | direct link |
| **temporary** | `temp_url` present (with or without `preview_only`) | only `temp_url` (`t1.…`), signed | "Full file available temporarily" |
| **unavailable** | `preview_only: true` with no `temp_url`, **or** post `has_full: false` | nowhere — 404 | "Previews only" |

Rules that follow:

- `temp_url` is the only reliable discriminator. `preview_only` alone is
  neither necessary (22 video entries have a temp URL without it) nor
  sufficient (21 `thumbnail.png` attachments have it and 404).
- `path` is still usable for thumbnails in every state.
- `has_full == false` means the post was never imported; don't even try the
  file host.
- A file can flip temporary → stored during backfill, which changes its URL
  and therefore its cache key. "Never download twice" holds per URL, not per
  file.

Frequency across 8 creators / 1,573 files (2026-11-04): 62% temporary, 37%
stored, 1% unavailable — with huge per-creator variance (five creators 0%
temporary, one 93%). The API returns no field explaining which state applies.

## `temp_url` semantics

- Minted **per request**: same file fetched 10 s apart returns a different
  `s=` and `e=`.
- `e=` is always **now + 6 hours**. Expired → `403 link expired`; tampered
  signature → `403 bad signature`.
- `temp_expires` is **now + 15 days**, recomputed each request. It is advisory
  and does not describe the URL's validity. Do not gate on it.
- Cache keys must strip the query string, otherwise every refresh re-downloads.

## 403 bodies are the error taxonomy

| Cause | Status | Body |
|---|---|---|
| expired signed URL | 403 | `link expired` |
| bad signature | 403 | `bad signature` |
| browser-like UA | 403 | the DDoS-Guard paragraph above |

The app classifies these (`classifyBody`) to decide between refreshing the
post data and falling back to the preview. A blind retry is wrong: retrying a
bot-block makes things worse.

## HLS videos

Some `deferred` videos return a playlist as `temp_url`
(`https://t1.pawchive.pw/v/{id}/master.m3u8`) plus a `temp_download_url`
(`…/d/{id}/…`) for the actual file. Not observed in normal browsing yet;
handled only as "prefer `tempDownloadUrl` when the main URL is null".

## Pagination and the post count

- `GET /api/v1/{service}/user/{id}?o={offset}` returns 50 posts per page;
  offsets 0/50/100 returned distinct sets with zero overlap. Out of range → `[]`.
- There is **no total count in the JSON**: no header, no wrapper; `?count=true`,
  `?total=true`, `?limit=1` are ignored (byte-identical response); `/count`
  endpoints 404.
- The count exists only in the **server-rendered creator page**:
  `GET /{service}/user/{id}` contains `Showing 1 - 50 of 263` and pager links
  `?o=50`. The line is absent when the creator fits on one page.
- The app scrapes that line once per creator; when it fails the paginator
  degrades to prev/next without "of N".

## Auth

- `POST /account/login` (form-encoded: `username`, `password`, `location`).
- Success and failure both return `302`. Success → `Location: /artists?logged_in=yes…`;
  failure → `Location: /account/login…` with the reason in the `session`
  cookie's `_flashes` (Flask, sign-only, sometimes zlib-packed).
- Session is a `session=` cookie sent manually; `GET /account/favorites` without
  it returns `401 {}`.

## Archive formats

200-post sample (2,019 files): 22 zip, 6 rar, 0 7z/tar/cbz/cbr. `koni_archive`
already covers all of them. RAR is real but rare, so range-preview support for
solid RAR is a low priority (solid blocks decompress as a whole on first read).
