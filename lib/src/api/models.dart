import 'package:dart_mappable/dart_mappable.dart';

import 'api_constants.dart';

part 'models.mapper.dart';

@MappableClass(caseStyle: CaseStyle.snakeCase)
class Creator with CreatorMappable {
  final String id;
  final String name;
  final String service;
  final int indexed;
  final int updated;
  final int favorited;
  final bool everImported;

  const Creator({
    required this.id,
    required this.name,
    required this.service,
    required this.indexed,
    required this.updated,
    required this.favorited,
    required this.everImported,
  });
}

class EmptyObjectAsNullHook extends MappingHook {
  const EmptyObjectAsNullHook();

  @override
  Object? beforeDecode(Object? value) {
    if (value is Map && value.isEmpty) return null;
    return value;
  }
}

@MappableClass(caseStyle: CaseStyle.snakeCase)
class Post with PostMappable {
  final String id;
  final String user;
  final String service;
  final String title;
  final String? content;
  final String? substring;
  final String published;
  @MappableField(hook: EmptyObjectAsNullHook())
  final FileInfo? file;
  final List<FileInfo> attachments;
  final String? previewState;
  final bool hasFull;
  final String? origin;
  final Map? embed;
  final String? tags;
  final String? added;
  final String? edited;

  const Post({
    required this.id,
    required this.user,
    required this.service,
    required this.title,
    this.content,
    this.substring,
    required this.published,
    this.file,
    this.attachments = const [],
    this.previewState,
    this.hasFull = false,
    this.origin,
    this.embed,
    this.tags,
    this.added,
    this.edited,
  });

  /// URL for the original file, or null when this post has no full file at all
  /// (`has_full: false`, only previews exist).
  String? downloadUrlFor(FileInfo file) => file.downloadUrl(hasFull: hasFull);

  /// Every file on the post, main file first.
  List<FileInfo> get allFiles => [?file, ...attachments];
}

@MappableClass(caseStyle: CaseStyle.snakeCase)
class FileInfo with FileInfoMappable {
  final String? name;
  final String? path;
  final bool? deferred;

  /// True when pawchive does not store the file and only has a preview.
  /// Informational — [tempUrl] is what decides where the bytes come from.
  final bool? previewOnly;

  /// Signed, short-lived (about 6 hours) URL to the original file. Present when
  /// the file is not stored on pawchive's own nodes.
  final String? tempUrl;

  /// Downloadable companion of a HLS [tempUrl] (videos).
  final String? tempDownloadUrl;

  /// Advisory only: always "now + 15 days", unrelated to [tempUrl]'s real
  /// expiry (the `e=` parameter inside the URL). Do not use for gating.
  final String? tempExpires;

  const FileInfo({
    this.name,
    this.path,
    this.deferred,
    this.previewOnly,
    this.tempUrl,
    this.tempDownloadUrl,
    this.tempExpires,
  });

  bool get isTemporary => tempUrl != null;

  bool get isVideo {
    final n = name;
    if (n == null) return false;
    final ext = n.split('.').last.toLowerCase();
    return const {'mp4', 'webm', 'mkv', 'mov', 'avi', 'm4v', '3gp'}.contains(ext);
  }

  /// Where the original bytes live: the signed URL when pawchive only proxies
  /// the file, otherwise the stable file host path. Null when the post has no
  /// full file (`hasFull == false`) or the path is missing.
  String? downloadUrl({bool hasFull = true}) {
    final signed = tempUrl;
    if (signed != null) return signed;
    final p = path;
    if (!hasFull || p == null || p.isEmpty) return null;
    return '${ApiConstants.fileDataBase}$p';
  }

  /// Thumbnail URL — available even when the original is not.
  String? get thumbnailUrl {
    final p = path;
    if (p == null || p.isEmpty) return null;
    return '${ApiConstants.thumbDataBase}$p';
  }
}

@MappableClass(caseStyle: CaseStyle.snakeCase)
class FavoriteCreator with FavoriteCreatorMappable {
  final String id;
  final String name;
  final String service;
  final String updated;
  final bool everImported;
  final String? lastImported;
  final int kemonoFavorited;

  const FavoriteCreator({
    required this.id,
    required this.name,
    required this.service,
    required this.updated,
    required this.everImported,
    this.lastImported,
    required this.kemonoFavorited,
  });
}
