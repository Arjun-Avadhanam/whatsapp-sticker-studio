import 'dart:async';

import 'package:flutter/material.dart';

import '../sources/giphy_client.dart';

/// Same as the Library's, deliberately: two search fields in one app that feel
/// different are worse than either choice on its own.
const _debounce = Duration(milliseconds: 300);

/// How close to the bottom triggers the next page.
const _loadMoreThreshold = 600.0;

/// Opens the Giphy picker and returns the chosen gif, or null if backed out.
Future<GiphyGif?> showGiphyPicker({
  required BuildContext context,
  required GiphyClient client,
}) {
  // A full route, not a bottom sheet. This needs a keyboard, a scrolling grid
  // and most of the screen — and a sheet is not lifted for the keyboard, which
  // is how the add-to-pack sheet ended up hidden behind it on device.
  return Navigator.of(context).push<GiphyGif>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => GiphyPickerScreen(client: client),
    ),
  );
}

/// Search Giphy and pick one gif.
class GiphyPickerScreen extends StatefulWidget {
  const GiphyPickerScreen({super.key, required this.client});

  final GiphyClient client;

  @override
  State<GiphyPickerScreen> createState() => _GiphyPickerScreenState();
}

class _GiphyPickerScreenState extends State<GiphyPickerScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  Timer? _debounceTimer;

  /// Guards against a slow earlier request landing after a later one.
  ///
  /// Debouncing reduces overlap but does not remove it: a slow query can still
  /// be in flight when the next resolves, and its stale results would land last
  /// and win. Proven load-bearing on the Library's search by removing it.
  int _requestId = 0;

  final _gifs = <GiphyGif>[];

  /// The query these results belong to. Empty means trending.
  String _query = '';

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  /// Rate limiting is held apart from other failures because it is the one
  /// case where offering a retry actively harms the user — see [_Failure].
  bool _rateLimited = false;

  @override
  void initState() {
    super.initState();
    // Trending, not an empty screen: opening on nothing asks the user to guess
    // what the app is good at before showing them anything.
    _load(reset: true);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (q.trim() == _query) return; // nothing actually changed
      _query = q.trim();
      _load(reset: true);
    });
    setState(() {}); // repaint the clear button
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading || _error != null) return;
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - _loadMoreThreshold) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    final id = ++_requestId;
    setState(() {
      if (reset) {
        _loading = true;
        _gifs.clear();
      } else {
        _loadingMore = true;
      }
      _error = null;
      _rateLimited = false;
    });

    final offset = reset ? 0 : _gifs.length;

    try {
      final page = _query.isEmpty
          ? await widget.client.trending(offset: offset)
          : await widget.client.search(_query, offset: offset);

      if (!mounted || id != _requestId) return; // superseded
      setState(() {
        _gifs.addAll(page.gifs);
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } on GiphyException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = e.message;
        _rateLimited = e is GiphyRateLimitException;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        // The client only throws GiphyException for anything it saw; reaching
        // here means the request never completed at all.
        _error = "Couldn't reach Giphy. Check your connection.";
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('giphy-search'),
          controller: _search,
          // Not autofocused: the keyboard would cover the trending grid the
          // instant the screen opens, hiding the thing it opens with.
          autofocus: false,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          decoration: InputDecoration(
            hintText: 'Search GIFs',
            border: InputBorder.none,
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('giphy-clear'),
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: () {
                      _search.clear();
                      _debounceTimer?.cancel();
                      _query = '';
                      _load(reset: true); // back to trending
                    },
                  ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          const _Attribution(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        key: Key('giphy-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return _Failure(
        message: _error!,
        // No retry while rate-limited. Measured against the live API: the limit
        // is a rolling window that further requests keep feeding, so a retry
        // button here would let the user extend their own outage while being
        // told to wait.
        onRetry: _rateLimited ? null : () => _load(reset: true),
      );
    }

    if (_gifs.isEmpty) {
      // Distinct from a failure, and worded for the case that actually happened
      // — a search that matched nothing. Conflating the two tells a user their
      // connection is broken when their spelling is.
      return _Empty(query: _query);
    }

    return GridView.builder(
      key: const Key('giphy-grid'),
      controller: _scroll,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      // One trailing cell carries the load-more spinner, so it scrolls with the
      // content instead of overlaying it.
      itemCount: _gifs.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _gifs.length) {
          return const Center(
            key: Key('giphy-loading-more'),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return _GifTile(
          gif: _gifs[i],
          onTap: () => Navigator.of(context).pop(_gifs[i]),
        );
      },
    );
  }
}

class _GifTile extends StatelessWidget {
  const _GifTile({required this.gif, required this.onTap});

  final GiphyGif gif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: Key('giphy-gif-${gif.id}'),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          color: scheme.surfaceContainerHighest,
          child: Image.network(
            gif.previewUrl.toString(),
            fit: BoxFit.cover,
            // The preview variant, not the full mp4: a grid of originals would
            // pull megabytes per screen for images shown at a third of the
            // width.
            semanticLabel: gif.title.isEmpty ? 'GIF' : gif.title,
            // A broken preview must not take the grid down, and must not be an
            // invisible gap either — the cell stays tappable, because the mp4
            // it points at may be perfectly fine.
            errorBuilder: (_, _, _) =>
                Icon(Icons.gif_box_outlined, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('giphy-no-results'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          query.isEmpty
              ? 'No GIFs to show right now.'
              : 'Nothing matched "$query".',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, this.onRetry});

  final String message;

  /// Null when retrying would make things worse — i.e. while rate-limited.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('giphy-error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Verbatim. For a rate limit this is the only thing that is true:
            // Giphy sends no Retry-After, so any countdown would be invented.
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('giphy-retry'),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Required by Giphy's API terms. Not decoration, and not optional.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Powered by GIPHY',
          key: const Key('giphy-attribution'),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
