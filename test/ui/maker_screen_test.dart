import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/sources/giphy_client.dart';
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
    Source Function(String)? xLinkSource,
    Future<Source?> Function(BuildContext)? gifSource,
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
          xLinkSource: xLinkSource,
          gifSource: gifSource,
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

  /// Alternates real-event-loop windows with pumped frames until [done] holds.
  ///
  /// A fixed delay is fragile for anything reaching **disk** — saving a sticker,
  /// writing a tray icon. Under full-suite load a 300 ms window is not always
  /// enough, and this test flaked exactly that way while passing in isolation.
  /// Waiting on the condition removes the race without slowing the fast case.
  Future<void> settleUntil(
    WidgetTester tester,
    bool Function() done, {
    int tries = 25,
  }) async {
    for (var i = 0; i < tries && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool present(Key key) => find.byKey(key).evaluate().isNotEmpty;

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

  testWidgets('a saved sticker can be filed into a pack', (tester) async {
    // Only a pack reaches WhatsApp — a loose sticker cannot — so this path is
    // what makes a saved sticker usable at all.
    final controller = await pump(tester, source: FakeSource(image()));

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save sticker'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await controller.pendingTagging;
    });
    await tester.pump();
    await scrollToBottom(tester);

    await tester.tap(find.byKey(const Key('add-to-pack')));
    // Not pumpAndSettle: the sheet shows an indeterminate spinner while it
    // loads, which schedules frames forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Add to pack'), findsWidgets);
    expect(find.text('New pack'), findsOneWidget);

    // Naming it creates the pack, and the export card appears READY with a
    // single sticker: the enforced floor is 1, so one sticker can go straight to
    // WhatsApp without inventing two more. See
    // WhatsAppSpec.enforcedMinStickersPerPack.
    await tester.tap(find.text('New pack'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('pack-name')), 'Road trip');
    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settleUntil(tester, () => present(const Key('export-card')));
    await scrollToBottom(tester);

    expect(find.byKey(const Key('export-card')), findsOneWidget);
    expect(find.textContaining('1 sticker · ready'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('export-button')),
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'one sticker is enough to send to WhatsApp',
    );
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

  group('the X link button', () {
    /// Drives the button's dialog with [link] and returns once the pick is done.
    Future<void> pasteLink(WidgetTester tester, String link) async {
      await tester.tap(find.byKey(const Key('x-link-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('x-link-field')), link);
      await tester.pump();
      await tester.tap(find.byKey(const Key('x-link-submit')));
      await tester.pumpAndSettle();
    }

    testWidgets('is hidden when the build has no extractor configured', (
      tester,
    ) async {
      // test dependencies carry no service address, which is also the state of
      // a release build made without --dart-define. A button that could only
      // ever fail is worse than no button.
      await pump(tester, source: FakeSource(image()));

      expect(find.byKey(const Key('x-link-button')), findsNothing);
    });

    testWidgets('turns a pasted link into media on the Maker', (tester) async {
      // The whole point: the post's video lands in the same editor as a gallery
      // pick, with the same fit modes and the same Save.
      String? asked;
      await pump(
        tester,
        source: FakeSource.cancelled(),
        xLinkSource: (link) {
          asked = link;
          return FakeSource(video());
        },
      );

      await pasteLink(tester, 'https://x.com/a/status/2087646138526802000?s=9');

      expect(
        asked,
        'https://x.com/i/status/2087646138526802000',
        reason: 'normalised before it leaves the app',
      );
      expect(find.byKey(const Key('sticker-preview')), findsOneWidget);
    });

    testWidgets('a failure is shown, not swallowed as a cancel', (
      tester,
    ) async {
      // This is the whole reason SourceException exists. Returning null meant a
      // dead network and a video-less post both left the screen inert, which
      // reads as a broken app rather than a bad link.
      await pump(
        tester,
        source: FakeSource.cancelled(),
        xLinkSource: (_) =>
            ThrowingSource('No video could be found in this tweet'),
      );

      await pasteLink(tester, 'https://x.com/a/status/2087646138526802000');

      // Verbatim: the service's wording separates "no video here" from "post
      // not found" from an outage, and we cannot tell those apart ourselves.
      expect(
        find.text('No video could be found in this tweet'),
        findsOneWidget,
      );

      // And it takes itself away again. Found on device: the banner sat on the
      // Maker indefinitely after a mistyped link, long after it had been read.
      // Nothing can be acted on from it — the remedy is a different link.
      await tester.pump(
        const Duration(seconds: 5) + const Duration(seconds: 1),
      );

      expect(find.text('No video could be found in this tweet'), findsNothing);
    });

    testWidgets('never covers Add to WhatsApp', (tester) async {
      // A floating button sits over the bottom-right of the body, and the list
      // ends with the export card — the single most important action here. The
      // list's bottom padding is what keeps them apart, so this asserts the
      // geometry rather than the padding value: the constant can change, the
      // overlap must not come back.
      final controller = await pump(
        tester,
        source: FakeSource(image()),
        xLinkSource: (_) => FakeSource(video()),
      );

      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save sticker'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await controller.pendingTagging;
      });
      await tester.pump();
      await scrollToBottom(tester);

      await tester.tap(find.byKey(const Key('add-to-pack')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('New pack'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('pack-name')), 'Road trip');
      await tester.runAsync(() async {
        await tester.tap(find.text('Create'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settleUntil(tester, () => present(const Key('export-card')));

      // Scrolled hard to the bottom, which is exactly where the two would
      // collide if the list had no clearance.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      final exportButton = tester.getRect(
        find.byKey(const Key('export-button')),
      );
      final fab = tester.getRect(find.byKey(const Key('x-link-button')));

      expect(
        exportButton.overlaps(fab),
        isFalse,
        reason:
            'the X button covered Add to WhatsApp — the list needs bottom '
            'padding at least as tall as the button plus its margin',
      );
    });
  });

  group('the GIF button', () {
    testWidgets('is hidden when the build has no Giphy key', (tester) async {
      // test dependencies carry no key, which is also the state of a release
      // build made without --dart-define. A button that could only ever fail is
      // worse than an absent one.
      await pump(tester, source: FakeSource(image()));

      expect(find.byKey(const Key('source-gif')), findsNothing);
    });

    testWidgets('a chosen GIF loads into the Maker like any other media', (
      tester,
    ) async {
      // The point of routing through pickFrom: a Giphy pick gets the same
      // preview, fit modes, trim and Save as a gallery clip, with no special
      // casing anywhere downstream.
      await pump(
        tester,
        source: FakeSource.cancelled(),
        gifSource: (_) async => FakeSource(video()),
      );

      await tester.tap(find.byKey(const Key('source-gif')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sticker-preview')), findsOneWidget);
    });

    testWidgets('backing out of the picker changes nothing', (tester) async {
      // Cancelling is an ordinary choice, not a failure — no banner, no media,
      // no snackbar.
      await pump(
        tester,
        source: FakeSource.cancelled(),
        gifSource: (_) async => null,
      );

      await tester.tap(find.byKey(const Key('source-gif')));
      await tester.pumpAndSettle();

      // Still the untouched opening state: no media, and no complaint about
      // something the user chose to do.
      expect(find.byKey(const Key('sticker-preview')), findsNothing);
      expect(find.text('Pick a photo or clip to begin.'), findsOneWidget);
    });

    testWidgets('the REAL picker path works end to end', (tester) async {
      // Every other test here injects a stub source, which leaves the wiring
      // production actually uses — build a client from the key, open the
      // picker, wrap the chosen gif in a GiphySource — completely untested.
      // This drives the whole thing over a mocked transport instead.
      final deps = await testDependencies(
        giphy: GiphyClient(
          MockClient(
            (req) async => http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'g1',
                    'title': 'a gif',
                    'images': {
                      'preview_gif': {'url': 'https://x/p.gif'},
                      'original': {'mp4': 'https://x/o.mp4'},
                    },
                  },
                ],
                'pagination': {'total_count': 1, 'offset': 0},
              }),
              200,
            ),
          ),
          apiKey: 'k',
        ),
        // Answers the mp4 download that GiphySource makes after the pick.
        httpClient: MockClient(
          (req) async => http.Response.bytes(onePixelPng(), 200),
        ),
      );
      addTearDown(deps.dispose);

      final controller = MakerController(
        deps: deps,
        staticEncoder: PngEncoder(),
        animatedEncoder: PngEncoder(kind: StickerKind.animated),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MakerScreen(dependencies: deps, controller: controller),
        ),
      );
      await tester.pump();

      // The key is present, so the button exists without being injected.
      expect(find.byKey(const Key('source-gif')), findsOneWidget);

      await tester.tap(find.byKey(const Key('source-gif')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('giphy-grid')), findsOneWidget);

      await tester.tap(find.byKey(const Key('giphy-gif-g1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sticker-preview')), findsOneWidget);
    });

    testWidgets('a failed download is shown, then clears itself', (
      tester,
    ) async {
      // GiphySource throws SourceException rather than returning null, so this
      // reaches the same banner as a bad X link — and self-clears for the same
      // reason: nothing can be acted on from it.
      await pump(
        tester,
        source: FakeSource.cancelled(),
        gifSource: (_) async =>
            ThrowingSource("That GIF couldn't be downloaded (HTTP 404)."),
      );

      await tester.tap(find.byKey(const Key('source-gif')));
      await tester.pumpAndSettle();

      expect(
        find.text("That GIF couldn't be downloaded (HTTP 404)."),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 6));

      expect(
        find.text("That GIF couldn't be downloaded (HTTP 404)."),
        findsNothing,
      );
    });
  });
}

/// A source that fails the way a remote one does.
class ThrowingSource implements Source {
  ThrowingSource(this.message);
  final String message;

  @override
  Future<MediaHandle?> pick() async => throw SourceException(message);
}
