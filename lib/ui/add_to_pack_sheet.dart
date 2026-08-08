import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../core/whatsapp_spec.dart';
import '../models/pack_record.dart';
import '../models/sticker_record.dart';
import '../packs/pack_service.dart';

/// Asks which pack [sticker] should join, and puts it there.
///
/// Returns the pack it joined, or `null` if the user backed out. Built as a
/// standalone sheet rather than as Maker state because the Library (Task 14)
/// needs exactly this action on an existing sticker.
Future<PackRecord?> showAddToPackSheet({
  required BuildContext context,
  required AppDependencies dependencies,
  required StickerRecord sticker,
}) {
  return showModalBottomSheet<PackRecord>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _AddToPackSheet(dependencies: dependencies, sticker: sticker),
  );
}

class _AddToPackSheet extends StatefulWidget {
  const _AddToPackSheet({required this.dependencies, required this.sticker});

  final AppDependencies dependencies;
  final StickerRecord sticker;

  @override
  State<_AddToPackSheet> createState() => _AddToPackSheetState();
}

class _AddToPackSheetState extends State<_AddToPackSheet> {
  List<PackRecord>? _packs;
  bool _busy = false;
  String? _error;

  /// True while the user is naming a new pack.
  ///
  /// Inline rather than a dialog on top of the sheet: a modal stacked on a
  /// modal is awkward on a phone, and keeping it to one route means naming and
  /// creating are a single interaction instead of two routes to unwind.
  bool _naming = false;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final packs = await widget.dependencies.store.allPacks();
    if (mounted) setState(() => _packs = packs);
  }

  /// Runs [work] with a spinner, turning [PackLimitException] into its own
  /// message rather than a crash — the limits are WhatsApp's, and its wording
  /// already names the remedy.
  Future<void> _run(Future<PackRecord> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pack = await work();
      if (mounted) Navigator.of(context).pop(pack);
    } on PackLimitException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _addTo(PackRecord pack) =>
      _run(() => widget.dependencies.packs.addSticker(pack, widget.sticker));

  Future<void> _createNew() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    await _run(
      () => widget.dependencies.packs.createPack(
        name: name,
        first: widget.sticker,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packs = _packs;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add to pack',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (_error != null) _ErrorText(_error!),
            if (_busy)
              // Deliberately says nothing about what is happening underneath.
              // Adding a static to an animated pack re-encodes it as a 2-frame
              // animation, and naming that would hand the user the very
              // constraint this design exists to dissolve.
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Adding…'),
                  ],
                ),
              )
            else if (packs == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_naming)
              _NameField(
                controller: _name,
                onCreate: _createNew,
                onCancel: () => setState(() => _naming = false),
              )
            else ...[
              if (packs.isNotEmpty)
                Flexible(
                  child: ListView(
                    key: const Key('pack-list'),
                    shrinkWrap: true,
                    children: [
                      for (final pack in packs)
                        _PackTile(pack: pack, onTap: () => _addTo(pack)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() => _naming = true),
                icon: const Icon(Icons.add),
                label: const Text('New pack'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({required this.pack, required this.onTap});

  final PackRecord pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = pack.stickerIds.length;
    final short = WhatsAppSpec.minStickersPerPack - count;

    return ListTile(
      onTap: onTap,
      title: Text(pack.name),
      // A pack under the floor cannot be added to WhatsApp at all, so say how
      // far off it is here rather than letting the user find out at export.
      subtitle: Text(
        short > 0
            ? '$count stickers · $short more before you can add it to WhatsApp'
            : '$count stickers',
      ),
    );
  }
}

/// Names a new pack, in place.
///
/// Deliberately not an [AlertDialog] over the sheet. Beyond a modal-on-a-modal
/// being awkward on a phone, a second route makes creation impossible to drive:
/// popping a dialog needs frames pumped, while the tray-icon write that follows
/// needs the real event loop, and a widget test cannot give both in that order.
class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.onCreate,
    required this.onCancel,
  });

  final TextEditingController controller;
  final VoidCallback onCreate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('pack-name'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Pack name',
            hintText: 'Inside jokes',
          ),
          onSubmitted: (_) => onCreate(),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: onCreate, child: const Text('Create')),
          ],
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      // PackLimitException's own wording. It names the remedy — "Start another
      // pack for this one" — which a generic failure would throw away.
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
