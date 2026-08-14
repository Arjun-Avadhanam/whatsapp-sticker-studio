"""Generates HEIC / HEIF / AVIF fixtures for the format-support probe.

Why this exists: the test phone (Nothing A059P) cannot *take* HEIC photos, and
HEIC is the gap we are closing — so the fixture has to be synthesised. libheif
produces genuine HEIC, which is enough to answer "can our decode path read this
container at all".

**Known limit, stated so nobody over-reads a pass:** an iPhone's HEIC is not
byte-identical in structure to libheif's. Apple uses particular HEVC profiles and
often stores multiple items (tiles, thumbnails, depth maps). Decoding this file
proves the container and codec path works; it does not fully prove every
real-camera file will.

Usage:
    pip install pillow-heif
    python3 tool/make_heic_fixture.py <output-dir>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw
import pillow_heif

pillow_heif.register_heif_opener()

# AVIF registration moved out of pillow_heif in newer releases; Pillow itself
# handles AVIF when built with libavif. Registered opportunistically so a missing
# AVIF writer degrades to "AVIF fixture not written" rather than failing the run —
# HEIC is the gap that matters.
if hasattr(pillow_heif, "register_avif_opener"):
    pillow_heif.register_avif_opener()


def source_image() -> Image.Image:
    """Structured, photo-like content — not noise.

    Noise is maximum-entropy and will not fit the sticker byte ceiling at any
    quality, so a fixture made of noise would fail the encode for reasons that
    have nothing to do with the format under test.
    """
    img = Image.new("RGB", (640, 480), (28, 96, 168))
    draw = ImageDraw.Draw(img)
    draw.ellipse((180, 60, 460, 340), fill=(250, 214, 42))
    draw.rectangle((120, 330, 520, 430), fill=(232, 76, 60))
    return img


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)

    img = source_image()
    written = []
    for name, kwargs in [
        ("fixture.heic", {"format": "HEIF"}),
        ("fixture.avif", {"format": "AVIF"}),
    ]:
        path = out / name
        try:
            img.save(path, **kwargs)
            written.append(f"{name} ({path.stat().st_size} bytes)")
        except Exception as exc:  # noqa: BLE001 - report and continue
            written.append(f"{name} FAILED: {exc}")

    # A JPEG control, so a probe failure can be attributed to the format rather
    # than to the fixture or the harness.
    jpg = out / "fixture.jpg"
    img.save(jpg, format="JPEG", quality=90)
    written.append(f"fixture.jpg ({jpg.stat().st_size} bytes)")

    print("\n".join(written))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
