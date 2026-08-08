import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';
import 'package:whatsapp_sticker_studio/encoder/tray_icon_encoder.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/packs/pack_service.dart';

import '../app/test_dependencies.dart';

void main() {
  late AppDatabase db;
  late LibraryStore store;
  late FakePromoter promoter;
  late Directory dir;
  late PackService packs;

  /// Writes a real file for [id] so promotion and tray encoding have bytes to
  /// read — the service reads from disk, not from a record field.
  Future<StickerRecord> sticker({
    String id = 's1',
    StickerKind kind = StickerKind.staticImage,
  }) async {
    // A real image, not filler: TrayIconEncoder genuinely decodes the pack's
    // first sticker, so junk bytes fail there rather than exercising the logic.
    final file = File('${dir.path}/$id.webp');
    await file.writeAsBytes(onePixelPng());
    final record = StickerRecord(
      id: id,
      filePath: file.path,
      thumbnailPath: file.path,
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
    await store.saveSticker(record);
    return record;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLibraryStore(db);
    promoter = FakePromoter();
    dir = Directory.systemTemp.createTempSync('packs_test');
    packs = PackService(
      store: store,
      trayIcons: TrayIconEncoder(FakeWebpEncoder()),
      promoter: promoter,
      directory: dir,
    );
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('creating a pack', () {
    test(
      'a new pack takes its kind and tray icon from the first sticker',
      () async {
        final first = await sticker();

        final pack = await packs.createPack(name: 'Inside jokes', first: first);

        expect(pack.name, 'Inside jokes');
        expect(pack.stickerIds, [first.id]);
        expect(pack.isAnimated, isFalse);
        // Generated, never asked for: every pack needs a 96x96 icon and the user
        // should not have to make a second decision to get one.
        expect(File(pack.trayIconPath).existsSync(), isTrue);
      },
    );

    test('the sticker is linked back to the pack', () async {
      final first = await sticker();
      final pack = await packs.createPack(name: 'Jokes', first: first);

      expect((await store.getSticker(first.id))!.packId, pack.id);
    });

    test('a pack created from an animated sticker is animated', () async {
      final first = await sticker(kind: StickerKind.animated);
      final pack = await packs.createPack(name: 'Motion', first: first);

      expect(pack.isAnimated, isTrue);
      expect(promoter.calls, 0, reason: 'nothing to promote');
    });

    test('the pack is persisted, not just returned', () async {
      final pack = await packs.createPack(
        name: 'Jokes',
        first: await sticker(),
      );
      expect(await store.getPack(pack.id), equals(pack));
    });

    test('an 11th pack is refused', () async {
      // WhatsApp allows at most 10 packs from one app. Refusing here beats
      // WhatsApp refusing opaquely at export.
      for (var i = 0; i < WhatsAppSpec.maxPacks; i++) {
        await packs.createPack(
          name: 'Pack $i',
          first: await sticker(id: 'a$i'),
        );
      }
      await expectLater(
        packs.createPack(
          name: 'One too many',
          first: await sticker(id: 'z'),
        ),
        throwsA(isA<PackLimitException>()),
      );
    });
  });

  group('adding a sticker', () {
    test('appends in order and links the sticker', () async {
      final pack = await packs.createPack(
        name: 'Jokes',
        first: await sticker(id: 's1'),
      );
      final second = await sticker(id: 's2');

      final updated = await packs.addSticker(pack, second);

      // Order is meaningful — it is the order WhatsApp renders the tray.
      expect(updated.stickerIds, ['s1', 's2']);
      expect((await store.getSticker('s2'))!.packId, pack.id);
    });

    test('adding the same sticker twice does not duplicate it', () async {
      final first = await sticker(id: 's1');
      final pack = await packs.createPack(name: 'Jokes', first: first);

      final updated = await packs.addSticker(pack, first);

      expect(updated.stickerIds, ['s1']);
    });

    test('a 31st sticker is refused', () async {
      var pack = await packs.createPack(
        name: 'Jokes',
        first: await sticker(id: 's0'),
      );
      for (var i = 1; i < WhatsAppSpec.maxStickersPerPack; i++) {
        pack = await packs.addSticker(pack, await sticker(id: 's$i'));
      }
      expect(pack.stickerIds, hasLength(WhatsAppSpec.maxStickersPerPack));

      await expectLater(
        packs.addSticker(pack, await sticker(id: 'overflow')),
        throwsA(isA<PackLimitException>()),
      );
    });
  });

  group('silent promotion', () {
    // Packs are homogeneous — all-static or all-animated, never mixed — and the
    // user must never meet that rule as an error. Promotion dissolves it: across
    // ~9,700 scraped reviews of competing apps, zero users correctly diagnosed
    // this constraint, so explaining it does not work.
    test('a static joining an animated pack is promoted', () async {
      final pack = await packs.createPack(
        name: 'Motion',
        first: await sticker(id: 'a1', kind: StickerKind.animated),
      );
      final still = await sticker(id: 's1');

      final updated = await packs.addSticker(pack, still);

      expect(promoter.calls, 1);
      expect(updated.isAnimated, isTrue);
      final stored = (await store.getSticker('s1'))!;
      expect(stored.kind, StickerKind.animated);
      // Promotion moves the sticker onto the 500 KB budget, so the recorded
      // size must be the promoted file's, not the original's.
      expect(stored.sizeBytes, 2048);
    });

    test(
      'an animated joining a static pack promotes every existing static',
      () async {
        var pack = await packs.createPack(
          name: 'Jokes',
          first: await sticker(id: 's1'),
        );
        pack = await packs.addSticker(pack, await sticker(id: 's2'));
        expect(pack.isAnimated, isFalse);
        expect(promoter.calls, 0);

        pack = await packs.addSticker(
          pack,
          await sticker(id: 'a1', kind: StickerKind.animated),
        );

        // Both existing statics, and not the newcomer, which is already animated.
        expect(promoter.calls, 2);
        expect(pack.isAnimated, isTrue);
        for (final id in ['s1', 's2']) {
          expect((await store.getSticker(id))!.kind, StickerKind.animated);
        }
      },
    );

    test(
      'promotion overwrites in place, keeping the file path valid',
      () async {
        final pack = await packs.createPack(
          name: 'Motion',
          first: await sticker(id: 'a1', kind: StickerKind.animated),
        );
        final still = await sticker(id: 's1');
        final originalPath = still.filePath;

        await packs.addSticker(pack, still);

        final stored = (await store.getSticker('s1'))!;
        // Other records point at this path (thumbnailPath, the staged pack, the
        // share sheet). Writing a new file would leave those dangling.
        expect(stored.filePath, originalPath);
        expect(File(originalPath).lengthSync(), 2048);
      },
    );

    test('an all-static pack never promotes anything', () async {
      var pack = await packs.createPack(
        name: 'Jokes',
        first: await sticker(id: 's1'),
      );
      pack = await packs.addSticker(pack, await sticker(id: 's2'));

      expect(promoter.calls, 0);
      expect(pack.isAnimated, isFalse);
    });
  });
}
