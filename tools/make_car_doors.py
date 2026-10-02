#!/usr/bin/env python3
"""Cuts the doors out of the game's own car pictures (round 15, task DOORS).

    python3 tools/make_car_doors.py                  # writes the pictures and the doors of assets/data/vehicles.json
    CAR_DOORS_DEBUG=some/dir python3 tools/make_car_doors.py   # also contact sheets of every kind, doors shut,
                                                     # half open and wide open, left and right, in that folder
    python3 tools/make_car_doors.py --check          # writes nothing: lists what on disk is not what this would write
                                                     # (exit 1 if anything is)

The pictures (assets/objects/174_car_s0.png, 116_pickup.png, 207_pickup.png, 175_bus_s0.png) are seen from above:
the roof, the glass and the hood, with no door in sight. What a viewer sees of a door from above is a thin strip of
the body between the A-pillar and the C-pillar: the outer skin and the window frame. Each door is cut as that strip
(and, where the picture has it, the wing mirror that sits on the front of the door), and for every kind this writes

    <art>_open.png               the body with every door strip replaced by the dark cabin: the sill and the door
                                 frame's edge stay, the floor and a seat's edge show
    <art>_door_<id>.png          one door, cut from the picture: the same canvas as the picture and transparent
                                 outside the strip, so the game draws it at the body's position and turns it
                                 about `hinge` (the front edge of the door at the outer skin)
    <art>_door_<id>_shadow.png   the soft shadow of that door on the ground (the same canvas, the same hinge)

and the `nose` and `doors` of every kind in assets/data/vehicles.json (the rest of that file is left as it is). At
angle 0 the panels on the `_open` body give back the picture: exactly, except for what makes a slab a door once it
moves (a thin dark shut line along the three cut edges of a panel, a handle on a car's door, the crease of the bus's
folding door), which is why the test allows a small tolerance. The picture is drawn while a car is still and `_open`
plus the panels while a door moves.

How the cut is made. Each door is a polygon in the door's own frame: `u` runs from the hinge back along the car,
`v` from the outer skin in toward the middle. A door covers the picture's body pixels inside it (the soft edge of the
body's outline goes with it, laid over what is outside: the picture's own shadow or nothing); the dark outline itself
stays in the `_open` body as the sill. A wing mirror that stands out from the front of a front door is cut with it.
What lies under the door in the `_open` body is painted from the numbers of the picture: the glass's own blue,
darkened, for the floor, the outline's colour and the body's own darkest red for the sill, a seat's edge (the bus
gets a stairwell of three treads). The sedan has four doors but three seats, so its rear left door (L2) has no seat
and is never used; the van's two doors serve its four seats (the rear seats climb in behind the front ones).

The pictures face three ways: the sedan and the bus nose south, the pickup north, the van east (and a little tilted:
its picture is drawn 2.85 degrees off). A door's `open_deg` is positive when it swings clockwise as drawn: the doors on
the left of the car (looking along its nose) swing clockwise, the ones on the right the other way.

Python 3 with NumPy and Pillow. Everything is arithmetic, so running it again writes the same files.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OBJ = os.path.join(ROOT, "assets", "objects")
VEHICLES = os.path.join(ROOT, "assets", "data", "vehicles.json")

# --------------------------------------------------------------------------------------------- the doors --
# Pixels of the picture. `hinge` is the front edge of the door at the outer skin (the picture's own outline starts
# there); `profile` is how deep (v) the door goes in at each distance u behind the hinge: the door's inner edge.

PHI = math.atan2(0.0497, 1.0)  # the van's tilt: its picture is drawn this far round, clockwise (2.85 degrees)

KINDS = {
    "sedan": {
        "art": "174_car_s0",
        "nose": "S",
        "tilt": 0.0,
        "glass": (42, 200),       # where to sample the blue of the glass
        "shadow": (8, 6),         # which way the picture's own shadow falls, in pixels
        "doors": [
            # the front doors begin at the wing mirror, behind the windscreen's foot; a pillar stands between them
            {"id": "L1", "side": "L", "seats": [0], "hinge": (242.0, 368.0), "open_deg": 70,
             "profile": [(0, 22), (52, 22), (61, 31), (126, 31)], "seat": (0.30, 0.94), "mirror": (251, 357)},
            {"id": "R1", "side": "R", "seats": [1], "hinge": (19.0, 368.0), "open_deg": -70,
             "profile": [(0, 22), (52, 22), (61, 31), (126, 31)], "seat": (0.30, 0.94), "mirror": (11, 357)},
            {"id": "L2", "side": "L", "seats": [], "hinge": (242.0, 236.0), "open_deg": 66,
             "profile": [(0, 31), (86, 31), (96, 24), (108, 24)], "seat": (0.10, 0.88)},
            {"id": "R2", "side": "R", "seats": [2], "hinge": (19.0, 236.0), "open_deg": -66,
             "profile": [(0, 31), (86, 31), (96, 24), (108, 24)], "seat": (0.10, 0.88)},
        ],
    },
    "pickup": {
        "art": "116_pickup",
        "nose": "N",
        "tilt": 0.0,
        "glass": (120, 190),
        "shadow": (8, 6),
        "doors": [
            {"id": "L1", "side": "L", "seats": [0], "hinge": (42.0, 157.0), "open_deg": 72,
             "profile": [(0, 28), (52, 28), (60, 34), (141, 34)], "seat": (0.30, 0.94), "mirror": (32, 172)},
            {"id": "R1", "side": "R", "seats": [1], "hinge": (287.0, 157.0), "open_deg": -72,
             "profile": [(0, 28), (52, 28), (60, 34), (141, 34)], "seat": (0.30, 0.94), "mirror": (297, 172)},
        ],
    },
    "van": {
        "art": "207_pickup",
        "nose": "E",
        "tilt": PHI,
        "glass": (415, 160),
        "shadow": (6, 8),
        "doors": [
            {"id": "L1", "side": "L", "seats": [0, 2], "hinge": (444.0, 40.0), "open_deg": 72,
             "profile": [(0, 28), (52, 28), (60, 34), (141, 34)], "seat": (0.30, 0.94), "mirror": (428, 28)},
            {"id": "R1", "side": "R", "seats": [1, 3], "hinge": (432.0, 283.0), "open_deg": -72,
             "profile": [(0, 28), (52, 28), (60, 34), (141, 34)], "seat": (0.30, 0.94), "mirror": (415, 293)},
        ],
    },
    "bus": {
        "art": "175_bus_s0",
        "nose": "S",
        "tilt": 0.0,
        "glass": (150, 1095),
        "shadow": (8, 6),
        "doors": [
            {"id": "F", "side": "R", "seats": [0, 1, 2, 3, 4, 5], "hinge": (41.0, 1078.0), "open_deg": -80,
             "profile": [(0, 32), (122, 32)], "seat": (0.0, 0.0), "style": "bus"},
        ],
    },
}

NOSE_VECTOR = {"N": (0.0, -1.0), "S": (0.0, 1.0), "E": (1.0, 0.0)}


# ------------------------------------------------------------------------------------------------ helpers --

def read(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)


def nose_vector(spec):
    n = np.array(NOSE_VECTOR[spec["nose"]], np.float64)
    c, s = math.cos(spec["tilt"]), math.sin(spec["tilt"])
    return np.array([n[0] * c - n[1] * s, n[0] * s + n[1] * c])  # the picture's tilt turns it clockwise (y runs down)


def door_frame(spec, door, shape):
    """The door's own coordinates of every pixel centre: u back along the car from the hinge, v in from the outer skin."""
    h, w = shape
    n = nose_vector(spec)
    left = np.array([n[1], -n[0]])
    out = left if door["side"] == "L" else -left
    X, Y = np.meshgrid(np.arange(w) + 0.5, np.arange(h) + 0.5)
    dx, dy = X - door["hinge"][0], Y - door["hinge"][1]
    u = -(dx * n[0] + dy * n[1])
    v = -(dx * out[0] + dy * out[1])
    return u, v


