import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sources/x_link.dart';

/// The floating button that starts an "make a sticker from an X post" flow, and
/// the dialog it opens.
///
/// Lives on the Maker only. It is a floating action rather than a fourth entry
/// in the source row because it is the one source that needs typing — the row's
/// buttons all hand off to the OS immediately, and a text field does not belong
/// in that rhythm.
///
/// **A dialog, not a bottom sheet.** Flutter lifts a dialog above the keyboard
/// automatically; it does *not* lift a bottom sheet, which is how the
/// add-to-pack sheet ended up hidden behind the keyboard on device (see
/// CLAUDE.md). This field is the whole point of the screen, so it cannot be the
/// thing that disappears.
class XLinkButton extends StatelessWidget {
  const XLinkButton({super.key, required this.onLink});

  /// Called with a validated, normalised post link.
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      key: const Key('x-link-button'),
      onPressed: () async {
        final link = await showDialog<String>(
          context: context,
          builder: (_) => const XLinkDialog(),
        );
        if (link != null) onLink(link);
      },
      tooltip: 'Make a sticker from an X post',
      child: const _XLogo(),
    );
  }
}

/// Asks for the link, and refuses to hand back anything that is not one.
class XLinkDialog extends StatefulWidget {
  const XLinkDialog({super.key});

  @override
  State<XLinkDialog> createState() => _XLinkDialogState();
}

class _XLinkDialogState extends State<XLinkDialog> {
  final _controller = TextEditingController();

  /// Only shown once the user has stopped typing a moment, or submitted.
  /// Complaining from the first character would flag every link as broken while
  /// it is still being typed.
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Any edit clears the complaint — it described the old text.
      if (_showError) setState(() => _showError = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isValid => XLink.isPostLink(_controller.text);

  void _submit() {
    if (!_isValid) {
      setState(() => _showError = true);
      return;
    }
    // Normalised, not raw: the extractor gets a post id and nothing else.
    Navigator.of(context).pop(XLink.normalise(_controller.text));
  }

  /// Fills the field from the clipboard, which is where the link almost always
  /// is — the user just copied it out of X.
  ///
  /// Offered as a button rather than done automatically on open: Android shows
  /// a system toast whenever an app reads the clipboard, and firing that at
  /// someone who meant to type would be startling and unexplained.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !mounted) return;
    _controller.text = text.trim();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sticker from an X post'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('x-link-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            // The link is a URL, so the shift-happy defaults are wrong: an
            // autocapitalised or autocorrected paste is a link that no longer
            // resolves.
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Enter X link here',
              // Judged locally, so it costs nothing and arrives instantly —
              // rather than after a spinner and a service error.
              errorText: _showError ? 'That is not a link to an X post.' : null,
              helperText: 'x.com/someone/status/1234567890',
              suffixIcon: IconButton(
                key: const Key('x-link-paste'),
                icon: const Icon(Icons.content_paste),
                tooltip: 'Paste',
                onPressed: _paste,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            // Sets expectations before the wait, not after it: extraction is a
            // network round trip and then a video encode, and on a real clip
            // that is 15–20 s.
            'The post needs to contain a video or GIF. This can take a few '
            'seconds.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('x-link-submit'),
          // Disabled rather than hidden while the field is empty or wrong, so
          // the button's position never moves under a thumb.
          onPressed: _isValid ? _submit : null,
          child: const Text('Get video'),
        ),
      ],
    );
  }
}

/// X's mark, drawn rather than set in text or shipped as an asset.
///
/// Material Icons has no X glyph. `Icons.close` is the same shape but means
/// "dismiss", and on a floating button that reads as a close control. The
/// obvious text options are worse: `𝕏` (U+1D54F) is a mathematical
/// double-struck letter that most system fonts do not carry, so it renders as a
/// tofu box on exactly the devices nobody tests on.
///
/// Two strokes on a canvas depend on no font at all.
class _XLogo extends StatelessWidget {
  const _XLogo();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(18, 18),
      painter: _XPainter(Theme.of(context).colorScheme.onPrimaryContainer),
    );
  }
}

class _XPainter extends CustomPainter {
  const _XPainter(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = size.width * 0.16
      // Square caps, not round: the mark is built from straight cut strokes,
      // and rounded ends turn it into a generic cross.
      ..strokeCap = StrokeCap.square;

    // Inset so the strokes' width stays inside the box rather than clipping.
    final i = size.width * 0.12;
    canvas.drawLine(
      Offset(i, i),
      Offset(size.width - i, size.height - i),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - i, i),
      Offset(i, size.height - i),
      paint,
    );
  }

  @override
  bool shouldRepaint(_XPainter old) => old.colour != colour;
}
