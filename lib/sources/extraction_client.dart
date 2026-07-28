import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/media.dart';

/// The media our extractor service resolved for a tweet.
class ExtractedMedia {
  const ExtractedMedia(this.mp4Url, this.kind);

  final Uri mp4Url;
  final MediaKind kind;
}

/// Thrown when extraction fails (private/deleted tweet, no video, service down).
/// The Maker turns this into a friendly message and the source degrades to null.
class ExtractionException implements Exception {
  ExtractionException(this.message);
  final String message;
  @override
  String toString() => 'ExtractionException: $message';
}

/// Talks to our self-hosted extractor: POST /extract {url} → {mp4_url, kind}.
class ExtractionClient {
  ExtractionClient(this._http, this._baseUri);

  final http.Client _http;
  final Uri _baseUri;

  Future<ExtractedMedia> extract(String tweetUrl) async {
    final resp = await _http.post(
      _baseUri.replace(path: '/extract'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': tweetUrl}),
    );

    if (resp.statusCode != 200) {
      throw ExtractionException(_errorFrom(resp.body, resp.statusCode));
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return ExtractedMedia(
      Uri.parse(json['mp4_url'] as String),
      _kindFrom(json['kind'] as String?),
    );
  }

  MediaKind _kindFrom(String? kind) =>
      kind == 'gif' ? MediaKind.gif : MediaKind.video;

  /// Pulls the service's `{"detail":{"error":...}}` message out when present,
  /// else falls back to the status code.
  String _errorFrom(String body, int status) {
    try {
      final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
      final msg = (detail as Map<String, dynamic>?)?['error'];
      if (msg is String) return msg;
    } catch (_) {
      // non-JSON body — fall through
    }
    return 'extraction failed (HTTP $status)';
  }
}
