"""Prison experiment, round 8: packs the renders of tools/make_zombie_dirs_blender.py into assets/zombies16/<set>.png and assets/zombies16/index.json.

    python3 tools/pack_zombie_dirs.py <renders dir> [set,set,...] [--colors=N]      (a set is "<kind>_<look>", e.g. walker_0)
    python3 tools/pack_zombie_dirs.py --sheets                                          (the contact sheets in docs/experiments/prison/zombies_*.png)

One atlas per set (a look of a kind). The atlas is a stack of pose regions; a region is a grid with a column for each heading and a row for each frame, with its own cell size and origin
(the figure's origin, where the rules put it, in the cell), so that a lying corpse does not pay for a standing cell. The ink line, the part lines and the halving to 160 px to the tile
are those of tools/pack_pawn_dirs.py (finish). The atlas is a palette PNG: COLORS opaque colours times three alpha steps.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack_pawn_dirs as PP   # noqa: E402

ROOT = PP.ROOT
OUT = os.path.join(ROOT, "assets/zombies16")
GUTTER = 2
POSES = ["walk", "idle", "attack", "hurt", "deathf", "deathb"]
# What of the renders goes into the atlas (the web budget): per kind and pose the frames kept (indices of the render) and the stride over the headings (2 keeps every second one).
# A pose that is not listed keeps everything; a pose set to None is left out (the game then uses the nearest other: see pawn_dirs.gd POSE_FALLBACK).
KEEP = {
    "walker": {"walk": ([0, 1, 3, 4, 5, 7], 1), "idle": ([0, 2], 1), "attack": ([0, 2, 3], 1), "hurt": ([1], 1), "deathf": ([0, 1, 3], 1), "deathb": None},
    "runner": {"walk": (None, 1), "idle": None, "attack": ([0, 2], 1), "hurt": ([1], 1), "deathf": ([1, 3], 1), "deathb": None},
    "brute": {"walk": ([0, 1, 3, 4], 2), "idle": None, "attack": ([0, 2], 1), "hurt": ([1], 1), "deathf": ([1, 3], 1), "deathb": None},
    "crawler": {"walk": (None, 2), "idle": None, "attack": ([0, 2], 1), "hurt": ([1], 1), "deathf": ([1, 3], 1), "deathb": None},
}
OPT = {a.split("=")[0]: a.split("=")[1] for a in sys.argv if a.startswith("--") and "=" in a}
PP.COLORS = int(OPT.get("--colors", 20))


def region(rdir, pose, keep=(None, 1)):
    fr = 0
    while os.path.exists(os.path.join(rdir, "%s_f%d_d00.png" % (pose, fr))):
        fr += 1
    dr = 0
    while os.path.exists(os.path.join(rdir, "%s_f0_d%02d.png" % (pose, dr))):
        dr += 1
    if fr == 0:
        return None
    flist = keep[0] if keep[0] is not None else list(range(fr))
    dlist = list(range(0, dr, keep[1]))
    cells, boxes = {}, []
    for fo, f in enumerate(flist):
        for do, d in enumerate(dlist):
            c = np.asarray(Image.open(os.path.join(rdir, "%s_f%d_d%02d.png" % (pose, f, d))).convert("RGBA"), np.float32) / 255.0
            i = np.asarray(Image.open(os.path.join(rdir, "i%s_f%d_d%02d.png" % (pose, f, d))).convert("RGB"))
            px = PP.finish(c, i)
            cells[(fo, do)] = px
            ys, xs = np.nonzero(px[..., 3] > 6)
            boxes.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    fr, dr = len(flist), len(dlist)
    H, W = cells[(0, 0)].shape[:2]
    cx, cy = W // 2, H // 2
    l, t = min(b[0] for b in boxes), min(b[1] for b in boxes)
    r, bt = max(b[2] for b in boxes), max(b[3] for b in boxes)
    ox = max(cx - l, r - cx) + 1
    cw, ch, oy = ox * 2, bt - t + 1, cy - t
    gw, gh = cw + 2 * GUTTER, ch + 2 * GUTTER
    img = np.zeros((gh * fr, gw * dr, 4), np.uint8)
    for (f, d), px in cells.items():
        sub = px[t:bt + 1, cx - ox:cx + ox]
        img[f * gh + GUTTER:f * gh + GUTTER + sub.shape[0], d * gw + GUTTER:d * gw + GUTTER + sub.shape[1]] = sub
    return {"img": img, "cell": [int(cw), int(ch)], "origin": [int(ox), int(oy)], "dirs": dr, "frames": fr}


def pack(name, rdir):
    kind = name.rsplit("_", 1)[0]
    regs = {}
    for p in POSES:
        k = KEEP[kind].get(p, (None, 1))
        regs[p] = region(rdir, p, k) if k is not None else None
    regs = {p: r for p, r in regs.items() if r is not None}
    W = max(r["img"].shape[1] for r in regs.values())
    H = sum(r["img"].shape[0] for r in regs.values())
    atlas = np.zeros((H, W, 4), np.uint8)
    y = 0
    meta_p = {}
    for p, r in regs.items():
        h, w = r["img"].shape[:2]
        atlas[y:y + h, :w] = r["img"]
        meta_p[p] = {"y": y, "cell": r["cell"], "origin": r["origin"], "dirs": r["dirs"], "frames": r["frames"]}
        y += h
    q = PP.quantize(Image.fromarray(atlas, "RGBA"))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    q.save(path, optimize=True)
    m = {"file": "res://assets/zombies16/%s.png" % name, "gutter": GUTTER, "density": PP.DENSITY, "poses": meta_p, "size": [W, H], "bytes": os.path.getsize(path)}
    print(name, m["size"], m["bytes"])
    return m


def cell(at, m, pose, f, d):
    p = m["poses"][pose]
    cw, ch = p["cell"]
    g = m["gutter"]
    gw, gh = cw + 2 * g, ch + 2 * g
    return at.crop((d * gw + g, p["y"] + f * gh + g, d * gw + g + cw, p["y"] + f * gh + g + ch))


def sheets():
    idx = json.load(open(os.path.join(OUT, "index.json")))["sets"]
    D = os.path.join(ROOT, "docs/experiments/prison")
    ats = {n: Image.open(os.path.join(ROOT, m["file"].replace("res://", ""))).convert("RGBA") for n, m in idx.items()}
    BG = (96, 100, 96, 255)

    def put(sheet, at, m, pose, f, d, x, y, W, base):
        p = m["poses"][pose]
        sheet.alpha_composite(cell(at, m, pose, f, d), (x + W // 2 - p["origin"][0], y + base - p["origin"][1]))

    # one sheet for each kind: for every look a row of 16 headings (walk frame 0), then its walk cycle facing south
    for kind in ("walker", "runner", "brute", "crawler"):
        names = sorted(n for n in idx if n.startswith(kind + "_"))
        if not names:
            continue
        W, H = 230, 300
        sh = Image.new("RGBA", (W * 16, H * 2 * len(names)), BG)
        for r, n in enumerate(names):
            m, at = idx[n], ats[n]
            for d in range(16):
                put(sh, at, m, "walk", 0, d, d * W, r * 2 * H, W, 215)
            for f in range(m["poses"]["walk"]["frames"]):
                put(sh, at, m, "walk", f, 4, f * W, r * 2 * H + H, W, 215)
        sh.convert("RGB").save(os.path.join(D, "zombies_%s.png" % kind))
    # the poses of every kind's first look: idle, attack, hurt, deathf, deathb strips at 8 headings (south, east, north) and the corpses
    names = [n for n in ("walker_0", "walker_2", "walker_5", "runner_0", "brute_0", "crawler_0") if n in idx]
    W, H = 230, 300
    cols = []
    for n in names:
        m = idx[n]
        for pose in ("idle", "attack", "hurt", "deathf", "deathb"):
            if pose in m["poses"]:
                cols.append((n, pose))
    maxf = 4
    sh = Image.new("RGBA", (W * maxf * 3, H * len(cols)), BG)
    for r, (n, pose) in enumerate(cols):
        m, at = idx[n], ats[n]
        p = m["poses"][pose]
        for k, d8 in enumerate((2, 0, 6)):      # south, east, north (8 headings: 0 east, 2 south, 4 west, 6 north)
            for f in range(p["frames"]):
                put(sh, at, m, pose, f, d8, (k * maxf + f) * W, r * H, W, 215)
    sh.convert("RGB").save(os.path.join(D, "zombies_poses.png"))
    # every walker look side by side, facing south, plus an angled heading
    names = sorted(n for n in idx if n.startswith("walker_"))
    sh = Image.new("RGBA", (W * len(names), H * 2), BG)
    for k, n in enumerate(names):
        put(sh, ats[n], idx[n], "walk", 0, 4, k * W, 0, W, 215)
        put(sh, ats[n], idx[n], "walk", 2, 2, k * W, H, W, 215)
    sh.convert("RGB").save(os.path.join(D, "zombies_looks.png"))


if __name__ == "__main__" and "--sheets" in sys.argv:
    sheets()
    sys.exit(0)

if __name__ == "__main__":
    rdir = sys.argv[1]
    names = sys.argv[2].split(",") if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else sorted(d for d in os.listdir(rdir) if os.path.isdir(os.path.join(rdir, d)))
    ip = os.path.join(OUT, "index.json")
    for n in names:
        m = pack(n, os.path.join(rdir, n))
        index = json.load(open(ip)) if os.path.exists(ip) else {"sets": {}}    # (re-read each time: several packers may run at once, one for each kind)
        index["sets"][n] = m
        os.makedirs(OUT, exist_ok=True)
        json.dump(index, open(ip, "w"), indent=1, sort_keys=True)
