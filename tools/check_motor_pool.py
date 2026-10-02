#!/usr/bin/env python3
"""Measures assets/data/motor_pool.json against the real map (round 15, task GATE).

What it checks (a failure is printed and the exit code is 1):
  - every route is sampled every 0.1 tile; the car's body (2.2 wide, 4.4 long, turned to the nose's heading) must lie
    in the allowed rectangles (`zones`) at every sample: its four corners and the middle of each side;
  - at the gate posts (y 17.2 to 18.1, x 36.58 to 41.42: the zone `posts`) the body stays between them;
  - no sample's body touches a solid tile of the map (the gate's own tiles, which stay shut for the dead, are let
    through: the opening is a picture), a prop the map keeps (a box of each object that is not ground paint), a piece
    of the streets' dressing that stands up, the deck's lattice face (but under the bridge) or a parked car;
  - the parked cars (2.2 x 4.4) stand inside the apron, an aisle of 3 tiles or more is left between the bays, and
    the bus (2.6 x 8.07) in the long spot stays in the aisle and clear of the other bays;
  - every spot has an out route and an in route; the out route starts at the spot, leaves forward and ends off the map's
    east edge; the in route starts at the west edge, ends at the spot, and its last leg is a reverse with the nose to the
    north; the headings are continuous (no jump over 25 degrees between points).
Options: --png <file> draws the apron with the routes (scratch picture), --quiet.
"""
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POOL = os.path.join(ROOT, "assets", "data", "motor_pool.json")
MAP = os.path.join(ROOT, "assets", "data", "map.json")
DRESS = os.path.join(ROOT, "assets", "data", "dressing.json")

CAR_L, CAR_W = 4.4, 2.2
BUS_L, BUS_W = 8.07, 2.6
STEP = 0.1
GROUND_KINDS = {"blood", "crack", "papers", "stain", "scorch", "spray", "trail", "manhole", "leaves", "treeShadow",
                "tracks", "drain", "court", "foursquare", "hopscotch", "lanes", "crosswalk", "mark", "paint", "puddle"}
SKIP_KINDS = {"walkway", "ladder", "bridge", "gatefloor", "apron", "roof", "awning", "tarp"}


def load(path):
    with open(path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------------------------------- geometry ----
def rect_corners(cx, cy, w, h, a):
    """Corners of a w x h rectangle (w along the heading a, radians) centred on (cx, cy)."""
    c, s = math.cos(a), math.sin(a)
    pts = []
    for fx, fy in ((w / 2, h / 2), (w / 2, -h / 2), (-w / 2, -h / 2), (-w / 2, h / 2)):
        pts.append((cx + fx * c - fy * s, cy + fx * s + fy * c))
    return pts


def edge_points(corners):
    out = list(corners)
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        out.append(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2))
    return out


def _axes(poly):
    axes = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        ex, ey = b[0] - a[0], b[1] - a[1]
        n = math.hypot(ex, ey)
        if n > 0:
            axes.append((-ey / n, ex / n))
    return axes


def overlap(p, q, margin=0.0):
    """Whether two convex polygons overlap (separating axis); `margin` shrinks the overlap that counts."""
    for ax, ay in _axes(p) + _axes(q):
        pa = [x * ax + y * ay for x, y in p]
        qa = [x * ax + y * ay for x, y in q]
        if max(pa) <= min(qa) + margin or max(qa) <= min(pa) + margin:
            return False
    return True


def in_rect(pt, r, slack=0.0):
    return r[0] - slack <= pt[0] <= r[2] + slack and r[1] - slack <= pt[1] <= r[3] + slack


def rect_poly(r):
    return [(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])]


# ------------------------------------------------------------------------------------------------------ routes ----
def unwrap_lerp(a, b, f):
    d = (b - a + 180.0) % 360.0 - 180.0
    return a + d * f


def sample(route, step=STEP):
    """[(x, y, heading_rad, reverse)] along the polyline, every `step` tiles."""
    out = []
    for i in range(1, len(route)):
        p0, p1 = route[i - 1], route[i]
        dx, dy = p1["x"] - p0["x"], p1["y"] - p0["y"]
        d = math.hypot(dx, dy)
        rev = bool(p1.get("rev", False))
        n = max(1, int(math.ceil(d / step)))
        for k in range(n + (1 if i == len(route) - 1 else 0)):
            f = k / n
            x, y = p0["x"] + dx * f, p0["y"] + dy * f
            if "h" in p0 and "h" in p1:
                h = math.radians(unwrap_lerp(p0["h"], p1["h"], f))
            else:
                h = math.atan2(dy, dx) + (math.pi if rev else 0.0)
            out.append((x, y, h, rev))
    return out


