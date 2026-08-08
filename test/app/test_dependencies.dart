import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/encoder/animated_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/static_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/tray_icon_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/webp_encoder.dart';
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
import 'package:whatsapp_sticker_studio/tagger/tagging_orchestrator.dart';
import 'package:whatsapp_sticker_studio/tagger/tagging_service.dart';

/// Returns canned bytes without touching a platform channel.
class FakeWebpEncoder implements WebpEncoder {
  @override
  Future<WebpEncodeResult> encode(
    Uint8List rgba, {
    required int width,
    required int height,
    required int maxBytes,
  }) async => WebpEncodeResult(
    bytes: Uint8List.fromList(List.filled(1024, 7)),
    quality: 90,
  );
}

class FakeTagger implements TaggingService {
  FakeTagger([this.tags = const StickerTags(subjects: ['dog'])]);
  final StickerTags tags;

  @override
  Future<StickerTags> tag(Uint8List imageBytes) async => tags;
}

/// Fails the first [failures] attempts, then succeeds.
///
/// A tagger that always fails only proves the failure is *shown*; this proves a
/// retry genuinely recovers, which is the whole point of offering one.
class FlakyTagger implements TaggingService {
  FlakyTagger({
    this.failures = 1,
    this.tags = const StickerTags(subjects: ['dog']),
  });

  final int failures;
  final StickerTags tags;
  int calls = 0;

  @override
  Future<StickerTags> tag(Uint8List imageBytes) async {
    calls++;
    if (calls <= failures) throw StateError('tagger unavailable');
    return tags;
  }
}

/// Counts promotions and returns a plausible animated result.
///
/// The real one shells out to ffmpeg; this is why [StaticPromoter] is an
/// interface at all — pack logic is pure bookkeeping and must not need a device.
class FakePromoter implements StaticPromoter {
  int calls = 0;

  @override
  Future<EncodedSticker> promoteStatic(Uint8List stillBytes) async {
    calls++;
    return EncodedSticker(
      webpBytes: Uint8List.fromList(List.filled(2048, 9)),
      kind: StickerKind.animated,
      width: 512,
      height: 512,
      sizeBytes: 2048,
      report: const QualityReport(
        fps: 10,
        frames: 2,
        quality: 90,
        sizeBytes: 2048,
      ),
    );
  }
}

class FakeExporter implements Exporter {
  final List<PackRecord> exported = [];

  /// Set to make the export fail the way a real one can.
  Object? throws;

  @override
  Future<void> addPackToWhatsApp(
    PackRecord pack,
    List<StickerRecord> stickers,
  ) async {
    exported.add(pack);
    if (throws != null) throw throws!;
  }
}

/// A [PackStager] that copies nothing.
///
/// Real staging writes a manifest and copies every sticker — genuine `dart:io`
/// async, which never completes inside `testWidgets`' fake-time zone and so
/// hangs the test silently. Staging has its own tests; widget tests only care
/// that export was *attempted*.
class StubPackStager extends PackStager {
  StubPackStager({super.baseDir});

  bool staged = false;

  @override
  Future<Directory> stage(
    PackRecord pack,
    List<StickerRecord> stickers, {
    String publisher = 'WhatsApp Sticker Studio',
  }) async {
    staged = true;
    return packDir(pack.id);
  }
}

class FakeShareBackend implements ShareBackend {
  final List<String> shared = [];

  @override
  Future<ShareOutcome> shareFile(String path, {String? mimeType}) async {
    shared.add(path);
    return ShareOutcome.shared;
  }
}

/// Builds an [AppDependencies] with nothing that needs a device.
///
/// That this is possible at all is the point of the composition root: every
/// platform-touching collaborator sits behind an interface, so the whole app
/// can be assembled and driven in a widget test. If this helper ever becomes
/// hard to write, something has started constructing its own dependencies.
Future<AppDependencies> testDependencies({
  Directory? stickerDir,
  TaggingService? tagger,
  FakeExporter? exporter,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  final store = DriftLibraryStore(db);
  final search = FtsSearchService(db, store); // no embedder: keyword-only
  final taggingService = tagger ?? FakeTagger();
  final dir =
      stickerDir ?? Directory.systemTemp.createTempSync('test_stickers');
  final fakeExporter = exporter ?? FakeExporter();
  final stubStager = StubPackStager(baseDir: dir);

  return AppDependencies(
    database: db,
    store: store,
    search: search,
    staticEncoder: StaticEncoder(FakeWebpEncoder()),
    animatedEncoder: const AnimatedEncoder(),
    trayIconEncoder: TrayIconEncoder(FakeWebpEncoder()),
    tagger: taggingService,
    tagging: TaggingOrchestrator(taggingService, store, search: search),
    exporter: fakeExporter,
    packStager: stubStager,
    packExport: PackExportService(
      store: store,
      stager: stubStager,
      exporter: fakeExporter,
    ),
    packs: PackService(
      store: store,
      trayIcons: TrayIconEncoder(FakeWebpEncoder()),
      // Fake, not AnimatedEncoder: promotion shells out to ffmpeg, and packs
      // must stay testable without a device.
      promoter: FakePromoter(),
      directory: dir,
    ),
    sharing: SharingService(FakeShareBackend(), store),
    stickerDirectory: dir,
  );
}

/// A still image the fake encoder can be handed.
MediaHandle fakeImage() => MediaHandle(
  bytes: Uint8List.fromList(List.filled(64, 1)),
  kind: MediaKind.image,
  mimeType: 'image/png',
);

/// A genuinely decodable 1x1 PNG.
///
/// Needed wherever real decoding happens rather than a fake standing in —
/// `Image.memory` in the preview, and `TrayIconEncoder`, which decodes with the
/// `image` package before handing pixels to the WebP encoder. Filler bytes fail
/// there with "could not decode", which looks like a logic bug and is not one.
Uint8List onePixelPng() => Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);
