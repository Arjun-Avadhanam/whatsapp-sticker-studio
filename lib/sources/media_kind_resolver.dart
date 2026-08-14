import '../core/media.dart';

/// Decides which [MediaKind] a picked or shared file is.
///
/// Shared by every [Source], and load-bearing: this is what routes media to the
/// static or the animated encoder. A GIF misread as an image silently loses its
/// animation; a video misread as an image fails later at decode, far from the
/// cause. So the rules live in one tested place rather than being re-derived in
/// each source.
class MediaKindResolver {
  const MediaKindResolver._();

  /// Formats the Dart `image` package cannot read, but **ffmpeg can** — so they
  /// are accepted here and handled by `StaticEncoder`'s transcoder fallback.
  ///
  /// These were rejected outright until 2026-08-14, which was a workaround, not
  /// a fix: HEIC is the default camera format on many phones, so a user picked a
  /// photo they could see perfectly well in their gallery and was told it was
  /// unsupported. Device-verified that this ffmpeg build decodes both HEIC and
  /// AVIF before the rejection was lifted — accepting them without that would
  /// only have traded "unsupported format" for the vaguer "could not decode".
  static const Set<String> _transcodedStills = {
    'image/heic',
    'image/heif',
    'image/avif',
  };

  /// Resolves from [mimeType] if given, else from [path]'s extension.
  ///
  /// Returns `null` when the media is not something we can make a sticker from
  /// — callers should reject it at the source rather than pass unknown bytes to
  /// an encoder.
  static MediaKind? of({String? mimeType, String? path}) {
    // The mime type wins: screen recorders and download caches routinely produce
    // names like "video.mp4.tmp", and share intents can supply no extension at
    // all, so an extension is only a fallback.
    final fromMime = _fromMime(mimeType);
    if (fromMime != null) return fromMime;
    return _fromExtension(path);
  }

  static MediaKind? _fromMime(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) return null;
    final mime = mimeType.toLowerCase().split(';').first.trim();

    // Checked before the generic image/ prefix: "image/gif" would otherwise be
    // classed as a still and lose its frames.
    if (mime == 'image/gif') return MediaKind.gif;
    if (mime.startsWith('video/')) return MediaKind.video;

    // Named explicitly rather than left to the generic image/ prefix, so the
    // set stays the one documented place recording which stills need the
    // transcoder — the prefix would accept them silently and lose that.
    if (_transcodedStills.contains(mime)) return MediaKind.image;

    if (mime.startsWith('image/')) return MediaKind.image;
    return null;
  }

  static MediaKind? _fromExtension(String? path) {
    if (path == null || path.isEmpty) return null;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    final ext = path.substring(dot + 1).toLowerCase();

    // Only formats we can actually decode. The first five go straight through
    // the Dart `image` package; heic/heif/avif have no decoder there and rely on
    // `StaticEncoder`'s ffmpeg transcoder instead — device-verified 2026-08-14.
    const images = {
      'png',
      'jpg',
      'jpeg',
      'webp',
      'bmp',
      'heic',
      'heif',
      'avif',
    };
    // Videos go through ffmpeg, which genuinely handles all of these.
    const videos = {'mp4', 'mov', 'webm', 'mkv', 'avi', '3gp', 'm4v'};

    if (ext == 'gif') return MediaKind.gif;
    if (images.contains(ext)) return MediaKind.image;
    if (videos.contains(ext)) return MediaKind.video;
    return null;
  }
}
