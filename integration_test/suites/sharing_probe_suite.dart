import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/native_webp_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/static_encoder.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/sharing/sharing_service.dart';

/// **INTERACTIVE** — Task 12 Step 4. The share sheet is system UI that
/// `integration_test` cannot drive, so a human picks a target or backs out.
///
/// Two questions, both of which shape decisions already made in code:
///
///  1. **Which `ShareResultStatus` does Android actually return?** Our usage
///     rule counts `success` and `unavailable` but never `dismissed`. If Android
///     reports `unavailable` routinely, that branch is load-bearing and mild
///     over-counting is the price of having a ranking signal at all. If it
///     reports precisely, the branch almost never fires and costs nothing.
///
///  2. **Does a shared WebP arrive in WhatsApp as a STICKER or an ordinary
///     image?** The sticker tray is only reachable through the ContentProvider
///     path (Task 11), so a plain file share very likely lands as a photo. That
///     does not make the feature useless — sending the image still works — but
///     it changes what the Maker's UI may promise, so it must be known before
///     Task 13 writes that copy.
void sharingProbeTests() {
  const longEnoughToTap = Timeout(Duration(minutes: 3));

  late AppDatabase db;
  late LibraryStore store;
  late Directory work;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLibraryStore(db);
    work = await Directory.systemTemp.createTemp('share_probe');
  });

  tearDown(() async {
    await db.close();
    if (work.existsSync()) await work.delete(recursive: true);
  });

  /// A real encoded sticker on disk — not a placeholder, so the share sheet
  /// gets exactly what the app would really send.
  Future<StickerRecord> realSticker() async {
    final source = img.Image(width: 600, height: 400, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(40, 130, 210, 255));
    img.fillCircle(
      source,
      x: 300,
      y: 200,
      radius: 130,
      color: img.ColorRgba8(255, 220, 0, 255),
    );

    final encoded = await StaticEncoder(NativeWebpEncoder()).encode(
      MediaHandle(
        bytes: Uint8List.fromList(img.encodePng(source)),
        kind: MediaKind.image,
        mimeType: 'image/png',
      ),
      const EncodeParams(fitMode: FitMode.pad),
    );

    final file = File(p.join(work.path, 'probe_sticker.webp'));
    await file.writeAsBytes(encoded.webpBytes);

    final record = StickerRecord(
      id: 'share-probe',
      filePath: file.path,
      thumbnailPath: file.path,
      kind: StickerKind.staticImage,
      packId: null,
      autoTags: const ['probe'],
      manualName: 'Share Probe',
      manualTags: const [],
      notes: null,
      source: StickerSource.maker,
      createdAt: DateTime(2026),
      usageCount: 0,
      sizeBytes: encoded.sizeBytes,
      taggingStatus: TaggingStatus.done,
    );
    await store.saveSticker(record);
    return record;
  }

  Future<void> report(String probe, ShareOutcome outcome, String id) async {
    final usage = (await store.getSticker(id))!.usageCount;
    debugPrint('');
    debugPrint('===== RESULT: $probe =====');
    debugPrint('ShareOutcome : $outcome');
    debugPrint('usageCount   : $usage');
    debugPrint('==============================');
    debugPrint('');
  }

  testWidgets(
    'SHARE 1 — COMPLETE a share and see what Android reports',
    (tester) async {
      debugPrint('');
      debugPrint('>>> Pick WhatsApp (or any target) and COMPLETE the share.');
      debugPrint('>>> Then check WhatsApp: did it arrive as a STICKER or a');
      debugPrint('>>> normal IMAGE in the chat? That answers question 2.');
      debugPrint('');

      final sticker = await realSticker();
      final outcome = await SharingService(
        const PlatformShareBackend(),
        store,
      ).shareSticker(sticker);

      await report('SHARE 1 (completed)', outcome, sticker.id);

      if (outcome == ShareOutcome.unknown) {
        debugPrint(
          '>>> FINDING: Android reports `unavailable` — it cannot tell what the '
          'user did. Our decision to count it as a send is therefore '
          'load-bearing: without it usageCount would never move and the search '
          'ranking signal would be dead. Record in CLAUDE.md.',
        );
      }
    },
    timeout: longEnoughToTap,
  );

  testWidgets('SHARE 2 — DISMISS the sheet; usage must not move', (
    tester,
  ) async {
    debugPrint('');
    debugPrint('>>> Press BACK / dismiss WITHOUT choosing a target.');
    debugPrint('');

    final sticker = await realSticker();
    final outcome = await SharingService(
      const PlatformShareBackend(),
      store,
    ).shareSticker(sticker);

    await report('SHARE 2 (dismissed)', outcome, sticker.id);

    // Only meaningful if Android actually distinguished the dismissal. When it
    // reports `unavailable` we cannot tell, and counting is the deliberate
    // choice — so assert only in the case where the platform was precise.
    if (outcome == ShareOutcome.dismissed) {
      expect(
        (await store.getSticker(sticker.id))!.usageCount,
        0,
        reason: 'a dismissed share must not inflate the ranking signal',
      );
    } else {
      debugPrint(
        '>>> NOTE: Android did not report a dismissal ($outcome), so usage '
        'counting cannot distinguish it here. See the decision in CLAUDE.md.',
      );
    }
  }, timeout: longEnoughToTap);
}
