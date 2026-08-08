import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/export/exporter.dart';
import 'package:whatsapp_sticker_studio/export/pack_export_service.dart';
import 'package:whatsapp_sticker_studio/export/pack_stager.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';

import '../app/test_dependencies.dart';

/// Records what it was handed instead of reaching WhatsApp, and can be told to
/// fail the way each real failure mode does.
class RecordingExporter implements Exporter {
  RecordingExporter({this.throws});

  final Object? throws;
  PackRecord? pack;
  List<StickerRecord>? stickers;

  @override
  Future<void> addPackToWhatsApp(PackRecord p, List<StickerRecord> s) async {
    pack = p;
    stickers = s;
    if (throws != null) throw throws!;
  }
}

/// Runs a callback at the moment the intent would fire.
class ProbeExporter implements Exporter {
  ProbeExporter(this.onExport);
  final Future<void> Function() onExport;

  @override
  Future<void> addPackToWhatsApp(
    PackRecord pack,
    List<StickerRecord> stickers,
  ) => onExport();
}

void main() {
  late AppDatabase db;
  late LibraryStore store;
  late Directory dir;
  late PackStager stager;
  late RecordingExporter exporter;

  Future<StickerRecord> sticker(String id) async {
    File('${dir.path}/$id.webp').writeAsBytesSync(onePixelPng());
    final record = StickerRecord(
      id: id,
      filePath: '${dir.path}/$id.webp',
      thumbnailPath: '${dir.path}/$id.webp',
      kind: StickerKind.staticImage,
      packId: 'pack-1',
      autoTags: const [],
      manualName: 'Sticker $id',
      manualTags: const [],
      notes: null,
      source: StickerSource.maker,
      createdAt: DateTime(2026, 8, 8),
      usageCount: 0,
      sizeBytes: 512,
      taggingStatus: TaggingStatus.done,
    );
    await store.saveSticker(record);
    return record;
  }

  Future<PackRecord> pack(List<String> ids) async {
    File('${dir.path}/tray.webp').writeAsBytesSync(onePixelPng());
    final record = PackRecord(
      id: 'pack-1',
      name: 'Inside jokes',
      trayIconPath: '${dir.path}/tray.webp',
      isAnimated: false,
      stickerIds: ids,
      createdAt: DateTime(2026, 8, 8),
    );
    await store.savePack(record);
    return record;
  }

  PackExportService service() =>
      PackExportService(store: store, stager: stager, exporter: exporter);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLibraryStore(db);
    dir = Directory.systemTemp.createTempSync('export_test');
    stager = PackStager(baseDir: dir);
    exporter = RecordingExporter();
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('stages the pack and hands it to the exporter in order', () async {
    for (final id in ['s3', 's1', 's2']) {
      await sticker(id);
    }
    final p = await pack(['s3', 's1', 's2']);

    await service().addToWhatsApp(p);

    expect(exporter.pack, equals(p));
    // Order is what WhatsApp renders in the tray, so it must survive the
    // id→record lookup rather than arriving in whatever order the query gives.
    expect(exporter.stickers!.map((s) => s.id), ['s3', 's1', 's2']);

    final staged = await stager.packDir(p.id);
    expect(
      File('${staged.path}/${PackStager.manifestName}').existsSync(),
      true,
    );
  });

  test('staging happens BEFORE the intent fires', () async {
    // WhatsApp reads through the ContentProvider as soon as it receives the
    // intent, so firing first would race an empty directory.
    for (final id in ['s1', 's2', 's3']) {
      await sticker(id);
    }
    final p = await pack(['s1', 's2', 's3']);

    var manifestExisted = false;
    final probing = PackExportService(
      store: store,
      stager: stager,
      exporter: ProbeExporter(() async {
        final staged = await stager.packDir(p.id);
        manifestExisted = File(
          '${staged.path}/${PackStager.manifestName}',
        ).existsSync();
      }),
    );

    await probing.addToWhatsApp(p);

    expect(manifestExisted, isTrue);
  });

  test('a sticker id with no record is skipped, not fatal', () async {
    await sticker('s1');
    final p = await pack(['s1', 'ghost']);

    await service().addToWhatsApp(p);

    expect(exporter.stickers!.map((s) => s.id), ['s1']);
  });

  test('every exporter failure propagates untouched', () async {
    // The UI distinguishes all three and each carries different, specific
    // information; flattening them here would throw that away.
    final failures = <Object>[
      const PackNotValidException(['too few stickers']),
      const WhatsAppRejectedException('pack is marked as animated pack'),
      const ExportCancelledException(),
    ];

    for (final failure in failures) {
      await sticker('s1');
      final p = await pack(['s1']);
      exporter = RecordingExporter(throws: failure);

      await expectLater(service().addToWhatsApp(p), throwsA(same(failure)));
    }
  });

  group('hasBeenStaged', () {
    test('is false before the first export', () async {
      final p = await pack([]);
      expect(await service().hasBeenStaged(p), isFalse);
    });

    test('is true afterwards, so the UI can warn about the refresh', () async {
      // Bumping image_data_version is the only refresh mechanism WhatsApp
      // offers and it demonstrably does not always work (issue #612,
      // acknowledged and closed unfixed), so a re-add must tell the user to
      // open WhatsApp's sticker manager.
      await sticker('s1');
      final p = await pack(['s1']);

      await service().addToWhatsApp(p);

      expect(await service().hasBeenStaged(p), isTrue);
    });
  });
}
