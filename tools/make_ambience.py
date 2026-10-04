#!/usr/bin/env python3
"""The ambience and the voices of the dead for Thirty Bells: mono 16-bit WAVs in assets/audio/, made from arithmetic alone (NumPy
and tools/audio_dsp.py), a fixed seed for each, so a second run writes the same bytes.

    python3 tools/make_ambience.py            # writes everything below and updates audio_manifest.json
    python3 tools/make_ambience.py --check    # renders and prints, writes nothing
    python3 tools/make_ambience.py groans     # one group: loops groans brute far

LOOPS (16 kHz, seamless: every component is circular, every modulation has a whole number of cycles over the file)
    wind_loop.wav       20 s   the day wind: a warm low bed, a mid whoosh that gusts, a very faint whistle
    night_bed.wav       20 s   the cold night: a steady sub rumble, a hollow howl whose pitch drifts, a thin hiss of air
    rain_loop.wav       12 s   rain on a roof and on the ground: a hiss of drops with sparse louder ones
    moan_loop.wav       12 s   the horde's moan, a crowd of low groans far enough to blur (replaces the baked one)
    generator_loop.wav   4 s   a generator: a 50 Hz hum with an engine's rough pulse
    radio_loop.wav       6 s   a radio desk: a radio left on, static and the odd pop

THE DEAD (16 kHz mono, one voice each, the groan of a person who no longer breathes: a glottal buzz with moving vowel formants,
vibrato and a pitch glide, a rough growl and breath; played with a random pitch, so eight variants make a crowd)
    groan_0..3.wav (the files the map data names) and groan_4..7.wav (added by scripts/audio/sound.gd)
    brute_roar_0..1.wav 22.05 kHz  the plated brute's bellow: 60 to 110 Hz fundamental, distorted, with a chest thump

FAR AWAY (16 kHz one-shots for the Distant bus: a lowpass and a reverb on the bus make them far; they are dull already)
    crow_0..2.wav  dog_far_0..1.wav  creak_0..1.wav  moan_far_0..1.wav  gunshot_far_0..1.wav
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as D  # noqa: E402

WRITE = "--check" not in sys.argv
SR = 16000

# vowel formants (F1, F2, F3) in Hz: the mouth shapes of a groan
VOWEL = {
    "u": (300.0, 870.0, 2240.0),
    "o": (450.0, 800.0, 2830.0),
    "aw": (570.0, 840.0, 2410.0),
    "ah": (730.0, 1090.0, 2440.0),
    "uh": (640.0, 1190.0, 2390.0),
    "e": (500.0, 1500.0, 2500.0),
    "ae": (660.0, 1720.0, 2410.0),
}


def path(n, sr, keys):
    """A smooth curve through (time fraction, value) keys, `n` samples."""
    xs = np.array([k[0] for k in keys])
    ys = np.array([k[1] for k in keys])
    x = np.arange(n) / max(n - 1, 1)
    y = np.interp(x, xs, ys)
    return D.smooth(y, 0.05, sr)


def voice(n, sr, rng, f0_t, vowels, bw=(90.0, 120.0, 180.0), tilt=-1.4, rough=0.3, rough_hz=30.0, breath=0.15, jitter=0.01, env=None,
          drive=1.0, max_hz=5000.0):
    """A glottal buzz through moving formants. f0_t: the fundamental over time (Hz, an array); vowels: [(time fraction, vowel
    name)] the mouth passes through; `rough` is how deeply a growl at `rough_hz` chops the voice, `breath` the share of noise,
    `jitter` a wander of the pitch."""
    t = np.arange(n) / sr
    wander = D.lowpass(rng.standard_normal(n), 14.0, sr, 2, circular=False)
    wander = wander / (np.std(wander) + 1e-9) * jitter
    f = f0_t * (1.0 + wander)
    phase = D.TAU * np.cumsum(f) / sr
    # the formant tracks
    keys = [(fr, VOWEL[v]) for fr, v in vowels]
    tracks = [path(n, sr, [(fr, F[i]) for fr, F in keys]) for i in range(3)]
    out = np.zeros(n)
    kmax = int(min(max_hz, sr * 0.45) / max(np.min(f), 1.0))
    for k in range(1, kmax + 1):
        fk = k * f
        amp = k ** tilt * (fk < min(max_hz, sr * 0.45))
        form = np.zeros(n)
        for i, g in enumerate((1.0, 0.7, 0.35)):
            half = bw[i] / 2.0
            form += g / (1.0 + ((fk - tracks[i]) / half) ** 2)
        out += amp * form * np.sin(k * phase + rng.uniform(0, D.TAU))
    out /= np.max(np.abs(out)) + 1e-9
    if rough > 0:
        chop = 1.0 - rough * (0.5 + 0.5 * np.sin(D.TAU * rough_hz * (1.0 + 0.2 * wander / (jitter + 1e-9)) * t + 1.0)) ** 1.5
        out = out * chop
    if breath > 0:
        nz = rng.standard_normal(n)
        shaped = np.zeros(n)
        for i, g in enumerate((1.0, 0.8, 0.4)):
            shaped += g * D.bandpass(nz, float(np.mean(tracks[i])) * 0.8, float(np.mean(tracks[i])) * 1.3, sr, 2, circular=False)
        shaped /= np.max(np.abs(shaped)) + 1e-9
        out = out + breath * shaped * (0.4 + 0.6 * np.abs(out))
    if env is not None:
        out = out * env
    if drive > 1.0:
        out = np.tanh(out * drive) / np.tanh(drive)
    return out / (np.max(np.abs(out)) + 1e-9)


def env_shape(n, sr, attack, release, humps=1, hump_depth=0.0, sustain_decay=0.0):
    """Attack, a body that may have `humps` swells and a slow droop, a release."""
    t = np.arange(n) / sr
    dur = n / sr
    e = D.ramp(t, attack) * D.ramp(dur - t, release)
    if humps > 1:
        e *= 1.0 - hump_depth * (0.5 + 0.5 * np.cos(D.TAU * humps * t / dur))
    if sustain_decay:
        e *= np.exp(-t * sustain_decay)
    return e


# name: (seconds, f0 keys (time fraction, semitones from the start pitch), start pitch Hz, vowels, voice options)
GROANS = {
    "groan_0": (1.50, [(0, 0), (0.15, 0.6), (0.5, 0.0), (0.8, -1.8), (1, -4.0)], 118.0, [(0, "u"), (0.35, "uh"), (0.75, "aw"), (1, "o")], dict(rough=0.35, breath=0.20)),
    "groan_1": (1.10, [(0, 0), (0.2, 1.0), (0.5, 0.2), (1, -4.5)], 130.0, [(0, "ah"), (0.5, "aw"), (1, "u")], dict(rough=0.25, breath=0.18)),
    "groan_2": (0.70, [(0, 0), (0.3, -0.5), (1, -2.5)], 105.0, [(0, "uh"), (1, "uh")], dict(rough=0.40, breath=0.60)),
    "groan_3": (1.40, [(0, 0), (0.4, 2.8), (0.65, 3.2), (1, -2.0)], 100.0, [(0, "u"), (0.3, "o"), (0.6, "ah"), (1, "aw")], dict(rough=0.30, breath=0.22)),
    "groan_4": (1.00, [(0, 0), (0.3, -0.8), (0.5, 0.4), (1, -3.0)], 112.0, [(0, "uh"), (0.45, "u"), (0.55, "uh"), (1, "aw")], dict(rough=0.40, breath=0.30, humps=2, hump_depth=0.75)),
    "groan_5": (1.20, [(0, 0), (0.4, -1.0), (1, -3.5)], 90.0, [(0, "aw"), (1, "uh")], dict(rough=0.60, breath=0.80, drive=1.8)),
    "groan_6": (1.30, [(0, 0), (0.3, 1.2), (0.7, 0.4), (1, -1.5)], 170.0, [(0, "u"), (0.4, "o"), (1, "u")], dict(rough=0.15, breath=0.25)),
    "groan_7": (0.45, [(0, 0), (1, -2.0)], 95.0, [(0, "uh"), (1, "aw")], dict(rough=0.30, breath=0.55)),
}


def make_groan(name, seed, sr=SR):
    secs, keys, f_start, vowels, opts = GROANS[name]
    rng = np.random.default_rng(seed)
    n = int(secs * sr)
    st = path(n, sr, keys)
    t = np.arange(n) / sr
    vib = 1.0 + 0.012 * np.sin(D.TAU * rng.uniform(4.2, 5.6) * t + rng.uniform(0, D.TAU)) * D.ramp(t - 0.15, 0.5)
    f0 = f_start * 2.0 ** (st / 12.0) * vib
    humps = opts.pop("humps", 1)
    depth = opts.pop("hump_depth", 0.0)
    env = env_shape(n, sr, 0.10, 0.35, humps, depth)
    y = voice(n, sr, rng, f0, vowels, env=env, **opts)
    return y


def save(name, y, sr, seed, loop=False, kind="sfx", notes="", peak_db=-9.0, rms_db=None):
    if rms_db is not None:
        y = y / (np.sqrt(np.mean(y ** 2)) + 1e-12) * 10.0 ** (rms_db / 20.0)
        y = D.soft_ceiling(y, peak_db)
    else:
        y = y / (np.max(np.abs(y)) + 1e-9) * 10.0 ** (peak_db / 20.0)
    st = D.save(name, y, sr, loop=loop, kind=kind, seed=seed, notes=notes) if WRITE else {
        "file": name + ".wav", "rate": sr, "seconds": len(y) / sr, "peak_db": D.peak_db(y), "rms_db": D.rms_db(y), "clipped": 0,
        "seam": D.seam_ratio(y) if loop else None, "bytes": len(y) * 2}
    D.report(st)
    return st


# ------------------------------------------------------------------------------------------------ loops

def gust(n, sr, seconds, cycles, phases, depth):
    """A slow 0..1 gust pattern with whole cycles over the loop."""
    t = np.arange(n) / sr
    g = np.zeros(n)
    for c, p in zip(cycles, phases):
        g += np.sin(D.TAU * c / seconds * t + p)
    g = g / len(cycles)
    return 1.0 - depth + depth * (0.5 + 0.5 * g)


def wind():
    secs = 20.0
    n = int(secs * SR)
    rng = np.random.default_rng(201)
    low = D.bandpass(rng.standard_normal(n), 60.0, 220.0, SR, 2) * gust(n, SR, secs, (1, 2, 3), (0.3, 1.9, 4.0), 0.55)
    mid = D.bandpass(rng.standard_normal(n), 250.0, 800.0, SR, 2) * gust(n, SR, secs, (2, 3, 5), (2.1, 0.4, 5.1), 0.8) * 0.7
    whoosh = D.bandpass(rng.standard_normal(n), 900.0, 2200.0, SR, 2) * gust(n, SR, secs, (3, 5, 7), (1.0, 3.3, 0.2), 0.95) ** 2 * 0.28
    whistle = D.bandpass(rng.standard_normal(n), 1100.0, 1260.0, SR, 3) * gust(n, SR, secs, (4, 6), (0.7, 2.2), 1.0) ** 3 * 0.05
    y = (low + mid + whoosh + whistle)
    return save("wind_loop", y - np.mean(y), SR, 201, loop=True, kind="ambience", notes="the day wind", peak_db=-19.0, rms_db=-31.0)


def night_bed():
    secs = 20.0
    n = int(secs * SR)
    rng = np.random.default_rng(211)
    sub = D.bandpass(rng.standard_normal(n), 30.0, 110.0, SR, 3) * (0.8 + 0.2 * D.swell_cycles(n, SR, secs, 2))
    # a hollow howl whose pitch drifts: two narrow bands crossfaded by a slow swell
    h1 = D.bandpass(rng.standard_normal(n), 330.0, 430.0, SR, 3)
    h2 = D.bandpass(rng.standard_normal(n), 470.0, 620.0, SR, 3)
    cross = D.swell_cycles(n, SR, secs, 2, 0.8)
    howl = (h1 * (1.0 - cross) + h2 * cross) * gust(n, SR, secs, (1, 3), (0.5, 3.0), 0.9) ** 2 * 0.75
    air = D.bandpass(rng.standard_normal(n), 2500.0, 5200.0, SR, 2) * gust(n, SR, secs, (2, 5), (2.0, 0.1), 0.8) * 0.10
    y = sub + howl + air
    return save("night_bed", y - np.mean(y), SR, 211, loop=True, kind="ambience", notes="the cold night", peak_db=-21.0, rms_db=-33.0)


def rain():
    secs = 12.0
    n = int(secs * SR)
    rng = np.random.default_rng(221)
    hiss = D.bandpass(D.colored(n, rng, -0.8, SR), 450.0, 6500.0, SR, 2)
    drops = np.zeros(n)
    for _ in range(int(secs * 70)):
        i = int(rng.integers(0, n))
        m = int(0.012 * SR)
        d = D.bandpass(rng.standard_normal(m), 1800.0, 5500.0, SR, 2, circular=False) * np.exp(-np.arange(m) / SR / 0.003) * rng.uniform(0.2, 0.7)
        j = min(n - i, m)
        drops[i:i + j] += d[:j]
        if j < m:
            drops[:m - j] += d[j:]
    big = np.zeros(n)
    for _ in range(int(secs * 7)):
        i = int(rng.integers(0, n))
        m = int(0.05 * SR)
        d = D.bandpass(rng.standard_normal(m), 700.0, 2600.0, SR, 2, circular=False) * np.exp(-np.arange(m) / SR / 0.015) * rng.uniform(0.5, 1.0)
        j = min(n - i, m)
        big[i:i + j] += d[:j]
        if j < m:
            big[:m - j] += d[j:]
    mod = 1.0 + 0.12 * np.sin(D.TAU * 2 / secs * np.arange(n) / SR + 1.0)
    y = (hiss / (np.std(hiss) + 1e-9) * 0.6 + drops / (np.std(drops) + 1e-9) * 0.35 + big / (np.std(big) + 1e-9) * 0.28) * mod
    return save("rain_loop", y - np.mean(y), SR, 221, loop=True, kind="ambience", notes="rain", peak_db=-20.0, rms_db=-32.0)


def moan_crowd():
    secs = 12.0
    n = int(secs * SR)
    rng = np.random.default_rng(231)
    buf = np.zeros(n)
    names = list(GROANS)
    for k in range(11):
        nm = names[int(rng.integers(0, len(names)))]
        g = make_groan(nm, 300 + k)
        rate = rng.uniform(0.78, 1.0)       # lower, slower: a far crowd is a murmur
        m = int(len(g) / rate)
        g = np.interp(np.arange(m) * rate, np.arange(len(g)), g)
        at = int(rng.uniform(0, secs) * SR)
        gain = rng.uniform(0.4, 1.0)
        j = min(n - at, m)
        buf[at:at + j] += g[:j] * gain
        if j < m:
            buf[:m - j] += g[j:] * gain
    buf = D.lowpass(buf, 1500.0, SR, 2)
    ir = D.reverb_ir(SR, 2.2, rng)
    buf = D.with_reverb(buf, ir, 0.35, circular=True)
    buf = D.highpass(buf, 60.0, SR, 2)
    return save("moan_loop", buf - np.mean(buf), SR, 231, loop=True, kind="ambience", notes="the horde's moan", peak_db=-12.0, rms_db=-24.0)


def generator():
    secs = 4.0
    sr = SR
    n = int(secs * sr)
    t = np.arange(n) / sr
    rng = np.random.default_rng(241)
    hum = sum(a * np.sin(D.TAU * round(50.0 * k * secs) / secs * t + rng.uniform(0, D.TAU)) for k, a in enumerate((1.0, 0.55, 0.3, 0.18, 0.1), start=1))
    # the engine's firing: a pulse a whole number of times in the loop
    pulses = 25.0
    ph = (t * pulses) % 1.0
    firing = np.exp(-ph * 14.0) * (0.6 + 0.4 * np.sin(D.TAU * 2 / secs * t))
    rough = D.lowpass(rng.standard_normal(n), 400.0, sr, 2) * firing * 0.8
    pulse_tone = np.sin(D.TAU * round(90.0 * secs) / secs * t) * firing
    y = hum * 0.5 + rough * 0.9 + pulse_tone * 0.6 + D.bandpass(rng.standard_normal(n), 800.0, 3000.0, sr, 2) * 0.03
    return save("generator_loop", y - np.mean(y), sr, 241, loop=True, kind="ambience", notes="the generator", peak_db=-14.0, rms_db=-28.0)


def radio():
    secs = 6.0
    n = int(secs * SR)
    rng = np.random.default_rng(251)
    hiss = D.bandpass(rng.standard_normal(n), 500.0, 3800.0, SR, 2) * (0.6 + 0.4 * D.swell_cycles(n, SR, secs, 3, 0.4))
    # a faint carrier whine and the odd pop
    t = np.arange(n) / SR
    whine = np.sin(D.TAU * round(1175.0 * secs) / secs * t) * 0.03 * D.swell_cycles(n, SR, secs, 2)
    pops = np.zeros(n)
    for _ in range(14):
        i = int(rng.integers(0, n))
        m = int(rng.uniform(0.004, 0.02) * SR)
        p = D.highpass(rng.standard_normal(m), 600.0, SR, 2, circular=False) * np.exp(-np.arange(m) / m * 5.0) * rng.uniform(0.5, 1.6)
        j = min(n - i, m)
        pops[i:i + j] += p[:j]
    y = hiss / (np.std(hiss) + 1e-9) + whine * 4.0 + pops * 3.0
    y = D.bandpass(y, 300.0, 4200.0, SR, 2)
    return save("radio_loop", y - np.mean(y), SR, 251, loop=True, kind="ambience", notes="a radio left on", peak_db=-16.0, rms_db=-30.0)


# ------------------------------------------------------------------------------------------------ the dead

def groans():
    # the files the map data names (groan_0..3) and four more
    for k, name in enumerate(GROANS):
        y = make_groan(name, 400 + k)
        save(name, y, SR, 400 + k, kind="groan", notes="a groan", peak_db=-9.0)


def brute():
    sr = 22050
    for k, (secs, f_from, f_to, seed) in enumerate(((2.0, 105.0, 66.0, 501), (1.6, 118.0, 74.0, 502))):
        rng = np.random.default_rng(seed)
        n = int(secs * sr)
        t = np.arange(n) / sr
        f0 = f_to + (f_from - f_to) * (0.15 * np.exp(-t / 0.06) + 0.85 * (1.0 - D.ramp(t, secs * 0.95)))
        f0 = f0 * (1.0 + 0.02 * np.sin(D.TAU * 5.0 * t))
        env = D.ramp(t, 0.035) * (0.75 + 0.25 * D.ramp(t, 0.5)) * D.ramp(secs - t, 0.7)
        vowels = [(0, "aw"), (0.18, "ah"), (0.55, "aw"), (1, "o")]
        y = voice(n, sr, rng, f0, vowels, bw=(150.0, 200.0, 300.0), tilt=-1.0, rough=0.55, rough_hz=21.0, breath=0.28, jitter=0.02, env=env, drive=3.2, max_hz=6000.0)
        sub = np.sin(D.TAU * np.cumsum(f0 * 0.5) / sr) * env * 0.35
        thump = np.sin(D.TAU * np.cumsum(f_to * (1.0 + 1.2 * np.exp(-t / 0.05))) / sr) * np.exp(-t / 0.12) * D.ramp(t, 0.003) * 0.9
        y = np.tanh(1.6 * (y + sub + thump))
        y = D.lowpass(y, 5500.0, sr, 2, circular=False)
        ir = D.reverb_ir(sr, 1.4, rng)
        y = D.with_reverb(y, ir, 0.22, circular=False)[:n]
        y *= D.tail_off(len(y), sr, 0.4)
        save("brute_roar_%d" % k, y, sr, seed, kind="groan", notes="the plated brute's bellow", peak_db=-4.0)


# ------------------------------------------------------------------------------------------------ far away

def far_chain(y, sr, rng, lp, rt60, wet, tail=0.6):
    y = D.lowpass(y, lp, sr, 2, circular=False)
    ir = D.reverb_ir(sr, rt60, rng)
    return D.with_reverb(y, ir, wet, circular=False)


def far():
    sr = SR
    # --- crows: two or three harsh caws
    for k, (seed, count) in enumerate(((601, 3), (602, 2), (603, 3))):
        rng = np.random.default_rng(seed)
        total = np.zeros(int(1.7 * sr))
        at = 0.05
        for c in range(count):
            m = int(rng.uniform(0.22, 0.32) * sr)
            tt = np.arange(m) / sr
            f0 = rng.uniform(430.0, 560.0) * (1.0 - 0.22 * D.ramp(tt, tt[-1]))
            env = D.ramp(tt, 0.02) * D.ramp(tt[-1] - tt, 0.09) * (0.8 + 0.2 * np.sin(D.TAU * 10 * tt))
            caw = voice(m, sr, rng, f0, [(0, "ae"), (1, "ah")], bw=(160.0, 300.0, 500.0), tilt=-0.7, rough=0.5, rough_hz=95.0, breath=0.30, jitter=0.01, env=env, drive=1.6)
            i = int(at * sr)
            total[i:i + m] += caw[:len(total) - i]
            at += rng.uniform(0.34, 0.5)
        y = far_chain(total, sr, rng, 3200.0, 1.2, 0.25)
        y = D.highpass(y, 250.0, sr, 2, circular=False) * D.tail_off(len(y), sr, 0.4)
        save("crow_%d" % k, y, sr, seed, kind="far", notes="a crow, far", peak_db=-12.0)
    # --- a far dog: a few barks
    for k, (seed, count) in enumerate(((611, 3), (612, 2))):
        rng = np.random.default_rng(seed)
        total = np.zeros(int(1.5 * sr))
        at = 0.05
        for c in range(count):
            m = int(rng.uniform(0.13, 0.19) * sr)
            tt = np.arange(m) / sr
            f0 = rng.uniform(300.0, 370.0) * (1.0 - 0.38 * D.ramp(tt, tt[-1]))
            env = D.ramp(tt, 0.006) * np.exp(-tt / 0.07) * D.ramp(tt[-1] - tt, 0.03)
            bark = voice(m, sr, rng, f0, [(0, "ae"), (1, "aw")], bw=(140.0, 260.0, 400.0), tilt=-1.0, rough=0.2, rough_hz=60.0, breath=0.4, jitter=0.02, env=env, drive=1.5)
            i = int(at * sr)
            total[i:i + m] += bark[:len(total) - i]
            at += rng.uniform(0.3, 0.45)
        y = far_chain(total, sr, rng, 2400.0, 1.6, 0.4)
        y = D.highpass(y, 180.0, sr, 2, circular=False) * D.tail_off(len(y), sr, 0.5)
        save("dog_far_%d" % k, y, sr, seed, kind="far", notes="a dog, far", peak_db=-12.0)
    # --- a creak of wood or a hinge
    for k, seed in enumerate((621, 622)):
        rng = np.random.default_rng(seed)
        secs = 1.2
        n = int(secs * sr)
        t = np.arange(n) / sr
        wander = D.lowpass(rng.standard_normal(n), 6.0, sr, 2, circular=False)
        wander = wander / (np.std(wander) + 1e-9)
        f0 = (170.0 + 60.0 * k) * (1.0 + 0.25 * wander) * (1.0 + 0.3 * D.ramp(t, secs))
        env = D.ramp(t, 0.12) * D.ramp(secs - t, 0.35) * (0.7 + 0.3 * D.lowpass(rng.standard_normal(n), 30.0, sr, 2, circular=False) * 4.0)
        y = voice(n, sr, rng, f0, [(0, "e"), (1, "ae")], bw=(180.0, 260.0, 400.0), tilt=-0.6, rough=0.75, rough_hz=48.0, breath=0.05, jitter=0.05, env=np.clip(env, 0, 1), drive=2.0)
        y = D.bandpass(y, 500.0, 2800.0, sr, 2, circular=False)
        save("creak_%d" % k, y, sr, seed, kind="far", notes="wood creaking", peak_db=-12.0)
    # --- the far moan of the dead
    for k, (name, seed) in enumerate((("groan_0", 631), ("groan_3", 632))):
        rng = np.random.default_rng(seed)
        g = make_groan(name, seed)
        g = np.interp(np.arange(int(len(g) / 0.85)) * 0.85, np.arange(len(g)), g)
        y = far_chain(np.concatenate([g, np.zeros(int(0.4 * sr))]), sr, rng, 1100.0, 2.6, 0.55)
        y = D.highpass(y, 70.0, sr, 2, circular=False) * D.tail_off(len(y), sr, 0.8)
        save("moan_far_%d" % k, y, sr, seed, kind="far", notes="a far moan", peak_db=-12.0)
    # --- a far gunshot with its echoes (the night's shots in the town): one, and two
    for k, (seed, shots) in enumerate(((641, (0.0,)), (642, (0.0, 0.62)))):
        rng = np.random.default_rng(seed)
        total = np.zeros(int(3.2 * sr))
        for at in shots:
            m = int(0.3 * sr)
            tt = np.arange(m) / sr
            crack = D.highpass(rng.standard_normal(m), 900.0, sr, 2, circular=False) * np.exp(-tt / 0.006)
            body = D.lowpass(rng.standard_normal(m), 500.0, sr, 2, circular=False) * np.exp(-tt / 0.045) * 1.6
            shot = crack + body
            i = int((0.05 + at) * sr)
            total[i:i + m] += shot[:len(total) - i] / (np.max(np.abs(shot)) + 1e-9)
        y = far_chain(total, sr, rng, 1700.0, 2.6, 0.6)
        # slap echoes off the far houses
        for gap, g in ((0.42, 0.35), (0.97, 0.18)):
            i = int(gap * sr)
            y[i:] += D.lowpass(y[:len(y) - i], 900.0, sr, 2, circular=False) * g
        y = D.highpass(y, 60.0, sr, 2, circular=False)[:int(3.2 * sr)] * D.tail_off(int(3.2 * sr), sr, 1.0)
        save("gunshot_far_%d" % k, y, sr, seed, kind="far", notes="a far gunshot and its echo", peak_db=-12.0)


GROUPS = {"loops": lambda: (wind(), night_bed(), rain(), moan_crowd(), generator(), radio()), "groans": groans, "brute": brute, "far": far}

if __name__ == "__main__":
    which = [a for a in sys.argv[1:] if not a.startswith("--")] or list(GROUPS)
    for g in which:
        GROUPS[g]()
