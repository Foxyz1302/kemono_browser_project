import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/api/pawchive_client.dart';

void main() {
  group('PawchiveClient', () {
    late PawchiveClient client;
    late Dio dio;

    setUp(() {
      client = PawchiveClient.instance;
      dio = Dio(BaseOptions(
        baseUrl: 'https://pawchive.pw',
        validateStatus: (status) => status != null && status < 500,
      ));
      client.dio = dio;
    });

    test('getCreators builds correct URL', () async {
      final adapter = MockAdapter(requestHandler: (request) {
        expect(request.method, 'GET');
        expect(request.path, '/api/v1/creators');
        expect(request.queryParameters, {'o': 0});
        return ResponseBody.fromString('[]', 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      });
      dio.httpClientAdapter = adapter;

      await client.getCreators(offset: 0);
    });

    test('getCreatorPosts builds correct URL', () async {
      final adapter = MockAdapter(requestHandler: (request) {
        expect(request.method, 'GET');
        expect(request.path, '/api/v1/patreon/user/123');
        return ResponseBody.fromString('[]', 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      });
      dio.httpClientAdapter = adapter;

      await client.getCreatorPosts(service: 'patreon', creatorId: '123');
    });

    test('getSinglePost builds correct URL', () async {
      final adapter = MockAdapter(requestHandler: (request) {
        expect(request.method, 'GET');
        expect(request.path, '/api/v1/patreon/user/123/post/456');
        return ResponseBody.fromString('{"id":"456","user":"123","service":"patreon","title":"Test","published":"2024-01-15T00:00:00.000Z","attachments":[],"has_full":false}', 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      });
      dio.httpClientAdapter = adapter;

      await client.getSinglePost(service: 'patreon', creatorId: '123', postId: '456');
    });

    test('getFavoriteCreators builds correct URL', () async {
      final adapter = MockAdapter(requestHandler: (request) {
        expect(request.method, 'GET');
        expect(request.path, '/api/v1/account/favorites');
        expect(request.queryParameters, {'type': 'creator'});
        return ResponseBody.fromString('[]', 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      });
      dio.httpClientAdapter = adapter;

      await client.getFavoriteCreators();
    });

    test('favoriteCreator sends POST to correct URL', () async {
      final adapter = MockAdapter(requestHandler: (request) {
        expect(request.method, 'POST');
        expect(request.path, '/api/v1/favorites/creator/patreon/123');
        return ResponseBody.fromString('', 204);
      });
      dio.httpClientAdapter = adapter;

      await client.favoriteCreator(service: 'patreon', creatorId: '123');
    });

    test('unfavoriteCreator sends DELETE to correct URL', () async {
      final adapter = MockAdapter(requestHandler: (request) {
        expect(request.method, 'DELETE');
        expect(request.path, '/api/v1/favorites/creator/patreon/123');
        return ResponseBody.fromString('', 204);
      });
      dio.httpClientAdapter = adapter;

      await client.unfavoriteCreator(service: 'patreon', creatorId: '123');
    });

    test('favoritePost sends POST to correct URL', () async {
      final adapter = MockAdapter(requestHandler: (request) {
        expect(request.method, 'POST');
        expect(request.path, '/api/v1/favorites/post/patreon/123/456');
        return ResponseBody.fromString('', 204);
      });
      dio.httpClientAdapter = adapter;

      await client.favoritePost(service: 'patreon', creatorId: '123', postId: '456');
    });

    test('unfavoritePost sends DELETE to correct URL', () async {
      final adapter = MockAdapter(requestHandler: (request) {
        expect(request.method, 'DELETE');
        expect(request.path, '/api/v1/favorites/post/patreon/123/456');
        return ResponseBody.fromString('', 204);
      });
      dio.httpClientAdapter = adapter;

      await client.unfavoritePost(service: 'patreon', creatorId: '123', postId: '456');
    });

    test('login sends POST with urlencoded form data to /account/login', () async {
      final adapter = MockAdapter(requestHandler: (request) {
        expect(request.method, 'POST');
        expect(request.path, '/account/login');
        expect(request.contentType, contains('application/x-www-form-urlencoded'));
        return ResponseBody.fromString('', 302, headers: {
          'location': ['/artists?logged_in=yes&role=consumer'],
          'set-cookie': ['session=abc123'],
        });
      });
      dio.httpClientAdapter = adapter;

      final result = await client.login(username: 'foxyz', password: 'secret');
      expect(result, isNotNull);
      expect(result!['location'], '/artists?logged_in=yes&role=consumer');
      expect(result['set_cookie'], 'session=abc123');
    });

    test('login returns null on non-302 status', () async {
      final adapter = MockAdapter(requestHandler: (_) {
        return ResponseBody.fromString('', 200);
      });
      dio.httpClientAdapter = adapter;

      final result = await client.login(username: 'foxyz', password: 'secret');
      expect(result, isNull);
    });

    test('throws PawchiveApiException on non-2xx GET', () async {
      final adapter = MockAdapter(requestHandler: (_) {
        return ResponseBody.fromString('<html>Unauthorized</html>', 401);
      });
      dio.httpClientAdapter = adapter;

      expect(
        () => client.getFavoriteCreators(),
        throwsA(isA<PawchiveApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('throws PawchiveApiException on non-2xx favorite POST', () async {
      final adapter = MockAdapter(requestHandler: (_) {
        return ResponseBody.fromString('', 403);
      });
      dio.httpClientAdapter = adapter;

      expect(
        () => client.favoriteCreator(service: 'patreon', creatorId: '123'),
        throwsA(isA<PawchiveApiException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });
  });
}

class MockAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions request) requestHandler;

  MockAdapter({required this.requestHandler});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return requestHandler(options);
  }

  @override
  void close({bool force = false}) {}
}
