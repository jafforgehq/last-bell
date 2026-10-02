#!/usr/bin/env python3
"""Builds the sprite of the radio mast (the Radio mast building, round 6) from one
reference picture kept in tools/art_src/: a lattice steel mast seen straight on, made
with Meshy from a text prompt (see docs/assets-log.md).

    python3 tools/make_mast_art.py            # writes assets/objects/392_mast.png
    MAST_DEBUG=some/dir python3 tools/make_mast_art.py   # also a preview on a yard colour

The same method as tools/make_deck_art.py (whose helpers it uses): the flat background is
cut out of the picture (and out of the edges), the steel is cooled and dimmed a touch so
it sits with the yard's props, the picture is squashed the way the game's slightly tilted
view squashes everything that stands up (people show about 0.6 of their height on
screen), and a soft shadow is laid on the ground to the south east (the light is from the
north west), baked in as the other props' are.

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
import make_deck_art as deck  # noqa: E402  (the keying and grading helpers)

ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "tools", "art_src", "ref_mast.png")
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
    keyed = deck.key_background(Image.open(SRC).convert("RGB"))
    box = keyed.getbbox()
    keyed = keyed.crop(box)
    # cooler and a little darker than the picture, so the steel sits with the yard's props
    keyed = deck.grade(keyed, gain=(0.93, 0.95, 0.97), lift=-4.0)
    w = int(round(MAST_W * PX))
    h = int(round(MAST_H * PX))
    return keyed.resize((w, h), Image.LANCZOS)


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
