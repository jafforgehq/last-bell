#!/usr/bin/env python3
"""Dresses the ring of streets (round 12, "the living streets"): writes assets/data/dressing.json.

The city round the base looked empty. This makes about a hundred and fifty decals and light props (blood, a body, papers,
bags and bins on the sidewalk, crates and sandbags where a barricade was, tyres, a hydrant knocked over) out of the pictures
the game already has in assets/objects, and puts them where a place that fell would have them: the remains of a barricade at
each mouth of the ring (lots.json), a body by a car, rubbish along the sidewalks, dropped things in the road. The north
street and the mouths are the densest, the school's side the sparsest.

Nothing here is solid: the walking grids do not change. Every piece lies on open ground of the street (asphalt, sidewalk or
the dirt of an alley; open for both the people and the dead), clear of every wall, prop, car and tree of the map, of the
walls' footprints at the mouths, of the ring's 3 x 3 lots and their work spots, of the yard, of the gate's lane and of the
place where the gate's vehicles park (round 13).

The file is this script's output and the script is rerunnable (seeded: the same map and lots make the same file):

    python3 tools/make_dressing.py                 # write assets/data/dressing.json
    python3 tools/make_dressing.py --preview x.png # and draw the map with the pieces on it (needs Pillow)

A piece: f the picture in assets/objects without .png, x and y the middle of the picture (tiles), w and h its size (tiles;
the picture's pixels over PPT), flat true for what lies on the ground (drawn under the people), flip (mirrored), rot (turned,
degrees clockwise; the box it covers is the turned one), sort the line the feet of a standing piece are on (the people walk
behind it up to there; the bottom edge unless said). scripts/render/dressing_node.gd draws it; tests/test_dressing.gd checks
what is said above against the map.
"""
import json
import math
import os
import random
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_PATH = os.path.join(ROOT, "assets/data/map.json")
LOTS_PATH = os.path.join(ROOT, "assets/data/lots.json")
OBJ_DIR = os.path.join(ROOT, "assets/objects")
OUT_PATH = os.path.join(ROOT, "assets/data/dressing.json")

SEED = 12012

# ------------------------------------------------------------------ sizes --
# Pixels to the tile. The building art draws the props at about 148; what lies on the ground (blood, papers, stains,
# trails) is drawn at 64 where the baked map draws it (they were made for it), and a body at 96 as the five that lie in the
# street already do.
PPT_DECAL = 64.0
PPT_BODY = 96.0
PPT_PROP = 148.0
DECALS = {"blood", "papers", "stain", "trail", "tracks", "spray"}
# the street furniture is drawn at the size the baked street has it (the very pictures of its bins, bags, hydrants and
# benches are there already, and a bin half that size beside them looks lost)
PPT_KIND = {"corpse": PPT_BODY, "trashcan": PPT_BODY, "trashbags": PPT_BODY, "hydrant": PPT_BODY, "bench": PPT_BODY}

# Every piece must lie on one of these (terrain ids: 1 asphalt, 2 sidewalk, 13 dirt of an alley) and on ground that is open
# for the people and for the dead.
STREET_TERRAIN = (1, 2, 13)
# How much two pieces may cover each other (of the smaller one's box): blood under a body, bags against a bin.
OVERLAP_MAX = 0.3
# A body's picture has a wide soft shadow round it: what has to keep clear of other things is the middle of the picture,
# this much of its box (the ground it lies on is still the whole box).
CORE = {"corpse": 0.75}
# How far a piece keeps from a wall's footprint, a lot, a work spot (tiles).
CLEAR = 0.4
# The ring's lots of round 9 (the middle of each 3 by 3 lot): round 11 cut them down to the six that lots.json has now, and
# this keeps the places of all seventeen clear in case the cut moves, so that a building can still be put on any of them.
RESERVED_LOTS = [
    (11.5, 11.5), (23.5, 8.5), (30.5, 13.5), (43.5, 6.5), (50.5, 12.5), (61.5, 7.5), (74.5, 13.5), (8.5, 18.5), (70.5, 18.5),
    (15.5, 36.5), (6.5, 42.5), (10.5, 47.5), (18.5, 51.5), (72.5, 40.5), (65.5, 47.5), (73.5, 46.5), (79.5, 53.5),
]
# What is left alone for the gate's parked vehicles (round 13): x0, y0, x1, y1.
GATE_PARKING = (33.5, 6.0, 44.5, 15.0)
# The eastbound lane (round 15: the colony's vehicles drive out and in along it, from x -8 to 92): nothing of the dressing stands in it
# (tools/edit_gate.py moved what the dresser had put there; run again, this keeps it clear).
VEHICLE_LANE = (-12.0, 9.9, 96.0, 12.6)
# How many pieces at most, so that a change of the map cannot flood the street.
MAX_PIECES = 175

