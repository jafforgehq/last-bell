#!/usr/bin/env python3
"""Draws the inventory's pictures (INV2): one PNG atlas of the items, the weapon and the melee swing, the quick slots' frames, the pack's badge and Ruth's outline,
and the table of where each one sits. Written with PIL and numpy only (no paid tool, no image API), the way the older art scripts of tools/ are.

    python3 tools/make_item_icons.py                      # writes assets/ui/inv/inv_icons.png and inv_icons.json
    python3 tools/make_item_icons.py --sheet /tmp/s.png   # and a contact sheet of every icon at 128, 72, 48 and 32 px (to be looked at)
then import them once: Godot --headless --path . --import

THE STYLE (the game's own: flat, outlined, desaturated): a dark outline, one flat colour for each part with a little worn texture in it, a pale edge along the top of every part and a darker one
along its foot, and a soft shadow under the whole picture. Every picture is drawn at four times its size and averaged down (clean edges), at 128 px for each cell of the item's footprint
(a bottle is 128 x 128, a ration pack 128 x 256, a jug 256 x 256, a medkit 256 x 128): the game shows a cell at 32 to 36 points, 72 at most, so each is readable at 32 and told from the others by SHAPE as well as colour
(a red tube on a brass base, a tin with a label, a green wrapped pack, a bottle with a cap, a round roll, a white case with a cross, a box). The windows draw them with mipmaps.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "ui", "inv")
SS = 4          # supersampling
U = 128         # pixels of one inventory cell
GUTTER = 12     # transparent pixels between two pictures in the atlas (mipmaps would blend neighbours otherwise)

OUTLINE = (13, 24, 20)
RED = (176, 66, 58)
RED_D = (128, 44, 40)
BRASS = (208, 168, 84)
BRASS_D = (150, 112, 50)
BRASS_L = (232, 200, 120)
TIN = (166, 174, 168)
TIN_L = (206, 212, 206)
TIN_D = (112, 120, 116)
ORANGE = (204, 122, 58)
ORANGE_D = (160, 88, 40)
CREAM = (234, 226, 204)
CREAM_D = (196, 186, 158)
OLIVE = (112, 126, 72)
OLIVE_D = (74, 88, 46)
BLUE = (84, 148, 192)
BLUE_D = (50, 104, 146)
BLUE_PALE = (204, 228, 240)
WHITE = (238, 234, 222)
GREY = (124, 132, 126)
STEEL = (92, 102, 98)
STEEL_D = (56, 64, 60)
WOOD = (140, 98, 56)
WOOD_D = (94, 62, 34)
PAPER = (208, 172, 108)
PAPER_D = (170, 134, 78)
CROSS = (192, 62, 54)
DARK = (22, 36, 31)
ACCENT = (240, 194, 74)


# ------------------------------------------------------------------------------ the canvas --

class Cv:
    """A picture drawn at SS times its size: shapes are painted over each other (an outline, then a flat colour with a pale top edge and a darker foot), and `finish` averages it down."""

    def __init__(self, w, h, seed=1):
        self.w, self.h = int(w), int(h)
        self.W, self.H = self.w * SS, self.h * SS
        self.P = np.zeros((self.H, self.W, 3), np.float32)    # premultiplied colour
        self.A = np.zeros((self.H, self.W), np.float32)
        self.rng = np.random.RandomState(seed)
        self.xf = None
        o1 = self._up(self.rng.randn(max(self.h // 2, 2), max(self.w // 2, 2)))
        o2 = self._up(self.rng.randn(max(self.h // 9, 2) + 1, max(self.w // 9, 2) + 1))
        self.noise = 0.65 * o1 / o1.std() + 0.35 * o2 / o2.std()

    def _up(self, a):
        im = Image.fromarray(a.astype(np.float32)).resize((self.W, self.H), Image.BICUBIC)
        return np.asarray(im, np.float32)

    # -- placing: a group of shapes drawn around a pivot, turned, scaled and put somewhere
    class _Group:
        def __init__(self, cv, rot, pivot, scale, to):
            self.cv, self.rot, self.pivot, self.scale, self.to = cv, math.radians(rot), pivot, scale, to
            self.prev = None

        def __enter__(self):
            self.prev = self.cv.xf
            c, s = math.cos(self.rot), math.sin(self.rot)
            px, py = self.pivot
            tx, ty = self.to if self.to is not None else self.pivot
            sc = self.scale
            old = self.prev

            def f(p):
                if old is not None:
                    p = old(p)
                x, y = (p[0] - px) * sc, (p[1] - py) * sc
                return (tx + x * c - y * s, ty + x * s + y * c)
            self.cv.xf = f

        def __exit__(self, *a):
            self.cv.xf = self.prev

    def group(self, rot=0.0, pivot=(64, 64), scale=1.0, to=None):
        return Cv._Group(self, rot, pivot, scale, to)

    def _pts(self, pts):
        out = []
        for p in pts:
            q = self.xf(p) if self.xf else p
            out.append((q[0] * SS, q[1] * SS))
        return out

    def _blank(self):
        return Image.new("L", (self.W, self.H), 0)

    # -- masks
    def _poly_masks(self, pts, ow):
        P = self._pts(pts)
        fill = self._blank()
        ImageDraw.Draw(fill).polygon(P, fill=255)
        band = self._blank()
        if ow > 0:
            ImageDraw.Draw(band).line(P + [P[0]], fill=255, width=max(1, int(round(ow * SS * (self._scale() if True else 1)))), joint="curve")
        return ImageChops.lighter(fill, band), ImageChops.subtract(fill, band)

    def _scale(self):
        if self.xf is None:
            return 1.0
        a, b = self.xf((0.0, 0.0)), self.xf((1.0, 0.0))
        return math.hypot(b[0] - a[0], b[1] - a[1])

    def _stroke_masks(self, path, w, ow, caps=True):
        P = self._pts(path)
        sc = self._scale()
        outer, inner = self._blank(), self._blank()
        for im, ww in ((outer, w + ow), (inner, w)):
            d = ImageDraw.Draw(im)
            width = max(1, int(round(ww * sc * SS)))
            d.line(P, fill=255, width=width, joint="curve")
            if caps:
                r = width / 2.0
                for (x, y) in (P[0], P[-1]):
                    d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        return outer, inner

    # -- painting
    def _comp(self, m, col):
        m3 = m[..., None]
        self.P = col * m3 + self.P * (1.0 - m3) if np.ndim(col) == 3 else np.asarray(col, np.float32) * m3 + self.P * (1.0 - m3)
        self.A = m + self.A * (1.0 - m)

    def _soft(self, a, radius):
        im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius * SS))
        return np.asarray(im, np.float32) / 255.0

    def paint(self, outer, inner, color, tex=0.05, hi=0.30, lo=0.15, ocol=OUTLINE, alpha=1.0, hb=5.0):
        o = np.asarray(outer, np.float32) / 255.0
        it = np.asarray(inner, np.float32) / 255.0
        if ocol is not None:
            self._comp(o * alpha, np.asarray(ocol, np.float32))
        col = np.empty((self.H, self.W, 3), np.float32)
        col[:] = np.asarray(color, np.float32)
        if tex > 0:
            col *= (1.0 + tex * self.noise)[..., None]
        n = max(1, int(hb * self._scale() * SS))
        if hi > 0:
            up = np.zeros_like(it)
            up[n:] = it[:-n]
            band = self._soft(np.clip(it - up, 0, 1), 0.9)
            col += (255.0 - col) * (hi * band * (it > 0.5))[..., None]
        if lo > 0:
            dn = np.zeros_like(it)
            dn[:-n] = it[n:]
            band = self._soft(np.clip(it - dn, 0, 1), 0.9)
            col *= (1.0 - lo * band * (it > 0.5))[..., None]
        self._comp(it * alpha, np.clip(col, 0, 255))

    # -- the shapes
    def poly(self, pts, color, ow=4.0, **kw):
        o, i = self._poly_masks(pts, ow)
        if ow <= 0:
            kw["ocol"] = None
        self.paint(o, i, color, **kw)

    def rrect(self, x0, y0, x1, y1, r, color, ow=4.0, **kw):
        self.poly(rrect_pts(x0, y0, x1, y1, r), color, ow, **kw)

    def ell(self, cx, cy, rx, ry, color, ow=4.0, **kw):
        self.poly(ell_pts(cx, cy, rx, ry), color, ow, **kw)

    def stroke(self, path, w, color, ow=3.0, caps=True, **kw):
        o, i = self._stroke_masks(path, w, ow, caps)
        if ow <= 0:
            kw["ocol"] = None
        self.paint(o, i, color, **kw)

    def detail(self, path, w, color=(255, 255, 255), alpha=0.3):
        """A thin line with no outline and no shading: a crease, a gloss, a letter's stroke."""
        self.stroke(path, w, color, ow=0, hi=0, lo=0, tex=0, alpha=alpha)

    def patch(self, pts, color, alpha=0.3):
        self.poly(pts, color, ow=0, hi=0, lo=0, tex=0, alpha=alpha)

    # -- the end: wear, a shadow, the averaging down
    def finish(self, shadow=(2.0, 4.0), blur=3.0, strength=0.42, wear=True):
        art = (self.A > 0.9).astype(np.float32)
        if wear:
            n = max(6, int(self.w * self.h / 1400))
            sc = self._blank()
            d = ImageDraw.Draw(sc)
            for _ in range(n):
                x, y = self.rng.uniform(8, self.w - 8), self.rng.uniform(8, self.h - 8)
                a = self.rng.uniform(0, math.pi)
                ln = self.rng.uniform(5, 16)
                d.line([(x * SS, y * SS), ((x + math.cos(a) * ln) * SS, (y + math.sin(a) * ln) * SS)], fill=255, width=max(1, int(SS * 0.9)))
            scr = np.asarray(sc, np.float32) / 255.0 * art
            sp = self._blank()
            d = ImageDraw.Draw(sp)
            for _ in range(n * 2):
                x, y = self.rng.uniform(8, self.w - 8), self.rng.uniform(8, self.h - 8)
                r = self.rng.uniform(0.8, 2.2) * SS
                d.ellipse([x * SS - r, y * SS - r, x * SS + r, y * SS + r], fill=255)
            spk = np.asarray(sp, np.float32) / 255.0 * art
            self.P += (self.A[..., None] * 255.0 - self.P) * (0.07 * scr)[..., None]
            self.P *= (1.0 - 0.10 * spk)[..., None]
        sh = self._soft(self.A, blur)
        dx, dy = int(shadow[0] * SS), int(shadow[1] * SS)
        sh = np.roll(np.roll(sh, dy, 0), dx, 1) * strength
        A2 = self.A + sh * (1.0 - self.A)
        chans = []
        for c in range(3):
            im = Image.fromarray(np.ascontiguousarray(self.P[..., c])).resize((self.w, self.h), Image.BOX)
            chans.append(np.asarray(im, np.float32))
        al = np.asarray(Image.fromarray(np.ascontiguousarray(A2)).resize((self.w, self.h), Image.BOX), np.float32)
        rgb = np.stack(chans, -1) / np.maximum(al, 1e-4)[..., None]
        out = np.dstack([np.clip(rgb, 0, 255), np.clip(al * 255.0, 0, 255)])
        # where there is nothing the colour is the outline's (so that a filter never pulls a pale fringe in)
        empty = out[..., 3] < 1.0
        out[empty, 0:3] = OUTLINE
        return Image.fromarray(out.astype(np.uint8))


