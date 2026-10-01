#!/usr/bin/env python3
"""Synthesises the menu sounds: five short mono 16-bit 44.1 kHz WAVs in assets/audio/
(the same format as the other sounds there), named like them with a variant number:

    ui_click_0.wav     a chalk tick: a hair of noise and a tiny wooden tock
    ui_confirm_0.wav   a small two-note bell (a fifth up), for "done" and "go"
    ui_error_0.wav     two dull knocks, for "no"
    ui_open_0.wav      a soft rising swish, for a page or a menu opening
    ui_close_0.wav     the same falling, for one closing

Nothing is downloaded or recorded: every sample comes from NumPy, with a fixed seed, so
running this again writes the same files. They are played through the `UI` bus
(scripts/audio/sound.gd, Sound.ui). Run from the repository root:

    python3 tools/make_ui_sounds.py            # writes assets/audio/ui_*_0.wav
    python3 tools/make_ui_sounds.py --check    # only prints the numbers, writes nothing

After adding or changing files, let Godot import them once:
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
"""
import os
import sys
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")


def axis(seconds):
    return np.arange(int(round(SR * seconds))) / SR


def rise(t, seconds):
    """0 to 1 over `seconds`, then 1."""
    return np.minimum(1.0, t / max(seconds, 1e-6))


def sweep_noise(seconds, f_start, f_end, rng, damping=0.3):
    """White noise through a band-pass whose middle frequency glides from f_start to f_end
    (a Chamberlin state-variable filter): the swish of a page, a hand over paper."""
    n = int(round(SR * seconds))
    x = rng.standard_normal(n)
    low = band = 0.0
    out = np.empty(n)
    for i in range(n):
        f = f_start + (f_end - f_start) * i / max(n - 1, 1)
        k = 2.0 * np.sin(np.pi * f / SR)
        low += k * band
        high = x[i] - low - damping * band
        band += k * high
        out[i] = band
    return out / (np.max(np.abs(out)) + 1e-9)


def bell(freq, seconds, tau):
    """A struck bell: a few inharmonic partials, the higher ones dying sooner."""
    t = axis(seconds)
    out = np.zeros_like(t)
    for ratio, amp in ((1.0, 1.0), (2.0, 0.42), (2.76, 0.30), (5.4, 0.12)):
        out += amp * np.sin(2.0 * np.pi * freq * ratio * t) * np.exp(-t / (tau / ratio ** 0.5))
    return out * rise(t, 0.002)


def knock(f0, seconds, rng):
    """A dull knock: a low tone that sags in pitch, with a puff of noise at the start."""
    t = axis(seconds)
    f = f0 * (1.0 - 0.3 * np.minimum(1.0, t / 0.08))
    phase = 2.0 * np.pi * np.cumsum(f) / SR
    tone = (np.sin(phase) + 0.35 * np.sin(2.0 * phase + 0.6)) * np.exp(-t / 0.05)
    puff = rng.standard_normal(t.size) * np.exp(-t / 0.006)
    return (tone + 0.25 * puff) * rise(t, 0.001)


def place(into, sound, at_seconds, gain=1.0):
    i = int(round(at_seconds * SR))
    j = min(into.size, i + sound.size)
    into[i:j] += gain * sound[: j - i]


def finish(x, peak):
    """No DC, a click-free start and end, scaled to `peak` (0 to 1), as 16-bit."""
    x = x - np.mean(x)
    n = x.size
    a = min(int(0.001 * SR), n // 4)
    b = min(int(0.010 * SR), n // 2)
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[-b:] *= np.linspace(1.0, 0.0, b)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    return np.round(x * 32767.0).astype(np.int16)


def ui_click():
    rng = np.random.default_rng(11)
    t = axis(0.075)
    tick = np.diff(rng.standard_normal(t.size + 1)) * np.exp(-t / 0.004)  # differenced noise: all treble
    tick /= np.max(np.abs(tick)) + 1e-9
    f = 520.0 + 700.0 * np.exp(-t / 0.03)
    tock = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.012)
    return finish(0.55 * tick + 0.45 * tock, 0.45)


def ui_confirm():
    x = np.zeros(int(SR * 0.55))
    place(x, bell(740.0, 0.5, 0.17), 0.0, 0.8)
    place(x, bell(1110.0, 0.45, 0.2), 0.085, 1.0)
    return finish(x, 0.5)


def ui_error():
    rng = np.random.default_rng(23)
    x = np.zeros(int(SR * 0.30))
    place(x, knock(150.0, 0.18, rng), 0.0, 1.0)
    place(x, knock(122.0, 0.2, rng), 0.115, 0.9)
    return finish(x, 0.55)


def ui_open():
    rng = np.random.default_rng(37)
    t = axis(0.19)
    swish = sweep_noise(0.19, 700.0, 3300.0, rng) * rise(t, 0.035) * np.exp(-t / 0.075)
    blip = np.sin(2.0 * np.pi * 523.0 * t) * np.exp(-t / 0.03) * rise(t, 0.004)
    return finish(0.85 * swish + 0.22 * blip, 0.4)


def ui_close():
    rng = np.random.default_rng(41)
    t = axis(0.14)
    swish = sweep_noise(0.14, 3000.0, 650.0, rng) * rise(t, 0.012) * np.exp(-t / 0.055)
    blip = np.sin(2.0 * np.pi * 330.0 * t) * np.exp(-t / 0.028) * rise(t, 0.004)
    return finish(0.85 * swish + 0.2 * blip, 0.36)


SOUNDS = {
    "ui_click": ui_click,
    "ui_confirm": ui_confirm,
    "ui_error": ui_error,
    "ui_open": ui_open,
    "ui_close": ui_close,
}


def write(name, samples):
    path = os.path.join(OUT, "%s_0.wav" % name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(samples.tobytes())
    return path


def main():
    check_only = "--check" in sys.argv
    print("%-12s %8s %8s %8s" % ("sound", "seconds", "peak", "rms dB"))
    for name, make in SOUNDS.items():
        s = make()
        f = s.astype(np.float64) / 32767.0
        rms = 20.0 * np.log10(np.sqrt(np.mean(f * f)) + 1e-12)
        print("%-12s %8.3f %8.3f %8.1f" % (name, s.size / SR, np.max(np.abs(f)), rms))
        if not check_only:
            write(name, s)
    if not check_only:
        print("written to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
