import 'package:flutter/foundation.dart';

/// A sticker pack — the unit WhatsApp installs.
///
/// Mirrors WhatsApp's pack model because it is serialised straight into the
/// `contents.json` the [Exporter]'s ContentProvider serves (Task 11).
///
/// Immutable for the same reason as `StickerRecord`: updates go through
/// [copyWith], so a pack handed out by the store cannot be mutated behind its
/// back.
@immutable
class PackRecord {
  const PackRecord({
    required this.id,
    required this.name,
    required this.trayIconPath,
    required this.isAnimated,
    required this.stickerIds,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// Path to the 96x96 tray icon shown as this pack's tab in WhatsApp's drawer.
  final String trayIconPath;

  /// Maps to WhatsApp's `animated_sticker_pack` metadata flag. A pack may not
  /// mix static and animated stickers.
  final bool isAnimated;

  /// Ordered — this is the order stickers appear in WhatsApp, so it is
  /// meaningful state, not just set membership. Equality treats it as such.
  final List<String> stickerIds;

  final DateTime createdAt;

  PackRecord copyWith({
    String? id,
    String? name,
    String? trayIconPath,
    bool? isAnimated,
    List<String>? stickerIds,
    DateTime? createdAt,
  }) {
    return PackRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      trayIconPath: trayIconPath ?? this.trayIconPath,
      isAnimated: isAnimated ?? this.isAnimated,
      stickerIds: stickerIds ?? this.stickerIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Value equality; [stickerIds] compared elementwise and **order-sensitively**
  /// via [listEquals], since reordering a pack is a real change WhatsApp renders.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PackRecord &&
        other.id == id &&
        other.name == name &&
        other.trayIconPath == trayIconPath &&
        other.isAnimated == isAnimated &&
        listEquals(other.stickerIds, stickerIds) &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    trayIconPath,
    isAnimated,
    Object.hashAll(stickerIds),
    createdAt,
  );

  @override
  String toString() =>
      'PackRecord(id: $id, name: $name, animated: $isAnimated, '
      'stickers: ${stickerIds.length})';
}
