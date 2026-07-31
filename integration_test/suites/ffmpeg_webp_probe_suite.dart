import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/packages.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Task 6 Step 1 — the gate before any `AnimatedEncoder` code is written.
///
/// `ffmpeg_kit_flutter_new_video`'s documentation claims libwebp is compiled in.
/// This proves it by running ffmpeg on the device. If it fails, the package
/// variant must change *first* — implementing against a build that cannot mux
/// animated WebP would be wasted work.
void ffmpegWebpProbeTests() {
  late Directory work;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('webp_probe');
  });

  tearDown(() async {
    if (work.existsSync()) await work.delete(recursive: true);
  });

  /// Walks the RIFF chunk list and returns the FourCCs in order.
  ///
  /// Deliberately parses the container rather than searching the raw bytes for
  /// 'ANMF' — compressed frame payloads can contain those four bytes by chance,
  /// which would make a still image look animated.
  List<String> webpChunks(Uint8List b) {
    expect(
      String.fromCharCodes(b.sublist(0, 4)),
      'RIFF',
      reason: 'not a RIFF container',
    );
    expect(
      String.fromCharCodes(b.sublist(8, 12)),
      'WEBP',
      reason: 'not a WebP file',
    );

    final chunks = <String>[];
    var offset = 12; // first chunk starts after 'RIFF' + size + 'WEBP'
    while (offset + 8 <= b.length) {
      chunks.add(String.fromCharCodes(b.sublist(offset, offset + 4)));
      final size = b.buffer.asByteData().getUint32(offset + 4, Endian.little);
      offset += 8 + size + (size.isOdd ? 1 : 0); // payloads are even-padded
    }
    return chunks;
  }

  testWidgets('the bundled ffmpeg reports libwebp among its libraries', (
    tester,
  ) async {
    final name = await Packages.getPackageName();
    final libraries = await Packages.getExternalLibraries();
    debugPrint('ffmpeg variant: $name');
    debugPrint('external libraries: $libraries');

    expect(
      libraries.any((l) => l.toLowerCase().contains('webp')),
      isTrue,
      reason: 'variant "$name" has no libwebp: $libraries',
    );
  });

  testWidgets('ffmpeg muxes a genuinely animated WebP', (tester) async {
    // A PNG sequence isolates the question to *muxing*. Decoding gif/mp4 is a
    // separate concern and uses FFmpeg's built-in decoders, not an external lib.
    const frames = 6;
    for (var i = 0; i < frames; i++) {
      final frame = img.Image(width: 512, height: 512, numChannels: 4);
      img.fill(frame, color: img.ColorRgba8(20 * i, 90, 200 - 20 * i, 255));
      File(
        '${work.path}/frame_${i.toString().padLeft(3, '0')}.png',
      ).writeAsBytesSync(img.encodePng(frame));
    }

    final out = '${work.path}/out.webp';
    final session = await FFmpegKit.execute(
      '-y -framerate 10 -i ${work.path}/frame_%03d.png '
      '-c:v libwebp -lossless 0 -q:v 75 -loop 0 -an $out',
    );

    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      debugPrint('ffmpeg failed: ${await session.getAllLogsAsString()}');
    }
    expect(ReturnCode.isSuccess(rc), isTrue, reason: 'ffmpeg command failed');

    final bytes = File(out).readAsBytesSync();
    expect(bytes.length, greaterThan(0));

    final chunks = webpChunks(bytes);
    debugPrint('output chunks: $chunks (${bytes.length} bytes)');

    // VP8X is the extended header that ANIM requires; ANIM holds the loop info;
    // each ANMF is one frame. WhatsApp's validator checks frameCount > 1, so
    // "has an ANIM chunk" is NOT sufficient — count the frames.
    expect(chunks, contains('VP8X'), reason: 'no extended header');
    expect(chunks, contains('ANIM'), reason: 'no animation chunk');
    expect(
      chunks.where((c) => c == 'ANMF').length,
      greaterThan(1),
      reason: 'output is not multi-frame, so WhatsApp would reject it',
    );
  });
}
