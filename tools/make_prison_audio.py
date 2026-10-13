#!/usr/bin/env python3
"""The sound and atmosphere of the prison game (Round 12): mono 16-bit WAVs in assets/audio/prison/, made from arithmetic alone
(NumPy and tools/audio_dsp.py, the voice of tools/make_ambience.py), a fixed seed for each, so a second run writes the same bytes.
No samples, no downloads, no services. Python 3 and NumPy only.

    python3 tools/make_prison_audio.py            # everything below; writes assets/audio/prison/audio_manifest.json
    python3 tools/make_prison_audio.py music      # one group: music stingers ambience foley barks tails

MUSIC (16 kHz, 60 bpm, D minor; loops whose every voice is circular, so the join is silent; the stems of one family are the same
length and are started together by scripts/prison/prison_audio.gd)
    pm_drone 16 s   pm_motif 32 s   pm_drip 16 s   pm_pulse 16 s   pm_perc 16 s   pm_danger 16 s
    pm_explore 32 s (A dorian, the clear phase)   pm_raid 16 s   pm_chase 16 s (120 bpm)
    stingers: pst_fall (a segment falls), pst_death (a dark swell), pst_dawn (the relief)
AMBIENCE (16 kHz loops): pa_rain_roof, pa_rain_concrete, pa_rain_grass, pa_wind_low, pa_wind_gust, pa_fire, pa_buzz, pa_room, pa_flutter, pa_static
    and one-shots pa_clatter_0..2 (the canteen), pa_owl_0..1
FOLEY (22.05 kHz): steps in mud, the dead's shuffle and drag, cell doors, the gate's chain, the rolling door, searching, the backpack, the belt,
    the saw and the drill, the chime of a finished project, the warning, the alarm, a heartbeat, wood hits, a shell going in, the pump, a death rattle
TAILS: pt_tail_0..2 the echo of a pistol, a rifle and a shotgun off the compound's walls
BARKS: pv_<male|female|old>_<grunt|gasp|cough|effort|pain|sob|whistle>
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as D  # noqa: E402
import make_ambience as MA  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "prison")
os.makedirs(OUT, exist_ok=True)
MR = 16000
SR = 22050
TAU = D.TAU
HZ = D.hz


def snap(f, secs):
    """A frequency with a whole number of cycles in `secs` (a sustained voice in a loop then closes exactly)."""
    return round(f * secs) / secs


def fin(name, y, sr, seed, loop=False, kind="sfx", notes="", peak=-9.0, rms=None):
    """Level and write. A loop is levelled by its RMS (what it sounds like); a one-shot by its peak."""
    y = np.asarray(y, dtype=np.float64)
    if loop:
        y = y - np.mean(y)
    if rms is not None:
        y = y / (np.sqrt(np.mean(y ** 2)) + 1e-12) * 10.0 ** (rms / 20.0)
        y = D.soft_ceiling(y, -1.0)
    else:
        y = y / (np.max(np.abs(y)) + 1e-12) * 10.0 ** (peak / 20.0)
    st = D.save(name, y, sr, loop=loop, kind=kind, seed=seed, notes=notes, out_dir=OUT)
    D.report(st)
    return st


def room(x, sr, rt, wet, seed, circular=False):
    ir = D.reverb_ir(sr, rt, np.random.default_rng(seed))
    return D.with_reverb(x, ir, wet, circular=circular)


def saw(f, t, top=3000.0, rolloff=1.2, rng=None):
    out = np.zeros(len(t))
    k = 1
    while k * f < top and k < 90:
        out += np.sin(TAU * k * f * t + (rng.uniform(0, TAU) if rng is not None else 0.0)) / k ** rolloff
        k += 1
    return out


def bass(f, dur, sr, rng, tau=0.3, top=900.0):
    t = np.arange(int(dur * sr)) / sr
    return saw(f, t, top, 1.0, rng) * np.exp(-t / tau) * D.ramp(t, 0.006) * D.ramp(dur - t, 0.03)


def clicks(n, sr, rng, rate, lo, hi, tau, amp_sigma=0.8):
    """Short damped ticks scattered over a loop (drops, crackle): wrap round the end."""
    L = D.Loop(n / sr, sr, int(rng.integers(1 << 30)))
    m = int(tau * 7 * sr)
    t = np.arange(m) / sr
    for _ in range(int(rate * n / sr)):
        f = rng.uniform(lo, hi)
        a = rng.lognormal(0.0, amp_sigma)
        L.add(rng.uniform(0, n / sr), np.sin(TAU * f * t + rng.uniform(0, TAU)) * np.exp(-t / tau), a)
    return L.buf


def slow(n, sr, secs, rng, depth, k=3):
    """A slow wander with whole cycles over `secs` (a loop's own breathing): 1 +- depth."""
    t = np.arange(n) / sr
    m = np.zeros(n)
    for c in rng.choice(np.arange(1, 7), size=k, replace=False):
        m += np.sin(TAU * c / secs * t + rng.uniform(0, TAU)) / k
    return 1.0 + depth * m


# ------------------------------------------------------------------------------------------------ MUSIC

def m_drone():
    L = D.Loop(16, MR, 101)
    r = L.rng
    t = np.arange(L.n) / MR
    y = np.zeros(L.n)
    for f, a in ((36.71, 0.7), (73.42, 1.0), (110.0, 0.5), (146.83, 0.55), (174.61, 0.16)):
        for det in (-0.125, 0.0, 0.125):
            y += a * saw(snap(f + det, 16), t, 2600.0, 1.4, r) / 3.0
    dark = D.lowpass(y, 260.0, MR)
    bright = D.lowpass(y, 900.0, MR)
    y = dark + bright * (0.3 + 0.3 * np.sin(TAU * t / 16.0 + 0.5)) * 0.6
    y += D.air(L.n, r, 60.0, 240.0, MR) * 0.18 * (0.6 + 0.4 * np.sin(TAU * 2 * t / 16.0 + 1.0))
    L.buf = y
    L.room(2.6, 0.25, seed=102)
    fin("pm_drone", L.buf, MR, 101, True, "music", "a low D pad with a minor third in it", rms=-22.0)


def m_motif():
    L = D.Loop(32, MR, 111)
    r = L.rng
    melody = [(0, 62, .75), (2, 65, .55), (4, 69, .7), (7, 67, .5), (8, 65, .65), (10.5, 64, .5), (12, 62, .7), (15, 60, .45),
              (16, 62, .7), (18, 65, .55), (20, 70, .6), (22, 69, .5), (24, 67, .6), (26.5, 65, .45), (28, 64, .55), (30, 62, .6)]
    for beat, m, v in melody:
        L.add(float(beat), D.piano(HZ_M(m), 6.0, v, MR, r, bright=0.8), 0.55)
    for bar, m in enumerate((38, 34, 41, 33, 38, 31, 33, 38)):
        L.add(bar * 4.0, D.piano(HZ_M(m), 7.0, 0.55, MR, r, bright=0.7), 0.7)
    for i, chord in enumerate(((50, 53, 57), (46, 50, 53), (43, 46, 50), (45, 48, 52))):
        for m in chord:
            L.add(i * 8.0, D.pad(HZ_M(m), 8.0, MR, r, attack=3.0, release=3.0, bright=0.45), 0.06)
    L.room(3.4, 0.4, seed=112)
    fin("pm_motif", L.buf, MR, 111, True, "music", "a slow piano motif in D minor, sparse", rms=-22.0)


def HZ_M(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def m_drip():
    L = D.Loop(16, MR, 121)
    r = L.rng
    notes = [(0.7, 587.3, .5), (2.9, 880.0, .35), (4.2, 698.5, .45), (7.1, 1046.5, .3), (8.4, 659.3, .5), (10.9, 784.0, .35), (13.2, 587.3, .4), (14.6, 880.0, .3)]
    for at, f, v in notes:
        b = D.chime(f, 3.5, MR, r, v)
        L.add(at, b)
        L.add(at + 0.52, D.lowpass(b, 1800.0, MR, 2, circular=False), 0.32)
        L.add(at + 1.05, D.lowpass(b, 1200.0, MR, 2, circular=False), 0.14)
    for at in (1.8, 5.5, 9.7, 12.1):
        n = int(0.09 * MR)
        t = np.arange(n) / MR
        ph = TAU * np.cumsum(500.0 + 1000.0 * np.exp(-t / 0.018)) / MR
        L.add(at, np.sin(ph) * np.exp(-t / 0.02) * D.ramp(t, 0.001), 0.5)
    L.room(3.2, 0.45, seed=122)
    fin("pm_drip", L.buf, MR, 121, True, "music", "sparse high bell notes and drips with echoes", rms=-25.0)


def m_pulse():
    L = D.Loop(16, MR, 131)
    r = L.rng
    for b in range(16):
        L.add(float(b), D.thump(MR, 110.0, 48.0, 0.5, 25.0, 0.14, 0.15, r), 1.0)
        L.add(b + 0.32, D.thump(MR, 92.0, 42.0, 0.4, 28.0, 0.1, 0.1, r), 0.5)
    pat = (36.71, 36.71, 36.71, 43.65, 36.71, 36.71, 48.99, 43.65)
    for i in range(32):
        f = pat[i % 8] * 2.0
        L.add(i * 0.5, bass(f, 0.42, MR, r, tau=0.2, top=500.0), 0.22 if i % 4 else 0.34)
    L.room(1.2, 0.12, seed=132)
    fin("pm_pulse", L.buf, MR, 131, True, "music", "a heartbeat and a muted bass ostinato", rms=-22.0)


def m_perc():
    L = D.Loop(16, MR, 141)
    r = L.rng
    for bar in range(4):
        for at, f, v in ((0, 95, 1.0), (1.5, 110, .5), (2.25, 95, .7), (3.0, 80, .6), (3.5, 110, .45)):
            L.add(bar * 4.0 + at, D.tom(f, 1.3, MR, r, v, tau=0.35), 0.8)
    for k in range(7):
        L.add(14.5 + k * 0.18, D.tom(100 - k * 4, 0.6, MR, r, 0.3 + k * 0.1, tau=0.18), 0.8)
    L.add(0.0, D.taiko(55.0, 2.0, MR, r, 1.0), 0.7)
    L.add(8.0, D.taiko(49.0, 2.0, MR, r, 0.8), 0.6)
    L.add(6.0, D.clank(1320.0, 1.6, MR, r, 0.3), 0.3)
    L.add(13.0, D.clank(990.0, 1.6, MR, r, 0.3), 0.3)
    L.room(1.9, 0.3, seed=142)
    fin("pm_perc", L.buf, MR, 141, True, "music", "frame drums, taiko and a bit of struck metal", rms=-21.0)


def m_danger():
    L = D.Loop(16, MR, 151)
    r = L.rng
    for f in (146.83, 155.56, 207.65, 220.0, 293.66):
        L.add(0.0, D.bowed(f, 12.0, MR, r, vel=0.5, attack=4.0, release=4.0, voices=3, bright=0.9), 0.5)
    sh = D.air(L.n, r, 2500.0, 6000.0, MR) * (0.5 - 0.5 * np.cos(TAU * np.arange(L.n) / L.n))
    L.add(0.0, sh, 0.03)
    for at in (4.0, 12.0):
        L.add(at, D.thump(MR, 55.0, 32.0, 2.4, 6.0, 0.6, 0.0, r), 0.9)
    L.lowpass(2600.0)
    L.room(2.4, 0.3, seed=152)
    fin("pm_danger", L.buf, MR, 151, True, "music", "dissonant strings that swell and fall, sub booms", rms=-22.0)


def m_explore():
    L = D.Loop(32, MR, 161)
    r = L.rng
    chords = [(45, 52, 57, 60, 64), (41, 48, 53, 57, 60), (48, 55, 60, 64, 67), (43, 50, 55, 59, 62),
              (45, 52, 57, 60, 64), (41, 48, 53, 57, 60), (50, 57, 62, 66, 69), (40, 47, 52, 55, 59)]
    order = (0, 2, 1, 3, 2, 4, 3, 2)
    for bar, ch in enumerate(chords):
        for i, ix in enumerate(order):
            L.add(bar * 4.0 + i * 0.5, D.piano(HZ_M(ch[ix]), 1.4, 0.45 if i % 2 == 0 else 0.3, MR, r, bright=0.85, decay_scale=0.3), 0.5)
        L.add(bar * 4.0, D.pad(HZ_M(ch[0]), 4.0, MR, r, attack=1.5, release=2.0, bright=0.4), 0.2)
    for at, m in ((0.0, 69), (8.0, 72), (16.0, 71), (24.0, 69)):
        L.add(at, D.bowed(HZ_M(m), 5.0, MR, r, vel=0.25, attack=1.5, release=1.5, voices=1), 0.5)
    L.room(2.2, 0.28, seed=162)
    fin("pm_explore", L.buf, MR, 161, True, "music", "a curious plucked arpeggio in A dorian", rms=-22.0)


def m_raid():
    L = D.Loop(16, MR, 171)
    r = L.rng
    for f in (82.41, 116.54):
        L.add(0.0, D.bowed(f, 12.0, MR, r, vel=0.5, attack=4.0, release=4.0, voices=2, bright=0.7), 0.6)
    for s in range(16):
        n = int(0.012 * MR)
        t = np.arange(n) / MR
        tick = D.bandpass(r.standard_normal(n), 1500.0, 4500.0, MR, 2, circular=False) * np.exp(-t / 0.003)
        L.add(s + 0.05, tick, 0.9 if s % 4 == 0 else 0.5)
    L.add(6.5, D.clank(1760.0, 1.5, MR, r, 0.3), 0.35)
    L.add(13.2, D.clank(1245.0, 1.5, MR, r, 0.3), 0.3)
    L.add(0.05, D.thump(MR, 60.0, 35.0, 1.5, 8.0, 0.4, 0.0, r), 0.5)
    L.room(2.0, 0.3, seed=172)
    fin("pm_raid", L.buf, MR, 171, True, "music", "a tritone drone, a ticking clock, far metal", rms=-23.0)


def m_chase():
    L = D.Loop(16, MR, 181)
    r = L.rng
    for b in range(32):
        L.add(b * 0.5 + 0.03, D.thump(MR, 120.0, 50.0, 0.3, 30.0, 0.09, 0.25, r), 0.9)
    pat = (0, 0, 0, 3, 0, 0, 5, 3)
    for i in range(64):
        L.add(i * 0.25, bass(73.42 * 2.0 ** (pat[i % 8] / 12.0), 0.22, MR, r, tau=0.12, top=1200.0), 0.3)
    for s in range(16):
        n = int(0.3 * MR)
        t = np.arange(n) / MR
        sn = D.bandpass(r.standard_normal(n), 900.0, 5000.0, MR, 2, circular=False) * np.exp(-t / 0.07) + np.sin(TAU * 190.0 * t) * np.exp(-t / 0.05)
        L.add(s * 1.0 + 0.5, sn, 0.35)
    for h in range(128):
        n = int(0.05 * MR)
        t = np.arange(n) / MR
        L.add(h * 0.125, D.highpass(r.standard_normal(n), 5000.0, MR, 2, circular=False) * np.exp(-t / 0.012), 0.12 if h % 2 else 0.06)
    for s in range(8):
        for f in (146.83, 155.56, 220.0):
            L.add(s * 2.0, D.brass(f, 0.3, MR, r, attack=0.04, release=0.3, level=0.9, voices=1), 0.18)
    L.room(1.0, 0.1, seed=182)
    fin("pm_chase", L.buf, MR, 181, True, "music", "a driving 120 bpm chase: kick, bass, snare, brass stabs", rms=-18.0)


def music():
    for f in (m_drone, m_motif, m_drip, m_pulse, m_perc, m_danger, m_explore, m_raid, m_chase):
        f()


def stingers():
    r = np.random.default_rng(201)
    # a segment falls: a boom, a crash of wire and a dissonant stab
    boom = D.thump(MR, 70.0, 28.0, 2.4, 6.0, 0.7, 0.2, r)
    t = np.arange(int(2.2 * MR)) / MR
    crash = D.bandpass(r.standard_normal(len(t)), 300.0, 5500.0, MR, 2, circular=False) * np.exp(-t / 0.45) * D.ramp(t, 0.004)
    stab = D.brass(55.0, 1.3, MR, r, attack=0.03, release=1.6, level=0.9) + D.brass(58.27, 1.3, MR, r, attack=0.03, release=1.6, level=0.9)
    x = np.zeros(int(4.2 * MR))
    x[:len(boom)] += boom * 1.0
    x[:len(crash)] += crash * 0.55
    x[:len(stab)] += stab * 0.5
    y = room(x, MR, 2.4, 0.35, 202)
    fin("pst_fall", y * D.tail_off(len(y), MR, 1.0), MR, 201, False, "music", "a segment falls", peak=-3.0)
    # someone dies: a dark swell that rises for six seconds and stops on a low thud
    n = int(8.5 * MR)
    x = np.zeros(n)
    for f in (73.42, 110.0, 155.56, 207.65):
        b = D.brass(f, 6.0, MR, r, attack=5.6, release=1.2, level=0.7, voices=2)
        x[:len(b)] += b
    sh = D.air(n, r, 2000.0, 5500.0, MR) * D.ramp(np.arange(n) / MR, 6.0) * D.ramp(6.2 - np.arange(n) / MR, 0.2) * 0.07
    x += sh
    th = D.thump(MR, 60.0, 30.0, 2.2, 6.0, 0.6, 0.1, r)
    i = int(6.2 * MR)
    x[i:i + len(th)] += th[:n - i] * 1.1
    y = room(x, MR, 3.4, 0.4, 203)
    fin("pst_death", y * D.tail_off(len(y), MR, 1.5), MR, 202, False, "music", "a dark swell when someone dies", peak=-3.0)
    # dawn survived: D major, warm, quiet
    n = int(15.0 * MR)
    x = np.zeros(n)
    for m in (50, 57, 66):
        b = D.pad(HZ_M(m), 8.0, MR, r, attack=3.0, release=4.0, bright=0.5)
        x[:len(b)] += b * 0.25
    for at, m, v in ((0.8, 69, .5), (2.2, 66, .45), (3.6, 74, .55), (5.5, 76, .45), (7.0, 78, .5), (9.0, 69, .4), (10.5, 74, .35)):
        b = D.piano(HZ_M(m), 5.0, v, MR, r, bright=0.8)
        i = int(at * MR)
        x[i:i + len(b)] += b[:n - i] * 0.6
    c = D.chime(HZ_M(90), 3.0, MR, r, 0.4)
    i = int(10.0 * MR)
    x[i:i + len(c)] += c * 0.25
    y = room(x, MR, 3.2, 0.35, 204)
    fin("pst_dawn", y * D.tail_off(len(y), MR, 3.0), MR, 203, False, "music", "the relief of a dawn survived, D major", peak=-3.0)


# ------------------------------------------------------------------------------------------------ AMBIENCE

def a_rain():
    for name, seed, bed, drops, body in (("roof", 301, (1800.0, 6500.0), (430, 1800.0, 4500.0), 0.35),
                                          ("concrete", 302, (1000.0, 7000.0), (260, 2800.0, 7000.0), 0.0),
                                          ("grass", 303, (250.0, 2600.0), (190, 700.0, 1900.0), 0.15)):
        L = D.Loop(8, MR, seed)
        r = L.rng
        y = D.bandpass(r.standard_normal(L.n), bed[0], bed[1], MR, 2) * 1.0
        y += D.lowpass(r.standard_normal(L.n), 260.0, MR) * body
        y += clicks(L.n, MR, r, drops[0], drops[1], drops[2], 0.0013 if name != "grass" else 0.003) * 0.22
        y *= slow(L.n, MR, 8.0, r, 0.12)
        fin("pa_rain_" + name, y, MR, seed, True, "ambience", "rain on a " + name, rms=-30.0)


def a_wind():
    L = D.Loop(12, MR, 311)
    r = L.rng
    y = D.lowpass(r.standard_normal(L.n), 420.0, MR) * 1.0 + D.air(L.n, r, 130.0, 330.0, MR) * 0.8
    y *= slow(L.n, MR, 12.0, r, 0.45, 4)
    fin("pa_wind_low", y, MR, 311, True, "ambience", "a low steady wind, breathing", rms=-31.0)
    L = D.Loop(12, MR, 312)
    r = L.rng
    t = np.arange(L.n) / MR
    gust = np.exp(-0.5 * ((((t - 3.0) + 6.0) % 12.0 - 6.0) / 1.1) ** 2) + 0.7 * np.exp(-0.5 * ((((t - 8.5) + 6.0) % 12.0 - 6.0) / 0.9) ** 2)
    y = D.bandpass(r.standard_normal(L.n), 450.0, 1900.0, MR, 2) * (0.15 + gust)
    y += np.sin(TAU * snap(640.0, 12) * t + 4.0 * np.sin(TAU * 3 / 12.0 * t)) * 0.05 * gust
    fin("pa_wind_gust", y, MR, 312, True, "ambience", "gusts through the wire, a faint whistle", rms=-32.0)


def a_fire():
    L = D.Loop(6, MR, 321)
    r = L.rng
    y = D.lowpass(r.standard_normal(L.n), 480.0, MR) * 0.22 * slow(L.n, MR, 6.0, r, 0.25)
    nz = D.Loop(6, MR, 322)
    for _ in range(int(34 * 6)):
        m = int(r.uniform(0.002, 0.009) * MR)
        nz.add(r.uniform(0, 6), r.standard_normal(m) * np.exp(-np.arange(m) / m * 3.0), r.lognormal(-0.4, 0.9))
    for _ in range(14):
        m = int(0.02 * MR)
        t = np.arange(m) / MR
        nz.add(r.uniform(0, 6), D.lowpass(r.standard_normal(m), 2200.0, MR, 2, circular=False) * np.exp(-t / 0.006) * 2.5, 1.0)
    y = D.highpass(y + nz.buf * 0.35, 120.0, MR)
    fin("pa_fire", y, MR, 321, True, "ambience", "a fire: a low roar, crackle and pops", rms=-31.0)


def a_buzz():
    L = D.Loop(4, MR, 331)
    r = L.rng
    t = np.arange(L.n) / MR
    y = np.zeros(L.n)
    for k in range(1, 28):
        y += np.sin(TAU * 100.0 * k * t + r.uniform(0, TAU)) / k ** 0.75
    y += D.highpass(r.standard_normal(L.n), 3000.0, MR) * 0.05
    flick = np.ones(L.n)
    for at in (0.9, 2.2, 3.1):
        flick *= 1.0 - 0.45 * np.exp(-0.5 * (((t - at) + 2.0) % 4.0 - 2.0) ** 2 / 0.0004)
    fin("pa_buzz", y * flick, MR, 331, True, "ambience", "a floodlight's mains buzz with a flicker", rms=-34.0)


def a_room():
    L = D.Loop(6, MR, 341)
    r = L.rng
    t = np.arange(L.n) / MR
    y = D.lowpass(r.standard_normal(L.n), 300.0, MR) * 0.6 * slow(L.n, MR, 6.0, r, 0.2) + 0.25 * np.sin(TAU * 50.0 * t) + 0.12 * np.sin(TAU * 100.0 * t)
    fin("pa_room", y, MR, 341, True, "ambience", "the tone of a closed room", rms=-36.0)


def a_flutter():
    L = D.Loop(6, MR, 351)
    r = L.rng
    t = np.arange(L.n) / MR
    g = np.clip(0.2 + 0.8 * np.sin(TAU * 1.0 / 6.0 * t + 1.0) ** 2, 0, 1)
    fl = 0.3 + 0.7 * np.maximum(0.0, np.sin(TAU * 5.0 * t + 1.3 * np.sin(TAU * 1 / 6.0 * t))) ** 2 + 0.2 * np.maximum(0.0, np.sin(TAU * 7.0 * t)) ** 2
    y = D.bandpass(r.standard_normal(L.n), 500.0, 2600.0, MR, 2) * fl * g
    fin("pa_flutter", y, MR, 351, True, "ambience", "laundry fluttering on the line", rms=-33.0)


def a_static():
    L = D.Loop(4, MR, 361)
    r = L.rng
    y = D.bandpass(r.standard_normal(L.n), 700.0, 4200.0, MR, 2) * 0.5 * slow(L.n, MR, 4.0, r, 0.3)
    y += clicks(L.n, MR, r, 6, 800.0, 3000.0, 0.004, 1.0) * 0.5
    fin("pa_static", y, MR, 361, True, "ambience", "a radio between stations, faint", rms=-34.0)


def a_oneshots():
    for k in range(3):
        r = np.random.default_rng(371 + k)
        n = int(1.9 * SR)
        x = np.zeros(n)
        at = 0.0
        for _ in range(r.integers(6, 11)):
            at += r.uniform(0.05, 0.25)
            f = r.uniform(1800, 4200)
            m = int(0.25 * SR)
            t = np.arange(m) / SR
            tau = r.uniform(0.02, 0.07)
            hit = (np.sin(TAU * f * t) + 0.5 * np.sin(TAU * f * 2.31 * t)) * np.exp(-t / tau) + D.highpass(r.standard_normal(m), 2000.0, SR, 2, circular=False) * np.exp(-t / 0.004) * 0.6
            i = int(at * SR)
            if i + m < n:
                x[i:i + m] += hit * r.uniform(0.3, 1.0)
        y = room(x, SR, 0.6, 0.2, 380 + k)
        fin("pa_clatter_%d" % k, y, SR, 371 + k, False, "ambience", "canteen: tin and china", peak=-14.0)
    for k, (f0, notes) in enumerate(((380.0, ((0.1, 0.55), (1.2, 0.35), (1.7, 0.45))), (330.0, ((0.1, 0.6), (1.4, 0.3), (1.85, 0.5), (2.4, 0.45))))):
        r = np.random.default_rng(391 + k)
        n = int(3.3 * SR)
        x = np.zeros(n)
        for at, d in notes:
            m = int(d * SR)
            t = np.arange(m) / SR
            f = f0 * (1.0 + 0.06 * (1.0 - D.ramp(t, d * 0.7)) - 0.04 * D.ramp(t - d * 0.5, d * 0.5))
            ph = TAU * np.cumsum(f * (1.0 + 0.012 * np.sin(TAU * 5.0 * t))) / SR
            v = (np.sin(ph) + 0.28 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)) * D.ramp(t, 0.12) * D.ramp(d - t, 0.2)
            v += D.bandpass(r.standard_normal(m), 300.0, 900.0, SR, 2, circular=False) * 0.04 * D.ramp(t, 0.1) * D.ramp(d - t, 0.2)
            i = int(at * SR)
            x[i:i + m] += v
        y = room(x, SR, 1.8, 0.35, 395 + k)
        fin("pa_owl_%d" % k, y * D.tail_off(len(y), SR, 0.8), SR, 391 + k, False, "ambience", "an owl, far off", peak=-14.0)


def ambience():
    a_rain()
    a_wind()
    a_fire()
    a_buzz()
    a_room()
    a_flutter()
    a_static()
    a_oneshots()


# ------------------------------------------------------------------------------------------------ FOLEY

def seq(n, sr):
    return np.zeros(int(n * sr))


def put(x, snd, at, sr, g=1.0):
    i = int(at * sr)
    m = min(len(snd), len(x) - i)
    if m > 0:
        x[i:i + m] += snd[:m] * g


def noise_burst(dur, lo, hi, tau, sr, rng, attack=0.003):
    n = int(dur * sr)
    t = np.arange(n) / sr
    return D.bandpass(rng.standard_normal(n), lo, hi, sr, 2, circular=False) * np.exp(-t / tau) * D.ramp(t, attack)


def foley_steps():
    for k in range(4):
        r = np.random.default_rng(401 + k)
        x = seq(0.4, SR)
        put(x, noise_burst(0.3, 120.0, 900.0, 0.07, SR, r, 0.008), 0.0, SR, 1.0)
        n = int(0.14 * SR)
        t = np.arange(n) / SR
        put(x, np.sin(TAU * np.cumsum(190.0 - 110.0 * D.ramp(t, 0.14)) / SR) * np.exp(-t / 0.05), 0.0, SR, 0.5)
        sq = D.bandpass(r.standard_normal(int(0.2 * SR)), 400.0, 1400.0, SR, 2, circular=False)
        sq *= np.abs(D.lowpass(r.standard_normal(len(sq)), 60.0, SR, 2, circular=False)) * 10.0 * np.exp(-np.arange(len(sq)) / SR / 0.08)
        put(x, sq, 0.05, SR, 0.35)
        fin("pf_mud_%d" % k, x, SR, 401 + k, False, "foley", "a step in mud", peak=-16.0)
    for k in range(4):
        r = np.random.default_rng(411 + k)
        x = seq(0.55, SR)
        env = D.ramp(np.arange(int(0.45 * SR)) / SR, 0.05) * np.exp(-np.arange(int(0.45 * SR)) / SR / 0.14)
        sc = D.bandpass(r.standard_normal(len(env)), 250.0, 2400.0, SR, 2, circular=False) * env * (0.6 + 0.4 * D.lowpass(r.standard_normal(len(env)), 40.0, SR, 1, circular=False) * 8.0)
        put(x, sc, 0.0, SR, 1.0)
        put(x, D.thump(SR, 110.0, 60.0, 0.12, 30.0, 0.035, 0.0, r), 0.03, SR, 0.4)
        fin("pf_shuffle_%d" % k, x, SR, 411 + k, False, "foley", "the dead's foot scuffing", peak=-16.0)
    for k in range(2):
        r = np.random.default_rng(421 + k)
        n = int(0.9 * SR)
        t = np.arange(n) / SR
        x = D.bandpass(r.standard_normal(n), 200.0, 2000.0, SR, 2, circular=False) * D.ramp(t, 0.12) * D.ramp(0.9 - t, 0.3) * (0.7 + 0.5 * np.abs(D.lowpass(r.standard_normal(n), 25.0, SR, 2, circular=False)) * 6.0)
        fin("pf_drag_%d" % k, x, SR, 421 + k, False, "foley", "a foot dragged on the ground", peak=-16.0)


def foley_doors():
    for k in range(2):
        r = np.random.default_rng(431 + k)
        x = seq(2.4, SR)
        f0 = (170.0, 205.0)[k]
        n = int(2.2 * SR)
        t = np.arange(n) / SR
        hit = np.zeros(n)
        for ratio, amp, tau in ((1.0, 1.0, 1.2), (1.59, 0.8, 0.9), (2.14, 0.7, 0.7), (2.65, 0.5, 0.5), (3.3, 0.45, 0.4), (4.2, 0.3, 0.3), (5.6, 0.2, 0.2)):
            hit += amp * np.sin(TAU * f0 * ratio * (1 + r.uniform(-0.01, 0.01)) * t + r.uniform(0, TAU)) * np.exp(-t / tau)
        put(x, hit, 0.0, SR, 1.0)
        put(x, noise_burst(0.12, 500.0, 6000.0, 0.015, SR, r, 0.001), 0.0, SR, 1.5)
        put(x, hit * 0.4, 0.11, SR, 1.0)
        put(x, D.thump(SR, 90.0, 45.0, 0.3, 25.0, 0.08, 0.2, r), 0.0, SR, 0.9)
        fin("pd_cell_slam_%d" % k, room(x, SR, 0.9, 0.2, 440 + k), SR, 431 + k, False, "foley", "a cell door slams", peak=-8.0)
    r = np.random.default_rng(441)
    x = seq(1.4, SR)
    put(x, noise_burst(0.02, 1200.0, 5000.0, 0.004, SR, r, 0.0005), 0.0, SR, 1.2)
    put(x, D.clank(900.0, 0.3, SR, r, 0.6), 0.02, SR, 0.8)
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    sl = D.bandpass(r.standard_normal(n), 600.0, 2400.0, SR, 2, circular=False) * D.ramp(t, 0.1) * D.ramp(0.7 - t, 0.15) * (0.6 + 0.4 * np.sin(TAU * 14.0 * t))
    put(x, sl, 0.12, SR, 0.5)
    put(x, noise_burst(0.02, 1200.0, 5000.0, 0.004, SR, r, 0.0005), 0.9, SR, 1.0)
    put(x, D.clank(700.0, 0.4, SR, r, 0.7), 0.91, SR, 0.9)
    fin("pd_cell_open_0", x, SR, 441, False, "foley", "a cell door unlocked and slid", peak=-9.0)
    # the gate's chain
    r = np.random.default_rng(451)
    x = seq(1.6, SR)
    for _ in range(46):
        at = abs(r.normal(0.0, 0.5))
        if at > 1.4:
            continue
        put(x, D.clank(r.uniform(2400.0, 5600.0), 0.14, SR, r, 1.0), at, SR, r.uniform(0.2, 1.0) * np.exp(-at * 0.8))
    put(x, D.lowpass(r.standard_normal(int(1.2 * SR)), 900.0, SR, 2, circular=False) * np.exp(-np.arange(int(1.2 * SR)) / SR / 0.5) * 0.25, 0.0, SR)
    fin("pd_chain_0", x, SR, 451, False, "foley", "the gate's chain rattles", peak=-9.0)
    # the rolling door
    r = np.random.default_rng(461)
    x = seq(2.9, SR)
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    ribs = np.abs(np.sin(TAU * 26.0 * t * (1.0 + 0.05 * t))) ** 1.4
    rr = D.bandpass(r.standard_normal(n), 300.0, 2600.0, SR, 2, circular=False) * ribs * D.ramp(t, 0.15) * D.ramp(2.2 - t, 0.4) * (0.6 + 0.4 * t / 2.2)
    put(x, rr, 0.25, SR, 1.0)
    put(x, D.thump(SR, 100.0, 50.0, 0.3, 20.0, 0.1, 0.3, r), 0.0, SR, 0.8)
    put(x, D.clank(260.0, 1.0, SR, r, 0.9), 2.45, SR, 1.0)
    put(x, noise_burst(0.1, 600.0, 5000.0, 0.02, SR, r, 0.001), 2.45, SR, 1.0)
    fin("pd_rolling_0", room(x, SR, 0.8, 0.15, 462), SR, 461, False, "foley", "a rolling door goes up and stops", peak=-9.0)


def foley_hands():
    for k in range(2):
        r = np.random.default_rng(471 + k)
        x = seq(0.5, SR)
        put(x, noise_burst(0.06, 800.0, 2500.0, 0.02, SR, r, 0.001), 0.0, SR, 1.0)
        put(x, D.thump(SR, 160.0, 90.0, 0.12, 30.0, 0.04, 0.0, r), 0.0, SR, 0.7)
        n = int(0.22 * SR)
        t = np.arange(n) / SR
        cr = np.sin(TAU * np.cumsum(300.0 + 140.0 * D.ramp(t, 0.2)) / SR)
        cr = D.lowpass(np.sign(cr) * 0.4 + cr, 1400.0, SR, 2, circular=False) * D.ramp(t, 0.03) * D.ramp(0.22 - t, 0.08)
        put(x, cr, 0.05, SR, 0.25)
        put(x, noise_burst(0.05, 600.0, 1800.0, 0.03, SR, r), 0.27, SR, 0.5)
        fin("pu_lid_%d" % k, x, SR, 471 + k, False, "foley", "a lid opened", peak=-12.0)
    for k in range(2):
        r = np.random.default_rng(481 + k)
        n = int(0.8 * SR)
        e = np.abs(D.lowpass(r.standard_normal(n), 14.0, SR, 2, circular=False))
        e = e / np.max(e)
        y = D.bandpass(r.standard_normal(n), 1500.0, 6000.0, SR, 2, circular=False) * e ** 1.5 * D.ramp(np.arange(n) / SR, 0.03) * D.ramp(0.8 - np.arange(n) / SR, 0.2)
        fin("pu_rustle_%d" % k, y, SR, 481 + k, False, "foley", "rummaging in a box", peak=-14.0)
    r = np.random.default_rng(491)
    x = seq(1.3, SR)
    for at, f in ((0.0, 3600.0), (0.17, 4300.0), (0.31, 3100.0), (0.55, 4900.0), (0.7, 3900.0)):
        put(x, D.chime(f, 0.6, SR, r, 0.8, partials=((1.0, 1.0, 0.15), (2.4, 0.5, 0.08), (4.1, 0.3, 0.05))), at, SR, r.uniform(0.4, 1.0))
    fin("pu_glass_0", x, SR, 491, False, "foley", "glass chinking", peak=-12.0)
    for k in range(2):
        r = np.random.default_rng(501 + k)
        x = seq(0.35, SR)
        put(x, noise_burst(0.12, 1500.0, 6000.0, 0.03, SR, r, 0.01), 0.0, SR, 1.0)
        put(x, noise_burst(0.03, 600.0, 2400.0, 0.01, SR, r, 0.0005), 0.1, SR, 0.8)
        fin("pu_pickup_%d" % k, x, SR, 501 + k, False, "foley", "picking something up", peak=-13.0)
    for name, rev, seed in (("pu_pack_open", False, 511), ("pu_pack_close", True, 512)):
        r = np.random.default_rng(seed)
        n = int(0.55 * SR)
        t = np.arange(n) / SR
        zip_ = D.bandpass(r.standard_normal(n), 2000.0, 6500.0, SR, 2, circular=False) * (0.5 + 0.5 * np.sign(np.sin(TAU * (45.0 + 60.0 * t / 0.55) * t))) * D.ramp(t, 0.02) * D.ramp(0.55 - t, 0.08)
        if rev:
            zip_ = zip_[::-1]
        x = seq(0.8, SR)
        put(x, zip_, 0.0, SR, 0.8)
        put(x, noise_burst(0.1, 500.0, 1800.0, 0.04, SR, r, 0.002), 0.55 if not rev else 0.0, SR, 0.5)
        fin(name, x, SR, seed, False, "foley", "the backpack zip", peak=-13.0)
    r = np.random.default_rng(521)
    x = seq(0.9, SR)
    for at in (0.0, 0.2, 0.37, 0.6):
        put(x, noise_burst(0.07, 800.0, 4500.0, 0.018, SR, r, 0.002), at, SR, r.uniform(0.6, 1.0))
    fin("pu_eat_0", x, SR, 521, False, "foley", "eating: a few crunches", peak=-12.0)
    r = np.random.default_rng(531)
    x = seq(1.0, SR)
    for at in (0.05, 0.4, 0.7):
        n = int(0.16 * SR)
        t = np.arange(n) / SR
        g = np.sin(TAU * np.cumsum(240.0 - 110.0 * D.ramp(t, 0.16)) / SR) * np.exp(-t / 0.08) * D.ramp(t, 0.01)
        put(x, g, at, SR, 0.6)
        put(x, noise_burst(0.15, 300.0, 1200.0, 0.06, SR, r, 0.01), at, SR, 0.3)
    fin("pu_drink_0", x, SR, 531, False, "foley", "drinking: gulps", peak=-12.0)
    r = np.random.default_rng(541)
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    y = D.highpass(r.standard_normal(n), 1200.0, SR, 2, circular=False) * (0.4 + 0.6 * np.abs(np.sin(TAU * 31.0 * t))) * D.ramp(t, 0.03) * D.ramp(0.7 - t, 0.25) * (0.6 + 0.4 * np.sin(TAU * 3.0 * t) ** 2)
    fin("pu_bandage_0", y, SR, 541, False, "foley", "cloth torn into a bandage", peak=-13.0)


def foley_build():
    r = np.random.default_rng(551)
    x = seq(1.6, SR)
    for s in range(4):
        n = int(0.34 * SR)
        t = np.arange(n) / SR
        st = D.ramp(t, 0.06) * D.ramp(0.34 - t, 0.1)
        body = D.bandpass(r.standard_normal(n), 1800.0, 6000.0, SR, 2, circular=False) * st
        buzz = saw(240.0 + 20.0 * s, t, 3000.0, 1.0) * st * 0.25
        put(x, body + buzz, s * 0.38, SR, 1.0)
    fin("pb_saw_0", x, SR, 551, False, "foley", "sawing wood: four strokes", peak=-12.0)
    r = np.random.default_rng(561)
    n = int(1.1 * SR)
    t = np.arange(n) / SR
    f = 150.0 + 70.0 * D.ramp(t, 0.25) - 20.0 * D.ramp(t - 0.9, 0.2)
    ph = TAU * np.cumsum(f) / SR
    y = (np.sin(ph) + 0.6 * np.sin(2 * ph) + 0.4 * np.sign(np.sin(3 * ph))) * 0.3
    y += np.sin(TAU * np.cumsum(1700.0 + 500.0 * D.ramp(t, 0.3)) / SR) * 0.15 + D.bandpass(r.standard_normal(n), 800.0, 3500.0, SR, 2, circular=False) * 0.35
    y *= D.ramp(t, 0.04) * D.ramp(1.1 - t, 0.15) * (0.85 + 0.15 * np.sin(TAU * 38.0 * t))
    fin("pb_drill_0", y, SR, 561, False, "foley", "a drill", peak=-12.0)
    r = np.random.default_rng(571)
    x = seq(2.0, SR)
    for at, f in ((0.0, 659.3), (0.22, 987.8)):
        put(x, D.chime(f, 1.6, SR, r, 0.9, partials=((1.0, 1.0, 1.0), (2.0, 0.4, 0.6), (3.01, 0.2, 0.4), (4.2, 0.1, 0.25))), at, SR, 1.0)
    fin("pb_done_0", room(x, SR, 1.2, 0.2, 572), SR, 571, False, "ui", "a project is finished", peak=-10.0)


def foley_ui():
    r = np.random.default_rng(581)
    x = seq(0.6, SR)
    for at, f in ((0.0, 520.0), (0.2, 390.0)):
        n = int(0.16 * SR)
        t = np.arange(n) / SR
        b = (np.sin(TAU * f * t) + 0.3 * np.sign(np.sin(TAU * f * t))) * D.ramp(t, 0.01) * D.ramp(0.16 - t, 0.06)
        put(x, D.lowpass(b, 1600.0, SR, 2, circular=False), at, SR, 1.0)
    fin("pu_warn_0", x, SR, 581, False, "ui", "a low warning: two falling beeps", peak=-10.0)
    n = int(3.0 * SR)
    t = np.arange(n) / SR
    f = 780.0 + 220.0 * np.sin(TAU * 0.7 * t - 1.0)
    ph = TAU * np.cumsum(f) / SR
    y = (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.2 * np.sin(3 * ph)) * D.ramp(t, 0.05) * D.ramp(3.0 - t, 0.4)
    fin("pu_alarm_0", D.lowpass(y, 2400.0, SR, 2, circular=False), SR, 582, False, "ui", "an alarm: a wavering siren", peak=-10.0)
    r = np.random.default_rng(583)
    x = seq(1.0, SR)
    put(x, D.thump(SR, 62.0, 40.0, 0.35, 12.0, 0.1, 0.0, r), 0.0, SR, 1.0)
    put(x, D.thump(SR, 52.0, 38.0, 0.3, 12.0, 0.09, 0.0, r), 0.3, SR, 0.65)
    fin("pu_heart_0", x, SR, 583, False, "foley", "a heartbeat: lub-dub", peak=-8.0)


def foley_combat():
    for k in range(3):
        r = np.random.default_rng(591 + k)
        x = seq(0.5, SR)
        put(x, D.thump(SR, 210.0 - 30 * k, 90.0, 0.2, 40.0, 0.045, 0.0, r), 0.0, SR, 1.0)
        put(x, noise_burst(0.2, 150.0 + 80 * k, 1400.0, 0.04, SR, r, 0.001), 0.0, SR, 0.9)
        fin("pw_wood_%d" % k, x, SR, 591 + k, False, "foley", "a bullet or a blow in wood", peak=-9.0)
    for k in range(2):
        r = np.random.default_rng(601 + k)
        x = seq(0.4, SR)
        put(x, D.clank(2700.0 + 300 * k, 0.12, SR, r, 0.8), 0.0, SR, 1.0)
        put(x, noise_burst(0.015, 2000.0, 7000.0, 0.003, SR, r, 0.0005), 0.0, SR, 0.8)
        put(x, D.clank(3400.0, 0.08, SR, r, 0.5), 0.13, SR, 0.5)
        fin("pw_shell_%d" % k, x, SR, 601 + k, False, "foley", "a shell pushed into the magazine", peak=-12.0)
    r = np.random.default_rng(611)
    x = seq(0.7, SR)
    put(x, noise_burst(0.35, 400.0, 3500.0, 0.09, SR, r, 0.004), 0.0, SR, 0.5)
    put(x, D.clank(1300.0, 0.15, SR, r, 0.9), 0.0, SR, 1.0)
    put(x, D.thump(SR, 150.0, 90.0, 0.1, 30.0, 0.03, 0.0, r), 0.0, SR, 0.6)
    put(x, D.clank(900.0, 0.2, SR, r, 1.0), 0.28, SR, 1.0)
    put(x, D.thump(SR, 130.0, 80.0, 0.1, 30.0, 0.03, 0.0, r), 0.28, SR, 0.7)
    fin("pw_pump_0", x, SR, 611, False, "foley", "a pump gun racked", peak=-9.0)
    for k in range(2):
        r = np.random.default_rng(621 + k)
        secs = (1.4, 1.1)[k]
        n = int(secs * SR)
        t = np.arange(n) / SR
        f0 = (68.0, 58.0)[k] * (1.0 - 0.3 * D.ramp(t, secs))
        v = MA.voice(n, SR, r, f0, [(0, "uh"), (1, "u")], bw=(120.0, 160.0, 240.0), tilt=-1.6, rough=0.7, rough_hz=17.0, breath=0.6, jitter=0.05, env=D.ramp(t, 0.1) * D.ramp(secs - t, 0.7))
        fin("pw_rattle_%d" % k, v, SR, 621 + k, False, "foley", "a death rattle", peak=-11.0)


def foley():
    foley_steps()
    foley_doors()
    foley_hands()
    foley_build()
    foley_ui()
    foley_combat()


def tails():
    for k, (name, rt, echoes, hi) in enumerate((("pistol", 0.9, ((0.16, 0.5), (0.31, 0.25)), 3200.0), ("rifle", 1.5, ((0.2, 0.55), (0.37, 0.3), (0.62, 0.15)), 2600.0),
                                                 ("shotgun", 2.1, ((0.22, 0.6), (0.4, 0.38), (0.66, 0.22), (0.95, 0.1)), 2000.0))):
        r = np.random.default_rng(701 + k)
        n = int((rt + 1.4) * SR)
        t = np.arange(n) / SR
        lo = D.lowpass(r.standard_normal(n), 380.0, SR, 2, circular=False) * np.exp(-t / (rt * 0.35))
        mid = D.bandpass(r.standard_normal(n), 380.0, hi, SR, 2, circular=False) * np.exp(-t / (rt * 0.2))
        x = (lo * 0.9 + mid * 0.7) * D.ramp(t, 0.02)
        for at, g in echoes:
            i = int(at * SR)
            m = int(0.25 * SR)
            seg = D.lowpass(r.standard_normal(m), hi * 0.7, SR, 2, circular=False) * np.exp(-np.arange(m) / SR / 0.05) * g * 1.4
            x[i:i + m] += seg
        x *= 1.0 - D.ramp(t - (rt + 0.8), 0.6)
        fin("pt_tail_%d" % k, x, SR, 701 + k, False, "tail", "the echo of a %s off the compound's walls" % name, peak=-14.0)


# ------------------------------------------------------------------------------------------------ BARKS

def _scaled_vowels():
    for name in list(MA.VOWEL):
        if not name.endswith("_f"):
            MA.VOWEL[name + "_f"] = tuple(f * 1.17 for f in MA.VOWEL[name])


def barks():
    _scaled_vowels()
    for who, f0, vs, jit, extra_breath, gain in (("male", 105.0, "", 0.012, 0.0, 1.0), ("female", 205.0, "_f", 0.012, 0.0, 1.0), ("old", 122.0, "", 0.045, 0.18, 0.8)):
        seed = {"male": 801, "female": 811, "old": 821}[who]

        def v(n_, f, vows, **kw):
            r = np.random.default_rng(seed + int(kw.pop("salt", 0)))
            vows = [(a, b + vs) for a, b in vows]
            return MA.voice(n_, SR, r, f, vows, jitter=kw.pop("jitter", jit), **kw)

        def fk(secs, keys):
            return MA.path(int(secs * SR), SR, keys)

        # grunt
        n = int(0.3 * SR)
        f = f0 * 2.0 ** (fk(0.3, [(0, 0), (1, -5)]) / 12.0)
        y = v(n, f, [(0, "uh"), (1, "aw")], rough=0.25, breath=0.3 + extra_breath, env=MA.env_shape(n, SR, 0.02, 0.1), salt=1)
        fin("pv_%s_grunt" % who, y * gain, SR, seed + 1, False, "voice", "a grunt", peak=-12.0)
        # effort
        n = int(0.34 * SR)
        f = f0 * 2.0 ** (fk(0.34, [(0, 3), (0.3, 2), (1, -3)]) / 12.0)
        y = v(n, f, [(0, "ah"), (1, "aw")], rough=0.15, breath=0.35 + extra_breath, drive=1.5, env=MA.env_shape(n, SR, 0.01, 0.12), salt=2)
        fin("pv_%s_effort" % who, y * gain, SR, seed + 2, False, "voice", "a shout of effort", peak=-11.0)
        # pain
        n = int(0.62 * SR)
        t = np.arange(n) / SR
        f = f0 * 1.5 * 2.0 ** (fk(0.62, [(0, 4), (0.25, 5), (1, -1)]) / 12.0) * (1.0 + 0.02 * np.sin(TAU * 6.5 * t) * D.ramp(t - 0.15, 0.2))
        y = v(n, f, [(0, "ae"), (0.5, "ah"), (1, "aw")], rough=0.35, breath=0.3 + extra_breath, jitter=jit * 2.5, drive=1.3, env=MA.env_shape(n, SR, 0.02, 0.25), salt=3)
        fin("pv_%s_pain" % who, y * gain, SR, seed + 3, False, "voice", "a cry of pain", peak=-11.0)
        # gasp: an in-breath through a moving mouth
        r = np.random.default_rng(seed + 4)
        n = int(0.5 * SR)
        t = np.arange(n) / SR
        nz = r.standard_normal(n)
        lo_, hi_ = D.bandpass(nz, 500.0, 1500.0, SR, 2, circular=False), D.bandpass(nz, 1500.0, 4200.0, SR, 2, circular=False)
        mix = D.ramp(t, 0.35)
        y = (lo_ * (1 - mix) + hi_ * mix) * D.ramp(t, 0.28) * D.ramp(0.5 - t, 0.04)
        fin("pv_%s_gasp" % who, y * gain, SR, seed + 4, False, "voice", "a gasp", peak=-14.0)
        # cough: two bursts
        x = seq(0.55, SR)
        for at, salt in ((0.0, 5), (0.22, 6)):
            n = int(0.14 * SR)
            f = np.full(n, f0 * 0.9) * (1.0 - 0.15 * np.arange(n) / n)
            y = v(n, f, [(0, "ah"), (1, "uh")], rough=0.85, rough_hz=70.0, breath=0.9, drive=1.6, env=MA.env_shape(n, SR, 0.004, 0.06), salt=salt)
            put(x, y, at, SR, 1.0)
            put(x, noise_burst(0.05, 600.0, 3000.0, 0.012, SR, r, 0.001), at, SR, 0.6)
        fin("pv_%s_cough" % who, x * gain, SR, seed + 5, False, "voice", "a cough", peak=-12.0)
        # sob: three breathy pulses
        x = seq(1.3, SR)
        for i, at in enumerate((0.0, 0.4, 0.78)):
            n = int(0.3 * SR)
            f = f0 * 1.2 * 2.0 ** (fk(0.3, [(0, 0), (0.4, 2.5 + i), (1, -1)]) / 12.0)
            y = v(n, f, [(0, "uh"), (1, "uh")], rough=0.5, rough_hz=11.0, breath=0.7 + extra_breath, env=MA.env_shape(n, SR, 0.05, 0.12), salt=7 + i)
            put(x, y, at, SR, 0.8 - 0.1 * i)
            put(x, noise_burst(0.1, 600.0, 2400.0, 0.04, SR, r, 0.02), at + 0.3, SR, 0.25)
        fin("pv_%s_sob" % who, x * gain, SR, seed + 6, False, "voice", "sobbing", peak=-13.0)
        # whistle: two notes
        base = {"male": 1900.0, "female": 2400.0, "old": 1700.0}[who]
        x = seq(1.0, SR)
        for at, f1, f2 in ((0.0, 1.0, 1.25), (0.4, 1.25, 0.95)):
            n = int(0.38 * SR)
            t = np.arange(n) / SR
            f = base * (f1 + (f2 - f1) * D.ramp(t, 0.38)) * (1.0 + 0.012 * np.sin(TAU * 5.5 * t) * D.ramp(t - 0.08, 0.1))
            ph = TAU * np.cumsum(f) / SR
            y = np.sin(ph) * D.ramp(t, 0.04) * D.ramp(0.38 - t, 0.06)
            y += D.bandpass(r.standard_normal(n), base * 0.8, base * 1.5, SR, 2, circular=False) * 0.07 * D.ramp(t, 0.04) * D.ramp(0.38 - t, 0.06)
            put(x, y, at, SR, 0.8)
        fin("pv_%s_whistle" % who, x, SR, seed + 7, False, "voice", "a whistle", peak=-14.0)


GROUPS = {"music": music, "stingers": stingers, "ambience": ambience, "foley": foley, "tails": tails, "barks": barks}

if __name__ == "__main__":
    which = [a for a in sys.argv[1:] if not a.startswith("--")] or list(GROUPS)
    for g in which:
        GROUPS[g]()