def door_polygon(door, outer=0.0):
    """The door's outline in its own frame (`outer` below zero reaches out past the skin: the outline's soft rim)."""
    prof = door["profile"]
    return [(0.0, outer)] + [(float(u), float(t)) for u, t in prof] + [(float(prof[-1][0]), outer)]


def inside(poly, u, v):
    """Even-odd test of every (u, v) against a polygon."""
    res = np.zeros(u.shape, bool)
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if y1 == y2:
            continue
        cond = (y1 > v) != (y2 > v)
        xi = x1 + (v - y1) * (x2 - x1) / (y2 - y1)
        res ^= cond & (u < xi)
    return res


def depth_at(door, u):
    us = [p[0] for p in door["profile"]]
    ts = [p[1] for p in door["profile"]]
    return np.interp(u, us, ts)


def dilate(mask, r):
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r + r:
                continue
            ys0, ys1 = max(dy, 0), h + min(dy, 0)
            xs0, xs1 = max(dx, 0), w + min(dx, 0)
            out[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx] |= mask[ys0:ys1, xs0:xs1]
    return out


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def rounded_box(u, v, u0, u1, v0, v1, r):
    """Signed distance (negative inside) to a rounded rectangle in the door's frame."""
    cu, cv = (u0 + u1) / 2.0, (v0 + v1) / 2.0
    hu, hv = (u1 - u0) / 2.0 - r, (v1 - v0) / 2.0 - r
    du = np.abs(u - cu) - hu
    dv = np.abs(v - cv) - hv
    outside = np.hypot(np.maximum(du, 0.0), np.maximum(dv, 0.0))
    inner = np.minimum(np.maximum(du, dv), 0.0)
    return outside + inner - r


