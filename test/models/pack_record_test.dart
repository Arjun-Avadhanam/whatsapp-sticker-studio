import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';

PackRecord sample() => PackRecord(
  id: 'p1',
  name: 'Inside jokes',
  trayIconPath: 'tray.webp',
  isAnimated: true,
  stickerIds: const ['1', '2', '3'],
  createdAt: DateTime(2026),
);

void main() {
  group('value equality', () {
    test('packs with identical field values are equal', () {
      expect(sample(), equals(sample()));
      expect(sample().hashCode, equals(sample().hashCode));
    });

    test('packs differing in a sticker id are not equal', () {
      expect(sample(), isNot(equals(sample().copyWith(stickerIds: ['1']))));
    });

    test('sticker id order is significant', () {
      final reversed = sample().copyWith(stickerIds: ['3', '2', '1']);

      expect(sample(), isNot(equals(reversed)));
    });
  });

  group('copyWith', () {
    test('changes only the named field', () {
      final renamed = sample().copyWith(name: 'Dog pics');

      expect(renamed.name, 'Dog pics');
      expect(renamed.copyWith(name: 'Inside jokes'), equals(sample()));
    });

    test('returns an equal pack when given no arguments', () {
      expect(sample().copyWith(), equals(sample()));
    });
  });
}
