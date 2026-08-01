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

  /// Still formats we must reject up front because nothing in our static path
  /// can read them. HEIC is a common phone camera format, so this is a real
  /// gap rather than a theoretical one — see `CLAUDE.md` for the fallback plan.
  static const Set<String> _undecodableStills = {
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

    // Also before the prefix: the Dart `image` package cannot decode HEIC/HEIF,
    // so accepting them here would defer the failure to the encoder and report
    // it as an unreadable file rather than an unsupported format.
    if (_undecodableStills.contains(mime)) return null;

    if (mime.startsWith('image/')) return MediaKind.image;
    return null;
  }

  static MediaKind? _fromExtension(String? path) {
    if (path == null || path.isEmpty) return null;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    final ext = path.substring(dot + 1).toLowerCase();

    // Only formats we can actually decode. Stills go through the Dart `image`
    // package, which has **no HEIC/HEIF decoder** — so heic/heif are deliberately
    // absent despite being a common phone camera format. Claiming them would
    // turn into "could not decode the image" on a photo the user can see fine in
    // their gallery. See CLAUDE.md for the planned fallback.
    const images = {'png', 'jpg', 'jpeg', 'webp', 'bmp'};
    // Videos go through ffmpeg, which genuinely handles all of these.
    const videos = {'mp4', 'mov', 'webm', 'mkv', 'avi', '3gp', 'm4v'};

    if (ext == 'gif') return MediaKind.gif;
    if (images.contains(ext)) return MediaKind.image;
    if (videos.contains(ext)) return MediaKind.video;
    return null;
  }
}
