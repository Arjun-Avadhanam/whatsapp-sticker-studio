import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/search/search_service.dart';
import 'package:whatsapp_sticker_studio/search/text_embedder.dart';

/// A deterministic stand-in for the real model.
///
/// Real embeddings are 512 opaque floats whose values we cannot predict, so
/// asserting on them would test the model rather than our code. This maps a few
/// known words onto hand-built vectors with the *relationships* we care about —
/// "puppy" close to "dog", "car" far from both — which is exactly what the
/// blending and thresholding logic needs in order to be tested at all. That the
/// real model produces sensible relationships is a separate, device-only claim.
class FakeTextEmbedder implements TextEmbedder {
  FakeTextEmbedder(this.vectors);

  final Map<String, List<double>> vectors;
  final List<String> embedded = [];

  @override
  Future<List<double>?> embed(String text) async {
    embedded.add(text);
    final lower = text.toLowerCase();
    for (final entry in vectors.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }
}

/// Always fails, standing in for a missing or broken model.
class UnavailableEmbedder implements TextEmbedder {
  @override
  Future<List<double>?> embed(String text) async => null;
}

StickerRecord stickerOf({
  required String id,
  List<String> autoTags = const [],
  String? manualName,
  int usageCount = 0,
}) => StickerRecord(
  id: id,
  filePath: '$id.webp',
  thumbnailPath: '${id}_t.webp',
  kind: StickerKind.staticImage,
  packId: null,
  autoTags: autoTags,
  manualName: manualName,
  manualTags: const [],
  notes: null,
  source: StickerSource.maker,
  createdAt: DateTime(2026),
  usageCount: usageCount,
  sizeBytes: 50000,
  taggingStatus: TaggingStatus.done,
);

void main() {
  // Three directions in a tiny vector space: dog and puppy point almost the same
  // way; car points elsewhere.
  const dog = [1.0, 0.0, 0.0];
  const puppy = [0.95, 0.31, 0.0];
  const car = [0.0, 0.0, 1.0];

  late AppDatabase db;
  late LibraryStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLibraryStore(db);
  });

  tearDown(() => db.close());

  FtsSearchService serviceWith(TextEmbedder? embedder) =>
      FtsSearchService(db, store, embedder: embedder);

  group('cosineSimilarity', () {
    test('identical directions score 1, orthogonal score 0', () {
      expect(cosineSimilarity(dog, dog), closeTo(1.0, 1e-9));
      expect(cosineSimilarity(dog, car), closeTo(0.0, 1e-9));
    });

    test('related directions score high, unrelated low', () {
      expect(cosineSimilarity(dog, puppy), greaterThan(0.9));
      expect(cosineSimilarity(puppy, car), lessThan(0.2));
    });

    test('a zero vector scores 0 rather than NaN', () {
      // NaN would poison the sort and scramble the whole result list.
      final score = cosineSimilarity(dog, const [0.0, 0.0, 0.0]);
      expect(score.isNaN, isFalse);
      expect(score, 0);
    });

    test('mismatched lengths score 0 rather than throwing', () {
      expect(cosineSimilarity(dog, const [1.0, 0.0]), 0);
    });
  });

  group('semantic search', () {
    test('finds a sticker by meaning when keyword search cannot', () async {
      // The headline case: "puppy" shares no characters with "dog", so FTS
      // returns nothing at all. If this passes, semantic search is adding
      // something keyword search fundamentally cannot.
      final search = serviceWith(
        FakeTextEmbedder({'dog': dog, 'puppy': puppy, 'car': car}),
      );
      await store.saveSticker(stickerOf(id: 'd', autoTags: const ['dog']));
      await store.saveSticker(stickerOf(id: 'c', autoTags: const ['car']));
      await search.reindex();

      // Prove keyword search really is blind to it, so the next assertion
      // cannot pass for the wrong reason.
      final keywordOnly = await serviceWith(null).query('puppy');
      expect(keywordOnly, isEmpty);

      final hits = await search.query('puppy');
      expect(hits.map((h) => h.record.id), contains('d'));

      // The assertion that actually matters, and the one whose absence let a
      // broken threshold pass on device: the unrelated sticker must be
      // EXCLUDED, not merely ranked lower. "contains the right answer" is
      // satisfied by returning the entire library.
      expect(
        hits.map((h) => h.record.id),
        isNot(contains('c')),
        reason: 'an unrelated sticker must not be a semantic match at all',
      );
    });

    test('a library of equally-unrelated stickers yields nothing', () async {
      // With only one candidate there is no spread, so nothing can stand out.
      // Returning it anyway would dress an arbitrary sticker up as a match.
      final search = serviceWith(
        FakeTextEmbedder({'dog': dog, 'puppy': puppy, 'car': car}),
      );
      await store.saveSticker(stickerOf(id: 'c', autoTags: const ['car']));
      await search.reindex();

      expect(await search.query('puppy'), isEmpty);
    });

    test(
      'ranking is relative, so a compressed similarity band still works',
      () async {
        // Mirrors what the real model does: measured on device, cosine(dog,puppy)
        // = 0.980 and cosine(dog,car) = 0.940 — a 0.04 margin. No absolute
        // threshold separates those, so scoring must be relative to the field.
        const nearDog = [1.0, 0.0, 0.0];
        const nearPuppy = [0.9998, 0.0199, 0.0]; // ~0.98 to dog
        const nearCar = [0.9945, 0.1045, 0.0]; // ~0.94 to dog — still very high

        final search = serviceWith(
          FakeTextEmbedder({
            'dog': nearDog,
            'puppy': nearPuppy,
            'car': nearCar,
          }),
        );
        await store.saveSticker(stickerOf(id: 'd', autoTags: const ['dog']));
        await store.saveSticker(stickerOf(id: 'c', autoTags: const ['car']));
        await search.reindex();

        final hits = await search.query('puppy');
        expect(hits.map((h) => h.record.id), contains('d'));
        expect(
          hits.map((h) => h.record.id),
          isNot(contains('c')),
          reason: 'a 0.94-similarity distractor must still be rejected',
        );
      },
    );

    test('a keyword match still outranks a merely-similar one', () async {
      final search = serviceWith(
        FakeTextEmbedder({'dog': dog, 'puppy': puppy}),
      );
      await store.saveSticker(
        stickerOf(id: 'exact', autoTags: const ['puppy']),
      );
      await store.saveSticker(
        stickerOf(id: 'similar', autoTags: const ['dog']),
      );
      await search.reindex();

      final hits = await search.query('puppy');
      expect(hits.first.record.id, 'exact');
    });
  });

  group('degradation', () {
    test('search still works when no embedder is supplied', () async {
      final search = serviceWith(null);
      await store.saveSticker(stickerOf(id: 'd', autoTags: const ['dog']));
      await search.reindex();

      expect((await search.query('dog')).map((h) => h.record.id), ['d']);
    });

    test('search still works when the embedder always fails', () async {
      // A missing or broken model must degrade to keyword-only, never take the
      // query down with it.
      final search = serviceWith(UnavailableEmbedder());
      await store.saveSticker(stickerOf(id: 'd', autoTags: const ['dog']));
      await search.reindex();

      expect((await search.query('dog')).map((h) => h.record.id), ['d']);
    });

    test(
      'a sticker with no searchable text is skipped, not embedded',
      () async {
        final embedder = FakeTextEmbedder({'dog': dog});
        final search = serviceWith(embedder);
        await store.saveSticker(stickerOf(id: 'blank'));
        await search.reindex();

        expect(embedder.embedded, isEmpty);
      },
    );
  });
}
