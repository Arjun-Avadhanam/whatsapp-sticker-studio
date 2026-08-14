import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/sources/giphy_client.dart';
import 'package:whatsapp_sticker_studio/ui/giphy_picker_screen.dart';

/// Records what was asked for and answers with whatever the test wants.
///
/// A real [GiphyClient] over a MockClient rather than a fake client, so the
/// screen is exercised against the actual parsing, paging and 429 handling —
/// the things D.1 just built.
class FakeApi {
  FakeApi();

  final requests = <Uri>[];

  /// Answers for the next call. Default: 6 gifs and more available.
  int status = 200;
  int count = 6;
  int totalCount = 500;

  /// Held open to force two requests to overlap.
  Completer<void>? gate;

  /// Distinguishes one response from another in assertions.
  String idPrefix = 'a';

  GiphyClient get client => GiphyClient(
    MockClient((req) async {
      requests.add(req.url);
      // Snapshot the answer BEFORE waiting. Building it afterwards means a
      // held-open request picks up whatever the test set for the *next* one, so
      // a "stale" reply arrives carrying fresh data and the staleness test
      // passes without ever exercising the race.
      final prefix = idPrefix;
      final thisStatus = status;
      final thisCount = count;
      final thisTotal = totalCount;

      final g = gate;
      if (g != null) await g.future;
      if (thisStatus != 200) return http.Response('{"m":"no"}', thisStatus);

      final offset =
          int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0;
      return http.Response(
        jsonEncode({
          'data': List.generate(
            thisCount,
            (i) => {
              'id': '$prefix${offset + i}',
              'title': 'gif $prefix${offset + i}',
              'images': {
                'preview_gif': {'url': 'https://x/p${offset + i}.gif'},
                'original': {'mp4': 'https://x/o${offset + i}.mp4'},
              },
            },
          ),
          'pagination': {'total_count': thisTotal, 'offset': offset},
        }),
        200,
      );
    }),
    apiKey: 'k',
  );
}

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  /// Pumps the picker and lets its opening load settle.
  ///
  /// Never `pumpAndSettle` here — an indeterminate CircularProgressIndicator
  /// schedules frames forever, so settling only ends at the 10-minute timeout.
  Future<GiphyGif?> pump(WidgetTester tester) async {
    GiphyGif? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              child: const Text('open'),
              onPressed: () async {
                chosen = await showGiphyPicker(
                  context: context,
                  client: api.client,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return chosen;
  }

  /// Types [q] and lets the debounce elapse.
  Future<void> search(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const Key('giphy-search')), q);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('opens on trending, with no query', (tester) async {
    // An empty search screen is a dead end: it asks the user to guess what the
    // app is good at before showing them anything.
    await pump(tester);

    expect(api.requests, hasLength(1));
    expect(api.requests.single.path, '/v1/gifs/trending');
    expect(api.requests.single.queryParameters.containsKey('q'), isFalse);
    expect(find.byKey(const Key('giphy-grid')), findsOneWidget);
  });

  testWidgets('rapid typing issues ONE search, not one per keystroke', (
    tester,
  ) async {
    // Requests are the scarce resource here — the rate limit has no headers to
    // warn how close it is, so spending one per keystroke is a real cost.
    await pump(tester);
    api.requests.clear();

    for (final q in ['c', 'ca', 'cat', 'cats']) {
      await tester.enterText(find.byKey(const Key('giphy-search')), q);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(seconds: 1));

    expect(api.requests, hasLength(1));
    expect(api.requests.single.queryParameters['q'], 'cats');
  });

  testWidgets('a slow earlier search cannot overwrite a later one', (
    tester,
  ) async {
    // Debouncing reduces overlap but does not remove it: a slow query can still
    // be in flight when the next resolves. The same guard was proven
    // load-bearing on the Library.
    //
    // Note what this asserts and why. A reset clears the list when the request
    // STARTS, so a late stale reply does not replace the fresh results — it
    // APPENDS to them. Checking the first item therefore passes with the guard
    // removed; the only honest assertion is that no stale item appears at all.
    // Kept small so every tile is built: the grid is lazy, and an unbuilt stale
    // tile would be indistinguishable from a rejected one.
    api.count = 3;
    await pump(tester);

    final held = Completer<void>();
    api.gate = held;
    api.idPrefix = 'stale';
    await search(tester, 'first');

    api.gate = null;
    api.idPrefix = 'fresh';
    await search(tester, 'second');
    expect(find.byKey(const Key('giphy-gif-fresh0')), findsOneWidget);

    held.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const Key('giphy-gif-stale0')),
      findsNothing,
      reason:
          'the superseded search must not add its results to the newer ones',
    );
    expect(find.byKey(const Key('giphy-gif-fresh0')), findsOneWidget);
  });

  testWidgets('a search matching nothing says so, and not as a failure', (
    tester,
  ) async {
    await pump(tester);
    api.count = 0;
    api.totalCount = 0;

    await search(tester, 'zzzznothing');

    expect(find.byKey(const Key('giphy-no-results')), findsOneWidget);
    // Scoped to the empty state: the search field holds the same text, so an
    // unscoped finder matches twice and proves nothing about the message.
    expect(
      find.descendant(
        of: find.byKey(const Key('giphy-no-results')),
        matching: find.textContaining('zzzznothing'),
      ),
      findsOneWidget,
    );
    // Conflating these tells a user their connection is broken when their
    // spelling is.
    expect(find.byKey(const Key('giphy-error')), findsNothing);
  });

  testWidgets('a failure offers a retry', (tester) async {
    await pump(tester);
    api.status = 500;

    await search(tester, 'cat');

    expect(find.byKey(const Key('giphy-error')), findsOneWidget);
    expect(find.byKey(const Key('giphy-retry')), findsOneWidget);

    // And the retry actually re-requests.
    api.status = 200;
    api.requests.clear();
    await tester.tap(find.byKey(const Key('giphy-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.requests, hasLength(1));
    expect(find.byKey(const Key('giphy-grid')), findsOneWidget);
  });

  testWidgets('a RATE LIMIT shows the wait, and offers NO retry', (
    tester,
  ) async {
    // The measured reason: the limit is a rolling window that further requests
    // keep feeding. Polling every 30 s stayed throttled for 8 minutes while
    // going quiet cleared it in 10. A retry button here would let the user
    // extend their own outage while being told to wait.
    await pump(tester);
    api.status = 429;

    await search(tester, 'cat');

    expect(find.byKey(const Key('giphy-error')), findsOneWidget);
    expect(find.textContaining('few minutes'), findsOneWidget);
    expect(
      find.byKey(const Key('giphy-retry')),
      findsNothing,
      reason: 'retrying while throttled makes the outage longer',
    );
  });

  testWidgets('tapping a gif returns it and closes the picker', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('giphy-gif-a0')));
    // Settling is safe here and a fixed pump is not: closing runs a route
    // transition, and 400 ms lands mid-animation with the old route still up.
    // Nothing indeterminate is on screen by this point.
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('giphy-grid')), findsNothing);
    expect(find.text('open'), findsOneWidget); // back on the caller
  });

  testWidgets('scrolling to the bottom appends the next page', (tester) async {
    // Enough to overflow the viewport: six gifs is two rows in a three-column
    // grid, which fits, so nothing scrolls and load-more could never fire.
    api.count = 30;
    // Exactly two pages, so no third load-more can fire and shift what sits at
    // the bottom of the list mid-assertion.
    api.totalCount = 60;
    await pump(tester);
    api.requests.clear();

    // Note the assertions below count REQUESTS and look up specific ids, not
    // built widgets. GridView.builder is lazy, so the number of tiles in the
    // tree reflects the viewport, never how much data has been loaded.
    expect(find.byKey(const Key('giphy-gif-a0')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('giphy-grid')),
      const Offset(0, -2000),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.requests, hasLength(1));
    expect(api.requests.single.queryParameters['offset'], '30');

    // Scroll to the very end. The last id belongs to page 2, so finding it
    // proves page 2 was appended rather than replacing page 1 — and it is the
    // one position that is stable, since a lazy grid only builds the rows it
    // is actually showing.
    await tester.drag(
      find.byKey(const Key('giphy-grid')),
      const Offset(0, -6000),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('giphy-gif-a59')), findsOneWidget);
    expect(api.requests, hasLength(1), reason: 'no third page exists to fetch');
  });

  testWidgets('paging stops at the end of the results', (tester) async {
    // Requests are scarce and unmonitorable, so asking past the end is a real
    // waste rather than a harmless no-op.
    api.count = 30;
    api.totalCount = 30; // one page and that is all
    await pump(tester);
    api.requests.clear();

    await tester.drag(
      find.byKey(const Key('giphy-grid')),
      const Offset(0, -2000),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.requests, isEmpty);
  });

  testWidgets('clearing the query goes back to trending', (tester) async {
    await pump(tester);
    await search(tester, 'cat');
    expect(api.requests.last.path, '/v1/gifs/search');

    await tester.tap(find.byKey(const Key('giphy-clear')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.requests.last.path, '/v1/gifs/trending');
  });

  testWidgets('the GIPHY attribution is always on screen', (tester) async {
    // Required by Giphy's API terms — not decoration, and not optional. Pinned
    // across states so a later layout change cannot quietly drop it.
    await pump(tester);
    expect(find.byKey(const Key('giphy-attribution')), findsOneWidget);

    api.status = 500;
    await search(tester, 'cat');
    expect(find.byKey(const Key('giphy-attribution')), findsOneWidget);
  });

  testWidgets('every request carries rating=g', (tester) async {
    // The screen must not be able to opt out of the content filter, whichever
    // endpoint it happens to be calling.
    await pump(tester);
    await search(tester, 'cat');

    expect(api.requests, isNotEmpty);
    for (final r in api.requests) {
      expect(r.queryParameters['rating'], 'g', reason: '$r');
    }
  });
}
