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

  /// What WhatsApp's **documentation** requires. Kept accurate; see
  /// [enforcedMinStickersPerPack] for what we actually gate on.
  static const int minStickersPerPack = 3;

  /// What **we** refuse to export below. Deliberately lower than
  /// [minStickersPerPack].
  ///
  /// **Set to 1 on 2026-08-08, a considered divergence from the documented spec.**
  /// Device-verified 2026-08-01 that 1- and 2-sticker packs install and are usable
  /// on `com.whatsapp` v2.26.27.85 — the documented minimum is not enforced at
  /// runtime on that build. The common case is wanting *one* sticker in WhatsApp
  /// without having to invent two more, and forcing a pack of three to satisfy a
  /// limit WhatsApp is not applying is friction we are choosing not to impose.
  ///
  /// **The risk, accepted knowingly:** WhatsApp re-validates on ingest with
  /// closed-source rules that demonstrably vary between builds (issue #998 —
  /// identical packs flipping pass/fail), so a build that enforces the minimum
  /// would refuse these packs. That refusal is *visible and retryable*:
  /// `WhatsAppRejectedException` surfaces their message verbatim before anything
  /// installs, and the user can add stickers and re-export. What is genuinely
  /// unknown is how an already-installed 1-sticker pack fares across a WhatsApp
  /// update; post-import sync is being removed, which weakly suggests installed
  /// packs are left alone.
  ///
  /// **To revert, set this to [minStickersPerPack].** Every gate and every piece
  /// of UI copy reads from here, so that is the whole change. Revert if real use
  /// starts producing rejections.
  static const int enforcedMinStickersPerPack = 1;

  static const int maxStickersPerPack = 30;

  /// WhatsApp accepts at most this many emoji per sticker.
  ///
  /// They feed the sticker tray's own emoji search — the one signal that helps a
  /// user find a sticker **inside WhatsApp**, where everything else we index
  /// cannot reach.
  static const int maxEmojisPerSticker = 3;

  /// Packs the app itself exposes to WhatsApp.
  static const int minPacks = 1;
  static const int maxPacks = 10;

  /// Total animation length ceiling, in milliseconds.
  static const int maxAnimationMs = 10000;

  /// Per-frame floor, in milliseconds. Faster frames are rejected.
  static const int minFrameMs = 8;
}
