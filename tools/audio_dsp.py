#!/usr/bin/env python3
"""The shared sound-making kit of Thirty Bells' audio generators (tools/make_score.py, make_bells.py, make_ambience.py,
make_base_sounds.py): plain NumPy, no samples, no downloads, no one else's sounds. Python 3 and NumPy only (no SciPy).

Everything here is deterministic: a generator gives each sound its own `numpy.random.default_rng(seed)`, so running a
generator again writes the same bytes. Nothing in this file touches the game.

What is in it
  * notes and levels        `hz("A4")`, `db_of(x)`, `rms_db(x)`, `peak_db(x)`
  * filters                 zero-phase, in the frequency domain (`lowpass`, `highpass`, `bandpass`, `peak_eq`); with
                            `circular=True` (the default for loops) the filter wraps round the buffer, so a loop stays
                            seamless; a one-shot is padded instead (`circular=False`)
  * reverb                  a synthetic impulse response (`reverb_ir`: early reflections and a tail whose highs die
                            first) convolved by FFT (`convolve`); circular for a loop, linear with its tail for a one-shot
  * `Loop`                  a buffer in which voices are added at times, a tail running past the end wraps to the front
  * voices                  `piano` (a felt piano), `bowed` (a bowed string with vibrato), `pad`, `brass`, `chime`,
                            drums (`tom`, `thump`, `taiko`, `shaker`, `clank`), `air` (band-limited noise)
  * writing and measuring   `write_wav` (16-bit mono, a hair of dither), `seam_ratio`, `manifest_put` (the numbers of
                            every file go to assets/audio/audio_manifest.json, which tests/test_audio_assets.gd reads)

The ear is not available to the machine that wrote this: the generators are checked by numbers (level, loop seam, spectrum,
the notes against the key) and by the owner's ears afterwards.
"""
import json
import os
import wave

import numpy as np

TAU = 2.0 * np.pi
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
MANIFEST = os.path.join(OUT_DIR, "audio_manifest.json")

_SEMI = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name):
    """The frequency of a note by name ("A4" is 440 Hz, equal temperament): "C#3", "F2"."""
    if name[1] in "#b" and len(name) > 2:
        letter, octave = name[:2], int(name[2:])
    else:
        letter, octave = name[0], int(name[1:])
    if letter.endswith("b"):
        letter = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"}[letter]
    return 440.0 * 2.0 ** ((12 * (octave - 4) + _SEMI[letter] - 9) / 12.0)


def pitch_class(freq):
    """The nearest note's pitch class name of a frequency (0 = C)."""
    return int(round(12.0 * np.log2(freq / 440.0) + 9)) % 12


# ------------------------------------------------------------------------------------------------ measuring

def db_of(x):
    return 20.0 * np.log10(max(float(x), 1e-12))


def peak_db(x):
    return db_of(np.max(np.abs(x)))


def rms_db(x):
    return db_of(np.sqrt(np.mean(np.asarray(x, dtype=np.float64) ** 2)))


def seam_ratio(x):
    """How big the step from the last sample to the first is, against a typical step inside the loop: 1 is as smooth
    as the loop is everywhere, 20 is a click. (The loops are built to close, so this should be about 1 to 3.)"""
    d = np.diff(x)
    typical = np.sqrt(np.mean(d * d)) + 1e-12
    return float(abs(x[0] - x[-1]) / typical)


def clipped(x, limit=0.999):
    return int(np.sum(np.abs(x) >= limit))


def band_energy_db(x, sr, edges=(0, 100, 250, 500, 1000, 2000, 4000, 8000, 22050)):
    """Mean energy of a signal in frequency bands, in dB (for the spectral-balance printouts)."""
    spec = np.abs(np.fft.rfft(x)) ** 2 / len(x) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    out = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (f >= lo) & (f < hi)
        out.append((lo, hi, 10.0 * np.log10(spec[m].sum() + 1e-18)))
    return out


# ------------------------------------------------------------------------------------------------ filters

def _freqs(n, sr):
    return np.fft.rfftfreq(n, 1.0 / sr)


def fft_apply(x, response, sr, circular=True):
    """Filters `x` with a zero-phase response (a function of frequency in Hz returning the gain). Circular: the filter
    wraps round the buffer (a loop). Not circular: padded with silence by the longest ringing a smooth filter can
    have, then cut back."""
    n = len(x)
    if circular:
        return np.fft.irfft(np.fft.rfft(x) * response(_freqs(n, sr)), n)
    m = n + int(0.25 * sr)
    y = np.fft.irfft(np.fft.rfft(x, m) * response(_freqs(m, sr)), m)
    return y[:n]


