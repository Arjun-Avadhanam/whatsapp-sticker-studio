import 'dart:io';

import 'package:drift/native.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';
import 'package:whatsapp_sticker_studio/encoder/animated_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/media_duration_probe.dart';
import 'package:whatsapp_sticker_studio/encoder/native_webp_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/static_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/tray_icon_encoder.dart';
import 'package:whatsapp_sticker_studio/export/exporter.dart';
import 'package:whatsapp_sticker_studio/export/pack_export_service.dart';
import 'package:whatsapp_sticker_studio/export/pack_stager.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/packs/pack_service.dart';
import 'package:whatsapp_sticker_studio/search/search_service.dart';
import 'package:whatsapp_sticker_studio/sharing/sharing_service.dart';
import 'package:whatsapp_sticker_studio/sources/source.dart';
import 'package:whatsapp_sticker_studio/tagger/mlkit_tagger.dart';
import 'package:whatsapp_sticker_studio/tagger/tagging_orchestrator.dart';
import 'package:whatsapp_sticker_studio/ui/maker_controller.dart';

/// Task 15 — the whole v1 loop, on device, with **real implementations**.
///
/// Every layer is already verified on its own. What has never been exercised is
/// the *seams between them* in one pass: the native encoder feeding the store,
/// the store's index hook feeding search, ML Kit's output reaching the FTS
/// blob, promotion firing from pack membership, and the stager writing what the
/// ContentProvider expects. A bug in any of those joints passes every unit test.
///
/// Only two things are substituted, both because they need a human:
/// - the **picker** — `GallerySource` opens the system photo picker;
/// - the **export intent** — it hands control to WhatsApp's own UI.
///
/// Both are covered elsewhere: pickers by the Task 7 source probes, and the
/// intent by `interactive_test.dart`, which a person taps through.
void endToEndTests() {
  late Directory work;
  late AppDatabase db;
  late AppDependencies deps;
  late RecordingExporter exporter;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('e2e');
    db = AppDatabase(NativeDatabase.memory());
    final store = DriftLibraryStore(db);

    // Keyword-only, matching production: the embedder is deliberately not wired
    // in (see CLAUDE.md — USE cannot separate a real query from gibberish).
    final search = FtsSearchService(db, store);
    final tagger = MlKitTagger();
    const animated = AnimatedEncoder();
    exporter = RecordingExporter();

    // An in-memory database and a temp directory, so a run leaves the device's
    // real library untouched. The stager still writes to the app support dir,
    // because that is the only place StickerContentProvider reads from.
    deps = AppDependencies(
      database: db,
      store: store,
      search: search,
      staticEncoder: StaticEncoder(NativeWebpEncoder()),
      animatedEncoder: animated,
      trayIconEncoder: TrayIconEncoder(NativeWebpEncoder()),
      // The real one: this suite exists to exercise the actual native stack.
      durationProbe: const FfprobeDurationProbe(),
      tagger: tagger,
      tagging: TaggingOrchestrator(tagger, store),
      exporter: exporter,
      packStager: PackStager(),
      packExport: PackExportService(
        store: store,
        stager: PackStager(),
        exporter: exporter,
      ),
      packs: PackService(
        store: store,
        trayIcons: TrayIconEncoder(NativeWebpEncoder()),
        promoter: animated,
        directory: work,
      ),
      sharing: SharingService(const PlatformShareBackend(), store),
      stickerDirectory: work,
    );
  });

  tearDown(() async {
    await db.close();
    if (work.existsSync()) await work.delete(recursive: true);
  });

  testWidgets('the whole loop: make → tag → name → find → pack → stage', (
    tester,
  ) async {
    final controller = MakerController(deps: deps);
    addTearDown(controller.dispose);

    // 1. MAKE — a real photo-like source through the real native encoder.
    await controller.pickFrom(_FixtureSource(_photoLikePng()));
    expect(controller.error, isNull, reason: controller.error ?? '');
    expect(controller.preview, isNotNull);

    final report = controller.preview!.report;
    debugPrint(
      '>>> E2E encoded: ${report.sizeBytes} bytes at quality ${report.quality}',
    );
    expect(
      report.sizeBytes,
      lessThanOrEqualTo(WhatsAppSpec.maxStaticBytes),
      reason: 'the encoder must never hand back something over the ceiling',
    );

    // 2. SAVE — writes the file and the record, and schedules tagging.
    final saved = await controller.save();
    expect(saved, isNotNull);
    expect(File(saved!.filePath).existsSync(), isTrue);

    // 3. TAG — real ML Kit. Awaited here only because a test must not outlive
    //    its own work; the app deliberately does not block the save on it.
    await controller.pendingTagging;
    final tagged = (await deps.store.getSticker(saved.id))!;
    debugPrint('>>> E2E auto-tags: ${tagged.autoTags}');
    expect(
      tagged.taggingStatus,
      TaggingStatus.done,
      reason: 'ML Kit failed on device: models missing from the APK?',
    );

    // 4. NAME — the highest-signal searchable text there is.
    await controller.renameLastSaved('penguin party');

    // 5. FIND — proves the store's index hook reached FTS5 for real. Both
    //    paths matter: the user's own words AND what vision found.
    final byName = await deps.search.query('penguin');
    expect(
      byName.map((h) => h.record.id),
      contains(saved.id),
      reason: 'a named sticker must be findable by that name',
    );

    // A nonsense query must return NOTHING. This is the regression guard for
    // the semantic layer being switched off — with it on, gibberish returned
    // most of the library.
    expect(
      await deps.search.query('ufidjsjsjsjs'),
      isEmpty,
      reason: 'gibberish must match nothing — is the embedder wired in again?',
    );

    if (tagged.autoTags.isNotEmpty) {
      final tag = tagged.autoTags.first;
      final byTag = await deps.search.query(tag);
      expect(
        byTag.map((h) => h.record.id),
        contains(saved.id),
        reason: 'auto-tag "$tag" reached the index but does not match',
      );
    }

    // 6. PACK — tray icon generated from the sticker, no user input.
    final pack = await deps.packs.createPack(name: 'E2E pack', first: tagged);
    expect(File(pack.trayIconPath).existsSync(), isTrue);
    expect((await deps.store.getSticker(saved.id))!.packId, pack.id);

    // 7. STAGE — where StickerContentProvider actually reads from, and with the
    //    real validator as the gate. A single sticker is enough: the enforced
    //    floor is 1.
    await deps.packExport.addToWhatsApp(pack);
    expect(exporter.exported.single.id, pack.id);

    final staged = await deps.packStager.packDir(pack.id);
    final manifest = File(p.join(staged.path, PackStager.manifestName));
    expect(manifest.existsSync(), isTrue);

    final json = await manifest.readAsString();
    debugPrint('>>> E2E manifest: $json');
    expect(json, contains('"identifier": "${pack.id}"'));
    expect(json, contains('E2E pack'));
    // accessibility_text is the ONLY per-sticker text WhatsApp accepts, and it
    // was exporting empty until Task 13 gave it a fallback.
    expect(
      json,
      contains('penguin party'),
      reason: 'the sticker name must reach accessibility_text',
    );
    expect(
      File(p.join(staged.path, '${saved.id}.webp')).existsSync(),
      isTrue,
      reason: 'the provider serves this path; a missing file is a broken pack',
    );
  });

  testWidgets('a static joining an animated pack is promoted, silently', (
    tester,
  ) async {
    // The project's largest design risk, exercised through the real ffmpeg path
    // rather than a fake promoter. A single frame would be rejected by WhatsApp
    // exactly like a static file, so the frame count is the assertion.
    final controller = MakerController(deps: deps);
    addTearDown(controller.dispose);

    // An animated sticker first, so the pack is animated.
    await controller.pickFrom(_FixtureSource(await _tinyMp4(work)));
    expect(controller.error, isNull, reason: controller.error ?? '');
    final motion = await controller.save();
    await controller.pendingTagging;
    expect(motion!.kind, StickerKind.animated);

    final pack = await deps.packs.createPack(name: 'Motion', first: motion);
    expect(pack.isAnimated, isTrue);

    // Now a still joins it.
    await controller.pickFrom(_FixtureSource(_photoLikePng()));
    final still = await controller.save();
    await controller.pendingTagging;
    expect(still!.kind, StickerKind.staticImage);

    await deps.packs.addSticker(pack, still);

    final promoted = (await deps.store.getSticker(still.id))!;
    expect(promoted.kind, StickerKind.animated);
    expect(
      promoted.filePath,
      still.filePath,
      reason: 'promotion overwrites in place; other records point at this path',
    );

    // The file really is multi-frame now. `ANMF` is the per-frame chunk.
    final bytes = await File(promoted.filePath).readAsBytes();
    final frames = _countChunks(bytes, 'ANMF');
    debugPrint('>>> E2E promoted frame count: $frames');
    expect(
      frames,
      greaterThanOrEqualTo(2),
      reason: 'WhatsApp rejects a 1-frame "animated" WebP like a static one',
    );
  });
}

