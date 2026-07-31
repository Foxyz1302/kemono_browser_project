import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signals/signals_flutter.dart';

import '../api/models.dart';
import '../api/pawchive_client.dart';
import '../cache/image_meta_store.dart';

enum SortBy {
  // All-creators sorts
  favorited,
  indexed,
  updated,
  name,
  service,
  cacheSize,
  // Favorites-only sorts
  favUpdated,
  favLastImported,
}

extension SortByLabel on SortBy {
  String get label => switch (this) {
        SortBy.favorited => 'Popularity',
        SortBy.indexed => 'Date Indexed',
        SortBy.updated => 'Date Updated',
        SortBy.name => 'Alphabetical',
        SortBy.service => 'Service',
        SortBy.cacheSize => 'Cache Size',
        SortBy.favUpdated => 'New Post Date',
        SortBy.favLastImported => 'Reimported Date',
      };

  bool get isFavoritesSort => switch (this) {
        SortBy.favUpdated || SortBy.favLastImported => true,
        _ => false,
      };
}

class AppState {
  static final AppState instance = AppState._();
  AppState._();

  late final Box _settingsBox;

  final creators = signal<List<Creator>>([]);
  final creatorsLoading = signal<bool>(false);
  final creatorsError = signal<String?>(null);
  final searchQuery = signal<String>('');
  final sortBy = signal<SortBy>(SortBy.updated);
  final sortAscending = signal<bool>(false);
  final activeTab = signal<int>(0);
  final showCachedOnly = signal<bool>(false);
  final showFavoritesOnly = signal<bool>(false);
  final showImageLoadAnimation = signal<bool>(true);

  // ── Favorites ────────────────────────────────────────────────────────────
  final favoriteCreators = signal<List<FavoriteCreator>>([]);

  /// Set of "service/id" strings for O(1) lookup in CreatorTile.
  late final favoritedIds = computed<Set<String>>(() {
    return favoriteCreators.value.map((fc) => '${fc.service}/${fc.id}').toSet();
  });

  /// Map of "service/id" → [FavoriteCreator] for quick access to the actual
  /// content-update timestamp.
  late final favoriteCreatorMap = computed<Map<String, FavoriteCreator>>(() {
    final map = <String, FavoriteCreator>{};
    for (final fc in favoriteCreators.value) {
      map['${fc.service}/${fc.id}'] = fc;
    }
    return map;
  });

  /// lastChecked tracking for new-post detection.
  ///
  /// Persisted as a flat JSON map: { "service/id": "ISO-8601" }.
  /// [_lastCheckedSignal] is bumped on every write so reactive UI can watch it.
  Map<String, String> _lastChecked = {};
  final _lastCheckedSignal = signal<int>(0);
  Timer? _lastCheckedSaveTimer;

  /// Set of "service/id" keys for creators whose [FavoriteCreator.updated] is
  /// newer than the local [lastChecked] timestamp.
  late final creatorsWithNewPosts = computed<Set<String>>(() {
    // Read both dependencies so this re-evaluates when either changes.
    final favs = favoriteCreators.value;
    _lastCheckedSignal.value; // depend on last-checked mutations
    if (favs.isEmpty) return {};
    final result = <String>{};
    for (final fc in favs) {
      final key = '${fc.service}/${fc.id}';
      final last = _lastChecked[key];
      if (last == null) {
        // Never checked — don't show "new" until first visit.
        continue;
      }
      try {
        if (DateTime.parse(fc.updated).isAfter(DateTime.parse(last))) {
          result.add(key);
        }
      } catch (_) {
        // Malformed date string; skip.
      }
    }
    return result;
  });

  void init(Box settingsBox) {
    _settingsBox = settingsBox;
    showImageLoadAnimation.value =
        _settingsBox.get('showImageLoadAnimation', defaultValue: true) as bool;
    _initSortModeEffect();
  }

  void setShowImageLoadAnimation(bool v) {
    showImageLoadAnimation.value = v;
    _settingsBox.put('showImageLoadAnimation', v);
  }

