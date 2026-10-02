#!/usr/bin/env python3
"""Draws the wall and door textures of the raid sites (round 14): four terrain
atlases in the format of the others in assets/terrain (512 x 512, a 4 x 4 atlas
of 128 px tiles, every one seamless so that a run of walls reads as one wall).

    python3 tools/make_site_art.py     # writes assets/terrain/wall_brick.png,
                                       # wall_plaster.png, wall_metal.png, door_wood.png

The world draws a wall tile as the ground of that tile (no height), so a wall is a
band one tile thick of one of these; they are darker and more saturated than the
floors (LINO, TERRAZZO, WOOD, KITCHEN) and the ground (ASPHALT, SIDEWALK, GRASS,
DIRT, CONCRETE, YARD) so that a room reads at a glance.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "terrain")
N = 512
TILE = 128


def noise(seed, sigma):
    """Periodic smooth noise in about -1..1 (a gaussian low-pass in Fourier space, so it wraps)."""
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((N, N)))
    fy = np.fft.fftfreq(N)[:, None]
    fx = np.fft.fftfreq(N)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    n = np.real(np.fft.ifft2(f * g))
    return n / (np.abs(n).max() + 1e-9)


def grain(seed, amount):
    rng = np.random.default_rng(seed)
    return rng.standard_normal((N, N)) * amount


def to_img(rgb):
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).convert("RGBA")


def brick():
    """Red-brown bricks in a running bond, pale mortar, a little bevel on each brick."""
    bw, bh = 32, 16          # a brick with its mortar line: 16 courses of 16 px in 512
    rng = np.random.default_rng(11)
    tone = np.zeros((N, N))
    mortar = np.zeros((N, N), dtype=bool)
    bevel = np.zeros((N, N))
    for r in range(N // bh):
        off = (bw // 2) if r % 2 else 0
        for b in range(N // bw):
            x0 = b * bw + off
            y0 = r * bh
            v = rng.normal(0.0, 1.0)
            for yy in range(bh):
                for xx in range(bw):
                    px = (x0 + xx) % N
                    py = y0 + yy
                    tone[py, px] = v
                    if yy >= bh - 2 or xx >= bw - 2:
                        mortar[py, px] = True      # the last two rows and columns are the mortar
                    elif yy < 2:
                        bevel[py, px] = 7.0
                    elif yy >= bh - 4 or xx >= bw - 4:
                        bevel[py, px] = -8.0
    blot = noise(3, 14.0) * 14.0 + noise(5, 3.0) * 5.0
    col = np.zeros((N, N, 3))
    base = (138.0, 62.0, 46.0)
    for c, k in enumerate((1.0, 0.8, 0.8)):
        col[:, :, c] = base[c] + tone * 13.0 * k + blot * k + bevel + grain(7 + c, 3.2)
    mor = (186.0, 172.0, 150.0)
    for c in range(3):
        mchan = mor[c] + noise(9, 4.0) * 10.0 + grain(20 + c, 2.5)
        col[:, :, c] = np.where(mortar, mchan, col[:, :, c])
    return to_img(col)


def plaster():
    """Grey poured concrete / plaster: panels one tile square with a fine seam, bolts, stains."""
    base = (112.0, 115.0, 119.0)
    big = noise(31, 22.0) * 11.0
    mid = noise(33, 6.0) * 6.0
    col = np.zeros((N, N, 3))
    for c in range(3):
        col[:, :, c] = base[c] + big + mid + grain(40 + c, 3.0)
    # panel seams on every tile edge: a dark line with a light edge beside it
    for k in range(0, N, TILE):
        col[k:k + 2, :, :] -= 30.0
        col[:, k:k + 2, :] -= 30.0
        col[k + 2:k + 4, :, :] += 9.0
        col[:, k + 2:k + 4, :] += 9.0
    # a bolt in each corner of every panel
    for k in range(0, N, TILE):
        for j in range(0, N, TILE):
            for (dx, dy) in ((11, 11), (TILE - 13, 11), (11, TILE - 13), (TILE - 13, TILE - 13)):
                y, x = j + dy, k + dx
                col[y - 2:y + 3, x - 2:x + 3, :] -= 22.0
                col[y - 2:y, x - 2:x, :] += 14.0
    stain = np.clip(noise(37, 9.0) * 1.8, -1, 1) * 7.0
    for c in range(3):
        col[:, :, c] += stain
    return to_img(col)


def metal():
    """Corrugated sheet metal in a blue-grey: vertical ribs, an overlap seam every 128 px, rust."""
    xs = np.arange(N)
    ribs = np.sin(2 * np.pi * xs / 16.0)[None, :] * 15.0 * np.ones((N, 1))
    base = (96.0, 114.0, 134.0)
    blot = noise(51, 18.0) * 9.0 + noise(53, 4.0) * 4.0
    col = np.zeros((N, N, 3))
    for c in range(3):
        col[:, :, c] = base[c] + ribs + blot + grain(60 + c, 2.2)
    for k in range(0, N, TILE):
        col[k:k + 3, :, :] -= 34.0
        col[k + 3:k + 5, :, :] += 14.0
        for x in range(8, N, 32):
            y = k + 10
            col[y - 2:y + 2, x - 2:x + 2, :] += 26.0
            col[y + 1:y + 3, x:x + 3, :] -= 22.0
    rust = np.clip(noise(55, 7.0) * 2.4 - 0.55, 0.0, 1.0)
    seam = np.zeros(N)
    for k in range(0, N, TILE):
        seam += np.exp(-((np.arange(N) - k - 4) % N) ** 2 / 90.0)
    rust = rust * (0.35 + seam[:, None] * 0.65)
    warm = (150.0, 88.0, 54.0)
    for c in range(3):
        col[:, :, c] = col[:, :, c] * (1 - rust * 0.6) + warm[c] * rust * 0.6
    return to_img(col)


def door():
    """A wooden threshold: dark planks across the doorway in a worn frame, every tile on its own."""
    rng = np.random.default_rng(71)
    col = np.zeros((N, N, 3))
    base = (126.0, 84.0, 52.0)
    blot = noise(73, 12.0) * 8.0
    plank_h = 21
    tone = np.zeros((N, N))
    edge = np.zeros((N, N))
    for t_y in range(0, N, TILE):
        for r in range(6):
            y0 = t_y + 6 + r * plank_h
            y1 = min(y0 + plank_h, t_y + TILE - 6)
            tone[y0:y1, :] = rng.normal(0.0, 1.0)
            edge[y0:y0 + 1, :] = -30.0
            edge[y1 - 1:y1, :] = -22.0
            edge[y0 + 1:y0 + 3, :] += 10.0
    gl = noise(75, 1.4) * 6.0
    for c in range(3):
        col[:, :, c] = base[c] + tone * 9.0 + blot + edge + gl + grain(80 + c, 3.0)
    frame = (60.0, 40.0, 28.0)
    for k in range(0, N, TILE):
        for c in range(3):
            col[k:k + 6, :, c] = frame[c]
            col[k + TILE - 6:k + TILE, :, c] = frame[c]
            col[:, k:k + 6, c] = frame[c]
            col[:, k + TILE - 6:k + TILE, c] = frame[c]
        col[k + 6:k + 8, :, :] += 22.0
        col[:, k + 6:k + 8, :] += 22.0
    # a brass strip across the middle of each threshold, where the door shuts
    for k in range(0, N, TILE):
        mid = k + TILE // 2
        for c, v in enumerate((176.0, 146.0, 78.0)):
            col[mid - 3:mid + 3, :, c] = v
        for c, v in enumerate((120.0, 94.0, 48.0)):
            col[mid + 3:mid + 5, :, c] = v
        # the frame stays on top at the tile's left and right edge
        for c in range(3):
            col[mid - 3:mid + 5, k:k + 6, c] = frame[c]
            col[mid - 3:mid + 5, k + TILE - 6:k + TILE, c] = frame[c]
    return to_img(col)


def main():
    for name, fn in (("wall_brick", brick), ("wall_plaster", plaster), ("wall_metal", metal), ("door_wood", door)):
        img = fn()
        path = os.path.join(OUT, name + ".png")
        img.save(path)
        print("wrote", path, img.size)


if __name__ == "__main__":
    main()
