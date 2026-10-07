#!/usr/bin/env python3
"""The footsteps, the shotgun, the reload and the blows of Thirty Bells (the SOUND pass): mono 16-bit WAVs in assets/audio/, made from arithmetic alone
(NumPy and tools/audio_dsp.py), a fixed seed for each file, so a second run writes the same bytes. Nobody can listen to them where they were made: every
file is checked by number (peak, loudness, length, spectrum, how long the tail is) with tools/audio_measure.py, and the owner's ears come after.

    python3 tools/make_foley_sounds.py             # writes everything and updates assets/audio/audio_manifest.json
    python3 tools/make_foley_sounds.py --check     # renders and prints, writes nothing
    python3 tools/make_foley_sounds.py steps       # one group: steps gun reload melee

    steps   fs_<surface>_0..2 (walking) and fs_<surface>_run_0..1 (running: heavier, harder, a push-off scuff) for the seven grounds the town has:
            grass, dirt, gravel, pave (asphalt and sidewalk), wood (a floor), tile (kitchen, bath, hall), carpet; 22.05 kHz, 0.2 to 0.3 s.
            dead_soft_0..2 / dead_hard_0..2 (the dead's shuffle: a soft foot with a scuff, on earth and carpet / on hard ground) and dead_drag_0..1 (a
            limper: a step and the drag of the other foot, 0.5 s).
    gun     blast_out_0..2 (the pump gun in the open: crack, body, sub thump and a short tail with one slap-back, 0.85 s) and blast_in_0..2 (the same shot
            in a room: the early reflections of walls and a dense tail, 1.1 s); 44.1 kHz. The old shot_shotgun_0..1 stay for the school and the tests.
    reload  shell_load_0..2 (a shell into the tube: the gate's click and the seat, 0.2 s), pump_rack_0..1 (the slide back and forward: chk-CLACK, 0.5 s),
            trigger_click_0..1 (the hammer falling on nothing, 0.12 s); 44.1 kHz. They replace shell_in, pump and dry_click by name (scripts/audio/sound.gd).
    melee   melee_swoosh_0..2 (the blow in the air: a fast rise and a fall, 0.3 s), melee_thud_0..2 (a blow that lands: dull, 0.26 s), melee_kill_0..2
            (a blow that kills: bone, a wet crunch and drops, 0.45 s); 22.05 kHz (the swoosh and the thud 44.1).

Levels are by peak (PEAKS below; nothing is above -3.2 dBFS: tests/test_audio_assets.gd wants -3 or lower for every file in the manifest), and the game's own
gain staging (scripts/audio/foley.gd, scripts/audio/buses.gd TRIM_DB, docs/audio-mix.md) puts each at its place in the mix.
"""
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as D  # noqa: E402
import audio_measure as M  # noqa: E402

WRITE = "--check" not in sys.argv
GROUPS = [a for a in sys.argv[1:] if not a.startswith("--")]

# the peak of each file (dBFS), by stem
PEAKS = {
    "fs_walk": -9.0, "fs_run": -6.0, "dead_soft": -12.0, "dead_hard": -10.0, "dead_drag": -11.0,
    "blast_out": -3.2, "blast_in": -3.2,
    "shell_load": -7.0, "pump_rack": -5.0, "trigger_click": -7.0,
    "melee_swoosh": -9.0, "melee_thud": -6.5, "melee_kill": -5.5,
}
# the blows, the steps and the reload are set by loudness (the loudest 400 ms, K-weighted, mono LUFS) and not by peak: a dull thump has a low peak for its weight, and the
# crisp click of a heel a high one. The numbers are the mix table's file column (docs/audio-mix.md); the game's gain staging and the buses do the rest.
MELEE_LOUD = {"melee_swoosh": -24.0, "melee_thud": -23.0, "melee_kill": -21.0}
STEP_LOUD = {"grass": -32.0, "dirt": -31.0, "gravel": -30.0, "pave": -31.0, "wood": -31.0, "tile": -31.0, "carpet": -33.0}
RUN_EXTRA_LU = 4.0
DEAD_LOUD = {"soft": -34.0, "hard": -32.0, "drag": -30.0}
RELOAD_LOUD = {"shell_load": -25.0, "pump_rack": -22.0, "trigger_click": -25.5}
# a surface's own loudness against the others (dB at the file: a lawn is soft, tile rings)
SURFACE_TRIM = {"grass": -3.0, "dirt": -1.0, "gravel": 0.0, "pave": 0.0, "wood": -0.5, "tile": 0.0, "carpet": -5.0}
SURFACES = ["grass", "dirt", "gravel", "pave", "wood", "tile", "carpet"]


