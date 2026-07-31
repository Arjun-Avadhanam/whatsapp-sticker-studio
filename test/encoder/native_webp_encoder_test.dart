import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/native_webp_encoder.dart';

/// These tests verify the **channel contract** — the arguments Dart sends and
/// how it reads the reply — without a device. Whether Android actually produces
/// a valid WebP is a separate, device-only check (Task 5b integration test):
/// a mock handler here would happily agree with a wrong contract, so this file
/// proves the wiring, not the encoding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(NativeWebpEncoder.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Records the last call and replies with [reply], or throws [error].
  MethodCall? lastCall;
  void mockNative({Object? reply, PlatformException? error}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      lastCall = call;
      if (error != null) throw error;
      return reply;
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    lastCall = null;
  });

  final rgba = Uint8List.fromList(List<int>.filled(16, 7));

  test('forwards the bitmap and the byte ceiling to the platform', () async {
    mockNative(
      reply: <Object?, Object?>{
        'bytes': Uint8List.fromList([1, 2, 3]),
        'quality': 90,
      },
    );

    await NativeWebpEncoder().encode(
      rgba,
      width: 2,
      height: 2,
      maxBytes: 102400,
    );

    expect(lastCall!.method, 'encodeStatic');
    final args = lastCall!.arguments as Map<Object?, Object?>;
    expect(args['rgba'], rgba);
    expect(args['width'], 2);
    expect(args['height'], 2);
    expect(args['maxBytes'], 102400);
  });

  test('returns the bytes and the quality the platform landed on', () async {
    mockNative(
      reply: <Object?, Object?>{
        'bytes': Uint8List.fromList([9, 9, 9, 9]),
        'quality': 70,
      },
    );

    final result = await NativeWebpEncoder().encode(
      rgba,
      width: 2,
      height: 2,
      maxBytes: 102400,
    );

    expect(result.bytes, [9, 9, 9, 9]);
    expect(result.quality, 70);
  });

  test(
    'a platform failure surfaces as EncoderException, not PlatformException',
    () async {
      // The Maker catches EncoderException to show a friendly message; letting a
      // raw PlatformException escape would bypass that handling entirely.
      mockNative(
        error: PlatformException(
          code: 'encode_failed',
          message: 'cannot fit 102400 bytes',
        ),
      );

      expect(
        () => NativeWebpEncoder().encode(
          rgba,
          width: 2,
          height: 2,
          maxBytes: 102400,
        ),
        throwsA(
          isA<EncoderException>().having(
            (e) => e.message,
            'message',
            contains('cannot fit'),
          ),
        ),
      );
    },
  );

  test('a malformed reply is rejected rather than silently mis-read', () async {
    mockNative(reply: <Object?, Object?>{'quality': 80}); // no bytes

    expect(
      () => NativeWebpEncoder().encode(
        rgba,
        width: 2,
        height: 2,
        maxBytes: 102400,
      ),
      throwsA(isA<EncoderException>()),
    );
  });
}
