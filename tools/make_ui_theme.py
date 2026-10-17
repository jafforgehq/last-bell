#!/usr/bin/env python3
"""Builds the "schoolyard noticeboard" frames of the HUD and the menus: slate-green
chalkboard panels in oak trim, brass for the clock, hall-pass badges for the crew,
paper slips for the alerts, notebook paper for the modals, buttons, chips and so on.

    python3 tools/make_ui_theme.py            # writes assets/ui/theme/*.png and frames.json
    UI_DEBUG=some/dir python3 tools/make_ui_theme.py   # also contact sheets of the frames, each
                                              # stretched to sizes the HUD uses (sheet.png, f_<name>.png)
    UI_SHEET=panel,card UI_DEBUG=... ...      # also sel.png: those frames only
    UI_DRY=1 ...                              # do not write the pictures, only check and draw sheets
    UI_ONLY=bubble python3 tools/make_ui_theme.py   # write only those frames' pictures and their entries in
                                              # frames.json (the others are left as they are)

Then run `Godot --headless --path . --import` once: the pictures are imported like any other.
The output is the same bytes every time (all the noise is seeded).

The materials are drawn here from seeded noise, no picture is read (since 2026-10-17; before
that they were pictures made with an image model, see docs/assets-log.md): a chalkboard with the
swipes of an eraser (material_slate), the chalk dust over it (material_dust), oak with growth
rings, streaks and pores (material_oak), brushed brass (material_brass), notebook paper
(material_paper) and card stock (material_card). Each is toned to the game's palette and wraps
(a tile cut from it is blended to join itself), then the frames are drawn with them: the
trims are cut with mitred corners and lit from the top left like a moulding, the boards sit in
a soft baked shadow, there are nail heads, screws, a pushpin, punched holes, a folded page, a
slot for a lanyard, a chalk dust that gathers on the slate. The finest grain (the buttons, the
slip) is noise made to wrap by construction, so it never shows a pattern.

Units. Every frame is drawn at TWICE the size it is shown at ("art pixels": 2 of them make one
pixel of the HUD, "logical" pixels). scripts/ui/frames.gd loads the picture as a texture that
reports half its size (ImageTexture.set_size_override), so a nine-patch drawn from it is half as
big and twice as sharp: it fills the 2x pixels of a retina screen exactly and is averaged down
on a 1x screen. So the numbers in this file are art pixels, except where a name says logical,
and the sides of every picture are even.

frames.json, one entry for each frame (all of them are read by scripts/ui/frames.gd):

    "file"     res:// path of the picture
    "margin"   the nine-patch margins [left, top, right, bottom] in ART pixels, the ones the
               picture is cut at (the shadow outside the board is part of them)
    "content"  the content margins [l, t, r, b] to give a Control, in LOGICAL pixels (what a
               text may be next to the frame; the old flat panels had 12/10)
    "expand"   how far the baked shadow reaches outside the Control, [l, t, r, b], in LOGICAL
               pixels (the picture is drawn that much bigger than the Control)
    "stretch"  how the middle is filled, [horizontal, vertical]: "stretch", "tile" or
               "tile_fit" (the tiles are seamless; tile_fit never cuts one)
    "avg"      the average colour of the middle (what a text is read against)
    "ink"      the text colour that reads on it at 4.5:1 or better

The frames, and what each is for:

    panel          the HUD's board: stores, selection, help, legend (oak trim, slate, nails)
    panel_slim     the same with a thin trim: a toolbar, the hint, a legend
    panel_inset    a block set into a board (a nested list), no trim
    clock          the time panel: brass rim, screws
    banner         a sign for a headline: oak trim, a chalk line inside
    card           a crew member's hall pass: card stock round a dark window (the content
    card_selected  rect) the portrait fills, a slot for the lanyard in the top 9 px. The
                   chosen badge is brass, a pixel bigger all round, with a glow: same content rect
    slip           an alert pinned to the board: pale paper, pin top right, folded corner
                   bottom right. Tint it with the colour of the level; dark ink
    paper          a modal page of ruled notebook paper: a red margin line (text starts 33 px
                   from the left), punch holes, rules every 14 px. Dark ink
    bubble         a speech bubble for what someone says in the world (round 4): a slip of pale paper
                   with a tail at the bottom left, tail tip at frames.json "tail" ([x from the
                   bubble's left edge, how far below its foot], logical px). The tail lies inside
                   the left margin, so the middle stretches without bending it; a bubble that
                   wants its tail at the right is drawn mirrored. Dark ink
    tooltip        a hover tip: small slate plaque
    toast          a one-line message: slate plaque
    chip           a key (R, Space): a small keycap
    pill           a capsule (PAUSED, the phase): pale card stock, dark ink; tint it
    bar_track      the groove of a meter
    bar_fill       the fill of a meter: a pale glossy capsule with a chalk hatch; tint it
    button, button_hover, button_pressed, button_off
                   a command: slate tile in an oak rim; light ink
    button_primary, button_primary_hover, button_primary_pressed
                   the main choice: a brushed brass plate; dark ink (#1a1508)

Checked on every run (the script stops if one fails): the HUD's text colours (INK, INK2, INK3)
read at 4.5:1 or better on the average colour of the middle of every dark frame, and the
dark inks on the pale ones; no tile of a middle or a rail jumps where it meets the next; the
baked shadow has faded to nothing at the border of the picture; the sides are even.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "theme")
RES = "res://assets/ui/theme/"

LOGICAL = 0.5          # logical pixels to the art pixel

# the text colours of the HUD (scripts/ui/hud.gd) and the dark ink for paper
INK = (0xEC, 0xE6, 0xD8)
INK2 = (0xB7, 0xAF, 0x9E)
INK3 = (0x9A, 0x93, 0x7F)
ACCENT = (0xF0, 0xC2, 0x4A)
ACCENT_INK = (0x1A, 0x15, 0x08)
PAPER_INK = (0x26, 0x2B, 0x36)

STRETCH, TILE, TILE_FIT = "stretch", "tile", "tile_fit"

OAK = (124, 85, 50)


# ------------------------------------------------------------- colour maths --

def _lin(c):
    c = np.asarray(c, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def luminance(rgb):
    r, g, b = _lin(rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def hexcolor(rgb):
    return "#%02x%02x%02x" % tuple(int(round(float(v))) for v in rgb)


# ------------------------------------------------------------ numeric tools --

def gblur(a, sigma, wrap=False):
    """Gaussian blur through the frequency domain (no scipy here). `wrap` treats
    the picture as a tile; otherwise its edges are mirrored."""
    a = np.asarray(a, np.float32)
    squeeze = a.ndim == 2
    if squeeze:
        a = a[..., None]
    pad = 0 if wrap else int(3 * sigma) + 1
    if pad:
        a = np.pad(a, ((pad, pad), (pad, pad), (0, 0)), mode="reflect")
    h, w, c = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    k = np.exp(-2 * np.pi ** 2 * sigma ** 2 * (fx ** 2 + fy ** 2)).astype(np.float32)
    out = np.empty_like(a)
    for i in range(c):
        out[..., i] = np.fft.irfft2(np.fft.rfft2(a[..., i]) * k, s=(h, w))
    if pad:
        out = out[pad:-pad, pad:-pad]
    return out[..., 0] if squeeze else out


def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, np.float32) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def resize(a, w, h):
    """A float RGB(A) array resized with Lanczos (through Pillow, per channel)."""
    chans = [np.asarray(Image.fromarray(a[..., i].astype(np.float32)).resize((w, h), Image.LANCZOS)) for i in range(a.shape[2])]
    return np.stack(chans, axis=2)


# ---------------------------------------------------------------- materials --

def retone(a, mean_rgb, gain=1.0, floor=0.0):
    """The same picture with another average colour and `gain` times the variation."""
    m = a.mean(axis=(0, 1))
    return np.clip(np.asarray(mean_rgb, np.float32) + (a - m) * gain, floor, 255.0)


def wrapped(a, nx, ny=None, origin=(0, 0)):
    """An nx x ny tile cut from `a` that wraps without a seam. Two passes, one for each
    axis: the crop is blended with the crop shifted by half a tile along that axis (the
    shift puts the crop's seam in the middle where the crop itself is continuous), the
    blend keeps the variance of the grain, and its window is flat over the middle 40
    percent so the picture itself is untouched there (a window that always adds up to
    one would repeat the tile twice over)."""
    ny = ny or nx
    ox, oy = origin
    c = a[oy:oy + ny, ox:ox + nx].astype(np.float32)
    assert c.shape[0] == ny and c.shape[1] == nx, "the source is too small for the tile"
    m = c.mean(axis=(0, 1))
    for axis, n in ((1, nx), (0, ny)):
        d = np.minimum(np.arange(n, dtype=np.float32) + 0.5, n - np.arange(n, dtype=np.float32) - 0.5)
        w1 = smoothstep(0.0, n * 0.30, d)
        norm1 = np.sqrt(w1 * w1 + (1.0 - w1) * (1.0 - w1))
        r = np.roll(c, n // 2, axis=axis)
        shape = (1, n, 1) if axis == 1 else (n, 1, 1)
        c = m + ((c - m) * w1.reshape(shape) + (r - m) * (1.0 - w1.reshape(shape))) / norm1.reshape(shape)
    return c


def periodic_noise(nx, ny, sigmas=(0.8, 2.0), weights=(1.0, 0.7), seed=1):
    """Noise with zero mean and unit spread that wraps in both directions by construction (blurred on a
    torus), so it can be tiled with no seam and no pattern: for the fine grain of a surface."""
    rng = np.random.RandomState(seed)
    out = np.zeros((ny, nx), np.float32)
    for sg, wt in zip(sigmas, weights):
        n = gblur(rng.randn(ny, nx).astype(np.float32), sg, wrap=True)
        out += wt * n / max(float(n.std()), 1e-6)
    return out / max(float(out.std()), 1e-6)


def brushed_noise(nx, ny, sx=7.0, sy=0.45, seed=2):
    """Periodic noise streaked along x (brushed metal): zero mean, unit spread, wraps both ways."""
    rng = np.random.RandomState(seed)
    a = rng.randn(ny, nx).astype(np.float32)
    fy = np.fft.fftfreq(ny)[:, None]
    fx = np.fft.rfftfreq(nx)[None, :]
    k = np.exp(-2 * np.pi ** 2 * ((sx * fx) ** 2 + (sy * fy) ** 2)).astype(np.float32)
    out = np.fft.irfft2(np.fft.rfft2(a) * k, s=(ny, nx))
    return (out / max(float(out.std()), 1e-6)).astype(np.float32)


def mirrored_x(a):
    """A strip that wraps along its length: the picture, then its mirror image."""
    return np.concatenate([a, a[:, ::-1]], axis=1)


def toned(v, mean_rgb, std_rgb):
    """A colour picture from a field `v`: `mean_rgb` on average, `std_rgb` the spread of each channel."""
    v = (v - v.mean()) / max(float(v.std()), 1e-6)
    return np.clip(np.asarray(mean_rgb, np.float32) + v[..., None] * np.asarray(std_rgb, np.float32), 0.0, 255.0)


def swipes(n, count, seed, strength=(0.25, 1.0), radius=(90.0, 260.0), band=(40.0, 110.0), span=(35.0, 110.0), soft=1.6):
    """Wide soft arcs like the swipes of an eraser or a cloth over a board, n x n and wrapping both ways
    (each arc is drawn on a 3 x 3 canvas and the nine tiles are added up). Each swipe is a band of thin
    concentric arcs that start and stop a little apart and are of uneven strength, so it is streaked along
    its length and soft at its two sides. Not normalised: 0 is no dust."""
    rng = np.random.RandomState(seed)
    acc = np.zeros((3 * n, 3 * n), np.float32)
    for _ in range(count):
        layer = Image.new("F", (3 * n, 3 * n), 0.0)
        dr = ImageDraw.Draw(layer)
        px, py = rng.uniform(n, 2 * n, 2)                  # a point on the swipe
        r = rng.uniform(*radius)
        th = rng.uniform(0.0, 2.0 * np.pi)
        ox, oy = px - r * np.cos(th), py - r * np.sin(th)  # the centre of its circle
        a0 = np.degrees(th) - rng.uniform(*span) / 2.0
        sp = rng.uniform(*span)
        bw = rng.uniform(*band)
        lines = max(4, int(bw / 1.6))
        amp = rng.uniform(*strength)
        for k in range(lines):
            t = (k + 0.5) / lines
            rr = r - bw / 2.0 + t * bw + rng.uniform(-0.8, 0.8)
            val = amp * math.sin(math.pi * t) ** 0.7 * rng.uniform(0.15, 1.0)
            st = a0 + rng.uniform(0.0, sp * 0.3)
            en = a0 + sp - rng.uniform(0.0, sp * 0.3)
            dr.arc([ox - rr, oy - rr, ox + rr, oy + rr], st, en, fill=float(val), width=int(rng.choice([1, 1, 2, 3])))
        acc += np.asarray(layer, np.float32)
    out = acc.reshape(3, n, 3, n).sum(axis=(0, 2))
    return gblur(out, soft, wrap=True)


def specks(n, count, seed, size=(0.6, 1.6)):
    """A few small soft dots, wrapping (0..1)."""
    rng = np.random.RandomState(seed)
    out = np.zeros((n, n), np.float32)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    for _ in range(count):
        cx, cy = rng.uniform(0, n, 2)
        dx = (xx - cx + n / 2) % n - n / 2
        dy = (yy - cy + n / 2) % n - n / 2
        out = np.maximum(out, np.exp(-(dx * dx + dy * dy) / (2.0 * rng.uniform(*size) ** 2)) * rng.uniform(0.5, 1.0))
    return out


def material_slate(n=512):
    """A dark green-black chalkboard: a slow mottle, the ghosts of wide eraser swipes and a fine grain."""
    mott = periodic_noise(n, n, (38.0, 90.0), (1.0, 0.7), seed=21)
    sw = swipes(n, 40, seed=22, strength=(0.2, 0.7), soft=0.9)
    grain = periodic_noise(n, n, (0.6, 1.4), (1.0, 0.5), seed=23)
    v = 0.45 * mott + 0.7 * sw / max(float(sw.std()), 1e-6) + 0.8 * grain
    return toned(v, (24, 35, 31), (5.1, 4.9, 5.2))


def material_dust(n=512):
    """Chalk dust wiped about with an eraser, 0..1: soft wide arcs, broken up by a grain."""
    sw = swipes(n, 30, seed=31, strength=(0.4, 1.0), band=(50.0, 130.0), soft=1.2)
    grain = periodic_noise(n, n, (1.5, 3.5), (1.0, 0.6), seed=32)
    d = sw * np.clip(0.85 + 0.15 * grain, 0.4, 1.3)
    d = (d - np.percentile(d, 55)) / (np.percentile(d, 99.5) - np.percentile(d, 55))
    return np.repeat(np.clip(d, 0.0, 1.0)[..., None], 3, axis=2)


def material_oak(n=640):
    """Varnished oak with the grain along x: growth rings (sharp dark lines on a wavering band), long
    fine streaks, and small dark pores drawn out along the grain. Wraps both ways."""
    yy = np.mgrid[0:n, 0:n][0].astype(np.float32)
    warp = periodic_noise(n, n, (55.0, 110.0), (1.0, 0.8), seed=41)
    phase = 2.0 * np.pi * (yy + 3.5 * warp) / n
    ring = (0.5 + 0.5 * np.sin(phase * 30.0)) ** 6
    ring2 = (0.5 + 0.5 * np.sin(phase * 97.0 + 1.3)) ** 4
    fine = brushed_noise(n, n, 4.0, 0.4, seed=42)
    rng = np.random.RandomState(43)
    pores = gblur_aniso((rng.rand(n, n) < 0.035).astype(np.float32), 1.6, 0.4)
    pores = np.clip(pores / max(float(np.percentile(pores, 99.7)), 1e-6), 0.0, 1.0)
    mott = periodic_noise(n, n, (30.0, 70.0), (1.0, 0.6), seed=45)
    v = -0.7 * ring - 0.35 * ring2 + 0.45 * fine - 1.1 * pores + 0.1 * mott
    return toned(v, OAK, (12.3, 11.8, 10.2))


def gblur_aniso(a, sx, sy):
    """A wrapping gaussian blur with its own width along x and along y."""
    ny, nx = a.shape
    fy = np.fft.fftfreq(ny)[:, None]
    fx = np.fft.rfftfreq(nx)[None, :]
    k = np.exp(-2 * np.pi ** 2 * ((sx * fx) ** 2 + (sy * fy) ** 2)).astype(np.float32)
    return np.fft.irfft2(np.fft.rfft2(a) * k, s=(ny, nx)).astype(np.float32)


def material_brass(n=640):
    """Brushed antique brass: fine and long streaks along x and a few soft patches of tarnish."""
    v = 0.8 * brushed_noise(n, n, 7.0, 0.5, seed=51) + 0.6 * brushed_noise(n, n, 45.0, 1.5, seed=52)
    t = smoothstep(1.0, 2.2, periodic_noise(n, n, (10.0, 30.0), (1.0, 0.8), seed=53))
    rgb = toned(v + 0.2 * periodic_noise(n, n, (60.0,), (1.0,), seed=54), (170, 130, 58), (6.9, 7.0, 6.1))
    rgb = rgb - t[..., None] * np.asarray((10.0, 7.0, 1.5), np.float32)
    return np.clip(rgb - rgb.mean(axis=(0, 1)) + np.asarray((170, 130, 58), np.float32), 0.0, 255.0)


def material_paper(n=464):
    """Notebook paper (no rules: the frames draw them): a fine fibre and a faint cloud."""
    v = periodic_noise(n, n, (0.7, 2.5), (1.0, 0.6), seed=61) + 0.5 * brushed_noise(n, n, 4.0, 0.6, seed=62) \
        + 0.6 * periodic_noise(n, n, (45.0,), (1.0,), seed=63)
    return toned(v, (240, 235, 220), (2.4, 2.2, 2.8))


def material_card(n=472):
    """Pale card stock: a fibre grain that runs up and down, a faint cloud and a few specks."""
    v = brushed_noise(n, n, 0.5, 5.0, seed=71) + 0.7 * periodic_noise(n, n, (0.7, 1.6), (1.0, 0.5), seed=72) \
        + 0.45 * periodic_noise(n, n, (40.0,), (1.0,), seed=73)
    rgb = toned(v, (214, 207, 190), (8.0, 8.4, 8.8))
    sp = specks(n, 14, seed=74)
    return np.clip(rgb - sp[..., None] * np.asarray((70.0, 72.0, 70.0), np.float32), 0.0, 255.0)


class Materials:
    """The processed pictures, as float RGB arrays (0..255). The tiles are made on
    demand for the size a frame wants and kept."""

    def __init__(self):
        # every material is drawn by the code below from seeded noise (no picture is read): a chalkboard,
        # the chalk dust over it, oak and brass with the grain along x, notebook paper and card stock
        self._slate = material_slate()
        self._dust = material_dust()
        self._oak = material_oak()
        self._brass = material_brass()
        self._paper = material_paper()
        self._card = material_card()
        self._cache = {}

    def _get(self, key, make):
        if key not in self._cache:
            self._cache[key] = make()
        return self._cache[key]

    def slate(self, nx, ny):
        return self._get(("slate", nx, ny), lambda: wrapped(self._slate, nx, ny, (20, 20)))

    def dust(self, nx, ny):
        return self._get(("dust", nx, ny), lambda: wrapped(self._dust, nx, ny, (50, 50))[..., 0])

    def paper(self, nx, ny):
        return self._get(("paper", nx, ny), lambda: wrapped(self._paper, nx, ny, (30, 30)))

    def card(self, nx, ny):
        return self._get(("card", nx, ny), lambda: wrapped(self._card, nx, ny, (30, 30)))

    def strips(self, which, nx, ny):
        """(horizontal, vertical) rail strips of oak or brass: grain along the rail, wrapping
        along it with the period of the frame's middle (nx for the top and bottom rails, ny for
        the left and right ones), 128 rows deep so each rail can take a different band."""
        src = self._oak if which == "oak" else self._brass

        def make():
            h = mirrored_x(src[40:168, 40:40 + nx // 2])
            v = np.transpose(mirrored_x(src[200:328, 40:40 + ny // 2]), (1, 0, 2)).copy()
            return h, v
        return self._get((which, nx, ny), make)


def solid_strips(rgb):
    a = np.broadcast_to(np.asarray(rgb, np.float32), (16, 16, 3)).copy()
    return a, a


# ----------------------------------------------------------- drawing tools --

class Canvas:
    """A float RGBA canvas (straight alpha, colours 0..255) layers are put over."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), np.float32)

    def over(self, rgb, alpha):
        """Puts a layer (a colour or an array, and an alpha array) over the canvas."""
        alpha = np.clip(np.asarray(alpha, np.float32), 0.0, 1.0)
        rgb = np.asarray(rgb, np.float32)
        if rgb.ndim == 1:
            rgb = np.broadcast_to(rgb, (self.h, self.w, 3))
        out_a = alpha + self.a * (1.0 - alpha)
        num = rgb * alpha[..., None] + self.rgb * (self.a * (1.0 - alpha))[..., None]
        self.rgb = np.where(out_a[..., None] > 1e-6, num / np.maximum(out_a, 1e-6)[..., None], self.rgb)
        self.a = out_a

    def cut(self, alpha):
        """Takes `alpha` (0..1) away from the canvas: a punched hole."""
        self.a = self.a * (1.0 - np.clip(alpha, 0.0, 1.0))

    def image(self):
        out = np.dstack([np.clip(self.rgb, 0, 255), np.clip(self.a, 0, 1) * 255.0])
        return Image.fromarray(np.round(out).astype(np.uint8))