def seed_of(name):
    return zlib.crc32(name.encode("ascii")) & 0x7fffffff


# ------------------------------------------------------------------------------------------------ small tools --

def tt(seconds, sr):
    return np.arange(int(round(seconds * sr))) / sr


def bp(x, lo, hi, sr):
    return D.bandpass(x, lo, hi, sr, 2, circular=False)


def lp(x, fc, sr, order=2):
    return D.lowpass(x, fc, sr, order, circular=False)


def hp(x, fc, sr, order=2):
    return D.highpass(x, fc, sr, order, circular=False)


def mixs(*parts):
    """The parts added up (each may be a different length: the sum is as long as the longest)."""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def put(buf, snd, at, sr, gain=1.0):
    i = int(round(at * sr))
    if i < 0:
        snd = snd[-i:]
        i = 0
    j = min(len(buf), i + len(snd))
    if j > i:
        buf[i:j] += gain * snd[:j - i]


def sweep(sr, seconds, f0, f1, tau, sweep_tau=None, attack=0.002):
    """A sine that falls from f0 to f1 and dies away in `tau`."""
    t = tt(seconds, sr)
    st = sweep_tau if sweep_tau is not None else tau * 0.5
    f = f1 + (f0 - f1) * np.exp(-t / st)
    ph = D.TAU * np.cumsum(f) / sr
    return np.sin(ph) * np.exp(-t / tau) * D.ramp(t, attack)


def burst(n, sr, rng, tau, lo=None, hi=None, rise=0.0003):
    t = np.arange(n) / sr
    x = rng.standard_normal(n) * np.exp(-t / tau) * D.ramp(t, rise)
    if lo is not None and hi is not None:
        x = bp(x, lo, hi, sr)
    elif hi is not None:
        x = lp(x, hi, sr)
    elif lo is not None:
        x = hp(x, lo, sr)
    return x


def modes(sr, seconds, parts, rng):
    """Damped sines: parts = [(hz, gain, tau)]."""
    t = tt(seconds, sr)
    out = np.zeros(len(t))
    for hz, g, tau in parts:
        if hz < sr * 0.45:
            out += g * np.sin(D.TAU * hz * t + rng.uniform(0, D.TAU)) * np.exp(-t / tau)
    return out


def finish(x, sr, peak_db, fade=0.02):
    x = x * D.tail_off(len(x), sr, fade)
    return x / (np.max(np.abs(x)) + 1e-12) * 10.0 ** (peak_db / 20.0)


def lay(x, rms, sr, window=0.1):
    """A layer at a given RMS over its first `window` seconds (so that the shares of a blow are set by what they are, not by how peaky each layer is)."""
    return x / (np.sqrt(np.mean(x[:int(window * sr)] ** 2)) + 1e-12) * rms


def finish_loud(x, sr, target, fade=0.03, ceiling=-3.4):
    """Scales a sound so that its loudest 400 ms is `target` LUFS (mono, K-weighted); a sample over the ceiling is rounded (a soft clip) and it is scaled again."""
    x = x * D.tail_off(len(x), sr, fade)
    for _ in range(6):
        m = float(M.momentary(x, sr).max())
        x = x * 10.0 ** ((target - m) / 20.0)
        if D.peak_db(x) > ceiling:
            x = D.soft_ceiling(x, ceiling)
    return x


def bands(x, sr):
    """The share of the energy (percent) under 150 Hz, 150 to 800, 800 to 3000 and over 3000 Hz."""
    spec = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    tot = max(spec.sum(), 1e-18)
    return [spec[(f >= lo) & (f < hi)].sum() / tot * 100.0 for lo, hi in ((0, 150), (150, 800), (800, 3000), (3000, 40000))]


