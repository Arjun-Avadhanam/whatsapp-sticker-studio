import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/search/search_service.dart';
import 'package:whatsapp_sticker_studio/search/text_embedder.dart';
import 'package:whatsapp_sticker_studio/tagger/tagging_orchestrator.dart';
import 'package:whatsapp_sticker_studio/tagger/tagging_service.dart';

class FakeTagger implements TaggingService {
  FakeTagger(this.tags);
  FakeTagger.failing() : tags = null;

  /// Fails in a way we do *not* model, to prove the catch is genuinely
  /// defensive rather than only handling TaggingException.
  FakeTagger.crashing() : tags = null, crash = true;

  final StickerTags? tags;
  bool crash = false;
  int calls = 0;

  @override
  Future<StickerTags> tag(Uint8List imageBytes) async {
    calls++;
    if (crash) throw StateError('something nobody anticipated');
    final result = tags;
    if (result == null) throw const TaggingException('vision unavailable');
    return result;
  }
}

/// Maps any text containing a known word to that word's vector.
class FakeEmbedder implements TextEmbedder {
  FakeEmbedder(this.vectors);
  final Map<String, List<double>> vectors;

  @override
  Future<List<double>?> embed(String text) async {
    final lower = text.toLowerCase();
    for (final entry in vectors.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  late AppDatabase db;
  late LibraryStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLibraryStore(db);
  });

  tearDown(() => db.close());

  StickerRecord pending(String id) => StickerRecord(
    id: id,
    filePath: '$id.webp',
    thumbnailPath: '${id}_t.webp',
    kind: StickerKind.staticImage,
    packId: null,
    autoTags: const [],
    manualName: null,
    manualTags: const [],
    notes: null,
    source: StickerSource.maker,
    createdAt: DateTime(2026),
    usageCount: 0,
    sizeBytes: 50000,
    taggingStatus: TaggingStatus.pending,
  );

  group('status transitions', () {
    test('success writes the tags and marks tagging done', () async {
      final tagger = FakeTagger(
        const StickerTags(subjects: ['dog'], textInImage: 'LOL'),
      );
      await store.saveSticker(pending('1'));

      await TaggingOrchestrator(tagger, store).tag(pending('1'), bytes);

      final saved = await store.getSticker('1');
      expect(saved!.taggingStatus, TaggingStatus.done);
      expect(saved.autoTags, containsAll(['dog', 'LOL']));
    });

    test('a TaggingException marks failed without throwing', () async {
      // The sticker is already saved and usable; a failed enrichment step must
      // not propagate into the Maker as an error.
      await store.saveSticker(pending('1'));

      await expectLater(
        TaggingOrchestrator(
          FakeTagger.failing(),
          store,
        ).tag(pending('1'), bytes),
        completes,
      );

      expect(
        (await store.getSticker('1'))!.taggingStatus,
        TaggingStatus.failed,
      );
    });

    test(
      'an unexpected error also marks failed rather than escaping',
      () async {
        // Taggers can fail in ways we have not modelled — a missing model, an
        // OOM decode, a platform exception. None justify losing the sticker.
        await store.saveSticker(pending('1'));

        await expectLater(
          TaggingOrchestrator(
            FakeTagger.crashing(),
            store,
          ).tag(pending('1'), bytes),
          completes,
        );

        expect(
          (await store.getSticker('1'))!.taggingStatus,
          TaggingStatus.failed,
        );
      },
    );

    test('a failed sticker keeps its file and metadata intact', () async {
      // "Failed" must mean "untagged", never "damaged".
      await store.saveSticker(pending('1'));
      await TaggingOrchestrator(
        FakeTagger.failing(),
        store,
      ).tag(pending('1'), bytes);

      final saved = await store.getSticker('1');
      expect(saved!.filePath, '1.webp');
      expect(saved.sizeBytes, 50000);
    });

    test('retry resets to pending then tags again', () async {
      final tagger = FakeTagger(const StickerTags(subjects: ['dog']));
      await store.saveSticker(
        pending('1').copyWith(taggingStatus: TaggingStatus.failed),
      );

      await TaggingOrchestrator(tagger, store).retry(pending('1'), bytes);

      expect((await store.getSticker('1'))!.taggingStatus, TaggingStatus.done);
      expect(tagger.calls, 1);
    });
  });

  group('search integration', () {
    test('auto-tags are immediately findable by keyword', () async {
      // Free via the store: setAutoTags routes through saveSticker, which
      // maintains the FTS index.
      final search = FtsSearchService(db, store);
      await store.saveSticker(pending('1'));

      await TaggingOrchestrator(
        FakeTagger(const StickerTags(subjects: ['dog'])),
        store,
      ).tag(pending('1'), bytes);

      expect((await search.query('dog')).map((h) => h.record.id), ['1']);
    });

    test('auto-tags are immediately findable SEMANTICALLY too', () async {
      // Not free: embeddings are owned by SearchService, not the store, so
      // without the orchestrator refreshing them a freshly-tagged sticker would
      // be invisible to semantic search until the next full reindex.
      const dog = [1.0, 0.0, 0.0];
      const puppy = [0.95, 0.31, 0.0];
      const car = [0.0, 0.0, 1.0];

      final search = FtsSearchService(
        db,
        store,
        embedder: FakeEmbedder({'dog': dog, 'puppy': puppy, 'car': car}),
      );

      await store.saveSticker(pending('1'));
      await store.saveSticker(pending('2').copyWith(manualName: 'car'));
      await search.reindex(); // '1' has no text yet, so nothing to embed

      await TaggingOrchestrator(
        FakeTagger(const StickerTags(subjects: ['dog'])),
        store,
        search: search,
      ).tag(pending('1'), bytes);

      // "puppy" shares no characters with "dog", so a hit can only come from
      // the embedding written during tagging.
      final hits = await search.query('puppy');
      expect(hits.map((h) => h.record.id), contains('1'));
      expect(
        hits.map((h) => h.record.id),
        isNot(contains('2')),
        reason: 'the unrelated sticker must not be a semantic match',
      );
    });

    test('works without a SearchService supplied', () async {
      // Search is optional wiring; the orchestrator must not require it.
      await store.saveSticker(pending('1'));

      await expectLater(
        TaggingOrchestrator(
          FakeTagger(const StickerTags(subjects: ['dog'])),
          store,
        ).tag(pending('1'), bytes),
        completes,
      );

      expect((await store.getSticker('1'))!.taggingStatus, TaggingStatus.done);
    });
  });
}
