import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app/dependencies.dart';
import '../core/media.dart';
import '../core/whatsapp_spec.dart';
import '../encoder/encoder.dart';
import '../encoder/media_duration_probe.dart';
import '../models/sticker_record.dart';
import '../sources/source.dart';
import '../tagger/tagging_orchestrator.dart';

/// State and behaviour behind the Maker screen.
///
/// Separate from the widget so the interesting rules — when to re-encode, when
/// a preview is stale, what happens on failure — are testable without pumping
/// widgets, and so the screen itself stays presentational.
class MakerController extends ChangeNotifier {
  MakerController({
    required AppDependencies deps,
    Encoder? staticEncoder,
    Encoder? animatedEncoder,
    MediaDurationProbe? durationProbe,
    this.transientErrorLifetime = const Duration(seconds: 5),
  }) : _deps = deps,
       _static = staticEncoder ?? deps.staticEncoder,
       _animated = animatedEncoder ?? deps.animatedEncoder,
       _durationProbe = durationProbe ?? deps.durationProbe;

  final AppDependencies _deps;
  final Encoder _static;
  final Encoder _animated;
  final MediaDurationProbe _durationProbe;

  MediaHandle? _media;
  EncodeParams _params = const EncodeParams();
  EncodedSticker? _preview;
  EncodeParams? _previewParams;
  bool _busy = false;
  String? _error;

  /// Clears a transient error after [transientErrorLifetime]. Null whenever the
  /// current error is one the user is meant to act on.
  Timer? _errorTimer;
  bool _disposed = false;

  /// How long a self-clearing error stays on screen.
  ///
  /// Long enough to read the longest of them — "No video could be found in this
  /// tweet" and the what-a-link-looks-like hint are both a full line — and short
  /// enough that it is gone before the next attempt.
  ///
  /// Injectable so tests can shorten it. The alternative, `fakeAsync`, does not
  /// compose with the async bodies these tests already need, and waiting out a
  /// real five seconds three times over is a slow suite for no gain.
  final Duration transientErrorLifetime;

  MediaHandle? get media => _media;
  EncodeParams get params => _params;
  EncodedSticker? get preview => _preview;

  /// True while an encode is running. Animated encodes take tens of seconds.
  bool get busy => _busy;

  String? get error => _error;

  /// Whether the media needs the slow ffmpeg path.
  bool get isAnimated => _media != null && _media!.kind != MediaKind.image;

  Duration? _sourceDuration;

  /// How long the loaded clip runs, or null when it could not be determined.
  ///
  /// Probed once per load, never per encode. The trim sliders use it to bound
  /// themselves; a null leaves them on their previous fallback, because a failed
  /// probe must not take away a control that works.
  Duration? get sourceDuration => _sourceDuration;

  /// The preview no longer reflects the current parameters.
  ///
  /// Only ever true for animated media: stills re-encode on every change, so
  /// their preview is never behind.
  bool get isPreviewStale =>
      _preview != null && _previewParams != null && _previewParams != _params;

  /// The current parameters have not produced a preview, so an encode is owed.
  ///
  /// Covers two cases the UI must treat alike, and the second one used to be a
  /// dead end. A preview that exists but was encoded with older parameters is
  /// *stale*. **A preview that does not exist at all, because the last encode
  /// failed, is not stale — it is absent** — so `isPreviewStale` was false, the
  /// only "Update preview" button in the app was hidden, and a user told to
  /// "try trimming it shorter" could move the sliders with nothing to press.
  ///
  /// Animated only. A still re-encodes automatically on every change, so it
  /// recovers from a failed encode by itself and never owes anything.
  bool get needsEncode =>
      _media != null && isAnimated && (_preview == null || isPreviewStale);

  /// Picks media and, for stills, encodes it straight away.
  ///
  /// A `null` from [source] means the user cancelled — an ordinary outcome that
  /// leaves the screen exactly as it was, with no error.
  ///
  /// A [SourceException] means it genuinely failed, and its message is shown
  /// verbatim in the error banner. The two are kept apart deliberately: a remote
  /// source fails far more often than a local one, and treating a failure as a
  /// cancel makes the app look broken rather than the link.
  Future<void> pickFrom(Source source) async {
    // Busy for the duration of the pick, not just the encode that follows. A
    // local picker returns the moment the user taps, but a remote source spends
    // seconds on the network first, and without this the screen sits inert with
    // no indication anything is happening. It also stops a second tap starting
    // a competing fetch.
    _busy = true;
    _clearError(); // a retry must not sit under the previous failure
    notifyListeners();

    final MediaHandle? picked;
    try {
      picked = await source.pick();
    } on SourceException catch (e) {
      // Self-clearing: there is nothing to do about a bad link except try
      // another one, so the banner has no reason to outlive being read.
      _showTransientError(e.message);
      return;
    } finally {
      // Released here rather than after loadMedia: _encode owns the flag from
      // that point, and leaving it set through both would make the two states
      // impossible to tell apart on the way out.
      _busy = false;
      notifyListeners();
    }

    if (picked == null) return;
    await loadMedia(picked);
  }

