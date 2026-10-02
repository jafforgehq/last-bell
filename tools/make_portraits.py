#!/usr/bin/env python3
"""Draws the sixteen portraits of the survivors who call over the radio: assets/portraits/gen_00.png .. gen_15.png.

The six authored portraits were drawn by the art code of the web prototype (drawPortrait in src/art/pawn.js:
a tinted backdrop and the front view of a figure, body and big head, in flat shapes with dark outlines). That
code is not in this repository any more, so this script carries a port of the front view of it (Pillow and
NumPy only: a small canvas that fills and strokes paths at four times the size and averages down) and draws
the portraits from the looks listed under "portrait_looks" in assets/data/recruits.json: a skin, a hair
style, clothes, glasses, a beard, a cap. Each portrait is therefore a different person drawn in the same
hand as the six, not a recoloured copy of one of them.

    python3 tools/make_portraits.py                 draws the sixteen, as listed in recruits.json
    python3 tools/make_portraits.py --check         draws the six authored from their looks in map.json and
                                                    reports how close they are to assets/portraits/*.png
    python3 tools/make_portraits.py --sheet out.png a contact sheet of the sixteen (and the six, beside them)
    python3 tools/make_portraits.py --out DIR       writes the sixteen to DIR instead of assets/portraits

It is deterministic: the same recruits.json gives the same files, byte for byte. Godot makes the .import
files of new portraits the next time it scans the project.

The looks use what the figure's drawing knows (see the lists below): hair short, buzz, curly, twists, messy,
ponytail, long, bald, balding; tops tee, shirt, hoodie, scrubs, coverall, uniform; outers jacket, cardigan,
vest, hivis; a cap or a beanie; glasses, a beard (full or stubble), a mustache, a backpack, a belt, a tie,
a patch, an armband, a bandolier.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data", "recruits.json")
MAP = os.path.join(ROOT, "assets", "data", "map.json")
OUT = os.path.join(ROOT, "assets", "portraits")
SIZE = 192
SUPERSAMPLE = 4

# the head and the body, in tiles (the prototype's numbers)
HEAD_Y = -0.53
HRX = 0.25
HRY = 0.265
TOP = -0.28
HEM = 0.13
SW = 0.64
HW = 0.54
LW = 0.038
EYE = "#1d1512"
INK = (26, 20, 15, 0.8)


# ---------------------------------------------------------------- colours --

def _round(v):
    return int(math.floor(v + 0.5))


def hex_rgb(h):
    return int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)


def to_hex(rgb):
    return "#" + "".join("%02x" % max(0, min(255, _round(v))) for v in rgb)


def shade(h, k):
    """k < 0 darkens toward black, k > 0 lightens toward white (as the prototype's shade)."""
    t = 0 if k < 0 else 255
    f = abs(k)
    return to_hex([v + (t - v) * f for v in hex_rgb(h)])


def alpha(h, a):
    r, g, b = hex_rgb(h)
    return (r, g, b, a)


def col(c):
    """A colour as (r, g, b, a): from '#rrggbb' or an (r, g, b, a) tuple."""
    if isinstance(c, str):
        r, g, b = hex_rgb(c)
        return (r, g, b, 1.0)
    return c


# ----------------------------------------------------------------- random --

def _imul(a, b):
    return (a * b) & 0xFFFFFFFF


def mulberry32(seed):
    state = [seed & 0xFFFFFFFF]

    def nxt():
        a = (state[0] + 0x6D2B79F5) & 0xFFFFFFFF
        state[0] = a
        t = _imul(a ^ (a >> 15), 1 | a)
        t = ((t + _imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
        return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

    return nxt


def rng(seed):
    return mulberry32((seed * 2654435761) & 0xFFFFFFFF)


# ----------------------------------------------------------------- canvas --

class Gradient:
    """A linear or radial gradient in device coordinates; `at(X, Y)` gives straight (r, g, b, a) per sample."""

    def __init__(self, kind, args, stops):
        self.kind = kind
        self.args = args
        self.stops = [(o, col(c)) for o, c in stops]

    def at(self, X, Y):
        if self.kind == "linear":
            x0, y0, x1, y1 = self.args
            dx, dy = x1 - x0, y1 - y0
            t = ((X - x0) * dx + (Y - y0) * dy) / (dx * dx + dy * dy)
        else:
            x0, y0, r0, x1, y1, r1 = self.args
            cx, cy, dr = x1 - x0, y1 - y0, r1 - r0
            px, py = X - x0, Y - y0
            a = cx * cx + cy * cy - dr * dr
            b = px * cx + py * cy + r0 * dr
            c = px * px + py * py - r0 * r0
            if abs(a) < 1e-9:
                t = c / (2.0 * b)
            else:
                disc = np.sqrt(np.maximum(b * b - a * c, 0.0))
                t1 = (b + disc) / a
                t2 = (b - disc) / a
                t = np.maximum(t1, t2)
        t = np.clip(t, 0.0, 1.0)
        offs = [s[0] for s in self.stops]
        out = np.empty(X.shape + (4,), np.float32)
        for ch in range(4):
            out[..., ch] = np.interp(t, offs, [s[1][ch] for s in self.stops])
        return out


class Canvas:
    """The bits of a 2D canvas the portrait drawing needs: paths of lines, curves, arcs and ellipses; fill
    (a colour or a gradient), stroke (round joins, round or butt caps), clip, save and restore, translate.
    Everything is drawn at SUPERSAMPLE times the size and averaged down at the end."""

    def __init__(self, w, h, ss=SUPERSAMPLE):
        self.w, self.h, self.ss = w, h, ss
        self.W, self.H = w * ss, h * ss
        self.buf = np.zeros((self.H, self.W, 4), np.float32)    # premultiplied
        self.scale, self.ox, self.oy = 1.0, 0.0, 0.0
        self.tx, self.ty = 0.0, 0.0
        self.clip_mask = None
        self.cap = "butt"
        self.path = []
        self._stack = []

    # -- state
    def set_transform(self, scale, ox, oy):
        self.scale, self.ox, self.oy = scale, ox, oy

    def translate(self, dx, dy):
        self.tx += dx
        self.ty += dy

    def save(self):
        self._stack.append((self.tx, self.ty, self.clip_mask, self.cap))

    def restore(self):
        self.tx, self.ty, self.clip_mask, self.cap = self._stack.pop()

    def _pt(self, x, y):
        return ((self.scale * (x + self.tx) + self.ox) * self.ss, (self.scale * (y + self.ty) + self.oy) * self.ss)

    def dev(self, v):
        """A length in tiles as device pixels."""
        return v * self.scale * self.ss

    # -- paths
    def begin(self):
        self.path = []

    def _cur(self):
        return self.path[-1][0] if self.path else None

    def move_to(self, x, y):
        self.path.append([[self._pt(x, y)], False])

    def line_to(self, x, y):
        if not self.path:
            self.move_to(x, y)
        else:
            self._cur().append(self._pt(x, y))

    def quad(self, cx, cy, x, y):
        p0 = self._cur()[-1]
        p1 = self._pt(cx, cy)
        p2 = self._pt(x, y)
        n = self._steps(p0, p1, p2)
        for i in range(1, n + 1):
            t = i / n
            u = 1 - t
            self._cur().append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))

    def bezier(self, c1x, c1y, c2x, c2y, x, y):
        p0 = self._cur()[-1]
        p1, p2, p3 = self._pt(c1x, c1y), self._pt(c2x, c2y), self._pt(x, y)
        n = self._steps(p0, p1, p2, p3)
        for i in range(1, n + 1):
            t = i / n
            u = 1 - t
            self._cur().append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                                u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))

    @staticmethod
    def _steps(*pts):
        length = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))
        return max(8, int(length / 3.0))

    def close(self):
        if self.path:
            self.path[-1][1] = True

    def ellipse(self, x, y, rx, ry, rot=0.0, a0=0.0, a1=2 * math.pi):
        n = max(24, int(2 * math.pi * self.dev(max(rx, ry)) / 3.0))
        full = abs(a1 - a0) >= 2 * math.pi - 1e-9
        pts = []
        cr, sr = math.cos(rot), math.sin(rot)
        steps = n if full else max(8, int(n * abs(a1 - a0) / (2 * math.pi)))
        for i in range(steps + (0 if full else 1)):
            a = a0 + (a1 - a0) * i / steps
            ex, ey = math.cos(a) * rx, math.sin(a) * ry
            pts.append(self._pt(x + ex * cr - ey * sr, y + ex * sr + ey * cr))
        self.path.append([pts, full])

    def circle(self, x, y, r):
        self.begin()
        self.ellipse(x, y, r, r)

    def ell(self, x, y, rx, ry, rot=0.0):
        self.begin()
        self.ellipse(x, y, rx, ry, rot)

    def round_rect(self, x, y, w, h, r):
        r = min(r, w / 2.0, h / 2.0)
        self.begin()
        self.move_to(x + r, y)
        self.line_to(x + w - r, y)
        for cx, cy, a0 in ((x + w - r, y + r, -math.pi / 2), (x + w - r, y + h - r, 0.0), (x + r, y + h - r, math.pi / 2), (x + r, y + r, math.pi)):
            for i in range(0, 9):
                a = a0 + (math.pi / 2) * i / 8
                self.line_to(cx + math.cos(a) * r, cy + math.sin(a) * r)
        self.close()

    def poly(self, pts):
        self.begin()
        self.move_to(pts[0], pts[1])
        for i in range(2, len(pts), 2):
            self.line_to(pts[i], pts[i + 1])
        self.close()

    # -- gradients
    def linear(self, x0, y0, x1, y1, stops):
        a, b = self._pt(x0, y0), self._pt(x1, y1)
        return Gradient("linear", (a[0], a[1], b[0], b[1]), stops)

    def radial(self, x0, y0, r0, x1, y1, r1, stops):
        a, b = self._pt(x0, y0), self._pt(x1, y1)
        return Gradient("radial", (a[0], a[1], self.dev(r0), b[0], b[1], self.dev(r1)), stops)

    # -- rasterising: every closed polygon counts, inside = non-zero winding, a sample is in if its centre is
    def _mask(self, polys):
        """(coverage, y0, y1, x0, x1) of the polygons, or None when nothing is inside the canvas."""
        edges0, edges1 = [], []
        for pts in polys:
            if len(pts) < 3:
                continue
            a = np.asarray(pts, np.float64)
            area = float(np.sum(a[:, 0] * np.roll(a[:, 1], -1) - np.roll(a[:, 0], -1) * a[:, 1]))
            if area < 0:
                a = a[::-1]
            edges0.append(a)
            edges1.append(np.roll(a, -1, axis=0))
        if not edges0:
            return None
        p0 = np.concatenate(edges0)
        p1 = np.concatenate(edges1)
        xmin = max(0, int(math.floor(min(p0[:, 0].min(), p1[:, 0].min()))) - 1)
        xmax = min(self.W, int(math.ceil(max(p0[:, 0].max(), p1[:, 0].max()))) + 2)
        ymin = max(0, int(math.floor(min(p0[:, 1].min(), p1[:, 1].min()))) - 1)
        ymax = min(self.H, int(math.ceil(max(p0[:, 1].max(), p1[:, 1].max()))) + 2)
        if xmax <= xmin or ymax <= ymin:
            return None
        y0, y1 = p0[:, 1], p1[:, 1]
        keep = y0 != y1
        p0, p1 = p0[keep], p1[keep]
        y0, y1 = p0[:, 1], p1[:, 1]
        r0 = np.clip(np.ceil(np.minimum(y0, y1) - 0.5).astype(np.int64), ymin, ymax)
        r1 = np.clip(np.ceil(np.maximum(y0, y1) - 0.5).astype(np.int64), ymin, ymax)
        n = np.maximum(r1 - r0, 0)
        total = int(n.sum())
        wid = xmax - xmin
        delta = np.zeros((ymax - ymin, wid + 1), np.int32)
        if total:
            e = np.repeat(np.arange(len(p0)), n)
            starts = np.cumsum(n) - n
            rows = r0[e] + (np.arange(total) - np.repeat(starts, n))
            yc = rows + 0.5
            x = p0[e, 0] + (yc - p0[e, 1]) * (p1[e, 0] - p0[e, 0]) / (p1[e, 1] - p0[e, 1])
            idx = np.clip(np.ceil(x - 0.5).astype(np.int64) - xmin, 0, wid)
            direction = np.where(p1[e, 1] > p0[e, 1], 1, -1).astype(np.int32)
            np.add.at(delta, (rows - ymin, idx), direction)
        inside = np.cumsum(delta[:, :wid], axis=1) != 0
        cov = inside.astype(np.float32)
        if self.clip_mask is not None:
            cov = cov * self.clip_mask[ymin:ymax, xmin:xmax]
        return cov, ymin, ymax, xmin, xmax

    def _paint(self, region, src):
        if region is None:
            return
        cov, y0, y1, x0, x1 = region
        sub = self.buf[y0:y1, x0:x1]
        if isinstance(src, Gradient):
            ys, xs = np.mgrid[y0:y1, x0:x1]
            c = src.at(xs + 0.5, ys + 0.5)
            sa = cov * c[..., 3]
            rgb = c[..., :3] / 255.0
        else:
            r, g, b, a = src
            sa = cov * a
            rgb = np.array([r, g, b], np.float32) / 255.0
        sub *= (1.0 - sa)[..., None]
        sub[..., :3] += sa[..., None] * rgb
        sub[..., 3] += sa

    def fill(self, style):
        self._paint(self._mask([p[0] for p in self.path]), col(style) if not isinstance(style, Gradient) else style)

    def fill_rect(self, x, y, w, h, style):
        self.poly([x, y, x + w, y, x + w, y + h, x, y + h])
        self.fill(style)

    def stroke(self, width, style):
        """Strokes every subpath of the current path, `width` tiles wide: round joins, and round caps when
        the cap is round (the prototype's `ink` and `line` set it; a fresh canvas has butt caps)."""
        wpx = max(self.dev(width), 0.5)
        r = wpx / 2.0
        polys = []
        steps = max(10, int(wpx * 1.5))
        for pts, closed in self.path:
            seq = list(pts)
            if closed and len(seq) > 1:
                seq.append(seq[0])
            # drop repeated points
            clean = [seq[0]] if seq else []
            for p in seq[1:]:
                if abs(p[0] - clean[-1][0]) > 1e-6 or abs(p[1] - clean[-1][1]) > 1e-6:
                    clean.append(p)
            if len(clean) == 1:
                if self.cap == "round":
                    polys.append(self._disc(clean[0], r, steps))
                continue
            for a, b in zip(clean[:-1], clean[1:]):
                dx, dy = b[0] - a[0], b[1] - a[1]
                ln = math.hypot(dx, dy)
                nx, ny = -dy / ln * r, dx / ln * r
                polys.append([(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny), (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)])
            for i, p in enumerate(clean):
                if 0 < i < len(clean) - 1 or closed or self.cap == "round":
                    polys.append(self._disc(p, r, steps))
        self._paint(self._mask(polys), col(style))

    @staticmethod
    def _disc(p, r, steps):
        return [(p[0] + math.cos(2 * math.pi * i / steps) * r, p[1] + math.sin(2 * math.pi * i / steps) * r) for i in range(steps)]

    def clip(self):
        region = None
        m = np.zeros((self.H, self.W), np.float32)
        saved = self.clip_mask
        self.clip_mask = None
        region = self._mask([p[0] for p in self.path])
        self.clip_mask = saved
        if region is not None:
            cov, y0, y1, x0, x1 = region
            m[y0:y1, x0:x1] = cov
        if saved is not None:
            m = m * saved
        self.clip_mask = m

    # -- output
    def image(self):
        a = self.buf.reshape(self.h, self.ss, self.w, self.ss, 4).mean(axis=(1, 3))
        alpha_ = a[..., 3:4]
        rgb = np.where(alpha_ > 1e-6, a[..., :3] / np.maximum(alpha_, 1e-6), 0.0)
        out = np.concatenate([np.clip(rgb * 255.0 + 0.5, 0, 255), np.clip(alpha_ * 255.0 + 0.5, 0, 255)], axis=2).astype(np.uint8)
        return Image.fromarray(out)