def lowpass(x, fc, sr, order=2, circular=True):
    return fft_apply(x, lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)), sr, circular)


def highpass(x, fc, sr, order=2, circular=True):
    def h(f):
        r = (f / fc) ** (2 * order)
        return np.sqrt(r / (1.0 + r))
    return fft_apply(x, h, sr, circular)


def bandpass(x, lo, hi, sr, order=2, circular=True):
    def h(f):
        a = np.sqrt((f / lo) ** (2 * order) / (1.0 + (f / lo) ** (2 * order)))
        b = 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order))
        return a * b
    return fft_apply(x, h, sr, circular)


def peak_eq(x, fc, q, gain_db, sr, circular=True):
    """A bell-shaped boost or cut round fc (a body resonance)."""
    g = 10.0 ** (gain_db / 20.0) - 1.0
    return fft_apply(x, lambda f: 1.0 + g * np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) * q * 1.6) ** 2), sr, circular)


def one_pole(x, fc, sr):
    """A one-pole low-pass run sample by sample (for envelopes and smoothing; slow for long buffers)."""
    a = 1.0 - np.exp(-TAU * fc / sr)
    y = np.empty(len(x))
    s = 0.0
    for i in range(len(x)):
        s += a * (x[i] - s)
        y[i] = s
    return y


def smooth(x, seconds, sr):
    """A moving average over `seconds`, circular (an envelope's softener)."""
    k = max(1, int(seconds * sr))
    if k <= 1:
        return x
    ker = np.zeros(len(x))
    ker[:k] = 1.0 / k
    ker = np.roll(ker, -k // 2)
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ker), len(x))


# ------------------------------------------------------------------------------------------------ noise, envelopes

def noise(n, rng):
    return rng.standard_normal(n)


def colored(n, rng, slope=-1.0, sr=22050, lo=20.0):
    """Noise whose power falls like f**slope (-1 is pink, -2 brown): shaped in the frequency domain, circular."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.maximum(_freqs(n, sr), lo)
    spec *= f ** (slope / 2.0)
    y = np.fft.irfft(spec, n)
    return y / (np.std(y) + 1e-12)


def air(n, rng, lo, hi, sr, steep=2):
    """Band-limited noise: a wind, a hiss. Circular."""
    return bandpass(rng.standard_normal(n), lo, hi, sr, steep)


def t_axis(seconds, sr):
    return np.arange(int(round(seconds * sr))) / sr


def decay(t, tau):
    return np.exp(-t / tau)


def ramp(t, seconds):
    """0 to 1 over `seconds` (a smooth start: no click)."""
    x = np.clip(t / max(seconds, 1e-6), 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def tail_off(n, sr, seconds):
    """1 for most of the buffer then a smooth fall to 0 at its end (a sound that ends in silence)."""
    t = np.arange(n) / sr
    return ramp((n / sr) - t, seconds)


def swell_cycles(n, sr, seconds, cycles, phase=0.0):
    """A 0..1 swell with a whole number of cycles over `seconds` (a loop's slow breathing closes on itself)."""
    t = np.arange(n) / sr
    return 0.5 - 0.5 * np.cos(TAU * cycles / seconds * t + phase)


# ------------------------------------------------------------------------------------------------ reverb

def reverb_ir(sr, rt60, rng, predelay=0.012, damp=3.0, early=6, low_boost=1.15, dark=True):
    """A synthetic room: `early` sparse reflections in the first 70 ms, then a noise tail that falls 60 dB in
    `rt60` seconds, the highs `damp` times quicker than the middle and the lows a little slower. Unit energy.
    Mono; the tail is cut at 1.25 x rt60."""
    n = int(rt60 * 1.25 * sr)
    t = np.arange(n) / sr
    spec = np.fft.rfft(rng.standard_normal(n))
    f = _freqs(n, sr)
    low = 1.0 / (1.0 + (f / 400.0) ** 4)
    high = (f / 3000.0) ** 4 / (1.0 + (f / 3000.0) ** 4)
    mid = np.clip(1.0 - low - high, 0.0, 1.0)
    ir = np.zeros(n)
    for w, rt in ((low, rt60 * low_boost), (mid, rt60), (high, rt60 / damp)):
        band = np.fft.irfft(spec * w, n)
        ir += band * np.exp(-t * (6.9078 / rt))
    if dark:
        ir = lowpass(ir, 7000.0, sr, 1, circular=False)
    ir *= ramp(t, 0.02)
    # the first reflections
    pd = int(predelay * sr)
    ir = np.concatenate([np.zeros(pd), ir])[:n]
    for k in range(early):
        at = int((predelay + 0.006 + rng.uniform(0.004, 0.065)) * sr)
        if at < n:
            ir[at] += rng.choice([-1.0, 1.0]) * rng.uniform(0.4, 1.0) * (1.0 - k / (early + 2.0)) * np.sqrt(np.sum(ir ** 2)) * 0.05
    return ir / np.sqrt(np.sum(ir ** 2) + 1e-12)


def convolve(x, ir, circular=False):
    """FFT convolution. Circular: the length stays that of `x` and the tail wraps (a loop). Otherwise the result is
    len(x) + len(ir) - 1 long (a one-shot with its tail)."""
    if circular:
        n = len(x)
        h = np.zeros(n)
        take = min(len(ir), n)
        h[:take] = ir[:take]
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n)
    m = len(x) + len(ir) - 1
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)


