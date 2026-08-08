import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../core/whatsapp_spec.dart';
import '../export/exporter.dart';
import '../models/pack_record.dart';

/// Confirms, then hands [pack] to WhatsApp, reporting whatever happened.
///
/// Returns true only if the pack actually reached WhatsApp.
///
/// **The confirmation is ours and it is not optional.** The spec assumed a pack
/// cannot be added silently because WhatsApp asks first — but on device
/// (`com.whatsapp` v2.26.27.85, 2026-08-01) four packs were added in ~11 s with
/// no per-pack dialog observed. If that holds, this is the only thing standing
/// between a tap and a pack appearing in the user's WhatsApp.
Future<bool> confirmAndExportPack({
  required BuildContext context,
  required AppDependencies dependencies,
  required PackRecord pack,
}) async {
  final again = await dependencies.packExport.hasBeenStaged(pack);
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _ConfirmDialog(pack: pack, again: again),
  );
  if (confirmed != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await dependencies.packExport.addToWhatsApp(pack);
  } on PackNotValidException catch (e) {
    // Our own validator, which names every problem specifically — the whole
    // reason it runs before the intent instead of letting WhatsApp answer.
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => _ProblemsDialog(problems: e.problems),
      );
    }
    return false;
  } on WhatsAppRejectedException catch (e) {
    // Their validation is closed-source and stricter than the published sample
    // (issue #606), so this string is the only diagnostic that exists. Show it
    // verbatim; paraphrasing would destroy the only clue.
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => _ProblemsDialog(
          title: 'WhatsApp would not add this pack',
          problems: [e.validationError],
        ),
      );
    }
    return false;
  } on ExportCancelledException {
    // Backing out is an ordinary choice, not a failure. Say nothing.
    return false;
  }

  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(
        again
            // Bumping image_data_version is the only refresh mechanism and it
            // demonstrably does not always work (issue #612, acknowledged and
            // closed unfixed). Saying nothing and hoping the poll fires is what
            // makes people recreate packs from scratch.
            ? 'Sent to WhatsApp. If you do not see the change, open WhatsApp\'s '
                  'sticker manager and re-add the pack.'
            : 'Added "${pack.name}" to WhatsApp.',
      ),
    ),
  );
  return true;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.pack, required this.again});

  final PackRecord pack;
  final bool again;

  @override
  Widget build(BuildContext context) {
    final count = pack.stickerIds.length;

    return AlertDialog(
      key: const Key('export-confirm'),
      title: Text(again ? 'Update in WhatsApp?' : 'Add to WhatsApp?'),
      content: Text(
        again
            ? '"${pack.name}" is already in WhatsApp. Sending it again updates '
                  'the $count stickers it contains.'
            : '"${pack.name}" and its $count stickers will be added to your '
                  'WhatsApp sticker tray.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(again ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}

class _ProblemsDialog extends StatelessWidget {
  const _ProblemsDialog({
    this.title = 'This pack is not ready',
    required this.problems,
  });

  final String title;
  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('export-problems'),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        // Every problem, not just the first: validation deliberately collects
        // them all so the user fixes everything in one pass instead of
        // discovering the next one each time they retry.
        children: [for (final problem in problems) Text('• $problem')],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Whether [pack] can be exported at all.
///
/// WhatsApp refuses a pack under the floor, so the button is disabled rather
/// than offered-then-refused; [shortfallLabel] says how far off it is.
bool canExport(PackRecord pack) =>
    pack.stickerIds.length >= WhatsAppSpec.minStickersPerPack;

String shortfallLabel(PackRecord pack) {
  final short = WhatsAppSpec.minStickersPerPack - pack.stickerIds.length;
  return '$short more sticker${short == 1 ? '' : 's'} before you can add '
      'this pack to WhatsApp';
}
