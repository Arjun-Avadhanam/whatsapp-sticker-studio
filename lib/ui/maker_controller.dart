import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app/dependencies.dart';
import '../core/media.dart';
import '../core/whatsapp_spec.dart';
import '../encoder/encoder.dart';
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
  }) : _deps = deps,
       _static = staticEncoder ?? deps.staticEncoder,
       _animated = animatedEncoder ?? deps.animatedEncoder;

  final AppDependencies _deps;
  final Encoder _static;
  final Encoder _animated;

  MediaHandle? _media;
  EncodeParams _params = const EncodeParams();
  EncodedSticker? _preview;
  EncodeParams? _previewParams;
  bool _busy = false;
  String? _error;

  MediaHandle? get media => _media;
  EncodeParams get params => _params;
  EncodedSticker? get preview => _preview;

  /// True while an encode is running. Animated encodes take tens of seconds.
  bool get busy => _busy;

  String? get error => _error;

  /// Whether the media needs the slow ffmpeg path.
  bool get isAnimated => _media != null && _media!.kind != MediaKind.image;

  /// The preview no longer reflects the current parameters.
  ///
  /// Only ever true for animated media: stills re-encode on every change, so
  /// their preview is never behind.
  bool get isPreviewStale =>
      _preview != null && _previewParams != null && _previewParams != _params;

  /// Picks media and, for stills, encodes it straight away.
  ///
  /// A `null` from [source] means the user cancelled — an ordinary outcome that
  /// leaves the screen exactly as it was, with no error.
  Future<void> pickFrom(Source source) async {
    final picked = await source.pick();
    if (picked == null) return;

    _media = picked;
    _params = const EncodeParams();
    _preview = null;
    _previewParams = null;
    _error = null;
    notifyListeners();

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
    final clamped = trim == null || trim > maxAnimation ? maxAnimation : trim;

    _params = EncodeParams(
      fitMode: _params.fitMode,
      start: start.isNegative ? Duration.zero : start,
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
    _error = null;
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

  @visibleForTesting
  void debugSetError(String message) {
    _error = message;
    notifyListeners();
  }
}
