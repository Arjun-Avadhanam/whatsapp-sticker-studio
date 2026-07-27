import 'package:http/http.dart' as http;

import '../core/media.dart';
import 'giphy_client.dart';
import 'source.dart';

/// A [Source] over a gif the user already chose from Giphy search.
///
/// Holds the chosen [GiphyGif] so [pick] stays argument-free, matching the
/// interface. Its only job is to download the mp4 and wrap it — all processing
/// happens later in the Encoder.
class GiphySource implements Source {
  GiphySource(this._gif, this._http);

  final GiphyGif _gif;
  final http.Client _http;

  @override
  Future<MediaHandle?> pick() async {
    final resp = await _http.get(_gif.mp4Url);
    // A failed download is recoverable — return null so the Maker can retry.
    if (resp.statusCode != 200) {
      return null;
    }

    return MediaHandle(
      bytes: resp.bodyBytes,
      kind: MediaKind.video, // we take the mp4 variant, not the gif
      mimeType: 'video/mp4',
    );
  }
}
