import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/ui/x_link_button.dart';

void main() {
  /// Pumps the button and records whatever link it hands back.
  Future<List<String>> pumpButton(WidgetTester tester) async {
    final links = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(floatingActionButton: XLinkButton(onLink: links.add)),
      ),
    );
    return links;
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('x-link-button')));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('x-link-field')), text);
    await tester.pump();
  }

  testWidgets('the dialog asks for a link, in those words', (tester) async {
    await pumpButton(tester);
    await openDialog(tester);

    expect(find.text('Enter X link here'), findsOneWidget);
    // The wait is set up front. Extraction is a network round trip and then a
    // video encode — 15-20 s on a real clip — and a screen that says nothing
    // about that reads as frozen.
    expect(find.textContaining('a few seconds'), findsOneWidget);
  });

  testWidgets('submit is disabled until the text is actually a post link', (
    tester,
  ) async {
    await pumpButton(tester);
    await openDialog(tester);

    FilledButton submit() =>
        tester.widget<FilledButton>(find.byKey(const Key('x-link-submit')));

    expect(submit().onPressed, isNull, reason: 'empty field');

    await type(tester, 'https://x.com/someone');
    expect(submit().onPressed, isNull, reason: 'a profile is not a post');

    await type(tester, 'https://x.com/someone/status/2087646138526802000');
    expect(submit().onPressed, isNotNull);
  });

  testWidgets('a valid link comes back normalised, not raw', (tester) async {
    // What leaves the dialog is what gets sent to our service, so the tracking
    // parameters must be gone by this point rather than later.
    final links = await pumpButton(tester);
    await openDialog(tester);

    await type(
      tester,
      'https://x.com/someone/status/2087646138526802000?s=20&t=abc',
    );
    await tester.tap(find.byKey(const Key('x-link-submit')));
    await tester.pumpAndSettle();

    expect(links, ['https://x.com/i/status/2087646138526802000']);
  });

  testWidgets('cancelling reports no link at all', (tester) async {
    final links = await pumpButton(tester);
    await openDialog(tester);
    await type(tester, 'https://x.com/a/status/2087646138526802000');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(links, isEmpty);
  });

  testWidgets('bad text is refused locally, with no round trip', (
    tester,
  ) async {
    // Submitting by keyboard bypasses the disabled button, so the guard has to
    // live in the submit path too — not only in the button's enabled state.
    final links = await pumpButton(tester);
    await openDialog(tester);
    await type(tester, 'look at this funny video');

    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(links, isEmpty, reason: 'nothing may reach the service');
    expect(find.text('That is not a link to an X post.'), findsOneWidget);
    expect(
      find.byKey(const Key('x-link-field')),
      findsOneWidget,
      reason: 'the dialog stays open so the paste can be fixed',
    );
  });

  testWidgets('editing clears the complaint about the old text', (
    tester,
  ) async {
    await pumpButton(tester);
    await openDialog(tester);
    await type(tester, 'nonsense');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('That is not a link to an X post.'), findsOneWidget);

    await type(tester, 'https://x.com/a/status/2087646138526802000');
    // Settle, not a single pump: InputDecorator fades its error out over a few
    // hundred ms, so the text is still mounted for the first frame after it is
    // cleared. Asserting on that frame would test the animation, not the state.
    await tester.pumpAndSettle();

    expect(find.text('That is not a link to an X post.'), findsNothing);
  });

  testWidgets('Paste fills the field from the clipboard', (tester) async {
    // The link is on the clipboard essentially every time — the user copied it
    // out of X seconds earlier. Typing a post id by hand is not a real flow.
    const link = 'https://x.com/a/status/2087646138526802000';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': link} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final links = await pumpButton(tester);
    await openDialog(tester);

    await tester.tap(find.byKey(const Key('x-link-paste')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('x-link-submit')));
    await tester.pumpAndSettle();

    expect(links, ['https://x.com/i/status/2087646138526802000']);
  });
}
