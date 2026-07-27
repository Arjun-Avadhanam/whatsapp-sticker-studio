import '../core/media.dart';

/// Where input media comes from — gallery, camera, share-in, Giphy, X-link.
///
/// Each implementation is constructed with whatever it needs (a chosen gif, a
/// pasted URL, …), so [pick] stays argument-free and the Maker can treat every
/// source identically. Defined here (device-free) ahead of Task 7's platform
/// pickers because Giphy (Task 8) and X-link (Task 8B) consume it now.
abstract class Source {
  /// The picked media, or `null` if the user cancelled or the source failed in a
  /// recoverable way — the Maker turns `null` into a friendly message rather
  /// than an error.
  Future<MediaHandle?> pick();
}
