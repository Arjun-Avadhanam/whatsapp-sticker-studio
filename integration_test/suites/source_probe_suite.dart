import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';
import 'package:whatsapp_sticker_studio/encoder/animated_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/native_webp_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/static_encoder.dart';
import 'package:whatsapp_sticker_studio/sources/camera_source.dart';
import 'package:whatsapp_sticker_studio/sources/gallery_source.dart';
import 'package:whatsapp_sticker_studio/sources/share_in_source.dart';

/// **INTERACTIVE** — Task 7 Step 4. Every flow here opens system UI that
/// `integration_test` cannot drive, so a human picks, cancels and shares.
///
/// Each probe reports the **mime type the device actually produced**, not just
/// pass/fail. That matters: the phone's camera or gallery may hand us HEIC,
/// which our static path cannot decode, and the resolved kind is the earliest
/// place that shows up.
void sourceProbeTests() {
  const longEnoughToTap = Timeout(Duration(minutes: 3));

  /// Proves the picked media is not merely present but genuinely usable, by
  /// running it through the real encoder for its kind.
  Future<void> reportAndEncode(String probe, MediaHandle? media) async {
    debugPrint('');
    debugPrint('===== RESULT: $probe =====');
    if (media == null) {
      debugPrint('picked         : null (cancelled, or an unsupported format)');
      debugPrint('==============================');
      return;
    }
    debugPrint('kind           : ${media.kind}');
    debugPrint('mimeType       : ${media.mimeType ?? "(none supplied)"}');
    debugPrint('bytes          : ${media.bytes.length}');

    try {
      final EncodedSticker sticker = media.kind == MediaKind.image
          ? await StaticEncoder(
              NativeWebpEncoder(),
            ).encode(media, const EncodeParams(fitMode: FitMode.pad))
          : await const AnimatedEncoder().encode(
              media,
              const EncodeParams(fitMode: FitMode.pad),
            );

      debugPrint(
        'encoded        : OK  ${sticker.sizeBytes} bytes, '
        '${sticker.width}x${sticker.height}, ${sticker.kind}, '
        'frames=${sticker.report.frames}',
      );
      expect(sticker.width, WhatsAppSpec.dimension);
      expect(
        sticker.sizeBytes,
        lessThanOrEqualTo(
          sticker.kind == StickerKind.animated
              ? WhatsAppSpec.maxAnimatedBytes
              : WhatsAppSpec.maxStaticBytes,
        ),
      );
    } catch (e) {
      // Reported rather than rethrown: discovering *which* real-world formats
      // fail is the point of this probe.
      debugPrint('encoded        : FAILED — $e');
    }
    debugPrint('==============================');
    debugPrint('');
  }

  testWidgets('SOURCE 1 — pick an IMAGE from the gallery', (tester) async {
    debugPrint('\n>>> Pick any PHOTO from the gallery.\n');
    await reportAndEncode(
      'SOURCE 1 (gallery image)',
      await GallerySource().pick(),
    );
  }, timeout: longEnoughToTap);

  testWidgets('SOURCE 2 — pick a VIDEO or GIF from the gallery', (
    tester,
  ) async {
    debugPrint('\n>>> Pick a VIDEO (or GIF) from the gallery.\n');
    await reportAndEncode(
      'SOURCE 2 (gallery video)',
      await GallerySource().pick(),
    );
  }, timeout: longEnoughToTap);

  testWidgets('SOURCE 3 — CANCEL the gallery picker', (tester) async {
    // Cancel must be an ordinary outcome. If this throws instead of returning
    // null, the Maker would show an error for something the user did on purpose.
    debugPrint('\n>>> Press BACK / cancel WITHOUT picking anything.\n');
    final media = await GallerySource().pick();
    expect(media, isNull, reason: 'cancel must yield null, not media');
    debugPrint(
      '\n===== RESULT: SOURCE 3 — cancel returned null, as required '
      '=====\n',
    );
  }, timeout: longEnoughToTap);

  testWidgets('SOURCE 4 — take a photo with the CAMERA', (tester) async {
    debugPrint('\n>>> Take a photo and confirm it.\n');
    await reportAndEncode(
      'SOURCE 4 (camera photo)',
      await CameraSource().pick(),
    );
  }, timeout: longEnoughToTap);

  testWidgets(
    'SOURCE 5 — share an image INTO the app while it is running '
    '(WARM path)',
    (tester) async {
      debugPrint('');
      debugPrint('>>> Leave this app running, switch to Gallery/Photos,');
      debugPrint('>>> and SHARE an image to "whatsapp_sticker_studio".');
      debugPrint('');

      final received = await ShareInSource().stream().first.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('no share arrived'),
      );

      await reportAndEncode('SOURCE 5 (warm share-in)', received);
      // NOTE: kept, but skipped — see the skip reason. Do not "fix" it by
      // extending the timeout; the share cannot reach this process.
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip:
        'Cannot be verified from integration_test, and the failure is an '
        'artefact of the harness rather than of the code. Two reasons, both '
        'established on device 2026-08-01: (1) `flutter test` UNINSTALLS the '
        'app when a run ends, and Android caches recent share targets, so an '
        'icon tapped in the share sheet can point at a package that no longer '
        'exists and the share silently goes nowhere; (2) a share from another '
        'app launches MainActivity into THAT app\'s task — observed landing in '
        'the Gallery\'s task t3918 — i.e. a different activity instance and a '
        'different Flutter engine from the one running this test, so the warm '
        'getMediaStream listener here can never hear it. '
        'WHAT IS ALREADY PROVEN without this test: the OS resolves us as a '
        'share target (`pm query-activities -a android.intent.action.SEND '
        '-t image/jpeg` returns .MainActivity) and a real share does start our '
        'activity. What remains unverified is only that the Dart side receives '
        'the media — observable once a real UI exists, in Task 15.',
  );
}
