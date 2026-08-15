import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/media.dart';
import 'x_link.dart';

/// The media resolved for an X post.
class ExtractedMedia {
  const ExtractedMedia(this.mp4Url, this.kind);

  final Uri mp4Url;
  final MediaKind kind;
}

/// Thrown when a post cannot be resolved (deleted, private, no video, offline).
/// The Maker turns this into a message the user can act on.
class ExtractionException implements Exception {
  ExtractionException(this.message);
  final String message;
  @override
  String toString() => 'ExtractionException: $message';
}

/// Resolves an X post to a direct mp4 URL, **from the phone, with no server**.
///
/// This used to POST to a self-hosted FastAPI + yt-dlp service. That service
/// still exists in `services/extractor/` and still works, but nothing depends on
/// it, because hosting it turned out to be the single thing standing between
/// this app and a shippable v1 — and the requirement it imposed was absurd for
/// a phone app: the device had to be tethered to a specific laptop over USB.
///
/// Instead this calls the endpoint X's own embed widgets use. Verified
/// 2026-08-14 against a real post — it returns the identical mp4 URL yt-dlp
/// resolved:
/// - **No auth, no API key, no cookies.** The `token` parameter is not a
///   credential — it is a hash X's own embed script computes from the post id,
///   carries no secret and gates nothing. See [_token].
/// - A missing post returns **404**; a post with no video returns **200** with
///   no media at all. Those are different messages to the user.
///
/// **⚠️ THE STATUS CODE IS ALWAYS 200 — judge the BODY.** A request X does not
/// like comes back `200 {}`, not an error. That cost two wrong conclusions
/// during development, both from checking the status and never the content, so
/// [_looksLikeAPost] guards it explicitly.
///
/// The responses are also CDN-cached for 60 s, which independently produced a
/// false "the token is optional" result: requests with junk tokens were being
/// served the body an earlier correct request had populated.
///
/// **It also removes the risk that made hosting hard.** Requests now come from
/// the user's own phone — a residential or mobile IP — instead of a datacenter
/// IP, which is where X is most likely to demand authentication.
///
/// The tradeoff, stated plainly: this is an **undocumented endpoint**, and a
/// change to it needs an app update rather than a server redeploy. That
/// advantage was always theoretical here — with nowhere to deploy, a yt-dlp
/// break would have required an app update too.
class ExtractionClient {
  ExtractionClient(this._http, [Uri? baseUri])
    : _baseUri = baseUri ?? Uri.parse('https://cdn.syndication.twimg.com');

  final http.Client _http;
  final Uri _baseUri;

  /// Resolves [post], which may be a full link or a bare post id.
  Future<ExtractedMedia> extract(String post) async {
    final id = XLink.postIdOf(post) ?? post;

    final uri = _baseUri.replace(
      path: '/tweet-result',
      queryParameters: {'id': id, 'token': _token(id), 'lang': 'en'},
    );

    final http.Response resp;
    try {
      resp = await _http.get(uri);
    } catch (_) {
      throw ExtractionException(
        "Couldn't reach X. Check your connection and try again.",
      );
    }

    if (resp.statusCode == 404) {
      throw ExtractionException(
        'That post could not be found. It may have been deleted, or the '
        'account may be private.',
      );
    }
    if (resp.statusCode != 200) {
      throw ExtractionException(
        'X could not be asked about that post right now '
        '(HTTP ${resp.statusCode}). Try again shortly.',
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ExtractionException('X sent a response we could not read.');
    }

    // A `200 {}` is X declining to answer, NOT a post without video. Observed
    // during development: every request — from curl and from Dart alike —
    // returned an empty object for a while, then recovered on its own. Without
    // this guard a user holding a perfectly good video link is told their post
    // has no video in it, which sends them off to fix the wrong thing.
    if (!_looksLikeAPost(json)) {
      throw ExtractionException(
        "X didn't return that post. Try again in a moment.",
      );
    }

    final mp4 = _bestMp4(json);
    if (mp4 == null) {
      // Now this genuinely means what it says: the post came back, and there is
      // no video in it.
      throw ExtractionException('No video or GIF could be found in that post.');
    }

    // Always video: we take the mp4 in every case, including for an
    // `animated_gif` post, where X serves the GIF as a silent H.264 mp4. The
    // old service reported `video` unconditionally for the same reason, so this
    // preserves behaviour that was verified end to end on device.
    return ExtractedMedia(mp4, MediaKind.video);
  }

  /// Whether the payload is a post at all, rather than X's empty brush-off.
  ///
  /// A real response always identifies itself; `{}` identifies nothing.
  bool _looksLikeAPost(Map<String, dynamic> json) =>
      json.containsKey('__typename') || json.containsKey('id_str');

  /// The `token` X's own embed script sends.
  ///
  /// **Not a credential.** It is a pure function of the post id — no account, no
  /// key, no secret, nothing issued and nothing paid for — so it is computed
  /// offline here exactly as the embed does: `(id / 1e6) × π`, rendered in base
  /// 36, with the zeros and the decimal point removed.
  ///
  /// The endpoint only checks that the parameter is **present and non-empty**;
  /// a junk value is accepted just as readily. It is derived properly anyway,
  /// because doing so costs ten lines, is what a genuine embed sends, and means
  /// that if X ever starts validating it we are already correct rather than
  /// newly broken.
  ///
  /// Omitting it entirely is what does not work: that returns `200 {}`.
  static String _token(String id) {
    final n = double.tryParse(id);
    if (n == null) return '0';

    const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
    final value = (n / 1e6) * math.pi;

    var whole = value.floor();
    var out = '';
    if (whole == 0) out = '0';
    while (whole > 0) {
      out = digits[whole % 36] + out;
      whole ~/= 36;
    }

    // Twelve fractional base-36 digits, matching the precision a JS
    // `Number.toString(36)` produces for values of this magnitude.
    var frac = value - value.floorToDouble();
    final buffer = StringBuffer(out);
    for (var i = 0; i < 12; i++) {
      frac *= 36;
      final digit = frac.floor();
      buffer.write(digits[digit]);
      frac -= digit;
    }

    final token = buffer.toString().replaceAll('0', '');
    // Never empty: an empty token is treated exactly like an absent one.
    return token.isEmpty ? '1' : token;
  }

  /// The highest-bitrate mp4 across every media item in the post.
  ///
  /// A GIF post carries a single variant at bitrate 0; a real video post
  /// carries several renditions plus HLS, and the best mp4 is the one worth
  /// downloading — the encoder downscales to 512² anyway, so a better source
  /// only helps.
  Uri? _bestMp4(Map<String, dynamic> json) {
    final variants = <Map<String, dynamic>>[];

    final details = json['mediaDetails'];
    if (details is List) {
      for (final media in details.whereType<Map<String, dynamic>>()) {
        final info = media['video_info'];
        if (info is! Map<String, dynamic>) continue;
        final list = info['variants'];
        if (list is List) {
          variants.addAll(list.whereType<Map<String, dynamic>>());
        }
      }
    }

    final mp4s = variants
        .where((v) => v['content_type'] == 'video/mp4' && v['url'] is String)
        .toList();
    if (mp4s.isEmpty) return null;

    mp4s.sort((a, b) {
      final ba = (a['bitrate'] as num?) ?? 0;
      final bb = (b['bitrate'] as num?) ?? 0;
      return bb.compareTo(ba);
    });
    return Uri.tryParse(mp4s.first['url'] as String);
  }
}
