import 'dart:async';

import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../core/media.dart';
import '../sources/share_in_source.dart';
import 'library_screen.dart';
import 'maker_controller.dart';
import 'maker_screen.dart';
import 'packs_screen.dart';

/// Three tabs: make a sticker, browse what you have made, and send a pack.
///
/// The Scaffold here is load-bearing beyond layout: it supplies the Material
/// ancestor the Library's InkWell tiles need.
///
/// It also owns **share-in**, because a share can arrive while the user is on
/// any tab and the app has to bring them to the Maker — which needs the
/// `TabController`, and therefore cannot live inside `MakerScreen`.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.dependencies, this.shareIn});

  final AppDependencies dependencies;

  /// Injectable for tests, which must not touch a real platform channel.
  final ShareInSource? shareIn;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const _makeTab = 0;

  late final TabController _tabs = TabController(length: 3, vsync: this);

  /// Owned here, not by [MakerScreen], so a shared file can be loaded into it
  /// from outside the Maker.
  late final MakerController _maker = MakerController(
    deps: widget.dependencies,
  );

  late final ShareInSource _shareIn = widget.shareIn ?? ShareInSource();
  StreamSubscription<MediaHandle>? _shares;

  @override
  void initState() {
    super.initState();

    // Cold start: media the app was *launched by*. ShareInSource.pick() resets
    // the intent afterwards, so it cannot replay on the next visit.
    _shareIn.pick().then(_receive);

    // Warm: shares arriving while the app is already running. Handling only the
    // cold case is the classic mistake — a share target is usually already in
    // memory when someone shares to it, so missing this drops the common case
    // silently, with nothing on screen to explain it.
    _shares = _shareIn.stream().listen(_receive);
  }

  /// Loads a shared file into the Maker and brings the user to it.
  Future<void> _receive(MediaHandle? media) async {
    if (media == null || !mounted) return;

    // Switch first: the encode can take tens of seconds for a clip, and the
    // user should be watching the Maker while it happens rather than wondering
    // whether their share went anywhere.
    _tabs.animateTo(_makeTab);
    await _maker.loadMedia(media);
  }

  @override
  void dispose() {
    _shares?.cancel();
    _maker.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sticker Studio'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.add_circle_outline), text: 'Make'),
            Tab(icon: Icon(Icons.grid_view_outlined), text: 'Library'),
            // A tab of its own rather than a corner of the Library: a pack is
            // the only route into WhatsApp's sticker tray, so reaching one must
            // not depend on remembering where it is hidden.
            Tab(icon: Icon(Icons.folder_copy_outlined), text: 'Packs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          MakerScreen(dependencies: widget.dependencies, controller: _maker),
          LibraryScreen(dependencies: widget.dependencies),
          PacksScreen(dependencies: widget.dependencies),
        ],
      ),
    );
  }
}
