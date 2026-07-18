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

**Unverified, needs an on-device test when a phone is available:**
- Is the 3-sticker minimum actually enforced at runtime? Every source is a developer working *around*
  it (apps reportedly pad with transparent stickers), never a statement of what WhatsApp does. Given
  the independent-validation finding above, assume enforced until proven otherwise.
- Does the ≥2-identical-frame promotion pass WhatsApp's **closed-source** validator? It passes every
  documented check, but their validator is stricter than the sample. **Fallback if it fails:
  pack-type-chosen-at-creation (Sticker.ly's model).**
- Can a pack's `animated_sticker_pack` flag flip after install? Undocumented in every source. Weak
  signal suggests it may be sticky.

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
