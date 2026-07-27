import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/sources/giphy_client.dart';
import 'package:whatsapp_sticker_studio/sources/giphy_source.dart';

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

  test('a failed download returns null rather than throwing', () async {
    final mock = MockClient((req) async => http.Response('nope', 404));
    expect(await GiphySource(gif, mock).pick(), isNull);
  });
}
