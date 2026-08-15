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

## ☠️ RUNNING `flutter test integration_test` DESTROYS THE APP'S DATA ON THE DEVICE

**`flutter test` uninstalls the app when a run ends, and an Android uninstall wipes `/data/data`** —
the drift database, every encoded WebP, every staged pack. Not a crash, not a bug: the normal end of
a normal test run.

**This actually happened, 2026-08-13.** A semantic-search probe was run against a device holding a
real sticker library built over two sessions. The library was unrecoverable. There is no bin, no undo
and no cloud copy; only the original photos in the gallery survived, so the stickers had to be remade.

**Back up first. Every time.** Before any `integration_test` run on a device with data worth keeping:

```bash
APP=com.stickerstudio.app

# BACK UP (run-as starts in the app's data dir, so the path is relative)
adb exec-out run-as $APP tar cf - files > backup.tar

# ... run the device tests, which uninstall and reinstall the app ...

# RESTORE — push first, then untar ON the device
adb push backup.tar /data/local/tmp/backup.tar
adb shell "run-as $APP tar xf /data/local/tmp/backup.tar -C /data/data/$APP"
```

**Restore must be push-then-untar.** `adb exec-out ... tar xf -  < backup.tar` **hangs**: `exec-out`
captures stdout and does not forward stdin, so tar waits forever on an archive that never arrives.
Verified working 2026-08-13 by deleting a marker file and restoring it.