def rrect_pts(x0, y0, x1, y1, r, seg=7):
    """A rectangle with round corners; `r` is one radius or four (top left, top right, bottom right, bottom left)."""
    rs = r if isinstance(r, (tuple, list)) else (r, r, r, r)
    out = []
    for (cx, cy, a0, rad) in ((x0 + rs[0], y0 + rs[0], 180, rs[0]), (x1 - rs[1], y0 + rs[1], 270, rs[1]), (x1 - rs[2], y1 - rs[2], 0, rs[2]), (x0 + rs[3], y1 - rs[3], 90, rs[3])):
        if rad <= 0.01:
            out.append((cx, cy))
            continue
        for k in range(seg + 1):
            a = math.radians(a0 + 90.0 * k / seg)
            out.append((cx + math.cos(a) * rad, cy + math.sin(a) * rad))
    return out


def ell_pts(cx, cy, rx, ry, a0=0.0, a1=360.0, n=72):
    return [(cx + math.cos(math.radians(a0 + (a1 - a0) * k / n)) * rx, cy + math.sin(math.radians(a0 + (a1 - a0) * k / n)) * ry) for k in range(n + 1 if a1 - a0 < 360 else n)]


def arc_path(cx, cy, r, a0, a1, n=24):
    return ell_pts(cx, cy, r, r, a0, a1, n)


