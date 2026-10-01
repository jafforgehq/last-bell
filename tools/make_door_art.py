#!/usr/bin/env python3
"""Draws the boarded school doors (the last wall of the colony): four pictures,
from planks nailed across the doorway to the doorway torn open.

    python3 tools/make_door_art.py     # writes assets/objects/391_door_s0..s3.png

The look is the game's own: flat wood with a dark outline, seen from above like
the pallets and the walkways. 96 pixels to the tile, as the other objects.
Both doors (the west one and the east one) use the same four pictures.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "objects")
PX = 96
SS = 4  # draw at four times the size and shrink, for clean edges

W_TILES = 2.5
H_TILES = 1.5
W = int(W_TILES * PX)
H = int(H_TILES * PX)

INK = (42, 28, 18, 255)
WOOD = (176, 128, 80, 255)
WOOD_LIGHT = (203, 158, 104, 255)
WOOD_DARK = (132, 92, 56, 255)
NAIL = (70, 70, 74, 255)
NAIL_LIGHT = (140, 142, 148, 255)
SPLINTER = (226, 196, 150, 255)


def plank(layer, cx, cy, length, thick, angle=0.0, broken=None, rng=None):
    """A plank on the layer (an RGBA image at SS times the scale): centre,
    length, thickness in pixels (1x), angle in degrees. `broken` is an x along
    the plank where it snaps (the two halves are drawn apart)."""
    rng = rng or random.Random(1)
    s = SS
    parts = [(-length / 2.0, length / 2.0)]
    if broken is not None:
        parts = [(-length / 2.0, broken - 2.0), (broken + 2.0, length / 2.0)]
    for k, (a, b) in enumerate(parts):
        piece = Image.new("RGBA", (int((b - a + 8) * s), int((thick + 8) * s)), (0, 0, 0, 0))
        d = ImageDraw.Draw(piece)
        x0, y0 = 4 * s, 4 * s
        x1, y1 = x0 + (b - a) * s, y0 + thick * s
        d.rectangle((x0, y0, x1, y1), fill=INK)
        d.rectangle((x0 + 2 * s, y0 + 2 * s, x1 - 2 * s, y1 - 2 * s), fill=WOOD)
        d.rectangle((x0 + 2 * s, y0 + 2 * s, x1 - 2 * s, y0 + 5 * s), fill=WOOD_LIGHT)
        d.rectangle((x0 + 2 * s, y1 - 5 * s, x1 - 2 * s, y1 - 2 * s), fill=WOOD_DARK)
        # grain
        for g in range(3):
            gy = y0 + (3.5 + g * (thick - 7) / 3.0) * s
            gx0 = x0 + rng.uniform(4, 20) * s
            gx1 = x1 - rng.uniform(4, 20) * s
            d.line((gx0, gy, gx1, gy + rng.uniform(-1, 1) * s), fill=WOOD_DARK, width=max(1, int(0.8 * s)))
        # a snapped end is jagged
        if broken is not None:
            end_x = x1 if k == 0 else x0
            for j in range(5):
                jy = y0 + j * (thick * s) / 4.0
                jx = end_x + (rng.uniform(-3, 3) * s)
                d.polygon([(end_x, jy), (jx, jy + thick * s / 8.0), (end_x, jy + thick * s / 4.0)], fill=SPLINTER if k == 0 else INK)
        # nails
        for nx in ((x0 + 8 * s, x1 - 8 * s) if (b - a) > 40 else (x0 + (x1 - x0) / 2.0,)):
            ny = y0 + thick * s / 2.0
            d.ellipse((nx - 3 * s, ny - 3 * s, nx + 3 * s, ny + 3 * s), fill=INK)
            d.ellipse((nx - 2 * s, ny - 2 * s, nx + 2 * s, ny + 2 * s), fill=NAIL)
            d.ellipse((nx - 1.2 * s, ny - 1.4 * s, nx + 0.2 * s, ny - 0.2 * s), fill=NAIL_LIGHT)
        mid = (a + b) / 2.0
        rot = piece.rotate(-angle, resample=Image.BICUBIC, expand=True)
        # the piece centre sits at (cx + mid*cos, cy + mid*sin)
        px = cx + mid * math.cos(math.radians(angle))
        py = cy + mid * math.sin(math.radians(angle))
        layer.alpha_composite(rot, (int(px * s - rot.size[0] / 2.0), int(py * s - rot.size[1] / 2.0)))


def post(layer, x, y0, y1, w=14, broken_at=None):
    s = SS
    d = ImageDraw.Draw(layer)
    d.rectangle(((x - w / 2) * s, y0 * s, (x + w / 2) * s, (broken_at if broken_at else y1) * s), fill=INK)
    d.rectangle(((x - w / 2 + 2) * s, (y0 + 2) * s, (x + w / 2 - 2) * s, ((broken_at if broken_at else y1) - 2) * s), fill=WOOD_DARK)


def shadow_of(layer, dx=5, dy=6, alpha=95, blur=5):
    s = SS
    a = layer.split()[3].point(lambda v: min(255, int(v * alpha / 255.0)))
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    sh.putalpha(a)
    black = Image.new("RGBA", layer.size, (0, 0, 0, 255))
    black.putalpha(a)
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.alpha_composite(black, (dx * s, dy * s))
    out = out.filter(ImageFilter.GaussianBlur(blur * s / 2.0))
    out.alpha_composite(layer)
    return out


def door(state):
    rng = random.Random(7 + state)
    s = SS
    layer = Image.new("RGBA", (W * s, H * s), (0, 0, 0, 0))
    cx = W / 2.0
    ys = [34, 60, 86, 112]
    length = 216
    if state == 0:
        post(layer, cx - 62, 14, 132)
        post(layer, cx + 62, 14, 132)
        for i, y in enumerate(ys):
            plank(layer, cx + rng.uniform(-3, 3), y + rng.uniform(-1.5, 1.5), length, 22, rng.uniform(-1.2, 1.2), rng=rng)
    elif state == 1:
        post(layer, cx - 62, 14, 132)
        post(layer, cx + 62, 14, 132)
        plank(layer, cx, ys[0], length, 22, -1.0, rng=rng)
        plank(layer, cx + 6, ys[1], length - 10, 22, 2.2, broken=28, rng=rng)
        plank(layer, cx - 4, ys[2], length, 22, 0.6, rng=rng)
        plank(layer, cx + 3, ys[3], length - 6, 22, -2.4, broken=-40, rng=rng)
    elif state == 2:
        post(layer, cx - 62, 14, 132, broken_at=96)
        post(layer, cx + 62, 30, 132)
        plank(layer, cx + 20, ys[0] + 8, 150, 22, 9.0, broken=60, rng=rng)
        plank(layer, cx - 40, ys[2] + 4, 120, 22, -16.0, rng=rng)
        plank(layer, cx + 52, ys[3] + 2, 90, 22, 4.0, rng=rng)
    else:
        # breached: the door is gone, boards lie where they fell
        post(layer, cx - 62, 70, 126, broken_at=98)
        plank(layer, cx - 66, 112, 66, 20, 31.0, rng=rng)
        plank(layer, cx + 56, 104, 90, 20, -24.0, broken=10, rng=rng)
        plank(layer, cx + 4, 124, 58, 18, 6.0, rng=rng)
        plank(layer, cx - 18, 90, 44, 18, -70.0, rng=rng)
    layer = shadow_of(layer, alpha=95 if state < 3 else 70)
    return layer.resize((W, H), Image.LANCZOS)


def main():
    for state in range(4):
        im = door(state)
        name = "391_door_s%d.png" % state
        im.save(os.path.join(OUT, name), optimize=True)
        print("wrote", name, im.size)


if __name__ == "__main__":
    main()
