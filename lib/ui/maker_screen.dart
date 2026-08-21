import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../core/media.dart';
import '../core/whatsapp_spec.dart';
import '../sources/camera_source.dart';
import '../sources/gallery_source.dart';
import '../sources/giphy_source.dart';
import '../models/sticker_record.dart';
import '../models/pack_record.dart';
import '../sources/source.dart';
import '../sources/xlink_source.dart';
import 'add_to_pack_sheet.dart';
import 'export_pack_action.dart';
import 'giphy_picker_screen.dart';
import 'send_sticker_action.dart';
import 'maker_controller.dart';
import 'x_link_button.dart';

/// Turn a picked image or clip into a compliant sticker.
///
/// Presentational: every rule about when to re-encode, what counts as stale and
/// how failures read lives in [MakerController], which is tested on its own.
class MakerScreen extends StatefulWidget {
  const MakerScreen({
    super.key,
    required this.dependencies,
    this.controller,
    this.sources,
    this.xLinkSource,
    this.gifSource,
  });

  final AppDependencies dependencies;

  /// Injectable for widget tests; production builds its own.
  final MakerController? controller;

  /// Injectable for widget tests, which must not open real system pickers.
  final Map<String, Source>? sources;

  /// Builds the source for a pasted X link. Injectable for widget tests, which
  /// must not reach the network.
  ///
  /// Unlike [sources] this is a *builder*: the link is only known once the user
  /// has typed it, so the source cannot exist before then.
  final Source Function(String link)? xLinkSource;

  /// Runs the "choose a GIF" flow and returns a source for the chosen one, or
  /// null if the user backed out. Injectable for widget tests, which must not
  /// reach the network.
  final Future<Source?> Function(BuildContext context)? gifSource;

  @override
  State<MakerScreen> createState() => _MakerScreenState();
}

/// Space kept below the Maker's content so the floating X button cannot sit on
/// top of it. See the note at its use site.
const _fabClearance = 136.0;

class _MakerScreenState extends State<MakerScreen> {
  late final MakerController _controller =
      widget.controller ?? MakerController(deps: widget.dependencies);

  late final Map<String, Source> _sources =
      widget.sources ?? {'Gallery': GallerySource(), 'Camera': CameraSource()};

  /// Always present now. It used to be null unless the build was pointed at a
  /// self-hosted extractor, which meant the X button never appeared in a
  /// release build at all; extraction runs on the phone, so there is nothing
  /// left to configure.
  late final Source Function(String) _xLinkSource =
      widget.xLinkSource ??
      (link) => XLinkSource(
        widget.dependencies.extraction,
        widget.dependencies.httpClient,
        link,
      );

  /// Null when the build carries no Giphy key — the GIF button is then hidden
  /// rather than shown as something that can only fail.
  late final Future<Source?> Function(BuildContext)? _gifSource =
      widget.gifSource ?? _defaultGifSource;

  Future<Source?> Function(BuildContext)? get _defaultGifSource {
    final giphy = widget.dependencies.giphy;
    if (giphy == null) return null;
    return (context) async {
      final gif = await showGiphyPicker(context: context, client: giphy);
      // Backing out is an ordinary choice, so it reaches the controller as a
      // null source and shows nothing at all.
      if (gif == null) return null;
      return GiphySource(gif, widget.dependencies.httpClient);
    };
  }

