#!/usr/bin/env python3
"""The score of Thirty Bells: mono 16-bit WAVs in assets/audio/ (mus_*.wav), made from arithmetic only, with a fixed seed per piece
(running it again writes the same files). Needs Python 3 and NumPy; the voices are in tools/audio_dsp.py.

    python3 tools/make_score.py              # all of them
    python3 tools/make_score.py indoors night  # just those groups: title indoors outdoors night fortress stingers endcard
    python3 tools/make_score.py --check      # render everything but write nothing (prints the numbers)

THE KEY IS A MINOR (A B C D E F G, no sharps), and its relative major, C: the dusk bell is tuned to A, the dawn and the rescue
resolve to C, the end card is the title's tune turned to the major. Every note below is a natural note and the generator checks that
(`check_in_key`). Sparse and slow: a felt piano, a lonely bowed string, a low drone pad, and in the night a heartbeat and soft drums;
nothing is fast. It is a placeholder for a composed score, and it was made without a way to hear it: the numbers (level, loop seam,
notes in key) are checked by machine, the taste is the owner's.

THE STATES THE GAME PLAYS (scripts/audio/music.gd picks them; nothing here knows a map)
    indoors     a cleared house: very sparse and quiet, a few piano notes in a small room
    outdoors    the day outside, exploring: tense, a drone with a semitone in it, a high string, a far heart
    night       the night outside: very tense; a pad, a heartbeat that comes in with the dead, soft drums when many are near
    fortress    the fortified house under attack: the lament bass A G F E, a heavy drum, a low brass, war drums, by the threat
    endcard     the end of the demo: the tune in C major, hopeful
    title       the title screen: the tune in A minor
    stingers    dusk (the bell), dawn (relief), rescue (warm and short), defeat

THE TUNE (the "bell motif": the minor triad a bell is made of, A C E, answered by a step down):
    bars 1-4   A4 C5 E5 | D5 . . C5 | C5 A4 | G4 ...          (Am Am F C: a question that ends on G)
    bars 5-8   A4 C5 E5 | F5 . . E5 | D5 C5 B4 | A4 ...        (Am Dm Em Am: the answer, home on A)
The title plays it in A minor, the end card turns it to the major, the other pieces keep only pieces of it.

WHAT IS MADE (rate, length; the stems of a mood are the same length and are meant to be played together)
    mus_title.wav          16 kHz  32 s   the tune on a felt piano over strings, a distant bell
    mus_indoors.wav        16 kHz  64 s   60 BPM, 16 bars: eleven piano notes, a drone and a pad far down, a small room
    mus_outdoors.wav       16 kHz  64 s   60 BPM: an A and E drone with an F against the E, a cluster pad, a high string that steps a semitone
    mus_night_base.wav     16 kHz  32 s   60 BPM, 8 bars: an A pedal under open fifths, glass notes                  (always)
    mus_night_pulse.wav    16 kHz  32 s   a low heartbeat on every beat                                              (the dead near)
    mus_night_perc.wav     16 kHz  32 s   soft frame drums, a shaker late in the loop                                (many dead near)
    mus_fortress_base.wav  16 kHz  32 s   the lament bass A G F E under dark chords and string tremolo
    mus_fortress_pulse.wav 12 kHz  32 s   a heavy low drum, boom ... boom-boom
    mus_fortress_brass.wav 12 kHz  32 s   a low brass drone on the bass line
    mus_fortress_perc.wav  16 kHz  32 s   war drums, an anvil, a shaker
    mus_dusk.wav           22 kHz  12 s   the stinger of the bell: a swelling drone, the motif slow on strings
    mus_dawn.wav           22 kHz  10 s   the relief: the night's A minor opens into C major
    mus_rescue.wav         22 kHz   7 s   someone found: three rising piano notes of C major and a warm string
    mus_defeat.wav         22 kHz   9 s   a low bell twice, the bass sinking A G F E, a last high note
    mus_endcard.wav        16 kHz  32 s   the tune in C major, hopeful (the end of the demo; it loops)

Levels are set so that the stems of a mood, played together at their full volume, come to about: indoors -27 dBFS RMS, outdoors -23,
night -23 (base) to -17 (all), fortress -22 (base) to -15 (all), title -19, end card -18 (the manifest, assets/audio/audio_manifest.json,
has every file's numbers; the game's Music bus is at 0 dB and ducks under big events). Peaks stay under -2 dBFS. Every loop's seam (the
step from its last sample to its first, against a normal step) is checked.

After adding or changing files, let Godot import them once:
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as D  # noqa: E402

WRITE = "--check" not in sys.argv
NATURALS = {"A", "B", "C", "D", "E", "F", "G"}
ALL_NOTES = []   # every note name used, for the key check


def note(name):
    ALL_NOTES.append(name)
    return D.hz(name)


def check_in_key():
    bad = sorted(set(n for n in ALL_NOTES if n[0] not in NATURALS or (len(n) > 2 and n[1] in "#b")))
    assert not bad, "notes outside A minor / C major: %s" % bad


def out(name, x, sr, loop, kind, seed, notes=""):
    st = D.save(name, x, sr, loop=loop, kind=kind, seed=seed, notes=notes) if WRITE else _stats_only(name, x, sr, loop)
    D.report(st)
    assert st["peak_db"] <= -1.9, "%s peaks at %.1f dBFS" % (name, st["peak_db"])
    assert st["clipped"] == 0, name
    if loop:
        assert st["seam"] <= 6.0, "%s: the loop does not close (seam %.2f)" % (name, st["seam"])
    return st


def _stats_only(name, x, sr, loop):
    return {"file": name + ".wav", "rate": sr, "seconds": len(x) / sr, "peak_db": D.peak_db(x), "rms_db": D.rms_db(x),
            "clipped": D.clipped(x), "seam": D.seam_ratio(x) if loop else None, "bytes": len(x) * 2}


# ------------------------------------------------------------------------------------------------ the harmony

# (pad voicing, bass note) of each chord, in the register the voices want
CHORD = {
    "Am": (["A3", "C4", "E4"], "A2"),
    "F": (["F3", "A3", "C4"], "F2"),
    "C": (["G3", "C4", "E4"], "C3"),
    "G": (["G3", "B3", "D4"], "G2"),
    "Dm": (["D3", "F3", "A3"], "D3"),
    "Em": (["E3", "G3", "B3"], "E2"),
}


def chord_pad(L, rng, name, start, length, gain, attack=2.0, release=2.5, bright=0.45, voices=3, lift=0):
    tones, _ = CHORD[name]
    for tone in tones:
        f = note(tone) * (2.0 ** lift)
        L.add(start, D.pad(f, length, L.sr, rng, attack, release, bright, voices), gain)


def chord_bass(L, rng, name, start, length, gain, attack=0.7, release=1.2, vel=0.5):
    _, bass = CHORD[name]
    L.add(start, D.bowed(note(bass), length, L.sr, rng, vel, attack, release, voices=2, bright=0.7), gain)


def drone(L, f, cycles_lfo, depth, gain, harm=(1.0, 0.45, 0.16, 0.06)):
    """A tone that fills the loop exactly (each partial snapped to a whole number of cycles) with a slow swell."""
    t = np.arange(L.n) / L.sr
    x = np.zeros(L.n)
    for k, a in enumerate(harm, start=1):
        fk = max(1, round(f * k * L.seconds)) / L.seconds
        x += a * np.sin(D.TAU * fk * t + L.rng.uniform(0, D.TAU))
    lfo = 1.0 + depth * np.sin(D.TAU * cycles_lfo / L.seconds * t + L.rng.uniform(0, D.TAU))
    L.add_loop(x * lfo / (1.0 + sum(harm)), gain)


def put_piano(L, rng, events, bar_s, beat_s, gain=1.0, jitter=0.012, ring=6.0, bright=1.0):
    """events: (beat, note name, beats held, velocity); beat counted from the start of the loop."""
    for beat, name, held, vel in events:
        at = beat * beat_s + rng.uniform(-jitter, jitter)
        v = float(np.clip(vel * rng.uniform(0.92, 1.06), 0.05, 1.0))
        L.add(at, D.piano(note(name), ring, v, L.sr, rng, bright=bright), gain)


# ------------------------------------------------------------------------------------------------ the tune

TUNE = [  # (beat, note, beats, velocity) in A minor, 8 bars of 4 beats
    (0, "A4", 2, 0.72), (2, "C5", 1, 0.60), (3, "E5", 1, 0.66),
    (4, "D5", 3, 0.70), (7, "C5", 1, 0.55),
    (8, "C5", 2, 0.62), (10, "A4", 2, 0.58),
    (12, "G4", 4, 0.66),
    (16, "A4", 2, 0.72), (18, "C5", 1, 0.60), (19, "E5", 1, 0.66),
    (20, "F5", 3, 0.70), (23, "E5", 1, 0.55),
    (24, "D5", 2, 0.62), (26, "C5", 1, 0.56), (27, "B4", 1, 0.50),
    (28, "A4", 4, 0.70),
]
TUNE_BARS = ["Am", "Am", "F", "C", "Am", "Dm", "Em", "Am"]

TUNE_MAJOR = [  # the end card: the same tune turned to the major, and it climbs at the end
    (0, "A4", 2, 0.66), (2, "C5", 1, 0.60), (3, "E5", 1, 0.68),
    (4, "F5", 3, 0.72), (7, "E5", 1, 0.58),
    (8, "E5", 2, 0.66), (10, "D5", 1, 0.58), (11, "C5", 1, 0.58),
    (12, "D5", 3, 0.66), (15, "B4", 1, 0.52),
    (16, "A4", 2, 0.70), (18, "C5", 1, 0.62), (19, "E5", 1, 0.70),
    (20, "G5", 3, 0.76), (23, "F5", 1, 0.60),
    (24, "B4", 2, 0.66), (26, "D5", 2, 0.66),
    (28, "C5", 4, 0.78),
]
MAJOR_BARS = ["Am", "F", "C", "G", "Am", "F", "G", "C"]


# ------------------------------------------------------------------------------------------------ title

def title():
    sr, secs = 16000, 32.0
    L = D.Loop(secs, sr, 11)
    rng = L.rng
    beat, bar = 1.0, 4.0
    # strings: a chord a bar, its bass under it
    for i, c in enumerate(TUNE_BARS):
        chord_pad(L, rng, c, i * bar - 1.0, bar + 0.6, 0.26, attack=1.6, release=2.4, bright=0.4)
        chord_bass(L, rng, c, i * bar - 0.2, bar - 0.2, 0.42, attack=0.8, release=1.4, vel=0.5)
    drone(L, note("A2"), 2, 0.06, 0.30)
    # the tune on the piano, and a left hand that only marks the first beat of the odd bars
    put_piano(L, rng, TUNE, bar, beat, 1.0, ring=7.0, bright=1.35)
    lh = [(0, "A2", 4, 0.50), (0, "E3", 4, 0.40), (8, "F2", 4, 0.45), (8, "C3", 4, 0.36), (12, "C3", 4, 0.42), (12, "G3", 4, 0.34),
          (16, "A2", 4, 0.48), (16, "E3", 4, 0.38), (20, "D3", 4, 0.44), (20, "A3", 4, 0.34), (24, "E2", 4, 0.46), (24, "B2", 4, 0.36)]
    put_piano(L, rng, lh, bar, beat, 0.55, ring=7.0, bright=0.7)
    # a distant bell on the first beat of each half: the game's name
    for at, nm in ((0.0, "A3"), (16.0, "A3")):
        L.add(at, D.chime(note(nm), 8.0, sr, rng, 0.8, partials=((0.5, 0.5, 7.0), (1.0, 1.0, 6.0), (1.2, 0.35, 4.0), (1.5, 0.45, 3.5), (2.0, 0.4, 2.5))), 0.30)
    L.room(3.2, 0.40, seed=12)
    L.highpass(45)
    L.master(-19.0, -2.5)
    return out("mus_title", L.buf, sr, True, "music", 11, "A minor tune on piano")


# ------------------------------------------------------------------------------------------------ indoors

def indoors():
    """A cleared house: very sparse. A drone and a pad far down, eleven piano notes with long silences between them in a small room."""
    sr, secs = 16000, 64.0
    L = D.Loop(secs, sr, 21)
    rng = L.rng
    slots = ["Am", "F", "Am", "Em"]          # 16 s each
    for i, c in enumerate(slots):
        chord_pad(L, rng, c, i * 16.0 - 2.0, 16.0 + 1.0, 0.20, attack=4.0, release=4.0, bright=0.30)
        chord_bass(L, rng, c, i * 16.0 - 1.0, 15.0, 0.16, attack=2.5, release=3.0, vel=0.35)
    drone(L, note("A2"), 2, 0.12, 0.10)
    notes = [(3.0, "E4", 0.40), (9.0, "A4", 0.36), (13.5, "C5", 0.34),
             (19.0, "A4", 0.34), (24.5, "C5", 0.32), (28.5, "F4", 0.34),
             (35.0, "A4", 0.40), (38.5, "C5", 0.36), (42.0, "E5", 0.36),
             (50.0, "B4", 0.30), (55.5, "G4", 0.30)]
    for at, nm, v in notes:
        L.add(at + rng.uniform(-0.05, 0.05), D.piano(note(nm), 6.5, v * rng.uniform(0.95, 1.05), sr, rng, bright=1.1), 0.95)
    L.add(60.0, D.piano(note("E4"), 6.5, 0.30, sr, rng, bright=1.0), 0.8)
    L.room(1.5, 0.28, predelay=0.006, damp=2.2, seed=22)     # a small room: short, warm
    L.highpass(45)
    L.master(-27.0, -11.0)
    return out("mus_indoors", L.buf, sr, True, "music", 21, "a cleared house, very sparse")


# ------------------------------------------------------------------------------------------------ outdoors

def outdoors():
    """The day outside, exploring: tense but slow. An A and E drone with an F that rubs against the E, a cluster pad whose notes lean on each
    other by a semitone (E F, B C: the two semitones of A minor), a high string that steps E5 to F5 and B4 to C5, a far heartbeat, a bit of
    metal and a glass note now and then."""
    sr, secs = 16000, 64.0
    L = D.Loop(secs, sr, 91)
    rng = L.rng
    drone(L, note("A1"), 2, 0.14, 0.34, harm=(1.0, 0.6, 0.25, 0.08))
    drone(L, note("E2"), 3, 0.12, 0.20)
    drone(L, note("F2"), 2, 0.30, 0.13)               # the semitone against the E: a slow beating
    clusters = [("E3", "F3", "A3"), ("D3", "E3", "A3", "B3"), ("E3", "F3", "B3", "C4"), ("D3", "F3", "A3", "E4")]
    for i, tones in enumerate(clusters):
        for tn in tones:
            L.add(i * 16.0 - 2.0, D.pad(note(tn), 17.0, sr, rng, 4.0, 4.5, 0.34, 3, 9.0), 0.34)
    for at, nm, held in ((4.0, "E5", 9.0), (12.5, "F5", 9.0), (36.0, "B4", 9.0), (44.5, "C5", 9.0)):
        L.add(at, D.bowed(note(nm), held, sr, rng, 0.30, attack=2.5, release=3.0, vib_rate=4.6, vib_depth=0.003, voices=2, bright=0.7), 0.60)
    for at, g in ((8.0, 0.6), (24.0, 0.5), (32.0, 0.6), (47.0, 0.5), (56.0, 0.6)):
        L.add(at, D.thump(sr, 100.0, 55.0, 0.9, 18.0, 0.2, 0.18, rng), g)
        L.add(at + 0.42, D.thump(sr, 90.0, 55.0, 0.7, 20.0, 0.14, 0.10, rng), g * 0.5)
    for at, f in ((14.0, 640.0), (27.0, 410.0), (39.5, 760.0), (53.0, 520.0)):
        L.add(at, D.clank(f, 0.5, sr, rng, 0.22), 0.6)
    for at, nm in ((21.0, "E6"), (59.0, "B5")):
        L.add(at, D.chime(note(nm), 5.0, sr, rng, 0.5), 0.20)
    L.room(3.0, 0.38, seed=92)
    L.highpass(32)
    L.master(-23.0, -9.0)
    return out("mus_outdoors", L.buf, sr, True, "music", 91, "tense exploring")


# ------------------------------------------------------------------------------------------------ stingers

def one_shot(L, rt60, wet, seed, seconds_tail=2.5):
    ir = D.reverb_ir(L.sr, rt60, np.random.default_rng(seed))
    y = D.with_reverb(L.buf, ir, wet, circular=False)
    return y


def dusk():
    sr, secs = 22050, 12.0
    L = D.Loop(secs + 4.0, sr, 51)       # rendered long, the tail is faded away below
    rng = L.rng
    L.add(0.0, D.pad(note("A2"), 9.0, sr, rng, 3.2, 3.0, 0.55, 3), 0.8)
    L.add(0.0, D.pad(note("E3"), 9.0, sr, rng, 3.6, 3.0, 0.45, 3), 0.6)
    L.add(1.2, D.pad(note("A3"), 8.0, sr, rng, 3.4, 3.0, 0.40, 3), 0.4)
    for at, nm, held in ((0.8, "A4", 3.0), (3.5, "C5", 3.0), (6.2, "E5", 4.0)):
        L.add(at, D.bowed(note(nm), held, sr, rng, 0.55, attack=0.9, release=1.8, voices=3, bright=0.9), 0.55)
    L.add(0.0, D.piano(note("A2"), 8.0, 0.6, sr, rng, bright=0.7), 0.9)
    L.add(6.2, D.piano(note("A3"), 6.0, 0.5, sr, rng, bright=0.8), 0.6)
    L.add(6.2, D.piano(note("E4"), 6.0, 0.42, sr, rng, bright=0.8), 0.5)
    L.add(9.0, D.chime(note("A5"), 5.0, sr, rng, 0.5), 0.25)
    y = one_shot(L, 3.4, 0.45, 52)[:int(secs * sr)]
    y = D.highpass(y, 40, sr, circular=False)
    y *= D.tail_off(len(y), sr, 3.0) * D.ramp(np.arange(len(y)) / sr, 0.25)
    y = y / (np.sqrt(np.mean(y ** 2)) + 1e-12) * 10 ** (-19.0 / 20)
    y = D.soft_ceiling(y, -3.0)
    return out("mus_dusk", y, sr, False, "stinger", 51, "the bell's stinger")


def dawn():
    sr, secs = 22050, 10.0
    L = D.Loop(secs + 4.0, sr, 61)
    rng = L.rng
    # the night's chord (A minor) for a moment, then it opens to C major
    for nm in ("A2", "E3", "A3", "C4"):
        L.add(0.0, D.pad(note(nm), 2.6, sr, rng, 0.8, 1.6, 0.4, 3), 0.55)
    for nm, g in (("C3", 0.7), ("G3", 0.5), ("E4", 0.45), ("G4", 0.35), ("D5", 0.25)):
        L.add(2.2, D.pad(note(nm), 7.0, sr, rng, 1.8, 3.0, 0.5, 3), g)
    L.add(0.4, D.bowed(note("E4"), 2.4, sr, rng, 0.5, 0.6, 1.0, voices=3), 0.4)
    L.add(2.4, D.bowed(note("G4"), 3.0, sr, rng, 0.58, 0.7, 1.2, voices=3), 0.5)
    L.add(5.0, D.bowed(note("C5"), 4.5, sr, rng, 0.62, 0.8, 1.6, voices=3), 0.55)
    for at, nm, v in ((2.5, "C5", 0.60), (3.2, "E5", 0.56), (3.9, "G5", 0.58), (5.4, "D5", 0.44), (6.3, "E5", 0.46), (7.4, "C5", 0.50)):
        L.add(at, D.piano(note(nm), 5.0, v, sr, rng, bright=1.0), 0.85)
    L.add(2.4, D.piano(note("C3"), 7.0, 0.55, sr, rng, bright=0.7), 0.8)
    L.add(3.1, D.chime(note("C6"), 5.0, sr, rng, 0.5), 0.30)
    L.add(6.0, D.chime(note("E6"), 4.0, sr, rng, 0.4), 0.20)
    y = one_shot(L, 2.8, 0.36, 62)[:int(secs * sr)]
    y = D.highpass(y, 40, sr, circular=False)
    y *= D.tail_off(len(y), sr, 2.5) * D.ramp(np.arange(len(y)) / sr, 0.2)
    y = y / (np.sqrt(np.mean(y ** 2)) + 1e-12) * 10 ** (-18.0 / 20)
    y = D.soft_ceiling(y, -3.0)
    return out("mus_dawn", y, sr, False, "stinger", 61, "relief, A minor to C major")


def rescue():
    """Someone found: three rising notes of C major on the piano, a warm string, a bell high up. Short."""
    sr, secs = 22050, 7.0
    L = D.Loop(secs + 3.0, sr, 111)
    rng = L.rng
    for nm, g in (("C3", 0.7), ("G3", 0.5), ("E4", 0.45), ("G4", 0.30)):
        L.add(0.0, D.pad(note(nm), 4.2, sr, rng, 0.9, 2.0, 0.5, 3), g)
    L.add(0.2, D.bowed(note("G4"), 2.0, sr, rng, 0.5, 0.5, 1.2, voices=3), 0.45)
    L.add(2.0, D.bowed(note("C5"), 3.0, sr, rng, 0.55, 0.6, 1.6, voices=3), 0.5)
    for at, nm, v in ((0.15, "C5", 0.60), (0.75, "E5", 0.58), (1.35, "G5", 0.62), (2.7, "E5", 0.42)):
        L.add(at, D.piano(note(nm), 4.5, v, sr, rng, bright=1.1), 0.85)
    L.add(0.15, D.piano(note("C3"), 5.0, 0.5, sr, rng, bright=0.7), 0.7)
    L.add(1.35, D.chime(note("C6"), 4.0, sr, rng, 0.5), 0.28)
    y = one_shot(L, 2.4, 0.30, 112)[:int(secs * sr)]
    y = D.highpass(y, 40, sr, circular=False)
    y *= D.tail_off(len(y), sr, 2.4) * D.ramp(np.arange(len(y)) / sr, 0.05)
    y = y / (np.sqrt(np.mean(y ** 2)) + 1e-12) * 10 ** (-19.0 / 20)
    y = D.soft_ceiling(y, -3.0)
    return out("mus_rescue", y, sr, False, "stinger", 111, "someone found: warm and short")


def defeat():
    sr, secs = 22050, 9.0
    L = D.Loop(secs + 4.0, sr, 71)
    rng = L.rng
    for at, nm, held in ((0.0, "A2", 2.6), (2.4, "G2", 2.6), (4.6, "F2", 2.6), (6.6, "E2", 3.4)):
        L.add(at, D.bowed(note(nm), held, sr, rng, 0.6, 0.5, 1.4, voices=3, bright=0.7), 0.9)
    L.add(0.0, D.pad(note("A3"), 7.0, sr, rng, 1.5, 3.0, 0.3, 3), 0.5)
    L.add(0.0, D.pad(note("E4"), 7.0, sr, rng, 1.8, 3.0, 0.3, 3), 0.4)
    L.add(0.0, D.piano(note("A2"), 8.0, 0.7, sr, rng, bright=0.6), 0.9)
    L.add(2.4, D.piano(note("E3"), 6.0, 0.5, sr, rng, bright=0.6), 0.6)
    for at, nm, v in ((4.4, "C5", 0.46), (5.8, "B4", 0.42), (7.1, "A4", 0.46)):
        L.add(at, D.piano(note(nm), 5.0, v, sr, rng, bright=0.8), 0.7)
    for at in (0.0, 3.4):
        L.add(at, D.chime(note("A2"), 8.0, sr, rng, 0.9, partials=((0.5, 0.6, 9.0), (1.0, 1.0, 7.0), (1.2, 0.4, 4.5), (1.5, 0.5, 4.0), (2.0, 0.45, 3.0))), 0.55)
    y = one_shot(L, 4.0, 0.50, 72)[:int(secs * sr)]
    y = D.highpass(y, 35, sr, circular=False)
    y *= D.tail_off(len(y), sr, 3.0) * D.ramp(np.arange(len(y)) / sr, 0.05)
    y = y / (np.sqrt(np.mean(y ** 2)) + 1e-12) * 10 ** (-17.0 / 20)
    y = D.soft_ceiling(y, -3.0)
    return out("mus_defeat", y, sr, False, "stinger", 71, "the sting of a lost run")


# ------------------------------------------------------------------------------------------------ night

NIGHT_UPPER = [("A3", "E4", "A4"), ("F3", "A3", "C4"), ("D3", "A3", "D4"), ("E3", "B3", "E4")]   # a pair of bars each, over an A pedal


def night():
    sr, secs = 16000, 32.0
    beat, bar = 1.0, 4.0
    # ------------------------------------------------ base
    L = D.Loop(secs, sr, 31)
    rng = L.rng
    drone(L, note("A1"), 2, 0.12, 0.55, harm=(1.0, 0.6, 0.22, 0.08))
    drone(L, note("E2"), 3, 0.10, 0.28)
    for i, tones in enumerate(NIGHT_UPPER):
        for tn in tones:
            L.add(i * 2 * bar - 1.4, D.pad(note(tn), 2 * bar + 0.6, sr, rng, 2.6, 3.0, 0.30, 3), 0.30)
    for at, nm in ((6.0, "E5"), (13.0, "C5"), (21.0, "A4"), (27.0, "B4")):
        L.add(at, D.chime(note(nm), 6.5, sr, rng, 0.6), 0.34)
    L.add(0.0, D.bowed(note("A3"), 7.5, sr, rng, 0.35, 2.5, 2.5, voices=2, bright=0.5), 0.35)
    L.add(16.0, D.bowed(note("A3"), 7.5, sr, rng, 0.35, 2.5, 2.5, voices=2, bright=0.5), 0.35)
    L.room(2.8, 0.40, seed=32)
    L.highpass(30)
    L.master(-23.0, -9.0)
    base_buf = L.buf.copy()
    out("mus_night_base", L.buf, sr, True, "music", 31, "night pad")

    # ------------------------------------------------ pulse: a heartbeat a beat
    P = D.Loop(secs, sr, 33)
    rng = P.rng
    accent = [1.0, 0.5, 0.8, 0.5]
    for k in range(int(secs / beat)):
        at = k * beat
        P.add(at, D.thump(sr, 120.0, 55.0, 0.7, 20.0, 0.17, 0.30, rng), 0.9 * accent[k % 4])
        if k % 2 == 0:
            P.add(at + 0.32, D.thump(sr, 105.0, 55.0, 0.5, 22.0, 0.12, 0.2, rng), 0.45)
    P.room(1.6, 0.25, seed=34)
    P.highpass(32)
    P.master(-23.0, -9.5)
    out("mus_night_pulse", P.buf, sr, True, "music", 33, "heartbeat")

    # ------------------------------------------------ percussion
    Q = D.Loop(secs, sr, 35)
    rng = Q.rng
    for b in range(8):
        t0 = b * bar
        Q.add(t0 + 0.0, D.tom(note("A2"), 1.2, sr, rng, 0.85, 0.30), 0.9)
        Q.add(t0 + 1.5, D.tom(note("E3"), 0.9, sr, rng, 0.38, 0.22), 0.7)
        Q.add(t0 + 2.0, D.tom(note("A2"), 1.2, sr, rng, 0.62, 0.28), 0.8)
        Q.add(t0 + 3.5, D.tom(note("A3"), 0.7, sr, rng, 0.34, 0.16), 0.6)
        if b in (3, 7):
            for k, v in enumerate((0.30, 0.38, 0.48, 0.60)):
                Q.add(t0 + 3.0 + k * 0.25, D.tom(note("E3") * (1.0 + 0.03 * k), 0.5, sr, rng, v, 0.14), 0.7)
        if b >= 4:
            for k in range(8):
                Q.add(t0 + k * 0.5 + 0.25, D.shaker(0.07, sr, rng, 0.16 + 0.04 * (k % 2)), 0.5)
    Q.room(1.8, 0.30, seed=36)
    Q.highpass(40)
    Q.master(-23.0, -9.5)
    out("mus_night_perc", Q.buf, sr, True, "music", 35, "soft drums")
    return base_buf


# ------------------------------------------------------------------------------------------------ the fortress

FORT_BASS = ["A", "G", "F", "E"]   # the lament bass, two bars each
FORT_ROOT_HZ = {"A": "A2", "G": "G2", "F": "F2", "E": "E2"}
FORT_CHORDS = {"A": ("A3", "C4", "E4"), "G": ("G3", "B3", "D4"), "F": ("F3", "A3", "C4"), "E": ("E3", "G3", "B3")}


def fortress():
    beat, bar, secs = 1.0, 4.0, 32.0
    # ------------------------------------------------ base: dark chords, string tremolo, glass
    sr = 16000
    L = D.Loop(secs, sr, 41)
    rng = L.rng
    for i, key in enumerate(FORT_BASS):
        for tn in FORT_CHORDS[key]:
            L.add(i * 2 * bar - 1.2, D.pad(note(tn), 2 * bar + 0.4, sr, rng, 2.0, 2.4, 0.42, 3, 9.0), 0.30)
        for tn in FORT_CHORDS[key][1:]:
            s = D.bowed(note(tn) * 2.0, 2 * bar + 0.3, sr, rng, 0.45, 1.2, 1.2, vib_rate=5.5, voices=3, bright=0.8)
            s = s * (0.72 + 0.28 * np.sin(D.TAU * 7.4 * np.arange(len(s)) / sr + rng.uniform(0, D.TAU)))
            L.add(i * 2 * bar - 0.6, s, 0.20)
    drone(L, note("A1"), 2, 0.14, 0.50, harm=(1.0, 0.7, 0.3, 0.12))
    for at, nm in ((5.0, "E5"), (11.5, "D5"), (19.0, "C5"), (26.0, "B4")):
        L.add(at, D.chime(note(nm), 6.0, sr, rng, 0.5), 0.26)
    L.room(2.6, 0.38, seed=42)
    L.highpass(30)
    L.master(-22.0, -10.0)
    out("mus_fortress_base", L.buf, sr, True, "music", 41, "the lament bass under dark chords")

    # ------------------------------------------------ pulse: a big drum (12 kHz: it has nothing above 4 kHz to say)
    sr = 12000
    P = D.Loop(secs, sr, 43)
    rng = P.rng
    for b in range(8):
        t0 = b * bar
        P.add(t0 + 0.0, D.taiko(55.0, 1.4, sr, rng, 1.0, 0.55), 1.0)
        P.add(t0 + 1.5, D.taiko(55.0, 1.0, sr, rng, 0.50, 0.35), 0.8)
        P.add(t0 + 2.0, D.taiko(55.0, 1.2, sr, rng, 0.80, 0.45), 0.9)
        if b % 2 == 1:
            P.add(t0 + 3.0, D.taiko(55.0, 1.0, sr, rng, 0.46, 0.30), 0.7)
            P.add(t0 + 3.5, D.taiko(55.0, 1.0, sr, rng, 0.58, 0.32), 0.8)
    P.room(2.0, 0.28, seed=44)
    P.highpass(32)
    P.lowpass(3500)
    P.master(-21.0, -10.0)
    out("mus_fortress_pulse", P.buf, sr, True, "music", 43, "heavy low drum")

    # ------------------------------------------------ brass drone on the lament bass
    B = D.Loop(secs, sr, 45)
    rng = B.rng
    for i, key in enumerate(FORT_BASS):
        f = note(FORT_ROOT_HZ[key])
        B.add(i * 2 * bar - 0.8, D.brass(f, 2 * bar + 0.2, sr, rng, 1.6, 2.0, 0.85, 2), 0.9)
        B.add(i * 2 * bar - 0.5, D.brass(f * 1.5, 2 * bar - 0.3, sr, rng, 1.8, 2.0, 0.6, 2), 0.38)
    B.room(2.2, 0.28, seed=46)
    B.highpass(35)
    B.lowpass(3800)
    B.master(-21.0, -11.0)
    out("mus_fortress_brass", B.buf, sr, True, "music", 45, "low brass on the bass line")

    # ------------------------------------------------ war drums, an anvil, a shaker
    sr = 16000
    Q = D.Loop(secs, sr, 47)
    rng = Q.rng
    pattern = [(0.0, 110.0, 0.9), (0.75, 82.4, 0.45), (1.0, 110.0, 0.55), (1.75, 82.4, 0.5), (2.0, 110.0, 0.85), (2.5, 82.4, 0.40), (3.0, 110.0, 0.5), (3.5, 82.4, 0.6)]
    for b in range(8):
        t0 = b * bar
        for at, f, v in pattern:
            Q.add(t0 + at, D.tom(f, 0.9, sr, rng, v * (0.85 + 0.2 * rng.random()), 0.22), 0.9)
        if b % 2 == 1:
            Q.add(t0 + 3.0, D.clank(note("A3") * 1.0, 0.7, sr, rng, 0.5), 0.6)
        for k in range(16):
            Q.add(t0 + k * 0.25 + 0.125, D.shaker(0.05, sr, rng, 0.12 + 0.05 * (k % 4 == 0)), 0.5)
    Q.room(1.8, 0.28, seed=48)
    Q.highpass(40)
    Q.master(-22.0, -10.0)
    out("mus_fortress_perc", Q.buf, sr, True, "music", 47, "war drums and an anvil")


# ------------------------------------------------------------------------------------------------ the end card

def endcard():
    sr, secs = 16000, 32.0
    L = D.Loop(secs, sr, 81)
    rng = L.rng
    bar = 4.0
    for i, c in enumerate(MAJOR_BARS):
        chord_pad(L, rng, c, i * bar - 1.0, bar + 0.8, 0.34, attack=1.4, release=2.2, bright=0.5, lift=0)
        chord_bass(L, rng, c, i * bar - 0.2, bar - 0.2, 0.6, attack=0.8, release=1.4, vel=0.5)
        tones = CHORD[c][0]
        # a gentle broken chord, an eighth-ish note at a time, in the register above the pad
        arp = [(0.0, 0), (1.0, 1), (1.5, 2), (2.5, 1), (3.0, 2), (3.5, 1)]
        for at, idx in arp:
            nm = tones[idx]
            nm = nm[0] + str(int(nm[1:]) + 1)
            L.add(i * bar + at + rng.uniform(-0.01, 0.01), D.piano(note(nm), 3.5, 0.26 + 0.06 * rng.random(), sr, rng, bright=0.8), 0.55)
    put_piano(L, rng, TUNE_MAJOR, bar, 1.0, 1.0, ring=7.0, bright=1.4)
    # strings carry the tune an octave under the last phrase, warm
    for beat_, nm, held in ((16, "A4", 2), (18, "C5", 1), (19, "E5", 1), (20, "G5", 3), (24, "B4", 2), (26, "D5", 2), (28, "C5", 4)):
        L.add(beat_, D.bowed(note(nm), held, sr, rng, 0.5, 0.35, 0.9, voices=3, bright=0.9), 0.30)
    for at, nm, v in ((16.0, "C6", 0.7), (28.0, "C6", 0.8)):
        L.add(at, D.chime(note(nm), 7.0, sr, rng, v), 0.26)
    L.room(3.0, 0.36, seed=82)
    L.highpass(45)
    L.master(-18.0, -2.5)
    return out("mus_endcard", L.buf, sr, True, "music", 81, "the tune in C major")


# ------------------------------------------------------------------------------------------------ the mix check

def mix_report():
    """The stems of a mood summed at full volume, measured from the files on disk."""
    import wave
    moods = {
        "night, base only": ["mus_night_base"],
        "night, + pulse": ["mus_night_base", "mus_night_pulse"],
        "night, all": ["mus_night_base", "mus_night_pulse", "mus_night_perc"],
        "fortress, base + pulse": ["mus_fortress_base", "mus_fortress_pulse"],
        "fortress, all": ["mus_fortress_base", "mus_fortress_pulse", "mus_fortress_brass", "mus_fortress_perc"],
    }
    def load(name):
        with wave.open(os.path.join(D.OUT_DIR, name + ".wav")) as w:
            sr = w.getframerate()
            return sr, np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    print("\nmoods (stems at full volume, resampled to 48 kHz by repetition-free linear interpolation):")
    for label, names in moods.items():
        total = None
        for nm in names:
            sr, x = load(nm)
            n48 = int(len(x) / sr * 48000)
            y = np.interp(np.arange(n48) / 48000.0 * sr, np.arange(len(x)), x)
            total = y if total is None else total + y
        print("  %-20s rms %6.1f dBFS  peak %6.1f dBFS" % (label, D.rms_db(total), D.peak_db(total)))


GROUPS = {"title": title, "indoors": indoors, "outdoors": outdoors, "stingers": lambda: (dusk(), dawn(), rescue(), defeat()), "night": night, "fortress": fortress, "endcard": endcard}

if __name__ == "__main__":
    which = [a for a in sys.argv[1:] if not a.startswith("--")] or list(GROUPS)
    for g in which:
        GROUPS[g]()
    check_in_key()
    print("all %d notes used are natural notes (A minor / C major)" % len(ALL_NOTES))
    if WRITE and set(which) == set(GROUPS):
        mix_report()
