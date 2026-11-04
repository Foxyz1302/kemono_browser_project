import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/state/creator_alias_index.dart';

Uint8List _bin({
  required List<String> services,
  required Map<String, List<(int, int)>> keys,
}) {
  final chunks = <int>[
    ...'DKBI'.codeUnits,
    1,
    services.length,
    for (final s in services) ...[utf8.encode(s).length, ...utf8.encode(s)],
  ];

  final out = <int>[...chunks];

  void appendVarint(int v) {
    while (true) {
      var b = v & 0x7F;
      v >>= 7;
      if (v != 0) {
        out.add(b | 0x80);
      } else {
        out.add(b);
        return;
      }
    }
  }

  appendVarint(keys.length);
  for (final entry in keys.entries) {
    appendVarint(utf8.encode(entry.key).length);
    out.addAll(utf8.encode(entry.key));
    appendVarint(entry.value.length);
    for (final (serviceIdx, id) in entry.value) {
      out.add(serviceIdx);
      appendVarint(id);
    }
  }
  return Uint8List.fromList(out);
}

void main() {
  group('CreatorAliasIndex.parse', () {
    test('round-trips keys to service/id refs', () {
      final bytes = _bin(
        services: ['fanbox', 'patreon'],
        keys: {
          'jovejun': [(0, 14644359)],
          'じょぶじゅん': [(0, 14644359), (1, 30500811)],
        },
      );
      final index = CreatorAliasIndex.parse(bytes);
      expect(index.extrasFor('fanbox', '14644359'), contains('jovejun'));
      expect(index.extrasFor('fanbox', '14644359'), contains('じょぶじゅん'));
      expect(index.extrasFor('patreon', '30500811'), contains('じょぶじゅん'));
      expect(index.extrasFor('patreon', '999'), isEmpty);
    });
  });

  group('CreatorAliasIndex.normalizeQuery', () {
    test('lowercases and strips leading @ and trailing punctuation', () {
      expect(CreatorAliasIndex.normalizeQuery('@JoveJun'), 'jovejun');
      expect(CreatorAliasIndex.normalizeQuery('JoveJun.'), 'jovejun');
      expect(CreatorAliasIndex.normalizeQuery('#jovejun_'), 'jovejun');
    });

    test('NFKC: full-width and math alphanumerics collapse to ASCII', () {
      expect(CreatorAliasIndex.normalizeQuery('ＪＯＶＥＪＵＮ'), 'jovejun');
      expect(CreatorAliasIndex.normalizeQuery('𝕁𝕠𝕧𝕖𝕁𝕦𝕟'), 'jovejun');
    });

    test('strips CJK punctuation from pasted display names', () {
      expect(CreatorAliasIndex.normalizeQuery('じょぶじゅん。'), 'じょぶじゅん');
      expect(CreatorAliasIndex.normalizeQuery('じよぶじゆん〇'), 'じよぶじゆん');
    });

    test('full pasted twitter line still contains the handle', () {
      final q = CreatorAliasIndex.normalizeQuery('じょぶじゅん。𝕁𝕠𝕧𝕖𝕁𝕦𝕟＠C108_二日目_東ウ-27ab@JoveJun');
      expect(q.contains('jovejun'), isTrue);
    });
  });
}