import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/search/search_service.dart';
import 'package:whatsapp_sticker_studio/search/text_embedder.dart';

/// Task 10 Step 4 — device verification of the REAL embedding model.
///
/// The unit tests prove the blending, thresholding and degradation logic using a
/// fake embedder with hand-built vectors. What they cannot prove is that
/// MediaPipe's Universal Sentence Encoder actually places related words near
/// each other — that is a property of the model, and only the device has it.
void semanticTests() {
  late AppDatabase db;
  late LibraryStore store;
  final embedder = NativeTextEmbedder();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLibraryStore(db);
  });

  tearDown(() => db.close());

  StickerRecord stickerOf(String id, List<String> tags) => StickerRecord(
    id: id,
    filePath: '$id.webp',
    thumbnailPath: '${id}_t.webp',
    kind: StickerKind.staticImage,
    packId: null,
    autoTags: tags,
    manualName: null,
    manualTags: const [],
    notes: null,
    source: StickerSource.maker,
    createdAt: DateTime(2026),
    usageCount: 0,
    sizeBytes: 50000,
    taggingStatus: TaggingStatus.done,
  );

  testWidgets('the bundled model loads and produces an embedding', (
    tester,
  ) async {
    final vector = await embedder.embed('a happy dog');
    expect(
      vector,
      isNotNull,
      reason: 'model missing from assets, or MediaPipe failed to load it',
    );
    debugPrint('embedding dimensions: ${vector!.length}');
    expect(vector.length, greaterThan(1));
    // An all-zero vector would mean the model ran but produced nothing usable,
    // which cosine similarity would silently report as "no similarity to
    // anything" rather than as a failure.
    expect(vector.any((v) => v != 0), isTrue);
  });

  testWidgets('related words really are closer than unrelated ones', (
    tester,
  ) async {
    // This is the assumption the whole feature rests on. If it does not hold on
    // the real model, semantic search cannot work no matter how correct our
    // blending is.
    final dog = await embedder.embed('dog');
    final puppy = await embedder.embed('puppy');
    final car = await embedder.embed('car');
    expect([dog, puppy, car], everyElement(isNotNull));

    final related = cosineSimilarity(dog!, puppy!);
    final unrelated = cosineSimilarity(dog, car!);
    debugPrint('cosine(dog, puppy) = $related');
    debugPrint('cosine(dog, car)   = $unrelated');

    expect(
      related,
      greaterThan(unrelated),
      reason: 'the model does not encode meaning usefully for our vocabulary',
    );
  });

  testWidgets('end to end: "puppy" finds a sticker tagged only "dog"', (
    tester,
  ) async {
    final search = FtsSearchService(db, store, embedder: embedder);
    await store.saveSticker(stickerOf('dog', const ['dog']));
    await store.saveSticker(stickerOf('car', const ['car', 'vehicle']));
    await search.reindex();

    // Keyword search is blind to this by construction — "puppy" shares no
    // characters with "dog" — so a hit can only have come from the embedding.
    final keywordOnly = await FtsSearchService(db, store).query('puppy');
    expect(keywordOnly, isEmpty);

    final hits = await search.query('puppy');
    debugPrint(
      'semantic hits for "puppy": '
      '${hits.map((h) => "${h.record.id}=${h.score.toStringAsFixed(3)}").join(", ")}',
    );

    expect(
      hits.map((h) => h.record.id),
      contains('dog'),
      reason: 'the real model did not rank "dog" close enough to "puppy"',
    );

    // The assertion that matters. USE compresses similarities into a narrow
    // high band — measured cosine(dog,car) = 0.940 against cosine(dog,puppy) =
    // 0.980 — so an absolute threshold admits everything and semantic search
    // silently degrades into "return the whole library, slightly reordered".
    expect(
      hits.map((h) => h.record.id),
      isNot(contains('car')),
      reason: 'an unrelated sticker must be EXCLUDED, not merely outranked',
    );
  });
}
