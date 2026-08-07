import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:whatsapp_sticker_studio/app/dependencies.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/encoder/animated_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/static_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/tray_icon_encoder.dart';
import 'package:whatsapp_sticker_studio/encoder/webp_encoder.dart';
import 'package:whatsapp_sticker_studio/export/exporter.dart';
import 'package:whatsapp_sticker_studio/export/pack_stager.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/pack_record.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
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

class FakeExporter implements Exporter {
  final List<PackRecord> exported = [];

  @override
  Future<void> addPackToWhatsApp(
    PackRecord pack,
    List<StickerRecord> stickers,
  ) async => exported.add(pack);
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
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  final store = DriftLibraryStore(db);
  final search = FtsSearchService(db, store); // no embedder: keyword-only
  final taggingService = tagger ?? FakeTagger();
  final dir =
      stickerDir ?? Directory.systemTemp.createTempSync('test_stickers');

  return AppDependencies(
    database: db,
    store: store,
    search: search,
    staticEncoder: StaticEncoder(FakeWebpEncoder()),
    animatedEncoder: const AnimatedEncoder(),
    trayIconEncoder: TrayIconEncoder(FakeWebpEncoder()),
    tagger: taggingService,
    tagging: TaggingOrchestrator(taggingService, store, search: search),
    exporter: FakeExporter(),
    packStager: PackStager(baseDir: dir),
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
