import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/sources/extraction_client.dart';
import 'package:whatsapp_sticker_studio/sources/source.dart';
import 'package:whatsapp_sticker_studio/sources/xlink_source.dart';

/// Stub client whose extract() either returns fixed media or throws.
class StubExtractionClient implements ExtractionClient {
  StubExtractionClient({this.result, this.error});

  final ExtractedMedia? result;
  final Object? error;

  /// What the source actually asked for — the assertion that the link was
  /// normalised before it left the app.
  String? asked;

  @override
  Future<ExtractedMedia> extract(String tweetUrl) async {
    asked = tweetUrl;
    if (error != null) throw error!;
    return result!;
  }
}

final _media = ExtractedMedia(
  Uri.parse('https://video.twimg.com/x.mp4'),
  MediaKind.video,
);

/// A client that must never be called.
http.Client get _unusedHttp =>
    MockClient((req) async => fail('no request should have been made'));

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

  test('the link is normalised before it leaves the app', () async {
    // The username and the `?s=&t=` share telemetry are stripped here rather
    // than server-side, so they never travel at all.
    final client = StubExtractionClient(result: _media);
    await XLinkSource(
      client,
      MockClient((req) async => http.Response.bytes(Uint8List(0), 200)),
      'https://twitter.com/someone/status/2087646138526802000?s=20&t=abc',
    ).pick();

    expect(client.asked, 'https://x.com/i/status/2087646138526802000');
  });

  group('failures are reported, never silent', () {
    // Returning null used to be the answer to all of these, and the Maker reads
    // null as "the user cancelled" — so a dead network, a private post and a
    // post with no video were each an inert screen with no explanation.

    test('text that is not a post link never reaches the service', () async {
      // The stub would throw on use; _unusedHttp fails the test on a request.
      // Both prove the round trip did not happen.
      await expectLater(
        XLinkSource(
          StubExtractionClient(),
          _unusedHttp,
          'look at this funny video',
        ).pick(),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            contains('x.com/someone/status'),
          ),
        ),
      );
    });

    test("the service's own wording is passed through verbatim", () async {
      // It distinguishes "no video in this post" from "post not found" from an
      // outage, and we cannot. Paraphrasing destroys the only diagnostic.
      await expectLater(
        XLinkSource(
          StubExtractionClient(
            error: ExtractionException('No video could be found in this tweet'),
          ),
          _unusedHttp,
          'https://x.com/u/status/1',
        ).pick(),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            'No video could be found in this tweet',
          ),
        ),
      );
    });

    test('an unreachable service reads as a connection problem', () async {
      // No response means no message to relay, so a generic one is the honest
      // option — and it names the thing the user can actually check.
      await expectLater(
        XLinkSource(
          StubExtractionClient(error: const SocketExceptionLike()),
          _unusedHttp,
          'https://x.com/u/status/1',
        ).pick(),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            contains('connection'),
          ),
        ),
      );
    });

    test('a failed download is distinct from a failed lookup', () async {
      // The post was found and its media URL handed over, then X refused to
      // serve it — usually an expired URL, so "try again" genuinely helps.
      await expectLater(
        XLinkSource(
          StubExtractionClient(result: _media),
          MockClient((req) async => http.Response('nope', 404)),
          'https://x.com/u/status/1',
        ).pick(),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            allOf(contains('404'), contains('Try again')),
          ),
        ),
      );
    });

    test(
      'a download that throws does not escape as a raw socket error',
      () async {
        await expectLater(
          XLinkSource(
            StubExtractionClient(result: _media),
            MockClient((req) async => throw const SocketExceptionLike()),
            'https://x.com/u/status/1',
          ).pick(),
          throwsA(isA<SourceException>()),
        );
      },
    );
  });
}

/// Stands in for a network error without depending on `dart:io`'s exact type —
/// the source catches anything, which is the behaviour under test.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