# ----------------------------------------------------------------------------------- the items --

def shell_art(cv, to=(64, 62), s=1.0, rot=0.0):
    """One shotgun shell standing: a red hull with a crimped top on a brass base with a rim."""
    with cv.group(rot, (64, 62), s, to):
        cv.rrect(45, 78, 83, 108, 5, BRASS)
        cv.rrect(40, 100, 88, 113, 4, BRASS_D, hi=0.18)
        cv.ell(64, 106, 9, 3.2, BRASS_L, ow=2.0, hi=0, lo=0)
        cv.rrect(46, 14, 82, 86, 9, RED)
        cv.rrect(46, 14, 82, 34, (9, 9, 2, 2), RED_D)
        for x in (54, 64, 74):
            cv.detail([(x, 18), (x, 30)], 2.6, (20, 8, 8), 0.55)
        cv.detail([(54, 42), (54, 74)], 5.0, (255, 240, 230), 0.30)
        cv.detail([(46, 80), (82, 80)], 3.0, (60, 14, 12), 0.55)


def icon_shell():
    cv = Cv(U, U, 11)
    shell_art(cv, (64, 62), 1.0, -12)
    return cv.finish()


def icon_shells():
    cv = Cv(U, U, 12)
    shell_art(cv, (36, 70), 0.74, -13)
    shell_art(cv, (92, 70), 0.74, 13)
    shell_art(cv, (64, 62), 0.82, 0)
    return cv.finish()


