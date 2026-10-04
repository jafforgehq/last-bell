#!/usr/bin/env python3
"""Sets the loudness of the game's sounds (assets/audio/*.wav) so that they sit in one mix.

The sounds were baked from the web prototype's synthesiser at the levels its mixer expected: gunshots at -17 to -26 dBFS,
the thuds, stabs and hammering near -32, the claws on a wall near -50 and the wind and crickets at -35 and -43, next to
menu sounds at -6. Heard together the game's own sounds were a whisper under its menu clicks. This scales each file so
that its loudest sample is at the level below (dBFS); a file not named here is left as it is. Running it again changes
nothing (it scales by the peak, so a file already at its level stays there).

    python3 tools/level_sounds.py          # rewrite the files that are off their level
    python3 tools/level_sounds.py --check  # only list them (exit 1 if any is off by more than half a decibel)

Python 3 with NumPy. The PCM wavs only (16-bit, any rate, any channels).
"""
import struct
import sys

import numpy as np

DIR = "assets/audio/"

# peak level in dBFS, by file stem (the number is dropped: shot_rifle_0, shot_rifle_1 and shot_rifle_2 share "shot_rifle")
LEVELS = {
    "shot_pistol": -9.0,
    "shot_rifle": -7.0,
    "shot_shotgun": -5.0,
    "bite": -10.0,
    "stab": -12.0,
    "thud": -12.0,
    "scrape_metal": -20.0,
    "scrape_stone": -20.0,
    "scrape_wood": -20.0,
    # the beds: quiet on purpose (they sit under everything), but heard
    # (wind_loop, moan_loop, the bells, the groans, the hammer and the other generated sounds are written at their level by
    # tools/make_ambience.py, make_bells.py and make_base_sounds.py, and are left out of this table: it would undo them)
    "crickets_loop": -26.0,
    # the car trip (round 15, tools/make_car_sounds.py writes them at this level already)
    "car_door_open": -8.0,
    "car_door_close": -8.0,
    "car_engine_start": -8.0,
    "car_gate_motor": -8.0,
}


def stem_of(name):
    base = name[:-4]
    parts = base.rsplit("_", 1)
    return parts[0] if len(parts) == 2 and parts[1].isdigit() else base


def read_wav(path):
    """(fmt bytes, samples as int16 array, the chunks before and after the data) of a 16-bit PCM wav."""
    raw = open(path, "rb").read()
    assert raw[:4] == b"RIFF" and raw[8:12] == b"WAVE", path
    pos = 12
    chunks = []
    while pos < len(raw):
        cid = raw[pos:pos + 4]
        size = struct.unpack("<I", raw[pos + 4:pos + 8])[0]
        body = raw[pos + 8:pos + 8 + size]
        chunks.append((cid, body))
        pos += 8 + size + (size & 1)
    fmt = dict(chunks)[b"fmt "]
    tag, channels, rate, _, _, bits = struct.unpack("<HHIIHH", fmt[:16])
    assert tag in (1, 0xFFFE) and bits == 16, "%s is not 16-bit PCM" % path
    return chunks


def peak_db(samples):
    return 20 * np.log10(max(float(np.max(np.abs(samples.astype(np.float64)))) / 32768.0, 1e-9))


def main():
    import glob
    import os
    check_only = "--check" in sys.argv
    off = 0
    for path in sorted(glob.glob(DIR + "*.wav")):
        name = os.path.basename(path)
        stem = stem_of(name)
        if stem not in LEVELS:
            continue
        chunks = read_wav(path)
        data = dict(chunks)[b"data"]
        s = np.frombuffer(data, dtype="<i2")
        now = peak_db(s)
        want = LEVELS[stem]
        if abs(now - want) <= 0.5:
            continue
        off += 1
        print("%-22s %6.1f dBFS -> %6.1f%s" % (name, now, want, "" if not check_only else "  (not written)"))
        if check_only:
            continue
        k = 10 ** ((want - now) / 20.0)
        scaled = np.clip(np.round(s.astype(np.float64) * k), -32768, 32767).astype("<i2").tobytes()
        out = b"RIFF\0\0\0\0WAVE"
        for cid, body in chunks:
            if cid == b"data":
                body = scaled
            out += cid + struct.pack("<I", len(body)) + body + (b"\0" if len(body) & 1 else b"")
        out = out[:4] + struct.pack("<I", len(out) - 8) + out[8:]
        open(path, "wb").write(out)
    print("%d file(s) %s" % (off, "off their level" if check_only else "rewritten"))
    return 1 if (check_only and off) else 0


if __name__ == "__main__":
    sys.exit(main())