# ---------------------------------------------------------------------------------------------------- the map ----
class World:
    def __init__(self):
        self.map = load(MAP)
        self.W, self.H = self.map["W"], self.map["H"]
        self.solid = [(a or b) for a, b in zip(self.map["solidZ"], self.map["solidP"])]
        self.props = []        # [(name, polygon)]
        self.bridge = None
        for o in self.map["objects"]:
            k = o["kind"]
            if k == "bridge":
                self.bridge = (o["cx"] - o["w"] / 2, o["cx"] + o["w"] / 2)
            if k in GROUND_KINDS or k in SKIP_KINDS or o["layer"] <= 1:
                continue
            if o.get("segment") is not None:
                continue
            self.props.append(("%s %s" % (k, o["id"]), rect_corners(o["cx"], o["cy"], o["w"], o["h"], o["a"]), o))
        self.lamps = []
        d = load(DRESS)
        self.dress = []
        for i, p in enumerate(d["pieces"]):
            if p.get("flat") and "corpse" not in p["f"] and "tarp" not in p["f"]:
                continue
            self.dress.append(("dressing %d %s" % (i, p["f"]), rect_corners(p["x"], p["y"], p["w"], p["h"], math.radians(p.get("rot", 0)))))
        # the deck's lattice face under the north walkway (a gap for the bridge)
        self.lattice = []
        for o in self.map["objects"]:
            if o["kind"] == "walkway" and o["w"] >= o["h"]:
                x0, x1 = o["cx"] - o["w"] / 2, o["cx"] + o["w"] / 2
                y1 = o["cy"] + o["h"] / 2
                gap = self.bridge or (36.0, 42.0)
                self.lattice.append(("deck face", rect_poly((x0, y1 + 0.05, gap[0], y1 + 1.3))))
                self.lattice.append(("deck face", rect_poly((gap[1], y1 + 0.05, x1, y1 + 1.3))))

    def solid_hit(self, poly):
        """A solid tile the polygon covers (the gate's own tiles, x 36 to 41, rows 15 to 20, are let through)."""
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        for ty in range(max(0, math.floor(min(ys))), min(self.H, math.floor(max(ys)) + 1)):
            for tx in range(max(0, math.floor(min(xs))), min(self.W, math.floor(max(xs)) + 1)):
                if not self.solid[ty * self.W + tx]:
                    continue
                if 36 <= tx <= 41 and 15 <= ty <= 20:
                    continue
                if overlap(poly, rect_poly((tx, ty, tx + 1, ty + 1)), 0.02):
                    return (tx, ty)
        return None


