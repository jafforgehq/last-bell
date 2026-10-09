#!/usr/bin/env python3
"""Check the snapshots of an audit run against the clutter budget (tools/ui_audit/budget.json).

    python3 tools/ui_audit/check_budget.py OUTDIR [--all]     # prints one line for each snapshot and metric that is over, the verdict, and exits 1 when something is

Each snapshot (a result.json of analyze.py) is held to the group its label begins with. The metrics: `persistent` the boards that are always there (stores, objective, crew, clock, weapon,
toolbar, minimap, arrows) as a share of the screen; `ui` everything (the HUD, the guide, banner, alerts, tips and the marks of the world); `centre` the same over the middle half of the
width and height; `blind_near` the share of the places within 14 tiles of the avatar where a dead one would be more than half hidden; `hidden` the awake dead in view hidden over half;
`covered_dead` the most any dead one in view is covered (percent). The shares are scaled to the window (see budget.json).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import analyze  # noqa: E402
import sheets  # noqa: E402


def factor(size, ref):
    w, h = size
    scale = max(1.0, min(w / 1600.0, h / 900.0))
    return (ref[0] * ref[1]) / float(w * h) * scale * scale


def group_of(label, groups):
    for name, g in groups.items():
        for m in g["match"]:
            if label.startswith(m):
                return name
    return None


def main():
    root = sys.argv[1]
    show_all = "--all" in sys.argv
    b = json.load(open(os.path.join(HERE, "budget.json")))
    rows = []
    over = 0
    checked = 0
    for d in analyze.find_all(root):
        p = os.path.join(d, "result.json")
        if not os.path.exists(p):
            continue
        r = json.load(open(p))
        label = os.path.basename(d)
        g = group_of(label, b["groups"])
        if g is None:
            continue
        lim = b["groups"][g]
        f = factor(r["size"], b["ref"])
        got = {
            "persistent": r["kinds"]["persistent"]["pct"], "ui": r["masks"]["union"]["pct"], "centre": r["masks"]["union"]["centre"], "blind_near": r["blind"]["union"]["near"],
            "hidden": r["dead_hidden"], "covered_dead": max([x["covered"] * 100 for x in r["dead"]] or [0.0]),
        }
        size = "%dx%d" % tuple(r["size"])
        keys = ["persistent", "ui", "centre", "blind_near", "hidden", "covered_dead"]
        if "--minimal" in sys.argv:
            # the same checks on the minimal HUD of the stage table (sheets.py MINIMAL): the budget must be one that the table itself meets
            if sheets.key_of(label) is None:
                continue
            ms = sheets.minimal_stats(d)
            got.update({"ui": ms["ui"], "centre": ms["centre"], "blind_near": ms["blind"]["near"], "hidden": ms["dead_hidden"]})
            keys = ["ui", "centre", "blind_near", "hidden"]
        for k in keys:
            allowed = lim[k] * (f if k in ("persistent", "ui", "centre", "blind_near") else 1.0)
            checked += 1
            bad = got[k] > allowed + 1e-9
            if bad:
                over += 1
            if bad or show_all:
                rows.append("%-4s %-9s %-26s %-12s %7.2f  allowed %6.2f  (group %s)" % ("OVER" if bad else "ok", size, label + "/s" + os.path.relpath(d, root).split(os.sep)[1].lstrip("s"), k, got[k], allowed, g))
        # an on-demand window: its width, its height and its area against `window_max_share`
        if g == "window":
            wm = b["window_max_share"]
            for e in r["elements"]:
                if e["name"] != "radio_panel":
                    continue
                bw, bh = e["bbox"][2] / float(r["size"][0]), e["bbox"][3] / float(r["size"][1])
                for k, got_v, allowed_v in (("window_width", bw, wm["width"]), ("window_height", bh, wm["height"]), ("window_area", e["pct"] / 100.0, wm["area"])):
                    checked += 1
                    bad = got_v > allowed_v + 1e-9
                    if bad:
                        over += 1
                    if bad or show_all:
                        rows.append("%-4s %-9s %-26s %-12s %7.3f  allowed %6.3f  (group window)" % ("OVER" if bad else "ok", size, label + "/s" + os.path.relpath(d, root).split(os.sep)[1].lstrip("s"), k, got_v, allowed_v))
    print("\n".join(rows))
    print("\nclutter budget: %d of %d checks over (%s)" % (over, checked, "FAIL" if over else "PASS"))
    sys.exit(1 if over else 0)


if __name__ == "__main__":
    main()
