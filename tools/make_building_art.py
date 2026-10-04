#!/usr/bin/env python3
"""Draws the pictures of the yard's buildings that did not read as what they are (the tents, the
bunk house, the workshop, the greenhouse beds, the floodlights): procedural drawing only, no
reference pictures and no tools off the machine.

    python3 tools/make_building_art.py                 # writes every picture below into assets/objects
    python3 tools/make_building_art.py tent bunk       # only those (names: tent, bunk, workshop, greenhouse, floodlights, tarp)
    BUILDING_ART_DEBUG=some/dir python3 tools/make_building_art.py   # also a preview of each on the yard's colour

What it writes (the sizes in tiles are the `w` and `h` in assets/data/building_art.json; the sprites are
drawn at PX pixels to the tile and the game scales them down):

    143_tent.png, 144_tent.png   the two tents (olive and sand canvas): REPLACED on purpose, same file names
                                 and the same proportions as the pictures they replace (the tents building,
                                 the raid sites' camps (site_layouts.json "tent") and tests/test_build_view.gd
                                 know them by name)
    393_tent.png                 a third colourway (weathered brown canvas)
    394_bunkroof.png             the bunk house's roof: salvaged corrugated sheets on posts over the cots
    395_bunkbed.png .. 398_bunkbed.png   the four beds: a strip of plank floor each, with one of the yard's cots on it
    399_workshop.png             the workshop's timber hut with its shingled roof and stovepipe
    400_tunnel.png, 401_tunnel.png   the greenhouse beds under a tunnel of plastic sheet (the second with one end rolled back)
    402_floodlight.png, 403_floodlight.png   a floodlight each: a bank of four lamps on a guyed steel pole (the cable runs the other way)
    117_tarp.png, 404_tarp.png   the shade shelter over the yard's workbench (and in the streets): an awning of see-through shade cloth
                                 on four wooden poles with guy ropes, olive and sand. 117_tarp is REPLACED on purpose (same name, size and
                                 footprint: assets/data/map.json and dressing.json place it); dressing.json uses 404_tarp for two street tarps

The style is the props': seen from above with a slight tilt (a thing that stands shows its south face and
its top, drawn with the same 0.6 squash as the tower and the mast), light from the north west, a dark brown
outline, a soft shadow thrown to the south east, flat fills with a gentle gradient, a little grain. Every
picture is drawn at three times the size and brought down, so its edges are smooth, and saved as an indexed
PNG (a palette of 232 colours for the picture and a ladder of alphas for the shadow: a fifth of the size of
the 32 bit file; BUILDING_ART_RGBA=1 writes the full colour ones instead). It needs Pillow and numpy; the beds
are composed with the yard's own cot pictures (082_cot, 073_mattress, 083_cot, 075_mattress), which it reads
from assets/objects. The same inputs give the same files, byte for byte.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.environ.get("BUILDING_ART_OUT") or os.path.join(ROOT, "assets", "objects")

PX = 128          # output pixels to the tile
SS = 3            # drawn this many times larger
S = PX * SS
K = 0.6           # how much of a thing's height shows on screen (people show about 0.6 of theirs)
OUTLINE = (34, 26, 19)
YARD = (118, 116, 110)     # the colour the previews are laid on


# ------------------------------------------------------------------ noise ---

def _hash(ix, iy, seed):
    """A repeatable pseudo random number in [0, 1) for each whole (ix, iy)."""
    n = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFF).astype(np.float32) / 65536.0


def vnoise(X, Y, freq, seed=0, fx=1.0, fy=1.0):
    """Smooth value noise in [0, 1], `freq` cells to the tile (fx, fy stretch it along an axis)."""
    x = X * (freq * fx)
    y = Y * (freq * fy)
    x0 = np.floor(x)
    y0 = np.floor(y)
    tx = x - x0
    ty = y - y0
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    a = _hash(x0, y0, seed)
    b = _hash(x0 + 1, y0, seed)
    c = _hash(x0, y0 + 1, seed)
    d = _hash(x0 + 1, y0 + 1, seed)
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(X, Y, freq, seed=0, octaves=3, fx=1.0, fy=1.0):
    tot = np.zeros_like(X, np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        tot += amp * vnoise(X, Y, freq * (2 ** o), seed + 17 * o, fx, fy)
        norm += amp
        amp *= 0.5
    return tot / norm


# ----------------------------------------------------------------- canvas ---

def mix(c0, c1, t):
    return tuple(a + (b - a) * t for a, b in zip(c0, c1))


def shade(c, f):
    return tuple(max(0.0, min(255.0, v * f)) for v in c)


class Art:
    """A picture being drawn. Coordinates are tiles from its top left corner. Everything is painted
    with a mask (a polygon, a stroke, an ellipse) and a colour (one colour or a function of X, Y)."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.W, self.H = int(round(w * S)), int(round(h * S))
        self.prem = np.zeros((self.H, self.W, 3), np.float32)
        self.alpha = np.zeros((self.H, self.W), np.float32)

    # -- masks (PIL 'L' images the size of the picture)
    def _new(self):
        im = Image.new("L", (self.W, self.H), 0)
        return im, ImageDraw.Draw(im)

    @staticmethod
    def _px(pts):
        return [(x * S, y * S) for x, y in pts]

    def poly(self, pts):
        im, d = self._new()
        d.polygon(self._px(pts), fill=255)
        return im

    def stroke(self, pts, width, closed=False, round_ends=True):
        im, d = self._new()
        p = self._px(pts)
        if closed:
            p = p + [p[0], p[1]]
        d.line(p, fill=255, width=max(1, int(round(width * S))), joint="curve")
        if round_ends and not closed:
            r = width * S / 2.0
            for x, y in (p[0], p[-1]):
                d.ellipse((x - r, y - r, x + r, y + r), fill=255)
        return im

    def dashes(self, pts, width, on, off, offset=0.0):
        """A dashed stroke along a polyline (the stitches, the seams)."""
        im, d = self._new()
        run = -offset
        for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
            seg = math.hypot(x1 - x0, y1 - y0)
            if seg < 1e-6:
                continue
            ux, uy = (x1 - x0) / seg, (y1 - y0) / seg
            t = 0.0
            while t < seg:
                phase = run % (on + off)
                if phase < on:
                    step = min(on - phase, seg - t)
                    a = (x0 + ux * t, y0 + uy * t)
                    b = (x0 + ux * (t + step), y0 + uy * (t + step))
                    d.line(self._px([a, b]), fill=255, width=max(1, int(round(width * S))))
                else:
                    step = min(on + off - phase, seg - t)
                step = max(step, 1e-4)
                t += step
                run += step
        return im

    def ellipse(self, cx, cy, rx, ry=None):
        ry = rx if ry is None else ry
        im, d = self._new()
        d.ellipse(((cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S), fill=255)
        return im

    def rect(self, x0, y0, x1, y1):
        return self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])

    def blur(self, mask, r):
        return mask.filter(ImageFilter.GaussianBlur(r * S))

    @staticmethod
    def both(a, b):
        return ImageChops.multiply(a, b)

    @staticmethod
    def either(a, b):
        return ImageChops.lighter(a, b)

    @staticmethod
    def minus(a, b):
        return ImageChops.subtract(a, b)

    # -- painting
    def paint(self, mask, colour, opacity=1.0, clip=None):
        """Lay a colour (a tuple, or a function of (X, Y) in tiles giving rows of colours) through a mask."""
        if clip is not None:
            mask = ImageChops.multiply(mask, clip)
        box = mask.getbbox()
        if box is None:
            return
        x0, y0, x1, y1 = box
        m = np.asarray(mask.crop(box), np.float32) / 255.0 * opacity
        if callable(colour):
            ys, xs = np.mgrid[y0:y1, x0:x1]
            col = colour(xs.astype(np.float32) / S, ys.astype(np.float32) / S)
        else:
            col = np.array(colour, np.float32)[None, None, :]
        sub = self.prem[y0:y1, x0:x1]
        asub = self.alpha[y0:y1, x0:x1]
        mm = m[..., None]
        sub[...] = col * mm + sub * (1 - mm)
        asub[...] = m + asub * (1 - m)

    def shadow_under(self, dx, dy, blur, strength, colour=(8, 6, 4), mask_of=None):
        """The soft shadow on the ground to the south east, laid under everything drawn so far."""
        a = self.alpha if mask_of is None else mask_of
        src = np.clip(a, 0, 1)
        sx, sy = int(round(dx * S)), int(round(dy * S))
        moved = np.zeros_like(src)          # shifted without wrapping round the edge
        h, w = src.shape
        moved[max(0, sy):h + min(0, sy), max(0, sx):w + min(0, sx)] = src[max(0, -sy):h - max(0, sy), max(0, -sx):w - max(0, sx)]
        im = Image.fromarray((moved * 255).astype(np.uint8))
        im = im.filter(ImageFilter.GaussianBlur(blur * S))
        sh = np.asarray(im, np.float32) / 255.0 * strength
        col = np.array(colour, np.float32)[None, None, :]
        # the shadow goes under: result = object over shadow
        newa = self.alpha + sh * (1 - self.alpha)
        self.prem = self.prem + col * (sh * (1 - self.alpha))[..., None]
        self.alpha = newa

    # -- the finished sprite
    def image(self, grain=0.0, seed=1, scale=1.0):
        """The picture at PX pixels to the tile (`scale` makes the whole drawing that much larger)."""
        w, h = int(round(self.w * PX * scale)), int(round(self.h * PX * scale))
        # the colours are premultiplied, so they are brought down with the alpha (no fringe at the edge)
        pa = np.dstack([self.prem, self.alpha]).astype(np.float32)
        out = []
        for i in range(4):
            c = Image.fromarray(np.ascontiguousarray(pa[..., i])).resize((w, h), Image.BOX)
            out.append(np.asarray(c, np.float32))
        al = np.clip(out[3], 0.0, 1.0)
        rgb = np.dstack(out[:3]) / np.maximum(al[..., None], 1e-6)
        if grain > 0:
            rng = np.random.RandomState(seed)
            n = rng.normal(0.0, 1.0, (h, w)).astype(np.float32)
            n = (n + 0.5 * (np.roll(n, 1, 0) + np.roll(n, -1, 0) + np.roll(n, 1, 1) + np.roll(n, -1, 1))) / 3.0
            solid = np.clip((al - 0.9) * 10.0, 0, 1)
            rgb = rgb * (1.0 + (grain * n * solid)[..., None])
        rgb = np.clip(rgb, 0, 255)
        res = np.dstack([rgb, al * 255.0])
        return Image.fromarray(np.clip(res, 0, 255).round().astype(np.uint8))


def preview(im, path, scale=1):
    bg = Image.new("RGBA", (im.width + 40, im.height + 40), YARD + (255,))
    bg.alpha_composite(im, (20, 20))
    if scale != 1:
        bg = bg.resize((bg.width * scale, bg.height * scale), Image.LANCZOS)
    bg.convert("RGB").save(path)


