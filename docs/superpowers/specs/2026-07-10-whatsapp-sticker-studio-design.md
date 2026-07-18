# WhatsApp Sticker Studio — Design Spec

- **Date:** 2026-07-10 (rev. 2026-07-11: added X/Twitter-link source)
- **Status:** Approved design → implementation in progress
- **Author:** Arjun (with Claude)

---

## 1. Product summary

A **standalone Android app** that makes and organizes WhatsApp stickers far better than WhatsApp's built-in tools, and lives *beside* WhatsApp — connected only through WhatsApp's two officially sanctioned bridges. It does three things:

1. **Pro Maker** — turn an image / GIF / video (from the gallery, a Giphy search result, or a pasted **X/Twitter link**) into a high-quality 512×512 animated or static sticker, without WhatsApp's forced crop and short-duration limits.
2. **Searchable Library** — every sticker you make is auto-tagged (free, on-device vision) and enriched with optional manual metadata, then found instantly by keyword or meaning.
3. **Send / Share** — push stickers into WhatsApp as a pack (official "Add to WhatsApp") or share a single sticker via the share sheet, and share whole packs with friends.

The product's defensible core is the **loop no competitor closes**: *make → auto-tag → find → send*, where each made sticker becomes permanently findable.

---

## 2. Hard constraints from feasibility research (must respect)

These are verified facts (sources: `github.com/WhatsApp/stickers`, WhatsApp ToS, Android developer docs, Google Play policy) that shape every decision below.

- **No in-app integration.** Injecting UI/search/buttons *inside* WhatsApp's chat screen is only possible via Xposed/LSPosed (root), modified clients (GBWhatsApp-style), or accessibility-service injection — **all violate WhatsApp ToS and/or Google Play policy** and risk account bans. The app is therefore **standalone**, bridged by the official sticker `ContentProvider` + intent and the OS share sheet.
- **Official sticker spec (the ceilings the Maker must hit):** WebP only, exactly **512×512 px**; **static ≤ 100 KB**, **animated ≤ 500 KB**; tray icon **96×96 px, ≤ 50 KB**; **3–30 stickers per pack**; **1–10 packs per app**; animation **≤ 10 s total**, **≥ 8 ms per frame**. Packs cannot be pushed silently — the user confirms each "Add to WhatsApp".
- **Search backend is not swappable inside WhatsApp** (server-side). WhatsApp already migrated its GIF search from Tenor to **Giphy** (2026). So "better search" is not a better corpus — it is our own search UI + ranking + conversion workflow, using the **Giphy API** as a Maker source.
- **No usage endpoint.** WhatsApp exposes **no API** to read how many times a sticker was used inside WhatsApp; chats are E2E-encrypted and closed. We can only count sends that flow **through our app**. → A usage-stats dashboard is **out of scope**; a `usageCount` field is kept solely as a **ranking signal**.
- **Existing WhatsApp sticker library** lives in WhatsApp's private storage and is not readable via standard APIs. Importing it (via Storage Access Framework folder grant → images only, no WhatsApp metadata) is **deferred to v2**.
- **X/Twitter media has no free official API.** X killed its free API tier (Feb 2026; now pay-per-use ~$0.005/read). Media extraction therefore uses the same **unofficial route** all downloaders use (internal guest-token → GraphQL/player manifest → MP4), via battle-tested extractors (yt-dlp / cobalt). This works today but is **fragile** — X periodically changes required params. Mitigation: run extraction in a **minimal self-hosted service** so breakage is fixed server-side (update the extractor) without an app release. Note: a "Twitter GIF" is delivered as MP4, so it reuses the existing animated-encoder path.

---

## 3. Scope

### v1 (this spec)
- **Pillar 1 — Better generation + search**
  - Pro Maker: image / GIF / video → compliant 512×512 WebP, up to full 10 s, **smart-fit** (pad / subject-aware) instead of forced center-crop, size-budgeted quality encoding, **no ads**.
  - **Giphy search as a Maker source**: search Giphy → pick → convert → save → send.
  - **X/Twitter link as a Maker source**: paste a tweet link → a minimal self-hosted extractor (yt-dlp/cobalt) resolves the MP4 → convert → save → send. (Solves the "can't download a Twitter GIF without an online converter" pain.)
