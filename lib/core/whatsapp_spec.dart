/// Hard limits imposed by WhatsApp's sticker format.
///
/// These are not tunable preferences — a pack violating any of them is rejected
/// by WhatsApp at add-time. Every encoder budget (Tasks 5/6) and the validator
/// (Task 4) reads its ceilings from here so there is exactly one place to change
/// if WhatsApp ever revises the spec.
class WhatsAppSpec {
  const WhatsAppSpec._();

  /// Sticker images must be exactly this many pixels on both axes.
  static const int dimension = 512;

  /// Tray (pack thumbnail) images must be exactly this many pixels on both axes.
  static const int trayDimension = 96;

  /// 100 KB.
  static const int maxStaticBytes = 102400;

  /// 500 KB.
  static const int maxAnimatedBytes = 512000;

  /// 50 KB.
  static const int maxTrayBytes = 51200;

  static const int minStickersPerPack = 3;
  static const int maxStickersPerPack = 30;

  /// Packs the app itself exposes to WhatsApp.
  static const int minPacks = 1;
  static const int maxPacks = 10;

  /// Total animation length ceiling, in milliseconds.
  static const int maxAnimationMs = 10000;

  /// Per-frame floor, in milliseconds. Faster frames are rejected.
  static const int minFrameMs = 8;
}