# ---------------------------------------------------------------- pictures --
CRATES = ["060_crate", "062_crate", "063_crate", "120_crate", "136_crate", "137_crate", "138_crate", "139_crate", "140_crate"]
BAGS = ["253_trashbags", "254_trashbags", "255_trashbags"]
BIN = "257_trashcan"
FALLEN_BIN = "252_trashcan"
HYDRANTS = ["250_hydrant", "251_hydrant"]
BENCHES = ["256_bench", "055_bench"]
TIRES = "071_tires"
SCRAP = ["069_scrap", "142_scrap"]
BARROW = "130_wheelbarrow"
SANDBAGS = "141_sandbags"
TARP = "117_tarp"
DRUMS = ["125_rainbarrel", "126_rainbarrel"]
CORPSES = ["267_corpse", "269_corpse", "271_corpse", "273_corpse", "275_corpse"]
BLOOD_BIG = ["268_blood", "270_blood", "272_blood", "274_blood", "276_blood"]
BLOOD_SMALL = ["%03d_blood" % i for i in (277, 278, 280, 281, 282, 284, 285, 287, 289, 292, 293, 294, 295, 298, 300, 301, 302, 303, 304)]
TRAILS = ["305_trail", "306_trail", "307_trail"]
PAPERS = ["%03d_papers" % i for i in range(309, 339)]
STAINS = ["%03d_stain" % i for i in (339, 340, 342, 343, 344, 346, 349, 351, 352, 356, 359, 360, 361, 362)]
TRACKS = "115_tracks"

_sizes = {}


def png_size(name):
    if name not in _sizes:
        with open(os.path.join(OBJ_DIR, name + ".png"), "rb") as f:
            head = f.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(name + " is not a PNG")
        _sizes[name] = struct.unpack(">II", head[16:24])
    return _sizes[name]


def kind_of(name):
    return name.split("_", 1)[1]


def ppt_of(name):
    k = kind_of(name)
    if k in DECALS:
        return PPT_DECAL
    return PPT_KIND.get(k, PPT_PROP)


def tiles_of(name, scale=1.0):
    pw, ph = png_size(name)
    p = ppt_of(name)
    return pw / p * scale, ph / p * scale


def turned_box(w, h, rot):
    """The width and height of the box a w by h picture turned by rot degrees covers."""
    r = math.radians(rot)
    c = abs(math.cos(r))
    s = abs(math.sin(r))
    return w * c + h * s, w * s + h * c


