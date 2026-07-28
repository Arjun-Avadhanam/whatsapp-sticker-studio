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

**Where things stand (2026-07-25):** Tasks 1–5 and 8 merged to `main` (CI green); **Task 8B
code-complete, pushed on `feat/xlink-source`, awaiting CI → merge**. 72 Flutter tests + 4 backend
pytest, analyze + format clean, debug APK builds. **Task 5 is the device-free half only** — its real
WebP encode (Task 5b) is deferred to the device session.

**NEXT SESSION = THE DEVICE BATCH (bring the Android phone).** All fully device-free work is done
(8 Giphy, 8B X-link). The only remaining device-free option is **Task 10 (search)** if you want a
warm-up; otherwise go straight to the device batch. Sequencing decided 2026-07-25: do split/native
tasks WHOLE on the device rather than fragmenting them. Order:
1. **Task 5b + 6** — real `WebpEncoder` + animated encoder (shared `ffmpeg_kit` dependency).
2. **Task 7** — real gallery/camera/share-in pickers (`image_picker`, `receive_sharing_intent`).
3. **Task 9** — real ML Kit tagger. **Task 12** — real share sheet.
4. **Task 11** — WhatsApp handshake (**needs a real phone with WhatsApp installed**, not an emulator).
5. **Tasks 13/14** — UI. **Task 15** — end-to-end.
Device is first strictly required at Task 6. Verify each device task once, at its end.

**Two live-verifications to run next session (both need external input, see `CLAUDE.md`):**
- **Giphy:** create a free key at developers.giphy.com → run the client against the real API
  (`--dart-define=GIPHY_API_KEY=…`, never commit); record rate limits + "Powered by GIPHY".
- **X-link extractor:** run `services/extractor` against a **known-video tweet URL** to confirm the
  success path (the real service already reaches Twitter; only success unconfirmed). Then pin the
  yt-dlp version and pick a deploy target.

**Tasks 1–5, 8, 8B shipped** — full detail in the auto-memory `project_state.md` and the plan's
ticked steps. Recurring lessons already captured there: drift upsert needs `Companion`+`Value(null)`
to clear a field; sentinel defaults must match on interface + impl; the `image` pkg can't encode
WebP (native step deferred); `decodeImage` throws on tiny buffers.

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
