import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/encoder/animated_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/native_webp_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/static_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/tray_icon_encoder.dart';
import 'package:whatsapp_sticker_studio/export/exporter.dart';
import 'package:whatsapp_sticker_studio/export/pack_stager.dart';
import 'package:whatsapp_sticker_studio/export/sticker_validator.dart';
import 'package:whatsapp_sticker_studio/export/webp_media_probe.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';

import 'suites/sharing_probe_suite.dart';
import 'suites/source_probe_suite.dart';

/// **INTERACTIVE — requires a human to tap WhatsApp's confirmation dialog.**
///
/// Deliberately a separate entry point from `device_test.dart`: these tests hand
/// control to WhatsApp and block until someone taps Add or Cancel, so they would
/// hang forever in CI. Never register them in the automated suite.
///
///     adb forward --remove-all
///     flutter test integration_test/interactive_test.dart -d <device-id>
///
/// Purpose is **discovery, not regression**. WhatsApp's validator is
/// closed-source and stricter than its published sample, so several probes below
/// assert nothing — they print a RESULT block, and the answers get written into
/// `CLAUDE.md` against the WhatsApp version they were observed on.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const longEnoughToTap = Timeout(Duration(minutes: 3));
  final stager = PackStager();
  final channel = PlatformStickerChannel();
  const authority = 'com.arjun.whatsapp_sticker_studio.stickercontentprovider';

  late Directory sources;

  setUp(() async {
    sources = await Directory.systemTemp.createTemp('interactive');
  });

  tearDown(() async {
    if (sources.existsSync()) await sources.delete(recursive: true);
  });

  Uint8List sourcePng(int i) {
    final image = img.Image(width: 600, height: 400, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(30 + i * 50, 120, 200 - i * 40, 255));
    img.fillCircle(
      image,
      x: 200 + i * 60,
      y: 200,
      radius: 110,
      color: img.ColorRgba8(255, 220, 0, 255),
    );
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Builds and stages a pack, returning it with its stickers.
  ///
  /// [promoteStatics] runs each sticker through `AnimatedEncoder.promoteStatic`,
  /// which is the whole point of probe 3.
  Future<(PackRecord, List<StickerRecord>)> buildPack({
    required String id,
    required String name,
    required int count,
    bool animated = false,
    bool promoteStatics = false,
  }) async {
    final static = StaticEncoder(NativeWebpEncoder());
    final trayEncoder = TrayIconEncoder(NativeWebpEncoder());
    const animatedEncoder = AnimatedEncoder();

    final stickers = <StickerRecord>[];
    for (var i = 0; i < count; i++) {
      final still = await static.encode(
        MediaHandle(
          bytes: sourcePng(i),
          kind: MediaKind.image,
          mimeType: 'image/png',
        ),
        const EncodeParams(fitMode: FitMode.pad),
      );

      final EncodedSticker encoded = promoteStatics
          ? await animatedEncoder.promoteStatic(still.webpBytes)
          : still;

      final file = File(p.join(sources.path, '${id}_$i.webp'));
      await file.writeAsBytes(encoded.webpBytes);

      stickers.add(
        StickerRecord(
          id: 's$i',
          filePath: file.path,
          thumbnailPath: file.path,
          kind: encoded.kind,
          packId: id,
          autoTags: const [],
          manualName: 'Sticker $i',
          manualTags: const [],
          notes: null,
          source: StickerSource.maker,
          createdAt: DateTime(2026),
          usageCount: 0,
          sizeBytes: encoded.sizeBytes,
          taggingStatus: TaggingStatus.done,
        ),
      );
    }

    final trayFile = File(p.join(sources.path, '${id}_tray.webp'));
    await trayFile.writeAsBytes(await trayEncoder.encode(sourcePng(0)));

    final pack = PackRecord(
      id: id,
      name: name,
      trayIconPath: trayFile.path,
      isAnimated: animated,
      stickerIds: stickers.map((s) => s.id).toList(),
      createdAt: DateTime(2026),
    );

    await stager.stage(pack, stickers);
    return (pack, stickers);
  }

  /// Fires the intent **without** our validator.
  ///
  /// Probes 2a/2b deliberately export packs our own `StickerValidator` would
  /// reject — that gate is exactly what is under test, so going through
  /// `WhatsAppExporter` would block the experiment before WhatsApp ever saw it.
  Future<StickerExportResult> fireRaw(PackRecord pack) {
    return channel.enableStickerPack(
      identifier: pack.id,
      authority: authority,
      name: pack.name,
    );
  }

  void report(String probe, String question, StickerExportResult r) {
    debugPrint('');
    debugPrint('===== RESULT: $probe =====');
    debugPrint('question       : $question');
    debugPrint('added          : ${r.added}');
    debugPrint('validationError: ${r.validationError ?? "(none)"}');
    debugPrint('==============================');
    debugPrint('');
  }

  testWidgets('PROBE 1 — a valid 3-sticker static pack installs', (
    tester,
  ) async {
    debugPrint('\n>>> TAP "ADD" in WhatsApp when the dialog appears.\n');
    final (pack, stickers) = await buildPack(
      id: 'probe-valid-3',
      name: 'Probe Valid 3',
      count: 3,
    );

    // Goes through the real exporter, so our own gate is exercised too.
    final exporter = WhatsAppExporter(
      validator: StickerValidator(const WebpMediaProbe()),
      channel: channel,
      authority: authority,
    );
    await exporter.addPackToWhatsApp(pack, stickers);

    debugPrint('\n===== RESULT: PROBE 1 — pack was accepted =====\n');
  }, timeout: longEnoughToTap);

  testWidgets(
    'PROBE 2a — is the 3-sticker minimum enforced? (2 stickers)',
    (tester) async {
      debugPrint(
        '\n>>> TAP "ADD" in WhatsApp. If it refuses, that answers it.\n',
      );
      final (pack, _) = await buildPack(
        id: 'probe-two',
        name: 'Probe Two Stickers',
        count: 2,
      );
      report(
        'PROBE 2a (2 stickers)',
        'is the documented 3-sticker minimum actually enforced?',
        await fireRaw(pack),
      );
    },
    timeout: longEnoughToTap,
  );

  testWidgets(
    'PROBE 2b — is the 3-sticker minimum enforced? (1 sticker)',
    (tester) async {
      debugPrint(
        '\n>>> TAP "ADD" in WhatsApp. If it refuses, that answers it.\n',
      );
      final (pack, _) = await buildPack(
        id: 'probe-one',
        name: 'Probe One Sticker',
        count: 1,
      );
      report(
        'PROBE 2b (1 sticker)',
        'is the documented 3-sticker minimum actually enforced?',
        await fireRaw(pack),
      );
    },
    timeout: longEnoughToTap,
  );

  testWidgets('PROBE 3 — does >=2-identical-frame promotion survive the '
      'closed-source validator?', (tester) async {
    // THE decisive one. A rejection here means falling back to
    // pack-type-chosen-at-creation and reworking Task 13 before any UI exists.
    debugPrint('\n>>> TAP "ADD" in WhatsApp. This is the decisive probe.\n');
    final (pack, _) = await buildPack(
      id: 'probe-promoted',
      name: 'Probe Promoted',
      count: 3,
      animated: true,
      promoteStatics: true,
    );
    report(
      'PROBE 3 (promoted statics in an animated pack)',
      'does the >=2-identical-frame promotion pass WhatsApp validation?',
      await fireRaw(pack),
    );
  }, timeout: longEnoughToTap);

  group('sources (Task 7)', sourceProbeTests);

  group('sharing (Task 12)', sharingProbeTests);
}
