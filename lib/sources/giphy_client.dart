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

/// A page of results, plus whether asking for more is worthwhile.
///
/// [hasMore] is computed here rather than guessed at the call site: Giphy
/// reports a `total_count`, and a picker that keeps requesting past the end
/// spends requests against a rate limit that has no headers to warn us with.
class GiphyPage {
  const GiphyPage({
    required this.gifs,
    required this.offset,
    required this.totalCount,
  });

  final List<GiphyGif> gifs;
  final int offset;
  final int totalCount;

  /// Where the next page starts.
  int get nextOffset => offset + gifs.length;

  bool get hasMore => gifs.isNotEmpty && nextOffset < totalCount;
}

/// Thrown when Giphy returns a non-200 (bad key, outage, malformed response).
class GiphyException implements Exception {
  const GiphyException(this.message);
  final String message;
  @override
  String toString() => 'GiphyException: $message';
}

/// Thrown on HTTP 429. **Its own type because the correct response is to STOP.**
///
/// Measured against the live API 2026-08-14: the limit is a rolling window that
/// retries keep feeding. Probing every 30 s stayed throttled for 8 solid
/// minutes, while going completely quiet cleared it in 10. So retry-on-failure —
/// the instinctive thing to write — makes the outage strictly longer.
///
/// Giphy sends **no** `Retry-After` and no `X-RateLimit-*` headers, on success or
/// failure, so there is no countdown to show and none to compute. Back off,
/// tell the user to try again in a few minutes, and do not schedule a retry.
class GiphyRateLimitException extends GiphyException {
  const GiphyRateLimitException()
    : super('Giphy is busy right now. Try again in a few minutes.');
}

/// Thin client over Giphy's free API. Injected [http.Client] so tests run
/// against a mock with no network.
class GiphyClient {
  GiphyClient(this._http, {required this.apiKey, Uri? baseUri})
    : _baseUri = baseUri ?? Uri.parse('https://api.giphy.com');

  final http.Client _http;
  final String apiKey;
  final Uri _baseUri;

  /// Content rating ceiling.
  ///
  /// **Giphy does not filter by default** — omitting this returns unrated
  /// content, so an innocent query can surface something no sticker app should
  /// show. `g` is the only defensible default here; it is not a preference.
  static const rating = 'g';

  /// Searches for [query].
  ///
  /// [offset] pages through results; feed it [GiphyPage.nextOffset].
  Future<GiphyPage> search(String query, {int limit = 25, int offset = 0}) =>
      _fetch('/v1/gifs/search', {
        'q': query,
        'limit': '$limit',
        'offset': '$offset',
      }, offset);

  /// What is popular right now, for the picker's opening state.
  ///
  /// An empty search screen is a dead end — it asks the user to guess what the
  /// app is good at before showing them anything.
  Future<GiphyPage> trending({int limit = 25, int offset = 0}) => _fetch(
    '/v1/gifs/trending',
    {'limit': '$limit', 'offset': '$offset'},
    offset,
  );

  Future<GiphyPage> _fetch(
    String path,
    Map<String, String> params,
    int offset,
  ) async {
    final uri = _baseUri.replace(
      path: path,
      queryParameters: {'api_key': apiKey, 'rating': rating, ...params},
    );

    final resp = await _http.get(uri);
    if (resp.statusCode == 429) throw const GiphyRateLimitException();
    if (resp.statusCode != 200) {
      throw GiphyException('Giphy search failed (HTTP ${resp.statusCode})');
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      // A 200 carrying something that is not the expected object — a captive
      // portal's login page is the classic one on mobile.
      throw const GiphyException('Giphy sent a response we could not read.');
    }

    final data = (json['data'] as List?) ?? const [];
    final pagination = json['pagination'] as Map<String, dynamic>?;

    return GiphyPage(
      gifs: data
          .cast<Map<String, dynamic>>()
          .map(_parse)
          .whereType<GiphyGif>()
          .toList(),
      offset: offset,
      // Absent total_count means "do not ask for more" rather than "ask
      // forever": requests are the scarce resource here.
      totalCount: (pagination?['total_count'] as int?) ?? 0,
    );
  }

  /// Returns null for a result missing the URLs we need, so one malformed entry
  /// is skipped rather than failing the whole search.
  GiphyGif? _parse(Map<String, dynamic> m) {
    final images = m['images'] as Map<String, dynamic>?;
    final id = m['id'] as String?;
    if (images == null || id == null) return null;

    final preview = _url(images['preview_gif']) ?? _url(images['fixed_width']);
    // `original`, not a fixed-width variant: it is typically 480×480 on real
    // data, and anything smaller would be upscaled further to reach our 512².
    final mp4 =
        (images['original'] as Map<String, dynamic>?)?['mp4'] as String?;
    if (preview == null || mp4 == null) return null;

    return GiphyGif(
      id: id,
      title: (m['title'] as String?) ?? '',
      previewUrl: Uri.parse(preview),
      mp4Url: Uri.parse(mp4),
    );
  }

  String? _url(Object? imageNode) =>
      (imageNode as Map<String, dynamic>?)?['url'] as String?;
}
