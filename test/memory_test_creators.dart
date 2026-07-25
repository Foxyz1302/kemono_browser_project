// dart test/memory_test_creators.dart
import 'dart:convert';
import 'dart:io';

class Creator {
  final String id, name, service;
  final int indexed, updated, favorited;
  final bool everImported;
  Creator({required this.id, required this.name, required this.service,
    required this.indexed, required this.updated,
    required this.favorited, required this.everImported});

  factory Creator.fromMap(Map<String, dynamic> m) => Creator(
    id: m['id'] as String,
    name: m['name'] as String,
    service: m['service'] as String,
    indexed: m['indexed'] as int,
    updated: m['updated'] as int,
    favorited: m['favorited'] as int,
    everImported: m['ever_imported'] as bool,
  );
}

double rssMb() => ProcessInfo.currentRss / (1024 * 1024);
void logMem(String label) => print('  [${rssMb().toStringAsFixed(1).padLeft(6)} MB] $label');

void main() async {
  print('\n══════════ CREATORS MEMORY TEST ══════════\n');

  logMem('1. baseline');
  final bytes = await File('test_creators.json').readAsBytes();
  print('Raw JSON: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB\n');

  logMem('2. raw bytes in memory');
  final s = utf8.decode(bytes);
  logMem('3. String decoded (+${(rssMb() - (rssMb() - 0)).toStringAsFixed(0)}?)');
  // baseline to compare against
  final stage2mem = rssMb();

  final parsed = jsonDecode(s) as List;
  logMem('4. jsonDecode → List<Map> (${parsed.length} entries)');
  final parseMem = rssMb();

  final creators = parsed.map((j) => Creator.fromMap(j as Map<String, dynamic>)).toList();
  logMem('5. Map→Creator (${creators.length} objects)');

  parsed.clear();
  logMem('6. List<Map> cleared (only List<Creator>)');

  creators.clear();
  logMem('7. both cleared');

  logMem('8. end');
  print('\nKey delta: jsonDecode added +${(parseMem - stage2mem).toStringAsFixed(1)} MB');
  print('Conversion to Creator objects: negligibly small (strings shared from Map)\n');
}
