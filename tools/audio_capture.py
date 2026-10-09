#!/usr/bin/env python3
"""Analyses a movie capture of the game (docs/audio-capture.md): what the real mix does, not one sound at a time.

    python3 tools/audio_capture.py CLIP_DIR [--wav movie.wav] [--name NAME] [--json out.json] [--md]

CLIP_DIR is what tools/capture_tap.gd wrote during a `--write-movie` run (`--capture=tap|walk|fight|build --capture-out=CLIP_DIR`):
  Master.f32 (after the limiter) Master_pre.f32 (before it), SFX, Steps, Voices, Ambience, Rain, Distant, Music, UI .f32 (raw 32-bit float stereo, 48 kHz: what each bus carries at the end
  of its own effects, BEFORE its own fader: the Voices stem is 9 dB under what it adds to SFX)
  meta.csv  (one line a frame: game hour, Ruth's tile, the ground under her, the dead awake within 20 tiles, ..., and every bus's fader in dB, which this script applies to the stems so that
  every number below is "as it reaches the Master")
--wav is the movie's own audio (tools/avi_extract.py writes it): the 16-bit file the owner will hear. Its clipping is counted, and it is lined up with the stems.

What it prints (and returns as a dict for --json):
  master      peak dBFS (sample and 16-bit file), samples at full scale, integrated loudness (ITU-R BS.1770-4: K-weighted, 400 ms blocks, gated at -70 LUFS and 10 LU under the
              rest), the loudest momentary and short-term (3 s) loudness, the share of the energy in six bands
  limiter     the Master's hard limiter (ceiling -0.5 dBFS): the pre-limiter peak, the samples that would have been over the ceiling and over full scale, the time it was working
              (1 ms blocks with more than 0.1 dB taken off), the most it took off
  buses       each bus's peak, loudest momentary loudness and integrated loudness over the time it plays
  events      the bursts of sound in each category's stem: footsteps (Steps), voices (Voices), the guns and blows (SFX alone: the SFX stem less Steps and Voices, which are sent
              to it) told apart by loudness (a gun is above -17 LUFS at its loudest 400 ms; the blows, reloads, doors under), thunder (a burst of the Rain bus above its bed)
  masking     the loudness of each gun against what plays under it (the music's, the rain bed's, in the 400 ms before the shot)

Needs numpy (and no other package). The K-weighting is the standard's two biquads applied through the FFT (tools/audio_measure.py).
"""
import argparse
import json
import os
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_measure as am  # noqa: E402

SR = 48000
BUS_FILES = ["Master", "Master_pre", "SFX", "Steps", "Voices", "Ambience", "Rain", "Distant", "Music", "UI"]
BANDS = [("20-100 Hz", 20, 100), ("100-300", 100, 300), ("300-1k", 300, 1000), ("1k-3k", 1000, 3000), ("3k-8k", 3000, 8000), ("8k-24k", 8000, 24000)]
CEILING = 10 ** (-0.5 / 20)
GUN_LUFS = -15.0   # a burst of the SFX bus alone whose loudest 400 ms is over this is a gun (the pump gun is -12.7 to -13.9 at the master; the loudest blow, a kill, -16.8; a far gun is under it too)
DEFAULT_FADER_DB = {"Steps": 2.5, "Voices": 9.0, "Rain": 0.5}    # (the fixed trims, for a capture with no f_<bus> columns in its meta.csv)


def db(x):
    return 20.0 * np.log10(max(float(x), 1e-9))


def load_stem(folder, name):
    p = os.path.join(folder, name + ".f32")
    if not os.path.exists(p):
        return None
    return np.fromfile(p, dtype="<f4").reshape(-1, 2).astype(np.float64)


def load_wav16(path):
    with wave.open(path, "rb") as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 2
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype="<i2").reshape(-1, 2)


def k_stereo(x):
    """K-weighted stereo signal (each channel through the standard's filters)."""
    return np.stack([am.k_weight(x[:, 0], SR), am.k_weight(x[:, 1], SR)], axis=1)


