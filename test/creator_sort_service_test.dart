import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/state/creator_sort_service.dart';

Creator _creator(
  String id, {
  String name = '',
  String service = 'patreon',
  int updated = 0,
  int favorited = 0,
  int indexed = 0,
  bool everImported = true,
}) =>
    Creator(
      id: id,
      name: name.isEmpty ? id : name,
      service: service,
      updated: updated,
      favorited: favorited,
      indexed: indexed,
      everImported: everImported,
    );

FavoriteCreator _fav(
  String service,
  String id, {
  String? updated,
  String? lastImported,
}) =>
    FavoriteCreator(
      id: id,
      name: id,
      service: service,
      updated: updated ?? '2026-01-01T00:00:00Z',
      everImported: true,
      lastImported: lastImported,
      kemonoFavorited: 0,
    );

/// Builds the parallel arrays [computeFilteredOrder] expects from a list of
/// [Creator] objects, mirroring what the service sends to the worker.
class _Harness {
  final List<Creator> creators;
  late final List<String> ids = [for (final c in creators) c.id];
  late final List<String> names = [for (final c in creators) c.name];
  late final List<String> services = [for (final c in creators) c.service];
  late final List<int> updated = [for (final c in creators) c.updated];
  late final List<int> favorited = [for (final c in creators) c.favorited];
  late final List<int> indexed = [for (final c in creators) c.indexed];
  late final ({List<String> namesLower, List<String> keys}) base =
      prepareSortKeys(ids: ids, names: names, services: services);

  _Harness(this.creators);

  List<int> order({
    String query = '',
    SortBy sortBy = SortBy.updated,
    bool ascending = false,
    bool favoritesOnly = false,
    List<FavoriteCreator> favs = const [],
    bool cachedOnly = false,
    Map<String, int> cacheBytes = const {},
    List<List<String>> extraKeys = const [],
  }) =>
      computeFilteredOrder(
        ids: ids,
        namesLower: base.namesLower,
        services: services,
        keys: base.keys,
        updated: updated,
        favorited: favorited,
        indexed: indexed,
        query: query,
        sortBy: sortBy,
        ascending: ascending,
        favoritesOnly: favoritesOnly,
        favKeys: [for (final f in favs) '${f.service}/${f.id}'],
        favUpdatedMillis: {
          for (final f in favs)
            '${f.service}/${f.id}': DateTime.tryParse(f.updated)?.millisecondsSinceEpoch ?? 0,
        },
        favImportedMillis: {
          for (final f in favs)
            '${f.service}/${f.id}': f.lastImported == null
                ? 0
                : DateTime.tryParse(f.lastImported!)?.millisecondsSinceEpoch ?? 0,
        },
        cachedOnly: cachedOnly,
        cacheBytes: cacheBytes,
        extraKeys: extraKeys,
      );

  List<String> idsOf(List<int> order) => [for (final i in order) ids[i]];
}

