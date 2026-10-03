#!/usr/bin/env python3
"""Draws the hand tools of the jobs (round 16, task ANIMS): assets/objects/tool_<name>.png and assets/data/tools.json.

A person at work (scripts/render/work_anim.gd) holds one of these: a hammer, a hoe, a plank, a pair of binoculars. Each is a
small picture in the game's own style (a dark outline round every part, flat colours with a light edge on top and a dark one
underneath, the palette of the weapons and the crates in assets/), drawn with Pillow at four times the size and brought down
so the edges are smooth. Deterministic: the same file every run (no random numbers).

The pictures are drawn at DENSITY pixels to the tile (the weapons' own), a hammer 0.6 of a tile long beside a figure about
1.15 tiles from cap to feet. A tool that has a long side points along +x, the way the weapons do ("axis": true: the game turns
it to the angle of the arm and shortens it as it points away); one with no long side (a clipboard, a bottle, a mug, a crate)
stands upright ("axis": false). `grip` is the pixel the hand holds, the point the picture is turned about.

    python3 tools/make_tools.py                    write the pictures and the data file
    python3 tools/make_tools.py --sheet x.png      and a contact sheet of them beside a person (for looking at)

(After new pictures: `Godot --headless --path . --import` makes their .import files.)
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "objects")
DATA_OUT = os.path.join(ROOT, "assets", "data", "tools.json")

DENSITY = 192.0      # pixels to the tile (the weapons' own)
SS = 4               # drawn this many times bigger and brought down
OUT = 3.0            # the outline, in pixels of the finished picture (the figure's own is about this)

INK = (26, 20, 15)
WOOD = (150, 100, 54)
WOOD_L = (190, 138, 80)
WOOD_D = (98, 62, 32)
STEEL = (118, 126, 134)
STEEL_L = (176, 184, 190)
STEEL_D = (66, 72, 80)
DARK = (54, 54, 60)
PAPER = (232, 226, 206)
GLASS = (132, 70, 30)
CRATE = (170, 130, 82)
CRATE_D = (96, 66, 36)


def _mix(c, k):
    """Lighter (k > 0) or darker (k < 0) by that share."""
    if k >= 0:
        return tuple(int(v + (255 - v) * k) for v in c)
    return tuple(int(v * (1.0 + k)) for v in c)


def _disk(r):
    r = int(round(r))
    return [(dx, dy) for dy in range(-r, r + 1) for dx in range(-r, r + 1) if dx * dx + dy * dy <= r * r + r]


def _dilate(mask, r):
    """The mask grown by r pixels (a disk), with plain shifts."""
    out = np.zeros_like(mask)
    h, w = mask.shape
    for dx, dy in _disk(r):
        ys0, ys1 = max(0, dy), min(h, h + dy)
        xs0, xs1 = max(0, dx), min(w, w + dx)
        out[ys0:ys1, xs0:xs1] |= mask[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
    return out


class Canvas:
    """A picture drawn part by part; every part gets its outline, then its colour, then a light top and a dark underside."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))

    # -- a mask for a shape (pixels of the finished picture, scaled up here)
    def _mask(self, fn):
        m = Image.new("L", self.im.size, 0)
        d = ImageDraw.Draw(m)
        fn(d, lambda v: v * SS)
        return np.array(m) > 127

    def _paint(self, mask, col, alpha_mask=None):
        arr = np.array(self.im)
        arr[mask] = (col[0], col[1], col[2], 255)
        self.im = Image.fromarray(arr)

    def part(self, fn, col, shade=0.22, outline=True, light=True):
        """Draws one part: fn(draw, s) draws its shape in white on a mask."""
        mask = self._mask(fn)
        if outline:
            self._paint(_dilate(mask, OUT * SS), INK)
        self._paint(mask, col)
        if shade:
            ys = np.where(mask.any(axis=1))[0]
            y0, y1 = ys[0], ys[-1]
            span = max(1, y1 - y0)
            rows = np.arange(mask.shape[0])[:, None]
            low = mask & (rows > y0 + span * 0.66)
            self._paint(low, _mix(col, -shade))
            if light:
                high = mask & (rows < y0 + max(2 * SS, span * 0.22))
                inner = mask & ~_dilate(~mask, 2 * SS)    # leave the very edge to the shade below it
                self._paint(high & inner, _mix(col, 0.28))

    def rect(self, x0, y0, x1, y1, col, r=2, **kw):
        self.part(lambda d, s: d.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s(r), fill=255), col, **kw)

    def ell(self, x0, y0, x1, y1, col, **kw):
        self.part(lambda d, s: d.ellipse([s(x0), s(y0), s(x1), s(y1)], fill=255), col, **kw)

    def poly(self, pts, col, **kw):
        self.part(lambda d, s: d.polygon([(s(x), s(y)) for x, y in pts], fill=255), col, **kw)

    def line(self, pts, col, width, **kw):
        def fn(d, s):
            d.line([(s(x), s(y)) for x, y in pts], fill=255, width=int(s(width)), joint="curve")
            for x, y in (pts[0], pts[-1]):
                d.ellipse([s(x - width / 2), s(y - width / 2), s(x + width / 2), s(y + width / 2)], fill=255)
        self.part(fn, col, **kw)

    def flat(self, fn, col):
        """A detail drawn on what is already there (no outline, no shading): a line of grain, a nail."""
        mask = self._mask(fn)
        arr = np.array(self.im)
        keep = mask & (arr[:, :, 3] > 0)
        arr[keep] = (col[0], col[1], col[2], 255)
        self.im = Image.fromarray(arr)

    def dash(self, x0, y0, x1, y1, col, width=1.4):
        self.flat(lambda d, s: d.line([(s(x0), s(y0)), (s(x1), s(y1))], fill=255, width=int(s(width))), col)

    def dot(self, x, y, r, col):
        self.flat(lambda d, s: d.ellipse([s(x - r), s(y - r), s(x + r), s(y + r)], fill=255), col)

    def erase(self, fn):
        mask = self._mask(fn)
        arr = np.array(self.im)
        arr[mask] = (0, 0, 0, 0)
        self.im = Image.fromarray(arr)

    def done(self):
        return self.im.resize((self.w, self.h), Image.LANCZOS)


