# Planned Features

## Archive (Offline Preservation)

Store a post permanently on disk so it's viewable offline, survives cache eviction, and preserves all files even if the source goes down.

### Flow

1. **Archive button** on PostDetailDialog (AppBar action or bottom bar)
2. On tap:
   - Download all attachments into `favorites/{service}/{creatorId}/{postId}/files/`
   - Set `_meta.json: archived: true`
   - Optionally pre-extract ZIP archives into `files/extracted/{archiveName}/`
   - Optionally convert images to WebP with configurable quality
3. **Archive settings** (in settings screen):
   - `convertToWebP: bool` (default false)
   - `webpQuality: int 1-100` (default 80)
   - `extractArchives: bool` (default true)
   - `extractAndDeleteOriginal: bool` (default false — delete ZIP after extraction)
4. **Archive browser** screen:
   - Browse archived posts by creator
   - View images offline (from local filesystem, not from cache/network)
   - Browse extracted ZIP contents as a file tree
5. **Unarchive**: remove `archived` flag from `_meta.json`, optionally delete files. Server favorite remains.

### Storage Layout

```
favorites/
  patreon/
    {creatorId}/
      _meta.json                    # {name, service, favoritedAt, lastChecked}
      {postId}/
        _meta.json                  # {title, published, viewedAt, archived: true, notes, webpConverted: true, archivesExtracted: true}
        files/
          image1.jpg
          image2.webp               # WebP copy if conversion enabled
          archive.zip
          extracted/                # Pre-unpacked ZIP contents
            archive/
              photo.png
              document.pdf
```

### Image Conversion (WebP)

- Use `dart:ui` `instantiateImageCodec` to decode → `FrameInfo` → `toByteData(format: imga解码.webp)` (if supported) or use a platform channel to `ffmpeg`/`cwebp`
- Fallback: just store original — no conversion
- Conversion runs as a background isolate to avoid jank
- Only applies to raster formats (jpg, png, gif, bmp) not animated (skip animated gif/png/webp)

### Offline Viewing

- `ArchiveImageProvider` extends `ImageProvider` — loads from local file path instead of network
- Falls through to network if the file doesn't exist on disk (e.g. post archived but image wasn't downloaded yet)

### ZIP Extraction

- Detect `.zip` / `.rar` / `.7z` attachments
- Extract using `archive` package into `files/extracted/{archiveName}/`
- Show extracted file tree in Archive Browser
- Each extracted file can be individually favorited/saved
- Extraction progress dialog (for large archives)
- On `extractAndDeleteOriginal: true`, delete ZIP after successful extraction