def grid(w, h):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    return xx + 0.5, yy + 0.5


def rr_sdf(w, h, rect, r):
    """Signed distance (negative inside) to a rounded rectangle (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = rect
    xx, yy = grid(w, h)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    hx, hy = (x1 - x0) / 2.0, (y1 - y0) / 2.0
    r = max(0.0, min(r, hx, hy))
    qx = np.abs(xx - cx) - (hx - r)
    qy = np.abs(yy - cy) - (hy - r)
    out = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inn = np.minimum(np.maximum(qx, qy), 0)
    return (out + inn - r).astype(np.float32)


def circle_sdf(w, h, cx, cy, r):
    xx, yy = grid(w, h)
    return (np.hypot(xx - cx, yy - cy) - r).astype(np.float32)


def tri_sdf(w, h, p0, p1, p2):
    """Signed distance (negative inside) to the triangle p0 p1 p2 (points in picture pixels)."""
    xx, yy = grid(w, h)
    best = None
    for a, b in ((p0, p1), (p1, p2), (p2, p0)):
        abx, aby = b[0] - a[0], b[1] - a[1]
        t = np.clip(((xx - a[0]) * abx + (yy - a[1]) * aby) / (abx * abx + aby * aby), 0.0, 1.0)
        d = np.hypot(xx - (a[0] + t * abx), yy - (a[1] + t * aby))
        best = d if best is None else np.minimum(best, d)
    cr = [(b[0] - a[0]) * (yy - a[1]) - (b[1] - a[1]) * (xx - a[0]) for a, b in ((p0, p1), (p1, p2), (p2, p0))]
    inside = ((cr[0] >= 0) & (cr[1] >= 0) & (cr[2] >= 0)) | ((cr[0] <= 0) & (cr[1] <= 0) & (cr[2] <= 0))
    return np.where(inside, -best, best).astype(np.float32)


def smooth_union(a, b, k):
    """The union of two shapes given as signed distances, with the concave joint between them
    rounded over about `k` pixels."""
    hh = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return (b * (1.0 - hh) + a * hh - k * hh * (1.0 - hh)).astype(np.float32)


def cov(sd, soft=1.0):
    """Coverage of a shape for a signed distance, with a 1 pixel edge."""
    return np.clip(0.5 - np.asarray(sd, np.float32) / soft, 0.0, 1.0)


def lit(height, k=2.0, light=(-0.55, -0.72, 0.65)):
    """How a heightfield is lit from the top left: 1.0 on the flat, more on a slope
    that faces the light, less on one that faces away."""
    gy, gx = np.gradient(height.astype(np.float32))
    nx, ny = -k * gx, -k * gy
    n = np.sqrt(nx * nx + ny * ny + 1.0)
    lv = np.asarray(light, np.float32)
    lv = lv / np.linalg.norm(lv)
    lam = (nx * lv[0] + ny * lv[1] + lv[2]) / n
    return lam / lv[2]


def wrap_at(tex, rows, cols):
    """tex[rows, cols] with the indices wrapped round the texture."""
    return tex[rows % tex.shape[0], cols % tex.shape[1]]


def tile_xy(w, h, ml, mt):
    """The row and column, counted from where the middle of a frame starts, of every pixel."""
    yy, xx = np.mgrid[0:h, 0:w]
    return yy - mt, xx - ml


def shadow(w, h, rect, r, dy, reach, alpha):
    """The soft shadow of a rounded rectangle, `dy` lower, fading to nothing `reach`
    pixels out. Made from the distance to the shape rather than by blurring it, so it is
    the same all along a straight edge (the straight parts of a nine-patch are stretched)
    and it is nothing at the border of the picture."""
    x0, y0, x1, y1 = rect
    sd = rr_sdf(w, h, (x0, y0 + dy, x1, y1 + dy), r)
    t = 1.0 - smoothstep(0.0, reach, sd)
    return alpha * t * t


def need_even(w, h, name):
    assert w % 2 == 0 and h % 2 == 0, "%s is %dx%d: the picture must have even sides" % (name, w, h)


# ------------------------------------------------------------------- frames --

def _lin_arr(c):
    c = np.asarray(c, np.float32) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


class Frame:
    def __init__(self, name, img, margin, content, expand, stretch=(TILE_FIT, TILE_FIT), ink=INK, check=(INK, INK2, INK3), extra=None):
        self.name = name
        self.extra = dict(extra or {})      # more keys for the entry in frames.json
        self.img = img                      # a PIL RGBA image, at 2x
        need_even(img.width, img.height, name)
        self.margin = [int(v) for v in margin]
        self.content = [float(v) for v in content]        # logical px
        self.expand = [float(v) * LOGICAL for v in expand]  # given in art px, kept in logical
        self.stretch = list(stretch)
        self.ink = ink
        self.check = check                  # the text colours that must read on the middle
        arr = np.asarray(img).astype(np.float32)
        h, w = arr.shape[:2]
        l, t, r, b = self.margin
        mid = arr[t:h - b, l:w - r]
        if mid.shape[0] == 0 or mid.shape[1] == 0:        # no middle (a bar): the row where it would be
            mid = arr[h // 2 - 1:h // 2 + 1, max(0, l - 1):w - r + 1]
        a = mid[..., 3:4] / 255.0
        self.avg = (mid[..., :3] * a).sum(axis=(0, 1)) / max(1e-6, a.sum())
        self.alpha_mid = float(a.mean())
        self.mid_rgb = mid[..., :3]
        self.mid_a = mid[..., 3]

    def entry(self):
        r = lambda v: [round(float(x), 2) for x in v]
        out = {
            "file": RES + self.name + ".png",
            "margin": self.margin,
            "content": r(self.content),
            "expand": r(self.expand),
            "stretch": self.stretch,
            "avg": hexcolor(self.avg),
            "ink": hexcolor(self.ink),
        }
        out.update(self.extra)
        return out

    def seam_ratio(self):
        """How much the picture jumps where one tile of a tiled middle ends and the next begins
        (and along the stretched rails too), against how much it changes from one pixel to the next
        anyway. 1.0 is a join nobody could see; the largest over the tiled axes is returned."""
        arr = np.asarray(self.img).astype(np.float32)
        h, w = arr.shape[:2]
        l, t, r, b = self.margin
        rgb, a = arr[..., :3], arr[..., 3]
        worst = 0.0
        if self.stretch[0] != STRETCH and w - l - r > 1:
            for (y0, y1) in ((t, h - b), (0, t), (h - b, h)):
                if y1 <= y0:
                    continue
                ok = (a[y0:y1, w - r - 1] > 250) & (a[y0:y1, l] > 250) & (a[y0:y1, l + 1] > 250)
                if ok.sum() < 3:
                    continue
                jump = np.abs(rgb[y0:y1, w - r - 1] - rgb[y0:y1, l])[ok].mean()
                typical = np.abs(rgb[y0:y1, l + 1:w - r] - rgb[y0:y1, l:w - r - 1])[ok].mean()
                worst = max(worst, jump / max(typical, 1.2))
        if self.stretch[1] != STRETCH and h - t - b > 1:
            for (x0, x1) in ((l, w - r), (0, l), (w - r, w)):
                if x1 <= x0:
                    continue
                ok = (a[h - b - 1, x0:x1] > 250) & (a[t, x0:x1] > 250) & (a[t + 1, x0:x1] > 250)
                if ok.sum() < 3:
                    continue
                jump = np.abs(rgb[h - b - 1, x0:x1] - rgb[t, x0:x1])[ok].mean()
                typical = np.abs(rgb[t + 1:h - b, x0:x1] - rgb[t:h - b - 1, x0:x1])[:, ok].mean()
                worst = max(worst, jump / max(typical, 1.2))
        return worst

    def verify(self):
        """Asserts the text colours read on the middle: on its average colour, and (a little
        looser) on its brightest few percent, where a speck of chalk dust is."""
        # the baked shadow must have faded to nothing at the border of the picture: no hard edge
        arr = np.asarray(self.img)
        a = arr[..., 3].astype(np.float32)
        for side, line in (("left", a[:, 0]), ("top", a[0, :]), ("right", a[:, -1]), ("bottom", a[-1, :])):
            idx = ("left", "top", "right", "bottom").index(side)
            if self.expand[idx] > 0:
                assert line.max() <= 6, "%s: the %s shadow is cut off at the edge of the picture (alpha %d)" % (self.name, side, line.max())
        seam = self.seam_ratio()
        assert seam < 2.2, "%s: a tile of its middle or of its rails does not join the next (a jump %.1f times the usual change)" % (self.name, seam)
        if not self.check:
            return
        assert self.alpha_mid > 0.98, "%s: the middle of a frame that carries text must be opaque" % self.name
        lum = 0.2126 * _lin_arr(self.mid_rgb[..., 0]) + 0.7152 * _lin_arr(self.mid_rgb[..., 1]) + 0.0722 * _lin_arr(self.mid_rgb[..., 2])
        for ink in self.check:
            c = contrast(ink, self.avg)
            assert c >= 4.5, "%s: %s on the average %s reads only %.2f:1" % (self.name, hexcolor(ink), hexcolor(self.avg), c)
            li = luminance(ink)
            dark_ink = li < 0.2
            edge = np.percentile(lum, 98.0 if not dark_ink else 2.0)
            worst = (li + 0.05) / (edge + 0.05) if not dark_ink else (edge + 0.05) / (li + 0.05)
            assert worst >= 3.0, "%s: %s on the %s end of the middle reads only %.2f:1" % (self.name, hexcolor(ink), "bright" if not dark_ink else "dark", worst)


def apply_light(rgb, s, spec=0.5):
    """Lights a colour: where the surface is lit less than flat (s < 1) the colour is darkened,
    where it is lit more (s > 1) it goes toward white (a highlight on varnish or metal does not
    just get more saturated)."""
    s = s[..., None]
    return np.where(s < 1.0, rgb * s, rgb + (255.0 - rgb) * (s - 1.0) * spec)


def rim_ring(w, h, outer, T, r_out, rim_h, rim_v, ml, mt, mitre=True, profile=None, k=2.4, rows=(10, 52, 90, 30), spec=0.5):
    """The four rails of a frame cut from a strip texture (the grain along the rail) and
    lit like a moulding from the top left, with a mitred joint in every corner.
    Returns the rgb of the whole picture, the signed distance to the outer edge and the
    mask of the band T wide inside it."""
    x0, y0, x1, y1 = outer
    xx, yy = grid(w, h)
    dl, dr, dt, db = xx - x0, x1 - xx, yy - y0, y1 - yy
    horiz = np.minimum(dt, db) <= np.minimum(dl, dr)             # top or bottom rail (the mitre is the diagonal)
    sd_out = rr_sdf(w, h, outer, r_out)
    u = np.maximum(-sd_out, 0.0)                                  # how far in from the edge
    ty, tx = tile_xy(w, h, ml, mt)
    top = wrap_at(rim_h, (rows[0] + np.floor(dt)).astype(np.int64), tx)
    bot = wrap_at(rim_h, (rows[1] + np.floor(db)).astype(np.int64), tx)
    lef = wrap_at(rim_v, ty, (rows[2] + np.floor(dl)).astype(np.int64))
    rig = wrap_at(rim_v, ty, (rows[3] + np.floor(dr)).astype(np.int64))
    col_h = np.where((dt <= db)[..., None], top, bot)
    col_v = np.where((dl <= dr)[..., None], lef, rig)
    rgb = np.where(horiz[..., None], col_h, col_v)
    prof = profile or [(0.0, 0.0), (0.09, 0.45), (0.22, 0.78), (0.70, 0.86), (0.94, 0.55), (1.0, 0.18)]
    hs = np.interp(u, [p[0] * T for p in prof], [p[1] for p in prof]).astype(np.float32)
    ring = (np.abs(sd_out + T * 0.5) <= T * 0.5 + 0.5)
    hs = np.where(ring, hs, 0.0)
    if mitre:
        # the joint: where two rails meet in a corner a thin groove
        corner = (np.minimum(dt, db) < T + 1) & (np.minimum(dl, dr) < T + 1)
        dm = np.where(corner, np.minimum(np.minimum(np.abs(dt - dl), np.abs(dt - dr)), np.minimum(np.abs(db - dl), np.abs(db - dr))), 99.0)
        hs = hs - 0.30 * np.exp(-(dm / 0.75) ** 2) * ring
    return apply_light(rgb, np.clip(lit(hs, k=k), 0.35, 1.9), spec), sd_out, ring


def nail(cv, cx, cy, r, base=(66, 58, 50), shine=0.5, cast=(0.9, 1.1), slot=None):
    """A nail or screw head: a small domed disc with a highlight and a short shadow;
    `slot` (an angle in radians) cuts the slot of a screw into it."""
    w, h = cv.w, cv.h
    cv.over((12, 8, 6), cov(circle_sdf(w, h, cx + cast[0], cy + cast[1], r + 0.3), 1.2) * 0.55)
    sd = circle_sdf(w, h, cx, cy, r)
    xx, yy = grid(w, h)
    d = np.hypot(xx - (cx - r * 0.3), yy - (cy - r * 0.35)) / (r * 1.5)
    dome = np.clip(1.0 - d, 0.0, 1.0)
    col = np.asarray(base, np.float32)[None, None, :] * (0.75 + 0.9 * dome[..., None] ** 1.3) + 255.0 * shine * (dome[..., None] ** 4.0)
    cv.over(col, cov(sd))
    cv.over((14, 10, 8), cov(np.abs(sd + 0.2) - 0.35) * 0.55)
    if slot is not None:
        ca, sa = math.cos(slot), math.sin(slot)
        along = (xx - cx) * ca + (yy - cy) * sa
        across = -(xx - cx) * sa + (yy - cy) * ca
        line = cov(np.maximum(np.abs(across) - 0.45, np.abs(along) - r * 0.82)) * cov(sd + 0.3)
        cv.over((18, 14, 10), line * 0.8)


def inner_light(sd_win, w, h, win, depth, dark=0.38, dark2=0.50, lit_a=0.0, shift=(1.6, 2.4), r_in=2.0):
    """What the face of a board looks like in the shadow of its trim: darker along its top
    and left (the trim stands over it), a touch lighter along its bottom and right. Gone before
    `depth` pixels in, so the middle of the picture is the plain material."""
    inside = -sd_win
    sd_sh = rr_sdf(w, h, (win[0] + shift[0], win[1] + shift[1], win[2] + shift[0], win[3] + shift[1]), r_in)
    occl = np.exp(-np.maximum(inside, 0.0) / 2.6) * dark + np.exp(-np.maximum(-sd_sh, 0.0) / 4.2) * dark2
    fade = 1.0 - smoothstep(depth - 3.0, depth - 0.5, inside)
    occl = np.clip(occl, 0.0, 0.85) * fade
    ligh = np.exp(-np.maximum(inside, 0.0) / 1.6) * lit_a * fade
    return occl, ligh


def even_up(n):
    return n + (n % 2)


def band(sd_win, w, h, win, dy, dx=0.0, r_in=2.0):
    """A thin band just inside an edge of the face: inside the window but not inside the
    window moved by (dx, dy). dy > 0 gives a band along the top, dy < 0 along the bottom."""
    moved = rr_sdf(w, h, (win[0] + dx, win[1] + dy, win[2] + dx, win[3] + dy), r_in)
    return np.clip(cov(sd_win) - cov(moved), 0.0, 1.0)


def vgrad(top, mid, bot, depth):
    """A face that is `top` colour along its top edge, `bot` along its bottom edge and `mid`
    over the rest: the gradients are `depth` pixels deep, so they stay inside the margins of a
    nine-patch and the middle can be stretched."""
    top, mid, bot = (np.asarray(c, np.float32) for c in (top, mid, bot))

    def face(g):
        w, h, win = g["w"], g["h"], g["win"]
        _, yy = grid(w, h)
        t_top = smoothstep(0.0, depth, yy - win[1])[..., None]
        t_bot = smoothstep(0.0, depth, win[3] - yy)[..., None]
        col = top * (1.0 - t_top) + mid * t_top
        col = bot * (1.0 - t_bot) + col * t_bot
        return np.broadcast_to(col, (h, w, 3)).astype(np.float32)
    return face


def make_plate(mats, name, *, centre, T, inner, r, ext, rim, face, content, nails=0, nail_r=2.4, nail_base=(66, 58, 50),
               screws=False, stretch=(TILE_FIT, TILE_FIT), shadow_a=(0.46, 0.40), dy=3.0, dust=0.35, gain=1.0, mitre=True,
               profile=None, k=2.4, outline=(36, 24, 14), outline_a=0.65, chalk_border=0.0, extra=None, ink=INK,
               check=(INK, INK2, INK3), dark=(0.38, 0.50), lit_a=0.0, hi_top=None, hi_bot=None, rim_rows=(10, 52, 90, 30), spec=0.5):
    """A board: a face in a rim, in a soft shadow. `rim` is "oak", "brass", an rgb tuple
    (a plain moulding) or None; `face` is "slate" (the wiped chalkboard), an rgb tuple or a
    function of the geometry that gives the colour of every pixel (see vgrad). `hi_top` and
    `hi_bot` are (rgb, alpha, depth) lines of light along the top and the bottom of the face."""
    sl, st, sr, sb = ext
    ml, mt = sl + max(T + inner, r), st + max(T + inner, r)
    mr, mb = sr + max(T + inner, r), sb + max(T + inner, r)
    cx, cy = centre
    cx, cy = even_up(ml + cx + mr) - ml - mr, even_up(mt + cy + mb) - mt - mb
    w, h = ml + cx + mr, mt + cy + mb
    need_even(w, h, name)
    outer = (sl, st, w - sr, h - sb)
    win = (outer[0] + T, outer[1] + T, outer[2] - T, outer[3] - T)
    r_in = max(r - T, 1.5)
    geom = dict(w=w, h=h, outer=outer, win=win, ml=ml, mt=mt, mr=mr, mb=mb)
    cv = Canvas(w, h)
    reach = max(1.0, min(sl, sr, st + dy, sb - dy))
    cv.over((6, 5, 4), shadow(w, h, outer, r, dy, reach, shadow_a[0]))
    cv.over((6, 5, 4), shadow(w, h, outer, r, min(1.2, dy), min(reach, 3.5), shadow_a[1]))
    # the face
    ty, tx = tile_xy(w, h, ml, mt)
    if face == "slate":
        base = wrap_at(mats.slate(cx, cy), ty, tx) * gain
        d = wrap_at(mats.dust(cx, cy), ty, tx)[..., None]
        fc = np.clip(base + d * np.array([20.0, 24.0, 21.0], np.float32) * dust, 0, 255)
    elif callable(face):
        fc = face(geom)
    else:
        fc = np.broadcast_to(np.asarray(face, np.float32), (h, w, 3)).copy()
    sd_win = rr_sdf(w, h, win, r_in)
    if dark is not None:
        occl, ligh = inner_light(sd_win, w, h, win, inner, dark[0], dark[1], lit_a=lit_a, r_in=r_in)
        fc = fc * (1.0 - occl)[..., None] + ligh[..., None] * 255.0
    if face == "slate":
        # a little chalk dust settles along the bottom of the face
        _, yy = grid(w, h)
        inside = -sd_win
        fade = 1.0 - smoothstep(inner - 3.0, inner - 0.5, inside)
        dust_b = np.exp(-np.maximum(win[3] - yy, 0.0) / 5.0) * (inside > 0) * fade
        fc = fc + dust_b[..., None] * np.array([7.0, 8.0, 7.0], np.float32)
    cv.over(fc, cov(sd_win))
    if hi_top is not None:
        col, a, depth = hi_top
        cv.over(col, band(sd_win, w, h, win, depth, 0.0, r_in) * a)
    if hi_bot is not None:
        col, a, depth = hi_bot
        cv.over(col, band(sd_win, w, h, win, -depth, 0.0, r_in) * a)
    if chalk_border > 0:
        sdc = rr_sdf(w, h, (win[0] + 8, win[1] + 8, win[2] - 8, win[3] - 8), max(r_in - 8, 1.5))
        n = 0.55 + 0.45 * wrap_at(mats.dust(cx, cy), ty, tx)
        cv.over((236, 230, 216), cov(np.abs(sdc) - 0.7) * chalk_border * n * cov(sd_win + 1.0))
    # the rim
    if rim is not None and T > 0:
        if rim in ("oak", "brass"):
            rh, rv = mats.strips(rim, cx, cy)
        else:
            rh, rv = solid_strips(rim)
        rgb, sd_out, ring = rim_ring(w, h, outer, T, r, rh, rv, ml, mt, mitre=(mitre and rim == "oak"), profile=profile, k=k, rows=rim_rows, spec=spec)
        cv.over(rgb, cov(sd_out) * (1.0 - cov(sd_win)))
        edge = cov(np.abs(sd_out + 0.5) - 0.5) * cov(sd_out + 0.2)
        cv.over(outline, edge * outline_a)
    if nails:
        c = T * 0.5 + 0.5
        pts = [(outer[0] + c, outer[1] + c), (outer[2] - c, outer[1] + c), (outer[0] + c, outer[3] - c), (outer[2] - c, outer[3] - c)]
        rng = np.random.RandomState(7)
        for (px, py) in pts[:nails]:
            nail(cv, px, py, nail_r, base=nail_base, slot=(rng.uniform(0.3, 2.8) if screws else None))
    if extra is not None:
        extra(cv, geom)
    return Frame(name, cv.image(), (ml, mt, mr, mb), content, ext, stretch, ink=ink, check=check)


# ------------------------------------------------------------- the frames --

SLATE_GRAIN = periodic_noise(64, 64, (0.7, 1.7), (1.0, 0.6), seed=11)
BRASS_GRAIN = brushed_noise(64, 64, 7.0, 0.5, seed=5)


def with_grain(face, grain, amp):
    """A face function with a periodic grain (a tile of noise, around zero) added to its colour."""
    def f(g):
        ty, tx = tile_xy(g["w"], g["h"], g["ml"], g["mt"])
        return face(g) + wrap_at(grain, ty, tx)[..., None] * amp
    return f


def make_panel(mats):
    return make_plate(mats, "panel", centre=(384, 384), T=12, inner=8, r=10, ext=(8, 6, 8, 14), rim="oak", face="slate",
                      content=(12, 10, 12, 10), nails=4, dy=3.0, dust=0.44)


def make_panel_slim(mats):
    return make_plate(mats, "panel_slim", centre=(256, 128), T=6, inner=5, r=8, ext=(6, 4, 6, 10), rim="oak", face="slate",
                      content=(6, 5, 6, 5), nails=0, dy=2.4, shadow_a=(0.42, 0.36), k=2.0, dark=(0.34, 0.46), dust=0.18)


def make_clock(mats):
    return make_plate(mats, "clock", centre=(320, 224), T=10, inner=8, r=14, ext=(8, 6, 8, 14), rim="brass", face="slate",
                      content=(12, 10, 12, 10), nails=4, nail_r=2.8, nail_base=(118, 92, 40), screws=True, gain=0.92, dy=3.0, dust=0.42,
                      profile=[(0.0, 0.0), (0.12, 0.45), (0.30, 0.85), (0.5, 1.0), (0.72, 0.85), (0.9, 0.5), (1.0, 0.15)], k=3.0,
                      outline=(58, 40, 10))


def make_panel_inset(mats):
    """A block set into a panel (a nested block): the slate a little darker, in the shadow
    of its upper edge and with a faint light along its lower one. No trim, no shadow."""
    return make_plate(mats, "panel_inset", centre=(128, 128), T=0, inner=10, r=6, ext=(0, 0, 0, 0), rim=None, face="slate", gain=0.8,
                      content=(8, 6, 8, 6), dust=0.2, dark=(0.40, 0.55), dy=0.0, shadow_a=(0.0, 0.0),
                      hi_bot=((230, 224, 205), 0.10, 1.4), hi_top=((0, 0, 0), 0.28, 1.2))


def make_tooltip(mats):
    face = with_grain(vgrad((30, 41, 37), (24, 33, 30), (20, 28, 25), 6), SLATE_GRAIN, 1.8)
    return make_plate(mats, "tooltip", centre=(64, 64), T=3, inner=6, r=8, ext=(5, 3, 5, 8), rim=(122, 84, 48), face=face,
                      content=(10, 7, 10, 7), stretch=(TILE_FIT, TILE_FIT), dy=2.5, shadow_a=(0.5, 0.4), k=1.6, dark=(0.3, 0.4))


def make_toast(mats):
    face = with_grain(vgrad((30, 41, 37), (24, 33, 30), (20, 28, 25), 6), SLATE_GRAIN, 1.8)
    return make_plate(mats, "toast", centre=(64, 64), T=4, inner=6, r=10, ext=(6, 4, 6, 10), rim=(128, 88, 50), face=face,
                      content=(14, 7, 14, 8), stretch=(TILE_FIT, TILE_FIT), dy=3.0, shadow_a=(0.5, 0.4), k=1.8, dark=(0.3, 0.4))


def make_banner(mats):
    return make_plate(mats, "banner", centre=(192, 96), T=10, inner=10, r=14, ext=(8, 6, 8, 14), rim="oak", face="slate",
                      content=(28, 10, 28, 12), nails=4, nail_r=2.6, dy=3.0, chalk_border=0.22, dust=0.30)


BUTTON = dict(centre=(64, 64), T=4, inner=8, r=7, ext=(3, 2, 3, 5), stretch=(TILE_FIT, TILE_FIT), content=(14, 2, 14, 2))
def make_button(mats, name, rim, top, mid, bot, *, pressed=False, off=False, check=(INK, INK2), ink=INK, hi=0.14, lo=0.30, glow=0.0,
                k=2.0, brass=False, spec=0.5):
    sh = (0.30, 0.22) if pressed else (0.50, 0.40)
    face = with_grain(vgrad(top, mid, bot, 7), BRASS_GRAIN if brass else SLATE_GRAIN, 5.0 if brass else 1.8)
    return make_plate(mats, name, rim=rim, face=face, shadow_a=sh, dy=(0.8 if pressed else 1.6), k=k, spec=spec,
                      dark=((0.55, 0.45) if pressed else (0.0, 0.0)) if not off else None, lit_a=glow,
                      hi_top=None if (off or pressed) else ((255, 250, 235), hi, 1.4),
                      hi_bot=None if off else (((255, 250, 235), 0.10, 1.2) if pressed else ((0, 0, 0), lo, 2.4)),
                      outline=(20, 14, 10), outline_a=0.7, check=check, ink=ink, rim_rows=(14, 60, 98, 36), **BUTTON)


def make_buttons(mats):
    out = []
    out.append(make_button(mats, "button", "oak", (46, 60, 55), (37, 50, 46), (29, 39, 36)))
    out.append(make_button(mats, "button_hover", "oak", (58, 74, 68), (48, 63, 58), (37, 49, 45), glow=0.10, hi=0.2, spec=0.9))
    out.append(make_button(mats, "button_pressed", (92, 64, 38), (23, 31, 28), (28, 38, 34), (34, 46, 42), pressed=True))
    out.append(make_button(mats, "button_off", (84, 76, 68), (31, 39, 37), (30, 38, 36), (29, 37, 35), off=True, check=(INK,), k=0.8))
    out.append(make_button(mats, "button_primary", "brass", (252, 216, 108), (240, 198, 78), (216, 166, 54), check=(ACCENT_INK,), ink=ACCENT_INK, hi=0.34, lo=0.22, brass=True, spec=0.9))
    out.append(make_button(mats, "button_primary_hover", "brass", (255, 228, 134), (248, 210, 96), (228, 180, 66), check=(ACCENT_INK,), ink=ACCENT_INK, hi=0.4, lo=0.18, glow=0.18, brass=True, spec=1.0))
    out.append(make_button(mats, "button_primary_pressed", (110, 76, 24), (206, 156, 48), (224, 178, 64), (238, 196, 82), pressed=True, check=(ACCENT_INK,), ink=ACCENT_INK, brass=True))
    return out


def make_chip(mats):
    """A key chip: a small keycap, lighter than the board it sits on."""
    return make_plate(mats, "chip", centre=(8, 10), T=2, inner=4, r=6, ext=(2, 1, 2, 4), rim=(150, 142, 126),
                      face=vgrad((70, 85, 79), (56, 70, 65), (42, 54, 50), 5), content=(4, 0, 4, 1), stretch=(STRETCH, STRETCH),
                      dy=1.4, shadow_a=(0.45, 0.35), k=1.2, dark=None, outline=(22, 18, 14), outline_a=0.7,
                      hi_top=((255, 250, 235), 0.16, 1.2), hi_bot=((0, 0, 0), 0.30, 2.0), check=(INK, INK2))


def make_pill(mats):
    """A capsule, pale like card stock (the PAUSED stamp, the phase chip): dark ink, and it
    takes a tint."""
    return make_plate(mats, "pill", centre=(4, 4), T=2, inner=3, r=16, ext=(3, 2, 3, 5), rim=(178, 168, 148),
                      face=vgrad((248, 245, 234), (238, 233, 219), (220, 212, 196), 8), content=(7, 2, 7, 2), stretch=(STRETCH, STRETCH),
                      dy=1.6, shadow_a=(0.40, 0.30), k=1.4, dark=None, outline=(70, 60, 44), outline_a=0.5,
                      hi_bot=((90, 76, 50), 0.16, 2.0), ink=ACCENT_INK, check=(ACCENT_INK, PAPER_INK))


def make_bar_track(mats):
    """The groove a meter fills: dark, in the shadow of its upper edge, a faint light along its lower."""
    return make_plate(mats, "bar_track", centre=(4, 0), T=0, inner=3, r=6, ext=(0, 0, 0, 0), rim=None,
                      face=vgrad((10, 15, 13), (18, 26, 23), (26, 36, 32), 5), content=(0, 0, 0, 0), stretch=(STRETCH, STRETCH),
                      dy=0.0, shadow_a=(0.0, 0.0), dark=None, hi_bot=((236, 228, 206), 0.18, 1.2), hi_top=((0, 0, 0), 0.35, 1.6), check=())


def make_bar_fill(mats):
    """What fills a meter: a pale capsule with a soft gloss and a faint chalk hatch (one hatch is
    8 pixels wide and the middle tiles it, so the stripes run unbroken however long the bar is).
    The caller tints it with the colour of what it measures."""
    cap, per, h = 6, 8, 12
    w = cap + per + cap
    cv = Canvas(w, h)
    sd = rr_sdf(w, h, (0, 0, w, h), 6.0)
    xx, yy = grid(w, h)
    col = np.asarray((240, 240, 240), np.float32)[None, None, :] * (1.0 - 0.18 * smoothstep(0.0, h, yy))[..., None]
    col = col + 14.0 * np.exp(-((yy - 2.0) / 1.6) ** 2)[..., None]
    hatch = 0.5 + 0.5 * np.sin(2.0 * np.pi * (xx - cap + yy) / per)
    col = col * (1.0 - 0.10 * smoothstep(0.55, 0.95, hatch))[..., None]
    col = col * (1.0 - 0.22 * np.exp(-np.maximum(-sd, 0.0) / 0.9))[..., None]
    cv.over(col, cov(sd))
    return Frame("bar_fill", cv.image(), (cap, 0, cap, 0), (0, 0, 0, 0), (0, 0, 0, 0), (TILE_FIT, STRETCH), ink=INK, check=())


def capsule_sdf(w, h, x1, x2, y, r):
    """Signed distance to a horizontal capsule (a slot) from (x1, y) to (x2, y), radius r."""
    xx, yy = grid(w, h)
    dx = np.maximum(np.maximum(x1 - xx, xx - x2), 0.0)
    return (np.hypot(dx, yy - y) - r).astype(np.float32)


def make_card(mats, selected=False):
    """A hall-pass badge for a member of the crew: card stock round a dark window the
    portrait fills, a slot for the lanyard in the top rim (its brass eyelet runs along the
    top and gets longer as the badge gets wider). The chosen one is brass, a pixel bigger all
    round (the window stays where it was), higher in its shadow, with a warm glow. Both have
    the same content margins: 3 logical pixels at the sides and the foot, 9 at the top."""
    name = "card_selected" if selected else "card"
    sl, st, sr, sb = (10, 9, 10, 14) if selected else (4, 3, 4, 8)      # where the Control's rectangle is
    over = 2 if selected else 0                                           # the chosen badge is bigger than it
    rs, rt, rb = 6 + over, 18 + over, 6 + over                            # the rim: at the sides, the top, the foot
    r = 9.0 + over
    M = 34                                                                # the ends of the slot lie in these side margins
    ml, mt, mr, mb = sl + M, st + 18 + 1, sr + M, sb + 6 + 1              # the nine-patch margins
    cx, cy = 8, 24
    cx, cy = even_up(ml + cx + mr) - ml - mr, even_up(mt + cy + mb) - mt - mb
    w, h = ml + cx + mr, mt + cy + mb
    outer = (sl - over, st - over, w - sr + over, h - sb + over)
    win = (sl + 6, st + 18, w - sr - 6, h - sb - 6)
    cv = Canvas(w, h)
    reach = max(1.0, min(sl, sr, st + 3.5, sb - 3.5))
    if selected:
        cv.over((244, 196, 80), shadow(w, h, outer, r, 0.0, float(min(sl, st)), 0.50))
    cv.over((6, 5, 4), shadow(w, h, outer, r, 3.5 if not selected else 4.5, reach, 0.46))
    cv.over((6, 5, 4), shadow(w, h, outer, r, 1.2, min(reach, 3.5), 0.40))
    sd_out = rr_sdf(w, h, outer, r)
    sd_win = rr_sdf(w, h, win, 3.0)
    u = np.maximum(-sd_out, 0.0)
    wd = np.maximum(sd_win, 0.0)
    hs = smoothstep(0.0, 2.6, u) * (1.0 - 0.85 * (1.0 - smoothstep(0.0, 2.4, wd)))
    hs = np.where(sd_win < 0, 0.0, hs)
    shade = np.clip(lit(hs, k=2.8), 0.5, 1.8)
    _, yy = grid(w, h)
    if selected:
        top, mid, bot = (240, 214, 142), (214, 172, 88), (172, 128, 54)
    else:
        top, mid, bot = (230, 224, 208), (216, 208, 190), (198, 190, 172)
    top, mid, bot = (np.asarray(c, np.float32) for c in (top, mid, bot))
    t1 = smoothstep(outer[1], outer[1] + 16, yy)[..., None]
    t2 = smoothstep(outer[3], outer[3] - 16, yy)[..., None]
    stock = bot * (1 - t2) + (top * (1 - t1) + mid * t1) * t2
    # the grain of card stock (fibres and a few specks), a little of it so the stock is not smooth
    grain = wrap_at(mats.card(256, 256), np.arange(h)[:, None] + 7, np.arange(w)[None, :] + 11)
    grain = (grain.mean(axis=2, keepdims=True) - grain.mean()) / 214.0
    stock = stock * (1.0 + grain * (0.55 if not selected else 0.35))
    cv.over(apply_light(stock, shade, spec=0.55), cov(sd_out))
    edge = cov(np.abs(sd_out + 0.5) - 0.5) * cov(sd_out + 0.2)
    cv.over((96, 64, 16) if selected else (120, 108, 88), edge * 0.6)
    # the window
    face = vgrad((18, 26, 23), (30, 42, 38), (34, 47, 43), 4)({"w": w, "h": h, "win": win})
    cv.over(face, cov(sd_win))
    cv.over((8, 12, 10), cov(np.abs(sd_win + 0.6) - 0.6) * 0.75)
    # the slot for the lanyard in the top rim, with a brass eyelet round it
    sy = outer[1] + rt * 0.5
    x1, x2 = ml - 12.0, (w - mr) + 12.0
    sd_slot = capsule_sdf(w, h, x1, x2, sy, 3.2)
    ring_h = np.clip(1.0 - np.abs(sd_slot - 0.9) / 1.1, 0.0, 1.0) * (sd_slot > -0.5)
    ring_sh = np.clip(lit(ring_h * 1.0, k=3.2), 0.4, 1.8)
    brass = apply_light(np.broadcast_to(np.asarray((178, 142, 68), np.float32), (h, w, 3)), ring_sh, spec=0.7)
    cv.over((10, 8, 6), cov(capsule_sdf(w, h, x1 + 0.6, x2 + 0.6, sy + 0.9, 3.2 + 1.4), 1.4) * 0.38)
    cv.over(brass, cov(sd_slot - 1.8))
    cv.cut(cov(sd_slot))
    crescent = cov(sd_slot) * (1.0 - cov(capsule_sdf(w, h, x1 + 0.9, x2 + 0.9, sy + 1.2, 3.2)))
    cv.over((6, 5, 4), crescent * 0.6)
    return Frame(name, cv.image(), (ml, mt, mr, mb), (3, 9, 3, 3), (sl, st, sr, sb), (STRETCH, STRETCH), ink=INK, check=(INK, INK2, INK3))


def folded_corner_sd(w, h, outer, r, fold, dy=0.0):
    """The signed distance to a page whose bottom right corner is folded away, the page moved down by dy."""
    xx, yy = grid(w, h)
    rect = rr_sdf(w, h, (outer[0], outer[1] + dy, outer[2], outer[3] + dy), r)
    return np.maximum(rect, (fold - ((outer[2] - xx) + (outer[3] + dy - yy))) / 1.4142)


def corner_cut(w, h, outer, fold):
    """1 over the page, 0 over the corner that is folded away (with a soft diagonal edge)."""
    xx, yy = grid(w, h)
    return np.clip((((outer[2] - xx) + (outer[3] - yy)) - fold) / 1.4 + 0.5, 0.0, 1.0)


def draw_fold(cv, w, h, outer, fold, sd, back=(238, 233, 220)):
    """The folded corner over a page that is already drawn: the shadow the page throws under the
    flap's two free edges, the flap (the back of the paper, a little darker, lighter toward the
    crease) and the crease. `sd` is the page's distance field (see folded_corner_sd)."""
    xx, yy = grid(w, h)
    uu, vv = outer[2] - xx, outer[3] - yy                     # distance from the right and the bottom edge
    flap = (uu < fold) & (vv < fold) & ((uu + vv) > fold)
    d_far = np.hypot(fold - uu, fold - vv) / (fold * 0.9)
    flap_col = np.asarray(back, np.float32)[None, None, :] * (0.92 + 0.08 * np.clip(1.0 - d_far, 0.0, 1.0))[..., None]
    free = np.minimum(np.abs(uu - fold), np.abs(vv - fold))
    cv.over((40, 32, 24), np.exp(-np.maximum(free - 0.5, 0.0) / 1.8) * 0.28 * (uu < fold + 2) * (vv < fold + 2) * (~flap) * cov(sd) * ((uu + vv) > fold))
    flap_a = np.clip(np.minimum(np.minimum(fold - uu, fold - vv), (uu + vv) - fold) / 1.0 + 0.5, 0.0, 1.0) * (uu > 0) * (vv > 0)
    cv.over(flap_col, flap_a * cov(sd))
    crease = np.exp(-(np.abs((uu + vv) - fold) / 0.9) ** 2) * (uu < fold + 1) * (vv < fold + 1)
    cv.over((255, 252, 244), crease * 0.6)


