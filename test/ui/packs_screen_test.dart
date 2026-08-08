import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/ui/packs_screen.dart';

import '../app/test_dependencies.dart';

void main() {
  late AppDependencies deps;
  late FakeExporter exporter;

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<StickerRecord> saveSticker(String id) async {
    final path = '${deps.stickerDirectory.path}/$id.webp';
    File(path).writeAsBytesSync(onePixelPng());

    final record = StickerRecord(
      id: id,
      filePath: path,
      thumbnailPath: path,
      kind: StickerKind.staticImage,
      packId: null,
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
    await deps.store.saveSticker(record);
    return record;
  }

  /// Saves a pack directly, so tests control counts and timestamps.
  Future<PackRecord> savePack({
    required String id,
    required String name,
    int stickers = 1,
    DateTime? createdAt,
  }) async {
    final tray = '${deps.stickerDirectory.path}/tray_$id.webp';
    File(tray).writeAsBytesSync(onePixelPng());

    final ids = <String>[];
    for (var i = 0; i < stickers; i++) {
      ids.add((await saveSticker('$id-s$i')).id);
    }

    final pack = PackRecord(
      id: id,
      name: name,
      trayIconPath: tray,
      isAnimated: false,
      stickerIds: ids,
      createdAt: createdAt ?? DateTime(2026, 8, 8),
    );
    await deps.store.savePack(pack);
    return pack;
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PacksScreen(dependencies: deps)),
      ),
    );
    await settle(tester);
  }

  setUp(() async {
    exporter = FakeExporter();
    deps = await testDependencies(exporter: exporter);
  });
  tearDown(() => deps.dispose());

  testWidgets('with no packs it explains how to make one', (tester) async {
    // A pack is the only route into WhatsApp's tray, so an empty state here has
    // to say how to get one rather than just reporting emptiness.
    await pump(tester);

    expect(find.byKey(const Key('packs-empty')), findsOneWidget);
    expect(find.textContaining('Add to pack'), findsWidgets);
  });

  testWidgets('packs are listed with their sticker counts', (tester) async {
    await savePack(id: 'p1', name: 'Inside jokes', stickers: 4);
    await pump(tester);

    expect(find.text('Inside jokes'), findsOneWidget);
    expect(find.textContaining('4 stickers'), findsOneWidget);
  });

  testWidgets('a one-sticker pack reads in the singular', (tester) async {
    // With the enforced floor at 1 this is the common case, not an edge one.
    await savePack(id: 'p1', name: 'Solo', stickers: 1);
    await pump(tester);

    expect(find.textContaining('1 sticker'), findsOneWidget);
    expect(find.textContaining('1 stickers'), findsNothing);
  });

  testWidgets('packs are newest first', (tester) async {
    await savePack(id: 'old', name: 'Older', createdAt: DateTime(2026, 1, 1));
    await savePack(id: 'new', name: 'Newer', createdAt: DateTime(2026, 6, 1));
    await pump(tester);

    final tiles = tester
        .widgetList<PackTile>(find.byType(PackTile))
        .map((t) => t.pack.name);
    expect(tiles, ['Newer', 'Older']);
  });

  testWidgets('Add to WhatsApp asks first, then exports', (tester) async {
    // The confirmation is ours and mandatory — on device, WhatsApp added four
    // packs in ~11 s with no dialog of its own.
    await savePack(id: 'p1', name: 'Inside jokes', stickers: 3);
    await pump(tester);

    await tester.tap(find.byKey(const Key('export-p1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('export-confirm')), findsOneWidget);
    expect(exporter.exported, isEmpty, reason: 'nothing before confirming');

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(exporter.exported.single.id, 'p1');
  });

  testWidgets('this screen is the ONLY way back to an existing pack', (
    tester,
  ) async {
    // The hole this closes: before it, a pack was exportable only in the moment
    // after adding a sticker in the Maker, so closing the app left every pack
    // unreachable and unsendable.
    await savePack(id: 'p1', name: 'Inside jokes', stickers: 2);
    await pump(tester);

    expect(find.byKey(const Key('export-p1')), findsOneWidget);
  });
}
