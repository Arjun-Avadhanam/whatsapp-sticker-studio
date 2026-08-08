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