  /// Chooses a GIF, then loads it exactly like any other picked media.
  ///
  /// The download runs through `pickFrom`, so the busy state and the error
  /// banner are the ones every other source already uses.
  Future<void> _pickGif() async {
    final build = _gifSource;
    if (build == null) return;

    final source = await build(context);
    if (source == null || !mounted) return;

    await _controller.pickFrom(source);
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    // A newly saved sticker gets an empty field; the same sticker rebuilding
    // keeps whatever the user has typed so far.
    final saved = _controller.lastSaved;
    if (saved != null && saved.id != _namedStickerId) {
      _namedStickerId = saved.id;
      _name.text = saved.manualName ?? '';
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _name.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await _controller.save();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved != null ? 'Saved to your library' : 'Nothing to save',
        ),
      ),
    );
  }

  /// The pack the last-saved sticker went into, if any.
  ///
  /// Held here rather than on the controller: it is a fact about this screen's
  /// current flow, not about making a sticker, and the Library (Task 14) will
  /// reach packs its own way.
  PackRecord? _pack;

  final _name = TextEditingController();

  /// Which sticker [_name] currently holds a name for.
  ///
  /// Tracked so the field is cleared when a *different* sticker is saved, but
  /// left alone across the many rebuilds one sticker causes — tagging alone
  /// triggers two. Without this, either the next sticker inherits the previous
  /// name or the user's typing is wiped mid-word.
  String? _namedStickerId;

  Future<void> _export() async {
    final pack = _pack;
    if (pack == null) return;

    await confirmAndExportPack(
      context: context,
      dependencies: widget.dependencies,
      pack: pack,
    );
  }

  /// Sends the sticker to WhatsApp on its own, named after itself.
  ///
  /// Saves any half-typed name first, for the same reason add-to-pack does: the
  /// name is what the wrapper pack will be called, so losing it here would send
  /// a sticker to WhatsApp under the wrong name entirely.
  Future<void> _sendToWhatsApp() async {
    final sticker = _controller.lastSaved;
    if (sticker == null) return;

    await _controller.renameLastSaved(_name.text);
    if (!mounted) return;

    await sendStickerToWhatsApp(
      context: context,
      dependencies: widget.dependencies,
      sticker: _controller.lastSaved ?? sticker,
    );
  }

  /// Offers to file the sticker that was just saved into a pack.
  ///
  /// Only a pack can be added to WhatsApp — a loose sticker cannot — so this is
  /// the step between making one and being able to use it.
  Future<void> _addToPack() async {
    final sticker = _controller.lastSaved;
    if (sticker == null) return;

    final pack = await showAddToPackSheet(
      context: context,
      dependencies: widget.dependencies,
      sticker: sticker,
    );
    if (pack == null || !mounted) return; // backed out

    setState(() => _pack = pack);

    final short =
        WhatsAppSpec.enforcedMinStickersPerPack - pack.stickerIds.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          short > 0
              // Says what is still needed rather than only celebrating: the
              // pack cannot reach WhatsApp until it clears the floor.
              ? 'Added to ${pack.name} · $short more to add it to WhatsApp'
              : 'Added to ${pack.name}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: XLinkButton(
        onLink: (link) => _controller.pickFrom(_xLinkSource(link)),
      ),
      body: ListView(
        // The bottom padding is the floating button's clearance, and it is
        // load-bearing. The list ends with the export card — "Add to WhatsApp",
        // the most important action on the screen — and the button floats over
        // the bottom-right corner of the body. Without room to scroll past it,
        // the button covers that action at exactly the moment it matters.
        //
        // Measured, not guessed: a 48 px small FAB sits 64 px up from the
        // bottom, so it occupies the last 112 px. An earlier 88 px looked
        // generous and still overlapped by 8 px. `_fabClearance` leaves a real
        // gap on top of that, and the geometry is pinned by a test — this
        // number will drift the day the button's size or position changes, and
        // the test is what will say so.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, _fabClearance),
        children: [
          _SourceButtons(
            sources: _sources,
            busy: _controller.busy,
            onPick: _controller.pickFrom,
            onGif: _gifSource == null ? null : _pickGif,
          ),
          const SizedBox(height: 16),
          if (_controller.error != null) _ErrorBanner(_controller.error!),
          if (_controller.media == null)
            const _EmptyState()
          else ...[
            _Preview(controller: _controller),
            const SizedBox(height: 16),
            _FitModeSelector(
              value: _controller.params.fitMode,
              onChanged: _controller.busy ? null : _controller.setFitMode,
            ),
            if (_controller.isAnimated) ...[
              const SizedBox(height: 16),
              _ClipRange(controller: _controller),
              // Directly under the controls that create the need for it, and
              // above Save, so the order reads: change the clip, re-encode it,
              // then save what you were shown.
              if (_controller.needsEncode)
                _EncodePrompt(controller: _controller),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _controller.busy ? null : _save,
              icon: const Icon(Icons.save_alt),
              label: const Text('Save sticker'),
            ),
          ],
          if (_controller.lastSaved != null) ...[
            const SizedBox(height: 16),
            _TaggingStatusCard(
              controller: _controller,
              onAddToPack: _addToPack,
              onSendToWhatsApp: _sendToWhatsApp,
              name: _name,
            ),
          ],
          if (_pack != null) ...[
            const SizedBox(height: 8),
            _ExportCard(pack: _pack!, onExport: _export),
          ],
        ],
      ),
    );
  }
}

