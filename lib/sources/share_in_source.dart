import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/media.dart';
import 'media_kind_resolver.dart';
import 'source.dart';

/// Receives media shared **into** the app from the OS share sheet.
///
/// A headline entry point, not a minor source (spec §4.1): "Share → Sticker
/// Studio" is a gesture users already know, it turns any screenshot or screen
/// recording into a sticker in one step, and it is **API-independent** — it
/// rides the OS share sheet rather than WhatsApp's sticker API, so it survives
/// any change WhatsApp makes to that API.
///
/// Unlike the pickers, this source is **push, not pull**: the OS decides when
/// media arrives. [pick] therefore returns whatever is already waiting, while
/// [stream] carries everything that arrives later.
class ShareInSource implements Source {
  ShareInSource({ReceiveSharingIntent? intent})
    : _intent = intent ?? ReceiveSharingIntent.instance;

  final ReceiveSharingIntent _intent;

  /// Media the app was **launched by** (cold start).
  ///
  /// Calls `reset()` afterwards. Without it the same share is replayed on every
  /// subsequent query, so a user who shares one image once would find it
  /// reappearing each time they returned to the Maker.
  @override
  Future<MediaHandle?> pick() async {
    final files = await _intent.getInitialMedia();
    final handle = await _firstUsable(files);
    if (files.isNotEmpty) _intent.reset();
    return handle;
  }

  /// Media shared while the app is **already running** (warm).
  ///
  /// Handling only the cold-start case is the classic mistake here: a share
  /// target is usually *already in memory* when someone shares to it, so missing
  /// this stream drops shares silently in the common case, with no error to
  /// explain the nothing that happened.
  Stream<MediaHandle> stream() {
    return _intent
        .getMediaStream()
        .asyncMap(_firstUsable)
        .where((h) => h != null)
        .cast<MediaHandle>();
  }

  /// Takes the first shareable file we can actually handle.
  ///
  /// `ACTION_SEND_MULTIPLE` can deliver several files, and a share can include
  /// items we cannot make stickers from (documents, plain text). Picking the
  /// first *usable* one is better than failing the whole share because item
  /// three was a PDF. Multi-sticker import is deferred to a later task.
  Future<MediaHandle?> _firstUsable(List<SharedMediaFile> files) async {
    for (final file in files) {
      final kind = MediaKindResolver.of(
        mimeType: file.mimeType,
        path: file.path,
      );
      if (kind == null) continue;

      final source = File(file.path);
      if (!source.existsSync()) continue;

      // The read is guarded, not just the existence check. Existing and
      // *readable* are different things: a share can hand over a path this
      // process has no permission to open, and device testing 2026-08-13 showed
      // that throwing here escapes as an **unhandled exception** — the app dies
      // on a share instead of quietly moving to the next file, which is exactly
      // what "first usable" is supposed to mean.
      final Uint8List bytes;
      try {
        bytes = await source.readAsBytes();
      } on FileSystemException {
        continue;
      }
      if (bytes.isEmpty) continue;

      return MediaHandle(bytes: bytes, kind: kind, mimeType: file.mimeType);
    }
    return null;
  }
}
