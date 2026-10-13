#!/usr/bin/env python3
"""Draws the prison's dead in the crew's own style (ROUND 10): small flat-coloured figures, a clean dark outline, a round head, one dark step and one light step of shading,
hunched and torn. Only PIL (no paid tool, no image API). Each figure is drawn at 4x and averaged down, on the same 368 x 327 canvas as assets/pawns/ruth_S.png
(pivot: the feet at pixel 184,227; 160 px to the tile; the legs are still the game's own mesh, coloured by the look's pants).

    python3 tools/make_rimworld_zombies.py                  # writes assets/pawns/zr<look>_S/E/N.png (24 looks) and zrc<look>_<pose>.png (corpses)
    python3 tools/make_rimworld_zombies.py --look=3         # only look 3
    python3 tools/make_rimworld_zombies.py --sheet=x.png    # also a 2x contact sheet next to Ruth, Walt and Ana
then import once: Godot --headless --path . --import

HOW TO ADD A LOOK: the outfit, its colours and the pants come from assets/data/map.json `zombieLooks` (so the game's legs match); this file adds the rest in small tables: SKIN_OF (skin tone),
EYES (pale, dark, red, white), HAIR_OVERRIDE (hair style), JOB (a job's outfit: prisoner, cook, nurse, mechanic, guard, gown), ARM_GONE, BITE, RIBS. A new look is one entry in each table that matters.
The parts (outfit(), hair_front(), head(), arm()) are shared. The game maps look_index % 24 to zr<n>.
"""
import argparse
import json
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAWNS = os.path.join(ROOT, "assets", "pawns")
SS = 4
CW, CH = 368, 327
CX = 184
OL = (30, 22, 17)
OLW = 6.0

BLOOD = (112, 22, 24)
BLOOD_D = (74, 14, 18)
BLOOD_L = (150, 36, 34)
BONE = (214, 206, 180)
TEETH = (222, 214, 184)
SOCKET = (38, 24, 28)
SKINS = [(142, 154, 124), (176, 166, 110), (126, 138, 150), (166, 164, 148), (150, 146, 118), (120, 130, 108)]    # grey-green, waxy yellow, bruised blue-grey, pale, dull olive, mouldy green


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mulc(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


class Win:
    """A transparent RGBA picture at 4x covering a window of the canvas, drawn in canvas pixels."""

    def __init__(self, x0, y0, w, h):
        self.x0, self.y0, self.w, self.h = int(round(x0)), int(round(y0)), int(w), int(h)
        self.img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))

    def pt(self, p):
        return ((p[0] - self.x0) * SS, (p[1] - self.y0) * SS)

    def mask(self, fn):
        m = Image.new("L", self.img.size, 0)
        fn(ImageDraw.Draw(m), self)
        return m


def poly_m(win, pts):
    return win.mask(lambda d, w: d.polygon([w.pt(p) for p in pts], fill=255))


def ell_m(win, cx, cy, rx, ry):
    return win.mask(lambda d, w: d.ellipse([w.pt((cx - rx, cy - ry)), w.pt((cx + rx, cy + ry))], fill=255))


def line_m(win, pts, width):
    def f(d, w):
        pp = [w.pt(p) for p in pts]
        d.line(pp, fill=255, width=int(width * SS), joint="curve")
        r = width * SS / 2
        for p in (pp[0], pp[-1]):
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)
    return win.mask(f)


def capsule_m(win, a, b, w0, w1=None):
    """A limb: round at both ends, w0 wide at a and w1 at b."""
    w1 = w0 if w1 is None else w1

    def f(d, w):
        pa, pb = w.pt(a), w.pt(b)
        ra, rb = w0 * SS / 2, w1 * SS / 2
        ang = math.atan2(pb[1] - pa[1], pb[0] - pa[0]) + math.pi / 2
        c, s = math.cos(ang), math.sin(ang)
        d.polygon([(pa[0] + c * ra, pa[1] + s * ra), (pb[0] + c * rb, pb[1] + s * rb), (pb[0] - c * rb, pb[1] - s * rb), (pa[0] - c * ra, pa[1] - s * ra)], fill=255)
        d.ellipse([pa[0] - ra, pa[1] - ra, pa[0] + ra, pa[1] + ra], fill=255)
        d.ellipse([pb[0] - rb, pb[1] - rb, pb[0] + rb, pb[1] + rb], fill=255)
    return win.mask(f)


def round_m(m, r=2.5):
    """Round the corners of a mask a little (a blur and a threshold)."""
    return m.filter(ImageFilter.GaussianBlur(r * SS)).point(lambda v: 255 if v > 128 else 0)


def dilate(m, r):
    """Grow a mask by about r px (a blur and a low threshold: round corners, and fast)."""
    s = max(1.0, r * 0.5)
    return m.filter(ImageFilter.GaussianBlur(s)).point(lambda v: 255 if v > 7 else 0)


def put(win, m, fill, outline=True, shade=True, ow=OLW, clip=None):
    """One flat part: outline, the fill, a dark band along the lower right and a light band along the upper left."""
    if clip is not None:
        m = ImageChops.multiply(m, clip)
    img = win.img
    if outline:
        img.paste(Image.new("RGBA", img.size, OL + (255,)), mask=dilate(m, ow * SS))
    img.paste(Image.new("RGBA", img.size, tuple(fill) + (255,)), mask=m)
    if shade:
        k = 5 * SS
        dark = ImageChops.subtract(m, ImageChops.offset(m, -k, -k))
        img.paste(Image.new("RGBA", img.size, mulc(fill, 0.8) + (255,)), mask=dark)
        k2 = 4 * SS
        lite = ImageChops.subtract(m, ImageChops.offset(m, k2, k2))
        img.paste(Image.new("RGBA", img.size, mulc(fill, 1.1) + (255,)), mask=lite)
    return m


