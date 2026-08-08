import '../core/media.dart';
import '../core/whatsapp_spec.dart';
import '../models/pack_record.dart';
import '../models/sticker_record.dart';
import 'media_probe.dart';

/// Outcome of validation. [problems] is empty iff [ok] — and every failure is
/// collected (validation never short-circuits), so the UI can show the user all
/// their issues at once instead of one-fix-at-a-time. Messages are user-facing
/// (Task 11 surfaces them), so keep them specific and plain.
class ValidationResult {
  const ValidationResult(this.ok, this.problems);

  final bool ok;
  final List<String> problems;
}

/// Enforces WhatsApp's ceilings on a sticker/pack **before** the export intent
/// fires. WhatsApp re-validates on ingest and returns opaque errors; this turns
/// those into specific, actionable messages up front.
class StickerValidator {
  StickerValidator(this._probe);

  final MediaProbe _probe;

  /// Validates a single sticker: real file dimensions/format (via [MediaProbe])
  /// plus the size ceiling for its kind.
  Future<ValidationResult> validateSticker(StickerRecord s) async {
    final problems = <String>[];
    await _collectStickerProblems(s, problems);
    return ValidationResult(problems.isEmpty, problems);
  }

  /// Validates a whole pack: count, kind homogeneity, and every sticker.
  Future<ValidationResult> validatePack(
    PackRecord pack,
    List<StickerRecord> stickers,
  ) async {
    final problems = <String>[];

    // Gated on the ENFORCED floor, not the documented one — see
    // `WhatsAppSpec.enforcedMinStickersPerPack` for why they differ and what the
    // accepted risk is.
    if (stickers.length < WhatsAppSpec.enforcedMinStickersPerPack) {
      problems.add(
        'A pack needs at least ${WhatsAppSpec.enforcedMinStickersPerPack} '
        'sticker${WhatsAppSpec.enforcedMinStickersPerPack == 1 ? '' : 's'} '
        '(this one has ${stickers.length}).',
      );
    }
    if (stickers.length > WhatsAppSpec.maxStickersPerPack) {
      problems.add(
        'A pack can have at most ${WhatsAppSpec.maxStickersPerPack} stickers '
        '(this one has ${stickers.length}).',
      );
    }

    final wantAnimated = pack.isAnimated;
    for (final s in stickers) {
      final isAnimated = s.kind == StickerKind.animated;
      if (isAnimated != wantAnimated) {
        problems.add(
          wantAnimated
              ? 'Sticker "${_label(s)}" is static, but this is an animated pack.'
              : 'Sticker "${_label(s)}" is animated, but this is a static pack.',
        );
      }
      await _collectStickerProblems(s, problems);
    }

    return ValidationResult(problems.isEmpty, problems);
  }

  /// Appends every problem found for [s] to [problems]. Shared by both entry
  /// points so a sticker is judged identically alone or inside a pack.
  Future<void> _collectStickerProblems(
    StickerRecord s,
    List<String> problems,
  ) async {
    final probe = await _probe.probe(s.filePath);

    if (probe.width != WhatsAppSpec.dimension ||
        probe.height != WhatsAppSpec.dimension) {
      problems.add(
        'Sticker "${_label(s)}" is ${probe.width}x${probe.height}; '
        'it must be exactly ${WhatsAppSpec.dimension}x${WhatsAppSpec.dimension}.',
      );
    }
    if (probe.format != 'webp') {
      problems.add(
        'Sticker "${_label(s)}" is ${probe.format.toUpperCase()}; '
        'it must be WebP.',
      );
    }

    final maxBytes = s.kind == StickerKind.animated
        ? WhatsAppSpec.maxAnimatedBytes
        : WhatsAppSpec.maxStaticBytes;
    if (s.sizeBytes > maxBytes) {
      problems.add(
        'Sticker "${_label(s)}" is ${_kb(s.sizeBytes)} KB; '
        'the limit for ${s.kind == StickerKind.animated ? 'animated' : 'static'} '
        'stickers is ${_kb(maxBytes)} KB.',
      );
    }
  }

  String _label(StickerRecord s) => s.manualName ?? s.id;

  String _kb(int bytes) => (bytes / 1024).toStringAsFixed(0);
}
