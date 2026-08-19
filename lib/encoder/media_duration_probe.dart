import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';

/// How long a piece of source media runs.
///
/// Exists so the Maker's trim sliders can be bounded by the real clip instead of
/// a guess. Before this, Start ran to a hardcoded 60 seconds regardless, so on a
/// three-second clip most of the slider was dead travel and a start past the end
/// produced an encode with no frames at all.
///
/// An interface for the usual reason: the implementation shells out to ffprobe,
/// and the Maker has to stay drivable in a widget test with no device.
abstract class MediaDurationProbe {
  /// The duration of [bytes], or **null when it cannot be determined**.
  ///
  /// Null is an ordinary answer, not a failure. Callers fall back to their
  /// previous behaviour rather than removing a control that works.
  Future<Duration?> durationOf(Uint8List bytes);
}

/// Reads the duration with ffprobe, which already ships inside the ffmpeg
/// package used for encoding, so this costs no new dependency.
class FfprobeDurationProbe implements MediaDurationProbe {
  const FfprobeDurationProbe();

  @override
  Future<Duration?> durationOf(Uint8List bytes) async {
    // ffprobe reads a path, not a buffer. The file carries no extension on
    // purpose: ffprobe identifies by content, and guessing a wrong extension is
    // worse than saying nothing when the whole point is that we do not know
    // what the source is.
    final work = await Directory.systemTemp.createTemp('probe_duration');
    try {
      final file = File('${work.path}/source');
      await file.writeAsBytes(bytes);

      final session = await FFprobeKit.getMediaInformation(file.path);
      final raw = session.getMediaInformation()?.getDuration();
      if (raw == null) return null;

      // Reported as seconds in a string, for example "12.345000". A stream with
      // no known duration reports "N/A", which parses to null and is correct.
      final seconds = double.tryParse(raw);
      if (seconds == null || seconds <= 0 || !seconds.isFinite) return null;

      return Duration(milliseconds: (seconds * 1000).round());
    } catch (_) {
      // A probe is an optimisation, never a precondition. Anything unexpected
      // here must leave the user with the sliders they had before.
      return null;
    } finally {
      await work.delete(recursive: true);
    }
  }
}
