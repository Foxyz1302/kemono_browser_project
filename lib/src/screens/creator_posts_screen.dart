import 'dart:math' as math;
import 'dart:ui';

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
import 'package:url_launcher/url_launcher.dart';
import 'package:signals/signals_flutter.dart';

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
          debugPrint("Creator: ${c.name} (id:${c.id})\nservice: ${c.service}");
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
              final imageFiles = p.attachments.where((f) => _isImage(f.name)).toList();
              final otherFiles = p.attachments.where((f) => !_isImage(f.name)).toList();
              final hasSeparateThumb = p.file != null && _isImage(p.file!.name) && !p.attachments.any((f) => f.path == p.file!.path);
              final previewFiles = hasSeparateThumb ? [...imageFiles, ...otherFiles] : [...imageFiles.skip(1), ...otherFiles];

              // debugPrint(
              //   "post.file: ${p.file?.path ?? 'none'}"
              //   "\nattachments (${p.attachments.length}): [${p.attachments.map((e) => e.path).join(', ')}]"
              //   "\nthumb: ${hasSeparateThumb ? 'post.file' : 'attachments[0]'}, previewFiles: ${previewFiles.length}",
              // );
              final thumbUrl = p.file != null && _isImage(p.file!.name)
                  ? '$_imgBase${p.file!.path}'
                  : imageFiles.isNotEmpty
                  ? '$_imgBase${imageFiles.first.path}'
                  : null;
              final isPending = p.previewState == 'pending';
              final isKemonoUnavailable = !isPending && p.hasFull == false;
              final isUnavailable = isPending || isKemonoUnavailable;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final halfTile = constraints.maxWidth * 0.5;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (thumbUrl != null)
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: halfTile),
                                child: SizedBox(
                                  height: double.infinity,
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.only(topRight: Radius.circular(15), bottomRight: Radius.circular(15)),
                                    clipBehavior: Clip.antiAlias,
                                    child: SignalBuilder(
                                      builder: (context) {
                                        final showAnim = AppState.instance.showImageLoadAnimation.value;
                                        return Image(
                                          image: KemonoImageProvider(thumbUrl, creatorId: c.id, postId: p.id),
                                          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                            if (frame == null) {
                                              return ShaderMask(
                                                shaderCallback: (bounds) => const LinearGradient(
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                  colors: [Colors.white, Colors.transparent],
                                                  stops: [-0.3, 0.0],
                                                ).createShader(bounds),
                                                blendMode: BlendMode.dstIn,
                                                child: child,
                                              );
                                            }
                                            if (showAnim) {
                                              return RevealShaderImage(key: ValueKey(thumbUrl), window: 0.3, finalStop2: 1.3, child: child);
                                            }
                                            return child;
                                          },
                                          fit: BoxFit.cover,
                                          alignment: Alignment.center,
                                          errorBuilder: (_, e, _) => Container(
                                            color: Colors.grey.shade800,
                                            child: const Icon(Icons.image_not_supported, color: Colors.white38),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
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

                                  if (previewFiles.isNotEmpty)
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
                                            final fileIdx = p.attachments.indexOf(f);
                                            return GestureDetector(
                                              onTap: isUnavailable
                                                  ? null
                                                  : () => FullscreenImageViewerScreen.open(
                                                      context,
                                                      files: p.attachments,
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

class ExpandOnLoadImage extends StatefulWidget {
  final Widget child;
  const ExpandOnLoadImage({super.key, required this.child});

  @override
  State<ExpandOnLoadImage> createState() => _ExpandOnLoadImageState();
}

class _ExpandOnLoadImageState extends State<ExpandOnLoadImage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.fastEaseInToSlowEaseOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scaleX: _scaleAnimation.value, // 0 → 1 reveals the image
          alignment: Alignment.centerLeft, // reveal from left to right
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class RevealShaderImage extends StatefulWidget {
  final Widget child;
  final double window;
  final double finalStop2;

  const RevealShaderImage({
    super.key, // now accepts an external key
    required this.child,
    this.window = 0.3,
    this.finalStop2 = 1.0,
  });

  @override
  State<RevealShaderImage> createState() => _RevealShaderImageState();
}

class _RevealShaderImageState extends State<RevealShaderImage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.fastEaseInToSlowEaseOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    final finalStop2 = widget.finalStop2;
    final finalStop1 = finalStop2 - window;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value;
        final startStop1 = -window;
        final startStop2 = 0.0;
        final stop1 = lerpDouble(startStop1, finalStop1, t)!;
        final stop2 = lerpDouble(startStop2, finalStop2, t)!;
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.white, Colors.transparent],
            stops: [stop1, stop2],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: child!,
        );
      },
      child: widget.child,
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
    final imageFiles = post.attachments.where((f) => _isImage(f.name)).toList();
    final otherFiles = post.attachments.where((f) => !_isImage(f.name)).toList();
    final isPending = post.previewState == 'pending';
    final isKemonoUnavailable = !isPending && post.hasFull == false;
    final isUnavailable = isPending || isKemonoUnavailable;
    final serviceColor = serviceColors[creator.service] ?? Colors.grey;
    final bannerUrl = !isUnavailable && post.file != null && _isImage(post.file!.name)
        ? '$_imgBase${post.file!.path}'
        : !isUnavailable && imageFiles.isNotEmpty
        ? '$_imgBase${imageFiles.first.path}'
        : null;

    // debugPrint(
    //   "Post opened (id:${post.id})"
    //   "\npost.file: ${post.file?.path ?? 'none'}"
    //   "\nattachments (${post.attachments.length}): [${post.attachments.map((e) => e.path).join(', ')}]"
    //   "\nbannerUrl: ${bannerUrl ?? 'none'}, content images: ${imageFiles.length}",
    // );
    return _optionalDialog(
      child: Column(
        // crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            fit: StackFit.loose,
            clipBehavior: .antiAlias,
            children: [
              if (bannerUrl != null)
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.transparent],
                    stops: const [0, 1.0],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: SizedBox(
                    height: 180,
                    child: Stack(
                      children: [
                        Image(
                          image: KemonoImageProvider(bannerUrl, creatorId: creator.id, postId: post.id),
                          fit: BoxFit.cover,
                          width: .infinity,
                          errorBuilder: (_, e, _) {
                            debugPrint("$e");
                            return Container(
                              color: Colors.grey.shade800,
                              child: const Icon(Icons.image_not_supported, color: Colors.white38),
                            );
                          },
                        ),

                        Positioned.fill(
                          child: Material(
                            type: .transparency,
                            child: InkWell(
                              onTap: () {
                                final bannerFiles = post.file != null && _isImage(post.file!.name)
                                    ? [post.file!, ...post.attachments.where((f) => f.path != post.file?.path)]
                                    : post.attachments;
                                FullscreenImageViewerScreen.open(
                                  context,
                                  files: bannerFiles,
                                  index: 0,
                                  creatorId: creator.id,
                                  postId: post.id,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              //   SizedBox(
              //     height: 180,
              //     child: Image(
              //       image: KemonoImageProvider(bannerUrl, creatorId: creator.id, postId: post.id),
              //       fit: BoxFit.cover,
              //       width: double.infinity,
              //       errorBuilder: (_, _, _) => ColoredBox(color: serviceColor.withValues(alpha: 0.3)),
              //     ),
              //   ),
              // if (bannerUrl != null)
              //   const Positioned.fill(
              //     right: 0,
              //     left: 0,
              //     child: IgnorePointer(
              //       child: DecoratedBox(
              //         decoration: BoxDecoration(
              //           gradient: LinearGradient(
              //             begin: Alignment.topCenter,
              //             end: Alignment.bottomCenter,
              //             colors: [Colors.transparent, Colors.black87],
              //           ),
              //         ),
              //       ),
              //     ),
              //   ),
              if (isUnavailable)
                SizedBox(
                  height: 180,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        Icon(Icons.cloud_off, color: Colors.white.withValues(alpha: 0.4), size: 32),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      onSelected: (value) {
                        final url = 'https://pawchive.pw/${post.service}/user/${post.user}/post/${post.id}';
                        switch (value) {
                          case 'browser':
                            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                          case 'copy':
                            Clipboard.setData(ClipboardData(text: url));
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'browser',
                          child: ListTile(
                            leading: Icon(Icons.open_in_browser),
                            title: Text('Open in browser'),
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'copy',
                          child: ListTile(
                            leading: Icon(Icons.copy),
                            title: Text('Copy link'),
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
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
                  spacing: 6,
                  children: [
                    Icon(Icons.storage, size: 14, color: Theme.of(context).colorScheme.outline),
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
    );
  }

  Widget _optionalDialog({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Scaffold(body: child);
        }
        return Dialog(
          clipBehavior: .antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.7),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, List<FileInfo> imageFiles, List<FileInfo> otherFiles, String? bannerUrl) {
    final isPending = post.previewState == 'pending';
    final isKemonoUnavailable = !isPending && post.hasFull == false;
    final isUnavailable = isPending || isKemonoUnavailable;
    final allFiles = [...imageFiles, ...otherFiles];
    final scrollableImages = imageFiles;
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
                  spacing: 8,
                  children: [
                    Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.outline, size: 24),
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
            SignalBuilder(
              builder: (context) {
                // Rebuild when ImageMetaStore gets new entries (aspect ratios resolve)
                final _ = ImageMetaStore.instance.metaReady.value;
                return JustifiedImageGrid(
                  targetRowHeight: 250,
                  items: scrollableImages.map((f) {
                    final url = '$_imgBase${f.path}';
                    final aspectRatio = ImageMetaStore.instance.lookup(url)?.aspectRatio ?? 1.0;
                    final idx = scrollableImages.indexOf(f);
                    return (
                      child: ImageWrapTile(
                        imgBase: _imgBase,
                        f: f,
                        creator: creator,
                        post: post,
                        isUnavailable: isUnavailable,
                        allFiles: allFiles,
                        idx: idx,
                      ),
                      aspectRatio: aspectRatio,
                    );
                  }).toList(),
                );
              },
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
                  spacing: 8,
                  children: [
                    Icon(_iconForExt[ext] ?? Icons.insert_drive_file, size: 16, color: Theme.of(context).colorScheme.outline),
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
                spacing: 8,
                children: [
                  Icon(Icons.link, size: 16, color: Theme.of(context).colorScheme.outline),
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

class JustifiedImageGrid extends StatelessWidget {
  final List<({Widget child, double aspectRatio})> items;
  final double targetRowHeight;
  final double spacing;
  final int maxItemsPerRow;

  const JustifiedImageGrid({
    super.key,
    required this.items,
    this.targetRowHeight = 180.0,
    this.spacing = 8.0,
    this.maxItemsPerRow = 10,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final n = items.length;
        if (n == 0) return const SizedBox.shrink();

        // Prefix sums of aspect ratios for O(1) row-height lookup
        final prefix = List<double>.filled(n + 1, 0);
        for (var i = 0; i < n; i++) {
          prefix[i + 1] = prefix[i] + items[i].aspectRatio;
        }

        // Height of a row containing items[i..j) if stretched to fill availableWidth
        double rowHeight(int i, int j) {
          final gapCount = j - i - 1;
          final aspectSum = prefix[j] - prefix[i];
          return (availableWidth - gapCount * spacing) / aspectSum;
        }

        // Cost: squared deviation from target height. Reject rows outside [0.5x, 2x] target.
        double cost(int i, int j) {
          final h = rowHeight(i, j);
          if (h < targetRowHeight * 0.5 || h > targetRowHeight * 2.0) return double.infinity;
          final err = h - targetRowHeight;
          return err * err;
        }

        // DP: dp[j] = min cost to layout items[0..j), parent[j] = best i
        final dp = List<double>.filled(n + 1, double.infinity);
        final parent = List<int>.filled(n + 1, -1);
        dp[0] = 0;

        for (var j = 1; j <= n; j++) {
          final start = (j - maxItemsPerRow).clamp(0, j - 1);
          for (var i = start; i < j; i++) {
            if (dp[i] == double.infinity) continue;
            final c = cost(i, j);
            if (c == double.infinity) continue;
            final total = dp[i] + c;
            if (total < dp[j]) {
              dp[j] = total;
              parent[j] = i;
            }
          }
        }

        // Fallback: if no valid partition, use Wrap
        if (dp[n] == double.infinity) {
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: items.map((item) {
              return SizedBox(
                width: targetRowHeight * item.aspectRatio,
                height: targetRowHeight,
                child: item.child,
              );
            }).toList(),
          );
        }

        // Reconstruct row boundaries by walking parent[] backwards
        final boundaries = <int>[];
        var j = n;
        while (j > 0) {
          boundaries.add(j);
          j = parent[j];
        }
        boundaries.add(0);
        final reversed = boundaries.reversed.toList();

        // Build ALL rows as justified (including the last one)
        final rows = <Widget>[];
        for (var r = 0; r < reversed.length - 1; r++) {
          final start = reversed[r];
          final end = reversed[r + 1];
          final isLast = r == reversed.length - 2;

          rows.add(_buildRow(start, end, availableWidth));
          if (!isLast) rows.add(SizedBox(height: spacing));
        }

        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows);
      },
    );
  }

  Widget _buildRow(int start, int end, double availableWidth) {
    final rowItems = items.sublist(start, end);
    final count = rowItems.length;
    final totalSpacing = (count - 1) * spacing;
    final aspectSum = rowItems.fold(0.0, (sum, item) => sum + item.aspectRatio);
    final rowHeight = (availableWidth - totalSpacing) / aspectSum;

    // Floor each width to guarantee no overflow, then distribute leftover pixels
    final idealWidths = rowItems.map((item) => rowHeight * item.aspectRatio).toList();
    final usableWidth = availableWidth - totalSpacing;
    final widths = <double>[];
    var leftover = usableWidth;
    for (var i = 0; i < count; i++) {
      final w = idealWidths[i].floorToDouble();
      widths.add(w);
      leftover -= w;
    }
    for (var i = 0; leftover > 0.5 && i < count; i++) {
      widths[i] += 1;
      leftover -= 1;
    }

    final children = <Widget>[];
    for (var i = 0; i < count; i++) {
      if (i > 0) children.add(SizedBox(width: spacing));
      children.add(SizedBox(
        width: widths[i],
        height: rowHeight,
        child: rowItems[i].child,
      ));
    }
    return Row(mainAxisAlignment: MainAxisAlignment.start, children: children);
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
        // constraints: const BoxConstraints(maxHeight: 250),
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
                      : () =>
                            FullscreenImageViewerScreen.open(context, files: allFiles, index: idx, creatorId: creator.id, postId: post.id),
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

  const _ArchiveTile({super.key, required this.fileUrl, required this.fileName, required this.archiveService});

  @override
  State<_ArchiveTile> createState() => _ArchiveTileState();
}

class _ArchiveTileState extends State<_ArchiveTile> {
  _ArchiveState _state = _ArchiveState.idle;
  double _downloadProgress = 0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  int? _fileSize;
  String _localPath = '';
  List<String> _entries = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchFileSize();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchFileSize() async {
    // Try the archive cache first (previously downloaded archives).
    _fileSize = ArchiveCache.instance.getFileSize(widget.fileUrl);
    if (_fileSize != null) {
      if (mounted) setState(() {});
      return;
    }
    // Fall back to a HEAD request.
    try {
      final size = await widget.archiveService.getFileSize(widget.fileUrl);
      if (size != null && mounted) {
        setState(() => _fileSize = size);
      }
    } catch (e, st) {
      debugPrint('CreatorPostsScreen: getFileSize failed for ${widget.fileUrl}: $e\n$st');
    }
  }

  void _start() async {
    setState(() => _state = _ArchiveState.downloading);
    try {
      _localPath = await ArchiveCache.instance.getOrDownload(
        widget.fileUrl,
        widget.archiveService,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadedBytes = received;
            if (total > 0) {
              _totalBytes = total;
              _downloadProgress = received / total;
            }
          });
        },
      );
      final entries = await widget.archiveService.listEntries(_localPath);
      if (!mounted) return;
      setState(() {
        _entries = entries.map((e) => e.path).toList();
        _state = _ArchiveState.ready;
      });
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('CreatorPostsScreen: archive download failed for ${widget.fileUrl}: $e\n$st');
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
    final theme = Theme.of(context);
    final sizeLabel = _fileSize != null ? ImageMetaStore.formatBytes(_fileSize!) : null;
    return InkWell(
      onTap: _start,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.folder_zip, size: 24),
            ),
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
                  Text(
                    sizeLabel != null ? 'Tap to download and extract \u2022 $sizeLabel' : 'Tap to download and extract',
                    style: TextStyle(color: theme.colorScheme.outline, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.download, size: 20, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = _downloadProgress > 0 ? '${(_downloadProgress * 100).toStringAsFixed(0)}%' : '';
    final sizeLabel = _totalBytes > 0
        ? '${ImageMetaStore.formatBytes(_downloadedBytes)} / ${ImageMetaStore.formatBytes(_totalBytes)}'
        : (_downloadedBytes > 0 ? ImageMetaStore.formatBytes(_downloadedBytes) : null);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
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
              if (percentage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(percentage, style: TextStyle(color: theme.colorScheme.outline, fontSize: 12)),
                ),
            ],
          ),
          LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
          if (sizeLabel != null) Text(sizeLabel, style: TextStyle(color: theme.colorScheme.outline, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildReady(BuildContext context) {
    final theme = Theme.of(context);
    final imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif'};
    final size = _fileSize ?? (_totalBytes > 0 ? _totalBytes : null);
    final sizeLabel = size != null ? ImageMetaStore.formatBytes(size) : null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(Icons.folder_zip, size: 18, color: theme.colorScheme.primary),
              Expanded(
                child: Text(
                  widget.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                sizeLabel != null ? '$sizeLabel \u2022 ${_entries.length} files' : '${_entries.length} files',
                style: TextStyle(color: theme.colorScheme.outline, fontSize: 11),
              ),
            ],
          ),
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
                          final imageEntries = _entries.where((e) => imageExts.contains(p.extension(e).toLowerCase())).toList();
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
            spacing: 8,
            children: [
              Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
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
