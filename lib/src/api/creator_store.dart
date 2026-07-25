import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/pawchive_client.dart';

/// Manages the creators index on disk without keeping 89K full objects
/// in memory permanently.
///
/// First fetch:
///   1. Stream-downloads API response → creators.json (no buffering)
///   2. Converts to creators.ldl — one JSON object per line
///   3. Builds in-memory index of {id, name, service} (~5 MB)
///
/// Subsequent starts:
///   1. Reads creators.ldl line by line
///   2. Each jsonDecode sees one ~200-byte line → tiny map, immediately GC'd
///   3. No 72 MB spike from parsing the full 12 MB array at once
///
/// No additional packages required — only dart:io + dart:convert.
class CreatorStore {
  final File jsonFile;
  final File ldlFile;

  final List<_CreatorIndexEntry> _index = [];
  bool _ready = false;

  CreatorStore({required String directory, String prefix = 'creators'})
      : jsonFile = File('$directory/$prefix.json'),
        ldlFile = File('$directory/$prefix.ldl');

  bool get isReady => _ready;
  int get count => _index.length;

  List<CreatorIndexResult> search(String query, {int limit = 50}) {
    if (query.isEmpty) {
      return _index.take(limit).map(_toResult).toList();
    }
    final q = query.toLowerCase();
    final results = <CreatorIndexResult>[];
    for (final entry in _index) {
      if (entry.nameLower.contains(q)) {
        results.add(_toResult(entry));
        if (results.length >= limit) break;
      }
    }
    return results;
  }

  Future<void> init({bool refresh = false}) async {
    if (refresh || !await ldlFile.exists()) {
      await _fetch();
    } else {
      await _loadFromLdl();
    }
    _ready = true;
    debugPrint('CreatorStore: ${_index.length} creators indexed');
  }

  Future<void> _fetch() async {
    debugPrint('CreatorStore: fetching from API...');

    // 1. Stream download — never holds the response body in memory
    await PawchiveClient.instance.dio.download(
      '/api/v1/creators',
      jsonFile.path,
    );

    // 2. Convert JSON array → line-delimited + build index
    //    One-time jsonDecode of 12 MB → 72 MB spike, then freed.
    await _convertToLdl();

    debugPrint('CreatorStore: done (${_index.length} creators)');
  }

  Future<void> _convertToLdl() async {
    _index.clear();
    final text = await jsonFile.readAsString();
    final list = jsonDecode(text) as List;
    final sink = ldlFile.openWrite(encoding: utf8);

    for (final item in list) {
      final map = item as Map<String, dynamic>;
      sink.writeln(jsonEncode(map));
      _index.add(_CreatorIndexEntry(
        id: map['id'] as String,
        name: map['name'] as String,
        service: map['service'] as String,
      ));
    }

    await sink.close();
    // List<Map> (~72 MB) is now eligible for GC
  }

  Future<void> _loadFromLdl() async {
    _index.clear();
    final lines = await ldlFile.readAsLines();

    for (final line in lines) {
      if (line.isEmpty) continue;
      // Parse ONE small object at a time — tiny allocation
      final map = jsonDecode(line) as Map<String, dynamic>;
      _index.add(_CreatorIndexEntry(
        id: map['id'] as String,
        name: map['name'] as String,
        service: map['service'] as String,
      ));
    }
  }

  CreatorIndexResult _toResult(_CreatorIndexEntry e) => CreatorIndexResult(
        id: e.id,
        name: e.name,
        service: e.service,
      );
}

class CreatorIndexResult {
  final String id;
  final String name;
  final String service;

  const CreatorIndexResult({
    required this.id,
    required this.name,
    required this.service,
  });
}

class _CreatorIndexEntry {
  final String id;
  final String name;
  final String service;
  final String nameLower;

  _CreatorIndexEntry({
    required this.id,
    required this.name,
    required this.service,
  }) : nameLower = name.toLowerCase();
}
