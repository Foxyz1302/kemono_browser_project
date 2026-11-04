import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../api/models.dart';

/// Sort modes for the creator grid. Kept in this library because the worker
/// isolate needs them; re-exported from [AppState] so screens can keep
/// importing `app_state.dart`.
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

/// Builds the per-creator search/sort keys for a base list:
/// lowercased names (case-insensitive filter + name sort) and "service/id"
/// keys (favorites membership). Called once per base transfer in the worker.
({List<String> namesLower, List<String> keys}) prepareSortKeys({
  required List<String> ids,
  required List<String> names,
  required List<String> services,
}) {
  final n = ids.length;
  return (
    namesLower: [for (var i = 0; i < n; i++) names[i].toLowerCase()],
    keys: [for (var i = 0; i < n; i++) '${services[i]}/${ids[i]}'],
  );
}

/// Sorts indices by [sortBy]. Pure; runs in the worker isolate and is
/// unit-tested directly.
List<int> sortIndices({
  required List<String> ids,
  required List<String> namesLower,
  required List<String> services,
  required List<String> keys,
  required List<int> updated,
  required List<int> favorited,
  required List<int> indexed,
  required SortBy sortBy,
  required bool ascending,
  required Map<String, int> favUpdatedMillis,
  required Map<String, int> favImportedMillis,
  required Map<String, int> cacheBytes,
}) {
  final order = List<int>.generate(ids.length, (i) => i);
  order.sort((a, b) {
    int cmp = switch (sortBy) {
      SortBy.updated => updated[b].compareTo(updated[a]),
      SortBy.favorited => favorited[b].compareTo(favorited[a]),
      SortBy.indexed => indexed[b].compareTo(indexed[a]),
      SortBy.name => namesLower[a].compareTo(namesLower[b]),
      SortBy.service => services[a].compareTo(services[b]),
      SortBy.cacheSize =>
        (cacheBytes[ids[b]] ?? 0).compareTo(cacheBytes[ids[a]] ?? 0),
      SortBy.favUpdated =>
        (favUpdatedMillis[keys[b]] ?? 0).compareTo(favUpdatedMillis[keys[a]] ?? 0),
      SortBy.favLastImported =>
        (favImportedMillis[keys[b]] ?? 0).compareTo(favImportedMillis[keys[a]] ?? 0),
    };
    return ascending ? -cmp : cmp;
  });
  return order;
}

/// Filters a sorted index list by query / favorites-only / cached-only.
/// Pure; runs in the worker isolate. Query matches the creator name or any
/// extra alias key ([extraKeys]); keys shorter than 3 chars only match
/// forward to avoid noise, longer keys match in both directions so pasted
/// full lines (e.g. a twitter bio) still hit.
List<int> filterOrder({
  required List<int> order,
  required List<String> ids,
  required List<String> namesLower,
  required List<String> keys,
  required List<List<String>> extraKeys,
  required String query,
  required bool favoritesOnly,
  required Set<String> favKeySet,
  required bool cachedOnly,
  required Map<String, int> cacheBytes,
}) {
  final q = query.toLowerCase();
  final out = <int>[];
  for (final i in order) {
    if (q.isNotEmpty) {
      var hit = namesLower[i].contains(q);
      if (!hit) {
        final extra = extraKeys.isEmpty ? const <String>[] : extraKeys[i];
        for (final k in extra) {
          if (k.length < 3 ? k.contains(q) : (k.contains(q) || q.contains(k))) {
            hit = true;
            break;
          }
        }
      }
      if (!hit) continue;
    }
    if (cachedOnly && !cacheBytes.containsKey(ids[i])) continue;
    if (favoritesOnly && !favKeySet.contains(keys[i])) continue;
    out.add(i);
  }
  return out;
}

/// Convenience wrapper: sort then filter. Used by unit tests and mirrors the
/// worker's per-request pipeline.
List<int> computeFilteredOrder({
  required List<String> ids,
  required List<String> namesLower,
  required List<String> services,
  required List<String> keys,
  required List<int> updated,
  required List<int> favorited,
  required List<int> indexed,
  required String query,
  required SortBy sortBy,
  required bool ascending,
  required bool favoritesOnly,
  required List<String> favKeys,
  required Map<String, int> favUpdatedMillis,
  required Map<String, int> favImportedMillis,
  required bool cachedOnly,
  required Map<String, int> cacheBytes,
  List<List<String>> extraKeys = const [],
}) {
  final order = sortIndices(
    ids: ids,
    namesLower: namesLower,
    services: services,
    keys: keys,
    updated: updated,
    favorited: favorited,
    indexed: indexed,
    sortBy: sortBy,
    ascending: ascending,
    favUpdatedMillis: favUpdatedMillis,
    favImportedMillis: favImportedMillis,
    cacheBytes: cacheBytes,
  );
  return filterOrder(
    order: order,
    ids: ids,
    namesLower: namesLower,
    keys: keys,
    extraKeys: extraKeys,
    query: query,
    favoritesOnly: favoritesOnly,
    favKeySet: favoritesOnly ? favKeys.toSet() : const {},
    cachedOnly: cachedOnly,
    cacheBytes: cacheBytes,
  );
}

