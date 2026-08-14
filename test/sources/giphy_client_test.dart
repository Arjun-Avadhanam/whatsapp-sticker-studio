import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/sources/giphy_client.dart';

/// A trimmed but realistically-shaped Giphy response.
///
/// The field names were checked against the live API 2026-08-14 — until then
/// this fixture was the only payload the parser had ever seen, which is a poor
/// position for code whose whole job is reading someone else's JSON.
String cannedResponse({int count = 2, int? totalCount, int offset = 0}) =>
    jsonEncode({
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
      'pagination': {
        'total_count': totalCount ?? count,
        'count': count,
        'offset': offset,
      },
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
    final page = await clientReturning(cannedResponse(count: 2)).search('dog');

    expect(page.gifs, hasLength(2));
    expect(page.gifs.first.id, 'id0');
    expect(page.gifs.first.title, 'gif number 0');
    expect(page.gifs.first.previewUrl.toString(), endsWith('preview0.gif'));
    expect(page.gifs.first.mp4Url.toString(), endsWith('original0.mp4'));
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

  test('ALWAYS sends rating=g, on search and on trending', () async {
    // Giphy does not filter by default — omitting this returns unrated content,
    // so an innocent query can surface something no sticker app should show.
    // Asserted on both endpoints because it is easy to add to one and forget
    // the other, and the omission is invisible until it is embarrassing.
    for (final call in <Future<GiphyPage> Function(GiphyClient)>[
      (c) => c.search('puppy'),
      (c) => c.trending(),
    ]) {
      http.Request? captured;
      await call(
        clientReturning(cannedResponse(), onRequest: (req) => captured = req),
      );
      expect(captured!.url.queryParameters['rating'], 'g');
    }
  });

  test('an empty result set yields an empty page', () async {
    final page = await clientReturning(cannedResponse(count: 0)).search('zzz');
    expect(page.gifs, isEmpty);
    expect(page.hasMore, isFalse);
  });

  test('a non-200 response throws GiphyException', () async {
    await expectLater(
      clientReturning('{"meta":{"status":403}}', status: 403).search('x'),
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
    final page = await clientReturning(body).search('x');
    expect(page.gifs, hasLength(1));
    expect(page.gifs.single.id, 'ok');
  });

  group('rate limiting', () {
    test('429 has its own type, because the response is to STOP', () async {
      // Measured against the live API: the limit is a rolling window that
      // retries keep feeding. Polling every 30 s stayed throttled for 8 minutes;
      // going quiet cleared it in 10. A caller that cannot distinguish 429 from
      // a generic failure will retry, and make the outage longer.
      await expectLater(
        clientReturning(
          '{"message":"Too Many Requests"}',
          status: 429,
        ).search('x'),
        throwsA(isA<GiphyRateLimitException>()),
      );
    });

    test('its message tells the user to wait, and never how long', () async {
      // Giphy sends no Retry-After and no X-RateLimit-* headers, on success or
      // failure, so any countdown would be invented.
      const e = GiphyRateLimitException();
      expect(e.message, contains('few minutes'));
      expect(e.message, isNot(matches(RegExp(r'\d+ (second|minute)s? left'))));
    });

    test('it is still a GiphyException, so nothing leaks past a catch', () {
      // Callers that only care "search failed" must not have to know about the
      // subtype in order to handle it at all.
      expect(const GiphyRateLimitException(), isA<GiphyException>());
    });
  });

  group('paging', () {
    test('hasMore is true while results remain', () async {
      final page = await clientReturning(
        cannedResponse(count: 25, totalCount: 500),
      ).search('cat');

      expect(page.hasMore, isTrue);
      expect(page.nextOffset, 25);
    });

    test('hasMore is false at the end of the results', () async {
      final page = await clientReturning(
        cannedResponse(count: 10, totalCount: 35, offset: 25),
      ).search('cat', offset: 25);

      expect(page.nextOffset, 35);
      expect(page.hasMore, isFalse);
    });

    test('a missing total_count stops paging rather than looping', () async {
      // Requests are the scarce resource, and there are no headers warning how
      // close the limit is — so an unknown end means stop, not "keep asking".
      final body = jsonEncode({
        'data': [
          {
            'id': 'a',
            'title': 't',
            'images': {
              'preview_gif': {'url': 'https://x/p.gif'},
              'original': {'mp4': 'https://x/o.mp4'},
            },
          },
        ],
      });

      expect((await clientReturning(body).search('x')).hasMore, isFalse);
    });

    test('offset is passed through to the request', () async {
      http.Request? captured;
      await clientReturning(
        cannedResponse(),
        onRequest: (req) => captured = req,
      ).search('cat', offset: 50);

      expect(captured!.url.queryParameters['offset'], '50');
    });
  });

  test('trending hits its own endpoint, with no query', () async {
    // The picker's opening state. An empty search screen asks the user to guess
    // what the app is good at before showing them anything.
    http.Request? captured;
    final page = await clientReturning(
      cannedResponse(count: 3),
      onRequest: (req) => captured = req,
    ).trending();

    expect(captured!.url.path, '/v1/gifs/trending');
    expect(captured!.url.queryParameters.containsKey('q'), isFalse);
    expect(page.gifs, hasLength(3));
  });

  test('a 200 carrying something that is not JSON is reported, not thrown '
      'as a cast error', () async {
    // The classic mobile case: a captive portal answering 200 with a login
    // page. A raw type error here would surface as a crash rather than a
    // message.
    await expectLater(
      clientReturning('<html>sign in</html>').search('x'),
      throwsA(
        isA<GiphyException>().having(
          (e) => e.message,
          'message',
          contains('could not read'),
        ),
      ),
    );
  });
}
