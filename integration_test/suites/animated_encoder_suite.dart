import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';
import 'package:whatsapp_sticker_studio/encoder/animated_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';

/// Task 6 — device verification of the animated encoder.
///
/// Sources are generated on-device by ffmpeg rather than committed as binary
/// fixtures, which also keeps the decode path honest: a GIF and an MP4 are both
/// exercised, since real inputs arrive as Giphy/X mp4s and gallery GIFs.
void animatedEncoderTests() {
  late Directory work;
  final encoder = AnimatedEncoder();

  setUp(() async {
    work = await Directory.systemTemp.createTemp('anim_enc');
  });

  tearDown(() async {
    if (work.existsSync()) await work.delete(recursive: true);
  });

  /// Writes [frames] PNGs shaped like a real sticker: a flat background with a
  /// small moving subject.
  ///
  /// Measured on device: this costs ~1.8 KB/frame, so a full 10 s clip lands
  /// around 270 KB — inside the 500 KB ceiling. Detailed, high-frequency
  /// content costs several KB/frame and cannot fill 10 s at all, because output
  /// size is very nearly linear in frame count on this toolchain. Flat fills are
  /// also orders of magnitude cheaper to generate than per-pixel Dart loops,
  /// which dominated this suite's runtime.
  Future<void> writeFrames(
    int frames, {
    required int width,
    required int height,
  }) async {
    for (var i = 0; i < frames; i++) {
      final frame = img.Image(width: width, height: height, numChannels: 4);
      img.fill(frame, color: img.ColorRgba8(30, 120, 200, 255));
      img.fillCircle(
        frame,
        x: (width * (i + 1) ~/ (frames + 1)),
        y: height ~/ 2,
        radius: width ~/ 10,
        color: img.ColorRgba8(255, 220, 0, 255),
      );
      File(
        '${work.path}/f_${i.toString().padLeft(3, '0')}.png',
      ).writeAsBytesSync(img.encodePng(frame));
    }
  }

  /// Muxes the PNG sequence into a real source file for the encoder to consume.
  Future<MediaHandle> buildSource({
    required int frames,
    required int fps,
    required String container, // 'gif' or 'mp4'
    int width = 640,
    int height = 480,
  }) async {
    await writeFrames(frames, width: width, height: height);
    final out = '${work.path}/source.$container';
    // mpeg4 is one of FFmpeg's built-in encoders — this variant has no x264
    // (GPL, deliberately excluded), so H.264 cannot be *written* here. Decoding
    // real-world H.264 mp4s is unaffected: that decoder is built in.
    final codec = container == 'mp4' ? '-c:v mpeg4 -pix_fmt yuv420p' : '';
    final session = await FFmpegKit.execute(
      '-y -framerate $fps -i ${work.path}/f_%03d.png $codec $out',
    );
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      debugPrint('source build failed: ${await session.getAllLogsAsString()}');
    }
    expect(ReturnCode.isSuccess(rc), isTrue, reason: 'could not build source');

    return MediaHandle(
      bytes: File(out).readAsBytesSync(),
      kind: container == 'mp4' ? MediaKind.video : MediaKind.gif,
      mimeType: container == 'mp4' ? 'video/mp4' : 'image/gif',
    );
  }

  /// A deliberately incompressible clip, synthesised by ffmpeg at no Dart cost.
  ///
  /// `testsrc2` alone is *not* hard enough — it is mostly static colour bars, so
  /// libwebp_anim diffs it down and it fits comfortably (measured). The `noise`
  /// filter with `allf=t` re-randomises every pixel on every frame, which
  /// defeats frame diffing by construction and is genuinely unencodable within
  /// the budget. Output is mp4 rather than gif so a 256-colour palette doesn't
  /// quantise the noise back into something compressible.
  Future<MediaHandle> buildHighMotionSource({
    required int seconds,
    required int fps,
  }) async {
    final out = '${work.path}/hard.mp4';
    final session = await FFmpegKit.execute(
      '-y -f lavfi -i testsrc2=s=640x480:r=$fps:d=$seconds '
      '-vf noise=alls=90:allf=t -c:v mpeg4 -q:v 2 $out',
    );
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      debugPrint('lavfi source failed: ${await session.getAllLogsAsString()}');
    }
    expect(ReturnCode.isSuccess(rc), isTrue, reason: 'could not build source');

    return MediaHandle(
      bytes: File(out).readAsBytesSync(),
      kind: MediaKind.video,
      mimeType: 'video/mp4',
    );
  }

  void expectCompliant(EncodedSticker sticker) {
    expect(sticker.kind, StickerKind.animated);
    expect(sticker.width, WhatsAppSpec.dimension);
    expect(sticker.height, WhatsAppSpec.dimension);
    expect(
      sticker.sizeBytes,
      lessThanOrEqualTo(WhatsAppSpec.maxAnimatedBytes),
      reason: 'over the 500 KB animated ceiling',
    );
    expect(
      sticker.report.frames,
      greaterThan(1),
      reason: 'a single-frame "animated" WebP is rejected by WhatsApp',
    );
    expect(
      1000 / sticker.report.fps,
      greaterThanOrEqualTo(WhatsAppSpec.minFrameMs.toDouble()),
      reason: 'frames must last at least 8 ms',
    );
    expect(
      sticker.report.frames / sticker.report.fps * 1000,
      lessThanOrEqualTo(WhatsAppSpec.maxAnimationMs.toDouble()),
      reason: 'animation must not exceed 10 s',
    );
  }

  testWidgets('encodes a GIF into a compliant animated sticker', (
    tester,
  ) async {
    final sticker = await encoder.encode(
      await buildSource(frames: 30, fps: 15, container: 'gif'),
      const EncodeParams(fitMode: FitMode.pad),
    );
    expectCompliant(sticker);
  });

  testWidgets('encodes an MP4 into a compliant animated sticker', (
    tester,
  ) async {
    final sticker = await encoder.encode(
      await buildSource(frames: 30, fps: 15, container: 'mp4'),
      const EncodeParams(fitMode: FitMode.pad),
    );
    expectCompliant(sticker);
  });

  testWidgets('pad keeps the letterbox bars transparent', (tester) async {
    // Same alpha risk already settled for statics — re-checked here because the
    // animated path pads inside an ffmpeg filter chain, not in Dart.
    final sticker = await encoder.encode(
      // Tall source -> bars on the left and right of the square frame.
      await buildSource(
        frames: 12,
        fps: 12,
        container: 'gif',
        width: 240,
        height: 640,
      ),
      const EncodeParams(fitMode: FitMode.pad),
    );

    final decoded = img.decodeWebP(sticker.webpBytes);
    expect(decoded, isNotNull, reason: 'output must be decodable WebP');
    expect(
      decoded!.getPixel(2, WhatsAppSpec.dimension ~/ 2).a,
      0,
      reason: 'left bar should be fully transparent',
    );
  });

  testWidgets('trim shortens the clip', (tester) async {
    // 60 frames at 15 fps = 4 s of source, trimmed to 1 s.
    final sticker = await encoder.encode(
      await buildSource(frames: 60, fps: 15, container: 'gif'),
      const EncodeParams(trim: Duration(seconds: 1)),
    );

    expectCompliant(sticker);
    final durationMs = sticker.report.frames / sticker.report.fps * 1000;
    expect(
      durationMs,
      lessThanOrEqualTo(1500),
      reason: 'trim to 1 s should not yield ${durationMs}ms',
    );
  });

  testWidgets('caps a source longer than the 10 s animation limit', (
    tester,
  ) async {
    // 180 frames at 15 fps = 12 s, which exceeds WhatsApp's ceiling.
    final sticker = await encoder.encode(
      await buildSource(frames: 180, fps: 15, container: 'gif'),
      const EncodeParams(),
    );
    // expectCompliant already asserts total duration <= 10 s.
    expectCompliant(sticker);
  });

  testWidgets('refuses a clip that cannot fit, pointing at trimming', (
    tester,
  ) async {
    // Dense high-frequency detail costs several KB per frame, and size is very
    // nearly linear in frame count here, so 12 s of it cannot fit at any rung.
    //
    // Real stickers are flat-ish and land far below the ceiling; this is the
    // pathological case. It is pinned because the behaviour matters: emitting an
    // oversize file would surface as an opaque WhatsApp rejection at export. The
    // distinct exception type lets the Maker suggest the remedy that actually
    // works — trim it shorter, rather than degrade quality further.
    await expectLater(
      encoder.encode(
        await buildHighMotionSource(seconds: 12, fps: 15),
        const EncodeParams(),
      ),
      throwsA(
        isA<EncoderBudgetException>().having(
          (e) => e.message,
          'message',
          contains('trimming'),
        ),
      ),
    );
  });

  group('promoteStatic', () {
    testWidgets('turns a static image into a multi-frame animated sticker', (
      tester,
    ) async {
      // Used when a static sticker joins an animated pack, so the user never
      // sees a mixed-kind error. Two identical frames is the documented floor:
      // WhatsApp's validator checks frameCount <= 1, not whether ANIM exists.
      final still = img.Image(width: 512, height: 512, numChannels: 4);
      img.fill(still, color: img.ColorRgba8(200, 40, 90, 255));

      final promoted = await encoder.promoteStatic(
        Uint8List.fromList(img.encodePng(still)),
      );

      expectCompliant(promoted);
      expect(promoted.report.frames, greaterThanOrEqualTo(2));
      // Promotion moves the sticker from the 100 KB budget to the 500 KB one.
      expect(
        promoted.sizeBytes,
        lessThanOrEqualTo(WhatsAppSpec.maxAnimatedBytes),
      );
    });
  });
}
