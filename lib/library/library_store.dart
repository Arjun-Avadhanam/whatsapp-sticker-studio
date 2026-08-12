import 'package:drift/drift.dart';

import '../models/pack_record.dart';
import '../models/sticker_record.dart';
import 'database.dart';

/// Distinguishes "argument omitted" from "argument passed as null" in
/// [LibraryStore.updateMetadata] — same technique as `StickerRecord.copyWith`,
/// but a *separate* sentinel object living in this library.
const Object _unset = Object();

/// Persistence for the sticker library. The one place that knows about storage;
/// everything else talks records.
abstract class LibraryStore {
  Future<void> saveSticker(StickerRecord r);
  Future<StickerRecord?> getSticker(String id);
  Future<List<StickerRecord>> allStickers();

  /// Updates only the fields supplied. `notes: null` clears the note; omitting
  /// `notes` leaves it untouched (see [_unset]).
  ///
  /// The `_unset` defaults MUST match the implementation's. Dart resolves an
  /// optional param's default from the statically-typed target — a caller
  /// holding this as a `LibraryStore` gets *these* defaults, not the concrete
  /// class's. If they disagreed, "omitted" and "passed null" would collapse
  /// into the same value here.
  Future<void> updateMetadata(
    String id, {
    Object? manualName = _unset,
    List<String>? manualTags,
    Object? notes = _unset,
  });

  /// Replaces auto-tags and marks tagging complete.
  Future<void> setAutoTags(String id, List<String> tags);

  /// Records how tagging ended. Separate from [setAutoTags], which implies
  /// success — this is how a *failure* is recorded so the UI can offer a retry
  /// instead of leaving the sticker stuck on "pending" forever.
  Future<void> setTaggingStatus(String id, TaggingStatus status);

  Future<void> incrementUsage(String id);

  /// Removes a sticker from the library, its search index and any pack.
  ///
  /// Does **not** touch the file on disk — that is the caller's, because the
  /// store has no business doing IO and because a record and its bytes can be
  /// deleted for different reasons.
  Future<void> deleteSticker(String id);

  /// Removes a pack. Its stickers stay in the library, unfiled.
  ///
  /// Deleting the stickers too would make "delete pack" a far more destructive
  /// action than it reads as — the user grouped them, they did not create them
  /// here, and losing the originals to a tidy-up is unrecoverable.
  Future<void> deletePack(String id);

  Future<void> savePack(PackRecord p);
  Future<PackRecord?> getPack(String id);
  Future<List<PackRecord>> allPacks();
}

/// drift-backed [LibraryStore]. Mutating methods read the record, apply
/// `copyWith`, and write it back — records are immutable, so there is no
/// in-place mutation.
class DriftLibraryStore implements LibraryStore {
  DriftLibraryStore(this._db);

  final AppDatabase _db;

  // ---- Stickers ----------------------------------------------------------

  @override
  Future<void> saveSticker(StickerRecord r) => _db.transaction(() => _write(r));

  Future<void> _write(StickerRecord r) async {
    await _db.into(_db.stickers).insertOnConflictUpdate(_toStickerRow(r));
    await _reindex(r);
  }

  /// Reads a sticker, applies [change], and writes it back — all inside ONE
  /// transaction, so the read cannot go stale before the write lands.
  ///
  /// The read has to be in here. Tagging runs in the background after a save,
  /// so a user edit overlaps it, and Dart yields at every `await`: with the read
  /// outside, `updateMetadata` could read the record, be suspended while
  /// `setAutoTags` read-modified-wrote it, then resume and save its pre-tagging
  /// copy — silently dropping the tags AND reverting the status to `pending`,
  /// which nothing would ever resolve because the tagging run had finished.
  /// Reproduced deterministically before this existed
  /// (`library_store_test.dart`, "concurrent edits").
  ///
  /// drift runs transactions exclusively, so the second caller's read is queued
  /// until the first has committed and therefore sees the fresh record.
  Future<void> _mutate(
    String id,
    StickerRecord Function(StickerRecord current) change,
  ) => _db.transaction(() async {
    final current = await getSticker(id);
    if (current == null) return;
    await _write(change(current));
  });

