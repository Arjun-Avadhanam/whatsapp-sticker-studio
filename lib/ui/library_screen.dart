import 'dart:io';

import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../models/sticker_record.dart';

/// Everything the user has made.
///
/// Task 14. Search, editing and per-sticker actions land on top of this grid;
/// it exists first so there is something for them to act on.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<StickerRecord>? _stickers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Newest-first ordering is the store's guarantee, not this screen's — see
    // `LibraryStore.allStickers`.
    final stickers = await widget.dependencies.store.allStickers();
    if (mounted) setState(() => _stickers = stickers);
  }

  @override
  Widget build(BuildContext context) {
    final stickers = _stickers;

    if (stickers == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (stickers.isEmpty) return const _EmptyLibrary();

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
      itemBuilder: (_, i) => StickerTile(sticker: stickers[i]),
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
