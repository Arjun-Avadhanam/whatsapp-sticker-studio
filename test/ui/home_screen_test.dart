import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/sources/share_in_source.dart';
import 'package:whatsapp_sticker_studio/ui/home_screen.dart';

import '../app/test_dependencies.dart';

/// Stands in for the OS share channel.
///
/// Subclasses rather than reimplements, so the cold/warm split under test is the
/// real one — `pick()` for what launched the app, `stream()` for what arrives
/// while it runs.
class FakeShareIn extends ShareInSource {
  FakeShareIn({this.cold});

  final MediaHandle? cold;
  final _warm = StreamController<MediaHandle>.broadcast();

  @override
  Future<MediaHandle?> pick() async => cold;

  @override
  Stream<MediaHandle> stream() => _warm.stream;

  /// Simulates a share arriving while the app is already open.
  void shareNow(MediaHandle media) => _warm.add(media);

  Future<void> close() => _warm.close();
}

void main() {
  late AppDependencies deps;

  setUp(() async {
    deps = await testDependencies();
  });
  tearDown(() => deps.dispose());

  Future<void> pump(WidgetTester tester, FakeShareIn share) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(dependencies: deps, shareIn: share),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('starts on Make with all three tabs', (tester) async {
    final share = FakeShareIn();
    addTearDown(share.close);
    await pump(tester, share);

    expect(find.text('Make'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Packs'), findsOneWidget);
    expect(find.text('Pick a photo or clip to begin.'), findsOneWidget);
  });

  testWidgets('a COLD share loads straight into the Maker', (tester) async {
    // The app was launched *by* the share. Nothing else has happened yet, so if
    // this is dropped the user sees an empty Maker and no explanation.
    final share = FakeShareIn(cold: fakeImage());
    addTearDown(share.close);

    await pump(tester, share);

    expect(
      find.text('Pick a photo or clip to begin.'),
      findsNothing,
      reason: 'the shared media should have replaced the empty state',
    );
    expect(find.byKey(const Key('sticker-preview')), findsOneWidget);
  });

  testWidgets('a WARM share arrives while the app is running', (tester) async {
    // The classic mistake is handling only the cold case: a share target is
    // usually already in memory when someone shares to it, so missing this
    // drops the common case silently.
    final share = FakeShareIn();
    addTearDown(share.close);
    await pump(tester, share);
    expect(find.text('Pick a photo or clip to begin.'), findsOneWidget);

    share.shareNow(fakeImage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('sticker-preview')), findsOneWidget);
  });

  testWidgets('a warm share BRINGS THE USER BACK to the Make tab', (
    tester,
  ) async {
    // The whole reason share-in lives on HomeScreen rather than in MakerScreen:
    // a share can arrive on any tab, and loading it somewhere the user cannot
    // see would look like the share vanished.
    final share = FakeShareIn();
    addTearDown(share.close);
    await pump(tester, share);

    await tester.tap(find.text('Packs'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('packs-empty')), findsOneWidget);

    share.shareNow(fakeImage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sticker-preview')), findsOneWidget);
    expect(find.byKey(const Key('packs-empty')), findsNothing);
  });

  testWidgets('no share leaves the Maker empty and waiting', (tester) async {
    // Launching the app normally must not look like a failed share.
    final share = FakeShareIn();
    addTearDown(share.close);

    await pump(tester, share);

    expect(find.text('Pick a photo or clip to begin.'), findsOneWidget);
  });
}
