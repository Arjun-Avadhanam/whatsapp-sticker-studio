import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/sources/giphy_client.dart';
import 'package:whatsapp_sticker_studio/sources/giphy_source.dart';
import 'package:whatsapp_sticker_studio/sources/source.dart';

final gif = GiphyGif(
  id: 'id0',
  title: 't',
  previewUrl: Uri.parse('https://media.giphy.com/preview0.gif'),
  mp4Url: Uri.parse('https://media.giphy.com/original0.mp4'),
);

void main() {
  test('downloads the chosen gif mp4 into a video MediaHandle', () async {
    Uri? requested;
    final mock = MockClient((req) async {
      requested = req.url;
      return http.Response.bytes(Uint8List.fromList([1, 2, 3, 4]), 200);
    });

    final handle = await GiphySource(gif, mock).pick();

    expect(requested, gif.mp4Url); // downloads the mp4, not the preview
    expect(handle, isNotNull);
    expect(handle!.bytes, [1, 2, 3, 4]);
    expect(handle.kind, MediaKind.video);
    expect(handle.mimeType, 'video/mp4');
  });

  group('failures are reported, never silent', () {
    // Returning null used to be the answer, and the Maker reads null as "the
    // user cancelled" — so a dead connection or a dropped CDN response left the
    // screen inert with no explanation. Same bug as the X-link source had.

    test('a refused download says so, and suggests another gif', () async {
      final mock = MockClient((req) async => http.Response('nope', 404));

      await expectLater(
        GiphySource(gif, mock).pick(),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            allOf(contains('404'), contains('Try another')),
          ),
        ),
      );
    });

    test('a network error reads as a connection problem', () async {
      final mock = MockClient((req) async => throw const _Offline());

      await expectLater(
        GiphySource(gif, mock).pick(),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            contains('connection'),
          ),
        ),
      );
    });
  });
}

/// Stands in for a socket failure without depending on `dart:io`'s exact type —
/// the source catches anything, which is the behaviour under test.
class _Offline implements Exception {
  const _Offline();
}