def with_reverb(x, ir, wet, circular=False, gain=1.0):
    """The dry sound and its room: `wet` is the share of the room (0 dry .. 1 only room). The room is scaled to the dry
    sound's total energy (the IR has unit energy), so `wet` 0.5 is as much room as dry."""
    w = convolve(x, ir, circular)
    w = w * gain * np.sqrt(max(np.sum(x ** 2), 1e-18) / max(np.sum(w ** 2), 1e-18))
    if circular:
        return x * (1.0 - wet) + w * wet
    y = np.zeros(len(w))
    y[:len(x)] = x * (1.0 - wet)
    return y + w * wet


# ------------------------------------------------------------------------------------------------ a loop buffer

class Loop:
    """A loop of `seconds` at `sr`: voices are added at times, and one that runs past the end wraps round to the front,
    so the join is as smooth as the voices are. Filters and the room are circular."""

    def __init__(self, seconds, sr, seed):
        self.sr = sr
        self.seconds = seconds
        self.n = int(round(seconds * sr))
        self.buf = np.zeros(self.n)
        self.rng = np.random.default_rng(seed)

    def add(self, start, sound, gain=1.0):
        i = int(round(start * self.sr)) % self.n
        s = np.asarray(sound) * gain
        while len(s) > 0:
            take = min(len(s), self.n - i)
            self.buf[i:i + take] += s[:take]
            s = s[take:]
            i = 0

    def add_loop(self, sound, gain=1.0):
        """A sound exactly as long as the loop (a drone, a bed)."""
        assert len(sound) == self.n, (len(sound), self.n)
        self.buf += sound * gain

    def room(self, rt60, wet, predelay=0.012, damp=3.0, seed=None):
        ir = reverb_ir(self.sr, rt60, np.random.default_rng(seed if seed is not None else int(self.rng.integers(1 << 30))), predelay, damp)
        self.buf = with_reverb(self.buf, ir, wet, circular=True)

    def lowpass(self, fc, order=2):
        self.buf = lowpass(self.buf, fc, self.sr, order)

    def highpass(self, fc, order=2):
        self.buf = highpass(self.buf, fc, self.sr, order)

    def master(self, rms_target_db, peak_ceiling_db=-1.0, drive=1.0):
        """Takes out the mean, then scales so that the loudness AFTER a soft limiter at the ceiling is the target (a few
        rounds): the loudest note never passes the ceiling, a peaky loop (drums) is squeezed rather than turned down,
        and what is under 70% of the ceiling is not touched."""
        b = self.buf - np.mean(self.buf)
        b = b / (np.sqrt(np.mean(b ** 2)) + 1e-12)
        gain = 10.0 ** (rms_target_db / 20.0) * drive
        for _ in range(8):
            y = soft_ceiling(b * gain, peak_ceiling_db)
            err = rms_db(y) - rms_target_db
            if abs(err) < 0.05:
                break
            gain *= 10.0 ** (-err / 20.0)
        self.buf = y
        return self.buf


def soft_ceiling(x, ceiling_db):
    """Leaves everything under ~70% of the ceiling alone and bends what is above it so it never passes the ceiling."""
    c = 10.0 ** (ceiling_db / 20.0)
    knee = 0.7 * c
    a = np.abs(x)
    over = a > knee
    y = x.copy()
    y[over] = np.sign(x[over]) * (knee + (c - knee) * np.tanh((a[over] - knee) / (c - knee)))
    return y