  /// Watch [showFavoritesOnly] and auto-switch [sortBy] between the
  /// all-creators and favorites-only sort sets.
  void _initSortModeEffect() {
    effect(() {
      if (showFavoritesOnly.value) {
        if (!sortBy.peek().isFavoritesSort) {
          sortBy.value = SortBy.favUpdated;
        }
      } else {
        if (sortBy.peek().isFavoritesSort) {
          sortBy.value = SortBy.updated;
        }
      }
    });
  }

  late final filteredCreators = computed<List<Creator>>(() {
    var list = creators.value;
    final query = searchQuery.value.toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((c) => c.name.toLowerCase().contains(query)).toList();
    }
    if (showCachedOnly.value) {
      final hasCache = <String>{};
      for (final m in ImageMetaStore.instance.allEntries.values) {
        if (m.creatorId != null) hasCache.add(m.creatorId!);
      }
      list = list.where((c) => hasCache.contains(c.id)).toList();
    }
    if (showFavoritesOnly.value) {
      final favSet = favoritedIds.value;
      list = list.where((c) => favSet.contains('${c.service}/${c.id}')).toList();
    }
    final favMap = favoriteCreatorMap.value;
    final needsCacheSort = sortBy.value == SortBy.cacheSize;
    final cacheBytes = needsCacheSort ? <String, int>{} : null;
    if (needsCacheSort) {
      for (final m in ImageMetaStore.instance.allEntries.values) {
        if (m.creatorId != null) {
          cacheBytes![m.creatorId!] = (cacheBytes[m.creatorId!] ?? 0) + m.bytes;
        }
      }
    }
    list = List.from(list)..sort((a, b) {
      int cmp = switch (sortBy.value) {
        SortBy.updated => b.updated.compareTo(a.updated),
        SortBy.favorited => b.favorited.compareTo(a.favorited),
        SortBy.indexed => b.indexed.compareTo(a.indexed),
        SortBy.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortBy.service => a.service.compareTo(b.service),
        SortBy.cacheSize => (cacheBytes![b.id] ?? 0).compareTo(cacheBytes[a.id] ?? 0),
        SortBy.favUpdated => () {
          int millis(Creator c) {
            final fc = favMap['${c.service}/${c.id}'];
            if (fc != null) {
              try {
                return DateTime.parse(fc.updated).millisecondsSinceEpoch;
              } catch (_) {}
            }
            return 0; // no post date → sort to bottom
          }
          return millis(b).compareTo(millis(a));
        }(),
        SortBy.favLastImported => () {
          int millis(Creator c) {
            final fc = favMap['${c.service}/${c.id}'];
            if (fc?.lastImported != null) {
              try {
                return DateTime.parse(fc!.lastImported!).millisecondsSinceEpoch;
              } catch (_) {}
            }
            return 0; // no import date → sort to bottom
          }
          return millis(b).compareTo(millis(a));
        }(),
      };
      return sortAscending.value ? -cmp : cmp;
    });
    return list;
  });

  Future<void> loadCreators({bool refresh = false}) async {
    if (creatorsLoading.peek()) return;
    creatorsLoading.value = true;
    creatorsError.value = null;
    try {
      if (refresh) creators.value = [];
      final client = PawchiveClient.instance;
      debugPrint('Loading creators...');
      final all = await client.getCreators();
      debugPrint('Got ${all.length} creators');
      creators.value = all;
    } catch (e, st) {
      debugPrint('Failed to load creators: $e\n$st');
      creatorsError.value = '$e';
    } finally {
      creatorsLoading.value = false;
    }
  }

  /// Fetch posts for a creator from the API.
  /// The caller owns the returned list — no global state is written.
  Future<List<Post>> fetchCreatorPosts(Creator creator) async {
    final client = PawchiveClient.instance;
    return client.getCreatorPosts(
      service: creator.service,
      creatorId: creator.id,
    );
  }

  // ── Favorites management ─────────────────────────────────────────────────

  final favoritesLoading = signal<bool>(false);

  /// Favorite post IDs: "service/creatorId/postId" set.
  final favoritePostIds = signal<Set<String>>({});

  /// Fetch favorite creators from the API and update the signal.
  /// Safe to call regardless of auth state — sets empty on error.
  Future<void> loadFavorites() async {
    if (favoritesLoading.peek()) return;
    favoritesLoading.value = true;
    try {
      final client = PawchiveClient.instance;
      final favs = await client.getFavoriteCreators();
      favoriteCreators.value = favs;
      debugPrint('Loaded ${favs.length} favorite creators');

      // Also load favorited posts
      final postFavs = await client.getFavoritePosts();
      favoritePostIds.value =
          postFavs.map((p) => '${p.service}/${p.user}/${p.id}').toSet();
      debugPrint('Loaded ${postFavs.length} favorite posts');
    } catch (e, st) {
      debugPrint('Failed to load favorites: $e\n$st');
      favoriteCreators.value = [];
      favoritePostIds.value = {};
    } finally {
      favoritesLoading.value = false;
    }
  }

  /// Add a creator to favorites locally after the API call succeeds.
  void addFavoriteCreator(Creator creator) {
    final fc = FavoriteCreator(
      id: creator.id,
      name: creator.name,
      service: creator.service,
      updated: DateTime.fromMillisecondsSinceEpoch(creator.updated * 1000).toUtc().toIso8601String(),
      everImported: creator.everImported,
      kemonoFavorited: creator.favorited,
    );
    favoriteCreators.value = [fc, ...favoriteCreators.peek()];
  }

  /// Remove a creator from favorites locally after the API call succeeds.
  void removeFavoriteCreator(String service, String id) {
    favoriteCreators.value = favoriteCreators.peek()
        .where((fc) => !(fc.service == service && fc.id == id))
        .toList();
  }

  /// Add a post to favorites locally (key: "service/creatorId/postId").
  void addFavoritePost(String service, String creatorId, String postId) {
    final key = '$service/$creatorId/$postId';
    final updated = Set<String>.from(favoritePostIds.peek())..add(key);
    favoritePostIds.value = updated;
  }

  /// Remove a post from favorites locally.
  void removeFavoritePost(String service, String creatorId, String postId) {
    final key = '$service/$creatorId/$postId';
    final updated = Set<String>.from(favoritePostIds.peek())..remove(key);
    favoritePostIds.value = updated;
  }

  /// Reset favorites state on logout.
  void clearFavorites() {
    favoriteCreators.value = [];
    _lastChecked = {};
    _lastCheckedSignal.value++;
  }

  String _lastCheckedKey(String service, String id) => '$service/$id';

  /// Returns the last-checked ISO timestamp for [creatorId], or null if the
  /// creator has never been viewed.
  String? getLastChecked(String service, String creatorId) {
    return _lastChecked[_lastCheckedKey(service, creatorId)];
  }

  /// Record that the user has viewed [creatorId]'s content now.
  void updateLastChecked(String service, String creatorId) {
    final key = _lastCheckedKey(service, creatorId);
    _lastChecked[key] = DateTime.now().toUtc().toIso8601String();
    _lastCheckedSignal.value++; // triggers reactive deps
    _scheduleSaveLastChecked();
  }

  // ── lastChecked persistence ──────────────────────────────────────────────

  String? _lastCheckedFilePath;

  Future<String> get _lastCheckedPath async {
    if (_lastCheckedFilePath == null) {
      final dir = await getApplicationDocumentsDirectory();
      _lastCheckedFilePath = '${dir.path}/last_checked.json';
    }
    return _lastCheckedFilePath!;
  }

  Future<void> loadLastChecked() async {
    try {
      final path = await _lastCheckedPath;
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = json.decode(content) as Map<String, dynamic>;
        _lastChecked = decoded.map((k, v) => MapEntry(k, v as String));
        _lastCheckedSignal.value++;
        debugPrint('Loaded ${_lastChecked.length} lastChecked entries');
      }
    } catch (e, st) {
      debugPrint('Failed to load lastChecked: $e\n$st');
      _lastChecked = {};
    }
  }

  void _scheduleSaveLastChecked() {
    _lastCheckedSaveTimer?.cancel();
    _lastCheckedSaveTimer = Timer(const Duration(seconds: 2), () {
      _saveLastChecked();
    });
  }

  Future<void> _saveLastChecked() async {
    try {
      final path = await _lastCheckedPath;
      final file = File(path);
      await file.writeAsString(json.encode(_lastChecked));
    } catch (e, st) {
      debugPrint('Failed to save lastChecked: $e\n$st');
    }
  }
}
