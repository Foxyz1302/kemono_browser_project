import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'image_cache_service.dart';
import 'image_meta_store.dart';

@immutable
class KemonoImageProvider extends ImageProvider<KemonoImageProvider> {
  final String url;
  final Map<String, String>? headers;
  final String? cacheKey;
  final String? creatorId;
  final String? postId;
  final double scale;
  final String _effectiveKey;

  KemonoImageProvider(this.url, {this.headers, this.cacheKey, this.creatorId, this.postId, this.scale = 1.0})
      : _effectiveKey = cacheKey ?? canonicalUrl(url);

  static String canonicalUrl(String url) => url.split('?').first;

  @override
  Future<KemonoImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(KemonoImageProvider key, ImageDecoderCallback decode) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    final codec = _loadAsync(key, decode, chunkEvents);

    final completer = MultiFrameImageStreamCompleter(
      codec: codec,
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('URL', url),
      ],
    );

    completer.addOnLastListenerRemovedCallback(() {
      ImageCacheService.instance.cancelDownload(url);
    });

    return completer;
  }

  Future<ui.Codec> _loadAsync(
    KemonoImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      final stream = ImageCacheService.instance.cache.getFileStream(
        key.url,
        key: key._effectiveKey,
        headers: key.headers,
        withProgress: true,
      );

      await for (final response in stream) {
        if (response is DownloadProgress) {
          chunkEvents.add(ImageChunkEvent(
            cumulativeBytesLoaded: response.downloaded,
            expectedTotalBytes: response.totalSize,
          ));
        } else if (response is FileInfo) {
          chunkEvents.close();
          if (ImageMetaStore.instance.isInitialized) {
            unawaited(ImageMetaStore.instance.record(
              key._effectiveKey,
              io.File(response.file.path),
              creatorId: key.creatorId,
              postId: key.postId,
            ));
          }
          return await decode(await ui.ImmutableBuffer.fromFilePath(response.file.path));
        }
      }
      throw Exception('Image stream completed without providing a file: ${key.url}');
    } catch (e) {
      chunkEvents.close();
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
        ImageCacheService.instance.removeFile(key._effectiveKey);
      });
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KemonoImageProvider &&
          _effectiveKey == other._effectiveKey &&
          scale == other.scale &&
          creatorId == other.creatorId &&
          postId == other.postId;

  @override
  int get hashCode => Object.hash(_effectiveKey, scale, creatorId, postId);

  @override
  String toString() => '${objectRuntimeType(this, 'KemonoImageProvider')}("$url", key: "$_effectiveKey")';
}
