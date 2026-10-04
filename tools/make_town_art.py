#!/usr/bin/env python3
"""Draws the art kit of the town (the one big open map of streets and houses, docs/superpowers/specs/2026-10-04-one-house-design.md): procedural drawing only,
no reference pictures, no tools off the machine, deterministic (every random choice comes from a fixed seed: the same script writes the same files).

    python3 tools/make_town_art.py                  # every category: assets/town/<category>/*.png and assets/data/town_art.json
    python3 tools/make_town_art.py street roof      # only those (street house roof floor furniture outdoors fortify marker); the others stay in the manifest
    TOWN_ART_SHEETS=some/dir python3 tools/make_town_art.py     # also a contact sheet PNG per category in that folder (to look at)
    TOWN_ART_OUT=dir TOWN_ART_MANIFEST=file.json ...            # write somewhere else
    TOWN_NOISE / TOWN_FREQ / TOWN_GRAIN / TOWN_COLOURS          # texture noise, its finest frequency, film grain and palette size: the kit's size knobs

What it makes (the manifest, assets/data/town_art.json, describes every piece: read its `_doc` first; tools/town_art_sample.gd composes a sample
scene from it at the game's tile size):

    street     asphalt (3), sidewalk slabs (3), lawn (3), dirt (2), gravel (2) as seamless 4 x 4 atlases of 64 px pieces; lane paint, the kerb with its
               corners, leaves (3), manholes (2), drains (2)
    house      wall tops in brick, white siding, blue siding, stucco and three inside materials (a 128 px tile each) with ONE autotile set of outlines and
               rims (wall_edges, by the mask of the open sides) and the soft wall shadows; front doors, inside doors and garage doors (closed / open / broken,
               four facings), windows (intact / broken / boarded), the step, the porch
    roof       terracotta, slate and brown shingle: lit and shaded slope tiles, ridge caps, an eave overlay (autotile, overhang and shadow), chimneys
    floor      wood (2), hall boards, hallway runner (2 ways), kitchen lino (2), bedroom carpet (2), bathroom tile (2): 4 x 4 atlases, worn
    furniture  39 things: kitchen, bedroom, living room, bathroom, workshop, containers (each with an `opened` look for 'searched'), rugs, a lamp, the base's radio
               set and stash chest, clutter decals (papers, glass, blood, a bag, a mattress)
    outdoors   picket (2), chain link, low brick wall and hedge as autotile lines, a yard gate, bushes, trees (reused), mailbox, bins, a bike, garden beds,
               a shed, swing set, slide, bench, market stall, parked cars in four colours (reused from the yard's sedans) and two wrecks (reused)
    fortify    wooden fence, reinforced fence and sandbags (autotile, built and damaged), a gate (two cells, and three cells wide for the base's gate slot), a corner
               watchtower and a one-shooter lookout post (1 x 2), a floodlight, window and door barricades and a second layer of planks for a barred door (each built
               and damaged), and the rubble of a fallen fence section
    marker     an 'enter' chevron and a 'searched' tick

The style is the yard's (tools/make_building_art.py, whose drawing engine it imports: Art, noise, palette PNGs): seen from above with a slight tilt for
what stands (its south face shows), light from the north west, a dark brown outline, a soft shadow to the south east, flat fills with a gentle gradient;
every picture is drawn at three times the size and brought down to 128 px to the tile (the ground at 64), and saved as an indexed PNG with a short ladder of
alphas for the shadow. Things with a front (furniture, doors, steps) are drawn facing south and turned for the other facings, and their shadow is thrown
again after the turn, so it always falls to the south east. Several pictures of one thing are packed in one PNG (shelf packing); the manifest names each
one's rectangle. It needs Pillow and numpy and reads from the repository: assets/trees and assets/objects (the reused trees and cars).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_building_art as mba            # noqa: E402  (the drawing engine of the yard's props: Art, noise, palette PNGs)
from make_building_art import Art, fbm, mix, shade, OUTLINE, S, PX      # noqa: E402

ROOT = os.path.dirname(HERE)
OUT = os.environ.get("TOWN_ART_OUT") or os.path.join(ROOT, "assets", "town")
MANIFEST = os.environ.get("TOWN_ART_MANIFEST") or os.path.join(ROOT, "assets", "data", "town_art.json")
SHEETS = os.environ.get("TOWN_ART_SHEETS")        # a folder for the contact sheets (one PNG per category)
SEED = 40404
GP = 64                 # pixels to the tile in the ground atlases (4 x 4 pieces of GP)
GA = GP * 4             # the atlas
CATEGORIES = ["street", "house", "roof", "floor", "furniture", "outdoors", "fortify", "marker"]

MAN = {c: [] for c in CATEGORIES}       # the manifest items made in this run, by category
BYTES = {}                              # file -> size


# ------------------------------------------------------------------ files ---

def _path(rel):
    p = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


LEVELS = 16          # steps in the ladder of alphas of a soft shadow (a palette PNG carries a transparency per colour)


def to_pal(im, colours=64, levels=LEVELS):
    """A sprite as an indexed PNG: the opaque pixels get a palette of their own (median cut), everything soft (the shadow, the antialiased edge)
    is a short ladder of alphas of one dark colour. Like mba.to_palette, but with a ladder of 16 instead of 24 to 56 (each entry costs 4 bytes
    in every file)."""
    arr = np.asarray(im.convert("RGBA"))
    a = arr[..., 3]
    rgb = arr[..., :3]
    solid = a >= 250
    dark = (a < 250) & (rgb.max(axis=2) < 52)
    keep = (a < 250) & ~dark & (a >= 100)
    solid = solid | keep
    if not solid.any():
        solid = a >= 1
    if not solid.any():
        solid = np.ones_like(solid)
    flat = rgb[solid].reshape(1, -1, 3)
    q = Image.fromarray(np.ascontiguousarray(flat)).quantize(colors=colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    full = Image.fromarray(np.ascontiguousarray(rgb)).quantize(palette=q, dither=Image.Dither.NONE)
    idx = np.asarray(full).astype(np.int32)
    ncol = min(len(q.getpalette()) // 3, colours)
    pal = list(q.getpalette()[:ncol * 3]) + [12, 9, 6] * levels
    alphas = [255] * ncol + [int(round(255.0 * i / (levels - 1))) for i in range(levels)]
    lev = np.clip(np.round(a.astype(np.float32) / 255.0 * (levels - 1)), 0, levels - 1).astype(np.int32)
    out = np.where(solid, idx, ncol + lev).astype(np.uint8)
    P = Image.fromarray(out)
    P.putpalette(pal + [0] * (768 - len(pal)))
    return P, bytes(alphas)


def to_pal_glass(im, colours=96, levels=LEVELS):
    """The same for a picture whose colour is itself see-through (a stain, glass): the pixels that are not just shadow are clustered with their
    alpha as a fourth channel (octree)."""
    arr = np.asarray(im.convert("RGBA"))
    a = arr[..., 3]
    rgb = arr[..., :3]
    shadow = ((a < 250) & (rgb.max(axis=2) < 52)) | (a < 8)
    work = arr.copy()
    work[shadow] = 0
    q = Image.fromarray(np.ascontiguousarray(work)).quantize(colors=colours, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    raw = q.getpalette("RGBA")
    ncol = min(len(raw) // 4, colours)
    pal, alphas = [], []
    for i in range(ncol):
        pal += raw[4 * i:4 * i + 3]
        alphas.append(raw[4 * i + 3])
    pal += [12, 9, 6] * levels
    alphas += [int(round(255.0 * i / (levels - 1))) for i in range(levels)]
    lev = np.clip(np.round(a.astype(np.float32) / 255.0 * (levels - 1)), 0, levels - 1).astype(np.int32)
    out = np.where(shadow, ncol + lev, np.asarray(q).astype(np.int32)).astype(np.uint8)
    P = Image.fromarray(out)
    P.putpalette(pal + [0] * (768 - len(pal)))
    return P, bytes(alphas)


COLOURS = int(os.environ.get("TOWN_COLOURS", "48"))


def put(rel, im, mode="sprite", colours=None):
    """Write a picture under assets/town as a palette PNG. mode: 'sprite' (opaque pixels plus a ladder of alphas for the shadow), 'glass'
    (a see-through colour needs its own alpha: octree), 'opaque' (a ground piece: no alpha at all), 'rgba' (the full 32 bit file).
    Returns the sprite record for the manifest: the file and the rectangle of it the sprite is."""
    path = _path(rel)
    colours = colours or COLOURS
    im = im.convert("RGBA")
    if mode == "rgba":
        im.save(path, optimize=True)
    elif mode == "opaque":
        q = im.convert("RGB").quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        q.save(path, optimize=True)
    elif mode == "glass":
        P, tr = to_pal_glass(im, max(colours, 96))
        P.save(path, optimize=True, transparency=tr)
    else:
        P, tr = to_pal(im, colours)
        P.save(path, optimize=True, transparency=tr)
    BYTES[rel] = os.path.getsize(path)
    return {"file": rel, "rect": [0, 0, im.width, im.height]}


def put_atlas(rel, cells, mode="sprite", max_w=1024, gap=2):
    """Pack pictures into one PNG (shelf packing, a 2 px gap) and write it; cells: [(picture, meta dict)]. Returns the sprite records:
    meta plus the file and the rectangle [x, y, w, h] of each."""
    x = y = rowh = 0
    placed = []
    for im, meta in cells:
        w, h = im.size
        if x + w > max_w and x > 0:
            x, y, rowh = 0, y + rowh + gap, 0
        placed.append((x, y, im, meta))
        x += w + gap
        rowh = max(rowh, h)
    W = max(px + im.width for px, py, im, m in placed)
    H = max(py + im.height for px, py, im, m in placed)
    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for px, py, im, m in placed:
        sheet.alpha_composite(im.convert("RGBA"), (px, py))
    put(rel, sheet, mode)
    recs = []
    for px, py, im, m in placed:
        r = {"file": rel, "rect": [px, py, im.width, im.height]}
        r.update(m)
        recs.append(r)
    return recs


def rng_for(name, extra=0):
    import zlib
    return np.random.default_rng((zlib.crc32(name.encode()) + SEED * 7919 + extra) & 0xFFFFFFFF)


def add_item(cat, d):
    MAN[cat].append(d)
    return d


# ------------------------------------------------------------------ noise ---

def pnoise(n, sigma, rng, nx=None, sx=None, sy=None):
    """Periodic smooth noise in about -1..1 (a gaussian low pass in Fourier space, so it wraps): a ground atlas made of it
    is seamless however it is repeated. sx, sy stretch the grain along an axis (the boards of a floor)."""
    nx = nx or n
    sx = sigma if sx is None else sx
    sy = sigma if sy is None else sy
    f = np.fft.fft2(rng.standard_normal((n, nx)))
    fy = np.fft.fftfreq(n)[:, None]
    fx = np.fft.fftfreq(nx)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * ((sx ** 2) * (fx ** 2) + (sy ** 2) * (fy ** 2)))
    o = np.real(np.fft.ifft2(f * g))
    return (o / (np.abs(o).max() + 1e-9)).astype(np.float32)


def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo + 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def col3(c):
    return np.array(c, np.float32)[None, None, :]


# ---------------------------------------------------------------- ground ---

class Ground:
    """A ground atlas (GA x GA, 4 x 4 pieces) being painted: float RGB, and masks drawn at 3 times the size for soft edges."""

    SS = 3

    def __init__(self, rgb, n=GA):
        self.n = n
        self.rgb = rgb.astype(np.float32).copy()
        m = 10                                      # decals keep clear of the atlas's outer edge: every variant joins every other
        self.inner = np.zeros((n, n), np.float32)
        self.inner[m:n - m, m:n - m] = 1.0

    def _mk(self):
        im = Image.new("L", (self.n * self.SS, self.n * self.SS), 0)
        return im, ImageDraw.Draw(im)

    def _out(self, im):
        return np.asarray(im.resize((self.n, self.n), Image.BOX), np.float32) / 255.0

    def line(self, pts, w):
        im, d = self._mk()
        k = self.SS
        p = [(x * k, y * k) for x, y in pts]
        d.line(p, fill=255, width=max(1, int(round(w * k))), joint="curve")
        return self._out(im)

    def lines(self, segs, w):
        im, d = self._mk()
        k = self.SS
        for pts in segs:
            d.line([(x * k, y * k) for x, y in pts], fill=255, width=max(1, int(round(w * k))), joint="curve")
        return self._out(im)

    def ellipses(self, items):
        """items: (cx, cy, rx, ry) each."""
        im, d = self._mk()
        k = self.SS
        for cx, cy, rx, ry in items:
            d.ellipse(((cx - rx) * k, (cy - ry) * k, (cx + rx) * k, (cy + ry) * k), fill=255)
        return self._out(im)

    def poly(self, pts):
        im, d = self._mk()
        k = self.SS
        d.polygon([(x * k, y * k) for x, y in pts], fill=255)
        return self._out(im)

    def sprinkle(self, shapes, wrap=True):
        """Many small ellipses with their own colours and alphas at once: shapes of (cx, cy, rx, ry, (r, g, b), alpha). They wrap
        round the atlas's edge (the grain of a ground must not stop at the seam)."""
        n, k = self.n, self.SS
        im = Image.new("RGBA", (n * k, n * k), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        for cx, cy, rx, ry, c, al in shapes:
            shifts = [(0, 0)]
            if wrap:
                sx = [0] + ([n] if cx - rx < 0 else []) + ([-n] if cx + rx > n else [])
                sy = [0] + ([n] if cy - ry < 0 else []) + ([-n] if cy + ry > n else [])
                shifts = [(a, b) for a in sx for b in sy]
            for ox, oy in shifts:
                d.ellipse(((cx + ox - rx) * k, (cy + oy - ry) * k, (cx + ox + rx) * k, (cy + oy + ry) * k), fill=tuple(int(v) for v in c) + (int(al * 255),))
        small = np.asarray(im.resize((n, n), Image.BOX), np.float32)
        a = (small[..., 3] / 255.0)[..., None]
        rgb = small[..., :3]            # (Pillow resizes an RGBA picture premultiplied: the colour is already the straight one)
        self.rgb = self.rgb * (1 - a) + rgb * a

    def strokes(self, segs, w, colour, op=1.0, wrap=True):
        """Many short strokes of one colour (grass blades, grain): each seg a ((x0, y0), (x1, y1))."""
        n, k = self.n, self.SS
        im = Image.new("L", (n * k, n * k), 0)
        d = ImageDraw.Draw(im)
        for (x0, y0), (x1, y1) in segs:
            sx = [0] + ([n] if min(x0, x1) < 3 else []) + ([-n] if max(x0, x1) > n - 3 else [])
            sy = [0] + ([n] if min(y0, y1) < 3 else []) + ([-n] if max(y0, y1) > n - 3 else [])
            for ox in sx:
                for oy in sy:
                    d.line([((x0 + ox) * k, (y0 + oy) * k), ((x1 + ox) * k, (y1 + oy) * k)], fill=255, width=max(1, int(round(w * k))))
        m = self._out(im)
        self.lay(m, colour, op, keep_inner=False)

    def lay(self, m, colour, op=1.0, keep_inner=True):
        if keep_inner:
            m = m * self.inner
        a = (m * op)[..., None]
        c = colour if isinstance(colour, np.ndarray) and colour.ndim == 3 else col3(colour)
        self.rgb = self.rgb * (1 - a) + c * a

    def shift(self, m, dx, dy):
        return np.roll(np.roll(m, dy, 0), dx, 1)

    def crack(self, pts, w=1.5, dark=(26, 28, 32), op=0.8, hi=(150, 152, 156), hiop=0.22):
        m = self.line(pts, w)
        self.lay(self.shift(m, 1, 1), hi, hiop)
        self.lay(m, dark, op)


def crack_walk(rng, start, ang, length, step=5.0, jit=0.45):
    x, y = start
    pts = [(x, y)]
    for _ in range(max(2, int(length / step))):
        ang += rng.normal(0, jit)
        x += np.cos(ang) * step
        y += np.sin(ang) * step
        pts.append((x, y))
    return pts


def crack_tree(rng, g, start, ang, length, w=1.5, depth=2, **kw):
    pts = crack_walk(rng, start, ang, length)
    g.crack(pts, w, **kw)
    if depth > 0:
        for i in range(2, len(pts) - 1, 3):
            if rng.random() < 0.55:
                side = 1 if rng.random() < 0.5 else -1
                crack_tree(rng, g, pts[i], ang + side * rng.uniform(0.6, 1.1), length * rng.uniform(0.25, 0.5), w * 0.7, depth - 1, **kw)


def blotch(g, rng, cx, cy, r, colour, op, sigma=3.0):
    """A soft irregular stain: a noisy disc."""
    n = g.n
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / r
    nz = pnoise(n, 5.0, rng)
    m = smooth(1.0 - d + 0.35 * nz, 0.0, 0.5)
    g.lay(m, colour, op)


def finish_ground(rgb, name, grain=0.0, rng=None):
    """The atlas as an opaque PNG."""
    if grain and rng is not None:
        rgb = rgb * (1 + grain * rng.standard_normal(rgb.shape[:2]).astype(np.float32)[..., None])
    im = Image.fromarray(np.clip(rgb, 0, 255).round().astype(np.uint8))
    return im


def ground_item(cat, id, tags, files_by_variant, note, bg=None):
    sprites = []
    for i, (rel, im) in enumerate(files_by_variant):
        rec = put(rel, im, "opaque")
        rec["variant"] = i
        sprites.append(rec)
    d = {"id": id, "category": cat, "kind": "ground_atlas", "layer": "ground", "footprint": [1, 1], "anchor": [0, 0],
         "grid": [4, 4], "piece_px": GP, "variants": len(sprites), "tags": ["walkable"] + list(tags), "sprites": sprites, "note": note}
    if bg:
        d["_bg"] = bg
    return add_item(cat, d)


# --------------------------------------------------------------- sprites ---

GRAIN = float(os.environ.get("TOWN_GRAIN", "0.005"))
PAD = (0.0625, 0.0625, 0.1875, 0.1875)      # left, top, right, bottom padding of a prop's picture: the soft shadow lives there
FACING = {0: "s", 1: "w", 2: "n", 3: "e"}   # a prop is drawn facing south (front to the bottom, back to the wall at the top);
#                                             quarter turns clockwise make it face west, north and east


def finish_prop(a, k=0, pad=PAD, shadow=(0.05, 0.065, 0.032, 0.42), grain=GRAIN, seed=1):
    """Turn a drawn body k quarter turns clockwise, pad it, throw its soft shadow to the south east, and give back
    (picture, footprint (w, h) after the turn, anchor (the footprint's top left inside the picture, in tiles))."""
    w, h = a.w, a.h
    prem, al = a.prem, a.alpha
    if k % 4:
        prem = np.ascontiguousarray(np.rot90(prem, -k, axes=(0, 1)))
        al = np.ascontiguousarray(np.rot90(al, -k, axes=(0, 1)))
        if k % 2:
            w, h = h, w
    pl, pt, pr, pb = pad
    b = Art(w + pl + pr, h + pt + pb)
    oy, ox = int(round(pt * S)), int(round(pl * S))
    hh, ww = al.shape
    b.prem[oy:oy + hh, ox:ox + ww] = prem
    b.alpha[oy:oy + hh, ox:ox + ww] = al
    if shadow:
        sil = b.alpha.copy()
        b.shadow_under(shadow[0], shadow[1], shadow[2], shadow[3], mask_of=sil)
    return b.image(grain=grain, seed=seed), (w, h), (pl, pt)


def body(w, h):
    return Art(w, h)


def rrect(x0, y0, x1, y1, r, n=5):
    """The points of a rounded rectangle."""
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for i in range(n + 1):
            t = np.radians(a0 + 90.0 * i / n)
            pts.append((cx + r * np.cos(t), cy + r * np.sin(t)))
    return pts


NOISE = float(os.environ.get("TOWN_NOISE", "0.6"))
FREQ_MAX = float(os.environ.get("TOWN_FREQ", "7.0"))


def lit(base, lo=0.84, hi=1.14, x0=0.0, y0=0.0, x1=1.0, y1=1.0, noise=0.0, seed=1, freq=14.0, along=None):
    """A colour function for a flat top lit from the top left: `hi` times the colour at the top left corner of the box,
    `lo` times at the bottom right, with a little noise."""
    b = np.array(base, np.float32)
    noise = noise * NOISE
    freq = min(freq, FREQ_MAX)

    def f(X, Y):
        t = ((X - x0) / max(x1 - x0, 1e-6) + (Y - y0) / max(y1 - y0, 1e-6)) / 2.0
        k = hi + (lo - hi) * np.clip(t, 0, 1)
        if noise:
            if along == "x":
                n = fbm(X, Y, freq, seed, 2, fx=0.12, fy=1.0)
            elif along == "y":
                n = fbm(X, Y, freq, seed, 2, fx=1.0, fy=0.12)
            else:
                n = fbm(X, Y, freq, seed, 2)
            k = k * (1 - noise / 2 + noise * n)
        return b[None, None, :] * k[..., None]
    return f


def slab(a, x0, y0, x1, y1, base, r=0.04, lw=0.028, lo=0.84, hi=1.12, noise=0.0, seed=1, rim=True, freq=14.0, along=None, outline=OUTLINE):
    """A box seen from above: rounded, lit from the top left, outlined, with a light rim on its top and left and a dark one on
    its bottom and right. Returns the mask."""
    pts = rrect(x0, y0, x1, y1, r)
    m = a.poly(pts)
    a.paint(m, lit(base, lo, hi, x0, y0, x1, y1, noise, seed, freq, along))
    if rim:
        ins = lw * 0.9 + 0.012
        a.paint(a.stroke([(x0 + ins, y1 - ins - r), (x0 + ins, y0 + ins + r * 0.3), (x0 + ins + r * 0.3, y0 + ins), (x1 - ins - r, y0 + ins)], 0.012, round_ends=False), (255, 250, 235), 0.28, clip=m)
        a.paint(a.stroke([(x0 + ins + r, y1 - ins), (x1 - ins, y1 - ins), (x1 - ins, y0 + ins + r)], 0.012, round_ends=False), (10, 8, 6), 0.22, clip=m)
    if lw > 0:
        a.paint(a.stroke(pts, lw, closed=True), outline, 1.0)
    return m


def disc(a, cx, cy, r, base, lw=0.026, lo=0.80, hi=1.15, outline=OUTLINE):
    """A round thing seen from above, lit from the top left."""
    a.paint(a.ellipse(cx, cy, r + lw / 2), outline, 1.0)

    def f(X, Y):
        t = np.clip(((X - (cx - r)) + (Y - (cy - r))) / (4 * r), 0, 1)
        k = hi + (lo - hi) * t
        return np.array(base, np.float32)[None, None, :] * k[..., None]
    a.paint(a.ellipse(cx, cy, r - lw / 2), f)


def dot(a, x, y, r, colour, op=1.0):
    a.paint(a.ellipse(x, y, r), colour, op)


def line(a, pts, w, colour, op=1.0, round_ends=True):
    a.paint(a.stroke(pts, w, round_ends=round_ends), colour, op)


def nail(a, x, y, r=0.012):
    a.paint(a.ellipse(x, y, r), (36, 30, 26), 0.9)
    a.paint(a.ellipse(x - r * 0.3, y - r * 0.3, r * 0.4), (190, 180, 160), 0.7)


def prop(cat, id, w, h, draw, facings=4, states=None, variants=1, tags=(), layer="object", solid="all", note="", pad=PAD,
         shadow=(0.05, 0.065, 0.032, 0.42), folder=None, mode="sprite", bg=None, grain=None, anchor_extra=(0.0, 0.0), variant_names=None, sort_y=None):
    """Draw a prop: one picture per facing (4 by default: s, w, n, e), per state and per variant, all packed into ONE png,
    <folder>/<id>.png, and described by one manifest item whose sprites each name their rectangle.
    draw(state, variant) returns an Art of w x h tiles with the body drawn facing south."""
    folder = folder or cat
    hv = facings == "hv"                 # a thing with two looks, along x ('h') and along y ('v')
    if hv:
        facings = 2
    nf = facings if isinstance(facings, int) else len(facings)
    facing_ks = list(range(nf)) if nf == 4 else ([0, 1] if (nf == 2 and hv) else ([0, 2] if nf == 2 else [0]))
    if isinstance(facings, (list, tuple)):
        facing_ks = list(facings)
    names = {0: "h", 1: "v"} if hv else FACING
    states_l = list(states) if states else [None]
    cells = []
    anchor = None
    for v in range(variants):
        for st in states_l:
            for k in facing_ks:
                a = draw(st, v)
                im, fp, anchor = finish_prop(a, k, pad, shadow, GRAIN if grain is None else grain, seed=1 + v * 7 + k)
                meta = {"fp": ([w, h] if k % 2 == 0 else [h, w]) if anchor_extra != (0.0, 0.0) else [round(fp[0], 3), round(fp[1], 3)]}
                if nf > 1:
                    meta["orient" if hv else "facing"] = names[k]
                if st:
                    meta["state"] = st
                if variants > 1:
                    meta["variant"] = v
                cells.append((im, meta))
    sprites = put_atlas("%s/%s.png" % (folder, id), cells, mode)
    d = {"id": id, "category": cat, "kind": "prop", "layer": layer, "footprint": [w, h], "anchor": [round(anchor[0] + anchor_extra[0], 4), round(anchor[1] + anchor_extra[1], 4)],
         "tags": list(tags), "solid": solid, "sprites": sprites}
    if variant_names:
        d["variant_names"] = list(variant_names)
    if sort_y is not None:
        d["sort_y"] = sort_y
    if nf > 1:
        d["orients" if hv else "facings"] = [names[k] for k in facing_ks]
    if states:
        d["states"] = list(states)
    if variants > 1:
        d["variants"] = variants
    if note:
        d["note"] = note
    if bg:
        d["_bg"] = bg
    return add_item(cat, d)


def atlas_item(cat, id, im, cols, rows, cells, cell_px, tags, layer, note, mode="glass", anchor=(0, 0), footprint=(1, 1), extra=None, bg=None, folder=None):
    """A picture holding a grid of cells (an autotile set or a set of overlays). cells: name -> [col, row]."""
    rec = put("%s/%s.png" % (folder or cat, id), im, mode)
    d = {"id": id, "category": cat, "kind": "atlas", "layer": layer, "footprint": list(footprint), "anchor": list(anchor),
         "grid": [cols, rows], "cell_px": list(cell_px), "cells": cells, "tags": list(tags), "sprites": [rec], "note": note}
    if extra:
        d.update(extra)
    if bg:
        d["_bg"] = bg
    return add_item(cat, d)


def sheet_cells(cols, rows, cw, ch):
    return Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))


# --------------------------------------------------------------- manifest ---

def write_manifest(only):
    old = {}
    if os.path.exists(MANIFEST):
        try:
            import json
            old = json.load(open(MANIFEST))
        except Exception:
            old = {}
    import json
    items = []
    keep = {}
    for it in old.get("items", []):
        keep.setdefault(it.get("category"), []).append(it)
    for c in CATEGORIES:
        if c in only or c not in keep:
            src = MAN[c]
        else:
            src = keep[c]
        for it in src:
            items.append({k: v for k, v in it.items() if not k.startswith("_")})
    doc = {"_doc": DOC, "version": 1, "tile_px": PX, "ground_piece_px": GP, "light": "top left (shadows fall to the south east)",
           "outline": "#%02x%02x%02x" % OUTLINE, "items": items}
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(doc, f, indent=1)
    return doc


DOC = {
    "overview": "The art kit of the town (tools/make_town_art.py draws it; assets/town holds the pictures). Everything is seen from above, lit from the top left "
                "(soft shadows fall to the south east), dark brown outline (#221a13), muted colours: the look of the yard's own art. `items` lists every "
                "piece; each has an id, a category, a footprint in tiles and its sprites. Tiles: the pictures are drawn at `tile_px` = 128 px to the tile "
                "(the game's TILE is 64 px, so draw a picture at 64 / 128 = 0.5 scale); the ground and the floors are 4 x 4 atlases of `ground_piece_px` = 64 px "
                "pieces (one piece to the tile, 64 px: draw them at scale 1; the tile at (x, y) shows piece (x % 4, y % 4), as assets/terrain does, but with "
                "64 px pieces instead of 128: world.gd `_build_ground` must use texture width / 4 for its piece size).",
    "item": {
        "id": "unique name",
        "category": "street | house | roof | floor | furniture | outdoors | fortify | marker",
        "kind": "ground_atlas (a ground or floor: grid [4, 4] of piece_px pieces) | atlas (a grid of cells in one picture: `cells` maps a name to [col, row], `cell_px` is the "
                "cell's size; an autotile set keys its cells by neighbour mask) | wall_fill / roof_fill (seamless 128 px tiles, with `edges` naming their autotile overlay) | "
                "prop (one or more pictures of one thing, packed in one PNG; see `sprites`) | overlay",
        "layer": "ground (the terrain: under everything) | decal (flat things on the ground or floor: paint, rugs, stains, steps; under the people) | object "
                 "(things that stand: furniture, trees, cars; depth-sorted with the people on the footprint's bottom edge, or `sort_y`) | wall (wall cells and what is set into "
                 "them: doors, windows, barricades) | roof (hidden when the avatar is inside)",
        "footprint": "[w, h] in tiles for the default facing (s). The cells the thing covers; w and h swap for facing e and w (each sprite has its own `fp`).",
        "anchor": "[ax, ay] in tiles: where the footprint's top left corner lies inside the picture (the picture has a soft shadow and sometimes a roof or crown "
                  "outside the footprint). To put a thing on cell (cx, cy): its picture's top left goes to (cx - ax, cy - ay) tiles. Same for every facing.",
        "sort_y": "(optional) tiles from the picture's top to the line the thing is depth-sorted on (default: anchor y + footprint h)",
        "solid": "\"all\" (every footprint cell blocks walking and the dead) | [] (walkable) | [[x, y], ...] (cells that block) | {state: bool} (by state, e.g. a door: closed true, "
                 "open false)",
        "tags": "container (can be searched: it has a `closed` and an `opened` state) | solid | walkable | door | window | opening | roof | hideable | wall | autotile | "
                "fence | gate | fortify | marker | decal | clutter | base (the base's radio and stash) | reused (made from the yard's existing pictures) | ...",
        "states": "(optional) e.g. [closed, opened] (a container: opened = searched), [closed, open, broken] (a door), [intact, broken, boarded] (a window)",
        "facings": "(optional) [s, w, n, e]: the way the front faces. s: the back is to the north wall, the front to the south; turn clockwise for w, n, e. A door's facing is the "
                   "side the OUTSIDE is on. `orients` [h, v] instead: along x or along y.",
        "variants": "(optional) how many looks (a colour, a book shelf's books). Every variant has the same states and facings. `variant_names` names them where it matters "
                    "([built, damaged] for the fortification pieces).",
        "sprites": "[{file, rect: [x, y, w, h] (pixels inside the PNG), facing | orient, state, variant, slope, fp: [w, h] (footprint of this sprite)}...]: pick the sprite whose "
                   "fields match what you want and draw its rect. A key an item has no use for is absent.",
        "note": "what it is, and anything particular to place it right",
    },
    "autotiles": "Walls, roofs, fences, hedges, sandbags, the kerb and the wall shadows come as `atlas` items whose cells are chosen by a 4 bit mask of the neighbours "
                 "(N 1, E 2, S 4, W 8; col = mask % 4, row = mask // 4). Walls and roof edges use the mask of the OPEN sides (the neighbour is not a wall / not roof); "
                 "fences, hedges and sandbags use the mask of the CONNECTED sides (the neighbour is the same kind of line).",
    "recipes": {
        "wall": "for each wall cell draw wall_<material> (variant a, b for one cell in six) then wall_edges cell [mask of open sides] over it. A door cell is not a wall for the "
                "mask; a window cell is. On every non wall cell next to a wall draw wall_shadows (n: wall to the north, w: to the west, nw: both, diag_nw: only the corner). "
                "Doors replace the wall cell; windows and barricades are laid over it.",
        "roof": "give a rectangle of roof cells: the ridge runs along the longer side; the half to the north (or west) uses the `lit` fill, the other the `shade` fill (turn the "
                "pictures a quarter turn counter clockwise for a ridge along y); lay the ridge strip along the middle line; lay roof_edge_<material> cell [mask of open sides] over "
                "every cell (it overhangs 0.2 tile and throws its shadow). Hide all roof layer pieces while the avatar is inside that building.",
        "street": "asphalt cells (three variants in blocks), lane_markings cells over them, sidewalk cells with kerb cells over them where road touches, lawn / dirt_path / gravel "
                  "for yards and drives, leaves / manhole / drain as decals; lawn_edge on the lawn cells that touch paving or a wall and lawn_patch here and there on the lawn (soft transitions "
                  "and no seen repeat); streetlamp and hydrant on the sidewalks. scripts/town/town_world.gd and town_chunk_paint.gd draw all of this.",
        "container": "a container has states closed / opened: draw closed until searched, then opened; the `marker_searched` tick can float over it.",
    },
}


# ---------------------------------------------------------- contact sheet ---

def contact(cat, name=None, cols_px=1800, scale=1.0, bg=(118, 116, 110), facings=None, ids=None):
    """A contact sheet of a category's pictures (what is in MAN, or in the manifest when the category was not made in this run); facings:
    only the sprites facing these ways (and those with no facing); ids: only these items."""
    if not SHEETS:
        return
    import json
    os.makedirs(SHEETS, exist_ok=True)
    items = MAN[cat]
    if not items and os.path.exists(MANIFEST):
        items = [i for i in json.load(open(MANIFEST))["items"] if i["category"] == cat]
    cache = {}
    tiles = []
    for it in items:
        if ids and it["id"] not in ids:
            continue
        ibg = it.get("_bg", bg)
        for sp in it["sprites"]:
            if facings is not None and sp.get("facing") is not None and sp["facing"] not in facings:
                continue
            if sp["file"] not in cache:
                cache[sp["file"]] = Image.open(os.path.join(OUT, sp["file"])).convert("RGBA")
            x0, y0, w, h = sp["rect"]
            im = cache[sp["file"]].crop((x0, y0, x0 + w, y0 + h))
            label = it["id"] + "".join("_" + str(sp[k]) for k in ("variant", "facing", "orient", "state", "slope") if k in sp)
            tiles.append((label, im, ibg))
    x, y, rowh = 6, 6, 0
    placed = []
    for label, im, ibg in tiles:
        if scale != 1.0:
            im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
        w, h = im.width + 6, im.height + 16
        if x + w > cols_px:
            x = 6
            y += rowh + 6
            rowh = 0
        placed.append((x, y, label, im, ibg))
        x += w + 4
        rowh = max(rowh, h)
    H = y + rowh + 12
    sheet = Image.new("RGB", (cols_px, H), (96, 94, 90))
    d = ImageDraw.Draw(sheet)
    for x, y, label, im, ibg in placed:
        sheet.paste(Image.new("RGB", (im.width + 6, im.height + 16), ibg), (x - 3, y - 1))
        sheet.paste(im.convert("RGB"), (x, y + 12), im.getchannel("A"))
        d.text((x, y), label[:30], fill=(250, 250, 250))
    p = os.path.join(SHEETS, "%s.png" % (name or cat))
    sheet.save(p)
    print("sheet", p, sheet.size)


# ======================================================================
# (the categories follow: street, house, roof, floor, furniture, outdoors, fortify, marker)
# ======================================================================

# ======================================================================
# STREET: ground atlases, lane paint, kerbs, leaves, manholes, drains
# ======================================================================

ASPHALT = (67, 70, 74)       # the colours of the yard's own ground (assets/terrain), kept, so that the town sits beside it
SIDEWALK = (151, 147, 138)


def asphalt_base():
    rng = rng_for("asphalt_base")
    n1, n2, n3 = pnoise(GA, 40, rng), pnoise(GA, 9, rng), pnoise(GA, 1.6, rng)
    k = 1 + 0.040 * n1 + 0.030 * n2 + 0.028 * n3
    rgb = col3(ASPHALT) * k[..., None]
    rgb = rgb + pnoise(GA, 55, rng)[..., None] * np.array([-1.5, 0.0, 2.0], np.float32)
    sp = rng.random((GA, GA))
    rgb[sp < 0.035] += 15
    rgb[sp > 0.972] -= 10
    return rgb


def asphalt(variant):
    rng = rng_for("asphalt", variant)
    g = Ground(asphalt_base())
    spec = [dict(cracks=2, depth=1, stains=3, patches=0, hole=0), dict(cracks=5, depth=2, stains=2, patches=0, hole=1),
            dict(cracks=3, depth=1, stains=2, patches=2, hole=0)][variant]
    # repair patches first (the cracks run over them): a rectangle of newer, darker tar with a sealed edge
    for _ in range(spec["patches"]):
        w, h = rng.uniform(34, 62), rng.uniform(18, 32)
        cx, cy = rng.uniform(40, GA - 40), rng.uniform(40, GA - 40)
        pts = [(cx - w / 2 + rng.normal(0, 1.2), cy - h / 2 + rng.normal(0, 1.2)), (cx + w / 2 + rng.normal(0, 1.2), cy - h / 2 + rng.normal(0, 1.2)),
               (cx + w / 2 + rng.normal(0, 1.2), cy + h / 2 + rng.normal(0, 1.2)), (cx - w / 2 + rng.normal(0, 1.2), cy + h / 2 + rng.normal(0, 1.2))]
        m = g.poly(pts)
        tone = rng.uniform(0.80, 0.88)
        g.lay(m, g.rgb * tone + 0, 1.0)
        edge = g.line(pts + [pts[0]], 1.3)
        g.lay(g.shift(edge, 1, 1), (120, 122, 126), 0.20)
        g.lay(edge, (30, 32, 36), 0.55)
    for _ in range(spec["stains"]):
        blotch(g, rng, rng.uniform(30, GA - 30), rng.uniform(30, GA - 30), rng.uniform(9, 17), (36, 38, 42), rng.uniform(0.35, 0.55))
    for _ in range(spec["cracks"]):
        crack_tree(rng, g, (rng.uniform(30, GA - 30), rng.uniform(30, GA - 30)), rng.uniform(0, 6.28), rng.uniform(50, 95), 1.5, spec["depth"])
    for _ in range(spec["hole"]):
        cx, cy = rng.uniform(60, GA - 60), rng.uniform(60, GA - 60)
        blotch(g, rng, cx, cy, 8.5, (28, 29, 32), 0.9)
        for a in rng.uniform(0, 6.28, 4):
            g.crack([(cx, cy), (cx + np.cos(a) * 14, cy + np.sin(a) * 14)], 1.2)
    # a few small stones and chips, here and there (the same sort of grain in every variant, so any two meet without a seam)
    return finish_ground(g.rgb, "asphalt", 0.0)


