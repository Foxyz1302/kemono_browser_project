import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:signals/signals.dart';

/// A post the user flagged while browsing, with a note about what looked wrong.
///
/// Post payloads can be re-fetched later; what cannot is the state the files
/// were in at the moment of flagging (a temporary link that later became
/// stored, or vice versa) and the note itself.
class PostFlag {
  final String key;
  final String url;
  final String service;
  final String creatorId;
  final String postId;
  final String title;
  final String comment;
  final String createdAt;
  final bool hasFull;
  final String? previewState;
  final List<Map<String, dynamic>> files;

  const PostFlag({
    required this.key,
    required this.url,
    required this.service,
    required this.creatorId,
    required this.postId,
    required this.title,
    required this.comment,
    required this.createdAt,
    required this.hasFull,
    this.previewState,
    this.files = const [],
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'url': url,
        'service': service,
        'creatorId': creatorId,
        'postId': postId,
        'title': title,
        'comment': comment,
        'createdAt': createdAt,
        'hasFull': hasFull,
        if (previewState != null) 'previewState': previewState,
        if (files.isNotEmpty) 'files': files,
      };

  static PostFlag? fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    if (key is! String) return null;
    return PostFlag(
      key: key,
      url: json['url'] as String? ?? '',
      service: json['service'] as String? ?? '',
      creatorId: json['creatorId'] as String? ?? '',
      postId: json['postId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      hasFull: json['hasFull'] as bool? ?? true,
      previewState: json['previewState'] as String?,
      files: (json['files'] as List?)?.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() ?? const [],
    );
  }
}

/// Local flag store. One flag per post — flagging again updates the note.
///
/// Lives in the app documents directory, next to nothing else the user can
/// lose; writes go through a temp file so a crash cannot truncate the list.
class FlagsStore {
  static final FlagsStore instance = FlagsStore._();

  FlagsStore._();

  static const String _fileName = 'kemono_flags.json';

  final Signal<List<PostFlag>> flags = signal<List<PostFlag>>(<PostFlag>[]);
  String? _filePath;

  Future<String> get _path async {
    final cached = _filePath;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    return _filePath = p.join(dir.path, _fileName);
  }

  Future<void> init() async {
    try {
      final file = File(await _path);
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final list = decoded['flags'];
      if (list is! List) return;
      flags.value = list
          .whereType<Map>()
          .map((e) => PostFlag.fromJson(e.cast<String, dynamic>()))
          .whereType<PostFlag>()
          .toList();
    } catch (e, st) {
      debugPrint('FlagsStore: failed to load flags: $e\n$st');
    }
  }

  bool isFlagged(String key) => flags.value.any((f) => f.key == key);

  PostFlag? forKey(String key) {
    for (final f in flags.value) {
      if (f.key == key) return f;
    }
    return null;
  }

  Future<void> save(PostFlag flag) async {
    final next = [...flags.value.where((f) => f.key != flag.key), flag];
    flags.value = next;
    await _persist(next);
  }

  Future<void> remove(String key) async {
    final next = flags.value.where((f) => f.key != key).toList();
    flags.value = next;
    await _persist(next);
  }

  Future<void> clear() async {
    flags.value = <PostFlag>[];
    await _persist(const []);
  }

  Future<void> _persist(List<PostFlag> next) async {
    try {
      final path = await _path;
      final tmp = File('$path.tmp');
      await tmp.writeAsString(jsonEncode({
        'version': 1,
        'flags': next.map((f) => f.toJson()).toList(),
      }), flush: true);
      await tmp.rename(path);
    } catch (e, st) {
      debugPrint('FlagsStore: failed to save flags: $e\n$st');
    }
  }

  String exportText() {
    if (flags.value.isEmpty) return 'No flags recorded.';
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'flags': flags.value.map((f) => f.toJson()).toList(),
    });
  }
}
