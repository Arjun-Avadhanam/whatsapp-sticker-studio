"""Renders launcher-icon candidates for Sticker Studio.

Two constraints shape all of these.

**No WhatsApp visual borrowing.** The app is a standalone third-party app, so
nothing may imply official affiliation — no WhatsApp green (#25D366), no
phone-in-speech-bubble, no WA mark. That is a ToS/trademark position, not taste.

**It has to survive 48 dp and a circular mask.** Android adaptive icons are
masked to whatever shape the launcher wants, and only the centre ~66% is
guaranteed visible. Round one failed on exactly this: a flat "peeling corner"
read as a plain square with a nicked corner, because a curl needs a shadow and a
distinct underside to be legible at all. Every candidate here is rendered at
48 dp in the contact sheet so that failure mode is visible rather than argued.

Usage:
    python3 tool/make_icon_candidates.py <output-dir>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SAFE = int(SIZE * 0.66)
PAD = (SIZE - PAD_) // 2 if (PAD_ := 0) else (SIZE - SAFE) // 2

WHITE = (255, 255, 255)


def _canvas(bg: tuple[int, int, int]) -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE), bg + (255,))


def _shadow(shape: list[tuple[float, float]], blur: int = 26,
            offset: int = 18) -> Image.Image:
    """A soft drop shadow, which is what makes a sticker look lifted off.

    Round one omitted this and the peel simply did not read.
    """
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(
        [(x, y + offset) for x, y in shape], fill=(0, 0, 0, 110)
    )
    return layer.filter(ImageFilter.GaussianBlur(blur))


def peel_with_backing(bg, face) -> Image.Image:
    """Die-cut white border + a corner peeling to show the white backing.

    The most literally "sticker" of the set: the border is what a real die-cut
    sticker has, and the curl reveals the backing paper rather than a mystery
    lighter shade.
    """
    img = _canvas(bg)
    x0, y0, x1, y1 = PAD, PAD, SIZE - PAD, SIZE - PAD
    curl = SAFE * 0.32
    body = [(x0, y0), (x1, y0), (x1, y1 - curl), (x1 - curl, y1), (x0, y1)]

    img.alpha_composite(_shadow(body))
    d = ImageDraw.Draw(img)
    d.polygon(body, fill=WHITE + (255,))  # die-cut border

    inset = SAFE * 0.075
    d.polygon(
        [
            (x0 + inset, y0 + inset),
            (x1 - inset, y0 + inset),
            (x1 - inset, y1 - curl),
            (x1 - curl, y1 - inset),
            (x0 + inset, y1 - inset),
        ],
        fill=face + (255,),
    )
    # The curl: backing paper, shaded so it reads as folded rather than cut.
    d.polygon(
        [(x1, y1 - curl), (x1 - curl, y1), (x1 - curl * 0.5, y1 - curl * 0.5)],
        fill=(232, 232, 236, 255),
    )
    return img


def stacked(bg, back, mid, front) -> Image.Image:
    """Three offset die-cut stickers — a PACK, which is this app's actual unit.

    A pack is the only route into WhatsApp's tray, so it is arguably the truer
    subject than a single sticker.
    """
    img = _canvas(bg)
    d = ImageDraw.Draw(img)
    step = SAFE * 0.13
    size = SAFE * 0.74

    for i, colour in enumerate([back, mid, front]):
        ox = PAD + step * (2 - i) * 0.7
        oy = PAD + step * i * 0.9
        box = [ox, oy, ox + size, oy + size]
        pts = [
            (box[0], box[1]), (box[2], box[1]), (box[2], box[3]), (box[0], box[3])
        ]
        if i == 2:
            img.alpha_composite(_shadow(pts, blur=20, offset=14))
            d = ImageDraw.Draw(img)
        d.rounded_rectangle(box, radius=int(size * 0.16), fill=WHITE + (255,))
        b = size * 0.08
        d.rounded_rectangle(
            [box[0] + b, box[1] + b, box[2] - b, box[3] - b],
            radius=int(size * 0.12),
            fill=colour + (255,),
        )
    return img


def diecut_face(bg, face) -> Image.Image:
    """Round one's strongest: die-cut circle with a face.

    Kept for comparison. Its weakness is genericness — it identifies the
    category, not this app.
    """
    img = _canvas(bg)
    cx, cy, r = SIZE // 2, SIZE // 2, SAFE // 2
    img.alpha_composite(
        _shadow([(cx - r, cy - r), (cx + r, cy - r), (cx + r, cy + r), (cx - r, cy + r)])
    )
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE + (255,))
    inner = int(r * 0.80)
    d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=face + (255,))

    eye = int(inner * 0.20)
    for dx in (-inner // 2, inner // 2):
        d.ellipse(
            [cx + dx - eye, cy - eye * 2, cx + dx + eye, cy], fill=WHITE + (255,)
        )
    d.arc(
        [cx - inner // 2, cy - inner // 4, cx + inner // 2, cy + inner // 2],
        start=15, end=165, fill=WHITE + (255,), width=int(r * 0.10),
    )
    return img


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)

    candidates = {
        "A_peel_amber": peel_with_backing(bg=(38, 42, 84), face=(255, 200, 64)),
        "B_peel_coral": peel_with_backing(bg=(26, 28, 38), face=(240, 96, 84)),
        "C_stack_indigo": stacked(
            bg=(32, 36, 76),
            back=(120, 132, 220), mid=(255, 140, 105), front=(255, 205, 70),
        ),
        "D_face_teal": diecut_face(bg=(18, 62, 74), face=(74, 200, 190)),
    }

    for name, img in candidates.items():
        img.save(out / f"{name}_1024.png")
        img.resize((48, 48), Image.LANCZOS).save(out / f"{name}_48.png")

    # Contact sheet: full size on top, 48 dp underneath at true scale, because
    # the small row is where an icon actually lives.
    cell = SIZE // 2
    sheet = Image.new("RGBA", (cell * len(candidates), cell + 150), WHITE + (255,))
    for i, img in enumerate(candidates.values()):
        sheet.paste(img.resize((cell, cell), Image.LANCZOS), (i * cell, 0))
        small = img.resize((48, 48), Image.LANCZOS)
        sheet.paste(small, (i * cell + cell // 2 - 24, cell + 20))
        sheet.paste(
            img.resize((96, 96), Image.LANCZOS),
            (i * cell + cell // 2 - 48, cell + 20),
        )
        sheet.paste(small, (i * cell + cell // 2 + 60, cell + 44))
    sheet.save(out / "contact_sheet.png")

    print(f"wrote {len(candidates)} candidates + contact_sheet.png to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
