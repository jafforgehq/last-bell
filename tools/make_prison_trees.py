#!/usr/bin/env python3
"""(prison experiment, same helpers as make_trees_extra.py) Three more: a scrub bush, a dry scrub and a sparse dead pine. Original text: Five more kinds of tree for the town (WORLD3): the ones of assets/trees (tree_0 to tree_12) are all one round crown on one trunk in three colours. This draws tree_13 to tree_17, the same size
(314 x 359) and the same look (a dark brown outline, light from the top left, a trunk with a soft shadow): a bare dead tree, a conifer, a birch, a poplar and an apple tree with fruit.

    python3 tools/make_trees_extra.py        # writes assets/trees/tree_13.png to tree_17.png

`scripts/raid/site_canvas.gd` `_add_tree` gives a share of the town's trees one of these (only for a lot of the town: the raid sites keep the old thirteen).
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 314, 359
SS = 3
INK = (34, 26, 19, 255)


def col(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class C:
    def __init__(self):
        self.im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def e(self, x0, y0, x1, y1, fill, ow=4):
        self.d.ellipse([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=fill + (255,) if fill else None, outline=INK if ow else None, width=ow * SS)

    def p(self, pts, fill, ow=4):
        q = [(x * SS, y * SS) for x, y in pts]
        self.d.polygon(q, fill=fill + (255,))
        if ow:
            self.d.line(q + [q[0]], fill=INK, width=ow * SS, joint="curve")

    def l(self, pts, fill, w):
        self.d.line([(x * SS, y * SS) for x, y in pts], fill=fill + (255,) if len(fill) == 3 else fill, width=int(round(w * SS)), joint="curve")

    def done(self):
        im = self.im.resize((W, H), Image.LANCZOS)
        a = im.split()[3]
        # a soft shadow on the ground under and beside the trunk, to the south east
        sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        base = Image.new("L", (W, H), 0)
        bd = ImageDraw.Draw(base)
        bd.ellipse([96, 300, 250, 352], fill=90)
        sh.putalpha(base.filter(ImageFilter.GaussianBlur(8)))
        out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        out.alpha_composite(sh)
        out.alpha_composite(im)
        return out


def trunk(c, x=157, top=235, bottom=338, w=26, color="5a4030"):
    c.d.rectangle([(x - w / 2) * SS, top * SS, (x + w / 2) * SS, bottom * SS], fill=col(color) + (255,), outline=INK, width=4 * SS)
    c.d.rectangle([(x - w / 2 + 5) * SS, (top + 4) * SS, (x - w / 2 + 11) * SS, (bottom - 6) * SS], fill=(120, 94, 72, 255))


def blobs(c, cx, cy, rx, ry, n, colors, seed, rr=(30, 50)):
    r = random.Random(seed)
    pts = []
    for k in range(n):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(0.0, 1.0) ** 0.6
        pts.append((cx + math.cos(a) * rx * d, cy + math.sin(a) * ry * d, r.randint(*rr)))
    pts.sort(key=lambda t: t[1])
    for x, y, s in pts:
        c.e(x - s - 4, y - s - 4, x + s + 4, y + s + 4, (34, 26, 19), ow=0)
    for x, y, s in pts:
        c.e(x - s, y - s, x + s, y + s, col(colors[0]), ow=0)
    for x, y, s in pts:
        c.e(x - s * 0.7, y - s * 0.7, x + s * 0.5, y + s * 0.5, col(colors[1]), ow=0)
    return pts


def crown_outline(c, cx, cy, rx, ry, n, seed):
    pass



# 18: scrub bush: a low wide mound of leaves
c = C()
blobs(c, 157, 288, 112, 40, 16, ["4d7a3c", "7aa24f"], 1801, (24, 36))
c.done().save(os.path.join(ROOT, "assets/trees/tree_18.png"))

# 19: dry scrub: olive and straw, a few dead twigs
c = C()
blobs(c, 157, 292, 100, 30, 13, ["7a7440", "a6a05a"], 1901, (20, 30))
for dx in (-60, -20, 25, 64):
    c.l([(157 + dx, 300), (157 + dx + dx * 0.2, 238)], INK, 8)
    c.l([(157 + dx, 300), (157 + dx + dx * 0.2, 238)], col("8a7a5a"), 4)
c.done().save(os.path.join(ROOT, "assets/trees/tree_19.png"))

# 20: a ragged half-dead pine: thin trunk, a few drooping brown-green tiers
c = C()
trunk(c, 157, 180, 338, 20, "4e3a2c")
for k, (y0, wd) in enumerate([(280, 70), (230, 58), (180, 46), (130, 32), (86, 20)]):
    c.p([(157 - wd, y0 + 40), (157, y0 - 28), (157 + wd, y0 + 40)], col("4a5a3a" if k % 2 else "6a5a3a"), 4)
c.done().save(os.path.join(ROOT, "assets/trees/tree_20.png"))