# ---------------------------------------------------------------- helpers --

def ink(c, w=0.042, color=INK):
    c.cap = "round"
    c.stroke(w, color)


def line(c, x0, y0, x1, y1, w, color):
    c.begin()
    c.move_to(x0, y0)
    c.line_to(x1, y1)
    c.cap = "round"
    c.stroke(w, color)


def fill_path(c, color):
    c.fill(color)


# ------------------------------------------------------------------ torso --

def torso_path(c):
    s = SW / 2
    h = HW / 2
    rad = 0.15
    c.begin()
    c.move_to(-s + rad, TOP)
    c.line_to(s - rad, TOP)
    c.quad(s, TOP, s + 0.005, TOP + rad)
    c.line_to(h, HEM - 0.05)
    c.quad(h, HEM, h - 0.05, HEM)
    c.line_to(-h + 0.05, HEM)
    c.quad(-h, HEM, -h, HEM - 0.05)
    c.line_to(-s - 0.005, TOP + rad)
    c.quad(-s, TOP, -s + rad, TOP)
    c.close()


def shade_torso(c):
    g = c.linear(-0.34, TOP, 0.3, HEM + 0.05, [(0, (255, 246, 228, 0.2)), (0.4, (255, 255, 255, 0.0)), (1, (0, 0, 0, 0.26))])
    c.fill_rect(-0.5, TOP - 0.05, 1, 0.6, g)
    h = c.linear(0, HEM - 0.1, 0, HEM + 0.05, [(0, (0, 0, 0, 0.0)), (1, (0, 0, 0, 0.2))])
    c.fill_rect(-0.5, HEM - 0.1, 1, 0.2, h)


