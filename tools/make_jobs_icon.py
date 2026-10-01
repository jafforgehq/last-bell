#!/usr/bin/env python3
"""Draws the HUD's Jobs icon (a clipboard with a duty roster on it) the way the older icons in
assets/ui/icons are: a white-on-transparent 64x64 PNG on a 64 unit grid, inside a 3 unit margin
(the HUD tints it with `modulate`, so the file carries only alpha). It is drawn at 8x and
averaged down, which gives clean edges.

    python3 tools/make_jobs_icon.py            # writes assets/ui/icons/jobs.png
then import it once: Godot --headless --path . --import
"""
import os
from PIL import Image, ImageDraw

SIZE = 64
SS = 8
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ui", "icons", "jobs.png")


def s(v):
    """A grid unit on the supersampled canvas."""
    return v * SS


def line(draw, x0, y0, x1, y1, w):
    """A stroked segment with round caps."""
    r = w * SS / 2.0
    draw.line([(s(x0), s(y0)), (s(x1), s(y1))], fill=255, width=int(round(w * SS)))
    for x, y in ((x0, y0), (x1, y1)):
        draw.ellipse([s(x) - r, s(y) - r, s(x) + r, s(y) + r], fill=255)


def main():
    mask = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    d = ImageDraw.Draw(mask)
    # the board: a rounded box, outlined (its top edge is hidden behind the clip)
    d.rounded_rectangle([s(11.5), s(9.5), s(52.5), s(60.5)], radius=s(6), outline=255, width=int(s(5)))
    # the clip: a solid tab across the top edge, with a gap round it so that it reads as a clip
    d.rounded_rectangle([s(19), s(5.5), s(45), s(17)], radius=s(4), fill=0)
    d.rounded_rectangle([s(22), s(3.5), s(42), s(14.5)], radius=s(3.5), fill=255)
    # the roster: three ruled lines, the last one short
    line(d, 21, 28, 43, 28, 4)
    line(d, 21, 38, 43, 38, 4)
    line(d, 21, 48, 34, 48, 4)
    alpha = mask.resize((SIZE, SIZE), Image.LANCZOS)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    img.putalpha(alpha)
    img.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
