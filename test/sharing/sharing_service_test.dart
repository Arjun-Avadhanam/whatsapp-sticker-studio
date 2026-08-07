import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/sharing/sharing_service.dart';

/// Records what it was asked to share and returns a scripted outcome.
class FakeShareBackend implements ShareBackend {
  FakeShareBackend(this.outcome);
  FakeShareBackend.throwing() : outcome = ShareOutcome.shared, explode = true;

  final ShareOutcome outcome;
  bool explode = false;

  final List<String> paths = [];
  final List<String?> mimeTypes = [];

  @override
  Future<ShareOutcome> shareFile(String path, {String? mimeType}) async {
    if (explode) throw StateError('share sheet blew up');
    paths.add(path);
    mimeTypes.add(mimeType);
    return outcome;
  }
}

void main() {
  late AppDatabase db;
  late LibraryStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLibraryStore(db);
  });

  tearDown(() => db.close());

  StickerRecord sticker({String id = '1', int usageCount = 0}) => StickerRecord(
    id: id,
    filePath: '/tmp/$id.webp',
    thumbnailPath: '/tmp/${id}_t.webp',
    kind: StickerKind.staticImage,
    packId: null,
    autoTags: const ['dog'],
    manualName: 'Doggo',
    manualTags: const [],
    notes: null,
    source: StickerSource.maker,
    createdAt: DateTime(2026),
    usageCount: usageCount,
    sizeBytes: 50000,
    taggingStatus: TaggingStatus.done,
  );

  Future<int> usageOf(String id) async =>
      (await store.getSticker(id))!.usageCount;

  group('what gets shared', () {
    test('sends the sticker file as image/webp', () async {
      final backend = FakeShareBackend(ShareOutcome.shared);
      await store.saveSticker(sticker());

      await SharingService(backend, store).shareSticker(sticker());

      expect(backend.paths, ['/tmp/1.webp']);
      expect(backend.mimeTypes, ['image/webp']);
    });
  });

  group('usage counting', () {
    // usageCount is NOT a statistic — WhatsApp exposes no usage data, so this is
    // purely a ranking signal feeding search. Counting shares that never
    // happened quietly degrades result ordering in a way nobody would trace
    // back to sharing.

    test('a completed share increments usage exactly once', () async {
      await store.saveSticker(sticker());

      await SharingService(
        FakeShareBackend(ShareOutcome.shared),
        store,
      ).shareSticker(sticker());

      expect(await usageOf('1'), 1);
    });

    test('a DISMISSED share does not increment usage', () async {
      // Same distinction Task 11 drew with ExportCancelledException: a thing the
      // user backed out of must not be recorded as a thing they did.
      await store.saveSticker(sticker());

      await SharingService(
        FakeShareBackend(ShareOutcome.dismissed),
        store,
      ).shareSticker(sticker());

      expect(await usageOf('1'), 0);
    });

    test('an UNDETERMINED outcome counts as a share', () async {
      // share_plus reports `unavailable` when the platform cannot tell what the
      // user did. Deliberately counted, because the alternative is worse: if
      // Android reports this often, refusing to count it leaves usageCount
      // permanently 0 and the ranking signal dead — the field would do nothing
      // at all. Slight over-counting still preserves the useful ordering
      // (stickers you opened the sheet for beat ones you never touched), while
      // a dead signal removes the tiebreaker entirely.
      //
      // Which case Android actually returns is a device question — see the
      // interactive probe. If it reports success/dismissed reliably, this branch
      // rarely fires and costs nothing.
      await store.saveSticker(sticker());

      await SharingService(
        FakeShareBackend(ShareOutcome.unknown),
        store,
      ).shareSticker(sticker());

      expect(await usageOf('1'), 1);
    });

    test('usage accumulates across repeated shares', () async {
      await store.saveSticker(sticker());
      final service = SharingService(
        FakeShareBackend(ShareOutcome.shared),
        store,
      );

      await service.shareSticker(sticker());
      await service.shareSticker(sticker());
      await service.shareSticker(sticker());

      expect(await usageOf('1'), 3);
    });
  });

  group('failure handling', () {
    test('a backend error does not throw at the caller', () async {
      // Sharing is a leaf action. A failure means "it did not send", not
      // "something is broken" — the Maker should not surface a crash.
      await store.saveSticker(sticker());

      await expectLater(
        SharingService(
          FakeShareBackend.throwing(),
          store,
        ).shareSticker(sticker()),
        completes,
      );
    });

    test('a failed share does not increment usage', () async {
      await store.saveSticker(sticker());

      await SharingService(
        FakeShareBackend.throwing(),
        store,
      ).shareSticker(sticker());

      expect(await usageOf('1'), 0);
    });

    test('the outcome is returned so the UI can react', () async {
      await store.saveSticker(sticker());

      expect(
        await SharingService(
          FakeShareBackend(ShareOutcome.dismissed),
          store,
        ).shareSticker(sticker()),
        ShareOutcome.dismissed,
      );
      expect(
        await SharingService(
          FakeShareBackend.throwing(),
          store,
        ).shareSticker(sticker()),
        ShareOutcome.failed,
      );
    });
  });
}
