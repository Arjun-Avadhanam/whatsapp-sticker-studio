import 'dart:typed_data';

import '../library/library_store.dart';
import '../models/sticker_record.dart';
import '../search/search_service.dart';
import 'tagging_service.dart';

/// Runs tagging *after* a sticker is saved, and records how it went.
///
/// **Tagging is never a precondition for saving.** Waiting on vision before
/// writing the record would make the Maker feel slow, and would lose the
/// sticker outright if tagging failed — the user's work must survive a failure
/// in an optional enrichment step. So the Maker saves with
/// [TaggingStatus.pending] and calls this afterwards.
class TaggingOrchestrator {
  const TaggingOrchestrator(this._tagger, this._store, {this.search});

  final TaggingService _tagger;
  final LibraryStore _store;

  /// Optional: when supplied, a newly-tagged sticker's embedding is refreshed
  /// so it becomes semantically searchable straight away.
  final SearchService? search;

  /// Tags [record] from [imageBytes] and writes the outcome.
  ///
  /// Takes the bytes rather than reading [StickerRecord.filePath] because the
  /// caller has just encoded them — re-reading from disk would be a pointless
  /// round trip, and it keeps this class free of file IO.
  ///
  /// Never throws for a tagging failure: the sticker is already saved and
  /// usable, and a failure only means it lacks auto-tags. It is recorded as
  /// [TaggingStatus.failed] so the UI can offer a retry rather than leaving the
  /// sticker stuck on "pending" forever.
  Future<void> tag(StickerRecord record, Uint8List imageBytes) async {
    try {
      final tags = await _tagger.tag(imageBytes);

      // setAutoTags flips the status to done and, because every store write
      // funnels through saveSticker, refreshes the keyword index for free.
      await _store.setAutoTags(record.id, tags.flatten());
      await _refreshEmbedding(record.id);
    } catch (_) {
      // Deliberately catch-all. A tagger can fail in ways we do not model —
      // a missing model, an out-of-memory decode, a platform exception — and
      // none of them justify losing the sticker or crashing the Maker.
      await _store.setTaggingStatus(record.id, TaggingStatus.failed);
    }
  }

  /// Re-runs tagging for a sticker that previously failed.
  ///
  /// Resets to [TaggingStatus.pending] first, so a UI observing status shows
  /// work in progress rather than appearing to do nothing until it finishes.
  Future<void> retry(StickerRecord record, Uint8List imageBytes) async {
    await _store.setTaggingStatus(record.id, TaggingStatus.pending);
    await tag(record, imageBytes);
  }

  /// Embeddings are not maintained by the store — see [SearchService] — so
  /// without this a freshly-tagged sticker would be findable by keyword but
  /// invisible to semantic search until the next full reindex.
  Future<void> _refreshEmbedding(String id) async {
    final index = search;
    if (index == null) return;

    // Re-read: setAutoTags changed the record, and the embedding must be built
    // from the *new* searchable text, not the pre-tagging copy we were handed.
    final updated = await _store.getSticker(id);
    if (updated != null) await index.embedSticker(updated);
  }
}
