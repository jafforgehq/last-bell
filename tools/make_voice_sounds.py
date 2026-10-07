#!/usr/bin/env python3
"""The voices of Thirty Bells (the SOUND pass): the dead's groans, growls, hiss and screech, the brute's growl, and Ruth's pain and breath. Mono 16-bit
WAVs in assets/audio/, 22.05 kHz, made from arithmetic alone (NumPy, tools/audio_dsp.py, the formant voice in tools/voice_kit.py), a fixed seed for
each, so a second run writes the same bytes. Nobody can listen to them where they were made: each is checked by number (loudness, pitch, spectrum, length)
and the owner's ears come after.

    python3 tools/make_voice_sounds.py             # writes everything and updates assets/audio/audio_manifest.json
    python3 tools/make_voice_sounds.py --check     # renders and prints, writes nothing
    python3 tools/make_voice_sounds.py zombie      # one group: zombie ruth

    zgroan_0..7        a walker's groan, eight shapes (a long low "ooo-awww", a rough "uhhh", a two-part "uh-aaah", a breathy sigh, a gurgle, a rising "oooh",
                       a short "ugh", a wail), 0.7 to 1.6 s, pitch 80 to 140 Hz, a rasp on all of them
    zgroan_far_0..2    three of them as heard from far off: darker (a low-pass at 600 Hz, a room's tail), a little lower, quieter
    zgrowl_0..3        the wind-up growl of the dead before a bite: short (0.3 to 0.45 s), low, rough, a hard start
    zbrute_growl_0..1  the brute's: lower (45 to 60 Hz source), heavier, 0.6 s
    zrun_hiss_0..1     a runner's hiss: breath through the teeth with a rasp under it (0.5 s)
    zrun_screech_0..1  a runner's screech: a voice that climbs from 400 to 900 Hz and breaks (0.55 s)
    ruth_pain_0..3     Ruth hurt (a bite): a gasp and a short voiced "uh" or "ah" (0.3 to 0.45 s), pitch 170 to 250 Hz
    ruth_breath_0..3   Ruth out of breath (the sprint's tank is nearly empty): an in-breath and an out-breath, 0.55 to 0.8 s, close to the microphone and quiet

Each is brought to a loudness (LOUD below, the loudest 400 ms K-weighted, mono, LUFS) rather than a peak: variants of one sound are within a unit or two of
each other, and the game's gain staging (scripts/audio/foley.gd, docs/audio-mix.md) puts each category at its place.
"""
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as D  # noqa: E402
import audio_measure as M  # noqa: E402
import voice_kit as V  # noqa: E402

WRITE = "--check" not in sys.argv
GROUPS = [a for a in sys.argv[1:] if not a.startswith("--")]
SR = 22050
CEILING = -3.4

# the loudest 400 ms momentary loudness of each kind (K-weighted, mono LUFS: at the master, two channels, 3 LU more)
LOUD = {
    "zgroan": -21.0, "zgroan_far": -27.0, "zgrowl": -19.0, "zbrute_growl": -17.0, "zrun_hiss": -24.0, "zrun_screech": -19.0,
    "ruth_pain": -21.0, "ruth_breath": -29.0,
}


def seed_of(name):
    return zlib.crc32(name.encode("ascii")) & 0x7fffffff


def to_loudness(x, sr, target, fade=0.04, ceiling=CEILING):
    """Scales a sound so that its loudest 400 ms is `target` LUFS; if that puts a sample over the ceiling, the peaks are rounded (a soft clip) and it is scaled again."""
    x = x * D.tail_off(len(x), sr, fade)
    for _ in range(6):
        m = float(M.momentary(x, sr).max())
        x = x * 10.0 ** ((target - m) / 20.0)
        if D.peak_db(x) > ceiling:
            x = D.soft_ceiling(x, ceiling)
    return x


def tt(n):
    return np.arange(n) / SR


# ------------------------------------------------------------------------------------------------ the dead --

