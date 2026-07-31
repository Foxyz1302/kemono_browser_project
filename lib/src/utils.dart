import 'package:flutter/material.dart';

class FileHelpers {
  FileHelpers._();

  static const String imgThumbBase = 'https://img.pawchive.pw/thumbnail/data';
  static const String fileDataBase = 'https://file.pawchive.pw/data';
  static const String baseUrl = 'https://pawchive.pw';

  static const Set<String> imageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif',
  };

  static const Set<String> videoExtensions = {
    'mp4', 'webm', 'mkv', 'mov', 'avi', 'm4v', '3gp',
  };

  /// Same as [imageExtensions] but with leading dots (for [p.extension] compatibility).
  static final Set<String> dottedImageExtensions =
      imageExtensions.map((e) => '.$e').toSet();

  /// Same as [videoExtensions] but with leading dots.
  static final Set<String> dottedVideoExtensions =
      videoExtensions.map((e) => '.$e').toSet();

  static const Map<String, IconData> iconForExtension = {
    'pdf': Icons.picture_as_pdf,
    'mp4': Icons.videocam,
    'webm': Icons.videocam,
    'mp3': Icons.audiotrack,
    'wav': Icons.audiotrack,
    'ogg': Icons.audiotrack,
    'zip': Icons.folder_zip,
    'rar': Icons.folder_zip,
    '7z': Icons.folder_zip,
    'psd': Icons.brush,
    'ai': Icons.brush,
    'clip': Icons.brush,
    'sai': Icons.brush,
    'txt': Icons.description,
    'doc': Icons.description,
    'docx': Icons.description,
  };

  static bool isImage(String? name) {
    if (name == null) return false;
    final ext = name.split('.').last.toLowerCase();
    return imageExtensions.contains(ext);
  }

  static bool isVideo(String? name) {
    if (name == null) return false;
    final ext = name.split('.').last.toLowerCase();
    return videoExtensions.contains(ext);
  }

  static String? fileExtension(String? name) {
    if (name == null) return null;
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : null;
  }
}
