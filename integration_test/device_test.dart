import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'suites/animated_encoder_suite.dart';
import 'suites/export_suite.dart';
import 'suites/ffmpeg_webp_probe_suite.dart';
import 'suites/native_webp_encoder_suite.dart';

/// The **single** entry point for every on-device test.
///
/// Deliberately the only `*_test.dart` file in `integration_test/`. Flutter
/// reruns `assembleDebug` **and reinstalls the APK for every test file**, and
/// it does not amortize that across a directory run — measured 2026-07-29, a
/// 13-test run across three files took ~17 minutes of which only ~2 minutes was
/// actual testing. Keeping the suites as plain libraries called from here makes
/// a full run cost one build and one install instead of N.
///
/// Add new areas as `suites/<area>_suite.dart` exposing a single function, then
/// register it below — never as another `*_test.dart` file.
///
/// Run with:
///
///     adb forward --remove-all   # stale forwards hang the handshake; see CLAUDE.md
///     flutter test integration_test/device_test.dart -d <device-id>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('ffmpeg/libwebp probe', ffmpegWebpProbeTests);
  group('static encoder (native)', nativeWebpEncoderTests);
  group('animated encoder', animatedEncoderTests);
  group('export staging', exportTests);
}
