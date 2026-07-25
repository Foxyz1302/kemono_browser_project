# Settings Screen — Planned

## Structure

```
Settings
├── Account
│   └── Logged in as: {username}  [Logout]
├── Cache
│   ├── Tracked: 247 files · 312.4 MB   (ImageMetaStore)
│   ├── Disk: 263 files · 348.1 MB      (getStats from disk)
│   ├── Thumbnails  [Clear]              (type == "thumb")
│   ├── Full images [Clear]              (type == "full")
│   ├── Stale >30d  [Purge]              (cachedAt < cutoff)
│   └── Storage: {path}
└── (future: Archived [Clear] section)
```

## Implementation

1. `image_meta_store.dart` — Add `type` field (`String?`) to `ImageMeta` (JSON key `y`). Update `record()` to accept `{String? type}`. Add `bytesForType()`, `fileCountForType()`, `purgeStale()`.

2. `kemono_image_provider.dart` — Add optional `type` param, pass through to `record()`.

3. `image_cache_service.dart` — Add `clearByType(String type)` that filters entries by type, removes matching URLs from meta store + disk.

4. `settings_screen.dart` — New `SignalStatefulWidget`. Loads `getStats()` on init. Uses `SignalBuilder` on `metaReady`. Buttons trigger confirm dialog → clear/purge → snackbar.

5. `home_screen.dart` — Add settings IconButton in AppBar, push SettingsScreen. Remove logout button (moved to settings).

## Navigation

- Settings icon in HomeScreen AppBar → push SettingsScreen
- Logout moves from HomeScreen AppBar into settings page
