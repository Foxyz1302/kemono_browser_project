import 'dart:async';
import 'dart:io' as io;

import 'package:file/file.dart' as f;
import 'package:file/local.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/cache/image_cache_service.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory tempDir;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => io.Directory.systemTemp.path,
    );
  });

  setUp(() async {
    tempDir = await io.Directory.systemTemp.createTemp('cache_service_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    ImageCacheService.instance.cache = FakeCacheManager();
    final metaDir = io.Directory(p.join(tempDir.path, 'meta'));
    await metaDir.create();
    await ImageMetaStore.instance.init(metaDir);
  });

  tearDown(() async {
    ImageMetaStore.instance.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('purgeUrls', () {
    test('returns freed bytes from meta store', () async {
      final file = const LocalFileSystem().file('${tempDir.path}/test.png');
      await file.writeAsBytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0, 0, 0, 0x0D, 73, 72, 68, 82,
        0, 0, 0, 1, 0, 0, 0, 1,
      ]);

      await ImageMetaStore.instance.record('https://example.com/a.png', file);
      final freed = await ImageCacheService.instance.purgeUrls(['https://example.com/a.png']);
      expect(freed, file.lengthSync());
      expect(ImageMetaStore.instance.lookup('https://example.com/a.png'), isNull);
    });

    test('returns 0 for unknown url', () async {
      final freed = await ImageCacheService.instance.purgeUrls(['https://example.com/missing.png']);
      expect(freed, 0);
    });
  });

  group('clearCache', () {
    test('clears meta store entries', () async {
      final file = const LocalFileSystem().file('${tempDir.path}/test.png');
      await file.writeAsBytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0, 0, 0, 0x0D, 73, 72, 68, 82,
        0, 0, 0, 1, 0, 0, 0, 1,
      ]);

      await ImageMetaStore.instance.record('https://example.com/a.png', file);
      expect(ImageMetaStore.instance.entryCount, 1);

      await ImageCacheService.instance.clearCache();
      expect(ImageMetaStore.instance.entryCount, 0);
    });
  });

  group('getStats', () {
    test('returns zero stats for empty dir', () async {
      final stats = await ImageCacheService.instance.getStats();
      expect(stats.fileCount, 0);
      expect(stats.totalBytes, 0);
    });
  });
}

class FakeCacheManager extends CacheManager {
  FakeCacheManager()
      : super(Config('fake_cache_service_test', fileService: _NoopFileService()));

  @override
  Future<f.File> getSingleFile(String url, {Map<String, String>? headers, String? key}) async {
    throw UnimplementedError();
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {}

  @override
  Future<void> removeFile(String key) async {}

  @override
  Future<void> emptyCache() async {}
}

class _NoopFileService extends FileService {
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) {
    throw UnimplementedError();
  }
}