# ------------------------------------------------------------------------------------------------ voices

def piano(f0, dur, vel, sr, rng, bright=1.0, decay_scale=1.0, strings=3):
    """A soft (felt) piano: partials a hair sharp of harmonic (a stiff string), a felt hammer that rolls the highs
    off (less with `vel`), two-stage decays (a quick fall, then a long ring) that are shorter up the keyboard and
    for the upper partials, a few strings a few cents apart so the note beats slowly, and a thump of the hammer.
    `dur` is the length rendered; the note is faded out over its last 60 ms."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    inharm = 0.00018 * (f0 / 110.0) ** 1.3
    tau1 = 7.0 * (110.0 / f0) ** 0.5 * decay_scale
    cutoff = 2100.0 * bright * (0.55 + 0.9 * vel)
    k = 1
    while True:
        fk = f0 * k * np.sqrt(1.0 + inharm * k * k)
        if fk > sr * 0.45 or k > 36:
            break
        amp = k ** -0.9 * np.exp(-(fk / cutoff) ** 2)
        if amp < 0.003:
            break
        tau = tau1 / (1.0 + 0.7 * (k - 1) ** 0.85)
        env = 0.55 * np.exp(-t / (tau * 0.28)) + 0.45 * np.exp(-t / tau)
        for s in range(strings):
            cents = (s - (strings - 1) / 2.0) * rng.uniform(0.6, 1.7)
            out += amp / strings * np.sin(TAU * fk * 2.0 ** (cents / 1200.0) * t + rng.uniform(0, TAU)) * env
        k += 1
    # the hammer's thump and the felt: a short low noise burst
    m = min(n, int(0.03 * sr))
    burst = bandpass(rng.standard_normal(m), 120.0, 1100.0, sr, 2, circular=False) * np.exp(-np.arange(m) / sr / 0.008)
    out[:m] += burst * 0.55 * (0.4 + vel)
    out *= ramp(t, 0.004) * ramp(dur - t, 0.06)
    return out * vel / (np.max(np.abs(out)) + 1e-9) * 0.9


def bowed(f0, dur, sr, rng, vel=0.7, attack=0.35, release=0.7, vib_rate=5.2, vib_depth=0.0055, voices=2, bright=1.0):
    """A bowed string, a lonely one: a sawtooth-ish harmonic series shaped by a body (resonances at 450, 1100, 2600 Hz),
    a scoop up to the pitch, a vibrato that comes in after half a second, bow noise, and a slow swell. `voices` tuned a
    few cents apart make it a small section."""
    total = dur + release
    n = int(total * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    vib_env = ramp(t - 0.45, 1.2)
    for v in range(voices):
        cents = (v - (voices - 1) / 2.0) * rng.uniform(5.0, 9.0)
        rate = vib_rate * rng.uniform(0.93, 1.07)
        f_t = f0 * 2.0 ** (cents / 1200.0) * (1.0 + vib_depth * vib_env * np.sin(TAU * rate * t + rng.uniform(0, TAU))) * (1.0 - 0.014 * np.exp(-t / 0.09))
        phase = TAU * np.cumsum(f_t) / sr
        k = 1
        while k * f0 < sr * 0.45 and k <= 34:
            fk = k * f0
            body = 1.0 + 1.4 * np.exp(-((fk - 450.0) / 220.0) ** 2) + 0.9 * np.exp(-((fk - 1100.0) / 350.0) ** 2) + 0.5 * np.exp(-((fk - 2600.0) / 700.0) ** 2)
            amp = k ** -1.05 * body * np.exp(-(fk / (4200.0 * bright)) ** 2)
            out += amp / voices * np.sin(k * phase + rng.uniform(0, TAU))
            k += 1
    env = ramp(t, attack) * (1.0 + 0.06 * np.sin(TAU * 0.23 * t)) * ramp(total - t, release)
    bow = bandpass(rng.standard_normal(n), 700.0, 3000.0, sr, 2, circular=False) * 0.03 * ramp(t, 0.12)
    out = (out * env + bow * env) * vel
    return out / (np.max(np.abs(out)) + 1e-9) * vel


def pad(f0, dur, sr, rng, attack=2.0, release=2.5, bright=0.5, voices=3, detune_cents=7.0):
    """A soft chord tone: detuned partials that fall away quickly (a warm, rounded tone), a slow swell and a fall."""
    total = dur + release
    n = int(total * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for v in range(voices):
        cents = (v - (voices - 1) / 2.0) * detune_cents * rng.uniform(0.7, 1.3)
        fv = f0 * 2.0 ** (cents / 1200.0)
        # a slow independent wobble of the pitch makes the chorus move
        drift = 1.0 + 0.0008 * np.sin(TAU * rng.uniform(0.07, 0.19) * t + rng.uniform(0, TAU))
        phase = TAU * np.cumsum(fv * drift) / sr
        k = 1
        while k * f0 < sr * 0.45 and k <= 14:
            amp = (bright ** (k - 1)) * k ** -0.6
            if amp < 0.004:
                break
            out += amp / voices * np.sin(k * phase + rng.uniform(0, TAU))
            k += 1
    env = ramp(t, attack) * ramp(total - t, release)
    return out * env / (np.max(np.abs(out)) + 1e-9)


def brass(f0, dur, sr, rng, attack=1.2, release=1.8, level=0.8, voices=2):
    """A low brass drone: a harmonic series whose upper partials come up as the note swells (a brass is brighter
    when it is louder), breath noise on the attack, a slow tremolo and two players a few cents apart."""
    total = dur + release
    n = int(total * sr)
    t = np.arange(n) / sr
    swell = ramp(t, attack) * ramp(total - t, release)
    out = np.zeros(n)
    for v in range(voices):
        cents = (v - (voices - 1) / 2.0) * rng.uniform(6.0, 11.0)
        fv = f0 * 2.0 ** (cents / 1200.0)
        trem_phase = rng.uniform(0, TAU)
        phase = TAU * np.cumsum(fv * (1.0 + 0.0012 * np.sin(TAU * 4.6 * t + trem_phase))) / sr
        k = 1
        while k * f0 < sr * 0.45 and k <= 22:
            tilt = 0.45 + 0.5 * level
            amp = k ** -0.85 * (tilt ** (k - 1) + (1.0 - tilt) * 0.0)
            # the upper partials follow the swell
            out += amp / voices * np.sin(k * phase + rng.uniform(0, TAU)) * (swell ** (0.35 * (k - 1) ** 0.6))
            k += 1
    breath = bandpass(rng.standard_normal(n), 300.0, 2500.0, sr, 2, circular=False) * 0.05 * np.exp(-t / 0.25)
    out = (out + breath) * swell
    return out / (np.max(np.abs(out)) + 1e-9)


def chime(f0, dur, sr, rng, vel=0.6, partials=((1.0, 1.0, 5.0), (2.0, 0.45, 3.2), (3.0, 0.2, 2.0), (4.2, 0.1, 1.2))):
    """A soft struck glass or small bell, tuned to the key: partials a little inharmonic with their own decays."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for ratio, amp, tau in partials:
        out += amp * np.sin(TAU * f0 * ratio * (1.0 + rng.uniform(-0.0015, 0.0015)) * t + rng.uniform(0, TAU)) * np.exp(-t / tau)
    out *= ramp(t, 0.004) * ramp(dur - t, 0.1)
    return out / (np.max(np.abs(out)) + 1e-9) * vel


