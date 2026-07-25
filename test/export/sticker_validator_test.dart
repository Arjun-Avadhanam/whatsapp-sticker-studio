import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/export/media_probe.dart';
import 'package:whatsapp_sticker_studio/export/sticker_validator.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';

/// Returns a fixed [ProbeResult] regardless of path, so validator tests need no
/// real files. Defaults to a compliant 512x512 WebP; override to simulate a
/// wrong-sized or wrong-format file.
class FakeMediaProbe implements MediaProbe {
  FakeMediaProbe({this.width = 512, this.height = 512, this.format = 'webp'});

  final int width;
  final int height;
  final String format;

  @override
  Future<ProbeResult> probe(String filePath) async =>
      ProbeResult(width: width, height: height, format: format);
}

StickerRecord stickerOf(
  int bytes,
  StickerKind kind, {
  String id = 's',
  String path = 'x.webp',
}) => StickerRecord(
  id: id,
  filePath: path,
  thumbnailPath: '${id}_t.webp',
  kind: kind,
  packId: null,
  autoTags: const [],
  manualName: null,
  manualTags: const [],
  notes: null,
  source: StickerSource.maker,
  createdAt: DateTime(2026),
  usageCount: 0,
  sizeBytes: bytes,
  taggingStatus: TaggingStatus.done,
);

List<StickerRecord> stickersOf(
  int count, {
  int bytes = 50000,
  StickerKind kind = StickerKind.staticImage,
}) => List.generate(count, (i) => stickerOf(bytes, kind, id: 's$i'));

PackRecord packOf(int count, {bool isAnimated = false}) => PackRecord(
  id: 'p1',
  name: 'Pack',
  trayIconPath: 'tray.webp',
  isAnimated: isAnimated,
  stickerIds: List.generate(count, (i) => 's$i'),
  createdAt: DateTime(2026),
);

void main() {
  late StickerValidator v;
  setUp(() => v = StickerValidator(FakeMediaProbe()));

  group('validateSticker size ceilings', () {
    test('animated sticker over 500KB fails', () async {
      final r = await v.validateSticker(
        stickerOf(600000, StickerKind.animated),
      );
      expect(r.ok, isFalse);
    });

    test('static sticker over 100KB fails', () async {
      final r = await v.validateSticker(
        stickerOf(150000, StickerKind.staticImage),
      );
      expect(r.ok, isFalse);
    });

    test('sticker within its ceiling passes', () async {
      expect(
        (await v.validateSticker(stickerOf(50000, StickerKind.staticImage))).ok,
        isTrue,
      );
    });
  });

  group('validateSticker probes the real file', () {
    test('non-512 dimensions fail', () async {
      final v = StickerValidator(FakeMediaProbe(width: 500));
      final r = await v.validateSticker(
        stickerOf(50000, StickerKind.staticImage),
      );
      expect(r.ok, isFalse);
      expect(r.problems.any((p) => p.contains('512')), isTrue);
    });

    test('non-webp format fails', () async {
      final v = StickerValidator(FakeMediaProbe(format: 'png'));
      final r = await v.validateSticker(
        stickerOf(50000, StickerKind.staticImage),
      );
      expect(r.ok, isFalse);
      expect(r.problems.any((p) => p.toLowerCase().contains('webp')), isTrue);
    });
  });

  group('validatePack count', () {
    test('fewer than 3 stickers fails with a helpful message', () async {
      final r = await v.validatePack(packOf(2), stickersOf(2));
      expect(r.ok, isFalse);
      expect(r.problems.any((p) => p.contains('at least 3')), isTrue);
    });

    test('more than 30 stickers fails', () async {
      final r = await v.validatePack(packOf(31), stickersOf(31));
      expect(r.ok, isFalse);
    });

    test('a valid static pack passes with no problems', () async {
      final r = await v.validatePack(packOf(5), stickersOf(5));
      expect(r.ok, isTrue);
      expect(r.problems, isEmpty);
    });
  });

  group('validatePack kind homogeneity', () {
    test('animated pack containing a static sticker fails', () async {
      final r = await v.validatePack(packOf(3, isAnimated: true), [
        stickerOf(400000, StickerKind.animated, id: 's0'),
        stickerOf(400000, StickerKind.animated, id: 's1'),
        stickerOf(50000, StickerKind.staticImage, id: 's2'), // intruder
      ]);
      expect(r.ok, isFalse);
      expect(r.problems.any((p) => p.contains('animated')), isTrue);
    });

    test('static pack containing an animated sticker fails', () async {
      final r = await v.validatePack(packOf(3, isAnimated: false), [
        stickerOf(50000, StickerKind.staticImage, id: 's0'),
        stickerOf(50000, StickerKind.staticImage, id: 's1'),
        stickerOf(400000, StickerKind.animated, id: 's2'),
      ]);
      expect(r.ok, isFalse);
    });

    test('a valid animated pack passes', () async {
      final r = await v.validatePack(
        packOf(3, isAnimated: true),
        stickersOf(3, bytes: 400000, kind: StickerKind.animated),
      );
      expect(r.ok, isTrue);
      expect(r.problems, isEmpty);
    });
  });

  group('validatePack collects all problems', () {
    test('does not short-circuit on the first failure', () async {
      // Count < 3 AND one sticker over the animated ceiling → at least 2 distinct problems.
      final r = await v.validatePack(packOf(2, isAnimated: true), [
        stickerOf(600000, StickerKind.animated, id: 's0'),
        stickerOf(400000, StickerKind.animated, id: 's1'),
      ]);
      expect(r.problems.length, greaterThanOrEqualTo(2));
    });
  });
}
