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
  Future<void> updateMetadata(String id, {String? manualName, List<String>? manualTags, String? notes});
  Future<void> setAutoTags(String id, List<String> tags);      // sets taggingStatus = TaggingStatus.done
  Future<void> incrementUsage(String id);
  Future<void> savePack(PackRecord p);
  Future<PackRecord?> getPack(String id);
  Future<List<PackRecord>> allPacks();
}
```

- [ ] **Step 1: Add dependencies** — edit `pubspec.yaml`, then `flutter pub get`.
- [ ] **Step 2: Write the failing test** — round-trip a sticker, update metadata, increment usage:

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

- [ ] **Step 3: Run it to see it fail** — `flutter test test/library` → FAIL (no `database.dart`).
- [ ] **Step 4: Define drift tables** in `database.dart` (Stickers, Packs; list columns stored as
  JSON text via a `TypeConverter`; `taggingStatus`/`source` stored via drift's `textEnum`, which persists
  the enum **name** — not `intEnum`, whose index would silently remap existing rows if the enum is
  ever reordered),
  run `dart run build_runner build --delete-conflicting-outputs`.
- [ ] **Step 5: Implement `DriftLibraryStore`** mapping rows ↔ records. Mutating methods
  (`updateMetadata`, `setAutoTags`, `incrementUsage`) read the row, apply `copyWith`, and write back
  — records are immutable, so nothing is mutated in place.
- [ ] **Step 6: Run tests** — `flutter test test/library` → PASS.
- [ ] **Step 7: Commit & push** on `feat/library-store`.

---

### Task 4: Sticker/pack validator (pure ceiling enforcement)

**Branch:** `feat/validator`

**Files:**
- Create: `lib/export/sticker_validator.dart`
- Test: `test/export/sticker_validator_test.dart`

**Interfaces:**
- Consumes: `WhatsAppSpec`, `PackRecord`, `StickerRecord`.
- Produces:
```dart
class ValidationResult { final bool ok; final List<String> problems;
  const ValidationResult(this.ok, this.problems); }
