#!/usr/bin/env python3
"""Five more kinds of tree for the town (WORLD3): the ones of assets/trees (tree_0 to tree_12) are all one round crown on one trunk in three colours. This draws tree_13 to tree_17, the same size
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


# 13: dead tree: a forking bare trunk
c = C()
trunk(c, 157, 215, 338, 30, "5e5248")
r = random.Random(13)
def branch(x, y, a, L, w, depth):
    if depth == 0 or L < 14:
        return
    x2, y2 = x + math.cos(a) * L, y + math.sin(a) * L
    c.l([(x, y), (x2, y2)], INK, w + 6)
    c.l([(x, y), (x2, y2)], col("6a5e52"), w)
    for k in range(2):
        branch(x2, y2, a + r.uniform(-0.8, 0.8) + (0.0 if k == 0 else 0.4) * (-1 if k else 1), L * r.uniform(0.62, 0.78), max(3, w * 0.7), depth - 1)
branch(157, 222, -math.pi / 2 - 0.45, 62, 14, 5)
branch(157, 222, -math.pi / 2 + 0.45, 64, 14, 5)
branch(157, 238, -math.pi / 2 + 0.05, 52, 12, 4)
c.l([(157, 330), (130, 346)], INK, 8)
c.l([(157, 330), (186, 346)], INK, 8)
c.done().save(os.path.join(ROOT, "assets/trees/tree_13.png"))

# 14: conifer: layers of dark green points
c = C()
trunk(c, 157, 300, 338, 22, "4e3a2c")
greens = ["2e5a3a", "3a6e46", "4a8454"]
for k, (y0, wd) in enumerate([(240, 118), (190, 98), (140, 78), (92, 56), (50, 34)]):
    pts = [(157 - wd, y0 + 70 - k * 4), (157, y0 - 34), (157 + wd, y0 + 70 - k * 4)]
    c.p(pts, col(greens[0]), 4)
    c.p([(157 - wd * 0.72, y0 + 62 - k * 4), (157 - 4, y0 - 24), (157 - 4, y0 + 62 - k * 4)], col(greens[1]), 0)
    c.p([(157 - wd * 0.45, y0 + 58 - k * 4), (157 - 12, y0 - 6), (157 - 12, y0 + 58 - k * 4)], col(greens[2]), 0)
    c.l([(157 - wd, y0 + 70 - k * 4), (157, y0 - 34), (157 + wd, y0 + 70 - k * 4), (157 - wd, y0 + 70 - k * 4)], INK, 5)
c.done().save(os.path.join(ROOT, "assets/trees/tree_14.png"))

# 15: birch: white trunk with black marks, a light small crown
c = C()
trunk(c, 157, 200, 338, 22, "e4dccc")
for y in range(222, 330, 18):
    c.l([(150, y), (158, y + 3)], INK, 4)
    c.l([(164, y + 8), (168, y + 11)], INK, 3)
blobs(c, 157, 120, 100, 78, 22, ["8ab04a", "b0d070"], 1500, (32, 46))
c.e(60, 40, 254, 200, None, ow=0)
c.done().save(os.path.join(ROOT, "assets/trees/tree_15.png"))

# 16: poplar: a narrow tall crown
c = C()
trunk(c, 157, 280, 338, 20, "5a4030")
blobs(c, 157, 140, 54, 112, 26, ["4a7a3a", "6a9a50"], 1600, (30, 44))
c.done().save(os.path.join(ROOT, "assets/trees/tree_16.png"))

# 17: an apple tree: a broad low crown with red fruit
c = C()
trunk(c, 157, 230, 338, 28, "5a4030")
blobs(c, 157, 150, 126, 80, 24, ["4a8040", "6aa458"], 1700, (38, 54))
r2 = random.Random(1717)
for k in range(16):
    a = r2.uniform(0, 2 * math.pi)
    d = r2.uniform(0.2, 0.95)
    x, y = 157 + math.cos(a) * 118 * d, 150 + math.sin(a) * 70 * d
    c.e(x - 9, y - 9, x + 9, y + 9, col("c8402e"), ow=2)
    c.e(x - 5, y - 6, x - 1, y - 2, col("e8806a"), ow=0)
c.done().save(os.path.join(ROOT, "assets/trees/tree_17.png"))
print("five trees written")