class _SourceButtons extends StatelessWidget {
  const _SourceButtons({
    required this.sources,
    required this.busy,
    required this.onPick,
    this.onGif,
  });

  /// Opens the Giphy picker. Null when the build has no API key, in which case
  /// no GIF button is drawn at all.
  ///
  /// Separate from [sources] because it does not fit their shape: the others
  /// hand off to the OS and come back with media, while this one has to run a
  /// whole search screen before there is a `Source` to pick from.
  final VoidCallback? onGif;

  final Map<String, Source> sources;
  final bool busy;
  final Future<void> Function(Source) onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in sources.entries)
          OutlinedButton(
            onPressed: busy ? null : () => onPick(entry.value),
            child: Text(entry.key),
          ),
        if (onGif != null)
          OutlinedButton(
            key: const Key('source-gif'),
            onPressed: busy ? null : onGif,
            child: const Text('GIF'),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: Text('Pick a photo or clip to begin.')),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      // The encoder's own wording, verbatim. EncoderBudgetException names the
      // remedy that actually works ("try trimming it shorter"); replacing it
      // with a generic failure would throw away the only useful advice.
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});
  final MakerController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.preview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Capped rather than free-running: a full-width square preview eats the
        // whole viewport on a phone and pushes the fit/trim controls below the
        // fold, which is exactly where the user needs to be looking.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (preview != null)
                    // Flutter decodes animated WebP natively, so this shows the
                    // real sticker looping — exactly what WhatsApp will
                    // receive, with no video player needed.
                    Image.memory(
                      preview.webpBytes,
                      key: const Key('sticker-preview'),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  if (controller.busy)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: const Center(child: _EncodingIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (preview != null) _QualityReadout(controller: controller),
      ],
    );
  }
}

class _EncodingIndicator extends StatelessWidget {
  const _EncodingIndicator();

  @override
  Widget build(BuildContext context) {
    // Progress is indeterminate — our ffmpeg wrapper exposes no callback — so
    // say the wait is expected rather than looking hung.
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Encoding… video can take a while', textAlign: TextAlign.center),
      ],
    );
  }
}

class _QualityReadout extends StatelessWidget {
  const _QualityReadout({required this.controller});
  final MakerController controller;