# --------------------------------------------------------------------------------------------------------------- the tools

def hammer():
    c = Canvas(128, 60)
    c.rect(6, 25, 104, 36, WOOD, r=5)
    c.dash(10, 28, 100, 28, WOOD_L)
    c.rect(88, 21, 96, 40, STEEL_D, r=2)                      # the ferrule
    c.rect(92, 7, 122, 53, STEEL, r=5)                        # the head
    c.dash(97, 12, 97, 48, STEEL_L, 3)
    c.dash(116, 11, 116, 49, _mix(STEEL, -0.25), 2)
    return c.done(), (28, 30), True


def mallet():
    c = Canvas(112, 64)
    c.rect(6, 28, 86, 37, WOOD, r=4)
    c.dash(9, 31, 82, 31, WOOD_L)
    c.rect(70, 8, 106, 57, WOOD_L, r=9)                      # the barrel of the head
    c.rect(73, 8, 79, 57, STEEL_D, r=1, outline=False)        # the iron bands
    c.rect(97, 8, 103, 57, STEEL_D, r=1, outline=False)
    c.dash(83, 14, 83, 50, _mix(WOOD_L, 0.25), 3)
    return c.done(), (24, 32), True


def hoe():
    c = Canvas(224, 100)
    c.rect(6, 34, 182, 43, WOOD, r=4)
    c.dash(10, 37, 178, 37, WOOD_L)
    c.poly([(170, 30), (190, 30), (204, 58), (186, 62)], STEEL_D)             # the neck
    c.poly([(180, 56), (214, 54), (218, 88), (178, 90)], STEEL)               # the blade
    c.dash(184, 60, 182, 85, STEEL_L, 3)
    return c.done(), (62, 38), True


