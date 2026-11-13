import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/utils/image_bytes.dart';
import 'package:flutter_test/flutter_test.dart';

/// `RIFF` + 4 size bytes + [form] (`WEBP`, `WAVE`, ...).
List<int> _riff(String form) => [
  ...'RIFF'.codeUnits,
  0,
  0,
  0,
  0,
  ...form.codeUnits,
];

/// `BM` + 12 header bytes + a little-endian DIB header size (18 bytes).
List<int> _bmp(int dibSize) => [
  0x42,
  0x4D,
  ...List.filled(12, 0),
  dibSize & 0xFF,
  dibSize >> 8 & 0xFF,
  dibSize >> 16 & 0xFF,
  dibSize >> 24 & 0xFF,
];

void main() {
  group('imageMimeType (6-1, 6-7, 6-8)', () {
    final cases = <(String, List<int>, String?)>[
      (
        'png: full 8-byte signature',
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        'image/png',
      ),
      ('png: truncated signature (6-7)', [137, 80, 78, 71], null),
      ('jpeg: FF D8 FF', [0xFF, 0xD8, 0xFF], 'image/jpeg'),
      ('jpeg: truncated signature', [0xFF, 0xD8], null),
      ('gif87a', 'GIF87a'.codeUnits, 'image/gif'),
      ('gif89a', 'GIF89a'.codeUnits, 'image/gif'),
      ('gif: truncated signature', 'GIF8'.codeUnits, null),
      ('webp', _riff('WEBP'), 'image/webp'),
      ('riff that is not webp (WAVE)', _riff('WAVE'), null),
      ('riff: too short', 'RIFF'.codeUnits, null),
      ('bmp: DIB header size 40', _bmp(40), 'image/bmp'),
      ('bmp: text starting with BM', 'BMW is a car'.codeUnits, null),
      ('bmp: shorter than 18 bytes', _bmp(40).sublist(0, 17), null),
      ('bmp: unknown DIB header size', _bmp(41), null),
      (
        'svg (6-8)',
        '<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits,
        null,
      ),
      ('xml prolog (6-8)', '<?xml version="1.0"?><svg/>'.codeUnits, null),
      ('empty', <int>[], null),
    ];

    for (final (name, bytes, mime) in cases) {
      test(name, () => expect(imageMimeType(bytes), mime));
    }
  });

  group('imageSummary', () {
    test('formats mime type, size and the truncated marker', () {
      expect(
        imageSummary('image/png', 35021),
        '[image/png, 34.2 KB]$kTruncatedMarker',
      );
    });
  });
}
