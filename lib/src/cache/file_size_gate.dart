/// Decides which files may load without asking the user first.
///
/// The size arrives in the response headers, so the gate costs no extra
/// request: the first attempt doubles as the probe. Thumbnails are on a
/// different host and never hit the threshold anyway.
class FileSizeGate {
  FileSizeGate._();

  /// Files above this size show a "load anyway" button instead of loading.
  static int thresholdBytes = 20 * 1024 * 1024;

  /// URLs the user explicitly allowed for this session.
  static final Set<String> _allowed = {};

  static String keyFor(String url) => url.split('?').first;

  static bool isAllowed(String url) => _allowed.contains(keyFor(url));

  static void allow(String url) => _allowed.add(keyFor(url));

  static void reset() => _allowed.clear();

  /// Only pawchive's own download hosts are gated; banners, icons and
  /// thumbnails live elsewhere and are small.
  static bool appliesTo(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host == null || !host.endsWith('pawchive.pw')) return false;
    return host.startsWith('file.') || host.startsWith('t') || RegExp(r'^n\d+\.').hasMatch(host);
  }

  static bool shouldBlock(String url, int bytes) {
    if (bytes <= thresholdBytes) return false;
    if (!appliesTo(url)) return false;
    return !isAllowed(url);
  }
}
