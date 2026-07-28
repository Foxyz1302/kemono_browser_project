import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../api/api_constants.dart';

class DioFileService extends FileService {
  final Dio _dio;
  final Map<String, CancelToken> _activeTokens = {};

  DioFileService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              responseType: ResponseType.stream,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'Referer': ApiConstants.referer,
                'User-Agent': ApiConstants.userAgent,
              },
            ));

  void cancelRequest(String url) {
    _activeTokens.remove(url)?.cancel();
  }

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    final token = CancelToken();
    _activeTokens[url] = token;
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
        cancelToken: token,
      );
      return DioFileServiceResponse(response);
    } finally {
      // Guard: only remove THIS request's token, not a newer one that may have
      // been inserted by a subsequent request for the same URL whose
      // _activeTokens[url] assignment raced with our finally block.
      if (identical(_activeTokens[url], token)) {
        _activeTokens.remove(url);
      }
    }
  }
}

class DioFileServiceResponse implements FileServiceResponse {
  final Response<ResponseBody> _response;

  DioFileServiceResponse(this._response);

  @override
  Stream<List<int>> get content => _response.data!.stream;

  @override
  int? get contentLength {
    final cl = _response.headers.value('content-length');
    return cl != null ? int.tryParse(cl) : null;
  }

  @override
  String? get eTag => _response.headers.value('etag');

  @override
  String get fileExtension {
    final contentType = _response.headers.value('content-type');
    if (contentType != null) {
      final ext = _extensionFromMime(contentType);
      if (ext != null) return ext;
    }
    final uri = Uri.tryParse(_response.realUri.toString());
    if (uri != null) {
      final path = uri.path;
      final dot = path.lastIndexOf('.');
      if (dot != -1) {
        final ext = path.substring(dot).split('?').first.toLowerCase();
        if (ext.length <= 5) return ext;
      }
    }
    return '.bin';
  }

  @override
  int get statusCode => _response.statusCode ?? 200;

  @override
  DateTime get validTill {
    final cacheControl = _response.headers.value('cache-control');
    if (cacheControl != null) {
      final maxAgeMatch = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
      if (maxAgeMatch != null) {
        final seconds = int.parse(maxAgeMatch.group(1)!);
        return DateTime.now().add(Duration(seconds: seconds));
      }
    }
    return DateTime.now().add(const Duration(days: 30));
  }

  static String? _extensionFromMime(String mime) {
    final type = mime.split(';').first.trim().toLowerCase();
    return switch (type) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/avif' => '.avif',
      'image/bmp' => '.bmp',
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      _ => null,
    };
  }
}
