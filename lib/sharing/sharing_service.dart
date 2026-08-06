import 'package:share_plus/share_plus.dart';

import '../library/library_store.dart';
import '../models/sticker_record.dart';

/// How a share ended.
///
/// Our own enum rather than `share_plus`'s, so the domain and its tests stay
/// free of the package's types and a fake backend is trivial to write.
enum ShareOutcome {
  /// The user picked a target and the share went through.
  shared,

  /// The user backed out of the share sheet.
  dismissed,

  /// The sheet was shown but the platform cannot report what the user did.
  unknown,

  /// The share could not be attempted at all.
  failed,
}

/// The platform side of sharing. Injected so the usage-counting rules are
/// testable without a device.
abstract class ShareBackend {
  Future<ShareOutcome> shareFile(String path, {String? mimeType});
}

/// Sends a single sticker through the OS share sheet, and records the send.
///
/// Note this is **not** how stickers get into WhatsApp's sticker tray — that is
/// the `ContentProvider` + intent path in `Exporter` (Task 11). This shares the
/// sticker as a *file*, which is what the OS share sheet can do.
///
/// **There is deliberately no `sharePack`.** The spec listed pack-sharing as a
/// v1 feature "reusing the Exporter", but that cannot work: WhatsApp identifies
/// a pack by the pair (ContentProvider **authority**, identifier), and that
/// authority only exists on *this* device. A friend's phone has no app
/// publishing it, so there is nothing for their WhatsApp to load.
///
/// The constraint is deeper than transport. Any cross-device pack sharing needs
/// the *receiving* device to construct the pack locally — and constructing a
/// pack out of received stickers **is** the import feature, which is scoped to
/// v2. Sending the WebP files instead would deliver images the recipient cannot
/// turn back into stickers, so it would be pack-sharing in name only.
///
/// Revisit after v1, once import exists; see `CLAUDE.md`.
class SharingService {
  const SharingService(this._backend, this._store);

  final ShareBackend _backend;
  final LibraryStore _store;

  /// Shares [sticker], incrementing its usage count if it actually went out.
  ///
  /// Never throws: sharing is a leaf action, and a failure means "it did not
  /// send", not "something is broken". The outcome is returned so the UI can
  /// respond without needing a try/catch.
  Future<ShareOutcome> shareSticker(StickerRecord sticker) async {
    final ShareOutcome outcome;
    try {
      outcome = await _backend.shareFile(
        sticker.filePath,
        mimeType: 'image/webp',
      );
    } catch (_) {
      return ShareOutcome.failed;
    }

    if (_countsAsSent(outcome)) {
      await _store.incrementUsage(sticker.id);
    }
    return outcome;
  }

  /// Whether an outcome should bump the usage count.
  ///
  /// `usageCount` is **not a statistic** — WhatsApp exposes no usage data, so
  /// this exists purely as a ranking signal for search. Two failure modes, and
  /// they are not symmetric:
  ///
  /// - Counting a **dismissed** share inflates the signal with sends that never
  ///   happened, quietly skewing search results. So it is not counted.
  /// - Refusing to count an **undetermined** outcome risks the opposite: if the
  ///   platform reports `unknown` routinely, usage never moves, the signal is
  ///   dead, and the field does nothing. That is worse — mild over-counting
  ///   still preserves the useful ordering (a sticker you opened the sheet for
  ///   beats one you never touched), whereas a dead signal removes the
  ///   tiebreaker altogether.
  bool _countsAsSent(ShareOutcome outcome) =>
      outcome == ShareOutcome.shared || outcome == ShareOutcome.unknown;
}

/// [ShareBackend] over `share_plus`.
class PlatformShareBackend implements ShareBackend {
  const PlatformShareBackend();

  @override
  Future<ShareOutcome> shareFile(String path, {String? mimeType}) async {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(path, mimeType: mimeType)]),
    );

    switch (result.status) {
      case ShareResultStatus.success:
        return ShareOutcome.shared;
      case ShareResultStatus.dismissed:
        return ShareOutcome.dismissed;
      case ShareResultStatus.unavailable:
        return ShareOutcome.unknown;
    }
  }
}