def make_slip(mats):
    """A slip of paper pinned to the board for an alert: pale and neutral (the HUD tints
    it with the colour of the level), a pushpin at the top right, the bottom right corner
    folded over and the foot of the page curling up a little. Dark ink."""
    sl, st, sr, sb = 6, 4, 6, 12
    fold = 20.0
    ml, mt, mr, mb = sl + 14, st + 24, sr + 30, sb + 26
    cx, cy = 64, 64
    cx, cy = even_up(ml + cx + mr) - ml - mr, even_up(mt + cy + mb) - mt - mb
    w, h = ml + cx + mr, mt + cy + mb
    outer = (sl, st, w - sr, h - sb)
    cv = Canvas(w, h)
    xx, yy = grid(w, h)
    reach = max(1.0, min(sl, sr, st + 2.5, sb - 3.0))
    for dy_, rc, al in ((3.0, reach, 0.44), (1.0, min(reach, 3.0), 0.34)):
        t = 1.0 - smoothstep(0.0, rc, folded_corner_sd(w, h, outer, 4.0, fold, dy_))
        cv.over((6, 5, 4), al * t * t)
    sd = rr_sdf(w, h, outer, 4.0)
    ty, tx = tile_xy(w, h, ml, mt)
    fibre = wrap_at(periodic_noise(cx, cy, seed=4), ty, tx)[..., None]
    paper = np.asarray((250, 246, 236), np.float32)[None, None, :] + fibre * 2.2
    # the page: lighter at the top, a little darker toward the foot, in the shade of its own edge
    paper = paper * (1.0 + 0.016 * (1.0 - smoothstep(0.0, 14.0, yy - outer[1])) - 0.035 * (1.0 - smoothstep(0.0, 20.0, outer[3] - yy)))[..., None]
    u_in = np.maximum(-sd, 0.0)
    paper = paper * (1.0 - 0.06 * np.exp(-u_in / 2.2))[..., None]
    # the foot curls up: a light band over a darker one along the bottom edge
    foot = outer[3] - yy
    paper = paper * (1.0 - 0.06 * np.exp(-((foot - 3.0) / 2.6) ** 2))[..., None]
    paper = paper + 5.0 * np.exp(-((foot - 6.5) / 1.6) ** 2)[..., None]
    alpha = cov(sd) * corner_cut(w, h, outer, fold)
    cv.over(paper, alpha)
    draw_fold(cv, w, h, outer, fold, sd)
    cv.over((60, 50, 38), cov(np.abs(sd + 0.5) - 0.5) * 0.20 * alpha)
    cv.over((255, 255, 250), cov(np.abs(sd + 0.5) - 0.5) * 0.35 * alpha * (yy < outer[1] + 3) * (xx < outer[2] - 10))
    # the pushpin, in the top right corner
    px, py = outer[2] - 17, outer[1] + 13
    nail(cv, px, py, 6.0, base=(202, 202, 212), shine=0.7, cast=(2.6, 3.4))
    cv.over((60, 60, 74), cov(np.abs(circle_sdf(w, h, px, py, 6.0)) - 0.4) * 0.4)
    return Frame("slip", cv.image(), (ml, mt, mr, mb), (9, 8, 10, 8), (sl, st, sr, sb), (TILE_FIT, TILE_FIT), ink=(0x17, 0x13, 0x0a), check=((0x17, 0x13, 0x0a),))


