import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import 'maker_screen.dart';

/// Two tabs: make a sticker, and browse what you have made.
///
/// A shell only — the Maker (Task 13) and Library (Task 14) fill the tabs. It
/// exists now because neither screen can be built or widget-tested without
/// somewhere to live.
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
            const _Placeholder(label: 'Library', task: 'Task 14'),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label, required this.task});

  final String label;
  final String task;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$label — $task',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
