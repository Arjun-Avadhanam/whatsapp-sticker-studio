import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/pack_record.dart';
import '../models/sticker_record.dart';

/// Writes a pack into the layout `StickerContentProvider` serves from.
///
/// The provider is a dumb reader of `<filesDir>/sticker_packs/<identifier>/`:
/// a `pack.json` manifest plus the tray image and sticker WebPs, copied in.
/// Keeping the exported copy separate from the library is deliberate — WhatsApp
/// reads these files asynchronously while handling the intent, so they must not
/// move or change underneath it if the user edits the library meanwhile.
class PackStager {
  /// [baseDir] is injectable for tests; production resolves to the same
  /// `context.filesDir` the provider reads (`getApplicationSupportDirectory`).
  PackStager({this.baseDir});

  final Directory? baseDir;

  static const String manifestName = 'pack.json';
  static const String trayName = 'tray.webp';
  static const String _packsDirName = 'sticker_packs';

  Future<Directory> _root() async =>
      baseDir ?? await getApplicationSupportDirectory();

  Future<Directory> packDir(String identifier) async {
    final root = await _root();
    return Directory(p.join(root.path, _packsDirName, identifier));
  }

  /// Stages [pack] and returns the directory written.
  ///
  /// Re-staging an existing pack **bumps `image_data_version`**, which is the
  /// only mechanism WhatsApp offers for noticing changed art. Note it is not
  /// reliable — WhatsApp polls and the bump demonstrably does not always refresh
  /// the tray (issue #612, acknowledged and unfixed) — so the UI must also tell
  /// the user to open WhatsApp's sticker manager. Bump anyway: it costs nothing
  /// and sometimes works.
  Future<Directory> stage(
    PackRecord pack,
    List<StickerRecord> stickers, {
    String publisher = 'WhatsApp Sticker Studio',
  }) async {
    final dir = await packDir(pack.id);
    final version = await _nextDataVersion(dir);

    // Rebuild from scratch so a sticker removed from the pack cannot linger on
    // disk and keep being served.
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    await File(pack.trayIconPath).copy(p.join(dir.path, trayName));

    final entries = <Map<String, Object?>>[];
    for (final sticker in stickers) {
      final fileName = '${sticker.id}.webp';
      await File(sticker.filePath).copy(p.join(dir.path, fileName));
      entries.add(<String, Object?>{
        'image_file': fileName,
        // Emojis are optional to WhatsApp (max 3) and we have none to offer yet
        // — Task 13 can let the user pick them. They only affect searchability
        // inside WhatsApp's tray, not validity.
        'emojis': const <String>[],
        'accessibility_text': _describe(sticker),
      });
    }

    final manifest = <String, Object?>{
      'identifier': pack.id,
      'name': pack.name,
      'publisher': publisher,
      'tray_image_file': trayName,
      'image_data_version': '$version',
      'animated_sticker_pack': pack.isAnimated,
      'android_play_store_link': '',
      'ios_app_store_link': '',
      'publisher_email': '',
      'publisher_website': '',
      'privacy_policy_website': '',
      'license_agreement_website': '',
      'stickers': entries,
    };

    await File(
      p.join(dir.path, manifestName),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));

    return dir;
  }

  /// A screen-reader description for one sticker.
  ///
  /// `accessibility_text` is the **only** per-sticker text WhatsApp's
  /// third-party API accepts — there is no display-name field, which is why a
  /// pack's stickers all show the pack's name in the tray. So this is the one
  /// place a sticker can describe itself, and it was previously left empty for
  /// everything the Maker makes, since `manualName` is null there. A screen
  /// reader got nothing at all.
  ///
  /// Auto-tags are the fallback, and this is the one job they are good at:
  /// device testing 2026-08-08 showed ML Kit labels the scene rather than the
  /// subject ("sports, team, event"), which is weak for search but a perfectly
  /// reasonable image description. Text read by OCR comes first when present —
  /// "the one that says LOL" is the most identifying thing about a sticker.
  String _describe(StickerRecord sticker) {
    final name = sticker.manualName?.trim();
    if (name != null && name.isNotEmpty) return name;

    final tags = sticker.autoTags.where((t) => t.trim().isNotEmpty).toList();
    return tags.isEmpty ? '' : tags.join(', ');
  }

  /// Reads the previous `image_data_version` and returns the next one.
  Future<int> _nextDataVersion(Directory dir) async {
    final manifest = File(p.join(dir.path, manifestName));
    if (!manifest.existsSync()) return 1;
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      final current = int.tryParse('${(decoded as Map)['image_data_version']}');
      return (current ?? 0) + 1;
    } catch (_) {
      // A corrupt manifest is being replaced wholesale anyway; restarting the
      // version at 1 is worse than moving forward, so assume the first write.
      return 1;
    }
  }
}