# ------------------------------------------------------------------- map --
class Ground:
    def __init__(self):
        with open(MAP_PATH) as f:
            self.map = json.load(f)
        with open(LOTS_PATH) as f:
            self.lots = json.load(f)
        m = self.map
        self.W = int(m["W"])
        self.H = int(m["H"])
        self.terrain = m["terrain"]
        self.solid_z = m["solidZ"]
        self.solid_p = m["solidP"]
        self.forbidden = []   # (x0, y0, x1, y1, why)
        self.hard = []        # obstacles: ("obb", cx, cy, w, h, a) or ("box", x0, y0, x1, y1)
        self.soft = []        # the baked decals: (x0, y0, x1, y1)
        self._forbid()
        self._obstacles()

    def open_tile(self, tx, ty):
        if tx < 0 or ty < 0 or tx >= self.W or ty >= self.H:
            return False
        i = ty * self.W + tx
        return self.terrain[i] in STREET_TERRAIN and self.solid_z[i] == 0 and self.solid_p[i] == 0

    def open_box(self, x0, y0, x1, y1):
        e = 0.02
        for ty in range(math.floor(y0 + e), math.floor(y1 - e) + 1):
            for tx in range(math.floor(x0 + e), math.floor(x1 - e) + 1):
                if not self.open_tile(tx, ty):
                    return False
        return True

    def _forbid(self):
        for mo in self.lots["mouths"]:
            x0, y0, x1, y1 = mo["rect"]
            self.forbidden.append((x0 - CLEAR, y0 - CLEAR, x1 + 1 + CLEAR, y1 + 1 + CLEAR, "mouth " + mo["id"]))
            px, py = mo["post"]["pos"]
            self.forbidden.append((px - 0.9, py - 0.9, px + 0.9, py + 0.9, "post " + mo["id"]))
        for pl in self.lots["plots"]:
            cx, cy = pl["pos"]
            sx, sy = pl["size"]
            self.forbidden.append((cx - sx / 2 - CLEAR, cy - sy / 2 - CLEAR, cx + sx / 2 + CLEAR, cy + sy / 2 + CLEAR, "plot " + pl["id"]))
            wx, wy = pl["work"]
            self.forbidden.append((wx - 1.7, wy - 0.9, wx + 1.7, wy + 0.9, "work " + pl["id"]))
        for cx, cy in RESERVED_LOTS:
            self.forbidden.append((cx - 1.5 - CLEAR, cy - 1.5 - CLEAR, cx + 1.5 + CLEAR, cy + 2.4 + CLEAR, "plot (reserved)"))
        for sp in self.map["spawns"]:
            self.forbidden.append((sp[0] - 1.0, sp[1] - 1.0, sp[0] + 1.0, sp[1] + 1.0, "spawn"))
        self.forbidden.append(GATE_PARKING + ("the gate",))
        self.forbidden.append(VEHICLE_LANE + ("the vehicles' lane",))

    def _obstacles(self):
        for o in self.map["objects"]:
            k = o["kind"]
            if k in ("leaves", "treeShadow", "crack", "tufts"):
                continue
            if k in ("blood", "papers", "stain", "trail", "spray", "scorch", "tracks"):
                for p in o.get("pieces", []):
                    self.soft.append((p["x"], p["y"], p["x"] + p["w"], p["y"] + p["h"]))
                continue
            if k in ("manhole", "drain"):
                self.hard.append(("box", o["cx"] - o["w"] / 2 - 0.1, o["cy"] - o["h"] / 2 - 0.1, o["cx"] + o["w"] / 2 + 0.1, o["cy"] + o["h"] / 2 + 0.1))
                continue
            if k == "lamppost":
                self.hard.append(("box", o["cx"] - 0.6, o["cy"] - 0.6, o["cx"] + 0.6, o["cy"] + 0.6))
                continue
            if k in ("awning",):
                self.hard.append(("box", o["cx"] - o["w"] / 2, o["cy"] - o["h"] / 2, o["cx"] + o["w"] / 2, o["cy"] + o["h"] / 2))
                continue
            # a prop, a car, a corpse, a bench, a bin: its turned rectangle, a little fatter
            self.hard.append(("obb", o["cx"], o["cy"], o["w"] + 0.2, o["h"] + 0.2, o["a"]))
        for t in self.map["trees"]:
            self.hard.append(("box", t["x"] - 0.7, t["y"] - 0.7, t["x"] + 0.7, t["y"] + 0.4))

    def hits_hard(self, x0, y0, x1, y1):
        """Whether the box (x0, y0, x1, y1) meets an obstacle: a box exactly, a turned rectangle by the separating axes."""
        for ob in self.hard:
            if ob[0] == "box":
                if x0 < ob[3] and x1 > ob[1] and y0 < ob[4] and y1 > ob[2]:
                    return True
                continue
            _, cx, cy, w, h, a = ob
            c = math.cos(a)
            s = math.sin(a)
            ex = abs(c) * w / 2 + abs(s) * h / 2
            ey = abs(s) * w / 2 + abs(c) * h / 2
            # the turned rectangle's own box against the box
            if x0 >= cx + ex or x1 <= cx - ex or y0 >= cy + ey or y1 <= cy - ey:
                continue
            # the box against the turned rectangle's two axes
            bx = (x0 + x1) / 2 - cx
            by = (y0 + y1) / 2 - cy
            hx = (x1 - x0) / 2
            hy = (y1 - y0) / 2
            if abs(bx * c + by * s) >= w / 2 + hx * abs(c) + hy * abs(s):
                continue
            if abs(-bx * s + by * c) >= h / 2 + hx * abs(s) + hy * abs(c):
                continue
            return True
        return False

    def forbidden_hit(self, x0, y0, x1, y1):
        for f in self.forbidden:
            if x0 < f[2] and x1 > f[0] and y0 < f[3] and y1 > f[1]:
                return f[4]
        return ""


def overlap_ratio(a, b):
    """How much of the smaller box the two boxes (x0, y0, x1, y1) share."""
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    if w <= 0 or h <= 0:
        return 0.0
    small = min((a[2] - a[0]) * (a[3] - a[1]), (b[2] - b[0]) * (b[3] - b[1]))
    return w * h / small if small > 0 else 1.0


class Dress:
    """The pieces so far, and the one question: may this go here?"""

    def __init__(self, ground, rng):
        self.g = ground
        self.rng = rng
        self.pieces = []
        self.boxes = []
        self.group = "?"
        self.refused = {}

    def add(self, f, x, y, rot=0.0, flip=None, scale=1.0, flat=None, wander=0.0, tries=1):
        """Puts picture `f` with its middle at (x, y), turned, if the place is good; else, up to `tries` times, a little
        aside (`wander` tiles). Returns the piece, or None."""
        if len(self.pieces) >= MAX_PIECES:
            return None
        w, h = tiles_of(f, scale)
        if flat is None:
            flat = kind_of(f) in DECALS or kind_of(f) == "corpse"
        if flip is None:
            flip = self.rng.random() < 0.5
        bw, bh = turned_box(w, h, rot)
        for t in range(tries):
            cx = x + (self.rng.uniform(-wander, wander) if t > 0 else 0.0)
            cy = y + (self.rng.uniform(-wander, wander) if t > 0 else 0.0)
            box = (cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2)
            k = CORE.get(kind_of(f), 1.0)
            core = (cx - bw / 2 * k, cy - bh / 2 * k, cx + bw / 2 * k, cy + bh / 2 * k)
            why = self._refuse(box, core)
            if why:
                self.refused[why] = self.refused.get(why, 0) + 1
                continue
            p = {"f": f, "x": round(cx, 2), "y": round(cy, 2), "w": round(w, 3), "h": round(h, 3)}
            if flip:
                p["flip"] = True
            if flat:
                p["flat"] = True
            if abs(rot) > 0.5:
                p["rot"] = round(rot, 1)
            if not flat:
                p["sort"] = round(cy + bh * 0.38, 2)
            p["_group"] = self.group
            self.pieces.append(p)
            self.boxes.append(core)
            return p
        return None

    def _refuse(self, box, core):
        g = self.g
        if not g.open_box(*box):
            return "ground"
        why = g.forbidden_hit(*core)
        if why:
            return why.split(" ")[0]
        if g.hits_hard(*core):
            return "obstacle"
        for s in g.soft:
            if overlap_ratio(core, s) > OVERLAP_MAX:
                return "baked decal"
        for b in self.boxes:
            if overlap_ratio(core, b) > OVERLAP_MAX:
                return "piece"
        return ""