def thump(sr, f_start=130.0, f_end=55.0, dur=0.6, drop=22.0, tau=0.16, click=0.25, rng=None):
    """A heartbeat-low drum: a sine that drops in pitch and dies away, with a hint of click so small speakers hear it."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    f = f_end + (f_start - f_end) * np.exp(-t * drop)
    ph = TAU * np.cumsum(f) / sr
    body = np.sin(ph) * np.exp(-t / tau) * ramp(t, 0.003)
    if rng is not None and click > 0:
        c = bandpass(rng.standard_normal(n), 400.0, 2400.0, sr, 2, circular=False) * np.exp(-t / 0.006) * click
        body = body + c
    return body


def tom(f0, dur, sr, rng, vel=0.8, tau=0.28, drop=1.7, noise_amt=0.35):
    """A soft frame drum or floor tom: a falling sine with a second membrane mode, a puff of felt-mallet noise."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    f = f0 * (1.0 + (drop - 1.0) * np.exp(-t / 0.05))
    ph = TAU * np.cumsum(f) / sr
    body = (np.sin(ph) + 0.35 * np.sin(1.59 * ph + 0.7) * np.exp(-t / 0.08)) * np.exp(-t / tau)
    puff = lowpass(rng.standard_normal(n), 1400.0, sr, 2, circular=False) * np.exp(-t / 0.012) * noise_amt * 2.0
    out = (body + puff) * ramp(t, 0.002) * ramp(dur - t, 0.03)
    return out * vel / (np.max(np.abs(out)) + 1e-9)


