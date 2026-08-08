import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/media.dart';
import '../core/whatsapp_spec.dart';
import '../encoder/encoder.dart';
import '../encoder/tray_icon_encoder.dart';
import '../library/library_store.dart';
import '../models/pack_record.dart';
import '../models/sticker_record.dart';

/// A pack cannot take this sticker, or the library cannot take another pack.
///
/// Distinct from [EncoderException]: nothing went wrong, a documented WhatsApp
/// ceiling was reached. The message says which one and what the user can do.
class PackLimitException implements Exception {
  const PackLimitException(this.message);
  final String message;

  @override
  String toString() => 'PackLimitException: $message';
}

/// Builds and grows sticker packs.
///
/// Holds the one rule the user must never meet as an error: **a pack is
/// animated if any sticker in it is animated, and statics are promoted to get
/// there.** WhatsApp packs are homogeneous — all-static or all-animated — and
/// `CLAUDE.md` records why explaining that constraint does not work (across
/// ~9,700 scraped reviews of competing apps, zero users diagnosed it
/// correctly; they blamed paywalls and bugs). So it is dissolved rather than
/// surfaced.
class PackService {
  // Fields are public only because Dart forbids named parameters starting with
  // an underscore, so private fields here would mean four positional arguments
  // and an unreadable call site.
  const PackService({
    required this.store,
    required this.trayIcons,
    required this.promoter,
    required this.directory,
  });

  final LibraryStore store;
  final TrayIconEncoder trayIcons;

  /// Interface, not [AnimatedEncoder], so pack logic does not drag in ffmpeg —
  /// packs are otherwise pure bookkeeping and stay testable off-device.
  final StaticPromoter promoter;

  /// Where tray icons are written.
  final Directory directory;

  /// Creates a pack around its first sticker.
  ///
  /// The first sticker is required rather than optional because a pack is not
  /// valid without a tray icon, and the tray icon is generated *from* a
  /// sticker. An empty pack could only exist in a state WhatsApp would reject.
  Future<PackRecord> createPack({
    required String name,
    required StickerRecord first,
  }) async {
    final existing = await store.allPacks();
    if (existing.length >= WhatsAppSpec.maxPacks) {
      throw PackLimitException(
        'You already have ${WhatsAppSpec.maxPacks} packs, which is all '
        'WhatsApp allows. Add this sticker to one of them instead.',
      );
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final pack = PackRecord(
      id: id,
      name: name,
      trayIconPath: await _writeTrayIcon(id, first),
      isAnimated: first.kind == StickerKind.animated,
      stickerIds: [first.id],
      createdAt: DateTime.now(),
    );

    await store.savePack(pack);
    await _link(first, pack.id);

    // Re-read rather than returning the in-memory copy. drift's dateTime()
    // column stores a unix timestamp in SECONDS, so DateTime.now()'s sub-second
    // part does not survive the round trip and the two records would compare
    // unequal. Returning what was actually persisted makes "the pack you got
    // back is the pack on disk" true by construction, instead of a rule every
    // future caller has to remember.
    return await store.getPack(pack.id) ?? pack;
  }

  /// Adds [sticker] to [pack], promoting whatever has to be promoted.
  ///
  /// Returns the updated pack. Re-adding a sticker already in the pack is a
  /// no-op rather than an error — the user's intent is already satisfied.
  Future<PackRecord> addSticker(PackRecord pack, StickerRecord sticker) async {
    if (pack.stickerIds.contains(sticker.id)) return pack;

    if (pack.stickerIds.length >= WhatsAppSpec.maxStickersPerPack) {
      throw PackLimitException(
        '"${pack.name}" already has ${WhatsAppSpec.maxStickersPerPack} '
        'stickers, which is WhatsApp\'s limit. Start another pack for this one.',
      );
    }

    final incomingIsAnimated = sticker.kind == StickerKind.animated;
    var updated = pack.copyWith(
      stickerIds: [...pack.stickerIds, sticker.id],
      // Any animated member makes the whole pack animated. Never the reverse:
      // there is no un-animating, and the flag may be sticky once installed.
      isAnimated: pack.isAnimated || incomingIsAnimated,
    );

    if (updated.isAnimated) {
      if (incomingIsAnimated && !pack.isAnimated) {
        // The pack has just flipped, so every sticker already in it is static
        // and must be brought up. Costly — one promotion per member — but the
        // alternative is telling the user their pack is the wrong kind, which
        // is the error this whole design exists to avoid.
        await _promoteAll(pack.stickerIds);
      } else if (!incomingIsAnimated) {
        await _promote(sticker);
      }
    }

    await store.savePack(updated);
    await _link(sticker, updated.id);
    return updated;
  }

  Future<void> _promoteAll(List<String> ids) async {
    for (final id in ids) {
      final s = await store.getSticker(id);
      if (s != null && s.kind != StickerKind.animated) await _promote(s);
    }
  }

  /// Re-encodes a still as a ≥2-frame animated WebP, **overwriting in place**.
  ///
  /// In place because other records already point at this path — the record's
  /// own `thumbnailPath`, anything staged for export, a pending share. Writing
  /// a new file would leave those dangling and orphan the old one.
  ///
  /// A single-frame "animated" WebP does not work: WhatsApp's validator tests
  /// `getFrameCount() <= 1`, so one frame is rejected exactly like a static
  /// file. Two frames is the floor. Verified on device 2026-08-01.
  Future<void> _promote(StickerRecord sticker) async {
    final file = File(sticker.filePath);
    final promoted = await promoter.promoteStatic(await file.readAsBytes());
    await file.writeAsBytes(promoted.webpBytes);

    await store.saveSticker(
      sticker.copyWith(
        kind: StickerKind.animated,
        // Promotion moves this sticker from the 100 KB budget to the 500 KB
        // one, so the recorded size must be the new file's or the validator
        // will judge it against the wrong ceiling.
        sizeBytes: promoted.sizeBytes,
      ),
    );
  }

  Future<String> _writeTrayIcon(String packId, StickerRecord from) async {
    final bytes = await trayIcons.encode(
      await File(from.filePath).readAsBytes(),
    );
    final file = File(p.join(directory.path, 'tray_$packId.webp'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Re-reads before linking: [_promote] may have just rewritten this record,
  /// and writing the caller's stale copy back would undo it.
  Future<void> _link(StickerRecord sticker, String packId) async {
    final current = await store.getSticker(sticker.id) ?? sticker;
    await store.saveSticker(current.copyWith(packId: packId));
  }
}
