import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../encoder/animated_encoder.dart';
import '../encoder/encoder.dart';
import '../encoder/native_webp_encoder.dart';
import '../encoder/static_encoder.dart';
import '../encoder/tray_icon_encoder.dart';
import '../export/exporter.dart';
import '../export/pack_stager.dart';
import '../export/sticker_validator.dart';
import '../export/webp_media_probe.dart';
import '../library/database.dart';
import '../library/library_store.dart';
import '../search/search_service.dart';
import '../search/text_embedder.dart';
import '../sharing/sharing_service.dart';
import '../tagger/mlkit_tagger.dart';
import '../tagger/tagging_orchestrator.dart';
import '../tagger/tagging_service.dart';

/// Everything the UI needs, constructed once.
///
/// The **only** place that names concrete implementations. Screens receive this
/// and never build their own collaborators — which is what keeps every one of
/// them widget-testable against fakes, and what has let the whole app be tested
/// without a device so far. Do not reach for a service locator or construct a
/// `NativeWebpEncoder` inside a widget; both would quietly undo that.
class AppDependencies {
  const AppDependencies({
    required this.database,
    required this.store,
    required this.search,
    required this.staticEncoder,
    required this.animatedEncoder,
    required this.trayIconEncoder,
    required this.tagger,
    required this.tagging,
    required this.exporter,
    required this.packStager,
    required this.sharing,
    required this.stickerDirectory,
  });

  final AppDatabase database;
  final LibraryStore store;
  final SearchService search;

  /// Stills. Fast enough to re-run on every parameter change.
  final Encoder staticEncoder;

  /// Motion. Slow — see the Maker's stale-preview model in `CLAUDE.md`.
  final AnimatedEncoder animatedEncoder;

  final TrayIconEncoder trayIconEncoder;
  final TaggingService tagger;
  final TaggingOrchestrator tagging;
  final Exporter exporter;
  final PackStager packStager;
  final SharingService sharing;

  /// Where encoded stickers and thumbnails live.
  final Directory stickerDirectory;

  /// Builds the real implementations. Device-only: the encoders, tagger and
  /// embedder all reach across platform channels.
  static Future<AppDependencies> bootstrap() async {
    final supportDir = await getApplicationSupportDirectory();

    // Same directory the ContentProvider serves packs from, so staging is a
    // local copy rather than a cross-volume move.
    final stickerDir = Directory(p.join(supportDir.path, 'stickers'));
    if (!stickerDir.existsSync()) await stickerDir.create(recursive: true);

    final database = AppDatabase(
      NativeDatabase(File(p.join(supportDir.path, 'library.sqlite'))),
    );
    final store = DriftLibraryStore(database);

    // Search degrades to keyword-only if the embedding model is unavailable —
    // it is an enhancement, never a dependency.
    final search = FtsSearchService(
      database,
      store,
      embedder: NativeTextEmbedder(),
    );

    final tagger = MlKitTagger();

    return AppDependencies(
      database: database,
      store: store,
      search: search,
      staticEncoder: StaticEncoder(NativeWebpEncoder()),
      animatedEncoder: const AnimatedEncoder(),
      trayIconEncoder: TrayIconEncoder(NativeWebpEncoder()),
      tagger: tagger,
      tagging: TaggingOrchestrator(tagger, store, search: search),
      exporter: WhatsAppExporter(
        validator: StickerValidator(const WebpMediaProbe()),
        channel: PlatformStickerChannel(),
        // Must match `android:authorities` in the manifest, which derives it
        // from the applicationId.
        authority: 'com.arjun.whatsapp_sticker_studio.stickercontentprovider',
      ),
      packStager: PackStager(),
      sharing: SharingService(const PlatformShareBackend(), store),
      stickerDirectory: stickerDir,
    );
  }

  Future<void> dispose() async {
    await database.close();
  }
}
