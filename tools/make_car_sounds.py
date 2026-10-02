#!/usr/bin/env python3
"""Synthesises the sounds of a car trip (round 15): four mono 16-bit 44.1 kHz WAVs in assets/audio/.

    car_door_open.wav     the latch's tick, the rubber seal letting go, the door check stopping the door (about 0.55 s)
    car_door_close.wav    a solid clunk: a low thump, the panel ringing, a metallic tick and the latch's click (0.65 s)
    car_engine_start.wav  a starter cranking, the engine catching, a flare and an idle that dies away (2.5 s)
    car_gate_motor.wav    the electric whine of a sliding gate with its rollers rattling and the clack at the stop (1.5 s)

Nothing is downloaded or recorded: every sample comes from NumPy with a fixed seed, so running this again writes the
same files. The levels are set afterwards by tools/level_sounds.py (its LEVELS table has these names at -8 dBFS; the
files here are written at that peak already). They are played through scripts/audio/sound.gd (`CAR_SOUNDS`,
sound.play("car_door_open")). Run from the repository root:

    python3 tools/make_car_sounds.py            # writes assets/audio/car_*.wav
    python3 tools/make_car_sounds.py --check    # only prints the numbers, writes nothing

After adding or changing files, let Godot import them once:
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
"""
import os
import sys
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
PEAK = 10.0 ** (-8.0 / 20.0)  # -8 dBFS


# ---------------------------------------------------------------------------------------------- the tools --

def axis(seconds):
    return np.arange(int(round(SR * seconds))) / SR


def rise(t, seconds):
    return np.minimum(1.0, t / max(seconds, 1e-6))


def lowpass(x, fc):
    """One pole low-pass."""
    a = 1.0 - np.exp(-2.0 * np.pi * fc / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(x.size):
        s += a * (x[i] - s)
        y[i] = s
    return y


def highpass(x, fc):
    return x - lowpass(x, fc)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def place(into, sound, at_seconds, gain=1.0):
    i = int(round(at_seconds * SR))
    if i >= into.size:
        return
    j = min(into.size, i + sound.size)
    into[i:j] += gain * sound[: j - i]


def ring(freq, seconds, tau, phase=0.0):
    """A damped sine: a panel or a latch ringing."""
    t = axis(seconds)
    return np.sin(2.0 * np.pi * freq * t + phase) * np.exp(-t / tau) * rise(t, 0.0004)


def tick(seconds, tau, lo, rng):
    """A metallic tick: a burst of noise with its low end taken off."""
    t = axis(seconds)
    n = rng.standard_normal(t.size) * np.exp(-t / tau)
    return highpass(n, lo) * rise(t, 0.0002)


def thump(f_hi, f_lo, seconds, tau):
    """A low thump: a sine that sags in pitch."""
    t = axis(seconds)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / 0.018)
    return np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau) * rise(t, 0.0008)


def panel(seconds, rng, scale=1.0):
    """A sheet-metal door ringing: a few modes, the higher ones dying sooner."""
    out = np.zeros(int(SR * seconds))
    for f, a, tau, ph in ((172.0, 0.55, 0.11, 0.3), (268.0, 0.42, 0.085, 1.1), (413.0, 0.28, 0.06, 2.0), (694.0, 0.17, 0.04, 0.7), (1130.0, 0.08, 0.025, 1.9)):
        r = ring(f, seconds, tau * scale, ph)
        out += a * r
    return out


