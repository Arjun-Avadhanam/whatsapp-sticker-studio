import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/native_webp_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/static_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/tray_icon_encoder.dart';
import 'package:whatsapp_sticker_studio/export/pack_stager.dart';
import 'package:whatsapp_sticker_studio/export/sticker_validator.dart';
import 'package:whatsapp_sticker_studio/export/webp_media_probe.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';

/// Task 11 — proves the export chain end to end **up to the intent**: real
/// encoder output → a pack our own validator accepts → staged exactly where
/// `StickerContentProvider` reads from.
///
/// The intent itself cannot be automated: it hands control to WhatsApp, whose UI
/// belongs to another app and cannot be driven from `integration_test`. That
/// step, and the three open validator questions, are answered by tapping through
/// the debug export screen on the device.
void exportTests() {
  late Directory sources;
  final stager =
      PackStager(); // real app support dir — where the provider looks

  setUp(() async {
    sources = await Directory.systemTemp.createTemp('export_src');
  });

  tearDown(() async {
    if (sources.existsSync()) await sources.delete(recursive: true);
  });

  /// A distinct, sticker-like source image per index.
  Uint8List sourcePng(int i) {
    final image = img.Image(width: 600, height: 400, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(30 + i * 40, 120, 200 - i * 30, 255));
    img.fillCircle(
      image,
      x: 300,
      y: 200,
      radius: 120,
      color: img.ColorRgba8(255, 220, 0, 255),
    );
    return Uint8List.fromList(img.encodePng(image));
  }

  testWidgets('a real encoded pack validates and stages where the provider '
      'reads it', (tester) async {
    final encoder = StaticEncoder(NativeWebpEncoder());
    final trayEncoder = TrayIconEncoder(NativeWebpEncoder());

    // 1. Encode three genuine stickers plus a tray icon.
    final stickers = <StickerRecord>[];
    for (var i = 0; i < 3; i++) {
      final encoded = await encoder.encode(
        MediaHandle(
          bytes: sourcePng(i),
          kind: MediaKind.image,
          mimeType: 'image/png',
        ),
        const EncodeParams(fitMode: FitMode.pad),
      );
      final file = File(p.join(sources.path, 'sticker_$i.webp'));
      await file.writeAsBytes(encoded.webpBytes);

      stickers.add(
        StickerRecord(
          id: 's$i',
          filePath: file.path,
          thumbnailPath: file.path,
          kind: StickerKind.staticImage,
          packId: 'device-pack',
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

    final trayBytes = await trayEncoder.encode(sourcePng(0));
    final trayFile = File(p.join(sources.path, 'tray.webp'));
    await trayFile.writeAsBytes(trayBytes);
    expect(
      trayBytes.length,
      lessThanOrEqualTo(WhatsAppSpec.maxTrayBytes),
      reason: 'tray icon over its 50 KB ceiling',
    );

    final pack = PackRecord(
      id: 'device-pack',
      name: 'Device Test Pack',
      trayIconPath: trayFile.path,
      isAnimated: false,
      stickerIds: stickers.map((s) => s.id).toList(),
      createdAt: DateTime(2026),
    );

    // 2. Our own validator must accept it before WhatsApp ever sees it.
    final validation = await StickerValidator(
      const WebpMediaProbe(),
    ).validatePack(pack, stickers);
    expect(
      validation.ok,
      isTrue,
      reason: 'encoder output failed our validator: ${validation.problems}',
    );

    // 3. Stage it, and confirm the layout the provider hard-codes.
    final dir = await stager.stage(pack, stickers);
    expect(p.basename(dir.parent.path), 'sticker_packs');
    expect(File(p.join(dir.path, PackStager.trayName)).existsSync(), isTrue);
    for (final s in stickers) {
      expect(File(p.join(dir.path, '${s.id}.webp')).existsSync(), isTrue);
    }

    final manifest =
        jsonDecode(
              await File(
                p.join(dir.path, PackStager.manifestName),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(manifest['identifier'], 'device-pack');
    expect(manifest['animated_sticker_pack'], isFalse);
    expect((manifest['stickers'] as List), hasLength(3));
  });
}
