#!/usr/bin/env python3
"""Synthesises the sounds of fighting (the polish wave, P-COMBAT): mono 16-bit 44.1 kHz WAVs in assets/audio/.

    shot_pistol_0..1      a 9 mm: a bright slap, a short low pop, a little room (0.38 s)
    shot_rifle_0..2       the carbine: a hard crack, a chest thump and a slap-back echo (0.55 s)
    shot_service_0        the M1: a heavier crack with a ring of steel in it (0.65 s)
    shot_hunting_0        the hunting rifle: deep and long, three echoes (1.0 s)
    shot_shotgun_0..1     the pump gun: a wall of low boom, a hiss of pellets, a long room (0.9 s)
    hit_flesh_0..2        a bullet in the dead: a wet thump (0.22 s)
    hit_plate_0..2        a bullet on a brute's steel: a ring of inharmonic partials (0.5 s)
    hit_wall_0..1         a bullet stopped by a wall: a dull knock and a ricochet's zing (0.3 s)
    melee_swing_0..1      a blow in the air: a whoosh (0.22 s)
    melee_hit_0..1        a blow that lands: a thwack (0.25 s)
    thud_0..1             one of the dead coming down: a body's weight (0.35 s; replaces the baked ones)
    dry_click_0           the hammer falling on nothing (0.08 s)
    mag_out_0, mag_in_0   a magazine let go of and pushed home (0.2 s each)
    bolt_0                the slide or bolt going forward (0.25 s)
    shell_in_0..1         a shell into the tube (0.14 s)
    pump_0                the pump's two clacks (0.34 s)
    casing_0..1           brass tinkling on the ground (0.16 s)

Nothing is downloaded or recorded: every sample is made from NumPy with a fixed seed, so running this again writes the same files. A gunshot is
four layers on top of each other, as a real one is heard: a click and a crack (the bright noise, a few thousandths of a second), a thump (a
sine that falls from a few hundred hertz to a few tens), a boom (the noise between 100 and 1000 Hz) and the room (a low-passed tail with
echoes), pressed together by a soft clip so that it is loud for its peak. Peaks are set per sound (PEAKS below; shots are near -3 dBFS) and
tools/level_sounds.py has the same table. Run from the repository root:

    python3 tools/make_combat_sounds.py            # writes assets/audio/*.wav (and prints each one's peak, RMS and length)
    python3 tools/make_combat_sounds.py --check    # only prints the numbers, writes nothing

After adding or changing files, let Godot import them once:
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
"""
import os
import sys
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")

# peak level in dBFS by file stem
PEAKS = {
    "shot_pistol": -4.0,
    "shot_rifle": -3.5,
    "shot_service": -3.5,
    "shot_hunting": -3.0,
    "shot_shotgun": -3.0,
    "hit_flesh": -9.0,
    "hit_plate": -6.0,
    "hit_wall": -10.0,
    "melee_swing": -10.0,
    "melee_hit": -7.0,
    "thud": -8.0,
    "dry_click": -8.0,
    "mag_out": -9.0,
    "mag_in": -7.0,
    "bolt": -8.0,
    "shell_in": -9.0,
    "pump": -5.0,
    "casing": -14.0,
}


# ---------------------------------------------------------------------------------------------- the tools --

def axis(seconds):
    return np.arange(int(round(SR * seconds))) / SR


def rise(t, seconds):
    return np.minimum(1.0, t / max(seconds, 1e-6))


def lowpass(x, fc, passes=1):
    """A one-pole low-pass (applied `passes` times: steeper), by convolution with its own impulse response."""
    a = 1.0 - np.exp(-2.0 * np.pi * fc / SR)
    klen = int(min(x.size, max(8, 9.2 / a)))
    h = a * (1.0 - a) ** np.arange(klen)
    y = x
    for _ in range(passes):
        y = np.convolve(y, h)[: x.size]
    return y


def highpass(x, fc, passes=1):
    return x - lowpass(x, fc, passes)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi, 2), lo, 2)


def noise(n, rng):
    return rng.standard_normal(n)


def ring(freq, seconds, tau, phase=0.0, attack=0.0004):
    """A damped sine: a metal part ringing."""
    t = axis(seconds)
    return np.sin(2.0 * np.pi * freq * t + phase) * np.exp(-t / tau) * rise(t, attack)


def thump(seconds, f0, f1, tau, sweep=0.6):
    """A sine that falls from f0 to f1 (its pitch gives way in `tau * sweep` seconds) and dies away in tau."""
    t = axis(seconds)
    f = f1 + (f0 - f1) * np.exp(-t / (tau * sweep))
    phase = 2.0 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.exp(-t / tau) * rise(t, 0.0008)


