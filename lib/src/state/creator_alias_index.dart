import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'nfkc_map.dart';

/// Offline alias index for creator search (bundled as `data/creators_alias.bin`).
///
/// The bin maps normalized alias keys (danbooru names, other names, group
/// names, fanbox/pixiv/twitter handles) to kemono creators (service + id).
/// Keys are already NFKC-normalized by the desktop build script; queries must
/// be normalized with [normalizeQuery] before use.
class CreatorAliasIndex {
  CreatorAliasIndex._(this._keysByRef);

  final Map<String, List<String>> _keysByRef;

  static const String defaultAssetPath = 'data/creators_alias.bin';

  static Future<CreatorAliasIndex> loadFromAsset({String path = defaultAssetPath}) async {
    final data = await rootBundle.load(path);
    return parse(data.buffer.asUint8List());
  }

  static CreatorAliasIndex parse(Uint8List bytes) {
    var pos = 0;
    if (bytes.length < 5 || String.fromCharCodes(bytes, 0, 4) != 'DKBI') {
      throw const FormatException('Bad alias index header');
    }
    pos = 4;
    final version = bytes[pos++];
    if (version != 1) throw FormatException('Unsupported alias index version $version');
    final serviceCount = bytes[pos++];
    final services = List<String>.generate(serviceCount, (_) {
      final len = bytes[pos++];
      final s = String.fromCharCodes(bytes, pos, pos + len);
      pos += len;
      return s;
    });
    final keysByRef = <String, List<String>>{};
    final keyCount = _readVarint(bytes, pos);
    pos = keyCount.$2;
    for (var i = 0; i < keyCount.$1; i++) {
      final kv = _readVarint(bytes, pos);
      pos = kv.$2;
      final key = utf8.decode(bytes.sublist(pos, pos + kv.$1));
      pos += kv.$1;
      final nv = _readVarint(bytes, pos);
      pos = nv.$2;
      for (var j = 0; j < nv.$1; j++) {
        final si = bytes[pos++];
        final idv = _readVarint(bytes, pos);
        pos = idv.$2;
        final ref = '${services[si]}/${idv.$1}';
        (keysByRef[ref] ??= []).add(key);
      }
    }
    return CreatorAliasIndex._(keysByRef);
  }

  /// Normalized alias keys for [service]/[id], or const [] when the creator
  /// has no danbooru match.
  List<String> extrasFor(String service, String id) =>
      _keysByRef['$service/$id'] ?? const [];

  static const _stripSuffix = '._- 〇。、・！？!?';

  /// Mirrors the build script's key normalization: NFKC via [nfkcMap],
  /// lowercase, strip leading '@'/'#' and trailing punctuation.
  static String normalizeQuery(String s) {
    if (s.isEmpty) return s;
    final sb = StringBuffer();
    for (final cp in s.runes) {
      sb.writeCharCode(nfkcMap[cp] ?? cp);
    }
    var out = sb.toString().toLowerCase();
    out = out.trim();
    while (out.isNotEmpty && (out.codeUnitAt(0) == 0x40 || out.codeUnitAt(0) == 0x23)) {
      out = out.substring(1);
    }
    while (out.isNotEmpty && _stripSuffix.contains(out[out.length - 1])) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  static (int, int) _readVarint(Uint8List bytes, int pos) {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = bytes[pos++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) return (result, pos);
      shift += 7;
    }
  }
}