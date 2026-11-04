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
import 'creator_alias_index.dart';
import 'creator_sort_service.dart';

export 'creator_sort_service.dart' show SortBy, SortByLabel;

class AppState {
  static final AppState instance = AppState._();
  AppState._();

  Box? _settingsBox;

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

  void init(Box? settingsBox) {
    _settingsBox = settingsBox;
    showImageLoadAnimation.value = (settingsBox?.get('showImageLoadAnimation', defaultValue: true) as bool?) ?? true;
    if (!_effectsReady) {
      _effectsReady = true;
      _initSortModeEffect();
      _initCreatorSortEffect();
    }
  }

  void setShowImageLoadAnimation(bool v) {
    showImageLoadAnimation.value = v;
    _settingsBox?.put('showImageLoadAnimation', v);
  }

  /// Saved video player volume (0–100), restored on every new player.
  double getPlayerVolume() {
    return (_settingsBox?.get('player-volume', defaultValue: 100.0) as num?)?.toDouble() ?? 100.0;
  }

  /// Persist the current player volume so the next video resumes at it.
  void setPlayerVolume(double volume) {
    _settingsBox?.put('player-volume', volume);
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

  // ── Creator sort pipeline (worker isolate) ────────────────────────────────
  // Filtering and sorting the 89K index runs in a long-lived worker isolate
  // (CreatorSortService) so the UI thread never blocks on it. An effect
  // watches the sort/filter inputs, sends a request, and applies the returned
  // index order to [filteredCreators]. Stale replies are discarded via the
  // request-id + base-identity guards.

  final filteredCreators = signal<List<Creator>>([]);
  final filtering = signal<bool>(false);

  final _sortService = CreatorSortService.instance;
  List<Creator>? _sentBase;
  List<FavoriteCreator>? _sentFavs;
  CreatorAliasIndex? _aliasIndex;
  List<List<String>> _creatorExtras = const [];
  int _workerGen = 0;
  int _lastReqId = 0;
  List<Creator>? _reqBase;
  bool _dirty = false;
  bool _inFlight = false;
  bool _effectsReady = false;

  void _initCreatorSortEffect() {
    effect(() {
      creators.value; // keep
      // searchQuery.value;    // <-- REMOVE this line
      sortBy.value;
      sortAscending.value;
      favoriteCreators.value;
      showCachedOnly.value;
      showFavoritesOnly.value;
      _dirty = true;
      _pump();
    });
  }

  Map<String, int> _cacheBytesSnapshot() {
    final map = <String, int>{};
    for (final m in ImageMetaStore.instance.allEntries.values) {
      if (m.creatorId != null) {
        map[m.creatorId!] = (map[m.creatorId!] ?? 0) + m.bytes;
      }
    }
    return map;
  }

  void onSearchTrigger(String text) {
    // The searchQuery signal already has the latest value (updated by SearchBar on every keystroke).
    // We just need to signal the pipeline to run.
    _dirty = true;
    _pump();
  }

  Future<void> _pump() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final all = creators.value;
      if (!identical(_sentBase, all)) {
        _workerGen++;
        await _sortService.setBase(_workerGen, all, extraKeys: _creatorExtras);
        _sentBase = all;
      }
      final favs = favoriteCreators.value;
      if (!identical(_sentFavs, favs)) {
        await _sortService.setFavs(favs);
        _sentFavs = favs;
      }
      final reqId = ++_lastReqId;
      _reqBase = all;
      _dirty = false;
      filtering.value = true;
      try {
        final order = await _sortService.request(
          reqId: reqId,
          gen: _workerGen,
          query: CreatorAliasIndex.normalizeQuery(searchQuery.value),
          sortBy: sortBy.value,
          ascending: sortAscending.value,
          favoritesOnly: showFavoritesOnly.value,
          cachedOnly: showCachedOnly.value,
          cacheBytes: showCachedOnly.value || sortBy.value == SortBy.cacheSize ? _cacheBytesSnapshot() : null,
        );
        if (reqId == _lastReqId && identical(_reqBase, creators.value)) {
          final current = creators.value;
          filteredCreators.value = [for (final i in order) current[i]];
        } else {
          // Inputs changed while the request was in flight — the reply is
          // stale. Re-pump so a fresh request carries the current state.
          _dirty = true;
        }
      } finally {
        if (reqId == _lastReqId) filtering.value = false;
      }
    } catch (e, st) {
      debugPrint('Creator sort pipeline failed: $e\n$st');
      _sortService.restart();
      _sentBase = null;
      _sentFavs = null;
      filtering.value = false;
      _dirty = true;
    } finally {
      _inFlight = false;
      if (_dirty) _pump();
    }
  }

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
      try {
        _aliasIndex ??= await CreatorAliasIndex.loadFromAsset();
        _creatorExtras = [for (final c in all) _aliasIndex!.extrasFor(c.service, c.id)];
      } catch (e, st) {
        debugPrint('Alias index unavailable: $e\n$st');
        _creatorExtras = const [];
      }
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
    return client.getCreatorPosts(service: creator.service, creatorId: creator.id);
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
      favoritePostIds.value = postFavs.map((p) => '${p.service}/${p.user}/${p.id}').toSet();
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
    favoriteCreators.value = favoriteCreators.peek().where((fc) => !(fc.service == service && fc.id == id)).toList();
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