def sidewalk(variant):
    rng = rng_for("sidewalk_base")
    n1, n2, n3 = pnoise(GA, 30, rng), pnoise(GA, 7, rng), pnoise(GA, 1.4, rng)
    rgb = col3(SIDEWALK) * (1 + 0.022 * n1 + 0.020 * n2 + 0.022 * n3)[..., None]
    rng = rng_for("sidewalk", variant)
    tone = 1 + rng.uniform(-0.035, 0.035, (4, 4))
    for j in range(4):
        for i in range(4):
            rgb[j * GP:(j + 1) * GP, i * GP:(i + 1) * GP] *= tone[j, i]
    g = Ground(rgb)
    # the joints: a dark line on every slab edge (it straddles the atlas's edge, so the repeat is seamless), a light lip on its far side
    jm = np.zeros((GA, GA), np.float32)
    lip = np.zeros((GA, GA), np.float32)
    for i in range(4):
        x = i * GP
        jm[:, (x - 1) % GA] = 1
        jm[:, x % GA] = 1
        lip[:, (x + 1) % GA] = 1
        jm[(x - 1) % GA, :] = 1
        jm[x % GA, :] = 1
        lip[(x + 1) % GA, :] = 1
    dirt = 0.55 + 0.35 * pnoise(GA, 6, rng_for("sidewalk_joint"))
    g.lay(lip, (200, 196, 186), 0.30, keep_inner=False)
    g.lay(jm, (84, 80, 72), 0.78 * dirt, keep_inner=False)
    spec = [dict(cracks=1, tufts=14, stains=3), dict(cracks=3, tufts=22, stains=2), dict(cracks=2, tufts=30, stains=4)][variant]
    # cracks inside slabs
    for _ in range(spec["cracks"]):
        si, sj = rng.integers(0, 4, 2)
        sx, sy = (si + rng.uniform(0.25, 0.75)) * GP, (sj + rng.uniform(0.25, 0.75)) * GP
        crack_tree(rng, g, (sx, sy), rng.uniform(0, 6.28), rng.uniform(22, 40), 1.2, 1, dark=(70, 66, 60), op=0.75, hi=(200, 196, 186), hiop=0.3)
    for _ in range(spec["stains"]):
        blotch(g, rng, rng.uniform(20, GA - 20), rng.uniform(20, GA - 20), rng.uniform(5, 11), (96, 92, 86), rng.uniform(0.25, 0.45))
    # grass and dirt in the joints and at the slab corners
    blades, soil = [], []
    for _ in range(spec["tufts"]):
        if rng.random() < 0.5:                      # a corner
            px_, py_ = rng.integers(1, 4) * GP + rng.uniform(-2, 2), rng.integers(1, 4) * GP + rng.uniform(-2, 2)
        else:
            if rng.random() < 0.5:
                px_, py_ = rng.integers(1, 4) * GP + rng.uniform(-1, 1), rng.uniform(14, GA - 14)
            else:
                px_, py_ = rng.uniform(14, GA - 14), rng.integers(1, 4) * GP + rng.uniform(-1, 1)
        soil.append((px_, py_, rng.uniform(2.5, 4.5), rng.uniform(2.0, 3.5), (92, 80, 62), 0.55))
        for _b in range(rng.integers(4, 8)):
            a = -np.pi / 2 + rng.normal(0, 0.6)
            ln = rng.uniform(3.0, 6.5)
            blades.append(((px_ + rng.normal(0, 1.4), py_ + rng.normal(0, 1.0)), (px_ + np.cos(a) * ln, py_ + np.sin(a) * ln)))
    g.sprinkle(soil, wrap=False)
    half = len(blades) // 2
    g.strokes(blades[:half], 1.2, (74, 104, 44), 0.95)
    g.strokes(blades[half:], 1.2, (110, 140, 62), 0.95)
    return finish_ground(g.rgb, "sidewalk", 0.0)


def lawn_base():
    rng = rng_for("lawn_base")
    n1, n2, n3 = pnoise(GA, 30, rng), pnoise(GA, 8, rng), pnoise(GA, 2, rng)
    dry = smooth(n1 + 0.45 * n2, 0.12, 0.60)[..., None]
    rgb = col3((78, 108, 48)) * (1 - dry) + col3((124, 126, 60)) * dry
    rgb = rgb * (1 + 0.05 * n2 + 0.045 * n3)[..., None]
    return rgb, dry[..., 0]


