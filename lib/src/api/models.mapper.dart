// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'models.dart';

class CreatorMapper extends ClassMapperBase<Creator> {
  CreatorMapper._();

  static CreatorMapper? _instance;
  static CreatorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = CreatorMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Creator';

  static String _$id(Creator v) => v.id;
  static const Field<Creator, String> _f$id = Field('id', _$id);
  static String _$name(Creator v) => v.name;
  static const Field<Creator, String> _f$name = Field('name', _$name);
  static String _$service(Creator v) => v.service;
  static const Field<Creator, String> _f$service = Field('service', _$service);
  static int _$indexed(Creator v) => v.indexed;
  static const Field<Creator, int> _f$indexed = Field('indexed', _$indexed);
  static int _$updated(Creator v) => v.updated;
  static const Field<Creator, int> _f$updated = Field('updated', _$updated);
  static int _$favorited(Creator v) => v.favorited;
  static const Field<Creator, int> _f$favorited = Field(
    'favorited',
    _$favorited,
  );
  static bool _$everImported(Creator v) => v.everImported;
  static const Field<Creator, bool> _f$everImported = Field(
    'everImported',
    _$everImported,
    key: r'ever_imported',
  );

  @override
  final MappableFields<Creator> fields = const {
    #id: _f$id,
    #name: _f$name,
    #service: _f$service,
    #indexed: _f$indexed,
    #updated: _f$updated,
    #favorited: _f$favorited,
    #everImported: _f$everImported,
  };

