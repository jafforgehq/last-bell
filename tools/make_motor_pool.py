#!/usr/bin/env python3
"""Writes assets/data/motor_pool.json: where the colony's vehicles park and the roads they drive (round 15, task GATE).

The numbers are worked out here from a few choices (the bays, the radii) and written as dense polylines of
{x, y, r, rev, h} points, so that whatever smooths a route (scripts/sim/convoy.gd) has almost nothing left to round:
every point of the apron carries its nose heading `h`, a reversing stretch is marked with `rev` on each leg it makes.
tools/check_motor_pool.py then measures the file (not this script).

Run:  python3 tools/make_motor_pool.py            (writes the file)
      python3 tools/make_motor_pool.py --print    (prints it)
"""
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "data", "motor_pool.json")

# ---- the street and the gate (tiles) -------------------------------------------------------------------------------
LANE_Y = 11.25          # the eastbound lane's middle (the south side of the street)
EDGE_WEST = -8.0
EDGE_EAST = 92.0
GATE_X = 39.0           # the gate's middle (wall segment 2 spans x 36 to 42)
TURN_R = 3.0            # the corner between the lane and the gate (the centre of the car's path)

# ---- the apron (tiles) ---------------------------------------------------------------------------------------------
APRON = [33.8, 20.85, 8.7, 13.55]          # x, y, w, h: from the deck's foot to the south end of the aisle (x to 42.5: the workbench's crate and table start at 42.55)
AISLE_X = 38.05                          # the aisle's middle (its edges are 36.5 and 39.6: 3.1 wide, between the two side bays)
BAY_W, SEDAN_L = 2.2, 4.4
K_Y0 = 21.2              # where a car's centre is when it starts its swing round (nose south, under the bridge)
XS = {"W": 38.0, "E": 38.2, "A": AISLE_X}   # the line a car comes down the gate on, by where it is going
K_R1 = {"W": 1.2, "E": 1.2, "A": 1.2}       # the radius of the centre of its path in the swing (forward)
SWING = {"W": -1, "E": 1, "A": -1}          # -1: to the left (south to east first), +1: to the right (south to west first)
# (the reverse that follows has the radius that brings the nose north exactly on the bay's line)
# the spots: id, name, x, y of the centre of the parked car (nose north)
SPOTS = [
    {"id": 0, "name": "west bay",  "at": [35.4, 27.6], "side": "W"},
    {"id": 1, "name": "east bay",  "at": [40.7, 27.6], "side": "E"},
    {"id": 2, "name": "aisle end", "at": [38.05, 30.17], "side": "A"},   # y: 32.0 for a sedan, less the bus's extra 1.83 so that its tail is flush with the apron's end (the bus's centre IS `at`)
]
STEP_DEG = 10.0          # a point on every arc this many degrees
S_START = 26.2          # a car leaves a side bay straight on until its middle is here (its tail has passed the bay's neighbours)
S_OUT = 5.6              # and then swings into the aisle in an S-curve this long (tiles along it)


class Turtle:
    """Drives a centre path: `m` is the way the car MOVES (degrees, 0 east, 90 south), `rev` whether it reverses
    (then the nose points the other way, m + 180)."""

    def __init__(self, x, y, m, rev=False):
        self.x, self.y, self.m, self.rev = x, y, m, rev
        self.pts = []
        self.add(False)

    def nose(self):
        return (self.m + (180.0 if self.rev else 0.0)) % 360.0

    def add(self, rev_leg, r=0.0):
        p = {"x": round(self.x, 3), "y": round(self.y, 3), "r": r, "h": round(self.nose(), 1)}
        if rev_leg:
            p["rev"] = True
        self.pts.append(p)

    def line(self, d):
        a = math.radians(self.m)
        self.x += d * math.cos(a)
        self.y += d * math.sin(a)
        self.add(self.rev)

    def line_to(self, x=None, y=None):
        """Straight on until x (or y) is reached (the heading must run along that axis)."""
        a = math.radians(self.m)
        if x is not None:
            d = (x - self.x) / math.cos(a)
        else:
            d = (y - self.y) / math.sin(a)
        self.line(d)

    def arc(self, radius, deg):
        """A turn of `deg` (positive to the right, clockwise on the screen) on a circle of `radius`."""
        n = max(1, int(round(abs(deg) / STEP_DEG)))
        each = deg / n
        for _ in range(n):
            # chord of a small arc
            a0 = math.radians(self.m)
            a1 = math.radians(self.m + each)
            mid = (a0 + a1) / 2.0
            chord = 2.0 * radius * math.sin(abs(a1 - a0) / 2.0)
            self.x += chord * math.cos(mid)
            self.y += chord * math.sin(mid)
            self.m = (self.m + each) % 360.0
            self.add(self.rev)

    def reverse(self):
        """The car stops and now drives the other way: the nose stays, the motion turns round."""
        self.rev = not self.rev
        self.m = (self.m + 180.0) % 360.0

    def s_curve(self, lateral, along, sign):
        """Two arcs one after the other that move the car `lateral` sideways while it goes `along` on: the first
        turns to the right when sign is +1 (to the left when -1), the second turns back."""
        theta = 2.0 * math.degrees(math.atan2(abs(lateral), along))
        r = along / (2.0 * math.sin(math.radians(theta)))
        self.arc(r, sign * theta)
        self.arc(r, -sign * theta)
        return theta, r


