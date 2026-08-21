import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/ui/send_sticker_action.dart';

import '../app/test_dependencies.dart';

void main() {
  late AppDependencies deps;

  setUp(() async => deps = await testDependencies());
  tearDown(() => deps.dispose());

  /// Saves a sticker with a real file, since a pack needs a tray icon made from
  /// it. Written synchronously: async `dart:io` never completes in the
  /// fake-time zone `testWidgets` runs in.
  Future<StickerRecord> save({
    String id = 's1',
    String? manualName,
    List<String> autoTags = const [],
  }) async {
    final path = '${deps.stickerDirectory.path}/$id.webp';
    File(path).writeAsBytesSync(onePixelPng());

    final record = StickerRecord(
      id: id,
      filePath: path,
      thumbnailPath: path,
      kind: StickerKind.staticImage,
      packId: null,
      autoTags: autoTags,
      manualName: manualName,
      manualTags: const [],
      notes: null,
      source: StickerSource.maker,
      createdAt: DateTime(2026, 8, 19),
      usageCount: 0,
      sizeBytes: 512,
      taggingStatus: TaggingStatus.done,
    );
    await deps.store.saveSticker(record);
    return record;
  }

  group('the pack is named after the sticker', () {
    // This name is the ONLY text WhatsApp renders for the sticker, which is the
    // entire reason the feature exists, so each fallback matters.

    test('the user\'s own name wins', () {
      expect(
        packNameFor(_stickerNamed('Captain Beer', tags: const ['drink'])),
        'Captain Beer',
      );
    });

    test('auto-tags stand in when there is no name', () {
      // Generic, but they do describe the picture, and something beats
      // "Sticker".
      expect(
        packNameFor(_stickerNamed(null, tags: const ['dog', 'pet'])),
        'dog, pet',
      );
    });

    test('a neutral fallback when there is nothing at all', () {
      // A pack must have a name; an empty one fails WhatsApp's validation, so
      // there is no option to send it nameless.
      expect(packNameFor(_stickerNamed(null)), 'Sticker');
      expect(packNameFor(_stickerNamed('   ')), 'Sticker');
    });

    test('a very long name is truncated, never refused', () {
      // Losing the tail of a name beats losing the sticker.
      final long = 'a' * 300;
      expect(packNameFor(_stickerNamed(long)).length, 128);
    });
  });

  testWidgets('the sticker survives, and the wrapper pack does not', (
    tester,
  ) async {
    // The two claims the whole feature rests on. The pack is scaffolding: it
    // exists to carry the name across, and leaving it behind would both clutter
    // the Packs tab and burn one of the ten packs an app may publish.
    final sticker = await save(manualName: 'Captain Beer');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => sendStickerToWhatsApp(
                context: context,
                dependencies: deps,
                sticker: sticker,
              ),
              child: const Text('send'),
            ),
          ),
        ),
      ),
    );

    // Started inside runAsync because creating the pack writes a tray icon to
    // disk, and genuine `dart:io` never completes in the fake-time zone a
    // testWidgets body runs in — it hangs with no error at all.
    await tester.runAsync(() async {
      await tester.tap(find.text('send'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();

    // Confirmation dialog: nothing reaches WhatsApp unsolicited.
    expect(find.text('Add to WhatsApp?'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Add'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();

    final exported = (deps.exporter as FakeExporter).exported;
    expect(exported, hasLength(1));
    expect(
      exported.single.name,
      'Captain Beer',
      reason: 'the pack name is what WhatsApp will show for this sticker',
    );

    expect(await deps.store.allPacks(), isEmpty, reason: 'wrapper discarded');
    final kept = await deps.store.getSticker(sticker.id);
    expect(kept, isNotNull, reason: 'the sticker itself must survive');
    expect(kept!.packId, isNull, reason: 'and belong to no pack afterwards');
    expect(File(kept.filePath).existsSync(), isTrue);
  });

  testWidgets('backing out leaves no wrapper pack behind', (tester) async {
    // Cancelling is ordinary. It must not leave the user with a pack they never
    // asked for and cannot explain.
    final sticker = await save(manualName: 'Captain Beer');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => sendStickerToWhatsApp(
                context: context,
                dependencies: deps,
                sticker: sticker,
              ),
              child: const Text('send'),
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('send'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Cancel'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();

    expect((deps.exporter as FakeExporter).exported, isEmpty);
    expect(await deps.store.allPacks(), isEmpty);
    expect(await deps.store.getSticker(sticker.id), isNotNull);
  });
}

StickerRecord _stickerNamed(String? name, {List<String> tags = const []}) =>
    StickerRecord(
      id: 'x',
      filePath: '/x.webp',
      thumbnailPath: '/x.webp',
      kind: StickerKind.staticImage,
      packId: null,
      autoTags: tags,
      manualName: name,
      manualTags: const [],
      notes: null,
      source: StickerSource.maker,
      createdAt: DateTime(2026, 8, 19),
      usageCount: 0,
      sizeBytes: 512,
      taggingStatus: TaggingStatus.done,
    );
