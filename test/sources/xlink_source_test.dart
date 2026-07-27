import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/sources/extraction_client.dart';
import 'package:whatsapp_sticker_studio/sources/xlink_source.dart';

/// Stub client whose extract() either returns fixed media or throws.
class StubExtractionClient implements ExtractionClient {
  StubExtractionClient({this.result, this.error});

  final ExtractedMedia? result;
  final Object? error;

  @override
  Future<ExtractedMedia> extract(String tweetUrl) async {
    if (error != null) throw error!;
    return result!;
  }
}

final _media = ExtractedMedia(
  Uri.parse('https://video.twimg.com/x.mp4'),
  MediaKind.video,
);

void main() {
  test('extracts then downloads the mp4 into a video MediaHandle', () async {
    Uri? requested;
    final download = MockClient((req) async {
      requested = req.url;
      return http.Response.bytes(Uint8List.fromList([9, 8, 7]), 200);
    });

    final handle = await XLinkSource(
      StubExtractionClient(result: _media),
      download,
      'https://x.com/u/status/1',
    ).pick();

    expect(requested, _media.mp4Url);
    expect(handle!.bytes, [9, 8, 7]);
    expect(handle.kind, MediaKind.video);
    expect(handle.mimeType, 'video/mp4');
  });

  test('returns null when extraction fails', () async {
    final handle = await XLinkSource(
      StubExtractionClient(error: ExtractionException('unavailable')),
      MockClient((req) async => http.Response('', 200)),
      'https://x.com/u/status/1',
    ).pick();

    expect(handle, isNull);
  });

  test('returns null when the mp4 download fails', () async {
    final handle = await XLinkSource(
      StubExtractionClient(result: _media),
      MockClient((req) async => http.Response('nope', 404)),
      'https://x.com/u/status/1',
    ).pick();

    expect(handle, isNull);
  });
}
