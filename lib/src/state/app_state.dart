import 'package:flutter/foundation.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../api/models.dart';
import '../api/pawchive_client.dart';

enum SortBy { updated, favorited, indexed, name, service }

extension SortByLabel on SortBy {
  String get label => switch (this) {
        SortBy.updated => 'Date Updated',
        SortBy.favorited => 'Popularity',
        SortBy.indexed => 'Date Indexed',
        SortBy.name => 'Alphabetical',
        SortBy.service => 'Service',
      };
}

class AppState {
  static final AppState instance = AppState._();
  AppState._();

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

  List<Creator> get filteredCreators {
    var list = creators.value;
    final query = searchQuery.value.toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((c) => c.name.toLowerCase().contains(query)).toList();
    }
    list = List.from(list)..sort((a, b) {
      int cmp = switch (sortBy.value) {
        SortBy.updated => b.updated.compareTo(a.updated),
        SortBy.favorited => b.favorited.compareTo(a.favorited),
        SortBy.indexed => b.indexed.compareTo(a.indexed),
        SortBy.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortBy.service => a.service.compareTo(b.service),
      };
      return sortAscending.value ? -cmp : cmp;
    });
    return list;
  }

  Future<void> loadCreators({bool refresh = false}) async {
    if (creatorsLoading.value) return;
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
