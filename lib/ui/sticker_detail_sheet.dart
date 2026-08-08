import 'dart:io';

import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../models/sticker_record.dart';

/// Shows one sticker and lets the user describe it.
///
/// Returns true if anything was saved, so the caller knows to refresh.
///
/// This is where a sticker earns its searchability. Auto-tags are generic —
/// device testing 2026-08-08 returned `sports, team, event` for a footballer —
/// so the words typed here are the strongest retrieval signal the library has,
/// and they are weighted an order of magnitude above the machine's guess.
Future<bool> showStickerDetailSheet({
  required BuildContext context,
  required AppDependencies dependencies,
  required StickerRecord sticker,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _StickerDetailSheet(dependencies: dependencies, sticker: sticker),
  );
  return saved ?? false;
}

class _StickerDetailSheet extends StatefulWidget {
  const _StickerDetailSheet({
    required this.dependencies,
    required this.sticker,
  });

  final AppDependencies dependencies;
  final StickerRecord sticker;

  @override
  State<_StickerDetailSheet> createState() => _StickerDetailSheetState();
}

class _StickerDetailSheetState extends State<_StickerDetailSheet> {
  late final _name = TextEditingController(
    text: widget.sticker.manualName ?? '',
  );
  late final _notes = TextEditingController(text: widget.sticker.notes ?? '');
  final _newTag = TextEditingController();

  /// A **copy**, edited locally and written only on Save — which is what makes
  /// Cancel genuinely discard rather than merely stop.
  late final List<String> _tags = [...widget.sticker.manualTags];

  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _newTag.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _newTag.text.trim();
    // Case-insensitive duplicate check: "Friends" and "friends" would both match
    // the same search, so keeping both is noise in the index and in the UI.
    if (tag.isEmpty || _tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
      _newTag.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _newTag.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);

    final name = _name.text.trim();
    final notes = _notes.text.trim();

    // One call, three fields. updateMetadata touches ONLY what it is given —
    // auto-tags and tagging status are untouched — and it funnels through
    // saveSticker, so the keyword index updates inside the same transaction.
    await widget.dependencies.store.updateMetadata(
      widget.sticker.id,
      // Empty clears rather than storing "": WhatsApp's accessibility_text falls
      // back to auto-tags on null, and would export a blank string otherwise.
      manualName: name.isEmpty ? null : name,
      manualTags: _tags,
      notes: notes.isEmpty ? null : notes,
    );

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // Applied by hand, OUTSIDE the SafeArea. A bottom sheet is anchored to the
    // bottom of the screen and Flutter does not lift it for the keyboard the way
    // it lifts a dialog — without this the fields sit behind the keyboard and the
    // user types blind. Found on device in the Add-to-pack sheet 2026-08-08; it
    // recurs verbatim in every new sheet with a text field.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Preview(path: widget.sticker.thumbnailPath),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('detail-name'),
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'so you can find it later',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                _MyTags(
                  tags: _tags,
                  controller: _newTag,
                  onAdd: _addTag,
                  onRemove: (tag) => setState(() => _tags.remove(tag)),
                ),
                if (widget.sticker.autoTags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _AutoTags(tags: widget.sticker.autoTags),
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const Key('detail-notes'),
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Capped so the editable fields stay on screen with the keyboard up —
      // a full-size preview would push the whole point of the sheet below the
      // fold.
      constraints: const BoxConstraints(maxHeight: 120),
      child: AspectRatio(
        aspectRatio: 1,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}

/// The user's own tags: removable, and added one at a time.
class _MyTags extends StatelessWidget {
  const _MyTags({
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tags;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your tags', style: Theme.of(context).textTheme.labelLarge),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in tags)
                Chip(
                  label: Text(tag),
                  onDeleted: () => onRemove(tag),
                  deleteIcon: Icon(
                    Icons.close,
                    size: 16,
                    key: Key('remove-tag-$tag'),
                  ),
                ),
            ],
          ),
        ],
        TextField(
          key: const Key('detail-add-tag'),
          controller: controller,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onAdd(),
          decoration: InputDecoration(
            hintText: 'Add a tag',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: onAdd,
            ),
          ),
        ),
      ],
    );
  }
}

/// What the tagger found. **Displayed, never editable.**
///
/// Deliberate: the user must never have to clear machine output to add their own
/// words. Offering a delete here would invite exactly that chore, and the next
/// tagging run replaces this list wholesale anyway — so a deletion would silently
/// come back. They are shown because they explain why a sticker turns up in a
/// search the user did not expect.
class _AutoTags extends StatelessWidget {
  const _AutoTags({required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Found automatically',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in tags)
              Chip(
                label: Text(tag),
                // Visually lighter than the user's own tags, matching how much
                // less they are weighted in search.
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
          ],
        ),
      ],
    );
  }
}