# ------------------------------------------------------------------------------------------------------ checks ----
def run(png=None, quiet=False):
    pool = load(POOL)
    world = World()
    fails = []

    def fail(msg):
        fails.append(msg)

    zones = pool["zones"]
    allowed = [zones[k] for k in zones]
    spots = pool["spots"]
    if not spots or len(spots) > 4:
        fail("a pool has one to four spots, this has %d" % len(spots))

    # the parked cars
    parked = {}
    for s in spots:
        parked[s["id"]] = rect_corners(s["at"][0], s["at"][1], CAR_L, CAR_W, -math.pi / 2)
    ap = zones["apron"]
    for s in spots:
        for c in edge_points(parked[s["id"]]):
            if not in_rect(c, ap, 0.001):
                fail("spot %d: the parked car leaves the apron at %s" % (s["id"], tuple(round(v, 2) for v in c)))
        hit = world.solid_hit(parked[s["id"]])
        if hit:
            fail("spot %d: the parked car stands on solid tile %s" % (s["id"], hit))
        for name, poly, *_ in world.props + world.dress + world.lattice:
            if overlap(parked[s["id"]], poly, 0.02):
                fail("spot %d: the parked car overlaps %s" % (s["id"], name))
    ids = [s["id"] for s in spots]
    for i in ids:
        for j in ids:
            if i < j and overlap(parked[i], parked[j], 0.01):
                fail("spots %d and %d overlap" % (i, j))
    # the aisle: the narrowest gap between the side bays (the cars beside it)
    side = [s for s in spots if not s.get("long")]
    if len(side) >= 2:
        west = max(s["at"][0] + CAR_W / 2 for s in side if s["at"][0] < pool["gate"]["x"])
        east = min(s["at"][0] - CAR_W / 2 for s in side if s["at"][0] > pool["gate"]["x"])
        if east - west < 3.0 - 1e-6:
            fail("the aisle is %.2f wide, 3.0 wanted" % (east - west))
    # the bus in the long spot
    for s in spots:
        if s.get("long"):
            bx, by = s["at"][0], s["at"][1] + float(s.get("long_dy", 0.0))
            bus = rect_corners(bx, by, BUS_L, BUS_W, -math.pi / 2)
            for o in spots:
                if o["id"] != s["id"] and overlap(bus, parked[o["id"]], 0.01):
                    fail("the bus in spot %d overlaps the car in spot %d" % (s["id"], o["id"]))
            hit = world.solid_hit(bus)
            if hit:
                fail("the bus in spot %d stands on solid tile %s" % (s["id"], hit))

    worst = {}
    samples_all = {}
    for s in spots:
        for which in ("out", "in"):
            route = s["%s_route" % which]
            label = "spot %d %s" % (s["id"], which)
            if len(route) < 2:
                fail("%s: a route needs two points" % label)
                continue
            if which == "out":
                if abs(route[0]["x"] - s["at"][0]) > 0.01 or abs(route[0]["y"] - s["at"][1]) > 0.01:
                    fail("%s starts at (%.2f, %.2f), not at the spot" % (label, route[0]["x"], route[0]["y"]))
                if abs(route[-1]["x"] - pool["edge_east"]) > 0.01:
                    fail("%s does not end at the east edge" % label)
                if any(p.get("rev") for p in route):
                    fail("%s reverses: a car leaves forward" % label)
            else:
                if abs(route[0]["x"] - pool["edge_west"]) > 0.01:
                    fail("%s does not start at the west edge" % label)
                if abs(route[-1]["x"] - s["at"][0]) > 0.01 or abs(route[-1]["y"] - s["at"][1]) > 0.01:
                    fail("%s ends at (%.2f, %.2f), not at the spot" % (label, route[-1]["x"], route[-1]["y"]))
                if not route[-1].get("rev"):
                    fail("%s: the last leg must be a reverse" % label)
                if abs(((route[-1].get("h", 0) - 270.0 + 180.0) % 360.0) - 180.0) > 0.5:
                    fail("%s ends with the nose at %s, 270 (north) wanted" % (label, route[-1].get("h")))
                if not any(p.get("rev") for p in route[:-1]) and len(route) > 2:
                    fail("%s: no reversing stretch before the end" % label)
            # no jumps in the heading
            for i in range(1, len(route)):
                if "h" in route[i] and "h" in route[i - 1]:
                    d = abs((route[i]["h"] - route[i - 1]["h"] + 180.0) % 360.0 - 180.0)
                    if d > 25.0:
                        fail("%s: the heading jumps %.0f degrees at point %d" % (label, d, i))
            sm = sample(route)
            samples_all[(s["id"], which)] = sm
            for (x, y, h, rev) in sm:
                body = rect_corners(x, y, CAR_L, CAR_W, h)
                pts = edge_points(body)
                key = (s["id"], which)
                for c in pts:
                    ok = any(in_rect(c, z, 0.001) for z in allowed)
                    if not ok:
                        worst.setdefault((label, "zone"), (x, y, c))
                hit = world.solid_hit(body)
                if hit:
                    worst.setdefault((label, "solid %s" % (hit,)), (x, y, hit))
                for name, poly, *_ in world.props + world.dress + world.lattice:
                    if overlap(body, poly, 0.02):
                        worst.setdefault((label, name), (x, y, name))
                for o in ids:
                    if o != s["id"] and overlap(body, parked[o], 0.02):
                        worst.setdefault((label, "parked car in spot %d" % o), (x, y, o))
    for (label, what), (x, y, extra) in sorted(worst.items(), key=lambda kv: str(kv[0])):
        fail("%s: %s at the car (%.2f, %.2f) %s" % (label, what, x, y, extra if not isinstance(extra, str) else ""))
    if png:
        draw(png, pool, world, samples_all, parked)
    if not quiet:
        print("%d spots, %d routes, %d problems" % (len(spots), 2 * len(spots), len(fails)))
        for f in fails[:60]:
            print("  FAIL", f)
        if len(fails) > 60:
            print("  ... and %d more" % (len(fails) - 60))
    return fails


