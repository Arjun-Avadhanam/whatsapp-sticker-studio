import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../core/media.dart';
import '../core/whatsapp_spec.dart';
import 'encoder.dart';
import 'webp_encoder.dart';

/// Encodes a still image into a compliant 512×512 static WebP sticker.
///
/// Splits cleanly in two: the **fit geometry** (decode → 512² bitmap) is pure
/// Dart and unit-tested here; the **WebP byte-encode + size budget** is
/// delegated to an injected [WebpEncoder] (native libwebp on a device, a fake in
/// tests). This class never touches WebP encoding directly.
class StaticEncoder implements Encoder {
  StaticEncoder(this._webp);

  final WebpEncoder _webp;

  static const int _dim = WhatsAppSpec.dimension;

  @override
  Future<EncodedSticker> encode(MediaHandle input, EncodeParams params) async {
    // decodeImage returns null for an unrecognised format, but *throws* (e.g.
    // RangeError) on bytes too short to even read a header — treat both as a
    // clean decode failure.
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(input.bytes);
    } catch (_) {
      throw const EncoderException('could not decode the image');
    }
    if (decoded == null) {
      throw const EncoderException('could not decode the image');
    }

    final fitted = _fit(decoded, params.fitMode);
    final rgba = fitted.getBytes(order: img.ChannelOrder.rgba);

    final result = await _webp.encode(
      rgba,
      width: _dim,
      height: _dim,
      maxBytes: WhatsAppSpec.maxStaticBytes,
    );

    return EncodedSticker(
      webpBytes: result.bytes,
      kind: StickerKind.staticImage,
      width: _dim,
      height: _dim,
      sizeBytes: result.bytes.length,
      report: QualityReport(
        fps: 0,
        frames: 1,
        quality: result.quality,
        sizeBytes: result.bytes.length,
      ),
    );
  }

  /// Returns a 512×512, 4-channel bitmap. The switch is exhaustive over
  /// [FitMode], so a new mode won't compile until it's handled here.
  img.Image _fit(img.Image src, FitMode mode) {
    // Guarantee an alpha channel so letterbox padding can be transparent.
    final rgba = src.numChannels == 4 ? src : src.convert(numChannels: 4);

    switch (mode) {
      case FitMode.pad:
      case FitMode.contain:
        return _letterbox(rgba);
      case FitMode.smartCrop:
        return _cropToSquare(rgba);
    }
  }

  /// Scale-to-fit preserving aspect ratio, centred on a transparent 512² canvas.
  /// Loses nothing; leaves transparent bars on the short axis.
  img.Image _letterbox(img.Image src) {
    final scale = math.min(_dim / src.width, _dim / src.height);
    final resized = img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
    );
    // A new 4-channel image is zero-filled == fully transparent.
    final canvas = img.Image(width: _dim, height: _dim, numChannels: 4);
    img.compositeImage(canvas, resized, center: true);
    return canvas;
  }

  /// Centre-crop to a square, then resize to fill the frame. Subject-aware
  /// cropping is deferred to v1.1.
  img.Image _cropToSquare(img.Image src) {
    final side = math.min(src.width, src.height);
    final cropped = img.copyCrop(
      src,
      x: (src.width - side) ~/ 2,
      y: (src.height - side) ~/ 2,
      width: side,
      height: side,
    );
    return img.copyResize(cropped, width: _dim, height: _dim);
  }
}