def taiko(f0, dur, sr, rng, vel=1.0, tau=0.55):
    """A big drum: a low sine that falls from twice its pitch, a lower body, a stick's click, a long ring."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    f = f0 * (1.0 + 1.1 * np.exp(-t / 0.045))
    ph = TAU * np.cumsum(f) / sr
    body = (np.sin(ph) + 0.5 * np.sin(2.0 * ph + 1.1) * np.exp(-t / 0.12) + 0.3 * np.sin(1.5 * ph) * np.exp(-t / 0.2)) * np.exp(-t / tau)
    click = bandpass(rng.standard_normal(n), 500.0, 3500.0, sr, 2, circular=False) * np.exp(-t / 0.01) * 0.5
    out = np.tanh(1.4 * (body + click)) * ramp(t, 0.002) * ramp(dur - t, 0.05)
    return out * vel / (np.max(np.abs(out)) + 1e-9)


def shaker(dur, sr, rng, vel=0.5):
    n = int(dur * sr)
    t = np.arange(n) / sr
    x = highpass(rng.standard_normal(n), 3500.0, sr, 2, circular=False) * np.exp(-t / (dur * 0.35)) * ramp(t, 0.006)
    return x * vel / (np.max(np.abs(x)) + 1e-9)


def clank(f0, dur, sr, rng, vel=0.6):
    """A bit of struck metal (an anvil, a chain): inharmonic partials that die quickly."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for ratio, amp, tau in ((1.0, 1.0, 0.18), (2.32, 0.7, 0.12), (3.87, 0.5, 0.08), (5.43, 0.35, 0.05), (7.1, 0.2, 0.03)):
        if f0 * ratio < sr * 0.45:
            out += amp * np.sin(TAU * f0 * ratio * t + rng.uniform(0, TAU)) * np.exp(-t / tau)
    out *= ramp(t, 0.001) * ramp(dur - t, 0.02)
    return out * vel / (np.max(np.abs(out)) + 1e-9)


# ------------------------------------------------------------------------------------------------ writing

def write_wav(path, x, sr, seed=0):
    """16-bit mono PCM. The samples are rounded with a hair of triangular dither (deterministic), clipped never."""
    rng = np.random.default_rng(seed)
    x = np.asarray(x, dtype=np.float64)
    dither = (rng.random(len(x)) - rng.random(len(x))) / 32768.0 * 0.5
    data = np.clip(np.round((x + dither) * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(sr))
        w.writeframes(data.tobytes())
    return data


def save(name, x, sr, loop=False, kind="sfx", seed=0, notes="", out_dir=None):
    """Writes `name`.wav in assets/audio and records its numbers in the manifest. Returns the stats."""
    out_dir = out_dir or OUT_DIR
    path = os.path.join(out_dir, name + ".wav")
    data = write_wav(path, x, sr, seed)
    f = data.astype(np.float64) / 32768.0
    stats = {
        "file": name + ".wav",
        "kind": kind,
        "rate": int(sr),
        "samples": int(len(f)),
        "seconds": round(len(f) / sr, 3),
        "peak_db": round(peak_db(f), 2),
        "rms_db": round(rms_db(f), 2),
        "clipped": clipped(f, 0.9995),
        "loop": bool(loop),
        "seam": round(seam_ratio(f), 3) if loop else None,
        "bytes": int(os.path.getsize(path)),
        "notes": notes,
    }
    manifest_put(name, stats, out_dir)
    return stats


def manifest_put(name, stats, out_dir=None):
    path = os.path.join(out_dir or OUT_DIR, "audio_manifest.json")
    data = {}
    if os.path.exists(path):
        with open(path) as fh:
            data = json.load(fh)
    data[name] = stats
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1, sort_keys=True)
        fh.write("\n")


def report(stats):
    seam = "" if stats["seam"] is None else "  seam %.2f" % stats["seam"]
    print("%-26s %6.1f s %5d Hz  peak %6.1f  rms %6.1f dBFS  %5d KB%s%s" % (
        stats["file"], stats["seconds"], stats["rate"], stats["peak_db"], stats["rms_db"], stats["bytes"] // 1024, seam,
        "  CLIPPED %d" % stats["clipped"] if stats["clipped"] else ""))
