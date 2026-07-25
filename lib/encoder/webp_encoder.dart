import 'dart:typed_data';

/// The WebP bytes produced for a bitmap, plus the quality that fit the budget.
class WebpEncodeResult {
  const WebpEncodeResult({required this.bytes, required this.quality});

  final Uint8List bytes;
  final int quality;
}

/// Compresses an RGBA bitmap to WebP under a byte ceiling.
///
/// This is the **one** part of encoding that needs native code — the Dart
/// `image` package cannot write WebP, so the real implementation wraps libwebp
/// (via `ffmpeg_kit`, added with Task 6) and only runs on a device. It lives
/// behind this interface so the geometry in [StaticEncoder] is testable in pure
/// Dart against a fake, and the native encoder is swapped in (and device-tested)
/// without touching any consumer.
abstract class WebpEncoder {
  /// Encodes a [width]×[height] RGBA bitmap to WebP, stepping quality down until
  /// the result is ≤ [maxBytes]. Returns the bytes and the quality landed on.
  Future<WebpEncodeResult> encode(
    Uint8List rgba, {
    required int width,
    required int height,
    required int maxBytes,
  });
}
