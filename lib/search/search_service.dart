import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../library/database.dart';
import '../library/library_store.dart';
import '../models/sticker_record.dart';

/// A matched sticker and the score it matched with. Higher [score] ranks first.
class SearchHit {
  const SearchHit(this.record, this.score);

  final StickerRecord record;
  final double score;
}

/// Finds stickers by their combined auto + manual metadata.
///
/// Note there is no per-sticker index method: [DriftLibraryStore] maintains the
/// index inside `saveSticker`, so anything written to the library is searchable
/// immediately. [reindex] exists for the cases that cannot cover — rebuilding
/// after a schema migration, or repairing an index that has drifted.
abstract class SearchService {
  /// Rebuilds the index from the library. Safe to call repeatedly.
  Future<void> reindex();

  Future<List<SearchHit>> query(String q, {int limit = 50});
}

/// [SearchService] over SQLite's FTS5, ranked by text relevance blended with
/// how often the sticker has actually been sent.
class FtsSearchService implements SearchService {
  FtsSearchService(this._db, this._store, {this.usageWeight = 0.5});

  final AppDatabase _db;
  final LibraryStore _store;

  /// How much a sticker's usage contributes relative to text relevance.
  final double usageWeight;

  @override
  Future<void> reindex() async {
    final stickers = await _store.allStickers();

    // Rebuild wholesale rather than upserting. Renaming a sticker must not
    // leave it findable under its old name, and a full rebuild is the only
    // thing that reliably drops text that no longer exists anywhere.
    await _db.transaction(() async {
      await _db.customStatement('DELETE FROM ${AppDatabase.searchTable};');
      for (final sticker in stickers) {
        await _insert(sticker);
      }
    });
  }

  @override
  Future<List<SearchHit>> query(String q, {int limit = 50}) async {
    final match = _toMatchQuery(q);
    if (match == null) return const [];

    // bm25() is FTS5's relevance score: MORE negative means a better match.
    // Negating it turns it into "higher is better", which is what SearchHit
    // promises and what the usage bonus can then be added to.
    final rows = await _db
        .customSelect(
          'SELECT id, -bm25(${AppDatabase.searchTable}) AS text_score '
          'FROM ${AppDatabase.searchTable} '
          'WHERE ${AppDatabase.searchTable} MATCH ?1 '
          'ORDER BY bm25(${AppDatabase.searchTable}) '
          'LIMIT ?2;',
          variables: [Variable<String>(match), Variable<int>(limit)],
        )
        .get();

    final hits = <SearchHit>[];
    for (final row in rows) {
      final record = await _store.getSticker(row.read<String>('id'));
      // A row can outlive its sticker if the library changed since the last
      // index; skip rather than surfacing a hit that opens nothing.
      if (record == null) continue;

      final textScore = row.read<double>('text_score');
      hits.add(SearchHit(record, textScore + _usageBonus(record.usageCount)));
    }

    // The usage bonus can reorder what SQLite returned, so sort in Dart.
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  /// Logarithmic on purpose. A linear bonus would let one sticker the user
  /// sends constantly outrank genuinely better text matches on every query,
  /// turning search into a most-used list.
  double _usageBonus(int usageCount) => usageWeight * math.log(1 + usageCount);

  Future<void> _insert(StickerRecord sticker) => _db.customStatement(
    'INSERT INTO ${AppDatabase.searchTable}(id, blob) VALUES (?, ?);',
    [sticker.id, sticker.searchBlob()],
  );

  /// Turns raw user input into a safe FTS5 MATCH expression, or `null` when
  /// there is nothing to search for.
  ///
  /// FTS5's MATCH is a query *language*: `"` quotes phrases, `*` is a prefix
  /// operator, `^` anchors, `(`/`)` group, and AND/OR/NOT/NEAR are keywords.
  /// Passing user text through raw means an apostrophe in "Arjun's face", or a
  /// stray quote, becomes a syntax error rather than a search — a crash on
  /// completely ordinary input.
  ///
  /// So each whitespace-separated term has its own double quotes stripped and
  /// is then wrapped in double quotes, making it a literal phrase — which also
  /// neutralises the AND/OR/NOT/NEAR keywords, since a quoted "AND" is searched
  /// for as the word rather than parsed as an operator.
  String? _toMatchQuery(String raw) {
    final terms = raw
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll('"', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (terms.isEmpty) return null;
    return terms.map((t) => '"$t"').join(' ');
  }
}