  @override
  Widget build(BuildContext context) {
    final report = controller.preview!.report;
    final animated = controller.isAnimated;
    final ceiling = animated
        ? WhatsAppSpec.maxAnimatedBytes
        : WhatsAppSpec.maxStaticBytes;

    final kb = (report.sizeBytes / 1024).toStringAsFixed(0);
    final ceilingKb = (ceiling / 1024).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Size against the ceiling is the number that matters; fps and frames
        // only become interesting when a clip is struggling to fit.
        Text(
          '$kb KB of $ceilingKb KB',
          key: const Key('size-readout'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        LinearProgressIndicator(
          value: (report.sizeBytes / ceiling).clamp(0.0, 1.0),
        ),
        const SizedBox(height: 8),
        Text(
          animated
              ? 'Quality ${report.quality} · ${report.fps} fps · '
                    '${report.frames} frames'
              : 'Quality ${report.quality}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Offers the encode the current parameters are owed.
///
/// Deliberately **outside** the size readout. It used to live inside it, and the
/// readout only renders when a preview exists — so a failed encode removed the
/// readout, this notice, and the app's only retry button all at once. The user
/// was told to trim the clip shorter, trimmed it, and had nothing to press.
class _EncodePrompt extends StatelessWidget {
  const _EncodePrompt({required this.controller});
  final MakerController controller;

  @override
  Widget build(BuildContext context) {
    // Two different situations, and the difference matters to the user: one
    // preview is merely out of date, the other does not exist because the last
    // attempt failed. The error banner says why; this says what to do next.
    final stale = controller.preview != null;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        key: const Key('encode-prompt'),
        children: [
          Expanded(
            child: stale
                ? const Text('Preview is out of date', key: Key('stale-notice'))
                : const Text('No preview yet', key: Key('no-preview-notice')),
          ),
          TextButton(
            onPressed: controller.busy ? null : controller.refreshPreview,
            child: Text(stale ? 'Update preview' : 'Try again'),
          ),
        ],
      ),
    );
  }
}

/// What happened to the sticker that was just saved.
///
/// Deliberately framed around the *sticker*, not the tagger: the sticker is
/// already in the library and already findable by whatever the user named it,
/// so a tagging failure is a missing convenience, never a lost sticker. The
/// copy has to say that, or a red "failed" reads as "your sticker is gone".
class _TaggingStatusCard extends StatelessWidget {
  const _TaggingStatusCard({
    required this.controller,
    required this.onAddToPack,
    required this.onSendToWhatsApp,
    required this.name,
  });

  final MakerController controller;
  final VoidCallback onAddToPack;

  /// Wraps the sticker in a pack of its own and sends that, which is the only
  /// way its name becomes visible in WhatsApp.
  final VoidCallback onSendToWhatsApp;

  /// Owned by the screen, not rebuilt here — a controller recreated on every
  /// rebuild would drop the user's half-typed name.
  final TextEditingController name;

  @override
  Widget build(BuildContext context) {
    final saved = controller.lastSaved!;
    final scheme = Theme.of(context).colorScheme;
    final detail = switch (saved.taggingStatus) {
      // Pending is driven by the record, not by taggingInProgress: the status
      // survives a rebuild, and both mean the same thing here.
      TaggingStatus.pending => const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Finding tags…', key: Key('tagging-pending')),
        ],
      ),
      TaggingStatus.done => _Tags(saved.autoTags),
      TaggingStatus.failed => Row(
        children: [
          const Expanded(
            child: Text(
              // Names the consequence, and the workaround, instead of just
              // announcing an error.
              'Could not tag it automatically — you can still find it by name.',
              key: Key('tagging-failed'),
            ),
          ),
          TextButton(
            onPressed: controller.taggingInProgress
                ? null
                : controller.retryTagging,
            child: const Text('Retry'),
          ),
        ],
      ),
    };

    return Card(
      key: const Key('tagging-status'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(child: Text('Sticker saved')),
              ],
            ),
            const SizedBox(height: 8),
            _NameField(controller: controller, name: name),
            const SizedBox(height: 8),
            detail,
            const SizedBox(height: 4),
            // Two ways out, and the order matters: sending one sticker is what
            // most people want most of the time, so it leads.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton.icon(
                  key: const Key('send-to-whatsapp'),
                  onPressed: onSendToWhatsApp,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send to WhatsApp'),
                ),
                // Offered whether or not tagging succeeded — the two are
                // unrelated, and a sticker with no tags is still perfectly good
                // in a pack.
                TextButton.icon(
                  key: const Key('add-to-pack'),
                  onPressed: onAddToPack,
                  icon: const Icon(Icons.library_add_outlined),
                  label: Text(
                    saved.packId == null
                        ? 'Add to pack'
                        : 'Move to another pack',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What the user calls this sticker.
///
/// Optional, and **deliberately not pre-filled** with the tagger's
/// `suggestedName`. Device testing showed ML Kit's most confident label is
/// scene-level and generic ("sports"), so pre-filling would hand the user a
/// mediocre guess they have to delete first — the same tedium as having to clear
/// auto-tags before adding their own. An empty field with a nudge is less work
/// than a wrong default.
class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.name});

  final MakerController controller;
  final TextEditingController name;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('sticker-name'),
      controller: name,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'Name (optional)',
        hintText: 'so you can find it later',
        isDense: true,
      ),
      // Saved on submit AND on focus loss, because a name typed and then
      // abandoned by tapping elsewhere is still a name the user meant.
      onSubmitted: controller.renameLastSaved,
      onTapOutside: (_) {
        FocusScope.of(context).unfocus();
        controller.renameLastSaved(name.text);
      },
    );
  }
}

