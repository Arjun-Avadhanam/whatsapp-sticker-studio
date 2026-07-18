import 'package:flutter/foundation.dart';

import '../core/media.dart';

/// Where a sticker originally came from.
///
/// An enum rather than a free-form string so a typo cannot invent a new source,
/// and so any future `switch` over provenance is exhaustiveness-checked.
enum StickerSource { maker, gallery, camera, shareIn, giphy, xLink }

/// Progress of the background auto-tagging pass.
///
/// [pending] is the state a sticker is saved in — tagging is deliberately async
/// so a slow or offline tagger never blocks the save (spec §7). [failed] marks a
/// terminal error so the UI can offer a retry instead of spinning forever.
enum TaggingStatus { pending, done, failed }

/// Sentinel distinguishing "argument not supplied" from "supplied as null" in
/// [StickerRecord.copyWith]. See the note on `copyWith` below.
const Object _unset = Object();

/// One encoded sticker in the library.
///
/// Immutable: every field is `final` and updates go through [copyWith]. That
/// means a record handed out by the store can never be mutated behind the
/// store's back, so a value read from the library is always exactly what is
/// persisted.
@immutable
class StickerRecord {
  const StickerRecord({
    required this.id,
    required this.filePath,
    required this.thumbnailPath,
    required this.kind,
    required this.packId,
    required this.autoTags,
    required this.manualName,
    required this.manualTags,
    required this.notes,
    required this.source,
    required this.createdAt,
    required this.usageCount,
    required this.sizeBytes,
    required this.taggingStatus,
  });

  final String id;

  /// Absolute path to the encoded 512x512 WebP.
  final String filePath;
  final String thumbnailPath;
  final StickerKind kind;

  /// Null when the sticker is in the library but not yet assigned to a pack.
  final String? packId;

  /// Tags produced by the on-device tagger. Replaced wholesale on each run.
  final List<String> autoTags;

  final String? manualName;
  final List<String> manualTags;
  final String? notes;

  final StickerSource source;
  final DateTime createdAt;

  /// Count of app-mediated sends. A **ranking signal only** — WhatsApp exposes
  /// no usage API, so this can never be a complete usage statistic (spec §2).
  final int usageCount;

  final int sizeBytes;
  final TaggingStatus taggingStatus;

  /// All searchable text as one string, for the FTS5 index (Task 10).
  ///
  /// Nulls and blanks are dropped rather than joined, so the blob never contains
  /// doubled separators that would pollute tokenisation.
  String searchBlob() => [
    ...autoTags,
    manualName,
    ...manualTags,
    notes,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');

  /// Returns a copy with the named fields replaced.
  ///
  /// Nullable fields ([packId], [manualName], [notes]) are typed `Object?` and
  /// default to [_unset] rather than `null`. This is the standard Dart workaround
  /// for a real ambiguity: with the naive `String? manualName` signature,
  /// `manualName ?? this.manualName` cannot tell `copyWith()` (leave it alone)
  /// from `copyWith(manualName: null)` (clear it) — both arrive as `null`, so
  /// clearing a field becomes impossible. Comparing against a private sentinel
  /// distinguishes the two. Non-nullable fields have no such ambiguity and use
  /// the plain `?? this.x` form.
  StickerRecord copyWith({
    String? id,
    String? filePath,
    String? thumbnailPath,
    StickerKind? kind,
    Object? packId = _unset,
    List<String>? autoTags,
    Object? manualName = _unset,
    List<String>? manualTags,
    Object? notes = _unset,
    StickerSource? source,
    DateTime? createdAt,
    int? usageCount,
    int? sizeBytes,
    TaggingStatus? taggingStatus,
  }) {
    return StickerRecord(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      kind: kind ?? this.kind,
      packId: identical(packId, _unset) ? this.packId : packId as String?,
      autoTags: autoTags ?? this.autoTags,
      manualName: identical(manualName, _unset)
          ? this.manualName
          : manualName as String?,
      manualTags: manualTags ?? this.manualTags,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      usageCount: usageCount ?? this.usageCount,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      taggingStatus: taggingStatus ?? this.taggingStatus,
    );
  }

  /// Value equality. List fields are compared **elementwise** via [listEquals] —
  /// `List`'s own `==` is identity, so comparing them directly would make a
  /// record unequal to its own copy.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StickerRecord &&
        other.id == id &&
        other.filePath == filePath &&
        other.thumbnailPath == thumbnailPath &&
        other.kind == kind &&
        other.packId == packId &&
        listEquals(other.autoTags, autoTags) &&
        other.manualName == manualName &&
        listEquals(other.manualTags, manualTags) &&
        other.notes == notes &&
        other.source == source &&
        other.createdAt == createdAt &&
        other.usageCount == usageCount &&
        other.sizeBytes == sizeBytes &&
        other.taggingStatus == taggingStatus;
  }

  /// Must agree with [==]: equal records are obliged to produce equal hashes,
  /// or hash-based lookups (`Set.contains`, `Map` keys) silently miss.
  /// [Object.hashAll] hashes list *contents*, since `List.hashCode` is identity.
  @override
  int get hashCode => Object.hash(
    id,
    filePath,
    thumbnailPath,
    kind,
    packId,
    Object.hashAll(autoTags),
    manualName,
    Object.hashAll(manualTags),
    notes,
    source,
    createdAt,
    usageCount,
    sizeBytes,
    taggingStatus,
  );

  @override
  String toString() =>
      'StickerRecord(id: $id, kind: $kind, name: $manualName, '
      'tags: $autoTags, usage: $usageCount, status: $taggingStatus)';
}
