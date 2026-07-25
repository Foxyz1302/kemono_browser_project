import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/cache/image_cache_service.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';
import 'package:kemono_browser_project/src/cache/kemono_image_provider.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../state/app_state.dart';
import '../state/auth_state.dart';
import 'creator_posts_screen.dart';

const serviceColors = <String, Color>{
  'patreon': Color(0xFFFF424D),
  'fanbox': Color(0xFF2C333C),
  'fantia': Color(0xFF3BB8F2),
  'afdian': Color(0xFFFF6B9D),
  'boosty': Color(0xFF3B82F6),
  'subscribestar': Color(0xFF7C3AED),
  'gumroad': Color(0xFFFF90E8),
  'dlsite': Color(0xFFE85D00),
  'fanclubs': Color(0xFF2C333C),
};

const serviceLabels = <String, String>{
  'patreon': 'Patreon',
  'fanbox': 'Pixiv Fanbox',
  'fantia': 'Fantia',
  'afdian': 'Afdian',
  'boosty': 'Boosty',
  'subscribestar': 'SubscribeStar',
  'gumroad': 'Gumroad',
  'dlsite': 'DLsite',
  'fanclubs': 'Fanclubs',
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _app = AppState.instance;

  @override
  void initState() {
    super.initState();
    _app.loadCreators();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kemono'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => AuthState.instance.logout())],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search creators...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => _app.searchQuery.value = v,
                  ),
                ),
                const SizedBox(width: 8),
                SignalBuilder(
                  builder: (context) {
                    return DropdownButton<SortBy>(
                      value: _app.sortBy.value,
                      items: SortBy.values
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(s.label, style: const TextStyle(fontSize: 13)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _app.sortBy.value = v;
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SignalBuilder(
              builder: (context) {
                if (_app.creatorsLoading.value && _app.creators.value.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_app.creatorsError.value != null && _app.creators.value.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Error: ${_app.creatorsError.value}'),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: () => _app.loadCreators(refresh: true), child: const Text('Retry')),
                      ],
                    ),
                  );
                }
                final creators = _app.filteredCreators;
                return creators.isEmpty
                    ? const Center(child: Text('No creators found'))
                    : CustomScrollView(
                        slivers: [
                          SliverPadding(
                            // Add your side padding here
                            padding: .all(4),
                            sliver: SliverGrid.builder(
                              gridDelegate: const FixedHeightGridDelegate(
                                maxCrossAxisExtent: 360,
                                height: 120.0, // <-- Strict, consistent tile pixel height
                                mainAxisSpacing: 4,
                                crossAxisSpacing: 4,
                              ),
                              itemCount: creators.length,
                              itemBuilder: (context, i) => CreatorTile(creators[i]),
                            ),
                          ),
                        ],
                      );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Perceptually uniform heat‑color from "now" → purple (1 year) → light purple (older).
Color heatColorCorrect(
  Duration duration, {
  Duration maxAge = const Duration(days: 365),
  Duration fadeDuration = const Duration(days: 365), // after maxAge, fade to light purple
}) {
  final age = duration;
  final t = age.inMilliseconds / maxAge.inMilliseconds; // 0 = now, 1 = maxAge

  // LCh control points: [L, C, h]    (h = hue in degrees)
  final stops = [
    [60.0, 75.0, 40.0], // hot orange-red
    [70.0, 55.0, 90.0], // yellow
    [55.0, 45.0, 200.0], // blue
    [40.0, 55.0, 300.0], // deep purple   (t = 1.0)
  ];

  // Interpolate inside [0, 1] along the LCh path
  if (t <= 1.0) {
    final sc = t * (stops.length - 1); // segment index + fraction
    final i = sc.floor().clamp(0, stops.length - 2);
    final f = sc - i;
    final lch = [
      stops[i][0] + (stops[i + 1][0] - stops[i][0]) * f,
      stops[i][1] + (stops[i + 1][1] - stops[i][1]) * f,
      stops[i][2] + (stops[i + 1][2] - stops[i][2]) * f,
    ];
    return lchToColor(lch[0], lch[1], lch[2]);
  }

  // Beyond maxAge: fade deep purple → light pastel purple
  final fadeFraction = ((age - maxAge).inMilliseconds / fadeDuration.inMilliseconds).clamp(0.0, 1.0);
  final deepPurpleLch = [40.0, 55.0, 300.0];
  final lightPurpleLch = [82.0, 18.0, 300.0]; // pastel

  return lchToColor(
    deepPurpleLch[0] + (lightPurpleLch[0] - deepPurpleLch[0]) * fadeFraction,
    deepPurpleLch[1] + (lightPurpleLch[1] - deepPurpleLch[1]) * fadeFraction,
    deepPurpleLch[2], // hue stays constant
  );
}

// ---------------------------------------------------------------------------
// CIELCh(ab) → sRGB  (D65 reference white, standard formulas)
// ---------------------------------------------------------------------------
Color lchToColor(double L, double C, double h) {
  // LCh → Lab
  final hRad = h * pi / 180.0;
  final a = C * cos(hRad);
  final b = C * sin(hRad);

  // Lab → XYZ (D65)
  const refX = 0.95047, refY = 1.00000, refZ = 1.08883;
  var fy = (L + 16) / 116;
  var fx = a / 500 + fy;
  var fz = fy - b / 200;

  final k = 6.0 / 29.0;
  final k2 = k * k;
  final k3 = k2 * k;

  final fx3 = fx * fx * fx, fy3 = fy * fy * fy, fz3 = fz * fz * fz;
  final x = refX * (fx3 > k3 ? fx3 : (116 * fx - 16) / 29.0 / 29.0);
  final y = refY * (fy3 > k3 ? fy3 : (116 * fy - 16) / 29.0 / 29.0);
  final z = refZ * (fz3 > k3 ? fz3 : (116 * fz - 16) / 29.0 / 29.0);

  // XYZ → linear RGB
  final rLin = x * 3.2404542 + y * -1.5371385 + z * -0.4985314;
  final gLin = x * -0.9692660 + y * 1.8760108 + z * 0.0415560;
  final bLin = x * 0.0556434 + y * -0.2040259 + z * 1.0572252;

  // Gamma correction (sRGB companding)
  double compand(double c) => c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055;

  return Color.fromARGB(
    255,
    (compand(rLin) * 255).clamp(0, 255).round(),
    (compand(gLin) * 255).clamp(0, 255).round(),
    (compand(bLin) * 255).clamp(0, 255).round(),
  );
}

// Defines a grid that forces a specific height regardless of screen width.
class FixedHeightGridDelegate extends SliverGridDelegate {
  final double maxCrossAxisExtent;
  final double height;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  const FixedHeightGridDelegate({
    required this.maxCrossAxisExtent,
    required this.height,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
  });

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    int crossAxisCount = ((constraints.crossAxisExtent + crossAxisSpacing) / (maxCrossAxisExtent + crossAxisSpacing)).ceil();
    if (crossAxisCount < 1) crossAxisCount = 1;

    final double childCrossAxisExtent = (constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1)) / crossAxisCount;

    // Explicitly set the height here
    return SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: height + mainAxisSpacing,
      crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
      childMainAxisExtent: height,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(FixedHeightGridDelegate oldDelegate) => true;
}

class CreatorTile extends StatelessWidget {
  final Creator creator;
  const CreatorTile(this.creator, {super.key});

  static const _base = 'https://pawchive.pw';

  @override
  Widget build(BuildContext context) {
    final serviceColor = serviceColors[creator.service] ?? Colors.grey;
    final serviceLabel = serviceLabels[creator.service] ?? creator.service;
    final bannerUrl = '$_base/banners/${creator.service}/${creator.id}';
    final iconUrl = '$_base/icons/${creator.service}/${creator.id}';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(creator.updated * 1000));

    return Material(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: KemonoImageProvider(bannerUrl),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: serviceColor.withValues(alpha: 0.3)),
          ),
          const ColoredBox(color: Colors.black45),
          Material(
            type: .transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              mouseCursor: SystemMouseCursors.click,
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreatorPostsScreen(creator)));
              },
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            right: 90,
            child: IgnorePointer(
              child: Row(
                children: [
                  ClipOval(
                    child: Container(
                      width: 40,
                      height: 40,
                      color: Colors.black54,
                      child: Image(
                        image: KemonoImageProvider(iconUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(Icons.person, color: Colors.white.withValues(alpha: 0.5), size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          creator.name,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('${creator.favorited} favorites', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
                      ],
                    ),
                  ),
                  if (!creator.everImported)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            right: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: serviceColor, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  serviceLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: heatColorCorrect(diff).withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
                child: Text(_timeAgo(creator.updated), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SignalBuilder(
              builder: (context) {
                final _ = ImageMetaStore.instance.metaReady.value;
                final files = ImageMetaStore.instance.fileCountForCreator(creator.id);
                if (files == 0) return SizedBox.shrink();
                final bytes = ImageMetaStore.instance.bytesForCreator(creator.id);
                return Material(
                  type: .transparency,
                  child: InkWell(
                    onTap: () => showDialog(context: context, builder: (context) => CreatorCacheDialog(creator)),
                    borderRadius: .circular(4),
                    child: Padding(
                      padding: .all(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          '$files files · ${ImageMetaStore.formatBytes(bytes)}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _timeAgo(int unixSeconds) {
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));
  if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
  if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'just now';
}

class CreatorCacheDialog extends StatelessWidget {
  final Creator creator;
  const CreatorCacheDialog(this.creator, {super.key});

  @override
  Widget build(BuildContext context) {
    final store = ImageMetaStore.instance;
    final serviceColor = serviceColors[creator.service] ?? Colors.grey;
    final serviceLabel = serviceLabels[creator.service] ?? creator.service;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: SignalBuilder(
          builder: (context) {
            final _ = store.metaReady.value;
            final files = store.fileCountForCreator(creator.id);
            final bytes = store.bytesForCreator(creator.id);
            final posts = store.postsForCreator(creator.id);

            return Column(
              mainAxisSize: .min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: serviceColor, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          serviceLabel,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          creator.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.storage, size: 16, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 8),
                      Text(
                        '$files files · ${ImageMetaStore.formatBytes(bytes)}',
                        style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (posts.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Posts',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: posts.length,
                      separatorBuilder: (_, _2) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = posts[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.postId, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${p.fileCount} files · ${ImageMetaStore.formatBytes(p.bytes)}',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                            onPressed: () async {
                              await _clearPost(store, p.postId);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (files > 0)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.delete_sweep, size: 18),
                      label: const Text('Clear all'),
                      style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                      onPressed: () async {
                        await _clearAll(context, store);
                      },
                    ),
                  ),
                if (files == 0)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No cached images',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _clearPost(ImageMetaStore store, String postId) async {
    final urls = <String>[];
    for (final e in store.allEntries.entries) {
      if (e.value.postId == postId && e.value.creatorId == creator.id) urls.add(e.key);
    }
    for (final url in urls) {
      store.remove(url);
      await ImageCacheService.instance.removeFile(url);
    }
  }

  Future<void> _clearAll(BuildContext context, ImageMetaStore store) async {
    final freed = store.purgeCreator(creator.id);
    for (final url in freed.keys) {
      await ImageCacheService.instance.removeFile(url);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared ${freed.length} files · ${ImageMetaStore.formatBytes(freed.values.fold(0, (a, b) => a + b))}')),
      );
    }
  }
}
