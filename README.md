# Sticker Studio

A standalone Android app for making WhatsApp stickers from photos, videos, GIFs, X posts and Giphy,
then organising them in a searchable local library and sending them into WhatsApp's sticker tray.

Everything runs on the device. Image labelling and text recognition happen on-device with ML Kit, encoding happens on-device with Android's WebP encoder and ffmpeg, and the library is a local SQLite database.

## Why it exists

WhatsApp accepts stickers only in a narrow format: WebP, exactly 512x512, under 100 KB when static
and under 500 KB when animated. Packs must be all static or all animated, never mixed. After a lot of personal frustration, I wanted to create an app that made this process easier for users.

So I made sure nearly all constraints are handled and absorbed where they can be, and users are told only about errors they can act on.


## What it does

**Make.** Bring in media from the gallery, the camera, a shared file, a pasted X post link, or Giphy
search. Choose how it is fitted into the 512x512 frame, trim a clip, and see the encoded size against
WhatsApp's ceiling before saving.

**Organise.** Saved stickers are labelled automatically on-device, then indexed for full-text search.

**Send.** Group stickers into packs and add them to WhatsApp through the official sticker
ContentProvider and intent. Individual stickers can also be exported as files through the system
share sheet (these land in WhatsApp as an ordinary image sadly, not as a sticker, because the tray is
reachable only through a pack).

## How it works

Media arrives through a `Source`, which is a small interface with a single `pick()` method. Gallery,
camera, share-in, X links and Giphy all implement it, so the Maker treats every origin identically
and each one is testable without a device.

From there the pipeline is the same regardless of origin:

1. **Decode.** Stills decode in Dart. Anything the Dart decoder cannot read, such as HEIC or AVIF,
   falls back to ffmpeg transcoding. Video and GIF go straight to ffmpeg.
2. **Fit.** The image is padded or cropped to exactly 512x512.
3. **Encode.** Stills use Android's built-in WebP encoder over a method channel, walking a quality
   ladder from 100 downward and stopping at the first result under the size ceiling. Animation uses
   ffmpeg with libwebp, degrading frame rate first because encoded size is close to linear in frame
   count.
4. **Store.** The record goes into SQLite via drift, with an FTS5 index maintained inside the store
   itself so no caller can forget to update it.
5. **Tag.** ML Kit labelling and OCR run after the save, never as a precondition, so a tagging
   failure can never cost a user a sticker.
6. **Export.** A pack is validated against WhatsApp's rules, staged to disk, and handed over by
   intent. Validation collects every problem at once rather than stopping at the first.

### X posts

X post links are resolved on the device by calling the endpoint X's own embed widgets use. There is
no server involved.


## Requirements

- Flutter, with a Dart SDK of 3.12 or newer
- Android SDK, with compile SDK 37
- Android 7.0 (API 24) or newer on the device, which is the floor imposed by the ffmpeg package
- A free Giphy API key, only if you want the Giphy source

## Building

```bash
flutter pub get
flutter build apk --debug --dart-define=GIPHY_API_KEY=your_key_here
```

The Giphy key is the only build-time input, and it is optional. Without it the app simply does not
show the GIF button. Nothing else needs configuring.

Do not commit the key. `giphy_api_key.txt` is git-ignored and exists so local builds can read it:

```bash
flutter build apk --debug --dart-define=GIPHY_API_KEY=$(cat giphy_api_key.txt)
```

## Testing

```bash
flutter analyze
flutter test
```

Tests that need hardware live in `integration_test/device_test.dart`, which is a single
entry point.

Note that running `flutter test integration_test` uninstalls the app when it finishes, and an Android
uninstall erases app data. Back up the device library first if it contains anything you want to keep.
The commands for doing so are in `CLAUDE.md`.

## Layout

```
lib/
  app/         composition root, the only place that names concrete classes
  core/        shared value types and the WhatsApp spec constants
  models/      sticker and pack records
  sources/     gallery, camera, share-in, X links, Giphy
  encoder/     fit to 512x512, WebP and animated WebP encoding
  library/     drift database, store, FTS5 index
  search/      query parsing and ranking
  tagger/      ML Kit labelling and OCR
  packs/       pack membership and static-to-animated promotion
  export/      validation, staging, WhatsApp intent
  sharing/     system share sheet, for exporting a single sticker file
  ui/          Make, Library and Packs screens
android/       Kotlin: WebP encoder, sticker ContentProvider, export intent
services/      retired X extractor, kept as a fallback
docs/          design spec and implementation plan
tool/          icon and test-fixture generators
```

Every platform-touching collaborator sits behind an interface and is assembled in `lib/app`.

## Status

Version 1 is feature complete and has been verified end to end on a physical device against
WhatsApp 2.26.27.85.

Known and accepted: encoding a video takes roughly 15 to 20 seconds, and selection among multiple
video renditions for X posts is covered by unit tests but has not yet been exercised against a real
multi-rendition post.

## A note on WhatsApp

This is an independent project. It is not affiliated with, endorsed by, or connected to WhatsApp or
Meta. It integrates only through the documented third-party sticker API, the official ContentProvider
and intent, and the system share sheet. It does not modify WhatsApp or inject anything into it.

## License

No license has been granted yet, so all rights are reserved by default. If you want to use any of
this, please open an issue and ask.
