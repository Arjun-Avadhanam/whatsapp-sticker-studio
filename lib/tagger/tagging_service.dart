import 'dart:typed_data';

/// What vision found in a sticker.
///
/// Fields are separate rather than one bag of strings because they mean
/// different things to the UI — [suggestedName] is offered as a name, the rest
/// are searchable metadata — even though [flatten] pours them all into the same
/// searchable text.
class StickerTags {
  const StickerTags({
    this.subjects = const [],
    this.emotion,
    this.action,
    this.textInImage,
    this.suggestedName,
    this.style,
  });

  /// What is in the picture: "dog", "person", "food".
  final List<String> subjects;

  final String? emotion;
  final String? action;

  /// Text read out of the image by OCR.
  ///
  /// Often the single most memorable thing about a sticker — people look for
  /// "the one that says LOL" far more than "the one with a dog" — so this is a
  /// first-class field, not a curiosity.
  final String? textInImage;

  /// A name to offer the user, which they can accept or overwrite.
  final String? suggestedName;

  final String? style;

  /// Everything searchable, de-duplicated, in one list.
  ///
  /// This is what reaches `StickerRecord.autoTags`, and from there both the FTS
  /// index and the embedding — so anything omitted here is permanently
  /// unfindable, by keyword *and* by meaning.
  List<String> flatten() {
    final all = <String>[
      ...subjects,
      ?emotion,
      ?action,
      ?textInImage,
      ?style,
      // suggestedName is deliberately excluded: it becomes the sticker's name,
      // and repeating it as a tag would double-count it in relevance scoring.
    ];

    final seen = <String>{};
    return all
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .where((t) => seen.add(t.toLowerCase()))
        .toList();
  }

  /// True when vision found nothing usable — the caller may still want to save
  /// the sticker, just without tags.
  bool get isEmpty => flatten().isEmpty && suggestedName == null;
}

/// Thrown when tagging cannot complete. The orchestrator turns this into
/// `TaggingStatus.failed` rather than losing the sticker.
class TaggingException implements Exception {
  const TaggingException(this.message);
  final String message;
  @override
  String toString() => 'TaggingException: $message';
}

/// Describes a sticker's contents, for free and on-device.
///
/// Behind an interface because the backend is the most likely thing in this app
/// to change: ML Kit today, possibly a free-tier hosted model later. Consumers
/// only ever see [StickerTags].
abstract class TaggingService {
  Future<StickerTags> tag(Uint8List imageBytes);
}
