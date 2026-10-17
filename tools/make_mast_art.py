#!/usr/bin/env python3
"""Draws the sprite of the radio mast (the Radio mast building, round 6) in code: a lattice
steel mast seen straight on, flat colours with a dark outline (until 2026-10-17 it was cut out
of a picture made with an image model; see docs/assets-log.md).

    python3 tools/make_mast_art.py            # writes assets/objects/392_mast.png
    MAST_DEBUG=some/dir python3 tools/make_mast_art.py   # also a preview on a yard colour

It uses the drawing helpers of tools/make_deck_art.py: a tapering truss of two legs with
X bracing, a cross arm near the top with two whip antennas, a small dish, a red beacon, a
concrete footing and a rusty equipment box at the foot. A soft shadow is laid on the ground
to the south east (the light is from the north west), baked in as the other props' are.

The sprite is drawn at 192 pixels to the tile (the deck pieces are too; the plain props
are at 96) because a lattice has thin bars. The size in tiles is MAST_W x MAST_H here and
in assets/data/building_art.json (the mast's foot is at the bottom of the picture, the
shadow runs a little below and to the right of it).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_deck_art as deck  # noqa: E402  (the drawing helpers)

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "objects", "392_mast.png")
PX = 192  # pixels to the tile

# What the mast measures on screen, in tiles: the mast itself (the footing's width and its
# height from the foot to the beacon). The picture carries a margin for the shadow.
MAST_W = 1.3
MAST_H = 3.7
# The shadow: how far it is thrown (tiles, east and south), how dark, how soft.
SHADOW_DX = 0.7
SHADOW_DY = 0.5
SHADOW_ALPHA = 0.34
SHADOW_BLUR = 0.07


def mast_piece():
    w = int(round(MAST_W * PX))
    h = int(round(MAST_H * PX))
    pad = deck.Pad(w, h)
    cx = w / 2.0
    foot, top = h - 22, 46                 # the legs' foot and top
    half_foot, half_top = 64.0, 20.0

    def half(y):
        t = (foot - y) / float(foot - top)
        return half_foot + (half_top - half_foot) * t

    # the footing and the equipment box
    pad.rect(cx - half_foot - 26, foot - 2, cx + half_foot + 26, h - 3, deck.CONCRETE)
    pad.line([(cx - half_foot - 24, foot + 2), (cx + half_foot + 24, foot + 2)], (176, 172, 164), 1.5)
    # the bays of the truss: X braces between level bars
    levels = np.linspace(foot, top + 6, 12)
    for ya, yb in zip(levels[:-1], levels[1:]):
        ha, hb = half(ya), half(yb)
        pad.line([(cx - ha, ya), (cx + hb, yb)], deck.OUTLINE, 5)
        pad.line([(cx + ha, ya), (cx - hb, yb)], deck.OUTLINE, 5)
        pad.line([(cx - ha, ya), (cx + hb, yb)], deck.STEEL, 2.5)
        pad.line([(cx + ha, ya), (cx - hb, yb)], deck.STEEL, 2.5)
    for y in levels:
        pad.plank((cx - half(y), y), (cx + half(y), y), 6, deck.STEEL, deck.STEEL_LIGHT, deck.STEEL_DARK)
    for sgn in (-1, 1):
        pad.plank((cx + sgn * half_foot, foot), (cx + sgn * half_top, top), 10, deck.STEEL, deck.STEEL_LIGHT, deck.STEEL_DARK)
    # rust on the legs
    rng = np.random.RandomState(7)
    for _ in range(14):
        y = rng.uniform(top + 40, foot - 10)
        x = cx + rng.choice([-1, 1]) * half(y) + rng.uniform(-2, 2)
        pad.dr.ellipse([(x - 2) * deck.SS, (y - 3) * deck.SS, (x + 2) * deck.SS, (y + 3) * deck.SS], fill=(132, 74, 44, 255))
    # the cross arm, the whips, the dish and the beacon
    arm = top + 40
    pad.plank((cx - 92, arm), (cx + 92, arm), 7, deck.STEEL, deck.STEEL_LIGHT, deck.STEEL_DARK)
    for x in (cx - 82, cx + 82):
        pad.line([(x, arm), (x, arm - 70)], deck.OUTLINE, 4.5)
        pad.line([(x, arm), (x, arm - 70)], deck.STEEL_LIGHT, 2)
        pad.dot(x, arm - 71, 2.2, deck.STEEL_DARK, 0.8)
    pad.dot(cx + half(top + 90) + 16, top + 90, 14, (196, 200, 204), 2)
    pad.dot(cx + half(top + 90) + 16, top + 90, 4, deck.STEEL_DARK, 1)
    pad.plank((cx + half(top + 90), top + 90), (cx + half(top + 90) + 6, top + 90), 4, deck.STEEL_DARK)
    pad.rect(cx - 4, top - 30, cx + 4, top + 2, deck.STEEL_DARK)
    pad.dot(cx, top - 34, 9, (206, 52, 40), 2)
    pad.dot(cx - 3, top - 37, 2.6, (255, 170, 150), 0.1)
    bx = cx + half_foot - 8
    pad.rect(bx, foot - 58, bx + 54, foot, (122, 104, 82))
    pad.rect(bx + 8, foot - 50, bx + 46, foot - 10, (104, 88, 70), 1.2)
    pad.line([(bx + 4, foot - 20), (bx - 18, foot - 6), (bx - 30, foot + 6)], deck.OUTLINE, 3)
    for _ in range(6):
        x, y = rng.uniform(bx + 4, bx + 50), rng.uniform(foot - 54, foot - 4)
        pad.dr.ellipse([(x - 3) * deck.SS, (y - 2) * deck.SS, (x + 3) * deck.SS, (y + 2) * deck.SS], fill=(140, 78, 46, 255))
    return pad.out()


def with_shadow(mast):
    """The mast on a larger canvas with its shadow under it: a soft patch under the
    footing, and the mast's own shadow laid on the ground and thrown to the south east
    (flattened and sheared away from the foot), faint."""
    w, h = mast.size
    pad_r = int(round(SHADOW_DX * PX)) + 12
    pad_b = int(round(SHADOW_DY * PX)) + 12
    canvas = Image.new("RGBA", (w + pad_r, h + pad_b), (0, 0, 0, 0))
    alpha = np.asarray(mast)[..., 3].astype(np.float32) / 255.0
    foot = h - 1
    # the footing's width: the widest rows in the bottom few
    cols = np.where(alpha[foot - 6:foot].max(axis=0) > 0.3)[0]
    fx0, fx1 = int(cols.min()), int(cols.max())
    sh = np.zeros((h + pad_b, w + pad_r), np.float32)
    flat = SHADOW_DY / MAST_H            # how far down the shadow reaches for each pixel of height
    shear = SHADOW_DX / MAST_H           # and how far to the right
    for y in range(h):
        up = foot - y                    # pixels above the foot
        row = np.where(alpha[y] > 0.3)[0]
        if row.size == 0:
            continue
        ty = foot + int(round(up * flat))
        dx = int(round(up * shear))
        # the mast is open lattice, its shadow is the body: fill between its edges, fading with height
        fade = 1.0 - 0.55 * (up / float(h))
        x0 = int(row.min()) + dx
        x1 = int(row.max()) + dx
        if 0 <= ty < sh.shape[0]:
            sh[ty, max(0, x0):min(sh.shape[1], x1 + 1)] = np.maximum(sh[ty, max(0, x0):min(sh.shape[1], x1 + 1)], fade)
    # a patch under the footing, a little to the right and low
    yy, xx = np.mgrid[0:sh.shape[0], 0:sh.shape[1]]
    cx = (fx0 + fx1) / 2.0 + 0.12 * PX
    cy = foot + 0.05 * PX
    rx = (fx1 - fx0) / 2.0 + 0.10 * PX
    ry = 0.16 * PX
    blob = np.clip(1.0 - (((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2), 0.0, 1.0)
    sh = np.maximum(sh, np.minimum(1.0, blob * 1.6))
    shadow = Image.fromarray((np.clip(sh, 0, 1) * 255.0).round().astype(np.uint8))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR * PX))
    sa = (np.asarray(shadow).astype(np.float32) * SHADOW_ALPHA).round().astype(np.uint8)
    layer = np.zeros((h + pad_b, w + pad_r, 4), np.uint8)
    layer[..., 3] = sa
    layer[..., 0:3] = (10, 8, 10)
    canvas = Image.alpha_composite(canvas, Image.fromarray(layer))
    canvas.alpha_composite(mast, (0, 0))
    return canvas


def main():
    mast = with_shadow(mast_piece())
    mast.save(OUT, optimize=True)
    print("wrote", os.path.relpath(OUT, ROOT), mast.size,
          "(mast %.2f x %.2f tiles, canvas %.2f x %.2f)" % (MAST_W, MAST_H, mast.size[0] / PX, mast.size[1] / PX))
    out = os.environ.get("MAST_DEBUG")
    if out:
        os.makedirs(out, exist_ok=True)
        bg = Image.new("RGBA", (mast.size[0] + 80, mast.size[1] + 80), (84, 84, 88, 255))
        bg.alpha_composite(mast, (40, 40))
        bg.convert("RGB").save(os.path.join(out, "mast_preview.png"))


if __name__ == "__main__":
    main()