def tidy(pts):
    """Takes out points that sit on top of each other and marks the first point of the route as not reversing."""
    out = []
    for p in pts:
        if out and abs(out[-1]["x"] - p["x"]) < 1e-6 and abs(out[-1]["y"] - p["y"]) < 1e-6:
            if p.get("rev"):
                out[-1]["rev"] = True
            continue
        out.append(p)
    out[0].pop("rev", None)
    return out


def in_route(spot):
    """From the west edge along the lane, right into the gate, a swing round in the top of the apron, a reverse into the bay."""
    ax, ay = spot["at"]
    side = spot["side"]
    xs = XS[side]
    # a car for the west bay swings to the left (south to east), one for the east bay or the aisle's end to the right (south to
    # west); then it reverses in a quarter circle that ends with the nose to the north on the bay's line, and on into the bay
    swing = SWING[side]
    r1 = K_R1[side]
    t = Turtle(EDGE_WEST, LANE_Y, 0.0)
    t.line_to(x=xs - TURN_R)
    t.arc(TURN_R, 90.0)                                   # right into the gate
    t.line_to(y=K_Y0)
    t.arc(r1, 90.0 * swing)                               # the swing (forward)
    t.reverse()
    # the circle of the reverse is centred straight below the point where the swing ended, on the side of the bay
    r2 = abs(ax - t.x)
    t.arc(r2, 90.0 * swing)
    # at (ax, y) nose north, moving south (reversing): on into the bay
    t.line_to(y=ay)
    return tidy(t.pts)


def out_route(spot):
    """From the bay forward (north) to the aisle's middle, up through the gate, right into the lane, away east."""
    ax, ay = spot["at"]
    side = spot["side"]
    t = Turtle(ax, ay, 270.0)
    if side != "A":
        lateral = AISLE_X - ax
        t.line_to(y=S_START)
        # driving north (m = 270), turning right goes east: a bay on the west turns right first
        t.s_curve(abs(lateral), S_OUT, +1 if lateral > 0 else -1)
    t.line_to(y=LANE_Y + TURN_R)
    t.arc(TURN_R, 90.0)                                    # right into the lane, heading east
    t.line_to(x=EDGE_EAST)
    return tidy(t.pts)


def build():
    spots = []
    for s in SPOTS:
        spots.append({"id": s["id"], "name": s["name"], "at": s["at"], "out_route": out_route(s), "in_route": in_route(s)})
    return spots