# -------------------------------------------------------------------------------------- the cabin under a door --

def sample(O, xy, r=3):
    x, y = xy
    patch = O[y - r:y + r + 1, x - r:x + r + 1, :3].reshape(-1, 3)
    return np.median(patch, axis=0)


def cabin(O, spec, door, u, v, mask):
    """RGB (0 to 255) of what is under the door: the floor, the seat's edge, the sill. Only the pixels in `mask`
    matter."""
    glass = sample(O, spec["glass"])
    floor = glass * 0.30                                    # the blue of the glass, deep in shadow
    seat_c = glass * 0.55 + np.array([22.0, 16.0, 14.0])    # a worn seat: the blue grey gone brownish
    L = door["profile"][-1][0]
    T = depth_at(door, u)
    rgb = np.empty(u.shape + (3,), np.float32)
    rgb[...] = floor
    # the roof's shadow: darker toward the middle of the car
    shade = 1.0 - 0.45 * smoothstep(0.35, 1.0, v / np.maximum(T, 1.0))
    rgb *= shade[..., None]
    if door.get("style") == "bus":
        # a stairwell seen from above: three rubber treads going up toward the middle of the bus, each with a pale
        # nosing, and a grab rail's post at the front corner
        pos = np.clip((v - 4.0) / np.maximum(T - 4.0, 1.0), 0.0, 0.9999) * 3.0
        tread = np.floor(pos)
        frac = pos - tread
        grey = np.array([58.0, 57.0, 60.0]) * (0.80 + 0.22 * tread)[..., None]
        grey = np.where((frac < 0.16)[..., None], np.array([150.0, 128.0, 70.0]) * (0.55 + 0.1 * tread)[..., None], grey)
        grey = np.where((frac > 0.86)[..., None], grey * 0.55, grey)
        rgb = np.where((v > 4.0)[..., None], grey, rgb)
        post = rounded_box(u, v, 2.5, 8.5, T - 11.0, T - 4.5, 2.5)
        rgb = np.where((post < 0)[..., None], np.array([170.0, 134.0, 50.0]) * 0.6, rgb)
    else:
        f0, f1 = door["seat"]
        su0, su1 = f0 * L, f1 * L
        sv0 = 9.0
        d = rounded_box(u, v, su0, su1, sv0, T - 1.5, 6.0)
        body = seat_c
        # the seat is lit from its outer edge and sinks toward the middle
        tt = np.clip((v - sv0) / np.maximum(T - sv0, 1.0), 0.0, 1.0)
        seat = body[None, None, :] * (1.25 - 0.55 * tt)[..., None]
        rim = np.clip(1.0 - np.abs(d + 1.2) / 1.2, 0.0, 1.0)[..., None] * np.array([36.0, 34.0, 36.0])
        seat = seat + rim
        rgb = np.where((d < 0)[..., None], seat, rgb)
        # a soft contact shadow round the seat
        halo = np.clip(1.0 - d / 5.0, 0.0, 1.0) * (d >= 0)
        rgb = rgb * (1.0 - 0.35 * halo)[..., None]
    return rgb