def make_bubble(mats):
    """A speech bubble for what someone says in the world: a slip of pale paper with a rounded
    outline and a tail at the bottom left, in a soft shadow. Dark ink.

    The tail lies wholly inside the left margin of the nine-patch (the left margin is 44 pixels past
    the bubble's edge, the tail ends 36 out), so the middle can stretch to any width without bending
    it. Where the tail's tip is, measured from the bubble's left edge and below its foot, is given in
    frames.json as "tail" (logical px); the HUD puts the tip on the speaker's head, and draws the
    picture mirrored when the speaker is nearer the bubble's right end."""
    sl, st, sr, sb = 6, 4, 6, 26                # where the bubble is in the picture: the shadow outside it; the foot has the tail (16) and its shadow (10)
    ml, mt, mr, mb = 50, 18, 20, 38             # the nine-patch margins
    cx, cy = 16, 8
    w, h = ml + cx + mr, mt + cy + mb
    need_even(w, h, "bubble")
    outer = (sl, st, w - sr, h - sb)
    r = 10.0
    tail = ((outer[0] + 14.0, outer[3] - 3.0), (outer[0] + 36.0, outer[3] - 3.0), (outer[0] + 17.0, outer[3] + 16.0))
    tip = (tail[2][0] - outer[0], tail[2][1] - outer[3])

    def union(dy=0.0):
        body = rr_sdf(w, h, (outer[0], outer[1] + dy, outer[2], outer[3] + dy), r)
        t = tri_sdf(w, h, *[(x, y + dy) for x, y in tail])
        return smooth_union(body, t, 3.0)

    cv = Canvas(w, h)
    xx, yy = grid(w, h)
    reach = 5.0
    for dy_, rc, al in ((3.0, reach, 0.46), (1.0, 3.0, 0.34)):
        t = 1.0 - smoothstep(0.0, rc, union(dy_))
        cv.over((6, 5, 4), al * t * t)
    sd = union()
    ty, tx = tile_xy(w, h, ml, mt)
    fibre = wrap_at(periodic_noise(cx, cy, seed=6), ty, tx)[..., None]
    paper = np.asarray((251, 247, 237), np.float32)[None, None, :] + fibre * 0.7
    # lighter at the top, a little darker toward the foot of the body, in the shade of its own edge
    paper = paper * (1.0 + 0.018 * (1.0 - smoothstep(0.0, 12.0, yy - outer[1])) - 0.04 * (1.0 - smoothstep(0.0, 14.0, outer[3] - yy)))[..., None]
    paper = paper * (1.0 - 0.05 * np.exp(-np.maximum(-sd, 0.0) / 2.0))[..., None]
    cv.over(paper, cov(sd))
    # the edge: a dark brown line all round the bubble and its tail, and a pale lip along the top
    cv.over((70, 58, 40), cov(np.abs(sd + 0.8) - 0.8) * 0.78)
    cv.over((255, 255, 250), cov(np.abs(sd + 2.2) - 0.7) * 0.40 * (yy < outer[1] + 6) * (xx > outer[0] + 8) * (xx < outer[2] - 8))
    return Frame("bubble", cv.image(), (ml, mt, mr, mb), (8, 5, 8, 6), (sl, st, sr, sb), (STRETCH, STRETCH), ink=ACCENT_INK, check=(ACCENT_INK, PAPER_INK),
                 extra={"tail": [round(tip[0] * LOGICAL, 2), round(tip[1] * LOGICAL, 2)]})


