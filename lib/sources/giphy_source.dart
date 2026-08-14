import 'package:http/http.dart' as http;

import '../core/media.dart';
import 'giphy_client.dart';
import 'source.dart';

/// A [Source] over a gif the user already chose from Giphy search.
///
/// Holds the chosen [GiphyGif] so [pick] stays argument-free, matching the
/// interface. Its only job is to download the mp4 and wrap it — all processing
/// happens later in the Encoder.
///
/// Failures throw [SourceException]. Returning `null` — which is what this did
/// before — means "the user cancelled" to the Maker, so a dead connection or a
/// dropped CDN response left the screen inert with no explanation, exactly the
/// bug fixed for X links.
class GiphySource implements Source {
  GiphySource(this._gif, this._http);

  final GiphyGif _gif;
  final http.Client _http;

  @override
  Future<MediaHandle?> pick() async {
    final http.Response resp;
    try {
      resp = await _http.get(_gif.mp4Url);
    } catch (_) {
      throw const SourceException(
        "Couldn't download that GIF. Check your connection and try again.",
      );
    }

    if (resp.statusCode != 200) {
      throw SourceException(
        "That GIF couldn't be downloaded (HTTP ${resp.statusCode}). "
        'Try another one.',
      );
    }

    return MediaHandle(
      bytes: resp.bodyBytes,
      // The mp4 variant, not the .gif — verified on real data 2026-08-14 to be
      // H.264 with no audio track, the same shape the X extractor yields.
      kind: MediaKind.video,
      mimeType: 'video/mp4',
    );
  }
}
