"""Generates the Sticker Studio launcher icon.

The design — three die-cut cards, fanned — came out of three rounds of rendered
comparison rather than description. It depicts a **pack**, which is this app's
actual unit and the only route into WhatsApp's tray, and it is the shape that
still carried meaning at 48 dp when a peeling corner and a die-cut face did not.

**No WhatsApp visual borrowing**: this is a standalone third-party app, so no
#25D366, no phone-in-speech-bubble, no WA mark. That is a trademark position.

Outputs three files, because Android needs two different things:
  - `icon.png`             full-bleed, for the legacy square icon
  - `icon_foreground.png`  cards only on transparency, for the adaptive icon
  - the background colour is a flat value set in pubspec

The adaptive foreground is drawn well inside the safe zone: a launcher may mask
it to a circle, and only the centre ~66% is guaranteed to survive.

Usage:
    python3 tool/make_app_icon.py assets/icon
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
WHITE = (255, 255, 255)

BACKGROUND = (26, 28, 40)  # near-black, so the cards carry the colour
CARDS = [
    (120, 132, 224),  # indigo, furthest back
    (244, 118, 96),   # coral
    (255, 200, 72),   # amber, front
]


def _card(size: int, fill: tuple[int, int, int]) -> Image.Image:
    """One die-cut sticker: a generous white rim around a coloured face.

    The rim is what reads as "sticker" rather than "card" — a hairline would
    vanish at 48 dp, so it stays thick.
    """
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    border = max(6, int(size * 0.075))
    r = int(size * 0.20)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=WHITE + (255,))
    d.rounded_rectangle(
        [border, border, size - 1 - border, size - 1 - border],
        radius=int(r * 0.72),
        fill=fill + (255,),
    )
    return card


def render(*, safe_fraction: float, background: tuple[int, int, int] | None):
    """Draws the fan. [background] None gives the transparent adaptive layer."""
    img = Image.new(
        "RGBA", (SIZE, SIZE),
        (background + (255,)) if background else (0, 0, 0, 0),
    )
    safe = int(SIZE * safe_fraction)
    pad = (SIZE - safe) // 2
    size = int(safe * 0.80)
    step = int(safe * 0.11)

    for i, colour in enumerate(CARDS):
        card = _card(size, colour).rotate(
            (i - (len(CARDS) - 1) / 2) * -9, resample=Image.BICUBIC, expand=True
        )
        ox = pad + (len(CARDS) - 1 - i) * step - (card.width - size) // 2
        oy = pad + i * step - (card.height - size) // 2

        # Only the front card casts a shadow; one per card turns to mud.
        if i == len(CARDS) - 1:
            shade = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            shade.paste(card, (ox, oy + 14), card)
            alpha = shade.filter(ImageFilter.GaussianBlur(18)).split()[3]
            faded = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            faded.paste((0, 0, 0, 90), (0, 0), alpha)
            img.alpha_composite(faded)

        layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        layer.paste(card, (ox, oy), card)
        img.alpha_composite(layer)

    return img


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/icon")
    out.mkdir(parents=True, exist_ok=True)

    render(safe_fraction=0.66, background=BACKGROUND).save(out / "icon.png")
    # Smaller safe fraction for the adaptive layer: a launcher can crop hard to a
    # circle, and the corners of the fan are the first thing it takes. 0.62 was
    # picked by rendering the circular mask (see the preview in tool/) — at 0.56
    # the stack floated in a moat of background, and anything above 0.62 started
    # losing the indigo card's outer corner to the crop.
    render(safe_fraction=0.62, background=None).save(out / "icon_foreground.png")

    print(
        f"wrote icon.png and icon_foreground.png to {out}\n"
        f"background: #{BACKGROUND[0]:02X}{BACKGROUND[1]:02X}{BACKGROUND[2]:02X}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
