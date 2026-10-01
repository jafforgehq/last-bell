#!/usr/bin/env python3
"""Draws the two icons round 4 adds to the HUD, the way the older ones in assets/ui/icons are:
white on transparent, 64x64, a 6 unit stroke with round caps on a 64 unit grid, inside a 3 unit
margin (the HUD tints them with `modulate`, so the file carries only alpha). Drawn at 8x and
averaged down, which gives clean edges.

    star.png    a five-pointed star: a skill went up (the alert `skill-<id>`)
    mood.png    a face with a down-turned mouth: someone is Shaken or Breaking (the mark on the
                crew card) and the alert of a breakdown (`breakdown-<id>`)

    python3 tools/make_people_icons.py         # writes assets/ui/icons/star.png and mood.png
then import them once: Godot --headless --path . --import   (see tools/make_menu_icon.py)
"""
import math
import os

from PIL import Image, ImageDraw

SIZE = 64
SS = 8
STROKE = 6
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ui", "icons")


def dot(draw, x, y, r):
    draw.ellipse([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS], fill=255)


def line(draw, x0, y0, x1, y1, w):
    """A stroked segment with round caps, on the supersampled grid."""
    draw.line([(x0 * SS, y0 * SS), (x1 * SS, y1 * SS)], fill=255, width=int(round(w * SS)))
    dot(draw, x0, y0, w / 2.0)
    dot(draw, x1, y1, w / 2.0)


def save(mask, name):
    alpha = mask.resize((SIZE, SIZE), Image.LANCZOS)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    img.putalpha(alpha)
    path = os.path.join(OUT, name)
    img.save(path)
    print("wrote", path)


def star():
    mask = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    d = ImageDraw.Draw(mask)
    cx, cy = 32.0, 34.0
    outer, inner = 25.0, 11.5
    pts = []
    for i in range(10):
        a = -math.pi / 2.0 + i * math.pi / 5.0
        r = outer if i % 2 == 0 else inner
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    for i in range(10):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % 10]
        line(d, x0, y0, x1, y1, STROKE - 0.5)
    save(mask, "star.png")


def mood():
    mask = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    d = ImageDraw.Draw(mask)
    # the face: a ring, 25 units in radius to the middle of the stroke
    r = 25.0
    d.ellipse([(32 - r - STROKE / 2) * SS, (32 - r - STROKE / 2) * SS, (32 + r + STROKE / 2) * SS, (32 + r + STROKE / 2) * SS], fill=255)
    d.ellipse([(32 - r + STROKE / 2) * SS, (32 - r + STROKE / 2) * SS, (32 + r - STROKE / 2) * SS, (32 + r - STROKE / 2) * SS], fill=0)
    # two eyes
    dot(d, 23.5, 26.5, 3.6)
    dot(d, 40.5, 26.5, 3.6)
    # the mouth: the top of a circle (a frown), drawn with a round brush so its ends are round
    mr, mx, my = 14.0, 32.0, 56.0
    a0, a1 = math.radians(228.0), math.radians(312.0)
    steps = 90
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        dot(d, mx + mr * math.cos(a), my + mr * math.sin(a), (STROKE - 0.5) / 2.0)
    save(mask, "mood.png")


if __name__ == "__main__":
    star()
    mood()
