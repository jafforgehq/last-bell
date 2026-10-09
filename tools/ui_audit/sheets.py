#!/usr/bin/env python3
"""Annotated sheets of the HUD audit: a snapshot as it is, as the audit sees it, and what it would look like with the MINIMAL HUD of the stage table.

    python3 tools/ui_audit/sheets.py SNAPSHOT_DIR OUT.png [--minimal]

Three panels, left to right: the screen as played; the masks (red: the HUD, yellow: the guide, banner and alerts, blue: the marks of the world, a thin white frame the centre zone) with a
box round each awake dead one (green: clear, orange: touched, red: hidden over half, with the share and what hides it); and, with --minimal, the same frame made of the world alone with
only the parts the stage table keeps for that moment put back (some of them cut down to their first line, as the table says "collapsed").
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze  # noqa: E402

# What the minimal HUD keeps at a moment of the first twenty minutes: (part, crop) with the crop (x0, y0, x1, y1) as shares of the part's own box, None for the whole part.
OBJ = ("objective", (0, 0, 1, 0.5))        # the objective cut down to its title line
WPN = ("weapon", (0, 0, 1, 0.55))           # the weapon panel cut down to the name and the rounds
CLK = ("clock", (0, 0, 1, 0.5))             # the clock cut down to the day and the hour
PILL = ("alerts", (0, 0, 1, 0.14))          # the alerts and the radio call cut down to one line
MINIMAL = {
    "a_hold": [OBJ, WPN, ("lesson_cues", None), ("edge_arrows", None)],
    "a_arrive": [OBJ, WPN, ("lesson_cues", None), ("edge_arrows", None)],
    "b_opening": [OBJ, WPN, ("lesson_cues", None)],
    "c_clearing": [OBJ, WPN, ("minimap", None), ("room_chips", None), ("lesson_cues", None)],
    "d_day": [("stores", None), OBJ, ("crew_cards", None), CLK, WPN, ("toolbar", None), ("minimap", None), PILL],
    "d_dusk": [("stores", None), OBJ, ("crew_cards", None), ("clock", None), WPN, ("minimap", None), PILL],
    "e_night": [("crew_cards", (0, 0, 1, 0.75)), CLK, WPN, ("minimap", None), PILL],
    "e_storm": [("crew_cards", (0, 0, 1, 0.75)), CLK, WPN, ("minimap", None), PILL],
    "f_dawn": [("stores", None), ("crew_cards", None), CLK, WPN, ("minimap", None), ("morning_card", (0, 0, 0.72, 0.5))],    # (the card as a corner card: its title, the night's four rows and the button, 360 px wide)
    "g_build": [("stores", None), ("crew_cards", None), CLK, WPN, ("radio_panel", None), ("lesson_cues", None)],    # (the page's own NEXT card says what the objective says)
    "g_radio": [("stores", None), ("crew_cards", None), CLK, WPN, ("radio_panel", None)],
}


def key_of(label):
    for k in sorted(MINIMAL, key=len, reverse=True):
        if label.startswith(k):
            return k
    return None


def minimal(d, meta):
    full = analyze.load(d, "full")
    world = analyze.load(d, "world")
    h, w = full.shape[:2]
    k = key_of(str(meta.get("label", "")) or os.path.basename(d))
    if k is None:
        k = key_of(os.path.basename(d))
    out = world.copy()
    keep = MINIMAL.get(k, [])
    kept = np.zeros((h, w), dtype=bool)
    for name, crop in keep:
        img = analyze.load(d, "e_" + name)
        if img is None:
            continue
        m = analyze.close(analyze.diff(full, img, analyze.PANEL_T), analyze.PANEL_R)
        if not m.any():
            continue
        if crop is not None:
            ys, xs = np.nonzero(m)
            x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
            cx0, cx1 = int(x0 + crop[0] * (x1 - x0)), int(x0 + crop[2] * (x1 - x0))
            cy0, cy1 = int(y0 + crop[1] * (y1 - y0)), int(y0 + crop[3] * (y1 - y0))
            sel = np.zeros_like(m)
            sel[cy0:cy1, cx0:cx1] = True
            m = m & sel
        out[m] = full[m]
        kept |= m
    return out.astype(np.uint8), keep, kept


def minimal_stats(d):
    """What the minimal HUD of the stage table would cover in this snapshot: the kept parts (cut down as the table says) and the marks of the world as they are."""
    meta = json.load(open(os.path.join(d, "meta.json")))
    _, keep, kept = minimal(d, meta)
    nohud = analyze.load(d, "nohud")
    world = analyze.load(d, "world")
    labels = analyze.close(analyze.diff(nohud, world, analyze.DIFF_T), analyze.CLOSE_R)
    union = kept | labels
    h, w = union.shape
    z = analyze.zone((h, w))
    tile = float(meta.get("tile_px") or 32.0)
    av = meta["avatar"]["px"]
    dead_cov = []
    for dd in meta.get("dead", []):
        bx, by, bw, bh = [int(round(v)) for v in dd["box"]]
        x0, y0, x1, y1 = max(bx, 0), max(by, 0), min(bx + bw, w), min(by + bh, h)
        if x1 > x0 and y1 > y0 and (x1 - x0) * (y1 - y0) >= 0.5 * bw * bh:
            dead_cov.append(float(union[y0:y1, x0:x1].mean()))
    return {"ui": round(analyze.pct(union), 2), "centre": round(analyze.pct_c(union, z), 2), "kept_pct": round(analyze.pct(kept), 2), "blind": analyze.blind(union, tile, av),
            "dead_in_view": len(dead_cov), "dead_hidden": sum(1 for c in dead_cov if c > analyze.HIDDEN_AT), "parts": [n for n, _ in keep]}


def main():
    d, outp = sys.argv[1], sys.argv[2]
    meta = json.load(open(os.path.join(d, "meta.json")))
    ann_p = os.path.join(d, "annotated.png")
    if not os.path.exists(ann_p):
        analyze.analyze(d)
    res = json.load(open(os.path.join(d, "result.json")))
    full = Image.open(os.path.join(d, "full.png")).convert("RGB")
    ann = Image.open(ann_p).convert("RGB")
    w, h = full.size
    f = analyze.font(max(12, w // 80))
    if "--minimal" not in sys.argv:
        sheet = Image.new("RGB", (w * 2, h))
        sheet.paste(full, (0, 0))
        sheet.paste(ann, (w, 0))
        sheet.save(outp)
        print("sheet", outp, sheet.size)
        return
    # two rows: as played | the audit's masks, then the minimal HUD | the numbers
    img, keep, _kept = minimal(d, meta)
    pm = Image.fromarray(img)
    dr = ImageDraw.Draw(pm)
    label = "MINIMAL HUD (the stage table): " + ", ".join(n for n, _ in keep)
    dr.rectangle([0, h - f.size - 8, w, h], fill=(0, 0, 0))
    dr.text((6, h - f.size - 5), label, fill=(255, 255, 255), font=f)
    ms = minimal_stats(d)
    txt = Image.new("RGB", (w, h), (18, 22, 20))
    td = ImageDraw.Draw(txt)
    lines = [
        "%s   %dx%d   hour %.1f" % (res["label"], w, h, float(res.get("hour") or 0)),
        "",
        "                                  now      minimal HUD",
        "UI, %% of the screen        %6.1f    %6.1f" % (res["masks"]["union"]["pct"], ms["ui"]),
        "UI, %% of the centre zone    %6.1f    %6.1f" % (res["masks"]["union"]["centre"], ms["centre"]),
        "blind near her (14 tiles) %% %6.1f    %6.1f" % (res["blind"]["union"]["near"], ms["blind"]["near"]),
        "dead in view                %6d    %6d" % (res["dead_in_view"], ms["dead_in_view"]),
        "dead hidden over half       %6d    %6d" % (res["dead_hidden"], ms["dead_hidden"]),
        "",
        "now: HUD %.1f%%, guide/banner/alerts %.1f%%, marks of the world %.1f%%" % (res["masks"]["hud"]["pct"], res["masks"]["tut"]["pct"], res["masks"]["labels"]["pct"]),
        "red: the HUD   yellow: the guide, banner, alerts, tips   blue: names, prompts, marks",
        "white frame: the centre zone (middle half of the width and height)",
        "box round a dead one: green clear, orange touched, red hidden over half",
        "",
        "biggest parts now:",
    ]
    for e in res["elements"][:8]:
        lines.append("  %-24s %5.2f%%  centre %5.2f%%" % (e["name"], e["pct"], e["centre"]))
    y = 18
    for ln in lines:
        td.text((18, y), ln, fill=(235, 235, 220), font=f)
        y += f.size + 6
    sheet = Image.new("RGB", (w * 2, h * 2))
    sheet.paste(full, (0, 0))
    sheet.paste(ann, (w, 0))
    sheet.paste(pm, (0, h))
    sheet.paste(txt, (w, h))
    sheet.save(outp)
    print("sheet", outp, sheet.size)


if __name__ == "__main__":
    main()
