import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';

/// A fully-populated sticker. Every field is distinct and non-default so a
/// round-trip that drops or mangles one is caught.
StickerRecord sampleSticker({
  String id = '1',
  int usageCount = 0,
  TaggingStatus taggingStatus = TaggingStatus.pending,
  StickerSource source = StickerSource.giphy,
}) => StickerRecord(
  id: id,
  filePath: '$id.webp',
  thumbnailPath: '${id}_t.webp',
  kind: StickerKind.animated,
  packId: 'pack-1',
  autoTags: const ['dog', 'high five'],
  manualName: 'Arjun high five',
  manualTags: const ['friends'],
  notes: 'inside joke',
  source: source,
  createdAt: DateTime(2026, 1, 2, 3, 4, 5),
  usageCount: usageCount,
  sizeBytes: 400000,
  taggingStatus: taggingStatus,
);

PackRecord samplePack({String id = 'pack-1'}) => PackRecord(
  id: id,
  name: 'Inside jokes',
  trayIconPath: 'tray.webp',
  isAnimated: true,
  stickerIds: const ['1', '2', '3'],
  createdAt: DateTime(2026, 1, 2, 3, 4, 5),
);

void main() {
  late AppDatabase db;
  late LibraryStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLibraryStore(db);
  });
  tearDown(() => db.close());

  group('sticker round-trip', () {
    test('save then get returns an identical record', () async {
      final s = sampleSticker();
      await store.saveSticker(s);
      expect(await store.getSticker('1'), equals(s));
    });

    test('get on a missing id returns null', () async {
      expect(await store.getSticker('nope'), isNull);
    });

    test('enum fields survive the round-trip by name', () async {
      final s = sampleSticker(
        source: StickerSource.xLink,
        taggingStatus: TaggingStatus.failed,
      );
      await store.saveSticker(s);
      final got = (await store.getSticker('1'))!;
      expect(got.source, StickerSource.xLink);
      expect(got.taggingStatus, TaggingStatus.failed);
    });

    test('list fields survive the JSON round-trip, including empty', () async {
      final s = sampleSticker().copyWith(
        autoTags: const [],
        manualTags: const ['a', 'b', 'c'],
      );
      await store.saveSticker(s);
      final got = (await store.getSticker('1'))!;
      expect(got.autoTags, isEmpty);
      expect(got.manualTags, ['a', 'b', 'c']);
    });

    test('saving an existing id overwrites it', () async {
      await store.saveSticker(sampleSticker());
      await store.saveSticker(sampleSticker().copyWith(manualName: 'Renamed'));
      expect((await store.getSticker('1'))!.manualName, 'Renamed');
    });

    test('allStickers returns every saved sticker', () async {
      await store.saveSticker(sampleSticker(id: '1'));
      await store.saveSticker(sampleSticker(id: '2'));
      final ids = (await store.allStickers()).map((s) => s.id).toSet();
      expect(ids, {'1', '2'});
    });

    test('allStickers is newest first', () async {
      // The Library shows this order directly, and "what I just made" is what a
      // user looks for first. Guaranteed by the store rather than sorted in the
      // UI, so every caller gets it and no screen can forget.
      await store.saveSticker(
        sampleSticker(id: 'old').copyWith(createdAt: DateTime(2026, 1, 1)),
      );
      await store.saveSticker(
        sampleSticker(id: 'new').copyWith(createdAt: DateTime(2026, 6, 1)),
      );
      await store.saveSticker(
        sampleSticker(id: 'middle').copyWith(createdAt: DateTime(2026, 3, 1)),
      );

      expect((await store.allStickers()).map((s) => s.id), [
        'new',
        'middle',
        'old',
      ]);
    });

    test('stickers made in the same second order deterministically', () async {
      // drift stores dateTime as unix SECONDS, so two stickers made in the same
      // second share a createdAt and would otherwise come back in arbitrary
      // order — a grid that reshuffles itself between rebuilds. The id breaks
      // the tie: the Maker mints it from microsecondsSinceEpoch, so a higher id
      // is genuinely later.
      final t = DateTime(2026, 5, 5);
      await store.saveSticker(sampleSticker(id: '1000').copyWith(createdAt: t));
      await store.saveSticker(sampleSticker(id: '2000').copyWith(createdAt: t));

      expect((await store.allStickers()).map((s) => s.id), ['2000', '1000']);
    });
  });

  group('updateMetadata', () {
    test('changes only the named fields', () async {
      await store.saveSticker(sampleSticker());
      await store.updateMetadata('1', manualName: 'New name');
      final got = (await store.getSticker('1'))!;
      expect(got.manualName, 'New name');
      expect(got.notes, 'inside joke'); // untouched
      expect(got.manualTags, ['friends']); // untouched
    });

    test('an omitted field is left untouched', () async {
      await store.saveSticker(sampleSticker());
      await store.updateMetadata('1', notes: 'edited');
      expect((await store.getSticker('1'))!.manualName, 'Arjun high five');
    });

    test('passing null clears a nullable field', () async {
      await store.saveSticker(sampleSticker());
      await store.updateMetadata('1', notes: null);
      expect((await store.getSticker('1'))!.notes, isNull);
    });
  });

  group('setAutoTags', () {
    test('replaces tags and marks tagging done', () async {
      await store.saveSticker(
        sampleSticker(taggingStatus: TaggingStatus.pending),
      );
      await store.setAutoTags('1', ['cat', 'jump']);
      final got = (await store.getSticker('1'))!;
      expect(got.autoTags, ['cat', 'jump']);
      expect(got.taggingStatus, TaggingStatus.done);
    });
  });

  group('concurrent edits', () {
    // Tagging runs in the background after a save, so anything the user does to
    // the sticker meanwhile overlaps it. Every mutator is read-modify-write, and
    // Dart yields at each await — so without the read being inside the write's
    // transaction, whichever finishes second writes back a record it read
    // BEFORE the first one landed, silently reverting it.
    test(
      'a manual edit during tagging does not clobber the auto-tags',
      () async {
        await store.saveSticker(
          sampleSticker(taggingStatus: TaggingStatus.pending),
        );

        // Started together, not awaited in turn: this is the real shape — the
        // user types a tag while the tagger is still working.
        await Future.wait([
          store.updateMetadata('1', manualTags: ['arjun']),
          store.setAutoTags('1', ['dog']),
        ]);

        final got = (await store.getSticker('1'))!;
        expect(got.manualTags, ['arjun'], reason: 'the edit must survive');
        expect(got.autoTags, ['dog'], reason: 'the tags must survive');
        // The nastier half: a reverted status leaves the sticker stuck on
        // "pending" forever, because the tagging that would resolve it has
        // already finished and nothing will run again.
        expect(got.taggingStatus, TaggingStatus.done);
      },
    );

    test('a usage bump during a rename loses neither', () async {
      await store.saveSticker(sampleSticker(usageCount: 3));

      await Future.wait([
        store.incrementUsage('1'),
        store.updateMetadata('1', manualName: 'Renamed'),
      ]);

      final got = (await store.getSticker('1'))!;
      expect(got.usageCount, 4);
      expect(got.manualName, 'Renamed');
    });
  });

  group('incrementUsage', () {
    test('bumps the count by one each call', () async {
      await store.saveSticker(sampleSticker(usageCount: 0));
      await store.incrementUsage('1');
      expect((await store.getSticker('1'))!.usageCount, 1);
      await store.incrementUsage('1');
      expect((await store.getSticker('1'))!.usageCount, 2);
    });
  });

  group('deleting', () {
    test('a deleted sticker is gone from the library', () async {
      await store.saveSticker(sampleSticker(id: '1'));
      await store.saveSticker(sampleSticker(id: '2'));

      await store.deleteSticker('1');

      expect(await store.getSticker('1'), isNull);
      expect((await store.allStickers()).map((s) => s.id), ['2']);
    });

    test('a deleted sticker leaves no search row behind', () async {
      // An orphaned FTS row surfaces a hit that opens nothing — worse than the
      // sticker still existing, because it looks like a broken app rather than
      // a full library.
      await store.saveSticker(sampleSticker(id: '1'));

      await store.deleteSticker('1');

      final rows = await db
          .customSelect(
            'SELECT id FROM ${AppDatabase.searchTable} WHERE id = ?;',
            variables: [Variable<String>('1')],
          )
          .get();
      expect(rows, isEmpty);
    });

    test('a deleted sticker is removed from its pack', () async {
      // stickerIds is a JSON list, so this cannot be a foreign key — nothing
      // cleans it up unless the store does. A stale id makes the pack export a
      // sticker that no longer exists.
      await store.saveSticker(sampleSticker(id: '1'));
      await store.saveSticker(sampleSticker(id: '2'));
      await store.savePack(samplePack().copyWith(stickerIds: ['1', '2']));

      await store.deleteSticker('1');

      expect((await store.getPack('pack-1'))!.stickerIds, ['2']);
    });

    test('deleting a sticker that is not there is not an error', () async {
      // Two taps on Delete, or a stale screen. Neither deserves a crash.
      await expectLater(store.deleteSticker('ghost'), completes);
    });

    test('deleting a pack KEEPS its stickers', () async {
      // The user grouped these; they did not create them here. Losing the
      // originals to a tidy-up would be unrecoverable.
      await store.saveSticker(sampleSticker(id: '1'));
      await store.savePack(samplePack().copyWith(stickerIds: ['1']));

      await store.deletePack('pack-1');

      expect(await store.getPack('pack-1'), isNull);
      expect(await store.getSticker('1'), isNotNull);
    });

    test('deleting a pack clears its stickers\' back-reference', () async {
      // Otherwise they keep claiming membership of a pack that no longer
      // exists, and show as already-filed forever.
      await store.saveSticker(sampleSticker(id: '1')); // packId: 'pack-1'
      await store.savePack(samplePack().copyWith(stickerIds: ['1']));

      await store.deletePack('pack-1');

      expect((await store.getSticker('1'))!.packId, isNull);
    });
  });

  group('pack round-trip', () {
    test('save then get returns an identical pack', () async {
      final p = samplePack();
      await store.savePack(p);
      expect(await store.getPack('pack-1'), equals(p));
    });

    test('get on a missing id returns null', () async {
      expect(await store.getPack('nope'), isNull);
    });

    test('stickerIds order is preserved', () async {
      await store.savePack(samplePack().copyWith(stickerIds: ['3', '1', '2']));
      expect((await store.getPack('pack-1'))!.stickerIds, ['3', '1', '2']);
    });

    test('allPacks returns every saved pack', () async {
      await store.savePack(samplePack(id: 'pack-1'));
      await store.savePack(samplePack(id: 'pack-2'));
      final ids = (await store.allPacks()).map((p) => p.id).toSet();
      expect(ids, {'pack-1', 'pack-2'});
    });
  });
}