/// Long-lived worker isolate entry point. Holds a compact resident copy of the
/// creator index (and favorites) and answers filter+sort requests, so the UI
/// isolate never touches the 89K list again after the one-time transfer.
///
/// Messages from the main isolate:
///   {'op': 'base', 'gen': int, 'ids': [...], 'names': [...], 'services': [...],
///    'updated': [...], 'favorited': [...], 'indexed': [...]}
///   {'op': 'favs', 'keys': [...], 'updatedMillis': [...], 'importedMillis': [...]}
///   {'op': 'request', 'reqId': int, 'gen': int, 'query': String, 'sortBy': SortBy,
///    'ascending': bool, 'favoritesOnly': bool, 'cachedOnly': bool,
///    'cacheIds': [...]?, 'cacheBytes': [...]?}
///   {'op': 'dispose'}
///
/// Replies: {'op': 'ready', 'port': SendPort} then
///         {'op': 'result', 'reqId': int, 'gen': int, 'order': TransferableTypedData}
@pragma('vm:entry-point')
void creatorSortWorker(SendPort mainPort) {
  final commands = ReceivePort();
  mainPort.send({'op': 'ready', 'port': commands.sendPort});

  List<String>? ids, namesLower, services, keys;
  List<List<String>> extraKeys = const [];
  List<int>? updated, favorited, indexed;
  Set<String> favKeySet = const {};
  Map<String, int> favUpdatedMillis = const {};
  Map<String, int> favImportedMillis = const {};
  int baseGen = -1;
  int favsVersion = 0;

  int? orderGen;
  SortBy? orderBy;
  bool? orderAsc;
  int? orderFavsVersion;
  List<int>? order;

  commands.listen((msg) {
    final map = msg as Map;
    switch (map['op'] as String) {
      case 'base':
        baseGen = map['gen'] as int;
        ids = List<String>.from(map['ids'] as List);
        final names = List<String>.from(map['names'] as List);
        services = List<String>.from(map['services'] as List);
        updated = List<int>.from(map['updated'] as List);
        favorited = List<int>.from(map['favorited'] as List);
        indexed = List<int>.from(map['indexed'] as List);
        extraKeys = [
          for (final e in (map['extraKeys'] as List? ?? const []))
            List<String>.from(e as List),
        ];
        final base = prepareSortKeys(ids: ids!, names: names, services: services!);
        namesLower = base.namesLower;
        keys = base.keys;
      case 'favs':
        final favKeys = List<String>.from(map['keys'] as List);
        final updatedMillis = List<int>.from(map['updatedMillis'] as List);
        final importedMillis = List<int>.from(map['importedMillis'] as List);
        favKeySet = favKeys.toSet();
        favUpdatedMillis = {
          for (var i = 0; i < favKeys.length; i++) favKeys[i]: updatedMillis[i],
        };
        favImportedMillis = {
          for (var i = 0; i < favKeys.length; i++) favKeys[i]: importedMillis[i],
        };
        favsVersion++;
      case 'request':
        final reqId = map['reqId'] as int;
        final gen = map['gen'] as int;
        if (gen != baseGen) {
          mainPort.send({
            'op': 'result',
            'reqId': reqId,
            'gen': gen,
            'order': TransferableTypedData.fromList([Int32List(0)]),
          });
          return;
        }
        final cacheIds = map['cacheIds'] as List?;
        final cacheBytesList = map['cacheBytes'] as List?;
        Map<String, int> cacheBytes = const {};
        if (cacheIds != null && cacheBytesList != null) {
          cacheBytes = {
            for (var i = 0; i < cacheIds.length; i++)
              cacheIds[i] as String: cacheBytesList[i] as int,
          };
        }
        final sortBy = map['sortBy'] as SortBy;
        final ascending = map['ascending'] as bool;
        final rebuildOrder = order == null ||
            orderGen != gen ||
            orderBy != sortBy ||
            orderAsc != ascending ||
            (sortBy.isFavoritesSort && orderFavsVersion != favsVersion) ||
            sortBy == SortBy.cacheSize;
        if (rebuildOrder) {
          order = sortIndices(
            ids: ids!,
            namesLower: namesLower!,
            services: services!,
            keys: keys!,
            updated: updated!,
            favorited: favorited!,
            indexed: indexed!,
            sortBy: sortBy,
            ascending: ascending,
            favUpdatedMillis: favUpdatedMillis,
            favImportedMillis: favImportedMillis,
            cacheBytes: cacheBytes,
          );
          orderGen = gen;
          orderBy = sortBy;
          orderAsc = ascending;
          orderFavsVersion = favsVersion;
        }
        final out = filterOrder(
          order: order!,
          ids: ids!,
          namesLower: namesLower!,
          keys: keys!,
          extraKeys: extraKeys,
          query: map['query'] as String,
          favoritesOnly: map['favoritesOnly'] as bool,
          favKeySet: favKeySet,
          cachedOnly: map['cachedOnly'] as bool,
          cacheBytes: cacheBytes,
        );
        mainPort.send({
          'op': 'result',
          'reqId': reqId,
          'gen': gen,
          'order': TransferableTypedData.fromList([Int32List.fromList(out)]),
        });
      case 'dispose':
        commands.close();
    }
  });
}

