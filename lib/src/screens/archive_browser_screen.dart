import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:kemono_browser_project/src/archive/archive_service.dart';
import 'package:path/path.dart' as p;

enum _ArchiveState { downloading, ready, error }

class ArchiveBrowserDialog extends StatefulWidget {
  final String archiveUrl;
  final String archiveName;
  final ArchiveService service;
  final String tempDir;

  const ArchiveBrowserDialog({
    super.key,
    required this.archiveUrl,
    required this.archiveName,
    required this.service,
    required this.tempDir,
  });

  @override
  State<ArchiveBrowserDialog> createState() => _ArchiveBrowserDialogState();
}

class _ArchiveBrowserDialogState extends State<ArchiveBrowserDialog> {
  _ArchiveState _state = _ArchiveState.downloading;
  double _downloadProgress = 0;
  String? _error;
  List<String> _entries = [];
  String _localPath = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _localPath = await widget.service.downloadArchive(
        widget.archiveUrl,
        widget.tempDir,
        onProgress: _onDownloadProgress,
      );
      final entries = await widget.service.listEntries(_localPath);
      if (!mounted) return;
      setState(() {
        _entries = entries.map((e) => e.path).toList();
        _state = _ArchiveState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _state = _ArchiveState.error;
      });
    }
  }

  void _onDownloadProgress(int received, int total) {
    if (!mounted) return;
    setState(() {
      _downloadProgress = total > 0 ? received / total : 0;
    });
  }

  Future<Uint8List> _loadEntry(String entryPath) async {
    return await widget.service.readEntry(_localPath, entryPath);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: switch (_state) {
          _ArchiveState.downloading => _buildProgress(context),
          _ArchiveState.ready => _buildGrid(context),
          _ArchiveState.error => _buildError(context),
        },
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final pct = (_downloadProgress * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text(
            widget.archiveName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),
          LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
          const SizedBox(height: 12),
          Text(
            'Downloading... $pct%',
            style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text('Failed to open archive', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(_error ?? 'Unknown error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton(onPressed: () {
            setState(() {
              _state = _ArchiveState.downloading;
              _downloadProgress = 0;
              _error = null;
            });
            _start();
          }, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.folder_zip, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.archiveName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${_entries.length} files', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              childAspectRatio: 1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _entries.length,
            itemBuilder: (context, i) {
              final path = _entries[i];
              final ext = p.extension(path).toLowerCase();
              final isImage = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif'].contains(ext);
              return GestureDetector(
                onTap: isImage ? () => _showImage(context, path) : null,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: isImage
                            ? FutureBuilder<Uint8List>(
                                future: _loadEntry(path),
                                builder: (context, imgSnapshot) {
                                  if (imgSnapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                  }
                                  if (imgSnapshot.hasError || !imgSnapshot.hasData) {
                                    return const Center(child: Icon(Icons.broken_image, color: Colors.white38));
                                  }
                                  return Image.memory(imgSnapshot.data!, fit: BoxFit.cover);
                                },
                              )
                            : Container(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: Center(
                                  child: Icon(
                                    _iconForExt(ext),
                                    size: 32,
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                        color: Colors.black87,
                        child: Text(
                          p.basename(path),
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showImage(BuildContext context, String path) async {
    final data = await _loadEntry(path);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenImage(data: data, title: widget.archiveName, entryPath: path),
      ),
    );
  }

  static IconData _iconForExt(String ext) {
    return switch (ext) {
      '.zip' || '.rar' || '.7z' => Icons.folder_zip,
      '.pdf' => Icons.picture_as_pdf,
      '.mp4' || '.webm' => Icons.videocam,
      '.mp3' || '.wav' || '.ogg' => Icons.audiotrack,
      '.psd' || '.ai' || '.clip' || '.sai' => Icons.brush,
      '.txt' || '.doc' || '.docx' => Icons.description,
      _ => Icons.insert_drive_file,
    };
  }
}

class _FullScreenImage extends StatelessWidget {
  final Uint8List data;
  final String title;
  final String entryPath;

  const _FullScreenImage({required this.data, required this.title, required this.entryPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('$title / ${p.basename(entryPath)}', style: const TextStyle(color: Colors.white, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.memory(data, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