def finish_cabin(O, spec, door, u, v, rgb, orig):
    """Adds the sill and the frame's ends to the cabin: `orig` is the picture's own RGB under the door."""
    L = door["profile"][-1][0]
    out = rgb.copy()
    # outer 3.5 px: the picture's own outline, so the side of the car stays whole
    keep = v < 3.5
    out = np.where(keep[..., None], orig, out)
    # 3.5 to 7 px: the sill, the body's colour near its edge, dark
    t = np.clip((v - 3.5) / 4.0, 0.0, 1.0)[..., None]
    in_sill = ((v >= 3.5) & (v < 7.5))[..., None]
    out = np.where(in_sill, orig * 0.42 * (1.0 - t) + out * t, out)
    # the door frame's ends (the pillars): a darker line where the door's front and rear edges meet the body
    near_end = np.minimum(u, L - u)
    dark = 1.0 - 0.5 * np.clip(1.0 - near_end / 2.5, 0.0, 1.0)
    out = out * dark[..., None]
    return np.clip(out, 0, 255)


def door_detail(rgb, u, v, door):
    """The strip as the door's own piece: the picture's pixels with a thin dark rim along the three cut edges (the
    outer skin has the body's own outline already) and, on a car's door, a handle on the skin near the rear edge. Only
    what a door shows once it moves: it is what makes a slab a door, and it is within the tolerance of the picture."""
    L = door["profile"][-1][0]
    T = depth_at(door, u)
    edge = np.minimum(np.minimum(u, L - u), T - v)
    rim = np.clip(1.0 - edge / 1.6, 0.0, 1.0) * 0.5
    out = rgb * (1.0 - rim[..., None]) + np.array([16.0, 12.0, 11.0]) * rim[..., None]
    if door.get("style") == "bus":
        # a folding door: the two leaves meet in a crease halfway along
        crease = np.clip(1.0 - np.abs(u - L / 2.0) / 1.3, 0.0, 1.0) * 0.5
        out = out * (1.0 - crease[..., None]) + np.array([16.0, 12.0, 11.0]) * crease[..., None]
    else:
        hu0, hu1 = L - 30.0, L - 14.0
        bar = rounded_box(u, v, hu0, hu1, 7.0, 10.5, 1.5)
        glint = rounded_box(u, v, hu0 + 1.0, hu1 - 1.0, 7.0, 8.4, 0.6)
        out = np.where((bar < 0)[..., None], out * 0.45, out)
        out = np.where((glint < 0)[..., None], np.minimum(out + 70.0, 255.0), out)
    return out


# -------------------------------------------------------------------------------------------- cutting one kind --