def finish(x, peak=PEAK):
    """No DC, a click-free start and end, scaled to `peak` (0 to 1), as 16-bit."""
    x = x - np.mean(x)
    n = x.size
    a = min(int(0.0008 * SR), n // 4)
    b = min(int(0.012 * SR), n // 2)
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[-b:] *= np.linspace(1.0, 0.0, b)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    return np.round(x * 32767.0).astype(np.int16)


# ---------------------------------------------------------------------------------------------- the sounds --

def car_door_open():
    rng = np.random.default_rng(101)
    x = np.zeros(int(SR * 0.58))
    # the latch lets go: a tick and a small knock
    place(x, tick(0.03, 0.004, 1800.0, rng), 0.0, 0.55)
    place(x, ring(1900.0, 0.03, 0.006), 0.0, 0.18)
    place(x, thump(150.0, 95.0, 0.08, 0.02), 0.0, 0.30)
    # the rubber seal peels away and the hinge takes the weight: a soft swish
    t = axis(0.30)
    swish = bandpass(rng.standard_normal(t.size), 600.0, 2600.0)
    swish /= np.max(np.abs(swish)) + 1e-9
    env = np.sin(np.pi * np.clip(t / 0.30, 0.0, 1.0)) ** 1.6
    place(x, swish * env, 0.015, 0.17)
    # the check strap stops the door: a dull stop
    place(x, thump(120.0, 80.0, 0.14, 0.045), 0.325, 0.62)
    place(x, panel(0.2, rng, 0.7), 0.325, 0.16)
    place(x, tick(0.02, 0.003, 1500.0, rng), 0.325, 0.22)
    return finish(x)


def car_door_close():
    rng = np.random.default_rng(103)
    x = np.zeros(int(SR * 0.66))
    # the weight of the door against the seal
    place(x, thump(74.0, 46.0, 0.30, 0.075), 0.0, 1.0)
    # the sheet metal rings
    place(x, panel(0.5, rng), 0.0, 0.55)
    # the edge meeting the body: a metallic tick
    place(x, tick(0.03, 0.0045, 1800.0, rng), 0.0, 0.60)
    # the latch: two small clicks a moment later, the second smaller
    place(x, tick(0.012, 0.0014, 3000.0, rng), 0.014, 0.42)
    place(x, ring(2650.0, 0.02, 0.004), 0.014, 0.16)
    place(x, tick(0.01, 0.0012, 3200.0, rng), 0.029, 0.26)
    place(x, ring(2150.0, 0.02, 0.004), 0.029, 0.09)
    # the loose things in the door settle: a short rattle
    t = axis(0.26)
    rattle = bandpass(rng.standard_normal(t.size), 800.0, 3200.0)
    rattle /= np.max(np.abs(rattle)) + 1e-9
    gate = (np.sin(2.0 * np.pi * 37.0 * t + 1.0) > 0.35).astype(float)
    place(x, rattle * gate * np.exp(-t / 0.07), 0.05, 0.10)
    return finish(x)


def car_engine_start():
    rng = np.random.default_rng(107)
    seconds = 2.5
    t = axis(seconds)
    n = t.size
    catch = 1.18    # the engine takes
    # --- the starter: a whine that pulses with each compression stroke
    crank_rate = 5.6 + 1.6 * np.clip(t / catch, 0.0, 1.0)      # compressions a second
    crank_phase = np.cumsum(crank_rate) / SR
    stroke = 0.55 + 0.45 * np.sin(2.0 * np.pi * crank_phase - 1.2) ** 2
    f_motor = (205.0 + 55.0 * np.clip(t / catch, 0.0, 1.0)) * (1.0 + 0.04 * np.sin(2.0 * np.pi * crank_phase - 0.4))
    ph = 2.0 * np.pi * np.cumsum(f_motor) / SR
    whine = sum(np.sin(k * ph + 0.7 * k) / k ** 1.1 for k in range(1, 9))
    whine += 0.5 * np.sin(3.17 * ph)   # a gear mesh tone
    starter_env = np.where(t < catch + 0.10, 1.0, np.exp(-(t - catch - 0.10) / 0.07)) * rise(t, 0.05)
    starter = whine * stroke * starter_env
    # the chug of the compressions: a low thud on each stroke while it cranks
    chug = np.zeros(n)
    beats = np.where(np.diff(np.floor(crank_phase)) > 0)[0]
    kern = thump(88.0, 52.0, 0.09, 0.03)
    for b in beats:
        if t[b] < catch + 0.2:
            place(chug, kern, b / SR, 0.7 + 0.2 * rng.random())
    # --- the engine: firing pulses whose rate follows the revs (a catch, a flare, a settle to idle)
    rpm = np.where(t < catch, 0.0, 0.0)
    u = np.clip(t - catch, 0.0, None)
    rpm = 430.0 + 1250.0 * (1.0 - np.exp(-u / 0.10)) * np.exp(-u / 0.55) + 450.0 * np.exp(-u / 0.9)
    rpm += 12.0 * np.sin(2.0 * np.pi * 1.7 * t) + 8.0 * np.sin(2.0 * np.pi * 4.3 * t + 2.0)
    fire_phase = np.cumsum(2.0 * rpm / 60.0) / SR      # four cylinders: two firings a turn
    fires = np.where(np.diff(np.floor(fire_phase)) > 0)[0]
    engine = np.zeros(n)
    for k, i in enumerate(fires):
        ti = t[i]
        if ti < catch:
            continue
        # the first strokes after the catch misfire now and then
        since = ti - catch
        if since < 0.35 and rng.random() < 0.55 * (1.0 - since / 0.35):
            continue
        f0 = 78.0 + 12.0 * rng.random() + 14.0 * np.exp(-since / 0.4)
        length = 0.045
        tt = axis(length)
        pulse = (np.sin(2.0 * np.pi * f0 * tt) + 0.5 * np.sin(4.0 * np.pi * f0 * tt + 0.8)) * np.exp(-tt / 0.016)
        puff = lowpass(rng.standard_normal(tt.size), 700.0) * np.exp(-tt / 0.008) * 3.0
        place(engine, (pulse + puff) * (0.85 + 0.3 * rng.random()), ti, 1.0)
    engine = np.tanh(1.6 * engine)   # an exhaust is never clean: a little grit
    ticking = highpass(rng.standard_normal(n), 2500.0) * (0.5 + 0.5 * np.sin(2.0 * np.pi * (rpm / 60.0) * t)) ** 6 * 0.12
    bed = lowpass(rng.standard_normal(n), 220.0) * 0.5
    eng_env = rise(np.clip(t - catch + 0.02, 0.0, None), 0.08)
    # the tail: the idle dies away over the last half second (the sound ends in silence, never cut)
    tail = np.where(t > 1.95, 0.5 * (1.0 + np.cos(np.pi * np.clip((t - 1.95) / 0.55, 0.0, 1.0))), 1.0)
    x = 0.55 * starter + 0.9 * chug + (engine + ticking + bed * 0.5) * eng_env * tail * 1.3
    return finish(x)


def car_gate_motor():
    rng = np.random.default_rng(109)
    seconds = 1.5
    t = axis(seconds)
    n = t.size
    # the motor: it spins up, hums, winds down at the end
    spin = np.minimum(rise(t, 0.2), np.clip((seconds - 0.09 - t) / 0.12, 0.0, 1.0) * 0.4 + 0.6)
    spin = np.where(t > seconds - 0.12, np.clip((seconds - t) / 0.12, 0.0, 1.0) * 0.6, spin)
    f = (95.0 + 105.0 * spin) * (1.0 + 0.012 * np.sin(2.0 * np.pi * 6.0 * t))
    ph = 2.0 * np.pi * np.cumsum(f) / SR
    motor = sum(np.sin(k * ph + 0.9 * k) / k ** 1.25 for k in range(1, 11))
    motor += 0.45 * np.sin(4.1 * ph)               # the gearbox's own whine
    motor *= 0.5 + 0.5 * rise(t, 0.15)
    # the rollers on the rail: a rattle of small clicks, a little irregular
    rattle = np.zeros(n)
    at = 0.12
    while at < seconds - 0.14:
        f_res = 900.0 + 1400.0 * rng.random()
        tt = axis(0.012)
        click = np.sin(2.0 * np.pi * f_res * tt) * np.exp(-tt / 0.0025) + 0.4 * highpass(rng.standard_normal(tt.size), 1500.0) * np.exp(-tt / 0.002)
        place(rattle, click, at, 0.4 + 0.6 * rng.random())
        at += (1.0 / 31.0) * (0.7 + 0.6 * rng.random())
    rumble = lowpass(rng.standard_normal(n), 140.0) * 6.0 * rise(t, 0.12)
    x = 0.42 * motor + 0.55 * rattle + 0.18 * rumble
    # the gate reaches its stop: a clunk and a bit of ringing
    place(x, thump(120.0, 70.0, 0.14, 0.04), seconds - 0.115, 0.75)
    place(x, panel(0.12, rng, 0.5), seconds - 0.115, 0.22)
    place(x, tick(0.015, 0.003, 1800.0, rng), seconds - 0.115, 0.28)
    return finish(x)


SOUNDS = {
    "car_door_open": car_door_open,
    "car_door_close": car_door_close,
    "car_engine_start": car_engine_start,
    "car_gate_motor": car_gate_motor,
}


def write(name, samples):
    path = os.path.join(OUT, "%s.wav" % name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(samples.tobytes())
    return path


def main():
    check_only = "--check" in sys.argv
    print("%-18s %8s %8s %8s" % ("sound", "seconds", "peak dB", "rms dB"))
    for name, make in SOUNDS.items():
        s = make()
        f = s.astype(np.float64) / 32767.0
        peak = 20.0 * np.log10(np.max(np.abs(f)) + 1e-12)
        rms = 20.0 * np.log10(np.sqrt(np.mean(f * f)) + 1e-12)
        print("%-18s %8.3f %8.1f %8.1f" % (name, s.size / SR, peak, rms))
        if not check_only:
            write(name, s)
    if not check_only:
        print("written to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
