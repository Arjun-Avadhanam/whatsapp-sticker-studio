/// Recognises and normalises an X/Twitter post link.
///
/// Exists so a pasted string is judged **before** it costs a network round trip.
/// Extraction is the slowest and least reliable thing the app does, and a user
/// who pastes the wrong thing — a profile, a search, a YouTube link, half a
/// sentence — should be told immediately rather than after a spinner and a
/// service error that reads like our fault.
///
/// It is deliberately a *recogniser*, not a validator of existence: whether the
/// post is public, still there, or has a video at all can only be answered by
/// the extractor. This rules out the cases that are wrong on their face.
class XLink {
  /// The hosts X has used and still redirects. `twitter.com` links are all over
  /// old messages and bookmarks, so refusing them would look like a bug.
  static const _hosts = {
    'x.com',
    'twitter.com',
    'fxtwitter.com',
    'vxtwitter.com',
  };

  /// Subdomains that are the same site. Stripped rather than enumerated into
  /// [_hosts] so `mobile.twitter.com` and `www.x.com` need no separate entries.
  static const _prefixes = {'www.', 'mobile.', 'm.'};

  /// The post id if [input] is an X post link, else null.
  ///
  /// Accepts what people actually paste: with or without a scheme, either host,
  /// the `/i/status/` form the share sheet produces, the legacy `/statuses/`
  /// form, and trailing `/photo/1` or `?s=20&t=…` tracking junk.
  static String? postIdOf(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // A bare `x.com/…` paste has no scheme, and Uri.parse would read the host
    // as a relative path. Adding one is what makes the common paste work.
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';

    final uri = Uri.tryParse(withScheme);
    if (uri == null) return null;

    var host = uri.host.toLowerCase();
    for (final prefix in _prefixes) {
      if (host.startsWith(prefix)) host = host.substring(prefix.length);
    }
    if (!_hosts.contains(host)) return null;

    // Scan for the segment rather than fixing an index: the username sits before
    // it on a normal link, `i` sits there on a shared one, and neither position
    // is stable.
    final segments = uri.pathSegments;
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i] != 'status' && segments[i] != 'statuses') continue;

      final id = segments[i + 1];
      // Ids are numeric and long. Checking that rejects `/status/photo`, which
      // would otherwise sail through as a "valid" link.
      if (id.isNotEmpty && int.tryParse(id) != null) return id;
    }
    return null;
  }

  /// True if [input] looks like an X post link.
  static bool isPostLink(String input) => postIdOf(input) != null;

  /// [input] reduced to a canonical link, or null if it is not one.
  ///
  /// Normalising to `/i/status/<id>` throws away the username and every query
  /// parameter. X resolves a post by id alone, so nothing is lost — and the
  /// parameters are share-tracking noise (`?s=20&t=…`) that has no business
  /// being sent to our service.
  static String? normalise(String input) {
    final id = postIdOf(input);
    return id == null ? null : 'https://x.com/i/status/$id';
  }
}
