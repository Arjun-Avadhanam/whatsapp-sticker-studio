import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/whatsapp_spec.dart';
import 'encoder.dart';
import 'webp_encoder.dart';

/// Produces a pack's tray icon: **96×96 WebP, ≤ 50 KB**.
///
/// Separate from [StaticEncoder] rather than a mode on it: the tray icon is a
/// property of the *pack*, not a sticker, and it has its own dimension and byte
/// ceiling. Every pack needs exactly one, so a pack cannot be exported without
/// this even though no sticker uses it.
class TrayIconEncoder {
  const TrayIconEncoder(this._webp);

  final WebpEncoder _webp;

  static const int _dim = WhatsAppSpec.trayDimension;

  /// Encodes any still image (typically the pack's first sticker) as a tray icon.
  Future<Uint8List> encode(Uint8List imageBytes) async {
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(imageBytes);
    } catch (_) {
      throw const EncoderException('could not decode the tray image');
    }
    if (decoded == null) {
      throw const EncoderException('could not decode the tray image');
    }

    final rgba = _fitToSquare(decoded).getBytes(order: img.ChannelOrder.rgba);

    final result = await _webp.encode(
      rgba,
      width: _dim,
      height: _dim,
      maxBytes: WhatsAppSpec.maxTrayBytes,
    );
    return result.bytes;
  }

  /// Scale-to-fit on a transparent 96² canvas — same letterbox rule as
  /// [FitMode.pad], so a tray icon never stretches or crops its sticker.
  img.Image _fitToSquare(img.Image src) {
    final rgba = src.numChannels == 4 ? src : src.convert(numChannels: 4);
    final scale = math.min(_dim / rgba.width, _dim / rgba.height);
    final resized = img.copyResize(
      rgba,
      width: math.max(1, (rgba.width * scale).round()),
      height: math.max(1, (rgba.height * scale).round()),
    );
    final canvas = img.Image(width: _dim, height: _dim, numChannels: 4);
    img.compositeImage(canvas, resized, center: true);
    return canvas;
  }
}
