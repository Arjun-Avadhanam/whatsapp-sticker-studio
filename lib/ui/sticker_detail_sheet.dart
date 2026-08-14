import 'dart:io';

import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../core/whatsapp_spec.dart';
import '../models/sticker_record.dart';
import '../sharing/sharing_service.dart';
import 'confirm_delete.dart';

/// What the detail sheet did.
///
/// Two facts, not one: an edit needs a grid refresh, while an add-to-pack request
/// needs the *caller* to act — the pack picker is itself a bottom sheet, and
/// stacking one over another is poor on a phone. Collapsing these into a single
/// flag would lose whichever the other implied.
class StickerDetailResult {
  const StickerDetailResult({
    this.changed = false,
    this.wantsAddToPack = false,
    this.deleted = false,
  });

  /// Metadata was written, so anything displaying this sticker is stale.
  final bool changed;

  /// The user asked to file this sticker into a pack. The sheet is already
  /// closed; the caller opens the picker.
  final bool wantsAddToPack;

  /// The sticker was deleted. It no longer exists, so a caller holding the old
  /// record must not act on it.
  final bool deleted;
}

/// Shows one sticker and lets the user describe it.
///
/// This is where a sticker earns its searchability. Auto-tags are generic —
/// device testing 2026-08-08 returned `sports, team, event` for a footballer —
/// so the words typed here are the strongest retrieval signal the library has,
/// and they are weighted an order of magnitude above the machine's guess.
Future<StickerDetailResult> showStickerDetailSheet({
  required BuildContext context,
  required AppDependencies dependencies,
  required StickerRecord sticker,
}) async {
  final result = await showModalBottomSheet<StickerDetailResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _StickerDetailSheet(dependencies: dependencies, sticker: sticker),
  );
  // Dismissed by tapping outside or swiping down — nothing happened.
  return result ?? const StickerDetailResult();
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

  /// Likewise a copy. Max three, which is WhatsApp's limit.
  late final List<String> _emojis = [...widget.sticker.emojis];

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

  Future<void> _save({bool thenAddToPack = false}) async {
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
      emojis: _emojis,
    );

    if (mounted) {
      Navigator.of(
        context,
      ).pop(StickerDetailResult(changed: true, wantsAddToPack: thenAddToPack));
    }
  }

  /// Deletes the sticker, its record and its file — after asking.
  ///
  /// The file goes too. Leaving orphaned WebPs behind would grow the app's
  /// storage with bytes nothing can ever reach again, and "delete" that leaves
  /// the data on disk is not what the word means.
  Future<void> _delete() async {
    final name = widget.sticker.manualName?.trim();
    final confirmed = await confirmDelete(
      context: context,
      title: 'Delete this sticker?',
      message: name == null || name.isEmpty
          ? 'It will be removed from your library and from any pack it is in. '
                'This cannot be undone.'
          : '"$name" will be removed from your library and from any pack it is '
                'in. This cannot be undone.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    await widget.dependencies.store.deleteSticker(widget.sticker.id);

    // Best-effort: the record is already gone, so a file that refuses to delete
    // is wasted space, not a failed deletion, and must not surface as an error.
    //
    // Synchronous on purpose. One small file is microseconds, and async
    // `dart:io` never completes inside `testWidgets`' fake-time zone — an
    // `await file.delete()` here left the sheet un-popped and the test hanging
    // on a null result, with no error to explain it.
    try {
      final file = File(widget.sticker.filePath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}

    if (mounted) {
      Navigator.of(
        context,
      ).pop(const StickerDetailResult(changed: true, deleted: true));
    }
  }

  /// Shares the sticker **as a file**, through the OS share sheet.
  ///
  /// Stays inside this sheet because the share sheet is an OS surface, not
  /// another Flutter modal — nothing stacks. Add-to-pack cannot do the same.
  Future<void> _exportFile() async {
    final outcome = await widget.dependencies.sharing.shareSticker(
      widget.sticker,
    );
    if (!mounted) return;

    // Only worth saying something when it did not go out. A successful share
    // already showed the user the OS sheet and their chosen app.
    if (outcome == ShareOutcome.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export this sticker.')),
      );
    }
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
                const SizedBox(height: 16),
                _EmojiPicker(
                  selected: _emojis,
                  onToggle: (emoji) => setState(() {
                    if (_emojis.remove(emoji)) return;
                    if (_emojis.length < WhatsAppSpec.maxEmojisPerSticker) {
                      _emojis.add(emoji);
                    }
                  }),
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
                const SizedBox(height: 16),
                _Actions(
                  busy: _busy,
                  onAddToPack: () => _save(thenAddToPack: true),
                  onExportFile: _exportFile,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Left, away from Save, and the only destructive control on
                    // the sheet — a mis-tap here cannot be undone.
                    TextButton.icon(
                      key: const Key('delete-sticker'),
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(const StickerDetailResult()),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : () => _save(),
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

/// The two things you can do with a sticker from here.
///
/// **The wording is load-bearing.** There are two routes out of this app and they
/// are not interchangeable:
/// - *Add to pack* → the ContentProvider + `ENABLE_STICKER_PACK` path, which puts
///   real stickers in WhatsApp's tray but needs a whole pack.
/// - *Export file* → the OS share sheet, which moves a file. Device-verified
///   2026-08-06 that WhatsApp renders that `.webp` as an **ordinary image** in a
///   chat, not a sticker.
///
/// So this must never say "send sticker". That would repeat exactly the
/// overpromise removed from pack sharing.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.busy,
    required this.onAddToPack,
    required this.onExportFile,
  });

  final bool busy;
  final VoidCallback onAddToPack;
  final VoidCallback onExportFile;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : onAddToPack,
          icon: const Icon(Icons.library_add_outlined, size: 18),
          label: const Text('Add to pack'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onExportFile,
          icon: const Icon(Icons.ios_share, size: 18),
          label: const Text('Export file'),
        ),
      ],
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

/// Emoji for **WhatsApp's** sticker search — the one thing here that works after
/// the sticker leaves this app.
///
/// Everything else on this sheet (name, tags, notes) is indexed by *our* search
/// and helps only inside the Library. But nobody sends stickers from the Library;
/// they send them from a WhatsApp chat, and `emojis` is the only handle the tray
/// gives them there.
///
/// A curated grid rather than a full emoji keyboard: three slots is a small
/// decision, and a system keyboard would need "is this actually an emoji?"
/// validation for a field with a hard three-item cap.
/// The five Fitzpatrick modifiers, plus "as-is" for the default yellow.
///
/// Chosen once and applied to every tone-capable emoji, which is how system
/// keyboards do it. Listing each hand in all six tones instead would turn nine
/// emoji into fifty-four near-identical tiles.
const _skinTones = <String, String>{
  'default': '',
  'light': '\u{1F3FB}',
  'medium-light': '\u{1F3FC}',
  'medium': '\u{1F3FD}',
  'medium-dark': '\u{1F3FE}',
  'dark': '\u{1F3FF}',
};

/// Applies [tone] to [base], or restores VS16 when there is no tone.
///
/// The variation selector cannot coexist with a modifier — `✌️\u{1F3FD}`
/// is not a valid sequence and renders as a splodge — so the two are mutually
/// exclusive.
String applySkinTone(String base, String tone) {
  if (tone.isEmpty) {
    // ✌ and ☝ need VS16 to render as emoji rather than as monochrome glyphs.
    return base.length == 1 ? '$base\u{FE0F}' : base;
  }
  return '$base$tone';
}

class _EmojiPicker extends StatefulWidget {
  const _EmojiPicker({required this.selected, required this.onToggle});

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  State<_EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<_EmojiPicker> {
  String _tone = '';
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  List<String> get selected => widget.selected;
  ValueChanged<String> get onToggle => widget.onToggle;

  /// Skewed towards what people actually react with, rather than a balanced
  /// sample of the Unicode blocks.
  ///
  /// A shortcut, **not a limit** — the field beside it accepts any emoji, so a
  /// grid that cannot hold everything is fine.
  static const _faces = [
    '😂',
    '😍',
    '😭',
    '😅',
    '🥲',
    '😎',
    '🤔',
    '🙄',
    '😴',
    '🤯',
    '🥳',
    '😳',
    '💀',
    '🔥',
    '❤️',
    '✨',
  ];

  /// Emoji that take a Fitzpatrick modifier.
  ///
  /// Kept separate because they are rendered in the user's chosen tone rather
  /// than as-is. Listed **without** VS16 (U+FE0F): a variation selector sits
  /// between the base and the modifier and breaks the sequence, so ✌ and ☝ are
  /// bare here and only get VS16 when no tone is applied.
  static const _hands = ['👍', '👏', '🙏', '🤙', '✌', '👌', '🤟', '✋', '👋'];

  static const _things = [
    '🎉',
    '👀',
    '💯',
    '🚀',
    '🐶',
    '🐱',
    '🍕',
    '🍺',
    '⚽',
    '🎵',
    '📸',
    '💬',
  ];

  @override
  Widget build(BuildContext context) {
    final full = selected.length >= WhatsAppSpec.maxEmojisPerSticker;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Emoji for WhatsApp search',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Spacer(),
            Text(
              '${selected.length}/${WhatsAppSpec.maxEmojisPerSticker}',
              key: const Key('emoji-count'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        // Says where these are used, because it is not obvious that this field
        // leaves the app at all.
        Text(
          'How you find this sticker inside WhatsApp.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),

        // Anything already chosen shows first, so a custom emoji the grid does
        // not contain is still visible and removable.
        if (selected.isNotEmpty) ...[
          Wrap(
            spacing: 4,
            children: [
              for (final emoji in selected)
                _EmojiChip(
                  // Distinct from the grid's key: a chosen emoji appears in both
                  // rows, and one key for two widgets makes every finder
                  // ambiguous.
                  key: Key('chosen-$emoji'),
                  emoji: emoji,
                  chosen: true,
                  enabled: true,
                  onTap: () => onToggle(emoji),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final emoji in [
              ..._faces,
              ..._hands.map((h) => applySkinTone(h, _tone)),
              ..._things,
            ])
              _EmojiChip(
                emoji: emoji,
                chosen: selected.contains(emoji),
                // Disabled once full — but a *chosen* one stays tappable, or
                // there would be no way to swap without clearing first.
                enabled: !full || selected.contains(emoji),
                onTap: () => onToggle(emoji),
              ),
          ],
        ),

        const SizedBox(height: 10),
        Row(
          children: [
            Text('Skin tone', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 8),
            for (final entry in _skinTones.entries)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _EmojiChip(
                  key: Key('tone-${entry.key}'),
                  emoji: applySkinTone('✋', entry.value),
                  chosen: _tone == entry.value,
                  enabled: true,
                  onTap: () => setState(() => _tone = entry.value),
                  size: 32,
                ),
              ),
          ],
        ),

        const SizedBox(height: 8),
        // The grid is a shortcut, not a ceiling: anything the user's own
        // keyboard can produce is fair game, and a fixed list would otherwise
        // decide for them which emoji exist.
        TextField(
          key: const Key('emoji-custom'),
          controller: _custom,
          enabled: !full,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            isDense: true,
            hintText: full ? 'Three is the maximum' : 'Or type any emoji',
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: full ? null : _addCustom,
            ),
          ),
          onSubmitted: (_) => _addCustom(),
        ),
      ],
    );
  }

  /// Takes the first character *cluster* the user typed.
  ///
  /// `characters` rather than `String`: an emoji is routinely several code units
  /// — a base plus a modifier, or a ZWJ sequence — so slicing by index would
  /// split it into halves that render as tofu.
  void _addCustom() {
    final typed = _custom.text.trim();
    if (typed.isEmpty) return;
    final first = typed.characters.first;
    _custom.clear();
    if (!selected.contains(first)) onToggle(first);
  }
}

class _EmojiChip extends StatelessWidget {
  const _EmojiChip({
    super.key,
    required this.emoji,
    required this.chosen,
    required this.enabled,
    required this.onTap,
    this.size = 40,
  });

  final String emoji;
  final bool chosen;
  final bool enabled;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: Key('emoji-$emoji'),
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: chosen ? scheme.primaryContainer : null,
            border: Border.all(
              color: chosen ? scheme.primary : scheme.outlineVariant,
              width: chosen ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      ),
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
