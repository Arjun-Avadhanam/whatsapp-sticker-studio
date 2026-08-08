import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../models/sticker_record.dart';
import '../search/search_service.dart';
import 'add_to_pack_sheet.dart';
import 'sticker_detail_sheet.dart';

/// How long typing has to stop before a query is issued.
///
/// Search is cheap here (a local FTS5 table over hundreds of rows), so this is
/// not about protecting a backend — it is about not replacing the grid under the
/// user's eyes on every keystroke, which reads as flicker.
const _debounce = Duration(milliseconds: 300);

/// Everything the user has made, searchable.
///
/// Task 14. Editing and per-sticker actions land on top of this.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.dependencies, this.search});

  final AppDependencies dependencies;

  /// Injectable so tests can observe query timing and count. Production uses
  /// the one from the composition root.
  final SearchService? search;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final SearchService _search =
      widget.search ?? widget.dependencies.search;

  final _field = TextEditingController();
  Timer? _debounceTimer;

  List<StickerRecord>? _stickers;
  String _query = '';

  /// Monotonic id of the most recently *issued* request.
  ///
  /// Debouncing reduces overlap but does not remove it: a slow query can still
  /// be in flight when a later one resolves, and its stale results would then
  /// land last and replace the newer ones — showing results for a query the user
  /// has already changed. Every response checks this before it is allowed to
  /// paint.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => _run(q));
  }

  /// Opens the detail sheet, and reloads if anything was saved.
  ///
  /// Reloads through the *current* query rather than resetting to the whole
  /// library: a rename can move a sticker out of the results it was found in, and
  /// silently dropping the user's filter would lose their place.
  Future<void> _openDetail(StickerRecord sticker) async {
    final result = await showStickerDetailSheet(
      context: context,
      dependencies: widget.dependencies,
      sticker: sticker,
    );
    if (!mounted) return;

    // Opened here, after the detail sheet has closed, rather than from inside it.
    // The picker is itself a bottom sheet, and stacking one over another is poor
    // on a phone. The sticker is re-read because the detail sheet may have just
    // renamed it, and the picker shows that name.
    if (result.wantsAddToPack) {
      final current =
          await widget.dependencies.store.getSticker(sticker.id) ?? sticker;
      if (!mounted) return;
      await showAddToPackSheet(
        context: context,
        dependencies: widget.dependencies,
        sticker: current,
      );
      if (!mounted) return;
    }

    if (result.changed || result.wantsAddToPack) await _run(_field.text);
  }

  Future<void> _run(String q) async {
    final id = ++_requestId;

    // An empty query means "show everything", answered by the store rather than
    // by search. Two reasons: it is the cheaper path, and FTS5's MATCH on an
    // empty string returns *nothing*, so routing it through search would blank
    // the library the moment the field is cleared.
    final results = q.trim().isEmpty
        ? await widget.dependencies.store.allStickers()
        : (await _search.query(q)).map((h) => h.record).toList();

    // Superseded while we were waiting. Discard rather than paint.
    if (!mounted || id != _requestId) return;
    setState(() {
      _stickers = results;
      _query = q.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final stickers = _stickers;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            key: const Key('library-search'),
            controller: _field,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search your stickers',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _field.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _field.clear();
                        // Immediate, not debounced: clearing is a decisive
                        // action and waiting 300ms to undo a filter feels broken.
                        _debounceTimer?.cancel();
                        _run('');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: switch (stickers) {
            null => const Center(child: CircularProgressIndicator()),
            [] when _query.isNotEmpty => _NoResults(query: _query),
            [] => const _EmptyLibrary(),
            _ => _Grid(stickers: stickers, onTap: _openDetail),
          },
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.stickers, required this.onTap});

  final List<StickerRecord> stickers;
  final ValueChanged<StickerRecord> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      key: const Key('library-grid'),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // Max extent rather than a fixed column count, so the grid adapts to
        // width instead of showing tiny tiles on a tablet.
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82, // square sticker + one line of label
      ),
      itemCount: stickers.length,
      itemBuilder: (_, i) =>
          StickerTile(sticker: stickers[i], onTap: () => onTap(stickers[i])),
    );
  }
}

/// One sticker in the grid.
///
/// Public so widget tests can assert on *order* by reading the built tiles,
/// rather than inferring it from paint positions.
class StickerTile extends StatelessWidget {
  const StickerTile({super.key, required this.sticker, this.onTap});

  final StickerRecord sticker;
  final VoidCallback? onTap;

  /// What to call this sticker in one line.
  ///
  /// Never the id — it is a microsecond timestamp, so showing it would be pure
  /// noise. Auto-tags are the fallback: device testing showed they are generic,
  /// but "dog, pet" still describes the picture, and something beats nothing.
  String get label {
    final name = sticker.manualName?.trim();
    if (name != null && name.isNotEmpty) return name;

    final tags = sticker.autoTags.where((t) => t.trim().isNotEmpty);
    return tags.isEmpty ? 'Untitled' : tags.take(2).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _Thumbnail(path: sticker.thumbnailPath),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      // Flutter decodes animated WebP natively, so animated stickers loop here
      // exactly as they will in WhatsApp.
      //
      // errorBuilder is not defensive padding: records and files can drift apart
      // via a failed write, a cleared cache or a restored backup, and without it
      // one missing file throws during paint and takes the whole grid with it.
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined, size: 28)),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('library-empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_view_outlined, size: 40),
            const SizedBox(height: 12),
            // A new install is *supposed* to be empty, so this names the next
            // action instead of reading like something went wrong.
            Text(
              'No stickers yet.\nMake one on the Make tab and it will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing matched the query.
///
/// Kept distinct from [_EmptyLibrary] on purpose: "you have no stickers" and
/// "none of your stickers match this" call for different next actions, and
/// showing the first when the second is true would suggest the library was lost.
class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('library-no-results'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 40),
            const SizedBox(height: 12),
            Text(
              'Nothing matches "$query".',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            // Auto-tags are generic (device-verified), so a name the user gave a
            // sticker is by far the most reliable way to find it again.
            Text(
              'Naming your stickers makes them much easier to find.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