def icon_shell_box():
    cv = Cv(U, U, 13)
    # the open top with the heads of the shells in it, a red box with a brass lid edge and a label that carries a shell
    cv.poly([(24, 50), (34, 32), (96, 32), (106, 50)], (38, 30, 28))
    for x in (44, 59, 74, 89):
        cv.rrect(x - 7, 26, x + 7, 46, 4, RED, ow=3.0, hi=0.25)
        cv.rrect(x - 7, 38, x + 7, 46, 2, BRASS, ow=0, hi=0, lo=0)
    cv.rrect(16, 48, 112, 108, 5, RED_D)
    cv.rrect(16, 48, 112, 60, (5, 5, 0, 0), BRASS, ow=3.5, hi=0.35)
    cv.rrect(30, 68, 98, 100, 3, CREAM, ow=3.0)
    cv.rrect(58, 72, 70, 92, 3, RED, ow=2.4)
    cv.rrect(57, 90, 71, 97, 2, BRASS_D, ow=2.0, hi=0, lo=0)
    cv.detail([(36, 76), (52, 76)], 3.0, RED_D, 0.8)
    cv.detail([(36, 86), (52, 86)], 3.0, RED_D, 0.8)
    cv.detail([(76, 76), (92, 76)], 3.0, RED_D, 0.8)
    cv.detail([(76, 86), (92, 86)], 3.0, RED_D, 0.8)
    cv.detail([(22, 66), (22, 100)], 4.0, (255, 220, 210), 0.22)
    return cv.finish()


def icon_canned_food():
    cv = Cv(U, U, 14)
    cv.ell(64, 104, 36, 9, TIN_D, ow=4.0, hi=0, lo=0)
    cv.rrect(28, 36, 100, 104, 4, TIN)
    cv.rrect(28, 54, 100, 90, 0, ORANGE, ow=3.5)
    cv.ell(64, 72, 19, 12, CREAM, ow=3.0)
    cv.ell(56, 71, 6, 4.5, ORANGE_D, ow=0, hi=0, lo=0)
    cv.ell(70, 74, 5.5, 4, (120, 150, 70), ow=0, hi=0, lo=0)
    cv.detail([(28, 60), (100, 60)], 2.4, (255, 235, 200), 0.4)
    cv.detail([(28, 42), (100, 42)], 2.6, (50, 56, 54), 0.4)
    cv.detail([(28, 97), (100, 97)], 2.6, (50, 56, 54), 0.4)
    cv.detail([(37, 44), (37, 98)], 5.0, (255, 255, 255), 0.26)
    cv.ell(64, 36, 36, 9.5, TIN_L, ow=4.0)
    cv.ell(64, 36, 29, 6.2, TIN, ow=0, hi=0, lo=0.1)
    cv.stroke(arc_path(78, 34, 9, 0, 360, 28), 3.4, TIN_D, ow=2.4, hi=0.1, lo=0, caps=False)
    return cv.finish()


def icon_ration_pack():
    cv = Cv(U, 2 * U, 15)
    left = [(26, 38), (31, 28), (36, 38), (41, 28), (46, 38), (51, 28), (56, 38), (61, 28), (66, 38), (71, 28), (76, 38), (81, 28), (86, 38), (91, 28), (96, 38), (101, 28)]
    right = [(101, 220), (96, 230), (91, 220), (86, 230), (81, 220), (76, 230), (71, 220), (66, 230), (61, 220), (56, 230), (51, 220), (46, 230), (41, 220), (36, 230), (31, 220), (26, 230)]
    body = left + [(104, 70), (107, 130), (104, 190)] + right + [(24, 190), (21, 130), (24, 70)]
    cv.poly(body, OLIVE, ow=4.0)
    cv.rrect(24, 38, 104, 54, 0, OLIVE_D, ow=0, hi=0.08)
    cv.rrect(24, 204, 104, 220, 0, OLIVE_D, ow=0, hi=0.0)
    cv.rrect(38, 78, 90, 178, 4, CREAM, ow=3.0)
    cv.rrect(38, 78, 90, 94, (4, 4, 0, 0), RED, ow=0, hi=0, lo=0)
    for k, wd in enumerate((38, 30, 36)):
        cv.detail([(46, 108 + k * 12), (46 + wd, 108 + k * 12)], 4.0, OLIVE_D, 0.8)
    cv.poly([(64 + math.cos(math.radians(-90 + 36 * k)) * (11 if k % 2 == 0 else 5), 158 + math.sin(math.radians(-90 + 36 * k)) * (11 if k % 2 == 0 else 5)) for k in range(10)], OLIVE_D, ow=0, hi=0, lo=0, tex=0)
    cv.detail([(30, 66), (40, 52)], 3.0, (255, 255, 255), 0.22)
    cv.detail([(98, 190), (88, 204)], 3.0, (255, 255, 255), 0.18)
    cv.patch([(24, 198), (24, 190), (30, 196)], (0, 0, 0), 0.25)
    return cv.finish()


