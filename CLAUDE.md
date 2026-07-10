# WhatsApp Sticker Studio — Working Rules

## Implementation rules (always)
- Commit frequently. One feature branch per task (`feat/<task>`). Push to GitHub after each task.
- **NEVER add "Co-authored-by" trailers to commit messages.**
- Full testing before "done": run the test suite (unit + backend/integration where possible). Report a task complete **only after** its tests pass — never claim completion on untested code.

## Product constraints (WhatsApp sticker spec — do not violate)
- WebP only, exactly **512×512**. Static **≤ 100 KB**, animated **≤ 500 KB**. Tray icon **96×96 ≤ 50 KB**.
- **3–30** stickers/pack; **1–10** packs. Animation **≤ 10 s**, **≥ 8 ms/frame**.
- **Vision/tagging must be FREE** — on-device ML Kit default; free-tier hosted adapters only. No paid model.
- **Standalone app.** Integrate ONLY via the official sticker `ContentProvider` + intent and the OS share sheet. No in-WhatsApp UI injection (ToS/ban risk).

## Where things are
- Design spec: `docs/superpowers/specs/2026-07-10-whatsapp-sticker-studio-design.md`
- Implementation plan: `docs/superpowers/plans/2026-07-10-whatsapp-sticker-studio-v1.md`

## Tech stack
Flutter (Dart) · Kotlin native glue · drift (SQLite + FTS5) · ffmpeg_kit_flutter + libwebp · Google ML Kit on-device (labeling + OCR) · on-device TFLite embeddings · Giphy HTTP API (free tier).