def open_panels(c, L):
    colr = L["outer"]
    for side in (-1, 1):
        c.poly([side * 0.06, TOP - 0.02, side * 0.5, TOP - 0.02, side * 0.5, HEM + 0.05, side * 0.085, HEM + 0.05, side * 0.075, TOP + 0.14])
        c.fill(colr)
        c.begin()
        c.move_to(side * 0.075, TOP + 0.14)
        c.line_to(side * 0.085, HEM + 0.05)
        ink(c, LW * 0.8)
        c.poly([side * 0.06, TOP - 0.01, side * 0.17, TOP - 0.01, side * 0.08, TOP + 0.16])
        c.fill(shade(colr, 0.12))
        ink(c, LW * 0.5, (26, 20, 15, 0.5))


def apparel(c, L):
    top = L["top"]
    ts = L.get("topStyle")
    if ts == "coverall":
        line(c, 0, TOP + 0.04, 0, HEM, 0.014, alpha(shade(top, -0.5), 0.8))
        for s in (-1, 1):
            c.round_rect(s * 0.17 - 0.06, TOP + 0.1, 0.12, 0.09, 0.015)
            c.fill(shade(top, -0.1))
            ink(c, 0.012, (26, 20, 15, 0.5))
        c.poly([-0.13, TOP - 0.01, 0, TOP + 0.07, 0.13, TOP - 0.01, 0.08, TOP - 0.02, 0, TOP + 0.03, -0.08, TOP - 0.02])
        c.fill(shade(top, 0.1))
    if ts == "hoodie":
        c.round_rect(-0.17, -0.02, 0.34, 0.12, 0.05)
        c.fill(shade(top, -0.08))
        ink(c, 0.014, (26, 20, 15, 0.45))
        line(c, -0.05, TOP + 0.02, -0.06, TOP + 0.16, 0.016, shade(top, 0.5))
        line(c, 0.05, TOP + 0.02, 0.06, TOP + 0.16, 0.016, shade(top, 0.5))
    if ts in ("scrubs", "gown"):
        c.poly([-0.09, TOP - 0.01, 0, TOP + 0.11, 0.09, TOP - 0.01])
        c.fill(shade(top, -0.22))
        if ts == "scrubs":
            c.round_rect(-0.21, TOP + 0.13, 0.1, 0.08, 0.012)
            c.fill(shade(top, -0.08))
            ink(c, 0.012, (26, 20, 15, 0.4))
    if ts in ("shirt", "uniform"):
        for s in (-1, 1):
            c.poly([0, TOP + 0.05, s * 0.13, TOP - 0.01, s * 0.1, TOP + 0.08])
            c.fill(shade(top, 0.15))
            ink(c, 0.012, (26, 20, 15, 0.5))
        y = TOP + 0.1
        while y < HEM - 0.03:
            c.circle(0.005, y, 0.011)
            c.fill(alpha(shade(top, -0.5), 0.7))
            y += 0.07
        if ts == "uniform":
            c.poly([0.13, TOP + 0.1, 0.19, TOP + 0.1, 0.19, TOP + 0.16, 0.16, TOP + 0.19, 0.13, TOP + 0.16])
            c.fill("#c9a54a")
            ink(c, 0.01)
    if L.get("tie"):
        x = 0
        c.poly([x - 0.025, TOP + 0.04, x + 0.025, TOP + 0.04, x + 0.04, TOP + 0.3, x, TOP + 0.35, x - 0.04, TOP + 0.3])
        c.fill(L["tie"])
        ink(c, 0.012, (26, 20, 15, 0.6))
    if L.get("outer"):
        if L.get("outerStyle") in ("hivis", "vest"):
            oc = L["outer"]
            for s in (-1, 1):
                c.fill_rect(0.07 if s > 0 else -0.5, TOP - 0.1, 0.43, 0.6, oc)
            if L.get("outerStyle") == "hivis":
                for y in (-0.08, 0.04):
                    c.fill_rect(-0.5, y, 1, 0.035, (225, 225, 215, 0.85))
                c.fill_rect(-0.07, TOP - 0.1, 0.14, 0.6, top)
        else:
            open_panels(c, L)
    if L.get("bandolier"):
        c.save()
        x0, x1 = -0.24, 0.24
        c.begin()
        c.move_to(x0, TOP - 0.02)
        c.line_to(x1, HEM - 0.02)
        c.stroke(0.075, "#4a3222")
        t = 0.15
        while t < 0.9:
            x = x0 + (x1 - x0) * t
            y = TOP - 0.02 + (HEM - TOP) * t
            c.round_rect(x - 0.018, y - 0.03, 0.036, 0.05, 0.008)
            c.fill("#b8352c")
            c.fill_rect(x - 0.018, y + 0.012, 0.036, 0.012, "#c9a54a")
            t += 0.14
        c.restore()
    if L.get("backpack"):
        for s in (-1, 1):
            c.begin()
            c.move_to(s * 0.17, TOP - 0.01)
            c.line_to(s * 0.19, -0.02)
            c.stroke(0.055, shade(L["backpack"], -0.25))
    if L.get("belt"):
        c.fill_rect(-0.5, HEM - 0.065, 1, 0.05, "#5a3b24" if L["belt"] == "tools" else "#2a221c")
        c.fill_rect(-0.025, HEM - 0.068, 0.05, 0.056, "#b9a26a")
        if L["belt"] == "tools":
            for s in (-1, 1):
                c.round_rect(s * 0.2 - 0.05, HEM - 0.08, 0.1, 0.1, 0.02)
                c.fill("#6b4a2e")
                ink(c, 0.012, (26, 20, 15, 0.6))
            line(c, -0.21, HEM - 0.1, -0.23, HEM + 0.06, 0.02, "#8a6a44")
    if L.get("armband"):
        x = -0.29
        c.round_rect(x - 0.055, TOP + 0.09, 0.11, 0.07, 0.015)
        c.fill("#ecebe6")
        ink(c, 0.012, (26, 20, 15, 0.6))
        c.fill_rect(x - 0.008, TOP + 0.1, 0.016, 0.05, "#c0392f")
        c.fill_rect(x - 0.025, TOP + 0.117, 0.05, 0.016, "#c0392f")
    if L.get("patch"):
        c.ell(0.15, TOP + 0.12, 0.06, 0.03)
        c.fill("#e8e4d8")
        line(c, 0.12, TOP + 0.12, 0.18, TOP + 0.12, 0.01, "#3b5a8a")


