import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  late Directory tempDir;
  late ImageMetaStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('meta_store_test');
    store = ImageMetaStore.instance;
    await store.init(tempDir);
  });

  tearDown(() async {
    store.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('record and lookup', () {
    test('records dims and bytes from real PNG file', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      final meta = await store.record('https://example.com/img.png', file);
      expect(meta, isNotNull);
      expect(meta!.width, 1);
      expect(meta.height, 1);
      expect(meta.bytes, greaterThan(0));

      final lookup = store.lookup('https://example.com/img.png');
      expect(lookup, isNotNull);
      expect(lookup!.width, 1);
    });

    test('does not re-read if already recorded', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      final meta1 = await store.record('https://example.com/img.png', file);
      final meta2 = await store.record('https://example.com/img.png', file);
      expect(identical(meta1, meta2), isTrue);
    });

    test('lookup returns null for unknown url', () {
      expect(store.lookup('https://example.com/missing.png'), isNull);
    });
  });

  group('persistence', () {
    test('flush writes JSON to disk and re-loads on init', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://example.com/img.png', file);
      await store.flush();

      store.clear();
      await store.init(tempDir);
      final meta = store.lookup('https://example.com/img.png');
      expect(meta, isNotNull);
      expect(meta!.width, 1);
      expect(meta.height, 1);
    });

    test('prunes entries older than 30 days on init', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://example.com/new.png', file);
      await store.flush();

      final json = {
        'https://example.com/new.png': {
          'w': 1, 'h': 1, 'b': 100,
          't': DateTime.now().subtract(const Duration(days: 60)).millisecondsSinceEpoch,
        },
        'https://example.com/fresh.png': {
          'w': 2, 'h': 2, 'b': 200,
          't': DateTime.now().millisecondsSinceEpoch,
        },
      };
      await File('${tempDir.path}/kemono_image_meta.json').writeAsString(jsonEncode(json));

      store.clear();
      await store.init(tempDir);
      expect(store.lookup('https://example.com/new.png'), isNull);
      expect(store.lookup('https://example.com/fresh.png'), isNotNull);
    });
  });

  group('bytes aggregation', () {
    test('bytesForUrls sums known entries', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://example.com/a.png', file);
      await store.record('https://example.com/b.png', file);

      final total = store.bytesForUrls([
        'https://example.com/a.png',
        'https://example.com/b.png',
        'https://example.com/missing.png',
      ]);
      expect(total, greaterThan(0));
      expect(total, store.lookup('https://example.com/a.png')!.bytes + store.lookup('https://example.com/b.png')!.bytes);
    });

    test('totalTrackedBytes matches sum of all entries', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://example.com/a.png', file);
      await store.record('https://example.com/b.png', file);
      expect(store.totalTrackedBytes, store.entryCount * file.lengthSync());
    });
  });

  group('remove and clear', () {
    test('remove drops entry and persists', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://example.com/img.png', file);
      store.remove('https://example.com/img.png');
      expect(store.lookup('https://example.com/img.png'), isNull);
    });

    test('clear drops all entries', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://example.com/a.png', file);
      await store.record('https://example.com/b.png', file);
      store.clear();
      expect(store.entryCount, 0);
    });
  });

  group('metaReady signal', () {
    test('increments on record', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      final before = store.metaReady.value;
      await store.record('https://example.com/img.png', file);
      expect(store.metaReady.value, before + 1);
    });

    test('increments on remove', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://example.com/img.png', file);
      final before = store.metaReady.value;
      store.remove('https://example.com/img.png');
      expect(store.metaReady.value, before + 1);
    });

    test('does not increment on record of duplicate url', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://example.com/img.png', file);
      final before = store.metaReady.value;
      await store.record('https://example.com/img.png', file);
      expect(store.metaReady.value, before);
    });
  });

  group('post helpers', () {
    test('postCachedBytes sums file + attachments', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://pawchive.pw/files/main.jpg', file);
      await store.record('https://pawchive.pw/files/att1.png', file);

      final post = Post(
        id: '1', user: '123', service: 'patreon', title: 'Test',
        published: '2024-01-15T00:00:00.000Z',
        file: FileInfo(name: 'main.jpg', path: '/files/main.jpg'),
        attachments: [
          FileInfo(name: 'att1.png', path: '/files/att1.png'),
        ],
        hasFull: false,
      );

      final bytes = store.postCachedBytes(post);
      expect(bytes, file.lengthSync() * 2);
    });

    test('postHasMeta returns true when any URL has meta', () async {
      final file = File('${tempDir.path}/test.png');
      await file.writeAsBytes(base64Decode(_pngBase64));

      await store.record('https://pawchive.pw/files/main.jpg', file);

      final post = Post(
        id: '1', user: '123', service: 'patreon', title: 'Test',
        published: '2024-01-15T00:00:00.000Z',
        file: FileInfo(name: 'main.jpg', path: '/files/main.jpg'),
        attachments: [
          FileInfo(name: 'att1.png', path: '/files/att1.png'),
        ],
        hasFull: false,
      );

      expect(store.postHasMeta(post), isTrue);
    });

    test('postHasMeta returns false when no URLs have meta', () {
      final post = Post(
        id: '1', user: '123', service: 'patreon', title: 'Test',
        published: '2024-01-15T00:00:00.000Z',
        file: FileInfo(name: 'main.jpg', path: '/files/main.jpg'),
        attachments: [],
        hasFull: false,
      );

      expect(store.postHasMeta(post), isFalse);
    });
  });

  group('formatBytes', () {
    test('formats bytes', () {
      expect(ImageMetaStore.formatBytes(0), '0 B');
      expect(ImageMetaStore.formatBytes(512), '512 B');
      expect(ImageMetaStore.formatBytes(1024), '1.0 KB');
      expect(ImageMetaStore.formatBytes(1536), '1.5 KB');
      expect(ImageMetaStore.formatBytes(1048576), '1.0 MB');
      expect(ImageMetaStore.formatBytes(2621440), '2.5 MB');
      expect(ImageMetaStore.formatBytes(1073741824), '1.0 GB');
    });
  });
}
