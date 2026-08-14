import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/sources/x_link.dart';

void main() {
  group('accepts what people actually paste', () {
    // Each of these is a real shape a link arrives in. The share sheet, the
    // desktop address bar, the copy-link menu and an old bookmark all differ,
    // and a user has no idea which one they hold.
    const accepted = {
      'the share-sheet form': 'https://x.com/i/status/2087646138526802000',
      'a normal post link': 'https://x.com/someone/status/2087646138526802000',
      'the old host': 'https://twitter.com/someone/status/2087646138526802000',
      'a mobile link':
          'https://mobile.twitter.com/a/status/2087646138526802000',
      'with www': 'https://www.x.com/a/status/2087646138526802000',
      'no scheme at all': 'x.com/a/status/2087646138526802000',
      'share tracking junk':
          'https://x.com/a/status/2087646138526802000?s=20&t=Xy',
      'a link to one photo in the post':
          'https://x.com/a/status/2087646138526802000/photo/1',
      'the legacy /statuses/ form':
          'https://twitter.com/a/statuses/2087646138526802000',
      'surrounding whitespace':
          '  https://x.com/i/status/2087646138526802000\n',
    };

    accepted.forEach((description, link) {
      test(description, () {
        expect(XLink.postIdOf(link), '2087646138526802000');
      });
    });
  });

  group('rejects, so gibberish never reaches the service', () {
    // Extraction is the slowest, least reliable thing the app does. Everything
    // here can be judged for free, and each one would otherwise cost a round
    // trip and return an error that reads like our bug rather than their paste.
    const rejected = {
      'empty': '',
      'only whitespace': '   ',
      'plain words': 'look at this funny video',
      'a profile, not a post': 'https://x.com/someone',
      'a search': 'https://x.com/search?q=cats',
      'the home timeline': 'https://x.com/home',
      'another site entirely': 'https://youtube.com/watch?v=abc',
      'a host that merely contains x.com':
          'https://x.com.evil.example/a/status/123',
      'status with no id': 'https://x.com/a/status/',
      'a non-numeric id': 'https://x.com/a/status/photo',
      // t.co cannot be judged without resolving it, and guessing would send
      // arbitrary shortened links to the extractor.
      'a t.co shortlink': 'https://t.co/abcdef',
    };

    rejected.forEach((description, link) {
      test(description, () {
        expect(XLink.postIdOf(link), isNull, reason: link);
        expect(XLink.isPostLink(link), isFalse);
      });
    });
  });

  test('normalising strips the username and the tracking parameters', () {
    // What we send the extractor should carry the post id and nothing else. The
    // username is redundant (X resolves by id) and `?s=&t=` is share telemetry
    // that has no business leaving the phone.
    expect(
      XLink.normalise(
        'https://x.com/someone/status/2087646138526802000?s=20&t=Q',
      ),
      'https://x.com/i/status/2087646138526802000',
    );
  });

  test('normalising a non-link is null, not a mangled string', () {
    expect(XLink.normalise('hello'), isNull);
  });
}
