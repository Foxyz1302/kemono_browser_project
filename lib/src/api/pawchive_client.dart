import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'interceptors/auth_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'models.dart';

class PawchiveClient {
  static final PawchiveClient _instance = PawchiveClient._();
  static PawchiveClient get instance => _instance;

  static const _baseUrl = 'https://pawchive.pw';
  static const _apiPrefix = '/api/v1';

  late final Dio dio;
  CookieJar? cookieJar;

  PawchiveClient._();

  /// Initialise the HTTP client: cookie storage, default config, and interceptors.
  ///
  /// [onReLogin] is called by [AuthInterceptor] when a 302/401 response
  /// suggests the session has expired. See [AuthInterceptor] for details.
  Future<void> init({Future<void> Function()? onReLogin}) async {
    final appDir = await getApplicationDocumentsDirectory();
    cookieJar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage('${appDir.path}/.cookies'),
    );

    dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      followRedirects: false,
      validateStatus: (status) => status != null && status < 500,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ));

    dio.interceptors.addAll([
      CookieManager(cookieJar!),
      if (onReLogin != null)
        AuthInterceptor(dio: dio, onReLogin: onReLogin),
      RetryInterceptor(),
    ]);
  }

  Future<Map<String, String>?> login({
    required String username,
    required String password,
  }) async {
    final response = await dio.post(
      '/account/login',
      data: {
        'username': username,
        'password': password,
        'location': '/artists',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        followRedirects: false,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    debugPrint('Login response: status=${response.statusCode}');

    if (response.statusCode == 302) {
      final location = response.headers.value('location');
      final setCookie = response.headers.value('set-cookie');
      if (location != null || setCookie != null) {
        return {'location': location ?? '', 'set_cookie': setCookie ?? ''};
      }
    }

    debugPrint('Login failed: unexpected status ${response.statusCode}');
    return null;
  }

  void _expectOk(Response response, String path) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw PawchiveApiException(status, path);
    }
  }

  /// Fetch all creators from the index.
  ///
  /// NOTE: This endpoint requires `Accept: text/css` — it returns JSON regardless
  /// but rejects requests with `Accept: application/json`. This is a known server
  /// quirk; keep `text/css` until the upstream issue is resolved.
  Future<List<Creator>> getCreators({int? offset}) async {
    final response = await dio.get(
      '$_apiPrefix/creators',
      queryParameters: offset != null ? {'o': offset} : null,
      options: Options(headers: {'Accept': 'text/css'}),
    );
    _expectOk(response, '/creators');
    final list = response.data as List;
    return list.map((j) => CreatorMapper.fromMap(j as Map<String, dynamic>)).toList();
  }

  Future<List<Post>> getCreatorPosts({
    required String service,
    required String creatorId,
  }) async {
    final response = await dio.get('$_apiPrefix/$service/user/$creatorId');
    _expectOk(response, '/$service/user/$creatorId');
    final list = response.data as List;
    return list.map((j) => PostMapper.fromMap(j as Map<String, dynamic>)).toList();
  }

  Future<Post> getSinglePost({
    required String service,
    required String creatorId,
    required String postId,
  }) async {
    final response = await dio.get('$_apiPrefix/$service/user/$creatorId/post/$postId');
    _expectOk(response, '/$service/user/$creatorId/post/$postId');
    return PostMapper.fromMap(response.data as Map<String, dynamic>);
  }

  Future<List<FavoriteCreator>> getFavoriteCreators() async {
    final response = await dio.get(
      '$_apiPrefix/account/favorites',
      queryParameters: {'type': 'creator'},
    );
    _expectOk(response, '/account/favorites');
    final list = response.data as List;
    return list.map((j) => FavoriteCreatorMapper.fromMap(j as Map<String, dynamic>)).toList();
  }

  Future<void> favoriteCreator({
    required String service,
    required String creatorId,
  }) async {
    final response = await dio.post('$_apiPrefix/favorites/creator/$service/$creatorId');
    _expectOk(response, '/favorites/creator/$service/$creatorId');
  }

  Future<void> unfavoriteCreator({
    required String service,
    required String creatorId,
  }) async {
    final response = await dio.delete('$_apiPrefix/favorites/creator/$service/$creatorId');
    _expectOk(response, '/favorites/creator/$service/$creatorId');
  }

  Future<void> favoritePost({
    required String service,
    required String creatorId,
    required String postId,
  }) async {
    final response = await dio.post('$_apiPrefix/favorites/post/$service/$creatorId/$postId');
    _expectOk(response, '/favorites/post/$service/$creatorId/$postId');
  }

  Future<void> unfavoritePost({
    required String service,
    required String creatorId,
    required String postId,
  }) async {
    final response = await dio.delete('$_apiPrefix/favorites/post/$service/$creatorId/$postId');
    _expectOk(response, '/favorites/post/$service/$creatorId/$postId');
  }
}

class PawchiveApiException implements Exception {
  final int statusCode;
  final String path;

  const PawchiveApiException(this.statusCode, this.path);

  @override
  String toString() => 'PawchiveApiException: $statusCode on $path';
}