# name -> (seconds, f0 curve points [(pos, Hz)], vowel path, rasp, breath, attack, release, extra)
GROANS = [
    # a long low "ooo-awww"
    dict(sec=1.55, f0=[(0, 112), (0.25, 104), (0.7, 88), (1, 74)], path=[(0, "oo"), (0.5, "aw"), (1, "aw")], rasp=0.40, breath=0.10, attack=0.22, release=0.5, wob=0.0),
    # a rough "uhhh", with a wobble
    dict(sec=1.15, f0=[(0, 128), (0.2, 122), (1, 90)], path=[(0, "uh"), (1, "uh")], rasp=0.62, breath=0.12, attack=0.10, release=0.34, wob=0.25),
    # a two-part "uh-aaah"
    dict(sec=1.35, f0=[(0, 118), (0.22, 100), (0.38, 112), (0.6, 126), (1, 86)], path=[(0, "uh"), (0.3, "uh"), (0.42, "aa"), (1, "uh")], rasp=0.33, breath=0.10, attack=0.07, release=0.42, wob=0.0),
    # a short "ugh"
    dict(sec=0.72, f0=[(0, 140), (0.15, 124), (1, 82)], path=[(0, "uh"), (1, "uu")], rasp=0.55, breath=0.08, attack=0.03, release=0.22, wob=0.0),
    # a breathy sigh
    dict(sec=1.25, f0=[(0, 98), (0.5, 90), (1, 78)], path=[(0, "aa"), (1, "aw")], rasp=0.30, breath=0.75, attack=0.18, release=0.5, wob=0.0),
    # a rising "oooh" that falls back
    dict(sec=1.45, f0=[(0, 92), (0.4, 128), (0.62, 118), (1, 80)], path=[(0, "oo"), (0.5, "aw"), (1, "uh")], rasp=0.28, breath=0.10, attack=0.2, release=0.5, wob=0.0),
    # a gurgle, fast wobble, raspy
    dict(sec=1.0, f0=[(0, 108), (0.5, 100), (1, 84)], path=[(0, "uh"), (0.5, "ih"), (1, "uh")], rasp=0.70, breath=0.2, attack=0.06, release=0.3, wob=0.55),
    # a wail
    dict(sec=1.6, f0=[(0, 104), (0.3, 138), (0.55, 132), (1, 90)], path=[(0, "aa"), (0.6, "aw"), (1, "oo")], rasp=0.36, breath=0.14, attack=0.16, release=0.55, wob=0.12),
]


def make_groan(i):
    name = "zgroan_%d" % i
    g = GROANS[i]
    rng = np.random.default_rng(seed_of(name))
    n = int(g["sec"] * SR)
    f0 = V.curve(n, g["f0"])
    hold = None
    if g["wob"] > 0.0:
        hold = 1.0 - g["wob"] * (0.5 + 0.5 * np.sin(V.TAU * (9.0 + 3 * i) * tt(n)))
    x = V.voice(SR, g["sec"], f0, g["path"], rng, rasp=g["rasp"], breath_amt=g["breath"], attack=g["attack"], release=g["release"], hold=hold)
    # (a ceiling of -7.5 dBFS: the Voices bus gives 9 dB, and a groan next to the camera must not live on the master's limiter)
    return name, to_loudness(x, SR, LOUD["zgroan"], 0.05, ceiling=-7.5), SR


def make_far(i, src):
    """A groan as it is far away: lower, dull, with the air's room around it."""
    name = "zgroan_far_%d" % i
    _, y, _ = make_groan(src)
    rng = np.random.default_rng(seed_of(name))
    # a little lower (resampled down by 8 percent: a longer, deeper sound), then dull and in a room
    k = 0.92
    yy = np.interp(np.arange(int(len(y) / k)) * k, np.arange(len(y)), y)
    yy = D.lowpass(yy, 620.0, SR, 2, circular=False)
    ir = D.reverb_ir(SR, 0.9, rng, predelay=0.03, damp=3.5, early=5)
    yy = D.with_reverb(yy, ir, 0.38)
    return name, to_loudness(yy, SR, LOUD["zgroan_far"], 0.18), SR


