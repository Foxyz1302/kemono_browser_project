import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kemono_browser_project/src/cache/image_size_parser.dart';

void main() {
  group('ImageSizeParser', () {
    group('PNG', () {
      test('parses 1x1 PNG', () {
        const base64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
        final bytes = base64Decode(base64);
        final dims = ImageSizeParser.parse(bytes);
        expect(dims, const ImageDims(1, 1));
      });

      test('parses crafted 1024x768 PNG header', () {
        final d = Uint8List(32);
        d[0] = 0x89; d[1] = 0x50; d[2] = 0x4E; d[3] = 0x47;
        d[4] = 0x0D; d[5] = 0x0A; d[6] = 0x1A; d[7] = 0x0A;
        d[8] = 0x00; d[9] = 0x00; d[10] = 0x00; d[11] = 0x0D;
        d[12] = 'I'.codeUnitAt(0); d[13] = 'H'.codeUnitAt(0);
        d[14] = 'D'.codeUnitAt(0); d[15] = 'R'.codeUnitAt(0);
        d[16] = 0x00; d[17] = 0x00; d[18] = 0x04; d[19] = 0x00;
        d[20] = 0x00; d[21] = 0x00; d[22] = 0x03; d[23] = 0x00;

        final dims = ImageSizeParser.parse(d);
        expect(dims, const ImageDims(1024, 768));
      });
    });

    group('GIF', () {
      test('parses 320x240 GIF89a', () {
        final d = Uint8List(20);
        d[0] = 0x47; d[1] = 0x49; d[2] = 0x46;
        d[3] = 0x38; d[4] = 0x39; d[5] = 0x61;
        d[6] = 0x40; d[7] = 0x01;
        d[8] = 0xF0; d[9] = 0x00;

        final dims = ImageSizeParser.parse(d);
        expect(dims, const ImageDims(320, 240));
      });
    });

    group('JPEG', () {
      test('parses 1920x1080 JPEG with SOF0', () {
        final d = Uint8List(64);
        d[0] = 0xFF; d[1] = 0xD8;
        d[2] = 0xFF; d[3] = 0xE0;
        d[4] = 0x00; d[5] = 0x10;
        final sofOffset = 2 + 2 + 16;
        d[sofOffset] = 0xFF; d[sofOffset + 1] = 0xC0;
        d[sofOffset + 2] = 0x00; d[sofOffset + 3] = 0x11;
        d[sofOffset + 4] = 0x08;
        d[sofOffset + 5] = 0x04; d[sofOffset + 6] = 0x38;
        d[sofOffset + 7] = 0x07; d[sofOffset + 8] = 0x80;

        final dims = ImageSizeParser.parse(d);
        expect(dims, const ImageDims(1920, 1080));
      });
    });

    group('WebP', () {
      test('parses VP8X extended format', () {
        final d = Uint8List(40);
        d[0] = 0x52; d[1] = 0x49; d[2] = 0x46; d[3] = 0x46;
        d[8] = 0x57; d[9] = 0x45; d[10] = 0x42; d[11] = 0x50;
        d[12] = 0x56; d[13] = 0x50; d[14] = 0x38; d[15] = 0x58;
        d[24] = 0x1F; d[25] = 0x03; d[26] = 0x00;
        d[27] = 0x57; d[28] = 0x02; d[29] = 0x00;

        final dims = ImageSizeParser.parse(d);
        expect(dims, const ImageDims(800, 600));
      });

      test('parses VP8 lossy format', () {
        final d = Uint8List(32);
        d[0] = 0x52; d[1] = 0x49; d[2] = 0x46; d[3] = 0x46;
        d[8] = 0x57; d[9] = 0x45; d[10] = 0x42; d[11] = 0x50;
        d[12] = 0x56; d[13] = 0x50; d[14] = 0x38; d[15] = 0x20;
        d[23] = 0x9D; d[24] = 0x01; d[25] = 0x2A;
        d[26] = 0x80; d[27] = 0x02;
        d[28] = 0xE0; d[29] = 0x01;

        final dims = ImageSizeParser.parse(d);
        expect(dims, const ImageDims(640, 480));
      });

      test('parses VP8L lossless format', () {
        final d = Uint8List(32);
        d[0] = 0x52; d[1] = 0x49; d[2] = 0x46; d[3] = 0x46;
        d[8] = 0x57; d[9] = 0x45; d[10] = 0x42; d[11] = 0x50;
        d[12] = 0x56; d[13] = 0x50; d[14] = 0x38; d[15] = 0x4C;
        d[20] = 0x2F;
        d[21] = 0x63; d[22] = 0x40; d[23] = 0x0C; d[24] = 0x00;

        final dims = ImageSizeParser.parse(d);
        expect(dims, const ImageDims(100, 50));
      });
    });

    group('edge cases', () {
      test('returns null for data too short', () {
        final d = Uint8List(4);
        expect(ImageSizeParser.parse(d), isNull);
      });

      test('returns null for unrecognized format', () {
        final d = Uint8List(20);
        d[0] = 0x00; d[1] = 0x00;
        expect(ImageSizeParser.parse(d), isNull);
      });

      test('returns null for PNG with zero dimensions', () {
        final d = Uint8List(24);
        d[0] = 0x89; d[1] = 0x50; d[2] = 0x4E; d[3] = 0x47;
        expect(ImageSizeParser.parse(d), isNull);
      });
    });
  });

  group('ImageDims', () {
    test('aspectRatio', () {
      const dims = ImageDims(1920, 1080);
      expect(dims.aspectRatio, closeTo(1.777, 0.001));
    });

    test('equality', () {
      const a = ImageDims(100, 200);
      const b = ImageDims(100, 200);
      const c = ImageDims(200, 100);
      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode == b.hashCode, isTrue);
    });
  });
}
