import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:signals/signals_flutter.dart';

import '../api/models.dart';
import 'image_size_parser.dart';

class ImageMeta {
  final int width;
  final int height;
  final int bytes;
  final int cachedAt;
  final String? creatorId;
  final String? postId;

  const ImageMeta({
    required this.width,
    required this.height,
    required this.bytes,
    required this.cachedAt,
    this.creatorId,
    this.postId,
  });

  double get aspectRatio => height == 0 ? 1 : width / height;

  factory ImageMeta.fromJson(Map<String, dynamic> json) => ImageMeta(
        width: json['w'] as int,
        height: json['h'] as int,
        bytes: json['b'] as int,
        cachedAt: json['t'] as int,
        creatorId: json['c'] as String?,
        postId: json['p'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'w': width,
        'h': height,
        'b': bytes,
        't': cachedAt,
        if (creatorId != null) 'c': creatorId,
        if (postId != null) 'p': postId,
      };
}

class ImageMetaStore {
  static final ImageMetaStore _instance = ImageMetaStore._();
  static ImageMetaStore get instance => _instance;

  static const _stalePeriod = Duration(days: 30);
  static const _metaFileName = 'kemono_image_meta.json';

  final Map<String, ImageMeta> _entries = {};
  final Set<String> _inFlight = {};
  final metaReady = signal<int>(0);

  File? _metaFile;
  Timer? _persistTimer;

  ImageMetaStore._();

  bool get isInitialized => _metaFile != null;

  Map<String, ImageMeta> get allEntries => _entries;

  Future<void> init(Directory dir) async {
    _metaFile = File('${dir.path}/$_metaFileName');
    if (!await _metaFile!.exists()) return;
    try {
      final raw = jsonDecode(await _metaFile!.readAsString()) as Map<String, dynamic>;
      final cutoff = DateTime.now().subtract(_stalePeriod).millisecondsSinceEpoch;
      for (final e in raw.entries) {
        final meta = ImageMeta.fromJson(e.value as Map<String, dynamic>);
        if (meta.cachedAt >= cutoff) _entries[e.key] = meta;
      }
    } catch (e, st) {
      debugPrint('ImageMetaStore: failed to load meta: $e\n$st');
    }
  }

  ImageMeta? lookup(String url) => _entries[url];

  Future<ImageMeta?> record(String url, File file, {String? creatorId, String? postId}) async {
    if (_entries.containsKey(url) || !_inFlight.add(url)) return _entries[url];
    try {
      final bytes = await file.length();
      final raf = await file.open();
      final header = await raf.read(ImageSizeParser.maxHeaderBytes);
      await raf.close();
      var dims = ImageSizeParser.parse(header);
      dims ??= await _decodeDims(file);
      if (dims == null) return null;
      final meta = ImageMeta(
        width: dims.width,
        height: dims.height,
        bytes: bytes,
        cachedAt: DateTime.now().millisecondsSinceEpoch,
        creatorId: creatorId,
        postId: postId,
      );
      _entries[url] = meta;
      metaReady.value++;
      _schedulePersist();
      return meta;
    } catch (e, st) {
      debugPrint('ImageMetaStore: record failed for $url: $e\n$st');
      return null;
    } finally {
      _inFlight.remove(url);
    }
  }

  Future<ImageDims?> _decodeDims(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final dims = ImageDims(frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return dims;
    } catch (e, st) {
      debugPrint('ImageMetaStore: codec decode failed for ${file.path}: $e\n$st');
      return null;
    }
  }

  int bytesForUrls(Iterable<String> urls) {
    var total = 0;
    for (final url in urls) {
      final meta = _entries[url];
      if (meta != null) total += meta.bytes;
    }
    return total;
  }

  int get totalTrackedBytes => _entries.values.fold(0, (sum, m) => sum + m.bytes);

  int get entryCount => _entries.length;

  int bytesForCreator(String creatorId) {
    var total = 0;
    for (final m in _entries.values) {
      if (m.creatorId == creatorId) total += m.bytes;
    }
    return total;
  }

  int bytesForPost(String postId) {
    var total = 0;
    for (final m in _entries.values) {
      if (m.postId == postId) total += m.bytes;
    }
    return total;
  }

  int fileCountForCreator(String creatorId) {
    var count = 0;
    for (final m in _entries.values) {
      if (m.creatorId == creatorId) count++;
    }
    return count;
  }

  List<PostCacheInfo> postsForCreator(String creatorId) {
    final map = <String, _PostCacheAccum>{};
    for (final e in _entries.entries) {
      final m = e.value;
      if (m.creatorId != creatorId || m.postId == null) continue;
      final accum = map.putIfAbsent(m.postId!, () => _PostCacheAccum());
      accum.fileCount++;
      accum.bytes += m.bytes;
    }
    final list = map.entries.map((e) => PostCacheInfo(postId: e.key, fileCount: e.value.fileCount, bytes: e.value.bytes)).toList();
    list.sort((a, b) => b.bytes.compareTo(a.bytes));
    return list;
  }

  Map<String, int> purgeCreator(String creatorId) {
    final urls = <String>[];
    for (final e in _entries.entries) {
      if (e.value.creatorId == creatorId) urls.add(e.key);
    }
    final freed = <String, int>{};
    for (final url in urls) {
      final meta = _entries.remove(url);
      if (meta != null) {
        freed[url] = meta.bytes;
      }
    }
    if (urls.isNotEmpty) {
      metaReady.value++;
      _schedulePersist();
    }
    return freed;
  }

  int postCachedBytes(Post post) {
    final urls = _postUrls(post);
    return bytesForUrls(urls);
  }

  bool postHasMeta(Post post) {
    final urls = _postUrls(post);
    return urls.any((u) => _entries.containsKey(u));
  }

  static List<String> _postUrls(Post post) {
    const base = 'https://img.pawchive.pw/thumbnail/data';
    return [
      if (post.file != null) '$base${post.file!.path}',
      for (final a in post.attachments) '$base${a.path}',
    ];
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void remove(String url) {
    if (_entries.remove(url) != null) {
      metaReady.value++;
      _schedulePersist();
    }
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    metaReady.value++;
    _schedulePersist();
  }

  void _schedulePersist() {
    if (_metaFile == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 1), flush);
  }

  Future<void> flush() async {
    _persistTimer?.cancel();
    final file = _metaFile;
    if (file == null) return;
    try {
      final json = {for (final e in _entries.entries) e.key: e.value.toJson()};
      await file.writeAsString(jsonEncode(json));
    } catch (e, st) {
      debugPrint('ImageMetaStore: persist failed: $e\n$st');
    }
  }
}

class PostCacheInfo {
  final String postId;
  final int fileCount;
  final int bytes;

  const PostCacheInfo({required this.postId, required this.fileCount, required this.bytes});
}

class _PostCacheAccum {
  int fileCount = 0;
  int bytes = 0;
}