def block_loudness(k, win_s, hop_s):
    """The loudness of each window of a K-weighted stereo signal (LUFS; channel powers added, as the standard does for L and R)."""
    win, hop = int(win_s * SR), int(hop_s * SR)
    sq = (k * k).sum(axis=1)
    c = np.concatenate([[0.0], np.cumsum(sq)])
    starts = np.arange(0, max(len(sq) - win, 0) + 1, hop)
    ms = (c[starts + win] - c[starts]) / win
    return starts, -0.691 + 10.0 * np.log10(np.maximum(ms, 1e-14))


def integrated(blocks):
    """BS.1770-4 gating: absolute -70 LUFS, then 10 LU under the mean of what is left."""
    b = blocks[blocks > -70.0]
    if len(b) == 0:
        return -70.0
    ref = -0.691 + 10 * np.log10(np.mean(10 ** ((b + 0.691) / 10)))
    b = b[b > ref - 10.0]
    if len(b) == 0:
        return float(ref)
    return float(-0.691 + 10 * np.log10(np.mean(10 ** ((b + 0.691) / 10))))


def band_shares(x):
    """The share of the energy in each of the six bands (a Hann-windowed mean of 0.5 s spectra, both channels)."""
    n = SR // 2
    win = np.hanning(n)
    acc = np.zeros(n // 2 + 1)
    for s in range(0, len(x) - n, n):
        for ch in range(2):
            acc += np.abs(np.fft.rfft(x[s:s + n, ch] * win)) ** 2
    f = np.fft.rfftfreq(n, 1.0 / SR)
    tot = max(acc[(f >= 20) & (f < 24000)].sum(), 1e-18)
    return [float(acc[(f >= lo) & (f < hi)].sum() / tot) for _, lo, hi in BANDS]


def align(master, wav):
    """The lag (samples) at which the stem's start is in the movie's audio: wav[lag + i] = master[i]. Taken over 8 s of the loudest stretch."""
    n = min(len(master), len(wav) // 1)
    if n < SR * 2:
        return None, 0.0
    env = np.abs(master[:n, 0])
    c = np.concatenate([[0.0], np.cumsum(env)])
    seg = SR * 6
    best = int(np.argmax(c[seg:n] - c[:n - seg])) if n > seg else 0
    a = master[best:best + seg, 0]
    w = wav[:, 0].astype(np.float64) / 32768.0
    m = len(w) + len(a)
    size = 1 << int(np.ceil(np.log2(m)))
    corr = np.fft.irfft(np.fft.rfft(w, size) * np.conj(np.fft.rfft(a, size)), size)
    lag_at = int(np.argmax(corr[:len(w)]))
    lag = lag_at - best
    err = 0.0
    if 0 <= lag_at and lag_at + seg <= len(w):
        d = w[lag_at:lag_at + seg] - a
        err = db(np.sqrt(np.mean(d * d)) / max(np.sqrt(np.mean(a * a)), 1e-9))
    return lag, err


def bursts(x, thr_db, quiet_db_gap=8.0, min_gap_s=0.12):
    """The bursts of a stereo stem: [start, end) sample indices where the 10 ms peak envelope goes over thr_db, and stays over (less quiet_db_gap) until it is under for min_gap_s."""
    hop = SR // 100
    nb = len(x) // hop
    env = np.abs(x[:nb * hop]).max(axis=1).reshape(nb, hop).max(axis=1)
    envd = 20 * np.log10(np.maximum(env, 1e-9))
    out = []
    i = 0
    gap = int(min_gap_s / 0.01)
    while i < nb:
        if envd[i] > thr_db:
            j = i
            last = i
            while j < nb and j - last <= gap:
                if envd[j] > thr_db - quiet_db_gap:
                    last = j
                j += 1
            out.append((i * hop, (last + 1) * hop))
            i = last + 1
        else:
            i += 1
    return out


def burst_stats(x, k, ev):
    """For each burst: start (s), peak dBFS, the loudest 400 ms from its onset (LUFS, the standard's momentary loudness on the stem's own K-weighting)."""
    out = []
    win = int(0.4 * SR)
    sq = (k * k).sum(axis=1)
    c = np.concatenate([[0.0], np.cumsum(sq)])
    for s, e in ev:
        pk = db(np.abs(x[s:e]).max())
        best = -120.0
        # the loudest 400 ms that starts within the burst (a short sound is alone in its window; a long one is measured where it is loudest)
        for a in range(max(s - int(0.02 * SR), 0), min(e, len(sq) - 1), int(0.05 * SR)):
            b = min(a + win, len(sq))
            ms = (c[b] - c[a]) / win
            best = max(best, -0.691 + 10 * np.log10(max(ms, 1e-14)))
        out.append({"t": s / SR, "len": (e - s) / SR, "peak": pk, "mmax": best})
    return out


def summarize(vals):
    if len(vals) == 0:
        return None
    v = np.sort(np.asarray(vals))
    return {"n": int(len(v)), "min": float(v[0]), "p10": float(v[int(0.1 * (len(v) - 1))]), "median": float(np.median(v)), "p90": float(v[int(0.9 * (len(v) - 1))]), "max": float(v[-1])}


def analyse(folder, wav_path=None, name=None, luma_csv=None):
    st = {n: load_stem(folder, n) for n in BUS_FILES}
    st = {n: x for n, x in st.items() if x is not None}
    n = min(len(x) for x in st.values())
    st = {k: x[:n] for k, x in st.items()}
    res = {"name": name or os.path.basename(folder.rstrip("/")), "seconds": n / SR}
    master = st["Master"]
    meta = load_meta(folder)

    # THE STEMS ARE BEFORE THEIR BUS'S FADER (checked: the SFX stem is exactly 2.818 x the Voices stem, +9.0 dB, when only voices play): what a bus sends on is its stem times its fader, which
    # meta.csv records every frame (f_<bus>, dB: the sliders, the fixed trims, the Rain bus's muffle, the Ambience bus's duck). `sm` is each bus as it reaches the Master.
    def gain(bus):
        col = "f_" + bus
        if meta and col in meta[0]:
            g = np.array([float(r[col]) for r in meta])
            per = np.repeat(g, SR // 30)
            if len(per) < n:
                per = np.concatenate([per, np.full(n - len(per), g[-1])])
            return (10.0 ** (per[:n] / 20.0))[:, None]
        return np.full((n, 1), 10.0 ** (DEFAULT_FADER_DB.get(bus, 0.0) / 20.0))

    sm = {}
    for b in ["SFX", "UI", "Ambience", "Music", "Steps", "Voices", "Rain", "Distant"]:
        if b in st:
            sm[b] = st[b] * gain(b)
    for b in ["Steps", "Voices"]:
        if b in sm:
            sm[b] = sm[b] * gain("SFX")      # (sent to SFX, which has a fader of its own)
    for b in ["Rain", "Distant"]:
        if b in sm:
            sm[b] = sm[b] * gain("Ambience")    # (sent to Ambience, with its duck)
    # --- the 16-bit file the owner hears
    wavd = None
    if wav_path:
        w16 = load_wav16(wav_path)
        lag, err = align(master, w16)
        w16 = w16[max(lag or 0, 0):max(lag or 0, 0) + n]    # (the clip itself: the movie's first seconds are the loading card, which the files for the owner leave out)
        wavd = {"file": os.path.basename(wav_path), "seconds": len(w16) / SR, "lag_samples": lag, "lag_s": None if lag is None else lag / SR,
                "match_db": err, "full_scale": int(((w16 == 32767) | (w16 == -32768)).sum()), "near_full_scale": int((np.abs(w16.astype(np.int32)) >= 32700).sum()),
                "peak_dbfs": db(np.abs(w16.astype(np.int32)).max() / 32768.0)}
        res["wav"] = wavd
    # --- master loudness
    k = k_stereo(master)
    st_m, mom = block_loudness(k, 0.4, 0.1)
    st_s, short = block_loudness(k, 3.0, 1.0)
    res["master"] = {
        "peak_dbfs": db(np.abs(master).max()), "over_0dbfs": int((np.abs(master) >= 1.0).sum()),
        "integrated": integrated(mom), "mmax": float(mom.max()), "short_max": float(short.max()) if len(short) else None,
        "short_series": [round(float(v), 1) for v in short[::5]],
        "rms_dbfs": db(np.sqrt(np.mean(master ** 2))),
        "bands": dict(zip([b[0] for b in BANDS], band_shares(master))),
    }
    # --- the limiter (a hard limiter looks ahead a few milliseconds, so the two are compared in 20 ms blocks of their peaks)
    pre = st["Master_pre"]
    blk = SR // 50
    nb = len(pre) // blk
    pp = np.abs(pre[:nb * blk]).max(axis=1).reshape(nb, blk).max(axis=1)
    po = np.abs(master[:nb * blk]).max(axis=1).reshape(nb, blk).max(axis=1)
    hot = pp > CEILING * 0.98
    po_l = np.maximum(po, np.concatenate([po[1:], po[-1:]]))    # (the output of this block and the next: the limiter's lookahead shifts a transient across a block edge)
    gr = np.zeros(nb)
    gr[hot] = -20 * np.log10(np.maximum(po_l[hot], 1e-9) / pp[hot])
    res["limiter"] = {
        "pre_peak_dbfs": db(pp.max()), "post_peak_dbfs": db(po.max()),
        "pre_over_ceiling": int((np.abs(pre) > CEILING).sum()), "pre_over_full_scale": int((np.abs(pre) >= 1.0).sum()),
        "ms_working": int(hot.sum() * 20), "max_reduction_db": float(max(gr.max(), 0.0)),
        "episodes": int(((hot[1:]) & (~hot[:-1])).sum() + (1 if hot[0] else 0)),
    }
    # --- the buses
    buses = {}
    for b in ["SFX", "Steps", "Voices", "Ambience", "Rain", "Distant", "Music", "UI"]:
        x = sm.get(b)
        if x is None:
            continue
        kb = k_stereo(x)
        _, mb = block_loudness(kb, 0.4, 0.1)
        act = mb[mb > -70.0]
        buses[b] = {"peak_dbfs": db(np.abs(x).max()), "mmax": float(mb.max()), "integrated": integrated(mb), "median_active": float(np.median(act)) if len(act) else None,
                    "active_share": float((mb > -50.0).mean())}
    res["buses"] = buses
    # --- events
    own = sm["SFX"] - sm["Steps"] - sm["Voices"]    # (the guns, the blows, the reloads, the doors, the bells, the hammer: SFX itself)
    res["sfx_residual_db"] = db(np.sqrt(np.mean((own) ** 2)))
    ev = {}
    k_own = k_stereo(own)
    gb = burst_stats(own, k_own, bursts(own, -30.0))
    guns = [g for g in gb if g["mmax"] > GUN_LUFS]
    blows = [g for g in gb if g["mmax"] <= GUN_LUFS and g["peak"] > -24.0]
    ev["guns"] = {"events": guns, "mmax": summarize([g["mmax"] for g in guns]), "peak": summarize([g["peak"] for g in guns])}
    ev["blows_and_other"] = {"mmax": summarize([g["mmax"] for g in blows]), "peak": summarize([g["peak"] for g in blows])}
    sb = burst_stats(sm["Steps"], k_stereo(sm["Steps"]), bursts(sm["Steps"], -40.0))
    ev["steps"] = {"mmax": summarize([g["mmax"] for g in sb]), "peak": summarize([g["peak"] for g in sb])}
    if meta:
        # Ruth's footsteps by ground, as tools/mix_probe.gd measures them: the loudest 400 ms of the Steps bus while she walks (or runs) on that ground the whole time
        _, ms_steps = block_loudness(k_stereo(sm["Steps"]), 0.4, 0.1)
        by = {}
        for i, loud_v in enumerate(ms_steps):
            f0, f1 = int(i * 0.1 * 30) + 1, int((i * 0.1 + 0.4) * 30)
            if f1 >= len(meta):
                break
            seg = meta[f0:f1 + 1]
            grounds = set(r["ground"] for r in seg)
            runs = set(r.get("run") for r in seg)
            if len(grounds) != 1 or len(runs) != 1:
                continue
            moved = ((float(seg[-1]["x"]) - float(seg[0]["x"])) ** 2 + (float(seg[-1]["y"]) - float(seg[0]["y"])) ** 2) ** 0.5
            if moved < 0.6:
                continue
            key = seg[0]["ground"] + (" run" if seg[0].get("run") == "1" else " walk")
            by.setdefault(key, []).append(float(loud_v))
        ev["steps_by_ground"] = {k: summarize(v) for k, v in sorted(by.items())}
    vb = burst_stats(sm["Voices"], k_stereo(sm["Voices"]), bursts(sm["Voices"], -42.0))
    ev["voices"] = {"mmax": summarize([g["mmax"] for g in vb]), "peak": summarize([g["peak"] for g in vb]), "events": vb}
    rain = sm["Rain"]
    kr = k_stereo(rain)
    _, mr = block_loudness(kr, 0.4, 0.1)
    bed = float(np.median(mr[mr > -70.0])) if (mr > -70.0).any() else None
    rb = []
    if bed is not None:
        # thunder: a rise of the Rain bus's 30-250 Hz band 6 dB over its median for 0.3 s or more (the rain bed has next to nothing down there; the thunder is mostly that)
        mono = rain.mean(axis=1)
        spec = np.fft.rfft(mono)
        fr = np.fft.rfftfreq(len(mono), 1.0 / SR)
        spec[(fr < 30) | (fr > 250)] = 0
        low = np.fft.irfft(spec, len(mono))
        hop = SR // 10
        nbl = len(low) // hop
        lowd = 20 * np.log10(np.maximum(np.sqrt((low[:nbl * hop].reshape(nbl, hop) ** 2).mean(axis=1)), 1e-9))
        base = float(np.median(lowd))
        over = lowd > base + 6.0
        i = 0
        while i < nbl:
            if over[i]:
                j = i
                last = i
                while j < nbl and j - last <= 5:
                    if over[j]:
                        last = j
                    j += 1
                if (last - i + 1) >= 3:
                    a, b = max(i - 2, 0), min(last + 8, len(mr))
                    rb.append({"t": i / 10.0, "len": (last - i + 1) / 10.0, "rise_db": float(lowd[i:last + 1].max() - base), "mmax": float(mr[a:b].max())})
                i = last + 1
            else:
                i += 1
    ev["rain_bed_mmax_median"] = bed
    ev["rain_bursts"] = rb
    # the rain bed under a roof and in the open (Ruth on a floor or on the ground), and at the master (the Ambience bus's fader and duck are on it)
    if bed is not None and meta:
        ind, outd = [], []
        for idx, loud_v in enumerate(mr):
            f0, f1 = int(idx * 0.1 * 30) + 1, int((idx * 0.1 + 0.4) * 30)
            if f1 >= len(meta):
                break
            seg = meta[f0:f1 + 1]
            gs = set(r["ground"] for r in seg)
            if loud_v < -70 or any(b["t"] - 0.5 <= idx * 0.1 <= b["t"] + b["len"] + 4.0 for b in rb):
                continue    # (silence, or a thunder's window: the bed alone is wanted)
            if gs <= {"tile", "wood", "carpet"}:
                ind.append(float(loud_v))
            elif gs <= {"grass", "pave", "dirt", "gravel"}:
                outd.append(float(loud_v))
        ev["rain_at_master"] = {"indoors": summarize(ind), "outdoors": summarize(outd)}
    res["events"] = ev
    # --- the calibration groans (tools/capture_tap.gd `--capture-calib=groan`): a groan played from a known distance, measured on the Voices bus as it reaches the Master
    cal = os.path.join(folder, "calib.csv")
    if os.path.exists(cal):
        kv = k_stereo(sm["Voices"])
        win = int(0.4 * SR)
        csq = np.concatenate([[0.0], np.cumsum((kv * kv).sum(axis=1))])
        out_c = []
        with open(cal) as f:
            f.readline()
            for line in f:
                fr, tiles = line.strip().split(",")
                a = int(max(int(fr) - 1, 0) / 30.0 * SR)
                best = -120.0
                for s in range(a, min(a + int(1.8 * SR), len(csq) - win - 1), SR // 20):
                    best = max(best, -0.691 + 10 * np.log10(max((csq[s + win] - csq[s]) / win, 1e-14)))
                out_c.append({"tiles": float(tiles), "mmax": best, "peak": db(np.abs(sm["Voices"][a:a + int(1.8 * SR)]).max())})
        res["calib"] = out_c
    # --- masking: each gun against the music and the rain under it (the 400 ms before the shot, on their own stems) and the ambience duck
    kmu = k_stereo(sm["Music"])
    _, mm = block_loudness(kmu, 0.4, 0.1)
    mask = []
    for g in guns:
        i = max(int((g["t"] - 0.5) * 10), 0)
        j = max(int(g["t"] * 10) - 3, i + 1)
        mus = float(np.max(mm[i:j])) if j <= len(mm) else None
        rn = float(np.max(mr[i:j])) if j <= len(mr) else None
        mask.append({"t": g["t"], "gun": g["mmax"], "music": mus, "rain": rn})
    res["masking"] = mask
    # lightning: a spike of the picture's brightness (the movie's frames: tools/avi_extract.py --luma=), and the thunder that follows it
    if luma_csv and os.path.exists(luma_csv) and wavd and wavd.get("lag_s") is not None:
        lum = []
        with open(luma_csv) as f:
            f.readline()
            for line in f:
                lum.append(float(line.split(",")[1]))
        lum = np.array(lum)
        flashes = []
        for i in range(8, len(lum) - 8):
            ref = np.median(np.concatenate([lum[i - 8:i - 2], lum[i + 3:i + 8]]))
            if lum[i] > ref * 1.2 + 1.0 and lum[i] == lum[i - 2:i + 3].max() and (not flashes or i / 30.0 - flashes[-1]["video_t"] > 0.6):
                flashes.append({"video_t": i / 30.0, "t": i / 30.0 - wavd["lag_s"], "luma_gain": float(lum[i] / max(ref, 1.0))})
        rbs = ev["rain_bursts"]
        for fl in flashes:
            nxt = [b for b in rbs if b["t"] >= fl["t"] - 0.2]
            fl["thunder_delay"] = float(nxt[0]["t"] - fl["t"]) if nxt else None
            fl["thunder_mmax"] = float(nxt[0]["mmax"]) if nxt else None
        res["flashes"] = [f for f in flashes if f["t"] >= 0]
    return res


def load_meta(folder):
    p = os.path.join(folder, "meta.csv")
    if not os.path.exists(p):
        return None
    rows = []
    with open(p) as f:
        head = f.readline().strip().split(",")
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == len(head):
                rows.append(dict(zip(head, parts)))
    return rows


def meta_at(rows, t):
    """The meta line of the frame in which second t (from the start of the stems) falls (the stems start on the tap's frame 1, 30 frames a second)."""
    i = int(t * 30.0)
    return rows[i] if 0 <= i < len(rows) else None


def fmt(v, d=1):
    return "n/a" if v is None else ("%.*f" % (d, v))


def report(res):
    out = []
    m = res["master"]
    out.append("== %s (%.1f s of stems)" % (res["name"], res["seconds"]))
    if "wav" in res:
        w = res["wav"]
        out.append("movie audio %s (the clip: %.1f s from %s s into the movie), stem vs file %.1f dB, samples at full scale %d, within 0.2 dB of it %d, peak %.2f dBFS" % (
            w["file"], w["seconds"], fmt(w["lag_s"], 3), w["match_db"], w["full_scale"], w["near_full_scale"], w["peak_dbfs"]))
    out.append("master: peak %.2f dBFS, over 0 dBFS %d, integrated %.1f LUFS, M-max %.1f, short-term max %.1f, rms %.1f dBFS" % (m["peak_dbfs"], m["over_0dbfs"], m["integrated"], m["mmax"], m["short_max"] or 0, m["rms_dbfs"]))
    out.append("bands (share of energy): " + ", ".join("%s %.0f%%" % (k, 100 * v) for k, v in m["bands"].items()))
    L = res["limiter"]
    out.append("limiter: pre peak %.2f dBFS, over the -0.5 ceiling %d samples, over 0 dBFS %d samples; working %d ms in %d episodes, most %.2f dB" % (
        L["pre_peak_dbfs"], L["pre_over_ceiling"], L["pre_over_full_scale"], L["ms_working"], L["episodes"], L["max_reduction_db"]))
    out.append("buses (peak dBFS / M-max / integrated LUFS / share of time playing):")
    for b, v in res["buses"].items():
        out.append("  %-9s %6.1f  %6.1f  %6.1f  %4.0f%%" % (b, v["peak_dbfs"], v["mmax"], v["integrated"], 100 * v["active_share"]))
    e = res["events"]
    for key in ["guns", "blows_and_other", "steps", "voices"]:
        s = e[key]["mmax"]
        p = e[key]["peak"]
        if s:
            out.append("%s: %d bursts, M-max LUFS min %.1f / median %.1f / max %.1f, peak dBFS median %.1f max %.1f" % (key, s["n"], s["min"], s["median"], s["max"], p["median"], p["max"]))
        else:
            out.append("%s: none" % key)
    for k2, v2 in e.get("steps_by_ground", {}).items():
        if v2:
            out.append("  Ruth on %-10s %3d windows of 400 ms: loudest %.1f LUFS (median %.1f)" % (k2, v2["n"], v2["max"], v2["median"]))
    out.append("rain bus bed M (median) %s LUFS; thunder (low-band rises): %s" % (fmt(e["rain_bed_mmax_median"]), ", ".join("%.1fs +%.0fdB M %.1f" % (b["t"], b["rise_db"], b["mmax"]) for b in e["rain_bursts"][:14])))
    ra = e.get("rain_at_master")
    if ra:
        for k2 in ["outdoors", "indoors"]:
            if ra[k2]:
                out.append("  rain bed at the master, %s (no thunder in the window): median %.1f, loudest 400 ms %.1f LUFS (n %d)" % (k2, ra[k2]["median"], ra[k2]["max"], ra[k2]["n"]))
    for c in res.get("calib", []):
        out.append("  calibration groan from %.0f tiles: %.1f LUFS (peak %.1f dBFS) at the master" % (c["tiles"], c["mmax"], c["peak"]))
    for fl in res.get("flashes", [])[:14]:
        out.append("  flash at %.1fs (picture %.2fx): thunder %s s after it, M-max %s" % (fl["t"], fl["luma_gain"], fmt(fl.get("thunder_delay"), 2), fmt(fl.get("thunder_mmax"))))
    for g in res["masking"][:6]:
        out.append("  gun at %.1fs: %.1f LUFS, music before it %s, rain before it %s" % (g["t"], g["gun"], fmt(g["music"]), fmt(g["rain"])))
    return "\n".join(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--wav")
    ap.add_argument("--name")
    ap.add_argument("--json")
    ap.add_argument("--luma")
    a = ap.parse_args()
    r = analyse(a.folder, a.wav, a.name, a.luma)
    print(report(r))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(r, f, indent=1)
