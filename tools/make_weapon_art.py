#!/usr/bin/env python3
"""Draws the prison game's submachine gun for the pawn (assets/weapons/smg.png, 336 x 70 like the other guns: the hands' pivot is at x = 96, the barrel's centre line at y = 31, the muzzle at
x = 206 = 0.57 tiles in front of the pivot at 192 px a tile). Same look as rifle.png: a dark outline, flat greys, a lighter top edge. PIL only.

    python3 tools/make_weapon_art.py        # writes assets/weapons/smg.png, then: Godot --headless --path . --import
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "weapons", "smg.png")
SS = 4
W, H = 336, 70
OUTLINE = (21, 18, 14, 255)
BODY = (48, 50, 52, 255)
BODY_L = (76, 80, 84, 255)
MAG = (59, 62, 65, 255)


def poly(d, pts, fill, ow=3):
    s = [(x * SS, y * SS) for x, y in pts]
    d.polygon(s, fill=fill)
    d.line(s + [s[0]], fill=OUTLINE, width=ow * SS, joint="curve")


def rect(d, x0, y0, x1, y1, fill, ow=3):
    poly(d, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], fill, ow)


def main():
    im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # folding wire stock and its butt plate
    d.line([(70 * SS, 27 * SS), (44 * SS, 26 * SS), (44 * SS, 38 * SS), (72 * SS, 36 * SS)], fill=OUTLINE, width=6 * SS, joint="curve")
    d.line([(70 * SS, 27 * SS), (44 * SS, 26 * SS), (44 * SS, 38 * SS), (72 * SS, 36 * SS)], fill=BODY_L, width=2 * SS, joint="curve")
    rect(d, 36, 22, 44, 42, BODY)
    # magazine (long, curved forward), the pistol grip, the front grip
    poly(d, [(124, 38), (142, 38), (146, 54), (150, 67), (132, 67), (130, 54)], MAG)
    poly(d, [(92, 38), (112, 38), (114, 50), (108, 63), (96, 63), (97, 50)], BODY)
    poly(d, [(166, 36), (180, 36), (181, 47), (169, 47)], BODY)
    # the receiver, the shroud and the barrel tip
    rect(d, 70, 21, 164, 40, BODY)
    rect(d, 70, 21, 164, 26, BODY_L, ow=0)
    rect(d, 160, 24, 198, 38, BODY_L)
    for x in range(166, 196, 6):
        d.line([(x * SS, 27 * SS), (x * SS, 35 * SS)], fill=OUTLINE, width=2 * SS)
    rect(d, 196, 28, 207, 34, OUTLINE, ow=2)
    # sights
    rect(d, 148, 15, 156, 22, BODY)
    rect(d, 76, 14, 86, 22, BODY)
    im = im.resize((W, H), Image.LANCZOS)
    im.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
