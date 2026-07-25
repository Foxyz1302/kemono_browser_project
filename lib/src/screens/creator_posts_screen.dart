import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cache;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/api/pawchive_client.dart';
import 'package:kemono_browser_project/src/archive/archive_cache.dart';
import 'package:kemono_browser_project/src/archive/archive_service.dart';
import 'package:kemono_browser_project/src/cache/image_cache_service.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';
import 'package:kemono_browser_project/src/cache/kemono_image_provider.dart';
import 'package:kemono_browser_project/src/widgets/context_menu.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';

import '../state/app_state.dart';
import 'home_screen.dart';
import 'fullscreen_image_viewer_screen.dart';

class CreatorPostsScreen extends SignalStatefulWidget {
  final Creator creator;
  const CreatorPostsScreen(this.creator, {super.key});

  @override
  State<CreatorPostsScreen> createState() => _CreatorPostsScreenState();
}

class _CreatorPostsScreenState extends State<CreatorPostsScreen> {
  final _app = AppState.instance;

  @override
  void initState() {
    super.initState();
    _app.loadCreatorPosts(widget.creator);
  }

  static const _imgBase = 'https://img.pawchive.pw/thumbnail/data';

  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'};

  static final _iconForExt = <String, IconData>{
    'pdf': Icons.picture_as_pdf,
    'mp4': Icons.videocam,
    'webm': Icons.videocam,
    'mp3': Icons.audiotrack,
    'wav': Icons.audiotrack,
    'ogg': Icons.audiotrack,
    'zip': Icons.folder_zip,
    'rar': Icons.folder_zip,
    '7z': Icons.folder_zip,
    'psd': Icons.brush,
    'ai': Icons.brush,
    'clip': Icons.brush,
    'sai': Icons.brush,
    'txt': Icons.description,
    'doc': Icons.description,
    'docx': Icons.description,
  };

  bool _isImage(String? name) {
    if (name == null) return false;
    final ext = name.split('.').last.toLowerCase();
    return _imageExts.contains(ext);
  }