def can():
    c = Canvas(104, 80)
    c.line([(18, 30), (18, 10), (44, 10), (50, 28)], STEEL_D, 6, shade=0)         # the handle
    c.line([(60, 62), (96, 30)], STEEL, 8, shade=0.15)                             # the spout
    c.ell(88, 16, 104, 40, STEEL_L, shade=0.15)                                   # the rose
    c.rect(14, 24, 64, 70, (112, 142, 138), r=7)                                  # the body
    c.dash(18, 34, 60, 34, STEEL_L, 2)
    c.dash(18, 58, 60, 58, _mix((112, 142, 138), -0.3), 2)
    return c.done(), (32, 10), True


def clipboard():
    c = Canvas(56, 74)
    c.rect(4, 6, 52, 70, WOOD, r=4)
    c.rect(9, 16, 47, 64, PAPER, r=2, shade=0.1, outline=False)
    for i, y in enumerate((24, 31, 38, 45, 52)):
        c.dash(13, y, 43 - (i % 2) * 8, y, (150, 146, 134), 1.6)
    c.rect(17, 2, 39, 15, STEEL, r=3)
    c.dot(28, 8, 2.2, STEEL_D)
    return c.done(), (28, 56), False


def bottle():
    c = Canvas(32, 62)
    c.rect(11, 8, 21, 26, GLASS, r=3)
    c.rect(5, 22, 27, 58, GLASS, r=7)
    c.rect(10, 2, 22, 11, (196, 156, 104), r=2, shade=0.2)
    c.rect(8, 33, 24, 48, PAPER, r=1, shade=0.1, outline=False)
    c.dash(11, 38, 21, 38, (150, 60, 50), 2)
    c.dash(11, 43, 19, 43, (150, 146, 134), 1.6)
    c.dash(8, 28, 8, 54, _mix(GLASS, 0.35), 2)
    return c.done(), (16, 40), False


def mug():
    c = Canvas(40, 36)
    c.line([(26, 12), (34, 14), (34, 22), (26, 24)], (216, 208, 184), 4, shade=0)  # the handle
    c.rect(4, 6, 28, 32, (222, 214, 190), r=4)
    c.dash(5, 14, 27, 14, (74, 104, 140), 3)
    return c.done(), (16, 20), False


def mic():
    c = Canvas(52, 30)
    c.rect(3, 10, 32, 21, DARK, r=4)
    c.dash(7, 13, 28, 13, (112, 112, 120), 2)
    c.ell(28, 3, 49, 26, (150, 156, 160), shade=0.25)
    c.dot(38, 14, 6, (96, 100, 106))
    return c.done(), (14, 15), True


def plank():
    c = Canvas(180, 32)
    c.rect(4, 4, 176, 28, (176, 132, 76), r=3)
    for x0, x1, y in ((14, 70, 12), (40, 120, 20), (96, 168, 14), (20, 60, 23)):
        c.dash(x0, y, x1, y, (126, 90, 48), 1.6)
    c.dot(12, 16, 2.2, STEEL_D)
    c.dot(168, 16, 2.2, STEEL_D)
    return c.done(), (44, 16), True


def saw():
    c = Canvas(160, 60)
    base = lambda x: 40 + 6.0 * (x - 40) / 112.0                    # the lower edge of the blade
    teeth = [(40, base(40))]
    for i in range(16):
        x = 40 + i * 7
        teeth += [(x + 3.5, base(x + 3.5) + 7), (x + 7, base(x + 7))]
    c.poly(teeth + [(152, base(152) - 1), (40, base(40) - 1)], STEEL_D, shade=0)       # the teeth
    c.poly([(40, 18), (152, 24), (152, base(152)), (40, base(40))], STEEL_L, shade=0.12)    # the blade
    c.dash(46, 26, 148, 31, STEEL_D, 1.6)
    c.rect(4, 12, 46, 50, WOOD, r=11)
    c.erase(lambda d, s: d.ellipse([s(14), s(21), s(34), s(41)], fill=255))
    c.dash(8, 18, 40, 16, WOOD_L, 2)
    return c.done(), (24, 30), True


def crate():
    c = Canvas(84, 84)
    c.rect(4, 4, 80, 80, CRATE_D, r=3)
    c.rect(11, 11, 73, 73, CRATE, r=1, outline=False, shade=0.12)
    for y in (26, 42, 58):
        c.dash(11, y, 73, y, CRATE_D, 1.6)
    c.dash(14, 14, 70, 70, CRATE_D, 6)
    c.dash(14, 14, 70, 70, _mix(CRATE, 0.12), 2.6)
    return c.done(), (42, 42), False