def lawn(variant):
    rng = rng_for("lawn", variant)
    rgb, dry = lawn_base()
    g = Ground(rgb)
    # blades: three short-stroke layers
    for colour, op, count in (((60, 90, 36), 0.50, 900), ((118, 148, 66), 0.45, 700), ((150, 146, 82), 0.40, 450)):
        segs = []
        for _ in range(count):
            x, y = rng.uniform(0, GA), rng.uniform(0, GA)
            if colour[0] > 140 and rng.random() > 0.15 + dry[int(y) % GA, int(x) % GA]:
                continue
            a = -np.pi / 2 + rng.normal(0, 0.7)
            ln = rng.uniform(2.5, 5.0)
            segs.append(((x, y), (x + np.cos(a) * ln, y + np.sin(a) * ln)))
        g.strokes(segs, 1.1, colour, op)
    if variant == 1:        # clover and daisies
        shapes = []
        for _ in range(26):
            cx, cy = rng.uniform(16, GA - 16), rng.uniform(16, GA - 16)
            for _k in range(rng.integers(3, 6)):
                shapes.append((cx + rng.normal(0, 3), cy + rng.normal(0, 3), 2.2, 1.9, (96, 134, 62), 0.85))
        for _ in range(14):
            cx, cy = rng.uniform(16, GA - 16), rng.uniform(16, GA - 16)
            shapes.append((cx, cy, 1.9, 1.7, (238, 236, 222), 0.95))
            shapes.append((cx, cy, 0.8, 0.8, (226, 188, 70), 1.0))
        g.sprinkle(shapes, wrap=False)
    if variant == 2:        # worn bare earth and long clumps
        for _ in range(3):
            cx, cy = rng.uniform(30, GA - 30), rng.uniform(30, GA - 30)
            blotch(g, rng, cx, cy, rng.uniform(9, 15), (112, 92, 64), 0.85)
            g.sprinkle([(cx + rng.normal(0, 5), cy + rng.normal(0, 5), 1.1, 0.9, (150, 132, 104), 0.9) for _ in range(14)], wrap=False)
        segs = []
        for _ in range(26):
            cx, cy = rng.uniform(14, GA - 14), rng.uniform(14, GA - 14)
            for _b in range(7):
                a = -np.pi / 2 + rng.normal(0, 0.8)
                ln = rng.uniform(5, 9)
                segs.append(((cx + rng.normal(0, 1.5), cy), (cx + np.cos(a) * ln, cy + np.sin(a) * ln)))
        g.strokes(segs[:len(segs) // 2], 1.4, (52, 80, 32), 0.7)
        g.strokes(segs[len(segs) // 2:], 1.4, (104, 134, 58), 0.65)
    return finish_ground(g.rgb, "lawn", 0.0)


def dirt(variant):
    rng_b = rng_for("dirt_base")
    n1, n2, n3 = pnoise(GA, 28, rng_b), pnoise(GA, 6, rng_b), pnoise(GA, 1.5, rng_b)
    rgb = col3((118, 97, 73)) * (1 + 0.06 * n1 + 0.05 * n2 + 0.04 * n3)[..., None]
    rng = rng_for("dirt", variant)
    g = Ground(rgb)
    shapes = []
    for _ in range(170 if variant == 0 else 120):
        x, y = rng.uniform(0, GA), rng.uniform(0, GA)
        r = rng.uniform(0.8, 2.2)
        c = (156, 138, 112) if rng.random() < 0.6 else (88, 70, 52)
        shapes.append((x + 0.8, y + 0.8, r, r * 0.8, (60, 46, 34), 0.5))
        shapes.append((x, y, r, r * 0.85, c, 0.9))
    g.sprinkle(shapes)
    if variant == 1:        # damp, trodden
        for _ in range(3):
            blotch(g, rng, rng.uniform(30, GA - 30), rng.uniform(30, GA - 30), rng.uniform(12, 20), (84, 66, 48), 0.55)
        for _ in range(5):
            x, y = rng.uniform(30, GA - 30), rng.uniform(30, GA - 30)
            g.lay(g.line([(x, y), (x + rng.uniform(-18, 18), y + rng.uniform(-6, 6))], 2.4), (90, 72, 54), 0.35)
    segs = []
    for _ in range(5 + 4 * variant):
        cx, cy = rng.uniform(16, GA - 16), rng.uniform(16, GA - 16)
        for _b in range(6):
            a = -np.pi / 2 + rng.normal(0, 0.7)
            ln = rng.uniform(3.5, 6.5)
            segs.append(((cx + rng.normal(0, 1.2), cy), (cx + np.cos(a) * ln, cy + np.sin(a) * ln)))
    g.strokes(segs, 1.2, (92, 112, 56), 0.9)
    return finish_ground(g.rgb, "dirt", 0.0)


def gravel(variant):
    rng_b = rng_for("gravel_base")
    n1 = pnoise(GA, 20, rng_b)
    base = (112, 106, 98) if variant == 0 else (128, 112, 92)
    rgb = col3(base) * (1 + 0.05 * n1)[..., None]
    rng = rng_for("gravel", variant)
    g = Ground(rgb)
    shapes = []
    tones = [(168, 160, 148), (146, 140, 130), (190, 182, 168), (122, 116, 108)] if variant == 0 else [(176, 156, 126), (150, 130, 104), (196, 176, 146), (128, 112, 90)]
    for _ in range(2300):
        x, y = rng.uniform(0, GA), rng.uniform(0, GA)
        r = rng.uniform(1.1, 2.5)
        c = tones[rng.integers(0, 4)]
        c = tuple(np.clip(np.array(c) + rng.normal(0, 7), 0, 255))
        shapes.append((x + 0.9, y + 0.9, r, r * 0.85, (44, 40, 34), 0.55))
        shapes.append((x, y, r, r * rng.uniform(0.7, 0.95), c, 1.0))
        shapes.append((x - r * 0.25, y - r * 0.3, r * 0.45, r * 0.35, (236, 230, 216), 0.35))
    g.sprinkle(shapes)
    if variant == 1:        # weeds up through it and two shallow tyre lines of finer dust
        segs = []
        for _ in range(9):
            cx, cy = rng.uniform(16, GA - 16), rng.uniform(16, GA - 16)
            for _b in range(6):
                a = -np.pi / 2 + rng.normal(0, 0.7)
                ln = rng.uniform(4, 7)
                segs.append(((cx + rng.normal(0, 1.2), cy), (cx + np.cos(a) * ln, cy + np.sin(a) * ln)))
        g.strokes(segs, 1.3, (88, 114, 54), 0.9)
    return finish_ground(g.rgb, "gravel", 0.0)


def wear_mask(w, h, seed, amount=0.45, freq=7.0):
    """An 'L' picture (the size of an Art w x h) that is 255 where paint is whole and less where it has worn or chipped away."""
    Wp, Hp = int(round(w * S)), int(round(h * S))
    ys, xs = np.mgrid[0:Hp, 0:Wp].astype(np.float32)
    X, Y = xs / S, ys / S
    n = fbm(X, Y, freq, seed, 3)
    chips = fbm(X, Y, freq * 5.0, seed + 5, 2)
    a = 1.0 - amount * smooth(n, 0.45, 0.8) - 0.5 * amount * smooth(chips, 0.62, 0.8)
    return Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))


WHITE_PAINT = (228, 226, 214)
YELLOW_PAINT = (224, 188, 76)


def street_markings():
    """Lane paint on 1 x 1 cells, 4 x 3: dash, double centre line, edge line (on the side named), crosswalk bar, stop line."""
    cells = {}
    sheet = sheet_cells(4, 3, PX, PX)
    specs = [
        ("dash_h", lambda a: a.rect(0.25, 0.44, 0.75, 0.56), WHITE_PAINT),
        ("dash_v", lambda a: a.rect(0.44, 0.25, 0.56, 0.75), WHITE_PAINT),
        ("double_h", lambda a: a.either(a.rect(0.0, 0.38, 1.0, 0.46), a.rect(0.0, 0.54, 1.0, 0.62)), YELLOW_PAINT),
        ("double_v", lambda a: a.either(a.rect(0.38, 0.0, 0.46, 1.0), a.rect(0.54, 0.0, 0.62, 1.0)), YELLOW_PAINT),
        ("edge_n", lambda a: a.rect(0.0, 0.10, 1.0, 0.18), WHITE_PAINT),
        ("edge_e", lambda a: a.rect(0.82, 0.0, 0.90, 1.0), WHITE_PAINT),
        ("edge_s", lambda a: a.rect(0.0, 0.82, 1.0, 0.90), WHITE_PAINT),
        ("edge_w", lambda a: a.rect(0.10, 0.0, 0.18, 1.0), WHITE_PAINT),
        ("cross_h", lambda a: a.rect(0.0, 0.20, 1.0, 0.72), WHITE_PAINT),
        ("cross_v", lambda a: a.rect(0.20, 0.0, 0.72, 1.0), WHITE_PAINT),
        ("stop_h", lambda a: a.rect(0.0, 0.34, 1.0, 0.62), WHITE_PAINT),
        ("stop_v", lambda a: a.rect(0.34, 0.0, 0.62, 1.0), WHITE_PAINT),
    ]
    for i, (name, mk, colour) in enumerate(specs):
        a = Art(1, 1)
        m = mk(a)
        m = ImageChops.multiply(m, wear_mask(1, 1, 11 + i, 0.30))
        a.paint(m, lambda X, Y, c=colour: np.array(c, np.float32)[None, None, :] * (0.94 + 0.10 * fbm(X, Y, 9.0, 4, 2))[..., None])
        cx, cy = i % 4, i // 4
        sheet.alpha_composite(a.image(grain=0.0), (cx * PX, cy * PX))
        cells[name] = [cx, cy]
    atlas_item("street", "lane_markings", sheet, 4, 3, cells, (PX, PX), ["decal", "road_paint"], "decal",
               "Road paint, laid over asphalt cells (worn, so it is see-through in places). dash_*: a dash half a cell long, the next cell continues "
               "the pattern; double_*: a yellow double centre line; edge_n/e/s/w: a white edge line near the named side of the cell (the side that "
               "is next to the kerb); cross_h / cross_v: one bar of a zebra crossing (h: the bar runs along x, for a crossing over a road that "
               "runs east to west: stack cells along y); stop_h / stop_v: a stop line (h: across a road that runs north to south).",
               bg=ASPHALT)


def kerb_cell(kind, k):
    """The kerb on a sidewalk cell, drawn for the road on the south (kind 'straight'), or the corner at the south east
    ('corner': the sidewalk's own corner, rounded) or ('inner': the road's corner cuts into the sidewalk), turned k quarter
    turns clockwise. 1.25 x 1.25 tiles: the extra quarter is where the kerb's shadow falls on the road."""
    R = 0.5
    kb = Art(1.0, 1.0)         # the kerb stone
    rd = Art(1.0, 1.0)         # asphalt where the corner rounds off
    stone = (176, 172, 162)
    edge = (70, 66, 60)

    def arc(cx, cy, r, a0, a1, n=14):
        return [(cx + r * np.cos(np.radians(a0 + (a1 - a0) * i / n)), cy + r * np.sin(np.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]

    def asph(X, Y):
        return col3(ASPHALT) * (0.97 + 0.07 * fbm(X, Y, 8.0, 31, 2))[..., None]

    if kind == "straight":
        band = [(0.0, 0.80), (1.0, 0.80), (1.0, 1.0), (0.0, 1.0)]
        kb.paint(kb.poly(band), lit(stone, 0.92, 1.08, 0, 0.8, 1, 1, 0.05, 3, 12))
        kb.paint(kb.stroke([(0.0, 0.815), (1.0, 0.815)], 0.016, round_ends=False), (214, 210, 200), 0.7)
        kb.paint(kb.stroke([(0.0, 0.80), (1.0, 0.80)], 0.012, round_ends=False), (96, 92, 84), 0.55)
        kb.paint(kb.stroke([(0.0, 0.985), (1.0, 0.985)], 0.03, round_ends=False), edge, 1.0)
        for xx in (0.0, 1.0):               # the stone joints
            kb.paint(kb.stroke([(xx, 0.80), (xx, 1.0)], 0.012, round_ends=False), (96, 92, 84), 0.8)
    elif kind == "corner":
        outer = [(0.0, 1.0)] + arc(1 - R, 1 - R, R, 90, 0)[::1] + [(1.0, 0.0), (0.0, 0.0)]
        outer = [(0.0, 0.0), (0.0, 1.0)] + arc(0.5, 0.5, R, 90, 0)[:] + [(1.0, 0.0)]
        inner = [(0.0, 0.80)] + arc(0.5, 0.5, R - 0.2, 90, 0) + [(0.80, 0.0), (0.0, 0.0)]
        inner = [(0.0, 0.0), (0.0, 0.80)] + arc(0.5, 0.5, R - 0.2, 90, 0) + [(0.80, 0.0)]
        mo, mi = kb.poly(outer), kb.poly(inner)
        band = kb.minus(mo, mi)
        kb.paint(band, lit(stone, 0.92, 1.08, 0, 0, 1, 1, 0.05, 3, 12))
        kb.paint(kb.stroke([(0.0, 1.0)] + arc(0.5, 0.5, R, 90, 0)[:-0 or None] + [(1.0, 0.0)], 0.03, round_ends=False), edge, 1.0, clip=mo)
        kb.paint(kb.stroke([(0.0, 0.80)] + arc(0.5, 0.5, R - 0.2, 90, 0) + [(0.80, 0.0)], 0.012, round_ends=False), (96, 92, 84), 0.55)
        corner_out = [(0.5, 1.0), (1.0, 1.0), (1.0, 0.5)] + arc(0.5, 0.5, R, 0, 90)[::1]
        corner_out = [(1.0, 1.0)] + arc(0.5, 0.5, R, 0, 90)
        rd.paint(rd.poly(corner_out), asph)
    else:   # 'inner': the road's corner bites a quarter disc out of the sidewalk at the south east corner
        outer = arc(1.0, 1.0, R + 0.2, 180, 270) + [(1.0, 1.0)]
        inner = arc(1.0, 1.0, R, 180, 270) + [(1.0, 1.0)]
        mo, mi = kb.poly(outer), kb.poly(inner)
        band = kb.minus(mo, mi)
        kb.paint(band, lit(stone, 0.92, 1.08, 0, 0, 1, 1, 0.05, 3, 12))
        kb.paint(kb.stroke(arc(1.0, 1.0, R + 0.015, 180, 270), 0.03, round_ends=False), edge, 1.0, clip=mo)
        kb.paint(kb.stroke(arc(1.0, 1.0, R + 0.2, 180, 270), 0.012, round_ends=False), (96, 92, 84), 0.55)
        rd.paint(rd.poly(inner), asph)
    # turn both, add the road's patch under the stone, the stone's shadow on both
    pad = 0.25
    out = Art(1.0 + pad, 1.0 + pad)

    def turned(art):
        pr, al = art.prem, art.alpha
        if k:
            pr = np.ascontiguousarray(np.rot90(pr, -k, axes=(0, 1)))
            al = np.ascontiguousarray(np.rot90(al, -k, axes=(0, 1)))
        return pr, al

    def over(pr, al):
        hh, ww = al.shape
        out.prem[:hh, :ww] = pr + out.prem[:hh, :ww] * (1 - al)[..., None]
        out.alpha[:hh, :ww] = al + out.alpha[:hh, :ww] * (1 - al)

    rp, ra = turned(rd)
    over(rp, ra)
    kp, ka = turned(kb)
    # the shadow of the stone, over the road and the pavement alike (it is the stone's, so it goes under the stone only)
    sil = np.zeros_like(out.alpha)
    sil[:ka.shape[0], :ka.shape[1]] = ka
    mv = Image.fromarray((sil * 255).astype(np.uint8))
    sx, sy = int(0.045 * S), int(0.06 * S)
    mv = ImageChops.offset(mv, sx, sy).filter(ImageFilter.GaussianBlur(0.03 * S))
    out.paint(mv, (8, 6, 4), 0.40)
    over(kp, ka)
    return out.image(grain=0.01, seed=5 + k)


def street_kerbs():
    cells = {}
    sheet = sheet_cells(4, 3, 160, 160)
    names = [("s", "straight", 0), ("w", "straight", 1), ("n", "straight", 2), ("e", "straight", 3),
             ("corner_se", "corner", 0), ("corner_sw", "corner", 1), ("corner_nw", "corner", 2), ("corner_ne", "corner", 3),
             ("inner_se", "inner", 0), ("inner_sw", "inner", 1), ("inner_nw", "inner", 2), ("inner_ne", "inner", 3)]
    for i, (name, kind, k) in enumerate(names):
        im = kerb_cell(kind, k)
        sheet.alpha_composite(im, ((i % 4) * 160, (i // 4) * 160))
        cells[name] = [i % 4, i // 4]
    atlas_item("street", "kerb", sheet, 4, 3, cells, (160, 160), ["decal", "kerb"], "decal",
               "The kerb, laid on a SIDEWALK cell. s/w/n/e: a stone along the named edge (the side the road is on); corner_se..: the sidewalk's "
               "own corner is rounded (the roads are on both named sides: asphalt fills the corner); inner_se..: the sidewalk cell's neighbours "
               "on the two named sides are sidewalk but the cell diagonally there is road (a street corner seen from its other side): a quarter "
               "disc of road bites into the cell. A cell is 160 x 160 px = 1.25 tiles, anchor (0, 0): the extra quarter to the right and below "
               "holds the stone's soft shadow, so the picture is laid with its top left on the cell's top left.",
               mode="sprite", bg=SIDEWALK)


def leaves(variant):
    rng = rng_for("leaves", variant)
    a = Art(1, 1)
    pal = [[(176, 112, 48), (190, 150, 56), (138, 88, 44), (118, 112, 52)],
           [(120, 84, 48), (140, 100, 56), (100, 74, 44), (156, 124, 70)],
           [(200, 160, 60), (180, 140, 52), (214, 176, 80), (160, 120, 48)]][variant]
    for _ in range(20 + 4 * variant):
        cx, cy = rng.uniform(0.08, 0.92), rng.uniform(0.08, 0.92)
        ang = rng.uniform(0, 6.28)
        L, Wd = rng.uniform(0.055, 0.085), rng.uniform(0.028, 0.042)
        pts = []
        for t in np.linspace(0, 2 * np.pi, 16, endpoint=False):
            x, y = np.cos(t) * L * (1.0 if np.cos(t) > 0 else 0.8), np.sin(t) * Wd * (1 - 0.3 * np.cos(t))
            pts.append((cx + x * np.cos(ang) - y * np.sin(ang), cy + x * np.sin(ang) + y * np.cos(ang)))
        c = pal[rng.integers(0, len(pal))]
        a.paint(a.poly(pts), tuple(np.clip(np.array(c) + rng.normal(0, 8, 3), 0, 255)))
        a.paint(a.stroke(pts, 0.010, closed=True), OUTLINE, 0.55)
        a.paint(a.stroke([(cx - np.cos(ang) * L * 0.8, cy - np.sin(ang) * L * 0.8), (cx + np.cos(ang) * L, cy + np.sin(ang) * L)], 0.008), shade(c, 0.6), 0.8)
    return a.image(grain=0.0)


def street_misc():
    sprites = put_atlas("street/leaves.png", [(leaves(v), {"variant": v}) for v in range(3)], "glass")
    add_item("street", {"id": "leaves", "category": "street", "kind": "overlay", "layer": "decal", "footprint": [1, 1], "anchor": [0, 0],
                        "variants": 3, "tags": ["decal", "walkable"], "sprites": sprites, "_bg": SIDEWALK,
                        "note": "Fallen leaves, scattered, laid over any ground cell (sidewalk, lawn, asphalt). Rotate or flip at will."})

    def manhole(state, v):
        a = Art(1, 1)
        r = 0.40
        base = (66, 64, 66) if v == 0 else (92, 62, 44)
        disc(a, 0.5, 0.5, r, base, lw=0.03, lo=0.86, hi=1.08)
        a.paint(a.stroke([(0.5 + (r - 0.07) * np.cos(t), 0.5 + (r - 0.07) * np.sin(t)) for t in np.linspace(0, 6.3, 40)], 0.016, closed=True), (30, 28, 28), 0.6)
        for i in range(8):
            ang = i * np.pi / 4 + np.pi / 8
            line(a, [(0.5 + 0.10 * np.cos(ang), 0.5 + 0.10 * np.sin(ang)), (0.5 + 0.27 * np.cos(ang), 0.5 + 0.27 * np.sin(ang))], 0.018, (116, 112, 108) if v == 0 else (150, 100, 66), 0.75)
        a.paint(a.ellipse(0.5, 0.5, 0.07), (110, 106, 102) if v == 0 else (140, 96, 66), 0.9)
        a.paint(a.stroke([(0.5 + 0.07 * np.cos(t), 0.5 + 0.07 * np.sin(t)) for t in np.linspace(0, 6.3, 20)], 0.012, closed=True), OUTLINE, 0.8)
        # a cut along the rim where the cover sits on its frame
        a.paint(a.stroke([(0.5 + (r + 0.02) * np.cos(t), 0.5 + (r + 0.02) * np.sin(t)) for t in np.linspace(0, 6.3, 40)], 0.012, closed=True), (24, 22, 22), 0.5)
        return a
    prop("street", "manhole", 1, 1, manhole, facings=1, variants=2, tags=["decal", "walkable"], layer="decal", pad=(0, 0, 0, 0), shadow=None, bg=ASPHALT,
         note="A cast iron manhole cover on a road or sidewalk cell. Flush with the ground: walkable, no shadow.")

    def drain(state, v):
        a = Art(1, 0.5)
        slab(a, 0.06, 0.06, 0.94, 0.44, (84, 84, 88), r=0.03, lw=0.028, lo=0.85, hi=1.05)
        for i in range(7):
            x = 0.14 + i * 0.112
            a.paint(a.rect(x, 0.12, x + 0.055, 0.38), (14, 14, 16), 1.0)
        if v == 1:      # choked with leaves and litter
            for (lx, ly, c) in ((0.30, 0.25, (150, 104, 52)), (0.52, 0.30, (176, 140, 60)), (0.72, 0.22, (126, 92, 50)), (0.42, 0.18, (112, 108, 54))):
                a.paint(a.ellipse(lx, ly, 0.055, 0.032), c, 0.95)
                a.paint(a.stroke([(lx - 0.05, ly), (lx + 0.05, ly)], 0.006), shade(c, 0.6), 0.8)
        return a
    prop("street", "drain", 1, 1, drain, facings="hv", variants=2, tags=["decal", "walkable"], layer="decal", pad=(0, 0, 0, 0), shadow=None, bg=ASPHALT,
         note="A storm drain grate along a kerb (h: along x; the picture is 1 x 0.5 tiles and sits at the cell's top for h, left for v after the "
              "turn: place its picture on the road cell next to the kerb). Flush with the ground.")


def lawn_edge_cell(k):
    """The edge of a lawn where it meets paving, road or a wall, on the lawn cell (128 px, the whole tile): a strip of bare soil along the
    named edge with a ragged inner side, a soft shade under it, and blades growing in from it. Drawn for the north edge, turned k quarter turns
    clockwise (0 n, 1 e, 2 s, 3 w)."""
    rng = rng_for("lawn_edge")
    a = Art(1, 1)
    xs = np.linspace(0, 1, 40)
    wob = 0.055 + 0.030 * np.sin(xs * 17.0 + 1.3) + 0.024 * np.sin(xs * 41.0 + 0.4)
    top = [(float(x), 0.0) for x in xs]
    soil = top + [(float(x), float(w)) for x, w in zip(xs[::-1], wob[::-1])]
    soil_m = a.poly(soil)
    shade_m = a.blur(a.poly(top + [(float(x), float(w) + 0.15) for x, w in zip(xs[::-1], wob[::-1])]), 0.035)
    a.paint(shade_m, (28, 40, 20), 0.34)
    a.paint(soil_m, lambda X, Y: np.array((70, 55, 36), np.float32)[None, None, :] * (0.88 + 0.22 * fbm(X, Y, 30.0, 17, 2))[..., None], 0.78)
    a.paint(a.poly(top + [(float(x), float(w) * 0.45) for x, w in zip(xs[::-1], wob[::-1])]), (40, 32, 22), 0.55)
    for _ in range(46):
        x = rng.uniform(0.02, 0.98)
        y0 = 0.045 + 0.05 * rng.random()
        ang = np.pi / 2 + rng.normal(0, 0.55)
        ln = rng.uniform(0.045, 0.11)
        c = [(50, 80, 32), (74, 108, 44), (112, 144, 62)][rng.integers(0, 3)]
        line(a, [(x, y0), (x + np.cos(ang) * ln, y0 + np.sin(ang) * ln)], 0.011, c, 0.85)
    for _ in range(12):
        x, y = rng.uniform(0.02, 0.98), rng.uniform(0.0, 0.06)
        dot(a, x, y, 0.012, (116, 100, 76), 0.8)
    im = a.image(grain=0.0)
    if k:
        im = im.rotate(-90 * k)
    return im


def lawn_patch(v):
    """A soft patch of different grass or bare earth, laid over the lawn here and there to break up its repeat (1.5 tiles across)."""
    rng = rng_for("lawn_patch", v)
    n = int(PX * 1.5)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.sqrt(((xs - n / 2) / (n / 2.05)) ** 2 + ((ys - n / 2) / (n / 2.05 * (0.78 + 0.12 * v / 3))) ** 2)
    nz = pnoise(n, 9.0, rng)
    m = smooth(1.0 - d + 0.42 * nz, 0.0, 0.62)
    cols = [((142, 132, 64), 0.36), ((52, 88, 40), 0.34), ((108, 88, 58), 0.42), ((126, 154, 74), 0.28)]
    c, op = cols[v]
    detail = 1.0 + 0.10 * pnoise(n, 1.6, rng)
    rgb = np.clip(np.array(c, np.float32)[None, None, :] * detail[..., None], 0, 255)
    al = np.clip(m * op, 0, 1)
    if v == 2:
        for _ in range(26):
            px, py = rng.normal(n / 2, n * 0.14), rng.normal(n / 2, n * 0.12)
            r = rng.uniform(1.0, 2.2)
            dd = np.sqrt((xs - px) ** 2 + (ys - py) ** 2)
            pm = (dd < r).astype(np.float32) * (m > 0.3)
            rgb = rgb * (1 - pm[..., None]) + np.array((150, 134, 108), np.float32) * pm[..., None]
            al = np.maximum(al, pm * 0.8)
    out = np.dstack([rgb, al * 255.0]).astype(np.uint8)
    return Image.fromarray(out)


def hydrant(st, v):
    a = body(1, 1)
    c = [(196, 54, 44), (214, 176, 56)][v]
    a.paint(a.ellipse(0.5, 0.5, 0.215), OUTLINE, 1.0)
    disc(a, 0.5, 0.5, 0.185, shade(c, 0.8), lw=0.0, lo=0.78, hi=1.12)
    for (cx, cy) in ((0.5, 0.2), (0.5, 0.8)):
        a.paint(a.ellipse(cx, cy, 0.075, 0.06), OUTLINE, 1.0)
        a.paint(a.ellipse(cx, cy, 0.055, 0.042), lit(c, 0.84, 1.12, cx - 0.05, cy - 0.04, cx + 0.05, cy + 0.04), 1.0)
    disc(a, 0.5, 0.5, 0.13, c, lw=0.022, lo=0.80, hi=1.18)
    a.paint(a.ellipse(0.46, 0.46, 0.05, 0.04), (255, 255, 255), 0.30)
    a.paint(a.ellipse(0.5, 0.5, 0.034), (70, 28, 24) if v == 0 else (110, 88, 30), 1.0)
    return a


def streetlamp(st, v):
    """A lamp post seen from above: the foot, the arm leaning out over the street (south) and the lamp head at its end."""
    a = body(1, 1)
    arm = [(0.5, 0.30), (0.5, 0.80)]
    a.paint(a.stroke(arm, 0.095), OUTLINE, 1.0)
    a.paint(a.stroke(arm, 0.056), lit((86, 90, 96), 0.80, 1.14, 0.44, 0.3, 0.56, 0.8), 1.0)
    a.paint(a.ellipse(0.5, 0.30, 0.115), OUTLINE, 1.0)
    disc(a, 0.5, 0.30, 0.088, (78, 82, 88), lw=0.0, lo=0.80, hi=1.15)
    a.paint(a.ellipse(0.48, 0.28, 0.034), (170, 174, 180), 0.8)
    # the head
    slab(a, 0.36, 0.74, 0.64, 0.96, (62, 64, 70), r=0.07, lw=0.026, lo=0.80, hi=1.12)
    a.paint(a.poly(rrect(0.41, 0.79, 0.59, 0.92, 0.04)), (244, 226, 160), 1.0)
    a.paint(a.stroke([(0.43, 0.81), (0.57, 0.81)], 0.012, round_ends=False), (255, 255, 240), 0.8)
    return a


def street_extras():
    sheet = sheet_cells(4, 1, PX, PX)
    cells = {}
    for i, name in enumerate(["n", "e", "s", "w"]):
        sheet.alpha_composite(lawn_edge_cell(i), (i * PX, 0))
        cells[name] = [i, 0]
    atlas_item("street", "lawn_edge", sheet, 4, 1, cells, (PX, PX), ["decal", "lawn"], "decal",
               "The edge of a LAWN cell where a side of it meets paving, road, wall or a fence (bare soil, a ragged line, blades): n/e/s/w name the side "
               "that touches; a corner cell takes two. Laid on the lawn cell itself (128 px = the tile), over the lawn, under everything that stands.",
               mode="rgba", bg=(78, 108, 48))
    patches = put_atlas("street/lawn_patch.png", [(lawn_patch(v), {"variant": v, "look": ["dry", "lush", "bare", "fresh"][v]}) for v in range(4)], "rgba")
    add_item("street", {"id": "lawn_patch", "category": "street", "kind": "overlay", "layer": "decal", "footprint": [1, 1], "anchor": [0, 0], "variants": 4,
                        "tags": ["decal", "walkable", "lawn"], "sprites": patches, "_bg": (78, 108, 48),
                        "note": "A soft patch of different grass (dry, lush, bare earth, fresh), 1.5 x 1.5 tiles, centred where you lay it, over a lawn here and there to "
                                "break up the repeat of the lawn atlas (the three lawns are laid in blocks of 4 x 4)."})
    prop("street", "hydrant", 1, 1, hydrant, facings=1, variants=2, tags=["street", "solid"], layer="object", solid=[], pad=(0.0625, 0.0625, 0.15, 0.15), bg=SIDEWALK,
         shadow=(0.03, 0.04, 0.02, 0.38), note="A fire hydrant on a sidewalk (a: red, b: yellow). Walkable around it; it is only a picture that blocks nothing.")
    prop("street", "streetlamp", 1, 1, streetlamp, facings=4, tags=["street", "solid", "light"], layer="object", solid="all", pad=(0.0625, 0.0625, 0.2, 0.2), bg=SIDEWALK,
         shadow=(0.10, 0.12, 0.04, 0.34), note="A street lamp seen from above: the foot in the cell, the arm leaning out over the street and the lamp head at its end. "
                                                 "Facing = the way the arm points (s: toward the south, so the post stands on the north sidewalk of an east-west street).")


def job_street():
    ground_item("street", "asphalt", ["road"], [("street/asphalt_%s.png" % "abc"[v], asphalt(v)) for v in range(3)],
                "Road surface: a 4 x 4 atlas of 64 px pieces, seamless when repeated (tile (x, y) shows piece (x % 4, y % 4), as assets/terrain does). "
                "a: worn with hairline cracks and oil stains; b: cracked, one pothole; c: two repair patches. All three share the same grain, so "
                "they can border each other: mix them in blocks.", bg=ASPHALT)
    ground_item("street", "sidewalk", ["sidewalk"], [("street/sidewalk_%s.png" % "abc"[v], sidewalk(v)) for v in range(3)],
                "Sidewalk slabs, one slab to the tile, grass in the joints; a 4 x 4 atlas of 64 px pieces. Three variants (a: tidy, b: cracked, c: overgrown).")
    ground_item("street", "lawn", ["grass", "lawn"], [("street/lawn_%s.png" % "abc"[v], lawn(v)) for v in range(3)],
                "Lawn; a 4 x 4 atlas of 64 px pieces. a: plain, b: clover and daisies, c: worn patches and long clumps. Same base, so they mix.")
    ground_item("street", "dirt_path", ["dirt", "path"], [("street/dirt_%s.png" % "ab"[v], dirt(v)) for v in range(2)],
                "Packed dirt for paths and back yards; a 4 x 4 atlas of 64 px pieces. a: dry with stones, b: damp and trodden.")
    ground_item("street", "gravel", ["gravel", "driveway"], [("street/gravel_%s.png" % "ab"[v], gravel(v)) for v in range(2)],
                "Gravel for driveways; a 4 x 4 atlas of 64 px pieces. a: grey, b: tan with weeds.")
    street_markings()
    street_kerbs()
    street_misc()
    street_extras()
    contact("street", scale=1.0)


# ======================================================================
# HOUSE: wall tops, wall edges and shadows, doors, windows, garage doors, steps, porch
# ======================================================================

def _yx():
    return np.mgrid[0:PX, 0:PX]


def _hash2(a, b, seed):
    return mba._hash(np.asarray(a, np.int64), np.asarray(b, np.int64), seed)


def wall_fill(material, variant):
    """A 128 px seamless tile of a wall seen from above (the top of a thick wall)."""
    n = PX
    rng = rng_for("wall_" + material)
    ys, xs = _yx()
    ys = ys.astype(np.int32)
    xs = xs.astype(np.int32)
    if material == "brick":
        bh, bw = 16, 32
        row = ys // bh
        off = (row % 2) * (bw // 2)
        cx = (xs + off) % n
        col = cx // bw
        lx = cx % bw
        ly = ys % bh
        tone = _hash2(row, col, 7)[..., None]
        pal = [np.array(c, np.float32) for c in ((150, 86, 68), (128, 68, 54), (166, 100, 76), (140, 76, 60))]
        sel = (_hash2(row, col, 9) * 4).astype(np.int32) % 4
        base = np.stack([pal[i] for i in range(4)])[sel]
        rgb = base * (0.90 + 0.20 * tone)
        rgb = rgb * (1 + 0.05 * pnoise(n, 1.2, rng)[..., None] + 0.05 * pnoise(n, 9, rng)[..., None])
        bev = np.ones((n, n), np.float32)
        bev[(ly >= 2) & (ly < 4)] *= 1.14
        bev[ly >= bh - 3] *= 0.84
        bev[(lx >= 2) & (lx < 4)] *= 1.07
        bev[lx >= bw - 3] *= 0.90
        rgb = rgb * bev[..., None]
        mortar = (lx < 2) | (ly < 2)
        mcol = col3((184, 172, 150)) * (0.94 + 0.10 * pnoise(n, 1.5, rng))[..., None]
        rgb = np.where(mortar[..., None], mcol, rgb)
    elif material in ("white", "blue"):
        bh = 16
        base = (214, 210, 198) if material == "white" else (100, 130, 156)
        row = ys // bh
        ly = ys % bh
        tone = (0.97 + 0.06 * _hash2(row, row * 0, 5))[..., None]
        grain = pnoise(n, 1, rng, sx=36, sy=1.0)
        rgb = col3(base) * tone * (1 + 0.035 * grain[..., None])
        k = np.ones((n, n), np.float32)
        k[ly == 0] *= 1.10
        k[ly >= bh - 3] *= 0.88
        k[ly >= bh - 1] *= 0.80
        rgb = rgb * k[..., None]
        # butt joints
        for r in range(n // bh):
            for _ in range(2):
                x = int(rng.integers(0, n))
                rgb[r * bh + 1:(r + 1) * bh - 1, x] *= 0.80
        dirt = smooth(pnoise(n, 1, rng_for("wall_dirt_" + material), sx=2.4, sy=22), 0.15, 0.9)
        rgb = rgb * (1 - 0.14 * dirt[..., None])
        rgb = rgb * (1 + 0.02 * pnoise(n, 8, rng)[..., None])
    elif material == "stucco":
        base = (194, 174, 140)
        rgb = col3(base) * (1 + 0.04 * pnoise(n, 0.9, rng)[..., None] + 0.035 * pnoise(n, 7, rng)[..., None] + 0.03 * pnoise(n, 24, rng)[..., None])
        sp = pnoise(n, 0.7, rng)
        rgb = np.where((sp > 0.55)[..., None], rgb * 1.08, rgb)
        rgb = np.where((sp < -0.55)[..., None], rgb * 0.90, rgb)
    elif material == "plaster":
        rgb = col3((224, 218, 202)) * (1 + 0.020 * pnoise(n, 0.9, rng)[..., None] + 0.025 * pnoise(n, 10, rng)[..., None])
    elif material == "sage":
        rgb = col3((156, 170, 142)) * (1 + 0.022 * pnoise(n, 0.9, rng)[..., None] + 0.03 * pnoise(n, 10, rng)[..., None])
    elif material == "timber":
        bh = 16
        row = ys // bh
        ly = ys % bh
        tone = (0.92 + 0.16 * _hash2(row, row * 0, 3))[..., None]
        grain = pnoise(n, 1, rng, sx=30, sy=0.9)
        rgb = col3((126, 94, 64)) * tone * (1 + 0.07 * grain[..., None])
        k = np.ones((n, n), np.float32)
        k[ly == 0] *= 1.12
        k[ly >= bh - 2] *= 0.70
        rgb = rgb * k[..., None]
    g = Ground(rgb, n=n)
    if variant == 1:
        r2 = rng_for("wall_decal_" + material)
        if material == "brick":
            blotch(g, r2, 64, 22, 26, (30, 26, 24), 0.38)        # soot
            pts = crack_walk(r2, (36, 70), 0.3, 56, step=4, jit=0.8)
            g.crack(pts, 1.8, dark=(40, 30, 26), op=0.9, hi=(210, 190, 170), hiop=0.2)
            g.lay(g.ellipses([(94, 98, 11, 6)]), (120, 56, 44), 0.8)       # a patched-in brick or two
            g.lay(g.line([(86, 98), (102, 98)], 1.3), (190, 178, 156), 0.9)
        elif material in ("white", "blue"):
            blotch(g, r2, 40, 70, 22, (70, 60, 44), 0.30)
            g.lay(g.poly([(66, 49), (110, 49), (110, 64), (66, 64)]), (62, 54, 46), 0.80)          # a board off, the dark behind it
            g.lay(g.line([(66, 49), (110, 49)], 2.0), (30, 26, 22), 0.55)
            g.lay(g.line([(66, 64), (110, 64)], 1.2), (240, 236, 220), 0.35)
        elif material == "stucco":
            blotch(g, r2, 52, 78, 20, (120, 100, 70), 0.30)
            g.crack(crack_walk(r2, (40, 30), 0.9, 52, step=4, jit=0.7), 2.0, dark=(70, 58, 44), op=0.85)
            g.crack(crack_walk(r2, (88, 24), 1.6, 40, step=4, jit=0.7), 1.4, dark=(70, 58, 44), op=0.8)
        else:       # an interior wall: a stain and a scuff
            blotch(g, r2, 60, 64, 28, (120, 106, 80), 0.30)
            g.lay(g.line([(24, 98), (70, 92)], 3.0), (170, 162, 146), 0.35)
    return finish_ground(g.rgb, material)


WALLS = [("brick", "Brick", "exterior"), ("white", "White siding", "exterior"), ("blue", "Blue siding", "exterior"), ("stucco", "Beige stucco", "exterior"),
         ("plaster", "Cream plaster", "interior"), ("sage", "Sage plaster", "interior"), ("timber", "Timber boarding", "interior")]


def wall_edges_atlas():
    """16 cells: the outline and the rim of a wall top on the sides that are OPEN (not wall). Index = N 1 + E 2 + S 4 + W 8."""
    sheet = sheet_cells(4, 4, PX, PX)
    cells = {}
    for idx in range(16):
        a = Art(1, 1)
        n_, e_, s_, w_ = bool(idx & 1), bool(idx & 2), bool(idx & 4), bool(idx & 8)
        ol, rm = 0.05, 0.05
        # rims inside the outline: light on the north and west, dark on the south and east
        if n_:
            a.paint(a.rect(0, ol, 1, ol + rm), (255, 250, 232), 0.30)
        if w_:
            a.paint(a.rect(ol, 0, ol + rm, 1), (255, 250, 232), 0.26)
        if s_:
            a.paint(a.rect(0, 1 - ol - rm, 1, 1 - ol), (10, 8, 6), 0.30)
        if e_:
            a.paint(a.rect(1 - ol - rm, 0, 1 - ol, 1), (10, 8, 6), 0.26)
        for flag, rect in ((n_, (0, 0, 1, ol)), (s_, (0, 1 - ol, 1, 1)), (w_, (0, 0, ol, 1)), (e_, (1 - ol, 0, 1, 1))):
            if flag:
                a.paint(a.rect(*rect), OUTLINE, 0.96)
        sheet.alpha_composite(a.image(), ((idx % 4) * PX, (idx // 4) * PX))
        cells[str(idx)] = [idx % 4, idx // 4]
    atlas_item("house", "wall_edges", sheet, 4, 4, cells, (PX, PX), ["wall", "autotile"], "wall",
               "The outline and the rims of a wall top, laid over a wall fill (wall_<material>) on a wall cell. Cell index = mask of the OPEN sides "
               "(the neighbour on that side is not a wall): N 1 + E 2 + S 4 + W 8; col = index % 4, row = index // 4. A door cell is NOT a wall for "
               "this (the wall ends in front of it get their outline); a window cell IS a wall (the wall runs on through it).",
               bg=(150, 90, 70))


def wall_shadows_atlas():
    """4 cells of soft shadow to lay on the FLOOR or GROUND cells next to a wall (light from the top left)."""
    sheet = sheet_cells(4, 1, PX, PX)
    cells = {}
    ys, xs = _yx()
    xn, yn = xs / PX, ys / PX
    shadow_n = np.clip(1 - yn / 0.36, 0, 1) ** 1.5 * 0.40         # a wall to the north: a band along the cell's top
    shadow_w = np.clip(1 - xn / 0.30, 0, 1) ** 1.5 * 0.32         # a wall to the west: a band along its left
    corner = np.clip(1 - np.sqrt(xn ** 2 + yn ** 2) / 0.34, 0, 1) ** 1.5 * 0.32
    layers = [shadow_n, shadow_w, np.maximum(shadow_n, shadow_w), corner]
    for i, a in enumerate(layers):
        im = np.zeros((PX, PX, 4), np.uint8)
        im[..., :3] = (10, 8, 6)
        im[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
        sheet.alpha_composite(Image.fromarray(im), (i * PX, 0))
    cells = {"n": [0, 0], "w": [1, 0], "nw": [2, 0], "diag_nw": [3, 0]}
    atlas_item("house", "wall_shadows", sheet, 4, 1, cells, (PX, PX), ["decal", "shadow"], "decal",
               "Soft wall shadows, laid on floor or ground cells (not on the wall itself). n: the cell's north neighbour is a wall; w: its west neighbour "
               "is a wall; nw: both; diag_nw: neither, but the cell to the north west is (a small dab in the corner). Light comes from the top left.",
               bg=(176, 140, 100))


def job_house():
    for mat, label, where in WALLS:
        sprites = []
        for v in range(2):
            rec = put("house/wall_%s_%s.png" % (mat, "ab"[v]), wall_fill(mat, v), "opaque")
            rec["variant"] = v
            sprites.append(rec)
        add_item("house", {"id": "wall_" + mat, "category": "house", "kind": "wall_fill", "layer": "wall", "footprint": [1, 1], "anchor": [0, 0],
                           "variants": 2, "tags": ["wall", "solid", where], "solid": "all", "sprites": sprites,
                           "edges": "wall_edges", "shadows": "wall_shadows", "name": label,
                           "note": "%s wall top, a seamless 128 px tile (the top of a one tile thick wall). Lay it on every wall cell, then the matching "
                                   "wall_edges cell over it (outline on the open sides). a is plain, b has a decal (crack, stain, patch) that stays "
                                   "clear of the edges: use b for about one cell in six." % label})
    wall_edges_atlas()
    wall_shadows_atlas()
    house_openings()
    contact("house", scale=1.0)


BRASS = (200, 170, 84)
FRONT_DOORS = [(122, 72, 54), (82, 116, 100)]          # oxblood, sage green
INT_DOORS = [(226, 222, 210), (146, 106, 72)]          # white painted, stained wood


def _planks_floor(a, x0, y0, x1, y1, base, seed, along="y", n=3):
    """Boards across a cell (the floor of a doorway)."""
    a.paint(a.rect(x0, y0, x1, y1), _wood_fn(base, seed, along))
    step = (x1 - x0) / n if along == "y" else (y1 - y0) / n
    for i in range(1, n):
        if along == "y":
            line(a, [(x0 + i * step, y0), (x0 + i * step, y1)], 0.012, (40, 28, 18), 0.55, round_ends=False)
        else:
            line(a, [(x0, y0 + i * step), (x1, y0 + i * step)], 0.012, (40, 28, 18), 0.55, round_ends=False)


def _wood_fn(base, seed, along="y", grain=0.28):
    """Boards with a grain (a colour function): two octaves, soft, so that the picture stays small."""
    def f(X, Y):
        n = fbm(X, Y, min(FREQ_MAX, 10.0), seed, 2, fx=(1.0 if along == "y" else 0.14), fy=(0.14 if along == "y" else 1.0))
        k = 1.0 - grain * NOISE / 2.0 + grain * NOISE * n
        return np.array(base, np.float32)[None, None, :] * k[..., None]
    return f


def door_cell(state, v, kind):
    """A door in a wall cell, facing south (the outside is south, the room north). kind 'front' or 'int'."""
    a = Art(1, 1)
    dc = (FRONT_DOORS if kind == "front" else INT_DOORS)[v]
    floor = (146, 108, 74) if kind == "front" else (150, 114, 80)
    _planks_floor(a, 0, 0, 1, 1, floor, 4 + v)
    if kind == "front":      # the sill: a concrete lip on the outside half
        a.paint(a.rect(0.0, 0.70, 1.0, 1.0), lambda X, Y: np.array((160, 156, 146), np.float32)[None, None, :] * (0.94 + 0.10 * fbm(X, Y, 10.0, 8, 2))[..., None])
        line(a, [(0.0, 0.70), (1.0, 0.70)], 0.014, (70, 64, 56), 0.7, round_ends=False)
        line(a, [(0.0, 0.715), (1.0, 0.715)], 0.010, (214, 210, 198), 0.5, round_ends=False)
    # the frame: a jamb each side
    jc = (86, 62, 44) if kind == "front" else ((196, 192, 180) if v == 0 else (104, 76, 52))
    for x0, x1 in ((0.0, 0.085), (0.915, 1.0)):
        a.paint(a.rect(x0, 0, x1, 1), lit(jc, 0.85, 1.1, x0, 0, x1, 1, 0.12, 6, 12, "y"))
    line(a, [(0.085, 0), (0.085, 1)], 0.022, OUTLINE, 0.95, round_ends=False)
    line(a, [(0.915, 0), (0.915, 1)], 0.022, OUTLINE, 0.95, round_ends=False)
    line(a, [(0.0, 0.0), (1.0, 0.0)], 0.0, OUTLINE, 0.0)
    left_hinged = v == 0

    def leaf_closed():
        slab(a, 0.085, 0.40, 0.915, 0.60, dc, r=0.012, lw=0.026, lo=0.80, hi=1.14, noise=0.10, seed=12, freq=18.0, along="x")
        if kind == "front":
            for x0, x1 in ((0.17, 0.46), (0.54, 0.83)):
                a.paint(a.rect(x0, 0.445, x1, 0.555), shade(dc, 0.72), 0.55)
                line(a, [(x0, 0.445), (x1, 0.445)], 0.008, shade(dc, 1.3), 0.5, round_ends=False)
        hx = 0.80 if left_hinged else 0.20
        dot(a, hx, 0.50, 0.030, (40, 32, 26))
        dot(a, hx, 0.50, 0.022, BRASS)
        dot(a, hx - 0.006, 0.494, 0.008, (250, 240, 200), 0.9)

    if state == "closed":
        # a thin shadow under the leaf on the sill side
        a.paint(a.blur(a.rect(0.09, 0.60, 0.91, 0.66), 0.012), (8, 6, 4), 0.32)
        leaf_closed()
    elif state == "open":
        hx0, hx1 = (0.085, 0.215) if left_hinged else (0.785, 0.915)
        a.paint(a.blur(a.rect(hx0 + 0.02, 0.12, hx1 + 0.10, 0.92), 0.02), (8, 6, 4), 0.30)
        slab(a, hx0, 0.10, hx1, 0.90, dc, r=0.012, lw=0.026, lo=0.80, hi=1.14, noise=0.10, seed=14, freq=18.0, along="y")
        a.paint(a.rect(hx0 + 0.03, 0.22, hx1 - 0.03, 0.42), shade(dc, 0.74), 0.5)
        a.paint(a.rect(hx0 + 0.03, 0.54, hx1 - 0.03, 0.74), shade(dc, 0.74), 0.5)
        hx = (hx0 + hx1) / 2
        dot(a, hx, 0.84, 0.026, (40, 32, 26))
        dot(a, hx, 0.84, 0.019, BRASS)
        for yy in (0.18, 0.62):
            a.paint(a.rect(hx0 - 0.012 if left_hinged else hx1 - 0.02, yy, hx0 + 0.02 if left_hinged else hx1 + 0.012, yy + 0.05), (44, 38, 34), 0.95)
    else:   # broken: the leaf hangs from its top hinge, torn, the frame splintered
        px_, py_ = (0.10, 0.20) if left_hinged else (0.90, 0.20)
        ang = np.radians(58 if left_hinged else 122)
        ux, uy = np.cos(ang), np.sin(ang)
        vx, vy = -uy, ux
        L, T = 0.78, 0.13
        pts = [(px_ + vx * T / 2, py_ + vy * T / 2), (px_ - vx * T / 2, py_ - vy * T / 2)]
        far = []
        for i, t in enumerate(np.linspace(-T / 2, T / 2, 5)):
            r = L - (0.07 if i % 2 else 0.0) - (0.04 if i == 2 else 0)
            far.append((px_ + ux * r + vx * t, py_ + uy * r + vy * t))
        poly = [(px_ + vx * T / 2, py_ + vy * T / 2)] + far[::-1] + [(px_ - vx * T / 2, py_ - vy * T / 2)]
        poly = [(px_ - vx * T / 2, py_ - vy * T / 2), (px_ + vx * T / 2, py_ + vy * T / 2)] + far[::-1]
        a.paint(a.blur(a.poly([(x + 0.03, y + 0.04) for x, y in poly]), 0.02), (8, 6, 4), 0.35)
        a.paint(a.poly(poly), lit(shade(dc, 0.82), 0.8, 1.1, 0, 0, 1, 1, 0.15, 21, 16))
        a.paint(a.stroke(poly, 0.024, closed=True), OUTLINE, 1.0)
        a.paint(a.poly([(px_ + ux * 0.3 + vx * 0.02, py_ + uy * 0.3 + vy * 0.02), (px_ + ux * 0.46 + vx * 0.03, py_ + uy * 0.46 + vy * 0.03),
                        (px_ + ux * 0.44 - vx * 0.02, py_ + uy * 0.44 - vy * 0.02)]), (26, 20, 16), 0.9)
        # splinters on the floor and a raw broken edge on the jamb
        for sx, sy, ang2 in ((0.42, 0.88, 0.4), (0.60, 0.78, 1.2), (0.30, 0.74, 2.0), (0.70, 0.90, 0.1)):
            if not left_hinged:
                sx = 1.0 - sx
            q = [(sx, sy), (sx + 0.07 * np.cos(ang2), sy + 0.07 * np.sin(ang2)), (sx + 0.07 * np.cos(ang2) - 0.012, sy + 0.07 * np.sin(ang2) + 0.014)]
            a.paint(a.poly(q), (176, 138, 96), 0.95)
            a.paint(a.stroke(q, 0.008, closed=True), OUTLINE, 0.7)
        jx = 0.915 if left_hinged else 0.085
        sg = 1 if left_hinged else -1
        a.paint(a.poly([(jx, 0.34), (jx - sg * 0.07, 0.40), (jx, 0.46), (jx - sg * 0.05, 0.54), (jx, 0.62), (jx + sg * 0.01, 0.34)]), (176, 138, 96), 1.0)
        a.paint(a.stroke([(jx, 0.34), (jx - sg * 0.07, 0.40), (jx, 0.46), (jx - sg * 0.05, 0.54), (jx, 0.62)], 0.012, round_ends=False), OUTLINE, 0.9)
    return a


def window_overlay(state, v):
    """A window set in a wall top (picture 1 x 1, glass strip across the middle of the wall's thickness), wall running along x."""
    a = Art(1, 1)
    frame = (232, 228, 216) if v == 0 else (126, 92, 62)
    y0, y1 = 0.22, 0.78
    # a lip of sill on both sides of the strip
    slab(a, 0.02, y0, 0.98, y1, frame, r=0.02, lw=0.03, lo=0.80, hi=1.08, noise=0.05, seed=3)
    gx0, gx1, gy0, gy1 = 0.10, 0.90, 0.32, 0.68

    def sky(X, Y):
        t = np.clip((Y - gy0) / (gy1 - gy0), 0, 1)[..., None]
        top = np.array((176, 200, 214), np.float32)[None, None, :]
        bot = np.array((108, 138, 164), np.float32)[None, None, :]
        return top * (1 - t) + bot * t
    if state == "boarded":
        a.paint(a.rect(gx0, gy0, gx1, gy1), (34, 30, 30), 1.0)
        a.paint(a.stroke([(gx0, gy0), (gx1, gy0), (gx1, gy1), (gx0, gy1)], 0.02, closed=True), OUTLINE, 1.0)
        rng = rng_for("boards", v)
        for i, (py0, py1) in enumerate(((0.20, 0.38), (0.41, 0.58), (0.60, 0.80))):
            x0, x1 = rng.uniform(-0.01, 0.06), rng.uniform(0.94, 1.01)
            tilt = rng.uniform(-0.025, 0.025)
            poly = [(x0, py0 + tilt), (x1, py0 - tilt), (x1, py1 - tilt), (x0, py1 + tilt)]
            a.paint(a.blur(a.poly([(x + 0.01, y + 0.025) for x, y in poly]), 0.015), (8, 6, 4), 0.45)
            a.paint(a.poly(poly), lit((150 + 8 * i, 114 + 6 * i, 78 + 4 * i), 0.82, 1.1, 0, py0, 1, py1, 0.18, 30 + i, 20, "x"))
            a.paint(a.stroke(poly, 0.020, closed=True), OUTLINE, 1.0)
            line(a, [(x0 + 0.02, py0 + 0.02 + tilt), (x1 - 0.02, py0 + 0.02 - tilt)], 0.008, (214, 180, 134), 0.5, round_ends=False)
            for nx_ in (0.14, 0.50, 0.86):
                nail(a, nx_, (py0 + py1) / 2 + tilt * (1 - 2 * nx_), 0.014)
        return a
    a.paint(a.rect(gx0, gy0, gx1, gy1), sky)
    a.paint(a.poly([(0.16, gy1), (0.30, gy0), (0.38, gy0), (0.24, gy1)]), (250, 250, 250), 0.22)
    a.paint(a.poly([(0.50, gy1), (0.64, gy0), (0.70, gy0), (0.56, gy1)]), (250, 250, 250), 0.16)
    if state == "broken":
        hole = [(0.50, gy0), (0.66, gy0), (0.76, 0.44), (0.70, 0.52), (0.78, gy1), (0.58, gy1), (0.54, 0.54), (0.60, 0.46)]
        a.paint(a.poly(hole), (26, 24, 28), 1.0)
        a.paint(a.stroke(hole, 0.012, closed=True), (236, 244, 250), 0.85)
        for p0, p1 in (((0.58, 0.50), (0.40, 0.42)), ((0.60, 0.50), (0.44, 0.62)), ((0.70, 0.5), (0.86, 0.40)), ((0.66, 0.54), (0.84, 0.62))):
            line(a, [p0, p1], 0.008, (236, 244, 250), 0.85)
        for sx, sy in ((0.46, 0.84), (0.64, 0.86), (0.54, 0.90), (0.80, 0.88)):
            a.paint(a.poly([(sx, sy), (sx + 0.045, sy + 0.012), (sx + 0.012, sy + 0.04)]), (210, 228, 238), 0.9)
    # the middle bar and the frame of the glass
    a.paint(a.rect(0.485, gy0, 0.515, gy1), frame, 1.0)
    a.paint(a.stroke([(0.485, gy0), (0.485, gy1)], 0.010, round_ends=False), OUTLINE, 0.8)
    a.paint(a.stroke([(0.515, gy0), (0.515, gy1)], 0.010, round_ends=False), OUTLINE, 0.8)
    a.paint(a.stroke([(gx0, gy0), (gx1, gy0), (gx1, gy1), (gx0, gy1)], 0.022, closed=True), OUTLINE, 1.0)
    if v == 1 and state == "intact":      # curtains drawn back to both sides
        for x0, x1, flip in ((gx0 + 0.012, 0.31, 1), (0.69, gx1 - 0.012, -1)):
            a.paint(a.rect(x0, gy0 + 0.015, x1, gy1 - 0.015), lit((230, 214, 188), 0.9, 1.08, x0, gy0, x1, gy1, 0.0, 1), 0.96)
            for i in range(1, 4):
                xx = x0 + (x1 - x0) * i / 4
                line(a, [(xx, gy0 + 0.02), (xx, gy1 - 0.02)], 0.008, (140, 120, 92), 0.55, round_ends=False)
        line(a, [(gx0, gy0 + 0.012), (gx1, gy0 + 0.012)], 0.012, (90, 70, 50), 0.9)
    return a


def garage_door(state, v):
    """3 x 1: an overhead door in a wall, facing south."""
    a = Art(3, 1)
    a.paint(a.rect(0, 0, 3, 1), lambda X, Y: np.array((140, 136, 126), np.float32)[None, None, :] * (0.95 + 0.08 * fbm(X, Y, 4.0, 9, 2))[..., None])
    rng = rng_for("garage", v)
    a.paint(a.blur(a.ellipse(1.4, 0.55, 0.45, 0.25), 0.06), (40, 36, 30), 0.35)         # an oil stain
    # the jambs and the track rails
    for x0, x1 in ((0.0, 0.10), (2.90, 3.0)):
        a.paint(a.rect(x0, 0, x1, 1), (100, 98, 94), 1.0)
    for xx in (0.10, 2.90):
        line(a, [(xx, 0), (xx, 1)], 0.022, OUTLINE, 0.95, round_ends=False)
    for xx in (0.17, 2.83):
        line(a, [(xx, 0.0), (xx, 1.0)], 0.030, (70, 72, 76), 0.95, round_ends=False)
    panel = (206, 204, 194) if v == 0 else (150, 164, 150)
    if state == "closed":
        a.paint(a.blur(a.rect(0.12, 0.60, 2.88, 0.68), 0.012), (8, 6, 4), 0.30)
        slab(a, 0.10, 0.38, 2.90, 0.60, panel, r=0.012, lw=0.026, lo=0.82, hi=1.10, noise=0.05, seed=22)
        for i in range(1, 6):
            line(a, [(0.10 + i * 2.8 / 6, 0.38), (0.10 + i * 2.8 / 6, 0.60)], 0.012, shade(panel, 0.62), 0.9, round_ends=False)
        for i in range(4):          # a row of small glazed lights
            x0 = 0.40 + i * 0.65
            a.paint(a.rect(x0, 0.45, x0 + 0.42, 0.53), (120, 150, 172), 0.95)
            a.paint(a.stroke([(x0, 0.45), (x0 + 0.42, 0.45), (x0 + 0.42, 0.53), (x0, 0.53)], 0.008, closed=True), OUTLINE, 0.8)
        line(a, [(1.30, 0.585), (1.70, 0.585)], 0.020, (60, 56, 52), 0.9)
    elif state == "open":
        # rolled up: the door hangs overhead against the ceiling, the lower part of the cell open to the floor
        slab(a, 0.10, 0.02, 2.90, 0.20, shade(panel, 0.92), r=0.010, lw=0.024, lo=0.78, hi=1.0, noise=0.05, seed=24)
        for i in range(1, 6):
            line(a, [(0.10 + i * 2.8 / 6, 0.02), (0.10 + i * 2.8 / 6, 0.20)], 0.010, shade(panel, 0.6), 0.9, round_ends=False)
        a.paint(a.rect(0.12, 0.21, 2.88, 0.36), (14, 12, 12), 0.30)
    else:   # broken: buckled, one end off its track
        pts_top = [(0.10, 0.34), (0.9, 0.38), (1.6, 0.30), (2.1, 0.44), (2.40, 0.52)]
        pts_bot = [(2.44, 0.76), (2.1, 0.66), (1.6, 0.52), (0.9, 0.58), (0.10, 0.56)]
        poly = pts_top + pts_bot
        a.paint(a.blur(a.poly([(x + 0.03, y + 0.05) for x, y in poly]), 0.02), (8, 6, 4), 0.35)
        a.paint(a.poly(poly), lit(shade(panel, 0.88), 0.78, 1.08, 0, 0.3, 3, 0.8, 0.12, 25, 12))
        a.paint(a.stroke(poly, 0.026, closed=True), OUTLINE, 1.0)
        for x in (0.7, 1.3, 1.9):
            line(a, [(x, 0.36 + 0.03 * (x > 1.2)), (x + 0.02, 0.56)], 0.012, shade(panel, 0.55), 0.9, round_ends=False)
        a.paint(a.poly([(0.74, 0.40), (1.0, 0.42), (0.96, 0.54), (0.70, 0.54)]), (26, 24, 24), 0.9)         # a panel torn out
        for px_, py_ in ((2.55, 0.62), (2.62, 0.82), (2.74, 0.70)):
            a.paint(a.poly([(px_, py_), (px_ + 0.10, py_ + 0.02), (px_ + 0.04, py_ + 0.08)]), shade(panel, 0.8), 0.95)
    return a


def step_body(state, v):
    """The step in front of a door (3 x 1, facing south): one concrete or wooden tread."""
    a = Art(3, 1)
    if v == 0:
        slab(a, 0.04, 0.06, 2.96, 0.60, (162, 158, 148), r=0.03, lw=0.028, lo=0.84, hi=1.10, noise=0.07, seed=31, freq=9.0)
        slab(a, 0.20, 0.52, 2.80, 0.94, (150, 146, 136), r=0.03, lw=0.028, lo=0.82, hi=1.08, noise=0.07, seed=32, freq=9.0)
        line(a, [(0.26, 0.54), (2.74, 0.54)], 0.012, (214, 210, 198), 0.6, round_ends=False)
        a.paint(a.blur(a.ellipse(1.8, 0.78, 0.22, 0.07), 0.02), (60, 56, 48), 0.35)
    else:
        for i, (y0, y1, x0, x1) in enumerate(((0.06, 0.34, 0.04, 2.96), (0.36, 0.64, 0.04, 2.96), (0.68, 0.94, 0.16, 2.84))):
            slab(a, x0, y0, x1, y1, (146 + 6 * i, 108 + 5 * i, 72 + 3 * i), r=0.012, lw=0.026, lo=0.80, hi=1.10, noise=0.18, seed=40 + i, freq=16.0, along="x")
            for nx_ in (x0 + 0.12, x1 - 0.12, (x0 + x1) / 2):
                nail(a, nx_, (y0 + y1) / 2, 0.011)
    return a


def porch_body(state, v):
    """A wooden porch deck 3 x 2 facing south: boards, a rail along both sides and the front, steps in the middle of the front."""
    a = Art(3, 2)
    wood = (150, 112, 76)
    a.paint(a.rect(0.04, 0.04, 2.96, 1.80), _wood_fn(wood, 51, "x", 0.30))
    for i in range(1, 10):
        yy = 0.04 + i * 0.176
        line(a, [(0.04, yy), (2.96, yy)], 0.012, (42, 30, 20), 0.55, round_ends=False)
    rng = rng_for("porch")
    for i in range(10):
        yy = 0.04 + i * 0.176
        for _ in range(2):
            x = rng.uniform(0.3, 2.7)
            line(a, [(x, yy), (x, yy + 0.176)], 0.010, (42, 30, 20), 0.5, round_ends=False)
    blotch_ = a.blur(a.ellipse(2.2, 1.0, 0.45, 0.28), 0.08)
    a.paint(blotch_, (60, 44, 30), 0.20)
    a.paint(a.stroke([(0.04, 0.04), (2.96, 0.04)], 0.03, round_ends=False), OUTLINE, 1.0)
    # the rail all round (but for the steps in the middle of the front), with a post at each corner
    rail = (214, 208, 192) if v == 0 else (112, 84, 58)
    for pts in (([(0.04, 0.04), (0.04, 1.80), (1.05, 1.80)]), ([(2.96, 0.04), (2.96, 1.80), (1.95, 1.80)])):
        line(a, pts, 0.07, shade(rail, 0.86), 1.0, round_ends=False)
        line(a, [(x + 0.012, y - 0.012) for x, y in pts], 0.026, shade(rail, 1.12), 0.9, round_ends=False)
    for px_, py_ in ((0.04, 0.10), (0.04, 1.80), (1.05, 1.80), (1.95, 1.80), (2.96, 1.80), (2.96, 0.10)):
        slab(a, px_ - 0.055, py_ - 0.055, px_ + 0.055, py_ + 0.055, shade(rail, 1.0), r=0.01, lw=0.02, lo=0.8, hi=1.1, rim=False)
    # the steps down at the front, in the middle
    for i, (y0, y1) in enumerate(((1.80, 1.89), (1.89, 1.98))):
        slab(a, 1.06, y0, 1.94, y1, (140 - 8 * i, 104 - 6 * i, 70 - 4 * i), r=0.008, lw=0.022, lo=0.82, hi=1.06, noise=0.14, seed=60 + i, freq=16.0, along="x")
    return a


def house_openings():
    # ---------------------------------------------------------- doors
    door_solid = {"closed": True, "open": False, "broken": False}
    prop("house", "door_front", 1, 1, lambda st, v: door_cell(st, v, "front"), facings=4, states=("closed", "open", "broken"), variants=2,
         tags=["door", "opening", "exterior"], layer="wall", solid=door_solid, pad=(0, 0, 0, 0), shadow=None, grain=0.01, bg=(150, 90, 70),
         note="A front door in a wall cell (replaces the wall cell: a full 128 px picture with its threshold floor and its frame). facing = the side "
              "the OUTSIDE is on (s: the wall runs along x with the street to the south; e: the wall runs along y with the street to the east). "
              "Variants are door styles (a: oxblood, hinged on the left of the frame as seen facing out; b: green, hinged on the right) and "
              "are the same in every state, so a door keeps its look when it is opened or broken. A closed door blocks; open and broken do not. "
              "Not a wall for wall_edges (the wall ends beside it get their outline).")
    prop("house", "door_interior", 1, 1, lambda st, v: door_cell(st, v, "int"), facings=4, states=("closed", "open"), variants=2,
         tags=["door", "opening", "interior"], layer="wall", solid={"closed": True, "open": False}, pad=(0, 0, 0, 0), shadow=None, grain=0.01, bg=(222, 216, 200),
         note="An inside door in a partition wall cell, same rules as door_front (facing: the side the door's front is on; a: white painted, hinged "
              "left; b: stained wood, hinged right). A doorway with no door needs no picture: leave a floor cell in the wall.")
    prop("house", "door_garage", 3, 1, garage_door, facings=4, states=("closed", "open", "broken"), variants=1,
         tags=["door", "opening", "exterior", "garage"], layer="wall", solid={"closed": True, "open": False, "broken": False}, pad=(0, 0, 0, 0), shadow=None,
         bg=(150, 90, 70),
         note="An overhead garage door, 3 cells wide (the wall run it replaces), facing the way the outside is (s: the wall runs along x). Picture "
              "3 x 1 tiles for s and n, 1 x 3 for e and w.")
    # ---------------------------------------------------------- windows
    prop("house", "window", 1, 1, window_overlay, facings="hv", states=("intact", "broken", "boarded"), variants=2,
         tags=["window", "opening", "overlay"], layer="wall", solid="all", pad=(0, 0, 0, 0), shadow=None, bg=(150, 90, 70),
         note="A window set into a wall top: laid OVER a wall cell (the wall fill and its edges stay underneath), h for a wall that runs along x, v "
              "for one that runs along y. The cell stays a wall (solid, and a wall for wall_edges) in every state; the sim decides who can see or "
              "climb through. Variants: a plain white frame, b wooden frame with curtains (curtains only while intact).")
    # ---------------------------------------------------------- steps and porch
    prop("house", "step", 3, 1, step_body, facings=4, variants=2, tags=["decor", "walkable", "step"], layer="decal", solid=[], bg=(98, 128, 66),
         note="The step in front of a door: 3 cells wide, 1 deep, laid on the ground cells outside the door, centred on it (a: concrete, b: wooden "
              "planks). Facing = the side it faces, away from the house (s: it lies south of a door in a wall that runs along x). Walkable.")
    prop("house", "porch", 3, 2, porch_body, facings=4, variants=1, tags=["decor", "walkable", "porch"], layer="decal", solid=[], bg=(98, 128, 66),
         note="A porch deck 3 x 2 cells in front of a door with a rail round its sides and the front, open in the middle for the steps. Facing = the "
              "side it faces, away from the house. Walkable. White rail. Its roof, if any, is a roof piece.")


# ======================================================================
# ROOF: shingle fills (lit and shaded slope), eaves, ridge caps, chimneys
# ======================================================================

ROOFS = {
    "terracotta": dict(label="Terracotta tiles", lit=(176, 108, 82), shade=(126, 78, 62), ridge=(172, 92, 62), fascia=(92, 64, 48)),
    "slate": dict(label="Slate", lit=(116, 124, 138), shade=(78, 86, 100), ridge=(66, 72, 84), fascia=(70, 62, 56)),
    "shingle": dict(label="Brown shingle", lit=(138, 102, 76), shade=(94, 68, 52), ridge=(98, 70, 52), fascia=(84, 62, 46)),
}


def roof_fill(kind, slope, variant):
    """128 px seamless roof tile. The slope runs along y (the ridge along x): the 'lit' one is the NORTH slope, the 'shade' one the south;
    turn them a quarter turn counter clockwise for a ridge along y (north becomes west, south east)."""
    n = PX
    spec = ROOFS[kind]
    base = np.array(spec[slope], np.float32)
    rng = rng_for("roof_" + kind)
    ys, xs = _yx()
    ys = ys.astype(np.int32)
    xs = xs.astype(np.int32)
    if kind == "terracotta":
        cw, ch = 32, 32
        col = xs // cw
        lx = xs % cw
        shift = (col % 2) * 16
        row = (ys + shift) // ch
        ly = (ys + shift) % ch
        tone = (0.88 + 0.24 * _hash2(row, col, 3))[..., None]
        prof = 0.78 + 0.34 * np.sin(np.pi * (lx + 0.5) / cw) + 0.10 * (1 - lx / cw)
        k = prof.copy()
        k[ly >= 27] *= 0.66
        k[(ly >= 22) & (ly < 27)] *= 1.06
        rgb = base * tone * k[..., None]
        rgb = rgb * (1 + 0.04 * pnoise(n, 7, rng)[..., None])
        gap = (lx < 1) | (lx >= cw - 1)
        rgb = np.where(gap[..., None], rgb * 0.55, rgb)
    elif kind == "slate":
        sh, sw = 16, 16
        row = ys // sh
        off = (row % 2) * (sw // 2)
        cx = (xs + off) % n
        col = cx // sw
        lx = cx % sw
        ly = ys % sh
        tone = (0.84 + 0.30 * _hash2(row, col, 5))[..., None]
        tint = np.array([[-6, 0, 6]], np.float32)[None] * (_hash2(row, col, 8) - 0.5)[..., None] * 2
        rgb = (base + tint) * tone
        k = np.ones((n, n), np.float32)
        k[ly >= sh - 3] *= 0.70
        k[ly == 0] *= 1.12
        k[(lx < 1) | (lx >= sw - 1)] *= 0.78
        rgb = rgb * k[..., None] * (1 + 0.04 * pnoise(n, 1.0, rng)[..., None] + 0.03 * pnoise(n, 9, rng)[..., None])
    else:
        sh, tw = 16, 32
        row = ys // sh
        off = (row % 2) * (tw // 2)
        cx = (xs + off) % n
        col = cx // tw
        lx = cx % tw
        ly = ys % sh
        tone = (0.90 + 0.20 * _hash2(row, col, 11))[..., None]
        rgb = base * tone
        k = np.ones((n, n), np.float32)
        k[ly >= sh - 3] *= 0.72
        k[ly == 0] *= 1.10
        notch = (lx < 2) & (ly >= 3)
        k[notch] *= 0.45
        rgb = rgb * k[..., None] * (1 + 0.06 * pnoise(n, 0.8, rng)[..., None] + 0.04 * pnoise(n, 8, rng)[..., None])
    g = Ground(rgb, n=n)
    if variant == 1:
        r2 = rng_for("roof_decal_" + kind)
        if kind == "terracotta":
            m = g.poly([(40, 30), (72, 26), (74, 56), (42, 60)])          # tiles gone: the felt and the battens
            g.lay(m, col3((52, 42, 34)) * (0.8 + 0.4 * pnoise(n, 2, r2)[..., None]), 1.0)
            for yy in (36, 46, 56):
                g.lay(g.line([(40, yy), (74, yy)], 2.0), (96, 74, 52), 0.8)
            g.lay(g.line([(40, 30), (72, 26), (74, 56), (42, 60), (40, 30)], 1.6), (30, 22, 18), 0.7)
        else:
            blotch(g, r2, 80, 80, 20, (84, 106, 56), 0.65)          # moss
            blotch(g, r2, 40, 36, 12, (30, 28, 26), 0.35)
            if kind == "shingle":
                g.lay(g.poly([(30, 70), (62, 70), (62, 86), (30, 86)]), (46, 38, 32), 0.9)      # a course missing
                g.lay(g.line([(30, 70), (62, 70)], 1.6), (24, 20, 18), 0.6)
    return finish_ground(g.rgb, "roof")


def roof_ridge(kind, orient):
    spec = ROOFS[kind]
    a = Art(1, 1)
    c = spec["ridge"]
    y0, y1 = 0.33, 0.67
    a.paint(a.blur(a.rect(0.0, y1 - 0.02, 1.0, y1 + 0.14), 0.04), (8, 6, 4), 0.40)          # shadow on the south slope
    a.paint(a.rect(0.0, y0, 1.0, y1), lit(c, 0.80, 1.12, 0, y0, 1, y1, 0.08, 6, 14, "x"))
    for i in range(4):               # cap tiles: a joint every quarter tile
        x = i * 0.25
        line(a, [(x, y0), (x, y1)], 0.012, shade(c, 0.55), 0.8, round_ends=False)
    a.paint(a.rect(0.0, y0, 1.0, y0 + 0.05), (255, 244, 224), 0.22)
    a.paint(a.rect(0.0, y1 - 0.06, 1.0, y1), (10, 8, 6), 0.20)
    line(a, [(0.0, y0), (1.0, y0)], 0.026, OUTLINE, 0.95, round_ends=False)
    line(a, [(0.0, y1), (1.0, y1)], 0.026, OUTLINE, 0.95, round_ends=False)
    if orient == "v":
        a.prem = np.ascontiguousarray(np.rot90(a.prem, -1, axes=(0, 1)))
        a.alpha = np.ascontiguousarray(np.rot90(a.alpha, -1, axes=(0, 1)))
    return a.image(grain=0.01, seed=3)


def roof_edges(kind):
    """16 cells of the eave on the OPEN sides of a roof cell: 1.75 x 1.75 tiles (224 px) with the cell at (0.25, 0.25): the roof reaches 0.2 tile
    beyond the cell on each open side, with its fascia, its outline and its shadow to the south and the east."""
    spec = ROOFS[kind]
    CELL = 224
    sheet = sheet_cells(4, 4, CELL, CELL)
    cells = {}
    ov = 0.20
    for idx in range(16):
        a = Art(1.75, 1.75)
        o = [bool(idx & 1), bool(idx & 2), bool(idx & 4), bool(idx & 8)]       # N E S W open
        cx0, cy0, cx1, cy1 = 0.25, 0.25, 1.25, 1.25
        ex0 = cx0 - (ov if o[3] else 0)
        ey0 = cy0 - (ov if o[0] else 0)
        ex1 = cx1 + (ov if o[1] else 0)
        ey1 = cy1 + (ov if o[2] else 0)
        if idx == 0:
            sheet.alpha_composite(a.image(), (0, 0))
            cells["0"] = [0, 0]
            continue
        ext = a.rect(ex0, ey0, ex1, ey1)
        inner = a.rect(cx0, cy0, cx1, cy1)
        ring = a.minus(ext, inner)
        # the shadow of the whole roof on what lies beyond (south and east only)
        sh = a.rect(ex0, ey0, ex1, ey1)
        shm = np.asarray(sh, np.float32) / 255.0
        a.shadow_under(0.07, 0.09, 0.05, 0.40, mask_of=shm)
        base = spec["lit"]
        a.paint(ring, lambda X, Y, b=base: np.array(b, np.float32)[None, None, :] * (0.80 + 0.06 * fbm(X, Y, 9.0, 4, 2))[..., None])
        # the underside of the overhang is a little darker, and the courses carry on
        a.paint(ring, (20, 14, 10), 0.14)
        for yy in np.arange(cy0 - ov, cy1 + ov, 0.25):
            a.paint(a.stroke([(ex0, yy), (ex1, yy)], 0.008, round_ends=False), shade(base, 0.6), 0.35, clip=ring)
        # a line where the wall is, and the fascia board along each open edge
        for flag, pts in ((o[0], [(ex0, ey0), (ex1, ey0)]), (o[2], [(ex0, ey1), (ex1, ey1)]), (o[3], [(ex0, ey0), (ex0, ey1)]), (o[1], [(ex1, ey0), (ex1, ey1)])):
            if flag:
                a.paint(a.stroke(pts, 0.052, round_ends=False), spec["fascia"], 1.0)
        for flag, pts in ((o[0], [(ex0, ey0 + 0.03), (ex1, ey0 + 0.03)]), (o[3], [(ex0 + 0.03, ey0), (ex0 + 0.03, ey1)])):
            if flag:
                a.paint(a.stroke(pts, 0.010, round_ends=False), (255, 236, 210), 0.35)
        a.paint(a.stroke([(ex0, ey0), (ex1, ey0), (ex1, ey1), (ex0, ey1)], 0.030, closed=True), OUTLINE, 1.0, clip=ring)
        for flag, pts in ((o[0], [(cx0, cy0), (cx1, cy0)]), (o[2], [(cx0, cy1), (cx1, cy1)]), (o[3], [(cx0, cy0), (cx0, cy1)]), (o[1], [(cx1, cy0), (cx1, cy1)])):
            if flag:
                a.paint(a.stroke(pts, 0.012, round_ends=False), (10, 8, 6), 0.35, clip=ring)
        iy0, iy1, ix0, ix1 = int(cy0 * S), int(cy1 * S), int(cx0 * S), int(cx1 * S)
        a.prem[iy0:iy1, ix0:ix1] = 0.0          # the cell itself is the roof's own fill: nothing of the eave (or its shadow) lies on it
        a.alpha[iy0:iy1, ix0:ix1] = 0.0
        sheet.alpha_composite(a.image(grain=0.01, seed=idx), ((idx % 4) * CELL, (idx // 4) * CELL))
        cells[str(idx)] = [idx % 4, idx // 4]
    atlas_item("roof", "roof_edge_" + kind, sheet, 4, 4, cells, (CELL, CELL), ["roof", "autotile", "overlay"], "roof",
               "The eave of a %s roof, laid on a roof cell over its fill: cell index = mask of the OPEN sides (the neighbour is not roof): N 1 + E 2 + S 4 + W 8; "
               "col = index %% 4, row = index // 4. A cell is 224 px = 1.75 tiles with the roof cell at (0.25, 0.25) tiles, so lay the cell's picture with its "
               "top left 0.25 tile up and left of the roof cell. The roof reaches 0.2 tile past the cell on every open side (over the wall below), with "
               "fascia, outline and a soft shadow to the south and east." % spec["label"].lower(), bg=(98, 128, 66), mode="sprite", anchor=(0.25, 0.25))


def chimney(state, v):
    a = Art(1, 1)
    if v == 0:
        slab(a, 0.10, 0.10, 0.90, 0.90, (150, 86, 68), r=0.02, lw=0.03, lo=0.80, hi=1.1, noise=0.10, seed=70, freq=10.0)
        for yy in np.arange(0.18, 0.90, 0.10):
            line(a, [(0.11, yy), (0.89, yy)], 0.008, (190, 176, 154), 0.6, round_ends=False)
        for yy in np.arange(0.18, 0.90, 0.20):
            for xx in (0.30, 0.55, 0.78):
                line(a, [(xx, yy), (xx, yy + 0.10)], 0.008, (190, 176, 154), 0.5, round_ends=False)
    else:
        slab(a, 0.10, 0.10, 0.90, 0.90, (146, 142, 134), r=0.02, lw=0.03, lo=0.80, hi=1.1, noise=0.14, seed=71, freq=8.0)
        for yy in (0.30, 0.50, 0.70):
            line(a, [(0.11, yy), (0.89, yy)], 0.010, (90, 86, 78), 0.6, round_ends=False)
    slab(a, 0.22, 0.22, 0.78, 0.78, (176, 172, 162), r=0.02, lw=0.028, lo=0.86, hi=1.1, noise=0.06, seed=72, freq=8.0)
    slab(a, 0.34, 0.34, 0.66, 0.66, (30, 26, 24), r=0.02, lw=0.022, lo=0.9, hi=1.1, rim=False)
    a.paint(a.blur(a.rect(0.37, 0.37, 0.63, 0.63), 0.025), (4, 3, 2), 0.7)
    return a


def job_roof():
    for kind, spec in ROOFS.items():
        sprites = []
        for slope in ("lit", "shade"):
            for v in range(2):
                rec = put("roof/roof_%s_%s_%s.png" % (kind, slope, "ab"[v]), roof_fill(kind, slope, v), "opaque")
                rec["slope"] = slope
                rec["variant"] = v
                sprites.append(rec)
        ridges = put_atlas("roof/roof_%s_ridge.png" % kind, [(roof_ridge(kind, o), {"orient": o}) for o in ("h", "v")], "sprite")
        add_item("roof", {"id": "roof_" + kind, "category": "roof", "kind": "roof_fill", "layer": "roof", "footprint": [1, 1], "anchor": [0, 0],
                          "variants": 2, "slopes": ["lit", "shade"], "tags": ["roof", "hideable", "walkable"], "sprites": sprites, "name": spec["label"],
                          "ridge": ridges, "edges": "roof_edge_" + kind, "_bg": (98, 128, 66),
                          "note": "%s: seamless 128 px roof tiles. For a gable roof with its ridge along x the north slope uses `lit` and the south slope `shade`; "
                                  "for a ridge along y turn the pictures a quarter turn counter clockwise (west lit, east shade). Variant b has a decal (moss, "
                                  "missing tiles): use it for about one cell in eight. `ridge` is a cap strip (1 x 1 cell, the strip in the middle third) laid "
                                  "along the ridge line; for an even number of rows the ridge falls on the line between two rows: lay it half a tile off. "
                                  "`edges` is the eave overlay set to lay on the border cells." % spec["label"]})
        roof_edges(kind)
    prop("roof", "chimney", 1, 1, chimney, facings=1, variants=2, tags=["roof", "hideable", "solid"], layer="roof", bg=(98, 128, 66),
         note="A chimney stack seen from above (a: brick, b: stone), one cell, set on a roof cell near the ridge. It belongs to the roof layer: hidden with it.")
    contact("roof", scale=0.9, bg=(98, 128, 66))


# ======================================================================
# FLOORS: 4 x 4 atlases of 64 px pieces, worn, low contrast
# ======================================================================

def wood_floor(variant, along="x", base=None):
    rng = rng_for("floor_wood", variant)
    base = base or [(162, 122, 84), (112, 80, 56), (118, 92, 70)][variant]
    n = GA
    rgb = np.zeros((n, n, 3), np.float32) + col3(base)
    pb = 16
    # boards in rows along x; each row is cut into planks of 2..3.5 tiles, the joints staggered
    kk = np.ones((n, n), np.float32)
    joint = np.zeros((n, n), np.float32)
    nails = []
    for r in range(n // pb):
        x = int(rng.integers(0, n))
        pos = x
        while pos < x + n:
            ln = int(rng.integers(100, 210))
            ln = min(ln, x + n - pos)
            tone = 1.0 + rng.uniform(-0.07, 0.07)
            for xx in range(pos, pos + ln):
                kk[r * pb:(r + 1) * pb, xx % n] = tone
            joint[r * pb + 1:(r + 1) * pb, pos % n] = 1.0
            for nx_ in (pos + 4, pos + ln - 5):
                nails.append((nx_ % n, r * pb + (4 if rng.random() < 0.5 else 11)))
            pos += ln
    gap = np.zeros((n, n), np.float32)
    for r in range(n // pb):
        gap[r * pb, :] = 1.0
    grain = pnoise(n, 1.0, rng, sx=26, sy=0.7)
    rgb = rgb * kk[..., None] * (1 + 0.06 * grain[..., None] + 0.04 * pnoise(n, 18, rng)[..., None])
    rgb = rgb * (1 - 0.45 * gap[..., None]) * (1 - 0.40 * joint[..., None])
    # a highlight just under the gap: the board's top edge
    hl = np.roll(gap, 1, 0)
    rgb = rgb * (1 + 0.10 * hl[..., None])
    g = Ground(rgb, n=n)
    g.sprinkle([(x + 0.5, y + 0.5, 0.8, 0.8, (40, 28, 20), 0.8) for x, y in nails])
    # wear: pale scuffs along the grain, water stains
    segs = []
    for _ in range(40):
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        segs.append(((x, y), (x + rng.uniform(6, 22), y + rng.uniform(-1, 1))))
    g.strokes(segs, 1.2, tuple(np.clip(np.array(base) * 1.3, 0, 255)), 0.28)
    for _ in range(3):
        blotch(g, rng, rng.uniform(20, n - 20), rng.uniform(20, n - 20), rng.uniform(12, 24), tuple(np.array(base) * 0.62), 0.32)
    out = g.rgb
    if along == "y":
        out = np.ascontiguousarray(np.rot90(out, 1))
    return finish_ground(out, "wood")


def lino_floor(variant):
    rng = rng_for("floor_lino", variant)
    n = GA
    a, b = [((178, 186, 164), (192, 194, 174)), ((196, 188, 164), (180, 164, 136))][variant]
    sw = pnoise(n, 9, rng)
    mix_ = smooth(sw + 0.5 * pnoise(n, 3, rng), -0.3, 0.5)[..., None]
    rgb = col3(a) * (1 - mix_) + col3(b) * mix_
    rgb = rgb * (1 + 0.02 * pnoise(n, 0.8, rng)[..., None])
    g = Ground(rgb, n=n)
    g.sprinkle([(rng.uniform(0, n), rng.uniform(0, n), 0.9, 0.7, (110, 100, 80) if rng.random() < 0.6 else (236, 232, 214), 0.40) for _ in range(300)])
    # seams every two tiles, and the wear in front of the cooker: a darker trodden line along the middle, scuffs, spills
    for i in range(2):
        x = i * 128
        g.lay(g.line([(x, 0), (x, n)], 1.2), (92, 88, 74), 0.35, keep_inner=False)
    for _ in range(4):
        blotch(g, rng, rng.uniform(20, n - 20), rng.uniform(20, n - 20), rng.uniform(7, 15), (96, 80, 56), 0.30)
    segs = [((x, y), (x + rng.uniform(-7, 7), y + rng.uniform(-7, 7))) for x, y in ((rng.uniform(0, n), rng.uniform(0, n)) for _ in range(30))]
    g.strokes(segs, 1.3, (92, 86, 70), 0.30)
    return finish_ground(g.rgb, "lino")


def carpet_floor(variant):
    rng = rng_for("floor_carpet", variant)
    n = GA
    base = [(98, 110, 128), (144, 106, 102)][variant]
    fibre = rng.standard_normal((n, n)).astype(np.float32)
    fibre = (fibre + 0.6 * (np.roll(fibre, 1, 0) + np.roll(fibre, -1, 1))) / 2.2
    rgb = col3(base) * (1 + 0.032 * fibre[..., None] + 0.04 * pnoise(n, 20, rng)[..., None] + 0.03 * pnoise(n, 5, rng)[..., None])
    g = Ground(rgb, n=n)
    for _ in range(3):
        blotch(g, rng, rng.uniform(20, n - 20), rng.uniform(20, n - 20), rng.uniform(8, 18), tuple(np.array(base) * 0.62), 0.38)
    for _ in range(2):
        blotch(g, rng, rng.uniform(20, n - 20), rng.uniform(20, n - 20), rng.uniform(14, 26), tuple(np.array(base) * 1.18), 0.25)
    # a trodden path of flattened pile, and a pale line where a door has scraped
    segs = [((x, y), (x + rng.uniform(4, 14), y + rng.uniform(-2, 2))) for x, y in ((rng.uniform(0, n), rng.uniform(0, n)) for _ in range(40))]
    g.strokes(segs, 1.0, tuple(np.clip(np.array(base) * 1.2, 0, 255)), 0.25)
    return finish_ground(g.rgb, "carpet")


def bath_floor(variant):
    rng = rng_for("floor_bath", variant)
    n = GA
    base = [(172, 194, 198), (206, 204, 194)][variant]
    ts = 16
    ys, xs = np.mgrid[0:n, 0:n]
    tx, ty = xs // ts, ys // ts
    tone = (0.96 + 0.07 * mba._hash(tx.astype(np.int64), ty.astype(np.int64), 5))[..., None]
    rgb = col3(base) * tone * (1 + 0.025 * pnoise(n, 10, rng)[..., None])
    lx, ly = xs % ts, ys % ts
    grout = (lx == 0) | (ly == 0)
    gcol = col3((146, 148, 140)) * (0.9 + 0.2 * pnoise(n, 3, rng)[..., None])
    rgb = np.where(grout[..., None], gcol, rgb)
    hi = ((lx == 1) | (ly == 1)) & ~grout
    rgb = np.where(hi[..., None], rgb * 1.07, rgb)
    lo = ((lx == ts - 1) | (ly == ts - 1)) & ~grout
    rgb = np.where(lo[..., None], rgb * 0.93, rgb)
    g = Ground(rgb, n=n)
    for _ in range(3):
        blotch(g, rng, rng.uniform(20, n - 20), rng.uniform(20, n - 20), rng.uniform(10, 20), (118, 130, 110), 0.28)
    for _ in range(4):
        x, y = rng.uniform(24, n - 24), rng.uniform(24, n - 24)
        crack_tree(rng, g, (x, y), rng.uniform(0, 6.28), rng.uniform(10, 22), 1.0, 0, dark=(70, 72, 66), op=0.7, hi=(240, 240, 232), hiop=0.3)
    return finish_ground(g.rgb, "bath")


def runner_floor(along):
    base = wood_floor(1, "x", base=(106, 80, 58))
    rng = rng_for("floor_runner")
    n = GA
    rgb = np.asarray(base, np.float32)
    g = Ground(rgb, n=n)
    for ty in range(4):
        y0 = ty * GP
        body = [(0, y0 + 13), (n, y0 + 13), (n, y0 + 51), (0, y0 + 51)]
        g.lay(g.line([(0, y0 + 32), (n, y0 + 32)], 40), (10, 8, 6), 0.20, keep_inner=False)
        m = np.zeros((n, n), np.float32)
        m[y0 + 12:y0 + 52, :] = 1.0
        wv = 1 + 0.05 * rng.standard_normal((n, n)).astype(np.float32)
        col = col3((120, 52, 52)) * wv[..., None] * (1 + 0.05 * pnoise(n, 6, rng)[..., None])
        g.lay(m, col, 1.0, keep_inner=False)
        for (yy, w, c) in ((y0 + 14.5, 2.0, (222, 202, 160)), (y0 + 49.5, 2.0, (222, 202, 160)), (y0 + 18.5, 1.0, (190, 160, 110)), (y0 + 45.5, 1.0, (190, 160, 110))):
            g.lay(g.line([(0, yy), (n, yy)], w), c, 0.95, keep_inner=False)
        g.lay(g.line([(0, y0 + 12), (n, y0 + 12)], 1.0), (40, 24, 20), 0.8, keep_inner=False)
        g.lay(g.line([(0, y0 + 52), (n, y0 + 52)], 1.0), (40, 24, 20), 0.8, keep_inner=False)
        # a diamond lozenge every half tile
        for xx in range(16, n, 32):
            g.lay(g.poly([(xx, y0 + 32), (xx + 8, y0 + 26), (xx + 16, y0 + 32), (xx + 8, y0 + 38)]), (170, 130, 90), 0.8, keep_inner=False)
    out = g.rgb
    if along == "y":
        out = np.ascontiguousarray(np.rot90(out, 1))
    return finish_ground(out, "runner")


def job_floor():
    ground_item("floor", "floor_wood", ["floor", "wood", "indoor"], [("floor/wood_%s.png" % "ab"[v], wood_floor(v)) for v in range(2)],
                "Wood boards for living rooms, bedrooms and halls: 4 x 4 atlas of 64 px pieces, boards along x, joints staggered, nail heads, scuffs and water "
                "stains. a: oak, b: dark walnut. Turn the pieces a quarter turn for boards along y.", bg=(120, 90, 60))
    ground_item("floor", "floor_hall", ["floor", "wood", "indoor", "hall"], [("floor/hall_a.png", wood_floor(2, "x", (118, 92, 70)))],
                "Hallway boards: a greyer, more worn wood than floor_wood; 4 x 4 atlas of 64 px pieces.", bg=(120, 90, 60))
    ground_item("floor", "floor_runner_h", ["floor", "wood", "indoor", "hall", "runner"], [("floor/runner_h.png", runner_floor("x"))],
                "A hallway floor with a runner rug along x down the middle of every cell row (a 1 cell wide hall is one runner; a 2 wide hall gets two): "
                "4 x 4 atlas of 64 px pieces.", bg=(120, 90, 60))
    ground_item("floor", "floor_runner_v", ["floor", "wood", "indoor", "hall", "runner"], [("floor/runner_v.png", runner_floor("y"))],
                "The same with the runner along y.", bg=(120, 90, 60))
    ground_item("floor", "floor_kitchen", ["floor", "lino", "indoor"], [("floor/kitchen_%s.png" % "ab"[v], lino_floor(v)) for v in range(2)],
                "Kitchen linoleum, marbled and worn: 4 x 4 atlas of 64 px pieces; a: sage and cream, b: sand and brown.", bg=(180, 180, 160))
    ground_item("floor", "floor_carpet", ["floor", "carpet", "indoor"], [("floor/carpet_%s.png" % "ab"[v], carpet_floor(v)) for v in range(2)],
                "Bedroom carpet with a worn path and stains: 4 x 4 atlas of 64 px pieces; a: grey blue, b: dusty rose.", bg=(120, 110, 110))
    ground_item("floor", "floor_bath", ["floor", "tile", "indoor"], [("floor/bath_%s.png" % "ab"[v], bath_floor(v)) for v in range(2)],
                "Bathroom tile, small tiles (a quarter cell) with dirty grout, cracks and damp stains: 4 x 4 atlas of 64 px pieces; a: pale blue, b: off white.", bg=(180, 190, 190))
    contact("floor", scale=1.0, bg=(110, 100, 90))


# ======================================================================
# FURNITURE AND CONTAINERS (seen from above; the front edge shows as a darker lip: handles, doors, seams)
# ======================================================================

WOOD_L, WOOD_M, WOOD_D = (186, 148, 104), (150, 110, 74), (106, 76, 54)
WHITE_C = (228, 226, 218)
FAB = {"slate": (92, 110, 132), "brick": (148, 84, 74), "olive": (122, 126, 84), "cream": (206, 190, 150), "mustard": (190, 150, 70)}


def cab(a, x0, y0, x1, y1, top, front=None, doors=1, opened=False, lip=0.13, noise=0.06, seed=1, r=0.04, along="x", handle="bar", hinge="split",
        drawers=False):
    """A box with a front: the top (lit), a darker front lip along the south edge with its door seams and handles; opened = the doors (or the
    drawer) ajar, the dark inside showing."""
    front = front or shade(top, 0.74)
    yt = y1 - lip
    pts = rrect(x0, y0, x1, y1, r)
    a.paint(a.poly(pts), lit(front, 0.84, 1.04, x0, yt, x1, y1))
    a.paint(a.poly(rrect(x0, y0, x1, yt + 0.01, r * 0.8)), lit(top, 0.84, 1.10, x0, y0, x1, y1, noise, seed, 12.0, along))
    a.paint(a.stroke([(x0 + 0.03, y0 + 0.025), (x1 - 0.03, y0 + 0.025)], 0.012, round_ends=False), (255, 250, 235), 0.28)
    a.paint(a.stroke([(x0 + 0.01, yt + 0.005), (x1 - 0.01, yt + 0.005)], 0.012, round_ends=False), (10, 8, 6), 0.35)
    w = x1 - x0
    dw = w / doors
    if opened and not drawers:
        a.paint(a.rect(x0 + 0.03, yt + 0.02, x1 - 0.03, y1 - 0.015), (16, 12, 10), 0.92)
        for i in range(doors):
            dx0, dx1 = x0 + i * dw, x0 + (i + 1) * dw
            if hinge == "split":
                outer_left = i < doors / 2.0
            else:
                outer_left = hinge == "left"
            hx = dx0 + 0.02 if outer_left else dx1 - 0.02
            sg = 1 if outer_left else -1
            ex, ey = hx + sg * (dw - 0.08) * 0.90, y1 + 0.095
            leaf = [(hx, y1 - 0.025), (ex, ey), (ex, ey + 0.035), (hx, y1 + 0.005)]
            a.paint(a.poly(leaf), lit(shade(front, 1.12), 0.85, 1.1, 0, 0, 1, 1))
            a.paint(a.stroke(leaf, 0.016, closed=True), OUTLINE, 0.95)
    elif drawers:
        # the front shows drawer fronts: a seam each and a knob
        for i in range(1, doors):
            xx = x0 + i * dw
            a.paint(a.stroke([(xx, yt + 0.01), (xx, y1 - 0.005)], 0.012, round_ends=False), (10, 8, 6), 0.55)
        for i in range(doors):
            cx_ = x0 + (i + 0.5) * dw
            dot(a, cx_, y1 - lip / 2.0 + 0.004, 0.017, (60, 50, 44))
            dot(a, cx_ - 0.004, y1 - lip / 2.0, 0.008, (222, 204, 160), 0.8)
        if opened:     # the first drawer pulled out: its front proud of the cabinet, a cloth hanging from it
            dx0, dx1 = x0 + 0.03, x0 + dw - 0.03
            a.paint(a.rect(dx0, yt + 0.02, dx1, y1), (16, 12, 10), 0.95)
            leaf = rrect(dx0, y1 - 0.03, dx1, y1 + 0.10, 0.015, 3)
            a.paint(a.poly(leaf), lit(shade(front, 1.18), 0.85, 1.1, dx0, y1, dx1, y1 + 0.1))
            a.paint(a.stroke(leaf, 0.018, closed=True), OUTLINE, 0.95)
            dot(a, (dx0 + dx1) / 2, y1 + 0.04, 0.016, (222, 204, 160))
            a.paint(a.poly([(dx0 + 0.08, yt + 0.03), (dx0 + 0.30, yt + 0.02), (dx0 + 0.34, y1 - 0.02), (dx0 + 0.10, y1 - 0.01)]), (178, 166, 150), 0.95)
    else:
        for i in range(1, doors):
            xx = x0 + i * dw
            a.paint(a.stroke([(xx, yt + 0.01), (xx, y1 - 0.005)], 0.012, round_ends=False), (10, 8, 6), 0.55)
        for i in range(doors):
            hx = x0 + (i + 0.5) * dw
            if doors == 1:
                hx = x1 - 0.18 if hinge != "left" else x0 + 0.18
            elif doors > 1:
                hx = x0 + (i + (0.82 if i < doors / 2.0 else 0.18)) * dw
            if handle == "bar":
                a.paint(a.rect(hx - 0.045, y1 - lip + 0.035, hx + 0.045, y1 - lip + 0.065), (70, 70, 72), 0.95)
            else:
                dot(a, hx, y1 - lip / 2.0, 0.016, (60, 50, 44))
    a.paint(a.stroke(pts, 0.028, closed=True), OUTLINE, 1.0)


def fridge(st, v):
    a = body(1, 1)
    c = [(226, 226, 220), (214, 206, 180)][v]
    op = st == "opened"
    x0, y0, x1, y1 = 0.10, 0.07, 0.90, 0.90
    pts = rrect(x0, y0, x1, y1, 0.05)
    a.paint(a.poly(pts), lit(shade(c, 0.78), 0.84, 1.04, x0, 0.77, x1, y1))
    a.paint(a.poly(rrect(x0, y0, x1, 0.80, 0.045)), lit(c, 0.84, 1.10, x0, y0, x1, 0.8, 0.02, 4, 10))
    a.paint(a.stroke([(x0 + 0.03, y0 + 0.025), (x1 - 0.03, y0 + 0.025)], 0.012, round_ends=False), (255, 255, 250), 0.45)
    a.paint(a.stroke([(x0 + 0.01, 0.805), (x1 - 0.01, 0.805)], 0.012, round_ends=False), (10, 8, 6), 0.35)
    a.paint(a.rect(x0 + 0.06, 0.26, x1 - 0.06, 0.285), shade(c, 0.74), 0.9)           # the freezer's line over the top
    a.paint(a.stroke(pts, 0.028, closed=True), OUTLINE, 1.0)
    if not op:
        for hx in (0.28, 0.70):
            a.paint(a.rect(hx - 0.02, 0.815, hx + 0.02, 0.88), (96, 98, 102), 0.95)
    else:
        a.paint(a.rect(x0 + 0.03, 0.82, x1 - 0.03, y1 - 0.02), (200, 214, 222), 0.95)
        leaf = [(x1 - 0.03, y1 - 0.02), (x1 - 0.74, y1 + 0.095), (x1 - 0.74, y1 + 0.135), (x1 - 0.03, y1 + 0.01)]
        a.paint(a.poly(leaf), lit(c, 0.9, 1.1, 0, 0, 1, 1))
        a.paint(a.stroke(leaf, 0.018, closed=True), OUTLINE, 0.95)
    return a


def counter(st, v):
    a = body(1, 1)
    top = [(196, 184, 160), (168, 176, 170)][v]
    cab(a, 0.06, 0.08, 0.94, 0.92, top, front=(138, 102, 70), doors=2, opened=(st == "opened"), noise=0.05, seed=5 + v, lip=0.14, r=0.03)
    if v == 0:      # a chopping board with a knife and a loaf's end
        a.paint(a.poly(rrect(0.20, 0.22, 0.62, 0.56, 0.03)), (178, 138, 92), 1.0)
        a.paint(a.stroke(rrect(0.20, 0.22, 0.62, 0.56, 0.03), 0.014, closed=True), OUTLINE, 0.9)
        a.paint(a.stroke([(0.66, 0.30), (0.84, 0.60)], 0.034), (196, 200, 204), 1.0)
        a.paint(a.stroke([(0.78, 0.50), (0.84, 0.60)], 0.040), (70, 50, 38), 1.0)
    else:           # a pot and a plate
        disc(a, 0.34, 0.40, 0.17, (74, 78, 84), lw=0.022)
        disc(a, 0.34, 0.40, 0.11, (40, 42, 46), lw=0.0)
        a.paint(a.stroke([(0.50, 0.40), (0.70, 0.36)], 0.036), (60, 56, 52), 1.0)
        disc(a, 0.72, 0.62, 0.13, (230, 228, 220), lw=0.020, lo=0.9)
    return a


def counter_sink(st, v):
    a = body(1, 1)
    cab(a, 0.06, 0.08, 0.94, 0.92, (196, 184, 160), front=(138, 102, 70), doors=2, noise=0.05, seed=9, lip=0.14, r=0.03)
    slab(a, 0.16, 0.20, 0.76, 0.66, (178, 184, 190), r=0.05, lw=0.024, lo=0.80, hi=1.10)
    slab(a, 0.22, 0.26, 0.70, 0.60, (132, 140, 148), r=0.04, lw=0.012, lo=0.80, hi=1.10, rim=False)
    dot(a, 0.46, 0.43, 0.02, (36, 38, 40))
    a.paint(a.rect(0.40, 0.10, 0.52, 0.16), (200, 204, 208), 1.0)
    a.paint(a.stroke([(0.46, 0.16), (0.46, 0.28)], 0.030), (200, 204, 208), 1.0)
    a.paint(a.stroke([(0.46, 0.16), (0.46, 0.28)], 0.030), OUTLINE, 0.0)
    for yy in (0.28, 0.36, 0.44, 0.52):         # the draining board
        line(a, [(0.80, yy), (0.90, yy)], 0.012, (120, 126, 130), 0.8, round_ends=False)
    return a


def stove(st, v):
    a = body(1, 1)
    c = [(224, 222, 214), (60, 60, 64)][v]
    x0, y0, x1, y1 = 0.08, 0.08, 0.92, 0.92
    cab(a, x0, y0, x1, y1, c, front=shade(c, 0.78), doors=1, lip=0.14, noise=0.0, r=0.04, handle="knob")
    for (bx, by, r_) in ((0.32, 0.30, 0.13), (0.68, 0.30, 0.11), (0.32, 0.62, 0.11), (0.68, 0.62, 0.13)):
        disc(a, bx, by, r_, (50, 50, 54), lw=0.020, lo=0.85)
        disc(a, bx, by, r_ * 0.55, (28, 28, 30), lw=0.0)
        a.paint(a.stroke([(bx + r_ * 0.55 * np.cos(t), by + r_ * 0.55 * np.sin(t)) for t in np.linspace(0, 6.3, 20)], 0.008, closed=True), (110, 108, 104), 0.7)
    for kx in (0.22, 0.42, 0.62, 0.80):
        dot(a, kx, 0.855, 0.020, (28, 28, 30))
        dot(a, kx - 0.005, 0.85, 0.008, (210, 210, 205), 0.8)
    a.paint(a.rect(0.30, 0.18, 0.70, 0.22), (10, 8, 6), 0.0)
    return a


def cupboard(st, v):
    a = body(1, 1)
    top = [WOOD_M, (214, 210, 198)][v]
    cab(a, 0.08, 0.06, 0.92, 0.92, top, front=shade(top, 0.76), doors=2, opened=(st == "opened"), lip=0.15, noise=0.12, seed=15 + v, r=0.03)
    a.paint(a.stroke(rrect(0.16, 0.14, 0.84, 0.70, 0.02), 0.012, closed=True), shade(top, 0.62), 0.7)     # the cornice
    return a


def wardrobe(st, v):
    a = body(2, 1)
    top = [WOOD_M, (210, 208, 198)][v]
    cab(a, 0.06, 0.06, 1.94, 0.92, top, front=shade(top, 0.76), doors=2, opened=(st == "opened"), lip=0.16, noise=0.12, seed=21 + v, r=0.03, handle="knob")
    a.paint(a.stroke(rrect(0.16, 0.14, 1.84, 0.70, 0.02), 0.012, closed=True), shade(top, 0.62), 0.7)
    a.paint(a.stroke([(1.0, 0.14), (1.0, 0.70)], 0.012, round_ends=False), shade(top, 0.62), 0.5)
    return a


def dresser(st, v):
    a = body(2, 1)
    top = [WOOD_M, WOOD_D][v]
    cab(a, 0.06, 0.12, 1.94, 0.92, top, front=shade(top, 0.78), doors=3, opened=(st == "opened"), drawers=True, lip=0.16, noise=0.12, seed=25 + v, r=0.03)
    # a doily with a trinket, a photo in a frame
    a.paint(a.poly(rrect(0.50, 0.26, 1.02, 0.60, 0.04)), (232, 226, 210), 0.95)
    disc(a, 0.76, 0.43, 0.075, (150, 120, 70), lw=0.016)
    a.paint(a.poly(rrect(1.28, 0.22, 1.62, 0.34, 0.01)), (60, 46, 36), 1.0)
    a.paint(a.rect(1.31, 0.24, 1.59, 0.32), (160, 150, 130), 1.0)
    return a


def nightstand(st, v):
    a = body(1, 1)
    cab(a, 0.14, 0.14, 0.86, 0.88, WOOD_M, doors=1, drawers=True, opened=(st == "opened"), lip=0.16, noise=0.10, seed=31, r=0.03)
    if v == 0:      # a lamp
        disc(a, 0.42, 0.40, 0.17, (236, 222, 184), lw=0.022, lo=0.86)
        disc(a, 0.42, 0.40, 0.07, (255, 246, 214), lw=0.0)
    else:           # a clock and a book
        a.paint(a.poly(rrect(0.24, 0.24, 0.44, 0.40, 0.02)), (50, 52, 56), 1.0)
        a.paint(a.stroke(rrect(0.24, 0.24, 0.44, 0.40, 0.02), 0.012, closed=True), OUTLINE, 0.9)
        a.paint(a.rect(0.28, 0.28, 0.40, 0.34), (190, 60, 50), 0.9)
        a.paint(a.poly(rrect(0.50, 0.30, 0.76, 0.62, 0.015)), (96, 70, 52), 1.0)
        a.paint(a.stroke(rrect(0.50, 0.30, 0.76, 0.62, 0.015), 0.012, closed=True), OUTLINE, 0.9)
    return a


BLANKETS = [(92, 124, 150), (150, 86, 80), (116, 140, 96), (214, 198, 156)]


def bed(w, v):
    h = 2.0
    a = body(w, h)
    frame = WOOD_D
    slab(a, 0.05, 0.04, w - 0.05, h - 0.04, frame, r=0.05, lw=0.03, lo=0.84, hi=1.10, noise=0.10, seed=41)
    # the headboard (north) and a lower footboard
    a.paint(a.poly(rrect(0.05, 0.04, w - 0.05, 0.22, 0.04)), lit(shade(frame, 0.82), 0.84, 1.1, 0, 0, 1, 1))
    a.paint(a.stroke(rrect(0.05, 0.04, w - 0.05, 0.22, 0.04), 0.02, closed=True), OUTLINE, 0.9)
    # mattress and sheet
    mx0, mx1, my0, my1 = 0.13, w - 0.13, 0.20, h - 0.12
    a.paint(a.poly(rrect(mx0, my0, mx1, my1, 0.05)), lit((232, 228, 214), 0.88, 1.06, mx0, my0, mx1, my1))
    a.paint(a.stroke(rrect(mx0, my0, mx1, my1, 0.05), 0.016, closed=True), OUTLINE, 0.8)
    # the blanket over the lower two thirds, folded back at its top
    c = BLANKETS[v % 4]
    by0 = 0.78
    a.paint(a.poly(rrect(mx0 + 0.01, by0, mx1 - 0.01, my1 - 0.01, 0.04)), lit(c, 0.80, 1.14, mx0, by0, mx1, my1, 0.10, 44 + v, 10.0))
    a.paint(a.rect(mx0 + 0.01, by0, mx1 - 0.01, by0 + 0.12), shade(c, 1.15), 0.95)
    a.paint(a.stroke([(mx0 + 0.01, by0 + 0.12), (mx1 - 0.01, by0 + 0.12)], 0.012, round_ends=False), (10, 8, 6), 0.35)
    a.paint(a.stroke([(mx0 + 0.01, by0), (mx1 - 0.01, by0)], 0.012, round_ends=False), (255, 250, 235), 0.30)
    for i in range(1, int(w * 3)):          # stripes of the weave
        xx = mx0 + 0.01 + i * (mx1 - mx0 - 0.02) / (w * 3)
        a.paint(a.stroke([(xx, by0 + 0.14), (xx, my1 - 0.03)], 0.012, round_ends=False), shade(c, 0.86), 0.45)
    # soft creases
    for (cx0, cy0, cx1, cy1) in ((mx0 + 0.15, by0 + 0.40, mx1 - 0.2, by0 + 0.46), (mx0 + 0.1, by0 + 0.80, mx1 - 0.3, by0 + 0.86)):
        a.paint(a.blur(a.stroke([(cx0, cy0), (cx1, cy1)], 0.05), 0.02), (10, 8, 6), 0.16)
    a.paint(a.stroke(rrect(mx0 + 0.01, by0, mx1 - 0.01, my1 - 0.01, 0.04), 0.016, closed=True), OUTLINE, 0.7)
    # pillows
    npil = 2 if w > 1.5 else 1
    for i in range(npil):
        cx = w * (i + 0.5) / npil
        pw = 0.78 if w > 1.5 else 0.60
        px0, px1, py0, py1 = cx - pw / 2, cx + pw / 2, 0.28, 0.66
        a.paint(a.blur(a.poly(rrect(px0 + 0.02, py0 + 0.03, px1 + 0.02, py1 + 0.03, 0.08)), 0.015), (8, 6, 4), 0.28)
        a.paint(a.poly(rrect(px0, py0, px1, py1, 0.08)), lit((244, 242, 234), 0.86, 1.06, px0, py0, px1, py1))
        a.paint(a.stroke(rrect(px0, py0, px1, py1, 0.08), 0.018, closed=True), OUTLINE, 0.85)
        a.paint(a.stroke([(px0 + 0.10, (py0 + py1) / 2), (px1 - 0.10, (py0 + py1) / 2)], 0.010), (170, 166, 154), 0.45)
    return a


def bed_single(st, v):
    return bed(1, v)


def bed_double(st, v):
    return bed(2, v + 1)


def seat(w, v, arms=True):
    """A sofa or an armchair, back to the north: backrest, arms, cushions."""
    a = body(w, 1)
    c = list(FAB.values())[v % 5]
    dark = shade(c, 0.72)
    slab(a, 0.05, 0.08, w - 0.05, 0.94, dark, r=0.07, lw=0.03, lo=0.86, hi=1.08, noise=0.06, seed=51 + v)
    # backrest
    a.paint(a.poly(rrect(0.07, 0.10, w - 0.07, 0.36, 0.06)), lit(shade(c, 0.94), 0.84, 1.12, 0, 0.1, w, 0.36, 0.05, 52 + v, 14.0))
    a.paint(a.stroke([(0.12, 0.34), (w - 0.12, 0.34)], 0.012, round_ends=False), (10, 8, 6), 0.35)
    # cushions
    n = max(1, int(round(w - 0.6))) if w > 1 else 1
    ax = 0.22 if arms else 0.08
    cw = (w - 2 * ax) / n
    for i in range(n):
        x0 = ax + i * cw + 0.012
        x1 = ax + (i + 1) * cw - 0.012
        a.paint(a.blur(a.poly(rrect(x0 + 0.015, 0.40, x1 + 0.015, 0.90, 0.05)), 0.012), (8, 6, 4), 0.20)
        a.paint(a.poly(rrect(x0, 0.37, x1, 0.88, 0.05)), lit(c, 0.84, 1.12, x0, 0.37, x1, 0.88, 0.07, 53 + v + i, 12.0))
        a.paint(a.stroke(rrect(x0, 0.37, x1, 0.88, 0.05), 0.016, closed=True), OUTLINE, 0.75)
        dot(a, (x0 + x1) / 2, 0.62, 0.014, shade(c, 0.6), 0.9)
    if arms:
        for xa in (0.07, w - 0.07 - 0.15):
            a.paint(a.poly(rrect(xa, 0.12, xa + 0.15, 0.90, 0.05)), lit(shade(c, 0.90), 0.84, 1.1, xa, 0.12, xa + 0.15, 0.9, 0.05, 54 + v))
            a.paint(a.stroke(rrect(xa, 0.12, xa + 0.15, 0.90, 0.05), 0.018, closed=True), OUTLINE, 0.9)
    return a


def sofa(st, v):
    a = seat(3, v)
    if v == 1:      # a throw pillow and a stain
        a.paint(a.blur(a.ellipse(1.8, 0.62, 0.20, 0.14), 0.03), (40, 24, 20), 0.30)
        a.paint(a.poly([(0.36, 0.46), (0.62, 0.42), (0.66, 0.68), (0.40, 0.72)]), (220, 196, 140), 1.0)
        a.paint(a.stroke([(0.36, 0.46), (0.62, 0.42), (0.66, 0.68), (0.40, 0.72)], 0.014, closed=True), OUTLINE, 0.85)
    return a


def loveseat(st, v):
    return seat(2, v + 2)


def armchair(st, v):
    return seat(1, v + 1)


def tv_stand(st, v):
    a = body(2, 1)
    cab(a, 0.10, 0.34, 1.90, 0.92, (110, 80, 58), front=(84, 60, 44), doors=2, lip=0.16, noise=0.10, seed=61, r=0.03, handle="knob")
    if v == 0:      # a flat screen
        a.paint(a.blur(a.rect(0.42, 0.20, 1.60, 0.46), 0.02), (8, 6, 4), 0.25)
        a.paint(a.poly(rrect(0.40, 0.06, 1.60, 0.14, 0.015)), (40, 42, 46), 1.0)
        a.paint(a.poly(rrect(0.40, 0.14, 1.60, 0.44, 0.02)), lambda X, Y: np.array((34, 40, 52), np.float32)[None, None, :] * (1.0 + 0.5 * np.clip(((X - 0.40) + (Y - 0.14)) * -0.5, -0.2, 0.3) + 0.0)[..., None])
        a.paint(a.stroke(rrect(0.40, 0.06, 1.60, 0.44, 0.02), 0.022, closed=True), OUTLINE, 1.0)
        a.paint(a.poly([(0.60, 0.44), (0.82, 0.14), (0.92, 0.14), (0.70, 0.44)]), (210, 224, 240), 0.14)
        a.paint(a.poly([(1.02, 0.44), (1.18, 0.14), (1.24, 0.14), (1.08, 0.44)]), (210, 224, 240), 0.10)
    else:           # an old boxy set
        slab(a, 0.46, 0.06, 1.54, 0.40, (74, 70, 64), r=0.04, lw=0.026, lo=0.80, hi=1.10)
        a.paint(a.poly(rrect(0.54, 0.12, 1.26, 0.36, 0.05)), (44, 52, 60), 1.0)
        a.paint(a.stroke(rrect(0.54, 0.12, 1.26, 0.36, 0.05), 0.014, closed=True), OUTLINE, 0.9)
        for yy in (0.16, 0.22, 0.28):
            line(a, [(1.34, yy), (1.46, yy)], 0.012, (120, 118, 110), 0.9, round_ends=False)
        dot(a, 1.40, 0.34, 0.016, (190, 60, 50))
    return a


def coffee_table(st, v):
    a = body(2, 1)
    top = [WOOD_M, WOOD_D][v]
    slab(a, 0.14, 0.18, 1.86, 0.84, top, r=0.05, lw=0.028, lo=0.84, hi=1.10, noise=0.12, seed=71 + v, along="x")
    a.paint(a.stroke(rrect(0.24, 0.26, 1.76, 0.76, 0.03), 0.012, closed=True), shade(top, 0.66), 0.55)
    # magazines and a mug
    a.paint(a.poly([(0.40, 0.34), (0.76, 0.30), (0.80, 0.56), (0.44, 0.60)]), (212, 208, 196), 1.0)
    a.paint(a.stroke([(0.40, 0.34), (0.76, 0.30), (0.80, 0.56), (0.44, 0.60)], 0.014, closed=True), OUTLINE, 0.85)
    a.paint(a.poly([(0.46, 0.38), (0.72, 0.35), (0.74, 0.52), (0.48, 0.55)]), (150, 62, 56), 0.9)
    disc(a, 1.34, 0.50, 0.075, (232, 230, 222), lw=0.018)
    disc(a, 1.34, 0.50, 0.045, (90, 60, 44), lw=0.0)
    return a


def dining_table(st, v):
    a = body(2, 1)
    if v == 0:
        slab(a, 0.08, 0.14, 1.92, 0.86, WOOD_M, r=0.05, lw=0.028, lo=0.84, hi=1.10, noise=0.14, seed=81, along="x")
        a.paint(a.stroke([(0.14, 0.50), (1.86, 0.50)], 0.010), shade(WOOD_M, 0.66), 0.5)
        disc(a, 1.0, 0.50, 0.15, (230, 226, 214), lw=0.018)
        disc(a, 1.0, 0.50, 0.08, (160, 90, 70), lw=0.0)
    else:
        slab(a, 0.08, 0.14, 1.92, 0.86, (232, 228, 214), r=0.05, lw=0.028, lo=0.88, hi=1.06, noise=0.04, seed=82)
        a.paint(a.stroke(rrect(0.18, 0.22, 1.82, 0.78, 0.03), 0.012, closed=True), (160, 60, 56), 0.7)
        for cx in (0.50, 1.50):
            disc(a, cx, 0.50, 0.14, (244, 242, 236), lw=0.016, lo=0.9)
            disc(a, cx, 0.50, 0.08, (222, 220, 212), lw=0.0)
        a.paint(a.blur(a.ellipse(1.0, 0.40, 0.14, 0.10), 0.03), (60, 40, 30), 0.28)
    return a


def chair(st, v):
    a = body(1, 1)
    if v == 0:
        slab(a, 0.20, 0.30, 0.80, 0.84, WOOD_M, r=0.06, lw=0.026, lo=0.84, hi=1.10, noise=0.10, seed=91)
        slab(a, 0.20, 0.16, 0.80, 0.30, shade(WOOD_M, 0.82), r=0.04, lw=0.026, lo=0.84, hi=1.08, rim=False)         # the back
        for xx in (0.38, 0.50, 0.62):
            line(a, [(xx, 0.18), (xx, 0.29)], 0.008, shade(WOOD_M, 0.5), 0.6, round_ends=False)
    else:           # an office swivel chair: seat disc, curved back, a star of feet
        for ang in range(5):
            t = np.radians(ang * 72 + 20)
            line(a, [(0.5, 0.55), (0.5 + 0.34 * np.cos(t), 0.55 + 0.34 * np.sin(t))], 0.036, (30, 30, 32), 1.0)
            dot(a, 0.5 + 0.34 * np.cos(t), 0.55 + 0.34 * np.sin(t), 0.035, (20, 20, 22))
        disc(a, 0.5, 0.55, 0.26, (74, 82, 98), lw=0.026, lo=0.84, hi=1.12)
        a.paint(a.stroke([(0.5 + 0.30 * np.cos(t), 0.55 + 0.30 * np.sin(t)) for t in np.linspace(3.6, 5.8, 14)], 0.09, round_ends=True), OUTLINE, 1.0)
        a.paint(a.stroke([(0.5 + 0.30 * np.cos(t), 0.55 + 0.30 * np.sin(t)) for t in np.linspace(3.6, 5.8, 14)], 0.060, round_ends=True), (96, 106, 124), 1.0)
    return a


def bookshelf(st, v):
    a = body(2, 1)
    op = st == "opened"
    x0, y0, x1, y1 = 0.06, 0.10, 1.94, 0.92
    top = WOOD_M
    a.paint(a.poly(rrect(x0, y0, x1, y1, 0.03)), (32, 24, 20))
    # the books, their tops in rows and their spines to the front
    rng = rng_for("books", v)
    cols = [(150, 62, 56), (60, 96, 130), (86, 120, 84), (196, 164, 84), (120, 84, 130), (214, 210, 196), (80, 60, 50), (170, 110, 70)]
    for row, (yy0, yy1) in enumerate(((0.16, 0.50), (0.52, 0.78))):
        x = x0 + 0.05
        while x < x1 - 0.1:
            bw = rng.uniform(0.07, 0.15)
            c = cols[rng.integers(0, len(cols))]
            gap = op and rng.random() < 0.22
            if not gap:
                a.paint(a.rect(x, yy0, x + bw, yy1), lit(c, 0.84, 1.1, x, yy0, x + bw, yy1))
                a.paint(a.stroke([(x, yy0), (x, yy1)], 0.008, round_ends=False), OUTLINE, 0.6)
            x += bw + 0.005
    a.paint(a.rect(x0 + 0.02, 0.50, x1 - 0.02, 0.52), WOOD_D, 1.0)         # a shelf board between the rows
    a.paint(a.rect(x0 + 0.02, 0.78, x1 - 0.02, 0.82), WOOD_D, 1.0)
    a.paint(a.stroke(rrect(x0, y0, x1, y1, 0.03), 0.028, closed=True), OUTLINE, 1.0)
    a.paint(a.poly(rrect(x0, y0, x1, 0.15, 0.03)), lit(top, 0.88, 1.1, x0, y0, x1, 0.15, 0.1, 5))
    a.paint(a.stroke(rrect(x0, y0, x1, 0.15, 0.03), 0.02, closed=True), OUTLINE, 0.9)
    if op:     # books that fell out onto the floor in front
        a.paint(a.poly([(1.1, 0.80), (1.34, 0.78), (1.36, 0.90), (1.12, 0.92)]), (86, 120, 84), 1.0)
        a.paint(a.stroke([(1.1, 0.80), (1.34, 0.78), (1.36, 0.90), (1.12, 0.92)], 0.012, closed=True), OUTLINE, 0.9)
    return a


def desk(st, v):
    a = body(2, 1)
    cab(a, 0.06, 0.10, 1.94, 0.92, WOOD_M, front=shade(WOOD_M, 0.76), doors=3, drawers=True, opened=(st == "opened"), lip=0.17, noise=0.12, seed=101 + v, r=0.03, along="x")
    if v == 0:       # papers, a pen, a lamp
        a.paint(a.poly([(0.30, 0.22), (0.66, 0.20), (0.70, 0.56), (0.34, 0.58)]), (232, 228, 214), 1.0)
        a.paint(a.stroke([(0.30, 0.22), (0.66, 0.20), (0.70, 0.56), (0.34, 0.58)], 0.012, closed=True), OUTLINE, 0.85)
        for yy in (0.30, 0.36, 0.42, 0.48):
            line(a, [(0.36, yy), (0.62, yy - 0.005)], 0.008, (140, 136, 130), 0.7)
        line(a, [(0.80, 0.30), (0.96, 0.52)], 0.016, (30, 60, 110), 1.0)
        disc(a, 1.62, 0.34, 0.17, (60, 100, 74), lw=0.022)
        disc(a, 1.62, 0.34, 0.06, (250, 238, 190), lw=0.0)
    else:            # a ledger, a mug, a tin
        a.paint(a.poly(rrect(0.34, 0.20, 0.80, 0.58, 0.015)), (96, 54, 46), 1.0)
        a.paint(a.stroke(rrect(0.34, 0.20, 0.80, 0.58, 0.015), 0.014, closed=True), OUTLINE, 0.9)
        a.paint(a.rect(0.36, 0.24, 0.78, 0.54), (226, 220, 200), 1.0)
        disc(a, 1.30, 0.40, 0.07, (222, 220, 212), lw=0.018)
        disc(a, 1.30, 0.40, 0.04, (80, 54, 40), lw=0.0)
        disc(a, 1.62, 0.36, 0.11, (150, 150, 140), lw=0.020)
        disc(a, 1.62, 0.36, 0.07, (186, 186, 176), lw=0.0)
    return a


def job_furniture_1():
    C = ["closed", "opened"]
    prop("furniture", "fridge", 1, 1, fridge, states=C, variants=2, tags=["container", "solid", "kitchen"], bg=(190, 190, 170),
         note="A fridge, back to the north (facing s: its door faces south). States: closed / opened (searched: the door stands ajar). Variants: white, cream.")
    prop("furniture", "kitchen_counter", 1, 1, counter, states=C, variants=2, tags=["container", "solid", "kitchen"], bg=(190, 190, 170),
         note="A kitchen counter cell with cupboard doors in front. Opened: a door stands ajar. Variants: a chopping board, a pot and a plate.")
    prop("furniture", "kitchen_sink", 1, 1, counter_sink, tags=["solid", "kitchen", "sink"], bg=(190, 190, 170), note="A counter with a steel sink and a draining board.")
    prop("furniture", "stove", 1, 1, stove, variants=2, tags=["solid", "kitchen", "stove"], bg=(190, 190, 170), note="A cooker with four rings. Variants: white, black.")
    prop("furniture", "cupboard", 1, 1, cupboard, states=C, variants=2, tags=["container", "solid"], bg=(190, 190, 170),
         note="A tall cupboard or pantry. Opened: its doors stand ajar. Variants: wood, painted white.")
    prop("furniture", "wardrobe", 2, 1, wardrobe, states=C, variants=2, tags=["container", "solid", "bedroom"], bg=(150, 130, 120),
         note="A wardrobe, two cells wide, doors to the front. Opened: both doors ajar. Variants: wood, painted white.")
    prop("furniture", "dresser", 2, 1, dresser, states=C, variants=2, tags=["container", "solid", "bedroom"], bg=(150, 130, 120),
         note="A chest of drawers, two cells wide. Opened: the top drawer stands out. Variants: oak, dark.")
    prop("furniture", "nightstand", 1, 1, nightstand, states=C, variants=2, tags=["container", "solid", "bedroom"], bg=(150, 130, 120),
         note="A bedside cabinet with a lamp (a) or a clock and a book (b). Opened: the drawer stands out.")
    prop("furniture", "bed_single", 1, 2, bed_single, variants=4, tags=["solid", "bed", "bedroom"], bg=(150, 130, 120),
         note="A single bed, head to the north (facing s), one cell wide and two long; for e and w it is two wide and one long. Variants are the four blankets.")
    prop("furniture", "bed_double", 2, 2, bed_double, variants=3, tags=["solid", "bed", "bedroom"], bg=(150, 130, 120),
         note="A double bed, head to the north, two cells square. Variants are three blankets.")
    prop("furniture", "sofa", 3, 1, sofa, variants=3, tags=["solid", "living"], bg=(150, 130, 120), note="A three seat sofa, back to the north. Variants: slate blue, brick, olive.")
    prop("furniture", "loveseat", 2, 1, loveseat, variants=2, tags=["solid", "living"], bg=(150, 130, 120), note="A two seat sofa, back to the north.")
    prop("furniture", "armchair", 1, 1, armchair, variants=4, tags=["solid", "living"], bg=(150, 130, 120), note="An armchair, back to the north.")
    prop("furniture", "tv_stand", 2, 1, tv_stand, variants=2, tags=["solid", "living"], bg=(150, 130, 120),
         note="A low cabinet with a television on it (a: flat screen, b: old boxy set).")
    prop("furniture", "coffee_table", 2, 1, coffee_table, variants=2, tags=["solid", "living"], bg=(150, 130, 120), note="A low table with magazines and a mug.")
    prop("furniture", "dining_table", 2, 1, dining_table, variants=2, tags=["solid", "dining"], bg=(150, 130, 120),
         note="A dining table, two cells wide (a: bare wood with a bowl, b: a white cloth and two plates). Put a `chair` on the cells along its long sides.")
    prop("furniture", "chair", 1, 1, chair, variants=2, tags=["dining", "walkable"], solid=[], bg=(150, 130, 120),
         note="A chair; facing is the way the seat looks (s: back at the north). a: wooden dining chair, b: office swivel chair. Not solid: the dead and the people can walk over it.")
    prop("furniture", "bookshelf", 2, 1, bookshelf, states=C, variants=2, tags=["container", "solid"], bg=(150, 130, 120),
         note="A bookcase two cells wide, books to the front. Opened: gaps in the rows and a book on the floor. The two variants have different books.")
    prop("furniture", "desk", 2, 1, desk, states=C, variants=2, tags=["container", "solid"], bg=(150, 130, 120),
         note="A desk with three drawers in front (a: papers, a pen and a lamp; b: a ledger, a mug and a tin). Opened: a drawer stands out.")


CERAMIC = (232, 232, 226)


def toilet(st, v):
    a = body(1, 1)
    # the cistern at the back, the bowl in front
    slab(a, 0.24, 0.08, 0.76, 0.32, CERAMIC, r=0.04, lw=0.026, lo=0.84, hi=1.08)
    dot(a, 0.5, 0.17, 0.024, (170, 176, 180))
    a.paint(a.ellipse(0.5, 0.60, 0.25, 0.31), OUTLINE, 1.0)
    a.paint(a.ellipse(0.5, 0.60, 0.225, 0.285), lit(shade(CERAMIC, 0.94), 0.84, 1.10, 0.25, 0.3, 0.75, 0.9))
    if v == 0:      # the lid down
        a.paint(a.ellipse(0.5, 0.60, 0.19, 0.245), lit(CERAMIC, 0.88, 1.08, 0.3, 0.35, 0.7, 0.85))
        a.paint(a.stroke([(0.5 + 0.19 * np.cos(t), 0.60 + 0.245 * np.sin(t)) for t in np.linspace(0, 6.3, 30)], 0.012, closed=True), (130, 130, 126), 0.8)
    else:           # the seat up: dark water in the bowl
        a.paint(a.ellipse(0.5, 0.64, 0.15, 0.20), (40, 54, 60), 1.0)
        a.paint(a.ellipse(0.5, 0.64, 0.15, 0.20), (150, 170, 176), 0.0)
        a.paint(a.stroke([(0.5 + 0.15 * np.cos(t), 0.64 + 0.20 * np.sin(t)) for t in np.linspace(0, 6.3, 30)], 0.016, closed=True), (214, 214, 206), 0.9)
        slab(a, 0.30, 0.16, 0.70, 0.30, (214, 212, 204), r=0.03, lw=0.02, lo=0.86, hi=1.06, rim=False)
    return a


def bathtub(st, v):
    a = body(2, 1)
    slab(a, 0.04, 0.06, 1.96, 0.94, CERAMIC, r=0.22, lw=0.03, lo=0.84, hi=1.08)
    basin = rrect(0.16, 0.17, 1.84, 0.83, 0.18)
    a.paint(a.poly(basin), lambda X, Y: np.array((196, 208, 214) if v == 0 else (120, 112, 90), np.float32)[None, None, :] * (1.08 - 0.30 * np.clip((Y - 0.17) / 0.66 * 0.6 + (X - 0.16) / 1.68 * 0.5, 0, 1))[..., None])
    a.paint(a.stroke(basin, 0.018, closed=True), OUTLINE, 0.9)
    dot(a, 1.66, 0.50, 0.035, (80, 84, 88))
    dot(a, 1.66, 0.50, 0.022, (30, 30, 32))
    # taps at the left end
    for yy in (0.38, 0.62):
        dot(a, 0.28, yy, 0.032, (200, 204, 208))
        dot(a, 0.275, yy - 0.005, 0.012, (255, 255, 255), 0.9)
    a.paint(a.stroke([(0.28, 0.5), (0.46, 0.5)], 0.030), (200, 204, 208), 1.0)
    if v == 1:      # a ring of scum and a stain
        a.paint(a.blur(a.ellipse(0.9, 0.5, 0.55, 0.20), 0.05), (60, 50, 34), 0.30)
    return a


def washbasin(st, v):
    a = body(1, 1)
    if v == 0:      # a pedestal basin
        slab(a, 0.14, 0.12, 0.86, 0.80, CERAMIC, r=0.18, lw=0.028, lo=0.84, hi=1.08)
        a.paint(a.poly(rrect(0.24, 0.22, 0.76, 0.70, 0.14)), lit((200, 212, 218), 0.8, 1.1, 0.24, 0.22, 0.76, 0.7))
        a.paint(a.stroke(rrect(0.24, 0.22, 0.76, 0.70, 0.14), 0.014, closed=True), (110, 120, 124), 0.8)
    else:           # a vanity with a cupboard under it
        cab(a, 0.10, 0.08, 0.90, 0.92, (214, 212, 202), front=(150, 120, 88), doors=2, lip=0.14, noise=0.03, seed=111, r=0.03)
        a.paint(a.poly(rrect(0.28, 0.22, 0.72, 0.62, 0.12)), lit((200, 212, 218), 0.8, 1.1, 0.28, 0.22, 0.72, 0.62))
        a.paint(a.stroke(rrect(0.28, 0.22, 0.72, 0.62, 0.12), 0.014, closed=True), OUTLINE, 0.9)
    dot(a, 0.5, 0.44, 0.02, (40, 44, 48))
    a.paint(a.rect(0.44, 0.13, 0.56, 0.19), (200, 204, 208), 1.0)
    a.paint(a.stroke([(0.5, 0.19), (0.5, 0.30)], 0.026), (200, 204, 208), 1.0)
    return a


def medicine_cabinet(st, v):
    a = body(1, 1)
    op = st == "opened"
    x0, y0, x1, y1 = 0.18, 0.04, 0.82, 0.38
    slab(a, x0, y0, x1, y1, (232, 232, 228), r=0.03, lw=0.026, lo=0.86, hi=1.08)
    a.paint(a.rect(x0 + 0.05, y0 + 0.06, x1 - 0.05, y1 - 0.06), (184, 204, 214), 0.9)
    a.paint(a.poly([(x0 + 0.10, y1 - 0.06), (x0 + 0.20, y0 + 0.06), (x0 + 0.26, y0 + 0.06), (x0 + 0.16, y1 - 0.06)]), (255, 255, 255), 0.35)
    if op:
        leaf = [(x1 - 0.02, y1 - 0.01), (x1 + 0.0, y1 + 0.26), (x1 - 0.30, y1 + 0.28), (x1 - 0.32, y1 - 0.01)]
        a.paint(a.poly(leaf), lit((232, 232, 228), 0.84, 1.08, 0, 0, 1, 1))
        a.paint(a.stroke(leaf, 0.020, closed=True), OUTLINE, 0.95)
        a.paint(a.rect(x1 - 0.20, y1 + 0.10, x1 - 0.10, y1 + 0.20), (180, 50, 44), 0.9)
        a.paint(a.rect(x1 - 0.17, y1 + 0.06, x1 - 0.13, y1 + 0.24), (180, 50, 44), 0.9)
        a.paint(a.rect(x0 + 0.04, y0 + 0.04, x1 - 0.04, y1 - 0.04), (22, 20, 20), 0.7)
    else:
        a.paint(a.rect(0.46, 0.14, 0.54, 0.28), (180, 50, 44), 0.95)
        a.paint(a.rect(0.40, 0.19, 0.60, 0.23), (180, 50, 44), 0.95)
    return a


def toolbox(st, v):
    a = body(1, 1)
    op = st == "opened"
    slab(a, 0.14, 0.28, 0.86, 0.74, (170, 52, 44), r=0.04, lw=0.028, lo=0.80, hi=1.12)
    if not op:
        a.paint(a.rect(0.16, 0.32, 0.84, 0.40), (255, 230, 220), 0.18)
        a.paint(a.stroke([(0.34, 0.30), (0.40, 0.16), (0.60, 0.16), (0.66, 0.30)], 0.040, round_ends=True), (50, 48, 48), 1.0)
        a.paint(a.stroke([(0.34, 0.30), (0.40, 0.16), (0.60, 0.16), (0.66, 0.30)], 0.020, round_ends=True), (130, 128, 126), 1.0)
        for xx in (0.26, 0.74):
            a.paint(a.rect(xx - 0.04, 0.66, xx + 0.04, 0.74), (190, 190, 184), 1.0)
    else:
        a.paint(a.rect(0.19, 0.31, 0.81, 0.71), (50, 36, 32), 1.0)
        a.paint(a.stroke([(0.24, 0.40), (0.50, 0.46)], 0.034), (190, 194, 198), 1.0)          # a spanner
        dot(a, 0.52, 0.47, 0.034, (190, 194, 198))
        a.paint(a.rect(0.56, 0.40, 0.62, 0.62), (120, 80, 50), 1.0)
        a.paint(a.rect(0.50, 0.38, 0.72, 0.46), (140, 144, 150), 1.0)                      # a hammer
        a.paint(a.poly(rrect(0.14, 0.08, 0.86, 0.26, 0.03)), lit((190, 62, 54), 0.84, 1.1, 0.14, 0.08, 0.86, 0.26))      # the lid, raised at the back
        a.paint(a.stroke(rrect(0.14, 0.08, 0.86, 0.26, 0.03), 0.022, closed=True), OUTLINE, 1.0)
    return a


def workbench(st, v):
    a = body(2, 1)
    cab(a, 0.06, 0.12, 1.94, 0.92, WOOD_L, front=shade(WOOD_M, 0.9), doors=3, drawers=True, opened=(st == "opened"), lip=0.17, noise=0.16, seed=121, r=0.02, along="x")
    # a vise, some tools and a can of nails
    slab(a, 0.20, 0.22, 0.46, 0.50, (70, 76, 84), r=0.02, lw=0.022, lo=0.8, hi=1.1)
    a.paint(a.rect(0.28, 0.50, 0.38, 0.62), (60, 64, 70), 1.0)
    a.paint(a.stroke([(0.70, 0.30), (1.10, 0.36)], 0.030), (110, 114, 120), 1.0)
    a.paint(a.stroke([(0.74, 0.46), (1.06, 0.52)], 0.024), (150, 96, 56), 1.0)
    disc(a, 1.46, 0.40, 0.11, (120, 124, 128), lw=0.020)
    disc(a, 1.46, 0.40, 0.065, (60, 60, 60), lw=0.0)
    a.paint(a.poly([(1.60, 0.24), (1.84, 0.28), (1.80, 0.54), (1.58, 0.50)]), (196, 188, 160), 0.95)
    return a


def box_cardboard(st, v):
    a = body(1, 1)
    op = st == "opened"
    size = [0.76, 0.62, 0.84][v]
    x0 = 0.5 - size / 2
    y0 = 0.52 - size / 2
    x1, y1 = x0 + size, y0 + size
    c = [(184, 148, 100), (170, 134, 90), (196, 160, 112)][v]
    if not op:
        slab(a, x0, y0, x1, y1, c, r=0.015, lw=0.026, lo=0.84, hi=1.1, noise=0.12, seed=130 + v, freq=10.0)
        a.paint(a.rect(0.5 - 0.045, y0, 0.5 + 0.045, y1), (222, 200, 150), 0.85)
        a.paint(a.stroke([(x0 + 0.02, 0.5), (x1 - 0.02, 0.5)], 0.010), shade(c, 0.7), 0.7)
        if v != 1:
            a.paint(a.poly(rrect(x0 + 0.08, y1 - 0.20, x0 + 0.30, y1 - 0.08, 0.01)), (236, 232, 220), 0.95)
            line(a, [(x0 + 0.11, y1 - 0.15), (x0 + 0.27, y1 - 0.15)], 0.008, (120, 60, 50), 0.9)
    else:
        a.paint(a.rect(x0, y0, x1, y1), (60, 44, 32), 1.0)
        a.paint(a.stroke(rrect(x0, y0, x1, y1, 0.015), 0.026, closed=True), OUTLINE, 1.0)
        for poly in ([(x0, y0), (x1, y0), (x1 - 0.06, y0 + 0.10), (x0 + 0.06, y0 + 0.10)], [(x0, y1), (x1, y1), (x1 - 0.06, y1 - 0.10), (x0 + 0.06, y1 - 0.10)],
                     [(x0, y0), (x0, y1), (x0 + 0.10, y1 - 0.06), (x0 + 0.10, y0 + 0.06)], [(x1, y0), (x1, y1), (x1 - 0.10, y1 - 0.06), (x1 - 0.10, y0 + 0.06)]):
            a.paint(a.poly(poly), lit(shade(c, 1.05), 0.8, 1.1, x0, y0, x1, y1))
            a.paint(a.stroke(poly, 0.012, closed=True), OUTLINE, 0.8)
        a.paint(a.poly([(x0 + 0.16, y0 + 0.2), (x1 - 0.22, y0 + 0.18), (x1 - 0.18, y0 + 0.40), (x0 + 0.2, y0 + 0.42)]), (150, 130, 110), 0.9)
    return a


def crate(st, v):
    a = body(1, 1)
    op = st == "opened"
    x0, y0, x1, y1 = 0.10, 0.10, 0.90, 0.90
    wood = [(172, 132, 88), (150, 120, 84)][v]
    slab(a, x0, y0, x1, y1, shade(wood, 0.8), r=0.02, lw=0.028, lo=0.84, hi=1.08, rim=False)
    if not op:
        for i in range(4):
            yy0 = y0 + 0.02 + i * 0.19
            a.paint(a.rect(x0 + 0.02, yy0, x1 - 0.02, yy0 + 0.17), lit(wood, 0.84, 1.10, x0, yy0, x1, yy0 + 0.17, 0.2, 140 + i + v * 7, 16.0, "x"))
            a.paint(a.stroke([(x0 + 0.02, yy0 + 0.17), (x1 - 0.02, yy0 + 0.17)], 0.012, round_ends=False), (30, 22, 16), 0.7)
        for yy in (0.18, 0.82):
            nail(a, 0.20, yy, 0.012)
            nail(a, 0.80, yy, 0.012)
        a.paint(a.stroke([(x0 + 0.04, y0 + 0.04), (x1 - 0.04, y1 - 0.04)], 0.040), shade(wood, 0.72), 0.85) if v == 1 else None
    else:
        a.paint(a.rect(x0 + 0.05, y0 + 0.05, x1 - 0.05, y1 - 0.05), (46, 34, 26), 1.0)
        a.paint(a.poly([(0.26, 0.30), (0.60, 0.26), (0.66, 0.50), (0.32, 0.56)]), (190, 170, 120), 0.9)      # straw and rags
        a.paint(a.poly([(0.50, 0.50), (0.78, 0.54), (0.74, 0.74), (0.46, 0.70)]), (130, 110, 84), 0.9)
        a.paint(a.poly(rrect(0.44, 0.04, 0.88, 0.16, 0.01)), lit(wood, 0.84, 1.1, 0.44, 0.04, 0.88, 0.16))     # a slat prised off, leaning
        a.paint(a.stroke(rrect(0.44, 0.04, 0.88, 0.16, 0.01), 0.018, closed=True), OUTLINE, 0.95)
    return a


def laundry_basket(st, v):
    a = body(1, 1)
    op = st == "opened"
    disc(a, 0.5, 0.52, 0.38, (196, 164, 110), lw=0.030, lo=0.80, hi=1.14)
    for r_ in (0.30, 0.22):
        a.paint(a.stroke([(0.5 + r_ * np.cos(t), 0.52 + r_ * np.sin(t)) for t in np.linspace(0, 6.3, 36)], 0.012, closed=True), (140, 106, 64), 0.6)
    for ang in range(8):
        t = np.radians(ang * 45)
        line(a, [(0.5 + 0.10 * np.cos(t), 0.52 + 0.10 * np.sin(t)), (0.5 + 0.34 * np.cos(t), 0.52 + 0.34 * np.sin(t))], 0.008, (140, 106, 64), 0.45)
    cl = [(110, 140, 170), (200, 160, 150), (230, 226, 210), (130, 150, 110)]
    for i, (cx, cy, r_) in enumerate(((0.42, 0.46, 0.15), (0.60, 0.50, 0.14), (0.50, 0.62, 0.13))):
        a.paint(a.ellipse(cx, cy, r_, r_ * 0.8), cl[i], 1.0)
        a.paint(a.stroke([(cx + r_ * np.cos(t), cy + r_ * 0.8 * np.sin(t)) for t in np.linspace(0, 6.3, 20)], 0.012, closed=True), OUTLINE, 0.7)
    if op:      # the washing pulled out and dropped at the edge
        a.paint(a.poly([(0.66, 0.74), (0.90, 0.70), (0.92, 0.88), (0.70, 0.90)]), (214, 150, 140), 1.0)
        a.paint(a.stroke([(0.66, 0.74), (0.90, 0.70), (0.92, 0.88), (0.70, 0.90)], 0.014, closed=True), OUTLINE, 0.8)
        a.paint(a.ellipse(0.5, 0.52, 0.10, 0.08), (30, 24, 18), 0.8)
    return a


def shelf_tins(st, v):
    a = body(2, 1)
    op = st == "opened"
    slab(a, 0.06, 0.12, 1.94, 0.92, (110, 112, 116), r=0.02, lw=0.028, lo=0.84, hi=1.08)
    a.paint(a.rect(0.12, 0.18, 1.88, 0.86), (60, 62, 66), 0.8)
    rng = rng_for("tins", v)
    cols = [(196, 70, 58), (86, 130, 90), (206, 170, 70), (90, 120, 160), (214, 210, 196), (160, 90, 60)]
    for row, cy in enumerate((0.36, 0.66)):
        for i in range(8):
            cx = 0.26 + i * 0.21
            if op and rng.random() < 0.45:
                continue
            c = cols[rng.integers(0, len(cols))]
            disc(a, cx, cy, 0.085, (180, 184, 188), lw=0.014, lo=0.82)
            a.paint(a.ellipse(cx, cy, 0.062), c, 1.0)
            a.paint(a.ellipse(cx - 0.02, cy - 0.02, 0.018), (255, 255, 255), 0.5)
    if op:
        disc(a, 1.30, 0.94, 0.07, (180, 184, 188), lw=0.014)
        a.paint(a.ellipse(1.30, 0.94, 0.052), (206, 170, 70), 1.0)
    return a


def rug_rect(st, v):
    a = body(3, 2)
    outer = [(126, 58, 56), (66, 88, 108)][v]
    field = [(92, 58, 54), (150, 130, 96)][v]
    a.paint(a.poly(rrect(0.10, 0.10, 2.90, 1.90, 0.02)), (222, 210, 182))
    a.paint(a.poly(rrect(0.18, 0.18, 2.82, 1.82, 0.015)), lit(outer, 0.88, 1.08, 0.18, 0.18, 2.82, 1.82, 0.10, 150 + v, 20.0))
    a.paint(a.poly(rrect(0.34, 0.34, 2.66, 1.66, 0.015)), (222, 210, 182))
    a.paint(a.poly(rrect(0.40, 0.40, 2.60, 1.60, 0.012)), lit(field, 0.88, 1.08, 0.4, 0.4, 2.6, 1.6, 0.12, 155 + v, 22.0))
    a.paint(a.poly([(1.5, 0.58), (2.1, 1.0), (1.5, 1.42), (0.9, 1.0)]), shade(outer, 1.15), 0.9)
    a.paint(a.stroke([(1.5, 0.58), (2.1, 1.0), (1.5, 1.42), (0.9, 1.0)], 0.020, closed=True), (222, 210, 182), 0.9)
    a.paint(a.poly([(1.5, 0.78), (1.84, 1.0), (1.5, 1.22), (1.16, 1.0)]), (222, 210, 182), 0.85)
    for (cx, cy) in ((0.60, 0.60), (2.40, 0.60), (0.60, 1.40), (2.40, 1.40)):
        a.paint(a.poly([(cx, cy - 0.12), (cx + 0.12, cy), (cx, cy + 0.12), (cx - 0.12, cy)]), (222, 210, 182), 0.8)
    for xx in np.arange(0.14, 2.9, 0.09):      # the fringe at both short ends
        line(a, [(xx, 0.04), (xx, 0.11)], 0.012, (222, 210, 182), 0.9, round_ends=False)
        line(a, [(xx, 1.89), (xx, 1.96)], 0.012, (222, 210, 182), 0.9, round_ends=False)
    a.paint(a.blur(a.ellipse(2.0, 1.4, 0.35, 0.22), 0.06), (30, 20, 16), 0.28)      # a stain
    a.paint(a.blur(a.ellipse(0.9, 0.7, 0.3, 0.2), 0.08), (255, 250, 235), 0.14)     # a worn patch
    a.paint(a.stroke(rrect(0.10, 0.10, 2.90, 1.90, 0.02), 0.020, closed=True), OUTLINE, 0.9)
    return a


def rug_round(st, v):
    a = body(2, 2)
    cols = [(104, 124, 96), (214, 200, 168), (150, 84, 70), (104, 124, 96)]
    for i, r_ in enumerate((0.90, 0.74, 0.58, 0.40, 0.2)):
        c = cols[i % 4] if v == 0 else [(70, 90, 112), (222, 210, 182), (140, 66, 60), (70, 90, 112), (222, 210, 182)][i]
        a.paint(a.ellipse(1.0, 1.0, r_), lit(c, 0.88, 1.08, 0.1, 0.1, 1.9, 1.9, 0.10, 160 + i, 16.0))
    a.paint(a.stroke([(1.0 + 0.90 * np.cos(t), 1.0 + 0.90 * np.sin(t)) for t in np.linspace(0, 6.3, 60)], 0.020, closed=True), OUTLINE, 0.9)
    a.paint(a.blur(a.ellipse(1.3, 1.3, 0.25, 0.2), 0.06), (30, 20, 16), 0.25)
    return a


def lamp_floor(st, v):
    a = body(1, 1)
    a.paint(a.blur(a.ellipse(0.5, 0.56, 0.18, 0.12), 0.03), (8, 6, 4), 0.40)
    sh = [(236, 222, 184), (196, 84, 70)][v]
    disc(a, 0.5, 0.5, 0.30, shade(sh, 0.86), lw=0.026)
    disc(a, 0.5, 0.5, 0.22, sh, lw=0.0)
    a.paint(a.ellipse(0.5, 0.5, 0.08), (255, 248, 220), 1.0)
    return a


def radio_set(st, v):
    a = body(2, 1)
    slab(a, 0.06, 0.12, 1.94, 0.92, WOOD_D, r=0.03, lw=0.028, lo=0.84, hi=1.08, noise=0.12, seed=170, along="x")
    # the set: olive steel box with a front panel
    x0, y0, x1, y1 = 0.18, 0.18, 1.18, 0.78
    a.paint(a.blur(a.poly(rrect(x0 + 0.03, y0 + 0.04, x1 + 0.03, y1 + 0.05, 0.03)), 0.015), (8, 6, 4), 0.35)
    pts = rrect(x0, y0, x1, y1, 0.03)
    a.paint(a.poly(pts), lit((92, 104, 76), 0.82, 1.12, x0, y0, x1, y1))
    a.paint(a.poly(rrect(x0 + 0.04, y0 + 0.04, x1 - 0.04, 0.34, 0.015)), lit((78, 88, 64), 0.9, 1.05, 0, 0, 1, 1))
    for i in range(10):          # the speaker grille
        for j in range(2):
            dot(a, x0 + 0.14 + i * 0.075, y0 + 0.09 + j * 0.06, 0.012, (36, 40, 30), 0.9)
    a.paint(a.poly(rrect(x0 + 0.06, 0.40, 0.74, 0.58, 0.015)), (214, 202, 150), 1.0)          # the dial
    a.paint(a.stroke(rrect(x0 + 0.06, 0.40, 0.74, 0.58, 0.015), 0.014, closed=True), OUTLINE, 0.9)
    for xx in np.arange(0.28, 0.72, 0.04):
        line(a, [(xx, 0.42), (xx, 0.46 if int(xx * 100) % 8 else 0.50)], 0.006, (60, 50, 36), 0.8, round_ends=False)
    line(a, [(0.52, 0.40), (0.52, 0.58)], 0.010, (180, 40, 36), 1.0)
    for kx in (0.88, 1.04):
        disc(a, kx, 0.50, 0.075, (40, 42, 38), lw=0.016, lo=0.8, hi=1.2)
        line(a, [(kx, 0.50), (kx + 0.04, 0.46)], 0.012, (230, 226, 210), 0.95)
    dot(a, 0.90, 0.70, 0.016, (210, 60, 50))
    dot(a, 1.02, 0.70, 0.016, (90, 180, 90))
    a.paint(a.stroke(pts, 0.026, closed=True), OUTLINE, 1.0)
    # a morse key, a pad of paper, a headset, a coil of wire and the aerial lead
    slab(a, 1.34, 0.50, 1.58, 0.72, (60, 60, 56), r=0.02, lw=0.018, lo=0.8, hi=1.1)
    a.paint(a.stroke([(1.40, 0.62), (1.56, 0.56)], 0.026), (200, 170, 84), 1.0)
    dot(a, 1.56, 0.56, 0.026, (40, 34, 30))
    a.paint(a.poly([(1.36, 0.22), (1.62, 0.19), (1.65, 0.44), (1.39, 0.46)]), (234, 230, 218), 1.0)
    a.paint(a.stroke([(1.36, 0.22), (1.62, 0.19), (1.65, 0.44), (1.39, 0.46)], 0.012, closed=True), OUTLINE, 0.85)
    for yy in (0.28, 0.33, 0.38):
        line(a, [(1.41, yy), (1.60, yy - 0.01)], 0.007, (100, 100, 110), 0.7)
    line(a, [(1.70, 0.30), (1.86, 0.38)], 0.014, (40, 40, 44), 1.0)
    a.paint(a.stroke([(1.30 + 0.12 * np.cos(t), 0.78 + 0.05 * np.sin(t) * 0) for t in []] or [(1.30, 0.80), (1.30, 0.80)], 0.01), (0, 0, 0), 0.0)
    a.paint(a.stroke([(1.70 + 0.14 * np.cos(t), 0.74 + 0.10 * np.sin(t)) for t in np.linspace(0, 6.3, 30)], 0.040), (60, 40, 30), 0.95)
    a.paint(a.stroke([(1.70 + 0.14 * np.cos(t), 0.74 + 0.10 * np.sin(t)) for t in np.linspace(0, 6.3, 30)], 0.022), (190, 120, 70), 1.0)
    a.paint(a.stroke([(1.18, 0.34), (1.30, 0.20), (1.30, 0.10)], 0.012), (30, 28, 26), 0.9)
    return a


def stash_chest(st, v):
    a = body(1, 1)
    op = st == "opened"
    wood = (126, 88, 58)
    iron = (66, 68, 72)
    if not op:
        slab(a, 0.10, 0.18, 0.90, 0.88, wood, r=0.05, lw=0.030, lo=0.80, hi=1.14, noise=0.14, seed=180, freq=14.0)
        for xx in (0.26, 0.74):
            a.paint(a.rect(xx - 0.045, 0.19, xx + 0.045, 0.87), lit(iron, 0.8, 1.2, xx - 0.05, 0.2, xx + 0.05, 0.8), 1.0)
            a.paint(a.stroke([(xx - 0.045, 0.19), (xx - 0.045, 0.87), (xx + 0.045, 0.87), (xx + 0.045, 0.19)], 0.012), OUTLINE, 0.8)
            nail(a, xx, 0.30, 0.012)
            nail(a, xx, 0.76, 0.012)
        a.paint(a.rect(0.12, 0.34, 0.88, 0.37), shade(wood, 0.6), 0.6)
        slab(a, 0.44, 0.70, 0.56, 0.84, (186, 160, 76), r=0.02, lw=0.018, lo=0.8, hi=1.2, rim=False)           # the lock
        dot(a, 0.5, 0.77, 0.012, (30, 24, 20))
    else:
        slab(a, 0.10, 0.34, 0.90, 0.88, (50, 36, 28), r=0.05, lw=0.030, lo=0.9, hi=1.0, rim=False)
        a.paint(a.poly(rrect(0.16, 0.40, 0.84, 0.82, 0.03)), (36, 26, 20), 1.0)
        a.paint(a.poly([(0.22, 0.50), (0.44, 0.46), (0.48, 0.66), (0.26, 0.70)]), (196, 176, 130), 1.0)             # cloth
        disc(a, 0.64, 0.62, 0.10, (150, 150, 140), lw=0.016)
        a.paint(a.ellipse(0.64, 0.62, 0.065), (206, 170, 70), 1.0)
        a.paint(a.poly(rrect(0.10, 0.04, 0.90, 0.30, 0.04)), lit(wood, 0.84, 1.12, 0.1, 0.04, 0.9, 0.3, 0.12, 181, 14.0))      # the lid thrown back
        for xx in (0.26, 0.74):
            a.paint(a.rect(xx - 0.045, 0.05, xx + 0.045, 0.29), iron, 1.0)
        a.paint(a.stroke(rrect(0.10, 0.04, 0.90, 0.30, 0.04), 0.026, closed=True), OUTLINE, 1.0)
    return a


# ----- clutter decals: flat things on the floor
def papers(st, v):
    rng = rng_for("papers", v)
    a = body(1, 1)
    for i in range(4 + v):
        cx, cy = rng.uniform(0.25, 0.75), rng.uniform(0.25, 0.75)
        ang = rng.uniform(0, 3.14)
        w, h = 0.26, 0.34
        pts = [(cx + dx * np.cos(ang) - dy * np.sin(ang), cy + dx * np.sin(ang) + dy * np.cos(ang)) for dx, dy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2))]
        a.paint(a.blur(a.poly([(x + 0.012, y + 0.016) for x, y in pts]), 0.01), (8, 6, 4), 0.30)
        a.paint(a.poly(pts), (232 - 4 * i, 228 - 4 * i, 212 - 5 * i))
        a.paint(a.stroke(pts, 0.010, closed=True), OUTLINE, 0.55)
        for k in range(1, 5):
            f = -h / 2 + k * h / 5.5
            p0 = (cx + (-w * 0.38) * np.cos(ang) - f * np.sin(ang), cy + (-w * 0.38) * np.sin(ang) + f * np.cos(ang))
            p1 = (cx + (w * 0.38 * (0.6 if k == 4 else 1.0)) * np.cos(ang) - f * np.sin(ang), cy + (w * 0.38 * (0.6 if k == 4 else 1.0)) * np.sin(ang) + f * np.cos(ang))
            line(a, [p0, p1], 0.006, (120, 118, 124), 0.65)
    if v == 2:
        a.paint(a.stroke([(0.74 + 0.05 * np.cos(t), 0.30 + 0.05 * np.sin(t)) for t in np.linspace(0, 6.3, 16)], 0.010, closed=True), (120, 74, 40), 0.7)
    return a


def broken_glass(st, v):
    rng = rng_for("glass", v)
    a = body(1, 1)
    for i in range(9 + 3 * v):
        cx, cy = rng.uniform(0.18, 0.82), rng.uniform(0.18, 0.82)
        ang = rng.uniform(0, 6.28)
        r1, r2, r3 = rng.uniform(0.05, 0.11), rng.uniform(0.03, 0.07), rng.uniform(0.02, 0.05)
        pts = [(cx + r1 * np.cos(ang), cy + r1 * np.sin(ang)), (cx + r2 * np.cos(ang + 2.2), cy + r2 * np.sin(ang + 2.2)), (cx + r3 * np.cos(ang + 4.0), cy + r3 * np.sin(ang + 4.0))]
        a.paint(a.poly(pts), (214, 232, 240), 0.85)
        a.paint(a.stroke(pts, 0.008, closed=True), (255, 255, 255), 0.9)
        a.paint(a.poly([(x - 0.004, y - 0.004) for x, y in pts[:2]] + [(cx, cy)]), (255, 255, 255), 0.35)
    return a


def blood_stain(st, v):
    rng = rng_for("bloodstain", v)
    a = body(1, 1)
    cx, cy = 0.5, 0.5
    for i in range(5 + 2 * v):
        x, y = cx + rng.normal(0, 0.10), cy + rng.normal(0, 0.10)
        r = rng.uniform(0.08, 0.17)
        a.paint(a.ellipse(x, y, r, r * rng.uniform(0.7, 1.0)), (112, 24, 24), 0.55)
    a.paint(a.ellipse(cx, cy, 0.14, 0.12), (96, 18, 18), 0.75)
    for i in range(14):
        x, y = cx + rng.normal(0, 0.28), cy + rng.normal(0, 0.28)
        a.paint(a.ellipse(x, y, rng.uniform(0.012, 0.03)), (104, 20, 20), 0.85)
    if v == 1:       # a smear where something was dragged
        a.paint(a.stroke([(0.5, 0.5), (0.74, 0.70), (0.90, 0.92)], 0.08), (100, 20, 20), 0.5)
    if v == 2:
        a.paint(a.stroke([(0.5, 0.5), (0.22, 0.34), (0.06, 0.20)], 0.07), (100, 20, 20), 0.5)
    return a


def dropped_bag(st, v):
    a = body(1, 1)
    if v == 0:      # a backpack lying on its back
        slab(a, 0.26, 0.14, 0.74, 0.86, (84, 96, 70), r=0.10, lw=0.028, lo=0.80, hi=1.14, noise=0.10, seed=190)
        slab(a, 0.32, 0.50, 0.68, 0.80, (70, 82, 58), r=0.05, lw=0.022, lo=0.8, hi=1.1, rim=False)
        line(a, [(0.34, 0.60), (0.66, 0.60)], 0.010, (190, 186, 160), 0.8)
        a.paint(a.stroke([(0.30, 0.16), (0.16, 0.40), (0.20, 0.66)], 0.050), (50, 56, 44), 1.0)
        a.paint(a.stroke([(0.70, 0.16), (0.84, 0.40), (0.80, 0.66)], 0.050), (50, 56, 44), 1.0)
        a.paint(a.rect(0.44, 0.26, 0.56, 0.36), (190, 150, 60), 1.0)
    else:           # a paper bag tipped over, a tin rolled out
        a.paint(a.poly([(0.22, 0.30), (0.62, 0.22), (0.72, 0.62), (0.30, 0.74)]), lit((186, 150, 102), 0.84, 1.1, 0.2, 0.2, 0.7, 0.7, 0.1, 193))
        a.paint(a.stroke([(0.22, 0.30), (0.62, 0.22), (0.72, 0.62), (0.30, 0.74)], 0.020, closed=True), OUTLINE, 0.95)
        a.paint(a.ellipse(0.66, 0.43, 0.07, 0.17), (60, 44, 32), 0.95)
        disc(a, 0.82, 0.80, 0.07, (190, 70, 56), lw=0.016)
        disc(a, 0.82, 0.80, 0.045, (226, 222, 210), lw=0.0)
    return a


def mattress(st, v):
    a = body(1, 2)
    if v == 0:
        slab(a, 0.10, 0.08, 0.90, 1.92, (218, 214, 200), r=0.07, lw=0.028, lo=0.84, hi=1.08)
        for i in range(9):
            a.paint(a.rect(0.14 + i * 0.087, 0.12, 0.14 + i * 0.087 + 0.043, 1.88), (116, 144, 176), 0.38)
        a.paint(a.blur(a.ellipse(0.5, 1.2, 0.26, 0.38), 0.07), (70, 50, 30), 0.35)
    else:
        slab(a, 0.10, 0.08, 0.90, 1.92, (170, 166, 154), r=0.07, lw=0.028, lo=0.84, hi=1.08)
        a.paint(a.poly([(0.30, 0.50), (0.56, 0.44), (0.64, 0.74), (0.38, 0.80)]), (50, 38, 30), 0.95)
        for yy in (0.50, 0.58, 0.66, 0.74):
            line(a, [(0.34, yy), (0.58, yy - 0.04)], 0.008, (150, 150, 146), 0.9)
        a.paint(a.blur(a.ellipse(0.55, 1.45, 0.24, 0.3), 0.07), (90, 20, 20), 0.35)
        for yy in np.arange(0.2, 1.9, 0.18):
            line(a, [(0.14, yy), (0.86, yy)], 0.008, (120, 118, 108), 0.35, round_ends=False)
    return a


def job_furniture_2():
    C = ["closed", "opened"]
    prop("furniture", "toilet", 1, 1, toilet, variants=2, tags=["solid", "bathroom", "toilet"], bg=(180, 190, 190), note="A toilet, cistern to the north. a: lid down, b: seat up.")
    prop("furniture", "bathtub", 2, 1, bathtub, variants=2, tags=["solid", "bathroom"], bg=(180, 190, 190), note="A bathtub two cells long, taps at its west end (facing s). b: a dirty one.")
    prop("furniture", "washbasin", 1, 1, washbasin, variants=2, tags=["solid", "bathroom", "sink"], bg=(180, 190, 190), note="A washbasin (a: pedestal, b: on a vanity cupboard).")
    prop("furniture", "medicine_cabinet", 1, 1, medicine_cabinet, states=C, tags=["container", "bathroom", "walkable"], solid=[], bg=(180, 190, 190),
         note="A small wall cabinet with a red cross, fixed to the north of its cell (so it takes no floor room: not solid). Opened: the mirror door swings out.")
    prop("furniture", "toolbox", 1, 1, toolbox, states=C, tags=["container", "walkable"], solid=[], bg=(150, 130, 120), note="A red steel toolbox on the floor. Opened: the lid is up, tools show.")
    prop("furniture", "workbench", 2, 1, workbench, states=C, tags=["container", "solid", "workshop"], bg=(150, 130, 120),
         note="A workbench with a vise and tools, drawers in front. Opened: a drawer stands out.")
    prop("furniture", "box", 1, 1, box_cardboard, states=C, variants=3, tags=["container", "solid"], bg=(150, 130, 120),
         note="A cardboard box (three sizes). Opened: the flaps are up and the inside shows.")
    prop("furniture", "crate", 1, 1, crate, states=C, variants=2, tags=["container", "solid"], bg=(150, 130, 120),
         note="A wooden crate. Opened: a slat is prised off and the inside shows.")
    prop("furniture", "laundry_basket", 1, 1, laundry_basket, facings=1, states=C, tags=["container", "walkable"], solid=[], bg=(150, 130, 120),
         note="A wicker laundry basket of clothes. Opened: clothes pulled out and dropped at its edge. Round: no facings.")
    prop("furniture", "shelf_tins", 2, 1, shelf_tins, states=C, variants=2, tags=["container", "solid", "kitchen"], bg=(150, 130, 120),
         note="A steel shelf with rows of tins, seen from above. Opened: tins missing, one rolled off.")
    prop("furniture", "rug_rect", 3, 2, rug_rect, facings=2, variants=2, tags=["decor", "walkable", "rug"], layer="decal", solid=[], shadow=(0.02, 0.03, 0.02, 0.22), bg=(150, 130, 120),
         note="A worn rug, 3 x 2 cells (facing s or n: the same picture; turn it for 2 x 3 with e or w if you add them). It lies on the floor under the furniture.")
    prop("furniture", "rug_round", 2, 2, rug_round, facings=1, variants=2, tags=["decor", "walkable", "rug"], layer="decal", solid=[], shadow=(0.02, 0.03, 0.02, 0.22), bg=(150, 130, 120),
         note="A round rug, 2 x 2 cells (a: sage and cream, b: blue and cream).")
    prop("furniture", "lamp_floor", 1, 1, lamp_floor, facings=1, variants=2, tags=["decor", "walkable", "light"], solid=[], bg=(150, 130, 120),
         note="A standing lamp seen from above, a round shade (a: cream, b: red). A light source can sit on it.")
    prop("furniture", "radio_set", 2, 1, radio_set, tags=["solid", "radio", "base"], bg=(150, 130, 120),
         note="THE BASE'S RADIO: a field radio set with a morse key, a notepad, headphones and a coil of aerial wire on a table, two cells wide. The set faces south.")
    prop("furniture", "stash_chest", 1, 1, stash_chest, states=C, tags=["container", "solid", "stash", "base"], bg=(150, 130, 120),
         note="THE BASE'S STASH: a chest with iron straps and a lock. Opened: the lid is thrown back, cloth and a tin inside.")
    prop("furniture", "papers", 1, 1, papers, facings=1, variants=3, tags=["clutter", "decal", "walkable"], layer="decal", solid=[], shadow=None, bg=(150, 130, 120),
         note="Scattered papers on the floor (a third has a coffee ring). Rotate or flip freely.")
    prop("furniture", "broken_glass", 1, 1, broken_glass, facings=1, variants=3, tags=["clutter", "decal", "walkable"], layer="decal", solid=[], shadow=None, bg=(120, 110, 100),
         mode="glass", note="Shards of broken glass. Rotate or flip freely.")
    prop("furniture", "blood_stain", 1, 1, blood_stain, facings=1, variants=3, tags=["clutter", "decal", "blood", "walkable"], layer="decal", solid=[], shadow=None, bg=(150, 130, 120),
         mode="glass", note="A blood stain (b and c have a drag mark). Rotate or flip freely.")
    prop("furniture", "dropped_bag", 1, 1, dropped_bag, facings=1, variants=2, tags=["clutter", "decal", "walkable"], layer="decal", solid=[], bg=(150, 130, 120),
         note="A dropped bag (a: a backpack, b: a paper bag spilled with a tin rolled out). Rotate freely.")
    prop("furniture", "mattress", 1, 2, mattress, facings=4, variants=2, tags=["clutter", "decal", "walkable", "bed"], layer="decal", solid=[], bg=(150, 130, 120),
         note="A loose mattress on the floor, one cell by two (a: striped ticking, b: stained and torn).")


def job_furniture():
    job_furniture_1()
    job_furniture_2()
    contact("furniture", scale=0.75, bg=(150, 130, 120), facings={"s"})


# ======================================================================
# AUTOTILE LINES: fences, hedges, low walls, sandbags (a post in the middle of the cell, an arm to each side that connects)
# ======================================================================

def _shift_down(arr, n):
    if n <= 0:
        return arr
    out = np.zeros_like(arr)
    out[n:] = arr[:-n]
    return out


def _L(arr):
    return Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8))


def _dilate(m, px):
    k = int(px) * 2 + 1
    return m.filter(ImageFilter.MaxFilter(k))


def line_cell(idx, t, H, cap_fn, face_fn, post=None, face_op=1.0, outline=0.026, seed=1, decor=None, shadow=0.38, rim=True):
    """One cell of a connecting line (fence, wall, hedge): idx = N 1 + E 2 + S 4 + W 8 of the sides that continue. The line's top is a band t
    tiles thick; its front (south) face is extruded H tiles down: that is the picture's tilt. post = (size, height) of the post in the middle."""
    a = Art(1, 1)
    p = post[0] if post else t
    rects = [(0.5 - p / 2, 0.5 - p / 2, 0.5 + p / 2, 0.5 + p / 2)]
    if idx & 1:
        rects.append((0.5 - t / 2, 0.0, 0.5 + t / 2, 0.5))
    if idx & 2:
        rects.append((0.5, 0.5 - t / 2, 1.0, 0.5 + t / 2))
    if idx & 4:
        rects.append((0.5 - t / 2, 0.5, 0.5 + t / 2, 1.0))
    if idx & 8:
        rects.append((0.0, 0.5 - t / 2, 0.5, 0.5 + t / 2))
    # the line without its post: the arms and a block as thick as the line
    arm_rects = [(0.5 - t / 2, 0.5 - t / 2, 0.5 + t / 2, 0.5 + t / 2)] + rects[1:]
    M = None
    for r in arm_rects:
        m = a.rect(*r)
        M = m if M is None else a.either(M, m)
    Ma = np.asarray(M, np.float32) / 255.0
    Fa = np.zeros_like(Ma)
    for dy in range(0, int(H * S) + 1, 2):
        Fa = np.maximum(Fa, _shift_down(Ma, dy))
    Fa = Fa * (1 - Ma)
    F = _L(Fa)
    U = _L(np.maximum(Ma, Fa))
    ring = a.minus(_dilate(U, max(1, int(outline * S / 2))), U)
    # the face first, then the top
    a.paint(F, face_fn, face_op)
    a.paint(M, cap_fn)
    if rim:
        top_edge = a.minus(M, ImageChops.offset(M, 0, int(0.02 * S)))
        a.paint(top_edge, (255, 250, 235), 0.26)
    seam = a.both(a.minus(_dilate(M, 3), M), F)
    a.paint(seam, (10, 8, 6), 0.45)
    a.paint(ring, OUTLINE, 0.95)
    if post:
        sz, ph = post
        px0, py0, px1, py1 = rects[0]
        Pm = a.rect(px0, py0, px1, py1)
        Pa = np.asarray(Pm, np.float32) / 255.0
        PF = np.zeros_like(Pa)
        for dy in range(0, int(ph * S) + 1, 2):
            PF = np.maximum(PF, _shift_down(Pa, dy))
        PF = PF * (1 - Pa)
        Pu = _L(np.maximum(Pa, PF))
        pr = a.minus(_dilate(Pu, max(1, int(outline * S / 2))), Pu)
        a.paint(_L(PF), face_fn, 1.0)
        a.paint(_L(PF), (10, 8, 6), 0.18)
        a.paint(Pm, cap_fn)
        a.paint(a.both(a.minus(_dilate(Pm, 3), Pm), _L(PF)), (10, 8, 6), 0.45)
        a.paint(pr, OUTLINE, 0.95)
    if decor:
        decor(a, idx, M, F)
    if shadow:
        sil = a.alpha.copy()
        a.shadow_under(0.04, 0.06, 0.028, shadow, mask_of=sil)
    return a.image(grain=GRAIN, seed=seed + idx)


def line_atlas(cat, id, label, t, H, cap_fn, face_fn, note, post=None, face_op=1.0, decor=None, mode="sprite", bg=(98, 128, 66), tags=("fence", "solid", "autotile"),
               solid="all", extra=None, seed=1, shadow=0.38, folder=None):
    sheet = sheet_cells(4, 4, PX, PX)
    cells = {}
    for idx in range(16):
        sheet.alpha_composite(line_cell(idx, t, H, cap_fn, face_fn, post, face_op, decor=decor, seed=seed, shadow=shadow), ((idx % 4) * PX, (idx // 4) * PX))
        cells[str(idx)] = [idx % 4, idx // 4]
    d = atlas_item(cat, id, sheet, 4, 4, cells, (PX, PX), list(tags), "object",
                   note + " Cell index = mask of the CONNECTED sides (the neighbour on that side is the same kind of line): N 1 + E 2 + S 4 + W 8; col = index % 4, "
                          "row = index // 4; index 0 is a lone post. The line runs through the middle of the cell. Cells are 128 x 128 px, anchor (0, 0), footprint 1 x 1.",
                   mode=mode, bg=bg, extra=dict(solid=solid, name=label, **(extra or {})), folder=folder)
    return d


def _grad(base, lo=0.84, hi=1.10, noise=0.0, seed=1, freq=8.0):
    """A colour function over the cell, lit from the top left."""
    return lit(base, lo, hi, 0.0, 0.0, 1.0, 1.0, noise, seed, freq)


def picket_face(base, seed):
    b = np.array(base, np.float32)

    def f(X, Y):
        u = np.mod(X, 0.125)
        slat = (u > 0.020) & (u < 0.105)
        idx = np.floor(X / 0.125)
        tone = (0.90 + 0.18 * mba._hash(idx.astype(np.int64), np.zeros_like(idx, np.int64) + seed, 3))[..., None]
        shade_ = (1.08 - 0.30 * np.clip((Y - 0.4) / 0.4, 0, 1))[..., None]
        edge = np.clip(np.minimum(u - 0.020, 0.105 - u) / 0.012, 0, 1)[..., None]
        col = b[None, None, :] * tone * shade_ * (0.72 + 0.28 * edge)
        gap = np.array((36, 28, 22), np.float32)[None, None, :]
        return np.where(slat[..., None], col, gap)
    return f


def mesh_face():
    def f(X, Y):
        d1 = np.abs(np.mod(X + Y, 0.10) - 0.05) < 0.007
        d2 = np.abs(np.mod(X - Y, 0.10) - 0.05) < 0.007
        base = np.array((176, 182, 188), np.float32)[None, None, :] * np.ones_like(X)[..., None]
        line_ = np.array((120, 128, 136), np.float32)[None, None, :]
        return np.where((d1 | d2)[..., None], line_, base)
    return f


def brick_face(base=(150, 86, 68)):
    def f(X, Y):
        row = np.floor(Y / 0.075).astype(np.int64)
        off = (row % 2) * 0.0625
        col = np.floor((X + off) / 0.125).astype(np.int64)
        lx = np.mod(X + off, 0.125)
        ly = np.mod(Y, 0.075)
        tone = (0.88 + 0.22 * mba._hash(row, col, 5))[..., None]
        b = np.array(base, np.float32)[None, None, :] * tone
        mortar = (lx < 0.008) | (ly < 0.007)
        return np.where(mortar[..., None], np.array((186, 174, 152), np.float32)[None, None, :] * np.ones_like(b), b * (1.0 - 0.18 * np.clip((Y - 0.5) / 0.4, 0, 1))[..., None])
    return f


def sandbag_fn(base=(196, 172, 124), face=False):
    bw, bh = 0.25, 0.16

    def f(X, Y):
        row = np.floor(Y / bh).astype(np.int64)
        off = (row % 2) * bw / 2
        col = np.floor((X + off) / bw).astype(np.int64)
        u = np.mod(X + off, bw) / bw
        v = np.mod(Y, bh) / bh
        d = np.maximum(np.abs(u - 0.5) * 2.0, np.abs(v - 0.5) * 2.0)
        dd = (np.abs(u - 0.5) * 2.0) ** 2.6 + (np.abs(v - 0.5) * 2.0) ** 2.6
        inside = dd < 0.85
        tone = (0.88 + 0.22 * mba._hash(row, col, 7))[..., None]
        hi = (1.14 - 0.34 * (u * 0.5 + v * 0.5))[..., None]
        b = np.array(base, np.float32)[None, None, :] * tone * hi * (0.80 if face else 1.0)
        seam = np.array((70, 56, 40), np.float32)[None, None, :]
        return np.where(inside[..., None], b, seam)
    return f

# ======================================================================
# OUTDOORS
# ======================================================================

def _leafy(base, seed):
    def f(X, Y):
        n = fbm(X, Y, 6.0, seed, 3)
        b = np.array(base, np.float32)[None, None, :]
        return b * (0.78 + 0.5 * n)[..., None] * (1.12 - 0.3 * np.clip(Y, 0, 1))[..., None]
    return f


def hedge_decor(a, idx, M, F):
    rng = rng_for("hedge", idx)
    Marr = np.asarray(M, np.float32) / 255.0
    ys, xs = np.nonzero(Marr[::8, ::8] > 0.5)
    pts = list(zip(xs * 8 / S, ys * 8 / S))
    for _ in range(26):
        if not pts:
            break
        x, y = pts[rng.integers(0, len(pts))]
        r = rng.uniform(0.04, 0.075)
        a.paint(a.both(a.ellipse(x, y, r, r * 0.8), M), (150, 184, 96), 0.55)
        a.paint(a.both(a.ellipse(x + r * 0.35, y + r * 0.3, r * 0.7, r * 0.5), M), (34, 66, 34), 0.35)
    for _ in range(5):
        if not pts:
            break
        x, y = pts[rng.integers(0, len(pts))]
        a.paint(a.both(a.ellipse(x, y, 0.016), M), (220, 90, 90), 0.0)


def job_outdoors_lines():
    line_atlas("outdoors", "fence_picket_white", "White picket fence", 0.07, 0.20, lambda X, Y: np.array((236, 232, 218), np.float32)[None, None, :] * np.ones_like(X)[..., None] * (1.06 - 0.12 * np.clip(Y, 0, 1))[..., None],
               picket_face((228, 224, 210), 1),
               "A white picket fence (a post in each cell, a rail with pickets in front of it).", post=(0.11, 0.30), seed=11)
    line_atlas("outdoors", "fence_picket_brown", "Weathered picket fence", 0.07, 0.20, lambda X, Y: np.array((150, 118, 84), np.float32)[None, None, :] * np.ones_like(X)[..., None] * (1.06 - 0.12 * np.clip(Y, 0, 1))[..., None],
               picket_face((144, 112, 80), 2),
               "A weathered brown picket fence.", post=(0.11, 0.30), seed=12)
    line_atlas("outdoors", "fence_chainlink", "Chain link fence", 0.05, 0.34, lambda X, Y: np.array((120, 126, 134), np.float32)[None, None, :] * np.ones_like(X)[..., None],
               mesh_face(), "A chain link fence on steel posts, see-through.", post=(0.09, 0.42), face_op=0.20, mode="glass", seed=13,
               tags=("fence", "solid", "autotile", "see_through"), shadow=0.30)
    line_atlas("outdoors", "wall_low_brick", "Low brick wall", 0.32, 0.14, lambda X, Y: np.array((196, 190, 178), np.float32)[None, None, :] * np.ones_like(X)[..., None] * (1.08 - 0.16 * np.clip(Y, 0, 1))[..., None],
               brick_face(), "A low garden wall of brick with a stone coping.", seed=14)
    line_atlas("outdoors", "hedge", "Hedge", 0.40, 0.14, _leafy((70, 110, 52), 4), _leafy((46, 78, 38), 5),
               "A clipped hedge, thick and green.", decor=hedge_decor, seed=15, tags=("fence", "solid", "autotile", "soft"))
    # a yard gate in a picket fence
    def gate(st, v):
        a = body(1, 1)
        base = (228, 224, 210)
        if st == "closed":
            a.paint(a.rect(0.0, 0.40, 1.0, 0.47), (236, 232, 218), 1.0)
            fn = picket_face(base, 3)
            a.paint(a.rect(0.05, 0.47, 0.95, 0.70), fn)
            a.paint(a.stroke([(0.05, 0.47), (0.95, 0.47), (0.95, 0.70), (0.05, 0.70)], 0.022, closed=True), OUTLINE, 0.9)
            a.paint(a.stroke([(0.05, 0.40), (0.95, 0.40), (0.95, 0.47), (0.05, 0.47)], 0.020, closed=True), OUTLINE, 0.9)
            dot(a, 0.82, 0.43, 0.022, (60, 56, 52))
        else:
            # swung back along the fence line to the left: a leaf standing at right angles, seen end on and from above
            a.paint(a.rect(0.06, 0.10, 0.14, 0.90), (236, 232, 218), 1.0)
            a.paint(a.rect(0.12, 0.10, 0.20, 0.90), picket_face(base, 3))
            a.paint(a.stroke([(0.06, 0.10), (0.20, 0.10), (0.20, 0.90), (0.06, 0.90)], 0.022, closed=True), OUTLINE, 0.9)
            for yy in np.arange(0.14, 0.9, 0.125):
                line(a, [(0.20, yy), (0.20, yy + 0.07)], 0.020, (228, 224, 210), 1.0, round_ends=False)
        for px_ in (0.05, 0.95):
            slab(a, px_ - 0.055, 0.40, px_ + 0.055, 0.50, (236, 232, 218), r=0.01, lw=0.02, lo=0.8, hi=1.1, rim=False)
        return a
    prop("outdoors", "gate_picket", 1, 1, gate, facings="hv", states=("closed", "open"), tags=["fence", "gate", "door"], layer="object",
         solid={"closed": True, "open": False}, bg=(98, 128, 66),
         note="A gate in a white picket fence, one cell: closed (the fence line runs on through it) or open (the leaf swung back). h: in a fence that runs along x.")


def bush(st, v):
    """A round shrub in the style of the trees: clumps of leaf with lighter tops, a dark outline."""
    a = body(1.3, 1.1)
    rng = rng_for("bush", v)
    base = [(70, 112, 52), (112, 120, 60), (60, 104, 56)][v]
    blobs = [(0.42, 0.62, 0.34), (0.82, 0.60, 0.30), (0.62, 0.40, 0.32), (0.34, 0.40, 0.24), (0.92, 0.42, 0.20)]
    for (cx, cy, r) in blobs:                                 # the outline round the whole bush first
        a.paint(a.ellipse(cx, cy, r + 0.026, (r + 0.026) * 0.92), OUTLINE, 1.0)
    for i, (cx, cy, r) in enumerate(blobs):
        a.paint(a.ellipse(cx, cy, r, r * 0.92), lit(shade(base, 0.9 + 0.05 * i), 0.78, 1.14, cx - r, cy - r, cx + r, cy + r))
    for (cx, cy, r) in blobs:
        a.paint(a.ellipse(cx - r * 0.25, cy - r * 0.30, r * 0.52, r * 0.44), shade(base, 1.22), 0.55)
        a.paint(a.ellipse(cx - r * 0.35, cy - r * 0.38, r * 0.20, r * 0.16), shade(base, 1.42), 0.55)
    if v == 2:        # flowers
        for _ in range(16):
            fx, fy = rng.uniform(0.2, 1.1), rng.uniform(0.2, 0.9)
            dot(a, fx, fy, 0.026, (232, 150, 170))
            dot(a, fx, fy, 0.010, (250, 230, 140))
    if v == 1:        # a few bare twigs
        for _ in range(5):
            fx, fy = rng.uniform(0.3, 1.0), rng.uniform(0.3, 0.8)
            line(a, [(fx, fy), (fx + rng.uniform(-0.1, 0.1), fy - rng.uniform(0.05, 0.12))], 0.012, (96, 72, 50), 0.9)
    return a


def mailbox(st, v):
    a = body(1, 1)
    op = st == "opened"
    a.paint(a.rect(0.46, 0.56, 0.54, 0.90), (96, 72, 52), 1.0)          # the post
    a.paint(a.stroke([(0.46, 0.56), (0.46, 0.90), (0.54, 0.90), (0.54, 0.56)], 0.014), OUTLINE, 0.8)
    c = [(70, 96, 140), (86, 122, 90)][v]
    slab(a, 0.28, 0.14, 0.72, 0.60, c, r=0.14, lw=0.026, lo=0.80, hi=1.14)
    a.paint(a.stroke([(0.34, 0.20), (0.66, 0.20)], 0.012, round_ends=False), (255, 255, 255), 0.30)
    if op:
        a.paint(a.poly([(0.30, 0.60), (0.70, 0.60), (0.70, 0.72), (0.30, 0.72)]), shade(c, 0.7), 1.0)
        a.paint(a.stroke([(0.30, 0.60), (0.30, 0.72), (0.70, 0.72), (0.70, 0.60)], 0.018), OUTLINE, 0.95)
        a.paint(a.poly([(0.40, 0.62), (0.58, 0.60), (0.60, 0.68), (0.42, 0.70)]), (234, 230, 218), 1.0)
    a.paint(a.rect(0.70, 0.22, 0.80, 0.30), (200, 60, 50), 1.0)             # the flag
    a.paint(a.stroke([(0.70, 0.22), (0.80, 0.22), (0.80, 0.30), (0.70, 0.30)], 0.012, closed=True), OUTLINE, 0.9)
    return a


def bin_(st, v):
    a = body(1, 1)
    op = st == "opened"
    c = [(70, 112, 78), (96, 100, 106)][v]
    slab(a, 0.16, 0.12, 0.84, 0.88, shade(c, 0.78), r=0.08, lw=0.028, lo=0.84, hi=1.10)
    if not op:
        a.paint(a.poly(rrect(0.14, 0.10, 0.86, 0.80, 0.08)), lit(c, 0.82, 1.14, 0.14, 0.1, 0.86, 0.8, 0.06, 5))
        a.paint(a.stroke(rrect(0.14, 0.10, 0.86, 0.80, 0.08), 0.026, closed=True), OUTLINE, 1.0)
        a.paint(a.rect(0.34, 0.66, 0.66, 0.74), shade(c, 0.6), 0.9)
        a.paint(a.stroke([(0.18, 0.16), (0.82, 0.16)], 0.012, round_ends=False), (255, 255, 255), 0.25)
    else:
        a.paint(a.poly(rrect(0.22, 0.26, 0.78, 0.82, 0.06)), (24, 20, 18), 1.0)
        for (cx, cy, c2) in ((0.40, 0.50, (190, 186, 170)), (0.60, 0.60, (150, 120, 90)), (0.5, 0.40, (110, 130, 100))):
            a.paint(a.ellipse(cx, cy, 0.09, 0.07), c2, 0.95)
        a.paint(a.poly(rrect(0.14, 0.00, 0.86, 0.18, 0.05)), lit(c, 0.82, 1.14, 0.14, 0, 0.86, 0.18))          # the lid, up at the back
        a.paint(a.stroke(rrect(0.14, 0.00, 0.86, 0.18, 0.05), 0.024, closed=True), OUTLINE, 1.0)
    return a


def bike(st, v):
    a = body(2, 1)
    c = [(176, 56, 48), (60, 126, 126)][v]
    for cx in (0.46, 1.56):
        a.paint(a.stroke([(cx + 0.36 * np.cos(t), 0.52 + 0.36 * np.sin(t)) for t in np.linspace(0, 6.3, 36)], 0.062, closed=True), OUTLINE, 1.0)
        a.paint(a.stroke([(cx + 0.36 * np.cos(t), 0.52 + 0.36 * np.sin(t)) for t in np.linspace(0, 6.3, 36)], 0.034, closed=True), (50, 50, 52), 1.0)
        for ang in range(0, 180, 30):
            t = np.radians(ang)
            line(a, [(cx - 0.34 * np.cos(t), 0.52 - 0.34 * np.sin(t)), (cx + 0.34 * np.cos(t), 0.52 + 0.34 * np.sin(t))], 0.006, (180, 182, 186), 0.7)
        dot(a, cx, 0.52, 0.03, (150, 152, 156))
    frame = [(0.46, 0.52), (0.82, 0.30), (1.24, 0.30), (1.56, 0.52), (1.12, 0.56), (0.82, 0.30)]
    a.paint(a.stroke(frame, 0.066, round_ends=True), OUTLINE, 1.0)
    a.paint(a.stroke(frame, 0.038, round_ends=True), c, 1.0)
    a.paint(a.stroke([(1.24, 0.30), (1.18, 0.16)], 0.050), OUTLINE, 1.0)
    a.paint(a.stroke([(1.24, 0.30), (1.18, 0.16)], 0.026), c, 1.0)
    a.paint(a.stroke([(1.50, 0.22), (1.50, 0.58)], 0.060), OUTLINE, 1.0)           # the handlebar
    a.paint(a.stroke([(1.50, 0.22), (1.50, 0.58)], 0.034), (50, 50, 52), 1.0)
    slab(a, 0.84, 0.18, 1.04, 0.30, (40, 38, 38), r=0.04, lw=0.02, lo=0.8, hi=1.1, rim=False)           # the saddle
    if v == 1:
        slab(a, 1.60, 0.30, 1.90, 0.62, (150, 120, 70), r=0.04, lw=0.022, lo=0.8, hi=1.1)               # a basket
    return a


def garden_bed(st, v):
    a = body(3, 1)
    slab(a, 0.05, 0.10, 2.95, 0.92, (110, 80, 54), r=0.04, lw=0.03, lo=0.84, hi=1.08, noise=0.14, seed=210, along="x")
    a.paint(a.rect(0.16, 0.22, 2.84, 0.80), lambda X, Y: np.array((70, 50, 36), np.float32)[None, None, :] * (0.86 + 0.2 * fbm(X, Y, 6.0, 3, 2))[..., None])
    rng = rng_for("bed", v)
    for r_, yy in enumerate((0.36, 0.64)):
        for i in range(9):
            cx = 0.32 + i * 0.30 + (0.1 if r_ else 0)
            if v == 0:      # cabbages
                a.paint(a.ellipse(cx, yy, 0.115, 0.10), OUTLINE, 1.0)
                a.paint(a.ellipse(cx, yy, 0.095, 0.082), lit((98, 150, 80), 0.8, 1.2, cx - 0.1, yy - 0.1, cx + 0.1, yy + 0.1))
                a.paint(a.ellipse(cx - 0.02, yy - 0.02, 0.045, 0.036), (150, 190, 120), 0.8)
            elif v == 1:    # seedlings in rows
                for k in range(3):
                    ang = k * 2.1 + i
                    line(a, [(cx, yy), (cx + 0.06 * np.cos(ang), yy + 0.05 * np.sin(ang))], 0.016, (104, 150, 70), 1.0)
                dot(a, cx, yy, 0.014, (70, 110, 50))
            else:           # gone to weed and dead stalks
                if rng.random() < 0.6:
                    for k in range(4):
                        ang = rng.uniform(0, 6.28)
                        line(a, [(cx, yy), (cx + 0.09 * np.cos(ang), yy + 0.07 * np.sin(ang))], 0.014, (126, 108, 62), 0.95)
                else:
                    a.paint(a.ellipse(cx, yy, 0.07, 0.06), (88, 120, 60), 0.95)
    return a


def shed(st, v):
    """3 x 2 footprint: a roof on top and the front wall below it (the picture is 3 x 2.4 tiles: its back is up, its door faces south)."""
    a = body(3, 2.4)
    if v == 0:
        roof_l, roof_s, wall = (136, 100, 72), (100, 72, 54), (150, 112, 78)
    else:
        roof_l, roof_s, wall = (150, 156, 160), (110, 116, 122), (126, 98, 74)
    # the roof: two slopes, ridge along x
    ry0, rym, ry1 = 0.06, 0.74, 1.42
    a.paint(a.rect(0.06, ry0, 2.94, rym), lit(roof_l, 0.86, 1.1, 0.06, ry0, 2.94, rym, 0.08, 220, 10.0, "x"))
    a.paint(a.rect(0.06, rym, 2.94, ry1), lit(roof_s, 0.86, 1.1, 0.06, rym, 2.94, ry1, 0.08, 221, 10.0, "x"))
    for yy in np.arange(ry0 + 0.17, ry1, 0.17):
        line(a, [(0.08, yy), (2.92, yy)], 0.008, shade(roof_s, 0.7), 0.55, round_ends=False)
    if v == 1:
        for xx in np.arange(0.2, 2.9, 0.22):
            line(a, [(xx, ry0), (xx, ry1)], 0.012, shade(roof_s, 0.8), 0.6, round_ends=False)
    a.paint(a.rect(0.06, rym - 0.03, 2.94, rym + 0.03), shade(roof_s, 0.7), 1.0)
    a.paint(a.stroke([(0.06, rym), (2.94, rym)], 0.014, round_ends=False), OUTLINE, 0.8)
    a.paint(a.stroke([(0.06, ry0), (2.94, ry0), (2.94, ry1), (0.06, ry1)], 0.030, closed=True), OUTLINE, 1.0)
    # the front wall: boards, a door, a window
    a.paint(a.rect(0.12, ry1, 2.88, 2.30), lit(wall, 0.80, 1.1, 0.12, ry1, 2.88, 2.3, 0.14, 222, 12.0, "x"))
    for xx in np.arange(0.12 + 0.18, 2.88, 0.18):
        line(a, [(xx, ry1), (xx, 2.30)], 0.008, shade(wall, 0.55), 0.6, round_ends=False)
    slab(a, 0.30, 1.56, 1.20, 2.30, (104, 76, 54), r=0.02, lw=0.024, lo=0.8, hi=1.1, noise=0.1, seed=223)
    a.paint(a.stroke([(0.75, 1.56), (0.75, 2.30)], 0.012, round_ends=False), OUTLINE, 0.7)
    dot(a, 1.08, 1.96, 0.026, (200, 170, 80))
    slab(a, 1.80, 1.66, 2.60, 2.06, (176, 196, 206), r=0.02, lw=0.022, lo=0.85, hi=1.1)
    line(a, [(2.2, 1.66), (2.2, 2.06)], 0.012, OUTLINE, 0.8, round_ends=False)
    line(a, [(1.80, 1.86), (2.60, 1.86)], 0.012, OUTLINE, 0.8, round_ends=False)
    a.paint(a.stroke([(0.12, ry1), (0.12, 2.30), (2.88, 2.30), (2.88, ry1)], 0.030), OUTLINE, 1.0)
    a.paint(a.rect(0.12, ry1, 2.88, ry1 + 0.05), (10, 8, 6), 0.35)
    return a


def swing_set(st, v):
    a = body(3, 2)
    for x in (0.12, 2.88):
        for dy in (0.30, 1.78):
            a.paint(a.stroke([(x, dy), (x, 0.52)], 0.055), OUTLINE, 1.0)
            a.paint(a.stroke([(x, dy), (x, 0.52)], 0.030), (80, 100, 150), 1.0)
    a.paint(a.stroke([(0.12, 0.52), (2.88, 0.52)], 0.090), OUTLINE, 1.0)
    a.paint(a.stroke([(0.12, 0.52), (2.88, 0.52)], 0.056), (86, 110, 160), 1.0)
    a.paint(a.stroke([(0.12, 0.50), (2.88, 0.50)], 0.012), (200, 220, 245), 0.7)
    for cx in (0.9, 2.1):
        for dx in (-0.18, 0.18):
            a.paint(a.stroke([(cx + dx, 0.52), (cx + dx * 0.8, 1.44)], 0.020), (60, 56, 52), 1.0)
        slab(a, cx - 0.26, 1.40, cx + 0.26, 1.64, (150, 96, 60), r=0.04, lw=0.026, lo=0.8, hi=1.12, noise=0.1, seed=230)
    return a


def slide(st, v):
    a = body(1, 3)
    slab(a, 0.12, 0.08, 0.88, 0.62, (186, 70, 56), r=0.04, lw=0.028, lo=0.8, hi=1.12)
    for yy in np.arange(0.14, 0.58, 0.10):
        line(a, [(0.16, yy), (0.84, yy)], 0.012, (120, 40, 34), 0.6, round_ends=False)
    chute = [(0.24, 0.60), (0.76, 0.60), (0.84, 2.92), (0.16, 2.92)]
    a.paint(a.poly(chute), lit((232, 196, 80), 0.84, 1.1, 0.16, 0.6, 0.84, 2.92))
    a.paint(a.stroke(chute, 0.030, closed=True), OUTLINE, 1.0)
    a.paint(a.stroke([(0.36, 0.7), (0.34, 2.8)], 0.012), (255, 244, 190), 0.5)
    a.paint(a.stroke([(0.26, 0.60), (0.18, 2.92)], 0.040), (190, 60, 48), 1.0)
    a.paint(a.stroke([(0.74, 0.60), (0.82, 2.92)], 0.040), (190, 60, 48), 1.0)
    return a


def bench(st, v):
    a = body(2, 1)
    wood = [(78, 122, 84), (150, 112, 76)][v]
    iron = (44, 44, 48)
    for xx in (0.20, 1.80):
        a.paint(a.rect(xx - 0.04, 0.22, xx + 0.04, 0.84), iron, 1.0)
    for i, (y0, y1) in enumerate(((0.12, 0.26), (0.30, 0.44), (0.50, 0.64), (0.66, 0.80))):
        slab(a, 0.06, y0, 1.94, y1, wood if i else shade(wood, 0.84), r=0.012, lw=0.024, lo=0.80, hi=1.12, noise=0.16, seed=240 + i, along="x")
    return a


def market_stall(st, v):
    """3 x 2: a plank roof over the back half, a counter with crates of produce in front."""
    a = body(3, 2)
    wood = (150, 112, 76)
    slab(a, 0.10, 1.10, 2.90, 1.84, shade(wood, 0.82), r=0.03, lw=0.028, lo=0.84, hi=1.1, noise=0.12, seed=250, along="x")
    prod = [((196, 62, 52), 0.07), ((120, 160, 70), 0.10), ((210, 170, 70), 0.075)]
    for k, cx in enumerate((0.55, 1.5, 2.45)):
        slab(a, cx - 0.40, 1.20, cx + 0.40, 1.74, wood, r=0.02, lw=0.022, lo=0.8, hi=1.1, noise=0.1, seed=251 + k)
        c, r = prod[k]
        rng = rng_for("produce", k)
        for _ in range(14):
            px_, py_ = cx + rng.uniform(-0.30, 0.30), 1.47 + rng.uniform(-0.20, 0.20)
            a.paint(a.ellipse(px_, py_, r, r * 0.9), OUTLINE, 1.0)
            a.paint(a.ellipse(px_, py_, r * 0.80, r * 0.72), lit(c, 0.8, 1.2, px_ - r, py_ - r, px_ + r, py_ + r))
    for i in range(9):
        x0 = 0.06 + i * 0.32
        a.paint(a.rect(x0, 0.06, x0 + 0.31, 1.0), lit((138 + 6 * (i % 3), 102 + 4 * (i % 3), 70), 0.84, 1.12, x0, 0.06, x0 + 0.31, 1.0, 0.14, 252 + i, 12.0, "y"))
        a.paint(a.stroke([(x0 + 0.31, 0.06), (x0 + 0.31, 1.0)], 0.010, round_ends=False), (30, 22, 16), 0.7)
    a.paint(a.rect(0.06, 0.94, 2.94, 1.06), shade(wood, 0.7), 1.0)
    a.paint(a.stroke([(0.06, 0.06), (2.94, 0.06), (2.94, 1.06), (0.06, 1.06)], 0.030, closed=True), OUTLINE, 1.0)
    a.paint(a.stroke([(0.06, 0.94), (2.94, 0.94)], 0.014, round_ends=False), OUTLINE, 0.7)
    for px_ in (0.10, 2.90):
        slab(a, px_ - 0.07, 1.04, px_ + 0.07, 1.90, shade(wood, 0.7), r=0.01, lw=0.022, lo=0.8, hi=1.1, rim=False)
    slab(a, 1.0, 1.02, 2.0, 1.12, (230, 220, 190), r=0.01, lw=0.018, lo=0.9, hi=1.05, rim=False)
    return a


def tree_item():
    """Three of the yard's own trees (assets/trees), as they are but for the size: brought to 128 px to the tile and packed into one picture."""
    srcs = [("tree_0.png", "green"), ("tree_1.png", "orange"), ("tree_3.png", "yellow")]
    cells = []
    for i, (f, nm) in enumerate(srcs):
        im = Image.open(os.path.join(ROOT, "assets", "trees", f)).convert("RGBA")
        k = 128.0 / 112.0           # the map draws them at 112 px to the tile
        im = im.resize((int(round(im.width * k)), int(round(im.height * k))), Image.LANCZOS)
        cells.append((im, {"variant": i, "colour": nm}))
    sprites = put_atlas("outdoors/tree.png", cells, "sprite")
    # the trunk's foot is 2.9 tiles down the picture and 1.4 from its left edge (assets/data/map.json 'tree': box -1.4 -2.9 1.4 0.3)
    add_item("outdoors", {"id": "tree", "category": "outdoors", "kind": "prop", "layer": "object", "footprint": [1, 1], "anchor": [0.9, 1.9],
                          "variants": 3, "tags": ["solid", "tree", "reused"], "solid": "all", "sprites": sprites, "sort_y": 2.9, "_bg": (98, 128, 66),
                          "note": "A tree from assets/trees (a: green, b: orange, c: yellow), reused as it is, at 128 px to the tile: 2.8 x 3.2 tiles with the crown "
                                  "above the trunk. The footprint is the trunk's cell, its feet on the bottom edge of the cell, 2.9 tiles down the picture: depth-sort "
                                  "on sort_y (tiles from the picture's top). Only the trunk blocks; the crown is drawn over people standing behind it."})


def _recolour_car(src, k):
    """One of the yard's car pictures without its baked shadow, turned k quarter turns clockwise, with the kit's own soft shadow, at 128 px to the tile."""
    im = Image.open(os.path.join(ROOT, "assets", "objects", src)).convert("RGBA")
    f = 128.0 / 131.0
    im = im.resize((int(round(im.width * f)), int(round(im.height * f))), Image.LANCZOS)
    arr = np.asarray(im).copy()
    arr[..., 3] = np.where(arr[..., 3] >= 150, arr[..., 3], 0)           # the body only (the old shadow is faint)
    body_im = Image.fromarray(arr)
    if k:
        body_im = body_im.rotate(-90 * k, expand=True)
    pad = 20
    out = Image.new("RGBA", (body_im.width + pad, body_im.height + pad), (0, 0, 0, 0))
    sil = np.asarray(body_im.getchannel("A"), np.float32) / 255.0
    sh = np.zeros((out.height, out.width), np.float32)
    sx, sy = int(0.07 * 128), int(0.09 * 128)
    sh[sy:sy + sil.shape[0], sx:sx + sil.shape[1]] = np.maximum(sh[sy:sy + sil.shape[0], sx:sx + sil.shape[1]], sil)
    shim = Image.fromarray((sh * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))
    shadow_im = Image.new("RGBA", out.size, (8, 6, 4, 0))
    shadow_im.putalpha(shim.point(lambda v: int(v * 0.42)))
    out.alpha_composite(shadow_im)
    out.alpha_composite(body_im, (0, 0))
    return out


def car_items():
    colours = [("red", "174_car_s0.png"), ("tan", "210_car.png"), ("white", "213_car.png"), ("charcoal", "211_car.png")]
    cells = []
    for i, (nm, f) in enumerate(colours):
        for k, o in ((0, "v"), (1, "h")):
            cells.append((_recolour_car(f, k), {"variant": i, "colour": nm, "orient": o}))
    sprites = put_atlas("outdoors/car.png", cells, "sprite")
    for sp in sprites:
        sp["fp"] = [4, 2] if sp["orient"] == "h" else [2, 4]
    add_item("outdoors", {"id": "car", "category": "outdoors", "kind": "prop", "layer": "object", "footprint": [2, 4], "anchor": [0.18, 0.12],
                          "variants": 4, "orients": ["v", "h"], "tags": ["solid", "vehicle", "parked", "reused"], "solid": "all", "sprites": sprites, "_bg": ASPHALT,
                          "note": "A parked car, the yard's own sedan pictures (assets/objects) in four colours (red, tan, white, charcoal), with the kit's shadow, one "
                                  "picture for a car along y (v: 2 x 4 cells) and one along x (h: 4 x 2). The picture is 2.2 x 4.4 tiles: it sits 0.1 tile off "
                                  "the footprint all round (anchor). The sprites have their dents and dirt: they are parked, not new."})
    wrecks = [("203_car.png", "burnt"), ("205_car.png", "stained")]
    cells = []
    for i, (f, nm) in enumerate(wrecks):
        im = Image.open(os.path.join(ROOT, "assets", "objects", f)).convert("RGBA")
        k = 128.0 / 131.0
        im = im.resize((int(round(im.width * k)), int(round(im.height * k))), Image.LANCZOS)
        cells.append((im, {"variant": i, "look": nm}))
    sprites = put_atlas("outdoors/car_wreck.png", cells, "sprite")
    add_item("outdoors", {"id": "car_wreck", "category": "outdoors", "kind": "prop", "layer": "object", "footprint": [4, 3], "anchor": [0.0, 0.0],
                          "variants": 2, "tags": ["solid", "vehicle", "wreck", "reused"], "solid": "all", "sprites": sprites, "_bg": ASPHALT,
                          "note": "A wrecked car, turned at an angle across the road, from the yard's own pictures (a: burnt out, b: stained and dented). The picture "
                                  "is about 4.3 x 2.8 tiles with its own shadow: place its middle on the middle of the 4 x 3 footprint. Solid."})


def job_outdoors():
    job_outdoors_lines()
    C = ["closed", "opened"]
    prop("outdoors", "bush", 1, 1, bush, facings=1, variants=3, tags=["solid", "bush", "soft"], pad=(0.04, 0.04, 0.2, 0.2), bg=(98, 128, 66), anchor_extra=(0.15, 0.05),
         note="A round shrub (a: green, b: dry and bare in places, c: flowering), 1.3 x 1.1 tiles on a 1 x 1 footprint. Rotate or flip freely.")
    prop("outdoors", "mailbox", 1, 1, mailbox, facings=1, states=C, variants=2, tags=["container", "solid"], bg=(98, 128, 66),
         note="A mailbox on a post. Opened: the door is down and a letter shows.")
    prop("outdoors", "bin", 1, 1, bin_, facings=1, states=C, variants=2, tags=["container", "solid", "bin"], bg=(150, 150, 140),
         note="A wheelie bin (a: green, b: grey). Opened: the lid is up, rubbish shows.")
    prop("outdoors", "bike", 2, 1, bike, facings="hv", variants=2, tags=["clutter", "walkable"], solid=[], bg=(98, 128, 66),
         note="A bicycle lying on its side (a: red, b: teal with a basket), 2 x 1 cells. Not solid.")
    prop("outdoors", "garden_bed", 3, 1, garden_bed, facings="hv", variants=3, tags=["solid", "garden"], bg=(98, 128, 66),
         note="A raised garden bed, 3 x 1 cells (a: cabbages, b: seedlings, c: weeds and dead stalks).")
    prop("outdoors", "shed", 3, 2, shed, facings=1, variants=2, tags=["solid", "building"], bg=(98, 128, 66), anchor_extra=(0.0, 0.4),
         note="A garden shed, 3 x 2 cells of footprint; the picture is taller (2.4 tiles) because it shows the roof and the front wall: its top 0.4 "
              "tile is above the footprint (anchor y). The door faces south. a: timber and shingle, b: board and corrugated iron.")
    prop("outdoors", "swing_set", 3, 2, swing_set, facings="hv", tags=["solid", "playground"], bg=(98, 128, 66), note="A swing set with two swings, 3 x 2 cells.")
    prop("outdoors", "slide", 1, 3, slide, facings=4, tags=["solid", "playground"], bg=(98, 128, 66), note="A playground slide, 1 x 3 cells, the platform at its north end (facing s: the chute runs south).")
    prop("outdoors", "bench", 2, 1, bench, variants=2, tags=["solid", "bench"], bg=(98, 128, 66), note="A bench, back to the north (a: green slats, b: wood).")
    prop("outdoors", "market_stall", 3, 2, market_stall, facings=1, tags=["solid", "stall"], bg=(150, 150, 140),
         note="A market stall, 3 x 2 cells: a plank roof over the back, a counter of crates of produce in front. Faces south (its customers). A stall may be searched like a container.")
    tree_item()
    car_items()
    contact("outdoors", scale=0.7, bg=(98, 128, 66), facings={"s"})


# ======================================================================
# FORTIFY: the pieces of the perimeter, each as built and as damaged
# ======================================================================

WOOD_BUILT, WOOD_OLD = (122, 88, 60), (96, 76, 60)


def _face_bbox(F):
    arr = np.asarray(F, np.float32) / 255.0
    ys, xs = np.nonzero(arr > 0.5)
    if len(xs) == 0:
        return None
    return xs.min() / S, ys.min() / S, xs.max() / S, ys.max() / S


def boards_face(base, rows=3, seed=1, damaged=False):
    """Horizontal boards across the front of a wall of planks."""
    b = np.array(base, np.float32)

    def f(X, Y):
        row = np.floor(Y / 0.12).astype(np.int64)
        ly = np.mod(Y, 0.12)
        tone = (0.86 + 0.28 * mba._hash(row, row * 0 + seed, 3))[..., None]
        gr = fbm(X, Y, 7.0, seed, 2, fx=0.12, fy=1.0)[..., None]
        col = b[None, None, :] * tone * (0.88 + 0.22 * gr) * (1.10 - 0.30 * np.clip(ly / 0.12, 0, 1))[..., None]
        return np.where((ly < 0.012)[..., None], np.array((24, 18, 14), np.float32)[None, None, :] * np.ones_like(col), col)
    return f


def wood_damage(a, idx, M, F):
    """Boards torn out, splintered ends, a crack in the top plank."""
    bb = _face_bbox(F)
    rng = rng_for("wood_damage", idx)
    if bb is None:
        return
    x0, y0, x1, y1 = bb
    if x1 - x0 < 0.4:
        return
    for _ in range(2):
        gx = rng.uniform(x0, max(x0 + 0.01, x1 - 0.22))
        gw = rng.uniform(0.16, 0.34)
        row = int(rng.integers(0, 3))
        gy0 = y0 + row * 0.12
        pts = [(gx, gy0), (gx + gw, gy0 + 0.01)]
        pts += [(gx + gw + rng.uniform(-0.03, 0.03), gy0 + 0.12), (gx + gw * 0.6, gy0 + 0.10 + rng.uniform(0, 0.03)), (gx + gw * 0.3, gy0 + 0.13), (gx, gy0 + 0.11)]
        a.paint(a.poly(pts), (24, 18, 14), 0.94, clip=F)
        a.paint(a.stroke(pts, 0.012, closed=True), (210, 170, 120), 0.7, clip=F)
        for k in range(3):                  # splinters
            sx = gx + gw * k / 2.0
            a.paint(a.poly([(sx, gy0 + 0.05), (sx + 0.03, gy0 + 0.0), (sx + 0.045, gy0 + 0.06)]), (196, 156, 108), 0.9, clip=F)
    cx = rng.uniform(x0 + 0.1, x1 - 0.1)
    a.paint(a.stroke([(cx, y0 - 0.07), (cx + 0.03, y0 - 0.02), (cx - 0.02, y0 + 0.03)], 0.014), (20, 14, 10), 0.8, clip=M)
    a.paint(F, (60, 50, 40), 0.18)


def corrugated_face(base, seed=1):
    b = np.array(base, np.float32)

    def f(X, Y):
        rib = 0.5 + 0.5 * np.sin(X * 2 * np.pi / 0.0625)
        k = (0.78 + 0.34 * rib)[..., None]
        col = b[None, None, :] * k * (1.06 - 0.22 * np.clip((Y - 0.4) / 0.5, 0, 1))[..., None]
        bolt = (np.abs(np.mod(X, 0.25) - 0.125) < 0.012) & (np.abs(np.mod(Y - 0.0, 0.10) - 0.05) < 0.012) & (Y > 0.5)
        return np.where(bolt[..., None], np.array((200, 204, 208), np.float32)[None, None, :] * np.ones_like(col), col)
    return f


def metal_damage(a, idx, M, F):
    bb = _face_bbox(F)
    rng = rng_for("metal_damage", idx)
    if bb is None:
        return
    x0, y0, x1, y1 = bb
    if x1 - x0 < 0.4:
        return
    for _ in range(3):                      # dents
        cx, cy = rng.uniform(x0 + 0.08, x1 - 0.08), rng.uniform(y0 + 0.05, y1 - 0.05)
        a.paint(a.blur(a.ellipse(cx, cy, 0.10, 0.07), 0.03), (20, 24, 30), 0.30, clip=F)
        a.paint(a.blur(a.ellipse(cx - 0.03, cy - 0.025, 0.06, 0.04), 0.02), (230, 236, 240), 0.22, clip=F)
    for _ in range(3):                      # rust runs
        rx = rng.uniform(x0 + 0.05, x1 - 0.05)
        a.paint(a.stroke([(rx, y0), (rx + rng.uniform(-0.02, 0.02), y1)], 0.03), (150, 78, 40), 0.55, clip=F)
    tx = rng.uniform(x0 + 0.1, max(x0 + 0.12, x1 - 0.3))
    a.paint(a.poly([(tx, y0), (tx + 0.22, y0), (tx + 0.10, y0 + 0.22)]), (20, 16, 14), 0.92, clip=F)        # torn open
    a.paint(a.stroke([(tx, y0), (tx + 0.10, y0 + 0.22), (tx + 0.22, y0)], 0.014), (200, 204, 208), 0.7, clip=F)


def sandbag_damage(a, idx, M, F):
    bb = _face_bbox(F)
    rng = rng_for("sandbag_damage", idx)
    ys, xs = np.nonzero(np.asarray(M, np.float32)[::8, ::8] > 0.5)
    if len(xs) == 0:
        return
    for _ in range(2):                      # a bag burst, sand spilled
        i = int(rng.integers(0, len(xs)))
        cx, cy = xs[i] * 8 / S, ys[i] * 8 / S
        a.paint(a.both(a.ellipse(cx, cy, 0.10, 0.07), M), (60, 48, 36), 0.85)
        a.paint(a.blur(a.ellipse(cx + 0.04, cy + 0.12, 0.12, 0.05), 0.02), (212, 190, 140), 0.85)
    a.paint(M, (50, 40, 30), 0.10)


def fort_cap(c):
    return lambda X, Y: np.array(c, np.float32)[None, None, :] * np.ones_like(X)[..., None] * (1.10 - 0.18 * np.clip(Y, 0, 1))[..., None]


def job_fortify_lines():
    for look in ("built", "damaged"):
        d = look == "damaged"
        other = "fort_fence_wood_damaged" if not d else "fort_fence_wood_built"
        line_atlas("fortify", "fort_fence_wood_" + look, "Wooden palisade fence (%s)" % look, 0.16, 0.38, fort_cap(WOOD_OLD if d else WOOD_BUILT),
                   boards_face(WOOD_OLD if d else WOOD_BUILT, 3, 7 + d), "A wooden fence of heavy planks on thick posts, the first fence the community builds: strong enough "
                   "for a night or two. %s." % ("DAMAGED: boards torn out, splintered, weathered" if d else "BUILT: new boards"), post=(0.20, 0.46),
                   decor=wood_damage if d else None, seed=30 + d, tags=("fortify", "fence", "solid", "autotile"),
                   extra={"look": look, "pair": other, "slot": "fence"}, bg=(98, 128, 66), folder="fortify")
        line_atlas("fortify", "fort_fence_reinforced_" + look, "Reinforced fence (%s)" % look, 0.18, 0.40, lambda X, Y: np.array((120, 126, 134), np.float32)[None, None, :] * np.ones_like(X)[..., None] * (1.08 - 0.16 * np.clip(Y, 0, 1))[..., None],
                   corrugated_face((92, 106, 122) if not d else (104, 100, 98), 9 + d),
                   "A reinforced fence: planks and corrugated steel sheet on steel posts. Holds longer than the wooden fence. %s." % ("DAMAGED: dented, rusted, torn open" if d else "BUILT: clean sheet and bolts"),
                   post=(0.20, 0.50), decor=metal_damage if d else None, seed=40 + d, tags=("fortify", "fence", "solid", "autotile"),
                   extra={"look": look, "pair": "fort_fence_reinforced_" + ("damaged" if not d else "built"), "slot": "fence_reinforced"}, bg=(98, 128, 66), folder="fortify")
        line_atlas("fortify", "sandbags_" + look, "Sandbags (%s)" % look, 0.34, 0.16, sandbag_fn(), sandbag_fn(face=True),
                   "A wall of sandbags, two courses of bags. %s." % ("DAMAGED: bags burst, sand spilled" if d else "BUILT: tidy courses"),
                   decor=sandbag_damage if d else None, seed=50 + d, tags=("fortify", "solid", "autotile", "cover"),
                   extra={"look": look, "pair": "sandbags_" + ("damaged" if not d else "built"), "slot": "sandbags"}, bg=(98, 128, 66), folder="fortify")


def gate_body(st, v, W=2.0):
    """A gate of W cells (2 by default) between two thick posts, running along x, the outside south. v 0 built, 1 damaged."""
    a = body(W, 1)
    mid = W / 2.0
    d = v == 1
    wood = WOOD_OLD if d else WOOD_BUILT
    iron = (70, 74, 80)
    rng = rng_for("fort_gate", v)

    def leaf(x0, x1, hinge_left, ajar):
        if not ajar:
            y0, y1 = 0.40, 0.56
            a.paint(a.blur(a.rect(x0 + 0.02, y1, x1 + 0.02, y1 + 0.06), 0.015), (8, 6, 4), 0.30)
            a.paint(a.rect(x0, y1, x1, y1 + 0.34), boards_face(wood, 3, 20 + v))
            a.paint(a.rect(x0, y0, x1, y1), lit(shade(wood, 1.10), 0.84, 1.12, x0, y0, x1, y1, 0.12, 21, 8.0, "x"))
            # a steel brace across the face, bolts, a hinge band
            a.paint(a.stroke([(x0 + 0.04, y1 + 0.04), (x1 - 0.04, y1 + 0.30)] if hinge_left else [(x0 + 0.04, y1 + 0.30), (x1 - 0.04, y1 + 0.04)], 0.044), iron, 1.0)
            a.paint(a.stroke([(x0 + 0.04, y1 + 0.04), (x1 - 0.04, y1 + 0.30)] if hinge_left else [(x0 + 0.04, y1 + 0.30), (x1 - 0.04, y1 + 0.04)], 0.044), OUTLINE, 0.0)
            for yy in (y1 + 0.10, y1 + 0.26):
                a.paint(a.rect(x0, yy - 0.025, x1, yy + 0.025), iron, 0.9)
            a.paint(a.stroke([(x0, y0), (x1, y0), (x1, y1 + 0.34), (x0, y1 + 0.34)], 0.026, closed=True), OUTLINE, 1.0)
            a.paint(a.stroke([(x0, y1), (x1, y1)], 0.012, round_ends=False), (10, 8, 6), 0.45)
            for xx in (x0 + 0.08, x1 - 0.08):
                nail(a, xx, y1 + 0.10, 0.014)
                nail(a, xx, y1 + 0.26, 0.014)
            if d:
                gx = rng.uniform(x0 + 0.1, x1 - 0.3)
                a.paint(a.poly([(gx, y1 + 0.12), (gx + 0.2, y1 + 0.12), (gx + 0.17, y1 + 0.24), (gx + 0.06, y1 + 0.22), (gx, y1 + 0.24)]), (24, 18, 14), 0.94)
                a.paint(a.stroke([(gx, y1 + 0.12), (gx + 0.2, y1 + 0.12)], 0.012), (210, 170, 120), 0.7)
        else:
            # swung part way open: the leaf seen at an angle, shorter, standing out to the north from its hinge
            hx = x0 if hinge_left else x1
            ex = hx + (0.46 if hinge_left else -0.46)
            poly = [(hx, 0.46), (ex, 0.20), (ex, 0.20 + 0.34), (hx, 0.46 + 0.34)]
            a.paint(a.blur(a.poly([(x + 0.03, y + 0.03) for x, y in poly]), 0.02), (8, 6, 4), 0.32)
            a.paint(a.poly(poly), boards_face(wood, 3, 22 + v))
            a.paint(a.stroke(poly, 0.026, closed=True), OUTLINE, 1.0)
            a.paint(a.stroke([(hx, 0.46), (ex, 0.20)], 0.040), shade(wood, 1.15), 1.0)
            a.paint(a.stroke([(hx, 0.46), (ex, 0.20)], 0.040), OUTLINE, 0.0)
            a.paint(a.stroke([(hx, 0.60), (ex, 0.34)], 0.040), iron, 0.9)

    if st == "closed":
        leaf(0.20, mid, True, False)
        leaf(mid, W - 0.20, False, False)
        a.paint(a.rect(mid - 0.02, 0.56, mid + 0.02, 0.90), (24, 18, 14), 0.8)
        a.paint(a.rect(mid - 0.10, 0.64, mid + 0.10, 0.70), iron, 1.0)      # the bar across the join
    else:
        leaf(0.20, mid, True, True)
        leaf(mid, W - 0.20, False, True)
    for px_ in (0.10, W - 0.10):         # the two posts
        slab(a, px_ - 0.10, 0.34, px_ + 0.10, 0.54, shade(wood, 0.9), r=0.01, lw=0.026, lo=0.8, hi=1.12, rim=False)
        a.paint(a.rect(px_ - 0.10, 0.54, px_ + 0.10, 0.92), boards_face(shade(wood, 0.82), 3, 25))
        a.paint(a.stroke([(px_ - 0.10, 0.34), (px_ - 0.10, 0.92), (px_ + 0.10, 0.92), (px_ + 0.10, 0.34)], 0.026), OUTLINE, 1.0)
        a.paint(a.stroke([(px_ - 0.10, 0.54), (px_ + 0.10, 0.54)], 0.012, round_ends=False), (10, 8, 6), 0.45)
    return a


def tower_body(st, v):
    """A corner watchtower: a 2 x 2 deck on stilts with a plank and sandbag parapet and a ladder, drawn 2 x 2.5 (the stilts show below the deck)."""
    a = body(2, 2.5)
    d = v == 1
    wood = WOOD_OLD if d else (146, 108, 74)
    deck = (0.04, 0.04, 1.96, 1.96)
    # the stilts and braces, seen below the deck (its south face)
    a.paint(a.rect(0.10, 1.96, 1.90, 2.46), (30, 22, 16), 0.35)
    for px_ in (0.16, 0.92, 1.84):
        a.paint(a.rect(px_ - 0.07, 1.96, px_ + 0.07, 2.46), lit(shade(wood, 0.80), 0.84, 1.1, px_ - 0.07, 1.96, px_ + 0.07, 2.46, 0.1, 31, 10.0, "y"))
        a.paint(a.stroke([(px_ - 0.07, 1.96), (px_ - 0.07, 2.46), (px_ + 0.07, 2.46), (px_ + 0.07, 1.96)], 0.022), OUTLINE, 1.0)
    for (x0, y0, x1, y1) in ((0.16, 2.0, 0.92, 2.40), (0.92, 2.0, 1.84, 2.40)):
        a.paint(a.stroke([(x0, y0), (x1, y1)], 0.05), OUTLINE, 1.0)
        a.paint(a.stroke([(x0, y0), (x1, y1)], 0.030), shade(wood, 0.9), 1.0)
    a.paint(a.rect(0.06, 1.96, 1.94, 2.04), (10, 8, 6), 0.35)
    # the deck
    a.paint(a.poly(rrect(*deck, 0.03)), lit(wood, 0.80, 1.12, 0.04, 0.04, 1.96, 1.96, 0.16, 32, 12.0, "x"))
    for yy in np.arange(0.04 + 0.19, 1.96, 0.19):
        a.paint(a.stroke([(0.06, yy), (1.94, yy)], 0.012, round_ends=False), (30, 22, 16), 0.6)
    a.paint(a.stroke(rrect(*deck, 0.03), 0.030, closed=True), OUTLINE, 1.0)
    # parapet: planks along the north and the west, sandbags along the east and a gap at the south for the ladder
    for (x0, y0, x1, y1) in ((0.04, 0.04, 1.96, 0.30), (0.04, 0.04, 0.30, 1.96)):
        a.paint(a.rect(x0, y0, x1, y1), lit(shade(wood, 0.78), 0.80, 1.14, x0, y0, x1, y1, 0.14, 33, 10.0, "x"))
        a.paint(a.stroke([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], 0.024, closed=True), OUTLINE, 1.0)
    bags = sandbag_fn()
    a.paint(a.rect(1.70, 0.30, 1.96, 1.40), lambda X, Y: bags(X * 1.0, Y * 1.0))
    a.paint(a.stroke([(1.70, 0.30), (1.70, 1.40), (1.96, 1.40), (1.96, 0.30)], 0.022), OUTLINE, 1.0)
    for (cx, cy) in ((0.17, 0.17), (1.83, 0.17), (0.17, 1.83), (1.83, 1.83)):         # corner posts
        slab(a, cx - 0.09, cy - 0.09, cx + 0.09, cy + 0.09, shade(wood, 0.7), r=0.01, lw=0.022, lo=0.8, hi=1.1, rim=False)
    # the ladder: a gap in the south edge and rungs going down
    a.paint(a.rect(1.10, 1.80, 1.50, 1.96), (20, 14, 10), 0.9)
    a.paint(a.stroke([(1.14, 1.82), (1.14, 2.44)], 0.040), OUTLINE, 1.0)
    a.paint(a.stroke([(1.46, 1.82), (1.46, 2.44)], 0.040), OUTLINE, 1.0)
    a.paint(a.stroke([(1.14, 1.82), (1.14, 2.44)], 0.022), (170, 132, 92), 1.0)
    a.paint(a.stroke([(1.46, 1.82), (1.46, 2.44)], 0.022), (170, 132, 92), 1.0)
    for yy in np.arange(1.9, 2.44, 0.12):
        a.paint(a.stroke([(1.14, yy), (1.46, yy)], 0.018), (170, 132, 92), 1.0)
    # a searchlight on the north parapet and a barrel of water
    disc(a, 0.60, 0.17, 0.10, (60, 64, 70), lw=0.02)
    a.paint(a.ellipse(0.60, 0.17, 0.055), (250, 240, 190) if not d else (70, 66, 60), 1.0)
    if d:
        a.paint(a.poly([(0.30, 0.60), (0.78, 0.44), (0.9, 0.80), (0.40, 1.0)]), (20, 14, 10), 0.92)          # a hole in the deck
        a.paint(a.stroke([(0.30, 0.60), (0.78, 0.44), (0.9, 0.80), (0.40, 1.0)], 0.020, closed=True), (200, 160, 110), 0.8)
        for (x0, y0, x1, y1) in ((0.30, 0.60, 0.50, 0.66), (0.62, 0.9, 0.9, 0.98), (1.0, 0.30, 1.30, 0.40)):
            a.paint(a.poly([(x0, y0), (x1, y0 + 0.02), (x1 - 0.02, y1), (x0 + 0.03, y1 + 0.02)]), (186, 146, 104), 0.95)
        a.paint(a.poly([(0.04, 0.30), (0.30, 0.30), (0.30, 0.9), (0.12, 0.96), (0.04, 0.7)]), (20, 14, 10), 0.0)
        a.paint(a.poly([(1.0, 0.04), (1.3, 0.04), (1.2, 0.30), (1.05, 0.26)]), (20, 14, 10), 0.92)      # a plank gone from the parapet
    return a


def floodlight_body(st, v):
    """A floodlight on a pole, 1.4 x 3.4 tiles: the foot at the bottom, the lamp head at the top."""
    a = body(1.4, 3.4)
    d = v == 1
    cx = 0.7
    top_dx = 0.16 if d else 0.0
    # the foot: a concrete block with sandbags
    slab(a, cx - 0.30, 3.00, cx + 0.30, 3.30, (156, 154, 144), r=0.02, lw=0.026, lo=0.80, hi=1.1, noise=0.1, seed=60)
    for bx in (cx - 0.46, cx + 0.12):
        a.paint(a.ellipse(bx + 0.17, 3.28, 0.17, 0.08), (186, 166, 124), 1.0)
        a.paint(a.stroke([(bx + 0.17 + 0.17 * np.cos(t), 3.28 + 0.08 * np.sin(t)) for t in np.linspace(0, 6.3, 20)], 0.014, closed=True), OUTLINE, 0.95)
    # the pole
    pole = [(cx - 0.06, 3.06), (cx + 0.06, 3.06), (cx + 0.04 + top_dx, 0.72), (cx - 0.04 + top_dx, 0.72)]
    a.paint(a.poly(pole), lit((86, 96, 106), 0.7, 1.2, cx - 0.06, 0, cx + 0.06, 1))
    a.paint(a.stroke(pole, 0.022, closed=True), OUTLINE, 1.0)
    for yy in (1.2, 1.9, 2.5):
        a.paint(a.rect(cx - 0.07 + top_dx * (3.06 - yy) / 2.34 * 0, yy, cx + 0.07, yy + 0.04), (58, 64, 72), 1.0)
    # the head: a box of four lamps
    hx = cx + top_dx
    hw, hh = 0.46, 0.30
    cy = 0.44
    ang = 0.18 if d else 0.0
    def R(x, y):
        dx, dy = x - hx, y - cy
        return (hx + dx * np.cos(ang) - dy * np.sin(ang), cy + dx * np.sin(ang) + dy * np.cos(ang))
    box = [R(hx - hw, cy - hh), R(hx + hw, cy - hh), R(hx + hw, cy + hh), R(hx - hw, cy + hh)]
    a.paint(a.poly(box), lit((54, 60, 66), 0.8, 1.14, 0.2, 0.1, 1.2, 0.8))
    a.paint(a.stroke(box, 0.026, closed=True), OUTLINE, 1.0)
    for i, (lx, ly) in enumerate(((-0.24, -0.13), (0.24, -0.13), (-0.24, 0.13), (0.24, 0.13))):
        px_, py_ = R(hx + lx, cy + ly)
        a.paint(a.ellipse(px_, py_, 0.108), (96, 102, 108), 1.0)
        a.paint(a.ellipse(px_, py_, 0.092), (30, 32, 34), 1.0)
        if d and i in (1, 2):         # smashed
            a.paint(a.ellipse(px_, py_, 0.074), (44, 46, 50), 1.0)
            for t in range(5):
                tt = t * 1.25
                line(a, [(px_, py_), (px_ + 0.07 * np.cos(tt), py_ + 0.07 * np.sin(tt))], 0.008, (200, 210, 220), 0.8)
        else:
            a.paint(a.ellipse(px_, py_, 0.074), (255, 244, 200), 1.0)
            a.paint(a.ellipse(px_ - 0.02, py_ - 0.02, 0.022), (255, 255, 255), 0.9)
        a.paint(a.stroke([(px_ + 0.100 * np.cos(t), py_ + 0.100 * np.sin(t)) for t in np.linspace(0, 6.3, 20)], 0.010, closed=True), OUTLINE, 0.95)
    if d:
        a.paint(a.stroke([(hx + 0.2, cy + 0.34), (hx + 0.34, 1.20), (hx + 0.30, 1.9), (cx + 0.22, 2.9)], 0.020), (24, 22, 20), 1.0)       # a cable hanging loose
    return a


def tower_post_body(st, v):
    """A lookout post on stilts for one shooter: a 1 x 2 deck with a plank and sandbag parapet and a ladder, drawn 1 x 2.34 (the stilts show a little below the deck)."""
    a = body(1, 2.34)
    d = v == 1
    wood = WOOD_OLD if d else (146, 108, 74)
    deck = (0.04, 0.04, 0.96, 1.96)
    # the stilts at the south edge, and a shadow under the deck
    a.paint(a.rect(0.08, 1.96, 0.92, 2.30), (30, 22, 16), 0.35)
    for px_ in (0.16, 0.84):
        a.paint(a.rect(px_ - 0.07, 1.96, px_ + 0.07, 2.32), lit(shade(wood, 0.80), 0.84, 1.1, px_ - 0.07, 1.96, px_ + 0.07, 2.32, 0.1, 31, 10.0, "y"))
        a.paint(a.stroke([(px_ - 0.07, 1.96), (px_ - 0.07, 2.32), (px_ + 0.07, 2.32), (px_ + 0.07, 1.96)], 0.022), OUTLINE, 1.0)
    a.paint(a.stroke([(0.16, 2.0), (0.84, 2.28)], 0.05), OUTLINE, 1.0)
    a.paint(a.stroke([(0.16, 2.0), (0.84, 2.28)], 0.030), shade(wood, 0.9), 1.0)
    a.paint(a.rect(0.06, 1.96, 0.94, 2.04), (10, 8, 6), 0.35)
    # the deck, its boards across
    a.paint(a.poly(rrect(*deck, 0.03)), lit(wood, 0.80, 1.12, 0.04, 0.04, 0.96, 1.96, 0.16, 32, 12.0, "x"))
    for yy in np.arange(0.04 + 0.19, 1.96, 0.19):
        a.paint(a.stroke([(0.06, yy), (0.94, yy)], 0.012, round_ends=False), (30, 22, 16), 0.6)
    a.paint(a.stroke(rrect(*deck, 0.03), 0.030, closed=True), OUTLINE, 1.0)
    # the parapet: planks along the north and the west, sandbags along the east, the south open for the ladder
    for (x0, y0, x1, y1) in ((0.04, 0.04, 0.96, 0.28), (0.04, 0.04, 0.26, 1.96)):
        a.paint(a.rect(x0, y0, x1, y1), lit(shade(wood, 0.78), 0.80, 1.14, x0, y0, x1, y1, 0.14, 33, 10.0, "x"))
        a.paint(a.stroke([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], 0.024, closed=True), OUTLINE, 1.0)
    bags = sandbag_fn()
    a.paint(a.rect(0.74, 0.28, 0.96, 1.30), lambda X, Y: bags(X * 1.0, Y * 1.0))
    a.paint(a.stroke([(0.74, 0.28), (0.74, 1.30), (0.96, 1.30), (0.96, 0.28)], 0.022), OUTLINE, 1.0)
    for (cx, cy) in ((0.15, 0.15), (0.85, 0.15), (0.15, 1.85)):         # corner posts
        slab(a, cx - 0.08, cy - 0.08, cx + 0.08, cy + 0.08, shade(wood, 0.7), r=0.01, lw=0.022, lo=0.8, hi=1.1, rim=False)
    # the ladder: a gap in the south edge and rungs going down
    a.paint(a.rect(0.38, 1.80, 0.64, 1.96), (20, 14, 10), 0.9)
    for lx in (0.40, 0.62):
        a.paint(a.stroke([(lx, 1.82), (lx, 2.30)], 0.040), OUTLINE, 1.0)
        a.paint(a.stroke([(lx, 1.82), (lx, 2.30)], 0.022), (170, 132, 92), 1.0)
    for yy in np.arange(1.9, 2.30, 0.12):
        a.paint(a.stroke([(0.40, yy), (0.62, yy)], 0.018), (170, 132, 92), 1.0)
    # a searchlight on the north parapet
    disc(a, 0.50, 0.16, 0.09, (60, 64, 70), lw=0.02)
    a.paint(a.ellipse(0.50, 0.16, 0.05), (250, 240, 190) if not d else (70, 66, 60), 1.0)
    if d:
        a.paint(a.poly([(0.30, 0.60), (0.66, 0.50), (0.72, 0.96), (0.34, 1.06)]), (20, 14, 10), 0.92)          # a hole in the deck
        a.paint(a.stroke([(0.30, 0.60), (0.66, 0.50), (0.72, 0.96), (0.34, 1.06)], 0.020, closed=True), (200, 160, 110), 0.8)
        a.paint(a.poly([(0.42, 0.04), (0.70, 0.04), (0.62, 0.28), (0.46, 0.24)]), (20, 14, 10), 0.92)            # a plank gone from the parapet
    return a


def rubble_cell(along, k):
    """What lies where a fence has fallen: planks and splinters on the ground and the stump of a post, in one cell (along x or along y); k picks one of four."""
    a = Art(1, 1)
    rng = rng_for("fence_rubble", k * 2 + (1 if along == "y" else 0))
    base = np.pi / 2 if along == "y" else 0.0

    def plank(cx, cy, ang, ln, th, tone):
        c, s_ = np.cos(ang), np.sin(ang)
        pts = [(cx + dx * c - dy * s_, cy + dx * s_ + dy * c) for dx, dy in ((-ln / 2, -th / 2), (ln / 2, -th / 2 + rng.uniform(-0.02, 0.02)), (ln / 2, th / 2), (-ln / 2, th / 2 + rng.uniform(-0.02, 0.02)))]
        a.paint(a.blur(a.poly([(x + 0.02, y + 0.03) for x, y in pts]), 0.012), (8, 6, 4), 0.30)
        a.paint(a.poly(pts), lit(shade(WOOD_OLD, tone), 0.8, 1.12, cx - 0.2, cy - 0.1, cx + 0.2, cy + 0.1, 0.16, 90 + k, 12.0, "x"))
        a.paint(a.stroke(pts, 0.022, closed=True), OUTLINE, 1.0)
        a.paint(a.stroke([pts[0], pts[1]], 0.010, round_ends=False), (210, 170, 120), 0.45)
    n = 3 + (k % 2)
    spots = [(0.22 + 0.56 * rng.random(), 0.22 + 0.56 * rng.random()) for _ in range(n)]
    for i, (cx, cy) in enumerate(spots):
        plank(cx, cy, base + rng.uniform(-0.55, 0.55), rng.uniform(0.34, 0.62), rng.uniform(0.09, 0.13), rng.uniform(0.85, 1.12))
    if k % 2 == 0:               # the stump of a post, splintered
        px_, py_ = rng.uniform(0.3, 0.7), rng.uniform(0.3, 0.7)
        pts = [(px_ - 0.09, py_ + 0.06), (px_ - 0.08, py_ - 0.07), (px_ - 0.02, py_ - 0.11), (px_ + 0.04, py_ - 0.07), (px_ + 0.09, py_ - 0.09), (px_ + 0.09, py_ + 0.07)]
        a.paint(a.poly(pts), lit(shade(WOOD_OLD, 0.8), 0.8, 1.1, px_ - 0.1, py_ - 0.1, px_ + 0.1, py_ + 0.1, 0.1, 95 + k, 10.0))
        a.paint(a.stroke(pts, 0.022, closed=True), OUTLINE, 1.0)
        a.paint(a.stroke([pts[1], pts[2], pts[3]], 0.010, round_ends=False), (210, 170, 120), 0.7)
    for _ in range(5):           # splinters
        sx, sy = rng.uniform(0.1, 0.9), rng.uniform(0.1, 0.9)
        ang = rng.uniform(0, 6.28)
        a.paint(a.poly([(sx, sy), (sx + 0.06 * np.cos(ang), sy + 0.06 * np.sin(ang)), (sx + 0.02 * np.cos(ang + 1.6), sy + 0.02 * np.sin(ang + 1.6))]), (196, 156, 108), 0.9)
    sil = a.alpha.copy()
    a.shadow_under(0.03, 0.045, 0.024, 0.30, mask_of=sil)
    return a.image(grain=GRAIN, seed=7 + k)


def fence_rubble_atlas():
    """4 x 2 cells of 128 px: the top row lies along x, the bottom row along y; four looks each."""
    sheet = sheet_cells(4, 2, PX, PX)
    cells = {}
    for row, along in enumerate(("x", "y")):
        for k in range(4):
            sheet.alpha_composite(rubble_cell(along, k), (k * PX, row * PX))
            cells["%s%d" % (along, k)] = [k, row]
    atlas_item("fortify", "fence_rubble", sheet, 4, 2, cells, (PX, PX), ["fortify", "walkable", "decal"], "decal",
               "What is left where a fence section has fallen: planks and splinters on the ground and the stump of a post, walkable. Cells are 128 x 128 px, anchor (0, 0), "
               "footprint 1 x 1; the top row lies along x (a fence that runs east to west), the bottom row along y; four looks each (pick one by the tile's coordinates). "
               "Draw it on every tile of a section that is down.",
               mode="sprite", bg=(98, 128, 66), folder="fortify", extra={"solid": [], "name": "Fallen fence"})


def door_reinforce(st, v):
    """A second layer of planks over a barricaded door (lay it over `barricade_door`): two planks crossed in an X with a steel strap, bolts at the ends; the wall runs along x."""
    a = body(1, 1)
    d = v == 1
    wood = WOOD_OLD if d else (134, 98, 66)
    iron = (70, 74, 80)
    rng = rng_for("door_reinforce", v)
    for (p0, p1) in (((0.02, 0.06), (0.98, 0.94)), ((0.02, 0.94), (0.98, 0.06))):
        if d and p0[1] > 0.5:
            p1 = (0.52, 0.52)               # one of them snapped half way
        ang = np.arctan2(p1[1] - p0[1], p1[0] - p0[0])
        nx_, ny_ = -np.sin(ang) * 0.075, np.cos(ang) * 0.075
        poly = [(p0[0] + nx_, p0[1] + ny_), (p1[0] + nx_, p1[1] + ny_), (p1[0] - nx_, p1[1] - ny_), (p0[0] - nx_, p0[1] - ny_)]
        a.paint(a.blur(a.poly([(x + 0.01, y + 0.03) for x, y in poly]), 0.012), (8, 6, 4), 0.35)
        a.paint(a.poly(poly), lit(wood, 0.8, 1.12, 0, 0, 1, 1, 0.16, 100, 12.0, "x"))
        a.paint(a.stroke(poly, 0.022, closed=True), OUTLINE, 1.0)
        a.paint(a.stroke([p0, p1], 0.020, round_ends=False), iron, 0.9)
    for (bx, by) in ((0.10, 0.12), (0.90, 0.12), (0.10, 0.88), (0.90, 0.88)):
        nail(a, bx, by, 0.018)
    a.paint(a.ellipse(0.5, 0.5, 0.055), iron, 1.0)
    a.paint(a.stroke([(0.5 - 0.055 * np.cos(t), 0.5 - 0.055 * np.sin(t)) for t in np.linspace(0, 6.3, 16)], 0.014, closed=True), OUTLINE, 0.95)
    return a


def barricade_window(st, v):
    """Heavy planks over a window cell (it lies over the wall cell and its window), the wall running along x."""
    a = body(1, 1)
    d = v == 1
    wood = WOOD_OLD if d else (150, 112, 76)
    rng = rng_for("fort_window", v)
    rows = [(0.14, 0.34), (0.38, 0.58), (0.62, 0.84)]
    for i, (y0, y1) in enumerate(rows):
        if d and i == 1:
            # a plank broken in two, one half hanging
            for (x0, x1, dy) in ((0.0, 0.40, 0.0), (0.58, 1.0, 0.10)):
                poly = [(x0, y0 + dy), (x1, y0 + dy + 0.02), (x1, y1 + dy + 0.02), (x0, y1 + dy)]
                a.paint(a.blur(a.poly([(x + 0.01, y + 0.03) for x, y in poly]), 0.012), (8, 6, 4), 0.35)
                a.paint(a.poly(poly), lit(wood, 0.8, 1.12, 0, y0, 1, y1, 0.16, 70 + i, 12.0, "x"))
                a.paint(a.stroke(poly, 0.022, closed=True), OUTLINE, 1.0)
            a.paint(a.poly([(0.40, y0), (0.46, y0 + 0.07), (0.40, y0 + 0.12), (0.46, y1)]), (24, 18, 14), 0.9)
            continue
        tilt = rng.uniform(-0.02, 0.02)
        poly = [(0.0, y0 + tilt), (1.0, y0 - tilt), (1.0, y1 - tilt), (0.0, y1 + tilt)]
        a.paint(a.blur(a.poly([(x + 0.01, y + 0.03) for x, y in poly]), 0.012), (8, 6, 4), 0.35)
        a.paint(a.poly(poly), lit(wood, 0.8, 1.12, 0, y0, 1, y1, 0.16, 70 + i, 12.0, "x"))
        a.paint(a.stroke(poly, 0.024, closed=True), OUTLINE, 1.0)
        line(a, [(0.02, y0 + 0.025 + tilt), (0.98, y0 + 0.025 - tilt)], 0.010, (220, 184, 140), 0.45, round_ends=False)
        for nx_ in (0.10, 0.50, 0.90):
            nail(a, nx_, (y0 + y1) / 2 + tilt * (1 - 2 * nx_), 0.016)
    # a cross brace and, built, a steel strap
    if not d:
        a.paint(a.stroke([(0.12, 0.10), (0.88, 0.90)], 0.060), OUTLINE, 1.0)
        a.paint(a.stroke([(0.12, 0.10), (0.88, 0.90)], 0.036), shade(wood, 0.86), 1.0)
        for p in ((0.30, 0.30), (0.70, 0.70)):
            nail(a, p[0], p[1], 0.016)
    else:
        a.paint(a.stroke([(0.12, 0.10), (0.40, 0.38)], 0.060), OUTLINE, 1.0)
        a.paint(a.stroke([(0.12, 0.10), (0.40, 0.38)], 0.036), shade(wood, 0.86), 1.0)
    return a


def barricade_door(st, v):
    """A door cell barricaded from inside: planks nailed across and a dresser pushed against it; the wall runs along x."""
    a = body(1, 1)
    d = v == 1
    wood = WOOD_OLD if d else (146, 108, 74)
    rng = rng_for("fort_door", v)
    a.paint(a.rect(0.0, 0.0, 1.0, 1.0), (30, 22, 16), 0.0)
    # a heavy bar across
    for i, (y0, y1) in enumerate(((0.08, 0.30), (0.34, 0.56), (0.60, 0.82))):
        if d and i == 2:
            poly = [(0.0, y0 + 0.08), (0.46, y0 + 0.04), (0.52, y1 + 0.10), (0.0, y1 + 0.14)]
        else:
            poly = [(0.0, y0), (1.0, y0 + rng.uniform(-0.01, 0.01)), (1.0, y1), (0.0, y1)]
        a.paint(a.blur(a.poly([(x + 0.01, y + 0.03) for x, y in poly]), 0.012), (8, 6, 4), 0.35)
        a.paint(a.poly(poly), lit(wood, 0.8, 1.12, 0, y0, 1, y1, 0.16, 80 + i, 12.0, "x"))
        a.paint(a.stroke(poly, 0.024, closed=True), OUTLINE, 1.0)
        for nx_ in (0.10, 0.9):
            nail(a, nx_, (y0 + y1) / 2, 0.016)
    iron = (70, 74, 80)
    a.paint(a.rect(0.0, 0.40, 1.0, 0.50), iron, 0.0)
    a.paint(a.stroke([(0.50, 0.06), (0.50, 0.94)], 0.070), OUTLINE, 1.0 if not d else 0.0)
    if not d:
        a.paint(a.stroke([(0.50, 0.06), (0.50, 0.94)], 0.044), shade(wood, 0.82), 1.0)
        nail(a, 0.5, 0.2, 0.016)
        nail(a, 0.5, 0.5, 0.016)
        nail(a, 0.5, 0.8, 0.016)
    else:
        a.paint(a.poly([(0.46, 0.06), (0.56, 0.06), (0.54, 0.40), (0.48, 0.44)]), shade(wood, 0.82), 1.0)
        a.paint(a.stroke([(0.46, 0.06), (0.56, 0.06), (0.54, 0.40), (0.48, 0.44)], 0.020, closed=True), OUTLINE, 1.0)
        a.paint(a.poly([(0.30, 0.70), (0.42, 0.64), (0.50, 0.74), (0.36, 0.80)]), (186, 146, 104), 0.95)
    return a


def job_fortify():
    job_fortify_lines()
    names = ["built", "damaged"]
    prop("fortify", "fort_gate", 2, 1, gate_body, facings="hv", states=("closed", "open"), variants=2, variant_names=names, tags=["fortify", "gate", "door"], layer="object",
         solid={"closed": True, "open": False}, bg=(98, 128, 66),
         note="The fence gate of the perimeter, two cells wide (replaces two cells of the fence line), between two thick posts: closed, or open (both leaves "
              "swung back). variant 0 is the BUILT look, variant 1 the DAMAGED one (a board torn out, hanging). h: in a fence that runs along x with the "
              "outside to the south; v: in one that runs along y. A closed gate blocks.")
    prop("fortify", "fort_tower", 2, 2, tower_body, facings=1, variants=2, variant_names=names, tags=["fortify", "tower", "solid", "post"], bg=(98, 128, 66), anchor_extra=(0.0, 0.5),
         note="A corner watchtower: a 2 x 2 deck on stilts with a plank and sandbag parapet, a searchlight and a ladder. The picture is 2.5 tiles tall because "
              "the stilts show below the deck: the footprint is the bottom 2 rows (anchor y 0.5 + padding). variant 0 BUILT, variant 1 DAMAGED (a hole in "
              "the deck, a plank gone).")
    prop("fortify", "floodlight", 1, 1, floodlight_body, facings=1, variants=2, variant_names=names, tags=["fortify", "light", "solid"], pad=(0.0625, 0.0625, 0.25, 0.25),
         anchor_extra=(0.2, 3.0), bg=(98, 128, 66),
         note="A floodlight on a pole with four lamps, a block and sandbags at its foot: 1.4 x 3.4 tiles, the footprint is the block's cell at the bottom (anchor "
              "(0.2, 3.0) + padding). variant 0 BUILT (lamps lit: put the engine's light on the head), variant 1 DAMAGED (leaning, two lamps smashed, a cable hanging).")
    prop("fortify", "fort_gate_wide", 3, 1, lambda st, v: gate_body(st, v, 3.0), facings="hv", states=("closed", "open"), variants=2, variant_names=names, tags=["fortify", "gate", "door"],
         layer="object", solid={"closed": True, "open": False}, bg=(98, 128, 66),
         note="The same gate three cells wide (the base's gate slot is three tiles): closed, or open (both leaves swung back); variant 0 BUILT, 1 DAMAGED; h: in a fence that runs "
              "along x with the outside to the south; v: along y. A closed gate blocks.")
    prop("fortify", "fort_tower_post", 1, 2, tower_post_body, facings=1, variants=2, variant_names=names, tags=["fortify", "tower", "solid", "post"], bg=(98, 128, 66), anchor_extra=(0.0, 0.34),
         note="A lookout post for one shooter on a 1 x 2 tile footprint (the tower's slot tile and the post tile beside it): a deck on stilts with a plank and sandbag parapet, "
              "a searchlight and a ladder. The picture is 2.34 tiles tall because the stilts show below the deck: the footprint is the bottom 2 rows (anchor y 0.34 + padding). "
              "variant 0 BUILT, variant 1 DAMAGED (a hole in the deck, a plank gone). The shooter stands on the deck: draw it under the people.")
    fence_rubble_atlas()
    prop("fortify", "door_reinforce", 1, 1, door_reinforce, facings="hv", variants=2, variant_names=names, tags=["fortify", "overlay", "door", "solid"], layer="wall",
         pad=(0, 0, 0, 0), shadow=None, bg=(150, 90, 70),
         note="Two planks crossed in an X with a steel strap, laid OVER `barricade_door`: the barred door that has the plank kit. variant 0 BUILT, 1 DAMAGED (one plank snapped).")
    prop("fortify", "barricade_window", 1, 1, barricade_window, facings="hv", variants=2, variant_names=names, tags=["fortify", "overlay", "window", "solid"], layer="wall",
         pad=(0, 0, 0, 0), shadow=None, bg=(150, 90, 70),
         note="Heavy planks and a brace over a window cell: lay it OVER the wall cell and the window (h: a wall that runs along x). variant 0 BUILT, variant 1 "
              "DAMAGED (a plank broken, the brace snapped).")
    prop("fortify", "barricade_door", 1, 1, barricade_door, facings="hv", variants=2, variant_names=names, tags=["fortify", "overlay", "door", "solid"], layer="wall",
         pad=(0, 0, 0, 0), shadow=None, bg=(150, 90, 70),
         note="A door cell barricaded with planks and a heavy bar: lay it OVER the door cell (h: the wall runs along x). variant 0 BUILT, variant 1 DAMAGED.")
    contact("fortify", scale=0.7, bg=(98, 128, 66))


# ======================================================================
# MARKERS: the few world markers the HUD does not have
# ======================================================================

def enter_marker(st, v):
    """A doorway chevron: two nested chevrons pointing south (the way it points is the way you would go)."""
    a = body(1, 1)
    for i, (cy, op) in enumerate(((0.30, 1.0), (0.58, 0.85))):
        pts = [(0.22, cy - 0.12), (0.5, cy + 0.12), (0.78, cy - 0.12)]
        a.paint(a.stroke(pts, 0.17, round_ends=False), OUTLINE, 0.9 * op)
        a.paint(a.stroke(pts, 0.11, round_ends=False), (255, 236, 160), op)
        a.paint(a.stroke([(0.26, cy - 0.10), (0.5, cy + 0.09)], 0.03, round_ends=False), (255, 255, 235), 0.7 * op)
    return a


def searched_marker(st, v):
    """A small tick on a dark round badge, half a tile across, to float over a container that has been searched."""
    a = body(0.5, 0.5)
    a.paint(a.ellipse(0.25, 0.25, 0.22), OUTLINE, 0.95)
    a.paint(a.ellipse(0.25, 0.25, 0.19), (46, 70, 52), 1.0)
    pts = [(0.14, 0.26), (0.22, 0.34), (0.37, 0.15)]
    a.paint(a.stroke(pts, 0.07), (10, 20, 12), 0.9)
    a.paint(a.stroke(pts, 0.045), (170, 236, 150), 1.0)
    return a


def job_marker():
    prop("marker", "marker_enter", 1, 1, enter_marker, facings=4, tags=["marker", "walkable"], layer="decal", solid=[], pad=(0, 0, 0, 0), shadow=None, mode="glass", bg=(120, 90, 60),
         note="An 'enter' doorway chevron for a door cell or the cell in front of it: two chevrons pointing the way you go (facing s: they point south, so for a "
              "front door in a south wall you want n, pointing into the house). Pulse its alpha in the engine.")
    prop("marker", "marker_searched", 0.5, 0.5, searched_marker, facings=1, tags=["marker"], layer="decal", solid=[], pad=(0, 0, 0.0625, 0.0625), shadow=(0.02, 0.03, 0.015, 0.4), bg=(150, 130, 120),
         note="A tick on a dark badge, half a tile across (64 px), for a container that has been searched: float it over the container's middle.")
    contact("marker", scale=1.0, bg=(120, 90, 60))


# --JOBS--

JOBS = {}
for _c in CATEGORIES:
    if "job_" + _c in globals():
        JOBS[_c] = globals()["job_" + _c]


def main(argv):
    only = argv[1:] or list(JOBS)
    for c in only:
        if c not in JOBS:
            print("unknown category", c, "- one of", ", ".join(JOBS))
            return 1
    for c in only:
        JOBS[c]()
    write_manifest(set(only))
    total = sum(BYTES.values())
    print("files", len(BYTES), "bytes", total // 1024, "KB; biggest", max(BYTES.items(), key=lambda kv: kv[1]) if BYTES else "-")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