def mirror_zone(O, spec, door, u, v):
    """The pixels of the wing mirror that stands outside the body next to a door: opaque pixels outside the body's
    edge within reach of the mirror's centre, grown by two so that the soft rim goes with it."""
    if "mirror" not in door:
        return np.zeros(u.shape, bool)
    cx, cy = door["mirror"]
    h, w = u.shape
    win = np.zeros((h, w), bool)
    win[max(cy - 24, 0):cy + 25, max(cx - 24, 0):cx + 25] = True
    core = win & (v < 0.0) & (O[..., 3] > 128)
    # the antenna's thin line must not be mistaken for the mirror: keep only the blob that holds the mirror's centre
    seed_ok = core[cy, cx] or core[cy - 1:cy + 2, cx - 1:cx + 2].any()
    assert seed_ok, "no mirror at %s for door %s" % (door["mirror"], door["id"])
    # flood from the seed
    blob = np.zeros_like(core)
    stack = [(cy, cx)]
    while stack:
        y, x = stack.pop()
        if y < 0 or x < 0 or y >= h or x >= w or blob[y, x] or not core[y, x]:
            continue
        blob[y, x] = True
        stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    return dilate(blob, 2) & (v < 0.5)


def shadow_estimate(O, spec, zone, u, v):
    """What the picture holds under a mirror, if there were none: the same distance from the body's edge, a little
    farther back along the car (premultiplied RGBA, 0 to 1)."""
    h, w = zone.shape
    n = nose_vector(spec)
    ys, xs = np.where(zone)
    span = np.ptp(u[zone]) + 8.0
    rx = np.clip(np.round(xs + 0.5 + span * (-n[0]) - 0.5).astype(int), 0, w - 1)
    ry = np.clip(np.round(ys + 0.5 + span * (-n[1]) - 0.5).astype(int), 0, h - 1)
    est = np.zeros((h, w, 4), np.float32)
    ref = O[ry, rx] / 255.0
    est[ys, xs, :3] = ref[:, :3] * ref[:, 3:4]
    est[ys, xs, 3] = ref[:, 3]
    return est


def split(O, zone, est, threshold=0.06):
    """For the pixels of `zone` where something lies over `est` (what the picture holds without it, premultiplied RGBA
    0 to 1): the piece that, laid over `est`, gives the picture back. Returns (keep mask, piece RGBA, under RGBA), the
    last two 0 to 255 and only meant for the pixels in `keep`."""
    o = O / 255.0
    o_pre = o[..., :3] * o[..., 3:4]
    s_a = est[..., 3]
    m = np.clip((o[..., 3] - s_a) / np.maximum(1.0 - s_a, 1e-6), 0.0, 1.0)
    keep = zone & (m > threshold)
    p_rgb = np.clip((o_pre - (1.0 - m[..., None]) * est[..., :3]) / np.maximum(m[..., None], 1e-6), 0.0, 1.0)
    piece = np.dstack([p_rgb * 255.0, m * 255.0])
    under_rgb = np.where(s_a[..., None] > 1e-6, est[..., :3] / np.maximum(s_a[..., None], 1e-6), 0.0)
    under = np.dstack([under_rgb * 255.0, s_a * 255.0])
    return keep, piece, under


def outside_estimate(O, spec, door, ring, reach=3.0):
    """What lies under the body's soft outline: what is just outside it (the picture's own shadow, or nothing)."""
    h, w = ring.shape
    n = nose_vector(spec)
    out = np.array([n[1], -n[0]]) * (1.0 if door["side"] == "L" else -1.0)
    ys, xs = np.where(ring)
    rx = np.clip(np.round(xs + out[0] * reach).astype(int), 0, w - 1)
    ry = np.clip(np.round(ys + out[1] * reach).astype(int), 0, h - 1)
    est = np.zeros((h, w, 4), np.float32)
    ref = O[ry, rx] / 255.0
    est[ys, xs, :3] = ref[:, :3] * ref[:, 3:4]
    est[ys, xs, 3] = ref[:, 3]
    return est