def icon_water_bottle():
    # PH10: ONE cell (it was two): a squat bottle with a cap, a shoulder, a label with a drop on it and the same flat look
    cv = Cv(U, U, 16)
    cv.rrect(36, 42, 92, 120, (16, 16, 11, 11), BLUE)
    cv.poly([(50, 28), (78, 28), (88, 48), (40, 48)], BLUE_PALE, ow=3.5)
    cv.rrect(49, 7, 79, 33, 3, WHITE, ow=4.0)
    for x in (55, 61, 67, 73):
        cv.detail([(x, 12), (x, 28)], 2.4, (110, 120, 126), 0.55)
    cv.rrect(36, 66, 92, 104, 0, WHITE, ow=3.5)
    cv.poly([(64, 71), (74, 85), (64, 98), (54, 85)], BLUE, ow=3.0)
    cv.detail([(43, 56), (43, 76)], 5.0, (255, 255, 255), 0.35)
    cv.detail([(43, 108), (43, 116)], 4.0, (255, 255, 255), 0.22)
    return cv.finish()


def icon_water_jug():
    cv = Cv(2 * U, 2 * U, 17)
    handle = [(186, 100), (214, 100), (230, 114), (230, 172), (214, 186), (186, 186)]
    cv.stroke(handle, 17, BLUE_D, ow=4.0, caps=False)
    cv.rrect(46, 84, 202, 238, 26, BLUE)
    cv.rrect(98, 44, 154, 92, 8, BLUE_PALE, ow=4.0)
    cv.rrect(104, 18, 148, 50, 5, WHITE, ow=4.0)
    for x in (112, 122, 132, 142):
        cv.detail([(x, 24), (x, 44)], 2.6, (110, 120, 126), 0.5)
    cv.rrect(60, 128, 188, 206, 5, WHITE, ow=3.5)
    cv.poly([(124, 138), (142, 168), (124, 192), (106, 168)], BLUE, ow=3.0)
    cv.detail([(56, 100), (56, 150)], 7.0, (255, 255, 255), 0.30)
    cv.detail([(52, 214), (196, 214)], 3.2, (30, 70, 100), 0.5)
    cv.detail([(52, 226), (196, 226)], 3.2, (30, 70, 100), 0.5)
    return cv.finish()


def icon_bandage():
    cv = Cv(U, U, 18)
    # the loose tail first (under the roll), then the roll seen from its end
    cv.poly([(72, 92), (118, 100), (120, 116), (84, 118), (70, 108)], CREAM, ow=3.6)
    cv.detail([(88, 106), (116, 108)], 2.6, CREAM_D, 0.8)
    cv.rrect(110, 99, 122, 117, 2, CROSS, ow=0, hi=0, lo=0)
    cv.ell(58, 62, 46, 44, CREAM, ow=4.0)
    cv.ell(58, 62, 36, 34, CREAM_D, ow=0, hi=0, lo=0.1)
    cv.ell(58, 62, 33, 31, CREAM, ow=0, hi=0, lo=0)
    cv.stroke(ell_pts(58, 62, 26, 24, 0, 340, 40), 2.6, CREAM_D, ow=0, hi=0, lo=0, tex=0, caps=False)
    cv.stroke(ell_pts(58, 62, 18, 17, 20, 360, 40), 2.6, CREAM_D, ow=0, hi=0, lo=0, tex=0, caps=False)
    cv.ell(58, 62, 11, 10, (36, 48, 42), ow=3.0, hi=0, lo=0.1)
    cv.detail([(30, 40), (46, 26)], 5.0, (255, 255, 255), 0.5)
    return cv.finish()


