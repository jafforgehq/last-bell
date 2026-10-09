#!/usr/bin/env python3
"""Takes a Godot movie-writer AVI (`--write-movie clip.avi`: MJPEG video, 16-bit PCM audio) apart, with the standard library only (docs/audio-capture.md).

    python3 tools/avi_extract.py clip.avi OUTDIR [--frames] [--range=FIRST,LAST] [--only=3,40,500]

OUTDIR/audio.wav is always written (the movie's whole soundtrack, 48 kHz stereo 16-bit). The frames are written as OUTDIR/f000000.jpg... only when asked: all of them
(`--frames`), those from FIRST to LAST (`--range`) or a few (`--only`). It prints the header facts (size, fps, frame count, audio length).
"""
import os
import struct
import sys
import wave


def parse(path):
    data = open(path, "rb").read()
    assert data[:4] == b"RIFF" and data[8:12] == b"AVI ", "not an AVI"
    info = {"video": [], "audio": bytearray(), "streams": []}

    def walk(start, end):
        p = start
        while p + 8 <= end:
            cid = data[p:p + 4]
            size = struct.unpack("<I", data[p + 4:p + 8])[0]
            body = p + 8
            if cid in (b"LIST", b"RIFF"):
                if data[body:body + 4] in (b"hdrl", b"strl", b"movi"):
                    walk(body + 4, min(body + size, end))
            elif cid == b"avih":
                us, _, _, _, total, _, _, _, w, h = struct.unpack("<IIIIIIIIII", data[body:body + 40])
                info["avih"] = {"us_per_frame": us, "total": total, "w": w, "h": h}
            elif cid == b"strh":
                scale, rate = struct.unpack("<II", data[body + 20:body + 28])
                info["streams"].append({"type": data[body:body + 4], "scale": scale, "rate": rate})
            elif cid == b"strf":
                st = info["streams"][-1]
                if st["type"] == b"auds":
                    fmt, ch, sr, _, _, bits = struct.unpack("<HHIIHH", data[body:body + 16])
                    st.update({"fmt": fmt, "ch": ch, "sr": sr, "bits": bits})
            elif cid[2:4] in (b"dc", b"db"):
                info["video"].append((body, size))
            elif cid[2:4] == b"wb":
                info["audio"] += data[body:body + size]
            p = body + size + (size & 1)

    walk(12, len(data))
    return data, info


def main():
    src, out = sys.argv[1], sys.argv[2]
    want = "--frames" in sys.argv
    rng = None
    only = None
    for a in sys.argv:
        if a.startswith("--range="):
            lo, hi = a[8:].split(",")
            rng = (int(lo), int(hi))
            want = True
        if a.startswith("--only="):
            only = set(int(x) for x in a[7:].split(","))
            want = True
    os.makedirs(out, exist_ok=True)
    data, info = parse(src)
    aud = [s for s in info["streams"] if s["type"] == b"auds"][0]
    vid = [s for s in info["streams"] if s["type"] == b"vids"][0]
    print("video: %dx%d @ %.3f fps, %d frames" % (info["avih"]["w"], info["avih"]["h"], vid["rate"] / vid["scale"], len(info["video"])))
    print("audio: %d ch, %d Hz, %d bit, %.2f s" % (aud["ch"], aud["sr"], aud["bits"], len(info["audio"]) / (aud["ch"] * aud["bits"] // 8) / aud["sr"]))
    with wave.open(os.path.join(out, "audio.wav"), "wb") as w:
        w.setnchannels(aud["ch"])
        w.setsampwidth(aud["bits"] // 8)
        w.setframerate(aud["sr"])
        w.writeframes(bytes(info["audio"]))
    for a in sys.argv:
        if a.startswith("--luma="):
            # the mean brightness of every frame (Pillow: the JPEG is decoded at 1/8 size): a lightning flash is a spike in it
            import io
            from PIL import Image
            with open(a[7:], "w") as f:
                f.write("frame,luma\n")
                for i, (off, size) in enumerate(info["video"]):
                    im = Image.open(io.BytesIO(data[off:off + size]))
                    im.draft("L", (im.width // 8, im.height // 8))
                    px = im.convert("L").resize((60, 34)).getdata()
                    f.write("%d,%.2f\n" % (i, sum(px) / len(px)))
    if want:
        n = 0
        for i, (off, size) in enumerate(info["video"]):
            if only is not None and i not in only:
                continue
            if rng is not None and not (rng[0] <= i <= rng[1]):
                continue
            with open(os.path.join(out, "f%06d.jpg" % i), "wb") as f:
                f.write(data[off:off + size])
            n += 1
        print("wrote", n, "jpgs")


main()