void main() {
  group('prepareSortKeys', () {
    test('lowercases names and builds service/id keys', () {
      final base = prepareSortKeys(
        ids: ['1', '2'],
        names: ['Alice', 'BOB'],
        services: ['patreon', 'fanbox'],
      );
      expect(base.namesLower, ['alice', 'bob']);
      expect(base.keys, ['patreon/1', 'fanbox/2']);
    });
  });

  group('sorts', () {
    test('sorts by updated descending by default', () {
      final h = _Harness([
        _creator('a', updated: 100),
        _creator('b', updated: 300),
        _creator('c', updated: 200),
      ]);
      expect(h.idsOf(h.order()), ['b', 'c', 'a']);
    });

    test('ascending reverses order', () {
      final h = _Harness([
        _creator('a', updated: 100),
        _creator('b', updated: 300),
        _creator('c', updated: 200),
      ]);
      expect(h.idsOf(h.order(ascending: true)), ['a', 'c', 'b']);
    });

    test('sorts by name case-insensitively', () {
      final h = _Harness([
        _creator('a', name: 'Zebra'),
        _creator('b', name: 'apple'),
        _creator('c', name: 'Mango'),
      ]);
      expect(h.idsOf(h.order(sortBy: SortBy.name)), ['b', 'c', 'a']);
      expect(h.idsOf(h.order(sortBy: SortBy.name, ascending: true)), ['a', 'c', 'b']);
    });

    test('sorts by favorited count descending', () {
      final h = _Harness([
        _creator('a', favorited: 10),
        _creator('b', favorited: 500),
        _creator('c', favorited: 200),
      ]);
      expect(h.idsOf(h.order(sortBy: SortBy.favorited)), ['b', 'c', 'a']);
    });

    test('sorts by service', () {
      final h = _Harness([
        _creator('a', service: 'fanbox'),
        _creator('b', service: 'patreon'),
        _creator('c', service: 'afdian'),
      ]);
      expect(h.idsOf(h.order(sortBy: SortBy.service)), ['c', 'a', 'b']);
    });

    test('cacheSize sorts by cached bytes, missing entries last', () {
      final h = _Harness([_creator('a'), _creator('b'), _creator('c')]);
      final order = h.order(
        sortBy: SortBy.cacheSize,
        cacheBytes: {'b': 300, 'a': 100},
      );
      expect(h.idsOf(order), ['b', 'a', 'c']);
    });

    test('favUpdated sorts by FavoriteCreator.updated, not Creator.updated', () {
      final h = _Harness([
        _creator('a', service: 'patreon', updated: 500),
        _creator('b', service: 'patreon', updated: 100),
      ]);
      final order = h.order(
        sortBy: SortBy.favUpdated,
        favoritesOnly: true,
        favs: [
          _fav('patreon', 'a', updated: '2026-01-01T00:00:00Z'),
          _fav('patreon', 'b', updated: '2026-07-01T00:00:00Z'),
        ],
      );
      expect(h.idsOf(order), ['b', 'a']);
    });

    test('missing or malformed favorite dates sort to bottom', () {
      final h = _Harness([
        _creator('a', service: 'patreon'),
        _creator('b', service: 'patreon'),
        _creator('c', service: 'patreon'),
      ]);
      final order = h.order(
        sortBy: SortBy.favUpdated,
        favoritesOnly: true,
        favs: [
          _fav('patreon', 'c', updated: 'not-a-date'),
          _fav('patreon', 'b', updated: '2026-06-01T00:00:00Z'),
          _fav('patreon', 'a', updated: '2026-03-01T00:00:00Z'),
        ],
      );
      expect(h.idsOf(order), ['b', 'a', 'c']);
    });

    test('favLastImported sorts by import date, missing dates to bottom', () {
      final h = _Harness([
        _creator('a', service: 'patreon'),
        _creator('b', service: 'patreon'),
      ]);
      final order = h.order(
        sortBy: SortBy.favLastImported,
        favoritesOnly: true,
        favs: [
          _fav('patreon', 'a'),
          _fav('patreon', 'b', lastImported: '2026-09-01T00:00:00Z'),
        ],
      );
      expect(h.idsOf(order), ['b', 'a']);
    });
  });

  group('filters', () {
    test('filters by query case-insensitively', () {
      final h = _Harness([
        _creator('a', name: 'Alice', updated: 300),
        _creator('b', name: 'bob', updated: 100),
        _creator('c', name: 'ALICE-2', updated: 200),
      ]);
      expect(h.idsOf(h.order(query: 'ali')), ['a', 'c']);
    });

    test('favorites-only shows only favorited creators', () {
      final h = _Harness([
        _creator('a', service: 'patreon', updated: 100),
        _creator('b', service: 'fanbox', updated: 300),
        _creator('c', service: 'patreon', updated: 200),
      ]);
      final order = h.order(favoritesOnly: true, favs: [_fav('fanbox', 'b')]);
      expect(h.idsOf(order), ['b']);
    });

    test('cached-only keeps only creators present in cacheBytes', () {
      final h = _Harness([_creator('a'), _creator('b'), _creator('c')]);
      final order = h.order(cachedOnly: true, cacheBytes: {'a': 10, 'c': 20});
      expect(h.idsOf(order), ['a', 'c']);
    });

    test('combines query, favorites-only and cached-only', () {
      final h = _Harness([
        _creator('a', name: 'Alice', service: 'patreon', updated: 300),
        _creator('b', name: 'bob', service: 'fanbox', updated: 100),
        _creator('c', name: 'Alpine', service: 'patreon', updated: 200),
      ]);
      final order = h.order(
        query: 'al',
        favoritesOnly: true,
        cachedOnly: true,
        favs: [_fav('patreon', 'a'), _fav('patreon', 'c')],
        cacheBytes: {'c': 5},
      );
      expect(h.idsOf(order), ['c']);
    });

    test('matches extra alias keys', () {
      final h = _Harness([
        _creator('a', name: 'じょぶじゅん', updated: 300),
        _creator('b', name: 'Other', updated: 100),
      ]);
      final order = h.order(
        query: 'jovejun',
        extraKeys: [
          ['jovejun', 'jun81jun'],
          const [],
        ],
      );
      expect(h.idsOf(order), ['a']);
    });

    test('long keys match in both directions (pasted full lines)', () {
      final h = _Harness([
        _creator('a', name: 'Other', updated: 300),
        _creator('b', name: 'Other2', updated: 100),
      ]);
      final order = h.order(
        query: 'じょぶじゅん。jovejun＠c108_二日目_東ウ-27ab@jovejun',
        extraKeys: [
          const [],
          ['jovejun'],
        ],
      );
      expect(h.idsOf(order), ['b']);
    });

    test('short keys only match forward to avoid noise', () {
      final h = _Harness([
        _creator('a', name: 'X', updated: 300),
        _creator('b', name: 'Y', updated: 100),
      ]);
      final order = h.order(
        query: 'xyxy',
        extraKeys: [
          const [],
          ['xy'],
        ],
      );
      expect(h.idsOf(order), isEmpty);
    });
  });

  group('CreatorSortService (real worker isolate)', () {
    setUp(() {
      CreatorSortService.instance.restart();
    });

    tearDown(() {
      CreatorSortService.instance.restart();
    });

    test('round-trips sorted order through the isolate', () async {
      final service = CreatorSortService.instance;
      final cs = [
        _creator('a', service: 'patreon', updated: 100, favorited: 10),
        _creator('b', service: 'fanbox', updated: 300, favorited: 500),
        _creator('c', service: 'patreon', updated: 200, favorited: 200),
      ];
      await service.setBase(1, cs);
      await service.setFavs([_fav('fanbox', 'b', updated: '2026-07-01T00:00:00Z')]);

      final byUpdated = await service.request(
        reqId: 1,
        gen: 1,
        query: '',
        sortBy: SortBy.updated,
        ascending: false,
        favoritesOnly: false,
        cachedOnly: false,
      );
      expect([for (final i in byUpdated) cs[i].id], ['b', 'c', 'a']);

      final byFavorited = await service.request(
        reqId: 2,
        gen: 1,
        query: '',
        sortBy: SortBy.favorited,
        ascending: false,
        favoritesOnly: false,
        cachedOnly: false,
      );
      expect([for (final i in byFavorited) cs[i].id], ['b', 'c', 'a']);

      final favOnly = await service.request(
        reqId: 3,
        gen: 1,
        query: '',
        sortBy: SortBy.favUpdated,
        ascending: false,
        favoritesOnly: true,
        cachedOnly: false,
      );
      expect([for (final i in favOnly) cs[i].id], ['b']);
    });

    test('filters by query and cache bytes through the isolate', () async {
      final service = CreatorSortService.instance;
      final cs = [
        _creator('a', name: 'Alice', updated: 300),
        _creator('b', name: 'bob', updated: 100),
        _creator('c', name: 'ALICE-2', updated: 200),
      ];
      await service.setBase(1, cs);

      final query = await service.request(
        reqId: 1,
        gen: 1,
        query: 'ali',
        sortBy: SortBy.updated,
        ascending: false,
        favoritesOnly: false,
        cachedOnly: false,
      );
      expect([for (final i in query) cs[i].id], ['a', 'c']);

      final cached = await service.request(
        reqId: 2,
        gen: 1,
        query: '',
        sortBy: SortBy.cacheSize,
        ascending: false,
        favoritesOnly: false,
        cachedOnly: false,
        cacheBytes: {'a': 100, 'b': 200},
      );
      expect([for (final i in cached) cs[i].id], ['b', 'a', 'c']);
    });

    test('replies empty when request gen does not match base gen', () async {
      final service = CreatorSortService.instance;
      await service.setBase(7, [_creator('a')]);
      final order = await service.request(
        reqId: 1,
        gen: 99,
        query: '',
        sortBy: SortBy.updated,
        ascending: false,
        favoritesOnly: false,
        cachedOnly: false,
      );
      expect(order, isEmpty);
    });

    test('filters by extra keys through the isolate', () async {
      final service = CreatorSortService.instance;
      final cs = [
        _creator('a', name: 'じょぶじゅん', updated: 300),
        _creator('b', name: 'Other', updated: 100),
      ];
      await service.setBase(1, cs, extraKeys: [
        ['jovejun', 'jun81jun'],
        const [],
      ]);

      final query = await service.request(
        reqId: 1,
        gen: 1,
        query: 'jovejun',
        sortBy: SortBy.updated,
        ascending: false,
        favoritesOnly: false,
        cachedOnly: false,
      );
      expect([for (final i in query) cs[i].id], ['a']);
    });
  });
}
