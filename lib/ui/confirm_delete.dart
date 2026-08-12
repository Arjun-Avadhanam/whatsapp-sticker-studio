import 'package:flutter/material.dart';

/// Asks before destroying something. Returns true only on an explicit yes.
///
/// Deletion here is **permanent and unrecoverable** — there is no bin, no undo
/// and no cloud copy — so it must never be one stray tap away. The confirm
/// button is styled as destructive and Cancel is the safe default that dismissal
/// falls back to.
Future<bool> confirmDelete({
  required BuildContext context,
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('confirm-delete'),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  // Tapping outside or pressing back is a decision not to delete.
  return confirmed ?? false;
}
