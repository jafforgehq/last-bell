#!/usr/bin/env python3
"""Makes the vehicle gate, the deck bridge, the clear lane and the motor pool apron (round 15, task GATE). Idempotent.

  python3 tools/edit_gate.py            data and pictures
  python3 tools/edit_gate.py --data     only assets/data/map.json and dressing.json (read, change, write in a moment: other
                                        builders edit these files too, so it only touches what it owns)
  python3 tools/edit_gate.py --art      only the pictures in assets/objects

What it does to the map (the numbers are in the tables below):
  - the walkway (object 155, planks only: its tiles do not change) loses the planks over x 36 to 42; they become their own
    object, the `bridge` (kind "bridge", layer 4: drawn over the cars, which are in z 3), with rails and a dark gap under it;
  - the gate's four damage pictures (165_gate_s0..s2) are cut into two posts and two leaves (scripts/render/gate_node.gd slides
    the leaves apart; the posts stay);
  - three wrecks that stood in the eastbound lane move to the north lane (with their solid tiles, scorch and fire light), a
    body on the road moves to the pavement, and every prop the street's dresser put in the lane or the junction is shifted out
    of the way (assets/data/dressing.json is NOT made again: its random seeds would reshuffle the whole street);
  - the decorative pickup (116) and the tyre mark (115) in the yard go (their solid tiles too), the two tents move a step
    west, off the apron; the apron gets a ground picture (gate_apron.png: the dropped kerb, the gate's floor, the slab, the bay
    lines, the tyre tracks the routes of assets/data/motor_pool.json leave).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True      # (no tools/__pycache__ for the one import below)
sys.path.insert(0, HERE)
import check_motor_pool as cm  # noqa: E402  (the same geometry helpers)

ROOT = os.path.dirname(HERE)
MAP = os.path.join(ROOT, "assets", "data", "map.json")
DRESS = os.path.join(ROOT, "assets", "data", "dressing.json")
POOL = os.path.join(ROOT, "assets", "data", "motor_pool.json")
OBJ = os.path.join(ROOT, "assets", "objects")
RES = "res://assets/objects/"

# ---- the numbers ----------------------------------------------------------------------------------------------------
# where the bridge is (the part of the walkway over the gate): x 36 to 42 (the gate segment's own span)
BRIDGE_X0, BRIDGE_X1 = 36.0, 42.0
WALK_PX = 96.0                       # the walkway's picture: pixels to the tile
WALK_FILE = "155_walkway_10"          # the piece of the walkway the bridge is cut from (x 34.69375, 14.76 tiles wide)
# the gate pictures: where the cuts are, in pixels of the 729 wide picture (post | left leaf | right leaf | post)
GATE_CUTS = (75, 343, 612)
GATE_STATES = (0, 1, 2)               # the damage pictures that have leaves (the last, the wreck, is one piece)
# wrecks that go to the north lane: object id -> (x, y); the scorch under the burning one and its fire light go with it
# (the north lane's free stretches are between the lots' mouths: x 22 to 25, 36 to 42 and 56.5 to 66, tests/test_lots_data.gd)
WRECKS = {203: (24.0, 7.7), 205: (58.7, 7.9), 207: (64.0, 7.6)}
SCORCH = {216: (24.0, 7.7)}
FIRE_LIGHT = (24.0, 7.5)          # the burning car's big fire light goes with it
BODIES = {275: (55.5, 13.9), 276: (55.8, 14.0)}     # a corpse and its blood: onto the pavement
YARD_REMOVE = (116, 115)              # the decorative pickup and the old tyre mark
TENTS = {143: (32.2, 26.8), 144: (32.2, 29.6)}    # off the apron and off the watchtower's lot (30 to 33, 21 to 24), on the court's east margin
# what the street keeps clear (tiles): the eastbound lane and the turn at the gate
KEEP_CLEAR = [(-12.0, 9.9, 96.0, 12.6), (33.0, 9.0, 45.0, 15.0)]
SOUTH_LIMIT = 14.95                   # the pavement ends at the compound's wall
NORTH_LIMIT = 6.2                     # the north kerb
# the apron picture
APRON_PX = 64.0
APRON_BOX = (33.4, 12.8, 43.0, 34.8)
APRON_FILE = "gate_apron"
APRON_ID = 394
BRIDGE_ID = 393


# ---- files ----------------------------------------------------------------------------------------------------------
def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, data):
    text = json.dumps(data, separators=(",", ":"), ensure_ascii=False)
    with open(path) as f:
        if f.read() == text:
            return False      # nothing to change: the file is not touched (others edit it too)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def save_dressing(path, data):
    """assets/data/dressing.json in the layout tools/make_dressing.py writes (one piece to a line), so that a diff reads."""
    pieces = data["pieces"]
    text = "{\n \"version\": %s,\n \"_doc\": %s,\n \"pieces\": [\n" % (json.dumps(data["version"]), json.dumps(data["_doc"]))
    for i, pc in enumerate(pieces):
        text += "  " + json.dumps(pc, separators=(", ", ": ")) + (",\n" if i < len(pieces) - 1 else "\n")
    text += " ]\n}\n"
    with open(path) as f:
        if f.read() == text:
            return False
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def obj_by_id(m, oid):
    for o in m["objects"]:
        if o["id"] == oid:
            return o
    return None


def footprint_tiles(o, shrink=0.04):
    """Tiles whose middle is inside the object's rotated rectangle (what the map makes solid for a wreck)."""
    a = float(o["a"])
    c, s = math.cos(-a), math.sin(-a)
    out = []
    r = int(max(o["w"], o["h"])) + 2
    for ty in range(int(o["cy"]) - r, int(o["cy"]) + r + 1):
        for tx in range(int(o["cx"]) - r, int(o["cx"]) + r + 1):
            dx, dy = tx + 0.5 - o["cx"], ty + 0.5 - o["cy"]
            lx, ly = dx * c - dy * s, dx * s + dy * c
            if abs(lx) <= o["w"] / 2 and abs(ly) <= o["h"] / 2 - shrink:
                out.append((tx, ty))
    return out