def burst(seconds, tau, rng, lo=None, hi=None):
    """A decaying burst of noise, optionally band-limited."""
    t = axis(seconds)
    n = noise(t.size, rng) * np.exp(-t / tau) * rise(t, 0.0002)
    if hi is not None:
        n = lowpass(n, hi, 2)
    if lo is not None:
        n = highpass(n, lo, 2)
    return n


def mix(*parts):
    """The parts added up (each may be a different length: the sum is as long as the longest)."""
    n = max(p.size for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: p.size] += p
    return out


def place(into, sound, at_seconds, gain=1.0):
    i = int(round(at_seconds * SR))
    if i >= into.size:
        return
    j = min(into.size, i + sound.size)
    into[i:j] += gain * sound[: j - i]


def finish(x, peak_db, drive=0.0, fade=0.01, limit=0.0):
    """Clip the tallest peaks off (when `limit`: the click of a shot is a few samples tall, and left alone it leaves the body of the sound
    quiet under it), soft clip (when `drive`), fade the end out, and scale to the peak."""
    if limit > 0.0:
        pk = np.max(np.abs(x)) * limit
        x = np.clip(x, -pk, pk)
    if drive > 0.0:
        x = np.tanh(drive * x / max(np.max(np.abs(x)), 1e-9))
    nf = int(fade * SR)
    if nf > 0:
        x = x.copy()
        x[-nf:] *= np.linspace(1.0, 0.0, nf)
    return x / max(np.max(np.abs(x)), 1e-9) * (10.0 ** (peak_db / 20.0))


# ----------------------------------------------------------------------------------------------- the guns --

