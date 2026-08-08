import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/ui/add_to_pack_sheet.dart';

import '../app/test_dependencies.dart';

void main() {
  late AppDependencies deps;
  PackRecord? returned;

  /// Runs work that touches the **filesystem** on the real event loop.
  ///
  /// `testWidgets` bodies run in a fake-async zone. drift's in-memory sqlite
  /// still completes there because it resolves through microtasks, but genuine
  /// `dart:io` async completes through the real event loop, which the fake zone
  /// never turns — so `await file.writeAsBytes(...)` in a test body hangs
  /// forever, with no error and no stack trace. Anything reaching disk (tray
  /// icons, promotion) must go through here. Diagnosed 2026-08-08 after it ate
  /// three full-timeout runs producing no output at all.
  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  /// Lets started work finish, then rebuilds.
  ///
  /// **Never `pumpAndSettle` once the sheet is open.** It shows an indeterminate
  /// `CircularProgressIndicator`, which schedules frames forever, so settling
  /// only ends at its 10-minute timeout.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Saves a sticker with a real file on disk, since the sheet's work reaches
  /// through to tray-icon encoding and promotion, both of which read bytes.
  ///
  /// Writes **synchronously** — see [real] for why an async write would hang.
  Future<StickerRecord> saveSticker({
    String id = 's1',
    StickerKind kind = StickerKind.staticImage,
  }) async {
    File(
      '${deps.stickerDirectory.path}/$id.webp',
    ).writeAsBytesSync(onePixelPng());

    final record = StickerRecord(
      id: id,
      filePath: '${deps.stickerDirectory.path}/$id.webp',
      thumbnailPath: '${deps.stickerDirectory.path}/$id.webp',
      kind: kind,
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

  /// Pumps a host screen and opens the sheet on it. What the sheet returns
  /// lands in [returned] — that return value is the sheet's contract.
  Future<void> openSheet(WidgetTester tester, StickerRecord sticker) async {
    returned = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  returned = await showAddToPackSheet(
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

  /// Taps a pack in the sheet. The tap is inside [real] because the add reaches
  /// disk — tray icons and, when a pack flips kind, promotion.
  Future<void> tapPack(WidgetTester tester, String name) async {
    await real(tester, () async {
      await tester.tap(find.text(name));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
  }

  setUp(() async {
    deps = await testDependencies();
  });
  tearDown(() => deps.dispose());

  testWidgets('with no packs, it offers only to start one', (tester) async {
    final sticker = await saveSticker();
    await openSheet(tester, sticker);

    expect(find.text('New pack'), findsOneWidget);
    expect(find.byKey(const Key('pack-list')), findsNothing);
  });

  testWidgets('existing packs are listed with their sticker counts', (
    tester,
  ) async {
    final first = await saveSticker(id: 'a');
    await real(
      tester,
      () => deps.packs.createPack(name: 'Inside jokes', first: first),
    );

    await openSheet(tester, await saveSticker(id: 'b'));

    expect(find.text('Inside jokes'), findsOneWidget);
    // The count itself, with no shortfall warning: the enforced floor is 1, so a
    // one-sticker pack is already sendable and telling the user it is short would
    // be false. The warning copy still exists and is covered in
    // export_pack_action_test, in case the floor is raised back to 3.
    expect(find.textContaining('1 sticker'), findsOneWidget);
    expect(find.textContaining('more before'), findsNothing);
  });

  testWidgets('tapping a pack adds the sticker and closes', (tester) async {
    final first = await saveSticker(id: 'a');
    final pack = await real(
      tester,
      () => deps.packs.createPack(name: 'Jokes', first: first),
    );
    final sticker = await saveSticker(id: 'b');

    await openSheet(tester, sticker);
    await tapPack(tester, 'Jokes');

    expect(returned, isNotNull);
    expect(returned!.stickerIds, [first.id, sticker.id]);
    expect((await deps.store.getPack(pack.id))!.stickerIds, hasLength(2));
  });

  testWidgets('New pack asks for a name and creates the pack', (tester) async {
    final sticker = await saveSticker();
    await openSheet(tester, sticker);

    await tester.tap(find.text('New pack'));
    await settle(tester);

    await tester.enterText(find.byKey(const Key('pack-name')), 'Road trip');

    // Inside real(), like tapPack: createPack writes a tray icon, and disk work
    // only completes if it STARTS on the real event loop.
    await real(tester, () async {
      await tester.tap(find.text('Create'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);

    expect(returned, isNotNull);
    expect(returned!.name, 'Road trip');
    expect(returned!.stickerIds, [sticker.id]);
    // Generated automatically — the user is never asked for a tray icon.
    expect(File(returned!.trayIconPath).existsSync(), isTrue);
  });

  testWidgets('the name field stays visible above the keyboard', (
    tester,
  ) async {
    // Regression, found on device 2026-08-08. A bottom sheet is anchored to the
    // bottom of the screen and Flutter does NOT lift it for the keyboard the
    // way it lifts a dialog, so with the field autofocused the keyboard covered
    // the entire sheet and the user typed blind into something invisible.
    const keyboard = 400.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.resetViewInsets);

    final sticker = await saveSticker();
    await openSheet(tester, sticker);

    await tester.tap(find.text('New pack'));
    await settle(tester);

    final field = tester.getRect(find.byKey(const Key('pack-name')));
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      field.bottom,
      lessThanOrEqualTo(screenHeight - keyboard),
      reason: 'the field must sit above the keyboard, not behind it',
    );
  });

  testWidgets('promotion is never mentioned to the user', (tester) async {
    // A static joining an animated pack is re-encoded as a 2-frame animation.
    // The user must not learn that: across ~9,700 scraped reviews of competing
    // apps, zero users diagnosed the homogeneity rule correctly, so naming it
    // reintroduces the confusion this design exists to dissolve.
    final animated = await saveSticker(id: 'a', kind: StickerKind.animated);
    await real(
      tester,
      () => deps.packs.createPack(name: 'Motion', first: animated),
    );

    await openSheet(tester, await saveSticker(id: 'b'));
    await tapPack(tester, 'Motion');

    for (final word in ['animat', 'convert', 'static', 'frame']) {
      expect(
        find.textContaining(RegExp(word, caseSensitive: false)),
        findsNothing,
        reason: '"$word" leaks the promotion',
      );
    }
    expect((await deps.store.getSticker('b'))!.kind, StickerKind.animated);
  });

  testWidgets('a full pack surfaces the limit message, not a crash', (
    tester,
  ) async {
    await real(tester, () async {
      var pack = await deps.packs.createPack(
        name: 'Full',
        first: await saveSticker(id: 'p0'),
      );
      for (var i = 1; i < WhatsAppSpec.maxStickersPerPack; i++) {
        pack = await deps.packs.addSticker(pack, await saveSticker(id: 'p$i'));
      }
    });

    await openSheet(tester, await saveSticker(id: 'extra'));
    await tapPack(tester, 'Full');

    // PackLimitException's own wording, which names the remedy ("Start another
    // pack for this one") rather than just reporting a number.
    expect(find.textContaining('Start another pack'), findsOneWidget);
    expect(returned, isNull, reason: 'the sheet stays open to be corrected');
  });
}
