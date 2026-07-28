import 'dart:math' as math;

import 'package:dio/dio.dart';

/// Intercepts transient HTTP failures (connection timeouts, receive timeouts,
/// server errors) and retries with exponential backoff.
///
/// Does NOT retry:
/// - Client errors (4xx) — the request or auth state needs changing.
/// - Cancellations — the caller explicitly asked to stop.
/// - Requests that have already been retried [maxRetries] times.
class RetryInterceptor extends QueuedInterceptor {
  final int maxRetries;
  final Duration baseDelay;

  RetryInterceptor({this.maxRetries = 3, this.baseDelay = const Duration(seconds: 1)});

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_shouldRetry(err)) {
      return handler.next(err);
    }

    final retryCount = err.requestOptions.extra['retryCount'] as int? ?? 0;
    if (retryCount >= maxRetries) {
      return handler.next(err);
    }

    for (var i = retryCount; i < maxRetries; i++) {
      final delay = baseDelay * math.pow(2, i - retryCount).toInt();
      await Future.delayed(delay);
      try {
        err.requestOptions.extra['retryCount'] = i + 1;
        final response = await Dio().fetch<dynamic>(err.requestOptions);
        return handler.resolve(response);
      } catch (_) {
        // Continue to next retry — the error is captured in the next
        // iteration or falls through to handler.next() below.
      }
    }

    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    // Never retry explicit cancellations.
    if (err.type == DioExceptionType.cancel) return false;

    // Never retry client errors.
    if (err.response != null && err.response!.statusCode! < 500) return false;

    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode ?? 0) >= 500;
  }
}
