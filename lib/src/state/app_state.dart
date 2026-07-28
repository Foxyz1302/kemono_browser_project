import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:signals/signals_flutter.dart';

import '../api/models.dart';
import '../api/pawchive_client.dart';
import '../cache/image_meta_store.dart';

enum SortBy { updated, favorited, indexed, name, service, cacheSize }

extension SortByLabel on SortBy {
  String get label => switch (this) {
        SortBy.updated => 'Date Updated',
        SortBy.favorited => 'Popularity',
        SortBy.indexed => 'Date Indexed',
        SortBy.name => 'Alphabetical',
        SortBy.service => 'Service',
        SortBy.cacheSize => 'Cache Size',
      };
}

class AppState {
  static final AppState instance = AppState._();
  AppState._();

  late final Box _settingsBox;

  final creators = signal<List<Creator>>([]);
  final creatorsLoading = signal<bool>(false);
  final creatorsError = signal<String?>(null);
  final selectedCreator = signal<Creator?>(null);
  final creatorPosts = signal<List<Post>>([]);
  final creatorPostsLoading = signal<bool>(false);
  final searchQuery = signal<String>('');
  final sortBy = signal<SortBy>(SortBy.updated);
  final sortAscending = signal<bool>(false);
  final activeTab = signal<int>(0);
  final showCachedOnly = signal<bool>(false);
  final showImageLoadAnimation = signal<bool>(true);

  void init(Box settingsBox) {
    _settingsBox = settingsBox;
    showImageLoadAnimation.value =
        _settingsBox.get('showImageLoadAnimation', defaultValue: true) as bool;
  }

  void setShowImageLoadAnimation(bool v) {
    showImageLoadAnimation.value = v;
    _settingsBox.put('showImageLoadAnimation', v);
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

  Future<void> loadCreatorPosts(Creator creator) async {
    selectedCreator.value = creator;
    creatorPostsLoading.value = true;
    try {
      final client = PawchiveClient.instance;
      final posts = await client.getCreatorPosts(
        service: creator.service,
        creatorId: creator.id,
      );
      creatorPosts.value = posts;
    } catch (e, st) {
      debugPrint('Failed to load creator posts: $e\n$st');
      creatorPosts.value = [];
    } finally {
      creatorPostsLoading.value = false;
    }
  }
}