def icon_medkit():
    cv = Cv(2 * U, U, 19)
    cv.stroke([(96, 40), (96, 22), (160, 22), (160, 40)], 10, STEEL, ow=4.0, caps=False)
    cv.rrect(16, 36, 240, 114, 12, WHITE)
    cv.rrect(16, 94, 240, 114, (0, 0, 12, 12), CREAM_D, ow=0, hi=0, lo=0.1)
    cv.rrect(16, 36, 34, 54, (12, 0, 0, 0), GREY, ow=2.5, hi=0.1)
    cv.rrect(222, 36, 240, 54, (0, 12, 0, 0), GREY, ow=2.5, hi=0.1)
    cv.rrect(98, 58, 158, 82, 3, CROSS, ow=3.0)
    cv.rrect(116, 44, 140, 96, 3, CROSS, ow=3.0)
    cv.rrect(98, 58, 158, 82, 3, CROSS, ow=0, hi=0.25)
    cv.rrect(40, 64, 56, 88, 3, STEEL, ow=3.0)
    cv.rrect(200, 64, 216, 88, 3, STEEL, ow=3.0)
    cv.detail([(26, 46), (86, 46)], 3.0, (255, 255, 255), 0.5)
    cv.detail([(170, 46), (230, 46)], 3.0, (255, 255, 255), 0.5)
    return cv.finish()


def icon_unknown():
    cv = Cv(U, U, 20)
    cv.rrect(22, 30, 106, 106, 5, PAPER)
    cv.rrect(22, 30, 106, 46, (5, 5, 0, 0), PAPER_D, ow=0)
    cv.stroke(arc_path(64, 66, 12, 200, 440, 20) + [(64, 80)], 7.0, DARK, ow=0, hi=0, lo=0, tex=0, caps=False)
    cv.ell(64, 94, 4.5, 4.5, DARK, ow=0, hi=0, lo=0, tex=0)
    return cv.finish()


# ----------------------------------------------------------------------------- the equipment --

def icon_pump_shotgun():
    """Side on, muzzle to the left: a long barrel over the magazine tube, the wooden pump grip under it, the receiver, a stock."""
    cv = Cv(2 * U, U, 21)
    cv.rrect(10, 46, 150, 58, 3, STEEL)
    cv.rrect(10, 60, 128, 70, 3, STEEL_D)
    cv.rrect(7, 44, 17, 60, 2, STEEL_D, ow=3.0)
    cv.rrect(78, 58, 126, 82, 6, WOOD)
    for x in (88, 98, 108, 118):
        cv.detail([(x, 62), (x, 78)], 2.6, WOOD_D, 0.8)
    cv.stroke([(168, 74), (172, 90), (186, 94), (192, 80)], 5.0, STEEL_D, ow=3.0, caps=False)
    cv.poly([(150, 40), (186, 40), (192, 50), (192, 76), (150, 78)], STEEL_D, ow=4.0)
    cv.rrect(158, 48, 180, 54, 2, STEEL, ow=0, hi=0.4, lo=0)
    cv.poly([(190, 44), (232, 56), (246, 84), (240, 94), (222, 92), (190, 78)], WOOD, ow=4.0)
    cv.detail([(196, 52), (232, 62)], 3.0, (255, 235, 200), 0.35)
    cv.ell(14, 46, 3, 3, BRASS_L, ow=0, hi=0, lo=0)
    return cv.finish()


def icon_melee():
    """A bat with the swish of a swing behind it (Ruth swings whatever she holds: it is the blow, not an item)."""
    cv = Cv(U, U, 22)
    cv.stroke(arc_path(52, 84, 56, -62, 30, 18), 9.0, CREAM, ow=0, hi=0, lo=0, tex=0, alpha=0.50, caps=True)
    cv.stroke(arc_path(52, 84, 44, -50, 22, 18), 4.5, CREAM, ow=0, hi=0, lo=0, tex=0, alpha=0.38, caps=True)
    with cv.group(-42, (64, 64), 1.0, (60, 70)):
        cv.poly([(26, 61), (60, 57), (88, 51), (108, 47), (118, 53), (118, 75), (108, 81), (88, 77), (60, 71), (26, 67)], WOOD, ow=4.0)
        cv.ell(18, 64, 9, 9, WOOD_D, ow=4.0, hi=0.15)
        cv.poly([(28, 60.5), (52, 57.6), (52, 70.4), (28, 67.5)], (46, 54, 50), ow=3.0, hi=0.1)
        for x in (33, 40, 47):
            cv.detail([(x, 60), (x + 4, 68)], 2.2, (150, 160, 154), 0.55)
        cv.detail([(70, 58), (112, 54)], 3.4, (255, 235, 200), 0.42)
        cv.detail([(70, 70), (110, 74)], 2.4, (60, 36, 18), 0.35)
    return cv.finish()


