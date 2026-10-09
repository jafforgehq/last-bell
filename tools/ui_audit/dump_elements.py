#!/usr/bin/env python3
"""The list of the UI parts of a snapshot with their screen rectangles, areas and shares, biggest first (markdown).

    python3 tools/ui_audit/dump_elements.py SNAPSHOT_DIR [--tree]      # --tree adds every visible Control of the scene tree with its rectangle (meta.json `tree`)

`rect` is the box of the part's node in screen pixels (a part that only draws, as the cues or the arrows, is the whole window: its box says nothing, `ink box` is the box of the pixels
it changes); `ink` is the number of pixels the part covers (the diff of the frame with and without it, closed), `% screen` and `% centre` its shares of the screen and of the centre zone.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze  # noqa: E402


def main():
    d = sys.argv[1]
    if not os.path.exists(os.path.join(d, "result.json")):
        analyze.analyze(d)
    r = json.load(open(os.path.join(d, "result.json")))
    m = json.load(open(os.path.join(d, "meta.json")))
    rects = {e["name"]: e["rects"] for e in m.get("elements", [])}
    w, h = r["size"]
    print("%s, %dx%d, hour %.1f: UI %.1f%% of the screen, %.1f%% of the centre\n" % (r["label"], w, h, float(r.get("hour") or 0), r["masks"]["union"]["pct"], r["masks"]["union"]["centre"]))
    print("| Part | Kind | Node rect (x, y, w, h) | Ink box | Ink px | % screen | % centre | Blind near her % |")
    print("|---|---|---|---|---|---|---|---|")
    for e in r["elements"]:
        rc = rects.get(e["name"], [])
        node = "; ".join("%d, %d, %d, %d" % tuple(int(v) for v in x) for x in rc[:2]) if rc else "-"
        if rc and len(rc) == 1 and int(rc[0][2]) >= w - 2 and int(rc[0][3]) >= h - 2:
            node = "whole window (draws)"
        ink = "%d, %d, %d, %d" % tuple(e["bbox"]) if node in ("-", "whole window (draws)") else "(in its box)"
        print("| %s | %s | %s | %s | %d | %.2f | %.2f | %.2f |" % (e["name"], e["kind"], node, ink, e["px"], e["pct"], e["centre"], e["blind"]["near"]))
    if r["dead"]:
        print("\nDead in view:\n")
        print("| Kind | State | Tiles from her | Screen point | Box (x, y, w, h) | Covered % | Hidden | Nearest part (px) | Top parts over it |")
        print("|---|---|---|---|---|---|---|---|---|")
        for x in r["dead"]:
            print("| %s | %s | %.1f | %d, %d | %d, %d, %d, %d | %d | %s | %s | %s |" % (x["kind"], x["state"], x["dist"], x["px"][0], x["px"][1], *x["box"], round(x["covered"] * 100), "yes" if x["hidden"] else "no",
                                                                                  "%s (%.0f)" % tuple(x["nearest"]) if x.get("nearest") else "-", ", ".join("%s %d%%" % (n, round(f * 100)) for n, f in x["top"]) or "-"))
    if "--tree" in sys.argv:
        print("\nEvery visible Control (scene tree order):\n")
        print("| Layer | Class | Rect (x, y, w, h) | Text | Path (end) |")
        print("|---|---|---|---|---|")
        for t in m.get("tree", []):
            if t.get("n2d") or t.get("full"):
                continue
            x, y, ww, hh = [int(v) for v in t["rect"]]
            if ww * hh < 120:
                continue
            print("| %d | %s | %d, %d, %d, %d | %s | %s |" % (t["layer"], t["cls"], x, y, ww, hh, t.get("text", "").replace("|", "/"), t["path"][-48:]))


if __name__ == "__main__":
    main()
