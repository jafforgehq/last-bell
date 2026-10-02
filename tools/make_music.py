#!/usr/bin/env python3
"""Makes the game's four music loops (assets/audio/music_*.wav) from nothing but arithmetic: no samples, no
downloads, no one else's music. Python 3 with NumPy.

    python3 tools/make_music.py [name ...]      # title day night danger; none given = all four

Every loop is mono, 22050 Hz, 16-bit and is built so that its end runs into its start without a click: each
voice is rendered over a longer buffer and the tail is folded back onto the front, the reverb and the filters
are circular (done in the frequency domain). The seed is fixed, so the files come out the same every time.

The score is a placeholder, as the spec says (a composer, or licensed tracks, before release); what it has to
do is not be silence: a slow pad and a low drone for the town by day, a thin colder one at night with a pulse
under it, and a darker one with a faster pulse when the dead are at the wall. The key is A minor throughout so
the loops can cross-fade into each other without a clash.
"""
import sys
import wave

import numpy as np

SR = 22050
OUT = "assets/audio/music_%s.wav"

# A minor, in Hz. Notes by name keep the score readable.
NOTE = {}
for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]):
    for octave in range(1, 8):
        NOTE["%s%d" % (n, octave)] = 440.0 * 2 ** ((12 * (octave - 4) + i - 9) / 12.0)


