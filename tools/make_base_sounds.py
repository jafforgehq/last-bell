#!/usr/bin/env python3
"""The sounds of life at the base, for Thirty Bells: mono 16-bit WAVs in assets/audio/, made from arithmetic alone (NumPy,
tools/audio_dsp.py), a fixed seed for each, so a second run writes the same bytes. Guns, melee, hits, kills, reloads and casings
are NOT here (they are the combat sounds').

    python3 tools/make_base_sounds.py            # writes everything and updates audio_manifest.json
    python3 tools/make_base_sounds.py --check    # renders and prints, writes nothing
    python3 tools/make_base_sounds.py steps      # one group: steps gate doors hammer ui engine

    steps    step_dirt_0..2  step_concrete_0..2  step_wood_0..2     22.05 kHz, 0.2 s, peak -14 dBFS (a step is a quiet sound)
    gate     gate_lever_0 (the lever's clunk and the chain's rattle, 1.3 s), gate_slide_0 (a heavy gate on its rail, 2.4 s),
             gate_clang_0 (the leaves meeting their stop, 1.5 s)                                      22.05 kHz, peaks -6 dBFS
    doors    door_open_0 door_close_0 hatch_0                                                        22.05 kHz
    hammer   hammer_0..3 (a nail, a bench tap; hammer_0..1 are the files the map data names, 2..3 are added in sound.gd)
    ui       ui_hover_0 ui_card_0 ui_notify_0 ui_radio_call_0 ui_radio_on_0 ui_radio_off_0   44.1 kHz like the other menu sounds, peaks -9..-14
    engine   car_engine_loop (2.4 s idle, 25 firings a second: the game raises its pitch with the speed) and car_road_loop (3 s)

All of them are checked by number (level, length) rather than by ear.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as D  # noqa: E402

WRITE = "--check" not in sys.argv


def place(into, sound, at, gain=1.0):
    i = int(round(at * SR_NOW[0]))
    if i < 0:
        sound = sound[-i:]
        i = 0
    j = min(len(into), i + len(sound))
    if j > i:
        into[i:j] += gain * sound[:j - i]


SR_NOW = [22050]


def save(name, y, sr, seed, notes, peak_db, loop=False, kind="sfx", fade_end=0.02, rms_db=None):
    if fade_end and not loop:
        y = y * D.tail_off(len(y), sr, fade_end)
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


def burst(n, sr, rng, lo, hi, tau, circular=False):
    t = np.arange(n) / sr
    return D.bandpass(rng.standard_normal(n), lo, hi, sr, 2, circular=circular) * np.exp(-t / tau)


def tone(n, sr, f, tau, rng=None, phase=None):
    t = np.arange(n) / sr
    p = phase if phase is not None else (rng.uniform(0, D.TAU) if rng is not None else 0.0)
    return np.sin(D.TAU * f * t + p) * np.exp(-t / tau)


# ------------------------------------------------------------------------------------------------ footsteps

def steps():
    sr = 22050
    SR_NOW[0] = sr
    for k in range(3):
        # dirt and gravel: the weight, then a crunch of grains, then the toe
        rng = np.random.default_rng(700 + k)
        x = np.zeros(int(0.24 * sr))
        place(x, burst(int(0.07 * sr), sr, rng, 60.0, 260.0, 0.022), 0.0, 1.0)
        for g in range(int(rng.integers(5, 10))):
            at = rng.uniform(0.004, 0.11)
            place(x, burst(int(0.012 * sr), sr, rng, 1100.0, 4800.0, 0.003), at, rng.uniform(0.12, 0.45))
        place(x, burst(int(0.06 * sr), sr, rng, 80.0, 300.0, 0.02), 0.085 + 0.01 * k, 0.45)
        place(x, burst(int(0.05 * sr), sr, rng, 900.0, 3000.0, 0.012), 0.085 + 0.01 * k, 0.18)
        save("step_dirt_%d" % k, x, sr, 700 + k, "a step on dirt and gravel", -14.0)
    for k in range(3):
        # concrete: a heel click and a soft tok, a toe slap, a scuff
        rng = np.random.default_rng(710 + k)
        x = np.zeros(int(0.24 * sr))
        place(x, burst(int(0.02 * sr), sr, rng, 1400.0, 5200.0, 0.004), 0.0, 0.8)
        place(x, tone(int(0.07 * sr), sr, 130.0 + 12 * k, 0.025, rng), 0.0, 0.9)
        place(x, burst(int(0.015 * sr), sr, rng, 1000.0, 4200.0, 0.004), 0.085, 0.4)
        place(x, tone(int(0.06 * sr), sr, 110.0 + 10 * k, 0.02, rng), 0.085, 0.45)
        place(x, burst(int(0.09 * sr), sr, rng, 2200.0, 5200.0, 0.03), 0.02, 0.10)
        save("step_concrete_%d" % k, x, sr, 710 + k, "a step on concrete", -14.0)
    for k in range(3):
        # a wooden deck: a hollow knock (two resonances of the planks) and a tiny give
        rng = np.random.default_rng(720 + k)
        x = np.zeros(int(0.30 * sr))
        n = int(0.16 * sr)
        knock = tone(n, sr, 190.0 + 14 * k, 0.05, rng) + 0.6 * tone(n, sr, 410.0 + 25 * k, 0.035, rng) + 0.25 * tone(n, sr, 780.0, 0.02, rng)
        place(x, knock, 0.0, 0.9)
        place(x, burst(int(0.012 * sr), sr, rng, 700.0, 3500.0, 0.004), 0.0, 0.5)
        place(x, tone(int(0.12 * sr), sr, 205.0 + 10 * k, 0.04, rng) + 0.5 * tone(int(0.12 * sr), sr, 430.0, 0.03, rng), 0.09, 0.40)
        if k == 1:
            # a board gives: a very quiet short creak
            c = D.bandpass(rng.standard_normal(int(0.12 * sr)), 500.0, 1400.0, sr, 2, circular=False) * D.ramp(np.arange(int(0.12 * sr)) / sr, 0.05) * D.ramp(0.12 - np.arange(int(0.12 * sr)) / sr, 0.05)
            place(x, c, 0.1, 0.12)
        save("step_wood_%d" % k, x, sr, 720 + k, "a step on a wooden deck", -14.0)


# ------------------------------------------------------------------------------------------------ the gate

def gate():
    sr = 22050
    SR_NOW[0] = sr
    # --- the lever: a thunk of the handle, a ratchet, the chain, a clunk at the stop
    rng = np.random.default_rng(730)
    x = np.zeros(int(1.3 * sr))
    place(x, D.thump(sr, 120.0, 62.0, 0.25, 25.0, 0.07, 0.0, rng), 0.0, 0.9)
    place(x, D.clank(640.0, 0.30, sr, rng, 0.8), 0.0, 0.5)
    for i, at in enumerate((0.07, 0.115, 0.158)):
        place(x, burst(int(0.012 * sr), sr, rng, 1800.0, 5000.0, 0.002), at, 0.55 - 0.1 * i)
        place(x, tone(int(0.02 * sr), sr, 1500.0 + 150 * i, 0.004, rng), at, 0.3)
    # the chain: clinks, thinning out
    at = 0.18
    amp = 0.7
    while at < 1.0:
        f = rng.uniform(1700.0, 3300.0)
        place(x, D.clank(f, 0.07, sr, rng, 1.0), at, amp * rng.uniform(0.4, 1.0))
        at += rng.uniform(0.018, 0.06) * (1.0 + 2.0 * (at - 0.18))
        amp *= 0.965
    place(x, D.thump(sr, 100.0, 55.0, 0.25, 22.0, 0.08, 0.0, rng), 0.88, 0.75)
    place(x, D.clank(520.0, 0.30, sr, rng, 0.9), 0.88, 0.35)
    place(x, burst(int(0.015 * sr), sr, rng, 1500.0, 4800.0, 0.003), 0.88, 0.5)
    save("gate_lever_0", x, sr, 730, "the gate lever and its chain", -6.0)
    # --- the slide: a heavy steel gate on its rail
    rng = np.random.default_rng(731)
    secs = 2.4
    n = int(secs * sr)
    t = np.arange(n) / sr
    env = D.ramp(t, 0.18) * D.ramp(secs - t, 0.5) * (0.85 + 0.15 * np.sin(D.TAU * 0.9 * t))
    rumble = D.bandpass(rng.standard_normal(n), 40.0, 230.0, sr, 2, circular=False) * (1.0 + 0.4 * np.sin(D.TAU * 9.0 * t + 1.0)) * env
    wheels = np.zeros(n)
    at = 0.12
    while at < secs - 0.3:
        place(wheels, burst(int(0.014 * sr), sr, rng, 500.0, 2400.0, 0.004), at, rng.uniform(0.4, 1.0))
        at += (1.0 / 17.0) * rng.uniform(0.8, 1.25)
    wheels *= env
    squeal = np.zeros(n)
    for c in range(4):
        s0 = rng.uniform(0.2, 1.8)
        m = int(rng.uniform(0.18, 0.4) * sr)
        tt = np.arange(m) / sr
        f = rng.uniform(1300.0, 2300.0) * (1.0 + 0.12 * np.sin(D.TAU * rng.uniform(2.0, 5.0) * tt))
        sq = np.sin(D.TAU * np.cumsum(f) / sr) * D.ramp(tt, 0.05) * D.ramp(tt[-1] - tt, 0.08)
        sq += 0.3 * D.bandpass(rng.standard_normal(m), 1200.0, 3000.0, sr, 2, circular=False) * D.ramp(tt, 0.04)
        place(squeal, sq, s0, 0.12)
    stress = tone(int(0.5 * sr), sr, 330.0, 0.18, rng) * (1.0 + 0.4 * np.sin(D.TAU * 28.0 * np.arange(int(0.5 * sr)) / sr))
    y = rumble * 1.3 + wheels * 0.55 + squeal + np.pad(stress, (0, n - len(stress)))[:n] * 0.12
    save("gate_slide_0", y, sr, 731, "a heavy gate sliding on its rail", -7.0, fade_end=0.2)
    # --- the clang: the leaves meet their stop
    rng = np.random.default_rng(732)
    x = np.zeros(int(1.5 * sr))
    place(x, D.thump(sr, 105.0, 52.0, 0.4, 20.0, 0.1, 0.0, rng), 0.0, 1.0)
    place(x, D.clank(142.0, 1.2, sr, rng, 1.0), 0.0, 0.85)
    place(x, D.clank(231.0, 0.8, sr, rng, 0.7), 0.004, 0.5)
    place(x, D.clank(1250.0, 0.5, sr, rng, 0.5), 0.0, 0.35)
    place(x, burst(int(0.02 * sr), sr, rng, 1200.0, 5200.0, 0.004), 0.0, 0.7)
    place(x, D.clank(2900.0, 0.1, sr, rng, 0.8), 0.14, 0.3)    # the latch drops
    place(x, burst(int(0.012 * sr), sr, rng, 2000.0, 5500.0, 0.002), 0.14, 0.5)
    save("gate_clang_0", x, sr, 732, "the gate leaves meet their stop", -6.0, fade_end=0.3)


# ------------------------------------------------------------------------------------------------ doors

def doors():
    sr = 22050
    SR_NOW[0] = sr
    rng = np.random.default_rng(740)
    # a wooden door: the latch lifts, the hinge creaks, the door swings
    x = np.zeros(int(0.9 * sr))
    place(x, burst(int(0.015 * sr), sr, rng, 1800.0, 5000.0, 0.003), 0.0, 0.7)
    place(x, D.clank(1900.0, 0.06, sr, rng, 0.8), 0.0, 0.4)
    m = int(0.55 * sr)
    tt = np.arange(m) / sr
    f = 260.0 * (1.0 + 0.45 * tt / tt[-1]) * (1.0 + 0.08 * np.sin(D.TAU * 7.0 * tt))
    creak = np.sin(D.TAU * np.cumsum(f) / sr) + 0.5 * np.sin(D.TAU * np.cumsum(2.01 * f) / sr)
    creak *= (0.55 + 0.45 * np.sin(D.TAU * 41.0 * tt + 1.0)) * D.ramp(tt, 0.1) * D.ramp(tt[-1] - tt, 0.15)
    creak = D.bandpass(creak, 350.0, 2400.0, sr, 2, circular=False)
    place(x, creak, 0.06, 0.38)
    place(x, D.lowpass(rng.standard_normal(int(0.4 * sr)), 400.0, sr, 2, circular=False) * D.ramp(np.arange(int(0.4 * sr)) / sr, 0.1) * 0.5, 0.1, 0.2)
    save("door_open_0", x, sr, 740, "a wooden door opens", -9.0)
    rng = np.random.default_rng(741)
    x = np.zeros(int(0.6 * sr))
    place(x, D.thump(sr, 130.0, 60.0, 0.25, 24.0, 0.07, 0.0, rng), 0.0, 1.0)
    place(x, D.lowpass(rng.standard_normal(int(0.2 * sr)), 700.0, sr, 2, circular=False) * np.exp(-np.arange(int(0.2 * sr)) / sr / 0.05), 0.0, 0.4)
    place(x, burst(int(0.01 * sr), sr, rng, 1800.0, 4800.0, 0.002), 0.012, 0.5)
    place(x, D.clank(1700.0, 0.05, sr, rng, 0.8), 0.14, 0.3)    # the latch
    place(x, burst(int(0.01 * sr), sr, rng, 1800.0, 4800.0, 0.002), 0.14, 0.45)
    save("door_close_0", x, sr, 741, "a wooden door closes", -9.0)
    rng = np.random.default_rng(742)
    x = np.zeros(int(0.8 * sr))
    place(x, D.clank(330.0, 0.6, sr, rng, 1.0), 0.0, 0.8)
    place(x, D.thump(sr, 140.0, 70.0, 0.3, 22.0, 0.08, 0.0, rng), 0.0, 0.7)
    place(x, burst(int(0.02 * sr), sr, rng, 1500.0, 5000.0, 0.004), 0.0, 0.5)
    m = int(0.25 * sr)
    tt = np.arange(m) / sr
    squeak = np.sin(D.TAU * np.cumsum(1700.0 + 500.0 * tt / tt[-1]) / sr) * D.ramp(tt, 0.04) * D.ramp(tt[-1] - tt, 0.1) * (0.6 + 0.4 * np.sin(D.TAU * 33.0 * tt))
    place(x, squeak, 0.12, 0.10)
    save("hatch_0", x, sr, 742, "a metal hatch", -8.0, fade_end=0.1)


# ------------------------------------------------------------------------------------------------ hammer

def hammer():
    sr = 22050
    SR_NOW[0] = sr
    for k in range(4):
        rng = np.random.default_rng(750 + k)
        heavy = k >= 2
        x = np.zeros(int(0.22 * sr))
        body = 0.5 + 0.18 * k
        place(x, tone(int(0.12 * sr), sr, 520.0 + 90 * k, 0.020, rng), 0.0, 0.8 * (1.0 if not heavy else 1.2))
        place(x, tone(int(0.12 * sr), sr, 1380.0 + 130 * k, 0.012, rng), 0.0, 0.5)
        place(x, tone(int(0.1 * sr), sr, 3150.0 + 220 * k, 0.014, rng), 0.0, 0.28 if not heavy else 0.2)    # the nail's ring
        place(x, burst(int(0.008 * sr), sr, rng, 900.0, 5500.0, 0.0018), 0.0, 0.9)
        place(x, tone(int(0.07 * sr), sr, (150.0 if heavy else 210.0), 0.03, rng), 0.0, 0.6 * body)    # the wood under it
        save("hammer_%d" % k, x, sr, 750 + k, "a hammer on a nail", -8.0, fade_end=0.05)


# ------------------------------------------------------------------------------------------------ the menus and the radio

def ui():
    sr = 44100
    SR_NOW[0] = sr
    rng = np.random.default_rng(760)
    x = np.zeros(int(0.06 * sr))
    place(x, tone(int(0.04 * sr), sr, 2300.0, 0.006, rng), 0.0, 0.7)
    place(x, burst(int(0.01 * sr), sr, rng, 2000.0, 7000.0, 0.002), 0.0, 0.35)
    save("ui_hover_0", x, sr, 760, "a hover tick", -13.5, fade_end=0.01)
    rng = np.random.default_rng(761)
    secs = 0.3
    n = int(secs * sr)
    t = np.arange(n) / sr
    f = 700.0 + 2000.0 * D.ramp(t, secs * 0.9)
    sw = D.bandpass(rng.standard_normal(n), 600.0, 3600.0, sr, 2, circular=False) * np.sin(np.pi * np.clip(t / secs, 0, 1)) ** 1.5
    x = sw.copy()
    place(x, tone(int(0.04 * sr), sr, 420.0, 0.012, rng), 0.255, 0.55)
    place(x, burst(int(0.01 * sr), sr, rng, 1200.0, 4500.0, 0.002), 0.255, 0.35)
    save("ui_card_0", x, sr, 761, "a card slides onto the table", -11.0, fade_end=0.03)
    rng = np.random.default_rng(762)
    x = np.zeros(int(1.1 * sr))
    for at, f, g in ((0.0, D.hz("E5"), 0.8), (0.17, D.hz("A5"), 0.7)):
        n = int(0.9 * sr)
        place(x, tone(n, sr, f, 0.22, rng) + 0.35 * tone(n, sr, f * 2.0, 0.12, rng) + 0.12 * tone(n, sr, f * 3.01, 0.07, rng), at, g)
    save("ui_notify_0", x, sr, 762, "a soft two-note chime", -9.0, fade_end=0.2)
    rng = np.random.default_rng(763)
    x = np.zeros(int(0.7 * sr))
    for at in (0.0, 0.19):
        n = int(0.14 * sr)
        tt = np.arange(n) / sr
        tn = (np.sin(D.TAU * 880.0 * tt) + np.sin(D.TAU * 1319.0 * tt) * 0.8) * D.ramp(tt, 0.004) * D.ramp(tt[-1] - tt, 0.02)
        place(x, tn, at, 0.7)
    place(x, burst(int(0.07 * sr), sr, rng, 700.0, 3200.0, 0.03), 0.37, 0.18)
    x = np.tanh(1.8 * D.bandpass(x, 420.0, 3400.0, sr, 2, circular=False))
    save("ui_radio_call_0", x, sr, 763, "the radio's call tone", -9.0, fade_end=0.04)
    rng = np.random.default_rng(764)
    x = np.zeros(int(0.09 * sr))
    place(x, burst(int(0.05 * sr), sr, rng, 600.0, 3400.0, 0.012), 0.0, 0.7)
    place(x, tone(int(0.02 * sr), sr, 1200.0, 0.004, rng), 0.0, 0.5)
    save("ui_radio_on_0", x, sr, 764, "push to talk: the click and a breath of static", -11.0, fade_end=0.01)
    rng = np.random.default_rng(765)
    x = np.zeros(int(0.16 * sr))
    place(x, burst(int(0.12 * sr), sr, rng, 500.0, 3600.0, 0.03), 0.0, 0.6)
    place(x, tone(int(0.02 * sr), sr, 900.0, 0.004, rng), 0.0, 0.3)
    place(x, burst(int(0.008 * sr), sr, rng, 1500.0, 5000.0, 0.002), 0.0, 0.5)
    save("ui_radio_off_0", x, sr, 765, "release: a squelch tail", -12.0, fade_end=0.03)


# ------------------------------------------------------------------------------------------------ the pickup truck

def engine():
    sr = 22050
    SR_NOW[0] = sr
    rng = np.random.default_rng(770)
    secs = 2.4
    n = int(secs * sr)
    t = np.arange(n) / sr
    fire_hz = 25.0
    count = int(round(secs * fire_hz))
    x = np.zeros(n)
    for i in range(count):
        at = (i + rng.uniform(-0.04, 0.04)) / fire_hz
        f0 = 70.0 + 22.0 * rng.random() + (8.0 if i % 2 else 0.0)
        m = int(0.07 * sr)
        tt = np.arange(m) / sr
        pulse = (np.sin(D.TAU * f0 * tt) + 0.5 * np.sin(D.TAU * 2.0 * f0 * tt + 0.8) + 0.25 * np.sin(D.TAU * 3.0 * f0 * tt)) * np.exp(-tt / 0.022)
        puff = D.lowpass(rng.standard_normal(m), 700.0, sr, 2, circular=False) * np.exp(-tt / 0.012) * 2.2
        g = rng.uniform(0.82, 1.15) * (0.9 if i % 2 else 1.0)
        # a pulse that runs past the end wraps to the start: the loop closes
        s = (pulse + puff) * g
        k = int(round(at * sr)) % n
        j = min(n - k, m)
        x[k:k + j] += s[:j]
        if j < m:
            x[:m - j] += s[j:]
    x = np.tanh(1.5 * x)
    tick = D.highpass(rng.standard_normal(n), 2800.0, sr, 2) * (0.5 + 0.5 * np.sin(D.TAU * 12.5 * t)) ** 8 * 0.06
    body = D.lowpass(rng.standard_normal(n), 190.0, sr, 2) * 0.55
    y = x + tick + body
    y = D.lowpass(y, 5200.0, sr, 2)
    save("car_engine_loop", y - np.mean(y), sr, 770, "a pickup's idle (raise the pitch with the speed)", -9.0, loop=True, kind="engine", rms_db=-19.0)
    rng = np.random.default_rng(771)
    secs = 3.0
    n = int(secs * sr)
    road = D.bandpass(D.colored(n, rng, -1.0, sr), 140.0, 1900.0, sr, 2)
    road = road * (0.85 + 0.15 * D.swell_cycles(n, sr, secs, 3))
    rumble = D.bandpass(rng.standard_normal(n), 30.0, 120.0, sr, 2) * 0.8
    y = road / (np.std(road) + 1e-9) + rumble / (np.std(rumble) + 1e-9) * 0.5
    save("car_road_loop", y - np.mean(y), sr, 771, "road and tyre noise (louder with the speed)", -12.0, loop=True, kind="engine", rms_db=-24.0)


GROUPS = {"steps": steps, "gate": gate, "doors": doors, "hammer": hammer, "ui": ui, "engine": engine}

if __name__ == "__main__":
    which = [a for a in sys.argv[1:] if not a.startswith("--")] or list(GROUPS)
    for g in which:
        GROUPS[g]()
