#!/usr/bin/env python3
"""Draws the radio card's icon (a little transistor radio) the way the older icons in
assets/ui/icons are: a white-on-transparent 64x64 PNG on a 64 unit grid, inside a 3 unit margin
(the HUD tints it with `modulate`, so the file carries only alpha). It is drawn at 8x and
averaged down, which gives clean edges.

    python3 tools/make_radio_icon.py            # writes assets/ui/icons/radio.png
then import it once: Godot --headless --path . --import
"""
import os
from PIL import Image, ImageDraw

SIZE = 64
SS = 8
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ui", "icons", "radio.png")


def s(v):
    """A grid unit on the supersampled canvas."""
    return v * SS


def line(draw, x0, y0, x1, y1, w):
    """A stroked segment with round caps."""
    r = w * SS / 2.0
    draw.line([(s(x0), s(y0)), (s(x1), s(y1))], fill=255, width=int(round(w * SS)))
    for x, y in ((x0, y0), (x1, y1)):
        draw.ellipse([s(x) - r, s(y) - r, s(x) + r, s(y) + r], fill=255)


def ring(draw, cx, cy, radius, w):
    """A circle drawn as an outline of width `w`."""
    outer = s(radius + w / 2.0)
    inner = s(radius - w / 2.0)
    draw.ellipse([s(cx) - outer, s(cy) - outer, s(cx) + outer, s(cy) + outer], fill=255)
    draw.ellipse([s(cx) - inner, s(cy) - inner, s(cx) + inner, s(cy) + inner], fill=0)


def disc(draw, cx, cy, radius):
    r = s(radius)
    draw.ellipse([s(cx) - r, s(cy) - r, s(cx) + r, s(cy) + r], fill=255)


def main():
    mask = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    d = ImageDraw.Draw(mask)
    # the body: a rounded box, outlined
    d.rounded_rectangle([s(6.5), s(23.5), s(57.5), s(56.5)], radius=s(7), outline=255, width=int(s(5)))
    # the aerial, with a ball on its tip
    line(d, 41, 23, 52, 8, 4)
    disc(d, 52, 8, 3.2)
    # the speaker: three short bars
    for y in (33, 40, 47):
        line(d, 15, y, 30, y, 3.6)
    # the dial
    ring(d, 44.5, 40, 6.2, 3.8)
    disc(d, 44.5, 40, 1.6)
    alpha = mask.resize((SIZE, SIZE), Image.LANCZOS)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    img.putalpha(alpha)
    img.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
