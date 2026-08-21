import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../models/pack_record.dart';
import '../models/sticker_record.dart';
import '../packs/pack_service.dart';
import 'export_pack_action.dart';

/// The longest pack name WhatsApp accepts.
///
/// Names are truncated rather than refused: a name too long to send is still a
/// name the user meant, and losing the tail beats losing the sticker.
const _maxPackNameChars = 128;

/// Sends a single sticker to WhatsApp by wrapping it in a pack of its own.
///
/// **This exists because WhatsApp's third-party API has no per-sticker display
/// name.** The only per-sticker text field is `accessibility_text`, which screen
/// readers announce and nothing renders, so every sticker in the tray shows its
/// *pack's* name. Naming a sticker therefore did nothing visible in WhatsApp at
/// all. A pack of one, named after the sticker, is the only way to make that
/// name appear — the pack name is the string WhatsApp actually draws.
///
/// The pack is a wrapper, not a thing the user asked for, so it is **discarded
/// once WhatsApp has it**. That keeps the Packs tab free of throwaway entries
/// and, more importantly, frees the slot: an app may publish at most ten packs,
/// and without cleanup this feature would stop working after ten stickers.
///
/// The cost is accepted deliberately: WhatsApp's tray gains one section per
/// sticker. Nothing can avoid that while pack name is the only visible name,
/// and other sticker apps behave the same way.
///
/// Returns true when the sticker reached WhatsApp.
Future<bool> sendStickerToWhatsApp({
  required BuildContext context,
  required AppDependencies dependencies,
  required StickerRecord sticker,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  final pack = await _createWrapperPack(
    context: context,
    dependencies: dependencies,
    sticker: sticker,
  );
  if (pack == null || !context.mounted) return false;

  // Reuses the ordinary export path, so this inherits the confirmation dialog
  // and all three distinct failure messages rather than re-deriving them.
  final sent = await confirmAndExportPack(
    context: context,
    dependencies: dependencies,
    pack: pack,
  );

  if (!sent) {
    // Cancelled, rejected or invalid. Discard the wrapper anyway: it was never
    // something the user asked to keep, and leaving it behind would put a pack
    // in their library that they did not make and cannot explain.
    await dependencies.packExport.discard(pack);
    return false;
  }

  // Only now, and only on a confirmed success. WhatsApp reads the sticker bytes
  // through our ContentProvider, so discarding any earlier would pull the files
  // out from under an import that has not finished.
  await dependencies.packExport.discard(pack);

  messenger.showSnackBar(
    SnackBar(content: Text('Sent "${pack.name}" to WhatsApp')),
  );
  return true;
}

/// Creates the one-sticker pack, or null if it could not be created.
Future<PackRecord?> _createWrapperPack({
  required BuildContext context,
  required AppDependencies dependencies,
  required StickerRecord sticker,
}) async {
  try {
    return await dependencies.packs.createPack(
      name: packNameFor(sticker),
      first: sticker,
    );
  } on PackLimitException catch (e) {
    // Should be close to unreachable now that wrappers are discarded, but a
    // library full of real packs can still hit it, and silently doing nothing
    // would be the worst possible response.
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return null;
  }
}

/// What to call the pack that carries [sticker].
///
/// This string is the only text WhatsApp will show for the sticker, so the
/// fallbacks matter. The user's own name first; then auto-tags, which are
/// generic but do describe the picture; then a neutral last resort, because a
/// pack must have a name and an empty one fails WhatsApp's validation.
@visibleForTesting
String packNameFor(StickerRecord sticker) {
  final name = sticker.manualName?.trim();
  if (name != null && name.isNotEmpty) return _capped(name);

  final tags = sticker.autoTags
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  if (tags.isNotEmpty) return _capped(tags.join(', '));

  return 'Sticker';
}

String _capped(String s) =>
    s.length <= _maxPackNameChars ? s : s.substring(0, _maxPackNameChars);
