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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSearchIndex();
      await _createEmbeddingTable();
    },
    onUpgrade: (m, from, to) async {
      // Explicit, additive migrations — never `fallbackToDestructiveMigration`.
      // A user's sticker library is not disposable, and both of these are
      // derived data that rebuild from the Stickers table anyway.
      if (from < 2) await _createSearchIndex();
      if (from < 3) await _createEmbeddingTable();
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
  Future<void> _createSearchIndex() => customStatement(
    'CREATE VIRTUAL TABLE IF NOT EXISTS $searchTable '
    'USING fts5(id UNINDEXED, blob);',
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
