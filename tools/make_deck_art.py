#!/usr/bin/env python3
"""Draws the art for the raised platforms (the walkways behind the wall and the corner
towers) in code: flat colours with a dark outline, like the game's other props. No picture
is read (until 2026-10-17 the pieces were cut out of pictures made with an image model;
see docs/assets-log.md).

    python3 tools/make_deck_art.py            # writes into assets/objects/
    DECK_DEBUG=some/dir python3 tools/make_deck_art.py   # also a contact sheet

The pieces scripts/render/deck_faces.gd puts together:

    deck_face_bay_0..2.png   one bay of the scaffold between two posts (half a post at each side)
    deck_face_post_0..1.png  a post with its lashings, drawn over each joint
    deck_face_cap_w/e.png    the left and the right end of a face
    deck_leg.png             one post on its own, for the side walkways
    deck_face_tower.png      the whole base of a corner tower
    deck_ladder_front.png    a ladder hung down a face
    deck_ladder_side_w/e.png a ladder leaning out from the side of the west
                             and the east walkway

The sizes here and the constants at the top of deck_faces.gd go together.
Units: the faces are drawn at 192 pixels to the tile (the game's objects at 96); every
piece is drawn SS times bigger and scaled down, so the edges are smooth.
The output is the same bytes every time (the only randomness is seeded).
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "objects")
PX = 192  # pixels to the tile
SS = 4    # supersampling

# What the faces measure, in tiles. deck_faces.gd has the same numbers.
BAY_W = 1.25
WALKWAY_H = 1.3
TOWER_W = 3.6
TOWER_H = 1.9
LADDER_W = 0.62
LADDER_LEAN = 1.35

# the pieces in pixels (deck_faces.gd: CAP_WIDTH 69, CAP_POST 36, POST_WIDTH 66, LEG_WIDTH 39)
FACE_H = int(round(WALKWAY_H * PX))      # 250
BAY_PX = int(round(BAY_W * PX))          # 240
POST_PX = 66
CAP_PX = 69
CAP_POST_PX = 36
LEG_PX = 39
TOWER_PAD = 26

OUTLINE = (36, 24, 16)
WOOD = (132, 95, 60)
WOOD_LIGHT = (164, 123, 80)
WOOD_DARK = (96, 67, 42)
ROPE = (196, 168, 116)
CONCRETE = (146, 142, 134)
CONCRETE_DARK = (108, 104, 98)
STEEL = (106, 124, 142)
STEEL_LIGHT = (146, 164, 182)
STEEL_DARK = (72, 86, 100)

# where things stand on a walkway face (pixels from its top)
FASCIA_H = 30          # the plank board along the top
LEDGER_Y = 150         # the middle of the horizontal beam
FOOT_Y = 222           # the top of a footing (the post stands on it)
GROUND_Y = 246         # the foot of the face
POST_HALF = 17         # half the width of a post


# ----------------------------------------------------------------- helpers --

class Pad:
    """An RGBA picture drawn SS times bigger; coordinates are in output pixels."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.dr = ImageDraw.Draw(self.im)

    def _p(self, pts):
        return [(x * SS, y * SS) for x, y in pts]

    def poly(self, pts, fill, line=2.0):
        self.dr.polygon(self._p(pts), fill=fill + (255,), outline=OUTLINE + (255,), width=max(1, int(round(line * SS))))

    def rect(self, x0, y0, x1, y1, fill, line=2.0):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], fill, line)

    def line(self, pts, fill, width):
        self.dr.line(self._p(pts), fill=fill + (255,), width=max(1, int(round(width * SS))), joint="curve")

    def dot(self, x, y, r, fill, line=1.0):
        self.dr.ellipse([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS], fill=fill + (255,), outline=OUTLINE + (255,), width=max(1, int(round(line * SS))))

    def plank(self, a, b, t, fill=WOOD, light=WOOD_LIGHT, dark=WOOD_DARK):
        """A plank from a to b, t wide: outlined, a lit edge on its upper side and a grain line."""
        (ax, ay), (bx, by) = a, b
        dx, dy = bx - ax, by - ay
        n = math.hypot(dx, dy) or 1.0
        px, py = -dy / n * t / 2.0, dx / n * t / 2.0
        if py > 0:
            px, py = -px, -py           # (px, py) points up
        self.poly([(ax + px, ay + py), (bx + px, by + py), (bx - px, by - py), (ax - px, ay - py)], fill)
        k = 0.55
        self.line([(ax + px * k, ay + py * k), (bx + px * k, by + py * k)], light, max(1.0, t * 0.16))
        k = -0.25
        self.line([(ax + px * k + dx * 0.15, ay + py * k + dy * 0.15), (ax + px * k + dx * 0.7, ay + py * k + dy * 0.7)], dark, 1.0)

    def under(self, x0, x1, y0, y1, dark=(10, 8, 8), light=(46, 40, 36)):
        """The shade under a deck between x0 and x1: near black under the planks, a little lighter at the foot."""
        a = np.asarray(self.im).astype(np.float32)
        Y0, Y1, X0, X1 = int(y0 * SS), int(y1 * SS), int(x0 * SS), int(x1 * SS)
        t = (np.arange(Y1 - Y0, dtype=np.float32) / max(1, Y1 - Y0 - 1)) ** 1.4
        col = np.array(dark, np.float32)[None, :] * (1 - t[:, None]) + np.array(light, np.float32)[None, :] * t[:, None]
        a[Y0:Y1, X0:X1, :3] = col[:, None, :]
        a[Y0:Y1, X0:X1, 3] = 255.0
        self.im = Image.fromarray(a.astype(np.uint8))
        self.dr = ImageDraw.Draw(self.im)

    def out(self):
        return self.im.resize((self.w, self.h), Image.LANCZOS)