def make_growl(i):
    name = "zgrowl_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sec = [0.34, 0.42, 0.30, 0.38][i]
    n = int(sec * SR)
    f0 = V.curve(n, [(0, [88, 80, 96, 84][i]), (0.4, [76, 70, 82, 74][i]), (1, [62, 58, 66, 60][i])])
    path = [[(0, "uh"), (1, "aw")], [(0, "aw"), (1, "uh")], [(0, "aa"), (1, "aw")], [(0, "uh"), (1, "oo")]][i]
    x = V.voice(SR, sec, f0, path, rng, rasp=0.85, breath_amt=0.22, attack=0.03, release=0.11, rasp_hz=30.0, jitter=0.03, sharp=5.0)
    x = np.tanh(1.8 * x / (np.max(np.abs(x)) + 1e-9))
    return name, to_loudness(x, SR, LOUD["zgrowl"], 0.03), SR


def make_brute_growl(i):
    name = "zbrute_growl_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sec = [0.62, 0.55][i]
    n = int(sec * SR)
    f0 = V.curve(n, [(0, [58, 52][i]), (0.5, [50, 46][i]), (1, [42, 40][i])])
    x = V.voice(SR, sec, f0, [(0, "aw"), (1, "oo")], rng, rasp=0.9, breath_amt=0.25, attack=0.05, release=0.2, rasp_hz=26.0, jitter=0.04, sharp=4.0, scale=0.86)
    x = np.tanh(2.2 * x / (np.max(np.abs(x)) + 1e-9))
    return name, to_loudness(x, SR, LOUD["zbrute_growl"], 0.05), SR


def make_hiss(i):
    name = "zrun_hiss_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sec = 0.55
    n = int(sec * SR)
    t = tt(n)
    # air through the teeth: noise from 3 to 9 kHz that comes in fast and goes out slowly, and a rough low voice under it ("ssaaah")
    sh = D.bandpass(rng.standard_normal(n), 2600 + 300 * i, 9500, SR, 2, circular=False) * D.ramp(t, 0.03) * np.exp(-t / 0.32)
    v = V.voice(SR, sec, V.curve(n, [(0, 210), (0.3, 190), (1, 150)]), [(0, "ah"), (1, "aa")], rng, rasp=0.8, breath_amt=0.3, attack=0.08, release=0.22, rasp_hz=45.0, jitter=0.03)
    x = sh / (np.sqrt(np.mean(sh ** 2)) + 1e-9) + 0.55 * v / (np.sqrt(np.mean(v ** 2)) + 1e-9) * np.exp(-t / 0.4)
    return name, to_loudness(x, SR, LOUD["zrun_hiss"], 0.1), SR


def make_screech(i):
    name = "zrun_screech_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sec = 0.55
    n = int(sec * SR)
    f0 = V.curve(n, [(0, [380, 420][i]), (0.55, [880, 820][i]), (0.8, [760, 900][i]), (1, [560, 600][i])])
    x = V.voice(SR, sec, f0, [(0, "aa"), (0.5, "ah"), (1, "eh")], rng, rasp=0.55, breath_amt=0.25, attack=0.05, release=0.16, rasp_hz=90.0, jitter=0.05, sharp=3.0)
    x = np.tanh(2.4 * x / (np.max(np.abs(x)) + 1e-9))
    return name, to_loudness(x, SR, LOUD["zrun_screech"], 0.06), SR


# ------------------------------------------------------------------------------------------------ Ruth --

def make_pain(i):
    name = "ruth_pain_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sec = [0.34, 0.42, 0.30, 0.45][i]
    n = int(sec * SR)
    t = tt(n)
    f0 = V.curve(n, [(0, [235, 250, 215, 205][i]), (0.25, [225, 235, 210, 195][i]), (1, [175, 185, 170, 160][i])])
    path = [[(0, "uh"), (1, "uh")], [(0, "ah"), (1, "uh")], [(0, "uh"), (1, "aw")], [(0, "aa"), (1, "aw")]][i]
    # a woman's mouth is smaller (formants 1.16 times higher), the cry is tight: little rasp, a hard start, a drop
    x = V.voice(SR, sec, f0, path, rng, rasp=[0.10, 0.12, 0.35, 0.18][i], breath_amt=0.14, attack=0.012, release=0.13, scale=1.16, jitter=0.02, sharp=6.0, hold=np.exp(-t / 0.28))
    # the gasp before it: a short breath in through the teeth
    gasp = D.bandpass(rng.standard_normal(int(0.05 * SR)), 900, 4200, SR, 2, circular=False) * np.hanning(int(0.05 * SR))
    pre = int(0.05 * SR)
    y = np.concatenate([np.zeros(pre), x])
    y[:pre] += gasp / (np.max(np.abs(gasp)) + 1e-9) * np.max(np.abs(x)) * 0.35
    return name, to_loudness(y, SR, LOUD["ruth_pain"], 0.05), SR