def build(kind, spec):
    """Everything one kind writes: {path: PIL image}, the door records, and the picture itself."""
    O = read(os.path.join(OBJ, spec["art"] + ".png"))
    h, w, _ = O.shape
    alpha = O[..., 3]
    opaque = alpha >= 254.5
    open_rgba = O.copy()
    taken = np.zeros((h, w), bool)
    pieces = {}
    records = []
    for door in spec["doors"]:
        u, v = door_frame(spec, door, (h, w))
        panel = np.zeros((h, w, 4), np.float32)
        # the wing mirror goes with the door (on the sides of the cars that have one)
        zone = mirror_zone(O, spec, door, u, v) & ~taken
        if zone.any():
            keep, piece, under = split(O, zone, shadow_estimate(O, spec, zone, u, v))
            taken |= zone
            panel[keep] = piece[keep]
            open_rgba[keep] = under[keep]
        # the strip: the opaque pixels of the body inside the door's outline ...
        solid = inside(door_polygon(door), u, v) & opaque & ~taken
        # ... and the body's soft outline along its outer skin, which is laid over what is outside the body
        ring = inside(door_polygon(door, -2.5), u, v) & (alpha > 0) & ~opaque & ~taken
        keep, piece, under = split(O, ring, outside_estimate(O, spec, door, ring))
        taken |= solid | keep
        panel[solid] = O[solid]
        panel[keep] = piece[keep]
        panel[..., :3] = np.where((solid | keep)[..., None], door_detail(panel[..., :3], u, v, door), panel[..., :3])
        # what the open body holds under the strip
        rgb = finish_cabin(O, spec, door, u, v, cabin(O, spec, door, u, v, solid), O[..., :3])
        open_rgba[solid, :3] = rgb[solid]
        open_rgba[solid, 3] = 255.0
        open_rgba[keep] = under[keep]
        ys, xs = np.where(panel[..., 3] > 0)
        rect = [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]
        # the hinge: on the front edge of the door, just inside the outline of the body (where a real pin would sit)
        n = nose_vector(spec)
        out_dir = np.array([n[1], -n[0]]) * (1.0 if door["side"] == "L" else -1.0)
        hp = np.array(door["hinge"]) - n * 1.0 - out_dir * 2.5
        hinge = [round(float(hp[0]), 1), round(float(hp[1]), 1)]
        pieces["%s_door_%s.png" % (spec["art"], door["id"])] = to_image(panel)
        pieces["%s_door_%s_shadow.png" % (spec["art"], door["id"])] = shadow_of(panel, spec["shadow"])
        records.append({"id": door["id"], "side": door["side"], "seats": door["seats"], "panel": rect,
                        "hinge": hinge, "open_deg": door["open_deg"]})
    pieces["%s_open.png" % spec["art"]] = to_image(open_rgba)
    return pieces, records, O


def to_image(arr):
    return Image.fromarray(np.clip(np.round(arr), 0, 255).astype(np.uint8))


def shadow_of(panel, offset, blur=5.0, strength=0.5):
    """The panel's silhouette, blurred and moved a little the way the picture's own shadow falls, as black with alpha."""
    a = Image.fromarray(np.round(panel[..., 3]).astype(np.uint8))
    big = Image.new("L", a.size, 0)
    big.paste(a, (int(offset[0]), int(offset[1])))
    big = big.filter(ImageFilter.GaussianBlur(blur))
    al = np.asarray(big).astype(np.float32) * strength
    out = np.zeros(panel.shape, np.float32)
    out[..., 3] = al
    return to_image(out)


# ----------------------------------------------------------------------------------------- contact sheets --

GROUND = (138, 136, 130)


def rotated(img, hinge, deg_cw, pad):
    """The picture, turned clockwise by deg_cw about the hinge, on a canvas with `pad` extra pixels all round."""
    big = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    big.alpha_composite(img, (pad, pad))
    return big.rotate(-deg_cw, resample=Image.BICUBIC, center=(hinge[0] + pad, hinge[1] + pad))


