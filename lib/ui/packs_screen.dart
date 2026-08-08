import 'dart:io';

import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../models/pack_record.dart';
import 'export_pack_action.dart';

/// The packs you have built, and the way to send each one to WhatsApp.
///
/// **This screen closes a real hole rather than adding a nicety.** Before it, a
/// pack could only be exported in the moment right after adding a sticker to it
/// in the Maker — close the app and every pack became unreachable, so a user
/// could build packs they were unable to send. A pack is also the *only* route
/// into WhatsApp's sticker tray, which makes that hole a v1 blocker.
class PacksScreen extends StatefulWidget {
  const PacksScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> {
  List<PackRecord>? _packs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packs = await widget.dependencies.store.allPacks();
    if (mounted) setState(() => _packs = packs);
  }

  Future<void> _export(PackRecord pack) async {
    await confirmAndExportPack(
      context: context,
      dependencies: widget.dependencies,
      pack: pack,
    );
    // Reload regardless of the outcome: a successful export changes nothing in
    // the record, but a *failed* one may have been caused by a change made
    // elsewhere, and showing stale counts next to a rejection is confusing.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final packs = _packs;

    if (packs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (packs.isEmpty) return const _NoPacks();

    return ListView.builder(
      key: const Key('packs-list'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: packs.length,
      itemBuilder: (_, i) =>
          PackTile(pack: packs[i], onExport: () => _export(packs[i])),
    );
  }
}

/// One pack.
///
/// Public so widget tests can assert on order by reading the built tiles rather
/// than inferring it from paint positions.
class PackTile extends StatelessWidget {
  const PackTile({super.key, required this.pack, required this.onExport});

  final PackRecord pack;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final ready = canExport(pack);

    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: Image.file(
          File(pack.trayIconPath),
          fit: BoxFit.contain,
          // Records and files can drift apart; a missing tray icon must not take
          // the list down.
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        ),
      ),
      title: Text(pack.name),
      // Deliberately not labelled animated or static. That is a property the
      // user never chose and cannot act on, and surfacing it would edge toward
      // exposing the promotion rule this design exists to keep invisible.
      subtitle: Text(ready ? stickerCount(pack) : shortfallLabel(pack)),
      trailing: FilledButton.tonal(
        key: Key('export-${pack.id}'),
        onPressed: ready ? onExport : null,
        child: const Text('Add to WhatsApp'),
      ),
    );
  }
}

class _NoPacks extends StatelessWidget {
  const _NoPacks();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('packs-empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_copy_outlined, size: 40),
            const SizedBox(height: 12),
            // Names the exact action that creates one. A pack is the only way
            // into WhatsApp's tray, so "you have no packs" without a route out
            // of that state would be a dead end.
            Text(
              'No packs yet.\n'
              'Open a sticker and choose "Add to pack" to start one.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
