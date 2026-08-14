import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:path/path.dart' as p;

import 'encoder.dart';

/// [ImageTranscoder] over the ffmpeg we already ship.
///
/// **Device-verified 2026-08-14**: this build decodes both HEIC and AVIF — real
/// libheif-generated fixtures came back as 640×480 PNGs. That was the open
/// question behind the whole fallback, and the alternative (Android's
/// `BitmapFactory`) is not needed: ffmpeg carries no API-28 floor, so this works
/// everywhere the app runs.
///
/// Costs a process spawn and two temp files, which is why it runs **only after**
/// the pure-Dart decode has already failed — the overwhelming majority of images
/// never reach it.
class FfmpegImageTranscoder implements ImageTranscoder {
  const FfmpegImageTranscoder();

  @override
  Future<Uint8List?> toPng(Uint8List bytes) async {
    final work = await Directory.systemTemp.createTemp('transcode');
    try {
      // Deliberately no extension. ffmpeg probes the container from content, and
      // guessing a wrong extension is worse than giving it none — the whole
      // reason we are here is that we could not identify the format.
      final source = File(p.join(work.path, 'source'));
      await source.writeAsBytes(bytes);
      final out = File(p.join(work.path, 'out.png'));

      // -frames:v 1 because a HEIF file can legitimately hold several items
      // (thumbnails, tiles, depth maps, burst frames) and we want the primary
      // image, not a sequence.
      final session = await FFmpegKit.execute(
        '-y -i ${source.path} -frames:v 1 ${out.path}',
      );

      if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
      // A zero exit with nothing written would otherwise be read as success.
      if (!out.existsSync() || out.lengthSync() == 0) return null;

      return await out.readAsBytes();
    } catch (_) {
      // Best-effort by contract: a failure here means the original decode error
      // stands, which the caller already reports properly.
      return null;
    } finally {
      if (work.existsSync()) await work.delete(recursive: true);
    }
  }
}