def to_palette(im, colours=232):
    """The sprite as an indexed PNG with a transparency per palette entry: the opaque pixels get a palette of
    their own (median cut), and everything soft (the shadow, the antialiased outline) is a ladder of alphas of
    one dark colour, so a soft shadow stays smooth and the file is a fifth of the size of the 32 bit one."""
    arr = np.asarray(im.convert("RGBA"))
    a = arr[..., 3]
    rgb = arr[..., :3]
    solid = a >= 250
    dark = (a < 250) & (rgb.max(axis=2) < 52)
    keep = (a < 250) & ~dark & (a >= 100)           # a thin light line's soft edge stays, made solid
    solid = solid | keep
    flat = rgb[solid].reshape(1, -1, 3)
    pal_src = Image.fromarray(np.ascontiguousarray(flat))
    q = pal_src.quantize(colors=colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    full = Image.fromarray(np.ascontiguousarray(rgb)).quantize(palette=q, dither=Image.Dither.NONE)
    idx = np.asarray(full).astype(np.int32)
    ncol = len(q.getpalette()) // 3
    ncol = min(ncol, colours)
    pal = list(q.getpalette()[:ncol * 3])
    levels = 256 - ncol
    pal += [12, 9, 6] * levels
    alphas = [255] * ncol + [int(round(255.0 * i / (levels - 1))) for i in range(levels)]
    lev = np.clip(np.round(a.astype(np.float32) / 255.0 * (levels - 1)), 0, levels - 1).astype(np.int32)
    out = np.where(solid, idx, ncol + lev).astype(np.uint8)
    P = Image.fromarray(out)
    P.putpalette(pal + [0] * (768 - len(pal)))
    return P, bytes(alphas)


def to_palette_alpha(im, colours=224):
    """Like to_palette, for a picture whose cloth is see-through: the pixels that are not just shadow are
    clustered with their alpha as a fourth channel (octree), the shadow is the ladder of alphas as before."""
    arr = np.asarray(im.convert("RGBA"))
    a = arr[..., 3]
    rgb = arr[..., :3]
    shadow = ((a < 250) & (rgb.max(axis=2) < 52)) | (a < 8)
    work = arr.copy()
    work[shadow] = 0
    q = Image.fromarray(np.ascontiguousarray(work)).quantize(colors=colours, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    raw = q.getpalette("RGBA")
    ncol = min(len(raw) // 4, colours)
    pal = []
    alphas = []
    for i in range(ncol):
        pal += raw[4 * i:4 * i + 3]
        alphas.append(raw[4 * i + 3])
    levels = 256 - ncol
    pal += [12, 9, 6] * levels
    alphas += [int(round(255.0 * i / (levels - 1))) for i in range(levels)]
    lev = np.clip(np.round(a.astype(np.float32) / 255.0 * (levels - 1)), 0, levels - 1).astype(np.int32)
    out = np.where(shadow, ncol + lev, np.asarray(q).astype(np.int32)).astype(np.uint8)
    P = Image.fromarray(out)
    P.putpalette(pal)
    return P, bytes(alphas)


def save(im, name, translucent=False):
    path = os.path.join(OUT, name)
    if os.environ.get("BUILDING_ART_RGBA"):
        im.save(path, optimize=True)
    else:
        P, tr = to_palette_alpha(im) if translucent else to_palette(im)
        P.save(path, optimize=True, transparency=tr)
    print("wrote", name, im.size, os.path.getsize(path) // 1024, "KB")
    dbg = os.environ.get("BUILDING_ART_DEBUG")
    if dbg:
        os.makedirs(dbg, exist_ok=True)
        preview(Image.open(path).convert("RGBA"), os.path.join(dbg, name.replace(".png", "_preview.png")))


# ------------------------------------------------------------------- tents ---

# The tent: a ridge tent seen from the south. The picture covers TENT_W x TENT_H tiles times TENT_SCALE (the building art
# draws it 2.8 x 3.08 tiles, and a camp in a raid site 2.7 wide; the pictures it replaces were 262 x 288 pixels).
TENT_W, TENT_H = 2.4, 2.64          # the canvas the tent is drawn on ...
TENT_SCALE = 7.0 / 6.0              # ... and it is brought out this much larger: 2.8 x 3.08 tiles in the yard
TENT_HALF = 0.78          # half the tent's width on the ground
TENT_YF, TENT_YB = 2.18, 0.68   # the ground line of the front and of the back
TENT_RIDGE = 1.0          # how high the ridge is (tiles), so it shows K * this above its foot

TENTS = {
    # name: base canvas colour, patch colour, how the door is tied, a few differences
    "143_tent": dict(base=(92, 100, 62), patch=(128, 118, 78), cord=(196, 182, 140), seed=3,
                     patch_at=(0.46, 0.60), patch_side="L", mud=0.55, boots=True),
    "144_tent": dict(base=(186, 164, 118), patch=(142, 120, 82), cord=(120, 96, 66), seed=8,
                     patch_at=(0.50, 0.30), patch_side="R", mud=0.45, boots=False),
    "393_tent": dict(base=(124, 104, 78), patch=(84, 90, 66), cord=(206, 190, 150), seed=15,
                     patch_at=(0.40, 0.72), patch_side="R", mud=0.7, boots=False),
}


def draw_tent(spec):
    a = Art(TENT_W, TENT_H)
    cx = TENT_W / 2.0
    xl, xr = cx - TENT_HALF, cx + TENT_HALF
    yf, yb = TENT_YF, TENT_YB
    kh = K * TENT_RIDGE
    base = spec["base"]
    seed = spec["seed"]

    def pl(u, v):      # left panel: u from the eave (0) to the ridge (1), v from the front (0) to the back (1)
        return (xl + u * (cx - xl), yf - v * (yf - yb) - u * kh)

    def pr(u, v):
        return (xr - u * (xr - cx), yf - v * (yf - yb) - u * kh)

    def uv_left(X, Y):
        u = (X - xl) / (cx - xl)
        v = (yf - Y - u * kh) / (yf - yb)
        return u, v

    def uv_right(X, Y):
        u = (xr - X) / (xr - cx)
        v = (yf - Y - u * kh) / (yf - yb)
        return u, v

    rf = (cx, yf - kh)
    rb = (cx, yb - kh)
    fl, fr, bl, br = (xl, yf), (xr, yf), (xl, yb), (xr, yb)

    left = [fl, rf, rb, bl]
    right = [fr, rf, rb, br]
    gable = [fl, rf, fr]

    def panel_colour(side):
        uv = uv_left if side == "L" else uv_right
        lit = side == "L"

        def f(X, Y):
            u, v = uv(X, Y)
            u = np.clip(u, 0, 1)
            if lit:
                k = 0.93 + 0.30 * np.power(u, 0.8)
            else:
                k = 0.60 + 0.20 * u
            # the canvas sags between the ridge and the pegs: long soft folds running down the slope
            fold = fbm(X, Y, 2.2, seed + (0 if lit else 5), 3, fx=2.2, fy=0.8)
            k = k * (0.93 + 0.14 * fold)
            # sun-bleached towards the ridge, a little dirt along the eave
            col = np.array(base, np.float32)[None, None, :] * k[..., None]
            sun = np.clip((u - 0.55) * 2.2, 0, 1)[..., None] * 0.07
            col = col * (1 + sun) + np.array([20, 18, 10], np.float32)[None, None, :] * sun
            mud = np.clip(1.0 - u / 0.22, 0, 1) * fbm(X, Y, 5.0, seed + 40, 2)
            mud = (mud * spec["mud"])[..., None]
            col = col * (1 - 0.45 * mud) + np.array([64, 48, 30], np.float32)[None, None, :] * 0.45 * mud
            return col
        return f

    outline_w = 0.026
    # ---- the two roof panels
    for side, pts, p, uv in (("L", left, pl, uv_left), ("R", right, pr, uv_right)):
        m = a.poly(pts)
        a.paint(m, panel_colour(side))
        # seams: the panels run from the eave to the ridge; stitched either side
        for v in (0.34, 0.68):
            line = [p(0.02, v), p(0.98, v)]
            a.paint(a.stroke(line, 0.020), shade(base, 0.62 if side == "R" else 0.80), 0.55, clip=m)
            a.paint(a.dashes([p(0.0, v - 0.016), p(1.0, v - 0.016)], 0.007, 0.03, 0.02), shade(base, 1.35), 0.35, clip=m)
            a.paint(a.dashes([p(0.0, v + 0.016), p(1.0, v + 0.016)], 0.007, 0.03, 0.02), shade(base, 1.35), 0.35, clip=m)
        # the hem along the eave
        hem = [p(0.045, 0.0), p(0.045, 1.0)]
        a.paint(a.stroke(hem, 0.014, round_ends=False), shade(base, 0.55), 0.55, clip=m)
        a.paint(a.stroke([p(0.0, 0.0), p(0.0, 1.0)], 0.03, round_ends=False), shade(base, 0.62), 0.5, clip=m)
        # creases where the canvas is pulled by the pegs: soft dark and light strips running up towards the ridge
        for (u0, v0, u1, v1) in ((0.0, 0.0, 0.62, 0.20), (0.0, 1.0, 0.62, 0.80), (0.0, 0.5, 0.45, 0.50)):
            ln = [p(u0, v0), p(u1, v1)]
            dark = a.blur(a.stroke(ln, 0.045), 0.018)
            a.paint(dark, (12, 10, 6), 0.16, clip=m)
            lite = a.blur(a.stroke([(x + 0.03, y - 0.012) for x, y in ln], 0.030), 0.014)
            a.paint(lite, (255, 244, 214), 0.07, clip=m)
        # tie tabs on the eave, where the pegs' cords start
        for v in (0.12, 0.88):
            x, y = p(0.0, v)
            a.paint(a.ellipse(x, y, 0.016), shade(OUTLINE, 1.0), 0.9)
        # a patch (once, on its side)
        if side == spec["patch_side"]:
            pu, pv = spec["patch_at"]
            w_u, w_v = 0.26, 0.20
            jit = [(-0.01, 0.01), (0.012, -0.008), (0.006, 0.012), (-0.012, -0.006)]
            ring = [(pu, pv), (pu + w_u, pv), (pu + w_u, pv + w_v), (pu, pv + w_v)]
            ppts = [p(uu + j[0], vv + j[1]) for (uu, vv), j in zip(ring, jit)]
            pm = a.poly(ppts)

            def pcol(X, Y, uvf=uv, pc=spec["patch"], kk=(1.0 if side == "L" else 0.72)):
                u, v = uvf(X, Y)
                n = fbm(X, Y, 9.0, seed + 90, 2)
                return np.array(pc, np.float32)[None, None, :] * ((0.92 + 0.16 * n) * kk)[..., None]
            a.paint(pm, pcol, clip=m)
            a.paint(a.stroke(ppts, 0.012, closed=True), shade(OUTLINE, 1.4), 0.55, clip=m)
            inner = [p(pu + 0.02, pv + 0.022), p(pu + w_u - 0.02, pv + 0.022), p(pu + w_u - 0.02, pv + w_v - 0.022), p(pu + 0.02, pv + w_v - 0.022)]
            a.paint(a.dashes(inner + [inner[0]], 0.007, 0.028, 0.02), shade(spec["cord"], 1.0), 0.65, clip=pm)
        # soft ambient dark under the eave line (the tent sits on the ground)
        edge = a.stroke([p(0.0, 0.0), p(0.0, 1.0)], 0.07, round_ends=False)
        a.paint(edge, (10, 8, 5), 0.18, clip=m)

    # ---- the ridge: a seam with a tape over it
    a.paint(a.stroke([rf, rb], 0.050, round_ends=False), shade(base, 0.62), 0.9)
    a.paint(a.stroke([(rf[0] - 0.012, rf[1]), (rb[0] - 0.012, rb[1])], 0.014, round_ends=False), shade(base, 1.45), 0.7)

    # ---- the front gable and the door
    gm = a.poly(gable)

    def gcol(X, Y):
        t = np.clip((Y - (yf - kh)) / kh, 0, 1)
        k = 0.78 - 0.10 * t
        fold = fbm(X, Y, 3.0, seed + 20, 2)
        return np.array(base, np.float32)[None, None, :] * (k * (0.94 + 0.12 * fold))[..., None]
    a.paint(gm, gcol)
    # the door: a narrower A, dark inside, with a groundsheet at its foot
    dh = 0.52         # height of the opening on screen
    dw = 0.36
    door = [(cx - dw, yf), (cx, yf - dh), (cx + dw, yf)]
    dm = a.poly(door)

    def inside(X, Y):
        t = np.clip((Y - (yf - dh)) / dh, 0, 1)[..., None]
        top = np.array([22, 18, 13], np.float32)[None, None, :]
        bot = np.array([62, 52, 38], np.float32)[None, None, :]
        return top * (1 - t) + bot * t
    a.paint(dm, inside)
    # a sleeping bag's end, just in the dark, and for one tent a pair of boots at the door
    bag = a.ellipse(cx + 0.02, yf - 0.05, 0.19, 0.075)
    a.paint(a.both(bag, dm), mix(base, (40, 36, 28), 0.55), 0.85)
    if spec.get("boots"):
        for bx in (-0.075, 0.085):
            a.paint(a.ellipse(cx + bx, yf + 0.07, 0.034, 0.062), (46, 36, 26), 0.95)
            a.paint(a.ellipse(cx + bx - 0.008, yf + 0.05, 0.011, 0.020), (120, 100, 72), 0.8)
    # the flaps, rolled back and tied at each side
    for sgn in (-1, 1):
        fl_pts = [(cx + sgn * dw, yf), (cx + sgn * 0.015, yf - dh), (cx + sgn * 0.07, yf - dh + 0.04), (cx + sgn * (dw + 0.07), yf - 0.02)]
        fm = a.poly(fl_pts)
        a.paint(fm, shade(base, 1.0 if sgn < 0 else 0.66))
        a.paint(a.stroke(fl_pts, 0.012, closed=True), shade(OUTLINE, 1.2), 0.6)
        # the cord and its toggle
        tx, ty = cx + sgn * (dw + 0.015), yf - 0.15
        a.paint(a.stroke([(tx, ty), (tx + sgn * 0.06, ty + 0.01)], 0.010), spec["cord"], 0.95)
        a.paint(a.ellipse(tx + sgn * 0.07, ty + 0.012, 0.013), spec["cord"], 1.0)
    # the hem of the gable, a darker strip at the ground
    a.paint(a.stroke([fl, fr], 0.034, round_ends=False), shade(base, 0.44), 0.8, clip=gm)

    # ---- outlines
    for pts in (left, right):
        a.paint(a.stroke(pts, outline_w, closed=True), OUTLINE, 1.0)
    a.paint(a.stroke(gable, outline_w, closed=True), OUTLINE, 1.0)
    a.paint(a.stroke(door, 0.016, closed=True), shade(OUTLINE, 0.8), 0.9)
    a.paint(a.stroke([rf, rb], 0.018, round_ends=False), shade(OUTLINE, 1.3), 0.45)

    # ---- ridge poles stick out and carry the guy ropes
    for (px_, py_) in (rf, rb):
        a.paint(a.ellipse(px_, py_, 0.040), OUTLINE, 1.0)
        a.paint(a.ellipse(px_, py_, 0.026), (150, 118, 76), 1.0)
        a.paint(a.ellipse(px_ - 0.008, py_ - 0.008, 0.010), (214, 188, 140), 0.9)

    # ---- ropes and pegs: a V from each ridge end, and the corners pegged out
    ropes = []
    ropes += [(rf, (cx + 0.02, yf + 0.25))]
    ropes += [(rb, (cx - 0.46, yb - 0.30)), (rb, (cx + 0.46, yb - 0.30))]
    ropes += [(fl, (xl - 0.22, yf + 0.15)), (fr, (xr + 0.22, yf + 0.15)),
              (bl, (xl - 0.22, yb - 0.10)), (br, (xr + 0.22, yb - 0.10))]
    for (p0, p1) in ropes:
        # a rope hangs a little: the middle sags towards the ground
        mx, my = (p0[0] + p1[0]) / 2.0, (p0[1] + p1[1]) / 2.0 + 0.012
        pts = [p0, (mx, my), p1]
        a.paint(a.stroke(pts, 0.022), (12, 9, 6), 0.45)
        a.paint(a.stroke(pts, 0.012), spec["cord"], 0.95)
    for (p0, p1) in ropes:
        a.paint(a.ellipse(p1[0], p1[1], 0.030, 0.026), (40, 30, 20), 1.0)
        a.paint(a.ellipse(p1[0] - 0.005, p1[1] - 0.005, 0.015, 0.012), (150, 120, 80), 0.9)

    # ---- the shadow on the ground, thrown to the south east
    sil = a.alpha.copy()
    a.shadow_under(0.08, 0.08, 0.040, 0.50, mask_of=sil)
    a.shadow_under(0.03, 0.04, 0.020, 0.30, mask_of=sil)
    return a.image(grain=0.025, seed=seed, scale=TENT_SCALE)


def tents():
    for name, spec in TENTS.items():
        save(draw_tent(spec), name + ".png")


# ---------------------------------------------------------------- bunk house ---

# The bunk house: a floor of planks, and over its back half a lean-to roof of salvaged corrugated sheets on
# posts, the cots under it (the cots themselves are the existing pictures, set out in building_art.json).
# The roof is high (the same squash as everything that stands), so it shows above where it stands and the
# heads of the cots are in its shade; the patients lie where `beds` in building_art.json says, in front of it.
BUNK_W, BUNK_H = 4.0, 2.8          # the roof picture: x from -2.0 to 2.0 (the yard keeps a picture within two tiles of the plot's middle), y from -2.8 to 0.0 (tiles from the plot's middle)


def _wood(base, seed, along="x", grain=0.35, fx=1.0):
    """A colour function: boards with a grain, for posts and floors."""
    def f(X, Y):
        n = fbm(X, Y, 14.0, seed, 3, fx=(1.0 if along == "y" else 0.12) * fx, fy=(0.12 if along == "y" else 1.0) * fx)
        k = 1.0 - grain / 2.0 + grain * n
        return np.array(base, np.float32)[None, None, :] * k[..., None]
    return f


def draw_bunk_roof():
    a = Art(BUNK_W, BUNK_H)
    ox, oy = BUNK_W / 2.0, BUNK_H

    def W(x, y):
        return (x + ox, y + oy)

    half = 1.62
    y_top, y_eave = -2.62, -1.28          # the roof sheet on screen: back edge and front eave
    y_foot = -0.60                          # where the posts stand
    beam_h = 0.10
    sheets = [(-half, -0.54, (86, 118, 106)), (-0.57, 0.54, (150, 154, 146)), (0.51, half, (150, 96, 66))]
    sheet_m = None
    # ---- the roof's own shadow on the ground (drawn first, the floor shows through it): the roof's footprint thrown south east
    foot = [W(-half, -1.72), W(half, -1.72), W(half, y_foot), W(-half, y_foot)]
    foot_m = a.poly(foot)
    # ---- the sheets
    ribp = 0.105
    ys0, ys1 = oy + y_top, oy + y_eave
    for i, (x0, x1, base) in enumerate(sheets):
        # the bottom edge is the profile of the corrugation: a scallop
        pts = [W(x0, y_top), W(x1, y_top)]
        n = int(round((x1 - x0) / (ribp / 6.0)))
        xs = [x1 - (x1 - x0) * j / n for j in range(n + 1)]
        for xx in xs:
            wave = 0.5 + 0.5 * math.sin((xx - x0) / ribp * 2 * math.pi)
            pts.append(W(xx, y_eave + 0.012 * wave))
        m = a.poly(pts)
        seed = 30 + i
        rust_amt = (0.35, 0.55, 0.9)[i]

        def col(X, Y, base=base, x0=x0, seed=seed, rust_amt=rust_amt, x0w=x0 + ox):
            ph = (X - x0w) / ribp * 2 * math.pi
            rib = 0.5 + 0.5 * np.sin(ph)
            k = 0.74 + 0.36 * rib
            t = np.clip((Y - ys0) / (ys1 - ys0), 0, 1)
            vert = 1.05 - 0.10 * t
            streak = fbm(X, Y, 3.0, seed, 3, fx=0.7, fy=0.22)
            c = np.array(base, np.float32)[None, None, :] * (k * vert * (0.86 + 0.28 * streak))[..., None]
            blot = np.clip((fbm(X, Y, 3.5, seed + 9, 3, fx=0.9, fy=0.5) - 0.55) * 3.2, 0, 1)
            edge = np.clip((t - 0.62) / 0.38, 0, 1) * fbm(X, Y, 7.0, seed + 4, 2, fx=1.0, fy=0.35)
            rust = np.clip(blot * rust_amt + edge * rust_amt * 0.9, 0, 1)[..., None]
            rc = np.array((128, 70, 40), np.float32)[None, None, :] * (0.55 + 0.6 * rib)[..., None]
            return c * (1 - 0.75 * rust) + rc * 0.75 * rust
        a.paint(m, col)
        a.paint(a.stroke(pts + [pts[0]], 0.022, closed=False), OUTLINE, 1.0)
        # the thickness of the sheet's edge: a thin lit line under the scallops
        under = [W(xx, y_eave + 0.012 * (0.5 + 0.5 * math.sin((xx - x0) / ribp * 2 * math.pi)) + 0.010) for xx in reversed(xs)]
        a.paint(a.stroke(under, 0.010), (214, 218, 210), 0.55)
        # the sheets lap over each other: a darker strip where they meet
        if i > 0:
            a.paint(a.stroke([W(x0, y_top), W(x0, y_eave + 0.01)], 0.02, round_ends=False), (18, 14, 10), 0.55)
        # screws on the crests, three rows
        for ry in (y_eave - 0.10, -1.98, y_top + 0.14):
            xx = x0 + ribp * 0.25
            while xx < x1 - 0.05:
                px_, py_ = W(xx, ry)
                a.paint(a.ellipse(px_, py_, 0.013), (24, 18, 12), 0.85)
                a.paint(a.ellipse(px_ - 0.003, py_ - 0.003, 0.006), (200, 196, 180), 0.8)
                xx += ribp * 2.0
    # the back edge: a flashing strip
    a.paint(a.stroke([W(-half, y_top + 0.015), W(half, y_top + 0.015)], 0.045, round_ends=False), (74, 78, 74), 0.95)
    a.paint(a.stroke([W(-half, y_top - 0.005), W(half, y_top - 0.005)], 0.022, round_ends=False), OUTLINE, 1.0)
    # an olive tarp roped over a hole at the top right, and a patch of sheet at the left
    tp = [W(0.74, -2.60), W(1.50, -2.60), W(1.54, -2.18), W(0.68, -2.14)]
    tm = a.poly(tp)

    def tarp(X, Y):
        n = fbm(X, Y, 6.0, 77, 3)
        return np.array((86, 92, 62), np.float32)[None, None, :] * (0.80 + 0.35 * n)[..., None]
    a.paint(tm, tarp)
    a.paint(a.stroke(tp, 0.020, closed=True), OUTLINE, 1.0)
    for (px0, py0), (px1, py1) in zip(tp, tp[1:] + tp[:1]):
        pass
    for k_, (x_, y_) in enumerate(tp):
        a.paint(a.ellipse(x_, y_ + 0.0, 0.012), (210, 196, 150), 0.9)
    a.paint(a.stroke([W(0.82, -2.55), W(1.44, -2.52), W(1.47, -2.22), W(0.78, -2.18)], 0.008, closed=True), (210, 196, 150), 0.45)
    # ---- the front beam under the eave, the posts, braces and footings
    beam = [W(-half - 0.04, y_eave + 0.025), W(half + 0.04, y_eave + 0.025), W(half + 0.04, y_eave + 0.025 + beam_h), W(-half - 0.04, y_eave + 0.025 + beam_h)]
    bm = a.poly(beam)
    a.paint(bm, _wood((128, 96, 62), 5, "x", 0.30))
    a.paint(a.stroke([beam[0], beam[1]], 0.012, round_ends=False), (176, 140, 96), 0.7)
    a.paint(a.stroke(beam, 0.018, closed=True), OUTLINE, 1.0)
    # under the roof it is dark: a gradient on the ground below the beam
    under_m = a.poly([W(-half, y_eave + 0.12), W(half, y_eave + 0.12), W(half, y_foot + 0.05), W(-half, y_foot + 0.05)])

    def dusk(X, Y):
        return np.zeros(X.shape + (3,), np.float32) + np.array((10, 8, 6), np.float32)
    # the darkness fades with the distance from the beam: painted as a mask with a vertical ramp
    ramp = Image.fromarray((np.clip(1.0 - (np.arange(a.H, dtype=np.float32)[:, None] / S - (oy + y_eave + 0.12)) / (y_foot + 0.10 - y_eave - 0.12), 0, 1) * 255 * np.ones((1, a.W), np.float32)).astype(np.uint8))
    a.paint(a.both(under_m, ramp), (10, 8, 6), 0.55)
    posts = (-1.50, 0.0, 1.50)
    for px_ in posts:
        # braces: short struts from the post up to the beam
        for sgn in (-1, 1):
            if (px_ == posts[0] and sgn < 0) or (px_ == posts[-1] and sgn > 0):
                continue
            br = [W(px_ + sgn * 0.02, y_eave + 0.025 + beam_h + 0.20), W(px_ + sgn * 0.30, y_eave + 0.025 + beam_h)]
            a.paint(a.stroke(br, 0.045, round_ends=False), OUTLINE, 1.0)
            a.paint(a.stroke(br, 0.026, round_ends=False), (118, 88, 56), 1.0)
        # the footing
        fx, fy = W(px_, y_foot)
        a.paint(a.poly([(fx - 0.11, fy - 0.02), (fx + 0.11, fy - 0.02), (fx + 0.12, fy + 0.045), (fx - 0.12, fy + 0.045)]), (120, 118, 110), 1.0)
        a.paint(a.stroke([(fx - 0.11, fy - 0.02), (fx + 0.11, fy - 0.02), (fx + 0.12, fy + 0.045), (fx - 0.12, fy + 0.045)], 0.014, closed=True), OUTLINE, 1.0)
        # the post
        pw = 0.065
        pm = a.rect(fx - pw, W(0, y_eave + 0.025 + beam_h)[1], fx + pw, fy)

        def pcol(X, Y, fx=fx, pw=pw):
            t = np.clip((X - (fx - pw)) / (2 * pw), 0, 1)
            k = 1.12 - 0.40 * t
            n = fbm(X, Y, 18.0, 55, 2, fx=0.1, fy=1.0)
            return np.array((132, 100, 64), np.float32)[None, None, :] * (k * (0.88 + 0.24 * n))[..., None]
        a.paint(pm, pcol)
        a.paint(a.stroke([(fx - pw, W(0, y_eave + 0.025 + beam_h)[1]), (fx - pw, fy), (fx + pw, fy), (fx + pw, W(0, y_eave + 0.025 + beam_h)[1])], 0.016), OUTLINE, 1.0)
    # a plank sign with a red cross, hung from the beam on two chains
    sx, sy = W(0.80, y_eave + 0.025 + beam_h)
    for dx in (-0.12, 0.12):
        a.paint(a.stroke([(sx + dx, sy), (sx + dx, sy + 0.085)], 0.008, round_ends=False), (60, 56, 50), 1.0)
    sign = [(sx - 0.17, sy + 0.085), (sx + 0.17, sy + 0.085), (sx + 0.17, sy + 0.31), (sx - 0.17, sy + 0.31)]
    a.paint(a.poly(sign), (222, 218, 202), 1.0)
    a.paint(a.stroke(sign, 0.016, closed=True), OUTLINE, 1.0)
    cxs, cys = sx, sy + 0.198
    a.paint(a.rect(cxs - 0.085, cys - 0.025, cxs + 0.085, cys + 0.025), (170, 40, 34), 1.0)
    a.paint(a.rect(cxs - 0.025, cys - 0.085, cxs + 0.025, cys + 0.085), (170, 40, 34), 1.0)
    # a lantern on the left post, its glass lit
    lx, ly = W(-1.50 + 0.16, y_eave + 0.22)
    a.paint(a.stroke([(lx, ly - 0.09), (lx, ly - 0.03)], 0.010), (40, 34, 28), 1.0)
    a.paint(a.poly([(lx - 0.05, ly - 0.03), (lx + 0.05, ly - 0.03), (lx + 0.06, ly + 0.115), (lx - 0.06, ly + 0.115)]), (40, 34, 28), 1.0)
    a.paint(a.rect(lx - 0.036, ly - 0.012, lx + 0.036, ly + 0.095), (255, 218, 138), 1.0)
    a.paint(a.rect(lx - 0.010, ly - 0.012, lx + 0.010, ly + 0.095), (255, 246, 200), 0.9)
    # ---- the shadows: the roof's on the ground (to the south east, over the cots), the posts' feet
    sil = a.alpha.copy()
    shadow_src = np.asarray(foot_m, np.float32) / 255.0
    # the roof's footprint thrown south east and kept off the roof itself
    a.shadow_under(0.22, 0.28, 0.06, 0.34, mask_of=shadow_src)
    a.shadow_under(0.05, 0.05, 0.03, 0.28, mask_of=sil)
    return a.image(grain=0.02, seed=4)


# Each bed is one picture of its own: a strip of the floor with the cot (one of the yard's cot pictures)
# on it, 0.78 tiles wide so that the four make one floor, the frame of heavier boards round the whole.
BED_STRIP = 0.78
BED_TOP, BED_BOTTOM = -1.58, 0.42      # the floor's far and near edge (tiles from the plot's middle)
BED_PAD_BOTTOM, BED_PAD_RIGHT = 0.16, 0.14
COTS = ["082_cot", "073_mattress", "083_cot", "075_mattress"]
COT_W, COT_H = 0.62, 1.63              # the cots, set on the strip (the pictures are 0.76 x 2.0 tiles at their old size)
COT_BOTTOM = 0.30


def draw_bunk_bed(i):
    """The i-th strip of the planks the cots stand on, seen from above, with the cot on it."""
    w = BED_STRIP + (BED_PAD_RIGHT if i == 3 else 0.0)
    h = BED_BOTTOM - BED_TOP + BED_PAD_BOTTOM
    a = Art(w, h)
    x0, x1 = 0.0, BED_STRIP
    y0, y1 = 0.0, BED_BOTTOM - BED_TOP
    plank = BED_STRIP / 3.0
    gx0 = i * BED_STRIP                   # the strip's place along the whole floor, so the planks line up across strips
    m = a.rect(x0, y0, x1, y1)

    def col(X, Y):
        idx = np.floor((X + gx0) / plank + 1e-4)
        hh = _hash(idx, idx * 0 + 3, 11)
        k = 0.86 + 0.22 * hh
        grain = fbm(X + gx0, Y, 16.0, 21, 3, fx=0.12, fy=1.0)
        c = np.array((142, 110, 74), np.float32)[None, None, :] * (k * (0.88 + 0.24 * grain))[..., None]
        f = (X + gx0) / plank
        gap = np.clip(1.0 - np.abs(f - np.round(f)) * plank / 0.012, 0, 1)
        return c * (1 - 0.55 * gap[..., None])
    a.paint(m, col)
    # joints between boards, here and there
    for j in range(3):
        yy = y0 + (0.30 + 0.37 * ((i * 3 + j * 5) % 7) / 7.0) * (y1 - y0)
        xs = x0 + j * plank
        a.paint(a.stroke([(xs + 0.012, yy), (xs + plank - 0.012, yy)], 0.010, round_ends=False), (40, 28, 18), 0.55)
    # the frame: boards along the far and near edges, and along the two ends of the whole floor
    frame = 0.12
    fcol = _wood((98, 72, 46), 9 + i, "x", 0.3)
    boards = [a.rect(x0, y0, x1, y0 + frame), a.rect(x0, y1 - frame, x1, y1)]
    if i == 0:
        boards.append(a.rect(x0, y0, x0 + frame, y1))
    if i == 3:
        boards.append(a.rect(x1 - frame, y0, x1, y1))
    for b in boards:
        a.paint(b, fcol)
    a.paint(a.stroke([(x0, y0 + frame), (x1, y0 + frame)], 0.010, round_ends=False), OUTLINE, 0.7)
    a.paint(a.stroke([(x0, y1 - frame), (x1, y1 - frame)], 0.010, round_ends=False), OUTLINE, 0.7)
    for xx in [x0 + 0.07 + 0.2 * k for k in range(4)]:
        for yy in (y0 + frame / 2.0, y1 - frame / 2.0):
            if xx < x1 - 0.05:
                a.paint(a.ellipse(xx, yy, 0.009), (30, 24, 18), 0.8)
    # the outline: the strip's far and near edges, and the floor's two ends
    for pts in ([(x0, y0), (x1, y0)], [(x0, y1), (x1, y1)]):
        a.paint(a.stroke(pts, 0.024, round_ends=False), OUTLINE, 1.0)
    if i == 0:
        a.paint(a.stroke([(x0, y0), (x0, y1)], 0.024, round_ends=False), OUTLINE, 1.0)
    if i == 3:
        a.paint(a.stroke([(x1, y0), (x1, y1)], 0.024, round_ends=False), OUTLINE, 1.0)
    # the shadow, to the south (and, at the end, the east) only, so the strips do not shade each other
    sil = a.alpha.copy()
    a.shadow_under(0.0 if i < 3 else 0.06, 0.07, 0.04, 0.45, mask_of=sil)
    img = a.image(grain=0.02, seed=5 + i)
    # the cot on it: set at its own place on the strip, at the final size
    cot = Image.open(os.path.join(OUT if os.path.exists(os.path.join(OUT, COTS[i] + ".png")) else os.path.join(ROOT, "assets", "objects"), COTS[i] + ".png")).convert("RGBA")
    cot = cot.resize((int(round(COT_W * PX)), int(round(COT_H * PX))), Image.LANCZOS)
    cx = int(round((BED_STRIP / 2.0 - COT_W / 2.0) * PX))
    cy = int(round((COT_BOTTOM - COT_H - BED_TOP) * PX))
    img.alpha_composite(cot, (cx, cy))
    return img


def bunk():
    save(draw_bunk_roof(), "394_bunkroof.png")
    for i in range(4):
        save(draw_bunk_bed(i), "%d_bunkbed.png" % (395 + i))


# ---------------------------------------------------------------- workshop ---

# The workshop: a small timber hut (board walls, a door, a window, tools on the wall, a felt roof and a
# stovepipe) at the back of the lot, the workbench and the generator in front of it (their own pictures).
WS_X0, WS_X1 = -1.80, 1.20        # the picture's x range (tiles from the plot's middle)
WS_Y0, WS_Y1 = -3.00, 0.10       # and y range: the bottom edge is the line the hut's walls stand on, a little below


def draw_workshop():
    a = Art(WS_X1 - WS_X0, WS_Y1 - WS_Y0)

    def W(x, y):
        return (x - WS_X0, y - WS_Y0)

    hx0, hx1 = -1.55, 0.55            # the hut's walls on the ground
    wb = -0.35                         # the foot of the front wall
    wt = -1.15                         # the top of the front wall (under the eave)
    eave = -1.12
    roof_top = -2.46
    rx0, rx1 = hx0 - 0.10, hx1 + 0.10
    # ---- the front wall: boards with gaps, in shade
    wall = [W(hx0, wb), W(hx1, wb), W(hx1, wt), W(hx0, wt)]
    wm = a.poly(wall)
    wx0 = hx0 - WS_X0

    def boards(X, Y):
        bw = 0.15
        idx = np.floor((X - wx0) / bw)
        h = _hash(idx, idx * 0 + 7, 5)
        k = 0.70 + 0.16 * h
        g = fbm(X, Y, 14.0, 12, 3, fx=0.10, fy=1.0)
        f = (X - wx0) / bw
        gap = np.clip(1.0 - np.abs(f - np.round(f)) * bw / 0.010, 0, 1)
        base = np.array((150, 126, 94), np.float32)[None, None, :]
        c = base * (k * (0.86 + 0.28 * g))[..., None]
        # grime and splashes at the foot, sun-bleached at the top
        t = np.clip((Y - W(0, wt)[1]) / (wb - wt), 0, 1)
        c = c * (1.0 - 0.28 * np.clip((t - 0.7) / 0.3, 0, 1)[..., None])
        return c * (1 - 0.6 * gap[..., None])
    a.paint(wm, boards)
    # the shade under the eave
    eaves = a.poly([W(hx0, wt), W(hx1, wt), W(hx1, wt + 0.22), W(hx0, wt + 0.22)])
    ramp = Image.fromarray((np.clip(1.0 - (np.arange(a.H, dtype=np.float32)[:, None] / S - (wt - WS_Y0)) / 0.22, 0, 1) * 255 * np.ones((1, a.W), np.float32)).astype(np.uint8))
    a.paint(a.both(eaves, ramp), (10, 8, 6), 0.55)
    # battens at the corners, a skirting board along the foot
    for xx in (hx0, hx1):
        a.paint(a.rect(*W(xx - 0.035, wt), *W(xx + 0.035, wb)), (110, 86, 58), 1.0)
    a.paint(a.rect(*W(hx0, wb - 0.07), *W(hx1, wb)), (96, 74, 50), 1.0)
    a.paint(a.stroke([W(hx0, wb - 0.07), W(hx1, wb - 0.07)], 0.010, round_ends=False), OUTLINE, 0.7)
    # ---- the door
    dx0, dx1 = -1.30, -0.76
    dt = wb - 0.68
    door = a.rect(*W(dx0, dt), *W(dx1, wb - 0.07))

    def doorcol(X, Y):
        n = fbm(X, Y, 14.0, 31, 3, fx=0.12, fy=1.0)
        k = 0.85 + 0.30 * n
        return np.array((76, 94, 82), np.float32)[None, None, :] * k[..., None]
    a.paint(a.rect(*W(dx0 - 0.045, dt - 0.045), *W(dx1 + 0.045, wb - 0.07)), (186, 170, 138), 1.0)
    a.paint(door, doorcol)
    a.paint(a.stroke([W(dx0 + 0.04, wb - 0.11), W(dx1 - 0.04, dt + 0.05)], 0.030, round_ends=False), (52, 66, 56), 0.9)
    for yy in (dt + 0.10, wb - 0.17):
        a.paint(a.stroke([W(dx0 + 0.03, yy), W(dx1 - 0.03, yy)], 0.028, round_ends=False), (52, 66, 56), 0.9)
    hxk, hyk = W(dx1 - 0.08, (dt + wb) / 2.0)
    a.paint(a.ellipse(hxk, hyk, 0.026), (196, 170, 70), 1.0)
    a.paint(a.stroke(a.rect(*W(dx0, dt), *W(dx1, wb - 0.07)) and [W(dx0, dt), W(dx1, dt), W(dx1, wb - 0.07), W(dx0, wb - 0.07)], 0.016, closed=True), OUTLINE, 1.0)
    # a step: a block of concrete
    a.paint(a.rect(*W(dx0 - 0.08, wb - 0.07), *W(dx1 + 0.08, wb + 0.07)), (136, 134, 126), 1.0)
    a.paint(a.stroke([W(dx0 - 0.08, wb - 0.07), W(dx1 + 0.08, wb - 0.07), W(dx1 + 0.08, wb + 0.07), W(dx0 - 0.08, wb + 0.07)], 0.014, closed=True), OUTLINE, 1.0)
    # ---- the window, with a cross frame
    wx_0, wx_1 = -0.46, 0.06
    wy_0, wy_1 = wb - 0.60, wb - 0.34
    frame = a.rect(*W(wx_0 - 0.04, wy_0 - 0.04), *W(wx_1 + 0.04, wy_1 + 0.04))
    a.paint(frame, (206, 196, 168), 1.0)

    def glass(X, Y):
        t = np.clip((Y - W(0, wy_0)[1]) / (wy_1 - wy_0), 0, 1)[..., None]
        return np.array((150, 176, 184), np.float32)[None, None, :] * (1 - t) + np.array((54, 66, 74), np.float32)[None, None, :] * t
    a.paint(a.rect(*W(wx_0, wy_0), *W(wx_1, wy_1)), glass)
    a.paint(a.stroke([W(wx_0 + 0.06, wy_1 - 0.02), W(wx_0 + 0.16, wy_0 + 0.02)], 0.020), (236, 244, 244), 0.55)
    a.paint(a.stroke([W((wx_0 + wx_1) / 2.0, wy_0), W((wx_0 + wx_1) / 2.0, wy_1)], 0.020, round_ends=False), (206, 196, 168), 1.0)
    a.paint(a.stroke([W(wx_0, (wy_0 + wy_1) / 2.0), W(wx_1, (wy_0 + wy_1) / 2.0)], 0.020, round_ends=False), (206, 196, 168), 1.0)
    a.paint(a.stroke([W(wx_0 - 0.04, wy_0 - 0.04), W(wx_1 + 0.04, wy_0 - 0.04), W(wx_1 + 0.04, wy_1 + 0.04), W(wx_0 - 0.04, wy_1 + 0.04)], 0.014, closed=True), OUTLINE, 1.0)
    a.paint(a.rect(*W(wx_0 - 0.07, wy_1 + 0.04), *W(wx_1 + 0.07, wy_1 + 0.075)), (170, 146, 108), 1.0)
    # ---- tools on nails, to the right of the window: a saw, a hammer, a wrench
    tx = 0.30
    # the saw: a long blade and a handle
    blade = [W(tx - 0.07, wb - 0.62), W(tx + 0.05, wb - 0.62), W(tx + 0.02, wb - 0.26), W(tx - 0.07, wb - 0.26)]
    a.paint(a.poly(blade), (186, 190, 188), 1.0)
    a.paint(a.stroke(blade, 0.010, closed=True), OUTLINE, 0.9)
    a.paint(a.rect(*W(tx - 0.06, wb - 0.70), *W(tx + 0.045, wb - 0.62)), (150, 50, 40), 1.0)
    a.paint(a.stroke([W(tx - 0.06, wb - 0.70), W(tx + 0.045, wb - 0.70), W(tx + 0.045, wb - 0.62), W(tx - 0.06, wb - 0.62)], 0.010, closed=True), OUTLINE, 0.9)
    # a hammer
    hx_ = tx + 0.20
    a.paint(a.stroke([W(hx_, wb - 0.62), W(hx_, wb - 0.30)], 0.030, round_ends=False), (150, 112, 68), 1.0)
    a.paint(a.rect(*W(hx_ - 0.07, wb - 0.67), *W(hx_ + 0.07, wb - 0.59)), (92, 96, 100), 1.0)
    a.paint(a.stroke([W(hx_ - 0.07, wb - 0.67), W(hx_ + 0.07, wb - 0.67), W(hx_ + 0.07, wb - 0.59), W(hx_ - 0.07, wb - 0.59)], 0.010, closed=True), OUTLINE, 0.9)
    # ---- the roof: felt in courses over battens, a fascia along the eave
    roof = [W(rx0, roof_top), W(rx1, roof_top), W(rx1, eave), W(rx0, eave)]
    rm = a.poly(roof)
    ry0 = roof_top - WS_Y0
    ry1 = eave - WS_Y0
    rx0w = rx0 - WS_X0

    def felt(X, Y):
        """Wooden shingles in staggered courses, each its own shade, grey with weather."""
        course, sw = 0.16, 0.20
        row = np.floor((Y - ry0) / course)
        xoff = (row % 2) * 0.5 * sw
        colx = np.floor((X - rx0w + xoff) / sw)
        h = _hash(colx, row, 4)
        h2 = _hash(colx, row, 14)
        k = 0.74 + 0.40 * h
        warm = np.array((134, 106, 78), np.float32)[None, None, :]
        grey = np.array((104, 100, 92), np.float32)[None, None, :]
        base = warm * (1 - h2[..., None]) + grey * h2[..., None]
        n = fbm(X, Y, 8.0, 44, 2, fx=0.5, fy=1.0)
        c = base * (k * (0.88 + 0.24 * n))[..., None]
        fy_ = ((Y - ry0) / course) % 1.0
        fx_ = ((X - rx0w + xoff) / sw) % 1.0
        edge = np.clip((fy_ - 0.78) / 0.22, 0, 1)            # the lower end of each shingle: a shadow line then the course below
        gap = np.clip(1.0 - np.minimum(fx_, 1 - fx_) * sw / 0.014, 0, 1)
        c = c * (1 - 0.42 * edge[..., None]) * (1 - 0.55 * gap[..., None])
        t = np.clip((Y - ry0) / (ry1 - ry0), 0, 1)
        moss = np.clip((fbm(X, Y, 4.0, 63, 3) - 0.60) * 4.0, 0, 1) * np.clip((t - 0.35) / 0.65, 0, 1)
        return c * (1 - 0.55 * moss[..., None]) + np.array((58, 76, 46), np.float32)[None, None, :] * 0.55 * moss[..., None]
    a.paint(rm, felt)
    # a patch of galvanised sheet, nailed over where the shingles went
    pat = [W(-1.28, -1.52), W(-0.74, -1.54), W(-0.72, -1.30), W(-1.30, -1.28)]
    pm_ = a.poly(pat)

    def tin(X, Y):
        ph = (X * 22.0)
        k = 0.78 + 0.28 * (0.5 + 0.5 * np.sin(ph))
        return np.array((156, 160, 154), np.float32)[None, None, :] * k[..., None]
    a.paint(pm_, tin)
    a.paint(a.stroke(pat, 0.014, closed=True), OUTLINE, 1.0)
    a.paint(a.stroke(roof, 0.024, closed=True), OUTLINE, 1.0)
    # the fascia: a timber board along the eave, and a drip of shade on the wall beneath it
    fas = a.rect(*W(rx0 - 0.02, eave), *W(rx1 + 0.02, eave + 0.085))
    a.paint(fas, _wood((132, 100, 66), 77, "x", 0.3))
    a.paint(a.stroke([W(rx0 - 0.02, eave), W(rx1 + 0.02, eave), W(rx1 + 0.02, eave + 0.085), W(rx0 - 0.02, eave + 0.085)], 0.016, closed=True), OUTLINE, 1.0)
    # ---- the stovepipe: a rusty pipe through the roof, with a collar and a rain cap
    px0 = 0.12
    base_y = -1.72
    top_y = -2.58
    a.paint(a.poly([W(px0 - 0.15, base_y + 0.03), W(px0 + 0.15, base_y + 0.03), W(px0 + 0.12, base_y - 0.03), W(px0 - 0.12, base_y - 0.03)]), (60, 60, 58), 1.0)
    pipe = a.rect(*W(px0 - 0.065, top_y), *W(px0 + 0.065, base_y))

    def pipecol(X, Y):
        t = np.clip((X - (px0 - 0.065 - WS_X0)) / 0.13, 0, 1)
        k = 1.25 - 0.65 * t
        n = fbm(X, Y, 8.0, 71, 2, fx=0.3, fy=1.0)
        soot = np.clip((Y - (top_y - WS_Y0) - 0.0) / 0.2, 0, 1)
        c = np.array((124, 82, 60), np.float32)[None, None, :] * (k * (0.8 + 0.4 * n))[..., None]
        return c * (0.7 + 0.3 * soot[..., None])
    a.paint(pipe, pipecol)
    a.paint(a.stroke([W(px0 - 0.065, top_y), W(px0 - 0.065, base_y), W(px0 + 0.065, base_y), W(px0 + 0.065, top_y)], 0.014), OUTLINE, 1.0)
    for yy in (base_y - 0.22, base_y - 0.46):
        a.paint(a.stroke([W(px0 - 0.07, yy), W(px0 + 0.07, yy)], 0.016, round_ends=False), (60, 46, 36), 0.9)
    cap = [W(px0 - 0.12, top_y), W(px0, top_y - 0.10), W(px0 + 0.12, top_y)]
    a.paint(a.poly(cap), (94, 90, 86), 1.0)
    a.paint(a.stroke(cap, 0.014, closed=True), OUTLINE, 1.0)
    # ---- the shadows
    foot = [W(hx0, -1.50), W(rx1, -1.50), W(rx1, wb), W(hx0, wb)]
    a.shadow_under(0.26, 0.22, 0.07, 0.30, mask_of=np.asarray(a.poly(foot), np.float32) / 255.0)
    sil = a.alpha.copy()
    a.shadow_under(0.06, 0.06, 0.03, 0.30, mask_of=sil)
    return a.image(grain=0.02, seed=6)


def workshop():
    save(draw_workshop(), "399_workshop.png")


# -------------------------------------------------------------- greenhouse ---

# The greenhouse beds: each bed under a low tunnel of plastic sheet over hoops, the sheet weighted down with
# bricks and gathered and tied at the ends, the lettuce dim through it. Seen from above, so it is the sheet's
# round back that shows: a bright stripe where the light catches it, dark at the sides, a rib at each hoop.
TUN_W, TUN_H = 1.30, 2.50


def draw_tunnel(variant):
    a = Art(TUN_W, TUN_H)
    cx = TUN_W / 2.0
    bw = 0.46                      # half the width of the bed's timber frame
    fy0, fy1 = 0.20, 2.08          # the frame's far and near ends
    sw = 0.385                     # half the width of the sheet over it
    # ---- the timber bed under it, and the soil
    frame = a.rect(cx - bw, fy0, cx + bw, fy1)
    a.paint(frame, _wood((120, 88, 56), 3 + variant, "y", 0.3))
    a.paint(a.stroke([(cx - bw, fy0), (cx + bw, fy0), (cx + bw, fy1), (cx - bw, fy1)], 0.022, closed=True), OUTLINE, 1.0)
    soil = a.rect(cx - bw + 0.07, fy0 + 0.07, cx + bw - 0.07, fy1 - 0.07)

    def soilcol(X, Y):
        n = fbm(X, Y, 18.0, 5 + variant, 3)
        return np.array((50, 36, 26), np.float32)[None, None, :] * (0.8 + 0.4 * n)[..., None]
    a.paint(soil, soilcol)
    # the lettuces, in two rows (a tall crop for the second variant)
    rows = 8
    for r in range(rows):
        yy = fy0 + 0.22 + (fy1 - fy0 - 0.44) * r / (rows - 1)
        for dx in (-0.17, 0.17):
            xx = cx + dx + 0.012 * math.sin(r * 2.3 + dx * 9)
            if variant == 0:
                for ang in range(0, 360, 72):
                    ox_ = 0.045 * math.cos(math.radians(ang + r * 20))
                    oy_ = 0.045 * math.sin(math.radians(ang + r * 20))
                    a.paint(a.ellipse(xx + ox_, yy + oy_, 0.052), (88, 142, 58), 1.0)
                a.paint(a.ellipse(xx, yy, 0.04), (140, 190, 90), 1.0)
            else:
                for ang in range(0, 360, 90):
                    ox_ = 0.05 * math.cos(math.radians(ang + r * 30))
                    oy_ = 0.05 * math.sin(math.radians(ang + r * 30))
                    a.paint(a.ellipse(xx + ox_, yy + oy_, 0.055, 0.04), (64, 120, 50), 1.0)
                a.paint(a.ellipse(xx, yy, 0.04), (226, 170, 40) if r % 2 else (170, 200, 80), 1.0)
    # ---- the sheet: a milky translucent tunnel, round across, dark at its sides
    sy0, sy1 = fy0 - 0.02, fy1 + 0.02
    sheet = a.poly([(cx - sw, sy0 + 0.06), (cx - sw + 0.05, sy0), (cx + sw - 0.05, sy0), (cx + sw, sy0 + 0.06),
                    (cx + sw, sy1 - 0.06), (cx + sw - 0.05, sy1), (cx - sw + 0.05, sy1), (cx - sw, sy1 - 0.06)])
    hoops = [fy0 + 0.20 + (fy1 - fy0 - 0.40) * i / 3.0 for i in range(4)]
    open_roll = variant == 1
    roll_y = fy0 + 0.60

    def plastic(X, Y):
        u = np.clip((X - (cx - sw)) / (2 * sw), 0, 1)            # 0 at the left side, 1 at the right
        # the tunnel's round back: bright at 0.35 across (light from the north west), dark at the far side
        bright = np.exp(-((u - 0.34) / 0.20) ** 2)
        side = np.power(np.abs(u - 0.5) * 2.0, 2.4)
        # the sheet sags between the hoops
        sag = np.zeros_like(u)
        for hy in hoops:
            sag = np.maximum(sag, np.exp(-((Y - hy) / 0.035) ** 2))
        wr = fbm(X, Y, 5.0, 91 + variant, 3, fx=1.0, fy=1.6)
        k = 0.46 + 0.52 * bright - 0.42 * side + 0.10 * (wr - 0.5) + 0.14 * sag
        alpha = np.clip(0.50 + 0.28 * side + 0.28 * bright + 0.08 * wr, 0, 1)
        return k, alpha
    # paint the sheet in two steps: its colour and its opacity (a milky veil over what is under it)
    ys, xs = None, None
    k_fun = lambda X, Y: plastic(X, Y)[0]
    box_mask = sheet

    def veil_colour(X, Y):
        k, al = plastic(X, Y)
        light = np.array((236, 244, 238), np.float32)[None, None, :]
        dark = np.array((82, 104, 96), np.float32)[None, None, :]
        kk = np.clip(k, 0, 1.2)[..., None]
        return dark * (1 - np.clip(kk, 0, 1)) + light * np.clip(kk, 0, 1)

    def paint_veil(mask):
        box = mask.getbbox()
        if box is None:
            return
        x0, y0, x1, y1 = box
        m = np.asarray(mask.crop(box), np.float32) / 255.0
        yy, xx = np.mgrid[y0:y1, x0:x1]
        X = xx.astype(np.float32) / S
        Y = yy.astype(np.float32) / S
        k, al = plastic(X, Y)
        col = veil_colour(X, Y)
        al = np.clip(al, 0, 1) * m
        sub = a.prem[y0:y1, x0:x1]
        asub = a.alpha[y0:y1, x0:x1]
        sub[...] = col * al[..., None] + sub * (1 - al[..., None])
        asub[...] = al + asub * (1 - al)
    if open_roll:
        # one end rolled back: the sheet is a tube across the bed at roll_y, the lettuce clear above it
        closed = a.rect(cx - sw, roll_y + 0.10, cx + sw, sy1)
        paint_veil(a.both(sheet, closed))
        tube = a.rect(cx - sw - 0.02, roll_y - 0.06, cx + sw + 0.02, roll_y + 0.10)

        def tubecol(X, Y):
            t = np.clip((Y - (roll_y - 0.06)) / 0.16, 0, 1)
            k = 1.12 - 0.62 * t
            return np.array((222, 232, 226), np.float32)[None, None, :] * k[..., None]
        a.paint(tube, tubecol)
        a.paint(a.stroke([(cx - sw - 0.02, roll_y - 0.06), (cx + sw + 0.02, roll_y - 0.06), (cx + sw + 0.02, roll_y + 0.10), (cx - sw - 0.02, roll_y + 0.10)], 0.016, closed=True), OUTLINE, 0.9)
        a.paint(a.stroke([(cx - sw + 0.02, roll_y + 0.0), (cx + sw - 0.02, roll_y + 0.0)], 0.008, round_ends=False), (250, 255, 250), 0.6)
        sheet_edge_y = roll_y + 0.10
    else:
        paint_veil(sheet)
        sheet_edge_y = sy0
    # the hoops, felt as ribs under the sheet
    for hy in hoops:
        if open_roll and hy < sheet_edge_y:
            continue
        a.paint(a.stroke([(cx - sw + 0.01, hy), (cx + sw - 0.01, hy)], 0.026, round_ends=False), (30, 40, 36), 0.22, clip=sheet)
        a.paint(a.stroke([(cx - sw + 0.01, hy - 0.020), (cx + sw - 0.01, hy - 0.020)], 0.010, round_ends=False), (255, 255, 250), 0.30, clip=sheet)
    # creases and drops
    rng = np.random.RandomState(40 + variant)
    for _ in range(7):
        x0_ = cx + rng.uniform(-0.3, 0.3)
        y0_ = rng.uniform(sheet_edge_y + 0.1, sy1 - 0.15)
        ln = [(x0_, y0_), (x0_ + rng.uniform(-0.12, 0.12), y0_ + rng.uniform(0.08, 0.20))]
        a.paint(a.stroke(ln, 0.008), (255, 255, 250), 0.35, clip=sheet)
    for _ in range(26):
        x0_ = cx + rng.uniform(-0.34, 0.34)
        y0_ = rng.uniform(sheet_edge_y + 0.04, sy1 - 0.04)
        a.paint(a.ellipse(x0_, y0_, 0.010), (255, 255, 255), 0.65, clip=sheet)
    # gathered and tied at the near end: the sheet pinched into a fan and a knot of cord
    for sgn in (1,):
        ty = sy1 + 0.05
        pts = [(cx - sw + 0.05, sy1 - 0.02), (cx, ty + 0.06), (cx + sw - 0.05, sy1 - 0.02)]
        a.paint(a.poly(pts), (206, 220, 212), 0.85)
        for off in (-0.28, -0.14, 0.0, 0.14, 0.28):
            a.paint(a.stroke([(cx + off, sy1 - 0.02), (cx + off * 0.2, ty + 0.05)], 0.008), (90, 112, 104), 0.5)
        a.paint(a.stroke(pts, 0.016, closed=True), OUTLINE, 0.9)
        a.paint(a.ellipse(cx, ty + 0.06, 0.028), (176, 150, 100), 1.0)
        a.paint(a.stroke([(cx, ty + 0.06), (cx + 0.05, ty + 0.15)], 0.010), (176, 150, 100), 1.0)
    # the far end: tucked under the frame's end board
    a.paint(a.stroke([(cx - sw + 0.04, sy0 + 0.03), (cx + sw - 0.04, sy0 + 0.03)], 0.012, round_ends=False), (255, 255, 250), 0.35)
    a.paint(a.stroke([(cx - sw + 0.05, sy0 + 0.0), (cx - sw + 0.05, sy0 + 0.0)], 0.01), OUTLINE, 0.0)
    a.paint(a.stroke([(cx - sw, sy0 + 0.06), (cx - sw + 0.05, sy0), (cx + sw - 0.05, sy0), (cx + sw, sy0 + 0.06),
                      (cx + sw, sy1 - 0.06), (cx + sw - 0.05, sy1), (cx - sw + 0.05, sy1), (cx - sw, sy1 - 0.06)], 0.016, closed=True), OUTLINE, 0.9,
            clip=None if not open_roll else a.rect(cx - sw - 0.1, sheet_edge_y, cx + sw + 0.1, sy1 + 0.1))
    # bricks along both sides weigh the sheet down
    for side in (-1, 1):
        for i in range(5):
            by = fy0 + 0.25 + (fy1 - fy0 - 0.5) * i / 4.0 + 0.02 * ((i + variant) % 2)
            if open_roll and by < sheet_edge_y + 0.05:
                continue
            bx = cx + side * (sw + 0.005)
            brick = [(bx - 0.050, by - 0.075), (bx + 0.050, by - 0.075), (bx + 0.050, by + 0.075), (bx - 0.050, by + 0.075)]
            a.paint(a.poly(brick), (150, 84, 62) if (i + variant) % 3 else (130, 128, 120), 1.0)
            a.paint(a.stroke(brick, 0.014, closed=True), OUTLINE, 1.0)
            a.paint(a.stroke([(bx - 0.030, by - 0.045), (bx + 0.030, by - 0.045)], 0.008, round_ends=False), (210, 150, 120), 0.5)
    # ---- the shadow
    a.shadow_under(0.07, 0.08, 0.05, 0.42)
    return a.image(grain=0.02, seed=7 + variant)


def greenhouse():
    save(draw_tunnel(0), "400_tunnel.png")
    save(draw_tunnel(1), "401_tunnel.png")


# -------------------------------------------------------------- floodlights ---

# A floodlight: a bank of four lamps on a steel pole bolted to a concrete block, guyed with wire, with the
# cable running to the generator in the middle of the building. Two of them (the cable runs the other way).
FL_X0, FL_X1 = -0.78, 0.82        # the picture's x range from the pole (tiles; the yard keeps a picture within two tiles of the plot's middle)
FL_Y0, FL_Y1 = -2.62, 0.78        # and y range: the pole's foot is at y 0.12, the lamps at about -2.15


def draw_floodlight(side):
    """side -1: the pole stands west of the generator (its cable runs east); +1: east of it (cable runs west)."""
    a = Art(FL_X1 - FL_X0, FL_Y1 - FL_Y0)

    def W(x, y):
        return (x - FL_X0, y - FL_Y0)

    steel = (78, 88, 98)
    # ---- guy wires first (behind the pole): from the pole at two thirds up to pegs on the ground
    top = -1.62
    pegs = [(-0.64, 0.20), (0.64, 0.20), (-0.18 * side, -0.26)]
    for (gx, gy) in pegs[:2]:
        pts = [W(0.0, top), W(gx * 0.5, (top + gy) / 2.0 + 0.01), W(gx, gy)]
        a.paint(a.stroke(pts, 0.016), (10, 8, 6), 0.35)
        a.paint(a.stroke(pts, 0.008), (176, 180, 182), 0.95)
    for (gx, gy) in pegs[:2]:
        px_, py_ = W(gx, gy)
        a.paint(a.ellipse(px_, py_, 0.034, 0.026), (36, 30, 24), 1.0)
        a.paint(a.ellipse(px_ - 0.006, py_ - 0.006, 0.016, 0.012), (170, 150, 120), 0.8)
    # ---- the concrete block
    bx0, bx1 = -0.28, 0.28
    gy0, gy1 = -0.10, 0.14            # its footprint on the ground
    hh = 0.30                          # its height; it shows K * that above the ground
    top_face = [W(bx0, gy0 - K * hh), W(bx1, gy0 - K * hh), W(bx1, gy1 - K * hh), W(bx0, gy1 - K * hh)]
    front = [W(bx0, gy1 - K * hh), W(bx1, gy1 - K * hh), W(bx1, gy1), W(bx0, gy1)]
    a.paint(a.poly(front), lambda X, Y: np.array((120, 118, 110), np.float32)[None, None, :] * (0.80 + 0.30 * fbm(X, Y, 18.0, 5, 2))[..., None])
    a.paint(a.poly(top_face), lambda X, Y: np.array((160, 158, 148), np.float32)[None, None, :] * (0.88 + 0.24 * fbm(X, Y, 16.0, 6, 2))[..., None])
    a.paint(a.stroke(front, 0.016, closed=True), OUTLINE, 1.0)
    a.paint(a.stroke(top_face, 0.016, closed=True), OUTLINE, 1.0)
    # four anchor bolts on the block, and the pole's foot plate
    foot_x, foot_y = W(0.0, (gy0 + gy1) / 2.0 - K * hh)
    for dx in (-0.19, 0.19):
        for dy in (-0.05, 0.05):
            a.paint(a.ellipse(foot_x + dx, foot_y + dy, 0.012), (40, 38, 34), 1.0)
    a.paint(a.ellipse(foot_x, foot_y, 0.105, 0.05), (96, 102, 108), 1.0)
    a.paint(a.stroke(a.ellipse(foot_x, foot_y, 0.105, 0.05) and [(foot_x - 0.105, foot_y), (foot_x + 0.105, foot_y)], 0.004), (0, 0, 0), 0.0)
    # sandbags at the foot
    for k_, (sx, sy) in enumerate(((-0.30, 0.20), (-0.12, 0.23), (0.30, 0.19))):
        bag = a.ellipse(*W(sx, sy), 0.105, 0.052)
        a.paint(bag, (176, 158, 118), 1.0)
        a.paint(a.stroke([W(sx - 0.07, sy - 0.01), W(sx + 0.07, sy - 0.01)], 0.008), (120, 104, 76), 0.7)
        a.paint(a.stroke([(W(sx, sy)[0] + math.cos(t) * 0.105, W(sx, sy)[1] + math.sin(t) * 0.052) for t in np.linspace(0, 2 * math.pi, 28)], 0.012, closed=True), OUTLINE, 0.95)
    # ---- the pole: a tapering tube, round (light on the left, dark on the right)
    y_bot = foot_y + FL_Y0 - 0.0
    pole_bot, pole_top = (gy0 + gy1) / 2.0 - K * hh, -2.04
    pb, pt = 0.060, 0.042                     # half widths at the foot and at the head
    pole = [W(-pb, pole_bot), W(pb, pole_bot), W(pt, pole_top), W(-pt, pole_top)]

    def tube(X, Y):
        u = np.clip((X - W(0, 0)[0]) / 0.07, -1, 1)          # -1 left edge .. 1 right edge (about)
        k = 1.18 - 0.60 * (u * 0.5 + 0.5)
        n = fbm(X, Y, 10.0, 12, 2, fx=0.2, fy=1.0)
        return np.array(steel, np.float32)[None, None, :] * (k * (0.9 + 0.2 * n))[..., None]
    a.paint(a.poly(pole), tube)
    a.paint(a.stroke(pole, 0.016, closed=True), OUTLINE, 1.0)
    # collars where the sections join, and a row of rungs up the pole's front
    for yy in (pole_bot - 0.40, pole_bot - 0.95, pole_bot - 1.45):
        a.paint(a.rect(*W(-0.075, yy), *W(0.075, yy + 0.035)), (58, 64, 72), 1.0)
        a.paint(a.stroke([W(-0.075, yy), W(0.075, yy), W(0.075, yy + 0.035), W(-0.075, yy + 0.035)], 0.008, closed=True), OUTLINE, 0.8)
    # the guy wires' anchor on the pole
    a.paint(a.ellipse(*W(0.0, top), 0.030), (50, 54, 60), 1.0)
    a.paint(a.stroke([(W(0.0, top)[0] + math.cos(t) * 0.030, W(0.0, top)[1] + math.sin(t) * 0.030) for t in np.linspace(0, 2 * math.pi, 18)], 0.008, closed=True), OUTLINE, 0.9)
    # ---- the lamp head: a crossbar, then a housing with four lamps
    hy = -2.16                                 # the middle of the housing
    hw, hhh = 0.50, 0.30                       # half its width and height
    a.paint(a.rect(*W(-0.07, hy + hhh - 0.01), *W(0.07, hy + hhh + 0.10)), (60, 66, 74), 1.0)
    a.paint(a.stroke([W(-0.07, hy + hhh), W(-0.07, hy + hhh + 0.10), W(0.07, hy + hhh + 0.10), W(0.07, hy + hhh)], 0.010), OUTLINE, 0.9)
    housing = [W(-hw, hy - hhh), W(hw, hy - hhh), W(hw, hy + hhh), W(-hw, hy + hhh)]
    # the visor on top, seen from a little above
    visor = [W(-hw - 0.02, hy - hhh - 0.07), W(hw + 0.02, hy - hhh - 0.07), W(hw, hy - hhh), W(-hw, hy - hhh)]
    a.paint(a.poly(visor), (116, 124, 132), 1.0)
    a.paint(a.stroke(visor, 0.014, closed=True), OUTLINE, 1.0)
    hm = a.poly(housing)

    def case(X, Y):
        t = np.clip((Y - W(0, hy - hhh)[1]) / (2 * hhh), 0, 1)[..., None]
        base = np.array((52, 58, 64), np.float32)[None, None, :]
        return base * (1.15 - 0.35 * t)
    a.paint(hm, case)
    a.paint(a.stroke(housing, 0.018, closed=True), OUTLINE, 1.0)
    for lx in (-0.25, 0.25):
        for ly in (-0.145, 0.145):
            cx_, cy_ = W(lx, hy + ly)
            r_ = 0.108
            # the lamp: a ring, a dark reflector and a glowing lens
            a.paint(a.ellipse(cx_, cy_, r_ + 0.014), (96, 102, 108), 1.0)
            a.paint(a.ellipse(cx_, cy_, r_), (34, 36, 38), 1.0)

            def lens(X, Y, cx_=cx_, cy_=cy_, r_=r_):
                d = np.sqrt((X - cx_) ** 2 + (Y - cy_) ** 2) / (r_ * 0.86)
                t = np.clip(d, 0, 1)[..., None]
                inner = np.array((255, 252, 232), np.float32)[None, None, :]
                outer = np.array((236, 206, 130), np.float32)[None, None, :]
                return inner * (1 - t) + outer * t
            a.paint(a.ellipse(cx_, cy_, r_ * 0.86), lens, 1.0)
            a.paint(a.ellipse(cx_ - 0.03, cy_ - 0.03, 0.022, 0.016), (255, 255, 255), 0.85)
            a.paint(a.stroke([(cx_ + math.cos(t) * r_, cy_ + math.sin(t) * r_) for t in np.linspace(0, 2 * math.pi, 28)], 0.010, closed=True), OUTLINE, 0.95)
    # ---- the cable on the ground, to the generator
    sgn = -side                                  # towards the middle: east (+) for the west pole
    ctrl = [(0.0, gy1), (sgn * 0.16, 0.31), (sgn * 0.44, 0.31), (sgn * 0.64, 0.17)]
    cab = []
    for t in np.linspace(0.0, 1.0, 24):         # a cubic curve through the four points
        u = 1 - t
        cab.append(W(u ** 3 * ctrl[0][0] + 3 * u * u * t * ctrl[1][0] + 3 * u * t * t * ctrl[2][0] + t ** 3 * ctrl[3][0],
                     u ** 3 * ctrl[0][1] + 3 * u * u * t * ctrl[1][1] + 3 * u * t * t * ctrl[2][1] + t ** 3 * ctrl[3][1]))
    a.paint(a.stroke(cab, 0.034), (8, 6, 5), 0.55)
    a.paint(a.stroke(cab, 0.020), (22, 20, 18), 1.0)
    a.paint(a.stroke([(x, y - 0.006) for x, y in cab], 0.006), (96, 92, 84), 0.7)
    # ---- the shadows: the pole's long one over the ground to the south east, with the lamps' box at its end
    sh = a.stroke([W(0.06, 0.10), W(0.46, 0.40)], 0.10)
    sh = a.either(sh, a.poly([W(0.32, 0.36), W(0.66, 0.36), W(0.64, 0.62), W(0.36, 0.64)]))
    a.shadow_under(0.0, 0.0, 0.04, 0.38, mask_of=np.asarray(sh, np.float32) / 255.0)
    sil = a.alpha.copy()
    a.shadow_under(0.05, 0.05, 0.035, 0.34, mask_of=sil)
    return a.image(grain=0.02, seed=21 + side)


def floodlights():
    save(draw_floodlight(-1), "402_floodlight.png")
    save(draw_floodlight(1), "403_floodlight.png")


# ------------------------------------------------------------------ the shade ---

# The shade shelter over the yard's workbench (and the smaller ones in the streets): a canvas awning stretched
# on four poles, its edges drawn in between them, the middle sagging, guy ropes to pegs. It replaces the flat
# blue tarp (117_tarp): that one was opaque and hid the worktable, the generator and the crate beneath it.
# This one is shade cloth, see-through enough to show what is under it, in the shade. Same picture size
# (7.464 x 6.402 tiles at 112 pixels to the tile) and the same footprint as the one it replaces, so the places
# that name it (assets/data/map.json, dressing.json) are unchanged: the awning is 5.8 x 4.6 tiles and its middle is
# 3.62 and 2.92 tiles from the picture's top left.
TARP_W, TARP_H = 836.0 / 112.0, 717.0 / 112.0
TARP_PX = 112.0
TARP_BODY = (0.72, 0.62, 6.52, 5.22)            # x0, y0, x1, y1 of the awning between its poles
TARP = {
    "117_tarp": dict(base=(92, 102, 64), cord=(200, 186, 144), seed=2),
    "404_tarp": dict(base=(190, 168, 120), cord=(126, 98, 66), seed=6),
}


def draw_tarp(spec):
    a = Art(TARP_W, TARP_H)
    x0, y0, x1, y1 = TARP_BODY
    base = spec["base"]
    seed = spec["seed"]
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    bow = 0.17                                   # how far each edge hangs in between its poles
    # the awning's outline: four edges, each curved in between the poles
    n = 28
    pts = []
    for i in range(n + 1):                       # north edge, west to east
        t = i / n
        pts.append((x0 + (x1 - x0) * t, y0 + bow * math.sin(math.pi * t)))
    for i in range(1, n + 1):                    # east edge
        t = i / n
        pts.append((x1 - bow * 1.0 * math.sin(math.pi * t), y0 + (y1 - y0) * t))
    for i in range(1, n + 1):                    # south edge, east to west
        t = i / n
        pts.append((x1 - (x1 - x0) * t, y1 - bow * math.sin(math.pi * t)))
    for i in range(1, n):                        # west edge, south to north
        t = i / n
        pts.append((x0 + bow * math.sin(math.pi * t), y1 - (y1 - y0) * t))
    body = a.poly(pts)

    def canvas(X, Y):
        dx = (X - cx) / ((x1 - x0) / 2.0)
        dy = (Y - cy) / ((y1 - y0) / 2.0)
        r2 = dx * dx + dy * dy
        k = 1.0 - 0.20 * np.exp(-r2 * 1.6)                    # the middle sags: darker
        k = k + 0.08 * (-dx * 0.5 - dy * 0.5)                  # light from the north west
        for (kx, ky) in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
            ang = np.arctan2(Y - ky, X - kx)
            dist = np.sqrt((X - kx) ** 2 + (Y - ky) ** 2)
            k = k + 0.07 * np.sin(ang * 13.0 + kx) * np.exp(-dist / 1.6)   # folds fanning out from each pole
        wr = fbm(X, Y, 1.3, seed, 3)
        k = k * (0.93 + 0.14 * wr)
        return np.array(base, np.float32)[None, None, :] * k[..., None]

    def veil(X, Y):
        """How much of the awning shows: the cloth is see-through shade cloth, thicker near its hem."""
        dx = np.abs((X - cx) / ((x1 - x0) / 2.0))
        dy = np.abs((Y - cy) / ((y1 - y0) / 2.0))
        edge = np.maximum(dx, dy)
        return np.clip(0.44 + 0.34 * np.clip((edge - 0.55) / 0.45, 0, 1) + 0.05 * (fbm(X, Y, 3.0, seed + 3, 2) - 0.5), 0, 1)

    def paint_cloth(mask):
        box = mask.getbbox()
        x_0, y_0, x_1, y_1 = box
        m = np.asarray(mask.crop(box), np.float32) / 255.0
        yy, xx = np.mgrid[y_0:y_1, x_0:x_1]
        X = xx.astype(np.float32) / S
        Y = yy.astype(np.float32) / S
        col = canvas(X, Y)
        al = veil(X, Y) * m
        sub = a.prem[y_0:y_1, x_0:x_1]
        asub = a.alpha[y_0:y_1, x_0:x_1]
        sub[...] = col * al[..., None] + sub * (1 - al[..., None])
        asub[...] = al + asub * (1 - al)

    # the ground under the awning is in its shade, and the shade falls to the south east: laid first
    shade_src = np.asarray(body, np.float32) / 255.0
    a.shadow_under(0.30, 0.36, 0.14, 0.30, mask_of=shade_src)
    paint_cloth(body)
    # the seams: three widths of cloth, a stitched pair of lines at each join
    for fx in (1.0 / 3.0, 2.0 / 3.0):
        xs = x0 + (x1 - x0) * fx
        ln = [(xs, y0 + bow * 0.5), (xs, y1 - bow * 0.5)]
        a.paint(a.stroke(ln, 0.030, round_ends=False), shade(base, 0.62), 0.55, clip=body)
        a.paint(a.dashes([(xs - 0.035, ln[0][1]), (xs - 0.035, ln[1][1])], 0.009, 0.05, 0.035), spec["cord"], 0.8, clip=body)
        a.paint(a.dashes([(xs + 0.035, ln[0][1]), (xs + 0.035, ln[1][1])], 0.009, 0.05, 0.035), spec["cord"], 0.8, clip=body)
    # a hem round the edge: a band of webbing, opaque, with a stitch line inside it
    hem_w = 0.115
    hem = a.both(a.stroke(pts, hem_w * 2.0, closed=True), body)
    a.paint(hem, shade(base, 0.62), 0.97)
    a.paint(a.dashes(_inset(pts, hem_w * 0.55, cx, cy), 0.009, 0.045, 0.03), spec["cord"], 0.85)
    # grommets along the hem
    for i in range(0, len(pts), 5):
        px_, py_ = pts[i]
        dx_, dy_ = cx - px_, cy - py_
        d_ = math.hypot(dx_, dy_)
        gx, gy = px_ + dx_ / d_ * 0.05, py_ + dy_ / d_ * 0.05
        a.paint(a.ellipse(gx, gy, 0.034), (30, 24, 18), 1.0)
        a.paint(a.ellipse(gx, gy, 0.020), (176, 170, 156), 1.0)
        a.paint(a.ellipse(gx, gy, 0.010), (26, 22, 18), 1.0)
    a.paint(a.stroke(pts, 0.024, closed=True), OUTLINE, 1.0)
    # ---- the four poles: wooden, their tops at the corners, the cloth tied to a ring on each; the two at the
    # front (south) show their length down to the ground, the two at the back are behind the cloth
    corners = [(x0 - 0.02, y0 - 0.02, -1, -1), (x1 + 0.02, y0 - 0.02, 1, -1), (x0 - 0.02, y1 + 0.02, -1, 1), (x1 + 0.02, y1 + 0.02, 1, 1)]
    for (px_, py_, sx, sy) in corners:
        # the reinforcing patch at the corner, a darker triangle of webbing with a ring in it
        tri = [(px_ + sx * 0.02, py_ + sy * 0.02), (px_ - sx * 0.62, py_ + sy * 0.02), (px_ + sx * 0.02, py_ - sy * 0.62)]
        a.paint(a.poly(tri), shade(base, 0.58), 0.95, clip=body)
        a.paint(a.stroke(tri, 0.012, closed=True), shade(OUTLINE, 1.3), 0.7, clip=body)
        a.paint(a.dashes([(px_ - sx * 0.06, py_ - sy * 0.50), (px_ - sx * 0.46, py_ - sy * 0.06)], 0.008, 0.04, 0.03), spec["cord"], 0.75, clip=body)
    for (px_, py_, sx, sy) in corners:
        # the pole's shaft at the front corners: down from the cap to a footing
        if sy > 0:
            sh_len = 0.40
            shaft = a.rect(px_ - 0.055, py_, px_ + 0.055, py_ + sh_len)
            a.paint(shaft, lambda X, Y, px_=px_: np.array((128, 98, 62), np.float32)[None, None, :] * (1.15 - 0.45 * np.clip((X - (px_ - 0.055)) / 0.11, 0, 1))[..., None])
            a.paint(a.stroke([(px_ - 0.055, py_), (px_ - 0.055, py_ + sh_len), (px_ + 0.055, py_ + sh_len), (px_ + 0.055, py_)], 0.014), OUTLINE, 1.0)
            a.paint(a.poly([(px_ - 0.11, py_ + sh_len + 0.01), (px_ + 0.11, py_ + sh_len + 0.01), (px_ + 0.12, py_ + sh_len + 0.06), (px_ - 0.12, py_ + sh_len + 0.06)]), (126, 124, 116), 1.0)
            a.paint(a.stroke([(px_ - 0.11, py_ + sh_len + 0.01), (px_ + 0.11, py_ + sh_len + 0.01), (px_ + 0.12, py_ + sh_len + 0.06), (px_ - 0.12, py_ + sh_len + 0.06)], 0.012, closed=True), OUTLINE, 1.0)
        # the cap: the pole's end seen from above
        a.paint(a.ellipse(px_, py_, 0.105), OUTLINE, 1.0)
        a.paint(a.ellipse(px_, py_, 0.088), (150, 116, 76), 1.0)
        a.paint(a.stroke([(px_ + math.cos(t) * 0.050, py_ + math.sin(t) * 0.050) for t in np.linspace(0, 2 * math.pi, 24)], 0.008, closed=True), (96, 70, 44), 0.8)
        a.paint(a.ellipse(px_ - 0.022, py_ - 0.026, 0.026, 0.020), (216, 190, 146), 0.9)
        # a steel ring lashed to it, and the guy rope out to a peg
        peg = (px_ + sx * 0.56, py_ + sy * 0.50)
        mid_ = ((px_ + peg[0]) / 2.0, (py_ + peg[1]) / 2.0 + 0.020)
        a.paint(a.stroke([(px_, py_), mid_, peg], 0.026), (12, 9, 6), 0.45)
        a.paint(a.stroke([(px_, py_), mid_, peg], 0.014), spec["cord"], 0.95)
        a.paint(a.ellipse(peg[0], peg[1], 0.040, 0.034), (40, 30, 20), 1.0)
        a.paint(a.ellipse(peg[0] - 0.008, peg[1] - 0.008, 0.020, 0.016), (150, 120, 80), 0.9)
    # the poles' shadows on the ground (a short soft stripe to the south east from each cap)
    sh = None
    for (px_, py_, sx, sy) in corners:
        st = a.stroke([(px_ + 0.04, py_ + 0.06), (px_ + 0.34, py_ + 0.40)], 0.07)
        sh = st if sh is None else a.either(sh, st)
    a.shadow_under(0.0, 0.0, 0.03, 0.30, mask_of=np.asarray(sh, np.float32) / 255.0)
    return a.image(grain=0.0, seed=seed, scale=TARP_PX / PX)


def _inset(pts, d, cx, cy):
    """The outline pulled in towards the middle by a little (the line of stitching inside the hem)."""
    out = []
    for (px_, py_) in pts:
        dx_, dy_ = cx - px_, cy - py_
        n_ = math.hypot(dx_, dy_)
        out.append((px_ + dx_ / n_ * d, py_ + dy_ / n_ * d))
    return out + [out[0]]


def shade_tarps():
    for name, spec in TARP.items():
        save(draw_tarp(spec), name + ".png", translucent=True)


# --------------------------------------------------------------------- main ---

JOBS = {
    "tent": tents,
    "bunk": bunk,
    "workshop": workshop,
    "greenhouse": greenhouse,
    "floodlights": floodlights,
    "tarp": shade_tarps,
}


def main(argv):
    wanted = argv[1:] or list(JOBS)
    for w in wanted:
        if w not in JOBS:
            print("unknown job", w, "- one of", ", ".join(JOBS))
            return 1
        JOBS[w]()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