class Loop:
    """A loop of `seconds`, mixed from voices that wrap round the end."""

    def __init__(self, seconds, seed):
        self.n = int(round(seconds * SR))
        self.buf = np.zeros(self.n)
        self.rng = np.random.default_rng(seed)

    def add(self, start, sound, gain=1.0):
        """Adds `sound` (a sample array) at `start` seconds, its tail wrapping to the front."""
        i = int(round(start * SR)) % self.n
        s = sound * gain
        while len(s) > 0:
            take = min(len(s), self.n - i)
            self.buf[i:i + take] += s[:take]
            s = s[take:]
            i = 0

    def reverb(self, seconds, wet):
        """Circular convolution with a decaying noise: a room that wraps round the loop."""
        m = int(seconds * SR)
        t = np.arange(m) / SR
        ir = self.rng.standard_normal(m) * np.exp(-t * (6.9 / seconds))
        ir[:int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))
        # darken the room: a one-pole lowpass of the impulse response
        for k in range(1, m):
            ir[k] = ir[k - 1] * 0.55 + ir[k] * 0.45
        ir /= np.sqrt(np.sum(ir ** 2))
        full = np.zeros(self.n)
        full[:min(m, self.n)] = ir[:self.n]
        wetsig = np.fft.irfft(np.fft.rfft(self.buf) * np.fft.rfft(full), self.n)
        self.buf = self.buf * (1.0 - wet) + wetsig * wet * 2.2

    def lowpass(self, cutoff):
        f = np.fft.rfftfreq(self.n, 1.0 / SR)
        self.buf = np.fft.irfft(np.fft.rfft(self.buf) / (1.0 + (f / cutoff) ** 4), self.n)

    def highpass(self, cutoff):
        f = np.fft.rfftfreq(self.n, 1.0 / SR)
        x = (f / cutoff) ** 4
        self.buf = np.fft.irfft(np.fft.rfft(self.buf) * x / (1.0 + x), self.n)

    def write(self, name, peak=0.55):
        b = self.buf - np.mean(self.buf)
        b = np.tanh(b / max(np.max(np.abs(b)), 1e-9) * 1.3) / np.tanh(1.3)   # a soft clip keeps the loudest note in check
        b = b / max(np.max(np.abs(b)), 1e-9) * peak
        # a few milliseconds of fade-in/out would click the loop; the wrap is already seamless, so none
        data = (b * 32767).astype("<i2")
        with wave.open(OUT % name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(data.tobytes())
        print("%s: %.1f s, rms %.3f, %d KB" % (name, self.n / SR, float(np.sqrt(np.mean(b ** 2))), data.nbytes // 1024))


# ----------------------------------------------------------------------------------------------- voices

def pad(freq, seconds, attack, release, rng, bright=0.5, detune=0.0035):
    """A soft chord tone: a few slightly detuned partials with a slow swell and fall."""
    n = int((seconds + release) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, amp in enumerate([1.0, 0.5 * bright + 0.2, 0.28 * bright, 0.14 * bright, 0.07 * bright], start=1):
        for d in (-detune, 0.0, detune):
            ph = rng.uniform(0, 2 * np.pi)
            out += amp * np.sin(2 * np.pi * freq * k * (1 + d * k * 0.5) * t + ph)
    env = np.minimum(1.0, t / attack) ** 2
    fall = np.clip((seconds + release - t) / release, 0.0, 1.0) ** 2
    return out * env * fall / 9.0


def bell(freq, seconds, rng, hardness=1.0):
    """A struck, slightly hollow tone: inharmonic partials with their own decays (a glass or a soft chime)."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, decay in [(1.0, 1.0, 1.2), (2.0, 0.45, 1.8), (2.76, 0.30 * hardness, 3.0), (4.07, 0.14 * hardness, 4.5), (5.4, 0.07 * hardness, 6.0)]:
        out += amp * np.sin(2 * np.pi * freq * ratio * t + rng.uniform(0, 6.28)) * np.exp(-t * decay)
    out *= np.minimum(1.0, t / 0.004)
    return out / 2.0


def pluck(freq, seconds, rng):
    """A plucked string (Karplus-Strong), dark and short: a piano in an empty room."""
    n = int(seconds * SR)
    period = max(2, int(round(SR / freq)))
    buf = rng.uniform(-1, 1, period)
    buf = np.convolve(buf, np.ones(3) / 3, mode="same")
    out = np.zeros(n)
    for i in range(n):
        j = i % period
        out[i] = buf[j]
        buf[j] = 0.4985 * (buf[j] + buf[(j + 1) % period])
    return out * np.exp(-np.arange(n) / SR * 0.6)


def drone(freq, seconds, rng, wobble=0.08, wobble_hz=0.1):
    """A low tone that breathes: two sines and a quiet fifth above, under a very slow tremolo (a whole number of
    cycles over the loop, so it closes)."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    cycles = max(1, round(wobble_hz * seconds))
    trem = 1.0 + wobble * np.sin(2 * np.pi * cycles / seconds * t + rng.uniform(0, 6.28))
    # every partial is snapped to a whole number of cycles over the loop, so the drone closes on itself
    def snap(f):
        return max(1, round(f * seconds)) / seconds
    out = (np.sin(2 * np.pi * snap(freq) * t) + 0.5 * np.sin(2 * np.pi * snap(freq * 2.003) * t)
           + 0.18 * np.sin(2 * np.pi * snap(freq * 3.01) * t))
    return out * trem / 1.7


def thump(seconds=0.5, f0=95.0, f1=38.0):
    """A heartbeat-low drum: a sine that drops in pitch, and dies away."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 9.0) * np.minimum(1.0, t / 0.003)


def air(rng, n, lo, hi, seconds):
    """Band-passed noise, a wind: made as one circular piece."""
    x = rng.standard_normal(n)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    h = np.exp(-((np.log(np.maximum(f, 1.0)) - np.log(np.sqrt(lo * hi))) / np.log(hi / lo) * 2.2) ** 2)
    return np.fft.irfft(np.fft.rfft(x) * h, n)


def swell(n, seconds, cycles, phase=0.0):
    """A slow 0..1 swell with a whole number of cycles over the loop."""
    t = np.arange(n) / SR
    return 0.5 - 0.5 * np.cos(2 * np.pi * cycles / seconds * t + phase)


# ----------------------------------------------------------------------------------------------- the loops

def title():
    """The title screen: a warm dusk, a long chord cycle, a few notes of glass over it. 64 s, 56 BPM-ish."""
    secs = 64.0
    L = Loop(secs, 11)
    rng = L.rng
    chords = [("A2", "E3", "A3", "C4"), ("F2", "C3", "F3", "A3"), ("C3", "G3", "C4", "E4"), ("G2", "D3", "G3", "B3")]
    step = secs / len(chords)
    for i, ch in enumerate(chords):
        for note in ch:
            L.add(i * step - 1.5, pad(NOTE[note], step + 1.0, 3.5, 4.5, rng, bright=0.55), 1.0)
    L.add(0, drone(NOTE["A1"], secs, rng, 0.1, 0.0625), 0.55)
    # the melody: sparse, high, unhurried
    tune = [(2.0, "E5"), (6.0, "C5"), (10.0, "D5"), (13.0, "A4"), (18.0, "C5"), (22.5, "A4"), (26.0, "G4"), (30.0, "E5"),
            (34.0, "D5"), (38.0, "C5"), (42.0, "E5"), (46.0, "G5"), (50.0, "E5"), (54.0, "D5"), (58.0, "B4"), (61.0, "A4")]
    for at, n in tune:
        L.add(at, bell(NOTE[n], 9.0, rng, 0.8), 0.5)
    L.add(0, air(rng, L.n, 120, 700, secs) * (0.35 + 0.25 * swell(L.n, secs, 2)), 0.12)
    L.reverb(2.6, 0.45)
    L.write("title")


def day():
    """By day: the school's quiet. A thin pad that moves slowly between two chords, a low drone, a plucked note now
    and then, the wind. 72 s."""
    secs = 72.0
    L = Loop(secs, 21)
    rng = L.rng
    chords = [("A2", "E3", "B3"), ("A2", "E3", "C4"), ("F2", "C3", "A3"), ("D2", "A2", "F3"), ("E2", "B2", "G3"), ("A2", "E3", "C4")]
    step = secs / len(chords)
    for i, ch in enumerate(chords):
        for note in ch:
            L.add(i * step - 2.0, pad(NOTE[note], step + 2.0, 4.5, 5.5, rng, bright=0.3), 0.8)
    L.add(0, drone(NOTE["A1"], secs, rng, 0.06, 0.0833), 0.5)
    pl = [(5.0, "A3"), (9.5, "E4"), (14.0, "C4"), (24.0, "A3"), (28.5, "G3"), (33.0, "E4"), (40.5, "D4"), (45.0, "A3"), (51.0, "C4"),
          (57.0, "E4"), (62.5, "A3"), (67.0, "G3")]
    for at, n in pl:
        L.add(at, pluck(NOTE[n], 6.0, rng), 0.55)
    L.add(0, air(rng, L.n, 80, 500, secs) * (0.3 + 0.7 * swell(L.n, secs, 3)), 0.16)
    L.reverb(2.2, 0.4)
    L.write("day")


def night():
    """After dusk: colder and thinner. A low drone, a pad with the third left out, high glass, a slow heartbeat
    under it. 60 s, the pulse at 42 per minute."""
    secs = 60.0
    L = Loop(secs, 31)
    rng = L.rng
    L.add(0, drone(NOTE["A1"], secs, rng, 0.12, 0.1), 0.8)
    L.add(0, drone(NOTE["E2"], secs, rng, 0.1, 0.0667), 0.35)
    chords = [("A2", "E3", "G3"), ("F2", "C3", "E3"), ("A2", "E3", "G3"), ("E2", "B2", "D3")]
    step = secs / len(chords)
    for i, ch in enumerate(chords):
        for note in ch:
            L.add(i * step - 2.0, pad(NOTE[note], step + 2.0, 5.0, 6.0, rng, bright=0.25), 0.55)
    gl = [(3.0, "E6"), (9.0, "B5"), (16.0, "G5"), (23.0, "E6"), (31.0, "C6"), (38.0, "D6"), (45.0, "B5"), (52.0, "A5")]
    for at, n in gl:
        L.add(at, bell(NOTE[n], 8.0, rng, 1.2), 0.22)
    beat = 60.0 / 42.0
    for k in range(int(secs / beat)):
        L.add(k * beat, thump(0.55), 0.45)
        L.add(k * beat + 0.28, thump(0.5, 80, 36), 0.22)
    L.add(0, air(rng, L.n, 60, 400, secs) * (0.4 + 0.6 * swell(L.n, secs, 4, 1.0)), 0.2)
    L.reverb(3.0, 0.5)
    L.write("night")


def danger():
    """The dead at the wall: the drone drops, the pulse quickens to 84 and a cluster of close notes grinds above it.
    40 s."""
    secs = 40.0
    L = Loop(secs, 41)
    rng = L.rng
    L.add(0, drone(NOTE["A1"], secs, rng, 0.2, 0.15), 0.9)
    L.add(0, drone(NOTE["F1"], secs, rng, 0.15, 0.1), 0.6)
    for note, gain in [("A2", 0.5), ("B2", 0.35), ("E3", 0.4), ("F3", 0.3), ("G#3", 0.22)]:
        L.add(-1.0, pad(NOTE[note], secs + 1.0, 6.0, 5.0, rng, bright=0.7, detune=0.006), gain * 0.8)
    beat = 60.0 / 84.0
    for k in range(int(secs / beat) + 1):
        if k * beat >= secs - 0.1:
            break
        L.add(k * beat, thump(0.45, 110, 40), 0.7 if k % 4 == 0 else 0.5)
        if k % 2 == 1:
            L.add(k * beat + beat * 0.5, thump(0.3, 150, 60), 0.25)
    hits = [(4.0, "A4"), (12.0, "E4"), (20.0, "F4"), (28.0, "G#4"), (34.0, "E4")]
    for at, n in hits:
        L.add(at, bell(NOTE[n], 6.0, rng, 1.6), 0.25)
    L.add(0, air(rng, L.n, 200, 1800, secs) * (0.3 + 0.7 * swell(L.n, secs, 5)), 0.2)
    L.reverb(1.8, 0.35)
    L.highpass(30)
    L.write("danger")


if __name__ == "__main__":
    which = sys.argv[1:] or ["title", "day", "night", "danger"]
    for name in which:
        globals()[name]()
