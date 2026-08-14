import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/media.dart';
import '../models/sticker_record.dart';

// drift generates the private base class `_$AppDatabase` (and all the row/
// companion classes) into this part file. It does not exist until
// `dart run build_runner build` has been run, and IS committed to git because
// CI does not run the generator.
part 'database.g.dart';

/// Stores a `List<String>` as a JSON array in a single text column. drift has
/// no native list column, so every list field routes through this. `const` so
/// the same instance is reused for every column that references it.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) =>
      (json.decode(fromDb) as List).cast<String>();

  @override
  String toSql(List<String> value) => json.encode(value);
}

/// Table backing [StickerRecord]. Column getters are declared, not called —
/// drift reads them via reflection-like code generation, so the `()()` is the
/// column-builder pattern (build the column, then invoke to finalise).
class Stickers extends Table {
  TextColumn get id => text()();
  TextColumn get filePath => text()();
  TextColumn get thumbnailPath => text()();

  // textEnum stores the enum's *name* ("animated"), not its index. Reordering
  // the enum later cannot silently remap existing rows the way an int index
  // would — the tradeoff being that renaming an enum value is a breaking change.
  TextColumn get kind => textEnum<StickerKind>()();

  TextColumn get packId => text().nullable()();
  TextColumn get autoTags => text().map(const StringListConverter())();
  TextColumn get manualName => text().nullable()();
  TextColumn get manualTags => text().map(const StringListConverter())();
  TextColumn get notes => text().nullable()();

  /// Emoji sent to WhatsApp as the sticker's `emojis` field (max 3).
  ///
  /// The only per-sticker signal that helps **inside** WhatsApp: its tray has
  /// its own emoji search, and everything else we index only helps find a
  /// sticker in *our* app. Defaulted rather than nullable so v4 rows read back
  /// as an empty list without a migration backfill.
  TextColumn get emojis => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();

  TextColumn get source => textEnum<StickerSource>()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get usageCount => integer()();
  IntColumn get sizeBytes => integer()();
  TextColumn get taggingStatus => textEnum<TaggingStatus>()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table backing [PackRecord].
class Packs extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get trayIconPath => text()();
  BoolColumn get isAnimated => boolean()();
  TextColumn get stickerIds => text().map(const StringListConverter())();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The database. Takes an explicit [QueryExecutor] so tests can inject
/// `NativeDatabase.memory()` and production can inject an on-disk connection —
/// the store never hard-codes where the data lives.
@DriftDatabase(tables: [Stickers, Packs])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Name of the FTS5 index backing search (Task 10).
  static const String searchTable = 'sticker_search';

  /// Semantic-search vectors, one row per sticker (Task 10 Step 4).
  static const String embeddingTable = 'sticker_embeddings';

  @override
  int get schemaVersion => 5;

  /// True when this open **rebuilt the search index and left it empty**.
  ///
  /// The v4 migration recreates the FTS table with different columns, and the
  /// store's per-save reindex hook only fires when a sticker is next written —
  /// so without an explicit rebuild every existing sticker silently disappears
  /// from search until the user happens to edit it. That failure is total and
  /// invisible, so it gets a flag rather than a hope.
  ///
  /// The migration cannot rebuild it itself: the searchable text is defined by
  /// `StickerRecord.mineBlob`/`autoBlob` in Dart, and reproducing that in SQL
  /// here would be a second definition free to drift from the first. So the
  /// migration raises this and `AppDependencies.bootstrap` calls
  /// `SearchService.reindex()` on seeing it.
  bool searchIndexNeedsRebuild = false;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSearchIndex();
      await _createEmbeddingTable();
    },
    onUpgrade: (m, from, to) async {
      // Explicit, additive migrations — never `fallbackToDestructiveMigration`.
      // A user's sticker library is not disposable, and all of these are derived
      // data that rebuild from the Stickers table anyway.
      if (from < 2) await _createSearchIndex();
      if (from < 3) await _createEmbeddingTable();
      if (from < 4) {
        // The column layout changed, so the old table cannot be reused. Dropped
        // rather than migrated in place: FTS5 has no ALTER for this, and the
        // contents are fully derivable.
        await customStatement('DROP TABLE IF EXISTS $searchTable;');
        await _createSearchIndex();
        searchIndexNeedsRebuild = true;
      }
      if (from < 5) {
        // Additive and non-destructive: the column has a default, so existing
        // rows read back as an empty list with no backfill. Emoji are also not
        // searchable text, so unlike v4 this needs no index rebuild.
        await m.addColumn(stickers, stickers.emojis);
      }
    },
  );

  /// The search index is a **virtual** FTS5 table, so it is created with raw
  /// SQL rather than a generated drift table — drift's Dart table API has no
  /// first-class virtual-table support, and fighting codegen here would buy
  /// nothing.
  ///
  /// `id UNINDEXED` matters: without it the sticker id is tokenised into the
  /// searchable text, so a query like "1" would match every sticker whose id
  /// contains a 1. The id is stored only so a hit can be mapped back to a
  /// record.
  ///
  /// **Two text columns, not one** (schema v4). `mine` holds the user's words —
  /// name, manual tags, notes — and `auto` holds what vision guessed, so bm25
  /// can weight them differently. FTS5 only supports per-*column* weights, which
  /// is the whole reason for the split; a single blob made a sticker the user
  /// named rank no higher than one a model happened to label the same way.
  ///
  /// Column ORDER is load-bearing: the bm25 weights in [FtsSearchService] are
  /// positional, so reordering these silently moves the weights to the wrong
  /// column and produces working-looking search with wrong ranking.
  Future<void> _createSearchIndex() => customStatement(
    'CREATE VIRTUAL TABLE IF NOT EXISTS $searchTable '
    'USING fts5(id UNINDEXED, mine, auto);',
  );

  /// One embedding per sticker, stored as raw Float32 bytes.
  ///
  /// A plain table rather than a column on Stickers: the vector is derived data
  /// like the FTS index, it is only meaningful to search, and it is absent
  /// whenever the embedding model is unavailable — none of which belongs in the
  /// record model that the rest of the app passes around.
  Future<void> _createEmbeddingTable() => customStatement(
    'CREATE TABLE IF NOT EXISTS $embeddingTable ('
    'id TEXT NOT NULL PRIMARY KEY, vector BLOB NOT NULL);',
  );
}
