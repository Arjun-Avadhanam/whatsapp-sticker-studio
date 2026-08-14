"""Renders launcher-icon candidates for Sticker Studio.

Constraint that shapes all of these: the app is a **standalone third-party app**,
so nothing may imply official WhatsApp affiliation — no WhatsApp green
(#25D366), no phone-in-speech-bubble, no WA mark. That is a ToS/trademark
position, not a taste one.

Second constraint: Android adaptive icons are masked to whatever shape the
launcher chooses (circle, squircle, teardrop), and only the centre ~66% is
guaranteed visible. Every candidate is drawn inside that safe zone.

Usage:
    python3 tool/make_icon_candidates.py <output-dir>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SAFE = int(SIZE * 0.66)  # adaptive-icon safe zone
PAD = (SIZE - SAFE) // 2


def _bg(colour: tuple[int, int, int]) -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE), colour + (255,))


def peeling_corner(bg: tuple[int, int, int], face: tuple[int, int, int],
                   under: tuple[int, int, int]) -> Image.Image:
    """A sticker with one corner curling up — the universal 'sticker' shorthand.

    Reads as a silhouette, which is what keeps it legible at 48 dp.
    """
    img = _bg(bg)
    d = ImageDraw.Draw(img)

    x0, y0 = PAD, PAD
    x1, y1 = SIZE - PAD, SIZE - PAD
    curl = SAFE * 0.34

    # The sticker face, with the peeled corner cut away (bottom-right).
    d.polygon(
        [(x0, y0), (x1, y0), (x1, y1 - curl), (x1 - curl, y1), (x0, y1)],
        fill=face + (255,),
    )
    # The curl itself: the underside showing through, lighter than the face.
    d.polygon(
        [(x1, y1 - curl), (x1 - curl, y1), (x1 - curl * 0.45, y1 - curl * 0.45)],
        fill=under + (255,),
    )
    return img


def die_cut(bg: tuple[int, int, int], face: tuple[int, int, int]) -> Image.Image:
    """A die-cut sticker: irregular shape inside the thick white border.

    Closer to what the app actually *produces* — a 512² sticker with transparent
    margins — but the border has to be thick to register when small.
    """
    img = _bg(bg)
    d = ImageDraw.Draw(img)
    cx, cy = SIZE // 2, SIZE // 2
    r = SAFE // 2

    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 255))
    inner = int(r * 0.78)
    d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=face + (255,))
    # A simple mark so it is a sticker *of* something rather than a plain dot.
    eye = int(inner * 0.22)
    for dx in (-inner // 2, inner // 2):
        d.ellipse(
            [cx + dx - eye, cy - eye * 2, cx + dx + eye, cy],
            fill=(255, 255, 255, 255),
        )
    d.arc(
        [cx - inner // 2, cy - inner // 4, cx + inner // 2, cy + inner // 2],
        start=15, end=165, fill=(255, 255, 255, 255), width=int(r * 0.09),
    )
    return img


def sticker_and_spark(bg: tuple[int, int, int], face: tuple[int, int, int],
                      spark: tuple[int, int, int]) -> Image.Image:
    """Sticker plus a spark — says *studio*, not just *sticker*.

    Two elements is pushing it at 48 dp; included so the tradeoff is visible
    rather than argued about.
    """
    img = _bg(bg)
    d = ImageDraw.Draw(img)

    x0, y0 = PAD, PAD + int(SAFE * 0.10)
    x1, y1 = SIZE - PAD - int(SAFE * 0.10), SIZE - PAD
    curl = SAFE * 0.30
    d.polygon(
        [(x0, y0), (x1, y0), (x1, y1 - curl), (x1 - curl, y1), (x0, y1)],
        fill=face + (255,),
    )

    # Four-point spark, top-right.
    sx, sy = SIZE - PAD - int(SAFE * 0.04), PAD + int(SAFE * 0.06)
    a, b = int(SAFE * 0.16), int(SAFE * 0.05)
    d.polygon(
        [(sx, sy - a), (sx + b, sy), (sx, sy + a), (sx - b, sy)],
        fill=spark + (255,),
    )
    d.polygon(
        [(sx - a, sy), (sx, sy - b), (sx + a, sy), (sx, sy + b)],
        fill=spark + (255,),
    )
    return img


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)

    # Deliberately nowhere near WhatsApp green. Deep indigo and warm amber both
    # stand out on a phone full of blue-green icons.
    candidates = {
        "1_peel_indigo": peeling_corner(
            bg=(38, 42, 84), face=(255, 209, 84), under=(255, 240, 200)
        ),
        "1_peel_coral": peeling_corner(
            bg=(32, 34, 44), face=(240, 96, 84), under=(255, 196, 186)
        ),
        "2_diecut_teal": die_cut(bg=(18, 62, 74), face=(74, 200, 190)),
        "3_spark_indigo": sticker_and_spark(
            bg=(38, 42, 84), face=(255, 209, 84), spark=(255, 255, 255)
        ),
    }

    for name, img in candidates.items():
        img.save(out / f"{name}_1024.png")
        # 48 dp is where an icon lives or dies — most of the time it is seen at
        # roughly this size in a launcher grid.
        img.resize((48, 48), Image.LANCZOS).save(out / f"{name}_48.png")

    # A contact sheet, so they can be compared side by side at real size.
    sheet = Image.new("RGBA", (SIZE // 2 * len(candidates), SIZE // 2 + 120),
                      (255, 255, 255, 255))
    for i, img in enumerate(candidates.values()):
        sheet.paste(img.resize((SIZE // 2, SIZE // 2), Image.LANCZOS),
                    (i * SIZE // 2, 0))
        sheet.paste(img.resize((96, 96), Image.LANCZOS),
                    (i * SIZE // 2 + SIZE // 4 - 48, SIZE // 2 + 12))
    sheet.save(out / "contact_sheet.png")

    print(f"wrote {len(candidates)} candidates + contact_sheet.png to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
