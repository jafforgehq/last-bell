#!/usr/bin/env python3
"""The closest thing to listening: measures every file of assets/audio/prison/ (peak, RMS, a K-weighted loudness in the manner of
ITU-R BS.1770 without gating, spectral centroid, clipping, DC, the step at a loop's seam) and draws spectrograms of the main sounds.
Writes docs/experiments/prison-audio-report.md and docs/experiments/prison-audio/*.png.   python3 tools/prison_audio_report.py
NumPy and Pillow only."""
import glob
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIR = os.path.join(ROOT, "assets", "audio", "prison")
DOC = os.path.join(ROOT, "docs", "experiments")
PNG = os.path.join(DOC, "prison-audio")
os.makedirs(PNG, exist_ok=True)
SPEC = ("pm_drone", "pm_motif", "pm_drip", "pm_pulse", "pm_perc", "pm_danger", "pm_chase", "pst_dawn", "pa_rain_roof", "pa_fire", "pa_wind_gust", "pd_cell_slam_0",
        "pd_chain_0", "pf_mud_0", "pv_male_pain", "pv_female_effort", "pt_tail_2", "pw_rattle_0")


def read(path):
    import wave
    with wave.open(path) as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    return x, sr


def kweight_response(f, sr):
    """The magnitude of the two K-weighting biquads (BS.1770: a high shelf, then a high-pass), derived for any sample rate."""
    def biquad(b, a):
        w = 2 * np.pi * f / sr
        z = np.exp(-1j * w)
        return (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = np.tan(np.pi * f0 / sr)
    Vh = 10 ** (G / 20.0)
    Vb = Vh ** 0.4996667741545416
    a0 = 1.0 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2.0 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1.0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = np.tan(np.pi * f0 / sr)
    a0 = 1.0 + K / Q + K * K
    a2 = [1.0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0]
    return np.abs(biquad(b1, a1)) * np.abs(biquad([1.0, -2.0, 1.0], a2))


def lufs(x, sr):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    y = np.fft.irfft(X * kweight_response(f, sr), len(x))
    return -0.691 + 10 * np.log10(np.mean(y * y) + 1e-12)


def db(v):
    return 20 * np.log10(max(v, 1e-9))


def spectrogram(x, sr, name):
    n = 1024 if sr >= 22050 else 512
    hop = max(1, (len(x) - n) // 800)
    win = np.hanning(n)
    cols = []
    for i in range(0, len(x) - n, hop):
        cols.append(np.abs(np.fft.rfft(x[i:i + n] * win)))
    S = 20 * np.log10(np.array(cols).T + 1e-6)
    S = np.clip((S - (S.max() - 80.0)) / 80.0, 0, 1)[::-1]
    h = min(S.shape[0], 200)
    S = np.array(Image.fromarray((S * 255).astype(np.uint8)).resize((S.shape[1], h), Image.BILINEAR))
    lut = np.array([[min(255, int(255 * (v / 255) ** 0.8 * c)) for c in (1.0, 0.75 + 0.25 * v / 255, 0.35)] for v in range(256)], dtype=np.uint8)
    Image.fromarray(lut[S]).save(os.path.join(PNG, name + ".png"))


def main():
    rows = []
    stats = {}
    for p in sorted(glob.glob(os.path.join(DIR, "*.wav"))):
        name = os.path.basename(p)[:-4]
        x, sr = read(p)
        man = json.load(open(os.path.join(DIR, "audio_manifest.json"))).get(name, {})
        loop = bool(man.get("loop"))
        spec = np.abs(np.fft.rfft(x))
        f = np.fft.rfftfreq(len(x), 1.0 / sr)
        cen = float((spec * f).sum() / (spec.sum() + 1e-12))
        d = np.diff(x)
        seam = abs(x[0] - x[-1])
        ratio = seam / (np.sqrt(np.mean(d * d)) + 1e-12)
        s = {"name": name, "sec": len(x) / sr, "sr": sr, "peak": db(np.max(np.abs(x))), "rms": db(np.sqrt(np.mean(x * x))), "lufs": lufs(x, sr), "cen": cen,
             "clip": int(np.sum(np.abs(x) >= 0.999)), "dc": float(np.mean(x)), "loop": loop, "seam": float(seam), "ratio": float(ratio), "kb": os.path.getsize(p) // 1024}
        stats[name] = s
        rows.append(s)
        if name in SPEC:
            spectrogram(x, sr, name)
    flags = []
    lines = ["# Prison audio report (Round 12)", "",
             "Made by `python3 tools/prison_audio_report.py` from the files in `assets/audio/prison/`. Nobody has listened to these: the numbers are what a machine can say. "
             "Loudness is a K-weighted level of the whole file without gating (LUFS-ish; a mono file played at 0 dB, before the bus trims and the player's volume). "
             "A loop's seam is the step between its last and first sample: `step` is that difference in full-scale units, `ratio` is it against the RMS of the steps inside the file (1 is as smooth as the loop is everywhere; a click is 20 or more).", "",
             "| file | sec | peak dB | RMS dB | LUFS | centroid Hz | clip | DC | seam step | seam ratio | KB |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    tot = 0
    music = 0
    for s in rows:
        tot += s["kb"]
        if s["name"].startswith(("pm_", "pst_")):
            music += s["kb"]
        seam = ("%.5f" % s["seam"], "%.2f" % s["ratio"]) if s["loop"] else ("", "")
        if s["clip"]:
            flags.append("%s clips (%d samples)" % (s["name"], s["clip"]))
        if s["loop"] and s["ratio"] > 6.0:
            flags.append("%s seam ratio %.1f" % (s["name"], s["ratio"]))
        if abs(s["dc"]) > 0.002:
            flags.append("%s DC offset %.4f" % (s["name"], s["dc"]))
        lines.append("| %s | %.1f | %.1f | %.1f | %.1f | %d | %d | %.4f | %s | %s | %d |" % (s["name"], s["sec"], s["peak"], s["rms"], s["lufs"], s["cen"], s["clip"], s["dc"], seam[0], seam[1], s["kb"]))
    # what a mood sounds like when its stems play together (powers add; the stems are not correlated)
    def mix(gains):
        p = sum(10 ** ((stats[k]["lufs"] + 20 * np.log10(g)) / 10) for k, g in gains.items())
        return 10 * np.log10(p)
    moods = {"day (drone .5, motif .8)": {"pm_drone": .5, "pm_motif": .8}, "dusk (drone .7, drip .6, motif .4)": {"pm_drone": .7, "pm_drip": .6, "pm_motif": .4},
             "night (drone .8, drip .8, pulse .35)": {"pm_drone": .8, "pm_drip": .8, "pm_pulse": .35},
             "siege full (drone .8, pulse 1, perc 1, danger .9)": {"pm_drone": .8, "pm_pulse": 1, "pm_perc": 1, "pm_danger": .9},
             "clear phase (explore .9, drone .3)": {"pm_explore": .9, "pm_drone": .3}, "far raid (raid 1, drone .5, drip .5)": {"pm_raid": 1, "pm_drone": .5, "pm_drip": .5},
             "chase (chase 1, raid .4)": {"pm_chase": 1, "pm_raid": .4}}
    lines += ["", "## Moods (the stems at the gains the game gives them, summed; mono, Music bus at 0 dB)", "", "| mood | LUFS-ish |", "|---|---|"]
    for k, g in moods.items():
        lines.append("| %s | %.1f |" % (k, mix(g)))
    lines += ["", "Target from the brief: music about -18 LUFS at its fullest, effects about -12 LUFS. The calm moods are meant to be quieter than that (they are the bed), the siege and the chase reach it.", "",
              "## Sizes", "", "All files: %.1f MB as WAV source. Music (pm_ and pst_): %.2f MB (the budget is 8 MB). The export carries them as QOA, about a fifth of this." % (tot / 1024.0, music / 1024.0), "",
              "## Flags", ""]
    lines += ["- " + f for f in flags] or ["- none: no clipping, no DC offset, no loop seam over a ratio of 6"]
    lines += ["", "## Spectrograms", "", "In `docs/experiments/prison-audio/` (time left to right, frequency up, 80 dB of range): " + ", ".join(SPEC) + "."]
    open(os.path.join(DOC, "prison-audio-report.md"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines[-14:]))
    for f in flags:
        print("FLAG", f)


if __name__ == "__main__":
    main()