/// Singleton facade over the worker isolate. Lives on the UI isolate; all
/// heavy work happens in [creatorSortWorker].
class CreatorSortService {
  static final CreatorSortService _instance = CreatorSortService._();
  static CreatorSortService get instance => _instance;

  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _replies;
  Future<void>? _startFuture;
  final Map<int, Completer<Int32List>> _pending = {};

  CreatorSortService._();

  Future<void> ensureStarted() => _startFuture ??= _start();

  Future<void> _start() async {
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    Isolate? isolate;
    try {
      _replies = replies;
      replies.listen((msg) {
        final map = msg as Map;
        if (map['op'] == 'ready') {
          ready.complete(map['port'] as SendPort);
        } else {
          _onReply(map);
        }
      });
      isolate = await Isolate.spawn(creatorSortWorker, replies.sendPort);
      _isolate = isolate;
      final port = await ready.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw TimeoutException('CreatorSortService: worker never became ready'),
      );
      if (!identical(_replies, replies)) {
        // A restart() happened while this start was in flight — orphaned.
        throw StateError('CreatorSortService: start superseded by restart');
      }
      _workerPort = port;
      debugPrint('CreatorSortService: worker ready');
    } catch (e, st) {
      debugPrint('CreatorSortService: start failed: $e\n$st');
      if (identical(_replies, replies)) {
        replies.close();
        _replies = null;
        _workerPort = null;
        _startFuture = null;
      }
      isolate?.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  void _onReply(dynamic msg) {
    final map = msg as Map;
    if (map['op'] != 'result') return;
    final reqId = map['reqId'] as int;
    final td = map['order'] as TransferableTypedData;
    final bytes = td.materialize();
    final order = Int32List.view(bytes);
    _pending.remove(reqId)?.complete(order);
  }

  /// Transfers the full creator index to the worker (one-time per load).
  /// [extraKeys] holds the normalized danbooru alias keys per creator, aligned
  /// with [creators].
  Future<void> setBase(
    int gen,
    List<Creator> creators, {
    List<List<String>> extraKeys = const [],
  }) async {
    await ensureStarted();
    _workerPort!.send({
      'op': 'base',
      'gen': gen,
      'ids': [for (final c in creators) c.id],
      'names': [for (final c in creators) c.name],
      'services': [for (final c in creators) c.service],
      'updated': [for (final c in creators) c.updated],
      'favorited': [for (final c in creators) c.favorited],
      'indexed': [for (final c in creators) c.indexed],
      'extraKeys': extraKeys,
    });
  }

  /// Transfers favorite metadata (keys + pre-parsed timestamps) to the worker.
  Future<void> setFavs(List<FavoriteCreator> favs) async {
    await ensureStarted();
    _workerPort!.send({
      'op': 'favs',
      'keys': [for (final fc in favs) '${fc.service}/${fc.id}'],
      'updatedMillis': [
        for (final fc in favs) DateTime.tryParse(fc.updated)?.millisecondsSinceEpoch ?? 0,
      ],
      'importedMillis': [
        for (final fc in favs)
          fc.lastImported == null
              ? 0
              : DateTime.tryParse(fc.lastImported!)?.millisecondsSinceEpoch ?? 0,
      ],
    });
  }

  /// Asks the worker for the filtered+sorted order. [cacheBytes] is included
  /// only when the request needs it (cached-only filter / cache-size sort).
  Future<Int32List> request({
    required int reqId,
    required int gen,
    required String query,
    required SortBy sortBy,
    required bool ascending,
    required bool favoritesOnly,
    required bool cachedOnly,
    Map<String, int>? cacheBytes,
  }) async {
    await ensureStarted();
    final completer = Completer<Int32List>();
    _pending[reqId] = completer;
    final needCache = cachedOnly || sortBy == SortBy.cacheSize;
    _workerPort!.send({
      'op': 'request',
      'reqId': reqId,
      'gen': gen,
      'query': query,
      'sortBy': sortBy,
      'ascending': ascending,
      'favoritesOnly': favoritesOnly,
      'cachedOnly': cachedOnly,
      if (needCache && cacheBytes != null) ...{
        'cacheIds': cacheBytes.keys.toList(),
        'cacheBytes': cacheBytes.values.toList(),
      },
    });
    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
      _pending.remove(reqId);
      throw TimeoutException('CreatorSortService: request $reqId timed out');
    });
  }

  /// Kills the worker and clears state so the next [ensureStarted] respawns.
  void restart() {
    _workerPort?.send({'op': 'dispose'});
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    _workerPort = null;
    _isolate = null;
    _replies = null;
    _startFuture = null;
    _pending.clear();
  }
}
