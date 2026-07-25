/// The intrinsic properties of an encoded media file, read from its actual
/// bytes rather than trusted from a record.
class ProbeResult {
  const ProbeResult({
    required this.width,
    required this.height,
    required this.format,
  });

  final int width;
  final int height;

  /// Lower-case container format: `'webp'`, `'png'`, `'jpeg'`, ... — whatever
  /// the header identifies. Never assumed; if unrecognised, the probe reports
  /// what it found so the validator can reject it.
  final String format;
}

/// Thrown when a file cannot be parsed at all (too short, or no recognised
/// signature). Failing loudly beats returning a plausible-looking default that
/// might slip an invalid file past validation.
class ProbeException implements Exception {
  const ProbeException(this.message);
  final String message;
  @override
  String toString() => 'ProbeException: $message';
}

/// Reads a media file's header to recover its true dimensions and format.
///
/// Injected into [StickerValidator] so validation can verify the real file
/// (catching corruption or a non-encoder import) instead of trusting the
/// record's fields — while tests substitute a fake and stay file-less.
abstract class MediaProbe {
  Future<ProbeResult> probe(String filePath);
}
