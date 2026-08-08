import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

import '../core/media.dart';
import '../core/whatsapp_spec.dart';
import 'encoder.dart';

/// One rung of the degradation ladder.
class _Attempt {
  const _Attempt(this.fps, this.quality);
  final int fps;
  final int quality;
}

/// Encodes GIF/video into a compliant 512×512 **animated** WebP sticker.
///
/// Unlike [StaticEncoder], the geometry is not done in Dart: ffmpeg has to
/// decode, scale, pad and re-time every frame anyway, so doing the fit inside
/// its filter chain avoids shuttling raw frames across the platform boundary.
/// ffmpeg is required here regardless — Android has no built-in animated-WebP
/// encoder at any API level.
class AnimatedEncoder implements Encoder, StaticPromoter {
  const AnimatedEncoder();

  static const int _dim = WhatsAppSpec.dimension;

  /// Tried in order; the first output at or under the ceiling wins.
  ///
  /// **Measured on device 2026-07-29 — cost is very nearly LINEAR IN FRAME
  /// COUNT here, so fps and duration are the dominant levers.** The theory that
  /// inter-frame compression makes frame count a poor predictor does not hold
  /// for this toolchain: 10 identical frames cost 10.09× a single frame and 40
  /// cost 40.28×, with moving content within 2% of identical content. Even
  /// `libwebp_anim`, which does diff frames, only recovers ~16%.
  ///
  /// Practical consequence: usable frames ≈ 500 KB ÷ per-frame cost. A simple
  /// sticker (flat background, small moving subject) runs ~1.8 KB/frame and can
  /// fill the full 10 s; a detailed one runs several KB/frame and cannot. Still
  /// **encode and measure** rather than predicting — per-frame cost varies with
  /// content — but expect dropping fps to pay off proportionally.
  static const List<_Attempt> _ladder = [
    _Attempt(15, 80),
    _Attempt(12, 80),
    _Attempt(12, 70),
    _Attempt(10, 70),
    _Attempt(8, 65),
    _Attempt(8, 50),
    _Attempt(6, 40),
  ];

  @override
  Future<EncodedSticker> encode(MediaHandle input, EncodeParams params) async {
    final work = await Directory.systemTemp.createTemp('anim_encode');
    try {
      final source = File('${work.path}/source${_extensionFor(input)}');
      await source.writeAsBytes(input.bytes);

      // Cap at WhatsApp's 10 s limit even when the caller asked for more (or
      // for nothing at all) — an over-long animation is rejected outright.
      final maxSeconds = WhatsAppSpec.maxAnimationMs / 1000;
      final seconds = params.trim == null
          ? maxSeconds
          : math.min(params.trim!.inMilliseconds / 1000, maxSeconds);

      // `-ss` goes AFTER `-i`, which is the frame-accurate form: ffmpeg decodes
      // from the beginning and starts emitting at the requested instant. The
      // faster pre-input form seeks to the nearest keyframe and can land a few
      // hundred milliseconds off — fine for a long video, but these clips are
      // 1–3 s, so being off by a fraction of a second can miss the moment the
      // user was aiming at entirely. Accuracy is worth the extra decode.
      final startSeconds = params.start.inMilliseconds / 1000;
      final seek = startSeconds > 0 ? '-ss $startSeconds ' : '';

      return await _runLadder(
        work: work,
        inputArgs: '-i ${source.path}',
        durationArgs: '$seek-t $seconds',
        fitMode: params.fitMode,
        what: 'this clip',
      );
    } finally {
      if (work.existsSync()) await work.delete(recursive: true);
    }
  }

  /// Re-encodes a still image as an animated WebP of **≥2 identical frames**.
  ///
  /// Used when a static sticker joins an animated pack, so the user never meets
  /// the pack-homogeneity rule (see `CLAUDE.md`). A **single**-frame "animated"
  /// WebP does not work: WhatsApp's validator tests `getFrameCount() <= 1`, not
  /// whether an ANIM chunk exists, so one frame is rejected exactly like a
  /// static file. Two is the floor and there is no minimum total duration.
  ///
  /// Promotion moves the sticker from the 100 KB static budget to the 500 KB
  /// animated one, so quality goes *up*, never down.
  @override
  Future<EncodedSticker> promoteStatic(Uint8List stillBytes) async {
    final work = await Directory.systemTemp.createTemp('promote');
    try {
      final source = File('${work.path}/still${_sniffExtension(stillBytes)}');
      await source.writeAsBytes(stillBytes);

      // -loop 1 re-reads the still forever; -frames:v 2 stops at two. At 10 fps
      // each frame lasts 100 ms — comfortably above the 8 ms minimum.
      return await _runLadder(
        work: work,
        inputArgs: '-loop 1 -i ${source.path}',
        durationArgs: '-frames:v 2',
        fitMode: FitMode.pad,
        what: 'this image',
        ladder: const [_Attempt(10, 90), _Attempt(10, 75), _Attempt(10, 50)],
        // MUST be the plain encoder. libwebp_anim diffs consecutive frames, and
        // two *identical* frames diff to nothing — it collapses them into one,
        // which WhatsApp then rejects exactly like a static file. Verified on
        // device. There is no compression to lose here: two frames of a still
        // image are tiny against the 500 KB animated budget.
        codec: 'libwebp',
      );
    } finally {
      if (work.existsSync()) await work.delete(recursive: true);
    }
  }