def make_paper(mats):
    """A page of ruled notebook paper for a modal: pale rules, a red margin line, three-hole
    punch holes down the left edge (the rules, the holes and the paper repeat every four
    lines, so the page can be any height), a soft shadow and the bottom right corner turned
    down."""
    sl, st, sr, sb = 8, 6, 8, 14
    LS = 28                                     # the rules are 14 logical pixels apart
    ml, mt, mr, mb = sl + 72, st + 36, sr + 28, sb + 36
    cx, cy = 256, LS * 4
    w, h = ml + cx + mr, mt + cy + mb
    need_even(w, h, "paper")
    outer = (sl, st, w - sr, h - sb)
    cv = Canvas(w, h)
    fold = 24.0                                 # (its shadow, 2 more, stays inside the margins)
    reach = max(1.0, min(sl, sr, st + 5.0, sb - 5.0))
    for dy_, rc, al in ((5.0, reach, 0.46), (1.6, min(reach, 4.0), 0.36)):
        t = 1.0 - smoothstep(0.0, rc, folded_corner_sd(w, h, outer, 6.0, fold, dy_))
        cv.over((6, 5, 4), al * t * t)
    sd = rr_sdf(w, h, outer, 6.0)
    ty, tx = tile_xy(w, h, ml, mt)
    paper = wrap_at(mats.paper(cx, cy), ty, tx)
    xx, yy = grid(w, h)
    u_in = np.maximum(-sd, 0.0)
    paper = paper * (1.0 - 0.06 * np.exp(-u_in / 3.0))[..., None]
    cut = corner_cut(w, h, outer, fold)
    cv.over(paper, cov(sd) * cut)
    # the rules, only over the body of the page
    phase = np.mod(ty - 24, LS)
    rule = np.clip(1.5 - np.abs(phase - 1.0), 0.0, 1.0) * ((yy > mt) & (yy < h - mb)) * (xx > outer[0] + 3) * (xx < outer[2] - 3)
    cv.over((118, 146, 192), rule * 0.40 * cov(sd + 1.0) * cut)
    # the margin line
    xm = outer[0] + 54.0
    cv.over((214, 98, 92), np.clip(1.5 - np.abs(xx - xm - 1.0), 0.0, 1.0) * 0.72 * cov(sd + 1.0) * cut * (yy > outer[1] + 3) * (yy < outer[3] - 3))
    # the punch holes: one in every four lines, between two rules, in the left strip only
    hx = outer[0] + 22.0
    ry = np.mod(ty, cy)
    hole_dist = np.hypot(xx - hx, ry - 67.0)
    in_strip = (yy >= mt) & (yy < h - mb) & (xx < ml)
    ring = np.exp(-(np.maximum(hole_dist - 5.5, 0.0) / 1.1) ** 2) * (hole_dist > 5.0)
    cv.over((70, 62, 50), ring * 0.30 * in_strip * cov(sd))
    cv.cut(cov(hole_dist - 5.5) * in_strip)
    # the wall of the hole, in the shade at its top left
    wall = cov(hole_dist - 5.5) * (1.0 - cov(np.hypot(xx - (hx + 1.0), ry - 68.2) - 5.5)) * in_strip
    cv.over((50, 44, 34), wall * 0.7)
    # the turned corner
    draw_fold(cv, w, h, outer, fold, sd, back=(228, 222, 206))
    return Frame("paper", cv.image(), (ml, mt, mr, mb), (33, 18, 18, 18), (sl, st, sr, sb), (TILE_FIT, TILE_FIT), ink=PAPER_INK, check=(PAPER_INK, ACCENT_INK))


