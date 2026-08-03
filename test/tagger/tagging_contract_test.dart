import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/tagger/tagging_service.dart';

/// Returns fixed tags, or throws. The real backend's vocabulary is not ours to
/// predict, so everything testable about tagging is tested against this.
class FakeTagger implements TaggingService {
  FakeTagger(this.tags);
  FakeTagger.failing() : tags = null;

  final StickerTags? tags;
  int calls = 0;

  @override
  Future<StickerTags> tag(Uint8List imageBytes) async {
    calls++;
    final result = tags;
    if (result == null) throw const TaggingException('vision unavailable');
    return result;
  }
}

void main() {
  group('StickerTags.flatten', () {
    test('includes subjects and the text read out of the image', () async {
      // textInImage is the field most likely to be forgotten, and the one users
      // reach for most — "the sticker that says LOL".
      const tags = StickerTags(
        subjects: ['dog', 'sunglasses'],
        textInImage: 'LOL',
      );

      expect(tags.flatten(), containsAll(['dog', 'sunglasses', 'LOL']));
    });

    test('includes emotion, action and style', () async {
      const tags = StickerTags(
        subjects: ['person'],
        emotion: 'happy',
        action: 'waving',
        style: 'cartoon',
      );

      expect(
        tags.flatten(),
        containsAll(['person', 'happy', 'waving', 'cartoon']),
      );
    });

    test('excludes suggestedName, which becomes the name not a tag', () async {
      // Keeping it would double-count the same words in relevance scoring.
      const tags = StickerTags(subjects: ['dog'], suggestedName: 'Happy dog');
      expect(tags.flatten(), ['dog']);
    });

    test('de-duplicates case-insensitively', () async {
      // ML Kit and OCR can easily both report the same word.
      const tags = StickerTags(
        subjects: ['Dog', 'dog'],
        textInImage: 'DOG',
        action: 'dog',
      );
      expect(tags.flatten(), hasLength(1));
    });

    test('drops blank and whitespace-only entries', () async {
      // An empty tag would add a meaningless token to the searchable text.
      const tags = StickerTags(subjects: ['dog', '', '   '], emotion: '');
      expect(tags.flatten(), ['dog']);
    });

    test('isEmpty reports when vision found nothing usable', () async {
      expect(const StickerTags().isEmpty, isTrue);
      expect(const StickerTags(subjects: ['dog']).isEmpty, isFalse);
      // A name alone is still something worth keeping.
      expect(const StickerTags(suggestedName: 'Dog').isEmpty, isFalse);
    });
  });

  group('TaggingService contract', () {
    final bytes = Uint8List.fromList([1, 2, 3]);

    test('a tagger returns tags for image bytes', () async {
      final tagger = FakeTagger(
        const StickerTags(subjects: ['dog'], suggestedName: 'Dog'),
      );

      final tags = await tagger.tag(bytes);
      expect(tags.subjects, ['dog']);
      expect(tags.suggestedName, 'Dog');
      expect(tagger.calls, 1);
    });

    test(
      'a failing tagger throws TaggingException, not an opaque error',
      () async {
        // The orchestrator distinguishes this from a bug so it can mark the
        // sticker failed and offer a retry.
        await expectLater(
          FakeTagger.failing().tag(bytes),
          throwsA(isA<TaggingException>()),
        );
      },
    );
  });
}
