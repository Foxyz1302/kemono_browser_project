import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/archive/archive_service.dart';
import 'package:koni_archive/io.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late ArchiveService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('archive_test_');
    service = ArchiveService(Dio());
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('listEntries', () {
    test('lists entries in a valid zip archive', () async {
      final zipPath = p.join(tempDir.path, 'test.zip');
      final writer = await createArchiveFile(
        zipPath,
        format: const ZipWriteFormat(),
      );
      await writer.addBytes(
        ArchiveEntrySpec(path: 'photo.png'),
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      );
      await writer.addBytes(
        ArchiveEntrySpec(path: 'readme.txt'),
        Uint8List.fromList([0x68, 0x65, 0x6C, 0x6C, 0x6F]),
      );
      await writer.addBytes(
        ArchiveEntrySpec(path: 'sub/img.webp'),
        Uint8List.fromList([0x52, 0x49, 0x46, 0x46]),
      );
      await writer.close();

      final entries = await service.listEntries(zipPath);

      expect(entries.length, 3);
      expect(entries[0].path, 'photo.png');
      expect(entries[0].isImage, isTrue);
      expect(entries[0].uncompressedSize, 4);
      expect(entries[1].path, 'readme.txt');
      expect(entries[1].isImage, isFalse);
      expect(entries[2].path, 'sub/img.webp');
      expect(entries[2].isImage, isTrue);
    });

    test('returns empty list for empty archive', () async {
      final zipPath = p.join(tempDir.path, 'empty.zip');
      final writer = await createArchiveFile(
        zipPath,
        format: const ZipWriteFormat(),
      );
      await writer.close();

      final entries = await service.listEntries(zipPath);

      expect(entries, isEmpty);
    });

    test('throws for non-existent file', () async {
      final fakePath = p.join(tempDir.path, 'nope.zip');

      expect(
        () => service.listEntries(fakePath),
        throwsA(isA<Exception>()),
      );
    });

    test('throws for corrupt archive', () async {
      final badPath = p.join(tempDir.path, 'corrupt.zip');
      await File(badPath).writeAsBytes([0x00, 0x01, 0x02]);

      expect(
        () => service.listEntries(badPath),
        throwsA(isA<ArchiveException>()),
      );
    });
  });

  group('readEntry', () {
    test('reads entry bytes correctly', () async {
      final zipPath = p.join(tempDir.path, 'test.zip');
      final content = Uint8List.fromList([0x41, 0x42, 0x43]);
      final writer = await createArchiveFile(
        zipPath,
        format: const ZipWriteFormat(),
      );
      await writer.addBytes(
        ArchiveEntrySpec(path: 'data.bin'),
        content,
      );
      await writer.close();

      final bytes = await service.readEntry(zipPath, 'data.bin');

      expect(bytes, content);
    });

    test('throws for missing entry', () async {
      final zipPath = p.join(tempDir.path, 'test.zip');
      final writer = await createArchiveFile(
        zipPath,
        format: const ZipWriteFormat(),
      );
      await writer.addBytes(
        ArchiveEntrySpec(path: 'a.txt'),
        Uint8List.fromList([0x41]),
      );
      await writer.close();

      expect(
        () => service.readEntry(zipPath, 'b.txt'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('extractEntry', () {
    test('writes entry to disk at correct path', () async {
      final zipPath = p.join(tempDir.path, 'test.zip');
      final content = Uint8List.fromList([0x48, 0x49]);
      final writer = await createArchiveFile(
        zipPath,
        format: const ZipWriteFormat(),
      );
      await writer.addBytes(
        ArchiveEntrySpec(path: 'subdir/file.txt'),
        content,
      );
      await writer.close();

      final outDir = p.join(tempDir.path, 'out');
      await service.extractEntry(zipPath, 'subdir/file.txt', outDir);

      final extracted = File(p.join(outDir, 'subdir', 'file.txt'));
      expect(extracted.existsSync(), isTrue);
      expect(await extracted.readAsBytes(), content);
    });
  });

  group('extractAll', () {
    test('extracts all entries', () async {
      final zipPath = p.join(tempDir.path, 'test.zip');
      final writer = await createArchiveFile(
        zipPath,
        format: const ZipWriteFormat(),
      );
      await writer.addBytes(
        ArchiveEntrySpec(path: 'a.png'),
        Uint8List.fromList([0x00]),
      );
      await writer.addBytes(
        ArchiveEntrySpec(path: 'b.txt'),
        Uint8List.fromList([0x01]),
      );
      await writer.close();

      final outDir = p.join(tempDir.path, 'out');
      await service.extractAll(zipPath, outDir);

      expect(File(p.join(outDir, 'a.png')).existsSync(), isTrue);
      expect(File(p.join(outDir, 'b.txt')).existsSync(), isTrue);
    });
  });
}
