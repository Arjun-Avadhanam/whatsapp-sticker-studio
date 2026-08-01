import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/sources/media_kind_resolver.dart';
import 'package:whatsapp_sticker_studio/sources/source.dart';

/// A source that yields fixed media, or nothing.
class FakeSource implements Source {
  FakeSource(this._handle);
  FakeSource.cancelled() : _handle = null;

  final MediaHandle? _handle;

  @override
  Future<MediaHandle?> pick() async => _handle;
}

void main() {
  group('Source contract', () {
    test('a picked source yields non-empty bytes and a kind', () async {
      final source = FakeSource(
        MediaHandle(
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          kind: MediaKind.image,
          mimeType: 'image/png',
        ),
      );

      final media = await source.pick();
      expect(media, isNotNull);
      expect(media!.bytes, isNotEmpty);
      expect(media.kind, MediaKind.image);
    });

    test('cancelling yields null rather than throwing', () async {
      // Cancel is an ordinary outcome, not an error: the Maker should quietly
      // return to its previous state, not surface a failure the user caused
      // deliberately.
      expect(await FakeSource.cancelled().pick(), isNull);
    });
  });

  group('MediaKindResolver', () {
    // This is the branch that decides whether media goes to StaticEncoder or
    // AnimatedEncoder, and every source depends on it. Getting a GIF wrong
    // silently produces a one-frame sticker; getting a video wrong fails later
    // at decode, far from the cause.

    test('reads the mime type when one is supplied', () {
      expect(MediaKindResolver.of(mimeType: 'image/png'), MediaKind.image);
      expect(MediaKindResolver.of(mimeType: 'image/jpeg'), MediaKind.image);
      expect(MediaKindResolver.of(mimeType: 'image/webp'), MediaKind.image);
      expect(MediaKindResolver.of(mimeType: 'image/gif'), MediaKind.gif);
      expect(MediaKindResolver.of(mimeType: 'video/mp4'), MediaKind.video);
      expect(
        MediaKindResolver.of(mimeType: 'video/quicktime'),
        MediaKind.video,
      );
    });

    test('GIF is its own kind, not a plain image', () {
      // image/gif starts with "image/", so a naive prefix check would call it a
      // static image and throw away the animation.
      expect(MediaKindResolver.of(mimeType: 'image/gif'), MediaKind.gif);
      expect(MediaKindResolver.of(path: 'a/b/funny.gif'), MediaKind.gif);
    });

    test('falls back to the file extension when mime is missing', () {
      // Share intents and some pickers hand over a path with no mime type.
      expect(MediaKindResolver.of(path: '/tmp/photo.JPG'), MediaKind.image);
      expect(MediaKindResolver.of(path: '/tmp/clip.MP4'), MediaKind.video);
      expect(MediaKindResolver.of(path: '/tmp/loop.webm'), MediaKind.video);
      expect(MediaKindResolver.of(path: '/tmp/shot.webp'), MediaKind.image);
    });

    test('prefers the mime type over a misleading extension', () {
      // Screen recorders and download caches routinely produce names like
      // "video.mp4.tmp" or extensionless files; the mime type is authoritative.
      expect(
        MediaKindResolver.of(mimeType: 'video/mp4', path: '/tmp/thing.png'),
        MediaKind.video,
      );
    });

    test('rejects stills nothing in our pipeline can decode', () {
      // HEIC is a common phone camera format, but the Dart `image` package has
      // no decoder for it. Accepting it here would defer the failure to the
      // encoder and report a photo the user can see in their gallery as
      // "could not decode the image".
      expect(MediaKindResolver.of(mimeType: 'image/heic'), isNull);
      expect(MediaKindResolver.of(mimeType: 'image/heif'), isNull);
      expect(MediaKindResolver.of(path: '/tmp/IMG_0001.heic'), isNull);
    });

    test('returns null when the kind cannot be determined', () {
      // Better to reject at the source than hand unknown bytes to an encoder
      // that will fail confusingly later.
      expect(MediaKindResolver.of(path: '/tmp/notes.txt'), isNull);
      expect(MediaKindResolver.of(mimeType: 'application/pdf'), isNull);
      expect(MediaKindResolver.of(), isNull);
    });
  });
}
