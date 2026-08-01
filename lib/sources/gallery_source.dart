import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../core/media.dart';
import 'media_kind_resolver.dart';
import 'source.dart';

/// Picks an existing image **or video** from the device gallery.
///
/// Video is not an afterthought here: a screen recording or a saved clip is one
/// of the most common things people want to turn into an animated sticker, and
/// restricting the gallery to stills would push them back to the Giphy/X paths
/// for media they already have.
class GallerySource implements Source {
  GallerySource({ImagePicker? picker, this.allowVideo = true})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// When true, `pickMedia` offers stills and clips together.
  final bool allowVideo;

  @override
  Future<MediaHandle?> pick() async {
    // pickMedia presents one chooser for both kinds rather than making the user
    // decide "photo or video" before they have seen what is there.
    final XFile? file = allowVideo
        ? await _picker.pickMedia()
        : await _picker.pickImage(source: ImageSource.gallery);

    return fileToHandle(file);
  }
}

/// Converts a picked file to a [MediaHandle], or `null` if unusable.
///
/// Shared by the gallery, camera and share-in sources. Returns `null` — never
/// throws — for a cancel, and also for a file whose kind we cannot determine:
/// handing unknown bytes to an encoder produces a confusing failure much later,
/// so rejecting at the source is kinder.
Future<MediaHandle?> fileToHandle(XFile? file) async {
  if (file == null) return null;

  final kind = MediaKindResolver.of(mimeType: file.mimeType, path: file.path);
  if (kind == null) return null;

  final bytes = await File(file.path).readAsBytes();
  if (bytes.isEmpty) return null;

  return MediaHandle(bytes: bytes, kind: kind, mimeType: file.mimeType);
}
