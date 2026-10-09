#!/usr/bin/env python3
"""Contact sheets of a patrol film (tools/patrol_film.gd): python3 tools/patrol_sheet.py FRAMES_DIR OUT_PREFIX [--cols=3] [--rows=3] [--crop=720x640] [--scale=0.667] [--from=0] [--label=TEXT] [--gain=1.5]

Reads FRAMES_DIR/f000.png ... and FRAMES_DIR/film.log (the times), crops the middle of every frame (the camera is held on the base's lot), labels it with the frame, the game
time and the hour and writes OUT_PREFIX_1.png, OUT_PREFIX_2.png ... with cols x rows frames each.
"""
import glob
import os
import re
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFont


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = {}
    for a in sys.argv[1:]:
        if a.startswith("--") and "=" in a:
            k, v = a[2:].split("=", 1)
            opts[k] = v
    frames_dir, prefix = args[0], args[1]
    cols = int(opts.get("cols", 3))
    rows = int(opts.get("rows", 3))
    cw, ch = [int(v) for v in opts.get("crop", "720x640").split("x")]
    scale = float(opts.get("scale", 0.667))
    start = int(opts.get("from", 0))
    label = opts.get("label", "")
    gain = float(opts.get("gain", 1.5))
    files = sorted(glob.glob(os.path.join(frames_dir, "f[0-9][0-9][0-9].png")))
    times = {}
    log = os.path.join(frames_dir, "film.log")
    if os.path.exists(log):
        for line in open(log):
            m = re.match(r"f(\d+) t=\s*([\d.]+) h\s*([\d.]+) (\w+) dead\s+(\d+) claw\s+(\d+)", line)
            if m:
                times[int(m.group(1))] = "t=%ds h%s dead %s claw %s" % (round(float(m.group(2))), m.group(3), m.group(5), m.group(6))
    try:
        font = ImageFont.load_default(size=18)
    except TypeError:
        font = ImageFont.load_default()
    per = cols * rows
    cell_w, cell_h = int(cw * scale), int(ch * scale)
    sheet_i = 0
    for s in range(start, len(files), per):
        chunk = files[s:s + per]
        sheet = Image.new("RGB", (cell_w * cols, cell_h * rows), (20, 20, 20))
        for i, f in enumerate(chunk):
            img = Image.open(f).convert("RGB")
            w, h = img.size
            x0 = (w - cw) // 2
            y0 = (h - ch) // 2
            tile = img.crop((x0, y0, x0 + cw, y0 + ch)).resize((cell_w, cell_h), Image.LANCZOS)
            tile = ImageEnhance.Brightness(tile).enhance(gain)
            d = ImageDraw.Draw(tile)
            n = int(os.path.basename(f)[1:4])
            text = "%s f%d %s" % (label, n, times.get(n, ""))
            d.rectangle((0, 0, cell_w, 24), fill=(0, 0, 0))
            d.text((4, 2), text.strip(), fill=(255, 255, 160), font=font)
            sheet.paste(tile, ((i % cols) * cell_w, (i // cols) * cell_h))
        sheet_i += 1
        out = "%s_%d.png" % (prefix, sheet_i)
        sheet.save(out)
        print(out)


if __name__ == "__main__":
    main()
