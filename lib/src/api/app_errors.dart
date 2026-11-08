import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';

/// A single captured failure, kept in a bounded log so the user can copy the
/// real reason instead of a useless "status 400".
@immutable
class AppErrorEntry {
  final DateTime at;
  final String source;
  final String? method;
  final String uri;
  final int? status;
  final String? reason;
  final String? body;

  const AppErrorEntry({
    required this.at,
    required this.source,
    this.method,
    required this.uri,
    this.status,
    this.reason,
    this.body,
  });

  String get headline {
    final code = status == null ? '' : ' $status';
    final why = reason == null ? '' : ' — $reason';
    return '[$source]${method == null ? '' : ' $method'} $uri$code$why';
  }

  String toText() {
    final b = body;
    return '${at.toIso8601String()}  $headline${b == null ? '' : '\n    $b'}';
  }
}

/// Classifies a response body into a short reason. The download hosts explain
/// themselves in plain text: `link expired`, `bad signature`, or the DDoS-Guard
/// "are you a bot" paragraph.
String? classifyBody(String? body) {
  if (body == null || body.isEmpty) return null;
  final trimmed = body.trim();
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('link expired')) return 'link expired';
  if (lower.startsWith('bad signature')) return 'bad signature';
  if (lower.contains('are you a bot') || lower.contains('pretending to be a browser')) {
    return 'blocked by ddos-guard (browser-like user agent)';
  }
  if (trimmed.startsWith('<!doctype html') || trimmed.startsWith('<html')) return 'html error page';
  if (trimmed.length <= 120 && !trimmed.startsWith('{') && !trimmed.startsWith('[')) return trimmed;
  return null;
}

/// Truncates a body for storage, keeping it on one line where possible.
String? summarizeBody(Object? data, {int limit = 800}) {
  if (data == null) return null;
  String text;
  if (data is String) {
    text = data;
  } else if (data is Map || data is List) {
    try {
      text = jsonEncode(data);
    } catch (_) {
      text = data.toString();
    }
  } else {
    return null;
  }
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  return text.length <= limit ? text : '${text.substring(0, limit)}…';
}

/// Strips the query string so signed temporary URLs don't leak into the log.
String safeUri(Uri uri) => '${uri.host}${uri.path}';

AppErrorEntry entryFromResponse(Response response, {String source = 'api'}) {
  final body = summarizeBody(response.data);
  return AppErrorEntry(
    at: DateTime.now(),
    source: source,
    method: response.requestOptions.method,
    uri: safeUri(response.requestOptions.uri),
    status: response.statusCode,
    reason: classifyBody(body),
    body: body,
  );
}

AppErrorEntry entryFromException(DioException error) {
  final response = error.response;
  final body = summarizeBody(response?.data);
  return AppErrorEntry(
    at: DateTime.now(),
    source: 'api',
    method: error.requestOptions.method,
    uri: safeUri(error.requestOptions.uri),
    status: response?.statusCode,
    reason: classifyBody(body) ?? error.type.name,
    body: body,
  );
}

/// Global, bounded error log. Everything that fails for an explainable reason
/// writes here, so the UI can show (and the user can copy) the actual cause.
class AppErrors {
  static final AppErrors instance = AppErrors._();

  AppErrors._();

  static const int maxEntries = 100;

  final Signal<List<AppErrorEntry>> entries = signal<List<AppErrorEntry>>(<AppErrorEntry>[]);

  void add(AppErrorEntry entry) {
    debugPrint('AppError: ${entry.headline}${entry.body == null ? '' : '\n  ${entry.body}'}');
    entries.value = [...entries.value, entry].take(maxEntries).toList();
  }

  void addFile(String url, int status, String? body, {String source = 'file'}) {
    add(AppErrorEntry(
      at: DateTime.now(),
      source: source,
      uri: safeUri(Uri.tryParse(url) ?? Uri()),
      status: status,
      reason: classifyBody(body),
      body: body,
    ));
  }

  void clear() => entries.value = <AppErrorEntry>[];

  String exportText() {
    if (entries.value.isEmpty) return 'No errors recorded.';
    return entries.value.map((e) => e.toText()).join('\n\n');
  }

  AppErrorEntry? lastFor(String path) {
    for (final e in entries.value.reversed) {
      if (e.uri.endsWith(path)) return e;
    }
    return null;
  }
}
