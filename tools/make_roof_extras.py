#!/usr/bin/env python3
"""Draws the ROOF EXTRAS of the town (WORLD3): the roofs that are not the kit's three gables, and what stands on a roof or hangs off a front.

    python3 tools/make_roof_extras.py            # writes assets/town/roof/roof_extras.png and assets/data/roof_extras.json

No reference pictures, no tools off the machine, deterministic (a fixed seed: the same script writes the same files). Seen from above, lit from the top left (the soft shadow falls to the south
east), a dark brown outline (#221a13), muted colours: the look of the art kit (tools/make_town_art.py). 128 px to the tile.

What it makes, in one sheet (so that a roof is still one draw call: scripts/render/roof_atlas.gd puts the sheet in the kit's atlas):
  fills (seamless, 128 x 128): flat roofs (tar, gravel, concrete, corrugated metal, green membrane, sand), standing seam metal, glass, canopy white, porch shingle, charred shingles, rubble, a hole in the
      roof, tarps (blue, green, orange)
  edges: the parapet of a flat roof (a strip along x, along y, a corner), the band of a canopy
  decor (transparent): chimney pots, a flue pipe, a vent pipe, a roof fan, two air conditioners, a dish, a solar panel, a skylight, a hatch, a water tank, an aerial, a mast with a dish, a dome (a silo),
      posts, a stack of tyres
  fronts: awnings (red, green, blue, yellow; striped; one tile wide, a tile and a half deep), a pergola, signs (an icon on a plate: bread, a cross, a wrench, a cup, scissors, a cart, a coin, a pump, a book,
      a paper, a drop, a mug, a ham, a flower, a car, a letter, a film, a bed, a plug, a hanger)

The JSON gives the rectangle of every piece in the sheet (without its 8 px of padding) and its size in tiles.
"""
import json
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PNG = os.path.join(ROOT, "assets/town/roof/roof_extras.png")
OUT_JSON = os.path.join(ROOT, "assets/data/roof_extras.json")
T = 128
PAD = 8
INK = (34, 26, 19, 255)
SS = 2  # supersampling for the drawn decor
rng = np.random.default_rng(31337)
random.seed(31337)


