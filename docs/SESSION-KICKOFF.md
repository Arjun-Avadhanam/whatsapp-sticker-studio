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

**Where things stand (2026-07-29):** Tasks 1–5, **5b**, 8 and 8B merged/committed. 76 Flutter tests
+ 4 on-device integration tests + 4 backend pytest; analyze + format clean; debug APK builds.
**Task 5b is now DONE and device-verified** — `main` is no longer the whole story: Task 5b sits on
the branch **`feat/encoder-native`** (commit a9f0ee0), not yet merged or pushed.

**THE DEVICE IS NOW WORKING.** usbipd-win forwards the phone into WSL — full `adb`, hot reload,
logcat and `integration_test`. **Read the "Connecting the Android device" section in `CLAUDE.md`
first**; it has the exact commands and the three failure symptoms. Per-session you need one attach:
`"/mnt/c/Program Files/usbipd-win/usbipd.exe" attach --wsl --busid 2-4` (no admin needed).

**NEXT: Task 6 (animated encoder), starting at its Step 1.** The dependency question is settled and
the APK builds against `ffmpeg_kit_flutter_new_video` — but **nobody has yet run ffmpeg on the device
to prove it can mux animated WebP**. Do that before writing `AnimatedEncoder`; if libwebp turns out
to be absent, the variant must change first. Then Step 5b's `promoteStatic` (≥2 identical frames).

Remaining order after that:
1. **Task 7** — real gallery/camera/share-in pickers (`image_picker`, `receive_sharing_intent`).
2. **Task 9** — real ML Kit tagger. **Task 12** — real share sheet.
3. **Task 11** — WhatsApp handshake (**needs a real phone with WhatsApp installed**, not an emulator).
   Consider pulling this *earlier*: it answers whether the 3-sticker minimum is truly enforced and
   whether the ≥2-frame promotion survives WhatsApp's closed-source validator — and a "no" on the
   latter changes Task 13's whole flow, which is expensive to learn after building the Maker UI.
4. **Tasks 13/14** — UI. **Task 15** — end-to-end. **Task 10** (search) is device-free, any time.

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

**Device access: SOLVED (2026-07-29)** via `usbipd-win` — see `CLAUDE.md`. Phone is A059P /
Android 16 (API 36), BUSID `2-4`, serial `<device-serial>`. Note that `adb.exe` on the *Windows*
side will steal the device from WSL; kill that server if `attach` reports "Device busy".

**Also pending:** the tiny extraction service for Task 8B (`services/extractor/`, FastAPI + yt-dlp)
needs a deploy target chosen before the X-link source can work end-to-end.
