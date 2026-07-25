import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/static_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/webp_encoder.dart';

/// Records what it was handed and returns canned output, so the geometry (the
/// RGBA bitmap [StaticEncoder] produces) can be inspected without a real WebP
/// encoder.
class FakeWebpEncoder implements WebpEncoder {
  FakeWebpEncoder({Uint8List? bytes, this.quality = 80})
    : bytes = bytes ?? Uint8List.fromList(List.filled(4321, 7));

  Uint8List? lastRgba;
  int? lastWidth;
  int? lastHeight;
  int? lastMaxBytes;

  final Uint8List bytes;
  final int quality;

  @override
  Future<WebpEncodeResult> encode(
    Uint8List rgba, {
    required int width,
    required int height,
    required int maxBytes,
  }) async {
    lastRgba = rgba;
    lastWidth = width;
    lastHeight = height;
    lastMaxBytes = maxBytes;
    return WebpEncodeResult(bytes: bytes, quality: quality);
  }
}

/// A solid opaque-red PNG of the given size — a known shape so letterbox padding
/// (transparent) is trivially distinguishable from content (opaque red).
Uint8List solidPng(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 0, 0, 255));
  return img.encodePng(im);
}

int _alphaAt(Uint8List rgba, int width, int x, int y) =>
    rgba[(y * width + x) * 4 + 3];
int _redAt(Uint8List rgba, int width, int x, int y) =>
    rgba[(y * width + x) * 4];

MediaHandle handleOf(Uint8List bytes) =>
    MediaHandle(bytes: bytes, kind: MediaKind.image);

void main() {
  late FakeWebpEncoder webp;
  late StaticEncoder encoder;

  setUp(() {
    webp = FakeWebpEncoder();
    encoder = StaticEncoder(webp);
  });

  test('produces a 512x512 static sticker from a landscape image', () async {
    final out = await encoder.encode(
      handleOf(solidPng(1024, 768)),
      const EncodeParams(fitMode: FitMode.pad),
    );
    expect(out.width, 512);
    expect(out.height, 512);
    expect(out.kind, StickerKind.staticImage);
    expect(out.report.frames, 1);
  });

  test('pad letterboxes a portrait: transparent bars, opaque centre', () async {
    await encoder.encode(
      handleOf(solidPng(100, 200)), // 1:2 → fits to 256x512, centred
      const EncodeParams(fitMode: FitMode.pad),
    );
    final rgba = webp.lastRgba!;

    // Left/right bars are transparent; the centre is opaque red.
    expect(
      _alphaAt(rgba, 512, 2, 256),
      0,
      reason: 'left bar should be transparent',
    );
    expect(
      _alphaAt(rgba, 512, 509, 256),
      0,
      reason: 'right bar should be transparent',
    );
    expect(
      _alphaAt(rgba, 512, 256, 256),
      255,
      reason: 'centre should be opaque',
    );
    expect(
      _redAt(rgba, 512, 256, 256),
      255,
      reason: 'centre should be the red content',
    );
  });

  test('smartCrop fills the frame with no transparent padding', () async {
    await encoder.encode(
      handleOf(solidPng(100, 200)),
      const EncodeParams(fitMode: FitMode.smartCrop),
    );
    final rgba = webp.lastRgba!;

    expect(_alphaAt(rgba, 512, 5, 5), 255);
    expect(_alphaAt(rgba, 512, 500, 500), 255);
  });

  test('delegates to the WebpEncoder with the static byte ceiling', () async {
    await encoder.encode(handleOf(solidPng(512, 512)), const EncodeParams());
    expect(webp.lastMaxBytes, WhatsAppSpec.maxStaticBytes);
    expect(webp.lastWidth, 512);
    expect(webp.lastHeight, 512);
  });

  test('passes the encoder result through to the EncodedSticker', () async {
    final webp = FakeWebpEncoder(
      bytes: Uint8List.fromList(List.filled(9000, 1)),
      quality: 65,
    );
    final out = await StaticEncoder(
      webp,
    ).encode(handleOf(solidPng(512, 512)), const EncodeParams());
    expect(out.sizeBytes, 9000);
    expect(out.webpBytes.length, 9000);
    expect(out.report.quality, 65);
  });

  test('throws EncoderException on undecodable input', () async {
    expect(
      () => encoder.encode(
        handleOf(Uint8List.fromList([1, 2, 3])),
        const EncodeParams(),
      ),
      throwsA(isA<EncoderException>()),
    );
  });
}
