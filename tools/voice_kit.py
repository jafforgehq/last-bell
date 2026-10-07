#!/usr/bin/env python3
"""A small formant voice for Thirty Bells' dead and for Ruth (the shared kit of tools/make_voice_sounds.py): NumPy only, no samples, no recordings.

A voice here is three things multiplied and added:
  * a SOURCE: a train of glottal pulses at a pitch that moves (`f0` is an array, one value per sample), with a little jitter (the pitch is never
    quite steady), a RASP (an amplitude modulation by slow noise: the roughness of a dead throat) and BREATH (noise that goes through the mouth too);
  * a MOUTH: three resonators (formants) whose centre frequencies move from one vowel to another (`vowels`), run sample by sample;
  * an ENVELOPE (`env`): how the sound begins, holds and dies.
Whether a result sounds like a dying walker is for the owner's ears: the checks here are numbers (the pitch, the spectrum, the loudness: tools/audio_measure.py).
"""
import numpy as np

import audio_dsp as D

TAU = 2.0 * np.pi

# formants F1, F2, F3 (Hz) of a few vowels for a low (male) voice; `scale` moves them for a smaller mouth (a woman: about 1.17)
VOWELS = {
    "uh": (640, 1190, 2390), "aa": (730, 1090, 2440), "oo": (300, 870, 2240), "aw": (570, 840, 2410),
    "ah": (660, 1720, 2410), "uu": (440, 1020, 2240), "eh": (530, 1840, 2480), "ih": (390, 1990, 2550),
}
FORMANT_GAINS = (1.0, 0.62, 0.30)
BANDWIDTHS = (90.0, 110.0, 170.0)


def smooth_noise(n, sr, rng, fc):
    """Slow random wobble, unit standard deviation (noise through a one-sided low-pass at fc)."""
    x = rng.standard_normal(n)
    x = D.lowpass(x, fc, sr, 2, circular=False)
    return x / (np.std(x) + 1e-12)


def curve(n, points):
    """A piecewise-linear curve through `points` = [(position 0..1, value)], n samples."""
    xs = np.array([p[0] for p in points]) * (n - 1)
    ys = np.array([p[1] for p in points])
    return np.interp(np.arange(n), xs, ys)


def glottal(sr, f0, rng, jitter=0.012, rasp=0.0, rasp_hz=38.0, shimmer=0.06, sharp=7.0):
    """A pulse train: each cycle a decaying exponential (a sharp opening and a closing that rings), at the pitch f0 (an array)."""
    n = len(f0)
    wob = smooth_noise(n, sr, rng, 14.0) * jitter
    ph = np.cumsum(f0 * (1.0 + wob)) / sr
    frac = ph % 1.0
    pulse = np.exp(-sharp * frac) - 1.0 / sharp * (1.0 - np.exp(-sharp))
    pulse = pulse - np.mean(pulse)
    amp = 1.0 + shimmer * smooth_noise(n, sr, rng, 25.0)
    if rasp > 0.0:
        m = smooth_noise(n, sr, rng, rasp_hz)
        am = np.clip(1.0 - rasp * (0.5 + 0.5 * np.tanh(m * 1.2)), 0.05, 1.0)
        # the pulses break up too: some cycles are dropped (a creak)
        pulse = pulse * am
    return pulse * amp


def resonators(x, sr, tracks, bws=BANDWIDTHS, gains=FORMANT_GAINS):
    """The mouth: the source goes through one resonator for each formant (`tracks` is a list of arrays of centre frequencies, one value per sample)."""
    n = len(x)
    xs = x.tolist()
    out = np.zeros(n)
    for k, track in enumerate(tracks):
        f = np.clip(np.asarray(track, dtype=np.float64), 80.0, sr * 0.45)
        bw = bws[k]
        r = np.exp(-np.pi * bw / sr)
        c1 = (2.0 * r * np.cos(TAU * f / sr)).tolist()
        c2 = -(r * r)
        a = (1.0 - r) * 1.0
        y1 = 0.0
        y2 = 0.0
        ys = [0.0] * n
        for i in range(n):
            y = a * xs[i] + c1[i] * y1 + c2 * y2
            y2 = y1
            y1 = y
            ys[i] = y
        out += np.array(ys) * gains[k]
    return out


def vowel_tracks(n, path, scale=1.0):
    """The formant tracks for a path of vowels [(position 0..1, 'uh'), ...]: each formant glides from one vowel's to the next."""
    tracks = []
    for k in range(3):
        pts = [(pos, VOWELS[v][k] * scale) for pos, v in path]
        tracks.append(curve(n, pts))
    return tracks


def breath(sr, n, rng, lo=500.0, hi=4000.0):
    return D.bandpass(rng.standard_normal(n), lo, hi, sr, 2, circular=False)


def envelope(n, sr, attack, release, hold_curve=None):
    """0 to 1 over `attack` seconds, held (with `hold_curve` laid on it), and down to 0 over `release` seconds at the end."""
    t = np.arange(n) / sr
    e = D.ramp(t, attack) * D.ramp((n / sr) - t, release)
    if hold_curve is not None:
        e = e * hold_curve
    return e


def voice(sr, seconds, f0, path, rng, rasp=0.3, breath_amt=0.1, attack=0.08, release=0.2, jitter=0.012, scale=1.0, hold=None, rasp_hz=38.0, sharp=7.0, bw_scale=1.0):
    """A whole sound: the pulse source through the mouth, with breath and an envelope. `f0` may be an array (one value per sample) or a number."""
    n = int(seconds * sr)
    f0a = np.full(n, float(f0)) if np.isscalar(f0) else np.asarray(f0)
    src = glottal(sr, f0a, rng, jitter=jitter, rasp=rasp, rasp_hz=rasp_hz, sharp=sharp)
    tr = vowel_tracks(n, path, scale)
    bws = tuple(b * bw_scale for b in BANDWIDTHS)
    voiced = resonators(src, sr, tr, bws)
    voiced = voiced / (np.sqrt(np.mean(voiced ** 2)) + 1e-12)
    out = voiced
    if breath_amt > 0.0:
        br = resonators(rng.standard_normal(n), sr, tr, tuple(b * 2.5 * bw_scale for b in BANDWIDTHS))
        br = br / (np.sqrt(np.mean(br ** 2)) + 1e-12)
        # the breath is there all through and a little more at the ends (a sigh going out)
        t = np.arange(n) / sr
        tail = 1.0 + 1.5 * D.ramp(t - (seconds - release * 1.5), release)
        out = out + breath_amt * br * tail
    return out * envelope(n, sr, attack, release, hold)
