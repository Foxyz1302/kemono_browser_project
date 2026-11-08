# docs — index

| Doc | Kind | Last verified | Contents |
|---|---|---|---|
| `../TODO.md` | work queue | — | `Now` / `Ideas` / `Superseded`. The only TODO |
| `state.md` | snapshot | 2026-11-04 | What is implemented, what is uncommitted, decisions + reasons, traps |
| `server-contract.md` | facts | 2026-11-04 | Verified API/CDN behaviour (file states, `temp_url`, UA rules, 403 bodies, rate limits, pagination) |
| `downloads-portal.md` | design (open) | 2026-10 | Download manager + portal. Its "archive preview = download" premise is outdated |
| `problems.md` | **untrusted** | 2026-07-27 | Stale review snapshot. Contains at least one false claim and several describing deleted code. Do not act on it without checking the code |
| `photo-view-evaluation.md` | done | 2026-07-31 | Produced the viewer that now lives in `leaf_widgets` |
| `future-boundary-aware-gestures.md` | done | 2026-07 | Implemented as edge-release in `leaf_widgets` |

Project facts and conventions live in `../AGENTS.md`. Do not duplicate them here.

Rules that keep this from rotting: plans live in `TODO.md` only; design docs are
written for `Now` items and get a `Status:` line; anything shipped moves to
`Superseded` or gets deleted.
