import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../core/media.dart';
import '../core/whatsapp_spec.dart';
import '../sources/camera_source.dart';
import '../sources/gallery_source.dart';
import '../sources/source.dart';
import 'maker_controller.dart';

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
  });

  final AppDependencies dependencies;

  /// Injectable for widget tests; production builds its own.
  final MakerController? controller;

  /// Injectable for widget tests, which must not open real system pickers.
  final Map<String, Source>? sources;

  @override
  State<MakerScreen> createState() => _MakerScreenState();
}

class _MakerScreenState extends State<MakerScreen> {
  late final MakerController _controller =
      widget.controller ?? MakerController(deps: widget.dependencies);

  late final Map<String, Source> _sources =
      widget.sources ?? {'Gallery': GallerySource(), 'Camera': CameraSource()};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SourceButtons(
            sources: _sources,
            busy: _controller.busy,
            onPick: _controller.pickFrom,
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
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _controller.busy ? null : _save,
              icon: const Icon(Icons.save_alt),
              label: const Text('Save sticker'),
            ),
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
  });

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
        if (controller.isPreviewStale) _StaleNotice(controller: controller),
      ],
    );
  }
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.controller});
  final MakerController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const Expanded(
            child: Text('Preview is out of date', key: Key('stale-notice')),
          ),
          TextButton(
            onPressed: controller.busy ? null : controller.refreshPreview,
            child: const Text('Update preview'),
          ),
        ],
      ),
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
    final maxSeconds = WhatsAppSpec.maxAnimationMs / 1000;
    final trimSeconds =
        (params.trim ?? Duration(seconds: maxSeconds.toInt())).inMilliseconds /
        1000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Clip', style: Theme.of(context).textTheme.titleSmall),
        // Trimming is the strongest lever for fitting the 500 KB ceiling — cost
        // is near-linear in frame count — so these are given more prominence
        // than any quality control, and there is no quality slider at all.
        _DurationSlider(
          label: 'Start',
          key: const Key('start-slider'),
          seconds: params.start.inMilliseconds / 1000,
          max: 60,
          enabled: !controller.busy,
          onChanged: (v) =>
              controller.setStart(Duration(milliseconds: (v * 1000).round())),
        ),
        _DurationSlider(
          label: 'Length',
          key: const Key('length-slider'),
          seconds: trimSeconds,
          max: maxSeconds,
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
