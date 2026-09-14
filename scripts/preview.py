#!/usr/bin/env python3
"""Render a before/after preview of the map marker colors, with a protanopia
simulation alongside, using the game's real marker artwork.

The background tones are sampled from the four packed TX_RideMap textures
rather than invented, but they're shown as flat swatches -- the point is the
color relationship, and flat swatches avoid spoiling map layouts.

Usage:
    preview.py <marker.png> <out.png>
"""

import argparse
import sys

from PIL import Image, ImageDraw, ImageFont

# Representative tones measured from TX_RideMap-02/03/05/06, spanning the range
# the markers actually have to survive against. Percentages are roughly how much
# of the map area sits near each tone.
BACKGROUNDS = [
    ("#FFEDCB", "paper"),
    ("#D5AD81", "light tan"),
    ("#8F8857", "olive"),
    ("#2C382F", "dark forest"),
]

MARKERS = [
    ("stock red", "#FF3200"),
    ("cyan", "#00FFFF"),
    ("bright blue", "#0B3FD9"),
    ("navy (default)", "#0A1A66"),
]

CELL = 86
PAD = 8
LEFT = 118
HEAD = 26


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    v = 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055
    return int(round(v * 255))


def simulate_protanopia(rgb):
    """Vienot/Brettel-style dichromat simulation, applied in linear RGB."""
    r, g, b = (srgb_to_linear(v) for v in rgb)

    L = 17.8824 * r + 43.5161 * g + 4.11935 * b
    M = 3.45565 * r + 27.1554 * g + 3.86714 * b
    S = 0.0299566 * r + 0.184309 * g + 1.46709 * b

    L = 2.02344 * M - 2.52581 * S  # protanope: the L cone is missing

    return (
        linear_to_srgb(0.080944 * L - 0.130504 * M + 0.116721 * S),
        linear_to_srgb(-0.0102485 * L + 0.0540194 * M - 0.113615 * S),
        linear_to_srgb(-0.000365294 * L - 0.00412163 * M + 0.693513 * S),
    )


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow < 10.1
        return ImageFont.load_default()


def build_grid(marker_art, simulate):
    """Grid of marker colors (rows) against background tones (columns)."""
    w = LEFT + len(BACKGROUNDS) * (CELL + PAD) + PAD
    h = HEAD + len(MARKERS) * (CELL + PAD) + PAD
    img = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    f = font(12)

    for ci, (bg_hex, bg_name) in enumerate(BACKGROUNDS):
        x = LEFT + ci * (CELL + PAD)
        d.text((x, 8), bg_name, fill=(60, 60, 60), font=f)

    for ri, (m_name, m_hex) in enumerate(MARKERS):
        y = HEAD + ri * (CELL + PAD)
        d.text((PAD, y + CELL // 2 - 12), m_name, fill=(20, 20, 20), font=f)
        d.text((PAD, y + CELL // 2 + 2), m_hex, fill=(120, 120, 120), font=f)

        for ci, (bg_hex, _) in enumerate(BACKGROUNDS):
            x = LEFT + ci * (CELL + PAD)
            bg = hex_to_rgb(bg_hex)
            fg = hex_to_rgb(m_hex)
            if simulate:
                bg, fg = simulate_protanopia(bg), simulate_protanopia(fg)

            cell = Image.new("RGBA", (CELL, CELL), bg + (255,))
            art = marker_art.resize((CELL - 12, CELL - 12), Image.LANCZOS)
            tint = Image.new("RGBA", art.size, fg + (255,))
            tint.putalpha(art.getchannel("A"))
            cell.alpha_composite(tint, (6, 6))
            img.alpha_composite(cell, (x, y))

    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("marker")
    ap.add_argument("out")
    args = ap.parse_args()

    art = Image.open(args.marker).convert("RGBA")
    normal = build_grid(art, simulate=False)
    protan = build_grid(art, simulate=True)

    f_title = font(17)
    f_sub = font(12)
    gap = 30
    canvas = Image.new(
        "RGBA", (normal.width * 2 + gap, normal.height + 44), (255, 255, 255, 255)
    )
    d = ImageDraw.Draw(canvas)
    d.text((PAD, 6), "normal vision", fill=(20, 20, 20), font=f_title)
    d.text((normal.width + gap + PAD, 6), "simulated protanopia",
           fill=(20, 20, 20), font=f_title)
    d.text((PAD, 24), "map tones sampled from the game's four RideMap textures",
           fill=(120, 120, 120), font=f_sub)

    canvas.alpha_composite(normal, (0, 44))
    canvas.alpha_composite(protan, (normal.width + gap, 44))
    canvas.convert("RGB").save(args.out)

    print(f"wrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
