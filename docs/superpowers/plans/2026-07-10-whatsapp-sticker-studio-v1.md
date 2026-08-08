# WhatsApp Sticker Studio v1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a standalone Android app that makes high-quality WhatsApp stickers (image/GIF/video/Giphy/**X-Twitter link** → compliant 512×512 WebP), auto-tags and stores them in a searchable local library, and exports/shares them into WhatsApp via the official sticker API and share sheet.

**Architecture:** Flutter app with five isolated modules behind interfaces — Sources, Encoder, Library store, Tagger, Search, Exporter/Sharing. Deterministic core logic (models, validation, encoding budget, search ranking) is pure Dart and unit-tested. Platform glue (ML Kit tagging, Giphy API, WhatsApp `ContentProvider`) lives behind the same interfaces with a small Kotlin layer.

**Tech Stack:** Flutter (Dart) · Kotlin (native glue) · `drift` (SQLite + FTS5) · `ffmpeg_kit_flutter` + `libwebp` (encoding) · Google ML Kit on-device (image labeling + OCR, FREE) · on-device TFLite embeddings (FREE) · Giphy HTTP API (free tier) · **minimal FastAPI + yt-dlp/cobalt extraction service** (X/Twitter links only).

## Global Constraints

Copy these verbatim into `lib/core/whatsapp_spec.dart` (Task 2). Every task implicitly depends on them.

- Sticker format: **WebP only**, dimensions **exactly 512×512 px**.
- Size ceilings: **static ≤ 100 KB (102400 bytes)**, **animated ≤ 500 KB (512000 bytes)**.
- Tray icon: **96×96 px, ≤ 50 KB (51200 bytes)**, WebP.
- Pack size: **3–30 stickers per pack**; app exposes **1–10 packs**.
- Animation: **total duration ≤ 10 s (10000 ms)**, **minimum 8 ms per frame**.
- A pack cannot be added silently — user confirms each "Add to WhatsApp".
- **Vision/tagging must be FREE** — on-device ML Kit default; only free-tier hosted adapters allowed. No paid model.
- **X/Twitter extraction is unofficial** — no free official X API; use maintained extractors (yt-dlp/cobalt) server-side; app must degrade gracefully when extraction fails.
- **Git:** commit frequently; **one feature branch per task**; push to GitHub after each task; **never add "Co-authored-by" trailers**; report a task complete **only after its tests pass**.

---

## File Structure

```
whatsapp-sticker-project/
├── CLAUDE.md                      # rules + spec constraints (Task 1)
├── docs/                          # spec + this plan moved here (Task 1 handoff)
├── pubspec.yaml
├── analysis_options.yaml
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── whatsapp_spec.dart     # constants (Task 2)
│   │   └── media.dart             # MediaHandle, MediaKind, StickerKind, FitMode (Task 2)
│   ├── models/
│   │   ├── sticker_record.dart    # (Task 2)
│   │   └── pack_record.dart       # (Task 2)
│   ├── library/
│   │   ├── database.dart          # drift schema (Task 3)
│   │   └── library_store.dart     # LibraryStore interface + impl (Task 3)
│   ├── export/
│   │   ├── sticker_validator.dart # ValidationResult, validatePack (Task 4)
│   │   └── exporter.dart          # Exporter interface + platform impl (Task 11)
│   ├── encoder/
│   │   ├── encoder.dart           # Encoder interface, EncodeParams, EncodedSticker (Task 5)
│   │   ├── static_encoder.dart    # (Task 5)
│   │   └── animated_encoder.dart  # (Task 6)
│   ├── sources/
│   │   ├── source.dart            # Source interface (Task 7)
│   │   ├── gallery_source.dart    # (Task 7)
│   │   ├── camera_source.dart     # (Task 7)
│   │   ├── share_in_source.dart   # (Task 7)
│   │   ├── giphy_source.dart      # (Task 8)
│   │   ├── extraction_client.dart # POST /extract → mp4 url (Task 8B)
│   │   └── xlink_source.dart      # X/Twitter link → MediaHandle (Task 8B)
│   ├── tagger/
│   │   ├── tagging_service.dart   # TaggingService interface, StickerTags (Task 9)
│   │   └── mlkit_tagger.dart      # (Task 9)
│   ├── search/
│   │   └── search_service.dart    # SearchService, SearchHit, ranking (Task 10)
│   ├── sharing/
│   │   └── sharing_service.dart   # single + pack share (Task 12)
│   └── ui/
│       ├── maker_screen.dart      # (Task 13)
│       └── library_screen.dart    # (Task 14)
├── android/app/src/main/kotlin/.../StickerContentProvider.kt  # (Task 11)
├── services/extractor/            # minimal FastAPI + yt-dlp extraction service (Task 8B)
│   ├── main.py                    # POST /extract {url} → {mp4_url, kind}
│   ├── requirements.txt           # fastapi, uvicorn, yt-dlp
│   ├── Dockerfile
│   └── test_extractor.py          # pytest — mocked yt-dlp
└── test/                          # mirrors lib/ ; integration_test/ for e2e (Task 15)
```

---

### Task 1: Repo bootstrap, Flutter scaffold, CI, CLAUDE.md

**Branch:** work directly on `main` for the initial scaffold (bootstrap is not a feature).

**Files:**
- Create: `/home/arjun/whatsapp-sticker-project/` (Flutter project root)
- Create: `CLAUDE.md`, `.gitignore`, `analysis_options.yaml`
- Create: `test/smoke_test.dart`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable Flutter app + green test run + a GitHub remote + green CI.

- [x] **Step 1: Create the Flutter project**

```bash
cd /home/arjun
flutter create --org com.arjun --project-name whatsapp_sticker_studio --platforms=android whatsapp-sticker-project
cd /home/arjun/whatsapp-sticker-project
```

- [x] **Step 2: Write `CLAUDE.md`** (repo-root, so rules load wherever the repo is worked on)

```markdown
# WhatsApp Sticker Studio — Working Rules

## Implementation rules (always)
- Commit frequently. One feature branch per task (`feat/<task>`). Push to GitHub after each task.
- NEVER add "Co-authored-by" trailers to commit messages.
- Full testing before "done": run the test suite; report a task complete only after it passes.

## Product constraints (WhatsApp sticker spec — do not violate)
- WebP only, exactly 512×512. Static ≤ 100 KB, animated ≤ 500 KB. Tray icon 96×96 ≤ 50 KB.
- 3–30 stickers/pack; 1–10 packs. Animation ≤ 10 s, ≥ 8 ms/frame.
- Vision/tagging must be FREE (on-device ML Kit; free-tier hosted only).
- Standalone app: integrate ONLY via official sticker ContentProvider + intent and the OS share sheet. No in-WhatsApp injection.

See docs/ for the full design spec and implementation plan.
```

- [x] **Step 3: Write a smoke test** — `test/smoke_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('smoke: arithmetic sanity', () {
    expect(1 + 1, 2);
  });
}
```

- [x] **Step 4: Run the smoke test**

Run: `flutter test`
Expected: PASS. *(Actual: 2/2 passed — smoke + scaffold widget test.)*

- [x] **Step 4b: Verify the Android build actually works** *(added — tests compile Dart only and do NOT prove the Android build)*