def flat(win, m, col, alpha=255, clip=None):
    """Paint on top of a part (blood, a stain, a seam) without an outline."""
    if clip is not None:
        m = ImageChops.multiply(m, clip)
    if alpha != 255:
        m = m.point(lambda v: v * alpha // 255)
    win.img.paste(Image.new("RGBA", win.img.size, tuple(col) + (255,)), mask=m)


def jag(rng, x0, x1, y, amp, step=7):
    """A ragged hem: points from x0 to x1 along y, jagged by amp."""
    pts = [(x0, y)]
    x = x0 + step * 0.5
    up = True
    while x < x1 - 2:
        pts.append((x, y + (rng.uniform(0.3, 1.0) * amp if up else -rng.uniform(0, 0.4) * amp)))
        up = not up
        x += step * rng.uniform(0.7, 1.4)
    pts.append((x1, y))
    return pts


def smooth_poly(pts, n=2):
    """Round the corners of a closed polygon (Chaikin)."""
    for _ in range(n):
        out = []
        for k in range(len(pts)):
            a, b = pts[k], pts[(k + 1) % len(pts)]
            out.append((a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25))
            out.append((a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75))
        pts = out
    return pts


# ------------------------------------------------------------------ looks
SKIN_OF = [2, 1, 0, 4, 3, 1, 0, 2, 5, 3, 0, 1, 4, 2, 1, 0, 3, 5, 2, 0, 1, 3, 4, 5]
EYES = ["pale", "dark", "red", "white", "dark", "pale", "dark", "white", "red", "dark", "pale", "dark", "white", "dark", "red", "pale", "dark", "white", "pale", "dark", "red", "dark", "white", "pale"]
HAIR_OVERRIDE = {1: "long", 5: "wisp", 15: "bun", 21: "long", 23: "long", 8: "shave", 12: "hood", 2: "hood", 22: "hood", 14: "cap", 4: "cap", 11: "short"}
JOB = {8: "prisoner", 18: "cook", 15: "nurse", 13: "mechanic", 4: "guard", 14: "guard", 5: "gown"}
ARM_GONE = {7: "L", 11: "R", 17: "L", 22: "R", 19: "R"}      # an arm torn off at the elbow (the screen side in the S view)
BITE = {0: "L", 3: "R", 6: "R", 9: "L", 12: "L", 14: "R", 16: "L", 18: "R", 20: "R", 21: "L", 23: "R"}   # a bite wound on the shoulder
RIBS = {13, 17, 19, 3}


def load_looks():
    d = json.load(open(os.path.join(ROOT, "assets", "data", "map.json")))
    out = []
    for i, l in enumerate(d["zombieLooks"][:24]):
        job = JOB.get(i, "")
        top = hexc(l["top"])
        outer = hexc(l["outer"]) if "outer" in l else None
        style = l["topStyle"]
        if job == "prisoner":
            top, style, outer = (214, 112, 38), "tee", None
        elif job == "cook":
            style, outer = "tee", (224, 220, 204)
        elif job == "nurse":
            top, style = (84, 150, 150), "scrubs"
        elif job == "mechanic":
            top, style, outer = (56, 82, 112), "coverall", None
        elif job == "guard":
            style = "uniform"
        tl = l["tilt"]
        if abs(tl) < 0.06:
            tl = 0.1 if i % 2 else -0.1
        out.append(dict(
            i=i, job=job, style=style, top=top, outer=outer, hivis=(l.get("outerStyle") == "hivis" and job != "mechanic"), pattern=hexc(l["patternColor"]) if l.get("pattern") else None,
            tie=hexc(l["tie"]) if "tie" in l else None, pants=hexc(l["pants"]),
            skin=SKINS[SKIN_OF[i]], hair=HAIR_OVERRIDE.get(i, l["hair"]), hair_col=hexc(l["hairColor"]),
            tilt=tl, torn=l["torn"], blood=l["blood"], eyes=EYES[i], arm_gone=ARM_GONE.get(i, ""), bite=BITE.get(i, ""),
            ribs=i in RIBS, scab=(i * 7) % 4 == 0, bruise=(i * 5) % 3 == 0))
    return out


# ------------------------------------------------------------------ the head
def head(L, view, hx, hy, R=38):
    """Head layer (a Win): the face of the S view, the profile of E, the back of N. Returned as its own layer so the whole head can lean."""
    W = Win(hx - 64, hy - 64, 128, 128)
    rng = random.Random(L["i"] * 31 + ord(view))
    skin = L["skin"]
    sk_d = mulc(skin, 0.74)
    if view == "N":
        hair_back(W, L, hx, hy, R, rng)
        return W
    clipm = ell_m(W, hx, hy, R - 1, R)
    mx = hx + (3 if L["tilt"] > 0 else -3)
    if view == "S":
        put(W, ell_m(W, hx, hy, R, R * 1.03), skin)
        for sx in (-1, 1):       # sunken cheeks
            flat(W, ell_m(W, hx + sx * 28, hy + 12, 9, 15), sk_d, 150, clip=clipm)
        flat(W, ell_m(W, hx, hy - 31, 22, 8), mulc(skin, 0.86), 130, clip=clipm)
        socket(W, L, hx - 15, hy - 3, 1)
        socket(W, L, hx + 15, hy - 3, -1)
        for sx in (-1, 1):       # heavy brows
            flat(W, line_m(W, [(hx + sx * 25, hy - 13 + (2 if sx > 0 else 0)), (hx + sx * 7, hy - 14)], 3.2), OL)
        flat(W, poly_m(W, [(hx - 2.5, hy + 5), (hx + 2.5, hy + 5), (hx + 1, hy + 11), (hx - 1, hy + 11)]), sk_d)
        mouth(W, mx, hy + 24, 15, 11)
        bx = mx
    else:
        put(W, ell_m(W, hx, hy, R, R * 1.03), skin)
        put(W, ell_m(W, hx - 9, hy + 3, 7, 8), mulc(skin, 0.94), ow=4.5)    # the ear
        flat(W, ell_m(W, hx + 22, hy + 10, 9, 14), sk_d, 150, clip=clipm)
        socket(W, L, hx + 18, hy - 3, 1)
        flat(W, line_m(W, [(hx + 28, hy - 13), (hx + 10, hy - 14)], 3.2), OL)
        flat(W, poly_m(W, [(hx + R - 4, hy + 3), (hx + R + 2, hy + 9), (hx + R - 5, hy + 11)]), sk_d)
        mouth(W, hx + 28, hy + 24, 11, 11)
        bx = hx + 28
    if L["bruise"]:
        flat(W, ell_m(W, hx - 18, hy + 6, 12, 9), (96, 90, 132), 120, clip=clipm)
    if L["scab"]:
        flat(W, ell_m(W, hx + 15, hy - 28, 8, 6), BLOOD_D, 255, clip=clipm)
        flat(W, ell_m(W, hx + 13, hy - 29, 4, 3), BLOOD_L, 255, clip=clipm)
    # blood from the mouth runs down the chin
    flat(W, line_m(W, [(bx + 5, hy + 28), (bx + 6, hy + 42)], 6), BLOOD)
    flat(W, ell_m(W, bx + 6, hy + 46, 3.6, 5), BLOOD)
    flat(W, line_m(W, [(bx - 7, hy + 30), (bx - 7, hy + 36)], 3.4), BLOOD)
    flat(W, line_m(W, [(bx + 4, hy + 28), (bx + 4, hy + 40)], 1.6), BLOOD_L)
    hair_front(W, L, view, hx, hy, R, rng)
    return W


def socket(W, L, x, y, side):
    """A dark sunken eye hole and the eye in it: pale, dark, red, or one white blind eye."""
    kind = L["eyes"]
    put(W, ell_m(W, x, y, 11, 9.5), SOCKET, outline=False, shade=False)
    flat(W, ell_m(W, x, y + 7, 12, 3.5), (74, 66, 92), 90)       # a bruise under it
    ball = {"pale": (232, 228, 196), "dark": (214, 210, 186), "red": (214, 214, 196), "white": (240, 240, 232)}[kind]
    flat(W, ell_m(W, x, y, 6.2, 5.6), ball)
    first = side > 0
    if kind == "red" and first:
        flat(W, ell_m(W, x, y, 6.2, 5.6), (206, 40, 36))
        flat(W, ell_m(W, x - 1, y - 1, 2.4, 2.2), (255, 160, 130))
    elif kind == "white" and first:
        flat(W, ell_m(W, x, y, 6.2, 5.6), (228, 234, 228))      # clouded, no pupil
        flat(W, ell_m(W, x - 1.5, y - 1.5, 2, 1.6), (255, 255, 255))
    else:
        flat(W, ell_m(W, x - side * 0.6, y + 0.8, 2.4, 2.8), (24, 18, 18))
    flat(W, line_m(W, [(x - 9, y - 7), (x + 9, y - 7.5)], 1.8), (24, 16, 18), 190)


def mouth(W, x, y, rx, ry):
    """An open mouth with teeth, a dark throat and a tongue."""
    put(W, ell_m(W, x, y, rx, ry), (44, 12, 16), shade=False, ow=3.2)
    cl = ell_m(W, x, y, rx - 0.5, ry - 0.5)
    flat(W, ell_m(W, x, y + ry * 0.45, rx * 0.6, ry * 0.45), (122, 34, 40), clip=cl)
    n = 5 if rx > 12 else 4
    for k in range(n):
        tx = x - rx * 0.78 + (2 * rx * 0.78) * k / (n - 1)
        h = 5.2 if k % 2 == 0 else 3.8
        flat(W, poly_m(W, [(tx - 1.8, y - ry), (tx + 1.8, y - ry), (tx + 0.8, y - ry + h), (tx - 0.8, y - ry + h)]), TEETH, clip=cl)
    for k in range(3):
        tx = x - rx * 0.4 + rx * 0.4 * k
        flat(W, poly_m(W, [(tx - 1.5, y + ry), (tx + 1.5, y + ry), (tx + 0.6, y + ry - 3.4), (tx - 0.6, y + ry - 3.4)]), TEETH, clip=cl)


# ------------------------------------------------------------------ hair
def tuft_edge(rng, cx, cy, r, a0, a1, jit, n=12):
    pts = []
    for k in range(n + 1):
        a = a0 + (a1 - a0) * k / n
        rr = r + (jit * rng.uniform(0.4, 1.0) if k % 2 else -jit * rng.uniform(0, 0.4))
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return pts


def hair_back(W, L, hx, hy, R, rng):
    """The back of the head (N view): hair, a hood, or a bald scabbed scalp."""
    st, col, skin = L["hair"], L["hair_col"], L["skin"]
    base = ell_m(W, hx, hy, R, R * 1.03)
    if st in ("bald", "shave", "wisp", "balding"):
        put(W, base, skin)
        if L["scab"]:
            flat(W, ell_m(W, hx - 8, hy - 20, 12, 7), BLOOD_D, 200, clip=base)
        for k in range(5):
            a = rng.uniform(0, 6.28)
            flat(W, line_m(W, [(hx + math.cos(a) * 14, hy + math.sin(a) * 14), (hx + math.cos(a) * 24, hy + math.sin(a) * 24 + 3)], 1.6), col, 220, clip=base)
        if st == "balding":
            put(W, poly_m(W, tuft_edge(rng, hx, hy + 4, R - 2, math.radians(150), math.radians(390), 5) + [(hx, hy + 8)]), col, ow=4, clip=base)
        return
    fill = L["top"] if st == "hood" else col
    if st == "cap":
        fill = (36, 52, 84) if L["i"] in (4, 14) else mulc(L["top"], 0.8)
    if st == "long":
        put(W, capsule_m(W, (hx - 20, hy + 20), (hx - 14, hy + 56), 28, 18), fill)
        put(W, capsule_m(W, (hx + 20, hy + 20), (hx + 15, hy + 58), 26, 16), fill)
    put(W, ell_m(W, hx, hy, R + 2, R + 3), fill)
    for k in range(9):
        a = math.radians(190 + k * 20)
        flat(W, line_m(W, [(hx + math.cos(a) * 6, hy + math.sin(a) * 6 - 6), (hx + math.cos(a) * 33, hy + math.sin(a) * 31)], 1.8), mulc(fill, 1.35), 150, clip=ell_m(W, hx, hy, R, R))
    if st in ("matted", "messy", "short") and L["i"] % 2 == 0:     # a bald patch at the back
        put(W, poly_m(W, smooth_poly([(hx + 6, hy - 14), (hx + 20, hy - 12), (hx + 22, hy - 2), (hx + 10, hy)], 2)), skin, ow=2.6, shade=False)
        flat(W, line_m(W, [(hx + 9, hy - 8), (hx + 18, hy - 5)], 2), BLOOD_D)


def hair_front(W, L, view, hx, hy, R, rng):
    st, col, skin = L["hair"], L["hair_col"], L["skin"]
    if view == "N":
        return
    face = view == "S"
    clipm = ell_m(W, hx, hy, R - 1, R)
    if st == "bald":
        for k in range(3):    # a few dead strands behind each ear
            for sx in (-1, 1):
                flat(W, line_m(W, [(hx + sx * (R - 5), hy - 6 + k * 5), (hx + sx * (R + 4), hy + 3 + k * 6)], 2.2), col, 230)
        return
    if st == "shave":
        flat(W, ell_m(W, hx, hy - 22, 30, 15), mulc(skin, 0.86), 120, clip=clipm)
        return
    if st == "wisp":     # an old one: white wisps on a spotted scalp
        for k in range(7):
            a = math.radians(205 + k * 21)
            flat(W, line_m(W, [(hx + math.cos(a) * 30, hy + math.sin(a) * 30), (hx + math.cos(a) * 46 + rng.uniform(-3, 3), hy + math.sin(a) * 44 + 3)], 2.4), (220, 216, 206))
        flat(W, ell_m(W, hx + 12, hy - 24, 4, 3), mulc(skin, 0.7), 220)
        flat(W, ell_m(W, hx - 14, hy - 28, 3, 3), mulc(skin, 0.7), 220)
        return
    if st == "balding":
        for s0, s1 in ((math.radians(160), math.radians(200)), (math.radians(340), math.radians(380))):
            pts = tuft_edge(rng, hx, hy + 2, R + 1, s0, s1, 3, 6) + [(hx + math.cos(s1) * (R - 18), hy + 3 + math.sin(s1) * (R - 18)), (hx + math.cos(s0) * (R - 18), hy + 3 + math.sin(s0) * (R - 18))]
            put(W, poly_m(W, pts), col, ow=4)
        put(W, poly_m(W, tuft_edge(rng, hx, hy - 30, 8, math.radians(180), math.radians(360), 4, 8) + [(hx, hy - 28)]), col, ow=3)
        return
    cap_top = hy - (13 if face else 11)
    if st in ("cap", "hood"):
        fill = mulc(L["top"], 0.92) if st == "hood" else ((36, 52, 84) if L["i"] in (4, 14) else mulc(L["top"], 0.8))
        edge = [(hx - R - 3, cap_top + 6)] + [(hx - R + 2 + k * (2 * R - 4) / 10, cap_top + (3 if k % 2 else 0)) for k in range(11)] + [(hx + R + 3, cap_top + 6), (hx + R + 3, hy - R - 8), (hx - R - 3, hy - R - 8)]
        put(W, ImageChops.multiply(poly_m(W, edge), ell_m(W, hx, hy, R + 3, R + 4)), fill)
        if st == "cap":
            flat(W, ell_m(W, hx, hy - 33, 4, 4), (200, 170, 70))
            if face:
                put(W, poly_m(W, [(hx - 30, cap_top + 2), (hx + 30, cap_top + 2), (hx + 26, cap_top + 9), (hx - 26, cap_top + 9)]), mulc(fill, 0.7), ow=3.5)
        elif face:
            put(W, capsule_m(W, (hx - R + 3, cap_top + 8), (hx - R + 1, hy + 24), 15), fill)
            put(W, capsule_m(W, (hx + R - 3, cap_top + 8), (hx + R - 1, hy + 24), 15), fill)
        return
    depth = {"matted": 0, "messy": -2, "short": 3, "long": 0, "bun": 2}.get(st, 0)
    ypts = [(hx - R - 3, cap_top + depth + 10)]
    n = 12
    for k in range(n + 1):
        x = hx - R + (2 * R) * k / n
        y = cap_top + depth + (rng.uniform(3, 6) if k % 2 else rng.uniform(0, 2)) + (8 if k in (0, n) else 0) + (3 if face and 3 < k < 9 else 0)
        ypts.append((x, y))
    ypts += [(hx + R + 3, cap_top + depth + 10), (hx + R + 3, hy - R - 8), (hx - R - 3, hy - R - 8)]
    m = round_m(ImageChops.multiply(poly_m(W, ypts), ell_m(W, hx, hy, R + 3, R + 4)), 1.6)
    if st == "long":
        for sx in (-1, 1):
            put(W, capsule_m(W, (hx + sx * (R - 4), hy - 14), (hx + sx * (R - 1), hy + 38 + sx * 5), 18, 12), col)
    put(W, m, col)
    if st == "bun":
        put(W, ell_m(W, hx, hy - R - 4, 15, 12), (214, 210, 200))
    for k in range(5):     # greasy strands
        a = math.radians(215 + k * 24)
        flat(W, line_m(W, [(hx + math.cos(a) * 10, hy - 36 + math.sin(a) * 4), (hx + math.cos(a) * 34, hy + math.sin(a) * 26 - 2)], 1.6), mulc(col, 0.7), 150, clip=m)
    if st in ("matted", "messy") or L["i"] % 3 == 1:     # a bald spot with a scab
        sx = hx + (14 if L["i"] % 2 else -15)
        put(W, ell_m(W, sx, cap_top - 6, 9, 7), skin, ow=3.2, clip=ell_m(W, hx, hy, R, R))
        flat(W, ell_m(W, sx + 1, cap_top - 6, 4, 3), BLOOD_D)


# ------------------------------------------------------------------ the body
def body(L, view, ls, rs, rng):
    """The torso layer: the hunched shoulders (one lower), a torn hem, the outfit's parts and the wounds."""
    W = Win(96, 96, 176, 184)
    if view == "E":
        upper = [(CX - 30, 252), (CX - 40, 224), (CX - 40, 196 + ls), (CX - 24, 175), (CX + 6, 172), (CX + 32, 190), (CX + 38, 214), (CX + 32, 252)]
        x0, x1 = CX - 30, CX + 32
    else:
        upper = [(CX - 50, 252), (CX - 57, 226), (CX - 60, 200 + ls), (CX - 46, 182 + ls), (CX - 26, 174), (CX + 26, 174), (CX + 46, 182 + rs), (CX + 60, 200 + rs), (CX + 57, 226), (CX + 50, 252)]
        x0, x1 = CX - 50, CX + 50
    ragged = jag(rng, x0, x1, 252, 5 + 11 * L["torn"], 8)
    m = round_m(poly_m(W, upper + ragged[::-1]), 2.2)
    put(W, m, L["top"])
    outfit(W, L, view, m, ls, rs)
    return W, m


def outfit(W, L, view, m, ls, rs):
    sty, top, outer = L["style"], L["top"], L["outer"]
    dark = mulc(top, 0.62)
    k = random.Random(L["i"] * 13 + 5)
    if L["pattern"] is not None and sty == "shirt":
        for x in range(CX - 70, CX + 72, 11):
            flat(W, line_m(W, [(x, 172), (x, 256)], 4), L["pattern"], 150, clip=m)
        for y in range(176, 260, 12):
            flat(W, line_m(W, [(CX - 72, y), (CX + 72, y)], 4), L["pattern"], 150, clip=m)
    if view == "N":
        flat(W, line_m(W, [(CX, 176), (CX, 250)], 2.4), dark, 220, clip=m)
        flat(W, line_m(W, [(CX - 28, 188), (CX + 28, 188)], 2.4), dark, 160, clip=m)
        if sty == "gown":     # open at the back: the ties, and skin
            flat(W, poly_m(W, [(CX - 10, 182), (CX + 10, 182), (CX + 12, 252), (CX - 12, 252)]), mulc(L["skin"], 0.94), clip=m)
            flat(W, line_m(W, [(CX - 10, 196), (CX + 10, 204)], 2.2), (214, 212, 196))
        if sty == "hoodie":
            put(W, ell_m(W, CX, 186, 40, 17), mulc(top, 0.9))
        if L["hivis"]:
            flat(W, poly_m(W, [(CX - 70, 180), (CX + 70, 180), (CX + 70, 250), (CX - 70, 250)]), outer, clip=m)
            for y in (214, 236):
                flat(W, poly_m(W, [(CX - 62, y), (CX + 62, y), (CX + 62, y + 7), (CX - 62, y + 7)]), (210, 212, 206), clip=m)
        elif outer is not None and L["job"] != "cook":
            flat(W, poly_m(W, [(CX - 70, 180), (CX + 70, 180), (CX + 70, 250), (CX - 70, 250)]), outer, clip=m)
        if L["job"] == "cook":
            put(W, poly_m(W, [(CX - 30, 186), (CX + 30, 186), (CX + 44, 252), (CX - 44, 252)]), outer, ow=4, clip=m)
            flat(W, line_m(W, [(CX - 30, 186), (CX + 30, 230)], 2.4), (170, 166, 150), 255)
        flat(W, ell_m(W, CX + k.randint(-24, 24), 214, 14, 20), BLOOD_D, 170, clip=m)
        flat(W, ell_m(W, CX + k.randint(-24, 24), 232, 9, 12), BLOOD, 190, clip=m)
        if L["bite"]:
            torn_bite(W, CX + (-46 if L["bite"] == "L" else 46), 202, m)
        return
    if sty == "shirt" and L["tie"] is not None:
        put(W, poly_m(W, [(CX - 18, 174), (CX, 190), (CX + 18, 174), (CX + 10, 168), (CX - 10, 168)]), mulc(top, 1.05), ow=3.5)
        flat(W, poly_m(W, [(CX - 5, 188), (CX + 5, 188), (CX + 8, 234), (CX, 242), (CX - 8, 234)]), L["tie"], clip=m)
        flat(W, poly_m(W, [(CX - 5, 188), (CX - 1, 188), (CX - 2, 236), (CX - 7, 232)]), mulc(L["tie"], 1.3), clip=m)
    elif sty == "shirt":
        flat(W, poly_m(W, [(CX - 16, 172), (CX, 196), (CX + 16, 172)]), mulc(L["skin"], 0.9), clip=m)
        flat(W, line_m(W, [(CX, 196), (CX + 2, 252)], 2.4), dark, 255, clip=m)
        for yy in (212, 228, 244):
            flat(W, ell_m(W, CX + 4, yy, 2.4, 2.4), (214, 208, 190), 255, clip=m)
    elif sty == "hoodie":
        put(W, ell_m(W, CX, 177, 38, 15), mulc(top, 0.86), ow=4)
        put(W, poly_m(W, [(CX - 30, 228), (CX + 30, 228), (CX + 36, 250), (CX - 36, 250)]), mulc(top, 0.86), ow=3.5, clip=m)
        flat(W, line_m(W, [(CX - 11, 188), (CX - 13, 214)], 2.6), (214, 208, 196))
        flat(W, line_m(W, [(CX + 11, 188), (CX + 14, 212)], 2.6), (214, 208, 196))
    elif sty == "uniform":
        put(W, poly_m(W, [(CX - 22, 172), (CX, 192), (CX + 22, 172), (CX + 14, 166), (CX - 14, 166)]), mulc(top, 1.25), ow=3.5)
        flat(W, line_m(W, [(CX, 192), (CX + 1, 252)], 2.6), mulc(top, 0.55), 255, clip=m)
        flat(W, poly_m(W, [(CX + 18, 204), (CX + 36, 204), (CX + 36, 224), (CX + 27, 231), (CX + 18, 224)]), (206, 176, 76), clip=m)
        for sx in (-1, 1):
            flat(W, poly_m(W, [(CX + sx * 60, 190), (CX + sx * 36, 180), (CX + sx * 36, 187), (CX + sx * 60, 198)]), (214, 190, 90), 255, clip=m)
    elif sty == "gown":
        put(W, poly_m(W, [(CX - 22, 172), (CX, 200), (CX + 22, 172), (CX + 12, 166), (CX - 12, 166)]), mulc(top, 1.14), ow=3.5)
        for q in range(4):
            flat(W, line_m(W, [(CX - 56 + q * 38, 206), (CX - 52 + q * 38, 250)], 2), mulc(top, 0.8), 140, clip=m)
        flat(W, ell_m(W, CX + 30, 232, 11, 8), (178, 148, 90), 130, clip=m)
    elif sty == "scrubs":
        put(W, poly_m(W, [(CX - 24, 172), (CX, 204), (CX + 24, 172), (CX + 12, 166), (CX - 12, 166)]), mulc(L["skin"], 0.95), ow=3.5)
        put(W, poly_m(W, [(CX - 24, 172), (CX, 204), (CX - 2, 206), (CX - 30, 176)]), mulc(top, 1.15), ow=3.2)
        put(W, poly_m(W, [(CX + 24, 172), (CX, 204), (CX + 2, 206), (CX + 30, 176)]), mulc(top, 1.15), ow=3.2)
        flat(W, poly_m(W, [(CX + 20, 216), (CX + 46, 216), (CX + 46, 242), (CX + 20, 242)]), mulc(top, 0.8), clip=m)
        flat(W, poly_m(W, [(CX - 52, 202), (CX - 36, 202), (CX - 36, 218), (CX - 52, 218)]), (226, 222, 214), clip=m)
        flat(W, poly_m(W, [(CX - 46, 205), (CX - 42, 205), (CX - 42, 215), (CX - 46, 215)]), (176, 40, 36), clip=m)
        flat(W, poly_m(W, [(CX - 50, 208), (CX - 38, 208), (CX - 38, 212), (CX - 50, 212)]), (176, 40, 36), clip=m)
    elif sty == "coverall":
        put(W, poly_m(W, [(CX - 22, 172), (CX, 194), (CX + 22, 172), (CX + 12, 166), (CX - 12, 166)]), mulc(top, 1.3), ow=3.5)
        flat(W, line_m(W, [(CX, 194), (CX, 252)], 3), mulc(top, 0.55), 255, clip=m)
        flat(W, ell_m(W, CX - 28, 236, 14, 8), (30, 28, 30), 190, clip=m)
        flat(W, ell_m(W, CX + 36, 214, 10, 7), (30, 28, 30), 150, clip=m)
        flat(W, poly_m(W, [(CX + 18, 214), (CX + 42, 214), (CX + 42, 234), (CX + 18, 234)]), mulc(top, 0.8), 255, clip=m)
    elif sty == "tee":
        flat(W, ell_m(W, CX, 170, 20, 14), mulc(L["skin"], 0.9), clip=m)       # a ragged round neck
        if L["job"] == "cook":
            put(W, poly_m(W, [(CX - 30, 186), (CX + 30, 186), (CX + 44, 252), (CX - 44, 252)]), outer, ow=4, clip=m)
            flat(W, ell_m(W, CX - 12, 232, 11, 8), (152, 40, 36), 230, clip=m)
            flat(W, ell_m(W, CX + 16, 214, 7, 5), (176, 150, 80), 170, clip=m)
        elif L["hivis"]:
            for sx in (-1, 1):
                put(W, poly_m(W, [(CX + sx * 62, 190), (CX + sx * 20, 176), (CX + sx * 12, 252), (CX + sx * 56, 252)]), outer, ow=4, clip=m)
                for y in (214, 236):
                    flat(W, poly_m(W, [(CX + sx * 56, y), (CX + sx * 13, y), (CX + sx * 13, y + 7), (CX + sx * 56, y + 7)]), (210, 212, 206), 255, clip=m)
        elif outer is not None:      # an open jacket
            for sx in (-1, 1):
                put(W, poly_m(W, [(CX + sx * 64, 188), (CX + sx * 22, 172), (CX + sx * 14, 252), (CX + sx * 58, 252)]), outer, ow=4, clip=m)
            flat(W, line_m(W, [(CX - 20, 176), (CX - 14, 250)], 2.6), mulc(outer, 0.6), 255, clip=m)
    # damage
    rb = L["blood"]
    if L["ribs"]:
        for yy in (206, 217, 228):
            flat(W, ell_m(W, CX + 6, yy - 1, 24, 6), BLOOD_D, 255, clip=m)
            flat(W, line_m(W, [(CX - 17, yy), (CX + 30, yy - 2)], 3.4), BONE, 255, clip=m)
        flat(W, line_m(W, [(CX + 5, 200), (CX + 7, 238)], 3.6), mulc(BONE, 0.88), 255, clip=m)
    flat(W, poly_m(W, [(CX - 10, 190), (CX + 14, 190), (CX + 22, 214), (CX + 12, 240), (CX - 4, 232), (CX - 16, 214)]), BLOOD, int(130 + 90 * rb), clip=m)
    flat(W, ell_m(W, CX - 4, 214, 11, 14), BLOOD_D, 160, clip=m)
    for dx in (-8, 2, 10):
        flat(W, line_m(W, [(CX + dx, 230), (CX + dx + 1, 238 + k.randint(0, 12))], 3), BLOOD, 230, clip=m)
    if L["bite"]:
        sx = -1 if L["bite"] == "L" else 1
        torn_bite(W, CX + sx * 46, 198 + (ls if sx < 0 else rs), m)


def torn_bite(W, x, y, m):
    """A bite taken out of the shoulder: a dark ragged hole, teeth marks, a red rim."""
    pts = smooth_poly([(x - 15, y + 2), (x - 8, y - 9), (x + 2, y - 6), (x + 14, y - 10), (x + 16, y + 4), (x + 6, y + 11), (x - 6, y + 9)], 1)
    flat(W, poly_m(W, pts), BLOOD, 255, clip=m)
    flat(W, ell_m(W, x, y + 1, 9, 6), BLOOD_D, 255, clip=m)
    flat(W, line_m(W, [(x - 4, y - 2), (x + 3, y + 3)], 2.2), (190, 84, 76), 255, clip=m)


# ------------------------------------------------------------------ arms
def sleeve_col(L):
    if L["outer"] is not None and L["job"] != "cook" and not L["hivis"]:
        return L["outer"]
    return L["top"]


def arm(W, L, sh, hand, rng, gone=False, wid=26):
    """One arm from the shoulder to the hand: a sleeve torn at the elbow, a bare grey forearm and a clawed hand with dried blood. `gone`: a bloody stump with bone."""
    sc = sleeve_col(L)
    skin = L["skin"]
    f = 0.5 if L["torn"] > 0.4 else 0.82
    cut = (sh[0] + (hand[0] - sh[0]) * f, sh[1] + (hand[1] - sh[1]) * f)
    if gone:
        cut = (sh[0] + (hand[0] - sh[0]) * 0.5, sh[1] + (hand[1] - sh[1]) * 0.5)
        put(W, capsule_m(W, sh, cut, wid, wid - 4), sc)
        ang = math.atan2(cut[1] - sh[1], cut[0] - sh[0])
        c, s = math.cos(ang), math.sin(ang)
        flat(W, ell_m(W, cut[0], cut[1], wid / 2 - 1, wid / 2 - 1), BLOOD)
        flat(W, ell_m(W, cut[0] + c * 1.5, cut[1] + s * 1.5, 6, 6), BLOOD_D)
        flat(W, ell_m(W, cut[0] + c * 2, cut[1] + s * 2, 2.6, 2.6), BONE)
        for q in range(3):
            flat(W, line_m(W, [(cut[0], cut[1]), (cut[0] + c * 4 + (q - 1) * 5, cut[1] + s * 8 + 6)], 2.6), BLOOD)
        return
    fa = capsule_m(W, cut, hand, wid * 0.62, wid * 0.52)
    put(W, fa, skin, ow=4.6)
    flat(W, capsule_m(W, cut, hand, 5, 5), BLOOD_D, 110, clip=fa)
    hx, hy = hand
    ang = math.atan2(hand[1] - cut[1], hand[0] - cut[0])
    put(W, ell_m(W, hx, hy, 11.5, 10.5), skin, ow=4.6)
    for q in range(3):
        a = ang + math.radians(-36 + q * 36)
        tip = (hx + math.cos(a) * 17, hy + math.sin(a) * 16)
        put(W, capsule_m(W, (hx + math.cos(a) * 6, hy + math.sin(a) * 5), tip, 8.4, 6.6), skin, ow=3.4, shade=False)
        flat(W, ell_m(W, tip[0], tip[1], 3, 3), BLOOD, 235)
    flat(W, ell_m(W, hx, hy + 1, 8, 7), BLOOD_D, 150 + int(70 * L["blood"]))
    sm = capsule_m(W, sh, cut, wid, wid * 0.88)
    put(W, sm, sc)
    ang2 = math.atan2(cut[1] - sh[1], cut[0] - sh[0])
    c, s = math.cos(ang2), math.sin(ang2)
    if L["pattern"] is not None and L["style"] == "shirt":
        for t in (0.25, 0.5, 0.75):
            q = (sh[0] + (cut[0] - sh[0]) * t, sh[1] + (cut[1] - sh[1]) * t)
            flat(W, line_m(W, [(q[0] - 11, q[1]), (q[0] + 11, q[1])], 4), L["pattern"], 150, clip=sm)
    flat(W, ell_m(W, cut[0] - c * 4, cut[1] - s * 4, 7, 6), BLOOD, 210, clip=sm)


# ------------------------------------------------------------------ the figure
def figure(L, view):
    rng = random.Random(L["i"] * 101 + ord(view))
    tilt = L["tilt"]
    ls, rs = (16, 0) if tilt < 0 else (0, 16)     # the side the head drops to has the higher shoulder
    if view == "E":
        ls = 4
    bw, bm = body(L, view, ls, rs, rng)
    arms = Win(96, 96, 176, 184)
    if view == "S":
        arm(arms, L, (CX - 50, 198 + ls), (CX - 56 - 3 * (tilt > 0), 250 + (4 if tilt > 0 else 0)), rng, L["arm_gone"] == "L", 24)
        arm(arms, L, (CX + 50, 198 + rs), (CX + 56 + 3 * (tilt < 0), 250 + (4 if tilt < 0 else 0)), rng, L["arm_gone"] == "R", 24)
        order = [bw, arms]
    elif view == "E":
        far = Win(96, 96, 176, 184)
        arm(far, L, (CX + 12, 194), (CX + 66, 226), rng, False, 22)
        shade = Image.new("RGBA", far.img.size, (0, 0, 0, 0))
        far.img = Image.composite(Image.new("RGBA", far.img.size, (30, 30, 30, 255)), far.img, far.img.getchannel("A").point(lambda v: 70 if v > 0 else 0))
        arm(arms, L, (CX - 4, 198), (CX + 60, 214), rng, L["arm_gone"] == "R")
        order = [far, bw, arms]
    else:
        arm(arms, L, (CX - 48, 198 + ls), (CX - 62, 246), rng, L["arm_gone"] == "L")
        arm(arms, L, (CX + 48, 198 + rs), (CX + 62, 246), rng, L["arm_gone"] == "R")
        order = [arms, bw]
    canvas = Image.new("RGBA", (CW * SS, CH * SS), (0, 0, 0, 0))
    hx = CX + (tilt * 70 if view == "S" else (20 + tilt * 30) if view == "E" else tilt * 60)
    hy = 152 if view != "N" else 164
    hw = head(L, view, hx, hy)
    ang = -tilt * 70 if view != "E" else 7 - tilt * 30
    himg = hw.img.rotate(ang, resample=Image.BICUBIC, center=((hx - hw.x0) * SS, (hy + 30 - hw.y0) * SS))
    if view == "N":     # seen from behind the head is low: the back hides its lower part
        canvas.alpha_composite(himg, (hw.x0 * SS, hw.y0 * SS))
    for w in order:
        canvas.alpha_composite(w.img, (w.x0 * SS, w.y0 * SS))
    if view != "N":
        canvas.alpha_composite(himg, (hw.x0 * SS, hw.y0 * SS))
    return canvas.resize((CW, CH), Image.LANCZOS)


# ------------------------------------------------------------------ corpses
def corpse(L, pose):
    """A body lying over a pool of blood (the pivot is 184,227): pose 0 on its back, 1 face down, 2 curled on its side. Head to the left, feet to the right (the game mirrors it)."""
    rng = random.Random(L["i"] * 977 + pose)
    W = Win(30, 120, 308, 196)
    cy = 224
    skin, pants = L["skin"], L["pants"]
    sc = sleeve_col(L)
    pool = []
    for q in range(18):
        a = q / 18 * 2 * math.pi
        pool.append((CX + math.cos(a) * (100 + rng.uniform(-14, 14)) - 4, cy + 6 + math.sin(a) * (48 + rng.uniform(-8, 8))))
    pm = round_m(poly_m(W, smooth_poly(pool, 2)), 3)
    flat(W, pm, BLOOD_D, 235)
    flat(W, ell_m(W, CX - 34, cy - 12, 22, 7), BLOOD_L, 110, clip=pm)
    shoe = (34, 28, 26)
    if pose == 2:
        put(W, capsule_m(W, (CX + 20, cy + 8), (CX + 80, cy - 14), 26, 22), pants)
        put(W, capsule_m(W, (CX + 80, cy - 14), (CX + 58, cy + 28), 22, 20), pants)
        put(W, capsule_m(W, (CX + 20, cy + 22), (CX + 78, cy + 20), 26, 22), mulc(pants, 0.88))
        put(W, capsule_m(W, (CX + 78, cy + 20), (CX + 50, cy + 44), 22, 20), mulc(pants, 0.88))
        put(W, ell_m(W, CX + 56, cy + 32, 9, 9), shoe, ow=4)
        put(W, ell_m(W, CX + 50, cy + 48, 9, 8), shoe, ow=4)
    else:
        put(W, capsule_m(W, (CX + 20, cy - 10), (CX + 112, cy - 24), 27, 22), pants)
        put(W, capsule_m(W, (CX + 20, cy + 16), (CX + 100, cy + 26 + pose * 4), 27, 22), mulc(pants, 0.88))
        put(W, ell_m(W, CX + 120, cy - 26, 12, 8), shoe, ow=4)
        put(W, ell_m(W, CX + 108, cy + 30 + pose * 4, 12, 8), shoe, ow=4)
    tp = smooth_poly([(CX - 30, cy - 36), (CX + 28, cy - 38), (CX + 36, cy - 8), (CX + 30, cy + 34), (CX - 28, cy + 36), (CX - 38, cy)], 2)
    tm = poly_m(W, tp)
    col = L["top"] if pose != 1 or L["outer"] is None or L["job"] == "cook" else L["outer"]
    put(W, tm, col)
    if L["pattern"] is not None and L["style"] == "shirt":
        for x in range(CX - 40, CX + 42, 11):
            flat(W, line_m(W, [(x, cy - 40), (x, cy + 40)], 4), L["pattern"], 150, clip=tm)
    if L["style"] == "gown" and pose == 1:
        flat(W, poly_m(W, [(CX - 20, cy - 34), (CX + 14, cy - 34), (CX + 14, cy + 34), (CX - 20, cy + 34)]), mulc(skin, 0.95), clip=tm)
    flat(W, ell_m(W, CX - 4, cy + 4, 18, 16), BLOOD_D, 210, clip=tm)
    flat(W, ell_m(W, CX + 6, cy + 10, 9, 8), BLOOD, 220, clip=tm)
    if L["ribs"] and pose == 0:
        for q in range(3):
            flat(W, line_m(W, [(CX - 12, cy - 12 + q * 10), (CX + 18, cy - 14 + q * 10)], 3.2), BONE, 255, clip=tm)
    ax = [(CX - 6, cy - 34, CX - 70, cy - 66), (CX - 4, cy + 34, CX - 60, cy + 64)]
    if pose == 1:
        ax = [(CX - 6, cy - 34, CX - 100, cy - 48), (CX - 4, cy + 34, CX - 102, cy + 46)]
    if pose == 2:
        ax = [(CX - 6, cy - 34, CX - 60, cy - 14), (CX - 4, cy + 30, CX - 56, cy + 22)]
    for q, (x0, y0, x1, y1) in enumerate(ax):
        if (L["arm_gone"] == "L" and q == 0) or (L["arm_gone"] == "R" and q == 1):
            ex, ey = x0 + (x1 - x0) * 0.35, y0 + (y1 - y0) * 0.35
            put(W, capsule_m(W, (x0, y0), (ex, ey), 24, 22), sc)
            flat(W, ell_m(W, ex, ey, 9, 9), BLOOD)
            flat(W, ell_m(W, ex, ey, 3, 3), BONE)
            continue
        mx, my = x0 + (x1 - x0) * 0.5, y0 + (y1 - y0) * 0.5
        put(W, capsule_m(W, (mx, my), (x1, y1), 14, 12), skin, ow=4.4)
        put(W, ell_m(W, x1, y1, 9.5, 9), skin, ow=4.4)
        flat(W, ell_m(W, x1, y1, 6, 5), BLOOD_D, 160)
        put(W, capsule_m(W, (x0, y0), (mx, my), 24, 20), sc)
    hv = "N" if pose == 1 else "S"
    hw = head(L, hv, 184, 150)
    hang = {0: 90, 1: 80, 2: 40}[pose]
    himg = hw.img.rotate(hang, resample=Image.BICUBIC, center=((184 - hw.x0) * SS, (150 - hw.y0) * SS))
    target = (CX - 76, cy + (8 if pose == 2 else 0))
    canvas = Image.new("RGBA", (CW * SS, CH * SS), (0, 0, 0, 0))
    canvas.alpha_composite(W.img, (W.x0 * SS, W.y0 * SS))
    canvas.alpha_composite(himg, (int((target[0] - (184 - hw.x0)) * SS), int((target[1] - (150 - hw.y0)) * SS)))
    return canvas.resize((CW, CH), Image.LANCZOS)


# ------------------------------------------------------------------ driver
def contact_sheet(path, looks, scale=2, per_row=0):
    names = ["ruth", "walt", "ana"]
    box = (104, 84, 264, 276)
    bw, bh = box[2] - box[0], box[3] - box[1]
    cols = len(looks) + len(names)
    sheet = Image.new("RGBA", (cols * bw * scale, 3 * bh * scale), (70, 80, 62, 255))
    for j, v in enumerate("SEN"):
        for c in range(cols):
            p = os.path.join(PAWNS, "%s_%s.png" % (names[c], v)) if c < len(names) else os.path.join(PAWNS, "zr%d_%s.png" % (looks[c - len(names)]["i"], v))
            if os.path.exists(p):
                im = Image.open(p).convert("RGBA").crop(box).resize((bw * scale, bh * scale), Image.NEAREST)
                sheet.alpha_composite(im, (c * bw * scale, j * bh * scale))
    sheet.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--look", type=int, default=-1)
    ap.add_argument("--sheet", default="")
    ap.add_argument("--out", default=PAWNS)
    ap.add_argument("--views", default="SEN")
    ap.add_argument("--corpses", action="store_true")
    a = ap.parse_args()
    looks = load_looks()
    sel = [l for l in looks if a.look < 0 or l["i"] == a.look]
    for L in sel:
        for v in a.views:
            figure(L, v).save(os.path.join(a.out, "zr%d_%s.png" % (L["i"], v)))
        if a.corpses or a.look < 0:
            for pose in range(3):
                corpse(L, pose).save(os.path.join(a.out, "zrc%d_%d.png" % (L["i"], pose)))
    if a.sheet:
        contact_sheet(a.sheet, sel)


if __name__ == "__main__":
    main()
