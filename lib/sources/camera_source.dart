import 'package:image_picker/image_picker.dart';

import '../core/media.dart';
import 'gallery_source.dart' show fileToHandle;
import 'source.dart';

/// Captures a fresh photo (or clip) with the device camera.
///
/// Goes through `ACTION_IMAGE_CAPTURE`, which the system camera app services.
/// Note we deliberately do **not** declare the `CAMERA` permission: Android only
/// *requires* it for this intent if the app declares it, so declaring it would
/// add a runtime permission prompt and a denial path for no benefit.
class CameraSource implements Source {
  CameraSource({
    ImagePicker? picker,
    this.captureVideo = false,
    this.maxDuration = defaultMaxDuration,
  }) : _picker = picker ?? ImagePicker();

  /// Caps camera recording. A sticker animation is ≤ 10 s, so letting someone
  /// record minutes only to trim almost all of it away wastes their time and
  /// the encoder's. Kept generously above the ceiling rather than at it, so
  /// there is room to record a moment and pick the best seconds out of it in
  /// the Maker — clamping to exactly 10 s would make the trim control useless.
  static const Duration defaultMaxDuration = Duration(seconds: 30);

  final ImagePicker _picker;

  /// Record a clip instead of taking a still.
  final bool captureVideo;

  final Duration maxDuration;

  @override
  Future<MediaHandle?> pick() async {
    final XFile? file = captureVideo
        ? await _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: maxDuration,
          )
        : await _picker.pickImage(source: ImageSource.camera);

    return fileToHandle(file);
  }
}
