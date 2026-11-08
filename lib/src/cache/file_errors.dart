/// Raised by the file transport for a non-2xx response, carrying the body that
/// the server used to explain itself (`link expired`, `bad signature`, the
/// DDoS-Guard paragraph). [flutter_cache_manager] would otherwise turn the
/// status into an `HttpExceptionWithStatus` with no body at all.
class PawchiveFileException implements Exception {
  final int statusCode;
  final String url;
  final String? reason;
  final String? body;

  const PawchiveFileException(this.statusCode, this.url, {this.reason, this.body});

  bool get isExpiredSignature => reason == 'link expired' || reason == 'bad signature';

  @override
  String toString() {
    final why = reason == null ? '' : ' ($reason)';
    final b = body == null ? '' : '\n  body: $body';
    return 'PawchiveFileException: $statusCode$why on $url$b';
  }
}

/// Raised before the body is transferred when a file exceeds the configured
/// autoload threshold. Nothing is downloaded; the caller decides whether to
/// allow it and retry.
class FileTooLargeException implements Exception {
  final String url;
  final int bytes;

  const FileTooLargeException(this.url, this.bytes);

  @override
  String toString() => 'FileTooLargeException: $bytes bytes on $url';
}
