import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/search/search_service.dart';

import '../search/search_service_test.dart' show stickerOf;

/// The v3 → v4 search-index migration.
///
/// Worth its own file because the failure mode is **silent and total**: v4
/// changes the FTS5 column layout, so the old table has to be dropped, and the
/// store's reindex hook only fires when a sticker is next written. Get this wrong
/// and every sticker a user already owns vanishes from search until they happen
/// to edit it — with no error anywhere.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('migration_test');
    file = File('${dir.path}/library.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Winds a v4 database back to look like v3: the old single-column FTS table,
  /// and `user_version` reset so drift runs the upgrade on the next open.
  ///
  /// Built by regression rather than by writing v3's DDL out by hand, so the
  /// Stickers/Packs tables are guaranteed to match what v3 really had.
  Future<void> pretendItIsVersion3() async {
    final db = AppDatabase(NativeDatabase(file));
    await db.customStatement(
      'DROP TABLE IF EXISTS ${AppDatabase.searchTable};',
    );
    await db.customStatement(
      'CREATE VIRTUAL TABLE ${AppDatabase.searchTable} '
      'USING fts5(id UNINDEXED, blob);',
    );
    await db.customStatement('PRAGMA user_version = 3;');
    await db.close();
  }

  test('an upgraded library is searchable again after the rebuild', () async {
    // Seed a v4 library with one sticker, then wind it back to v3.
    final seed = AppDatabase(NativeDatabase(file));
    await DriftLibraryStore(seed).saveSticker(
      stickerOf(id: 's1', manualName: 'penguin', autoTags: const ['bird']),
    );
    await seed.close();
    await pretendItIsVersion3();

    // Reopening runs the v4 migration.
    final db = AppDatabase(NativeDatabase(file));
    final store = DriftLibraryStore(db);
    final search = FtsSearchService(db, store);
    addTearDown(db.close);

    // Force the migration to run — drift opens lazily.
    expect(await store.allStickers(), hasLength(1));
    expect(
      db.searchIndexNeedsRebuild,
      isTrue,
      reason: 'the migration must announce that it emptied the index',
    );

    // Before the rebuild the index is genuinely empty. Asserted so the flag is
    // proven load-bearing rather than decorative — if search worked here, the
    // rebuild would be untested ceremony.
    expect(await search.query('penguin'), isEmpty);

    await search.reindex();

    final hits = await search.query('penguin');
    expect(hits.map((h) => h.record.id), ['s1']);
  });

  test('the rebuilt index has the v4 columns, weights included', () async {
    // A rebuild that wrote the old shape would leave search working but
    // unweighted — the exact bug v4 exists to fix, hidden behind a passing
    // migration.
    final seed = AppDatabase(NativeDatabase(file));
    final seedStore = DriftLibraryStore(seed);
    await seedStore.saveSticker(
      stickerOf(id: 'auto', autoTags: const ['sports']),
    );
    await seedStore.saveSticker(stickerOf(id: 'named', manualName: 'sports'));
    await seed.close();
    await pretendItIsVersion3();

    final db = AppDatabase(NativeDatabase(file));
    final store = DriftLibraryStore(db);
    final search = FtsSearchService(db, store);
    addTearDown(db.close);

    await search.reindex();

    expect((await search.query('sports')).map((h) => h.record.id), [
      'named',
      'auto',
    ]);
  });

  test('a fresh library needs no rebuild', () async {
    final db = AppDatabase(NativeDatabase(file));
    final store = DriftLibraryStore(db);
    addTearDown(db.close);

    await store.saveSticker(stickerOf(id: 's1', manualName: 'penguin'));

    expect(db.searchIndexNeedsRebuild, isFalse);
    // onCreate builds the current shape, and the store's hook keeps it current,
    // so a new install is searchable with no rebuild at all.
    final hits = await FtsSearchService(db, store).query('penguin');
    expect(hits.map((h) => h.record.id), ['s1']);
  });
}
