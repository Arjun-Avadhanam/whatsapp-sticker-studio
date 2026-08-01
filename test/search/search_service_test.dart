import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/search/search_service.dart';

/// Builds a sticker whose searchable fields are individually controllable, so a
/// test can prove *which* field a hit came from.
StickerRecord stickerOf({
  required String id,
  List<String> autoTags = const [],
  String? manualName,
  List<String> manualTags = const [],
  String? notes,
  int usageCount = 0,
}) => StickerRecord(
  id: id,
  filePath: '$id.webp',
  thumbnailPath: '${id}_t.webp',
  kind: StickerKind.staticImage,
  packId: null,
  autoTags: autoTags,
  manualName: manualName,
  manualTags: manualTags,
  notes: notes,
  source: StickerSource.maker,
  createdAt: DateTime(2026),
  usageCount: usageCount,
  sizeBytes: 50000,
  taggingStatus: TaggingStatus.done,
);

void main() {
  late AppDatabase db;
  late LibraryStore store;
  late SearchService search;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLibraryStore(db);
    search = FtsSearchService(db, store);
  });

  tearDown(() => db.close());

  Future<void> save(List<StickerRecord> stickers) async {
    for (final s in stickers) {
      await store.saveSticker(s);
    }
    await search.reindex();
  }

  group('keyword search covers the whole searchBlob', () {
    test('finds a sticker by its manual name', () async {
      await save([
        stickerOf(id: '1', manualName: 'Arjun high five'),
        stickerOf(id: '2', manualName: 'Something else'),
      ]);

      final hits = await search.query('arjun');
      expect(hits.map((h) => h.record.id), ['1']);
    });

    test('finds a sticker by an auto tag', () async {
      // Auto tags are the whole point of the tagger: a sticker the user never
      // named must still be findable.
      await save([
        stickerOf(id: '1', autoTags: const ['dog', 'high five']),
        stickerOf(id: '2', autoTags: const ['cat']),
      ]);

      expect((await search.query('dog')).map((h) => h.record.id), ['1']);
    });

    test('finds a sticker by a manual tag or a note', () async {
      await save([
        stickerOf(id: '1', manualTags: const ['friends']),
        stickerOf(id: '2', notes: 'inside joke'),
      ]);

      expect((await search.query('friends')).map((h) => h.record.id), ['1']);
      expect((await search.query('joke')).map((h) => h.record.id), ['2']);
    });

    test('search is case-insensitive', () async {
      await save([stickerOf(id: '1', manualName: 'Arjun high five')]);
      expect(await search.query('ARJUN'), hasLength(1));
    });
  });

  group('ranking', () {
    test('usageCount breaks ties between equal text matches', () async {
      // The entire reason usageCount exists: WhatsApp exposes no usage data, so
      // this is a ranking signal and nothing else.
      await save([
        stickerOf(id: 'rare', autoTags: const ['dog'], usageCount: 0),
        stickerOf(id: 'favourite', autoTags: const ['dog'], usageCount: 5),
      ]);

      final hits = await search.query('dog');
      expect(hits, hasLength(2));
      expect(hits.first.record.id, 'favourite');
      expect(hits.first.score, greaterThan(hits.last.score));
    });

    test(
      'a heavily-used sticker cannot outrank a much better text match',
      () async {
        // Usage is weighted logarithmically precisely so one popular sticker does
        // not colonise every result list.
        await save([
          stickerOf(id: 'exact', manualName: 'penguin', usageCount: 0),
          stickerOf(id: 'popular', manualName: 'dog', usageCount: 9999),
        ]);

        final hits = await search.query('penguin');
        expect(hits.map((h) => h.record.id), ['exact']);
      },
    );
  });

  group('robustness', () {
    test(
      'a query matching nothing returns empty rather than throwing',
      () async {
        await save([stickerOf(id: '1', manualName: 'Arjun')]);
        expect(await search.query('nothingmatchesthis'), isEmpty);
      },
    );

    test('an empty or whitespace query returns empty', () async {
      await save([stickerOf(id: '1', manualName: 'Arjun')]);
      expect(await search.query(''), isEmpty);
      expect(await search.query('   '), isEmpty);
    });

    test('FTS5 operator characters in a query do not blow up', () async {
      // FTS5's MATCH has its own syntax: ", *, ^, ( and ) are operators, and
      // NEAR/AND/OR are keywords. An unescaped apostrophe in "Arjun's face" or a
      // stray quote would otherwise turn an ordinary search into a syntax error
      // — a crash on completely normal user input.
      await save([stickerOf(id: '1', manualName: "Arjun's face")]);

      // `expect(() async => ..., returnsNormally)` would pass vacuously here:
      // it only proves the closure returns a Future without throwing
      // *synchronously*, so the query itself is never awaited and any real
      // failure surfaces long after the test has finished. Await each one.
      for (final q in ['"', "Arjun's", 'a*', '^b', '(c)', 'AND', 'x OR y']) {
        await expectLater(
          search.query(q),
          completes,
          reason: 'query "$q" must not throw',
        );
      }
    });

    test('respects the result limit', () async {
      await save([
        for (var i = 0; i < 10; i++)
          stickerOf(id: '$i', autoTags: const ['dog']),
      ]);

      expect(await search.query('dog', limit: 3), hasLength(3));
    });
  });

  group('index freshness', () {
    test('reindex picks up stickers saved after the index was built', () async {
      await save([stickerOf(id: '1', manualName: 'Arjun')]);
      await store.saveSticker(stickerOf(id: '2', manualName: 'Penguin'));

      await search.reindex();
      expect((await search.query('penguin')).map((h) => h.record.id), ['2']);
    });

    test('reindex reflects edited metadata and drops the stale text', () async {
      // Renaming a sticker must not leave it findable under its old name.
      await save([stickerOf(id: '1', manualName: 'Arjun')]);
      await store.updateMetadata('1', manualName: 'Penguin');
      await search.reindex();

      expect(await search.query('arjun'), isEmpty);
      expect((await search.query('penguin')).map((h) => h.record.id), ['1']);
    });

    test(
      'saving a sticker makes it searchable immediately — no reindex needed',
      () async {
        // The store maintains the index inside saveSticker, so there is no code
        // path that writes a sticker without indexing it. A sticker the user just
        // made that cannot be found reads as data loss.
        await store.saveSticker(stickerOf(id: '2', manualName: 'Penguin'));

        expect((await search.query('penguin')).map((h) => h.record.id), ['2']);
      },
    );

    test(
      'renaming replaces the index entry rather than adding a second',
      () async {
        await store.saveSticker(stickerOf(id: '1', manualName: 'Arjun'));
        await store.updateMetadata('1', manualName: 'Penguin');

        expect(
          await search.query('arjun'),
          isEmpty,
          reason: 'the old name must stop matching',
        );
        expect(await search.query('penguin'), hasLength(1));
      },
    );

    test('auto-tags from the tagger become searchable', () async {
      // setAutoTags routes through saveSticker, so it is covered by the same
      // hook — the tagger never has to know the search index exists.
      await store.saveSticker(stickerOf(id: '1', manualName: 'Untitled'));
      await store.setAutoTags('1', const ['dog', 'high five']);

      expect((await search.query('dog')).map((h) => h.record.id), ['1']);
    });

    test(
      'incrementing usage does not corrupt or duplicate the entry',
      () async {
        await store.saveSticker(stickerOf(id: '1', autoTags: const ['dog']));
        await store.incrementUsage('1');
        await store.incrementUsage('1');

        expect(await search.query('dog'), hasLength(1));
      },
    );

    test('reindex is idempotent — no duplicate hits', () async {
      await save([
        stickerOf(id: '1', autoTags: const ['dog']),
      ]);
      await search.reindex();
      await search.reindex();

      expect(await search.query('dog'), hasLength(1));
    });
  });
}
