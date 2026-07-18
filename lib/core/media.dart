import 'dart:typed_data';

/// What kind of media a [Source] handed us, *before* encoding.
///
/// Coarse on purpose — the pipeline only ever branches three ways. The precise
/// external label (e.g. `video/quicktime` vs `video/mp4`) is preserved separately
/// on [MediaHandle.mimeType] for the encoder, which does care.
enum MediaKind {
  image,
  gif,
  video;

  /// The sticker a source of this kind becomes once encoded.
  ///
  /// Chosen here rather than at each call site so the mapping lives in one
  /// place: adding a future [MediaKind] forces this switch to be updated, and
  /// the compiler flags every unhandled case.
  StickerKind get producesStickerKind => switch (this) {
    MediaKind.image => StickerKind.staticImage,
    MediaKind.gif => StickerKind.animated,
    MediaKind.video => StickerKind.animated,
  };
}

/// What a sticker *is* once encoded — the distinction WhatsApp cares about,
/// because it selects the size ceiling (100 KB static vs 500 KB animated) and
/// the pack's `animated_sticker_pack` metadata flag.
enum StickerKind { staticImage, animated }

/// How to fit a non-square source into the mandatory 512x512 frame.
enum FitMode {
  /// Letterbox: scale to fit, then centre on a transparent 512² canvas.
  /// Loses nothing, but leaves empty bars.
  pad,

  /// Centre-crop to a square, then scale. Fills the frame, cuts the edges.
  /// Subject-aware cropping is deferred to v1.1.
  smartCrop,

  /// Scale to fit without padding to the full canvas.
  contain,
}

/// Raw media in flight between a [Source] and the [Encoder].
///
/// Deliberately holds *bytes*, not a file path: sources are heterogeneous
/// (gallery file, camera capture, HTTP download from Giphy or the X extractor)
/// and only bytes are common to all of them. Keeping the encoder's input to one
/// type means each new source is a new [Source] implementation, not a new branch
/// inside the encoder.
class MediaHandle {
  const MediaHandle({required this.bytes, required this.kind, this.mimeType});

  final Uint8List bytes;

  /// Our coarse interpretation, used for pipeline branching.
  final MediaKind kind;

  /// The precise external media type (e.g. `video/mp4`) when the source knew it.
  ///
  /// Null when unknowable — e.g. a picker gave us only a file extension. Recorded
  /// honestly as absent rather than guessed, so a later consumer can tell
  /// "unknown" apart from "known to be X".
  final String? mimeType;
}