DOC = (
    "Where the colony's vehicles park and the roads they drive (round 15, task GATE; written by tools/make_motor_pool.py, checked by "
    "tools/check_motor_pool.py: change the choices there and run it again, do not edit the points by hand). Tiles, x east, y south; a heading "
    "is in degrees, 0 east, 90 south, 270 north. THE PLACE: the motor pool is the apron inside the main gate (`apron` [x, y, w, h]); the gate "
    "is the opening in the north wall (wall segment 2): its middle is `gate.x`, the free opening between the two gate posts is `gate.free` "
    "wide (the leaves slide out of it behind the neighbouring wall pieces), and a car passing it is under the walkway's bridge between "
    "`gate.y_north` and `gate.y_south`; the street's eastbound lane (the south side) has its middle at `lane_y`, and the route's ends are "
    "`edge_west` (where a car comes onto the map) and `edge_east` (where it leaves). `zones` are the rectangles [x0, y0, x1, y1] a car's body "
    "(2.2 wide, 4.4 long) may be in: lane, junction (where it turns between the lane and the gate), gate (between the pallets and the bus), "
    "posts (between the two gate posts), bridge (under the catwalk bridge, between the ends of the deck's lattice) and apron. THE SPOTS: `at` is the "
    "middle of the parked car, nose to the north; a car leaves FORWARD (`out_route`: bay, aisle, gate, a right turn into the lane, east) and "
    "arrives FORWARD through the gate (`in_route`: west edge, lane, a right turn into the gate, down to the top of the apron, a swing round "
    "(forward, one way round the aisle's middle, then a few tiles in reverse the other way) to face north, then a REVERSING stretch down the "
    "aisle and into the bay). A route is a list of points {x, y, r, rev, h}: x and y the middle of the car; r the corner radius (0 everywhere: "
    "the corners are already cut into points); rev true on a point means the leg that ENDS at that point is driven in reverse (the nose keeps "
    "its heading while the car moves backwards); h the nose's heading, given on every point of the apron, the swing and the reverse: "
    "interpolate it between the points (unwrap the angle). Where `h` is missing the nose is the direction of the leg (turned round on a "
    "reversing leg). THE BUS: a vehicle longer than a bay (the bus, 2.6 x 8.07) takes the spot with `long: true` (the aisle end, id 2), "
    "whose `at` is the BUS's middle (so that its 8.07 tail is flush with the apron's end: it stands in the aisle between the two "
    "side bays, 2.6 wide in a 3.1 aisle); it swings through the gate and the apron on the same route and its ends overhang the apron at the "
    "swing (tools/check_motor_pool.py sweeps a sedan-sized body only; it does check the bus parked). THREE SPOTS: a fourth bay would stand "
    "behind another and could not leave forward, so the pool holds three and a fourth vehicle has to share a place; the aisle is 3.1 wide "
    "(between the cars in the two side bays), the gate's free opening 4.84."
)


def make():
    spots = build()
    gate_free = 4.84
    data = {
        "version": 2,
        "_doc": DOC,
        "apron": APRON,
        "gate": {"x": GATE_X, "y_north": 14.5, "y_south": 21.0, "w": 6.0, "free": gate_free, "aisle_x": AISLE_X},
        "lane_y": LANE_Y,
        "edge_east": EDGE_EAST,
        "edge_west": EDGE_WEST,
        "zones": {
            "lane": [EDGE_WEST - 6.0, 9.9, EDGE_EAST + 6.0, 12.6],
            "junction": [33.0, 9.0, 45.0, 15.0],
            "gate": [36.3, 14.5, 41.9, 17.2],
            "posts": [36.58, 17.2, 41.42, 18.1],
            "bridge": [36.0, 18.1, 42.0, 21.0],
            "apron": [APRON[0], APRON[1], APRON[0] + APRON[2], APRON[1] + APRON[3]],
        },
        "spots": spots,
    }
    spots[2]["long"] = True
    return data


def dump(data):
    """One point to a line, so that a diff of this file reads."""
    lines = ["{"]
    keys = [k for k in data if k != "spots"]
    for k in keys:
        lines.append('  %s: %s,' % (json.dumps(k), json.dumps(data[k], ensure_ascii=False)))
    lines.append('  "spots": [')
    for i, s in enumerate(data["spots"]):
        lines.append("    {")
        for k in s:
            if k in ("out_route", "in_route"):
                continue
            lines.append("      %s: %s," % (json.dumps(k), json.dumps(s[k])))
        for k in ("out_route", "in_route"):
            lines.append("      %s: [" % json.dumps(k))
            for j, p in enumerate(s[k]):
                lines.append("        %s%s" % (json.dumps(p, separators=(", ", ": ")), "," if j < len(s[k]) - 1 else ""))
            lines.append("      ]%s" % ("," if k == "out_route" else ""))
        lines.append("    }%s" % ("," if i < len(data["spots"]) - 1 else ""))
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    text = dump(make())
    json.loads(text)
    if "--print" in sys.argv:
        print(text)
    else:
        tmp = OUT + ".tmp"
        with open(tmp, "w") as f:
            f.write(text)
        os.replace(tmp, OUT)
        print("wrote", OUT, len(text), "bytes")
