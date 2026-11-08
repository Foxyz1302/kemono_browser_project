import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils.dart';
import 'api_constants.dart';
import 'app_errors.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_descriptor_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'models.dart';

class PawchiveClient {
  static final PawchiveClient _instance = PawchiveClient._();
  static PawchiveClient get instance => _instance;

  static const _apiPrefix = '/api/v1';

  late final Dio dio;

  /// The raw session cookie value (without the "session=" prefix).
  /// Set by [AuthState] after login or re-login.
  String? sessionCookie;

  PawchiveClient._();

  /// Initialise the HTTP client with interceptors.
  ///
  /// [onReLogin] is called by [AuthInterceptor] when a 302/401 response
  /// suggests the session has expired. See [AuthInterceptor] for details.
  Future<void> init({Future<void> Function()? onReLogin}) async {
    dio = Dio(BaseOptions(
      baseUrl: FileHelpers.baseUrl,
      followRedirects: false,
      validateStatus: (status) => status != null && status < 500,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'User-Agent': ApiConstants.userAgent,
      },
    ));

    dio.interceptors.addAll([
      // Attach session cookie on every request.
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (sessionCookie != null) {
            options.headers[HttpHeaders.cookieHeader] =
                'session=$sessionCookie';
          }
          handler.next(options);
        },
      ),
      if (onReLogin != null)
        AuthInterceptor(dio: dio, onReLogin: onReLogin),
      ErrorDescriptorInterceptor(),
      RetryInterceptor(),
    ]);
  }

  /// Log in and report whether the server actually authenticated us.
  ///
  /// Kemono-style backends respond with a 302 redirect on BOTH outcomes:
  ///   success → `Location: /artists?logged_in=yes&role=consumer`
  ///   failure → `Location: /account/login?location=/artists` (session cookie
  ///   carries a "_flashes" message like "Username or password is incorrect").
  /// Treating any 302 as success (the old bug) made failed logins look
  /// successful, saving bad credentials to Hive and looping forever.
  Future<LoginResult> login({
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
    final setCookie = response.headers.value('set-cookie');
    debugPrint('Login Set-Cookie: $setCookie');

    if (response.statusCode == 302) {
      final location = response.headers.value('location');
      // A failed login redirects straight back to the login page.
      final bouncedBackToLogin = location != null && location.startsWith('/account/login');
      if (!bouncedBackToLogin && location != null) {
        return LoginResult(success: true, setCookie: setCookie ?? '');
      }
      final serverMessage = _decodeFailureReason(setCookie);
      debugPrint('Login rejected by server: $serverMessage');
      return LoginResult(
        success: false,
        errorMessage: serverMessage ?? 'Invalid username or password',
      );
    }

    debugPrint('Login failed: unexpected status ${response.statusCode}');
    return LoginResult(
      success: false,
      errorMessage: 'Unexpected server response (${response.statusCode})',
    );
  }

  /// Best-effort retrieval of the server's rejection reason from the Flask
  /// session cookie set on a failed login. The payload is only signed, not
  /// encrypted, and may be zlib-compressed (leading "." on the blob).
  String? _decodeFailureReason(String? setCookie) {
    final match = setCookie == null ? null : RegExp(r'session=([^;]+)').firstMatch(setCookie);
    final cookieValue = match?.group(1);
    if (cookieValue == null) return null;

    // Cookie packet: "<payload>.<timestamp>.<signature>"; when compressed the
    // payload itself is prefixed with a dot (".eJ..."). Decode the first
    // non-empty parts and look for flask's "_flashes" tuple.
    for (final part in cookieValue.split('.')) {
      List<int> bytes;
      try {
        bytes = base64Url.decode(base64Url.normalize(part));
      } catch (_) {
        continue;
      }
      // zlib-deflate the payload if it starts with a zlib header.
      if (bytes.length > 2 && bytes[0] == 0x78 && (bytes[1] == 0x9c || bytes[1] == 0x01)) {
        try {
          bytes = zlib.decode(bytes);
        } catch (_) {
          continue;
        }
      }
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map) {
          final flashes = decoded['_flashes'];
          if (flashes is List) {
            for (final flash in flashes) {
              // Flask TaggedJSONSerializer encodes tuples as {" t": [...]}.
              if (flash is Map && flash[' t'] is List) {
                final t = flash[' t'] as List;
                if (t.length == 2 && t[1] is String && (t[1] as String).isNotEmpty) {
                  return t[1] as String;
                }
              }
            }
          }
        }
      } catch (_) {
        // Not a decodable session payload; keep scanning parts.
      }
    }
    return null;
  }

  void _expectOk(Response response, String path) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      final body = summarizeBody(response.data);
      throw PawchiveApiException(status, path, body: body, reason: classifyBody(body));
    }
  }

  /// Fetch all creators from the index.
  Future<List<Creator>> getCreators({int? offset}) async {
    final response = await dio.get(
      '$_apiPrefix/creators',
      queryParameters: offset != null ? {'o': offset} : null,
    );
    _expectOk(response, '/creators');
    final list = response.data as List;
    return list.map((j) => CreatorMapper.fromMap(j as Map<String, dynamic>)).toList();
  }

  /// Remove attachments with neither a [FileInfo.path] nor a signed
  /// [FileInfo.tempUrl] — nothing can be built from them.
  Post _sanitizePost(Post post) {
    var changed = false;
    final filtered = post.attachments.where((f) {
      if (f.path == null && f.tempUrl == null) {
        changed = true;
        return false;
      }
      return true;
    }).toList();
    final mainFile = (post.file?.path != null || post.file?.tempUrl != null) ? post.file : null;
    if (mainFile != post.file) changed = true;
    if (!changed) return post;
    return post.copyWith(attachments: filtered, file: mainFile);
  }

  Future<List<Post>> getCreatorPosts({
    required String service,
    required String creatorId,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '$_apiPrefix/$service/user/$creatorId',
      queryParameters: offset > 0 ? {'o': offset} : null,
    );
    _expectOk(response, '/$service/user/$creatorId');
    final list = response.data as List;
    return list.map((j) => _sanitizePost(PostMapper.fromMap(j as Map<String, dynamic>))).toList();
  }

  /// Total post count for a creator, scraped from the server-rendered creator
  /// page. The JSON API exposes no count (no header, no wrapper, and
  /// `?count=true` / `/count` are ignored or 404), but the page prints
  /// "Showing 1 - 50 of N" and only when there is more than one page. Returns
  /// null when the creator fits on a single page or the markup changes.
  Future<int?> getCreatorPostCount({
    required String service,
    required String creatorId,
  }) async {
    final response = await dio.get(
      '/$service/user/$creatorId',
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Accept': 'text/html'},
      ),
    );
    _expectOk(response, '/$service/user/$creatorId');
    final html = response.data;
    if (html is! String) return null;
    final match = RegExp(r'Showing\s+\d+\s*-\s*\d+\s+of\s+(\d+)').firstMatch(html);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  Future<Post> getSinglePost({
    required String service,
    required String creatorId,
    required String postId,
  }) async {
    final response = await dio.get('$_apiPrefix/$service/user/$creatorId/post/$postId');
    _expectOk(response, '/$service/user/$creatorId/post/$postId');
    return _sanitizePost(PostMapper.fromMap(response.data as Map<String, dynamic>));
  }

  Future<List<FavoriteCreator>> getFavoriteCreators() async {
    final response = await dio.get(
      '$_apiPrefix/account/favorites',
      queryParameters: {'type': 'artist'},
    );
    _expectOk(response, '/account/favorites');
    final list = response.data as List;
    return list.map((j) => FavoriteCreatorMapper.fromMap(j as Map<String, dynamic>)).toList();
  }

  Future<List<Post>> getFavoritePosts() async {
    final response = await dio.get(
      '$_apiPrefix/account/favorites',
      queryParameters: {'type': 'post'},
    );
    _expectOk(response, '/account/favorites');
    final list = response.data as List;
    return list.map((j) => _sanitizePost(PostMapper.fromMap(j as Map<String, dynamic>))).toList();
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

  /// Truncated response body — the server explains 4xx/5xx failures in it.
  final String? body;

  /// Short classification of [body] when one is recognized.
  final String? reason;

  const PawchiveApiException(this.statusCode, this.path, {this.body, this.reason});

  @override
  String toString() {
    final why = reason == null ? '' : ' ($reason)';
    final b = body == null ? '' : '\n  body: $body';
    return 'PawchiveApiException: $statusCode$why on $path$b';
  }
}

/// Outcome of a [PawchiveClient.login] attempt.
class LoginResult {
  const LoginResult({
    required this.success,
    this.setCookie,
    this.errorMessage,
  });

  final bool success;

  /// The raw `Set-Cookie` header value on success (used to extract the
  /// session cookie).
  final String? setCookie;

  /// Human-readable rejection reason on failure (may mirror the server's own
  /// flash message, e.g. "Username or password is incorrect").
  final String? errorMessage;
}
