import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/export/exporter.dart';
import 'package:whatsapp_sticker_studio/export/media_probe.dart';
import 'package:whatsapp_sticker_studio/export/sticker_validator.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';

/// Always reports a compliant 512×512 WebP, so these tests exercise the
/// *export gate* rather than re-testing Task 4's file probing.
class FakeMediaProbe implements MediaProbe {
  @override
  Future<ProbeResult> probe(String filePath) async =>
      const ProbeResult(width: 512, height: 512, format: 'webp');
}

/// Stands in for the platform side, recording what would have been fired.
class FakeStickerChannel implements StickerChannel {
  final List<Map<String, String>> intentsFired = [];
  String? validationError;
  bool added = true;

  @override
  Future<StickerExportResult> enableStickerPack({
    required String identifier,
    required String authority,
    required String name,
  }) async {
    intentsFired.add({
      'identifier': identifier,
      'authority': authority,
      'name': name,
    });
    return StickerExportResult(added: added, validationError: validationError);
  }
}

StickerRecord _sticker(String id, {required StickerKind kind, int? bytes}) {
  return StickerRecord(
    id: id,
    filePath: '/tmp/$id.webp',
    thumbnailPath: '/tmp/$id.thumb.webp',
    kind: kind,
    packId: 'pack-1',
    autoTags: const [],
    manualName: null,
    manualTags: const [],
    notes: null,
    source: StickerSource.maker,
    createdAt: DateTime(2026),
    usageCount: 0,
    sizeBytes: bytes ?? (kind == StickerKind.animated ? 400000 : 50000),
    taggingStatus: TaggingStatus.done,
  );
}

PackRecord _pack(int count, {bool isAnimated = false}) {
  return PackRecord(
    id: 'pack-1',
    name: 'Test Pack',
    trayIconPath: '/tmp/tray.webp',
    isAnimated: isAnimated,
    stickerIds: List.generate(count, (i) => 's$i'),
    createdAt: DateTime(2026),
  );
}

List<StickerRecord> _stickers(int count, {bool animated = false}) {
  return List.generate(
    count,
    (i) => _sticker(
      's$i',
      kind: animated ? StickerKind.animated : StickerKind.staticImage,
    ),
  );
}

void main() {
  late FakeStickerChannel channel;
  late Exporter exporter;

  setUp(() {
    channel = FakeStickerChannel();
    exporter = WhatsAppExporter(
      validator: StickerValidator(FakeMediaProbe()),
      channel: channel,
      authority: 'com.arjun.whatsapp_sticker_studio.stickercontentprovider',
    );
  });

  test('a valid pack fires the intent with the pack identity', () async {
    await exporter.addPackToWhatsApp(_pack(3), _stickers(3));

    expect(channel.intentsFired, hasLength(1));
    expect(channel.intentsFired.single['identifier'], 'pack-1');
    expect(channel.intentsFired.single['name'], 'Test Pack');
    expect(
      channel.intentsFired.single['authority'],
      contains('stickercontent'),
    );
  });

  test('an undersized pack is rejected and NO intent is fired', () async {
    // The gate is the point: firing on an invalid pack trades our specific,
    // actionable problem list for an opaque WhatsApp rejection.
    await expectLater(
      exporter.addPackToWhatsApp(_pack(2), _stickers(2)),
      throwsA(
        isA<PackNotValidException>().having(
          (e) => e.problems.join(' '),
          'problems',
          contains('at least 3'),
        ),
      ),
    );
    expect(channel.intentsFired, isEmpty);
  });

  test('a mixed-kind pack is rejected before reaching WhatsApp', () async {
    // Promotion (Task 6) should mean this never happens; reaching here is a bug
    // in the Maker, not user error — but the gate must still catch it.
    final stickers = [
      ..._stickers(2, animated: true),
      _sticker('s2', kind: StickerKind.staticImage),
    ];

    await expectLater(
      exporter.addPackToWhatsApp(_pack(3, isAnimated: true), stickers),
      throwsA(isA<PackNotValidException>()),
    );
    expect(channel.intentsFired, isEmpty);
  });

  test('every problem is reported, not just the first', () async {
    final stickers = [
      _sticker('s0', kind: StickerKind.staticImage, bytes: 150000), // oversize
      _sticker('s1', kind: StickerKind.staticImage),
    ];

    try {
      await exporter.addPackToWhatsApp(_pack(2), stickers);
      fail('expected PackNotValidException');
    } on PackNotValidException catch (e) {
      expect(e.problems.length, greaterThanOrEqualTo(2));
    }
  });

  test(
    "WhatsApp's own validation_error surfaces as a distinct failure",
    () async {
      // WhatsApp re-validates independently and is stricter than the published
      // sample, so a pack can pass our gate and still be refused. That message is
      // the only diagnostic we get, so it must not be swallowed.
      channel.validationError =
          'pack is marked as animated pack but contains non animated stickers';
      channel.added = false; // WhatsApp returns non-OK alongside the error

      await expectLater(
        exporter.addPackToWhatsApp(_pack(3), _stickers(3)),
        throwsA(
          isA<WhatsAppRejectedException>().having(
            (e) => e.validationError,
            'validationError',
            contains('animated'),
          ),
        ),
      );
    },
  );

  test('backing out of the confirmation is cancellation, not success', () async {
    // A decline yields a non-OK result with no validation_error. Treating that
    // as success would have the app record a pack the user never added.
    channel.added = false;

    await expectLater(
      exporter.addPackToWhatsApp(_pack(3), _stickers(3)),
      throwsA(isA<ExportCancelledException>()),
    );
    expect(channel.intentsFired, hasLength(1));
  });
}