# ------------------------------------------------------------------- head --

def cap_path(c, vol, edge, bumps):
    rx = HRX + vol
    ry = HRY + vol
    c.begin()
    n = 16 if bumps else 12
    for i in range(n + 1):
        th = math.pi - 0.12 + ((math.pi + 0.24) * i) / n
        k = (1 + (bumps if i % 2 else -bumps * 0.3)) if bumps else 1
        x = math.cos(th) * rx * k
        y = math.sin(th) * ry * k
        if i == 0:
            c.move_to(x, y)
        elif bumps:
            c.quad(math.cos(th - 0.1) * rx * (1 + bumps), math.sin(th - 0.1) * ry * (1 + bumps), x, y)
        else:
            c.line_to(x, y)
    c.line_to(HRX - 0.02, 0.0)
    c.bezier(HRX - 0.04, edge + 0.04, 0.15, edge, 0.06, edge + 0.005)
    c.bezier(0.02, edge + 0.03, -0.05, edge - 0.02, -0.12, edge + 0.005)
    c.bezier(-0.19, edge + 0.02, -(HRX - 0.04), edge + 0.05, -(HRX - 0.02), 0.0)
    c.close()


def hair_shade(c, color):
    g = c.linear(-0.2, -0.3, 0.2, 0.1, [(0, shade(color, 0.18)), (0.5, color), (1, shade(color, -0.18))])
    c.fill(g)


