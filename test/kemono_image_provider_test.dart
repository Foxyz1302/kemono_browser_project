import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:file/file.dart' as f;
import 'package:file/local.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/cache/image_cache_service.dart';
import 'package:kemono_browser_project/src/cache/kemono_image_provider.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => io.Directory.systemTemp.path,
    );
  });
  group('KemonoImageProvider', () {
    test('obtainKey returns SynchronousFuture of itself', () async {
      final provider = KemonoImageProvider('https://pawchive.pw/files/image.jpg');
      final key = await provider.obtainKey(ImageConfiguration.empty);
      expect(key, isA<KemonoImageProvider>());
      expect(key.url, 'https://pawchive.pw/files/image.jpg');
    });

    test('equals and hashCode based on cacheKey and scale', () {
      final a = KemonoImageProvider('https://pawchive.pw/files/image.jpg?q=1');
      final b = KemonoImageProvider('https://pawchive.pw/files/image.jpg?q=2');
      final c = KemonoImageProvider('https://pawchive.pw/files/image.jpg', scale: 2.0);
      final d = KemonoImageProvider('https://pawchive.pw/files/image.jpg', cacheKey: 'custom_key');

      expect(a == b, isTrue);
      expect(a.hashCode == b.hashCode, isTrue);
      expect(a == c, isFalse);
      expect(b == c, isFalse);
      expect(a == d, isFalse);
    });

    test('canonicalUrl strips query parameters', () {
      expect(
        KemonoImageProvider.canonicalUrl('https://pawchive.pw/files/image.jpg?w=800&h=600'),
        'https://pawchive.pw/files/image.jpg',
      );
      expect(
        KemonoImageProvider.canonicalUrl('https://pawchive.pw/files/image.jpg'),
        'https://pawchive.pw/files/image.jpg',
      );
    });

    test('toString includes url and key', () {
      final provider = KemonoImageProvider('https://pawchive.pw/files/image.jpg');
      final str = provider.toString();
      expect(str, contains('KemonoImageProvider'));
      expect(str, contains('https://pawchive.pw/files/image.jpg'));
    });

    test('identical instances are equal', () {
      final provider = KemonoImageProvider('https://pawchive.pw/files/image.jpg');
      expect(provider == provider, isTrue);
    });

    test('different scale makes unequal', () {
      final a = KemonoImageProvider('https://pawchive.pw/files/image.jpg', scale: 1.0);
      final b = KemonoImageProvider('https://pawchive.pw/files/image.jpg', scale: 2.0);
      expect(a == b, isFalse);
    });

    test('cacheKey overrides canonical url for equality', () {
      final a = KemonoImageProvider('https://pawchive.pw/files/a.jpg', cacheKey: 'same');
      final b = KemonoImageProvider('https://pawchive.pw/files/b.jpg', cacheKey: 'same');
      expect(a == b, isTrue);
    });

    testWidgets('loadImage streams chunk events and decodes cached file', (tester) async {
      await tester.runAsync(() async {
        final dir = await io.Directory.systemTemp.createTemp('kemono_provider_test');
        final file = const LocalFileSystem().file('${dir.path}/test.png');
        await file.writeAsBytes(base64Decode(_pngBase64));

        ImageCacheService.instance.cache = FakeCacheManager(file);

        try {
          const url = 'https://pawchive.pw/files/test.png';
          final provider = KemonoImageProvider(url);
          final completer = provider.loadImage(
            provider,
            PaintingBinding.instance.instantiateImageCodecWithSize,
          );

          expect(completer, isA<MultiFrameImageStreamCompleter>());

          final imageResult = Completer<ImageInfo>();
          final chunkEvents = <ImageChunkEvent>[];
          late ImageStreamListener listener;
          listener = ImageStreamListener(
            (info, _) => imageResult.complete(info),
            onChunk: chunkEvents.add,
            onError: imageResult.completeError,
          );
          completer.addListener(listener);

          final info = await imageResult.future;
          expect(info.image.width, 1);
          expect(info.image.height, 1);
          expect(chunkEvents, isNotEmpty);
          expect(chunkEvents.last.cumulativeBytesLoaded, 100);
          expect(chunkEvents.last.expectedTotalBytes, 100);

          completer.removeListener(listener);
        } finally {
          await dir.delete(recursive: true);
        }
      });
    });

    testWidgets('loadImage propagates error when stream completes without file', (tester) async {
      await tester.runAsync(() async {
        ImageCacheService.instance.cache = FakeCacheManager(null);

        const url = 'https://pawchive.pw/files/missing.png';
        final provider = KemonoImageProvider(url);
        final completer = provider.loadImage(
          provider,
          PaintingBinding.instance.instantiateImageCodecWithSize,
        );

        final errorResult = Completer<Object>();
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (_, _) {},
          onError: (e, _) => errorResult.complete(e),
        );
        completer.addListener(listener);

        final error = await errorResult.future;
        expect(error, isA<Exception>());
        expect(error.toString(), contains('without providing a file'));

        completer.removeListener(listener);
      });
    });
  });
}

class FakeCacheManager extends CacheManager {
  final f.File? file;

  FakeCacheManager(this.file)
      : super(Config('fake_test_cache', fileService: _NoopFileService()));

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    if (file == null) return;
    if (withProgress) {
      yield DownloadProgress(url, 100, 50);
      yield DownloadProgress(url, 100, 100);
    }
    yield FileInfo(file!, FileSource.Cache, DateTime.now().add(const Duration(days: 1)), url);
  }

  @override
  Future<void> removeFile(String key) async {}
}

class _NoopFileService extends FileService {
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) {
    throw UnimplementedError();
  }
}
