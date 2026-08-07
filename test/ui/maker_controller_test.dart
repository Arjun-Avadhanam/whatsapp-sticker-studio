import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/sources/source.dart';
import 'package:whatsapp_sticker_studio/ui/maker_controller.dart';

import '../app/test_dependencies.dart';

class FakeSource implements Source {
  FakeSource(this._handle);
  FakeSource.cancelled() : _handle = null;
  final MediaHandle? _handle;

  @override
  Future<MediaHandle?> pick() async => _handle;
}

/// Counts encodes so tests can prove a re-encode did — or did not — happen.
class CountingEncoder implements Encoder {
  CountingEncoder({this.throws});

  final Object? throws;
  int calls = 0;
  EncodeParams? lastParams;

  @override
  Future<EncodedSticker> encode(MediaHandle input, EncodeParams params) async {
    calls++;
    lastParams = params;
    if (throws != null) throw throws!;
    return EncodedSticker(
      webpBytes: Uint8List.fromList(List.filled(512, 3)),
      kind: input.kind == MediaKind.image
          ? StickerKind.staticImage
          : StickerKind.animated,
      width: 512,
      height: 512,
      sizeBytes: 512,
      report: const QualityReport(
        fps: 0,
        frames: 1,
        quality: 90,
        sizeBytes: 512,
      ),
    );
  }
}

MediaHandle video() => MediaHandle(
  bytes: Uint8List.fromList(List.filled(64, 2)),
  kind: MediaKind.video,
  mimeType: 'video/mp4',
);