  /// Loads media the screen already has in hand.
  ///
  /// Split out of [pickFrom] for **share-in**, which is push rather than pull:
  /// the OS hands us a file when the user shares into the app, so there is no
  /// picker to call and requiring a `Source` wrapper would be ceremony.
  Future<void> loadMedia(MediaHandle picked) async {
    _media = picked;
    _params = const EncodeParams();
    _preview = null;
    _previewParams = null;
    _sourceDuration = null;
    _clearError();
    notifyListeners();

    // Before the encode, because the trim sliders are built from it and the
    // encode is the slow part. A still has no duration worth asking about.
    if (picked.kind != MediaKind.image) {
      _sourceDuration = await _durationProbe.durationOf(picked.bytes);
      notifyListeners();
    }

    await _encode();
  }

  /// Changes how the sticker is fitted into the 512² frame.
  ///
  /// Stills re-encode immediately — it costs well under a second. Animated
  /// media only records the change and marks the preview stale, because a real
  /// clip measured ~24 s to encode and doing that per toggle would make the
  /// screen unusable.
  Future<void> setFitMode(FitMode mode) async {
    _params = _params.copyWith(fitMode: mode);
    if (_media == null) {
      notifyListeners();
      return;
    }

    if (isAnimated) {
      notifyListeners(); // now stale; the UI offers an explicit refresh
      return;
    }
    await _encode();
  }

  /// Sets how much of a clip to keep, from [MakerController.params]'s start.
  ///
  /// Trimming is the strongest lever for fitting the 500 KB ceiling — cost is
  /// near-linear in frame count — so this matters more than quality tweaking.
  Future<void> setTrim(Duration? trim) =>
      _setClipRange(start: _params.start, trim: trim);

  /// Sets where in the clip the sticker begins.
  ///
  /// Without this, trimming would only ever mean "keep the opening", which is
  /// rarely the moment someone wants out of a longer video.
  Future<void> setStart(Duration start) =>
      _setClipRange(start: start, trim: _params.trim);

  Future<void> _setClipRange({
    required Duration start,
    required Duration? trim,
  }) async {
    // WhatsApp rejects anything past 10 s outright, so clamp the *kept* span
    // here rather than letting the encoder silently truncate it — the readout
    // should show what will actually be produced.
    const maxAnimation = Duration(milliseconds: WhatsAppSpec.maxAnimationMs);
    var clamped = trim == null || trim > maxAnimation ? maxAnimation : trim;

    var from = start.isNegative ? Duration.zero : start;

    // Bound both to the clip itself once its length is known. A start past the
    // end used to be settable, and produced an encode with no frames at all —
    // a failure the user could neither see coming nor explain.
    final total = _sourceDuration;
    if (total != null) {
      if (from > total) from = total;
      final remaining = total - from;
      if (clamped > remaining) clamped = remaining;
    }

    _params = EncodeParams(
      fitMode: _params.fitMode,
      start: from,
      trim: clamped,
    );

    if (_media == null || isAnimated) {
      // Animated: recorded only. The preview is now stale and the UI offers an
      // explicit refresh, because re-encoding here costs tens of seconds.
      notifyListeners();
      return;
    }
    await _encode();
  }

  /// Re-encodes with the current parameters. The explicit action offered when
  /// an animated preview has gone stale.
  Future<void> refreshPreview() => _encode();

  /// Encodes if needed, writes the files, persists the record and hands off to
  /// tagging. Returns the saved record, or `null` if there was nothing to save.
  ///
  /// **Re-encodes first when the preview is stale**, so a user cannot persist a
  /// sticker that differs from the one they were shown.
  Future<StickerRecord?> save() async {
    if (_media == null) return null;
    if (_preview == null || isPreviewStale) {
      await _encode();
    }

    final encoded = _preview;
    if (encoded == null) return null; // the encode failed; _error is set

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final file = File(p.join(_deps.stickerDirectory.path, '$id.webp'));
    await file.writeAsBytes(encoded.webpBytes);

    final record = StickerRecord(
      id: id,
      filePath: file.path,
      // The sticker is already 512² and small; a separate thumbnail would be
      // another file to keep in sync for no benefit at this size.
      thumbnailPath: file.path,
      kind: encoded.kind,
      packId: null,
      autoTags: const [],
      manualName: null,
      manualTags: const [],
      notes: null,
      source: StickerSource.maker,
      createdAt: DateTime.now(),
      usageCount: 0,
      sizeBytes: encoded.sizeBytes,
      taggingStatus: TaggingStatus.pending,
    );

    // Saved first, and searchable immediately — the store maintains the keyword
    // index inside saveSticker.
    await _deps.store.saveSticker(record);

    _lastSaved = record;
    _startTagging(record, encoded.webpBytes);
    return record;
  }

  StickerRecord? _lastSaved;

  /// The most recently saved sticker, refreshed as tagging resolves.
  ///
  /// The UI reads this to show tags once they land, or a retry when they do not.
  StickerRecord? get lastSaved => _lastSaved;

