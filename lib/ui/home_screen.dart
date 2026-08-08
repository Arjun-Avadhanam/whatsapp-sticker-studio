import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import 'library_screen.dart';
import 'maker_screen.dart';
import 'packs_screen.dart';

/// Three tabs: make a sticker, browse what you have made, and send a pack.
///
/// The Scaffold here is load-bearing beyond layout: it supplies the Material
/// ancestor the Library's InkWell tiles need.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sticker Studio'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.add_circle_outline), text: 'Make'),
              Tab(icon: Icon(Icons.grid_view_outlined), text: 'Library'),
              // A tab of its own rather than a corner of the Library: a pack is
              // the only route into WhatsApp's sticker tray, so reaching one
              // must not depend on remembering where it is hidden.
              Tab(icon: Icon(Icons.folder_copy_outlined), text: 'Packs'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            MakerScreen(dependencies: dependencies),
            LibraryScreen(dependencies: dependencies),
            PacksScreen(dependencies: dependencies),
          ],
        ),
      ),
    );
  }
}