def icon_pack():
    """A small backpack, for the chip and the window's head (brass, as the HUD's own marks)."""
    cv = Cv(U, U, 23)
    cv.stroke(arc_path(64, 28, 17, 180, 360, 14), 7.0, BRASS_D, ow=3.0, caps=False)
    body = [(24, 112), (22, 70)] + ell_pts(64, 66, 42, 42, 180, 360, 24)[1:-1] + [(106, 70), (104, 112)]
    cv.poly(body, BRASS, ow=4.5)
    cv.rrect(24, 70, 104, 82, 0, BRASS_D, ow=0, hi=0, lo=0.1)
    cv.rrect(40, 88, 88, 110, 5, BRASS_D, ow=3.5)
    cv.detail([(46, 94), (82, 94)], 3.0, BRASS_L, 0.6)
    cv.detail([(34, 50), (48, 36)], 5.0, (255, 255, 255), 0.35)
    return cv.finish()


def icon_slot(kind):
    """The frame of a quick slot: a dark inset with a brass edge and four corner ticks (empty), lit (a warm edge: something is in it), or off (dimmed)."""
    cv = Cv(U, U, 24 + len(kind))
    edge = {"slot": (122, 100, 52), "slot_on": ACCENT, "slot_off": (82, 90, 84)}[kind]
    fill = {"slot": (13, 26, 22), "slot_on": (30, 34, 24), "slot_off": (18, 26, 24)}[kind]
    cv.rrect(8, 8, 120, 120, 16, fill, ow=7.0, hi=0.0, lo=0.0, tex=0.03, ocol=edge, hb=3.0)
    cv.rrect(8, 8, 120, 120, 16, fill, ow=0, hi=0.0, lo=0.0, tex=0.0, alpha=0.0)
    for (x, y, dx, dy) in ((20, 20, 1, 1), (108, 20, -1, 1), (20, 108, 1, -1), (108, 108, -1, -1)):
        cv.detail([(x, y + dy * 16), (x, y), (x + dx * 16, y)], 4.0, edge, 0.55 if kind != "slot_off" else 0.3)
    if kind == "slot_on":
        cv.rrect(14, 14, 114, 114, 12, ACCENT, ow=0, hi=0, lo=0, tex=0, alpha=0.10)
    return cv.finish(shadow=(0, 0), blur=1.0, strength=0.0, wear=False)


