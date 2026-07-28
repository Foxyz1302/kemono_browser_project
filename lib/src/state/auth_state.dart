import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:signals/signals_flutter.dart';

import '../api/pawchive_client.dart';

enum AuthStatus { loggedOut, loading, loggedIn, error }

class AuthState {
  static final AuthState instance = AuthState._();
  AuthState._();

  late final Box _box;
  final authStatus = signal<AuthStatus>(AuthStatus.loggedOut);
  final errorMsg = signal<String?>(null);
  String get username => _box.get('username', defaultValue: '') as String;
  bool get hasSavedCredentials => username.isNotEmpty;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('kemono_auth');
  }

  Future<void> login(String user, String password) async {
    authStatus.value = AuthStatus.loading;
    errorMsg.value = null;
    try {
      final client = PawchiveClient.instance;
      final result = await client.login(username: user, password: password);
      if (result != null) {
        await _box.put('username', user);
        await _box.put('password', password);
        debugPrint('Login successful, setting loggedIn');
        authStatus.value = AuthStatus.loggedIn;
      } else {
        authStatus.value = AuthStatus.error;
        errorMsg.value = 'Login failed — invalid credentials';
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
  ///
  /// Throws if no credentials are saved or the login request fails.
  Future<void> reLogin() async {
    final user = _box.get('username', defaultValue: '') as String;
    final pass = _box.get('password', defaultValue: '') as String;
    if (user.isEmpty || pass.isEmpty) throw Exception('No saved credentials');
    await login(user, pass);
  }

  Future<void> logout() async {
    await _box.delete('username');
    await _box.delete('password');
    authStatus.value = AuthStatus.loggedOut;
    errorMsg.value = null;
  }
}