def t40(x, sr):
    """The seconds until the 10 ms envelope has fallen 40 dB under its peak for good (how long the tail is)."""
    w = max(1, int(0.01 * sr))
    env = np.sqrt(np.convolve(x * x, np.ones(w) / w, mode="same"))
    over = np.where(env > env.max() * 0.01)[0]
    return float(over[-1] / sr) if len(over) else 0.0


# ------------------------------------------------------------------------------------------------ footsteps --

def contact(sr, seconds, kind, rng, hard, soft_attack=0.0):
    """One foot meeting the ground: `hard` 1.0 is a walking foot, more is a running one (heavier thump, a harder click, a longer ring)."""
    n = int(seconds * sr)
    out = np.zeros(n)
    h = hard
    v = rng.uniform(0.92, 1.08)
    if kind == "grass":
        out += sweep(sr, seconds, 115 * v, 68, 0.035 * h ** 0.3, attack=0.004)[:n] * 0.45 * h
        out += burst(n, sr, rng, 0.05, 180, 1100, 0.004) * 0.55 * h
        t = np.arange(n) / sr
        blades = bp(rng.standard_normal(n), 1600, 6500, sr) * D.ramp(t, 0.02) * np.exp(-t / 0.075)
        out += blades * 0.30 * h
    elif kind == "dirt":
        out += sweep(sr, seconds, 135 * v, 80, 0.03, attack=0.003)[:n] * 0.55 * h
        out += burst(n, sr, rng, 0.04, 280, 2000, 0.002) * 0.8 * h
        for _ in range(14):
            at = rng.uniform(0.0, 0.1)
            g = rng.uniform(0.3, 1.0) * np.exp(-at / 0.06)
            gr = burst(int(0.012 * sr), sr, rng, 0.003, 1200, 5200, 0.0003)
            put(out, gr, at, sr, 0.22 * g * h)
    elif kind == "gravel":
        out += sweep(sr, seconds, 150 * v, 95, 0.025, attack=0.003)[:n] * 0.35 * h
        out += burst(n, sr, rng, 0.03, 400, 2600, 0.001) * 0.55 * h
        for _ in range(60):
            at = rng.uniform(0.0, 0.17) ** 1.15
            g = rng.uniform(0.25, 1.0) * np.exp(-at / 0.09)
            gr = burst(int(0.01 * sr), sr, rng, 0.0022, rng.uniform(1800, 3200), rng.uniform(4800, 8000), 0.0002)
            put(out, gr, at, sr, 0.55 * g * h)
    elif kind == "pave":
        out += burst(n, sr, rng, 0.0022, 1800, 7000, 0.0001) * 0.75 * h
        out += burst(n, sr, rng, 0.016, 450, 2400, 0.0004) * 0.6 * h
        out += sweep(sr, seconds, 210 * v, 120, 0.022, attack=0.002)[:n] * 0.4 * h
        out += modes(sr, seconds, [(1250 * v, 0.14, 0.02), (2100, 0.07, 0.012)], rng)[:n] * h
    elif kind == "wood":
        out += modes(sr, seconds, [(118 * v, 1.0, 0.055), (187 * v, 0.7, 0.045), (305, 0.5, 0.032), (470, 0.3, 0.024), (760, 0.12, 0.018)], rng)[:n] * 0.55 * h
        out += burst(n, sr, rng, 0.003, 1400, 5000, 0.0002) * 0.45 * h
        out += burst(n, sr, rng, 0.02, 250, 1500, 0.0005) * 0.4 * h
    elif kind == "tile":
        out += burst(n, sr, rng, 0.0018, 2600, 9000, 0.0001) * 0.9 * h
        out += burst(n, sr, rng, 0.012, 500, 3000, 0.0003) * 0.45 * h
        out += modes(sr, seconds, [(1850 * v, 0.2, 0.024), (2780, 0.14, 0.02), (3650, 0.09, 0.016), (230, 0.35, 0.03)], rng)[:n] * h
    elif kind == "carpet":
        out += sweep(sr, seconds, 92 * v, 62, 0.04, attack=0.005)[:n] * 0.5 * h
        out += burst(n, sr, rng, 0.05, 140, 760, 0.006) * 0.45 * h
        out = lp(out, 1500, sr)
    return out


