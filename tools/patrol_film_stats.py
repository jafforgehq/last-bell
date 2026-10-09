#!/usr/bin/env python3
"""What a patrol film (tools/patrol_film.gd) shows, counted from its film.log (one line a frame): python3 tools/patrol_film_stats.py FILM_DIR [FILM_DIR ...]

For each film: the frames (8 s apart), how many had two of the crew within 1.5 tiles of each other (a clump) and within 0.9 (on top of each other), how many had somebody outside
the lot, how many had the dead clawing at the fence while nobody of the crew was within 8 tiles of the middle of the claw (a side nobody covers: the log has no dead positions, so this
counts the frames with `claw > 0` and every crew member in mode walk/pause on the far side of the lot, see below), how many person-frames were spent standing in the open in
mode walk (not a pause) and how many in `hold`/`engaged`, and how many frames the crew was all down.
"""
import math
import re
import sys


def parse_lot(log_path):
    try:
        text = open(log_path).read()
    except OSError:
        return None
    m = re.search(r"lot \[P: \(([\d.]+), ([\d.]+)\), S: \(([\d.]+), ([\d.]+)\)\]", text)
    if not m:
        return None
    x, y, w, h = [float(v) for v in m.groups()]
    return (x, y, x + w, y + h)


def main():
    for d in sys.argv[1:]:
        lot = parse_lot(d + ".log")
        frames = 0
        clump = 0
        ontop = 0
        outside = 0
        claw_frames = 0
        hold_pf = 0
        walk_pf = 0
        pause_pf = 0
        post_pf = 0
        all_down = 0
        for line in open(d + "/film.log"):
            m = re.match(r"f(\d+) t=\s*([\d.]+) h\s*([\d.]+) (\w+) dead\s+(\d+) claw\s+(\d+) \| (.*)", line)
            if not m:
                continue
            if m.group(4) not in ("night", "dusk"):
                continue
            frames += 1
            claw = int(m.group(6))
            if claw > 0:
                claw_frames += 1
            people = []
            for part in m.group(7).split(" | "):
                pm = re.match(r"(\w+)\(([\d.]+),([\d.]+)\) (.*)", part)
                if not pm:
                    continue
                name, x, y, what = pm.group(1), float(pm.group(2)), float(pm.group(3)), pm.group(4)
                if name == "Rut" or "(avatar)" in what:
                    continue
                people.append((name, x, y, what))
            up = [p for p in people if "Down" not in p[3]]
            if people and not up:
                all_down += 1
            for i in range(len(up)):
                n, x, y, w = up[i]
                if lot and not (lot[0] <= x <= lot[2] and lot[1] <= y <= lot[3]):
                    outside += 1
                if w.startswith("walk"):
                    walk_pf += 1
                elif w.startswith("pause"):
                    pause_pf += 1
                elif w.startswith("hold") or w.startswith("engaged"):
                    hold_pf += 1
                elif w.startswith("-["):
                    post_pf += 1
            c = False
            t = False
            for i in range(len(up)):
                for j in range(i + 1, len(up)):
                    if up[i][3].startswith("-[Band") or up[j][3].startswith("-[Band"):
                        continue
                    dd = math.hypot(up[i][1] - up[j][1], up[i][2] - up[j][2])
                    if dd < 1.5:
                        c = True
                    if dd < 0.9:
                        t = True
            clump += int(c)
            ontop += int(t)
        print("%-34s night frames %2d | clump(<1.5) %2d  on top(<0.9) %2d | crew outside the lot %d person-frames | claw frames %2d | person-frames: walk %3d pause %3d hold/engaged %3d other-job %3d | all down %d" % (
            d.split("/")[-1], frames, clump, ontop, outside, claw_frames, walk_pf, pause_pf, hold_pf, post_pf, all_down))


if __name__ == "__main__":
    main()