  /// Keeps the FTS5 search index in step with the row just written.
  ///
  /// Done here, inside the same transaction, rather than left to callers: a
  /// sticker the user just made or renamed that does not turn up in search
  /// reads as data loss, and "remember to reindex after every write" is a rule
  /// that gets forgotten exactly once and then fails silently. Every mutating
  /// method funnels through [saveSticker], so this one hook covers
  /// `updateMetadata`, `setAutoTags` and `incrementUsage` as well.
  ///
  /// Delete-then-insert because FTS5 virtual tables have no UPSERT: without the
  /// delete, renaming a sticker would leave it findable under its old name.
  ///
  /// The blob comes from [StickerRecord.searchBlob], which stays the single
  /// definition of what is searchable. Rebuilding it in SQL — via triggers, say
  /// — would mean maintaining that definition twice, in two languages, free to
  /// drift apart.
  Future<void> _reindex(StickerRecord r) async {
    await _db.customStatement(
      'DELETE FROM ${AppDatabase.searchTable} WHERE id = ?;',
      [r.id],
    );
    await _db.customStatement(
      'INSERT INTO ${AppDatabase.searchTable}(id, mine, auto) '
      'VALUES (?, ?, ?);',
      // Two columns so bm25 can weight the user's own words above the machine's.
      [r.id, r.mineBlob(), r.autoBlob()],
    );
  }

