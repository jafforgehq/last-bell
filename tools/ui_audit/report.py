#!/usr/bin/env python3
"""Tables of the HUD audit from the result.json files of tools/ui_audit/analyze.py.

    python3 tools/ui_audit/report.py OUTDIR [--budget]        # markdown to stdout, OUTDIR/summary.md and summary.json

One row for each state and window size: how much of the screen the UI covers (the union of the HUD, the guide with the banner and the alerts, and the marks of the world), how much of the
centre zone, the share of each, the share the persistent boards alone cover, the BLIND share near the avatar (where a dead one within 14 tiles of her would be more than half hidden),
and the dead in view and how many were hidden over half. A state with more than one seed or snapshot is the mean of them (the dead are summed).
"""
import json
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze  # noqa: E402

ORDER = ["a_hold", "a_arrive", "b_opening_0", "b_opening_3", "c_clearing", "d_day", "d_dusk", "e_night", "e_storm", "f_dawn", "g_build", "g_radio",
         "l_walk", "l_shoot", "l_reload", "l_find", "l_claim", "l_build", "l_ask", "l_rehearsal"]
TITLES = {
    "a_hold": "(a) arrival, held, before the first key", "a_arrive": "(a) arrival, the first second after the key", "b_opening_0": "(b) opening: the walker steps out",
    "b_opening_3": "(b) opening: 3 s later", "c_clearing": "(c) in the house, dead near", "d_day": "(d) the claimed house by day, crew at work", "d_dusk": "(d) the first dusk, the bell",
    "e_night": "(e) first attack night, clear", "e_storm": "(e) first attack night, storm", "f_dawn": "(f) the morning card", "g_build": "(g) the Build page open", "g_radio": "(g) the radio panel open",
    "l_walk": "lesson: walk", "l_shoot": "lesson: shoot", "l_reload": "lesson: reload", "l_find": "lesson: find a house", "l_claim": "lesson: claim", "l_build": "lesson: build",
    "l_ask": "lesson: ask", "l_rehearsal": "lesson: rehearsal card"}


def state_of(label):
    m = re.match(r"^(e_night|e_storm)_\d+$", label)
    return m.group(1) if m else label


def collect(root):
    rows = []
    for d in analyze.find_all(root):
        p = os.path.join(d, "result.json")
        if not os.path.exists(p):
            continue
        r = json.load(open(p))
        parts = os.path.relpath(d, root).split(os.sep)
        r["_size"] = parts[0]
        r["_seed"] = int(parts[1].lstrip("s")) if len(parts) > 1 and parts[1].startswith("s") else 1
        r["_state"] = state_of(parts[-1])
        r["_label"] = parts[-1]
        r["_dir"] = d
        rows.append(r)
    return rows


def with_minimal(rows):
    """Each row gets `_min`: what the minimal HUD of the stage table would cover in the same frame (tools/ui_audit/sheets.py MINIMAL), None for a state it does not describe."""
    import sheets
    for r in rows:
        try:
            if sheets.key_of(r["_label"]) is None:
                r["_min"] = None
            else:
                r["_min"] = sheets.minimal_stats(r["_dir"])
        except Exception as exc:    # (a snapshot with a part missing: the table says nothing for it)
            print("minimal_stats failed for", r["_dir"], exc, file=sys.stderr)
            r["_min"] = None
    return rows


def mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs) if xs else 0.0


def aggregate(rows):
    g = defaultdict(list)
    for r in rows:
        g[(r["_size"], r["_state"])].append(r)
    out = {}
    for k, rs in g.items():
        el = defaultdict(list)
        for r in rs:
            for e in r["elements"]:
                el[e["name"]].append(e)
        out[k] = {
            "n": len(rs), "ui": mean(r["masks"]["union"]["pct"] for r in rs), "centre": mean(r["masks"]["union"]["centre"] for r in rs),
            "hud": mean(r["masks"]["hud"]["pct"] for r in rs), "tut": mean(r["masks"]["tut"]["pct"] for r in rs), "labels": mean(r["masks"]["labels"]["pct"] for r in rs),
            "hud_c": mean(r["masks"]["hud"]["centre"] for r in rs), "tut_c": mean(r["masks"]["tut"]["centre"] for r in rs), "labels_c": mean(r["masks"]["labels"]["centre"] for r in rs),
            "persistent": mean(r["kinds"]["persistent"]["pct"] for r in rs), "teaching": mean(r["kinds"]["teaching"]["pct"] for r in rs), "transient": mean(r["kinds"]["transient"]["pct"] for r in rs),
            "persistent_c": mean(r["kinds"]["persistent"]["centre"] for r in rs),
            "blind_near": mean(r["blind"]["union"]["near"] for r in rs), "blind_all": mean(r["blind"]["union"]["all"] for r in rs),
            "dead": sum(r["dead_in_view"] for r in rs), "hidden": sum(r["dead_hidden"] for r in rs), "cov30": sum(r["dead_covered_30"] for r in rs), "covany": sum(r["dead_covered_any"] for r in rs),
            "elements": {n: {"pct": mean(e["pct"] for e in es), "centre": mean(e["centre"] for e in es), "blind_near": mean(e["blind"]["near"] for e in es), "n": len(es), "kind": es[0]["kind"]} for n, es in el.items()},
            "rows": rs,
        }
    return out


def f1(x):
    return "%.1f" % x