# ----------------------------------------------------------------- groups --
def pick(rng, items):
    return items[rng.randrange(len(items))]


def spill_papers(d, rng, x, y, n=1, spread=0.9, chance=0.8):
    """Sheets of paper (each placed with this chance) round (x, y)."""
    for _ in range(n):
        if rng.random() < chance:
            d.add(pick(rng, PAPERS), x + rng.uniform(-spread, spread), y + rng.uniform(-spread, spread), rot=rng.uniform(-90, 90), tries=4, wander=0.5)


def body_group(d, rng, x, y, ang, with_trail=True):
    """A body, the blood beside and behind it, a drag mark and papers: `ang` is the way it was dragged or ran (radians, 0
    east, y down); the blood and the mark take another way when that one is blocked."""
    c = d.add(pick(rng, CORPSES), x, y, tries=12, wander=0.9)
    if c is None:
        return None
    x, y = c["x"], c["y"]
    a = ang
    for k in range(8):
        a = ang + (0.0 if k == 0 else rng.uniform(-1.3, 1.3) + (math.pi if k > 3 else 0.0))
        if d.add(pick(rng, BLOOD_BIG), x - math.cos(a) * 0.95, y - math.sin(a) * 0.95, rot=rng.uniform(-40, 40), tries=2, wander=0.25):
            break
    ux, uy = math.cos(a), math.sin(a)
    for k in range(rng.randrange(1, 3)):
        d.add(pick(rng, BLOOD_SMALL), x - ux * rng.uniform(1.6, 2.6) + rng.uniform(-0.4, 0.4), y - uy * rng.uniform(1.6, 2.6) + rng.uniform(-0.4, 0.4), rot=rng.uniform(-40, 40), tries=5, wander=0.5)
    if with_trail and rng.random() < 0.6:
        t = pick(rng, TRAILS)
        tw, th = tiles_of(t, 0.7)
        # the trail's long side is turned along the drag
        turn = math.degrees(a) - (0.0 if tw >= th else 90.0)
        d.add(t, x - ux * 3.0, y - uy * 3.0, rot=turn, scale=0.7, tries=5, wander=0.5)
    spill_papers(d, rng, x + uy * 1.3, y - ux * 1.3, n=rng.randrange(1, 3), chance=0.6)
    return c


def car_groups(d, rng, ground):
    """By each car that stands in the street (not the compound's own walls): what a crash or a flight left."""
    cars = [o for o in ground.map["objects"] if o["kind"] in ("car", "pickup") and o.get("segment") is None]
    plan = ["body", "bags", "debris", "body", "bags", "debris", "stain", "body", "debris", "bags", "stain", "body"]
    k = 0
    for o in cars:
        # the cars along the school's side of the ring get only a stain and a skid mark
        if o["cy"] > 55.0:
            kind = "stain"
        else:
            kind = plan[k % len(plan)]
            k += 1
        d.group = "car %d %s" % (o["id"], kind)
        a = o["a"]
        ux, uy = math.cos(a), math.sin(a)       # along the car
        vx, vy = -uy, ux                        # across it
        side = 1.0 if rng.random() < 0.5 else -1.0
        L = o["w"] / 2.0
        Wd = o["h"] / 2.0
        cx, cy = o["cx"], o["cy"]
        if kind == "body":
            for k in range(8):
                sd = side if k % 2 == 0 else -side
                ox = cx + vx * sd * (Wd + 1.4 + 0.15 * k) + ux * rng.uniform(-0.8, 1.0)
                oy = cy + vy * sd * (Wd + 1.4 + 0.15 * k) + uy * rng.uniform(-0.8, 1.0)
                if body_group(d, rng, ox, oy, math.atan2(vy * sd, vx * sd) + rng.uniform(-0.6, 0.6)):
                    break
        elif kind == "bags":
            for k in range(rng.randrange(1, 3)):
                d.add(pick(rng, BAGS), cx + ux * (L + 0.8 + k * 0.9) * (1 if k % 2 == 0 else -1), cy + uy * (L + 0.8 + k * 0.9) * (1 if k % 2 == 0 else -1) + rng.uniform(-0.3, 0.3), rot=rng.uniform(-30, 30), tries=8, wander=0.5)
            spill_papers(d, rng, cx + vx * side * (Wd + 1.0), cy + vy * side * (Wd + 1.0), n=1, chance=0.6)
        elif kind == "debris":
            d.add(TIRES, cx + ux * (L + 1.0) + vx * side * 0.3, cy + uy * (L + 1.0) + vy * side * 0.3, rot=rng.uniform(0, 180), tries=8, wander=0.6)
            d.add(pick(rng, SCRAP), cx - ux * (L + 1.3) + vx * side * 0.5, cy - uy * (L + 1.3) + vy * side * 0.5, tries=8, wander=0.7)
            d.add(pick(rng, BLOOD_SMALL), cx + vx * side * (Wd + 0.7), cy + vy * side * (Wd + 0.7), rot=rng.uniform(0, 360), tries=5, wander=0.4)
        else:
            d.add(pick(rng, STAINS), cx + ux * (L + 1.2), cy + uy * (L + 1.2), rot=rng.uniform(0, 180), tries=8, wander=0.8)
            d.add(TRACKS, cx - ux * (L + 3.4), cy - uy * (L + 3.4), rot=math.degrees(a) + 90.0, tries=10, wander=0.6, scale=0.8)
            spill_papers(d, rng, cx + vx * side * (Wd + 1.2), cy + vy * side * (Wd + 1.2), n=1, chance=0.6)