def hair_back(c, L):
    color = L["hairColor"]
    if L.get("hair") in ("long", "matted"):
        c.begin()
        c.move_to(-0.28, -0.05)
        c.bezier(-0.33, 0.15, -0.3, 0.3, -0.2, 0.36)
        c.line_to(0.2, 0.36)
        c.bezier(0.3, 0.3, 0.33, 0.15, 0.28, -0.05)
        c.close()
        hair_shade(c, shade(color, -0.08))
        ink(c, LW)
    if L.get("topStyle") == "hoodie":
        c.ell(0, 0.27, 0.25, 0.07)
        c.fill(shade(L["top"], -0.12))
        ink(c, LW * 0.8)


def hair_front(c, L, r, quirk):
    color = L["hairColor"]
    h = L.get("hair")
    if not h or h == "bald":
        c.ell(-0.07, -0.14, 0.07, 0.04, -0.4)
        c.fill((255, 255, 255, 0.12))
        return
    if h == "balding":
        c.save()
        c.cap = "round"
        for s in (-1, 1):
            for _ in range(4):
                x0 = s * (0.18 + r() * 0.05)
                y0 = -0.14 + r() * 0.12
                c.begin()
                c.move_to(x0, y0)
                c.quad(x0 + s * 0.06, y0 + 0.05, x0 + s * 0.05 + (r() - 0.5) * 0.05, y0 + 0.13)
                c.stroke(0.03, color)
        c.restore()
        return
    vol, edge, bumps = 0.03, -0.12, 0
    if h == "buzz":
        vol, edge = 0.01, -0.15
    elif h == "twists":
        vol, edge, bumps = 0.045, -0.15, 0.05
    elif h == "curly":
        vol, edge, bumps = 0.06, -0.13, 0.07
    elif h in ("messy", "matted"):
        vol, edge, bumps = 0.035, -0.1, 0.06
    elif h in ("ponytail", "long"):
        vol, edge = 0.025, -0.16
    cap_path(c, vol, edge, bumps)
    if h == "buzz":
        c.fill(alpha(color, 0.78))
    else:
        hair_shade(c, color)
    if h in ("twists", "curly"):
        c.save()
        c.clip()
        dot = alpha(shade(color, 0.28 if h == "curly" else 0.18), 0.8)
        for _ in range(22):
            a = r() * math.pi * 2
            d = math.sqrt(r()) * 0.27
            c.circle(math.cos(a) * d, math.sin(a) * d * 1.05 - 0.08, 0.03 if h == "curly" else 0.018)
            c.fill(dot)
        c.restore()
        if not quirk:
            # the prototype strokes whatever path is current here, which is the last dot; the outline of
            # the hair is what was meant, and what every other style has
            cap_path(c, vol, edge, bumps)
    ink(c, LW)
    if h in ("ponytail", "long"):
        line(c, 0.0, -0.285, 0.02, -0.17, 0.014, alpha(shade(color, -0.5), 0.6))


