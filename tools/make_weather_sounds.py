#!/usr/bin/env python3
"""The thunder of Thirty Bells (the SOUND pass): mono 16-bit 22.05 kHz WAVs in assets/audio/, made from arithmetic alone (NumPy, tools/audio_dsp.py), a
fixed seed for each, so a second run writes the same bytes. (The rain bed, `rain_loop`, is the earlier generator's: tools/make_ambience.py.) Nobody can
listen where this was made: the thunder is checked by number (peak, loudness, length, how the energy is spread over frequency and over time) and the
owner's ears come after.

    python3 tools/make_weather_sounds.py             # writes the files and updates assets/audio/audio_manifest.json
    python3 tools/make_weather_sounds.py --check     # renders and prints, writes nothing

    thunder_near_0..1   a strike that is close: a tearing crack (a burst of 6 to 10 sharp snaps in a third of a second, then a rip), the first boom and
                        a rumble that rolls on for about four seconds (4.4 s)
    thunder_mid_0..1    a strike a few kilometres away: the crack is a dull snap, the rumble is longer and rolls in three or four waves (5.8 s)
    thunder_far_0       a strike far off: no crack at all, a slow swell of low rumble that rises for half a second and falls away (7.2 s)

The game (scripts/audio/foley.gd `thunder`, played from scripts/render/rain_view.gd) picks one by how far the strike is (the delay after the flash, 1 to 3 s,
sets it) and plays it on the Rain bus, so that the roof of a house muffles it like the rain.
"""
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as D  # noqa: E402
import audio_measure as M  # noqa: E402

WRITE = "--check" not in sys.argv
SR = 22050
CEILING = -4.0
# the loudest 400 ms (K-weighted mono LUFS) of each: a near strike is the loudest thing in a storm after a shot
LOUD = {"thunder_near": -15.0, "thunder_mid": -20.0, "thunder_far": -25.0}


def seed_of(name):
    return zlib.crc32(name.encode("ascii")) & 0x7fffffff


def lp(x, fc, order=2):
    return D.lowpass(x, fc, SR, order, circular=False)


def hp(x, fc, order=2):
    return D.highpass(x, fc, SR, order, circular=False)


def to_loudness(x, target, fade):
    x = x * D.tail_off(len(x), SR, fade)
    for _ in range(6):
        m = float(M.momentary(x, SR).max())
        x = x * 10.0 ** ((target - m) / 20.0)
        if D.peak_db(x) > CEILING:
            x = D.soft_ceiling(x, CEILING)
    return x


def rolls(t, rng, count, span, first, decay_s):
    """A rumble's loudness over time: a few waves (Gaussians) laid over a long fall; the first at `first` seconds."""
    env = np.zeros(len(t))
    centers = [first] + sorted(rng.uniform(first + 0.2, span, count - 1).tolist())
    for k, c in enumerate(centers):
        w = rng.uniform(0.18, 0.55) * (1.0 + 0.15 * k)
        a = rng.uniform(0.35, 1.0) if k else 1.0
        env += a * np.exp(-0.5 * ((t - c) / w) ** 2) * np.exp(-(c - first) / decay_s)
    return env * np.exp(-(t - first).clip(0) / (decay_s * 1.4))