  String? _fileExt(String? name) {
    if (name == null) return null;
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.creator;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          SignalBuilder(
            builder: (context) {
              final _ = ImageMetaStore.instance.metaReady.value;
              final bytes = ImageMetaStore.instance.bytesForCreator(c.id);
              final files = ImageMetaStore.instance.fileCountForCreator(c.id);
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: files == 0
                      ? Text('No cache', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12))
                      : Text(
                          '$files files · ${ImageMetaStore.formatBytes(bytes)}',
                          style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                        ),
                ),
              );
            },
          ),
        ],
      ),
      body: SignalBuilder(
        builder: (context) {
          if (_app.creatorPostsLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = _app.creatorPosts.value;
          if (posts.isEmpty) {
            return const Center(child: Text('No posts found'));
          }
          return GridView.builder(
            gridDelegate: const FixedHeightGridDelegate(
              maxCrossAxisExtent: 900,
              height: 200, // <-- Strict, consistent tile pixel height
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            padding: const EdgeInsets.all(12),
            itemCount: posts.length,
            itemBuilder: (context, i) {
              final p = posts[i];
              final hasImage = p.file != null && (p.file!.name?.isNotEmpty ?? false);
              final thumbUrl = hasImage ? '$_imgBase${p.file!.path}' : null;

              final allFiles = <FileInfo>[if (p.file != null) p.file!, ...p.attachments];
              final imageFiles = allFiles.where((f) => _isImage(f.name)).toList();
              final otherFiles = allFiles.where((f) => !_isImage(f.name)).toList();
              final previewFiles = [...imageFiles, ...otherFiles];
              final isPending = p.previewState == 'pending';
              final isKemonoUnavailable = !isPending && p.hasFull == false;
              final isUnavailable = isPending || isKemonoUnavailable;

              return Card(
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (thumbUrl != null)
                          Image(
                            image: KemonoImageProvider(thumbUrl, creatorId: c.id, postId: p.id),
                            fit: BoxFit.cover,
                            errorBuilder: (_, e, _) {
                              debugPrint("$e");
                              return Container(
                                color: Colors.grey.shade800,
                                child: const Icon(Icons.image_not_supported, color: Colors.white38),
                              );
                            },
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: .spaceBetween,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    spacing: 4,
                                    children: [
                                      Text(
                                        p.title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        _timeAgo(p.published),
                                        style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                                      ),
                                      if (p.content != null && p.content!.isNotEmpty) ...[
                                        Expanded(
                                          child: Text(
                                            p.content!.replaceAll(RegExp(r'<[^>]*>'), ''),
                                            softWrap: true,
                                            overflow: TextOverflow.fade,
                                            style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),

                              if (previewFiles.length > 1)
                                SizedBox(
                                  height: 72,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                    itemCount: math.min(previewFiles.length, 12),
                                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                                    itemBuilder: (context, j) {
                                      final f = previewFiles[j];
                                      if (_isImage(f.name)) {
                                        final fileIdx = allFiles.indexOf(f);
                                        return GestureDetector(
                                          onTap: isUnavailable
                                              ? null
                                              : () => FullscreenImageViewerScreen.open(
                                                  context,
                                                  files: allFiles,
                                                  index: fileIdx >= 0 ? fileIdx : j,
                                                  creatorId: c.id,
                                                  postId: p.id,
                                                ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: Image(
                                                image: KemonoImageProvider('$_imgBase${f.path}', creatorId: c.id, postId: p.id),
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => _fileIcon(f.name),
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      return _fileIcon(f.name);
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Material(
                      type: .transparency,
                      child: InkWell(
                        mouseCursor: SystemMouseCursors.click,
                        onTap: () => showDialog(context: context, builder: (_) => PostDetailDialog(c, p)),
                      ),
                    ),
                    if (isPending)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade800.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Pending',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    if (isKemonoUnavailable)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Kemono (unavailable)',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _fileIcon(String? name) {
    final ext = _fileExt(name);
    final icon = _iconForExt[ext] ?? Icons.insert_drive_file;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
          if (ext != null)
            Text(
              ext.toUpperCase(),
              style: TextStyle(fontSize: 7, color: Theme.of(context).colorScheme.outline),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

String _timeAgo(String isoDate) {
  final diff = DateTime.now().difference(DateTime.parse(isoDate));
  if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
  if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'just now';
}

class PostDetailDialog extends StatelessWidget {
  final Creator creator;
  final Post post;
  const PostDetailDialog(this.creator, this.post, {super.key});

  static const _imgBase = 'https://img.pawchive.pw/thumbnail/data';
  static const _fileBase = 'https://file.pawchive.pw/data';

  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'};

  static final _iconForExt = <String, IconData>{
    'pdf': Icons.picture_as_pdf,
    'mp4': Icons.videocam,
    'webm': Icons.videocam,
    'mp3': Icons.audiotrack,
    'wav': Icons.audiotrack,
    'ogg': Icons.audiotrack,
    'zip': Icons.folder_zip,
    'rar': Icons.folder_zip,
    '7z': Icons.folder_zip,
    'psd': Icons.brush,
    'ai': Icons.brush,
    'clip': Icons.brush,
    'sai': Icons.brush,
    'txt': Icons.description,
    'doc': Icons.description,
    'docx': Icons.description,
  };

  bool _isImage(String? name) {
    if (name == null) return false;
    final ext = name.split('.').last.toLowerCase();
    return _imageExts.contains(ext);
  }

  String? _fileExt(String? name) {
    if (name == null) return null;
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : null;
  }

  @override
  Widget build(BuildContext context) {
    final allFiles = <FileInfo>[if (post.file != null) post.file!, ...post.attachments];
    final imageFiles = allFiles.where((f) => _isImage(f.name)).toList();
    final otherFiles = allFiles.where((f) => !_isImage(f.name)).toList();
    final isPending = post.previewState == 'pending';
    final isKemonoUnavailable = !isPending && post.hasFull == false;
    final isUnavailable = isPending || isKemonoUnavailable;

    final serviceColor = serviceColors[creator.service] ?? Colors.grey;
    final bannerUrl = !isUnavailable && imageFiles.isNotEmpty ? '$_imgBase${imageFiles.first.path}' : null;

    return Dialog(
      clipBehavior: .antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        child: Column(
          // crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              fit: StackFit.loose,
              children: [
                if (bannerUrl != null)
                  SizedBox(
                    height: 180,
                    child: Image(
                      image: KemonoImageProvider(bannerUrl, creatorId: creator.id, postId: post.id),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) => ColoredBox(color: serviceColor.withValues(alpha: 0.3)),
                    ),
                  ),
                if (bannerUrl != null)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isUnavailable)
                  SizedBox(
                    height: 180,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off, color: Colors.white.withValues(alpha: 0.4), size: 32),
                          const SizedBox(height: 8),
                          Text(
                            isPending
                                ? 'This post has not been imported yet'
                                : 'This post was migrated from Kemono but its files\nare not available on this site',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 4,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                if (bannerUrl != null)
                  Positioned.fill(
                    child: Material(
                      type: .transparency,
                      child: InkWell(
                        onTap: () =>
                            FullscreenImageViewerScreen.open(context, files: allFiles, index: 0, creatorId: creator.id, postId: post.id),
                      ),
                    ),
                  ),
                Positioned(
                  left: 16,
                  bottom: 12,
                  right: 56,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: serviceColor, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          serviceLabels[creator.service] ?? creator.service,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        post.title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(_timeAgo(post.published), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(child: _buildContent(context, imageFiles, otherFiles, bannerUrl)),
            SignalBuilder(
              builder: (context) {
                final _ = ImageMetaStore.instance.metaReady.value;
                final bytes = ImageMetaStore.instance.bytesForPost(post.id);
                if (bytes == 0) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storage, size: 14, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 6),
                      Text(
                        'Cached: ${ImageMetaStore.formatBytes(bytes)}',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<FileInfo> imageFiles, List<FileInfo> otherFiles, String? bannerUrl) {
    final isPending = post.previewState == 'pending';
    final isKemonoUnavailable = !isPending && post.hasFull == false;
    final isUnavailable = isPending || isKemonoUnavailable;
    final allFiles = [...imageFiles, ...otherFiles];
    final scrollableImages = imageFiles.length > 1 ? imageFiles.skip(1).toList() : <FileInfo>[];
    final archiveExts = {'zip', 'rar', '7z'};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isUnavailable)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.outline, size: 24),
                    const SizedBox(height: 8),
                    Text(
                      isPending
                          ? 'This post has not been imported.\nFiles are not available.'
                          : 'This post was migrated from Kemono.\nFiles from the original site are missing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          if (scrollableImages.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: scrollableImages.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final f = entry.value;
                return ImageWrapTile(
                  imgBase: _imgBase,
                  f: f,
                  creator: creator,
                  post: post,
                  isUnavailable: isUnavailable,
                  allFiles: allFiles,
                  idx: idx,
                );
              }).toList(),
            ),
          if (post.content != null && post.content!.isNotEmpty) ...[
            HtmlWidget(post.content!, textStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
            const SizedBox(height: 12),
          ],
          if (allFiles.any((f) => f.name != null && archiveExts.contains(_fileExt(f.name))))
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                'Archives',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ...otherFiles.map((f) {
            final ext = _fileExt(f.name);
            final isArchive = ext != null && archiveExts.contains(ext);
            if (isArchive) {
              final fileUrl = '$_fileBase${f.path}?f=${f.name ?? ext.toUpperCase()}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ArchiveTile(
                  key: ValueKey(fileUrl),
                  fileUrl: fileUrl,
                  fileName: f.name ?? 'archive',
                  archiveService: ArchiveService(PawchiveClient.instance.dio),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(_iconForExt[ext] ?? Icons.insert_drive_file, size: 16, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.name ?? ext?.toUpperCase() ?? 'File',
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (post.tags != null && post.tags!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Tags',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: post.tags!
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .map(
                    (t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 11)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (post.embed != null && post.embed!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${post.embed}', style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
          if (bannerUrl == null && imageFiles.isEmpty && otherFiles.isEmpty && (post.content == null || post.content!.isEmpty))
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No content', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ),
            ),
        ],
      ),
    );
  }
}

class ImageWrapTile extends StatelessWidget {
  const new({
    super.key,
    required this._imgBase,
    required this.f,
    required this.creator,
    required this.post,
    required this.isUnavailable,
    required this.allFiles,
    required this.idx,
  });

  final String _imgBase;
  final FileInfo f;
  final Creator creator;
  final Post post;
  final bool isUnavailable;
  final List<FileInfo> allFiles;
  final int idx;

  @override
  Widget build(BuildContext context) {
    final fullUrl = 'https://file.pawchive.pw/data${f.path}?f=${f.name ?? p.basename(f.path)}';

    return FContextMenu(
      entries: [
        ContextMenuAction(
          label: 'Copy image',
          icon: Icons.image,
          onTap: () async {
            try {
              final info = await ImageCacheService.instance
                  .getCachedFileStream(fullUrl)
                  .where((r) => r is cache.FileInfo)
                  .cast<cache.FileInfo>()
                  .first;
              final bytes = await info.file.readAsBytes();
              await Pasteboard.writeImage(bytes);
            } catch (e, st) {
              debugPrint('Copy image failed: $e\n$st');
            }
          },
        ),
        ContextMenuAction(
          label: 'Copy file',
          icon: Icons.insert_drive_file,
          onTap: () async {
            try {
              final info = await ImageCacheService.instance
                  .getCachedFileStream(fullUrl)
                  .where((r) => r is cache.FileInfo)
                  .cast<cache.FileInfo>()
                  .first;
              await Pasteboard.writeFiles([info.file.path]);
            } catch (e, st) {
              debugPrint('Copy file failed: $e\n$st');
            }
          },
        ),
        ContextMenuAction(
          label: 'Copy image URL',
          icon: Icons.link,
          onTap: () => Clipboard.setData(ClipboardData(text: fullUrl)),
        ),
      ],
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        constraints: const BoxConstraints(maxHeight: 250),
        child: Stack(
          children: [
            Image(
              image: KemonoImageProvider('$_imgBase${f.path}', creatorId: creator.id, postId: post.id),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 120,
                height: 120,
                color: Colors.grey.shade800,
                child: const Icon(Icons.image_not_supported, color: Colors.white38),
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: isUnavailable
                      ? null
                      : () => FullscreenImageViewerScreen.open(
                          context,
                          files: allFiles,
                          index: idx,
                          creatorId: creator.id,
                          postId: post.id,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ArchiveState { idle, downloading, ready, error }

class _ArchiveTile extends StatefulWidget {
  final String fileUrl;
  final String fileName;
  final ArchiveService archiveService;

  const _ArchiveTile({
    super.key,
    required this.fileUrl,
    required this.fileName,
    required this.archiveService,
  });

  @override
  State<_ArchiveTile> createState() => _ArchiveTileState();
}

class _ArchiveTileState extends State<_ArchiveTile> {
  _ArchiveState _state = _ArchiveState.idle;
  double _downloadProgress = 0;
  String _localPath = '';
  List<String> _entries = [];
  String? _error;

  @override
  void dispose() {
    super.dispose();
  }

  void _start() async {
    setState(() => _state = _ArchiveState.downloading);
    try {
      _localPath = await ArchiveCache.instance.getOrDownload(
        widget.fileUrl,
        widget.archiveService,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => _downloadProgress = total > 0 ? received / total : 0);
        },
      );
      final entries = await widget.archiveService.listEntries(_localPath);
      if (!mounted) return;
      setState(() {
        _entries = entries.map((e) => e.path).toList();
        _state = _ArchiveState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _state = _ArchiveState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: switch (_state) {
        _ArchiveState.idle => _buildIdle(context),
        _ArchiveState.downloading => _buildProgress(context),
        _ArchiveState.ready => _buildReady(context),
        _ArchiveState.error => _buildError(context),
      },
    );
  }

  Widget _buildIdle(BuildContext context) {
    return InkWell(
      onTap: _start,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.folder_zip, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('Tap to download and extract', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.download, size: 20, color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _downloadProgress > 0 ? '${(_downloadProgress * 100).toStringAsFixed(0)}%' : '',
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
        ],
      ),
    );
  }

  Widget _buildReady(BuildContext context) {
    final imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif'};
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.folder_zip, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${_entries.length} files', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          if (_entries.isEmpty)
            Text('Empty archive', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12))
          else
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1,
              children: _entries.take(8).map((path) {
                final ext = p.extension(path).toLowerCase();
                final isImage = imageExts.contains(ext);
                return GestureDetector(
                  onTap: isImage
                      ? () {
                          final imageEntries = _entries
                              .where((e) => imageExts.contains(p.extension(e).toLowerCase()))
                              .toList();
                          final index = imageEntries.indexOf(path);
                          FullscreenImageViewerScreen.openArchive(
                            context,
                            archiveService: widget.archiveService,
                            localPath: _localPath,
                            entries: imageEntries,
                            initialIndex: index >= 0 ? index : 0,
                            archiveName: widget.fileName,
                          );
                        }
                      : null,
                  child: isImage
                      ? FutureBuilder<Uint8List>(
                          future: widget.archiveService.readEntry(_localPath, path),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            if (snapshot.hasError || !snapshot.hasData) {
                              return Container(
                                decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(6)),
                                child: const Icon(Icons.broken_image, size: 20, color: Colors.white38),
                              );
                            }
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                            );
                          },
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(_extLabel(ext), style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline)),
                          ),
                        ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_error ?? 'Unknown error', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11)),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: OutlinedButton(
              onPressed: () {
                setState(() => _state = _ArchiveState.idle);
              },
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact),
              child: const Text('Retry', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  String _extLabel(String ext) {
    return switch (ext) {
      '.txt' || '.md' => 'TXT',
      '.pdf' => 'PDF',
      '.mp4' || '.webm' => 'VID',
      '.mp3' || '.wav' || '.ogg' => 'AUD',
      _ => ext.replaceAll('.', '').toUpperCase(),
    };
  }
}