def hat(c, L):
    if not L.get("hat"):
        return
    color = L["hatColor"]
    if L["hat"] == "cap":
        cap_path(c, 0.035, -0.1, 0)
        c.fill(color)
        g = c.linear(-0.2, -0.3, 0.2, 0, [(0, (255, 255, 255, 0.18)), (1, (0, 0, 0, 0.18))])
        c.fill(g)
        ink(c, LW)
        c.circle(0, -0.29, 0.02)
        c.fill(shade(color, -0.2))
        c.ell(0, -0.085, 0.215, 0.075)
        c.fill(shade(color, -0.18))
        ink(c, LW)
        c.ell(0, -0.06, 0.2, 0.035)
        c.fill((0, 0, 0, 0.15))
    elif L["hat"] == "beanie":
        cap_path(c, 0.035, -0.1, 0)
        c.fill(color)
        ink(c, LW)
        c.save()
        c.clip()
        y = -0.17
        c.fill_rect(-0.4, y, 0.8, 0.09, shade(color, -0.12))
        x = -0.3
        while x < 0.3:
            c.begin()
            c.move_to(x, y)
            c.line_to(x, y + 0.09)
            c.stroke(0.01, alpha(shade(color, -0.4), 0.6))
            x += 0.035
        c.restore()
        line(c, -0.3, y, 0.3, y, 0.014, alpha(shade(color, -0.45), 0.7))