def make(kind, i):
    name = "thunder_%s_%d" % (kind, i)
    rng = np.random.default_rng(seed_of(name))
    dur = {"near": 4.4, "mid": 5.8, "far": 7.2}[kind]
    n = int(dur * SR)
    t = np.arange(n) / SR
    brown = D.colored(n, rng, slope=-1.3, sr=SR)
    fc = {"near": 480.0, "mid": 340.0, "far": 250.0}[kind]
    low = hp(lp(brown, fc, 3), 38.0)
    mid = lp(hp(D.colored(n, rng, slope=-1.2, sr=SR), 70.0), {"near": 1400.0, "mid": 800.0, "far": 450.0}[kind])
    first = {"near": 0.06, "mid": 0.18, "far": 0.55}[kind]
    env = rolls(t, rng, {"near": 7, "mid": 6, "far": 5}[kind], dur * 0.62, first, {"near": 1.3, "mid": 1.9, "far": 2.5}[kind])
    env_mid = rolls(t, rng, 5, dur * 0.4, first, 0.7 if kind == "near" else 1.0)
    # the swell: a slow rise at the start (the nearer it is, the quicker)
    rise = D.ramp(t - (first - {"near": 0.0, "mid": 0.1, "far": 0.4}[kind]), {"near": 0.05, "mid": 0.25, "far": 0.7}[kind])
    out = (low / np.std(low)) * env * rise * 1.0 + (mid / np.std(mid)) * env_mid * rise * {"near": 0.9, "mid": 0.7, "far": 0.5}[kind]
    if kind in ("near", "mid"):
        # the lightning's own noise: sharp snaps (the channel tearing) and a rip that falls away in a fifth of a second
        k = 1.0 if kind == "near" else 0.28
        snaps = np.zeros(n)
        for j in range(int(rng.integers(6, 11)) if kind == "near" else int(rng.integers(3, 6))):
            at = 0.02 + 0.33 * rng.uniform(0, 1) ** 1.4
            ln = int(rng.uniform(0.004, 0.02) * SR)
            b = rng.standard_normal(ln) * np.exp(-np.arange(ln) / SR / rng.uniform(0.002, 0.008))
            b = hp(b, 650.0)
            a0 = int(at * SR)
            snaps[a0:a0 + ln] += b[:max(0, min(ln, n - a0))] * rng.uniform(0.4, 1.0) * np.exp(-at / 0.3)
        rip = lp(hp(rng.standard_normal(n), 900.0), 4200.0) * np.exp(-(t - 0.03).clip(0) / 0.11) * D.ramp(t, 0.01)
        sn = snaps / (np.std(snaps[:int(0.4 * SR)]) + 1e-9)
        rp = rip / (np.std(rip[:int(0.4 * SR)]) + 1e-9)
        out = out * 1.0 + k * (0.55 * sn + 0.35 * rp) * (np.std(out[:int(0.5 * SR)]) + 1e-9) * 1.0
    return name, to_loudness(out, LOUD["thunder_%s" % kind], 0.5), SR


def sounds():
    return [make("near", 0), make("near", 1), make("mid", 0), make("mid", 1), make("far", 0)]


def bands(x):
    spec = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    tot = max(spec.sum(), 1e-18)
    return [spec[(f >= lo) & (f < hi)].sum() / tot * 100.0 for lo, hi in ((0, 100), (100, 400), (400, 1500), (1500, 20000))]


def main():
    total = 0
    for name, x, sr in sounds():
        peak = D.peak_db(x)
        assert peak <= -3.0, "%s peaks at %.1f dBFS" % (name, peak)
        if WRITE:
            st = D.save(name, x, sr, kind="sfx", seed=seed_of(name), notes="make_weather_sounds.py")
            total += st["bytes"]
            fs = M.stats_of(os.path.join(D.OUT_DIR, name + ".wav"))    # (what is in the file: the loudest 400 ms and the centroid go into the manifest beside the peak)
            st["mmax_lufs"] = round(fs["mmax"], 1)
            st["centroid_hz"] = round(fs["cent"])
            D.manifest_put(name, st)
        s = M.stats(x, sr)
        w = int(0.25 * sr)
        env = np.sqrt(np.convolve(x * x, np.ones(w) / w, mode="same"))
        late = float(np.argmax(env) / sr)
        print("%-16s %5.2f s %5d Hz  peak %5.1f  M-max %6.1f LUFS  centroid %5.0f Hz  loudest at %.2f s  bands <100/<400/<1.5k/over %s" % (
            name, s["dur"], sr, s["peak"], s["mmax"], s["cent"], late, " ".join("%2.0f" % b for b in bands(x))))
    if WRITE:
        print("wrote %.0f KB" % (total / 1024.0))


if __name__ == "__main__":
    main()