def col(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# --------------------------------------------------------------------------- seamless noise --
def tile_noise(size, sigma, seed):
    r = np.random.default_rng(seed)
    n = r.standard_normal((size, size))
    f = np.fft.fft2(n)
    ky = np.fft.fftfreq(size)[:, None]
    kx = np.fft.fftfreq(size)[None, :]
    g = np.exp(-(kx * kx + ky * ky) * (2 * math.pi * sigma) ** 2 / 2)
    out = np.real(np.fft.ifft2(f * g))
    out -= out.mean()
    out /= (out.std() + 1e-9)
    return out


def fill_img(base, noise_amp=6, sigma=5, seed=1, speck=0.0, lines=None):
    """A seamless T x T opaque tile from a base colour: soft noise, specks, and lines [(axis, pos, width, delta)]."""
    a = np.zeros((T, T, 3), dtype=np.float64)
    a[:] = base
    n = tile_noise(T, sigma, seed)
    a += n[:, :, None] * noise_amp
    n2 = tile_noise(T, 1.2, seed + 7)
    a += n2[:, :, None] * (noise_amp * 0.35)
    if speck > 0:
        r = np.random.default_rng(seed + 99)
        m = r.random((T, T))
        a[m < speck] += 22
        a[m > 1 - speck] -= 22
    for ax, pos, w, d in (lines or []):
        for k in range(w):
            p = (pos + k) % T
            if ax == "h":
                a[p, :, :] += d
            else:
                a[:, p, :] += d
    a = np.clip(a, 0, 255).astype(np.uint8)
    im = Image.fromarray(a).convert("RGBA")
    return im


def wrap_pad(im):
    """T x T seamless tile -> (T + 2 PAD) square with the tile's own opposite edges all round."""
    w = T + 2 * PAD
    out = Image.new("RGBA", (w, w))
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            out.paste(im, (PAD + ox * T, PAD + oy * T))
    return out


# ----------------------------------------------------------------------------- drawing helpers --
class Cv:
    """A supersampled RGBA canvas of w x h px (in the sheet's px): shapes are drawn at SS x and reduced."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def s(self, v):
        return v * SS

    @staticmethod
    def _fill(fill):
        if fill is None or (len(fill) == 4 and fill[3] == 0):
            return None
        return fill + (255,) if len(fill) == 3 else fill

    def rect(self, x0, y0, x1, y1, fill, outline=INK, ow=3, r=0):
        box = [self.s(x0), self.s(y0), self.s(x1), self.s(y1)]
        if r > 0:
            self.d.rounded_rectangle(box, radius=self.s(r), fill=self._fill(fill), outline=outline if ow else None, width=self.s(ow))
        else:
            self.d.rectangle(box, fill=self._fill(fill), outline=outline if ow else None, width=self.s(ow))

    def ellipse(self, x0, y0, x1, y1, fill, outline=INK, ow=3):
        self.d.ellipse([self.s(x0), self.s(y0), self.s(x1), self.s(y1)], fill=self._fill(fill), outline=outline if ow else None, width=self.s(ow))

    def line(self, pts, fill, w=2):
        self.d.line([(self.s(x), self.s(y)) for x, y in pts], fill=fill + (255,) if len(fill) == 3 else fill, width=self.s(w))

    def poly(self, pts, fill, outline=INK, ow=3):
        p = [(self.s(x), self.s(y)) for x, y in pts]
        self.d.polygon(p, fill=fill + (255,) if len(fill) == 3 else fill)
        if outline and ow:
            self.d.line(p + [p[0]], fill=outline, width=self.s(ow), joint="curve")

    def done(self, shadow=True, shadow_off=(5, 8), shadow_a=70):
        im = self.im.resize((self.w, self.h), Image.LANCZOS)
        if shadow:
            alpha = im.split()[3]
            sh = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
            blur = alpha.filter(ImageFilter.GaussianBlur(3))
            sh_alpha = blur.point(lambda v: int(v * shadow_a / 255))
            sh.putalpha(sh_alpha)
            out = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
            out.paste(sh, shadow_off, sh)
            out.alpha_composite(im)
            return out
        return im


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3])


def bevel(cv, x0, y0, x1, y1, base, ow=3, r=0):
    """A box lit from the top left: light edge on the top and left, a dark one below and on the right."""
    cv.rect(x0, y0, x1, y1, base, ow=ow, r=r)
    cv.line([(x0 + ow + 1, y0 + ow + 1), (x1 - ow - 1, y0 + ow + 1)], shade(base, 1.25) + (255,), 2)
    cv.line([(x0 + ow + 1, y0 + ow + 1), (x0 + ow + 1, y1 - ow - 1)], shade(base, 1.2) + (255,), 2)
    cv.line([(x0 + ow + 1, y1 - ow - 1), (x1 - ow - 1, y1 - ow - 1)], shade(base, 0.72) + (255,), 2)
    cv.line([(x1 - ow - 1, y0 + ow + 1), (x1 - ow - 1, y1 - ow - 1)], shade(base, 0.76) + (255,), 2)


# ---------------------------------------------------------------------------------- the pieces --
pieces = []  # (name, image (w x h, no pad), seamless, size in tiles (w, h), pad kind)


def add(name, im, seamless=False, tiles=None):
    w, h = im.size
    pieces.append({"name": name, "im": im, "seamless": seamless, "tiles": tiles or (round(w / T, 3), round(h / T, 3))})


# ---- fills
def seam_lines(period, w=2, d=-18, ax="h"):
    return [(ax, k * period, w, d) for k in range(T // period)]


add("flat_tar", fill_img((104, 100, 94), 5, 6, 11, 0.004, seam_lines(64, 2, -26, "h") + seam_lines(64, 1, 12, "h")), True)
add("flat_gravel", fill_img((132, 127, 118), 7, 3, 12, 0.07), True)
add("flat_concrete", fill_img((150, 150, 146), 4, 7, 13, 0.01, [("h", 0, 2, -24), ("v", 0, 2, -24), ("h", 64, 1, -12), ("v", 64, 1, -12)]), True)
add("flat_green", fill_img((88, 112, 90), 6, 7, 14, 0.006, seam_lines(64, 2, -20, "v")), True)
add("flat_sand", fill_img((176, 160, 128), 5, 6, 15, 0.015, seam_lines(64, 2, -16, "h")), True)


def metal_fill(base, period, seed, vertical=True, rust=0.0):
    a = np.zeros((T, T, 3), dtype=np.float64)
    a[:] = base
    xs = np.arange(T)
    prof = np.sin(xs / period * 2 * math.pi)
    for i in range(T):
        v = prof[i]
        if vertical:
            a[:, i, :] += v * 14
        else:
            a[i, :, :] += v * 14
    a += tile_noise(T, 6, seed)[:, :, None] * (5 + rust * 12)
    if rust > 0:
        m = tile_noise(T, 4, seed + 3) > 1.1
        a[m] += np.array([26, 6, -10])
    a = np.clip(a, 0, 255).astype(np.uint8)
    return Image.fromarray(a).convert("RGBA")


add("flat_metal", metal_fill((116, 122, 126), 16, 21, True, 0.2), True)
add("metal_rib", metal_fill((126, 104, 90), 32, 22, True, 0.6), True)
add("metal_rib_h", metal_fill((128, 132, 130), 32, 23, False, 0.15), True)

# glass (greenhouse): pale panes in a frame, a glint
g = fill_img((152, 186, 190), 4, 8, 31, 0.0)
gd = ImageDraw.Draw(g)
for k in (0, 64):
    gd.rectangle([k, 0, k + 3, T], fill=(88, 100, 98, 255))
    gd.rectangle([0, k, T, k + 3], fill=(88, 100, 98, 255))
for k in (0, 64):
    gd.line([(k + 14, k + 30), (k + 38, k + 8)], fill=(214, 236, 238, 255), width=3)
    gd.line([(k + 26, k + 40), (k + 50, k + 18)], fill=(200, 226, 230, 255), width=2)
add("glass", g, True)

# canopy white (a gas station's): off-white panels
add("canopy_white", fill_img((204, 202, 194), 3, 8, 32, 0.0, [("h", 0, 3, -30), ("v", 0, 3, -30), ("h", 64, 1, -14), ("v", 64, 1, -14)]), True)
# porch shingle: small brown courses
ps = fill_img((112, 86, 64), 5, 4, 33, 0.01)
pd = ImageDraw.Draw(ps)
for y in range(0, T, 16):
    pd.line([(0, y), (T, y)], fill=(70, 52, 38, 255), width=2)
    off = 0 if (y // 16) % 2 == 0 else 16
    for x in range(off, T, 32):
        pd.line([(x, y), (x, y + 16)], fill=(70, 52, 38, 255), width=2)
add("porch_shingle", ps, True)

# charred shingles: dark, courses, soot
bs = fill_img((46, 40, 37), 6, 5, 34, 0.02)
bd = ImageDraw.Draw(bs)
for y in range(0, T, 16):
    bd.line([(0, y), (T, y)], fill=(18, 14, 12, 255), width=2)
    off = 0 if (y // 16) % 2 == 0 else 16
    for x in range(off, T, 32):
        bd.line([(x, y), (x, y + 16)], fill=(18, 14, 12, 255), width=2)
add("burnt", bs, True)

# rubble: debris, beams
rb = fill_img((70, 62, 54), 9, 3, 35, 0.06)
rd = ImageDraw.Draw(rb)
r2 = random.Random(5)
for k in range(9):
    x, y = r2.randint(0, T), r2.randint(0, T)
    a = r2.uniform(0, math.pi)
    L = r2.randint(26, 60)
    dx, dy = math.cos(a) * L / 2, math.sin(a) * L / 2
    for ox in (-T, 0, T):
        for oy in (-T, 0, T):
            rd.line([(x - dx + ox, y - dy + oy), (x + dx + ox, y + dy + oy)], fill=(24, 18, 14, 255), width=7)
            rd.line([(x - dx + ox - 1, y - dy + oy - 2), (x + dx + ox - 1, y + dy + oy - 2)], fill=(92, 70, 48, 255), width=2)
add("rubble", rb, True)

# a hole in the roof: the dark of a burnt floor with joists
ho = fill_img((26, 22, 20), 4, 4, 36, 0.01)
hd = ImageDraw.Draw(ho)
for x in range(8, T, 32):
    hd.rectangle([x, 0, x + 9, T], fill=(58, 42, 30, 255), outline=(14, 10, 8, 255), width=2)
add("hole", ho, True)


def tarp(base, seed):
    im = fill_img(base, 4, 8, seed, 0.0)
    d = ImageDraw.Draw(im)
    dark = shade(base, 0.62) + (255,)
    light = shade(base, 1.2) + (255,)
    for p in [(0, 32, 128, 44), (0, 84, 128, 76)]:
        d.line([(p[0], p[1]), (p[2], p[3])], fill=dark, width=3)
        d.line([(p[0], p[1] - 3), (p[2], p[3] - 3)], fill=light, width=2)
    d.line([(40, 0), (52, 128)], fill=dark, width=3)
    d.line([(100, 0), (92, 128)], fill=dark, width=3)
    for gx, gy in [(10, 10), (118, 10), (10, 118), (118, 118), (64, 10), (64, 118)]:
        d.ellipse([gx - 4, gy - 4, gx + 4, gy + 4], fill=(180, 176, 160, 255), outline=(40, 34, 28, 255), width=2)
    return im


add("tarp_blue", tarp((70, 110, 150), 41), True)
add("tarp_green", tarp((82, 112, 78), 42), True)
add("tarp_orange", tarp((178, 108, 52), 43), True)

# ---- parapet strips (flat roofs' edges): lit from the top left
def parapet(w, h, horizontal):
    cv = Cv(w, h)
    base = (176, 174, 168)
    cv.rect(1, 1, w - 1, h - 1, base, ow=3)
    if horizontal:
        cv.line([(4, 4), (w - 4, 4)], (214, 212, 204, 255), 2)
        cv.line([(4, h - 5), (w - 4, h - 5)], (118, 116, 110, 255), 2)
    else:
        cv.line([(4, 4), (4, h - 4)], (214, 212, 204, 255), 2)
        cv.line([(w - 5, 4), (w - 5, h - 4)], (118, 116, 110, 255), 2)
    return cv.done(shadow=False)


add("parapet_h", parapet(128, 22, True), False, (1.0, 22 / 128))
add("parapet_v", parapet(22, 128, False), False, (22 / 128, 1.0))
add("parapet_c", parapet(22, 22, True), False, (22 / 128, 22 / 128))


def band(w, h, c1, c2, horizontal=True):
    cv = Cv(w, h)
    cv.rect(0, 0, w, h, c1, ow=3)
    n = 0
    step = 24
    if horizontal:
        for x in range(0, w, step):
            if (x // step) % 2 == 1:
                cv.rect(x, 2, min(w - 2, x + step), h - 2, c2, outline=None, ow=0)
        cv.rect(0, 0, w, h, (0, 0, 0, 0), ow=3)
    else:
        for y in range(0, h, step):
            if (y // step) % 2 == 1:
                cv.rect(2, y, w - 2, min(h - 2, y + step), c2, outline=None, ow=0)
        cv.rect(0, 0, w, h, (0, 0, 0, 0), ow=3)
    return cv.done(shadow=False)


add("canopy_band_h", band(128, 22, col("b04a42"), col("e2dcd0"), True), False, (1.0, 22 / 128))
add("canopy_band_v", band(22, 128, col("b04a42"), col("e2dcd0"), False), False, (22 / 128, 1.0))

# ---- decor
def chimney_flue():
    cv = Cv(96, 96)
    cv.rect(24, 24, 72, 72, (126, 124, 120), ow=3, r=6)
    cv.ellipse(36, 36, 60, 60, (36, 34, 32), outline=INK, ow=3)
    cv.ellipse(42, 40, 54, 52, (12, 10, 10), outline=None, ow=0)
    return cv.done()


def vent_pipe():
    cv = Cv(48, 48)
    cv.ellipse(12, 12, 36, 36, (150, 150, 146), ow=3)
    cv.ellipse(18, 18, 30, 30, (30, 28, 26), outline=INK, ow=2)
    return cv.done()


def roof_fan():
    cv = Cv(72, 72)
    cv.ellipse(8, 8, 64, 64, (170, 172, 170), ow=3)
    for k in range(8):
        a = k / 8 * 2 * math.pi
        cv.line([(36, 36), (36 + math.cos(a) * 24, 36 + math.sin(a) * 24)], (96, 100, 100, 255), 2)
    cv.ellipse(28, 28, 44, 44, (120, 124, 124), ow=2)
    return cv.done()


def ac_unit(w, h):
    cv = Cv(w, h)
    bevel(cv, 4, 4, w - 4, h - 4, (176, 180, 182), ow=3, r=4)
    n = w // 96
    for i in range(max(1, n)):
        cx = 4 + (w - 8) * (i + 0.5) / max(1, n)
        cy = h / 2
        rr = min(h - 16, 70) / 2
        cv.ellipse(cx - rr, cy - rr, cx + rr, cy + rr, (80, 84, 86), outline=INK, ow=2)
        for k in range(6):
            a = k / 6 * 2 * math.pi
            cv.line([(cx, cy), (cx + math.cos(a) * rr * 0.8, cy + math.sin(a) * rr * 0.8)], (150, 154, 156, 255), 2)
    return cv.done()


def dish():
    cv = Cv(96, 96)
    cv.ellipse(10, 10, 78, 78, (214, 214, 208), ow=3)
    cv.ellipse(22, 22, 66, 66, (186, 188, 184), outline=(120, 120, 116, 255), ow=2)
    cv.line([(44, 44), (72, 20)], (60, 60, 58, 255), 4)
    cv.ellipse(66, 14, 78, 26, (60, 60, 58), outline=INK, ow=2)
    return cv.done()


def solar(w, h):
    cv = Cv(w, h)
    cv.rect(4, 4, w - 4, h - 4, (44, 62, 96), ow=3)
    for x in range(4 + 32, w - 4, 32):
        cv.line([(x, 6), (x, h - 6)], (140, 156, 190, 255), 2)
    for y in range(4 + 32, h - 4, 32):
        cv.line([(6, y), (w - 6, y)], (140, 156, 190, 255), 2)
    cv.line([(10, 10), (30, 8)], (120, 150, 200, 255), 3)
    return cv.done()


def skylight():
    cv = Cv(128, 128)
    cv.rect(14, 14, 114, 114, (92, 100, 104), ow=3)
    cv.rect(24, 24, 104, 104, (160, 196, 204), ow=2)
    cv.line([(64, 24), (64, 104)], (96, 106, 110, 255), 3)
    cv.line([(24, 64), (104, 64)], (96, 106, 110, 255), 3)
    cv.line([(32, 40), (52, 30)], (226, 244, 246, 255), 3)
    return cv.done()


def hatch():
    cv = Cv(96, 96)
    bevel(cv, 10, 10, 86, 86, (126, 124, 118), ow=3, r=3)
    cv.ellipse(70, 42, 80, 52, (60, 58, 54), outline=INK, ow=2)
    return cv.done()


def water_tank():
    cv = Cv(176, 176)
    cv.ellipse(10, 10, 166, 166, (156, 128, 98), ow=4)
    cv.ellipse(26, 26, 150, 150, (176, 148, 116), outline=(110, 86, 62, 255), ow=3)
    for k in range(10):
        a = k / 10 * 2 * math.pi
        cv.line([(88, 88), (88 + math.cos(a) * 62, 88 + math.sin(a) * 62)], (120, 94, 70, 255), 3)
    cv.ellipse(70, 70, 106, 106, (96, 74, 54), outline=INK, ow=3)
    return cv.done()


def aerial():
    cv = Cv(64, 64)
    cv.line([(10, 54), (54, 10)], (150, 152, 150, 255), 4)
    for k in range(4):
        x = 16 + k * 9
        y = 48 - k * 9
        cv.line([(x - 8, y - 8), (x + 8, y + 8)], (178, 180, 176, 255), 3)
    cv.ellipse(6, 50, 18, 62, (70, 70, 68), outline=INK, ow=2)
    return cv.done()


def mast_dish():
    cv = Cv(192, 192)
    cv.ellipse(12, 12, 150, 150, (220, 220, 214), ow=4)
    cv.ellipse(40, 40, 122, 122, (188, 190, 186), outline=(120, 120, 116, 255), ow=3)
    cv.line([(81, 81), (150, 30)], (70, 70, 68, 255), 6)
    cv.ellipse(140, 20, 164, 44, (70, 70, 68), outline=INK, ow=3)
    cv.ellipse(70, 70, 92, 92, (200, 60, 50), outline=INK, ow=3)
    return cv.done()


def dome():
    cv = Cv(208, 208)
    cv.ellipse(6, 6, 202, 202, (150, 154, 156), ow=5)
    cv.ellipse(24, 24, 184, 184, (176, 180, 182), outline=(112, 116, 118, 255), ow=3)
    cv.ellipse(54, 46, 146, 124, (206, 210, 212), outline=None, ow=0)
    cv.ellipse(86, 86, 122, 122, (94, 98, 100), outline=INK, ow=4)
    return cv.done()


def post():
    cv = Cv(40, 40)
    cv.ellipse(8, 8, 32, 32, (146, 112, 78), ow=3)
    cv.ellipse(14, 14, 26, 26, (172, 136, 98), outline=None, ow=0)
    return cv.done()


def tyres():
    cv = Cv(112, 112)
    for (x, y) in [(10, 10), (54, 14), (28, 54)]:
        cv.ellipse(x, y, x + 48, y + 48, (40, 38, 36), ow=3)
        cv.ellipse(x + 14, y + 14, x + 34, y + 34, (96, 94, 90), outline=INK, ow=2)
    return cv.done()


add("chimney_flue", chimney_flue(), False, (0.75, 0.75))
add("vent_pipe", vent_pipe(), False, (0.375, 0.375))
add("roof_fan", roof_fan(), False, (0.5625, 0.5625))
add("ac_small", ac_unit(96, 96), False, (0.75, 0.75))
add("ac_big", ac_unit(192, 96), False, (1.5, 0.75))
add("dish", dish(), False, (0.75, 0.75))
add("solar", solar(192, 96), False, (1.5, 0.75))
add("solar_big", solar(256, 128), False, (2.0, 1.0))
add("skylight", skylight(), False, (1.0, 1.0))
add("hatch", hatch(), False, (0.75, 0.75))
add("water_tank", water_tank(), False, (1.375, 1.375))
add("aerial", aerial(), False, (0.5, 0.5))
add("mast_dish", mast_dish(), False, (1.5, 1.5))
add("dome", dome(), False, (1.625, 1.625))
add("post", post(), False, (0.3125, 0.3125))
add("tyres", tyres(), False, (0.875, 0.875))


# ---- awnings: a tile wide, a tile and a half deep; stripes run out from the wall; a darker lip at the outer edge, a scallop
def awning(c1, c2):
    w, h = 128, 192
    cv = Cv(w, h)
    cv.rect(0, 0, w, h, c1, ow=3)
    for k in range(4):
        x0 = k * 32
        if k % 2 == 1:
            cv.rect(x0, 3, x0 + 32, h - 3, c2, outline=None, ow=0)
    # a soft light on the high edge and a shade near the lip
    cv.line([(3, 6), (w - 3, 6)], (255, 255, 255, 70), 3)
    cv.rect(0, h - 30, w, h, shade(c1, 0.8), ow=3)
    for k in range(4):
        x0 = k * 32
        cv.rect(x0, h - 30, x0 + 32, h, c2 if k % 2 == 1 else shade(c1, 0.8), ow=0, outline=None)
    for k in range(5):
        cv.line([(k * 32, 4), (k * 32, h - 4)], (0, 0, 0, 30), 2)
    cv.rect(0, h - 30, w, h, (0, 0, 0, 0), ow=3)
    return cv.done(shadow=True, shadow_off=(4, 8), shadow_a=80)


add("awning_red", awning(col("a84a42"), col("e6e0d2")), False, (1.0, 1.5))
add("awning_green", awning(col("4d7a56"), col("e6e0d2")), False, (1.0, 1.5))
add("awning_blue", awning(col("48648c"), col("e6e0d2")), False, (1.0, 1.5))
add("awning_yellow", awning(col("c29a3c"), col("efe6c8")), False, (1.0, 1.5))


def pergola():
    cv = Cv(128, 128)
    for y in range(8, 128, 24):
        cv.rect(0, y, 128, y + 12, (126, 96, 66), ow=3)
    return cv.done(shadow=True, shadow_off=(4, 7), shadow_a=70)


add("pergola", pergola(), False, (1.0, 1.0))


# ---- signs: a plate with an icon
def plate(bg, drawer):
    cv = Cv(96, 96)
    bevel(cv, 6, 6, 90, 90, bg, ow=4, r=10)
    drawer(cv)
    return cv.done(shadow=True, shadow_off=(4, 6), shadow_a=90)


W_ = (238, 232, 218)
D_ = (44, 34, 28)


def ic_bread(cv):
    cv.ellipse(20, 32, 76, 66, (208, 156, 84), outline=D_ + (255,), ow=3)
    for x in (34, 46, 58):
        cv.line([(x, 38), (x - 4, 60)], D_ + (255,), 3)


def ic_cross(cv):
    cv.rect(38, 18, 58, 78, (232, 232, 224), outline=D_ + (255,), ow=3)
    cv.rect(18, 38, 78, 58, (232, 232, 224), outline=D_ + (255,), ow=3)
    cv.rect(39, 39, 57, 57, (232, 232, 224), outline=None, ow=0)


def ic_wrench(cv):
    cv.line([(28, 70), (66, 30)], W_ + (255,), 9)
    cv.ellipse(58, 18, 80, 40, W_, outline=D_ + (255,), ow=3)
    cv.ellipse(66, 22, 78, 32, (80, 80, 80), outline=None, ow=0)
    cv.ellipse(20, 62, 36, 78, W_, outline=D_ + (255,), ow=3)


def ic_cup(cv):
    cv.rect(26, 34, 60, 66, W_, outline=D_ + (255,), ow=3, r=4)
    cv.ellipse(56, 40, 74, 58, (0, 0, 0, 0), outline=W_ + (255,), ow=5)
    cv.line([(32, 24), (32, 30)], W_ + (255,), 3)
    cv.line([(44, 22), (44, 30)], W_ + (255,), 3)


def ic_scissors(cv):
    cv.line([(24, 24), (72, 72)], W_ + (255,), 6)
    cv.line([(72, 24), (24, 72)], W_ + (255,), 6)
    cv.ellipse(16, 62, 34, 80, (0, 0, 0, 0), outline=W_ + (255,), ow=4)
    cv.ellipse(62, 62, 80, 80, (0, 0, 0, 0), outline=W_ + (255,), ow=4)


def ic_cart(cv):
    cv.line([(18, 28), (30, 28), (38, 58), (70, 58), (76, 36), (34, 36)], W_ + (255,), 5)
    cv.ellipse(36, 64, 48, 76, W_, outline=D_ + (255,), ow=2)
    cv.ellipse(62, 64, 74, 76, W_, outline=D_ + (255,), ow=2)


def ic_coin(cv):
    cv.ellipse(20, 20, 76, 76, (220, 188, 88), outline=D_ + (255,), ow=4)
    cv.line([(48, 30), (48, 66)], D_ + (255,), 5)
    cv.line([(38, 38), (58, 38), (38, 48), (58, 58), (38, 58)], D_ + (255,), 4)


def ic_fuel(cv):
    cv.rect(26, 26, 56, 72, W_, outline=D_ + (255,), ow=3, r=3)
    cv.rect(32, 32, 50, 46, (90, 130, 150), outline=D_ + (255,), ow=2)
    cv.line([(56, 38), (68, 38), (70, 62)], W_ + (255,), 4)


def ic_book(cv):
    cv.rect(18, 26, 48, 70, W_, outline=D_ + (255,), ow=3)
    cv.rect(48, 26, 78, 70, (220, 214, 196), outline=D_ + (255,), ow=3)
    cv.line([(24, 38), (42, 38)], D_ + (255,), 2)
    cv.line([(54, 38), (72, 38)], D_ + (255,), 2)
    cv.line([(24, 48), (42, 48)], D_ + (255,), 2)


def ic_news(cv):
    cv.rect(20, 22, 76, 74, W_, outline=D_ + (255,), ow=3)
    cv.rect(26, 28, 50, 44, (60, 60, 56), outline=None, ow=0)
    for y in (50, 58, 66):
        cv.line([(26, y), (70, y)], D_ + (255,), 2)
    cv.line([(56, 32), (70, 32)], D_ + (255,), 2)
    cv.line([(56, 40), (70, 40)], D_ + (255,), 2)


def ic_drop(cv):
    cv.poly([(48, 18), (28, 52), (32, 68), (48, 76), (64, 68), (68, 52)], (150, 190, 226), outline=D_ + (255,), ow=3)


def ic_mug(cv):
    cv.rect(24, 28, 58, 74, (222, 188, 100), outline=D_ + (255,), ow=3, r=3)
    cv.rect(24, 28, 58, 40, (240, 236, 224), outline=D_ + (255,), ow=3, r=3)
    cv.ellipse(54, 38, 76, 62, (0, 0, 0, 0), outline=(222, 188, 100, 255), ow=5)


def ic_ham(cv):
    cv.ellipse(18, 30, 70, 70, (190, 96, 90), outline=D_ + (255,), ow=3)
    cv.ellipse(58, 38, 80, 60, (232, 224, 210), outline=D_ + (255,), ow=3)
    cv.ellipse(30, 40, 46, 54, (216, 140, 134), outline=None, ow=0)


def ic_flower(cv):
    for k in range(5):
        a = k / 5 * 2 * math.pi
        x, y = 48 + math.cos(a) * 15, 40 + math.sin(a) * 15
        cv.ellipse(x - 9, y - 9, x + 9, y + 9, (220, 120, 140), outline=D_ + (255,), ow=2)
    cv.ellipse(40, 32, 56, 48, (230, 200, 90), outline=D_ + (255,), ow=2)
    cv.line([(48, 56), (48, 76)], (96, 160, 96, 255), 4)


def ic_car(cv):
    cv.rect(16, 40, 80, 64, (200, 70, 60), outline=D_ + (255,), ow=3, r=6)
    cv.rect(30, 30, 66, 44, (150, 190, 214), outline=D_ + (255,), ow=3, r=4)
    cv.ellipse(22, 58, 38, 74, (40, 40, 40), outline=D_ + (255,), ow=2)
    cv.ellipse(58, 58, 74, 74, (40, 40, 40), outline=D_ + (255,), ow=2)


def ic_mail(cv):
    cv.rect(18, 28, 78, 68, W_, outline=D_ + (255,), ow=3)
    cv.line([(18, 28), (48, 52), (78, 28)], D_ + (255,), 3)


def ic_film(cv):
    cv.rect(20, 24, 76, 72, (40, 40, 44), outline=D_ + (255,), ow=3)
    for y in range(30, 70, 10):
        cv.rect(24, y, 30, y + 6, W_, outline=None, ow=0)
        cv.rect(66, y, 72, y + 6, W_, outline=None, ow=0)
    cv.rect(34, 32, 62, 64, (210, 200, 160), outline=None, ow=0)


def ic_bed(cv):
    cv.rect(16, 44, 80, 66, W_, outline=D_ + (255,), ow=3)
    cv.rect(16, 36, 34, 66, (140, 160, 200), outline=D_ + (255,), ow=3)
    cv.rect(18, 66, 24, 74, D_, outline=None, ow=0)
    cv.rect(72, 66, 78, 74, D_, outline=None, ow=0)


def ic_plug(cv):
    cv.rect(34, 26, 62, 52, W_, outline=D_ + (255,), ow=3, r=4)
    cv.line([(42, 26), (42, 16)], W_ + (255,), 5)
    cv.line([(54, 26), (54, 16)], W_ + (255,), 5)
    cv.line([(48, 52), (48, 74)], W_ + (255,), 5)


def ic_hanger(cv):
    cv.line([(48, 24), (48, 34), (22, 56), (74, 56), (48, 34)], W_ + (255,), 4)
    cv.ellipse(42, 14, 54, 26, (0, 0, 0, 0), outline=W_ + (255,), ow=3)


SIGNS = [("bread", col("b4824a"), ic_bread), ("cross", col("4f7f5a"), ic_cross), ("wrench", col("a0442e"), ic_wrench), ("cup", col("5a7090"), ic_cup),
         ("scissors", col("6a4f86"), ic_scissors), ("cart", col("4c7a6e"), ic_cart), ("coin", col("4a5f84"), ic_coin), ("fuel", col("b8523c"), ic_fuel), ("book", col("7a5a3a"), ic_book),
         ("news", col("8a8a80"), ic_news), ("drop", col("4a82a8"), ic_drop), ("mug", col("5a7a44"), ic_mug), ("ham", col("8a4a44"), ic_ham), ("flower", col("86608a"), ic_flower),
         ("car", col("4e5e78"), ic_car), ("mail", col("a0443c"), ic_mail), ("film", col("3c3c48"), ic_film), ("bed", col("5a6e8c"), ic_bed), ("plug", col("8a6a2e"), ic_plug),
         ("hanger", col("6a7a7e"), ic_hanger)]
for name, bg, fn in SIGNS:
    add("sign_" + name, plate(bg, fn), False, (0.75, 0.75))


# ------------------------------------------------------------------------------------ packing --
def pack(pieces, width=1024):
    x = y = row_h = 0
    out = []
    for p in sorted(pieces, key=lambda q: (-q["im"].size[1], q["name"])):
        w, h = p["im"].size
        pw, ph = w + 2 * PAD, h + 2 * PAD
        if x + pw > width:
            x = 0
            y += row_h
            row_h = 0
        out.append((p, x, y))
        x += pw
        row_h = max(row_h, ph)
    return out, y + row_h


placed, height = pack(pieces)
H = height
sheet = Image.new("RGBA", (1024, H), (0, 0, 0, 0))
meta = {"_doc": "The rectangle of every piece of roof_extras.png (without its 8 px of padding) and its size in tiles. Written by tools/make_roof_extras.py.", "pad": PAD, "tile_px": T, "pieces": {}}
for p, x, y in placed:
    im = p["im"]
    if p["seamless"]:
        pad_im = wrap_pad(im)
        sheet.paste(pad_im, (x, y))
    else:
        sheet.paste(im, (x + PAD, y + PAD))
    meta["pieces"][p["name"]] = {"rect": [x + PAD, y + PAD, im.size[0], im.size[1]], "tiles": list(p["tiles"]), "fill": bool(p["seamless"])}
sheet.save(OUT_PNG, optimize=True)
with open(OUT_JSON, "w") as f:
    json.dump(meta, f, indent=1)
print("roof extras: %d pieces, sheet %d x %d, %d bytes" % (len(pieces), sheet.size[0], sheet.size[1], os.path.getsize(OUT_PNG)))
