"""Prison experiment, round 7: packs the renders of tools/make_pawn_dirs_blender.py into the game's atlases.

    python3 tools/pack_pawn_dirs.py <renders dir> [look,look,...]        (writes assets/pawns16/<look>.png and assets/pawns16/index.json)

For every look: reads <renders>/<look>/f<frame>_d<dir>.png (the colour render, 320 px to the tile) and i<frame>_d<dir>.png (a flat colour for each part of the body),
draws the dark ink line round the silhouette and thin lines where two parts of the body meet (the baked bust of assets/pawns has both), halves the size to the game's 160 px to
the tile (a 2x antialiasing), crops every picture to one cell size common to the look, packs the cells in a grid (one column for each heading, one row for each frame) with a
gutter, quantises the colours (the soft edge keeps its alpha) and writes the atlas. index.json holds, for each look: the file, the cell size in px, the origin (the point
the rules put the person at) in the cell, the gutter, the number of headings and frames, and the pixels to the tile.
Only PIL and numpy are used.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/pawns16")
DENSITY = 160.0              # px to the tile of the game's baked art (assets/data/map.json pawn.density)
SS = 2                       # renders are 2x
INK = np.array([26, 20, 15], np.float32)
OUTER = 5.0                  # the silhouette line, px at 160 to the tile (the bust's is 4 to 5)
INNER = 2.4                  # the line between parts of the body
GUTTER = 2
COLORS = 84


def blur_mask(m, r):
    return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0


def dilate(m, r):
    """A round dilation by r px: blur the mask and keep what is over a threshold that makes the edge move about r."""
    if r <= 0:
        return m
    b = blur_mask(m, r * 0.62)
    return np.clip((b - 0.07) * 6.0, 0.0, 1.0)


def finish(color, ids):
    """color: float HxWx4 (0..1, straight alpha) at SS * DENSITY; ids: uint8 HxWx3 part colours. Returns premultiplied-correct RGBA at DENSITY, with the lines."""
    a = color[..., 3]
    rgb = color[..., :3] * 255.0
    inside = (a > 0.02).astype(np.float32)
    # the lines between parts: where the part colour changes between two figure pixels
    pid = np.zeros(ids.shape[:2], np.int32)
    pid += (ids[..., 0] > 127) * 1 + (ids[..., 1] > 127) * 2 + (ids[..., 2] > 127) * 4
    pid[inside < 0.5] = 0
    edge = np.zeros(pid.shape, np.float32)
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        sh = np.roll(np.roll(pid, dy, 0), dx, 1)
        edge = np.maximum(edge, ((pid != sh) & (pid > 0) & (sh > 0)).astype(np.float32))
    line = dilate(edge, INNER * SS * 0.5) * inside
    rgb = rgb * (1 - line[..., None] * 0.9) + INK * (line[..., None] * 0.9)
    # the silhouette line: the figure grown by OUTER px, painted under it
    grown = dilate(inside, OUTER * SS)
    outer = np.clip(grown - a, 0.0, 1.0)
    # composite: the figure over the ink (straight alpha out)
    out_a = np.clip(a + outer * (1 - a), 0.0, 1.0)
    out_rgb = np.where(out_a[..., None] > 0, (rgb * a[..., None] + INK * (outer * (1 - a))[..., None]) / np.maximum(out_a[..., None], 1e-4), 0.0)
    # down to the game's size, in premultiplied space so that the edge does not bleed
    pm = np.concatenate([out_rgb * out_a[..., None], out_a[..., None] * 255.0], -1)
    h, w = pm.shape[:2]
    im = Image.fromarray(pm.astype(np.float32), "RGBA") if False else None
    chans = []
    for c in range(4):
        ch = Image.fromarray(pm[..., c].astype(np.float32), "F")
        chans.append(np.asarray(ch.resize((w // SS, h // SS), Image.LANCZOS), np.float32))
    pm2 = np.stack(chans, -1)
    al = np.clip(pm2[..., 3], 0, 255)
    rgb2 = np.where(al[..., None] > 0.5, pm2[..., :3] / np.maximum(al[..., None] / 255.0, 1e-4), 0.0)
    res = np.concatenate([np.clip(rgb2, 0, 255), al[..., None]], -1)
    return res.astype(np.uint8)


def pack(name, rdir):
    fr, dr = 0, 0
    while os.path.exists(os.path.join(rdir, "f%d_d00.png" % fr)):
        fr += 1
    while os.path.exists(os.path.join(rdir, "f0_d%02d.png" % dr)):
        dr += 1
    cells = {}
    boxes = []
    for f in range(fr):
        for d in range(dr):
            c = np.asarray(Image.open(os.path.join(rdir, "f%d_d%02d.png" % (f, d))).convert("RGBA"), np.float32) / 255.0
            i = np.asarray(Image.open(os.path.join(rdir, "i%d_d%02d.png" % (f, d))).convert("RGB"))
            px = finish(c, i)
            cells[(f, d)] = px
            ys, xs = np.nonzero(px[..., 3] > 6)
            boxes.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    H, W = cells[(0, 0)].shape[:2]
    cx, cy = W // 2, H // 2          # the figure's origin: the middle of the render
    l = min(b[0] for b in boxes)
    t = min(b[1] for b in boxes)
    r = max(b[2] for b in boxes)
    bt = max(b[3] for b in boxes)
    # one cell for every picture of the look, with the origin at the same place in each
    ox = max(cx - l, r - cx) + 1       # symmetric about the origin's column so that a mirror (never needed) would also fit
    cw = ox * 2
    ch = bt - t + 1
    oy = cy - t
    gw, gh = cw + 2 * GUTTER, ch + 2 * GUTTER
    atlas = np.zeros((gh * fr, gw * dr, 4), np.uint8)
    for (f, d), px in cells.items():
        x0 = d * gw + GUTTER
        y0 = f * gh + GUTTER
        sub = px[t:bt + 1, cx - ox:cx + ox]
        atlas[y0:y0 + sub.shape[0], x0:x0 + sub.shape[1]] = sub
    im = Image.fromarray(atlas, "RGBA")
    q = quantize(im)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    q.save(path, optimize=True)
    meta = {"file": "res://assets/pawns16/%s.png" % name, "cell": [int(cw), int(ch)], "origin": [int(ox), int(oy)], "gutter": GUTTER, "dirs": dr, "frames": fr, "density": DENSITY, "bytes": os.path.getsize(path)}
    print(name, meta)
    return meta


def quantize(im):
    """A palette PNG of at most 256 entries: COLORS opaque colours (median cut of the colour planes) times three alpha steps for the soft edge, and entry 0 clear."""
    a = np.asarray(im)
    steps = np.array([0, 85, 170, 255], np.int32)
    step_no = np.argmin(np.abs(a[..., 3:4].astype(np.int32) - steps[None, None, :]), -1)
    pal_img = Image.fromarray(a[..., :3].copy(), "RGB").quantize(colors=COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = pal_img.getpalette()[:3 * COLORS]
    pal += [0] * (3 * COLORS - len(pal))
    idx = np.asarray(pal_img, np.int32)
    ent = np.where(step_no == 0, 0, 1 + idx + COLORS * (step_no - 1))
    palette = [0, 0, 0]
    trns = [0]
    for s in (1, 2, 3):
        palette += pal
        trns += [int(steps[s])] * COLORS
    out = Image.fromarray(ent.astype(np.uint8), "P")
    out.putpalette(palette)
    out.info["transparency"] = bytes(trns)
    return out


def sheet(names, old, path):
    """A contact sheet from the atlases: for each look a row of the 16 headings (frame 0), a row of the 6 frames of the stride facing south, and, for comparison, the old baked views S, E, N."""
    index = json.load(open(os.path.join(OUT, "index.json")))["sets"]
    rows = []
    for n, o in zip(names, old):
        m = index[n]
        at = Image.open(os.path.join(ROOT, m["file"].replace("res://", ""))).convert("RGBA")
        cw, ch = m["cell"]
        g = m["gutter"]
        ox, oy = m["origin"]

        def cell(d, f):
            return at.crop((d * (cw + 2 * g) + g, f * (ch + 2 * g) + g, d * (cw + 2 * g) + g + cw, f * (ch + 2 * g) + g + ch))
        W, H = 230, 270
        row = Image.new("RGBA", (W * 16, H * 2), (96, 100, 96, 255))
        for d in range(16):
            row.alpha_composite(cell(d, 0), (d * W + W // 2 - ox, 200 - oy))
        for f in range(6):
            row.alpha_composite(cell(4, f), (f * W + W // 2 - ox, H + 200 - oy))
        for k, v in enumerate("SEN"):
            im = Image.open(os.path.join(ROOT, "assets/pawns/%s_%s.png" % (o, v)))
            row.alpha_composite(im.crop((184 - 115, 227 - 190, 184 + 115, 227 + 80)), ((7 + k) * W, H))
        rows.append(row)
    out = Image.new("RGBA", (rows[0].width, sum(r.height for r in rows)))
    y = 0
    for r in rows:
        out.alpha_composite(r, (0, y))
        y += r.height
    out.convert("RGB").save(path)


if __name__ == "__main__" and sys.argv[1] == "--sheets":
    d = os.path.join(ROOT, "docs/experiments/prison")
    sheet(["ruth"], ["ruth"], os.path.join(d, "dirs_ruth.png"))
    sheet(["walt", "dez", "sol", "rae"], ["walt", "dez", "hector", "ana"], os.path.join(d, "dirs_guard.png"))
    sheet(["z0", "z1"], ["z0", "z1"], os.path.join(d, "dirs_zombie.png"))
    sys.exit(0)

if __name__ == "__main__":
    rdir = sys.argv[1]
    names = sys.argv[2].split(",") if len(sys.argv) > 2 else sorted(d for d in os.listdir(rdir) if os.path.isdir(os.path.join(rdir, d)))
    idx_path = os.path.join(OUT, "index.json")
    index = json.load(open(idx_path)) if os.path.exists(idx_path) else {"sets": {}}
    for n in names:
        index["sets"][n] = pack(n, os.path.join(rdir, n))
    os.makedirs(OUT, exist_ok=True)
    json.dump(index, open(idx_path, "w"), indent=1, sort_keys=True)
