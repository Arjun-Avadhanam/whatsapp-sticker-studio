import 'package:flutter/services.dart';

import '../models/pack_record.dart';
import '../models/sticker_record.dart';
import 'sticker_validator.dart';

/// The pack failed **our** pre-flight validation, so the intent was never fired.
///
/// [problems] comes straight from [ValidationResult] and is user-facing: these
/// are the specific, fixable messages we can offer *instead of* WhatsApp's
/// opaque rejection.
class PackNotValidException implements Exception {
  const PackNotValidException(this.problems);

  final List<String> problems;

  @override
  String toString() => 'PackNotValidException: ${problems.join('; ')}';
}

/// The pack passed our validation but **WhatsApp refused it**.
///
/// Kept distinct from [PackNotValidException] because it means something quite
/// different: WhatsApp re-validates on ingest with closed-source rules that are
/// stricter than the published sample (a maintainer says so in issue #606), so
/// this is the gap between their rules and ours. [validationError] is the only
/// diagnostic they give us — never swallow it, and record it when it appears.
class WhatsAppRejectedException implements Exception {
  const WhatsAppRejectedException(this.validationError);

  final String validationError;

  @override
  String toString() => 'WhatsAppRejectedException: $validationError';
}

/// The user backed out of WhatsApp's confirmation. Not an error — the pack is
/// fine and nothing is wrong — but the export did **not** happen, so callers
/// must not record the pack as exported.
class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => 'ExportCancelledException: the user cancelled the add';
}

/// What WhatsApp reported back after the intent.
///
/// Carries **two** facts rather than one nullable error: a cancelled add yields
/// no `validation_error`, so collapsing them would make a decline look like a
/// success and leave the app claiming a pack was exported when it wasn't.
class StickerExportResult {
  const StickerExportResult({required this.added, this.validationError});

  final bool added;
  final String? validationError;
}

/// The platform side of the export: fires WhatsApp's `ENABLE_STICKER_PACK`
/// intent. Injected so the gate logic is testable without a device.
abstract class StickerChannel {
  Future<StickerExportResult> enableStickerPack({
    required String identifier,
    required String authority,
    required String name,
  });
}

/// Hands a finished pack to WhatsApp.
abstract class Exporter {
  Future<void> addPackToWhatsApp(PackRecord pack, List<StickerRecord> stickers);
}

/// [Exporter] over the official third-party sticker API: our `ContentProvider`
/// serves the assets, and this fires the intent that asks WhatsApp to read them.
///
/// **Validation happens first and is a hard gate.** WhatsApp's own rejection is
/// a single opaque string surfaced long after the user did the work; ours names
/// every problem specifically. Firing an intent we already know will fail trades
/// the good error for the bad one.
class WhatsAppExporter implements Exporter {
  WhatsAppExporter({
    required this.validator,
    required this.channel,
    required this.authority,
  });

  final StickerValidator validator;
  final StickerChannel channel;

  /// Must match the `android:authorities` of `StickerContentProvider`.
  final String authority;

  @override
  Future<void> addPackToWhatsApp(
    PackRecord pack,
    List<StickerRecord> stickers,
  ) async {
    final result = await validator.validatePack(pack, stickers);
    if (!result.ok) {
      throw PackNotValidException(result.problems);
    }

    final outcome = await channel.enableStickerPack(
      identifier: pack.id,
      authority: authority,
      name: pack.name,
    );

    // Check the rejection first: WhatsApp returns a non-OK result *and* an error
    // when it refuses, and the error is the far more useful of the two facts.
    final error = outcome.validationError;
    if (error != null && error.isNotEmpty) {
      throw WhatsAppRejectedException(error);
    }
    if (!outcome.added) {
      throw const ExportCancelledException();
    }
  }
}

/// Real [StickerChannel] over a [MethodChannel] to the Kotlin side.
class PlatformStickerChannel implements StickerChannel {
  PlatformStickerChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must stay in sync with `StickerExportChannel.CHANNEL` (Kotlin).
  static const String channelName = 'com.stickerstudio.app/sticker_export';

  final MethodChannel _channel;

  @override
  Future<StickerExportResult> enableStickerPack({
    required String identifier,
    required String authority,
    required String name,
  }) async {
    final reply = await _channel.invokeMethod<Map<Object?, Object?>>(
      'enableStickerPack',
      <String, Object?>{
        'identifier': identifier,
        'authority': authority,
        'name': name,
      },
    );

    return StickerExportResult(
      added: reply?['added'] == true,
      validationError: reply?['validationError'] as String?,
    );
  }
}
