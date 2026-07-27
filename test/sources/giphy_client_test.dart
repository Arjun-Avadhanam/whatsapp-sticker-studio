import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/sources/giphy_client.dart';

/// A trimmed but realistically-shaped Giphy `/v1/gifs/search` response.
String cannedResponse({int count = 2}) => jsonEncode({
  'data': List.generate(
    count,
    (i) => {
      'id': 'id$i',
      'title': 'gif number $i',
      'images': {
        'preview_gif': {'url': 'https://media.giphy.com/preview$i.gif'},
        'original': {'mp4': 'https://media.giphy.com/original$i.mp4'},
      },
    },
  ),
  'pagination': {'total_count': count, 'count': count, 'offset': 0},
  'meta': {'status': 200, 'msg': 'OK'},
});

void main() {
  GiphyClient clientReturning(
    String body, {
    int status = 200,
    void Function(http.Request)? onRequest,
  }) {
    final mock = MockClient((req) async {
      onRequest?.call(req);
      return http.Response(body, status);
    });
    return GiphyClient(mock, apiKey: 'test-key');
  }

  test('parses the search payload into GiphyGifs', () async {
    final gifs = await clientReturning(cannedResponse(count: 2)).search('dog');

    expect(gifs, hasLength(2));
    expect(gifs.first.id, 'id0');
    expect(gifs.first.title, 'gif number 0');
    expect(gifs.first.previewUrl.toString(), endsWith('preview0.gif'));
    expect(gifs.first.mp4Url.toString(), endsWith('original0.mp4'));
  });

  test('sends the api key, query and limit as request parameters', () async {
    http.Request? captured;
    await clientReturning(
      cannedResponse(),
      onRequest: (req) => captured = req,
    ).search('happy dog', limit: 10);

    final q = captured!.url.queryParameters;
    expect(q['api_key'], 'test-key');
    expect(q['q'], 'happy dog');
    expect(q['limit'], '10');
    expect(captured!.url.path, '/v1/gifs/search');
  });

  test('an empty result set yields an empty list', () async {
    final gifs = await clientReturning(cannedResponse(count: 0)).search('zzz');
    expect(gifs, isEmpty);
  });

  test('a non-200 response throws GiphyException', () async {
    expect(
      () => clientReturning('{"meta":{"status":403}}', status: 403).search('x'),
      throwsA(isA<GiphyException>()),
    );
  });

  test('a gif missing its mp4 or preview is skipped, not fatal', () async {
    final body = jsonEncode({
      'data': [
        {
          'id': 'ok',
          'title': 't',
          'images': {
            'preview_gif': {'url': 'https://x/p.gif'},
            'original': {'mp4': 'https://x/o.mp4'},
          },
        },
        {
          'id': 'broken',
          'title': 't',
          'images': {
            'preview_gif': {'url': 'https://x/p.gif'},
          }, // no mp4
        },
      ],
    });
    final gifs = await clientReturning(body).search('x');
    expect(gifs, hasLength(1));
    expect(gifs.single.id, 'ok');
  });
}
