import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/sources/source.dart';
import 'package:whatsapp_sticker_studio/tagger/tagging_service.dart';
import 'package:whatsapp_sticker_studio/ui/maker_controller.dart';
import 'package:whatsapp_sticker_studio/ui/maker_screen.dart';

import '../app/test_dependencies.dart';

class FakeSource implements Source {
  FakeSource(this._handle);
  FakeSource.cancelled() : _handle = null;
  final MediaHandle? _handle;

  @override
  Future<MediaHandle?> pick() async => _handle;
}

/// Returns a real 1x1 PNG so `Image.memory` in the preview can decode it —
/// canned junk bytes would make the widget throw while painting.
Uint8List onePixelPng() => Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// Encodes to a genuinely decodable image, unlike the byte-filler fake used for
/// pure logic tests.
class PngEncoder implements Encoder {
  PngEncoder({this.kind = StickerKind.staticImage, this.throws});

  final StickerKind kind;
  final Object? throws;
  int calls = 0;

  @override
  Future<EncodedSticker> encode(MediaHandle input, EncodeParams params) async {
    calls++;
    if (throws != null) throw throws!;
    final bytes = onePixelPng();
    return EncodedSticker(
      webpBytes: bytes,
      kind: kind,
      width: 512,
      height: 512,
      sizeBytes: 40960,
      report: const QualityReport(
        fps: 12,
        frames: 24,
        quality: 80,
        sizeBytes: 40960,
      ),
    );
  }
}

MediaHandle image() => MediaHandle(
  bytes: onePixelPng(),
  kind: MediaKind.image,
  mimeType: 'image/png',
);

MediaHandle video() => MediaHandle(
  bytes: onePixelPng(),
  kind: MediaKind.video,
  mimeType: 'video/mp4',
);

