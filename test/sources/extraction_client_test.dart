import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/sources/extraction_client.dart';

/// The shape X's syndication endpoint really returns.
///
/// Checked against the live endpoint 2026-08-14 with a real post, rather than
/// invented — the previous fixture described our own service's response, which
/// no longer exists.
String post({List<Map<String, Object>> variants = const []}) => jsonEncode({
  '__typename': 'Tweet',
  'id_str': '2087646138526802000',
  'mediaDetails': [
    {
      'type': 'animated_gif',
      'media_url_https': 'https://pbs.twimg.com/tweet_video_thumb/x.jpg',
      if (variants.isNotEmpty) 'video_info': {'variants': variants},
    },
  ],
});

const _gifVariant = {
  'bitrate': 0,
  'content_type': 'video/mp4',
  'url': 'https://video.twimg.com/tweet_video/HPjPGOLaQAAFo8i.mp4',
};

ExtractionClient clientReturning(
  String body, {
  int status = 200,
  void Function(http.Request)? onRequest,
}) {
  final mock = MockClient((req) async {
    onRequest?.call(req);
    return http.Response(body, status);
  });
  return ExtractionClient(mock, Uri.parse('https://cdn.syndication.twimg.com'));
}

void main() {
  test('resolves the mp4 out of a real post payload', () async {
    final media = await clientReturning(
      post(variants: [_gifVariant]),
    ).extract('https://x.com/u/status/2087646138526802000');

    expect(media.mp4Url.toString(), endsWith('HPjPGOLaQAAFo8i.mp4'));
    // Always video: we take the mp4 even for an `animated_gif` post, because
    // that is exactly what X serves — a silent H.264 mp4.
    expect(media.kind, MediaKind.video);
  });

  test('asks X directly, by post id', () async {
    http.Request? captured;
    await clientReturning(
      post(variants: [_gifVariant]),
      onRequest: (req) => captured = req,
    ).extract('https://x.com/someone/status/2087646138526802000?s=20&t=abc');

    expect(captured!.method, 'GET');
    expect(captured!.url.host, 'cdn.syndication.twimg.com');
    expect(captured!.url.path, '/tweet-result');
    expect(captured!.url.queryParameters['id'], '2087646138526802000');
    // The username and the share telemetry never travel.
    expect(captured!.url.query, isNot(contains('someone')));
  });

  group('the token', () {
    /// The token the client puts on the wire for [id].
    Future<String?> tokenFor(String id) async {
      http.Request? captured;
      await clientReturning(
        post(variants: [_gifVariant]),
        onRequest: (req) => captured = req,
      ).extract(id);
      return captured!.url.queryParameters['token'];
    }

    test('is always present and never empty', () async {
      // THE thing that actually matters. The endpoint does not validate the
      // token's value — a junk one is accepted — but it does require the
      // parameter to be there and non-empty. Omitting it returns `200 {}`,
      // which the client would otherwise report as "no video in that post".
      for (final id in ['2087646138526802000', '20', '1', '999']) {
        final t = await tokenFor(id);
        expect(t, isNotNull, reason: id);
        expect(t, isNotEmpty, reason: id);
      }
    });

    test('matches what X derives, for known posts', () async {
      // Pinned against the live endpoint 2026-08-14: each of these was the
      // token on a request that came back with a real payload on a cache MISS.
      // The value is not checked today, but deriving it correctly means we are
      // already right if X ever starts checking, instead of newly broken.
      expect(await tokenFor('2087646138526802000'), '2boy5o6d6wewmi');
      expect(await tokenFor('20'), '2xj79n7d8r');
      expect(await tokenFor('1460323737035677698'), '1mjkvbsti2t9');
    });

    test('a non-numeric id still yields a usable token', () async {
      // Nothing should be able to produce an empty token, since that is treated
      // exactly like an absent one.
      expect(await tokenFor('not-a-number'), isNotEmpty);
    });
  });

  test('accepts a bare post id as well as a link', () async {
    // XLinkSource hands over a normalised link, but nothing should break if a
    // caller has already reduced it to an id.
    http.Request? captured;
    await clientReturning(
      post(variants: [_gifVariant]),
      onRequest: (req) => captured = req,
    ).extract('2087646138526802000');

    expect(captured!.url.queryParameters['id'], '2087646138526802000');
  });

  test('picks the highest-bitrate mp4 when a post has several', () async {
    // A GIF post carries one variant at bitrate 0; a real video post carries
    // several renditions. The encoder downscales to 512² regardless, so the
    // best source only helps. This path is unexercised on live data — every
    // real post tested so far has been a GIF.
    final media = await clientReturning(
      post(
        variants: [
          {
            'bitrate': 632000,
            'content_type': 'video/mp4',
            'url': 'https://v/low.mp4',
          },
          {
            'bitrate': 2176000,
            'content_type': 'video/mp4',
            'url': 'https://v/high.mp4',
          },
          {
            'bitrate': 950000,
            'content_type': 'video/mp4',
            'url': 'https://v/mid.mp4',
          },
        ],
      ),
    ).extract('2087646138526802000');

    expect(media.mp4Url.toString(), 'https://v/high.mp4');
  });

  test('ignores HLS and anything that is not an mp4', () async {
    // Real video posts list an m3u8 alongside the mp4s. ffmpeg would struggle
    // with a playlist here, and there is no reason to take one.
    final media = await clientReturning(
      post(
        variants: [
          {'content_type': 'application/x-mpegURL', 'url': 'https://v/p.m3u8'},
          _gifVariant,
        ],
      ),
    ).extract('2087646138526802000');

    expect(media.mp4Url.toString(), endsWith('.mp4'));
  });

  group('failures say which one it was', () {
    test('a post with no video is distinct from a broken link', () async {
      // By far the most common failure, and the one worth wording well: the
      // link is fine and the post exists, it simply has no video in it.
      await expectLater(
        clientReturning(jsonEncode({'__typename': 'Tweet'})).extract('1'),
        throwsA(
          isA<ExtractionException>().having(
            (e) => e.message,
            'message',
            contains('No video or GIF'),
          ),
        ),
      );
    });

    test('an empty {} is X declining, NOT a post without video', () async {
      // Observed during development: every request, from curl and Dart alike,
      // returned `200 {}` for a while and then recovered on its own. Conflating
      // that with "this post has no video" sends a user holding a perfectly
      // good link off to fix the wrong thing.
      await expectLater(
        clientReturning('{}').extract('2087646138526802000'),
        throwsA(
          isA<ExtractionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Try again'), isNot(contains('No video'))),
          ),
        ),
      );
    });

    test('404 means deleted or private, and says so', () async {
      await expectLater(
        clientReturning('', status: 404).extract('1'),
        throwsA(
          isA<ExtractionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('deleted'), contains('private')),
          ),
        ),
      );
    });

    test('any other status is reported with its code', () async {
      await expectLater(
        clientReturning('', status: 503).extract('1'),
        throwsA(
          isA<ExtractionException>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });

    test('a network error reads as a connection problem', () async {
      final mock = MockClient((req) async => throw const _Offline());

      await expectLater(
        ExtractionClient(mock).extract('1'),
        throwsA(
          isA<ExtractionException>().having(
            (e) => e.message,
            'message',
            contains('connection'),
          ),
        ),
      );
    });

    test('a 200 carrying something that is not JSON does not crash', () async {
      // A captive portal answering 200 with a login page — the classic mobile
      // case. A raw cast error here would surface as a crash, not a message.
      await expectLater(
        clientReturning('<html>sign in</html>').extract('1'),
        throwsA(isA<ExtractionException>()),
      );
    });
  });
}

/// Stands in for a socket failure without depending on `dart:io`'s exact type.
class _Offline implements Exception {
  const _Offline();
}