def build_all(mats):
    """Every frame, the ones the HUD needs first."""
    out = [make_panel(mats), make_card(mats), make_card(mats, True), make_slip(mats), make_paper(mats)]
    out.append(make_bubble(mats))
    out += make_buttons(mats)
    out += [make_panel_inset(mats), make_clock(mats), make_tooltip(mats), make_toast(mats), make_chip(mats), make_bar_track(mats),
            make_pill(mats), make_banner(mats), make_panel_slim(mats), make_bar_fill(mats)]
    return out


# ----------------------------------------------------------------- preview --

def map_axis(n_dst, n_src, m0, m1, mode):
    """For every pixel of a stretched side of a nine-patch, the pixel of the picture
    Godot draws there (the same arithmetic as the canvas shader's)."""
    p = np.arange(n_dst, dtype=np.float64) + 0.5
    out = np.empty(n_dst)
    first = p < m0
    last = p >= n_dst - m1
    mid = ~(first | last)
    out[first] = p[first]
    out[last] = n_src - (n_dst - p[last])
    cs, cd = n_src - m0 - m1, n_dst - m0 - m1
    q = p[mid] - m0
    if cs <= 0 or cd <= 0:
        out[mid] = m0
    elif mode == STRETCH:
        out[mid] = m0 + q / cd * cs
    elif mode == TILE:
        out[mid] = m0 + np.mod(q, cs)
    else:
        scale = max(1.0, math.floor(cd / cs + 0.5))
        out[mid] = m0 + np.mod(q / cd * scale, 1.0) * cs
    return out


