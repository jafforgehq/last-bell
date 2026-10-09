#!/usr/bin/env python3
"""Play a list of scenes at a list of window sizes, one Godot at a time:

    python3 tools/ui_audit/run_scenes.py OUTDIR [--scenes a_arrive,b_opening,...|probe|other|all] [--sizes 1280x720,...] [--seeds each|1,3,5]

`probe` is scenes.PROBE (the default), `other` scenes.OTHER (what the other window sizes get), `inv` the inventory window, `all` every other scene of tools/ui_audit/scenes.py. With --seeds each (the default) a scene
plays the seeds it names itself (`seeds`, and at a size other than the first of SIZES the shorter `seeds_other`).
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scenes  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--scenes", default="probe")
    ap.add_argument("--sizes", default=scenes.SIZES[0])
    ap.add_argument("--seeds", default="each")
    a = ap.parse_args()
    names = {"probe": scenes.PROBE, "other": scenes.OTHER, "inv": scenes.INV, "all": [n for n in scenes.SCENES if n not in scenes.INV]}.get(a.scenes) or a.scenes.split(",")
    for size in a.sizes.split(","):
        for name in names:
            sc = scenes.SCENES[name]
            if a.seeds == "each":
                seeds = sc["seeds_other"] if size != scenes.SIZES[0] and "seeds_other" in sc else sc["seeds"]
            else:
                seeds = [int(x) for x in a.seeds.split(",")]
            for seed in seeds:
                scenes.run(a.out, name, size, seed)


if __name__ == "__main__":
    main()
