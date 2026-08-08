import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/search/search_service.dart';
import 'package:whatsapp_sticker_studio/ui/library_screen.dart';

import '../app/test_dependencies.dart';

/// Wraps the real search so tests can count queries and control their timing.
///
/// Delegating rather than faking keeps the ranking real — these tests assert on
/// what search actually returns, not on a canned list.
class SpySearch implements SearchService {
  SpySearch(this._inner);
  final SearchService _inner;

  final List<String> queries = [];

  /// When set, every query waits on this instead of returning — used to force
  /// two requests to be in flight at once.
  Completer<void>? gate;

  @override
  Future<List<SearchHit>> query(String q, {int limit = 50}) async {
    queries.add(q);
    if (gate != null) await gate!.future;
    return _inner.query(q, limit: limit);
  }

  @override
  Future<void> reindex() => _inner.reindex();

  @override
  Future<void> embedSticker(StickerRecord sticker) =>
      _inner.embedSticker(sticker);
}

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

  group('search', () {
    late SpySearch spy;

    /// Pumps with search spied on, so query timing and count are observable.
    Future<void> pumpWithSpy(WidgetTester tester) async {
      spy = SpySearch(deps.search);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryScreen(dependencies: deps, search: spy),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// Types [q] and lets the debounce elapse.
    Future<void> search(WidgetTester tester, String q) async {
      await tester.enterText(find.byKey(const Key('library-search')), q);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }

    testWidgets('typing filters the grid, and EXCLUDES non-matches', (
      tester,
    ) async {
      // Asserting only that the match is present would pass if search returned
      // everything — which is exactly how the semantic-threshold bug survived
      // its tests. The distractor's absence is the real assertion.
      await saveSticker(id: 'dog', manualName: 'penguin');
      await saveSticker(id: 'car', manualName: 'motorbike');
      await pumpWithSpy(tester);

      await search(tester, 'penguin');

      final tiles = tester
          .widgetList<StickerTile>(find.byType(StickerTile))
          .map((t) => t.sticker.id);
      expect(tiles, ['dog']);
      expect(tiles, isNot(contains('car')));
    });

    testWidgets('rapid typing issues ONE query, not one per keystroke', (
      tester,
    ) async {
      await saveSticker(id: 's1', manualName: 'penguin');
      await pumpWithSpy(tester);

      // Each entry lands well inside the debounce window.
      for (final q in ['p', 'pe', 'pen', 'peng']) {
        await tester.enterText(find.byKey(const Key('library-search')), q);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(seconds: 1));

      expect(spy.queries, ['peng']);
    });

    testWidgets('clearing the field shows the whole library again', (
      tester,
    ) async {
      await saveSticker(id: 'a', manualName: 'penguin');
      await saveSticker(id: 'b', manualName: 'motorbike');
      await pumpWithSpy(tester);

      await search(tester, 'penguin');
      expect(find.byType(StickerTile), findsOneWidget);

      await search(tester, '');

      expect(find.byType(StickerTile), findsNWidgets(2));
      // An empty query is "show everything", which the store already answers —
      // asking search for it would be a wasted round trip and, with FTS5, an
      // empty MATCH returns nothing at all.
      expect(spy.queries, ['penguin']);
    });

    testWidgets('a query matching nothing says so, and not as an error', (
      tester,
    ) async {
      await saveSticker(id: 'a', manualName: 'penguin');
      await pumpWithSpy(tester);

      await search(tester, 'zzzznothing');

      expect(find.byKey(const Key('library-no-results')), findsOneWidget);
      expect(find.byType(StickerTile), findsNothing);
      // Distinct from the empty-library state: one means "nothing here yet", the
      // other "nothing matched", and they call for different next actions.
      expect(find.byKey(const Key('library-empty')), findsNothing);
    });

    testWidgets('a slow earlier query cannot overwrite a later one', (
      tester,
    ) async {
      // Debouncing does not prevent overlap: a slow query can still be in flight
      // when the next one resolves, and without a guard its stale results would
      // land last and replace the newer ones. The user sees results for a query
      // they have already changed.
      await saveSticker(id: 'a', manualName: 'penguin');
      await saveSticker(id: 'b', manualName: 'motorbike');
      await pumpWithSpy(tester);

      // First query is held open mid-flight.
      final held = Completer<void>();
      spy.gate = held;
      await search(tester, 'penguin');

      // Second query runs to completion while the first is still blocked.
      spy.gate = null;
      await search(tester, 'motorbike');
      expect(
        tester
            .widgetList<StickerTile>(find.byType(StickerTile))
            .map((t) => t.sticker.id),
        ['b'],
      );

      // Now let the stale one finish. It must be discarded.
      held.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester
            .widgetList<StickerTile>(find.byType(StickerTile))
            .map((t) => t.sticker.id),
        ['b'],
        reason: 'the superseded query must not win by finishing last',
      );
    });
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
