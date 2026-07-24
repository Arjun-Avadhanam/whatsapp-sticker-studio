# Session Kickoff — WhatsApp Sticker Studio

Paste the prompt below at the start of a new Claude Code session run from
`~/whatsapp-sticker-project`. It loads context, verifies the build is actually green,
and picks up exactly where the last session stopped.

---

## The prompt

```
We're continuing the WhatsApp Sticker Studio build. Get fully oriented before writing any code:

1. ORIENT — read, in this order:
   - CLAUDE.md (rules, product constraints, WSL toolchain gotchas)
   - docs/superpowers/specs/2026-07-10-whatsapp-sticker-studio-design.md (the design)
   - docs/superpowers/plans/2026-07-10-whatsapp-sticker-studio-v1.md (16-task plan; find the
     first task whose checkboxes are unticked — that's where we are)

2. VERIFY STATE — don't trust the docs, confirm it. Run:
   export PATH="$HOME/flutter/bin:$PATH"     # REQUIRED: non-interactive shells skip ~/.bashrc
   git log --oneline -5 && git status --short && git branch --show-current
   flutter analyze && flutter test
   Report what's actually green vs. what the plan claims.

3. REPORT — tell me: current task, what's done, anything broken, and your proposed next step.
   Then wait for my go-ahead before implementing.

Key rules (also in CLAUDE.md): one feature branch per task; commit frequently; push after each
task; NEVER add "Co-authored-by" trailers; and never call a task complete until its tests pass —
show me the output.
```

---

## Fast facts for whoever picks this up

**Where things stand (2026-07-24):** Tasks 1–3 complete, merged to `main`, CI green — 35/35 tests,
analyze clean, format clean, debug APK builds (with drift's native SQLite). Next is **Task 4 —
sticker/pack validator**, branch `feat/validator`. Pure Dart, no device needed. Note Task 4 now
carries a **kind-homogeneity rule** (added 2026-07-18): every sticker's `kind` must match the pack's
`isAnimated`, as a backstop to the silent-promotion UX.

**Task 3 shipped** `lib/library/database.dart` (drift Stickers/Packs, `StringListConverter` for list
fields, `textEnum` for enums), the **committed** generated `database.g.dart` (CI does not run
build_runner), and `LibraryStore`/`DriftLibraryStore`. Two reusable gotchas it surfaced:
- **drift upsert + null:** pass an explicit `Companion` with `Value(null)` to
  `insertOnConflictUpdate`, not a data-class row — a data class serialises nulls as *absent*, so an
  upsert leaves a column unchanged and a field can never be cleared.
- **Dart optional-param defaults** resolve from the *static type*. A sentinel default (`_unset` for
  nullable `copyWith`/`updateMetadata` params) must be on BOTH the abstract interface and the impl,
  or "omitted" and "passed null" collapse for callers holding the interface type.

**Task 2 shipped** `WhatsAppSpec`, `media.dart` and immutable `StickerRecord`/`PackRecord` (enums,
`final` + `copyWith`, value equality — folded into spec and plan as source of truth). Records use
`listEquals`/`Object.hashAll` for list fields (`List`'s own `==` is identity).

**Read the "WhatsApp API realities" section in `CLAUDE.md` before Tasks 4, 11 or 13.** Researched
2026-07-18: WhatsApp validates independently of our code (you can't delete your way around a rule),
`avoid_cache` is deprecated, pack-refresh-after-update is an unfixed WhatsApp defect, and packs are
homogeneous — with an agreed silent-promotion strategy for statics joining animated packs.

**Toolchain gotchas — already solved, don't rediscover:**
- Flutter lives at `~/flutter`. Non-interactive shells don't read `~/.bashrc`, so every script must
  `export PATH="$HOME/flutter/bin:$PATH"` first.
- Android builds need **ninja**, supplied by `sdkmanager "cmake;3.22.1"`. Symptom if missing:
  `[CXX1416] Could not find Ninja`. Already installed on this machine.
- **`flutter test` does not prove the Android build works.** Also run `flutter build apk --debug`.
- CI (`.github/workflows/ci.yml`) runs format → analyze → test → debug APK on every push/PR.

**Not yet available:** no Android device is connected. Tasks **6** (animated encoder / FFmpeg),
**11** (WhatsApp ContentProvider handshake) and **15** (e2e) need a real phone over adb — in WSL2,
adb-over-Wi-Fi or `usbipd-win` are the workable routes; emulators inside WSL2 are painful.

**Also pending:** the tiny extraction service for Task 8B (`services/extractor/`, FastAPI + yt-dlp)
needs a deploy target chosen before the X-link source can work end-to-end.
