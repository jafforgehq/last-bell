#!/usr/bin/env python3
"""Makes the files for a person to open from the clips of tools/capture_clip.sh (docs/audio-capture.md): an .mp4 (H.264 picture and AAC sound, 1280 x 720, about 3.5 Mbit/s) and a .wav
(16-bit, 48 kHz, stereo: what the Master played, no encoder in between) of each clip, both with the loading card cut away.

    python3 tools/capture_publish.py RUN_DIR OUT_DIR /path/to/make_mp4 [clip names...]

RUN_DIR is what tools/capture_clip.sh was given (it holds NAME.json and raw/NAME.avi, raw/NAME_x/audio.wav). make_mp4 is tools/make_mp4.swift compiled (`swiftc -O tools/make_mp4.swift -o make_mp4`).
"""
import json
import os
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    run, out, mk = sys.argv[1], sys.argv[2], sys.argv[3]
    names = sys.argv[4:] or ["a_walk", "b_fight", "c_storm", "d_night", "e1_build", "e2_dawn", "h_storm_attack"]
    os.makedirs(out, exist_ok=True)
    for n in names:
        meta = json.load(open(os.path.join(run, n + ".json")))
        lag = int(meta["wav"]["lag_samples"])
        first = int(round(lag / 1600.0))      # (a frame is 1600 samples at 48 kHz and 30 fps)
        avi = os.path.join(run, "raw", n + ".avi")
        frames = os.path.join(run, "raw", n + "_mp4frames")
        res = subprocess.run([sys.executable, os.path.join(HERE, "avi_extract.py"), avi, frames, "--range=%d,%d" % (first, 10 ** 7)], capture_output=True, text=True)
        total = int([l for l in res.stdout.splitlines() if l.startswith("video:")][0].split(",")[1].split()[0])
        last = total - 1
        mp4 = os.path.join(out, "lastbell_%s.mp4" % n)
        subprocess.run([mk, frames, os.path.join(frames, "audio.wav"), mp4, str(first), str(last), "1280", "3500"], check=True)
        # the wav of the clip
        with wave.open(os.path.join(frames, "audio.wav"), "rb") as w:
            w.setpos(first * 1600)
            data = w.readframes((last - first + 1) * 1600)
            params = w.getparams()
        with wave.open(os.path.join(out, "lastbell_%s.wav" % n), "wb") as o:
            o.setparams(params)
            o.writeframes(data)
        print(n, "frames", first, "to", last, "->", mp4, "%.1f MB" % (os.path.getsize(mp4) / 1e6))


main()