def nine_slice(frame, w_log, h_log):
    """What Godot draws for a Control of w_log x h_log logical pixels with this frame, at
    2 pixels to the logical one: the picture over the Control's rectangle grown by `expand`,
    its middle filled as `stretch` says. Returns an RGBA float array and the position of
    the Control's top left corner in it."""
    ex = frame.expand
    wd = int(round((w_log + ex[0] + ex[2]) * 2.0))
    hd = int(round((h_log + ex[1] + ex[3]) * 2.0))
    arr = np.asarray(frame.img).astype(np.float32)
    th, tw = arr.shape[:2]
    l, t, r, b = frame.margin
    sx = map_axis(wd, tw, l, r, frame.stretch[0])
    sy = map_axis(hd, th, t, b, frame.stretch[1])
    x0 = np.clip(np.floor(sx - 0.5).astype(int), 0, tw - 1)
    x1 = np.clip(x0 + 1, 0, tw - 1)
    fx = np.clip(sx - 0.5 - x0, 0, 1)[None, :, None]
    y0 = np.clip(np.floor(sy - 0.5).astype(int), 0, th - 1)
    y1 = np.clip(y0 + 1, 0, th - 1)
    fy = np.clip(sy - 0.5 - y0, 0, 1)[:, None, None]
    pm = arr.copy()
    pm[..., :3] *= pm[..., 3:4] / 255.0                                # premultiply to filter
    top = pm[y0][:, x0] * (1 - fx) + pm[y0][:, x1] * fx
    bot = pm[y1][:, x0] * (1 - fx) + pm[y1][:, x1] * fx
    out = top * (1 - fy) + bot * fy
    a = out[..., 3:4]
    rgb = np.where(a > 1e-3, out[..., :3] / np.maximum(a, 1e-3) * 255.0, 0.0)
    return np.concatenate([rgb, a], axis=2), (ex[0] * 2.0, ex[1] * 2.0)


