import 'dart:typed_data';

import '../core/media.dart';

/// Knobs for a single encode. [trim] is ignored by the static encoder and used
/// by the animated one (Task 6).
class EncodeParams {
  const EncodeParams({this.fitMode = FitMode.pad, this.trim});

  final FitMode fitMode;
  final Duration? trim;
}

/// What the encoder had to do to fit the ceilings — surfaced live in the Maker
/// so the user can see quality drop and choose to trim instead. [fps]/[frames]
/// describe animation; a static sticker is `fps: 0, frames: 1`.
class QualityReport {
  const QualityReport({
    required this.fps,
    required this.frames,
    required this.quality,
    required this.sizeBytes,
  });

  final int fps;
  final int frames;
  final int quality;
  final int sizeBytes;
}

/// A compliant, ready-to-store sticker: WebP bytes plus the facts the validator
/// and library care about.
class EncodedSticker {
  const EncodedSticker({
    required this.webpBytes,
    required this.kind,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.report,
  });

  final Uint8List webpBytes;
  final StickerKind kind;
  final int width;
  final int height;
  final int sizeBytes;
  final QualityReport report;
}

/// Thrown when input cannot be turned into a compliant sticker (undecodable
/// media, or a budget that can't be met — Task 6). Surfaced to the Maker UI.
class EncoderException implements Exception {
  const EncoderException(this.message);
  final String message;
  @override
  String toString() => 'EncoderException: $message';
}

/// The input decoded fine but could not be squeezed under its size ceiling.
///
/// Separate from a plain [EncoderException] because the *remedy* differs and
/// only the user can apply it: trimming the clip shortens the animation and is
/// usually far more effective than any further quality drop. The Maker should
/// say so rather than reporting a generic failure.
class EncoderBudgetException extends EncoderException {
  const EncoderBudgetException(super.message);
  @override
  String toString() => 'EncoderBudgetException: $message';
}

/// Turns raw media into a compliant 512×512 WebP sticker.
abstract class Encoder {
  Future<EncodedSticker> encode(MediaHandle input, EncodeParams params);
}
