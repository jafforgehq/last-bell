#!/usr/bin/env python3
"""Tidies the parked cars' pictures (2026-10-17, "everything should look much better").

    python3 tools/tidy_car_art.py            # rewrites the car pictures in place, then run tools/make_car_doors.py
    python3 tools/tidy_car_art.py --sheet OUT.png   # writes nothing: a before and after sheet of every picture

The car pictures (assets/objects/167_car_s*, 174_car_s*, 203 to 215) came with long thin dark strokes (aerials and
wipers drawn far past the body) that read as scratches across the street. This takes them out and keeps the rest:

  - past the body: an opening of the alpha (5 px) drops every stroke thinner than that, the soft shadow stays;
  - on the body, away from its outline: where a closing of the colour (5 px) is much lighter than the picture, the
    pixel was a thin dark stroke and takes the closing's colour. Glass cracks (light strokes) and rust (blobs) stay.

The buses (166, 175) are left alone: their thin dark lines are the mirror arms and the roof vents' rims. After a run,
`python3 tools/make_car_doors.py` cuts the doors again from the tidied sedan and pickup.
"""
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PATTERNS = ["assets/objects/167_car_s[0-3].png", "assets/objects/174_car_s[0-3].png", "assets/objects/2[01][0-9]_car.png",
            "assets/objects/207_pickup.png"]


def files():
    out = []
    for p in PATTERNS:
        out += sorted(glob.glob(os.path.join(ROOT, p)))
    return out


def tidy(im):
    im = im.convert("RGBA")
    a = im.getchannel("A")
    a_open = a.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
    rgb = im.convert("RGB")
    closed = rgb.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    A = np.array(a).astype(int)
    AO = np.array(a_open).astype(int)
    R = np.array(rgb).astype(int)
    C = np.array(closed).astype(int)
    solid = A > 200
    core = np.array(Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(13))) > 0
    stroke = (C.sum(2) - R.sum(2) > 90) & core
    R[stroke] = C[stroke]
    A2 = np.where(solid, A, np.minimum(A, AO))
    return Image.fromarray(np.dstack([R, A2]).astype(np.uint8))


def sheet(out):
    W = 1800
    x = y = rowh = 0
    S = Image.new("RGBA", (W, 6000), (70, 72, 75, 255))
    d = ImageDraw.Draw(S)
    for f in files():
        for k, i in enumerate([Image.open(f).convert("RGBA"), tidy(Image.open(f))]):
            i = i.resize((i.width // 2, i.height // 2))
            if x + i.width > W:
                x = 0
                y += rowh + 16
                rowh = 0
            S.alpha_composite(i, (x, y + 14))
            d.text((x + 2, y), ("after " if k else "") + os.path.basename(f), fill=(255, 255, 255, 255))
            x += i.width + 10
            rowh = max(rowh, i.height + 14)
    S.crop((0, 0, W, y + rowh + 20)).convert("RGB").save(out)


if __name__ == "__main__":
    if "--sheet" in sys.argv:
        sheet(sys.argv[sys.argv.index("--sheet") + 1])
    else:
        for f in files():
            tidy(Image.open(f)).save(f)
            print("tidied", os.path.relpath(f, ROOT))
