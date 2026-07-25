import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:koni_archive/io.dart';
import 'package:path/path.dart' as p;

class ArchiveEntryInfo {
  final String path;
  final int uncompressedSize;
  final bool isImage;

  const ArchiveEntryInfo({
    required this.path,
    required this.uncompressedSize,
    required this.isImage,
  });
}

class ArchiveService {
  static const _imageExts = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif'};

  final Dio dio;

  ArchiveService(this.dio);

  Future<String> downloadArchive(String url, String tempDir, {String? localPath, CancelToken? cancelToken, void Function(int received, int total)? onProgress}) async {
    localPath ??= () {
      final uri = Uri.parse(url);
      final filename = uri.queryParameters['f'] ?? uri.pathSegments.last;
      return p.join(tempDir, filename);
    }();
    final dir = Directory(p.dirname(localPath));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    try {
      await dio.download(
        url,
        localPath,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          headers: {
            'Referer': 'https://pawchive.pw/',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );
    } on DioException catch (e) {
      debugPrint('Archive download failed: ${e.message}');
      rethrow;
    }
    return localPath;
  }

  Future<List<ArchiveEntryInfo>> listEntries(String localPath) async {
    final file = File(localPath);
    if (!file.existsSync()) {
      throw Exception('Archive file not found: $localPath');
    }
    try {
      final archive = await openArchiveFile(localPath);
      try {
        return archive.files.map((e) {
          final ext = p.extension(e.path).toLowerCase();
          return ArchiveEntryInfo(
            path: e.path,
            uncompressedSize: e.uncompressedSize,
            isImage: _imageExts.contains(ext),
          );
        }).toList();
      } finally {
        await archive.close();
      }
    } on ArchiveException catch (e) {
      debugPrint('Archive listing failed: $e');
      rethrow;
    }
  }

  Future<Uint8List> readEntry(String localPath, String entryPath) async {
    try {
      final archive = await openArchiveFile(localPath);
      try {
        final entry = archive.entry(entryPath);
        if (entry == null) throw Exception('Entry not found: $entryPath');
        return await archive.readBytes(entry);
      } finally {
        await archive.close();
      }
    } on ArchiveException catch (e) {
      debugPrint('Archive read failed: $e');
      rethrow;
    }
  }

  Future<void> extractEntry(String localPath, String entryPath, String outputDir) async {
    final bytes = await readEntry(localPath, entryPath);
    final outFile = File(p.join(outputDir, entryPath));
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(bytes);
  }

  Future<void> extractAll(String localPath, String outputDir) async {
    final entries = await listEntries(localPath);
    for (final e in entries) {
      await extractEntry(localPath, e.path, outputDir);
    }
  }

  void deleteArchivedFile(String localPath) {
    final file = File(localPath);
    if (file.existsSync()) file.deleteSync();
  }
}
