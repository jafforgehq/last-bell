#!/usr/bin/env python3
"""Draws two HUD icons of round 13 (vehicles and fuel) the way the older icons in assets/ui/icons are: outlines,
white on transparent, 64x64 on a 64 unit grid inside a 3 unit margin (the HUD tints them with `modulate`, so the
files carry only alpha). Drawn at 8x and averaged down, which gives clean edges.

    fuel.png   a petrol pump (the stores panel's Fuel line)
    car.png    a car seen from the side (the alerts of a vehicle found or lost)

    python3 tools/make_fuel_icon.py             # writes assets/ui/icons/fuel.png and car.png
then import them once: Godot --headless --path . --import
"""
import os
from PIL import Image, ImageDraw

SIZE = 64
SS = 8
STROKE = 4.6
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ui", "icons")


def s(v):
    """A grid unit on the supersampled canvas."""
    return v * SS


def pts(points):
    return [(s(x), s(y)) for x, y in points]


def canvas():
    layer = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    return layer, ImageDraw.Draw(layer)


def line(d, points, width=STROKE):
    """A round-capped polyline."""
    p = pts(points)
    d.line(p, fill=255, width=round(s(width)), joint="curve")
    r = s(width) / 2.0
    for x, y in (p[0], p[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)


def ring(d, box, radius, width=STROKE):
    d.rounded_rectangle([s(box[0]), s(box[1]), s(box[2]), s(box[3])], radius=s(radius), outline=255, width=round(s(width)))


def save(layer, name):
    alpha = layer.resize((SIZE, SIZE), Image.BOX)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    img.putalpha(alpha)
    path = os.path.join(OUT, name)
    img.save(path)
    print("wrote", path)


def fuel():
    layer, d = canvas()
    # the pump: a tall body with its window, standing on a base
    ring(d, (12.5, 7.5, 38.5, 53.5), 4.0)
    ring(d, (18.5, 14.0, 32.5, 27.5), 2.5, 4.0)
    line(d, [(8.5, 58.0), (42.5, 58.0)])
    # the hose: from the side of the body, over, and down to the nozzle
    line(d, [(38.5, 24.0), (47.0, 24.0), (52.0, 30.0), (52.0, 44.0)])
    d.ellipse([s(52.0 - 3.2), s(46.0 - 3.2), s(52.0 + 3.2), s(46.0 + 3.2)], fill=255)
    save(layer, "fuel.png")


def car():
    layer, d = canvas()
    # the body, seen from the side: the roof over the cabin, the long low hull
    body = [(6.5, 41.0), (6.5, 33.5), (14.0, 31.0), (21.0, 19.5), (43.0, 19.5), (50.0, 31.0), (57.5, 33.5), (57.5, 41.0)]
    line(d, body + [body[0]])
    line(d, [(21.0, 31.0), (43.0, 31.0)], 3.6)
    # the wheels: rings that interrupt the hull's line
    for cx in (18.5, 45.5):
        d.ellipse([s(cx - 7.4), s(41.0 - 7.4 + 3.0), s(cx + 7.4), s(41.0 + 7.4 + 3.0)], fill=0)
        d.ellipse([s(cx - 6.2), s(41.0 - 6.2 + 3.0), s(cx + 6.2), s(41.0 + 6.2 + 3.0)], outline=255, width=round(s(STROKE)))
    save(layer, "car.png")


if __name__ == "__main__":
    fuel()
    car()