def gunshot(rng, dur, crack, thump_spec, boom, tail, echoes, extra=None, sizzle=0.0, drive=2.4):
    """The layers of a shot: crack = (tau, lo, hi, gain), thump_spec = (f0, f1, tau, gain), boom = (tau, lo, hi, gain),
    tail = (tau, low-pass, gain), echoes = [(delay, gain, low-pass)]; `sizzle` the hiss of a spread of pellets."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    # the click and the crack
    ctau, clo, chi, cg = crack
    click = noise(n, rng) * np.exp(-t / 0.0005)
    click = highpass(click, 3000.0, 2)
    out += click * 0.9
    out += bandpass(noise(n, rng) * np.exp(-t / ctau) * rise(t, 0.0002), clo, chi) * cg * 2.2
    if sizzle > 0.0:
        out += bandpass(noise(n, rng) * np.exp(-t / 0.05), 1800.0, 7000.0) * sizzle * 2.0
    # the thump
    f0, f1, ttau, tg = thump_spec
    th = thump(dur, f0, f1, ttau)
    out += th[:n] * tg * 1.4
    # the boom
    btau, blo, bhi, bg = boom
    out += bandpass(noise(n, rng) * np.exp(-t / btau) * rise(t, 0.0015), blo, bhi) * bg * 3.0
    # the room
    ttau2, tlp, tg2 = tail
    out += lowpass(noise(n, rng), tlp, 2) * np.exp(-t / ttau2) * rise(t, 0.006) * tg2 * 2.4
    # the echoes (a copy of what came before, dull, later and softer)
    dry = out.copy()
    for delay, gain, lp in echoes:
        place(out, lowpass(dry, lp, 2), delay, gain)
    if extra is not None:
        out += extra[:n] if extra.size >= n else np.pad(extra, (0, n - extra.size))
    return finish(out, 0.0, drive=drive, fade=0.03, limit=0.42)


def vary(rng, base, spread=0.12):
    """A parameter wobbled a little, so that the variations of one gun are not the same shot."""
    return base * (1.0 + (rng.random() - 0.5) * 2.0 * spread)


def make_pistol(i):
    rng = np.random.default_rng(100 + i)
    return gunshot(rng, 0.38,
                   crack=(vary(rng, 0.0065), 1800.0, 9000.0, 1.5),
                   thump_spec=(vary(rng, 320.0), 110.0, vary(rng, 0.035), 0.45),
                   boom=(0.05, 250.0, 1400.0, 0.8),
                   tail=(0.07, 2500.0, 0.10),
                   echoes=[(0.045, 0.18, 3500.0), (0.11, 0.08, 2500.0)],
                   drive=3.6)


def make_rifle(i):
    rng = np.random.default_rng(200 + i)
    return gunshot(rng, 0.55,
                   crack=(vary(rng, 0.010), 1500.0, 8000.0, 1.5),
                   thump_spec=(vary(rng, 220.0), 80.0, vary(rng, 0.06), 0.4),
                   boom=(0.09, 150.0, 1100.0, 1.0),
                   tail=(0.12, 1800.0, 0.2),
                   echoes=[(0.06, 0.28, 3000.0), (0.15, 0.15, 2200.0), (0.28, 0.07, 1600.0)],
                   drive=3.6)


def make_service():
    rng = np.random.default_rng(300)
    t = axis(0.65)
    ping = ring(3300.0, 0.65, 0.09) * 0.10 + ring(4950.0, 0.65, 0.05) * 0.04
    return gunshot(rng, 0.65,
                   crack=(0.011, 1400.0, 7500.0, 1.5),
                   thump_spec=(190.0, 70.0, 0.07, 0.45),
                   boom=(0.10, 130.0, 1000.0, 1.1),
                   tail=(0.16, 1700.0, 0.22),
                   echoes=[(0.07, 0.30, 2800.0), (0.17, 0.17, 2000.0), (0.31, 0.09, 1500.0)],
                   extra=ping * np.exp(-t / 0.2), drive=3.6)


def make_hunting():
    rng = np.random.default_rng(400)
    return gunshot(rng, 1.0,
                   crack=(0.014, 1200.0, 6500.0, 1.4),
                   thump_spec=(150.0, 55.0, 0.12, 0.6),
                   boom=(0.16, 100.0, 850.0, 1.2),
                   tail=(0.26, 1400.0, 0.28),
                   echoes=[(0.09, 0.35, 2500.0), (0.21, 0.22, 1800.0), (0.40, 0.12, 1300.0), (0.62, 0.06, 1000.0)],
                   drive=3.8)


def make_shotgun(i):
    rng = np.random.default_rng(500 + i)
    return gunshot(rng, 0.9,
                   crack=(vary(rng, 0.016), 900.0, 7000.0, 1.5),
                   thump_spec=(vary(rng, 135.0), 48.0, vary(rng, 0.13), 0.65),
                   boom=(0.2, 90.0, 800.0, 1.3),
                   tail=(0.32, 1500.0, 0.3),
                   echoes=[(0.07, 0.30, 2200.0), (0.17, 0.20, 1700.0), (0.33, 0.12, 1300.0), (0.55, 0.05, 1000.0)],
                   sizzle=0.7, drive=4.2)


# ---------------------------------------------------------------------------------------------- the hits --

def make_hit_flesh(i):
    rng = np.random.default_rng(600 + i)
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    out = thump(0.22, vary(rng, 200.0), 85.0, 0.025)[:n] * 0.5
    out += bandpass(noise(n, rng), 200.0, 2500.0) * np.exp(-t / 0.04) * rise(t, 0.001) * 2.2
    out += burst(0.22, 0.003, rng, lo=1500.0)[:n] * 0.4
    return finish(out, 0.0, drive=1.5, fade=0.02)


def make_hit_plate(i):
    rng = np.random.default_rng(700 + i)
    n = int(SR * 0.5)
    f0 = [780.0, 860.0, 940.0][i]
    out = np.zeros(n)
    for ratio, tau, gain in [(1.0, 0.12, 1.0), (1.59, 0.09, 0.7), (2.14, 0.07, 0.5), (2.65, 0.05, 0.4), (3.51, 0.035, 0.3)]:
        out += ring(f0 * ratio, 0.5, tau, phase=rng.random() * 6.28)[:n] * gain
    out += burst(0.5, 0.004, rng, lo=2000.0)[:n] * 0.8
    out += thump(0.5, 250.0, 120.0, 0.015)[:n] * 0.5
    return finish(out, 0.0, drive=1.3, fade=0.04)


def make_hit_wall(i):
    rng = np.random.default_rng(800 + i)
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    out = lowpass(noise(n, rng), 1200.0, 2) * np.exp(-t / 0.02) * 1.5
    f = 3200.0 - (3200.0 - 1400.0) * np.minimum(1.0, t / 0.18)
    out += np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09) * rise(t, 0.004) * 0.25
    out += burst(0.3, 0.003, rng, lo=2500.0)[:n] * 0.4
    return finish(out, 0.0, drive=1.3, fade=0.03)


def make_melee_swing(i):
    rng = np.random.default_rng(900 + i)
    dur = 0.22
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for centre, lo, hi in [(0.25, 400.0, 900.0), (0.5, 800.0, 1800.0), (0.75, 1500.0, 3500.0)]:
        env = np.exp(-((t / dur - centre) ** 2) / (2.0 * 0.15 ** 2))
        out += bandpass(noise(n, rng), lo, hi) * env
    out *= np.sin(np.pi * np.minimum(1.0, t / dur)) ** 2
    return finish(out, 0.0, drive=0.0, fade=0.03)


def make_melee_hit(i):
    rng = np.random.default_rng(1000 + i)
    n = int(SR * 0.25)
    t = np.arange(n) / SR
    out = bandpass(noise(n, rng), 200.0, 2200.0) * np.exp(-t / 0.02) * 2.0
    out += thump(0.25, vary(rng, 240.0), 100.0, 0.03)[:n] * 0.5
    out += burst(0.25, 0.002, rng, lo=2000.0)[:n] * 0.6
    return finish(out, 0.0, drive=1.6, fade=0.03)


def make_thud(i):
    rng = np.random.default_rng(1100 + i)
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    out = thump(0.35, vary(rng, 170.0), 70.0, 0.06)[:n] * 0.4
    out += bandpass(noise(n, rng), 130.0, 800.0) * np.exp(-t / 0.07) * rise(t, 0.003) * 2.6
    out += bandpass(noise(n, rng), 300.0, 2500.0) * np.exp(-t / 0.012) * 1.0
    place(out, thump(0.2, 120.0, 60.0, 0.04)[: int(SR * 0.2)] * 0.6 + bandpass(noise(int(SR * 0.2), rng), 150.0, 600.0) * np.exp(-axis(0.2) / 0.05) * 0.8, 0.09, 0.5)
    return finish(out, 0.0, drive=1.4, fade=0.04)


# ------------------------------------------------------------------------------------- the hands and the brass --

def make_dry_click():
    rng = np.random.default_rng(1200)
    n = int(SR * 0.08)
    out = np.zeros(n)
    place(out, mix(highpass(burst(0.03, 0.003, rng), 2500.0, 2) * 1.0, ring(1900.0, 0.03, 0.012) * 0.5), 0.0)
    place(out, mix(highpass(burst(0.03, 0.002, rng), 2500.0, 2) * 0.5, ring(2300.0, 0.03, 0.008) * 0.25), 0.028)
    return finish(out, 0.0, fade=0.01)


def make_mag_out():
    rng = np.random.default_rng(1300)
    n = int(SR * 0.2)
    out = np.zeros(n)
    place(out, mix(ring(2200.0, 0.06, 0.006), highpass(burst(0.05, 0.004, rng), 1500.0) * 0.6), 0.0)
    place(out, bandpass(noise(int(SR * 0.12), rng), 1000.0, 4000.0) * 0.12 * np.sin(np.linspace(0, np.pi, int(SR * 0.12))), 0.03)
    place(out, mix(ring(1700.0, 0.05, 0.008) * 0.7, highpass(burst(0.04, 0.003, rng), 1500.0) * 0.4), 0.16)
    return finish(out, 0.0, fade=0.02)


def make_mag_in():
    rng = np.random.default_rng(1400)
    n = int(SR * 0.2)
    out = np.zeros(n)
    place(out, mix(thump(0.1, 320.0, 160.0, 0.02), ring(1500.0, 0.1, 0.02) * 0.5, burst(0.1, 0.006, rng, lo=800.0, hi=5000.0) * 0.8), 0.0)
    place(out, ring(2100.0, 0.05, 0.006) * 0.4, 0.07)
    return finish(out, 0.0, drive=1.3, fade=0.02)


def make_bolt():
    rng = np.random.default_rng(1500)
    n = int(SR * 0.25)
    out = np.zeros(n)
    for at, gain in [(0.0, 0.8), (0.11, 1.0)]:
        place(out, mix(ring(1100.0, 0.08, 0.015) * gain, burst(0.06, 0.008, rng, lo=800.0, hi=5000.0) * gain * 0.9, thump(0.06, 400.0, 200.0, 0.012) * 0.5 * gain), at)
    return finish(out, 0.0, drive=1.3, fade=0.02)


def make_shell_in(i):
    rng = np.random.default_rng(1600 + i)
    n = int(SR * 0.14)
    out = np.zeros(n)
    f = [2600.0, 2400.0][i]
    out += ring(f, 0.14, 0.01)[:n] + ring(f * 0.66, 0.14, 0.012)[:n] * 0.6
    out += burst(0.14, 0.003, rng, lo=1500.0)[:n] * 0.7
    out += thump(0.14, 420.0, 260.0, 0.012)[:n] * 0.6
    return finish(out, 0.0, drive=1.2, fade=0.02)


def make_pump():
    rng = np.random.default_rng(1700)
    n = int(SR * 0.34)
    out = np.zeros(n)
    place(out, mix(ring(700.0, 0.09, 0.02) * 0.8, ring(1800.0, 0.07, 0.01) * 0.5, burst(0.08, 0.008, rng, lo=600.0, hi=5000.0) * 0.8), 0.0)
    place(out, bandpass(noise(int(SR * 0.1), rng), 600.0, 3000.0) * 0.15 * np.sin(np.linspace(0, np.pi, int(SR * 0.1))), 0.06)
    place(out, mix(ring(900.0, 0.1, 0.022), ring(2100.0, 0.08, 0.012) * 0.6, burst(0.09, 0.01, rng, lo=500.0, hi=5000.0) * 1.0, thump(0.08, 300.0, 140.0, 0.018) * 0.7), 0.17)
    return finish(out, 0.0, drive=1.4, fade=0.03)


def make_casing(i):
    n = int(SR * 0.16)
    out = np.zeros(n)
    fa, fb = [(3400.0, 5200.0), (3100.0, 4700.0)][i]
    for at, gain in [(0.0, 1.0), (0.055, 0.5), (0.095, 0.25)]:
        place(out, mix(ring(fa, 0.06, 0.02), ring(fb, 0.06, 0.012) * 0.6) * gain, at)
    return finish(out, 0.0, fade=0.02)


# ------------------------------------------------------------------------------------------------- the files --

def sounds():
    """name -> the samples (peak applied)."""
    out = {}
    for i in range(2):
        out["shot_pistol_%d" % i] = make_pistol(i)
    for i in range(3):
        out["shot_rifle_%d" % i] = make_rifle(i)
    out["shot_service_0"] = make_service()
    out["shot_hunting_0"] = make_hunting()
    for i in range(2):
        out["shot_shotgun_%d" % i] = make_shotgun(i)
    for i in range(3):
        out["hit_flesh_%d" % i] = make_hit_flesh(i)
        out["hit_plate_%d" % i] = make_hit_plate(i)
    for i in range(2):
        out["hit_wall_%d" % i] = make_hit_wall(i)
        out["melee_swing_%d" % i] = make_melee_swing(i)
        out["melee_hit_%d" % i] = make_melee_hit(i)
        out["thud_%d" % i] = make_thud(i)
        out["shell_in_%d" % i] = make_shell_in(i)
        out["casing_%d" % i] = make_casing(i)
    out["dry_click_0"] = make_dry_click()
    out["mag_out_0"] = make_mag_out()
    out["mag_in_0"] = make_mag_in()
    out["bolt_0"] = make_bolt()
    out["pump_0"] = make_pump()
    final = {}
    for name, x in out.items():
        stem = name.rsplit("_", 1)[0]
        peak = 10.0 ** (PEAKS[stem] / 20.0)
        final[name] = x / max(np.max(np.abs(x)), 1e-9) * peak
    return final


def analyse(x):
    """(the share of the energy below 150 Hz, 150-800, 800-3000 and over 3000 Hz, in percent; the seconds until the 10 ms envelope is 40 dB under
    its peak): a way to see what a sound is made of without hearing it."""
    spec = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(x.size, 1.0 / SR)
    total = max(spec.sum(), 1e-12)
    shares = [spec[(f >= lo) & (f < hi)].sum() / total * 100.0 for lo, hi in [(0, 150), (150, 800), (800, 3000), (3000, 30000)]]
    w = int(0.01 * SR)
    env = np.sqrt(np.convolve(x * x, np.ones(w) / w, mode="same"))
    peak = env.max()
    over = np.where(env > peak * 0.01)[0]
    return shares, (over[-1] / SR if over.size else 0.0)


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    check = "--check" in sys.argv
    total = 0
    for name, x in sounds().items():
        peak = 20.0 * np.log10(max(np.max(np.abs(x)), 1e-9))
        rms = 20.0 * np.log10(max(np.sqrt(np.mean(x * x)), 1e-9))
        size = x.size * 2 + 44
        total += size
        shares, decay = analyse(x)
        print("%-16s %5.2f s  peak %6.1f dBFS  rms %6.1f dBFS  %6d bytes  bands <150/<800/<3k/over %2.0f %2.0f %2.0f %2.0f %%  -40 dB at %.2f s" % ((name, x.size / SR, peak, rms, size) + tuple(shares) + (decay,)))
        if not check:
            write_wav(os.path.join(OUT, name + ".wav"), x)
    print("total %d bytes" % total)


if __name__ == "__main__":
    main()
