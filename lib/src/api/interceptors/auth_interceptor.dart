import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

/// Intercepts session-expiry signals (302 redirect or 401) on auth-gated
/// endpoints, re-authenticates via [onReLogin], and retries the original
/// request once with the newly-established session cookie.
///
/// Only triggers on paths that require authentication (/account/*, /favorites/*).
/// The login endpoint itself (/account/login) is excluded.
///
/// Uses a [_retrying] flag to prevent infinite retry loops when the re-login
/// request or the retried request itself fails.
class AuthInterceptor extends QueuedInterceptor {
  final Dio _dio;
  final Future<void> Function() _onReLogin;
  bool _retrying = false;

  /// Matches auth-gated API paths but excludes /account/login.
  ///
  /// Examples:
  ///   /api/v1/account/favorites        → match
  ///   /api/v1/favorites/creator/...    → match
  ///   /account/login                   → no match (excluded by lookahead)
  ///   /api/v1/creators                 → no match
  static final RegExp _authPaths = RegExp(r'^/(api/v1/)?(account/(?!login)|favorites)');

  AuthInterceptor({
    required this._dio,
    required this._onReLogin,
  });

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final status = response.statusCode;

    // 302 = server redirected (likely to login page, session expired).
    // 401 = explicit unauthorized.
    if ((status == 302 || status == 401) && _isAuthPath(response.requestOptions)) {
      debugPrint('AuthInterceptor: 302/401 on ${response.requestOptions.uri.path} — triggering reLogin');
      if (_retrying) {
        // Already retried — let the original response propagate.
        return handler.next(response);
      }

      _retrying = true;
      _onReLogin().then((_) {
        return _dio.fetch<dynamic>(response.requestOptions);
      }).then((retryResponse) {
        handler.resolve(retryResponse);
      }).catchError((_) {
        // Re-login or retry failed — surface the original error.
        handler.next(response);
      }).whenComplete(() {
        _retrying = false;
      });
      return;
    }

    handler.next(response);
  }

  bool _isAuthPath(RequestOptions options) {
    // uri.path is the clean path without query string, e.g.
    //   /api/v1/account/favorites
    //   /account/login
    return _authPaths.hasMatch(options.uri.path);
  }
}
