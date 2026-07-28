import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'archive_service.dart';

/// Persistent cache for downloaded archives.
///
/// Stores archives in `{appDocDir}/archive_cache/` with a JSON manifest.
/// Keeps at most [maxArchives] files, evicting the least recently accessed
/// when the limit is exceeded.
class ArchiveCache {
  ArchiveCache._();

  static final ArchiveCache instance = ArchiveCache._();

  static const int maxArchives = 10;
  static const String _dirName = 'archive_cache';
  static const String _manifestName = 'manifest.json';

  String? _cachePath;
  List<_CacheEntry> _entries = [];

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _cachePath = p.join(appDir.path, _dirName);
    await Directory(_cachePath!).create(recursive: true);
    await _loadManifest();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the local path to the archive for [url].
  ///
  /// If the archive is already cached and the file exists on disk, it is
  /// returned immediately. Otherwise it is downloaded via [service].
  Future<String> getOrDownload(
    String url,
    ArchiveService service, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (_cachePath == null) await init();

    // ---- 1. Check manifest ----
    final existing = _findByUrl(url);
    if (existing != null) {
      final file = File(existing.localPath);
      if (file.existsSync()) {
        existing.lastAccessedAt = DateTime.now();
        await _saveManifest();
        return existing.localPath;
      }
      // File was manually deleted — remove manifest entry, re-download below.
      _entries.remove(existing);
    }

    // ---- 2. Compute unique path and download ----
    final safeName = _safeFilename(url);
    final localPath = p.join(_cachePath!, safeName);

    try {
      await service.downloadArchive(
        url,
        _cachePath!,
        localPath: localPath,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    } catch (e, st) {
      debugPrint('ArchiveCache: download failed for $url: $e\n$st');
      // Clean up partial download on failure.
      try {
        await File(localPath).delete();
      } catch (e2, st2) {
        debugPrint('ArchiveCache: failed to delete partial $localPath: $e2\n$st2');
      }
      rethrow;
    }

    // ---- 3. Add to manifest ----
    final file = File(localPath);
    final fileSize = await file.length();
    final entries = await service.listEntries(localPath);
    final entryCount = entries.length;

    _entries.add(_CacheEntry(
      url: url,
      localPath: localPath,
      cachedAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
      fileSize: fileSize,
      entryCount: entryCount,
    ));

    // ---- 4. Trim to limit ----
    await _trim();
    await _saveManifest();
    return localPath;
  }

  /// Update the last-accessed timestamp for [url] without downloading.
  void touch(String url) {
    final entry = _findByUrl(url);
    if (entry != null) {
      entry.lastAccessedAt = DateTime.now();
      _saveManifest(); // fire-and-forget
    }
  }

  /// Returns the cached file size for [url], or `null` if not in the cache.
  int? getFileSize(String url) {
    return _findByUrl(url)?.fileSize;
  }

  /// Remove a single archive from the cache (file + manifest entry).
  Future<void> remove(String url) async {
    final entry = _findByUrl(url);
    if (entry == null) return;
    _entries.remove(entry);
    try {
      await File(entry.localPath).delete();
    } catch (e, st) {
      debugPrint('ArchiveCache: failed to delete ${entry.localPath}: $e\n$st');
    }
    await _saveManifest();
  }

  /// Delete every cached archive.
  Future<void> clearAll() async {
    for (final entry in _entries) {
      try {
        await File(entry.localPath).delete();
      } catch (e, st) {
        debugPrint('ArchiveCache: failed to delete ${entry.localPath} during clear: $e\n$st');
      }
    }
    _entries.clear();
    await _saveManifest();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  _CacheEntry? _findByUrl(String url) {
    return _entries.where((e) => e.url == url).firstOrNull;
  }

  Future<void> _trim() async {
    if (_entries.length <= maxArchives) return;

    _entries.sort((a, b) => a.lastAccessedAt.compareTo(b.lastAccessedAt));
    final toEvict = _entries.take(_entries.length - maxArchives).toList();
    _entries = _entries.skip(_entries.length - maxArchives).toList();

    for (final entry in toEvict) {
      try {
        await File(entry.localPath).delete();
        debugPrint('ArchiveCache: evicted ${entry.url}');
      } catch (e, st) {
        debugPrint('ArchiveCache: failed to evict ${entry.url}: $e\n$st');
      }
    }
  }

  // ---- Manifest persistence ----

  String get _manifestPath => p.join(_cachePath!, _manifestName);

  Future<void> _loadManifest() async {
    final file = File(_manifestPath);
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is List) {
        _entries = json.map((e) => _CacheEntry.fromJson(e as Map<String, dynamic>)).toList();
        // Remove entries whose files no longer exist on disk.
        _entries.removeWhere((e) => !File(e.localPath).existsSync());
      }
    } catch (e, st) {
      debugPrint('ArchiveCache: failed to load manifest — $e\n$st');
      _entries = [];
    }
  }

  Future<void> _saveManifest() async {
    try {
      final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await File(_manifestPath).writeAsString(json);
    } catch (e, st) {
      debugPrint('ArchiveCache: failed to save manifest — $e\n$st');
    }
  }

  /// Build a filesystem-safe, unique filename for [url].
  String _safeFilename(String url) {
    final uri = Uri.parse(url);
    final origName = uri.queryParameters['f'] ?? uri.pathSegments.last;
    final safe = origName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final hash = url.hashCode.toRadixString(16);
    return '${hash}_$safe';
  }
}

// =============================================================================
// Manifest entry
// =============================================================================

class _CacheEntry {
  final String url;
  final String localPath;
  DateTime cachedAt;
  DateTime lastAccessedAt;
  final int fileSize;
  final int entryCount;

  _CacheEntry({
    required this.url,
    required this.localPath,
    required this.cachedAt,
    required this.lastAccessedAt,
    required this.fileSize,
    required this.entryCount,
  });

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
        url: json['u'] as String,
        localPath: json['p'] as String,
        cachedAt: DateTime.parse(json['c'] as String),
        lastAccessedAt: DateTime.parse(json['l'] as String),
        fileSize: json['s'] as int,
        entryCount: json['n'] as int,
      );

  Map<String, dynamic> toJson() => {
        'u': url,
        'p': localPath,
        'c': cachedAt.toIso8601String(),
        'l': lastAccessedAt.toIso8601String(),
        's': fileSize,
        'n': entryCount,
      };
}
