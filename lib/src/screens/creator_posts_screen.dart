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
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:fox_utils/fox_utils.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:signals/signals_flutter.dart';

import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/flags_store.dart';
import '../utils.dart';
import '../widgets/flag_post_dialog.dart';
import 'home_screen.dart';
import 'fullscreen_image_viewer_screen.dart';
import '../widgets/post_paginator.dart';

class CreatorPostsScreen extends SignalStatefulWidget {
  final Creator creator;
  const CreatorPostsScreen(this.creator, {super.key});

  @override
  State<CreatorPostsScreen> createState() => _CreatorPostsScreenState();
}

class _CreatorPostsScreenState extends State<CreatorPostsScreen> {
  final _app = AppState.instance;

  List<Post> _posts = [];
  bool _loading = true;
  Set<String> _newPostIds = {};

  static const int _pageSize = 50;
  int _page = 1;
  int? _totalPosts;
  int _requestSeq = 0;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPage(int page) async {
    final seq = ++_requestSeq;
    setState(() => _loading = _posts.isEmpty);
    try {
      final posts = await _app.fetchCreatorPosts(widget.creator, offset: (page - 1) * _pageSize);
      if (!mounted || seq != _requestSeq) return;

      if (posts.isEmpty && page > 1) {
        // Past the last page — the total was wrong or unknown. Clamp and stop.
        setState(() => _totalPosts = (page - 1) * _pageSize);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No posts on page $page')));
        return;
      }

      int? total = _totalPosts;
      if (total == null) {
        try {
          total = await _app.fetchCreatorPostCount(widget.creator);
        } catch (e, st) {
          debugPrint('Failed to read post count for ${widget.creator.id}: $e\n$st');
          total = null;
        }
        if (!mounted || seq != _requestSeq) return;
        if (total != null && total <= _pageSize) total = null;
      }

      setState(() {
        _posts = posts;
        _page = page;
        _totalPosts = total;
      });

      if (page == 1) {
        _computeNewPosts(posts);
        _app.updateLastChecked(widget.creator.service, widget.creator.id);
      }
    } catch (e, st) {
      debugPrint('Failed to load creator posts page $page: $e\n$st');
      if (!mounted || seq != _requestSeq) return;
      if (page == 1) {
        setState(() {
          _posts = [];
          _newPostIds = {};
        });
      }
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loading = false);
    }
  }

  void _goToPage(int page) {
    _loadPage(page);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _computeNewPosts(List<Post> posts) {
    final lastChecked = _app.getLastChecked(widget.creator.service, widget.creator.id);
    if (lastChecked == null) {
      _newPostIds = {};
      return;
    }
    _newPostIds = posts
        .where((p) {
          try {
            return DateTime.parse(p.published).isAfter(DateTime.parse(lastChecked));
          } catch (_) {
            return false;
          }
        })
        .map((p) => p.id)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.creator;
    if (_loading && _posts.isEmpty) {
      return Scaffold(
        body: SafeArea(top: true, bottom: false, child: const Center(child: CircularProgressIndicator())),
      );
    }

    final hasData = _posts.isNotEmpty;
    // A short first page means there is nothing to page to, and an unknown
    // total can't drive a pager — hide it in both cases.
    final showPaginator = hasData && (_totalPosts != null || _posts.length >= _pageSize);

    final serviceColor = serviceColors[c.service] ?? Colors.grey;
    final serviceLabel = serviceLabels[c.service] ?? c.service;
    final iconUrl = '${FileHelpers.baseUrl}/icons/${c.service}/${c.id}';
    final ts = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    // ── Shared heart & cache widgets ──────────────────────────────
    final heartWidget = SignalBuilder(
      builder: (context) {
        final isFav = _app.favoritedIds.value.contains('${c.service}/${c.id}');
        return AnimatedFavoriteButton(
          key: ValueKey('cph_${c.service}_${c.id}'),
          isFavorited: isFav,
          size: 20,
          onChanged: (newIsFav) async {
            final loggedIn = AuthState.instance.authStatus.value == AuthStatus.loggedIn;
            if (!loggedIn) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to favorite creators')));
              }
              return false;
            }
            try {
              if (newIsFav) {
                await PawchiveClient.instance.favoriteCreator(service: c.service, creatorId: c.id);
                _app.addFavoriteCreator(c);
              } else {
                await PawchiveClient.instance.unfavoriteCreator(service: c.service, creatorId: c.id);
                _app.removeFavoriteCreator(c.service, c.id);
              }
              return true;
            } catch (e, st) {
              debugPrint('Failed to toggle favorite: $e\n$st');
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
              return false;
            }
          },
        );
      },
    );

    final cacheWidget = SignalBuilder(
      builder: (context) {
        final _ = ImageMetaStore.instance.metaReady.value;
        final bytes = ImageMetaStore.instance.bytesForCreator(c.id);
        final files = ImageMetaStore.instance.fileCountForCreator(c.id);
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: files == 0
                ? Text('No cache', style: TextStyle(color: ts.colorScheme.outline, fontSize: 11))
                : Text(
                    '$files files · ${ImageMetaStore.formatBytes(bytes)}',
                    style: TextStyle(color: ts.colorScheme.outline, fontSize: 11),
                  ),
          ),
        );
      },
    );

    // ── Expanded header ──────────────────────────────────────────────
    final expandedHeader = Material(
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.only(bottomRight: .circular(8), bottomLeft: .circular(8)),
      // margin: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: SizedBox(
        // height: 116,
        child: Column(
          mainAxisSize: .min,
          children: [
            // Service color accent strip
            // Container(height: 3, color: serviceColor),
            // Top bar: back + name + heart + cache
            // SizedBox(
            //   height: 40,
            //   child: Row(
            //     children: [
            //       IconButton(
            //         icon: const Icon(Icons.arrow_back),
            //         onPressed: () => Navigator.pop(context),
            //       ),
            //       Expanded(
            //         child: Text(c.name,
            //           style: ts.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            //           maxLines: 1, overflow: TextOverflow.ellipsis),
            //       ),
            //       heartWidget,
            //       cacheWidget,
            //     ],
            //   ),
            // ),
            // Remaining content: icon + name + badge + followers
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipOval(
                      child: Container(
                        width: 48,
                        height: 48,
                        color: serviceColor.withValues(alpha: 0.3),
                        child: SignalBuilder(
                          builder: (context) {
                            final showAnim = AppState.instance.showImageLoadAnimation.value;
                            return LeafImage(
                              image: KemonoImageProvider(iconUrl),
                              fit: BoxFit.cover,
                              cacheWidth: (48 * dpr).round(),
                              errorBuilder: (_, _, _) => Icon(Icons.person, color: Colors.white.withValues(alpha: 0.5), size: 28),
                              revealAnimation: showAnim ? const GradientRevealAnimation() : null,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.name,
                            style: ts.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            spacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: serviceColor, borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  serviceLabel,
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text('${c.favorited} favorites', style: ts.textTheme.bodySmall?.copyWith(color: ts.colorScheme.outline)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    heartWidget,
                    cacheWidget,
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // ── Collapsed header (compact toolbar) ─────────────────────────
    final collapsedHeader = Container(
      height: kToolbarHeight,
      decoration: BoxDecoration(
        color: ts.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: ts.dividerColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),

            ClipOval(
              child: Container(
                width: 36,
                height: 36,
                color: serviceColor.withValues(alpha: 0.3),
                child: SignalBuilder(
                  builder: (context) {
                    final showAnim = AppState.instance.showImageLoadAnimation.value;
                    return LeafImage(
                      image: KemonoImageProvider(iconUrl),
                      fit: BoxFit.cover,
                      cacheWidth: (36 * dpr).round(),
                      errorBuilder: (_, _, _) => Icon(Icons.person, color: Colors.white.withValues(alpha: 0.5), size: 28),
                      revealAnimation: showAnim ? const GradientRevealAnimation() : null,
                    );
                  },
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(c.name, style: ts.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            heartWidget,
            cacheWidget,
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverHeaderDelegate(
                expanded: expandedHeader,
                collapsed: collapsedHeader,
                maxHeight: 80,
                minHeight: kToolbarHeight,
              ),
            ),
            if (showPaginator)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                sliver: SliverToBoxAdapter(
                  child: PostPaginator(
                    page: _page,
                    pageSize: _pageSize,
                    total: _totalPosts,
                    onPage: _goToPage,
                  ),
                ),
              ),
            if (!hasData && !_loading)
              const SliverFillRemaining(child: Center(child: Text('No posts found')))
            else
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid.builder(
                  gridDelegate: const FixedHeightGridDelegate(
                    maxCrossAxisExtent: 900,
                    height: 200,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: _posts.length,
                  itemBuilder: (context, i) {
                    final p = _posts[i];
                    final imageFiles = p.attachments.where((f) => FileHelpers.isImage(f.name)).toList();
                    final otherFiles = p.attachments.where((f) => !FileHelpers.isImage(f.name)).toList();
                    final hasSeparateThumb =
                        p.file != null && FileHelpers.isImage(p.file!.name) && !p.attachments.any((f) => f.path == p.file!.path);
                    // Only fanbox uses "the first attachment is the post banner";
                    // on patreon the first image is usually real content.
                    final skipBannerImage = !hasSeparateThumb && p.service == 'fanbox';
                    final previewFiles =
                        skipBannerImage ? [...imageFiles.skip(1), ...otherFiles] : [...imageFiles, ...otherFiles];

                    final thumbUrl = p.file != null && FileHelpers.isImage(p.file!.name)
                        ? '${FileHelpers.imgThumbBase}${p.file!.path}'
                        : imageFiles.isNotEmpty
                        ? '${FileHelpers.imgThumbBase}${imageFiles.first.path}'
                        : null;
                    final isPending = p.previewState == 'pending';
                    final isKemonoUnavailable = !isPending && p.hasFull == false;

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final halfTile = constraints.maxWidth * 0.5;
                        final thumbCacheWidth = (halfTile * MediaQuery.devicePixelRatioOf(context)).round();
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              // "New" star for posts published after last visit.
                              if (_newPostIds.contains(p.id)) const Positioned(top: 4, right: 4, child: AnimatedStar(size: 16)),
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
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(15),
                                            bottomRight: Radius.circular(15),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: SignalBuilder(
                                            builder: (context) {
                                              final showAnim = AppState.instance.showImageLoadAnimation.value;
                                              return LeafImage(
                                                image: KemonoImageProvider(thumbUrl, creatorId: c.id, postId: p.id),
                                                fit: BoxFit.cover,
                                                cacheWidth: thumbCacheWidth,
                                                revealAnimation: showAnim ? const GradientRevealAnimation() : null,
                                                loadingBuilder: (ctx, progress) => ShaderMask(
                                                  shaderCallback: (bounds) => const LinearGradient(
                                                    begin: Alignment.centerLeft,
                                                    end: Alignment.centerRight,
                                                    colors: [Colors.white, Colors.transparent],
                                                    stops: [-0.3, 0.0],
                                                  ).createShader(bounds),
                                                  blendMode: BlendMode.dstIn,
                                                  child: Container(color: Colors.grey.shade800),
                                                ),
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
                                                if (FileHelpers.isImage(f.name)) {
                                                  final fileIdx = p.attachments.indexOf(f);
                                                  return GestureDetector(
                                                    onTap: () => FullscreenImageViewerScreen.open(
                                                      context,
                                                      files: p.attachments,
                                                      index: fileIdx >= 0 ? fileIdx : j,
                                                      service: c.service,
                                                      creatorId: c.id,
                                                      postId: p.id,
                                                      hasFull: p.hasFull,
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: SizedBox(
                                                        width: 48,
                                                        height: 48,
                                                        child: LeafImage(
                                                          image: KemonoImageProvider(
                                                            '${FileHelpers.imgThumbBase}${f.path}',
                                                            creatorId: c.id,
                                                            postId: p.id,
                                                          ),
                                                          fit: BoxFit.cover,
                                                          cacheWidth: (48 * MediaQuery.devicePixelRatioOf(context)).round(),
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
              ),
            if (showPaginator)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                sliver: SliverToBoxAdapter(
                  child: PostPaginator(
                    page: _page,
                    pageSize: _pageSize,
                    total: _totalPosts,
                    onPage: _goToPage,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fileIcon(String? name) {
    final ext = FileHelpers.fileExtension(name);
    final icon = FileHelpers.iconForExtension[ext] ?? Icons.insert_drive_file;
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

// ── Collapsible sliver header delegate ─────────────────────────────────────
class _SliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget expanded;
  final Widget collapsed;
  final double maxHeight;
  final double minHeight;

  _SliverHeaderDelegate({required this.expanded, required this.collapsed, required this.maxHeight, required this.minHeight});

  @override
  double get maxExtent => maxHeight;
  @override
  double get minExtent => minHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final extent = maxExtent - minExtent;
    final progress = extent > 0 ? (shrinkOffset / extent).clamp(0.0, 1.0) : 0.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (progress < 1.0) Opacity(opacity: 1.0 - progress, child: expanded),
        if (progress > 0.0) Opacity(opacity: progress, child: collapsed),
      ],
    );
  }

  @override
  bool shouldRebuild(_SliverHeaderDelegate oldDelegate) => true;
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

  @override
  Widget build(BuildContext context) {
    final imageFiles = post.attachments.where((f) => FileHelpers.isImage(f.name)).toList();
    final otherFiles = post.attachments.where((f) => !FileHelpers.isImage(f.name)).toList();
    final isPending = post.previewState == 'pending';
    final isKemonoUnavailable = !isPending && post.hasFull == false;
    final isUnavailable = isPending || isKemonoUnavailable;
    final serviceColor = serviceColors[creator.service] ?? Colors.grey;
    final bannerUrl = !isUnavailable && post.file != null && FileHelpers.isImage(post.file!.name)
        ? '${FileHelpers.imgThumbBase}${post.file!.path}'
        : !isUnavailable && post.service == 'fanbox' && imageFiles.isNotEmpty
        ? '${FileHelpers.imgThumbBase}${imageFiles.first.path}'
        : null;
    final dpr = MediaQuery.devicePixelRatioOf(context);

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
                        LeafImage(
                          image: KemonoImageProvider(bannerUrl, creatorId: creator.id, postId: post.id),
                          fit: BoxFit.cover,
                          cacheHeight: (180 * dpr).round(),
                          height: .infinity,
                          width: .infinity,
                          errorBuilder: (_, e, _) {
                            debugPrint("$e");
                            return Container(
                              color: Colors.grey.shade800,
                              child: const Icon(Icons.image_not_supported, color: Colors.white38),
                            );
                          },
                          onTap: () {
                            final bannerFiles = post.file != null && FileHelpers.isImage(post.file!.name)
                                ? [post.file!, ...post.attachments.where((f) => f.path != post.file?.path)]
                                : post.attachments;
                            FullscreenImageViewerScreen.open(
                              context,
                              files: bannerFiles,
                              index: 0,
                              service: creator.service,
                              creatorId: creator.id,
                              postId: post.id,
                              hasFull: post.hasFull,
                            );
                          },
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
                      onSelected: (value) async {
                        final url = '${FileHelpers.baseUrl}/${post.service}/user/${post.user}/post/${post.id}';
                        switch (value) {
                          case 'browser':
                            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                          case 'copy':
                            Clipboard.setData(ClipboardData(text: url));
                          case 'flag':
                            final key = '${post.service}/${post.user}/${post.id}';
                            final saved = await showFlagPostDialog(
                              context,
                              post,
                              existing: FlagsStore.instance.forKey(key)?.comment,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(saved ? 'Flag saved' : 'Flag updated')),
                            );
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
                        const PopupMenuItem(
                          value: 'flag',
                          child: ListTile(
                            leading: Icon(Icons.flag_outlined),
                            title: Text('Flag post'),
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    SignalBuilder(
                      builder: (context) {
                        final key = '${post.service}/${post.user}/${post.id}';
                        final isFav = AppState.instance.favoritePostIds.value.contains(key);
                        return AnimatedFavoriteButton(
                          key: ValueKey('pdh_${post.service}/${post.user}/${post.id}'),
                          isFavorited: isFav,
                          onChanged: (newIsFav) async {
                            final loggedIn = AuthState.instance.authStatus.value == AuthStatus.loggedIn;
                            if (!loggedIn) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to favorite posts')));
                              }
                              return false;
                            }
                            try {
                              if (newIsFav) {
                                await PawchiveClient.instance.favoritePost(service: post.service, creatorId: post.user, postId: post.id);
                                AppState.instance.addFavoritePost(post.service, post.user, post.id);
                              } else {
                                await PawchiveClient.instance.unfavoritePost(service: post.service, creatorId: post.user, postId: post.id);
                                AppState.instance.removeFavoritePost(post.service, post.user, post.id);
                              }
                              return true;
                            } catch (e, st) {
                              debugPrint('Failed to toggle post favorite: $e\n$st');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                              }
                              return false;
                            }
                          },
                        );
                      },
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
                    final url = '${FileHelpers.imgThumbBase}${f.path}';
                    final aspectRatio = ImageMetaStore.instance.lookup(url)?.aspectRatio ?? 1.0;
                    final idx = scrollableImages.indexOf(f);
                    return (
                      child: ImageWrapTile(f: f, creator: creator, post: post, allFiles: allFiles, idx: idx),
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
          if (allFiles.any((f) => f.name != null && archiveExts.contains(FileHelpers.fileExtension(f.name))))
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                'Archives',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ...otherFiles.map((f) {
            final ext = FileHelpers.fileExtension(f.name);
            final isArchive = ext != null && archiveExts.contains(ext);
            if (isArchive) {
              final fileUrl = f.downloadUrl(hasFull: post.hasFull);
              if (fileUrl == null) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(Icons.folder_zip, color: Theme.of(context).colorScheme.outline),
                      Expanded(
                        child: Text(
                          f.name ?? 'archive',
                          style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                        ),
                      ),
                      Text('not available', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 11)),
                    ],
                  ),
                );
              }
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
              child: GestureDetector(
                onTap: FileHelpers.isVideo(f.name)
                    ? () {
                        final idx = allFiles.indexOf(f);
                        if (idx >= 0) {
                          FullscreenImageViewerScreen.open(
                            context,
                            files: allFiles,
                            index: idx,
                            service: post.service,
                            creatorId: creator.id,
                            postId: post.id,
                            hasFull: post.hasFull,
                          );
                        }
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(
                        FileHelpers.isVideo(f.name) ? Icons.videocam : FileHelpers.iconForExtension[ext] ?? Icons.insert_drive_file,
                        size: 16,
                        color: FileHelpers.isVideo(f.name) ? Colors.blue.shade300 : Theme.of(context).colorScheme.outline,
                      ),
                      Expanded(
                        child: Text(
                          f.name ?? ext?.toUpperCase() ?? 'File',
                          style: TextStyle(fontSize: 12, color: FileHelpers.isVideo(f.name) ? Colors.blue.shade200 : null),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (FileHelpers.isVideo(f.name)) Icon(Icons.play_circle_outline, size: 16, color: Colors.blue.shade300),
                    ],
                  ),
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

  const JustifiedImageGrid({super.key, required this.items, this.targetRowHeight = 180.0, this.spacing = 8.0, this.maxItemsPerRow = 10});

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
              return SizedBox(width: targetRowHeight * item.aspectRatio, height: targetRowHeight, child: item.child);
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

    final usableWidth = availableWidth - totalSpacing;
    final widths = <double>[];
    var remainingWidth = usableWidth;
    for (var i = 0; i < count; i++) {
      if (i == count - 1) {
        // Last item — whatever is left, avoids fp overflow
        widths.add(remainingWidth);
      } else {
        final w = (rowHeight * rowItems[i].aspectRatio).floorToDouble();
        widths.add(w);
        remainingWidth -= w;
      }
    }

    final children = <Widget>[];
    for (var i = 0; i < count; i++) {
      if (i > 0) children.add(SizedBox(width: spacing));
      children.add(SizedBox(width: widths[i], height: rowHeight, child: rowItems[i].child));
    }
    return Row(mainAxisAlignment: MainAxisAlignment.start, children: children);
  }
}

// In a shared file (or at the bottom of the screen file)
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key, required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final shortest = math.min(w, h);

        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8), // match tile radius
              ),
            ),
            CustomPaint(
              size: Size(w, h),
              painter: ClockwiseBorderPainter(progress: progress),
            ),
            Positioned(
              bottom: shortest * 0.06,
              child: Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: shortest * 0.04,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ImageWrapTile extends StatelessWidget {
  const ImageWrapTile({
    super.key,
    required this.f,
    required this.creator,
    required this.post,
    required this.allFiles,
    required this.idx,
  });

  final FileInfo f;
  final Creator creator;
  final Post post;
  final List<FileInfo> allFiles;
  final int idx;

  @override
  Widget build(BuildContext context) {
    final fullUrl = f.downloadUrl(hasFull: post.hasFull);
    final thumbUrl = '${FileHelpers.imgThumbBase}${f.path}';
    final isTouch =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.fuchsia;

    final fullSize = fullUrl == null ? null : ImageMetaStore.instance.lookup(KemonoImageProvider.canonicalUrl(fullUrl))?.bytes;
    final thumbSize = ImageMetaStore.instance.lookup(thumbUrl)?.bytes;
    String? sizeOf(int? bytes) => bytes == null ? null : ImageMetaStore.formatBytes(bytes);

    return LeafContextMenu(
      entries: [
        if (fullUrl != null && isTouch)
          ContextMenuAsyncAction(
            label: 'Copy image',
            icon: Icons.image,
            subtitle: sizeOf(fullSize),
            doneLabel: 'Image copied',
            task: (p) => _copyImageBytes(fullUrl, p),
          ),
        if (fullUrl != null && !isTouch)
          ContextMenuAsyncAction(
            label: 'Copy image file',
            icon: Icons.insert_drive_file,
            subtitle: sizeOf(fullSize),
            doneLabel: 'File copied',
            task: (_) => _copyFilePath(fullUrl),
          ),
        if (fullUrl != null)
          ContextMenuAsyncAction(
            label: 'Copy image URL',
            icon: Icons.link,
            doneLabel: 'URL copied',
            task: (_) => Clipboard.setData(ClipboardData(text: fullUrl)),
          ),
        const ContextMenuDivider(),
        if (isTouch)
          ContextMenuAsyncAction(
            label: 'Copy thumbnail',
            icon: Icons.image,
            subtitle: sizeOf(thumbSize),
            doneLabel: 'Thumbnail copied',
            task: (p) => _copyImageBytes(thumbUrl, p),
          ),
        if (!isTouch)
          ContextMenuAsyncAction(
            label: 'Copy thumbnail file',
            icon: Icons.insert_drive_file,
            subtitle: sizeOf(thumbSize),
            doneLabel: 'File copied',
            task: (_) => _copyFilePath(thumbUrl),
          ),
        ContextMenuAsyncAction(
          label: 'Copy thumbnail URL',
          icon: Icons.link,
          doneLabel: 'URL copied',
          task: (_) => Clipboard.setData(ClipboardData(text: thumbUrl)),
        ),
      ],
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        child: LeafImage(
          image: KemonoImageProvider('${FileHelpers.imgThumbBase}${f.path}', creatorId: creator.id, postId: post.id),
          fit: BoxFit.cover,
          cacheHeight: (250 * MediaQuery.devicePixelRatioOf(context)).round(),
          width: .infinity,
          height: .infinity,
          loadingBuilder: (context, progress) => SkeletonTile(progress: progress),
          errorBuilder: (_, _, retry) => AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              color: Colors.grey.shade800,
              alignment: Alignment.center,
              child: Column(
                spacing: 4,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image_not_supported, color: Colors.white38),
                  IconButton.outlined(icon: Icon(Icons.refresh), onPressed: retry),
                ],
              ),
            ),
          ),
          onTap: () => FullscreenImageViewerScreen.open(
                context,
                files: allFiles,
                index: idx,
                service: post.service,
                creatorId: creator.id,
                postId: post.id,
                hasFull: post.hasFull,
              ),
        ),
      ),
    );
  }

  Future<cache.FileInfo> _cachedFile(String url, {ValueChanged<double>? onProgress}) async {
    cache.FileInfo? info;
    await for (final r in ImageCacheService.instance.getCachedFileStream(url)) {
      if (r is cache.DownloadProgress) {
        final progress = r.progress;
        if (progress != null) onProgress?.call(progress);
      } else if (r is cache.FileInfo) {
        info = r;
      }
    }
    if (info == null) throw StateError('No cached file for $url');
    return info;
  }

  Future<void> _copyImageBytes(String url, ValueChanged<double>? onProgress) async {
    final info = await _cachedFile(url, onProgress: onProgress);
    final bytes = await info.file.readAsBytes();
    await ClipboardX.copyImage(bytes);
  }

  Future<void> _copyFilePath(String url) async {
    final info = await _cachedFile(url);
    await ClipboardX.copyFiles([info.file.path]);
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
                final isImage = FileHelpers.dottedImageExtensions.contains(ext);
                final isVideo = FileHelpers.dottedVideoExtensions.contains(ext);
                final isMedia = isImage || isVideo;
                return GestureDetector(
                  onTap: isMedia
                      ? () {
                          final mediaExtensions = {...FileHelpers.dottedImageExtensions, ...FileHelpers.dottedVideoExtensions};
                          final mediaEntries = _entries.where((e) => mediaExtensions.contains(p.extension(e).toLowerCase())).toList();
                          final index = mediaEntries.indexOf(path);
                          FullscreenImageViewerScreen.openArchive(
                            context,
                            archiveService: widget.archiveService,
                            localPath: _localPath,
                            entries: mediaEntries,
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
                            child: isVideo
                                ? const Icon(Icons.videocam, size: 20, color: Colors.white54)
                                : Text(_extLabel(ext), style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline)),
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
