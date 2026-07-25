import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/api/models.dart';

void main() {
  group('Creator', () {
    test('fromJson parses snake_case', () {
      final json = {
        'id': '123',
        'name': 'TestCreator',
        'service': 'patreon',
        'indexed': 1700000000,
        'updated': 1700000000,
        'favorited': 42,
        'ever_imported': true,
      };

      final creator = CreatorMapper.fromMap(json);
      expect(creator.id, '123');
      expect(creator.name, 'TestCreator');
      expect(creator.service, 'patreon');
      expect(creator.updated, 1700000000);
      expect(creator.favorited, 42);
      expect(creator.everImported, true);
    });

    test('toJson produces snake_case', () {
      final creator = Creator(
        id: '123',
        name: 'TestCreator',
        service: 'patreon',
        indexed: 1700000000,
        updated: 1700000000,
        favorited: 42,
        everImported: true,
      );

      final json = creator.toMap();
      expect(json['id'], '123');
      expect(json['name'], 'TestCreator');
      expect(json['service'], 'patreon');
      expect(json['updated'], 1700000000);
      expect(json['favorited'], 42);
      expect(json['ever_imported'], true);
    });

    test('round trip', () {
      final json = {
        'id': '123',
        'name': 'TestCreator',
        'service': 'patreon',
        'indexed': 1700000000,
        'updated': 1700000000,
        'favorited': 42,
        'ever_imported': true,
      };

      final creator = CreatorMapper.fromMap(json);
      final result = creator.toMap();
      expect(result, json);
    });
  });

  group('Post', () {
    test('fromJson parses snake_case with all fields', () {
      final json = {
        'id': '456',
        'user': '123',
        'service': 'patreon',
        'title': 'Test Post',
        'content': '<p>Hello world</p>',
        'substring': 'Hello world...',
        'published': '2024-01-15T00:00:00.000Z',
        'file': {
          'name': 'image.jpg',
          'path': '/files/image.jpg',
          'deferred': false,
        },
        'attachments': [
          {'name': 'file.zip', 'path': '/files/file.zip'},
        ],
        'preview_state': 'scraped',
        'has_full': true,
        'origin': 'fanbox',
        'embed': {'url': 'https://example.com'},
        'tags': '{Tag1,Tag2}',
        'added': '2024-01-14T00:00:00.000Z',
        'edited': '2024-01-16T00:00:00.000Z',
      };

      final post = PostMapper.fromMap(json);
      expect(post.id, '456');
      expect(post.user, '123');
      expect(post.service, 'patreon');
      expect(post.title, 'Test Post');
      expect(post.content, '<p>Hello world</p>');
      expect(post.substring, 'Hello world...');
      expect(post.published, '2024-01-15T00:00:00.000Z');
      expect(post.file!.name, 'image.jpg');
      expect(post.attachments.length, 1);
      expect(post.attachments[0].name, 'file.zip');
      expect(post.previewState, 'scraped');
      expect(post.hasFull, true);
      expect(post.origin, 'fanbox');
      expect(post.embed!['url'], 'https://example.com');
      expect(post.tags, '{Tag1,Tag2}');
      expect(post.added, '2024-01-14T00:00:00.000Z');
      expect(post.edited, '2024-01-16T00:00:00.000Z');
    });

    test('fromJson handles minimal fields', () {
      final json = {
        'id': '456',
        'user': '123',
        'service': 'patreon',
        'title': 'Minimal Post',
        'published': '2024-01-15T00:00:00.000Z',
        'attachments': [],
        'has_full': false,
      };

      final post = PostMapper.fromMap(json);
      expect(post.content, isNull);
      expect(post.substring, isNull);
      expect(post.file, isNull);
      expect(post.attachments, isEmpty);
      expect(post.previewState, isNull);
      expect(post.hasFull, false);
      expect(post.origin, isNull);
      expect(post.embed, isNull);
      expect(post.tags, isNull);
      expect(post.added, isNull);
      expect(post.edited, isNull);
    });

    test('fromJson handles empty object file (kemono file: {} quirk)', () {
      final json = {
        'id': '456',
        'user': '123',
        'service': 'patreon',
        'title': 'No File Post',
        'published': '2024-01-15T00:00:00.000Z',
        'file': <String, dynamic>{},
        'attachments': [],
        'has_full': false,
      };

      final post = PostMapper.fromMap(json);
      expect(post.file, isNull);
    });

    test('fromJson decodes real file object normally', () {
      final json = {
        'id': '456',
        'user': '123',
        'service': 'patreon',
        'title': 'File Post',
        'published': '2024-01-15T00:00:00.000Z',
        'file': {'name': 'image.jpg', 'path': '/files/image.jpg'},
        'attachments': [],
        'has_full': true,
      };

      final post = PostMapper.fromMap(json);
      expect(post.file, isNotNull);
      expect(post.file!.name, 'image.jpg');
    });

    test('round trip', () {
      final json = {
        'id': '456',
        'user': '123',
        'service': 'patreon',
        'title': 'Test',
        'published': '2024-01-15T00:00:00.000Z',
        'content': null,
        'substring': null,
        'file': null,
        'attachments': [],
        'preview_state': null,
        'has_full': false,
        'origin': null,
        'embed': null,
        'tags': null,
        'added': null,
        'edited': null,
      };

      final post = PostMapper.fromMap(json);
      final result = post.toMap();
      expect(result, json);
    });
  });

  group('FileInfo', () {
    test('fromJson parses snake_case', () {
      final json = {
        'name': 'file.jpg',
        'path': '/files/file.jpg',
        'deferred': true,
      };

      final file = FileInfoMapper.fromMap(json);
      expect(file.name, 'file.jpg');
      expect(file.path, '/files/file.jpg');
      expect(file.deferred, true);
    });

    test('fromJson handles missing deferred', () {
      final json = {
        'name': 'file.jpg',
        'path': '/files/file.jpg',
      };

      final file = FileInfoMapper.fromMap(json);
      expect(file.name, 'file.jpg');
      expect(file.path, '/files/file.jpg');
      expect(file.deferred, isNull);
    });

    test('round trip', () {
      final file = FileInfo(name: 'test.png', path: '/img/test.png', deferred: false);
      final json = file.toMap();
      final restored = FileInfoMapper.fromMap(json);
      expect(restored.name, file.name);
      expect(restored.path, file.path);
      expect(restored.deferred, file.deferred);
    });
  });

  group('FavoriteCreator', () {
    test('fromJson parses snake_case', () {
      final json = {
        'id': '123',
        'name': 'TestCreator',
        'service': 'patreon',
        'updated': '2024-01-15T00:00:00.000Z',
        'ever_imported': true,
        'last_imported': '2024-01-14T00:00:00.000Z',
        'kemono_favorited': 5,
      };

      final fc = FavoriteCreatorMapper.fromMap(json);
      expect(fc.id, '123');
      expect(fc.name, 'TestCreator');
      expect(fc.service, 'patreon');
      expect(fc.updated, '2024-01-15T00:00:00.000Z');
      expect(fc.everImported, true);
      expect(fc.lastImported, '2024-01-14T00:00:00.000Z');
      expect(fc.kemonoFavorited, 5);
    });

    test('fromJson handles missing lastImported', () {
      final json = {
        'id': '123',
        'name': 'TestCreator',
        'service': 'patreon',
        'updated': '2024-01-15T00:00:00.000Z',
        'ever_imported': false,
        'kemono_favorited': 0,
      };

      final fc = FavoriteCreatorMapper.fromMap(json);
      expect(fc.lastImported, isNull);
      expect(fc.everImported, false);
      expect(fc.kemonoFavorited, 0);
    });

    test('round trip', () {
      final json = {
        'id': '123',
        'name': 'TestCreator',
        'service': 'patreon',
        'updated': '2024-01-15T00:00:00.000Z',
        'ever_imported': true,
        'last_imported': null,
        'kemono_favorited': 5,
      };

      final fc = FavoriteCreatorMapper.fromMap(json);
      final result = fc.toMap();
      expect(result, json);
    });
  });
}
