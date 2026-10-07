#!/usr/bin/env python3
"""Measures sounds the way the mix table (docs/audio-mix.md) talks about them: no ear involved, only numbers.

    python3 tools/audio_measure.py assets/audio/groan_0.wav assets/audio/rain_loop.wav ...
    python3 tools/audio_measure.py --md assets/audio/fs_*.wav          # markdown rows

What it prints for each 16-bit mono WAV
  dur     seconds
  peak    the loudest sample, dBFS
  rms     root-mean-square over the whole file, dBFS
  M-max   the loudest MOMENTARY LOUDNESS (a 400 ms window, K-weighted as in ITU-R BS.1770 / EBU R128, stepped every 100 ms), in LUFS.
          A sound shorter than 400 ms is measured as it would be heard in that window (the rest of the window is silence), so a click and a
          bed are on one scale. LU (loudness units) are differences of these: 1 LU is 1 dB.
  M-mean  the mean of the momentary loudness over the windows that are within 25 LU of the loudest one (for a bed or a loop this is its
          steady loudness; for a one-shot it is about the same as M-max)
  cent    the spectral centroid, Hz: the power-weighted mean frequency of the whole file (low = dull, high = bright / hissy)

The K-weighting is the standard's two biquads (a high shelf of +4 dB above 1.5 kHz and a 38 Hz high-pass) at 48 kHz; the sound is resampled
to 48 kHz first (linear interpolation: good enough for loudness). No SciPy: the filters are applied in the frequency domain.
"""
import os
import sys
import wave

import numpy as np

K_SR = 48000
# ITU-R BS.1770-4, the coefficients for 48 kHz
_S1_B = np.array([1.53512485958697, -2.69169618940638, 1.19839281085285])
_S1_A = np.array([1.0, -1.69065929318241, 0.73248077421585])
_S2_B = np.array([1.0, -2.0, 1.0])
_S2_A = np.array([1.0, -1.99004745483398, 0.99007225036621])


def read_wav(path):
    """(samples as float in -1..1, sample rate) of a 16-bit mono (or the first channel of a stereo) PCM wav."""
    with wave.open(path, "rb") as w:
        n = w.getnframes()
        ch = w.getnchannels()
        raw = w.readframes(n)
        sr = w.getframerate()
        assert w.getsampwidth() == 2, "16-bit only: %s" % path
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch)[:, 0]
    return x, sr


def db(x):
    return 20.0 * np.log10(max(float(x), 1e-12))


def resample(x, sr, to=K_SR):
    if sr == to:
        return x
    n = int(round(len(x) * to / sr))
    return np.interp(np.arange(n) * sr / to, np.arange(len(x)), x)


def _response(b, a, f, sr):
    z = np.exp(-1j * 2.0 * np.pi * f / sr)
    return (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)


def k_weight(x, sr=K_SR):
    """The K-weighted signal (the standard's two stages, applied through the FFT; the signal is padded so that the filters' ringing is not wrapped)."""
    n = len(x)
    m = 1 << int(np.ceil(np.log2(n + int(0.5 * sr) + 1)))
    f = np.fft.rfftfreq(m, 1.0 / sr)
    h = _response(_S1_B, _S1_A, f, sr) * _response(_S2_B, _S2_A, f, sr)
    return np.fft.irfft(np.fft.rfft(x, m) * h, m)[:n]


def momentary(x, sr):
    """The momentary loudness (LUFS) of each 400 ms window, every 100 ms (the first window starts 300 ms before the sound, so that a short sound is in one whole window)."""
    y = resample(np.asarray(x, dtype=np.float64), sr)
    pad = int(0.3 * K_SR)
    y = np.concatenate([np.zeros(pad), y, np.zeros(int(0.4 * K_SR))])
    k = k_weight(y)
    win = int(0.4 * K_SR)
    hop = int(0.1 * K_SR)
    sq = k * k
    c = np.concatenate([[0.0], np.cumsum(sq)])
    out = []
    for s in range(0, len(k) - win + 1, hop):
        ms = (c[s + win] - c[s]) / win
        out.append(-0.691 + 10.0 * np.log10(max(ms, 1e-14)))
    return np.array(out)


def centroid(x, sr):
    spec = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    return float((spec * f).sum() / max(spec.sum(), 1e-18))


def stats(x, sr):
    """A dictionary of the numbers (see the header)."""
    m = momentary(x, sr)
    mmax = float(m.max())
    near = m[m >= mmax - 25.0]
    # the mean is taken in the energy domain over the windows near the top
    mmean = float(10.0 * np.log10(np.mean(10.0 ** (near / 10.0))))
    return {
        "dur": len(x) / sr,
        "rate": sr,
        "peak": db(np.max(np.abs(x))),
        "rms": db(np.sqrt(np.mean(x ** 2))),
        "mmax": mmax,
        "mmean": mmean,
        "cent": centroid(x, sr),
    }


def stats_of(path):
    x, sr = read_wav(path)
    s = stats(x, sr)
    s["file"] = os.path.basename(path)
    s["bytes"] = os.path.getsize(path)
    return s


def line(s, md=False):
    if md:
        return "| %s | %.2f | %.1f | %.1f | %.1f | %.0f |" % (s["file"], s["dur"], s["peak"], s["rms"], s["mmax"], s["cent"])
    return "%-26s %5.2f s %5d Hz  peak %6.1f  rms %6.1f dBFS  M-max %6.1f  M-mean %6.1f LUFS  centroid %5.0f Hz" % (
        s["file"], s["dur"], s["rate"], s["peak"], s["rms"], s["mmax"], s["mmean"], s["cent"])


def main():
    md = "--md" in sys.argv
    paths = [a for a in sys.argv[1:] if not a.startswith("--")]
    if md:
        print("| file | s | peak dBFS | RMS dBFS | M-max LUFS | centroid Hz |")
        print("|---|---|---|---|---|---|")
    for p in paths:
        print(line(stats_of(p), md))


if __name__ == "__main__":
    main()