def render(kind, spec, pieces, original, angles, pad=230):
    """One picture of the car on a concrete ground with each door at `angles[id]` degrees (0 to 1 of its open_deg)."""
    art = spec["art"]
    w, h = original.size
    ground = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), GROUND + (255,))
    moving = any(t > 0.0 for t in angles.values())
    for door in spec["doors"]:
        t = angles.get(door["id"], 0.0)
        if t > 0.0:
            sh = pieces["%s_door_%s_shadow.png" % (art, door["id"])]
            ground.alpha_composite(rotated(sh, door["hinge"], door["open_deg"] * t, pad))
    body = pieces["%s_open.png" % art] if moving else original
    big = Image.new("RGBA", ground.size, (0, 0, 0, 0))
    big.alpha_composite(body, (pad, pad))
    ground.alpha_composite(big)
    for door in spec["doors"]:
        t = angles.get(door["id"], 0.0)
        panel = pieces["%s_door_%s.png" % (art, door["id"])]
        if moving:
            ground.alpha_composite(rotated(panel, door["hinge"], door["open_deg"] * t, pad))
    return ground


def contact_sheet(kind, spec, pieces, original, cell=520):
    """Two rows, the left side then the right: the doors shut, 35 degrees open and wide open, each cropped to what
    moves (the doors of that side and the room they swing into), on one scale."""
    pad = 230
    rows = []
    for side in ("L", "R"):
        ids = [d["id"] for d in spec["doors"] if d["side"] == side]
        if not ids:
            continue
        cols = [{}, {i: 35.0 / abs(next(d["open_deg"] for d in spec["doors"] if d["id"] == i)) for i in ids}, {i: 1.0 for i in ids}]
        ims = [render(kind, spec, pieces, original, angles, pad) for angles in cols]
        # the doors' own height (or width) and the room they take: the box round everything that is not ground
        ground = np.array(GROUND + (255,), np.int16)
        used = np.zeros(ims[0].size[::-1], bool)
        for im in ims:
            used |= (np.abs(np.asarray(im).astype(np.int16) - ground).max(axis=2) > 6)
        ys, xs = np.where(used)
        reach = [rect for d in spec["doors"] if d["side"] == side for rect in [pieces_rect(pieces, spec, d)]]
        if spec["nose"] == "E":
            box = (min(r[0] for r in reach) - 50, int(ys.min()) - 15, max(r[0] + r[2] for r in reach) + 70, int(ys.max()) + 15)
        else:
            box = (int(xs.min()) - 15, min(r[1] for r in reach) + pad - 50, int(xs.max()) + 15, max(r[1] + r[3] for r in reach) + pad + 50)
        if spec["nose"] == "E":
            box = (box[0] + pad, box[1], box[2] + pad, box[3])
        rows.append([im.crop(box) for im in ims])
    sc = cell / float(max(max(c.size) for row in rows for c in row))
    rw = max(row[0].size[0] for row in rows)
    sheets = []
    for row in rows:
        cw, ch = row[0].size
        strip = Image.new("RGBA", (cw * 3, ch), GROUND + (255,))
        for c, im in enumerate(row):
            strip.paste(im, (c * cw, 0))
        sheets.append(strip)
    total = Image.new("RGBA", (max(s_.width for s_ in sheets), sum(s_.height for s_ in sheets)), GROUND + (255,))
    y = 0
    for s_ in sheets:
        total.paste(s_, (0, y))
        y += s_.height
    return total.resize((int(total.width * sc), int(total.height * sc)), Image.LANCZOS)


def pieces_rect(pieces, spec, door):
    """The box of a door's cut: x, y, width, height."""
    im = pieces["%s_door_%s.png" % (spec["art"], door["id"])]
    bb = im.getchannel("A").getbbox()
    return bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]


# ---------------------------------------------------------------------------------------------- the files --

def kind_block(base, nose, doors, last):
    """The lines of one kind: its own line as it was (`base`, without its closing brace), then its nose and doors."""
    lines = [base + ",", '      "nose": %s,' % json.dumps(nose), '      "doors": [']
    for i, d in enumerate(doors):
        lines.append("        %s%s" % (json.dumps(d, separators=(", ", ": ")), "," if i < len(doors) - 1 else ""))
    lines.append("      ]}" + ("" if last else ","))
    return lines