Restore only works after the app is reinstalled (the uninstall removes the uid's directory), and the
app must be **debuggable** for `run-as` — true for the debug APK, not for release. Note `run-as`
starts *in* `/data/data/$APP`, so `files/...` paths are relative and `-C` is unnecessary on backup.

**Better still, order the work so it cannot bite:** run device *probes* on an empty or disposable
library, and do interactive walkthroughs — the ones that populate real data — **afterwards**. A probe
is cheap to repeat; a hand-built library is not.

**Testing the encoders (learned the slow way):**
- Keep the phone awake: `adb shell svc power stayon usb`. A locking screen suspends the test app.
- **Clear stale adb forwards before every device-test run:**
  `adb forward --remove-all`. `flutter test` allocates a VM-service port forward per run and **leaks
  it** — especially when a run is interrupted. They accumulate (5 seen in one session), and the
  host↔device handshake then intermittently fails: the app launches, sits in the foreground doing
  nothing, and `flutter test` waits forever with no output. Diagnosed 2026-07-29 after it silently
  ate most of a session. Check with `adb forward --list`.
- **☠️ A STALLED INSTALL IS USUALLY `adb install` ITSELF, NOT THE LINK. Push and install separately.**
  Established 2026-08-14, and it **supersedes the re-attach advice below as the first thing to try**.
  - **Symptom:** identical to the usbipd wedge — `adb install` sits forever while `adb devices`,
    `df` and `pm list packages` all answer instantly. The I/O-counter check below still correctly
    says "the transfer is dead"; what it *cannot* tell you is **which** transfer.
  - **The decisive test takes 40 seconds — `adb push` the same APK.** A plain file transfer uses a
    different path from a streamed install:
    ```bash
    adb push build/app/outputs/flutter-apk/app-debug.apk /data/local/tmp/ss.apk
    adb shell pm install -r -t /data/local/tmp/ss.apk
    adb shell rm -f /data/local/tmp/ss.apk
    ```
    **Measured: the push moved 360 MB in 37 s (~9.6 MB/s) and `pm install` took 3 s — on the very
    link where `adb install` had just frozen twice.** So the link was never the problem.
  - **Re-attaching usbipd did NOT fix it**, which is what ruled the link out. `adb install` stalled
    at ~8.5 MB on a freshly attached link and ~11 MB on the next attempt; both times the adb
    server's `rchar` went to exactly zero and stayed there.
  - **`adb kill-server` silently drops every `adb reverse` mapping.** Nothing in the app needs one
    any more (X links are resolved on the phone), but if you ever tether a local service again,
    re-establish the mapping after any server restart — a dropped forward looks exactly like a
    broken feature.
  - Prefer push+install as the **default** for this project's debug APK. It is ~40 s, it is
    observable (the file grows), and it does not depend on the streamed-install path at all.

- **☠️ A STALLED INSTALL CAN ALSO BE A WEDGED usbipd LINK. Re-attach it — do not wait, do not poke adb.**
  Diagnosed properly 2026-08-13, and this supersedes the "keep polling / just wait it out" folklore
  below.
  - **Symptom:** `adb install` (or `flutter test`'s install step) sits for 10+ minutes, while
    `adb devices`, `adb shell df` and `pm list packages` all answer **instantly**. The control path is
    healthy; only the bulk transfer is dead.
  - **The decisive check takes ten seconds** — sample the adb server's I/O counters twice:
    ```bash
    sp=$(pgrep -f "adb -L tcp:5037 fork-server"); grep rchar /proc/$sp/io; sleep 10; grep rchar /proc/$sp/io
    ```
    **Frozen `rchar` = hung, not slow.** Measured: it stopped at ~51 MB and ~52 MB on two consecutive
    attempts — the same point twice, which is what ruled out "it is just slow".
  - **The fix is to re-attach**, then restart the adb server:
    ```bash
    "/mnt/c/Program Files/usbipd-win/usbipd.exe" attach --wsl --busid 2-4
    adb kill-server && adb devices
    ```
    On a freshly attached link, **343 MB installed in 14 seconds** (~25 MB/s). The wedges happened on
    a link that had been up for hours and had already dropped the device once.
  - **Payload size is NOT the cause.** The successful 14 s install was the *larger* APK (343 MB) and
    the wedged ones were 285 MB. A plausible-sounding theory — that 111 MB of unusable `x86_64` +
    `armeabi-v7a` native libs were the problem — was falsified by that single run.
  - **`ndk { abiFilters }` in `buildTypes.debug` does NOT filter anything.** Tried 2026-08-13:
    Flutter's Gradle plugin owns ABI selection, so `+=` merely adds to a set it has already fully
    populated, and the APK came out *bigger*. If a per-ABI debug build is ever genuinely needed, use
    `flutter build apk --debug --target-platform android-arm64` — but note `flutter test
    integration_test` builds its own APK and has no such flag.

- **Installs stall for minutes at a time, and NOTHING reliably unsticks them except killing the run
  and retrying.** Measured, including a failed hypothesis worth not re-testing:
  - *2026-08-04:* an install sat 9.5 min with no adb contact; `adb devices` (a host-side query that
    never touches the phone) did nothing for 6 more min; `adb shell pm list packages` was then
    followed by tests starting within ~40 s. Twice. That looked like "opening a transport revives a
    half-dead connection".
  - *2026-08-06:* **it did not reproduce.** A stall at 586 s was poked with `adb shell true` (no
    effect after 3.5 min) and then with `pm list packages` + `pidof` + `df` (no effect), while adb
    itself answered instantly — 441 packages listed, `df` immediate — and the package remained
    uninstalled.
  - *2026-08-13:* **the first properly controlled test, and a clean miss.** Zero adb contact for
    9m11s, then a single poke at a recorded time; 63 s later nothing had changed and the install was
    still frozen. **Net: 2 correlational hits, 3 clean misses, and the only rigorous attempt is a
    miss.**
  - **There is now a mechanical reason it cannot work:** the install holds its own live adb stream,
    so there is no dead connection for a poll to revive — which is exactly why control commands keep
    answering while the transfer is dead. **Do not poke adb.** Check the I/O counters and re-attach
    usbipd (see above).
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

## Maker UI (Task 13 — decided 2026-08-07)

**"Live QualityReport" works for stills and NOT for animation — the two paths need different
interaction models.** The plan's Step 3 assumed one live readout for both. Measured on device: a
static encode is an in-memory quality ladder returning in well under a second, but a real 1.5 MB
gallery video took **~24 seconds**, because the degradation ladder can run up to seven ffmpeg passes
over the whole clip. Re-encoding on every fit-mode toggle would make the screen unusable.

- **Static:** re-encode on change. The readout is genuinely live.
- **Animated:** encode **once** when the media loads (defaults: `pad`, no trim), then treat parameter
  changes as making the preview **stale** — show the previous result plus an explicit *Update
  preview* action. Progress is indeterminate (our ffmpeg wrapper exposes no callback), so show a
  spinner and say the wait is expected for video rather than looking hung.

**Save must never persist a sticker that does not match what was previewed.** Track the params used
for the last successful encode; if the current params differ, Save encodes first and then saves.
Otherwise a user who changes fit mode and immediately taps Save gets a sticker that looks nothing
like the preview — silently.

**Trim is the lever to promote, not quality.** Cost is near-linear in frame count here, so shortening
a clip is by far the strongest way to fit the 500 KB ceiling, and good animated stickers are 1.5–3 s
loops rather than the full 10 s. When `EncoderBudgetException` fires, its message already says
"try trimming it shorter" — surface that, do not replace it with a generic failure.

**Widget tests: real `dart:io` async must START inside `tester.runAsync`.** `testWidgets` bodies run
in a fake-time zone. Work that resolves through **microtasks** completes there fine — including
drift's in-memory SQLite, which is why store calls in widget tests have always worked. But genuine
file IO completes through the **real event loop**, which the fake zone never turns, so
`await file.readAsBytes()` in a test body **hangs forever with no error, no stack and no output** —
it does not fail, the run just stops. Diagnosed 2026-08-08 after it silently ate three full-timeout
runs.
- A `runAsync` window *afterwards* does **not** rescue work already in flight. The operation has to
  begin inside it: `await tester.runAsync(() async { await tester.tap(...); await Future.delayed(...); })`.
- `tester.pump()` cannot be called inside `runAsync`. So a flow needing **both** pumped frames and
  real IO, in that order, is undrivable — which is why the new-pack name entry is inline in the sheet
  rather than an `AlertDialog` over it (popping the dialog needs frames; the tray-icon write that
  follows needs the real loop).
- **Never `pumpAndSettle` while an indeterminate `CircularProgressIndicator` is on screen.** It
  schedules frames forever, so settling only ends at its 10-minute timeout. Pump manually.
- Sync IO (`writeAsBytesSync`) sidesteps all of this and is the right choice in fixtures.

**drift's `dateTime()` column stores unix SECONDS.** `DateTime.now()`'s sub-second part does not
survive a round trip, so a record saved and re-read compares **unequal** to the in-memory original.
`PackService.createPack` re-reads after saving for this reason. Nothing needs sub-second precision
(`createdAt` only drives Library sort order), so this is recorded rather than migrated — but Task 14
should not assume `saved == fetched`.

**The sticker name is offered in the Maker, and it is the highest-value text in the app.** Added
2026-08-08 once real-content testing showed auto-tags are generic. It feeds three things at once:
keyword search, the embedding, and WhatsApp's `accessibility_text` (the only per-sticker text field
that exists). Optional, empty by default, saved on submit **and** on focus loss — a name typed and
then abandoned by tapping elsewhere is still a name the user meant.
- **Empty stores `null`, not `""`**, so `accessibility_text` falls back to auto-tags instead of
  exporting a blank description.
- **Name and auto-tags are separate fields and must stay separate.** Naming never disturbs tags, so
  the user never has to clear machine output to add their own words. Task 14's edit sheet must keep
  this — a single merged tag list would force exactly that chore.
- The `TextEditingController` lives on the *screen*, keyed by the saved sticker's id: one sticker
  causes several rebuilds (tagging alone triggers two), so a controller rebuilt inline would wipe
  half-typed input, and one never reset would leak the previous sticker's name into the next.

**Tray icons are generated, not asked for.** Every pack needs a 96×96 ≤50 KB icon and `PackRecord`
requires the path; the plan never says where it comes from. Use `TrayIconEncoder` on the pack's first
sticker automatically — one less decision to put in front of the user.

## Packs (Task 13 · #42 — decided 2026-08-08)

**A pack is animated if ANY sticker in it is animated. Statics are promoted, silently, on demand.**
This is the one rule that makes the homogeneity constraint invisible, and it yields exactly two
cases: a static joining an animated pack is promoted, and an animated joining a static pack flips the
pack and promotes **every existing member**. The second is costly — one `promoteStatic` per member —
and that cost is accepted deliberately, because the alternative is telling the user their pack is the
wrong kind, which is the error the whole design exists to avoid. Never flip animated→static: there is
no un-animating, and the installed flag may be sticky.

**Promotion overwrites the sticker file IN PLACE.** Other records already point at that path — the
record's own `thumbnailPath`, anything staged for export, a pending share — so writing a new file
would leave those dangling and orphan the old one.

**`StaticPromoter` is a separate interface from `Encoder`.** `AnimatedEncoder` implements both. Packs
need *promotion* only, and depending on the full encoder would drag ffmpeg into what is otherwise
pure bookkeeping, making the entire feature untestable off-device.

**`createPack` requires its first sticker.** A pack is invalid without a tray icon and the tray icon
is generated *from* a sticker, so an empty pack could only exist in a state WhatsApp rejects. Matches
the UI flow anyway (*Add to pack → New pack*).

**Never name the promotion in UI copy.** The busy state says only "Adding…". A widget test asserts
the words "animat", "convert", "static" and "frame" appear nowhere in the sheet. Packs below the
3-sticker floor *do* say how many more they need — that is honest and actionable, and unrelated to
promotion.

## Library & packs UI (Task 14 — decided 2026-08-08)

**Three tabs now: Make · Library · Packs.** Packs earned its own tab because a
pack is the **only** route into WhatsApp's sticker tray, and before this screen a
pack was exportable *only* in the moment right after adding a sticker in the
Maker — close the app and every pack became unreachable. That was a v1 blocker,
not a missing convenience.

**A single sticker can now go to WhatsApp.** `WhatsAppSpec.minStickersPerPack`
stays **3** because that is what WhatsApp documents; the gate reads
`enforcedMinStickersPerPack`, now **1**. Rationale, risk and the one-number revert
are recorded at the constant. Consequence to remember: **one-sticker packs are the
common case**, so singular/plural copy is on screen constantly — `stickerCount()`
exists so the surfaces cannot disagree.

**Ordering is a store guarantee, with an id tiebreak.** `allStickers` and
`allPacks` are both newest-first, tiebroken by id. Not defensive: drift stores
`dateTime` as unix **seconds**, so two things made in the same second would
otherwise come back in arbitrary order and the grid would reshuffle between
rebuilds. Ids are minted from `microsecondsSinceEpoch`, so a higher id is later.

**Search: an empty query goes to the STORE, not to search.** FTS5's `MATCH` on an
empty string returns nothing, so routing a cleared field through search blanks the
library the instant the ✕ is tapped — it looks exactly like data loss.

**Search responses carry a request id.** Debouncing (300 ms) reduces overlap but
does not remove it: a slow query can still be in flight when a later one resolves,
and its stale results would land last and win. Verified load-bearing by removing
the guard and watching the superseded results take over.

**"Nothing matched" and "no stickers yet" are separate states.** Conflating them
tells a user with a full library that it is empty.

**Auto-tags are shown in the editor but have NO delete affordance.** Two reasons,
the second decisive: the user must never have to clear machine output to add their
own words, and a deletion would silently come back anyway because `setAutoTags`
replaces the list wholesale on every tagging run. They are displayed because they
explain why a sticker turns up in an unexpected search, styled lighter to match
how much less they weigh.

**Add-to-pack is opened by the CALLER, after the detail sheet closes.** The picker
is itself a bottom sheet; stacking one over another is poor on a phone *and*
reinstates the fake-async ordering trap (a route pop needs pumped frames, the
tray-icon write needs the real event loop). Hence `StickerDetailResult` carries
two facts rather than one flag. Add-to-pack **saves pending edits first** — losing
a half-typed name to another action is silent data loss.

**Sharing is surfaced as *Export file*, never "send sticker."** Device-verified
2026-08-06: a shared WebP arrives in WhatsApp as an ordinary image. A test asserts
the wrong wording appears nowhere.

**Deleting is permanent, confirmed, and asymmetric between stickers and packs** (added 2026-08-13
after device use showed nothing could be removed at all).
- **Deleting a sticker removes the record, its FTS row, its embedding, its membership of any pack,
  AND the file.** All of it in one transaction plus a best-effort file unlink: an orphaned index row
  surfaces a hit that opens nothing, a stale id makes a pack export a sticker that no longer exists,
  and a "delete" that leaves the bytes on disk is not what the word means. `stickerIds` is a JSON
  list, so nothing cleans it up unless the store does — it cannot be a foreign key.
- **Deleting a pack KEEPS its stickers**, and the dialog says so. The user grouped them; they did not
  create them there, and losing originals to a tidy-up is unrecoverable.
- **The pack dialog also warns that WhatsApp keeps its copy.** A pack is a one-shot import — deleting
  ours does not reach into WhatsApp, and a user assuming otherwise will think the delete failed.
- The sticker file is deleted with `deleteSync`. Async `dart:io` never completes in `testWidgets`'
  fake-time zone, so `await file.delete()` left the sheet un-popped and the test hanging on a null
  result with no error; one small file is microseconds anyway.

**Considered and NOT done: weighting the name above manual tags.** Both are the
user's own words and equally deliberate, so they share the `mine` column at 10×.
Known consequence: bm25 length-normalises the whole column, so long notes slightly
soften a name match on that sticker. Splitting into `(name, tags, auto)` is another
schema version — do it only if real use shows a problem, since ranking tuned on
speculation is how the semantic-threshold bug happened.

## Device walk-through of the Maker (Task 13 · #44 — 2026-08-08)

Real end-to-end run on the A059P against `com.whatsapp` v2.26.27.85. **Everything worked.** Findings
worth keeping:

- **The ≥2-frame promotion works in practice, not just in principle** — "near flawless" across a real
  pack. Combined with the 2026-08-01 export result, the silent-promotion strategy is now verified both
  at the validator and at the user-experience level.
- **A pack update DID refresh WhatsApp** on this build, on one pack. This does **not** overturn the
  `image_data_version` caveat — the defect is that it *sometimes* fails (issue #612), so one success is
  consistent with it. Keep telling the user to open the sticker manager on a re-add.
- **There is no per-sticker display name in WhatsApp's third-party API.** Every sticker in the tray
  shows the *pack's* name; the only per-sticker text field is `accessibility_text`. That was being set
  from `manualName`, which is `null` for everything the Maker makes, so it exported **empty** and a
  screen-reader user got nothing. Now falls back to auto-tags — the one job those generic scene labels
  are genuinely good at. `emojis` is still sent empty; it is WhatsApp's own in-tray search hook and is
  the remaining unexploited per-sticker field.
- **Video encoding takes 15–20 s on real clips** (earlier measurement said ~24 s; same order). Noted,
  accepted for v1, revisit post-v1. The stale-preview model is what makes it tolerable.
- **BUG, found here and fixed: the Add-to-pack sheet was hidden behind the keyboard.** A bottom sheet
  is anchored to the bottom of the screen and Flutter does **not** lift it for the keyboard the way it
  lifts a dialog, so with the name field autofocused the keyboard covered the whole sheet and the user
  typed blind into something invisible. Fix is `Padding(bottom: MediaQuery.viewInsetsOf(context)
  .bottom)` **outside** the `SafeArea`. This was a direct cost of choosing an inline field over an
  `AlertDialog`, which gets keyboard handling for free — the tradeoff was still right (see #42), but
  the cost is real and any future in-sheet text input needs the same treatment. Regression test exists
  and was **verified to fail without the fix** (field sat 324 logical px behind the keyboard).

## Export UI (Task 13 · #43 — decided 2026-08-08)

**Our confirmation dialog is mandatory, because WhatsApp's may not exist.** The spec assumed a pack
cannot be added silently. On device (`com.whatsapp` v2.26.27.85, 2026-08-01) four packs were added in
~11 s with **no per-pack dialog observed**, so ours may be the only thing between a tap and a pack
appearing in someone's WhatsApp. `confirmAndExportPack` gates everything behind it and exports
nothing until it is answered.

**The three export failures stay distinct all the way to the UI.** `PackExportService` deliberately
does not flatten them:
- `PackNotValidException` → our validator, listing **every** problem at once (it never
  short-circuits, so the user fixes everything in one pass).
- `WhatsAppRejectedException` → shown **verbatim**. Their validation is closed-source and stricter
  than the sample (issue #606), so that string is the only diagnostic that exists; paraphrasing
  destroys the sole clue.
- `ExportCancelledException` → **silent**. Backing out is an ordinary choice, not a failure — no
  dialog, no snackbar.

**Staging must precede the intent, and `PackExportService` owns that order.** WhatsApp reads through
the ContentProvider the moment it receives the intent, so firing first races an unwritten directory.
Screens use `deps.packExport`, never `deps.exporter` directly.

**A re-add says the refresh may not happen.** `hasBeenStaged` detects it, and the success message
tells the user to open WhatsApp's sticker manager — because bumping `image_data_version` demonstrably
does not always refresh the tray (issue #612, acknowledged, closed unfixed).

**Packs below the 3-sticker floor show a disabled button plus the shortfall**, rather than an enabled
one that earns a rejection.

**Sharing is NOT in the Maker.** Considered and cut 2026-08-08: the sticker file is built for the
tray, and as a chat photo it is a *worse* image than the source the user already has in their
gallery. WhatsApp itself covers the real need once a pack is installed (send sticker in chat →
recipient gets a real sticker). `SharingService` is kept — it is written, tested and device-verified
— and its honest home is the **Library (Task 14)** as *Export file*, where "get this file out of the
app" is the obvious reading and WhatsApp is not the implied destination. **Untested:** what WhatsApp
does with our alpha channel when it renders the WebP as a photo.

## Sharing (Task 12 — decided 2026-08-06)

**Single-sticker sharing ships in v1. Pack sharing does NOT — and the reason is a hard constraint,
not a time cut.**

WhatsApp identifies a pack by the pair **(ContentProvider authority, identifier)**, and that
authority exists only on the device running our app. A friend's phone publishes no such authority, so
their WhatsApp has nothing to load. Pack-add is inherently **local**.

The constraint survives any change of transport. Files, deep link, QR — all of them still require the
**receiving** device to construct the pack locally, and constructing a pack out of received stickers
*is* the **import** feature, which is scoped to **v2**. So:

> **Pack sharing is blocked on import (v2). It cannot be a v1 feature under any transport.**

Sending the raw `.webp` files was considered and rejected: the recipient gets ordinary images they
cannot turn back into stickers (we have no import path), so it would be pack-sharing in name only —
and no better than sending pictures from the gallery.

**This corrects the spec.** §3 lists pack sharing under v1 as *"nearly free; reuses the Exporter"*.
It is neither: the Exporter cannot serve another device, and the feature is gated behind v2's import.

**And the user need it appeared to serve is already met — by WhatsApp itself.** Once a pack is in
your tray, sending those stickers in a chat sends *real stickers*, and the recipient handles them
with WhatsApp's own tools. So the flow "share my stickers with a friend" works end to end today:
**add pack → send in chat → WhatsApp does the rest.** Pack sharing is therefore not outstanding debt
or a hole in v1 — it is a feature we do not need. Treat it as closed, not deferred, unless a concrete
user problem shows up that this flow genuinely fails to solve.

**A shared sticker arrives in WhatsApp as an ORDINARY IMAGE, not a sticker.** Device-verified
2026-08-06. The sticker tray is reachable *only* through the `ContentProvider` + `ENABLE_STICKER_PACK`
path (Task 11); the OS share sheet just moves a file, and WhatsApp renders that `.webp` as a photo in
the chat.

**This constrains Task 13's UI copy.** The button must not say or imply "send sticker" — call it
*Send as image* or similar. Two ways into WhatsApp, and they are not interchangeable:
- **Add to WhatsApp** (Exporter) → real stickers in the tray, needs a whole valid pack.
- **Share** (share sheet) → one picture in a chat, works for a single sticker, instantly.

Promising "send a sticker" here would repeat exactly the overpromise removed from pack sharing above.

**`usageCount` and cancelled shares.** `share_plus` reports three outcomes: `success`, `dismissed`
and **`unavailable`** ("shown, but the platform cannot tell what the user did"). We count `success`
and `unavailable`, never `dismissed`. The two errors are not symmetric: counting a dismissal inflates
a signal that feeds *search ranking*, but refusing to count an undetermined outcome risks
`usageCount` never moving at all if a platform reports `unavailable` routinely — a dead signal
removes the ranking tiebreaker entirely, which is worse than mild over-counting.

**Device-verified 2026-08-06: Android reports precisely** — a completed share returned `success`
(usage 1) and a dismissal returned `dismissed` (usage 0). The `unavailable` branch never fired, so it
is defensive code for other platforms rather than load-bearing here, and there is no over-counting in
practice.

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

## Giphy — probed with a real key 2026-08-14. **VERDICT: feasible, build it.**

Run against the live API before writing any UI, because the whole feature hinged on whether a free
key's rate limit could survive a search screen. It can.

- **The existing parser needs NO changes.** `GiphyClient._parse` read real payload 5/5 — it had only
  ever seen mocked JSON. `images.original.mp4` and `images.preview_gif.url` are both present.
- **`rating=g` works and MUST be sent.** Giphy does not filter by default; the client currently sends
  only `api_key`, `q`, `limit`. A sticker app returning unrated content on an innocent query is not a
  bug worth discovering on a user's phone.
- **Pagination works** (`total_count: 500`, `offset` honoured), so load-more is viable.
- **The mp4 is the right shape**: 263 KB, `[ftyp, moov, free, mdat]`, **avc1 (H.264), no audio track**
  — identical in kind to the X extractor's output, so it feeds `AnimatedEncoder` the same way.
- Originals are typically **480×480**, i.e. a mild upscale to our 512. Acceptable, worth knowing.

**The rate limit, measured rather than looked up.** The widely-quoted "42 requests/hour beta" figure
is **wrong for this key**:
- **~168 back-to-back requests before HTTP 429.** 54 distinct queries passed, then a second burst
  tripped at request 114 of that run.
- **⚠️ POLLING WHILE THROTTLED EXTENDS THE BAN.** Probing every 30 s stayed 429 for **8 solid
  minutes**; stopping all traffic cleared it in **10 minutes**. This is a rolling window that the
  retries themselves keep feeding. **So on 429 the app must back off and stop — never retry-on-fail,
  which is the instinctive thing to write and makes it strictly worse.**
- **A realistic session does not come close**: 30 distinct searches at 2 s spacing all returned 200.
  At ~3 requests per search, 168 is roughly 55 searches fired with no pause. Debounce (300 ms, as in
  the Library) plus per-query caching keeps a user an order of magnitude away.

**⚠️ Giphy sends NO rate-limit headers.** No `X-RateLimit-*`, no `Retry-After`, on 200 or on 429. The
app can never know how close it is or how long to wait, so the only honest 429 copy is a soft "search
is busy, try again in a few minutes" — do not invent a countdown, and do not auto-retry.

**Attribution is required by Giphy's API terms** — the picker must carry the "Powered by GIPHY" mark.

**✅ DEVICE-VERIFIED END TO END 2026-08-14.** Search, trending, paging, pick, download, ffmpeg
encode and Save all work on the A059P. The full chain from Giphy's mp4 to a saved sticker is closed.

**Picker decisions (Task D.2/D.3):**
- **A full route, not a bottom sheet.** It needs a keyboard, a scrolling grid and most of the screen,
  and a sheet is not lifted for the keyboard — the same trap that hid the add-to-pack sheet on device.
- **Opens on trending**, because an empty search screen asks the user to guess what the app is good
  at before showing them anything.
- **Debounce (300 ms) and the request-id guard are lifted from the Library** deliberately: two search
  fields in one app that behave differently are worse than either choice alone. Here the debounce is
  also a cost control, not just polish.
- **`GIF` is a third button in the source row** (Gallery · Camera · GIF) — it is a *pick*, like the
  other two. It could not join the `sources` map, though: the others hand off to the OS and come back
  with media, while this one runs a whole search screen before there is a `Source` at all.
- The download runs through `pickFrom`, so a Giphy pick inherits the same busy state and the same
  self-clearing error banner as every other source, with no special casing downstream.

**⚠️ Two tests here passed while asserting nothing — both worth recognising elsewhere:**
- The staleness test passed with the request-id guard *removed*, twice. First the fake built its
  response **after** the gate, so the "stale" reply carried fresh data. Then, once fixed, the
  assertion still checked the *first* item — but a reset clears the list when the request **starts**,
  so a late reply **appends** rather than replaces. Only "no stale item appears at all" catches it.
- The paging test read **built widgets** as a proxy for loaded data. `GridView.builder` is lazy, so
  that counts the viewport, not the list. Count requests and look up specific ids instead.
- Both were found by deleting the guard and checking the test failed. Do that; it is the only thing
  that distinguishes a real test from a decorative one.

## X links — resolved ON THE PHONE, no server (rewritten 2026-08-15)

**`ExtractionClient` calls X's own embed endpoint directly. There is no service in the request path,
and `services/extractor/` is now dead weight kept only as a fallback.**

```
GET https://cdn.syndication.twimg.com/tweet-result?id=<post id>&token=<derived>&lang=en
```

**Why the service had to go.** It was deliberately server-side so a Twitter-format break could be
fixed by bumping yt-dlp and redeploying instead of shipping an app build. That reasoning was sound
and it still failed in practice, because the service has to run *somewhere the phone can reach*:
Cloud Run died on billing verification, and the fallback — uvicorn on the dev machine plus
`adb reverse` — meant the feature only worked with the phone tethered to one specific laptop by USB.
The redeploy advantage was also always theoretical here: with nowhere to deploy, a yt-dlp break
needed an app update anyway. Calling X directly costs nothing real and removes hosting entirely.

**It also removes the risk that made hosting hard.** Requests now come from the user's own phone — a
residential or mobile IP — rather than a datacenter IP, which is where X is most likely to demand
auth. The cookies contingency is moot.

**☠️ THE STATUS CODE IS ALWAYS 200. JUDGE THE BODY.** A request X dislikes returns `200 {}`, not an
error. This produced **two** wrong conclusions during development, both from checking status and
never content:
1. *"the token is optional"* — the responses are **CDN-cached for 60 s**, so junk-token requests were
   being served the body an earlier correct request had populated. `x-cache: MISS` is what exposed it.
2. *"omitting the token works"* — `curl -w %{http_code}` said 200 while the body was `{}`.

**The rule, measured properly (body length, uncached ids):** `token` **absent** → `{}`;
**present but empty** → `{}`; **present with junk** → full payload; **present, correctly derived** →
full payload. So *the parameter must exist and be non-empty; its value is not validated.*

**The token is NOT a credential** — no account, no key, nothing issued or paid. It is a pure function
of the post id, computed offline exactly as X's embed script does: `(id / 1e6) × π` in base 36, zeros
and the decimal point stripped. Derived properly anyway (ten lines), so we are already correct if X
ever starts validating it. Pinned by tests: `20 → 2xj79n7d8r`,
`2087646138526802000 → 2boy5o6d6wewmi`, `1460323737035677698 → 1mjkvbsti2t9`.

**`200 {}` must NOT be reported as "no video in that post".** Observed: every request, curl and Dart
alike, returned `{}` for a stretch and then recovered on its own. Conflating that with a genuinely
video-less post sends a user holding a good link off to fix the wrong thing. `_looksLikeAPost` gates
it on `__typename`/`id_str`.

**✅ VERIFIED LIVE 2026-08-15 with the real Dart client**, not curl: the GIF post resolves and
downloads **101 004 bytes** of `video/mp4` — byte-identical to what yt-dlp's URL produced. `id=20`
(no video) and `id=1` (404) each give their own distinct message.

**Still unproven, exactly as it was with yt-dlp:** a real *video* post returns several mp4 renditions
plus HLS. The client takes the highest-bitrate mp4 and ignores `m3u8`, but every live post tested has
been an animated GIF, which carries a single variant at bitrate 0.

### The retired service (`services/extractor/`), kept as a fallback

FastAPI + yt-dlp. `POST /extract {url}` → `200 {mp4_url, kind}` | `422 {detail:{error}}`. yt-dlp only
**resolves** the tweet's mp4 URL (`skip_download`); the app downloads the bytes. **Nothing in the app
depends on it any more.** It still works, its tests and CI pytest job still run, and it is the ready
answer if the syndication endpoint ever dies. Its Dockerfile honours `$PORT` (Cloud Run's contract),
so it can still be deployed if that day comes.

**✅ SUCCESS PATH CONFIRMED 2026-08-14 — the last open question here is closed.**
Run against a real video-bearing tweet supplied by the user
(`https://x.com/i/status/2087646138526802000`) with **yt-dlp 2026.07.04**, unmocked:

- `resolve_info` returned one mp4 format and `pick_mp4` selected
  `https://video.twimg.com/tweet_video/HPjPGOLaQAAFo8i.mp4`. ✅
- Those bytes really download: **HTTP 200, 101 004 bytes, `video/mp4`**, box structure
  `[ftyp, moov, mdat]` with an **`avc1`** sample entry and **no audio track**. ✅
- **No cookies and no auth were needed** from this IP. The feared "Twitter auth-gates video from a
  datacenter IP" case did *not* occur here — but this is a residential WSL host, so it is **not**
  evidence about a PaaS IP. Re-check after deploying; cookies remain the contingency.
- **`tweet_video/` is Twitter's GIF path** — Twitter serves animated GIFs as silent H.264 mp4s.
  That is the ideal sticker input, and our ffmpeg decodes H.264 with its built-in decoder.
- **yt-dlp is now PINNED** to the verified `==2026.7.4`. Bumping it is the fix for a format break.

**Only ONE format came back** (`height: None`), because a GIF has a single variant. The
multi-variant path in `pick_mp4` (`max` by height) is therefore **still unexercised on real data** —
a genuine *video* tweet returns several mp4 renditions plus HLS. Low risk, but unproven.

**⚠️ `INTERNET` was in the DEBUG manifest only** (the Flutter scaffold puts it there for hot reload).
Every debug build and every test worked, and a **release build would have had no network permission
at all** — both remote sources failing only in release. Now declared in the main manifest. Fixed
2026-08-14; nothing else in the app touches the network, which is why it went unnoticed.

**`usesCleartextTraffic` is GONE, including from debug.** It existed only so `adb reverse` could
reach a locally-run uvicorn over plain HTTP. Nothing in this project speaks cleartext now.

**There is no `EXTRACTOR_BASE_URL` any more**, and nothing to configure at build time. The X button
used to be hidden unless a build was pointed at a service, which meant **it never appeared in a
release build at all**. It is now unconditional.

To run the retired service locally: `pip install -r services/extractor/requirements.txt` then
`uvicorn main:app` from `services/extractor/`.

## Post-v1 gaps — device-verified 2026-08-14 (A, B, C, F)

Full walkthrough on the A059P against the build installed that day. **Everything passed.** What the
run settled, beyond "it works":

**HEIC makes a sticker on real hardware.** The ffmpeg fallback engages invisibly — the user-facing
behaviour is indistinguishable from a JPEG, which was the whole design goal. Note the fixture came
from libheif, not a camera (see the Sources section), so this proves the container and codec path.
- **Gallery apps mostly surface `DCIM/Camera` only.** A fixture pushed to `Pictures/` is correctly
  indexed by MediaStore and still effectively invisible. Push test images to
  `/sdcard/DCIM/Camera/` and scan them with
  `content call --uri content://media/external/file --method scan_file --arg <path>`.

**X-post stickers work end to end**, including local link validation, extraction, the ffmpeg encode
and Save. Emoji selection works, skin-tone variants included.

**BUG found here and fixed: the source-error banner never went away.** A mistyped link left a red
banner sitting on the Maker indefinitely, following the user into unrelated work.
- **Source failures now self-clear after 5 s.** There is nothing to act on from that banner — the
  remedy is always "try a different link" — so once read it is pure clutter.
- **Encoder failures deliberately do NOT self-clear.** `EncoderBudgetException` says "try trimming it
  shorter", which is an instruction to carry out *on that screen with the media still loaded*.
  Retracting it mid-task would remove the only guidance that works. They clear on the next encode.
- The lifetime is a constructor argument, because `fakeAsync` does not compose with the async test
  bodies the controller tests already have, and waiting out five real seconds per test is a slow
  suite for nothing. A widget test must **pump past the lifetime** or the fake-time zone reports
  "A Timer is still pending even after the widget tree was disposed".

**The launcher identity is real now** — `android:label="Sticker Studio"` plus a generated adaptive
icon (`tool/make_app_icon.py`). Both are checked-in generated artefacts that nothing else tests, so
`test/app/app_identity_test.dart` pins them; the failure is otherwise only visible on a home screen.

## Connecting the Android device (WSL2) — solved 2026-07-29, don't re-derive

**A USB cable alone does nothing: WSL2 has no USB stack.** The phone attaches to the Windows kernel;
WSL is a separate VM, so `adb devices` in WSL is empty by design — it is not an adb bug. (Wireless
`adb pair` also fails here under NAT networking with `protocol fault (couldn't read status message)`.
A sibling project never solved this and sideloaded APKs to `/mnt/c/Users/<user>/Downloads/`
instead — viable, but it gives up hot reload, logcat and `integration_test`, so it is not our route.)

**Working setup — `usbipd-win` forwards the USB device into WSL.** Device: **A059P, Android 16
(API 36)**, serial `<device-serial>`, USB id `18d1:4e11`, usbipd **BUSID 2-4**.

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
  `"/mnt/c/Users/<user>/AppData/Local/Android/Sdk/platform-tools/adb.exe" kill-server`. Note that
  running `adb.exe devices` **restarts** that daemon, re-breaking it — don't re-query after killing.
- `adb devices` → **"no permissions"** — the udev rule is missing or hasn't applied yet.
  `udevadm trigger` is **asynchronous**, so adb can scan too early; just restart adb afterwards.
- `adb devices` → **"unauthorized"** — permissions are fine; accept the *"Allow USB debugging?"*
  prompt on the phone (tick *Always allow*).

Four WSL distros are installed and `Ubuntu-20.04` is the default, but **this project lives in
`Ubuntu-22.04`**. usbipd reports attaching via the default distro; that's fine — WSL2 distros share
one kernel, so the device is visible in all of them.

Verify with `flutter devices`; run device tests with
`flutter test integration_test/<file> -d <device-serial>`.

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
  `^`, `(`, `)` are operators and AND/OR/NOT/NEAR are keywords — an apostrophe in "Ana's face"
  would be a syntax error, i.e. a crash on ordinary input. Each term is quoted into a literal phrase.

## ⛔ SEMANTIC SEARCH IS CUT FROM v1 — keyword only (decided 2026-08-13)

**The embedder is deliberately NOT wired into `AppDependencies.bootstrap`.** Everything below about
the semantic layer still describes working code; it is simply not switched on. Re-enabling is one
constructor argument — do it only with new device evidence, not on the strength of the notes below.

**Why: measured on device, USE cannot tell a real query from gibberish.** Cosine spread across a
5-sticker library:

| query | kind | spread | top score |
|---|---|---|---|
| `beer` | real | 0.0883 | 0.9574 ✅ correct |
| `football` | real | 0.0838 | 0.9428 ✅ correct |
| `phone` | real | 0.1173 | 0.9519 ✅ correct |
| `ufidjsjsjsjs` | gibberish | 0.0833 | 0.9200 |
| `qqqqzzzzxxxx` | gibberish | 0.0827 | 0.9328 |
| `zzzzzz` | gibberish | 0.0926 | **0.9465** |

**The ranges overlap.** Gibberish `zzzzzz` has a *wider* spread than real `football`, and a *higher*
top score than `football`'s correct answer. Standard deviations above the mean overlap too (real
1.93/1.92/1.36 vs gibberish 1.49/1.33/1.31). **No threshold exists** — not absolute, not relative,
not z-score — because the distributions genuinely overlap. Gibberish also ranked the same sticker
first every time: some records simply sit near the centre of the embedding space.

**In use this was user-visible**: gibberish returned most of the library, and semantic noise
outranked exact keyword hits (a sticker named "Captain Beer" losing to an unrelated one).

**The relative-ranking fix was itself the bug, one level down.** Rescaling best..worst to 0..1 before
applying `semanticMargin` *manufactures* signal from a sliver of absolute spread; the `spread <= 0`
guard is effectively never true. Fixing an absolute threshold with a relative one just moved the
failure.

**Judgement: junk results are worse than no results.** Search that confidently returns five wrong
stickers for a typo teaches the user not to trust it. Keyword search is also far stronger since v4
weights the user's own words 10× above auto-tags — semantic existed to compensate for generic tags,
and is no longer the only defence.

**If revisiting:** the 24.9 MB BERT embedder is the obvious candidate, and the bar is a *measured*
separation between real and nonsense queries on a real library — not a plausible-looking threshold.

**Semantic layer — built and device-verified 2026-08-01, now OFF (see above).** MediaPipe **Universal Sentence Encoder**
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

**⚠️ KNOWN RANKING GAP — a user's own name weighs the SAME as a machine label.**
`StickerRecord.searchBlob()` flattens `autoTags + manualName + manualTags + notes` into one string, and
the FTS5 table has a single `blob` column, so bm25 sees one undifferentiated bag of words. Search
"sports" and a sticker the user deliberately *named* "sports party" ranks no higher than five stickers
ML Kit generically labelled "sports" — the signal they chose is drowned by the signal a model guessed.
This matters more now that tag genericness is confirmed (see Tagger below).

**Fix, sized 2026-08-08 — ~25 lines of production code, deferred to Task 14** so the ranking can be
*seen* on a real search screen rather than tuned blind:
- `fts5(id UNINDEXED, mine, auto)` instead of `(id UNINDEXED, blob)`; `schemaVersion` 3 → **4**.
- Split `searchBlob()` into `mineBlob()` (name, manual tags, notes) + `autoBlob()` (auto-tags). Keep
  `searchBlob()` for **embeddings** — semantic search should still see everything.
- `_reindex` inserts three columns; query becomes `bm25(table, 0.0, 10.0, 1.0)`.
- **The risky part is repopulation, not the weights.** Dropping and recreating the FTS table leaves it
  empty, and `_reindex` only fires on the next save — so every existing sticker silently disappears
  from search until it happens to be edited. `SearchService.reindex()` exists for this but the
  migration cannot call it (wrong layer), so `AppDatabase` must record that an upgrade happened and
  `bootstrap()` must call `reindex()` on seeing it. Test that; the failure is silent and total.
  Do **not** repopulate in raw SQL — that duplicates `searchBlob()` in a second language.
- **Verify, do not assume, that `UNINDEXED` columns occupy a bm25 weight slot** (hence the leading
  `0.0`). Getting it wrong shifts weights to the wrong column and looks like working search with
  subtly wrong ranking — the same shape as the threshold bug below. Pin it with a test asserting a
  real ordering, not a signature.

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

**ANSWERED ON REAL CONTENT 2026-08-08 — tags are SCENE-LEVEL and generic, and that is inherent.**
A video of a footballer returned `sports, team, event, stadium, competition`. Nothing is *wrong*, but
ML Kit labels the scene rather than the subject, so the tail matches any sports photo at all. Two
consequences, both acted on:
- **`maxSubjects` lowered 5 → 3.** Reduces noise, but does **not** make tags specific — the
  genericness is in ML Kit's label set, not in our threshold. Do not expect more tuning to fix it.
- **A user-typed name is worth far more than any auto-tag**, which is why the Maker now offers a name
  field, and why the ranking gap above matters.

**Latent bug found and fixed alongside: the cap did not sort.** `where(confidence).map(label)
.take(maxSubjects)` kept whatever order ML Kit returned. ML Kit is *believed* to sort
confidence-descending but does not document it, so `take(3)` could keep three arbitrary labels — and
`suggestedName` could be an arbitrary label too. Now sorted explicitly. `MlKitTagger` is also
**testable off-device** now (`test/tagger/mlkit_tagger_test.dart`): `ImageLabeler` and
`TextRecognizer` are plain injectable classes, so threshold/ranking/cap rules need no phone.

**`suggestedName` is computed and deliberately NOT consumed.** The Maker's name field is left empty
rather than pre-filled with it: a generic guess like "sports" is one the user must delete first, which
is the same tedium as having to clear auto-tags before adding their own words. An empty field with a
hint beats a wrong default.

**Evidence strength of the earlier synthetic run: SYNTHETIC fixtures, one label each.** What is established is the
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

**Share-in is WIRED IN as of Task 15 (2026-08-13) — it was built in Task 7 and never connected.**
`ShareInSource` existed and was tested but no screen used it, so sharing a photo into the app launched
it and did nothing. It now lives on **`HomeScreen`**, not `MakerScreen`, because a share can arrive
while the user is on any tab and has to bring them to the Maker — which needs the `TabController`.
`HomeScreen` therefore owns the `MakerController` too, and `MakerController.loadMedia` exists so media
the screen already holds needs no `Source` wrapper.

**BUG found by probing it on device, now fixed: an unreadable shared file crashed the app.**
`_firstUsable` checked `existsSync()` but not the read, so a path the process cannot open threw
`PathAccessException` as an **unhandled exception** out of `HomeScreen`. Existing and *readable* are
different things; the read is now guarded and the file skipped, which is what "first usable" always
meant. A unit test reproduces the exact device failure without the guard. `ShareInSource` had **no
unit tests at all** before this — 10 now.

**✅ VERIFIED END TO END ON DEVICE 2026-08-14 — both paths.** A real gallery → share sheet →
Sticker Studio share loads the photo straight into the Maker. **Cold** (app swiped away) opens on Make
with the image already previewed; **warm** (app open on another tab) switches to Make by itself and
loads it. This was the last unproven path in the project.

It also settles an ambiguity from the automated probing: a `content://` URI fired with
`adb shell am start` produced no media and no error, which looked like it might be a gap in the
plugin's content-URI handling. It was **an artifact of the probe** — `am start` does not grant the URI
the way a real share sheet does. Do not chase that; only a real share is a valid test.

**Share-in cannot be verified from `integration_test` — don't try, and don't treat its failure as a
code bug.** Established on device 2026-08-01 after two misdiagnosed runs:
- `flutter test` **uninstalls the app when a run ends**, and Android **caches recent share targets**,
  so an icon tapped in the share sheet can point at a package that no longer exists — the share then
  silently goes nowhere and looks exactly like a broken listener.
- A share from another app **launches `MainActivity` into that app's task** (observed landing in the
  Nothing Gallery's task `t3918`), i.e. a different activity instance and a different Flutter engine
  from the one running the test. The test's warm `getMediaStream` listener can never hear it.

**What IS proven** without that test: `pm query-activities --brief -a android.intent.action.SEND
-t image/jpeg` returns `com.stickerstudio.app/.MainActivity`, and a real share does start
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

**✅ HEIC CLOSED 2026-08-14 — and the format list is finally measured, not assumed.**

**This ffmpeg build decodes HEIC and AVIF.** Real libheif fixtures came back as 640×480 PNGs on
device. That was the open question behind the whole fix: the alternative was Android's
`BitmapFactory`, which carries an **API 28 floor** ffmpeg does not. Probed *before* implementing,
because the recorded plan ("fall back to the ffmpeg we already ship") rested on an unchecked
assumption about this specific build.

- `ImageTranscoder` (interface) + `FfmpegImageTranscoder`, injected into `StaticEncoder`. It runs
  **only after** the pure-Dart decode fails, so ordinary images never pay the process spawn.
- `StaticEncoder._decode` returns `null` for every failure — a throw, a null, or a failed transcode —
  so `encode` keeps **one** throw site instead of three copies of the same message.
- `MediaKindResolver` now **accepts** heic/heif/avif. Note the extension branch is the one that
  actually runs: `image_picker` supplies no mime type on Android.
- ffmpeg is given the bytes with **no file extension** — it probes content, and guessing wrong is
  worse than saying nothing when the whole reason we are there is not knowing the format.

**ALL SIX video containers round-trip: mkv, avi, 3gp, m4v, mov, webm.** The first version of this
test transcoded H.264 into every one of them and reported **3gp and webm as unsupported — that was
wrong**. WebM cannot legally carry H.264, so the *muxer* refused an invalid combination; the
**demuxer** was never exercised, and the demuxer is what matters because a user hands us a file
someone else wrote. Give each container a codec it accepts and all six pass. Do not "fix" the
supported list on the strength of a write-side failure.

**Fixture limit, so a pass is not over-read:** the HEIC came from libheif, not a camera. An iPhone's
HEIC uses particular HEVC profiles and often carries several items (tiles, thumbnails, depth maps),
so this proves the container and codec path rather than every real-camera file. Fixtures are
generated by `tool/make_heic_fixture.py` and bundled as **assets** — the app has no storage
permission, so an `adb push`ed file fails to open.

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
Flutter (Dart) · Kotlin native glue · drift (SQLite + FTS5) · ffmpeg_kit_flutter_new_video + libwebp ·
Google ML Kit on-device (labeling + OCR) · Giphy HTTP API (free tier) · X syndication endpoint.
On-device TFLite embeddings exist in the tree but are **switched off** (see the semantic-search
section). `services/extractor/` (FastAPI + yt-dlp) is retained as a fallback and is **not** in the
request path.

## Build

```bash
flutter build apk --debug --dart-define=GIPHY_API_KEY=$(cat giphy_api_key.txt)
```

`GIPHY_API_KEY` is the **only** build-time input, and without it the GIF button simply does not
appear. Nothing else needs configuring: X links resolve on the phone, and everything else is local.