  Future<void>? _pendingTagging;

  /// Completes when the in-flight tagging finishes, or `null` if none is
  /// running. Tagging is asynchronous by design; this is how to observe it.
  Future<void>? get pendingTagging => _pendingTagging;

  /// True while tags are still being worked out for [lastSaved].
  bool get taggingInProgress => _pendingTagging != null;

  /// Runs tagging again for the sticker that was just saved.
  ///
  /// Reads the bytes back from disk rather than reusing the preview, so a retry
  /// still works after the user has moved on and re-encoded something else.
  ///
  /// Goes through the orchestrator's [TaggingOrchestrator.retry], which resets
  /// the record to pending first — so the badge shows work in progress instead
  /// of sitting on "failed" until the second attempt resolves.
  Future<void> retryTagging() async {
    final record = _lastSaved;
    if (record == null || _pendingTagging != null) return;

    final file = File(record.filePath);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();

    _track(_deps.tagging.retry(record, bytes));
    await _pendingTagging;
  }

  /// Names the sticker that was just saved.
  ///
  /// The name is the **highest-signal searchable text there is** — better than
  /// auto-tags for both keyword and semantic search, since device testing
  /// (2026-08-08) showed ML Kit labels the scene rather than the subject
  /// ("sports, team, event" for a footballer). It is also the only per-sticker
  /// text WhatsApp can use, via `accessibility_text`.
  ///
  /// Writes through `updateMetadata`, which touches **only** the name — auto-tags
  /// are a separate field, so naming never disturbs them and the user never has
  /// to clear tags to add their own words.
  Future<void> renameLastSaved(String name) async {
    final record = _lastSaved;
    if (record == null) return;

    final trimmed = name.trim();
    await _deps.store.updateMetadata(
      record.id,
      // Empty clears it rather than storing "", so `accessibility_text` falls
      // back to the auto-tags instead of exporting a blank description.
      manualName: trimmed.isEmpty ? null : trimmed,
    );
    await _refreshLastSaved();
  }

  /// Kicks off tagging and keeps the handle.
  ///
  /// Deliberately NOT awaited by [save]: tagging must never delay the save, and
  /// a failure inside it must not cost the user their sticker. But the future is
  /// *kept* rather than discarded — the UI awaits it to refresh a status badge,
  /// and tests await it before tearing down the database. Dropping it entirely
  /// would let the work run on past anything that could observe or clean up
  /// after it.
  void _startTagging(StickerRecord record, Uint8List bytes) =>
      _track(_deps.tagging.tag(record, bytes));

  void _track(Future<void> work) {
    _pendingTagging = work.whenComplete(() async {
      _pendingTagging = null;
      // Re-read so the UI shows the tags that landed, or the failed state that
      // earns a retry button.
      await _refreshLastSaved();
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _refreshLastSaved() async {
    final id = _lastSaved?.id;
    if (id == null) return;
    _lastSaved = await _deps.store.getSticker(id) ?? _lastSaved;
    notifyListeners();
  }

  Future<void> _encode() async {
    final media = _media;
    if (media == null) return;

    _busy = true;
    _clearError();
    notifyListeners();

    final attempted = _params;
    try {
      final encoder = isAnimated ? _animated : _static;
      _preview = await encoder.encode(media, attempted);
      _previewParams = attempted;
    } on EncoderException catch (e) {
      // Includes EncoderBudgetException, whose message names the remedy that
      // actually works ("try trimming it shorter") — surfaced verbatim rather
      // than flattened into a generic failure.
      _error = e.message;
      _preview = null;
      _previewParams = null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Shows [message] and takes it away again on its own.
  ///
  /// Used for failures the user cannot act on from the banner — a bad link, a
  /// post with no video, a dead connection. The remedy is always "try a
  /// different link", so once it has been read the banner is only clutter, and
  /// it used to sit on the Maker indefinitely while the user got on with
  /// something unrelated.
  ///
  /// **Encoder failures deliberately do NOT use this.** `EncoderBudgetException`
  /// says "try trimming it shorter", which is an instruction to carry out on
  /// this screen with the media still loaded; taking it away mid-task would
  /// remove the only guidance that works. Those clear on the next encode.
  void _showTransientError(String message) {
    _error = message;
    _errorTimer?.cancel();
    _errorTimer = Timer(transientErrorLifetime, () {
      // A later error, or any action that cleared the field, wins — this timer
      // only ever retracts the message it was started for.
      if (_disposed || _error != message) return;
      _error = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Drops any error, and the pending retraction with it.
  ///
  /// Cancelling matters: without it a timer from a dismissed error fires later
  /// and notifies for nothing, and in a test it outlives the controller.
  void _clearError() {
    _errorTimer?.cancel();
    _errorTimer = null;
    _error = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _errorTimer?.cancel();
    super.dispose();
  }

  @visibleForTesting
  void debugSetError(String message) {
    _error = message;
    notifyListeners();
  }
}
