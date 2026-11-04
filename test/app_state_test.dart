import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/state/app_state.dart';
import 'package:kemono_browser_project/src/state/creator_sort_service.dart';

Creator _creator(
  String id, {
  String name = '',
  String service = 'patreon',
  int updated = 0,
  int favorited = 0,
}) =>
    Creator(
      id: id,
      name: name.isEmpty ? id : name,
      service: service,
      updated: updated,
      favorited: favorited,
      indexed: 0,
      everImported: true,
    );

FavoriteCreator _fav(
  String service,
  String id, {
  String? updated,
}) =>
    FavoriteCreator(
      id: id,
      name: id,
      service: service,
      updated: updated ?? '2026-01-01T00:00:00Z',
      everImported: true,
      lastImported: null,
      kemonoFavorited: 0,
    );

void main() {
  final app = AppState.instance;

  setUp(() {
    app.init(null);
    app.creators.value = [];
    app.filteredCreators.value = [];
    app.favoriteCreators.value = [];
    app.searchQuery.value = '';
    app.sortBy.value = SortBy.updated;
    app.sortAscending.value = false;
    app.showCachedOnly.value = false;
    app.showFavoritesOnly.value = false;
  });

  tearDown(() {
    CreatorSortService.instance.restart();
  });

  Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Timed out waiting for condition');
  }

  test('populates filteredCreators from the worker after load', () async {
    app.creators.value = [
      _creator('a', updated: 100),
      _creator('b', updated: 300),
      _creator('c', updated: 200),
    ];
    await waitFor(() => app.filteredCreators.value.length == 3);
    expect(app.filteredCreators.value.map((c) => c.id), ['b', 'c', 'a']);
    expect(app.filtering.value, isFalse);
  });

  test('favorites-only toggle filters to favorited creators', () async {
    app.creators.value = [
      _creator('a', service: 'patreon', updated: 100),
      _creator('b', service: 'fanbox', updated: 300),
      _creator('c', service: 'patreon', updated: 200),
    ];
    await waitFor(() => app.filteredCreators.value.length == 3);
    app.favoriteCreators.value = [
      _fav('fanbox', 'b', updated: '2026-07-01T00:00:00Z'),
    ];
    app.showFavoritesOnly.value = true;
    await waitFor(() => app.filteredCreators.value.length == 1);
    expect(app.filteredCreators.value.map((c) => c.id), ['b']);
  });

  test('changing sort reorders through the worker', () async {
    app.creators.value = [
      _creator('a', updated: 300, favorited: 10),
      _creator('b', updated: 100, favorited: 500),
      _creator('c', updated: 200, favorited: 200),
    ];
    await waitFor(() => app.filteredCreators.value.length == 3);
    expect(app.filteredCreators.value.map((c) => c.id), ['a', 'c', 'b']);
    app.sortBy.value = SortBy.favorited;
    await waitFor(() => app.filteredCreators.value.first.id == 'b');
    expect(app.filteredCreators.value.map((c) => c.id), ['b', 'c', 'a']);
  });

  test('query filters through the worker', () async {
    app.creators.value = [
      _creator('a', name: 'Alice', updated: 300),
      _creator('b', name: 'bob', updated: 100),
      _creator('c', name: 'ALICE-2', updated: 200),
    ];
    await waitFor(() => app.filteredCreators.value.length == 3);
    app.searchQuery.value = 'ali';
    app.onSearchTrigger('ali');
    await waitFor(() => app.filteredCreators.value.length == 2);
    expect(app.filteredCreators.value.map((c) => c.id), ['a', 'c']);
    app.searchQuery.value = '';
    app.onSearchTrigger('');
    await waitFor(() => app.filteredCreators.value.length == 3);
  });

  test('sortAscending reverses the worker order', () async {
    app.creators.value = [
      _creator('a', updated: 100),
      _creator('b', updated: 300),
      _creator('c', updated: 200),
    ];
    await waitFor(() => app.filteredCreators.value.length == 3);
    app.sortAscending.value = true;
    await waitFor(() => app.filteredCreators.value.first.id == 'a');
    expect(app.filteredCreators.value.map((c) => c.id), ['a', 'c', 'b']);
  });

  test('filtering flag settles to false after the worker replies', () async {
    expect(app.filtering.value, isFalse);
    app.creators.value = [_creator('a', updated: 1)];
    await waitFor(() => app.filteredCreators.value.length == 1);
    expect(app.filteredCreators.value.map((c) => c.id), ['a']);
    expect(app.filtering.value, isFalse);
  });
}
