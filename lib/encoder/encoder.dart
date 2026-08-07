import 'dart:typed_data';

import '../core/media.dart';

/// Knobs for a single encode. [trim] is ignored by the static encoder and used
/// by the animated one (Task 6).
class EncodeParams {
  const EncodeParams({
    this.fitMode = FitMode.pad,
    this.start = Duration.zero,
    this.trim,
  });

  final FitMode fitMode;

  /// Where in the clip to begin.
  ///
  /// Without this, trimming could only ever mean "keep the first N seconds",
  /// which is usually the wrong moment — someone turning a 30 s video into a
  /// reaction sticker almost never wants its opening. Ignored for stills.
  final Duration start;

  /// How much of the clip to keep from [start]. Ignored for stills.
  final Duration? trim;

  EncodeParams copyWith({FitMode? fitMode, Duration? start, Duration? trim}) =>
      EncodeParams(
        fitMode: fitMode ?? this.fitMode,
        start: start ?? this.start,
        trim: trim ?? this.trim,
      );

  // Value equality so the Maker can ask "are these the params the current
  // preview was encoded with?" — the check that stops a user saving a sticker
  // that does not match what they were shown.
  @override
  bool operator ==(Object other) =>
      other is EncodeParams &&
      other.fitMode == fitMode &&
      other.start == start &&
      other.trim == trim;

  @override
  int get hashCode => Object.hash(fitMode, start, trim);
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