  static Creator _instantiate(DecodingData data) {
    return Creator(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      service: data.dec(_f$service),
      indexed: data.dec(_f$indexed),
      updated: data.dec(_f$updated),
      favorited: data.dec(_f$favorited),
      everImported: data.dec(_f$everImported),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Creator fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Creator>(map);
  }

  static Creator fromJson(String json) {
    return ensureInitialized().decodeJson<Creator>(json);
  }
}

mixin CreatorMappable {
  String toJson() {
    return CreatorMapper.ensureInitialized().encodeJson<Creator>(
      this as Creator,
    );
  }

  Map<String, dynamic> toMap() {
    return CreatorMapper.ensureInitialized().encodeMap<Creator>(
      this as Creator,
    );
  }

  CreatorCopyWith<Creator, Creator, Creator> get copyWith =>
      _CreatorCopyWithImpl<Creator, Creator>(
        this as Creator,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return CreatorMapper.ensureInitialized().stringifyValue(this as Creator);
  }

  @override
  bool operator ==(Object other) {
    return CreatorMapper.ensureInitialized().equalsValue(
      this as Creator,
      other,
    );
  }

  @override
  int get hashCode {
    return CreatorMapper.ensureInitialized().hashValue(this as Creator);
  }
}

extension CreatorValueCopy<$R, $Out> on ObjectCopyWith<$R, Creator, $Out> {
  CreatorCopyWith<$R, Creator, $Out> get $asCreator =>
      $base.as((v, t, t2) => _CreatorCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class CreatorCopyWith<$R, $In extends Creator, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? name,
    String? service,
    int? indexed,
    int? updated,
    int? favorited,
    bool? everImported,
  });
  CreatorCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _CreatorCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Creator, $Out>
    implements CreatorCopyWith<$R, Creator, $Out> {
  _CreatorCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Creator> $mapper =
      CreatorMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? name,
    String? service,
    int? indexed,
    int? updated,
    int? favorited,
    bool? everImported,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (name != null) #name: name,
      if (service != null) #service: service,
      if (indexed != null) #indexed: indexed,
      if (updated != null) #updated: updated,
      if (favorited != null) #favorited: favorited,
      if (everImported != null) #everImported: everImported,
    }),
  );
  @override
  Creator $make(CopyWithData data) => Creator(
    id: data.get(#id, or: $value.id),
    name: data.get(#name, or: $value.name),
    service: data.get(#service, or: $value.service),
    indexed: data.get(#indexed, or: $value.indexed),
    updated: data.get(#updated, or: $value.updated),
    favorited: data.get(#favorited, or: $value.favorited),
    everImported: data.get(#everImported, or: $value.everImported),
  );

  @override
  CreatorCopyWith<$R2, Creator, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _CreatorCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PostMapper extends ClassMapperBase<Post> {
  PostMapper._();

  static PostMapper? _instance;
  static PostMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PostMapper._());
      FileInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Post';

  static String _$id(Post v) => v.id;
  static const Field<Post, String> _f$id = Field('id', _$id);
  static String _$user(Post v) => v.user;
  static const Field<Post, String> _f$user = Field('user', _$user);
  static String _$service(Post v) => v.service;
  static const Field<Post, String> _f$service = Field('service', _$service);
  static String _$title(Post v) => v.title;
  static const Field<Post, String> _f$title = Field('title', _$title);
  static String? _$content(Post v) => v.content;
  static const Field<Post, String> _f$content = Field(
    'content',
    _$content,
    opt: true,
  );
  static String? _$substring(Post v) => v.substring;
  static const Field<Post, String> _f$substring = Field(
    'substring',
    _$substring,
    opt: true,
  );
  static String _$published(Post v) => v.published;
  static const Field<Post, String> _f$published = Field(
    'published',
    _$published,
  );
  static FileInfo? _$file(Post v) => v.file;
  static const Field<Post, FileInfo> _f$file = Field(
    'file',
    _$file,
    opt: true,
    hook: EmptyObjectAsNullHook(),
  );
  static List<FileInfo> _$attachments(Post v) => v.attachments;
  static const Field<Post, List<FileInfo>> _f$attachments = Field(
    'attachments',
    _$attachments,
    opt: true,
    def: const [],
  );
  static String? _$previewState(Post v) => v.previewState;
  static const Field<Post, String> _f$previewState = Field(
    'previewState',
    _$previewState,
    key: r'preview_state',
    opt: true,
  );
  static bool _$hasFull(Post v) => v.hasFull;
  static const Field<Post, bool> _f$hasFull = Field(
    'hasFull',
    _$hasFull,
    key: r'has_full',
    opt: true,
    def: false,
  );
  static String? _$origin(Post v) => v.origin;
  static const Field<Post, String> _f$origin = Field(
    'origin',
    _$origin,
    opt: true,
  );
  static Map<dynamic, dynamic>? _$embed(Post v) => v.embed;
  static const Field<Post, Map<dynamic, dynamic>> _f$embed = Field(
    'embed',
    _$embed,
    opt: true,
  );
  static String? _$tags(Post v) => v.tags;
  static const Field<Post, String> _f$tags = Field('tags', _$tags, opt: true);
  static String? _$added(Post v) => v.added;
  static const Field<Post, String> _f$added = Field(
    'added',
    _$added,
    opt: true,
  );
  static String? _$edited(Post v) => v.edited;
  static const Field<Post, String> _f$edited = Field(
    'edited',
    _$edited,
    opt: true,
  );

  @override
  final MappableFields<Post> fields = const {
    #id: _f$id,
    #user: _f$user,
    #service: _f$service,
    #title: _f$title,
    #content: _f$content,
    #substring: _f$substring,
    #published: _f$published,
    #file: _f$file,
    #attachments: _f$attachments,
    #previewState: _f$previewState,
    #hasFull: _f$hasFull,
    #origin: _f$origin,
    #embed: _f$embed,
    #tags: _f$tags,
    #added: _f$added,
    #edited: _f$edited,
  };

  static Post _instantiate(DecodingData data) {
    return Post(
      id: data.dec(_f$id),
      user: data.dec(_f$user),
      service: data.dec(_f$service),
      title: data.dec(_f$title),
      content: data.dec(_f$content),
      substring: data.dec(_f$substring),
      published: data.dec(_f$published),
      file: data.dec(_f$file),
      attachments: data.dec(_f$attachments),
      previewState: data.dec(_f$previewState),
      hasFull: data.dec(_f$hasFull),
      origin: data.dec(_f$origin),
      embed: data.dec(_f$embed),
      tags: data.dec(_f$tags),
      added: data.dec(_f$added),
      edited: data.dec(_f$edited),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Post fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Post>(map);
  }

  static Post fromJson(String json) {
    return ensureInitialized().decodeJson<Post>(json);
  }
}

mixin PostMappable {
  String toJson() {
    return PostMapper.ensureInitialized().encodeJson<Post>(this as Post);
  }

  Map<String, dynamic> toMap() {
    return PostMapper.ensureInitialized().encodeMap<Post>(this as Post);
  }

  PostCopyWith<Post, Post, Post> get copyWith =>
      _PostCopyWithImpl<Post, Post>(this as Post, $identity, $identity);
  @override
  String toString() {
    return PostMapper.ensureInitialized().stringifyValue(this as Post);
  }

  @override
  bool operator ==(Object other) {
    return PostMapper.ensureInitialized().equalsValue(this as Post, other);
  }

  @override
  int get hashCode {
    return PostMapper.ensureInitialized().hashValue(this as Post);
  }
}

extension PostValueCopy<$R, $Out> on ObjectCopyWith<$R, Post, $Out> {
  PostCopyWith<$R, Post, $Out> get $asPost =>
      $base.as((v, t, t2) => _PostCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PostCopyWith<$R, $In extends Post, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  FileInfoCopyWith<$R, FileInfo, FileInfo>? get file;
  ListCopyWith<$R, FileInfo, FileInfoCopyWith<$R, FileInfo, FileInfo>>
  get attachments;
  MapCopyWith<$R, dynamic, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>?
  get embed;
  $R call({
    String? id,
    String? user,
    String? service,
    String? title,
    String? content,
    String? substring,
    String? published,
    FileInfo? file,
    List<FileInfo>? attachments,
    String? previewState,
    bool? hasFull,
    String? origin,
    Map<dynamic, dynamic>? embed,
    String? tags,
    String? added,
    String? edited,
  });
  PostCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PostCopyWithImpl<$R, $Out> extends ClassCopyWithBase<$R, Post, $Out>
    implements PostCopyWith<$R, Post, $Out> {
  _PostCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Post> $mapper = PostMapper.ensureInitialized();
  @override
  FileInfoCopyWith<$R, FileInfo, FileInfo>? get file =>
      $value.file?.copyWith.$chain((v) => call(file: v));
  @override
  ListCopyWith<$R, FileInfo, FileInfoCopyWith<$R, FileInfo, FileInfo>>
  get attachments => ListCopyWith(
    $value.attachments,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(attachments: v),
  );
  @override
  MapCopyWith<$R, dynamic, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>?
  get embed => $value.embed != null
      ? MapCopyWith(
          $value.embed!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(embed: v),
        )
      : null;
  @override
  $R call({
    String? id,
    String? user,
    String? service,
    String? title,
    Object? content = $none,
    Object? substring = $none,
    String? published,
    Object? file = $none,
    List<FileInfo>? attachments,
    Object? previewState = $none,
    bool? hasFull,
    Object? origin = $none,
    Object? embed = $none,
    Object? tags = $none,
    Object? added = $none,
    Object? edited = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (user != null) #user: user,
      if (service != null) #service: service,
      if (title != null) #title: title,
      if (content != $none) #content: content,
      if (substring != $none) #substring: substring,
      if (published != null) #published: published,
      if (file != $none) #file: file,
      if (attachments != null) #attachments: attachments,
      if (previewState != $none) #previewState: previewState,
      if (hasFull != null) #hasFull: hasFull,
      if (origin != $none) #origin: origin,
      if (embed != $none) #embed: embed,
      if (tags != $none) #tags: tags,
      if (added != $none) #added: added,
      if (edited != $none) #edited: edited,
    }),
  );
  @override
  Post $make(CopyWithData data) => Post(
    id: data.get(#id, or: $value.id),
    user: data.get(#user, or: $value.user),
    service: data.get(#service, or: $value.service),
    title: data.get(#title, or: $value.title),
    content: data.get(#content, or: $value.content),
    substring: data.get(#substring, or: $value.substring),
    published: data.get(#published, or: $value.published),
    file: data.get(#file, or: $value.file),
    attachments: data.get(#attachments, or: $value.attachments),
    previewState: data.get(#previewState, or: $value.previewState),
    hasFull: data.get(#hasFull, or: $value.hasFull),
    origin: data.get(#origin, or: $value.origin),
    embed: data.get(#embed, or: $value.embed),
    tags: data.get(#tags, or: $value.tags),
    added: data.get(#added, or: $value.added),
    edited: data.get(#edited, or: $value.edited),
  );

  @override
  PostCopyWith<$R2, Post, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _PostCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class FileInfoMapper extends ClassMapperBase<FileInfo> {
  FileInfoMapper._();

  static FileInfoMapper? _instance;
  static FileInfoMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FileInfoMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FileInfo';

  static String? _$name(FileInfo v) => v.name;
  static const Field<FileInfo, String> _f$name = Field(
    'name',
    _$name,
    opt: true,
  );
  static String _$path(FileInfo v) => v.path;
  static const Field<FileInfo, String> _f$path = Field('path', _$path);
  static bool? _$deferred(FileInfo v) => v.deferred;
  static const Field<FileInfo, bool> _f$deferred = Field(
    'deferred',
    _$deferred,
    opt: true,
  );

  @override
  final MappableFields<FileInfo> fields = const {
    #name: _f$name,
    #path: _f$path,
    #deferred: _f$deferred,
  };

  static FileInfo _instantiate(DecodingData data) {
    return FileInfo(
      name: data.dec(_f$name),
      path: data.dec(_f$path),
      deferred: data.dec(_f$deferred),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FileInfo fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FileInfo>(map);
  }

  static FileInfo fromJson(String json) {
    return ensureInitialized().decodeJson<FileInfo>(json);
  }
}

mixin FileInfoMappable {
  String toJson() {
    return FileInfoMapper.ensureInitialized().encodeJson<FileInfo>(
      this as FileInfo,
    );
  }

  Map<String, dynamic> toMap() {
    return FileInfoMapper.ensureInitialized().encodeMap<FileInfo>(
      this as FileInfo,
    );
  }

  FileInfoCopyWith<FileInfo, FileInfo, FileInfo> get copyWith =>
      _FileInfoCopyWithImpl<FileInfo, FileInfo>(
        this as FileInfo,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FileInfoMapper.ensureInitialized().stringifyValue(this as FileInfo);
  }

  @override
  bool operator ==(Object other) {
    return FileInfoMapper.ensureInitialized().equalsValue(
      this as FileInfo,
      other,
    );
  }

  @override
  int get hashCode {
    return FileInfoMapper.ensureInitialized().hashValue(this as FileInfo);
  }
}

extension FileInfoValueCopy<$R, $Out> on ObjectCopyWith<$R, FileInfo, $Out> {
  FileInfoCopyWith<$R, FileInfo, $Out> get $asFileInfo =>
      $base.as((v, t, t2) => _FileInfoCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FileInfoCopyWith<$R, $In extends FileInfo, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? name, String? path, bool? deferred});
  FileInfoCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FileInfoCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FileInfo, $Out>
    implements FileInfoCopyWith<$R, FileInfo, $Out> {
  _FileInfoCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FileInfo> $mapper =
      FileInfoMapper.ensureInitialized();
  @override
  $R call({Object? name = $none, String? path, Object? deferred = $none}) =>
      $apply(
        FieldCopyWithData({
          if (name != $none) #name: name,
          if (path != null) #path: path,
          if (deferred != $none) #deferred: deferred,
        }),
      );
  @override
  FileInfo $make(CopyWithData data) => FileInfo(
    name: data.get(#name, or: $value.name),
    path: data.get(#path, or: $value.path),
    deferred: data.get(#deferred, or: $value.deferred),
  );

  @override
  FileInfoCopyWith<$R2, FileInfo, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FileInfoCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class FavoriteCreatorMapper extends ClassMapperBase<FavoriteCreator> {
  FavoriteCreatorMapper._();

  static FavoriteCreatorMapper? _instance;
  static FavoriteCreatorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FavoriteCreatorMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FavoriteCreator';

  static String _$id(FavoriteCreator v) => v.id;
  static const Field<FavoriteCreator, String> _f$id = Field('id', _$id);
  static String _$name(FavoriteCreator v) => v.name;
  static const Field<FavoriteCreator, String> _f$name = Field('name', _$name);
  static String _$service(FavoriteCreator v) => v.service;
  static const Field<FavoriteCreator, String> _f$service = Field(
    'service',
    _$service,
  );
  static String _$updated(FavoriteCreator v) => v.updated;
  static const Field<FavoriteCreator, String> _f$updated = Field(
    'updated',
    _$updated,
  );
  static bool _$everImported(FavoriteCreator v) => v.everImported;
  static const Field<FavoriteCreator, bool> _f$everImported = Field(
    'everImported',
    _$everImported,
    key: r'ever_imported',
  );
  static String? _$lastImported(FavoriteCreator v) => v.lastImported;
  static const Field<FavoriteCreator, String> _f$lastImported = Field(
    'lastImported',
    _$lastImported,
    key: r'last_imported',
    opt: true,
  );
  static int _$kemonoFavorited(FavoriteCreator v) => v.kemonoFavorited;
  static const Field<FavoriteCreator, int> _f$kemonoFavorited = Field(
    'kemonoFavorited',
    _$kemonoFavorited,
    key: r'kemono_favorited',
  );

  @override
  final MappableFields<FavoriteCreator> fields = const {
    #id: _f$id,
    #name: _f$name,
    #service: _f$service,
    #updated: _f$updated,
    #everImported: _f$everImported,
    #lastImported: _f$lastImported,
    #kemonoFavorited: _f$kemonoFavorited,
  };

  static FavoriteCreator _instantiate(DecodingData data) {
    return FavoriteCreator(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      service: data.dec(_f$service),
      updated: data.dec(_f$updated),
      everImported: data.dec(_f$everImported),
      lastImported: data.dec(_f$lastImported),
      kemonoFavorited: data.dec(_f$kemonoFavorited),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FavoriteCreator fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FavoriteCreator>(map);
  }

  static FavoriteCreator fromJson(String json) {
    return ensureInitialized().decodeJson<FavoriteCreator>(json);
  }
}

mixin FavoriteCreatorMappable {
  String toJson() {
    return FavoriteCreatorMapper.ensureInitialized()
        .encodeJson<FavoriteCreator>(this as FavoriteCreator);
  }

  Map<String, dynamic> toMap() {
    return FavoriteCreatorMapper.ensureInitialized().encodeMap<FavoriteCreator>(
      this as FavoriteCreator,
    );
  }

  FavoriteCreatorCopyWith<FavoriteCreator, FavoriteCreator, FavoriteCreator>
  get copyWith =>
      _FavoriteCreatorCopyWithImpl<FavoriteCreator, FavoriteCreator>(
        this as FavoriteCreator,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FavoriteCreatorMapper.ensureInitialized().stringifyValue(
      this as FavoriteCreator,
    );
  }

  @override
  bool operator ==(Object other) {
    return FavoriteCreatorMapper.ensureInitialized().equalsValue(
      this as FavoriteCreator,
      other,
    );
  }

  @override
  int get hashCode {
    return FavoriteCreatorMapper.ensureInitialized().hashValue(
      this as FavoriteCreator,
    );
  }
}

extension FavoriteCreatorValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FavoriteCreator, $Out> {
  FavoriteCreatorCopyWith<$R, FavoriteCreator, $Out> get $asFavoriteCreator =>
      $base.as((v, t, t2) => _FavoriteCreatorCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FavoriteCreatorCopyWith<$R, $In extends FavoriteCreator, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? name,
    String? service,
    String? updated,
    bool? everImported,
    String? lastImported,
    int? kemonoFavorited,
  });
  FavoriteCreatorCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _FavoriteCreatorCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FavoriteCreator, $Out>
    implements FavoriteCreatorCopyWith<$R, FavoriteCreator, $Out> {
  _FavoriteCreatorCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FavoriteCreator> $mapper =
      FavoriteCreatorMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? name,
    String? service,
    String? updated,
    bool? everImported,
    Object? lastImported = $none,
    int? kemonoFavorited,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (name != null) #name: name,
      if (service != null) #service: service,
      if (updated != null) #updated: updated,
      if (everImported != null) #everImported: everImported,
      if (lastImported != $none) #lastImported: lastImported,
      if (kemonoFavorited != null) #kemonoFavorited: kemonoFavorited,
    }),
  );
  @override
  FavoriteCreator $make(CopyWithData data) => FavoriteCreator(
    id: data.get(#id, or: $value.id),
    name: data.get(#name, or: $value.name),
    service: data.get(#service, or: $value.service),
    updated: data.get(#updated, or: $value.updated),
    everImported: data.get(#everImported, or: $value.everImported),
    lastImported: data.get(#lastImported, or: $value.lastImported),
    kemonoFavorited: data.get(#kemonoFavorited, or: $value.kemonoFavorited),
  );

  @override
  FavoriteCreatorCopyWith<$R2, FavoriteCreator, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FavoriteCreatorCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

