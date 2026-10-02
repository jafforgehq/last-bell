#!/usr/bin/env python3
"""Draws the HUD's Build icon (a claw hammer, tilted, over a plank) the way the older icons in
assets/ui/icons are: a white-on-transparent 64x64 PNG on a 64 unit grid, inside a 3 unit margin (the HUD
tints it with `modulate`, so the file carries only alpha). It is drawn at 8x and averaged down, which gives
clean edges. (The mallet of the Repair order is another picture: this one has a claw and a plank under it,
so that the two are told apart even in the small size, where only icons show.)

    python3 tools/make_build_icon.py            # writes assets/ui/icons/build.png
then import it once: Godot --headless --path . --import
"""
import os
from PIL import Image, ImageChops, ImageDraw

SIZE = 64
SS = 8
MARGIN = 3
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ui", "icons", "build.png")
# how far the hammer is turned (degrees, clockwise) and the room it has: above the plank, inside the margin
TILT = -40
HAMMER_BOX = (MARGIN, MARGIN, SIZE - MARGIN, 51.5)
PLANK = (6.5, 55.2, 57.5, 60.7)


def s(v):
    """A grid unit on the supersampled canvas."""
    return v * SS


def pts(points):
    return [(s(x), s(y)) for x, y in points]


def hammer():
    """The claw hammer, upright (the head at the top, the claw to the left), on a 64 unit canvas."""
    layer = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    d = ImageDraw.Draw(layer)
    # the handle: a solid rounded bar
    d.rounded_rectangle([s(28), s(16), s(36), s(62)], radius=s(3.6), fill=255)
    # the head: a block, its flat face to the right ...
    d.rounded_rectangle([s(30), s(5), s(56), s(23)], radius=s(3), fill=255)
    # ... and the claw to the left: a prong that tapers and curves down
    d.polygon(pts([(33, 5), (20, 5.5), (9, 10), (3, 19), (11, 16.5), (20, 17.5), (33, 23)]), fill=255)
    return layer.rotate(TILT, resample=Image.BICUBIC, center=(s(32), s(32)))


def fit(layer, box):
    """`layer` scaled down (never up) and moved so that what is drawn in it lies inside `box` (grid units),
    as far to the right as it likes: centred in the box."""
    bbox = layer.getbbox()
    x0, y0, x1, y1 = [v / SS for v in bbox]
    w, h = x1 - x0, y1 - y0
    bw, bh = box[2] - box[0], box[3] - box[1]
    k = min(1.0, bw / w, bh / h)
    art = layer.crop(bbox)
    art = art.resize((max(1, round(art.size[0] * k)), max(1, round(art.size[1] * k))), Image.LANCZOS)
    out = Image.new("L", layer.size, 0)
    cx = (box[0] + box[2]) / 2.0 - art.size[0] / SS / 2.0
    cy = (box[1] + box[3]) / 2.0 - art.size[1] / SS / 2.0
    out.paste(art, (round(s(cx)), round(s(cy))))
    return out


def main():
    mask = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([s(PLANK[0]), s(PLANK[1]), s(PLANK[2]), s(PLANK[3])], radius=s(2.7), fill=255)
    mask = ImageChops.lighter(mask, fit(hammer(), HAMMER_BOX))
    alpha = mask.resize((SIZE, SIZE), Image.BOX)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    img.putalpha(alpha)
    img.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
