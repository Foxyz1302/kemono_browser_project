import 'package:dio/dio.dart';

import '../app_errors.dart';

/// Records every failed request (status >= 400, or a transport error) with its
/// status, sanitized URI and a truncated response body.
///
/// The client keeps `validateStatus: status < 500`, so 4xx responses reach
/// [onResponse] instead of [onError] — both paths are covered here. Redirects
/// are ignored on purpose: 302 is a normal outcome for login and session
/// expiry in this backend.
class ErrorDescriptorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      AppErrors.instance.add(entryFromResponse(response));
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    AppErrors.instance.add(entryFromException(err));
    handler.next(err);
  }
}
