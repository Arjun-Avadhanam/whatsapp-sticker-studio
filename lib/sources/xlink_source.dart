import 'package:http/http.dart' as http;

import '../core/media.dart';
import 'extraction_client.dart';
import 'source.dart';
import 'x_link.dart';

/// A [Source] over a pasted X/Twitter link.
///
/// Three steps: check the link is even a post link, ask the extractor to resolve
/// its mp4 URL, then download those bytes.
///
/// Every failure throws [SourceException] carrying a message meant for the user.
/// It used to return `null`, which the Maker treats as a cancel — so a dead
/// network, a private post and a post with no video were all a silent no-op,
/// and the only feedback was that nothing happened.
class XLinkSource implements Source {
  XLinkSource(this._client, this._http, this._tweetUrl);

  final ExtractionClient _client;
  final http.Client _http;
  final String _tweetUrl;

  @override
  Future<MediaHandle?> pick() async {
    // Judged locally and for free. Sending a profile link or a sentence to the
    // extractor costs a round trip to be told what we already knew.
    final normalised = XLink.normalise(_tweetUrl);
    if (normalised == null) {
      throw const SourceException(
        "That doesn't look like an X post link. It should look like "
        'x.com/someone/status/1234567890.',
      );
    }

    final ExtractedMedia media;
    try {
      media = await _client.extract(normalised);
    } on ExtractionException catch (e) {
      // The service's wording, verbatim — it distinguishes "no video in this
      // post" from "post not found" from an outage, and we cannot.
      throw SourceException(e.message);
    } catch (_) {
      // Anything else reaching here is the network, not the service: a timeout,
      // no connectivity, DNS. The service never answered, so there is no
      // message to pass on and a generic one is the honest option.
      throw const SourceException(
        "Couldn't reach the link service. Check your connection and try again.",
      );
    }

    final http.Response resp;
    try {
      resp = await _http.get(media.mp4Url);
    } catch (_) {
      throw const SourceException(
        "Couldn't download the video. Check your connection and try again.",
      );
    }
    if (resp.statusCode != 200) {
      // Distinct from the resolve failure above: the post was found and the
      // media URL handed over, then X refused to serve it. Usually an expired
      // URL, so retrying genuinely helps.
      throw SourceException(
        'That post was found, but its video could not be downloaded '
        '(HTTP ${resp.statusCode}). Try again.',
      );
    }

    return MediaHandle(
      bytes: resp.bodyBytes,
      kind: media.kind,
      mimeType: 'video/mp4',
    );
  }
}
