import 'dart:math';

import 'package:flutter/material.dart' hide SearchBar;
import 'package:flutter/rendering.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/cache/image_cache_service.dart';
import 'package:kemono_browser_project/src/cache/image_meta_store.dart';
import 'package:kemono_browser_project/src/cache/kemono_image_provider.dart';
import 'package:kemono_browser_project/src/widgets/search_bar.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:persistent_header_adaptive/persistent_header_adaptive.dart';
import 'package:signals/signals_flutter.dart';

import '../api/pawchive_client.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../utils.dart';
import 'creator_posts_screen.dart';
import 'login_screen.dart';

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
  final _filterCtrl = LeafPopoverController();
  final _mobileOverflowCtrl = LeafPopoverController();
  final _settingsCtrl = LeafPopoverController();
  final _accountCtrl = LeafPopoverController();

  @override
  void initState() {
    super.initState();
    _app.loadCreators();
  }

  Widget _buildDesktopLayout(BuildContext context) {
    debugPrint("building desktop layout");
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(15),
      color: cs.surfaceContainerLow.withValues(alpha: 0.8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          spacing: 6,
          children: [
            const Text('Kemono', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 32, child: VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant)),
            // ── Favorites-only toggle ──────────────────────────────────────────
            SignalBuilder(
              builder: (context) {
                final active = _app.showFavoritesOnly.value;
                // return _FilterToggle(
                //   icon: Icons.favorite,
                //   label: 'Favorites only',
                //   subtitle: 'Show only followed creators',
                //   value: active,
                //   onChanged: (v) => _app.showFavoritesOnly.value = v,
                // );
                return Material(
                  clipBehavior: .antiAlias,
                  borderRadius: .circular(100),
                  elevation: 4,
                  child: InkWell(
                    onTap: () => _app.showFavoritesOnly.value = !_app.showFavoritesOnly.value,
                    child: Row(
                      children: [
                        AnimatedFavoriteButton(
                          isFavorited: active,
                          onChanged: (newIsFavorited) => Future(() {
                            _app.showFavoritesOnly.value = !newIsFavorited;
                            return true;
                          }),
                        ),
                        Text("Favorites", style: TextTheme.of(context).bodyLarge?.copyWith(color: cs.onSurface)),
                        SizedBox(width: 10),
                      ],
                    ),
                  ),
                );
              },
            ),
            SignalBuilder(
              builder: (context) {
                final loggedIn = AuthState.instance.authStatus.value == AuthStatus.loggedIn;
                if (!loggedIn) {
                  return IconButton(
                    icon: const Icon(Icons.login, size: 20),
                    tooltip: 'Sign in',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                  );
                }
                return LeafPopover(
                  controller: _accountCtrl,
                  childAnchor: Alignment.bottomCenter,
                  popoverAnchor: Alignment.topCenter,
                  spacing: 6,
                  popoverBuilder: (context, ctrl) => _AccountMenuContent(controller: ctrl),
                  child: IconButton(
                    icon: const Icon(Icons.account_circle, size: 20),
                    tooltip: 'Account',
                    onPressed: () => _accountCtrl.toggle(),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
            Expanded(
              child: SearchBar(
                querySignal: _app.searchQuery,
                hintText: 'Search creators...',
                onSearch: _app.onSearchTrigger, // <-- debounced callback
              ),
            ),
            SignalBuilder(
              builder: (context) {
                final asc = _app.sortAscending.value;
                return IconButton(
                  icon: Icon(asc ? Icons.arrow_upward : Icons.arrow_downward, size: 20),
                  tooltip: asc ? 'Ascending' : 'Descending',
                  onPressed: () => _app.sortAscending.value = !asc,
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                );
              },
            ),
            SignalBuilder(
              builder: (context) {
                final isFavMode = _app.showFavoritesOnly.value;
                return DropdownButton<SortBy>(
                  value: _app.sortBy.value,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(15),
                  elevation: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  dropdownColor: cs.surfaceContainerHigh,
                  items: SortBy.values
                      .where((s) => s.isFavoritesSort == isFavMode)
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _app.sortBy.value = v;
                  },
                );
              },
            ),
            LeafPopover(
              controller: _filterCtrl,
              childAnchor: Alignment.bottomCenter,
              popoverAnchor: Alignment.topCenter,
              spacing: 6,
              popoverBuilder: (context, _) => _FilterPopoverContent(),
              child: IconButton(
                icon: Icon(_app.showCachedOnly.value ? Icons.filter_alt : Icons.filter_alt_outlined, size: 20),
                tooltip: 'Filters',
                onPressed: () => _filterCtrl.toggle(),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              ),
            ),
            SizedBox(height: 32, child: VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant)),
            LeafPopover(
              controller: _settingsCtrl,
              childAnchor: Alignment.bottomCenter,
              popoverAnchor: Alignment.topCenter,
              spacing: 6,
              popoverBuilder: (context, _) => _SettingsPopoverContent(),
              child: IconButton(
                icon: const Icon(Icons.settings, size: 20),
                tooltip: 'Settings',
                onPressed: () => _settingsCtrl.toggle(),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(15),
      color: cs.surfaceContainerLow.withValues(alpha: 0.8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          spacing: 4,
          children: [
            SignalBuilder(
              builder: (context) {
                final loggedIn = AuthState.instance.authStatus.value == AuthStatus.loggedIn;
                if (!loggedIn) {
                  return IconButton(
                    icon: const Icon(Icons.login, size: 20),
                    tooltip: 'Sign in',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                  );
                }
                return LeafPopover(
                  controller: _accountCtrl,
                  childAnchor: Alignment.bottomRight,
                  popoverAnchor: Alignment.topRight,
                  spacing: 6,
                  popoverBuilder: (context, ctrl) => _AccountMenuContent(controller: ctrl),
                  child: IconButton(
                    icon: const Icon(Icons.account_circle, size: 20),
                    tooltip: 'Account',
                    onPressed: () => _accountCtrl.toggle(),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
            SignalBuilder(
              builder: (context) {
                final active = _app.showFavoritesOnly.value;
                // return _FilterToggle(
                //   icon: Icons.favorite,
                //   label: 'Favorites only',
                //   subtitle: 'Show only followed creators',
                //   value: active,
                //   onChanged: (v) => _app.showFavoritesOnly.value = v,
                // );
                return AnimatedFavoriteButton(
                  isFavorited: active,
                  onChanged: (newIsFavorited) => Future(() {
                    _app.showFavoritesOnly.value = newIsFavorited;
                    return true;
                  }),
                );
              },
            ),
            Expanded(
              child: SearchBar(
                querySignal: _app.searchQuery,
                hintText: 'Search creators...',
                onSearch: _app.onSearchTrigger, // <-- debounced callback
              ),
            ),
            LeafPopover(
              controller: _mobileOverflowCtrl,
              childAnchor: Alignment.bottomRight,
              popoverAnchor: Alignment.topRight,
              spacing: 6,
              popoverBuilder: (context, _) => _MobileSortFilterContent(),
              child: IconButton(
                icon: const Icon(Icons.tune, size: 20),
                tooltip: 'Sort & Filter',
                onPressed: () => _mobileOverflowCtrl.toggle(),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              ),
            ),
            LeafPopover(
              controller: _settingsCtrl,
              childAnchor: Alignment.bottomRight,
              popoverAnchor: Alignment.topRight,
              spacing: 6,
              popoverBuilder: (context, _) => _SettingsPopoverContent(),
              child: IconButton(
                icon: const Icon(Icons.settings, size: 20),
                tooltip: 'Settings',
                onPressed: () => _settingsCtrl.toggle(),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SignalBuilder(
        builder: (context) {
          if (_app.creatorsLoading.value && _app.creators.value.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_app.creatorsError.value != null && _app.creators.value.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  Text('Error: ${_app.creatorsError.value}'),
                  FilledButton(onPressed: () => _app.loadCreators(refresh: true), child: const Text('Retry')),
                ],
              ),
            );
          }
          final creators = _app.filteredCreators.value;
          // if (_app.filtering.value && _app.creators.value.isEmpty) {
          //   return const Center(child: CircularProgressIndicator());
          // }
          return CustomScrollView(
            slivers: [
              AdaptiveHeightSliverPersistentHeader(
                floating: true,
                pinned: true,
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 560) {
                              return _buildMobileLayout(context);
                            }
                            return _buildDesktopLayout(context);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // SliverToBoxAdapter(
              //   child: Center(
              //     child: Padding(
              //       padding: const EdgeInsets.symmetric(vertical: 8),
              //       child: Row(
              //         mainAxisSize: MainAxisSize.min,
              //         spacing: 10,
              //         children: [
              //           const AnimatedStar(size: 20),
              //           Text('New Posts', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
              //           const AnimatedStar(size: 16, color: Colors.lightBlueAccent),
              //         ],
              //       ),
              //     ),
              //   ),
              // ),
              if (creators.isEmpty && _app.filtering.value)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (creators.isEmpty)
                const SliverFillRemaining(child: Center(child: Text('No creators found')))
              else
                SliverPadding(
                  padding: .all(4),
                  sliver: SliverGrid.builder(
                    gridDelegate: const FixedHeightGridDelegate(
                      maxCrossAxisExtent: 360,
                      height: 120.0,
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

  @override
  Widget build(BuildContext context) {
    final serviceColor = serviceColors[creator.service] ?? Colors.grey;
    final serviceLabel = serviceLabels[creator.service] ?? creator.service;
    final bannerUrl = '${FileHelpers.baseUrl}/banners/${creator.service}/${creator.id}';
    final iconUrl = '${FileHelpers.baseUrl}/icons/${creator.service}/${creator.id}';
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final bannerCacheWidth = (360 * dpr).round();
    final iconCacheSize = (40 * dpr).round();

    return Material(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SignalBuilder(
            builder: (context) {
              final showAnim = AppState.instance.showImageLoadAnimation.value;
              return LeafImage(
                image: KemonoImageProvider(bannerUrl),
                fit: BoxFit.cover,
                cacheWidth: bannerCacheWidth,
                errorBuilder: (_, _, _) => ColoredBox(color: serviceColor.withValues(alpha: 0.3)),
                revealAnimation: showAnim ? const GradientRevealAnimation() : null,
              );
            },
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
          Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 6,
              children: [
                Spacer(),
                IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(color: serviceColor, borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      serviceLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: IgnorePointer(
                        child: Row(
                          spacing: 10,
                          children: [
                            ClipOval(
                              child: Container(
                                width: 40,
                                height: 40,
                                color: Colors.black54,
                                child: SignalBuilder(
                                  builder: (context) {
                                    final showAnim = AppState.instance.showImageLoadAnimation.value;
                                    return LeafImage(
                                      image: KemonoImageProvider(iconUrl),
                                      fit: BoxFit.cover,
                                      cacheWidth: iconCacheSize,
                                      errorBuilder: (_, _, _) => Icon(Icons.person, color: Colors.white.withValues(alpha: 0.5), size: 24),
                                      revealAnimation: showAnim ? const GradientRevealAnimation() : null,
                                    );
                                  },
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                spacing: 4,
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    creator.name,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${creator.favorited} favorites',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                                  ),
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
                    SignalBuilder(
                      builder: (context) {
                        final isFav = AppState.instance.favoritedIds.value.contains('${creator.service}/${creator.id}');
                        return AnimatedFavoriteButton(
                          key: ValueKey('cht_${creator.service}_${creator.id}'),
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
                                await PawchiveClient.instance.favoriteCreator(service: creator.service, creatorId: creator.id);
                                AppState.instance.addFavoriteCreator(creator);
                              } else {
                                await PawchiveClient.instance.unfavoriteCreator(service: creator.service, creatorId: creator.id);
                                AppState.instance.removeFavoriteCreator(creator.service, creator.id);
                              }
                              return true;
                            } catch (e, st) {
                              debugPrint('Failed to toggle favorite: $e\n$st');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                              }
                              return false;
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          SignalBuilder(
            builder: (context) {
              final key = '${creator.service}/${creator.id}';
              final fc = AppState.instance.favoriteCreatorMap.value[key];
              if (fc == null) return SizedBox.shrink();
              DateTime? favDate;
              try {
                favDate = DateTime.parse(fc.updated);
              } catch (_) {
                return SizedBox.shrink();
              }
              final diff = DateTime.now().difference(favDate);
              final unixSec = favDate.millisecondsSinceEpoch ~/ 1000;
              return Positioned(
                top: 6,
                left: 6,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      border: Border(left: BorderSide(color: heatColorCorrect(diff), width: 3)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_timeAgo(unixSec), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                  ),
                ),
              );
            },
          ),
          SignalBuilder(
            builder: (context) {
              final hasNew = AppState.instance.creatorsWithNewPosts.value.contains('${creator.service}/${creator.id}');
              if (!hasNew) return SizedBox.shrink();
              return Positioned(top: 32, left: 8, child: IgnorePointer(child: AnimatedStar(size: 20)));
            },
          ),
          // Bottom accent strip for favorited creators.
          // Painted as BoxDecoration foreground so the bottom border respects
          // the rounded corners (via Border.paint + borderRadius).
          SignalBuilder(
            builder: (context) {
              final isFav = AppState.instance.favoritedIds.value.contains('${creator.service}/${creator.id}');
              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                top: 0,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 400),
                    curve: Curves.fastEaseInToSlowEaseOut,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border(bottom: isFav ? BorderSide(color: Colors.red, width: 3) : BorderSide.none),
                    ),
                  ),
                ),
              );
            },
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
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
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
                    spacing: 8,
                    children: [
                      Icon(Icons.storage, size: 16, color: Theme.of(context).colorScheme.outline),
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
                      separatorBuilder: (_, _) => const Divider(height: 1),
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

// ─────────────────────────────────────────────────────────────────────────────
// _MobileSortFilterContent
// ─────────────────────────────────────────────────────────────────────────────

class _MobileSortFilterContent extends StatelessWidget {
  _MobileSortFilterContent();

  final _app = AppState.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: cs.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text('Sort', style: text.labelSmall?.copyWith(color: cs.outline)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SignalBuilder(
                builder: (context) {
                  final isFavMode = _app.showFavoritesOnly.value;
                  return DropdownButton<SortBy>(
                    value: _app.sortBy.value,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(15),
                    elevation: 12,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    dropdownColor: cs.surfaceContainerHigh,
                    items: SortBy.values
                        .where((s) => s.isFavoritesSort == isFavMode)
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _app.sortBy.value = v;
                    },
                  );
                },
              ),
            ),
            SignalBuilder(
              builder: (context) {
                final asc = _app.sortAscending.value;
                return _FilterToggle(
                  icon: asc ? Icons.arrow_upward : Icons.arrow_downward,
                  label: asc ? 'Ascending' : 'Descending',
                  value: asc,
                  onChanged: (v) => _app.sortAscending.value = v,
                );
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Text('Filter', style: text.labelSmall?.copyWith(color: cs.outline)),
            ),
            SignalBuilder(
              builder: (context) {
                final active = _app.showCachedOnly.value;
                return _FilterToggle(
                  icon: Icons.storage,
                  label: 'Has cached files',
                  subtitle: 'Show only creators with cached images',
                  value: active,
                  onChanged: (v) => _app.showCachedOnly.value = v,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FilterPopoverContent
// ─────────────────────────────────────────────────────────────────────────────

class _FilterPopoverContent extends StatelessWidget {
  _FilterPopoverContent();

  final _app = AppState.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: cs.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text('Filter', style: text.labelSmall?.copyWith(color: cs.outline)),
            ),
            const Divider(height: 1),
            SignalBuilder(
              builder: (context) {
                final active = _app.showCachedOnly.value;
                return _FilterToggle(
                  icon: Icons.storage,
                  label: 'Has cached files',
                  subtitle: 'Show only creators with cached images',
                  value: active,
                  onChanged: (v) => _app.showCachedOnly.value = v,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FilterToggle({required this.icon, required this.label, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: text.bodyLarge?.copyWith(color: cs.onSurface)),
                  if (subtitle != null) Text(subtitle!, style: text.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 24,
              child: Switch(value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SettingsPopoverContent
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsPopoverContent extends StatelessWidget {
  _SettingsPopoverContent();

  final _app = AppState.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: cs.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text('Settings', style: text.labelSmall?.copyWith(color: cs.outline)),
            ),
            const Divider(height: 1),
            SignalBuilder(
              builder: (context) {
                final active = _app.showImageLoadAnimation.value;
                return _FilterToggle(
                  icon: Icons.animation,
                  label: 'Image reveal animation',
                  subtitle: 'Animated left-to-right reveal on thumbnails',
                  value: active,
                  onChanged: (v) => _app.setShowImageLoadAnimation(v),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AccountMenuContent
// ─────────────────────────────────────────────────────────────────────────────

class _AccountMenuContent extends StatelessWidget {
  _AccountMenuContent({required this.controller});

  final LeafPopoverController controller;
  final _app = AppState.instance;
  final _auth = AuthState.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;
    final username = _auth.username;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      initial,
                      style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(username, style: text.titleSmall?.copyWith(color: cs.onSurface)),
                        const SizedBox(height: 2),
                        SignalBuilder(
                          builder: (context) {
                            final count = _app.favoriteCreators.value.length;
                            return Text('$count followed', style: text.bodySmall?.copyWith(color: cs.outline));
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── Refresh ────────────────────────────────────────────────────────
            SignalBuilder(
              builder: (context) {
                final loading = _app.favoritesLoading.value;
                return _MenuRow(
                  icon: loading ? Icons.sync : Icons.sync,
                  label: loading ? 'Refreshing…' : 'Refresh favorites',
                  trailing: loading
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurfaceVariant))
                      : null,
                  onTap: loading ? null : () => _app.loadFavorites(),
                );
              },
            ),
            const Divider(height: 1),
            // ── Sign out ───────────────────────────────────────────────────────
            _MenuRow(
              icon: Icons.logout,
              label: 'Sign out',
              color: cs.error,
              onTap: () {
                _auth.logout();
                controller.hide();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MenuRow — simple icon + label tappable row
// ─────────────────────────────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _MenuRow({required this.icon, required this.label, this.color, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = color ?? cs.onSurface;
    final opacity = onTap == null ? 0.5 : 1.0;

    return Opacity(
      opacity: opacity,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: text.bodyLarge?.copyWith(color: fg)),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
