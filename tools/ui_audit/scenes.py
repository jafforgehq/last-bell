#!/usr/bin/env python3
"""The staged scenes of the HUD audit (PH7) and the runner that plays one of them in a real window.

    python3 tools/ui_audit/scenes.py list
    python3 tools/ui_audit/scenes.py run OUTDIR SCENE WxH [seed]      # one scene at one window size

A scene is the game's own flags (README flag table) plus the audit driver's (tools/ui_audit/driver.gd): `scn` is the driver's scenario, the other keys are `--capture-<key>=`.
One Godot at a time; a run that has not finished in `timeout` seconds is killed by its own PID (never by name).
"""
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GODOT = os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot")

# The windows: the itch embed first.
SIZES = ["1280x720", "1280x800", "1920x1080", "1024x640"]

# name -> {"flags": game flags, "scn": driver scenario, "opts": driver options, "snaps": snapshot labels it writes (for the analysis), "seeds": seeds worth taking, "timeout": s}
# {S} is the town seed. The staging flags are the README's.
SCENES = {
    # (a) arrival at dawn, before she moves. a_hold is the first screen of a real run (the game held, "Press W A S D to begin", no banner); a_arrive is the next second
    # (the first key lifts the hold: the banner "The bell is ringing somewhere", the WASD cue, the lesson card, the legend, the objective and the arrows of the first screen)
    "a_hold": {"flags": "--stage=arrive", "scn": "still", "opts": {"wait": 60, "hold": 1}, "snaps": ["a_hold"], "seeds": [1, 3, 5], "seeds_other": [1], "timeout": 120},
    "a_arrive": {"flags": "--stage=arrive", "scn": "still", "opts": {"wait": 100}, "snaps": ["a_arrive"], "seeds": [1, 3, 5], "seeds_other": [1], "timeout": 120},
    # (b) the scripted opening: the first walker steps out, and three seconds later
    "b_opening": {"flags": "--stage=arrive", "scn": "opening", "opts": {"wait": 30}, "snaps": ["b_opening_0", "b_opening_3"], "seeds": [1, 3, 5], "timeout": 240},
    # (c) in the first house, the rooms not yet cleared, two of the dead awake and coming
    "c_clearing": {"flags": "--stage=arrive --lesson=door:in", "scn": "clearing", "opts": {"wait": 60, "dead": 2, "run": 2.0}, "snaps": ["c_clearing"], "seeds": [1, 3, 5], "seeds_other": [1], "timeout": 120},
    # (d) the claimed house by day, the crew at work; the first dusk
    "d_day": {"flags": "--stage=rescued2 --hour=11 --advance=20 --stock=scrap:30,ammo:24,food:12,water:18,meds:3", "scn": "still", "opts": {"wait": 120, "guide": "done", "tips": 1}, "snaps": ["d_day"], "seeds": [1], "timeout": 120},
    "d_dusk": {"flags": "--stage=fourth --slots=built --hour=18.7 --moment=bell:1.0 --stock=scrap:30,ammo:24,food:12,water:18,meds:3", "scn": "still", "opts": {"wait": 150, "guide": "done", "tips": 1}, "snaps": ["d_dusk"], "seeds": [1], "timeout": 120},
    # (e) the first attack night, at the fence: patrol, shooting; in clear weather and in a storm
    "e_night": {"flags": "--stage=night --slots=built --weather=clear --advance=135 --weapon=shotgun --avatar-at=149.5,91.5", "scn": "night", "opts": {"wait": 30, "dead": 2, "gap": 6, "shots": 3, "guide": "done", "tips": 1}, "snaps": ["e_night_1", "e_night_2", "e_night_3"], "seeds": [1], "timeout": 300},
    "e_storm": {"flags": "--stage=night --slots=built --weather=storm --advance=135 --weapon=shotgun --avatar-at=149.5,91.5", "scn": "night", "opts": {"wait": 30, "dead": 2, "gap": 6, "shots": 3, "guide": "done", "tips": 1}, "snaps": ["e_storm_1", "e_storm_2", "e_storm_3"], "seeds": [1], "timeout": 300},
    # (f) the morning card
    "f_dawn": {"flags": "--stage=night --slots=damaged --moment=dawn", "scn": "dawn", "opts": {"wait": 60, "until": "dawn", "guide": "done"}, "snaps": ["f_dawn"], "seeds": [1], "timeout": 120},
    # (g) the Build page and the radio panel open (the build lesson is the guide's own on the Build page: its card and cue stay)
    "g_build": {"flags": "--stage=arrive --lesson=build --radio=build --stock=scrap:30,ammo:24,food:12,water:18,meds:3", "scn": "still", "opts": {"wait": 100}, "snaps": ["g_build"], "seeds": [1], "timeout": 120},
    "g_radio": {"flags": "--stage=fourth --slots=built --hour=15 --radio=news,news", "scn": "still", "opts": {"wait": 100, "guide": "done"}, "snaps": ["g_radio"], "seeds": [1], "timeout": 120},
}