# ------------------------------------------------------------------------------------------------------ drawing ----
def draw(path, pool, world, samples, parked):
    from PIL import Image, ImageDraw
    X0, Y0, X1, Y1, PX = 30.0, 8.0, 48.0, 36.0, 44
    im = Image.new("RGB", (int((X1 - X0) * PX), int((Y1 - Y0) * PX)), (66, 64, 60))
    d = ImageDraw.Draw(im, "RGBA")

    def P(x, y):
        return ((x - X0) * PX, (y - Y0) * PX)

    def poly(pts, fill=None, outline=None, width=1):
        d.polygon([P(*p) for p in pts], fill=fill, outline=outline, width=width)

    z = pool["zones"]
    # the street, the wall, the apron
    poly(rect_poly((X0, 6, X1, 13)), fill=(54, 54, 56))
    poly(rect_poly((X0, 13, X1, 15)), fill=(120, 116, 108))
    poly(rect_poly((X0, 15, X1, 18)), fill=(90, 86, 80))
    poly(rect_poly((X0, 18, X1, Y1)), fill=(84, 78, 72))
    poly(rect_poly((z["apron"][0], z["apron"][1], z["apron"][2], z["apron"][3])), fill=(110, 106, 100, 120), outline=(255, 255, 255, 120))
    poly(rect_poly(z["gate"]), outline=(80, 200, 255, 160))
    poly(rect_poly(z["lane"]), outline=(255, 255, 0, 90))
    # the wall pieces and the posts
    poly(rect_poly((32.58, 15.9, 36.25, 18.35)), fill=(150, 120, 80))
    poly(rect_poly((41.93, 15.0, 53.2, 18.84)), fill=(220, 180, 40))
    poly(rect_poly((35.97, 17.3, 36.58, 18.0)), fill=(170, 170, 160))
    poly(rect_poly((41.42, 17.3, 42.03, 18.0)), fill=(170, 170, 160))
    for name, pg in world.lattice:
        poly(pg, fill=(150, 100, 40, 170))
    poly(rect_poly((36.0, 18.0, 42.0, 19.55)), fill=(200, 150, 90, 150))
    for name, pg, *_ in world.props:
        xs = [p[0] for p in pg]
        ys = [p[1] for p in pg]
        if X0 < sum(xs) / 4 < X1 and Y0 < sum(ys) / 4 < Y1:
            poly(pg, fill=(200, 60, 60, 100), outline=(255, 120, 120))
    for name, pg in world.dress:
        xs = [p[0] for p in pg]
        ys = [p[1] for p in pg]
        if X0 < sum(xs) / 4 < X1 and Y0 < sum(ys) / 4 < Y1:
            poly(pg, fill=(200, 100, 60, 100), outline=(255, 160, 100))
    for sid, pg in parked.items():
        poly(pg, fill=(60, 120, 200, 110), outline=(120, 180, 255), width=2)
    colors = {"out": (80, 255, 120), "in": (255, 120, 220)}
    for (sid, which), sm in samples.items():
        pts = [P(x, y) for x, y, h, r in sm]
        d.line(pts, fill=colors[which] + (200,), width=2)
        # the car's outline now and then
        last = -9
        for i, (x, y, h, r) in enumerate(sm):
            if X0 < x < X1 and Y0 < y < Y1 and i - last >= 12 and (which == "in" or sid == 0):
                last = i
                col = (255, 255, 255, 70) if not r else (255, 200, 80, 90)
                body = rect_corners(x, y, CAR_L, CAR_W, h)
                poly(body, outline=col)
                nx, ny = x + math.cos(h) * 2.2, y + math.sin(h) * 2.2
                d.line([P(x, y), P(nx, ny)], fill=col, width=1)
    im.save(path)


if __name__ == "__main__":
    png = None
    if "--png" in sys.argv:
        png = sys.argv[sys.argv.index("--png") + 1]
    fails = run(png, "--quiet" in sys.argv)
    sys.exit(1 if fails else 0)
