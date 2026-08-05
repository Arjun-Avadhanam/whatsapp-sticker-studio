# WhatsApp Sticker Studio — Working Rules

## Implementation rules (always)
- Commit frequently. One feature branch per task (`feat/<task>`). Push to GitHub after each task.
- **NEVER add "Co-authored-by" trailers to commit messages.**
- Full testing before "done": run the test suite (unit + backend/integration where possible). Report a task complete **only after** its tests pass — never claim completion on untested code.
- On the completion of a task - make sure to review, update any relevant documentation and finally report the current status of the project in the session.

## Product constraints (WhatsApp sticker spec — do not violate)
- WebP only, exactly **512×512**. Static **≤ 100 KB**, animated **≤ 500 KB**. Tray icon **96×96 ≤ 50 KB**.
- **3–30** stickers/pack; **1–10** packs. Animation **≤ 10 s**, **≥ 8 ms/frame**.
- **Vision/tagging must be FREE** — on-device ML Kit default; free-tier hosted adapters only. No paid model.
- **Standalone app.** Integrate ONLY via the official sticker `ContentProvider` + intent and the OS share sheet. No in-WhatsApp UI injection (ToS/ban risk).

## WhatsApp API realities (researched 2026-07-18 — do not re-derive)

**Two separate paths exist into WhatsApp's sticker tray. We use only the first.**
1. **Third-party sticker API** (ours): `ContentProvider` + `ENABLE_STICKER_PACK` intent. The 3–30
   stickers/pack and 1–10 packs limits apply *here*.
2. **WhatsApp's own native sticker features** — sticker creator (~Mar 2024) and native custom packs
   (globally rolled out ~17 Apr 2025, the pencil icon in the sticker tray). No minimum, no pack API.
   When a user says "WhatsApp let me add one sticker to a new pack," this is what they used. It is
   not available to us and is not a counter-example to the 3-sticker floor.

