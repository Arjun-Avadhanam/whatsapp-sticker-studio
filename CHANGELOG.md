# Changelog

All notable changes to this project are recorded here, newest first.

Versions are `MAJOR.MINOR.PATCH+BUILD`, matching the `version:` line in
`pubspec.yaml`, which is what Android reads as `versionName` and `versionCode`.

- **MAJOR** changes the shape of a user's data or how the app integrates with
  WhatsApp, in a way that is not backward compatible.
- **MINOR** adds a capability the user can see.
- **PATCH** fixes or refines something that already exists.
- **BUILD** increments on every build that leaves the machine, and never resets.
  Android requires it to be strictly increasing for an upgrade to install.

The database `schemaVersion` in `lib/library/database.dart` is deliberately
separate and moves on its own schedule, since a release often changes neither.

## 1.2.0 (build 4)

### Added

- "Send to WhatsApp" on a saved sticker, which sends that sticker on its own and
  makes its name visible in WhatsApp for the first time.

  WhatsApp's third-party sticker API has no per-sticker display name. The only
  per-sticker text field is an accessibility label, which screen readers
  announce and nothing draws, so every sticker in the tray shows its pack's
  name. Naming a sticker therefore had no visible effect there at all. Sending
  it as a pack of one, named after the sticker, is the only way the name
  appears.

  The pack is scaffolding rather than something to keep, so it is discarded once
  WhatsApp has it. The sticker itself stays in the library, and WhatsApp keeps
  its imported copy. Discarding also frees the slot, since an app may publish at
  most ten packs and the feature would otherwise stop working after ten.

  Known and accepted: WhatsApp's tray gains one section per sticker sent this
  way. Nothing can avoid that while the pack name is the only name WhatsApp
  renders.

## 1.1.1 (build 3)

### Fixed

- A clip that failed to fit under the size ceiling left no way to try again.
  The error asked the user to trim the clip shorter, but the only "Update
  preview" button was drawn inside the size readout, which is not shown when
  there is no preview. Failing therefore removed the readout, the notice and
  the retry control together, so moving the sliders appeared to do nothing.
  The prompt now sits below the clip controls and appears whenever the current
  settings have not produced a preview, whether that is because they changed or
  because the last attempt failed.

## 1.1.0 (build 2)

### Added

- The clip trim sliders are now bounded by the video's real length, which is
  read once when the media loads. The Maker also shows how much clip there is to
  work with.

### Fixed

- A trim start could be set past the end of a short clip, which produced an
  encode containing no frames. The Start and Length sliders are now clamped to
  the clip, so the state is no longer reachable. This was most visible on X
  posts, where the video has usually never been watched before it is trimmed,
  but it affected gallery and Giphy clips equally.

## 1.0.0 (build 1)

First complete version, verified end to end on a physical device against
WhatsApp 2.26.27.85.

### Added

- Make stickers from the gallery, the camera, a shared file, a pasted X post
  link, or Giphy search, fitted to 512x512 and encoded as WebP within
  WhatsApp's size ceilings.
- HEIC and AVIF photos, through an ffmpeg fallback used only when the Dart
  decoder cannot read the file.
- A local library with full-text search, where a name typed by the user
  outranks a machine-generated tag.
- On-device labelling and text recognition, run after the save so a tagging
  failure can never cost a sticker.
- Packs, with silent promotion of static stickers when they join an animated
  pack, and export to WhatsApp through the official ContentProvider and intent.
- Emoji per sticker, which is what WhatsApp's own in-tray search reads.
- Export of a single sticker as a file through the system share sheet.

### Notes

- Semantic search was built, measured on a real library, and switched off,
  because it could not distinguish a real query from nonsense.
- Pack sharing between phones is not possible: WhatsApp identifies a pack by a
  ContentProvider authority that exists only on the device that created it.