# The lessons of the guide one by one (a still of each: README `--lesson=`).
for _l in ["walk", "shoot", "reload", "find", "claim", "build", "ask"]:
    SCENES["l_" + _l] = {"flags": "--stage=arrive --lesson=" + _l, "scn": "still", "opts": {"wait": 100}, "snaps": ["l_" + _l], "seeds": [1], "timeout": 120}
SCENES["l_rehearsal"] = {"flags": "--stage=claimed --lesson=rehearsal --hour=11", "scn": "still", "opts": {"wait": 100}, "snaps": ["l_rehearsal"], "seeds": [1], "timeout": 120}

# The set the probe (run_audit.sh) plays by default: the states that carry the numbers, in the itch window.
# The inventory window (INV-UI, Tab): the pack with the weapon and the melee slot. `--inv=` is the game's own staging (README).
# (`--inv=loot` and `--inv=stash` open at frame 6 and close again when she is not at the container or the stash, which a driver that waits cannot help: only the pack is staged here)
for _n, _f in [("h_inv_pack", "--inv=open")]:
    SCENES[_n] = {"flags": "--stage=claimed --hour=10 " + _f, "scn": "still", "opts": {"wait": 120, "guide": "done"}, "snaps": [_n], "seeds": [1], "timeout": 120}

PROBE = ["a_hold", "a_arrive", "b_opening", "c_clearing", "d_day", "e_night", "f_dawn", "g_build"]
# the set played at the other window sizes (no lessons one by one, no storm: the shares of the screen change with the window, not with the sky)
INV = ["h_inv_pack"]
OTHER = ["a_hold", "a_arrive", "b_opening", "c_clearing", "d_day", "d_dusk", "e_night", "f_dawn", "g_build", "g_radio"]


def trash(path):
    """An old result is moved to ~/.Trash, never deleted."""
    if not os.path.exists(path):
        return
    dest = os.path.join(os.path.expanduser("~/.Trash"), "ui_audit_%d_%s" % (int(time.time() * 1000), os.path.basename(path)))
    shutil.move(path, dest)


def run(outdir, scene, size, seed=1):
    sc = SCENES[scene]
    os.makedirs(outdir, exist_ok=True)
    raw = os.path.join(outdir, "raw")
    os.makedirs(raw, exist_ok=True)
    tag = "%s_%s_s%d" % (scene, size, seed)
    snapdir = os.path.join(outdir, size, "s%d" % seed)
    os.makedirs(snapdir, exist_ok=True)
    for sn in sc["snaps"]:
        trash(os.path.join(snapdir, sn))
    prefs = os.path.join(raw, "prefs_%s.cfg" % tag)
    trash(prefs)
    cmd = [GODOT, "--path", ROOT, "--", "--winpx=" + size, "--os-scale=1", "--town=%d" % seed]
    cmd += sc["flags"].split()
    cmd += ["--shot=" + os.path.join(raw, "never.png"), "--frames=99999999", "--prefs=" + prefs, "--capture=audit", "--capture-scn=" + sc["scn"],
            "--capture-name=" + scene, "--capture-out=" + snapdir]
    for k, v in sc["opts"].items():
        cmd.append("--capture-%s=%s" % (k, v))
    log = os.path.join(raw, tag + ".log")
    t0 = time.time()
    with open(log, "w") as lf:
        p = subprocess.Popen(cmd, stdout=lf, stderr=subprocess.STDOUT, cwd=ROOT)
        try:
            p.wait(timeout=sc.get("timeout", 150))
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()
            print("TIMEOUT", tag)
    done = [sn for sn in sc["snaps"] if os.path.exists(os.path.join(snapdir, sn, "meta.json"))]
    print("%-22s %-10s seed %d: %d of %d snapshots, %.0f s" % (scene, size, seed, len(done), len(sc["snaps"]), time.time() - t0))
    return done


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "list":
        for k, v in SCENES.items():
            print(k, v["flags"], v["scn"], v["seeds"])
    elif len(sys.argv) >= 5 and sys.argv[1] == "run":
        run(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]) if len(sys.argv) > 5 else 1)
    else:
        print(__doc__)