def paste(bg, fg, x, y, tint=None):
    """Straight-alpha `fg` (float RGBA) over `bg` (float RGB) at integer x, y."""
    h, w = fg.shape[:2]
    x, y = int(round(x)), int(round(y))
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(bg.shape[1], x + w), min(bg.shape[0], y + h)
    if x1 <= x0 or y1 <= y0:
        return
    f = fg[y0 - y:y1 - y, x0 - x:x1 - x]
    a = f[..., 3:4] / 255.0
    rgb = f[..., :3]
    if tint is not None:
        rgb = rgb * np.asarray(tint, np.float32)
    bg[y0:y1, x0:x1] = rgb * a + bg[y0:y1, x0:x1] * (1 - a)


PREVIEW = {
    "panel": [(140, 165), (248, 150), (300, 200), (560, 90)],
    "panel_slim": [(180, 40), (240, 38), (130, 90)],
    "clock": [(248, 150), (164, 110)],
    "panel_inset": [(120, 80), (240, 40)],
    "tooltip": [(150, 40), (260, 56)],
    "toast": [(200, 32), (320, 32)],
    "banner": [(420, 92), (260, 70)],
    "chip": [(24, 18), (60, 18), (28, 18)],
    "pill": [(76, 18), (96, 20), (60, 18)],
    "bar_track": [(120, 6), (60, 8), (200, 6)],
    "bar_fill": [(120, 6), (60, 8), (200, 6)],
    "card": [(60, 80), (72, 96), (48, 68)],
    "card_selected": [(60, 80), (72, 96), (48, 68)],
    "slip": [(248, 52), (248, 70), (164, 52)],
    "paper": [(320, 220), (460, 300), (560, 160)],
    "bubble": [(70, 22), (140, 32), (200, 46)],
}
for _n in ("button", "button_hover", "button_pressed", "button_off", "button_primary", "button_primary_hover", "button_primary_pressed"):
    PREVIEW[_n] = [(66, 66), (112, 40), (200, 36), (44, 44)]


def backdrop(w, h, kind="day"):
    """A stand-in for the world behind the HUD: asphalt by day, dark blue-grey at night."""
    rng = np.random.RandomState(3)
    base = np.array((120, 112, 102) if kind == "day" else (40, 38, 50), np.float32)
    noise = gblur(rng.randn(h, w).astype(np.float32), 1.2) * 6.0 + gblur(rng.randn(h, w).astype(np.float32), 18.0) * 40.0
    return np.clip(base[None, None, :] + noise[..., None], 0, 255).astype(np.float32)


def contact_sheet(frames, path, tint_map=None, kinds=("day", "night")):
    """One picture of every frame at several sizes, on a daylight and a night backdrop."""
    rows = []
    for f in frames:
        sizes = PREVIEW.get(f.name, [(140, 100), (260, 100)])
        rows.append((f, [nine_slice(f, wl, hl)[0] for (wl, hl) in sizes]))
    width = max(sum(i.shape[1] + 40 for i in imgs) + 40 for f, imgs in rows)
    height = sum(max(i.shape[0] for i in imgs) + 50 for f, imgs in rows) + 20
    halves = []
    for kind in kinds:
        sheet = backdrop(width, height, kind)
        y = 20
        labels = []
        for f, imgs in rows:
            x = 30
            tint = (tint_map or {}).get(f.name)
            for i in imgs:
                paste(sheet, i, x, y + 20, tint)
                x += i.shape[1] + 40
            labels.append((f.name, 30, y))
            y += max(i.shape[0] for i in imgs) + 50
        halves.append((sheet, labels))
    pil = Image.fromarray(np.clip(np.concatenate([h for h, l in halves], axis=0), 0, 255).astype(np.uint8))
    dr = ImageDraw.Draw(pil)
    for k, (h, labels) in enumerate(halves):
        for (t, x, yy) in labels:
            dr.text((x, yy + 2 + k * height), t, fill=(240, 240, 230))
    pil.save(path)


def write_all(frames, only=None):
    """Writes the pictures and frames.json. With `only` (a list of names) just those frames are
    written, and their entries are put into the frames.json that is there, the rest left as it is."""
    os.makedirs(OUT, exist_ok=True)
    table = {}
    path = os.path.join(OUT, "frames.json")
    if only and os.path.exists(path):
        with open(path) as fh:
            table = json.load(fh)
    for f in frames:
        if only and f.name not in only:
            continue
        f.img.save(os.path.join(OUT, f.name + ".png"), optimize=True)
        table[f.name] = f.entry()
    with open(path, "w") as fh:
        json.dump(table, fh, indent=1)
        fh.write("\n")
    return table


def main():
    mats = Materials()
    frames = build_all(mats)
    for f in frames:
        f.verify()
    out = os.environ.get("UI_DEBUG")
    if out:
        os.makedirs(out, exist_ok=True)
        contact_sheet(frames, os.path.join(out, "sheet.png"))
        for f in frames:
            contact_sheet([f], os.path.join(out, "f_%s.png" % f.name))
        pick = [n for n in os.environ.get("UI_SHEET", "").split(",") if n]
        if pick:
            contact_sheet([f for f in frames if f.name in pick], os.path.join(out, "sel.png"))
    if not os.environ.get("UI_DRY"):
        only = [n for n in os.environ.get("UI_ONLY", "").split(",") if n]
        table = write_all(frames, only)
        print("wrote %d frames to %s" % (len(only) if only else len(table), OUT))
        for f in frames:
            if only and f.name not in only:
                continue
            print("  %-22s %4dx%-4d avg %s  %d bytes" % (f.name, f.img.width, f.img.height, hexcolor(f.avg), os.path.getsize(os.path.join(OUT, f.name + ".png"))))


if __name__ == "__main__":
    main()