def nails(pad, x0, x1, y, rng, step=30.0):
    x = x0 + rng.uniform(6, 14)
    while x < x1 - 6:
        pad.dot(x, y, 1.6, (70, 64, 60), 0.6)
        x += step + rng.uniform(-6, 6)


def fascia(pad, x0, x1, rng):
    pad.plank((x0, FASCIA_H / 2.0), (x1, FASCIA_H / 2.0), FASCIA_H - 2)
    nails(pad, x0, x1, FASCIA_H * 0.62, rng)


def post(pad, cx, rng, top=FASCIA_H - 4, lash=True):
    """A post standing on its footing at cx, with the rope lashings where the braces meet it."""
    pad.rect(cx - POST_HALF - 6, FOOT_Y, cx + POST_HALF + 6, GROUND_Y, CONCRETE)
    pad.line([(cx - POST_HALF - 4, FOOT_Y + 3), (cx + POST_HALF + 4, FOOT_Y + 3)], (176, 172, 164), 1.5)
    pad.plank((cx, top), (cx, FOOT_Y + 1), POST_HALF * 2)
    pad.line([(cx - POST_HALF * 0.3, top + 10), (cx - POST_HALF * 0.3, FOOT_Y - 30)], WOOD_DARK, 1.0)
    if lash:
        for y in (FASCIA_H + 10, LEDGER_Y):
            for k in range(3):
                yy = y - 6 + k * 5
                pad.line([(cx - POST_HALF - 2, yy - 3), (cx + POST_HALF + 2, yy + 3)], ROPE, 1.6)


def ledger(pad, x0, x1):
    pad.plank((x0, LEDGER_Y), (x1, LEDGER_Y), 15)


# ---------------------------------------------------------------- walkway ---

def bay(i):
    """One bay: the dark under the deck, the cross braces, the ledger, half a post at each
    side and the fascia. The three bays differ in their braces and a little in their wood."""
    rng = np.random.RandomState(100 + i)
    w = BAY_PX
    pad = Pad(w, FACE_H)
    pad.under(0, w, FASCIA_H - 4, GROUND_Y - 1)
    l, r = POST_HALF, w - POST_HALF
    top = FASCIA_H + 4
    if i == 0:      # one big X down to the ledger
        pad.plank((l, top), (r, LEDGER_Y - 4), 13)
        pad.plank((l, LEDGER_Y - 4), (r, top), 13)
    elif i == 1:    # a single brace, low on the left
        pad.plank((l, LEDGER_Y - 4), (r, top), 13)
        pad.plank((l, FOOT_Y - 10), (l + 120, LEDGER_Y + 8), 11)
    else:           # an X, a short brace under the ledger
        pad.plank((l, top), (r, LEDGER_Y - 4), 13)
        pad.plank((l, LEDGER_Y - 4), (r, top), 13)
        pad.plank((r, FOOT_Y - 10), (r - 120, LEDGER_Y + 8), 10)
    ledger(pad, 0, w)
    post(pad, 0, rng)
    post(pad, w, rng)
    fascia(pad, -4, w + 4, rng)
    return pad.out()


