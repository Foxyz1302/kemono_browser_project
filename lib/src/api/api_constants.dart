/// HTTP headers required by the pawchive.pw ecosystem.
///
/// The download hosts (`file.pawchive.pw`, `t1.pawchive.pw`) sit behind
/// DDoS-Guard, which rejects browser-like User-Agents with 403 —
/// "pretending to be a browser will result in a block". They ask for an
/// identifiable UA with a way to contact the author, so keep this honest and
/// replace `-dev` with a repo URL once one exists.
///
/// `Referer` is sent for the image CDN; it is not required today but costs
/// nothing and guards against hotlink protection being re-enabled.
class ApiConstants {
  ApiConstants._();

  static const String referer = 'https://pawchive.pw/';
  static const String userAgent = 'KemonoBrowserProject-dev (+discord: foxyz)';

  static const String fileDataBase = 'https://file.pawchive.pw/data';
  static const String thumbDataBase = 'https://img.pawchive.pw/thumbnail/data';
}
