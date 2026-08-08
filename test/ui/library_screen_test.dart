import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/ui/library_screen.dart';

import '../app/test_dependencies.dart';

void main() {
  late AppDependencies deps;

  /// Saves a sticker with a real decodable file, since the grid paints it.
  ///
  /// Writes **synchronously** — an async `dart:io` write inside `testWidgets`'
  /// fake-time zone never completes and hangs the test with no output at all.
  Future<StickerRecord> saveSticker({
    required String id,
    String? manualName,
    List<String> autoTags = const [],
    DateTime? createdAt,
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
      manualTags: const [],
      notes: null,
      source: StickerSource.maker,
      createdAt: createdAt ?? DateTime(2026, 8, 8),
      usageCount: 0,
      sizeBytes: 512,
      taggingStatus: TaggingStatus.done,
    );
    await deps.store.saveSticker(record);
    return record;
  }

  /// Pumps the screen and lets its initial load finish.
  ///
  /// The load reaches drift, which resolves through microtasks, so plain pumping
  /// is enough here — but never `pumpAndSettle` while a progress indicator is on
  /// screen, since that schedules frames forever.
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // Scaffold, not a bare `home:`. The tiles use InkWell, which needs a
        // Material ancestor, and in the app HomeScreen supplies one via its own
        // Scaffold — so pumping the screen bare would test a tree that never
        // occurs and fail for a reason the app does not have.
        home: Scaffold(body: LibraryScreen(dependencies: deps)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  setUp(() async {
    deps = await testDependencies();
  });
  tearDown(() => deps.dispose());

  testWidgets('an empty library points at the Make tab', (tester) async {
    // Not an error state, and it must not read as one: a new install is supposed
    // to be empty, so the copy names the next action.
    await pump(tester);

    expect(find.byKey(const Key('library-empty')), findsOneWidget);
    expect(find.textContaining('Make'), findsWidgets);
  });

  testWidgets('saved stickers appear in the grid', (tester) async {
    await saveSticker(id: 's1');
    await saveSticker(id: 's2');

    await pump(tester);

    expect(find.byKey(const Key('library-grid')), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.byKey(const Key('library-empty')), findsNothing);
  });

  testWidgets('the grid is newest first', (tester) async {
    // "What I just made" is what a user looks for first.
    await saveSticker(id: 'old', createdAt: DateTime(2026, 1, 1));
    await saveSticker(id: 'newest', createdAt: DateTime(2026, 6, 1));

    await pump(tester);

    final tiles = tester
        .widgetList<StickerTile>(find.byType(StickerTile))
        .map((t) => t.sticker.id);
    expect(tiles, ['newest', 'old']);
  });

  testWidgets('a sticker shows its name when it has one', (tester) async {
    await saveSticker(id: 's1', manualName: 'Arjun high five');

    await pump(tester);

    expect(find.text('Arjun high five'), findsOneWidget);
  });

  testWidgets('an unnamed sticker falls back to its tags, not its id', (
    tester,
  ) async {
    // The id is a microsecond timestamp — showing it would be noise. Auto-tags
    // are generic (device-verified) but still describe the picture.
    await saveSticker(id: '1786175243054129', autoTags: const ['dog', 'pet']);

    await pump(tester);

    expect(find.textContaining('dog'), findsOneWidget);
    expect(find.textContaining('1786175243054129'), findsNothing);
  });

  testWidgets('a sticker with neither name nor tags still renders', (
    tester,
  ) async {
    // Abstract art the tagger found nothing in. It must not show a blank tile or
    // crash on a null.
    await saveSticker(id: 's1');

    await pump(tester);

    expect(find.byType(StickerTile), findsOneWidget);
    expect(find.text('Untitled'), findsOneWidget);
  });

  testWidgets('a missing file does not take the whole grid down', (
    tester,
  ) async {
    // Files and records can drift apart — a failed write, a cleared cache, a
    // restored backup. One broken sticker must not blank the library.
    final record = await saveSticker(id: 'ghost');
    File(record.filePath).deleteSync();
    await saveSticker(id: 'fine');

    await pump(tester);

    expect(find.byType(StickerTile), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