/// The pack the sticker just joined, and the way into WhatsApp.
///
/// This is the only route to the sticker tray — the OS share sheet moves a file
/// and WhatsApp renders it as an ordinary photo (device-verified 2026-08-06).
/// So the wording here says *pack*, and never implies a sticker can be sent
/// straight to someone.
class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.pack, required this.onExport});

  final PackRecord pack;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final ready = canExport(pack);

    return Card(
      key: const Key('export-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pack.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              // Disabled-with-a-reason rather than offered-then-refused: the
              // 3-sticker floor is WhatsApp's and it will reject the pack.
              ready ? '${stickerCount(pack)} · ready' : shortfallLabel(pack),
              key: const Key('export-readiness'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('export-button'),
                onPressed: ready ? onExport : null,
                icon: const Icon(Icons.add_to_home_screen),
                label: const Text('Add pack to WhatsApp'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags(this.tags);
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      // Tagging succeeded but recognised nothing — a real outcome for abstract
      // art, and not a failure, so it must not offer a retry that would return
      // the same empty answer.
      return const Text('No tags found', key: Key('tagging-empty'));
    }
    return Wrap(
      key: const Key('tagging-tags'),
      spacing: 6,
      children: [for (final tag in tags) Chip(label: Text(tag))],
    );
  }
}

class _FitModeSelector extends StatelessWidget {
  const _FitModeSelector({required this.value, required this.onChanged});

  final FitMode value;
  final ValueChanged<FitMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<FitMode>(
      segments: const [
        // `contain` is omitted deliberately: it behaves identically to `pad` in
        // the encoder, so offering both would be a distinction without a
        // difference.
        ButtonSegment(
          value: FitMode.pad,
          label: Text('Fit'),
          icon: Icon(Icons.fit_screen),
        ),
        ButtonSegment(
          value: FitMode.smartCrop,
          label: Text('Fill'),
          icon: Icon(Icons.crop),
        ),
      ],
      selected: {value},
      onSelectionChanged: onChanged == null
          ? null
          : (selection) => onChanged!(selection.first),
    );
  }
}

class _ClipRange extends StatelessWidget {
  const _ClipRange({required this.controller});
  final MakerController controller;

  @override
  Widget build(BuildContext context) {
    final params = controller.params;
    final ceiling = WhatsAppSpec.maxAnimationMs / 1000;

    // The clip's real length when it is known. Before this it was a hardcoded
    // 60 s for every video, so a three-second clip offered fifty-seven seconds
    // of dead travel and let the user set a start past the end.
    final total = controller.sourceDuration;
    final totalSeconds = total == null ? null : total.inMilliseconds / 1000;

    final startSeconds = params.start.inMilliseconds / 1000;
    // Falls back to the old behaviour when the probe could not tell, because a
    // failed probe must not remove a control that works.
    final startMax = totalSeconds ?? 60.0;

    // Never offer more length than there is clip left after the start point.
    final lengthMax = totalSeconds == null
        ? ceiling
        : (totalSeconds - startSeconds).clamp(0.1, ceiling);

    final trimSeconds =
        (params.trim ?? Duration(seconds: ceiling.toInt())).inMilliseconds /
        1000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Clip', style: Theme.of(context).textTheme.titleSmall),
            if (totalSeconds != null) ...[
              const SizedBox(width: 8),
              Text(
                // Says what there is to work with. Without it the sliders are
                // guesswork, which matters most for an X post the user has
                // very likely never watched.
                key: const Key('clip-duration'),
                '${totalSeconds.toStringAsFixed(1)}s available',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        // Trimming is the strongest lever for fitting the 500 KB ceiling — cost
        // is near-linear in frame count — so these are given more prominence
        // than any quality control, and there is no quality slider at all.
        _DurationSlider(
          label: 'Start',
          key: const Key('start-slider'),
          seconds: startSeconds,
          max: startMax,
          enabled: !controller.busy,
          onChanged: (v) =>
              controller.setStart(Duration(milliseconds: (v * 1000).round())),
        ),
        _DurationSlider(
          label: 'Length',
          key: const Key('length-slider'),
          seconds: trimSeconds,
          max: lengthMax,
          enabled: !controller.busy,
          onChanged: (v) =>
              controller.setTrim(Duration(milliseconds: (v * 1000).round())),
        ),
      ],
    );
  }
}

class _DurationSlider extends StatelessWidget {
  const _DurationSlider({
    super.key,
    required this.label,
    required this.seconds,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double seconds;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label)),
        Expanded(
          child: Slider(
            value: seconds.clamp(0, max),
            max: max,
            divisions: max.toInt() * 2,
            label: '${seconds.toStringAsFixed(1)}s',
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '${seconds.toStringAsFixed(1)}s',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