def write_vehicles(records_by_kind):
    """assets/data/vehicles.json with the nose and the doors of every kind. The rest of the file stays as it is, to the
    character (other tasks edit the kinds' own lines): a kind's line loses its closing brace and the nose and doors
    follow on the lines below, which a second run replaces."""
    with open(VEHICLES) as f:
        text = f.read()
    lines = text.split("\n")
    out = []
    i = 0
    kinds = list(KINDS)
    while i < len(lines):
        line = lines[i]
        hit = next((k for k in kinds if line.lstrip().startswith('"%s"' % k + ":")), None)
        if hit is None:
            out.append(line)
            i += 1
            continue
        # where this kind's block ends: its own line if it closes there, else the line `]}` of the doors
        j = i
        if not (line.rstrip().endswith("}") or line.rstrip().endswith("},")):
            while not lines[j].strip().startswith("]}"):
                j += 1
            last = not lines[j].rstrip().endswith(",")
        else:
            last = not line.rstrip().endswith(",")
        base = line.rstrip()
        if base.endswith("},"):
            base = base[:-2]
        elif base.endswith("}"):
            base = base[:-1]
        elif base.endswith(","):
            base = base[:-1]
        out += kind_block(base.rstrip(), KINDS[hit]["nose"], records_by_kind[hit], last)
        i = j + 1
    result = "\n".join(out)
    before, after = json.loads(text), json.loads(result)
    for k, v in before["kinds"].items():
        assert all(after["kinds"][k][f] == x for f, x in v.items() if f not in ("nose", "doors")), "changed a field of %s" % k
    return result


def png_bytes(img):
    import io
    b = io.BytesIO()
    img.save(b, "PNG", optimize=True)
    return b.getvalue()


def composite_error(spec, pieces, original):
    """Max and mean difference (0 to 255, premultiplied) between the picture and `_open` plus every panel at angle 0."""
    art = spec["art"]
    comp = pieces["%s_open.png" % art].copy()
    for door in spec["doors"]:
        comp.alpha_composite(pieces["%s_door_%s.png" % (art, door["id"])])
    a = np.asarray(comp).astype(np.float32)
    b = np.asarray(Image.fromarray(original.astype(np.uint8))).astype(np.float32)
    pa = np.dstack([a[..., :3] * a[..., 3:4] / 255.0, a[..., 3]])
    pb = np.dstack([b[..., :3] * b[..., 3:4] / 255.0, b[..., 3]])
    d = np.abs(pa - pb).max(axis=2)
    return float(d.max()), float(d.mean()), int((d > 10).sum())


def main():
    check_only = "--check" in sys.argv
    debug = os.environ.get("CAR_DOORS_DEBUG")
    records_by_kind = {}
    outputs = {}
    for kind, spec in KINDS.items():
        pieces, records, original = build(kind, spec)
        records_by_kind[kind] = records
        mx, mean, off = composite_error(spec, pieces, original)
        print("%-7s %d doors  composite: max %.1f mean %.4f, %d pixels off by more than 10" % (kind, len(records), mx, mean, off))
        assert mean < 1.0 and off < 0.01 * original.shape[0] * original.shape[1], "%s: the panels do not give back the picture" % kind
        for name, img in pieces.items():
            outputs[os.path.join(OBJ, name)] = png_bytes(img)
        if debug:
            os.makedirs(debug, exist_ok=True)
            orig_img = Image.fromarray(original.astype(np.uint8))
            contact_sheet(kind, spec, pieces, orig_img).save(os.path.join(debug, "sheet_%s.png" % kind))
    outputs[VEHICLES] = write_vehicles(records_by_kind).encode()
    bad = 0
    for path, data in outputs.items():
        same = os.path.exists(path) and open(path, "rb").read() == data
        if check_only:
            if not same:
                print("differs: %s" % os.path.relpath(path, ROOT))
                bad += 1
        elif not same:
            with open(path, "wb") as f:
                f.write(data)
    print("%d files %s" % (len(outputs), "checked" if check_only else "written (the ones that changed)"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
