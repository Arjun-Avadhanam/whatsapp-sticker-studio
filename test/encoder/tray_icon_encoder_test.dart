import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/tray_icon_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/webp_encoder.dart';

/// Records what it was handed so the geometry can be asserted without a device.
class FakeWebpEncoder implements WebpEncoder {
  Uint8List? rgba;
  int? width;
  int? height;
  int? maxBytes;

  @override
  Future<WebpEncodeResult> encode(
    Uint8List rgba, {
    required int width,
    required int height,
    required int maxBytes,
  }) async {
    this.rgba = rgba;
    this.width = width;
    this.height = height;
    this.maxBytes = maxBytes;
    return WebpEncodeResult(bytes: Uint8List.fromList([1, 2, 3]), quality: 90);
  }
}

Uint8List _png(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(10, 200, 90, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late FakeWebpEncoder webp;
  late TrayIconEncoder encoder;

  setUp(() {
    webp = FakeWebpEncoder();
    encoder = TrayIconEncoder(webp);
  });

  test(
    'encodes at 96x96 under the tray ceiling, not the sticker one',
    () async {
      await encoder.encode(_png(400, 400));

      expect(webp.width, WhatsAppSpec.trayDimension);
      expect(webp.height, WhatsAppSpec.trayDimension);
      expect(webp.maxBytes, WhatsAppSpec.maxTrayBytes);
      expect(webp.rgba, hasLength(96 * 96 * 4));
    },
  );

  test('letterboxes a non-square source rather than stretching it', () async {
    await encoder.encode(_png(400, 100)); // wide

    // Top-left must be transparent padding; the centre must be the image.
    final rgba = webp.rgba!;
    int alphaAt(int x, int y) => rgba[(y * 96 + x) * 4 + 3];

    expect(alphaAt(2, 2), 0, reason: 'top bar should be transparent');
    expect(alphaAt(48, 48), 255, reason: 'centre should be opaque');
  });

  test('passes the encoded bytes through', () async {
    expect(await encoder.encode(_png(96, 96)), [1, 2, 3]);
  });

  test('throws EncoderException on undecodable input', () async {
    expect(
      () => encoder.encode(Uint8List.fromList([0, 1, 2])),
      throwsA(isA<EncoderException>()),
    );
  });
}