def table(agg, size):
    lines = ["| State | UI % screen | UI % centre | HUD % | Guide, banner, alerts % | Marks of the world % | Persistent boards % | Blind near her % | Dead in view | Hidden over half |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for st in ORDER:
        a = agg.get((size, st))
        if a is None:
            continue
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %d | %d |" % (TITLES.get(st, st), f1(a["ui"]), f1(a["centre"]), f1(a["hud"]), f1(a["tut"]), f1(a["labels"]), f1(a["persistent"]),
                                                                              f1(a["blind_near"]), a["dead"], a["hidden"]))
    return "\n".join(lines)


def offenders(agg, size, states):
    """Parts ranked by their mean share of the screen over the given states."""
    per = defaultdict(list)
    for st in states:
        a = agg.get((size, st))
        if a is None:
            continue
        for n, e in a["elements"].items():
            per[n].append((st, e))
    rows = []
    n_states = len([s for s in states if (size, s) in agg])
    for n, lst in per.items():
        mean_pct = sum(e["pct"] for _, e in lst) / max(n_states, 1)
        rows.append((n, lst[0][1]["kind"], mean_pct, max(e["pct"] for _, e in lst), max(lst, key=lambda x: x[1]["pct"])[0], sum(e["blind_near"] for _, e in lst) / max(n_states, 1),
                     len(lst), sum(e["centre"] for _, e in lst) / max(n_states, 1)))
    rows.sort(key=lambda r: -r[2])
    return rows, n_states


def md_offenders(rows, n_states):
    lines = ["| Rank | Part | Kind | Mean % of screen | Most % (in) | Mean % of centre | Blind near her % | In how many states |", "|---|---|---|---|---|---|---|---|"]
    for i, r in enumerate(rows, 1):
        lines.append("| %d | %s | %s | %.2f | %.2f (%s) | %.2f | %.2f | %d of %d |" % (i, r[0], r[1], r[2], r[3], r[4], r[7], r[5], r[6], n_states))
    return "\n".join(lines)


def dead_table(rows, size):
    lines = ["| State | Seed | Dead in view | Covered over 0 | Over 30 percent | Hidden over 50 percent | What covers them (top parts) |", "|---|---|---|---|---|---|---|"]
    for st in ORDER:
        for r in sorted([x for x in rows if x["_size"] == size and x["_state"] == st], key=lambda x: (x["_seed"], x["_label"])):
            if r["dead_in_view"] == 0:
                continue
            tops = defaultdict(float)
            for d in r["dead"]:
                for n, f in d["top"]:
                    tops[n] = max(tops[n], f)
            top = ", ".join("%s %d%%" % (n, round(f * 100)) for n, f in sorted(tops.items(), key=lambda kv: -kv[1])[:3])
            lines.append("| %s (%s) | %d | %d | %d | %d | %d | %s |" % (TITLES.get(st, st), r["_label"], r["_seed"], r["dead_in_view"], r["dead_covered_any"], r["dead_covered_30"], r["dead_hidden"], top))
    return "\n".join(lines)


def minimal_table(rows, size):
    """Current against the minimal HUD, state by state (the mean of the seeds and shots of a state)."""
    g = defaultdict(list)
    for r in rows:
        if r["_size"] == size and r.get("_min") is not None:
            g[r["_state"]].append(r)
    lines = ["| State | UI % now | UI % minimal | Centre % now | Centre % minimal | Blind near her % now | minimal | Dead in view | Hidden over half now | minimal |", "|---|---|---|---|---|---|---|---|---|---|"]
    for st in ORDER:
        rs = g.get(st)
        if not rs:
            continue
        lines.append("| %s | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %d | %d | %d |" % (
            TITLES.get(st, st), mean(r["masks"]["union"]["pct"] for r in rs), mean(r["_min"]["ui"] for r in rs), mean(r["masks"]["union"]["centre"] for r in rs),
            mean(r["_min"]["centre"] for r in rs), mean(r["blind"]["union"]["near"] for r in rs), mean(r["_min"]["blind"]["near"] for r in rs),
            sum(r["dead_in_view"] for r in rs), sum(r["dead_hidden"] for r in rs), sum(r["_min"]["dead_hidden"] for r in rs)))
    return "\n".join(lines)


def main():
    root = sys.argv[1]
    rows = collect(root)
    if "--minimal" in sys.argv:
        with_minimal(rows)
    agg = aggregate(rows)
    sizes = sorted({r["_size"] for r in rows}, key=lambda s: -int(s.split("x")[0]) * int(s.split("x")[1]))
    out = []
    for size in sizes:
        out.append("### %s\n" % size)
        out.append(table(agg, size))
        out.append("")
    json.dump({"%s|%s" % k: {kk: vv for kk, vv in v.items() if kk != "rows"} for k, v in agg.items()}, open(os.path.join(root, "summary.json"), "w"), indent=1)
    text = "\n".join(out)
    open(os.path.join(root, "summary.md"), "w").write(text)
    print(text)
    if "--minimal" in sys.argv:
        for size in sizes:
            print("\n#### The minimal HUD against the HUD now, %s\n" % size)
            print(minimal_table(rows, size))
    if "--budget" in sys.argv:
        play = ["a_arrive", "b_opening_0", "b_opening_3", "c_clearing", "d_day", "e_night", "e_storm"]
        for size in sizes:
            rws, n = offenders(agg, size, play)
            print("\n#### Offenders at %s (mean over %s)\n" % (size, ", ".join(play)))
            print(md_offenders(rws, n))


if __name__ == "__main__":
    main()