**`avoid_cache`: do not set it, in either direction.** WhatsApp staff stated (issue #1089) they are
deprecating the flag and moving stickers to storage permanent within WhatsApp "that does not rely on
additional syncing with apps after initial user import." Ignoring it in 2.25.9.78 broke installed
packs widely; devs fixed it by removing the field entirely. Strategic consequence: **post-import
sync is going away** — treat a pack as a one-shot import.

**Updating an installed pack is unreliable — design around it.** The only mechanism is bumping
`image_data_version` in `contents.json`; there is **no push/notify API**, WhatsApp polls. Bumping it
demonstrably does not always refresh the tray (issue #612, acknowledged by a WhatsApp engineer,
closed without a fix; #644 open since 2020). **So: bump the version AND tell the user in-app to open
WhatsApp's sticker manager.** Silently relying on the refresh reproduces the exact frustration that
drives users to recreate packs.

**WhatsApp validates independently of the sample code — you cannot delete your way around a rule.**
The sample `StickerPackValidator.java` is deletable app-side code, but WhatsApp re-validates on
ingest and returns errors via `validation_error` in the intent result. Proof: issue #763 carries the
string `pack is marked as animated pack but contains non animated stickers`, wording that exists
**nowhere in the sample source**. Corroborated on iOS (no Java validator exists there) and by #998
(identical packs flipping pass/fail across WhatsApp builds). A maintainer states in #606 that their
validation is deliberately closed-source and *stricter* than the sample. Treat every documented
limit as genuinely enforced.

**Packs are homogeneous: all-static or all-animated, never mixed.** `animated_sticker_pack` is a
pack-level flag and also selects the size ceiling (100 KB vs 500 KB).

**Decision (2026-07-18): auto-promote statics into animated packs, silently.** When a static sticker
joins an animated pack, re-encode it as **≥2 identical frames** (each ≥8 ms, total ≤10 s) so it is
genuinely animated. Never show the user a mixed-kind error.
- **A single-frame "animated" WebP does NOT work** — the validator checks
  `webPImage.getFrameCount() <= 1`, not whether an ANIM/ANMF chunk is present. One frame is rejected
  exactly like a static file. This was tried on paper and ruled out; do not revisit it.
- There is no minimum frame count beyond `> 1` and no minimum *total* duration, so 2 frames is legal.
- Rationale: across ~9,700 scraped Play Store reviews of competing apps, **zero users correctly
  diagnosed this constraint** — they blamed paywalls or bugs. Explaining it does not work; dissolving
  it does. Apps that accept a static sticker then fail at export earn reviews like *"I wasted
  literally 20 mins"*. The one app users praise for mixed packs (FSM, 10M+ installs) almost certainly
  does this promotion.
- Promotion moves that sticker from the 100 KB to the 500 KB budget — quality goes *up*.

**ANSWERED ON DEVICE 2026-08-01 — WhatsApp `com.whatsapp` v2.26.27.85, A059P / Android 16.**
Four packs were built from real encoder output, staged through our provider, and exported via
`ENABLE_STICKER_PACK` (`integration_test/interactive_test.dart`). **All four installed, and the
stickers render and send inside WhatsApp.** Record the WhatsApp version with any future re-test —
their validation is closed-source and demonstrably varies between builds (issue #998).

- **The ≥2-identical-frame promotion PASSES.** ✅ An all-animated pack whose stickers were statics
  put through `AnimatedEncoder.promoteStatic` was accepted and is usable. **The silent-promotion
  strategy is validated — Task 13 keeps it, and the pack-type-chosen-at-creation fallback is not
  needed.** This was the decisive open question in the whole project.
- **The 3-sticker minimum is NOT enforced at runtime on this build.** A 2-sticker pack *and* a
  1-sticker pack both installed and are usable. **Do not design around this.** It is a documented
  limit that WhatsApp validates independently and could re-enforce in any build; a pack is a
  one-shot import, so a 2-sticker pack that installs here could fail for a user on a different
  version with no recourse. Our validator keeps the 3-minimum as a deliberate safety margin — the
  finding removes the need to *pad packs with transparent filler stickers*, which is what
  competitors reportedly do, not a licence to ship undersized packs.
- **Still unknown: can a pack's `animated_sticker_pack` flag flip after install?** Not probed;
  undocumented everywhere. Weak signal suggests it may be sticky.
- **Observed, needs confirming:** the adds appeared to complete **without a per-pack confirmation
  dialog** (four packs in ~11 s). If real, that contradicts the spec's "a pack cannot be added
  silently" assumption and means **our app must present its own confirmation** before exporting —
  the user must never have a pack appear in WhatsApp without having asked for it.

## Encoding stack (decided + device-verified 2026-07-29)

**Static WebP uses Android's built-in encoder, not ffmpeg.** `Bitmap.compress(WEBP_LOSSY)` behind a
`MethodChannel` (`WebpEncoderChannel.kt` ↔ `lib/encoder/native_webp_encoder.dart`), walking quality
**100→90→…→50** and stopping at the first result ≤ 100 KB. No dependency, and it compresses in
memory — routing six ladder attempts through ffmpeg would mean six process spawns and six temp-file
round-trips on every live-preview refresh. `WebpEncoder` stays an injected interface, so this is
cheap to swap if it ever disappoints.

- **Verified on device:** lossy WebP **preserves alpha**, so `pad`'s letterbox bars stay transparent.
  This was the main risk in not using libwebp directly. Settled — don't re-litigate.
- **Refuses rather than overshoots:** if quality 50 still exceeds the ceiling it throws
  `EncoderException`. Overshooting silently would resurface as an opaque WhatsApp rejection at export,
  long after the user made the sticker.
- **Threading:** encode on a background `Executor`; post **both** success and error replies back via
  `Handler(Looper.getMainLooper())` — `MethodChannel.Result` is not thread-safe.
- **Pixel packing:** explicit `setPixels` with `0xAARRGGBB` ints, **never** `copyPixelsFromBuffer`
  (raw byte copy assuming an in-memory order that isn't RGBA everywhere; silently swaps red/blue).
  Kotlin's `Byte` is signed, so each channel needs `and 0xFF`.
- **Test fixtures:** uniform random noise is maximum-entropy and fits under 100 KB at *no* quality
  (139 KB at q50). Use structured photo-like fixtures to exercise the ladder; keep noise only to pin
  the refusal path.

**Animated WebP still needs ffmpeg — Android has no built-in animated-WebP encoder at any API
level.** `ffmpeg_kit_flutter` is **retired** (2026-01-06; binaries pulled 2026-04-01 — it cannot
build). Use **`ffmpeg_kit_flutter_new_video`** (LGPL, FFmpeg 8.1.2, minSdk 24): the smallest
maintained variant carrying libwebp, avoiding the x264/x265 **GPL** obligations of the full variants.
It emits a Kotlin-Gradle-Plugin deprecation warning; harmless now.

**Device-verified 2026-07-29 (Task 6 Step 1).** Runtime reports variant `video` with
`[dav1d, fontconfig, freetype, fribidi, iconv, kvazaar, libass, libtheora, libvorbis, libvpx,
libwebp, snappy, zimg]` and genuinely muxes multi-frame WebP (`[VP8X, ANIM, ANMF×6]`). Note there is
**no H.264 *encoder*** (x264 is GPL and correctly absent) — irrelevant to us, since we only *decode*
H.264 (built-in decoder) and only *encode* WebP.

**Animated-WebP cost is ~LINEAR IN FRAME COUNT — the plan's inter-frame-compression assumption is
WRONG for this toolchain.** Measured on device: 10 identical frames = **10.09×** one frame, 40 =
**40.28×**, and moving content came within **2%** of identical content. Consequences:
- Usable frames ≈ **500 KB ÷ per-frame cost**. A simple sticker (flat background, small moving
  subject) runs ~1.8 KB/frame and *can* fill the full 10 s; detailed/high-frequency content runs
  several KB/frame and **cannot** — 10 s stickers are only reachable for simple art.
- **fps and duration are the dominant levers**, so the fps-first degradation ladder is right, and
  Task 13's UI should push *trimming* over quality when a clip won't fit.
- Still **encode and measure** rather than predicting: per-frame cost varies with content.

**Use `-c:v libwebp_anim` for real clips, but `-c:v libwebp` for `promoteStatic`.** `libwebp_anim`
drives libwebp's `WebPAnimEncoder` (frame diffing + disposal) and measured ~16% smaller. But it
diffs *identical* frames to nothing and **collapses them into a single frame** — which is exactly
what promotion depends on, and a 1-frame file is rejected by WhatsApp like a static one. Verified on
device. Promotion loses nothing by using the plain encoder: two frames of a still are tiny against
the 500 KB budget.

**Testing the encoders (learned the slow way):**
- Keep the phone awake: `adb shell svc power stayon usb`. A locking screen suspends the test app.
- **Clear stale adb forwards before every device-test run:**
  `adb forward --remove-all`. `flutter test` allocates a VM-service port forward per run and **leaks
  it** — especially when a run is interrupted. They accumulate (5 seen in one session), and the
  host↔device handshake then intermittently fails: the app launches, sits in the foreground doing
  nothing, and `flutter test` waits forever with no output. Diagnosed 2026-07-29 after it silently
  ate most of a session. Check with `adb forward --list`.
- **A stalled install often resumes when you open a TRANSPORT to the device — run any
  `adb shell` command.** Observed twice, 2026-08-04, and the contrast is what makes it more than
  coincidence: an install sat at `Installing…` for **9.5 min with no adb contact**, then `adb devices`
  (a **host-side query that never touches the phone** — it only reads the adb server's cached list)
  did nothing for a further **6 min**; issuing `adb shell pm list packages` then saw tests start
  within ~40 s. Likely an idle or half-dead transport that a new connection forces to re-establish.
  **n=2 and the mechanism is unconfirmed**, but the remedy is free: if an install stalls, run
  `adb shell true`. This supersedes the earlier advice to just wait — waiting cost real time.
- **Device-test overhead is per FILE, and it dominates.** `flutter test integration_test -d <id>`
  does **not** amortize the build across files — Flutter reruns `assembleDebug` **and reinstalls the
  APK for every test file**. Measured 2026-07-29: a 13-test run took **~17 min wall-clock of which
  only ~2 min was actual testing**; the rest was three build+install cycles. Installs of this debug
  APK (it carries the ffmpeg native libs) can take **many minutes** on this device, printing nothing
  while they wait — **a slow install is not a hang**; don't kill it.
  **Fix: keep device tests in ONE entry-point file** that calls per-area groups, so a run costs one
  build and one install instead of N.
- **Generate fixtures with ffmpeg (`-f lavfi -i testsrc2=…`, `color`, `noise`), not per-pixel Dart
  loops** — the loops dominated runtime (~6 min → ~1.3 min for the animated suite).
- For a genuinely unencodable fixture, `testsrc2` alone is **not** hard enough (mostly static bars,
  diffs away). Add `noise=alls=90:allf=t`, and emit mp4 not gif so a 256-colour palette doesn't
  quantise the noise back into something compressible.

## Exporter / ContentProvider (Task 11 — decided 2026-07-31)

**Hand-roll `StickerContentProvider.kt`; do not take a Flutter sticker package.** Surveyed the two
real candidates and both are unusable:
- `whatsapp_stickers_exporter` — supports animated, but **last released 3 years ago** (12 likes, 61
  downloads) and explicitly does *no* format conversion or validation.
- `whatsapp_stickers_injector` — last release 13 months ago, 79 downloads, and **no documented
  animated-pack support** at all.

Depending on an abandoned package for a **moving** API is the wrong trade here: `avoid_cache` is
mid-deprecation and the `image_data_version` refresh defect is open and unfixed, so we need direct
control. We also need behaviour no package offers — our own validator as a hard pre-flight gate,
the static→animated promotion path, and surfacing WhatsApp's `validation_error` verbatim. The Kotlin
layer already exists (`WebpEncoderChannel.kt` from Task 5b), so a provider is incremental work, not
new infrastructure.

**Test device state (2026-07-31):** WhatsApp **`com.whatsapp` v2.26.27.85** is installed on the
A059P. Record the version alongside any validator finding — WhatsApp's validation is closed-source
and demonstrably varies between builds (issue #998: identical packs flipping pass/fail), so a result
is only meaningful against a known version. A competitor app, `com.marsvard.stickermakerforwhatsapp`,
is also installed and is useful for comparing real-world pack behaviour.

## X/Twitter extractor service (`services/extractor/`)

FastAPI + yt-dlp. `POST /extract {url}` → `200 {mp4_url, kind}` | `422 {detail:{error}}`. yt-dlp only
**resolves** the tweet's mp4 URL (`skip_download`); the app downloads the bytes. Server-side so a
Twitter-format break is fixed by upgrading yt-dlp, not shipping a new app build.

**Live-test findings (2026-07-25, local run, real unmocked yt-dlp):**
- Service runs end-to-end; error path surfaces yt-dlp's real messages as 422. ✅
- **This environment reaches Twitter** — yt-dlp's `[twitter]` extractor ran and returned
  tweet-specific responses (`No video could be found in this tweet`), i.e. **not** IP-blocked at the
  network level. ✅
- **Success path (200 + real `mp4_url`) NOT yet confirmed** — the tweets tried had no extractable
  video (IDs were guessed). Needs a **known-video tweet URL** to confirm.

**TODO next session (needs a real video-bearing tweet URL, ideally from the user):**
- Run `POST /extract` with a tweet that definitely has video → confirm a real `mp4_url` comes back.
- If Twitter auth-gates video from a datacenter IP, the deploy target may need yt-dlp **cookies**.
- After a confirmed success, **pin the working yt-dlp version** in `requirements.txt` (currently a
  floor `>=`, deliberately kept updatable).
- **Choose a deploy target** (free PaaS / small VPS) and record the base URL the app points at.

To run locally: `pip install -r services/extractor/requirements.txt` then
`uvicorn main:app` from `services/extractor/`.

## Connecting the Android device (WSL2) — solved 2026-07-29, don't re-derive

**A USB cable alone does nothing: WSL2 has no USB stack.** The phone attaches to the Windows kernel;
WSL is a separate VM, so `adb devices` in WSL is empty by design — it is not an adb bug. (Wireless
`adb pair` also fails here under NAT networking with `protocol fault (couldn't read status message)`.
The sibling DaySync project never solved this and sideloaded APKs to `/mnt/c/Users/arjun/Downloads/`
instead — viable, but it gives up hot reload, logcat and `integration_test`, so it is not our route.)

**Working setup — `usbipd-win` forwards the USB device into WSL.** Device: **A059P, Android 16
(API 36)**, serial `00178358P000397`, USB id `18d1:4e11`, usbipd **BUSID 2-4**.

One-time (Windows PowerShell **as admin**; `winget install usbipd`):
```powershell
usbipd bind --busid 2-4        # once per device; survives reboots
```
Per session, after each replug/reboot (this one does **not** need admin, so it can be run from WSL):
```bash
"/mnt/c/Program Files/usbipd-win/usbipd.exe" attach --wsl --busid 2-4
~/Android/Sdk/platform-tools/adb kill-server   # REQUIRED after every re-attach
~/Android/Sdk/platform-tools/adb devices -l    # restarts the server; phone appears
```

**`attach` alone is not enough — restart the adb server after it.** A server that was already running
does not rescan, so `adb devices` stays empty despite a successful attach. This looks identical to a
failed attach; `lsusb | grep -i google` distinguishes them — if the phone is listed there, the attach
worked and only the stale adb server is at fault.
One-time in WSL (needs a **real terminal** — sudo can't prompt for a password through Claude Code):
```bash
sudo tee /etc/udev/rules.d/51-android.rules >/dev/null \
  <<< 'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"'
sudo udevadm control --reload-rules && sudo udevadm trigger
```

**Three failure modes, each with a distinct symptom:**
- `attach` → **"Device busy (exported)"** — a **Windows** adb server has claimed the phone. Fix:
  `"/mnt/c/Users/arjun/AppData/Local/Android/Sdk/platform-tools/adb.exe" kill-server`. Note that
  running `adb.exe devices` **restarts** that daemon, re-breaking it — don't re-query after killing.
- `adb devices` → **"no permissions"** — the udev rule is missing or hasn't applied yet.
  `udevadm trigger` is **asynchronous**, so adb can scan too early; just restart adb afterwards.
- `adb devices` → **"unauthorized"** — permissions are fine; accept the *"Allow USB debugging?"*
  prompt on the phone (tick *Always allow*).

Four WSL distros are installed and `Ubuntu-20.04` is the default, but **this project lives in
`Ubuntu-22.04`**. usbipd reports attaching via the default distro; that's fine — WSL2 distros share
one kernel, so the device is visible in all of them.

Verify with `flutter devices`; run device tests with
`flutter test integration_test/<file> -d 00178358P000397`.

## Search (Task 10 — keyword half done 2026-08-01; semantic half deferred)

**Search is fully testable without a device** — the host SQLite that `flutter test` and CI use has
**FTS5 compiled in** (verified 2026-08-01). No phone needed for anything in this area.

**The index is maintained by `DriftLibraryStore.saveSticker`, not by callers.** Every mutating store
method funnels through `saveSticker`, so one hook covers `updateMetadata`, `setAutoTags` and
`incrementUsage` too, and both writes share a transaction. Chosen over the two alternatives
deliberately:
- *Callers call `indexSticker` themselves* — rejected: the rule gets forgotten exactly once, and the
  symptom (a sticker the user just made is missing from search) is silent, user-facing, and looks
  like a search bug rather than a missed write.
- *SQL triggers* — rejected despite being the most bypass-proof: a trigger must rebuild the
  searchable text **in SQL**, duplicating `StickerRecord.searchBlob()` in a second language where
  the two can silently drift. `searchBlob()` stays the single definition of what is searchable.

`SearchService.reindex()` still exists, but only for what the hook cannot cover: rebuilding after a
schema migration, and repairing a drifted index.

**Other details worth not re-deriving:**
- The FTS5 table is created with raw SQL in the drift migration — drift's Dart table API has no
  first-class virtual-table support. `schemaVersion` is now **2**; the migration is explicit and
  additive (never `fallbackToDestructiveMigration` — a user's library is not disposable).
- **`id UNINDEXED`** in the table definition. Without it the sticker id is tokenised into the
  searchable text, so a query like "1" matches every sticker whose id contains a 1.
- Ranking is `-bm25() + usageWeight * log(1 + usageCount)`. bm25 is *more negative for better
  matches*, hence the negation. Usage is **logarithmic** so one heavily-sent sticker cannot outrank
  genuinely better text matches and turn search into a most-used list.
- **User input is never passed raw to `MATCH`.** FTS5's MATCH is a query language where `"`, `*`,
  `^`, `(`, `)` are operators and AND/OR/NOT/NEAR are keywords — an apostrophe in "Arjun's face"
  would be a syntax error, i.e. a crash on ordinary input. Each term is quoted into a literal phrase.

**Semantic layer — DONE and device-verified 2026-08-01.** MediaPipe **Universal Sentence Encoder**
(`com.google.mediapipe:tasks-text`), model bundled at
`android/app/src/main/assets/universal_sentence_encoder.tflite`.

- **5.8 MB** — measured, not guessed. (BERT embedder is 24.9 MB; USE is the affordable one.) Output
  is **100-dimensional**, not the 512 the docs imply.
- **Kotlin `TextEmbedderChannel`, not `tflite_flutter`.** USE needs **SentencePiece tokenisation** to
  turn text into token ids; a raw TFLite interpreter only exposes tensors, so that tokeniser would
  have to be reimplemented in Dart. MediaPipe does it natively from the model's own metadata.
- **`noCompress += "tflite"`** in `build.gradle.kts` — MediaPipe memory-maps the model straight out
  of the APK, which only works on a stored (uncompressed) entry.
- Embeddings live in a **`sticker_embeddings` table** (schema **v3**), Float32 blobs. Owned by
  `SearchService`, **not** the store — unlike the FTS index — because producing one needs the native
  model, and putting that in `LibraryStore` would make the store untestable without a device.

**⚠️ USE similarities are COMPRESSED — never threshold on the absolute value.** Measured on device:
`cosine(dog, puppy) = 0.980` but `cosine(dog, car) = **0.940**`. A 0.04 margin between related and
unrelated, so **no absolute floor separates them**: a threshold low enough to admit a true match
admits the entire library, and semantic search silently degrades into "return everything, slightly
reordered". This was shipped and caught only by reading the device numbers — the tests passed.

**The fix: rank relatively.** Take the top-K nearest, rescale so best = 1 and worst = 0, and require
a candidate to clear `semanticMargin` of the observed *spread*. If the spread is flat (everything
equally unrelated, or a one-item library) return nothing rather than presenting arbitrary stickers as
matches. Result: `"puppy"` now returns `dog=2.000` and correctly excludes `car`.

**Two test smells that let the bug through — worth recognising elsewhere:**
- Asserting `contains(expected)` on a result list is satisfied by **returning everything**. Assert
  the distractor is **excluded** too.
- `expect(() async => f(), returnsNormally)` passes **vacuously**: it only proves the closure did not
  throw *synchronously*, never awaits the future, and lets the work leak past teardown. Use
  `await expectLater(f(), completes)`.

## Tagger (Task 9 — device-verified 2026-08-04)

**ML Kit models are BUNDLED IN THE APK, not downloaded by Play Services.** Confirmed by inspecting
the built APK: `assets/mlkit_label_default_model/mobile_ica_8bit_with_metadata_tflite` (3.0 MB) and
five OCR models under `assets/mlkit-google-ocr-models/`. So **tagging works offline from first
launch** — no network, no API key, no first-run download gap. The `failed`/retry path is therefore
for genuine errors, not a routine cold start.

**Cost: +64.8 MB on the debug APK** (259.6 → 324.4 MB), and it is overwhelmingly **native libraries,
not models**: `libmlkitcommonpipeline.so` + `libmlkit_google_ocr_pipeline.so` are ~59 MB across three
ABIs; the models themselves are ~4 MB. **A debug APK carries all three ABIs**, so a release build with
per-ABI splits or an app bundle should be roughly a third of that — *estimated, not yet measured;
confirm with a real release build before quoting a figure.*

**Both quality risks were checked and did NOT materialise** (`integration_test/suites/tagger_suite.dart`):
- *Illustrated stickers* — a flat cartoon face returned `[Smile]`. The photograph-trained labeller
  does handle drawn art, which was the risk that would have undermined Task 14's search UI.
- *Sticker text* — OCR read `LOL` off a white background cleanly, so text recognition earns its
  ~29 MB half of the footprint. Do not drop it.

**Evidence strength: these were SYNTHETIC fixtures, one label each.** What is established is the
*floor* — neither illustrated art nor text comes back empty. Whether tags are rich enough to carry
search on a real library is still open; re-check with real stickers during Task 14.

**Confidence threshold is 0.6, capped at 5 subjects.** ML Kit returns a long tail of low-confidence
guesses; those pollute the searchable text and — because that same text is embedded — drag the
sticker toward unrelated meanings in vector space too. Fewer, better tags beat more tags.

**`MlKitTagger` writes a temp file.** ML Kit's `InputImage` wants a path or platform bitmap, not raw
bytes, so the adapter bridges it rather than widening `TaggingService` to ML Kit's shape.

## Sources (Task 7)

**`compileSdk` is pinned to 37 in `android/app/build.gradle.kts`, not `flutter.compileSdkVersion`
(36).** `receive_sharing_intent` 1.9.0 declares an AAR-metadata minimum of 37 and the build fails
outright below it (`checkDebugAarMetadata`). `compileSdk` only governs which APIs we may *reference*
— it does not raise `minSdk` or `targetSdk`, so the API 36 test device is unaffected. AGP 9.0.1
prints a "maximum recommended compile SDK is 36" warning; harmless. If a Flutter upgrade later moves
`flutter.compileSdkVersion` past 37, drop the pin.

**`image_picker` supplies NO mime type on Android — the extension fallback is the *primary* path.**
Device-verified 2026-08-01: every gallery and camera pick returned `mimeType: (none supplied)`, so
`MediaKindResolver`'s extension branch is what actually resolves the kind. A mime-first-only resolver
would return `null` for every pick and nothing would work. Do not "simplify" that fallback away.

**Share-in cannot be verified from `integration_test` — don't try, and don't treat its failure as a
code bug.** Established on device 2026-08-01 after two misdiagnosed runs:
- `flutter test` **uninstalls the app when a run ends**, and Android **caches recent share targets**,
  so an icon tapped in the share sheet can point at a package that no longer exists — the share then
  silently goes nowhere and looks exactly like a broken listener.
- A share from another app **launches `MainActivity` into that app's task** (observed landing in the
  Nothing Gallery's task `t3918`), i.e. a different activity instance and a different Flutter engine
  from the one running the test. The test's warm `getMediaStream` listener can never hear it.

**What IS proven** without that test: `pm query-activities --brief -a android.intent.action.SEND
-t image/jpeg` returns `com.arjun.whatsapp_sticker_studio/.MainActivity`, and a real share does start
our activity. Only "the Dart side receives the media" is unverified — observable at Task 15, once a
real UI exists. The probe is kept but `skip`ped with that reasoning inline.

**Careful reading the installed APK: `flutter test integration_test` overwrites
`build/app/outputs/flutter-apk/app-debug.apk` with the TEST-entrypoint build.** Installing that
by hand gives a black screen (the test bundle draws nothing and waits for a driver). Re-run
`flutter build apk --debug` before sideloading the real app.

**`launchMode` must be `singleTask`, not Flutter's default `singleTop`.** A share into a
backgrounded app arrives from another task, and `singleTop` only reuses an activity already on top of
the *current* task — so Android spawned a fresh instance and a fresh Flutter engine per share, and
the warm `getMediaStream()` listener in the running engine never fired. The share vanished with no
error. Caught on device by the SOURCE 5 probe, 2026-08-01.

**Format support differs between the two paths, because they use different decoders.** Same shape
either way (bytes → decode → fit to 512² → WebP), but stills decode in Dart and motion decodes in
ffmpeg:
- **Stills** — Dart `image` package: png, jpg/jpeg, webp, bmp (also gif, but gif routes to the
  animated path). **It has NO HEIC/HEIF/AVIF decoder.**
- **Motion** — ffmpeg: gif, mp4, mov, webm, mkv, avi, 3gp, m4v. Believed-good from the build's
  demuxers/decoders (H.264 + HEVC built in, libvpx, dav1d) but **not yet observed end-to-end**.

**HEIC is a real, unclosed gap.** It is a common phone camera format, so users will hit it.
`MediaKindResolver` currently **rejects** heic/heif/avif up front so they fail as "unsupported
format" rather than as "could not decode the image" on a photo the user can see in their gallery —
that is a workaround, not a fix. Planned fix: fall back to transcoding via the ffmpeg we already
ship when `img.decodeImage` fails, which covers anything ffmpeg knows, not just HEIC.

**No Android permissions are required for the pickers, and none should be added.** On API 33+
`image_picker` uses the system **Photo Picker**, which grants access to only the chosen item —
`READ_MEDIA_IMAGES` would be an unnecessary sensitive permission that invites Play Store review
scrutiny. Camera capture goes through `ACTION_IMAGE_CAPTURE`, which the camera app services; note
that **declaring** `CAMERA` would *make it mandatory* at runtime, so declaring it is strictly worse
than not.

## Local dev setup (WSL/Ubuntu)
- Flutter SDK lives at `~/flutter`. Non-interactive shells don't read `~/.bashrc`, so scripts must
  `export PATH="$HOME/flutter/bin:$PATH"` before calling `flutter`.
- **Android builds need ninja.** The scaffold sets `ndkVersion`, so Gradle configures a CMake task and
  fails with `[CXX1416] Could not find Ninja` if only the system cmake is present. Fix (no sudo):
  `sdkmanager "cmake;3.22.1"` — it bundles ninja into `$ANDROID_SDK/cmake/3.22.1/bin/`.
- Verify the build with `flutter build apk --debug`, not just `flutter test` — tests compile Dart
  only and will not catch a broken Android build.

## CI
`.github/workflows/ci.yml` runs on every push/PR: `dart format` check → `flutter analyze` →
`flutter test`, then a debug APK build. Keep it green; it mechanically enforces the
"full testing before done" rule.

## Where things are
- Design spec: `docs/superpowers/specs/2026-07-10-whatsapp-sticker-studio-design.md`
- Implementation plan: `docs/superpowers/plans/2026-07-10-whatsapp-sticker-studio-v1.md`

## Tech stack
Flutter (Dart) · Kotlin native glue · drift (SQLite + FTS5) · ffmpeg_kit_flutter + libwebp · Google ML Kit on-device (labeling + OCR) · on-device TFLite embeddings · Giphy HTTP API (free tier).
