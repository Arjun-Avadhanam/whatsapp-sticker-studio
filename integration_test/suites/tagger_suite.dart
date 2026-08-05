import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whatsapp_sticker_studio/tagger/mlkit_tagger.dart';
import 'package:whatsapp_sticker_studio/tagger/tagging_service.dart';

/// Task 9 — device verification of the REAL ML Kit backend.
///
/// Mostly **reporting, not asserting**. ML Kit's label vocabulary is not ours to
/// pin, and asserting fixed strings would test Google's model rather than our
/// code. What matters is a judgement the printout supports: *would these tags
/// let someone find this sticker again?* — which is the product's whole premise.
///
/// Two specific risks worth watching in the output:
///  - **Illustrated stickers.** A lot of stickers are drawings, and labellers
///    trained on photographs often return generic or wrong labels for cartoon
///    art. Weak labels here would undermine Task 14's search UI.
///  - **Sticker-style text.** OCR is tuned for document text. Heavy display
///    fonts, outlines and text over busy backgrounds are the sticker norm, and
///    the OCR pipeline is roughly half of ML Kit's ~61 MB footprint — so if it
///    cannot read sticker text, dropping it is a real size win.
void taggerTests() {
  late MlKitTagger tagger;

  setUp(() => tagger = MlKitTagger());
  tearDown(() => tagger.close());

  void report(String label, StickerTags tags) {
    debugPrint('');
    debugPrint('===== TAGS: $label =====');
    debugPrint('subjects      : ${tags.subjects}');
    debugPrint('textInImage   : ${tags.textInImage ?? "(none)"}');
    debugPrint('suggestedName : ${tags.suggestedName ?? "(none)"}');
    debugPrint('flatten()     : ${tags.flatten()}');
    debugPrint('==============================');
    debugPrint('');
  }

  /// A flat-coloured shape with a face — the shape most stickers actually take,
  /// and deliberately NOT a photograph.
  Uint8List cartoonFace() {
    final im = img.Image(width: 512, height: 512, numChannels: 4);
    img.fill(im, color: img.ColorRgba8(255, 214, 10, 255));
    img.fillCircle(
      im,
      x: 256,
      y: 256,
      radius: 200,
      color: img.ColorRgba8(255, 236, 120, 255),
    );
    img.fillCircle(
      im,
      x: 190,
      y: 210,
      radius: 28,
      color: img.ColorRgba8(20, 20, 20, 255),
    );
    img.fillCircle(
      im,
      x: 322,
      y: 210,
      radius: 28,
      color: img.ColorRgba8(20, 20, 20, 255),
    );
    // A crude smile.
    for (var x = 170; x < 342; x++) {
      final y = 300 + ((x - 256) * (x - 256) ~/ 260);
      img.drawPixel(im, x, y, img.ColorRgba8(20, 20, 20, 255));
      img.drawPixel(im, x, y + 1, img.ColorRgba8(20, 20, 20, 255));
      img.drawPixel(im, x, y + 2, img.ColorRgba8(20, 20, 20, 255));
    }
    return Uint8List.fromList(img.encodePng(im));
  }

  /// Big bold text on a plain background — the easiest possible case for OCR.
  /// If this fails, sticker text in the wild has no chance.
  Uint8List boldText() {
    final im = img.Image(width: 512, height: 512, numChannels: 4);
    img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
    img.drawString(
      im,
      'LOL',
      font: img.arial48,
      x: 180,
      y: 220,
      color: img.ColorRgba8(0, 0, 0, 255),
    );
    return Uint8List.fromList(img.encodePng(im));
  }

  /// A photograph-like gradient scene, which is what ML Kit's labeller is
  /// actually trained on — the control case.
  Uint8List photoLike() {
    final im = img.Image(width: 512, height: 512, numChannels: 4);
    for (var y = 0; y < 512; y++) {
      for (var x = 0; x < 512; x++) {
        im.setPixelRgba(x, y, 40 + y ~/ 4, 90 + x ~/ 8, 160 - y ~/ 6, 255);
      }
    }
    img.fillCircle(
      im,
      x: 256,
      y: 330,
      radius: 120,
      color: img.ColorRgba8(90, 70, 50, 255),
    );
    return Uint8List.fromList(img.encodePng(im));
  }

  testWidgets(
    'ML Kit runs offline and returns something for a photo-like image',
    (tester) async {
      // The only hard assertion in this suite: the backend is wired up and does
      // not throw. Everything about *quality* is reported, not asserted.
      final tags = await tagger.tag(photoLike());
      report('photo-like gradient (control)', tags);
      expect(tags, isNotNull);
    },
  );

  testWidgets('REPORT: labels on an illustrated sticker', (tester) async {
    final tags = await tagger.tag(cartoonFace());
    report('cartoon face (the common sticker case)', tags);

    if (tags.subjects.isEmpty) {
      debugPrint(
        '>>> FINDING: no labels above confidence for illustrated art. '
        'If this holds for real stickers, auto-tagging carries much less of '
        'the search load than the spec assumes, and Task 14 should lean on '
        'manual names. Record in CLAUDE.md.',
      );
    }
  });

  testWidgets('REPORT: OCR on large bold text', (tester) async {
    final tags = await tagger.tag(boldText());
    report('bold "LOL" on white (easiest possible OCR)', tags);

    if (tags.textInImage == null) {
      debugPrint(
        '>>> FINDING: OCR read nothing from the easiest possible input. '
        'Text recognition is ~half of ML Kit\'s ~61 MB footprint, so if it '
        'cannot read sticker text, dropping the dependency is a real win.',
      );
    }
  });
}
