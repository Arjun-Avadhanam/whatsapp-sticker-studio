import 'package:flutter/services.dart';

import 'encoder.dart';
import 'webp_encoder.dart';

/// The real [WebpEncoder]: hands the bitmap to Android's built-in WebP encoder
/// over a [MethodChannel], which walks a quality ladder until the bytes fit.
///
/// Only usable on a device — in a plain `flutter test` there is no platform side
/// to answer, so [StaticEncoder] tests inject a fake instead. The channel
/// contract itself is covered in `test/encoder/native_webp_encoder_test.dart`.
class NativeWebpEncoder implements WebpEncoder {
  /// [channel] is injectable so tests can supply a mock; production uses the
  /// const channel that [WebpEncoderChannel] on the Kotlin side listens on.
  NativeWebpEncoder({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must stay in sync with `WebpEncoderChannel.CHANNEL` (Kotlin).
  static const String channelName = 'com.arjun.whatsapp_sticker_studio/webp';

  final MethodChannel _channel;

  @override
  Future<WebpEncodeResult> encode(
    Uint8List rgba, {
    required int width,
    required int height,
    required int maxBytes,
  }) async {
    final Map<Object?, Object?>? reply;
    try {
      reply = await _channel.invokeMethod<Map<Object?, Object?>>(
        'encodeStatic',
        <String, Object?>{
          'rgba': rgba,
          'width': width,
          'height': height,
          'maxBytes': maxBytes,
        },
      );
    } on PlatformException catch (e) {
      // Includes the "cannot fit maxBytes" case: the platform refuses to return
      // an oversize sticker, and that must reach the Maker as an encoder error.
      throw EncoderException(e.message ?? 'native WebP encode failed');
    } on MissingPluginException {
      throw const EncoderException(
        'the native WebP encoder is unavailable on this platform',
      );
    }

    final bytes = reply?['bytes'];
    final quality = reply?['quality'];
    if (bytes is! Uint8List || quality is! int) {
      throw const EncoderException(
        'the native WebP encoder returned a malformed result',
      );
    }

    return WebpEncodeResult(bytes: bytes, quality: quality);
  }
}
