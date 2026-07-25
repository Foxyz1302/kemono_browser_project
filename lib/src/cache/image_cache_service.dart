import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dio_file_service.dart';
import 'image_meta_store.dart';

class CacheStats {
  final int fileCount;
  final int totalBytes;
  final DateTime? oldestFile;
  final DateTime? newestFile;

  const CacheStats({
    required this.fileCount,
    required this.totalBytes,
    this.oldestFile,
    this.newestFile,
  });

  double get totalMB => totalBytes / (1024 * 1024);

  @override
  String toString() => 'CacheStats($fileCount files, ${totalMB.toStringAsFixed(1)} MB)';
}

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._();
  static ImageCacheService get instance => _instance;

  static const _key = 'kemono_cache';

  late final DioFileService _fileService;
  late CacheManager cache;

  ImageCacheService._() {
    _fileService = DioFileService();
    cache = CacheManager(Config(
      _key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1000,
      fileService: _fileService,
    ));
  }

  Future<void> init() async {
    final tempDir = await getTemporaryDirectory();
    await ImageMetaStore.instance.init(Directory(p.join(tempDir.path, _key)));
  }

  void cancelDownload(String url) => _fileService.cancelRequest(url);

  Future<void> removeFile(String url) => cache.removeFile(url);

  Future<void> clearCache() async {
    await cache.emptyCache();
    ImageMetaStore.instance.clear();
  }

  Stream<FileResponse> getCachedFileStream(String url, {Map<String, String>? headers}) {
    return cache.getFileStream(
      url,
      key: url.split('?').first,
      headers: headers,
      withProgress: true,
    );
  }

  Future<void> prefetchDims(List<String> urls) async {
    final store = ImageMetaStore.instance;
    final pending = urls.map((u) => u.split('?').first).where((u) => store.lookup(u) == null).toList();
    const batchSize = 4;
    for (var i = 0; i < pending.length; i += batchSize) {
      final end = (i + batchSize > pending.length) ? pending.length : i + batchSize;
      final batch = pending.sublist(i, end);
      await Future.wait(batch.map((url) async {
        try {
          final file = await cache.getSingleFile(url);
          await store.record(url, File(file.path));
        } catch (e, st) {
          debugPrint('prefetchDims failed for $url: $e\n$st');
        }
      }));
    }
  }

  Future<int> purgeUrls(List<String> urls) async {
    final store = ImageMetaStore.instance;
    var freed = 0;
    for (final url in urls) {
      final key = url.split('?').first;
      freed += store.lookup(key)?.bytes ?? 0;
      store.remove(key);
      await cache.removeFile(key);
    }
    return freed;
  }

  Future<CacheStats> getStats() async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, _key));
    if (!await dir.exists()) {
      return const CacheStats(fileCount: 0, totalBytes: 0);
    }

    var count = 0;
    var bytes = 0;
    DateTime? oldest;
    DateTime? newest;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        count++;
        bytes += stat.size;
        final modified = stat.modified;
        if (oldest == null || modified.isBefore(oldest)) oldest = modified;
        if (newest == null || modified.isAfter(newest)) newest = modified;
      }
    }

    return CacheStats(fileCount: count, totalBytes: bytes, oldestFile: oldest, newestFile: newest);
  }
}
