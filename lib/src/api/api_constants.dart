/// HTTP headers required by the pawchive.pw ecosystem.
///
/// `Referer` is required by img.pawchive.pw and file.pawchive.pw (CDN hotlink
/// protection). The browser User-Agent is sent alongside it — some CDNs reject
/// requests with a bare Dart/Dio User-Agent.
class ApiConstants {
  ApiConstants._();

  static const String referer = 'https://pawchive.pw/';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
}