def icon_glow():
    a = np.zeros((64, 64), np.float32)
    y, x = np.mgrid[0:64, 0:64]
    r = np.hypot(x - 31.5, y - 31.5) / 31.5
    a = np.clip(1.0 - r, 0, 1) ** 1.8
    out = np.zeros((64, 64, 4), np.uint8)
    out[..., 0:3] = (255, 244, 214)
    out[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(out)


# ------------------------------------------------------------------------------------ Ruth --

SKIN = (132, 104, 86)
JACKET = (104, 60, 52)
JACKET_D = (78, 44, 38)
TROUSERS = (58, 70, 74)
HAIR = (160, 162, 154)


def icon_ruth():
    """Ruth from the front, in the game's flat way: grey hair, a rust jacket with the collar up, a belt, dark trousers. 224 x 336 (the window shows it at half that: 112 x 168)."""
    cv = Cv(224, 336, 25)
    cx = 112
    # legs and boots
    cv.poly([(76, 214), (110, 214), (106, 312), (78, 312)], TROUSERS, ow=4.5)
    cv.poly([(114, 214), (148, 214), (146, 312), (118, 312)], TROUSERS, ow=4.5)
    cv.rrect(70, 304, 108, 326, (4, 8, 6, 4), (40, 36, 34), ow=4.5)
    cv.rrect(116, 304, 154, 326, (8, 4, 4, 6), (40, 36, 34), ow=4.5)
    # arms (behind the body at the shoulder, hands at the belt)
    cv.poly([(66, 92), (50, 100), (40, 150), (36, 206), (56, 208), (62, 160), (80, 112)], JACKET_D, ow=4.5)
    cv.poly([(158, 92), (174, 100), (184, 150), (188, 206), (168, 208), (162, 160), (144, 112)], JACKET_D, ow=4.5)
    cv.ell(46, 214, 12, 13, SKIN, ow=4.0)
    cv.ell(178, 214, 12, 13, SKIN, ow=4.0)
    # the body: shoulders, jacket, hem
    cv.poly([(80, 84), (112, 76), (144, 84), (158, 96), (152, 150), (156, 226), (68, 226), (72, 150), (66, 96)], JACKET, ow=4.5)
    cv.detail([(112, 96), (112, 224)], 3.0, JACKET_D, 0.8)
    cv.rrect(66, 204, 158, 226, 2, (50, 40, 34), ow=3.5)
    cv.rrect(104, 207, 120, 223, 2, BRASS, ow=2.5)
    # neck, collar, head, hair
    cv.rrect(98, 60, 126, 90, 6, SKIN, ow=4.0)
    cv.poly([(86, 82), (104, 92), (112, 100), (120, 92), (138, 82), (132, 72), (112, 84), (92, 72)], JACKET_D, ow=3.5)
    cv.ell(112, 14, 12, 10, HAIR, ow=4.0)
    cv.ell(112, 40, 28, 30, HAIR, ow=4.5)
    cv.ell(112, 50, 20, 24, SKIN, ow=4.0)
    cv.poly([(92, 46), (98, 30), (112, 25), (126, 30), (132, 46), (124, 36), (112, 33), (100, 36)], HAIR, ow=3.0)
    cv.ell(104, 50, 2.6, 2.6, (40, 30, 26), ow=0, hi=0, lo=0, tex=0)
    cv.ell(120, 50, 2.6, 2.6, (40, 30, 26), ow=0, hi=0, lo=0, tex=0)
    cv.detail([(98, 30), (110, 22)], 4.0, (255, 255, 255), 0.35)
    return cv.finish(shadow=(0, 3), blur=3.0, strength=0.35, wear=False)


# ------------------------------------------------------------------------------------ atlas --

ICONS = [
    ("shell", icon_shell), ("shells", icon_shells), ("shell_box", icon_shell_box), ("canned_food", icon_canned_food), ("bandage", icon_bandage),
    ("ration_pack", icon_ration_pack), ("water_bottle", icon_water_bottle), ("water_jug", icon_water_jug), ("medkit", icon_medkit), ("unknown", icon_unknown),
    ("pump_shotgun", icon_pump_shotgun), ("melee", icon_melee), ("pack", icon_pack),
    ("slot", lambda: icon_slot("slot")), ("slot_on", lambda: icon_slot("slot_on")), ("slot_off", lambda: icon_slot("slot_off")),
    ("glow", icon_glow), ("ruth", icon_ruth),
]


def pack_atlas(images, width=1024):
    """A shelf packer: the tallest first, rows to `width`."""
    order = sorted(images.items(), key=lambda kv: (-kv[1].height, kv[0]))
    x = y = row_h = 0
    placed = {}
    for name, im in order:
        if x + im.width + GUTTER > width:
            x = 0
            y += row_h + GUTTER
            row_h = 0
        placed[name] = (x + GUTTER // 2, y + GUTTER // 2)
        x += im.width + GUTTER
        row_h = max(row_h, im.height)
    height = y + row_h + GUTTER
    return placed, height


def build(out_dir):
    images = {}
    for name, fn in ICONS:
        images[name] = fn()
        print("drew", name, images[name].size)
    placed, height = pack_atlas(images)
    height = 1 << max(8, (height - 1).bit_length())
    atlas = Image.new("RGBA", (1024, height), (0, 0, 0, 0))
    regions = {}
    for name, im in images.items():
        px, py = placed[name]
        atlas.paste(im, (px, py))
        regions[name] = [px, py, im.width, im.height]
    os.makedirs(out_dir, exist_ok=True)
    png = os.path.join(out_dir, "inv_icons.png")
    atlas.save(png, optimize=True)
    with open(os.path.join(out_dir, "inv_icons.json"), "w") as f:
        json.dump({"_doc": "Made by tools/make_item_icons.py. unit: pixels of one inventory cell in the atlas; regions: name -> [x, y, w, h].", "unit": U, "regions": regions}, f, indent=1, sort_keys=True)
        f.write("\n")
    print("atlas", atlas.size, os.path.getsize(png), "bytes")
    return images


def sheet(images, path):
    """Every picture at 128, 72, 48 and 32 px for a cell, on the panel's own dark green, one row for each size."""
    bg = (27, 42, 38, 255)
    names = [n for n, _ in ICONS if n not in ("glow", "ruth")]
    sizes = [128, 72, 48, 32]
    margin = 12
    widths = []
    for n in names:
        widths.append(images[n].width / U)
    total_w = [sum(int(w * s) + margin for w in widths) + margin for s in sizes]
    W = max(total_w)
    H = sum(2 * s + margin for s in sizes) + margin
    im = Image.new("RGBA", (W, H), bg)
    y = margin
    for s in sizes:
        x = margin
        for n in names:
            src = images[n]
            w, h = int(src.width * s / U), int(src.height * s / U)
            sm = src.resize((w, h), Image.LANCZOS)
            im.alpha_composite(sm, (x, y))
            x += w + margin
        y += 2 * s + margin
    r = images["ruth"]
    im.save(path)
    print("sheet", path, im.size)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--sheet", default="")
    a = ap.parse_args(argv)
    images = build(a.out)
    if a.sheet:
        sheet(images, a.sheet)


if __name__ == "__main__":
    main(sys.argv[1:])
