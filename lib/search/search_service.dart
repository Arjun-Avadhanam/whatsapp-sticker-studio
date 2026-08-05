import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../library/database.dart';
import '../library/library_store.dart';
import '../models/sticker_record.dart';
import 'text_embedder.dart';

/// A matched sticker and the score it matched with. Higher [score] ranks first.
class SearchHit {
  const SearchHit(this.record, this.score);

  final StickerRecord record;
  final double score;
}

/// Finds stickers by their combined auto + manual metadata.
///
/// Index maintenance is split, deliberately and asymmetrically:
/// - the **keyword** index is maintained by [DriftLibraryStore] inside
///   `saveSticker`, so anything written to the library is instantly searchable
///   with no caller discipline;
/// - **embeddings** are maintained here, because producing one needs the native
///   model and the store must stay testable without a device.
///
/// That split is why [embedSticker] exists at all. [reindex] covers what neither
/// can: rebuilding after a schema migration, or repairing a drifted index.
abstract class SearchService {
  /// Rebuilds the index from the library. Safe to call repeatedly.
  Future<void> reindex();

  /// Refreshes just this sticker's **embedding**.
  ///
  /// Only embeddings — the FTS index is maintained by the store on every write.
  /// This exists because embeddings cannot be: producing one needs the native
  /// model, which the store must not depend on. Without it, a sticker tagged
  /// after indexing is findable by keyword but invisible to semantic search
  /// until the next full [reindex].
  Future<void> embedSticker(StickerRecord sticker);

  Future<List<SearchHit>> query(String q, {int limit = 50});
}

/// [SearchService] over SQLite's FTS5, ranked by text relevance blended with
/// how often the sticker has actually been sent.
class FtsSearchService implements SearchService {
  FtsSearchService(
    this._db,
    this._store, {
    this.usageWeight = 0.5,
    this.embedder,
    this.semanticWeight = 2.0,
    this.semanticTopK = 5,
    this.semanticMargin = 0.35,
  });

  final AppDatabase _db;
  final LibraryStore _store;

  /// How much a sticker's usage contributes relative to text relevance.
  final double usageWeight;

  /// Optional. When absent, search is keyword-only — semantic matching is an
  /// enhancement, and a missing model must never break search.
  final TextEmbedder? embedder;

  /// Scales cosine similarity (which is only ever -1..1) up to compete with
  /// bm25 scores, which are unbounded.
  final double semanticWeight;

  /// How many of the closest stickers may be admitted as semantic matches.
  ///
  /// **Deliberately a rank cutoff, not a similarity threshold.** Measured on
  /// device with the bundled Universal Sentence Encoder:
  /// `cosine(dog, puppy) = 0.980` but `cosine(dog, car) = 0.940` — the model
  /// compresses all similarities into a narrow high band, so no absolute floor
  /// separates related from unrelated. Any threshold low enough to admit a true
  /// match also admits the entire library. What the model *does* get right is
  /// the ordering, so we trust the ranking and ignore the absolute value.
  final int semanticTopK;

  /// A candidate must be at least this much closer than the *weakest* candidate
  /// to count, expressed as a fraction of the observed similarity spread.
  ///
  /// Guards the case where every sticker really is equally unrelated: with a
  /// flat spread nothing stands out, and admitting the top K anyway would put
  /// arbitrary stickers in front of the user.
  final double semanticMargin;

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

    // Embeddings are refreshed outside that transaction: each one is a platform
    // call that can be slow or fail, and holding a write transaction open across
    // them would block every other database user for the duration.
    await _reembedAll(stickers);
  }

  @override
  Future<void> embedSticker(StickerRecord sticker) => _reembedAll([sticker]);

  /// Recomputes and stores the embedding for every sticker.
  ///
  /// Unlike the FTS index — which the store maintains on save — embeddings are
  /// owned here, because producing one needs the native model, which does not
  /// exist in unit tests or on a machine without the platform channel. Keeping
  /// that dependency out of [LibraryStore] is what lets the store stay
  /// device-free.
  Future<void> _reembedAll(List<StickerRecord> stickers) async {
    final model = embedder;
    if (model == null) return;

    for (final sticker in stickers) {
      final blob = sticker.searchBlob();
      if (blob.trim().isEmpty) continue;

      // A null vector means the model is unavailable for this one; leave it
      // keyword-only rather than failing the whole reindex.
      final vector = await model.embed(blob);
      if (vector == null) continue;

      await _db.customStatement(
        'INSERT OR REPLACE INTO ${AppDatabase.embeddingTable}(id, vector) '
        'VALUES (?, ?);',
        [sticker.id, Float32List.fromList(vector).buffer.asUint8List()],
      );
    }
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

    final textScores = <String, double>{
      for (final row in rows)
        row.read<String>('id'): row.read<double>('text_score'),
    };

    // Semantic matches are found over the WHOLE library, not just the keyword
    // hits. That is the entire point: "puppy" should surface a sticker tagged
    // only "dog", which keyword search returns zero rows for — so intersecting
    // with the FTS results would leave semantic search unable to add anything.
    final semanticScores = await _semanticScores(q);

    final hits = <SearchHit>[];
    for (final id in {...textScores.keys, ...semanticScores.keys}) {
      final record = await _store.getSticker(id);
      // A row can outlive its sticker if the library changed since the last
      // index; skip rather than surfacing a hit that opens nothing.
      if (record == null) continue;

      final score =
          (textScores[id] ?? 0) +
          _usageBonus(record.usageCount) +
          semanticWeight * (semanticScores[id] ?? 0);
      hits.add(SearchHit(record, score));
    }

    // The usage and semantic bonuses reorder what SQLite returned, so sort here.
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  /// The closest stickers to [query] by meaning, as scores in 0..1.
  ///
  /// Brute force over all vectors: a personal sticker library is hundreds of
  /// items, not millions, so an approximate-nearest-neighbour index would be
  /// machinery without a payoff.
  ///
  /// Similarities are converted to *relative* scores rather than used directly,
  /// because the model's absolute values are nearly meaningless — see
  /// [semanticTopK]. The best candidate scores 1, the worst 0, and only those
  /// standing clear of the pack by [semanticMargin] survive.
  Future<Map<String, double>> _semanticScores(String query) async {
    final model = embedder;
    if (model == null) return const {};

    final queryVector = await model.embed(query);
    if (queryVector == null) return const {};

    final rows = await _db
        .customSelect('SELECT id, vector FROM ${AppDatabase.embeddingTable};')
        .get();
    if (rows.isEmpty) return const {};

    final similarities = <String, double>{};
    for (final row in rows) {
      final bytes = row.read<Uint8List>('vector');
      final vector = bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
      similarities[row.read<String>('id')] = cosineSimilarity(
        queryVector,
        vector,
      );
    }

    final ranked = similarities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final best = ranked.first.value;
    final worst = ranked.last.value;
    final spread = best - worst;

    // Everything is equally (dis)similar, so nothing genuinely stands out.
    // Admitting the top K here would hand the user arbitrary stickers dressed
    // up as matches. A single-sticker library lands here too, correctly: one
    // item cannot be "closer than the rest".
    if (spread <= 0) return const {};

    final scores = <String, double>{};
    for (final entry in ranked.take(semanticTopK)) {
      final relative = (entry.value - worst) / spread;
      if (relative >= semanticMargin) scores[entry.key] = relative;
    }
    return scores;
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
