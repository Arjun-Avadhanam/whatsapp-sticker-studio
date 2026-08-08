import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import 'library_screen.dart';
import 'maker_screen.dart';

/// Two tabs: make a sticker, and browse what you have made.
///
/// The Scaffold here is load-bearing beyond layout: it supplies the Material
/// ancestor the Library's InkWell tiles need.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sticker Studio'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.add_circle_outline), text: 'Make'),
              Tab(icon: Icon(Icons.grid_view_outlined), text: 'Library'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            MakerScreen(dependencies: dependencies),
            LibraryScreen(dependencies: dependencies),
          ],
        ),
      ),
    );
  }
}
