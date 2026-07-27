import 'package:http/http.dart' as http;

import '../core/media.dart';
import 'extraction_client.dart';
import 'source.dart';

/// A [Source] over a pasted X/Twitter link.
///
/// Two steps: ask the extractor to resolve the tweet's mp4 URL, then download
/// those bytes. Either step failing yields `null` (a friendly Maker message)
/// rather than an exception — extraction of third-party links is inherently
/// unreliable and must degrade gracefully.
class XLinkSource implements Source {
  XLinkSource(this._client, this._http, this._tweetUrl);

  final ExtractionClient _client;
  final http.Client _http;
  final String _tweetUrl;

  @override
  Future<MediaHandle?> pick() async {
    final ExtractedMedia media;
    try {
      media = await _client.extract(_tweetUrl);
    } on ExtractionException {
      return null;
    }

    final resp = await _http.get(media.mp4Url);
    if (resp.statusCode != 200) {
      return null;
    }

    return MediaHandle(
      bytes: resp.bodyBytes,
      kind: media.kind,
      mimeType: 'video/mp4',
    );
  }
}
