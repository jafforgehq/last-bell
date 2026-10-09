#!/usr/bin/env python3
"""Check that the snapshot's switches do what the game's own flags do: three real screenshot runs of the arrival (full, `--nohud`, `--hide-lesson --no-banner --no-alerts`) against the same
masks made by the driver in one frozen frame. Prints the overlap (intersection over union) of the masks and the pixels each has alone.

    python3 tools/ui_audit/verify_flags.py OUTDIR SNAPSHOT_DIR [WxH] [seed]      # SNAPSHOT_DIR: a_arrive of the same size and seed, from run_scenes.py
"""
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze  # noqa: E402
import scenes  # noqa: E402


def shot(out, name, size, seed, extra):
    p = os.path.join(out, name + ".png")
    cmd = [scenes.GODOT, "--path", scenes.ROOT, "--", "--winpx=" + size, "--os-scale=1", "--town=%d" % seed, "--stage=arrive", "--shot=" + p, "--frames=130",
           "--prefs=" + os.path.join(out, "prefs_verify.cfg")] + extra
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180, cwd=scenes.ROOT)
    return p


def main():
    out, snap = sys.argv[1], sys.argv[2]
    size = sys.argv[3] if len(sys.argv) > 3 else "1280x720"
    seed = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    os.makedirs(out, exist_ok=True)
    shot(out, "v_full", size, seed, [])
    shot(out, "v_nohud", size, seed, ["--nohud"])
    shot(out, "v_flags", size, seed, ["--hide-lesson", "--no-banner", "--no-alerts"])
    full, nohud, flags = (analyze.load(out, n) for n in ("v_full", "v_nohud", "v_flags"))
    mine = {"nohud": analyze.diff(analyze.load(snap, "full"), analyze.load(snap, "nohud")), "flags": analyze.diff(analyze.load(snap, "full"), analyze.load(snap, "flags"))}
    real = {"nohud": analyze.diff(full, nohud), "flags": analyze.diff(full, flags)}
    for k in ("nohud", "flags"):
        a, b = mine[k], real[k]
        inter = int((a & b).sum())
        uni = int((a | b).sum())
        print("%-6s snapshot %6d px, real flag %6d px, overlap (IoU) %.3f, only in the snapshot %d, only in the real run %d" % (k, int(a.sum()), int(b.sum()), inter / max(uni, 1), int((a & ~b).sum()), int((b & ~a).sum())))


if __name__ == "__main__":
    main()
