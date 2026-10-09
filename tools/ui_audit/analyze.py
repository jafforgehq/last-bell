#!/usr/bin/env python3
"""Measure what the UI covers in the snapshots of tools/ui_audit/driver.gd, and what it hides.

    python3 tools/ui_audit/analyze.py SNAPSHOT_DIR [...]      # one snapshot (a directory with full.png, flags.png, ... meta.json): writes result.json and sheet.png
    python3 tools/ui_audit/analyze.py --all OUTDIR            # every snapshot under OUTDIR/<size>/s<seed>/<label>/

THE MASKS (a pixel is "changed" when its three channels together differ by more than PANEL_T (the HUD) or DIFF_T (the marks of the world); the game is frozen while a snapshot is
drawn, so the noise floor is zero):
  tut     full  vs  flags   what `--hide-lesson --no-banner --no-alerts` takes away: the guide's card and cues, the banner, the alerts and the radio call, the tips
  hud     flags vs  nohud   what `--nohud` takes away that the flags above leave: stores, objective, crew, clock, weapon, toolbar, minimap, arrows, the legend, toasts, pages...
  labels  nohud vs  world   what stays on the screen with the HUD off and is not the world: the names, prompts, barks and marks of the overlay layer, the loot shimmer
  union   the three together
Each mask is CLOSED by CLOSE_R pixels (a gap between two letters is not a hole to see through), then measured as a share of the screen and of the CENTRE ZONE (the middle half of the
width and of the height: a quarter of the screen, round the avatar). Every named part of the UI (e_<part>.png: the same frame without that part) has a mask of its own the same way.
THE DEAD: each awake dead one of meta.json has a box (one tile wide, one and a half tall, at its feet); the share of the box (the part of it that is on the screen) under the union is its
`covered`, and under each part its `by`. HIDDEN is covered over 50 percent. Dead with less than half their box on the screen are not counted as in view.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# The boards of the HUD are solid (a pixel of a board on a dark night street can differ from the street by only a few levels: a low threshold, and a wide closing that fills the words'
# gaps and the board's dark spots); the marks of the world include faint tints (the avatar's rally disc, the veil of a room) that are not ink: a higher threshold, a narrow closing.
DIFF_T = 20          # the marks of the world
PANEL_T = 8          # the HUD, the guide, the banner, the alerts
FAINT_T = 6
CLOSE_R = 2          # the marks of the world
PANEL_R = 4          # the HUD
PANEL_GROUPS = ("hud", "tutorial", "banner", "alerts")
HIDDEN_AT = 0.5
# a part drawn at or under this opacity (a board the game has made see-through over a dead one, a card half faded) does not hide what is under it
GHOST_A = 0.4
KINDS = ["persistent", "teaching", "transient", "world"]


def load(d, name):
    p = os.path.join(d, name + ".png")
    if not os.path.exists(p):
        return None
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.int16)


def diff(a, b, t=DIFF_T):
    """Pixels whose three channels together differ by more than `t` (a faint tint, as the avatar's rally disc, is under DIFF_T)."""
    return np.abs(a - b).sum(axis=2) > t


def dilate(m, r):
    out = m.copy()
    for dx in range(1, r + 1):
        out[:, dx:] |= m[:, :-dx]
        out[:, :-dx] |= m[:, dx:]
    m2 = out.copy()
    for dy in range(1, r + 1):
        out[dy:, :] |= m2[:-dy, :]
        out[:-dy, :] |= m2[dy:, :]
    return out


def close(m, r=CLOSE_R):
    return _erode(dilate(m, r), r)


def _erode(m, r):
    # erosion with the border treated as covered, so that a panel at the window's edge keeps its edge
    padded = np.pad(m, r, constant_values=True)
    out = padded.copy()
    h, w = m.shape
    acc = np.ones_like(m)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            acc &= padded[r + dy:r + dy + h, r + dx:r + dx + w]
    return acc


def zone(shape):
    h, w = shape
    z = np.zeros(shape, dtype=bool)
    z[h // 4: (3 * h) // 4, w // 4: (3 * w) // 4] = True
    return z


def pct(m):
    return float(m.mean()) * 100.0


def pct_c(m, z):
    return float((m & z).sum()) / float(z.sum()) * 100.0


NEAR_TILES = 14.0
GRID = 4


def blind(mask, tile_px, avatar_px):
    """Where a dead one could stand and be hidden. A sprite box (one tile wide, one and a half tall, the feet 0.65 tile under its point) is put at every GRID-th pixel of the
    screen; the share of positions (those with at least half the box on the screen) where the mask covers over half the box is the BLIND share of the screen, and the same over the
    positions within NEAR_TILES tiles of the avatar (the dead of the threat rule) is the BLIND share NEAR her."""
    h, w = mask.shape
    s = np.zeros((h + 1, w + 1), dtype=np.int64)
    s[1:, 1:] = mask.cumsum(axis=0).cumsum(axis=1)
    t = tile_px
    xs = np.arange(0, w, GRID)
    ys = np.arange(0, h, GRID)
    cx, cy = np.meshgrid(xs, ys)
    x0 = cx - 0.5 * t
    y0 = cy - 0.85 * t
    x1 = x0 + t
    y1 = y0 + 1.5 * t
    full_area = (x1 - x0) * (y1 - y0)
    ix0 = np.clip(np.round(x0), 0, w).astype(int)
    ix1 = np.clip(np.round(x1), 0, w).astype(int)
    iy0 = np.clip(np.round(y0), 0, h).astype(int)
    iy1 = np.clip(np.round(y1), 0, h).astype(int)
    area = np.maximum((ix1 - ix0) * (iy1 - iy0), 1)
    cov = (s[iy1, ix1] - s[iy0, ix1] - s[iy1, ix0] + s[iy0, ix0]) / area
    ok = area / full_area >= 0.5
    near = ok & ((cx - avatar_px[0]) ** 2 + (cy - avatar_px[1]) ** 2 <= (NEAR_TILES * t) ** 2)
    hid = cov > HIDDEN_AT
    return {"all": round(float((hid & ok).sum()) / max(int(ok.sum()), 1) * 100, 2), "near": round(float((hid & near).sum()) / max(int(near.sum()), 1) * 100, 2)}


def fill_rects(e, h, w):
    """The boxes of the part's nodes (pixels) filled in a mask; nothing for a part that only draws over the whole window; the minimap is the ellipse in its box."""
    m = np.zeros((h, w), dtype=bool)
    for x, y, rw, rh in e.get("rects", []):
        if rw >= w - 2 and rh >= h - 2:
            continue
        if rw < 2 or rh < 2:
            continue
        x0, y0, x1, y1 = max(int(round(x)), 0), max(int(round(y)), 0), min(int(round(x + rw)), w), min(int(round(y + rh)), h)
        if x1 <= x0 or y1 <= y0:
            continue
        if e["name"] == "minimap":
            yy, xx = np.mgrid[y0:y1, x0:x1]
            cx, cy = x + rw / 2.0, y + rh / 2.0
            m[y0:y1, x0:x1] |= ((xx - cx) / (rw / 2.0)) ** 2 + ((yy - cy) / (rh / 2.0)) ** 2 <= 1.0
        else:
            m[y0:y1, x0:x1] = True
    return m


def analyze(d):
    meta = json.load(open(os.path.join(d, "meta.json")))
    full = load(d, "full")
    h, w = full.shape[:2]
    z = zone((h, w))
    flags = load(d, "flags")
    nohud = load(d, "nohud")
    world = load(d, "world")
    again = load(d, "again")
    noise = int(diff(full, again).sum()) if again is not None else -1
    raw = {"tut": diff(full, flags, PANEL_T), "hud": diff(flags, nohud, PANEL_T), "labels": diff(nohud, world, DIFF_T)}
    # `--hide-lesson` puts the legend of the keys away as well (checked against the real flags: verify_flags.py); the first snapshots made it a part of the HUD, so move it here
    leg = load(d, "e_key_legend")
    if leg is not None:
        lm = diff(full, leg, PANEL_T)
        raw["tut"] = raw["tut"] | lm
        raw["hud"] = raw["hud"] & ~lm
    masks = {k: close(v, CLOSE_R if k == "labels" else PANEL_R) for k, v in raw.items()}
    # a board whose pixels hardly differ from a dark night street is still a board: the box of its node (meta.json `elements[].rects`) is filled in too (the minimap as its round window)
    fills = {e["name"]: fill_rects(e, h, w) for e in meta.get("elements", [])}
    for e in meta.get("elements", []):
        f = fills[e["name"]]
        if f.any():
            if e["group"] in ("tutorial", "banner", "alerts"):
                masks["tut"] = masks["tut"] | f
            elif e["group"] == "hud":
                masks["hud"] = masks["hud"] | f
    masks["union"] = masks["tut"] | masks["hud"] | masks["labels"]
    res = {"label": meta.get("label"), "dir": d, "size": [w, h], "hour": meta.get("hour"), "day": meta.get("day"), "sim_t": meta.get("sim_t"), "noise_px": noise,
           "tile_px": meta.get("tile_px"), "avatar_px": meta["avatar"]["px"], "stage": meta.get("stage"), "banner_alpha": meta.get("banner_alpha"), "speed": meta.get("speed")}
    res["masks"] = {k: {"pct": round(pct(v), 2), "centre": round(pct_c(v, z), 2), "raw_pct": round(pct(raw[k]), 2) if k in raw else None} for k, v in masks.items()}
    # tints too faint to count (the avatar's rally disc, the veil of a room): reported, not counted
    faint = diff(full, world, FAINT_T) & ~masks["union"] & ~dilate(masks["union"], 2)
    asplayed = load(d, "asplayed")
    res["fx"] = {"pct": round(pct(diff(asplayed, full, PANEL_T)), 2) if asplayed is not None else None}
    res["faint"] = {"pct": round(pct(faint), 2), "centre": round(pct_c(faint, z), 2)}
    # the named parts
    parts = {}
    elems = {}
    for e in meta.get("elements", []):
        img = load(d, "e_" + e["name"])
        if img is None:
            continue
        panel = e["group"] in PANEL_GROUPS
        m = close(diff(full, img, PANEL_T if panel else DIFF_T), PANEL_R if panel else CLOSE_R)
        rects = e.get("rects", [])
        boxes = [rc for rc in rects if not (rc[2] >= w - 2 and rc[3] >= h - 2)]
        if rects and boxes and len(boxes) == len(rects):
            # a part made of boards: what it covers is within a few pixels of its own boxes (a few pixels elsewhere change with any switch: the minimap's hover, an animation)
            fill = fills.get(e["name"], np.zeros_like(m))
            if not fill.any():
                continue
            m = (m | fill) & dilate(fill, 8) if panel else m
        elif panel:
            m = m | fills.get(e["name"], np.zeros_like(m))
        if int(m.sum()) < 200:
            continue    # (a few pixels that change with any switch, as the minimap's hover: not a part of the picture)
        parts[e["name"]] = m
    # the HUD's town layer (the objective's arrow and the ring of a session in hand) is also the parent of the key legend, the lesson card and the radio pill: what they cover is theirs
    if "objective_arrow_ring" in parts:
        nested = np.zeros((h, w), dtype=bool)
        for n in ("key_legend", "lesson_card", "radio_pill", "objective"):
            if n in parts:
                nested |= dilate(parts[n], 1)
        parts["objective_arrow_ring"] = parts["objective_arrow_ring"] & ~nested
        if not parts["objective_arrow_ring"].any():
            del parts["objective_arrow_ring"]
    for e in meta.get("elements", []):
        m = parts.get(e["name"])
        if m is None:
            continue
        ys, xs = np.nonzero(m)
        elems[e["name"]] = {"name": e["name"], "kind": e["kind"], "group": e["group"], "pct": round(pct(m), 2), "centre": round(pct_c(m, z), 2), "px": int(m.sum()),
                            "bbox": [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]}
    tile = float(meta.get("tile_px") or 32.0)
    avpx = meta["avatar"]["px"]
    for n, e in elems.items():
        e["blind"] = blind(parts[n], tile, avpx)
    res["elements"] = sorted(elems.values(), key=lambda e: -e["px"])
    kinds = {}
    kind_masks = {}
    for k in KINDS:
        m = np.zeros((h, w), dtype=bool)
        for n, e in elems.items():
            if e["kind"] == k:
                m |= parts[n]
        kind_masks[k] = m
        kinds[k] = {"pct": round(pct(m), 2), "centre": round(pct_c(m, z), 2), "blind": blind(m, tile, avpx)}
    res["kinds"] = kinds
    # what HIDES: the union less the parts that are drawn see-through
    cover = masks["union"].copy()
    ghosted = [e["name"] for e in meta.get("elements", []) if float(e.get("alpha", 1.0)) <= GHOST_A and e["name"] in parts]
    for n in ghosted:
        cover &= ~parts[n]
    res["ghosted"] = ghosted
    res["blind"] = {k: blind(v if k != "union" else cover, tile, avpx) for k, v in masks.items()}
    # what the named parts leave unexplained (the union minus the parts)
    allp = np.zeros((h, w), dtype=bool)
    for m in parts.values():
        allp |= m
    res["unexplained_pct"] = round(pct(masks["union"] & ~allp), 2)
    # the dead
    dead = []
    for dd in meta.get("dead", []):
        bx, by, bw, bh = dd["box"]
        x0, y0, x1, y1 = int(round(bx)), int(round(by)), int(round(bx + bw)), int(round(by + bh))
        cx0, cy0, cx1, cy1 = max(x0, 0), max(y0, 0), min(x1, w), min(y1, h)
        full_area = max((x1 - x0) * (y1 - y0), 1)
        if cx1 <= cx0 or cy1 <= cy0:
            continue
        on_frac = (cx1 - cx0) * (cy1 - cy0) / full_area
        if on_frac < 0.5:
            continue
        sub = cover[cy0:cy1, cx0:cx1]
        cov = float(sub.mean())
        by_part = {}
        for n, m in parts.items():
            if n in ghosted:
                continue
            f = float(m[cy0:cy1, cx0:cx1].mean())
            if f > 0.0:
                by_part[n] = round(f, 3)
        cats = {k: round(float(masks[k][cy0:cy1, cx0:cx1].mean()), 3) for k in ("hud", "tut", "labels")}
        top = sorted(by_part.items(), key=lambda kv: -kv[1])[:3]
        # the nearest part that does not touch it, and how many pixels away (within 150 px)
        near = None
        R = 150
        wx0, wy0, wx1, wy1 = max(cx0 - R, 0), max(cy0 - R, 0), min(cx1 + R, w), min(cy1 + R, h)
        for n, m in parts.items():
            win = m[wy0:wy1, wx0:wx1]
            if not win.any():
                continue
            ys, xs = np.nonzero(win)
            xs = xs + wx0
            ys = ys + wy0
            dx = np.maximum(np.maximum(cx0 - xs, xs - (cx1 - 1)), 0)
            dy = np.maximum(np.maximum(cy0 - ys, ys - (cy1 - 1)), 0)
            dist = float(np.sqrt(dx * dx + dy * dy).min())
            if near is None or dist < near[1]:
                near = (n, round(dist, 1))
        dead.append({"kind": dd["kind"], "state": dd["state"], "dist": dd["dist"], "px": dd["px"], "box": [x0, y0, x1 - x0, y1 - y0], "on_screen_frac": round(on_frac, 2),
                     "covered": round(cov, 3), "hidden": cov > HIDDEN_AT, "by": cats, "top": top, "nearest": near, "in_centre": bool(z[int(dd["px"][1]) if 0 <= int(dd["px"][1]) < h else 0, int(dd["px"][0]) if 0 <= int(dd["px"][0]) < w else 0])})
    res["dead"] = dead
    res["dead_in_view"] = len(dead)
    res["dead_hidden"] = sum(1 for x in dead if x["hidden"])
    res["dead_covered_30"] = sum(1 for x in dead if x["covered"] > 0.3)
    res["dead_covered_any"] = sum(1 for x in dead if x["covered"] > 0.0)
    json.dump(res, open(os.path.join(d, "result.json"), "w"), indent=1)
    sheet(d, full, masks, parts, res, meta)
    return res


# ------------------------------------------------------------------------------ the sheet --

COL = {"hud": (255, 70, 70), "tut": (255, 215, 0), "labels": (60, 170, 255)}


def font(size):
    for p in ["/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/System/Library/Fonts/Helvetica.ttc", "/Library/Fonts/Arial.ttf"]:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()


def paint(base, m, c, a):
    for i in range(3):
        base[..., i] = np.where(m, base[..., i] * (1 - a) + c[i] * a, base[..., i])


def sheet(d, full, masks, parts, res, meta):
    h, w = full.shape[:2]
    base = (full.astype(np.float32) * 0.55)
    # labels first, then the HUD, then the tutorial on top (a cue over a card is yellow)
    paint(base, masks["labels"], COL["labels"], 0.55)
    paint(base, masks["hud"], COL["hud"], 0.5)
    paint(base, masks["tut"], COL["tut"], 0.55)
    ann = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
    dr = ImageDraw.Draw(ann)
    f = font(max(11, w // 100))
    for x in res["dead"]:
        bx, by, bw, bh = x["box"]
        col = (255, 40, 40) if x["hidden"] else ((255, 150, 0) if x["covered"] > 0.1 else (60, 255, 90))
        dr.rectangle([bx, by, bx + bw, by + bh], outline=col, width=3)
        label = "%d%%" % round(x["covered"] * 100)
        if x["hidden"] and x["top"]:
            label += " " + x["top"][0][0]
        tw = dr.textlength(label, font=f)
        dr.rectangle([bx, by - f.size - 4, bx + tw + 6, by], fill=(0, 0, 0))
        dr.text((bx + 3, by - f.size - 3), label, fill=col, font=f)
    t = "%s  %dx%d   UI %.1f%% of the screen, %.1f%% of the centre   HUD %.1f  guide/banner/alerts %.1f  labels %.1f   dead in view %d, hidden %d" % (
        res["label"], w, h, res["masks"]["union"]["pct"], res["masks"]["union"]["centre"], res["masks"]["hud"]["pct"], res["masks"]["tut"]["pct"], res["masks"]["labels"]["pct"],
        res["dead_in_view"], res["dead_hidden"])
    dr.rectangle([0, h - f.size - 8, w, h], fill=(0, 0, 0))
    dr.text((6, h - f.size - 5), t, fill=(255, 255, 255), font=f)
    # the centre zone
    dr.rectangle([w // 4, h // 4, 3 * w // 4, 3 * h // 4], outline=(255, 255, 255), width=1)
    out = Image.new("RGB", (w * 2, h))
    out.paste(Image.fromarray(full.astype(np.uint8)), (0, 0))
    out.paste(ann, (w, 0))
    out.save(os.path.join(d, "sheet.png"))
    ann.save(os.path.join(d, "annotated.png"))


def find_all(root):
    out = []
    for dp, dn, fn in os.walk(root):
        if "meta.json" in fn and "full.png" in fn:
            out.append(dp)
    return sorted(out)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--all":
        dirs = find_all(args[1])
    else:
        dirs = args
    for dd in dirs:
        r = analyze(dd)
        print("%-60s UI %5.1f%% centre %5.1f%%  (hud %.1f tut %.1f labels %.1f)  dead in view %d hidden %d" % (
            os.path.relpath(dd, os.path.dirname(dd) if len(dirs) == 1 else args[1]), r["masks"]["union"]["pct"], r["masks"]["union"]["centre"], r["masks"]["hud"]["pct"],
            r["masks"]["tut"]["pct"], r["masks"]["labels"]["pct"], r["dead_in_view"], r["dead_hidden"]))