  @override
  Future<StickerRecord?> getSticker(String id) async {
    final row = await (_db.select(
      _db.stickers,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromStickerRow(row);
  }

  /// Newest first, and **deterministically so**.
  ///
  /// Ordered here rather than in the Library screen: every caller wants it, and
  /// a guarantee in one place cannot be forgotten by a screen.
  ///
  /// The id tiebreak is load-bearing, not defensive. drift stores `dateTime` as
  /// unix **seconds**, so two stickers made in the same second share a
  /// `createdAt` and SQLite is free to return them in any order — a grid that
  /// silently reshuffles between rebuilds. The Maker mints ids from
  /// `microsecondsSinceEpoch`, so a higher id really is later.
  @override
  Future<List<StickerRecord>> allStickers() async {
    final query = _db.select(_db.stickers)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return (await query.get()).map(_fromStickerRow).toList();
  }

  @override
  Future<void> updateMetadata(
    String id, {
    Object? manualName = _unset,
    List<String>? manualTags,
    Object? notes = _unset,
  }) => _mutate(id, (current) {
    // Each field is forwarded to copyWith only when the caller supplied it.
    // We cannot pass this library's _unset into copyWith — copyWith compares
    // against its *own* sentinel — so we branch instead of forwarding.
    var updated = current;
    if (!identical(manualName, _unset)) {
      updated = updated.copyWith(manualName: manualName as String?);
    }
    if (manualTags != null) {
      updated = updated.copyWith(manualTags: manualTags);
    }
    if (!identical(notes, _unset)) {
      updated = updated.copyWith(notes: notes as String?);
    }
    return updated;
  });

  @override
  Future<void> setAutoTags(String id, List<String> tags) => _mutate(
    id,
    (current) =>
        current.copyWith(autoTags: tags, taggingStatus: TaggingStatus.done),
  );

  @override
  Future<void> setTaggingStatus(String id, TaggingStatus status) =>
      _mutate(id, (current) => current.copyWith(taggingStatus: status));

  /// One transaction covering the row, the search index, the embedding and the
  /// sticker's membership of any pack.
  ///
  /// All four, because a half-deleted sticker is worse than a live one: an
  /// orphaned FTS row surfaces a hit that opens nothing, and an id left in
  /// `stickerIds` makes the pack export a sticker that no longer exists.
  @override
  Future<void> deleteSticker(String id) => _db.transaction(() async {
    await (_db.delete(_db.stickers)..where((t) => t.id.equals(id))).go();
    await _db.customStatement(
      'DELETE FROM ${AppDatabase.searchTable} WHERE id = ?;',
      [id],
    );
    await _db.customStatement(
      'DELETE FROM ${AppDatabase.embeddingTable} WHERE id = ?;',
      [id],
    );

    // Packs store their members as a JSON list, so this cannot be a foreign
    // key — the pack rows have to be rewritten by hand.
    for (final pack in await allPacks()) {
      if (!pack.stickerIds.contains(id)) continue;
      final remaining = pack.stickerIds.where((s) => s != id).toList();
      await _db
          .into(_db.packs)
          .insertOnConflictUpdate(
            _toPackRow(pack.copyWith(stickerIds: remaining)),
          );
    }
  });

  /// Deletes the pack row only. Its stickers survive, unfiled.
  @override
  Future<void> deletePack(String id) => _db.transaction(() async {
    await (_db.delete(_db.packs)..where((t) => t.id.equals(id))).go();

    // Clear the back-reference, or the stickers keep claiming membership of a
    // pack that no longer exists — which would show them as already-filed and
    // make them impossible to reason about.
    for (final sticker in await allStickers()) {
      if (sticker.packId != id) continue;
      await _write(sticker.copyWith(packId: null));
    }
  });

  @override
  Future<void> incrementUsage(String id) => _mutate(
    id,
    (current) => current.copyWith(usageCount: current.usageCount + 1),
  );

  // ---- Packs -------------------------------------------------------------

  @override
  Future<void> savePack(PackRecord p) =>
      _db.into(_db.packs).insertOnConflictUpdate(_toPackRow(p));

  @override
  Future<PackRecord?> getPack(String id) async {
    final row = await (_db.select(
      _db.packs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromPackRow(row);
  }

  @override
  /// Newest first, with the same id tiebreak as [allStickers] and for the same
  /// reason: `createdAt` is stored to the second, so packs made in one sitting
  /// would otherwise reorder themselves between rebuilds.
  @override
  Future<List<PackRecord>> allPacks() async {
    final query = _db.select(_db.packs)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return (await query.get()).map(_fromPackRow).toList();
  }

  // ---- Row <-> record mapping --------------------------------------------

  // Returns a Companion with every field wrapped in an explicit `Value`,
  // including `Value(null)` for nulls. Passing a plain data class instead would
  // serialise nulls as *absent*, and insertOnConflictUpdate would then leave a
  // previously-set column unchanged rather than clearing it (drift's
  // nullToAbsent behaviour) — so a note could never be deleted.
  StickersCompanion _toStickerRow(StickerRecord r) => StickersCompanion(
    id: Value(r.id),
    filePath: Value(r.filePath),
    thumbnailPath: Value(r.thumbnailPath),
    kind: Value(r.kind),
    packId: Value(r.packId),
    autoTags: Value(r.autoTags),
    manualName: Value(r.manualName),
    manualTags: Value(r.manualTags),
    notes: Value(r.notes),
    source: Value(r.source),
    createdAt: Value(r.createdAt),
    usageCount: Value(r.usageCount),
    sizeBytes: Value(r.sizeBytes),
    taggingStatus: Value(r.taggingStatus),
  );

  StickerRecord _fromStickerRow(Sticker row) => StickerRecord(
    id: row.id,
    filePath: row.filePath,
    thumbnailPath: row.thumbnailPath,
    kind: row.kind,
    packId: row.packId,
    autoTags: row.autoTags,
    manualName: row.manualName,
    manualTags: row.manualTags,
    notes: row.notes,
    source: row.source,
    createdAt: row.createdAt,
    usageCount: row.usageCount,
    sizeBytes: row.sizeBytes,
    taggingStatus: row.taggingStatus,
  );

  PacksCompanion _toPackRow(PackRecord p) => PacksCompanion(
    id: Value(p.id),
    name: Value(p.name),
    trayIconPath: Value(p.trayIconPath),
    isAnimated: Value(p.isAnimated),
    stickerIds: Value(p.stickerIds),
    createdAt: Value(p.createdAt),
  );

  PackRecord _fromPackRow(Pack row) => PackRecord(
    id: row.id,
    name: row.name,
    trayIconPath: row.trayIconPath,
    isAnimated: row.isAnimated,
    stickerIds: row.stickerIds,
    createdAt: row.createdAt,
  );
}
