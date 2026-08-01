import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/export/pack_stager.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';

void main() {
  late Directory tmp;
  late PackStager stager;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stager');
    stager = PackStager(baseDir: tmp);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Source files the stager copies from — content is irrelevant here, only
  /// that the right bytes land at the right names.
  String writeSource(String name, String content) {
    final f = File(p.join(tmp.path, name))..writeAsStringSync(content);
    return f.path;
  }

  PackRecord packOf(int count, {bool isAnimated = false}) => PackRecord(
    id: 'pack-1',
    name: 'My Pack',
    trayIconPath: writeSource('tray_src.webp', 'TRAY'),
    isAnimated: isAnimated,
    stickerIds: List.generate(count, (i) => 's$i'),
    createdAt: DateTime(2026),
  );

  List<StickerRecord> stickersOf(int count) => List.generate(
    count,
    (i) => StickerRecord(
      id: 's$i',
      filePath: writeSource('src_s$i.webp', 'STICKER$i'),
      thumbnailPath: '/tmp/t.webp',
      kind: StickerKind.staticImage,
      packId: 'pack-1',
      autoTags: const [],
      manualName: 'Sticker $i',
      manualTags: const [],
      notes: null,
      source: StickerSource.maker,
      createdAt: DateTime(2026),
      usageCount: 0,
      sizeBytes: 50000,
      taggingStatus: TaggingStatus.done,
    ),
  );

  Future<Map<String, dynamic>> readManifest(Directory dir) async {
    final raw = await File(
      p.join(dir.path, PackStager.manifestName),
    ).readAsString();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  test(
    'writes the manifest, tray and every sticker where the provider looks',
    () async {
      final dir = await stager.stage(packOf(3), stickersOf(3));

      // The provider resolves <base>/sticker_packs/<identifier>/…
      expect(p.basename(dir.path), 'pack-1');
      expect(p.basename(dir.parent.path), 'sticker_packs');

      expect(
        File(p.join(dir.path, PackStager.trayName)).readAsStringSync(),
        'TRAY',
      );
      for (var i = 0; i < 3; i++) {
        expect(
          File(p.join(dir.path, 's$i.webp')).readAsStringSync(),
          'STICKER$i',
        );
      }

      final manifest = await readManifest(dir);
      expect(manifest['identifier'], 'pack-1');
      expect(manifest['name'], 'My Pack');
      expect(manifest['tray_image_file'], PackStager.trayName);
      expect((manifest['stickers'] as List), hasLength(3));
      expect((manifest['stickers'] as List).first['image_file'], 's0.webp');
    },
  );

  test('animated_sticker_pack mirrors the pack flag', () async {
    final dir = await stager.stage(packOf(3, isAnimated: true), stickersOf(3));
    expect((await readManifest(dir))['animated_sticker_pack'], isTrue);
  });

  test('re-staging bumps image_data_version', () async {
    // The only signal WhatsApp has that the art changed.
    var dir = await stager.stage(packOf(3), stickersOf(3));
    expect((await readManifest(dir))['image_data_version'], '1');

    dir = await stager.stage(packOf(3), stickersOf(3));
    expect((await readManifest(dir))['image_data_version'], '2');
  });

  test('a sticker dropped from the pack stops being served', () async {
    await stager.stage(packOf(3), stickersOf(3));
    final dir = await stager.stage(packOf(2), stickersOf(2));

    // A stale file left behind would still be reachable through the provider.
    expect(File(p.join(dir.path, 's2.webp')).existsSync(), isFalse);
    expect((await readManifest(dir))['stickers'], hasLength(2));
  });
}