def mouth_groups(d, rng, ground):
    """The remains of a barricade outside each wall plot: sandbags torn open, crates, a heap of scrap, tyres, the people who
    held it and what they carried."""
    for mo in ground.lots["mouths"]:
        x0, y0, x1, y1 = mo["rect"]
        side = mo["side"]
        length = float(mo["length"])
        d.group = "mouth " + mo["id"]
        ox, oy = {"N": (0.0, -1.0), "S": (0.0, 1.0), "W": (-1.0, 0.0), "E": (1.0, 0.0)}[side]
        ax, ay = -oy, ox                         # along the wall
        horiz = side in ("N", "S")
        face = {"N": float(y0), "S": float(y1 + 1), "W": float(x0), "E": float(x1 + 1)}[side]
        cxm, cym = mo["center"]
        sp = ground.map["spawns"][int(mo["spawn"])]

        def at(t, n):
            # t along the wall from its middle, n out from its outer face
            if horiz:
                return cxm + ax * t, face + oy * n
            return face + ox * n, cym + ay * t

        turn = 0.0 if horiz else 90.0
        half = length / 2.0
        # the places along the wall that have open street outside them (a street can be narrower than its wall)
        ts = []
        t = -half + 0.7
        while t <= half - 0.7:
            x, y = at(t, 1.0)
            if ground.open_tile(math.floor(x), math.floor(y)):
                ts.append(t)
            t += 0.5
        if not ts:
            continue
        want_sandbags = 2 if length >= 10 else 1
        clusters = 2 if length >= 4.5 else 1
        # sandbags torn from the barricade, lying along it
        for k in range(want_sandbags):
            t = pick(rng, ts)
            x, y = at(t, rng.uniform(0.9, 1.5))
            d.add(SANDBAGS, x, y, rot=turn + rng.uniform(-12, 12), tries=14, wander=0.8)
        kinds = ["crates", "spill", "junk", "crates", "drum", "junk"]
        rng.shuffle(kinds)
        for k in range(clusters):
            t = pick(rng, ts)
            n = rng.uniform(1.0, 2.0)
            x, y = at(t, n)
            kind = kinds[k % len(kinds)]
            if kind == "crates":
                d.add(pick(rng, CRATES), x, y, rot=rng.uniform(-25, 25), tries=10, wander=0.8)
                d.add(pick(rng, CRATES), x + ax * 0.85, y + ay * 0.85 + ox * 0.2, rot=rng.uniform(-40, 40), tries=10, wander=0.8)
                spill_papers(d, rng, x - ax * 0.5 + ox * 0.9, y - ay * 0.5 + oy * 0.9, n=1, chance=0.6)
            elif kind == "spill":
                d.add(pick(rng, CRATES), x, y, rot=rng.uniform(25, 65), tries=10, wander=0.8)
                spill_papers(d, rng, x + ax * 0.9, y + ay * 0.9, n=2, chance=0.6)
                d.add(pick(rng, BLOOD_SMALL), x - ax * 0.7 + ox * 0.6, y - ay * 0.7 + oy * 0.6, rot=rng.uniform(0, 360), tries=5, wander=0.4)
            elif kind == "junk":
                d.add(pick(rng, SCRAP), x, y, tries=10, wander=0.8)
                d.add(TIRES, x + ax * 1.3, y + ay * 1.3, rot=turn + rng.uniform(-20, 20), tries=10, wander=0.8)
            else:
                d.add(pick(rng, DRUMS), x, y, tries=10, wander=0.8)
                d.add(pick(rng, BAGS), x + ax * 0.9, y + ay * 0.9, rot=rng.uniform(-30, 30), tries=8, wander=0.8)
        # the one who held it, in most of them
        if rng.random() < 0.8:
            for k in range(8):
                t = pick(rng, ts)
                x, y = at(t, rng.uniform(1.2, 2.4))
                if body_group(d, rng, x, y, math.atan2(oy, ox) + rng.uniform(-0.5, 0.5)):
                    break
        # an alley is narrow and its dead come out of a spawn point's own corner: when the big things did not fit, small ones
        # (a crate, a bag, sheets of paper, a stain of blood) that do, looked for place by place, on the dead's side and (a
        # few) on the near side of the wall, the street the people hold
        mine = [p for p in d.pieces if p["_group"] == d.group]
        all_t = [-half + 0.5 + 0.5 * k for k in range(int(length / 0.5))]
        spots = [(t, n) for t in ts for n in (0.8, 1.0, 1.2, 1.4, 1.6)] + [(t, n) for t in all_t for n in (-3.9, -4.2, -4.5)]
        for f in (pick(rng, CRATES), pick(rng, BAGS), pick(rng, PAPERS), pick(rng, BLOOD_SMALL), pick(rng, CRATES), pick(rng, PAPERS)):
            if len(mine) >= 3:
                break
            rng.shuffle(spots)
            for t, n in spots:
                x, y = at(t, n)
                rot = rng.uniform(-30, 30) if kind_of(f) not in DECALS else rng.uniform(-60, 60)
                if d.add(f, x, y, rot=rot, tries=2, wander=0.3):
                    mine = [p for p in d.pieces if p["_group"] == d.group]
                    break