def post_piece(i):
    rng = np.random.RandomState(200 + i)
    w = POST_PX
    pad = Pad(w, FACE_H)
    fascia(pad, -4, w + 4, rng)
    post(pad, w / 2.0, rng)
    return pad.out()


def cap_piece():
    """The left end of a face: the end post (CAP_POST_PX in from the end), the fascia from
    a little left of it, and the dark under the deck to its right."""
    rng = np.random.RandomState(300)
    w = CAP_PX
    pad = Pad(w, FACE_H)
    pad.under(CAP_POST_PX, w, FASCIA_H - 4, GROUND_Y - 1)
    ledger(pad, CAP_POST_PX, w + 4)
    post(pad, CAP_POST_PX, rng)
    fascia(pad, 4, w + 4, rng)
    return pad.out()


def leg_piece():
    """One post on its own (the supports along the side walkways, which show their edge to
    the yard), with the end of the board on it and nothing behind it."""
    rng = np.random.RandomState(400)
    w = LEG_PX
    pad = Pad(w, FACE_H)
    post(pad, w / 2.0, rng, top=4, lash=False)
    pad.plank((2, FASCIA_H / 2.0), (w - 2, FASCIA_H / 2.0), FASCIA_H - 6)
    return pad.out()


# ------------------------------------------------------------------ tower ---

def tower_piece():
    """The base of a corner tower: a thick deck slab TOWER_W wide, two front legs splayed a
    little out to their footings, two back legs (darker) between them, two tiers of cross
    bracing with ledgers, and the shade between the legs."""
    rng = np.random.RandomState(500)
    slab = int(round(TOWER_W * PX))
    w = slab + 2 * TOWER_PAD
    h = int(round(TOWER_H * PX))
    pad = Pad(w, h)
    x0, x1 = TOWER_PAD, TOWER_PAD + slab
    st = 44                              # the slab's depth
    gy = h - 8                           # the ground
    fy = gy - 26                         # the top of the footings
    # front legs: from under the slab corners (inset) out to their footings
    fl_top, fl_foot = x0 + 60, x0 + 22
    fr_top, fr_foot = x1 - 60, x1 - 22
    bl, br = x0 + 150, x1 - 150          # back legs (straight)
    pad.under(fl_top - 10, fr_top + 10, st - 4, gy - 2)
    for x in (bl, br):
        pad.rect(x - 26, fy + 8, x + 26, gy - 8, CONCRETE_DARK)
        pad.plank((x, st), (x, fy + 9), 30, WOOD_DARK, WOOD, (70, 48, 30))
    # bracing: two tiers, each an X and a ledger under it
    tiers = [(st + 10, 150), (150, fy - 44)]
    for (ta, tb) in tiers:
        la = fl_top + (fl_foot - fl_top) * (ta - st) / (fy - st)
        lb = fl_top + (fl_foot - fl_top) * (tb - st) / (fy - st)
        ra = fr_top + (fr_foot - fr_top) * (ta - st) / (fy - st)
        rb = fr_top + (fr_foot - fr_top) * (tb - st) / (fy - st)
        pad.plank((la, ta + 6), (rb, tb - 8), 16)
        pad.plank((lb, tb - 8), (ra, ta + 6), 16)
        pad.dot((la + rb) / 2.0, (ta + tb) / 2.0 - 1, 4.0, (80, 74, 70))
        pad.plank((lb - 22, tb), (rb + 22, tb), 17)
    for (top, foot) in ((fl_top, fl_foot), (fr_top, fr_foot)):
        pad.rect(foot - 34, fy, foot + 34, gy, CONCRETE)
        pad.line([(foot - 32, fy + 3), (foot + 32, fy + 3)], (176, 172, 164), 1.5)
        pad.plank((top, st - 4), (foot, fy + 1), 38)
        for y in (st + 14, 150):
            t = (y - st) / (fy - st)
            cx = top + (foot - top) * t
            for k in range(3):
                yy = y - 7 + k * 6
                pad.line([(cx - 21, yy - 4), (cx + 21, yy + 4)], ROPE, 1.8)
    # the slab: a thick plank board with a lit top edge and nails
    pad.plank((x0, st / 2.0), (x1, st / 2.0), st)
    pad.line([(x0 + 4, st * 0.5), (x1 - 4, st * 0.5)], WOOD_DARK, 1.2)
    nails(pad, x0, x1, st * 0.28, rng, 44.0)
    nails(pad, x0, x1, st * 0.74, rng, 44.0)
    return pad.out(), (TOWER_PAD, slab)