/// Hands the Maker bytes without opening a picker.
class _FixtureSource implements Source {
  _FixtureSource(this.bytes);
  final Uint8List bytes;

  @override
  Future<MediaHandle?> pick() async => MediaHandle(
    bytes: bytes,
    kind: _isMp4(bytes) ? MediaKind.video : MediaKind.image,
    mimeType: _isMp4(bytes) ? 'video/mp4' : 'image/png',
  );

  static bool _isMp4(Uint8List b) =>
      b.length > 8 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79;
}

/// Records the export instead of handing control to WhatsApp's UI, which cannot
/// be driven from `integration_test`. The intent itself is covered by
/// `interactive_test.dart`.
class RecordingExporter implements Exporter {
  final List<PackRecord> exported = [];

  @override
  Future<void> addPackToWhatsApp(
    PackRecord pack,
    List<StickerRecord> stickers,
  ) async => exported.add(pack);
}

/// Structured, photo-like content rather than noise.
///
/// Uniform random noise is maximum-entropy and will not fit under 100 KB at any
/// quality, so it would fail the encode for reasons unrelated to the loop. It
/// also gives ML Kit something it can plausibly label.
Uint8List _photoLikePng() {
  final image = img.Image(width: 640, height: 480, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(28, 96, 168, 255));
  img.fillCircle(
    image,
    x: 320,
    y: 200,
    radius: 140,
    color: img.ColorRgba8(250, 214, 42, 255),
  );
  img.fillRect(
    image,
    x1: 120,
    y1: 330,
    x2: 520,
    y2: 430,
    color: img.ColorRgba8(232, 76, 60, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// A short real clip, generated with ffmpeg rather than by a per-pixel Dart
/// loop — the loops dominated runtime badly enough to be worth avoiding.
Future<Uint8List> _tinyMp4(Directory dir) async {
  final out = File(p.join(dir.path, 'clip.mp4'));
  await _ffmpeg(
    '-y -f lavfi -i testsrc2=size=320x240:rate=10:duration=1 '
    '-pix_fmt yuv420p ${out.path}',
  );
  return out.readAsBytes();
}

Future<void> _ffmpeg(String args) async {
  final session = await FFmpegKit.execute(args);
  final code = await session.getReturnCode();
  if (!ReturnCode.isSuccess(code)) {
    throw StateError(
      'fixture ffmpeg failed: ${await session.getAllLogsAsString()}',
    );
  }
}

/// Counts occurrences of a four-character RIFF chunk id.
int _countChunks(Uint8List bytes, String fourCC) {
  final target = fourCC.codeUnits;
  var count = 0;
  for (var i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] == target[0] &&
        bytes[i + 1] == target[1] &&
        bytes[i + 2] == target[2] &&
        bytes[i + 3] == target[3]) {
      count++;
    }
  }
  return count;
}