def binoculars():
    c = Canvas(76, 40)
    c.rect(8, 21, 68, 35, _mix((62, 78, 62), -0.2), r=5, shade=0.1)               # the far barrel
    c.rect(4, 9, 66, 25, (62, 78, 62), r=5)
    c.rect(62, 5, 74, 29, DARK, r=4)                                               # the front lens ring
    c.rect(2, 11, 12, 23, DARK, r=3)                                               # the eyepiece
    c.dash(14, 13, 60, 13, (120, 140, 116), 2)
    return c.done(), (10, 17), True


def binoculars_front():
    c = Canvas(68, 44)
    c.rect(28, 17, 40, 29, DARK, r=2)
    for x in (2, 36):
        c.ell(x, 4, x + 30, 38, (62, 78, 62), shade=0.1)
        c.ell(x + 5, 9, x + 25, 33, (64, 100, 124), shade=0, light=False)
        c.dot(x + 11, 16, 3.5, (210, 232, 244))
    return c.done(), (34, 22), False


def headset():
    """Seen from the front, worn over the cap: the band over the top, a cup on each ear and a boom to the mouth. The grip is
    the middle of the line of the ears."""
    c = Canvas(156, 120)
    import math
    band = [(78 + 66 * math.cos(math.radians(a)), 74 + 62 * math.sin(math.radians(a))) for a in range(190, 351, 10)]
    c.line(band, STEEL_D, 8, shade=0.2)
    for x0 in (6, 118):
        c.rect(x0, 54, x0 + 32, 98, DARK, r=11)
        c.dash(x0 + 7, 62, x0 + 7, 90, (112, 112, 120), 3)
    c.dot(22, 76, 4.5, (190, 60, 50))                  # a lamp on the near cup
    c.line([(134, 96), (126, 112), (104, 114)], DARK, 4, shade=0)
    c.ell(94, 106, 108, 120, (150, 156, 160), shade=0.2)
    return c.done(), (78, 74), False


TOOLS = {
    "hammer": hammer, "mallet": mallet, "hoe": hoe, "can": can, "clipboard": clipboard, "bottle": bottle, "mug": mug,
    "mic": mic, "plank": plank, "saw": saw, "crate": crate, "binoculars": binoculars,
    "binoculars_front": binoculars_front, "headset": headset,
}


def build():
    """{name: (image, grip, axis)} of every tool."""
    return {name: fn() for name, fn in TOOLS.items()}


def write():
    data = {"density": DENSITY, "tools": {}}
    for name, (im, grip, axis) in build().items():
        im.save(os.path.join(OUT_DIR, "tool_%s.png" % name))
        data["tools"][name] = {"file": "res://assets/objects/tool_%s.png" % name, "w": im.width, "h": im.height,
                               "grip": list(grip), "axis": axis}
    with open(DATA_OUT, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    return data


def sheet(path):
    """The tools in a row beside a person, at the size the game draws them (the person's 160 pixels to the tile)."""
    pawn = Image.open(os.path.join(ROOT, "assets", "pawns", "dez_S.png")).convert("RGBA")
    k = 160.0 / DENSITY
    tools = build()
    pad = 24
    row_h = 150
    cols = 7
    rows = (len(tools) + cols - 1) // cols
    big = Image.new("RGBA", (pawn.width + cols * 190 + pad, max(pawn.height, rows * row_h) + pad), (112, 110, 104, 255))
    big.alpha_composite(pawn, (10, 10))
    for i, (name, (im, grip, axis)) in enumerate(tools.items()):
        t = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
        x = pawn.width + 30 + (i % cols) * 190
        y = 20 + (i // cols) * row_h
        big.alpha_composite(t, (x, y))
    big.save(path)


if __name__ == "__main__":
    if "--sheet" in sys.argv:
        sheet(sys.argv[sys.argv.index("--sheet") + 1])
    else:
        write()
        print("wrote %d tools" % len(TOOLS))
