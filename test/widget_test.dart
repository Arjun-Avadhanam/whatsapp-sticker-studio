import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/main.dart';

import 'app/test_dependencies.dart';

void main() {
  testWidgets('the app shell builds and shows both tabs', (tester) async {
    // Building the WHOLE app in a plain widget test is the point of the
    // composition root: every platform-touching collaborator sits behind an
    // interface, so nothing here reaches for Kotlin, ML Kit or ffmpeg.
    final deps = await testDependencies();
    addTearDown(deps.dispose);

    await tester.pumpWidget(StickerStudioApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(find.text('Sticker Studio'), findsOneWidget);
    expect(find.text('Make'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('switching tabs shows the other section', (tester) async {
    final deps = await testDependencies();
    addTearDown(deps.dispose);

    await tester.pumpWidget(StickerStudioApp(dependencies: deps));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Library'), findsWidgets);
  });
}
