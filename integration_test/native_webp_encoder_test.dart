import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/native_webp_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/static_encoder.dart';
import 'package:whatsapp_sticker_studio/export/webp_media_probe.dart';

/// Device-only verification of Task 5b: the native encoder really does emit a
/// WhatsApp-compliant WebP.
///
/// The unit tests prove the *geometry* against a fake and the *channel contract*
/// against a mock — neither can prove that Android produced valid WebP bytes.
/// That claim needs real hardware, so it lives here. Run with:
///
///     flutter test integration_test/native_webp_encoder_test.dart -d <device-id>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final encoder = StaticEncoder(NativeWebpEncoder());
  const probe = WebpMediaProbe();

  /// A deliberately incompressible image: seeded per-pixel noise. A flat colour
  /// would shrink to a few hundred bytes and quietly pass every size assertion
  /// without the quality ladder ever being exercised.
  MediaHandle noisyPng(int width, int height) {
    final rng = math.Random(42);
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgba(
          x,
          y,
          rng.nextInt(256),
          rng.nextInt(256),
          rng.nextInt(256),
          255,
        );
      }
    }
    return MediaHandle(
      bytes: Uint8List.fromList(img.encodePng(image)),
      kind: MediaKind.image,
      mimeType: 'image/png',
    );
  }

  /// A photo-like image: smooth gradients and banding (structure the codec can
  /// model) overlaid with fine grain (expensive to keep at high quality, cheap
  /// to discard at low). Unlike pure noise, this compresses once quality drops.
  MediaHandle texturedPng(int width, int height) {
    final rng = math.Random(7);
    final image = img.Image(width: width, height: height, numChannels: 4);
    int clamp(num v) => v.clamp(0, 255).toInt();

    for (var y = 0; y < height; y++) {
      final band = math.sin(y / 6) * 40;
      for (var x = 0; x < width; x++) {
        final base = x * 255 / width;
        final grain = rng.nextInt(50) - 25;
        image.setPixelRgba(
          x,
          y,
          clamp(base + grain),
          clamp(200 - base / 2 + band + grain),
          clamp(128 + band + grain),
          255,
        );
      }
    }
    return MediaHandle(
      bytes: Uint8List.fromList(img.encodePng(image)),
      kind: MediaKind.image,
      mimeType: 'image/png',
    );
  }

  /// Probing reads a real file header, so the bytes have to hit disk first.
  Future<String> writeTemp(Uint8List bytes, String name) async {
    final file = File('${Directory.systemTemp.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  testWidgets('produces a real 512x512 WebP within the static ceiling', (
    tester,
  ) async {
    final sticker = await encoder.encode(
      noisyPng(900, 600),
      const EncodeParams(fitMode: FitMode.pad),
    );

    // The header must say WebP 512x512 — not merely our record claiming so.
    final path = await writeTemp(sticker.webpBytes, 'probe_pad.webp');
    final probed = await probe.probe(path);

    expect(probed.format, 'webp');
    expect(probed.width, WhatsAppSpec.dimension);
    expect(probed.height, WhatsAppSpec.dimension);
    expect(sticker.sizeBytes, lessThanOrEqualTo(WhatsAppSpec.maxStaticBytes));
    expect(sticker.kind, StickerKind.staticImage);
    expect(sticker.report.frames, 1);
  });

  testWidgets('pad keeps its letterbox bars transparent', (tester) async {
    // The real risk in using Android's encoder: lossy WebP must carry the alpha
    // channel through. If it flattens alpha, padding turns black and every
    // padded sticker ships with ugly bars.
    final sticker = await encoder.encode(
      noisyPng(400, 900), // portrait -> bars on the left and right
      const EncodeParams(fitMode: FitMode.pad),
    );

    final decoded = img.decodeWebP(sticker.webpBytes);
    expect(decoded, isNotNull, reason: 'output must be decodable WebP');

    expect(
      decoded!.getPixel(2, WhatsAppSpec.dimension ~/ 2).a,
      0,
      reason: 'left bar should be fully transparent',
    );
    expect(
      decoded
          .getPixel(WhatsAppSpec.dimension ~/ 2, WhatsAppSpec.dimension ~/ 2)
          .a,
      255,
      reason: 'the subject in the centre should stay opaque',
    );
  });

  testWidgets('steps quality down when the source will not fit at 100', (
    tester,
  ) async {
    // Photo-like: smooth structure carrying fine grain. Too costly to store at
    // quality 100, but the grain quantises away lower down — so a pass here
    // proves the ladder actually descended rather than fitting on the first try.
    final sticker = await encoder.encode(
      texturedPng(1400, 1400),
      const EncodeParams(fitMode: FitMode.smartCrop),
    );

    expect(sticker.sizeBytes, lessThanOrEqualTo(WhatsAppSpec.maxStaticBytes));
    expect(
      sticker.report.quality,
      lessThan(100),
      reason: 'detailed input must have forced a lower quality',
    );
  });

  testWidgets('refuses to emit an oversize sticker when even the floor is too '
      'big', (tester) async {
    // Uniform random noise is maximum-entropy — no spatial correlation for the
    // codec to exploit, so it will not fit under 100 KB at any quality we allow.
    // Verified on device: the smallest result was ~139 KB at quality 50.
    //
    // Real photographs always carry structure and land far below the ceiling,
    // so this is the pathological case, not a common one. It is pinned because
    // the *behaviour* matters: overshooting silently would surface later as an
    // opaque WhatsApp rejection at export, long after the user made the sticker.
    expect(
      () => encoder.encode(
        noisyPng(1400, 1400),
        const EncodeParams(fitMode: FitMode.smartCrop),
      ),
      throwsA(
        isA<EncoderException>().having(
          (e) => e.message,
          'message',
          contains('cannot fit'),
        ),
      ),
    );
  });
}
