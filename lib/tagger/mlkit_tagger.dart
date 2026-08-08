import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;

import 'tagging_service.dart';

/// [TaggingService] over Google ML Kit, on-device.
///
/// Free by hard constraint and genuinely so: verified 2026-08-01 that both
/// models ship **inside the APK** (`assets/mlkit_label_default_model/…` and
/// `assets/mlkit-google-ocr-models/…`), so tagging works offline from first
/// launch with no API key, no network call and no per-use cost.
class MlKitTagger implements TaggingService {
  MlKitTagger({
    ImageLabeler? labeler,
    TextRecognizer? recognizer,
    this.minConfidence = 0.6,
    this.maxSubjects = 3,
  }) : _labeler =
           labeler ??
           ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5)),
       _recognizer = recognizer ?? TextRecognizer();

  final ImageLabeler _labeler;
  final TextRecognizer _recognizer;

  /// Labels below this are discarded.
  ///
  /// ML Kit will happily return a long tail of low-confidence guesses. Those
  /// pollute the searchable text and, because that same text is embedded, they
  /// degrade *semantic* search as well — a sticker tagged with five things it
  /// is not drifts toward all of them in vector space. Fewer, better tags beat
  /// more tags.
  final double minConfidence;

  /// Caps how many subjects reach the index, for the same reason.
  ///
  /// **Three, lowered from five after real-content testing 2026-08-08.** ML Kit
  /// labels the *scene*, not the subject: a video of a footballer came back
  /// `sports, team, event, stadium, competition` — none wrong, but the tail is
  /// near-noise that would match any sports photo at all. Note this cap reduces
  /// noise without making tags specific; the genericness is inherent to ML Kit's
  /// label set, not to our threshold.
  final int maxSubjects;

  @override
  Future<StickerTags> tag(Uint8List imageBytes) async {
    // ML Kit's InputImage wants a file path or a platform bitmap, not raw
    // bytes. Bridging that here rather than widening the interface keeps every
    // caller — and every other backend — free of ML Kit's shape.
    final temp = File(
      p.join(
        Directory.systemTemp.path,
        'mlkit_${DateTime.now().microsecondsSinceEpoch}.png',
      ),
    );

    try {
      await temp.writeAsBytes(imageBytes);
      final input = InputImage.fromFilePath(temp.path);

      final labels = await _labeler.processImage(input);
      final recognised = await _recognizer.processImage(input);

      // Sorted explicitly before the cap. ML Kit is *believed* to return labels
      // confidence-descending but does not document it, and relying on that
      // would make `take(maxSubjects)` keep three arbitrary labels rather than
      // the three best — invisible in tests, and exactly the kind of quiet
      // quality loss the cap exists to prevent. Also makes `suggestedName`
      // genuinely the most confident label.
      final ranked = labels.where((l) => l.confidence >= minConfidence).toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));

      final subjects = ranked.map((l) => l.label).take(maxSubjects).toList();

      final text = recognised.text.trim();

      return StickerTags(
        subjects: subjects,
        // Newlines would become one unsearchable run-on token in the blob.
        textInImage: text.isEmpty ? null : text.replaceAll('\n', ' '),
        // The most confident label is the best one-word summary we have. The
        // user can always overwrite it.
        suggestedName: subjects.isNotEmpty ? subjects.first : null,
      );
    } on Exception catch (e) {
      // Surfaced as our own type so the orchestrator can tell "vision failed"
      // apart from a programming error, and mark the sticker retryable.
      throw TaggingException('ML Kit could not tag this image: $e');
    } finally {
      if (temp.existsSync()) {
        try {
          await temp.delete();
        } catch (_) {
          // A leftover temp file is harmless; failing to clean it up must not
          // turn a successful tagging into a failure.
        }
      }
    }
  }

  /// Releases the native detectors. Both hold real resources.
  Future<void> close() async {
    await _labeler.close();
    await _recognizer.close();
  }
}
