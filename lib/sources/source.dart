import '../core/media.dart';

/// Where input media comes from — gallery, camera, share-in, Giphy, X-link.
///
/// Each implementation is constructed with whatever it needs (a chosen gif, a
/// pasted URL, …), so [pick] stays argument-free and the Maker can treat every
/// source identically. Defined here (device-free) ahead of Task 7's platform
/// pickers because Giphy (Task 8) and X-link (Task 8B) consume it now.
abstract class Source {
  /// The picked media, or `null` if **the user cancelled**.
  ///
  /// Null means "nothing happened, on purpose" and the Maker shows nothing at
  /// all — backing out of the gallery is an ordinary choice, not a failure.
  /// A source that genuinely *failed* throws [SourceException] instead.
  Future<MediaHandle?> pick();
}

/// A source that failed for a reason the user needs to hear.
///
/// Split from the `null` return because the two were conflated, and the cost
/// landed entirely on the remote sources: a dead network, a private post and a
/// deleted post all became a silent no-op, identical to a cancel. The user taps,
/// waits, and nothing happens — which reads as a broken app rather than a
/// broken link.
///
/// [message] is shown **verbatim**, the same rule the exporter follows for
/// WhatsApp's rejections: for a third-party link the service's own wording
/// ("No video could be found in this tweet") is the only diagnostic that exists,
/// and paraphrasing it into "something went wrong" destroys the sole clue.
class SourceException implements Exception {
  const SourceException(this.message);
  final String message;
  @override
  String toString() => 'SourceException: $message';
}