Run: `flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.
*(Actual: initially FAILED with `[CXX1416] Could not find Ninja`. Root cause: the scaffold sets
`ndkVersion`, so Gradle configures a CMake task; only the system `/usr/bin/cmake` was present and it
ships no ninja. Fixed with `sdkmanager "cmake;3.22.1"`, which bundles ninja. Build then succeeded.)*

- [x] **Step 4c: Add CI** *(added — the task title promised CI but the original steps omitted it)*

Create `.github/workflows/ci.yml` running on every push/PR: `dart format` check → `flutter analyze`
→ `flutter test`, then a `build-apk` job for `flutter build apk --debug`. This mechanically enforces
the "full testing before done" rule instead of relying on memory.

- [x] **Step 5: Init git, first commit**

```bash
cd /home/arjun/whatsapp-sticker-project
git init
git add -A
git commit -m "chore: bootstrap Flutter project, CLAUDE.md, smoke test"
```

- [x] **Step 6: Create GitHub repo and push**

```bash
gh repo create whatsapp-sticker-studio --private --source=. --remote=origin --push
```
Expected: repo created; `main` pushed. Verify with `gh repo view --web` or `git remote -v`.

---

### Task 2: Core domain models & spec constants

**Branch:** `feat/domain-models`

**Files:**
- Create: `lib/core/whatsapp_spec.dart`, `lib/core/media.dart`
- Create: `lib/models/sticker_record.dart`, `lib/models/pack_record.dart`
- Test: `test/models/sticker_record_test.dart`, `test/core/whatsapp_spec_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `WhatsAppSpec` constants (see code).
  - `enum MediaKind { image, gif, video }`
  - `enum StickerKind { staticImage, animated }`
  - `enum FitMode { pad, smartCrop, contain }`
  - `class MediaHandle { final Uint8List bytes; final MediaKind kind; final String? mimeType; }`
  - `enum TaggingStatus { pending, done, failed }` (in `sticker_record.dart`)
  - `enum StickerSource { maker, gallery, camera, shareIn, giphy, xLink }` (in `sticker_record.dart`)
  - `StickerRecord` and `PackRecord` — **immutable value types**: every field `final`, a `copyWith()`
    for each, and hand-written `==`/`hashCode` (no new dependency; list fields compared elementwise
    via `package:collection`'s `DeepCollectionEquality`, already a transitive Flutter dep).

```dart
class StickerRecord {
  final String id;
  final String filePath;
  final String thumbnailPath;
  final StickerKind kind;
  final String? packId;
  final List<String> autoTags;
  final String? manualName;
  final List<String> manualTags;
  final String? notes;
  final StickerSource source;
  final DateTime createdAt;
  final int usageCount;
  final int sizeBytes;
  final TaggingStatus taggingStatus;
  const StickerRecord({required this.id, /* … */});
  String searchBlob();
  StickerRecord copyWith({String? manualName, List<String>? manualTags, String? notes,
                          List<String>? autoTags, int? usageCount, TaggingStatus? taggingStatus,
                          String? packId});
}

class PackRecord {
  final String id;
  final String name;
  final String trayIconPath;
  final bool isAnimated;
  final List<String> stickerIds;
  final DateTime createdAt;
  const PackRecord({required this.id, /* … */});
  PackRecord copyWith({String? name, String? trayIconPath, List<String>? stickerIds});
}
```

> **Why immutable + enums:** `taggingStatus`/`source` as `String` invite typo bugs the compiler
> can't catch (`'done'` vs `'Done'`), and mutable records make it impossible to tell whether a
> store returned a fresh row or a caller's aliased object. Value `==` also makes every downstream
> test assert on whole records instead of field-by-field. Later tasks (3, 9, 10, 12) mutate records
> **only** via `copyWith` — no cascade assignment anywhere.

- [x] **Step 1: Write the failing test** — `test/core/whatsapp_spec_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';

void main() {
  test('spec constants match WhatsApp ceilings', () {
    expect(WhatsAppSpec.dimension, 512);
    expect(WhatsAppSpec.maxStaticBytes, 102400);
    expect(WhatsAppSpec.maxAnimatedBytes, 512000);
    expect(WhatsAppSpec.maxTrayBytes, 51200);
    expect(WhatsAppSpec.trayDimension, 96);
    expect(WhatsAppSpec.minStickersPerPack, 3);
    expect(WhatsAppSpec.maxStickersPerPack, 30);
    expect(WhatsAppSpec.maxAnimationMs, 10000);
    expect(WhatsAppSpec.minFrameMs, 8);
  });
}
```

- [x] **Step 2: Run it to see it fail**

Run: `flutter test test/core/whatsapp_spec_test.dart`
Expected: FAIL — `whatsapp_spec.dart` not found.

- [x] **Step 3: Implement constants** — `lib/core/whatsapp_spec.dart`

```dart
class WhatsAppSpec {
  static const int dimension = 512;
  static const int trayDimension = 96;
  static const int maxStaticBytes = 102400;   // 100 KB
  static const int maxAnimatedBytes = 512000;  // 500 KB
  static const int maxTrayBytes = 51200;       // 50 KB
  static const int minStickersPerPack = 3;
  static const int maxStickersPerPack = 30;
  static const int minPacks = 1;
  static const int maxPacks = 10;
  static const int maxAnimationMs = 10000;
  static const int minFrameMs = 8;
}
```

- [x] **Step 4: Implement `media.dart`** — enums + `MediaHandle` (see Interfaces block; `import 'dart:typed_data';`).

- [x] **Step 5: Write failing test for `StickerRecord.searchBlob()`** — `test/models/sticker_record_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/models/sticker_record.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';

void main() {
  test('searchBlob concatenates all searchable text', () {
    final r = StickerRecord(
      id: '1', filePath: 'a.webp', thumbnailPath: 't.webp',
      kind: StickerKind.animated, packId: null,
      autoTags: ['dog', 'high five'], manualName: 'Arjun high five',
      manualTags: ['friends'], notes: 'inside joke',
      source: StickerSource.maker, createdAt: DateTime(2026), usageCount: 0,
      sizeBytes: 400000, taggingStatus: TaggingStatus.done,
    );
    final blob = r.searchBlob().toLowerCase();
    for (final term in ['dog', 'high five', 'arjun', 'friends', 'inside joke']) {
      expect(blob.contains(term), isTrue, reason: 'missing "$term"');
    }
  });
}
```

- [x] **Step 5b: Write failing tests for value equality and `copyWith`** — same file:

```dart
test('records with identical field values are equal', () {
  expect(sample(), equals(sample()));
  expect(sample().hashCode, equals(sample().hashCode));
});

test('records differing in a list element are not equal', () {
  expect(sample(), isNot(equals(sample().copyWith(autoTags: ['cat']))));
});

test('copyWith changes only the named field', () {
  final bumped = sample().copyWith(usageCount: 5);
  expect(bumped.usageCount, 5);
  expect(bumped.copyWith(usageCount: 0), equals(sample()));
});
```

- [x] **Step 6: Implement `StickerRecord` and `PackRecord`** — all fields `final`; `searchBlob()`
  returns `[autoTags, manualName, manualTags, notes].join(' ')` with nulls skipped; `copyWith()` per
  the Interfaces block; hand-written `==`/`hashCode` for the list fields (a plain `==` on `List`
  compares identity and would make Step 5b's first test fail). Declare `TaggingStatus` and
  `StickerSource` in `sticker_record.dart`.

  *(Actual: used **`listEquals` from `package:flutter/foundation.dart`** rather than the planned
  `DeepCollectionEquality` — identical behaviour for our flat `List<String>` fields, and it is
  already a declared dependency, so no new package. Hashing uses `Object.hashAll`, since
  `List.hashCode` is identity-based too.*

  *Also unplanned: `copyWith`'s **nullable** params are typed `Object?` defaulting to a private
  `_unset` sentinel. The naive `String?` form cannot distinguish `copyWith()` from
  `copyWith(manualName: null)` — both arrive as `null` — making it impossible to ever clear
  `packId`, `manualName` or `notes`. Clearing `packId` is how a sticker leaves a pack, so this is
  load-bearing, not academic. Non-nullable params keep the plain `?? this.x` form.)*

- [x] **Step 7: Run model tests**

Run: `flutter test test/models test/core`
Expected: PASS. *(Actual: 20/20 pass across the whole suite; `dart format` and `flutter analyze`
clean. `dart format` did rewrite `test/core/media_test.dart` — CI would have failed on it, so run
the format check locally before pushing, not just `flutter test`.)*

- [x] **Step 8: Commit & push**

```bash
git checkout -b feat/domain-models
git add -A && git commit -m "feat: core spec constants and domain models"
git push -u origin feat/domain-models
```

---

### Task 3: Library store (drift/SQLite + CRUD + usage)

**Branch:** `feat/library-store`

**Files:**
- Create: `lib/library/database.dart` (drift tables), `lib/library/library_store.dart`
- Modify: `pubspec.yaml` (add `drift`, `sqlite3_flutter_libs`, `path_provider`, `path`; dev `drift_dev`, `build_runner`)
- Test: `test/library/library_store_test.dart` (in-memory drift DB)

**Interfaces:**
- Consumes: `StickerRecord`, `PackRecord` (Task 2).
- Produces:
```dart
abstract class LibraryStore {
  Future<void> saveSticker(StickerRecord r);
  Future<StickerRecord?> getSticker(String id);
  Future<List<StickerRecord>> allStickers();
  // manualName/notes are Object? with an _unset sentinel default (as StickerRecord.copyWith),
  // so `notes: null` clears the note and an omitted arg leaves it untouched — a plain String?
  // cannot tell those apart. manualTags has no null state (empty list = "no tags").
  Future<void> updateMetadata(String id, {Object? manualName, List<String>? manualTags, Object? notes});
  Future<void> setAutoTags(String id, List<String> tags);      // sets taggingStatus = TaggingStatus.done
  Future<void> incrementUsage(String id);
  Future<void> savePack(PackRecord p);
  Future<PackRecord?> getPack(String id);
  Future<List<PackRecord>> allPacks();
}
```

- [x] **Step 1: Add dependencies** — edit `pubspec.yaml`, then `flutter pub get`. *(Actual: `drift`
  2.28, `sqlite3_flutter_libs`, `path_provider`, `path`; dev `drift_dev`, `build_runner`.)*
- [x] **Step 2: Write the failing test** — round-trip a sticker, update metadata, increment usage.
  *(Actual: went broader than the sketch below — 15 tests covering all 9 methods plus round-trip
  fidelity of enums and list fields, and the omitted-vs-null-vs-set cases of `updateMetadata`. Two of
  those caught real bugs; see Steps 5–6.)*

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:whatsapp_sticker_studio/library/database.dart';
import 'package:whatsapp_sticker_studio/library/library_store.dart';
// ... build a StickerRecord (as in Task 2 test)

void main() {
  late LibraryStore store;
  setUp(() => store = DriftLibraryStore(AppDatabase(NativeDatabase.memory())));

  test('save then get returns the sticker', () async {
    await store.saveSticker(sample);
    final got = await store.getSticker('1');
    expect(got!.manualName, sample.manualName);
  });

  test('incrementUsage bumps count', () async {
    await store.saveSticker(sample);
    await store.incrementUsage('1');
    expect((await store.getSticker('1'))!.usageCount, 1);
  });
}
```

- [x] **Step 3: Run it to see it fail** — `flutter test test/library` → FAIL (no `database.dart`).
- [x] **Step 4: Define drift tables** in `database.dart` (Stickers, Packs; list columns stored as
  JSON text via a `StringListConverter` `TypeConverter`; `kind`/`source`/`taggingStatus` via drift's
  `textEnum`, which persists the enum **name** — not `intEnum`, whose index would silently remap
  existing rows if the enum is ever reordered), then `dart run build_runner build`. *(Actual: the
  `--delete-conflicting-outputs` flag is now a no-op — this build_runner deletes stale outputs by
  default. **`database.g.dart` is committed** — CI does not run the generator, and it is clean under
  `dart format` and `flutter analyze` as generated.)*
- [x] **Step 5: Implement `DriftLibraryStore`** mapping rows ↔ records. Mutating methods
  (`updateMetadata`, `setAutoTags`, `incrementUsage`) read the row, apply `copyWith`, and write back
  — records are immutable, so nothing is mutated in place.

  **Two non-obvious bugs the tests caught, both about clearing a field to null:**
  1. **Interface/impl default mismatch.** The `_unset` sentinel default for `updateMetadata`'s
     nullable params must be declared on **both** the abstract `LibraryStore` and the concrete class.
     Dart resolves an optional param's default from the *statically-typed* target; a caller holding a
     `LibraryStore` uses the interface's default. If only the impl had `_unset`, "omitted" and
     "passed null" collapsed to the same value and clearing was impossible.
  2. **drift `nullToAbsent` on upsert.** `saveSticker` must build an explicit **Companion**
     (`StickersCompanion` with `Value(null)`), not pass a plain data-class row, to
     `insertOnConflictUpdate`. A data class serialises nulls as *absent*, so an upsert over an
     existing row leaves the old value instead of clearing it — a note could never be deleted.
- [x] **Step 6: Run tests** — `flutter test test/library` → PASS *(15/15; full suite 35/35, analyze +
  format clean, debug APK builds with drift's native SQLite)*.
- [x] **Step 7: Commit & push** on `feat/library-store`. *(Merged to `main` as aaeee13.)*

---

### Task 4: Sticker/pack validator (pure ceiling enforcement)

**Branch:** `feat/validator`

**Files:**
- Create: `lib/export/media_probe.dart` (`MediaProbe` interface + `ProbeResult`), `lib/export/webp_media_probe.dart` (real WebP-header reader), `lib/export/sticker_validator.dart`
- Test: `test/export/sticker_validator_test.dart` (against a `FakeMediaProbe`), `test/export/webp_media_probe_test.dart` (real WebP fixtures)

**Interfaces:**
- Consumes: `WhatsAppSpec`, `PackRecord`, `StickerRecord`, `MediaProbe`.
- Produces:
```dart
class ProbeResult { final int width; final int height; final String format; // 'webp', 'png', ...
  const ProbeResult({required this.width, required this.height, required this.format}); }
abstract class MediaProbe { Future<ProbeResult> probe(String filePath); }

class ValidationResult { final bool ok; final List<String> problems;
  const ValidationResult(this.ok, this.problems); }
class StickerValidator {
  StickerValidator(this._probe);           // MediaProbe injected
  Future<ValidationResult> validateSticker(StickerRecord s);       // probes the real file
  Future<ValidationResult> validatePack(PackRecord pack, List<StickerRecord> stickers);
}
```

> **Why `MediaProbe` (decided 2026-07-24).** `StickerRecord` stores `sizeBytes` + `kind` but no pixel
> dimensions or format, so a record-only validator would *trust* that 512×512 holds rather than verify
> it. Every sticker is encoder-produced today, so the invariant holds by construction — but that breaks
> for on-disk corruption or v2's "import existing `.webp`" path. `MediaProbe.probe(path)` reads the
> **real file header** (WebP dimensions live in the first ~30 bytes) so `validateSticker` checks actual
> bytes, not a record field. The interface is injected so validator tests use a `FakeMediaProbe` and
> stay fast/file-less; `WebpMediaProbe` is verified separately against real WebP fixtures. This makes
> `validateSticker`/`validatePack` **async**.

- [x] **Step 1: Write failing validator tests** against a `FakeMediaProbe` — `test/export/sticker_validator_test.dart`:

```dart
// FakeMediaProbe returns a fixed ProbeResult (default 512x512 webp) so tests
// need no real files. Helpers: stickerOf(bytes, kind, {path}), packOf(count, {isAnimated}).

test('pack with <3 stickers fails', () async {
  final r = await v.validatePack(packOf(2), stickersOf(2));
  expect(r.ok, isFalse);
  expect(r.problems.any((p) => p.contains('at least 3')), isTrue);
});
test('animated sticker >500KB fails', () async {
  expect((await v.validateSticker(stickerOf(600000, StickerKind.animated))).ok, isFalse);
});
test('static sticker >100KB fails', () async {
  expect((await v.validateSticker(stickerOf(150000, StickerKind.staticImage))).ok, isFalse);
});
test('non-512 dimensions fail (probe returns 500x512)', () async {
  final v = StickerValidator(FakeMediaProbe(width: 500));
  final r = await v.validateSticker(stickerOf(50000, StickerKind.staticImage));
  expect(r.ok, isFalse);
  expect(r.problems.any((p) => p.contains('512')), isTrue);
});
test('non-webp format fails (probe returns png)', () async {
  final v = StickerValidator(FakeMediaProbe(format: 'png'));
  expect((await v.validateSticker(stickerOf(50000, StickerKind.staticImage))).ok, isFalse);
});
test('valid pack passes', () async {
  final r = await v.validatePack(packOf(5), stickersOf(5, bytes: 400000));
  expect(r.ok, isTrue);
  expect(r.problems, isEmpty);
});
test('all problems are collected, not short-circuited', () async {
  // <3 stickers AND one oversize: expect >=2 distinct problems.
  final r = await v.validatePack(packOf(2), [
    stickerOf(600000, StickerKind.animated), stickerOf(400000, StickerKind.animated),
  ]);
  expect(r.problems.length, greaterThanOrEqualTo(2));
});

// Kind homogeneity — real WhatsApp rule (see note).
test('animated pack containing a static sticker fails', () async {
  final r = await v.validatePack(packOf(3, isAnimated: true), [
    stickerOf(400000, StickerKind.animated),
    stickerOf(400000, StickerKind.animated),
    stickerOf(50000, StickerKind.staticImage), // intruder
  ]);
  expect(r.ok, isFalse);
  expect(r.problems.any((p) => p.contains('animated')), isTrue);
});
test('static pack containing an animated sticker fails', () async {
  final r = await v.validatePack(packOf(3, isAnimated: false), [
    stickerOf(50000, StickerKind.staticImage),
    stickerOf(50000, StickerKind.staticImage),
    stickerOf(400000, StickerKind.animated),
  ]);
  expect(r.ok, isFalse);
});
```

> **Kind homogeneity is a real WhatsApp rule and was missing from this task.** Packs must be
> all-static or all-animated — `animated_sticker_pack` is a pack-level flag that also selects the
> size ceiling. WhatsApp enforces this **independently of our code** (see `CLAUDE.md`), so the
> validator must catch it before we fire the intent, or the user gets an opaque rejection.
>
> This validator is the **backstop, not the UX**. Per the 2026-07-18 decision, the Maker
> (Task 13) auto-promotes a static sticker to animated (≥2 identical frames) when it joins an
> animated pack, so a mixed pack should never reach here. Reaching this rule means promotion failed
> or was skipped — a bug, not a user error.

- [x] **Step 2: Run → FAIL** (no `sticker_validator.dart` / `media_probe.dart`).
- [x] **Step 3: Implement `MediaProbe` + `StickerValidator`.** `validateSticker`: probe the file →
  check `width==512 && height==512`, `format=='webp'`, and size-by-kind. `validatePack`: count 3–30,
  every `kind` matches `pack.isAnimated`, delegate each sticker to `validateSticker`. **Collect all
  problems, don't short-circuit** — a user with three issues should see three messages. Problem
  strings are user-facing (Task 11 surfaces them), so make them specific and friendly.
- [x] **Step 4: Run → PASS.**
- [x] **Step 5: Write failing `WebpMediaProbe` tests** — `test/export/webp_media_probe_test.dart`
  against real fixtures: a genuine 512×512 WebP returns `(512, 512, 'webp')`; a non-WebP (e.g. a PNG,
  or truncated bytes) is reported as a different `format` or a probe error, not silently passed.
- [x] **Step 6: Implement `WebpMediaProbe`** — parse the RIFF/WEBP header (`VP8 `/`VP8L`/`VP8X`
  chunks) to read width/height and confirm the `WEBP` FourCC. No new dependency if the header parse is
  hand-rolled; otherwise reuse the `image` package once Task 5 adds it.
- [x] **Step 7: Run → PASS**, then full suite + format + analyze.
- [x] **Step 8: Commit & push** on `feat/validator`. *(Merged to `main` as ec96177.)*

---

### Task 5: Encoder — static images

**Branch:** `feat/encoder-static`

> **Reshaped 2026-07-24 — the `image` package cannot encode WebP** (confirmed in its docs: decode
> only). Real WebP byte-encoding needs native libwebp, which only runs on a device — so Task 5 splits
> into a **pure-Dart geometry half (built + unit-tested now)** and a **native WebP-encode half behind
> an injected `WebpEncoder` interface (device-verified with Task 6)**. `StaticEncoder` does
> decode→fit→512²-bitmap, then delegates the bytes to a `WebpEncoder`: faked in tests, real on device.

**Files:**
- Create: `lib/encoder/encoder.dart` (interface + params + `EncoderException`),
  `lib/encoder/webp_encoder.dart` (`WebpEncoder` interface + `WebpEncodeResult`),
  `lib/encoder/static_encoder.dart`
- Modify: `pubspec.yaml` (add `image` — decode/resize/crop only; it does **not** encode WebP)
- Test: `test/encoder/static_encoder_test.dart` (geometry, against a `FakeWebpEncoder`; fixtures
  generated in-test with `image` so no binary assets are committed)

**Interfaces:**
- Consumes: `MediaHandle`, `FitMode`, `WhatsAppSpec`, `StickerKind`, `WebpEncoder`.
- Produces:
```dart
class EncodeParams { final FitMode fitMode; final Duration? trim; const EncodeParams({this.fitMode = FitMode.pad, this.trim}); }
class QualityReport { final int fps; final int frames; final int quality; final int sizeBytes; }
class EncodedSticker { final Uint8List webpBytes; final StickerKind kind; final int width; final int height; final int sizeBytes; final QualityReport report; }
abstract class Encoder { Future<EncodedSticker> encode(MediaHandle input, EncodeParams params); }

class WebpEncodeResult { final Uint8List bytes; final int quality; }
abstract class WebpEncoder {
  // Encode a width×height RGBA bitmap to WebP under maxBytes, stepping quality down as needed.
  Future<WebpEncodeResult> encode(Uint8List rgba, {required int width, required int height, required int maxBytes});
}
```

- [x] **Step 1: Write failing geometry tests** — `test/encoder/static_encoder_test.dart`, against a
  `FakeWebpEncoder` that records the RGBA/dims/maxBytes it receives and returns canned bytes+quality.
  Fixtures generated in-test (`img.Image` filled solid, `encodePng`). Cover:
  - a landscape input → `EncodedSticker` is 512×512, `kind == staticImage`, `report.frames == 1`;
  - `pad` on a portrait → the fitted bitmap has **transparent side bars and an opaque centre** (no
    stretch), verified by reading alpha out of the RGBA the fake captured;
  - `smartCrop` on a portrait → the frame is **fully opaque** (cropped to fill, no padding);
  - `encode` delegates with `maxBytes == WhatsAppSpec.maxStaticBytes`, and passes the encoder's
    `bytes`/`quality` through to `EncodedSticker`/`QualityReport`;
  - undecodable bytes → throws `EncoderException`.
- [x] **Step 2: Run → FAIL.**
- [x] **Step 3: Implement `Encoder` types, `WebpEncoder` interface, and `StaticEncoder`.** Decode with
  `image`; `_fit` switches exhaustively over `FitMode` — `pad`/`contain` letterbox onto a transparent
  512² canvas via `compositeImage(center: true)`; `smartCrop` centre-crops to square then resizes
  (subject-aware detection deferred to v1.1). Extract RGBA and delegate to the injected `WebpEncoder`.
- [x] **Step 4: Run → PASS** (pure Dart, no device).
- [x] **Step 5: Commit & push** the device-free half on `feat/encoder-static`.
- [x] **Step 5b (device session): implement the real `WebpEncoder`** over libwebp/`ffmpeg_kit` (pairs
  with Task 6), stepping quality 100→90→…→50 until ≤ 100 KB. Device-verify: real photo → genuine
  512×512 WebP ≤ 100 KB, confirmed by the `WebpMediaProbe` from Task 4.

  *(Actual, 2026-07-29 — **not** ffmpeg. Static WebP uses Android's built-in
  `Bitmap.compress(WEBP_LOSSY)` via a `MethodChannel` (`WebpEncoderChannel.kt` +
  `lib/encoder/native_webp_encoder.dart`). No dependency, and it compresses **in memory** — the
  ladder re-encodes up to six times, and routing that through ffmpeg would mean six process spawns
  and six temp-file round-trips every time the Maker refreshes its live readout. ffmpeg is still
  needed for Task 6, since Android has **no built-in animated-WebP encoder at any API level**.*

  *Three implementation notes worth not rediscovering:*
  - *Encoding runs on a background `Executor`, but **every** reply — success **and** error — is
    posted back via `Handler(Looper.getMainLooper())`. `MethodChannel.Result` is not thread-safe.*
  - *RGBA→ARGB packing is explicit (`setPixels` with `0xAARRGGBB` ints), **not**
    `copyPixelsFromBuffer`, which copies raw bytes assuming an in-memory order that is not RGBA
    everywhere and silently swaps red/blue where it is wrong. Alpha is load-bearing here.*
  - *Kotlin `Byte` is signed, so every channel needs `and 0xFF` or values above 127 come out wrong.*

  *Device-verified on A059P / Android 16 (API 36), 4 integration tests in
  `integration_test/native_webp_encoder_test.dart`: probe-confirmed 512×512 WebP ≤ 100 KB; **lossy
  WebP preserves alpha**, so `pad`'s letterbox bars stay transparent (the main risk in choosing
  Android's encoder); the ladder demonstrably steps below 100 on detailed input; and an input that
  cannot fit is **refused** rather than silently overshooting.*

  *Test-fixture lesson: uniform random noise is maximum-entropy and will not fit under 100 KB at any
  quality (smallest was 139 KB at q50). Use structured, photo-like fixtures to exercise the ladder;
  keep a noise fixture only to pin the refusal path.*

---

### Task 6: Encoder — animated (GIF/video)

**Branch:** `feat/encoder-animated`

**Files:**
- Create: `lib/encoder/animated_encoder.dart`
- Modify: `pubspec.yaml` — **done 2026-07-29**: `ffmpeg_kit_flutter_new_video: ^2.4.3`.

> **The originally-named `ffmpeg_kit_flutter` is DEAD — do not try to use it.** FFmpegKit was retired
> 2026-01-06 and its native binaries were pulled from Maven Central/CocoaPods on 2026-04-01, so it
> cannot build at all. `ffmpeg_kit_flutter_new` is the maintained community fork (FFmpeg 8.1.2,
> minSdk 24 — matches this project exactly).
>
> **Take the `_video` variant, not the plan's original "min GPL" wording.** `_video` is the smallest
> variant that ships **libwebp** (needed to mux animated WebP); `_full` and the unsuffixed package
> add x264/x265 under **GPL**, whose obligations would attach to the distributed app. We only
> *decode* H.264 (FFmpeg's built-in decoder, no external lib) and only *encode* WebP, so LGPL
> `_video` is sufficient. Verified: debug APK builds and links against it.
>
> Known warning, not yet blocking: the plugin applies its own Kotlin Gradle Plugin, which Flutter
> warns future versions will reject. Revisit if a Flutter upgrade breaks the build.
- Test: `integration_test/animated_encoder_test.dart` (runs on a device/emulator — ffmpeg needs the platform)

**Interfaces:**
- Consumes: `MediaHandle` (gif/video), `EncodeParams` (uses `trim`), `WhatsAppSpec`.
- Produces: `EncodedSticker` with `kind == StickerKind.animated`.

- [x] **Step 1: Verify the ffmpeg package variant** exposes animated-WebP muxing. *(DONE 2026-07-29,
  device-verified — `integration_test/ffmpeg_webp_probe_test.dart`.)*

Run (in `integration_test`): encode a 3 s test mp4 to animated webp via an FFmpeg command; assert exit code success. If the chosen variant lacks libwebp, switch variants before proceeding. Document the working variant in `CLAUDE.md`.

  *(Actual: runtime reports variant `video` with libwebp present, and produces genuine multi-frame
  output — chunks `[VP8X, ANIM, ANMF×6]`. The test **parses the RIFF chunk list** rather than
  searching the bytes for 'ANMF', because compressed payloads can contain those bytes by chance and
  a still image would otherwise look animated. Note the build has **no H.264 encoder** (x264 is GPL
  and correctly absent); irrelevant, since we only decode H.264 and only encode WebP.)*

- [x] **Step 2: Write failing integration test** — trim to ≤ 10 s, output ≤ 500 KB, 512×512, animated:

```dart
testWidgets('animated encode ≤500KB, ≤10s, 512²', (t) async {
  final out = await AnimatedEncoder().encode(videoHandle, const EncodeParams(trim: Duration(seconds: 6)));
  expect(out.sizeBytes, lessThanOrEqualTo(512000));
  expect(out.width, 512);
  expect(out.report.frames * out.report.fps <= 10 * out.report.fps, isTrue);
  expect((1000 / out.report.fps) >= 8, isTrue); // ≥8ms/frame
});
```

- [x] **Step 3: Run → FAIL.**
- [x] **Step 4: Implement `AnimatedEncoder`** with **progressive degradation** to hit 500 KB: pipeline = trim (≤10 s) → scale/pad to 512² → encode animated WebP at target fps/quality; if oversize, degrade in order **fps (15→12→10→8) → drop frames → quality → dimension-internal** until ≤ 500 KB, recording each choice in `QualityReport`. Never emit an oversize file — if the floor still exceeds 500 KB, throw `EncoderBudgetException` for the UI to surface.

> **Do not budget as `500 KB ÷ frame count`.** Animated WebP uses **inter-frame compression** — after
> the keyframe, each frame stores only the changed-pixel rectangle. Cost therefore scales with *visual
> change*, not frame count: a static-background clip stays cheap at 15 fps, while a pan or scene-cut
> blows the budget at 8 fps. Consequences for this task:
> - Never assume dropping fps is the highest-leverage lever. **Measure**: encode, check bytes, then
>   degrade. The ladder above is the order to *try*, not a formula to predict from.
> - **Trimming duration beats degrading quality** for high-motion sources, and the user controls
>   duration. Task 13's UI must surface the size/quality readout so they can shorten the clip rather
>   than accept a mushy sticker. Most good animated stickers are 1.5–3 s loops, not the full 10 s.
> - A scene cut mid-clip forces a new keyframe. If a source blows the budget, check for cuts before
>   assuming the whole clip is too complex.

> **⚠️ MEASURED 2026-07-29 — the note above is WRONG for this toolchain. Cost is ~LINEAR IN FRAME
> COUNT.** On device: 10 identical frames = **10.09×** one frame, 40 = **40.28×**, and *moving*
> content came within **2%** of *identical* content. FFmpeg's webp muxer encodes each frame
> independently rather than diffing. Switching to `-c:v libwebp_anim` (which does drive libwebp's
> `WebPAnimEncoder`) recovers only ~16%. Consequences:
> - Usable frames ≈ **500 KB ÷ per-frame cost**. Simple sticker art (flat background, small moving
>   subject) runs ~1.8 KB/frame and *can* fill the full 10 s; detailed content runs several KB/frame
>   and **cannot** — long stickers are only reachable for simple art.
> - **fps and duration are therefore the dominant levers**, which vindicates the fps-first ladder
>   above but for the opposite reason to the one given. Task 13 should push *trimming* over quality.
> - Still **encode and measure** rather than predicting — per-frame cost varies with content.
> - `promoteStatic` **must use plain `-c:v libwebp`**: `libwebp_anim` diffs two identical frames to
>   nothing and collapses them into one, which WhatsApp rejects exactly like a static file.
- [x] **Step 5: Run → PASS** — on the real device (A059P/API 36), not an emulator. 7 tests in
  `integration_test/animated_encoder_test.dart`: GIF source, MP4 source, transparent pad bars, trim,
  the 10 s cap, budget refusal, and promotion.

- [x] **Step 5b: Implement static→animated promotion** *(added 2026-07-18 — see `CLAUDE.md`)*

  Add `Future<EncodedSticker> promoteStatic(Uint8List staticWebp)`: re-encode a static image as an
  animated WebP of **≥2 identical frames**, each ≥8 ms. Used when a static sticker joins an animated
  pack, so the user never sees a mixed-kind error.

  **A single frame does not work** — WhatsApp's validator tests `getFrameCount() <= 1`, not whether
  an ANIM chunk exists, so a 1-frame file is rejected exactly like a static one. Two frames is the
  floor; there is no minimum total duration.

  Failing test first: promoting a static yields `kind == StickerKind.animated`, `report.frames >= 2`,
  every frame duration ≥ `WhatsAppSpec.minFrameMs`, total ≤ `maxAnimationMs`, and size ≤
  `maxAnimatedBytes` (note the ceiling is now 500 KB, not 100 KB — promotion *raises* the budget).

  Verify on a device against WhatsApp's **closed-source** validator, which is stricter than the
  published sample. **If it rejects the promoted sticker, fall back to pack-type-chosen-at-creation**
  (Sticker.ly's model) and revisit Task 13's flow.

- [x] **Step 6: Commit & push** — done on `feat/encoder-native` (shared with Task 5b, since both
  hinge on the same encoding-stack decisions) rather than a separate `feat/encoder-animated`.

---

### Task 7: Sources — gallery, camera, share-in

**Branch:** `feat/sources`

**Files:**
- Create: `lib/sources/source.dart`, `gallery_source.dart`, `camera_source.dart`, `share_in_source.dart`
- Modify: `pubspec.yaml` (`image_picker`; `receive_sharing_intent` for share-into-app), Android manifest (share intent filters)
- Test: `test/sources/source_contract_test.dart` (against a `FakeSource`)

**Interfaces:**
- Consumes: `MediaHandle`, `MediaKind`.
- Produces: `abstract class Source { Future<MediaHandle?> pick(); }` and the three implementations. `pick()` returns `null` on user-cancel.

> **Share-into-app is a first-class entry point (see spec §4.1), not a minor source.** Registering as
> an OS share target lets a shared screenshot / screen recording / gallery item open straight into the
> Maker — the same "Share → …" gesture users know, and **API-independent** (it does not touch the
> WhatsApp sticker API, so it survives any change to that API). Treat it as a headline feature.

- [x] **Step 1: Write the contract test** — `FakeSource` returns a `MediaHandle`; assert non-null bytes and a valid `MediaKind`; a cancelling source returns `null`.
- [x] **Step 2: Run → FAIL.**
- [x] **Step 3: Implement** `GallerySource`/`CameraSource` over `image_picker`; map picked files → `MediaHandle` (infer `MediaKind` from mime/extension). `pick()` returns `null` on cancel.
- [x] **Step 3b: Implement the share-in target** — `ShareInSource` over `receive_sharing_intent`:
  - Android manifest: add `<intent-filter>` for `ACTION_SEND` and `ACTION_SEND_MULTIPLE` on
    `image/*` and `video/*` to the launcher activity.
  - Handle **both** delivery cases the package exposes: the **cold-start** stream
    (`getInitialMedia`, app launched *by* the share) and the **warm** stream (`getMediaStream`, app
    already running). Missing the warm case drops shares silently when the app is backgrounded.
  - Map the shared file(s) → `MediaHandle`, inferring `MediaKind` from mime/extension.
  - **iOS Share Extension is deferred with iOS** (project is Android-only). Note this in `CLAUDE.md`
    so it is a known gap, not a forgotten one.
- [x] **Step 4: Run contract test → PASS.** (Real picker + real share-sheet flows verified manually
  on device — the share intent-filters and cold/warm streams can only be exercised on a phone.)
- [x] **Step 5: Commit & push** on `feat/sources`.

  *(Actual, 2026-08-01, device-verified on A059P / Android 16.)*
  - *Pickers confirmed with real phone media: gallery image 682 KB → 70 KB static; **gallery video
    1.5 MB → 463 KB animated, 72 frames**; camera photo 1 MB → 67 KB; cancel returns `null`.*
  - ***`image_picker` supplies NO mime type on Android*** *— every pick reported "(none supplied)".
    `MediaKindResolver`'s extension branch is the **primary** path, not a fallback; a mime-first-only
    resolver returns `null` for every pick. Do not "simplify" it away.*
  - ***`launchMode` must be `singleTask`***, *not Flutter's default `singleTop`: a share into a
    backgrounded app arrives from another task.*
  - ***Format support is narrower than assumed.*** *`heic`/`heif`/`avif` are **rejected** — the Dart
    `image` package has no decoder for them and HEIC is a common phone camera format. Rejecting is a
    workaround; the fix (ffmpeg transcode fallback) is tracked separately.*
  - ***`compileSdk` pinned to 37*** *— `receive_sharing_intent` fails the build below it. Does not
    raise `minSdk`/`targetSdk`.*
  - ***No Android permissions added, deliberately*** *— the Photo Picker grants per-item access, and
    declaring `CAMERA` would only make it mandatory at runtime.*
  - ***Warm share-in is NOT verifiable from `integration_test`*** *and its probe is `skip`ped with the
    reasoning inline: `flutter test` uninstalls the app at the end of a run (so a cached share-sheet
    icon points at a missing package), and a real share launches `MainActivity` into the **sharing**
    app's task — a different Flutter engine from the test's. **Proven anyway:** the OS resolves us as
    a share target and a real share starts our activity. Only Dart-side receipt is unverified —
    observable at **Task 15**, where the cold path should be checked too.*

---

### Task 8: Giphy source

**Branch:** `feat/giphy-source`

**Files:**
- Create: `lib/sources/source.dart` (the `Source` interface, pulled forward from Task 7),
  `lib/sources/giphy_client.dart`, `lib/sources/giphy_source.dart`
- Modify: `pubspec.yaml` (`http`); real `GIPHY_API_KEY` supplied via `--dart-define` at runtime
- Test: `test/sources/giphy_client_test.dart`, `test/sources/giphy_source_test.dart` (mock `http.Client`, no network)

**Interfaces:**
- Consumes: `http.Client`, `MediaHandle`, `Source`.
- Produces: `class GiphyClient { Future<List<GiphyGif>> search(String q, {int limit}); }`, `class GiphyGif { String id; String title; Uri previewUrl; Uri mp4Url; }`, and `GiphySource implements Source` (returns the chosen gif's mp4 as a `MediaHandle` of kind `video`).

- [x] **Step 1: Verify Giphy API terms** — free key needs no verification for the mocked tests; real
  key + rate limits/attribution recorded in `CLAUDE.md` when the user creates one (live-verify step).
- [x] **Step 2: Write failing tests** — `GiphyClient.search` parses a canned JSON fixture into
  `GiphyGif`s via a `MockClient`; `GiphySource.pick()` downloads the mp4 into a `MediaHandle`.
- [x] **Step 3: Run → FAIL.**
- [x] **Step 4: Implement** the `Source` interface, `GiphyClient` (GET `/v1/gifs/search`), and
  `GiphySource` (downloads the chosen gif's mp4 → `MediaHandle`, `null` on a failed download).
  *(Actual: parser skips a malformed gif rather than failing the whole search; `apiKey` made a public
  initializing formal to satisfy `prefer_initializing_formals`.)*
- [x] **Step 5: Run → PASS** *(7 source tests; full suite 66/66; format + analyze clean; debug APK
  builds).*
- [x] **Step 6: Commit & push** on `feat/giphy-source`. *(Merged to `main` as 65c7724.)*

**Deferred (runtime, non-blocking):** live-verify `GiphyClient` against the real API once the user's
free key exists (`--dart-define=GIPHY_API_KEY=…`, never committed); record real rate limits +
"Powered by GIPHY" attribution in `CLAUDE.md`. The *browsing/selection* UI (pick which gif) is the
Maker's job (Task 13); `GiphySource` only fetches the already-chosen gif.

---

### Task 8B: X/Twitter link → sticker (extraction service + XLinkSource)

**Branch:** `feat/xlink-source`

**Files:**
- Create (backend): `services/extractor/main.py`, `services/extractor/requirements.txt`, `services/extractor/Dockerfile`, `services/extractor/test_extractor.py`
- Create (app): `lib/sources/extraction_client.dart`, `lib/sources/xlink_source.dart`
- Test (app): `test/sources/extraction_client_test.dart`

**Interfaces:**
- Backend HTTP: `POST /extract` with body `{"url": "<tweet url>"}` → `200 {"mp4_url": "<url>", "kind": "video"}`; on failure → `422 {"error": "<reason>"}`.
- Consumes: `MediaHandle`, `MediaKind`, `Source` (Task 7), `http.Client`.
- Produces:
```dart
class ExtractedMedia { final Uri mp4Url; final MediaKind kind; const ExtractedMedia(this.mp4Url, this.kind); }
class ExtractionException implements Exception { final String message; ExtractionException(this.message); }
class ExtractionClient { ExtractionClient(this._http, this._baseUri); Future<ExtractedMedia> extract(String tweetUrl); }
// XLinkSource is constructed with the pasted URL (same pattern as GiphySource holding the chosen gif),
// keeping the arg-less Source.pick() interface intact.
class XLinkSource implements Source { XLinkSource(this._client, this._http, this._tweetUrl); Future<MediaHandle?> pick(); }
```

- [x] **Step 1: Write the failing backend test** — `services/extractor/test_extractor.py` (mock yt-dlp; no network):

```python
from fastapi.testclient import TestClient
from unittest.mock import patch
import main

client = TestClient(main.app)

def test_extract_returns_mp4_url():
    fake_info = {"url": "https://video.twimg.com/x.mp4",
                 "formats": [{"url": "https://video.twimg.com/x.mp4", "ext": "mp4", "vcodec": "h264"}]}
    with patch.object(main, "resolve_info", return_value=fake_info):
        r = client.post("/extract", json={"url": "https://x.com/u/status/1"})
    assert r.status_code == 200
    assert r.json()["mp4_url"].endswith(".mp4")
    assert r.json()["kind"] == "video"

def test_extract_failure_returns_422():
    with patch.object(main, "resolve_info", side_effect=RuntimeError("unavailable")):
        r = client.post("/extract", json={"url": "https://x.com/u/status/1"})
    assert r.status_code == 422
    assert "error" in r.json()
```

- [x] **Step 2: Run it to see it fail**

Run: `cd services/extractor && pip install -r requirements.txt && pytest`
Expected: FAIL — `main` not found.

- [x] **Step 3: Implement the service** — `services/extractor/main.py`:

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import yt_dlp

app = FastAPI()

class ExtractRequest(BaseModel):
    url: str

def resolve_info(url: str) -> dict:
    # extract only; do NOT download the media here
    with yt_dlp.YoutubeDL({"quiet": True, "skip_download": True}) as ydl:
        return ydl.extract_info(url, download=False)

def pick_mp4(info: dict) -> str:
    fmts = [f for f in info.get("formats", []) if f.get("ext") == "mp4" and f.get("url")]
    if not fmts:
        raise RuntimeError("no mp4 variant")
    return max(fmts, key=lambda f: f.get("height") or 0)["url"]

@app.post("/extract")
def extract(req: ExtractRequest):
    try:
        info = resolve_info(req.url)
        return {"mp4_url": pick_mp4(info), "kind": "video"}
    except Exception as e:
        raise HTTPException(status_code=422, detail={"error": str(e)})
```

`requirements.txt`: `fastapi`, `uvicorn`, `yt-dlp`. `Dockerfile`: python-slim, install requirements, `CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]`.

- [x] **Step 4: Run backend tests**

Run: `cd services/extractor && pytest`
Expected: PASS (2 tests).

- [~] **Step 5: Verify real extraction (§9 item)** — *(PARTIAL, 2026-07-25 — see `CLAUDE.md`)*
  Ran the real (unmocked) service locally: it works end-to-end, and **this environment reaches
  Twitter** (yt-dlp's `[twitter]` extractor ran, returned tweet-specific responses — not IP-blocked).
  Error path surfaces yt-dlp messages as 422. **Success path (200 + real `mp4_url`) NOT yet
  confirmed** — the tweets tried had no extractable video. **Next session:** run against a
  known-video tweet URL; if auth-gated from a datacenter IP, add yt-dlp cookies on the deploy target;
  then **pin the working yt-dlp version** and **choose a deploy target** (both noted in `CLAUDE.md`).

- [x] **Step 6: Write the failing Dart client test** — `test/sources/extraction_client_test.dart` (mocked `http.Client`, no network):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/sources/extraction_client.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';

void main() {
  test('parses mp4_url and kind from 200', () async {
    final mock = MockClient((req) async =>
        http.Response('{"mp4_url":"https://video.twimg.com/x.mp4","kind":"video"}', 200));
    final client = ExtractionClient(mock, Uri.parse('http://localhost:8000'));
    final media = await client.extract('https://x.com/u/status/1');
    expect(media.mp4Url.toString(), endsWith('.mp4'));
    expect(media.kind, MediaKind.video);
  });

  test('throws ExtractionException on 422', () async {
    final mock = MockClient((req) async => http.Response('{"error":"unavailable"}', 422));
    final client = ExtractionClient(mock, Uri.parse('http://localhost:8000'));
    expect(() => client.extract('https://x.com/u/status/1'),
           throwsA(isA<ExtractionException>()));
  });
}
```

- [x] **Step 7: Run it to see it fail** — `flutter test test/sources/extraction_client_test.dart` → FAIL (no `extraction_client.dart`).

- [x] **Step 8: Implement `ExtractionClient` and `XLinkSource`.** `ExtractionClient.extract` POSTs `{url}` to `$_baseUri/extract`; on 200 parse `ExtractedMedia`; else throw `ExtractionException`. `XLinkSource.pick()` calls `extract(_tweetUrl)`, downloads the mp4 bytes via `_http.get`, and returns `MediaHandle(bytes: …, kind: MediaKind.video, mimeType: 'video/mp4')`; on `ExtractionException` returns `null` so the Maker can surface a friendly message (per spec §7).

- [x] **Step 9: Run Dart tests** — `flutter test test/sources` → PASS.

- [x] **Step 10: Commit & push** on `feat/xlink-source` (backend + app together). *(Merged to `main` as 38689db.)*

---

### Task 9: Tagger — ML Kit (FREE, on-device) + stub

**Branch:** `feat/tagger`

**Files:**
- Create: `lib/tagger/tagging_service.dart`, `lib/tagger/mlkit_tagger.dart`, `test/tagger/fake_tagger.dart`
- Modify: `pubspec.yaml` (`google_mlkit_image_labeling`, `google_mlkit_text_recognition`)
- Test: `test/tagger/tagging_contract_test.dart`

**Interfaces:**
- Consumes: image bytes (PNG/WebP), `LibraryStore.setAutoTags`.
- Produces:
```dart
class StickerTags { final List<String> subjects; final String? emotion; final String? action; final String? textInImage; final String? suggestedName; final String? style; List<String> flatten(); }
abstract class TaggingService { Future<StickerTags> tag(Uint8List imageBytes); }
```

- [x] **Step 1: Write the contract test** against `FakeTagger` (returns fixed tags); assert `flatten()` includes subjects + textInImage; assert an orchestrator writes them via `LibraryStore.setAutoTags` and sets `taggingStatus` to `TaggingStatus.done` (and to `TaggingStatus.failed` when `tag()` throws — see spec §7).
- [x] **Step 2: Run → FAIL.**
- [x] **Step 3: Implement `MlKitTagger`** — run on-device Image Labeling (subjects) + Text Recognition (textInImage); map to `StickerTags`. **No network, no key, free.** `suggestedName` = top label. (Optional free-tier hosted VLM adapter is a later drop-in behind `TaggingService` — not built now.)
- [x] **Step 4: Run contract test → PASS.** Real labeling verified on device.
- [x] **Step 5: Commit & push** on `feat/tagger`.

  *(Actual, 2026-08-04 — device-verified on A059P / Android 16. Full detail in `CLAUDE.md`'s
  "Tagger" section.)*
  - ***ML Kit models are BUNDLED in the APK***, *not fetched by Play Services — confirmed by
    inspecting the built APK. **Tagging works offline from first launch**, so the `failed`/retry
    path is for genuine errors rather than a routine cold-start gap.*
  - ***Cost +64.8 MB on the DEBUG APK*** *(259.6 → 324.4), almost all native libs (~59 MB across
    three ABIs) rather than models (~4 MB). A release build ships one ABI, so expect roughly a
    third — **estimated, not measured**; confirm before quoting it.*
  - ***Both quality risks checked and absent:*** *a flat cartoon face labelled `[Smile]` (the
    photograph-trained labeller does handle drawn art), and OCR read `LOL` cleanly — so text
    recognition earns its ~29 MB. **Caveat: synthetic fixtures, one label each.** The floor is
    established; richness on a real library is still open — re-check in Task 14.*
  - ***Confidence threshold 0.6, max 5 subjects.*** *Low-confidence guesses pollute the searchable
    text and, since that text is embedded, drag the sticker toward unrelated meanings too.*
  - ***Orchestrator also refreshes the embedding*** *after tagging, closing a seam from Task 10:
    `setAutoTags` updates the FTS index for free but not the vector, so a freshly-tagged sticker was
    keyword-findable and semantically invisible until the next reindex.*

---

### Task 10: Search — FTS5 keyword + semantic + usage-ranking

**Branch:** `feat/search`

**Files:**
- Create: `lib/search/search_service.dart`
- Modify: `lib/library/database.dart` (add FTS5 virtual table mirroring `searchBlob`)
- Test: `test/search/search_service_test.dart` (in-memory drift)

**Interfaces:**
- Consumes: `LibraryStore`, `StickerRecord.searchBlob()`, `usageCount`.
- Produces:
```dart
class SearchHit { final StickerRecord record; final double score; }
abstract class SearchService { Future<void> reindex(); Future<List<SearchHit>> query(String q, {int limit = 50}); }
```

- [x] **Step 1: Write failing tests:**
  - keyword: searching "arjun" returns the sticker whose manualName contains it;
  - ranking: with two keyword-equal matches, the one with higher `usageCount` ranks first.

```dart
test('usageCount breaks ties in ranking', () async {
  await store.saveSticker(matchA.copyWith(usageCount: 0));
  await store.saveSticker(matchB.copyWith(usageCount: 5));
  final hits = await search.query('dog');
  expect(hits.first.record.id, matchB.id);
});
```

- [x] **Step 2: Run → FAIL.**
- [x] **Step 3: Implement keyword search** via FTS5 over the blob; final score = `textMatchScore + usageWeight * log(1 + usageCount)`.
- [x] **Step 4: Add semantic layer (FREE):** verify/choose an on-device TFLite sentence-embedding model; embed each `searchBlob` on index and the query at search time; blend cosine similarity into the score. FTS5 remains the fallback if embeddings are unavailable. Add a semantic test ("puppy" retrieves a sticker tagged "dog").
- [x] **Step 5: Run → PASS.** *(115 unit tests; analyze + format clean.)*
- [x] **Step 6: Commit & push** on `feat/search`.

  *(Actual, 2026-08-01 — **Task 10 is COMPLETE**: keyword half device-free, semantic half
  device-verified the same day. Full detail in `CLAUDE.md`'s "Search" section.)*
  - *Host SQLite **has FTS5**, so all of this is testable with no phone attached.*
  - ***The index is maintained inside `DriftLibraryStore.saveSticker`***, *not by callers — every
    mutating method funnels through it, so `updateMetadata`/`setAutoTags`/`incrementUsage` are
    covered by one hook in one transaction. Rejected: caller-driven indexing (the rule gets
    forgotten once and fails silently) and SQL triggers (they would duplicate `searchBlob()` in a
    second language). `reindex()` remains, for migrations and repair only.*
  - *Schema is now **version 2**, with an explicit additive migration; the FTS5 table is raw SQL
    (drift has no virtual-table API) and uses **`id UNINDEXED`** so ids are not tokenised into the
    searchable text.*
  - *Ranking is `-bm25() + usageWeight * log(1 + usageCount)` — **logarithmic** so a heavily-used
    sticker cannot outrank far better text matches.*
  - ***User input is never passed raw to `MATCH`***: FTS5 is a query language, so an apostrophe in
    "Arjun's face" would otherwise be a syntax error — a crash on ordinary input.*
  - ***Semantic layer: MediaPipe Universal Sentence Encoder***, *5.8 MB (measured), 100-dimensional,
    bundled as an Android asset and driven from Kotlin — **not** `tflite_flutter`, because USE needs
    SentencePiece tokenisation that a raw TFLite interpreter cannot supply.*
  - ***USE similarities are COMPRESSED: `cosine(dog,puppy)=0.980` but `cosine(dog,car)=0.940`.***
    *No absolute threshold separates related from unrelated, so ranking is **relative** — top-K,
    rescaled to best=1/worst=0, with a margin on the observed spread; a flat spread returns nothing.
    The first implementation used an absolute floor of 0.35, shipped green, and was returning the
    whole library on every query. Only reading the device numbers caught it.*
  - ***Two test smells that let it through:*** *`contains(expected)` is satisfied by returning
    everything — assert the distractor is excluded; and
    `expect(() async => f(), returnsNormally)` passes vacuously, never awaiting the future.*

---

### Task 11: Exporter — WhatsApp ContentProvider + intent

**Branch:** `feat/exporter`

**Files:**
- Create: `android/app/src/main/kotlin/com/arjun/whatsapp_sticker_studio/StickerContentProvider.kt`, `lib/export/exporter.dart`
- Modify: `AndroidManifest.xml` (register provider with authority + `com.whatsapp.sticker.READ`), add a `MethodChannel`
- Test: `test/export/exporter_test.dart` (validation-gate logic) + manual device verification of the WhatsApp handshake

**Interfaces:**
- Consumes: `PackRecord`, `StickerRecord`, `StickerValidator` (Task 4).
- Produces:
```dart
abstract class Exporter { Future<void> addPackToWhatsApp(PackRecord pack, List<StickerRecord> stickers); }
```

- [x] **Step 1: Verify approach** — check whether a maintained Flutter WhatsApp-sticker package supports **animated** packs. If yes, use it and skip hand-writing the provider; if no, implement `StickerContentProvider.kt` mirroring the official `WhatsApp/stickers` sample (four content URIs; metadata incl. `animated_sticker_pack`). Record the decision in `CLAUDE.md`.
- [x] **Step 2: Write failing test** — `addPackToWhatsApp` throws `PackNotValidException` (surfacing `ValidationResult.problems`) when the pack is invalid, and does **not** fire the intent:

```dart
test('export blocks invalid pack', () async {
  expect(() => exporter.addPackToWhatsApp(packOf(2), stickersOf(2)),
         throwsA(isA<PackNotValidException>()));
  expect(fakeChannel.intentsFired, isEmpty);
});
```

- [x] **Step 3: Run → FAIL.**
- [x] **Step 4: Implement** — validate first (Task 4); on pass, fire `com.whatsapp.intent.action.ENABLE_STICKER_PACK` with `sticker_pack_id`, `sticker_pack_authority`, `sticker_pack_name` via the MethodChannel; serve assets through the provider.

> **Researched 2026-07-18 — three non-obvious API realities (details in `CLAUDE.md`):**
> - **Do not set `avoid_cache`**, in either direction. WhatsApp is deprecating it (issue #1089) and
>   ignoring it once broke installed packs at scale. If the sample provider we mirror carries it,
>   strip the field.
> - **Pack updates do not reliably refresh.** Bump `image_data_version` in `contents.json` on every
>   mutation *and* surface an in-app hint telling the user to open WhatsApp's sticker manager. There
>   is no notify API; WhatsApp polls, and issue #612 shows the bump alone is not sufficient. This is
>   an acknowledged, unfixed WhatsApp defect — not something we can code around.
> - **Treat a pack as a one-shot import.** WhatsApp stated they are moving stickers to storage that
>   does not sync with the source app post-import. Do not design features assuming an installed pack
>   stays in sync with our library.

- [x] **Step 4b: Verify the unverified** *(added — needs a physical device; see `CLAUDE.md`)*
  With WhatsApp installed, test through our own provider: (a) does a **1- or 2-sticker pack** install,
  or is the documented 3-minimum actually enforced? (b) does a static image encoded as a
  **single-frame animated WebP** install inside an animated pack? Both are currently inferences, and
  (b) determines whether Task 4's mixed-kind rule can be relaxed into a conversion path. Record the
  answers in `CLAUDE.md`.

  *(Actual, 2026-08-01, WhatsApp **v2.26.27.85** on A059P / Android 16 — four packs built from real
  encoder output, staged through our provider, exported via the intent. **All four installed and the
  stickers render and send.** Full detail in `CLAUDE.md`.*
  - ***The ≥2-identical-frame promotion PASSES.*** *An all-animated pack of promoted statics was
    accepted. The silent-promotion strategy stands; the pack-type-chosen-at-creation fallback is
    **not** needed and Task 13 Step 3b is unchanged. This was the project's largest design risk.*
  - ***The 3-sticker minimum is NOT enforced on this build*** *— 1- and 2-sticker packs both
    installed. **Deliberately not acted on:** it is a documented limit, WhatsApp re-validates
    independently and could re-enforce it, and a pack is a one-shot import, so an undersized pack
    that works here could fail for another user with no recourse. What it does buy us is that
    **padding packs with transparent filler stickers is unnecessary**.*
  - *Sub-question (b) from the original step — the **single**-frame animated WebP — was **not**
    tested: it is already settled on paper (the validator checks `getFrameCount() <= 1`), so device
    time went to the two-frame promotion instead.*
  - ***Still open:*** *can `animated_sticker_pack` flip after install? Not probed.*
  - ***New observation:*** *the adds completed with **no per-pack confirmation dialog** (~11 s for
    four packs). If confirmed, the spec's "a pack cannot be added silently" does not hold, and
    **our app must present its own confirmation** — see Task 13.)*
- [x] **Step 5: Run unit test → PASS.** Then on a device with WhatsApp: build a valid pack → tap Add → confirm the pack appears in WhatsApp.
- [x] **Step 6: Commit & push** on `feat/exporter`.

---

### Task 12: Sharing — single sticker + whole pack

**Branch:** `feat/sharing`

**Files:**
- Create: `lib/sharing/sharing_service.dart`
- Modify: `pubspec.yaml` (`share_plus`)
- Test: `test/sharing/sharing_service_test.dart` (fake share backend)

**Interfaces:**
- Consumes: `StickerRecord`, `PackRecord`, `LibraryStore.incrementUsage`.
- Produces:
```dart
abstract class SharingService {
  Future<void> shareSticker(StickerRecord s); // share sheet, then incrementUsage
  // NO sharePack — removed from v1 (2026-08-06). WhatsApp ties a pack to our
  // ContentProvider's authority, which exists only on this device, so pack-add
  // cannot cross devices. Any transport still needs the RECEIVING device to
  // construct the pack, which is v2's import feature. See CLAUDE.md.
}
```

- [x] **Step 1: Write failing test** — `shareSticker` calls the share backend with the WebP file and then calls `incrementUsage(s.id)` exactly once.
- [x] **Step 2: Run → FAIL.**
- [x] **Step 3: Implement** over `share_plus`. *(`sharePack` was **dropped** — the premise that it
  "reuses the Exporter's add-to-WhatsApp flow so a friend can add the pack" is false: the Exporter
  points WhatsApp at **our** device's ContentProvider, which a friend's phone cannot read. Blocked on
  v2's import; full reasoning in `CLAUDE.md`.)*
- [x] **Step 4: Run → PASS.**
- [x] **Step 5: Commit & push** on `feat/sharing`.

  *(Actual, 2026-08-06 — device-verified on A059P / Android 16. Detail in `CLAUDE.md`'s "Sharing"
  section.)*
  - ***A shared sticker arrives in WhatsApp as an ORDINARY IMAGE, not a sticker.*** *The tray is
    reachable only via the ContentProvider + intent path; the share sheet just moves a file.
    **Task 13's button must not imply "send sticker"** — the two routes into WhatsApp are not
    interchangeable, and promising otherwise would repeat the overpromise just removed from pack
    sharing.*
  - ***Android reports share outcomes precisely***: a completed share returned `success` (usage 1),
    a dismissal returned `dismissed` (usage 0). The `unavailable` branch never fired, so counting it
    as a send is defensive rather than load-bearing, and there is no over-counting in practice.*
  - ***`sharePack` dropped*** *— see the note on the interface above.*

---

### Task 13: Maker screen (UI flow)

**Branch:** `feat/maker-ui`

**Files:**
- Create: `lib/ui/maker_screen.dart`
- Test: `test/ui/maker_screen_test.dart` (widget test with fake Source/Encoder/Library)

**Interfaces:**
- Consumes: `Source`, `Encoder`, `LibraryStore`, `TaggingService`.
- Produces: a screen; on "Save", persists via `LibraryStore` and kicks async tagging.

- [x] **Step 1: Write failing widget test** — pick (fake Source) → shows preview + fit-mode toggle + size/quality readout (from `QualityReport`) → tap Save → `LibraryStore.saveSticker` called once and async `TaggingService.tag` scheduled.
- [x] **Step 2: Run → FAIL.**
- [x] **Step 3: Implement** the flow: source picker (gallery / camera / Giphy / **paste X-Twitter link**) → Encoder (live `QualityReport`) → fit-mode selector → Save (persist + schedule tagging) → offer "Add to WhatsApp"/"Share". The X-link entry shows a paste field, constructs an `XLinkSource(url)`, and surfaces a friendly error if extraction returns `null`.

  > **⚠️ CORRECTED 2026-08-07 — "live `QualityReport`" holds for stills only.** Measured on device: a
  > static encode returns in well under a second, but a real 1.5 MB gallery video took **~24 s**
  > (the ladder runs up to seven ffmpeg passes over the whole clip). Re-encoding on every toggle
  > would make the screen unusable, so:
  > - **Static** — re-encode on change; the readout really is live.
  > - **Animated** — encode once on load, then mark the preview **stale** on parameter changes and
  >   offer an explicit *Update preview*. Progress is indeterminate (no ffmpeg callback in our
  >   wrapper), so say the wait is expected rather than looking hung.
  > - **Save must not persist something the user never previewed**: track the params of the last
  >   successful encode and re-encode before saving if they have since changed.
  > - When it will not fit, push **trimming** over quality — cost is near-linear in frame count, and
  >   `EncoderBudgetException` already carries that guidance. See `CLAUDE.md`.

  > **⚠️ SCOPE, as built 2026-08-08.** Two source entries shipped — **Gallery** and **Camera**. Giphy
  > and the X-link paste field are **not** in this screen: Giphy is Task 8 and the X extractor (Task 8B)
  > has no confirmed success path or deploy target yet (see `CLAUDE.md`), so a paste field would offer a
  > route that cannot work. `MakerScreen` takes an injectable `sources` map, so each is a one-line
  > addition once its `Source` is real.
  >
  > **Also added beyond the plan, driven by device findings:** an optional **sticker name** field (the
  > highest-signal searchable text there is, and the only per-sticker text WhatsApp accepts), and an
  > honest tagging-status card with a retry. **Sharing was cut** from this screen — see `CLAUDE.md`.

- [x] **Step 3b: Add-to-pack silently promotes statics** *(added 2026-07-18 — see `CLAUDE.md`)*

  When the user adds a **static** sticker to an **animated** pack, call
  `AnimatedEncoder.promoteStatic` (Task 6 Step 5b) and add it with no dialog, no warning, no error.
  The pack-kind constraint must be invisible.

  Failing widget test first: selecting an animated pack for a static sticker results in
  `LibraryStore.saveSticker` receiving a record with `kind == StickerKind.animated`, and **no error
  widget is shown**.

  Do **not** grey out incompatible packs or explain the constraint. Research into ~9,700 competitor
  reviews found *zero* users who correctly diagnosed it — they blame paywalls and bugs. Apps that
  accept the sticker then fail at export earn *"I wasted literally 20 mins"*. Promotion is the only
  approach users praise.

  **Validated on device 2026-08-01 (Task 11 Step 4b): WhatsApp accepts the promoted pack.** Build
  this step as written — the fallback is not needed.

  **Built and confirmed on real content 2026-08-08:** promotion works "near flawless" through a real
  pack on device. Note the rule shipped slightly broader than written here — a pack is animated if
  **any** sticker in it is animated, so an *animated* sticker joining a *static* pack flips the pack
  and promotes every existing member. Both directions are silent. See `CLAUDE.md`.

- [x] **Step 3c: The app must show its OWN "Add to WhatsApp?" confirmation** *(added 2026-08-01)*

  Task 11's device probes exported four packs in ~11 s with **no per-pack confirmation dialog from
  WhatsApp**. The spec assumed WhatsApp always asks ("a pack cannot be added silently — user
  confirms each Add"); on v2.26.27.85 it did not. So the guarantee has to come from us.

  Never fire the export intent as a side effect of another action. A user must never discover a pack
  in WhatsApp they did not explicitly ask for — that is both a trust problem and, at scale, the kind
  of behaviour that gets an app reported. Show the pack name and sticker count, and require an
  explicit tap.

  **Built as `confirmAndExportPack`.** Shows the pack name and sticker count, exports nothing until
  answered, and handles all four outcomes distinctly — see `CLAUDE.md` "Export UI".

- [x] **Step 3d: Device walk-through** *(added 2026-08-08)* — the whole flow run on the A059P against
  WhatsApp v2.26.27.85. Everything worked. Findings, and the keyboard bug it caught, in `CLAUDE.md`
  "Device walk-through of the Maker".
- [x] **Step 4: Run → PASS.** 231 tests, `dart format` and `flutter analyze` clean, debug APK builds.
- [x] **Step 5: Commit & push** on `feat/maker-ui`.

---

### Task 14: Library & search screen (UI)

**Branch:** `feat/library-ui`

**Files:**
- Create: `lib/ui/library_screen.dart`
- Test: `test/ui/library_screen_test.dart` (widget test with fake SearchService/LibraryStore)

**Interfaces:**
- Consumes: `SearchService`, `LibraryStore`, `SharingService`.
- Produces: a grid + search bar + per-sticker actions (share, edit metadata, add-to-pack).

- [ ] **Step 1: Write failing widget test** — typing a query calls `SearchService.query` and renders the returned stickers in order; the edit sheet calls `LibraryStore.updateMetadata`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** the grid, debounced search bar, metadata edit sheet, share/add-to-pack actions.
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit & push** on `feat/library-ui`.

---

### Task 15: End-to-end wiring & integration test

**Branch:** `feat/e2e`

**Files:**
- Modify: `lib/main.dart` (dependency wiring, navigation between Maker and Library)
- Test: `integration_test/end_to_end_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: the shipped app entrypoint.

- [ ] **Step 1: Write failing integration test** — full loop on an emulator: create sticker from a bundled image → it appears in the Library → search finds it by an auto-tag → share increments `usageCount`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Wire dependencies** in `main.dart` (concrete implementations injected; Maker + Library tabs).
- [ ] **Step 4: Run the integration test on emulator → PASS.**
- [ ] **Step 5: Run the full suite** — `flutter test` and `flutter test integration_test` → all green.
- [ ] **Step 6: Commit & push** on `feat/e2e`; open a PR to `main`.

---

## Self-Review

**Spec coverage:**
- Pro Maker (encode, smart-fit, full 10 s, no crop) → Tasks 5, 6, 13. ✅
- Giphy search source → Task 8 (+ Source interface Task 7). ✅
- X/Twitter-link source (+ minimal extraction service) → Task 8B. ✅
- Auto-tagging (FREE) → Task 9. ✅
- Manual metadata → Tasks 2 (fields), 3 (`updateMetadata`), 14 (edit UI). ✅
- Search (keyword + semantic, usage-ranked) → Task 10. ✅
- Export / Add-to-WhatsApp with pre-validation → Tasks 4, 11. ✅
- Single + pack sharing → Task 12. ✅
- `usageCount` as ranking-only signal → Tasks 3, 10, 12. ✅
- Spec ceilings enforced → Task 2 (constants), 4 (validator), 5/6 (encoder budgets). ✅
- v1.1 (bg-removal, text overlay) and v2 (existing-library import) → intentionally **absent**. ✅

**Placeholder scan:** Platform-API "verify" steps (ffmpeg variant, Giphy terms, ML Kit model, sticker-package animated support, TFLite embedding model) are the spec's §9 deferred decisions, written as explicit verification steps with expected outcomes — not vague placeholders. No "TODO/handle edge cases" left.

**Type consistency:** `MediaHandle`, `StickerKind`, `FitMode`, `TaggingStatus`, `StickerSource`, `EncodeParams`, `EncodedSticker`, `QualityReport`, `StickerRecord`, `PackRecord`, `ValidationResult`, `StickerTags`, `SearchHit`, and the `LibraryStore`/`Encoder`/`Source`/`TaggingService`/`SearchService`/`Exporter`/`SharingService` interfaces are defined once (Tasks 2–12) and referenced consistently by later tasks.