  /// Encodes repeatedly, stepping down the ladder until the output fits.
  Future<EncodedSticker> _runLadder({
    required Directory work,
    required String inputArgs,
    required String durationArgs,
    required FitMode fitMode,
    required String what,
    List<_Attempt> ladder = _ladder,
    String codec = 'libwebp_anim',
  }) async {
    var smallest = -1;

    for (final attempt in ladder) {
      final out = File(
        '${work.path}/out_${attempt.fps}_${attempt.quality}.webp',
      );
      final session = await FFmpegKit.execute(
        '-y $inputArgs $durationArgs -an '
        '-vf "${_filterChain(fitMode, attempt.fps)}" '
        // libwebp_anim drives libwebp's WebPAnimEncoder, which diffs frames and
        // handles disposal; the plain libwebp encoder leaves the muxer to
        // concatenate independent full frames. Measured ~16% smaller output.
        // See promoteStatic for the one case that must NOT use it.
        '-c:v $codec -lossless 0 -q:v ${attempt.quality} -loop 0 '
        '${out.path}',
      );

      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        throw EncoderException(
          'ffmpeg could not encode $what: ${await session.getFailStackTrace() ?? await session.getAllLogsAsString()}',
        );
      }

      final bytes = await out.readAsBytes();
      if (smallest < 0 || bytes.length < smallest) smallest = bytes.length;

      if (bytes.length <= WhatsAppSpec.maxAnimatedBytes) {
        final frames = _countFrames(bytes);
        if (frames <= 1) {
          // Would be rejected by WhatsApp exactly like a static file, so it is
          // never a valid result no matter how small it is.
          throw EncoderException(
            'encoding $what produced a single frame, which WhatsApp rejects',
          );
        }
        return EncodedSticker(
          webpBytes: bytes,
          kind: StickerKind.animated,
          width: _dim,
          height: _dim,
          sizeBytes: bytes.length,
          report: QualityReport(
            fps: attempt.fps,
            frames: frames,
            quality: attempt.quality,
            sizeBytes: bytes.length,
          ),
        );
      }
    }

    // Never emit an oversize file: WhatsApp would reject it at export, long
    // after the user made the sticker. Trimming is the user's best lever here,
    // which is why this is a budget error rather than a generic failure.
    throw EncoderBudgetException(
      'could not fit $what under ${WhatsAppSpec.maxAnimatedBytes ~/ 1024} KB '
      '(smallest was ${smallest ~/ 1024} KB) — try trimming it shorter',
    );
  }

  /// Fit geometry, expressed as an ffmpeg filter chain.
  ///
  /// `format=rgba` comes **before** the pad so there is an alpha channel to pad
  /// *into*: video sources decode to yuv420p, which has none, and the letterbox
  /// bars would come out black instead of transparent.
  String _filterChain(FitMode mode, int fps) {
    switch (mode) {
      case FitMode.pad:
      case FitMode.contain:
        return 'fps=$fps,format=rgba,'
            'scale=$_dim:$_dim:force_original_aspect_ratio=decrease,'
            'pad=$_dim:$_dim:(ow-iw)/2:(oh-ih)/2:color=black@0';
      case FitMode.smartCrop:
        return 'fps=$fps,format=rgba,'
            "crop='min(iw,ih)':'min(iw,ih)',scale=$_dim:$_dim";
    }
  }

  /// Counts ANMF chunks by walking the RIFF container.
  ///
  /// Parsed rather than byte-searched: compressed frame payloads can contain
  /// the bytes 'ANMF' by chance, which would inflate the count.
  int _countFrames(Uint8List b) {
    if (b.length < 12) return 0;
    if (String.fromCharCodes(b.sublist(0, 4)) != 'RIFF') return 0;
    if (String.fromCharCodes(b.sublist(8, 12)) != 'WEBP') return 0;

    final view = b.buffer.asByteData();
    var frames = 0;
    var offset = 12;
    while (offset + 8 <= b.length) {
      if (String.fromCharCodes(b.sublist(offset, offset + 4)) == 'ANMF') {
        frames++;
      }
      final size = view.getUint32(offset + 4, Endian.little);
      offset += 8 + size + (size.isOdd ? 1 : 0); // payloads are even-padded
    }
    return frames;
  }

  String _extensionFor(MediaHandle input) {
    switch (input.kind) {
      case MediaKind.gif:
        return '.gif';
      case MediaKind.video:
        return '.mp4';
      case MediaKind.image:
        return _sniffExtension(input.bytes);
    }
  }

  /// ffmpeg probes by content, but a matching extension avoids any ambiguity.
  String _sniffExtension(Uint8List b) {
    if (b.length >= 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      return '.webp';
    }
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50) return '.png';
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8) return '.jpg';
    return '.bin';
  }
}
