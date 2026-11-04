import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:signals/signals_flutter.dart';

import '../api/pawchive_client.dart';
import 'app_state.dart';

enum AuthStatus { loggedOut, loading, loggedIn, error }

class AuthState {
  static final AuthState instance = AuthState._();
  AuthState._();

  late final Box _box;
  final authStatus = signal<AuthStatus>(AuthStatus.loggedOut);
  final errorMsg = signal<String?>(null);
  String get username => _box.get('username', defaultValue: '') as String;
  bool get hasSavedCredentials => username.isNotEmpty;

  /// Tracks an in-flight [login] call so concurrent callers (e.g. the
  /// auth-interceptor's re-login path) wait for it instead of starting a
  /// duplicate request.
  Future<void>? _loginFuture;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('kemono_auth');

    // Restore session cookie so authenticated requests work immediately
    // without waiting for restoreSession() → login() to complete.
    final saved = _box.get('sessionCookie', defaultValue: '') as String;
    if (saved.isNotEmpty) {
      PawchiveClient.instance.sessionCookie = saved;
    }
  }

  Future<void> login(String user, String password) async {
    if (_loginFuture != null) {
      debugPrint('login() called while already in-flight — awaiting existing');
      await _loginFuture;
      return;
    }
    _loginFuture = _doLogin(user, password);
    try {
      await _loginFuture;
    } finally {
      _loginFuture = null;
    }
  }

  Future<void> _doLogin(String user, String password) async {
    debugPrint('_doLogin called — setting authStatus to loading');
    authStatus.value = AuthStatus.loading;
    errorMsg.value = null;
    try {
      final client = PawchiveClient.instance;
      final result = await client.login(username: user, password: password);
      if (result.success) {
        await _box.put('username', user);
        await _box.put('password', password);

        // Extract and persist the session cookie from the Set-Cookie header.
        final sessionValue = _parseSessionCookie(result.setCookie);
        if (sessionValue != null) {
          client.sessionCookie = sessionValue;
          await _box.put('sessionCookie', sessionValue);
        } else {
          debugPrint('Warning: no session cookie in login response');
        }

        debugPrint('Login successful, setting loggedIn');
        authStatus.value = AuthStatus.loggedIn;
        AppState.instance.loadFavorites();
      } else {
        authStatus.value = AuthStatus.error;
        errorMsg.value = result.errorMessage ?? 'Login failed — invalid credentials';
        debugPrint('Login rejected: ${result.errorMessage}');
      }
    } on DioException catch (e, st) {
      debugPrint('Login DioException: $e\n$st');
      authStatus.value = AuthStatus.error;
      final msg = switch (e.type) {
        DioExceptionType.connectionTimeout => 'Connection timed out',
        DioExceptionType.sendTimeout => 'Send timed out',
        DioExceptionType.receiveTimeout => 'Receive timed out',
        DioExceptionType.connectionError => 'Cannot reach server — is pawchive.pw down?',
        DioExceptionType.badResponse => 'Server error: ${e.response?.statusCode}',
        DioExceptionType.cancel => 'Request cancelled',
        _ => 'Network error: ${e.message}',
      };
      errorMsg.value = msg;
    } catch (e, st) {
      debugPrint('Login failed: $e\n$st');
      authStatus.value = AuthStatus.error;
      errorMsg.value = 'Login failed — $e';
    }
  }

  Future<void> restoreSession() async {
    final user = _box.get('username', defaultValue: '') as String;
    final pass = _box.get('password', defaultValue: '') as String;
    if (user.isEmpty || pass.isEmpty) {
      authStatus.value = AuthStatus.loggedOut;
      return;
    }
    await login(user, pass);
  }

  /// Re-authenticate with saved credentials. Used by [AuthInterceptor] after
  /// session expiry.
  Future<void> reLogin() async {
    debugPrint('reLogin() called — re-authenticating with saved credentials');
    final user = _box.get('username', defaultValue: '') as String;
    final pass = _box.get('password', defaultValue: '') as String;
    if (user.isEmpty || pass.isEmpty) throw Exception('No saved credentials');
    // Clear the stale cookie before re-login so that the login POST doesn't
    // send a stale session (in case that causes issues with the server).
    PawchiveClient.instance.sessionCookie = null;
    await login(user, pass);
  }

  Future<void> logout() async {
    await _box.delete('username');
    await _box.delete('password');
    await _box.delete('sessionCookie');
    PawchiveClient.instance.sessionCookie = null;
    authStatus.value = AuthStatus.loggedOut;
    errorMsg.value = null;
    AppState.instance.clearFavorites();
  }

  /// Extract the raw session value from a Set-Cookie header.
  ///
  /// Input:  "session=eyJ...abc; Expires=...; HttpOnly; Path=/"
  /// Output: "eyJ...abc"
  String? _parseSessionCookie(String? setCookie) {
    if (setCookie == null) return null;
    final match = RegExp(r'session=([^;]+)').firstMatch(setCookie);
    return match?.group(1);
  }
}
