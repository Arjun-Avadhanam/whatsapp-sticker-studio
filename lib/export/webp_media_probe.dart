import 'dart:io';
import 'dart:typed_data';

import 'media_probe.dart';

/// [MediaProbe] that reads image dimensions and format straight from the file
/// header. Supports the three WebP chunk types an encoder can emit (VP8X for
/// animated/extended, VP8L lossless, VP8 lossy) and recognises PNG so a
/// wrong-format file is reported rather than mistaken for WebP.
class WebpMediaProbe implements MediaProbe {
  const WebpMediaProbe();

  @override
  Future<ProbeResult> probe(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return _parse(bytes);
  }

  ProbeResult _parse(Uint8List b) {
    if (_matches(b, 0, 'RIFF') && _matches(b, 8, 'WEBP')) {
      return _parseWebp(b);
    }
    if (_isPng(b)) {
      // width/height are big-endian in the IHDR block at offset 16.
      return ProbeResult(
        width: _u32be(b, 16),
        height: _u32be(b, 20),
        format: 'png',
      );
    }
    throw const ProbeException('unrecognised file signature');
  }

  ProbeResult _parseWebp(Uint8List b) {
    // The inner chunk's FourCC sits at offset 12; its data starts at 20.
    final chunk = String.fromCharCodes(b.sublist(12, 16));
    switch (chunk) {
      case 'VP8X':
        // Canvas size stored as (width-1)/(height-1), 24-bit LE at 24 and 27.
        return ProbeResult(
          width: _u24le(b, 24) + 1,
          height: _u24le(b, 27) + 1,
          format: 'webp',
        );
      case 'VP8L':
        // 0x2F signature at 20, then 14-bit (w-1) and (h-1) packed LE.
        final bits = _u32le(b, 21);
        return ProbeResult(
          width: (bits & 0x3FFF) + 1,
          height: ((bits >> 14) & 0x3FFF) + 1,
          format: 'webp',
        );
      case 'VP8 ':
        // Frame tag (3) + start code 9d 01 2a, then 14-bit w/h little-endian.
        return ProbeResult(
          width: _u16le(b, 26) & 0x3FFF,
          height: _u16le(b, 28) & 0x3FFF,
          format: 'webp',
        );
      default:
        throw ProbeException('unknown WebP chunk "$chunk"');
    }
  }

  bool _isPng(Uint8List b) =>
      b.length >= 24 &&
      const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ].indexed.every((e) => b[e.$1] == e.$2);

  bool _matches(Uint8List b, int offset, String tag) {
    if (b.length < offset + tag.length) return false;
    for (var i = 0; i < tag.length; i++) {
      if (b[offset + i] != tag.codeUnitAt(i)) return false;
    }
    return true;
  }

  int _u16le(Uint8List b, int o) {
    _need(b, o + 2);
    return b[o] | (b[o + 1] << 8);
  }

  int _u24le(Uint8List b, int o) {
    _need(b, o + 3);
    return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
  }

  int _u32le(Uint8List b, int o) {
    _need(b, o + 4);
    return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  }

  int _u32be(Uint8List b, int o) {
    _need(b, o + 4);
    return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  }

  void _need(Uint8List b, int end) {
    if (b.length < end) throw const ProbeException('file header truncated');
  }
}
