import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/api/models.dart';
import 'package:kemono_browser_project/src/state/creator_sort_service.dart';
import 'package:signals/signals_flutter.dart';

final filteredCreators = signal<List<Creator>>([]);

const _n = 89000;
const _favCount = 300;

List<Creator> _creators() {
  const services = ['patreon', 'fanbox', 'afdian', 'gumroad', 'dlsite', 'fanclubs'];
  return [
    for (var i = 0; i < _n; i++)
      Creator(
        id: 'id$i',
        name: 'Creator $i',
        service: services[i % services.length],
        updated: i * 7919 % 100000000,
        favorited: i * 104729 % 100000,
        indexed: i * 104729 % 1000000000,
        everImported: i % 7 != 0,
      ),
  ];
}

List<FavoriteCreator> _favs() {
  return [
    for (var i = 0; i < _favCount; i++)
      FavoriteCreator(
        id: 'id${i * 97 % _n}',
        name: 'Creator ${i * 97 % _n}',
        service: ['patreon', 'fanbox', 'afdian'][i % 3],
        updated: '2026-0${i % 9 + 1}-01T00:00:00Z',
        everImported: true,
        lastImported: '2026-07-01T00:00:00Z',
        kemonoFavorited: 0,
      ),
  ];
}

void main() {
  // Match the app: the debug DevTools observer adds a full toString pass per
  // signal set (see main.dart), so disable it to measure real costs.
  SignalsObserver.instance = null;
  final service = CreatorSortService.instance;

  setUp(() => service.restart());
  tearDown(() => service.restart());

  test('bench: worker round-trip latency per sort mode', () async {
    final all = _creators();
    final favs = _favs();
    final sw = Stopwatch()..start();
    await service.setBase(1, all);
    await service.setFavs(favs);
    final baseMs = sw.elapsedMilliseconds;
    debugPrintB('base transfer (${all.length} creators): ${baseMs}ms');

    var reqId = 0;
    Future<void> bench(
      String label, {
      required SortBy sortBy,
      bool ascending = false,
      bool favoritesOnly = false,
      String query = '',
    }) async {
      sw..reset()..start();
      final order = await service.request(
        reqId: ++reqId,
        gen: 1,
        query: query,
        sortBy: sortBy,
        ascending: ascending,
        favoritesOnly: favoritesOnly,
        cachedOnly: false,
        cacheBytes: sortBy == SortBy.cacheSize ? {for (var i = 0; i < 5000; i++) 'id${i * 13}': i * 1024} : null,
      );
      final ms = sw.elapsedMilliseconds;
      debugPrintB('$label: ${ms}ms (order=${order.length})');
    }

    await bench('sort updated (full)', sortBy: SortBy.updated);
    await bench('sort updated (full, repeat)', sortBy: SortBy.updated);
    await bench('sort name (full)', sortBy: SortBy.name);
    await bench('sort favorited (full)', sortBy: SortBy.favorited);
    await bench('sort favUpdated (favorites)', sortBy: SortBy.favUpdated, favoritesOnly: true);
    await bench('sort favUpdated (favorites, repeat)', sortBy: SortBy.favUpdated, favoritesOnly: true);
    await bench('sort favLastImported (favorites)', sortBy: SortBy.favLastImported, favoritesOnly: true);
    await bench('sort cacheSize (full)', sortBy: SortBy.cacheSize);
    await bench('TOGGLE OFF: back to updated (full)', sortBy: SortBy.updated);
    await bench('query "creator 500" (full)', sortBy: SortBy.updated, query: 'creator 500');

    // ── Isolate the apply cost: list build vs signal set ──────────────────
    final order = await service.request(
      reqId: ++reqId, gen: 1, query: '', sortBy: SortBy.updated, ascending: false,
      favoritesOnly: false, cachedOnly: false, cacheBytes: null,
    );
    final current = all;
    final applySw = Stopwatch()..start();
    final newList = [for (final i in order) current[i]];
    debugPrintB('apply: loop+build ${applySw.elapsedMilliseconds}ms (${newList.length})');
    applySw..reset()..start();
    filteredCreators.value = newList;
    debugPrintB('apply: signal set+notify ${applySw.elapsedMilliseconds}ms');
    applySw..reset()..start();
    filteredCreators.value = newList;
    debugPrintB('apply: signal set SAME identity ${applySw.elapsedMilliseconds}ms');
    applySw..reset()..start();
    final newList2 = [for (final i in order) current[i]];
    filteredCreators.value = newList2;
    debugPrintB('apply: loop+set combined (new identity) ${applySw.elapsedMilliseconds}ms');
  });
}

void debugPrintB(String s) => print('[BENCH] $s');