def sidewalks(d, rng, ground):
    """What lines a sidewalk: bins and bags against the buildings, a bench or a hydrant by the kerb, a bin that was knocked
    over, a crate that someone dropped. Each line has its face (where the wall is), the way away from it, its length and how
    close together things stand there."""
    # name, horizontal, face coordinate, away (+1/-1), from, to, gap (min, max) along it, width of the sidewalk
    lines = [
        ("north street, north sidewalk", True, 4.0, 1.0, 5.5, 80.5, (3.5, 6.0), 2.0),
        ("north street, south sidewalk", True, 15.0, -1.0, 5.5, 80.5, (4.0, 6.5), 2.0),
        ("west road, west sidewalk", False, 3.0, 1.0, 15.5, 61.5, (9.0, 14.0), 2.0),
        ("west road, east sidewalk", False, 14.0, -1.0, 15.5, 61.5, (11.0, 16.0), 2.0),
        ("east road, east sidewalk", False, 81.0, -1.0, 15.5, 61.5, (9.0, 14.0), 2.0),
        ("east road, west sidewalk", False, 70.0, 1.0, 15.5, 61.5, (11.0, 16.0), 2.0),
        ("south street", True, 60.0, 1.0, 5.5, 80.5, (16.0, 26.0), 2.0),
    ]
    templates = ["bin_bags", "bags", "fallen_bin", "crate", "bench", "hydrant", "barrow", "drift", "bin_bags", "stain"]
    for name, horiz, face, away, s0, s1, gap, width in lines:
        d.group = name
        s = s0 + rng.uniform(0.0, gap[1])
        while s < s1:
            kind = pick(rng, templates)
            _line_cluster(d, rng, kind, horiz, face, away, s, width)
            s += rng.uniform(gap[0], gap[1])


def _line_cluster(d, rng, kind, horiz, face, away, s, width):
    def put(f, ds, u, rot=0.0, scale=1.0, tries=10, flat=None):
        """u: the gap between the face and the picture's near edge."""
        w, h = tiles_of(f, scale)
        # the box this will cover once it is along the line: turned a quarter on the vertical lines when it is long
        r = rot + (90.0 if (not horiz and w > h * 1.5) else 0.0)
        bw, bh = turned_box(w, h, r)
        cross = (bh if horiz else bw) / 2.0
        c = face + away * (u + cross)
        x, y = (s + ds, c) if horiz else (c, s + ds)
        return d.add(f, x, y, rot=r, scale=scale, tries=tries, wander=0.5, flat=flat)

    if kind == "bin_bags":
        put(BIN, 0.0, rng.uniform(0.1, 0.3))
        put(pick(rng, BAGS), rng.uniform(0.7, 1.1), rng.uniform(0.1, 0.4), rot=rng.uniform(-20, 20))
        if rng.random() < 0.5:
            put(pick(rng, PAPERS), rng.uniform(-0.2, 0.8), rng.uniform(0.9, 1.4), rot=rng.uniform(-90, 90))
    elif kind == "bags":
        put(pick(rng, BAGS), 0.0, rng.uniform(0.1, 0.4), rot=rng.uniform(-25, 25))
        if rng.random() < 0.6:
            put(pick(rng, BAGS), rng.uniform(0.8, 1.2), rng.uniform(0.1, 0.5), rot=rng.uniform(-25, 25))
    elif kind == "fallen_bin":
        put(FALLEN_BIN, 0.0, rng.uniform(0.1, 0.4), rot=rng.uniform(-30, 30))
        if rng.random() < 0.6:
            put(pick(rng, PAPERS), 0.9, rng.uniform(0.6, 1.2), rot=rng.uniform(-90, 90))
    elif kind == "crate":
        put(pick(rng, CRATES), 0.0, rng.uniform(0.1, 0.5), rot=rng.uniform(-30, 30))
        put(pick(rng, PAPERS), rng.uniform(0.6, 1.2), rng.uniform(0.4, 1.0), rot=rng.uniform(-90, 90))
    elif kind == "bench":
        put(pick(rng, BENCHES), 0.0, rng.uniform(0.1, 0.3))
        if rng.random() < 0.4:
            put(pick(rng, PAPERS), rng.uniform(-0.5, 0.5), 0.9, rot=rng.uniform(-90, 90))
    elif kind == "hydrant":
        put(pick(rng, HYDRANTS), 0.0, width - 0.7, rot=rng.choice([0.0, 90.0, 180.0, 270.0]))
    elif kind == "barrow":
        put(BARROW, 0.0, rng.uniform(0.2, 0.7), rot=rng.uniform(-60, 60))
    elif kind == "tires":
        put(TIRES, 0.0, rng.uniform(0.1, 0.5), rot=rng.uniform(-20, 20))
        if rng.random() < 0.5:
            put(pick(rng, BAGS), rng.uniform(0.9, 1.4), rng.uniform(0.1, 0.5), rot=rng.uniform(-25, 25))
    elif kind == "stain":
        put(pick(rng, STAINS), 0.0, rng.uniform(0.0, 0.4), rot=rng.uniform(-30, 30))
        put(pick(rng, PAPERS), rng.uniform(0.8, 1.6), rng.uniform(0.2, 0.9), rot=rng.uniform(-90, 90))
    else:
        # things the wind took along the face
        for k in range(2):
            put(pick(rng, PAPERS), k * rng.uniform(0.8, 1.4), rng.uniform(0.1, 1.2), rot=rng.uniform(-90, 90))