def face(c, L):
    eyes = [-0.088, 0.088]
    skin = L["skin"]
    for x in (-0.14, 0.14):
        c.circle(x, 0.075, 0.05)
        c.fill((214, 90, 80, 0.13))
    bc = L.get("browColor") or shade(L.get("hairColor") or "#333333", -0.3)
    for x in eyes:
        line(c, x - 0.04, -0.072, x + 0.04, -0.08 + (0.004 if x > 0 else 0), 0.024, bc)
        c.ell(x, -0.01, 0.027, 0.034)
        c.fill(EYE)
        c.circle(x + 0.009, -0.021, 0.0085)
        c.fill((255, 255, 255, 0.75))
    c.ell(0, 0.058, 0.03, 0.017)
    c.fill((0, 0, 0, 0.13))
    line(c, -0.035, 0.132, 0.035, 0.128, 0.017, alpha(shade(skin, -0.45), 0.7))
    if L.get("beard"):
        bcol = L.get("beardColor") or L["hairColor"]
        c.begin()
        c.move_to(-0.245, 0.0)
        c.bezier(-0.23, 0.2, -0.1, 0.28, 0, 0.28)
        c.bezier(0.1, 0.28, 0.23, 0.2, 0.245, 0.0)
        c.quad(0.2, 0.06, 0.07, 0.08)
        c.quad(0, 0.1, -0.07, 0.08)
        c.quad(-0.2, 0.06, -0.245, 0.0)
        c.close()
        if L["beard"] == "stubble":
            c.fill(alpha(bcol, 0.32))
        else:
            hair_shade(c, bcol)
            ink(c, LW * 0.7, (26, 20, 15, 0.55))
            line(c, -0.03, 0.14, 0.03, 0.14, 0.017, alpha(shade(bcol, -0.5), 0.8))
    if L.get("mustache"):
        c.round_rect(-0.075, 0.085, 0.15, 0.04, 0.02)
        c.fill(L.get("beardColor") or L["hairColor"])
        ink(c, 0.012, (26, 20, 15, 0.5))
    if L.get("glasses"):
        for x in eyes:
            c.circle(x, -0.01, 0.058)
            c.fill((220, 235, 245, 0.18))
            c.stroke(0.017, "#2a2420")
        line(c, -0.03, -0.015, 0.03, -0.015, 0.014, "#2a2420")