class StickerValidator {
  ValidationResult validatePack(PackRecord pack, List<StickerRecord> stickers);
  ValidationResult validateSticker(StickerRecord s); // dimension/size/format per kind
}
```

- [ ] **Step 1: Write failing tests** covering each rule:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/export/sticker_validator.dart';
// helpers: stickerOf(sizeBytes, kind), packOf(count)

void main() {
  final v = StickerValidator();
  test('pack with <3 stickers fails', () {
    final r = v.validatePack(packOf(2), stickersOf(2));
    expect(r.ok, isFalse);
    expect(r.problems.any((p) => p.contains('at least 3')), isTrue);
  });
  test('animated sticker >500KB fails', () {
    final r = v.validateSticker(stickerOf(600000, StickerKind.animated));
    expect(r.ok, isFalse);
  });
  test('valid pack passes', () {
    final r = v.validatePack(packOf(5), stickersOf(5, bytes: 400000));
    expect(r.ok, isTrue);
    expect(r.problems, isEmpty);
  });
}
```

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** using `WhatsAppSpec` (count 3–30; per-sticker size by kind; collect all problems, don't short-circuit).
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit & push** on `feat/validator`.

---

### Task 5: Encoder — static images

**Branch:** `feat/encoder-static`

**Files:**
- Create: `lib/encoder/encoder.dart` (interface + params), `lib/encoder/static_encoder.dart`
- Modify: `pubspec.yaml` (add `image` package for decode/resize)
- Test: `test/encoder/static_encoder_test.dart` (uses a real bundled test image asset)

**Interfaces:**
- Consumes: `MediaHandle`, `FitMode`, `WhatsAppSpec`, `StickerKind`.
- Produces:
```dart
class EncodeParams { final FitMode fitMode; final Duration? trim; const EncodeParams({this.fitMode = FitMode.pad, this.trim}); }
class QualityReport { final int fps; final int frames; final int quality; final int sizeBytes; }
class EncodedSticker { final Uint8List webpBytes; final StickerKind kind; final int width; final int height; final int sizeBytes; final QualityReport report; }
abstract class Encoder { Future<EncodedSticker> encode(MediaHandle input, EncodeParams params); }
```

- [ ] **Step 1: Add a 1024×768 test JPEG** to `test/fixtures/landscape.jpg`.
- [ ] **Step 2: Write failing test** — output is exactly 512×512 WebP and ≤ 100 KB:

```dart
test('static encode → 512x512 webp under 100KB', () async {
  final bytes = await File('test/fixtures/landscape.jpg').readAsBytes();
  final out = await StaticEncoder().encode(
    MediaHandle(bytes: bytes, kind: MediaKind.image),
    const EncodeParams(fitMode: FitMode.pad));
  expect(out.width, 512);
  expect(out.height, 512);
  expect(out.sizeBytes, lessThanOrEqualTo(102400));
  expect(out.kind, StickerKind.staticImage);
});
```

- [ ] **Step 3: Run → FAIL.**
- [ ] **Step 4: Implement `StaticEncoder`.** Decode with `image`; apply `FitMode` (pad = letterbox onto transparent 512² canvas; contain = scale-to-fit; smartCrop = center-crop to square then resize — subject-aware detection deferred to v1.1). Encode WebP; if > 100 KB, step quality down (e.g., 100→90→…→50) until under ceiling; populate `QualityReport`.
- [ ] **Step 5: Run → PASS.** Also add a portrait fixture test to confirm padding keeps aspect ratio (no stretch).
- [ ] **Step 6: Commit & push** on `feat/encoder-static`.

---

### Task 6: Encoder — animated (GIF/video)

**Branch:** `feat/encoder-animated`

**Files:**
- Create: `lib/encoder/animated_encoder.dart`
- Modify: `pubspec.yaml` (add `ffmpeg_kit_flutter` — pick the min GPL/LTS variant that includes libwebp/libvpx)
- Test: `integration_test/animated_encoder_test.dart` (runs on a device/emulator — ffmpeg needs the platform)

**Interfaces:**
- Consumes: `MediaHandle` (gif/video), `EncodeParams` (uses `trim`), `WhatsAppSpec`.
- Produces: `EncodedSticker` with `kind == StickerKind.animated`.

- [ ] **Step 1: Verify the ffmpeg package variant** exposes animated-WebP muxing.

Run (in `integration_test`): encode a 3 s test mp4 to animated webp via an FFmpeg command; assert exit code success. If the chosen variant lacks libwebp, switch variants before proceeding. Document the working variant in `CLAUDE.md`.

- [ ] **Step 2: Write failing integration test** — trim to ≤ 10 s, output ≤ 500 KB, 512×512, animated:

```dart
testWidgets('animated encode ≤500KB, ≤10s, 512²', (t) async {
  final out = await AnimatedEncoder().encode(videoHandle, const EncodeParams(trim: Duration(seconds: 6)));
  expect(out.sizeBytes, lessThanOrEqualTo(512000));
  expect(out.width, 512);
  expect(out.report.frames * out.report.fps <= 10 * out.report.fps, isTrue);
  expect((1000 / out.report.fps) >= 8, isTrue); // ≥8ms/frame
});
```

- [ ] **Step 3: Run → FAIL.**
- [ ] **Step 4: Implement `AnimatedEncoder`** with **progressive degradation** to hit 500 KB: pipeline = trim (≤10 s) → scale/pad to 512² → encode animated WebP at target fps/quality; if oversize, degrade in order **fps (15→12→10→8) → drop frames → quality → dimension-internal** until ≤ 500 KB, recording each choice in `QualityReport`. Never emit an oversize file — if the floor still exceeds 500 KB, throw `EncoderBudgetException` for the UI to surface.

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
- [ ] **Step 5: Run → PASS** on emulator.
- [ ] **Step 6: Commit & push** on `feat/encoder-animated`.

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

- [ ] **Step 1: Write the contract test** — `FakeSource` returns a `MediaHandle`; assert non-null bytes and a valid `MediaKind`; a cancelling source returns `null`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** `GallerySource`/`CameraSource` over `image_picker`, `ShareInSource` over `receive_sharing_intent`; map picked files → `MediaHandle` (infer `MediaKind` from mime/extension).
- [ ] **Step 4: Run contract test → PASS.** (Real picker flows verified manually on device.)
- [ ] **Step 5: Commit & push** on `feat/sources`.

---

### Task 8: Giphy source

**Branch:** `feat/giphy-source`

**Files:**
- Create: `lib/sources/giphy_source.dart`, `lib/sources/giphy_client.dart`
- Modify: `pubspec.yaml` (`http`); add `GIPHY_API_KEY` via `--dart-define`
- Test: `test/sources/giphy_client_test.dart` (mock `http.Client`, no network)

**Interfaces:**
- Consumes: `http.Client`, `MediaHandle`.
- Produces: `class GiphyClient { Future<List<GiphyGif>> search(String q, {int limit}); }`, `class GiphyGif { String id; String title; Uri previewUrl; Uri mp4Url; }`, and `GiphySource` (returns the chosen gif's media as a `MediaHandle` of kind `video`/`gif`).

- [ ] **Step 1: Verify Giphy API terms** — confirm the free/beta key works, note rate limits and required attribution in `CLAUDE.md`.
- [ ] **Step 2: Write failing test** — `GiphyClient.search` parses a canned JSON fixture into `GiphyGif`s (inject a mocked `http.Client`).
- [ ] **Step 3: Run → FAIL.**
- [ ] **Step 4: Implement** `GiphyClient` (GET `/v1/gifs/search`), `GiphySource` (download chosen gif bytes → `MediaHandle`). Feeds straight into the Encoder.
- [ ] **Step 5: Run → PASS.**
- [ ] **Step 6: Commit & push** on `feat/giphy-source`.

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

- [ ] **Step 1: Write the failing backend test** — `services/extractor/test_extractor.py` (mock yt-dlp; no network):

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

- [ ] **Step 2: Run it to see it fail**

Run: `cd services/extractor && pip install -r requirements.txt && pytest`
Expected: FAIL — `main` not found.

- [ ] **Step 3: Implement the service** — `services/extractor/main.py`:

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

- [ ] **Step 4: Run backend tests**

Run: `cd services/extractor && pytest`
Expected: PASS (2 tests).

- [ ] **Step 5: Verify real extraction (§9 item)** — with the service running, `curl -X POST localhost:8000/extract -d '{"url":"<a real public tweet with a GIF/video>"}' -H 'Content-Type: application/json'` returns an mp4 URL. If X changed its params and it fails, run `pip install -U yt-dlp` and retry; pin the working version in `requirements.txt`. Note the deploy target (VPS / free-tier PaaS) in `CLAUDE.md`.

- [ ] **Step 6: Write the failing Dart client test** — `test/sources/extraction_client_test.dart` (mocked `http.Client`, no network):

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

- [ ] **Step 7: Run it to see it fail** — `flutter test test/sources/extraction_client_test.dart` → FAIL (no `extraction_client.dart`).

- [ ] **Step 8: Implement `ExtractionClient` and `XLinkSource`.** `ExtractionClient.extract` POSTs `{url}` to `$_baseUri/extract`; on 200 parse `ExtractedMedia`; else throw `ExtractionException`. `XLinkSource.pick()` calls `extract(_tweetUrl)`, downloads the mp4 bytes via `_http.get`, and returns `MediaHandle(bytes: …, kind: MediaKind.video, mimeType: 'video/mp4')`; on `ExtractionException` returns `null` so the Maker can surface a friendly message (per spec §7).

- [ ] **Step 9: Run Dart tests** — `flutter test test/sources` → PASS.

- [ ] **Step 10: Commit & push** on `feat/xlink-source` (backend + app together).

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

- [ ] **Step 1: Write the contract test** against `FakeTagger` (returns fixed tags); assert `flatten()` includes subjects + textInImage; assert an orchestrator writes them via `LibraryStore.setAutoTags` and sets `taggingStatus` to `TaggingStatus.done` (and to `TaggingStatus.failed` when `tag()` throws — see spec §7).
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement `MlKitTagger`** — run on-device Image Labeling (subjects) + Text Recognition (textInImage); map to `StickerTags`. **No network, no key, free.** `suggestedName` = top label. (Optional free-tier hosted VLM adapter is a later drop-in behind `TaggingService` — not built now.)
- [ ] **Step 4: Run contract test → PASS.** Real labeling verified on device.
- [ ] **Step 5: Commit & push** on `feat/tagger`.

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

- [ ] **Step 1: Write failing tests:**
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

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement keyword search** via FTS5 over the blob; final score = `textMatchScore + usageWeight * log(1 + usageCount)`.
- [ ] **Step 4: Add semantic layer (FREE):** verify/choose an on-device TFLite sentence-embedding model; embed each `searchBlob` on index and the query at search time; blend cosine similarity into the score. FTS5 remains the fallback if embeddings are unavailable. Add a semantic test ("puppy" retrieves a sticker tagged "dog").
- [ ] **Step 5: Run → PASS.**
- [ ] **Step 6: Commit & push** on `feat/search`.

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

- [ ] **Step 1: Verify approach** — check whether a maintained Flutter WhatsApp-sticker package supports **animated** packs. If yes, use it and skip hand-writing the provider; if no, implement `StickerContentProvider.kt` mirroring the official `WhatsApp/stickers` sample (four content URIs; metadata incl. `animated_sticker_pack`). Record the decision in `CLAUDE.md`.
- [ ] **Step 2: Write failing test** — `addPackToWhatsApp` throws `PackNotValidException` (surfacing `ValidationResult.problems`) when the pack is invalid, and does **not** fire the intent:

```dart
test('export blocks invalid pack', () async {
  expect(() => exporter.addPackToWhatsApp(packOf(2), stickersOf(2)),
         throwsA(isA<PackNotValidException>()));
  expect(fakeChannel.intentsFired, isEmpty);
});
```

- [ ] **Step 3: Run → FAIL.**
- [ ] **Step 4: Implement** — validate first (Task 4); on pass, fire `com.whatsapp.intent.action.ENABLE_STICKER_PACK` with `sticker_pack_id`, `sticker_pack_authority`, `sticker_pack_name` via the MethodChannel; serve assets through the provider.

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

- [ ] **Step 4b: Verify the unverified** *(added — needs a physical device; see `CLAUDE.md`)*
  With WhatsApp installed, test through our own provider: (a) does a **1- or 2-sticker pack** install,
  or is the documented 3-minimum actually enforced? (b) does a static image encoded as a
  **single-frame animated WebP** install inside an animated pack? Both are currently inferences, and
  (b) determines whether Task 4's mixed-kind rule can be relaxed into a conversion path. Record the
  answers in `CLAUDE.md`.
- [ ] **Step 5: Run unit test → PASS.** Then on a device with WhatsApp: build a valid pack → tap Add → confirm the pack appears in WhatsApp.
- [ ] **Step 6: Commit & push** on `feat/exporter`.

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
  Future<void> sharePack(PackRecord p);        // pack-add flow for friends
}
```

- [ ] **Step 1: Write failing test** — `shareSticker` calls the share backend with the WebP file and then calls `incrementUsage(s.id)` exactly once.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** over `share_plus`; `sharePack` reuses the Exporter's add-to-WhatsApp flow so a friend can add the pack.
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit & push** on `feat/sharing`.

---

### Task 13: Maker screen (UI flow)

**Branch:** `feat/maker-ui`

**Files:**
- Create: `lib/ui/maker_screen.dart`
- Test: `test/ui/maker_screen_test.dart` (widget test with fake Source/Encoder/Library)

**Interfaces:**
- Consumes: `Source`, `Encoder`, `LibraryStore`, `TaggingService`.
- Produces: a screen; on "Save", persists via `LibraryStore` and kicks async tagging.

- [ ] **Step 1: Write failing widget test** — pick (fake Source) → shows preview + fit-mode toggle + size/quality readout (from `QualityReport`) → tap Save → `LibraryStore.saveSticker` called once and async `TaggingService.tag` scheduled.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** the flow: source picker (gallery / camera / Giphy / **paste X-Twitter link**) → Encoder (live `QualityReport`) → fit-mode selector → Save (persist + schedule tagging) → offer "Add to WhatsApp"/"Share". The X-link entry shows a paste field, constructs an `XLinkSource(url)`, and surfaces a friendly error if extraction returns `null`.
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit & push** on `feat/maker-ui`.

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
