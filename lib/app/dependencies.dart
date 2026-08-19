import 'dart:io';

import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../encoder/animated_encoder.dart';
import '../encoder/encoder.dart';
import '../encoder/ffmpeg_image_transcoder.dart';
import '../encoder/media_duration_probe.dart';
import '../encoder/native_webp_encoder.dart';
import '../encoder/static_encoder.dart';
import '../encoder/tray_icon_encoder.dart';
import '../export/exporter.dart';
import '../export/pack_export_service.dart';
import '../export/pack_stager.dart';
import '../export/sticker_validator.dart';
import '../export/webp_media_probe.dart';
import '../library/database.dart';
import '../library/library_store.dart';
import '../packs/pack_service.dart';
import '../search/search_service.dart';
import '../sharing/sharing_service.dart';
import '../sources/extraction_client.dart';
import '../sources/giphy_client.dart';
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
  AppDependencies({
    required this.database,
    required this.store,
    required this.search,
    required this.staticEncoder,
    required this.animatedEncoder,
    required this.trayIconEncoder,
    required this.durationProbe,
    required this.tagger,
    required this.tagging,
    required this.exporter,
    required this.packStager,
    required this.packExport,
    required this.packs,
    required this.sharing,
    required this.stickerDirectory,
    this.giphy,
    ExtractionClient? extraction,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client() {
    // Assigned in the body, not the initializer list, so it can share the one
    // http client. An initializer list cannot read `this`, and writing
    // `httpClient ?? http.Client()` twice would quietly build a second client
    // with its own connection pool — which `dispose` would then never close.
    this.extraction = extraction ?? ExtractionClient(this.httpClient);
  }

  final AppDatabase database;
  final LibraryStore store;
  final SearchService search;

  /// Stills. Fast enough to re-run on every parameter change.
  final Encoder staticEncoder;

  /// Motion. Slow — see the Maker's stale-preview model in `CLAUDE.md`.
  final AnimatedEncoder animatedEncoder;

  final TrayIconEncoder trayIconEncoder;

  /// How long a source clip runs, so the Maker's trim sliders can be bounded by
  /// the real thing rather than a hardcoded guess.
  final MediaDurationProbe durationProbe;
  final TaggingService tagger;
  final TaggingOrchestrator tagging;
  final Exporter exporter;
  final PackStager packStager;

  /// Stage-then-export, in that order. The screens use this, not [exporter]
  /// directly — firing the intent before staging races an unwritten directory.
  final PackExportService packExport;

  /// Pack creation and growth, including the silent static→animated promotion.
  final PackService packs;

  final SharingService sharing;

  /// Where encoded stickers and thumbnails live.
  final Directory stickerDirectory;

  /// Resolves an X post to a video URL, straight from the phone.
  ///
  /// **Non-null, always.** It used to be nullable and gated on a build-time
  /// service address, so the X button vanished unless a build was pointed at a
  /// self-hosted extractor — which meant it never appeared in a release build
  /// at all. There is no service any more, so there is nothing to configure and
  /// nothing to hide behind.
  late final ExtractionClient extraction;

  /// Shared by the remote sources. One client, so connections are pooled rather
  /// than a fresh socket per download.
  final http.Client httpClient;

  /// Searches Giphy, or **null when no API key was supplied** — in which case
  /// the Maker hides the GIF button, exactly as it does for [extraction].
  final GiphyClient? giphy;

  /// The Giphy API key, supplied at build time:
  ///
  /// ```
  /// flutter build apk --dart-define=GIPHY_API_KEY=$(cat giphy_api_key.txt)
  /// ```
  ///
  /// **Never checked in.** `giphy_api_key.txt` is gitignored and holds the key
  /// for local builds; a real credential in the repository is one `git add`
  /// away from being published.
  static const giphyApiKey = String.fromEnvironment('GIPHY_API_KEY');

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

    // **KEYWORD-ONLY IN v1 — the embedder is deliberately NOT wired in.**
    //
    // Semantic search was measured on device 2026-08-13 and cannot tell a
    // meaningful query from nonsense. Cosine spreads for real queries
    // (0.084/0.088/0.117) OVERLAP those for gibberish (0.083/0.083/0.093), and
    // gibberish "zzzzzz" scored a higher top match (0.9465) than the correct
    // answer for "football" (0.9428). No threshold separates them — not
    // absolute, not relative, not standard deviations from the mean — because
    // the distributions genuinely overlap. In use it returned most of the
    // library for gibberish and drowned exact keyword hits.
    //
    // Junk results are worse than no results: search that confidently returns
    // five wrong stickers for a typo teaches the user not to trust it. Keyword
    // search is also much stronger now that v4 weights the user's own words
    // above auto-tags — semantic was designed to compensate for generic tags,
    // and that compensation is no longer the only defence.
    //
    // Everything is retained — `NativeTextEmbedder`, the bundled model, the
    // blending code and its tests — so re-enabling is *this one argument*. Do
    // that only with device evidence that a better model (the 24.9 MB BERT
    // embedder is the obvious candidate) actually discriminates. See CLAUDE.md.
    final search = FtsSearchService(database, store);

    // A schema upgrade can leave the search index empty — v4 changed the FTS5
    // column layout, and the store's per-save hook only covers stickers written
    // *after* it. Rebuilding here is the difference between an upgraded user's
    // library being searchable and silently not.
    //
    // Reading `allStickers()` first is deliberate: drift opens lazily, so the
    // migration (and therefore the flag) has not run until something queries.
    final existing = await store.allStickers();
    if (database.searchIndexNeedsRebuild && existing.isNotEmpty) {
      await search.reindex();
    }

    final tagger = MlKitTagger();
    final httpClient = http.Client();
    const animated = AnimatedEncoder();
    final stager = PackStager();
    final exporter = WhatsAppExporter(
      validator: StickerValidator(const WebpMediaProbe()),
      channel: PlatformStickerChannel(),
      // Must match `android:authorities` in the manifest, which derives it
      // from the applicationId.
      authority: 'com.stickerstudio.app.stickercontentprovider',
    );

    return AppDependencies(
      database: database,
      store: store,
      search: search,
      // The transcoder is the HEIC fallback: photos the Dart `image` package
      // cannot read go through ffmpeg instead of being refused.
      staticEncoder: StaticEncoder(
        NativeWebpEncoder(),
        transcoder: const FfmpegImageTranscoder(),
      ),
      animatedEncoder: animated,
      trayIconEncoder: TrayIconEncoder(NativeWebpEncoder()),
      durationProbe: const FfprobeDurationProbe(),
      tagger: tagger,
      tagging: TaggingOrchestrator(tagger, store, search: search),
      exporter: exporter,
      packStager: stager,
      packExport: PackExportService(
        store: store,
        stager: stager,
        exporter: exporter,
      ),
      packs: PackService(
        store: store,
        trayIcons: TrayIconEncoder(NativeWebpEncoder()),
        // The same AnimatedEncoder as above, taken through its StaticPromoter
        // face: packs only ever need promotion, never a full encode.
        promoter: animated,
        directory: stickerDir,
      ),
      sharing: SharingService(const PlatformShareBackend(), store),
      stickerDirectory: stickerDir,
      // No argument needed: it talks to X directly and has nothing to
      // configure. Left to the default so there is exactly one place that
      // knows the endpoint.
      // Same rule as the extractor: no key, no button. A build that cannot
      // search should not offer a search.
      giphy: giphyApiKey.isEmpty
          ? null
          : GiphyClient(httpClient, apiKey: giphyApiKey),
      httpClient: httpClient,
    );
  }

  Future<void> dispose() async {
    httpClient.close();
    await database.close();
  }
}
