import 'dart:typed_data';

class ImageDims {
  final int width;
  final int height;

  const ImageDims(this.width, this.height);

  double get aspectRatio => height == 0 ? 1 : width / height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ImageDims && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ImageDims($width x $height)';
}

class ImageSizeParser {
  static const maxHeaderBytes = 65536;

  static ImageDims? parse(Uint8List data) {
    if (data.length < 12) return null;
    if (_isPng(data)) return _parsePng(data);
    if (_isGif(data)) return _parseGif(data);
    if (_isJpeg(data)) return _parseJpeg(data);
    if (_isWebP(data)) return _parseWebP(data);
    return null;
  }

  static bool _isPng(Uint8List d) => d[0] == 0x89 && d[1] == 0x50 && d[2] == 0x4E && d[3] == 0x47;

  static ImageDims? _parsePng(Uint8List d) {
    if (d.length < 24) return null;
    final w = _be32(d, 16);
    final h = _be32(d, 20);
    return (w > 0 && h > 0) ? ImageDims(w, h) : null;
  }

  static bool _isGif(Uint8List d) => d[0] == 0x47 && d[1] == 0x49 && d[2] == 0x46;

  static ImageDims? _parseGif(Uint8List d) {
    if (d.length < 10) return null;
    final w = _le16(d, 6);
    final h = _le16(d, 8);
    return (w > 0 && h > 0) ? ImageDims(w, h) : null;
  }

  static bool _isJpeg(Uint8List d) => d[0] == 0xFF && d[1] == 0xD8;

  static ImageDims? _parseJpeg(Uint8List d) {
    var i = 2;
    while (i + 9 < d.length) {
      if (d[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = d[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) return null;
      final len = _be16(d, i + 2);
      if (len < 2) return null;
      final isSof =
          marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
      if (isSof) {
        final h = _be16(d, i + 5);
        final w = _be16(d, i + 7);
        return (w > 0 && h > 0) ? ImageDims(w, h) : null;
      }
      i += 2 + len;
    }
    return null;
  }

  static bool _isWebP(Uint8List d) =>
      d[0] == 0x52 &&
      d[1] == 0x49 &&
      d[2] == 0x46 &&
      d[3] == 0x46 &&
      d[8] == 0x57 &&
      d[9] == 0x45 &&
      d[10] == 0x42 &&
      d[11] == 0x50;

  static ImageDims? _parseWebP(Uint8List d) {
    if (d.length < 30) return null;
    final fourCC = String.fromCharCodes(d.sublist(12, 16));
    switch (fourCC) {
      case 'VP8X':
        return ImageDims(1 + _le24(d, 24), 1 + _le24(d, 27));
      case 'VP8 ':
        if (d[23] != 0x9D || d[24] != 0x01 || d[25] != 0x2A) return null;
        final w = _le16(d, 26) & 0x3FFF;
        final h = _le16(d, 28) & 0x3FFF;
        return (w > 0 && h > 0) ? ImageDims(w, h) : null;
      case 'VP8L':
        if (d[20] != 0x2F) return null;
        final b0 = d[21];
        final b1 = d[22];
        final b2 = d[23];
        final b3 = d[24];
        final w = 1 + (((b1 & 0x3F) << 8) | b0);
        final h = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6));
        return (w > 0 && h > 0) ? ImageDims(w, h) : null;
    }
    return null;
  }

  static int _be16(Uint8List d, int o) => (d[o] << 8) | d[o + 1];

  static int _be32(Uint8List d, int o) => (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

  static int _le16(Uint8List d, int o) => d[o] | (d[o + 1] << 8);

  static int _le24(Uint8List d, int o) => d[o] | (d[o + 1] << 8) | (d[o + 2] << 16);
}
