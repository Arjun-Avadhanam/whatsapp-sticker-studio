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
  Future<void> saveSticker(StickerRecord r) => _db.transaction(() async {
    await _db.into(_db.stickers).insertOnConflictUpdate(_toStickerRow(r));
    await _reindex(r);
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
      'INSERT INTO ${AppDatabase.searchTable}(id, blob) VALUES (?, ?);',
      [r.id, r.searchBlob()],
    );
  }

  @override
  Future<StickerRecord?> getSticker(String id) async {
    final row = await (_db.select(
      _db.stickers,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromStickerRow(row);
  }

  @override
  Future<List<StickerRecord>> allStickers() async =>
      (await _db.select(_db.stickers).get()).map(_fromStickerRow).toList();

  @override
  Future<void> updateMetadata(
    String id, {
    Object? manualName = _unset,
    List<String>? manualTags,
    Object? notes = _unset,
  }) async {
    final current = await getSticker(id);
    if (current == null) return;

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
    await saveSticker(updated);
  }

  @override
  Future<void> setAutoTags(String id, List<String> tags) async {
    final current = await getSticker(id);
    if (current == null) return;
    await saveSticker(
      current.copyWith(autoTags: tags, taggingStatus: TaggingStatus.done),
    );
  }

  @override
  Future<void> setTaggingStatus(String id, TaggingStatus status) async {
    final current = await getSticker(id);
    if (current == null) return;
    await saveSticker(current.copyWith(taggingStatus: status));
  }

  @override
  Future<void> incrementUsage(String id) async {
    final current = await getSticker(id);
    if (current == null) return;
    await saveSticker(current.copyWith(usageCount: current.usageCount + 1));
  }

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
  Future<List<PackRecord>> allPacks() async =>
      (await _db.select(_db.packs).get()).map(_fromPackRow).toList();

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
