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
