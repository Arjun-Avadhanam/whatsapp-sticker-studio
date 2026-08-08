import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/ui/sticker_detail_sheet.dart';

import '../app/test_dependencies.dart';

void main() {
  late AppDependencies deps;
  bool? changed;

  /// Real work here is drift only, which resolves through microtasks, so plain
  /// pumping suffices. Never `pumpAndSettle` while a spinner is on screen.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<StickerRecord> saveSticker({
    String id = 's1',
    String? manualName,
    List<String> autoTags = const [],
    List<String> manualTags = const [],
    String? notes,
  }) async {
    final path = '${deps.stickerDirectory.path}/$id.webp';
    File(path).writeAsBytesSync(onePixelPng());

    final record = StickerRecord(
      id: id,
      filePath: path,
      thumbnailPath: path,
      kind: StickerKind.staticImage,
      packId: null,
      autoTags: autoTags,
      manualName: manualName,
      manualTags: manualTags,
      notes: notes,
      source: StickerSource.maker,
      createdAt: DateTime(2026, 8, 8),
      usageCount: 0,
      sizeBytes: 40960,
      taggingStatus: TaggingStatus.done,
    );
    await deps.store.saveSticker(record);
    return record;
  }

  /// Opens the sheet on a host screen; [changed] receives what it returns.
  Future<void> open(WidgetTester tester, StickerRecord sticker) async {
    changed = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  changed = await showStickerDetailSheet(
                    context: context,
                    dependencies: deps,
                    sticker: sticker,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await settle(tester);
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await settle(tester);
  }

  setUp(() async {
    deps = await testDependencies();
  });
  tearDown(() => deps.dispose());

  testWidgets('shows the sticker\'s current metadata', (tester) async {
    await open(
      tester,
      await saveSticker(
        manualName: 'Arjun high five',
        manualTags: const ['friends'],
        notes: 'inside joke',
        autoTags: const ['person', 'hand'],
      ),
    );

    expect(find.text('Arjun high five'), findsOneWidget);
    expect(find.text('friends'), findsOneWidget);
    expect(find.text('inside joke'), findsOneWidget);
    expect(find.text('person'), findsOneWidget);
  });

  testWidgets('editing the name persists it and reports a change', (
    tester,
  ) async {
    final sticker = await saveSticker(manualName: 'old');
    await open(tester, sticker);

    await tester.enterText(find.byKey(const Key('detail-name')), 'penguin');
    await tapSave(tester);

    expect((await deps.store.getSticker(sticker.id))!.manualName, 'penguin');
    expect(changed, isTrue, reason: 'the grid needs to know to refresh');
  });

  testWidgets('a renamed sticker is findable by its new name', (tester) async {
    // The point of naming. updateMetadata funnels through saveSticker, so the
    // keyword index updates inside the same transaction — no reindex needed.
    final sticker = await saveSticker(manualName: 'old');
    await open(tester, sticker);

    await tester.enterText(find.byKey(const Key('detail-name')), 'penguin');
    await tapSave(tester);

    final hits = await deps.search.query('penguin');
    expect(hits.map((h) => h.record.id), [sticker.id]);
  });

  testWidgets('adding a manual tag keeps the existing ones', (tester) async {
    final sticker = await saveSticker(manualTags: const ['friends']);
    await open(tester, sticker);

    await tester.enterText(find.byKey(const Key('detail-add-tag')), 'holiday');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await tapSave(tester);

    expect((await deps.store.getSticker(sticker.id))!.manualTags, [
      'friends',
      'holiday',
    ]);
  });

  testWidgets('a manual tag can be removed', (tester) async {
    final sticker = await saveSticker(manualTags: const ['friends', 'holiday']);
    await open(tester, sticker);

    await tester.tap(find.byKey(const Key('remove-tag-friends')));
    await settle(tester);
    await tapSave(tester);

    expect((await deps.store.getSticker(sticker.id))!.manualTags, ['holiday']);
  });

  testWidgets('AUTO tags are shown but cannot be deleted', (tester) async {
    // The whole point of keeping the two fields separate: the user must never
    // have to clear machine output to add their own words. Offering a delete on
    // an auto-tag would invite exactly that chore, and the next tagging run would
    // put it straight back anyway.
    final sticker = await saveSticker(
      autoTags: const ['sports', 'team'],
      manualTags: const ['friends'],
    );
    await open(tester, sticker);

    expect(find.text('sports'), findsOneWidget);
    expect(find.byKey(const Key('remove-tag-sports')), findsNothing);
    // The user's own tag stays removable.
    expect(find.byKey(const Key('remove-tag-friends')), findsOneWidget);

    await tapSave(tester);
    expect((await deps.store.getSticker(sticker.id))!.autoTags, [
      'sports',
      'team',
    ]);
  });

  testWidgets('cancelling discards every edit', (tester) async {
    final sticker = await saveSticker(manualName: 'old', notes: 'keep me');
    await open(tester, sticker);

    await tester.enterText(find.byKey(const Key('detail-name')), 'discarded');
    await tester.enterText(find.byKey(const Key('detail-notes')), 'discarded');
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    final stored = (await deps.store.getSticker(sticker.id))!;
    expect(stored.manualName, 'old');
    expect(stored.notes, 'keep me');
    expect(changed, isFalse);
  });

  testWidgets('clearing the name stores null, not an empty string', (
    tester,
  ) async {
    // Empty must fall back to auto-tags for WhatsApp's accessibility_text rather
    // than exporting a blank description.
    final sticker = await saveSticker(manualName: 'old');
    await open(tester, sticker);

    await tester.enterText(find.byKey(const Key('detail-name')), '   ');
    await tapSave(tester);

    expect((await deps.store.getSticker(sticker.id))!.manualName, isNull);
  });

  testWidgets('the fields stay visible above the keyboard', (tester) async {
    // Same trap as the Add-to-pack sheet: a bottom sheet is anchored to the
    // bottom of the screen and Flutter does not lift it for the keyboard the way
    // it lifts a dialog. Found on device 2026-08-08 and it recurs verbatim in any
    // new sheet with a text field.
    const keyboard = 400.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.resetViewInsets);

    await open(tester, await saveSticker(manualName: 'x'));

    final field = tester.getRect(find.byKey(const Key('detail-name')));
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      field.bottom,
      lessThanOrEqualTo(screenHeight - keyboard),
      reason: 'the name field must sit above the keyboard, not behind it',
    );
  });
}
