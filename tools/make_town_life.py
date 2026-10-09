#!/usr/bin/env python3
"""Draws the LIFE of the town (WORLD3, "add more life to the world"): the street and yard props, the signs of the fall and the extra furniture of the rooms, all in ONE sheet.

    python3 tools/make_town_life.py     # writes assets/town/life/life_sheet.png, assets/data/town_art_life.json and merges the sizes of the new items into assets/data/prop_sizes.json

Seen from above, lit from the top left (a soft shadow falls to the south east), a dark brown outline (#221a13), muted colours: the look of the art kit (tools/make_town_art.py). 128 px to the tile; a
picture is its footprint plus 8 px at the top and left and 24 at the bottom and right (the anchor is 0.0625 tile: the same as the kit's). Deterministic (the same script writes the same files).
The manifest it writes, assets/data/town_art_life.json, has the schema of assets/data/town_art.json; scripts/town/town_art.gd reads it after the kit's and adds its items (an item that is in the kit
already, like `car_wreck`, gets its `append_sprites`).

What it makes: street (cones, a fallen barrier, debris, a tyre, potholes, cracks, puddles, signs, a post box, newspaper boxes, flyers, graffiti, shopping carts, suitcases, backpacks, bin bags, bodies,
blood, a tent, a camp fire, a lean-to tarp, pallets, a note on a door, flowers, rubble, a pram, burnt cars), yard (washing lines, a trampoline, a barbecue, gnomes, toys, a sandpit, a paddling pool, flower
beds, a vegetable patch, weeds, a wood pile, a rain barrel, a wheelbarrow, a bird bath, deck chairs, a picnic table, a kennel, a doormat, plant pots, a compost heap, a gas pump) and the room's
furniture (shop shelves, a check-out, a display case, a cooler, a tool chest, a toy chest, a vanity, a piano, a fireplace, an aquarium, a cot, bunk beds, a shower, a washing machine, a square table, a
barber's chair, a cafe table, a bar stool, a big plant, a rocking chair, a stack of tyres, a jerry can, a mannequin).
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PNG = os.path.join(ROOT, "assets/town/life/life_sheet.png")
OUT_JSON = os.path.join(ROOT, "assets/data/town_art_life.json")
SIZES_JSON = os.path.join(ROOT, "assets/data/prop_sizes.json")
T = 128
OFF = 8
EXTRA = 24
INK = (34, 26, 19, 255)
SS = 2
R = random.Random(2468)


def col(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3])


class Spr:
    """A picture of a thing of fw x fh tiles: coordinates are in px of the footprint (0 to fw * 128); a supersampled canvas."""

    def __init__(self, fw, fh):
        self.fw, self.fh = fw, fh
        self.W = fw * T + OFF + EXTRA
        self.H = fh * T + OFF + EXTRA
        self.im = Image.new("RGBA", (self.W * SS, self.H * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def p(self, x, y):
        return ((x + OFF) * SS, (y + OFF) * SS)

    @staticmethod
    def _f(fill):
        if fill is None:
            return None
        if len(fill) == 4:
            return None if fill[3] == 0 else fill
        return tuple(fill) + (255,)

    def rect(self, x0, y0, x1, y1, fill, ow=3, r=0, outline=INK):
        a = self.p(x0, y0)
        b = self.p(x1, y1)
        box = [a[0], a[1], b[0], b[1]]
        if r > 0:
            self.d.rounded_rectangle(box, radius=r * SS, fill=self._f(fill), outline=outline if ow else None, width=ow * SS)
        else:
            self.d.rectangle(box, fill=self._f(fill), outline=outline if ow else None, width=ow * SS)

    def ellipse(self, x0, y0, x1, y1, fill, ow=3, outline=INK):
        a = self.p(x0, y0)
        b = self.p(x1, y1)
        self.d.ellipse([a[0], a[1], b[0], b[1]], fill=self._f(fill), outline=outline if ow else None, width=ow * SS)

    def line(self, pts, fill, w=2):
        self.d.line([self.p(x, y) for x, y in pts], fill=self._f(fill), width=w * SS, joint="curve")

    def poly(self, pts, fill, ow=3, outline=INK):
        q = [self.p(x, y) for x, y in pts]
        self.d.polygon(q, fill=self._f(fill))
        if outline and ow:
            self.d.line(q + [q[0]], fill=outline, width=ow * SS, joint="curve")

    def bevel(self, x0, y0, x1, y1, base, ow=3, r=0):
        self.rect(x0, y0, x1, y1, base, ow=ow, r=r)
        self.line([(x0 + ow + 1, y0 + ow + 1), (x1 - ow - 1, y0 + ow + 1)], shade(base, 1.25), 2)
        self.line([(x0 + ow + 1, y0 + ow + 1), (x0 + ow + 1, y1 - ow - 1)], shade(base, 1.2), 2)
        self.line([(x0 + ow + 1, y1 - ow - 1), (x1 - ow - 1, y1 - ow - 1)], shade(base, 0.72), 2)
        self.line([(x1 - ow - 1, y0 + ow + 1), (x1 - ow - 1, y1 - ow - 1)], shade(base, 0.76), 2)

    def done(self, shadow=True, alpha=0.5, off=(5, 8), blur=3):
        """The picture at 64 px to the tile (it is drawn at 128 and reduced: the sheet is a quarter of the size)."""
        im = self.im.resize((self.W, self.H), Image.LANCZOS)
        if shadow:
            a = im.split()[3]
            sh = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
            sh.putalpha(a.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * alpha * 0.55)))
            out = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
            out.paste(sh, off, sh)
            out.alpha_composite(im)
            im = out
        return im.resize((self.W // 2, self.H // 2), Image.LANCZOS)


ITEMS = {}  # id -> {"fp": (w, h), "layer": 1|2|4, "solid": bool, "container": str, "sprites": [(variant, facing, orient, image)], "note": str, "states": ...}


def item(iid, fw, fh, layer, solid=False, container="", note="", cat="street"):
    ITEMS[iid] = {"fp": (fw, fh), "layer": layer, "solid": solid, "container": container, "sprites": [], "note": note, "cat": cat}
    return ITEMS[iid]


def sprite(iid, im, variant=0, facing="", orient="", state=""):
    ITEMS[iid]["sprites"].append({"v": variant, "facing": facing, "orient": orient, "state": state, "im": im})


def faced(iid, base, variant=0, square=False):
    """The facings of a wall-backed thing: `base` is drawn facing south (its back to the north wall); north is the picture turned over; a square thing also has west and east."""
    sprite(iid, base, variant, "s")
    sprite(iid, base.transpose(Image.FLIP_TOP_BOTTOM), variant, "n")
    if square:
        sprite(iid, base.rotate(-90, expand=True), variant, "w")
        sprite(iid, base.rotate(90, expand=True), variant, "e")


# =============================================================================== street ==
item("cone", 1, 1, 2, note="A traffic cone (a: standing, b: knocked over).")
s = Spr(1, 1)
s.rect(30, 30, 98, 98, (60, 60, 58), ow=3, r=4)
s.ellipse(38, 38, 90, 90, col("d8742c"), ow=3)
s.ellipse(48, 48, 80, 80, col("ece4d4"), ow=2)
s.ellipse(56, 56, 72, 72, col("c8601f"), ow=2)
sprite("cone", s.done(alpha=0.5), 0)
s = Spr(1, 1)
s.poly([(30, 90), (98, 70), (90, 40), (34, 56)], col("d8742c"))
s.line([(60, 82), (62, 50)], col("ece4d4"), 8)
s.rect(26, 78, 60, 100, (60, 60, 58), ow=3, r=3)
sprite("cone", s.done(), 1)

item("barrier_fallen", 2, 1, 2, note="A striped road barrier lying on its side.")
s = Spr(2, 1)
s.rect(14, 38, 242, 86, col("e0d8c6"), ow=4, r=4)
for k in range(8):
    x = 22 + k * 28
    s.poly([(x, 40), (x + 14, 40), (x + 2, 84), (x - 12, 84)], col("d4702a"), ow=0)
s.rect(14, 38, 242, 86, (0, 0, 0, 0), ow=4, r=4)
s.rect(44, 86, 56, 112, col("5a5a58"), ow=3)
s.rect(196, 86, 208, 112, col("5a5a58"), ow=3)
sprite("barrier_fallen", s.done(), 0)

item("debris", 1, 1, 1, note="Bits of the fall on the road: bricks, boards, a bag (a, b, c).")
for v in range(3):
    s = Spr(1, 1)
    r = random.Random(100 + v)
    for k in range(5 + v):
        x, y = r.randint(20, 100), r.randint(20, 100)
        if v == 0:
            s.rect(x, y, x + r.randint(14, 26), y + r.randint(10, 16), col(r.choice(["a8624a", "98543e", "b8725a"])), ow=2)
        elif v == 1:
            a = r.uniform(0, math.pi)
            L = r.randint(30, 56)
            s.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], col("9a7a52"), 8)
            s.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], (34, 26, 19, 120), 2)
        else:
            s.ellipse(x, y, x + r.randint(14, 24), y + r.randint(12, 20), col(r.choice(["5a5c60", "70706a", "4a4a46"])), ow=2)
    sprite("debris", s.done(shadow=True, alpha=0.4), v)

item("tire", 1, 1, 2, note="A tyre on the road.")
s = Spr(1, 1)
s.ellipse(30, 30, 98, 98, col("3a3836"), ow=3)
s.ellipse(48, 48, 80, 80, col("8a8880"), ow=3)
s.ellipse(56, 56, 72, 72, col("2c2a28"), ow=2)
sprite("tire", s.done(), 0)

item("pothole", 1, 1, 1, note="A pothole in the road (a, b).")
for v in range(2):
    s = Spr(1, 1)
    r = random.Random(200 + v)
    pts = []
    for k in range(10):
        a = k / 10 * 2 * math.pi
        rr = r.randint(30, 44)
        pts.append((64 + math.cos(a) * rr, 64 + math.sin(a) * rr * 0.8))
    s.poly(pts, col("46464a"), ow=3, outline=(30, 28, 26, 255))
    s.poly([(64 + (x - 64) * 0.7, 64 + (y - 64) * 0.7 + 3) for x, y in pts], col("2a2a2e"), ow=0)
    sprite("pothole", s.done(shadow=False), v)

item("pave_crack", 2, 1, 1, note="A crack running across the paving (a, b).")
for v in range(2):
    s = Spr(2, 1)
    r = random.Random(300 + v)
    x, y = 10, 64
    pts = [(x, y)]
    while x < 240:
        x += r.randint(14, 30)
        y += r.randint(-14, 14)
        y = max(24, min(104, y))
        pts.append((x, y))
    s.line(pts, (30, 28, 26, 230), 4)
    for k in range(2):
        b = r.choice(pts[1:-1])
        s.line([b, (b[0] + r.randint(10, 30), b[1] + r.randint(-30, 30))], (30, 28, 26, 190), 3)
    sprite("pave_crack", s.done(shadow=False), v)

item("puddle", 2, 1, 1, note="A puddle (a, b, c): blue-grey with a pale glint.")
for v in range(3):
    s = Spr(2, 1)
    r = random.Random(400 + v)
    pts = []
    for k in range(14):
        a = k / 14 * 2 * math.pi
        pts.append((128 + math.cos(a) * r.randint(62, 100) * (1.0 if v < 2 else 0.8), 64 + math.sin(a) * r.randint(26, 44)))
    s.poly(pts, (86, 108, 128, 175), ow=2, outline=(40, 52, 66, 200))
    s.poly([(128 + (x - 128) * 0.6, 64 + (y - 64) * 0.6) for x, y in pts], (120, 146, 168, 150), ow=0)
    s.line([(86, 52), (120, 46)], (220, 236, 244, 220), 3)
    sprite("puddle", s.done(shadow=False), v)

item("stop_sign", 1, 1, 2, note="A stop sign on a post, seen from above: the plate and the post's shadow.")
s = Spr(1, 1)
s.ellipse(54, 54, 74, 74, col("707068"), ow=2)
pts = [(64 + math.cos(k / 8 * 2 * math.pi + math.pi / 8) * 36, 64 + math.sin(k / 8 * 2 * math.pi + math.pi / 8) * 36) for k in range(8)]
s.poly(pts, col("b8403a"), ow=4)
s.poly([(64 + (x - 64) * 0.78, 64 + (y - 64) * 0.78) for x, y in pts], (0, 0, 0, 0), ow=2, outline=(232, 228, 216, 255))
sprite("stop_sign", s.done(), 0)

item("bus_sign", 1, 1, 2, note="A bus stop sign: a blue disc on a post.")
s = Spr(1, 1)
s.ellipse(28, 28, 100, 100, col("4a6a98"), ow=4)
s.ellipse(36, 36, 92, 92, (0, 0, 0, 0), ow=2, outline=(232, 228, 216, 255))
s.rect(46, 52, 82, 76, col("e8e2d2"), ow=2, r=4)
s.ellipse(52, 72, 60, 80, (40, 40, 40), ow=1)
s.ellipse(68, 72, 76, 80, (40, 40, 40), ow=1)
sprite("bus_sign", s.done(), 0)

item("parking_meter", 1, 1, 2, note="A parking meter.")
s = Spr(1, 1)
s.ellipse(40, 40, 88, 88, col("808884"), ow=3)
s.ellipse(52, 50, 76, 72, col("c4d4c8"), ow=2)
sprite("parking_meter", s.done(), 0)

item("postbox", 1, 1, 2, note="A blue post box on the pavement.")
s = Spr(1, 1)
s.bevel(26, 26, 102, 102, col("4a68a0"), ow=3, r=14)
s.rect(40, 50, 88, 62, (20, 24, 40), ow=2, r=3)
sprite("postbox", s.done(), 0)

item("news_box", 1, 1, 2, note="A newspaper box (a red, b blue, c yellow).")
for v, c in enumerate(["b04a42", "48648c", "c8a03c"]):
    s = Spr(1, 1)
    s.bevel(28, 28, 100, 100, col(c), ow=3, r=6)
    s.rect(40, 40, 88, 66, col("d4e0e8"), ow=2, r=2)
    s.rect(46, 78, 82, 86, shade(col(c), 0.6), ow=2)
    sprite("news_box", s.done(), v)

item("flyers", 1, 1, 1, note="Flyers and posters torn down and trodden: pale sheets with a scrawl (a, b, c).")
for v in range(3):
    s = Spr(1, 1)
    r = random.Random(500 + v)
    for k in range(3):
        x, y = r.randint(16, 70), r.randint(16, 70)
        a = r.uniform(-0.5, 0.5)
        cx, cy = x + 26, y + 32
        pts = [(cx + (dx * math.cos(a) - dy * math.sin(a)), cy + (dx * math.sin(a) + dy * math.cos(a))) for dx, dy in [(-24, -30), (24, -30), (24, 30), (-24, 30)]]
        s.poly(pts, col(r.choice(["e8e4d4", "dcd4b8", "e4d8d0"])), ow=2)
        for q in range(3):
            s.line([(cx - 16, cy - 16 + q * 14), (cx + 12, cy - 16 + q * 14)], (60, 50, 44, 200), 2)
    sprite("flyers", s.done(shadow=True, alpha=0.3), v)

item("graffiti", 2, 1, 1, note="Spray paint on the paving (a: a tag, b: a cross, c: a face, d: HELP).")
for v in range(4):
    s = Spr(2, 1)
    c = col(["b84438", "3c68a8", "c8a838", "5a9a58"][v])
    cc = c + (230,)
    if v == 0:
        s.line([(30, 90), (60, 30), (90, 90), (120, 40), (150, 88), (190, 36), (226, 84)], cc, 9)
        s.line([(40, 100), (216, 100)], cc, 5)
    elif v == 1:
        s.line([(60, 20), (196, 108)], cc, 12)
        s.line([(196, 20), (60, 108)], cc, 12)
        s.ellipse(100, 28, 156, 100, (0, 0, 0, 0), ow=0, outline=None)
    elif v == 2:
        s.ellipse(80, 14, 176, 114, (0, 0, 0, 0), ow=0, outline=None)
        s.line([(100, 64), (128, 90), (156, 64)], cc, 8)
        s.ellipse(100, 36, 114, 50, c, ow=0, outline=None)
        s.ellipse(142, 36, 156, 50, c, ow=0, outline=None)
        s.line([(80, 64), (86, 30), (128, 12), (170, 30), (176, 64), (170, 98), (128, 116), (86, 98), (80, 64)], cc, 7)
    else:
        for i, ch in enumerate("HELP"):
            x = 34 + i * 50
            if ch == "H":
                s.line([(x, 28), (x, 100)], cc, 9)
                s.line([(x + 30, 28), (x + 30, 100)], cc, 9)
                s.line([(x, 64), (x + 30, 64)], cc, 8)
            elif ch == "E":
                s.line([(x + 28, 30), (x, 30), (x, 98), (x + 28, 98)], cc, 9)
                s.line([(x, 64), (x + 22, 64)], cc, 8)
            elif ch == "L":
                s.line([(x, 28), (x, 98), (x + 28, 98)], cc, 9)
            else:
                s.line([(x, 100), (x, 28), (x + 28, 28), (x + 28, 62), (x, 62)], cc, 9)
    sprite("graffiti", s.done(shadow=False), v)

item("cart", 1, 1, 2, note="A shopping trolley, upright.")
s = Spr(1, 1)
s.rect(22, 34, 98, 96, (0, 0, 0, 0), ow=4, r=3)
for k in range(1, 5):
    s.line([(22 + k * 15, 36), (22 + k * 15, 94)], (150, 154, 156, 255), 3)
for k in range(1, 4):
    s.line([(24, 34 + k * 15), (96, 34 + k * 15)], (150, 154, 156, 255), 3)
s.rect(22, 34, 98, 96, (0, 0, 0, 0), ow=3, r=3, outline=col("8c9096"))
s.line([(98, 40), (116, 30)], col("8c9096"), 6)
sprite("cart", s.done(), 0)
item("cart_fallen", 2, 1, 2, note="A shopping trolley on its side (a, b).")
for v in range(2):
    s = Spr(2, 1)
    s.rect(30, 30, 200, 94, (0, 0, 0, 0), ow=4, r=3, outline=col("8c9096"))
    for k in range(1, 7):
        s.line([(30 + k * 24, 32), (30 + k * 24, 92)], (150, 154, 156, 255), 3)
    for k in range(1, 3):
        s.line([(32, 30 + k * 21), (198, 30 + k * 21)], (150, 154, 156, 255), 3)
    s.line([(200, 36), (236, 20 + v * 70)], col("8c9096"), 6)
    s.ellipse(46, 92, 64, 110, col("2c2a28"), ow=2)
    s.ellipse(168, 92, 186, 110, col("2c2a28"), ow=2)
    sprite("cart_fallen", s.done(), v)

item("suitcase", 1, 1, 2, note="A suitcase left in the road (a: brown, b: green, c: red).")
for v, c in enumerate(["8a5e3a", "4a6e58", "a04a42"]):
    s = Spr(1, 1)
    s.bevel(26, 30, 102, 98, col(c), ow=3, r=8)
    s.line([(64, 34), (64, 94)], shade(col(c), 0.7), 3)
    s.rect(52, 20, 76, 32, (0, 0, 0, 0), ow=3, r=4)
    s.rect(34, 60, 44, 70, col("d4c070"), ow=2)
    s.rect(84, 60, 94, 70, col("d4c070"), ow=2)
    sprite("suitcase", s.done(), v)
item("backpack", 1, 1, 2, note="A dropped rucksack (a: blue, b: olive).")
for v, c in enumerate(["3e5a84", "5c6a3e"]):
    s = Spr(1, 1)
    s.bevel(34, 30, 94, 100, col(c), ow=3, r=14)
    s.rect(44, 62, 84, 88, shade(col(c), 0.8), ow=2, r=6)
    s.line([(40, 34), (30, 54)], (60, 50, 40, 255), 5)
    s.line([(88, 34), (98, 54)], (60, 50, 40, 255), 5)
    sprite("backpack", s.done(), v)
item("bin_bag", 1, 1, 2, note="A black bin bag, split (a, b).")
for v in range(2):
    s = Spr(1, 1)
    s.poly([(34, 70), (40, 40), (64, 28), (92, 40), (98, 74), (80, 96), (50, 96)], col("2a2a2e"), ow=3)
    s.line([(54, 34), (74, 30)], (90, 90, 96, 255), 3)
    if v == 1:
        s.line([(90, 90), (118, 100)], col("5a5a52"), 5)
        s.ellipse(106, 92, 122, 108, col("c8c0a4"), ow=2)
    sprite("bin_bag", s.done(), v)

item("body", 2, 1, 1, note="One of the fallen (a to d: different clothes and poses). Dark blood round it.")
CLOTHES = [("5a6a8c", "3c3a48"), ("8a4a42", "4a4238"), ("5a7a5a", "3a3a44"), ("a09060", "50463a")]
for v in range(4):
    s = Spr(2, 1)
    r = random.Random(600 + v)
    s.ellipse(40, 12, 230, 120, (92, 22, 22, 150), ow=0, outline=None)
    s.ellipse(70, 26, 200, 106, (110, 28, 26, 170), ow=0, outline=None)
    top, bot = CLOTHES[v]
    flip = v % 2
    def X(x):
        return 256 - x if flip else x
    # legs, torso, arms, head (a figure lying on its back or its side)
    s.line([(X(150), 58), (X(220), 44 + r.randint(-8, 8))], col(bot), 22)
    s.line([(X(150), 72), (X(214), 88 + r.randint(-8, 8))], col(bot), 22)
    s.line([(X(90), 64), (X(156), 64)], col(top), 40)
    s.line([(X(100), 46), (X(70), 24 + r.randint(0, 20))], col(top), 14)
    s.line([(X(100), 84), (X(66), 100 - r.randint(0, 16))], col(top), 14)
    s.ellipse(X(80) - 22, 64 - 22, X(80) + 22, 64 + 22, col("c49a7c"), ow=3)
    s.ellipse(X(74) - 14, 64 - 16, X(74) + 12, 64 + 12, col("5a4030" if v % 3 else "c8a850"), ow=0, outline=None)
    sprite("body", s.done(shadow=True, alpha=0.4), v)
s = Spr(2, 1)
s.ellipse(20, 8, 236, 122, (96, 24, 22, 120), ow=0, outline=None)
s.poly([(40, 44), (110, 30), (220, 44), (222, 86), (110, 98), (40, 84)], col("dcd8cc"), ow=3)
s.line([(70, 40), (96, 60), (150, 54), (190, 70)], (180, 176, 164, 255), 3)
s.ellipse(90, 50, 116, 76, (120, 36, 30, 160), ow=0, outline=None)
sprite("body", s.done(alpha=0.4), 4)

item("blood_smear", 2, 1, 1, note="A smear of blood dragged along the ground (a, b, c).")
for v in range(3):
    s = Spr(2, 1)
    r = random.Random(700 + v)
    for k in range(4):
        y = 30 + k * 18 + r.randint(-6, 6)
        s.line([(20 + r.randint(0, 20), y), (236 - r.randint(0, 40), y + r.randint(-14, 14))], (96, 22, 22, 190 - k * 20), 12 - k * 2)
    s.ellipse(r.randint(10, 40), 40, r.randint(70, 100), 90, (100, 24, 24, 170), ow=0, outline=None)
    sprite("blood_smear", s.done(shadow=False), v)
item("blood_pool", 1, 1, 1, note="A pool of blood (a, b).")
for v in range(2):
    s = Spr(1, 1)
    r = random.Random(750 + v)
    pts = [(64 + math.cos(k / 12 * 2 * math.pi) * r.randint(28, 46), 64 + math.sin(k / 12 * 2 * math.pi) * r.randint(24, 42)) for k in range(12)]
    s.poly(pts, (104, 24, 24, 200), ow=0, outline=None)
    s.poly([(64 + (x - 64) * 0.55, 64 + (y - 64) * 0.55) for x, y in pts], (126, 32, 30, 190), ow=0, outline=None)
    for k in range(5):
        x, y = r.randint(10, 118), r.randint(10, 118)
        s.ellipse(x, y, x + r.randint(5, 10), y + r.randint(5, 10), (104, 24, 24, 200), ow=0, outline=None)
    sprite("blood_pool", s.done(shadow=False), v)
item("blood_prints", 2, 1, 1, note="Bloody footprints going away.")
s = Spr(2, 1)
for k in range(6):
    x = 24 + k * 38
    y = 40 + (k % 2) * 36
    s.ellipse(x, y, x + 22, y + 34, (100, 24, 24, 190), ow=0, outline=None)
    s.ellipse(x + 2, y - 8, x + 18, y + 4, (100, 24, 24, 190), ow=0, outline=None)
sprite("blood_prints", s.done(shadow=False), 0)

item("camp_tent", 3, 2, 2, note="A makeshift tent (a: olive, b: orange, c: blue). Walkable: it is only a picture.")
for v, c in enumerate(["6a7a4a", "c4782e", "4a6a96"]):
    s = Spr(3, 2)
    base = col(c)
    s.poly([(40, 220), (60, 40), (330, 40), (350, 220)], shade(base, 0.85), ow=4)
    s.poly([(60, 40), (192, 70), (192, 222), (40, 220)], base, ow=0)
    s.poly([(192, 70), (330, 40), (350, 220), (192, 222)], shade(base, 0.7), ow=0)
    s.line([(60, 40), (192, 70), (330, 40)], INK, 4)
    s.line([(192, 70), (192, 222)], INK, 4)
    s.poly([(40, 220), (60, 40), (330, 40), (350, 220)], (0, 0, 0, 0), ow=4)
    s.poly([(120, 222), (192, 110), (264, 222)], (30, 26, 22), ow=3)
    s.line([(60, 40), (20, 12)], (60, 50, 40, 255), 3)
    s.line([(330, 40), (370, 12)], (60, 50, 40, 255), 3)
    s.line([(40, 220), (14, 244)], (60, 50, 40, 255), 3)
    s.line([(350, 220), (376, 244)], (60, 50, 40, 255), 3)
    sprite("camp_tent", s.done(), v)
item("campfire", 1, 1, 1, note="The ashes of a camp fire in a ring of stones (a, b).")
for v in range(2):
    s = Spr(1, 1)
    r = random.Random(800 + v)
    s.ellipse(22, 22, 106, 106, (34, 30, 28), ow=0, outline=None)
    for k in range(10):
        a = k / 10 * 2 * math.pi
        x, y = 64 + math.cos(a) * 40, 64 + math.sin(a) * 40
        s.ellipse(x - 12, y - 11, x + 12, y + 11, col(r.choice(["8a8a84", "76766e", "9a9a90"])), ow=3)
    s.line([(44, 70), (84, 52)], (30, 20, 14, 255), 9)
    s.line([(46, 52), (82, 74)], (40, 28, 18, 255), 8)
    if v == 1:
        s.ellipse(54, 54, 74, 74, (200, 90, 40, 160), ow=0, outline=None)
    sprite("campfire", s.done(), v)
item("camp_chair", 1, 1, 2, note="A folding chair.")
s = Spr(1, 1)
s.rect(30, 30, 98, 98, col("5a6a8a"), ow=3, r=4)
s.rect(30, 30, 98, 52, shade(col("5a6a8a"), 0.7), ow=3, r=4)
sprite("camp_chair", s.done(), 0)
item("tarp_lean", 2, 2, 2, note="A tarpaulin stretched from a wall to two poles: a lean-to (a blue, b green).")
for v, c in enumerate(["4a76a0", "5a7a4a"]):
    s = Spr(2, 2)
    base = col(c)
    s.poly([(20, 24), (236, 24), (252, 230), (4, 230)], base, ow=4)
    s.poly([(20, 24), (236, 24), (230, 90), (26, 90)], shade(base, 1.15), ow=0)
    s.line([(20, 24), (236, 24)], INK, 5)
    s.line([(128, 24), (128, 230)], shade(base, 0.7), 3)
    for gx, gy in [(14, 226), (242, 226), (128, 228)]:
        s.ellipse(gx - 6, gy - 6, gx + 6, gy + 6, (190, 186, 170), ow=2)
    s.line([(4, 230), (-2, 252)], (150, 130, 90, 255), 3)
    s.line([(252, 230), (258, 252)], (150, 130, 90, 255), 3)
    sprite("tarp_lean", s.done(), v)
item("pallet", 2, 1, 2, note="Wooden pallets (a, b).")
for v in range(2):
    s = Spr(2, 1)
    for k in range(5):
        y = 14 + k * 22
        s.rect(10, y, 246, y + 14, col(["a07c52", "8c6a44"][(k + v) % 2]), ow=2)
    for x in (10, 120, 232):
        s.rect(x, 10, x + 14, 118, col("7a5a38"), ow=2)
    sprite("pallet", s.done(), v)
item("note", 1, 1, 1, note="A note nailed to a door or left on the step (a, b, c).")
for v in range(3):
    s = Spr(1, 1)
    r = random.Random(900 + v)
    a = r.uniform(-0.3, 0.3)
    cx, cy = 64, 64
    pts = [(cx + (dx * math.cos(a) - dy * math.sin(a)), cy + (dx * math.sin(a) + dy * math.cos(a))) for dx, dy in [(-26, -34), (26, -34), (26, 34), (-26, 34)]]
    s.poly(pts, col("eee8d4"), ow=3)
    for q in range(5):
        s.line([(cx - 18, cy - 24 + q * 11), (cx + 12 - r.randint(0, 14), cy - 24 + q * 11)], (70, 56, 48, 220), 2)
    if v == 1:
        s.line([(cx - 20, cy - 28), (cx + 20, cy + 28)], (170, 40, 36, 255), 4)
        s.line([(cx + 20, cy - 28), (cx - 20, cy + 28)], (170, 40, 36, 255), 4)
    s.rect(cx - 6, cy - 40, cx + 6, cy - 30, (200, 190, 150, 220), ow=1)
    sprite("note", s.done(shadow=True, alpha=0.4), v)
item("flowers", 1, 1, 1, note="Flowers and a burnt-down candle left for somebody.")
s = Spr(1, 1)
for k in range(7):
    a = k / 7 * 2 * math.pi
    x, y = 64 + math.cos(a) * 24, 64 + math.sin(a) * 24
    s.ellipse(x - 12, y - 12, x + 12, y + 12, col(["c86a7a", "e0c050", "d8d4d0", "9a6ab0"][k % 4]), ow=2)
s.rect(56, 40, 72, 72, col("e8e0cc"), ow=2, r=2)
s.ellipse(58, 34, 70, 46, col("e8a030"), ow=1)
sprite("flowers", s.done(alpha=0.4), 0)
item("rubble", 1, 1, 1, note="Rubble: broken brick and plaster (a, b, c).")
for v in range(3):
    s = Spr(1, 1)
    r = random.Random(1000 + v)
    for k in range(9):
        x, y = r.randint(14, 100), r.randint(14, 100)
        w, h = r.randint(12, 30), r.randint(10, 24)
        s.poly([(x, y), (x + w, y + r.randint(-4, 6)), (x + w - 4, y + h), (x - 2, y + h - 3)], col(r.choice(["8a8278", "a09a8e", "7a5a4a", "94887a"])), ow=2)
    sprite("rubble", s.done(alpha=0.4), v)
item("pram", 1, 1, 2, note="A pram left behind.")
s = Spr(1, 1)
s.rect(34, 22, 94, 82, col("5a6a8a"), ow=3, r=10)
s.ellipse(40, 28, 88, 66, col("d8d4c4"), ow=2)
s.rect(36, 82, 92, 100, (0, 0, 0, 0), ow=0)
for x in (30, 88):
    s.ellipse(x, 86, x + 14, 110, col("2c2a28"), ow=2)
s.line([(48, 82), (80, 82)], col("8c9096"), 4)
sprite("pram", s.done(), 0)

# burnt cars: more looks for the kit's wreck (it has two); added by `append_sprites`
WRECKS = []
for v in range(2):
    W, H = 554, 394
    s = Spr(4, 3)
    base = col(["3a3836", "4a3a34"][v])
    s.poly([(40, 90), (80, 40), (400, 36), (468, 92), (476, 236), (60, 244)], base, ow=5)
    s.poly([(120, 66), (240, 54), (262, 120), (112, 126)], (22, 20, 20), ow=4)
    s.poly([(300, 56), (400, 54), (432, 112), (298, 120)], (22, 20, 20), ow=4)
    s.poly([(110, 150), (380, 146), (400, 220), (96, 224)], shade(base, 1.2), ow=3)
    for sx, sy in [(110, 40), (420, 80), (90, 240), (440, 230)]:
        s.ellipse(sx - 22, sy - 12, sx + 22, sy + 22, (20, 18, 18), ow=3)
    for k in range(8):
        x, y = R.randint(70, 440), R.randint(60, 230)
        s.ellipse(x, y, x + R.randint(12, 36), y + R.randint(8, 22), (130 + R.randint(0, 40), 70 + R.randint(0, 30), 30), ow=0, outline=None)
    WRECKS.append(s.done())

# =============================================================================== yard ==
item("laundry", 3, 1, 4, note="A washing line between two poles, with washing on it (a, b).", cat="outdoors")
for v in range(2):
    s = Spr(3, 1)
    r = random.Random(1100 + v)
    s.ellipse(8, 50, 28, 74, col("6a5a46"), ow=3)
    s.ellipse(356, 50, 376, 74, col("6a5a46"), ow=3)
    s.line([(18, 62), (366, 62)], (40, 34, 28, 255), 3)
    x = 40
    while x < 330:
        w = r.randint(30, 56)
        c = col(r.choice(["d8d4c8", "7a9ac0", "c87a6a", "9ac07a", "d8c07a", "a88ac0"]))
        s.rect(x, 52, x + w, 52 + r.randint(40, 62), c, ow=2, r=3)
        x += w + r.randint(8, 22)
    sprite("laundry", s.done(alpha=0.45, off=(6, 14)), v, orient="h")

item("trampoline", 2, 2, 2, note="A trampoline: a mat in a ring of springs, a net.", cat="outdoors")
s = Spr(2, 2)
s.ellipse(14, 14, 242, 242, col("2c3a58"), ow=4)
s.ellipse(30, 30, 226, 226, col("1c1c20"), ow=3)
for k in range(24):
    a = k / 24 * 2 * math.pi
    s.line([(128 + math.cos(a) * 92, 128 + math.sin(a) * 92), (128 + math.cos(a) * 104, 128 + math.sin(a) * 104)], (150, 154, 156, 255), 3)
s.ellipse(90, 90, 166, 166, (0, 0, 0, 0), ow=2, outline=(70, 70, 76, 255))
sprite("trampoline", s.done(), 0)
item("bbq", 1, 1, 2, note="A barbecue grill (a: black, b: red).", cat="outdoors")
for v, c in enumerate(["2c2a2a", "a0443a"]):
    s = Spr(1, 1)
    s.ellipse(24, 24, 104, 104, col(c), ow=4)
    s.ellipse(34, 34, 94, 94, shade(col(c), 1.3), ow=2)
    for k in range(5):
        s.line([(40 + k * 12, 38), (40 + k * 12, 90)], (70, 70, 74, 255), 2)
    s.rect(96, 56, 118, 70, col("7a5a38"), ow=2, r=2)
    sprite("bbq", s.done(), v)
item("gnome", 1, 1, 2, note="A garden gnome (a, b).", cat="outdoors")
for v in range(2):
    s = Spr(1, 1)
    s.ellipse(40, 40, 88, 88, col(["4a6aa0", "5a8a5a"][v]), ow=3)
    s.ellipse(50, 48, 78, 74, col("d8b090"), ow=2)
    s.poly([(64, 20), (82, 54), (46, 54)], col("c04a3a"), ow=3)
    sprite("gnome", s.done(alpha=0.35), v)
item("toys", 1, 1, 1, note="Toys left in the grass (a: a ball, b: a truck, c: a doll).", cat="outdoors")
s = Spr(1, 1)
s.ellipse(40, 40, 88, 88, col("c8503c"), ow=3)
s.line([(48, 64), (80, 64)], col("e8e0cc"), 6)
sprite("toys", s.done(alpha=0.35), 0)
s = Spr(1, 1)
s.rect(28, 50, 100, 82, col("d8a830"), ow=3, r=5)
s.rect(76, 44, 100, 66, col("3c5a8c"), ow=3, r=3)
s.ellipse(34, 78, 54, 96, (30, 28, 26), ow=2)
s.ellipse(74, 78, 94, 96, (30, 28, 26), ow=2)
sprite("toys", s.done(alpha=0.35), 1)
s = Spr(1, 1)
s.ellipse(48, 24, 80, 52, col("d8b090"), ow=2)
s.rect(46, 50, 82, 100, col("c87a9a"), ow=3, r=6)
s.line([(46, 62), (24, 80)], col("d8b090"), 8)
s.line([(82, 62), (104, 80)], col("d8b090"), 8)
sprite("toys", s.done(alpha=0.35), 2)
item("sandpit", 2, 2, 1, note="A child's sandpit with a bucket.", cat="outdoors")
s = Spr(2, 2)
s.rect(20, 20, 236, 236, col("8a6a44"), ow=4, r=6)
s.rect(34, 34, 222, 222, col("d4c08a"), ow=3, r=4)
s.ellipse(150, 120, 190, 160, col("c8503c"), ow=3)
s.line([(60, 70), (100, 90), (80, 130)], (170, 150, 100, 255), 4)
sprite("sandpit", s.done(alpha=0.4), 0)
item("paddling_pool", 2, 2, 1, note="A paddling pool (a blue, b green).", cat="outdoors")
for v, c in enumerate(["5a8ac0", "5aa088"]):
    s = Spr(2, 2)
    s.ellipse(14, 14, 242, 242, col(["d8c048", "c8503c"][v]), ow=4)
    s.ellipse(40, 40, 216, 216, col(c), ow=3)
    s.ellipse(70, 66, 130, 112, shade(col(c), 1.3), ow=0, outline=None)
    sprite("paddling_pool", s.done(alpha=0.4), v)
item("flower_bed", 2, 1, 1, note="A bed of flowers (a red, b yellow, c purple).", cat="outdoors")
for v, c in enumerate(["c8504a", "e0c040", "9a6ab8"]):
    s = Spr(2, 1)
    r = random.Random(1200 + v)
    s.rect(12, 20, 244, 108, col("5a3e2a"), ow=3, r=6)
    for k in range(22):
        x, y = r.randint(24, 232), r.randint(32, 98)
        s.ellipse(x - 8, y - 8, x + 8, y + 8, col("4a7a44"), ow=1)
        s.ellipse(x - 5, y - 5, x + 5, y + 5, col(c), ow=1)
    sprite("flower_bed", s.done(alpha=0.4), v)
item("veg_patch", 3, 2, 1, note="Rows of vegetables (a green, b gone to seed).", cat="outdoors")
for v in range(2):
    s = Spr(3, 2)
    r = random.Random(1300 + v)
    s.rect(12, 12, 372, 244, col("5a3e2a"), ow=3, r=6)
    for row in range(4):
        y = 40 + row * 54
        for k in range(9):
            x = 36 + k * 38
            c = ["4a8a44", "5a9a50", "6a9a48"][r.randint(0, 2)] if v == 0 else ["8a8a44", "9a8a50", "7a6a44"][r.randint(0, 2)]
            s.ellipse(x - 14, y - 14, x + 14, y + 14, col(c), ow=2)
    sprite("veg_patch", s.done(alpha=0.4), v)
item("weeds", 1, 1, 1, note="Weeds and tall grass gone wild (a, b, c).", cat="outdoors")
for v in range(3):
    s = Spr(1, 1)
    r = random.Random(1400 + v)
    for k in range(12 + v * 3):
        x, y = r.randint(24, 104), r.randint(40, 108)
        a = r.uniform(-0.6, 0.6)
        L = r.randint(26, 52)
        s.line([(x, y), (x + math.sin(a) * L, y - math.cos(a) * L)], col(r.choice(["5a7a3a", "6a8a44", "8a8a4a", "4a6a34"])) + (230,), 4)
    sprite("weeds", s.done(shadow=False), v)
item("woodpile", 2, 1, 2, note="A stack of firewood.", cat="outdoors")
s = Spr(2, 1)
for row in range(3):
    for k in range(10):
        s.ellipse(14 + k * 22, 14 + row * 30, 36 + k * 22, 40 + row * 30, col(["8a6a44", "9a7a50", "7a5a38"][(k + row) % 3]), ow=2)
sprite("woodpile", s.done(), 0)
item("rain_barrel", 1, 1, 2, note="A rain barrel.", cat="outdoors")
s = Spr(1, 1)
s.ellipse(24, 24, 104, 104, col("6a5a46"), ow=4)
s.ellipse(34, 34, 94, 94, col("4a6a8a"), ow=3)
s.ellipse(44, 42, 70, 62, col("8aa8c0"), ow=0, outline=None)
sprite("rain_barrel", s.done(), 0)
item("barrow", 1, 1, 2, note="A wheelbarrow.", cat="outdoors")
s = Spr(1, 1)
s.poly([(30, 30), (98, 30), (86, 96), (42, 96)], col("4a7a9a"), ow=3)
s.line([(42, 96), (34, 118)], (90, 70, 46, 255), 5)
s.line([(86, 96), (94, 118)], (90, 70, 46, 255), 5)
sprite("barrow", s.done(), 0)
item("birdbath", 1, 1, 2, note="A bird bath.", cat="outdoors")
s = Spr(1, 1)
s.ellipse(22, 22, 106, 106, col("a8a8a0"), ow=4)
s.ellipse(34, 34, 94, 94, col("7a9ab0"), ow=3)
sprite("birdbath", s.done(), 0)
item("deck_chair", 1, 1, 2, note="A deck chair (a red, b blue).", cat="outdoors")
for v, c in enumerate(["b84a3a", "4a6aa0"]):
    s = Spr(1, 1)
    s.rect(26, 22, 102, 104, col("8a6a44"), ow=3, r=3)
    for k in range(5):
        s.rect(34, 30 + k * 14, 94, 40 + k * 14, col(c if k % 2 == 0 else "e8e0cc"), ow=1)
    sprite("deck_chair", s.done(), v)
item("picnic_table", 3, 2, 2, note="A picnic table with benches.", cat="outdoors")
s = Spr(3, 2)
s.rect(20, 14, 364, 60, col("8a6a44"), ow=3, r=4)
s.rect(20, 196, 364, 242, col("8a6a44"), ow=3, r=4)
s.rect(36, 68, 348, 188, col("a88458"), ow=4, r=4)
for k in range(1, 5):
    s.line([(36 + k * 62, 70), (36 + k * 62, 186)], (60, 44, 30, 255), 2)
sprite("picnic_table", s.done(), 0)
item("kennel", 1, 1, 2, note="A dog kennel.", cat="outdoors")
s = Spr(1, 1)
s.poly([(22, 98), (22, 40), (64, 20), (106, 40), (106, 98)], col("a86a4a"), ow=4)
s.line([(64, 20), (64, 98)], (60, 40, 30, 255), 3)
s.poly([(46, 98), (46, 74), (64, 62), (82, 74), (82, 98)], (30, 24, 20), ow=2)
sprite("kennel", s.done(), 0)
item("doormat", 1, 1, 1, note="A doormat (a, b).", cat="outdoors")
for v, c in enumerate(["7a5a3a", "5a6a4a"]):
    s = Spr(1, 1)
    s.rect(22, 38, 106, 90, col(c), ow=3, r=4)
    for k in range(6):
        s.line([(30, 46 + k * 7), (98, 46 + k * 7)], shade(col(c), 0.7), 2)
    sprite("doormat", s.done(shadow=False), v)
item("plant_pot", 1, 1, 2, note="A potted plant by the door (a, b, c).", cat="outdoors")
for v, c in enumerate(["4a8a4a", "6a9a44", "c05a4a"]):
    s = Spr(1, 1)
    s.ellipse(26, 26, 102, 102, col("a8643c"), ow=3)
    s.ellipse(34, 34, 94, 94, col("4a3828"), ow=0, outline=None)
    for k in range(7):
        a = k / 7 * 2 * math.pi
        s.ellipse(64 + math.cos(a) * 18 - 16, 64 + math.sin(a) * 18 - 16, 64 + math.cos(a) * 18 + 16, 64 + math.sin(a) * 18 + 16, col(c if v < 2 else ["4a8a4a", "c05a4a"][k % 2]), ow=2)
    sprite("plant_pot", s.done(alpha=0.4), v)
item("compost_heap", 1, 1, 2, note="A compost heap.", cat="outdoors")
s = Spr(1, 1)
s.rect(22, 22, 106, 106, col("7a5a38"), ow=3, r=4)
s.ellipse(32, 32, 96, 96, col("4a3a28"), ow=0, outline=None)
for k in range(8):
    cx0, cy0 = R.randint(34, 76), R.randint(34, 76)
    s.ellipse(cx0, cy0, cx0 + R.randint(12, 24), cy0 + R.randint(10, 20), col(R.choice(["6a8a44", "8a6a3a", "9a8a58"])), ow=1)
sprite("compost_heap", s.done(), 0)
item("gas_pump", 1, 2, 2, note="A petrol pump on its island: two nozzles, a display.", cat="outdoors")
s = Spr(1, 2)
s.rect(10, 12, 118, 244, col("a8a8a0"), ow=4, r=6)
s.bevel(30, 44, 98, 212, col("c0b8a8"), ow=3, r=6)
s.rect(40, 56, 88, 86, col("202c30"), ow=2)
s.rect(46, 62, 82, 80, col("8ac07a"), ow=1)
s.rect(40, 100, 88, 112, col("b84a3a"), ow=2)
s.line([(30, 150), (14, 176)], (40, 36, 34, 255), 5)
s.line([(98, 150), (114, 176)], (40, 36, 34, 255), 5)
sprite("gas_pump", s.done(), 0)

# =========================================================================== furniture ==
def shelf_img(c1, c2):
    s = Spr(2, 1)
    s.bevel(8, 14, 248, 114, col("8a8a84"), ow=3, r=4)
    for k in range(6):
        x = 18 + k * 38
        s.rect(x, 22, x + 30, 52, col(c1 if k % 2 == 0 else c2), ow=2, r=2)
        s.rect(x, 62, x + 30, 92, col(c2 if k % 2 == 0 else c1), ow=2, r=2)
    s.line([(12, 58), (244, 58)], (60, 60, 60, 255), 3)
    return s.done()


item("shop_shelf", 2, 1, 2, solid=True, container="shelf_tins", note="A shop shelf stacked with tins and boxes (a, b, c).", cat="furniture")
for v, (c1, c2) in enumerate([("c8503c", "d8c048"), ("4a7aa8", "e0d8c0"), ("5a8a50", "c87a3c")]):
    faced("shop_shelf", shelf_img(c1, c2), v)
item("checkout", 2, 1, 2, solid=True, container="kitchen_counter", note="A check-out counter with a till.", cat="furniture")
s = Spr(2, 1)
s.bevel(8, 14, 248, 114, col("8a6a44"), ow=3, r=4)
s.rect(24, 28, 100, 96, col("b8b4a8"), ow=3, r=3)
s.rect(34, 36, 80, 62, col("202c30"), ow=2)
s.rect(36, 70, 90, 88, col("707068"), ow=2)
s.line([(160, 30), (230, 30), (230, 98), (160, 98)], (60, 60, 60, 255), 3)
faced("checkout", s.done())
item("display_case", 2, 1, 2, solid=True, container="cupboard", note="A glass display case.", cat="furniture")
s = Spr(2, 1)
s.bevel(8, 14, 248, 114, col("a8b4b4"), ow=3, r=4)
s.rect(20, 26, 236, 102, col("c4dcdc"), ow=2, r=2)
for k in range(5):
    s.ellipse(34 + k * 40, 50, 58 + k * 40, 74, col(["c8a038", "b8b8b0", "c05a4a", "5a8a9a", "d8d0b0"][k]), ow=2)
s.line([(30, 34), (110, 30)], (255, 255, 255, 120), 3)
faced("display_case", s.done())
item("cooler", 1, 1, 2, solid=True, container="fridge", note="A drinks cooler.", cat="furniture")
s = Spr(1, 1)
s.bevel(10, 14, 118, 118, col("c8d0d4"), ow=3, r=4)
s.rect(22, 26, 106, 104, col("8ab0c8"), ow=2, r=2)
for k in range(3):
    s.rect(30 + k * 26, 36, 46 + k * 26, 90, col(["c8503c", "5a9a5a", "d8c048"][k]), ow=2, r=3)
faced("cooler", s.done(), 0, square=True)
item("tool_chest", 2, 1, 2, solid=True, container="locker", note="A red tool chest on wheels.", cat="furniture")
s = Spr(2, 1)
s.bevel(8, 14, 248, 114, col("b0453a"), ow=3, r=4)
for k in range(4):
    s.rect(18, 22 + k * 22, 238, 40 + k * 22, shade(col("b0453a"), 1.1 - 0.05 * k), ow=2, r=2)
    s.rect(110, 28 + k * 22, 146, 34 + k * 22, col("d8d0c0"), ow=1)
faced("tool_chest", s.done())
item("toy_chest", 1, 1, 2, solid=True, container="crate", note="A toy chest.", cat="furniture")
s = Spr(1, 1)
s.bevel(12, 20, 116, 112, col("c8903c"), ow=3, r=6)
s.rect(20, 30, 108, 54, col("5a7ab0"), ow=2, r=3)
s.ellipse(54, 36, 74, 56, col("e8d048"), ow=2)
faced("toy_chest", s.done(), 0, square=True)
item("vanity", 1, 1, 2, solid=True, container="cabinet", note="A dressing table with a mirror.", cat="furniture")
s = Spr(1, 1)
s.bevel(8, 22, 120, 112, col("d4c4a4"), ow=3, r=4)
s.rect(30, 8, 98, 32, col("a8d0e0"), ow=3, r=4)
s.rect(18, 50, 56, 76, col("e0b0c0"), ow=2)
s.ellipse(80, 54, 104, 76, col("c8a050"), ow=2)
faced("vanity", s.done(), 0, square=True)
item("piano", 2, 1, 2, solid=True, note="An upright piano.", cat="furniture")
s = Spr(2, 1)
s.bevel(8, 10, 248, 118, col("3c2e28"), ow=3, r=4)
s.rect(20, 66, 236, 106, col("e8e4d8"), ow=2)
for k in range(15):
    s.line([(32 + k * 14, 66), (32 + k * 14, 106)], (60, 54, 48, 255), 2)
for k in (1, 2, 4, 5, 6, 8, 9, 11, 12, 13):
    s.rect(28 + k * 14, 66, 38 + k * 14, 92, (30, 26, 24), ow=1)
faced("piano", s.done())
item("fireplace", 2, 1, 2, solid=True, note="A brick fireplace.", cat="furniture")
s = Spr(2, 1)
s.bevel(8, 8, 248, 118, col("a8604a"), ow=3, r=3)
s.rect(70, 30, 186, 112, (22, 18, 16), ow=3, r=3)
s.rect(86, 70, 170, 106, col("4a3a2e"), ow=2)
s.ellipse(96, 84, 156, 108, (90, 50, 30), ow=0, outline=None)
for k in range(7):
    s.line([(14, 18 + k * 14), (66, 18 + k * 14)], (90, 52, 40, 255), 2)
    s.line([(190, 18 + k * 14), (242, 18 + k * 14)], (90, 52, 40, 255), 2)
faced("fireplace", s.done())
item("aquarium", 2, 1, 2, solid=True, note="A fish tank on a stand.", cat="furniture")
s = Spr(2, 1)
s.bevel(8, 14, 248, 114, col("2c3c4a"), ow=3, r=4)
s.rect(18, 24, 238, 96, col("5aa0b8"), ow=2, r=2)
s.ellipse(60, 44, 100, 64, col("e08a3a"), ow=2)
s.ellipse(150, 60, 184, 76, col("c8c8d0"), ow=2)
s.line([(30, 90), (40, 52), (50, 90)], (60, 130, 70, 255), 4)
s.line([(200, 90), (212, 56), (224, 90)], (60, 130, 70, 255), 4)
faced("aquarium", s.done())
item("crib", 1, 2, 2, solid=True, note="A cot with a mobile.", cat="furniture")
s = Spr(1, 2)
s.bevel(10, 10, 118, 246, col("d8c8a8"), ow=3, r=4)
s.rect(22, 24, 106, 232, col("e8e4dc"), ow=2, r=3)
for k in range(8):
    s.line([(16, 30 + k * 26), (112, 30 + k * 26)], (150, 130, 100, 255), 2)
s.ellipse(40, 40, 88, 82, col("d8b894"), ow=2)
sprite("crib", s.done(), 0, "s")
sprite("crib", s.done().transpose(Image.FLIP_TOP_BOTTOM), 0, "n")
item("bunk_bed", 1, 2, 2, solid=True, note="Bunk beds seen from above: the top bunk and its ladder.", cat="furniture")
s = Spr(1, 2)
s.bevel(8, 8, 120, 248, col("8a6a44"), ow=3, r=4)
s.rect(20, 24, 108, 232, col("5a78a8"), ow=2, r=4)
s.rect(26, 28, 102, 72, col("e8e4dc"), ow=2, r=6)
s.line([(116, 70), (116, 220)], (60, 44, 30, 255), 4)
for k in range(5):
    s.line([(112, 80 + k * 30), (124, 80 + k * 30)], (60, 44, 30, 255), 3)
sprite("bunk_bed", s.done(), 0, "s")
sprite("bunk_bed", s.done().transpose(Image.FLIP_TOP_BOTTOM), 0, "n")
item("shower", 1, 1, 2, solid=True, note="A shower stall.", cat="furniture")
s = Spr(1, 1)
s.bevel(8, 8, 120, 120, col("c8d4d8"), ow=3, r=4)
s.rect(20, 20, 108, 108, col("e4eaec"), ow=2, r=6)
s.ellipse(52, 52, 76, 76, col("8a98a0"), ow=3)
for k in range(8):
    a = k / 8 * 2 * math.pi
    s.line([(64, 64), (64 + math.cos(a) * 30, 64 + math.sin(a) * 30)], (255, 255, 255, 110), 2)
faced("shower", s.done(), 0, square=True)
item("washer", 1, 1, 2, solid=True, note="A washing machine (a white, b grey).", cat="furniture")
for v, c in enumerate(["e0e0dc", "b4b8bc"]):
    s = Spr(1, 1)
    s.bevel(10, 10, 118, 118, col(c), ow=3, r=6)
    s.ellipse(30, 36, 98, 104, col("5a6a74"), ow=4)
    s.ellipse(40, 46, 88, 94, col("9ab0bc"), ow=2)
    s.rect(24, 16, 60, 28, col("9a9a96"), ow=1)
    s.ellipse(76, 16, 90, 28, col("6a6a68"), ow=1)
    faced("washer", s.done(), v, square=True)
item("dining_table_sq", 2, 2, 2, solid=True, note="A square table (a wood, b white).", cat="furniture")
for v, c in enumerate(["a07c52", "dcd8cc"]):
    s = Spr(2, 2)
    s.bevel(14, 14, 242, 242, col(c), ow=4, r=8)
    s.ellipse(100, 100, 156, 156, shade(col(c), 0.85), ow=2)
    sprite("dining_table_sq", s.done(), v)
item("barber_chair", 1, 1, 2, solid=True, note="A barber's chair.", cat="furniture")
s = Spr(1, 1)
s.ellipse(14, 14, 114, 114, col("4a4a50"), ow=4)
s.ellipse(26, 26, 102, 102, col("a8483a"), ow=3)
s.rect(36, 18, 92, 40, col("8a3c30"), ow=3, r=6)
s.ellipse(50, 50, 78, 78, col("c0584a"), ow=2)
faced("barber_chair", s.done(), 0, square=True)
item("cafe_table", 1, 1, 2, solid=True, note="A small round cafe table (a, b).", cat="furniture")
for v, c in enumerate(["dcd0b4", "7a9ab0"]):
    s = Spr(1, 1)
    s.ellipse(16, 16, 112, 112, col(c), ow=4)
    s.ellipse(28, 28, 100, 100, shade(col(c), 1.1), ow=0, outline=None)
    s.ellipse(52, 50, 74, 72, (250, 250, 246), ow=2)
    sprite("cafe_table", s.done(), v)
item("bar_stool", 1, 1, 2, note="A bar stool.", cat="furniture")
s = Spr(1, 1)
s.ellipse(30, 30, 98, 98, col("a8483a"), ow=4)
s.ellipse(40, 40, 88, 88, col("c0584a"), ow=0, outline=None)
sprite("bar_stool", s.done(), 0)
item("plant_floor", 1, 1, 2, note="A big plant in a pot (a, b).", cat="furniture")
for v in range(2):
    s = Spr(1, 1)
    s.ellipse(30, 30, 98, 98, col("a8643c"), ow=3)
    for k in range(9):
        a = k / 9 * 2 * math.pi + v
        x, y = 64 + math.cos(a) * 26, 64 + math.sin(a) * 26
        s.ellipse(x - 22, y - 22, x + 22, y + 22, col(["4a8a4a", "5a9a50", "3a7a44"][k % 3]), ow=2)
    s.ellipse(44, 44, 84, 84, col("6aa858"), ow=2)
    sprite("plant_floor", s.done(alpha=0.4), v)
item("rocking_chair", 1, 1, 2, note="A rocking chair.", cat="furniture")
s = Spr(1, 1)
s.rect(24, 20, 104, 108, col("8a6a44"), ow=3, r=6)
s.rect(34, 30, 94, 92, col("b89868"), ow=2, r=4)
s.line([(20, 24), (20, 104)], (60, 44, 30, 255), 4)
s.line([(108, 24), (108, 104)], (60, 44, 30, 255), 4)
sprite("rocking_chair", s.done(), 0)
item("tire_stack", 1, 1, 2, solid=True, note="A stack of tyres.", cat="furniture")
s = Spr(1, 1)
for k in range(3):
    o = k * 5
    s.ellipse(20 + o, 20 + o, 108 + o - 10, 108 + o - 10, col("3a3836"), ow=3)
    s.ellipse(44 + o, 44 + o, 84 + o - 10, 84 + o - 10, col("7a7870"), ow=3)
sprite("tire_stack", s.done(), 0)
item("jerrycan", 1, 1, 2, note="A jerry can (a red, b green).", cat="furniture")
for v, c in enumerate(["b8402e", "5a7a44"]):
    s = Spr(1, 1)
    s.bevel(34, 26, 94, 100, col(c), ow=3, r=6)
    s.rect(44, 30, 64, 44, shade(col(c), 0.6), ow=2)
    s.line([(74, 40), (74, 90)], shade(col(c), 0.7), 3)
    sprite("jerrycan", s.done(), v)
item("mannequin", 1, 1, 2, note="A shop mannequin.", cat="furniture")
s = Spr(1, 1)
s.ellipse(24, 40, 104, 88, col("d8c8b0"), ow=4)
s.ellipse(48, 24, 80, 56, col("e8d8c0"), ow=3)
s.line([(24, 64), (104, 64)], (170, 150, 120, 255), 3)
sprite("mannequin", s.done(), 0)

# ===================================================================================== the lines ==
# More kinds of fence and hedge (the kit has a white and a brown picket fence, chain link, a low brick wall and a clipped hedge): a rusty wire fence, a tall board fence, a post and rail fence, an
# unkept hedge and a low stone wall. Each is an AUTOTILE: 16 cells of 128 px, the cell by the sides that connect (N 1, E 2, S 4, W 8), the line running through the middle of the cell.
FENCES = [("fence_wire", "A rusty wire fence on posts, sagging."), ("fence_privacy", "A tall board fence, seen from above."), ("fence_rail", "A post and rail fence."),
          ("hedge_wild", "An unkept hedge, ragged and overgrown."), ("wall_stone", "A low wall of rough stone with a flat coping.")]


def fence_cell(style, mask):
    S3 = 3
    im = Image.new("RGBA", (128 * S3, 128 * S3), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = random.Random(hash((style, mask)) & 0xffff)

    def P(x, y):
        return (x * S3, y * S3)

    def seg(a, b, w, fill):
        d.line([P(*a), P(*b)], fill=fill + (255,) if len(fill) == 3 else fill, width=int(w * S3))

    ends = []
    if mask & 1:
        ends.append((64, 0))
    if mask & 2:
        ends.append((128, 64))
    if mask & 4:
        ends.append((64, 128))
    if mask & 8:
        ends.append((0, 64))
    c = (64, 64)
    if style == "fence_wire":
        for e in ends:
            for off, wd in ((-9, 2.2), (0, 2.2), (9, 2.2)):
                a = (c[0] + (off if e[0] == 64 else 0), c[1] + (off if e[1] == 64 else 0))
                b = (e[0] + (off if e[0] == 64 else 0), e[1] + (off if e[1] == 64 else 0))
                seg(a, b, wd + 2.4, INK)
            for off in (-9, 0, 9):
                a = (c[0] + (off if e[0] == 64 else 0), c[1] + (off if e[1] == 64 else 0))
                b = (e[0] + (off if e[0] == 64 else 0), e[1] + (off if e[1] == 64 else 0))
                seg(a, b, 2.2, col("9a6a4a"))
        d.rectangle([P(56, 56), P(72, 72)], fill=col("6a5038") + (255,), outline=INK, width=3 * S3)
        d.rectangle([P(59, 58), P(64, 64)], fill=col("8a6a4c") + (255,))
    elif style == "fence_privacy":
        for e in ends:
            horiz = e[1] == 64
            a = c
            b = e
            seg(a, b, 28, INK)
            seg(a, b, 22, col("a07c52"))
            seg(a, b, 6, col("c09a6a"))
            for k in range(1, 8):
                t = k / 8.0
                p = (c[0] + (e[0] - c[0]) * t, c[1] + (e[1] - c[1]) * t)
                if horiz:
                    seg((p[0], p[1] - 10), (p[0], p[1] + 10), 1.6, col("5a4028"))
                else:
                    seg((p[0] - 10, p[1]), (p[0] + 10, p[1]), 1.6, col("5a4028"))
        d.rectangle([P(52, 52), P(76, 76)], fill=col("7a5a3a") + (255,), outline=INK, width=3 * S3)
        d.rectangle([P(56, 56), P(70, 70)], fill=col("a88458") + (255,))
    elif style == "fence_rail":
        for e in ends:
            horiz = e[1] == 64
            for off in (-8, 8):
                a = (c[0] + (0 if horiz else off), c[1] + (off if horiz else 0))
                b = (e[0] + (0 if horiz else off), e[1] + (off if horiz else 0))
                seg(a, b, 8, INK)
                seg(a, b, 4.5, col("a47c52"))
        d.rectangle([P(55, 55), P(73, 73)], fill=col("7a5a3a") + (255,), outline=INK, width=3 * S3)
        d.rectangle([P(58, 57), P(66, 65)], fill=col("a88458") + (255,))
    elif style == "hedge_wild":
        blobs = []
        for e in ends + [c]:
            n = 5 if e != c else 3
            for k in range(n):
                t = (k + 0.5) / n
                p = (c[0] + (e[0] - c[0]) * t, c[1] + (e[1] - c[1]) * t) if e != c else c
                blobs.append((p[0] + r.uniform(-7, 7), p[1] + r.uniform(-7, 7), r.uniform(15, 25)))
        for x, y, rr in blobs:
            d.ellipse([P(x - rr - 3, y - rr - 3), P(x + rr + 3, y + rr + 3)], fill=INK)
        for x, y, rr in blobs:
            d.ellipse([P(x - rr, y - rr), P(x + rr, y + rr)], fill=col(r.choice(["3c6a38", "4a7a40", "34603a"])) + (255,))
        for x, y, rr in blobs:
            d.ellipse([P(x - rr * 0.65, y - rr * 0.75), P(x + rr * 0.35, y + rr * 0.2)], fill=col(r.choice(["5a9248", "6aa254"])) + (255,))
        for k in range(6):
            x, y = r.randint(24, 104), r.randint(24, 104)
            seg((x, y), (x + r.randint(-8, 8), y - r.randint(8, 16)), 2.2, col("4a7a3a"))
    else:
        for e in ends:
            seg(c, e, 34, INK)
            seg(c, e, 28, col("8c8a82"))
            seg(c, e, 8, col("b4b0a4"))
            horiz = e[1] == 64
            for k in range(1, 6):
                t = k / 6.0
                p = (c[0] + (e[0] - c[0]) * t, c[1] + (e[1] - c[1]) * t)
                if horiz:
                    seg((p[0], p[1] - 12), (p[0], p[1] + 12), 1.8, col("5e5c56"))
                else:
                    seg((p[0] - 12, p[1]), (p[0] + 12, p[1]), 1.8, col("5e5c56"))
        d.rectangle([P(48, 48), P(80, 80)], fill=col("8c8a82") + (255,), outline=INK, width=3 * S3)
        d.rectangle([P(54, 54), P(70, 70)], fill=col("b4b0a4") + (255,))
    return im.resize((128, 128), Image.LANCZOS)


fences_img = Image.new("RGBA", (512, 512 * len(FENCES)), (0, 0, 0, 0))
for fi, (fid, _note) in enumerate(FENCES):
    for m in range(16):
        fences_img.alpha_composite(fence_cell(fid, m), ((m % 4) * 128, fi * 512 + (m // 4) * 128))
os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
fences_img.save(os.path.join(os.path.dirname(OUT_PNG), "fences.png"), optimize=True)

# ====================================================================================== the sheet ==
def pack(items_imgs, width=1536):
    out = []
    x = y = row_h = 0
    for key, im in sorted(items_imgs, key=lambda t: (-t[1].size[1], t[0])):
        w, h = im.size
        if x + w + 4 > width:
            x = 0
            y += row_h + 4
            row_h = 0
        out.append((key, x, y, im))
        x += w + 4
        row_h = max(row_h, h)
    return out, y + row_h


flat = []
for iid, it in ITEMS.items():
    for k, sp in enumerate(it["sprites"]):
        flat.append(((iid, k), sp["im"]))
for v, im in enumerate(WRECKS):
    flat.append((("car_wreck", v), im))
placed, height = pack(flat)
sheet = Image.new("RGBA", (1536, height), (0, 0, 0, 0))
pos = {}
for key, x, y, im in placed:
    sheet.alpha_composite(im, (x, y))
    pos[key] = (x, y, im.size[0], im.size[1])
os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
sheet.save(OUT_PNG, optimize=True)

man_items = []
sizes = {}
for iid, it in ITEMS.items():
    fw, fh = it["fp"]
    sprites = []
    variants = 0
    facings = set()
    for k, sp in enumerate(it["sprites"]):
        x, y, w, h = pos[(iid, k)]
        e = {"file": "life/life_sheet.png", "rect": [x, y, w, h], "fp": [fw, fh] if sp["facing"] not in ("w", "e") else [fh, fw], "variant": sp["v"]}
        if sp["facing"]:
            e["facing"] = sp["facing"]
            facings.add(sp["facing"])
        if sp["orient"]:
            e["orient"] = sp["orient"]
        if sp["state"]:
            e["state"] = sp["state"]
        sprites.append(e)
        variants = max(variants, sp["v"] + 1)
    layer = {1: "decal", 2: "object", 4: "object"}[it["layer"]]
    tags = ["life"]
    if it["solid"]:
        tags.append("solid")
    if it["container"]:
        tags.append("container")
    m = {"id": iid, "category": it["cat"], "kind": "prop", "layer": layer, "footprint": [fw, fh], "anchor": [0.0625, 0.0625], "tags": tags, "solid": "all" if it["solid"] else [],
         "sprites": sprites, "variants": variants, "note": it["note"], "tile_px": 64}
    if facings:
        m["facings"] = sorted(facings)
    man_items.append(m)
    cat_dir = {"street": "street", "outdoors": "outdoors", "furniture": "furniture"}[it["cat"]]
    sizes["res://assets/town/life/%s.png" % iid] = [sprites[0]["rect"][2], sprites[0]["rect"][3]]
for fi, (fid, note) in enumerate(FENCES):
    man_items.append({"id": fid, "category": "outdoors", "kind": "atlas", "layer": "object", "footprint": [1, 1], "anchor": [0, 0], "grid": [4, 4], "cell_px": [128, 128],
                      "cells": {str(m): [m % 4, m // 4] for m in range(16)}, "tags": ["fence", "solid", "autotile", "life"], "sprites": [{"file": "life/fences.png", "rect": [0, fi * 512, 512, 512]}],
                      "note": note + " Cell index = mask of the CONNECTED sides: N 1 + E 2 + S 4 + W 8; col = index % 4, row = index // 4.", "solid": "all", "name": fid})
append = []
w_sprites = []
for v in range(len(WRECKS)):
    x, y, w, h = pos[("car_wreck", v)]
    w_sprites.append({"file": "life/life_sheet.png", "rect": [x, y, w, h], "variant": 2 + v, "look": "burnt", "fp": [4, 3], "tile_px": 64})
doc = {"_doc": "The items of tools/make_town_life.py (WORLD3): the schema of town_art.json. An item whose id is in the kit gets `append_sprites` added to its sprites (and `variants` raised).",
       "items": man_items, "append": [{"id": "car_wreck", "append_sprites": w_sprites, "variants": 4, "tile_px_of_appended": 64}]}
with open(OUT_JSON, "w") as f:
    json.dump(doc, f, indent=1)
# the sizes the generator reads (assets/data/prop_sizes.json: one line for each picture)
table = json.load(open(SIZES_JSON))
for k in list(table.keys()):
    if "/town/life/" in k:
        del table[k]
table.update(sizes)
with open(SIZES_JSON, "w") as f:
    f.write("{\n" + ",\n".join('"%s": [%d, %d]' % (k, v[0], v[1]) for k, v in sorted(table.items())) + "\n}\n")
print("town life: %d items, %d sprites, sheet %d x %d, %d bytes" % (len(man_items), len(flat), sheet.size[0], sheet.size[1], os.path.getsize(OUT_PNG)))