def gutters(d, rng, ground):
    """The road's own edges: what the wind and the people running left along each kerb (papers, a crate, tyres, a bag, an
    oil stain), a little less often than on the sidewalks. The kerb is the face and away is into the lane."""
    # name, horizontal, kerb coordinate, away, from, to, gap (min, max) along it
    lines = [
        ("north street, north gutter", True, 6.0, 1.0, 5.5, 80.5, (5.0, 9.0)),
        ("north street, south gutter", True, 13.0, -1.0, 5.5, 80.5, (5.0, 9.0)),
        ("west road, west gutter", False, 5.0, 1.0, 15.5, 61.5, (12.0, 17.0)),
        ("west road, east gutter", False, 12.0, -1.0, 15.5, 61.5, (12.0, 17.0)),
        ("east road, west gutter", False, 72.0, 1.0, 15.5, 61.5, (12.0, 17.0)),
        ("east road, east gutter", False, 79.0, -1.0, 15.5, 61.5, (12.0, 17.0)),
        ("south street, gutter", True, 62.0, 1.0, 5.5, 80.5, (22.0, 32.0)),
    ]
    kinds = ["drift", "crate", "tires", "drift", "stain", "stain"]
    for name, horiz, kerb, away, s0, s1, gap in lines:
        d.group = name
        s = s0 + rng.uniform(0.0, gap[1])
        while s < s1:
            _line_cluster(d, rng, pick(rng, kinds), horiz, kerb, away, s, 1.4)
            s += rng.uniform(gap[0], gap[1])


def set_pieces(d, rng, ground):
    """A few things that tell something by themselves: a hydrant knocked over in its own puddle, a tarp somebody lived
    under, and the crates they had with them."""
    d.group = "hydrant knocked over"
    # (x, y) of the places: on the sidewalk by a kerb, clear of the rest
    for x, y in ((57.0, 13.7), (73.2, 54.5), (11.2, 22.5)):
        h = d.add(pick(rng, HYDRANTS), x, y, rot=rng.uniform(60, 120), flip=False, tries=14, wander=1.2)
        if h is not None:
            for k in range(2):
                d.add(pick(rng, STAINS), h["x"] + rng.uniform(-0.6, 0.6), h["y"] + rng.uniform(0.2, 1.0), rot=rng.uniform(0, 180), scale=0.8, tries=8, wander=0.8)
    d.group = "tarp"
    for x, y, r in ((10.4, 2.2, -8.0), (82.7, 11.9, 80.0), (20.8, 61.9, 5.0), (62.0, 61.9, -6.0)):
        t = None    # (the tarps were taken out on 2026-10-04: they hid what stood under them and read as nothing)
        if t is not None:
            d.add(pick(rng, CRATES), t["x"] + 1.5, t["y"] + 0.2, rot=rng.uniform(-30, 30), tries=10, wander=0.8)
            d.add(pick(rng, DRUMS), t["x"] - 1.4, t["y"] - 0.1, tries=10, wander=0.8)


# ------------------------------------------------------------------- main --
def build():
    ground = Ground()
    rng = random.Random(SEED)
    d = Dress(ground, rng)
    set_pieces(d, rng, ground)
    mouth_groups(d, rng, ground)
    car_groups(d, rng, ground)
    sidewalks(d, rng, ground)
    gutters(d, rng, ground)
    return ground, d