void main() {
  late CountingEncoder stills;
  late CountingEncoder motion;

  Future<MakerController> controller() async {
    final deps = await testDependencies();
    addTearDown(deps.dispose);
    return MakerController(
      deps: deps,
      staticEncoder: stills,
      animatedEncoder: motion,
    );
  }

  setUp(() {
    stills = CountingEncoder();
    motion = CountingEncoder();
  });

  group('picking', () {
    test('a picked still is encoded immediately', () async {
      final c = await controller();
      await c.pickFrom(FakeSource(fakeImage()));

      expect(c.media, isNotNull);
      expect(c.preview, isNotNull);
      expect(stills.calls, 1);
      expect(c.error, isNull);
    });

    test('cancelling leaves the screen untouched and shows no error', () async {
      // Cancel is an ordinary outcome. Showing an error for something the user
      // did deliberately is the wrong response.
      final c = await controller();
      await c.pickFrom(FakeSource.cancelled());

      expect(c.media, isNull);
      expect(c.preview, isNull);
      expect(c.error, isNull);
      expect(stills.calls, 0);
    });
  });

  group('preview freshness', () {
    test('changing fit mode on a STILL re-encodes right away', () async {
      // Stills encode in-memory in well under a second, so a live readout is
      // honest here.
      final c = await controller();
      await c.pickFrom(FakeSource(fakeImage()));

      await c.setFitMode(FitMode.smartCrop);

      expect(stills.calls, 2);
      expect(stills.lastParams!.fitMode, FitMode.smartCrop);
      expect(c.isPreviewStale, isFalse);
    });

    test(
      'changing fit mode on a VIDEO marks stale WITHOUT re-encoding',
      () async {
        // Measured on device: a real gallery video takes ~24 s to encode, because
        // the ladder can run seven ffmpeg passes. Re-encoding per toggle would
        // make the screen unusable.
        final c = await controller();
        await c.pickFrom(FakeSource(video()));
        expect(motion.calls, 1); // the initial encode on load

        await c.setFitMode(FitMode.smartCrop);

        expect(motion.calls, 1, reason: 'must not re-encode on every toggle');
        expect(c.isPreviewStale, isTrue);
      },
    );

    test('an explicit refresh re-encodes and clears the stale flag', () async {
      final c = await controller();
      await c.pickFrom(FakeSource(video()));
      await c.setFitMode(FitMode.smartCrop);

      await c.refreshPreview();

      expect(motion.calls, 2);
      expect(motion.lastParams!.fitMode, FitMode.smartCrop);
      expect(c.isPreviewStale, isFalse);
    });
  });

  group('clip range', () {
    test('a start offset is carried into the encode', () async {
      // Without a start, trimming could only mean "keep the opening", which is
      // rarely the moment someone wants out of a longer video.
      final c = await controller();
      await c.pickFrom(FakeSource(video()));

      await c.setStart(const Duration(seconds: 4));
      await c.refreshPreview();

      expect(motion.lastParams!.start, const Duration(seconds: 4));
    });

    test('start and duration survive each other', () async {
      final c = await controller();
      await c.pickFrom(FakeSource(video()));

      await c.setStart(const Duration(seconds: 4));
      await c.setTrim(const Duration(seconds: 3));
      await c.refreshPreview();

      expect(motion.lastParams!.start, const Duration(seconds: 4));
      expect(motion.lastParams!.trim, const Duration(seconds: 3));
    });

    test('a kept span longer than 10 s is clamped', () async {
      // WhatsApp rejects anything past 10 s outright, so clamp here rather than
      // letting the encoder silently truncate — the readout must show what will
      // actually be produced.
      final c = await controller();
      await c.pickFrom(FakeSource(video()));

      await c.setTrim(const Duration(seconds: 30));

      expect(c.params.trim, const Duration(seconds: 10));
    });

    test('a negative start is floored at zero', () async {
      final c = await controller();
      await c.pickFrom(FakeSource(video()));

      await c.setStart(const Duration(seconds: -5));

      expect(c.params.start, Duration.zero);
    });

    test('changing the range marks an animated preview stale', () async {
      final c = await controller();
      await c.pickFrom(FakeSource(video()));
      expect(motion.calls, 1);

      await c.setStart(const Duration(seconds: 2));

      expect(motion.calls, 1, reason: 'must not re-encode on every drag');
      expect(c.isPreviewStale, isTrue);
    });
  });

  group('saving', () {
    test('a stale preview is re-encoded BEFORE saving', () async {
      // Otherwise a user who changes fit mode and immediately taps Save gets a
      // sticker that looks nothing like what they were shown — silently.
      final c = await controller();
      await c.pickFrom(FakeSource(video()));
      await c.setFitMode(FitMode.smartCrop);
      expect(c.isPreviewStale, isTrue);

      final saved = await c.save();
      await c
          .pendingTagging; // tagging outlives save; settle it before teardown

      expect(motion.calls, 2, reason: 'save must encode the current params');
      expect(motion.lastParams!.fitMode, FitMode.smartCrop);
      expect(saved, isNotNull);
    });

    test('saving persists the sticker and schedules tagging', () async {
      final deps = await testDependencies();
      addTearDown(deps.dispose);
      final c = MakerController(
        deps: deps,
        staticEncoder: stills,
        animatedEncoder: motion,
      );

      await c.pickFrom(FakeSource(fakeImage()));
      final saved = await c.save();

      // Tagging is deliberately not awaited by save(), but the controller keeps
      // the future so it can be observed — without this the work would still be
      // touching the database after the test closed it.
      await c.pendingTagging;

      final stored = await deps.store.getSticker(saved!.id);
      expect(stored, isNotNull);
      expect(stored!.filePath, isNotEmpty);
      // Tagging runs after the save and must not be a precondition for it, so
      // the record exists either way; the fake tagger resolves it to done.
      expect(
        stored.taggingStatus,
        anyOf(TaggingStatus.pending, TaggingStatus.done),
      );
    });

    test('saving with nothing picked does nothing', () async {
      final c = await controller();
      expect(await c.save(), isNull);
    });
  });

  group('encoder failures', () {
    test('undecodable input surfaces a message rather than crashing', () async {
      stills = CountingEncoder(
        throws: const EncoderException('could not decode the image'),
      );
      final c = await controller();

      await c.pickFrom(FakeSource(fakeImage()));

      expect(c.error, contains('could not decode'));
      expect(c.preview, isNull);
    });

    test('a clip that cannot fit surfaces the TRIM guidance verbatim', () async {
      // Cost is near-linear in frame count, so trimming is the strongest lever
      // and EncoderBudgetException already says so. Replacing it with a generic
      // failure would throw away the one piece of advice that actually works.
      motion = CountingEncoder(
        throws: const EncoderBudgetException(
          'could not fit this clip under 500 KB (smallest was 977 KB) — '
          'try trimming it shorter',
        ),
      );
      final c = await controller();

      await c.pickFrom(FakeSource(video()));

      expect(c.error, contains('trimming'));
    });

    test('a failure clears once a later encode succeeds', () async {
      final c = await controller();
      await c.pickFrom(FakeSource(fakeImage()));
      c.debugSetError('something went wrong');

      await c.setFitMode(FitMode.smartCrop);

      expect(c.error, isNull);
    });
  });
}