def make_ruth_breath(i):
    name = "ruth_breath_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sec = [0.62, 0.7, 0.55, 0.8][i]
    n = int(sec * SR)
    t = tt(n)
    out = np.zeros(n)
    # an in-breath (a rush of air through the mouth, a little higher) and an out-breath (lower, longer, with a trace of voice in it: "haa")
    inn = [0.17, 0.2, 0.15, 0.22][i]
    i0, o0 = 0.03, 0.03 + inn + 0.04
    a = D.bandpass(rng.standard_normal(n), 700, 4600, SR, 2, circular=False)
    b = D.bandpass(rng.standard_normal(n), 450, 3300, SR, 2, circular=False)
    env_in = D.ramp(t - i0, inn * 0.45) * D.ramp(i0 + inn - t, inn * 0.55)
    ex = sec - o0 - 0.02
    env_out = D.ramp(t - o0, ex * 0.25) * D.ramp(o0 + ex - t, ex * 0.6)
    out += a * env_in * 0.8 + b * env_out
    f0 = V.curve(n, [(0, 175), (1, 150)])
    vv = V.voice(SR, sec, f0, [(0, "ah"), (1, "aw")], rng, rasp=0.5, breath_amt=0.0, attack=0.1, release=0.3, scale=1.16)
    out += 0.09 * vv / (np.max(np.abs(vv)) + 1e-9) * np.max(np.abs(b)) * env_out
    return name, to_loudness(out, SR, LOUD["ruth_breath"], 0.06), SR


# ------------------------------------------------------------------------------------------------ the files --

def sounds(groups):
    out = []
    want = lambda g: not groups or g in groups  # noqa: E731
    if want("zombie"):
        for i in range(8):
            out.append(make_groan(i))
        for i, src in enumerate((0, 2, 5)):
            out.append(make_far(i, src))
        for i in range(4):
            out.append(make_growl(i))
        for i in range(2):
            out.append(make_brute_growl(i))
            out.append(make_hiss(i))
            out.append(make_screech(i))
    if want("ruth"):
        for i in range(4):
            out.append(make_pain(i))
            out.append(make_ruth_breath(i))
    return out


def pitch_hz(x, sr):
    """A rough pitch of the loudest 100 ms (autocorrelation between 50 and 600 Hz); 0 if there is none to find."""
    w = int(0.1 * sr)
    e = np.convolve(x * x, np.ones(w), mode="valid")
    s = int(np.argmax(e))
    seg = x[s:s + w]
    seg = seg - np.mean(seg)
    ac = np.correlate(seg, seg, mode="full")[len(seg) - 1:]
    lo, hi = int(sr / 600.0), int(sr / 50.0)
    if hi >= len(ac) or ac[0] <= 0:
        return 0.0
    k = lo + int(np.argmax(ac[lo:hi]))
    return sr / k if ac[k] > 0.2 * ac[0] else 0.0


def main():
    total = 0
    for name, x, sr in sounds(GROUPS):
        peak = D.peak_db(x)
        assert peak <= -3.0, "%s peaks at %.1f dBFS" % (name, peak)
        if WRITE:
            st = D.save(name, x, sr, kind="sfx", seed=seed_of(name), notes="make_voice_sounds.py")
            total += st["bytes"]
            fs = M.stats_of(os.path.join(D.OUT_DIR, name + ".wav"))    # (what is in the file: the loudest 400 ms and the centroid go into the manifest beside the peak)
            st["mmax_lufs"] = round(fs["mmax"], 1)
            st["centroid_hz"] = round(fs["cent"])
            D.manifest_put(name, st)
        s = M.stats(x, sr)
        print("%-18s %5.2f s %5d Hz  peak %5.1f  M-max %6.1f LUFS  centroid %5.0f Hz  pitch %4.0f Hz" % (name, s["dur"], sr, s["peak"], s["mmax"], s["cent"], pitch_hz(x, sr)))
    if WRITE:
        print("wrote %.0f KB" % (total / 1024.0))


if __name__ == "__main__":
    main()
