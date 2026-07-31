import 'package:dart_mappable/dart_mappable.dart';

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
}

@MappableClass(caseStyle: CaseStyle.snakeCase)
class FileInfo with FileInfoMappable {
  final String? name;
  final String? path;
  final bool? deferred;

  const FileInfo({
    this.name,
    this.path,
    this.deferred,
  });
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
