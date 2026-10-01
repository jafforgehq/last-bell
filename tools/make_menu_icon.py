#!/usr/bin/env python3
"""Draws the HUD's menu icon (three bars) the way the older icons in assets/ui/icons are:
a white-on-transparent 64x64 PNG with a 6 unit stroke and round caps on a 64 unit grid,
inside a 3 unit margin (the HUD tints it with `modulate`, so the file carries only alpha).
It is drawn at 8x and averaged down, which gives clean edges.

    python3 tools/make_menu_icon.py            # writes assets/ui/icons/menu.png
then import it once: Godot --headless --path . --import
"""
import os
from PIL import Image, ImageDraw

SIZE = 64
SS = 8
STROKE = 6
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ui", "icons", "menu.png")

# three bars: x from 11 to 53 (round caps reach 8 and 56), 13 units apart
BARS = [(11, 19, 53, 19), (11, 32, 53, 32), (11, 45, 53, 45)]


def line(draw, x0, y0, x1, y1, w):
    """A stroked segment with round caps, on the supersampled grid."""
    r = w * SS / 2.0
    draw.line([(x0 * SS, y0 * SS), (x1 * SS, y1 * SS)], fill=255, width=int(round(w * SS)))
    for x, y in ((x0, y0), (x1, y1)):
        draw.ellipse([x * SS - r, y * SS - r, x * SS + r, y * SS + r], fill=255)


def main():
    mask = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    d = ImageDraw.Draw(mask)
    for bar in BARS:
        line(d, *bar, STROKE)
    alpha = mask.resize((SIZE, SIZE), Image.LANCZOS)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    img.putalpha(alpha)
    img.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
