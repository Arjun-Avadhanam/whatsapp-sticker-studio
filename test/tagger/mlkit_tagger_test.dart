import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:whatsapp_sticker_studio/tagger/mlkit_tagger.dart';

import '../app/test_dependencies.dart';

/// Returns canned labels without touching ML Kit's platform channel.
///
/// `ImageLabeler` and `TextRecognizer` are plain injectable classes, so the
/// *selection* rules — threshold, ranking, cap — are testable off-device even
/// though the models themselves are not.
class FakeLabeler implements ImageLabeler {
  FakeLabeler(this.labels);
  final List<ImageLabel> labels;

  @override
  final String id = 'fake';

  @override
  ImageLabelerOptions get options => ImageLabelerOptions();

  @override
  Future<List<ImageLabel>> processImage(InputImage inputImage) async => labels;

  @override
  Future<void> close() async {}
}

class FakeRecognizer implements TextRecognizer {
  FakeRecognizer([this.text = '']);
  final String text;

  @override
  final String id = 'fake';

  @override
  TextRecognitionScript get script => TextRecognitionScript.latin;

  @override
  Future<RecognizedText> processImage(InputImage inputImage) async =>
      RecognizedText(text: text, blocks: const []);

  @override
  Future<void> close() async {}
}

ImageLabel label(String name, double confidence) =>
    ImageLabel(label: name, confidence: confidence, index: 0);

void main() {
  MlKitTagger tagger(List<ImageLabel> labels, {String text = ''}) =>
      MlKitTagger(
        labeler: FakeLabeler(labels),
        recognizer: FakeRecognizer(text),
      );

  test('keeps the three MOST CONFIDENT labels, not the first three', () async {
    // The cap used to take whatever order ML Kit returned. ML Kit is believed to
    // sort by confidence but does not document it, so an unsorted take() would
    // silently keep three arbitrary labels — invisible in output, and exactly
    // the quality loss the cap exists to prevent.
    final tags = await tagger([
      label('stadium', 0.61),
      label('event', 0.62),
      label('sports', 0.95),
      label('team', 0.90),
      label('competition', 0.80),
    ]).tag(onePixelPng());

    expect(tags.subjects, ['sports', 'team', 'competition']);
  });

  test('caps at three, lowered from five after real-content testing', () async {
    // A footballer video returned `sports, team, event, stadium, competition` on
    // device 2026-08-08 — none wrong, but the tail matches any sports photo at
    // all, and that noise is embedded as well as indexed.
    final tags = await tagger([
      for (var i = 0; i < 8; i++) label('label$i', 0.9 - i * 0.01),
    ]).tag(onePixelPng());

    expect(tags.subjects, hasLength(3));
  });

  test('discards labels below the confidence floor', () async {
    final tags = await tagger([
      label('dog', 0.9),
      label('maybe-a-cat', 0.4),
    ]).tag(onePixelPng());

    expect(tags.subjects, ['dog']);
  });

  test('suggestedName is the most confident label', () async {
    final tags = await tagger([
      label('stadium', 0.7),
      label('sports', 0.99),
    ]).tag(onePixelPng());

    expect(tags.suggestedName, 'sports');
  });

  test('OCR text is kept and flattened to one line', () async {
    // Newlines would become a single unsearchable run-on token in the blob, and
    // sticker text is often the most memorable thing about a sticker.
    final tags = await tagger([], text: 'LOL\nWHAT').tag(onePixelPng());

    expect(tags.textInImage, 'LOL WHAT');
  });

  test('no labels and no text yields empty tags, not a failure', () async {
    // A real outcome for abstract art. It must not read as an error, because the
    // sticker is still perfectly usable and findable by whatever it is named.
    final tags = await tagger([]).tag(onePixelPng());

    expect(tags.subjects, isEmpty);
    expect(tags.textInImage, isNull);
    expect(tags.flatten(), isEmpty);
  });
}
