import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/export/exporter.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/ui/export_pack_action.dart';

import '../app/test_dependencies.dart';

void main() {
  late AppDependencies deps;
  late FakeExporter exporter;
  bool? result;

  /// The export path is deliberately disk-free in these tests — the stager is
  /// stubbed in [testDependencies] — so plain pumping is enough and there is no
  /// fake-async trap to work around.
  Future<void> openAndConfirm(
    WidgetTester tester,
    PackRecord pack, {
    String? tapInstead,
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await confirmAndExportPack(
                    context: context,
                    dependencies: deps,
                    pack: pack,
                  );
                },
                child: const Text('Export'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    if (tapInstead != null) {
      await tester.tap(find.text(tapInstead));
      await tester.pumpAndSettle();
    }
  }

  PackRecord pack({int stickers = 3, String id = 'pack-1'}) => PackRecord(
    id: id,
    name: 'Inside jokes',
    trayIconPath: '${deps.stickerDirectory.path}/tray.webp',
    isAnimated: false,
    stickerIds: [for (var i = 0; i < stickers; i++) 's$i'],
    createdAt: DateTime(2026, 8, 8),
  );

  setUp(() async {
    exporter = FakeExporter();
    deps = await testDependencies(exporter: exporter);
  });
  tearDown(() => deps.dispose());

  testWidgets('asks before anything reaches WhatsApp', (tester) async {
    // On device, four packs were added in ~11 s with no per-pack WhatsApp
    // dialog observed. If that holds, ours is the only confirmation there is,
    // so nothing may be exported before it is answered.
    await openAndConfirm(tester, pack());

    expect(find.byKey(const Key('export-confirm')), findsOneWidget);
    expect(exporter.exported, isEmpty);
  });

  testWidgets('cancelling exports nothing and reports false', (tester) async {
    await openAndConfirm(tester, pack(), tapInstead: 'Cancel');

    expect(exporter.exported, isEmpty);
    expect(result, isFalse);
  });

  testWidgets('confirming exports the pack and confirms it landed', (
    tester,
  ) async {
    await openAndConfirm(tester, pack(), tapInstead: 'Add');

    expect(exporter.exported.single.id, 'pack-1');
    expect(result, isTrue);
    expect(find.textContaining('Added "Inside jokes"'), findsOneWidget);
  });

  testWidgets('our validator problems are listed in full', (tester) async {
    // All of them, not just the first: validation collects every problem so the
    // user fixes everything in one pass rather than one per retry.
    exporter.throws = const PackNotValidException([
      'A pack needs at least 1 sticker (this one has 0).',
      'Sticker "grin" is 400x400; it must be exactly 512x512.',
    ]);

    await openAndConfirm(tester, pack(), tapInstead: 'Add');

    expect(find.byKey(const Key('export-problems')), findsOneWidget);
    expect(find.textContaining('at least 1 sticker'), findsOneWidget);
    expect(find.textContaining('400x400'), findsOneWidget);

    // Only after the dialog is dismissed does the call return — it waits so the
    // user cannot miss the problems.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('WhatsApp\'s own rejection is shown verbatim', (tester) async {
    // Their validation is closed-source and stricter than the published sample
    // (issue #606), so this string is the only diagnostic in existence.
    // Paraphrasing it would destroy the sole clue.
    const raw =
        'pack is marked as animated pack but contains non animated '
        'stickers';
    exporter.throws = const WhatsAppRejectedException(raw);

    await openAndConfirm(tester, pack(), tapInstead: 'Add');

    expect(find.text('• $raw'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('backing out inside WhatsApp is silent, not an error', (
    tester,
  ) async {
    exporter.throws = const ExportCancelledException();

    await openAndConfirm(tester, pack(), tapInstead: 'Add');

    // An ordinary choice. No dialog, no snackbar, nothing to dismiss.
    expect(find.byKey(const Key('export-problems')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(result, isFalse);
  });

  testWidgets('a re-add warns that WhatsApp may not refresh', (tester) async {
    // Bumping image_data_version is the only refresh mechanism and demonstrably
    // does not always work (issue #612, acknowledged, closed unfixed). Staying
    // silent is what makes people recreate packs from scratch.
    final p = pack();
    final staged = await deps.packStager.packDir(p.id);
    staged.createSync(recursive: true);
    File('${staged.path}/pack.json').writeAsStringSync('{}');

    await openAndConfirm(tester, p);

    expect(find.text('Update in WhatsApp?'), findsOneWidget);

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sticker manager'), findsOneWidget);
  });

  group('readiness', () {
    test('a SINGLE sticker can be sent to WhatsApp', () async {
      // The enforced floor is 1, deliberately below WhatsApp's documented 3.
      // Device-verified 2026-08-01 that 1- and 2-sticker packs install and work
      // on v2.26.27.85, and the common case is wanting one sticker in WhatsApp
      // without inventing two more. See WhatsAppSpec.enforcedMinStickersPerPack
      // for the accepted risk.
      expect(canExport(pack(stickers: 1)), isTrue);
      expect(canExport(pack(stickers: 3)), isTrue);
    });

    test('an empty pack still cannot', () {
      // Not reachable through the UI — createPack requires a first sticker — but
      // the gate must not pass a pack with nothing in it.
      expect(canExport(pack(stickers: 0)), isFalse);
    });

    test('shortfall copy stays correct if the floor is raised back', () {
      // The floor is a single constant, so a revert must not need UI edits.
      // Exercised directly rather than via canExport, which is 1 today.
      expect(shortfallLabel(pack(stickers: 0)), contains('1 more sticker '));
    });
  });
}