def draw_head(c, L, seed):
    r = rng(seed + 13)
    c.save()
    c.translate(0, HEAD_Y)
    hair_back(c, L)
    for s in (-1, 1):
        c.ell(s * 0.245, 0.015, 0.045, 0.062)
        c.fill(shade(L["skin"], -0.05))
        ink(c, LW * 0.8)
    c.ell(0, 0, HRX, HRY)
    c.fill(L["skin"])
    g = c.radial(-0.08, -0.1, 0.02, 0, 0, 0.3, [(0, (255, 244, 228, 0.2)), (0.6, (255, 255, 255, 0.0)), (1, (0, 0, 0, 0.2))])
    c.fill(g)
    ink(c, LW)
    face(c, L)
    hair_front(c, L, r, QUIRK[0])
    hat(c, L)
    c.restore()


QUIRK = [False]


def draw_figure(c, L):
    seed = int(L.get("seed", 1))
    torso_path(c)
    c.fill(L["top"])
    c.save()
    c.clip()
    apparel(c, L)
    shade_torso(c)
    c.restore()
    torso_path(c)
    ink(c, LW)
    draw_head(c, L, seed)


def draw_portrait(look, tint="#3a3630", size=SIZE, ss=SUPERSAMPLE, quirk=False):
    """The portrait of `look` on a backdrop tinted `tint`, as an RGBA image `size` pixels square."""
    QUIRK[0] = quirk
    c = Canvas(size, size, ss)
    top, bottom = hex_rgb(shade(tint, 0.1)), hex_rgb(shade(tint, -0.35))
    t = ((np.arange(c.H) + 0.5) / c.H)[:, None]
    rows = np.array(top, np.float32)[None, :] * (1 - t) + np.array(bottom, np.float32)[None, :] * t
    c.buf[..., :3] = (rows / 255.0)[:, None, :]
    c.buf[..., 3] = 1.0
    s = size * 1.05
    c.set_transform(s, size / 2.0, size * 0.47 - HEAD_Y * s)
    draw_figure(c, look)
    return c.image()


# -------------------------------------------------------------------- main --

def load_json(path):
    with open(path) as f:
        return json.load(f)


def authored():
    people = load_json(MAP)["people"]
    return [(p["id"], p["look"], p["tint"]) for p in people]


def mean_abs_diff(a, b):
    x = np.asarray(a.convert("RGB"), np.float32)
    y = np.asarray(b.convert("RGB"), np.float32)
    return float(np.abs(x - y).mean())


def check():
    """Draws the six authored portraits from their looks and compares them with the files."""
    worst = 0.0
    for pid, look, tint in authored():
        img = draw_portrait(look, tint, quirk=True)
        ref = Image.open(os.path.join(OUT, pid + ".png")).convert("RGBA")
        d = mean_abs_diff(img, ref)
        worst = max(worst, d)
        print("%-8s mean difference %.2f of 255" % (pid, d))
    print("worst %.2f" % worst)
    return worst


def sheet(path, images, cols, cell=SIZE):
    rows = (len(images) + cols - 1) // cols
    img = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 255))
    for i, im in enumerate(images):
        img.paste(im.resize((cell, cell), Image.LANCZOS) if im.size != (cell, cell) else im, ((i % cols) * cell, (i // cols) * cell))
    img.save(path)


def main():
    ap = argparse.ArgumentParser(description="Draws the portraits of the generated survivors.")
    ap.add_argument("--check", action="store_true", help="compare the drawing with the six authored portraits")
    ap.add_argument("--sheet", metavar="PNG", help="write a contact sheet of the sixteen and the six authored")
    ap.add_argument("--out", metavar="DIR", default=OUT, help="where the sixteen go (default assets/portraits)")
    args = ap.parse_args()
    if args.check:
        check()
        return 0
    data = load_json(DATA)
    entries = data["portrait_looks"]
    paths = data["portraits"]
    if len(entries) != len(paths):
        print("recruits.json: %d portrait_looks for %d portraits" % (len(entries), len(paths)), file=sys.stderr)
        return 1
    os.makedirs(args.out, exist_ok=True)
    images = []
    for entry, res_path in zip(entries, paths):
        img = draw_portrait(entry["look"], entry["tint"])
        images.append(img)
        name = os.path.basename(res_path)
        if args.sheet is None:
            img.save(os.path.join(args.out, name), optimize=False)
    if args.sheet:
        both = images + [Image.open(os.path.join(OUT, pid + ".png")).convert("RGBA") for pid, _, _ in authored()]
        sheet(args.sheet, both, 8)
    return 0


if __name__ == "__main__":
    sys.exit(main())