def make_step(surface, i, run):
    name = "fs_%s_%s%d" % (surface, "run_" if run else "", i)
    rng = np.random.default_rng(seed_of(name))
    sr = 22050
    seconds = 0.30 if run else 0.24
    n = int(seconds * sr)
    out = np.zeros(n)
    hard = 1.55 if run else 1.0
    toe = rng.uniform(0.05, 0.065) if run else rng.uniform(0.075, 0.095)
    put(out, contact(sr, seconds, surface, rng, hard), 0.0, sr, 1.0)
    put(out, contact(sr, seconds - toe, surface, rng, hard * 0.55), toe, sr, 0.6 if not run else 0.75)
    if run:
        # the push-off: a scuff of the sole leaving the ground
        sc = bp(rng.standard_normal(int(0.07 * sr)), 700, 3800, sr) * np.hanning(int(0.07 * sr))
        put(out, sc, toe + 0.025, sr, 0.18 if surface not in ("carpet", "grass") else 0.1)
    if surface == "tile":
        ir = D.reverb_ir(sr, 0.22, np.random.default_rng(seed_of(name) + 1), predelay=0.004, damp=2.0, early=4)
        out = D.with_reverb(out, ir, 0.22)[:n]
    return name, finish_loud(out, sr, STEP_LOUD[surface] + (RUN_EXTRA_LU if run else 0.0), 0.025, ceiling=-6.0), sr


