import 'dart:io';

import 'package:path/path.dart' as p;

import '../library/library_store.dart';
import '../models/pack_record.dart';
import '../models/sticker_record.dart';
import 'exporter.dart';
import 'pack_stager.dart';

/// Puts a finished pack into WhatsApp: gather → stage → fire the intent.
///
/// The three steps are ordered, not independent, and getting the order wrong is
/// silent — hence one place that owns it rather than a screen wiring it by hand.
/// Task 14 needs the same sequence from the Library.
class PackExportService {
  const PackExportService({
    required this.store,
    required this.stager,
    required this.exporter,
  });

  final LibraryStore store;
  final PackStager stager;
  final Exporter exporter;

  /// Stages the pack's assets and asks WhatsApp to add it.
  ///
  /// Throws exactly what [Exporter] throws — [PackNotValidException],
  /// [WhatsAppRejectedException] or [ExportCancelledException] — deliberately
  /// unflattened. The three mean genuinely different things (our validation
  /// caught it / WhatsApp's stricter closed-source validation caught it / the
  /// user declined), and only the caller can phrase each one usefully.
  Future<void> addToWhatsApp(PackRecord pack) async {
    final stickers = await _stickersOf(pack);

    // Staging MUST precede the intent: WhatsApp reads through our
    // ContentProvider the moment it receives one, so firing first races an
    // unwritten directory. Re-staging also bumps `image_data_version`, the only
    // refresh mechanism WhatsApp offers.
    await stager.stage(pack, stickers);

    await exporter.addPackToWhatsApp(pack, stickers);
  }

  /// Discards a pack we only created in order to carry one sticker across.
  ///
  /// **The sticker survives.** `deletePack` clears the membership back-reference
  /// and leaves the record and its file alone, which is what makes a throwaway
  /// pack safe.
  ///
  /// **WhatsApp keeps its imported copy**, confirmed in real use: stickers added
  /// this way persist even after the app is uninstalled and its data wiped. A
  /// pack is a one-shot import, so removing ours does not reach into WhatsApp.
  ///
  /// Both halves are required. Unstaging alone leaves an orphan record; deleting
  /// the record alone leaves the directory, and the provider enumerates packs
  /// from the filesystem, so WhatsApp would still be offered a pack that counts
  /// against the ten an app may publish.
  ///
  /// Call this only after an export has genuinely succeeded. WhatsApp reads the
  /// bytes through the provider, so discarding early races an unfinished import.
  Future<void> discard(PackRecord pack) async {
    await stager.unstage(pack.id);
    await store.deletePack(pack.id);
  }

  /// Whether this pack has been staged before — i.e. the user is re-adding it.
  ///
  /// Drives the one caveat worth saying out loud: bumping `image_data_version`
  /// does not reliably refresh an installed pack (issue #612, acknowledged by a
  /// WhatsApp engineer and closed without a fix), so on a re-add the user has to
  /// be told to open WhatsApp's sticker manager. Staying silent and hoping the
  /// poll works reproduces exactly the frustration that drives people to
  /// recreate packs from scratch.
  Future<bool> hasBeenStaged(PackRecord pack) async {
    final dir = await stager.packDir(pack.id);
    return File(p.join(dir.path, PackStager.manifestName)).existsSync();
  }

  /// Resolves the pack's ids to records, **preserving pack order**.
  ///
  /// Order is meaningful — it is the order WhatsApp renders the tray — so this
  /// walks [PackRecord.stickerIds] rather than querying and taking whatever
  /// order comes back. An id with no record is skipped: a pack referencing a
  /// deleted sticker should export the rest, not fail wholesale, and the
  /// validator still catches the pack if that drops it below the floor.
  Future<List<StickerRecord>> _stickersOf(PackRecord pack) async {
    final records = <StickerRecord>[];
    for (final id in pack.stickerIds) {
      final sticker = await store.getSticker(id);
      if (sticker != null) records.add(sticker);
    }
    return records;
  }
}
