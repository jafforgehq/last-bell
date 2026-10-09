#!/usr/bin/env python3
"""Markdown tables of docs/audio-capture.md from the .json files of tools/audio_capture.py (tools/capture_clip.sh writes one per clip).

    python3 tools/audio_capture_tables.py LABEL=DIR [LABEL=DIR ...]      (one directory of clip json files per run: "before", "after")

Prints: the master of each clip (peak of the 16-bit file, samples at full scale, loudness, the limiter's work), each bus's loudness by clip, and the figures that the mix table of
docs/audio-mix.md has a target for (the pump gun, footsteps by ground, voices, the rain bed, thunder), as the real mix measured them.
"""
import json
import os
import sys

CLIPS = ["a_walk", "b_fight", "c_storm", "d_night", "e1_build", "e2_dawn", "h_storm_attack"]
NAMES = {"a_walk": "a walk", "b_fight": "b day fight", "c_storm": "c storm", "d_night": "d night attack", "e1_build": "e1 build", "e2_dawn": "e2 dawn card", "h_storm_attack": "h storm attack"}


def load(d):
    out = {}
    for c in CLIPS + ["g_calib"]:
        p = os.path.join(d, c + ".json")
        if os.path.exists(p):
            out[c] = json.load(open(p))
    return out


def f(v, d=1):
    return "-" if v is None else ("%.*f" % (d, v))


def main():
    runs = []
    for a in sys.argv[1:]:
        label, d = a.split("=", 1)
        runs.append((label, load(d)))
    for label, R in runs:
        print("### %s: the master of each clip\n" % label)
        print("| Clip | Length (s) | Peak of the 16-bit file (dBFS) | Samples at full scale | Integrated (LUFS) | M-max | Short-term max | Pre-limiter peak (dBFS) | Over the -0.5 ceiling (samples) | Limiter working (ms, episodes) | Most it took off (dB) |")
        print("|---|---|---|---|---|---|---|---|---|---|---|")
        for c in CLIPS:
            r = R.get(c)
            if not r:
                continue
            m, L, w = r["master"], r["limiter"], r.get("wav", {})
            print("| %s | %.0f | %s | %s | %s | %s | %s | %s | %d | %d ms, %d | %s |" % (NAMES[c], r["seconds"], f(w.get("peak_dbfs"), 2), w.get("full_scale", "-"), f(m["integrated"]), f(m["mmax"]), f(m["short_max"]), f(L["pre_peak_dbfs"], 2),
                                                                                     L["pre_over_ceiling"], L["ms_working"], L["episodes"], f(L["max_reduction_db"], 1)))
        print()
        print("### %s: each bus as it reaches the Master (integrated LUFS over the clip / loudest 400 ms)\n" % label)
        buses = ["SFX", "Steps", "Voices", "Ambience", "Rain", "Distant", "Music", "UI"]
        cl = [c for c in CLIPS if c in R]
        print("| Bus | " + " | ".join(NAMES[c] for c in cl) + " |")
        print("|---|" + "---|" * len(cl))
        for b in buses:
            cells = []
            for c in cl:
                v = R[c]["buses"].get(b)
                cells.append("-" if (v is None or v["integrated"] <= -69.0) else "%s / %s" % (f(v["integrated"]), f(v["mmax"])))
            print("| %s | " % b + " | ".join(cells) + " |")
        print()
        print("### %s: against the mix table\n" % label)
        rows = []
        for c in cl:
            r = R[c]
            g = r["events"]["guns"]["mmax"]
            if g:
                rows.append(("Gunfire (bursts of the SFX bus alone over -15 LUFS), %s" % NAMES[c], "%d bursts, median %.1f, loudest %.1f, quietest %.1f" % (g["n"], g["median"], g["max"], g["min"]), "-13 (-12.7 to -13.9)"))
        for c in cl:
            sg = R[c]["events"].get("steps_by_ground", {})
            for k, v in sg.items():
                rows.append(("Ruth %s, %s (loudest 400 ms)" % (k, NAMES[c]), "%.1f (%d windows)" % (v["max"], v["n"]), "walk: -28 to -30.5; run: -21.4 to -23.9"))
        for c in cl:
            vo = R[c]["events"]["voices"]["mmax"]
            if vo:
                rows.append(("Voices, %s" % NAMES[c], "%d bursts, loudest %.1f, median %.1f" % (vo["n"], vo["max"], vo["median"]), "near -15.5 to -17; far under -22"))
        for c in cl:
            ra = R[c]["events"].get("rain_at_master")
            if ra and ra.get("outdoors"):
                rows.append(("Rain bed outdoors, %s (loudest 400 ms, no thunder)" % NAMES[c], "%.1f (median %.1f)" % (ra["outdoors"]["max"], ra["outdoors"]["median"]), "storm -20.4"))
            if ra and ra.get("indoors"):
                rows.append(("Rain bed under a roof, %s (median)" % NAMES[c], "%.1f" % ra["indoors"]["median"], "storm -31.8"))
            rb = R[c]["events"].get("rain_bursts")
            if rb:
                rows.append(("Thunder, %s" % NAMES[c], ", ".join("%.1f" % b["mmax"] for b in rb), "near -13.4 / mid -21.4 / far -27.8"))
        if "g_calib" in R and R["g_calib"].get("calib"):
            for cc in R["g_calib"]["calib"]:
                rows.append(("Calibration groan from %.0f tiles" % cc["tiles"], "%.1f" % cc["mmax"], "3 tiles -15.5 to -17.0; 8 tiles -18.6 to -19.9; 14 tiles -22.0 to -22.7"))
        print("| What | Measured in the real mix (LUFS at the Master) | Mix table (docs/audio-mix.md) |")
        print("|---|---|---|")
        for a, b, c in rows:
            print("| %s | %s | %s |" % (a, b, c))
        print()


main()