# ----------------------------------------------------------------- ladders --

def ladder_big():
    """A steel pipe ladder seen from the front, hooks at the top and foot plates, drawn big
    (front and side pieces are scaled from it)."""
    w, h = 120, 300
    pad = Pad(w, h)
    lx, rx = 24, 96
    top, foot = 30, h - 8
    y = top + 22
    while y < foot - 14:
        pad.plank((lx, y), (rx, y), 7, STEEL, STEEL_LIGHT, STEEL_DARK)
        y += 26
    for x in (lx, rx):
        pad.plank((x, top), (x, foot - 4), 10, STEEL, STEEL_LIGHT, STEEL_DARK)
        # the hook over the rail
        hook = [(x, top + 2), (x, top - 12), (x + 3, top - 19), (x + 9, top - 22), (x + 15, top - 19), (x + 18, top - 12), (x + 18, top - 2)]
        pad.line(hook, OUTLINE, 12)
        pad.line(hook, STEEL, 8)
        pad.line(hook[1:5], STEEL_LIGHT, 2)
        pad.rect(x - 11, foot - 6, x + 11, foot, STEEL_DARK)
    return pad.out()


def ladder_pieces():
    big = ladder_big()
    front = big.resize((int(round(LADDER_W * PX)), int(round((WALKWAY_H + 0.22) * PX))), Image.LANCZOS)
    side = big.rotate(90, expand=True).resize((int(round(LADDER_LEAN * PX)), int(round(0.56 * PX))), Image.LANCZOS)
    return front, side


# -------------------------------------------------------------------- main --

def save(im, name):
    im.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, im.size)


def contact_sheet(parts):
    w = sum(p.size[0] + 20 for p in parts) + 20
    h = max(p.size[1] for p in parts) + 40
    sheet = Image.new("RGBA", (w, h), (118, 116, 112, 255))
    x = 20
    for p in parts:
        sheet.alpha_composite(p, (x, 20))
        x += p.size[0] + 20
    return sheet


def main():
    bays = [bay(i) for i in range(3)]
    posts = [post_piece(i) for i in range(2)]
    cap = cap_piece()
    for i, b in enumerate(bays):
        save(b, "deck_face_bay_%d.png" % i)
    for i, p in enumerate(posts):
        save(p, "deck_face_post_%d.png" % i)
    save(leg_piece(), "deck_leg.png")
    save(cap, "deck_face_cap_w.png")
    save(ImageOps.mirror(cap), "deck_face_cap_e.png")
    tower, (slab_x, slab_w) = tower_piece()
    save(tower, "deck_face_tower.png")
    print("tower: slab %d px wide, overhang %d px each side" % (slab_w, slab_x))
    front, side = ladder_pieces()
    save(front, "deck_ladder_front.png")
    save(side, "deck_ladder_side_w.png")
    save(ImageOps.mirror(side), "deck_ladder_side_e.png")
    out = os.environ.get("DECK_DEBUG")
    if out:
        os.makedirs(out, exist_ok=True)
        strip = Image.new("RGBA", (cap.size[0] * 2 + sum(b.size[0] for b in bays) + 200, bays[0].size[1] + 40), (118, 116, 112, 255))
        x = 20
        strip.alpha_composite(cap, (x, 20))
        x += CAP_POST_PX
        for i, b in enumerate(bays):
            strip.alpha_composite(b, (x, 20))
            if i:
                strip.alpha_composite(posts[i % 2], (x - POST_PX // 2, 20))
            x += b.size[0]
        strip.alpha_composite(ImageOps.mirror(cap), (x - (CAP_PX - CAP_POST_PX), 20))
        contact_sheet([strip]).convert("RGB").save(os.path.join(out, "face_strip.png"))
        contact_sheet([tower, front, side]).convert("RGB").save(os.path.join(out, "tower_ladders.png"))


if __name__ == "__main__":
    main()
