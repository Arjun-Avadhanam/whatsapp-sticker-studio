import 'package:flutter/material.dart';

import 'app/dependencies.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  // bootstrap() touches the filesystem and platform channels, so the binding
  // must exist before it runs.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(StickerStudioApp(dependencies: await AppDependencies.bootstrap()));
}

/// The app shell.
///
/// Takes its [dependencies] rather than building them, so a test can run the
/// whole app against fakes — the same rule every screen follows.
class StickerStudioApp extends StatelessWidget {
  const StickerStudioApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticker Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF25D366)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25D366),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(dependencies: dependencies),
    );
  }
}