- **Pillar 2 — Better organisation**
  - Auto-tagging (free, on-device vision) of every made sticker.
  - Optional **manual metadata** (name, pack, tags, notes).
  - **Search** over combined auto + manual metadata: keyword + semantic.
- **Pack sharing with friends** — share a whole pack via WhatsApp's own pack-add flow (nearly free; reuses the Exporter).
- `usageCount` incremented on app-mediated sends, used only to rank library/search results (no stats UI).

### v1.1 (explicitly planned, not v1)
- **Maker enhancers** — both flagged here so they are designed-for but not built in v1:
  - **Background removal / auto-cutout** (free, on-device ML Kit Subject Segmentation).
  - **Text / caption overlay** (meme-style captions on stickers).

### v2
- **Import & reorganise existing WhatsApp stickers** — SAF folder grant → import `.webp` images → auto-tag. (Access-feasibility risk to validate first; yields images without WhatsApp's own pack/name metadata.)

### Out of scope (not planned)
- Any in-WhatsApp UI injection; usage-stats dashboard; public discovery feed; multi-provider public search; iOS; WhatsApp Web companion. (iOS remains *possible later* thanks to Flutter, but is not a goal.)

---

## 4. Architecture

Five isolated modules, each with one job and a clean interface, independently testable. The two highest-risk / most-swappable modules (**Encoder**, **Tagger**) sit behind interfaces so their backends can change without touching consumers.

```
        ┌────────────┐   Source (gallery / camera / share-in / Giphy / X-link)
        │   Sources  ├───────────────┐
        └────────────┘               ▼
                            ┌───────────────────┐
                            │      Encoder      │  media → compliant 512×512 WebP
                            │  (pure, no UI)    │
                            └─────────┬─────────┘
                                      ▼
   ┌─────────────┐  save     ┌───────────────────┐   query   ┌──────────────┐
   │   Tagger    │◀──────────│   Library store   │◀──────────│    Search    │
   │ (free, VLM) │  tags     │ (SQLite + files)  │  results  │ (free)       │
   └─────────────┘──────────▶└─────────┬─────────┘           └──────────────┘
                                       ▼
                             ┌───────────────────┐
                             │     Exporter      │  pack → WhatsApp (ContentProvider
                             │   + Sharing       │  + intent); single → share sheet;
                             └───────────────────┘  pack → friend; usageCount++
```

### 4.1 Sources (`Source` interface)
Abstracts where input media comes from. **v1 sources:** gallery pick, camera, share-into-app, **Giphy search**, **X/Twitter link**. Each is *just another Source*, so all input paths are fully in v1. Interface: `Source.pick() → MediaHandle` (bytes/URI + kind: image | gif | video). New providers (custom corpus, other APIs) drop in later without Maker changes.

The **X-link source** posts the pasted URL to a minimal self-hosted extraction endpoint (yt-dlp or cobalt behind a small FastAPI service), receives the resolved MP4 URL, downloads it, and returns a `MediaHandle` of kind `video`. Keeping extraction server-side means X-format breakage is fixed by updating the extractor, not by shipping a new app build.

### 4.2 Encoder (the core engineering risk)
Pure module: **media in → spec-compliant WebP out**, no UI. Responsibilities:
- Decode input (static image, animated GIF, or video frames via FFmpeg).
- Apply user edit params: **fit mode** (smart-pad / subject-aware fit / manual crop), **trim** (≤ 10 s), target quality.
- Encode to **512×512 WebP**, static or animated, enforcing **all ceilings** (≤ 100 KB static / ≤ 500 KB animated, ≥ 8 ms/frame, ≤ 10 s).
- **Size budgeting with visible, progressive degradation:** if it cannot meet 500 KB at acceptable quality, it reduces fps → frames → then dimensions/quality, surfacing a live **size vs. quality readout**. It never silently emits a file WhatsApp will reject.

This is the hardest part: animated-WebP-under-500-KB with good quality. Encoding via `libwebp` (`img2webp`/`cwebp`) and/or FFmpeg. Keep behind an `Encoder` interface so the encoding backend can be swapped.

### 4.3 Tagger (free, on-device — swappable)
On save, produces structured tags from the sticker image, **asynchronously** (library is usable before tagging finishes; failures retried; search still works on manual metadata + name meanwhile).

- **v1 default backend (FREE, offline, no keys):** Google **ML Kit** on-device **Image Labeling** (subjects/objects/scene) + **Text Recognition / OCR** (text-in-image). Zero cost, no rate limits, private.
- **Optional adapter (still free):** a **free-tier hosted VLM** (e.g. Gemini API free tier or Groq free-tier vision) behind the same `TaggingService` interface, for richer natural-language tags — opt-in, within free limits. **No paid vision model is used.**

Tag schema: `subjects[]`, `emotion/reaction`, `action`, `textInImage`, `suggestedName`, `style`.

### 4.4 Library store
Local **SQLite** (via `drift`) + a WebP file store. Owns CRUD and the search index. Records:

- **Sticker:** `id`, `filePath`, `thumbnailPath`, `kind` (static|animated), `packId`, `autoTags[]`, `manualName`, `manualTags[]`, `notes`, `source`, `createdAt`, `usageCount`, `sizeBytes`, `taggingStatus`.
- **Pack:** `id`, `name`, `trayIconPath`, `isAnimated`, `stickerIds[]`, `createdAt`. (Mirrors WhatsApp's pack model; required for export — 3–30 stickers, one tray icon.)

`isAnimated` maps to WhatsApp's pack-level `animated_sticker_pack` flag: **a pack is all-static or
all-animated, never mixed**, and the flag also selects the size ceiling (100 KB vs 500 KB). Rather
than surfacing this to the user, the Maker **silently promotes** a static sticker to animated
(re-encoded as ≥2 identical frames) when it joins an animated pack — decided 2026-07-18, rationale
and the ruled-out single-frame variant in `CLAUDE.md`.

Both records are **immutable value types**: all fields `final`, updates via `copyWith()`, value
`==`/`hashCode`. `taggingStatus` (`pending|done|failed`) and `source` (`maker|gallery|camera|shareIn|giphy|xLink`)
are **enums**, not free-form strings, so invalid states can't be constructed and the compiler
catches every unhandled case at the switch sites.

### 4.5 Search (free)
Query over a combined text blob = `autoTags + manualName + manualTags + notes`. Two layers, both free:
- **Keyword:** SQLite **FTS5** (fast, offline, always available).
- **Semantic:** free embeddings — **on-device sentence-embedding model** (TFLite) with cosine similarity over the (personal-scale) library; FTS5 as fallback if embeddings unavailable. Optional free-tier hosted embeddings behind the same `SearchService` interface.
- **Ranking:** blends match score with `usageCount` recency/frequency so frequently-sent stickers surface first.

### 4.6 Exporter + Sharing
- **Add to WhatsApp:** implements `StickerContentProvider` (metadata + asset URIs, `com.whatsapp.sticker.READ`) and fires `ENABLE_STICKER_PACK` with `sticker_pack_id`, `sticker_pack_authority`, `sticker_pack_name`.
- **Pre-export validation:** reuse WhatsApp's `StickerPackValidator` logic to check *every* ceiling **before** launching WhatsApp; surface exactly what's non-compliant. Never hand WhatsApp a pack it will reject.
- **Single-sticker share:** share-sheet the WebP to WhatsApp (or anywhere).
- **Pack sharing with friends:** share the pack via WhatsApp's pack-add flow.
- Increments `usageCount` on every app-mediated send/export.

---

## 5. Data flow

```
gallery / Giphy-pick / X-link → Encoder (compliant WebP) → Library.save() + file store
                                                        │
                                     async Tagger fills autoTags
                                                        │
                                 user optionally adds manual metadata
                                                        │
                                     Search indexes combined blob
                                                        │
                        query → ranked results → Exporter → WhatsApp / friend
                                                        │
                                              usageCount++ (ranking only)
```

---

## 6. Technology stack

- **App:** **Flutter (Dart)** — fast UI, gentle curve from Python, one codebase toward possible future iOS.
- **Native glue:** **minimal Kotlin** — use a maintained Flutter WhatsApp-sticker-export package if it supports **animated** packs; otherwise a small hand-written Kotlin `ContentProvider`. (Plan-time verification — see §9.)
- **Encoding:** `ffmpeg_kit_flutter` + `libwebp`.
- **Vision/tagging:** **FREE** — ML Kit on-device (labeling + OCR) default; optional free-tier hosted VLM adapter. No paid model.
- **Search:** SQLite **FTS5** + free on-device embeddings.
- **Storage:** local SQLite (`drift`) + WebP file store.
- **Backend:** **minimal in v1** — one small **FastAPI** service exposing a single `POST /extract` endpoint that wraps **yt-dlp** (or a self-hosted **cobalt** instance) to resolve an X/Twitter link → MP4 URL. This is the only server dependency in v1 and exists solely for the X-link source. It is also the first slice of the backend that can later absorb the `TaggingService`/`SearchService` interfaces (keys server-side, sync, scaling) without app changes.

---

## 7. Error handling (the parts that bite)

- **Encoder can't hit 500 KB at good quality** → progressive, *visible* degradation (fps → frames → dims/quality) with a live size/quality readout; never emit a rejectable file.
- **Pack fails validation** (count 3–30, tray 96×96 ≤ 50 KB, dims/sizes) → block export, show precisely what's wrong.
- **Tagger offline / fails** → sticker still saved; `taggingStatus` = `TaggingStatus.pending` (or `failed` after a terminal error); retried; search works on manual metadata + name meanwhile.
- **WhatsApp not installed** → disable/relabel Add-to-WhatsApp and share actions gracefully.
- **Giphy API unavailable / rate-limited** → degrade to other sources; never block the Maker.
- **X-link extraction fails** (private/deleted tweet, X changed its params, service down) → show a clear "couldn't fetch this tweet's media" message and fall back to other sources; never crash the Maker. Log the failure to prompt an extractor update.

---

## 8. Testing strategy

- **Encoder golden tests:** across static image / GIF / mp4 and portrait / landscape / square inputs, assert outputs satisfy **every** ceiling (512×512, size, ≤ 10 s, ≥ 8 ms/frame).
- **Exporter:** run WhatsApp's `StickerPackValidator` against generated packs; assert the intent handshake extras.
- **Search:** query → expected-sticker fixtures (keyword + semantic).
- **Tagger:** interface contract tests with a stub backend (so tests don't depend on ML Kit/network).
- **Module isolation:** each module tested behind its interface without the others.

---

## 9. Plan-time decisions & verifications (deferred, not blocking)

1. **Flutter sticker-export package supports animated packs?** If not, write the small Kotlin `ContentProvider`. (Bounded either way.)
2. **Free embedding model choice** (which on-device TFLite sentence model) — pick at plan time; FTS5 works regardless.
3. **Giphy API terms / production key & rate limits** — confirm free-tier fit (trivial at personal scale).
4. **Optional free-tier VLM** (Gemini vs Groq free tier) — only if richer tags are wanted beyond ML Kit.
5. **X-link extractor choice & hosting** — yt-dlp-in-FastAPI vs self-hosted cobalt; where to host the tiny service (personal VPS / free-tier PaaS). Confirm current X extraction works at build time (`yt-dlp -U`).

---

## 10. Risks

- **Encoder quality/size tradeoff** is the main technical risk — mitigate with the progressive-degradation strategy and golden tests early.
- **WhatsApp changes the sticker spec** without notice — re-verify ceilings against `github.com/WhatsApp/stickers` before building; centralize the constants.
- **v2 existing-library import** may prove infeasible past image extraction — kept out of v1 so v1 never depends on it.
- **Free-tier dependencies** (Giphy, optional hosted VLM) can change — the on-device defaults (ML Kit, FTS5) keep the app fully functional and free without them.
- **X-link extraction is unofficial and fragile** — X changes break extractors periodically. Mitigated by (a) using maintained extractors (yt-dlp/cobalt), (b) keeping extraction server-side so a fix is a service update not an app release, and (c) graceful fallback to other sources. The rest of the app is fully functional if X extraction is temporarily down.

---

## 11. The loop, restated

*Make a better sticker → it's auto-tagged and saved → find it instantly by meaning → one-tap send/share.* WhatsApp can't organize or search your stickers; Sticker.ly is a maker + public feed, not a personal semantic library. This spec builds the closed loop neither of them does — for free, and without touching WhatsApp's ToS.
