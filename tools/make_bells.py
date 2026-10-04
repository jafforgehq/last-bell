#!/usr/bin/env python3
"""The bells of Thirty Bells (the game is named for the one the community rings at dusk): nine mono 16-bit WAVs in assets/audio/,
made from arithmetic alone (NumPy, tools/audio_dsp.py), a fixed seed for each, so a second run writes the same bytes.

    python3 tools/make_bells.py            # writes assets/audio/bell_*.wav and updates audio_manifest.json
    python3 tools/make_bells.py --check    # renders and prints, writes nothing

    bell_0.wav          22.05 kHz  9 s   THE DUSK BELL, one toll (the file the map data calls "bell"): a big brass bell tuned to A
    bell_dusk_1.wav     22.05 kHz  9 s   the same bell struck a little differently (softer, other beats)
    bell_dusk_2.wav     22.05 kHz  9 s   and again, harder: the game rings the dusk bell as a few tolls, each a different one
    bell_deep.wav       16 kHz    10 s   the season bell: an octave lower, slow, the hum at 55 Hz
    bell_alarm.wav      22.05 kHz  3 s   the call to arms: a small bell struck five times in a hurry (E, thin and bright)
    bell_chime_0..2.wav 22.05 kHz  2.5 s a small bright bell for "built" and "arrived": three notes of the key (E5 G5 A5)
    bell_far.wav        16 kHz    10 s   the dusk bell as heard a long way off (a trip away from the base): dull, smeared, echoing

THE BELL. A bell's partials are not harmonic: with the prime at 1.0 they are at ratios of about 0.5 (the hum, an octave down),
1.0 (prime), 1.18 (the tierce, a minor third), 1.51 (the quint), 2.0 (the nominal), 2.51, 2.66, 3.01, 4.17, 5.43: with the prime
tuned to A3 (220 Hz) the first five ring A, A, C, E, A, which is an A minor chord, so the bell sits in the score's key. Each
partial is a pair a fraction of a hertz apart (a real bell is never quite round, and beats), has its own decay (the hum rings
for ten seconds, the high partials for one), and the clapper adds a bright click that dies in a few milliseconds. The room is a
synthetic impulse response with sparse echoes off far walls (that is what makes a bell carry) and a tail whose highs die first.

The levels: the near bells peak at -3.5 dBFS (an effect, like the shots), the far bell at -12.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as D  # noqa: E402

WRITE = "--check" not in sys.argv

# ratio to the prime, level, ring time of the biggest bell (seconds)
PARTIALS = [
    (0.500, 0.80, 15.0),
    (1.000, 1.00, 10.0),
    (1.183, 0.75, 7.5),
    (1.506, 0.55, 5.8),
    (2.000, 0.90, 4.6),
    (2.514, 0.38, 3.2),
    (2.662, 0.34, 3.0),
    (3.011, 0.30, 2.4),
    (4.166, 0.20, 1.5),
    (5.433, 0.12, 1.0),
    (6.796, 0.08, 0.7),
]


def bell_dry(prime, seconds, sr, rng, size=1.0, hard=1.0, vel=1.0):
    """One strike of a bell. `prime` is its prime partial in Hz; `size` stretches the ring times (a big bell rings on);
    `hard` is the hardness of the clapper (the click and the high partials)."""
    n = int(seconds * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for ratio, amp, ring in PARTIALS:
        f = prime * ratio
        if f > sr * 0.45:
            continue
        a = amp * (hard ** max(0.0, np.log2(max(ratio, 1.0))) if ratio > 2.2 else 1.0)
        tau = ring * size / 6.9             # the ring time is the time to fall 60 dB
        # a pair of partials a fraction of a hertz apart: the beat
        split = rng.uniform(0.25, 0.9) * (1.0 + 0.3 * ratio)
        for sign, share in ((-1.0, 0.55), (1.0, 0.45)):
            out += a * share * np.sin(D.TAU * (f + sign * split / 2.0) * t + rng.uniform(0, D.TAU)) * np.exp(-t / tau)
    out *= D.ramp(t, 0.0012)
    # the clapper: a click and a few bright, short partials
    m = int(0.012 * sr)
    click = D.bandpass(rng.standard_normal(n), 900.0, 6000.0, sr, 2, circular=False)[:m] * np.exp(-np.arange(m) / sr / 0.0025)
    out[:m] += click * 0.55 * hard
    for fb, ab, tb in ((3150.0, 0.16, 0.06), (4670.0, 0.10, 0.04), (6280.0, 0.07, 0.03)):
        if fb * (prime / 220.0) < sr * 0.45:
            out += ab * hard * np.sin(D.TAU * fb * (prime / 220.0) * t + rng.uniform(0, D.TAU)) * np.exp(-t / tb) * D.ramp(t, 0.0005)
    out *= vel
    return out / (np.max(np.abs(out)) + 1e-9)


def room_far(sr, rng, rt60, echo_gaps=(0.21, 0.47, 0.83), echo_gain=(0.5, 0.32, 0.2)):
    """A room that carries: the usual tail and a few slap echoes off far walls (the clack of the hills)."""
    ir = D.reverb_ir(sr, rt60, rng, predelay=0.02, damp=2.6)
    for gap, g in zip(echo_gaps, echo_gain):
        at = int(gap * sr)
        seg = D.lowpass(rng.standard_normal(int(0.05 * sr)), 2500.0, sr, 2, circular=False) * np.exp(-np.arange(int(0.05 * sr)) / sr / 0.015)
        if at + len(seg) < len(ir):
            ir[at:at + len(seg)] += seg / (np.sqrt(np.sum(seg ** 2)) + 1e-9) * g * 0.35
    return ir / np.sqrt(np.sum(ir ** 2))


def finish(dry, sr, seconds, rt60, wet, rng, peak_db, echoes=True, lowpass_hz=None, tail=2.5, high_pass=45.0, loud_db=None):
    """Adds the room, cuts, fades the end, and sets the level: the first two seconds are scaled to `loud_db` RMS (so
    every strike of a bell is as loud as the others whatever its random phases did to the peak), and a soft limiter keeps
    the peak at `peak_db`."""
    ir = room_far(sr, rng, rt60) if echoes else D.reverb_ir(sr, rt60, rng)
    y = D.with_reverb(dry, ir, wet, circular=False)[:int(seconds * sr)]
    if lowpass_hz:
        y = D.lowpass(y, lowpass_hz, sr, 2, circular=False)
    y = D.highpass(y, high_pass, sr, 2, circular=False)
    y *= D.tail_off(len(y), sr, tail)
    if loud_db is None:
        return y / (np.max(np.abs(y)) + 1e-9) * 10.0 ** (peak_db / 20.0)
    head = y[:int(2.0 * sr)]
    y = y / (np.sqrt(np.mean(head ** 2)) + 1e-12) * 10.0 ** (loud_db / 20.0)
    return D.soft_ceiling(y, peak_db)


def save(name, y, sr, seed, notes):
    st = D.save(name, y, sr, loop=False, kind="bell", seed=seed, notes=notes) if WRITE else None
    if st is None:
        st = {"file": name + ".wav", "rate": sr, "seconds": len(y) / sr, "peak_db": D.peak_db(y), "rms_db": D.rms_db(y), "clipped": 0, "seam": None, "bytes": len(y) * 2}
    D.report(st)
    return st


def main():
    sr = 22050
    prime = D.hz("A3")
    # --- the dusk bell: three tolls of one bell (the strikes differ in hardness and in the phases of the beats)
    for k, (name, vel, hard, seed) in enumerate((("bell_0", 1.0, 1.0, 101), ("bell_dusk_1", 0.8, 0.75, 102), ("bell_dusk_2", 0.9, 1.15, 103))):
        rng = np.random.default_rng(seed)
        dry = bell_dry(prime * 2.0 ** (rng.uniform(-3, 3) / 1200.0), 9.0, sr, rng, 1.0, hard, vel)
        y = finish(dry, sr, 9.0, 4.6, 0.38, rng, -3.5, tail=3.5, loud_db=-17.0)
        save(name, y, sr, seed, "the dusk bell, a toll")
    # --- the season bell: an octave and more below, slow
    sr2 = 16000
    rng = np.random.default_rng(111)
    dry = bell_dry(D.hz("A2"), 10.0, sr2, rng, 1.25, 0.6, 1.0)
    y = finish(dry, sr2, 10.0, 5.2, 0.42, rng, -3.5, tail=3.5, loud_db=-17.0)
    save("bell_deep", y, sr2, 111, "the season bell")
    # --- the call to arms: a small bell, struck five times in a hurry, each a little weaker than the last but one
    rng = np.random.default_rng(121)
    seconds = 3.0
    buf = np.zeros(int(seconds * sr))
    at = 0.0
    for k, v in enumerate((1.0, 0.9, 0.95, 0.85, 0.8)):
        hit = bell_dry(D.hz("E5") * 2.0 ** (rng.uniform(-2, 2) / 1200.0), 1.6, sr, rng, 0.16, 1.4, v)
        i = int(at * sr)
        buf[i:i + len(hit)] += hit[:len(buf) - i]
        at += rng.uniform(0.27, 0.34)
    y = finish(buf, sr, seconds, 1.4, 0.22, rng, -4.5, echoes=False, tail=0.6, high_pass=300.0, loud_db=-17.0)
    save("bell_alarm", y, sr, 121, "five quick strikes of a small bell")
    # --- the chimes
    for k, (nm, seed) in enumerate((("E5", 131), ("G5", 132), ("A5", 133))):
        rng = np.random.default_rng(seed)
        dry = bell_dry(D.hz(nm), 2.5, sr, rng, 0.30, 1.1, 1.0)
        y = finish(dry, sr, 2.5, 1.2, 0.2, rng, -9.0, echoes=False, tail=0.8, high_pass=250.0, loud_db=-23.0)
        save("bell_chime_%d" % k, y, sr, seed, "a small bell, %s" % nm)
    # --- the far bell: soft strike, dull, smeared, echoing
    rng = np.random.default_rng(141)
    dry = bell_dry(prime, 9.0, sr2, rng, 1.0, 0.25, 0.9)
    y = finish(dry, sr2, 10.0, 6.0, 0.6, rng, -12.0, lowpass_hz=1800.0, tail=4.0, loud_db=-25.0)
    save("bell_far", y, sr2, 141, "the dusk bell a long way off")


if __name__ == "__main__":
    main()