void main() {
  late AppDependencies deps;

  Future<MakerController> pump(
    WidgetTester tester, {
    required Source source,
    Encoder? stills,
    Encoder? motion,
    TaggingService? tagger,
  }) async {
    deps = await testDependencies(tagger: tagger);
    addTearDown(deps.dispose);

    final controller = MakerController(
      deps: deps,
      staticEncoder: stills ?? PngEncoder(),
      animatedEncoder: motion ?? PngEncoder(kind: StickerKind.animated),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MakerScreen(
          dependencies: deps,
          controller: controller,
          // Injected so no real gallery or camera opens.
          sources: {'Gallery': source},
        ),
      ),
    );
    return controller;
  }

  /// Scrolls the Maker's ListView to the bottom.
  ///
  /// The list is lazy, so the status card below the Save button is not built at
  /// all until it comes near the viewport — a `findsNothing` there would be the
  /// list, not the widget.
  Future<void> scrollToBottom(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
  }

  testWidgets('starts empty and prompts for media', (tester) async {
    await pump(tester, source: FakeSource(image()));

    expect(find.text('Pick a photo or clip to begin.'), findsOneWidget);
    expect(find.byKey(const Key('sticker-preview')), findsNothing);
  });

  testWidgets('picking shows the preview and the size readout', (tester) async {
    await pump(tester, source: FakeSource(image()));

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sticker-preview')), findsOneWidget);
    // Size against the ceiling is the number that matters: 40960 B = 40 KB of
    // the 100 KB static budget.
    expect(find.byKey(const Key('size-readout')), findsOneWidget);
    expect(find.textContaining('40 KB of 100 KB'), findsOneWidget);
  });

  testWidgets('cancelling a pick leaves the screen as it was', (tester) async {
    // Cancel is an ordinary outcome, so no error and no state change.
    await pump(tester, source: FakeSource.cancelled());

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    expect(find.text('Pick a photo or clip to begin.'), findsOneWidget);
    expect(find.byKey(const Key('sticker-preview')), findsNothing);
  });

  testWidgets('a still shows no clip sliders', (tester) async {
    // Trimming is meaningless for a photo; offering the controls would imply it
    // does something.
    await pump(tester, source: FakeSource(image()));

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start-slider')), findsNothing);
    expect(find.byKey(const Key('length-slider')), findsNothing);
  });

  testWidgets('a video shows clip sliders and the animated readout', (
    tester,
  ) async {
    await pump(tester, source: FakeSource(video()));

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start-slider')), findsOneWidget);
    expect(find.byKey(const Key('length-slider')), findsOneWidget);
    // 500 KB ceiling for animation, and fps/frames become relevant.
    expect(find.textContaining('of 500 KB'), findsOneWidget);
    expect(find.textContaining('12 fps'), findsOneWidget);
  });

  testWidgets('changing fit mode on a VIDEO shows the stale notice', (
    tester,
  ) async {
    final motion = PngEncoder(kind: StickerKind.animated);
    await pump(tester, source: FakeSource(video()), motion: motion);

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(motion.calls, 1);

    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();

    // The whole point of the stale model: no re-encode on a toggle, because a
    // real clip takes ~24 s.
    expect(motion.calls, 1);
    expect(find.byKey(const Key('stale-notice')), findsOneWidget);
    expect(find.text('Update preview'), findsOneWidget);
  });

  testWidgets('Update preview re-encodes and clears the notice', (
    tester,
  ) async {
    final motion = PngEncoder(kind: StickerKind.animated);
    await pump(tester, source: FakeSource(video()), motion: motion);

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update preview'));
    await tester.pumpAndSettle();

    expect(motion.calls, 2);
    expect(find.byKey(const Key('stale-notice')), findsNothing);
  });

  testWidgets('changing fit mode on a STILL never goes stale', (tester) async {
    final stills = PngEncoder();
    await pump(tester, source: FakeSource(image()), stills: stills);

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();

    expect(stills.calls, 2, reason: 'stills re-encode immediately');
    expect(find.byKey(const Key('stale-notice')), findsNothing);
  });

  testWidgets('a budget failure surfaces the trim guidance verbatim', (
    tester,
  ) async {
    // The encoder's message names the remedy that actually works; a generic
    // "encoding failed" would throw that away.
    await pump(
      tester,
      source: FakeSource(video()),
      motion: PngEncoder(
        throws: const EncoderBudgetException(
          'could not fit this clip under 500 KB — try trimming it shorter',
        ),
      ),
    );

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    expect(find.textContaining('try trimming it shorter'), findsOneWidget);
    expect(find.byKey(const Key('sticker-preview')), findsNothing);
  });

  testWidgets('saving persists the sticker and confirms', (tester) async {
    final controller = await pump(tester, source: FakeSource(image()));

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    // save() writes a real file, and testWidgets runs in a fake-time zone where
    // pump() will not let genuine dart:io futures complete. Running the tap
    // itself inside runAsync puts the handler's continuation on the real event
    // loop, so the write and the database insert finish before we look.
    await tester.runAsync(() async {
      await tester.tap(find.text('Save sticker'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    // Then pump manually, NOT pumpAndSettle: settling pumps until no animation
    // remains, and a SnackBar's lifecycle includes auto-dismissing after ~4 s —
    // so it would run straight past the thing being asserted.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Saved to your library'), findsOneWidget);

    // The sticker really is in the library, not merely announced.
    final stored = await deps.store.allStickers();
    expect(stored, hasLength(1));
    expect(stored.single.taggingStatus, isNot(TaggingStatus.failed));

    await controller.pendingTagging; // settle before the db closes
  });

  testWidgets('the saved sticker shows its tags once they land', (
    tester,
  ) async {
    final controller = await pump(tester, source: FakeSource(image()));

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save sticker'));
      // tap() dispatches the gesture but does not await the async handler
      // behind it, so save() has not started writing yet — pendingTagging is
      // still null the instant the tap returns. Give it a turn on the real
      // event loop before asking for the future it creates.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await controller.pendingTagging;
    });
    await tester.pump();
    await scrollToBottom(tester);

    expect(find.byKey(const Key('tagging-status')), findsOneWidget);
    expect(find.byKey(const Key('tagging-tags')), findsOneWidget);
    expect(find.text('dog'), findsOneWidget);
  });

  testWidgets('a tagging failure offers a retry, never looks like loss', (
    tester,
  ) async {
    final controller = await pump(
      tester,
      source: FakeSource(image()),
      tagger: FlakyTagger(), // fails once, then succeeds
    );

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save sticker'));
      // tap() dispatches the gesture but does not await the async handler
      // behind it, so save() has not started writing yet — pendingTagging is
      // still null the instant the tap returns. Give it a turn on the real
      // event loop before asking for the future it creates.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await controller.pendingTagging;
    });
    await tester.pump();
    await scrollToBottom(tester);

    // The sticker is safe and the copy has to say so — a bare "failed" reads as
    // "your sticker is gone".
    expect(find.byKey(const Key('tagging-failed')), findsOneWidget);
    expect(find.text('Sticker saved'), findsOneWidget);
    expect((await deps.store.allStickers()), hasLength(1));

    await tester.runAsync(() async {
      await tester.tap(find.text('Retry'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await controller.pendingTagging;
    });
    await tester.pump();

    expect(find.byKey(const Key('tagging-failed')), findsNothing);
    expect(find.text('dog'), findsOneWidget);
  });
}
