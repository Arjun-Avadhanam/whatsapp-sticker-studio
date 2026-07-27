import 'dart:convert';

import 'package:http/http.dart' as http;

/// One search result: a preview to show in the picker and the mp4 the encoder
/// will actually consume.
class GiphyGif {
  const GiphyGif({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.mp4Url,
  });

  final String id;
  final String title;
  final Uri previewUrl;
  final Uri mp4Url;
}

/// Thrown when Giphy returns a non-200 (rate limit, bad key, outage). The Maker
/// turns this into a friendly message; the app degrades to other sources.
class GiphyException implements Exception {
  const GiphyException(this.message);
  final String message;
  @override
  String toString() => 'GiphyException: $message';
}

/// Thin client over Giphy's free search API. Injected [http.Client] so tests run
/// against a mock with no network.
class GiphyClient {
  GiphyClient(this._http, {required this.apiKey, Uri? baseUri})
    : _baseUri = baseUri ?? Uri.parse('https://api.giphy.com');

  final http.Client _http;
  final String apiKey;
  final Uri _baseUri;

  Future<List<GiphyGif>> search(String query, {int limit = 25}) async {
    final uri = _baseUri.replace(
      path: '/v1/gifs/search',
      queryParameters: {'api_key': apiKey, 'q': query, 'limit': '$limit'},
    );

    final resp = await _http.get(uri);
    if (resp.statusCode != 200) {
      throw GiphyException('Giphy search failed (HTTP ${resp.statusCode})');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = (json['data'] as List?) ?? const [];
    return data
        .cast<Map<String, dynamic>>()
        .map(_parse)
        .whereType<GiphyGif>()
        .toList();
  }

  /// Returns null for a result missing the URLs we need, so one malformed entry
  /// is skipped rather than failing the whole search.
  GiphyGif? _parse(Map<String, dynamic> m) {
    final images = m['images'] as Map<String, dynamic>?;
    if (images == null) return null;

    final preview = _url(images['preview_gif']) ?? _url(images['fixed_width']);
    final mp4 =
        (images['original'] as Map<String, dynamic>?)?['mp4'] as String?;
    if (preview == null || mp4 == null) return null;

    return GiphyGif(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      previewUrl: Uri.parse(preview),
      mp4Url: Uri.parse(mp4),
    );
  }

  String? _url(Object? imageNode) =>
      (imageNode as Map<String, dynamic>?)?['url'] as String?;
}
