import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';

/// A fresh, fully-populated record. A function rather than a shared constant so
/// each test gets its own instance — proving equality compares *values*, not
/// object identity.
StickerRecord sample() => StickerRecord(
  id: '1',
  filePath: 'a.webp',
  thumbnailPath: 't.webp',
  kind: StickerKind.animated,
  packId: null,
  autoTags: const ['dog', 'high five'],
  manualName: 'Ana high five',
  manualTags: const ['friends'],
  notes: 'inside joke',
  source: StickerSource.maker,
  createdAt: DateTime(2026),
  usageCount: 0,
  sizeBytes: 400000,
  taggingStatus: TaggingStatus.done,
);

void main() {
  group('searchBlob', () {
    test('concatenates all searchable text', () {
      final blob = sample().searchBlob().toLowerCase();

      for (final term in [
        'dog',
        'high five',
        'ana',
        'friends',
        'inside joke',
      ]) {
        expect(blob.contains(term), isTrue, reason: 'missing "$term"');
      }
    });

    test('skips null fields without leaving stray separators', () {
      final blob = sample()
          .copyWith(manualName: null, notes: null)
          .searchBlob();

      expect(blob, isNot(contains('  ')));
      expect(blob.trim(), blob);
    });
  });

  group('value equality', () {
    test('records with identical field values are equal', () {
      expect(sample(), equals(sample()));
      expect(sample().hashCode, equals(sample().hashCode));
    });

    test('records differing in a scalar field are not equal', () {
      expect(sample(), isNot(equals(sample().copyWith(usageCount: 5))));
    });

    test('records differing in a list element are not equal', () {
      expect(sample(), isNot(equals(sample().copyWith(autoTags: ['cat']))));
    });

    test('equal records agree on hashCode across list contents', () {
      final a = sample().copyWith(autoTags: ['cat', 'hat']);
      final b = sample().copyWith(autoTags: ['cat', 'hat']);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('copyWith', () {
    test('changes only the named field', () {
      final bumped = sample().copyWith(usageCount: 5);

      expect(bumped.usageCount, 5);
      expect(bumped.copyWith(usageCount: 0), equals(sample()));
    });

    test('can clear a nullable field', () {
      expect(sample().copyWith(manualName: null).manualName, isNull);
    });

    test('returns an equal record when given no arguments', () {
      expect(sample().copyWith(), equals(sample()));
    });
  });
}