def write(d, path=OUT_PATH):
    out = []
    for p in d.pieces:
        q = dict(p)
        q.pop("_group", None)
        out.append(q)
    doc = {
        "version": 1,
        "_doc": "The dressing of the ring of streets (round 12), made by tools/make_dressing.py from assets/data/map.json and "
                "assets/data/lots.json: do not edit by hand, run the script again. A piece: f, the picture in assets/objects "
                "without .png; x and y, the middle of the picture; w and h, its size (tiles); flat, true for what lies on the "
                "ground (drawn under the people); flip, mirrored; rot, turned (degrees, clockwise); sort, the line the feet of a "
                "standing piece are on (y, tiles; the people walk behind it up to there). None of it is solid. It is drawn "
                "only in a settlement game (scripts/render/dressing_node.gd).",
        "pieces": out,
    }
    with open(path, "w") as f:
        f.write("{\n \"version\": 1,\n \"_doc\": %s,\n \"pieces\": [\n" % json.dumps(doc["_doc"]))
        for i, p in enumerate(out):
            f.write("  " + json.dumps(p, separators=(", ", ": ")) + (",\n" if i < len(out) - 1 else "\n"))
        f.write(" ]\n}\n")


def preview(ground, d, path, scale=22):
    from PIL import Image, ImageDraw
    m = ground.map
    W, H = ground.W, ground.H
    cols = {1: (70, 70, 76), 2: (150, 148, 140), 3: (120, 110, 90), 4: (70, 110, 60), 12: (110, 110, 130), 13: (150, 110, 60)}
    im = Image.new("RGBA", (W * scale, H * scale), (30, 30, 30, 255))
    dr = ImageDraw.Draw(im)
    for y in range(H):
        for x in range(W):
            t = ground.terrain[y * W + x]
            c = cols.get(t, (95, 70, 70))
            dr.rectangle([x * scale, y * scale, x * scale + scale - 1, y * scale + scale - 1], fill=c)
            if ground.solid_z[y * W + x] or ground.solid_p[y * W + x]:
                dr.rectangle([x * scale, y * scale, x * scale + scale - 1, y * scale + scale - 1], fill=(120, 60, 60))

    def paste(name, x, y, w, h, flip=False, rot=0.0):
        img = Image.open(os.path.join(OBJ_DIR, name + ".png")).convert("RGBA")
        img = img.resize((max(1, int(w * scale)), max(1, int(h * scale))))
        if flip:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        if abs(rot) > 0.5:
            img = img.rotate(-rot, expand=True, resample=Image.BICUBIC)
        im.alpha_composite(img, (int(x * scale - img.width / 2), int(y * scale - img.height / 2)))

    for o in m["objects"]:
        if o["kind"] in ("locker", "crack", "treeShadow", "leaves"):
            continue
        for p in o.get("pieces", [])[:1] if o.get("states") is None else []:
            name = os.path.basename(p["file"])[:-4]
            if not os.path.exists(os.path.join(OBJ_DIR, name + ".png")):
                continue
            paste(name, p["x"] + p["w"] / 2, p["y"] + p["h"] / 2, p["w"], p["h"], p.get("flip_h", False))
        if o.get("states") is not None:
            for p in o["states"][0]:
                name = os.path.basename(p["file"])[:-4]
                if os.path.exists(os.path.join(OBJ_DIR, name + ".png")):
                    paste(name, p["x"] + p["w"] / 2, p["y"] + p["h"] / 2, p["w"], p["h"])
    for p in d.pieces:
        paste(p["f"], p["x"], p["y"], p["w"], p["h"], p.get("flip", False), p.get("rot", 0.0))
    dr = ImageDraw.Draw(im)
    for mo in ground.lots["mouths"]:
        x0, y0, x1, y1 = mo["rect"]
        dr.rectangle([x0 * scale, y0 * scale, (x1 + 1) * scale, (y1 + 1) * scale], outline=(255, 0, 255, 255), width=2)
    for pl in ground.lots["plots"]:
        cx, cy = pl["pos"]
        dr.rectangle([(cx - 1.5) * scale, (cy - 1.5) * scale, (cx + 1.5) * scale, (cy + 1.5) * scale], outline=(0, 255, 255, 255), width=2)
    g = GATE_PARKING
    dr.rectangle([g[0] * scale, g[1] * scale, g[2] * scale, g[3] * scale], outline=(255, 255, 0, 255), width=1)
    im.convert("RGB").save(path)


def main(argv):
    ground, d = build()
    write(d)
    groups = {}
    for p in d.pieces:
        key = p["_group"].split(" ")[0]
        groups[key] = groups.get(key, 0) + 1
    flat = sum(1 for p in d.pieces if p.get("flat"))
    print("%d pieces (%d flat, %d standing); by group: %s" % (len(d.pieces), flat, len(d.pieces) - flat, groups))
    print("refused: %s" % d.refused)
    if "--preview" in argv:
        preview(ground, d, argv[argv.index("--preview") + 1])


if __name__ == "__main__":
    main(sys.argv[1:])