def set_tiles(m, tiles, value):
    W = m["W"]
    for tx, ty in tiles:
        if 0 <= tx < W and 0 <= ty < m["H"]:
            m["solidZ"][ty * W + tx] = value
            m["solidP"][ty * W + tx] = value


def move_object(m, o, x, y):
    """Moves an object and its pictures (and its solid tiles, when it was solid on the ground: wrecks are, in the tiles)."""
    dx, dy = x - o["cx"], y - o["cy"]
    if abs(dx) < 1e-9 and abs(dy) < 1e-9:
        return False
    o["cx"], o["cy"] = x, y
    for p in o.get("pieces", []):
        p["x"] = round(p["x"] + dx, 6)
        p["y"] = round(p["y"] + dy, 6)
    for st in o.get("states", []) or []:
        for p in st:
            p["x"] = round(p["x"] + dx, 6)
            p["y"] = round(p["y"] + dy, 6)
    return True


# ---- the data -------------------------------------------------------------------------------------------------------
def edit_map(m, log):
    objs = m["objects"]
    W = m["W"]
    # the wrecks: their solid tiles go to the north lane with them
    for oid, (x, y) in WRECKS.items():
        o = obj_by_id(m, oid)
        if o is None:
            continue
        if abs(o["cx"] - x) < 1e-6 and abs(o["cy"] - y) < 1e-6:
            continue
        old = footprint_tiles(o)
        set_tiles(m, [t for t in old if m["solidZ"][t[1] * W + t[0]]], 0)
        move_object(m, o, x, y)
        new = footprint_tiles(o)
        clash = [t for t in new if m["solidZ"][t[1] * W + t[0]]]
        if clash:
            log("wreck %d: tiles already solid at the new place %s" % (oid, clash))
        set_tiles(m, new, 1)
        log("wreck %d moved to (%.1f, %.1f)" % (oid, x, y))
    for oid, (x, y) in {**SCORCH, **BODIES}.items():
        o = obj_by_id(m, oid)
        if o is not None and move_object(m, o, x, y):
            log("object %d moved to (%.1f, %.1f)" % (oid, x, y))
    for l in m["lights"]:
        if l.get("fire") and l.get("big") and (abs(l["x"] - FIRE_LIGHT[0]) > 1e-6 or abs(l["y"] - FIRE_LIGHT[1]) > 1e-6):
            l["x"], l["y"] = FIRE_LIGHT
            log("the burning car's fire light moved")
    # the yard: no parked pickup, no old tyre mark
    for oid in YARD_REMOVE:
        o = obj_by_id(m, oid)
        if o is None:
            continue
        if o["solid"]:
            set_tiles(m, [t for t in footprint_tiles(o, 0.0) if m["solidZ"][t[1] * W + t[0]]], 0)
        objs.remove(o)
        log("object %d (%s) removed" % (oid, o["kind"]))
    for oid, (x, y) in TENTS.items():
        o = obj_by_id(m, oid)
        if o is not None and move_object(m, o, x, y):
            log("tent %d moved to (%.1f, %.1f)" % (oid, x, y))
    # the walkway: the planks over the gate are the bridge
    walk = obj_by_id(m, 155)
    names = [p["file"].split("/")[-1][:-4] for p in walk["pieces"]]
    if WALK_FILE in names:
        i = names.index(WALK_FILE)
        p = walk["pieces"][i]
        cut0 = int(round((BRIDGE_X0 - p["x"]) * WALK_PX))
        cut1 = int(round((BRIDGE_X1 - p["x"]) * WALK_PX))
        total = int(round(p["w"] * WALK_PX))
        xa = p["x"]
        xb = xa + cut0 / WALK_PX
        xc = xa + cut1 / WALK_PX
        left = {"file": RES + WALK_FILE + "a.png", "x": xa, "y": p["y"], "w": cut0 / WALK_PX, "h": p["h"]}
        right = {"file": RES + WALK_FILE + "b.png", "x": xc, "y": p["y"], "w": (total - cut1) / WALK_PX, "h": p["h"]}
        walk["pieces"][i:i + 1] = [left, right]
        log("the walkway's middle piece is cut at x %.3f and %.3f" % (xb, xc))
        bridge_piece = {"x": xb, "y": p["y"], "w": (cut1 - cut0) / WALK_PX, "h": p["h"], "cut": (cut0, cut1)}
    else:
        bridge_piece = None
    if obj_by_id(m, BRIDGE_ID) is None and bridge_piece is not None:
        ex = BRIDGE_EXTRA_ROWS / WALK_PX
        b = {"id": BRIDGE_ID, "kind": "bridge", "layer": 4, "order": BRIDGE_ID,
             "cx": (BRIDGE_X0 + BRIDGE_X1) / 2, "cy": walk["cy"], "w": BRIDGE_X1 - BRIDGE_X0, "h": walk["h"], "a": 0, "solid": False,
             "pieces": [{"file": RES + "155_bridge.png", "x": bridge_piece["x"], "y": bridge_piece["y"], "w": bridge_piece["w"], "h": bridge_piece["h"] + ex}]}
        objs.insert(objs.index(walk) + 1, b)
        log("the bridge is object %d" % BRIDGE_ID)
    # the apron's ground picture, where the old tyre mark was drawn (over the court's and the four-square's paint)
    x0, y0, x1, y1 = APRON_BOX
    piece = {"file": RES + APRON_FILE + ".png", "x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0}
    a = obj_by_id(m, APRON_ID)
    if a is None:
        a = {"id": APRON_ID, "kind": "apron", "layer": 1, "order": APRON_ID, "cx": 0, "cy": 0, "w": 0, "h": 0, "a": 0, "solid": False, "pieces": []}
        # after the paint of the court, the four-square and the hopscotch (objects 96 to 99), before the cracks and stains
        idx = len(objs)
        for i, o in enumerate(objs):
            if o["id"] == 100:
                idx = i
                break
        objs.insert(idx, a)
        log("the apron's ground is object %d" % APRON_ID)
    a.update({"cx": (x0 + x1) / 2, "cy": (y0 + y1) / 2, "w": x1 - x0, "h": y1 - y0, "pieces": [piece]})


BRIDGE_EXTRA_ROWS = 56               # pixels the bridge's picture reaches below the walkway's own (its beam and shadow)


def piece_poly(p):
    return cm.rect_corners(p["x"], p["y"], p["w"], p["h"], math.radians(p.get("rot", 0)))


def clear_of_zones(poly):
    return not any(cm.overlap(poly, cm.rect_poly(z), 0.0) for z in KEEP_CLEAR)


# what tests/test_dressing.gd keeps true of every piece (the street's dresser's own rules): replicated here so that a piece moved
# out of the lane lands on ground that is all right
STREET_TERRAIN = (1, 2, 13)
OVERLAP_MAX = 0.35
CORE = {"corpse": 0.75}
GATE_FRONT = (36.0, 12.0, 42.0, 15.0)
DRESS_GROUND_KINDS = ("leaves", "treeShadow", "crack", "tufts", "blood", "papers", "stain", "trail", "spray", "scorch", "tracks")


class DressRules:
    def __init__(self, m, d):
        self.m = m
        self.W, self.H = m["W"], m["H"]
        lots = load(os.path.join(ROOT, "assets", "data", "lots.json"))
        self.rects = []
        for mo in lots["mouths"]:
            r = mo["rect"]
            self.rects.append((r[0], r[1], r[2] + 1.0, r[3] + 1.0))
            px, py = mo["post"]["pos"]
            self.rects.append((px - 0.5, py - 0.5, px + 0.5, py + 0.5))
        for pl in lots["plots"]:
            c, sz, wk = pl["pos"], pl["size"], pl["work"]
            self.rects.append((c[0] - sz[0] / 2, c[1] - sz[1] / 2, c[0] + sz[0] / 2, c[1] + sz[1] / 2))
            self.rects.append((wk[0] - 0.5, wk[1] - 0.5, wk[0] + 0.5, wk[1] + 0.5))
        self.rects.append(GATE_FRONT)
        self.props = [o for o in m["objects"] if o["kind"] not in DRESS_GROUND_KINDS]
        self.trees = m["trees"]

    @staticmethod
    def box(p, core=False):
        r = math.radians(p.get("rot", 0.0))
        w = abs(math.cos(r)) * p["w"] + abs(math.sin(r)) * p["h"]
        h = abs(math.sin(r)) * p["w"] + abs(math.cos(r)) * p["h"]
        if core:
            k = CORE.get(p["f"].split("_")[1], 1.0)
            w *= k
            h *= k
        return (p["x"] - w / 2, p["y"] - h / 2, p["x"] + w / 2, p["y"] + h / 2)

    def ground_ok(self, p):
        b = self.box(p)
        for ty in range(math.floor(b[1] + 0.02), math.floor(b[3] - 0.02) + 1):
            for tx in range(math.floor(b[0] + 0.02), math.floor(b[2] - 0.02) + 1):
                if not (0 <= tx < self.W and 0 <= ty < self.H):
                    return False
                i = ty * self.W + tx
                if self.m["terrain"][i] not in STREET_TERRAIN or self.m["solidZ"][i] or self.m["solidP"][i]:
                    return False
        return True

    def footprint_ok(self, p):
        b = self.box(p)
        for r in self.rects:
            if b[0] < r[2] and b[2] > r[0] and b[1] < r[3] and b[3] > r[1]:
                return False
        return True

    def props_ok(self, p):
        b = self.box(p, True)
        y = b[1]
        while y <= b[3] + 0.001:
            x = b[0]
            while x <= b[2] + 0.001:
                for o in self.props:
                    if o["kind"] == "lamppost":
                        hit = abs(x - o["cx"]) <= 0.5 and abs(y - o["cy"]) <= 0.5
                    elif o["kind"] == "awning":
                        hit = abs(x - o["cx"]) <= o["w"] / 2 and abs(y - o["cy"]) <= o["h"] / 2
                    else:
                        c, s = math.cos(-o["a"]), math.sin(-o["a"])
                        dx, dy = x - o["cx"], y - o["cy"]
                        hit = abs(dx * c - dy * s) <= o["w"] / 2 and abs(dx * s + dy * c) <= o["h"] / 2
                    if hit:
                        return False
                x += 0.25
            y += 0.25
        for t in self.trees:
            if b[0] <= t["x"] <= b[2] and b[1] <= t["y"] <= b[3]:
                return False
        return True

    def overlap_ok(self, p, others):
        a = self.box(p, True)
        for q in others:
            if q is p:
                continue
            c = self.box(q, True)
            iw = min(a[2], c[2]) - max(a[0], c[0])
            ih = min(a[3], c[3]) - max(a[1], c[1])
            if iw <= 0 or ih <= 0:
                continue
            small = min((a[2] - a[0]) * (a[3] - a[1]), (c[2] - c[0]) * (c[3] - c[1]))
            if (iw * ih / small if small > 0 else 1.0) > OVERLAP_MAX:
                return False
        return True

    def ok(self, p, others):
        return self.ground_ok(p) and self.footprint_ok(p) and self.props_ok(p) and self.overlap_ok(p, others)


def needs_lane(p):
    """Whether a piece must keep out of the lane and the turn: what stands up (and a body or a tarp lying down)."""
    return not p.get("flat") or "corpse" in p["f"] or "tarp" in p["f"]


def edit_dressing(d, m, log):
    """Every piece of the street's dressing that stands in the lane or the turn, or that is on something now (a wreck that moved, a
    prop that went), goes to the nearest place that obeys the dresser's own rules (tests/test_dressing.gd)."""
    rules = DressRules(m, d)
    pieces = d["pieces"]
    n = 0
    for p in pieces:
        bad_lane = needs_lane(p) and not clear_of_zones(piece_poly(p))
        if not bad_lane and rules.ok(p, pieces):
            continue
        old = (p["x"], p["y"])
        cands = []
        for ix in range(-40, 41):
            for iy in range(-40, 41):
                dx, dy = ix * 0.25, iy * 0.25
                cands.append((dx * dx + dy * dy, dx, dy))
        cands.sort()
        done = False
        for _, dx, dy in cands:
            q = dict(p)
            q["x"], q["y"] = round(old[0] + dx, 3), round(old[1] + dy, 3)
            if needs_lane(q) and not clear_of_zones(piece_poly(q)):
                continue
            if not rules.ok(q, [x for x in pieces if x is not p]):
                continue
            p["x"], p["y"] = q["x"], q["y"]
            if "sort" in p:
                p["sort"] = round(p["sort"] + dy, 3)
            done = True
            break
        log("dressing %s moved from (%.2f, %.2f) to (%.2f, %.2f)%s" % (p["f"], old[0], old[1], p["x"], p["y"], "" if done else "  (NOT placed)"))
        n += 1
    return n


# ---- the pictures ---------------------------------------------------------------------------------------------------
def smooth_noise(h, w, seed, scales=(32, 12, 5), weights=(0.5, 0.3, 0.2)):
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), float)
    for sc, wt in zip(scales, weights):
        small = rng.random((max(2, h // sc + 2), max(2, w // sc + 2)))
        im = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += wt * np.asarray(im, float) / 255.0
    return out


def cut_walkway(log):
    """The walkway's middle piece into a left part, the bridge's planks and a right part."""
    src = Image.open(os.path.join(OBJ, WALK_FILE + ".png")).convert("RGBA")
    # where the cuts are (the piece of the original walkway that carries the middle starts at x 34.69375)
    x_orig = 34.69375
    cut0 = int(round((BRIDGE_X0 - x_orig) * WALK_PX))
    cut1 = int(round((BRIDGE_X1 - x_orig) * WALK_PX))
    src.crop((0, 0, cut0, src.height)).save(os.path.join(OBJ, WALK_FILE + "a.png"))
    src.crop((cut1, 0, src.width, src.height)).save(os.path.join(OBJ, WALK_FILE + "b.png"))
    planks = src.crop((cut0, 0, cut1, src.height))
    make_bridge(planks).save(os.path.join(OBJ, "155_bridge.png"))
    log("walkway pieces and the bridge written (cuts at %d and %d px)" % (cut0, cut1))


def make_bridge(planks):
    """The bridge: the planks (cut from the walkway), a steel handrail on the south edge with posts, the beam under the edge and
    a soft shadow on the ground under it, over the dark gap where the cars go."""
    w = planks.width
    h0 = planks.height
    ex = BRIDGE_EXTRA_ROWS
    H = h0 + ex
    out = Image.new("RGBA", (w, H), (0, 0, 0, 0))
    out.alpha_composite(planks, (0, 0))
    a = np.array(out).astype(float)
    rng = np.random.default_rng(393)
    # rows 150 to the end of the planks' picture hold the old rail and its shadow: paint the new south edge over them
    rail_top = 142
    beam_top, beam_bot = 154, 176
    # the planks run on to the beam: fill the old shadow band with plank colour first
    band = a[rail_top - 12:rail_top - 4, :, :].copy()
    for y in range(rail_top - 4, beam_top):
        a[y, :, :] = band[(y - rail_top + 4) % band.shape[0], :, :]
    a[rail_top - 4:beam_top, :, 3] = 255
    img = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(img, "RGBA")
    # the beam under the edge: dark wood with a lighter top
    d.rectangle((0, beam_top, w, beam_bot), fill=(86, 60, 38, 255))
    d.rectangle((0, beam_top, w, beam_top + 3), fill=(120, 88, 56, 255))
    d.rectangle((0, beam_top + 4, w, beam_top + 5), fill=(40, 28, 20, 255))
    d.rectangle((0, beam_bot - 3, w, beam_bot), fill=(46, 32, 22, 255))
    for x in range(14, w, 38):
        d.line((x, beam_top + 8, x + rng.integers(-3, 4), beam_bot - 5), fill=(70, 48, 30, 120), width=1)
    # steel brackets under the beam at the two ends and the middle
    for bx in (0, w // 2 - 6, w - 12):
        d.rectangle((bx, beam_top - 2, bx + 12, beam_bot + 6), fill=(58, 60, 64, 255), outline=(26, 26, 28, 255))
        d.ellipse((bx + 3, beam_top + 5, bx + 8, beam_top + 10), fill=(150, 152, 156, 255))
    # the handrail: a steel rail along the south edge, posts every 1.5 tiles, a dark line under it
    ry = rail_top
    d.rectangle((0, ry + 2, w, ry + 9), fill=(34, 36, 40, 255))
    d.rectangle((0, ry, w, ry + 5), fill=(142, 146, 152, 255))
    d.rectangle((0, ry + 4, w, ry + 5), fill=(98, 102, 108, 255))
    d.rectangle((0, ry, w, ry + 1), fill=(200, 204, 210, 255))
    for px in range(0, w + 1, 144):
        x = min(max(px, 6), w - 6)
        d.ellipse((x - 7, ry - 3, x + 7, ry + 11), fill=(48, 50, 54, 255), outline=(20, 20, 22, 255))
        d.ellipse((x - 3, ry, x + 3, ry + 6), fill=(170, 174, 180, 255))
    # the north edge (against the gate): a low toe rail
    d.rectangle((0, 12, w, 14), fill=(60, 44, 30, 255))
    # the joints with the walkway's own planks at the two ends
    for x in (0, w - 1):
        d.line((x, 6, x, beam_top), fill=(40, 28, 20, 255), width=2)
    # the soft shadow it throws on the dark floor under it
    arr = np.array(img).astype(float)
    for y in range(beam_bot + 1, H):
        t = (y - beam_bot) / float(H - beam_bot)
        al = 150.0 * (1.0 - t) ** 1.6
        arr[y, :, :3] = 0.0
        arr[y, :, 3] = al
    # the shadow fades at the sides
    for x in range(0, 20):
        arr[beam_bot + 1:, x, 3] *= x / 20.0
        arr[beam_bot + 1:, w - 1 - x, 3] *= x / 20.0
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def cut_gate(log):
    """Each damage picture with leaves is cut into a left post, two leaves and a right post (the columns GATE_CUTS)."""
    a, m, b = GATE_CUTS
    for s in GATE_STATES:
        src = Image.open(os.path.join(OBJ, "165_gate_s%d.png" % s)).convert("RGBA")
        w, h = src.size
        pieces = {"pl": (0, a), "l": (a, m), "r": (m, b), "pr": (b, w)}
        for name, (x0, x1) in pieces.items():
            src.crop((x0, 0, x1, h)).save(os.path.join(OBJ, "165_gate_s%d_%s.png" % (s, name)))
    log("the gate's pictures are cut in four (columns %s)" % (GATE_CUTS,))


def make_apron(log):
    """The ground picture of the gate and the motor pool: the dropped kerb over the pavement, the gate's floor (dark under the
    bridge), the apron's slab with its joints, the bay lines, and the tyre tracks the routes leave."""
    X0, Y0, X1, Y1 = APRON_BOX
    PX = APRON_PX
    W, H = int(round((X1 - X0) * PX)), int(round((Y1 - Y0) * PX))
    pool = load(POOL)
    zap = pool["zones"]["apron"]            # x0, y0, x1, y1 of the apron
    aisle_x = float(pool["gate"]["aisle_x"])
    gate_x0, gate_x1 = BRIDGE_X0, BRIDGE_X1
    yy, xx = np.mgrid[0:H, 0:W]
    X = X0 + (xx + 0.5) / PX
    Y = Y0 + (yy + 0.5) / PX
    rng = np.random.default_rng(15)
    n1 = smooth_noise(H, W, 1)
    n2 = smooth_noise(H, W, 2, scales=(6, 3, 2), weights=(0.5, 0.3, 0.2))

    def smooth(v, a, b):
        t = np.clip((v - a) / (b - a), 0.0, 1.0)
        return t * t * (3 - 2 * t)

    asphalt = np.array([70.0, 72.0, 77.0])
    throat = np.array([104.0, 101.0, 95.0])
    slab = np.array([122.0, 118.0, 110.0])
    # the colour by where it is: asphalt over the pavement, the gate's concrete, the slab
    k_throat = smooth(Y, 14.95, 15.25)[..., None]
    k_slab = smooth(Y, 20.7, 21.4)[..., None]
    col = asphalt * (1 - k_throat) + throat * k_throat
    col = col * (1 - k_slab) + slab * k_slab
    # dark under the bridge
    shade = 1.0 - 0.42 * smooth(Y, 17.9, 18.4) * (1 - smooth(Y, 20.6, 21.3))
    col = col * shade[..., None]
    col = col + ((n1 - 0.5) * 14.0 + (n2 - 0.5) * 8.0)[..., None]
    # the slab's expansion joints: a grid of about 3.8 tiles
    joint = np.zeros((H, W))
    for jy in (24.9, 28.7, 32.5):
        joint = np.maximum(joint, (np.abs(Y - jy) < 0.025).astype(float))
    for jx in (aisle_x,):
        joint = np.maximum(joint, ((np.abs(X - jx) < 0.025) & (Y > 20.9)).astype(float))
    joint *= (Y > 20.9)
    col = col * (1 - 0.22 * joint[..., None])
    # alpha: the driveway over the pavement, the gate's floor, the apron slab; crisp, a little ragged at the edges
    edge = (n2 - 0.5) * 0.08
    in_gate = smooth(X + edge, gate_x0 - 0.04, gate_x0 + 0.04) * (1 - smooth(X + edge, gate_x1 - 0.04, gate_x1 + 0.04))
    a_gate = in_gate * smooth(Y, 12.9, 13.0) * (1 - smooth(Y, 20.9, 21.3))
    a_slab = smooth(X + edge, zap[0], zap[0] + 0.12) * (1 - smooth(X + edge, zap[2] - 0.12, zap[2])) * smooth(Y, 20.6, 21.0) * (1 - smooth(Y + edge * 3, zap[3] - 0.5, zap[3]))
    alpha = np.maximum(a_gate, a_slab)
    # the dropped kerb: a light ramp edge on each side of the driveway where it crosses the pavement, and a gutter line
    for cx in (gate_x0, gate_x1):
        side = (np.abs(X - cx) < 0.05) & (Y > 13.0) & (Y < 15.0)
        col[side] = col[side] * 0.5 + np.array([36.0, 36.0, 38.0]) * 0.5
    for sx in (-1, 1):
        cx = gate_x0 if sx < 0 else gate_x1
        wing = (np.abs(X - cx) < 0.34) & (Y > 12.9) & (Y < 13.3) & ((np.abs(X - cx) + (Y - 12.9) * 0.85) < 0.34)
        col[wing] = col[wing] * 0.45 + np.array([158.0, 154.0, 144.0]) * 0.55
        alpha = np.maximum(alpha, wing.astype(float))
    paint = np.zeros((H, W))
    paint_col = np.array([226.0, 206.0, 120.0])
    wear = np.clip(smooth_noise(H, W, 7, scales=(14, 6, 3), weights=(0.4, 0.3, 0.3)) * 1.6 - 0.2, 0.25, 1.0)

    def line(x0, y0, x1, y1, wd=0.09):
        m = (X >= min(x0, x1) - wd / 2) & (X <= max(x0, x1) + wd / 2) & (Y >= min(y0, y1) - wd / 2) & (Y <= max(y0, y1) + wd / 2)
        paint[m] = 1.0

    for s in pool["spots"]:
        ax, ay = s["at"]
        if s.get("long"):
            # the aisle's end: a back line and two short ticks
            line(ax - 1.2, ay + 2.2, ax + 1.2, ay + 2.2)
            line(ax - 1.2, ay + 1.4, ax - 1.2, ay + 2.2)
            line(ax + 1.2, ay + 1.4, ax + 1.2, ay + 2.2)
        else:
            sx = -1 if ax < aisle_x else 1
            outer = ax + sx * 1.2
            inner = ax - sx * 1.2
            line(outer, ay - 2.3, outer, ay + 2.2)
            line(inner, ay - 2.3, inner, ay + 2.2)
            line(min(outer, inner), ay + 2.2, max(outer, inner), ay + 2.2)
    # a worn arrow up the aisle, pointing at the gate: the way out
    ax0, ay0 = aisle_x, 24.0
    arrow = np.zeros((H, W))
    shaft = (np.abs(X - ax0) < 0.12) & (Y > ay0) & (Y < ay0 + 1.5)
    head = (Y > ay0 - 0.75) & (Y <= ay0) & (np.abs(X - ax0) < (Y - (ay0 - 0.75)) * 0.55)
    arrow[shaft | head] = 1.0
    col_arrow = np.array([214.0, 210.0, 196.0])
    # the tyre tracks of the routes: two wheels, each pass a little darker
    tracks_acc = np.zeros((H, W))
    for s in pool["spots"]:
        for which in ("out_route", "in_route"):
            sm = cm.sample(s[which], 0.12)
            for side in (-0.74, 0.74):
                pts = []
                for (x, y, h, rev) in sm:
                    px = x + math.cos(h + math.pi / 2) * side
                    py = y + math.sin(h + math.pi / 2) * side
                    pts.append(((px - X0) * PX, (py - Y0) * PX))
                lay = Image.new("L", (W, H), 0)
                ImageDraw.Draw(lay).line(pts, fill=255, width=max(2, int(0.15 * PX)), joint="curve")
                tracks_acc += np.asarray(lay, float) / 255.0
    tracks_acc = np.clip(tracks_acc * 0.13, 0.0, 0.42)
    tracks_acc = np.asarray(Image.fromarray((tracks_acc * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.4)), float) / 255.0
    # oil stains in the bays
    stain = np.zeros((H, W))
    for s in pool["spots"]:
        ax, ay = s["at"]
        for _ in range(3):
            cx = ax + rng.uniform(-0.6, 0.6)
            cy = ay + rng.uniform(-1.2, 1.4)
            rx, ry = rng.uniform(0.18, 0.5), rng.uniform(0.25, 0.7)
            stain = np.maximum(stain, np.clip(1.0 - (((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2), 0, 1) ** 0.8 * rng.uniform(0.25, 0.5))
    out = col
    out = out * (1 - 0.55 * tracks_acc[..., None]) + np.array([28.0, 26.0, 24.0]) * 0.55 * tracks_acc[..., None]
    out = out * (1 - stain[..., None] * 0.7) + np.array([22.0, 20.0, 20.0]) * stain[..., None] * 0.7
    pa = (paint * wear * 0.8 * (Y > 21.0))[..., None]
    out = out * (1 - pa) + paint_col * pa
    aa = (arrow * wear * 0.55)[..., None]
    out = out * (1 - aa) + col_arrow * aa
    rgba = np.dstack([np.clip(out, 0, 255), np.clip(alpha * 255.0, 0, 255)]).astype(np.uint8)
    Image.fromarray(rgba).save(os.path.join(OBJ, APRON_FILE + ".png"), optimize=True)
    log("the apron's ground picture written (%dx%d)" % (W, H))


def main():
    only_data = "--data" in sys.argv
    only_art = "--art" in sys.argv
    msgs = []
    log = msgs.append
    if not only_art:
        # (read, change and write each file at once: others edit them too)
        m = load(MAP)
        edit_map(m, log)
        save(MAP, m)
        d = load(DRESS)
        m = load(MAP)
        edit_dressing(d, m, log)
        save_dressing(DRESS, d)
    if not only_data:
        cut_walkway(log)
        cut_gate(log)
        make_apron(log)
    for line in msgs:
        print(line)
    print("done")


if __name__ == "__main__":
    main()
