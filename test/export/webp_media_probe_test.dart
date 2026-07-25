import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/export/media_probe.dart';
import 'package:whatsapp_sticker_studio/export/webp_media_probe.dart';

/// Wraps a chunk in a RIFF/WEBP container: 'RIFF' + fileSize + 'WEBP' + fourCC
/// + chunkSize + data.
Uint8List riffWebp(String fourCC, List<int> data) {
  final b = BytesBuilder();
  final body = BytesBuilder()
    ..add('WEBP'.codeUnits)
    ..add(fourCC.codeUnits)
    ..add(_u32le(data.length))
    ..add(data);
  b
    ..add('RIFF'.codeUnits)
    ..add(_u32le(body.length))
    ..add(body.toBytes());
  return b.toBytes();
}

List<int> _u32le(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];
List<int> _u24le(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF];

/// VP8X extended header: stores canvas (width-1)/(height-1) as 24-bit LE.
Uint8List vp8x(int w, int h) =>
    riffWebp('VP8X', [0x10, 0, 0, 0, ..._u24le(w - 1), ..._u24le(h - 1)]);

/// VP8L lossless: 0x2F signature then 14-bit (w-1) and (h-1) packed LE.
Uint8List vp8l(int w, int h) {
  final bits = (w - 1) | ((h - 1) << 14);
  return riffWebp('VP8L', [0x2F, ..._u32le(bits)]);
}

/// VP8 lossy: 3-byte frame tag, start code 9d 01 2a, then 16-bit w/h (14 used).
Uint8List vp8(int w, int h) => riffWebp('VP8 ', [
  0,
  0,
  0,
  0x9d,
  0x01,
  0x2a,
  w & 0xFF,
  (w >> 8) & 0xFF,
  h & 0xFF,
  (h >> 8) & 0xFF,
]);

Uint8List png(int w, int h) {
  final b = BytesBuilder()
    ..add([137, 80, 78, 71, 13, 10, 26, 10]) // PNG signature
    ..add([0, 0, 0, 13]) // IHDR length
    ..add('IHDR'.codeUnits)
    ..add([(w >> 24) & 0xFF, (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF])
    ..add([(h >> 24) & 0xFF, (h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF]);
  return b.toBytes();
}

void main() {
  late Directory dir;
  final probe = WebpMediaProbe();

  setUp(() => dir = Directory.systemTemp.createTempSync('probe_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProbeResult> probeBytes(Uint8List bytes) async {
    final f = File('${dir.path}/f')..writeAsBytesSync(bytes);
    return probe.probe(f.path);
  }

  group('WebP dimensions by chunk type', () {
    test('VP8X (extended) reports 512x512 webp', () async {
      final r = await probeBytes(vp8x(512, 512));
      expect(r.format, 'webp');
      expect(r.width, 512);
      expect(r.height, 512);
    });

    test('VP8L (lossless) reports its dimensions', () async {
      final r = await probeBytes(vp8l(512, 512));
      expect(r.format, 'webp');
      expect(r.width, 512);
      expect(r.height, 512);
    });

    test('VP8 (lossy) reports its dimensions', () async {
      final r = await probeBytes(vp8(512, 512));
      expect(r.format, 'webp');
      expect(r.width, 512);
      expect(r.height, 512);
    });

    test('a non-512 WebP is reported as-is', () async {
      final r = await probeBytes(vp8x(400, 512));
      expect(r.width, 400);
      expect(r.height, 512);
    });
  });

  test('a PNG is reported as a non-webp format', () async {
    final r = await probeBytes(png(512, 512));
    expect(r.format, isNot('webp'));
  });

  test('truncated/garbage bytes throw rather than pass silently', () async {
    expect(
      () => probeBytes(Uint8List.fromList([0, 1, 2, 3])),
      throwsA(isA<ProbeException>()),
    );
  });
}