def make_dead(kind, i):
    """kind: soft (earth, carpet), hard (pavement, floors), drag (a limper)."""
    name = "dead_%s_%d" % (kind, i)
    rng = np.random.default_rng(seed_of(name))
    sr = 22050
    seconds = 0.5 if kind == "drag" else 0.34
    n = int(seconds * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    v = rng.uniform(0.9, 1.1)
    # a loose, wet-heavy foot: no click, a low soft thud and the scuff of a toe that is not lifted
    out += sweep(sr, seconds, 100 * v, 60, 0.05, attack=0.006)[:n] * 0.55
    out += burst(n, sr, rng, 0.07, 120, 700, 0.008) * 0.5
    scuff = bp(rng.standard_normal(n), 450, 2600 if kind != "soft" else 1700, sr)
    shape = D.ramp(t - 0.03, 0.09) * np.exp(-(t - 0.03).clip(0) / (0.11 if kind != "drag" else 0.18))
    out += scuff * shape * (0.55 if kind == "soft" else 0.7)
    if kind == "hard":
        out += burst(n, sr, rng, 0.004, 1200, 4000, 0.0004) * 0.18
    if kind == "drag":
        # the other foot is pulled: a long uneven scrape that comes after the step
        sl = bp(rng.standard_normal(n), 300, 2200, sr)
        wob = 0.55 + 0.45 * np.sin(D.TAU * rng.uniform(9, 13) * t + rng.uniform(0, 6.28))
        shape2 = D.ramp(t - 0.11, 0.07) * np.exp(-(t - 0.11).clip(0) / 0.2) * D.ramp(seconds - 0.03 - t, 0.1)
        out += sl * wob * shape2 * 0.9
    return name, finish_loud(out, sr, DEAD_LOUD[kind], 0.04, ceiling=-6.0), sr


# ------------------------------------------------------------------------------------------------ the pump gun --

def make_blast(i, indoor):
    name = "blast_%s_%d" % ("in" if indoor else "out", i)
    rng = np.random.default_rng(seed_of(name))
    sr = 44100
    seconds = 1.15 if indoor else 0.85
    n = int(seconds * sr)
    t = np.arange(n) / sr
    v = rng.uniform(0.94, 1.06)
    # 1. the crack: a hard click and the bright burst of the powder (a few thousandths of a second)
    click = hp(rng.standard_normal(n), 4200, sr) * np.exp(-t / 0.0006)
    click = click / (np.max(np.abs(click)) + 1e-12) * 1.6
    crack = lay(hp(rng.standard_normal(n), 1300, sr) * np.exp(-t / 0.0085 * v) * D.ramp(t, 0.00015), 0.42, sr)
    # 2. the pellets: a spray of hiss that dies in a twentieth of a second
    spray = lay(bp(rng.standard_normal(n), 2600, 9500, sr) * np.exp(-t / 0.045) * D.ramp(t, 0.003), 0.11, sr)
    # 3. the chest: the blast's body between 90 and 900 Hz
    body = lay(bp(rng.standard_normal(n), 90, 900, sr) * np.exp(-t / 0.085) * D.ramp(t, 0.0012), 0.62, sr)
    # 4. the thump under it: a sine that falls from 120 to 38 Hz, with its octave a little
    th = sweep(sr, seconds, 118 * v, 38, 0.1, sweep_tau=0.05, attack=0.0015)[:n]
    th += 0.35 * sweep(sr, seconds, 236 * v, 76, 0.06, sweep_tau=0.035, attack=0.0015)[:n]
    th = lay(th, 0.34, sr)
    dry = click + crack + spray + body + th
    # a hard knee on the click's few samples, so that the body is not left small under it
    pk = np.max(np.abs(dry)) * 0.36
    dry = np.clip(dry, -pk, pk)
    dry = np.tanh(2.2 * dry / pk) * pk
    if not indoor:
        # the open air: a short tail (a low-passed hiss that falls away at once) and one slap back from a house across the street, then a faint far one
        tail = lp(rng.standard_normal(n), 1400, sr) * np.exp(-t / 0.11) * D.ramp(t, 0.01)
        out = dry + tail * np.max(np.abs(dry)) / (np.max(np.abs(tail)) + 1e-9) * 0.3
        for delay, g, fc in ((0.15 + 0.012 * rng.uniform(-1, 1), 0.22, 1800), (0.33, 0.06, 1100)):
            put(out, lp(dry, fc, sr), delay, sr, g)
    else:
        # a room: the walls come back within a few hundredths, and a tail that is dense, dull and a half second long
        ir = D.reverb_ir(sr, 0.5, np.random.default_rng(seed_of(name) + 7), predelay=0.006, damp=2.6, early=9, low_boost=1.1)
        wet = D.convolve(dry, ir)
        wet = wet / (np.sqrt(np.sum(wet ** 2)) + 1e-12) * np.sqrt(np.sum(dry ** 2)) * 1.05
        out = np.zeros(len(wet))
        out[:n] += dry * 0.82
        out += wet * 0.55
        out = out[:n]
    out = finish(out, sr, PEAKS["blast_in" if indoor else "blast_out"], 0.12)
    return name, out, sr


# ------------------------------------------------------------------------------------------------ the reload --

def make_shell_load(i):
    name = "shell_load_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sr = 44100
    n = int(0.22 * sr)
    out = np.zeros(n)
    f = [2150, 2000, 2300][i]
    # the shell's rim on the loading gate: a sharp tick with a ring of brass
    put(out, mixs(burst(n, sr, rng, 0.0016, 1800, 9000, 0.0001) * 0.7, modes(sr, 0.1, [(f, 0.5, 0.012), (f * 1.52, 0.25, 0.008)], rng)), 0.0, sr)
    # the shell going home in the tube and seating: a dull knock with the tube's hollow note
    put(out, mixs(sweep(sr, 0.12, 330, 200, 0.02, attack=0.001) * 0.9, modes(sr, 0.12, [(740 + 40 * i, 0.5, 0.018), (1480, 0.2, 0.01)], rng), burst(int(0.12 * sr), sr, rng, 0.008, 500, 3500, 0.0003) * 0.6), 0.052 + 0.004 * i, sr, 1.0)
    # the gate's spring closing: a tiny late tick
    put(out, burst(int(0.02 * sr), sr, rng, 0.002, 2400, 8000, 0.0001), 0.125, sr, 0.18)
    return name, finish_loud(out, sr, RELOAD_LOUD["shell_load"], 0.03), sr


def make_pump_rack(i):
    name = "pump_rack_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sr = 44100
    n = int(0.52 * sr)
    out = np.zeros(n)
    # chk: the slide unlocks and goes back (a rattle of metal and a short rasp of its travel)
    put(out, mixs(burst(int(0.09 * sr), sr, rng, 0.012, 1100, 6500, 0.0002) * 0.8, modes(sr, 0.09, [(930, 0.5, 0.02), (1860, 0.3, 0.012), (3100, 0.12, 0.01)], rng), sweep(sr, 0.09, 260, 170, 0.014, attack=0.001) * 0.6), 0.0, sr)
    travel = bp(rng.standard_normal(int(0.14 * sr)), 500, 3000, sr) * np.hanning(int(0.14 * sr))
    put(out, travel, 0.07, sr, 0.17)
    # CLACK: the slide comes forward and locks (heavier: the ring of the receiver, a thump, then the lock's tick)
    at = 0.235 + 0.01 * i
    put(out, mixs(burst(int(0.16 * sr), sr, rng, 0.016, 700, 7500, 0.0002) * 1.0, modes(sr, 0.16, [(720, 0.9, 0.03), (1450, 0.6, 0.02), (2800, 0.3, 0.014), (4300, 0.12, 0.01)], rng), sweep(sr, 0.16, 300, 140, 0.03, attack=0.001) * 0.9), at, sr)
    put(out, mixs(burst(int(0.03 * sr), sr, rng, 0.003, 2000, 9000, 0.0001), modes(sr, 0.05, [(2400, 0.6, 0.01)], rng)), at + 0.034, sr, 0.35)
    return name, finish_loud(out, sr, RELOAD_LOUD["pump_rack"], 0.04), sr


def make_trigger_click(i):
    name = "trigger_click_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sr = 44100
    n = int(0.14 * sr)
    out = np.zeros(n)
    # the hammer falls on an empty chamber: a small hard "tk" (metal on metal, bright) and a duller "tok" of the frame
    put(out, mixs(burst(n, sr, rng, 0.0014, 2200, 10000, 0.0001) * 0.8, modes(sr, 0.05, [(1650 + 120 * i, 0.5, 0.01), (3300, 0.2, 0.006)], rng)), 0.0, sr)
    put(out, mixs(sweep(sr, 0.08, 330, 180, 0.012, attack=0.0008) * 0.8, burst(int(0.05 * sr), sr, rng, 0.006, 400, 2200, 0.0002) * 0.5), 0.012, sr, 0.8)
    return name, finish_loud(out, sr, RELOAD_LOUD["trigger_click"], 0.02), sr


# ------------------------------------------------------------------------------------------------ melee --

def make_swoosh(i):
    name = "melee_swoosh_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sr = 44100
    seconds = 0.3
    n = int(seconds * sr)
    t = np.arange(n) / sr
    base = rng.standard_normal(n)
    # a blow is a short, fast rise (the weapon coming up to speed: the pitch of the air climbs from 500 to 3500 Hz in 45 ms) and a fall: the whip of it
    bands = [(300, 800, 0.040), (700, 1700, 0.047), (1500, 3300, 0.052), (3000, 6000, 0.057)]
    out = np.zeros(n)
    peak_t = 0.046 + 0.004 * (i - 1)
    for k, (lo, hi, c) in enumerate(bands):
        c = c + 0.004 * (i - 1)
        rise = np.exp(-((np.minimum(t, c) - c) / (0.014 + 0.003 * k)) ** 2)
        fall_tau = 0.11 - 0.018 * k
        fall = np.exp(-(t - c).clip(0) / fall_tau)
        out += bp(base, lo, hi, sr) * np.where(t < c, rise, fall) * (1.0, 1.0, 0.6, 0.3)[k]
    out *= D.ramp(t, 0.012)
    return name, finish_loud(out, sr, MELEE_LOUD["melee_swoosh"], 0.06), sr


def make_thud(i):
    name = "melee_thud_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sr = 44100
    n = int(0.26 * sr)
    t = np.arange(n) / sr
    v = rng.uniform(0.92, 1.08)
    # a dull blow into a body: a low knock (a sine that falls from 120 to 62 Hz), the flesh's thump between 120 and 900 Hz, a trace of cloth and sinew above
    sub = lay(sweep(sr, 0.26, 120 * v, 62, 0.06, sweep_tau=0.03, attack=0.0015)[:n], 0.22, sr, 0.06)
    flesh = lay(burst(n, sr, rng, 0.04, 120, 900, 0.001), 0.34, sr, 0.06)
    cloth = lay(burst(n, sr, rng, 0.012, 800, 3000, 0.0004), 0.07, sr, 0.06)
    out = lp(sub + flesh + cloth, 3600, sr)
    return name, finish_loud(out, sr, MELEE_LOUD["melee_thud"], 0.04), sr


def make_kill(i):
    name = "melee_kill_%d" % i
    rng = np.random.default_rng(seed_of(name))
    sr = 44100
    n = int(0.46 * sr)
    t = np.arange(n) / sr
    v = rng.uniform(0.9, 1.1)
    sub = lay(sweep(sr, 0.46, 104 * v, 52, 0.07, sweep_tau=0.03, attack=0.0015)[:n], 0.18, sr, 0.06)
    flesh = lay(burst(n, sr, rng, 0.04, 120, 900, 0.001), 0.28, sr, 0.06)
    # the bone: a sharp crack
    bone = lay(burst(n, sr, rng, 0.0045, 1300, 5400, 0.0002), 0.22, sr, 0.06)
    # the wet of it: a squelch, noise that bubbles (a modulation that slows down from 70 to 30 a second) and dies in a tenth of a second or two
    fm = 70.0 - 40.0 * np.minimum(t / 0.2, 1.0)
    bubble = 0.5 + 0.5 * np.sin(D.TAU * np.cumsum(fm) / sr + rng.uniform(0, 6.28))
    wet = lay(bp(rng.standard_normal(n), 300, 2400, sr) * bubble ** 1.5 * np.exp(-t / 0.1) * D.ramp(t, 0.004), 0.38, sr, 0.12)
    out = sub + flesh + bone + wet
    # and the drops after it
    for _ in range(int(rng.integers(4, 8))):
        at = rng.uniform(0.09, 0.38)
        d = burst(int(0.03 * sr), sr, rng, 0.006, rng.uniform(500, 900), rng.uniform(1800, 3200), 0.0004)
        d = d / (np.max(np.abs(d)) + 1e-12)
        put(out, d, at, sr, rng.uniform(0.05, 0.16) * np.exp(-at / 0.25))
    return name, finish_loud(out, sr, MELEE_LOUD["melee_kill"], 0.05), sr


# ------------------------------------------------------------------------------------------------ the files --

def sounds(groups):
    out = []
    want = lambda g: not groups or g in groups  # noqa: E731
    if want("steps"):
        for s in SURFACES:
            for i in range(3):
                out.append(make_step(s, i, False))
            for i in range(2):
                out.append(make_step(s, i, True))
        for kind in ("soft", "hard"):
            for i in range(3):
                out.append(make_dead(kind, i))
        for i in range(2):
            out.append(make_dead("drag", i))
    if want("gun"):
        for i in range(3):
            out.append(make_blast(i, False))
        for i in range(3):
            out.append(make_blast(i, True))
    if want("reload"):
        for i in range(3):
            out.append(make_shell_load(i))
        for i in range(2):
            out.append(make_pump_rack(i))
            out.append(make_trigger_click(i))
    if want("melee"):
        for i in range(3):
            out.append(make_swoosh(i))
            out.append(make_thud(i))
            out.append(make_kill(i))
    return out


def main():
    total = 0
    for name, x, sr in sounds(GROUPS):
        peak = D.peak_db(x)
        assert peak <= -3.0, "%s peaks at %.1f dBFS" % (name, peak)
        if WRITE:
            st = D.save(name, x, sr, kind="sfx", seed=seed_of(name), notes="make_foley_sounds.py")
            total += st["bytes"]
            fs = M.stats_of(os.path.join(D.OUT_DIR, name + ".wav"))    # (what is in the file: the loudest 400 ms and the centroid go into the manifest beside the peak)
            st["mmax_lufs"] = round(fs["mmax"], 1)
            st["centroid_hz"] = round(fs["cent"])
            D.manifest_put(name, st)
        s = M.stats(x, sr)
        print("%-18s %5.2f s %5d Hz  peak %5.1f  M-max %6.1f LUFS  centroid %5.0f Hz  tail(-40 dB) %.2f s  bands %s" % (name, s["dur"], sr, s["peak"], s["mmax"], s["cent"], t40(x, sr), " ".join("%2.0f" % b for b in bands(x, sr))))
    if WRITE:
        print("wrote %.0f KB" % (total / 1024.0))


if __name__ == "__main__":
    main()
