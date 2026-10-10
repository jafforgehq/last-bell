#!/usr/bin/env python3
"""The before and after of the HUD (PH8) as one table: for each window size and each state, what the persistent boards, the whole UI and the centre zone cover, and the dead that were hidden.

    python3 tools/ui_audit/compare.py BEFORE_DIR AFTER_DIR [--sizes 1280x720,1920x1080,...] [--lines]

Both directories are what tools/ui_audit/run_audit.sh (or run_scenes.py and analyze.py --all) writes. A state with more than one snapshot (the night's three looks, the opening's two) is the worst of them
(the largest share, the most dead hidden), because the budget is held to each. `--lines` prints the budget lines of the AFTER directory as `check_budget.py` counts them, by size.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import analyze  # noqa: E402
import check_budget  # noqa: E402

STATES = [("a_hold", "arrival, held"), ("a_arrive", "arrival, 1 s after the key"), ("b_opening_0", "opening: walker out"), ("b_opening_3", "opening: +3 s"), ("c_clearing", "first house, dead near"),
          ("d_day", "claimed, day"), ("d_dusk", "first dusk"), ("e_night", "first night"), ("f_dawn", "morning card"), ("g_build", "Build page"), ("g_radio", "radio panel")]


def load(root):
    """{size: {state: [result, ...]}}"""
    out = {}
    for d in analyze.find_all(root):
        p = os.path.join(d, "result.json")
        if not os.path.exists(p):
            continue
        r = json.load(open(p))
        parts = os.path.relpath(d, root).split(os.sep)
        size, label = parts[0], parts[-1]
        state = "e_night" if label.startswith("e_night_") else label
        out.setdefault(size, {}).setdefault(state, []).append(r)
    return out


def worst(rs, key):
    vals = []
    for r in rs:
        if key == "persistent":
            vals.append(r["kinds"]["persistent"]["pct"])
        elif key == "ui":
            vals.append(r["masks"]["union"]["pct"])
        elif key == "centre":
            vals.append(r["masks"]["union"]["centre"])
        elif key == "hidden":
            vals.append(r["dead_hidden"])
        elif key == "covered":
            vals.append(max([x["covered"] * 100.0 for x in r["dead"]] or [0.0]))
    return max(vals) if vals else None


def cell(b, a, fmt="%.1f"):
    if b is None and a is None:
        return "-"
    return "%s -> %s" % (fmt % b if b is not None else "-", fmt % a if a is not None else "-")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    before, after = load(args[0]), load(args[1])
    sizes = ["1280x720"]
    lines = "--lines" in sys.argv
    for a in sys.argv[1:]:
        if a.startswith("--sizes="):
            sizes = a.split("=", 1)[1].split(",")
    if "--sizes" in sys.argv:
        sizes = sys.argv[sys.argv.index("--sizes") + 1].split(",")
    b = json.load(open(os.path.join(HERE, "budget.json")))
    print("| Window | State | Persistent % | UI % | Centre % | Hidden over half | Most a dead one is covered % |")
    print("|---|---|---|---|---|---|---|")
    for size in sizes:
        for st, name in STATES:
            rb = before.get(size, {}).get(st)
            ra = after.get(size, {}).get(st)
            if rb is None and ra is None:
                continue
            row = [size, name]
            for key, fmt in (("persistent", "%.1f"), ("ui", "%.1f"), ("centre", "%.1f"), ("hidden", "%d"), ("covered", "%.0f")):
                row.append(cell(worst(rb, key) if rb else None, worst(ra, key) if ra else None, fmt))
            print("| " + " | ".join(row) + " |")
    if lines:
        print()
        for size in sizes:
            over = checked = 0
            for st, rs in after.get(size, {}).items():
                for r in rs:
                    label = os.path.basename(r["dir"])
                    g = check_budget.group_of(label, b["groups"])
                    if g is None:
                        continue
                    lim = b["groups"][g]
                    f = check_budget.factor(r["size"], b["ref"])
                    got = {"persistent": r["kinds"]["persistent"]["pct"], "ui": r["masks"]["union"]["pct"], "centre": r["masks"]["union"]["centre"], "blind_near": r["blind"]["union"]["near"],
                           "hidden": r["dead_hidden"], "covered_dead": max([x["covered"] * 100 for x in r["dead"]] or [0.0])}
                    for k in ("persistent", "ui", "centre", "blind_near", "hidden", "covered_dead"):
                        allowed = lim[k] * (f if k in ("persistent", "ui", "centre", "blind_near") else 1.0)
                        checked += 1
                        over += 1 if got[k] > allowed + 1e-9 else 0
            print("%s: %d of %d budget checks over" % (size, over, checked))


if __name__ == "__main__":
    main()
