#!/usr/bin/env python3
"""Writes assets/data/site_layouts.json: the layouts of the raid sites (round 14, scripts/raid/site_gen.gd).

    python3 tools/make_site_layouts.py

The recipes are written here as Python (so a row of shelves or the four houses of a street are a loop and a
helper, not forty lines of JSON) and come out as plain JSON data: a prop catalogue, templates (small layouts
stamped at a place) and one recipe for each kind of place of assets/data/town.json (and for a few places that
have a layout of their own). The ops and what they take are described in scripts/raid/site_canvas.gd.

Coordinates are tiles on the site's canvas, x across and y down. The squad arrives at the bottom edge, on a
street (or a lane) of `approach` rows with a verge above it; the buildings stand above that. A number may be
{"r": [lo, hi]}, drawn from the site's seed.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "data", "site_layouts.json")


def R(lo, hi):
    return {"r": [lo, hi]}


def prop(files, tiles, ppt=96, layer=2, solid=True, **kw):
    d = {"files": files, "tiles": tiles, "layer": layer}
    if ppt != 96:
        d["ppt"] = ppt
    if not solid:
        d["solid"] = False
    d.update(kw)
    return d


def seq(fmt, nums):
    return [fmt % n for n in nums]


# ------------------------------------------------------------------ catalogue --

PROPS = {
    # shop and office furniture (pictures in assets/objects, 96 px to the tile)
    "shelf": prop(["079_shelf", "095_shelf"], [3, 1], dw=2.95, container="shelf"),
    "shelf_s": prop(["095_shelf"], [2, 1], dw=1.95, container="shelf"),
    "counter": prop(["092_counter"], [4, 1], dw=3.95, container="counter"),
    "counter3": prop(["092_counter"], [3, 1], dw=2.95, container="counter"),
    "counter2": prop(["092_counter"], [2, 1], dw=1.95, container="counter"),
    "fridge": prop(["094_fridge"], [1, 1], dw=0.98, container="fridge"),
    "stove": prop(["093_stove"], [1, 1], dw=1.0),
    "cabinet": prop(["085_cabinet"], [1, 2], dw=0.92, container="cabinet"),
    "locker": prop(seq("%03d_locker", range(1, 12)), [1, 1], dw=0.9, container="locker"),
    "crate": prop(["060_crate", "062_crate", "063_crate", "120_crate", "136_crate", "137_crate", "138_crate", "139_crate", "140_crate"], [1, 1], dw=0.95, container="crate"),
    "crate_ammo": prop(["061_crate"], [1, 1], dw=0.95, container="crate", only=["ammo"]),
    "cans": prop(["064_cans", "065_cans", "066_cans"], [1, 1], dw=0.98, container="crate", only=["food"]),
    "waterpack": prop(["067_waterpack", "068_waterpack"], [1, 1], dw=1.0, container="crate", only=["water"]),
    "scrap": prop(["069_scrap", "142_scrap"], [2, 2], dw=2.1, container="crate", only=["scrap"]),
    "tires": prop(["071_tires"], [1, 2], dw=0.9),
    "generator": prop(["070_generator", "119_generator"], [1, 1], dw=1.15),
    "pump": prop(["127_ibc", "128_ibc"], [1, 1], dw=1.05, container="pump", only=["fuel"]),
    "ibc": prop(["127_ibc", "128_ibc"], [1, 1], dw=1.05),
    "rainbarrel": prop(["125_rainbarrel", "126_rainbarrel"], [1, 1], dw=0.95),
    "waterpump": prop(["125_rainbarrel", "126_rainbarrel"], [1, 1], dw=0.95, container="pump", only=["water"]),
    "toolboard": prop(["059_toolboard"], [4, 1], dw=3.6, solid=False, loose=True, dy=0.0),
    "chalkboard": prop(["087_chalkboard"], [5, 1], dw=4.9, solid=False, loose=True, dy=0.0),
    "barrel": prop(seq("%03d_barrel", range(151, 155)), [1, 1], dw=0.95),
    "bench": prop(["055_bench", "256_bench"], [2, 1], dw=2.1),
    "bed": prop(seq("%03d_mattress", range(72, 76)), [1, 2], dw=1.05),
    "cot": prop(["082_cot", "083_cot"], [1, 2], dw=1.05),
    "desk": prop(["076_desk", "077_desk", "078_desk"], [1, 1], dw=1.1),
    "desk2": prop(["088_desk", "089_desk"], [1, 1], dw=0.95),
    "teacherdesk": prop(["086_teacherdesk"], [2, 1], dw=1.95),
    "longtable": prop(["090_longtable", "091_longtable"], [4, 2], dw=4.4),
    "radiodesk": prop(["054_radiodesk"], [3, 1], dw=2.9, container="counter"),
    "workbench": prop(["058_workbench"], [4, 1], dw=3.95, container="counter"),
    "worktable": prop(["118_worktable"], [3, 1], dw=2.7),
    "lamp": prop(["081_lamp"], [1, 1], dw=0.55, solid=False, loose=True),
    "rug": prop(["056_rug"], [4, 2], ppt=64, layer=1, solid=False, loose=True),
    "rug2": prop(["080_rug"], [5, 3], ppt=64, layer=1, solid=False, loose=True),
    "picnic": prop(["133_picnic", "134_picnic"], [3, 2], dw=2.6),
    "tent": prop(["143_tent", "144_tent"], [3, 3], dw=2.7),
    "sandbags": prop(["141_sandbags"], [3, 1], dw=2.6),
    "ivstand": prop(["084_ivstand"], [1, 1], dw=0.6, solid=False, loose=True),
    "hoop": prop(["097_hoop"], [2, 1], ppt=112, layer=4, solid=False, loose=True),
    "court": prop(["096_court"], [12, 12], ppt=64, layer=1, solid=False, loose=True),
    "foursquare": prop(["098_foursquare"], [4, 4], ppt=64, layer=1, solid=False, loose=True),
    "hopscotch": prop(["099_hopscotch"], [1, 7], ppt=64, layer=1, solid=False, loose=True),
    # the yard
    "shrub": prop(seq("%03d_shrub", range(145, 151)), [1, 1], dw=1.4),
    "trashcan": prop(["257_trashcan"], [1, 1], dw=0.8, container="bin"),
    "trashbags": prop(["253_trashbags", "254_trashbags", "255_trashbags"], [1, 1], dw=1.1, container="bin"),
    "corpse": prop(seq("%03d_corpse", [267, 269, 271, 273, 275]), [1, 1], dw=1.5, solid=False, loose=True),
    "hydrant": prop(["250_hydrant", "251_hydrant"], [1, 1], dw=0.7, solid=False, loose=True),
    "lamppost": prop(seq("%03d_lamppost", range(243, 250)), [1, 1], ppt=112, layer=4, solid=False, loose=True, dx=0.34, dy=-0.3),
    "compost": prop(["129_compost"], [1, 1], dw=1.1),
    "wheelbarrow": prop(["130_wheelbarrow"], [1, 1], dw=1.2, solid=False, loose=True),
    "clothesline": prop(["132_clothesline"], [9, 1], solid=False, loose=True),
    "garden_h": prop(["124_bed"], [8, 2], dw=8.0, solid=False, loose=True),
    "garden_v": prop(["121_bed", "122_bed", "123_bed"], [2, 5], dh=5.0, solid=False, loose=True),
    # vehicles and the big things (112 px to the tile)
    "car_h": prop(["203_car", "205_car", "206_car", "214_car", "215_car"], [5, 2], ppt=112, layer=4, container="trunk", dw=4.8),
    "car_police": prop(["204_car"], [5, 2], ppt=112, layer=4, container="trunk", dw=4.8),
    "car_v": prop(["208_car", "210_car", "211_car", "213_car"], [2, 5], ppt=112, layer=4, container="trunk", dh=4.8),
    "van_h": prop(["207_pickup"], [5, 2], ppt=112, layer=4, container="trunk", dw=5.0),
    "pickup_v": prop(["116_pickup"], [2, 5], ppt=112, layer=4, container="trunk", dh=5.0),
    "bus_h": prop(["166_bus_s0"], [11, 3], ppt=112, layer=4, container="trunk", dw=10.8),
    "bus_v": prop(["175_bus_s0"], [3, 11], ppt=112, layer=4, container="trunk", dh=10.8),
    "cont_red": prop(["163_container_s0"], [12, 3], ppt=112, layer=4, dw=12.0),
    "cont_blue": prop(["168_container_s0"], [6, 3], ppt=112, layer=4, dw=6.0),
    "cont_green_v": prop(["169_container_s0"], [3, 13], ppt=112, layer=4, dh=12.8),
    "cont_orange_v": prop(["173_container_s0"], [3, 7], ppt=112, layer=4, dh=6.8),
    "chain_v": prop(["170_chainlink_s0", "176_chainlink_s0"], [1, 5], ppt=112, layer=4, dh=4.95, solid=False, loose=True, dx=0.0, dy=0.0),
    "blocks_v": prop(["171_blocks_s0"], [1, 5], ppt=112, layer=4, dh=5.0, dx=0.0, dy=0.0),
    "awning_r": prop(["199_awning"], [6, 1], ppt=112, layer=4, solid=False, loose=True, dy=0.0),
    "awning_g": prop(["200_awning"], [7, 1], ppt=112, layer=4, solid=False, loose=True, dy=0.0),
    "awning_b": prop(["201_awning"], [6, 1], ppt=112, layer=4, solid=False, loose=True, dy=0.0),
    # marks on the floor (64 px to the tile, flat, shut nothing)
    "blood": prop(seq("%03d_blood", [268, 270, 272, 274] + list(range(276, 305))), [1, 1], ppt=64, layer=1, solid=False, loose=True, dx=0.0, dy=0.0),
    "papers": prop(seq("%03d_papers", range(309, 339)), [1, 1], ppt=64, layer=1, solid=False, loose=True, dx=0.0, dy=0.0),
    "stain": prop(seq("%03d_stain", range(339, 365)), [1, 1], ppt=64, layer=1, solid=False, loose=True, dx=0.0, dy=0.0),
    "crack": prop(seq("%03d_crack", range(365, 387)), [1, 1], ppt=64, layer=1, solid=False, loose=True, dx=0.0, dy=0.0),
    "scorch": prop(["216_scorch"], [1, 1], ppt=64, layer=1, solid=False, loose=True, dx=0.0, dy=0.0),
}

TERRAIN = {
    "WALL_BRICK": {"id": 20, "file": "res://assets/terrain/wall_brick.png"},
    "WALL_PLASTER": {"id": 21, "file": "res://assets/terrain/wall_plaster.png"},
    "WALL_METAL": {"id": 22, "file": "res://assets/terrain/wall_metal.png"},
    "DOOR_WOOD": {"id": 23, "file": "res://assets/terrain/door_wood.png"},
}

# how much of one stock a container takes before another is wanted (the number of containers follows the loot)
CAPS = {"food": 4, "water": 5, "scrap": 6, "ammo": 40, "meds": 2, "fuel": 15}

# how well a kind of container holds a stock
AFFINITY = {
    "food": {"shelf": 3, "fridge": 3, "cabinet": 1.5, "counter": 1.5, "crate": 2, "bin": 1, "trunk": 1, "locker": 0.3},
    "water": {"fridge": 2, "shelf": 2, "crate": 2.5, "cabinet": 0.8, "trunk": 1, "counter": 0.8, "bin": 0.2, "locker": 0.2, "pump": 2.5},
    "scrap": {"crate": 3, "locker": 2, "cabinet": 1, "trunk": 2, "shelf": 1, "bin": 1.5, "counter": 0.8, "fridge": 0.1},
    "ammo": {"locker": 3, "cabinet": 2, "crate": 3, "counter": 1.5, "trunk": 1.5, "shelf": 0.5, "bin": 0.1},
    "meds": {"cabinet": 3, "shelf": 2, "counter": 2, "locker": 1, "fridge": 1.5, "crate": 0.6, "trunk": 0.6, "bin": 0.3},
    "fuel": {"pump": 4, "trunk": 1.5, "crate": 0.6, "locker": 0.3, "cabinet": 0.3, "counter": 0.2, "shelf": 0.2, "bin": 0.1},
}

# seconds standing at a container, before what it holds adds to it
SEARCH = {"shelf": 4, "crate": 5, "cabinet": 5, "fridge": 3.5, "locker": 4, "trunk": 6, "pump": 7, "counter": 4.5, "bin": 3.5}

# kinds that have no layout of their own and what they are like
ALIASES = {"hospital": "clinic", "mortuary": "clinic", "market": "supermarket", "harbour": "warehouse", "port": "warehouse", "factory": "warehouse", "airfield": "fuel_depot", "town_hall": "library", "school": "school_annex", "stadium": "school_annex", "hotel": "flats", "apartments": "flats", "prison": "police", "barracks": "checkpoint", "depot": "bus_depot", "garage_forecourt": "garage", "pub": "bakery", "shop": "radio_shop", "tower": "flats"}


# ------------------------------------------------------------------- op helpers --

def fill(rect, t, **kw):
    d = {"op": "fill", "rect": rect, "t": t}
    d.update(kw)
    return d


def building(rect, id=None, name=None, wall="WALL_BRICK", floor="LINO", doors=(), **kw):
    d = {"op": "building", "rect": rect, "wall": wall, "floor": floor, "doors": list(doors)}
    if id:
        d["id"] = id
    if name:
        d["name"] = name
    d.update(kw)
    return d


def block(rect, wall="WALL_BRICK", roof="ROOF", **kw):
    d = {"op": "block", "rect": rect, "wall": wall, "roof": roof}
    d.update(kw)
    return d


def door(side, at="mid", w=2, **kw):
    d = {"side": side, "at": at, "w": w}
    d.update(kw)
    return d


def gap(at, w=2):
    """A doorway in a wall made by `wall` or `split`: where along it (from its start) and how wide."""
    return {"at": at, "w": w}


def split(id, dir, at, into, names=None, floors=None, doors=(), wall="WALL_PLASTER", dead=None, **kw):
    d = {"op": "split", "id": id, "dir": dir, "at": at, "into": list(into), "wall": wall, "doors": list(doors)}
    if names:
        d["names"] = list(names)
    if floors:
        d["floors"] = list(floors)
    if dead:
        d["dead"] = list(dead)
    d.update(kw)
    return d


def area(rect, name=None, id=None, dead=0.6, indoor=False, floor=None, **kw):
    d = {"op": "area", "rect": rect, "dead": dead}
    if name:
        d["name"] = name
    if id:
        d["id"] = id
    if indoor:
        d["indoor"] = True
    if floor:
        d["floor"] = floor
    d.update(kw)
    return d


def line(rect, side, kinds, container=False, gap=(0, 0), **kw):
    d = {"op": "line", "rect": rect, "side": side, "kinds": kinds, "gap": list(gap)}
    if container:
        d["container"] = container
    d.update(kw)
    return d


def rows(rect, kinds, pitch=3, container=False, **kw):
    d = {"op": "rows", "rect": rect, "kinds": kinds, "pitch": pitch}
    if container:
        d["container"] = container
    d.update(kw)
    return d


def scatter(rect, kinds, n, container=False, **kw):
    d = {"op": "scatter", "rect": rect, "kinds": kinds, "n": n}
    if container:
        d["container"] = container
    d.update(kw)
    return d


def place(kind=None, at=None, into=None, anchor="C", container=False, kinds=None, **kw):
    d = {"op": "place"}
    if kind:
        d["kind"] = kind
    if kinds:
        d["kinds"] = kinds
    if at is not None:
        d["at"] = at
    if into is not None:
        d["in"] = into
        d["anchor"] = anchor
    if container:
        d["container"] = container
    d.update(kw)
    return d


def decals(rect, kinds, n, **kw):
    d = {"op": "decals", "rect": rect, "kinds": kinds, "n": n}
    d.update(kw)
    return d


def cars(rect, n, container=True, kinds=None, **kw):
    d = {"op": "cars", "rect": rect, "n": n}
    if container:
        d["container"] = container
    if kinds:
        d["kinds"] = kinds
    d.update(kw)
    return d


def trees(rect, n, **kw):
    d = {"op": "trees", "rect": rect, "n": n}
    d.update(kw)
    return d


def stamp(templates, at, id=None, **kw):
    d = {"op": "stamp", "at": at}
    if isinstance(templates, list):
        d["templates"] = templates
    else:
        d["template"] = templates
    if id:
        d["id"] = id
    d.update(kw)
    return d


def group(ops, **kw):
    """Ops that happen together or not at all (p: the chance; if / min_danger: when)."""
    d = {"op": "group", "ops": list(ops)}
    d.update(kw)
    return d


def fence(rect, **kw):
    d = {"op": "fence", "rect": rect}
    d.update(kw)
    return d


STREET = {"road": "ASPHALT", "rows": 7, "verge": "SIDEWALK", "verge_rows": 2, "ends": "barricade"}
LANE = {"road": "DIRT", "rows": 7, "verge": "GRASS", "verge_rows": 2, "ends": "barricade", "lanes": False}
BORDER = {"t": "GRASS", "l": 2, "r": 2, "u": 2}

RECIPES = {}
TEMPLATES = {}


def street_dressing(W, H, cars_n=R(2, 3), junk=14, lamps=R(2, 4)):
    """What a street has lying about: wrecks in the road, a hydrant, a lamp post or two, litter."""
    return [
        cars([3, H - 7, W - 6, 7], cars_n, container=0.6),
        scatter([2, H - 9, W - 4, 2], ["hydrant", "lamppost"], lamps),
        decals([0, H - 9, W, 9], ["papers", "stain", "blood", "crack"], junk),
    ]


def recipe(size, approach=None, border=BORDER, ground="GRASS", containers=(4, 14), ops=(), **kw):
    W, H = size
    d = {"size": [W, H], "ground": ground, "containers": list(containers)}
    if approach is not None:
        d["approach"] = approach
    if border is not None:
        d["border"] = border
    d.update(kw)
    d["ops"] = list(ops)
    return d


# -------------------------------------------------------------- the rooms of a home --

def bedroom(id):
    return [
        place("bed", into=id, anchor="NW", dx=R(0, 1)),
        place("shelf_s", into=id, anchor="NE", container=True),
        place("lamp", into=id, anchor="SW"),
        place("rug", into=id, anchor="S", p=0.7),
        decals(id, ["papers", "stain"], R(0, 2)),
    ]


def living_room(id):
    return [
        place("rug", into=id, anchor="C"),
        line(id, "N", ["bench", "shelf_s", "desk"], container=0.5, gap=(0, 1), n=2),
        place("lamp", into=id, anchor="NE", dx=-1),
        scatter(id, ["desk2", "desk"], R(0, 1), wall=True),
        decals(id, ["papers", "blood", "stain"], R(1, 3)),
    ]


def kitchen_room(id, table=True):
    ops = [line(id, "N", ["stove", "fridge", "counter2", "shelf_s"], container=True, gap=(0, 0))]
    if table:
        ops.append(place("desk2", into=id, anchor="SE", dx=-1, dy=-1))
    return ops


def bathroom_room(id):
    return [
        place("cabinet", into=id, anchor="NE", container=True),
        place("counter2", into=id, anchor="SW"),
    ]


def house(flip=False, w=13, h=11, back_door=True):
    """A detached house: living room and kitchen at the front, bedrooms behind. The front door opens into the living room."""
    vsplit = 6 if not flip else 5
    west, east = ("living", "kitchen") if not flip else ("kitchen", "living")
    front_x = R(2, 3) if not flip else R(7, 8)
    doors = [door("S", front_x, 2)]
    if back_door:
        doors.append(door("N", R(2, 3) if flip else R(8, 9), 2))
    ops = [
        building([0, 0, w, h], id="h", floor="WOOD", doors=doors),
        split("h", "v", vsplit, ["w", "e"], doors=[gap(R(6, 7))]),
        split("w", "h", 4, ["wn", "ws"], names=["bedroom", "living room" if west == "living" else "kitchen"],
              floors=["WOOD", "WOOD" if west == "living" else "KITCHEN"], doors=[gap(R(1, 3))]),
        split("e", "h", 4, ["en", "es"], names=["bathroom" if not flip else "bedroom", "kitchen" if east == "kitchen" else "living room"],
              floors=["KITCHEN" if not flip else "WOOD", "KITCHEN" if east == "kitchen" else "WOOD"], doors=[gap(R(1, 2))]),
    ]
    ops += bedroom("wn")
    ops += living_room("ws") if west == "living" else kitchen_room("ws")
    ops += bathroom_room("en") if not flip else bedroom("en")
    ops += kitchen_room("es") if east == "kitchen" else living_room("es")
    return {"size": [w, h], "ops": ops}


TEMPLATES["house_a"] = house(False)
TEMPLATES["house_b"] = house(True)
TEMPLATES["house_a_back"] = house(False, back_door=False)
TEMPLATES["house_b_back"] = house(True, back_door=False)


# ------------------------------------------------------------------- shop pieces --

def storeroom(id, kinds=("shelf",), crates=("crate", "cans", "crate"), n=6, container=True, only=None, y0=0):
    kw = {}
    if only:
        kw["only"] = only
    return [
        rows(id, list(kinds), pitch=3, container=container, margin=1, y0=y0, **kw),
        scatter(id, list(crates), n, container=container, wall=True, **kw),
    ]


def office(id, container=True):
    return [
        place("desk", into=id, anchor="NW", dx=1, dy=1),
        place("shelf_s", into=id, anchor="NE", container=container),
        place("lamp", into=id, anchor="SW"),
        place("rug", into=id, anchor="C", p=0.6),
        decals(id, ["papers"], R(2, 4)),
    ]


def terrace_shop(W, H, x, w, top, name, floor="LINO", wall="WALL_BRICK", doors=None, neighbor_roof="ROOF_LIGHT", alley=2):
    """The frame of a shop in a street: the next buildings on both sides, alleys down the sides, a back lot, the shop itself."""
    h = H - 9 - top
    doors = doors if doors is not None else [door("S", "mid", 2), door("N", R(5, 9), 2)]
    return [
        fill([2, 2, W - 4, H - 11], "YARD"),
        block([2, top, x - alley - 2, h], roof=neighbor_roof),
        block([x + w + alley, top, W - 2 - (x + w + alley), h], roof=neighbor_roof),
        building([x, top, w, h], id=name, name=name, floor=floor, wall=wall, doors=doors),
        awning(R(x + 2, x + max(3, w - 9)), H - 10),
    ]


# ---------------------------------------------------------------------- recipes --

def houses():
    """A suburban street of six detached houses in two rows with a lane between them, gardens, cars on the drives."""
    W, H = 50, 38
    ops = [
        fill([2, 2, W - 4, H - 11], "GRASS"),
        fill([2, 13, W - 4, 3], "YARD"),
        area([2, 13, W - 4, 3], "the lane", dead=0.6),
        area([2, 27, W - 4, 2], "front gardens", dead=0.4),
        stamp(["house_a_back", "house_b_back"], [R(3, 4), 2], id="b1"),
        stamp(["house_a_back", "house_b_back"], [R(19, 20), 2], id="b2"),
        stamp(["house_a_back", "house_b_back"], [R(35, 36), 2], id="b3"),
        stamp(["house_a", "house_b"], [R(3, 4), 16], id="h1"),
        stamp(["house_a", "house_b"], [R(19, 20), 16], id="h2"),
        stamp(["house_a", "house_b"], [R(35, 36), 16], id="h3"),
        scatter([2, 27, W - 4, 2], ["shrub", "shrub", "trashbags", "trashcan"], R(5, 8), apart=1, container=0.5),
        cars([2, 27, W - 4, 2], R(1, 2), kinds=["car_h"], container=0.7),
        scatter([2, 13, W - 4, 3], ["trashbags", "trashcan", "wheelbarrow", "compost"], R(3, 5), apart=1, container=0.5),
        trees([2, 2, W - 4, 25], R(4, 6), on=["GRASS"], gap=3),
        decals([2, 2, W - 4, 25], ["papers", "blood", "stain"], 8),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=36), containers=(7, 14), ops=ops + street_dressing(W, H))


def pharmacy():
    """A chemist's shop in a terrace: counters and aisles of shelves at the front, a stock room behind, a back door onto the alley."""
    W, H = 46, 32
    ops = terrace_shop(W, H, 12, 23, 5, "pharmacy", doors=[door("S", R(9, 12), 2), door("S", R(15, 18), 2), door("N", R(9, 13), 2)]) + [
        split("pharmacy", "h", 6, ["stock", "shop"], names=["stock room", "shop"], floors=["WOOD", "LINO"],
              doors=[gap(R(4, 7)), gap(R(13, 16))], dead=[1.2, 1.0]),
        line("shop", "N", ["cabinet"], container=True, gap=(0, 1)),
        line([13, 15, 21, 1], "N", ["counter"], container=True, gap=(0, 0), start=2),
        rows([13, 17, 21, 5], ["shelf"], pitch=3, container=True, margin=1, gap_every=2),
        place("rug", into="shop", anchor="S", dy=-1),
        scatter("stock", ["crate", "crate", "cans"], 6, container=True, wall=True),
        rows("stock", ["shelf"], pitch=3, container=True, margin=1),
        scatter([2, 2, 42, 3], ["trashcan", "trashbags", "crate"], 5, container=0.5),
        decals([12, 6, 23, 16], ["papers", "stain", "blood"], 8),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=14, entry_hi=30), containers=(5, 12), ops=ops + street_dressing(W, H))


def bakery():
    """Pell's bakery: a front shop with a counter and bread racks, the ovens and benches behind, a store of tins, a yard with a van."""
    W, H = 44, 30
    ops = terrace_shop(W, H, 8, 28, 5, "bakery", doors=[door("S", R(8, 14), 2), door("S", R(19, 23), 2), door("N", R(4, 8), 2)]) + [
        split("bakery", "h", 7, ["back", "shop"], names=["", "shop"], floors=["KITCHEN", "LINO"], doors=[gap(R(6, 8)), gap(R(16, 18))], dead=[1.0, 1.0]),
        split("back", "v", 13, ["ovens", "store"], names=["bakehouse", "store room"], floors=["KITCHEN", "CONCRETE"], doors=[gap(R(2, 4))], dead=[1.2, 1.0]),
        line("shop", "N", ["shelf"], container=True, gap=(0, 0)),
        line([9, 16, 26, 1], "N", ["counter"], container=True, gap=(0, 0), start=1, n=3),
        rows([9, 18, 26, 2], ["shelf"], pitch=3, container=True, margin=1, gap_every=2),
        place("rug", into="shop", anchor="SE", dy=-1, dx=-2),
        line("ovens", "N", ["stove"], gap=(1, 1), n=4),
        rows([9, 9, 13, 4], ["workbench"], pitch=3, container=True, margin=1),
        scatter("ovens", ["crate", "cans"], 3, container=True, wall=True),
        storeroom("store", kinds=("shelf",), crates=("cans", "crate", "cans", "waterpack"), n=7),
        place("van_h", at=[R(14, 22), 2], container=True, p=0.7),
        scatter([2, 2, 40, 3], ["trashcan", "trashbags", "crate"], 4, container=0.5),
        decals([8, 6, 28, 14], ["papers", "stain", "blood"], 8),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=30), containers=(5, 12), ops=ops + street_dressing(W, H))


def hardware():
    """The hardware store: aisles of shelves, a counter with lockers and ammunition behind it, a stock room, and a fenced timber yard."""
    W, H = 48, 34
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        block([2, 8, 3, 17], roof="ROOF_LIGHT"),
        building([6, 8, 26, 17], id="store", name="store", floor="CONCRETE", doors=[door("S", R(10, 14), 3), door("N", R(15, 18), 2), door("E", R(4, 8), 2)]),
        split("store", "h", 6, ["stock", "shop"], names=["stock room", "shop floor"], floors=["CONCRETE", "LINO"], doors=[gap(R(4, 7)), gap(R(15, 18))], dead=[1.1, 1.0]),
        line([7, 16, 24, 1], "N", ["locker", "locker", "crate_ammo"], container=True, gap=(0, 0), n=7),
        line([7, 18, 12, 1], "N", ["counter"], container=True, gap=(0, 0), start=0, n=3),
        rows([7, 20, 24, 4], ["shelf"], pitch=3, container=True, margin=1, gap_every=2),
        scatter("shop", ["workbench", "tires", "crate"], 3, container=0.4, wall=True),
        storeroom("stock", kinds=("shelf",), crates=("crate", "crate_ammo", "scrap"), n=6),
        # the timber yard
        fence([33, 5, 13, 20], style="metal", gates=[{"side": "S", "at": 4, "w": 3}, {"side": "W", "at": R(6, 9), "w": 2}]),
        area([34, 6, 11, 18], "timber yard", dead=0.8, floor="DIRT"),
        place("cont_blue", at=[35, 7], container=True, ckind="crate"),
        scatter([34, 6, 11, 18], ["crate", "crate", "tires", "scrap", "crate_ammo"], 12, container=True, apart=0),
        scatter([34, 6, 11, 18], ["trashbags", "barrel"], 3),
        patch_dirt(),
        decals([2, 5, W - 4, 20], ["papers", "stain", "blood"], 9),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=10, entry_hi=36), containers=(6, 14), ops=ops + street_dressing(W, H))


def patch_dirt():
    return {"op": "patch", "rect": [34, 6, 11, 18], "t": "SOIL", "n": 3, "r": [1.5, 3]}


def radio_shop():
    """Ferris radio and TV: rows of dead screens on shelves, a counter, a workshop behind with benches and parts."""
    W, H = 44, 30
    ops = terrace_shop(W, H, 9, 26, 5, "shop", doors=[door("S", R(10, 15), 2), door("S", R(18, 21), 2), door("N", R(5, 9), 2)]) + [
        split("shop", "h", 6, ["work", "front"], names=["workshop", "showroom"], floors=["CONCRETE", "TERRAZZO"], doors=[gap(R(5, 7)), gap(R(15, 18))], dead=[1.1, 1.0]),
        line("front", "N", ["shelf"], container=True, gap=(0, 0)),
        line([10, 15, 24, 1], "N", ["counter2", "radiodesk"], container=True, gap=(0, 0), start=1, n=3),
        rows([10, 17, 24, 3], ["shelf"], pitch=3, container=True, margin=1, gap_every=2),
        place("rug", into="front", anchor="SE", dy=-1),
        rows("work", ["workbench"], pitch=3, container=True, margin=1),
        scatter("work", ["crate", "locker", "scrap", "desk"], 6, container=True, wall=True),
        scatter([2, 2, 40, 3], ["trashcan", "trashbags", "crate"], 4, container=0.5),
        decals([9, 6, 26, 14], ["papers", "stain", "blood"], 8),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=32), containers=(5, 12), ops=ops + street_dressing(W, H))


def library():
    """The public library: a reading room of long tables and stacks, a desk at the door, a children's corner, the staff kitchen behind."""
    W, H = 46, 32
    ops = terrace_shop(W, H, 7, 32, 5, "library", floor="TERRAZZO", doors=[door("S", R(12, 18), 3), door("N", R(24, 28), 2)]) + [
        split("library", "h", 6, ["staff", "reading"], names=["", "reading room"], floors=["KITCHEN", "TERRAZZO"], doors=[gap(R(20, 24)), gap(R(8, 10))], dead=[1.0, 1.0]),
        split("staff", "v", 12, ["kitchen", "office"], names=["staff kitchen", "office"], floors=["KITCHEN", "WOOD"], doors=[gap(R(2, 4))], dead=[1.0, 1.0]),
        line("kitchen", "N", ["fridge", "counter2", "shelf_s", "stove"], container=True, gap=(0, 0)),
        place("desk2", into="kitchen", anchor="SE", dx=-1, dy=-1),
        office("office"),
        rows([9, 14, 30, 7], ["shelf"], pitch=3, margin=2, y0=0, gap_every=2),
        place("longtable", into="reading", anchor="S", dx=-10, dy=-1),
        place("longtable", into="reading", anchor="S", dx=6, dy=-1),
        place("counter", at=[R(10, 12), 19], container=0.5, only=["food", "water"]),
        place("rug2", at=[R(30, 32), 14]),
        scatter("reading", ["desk2", "bench"], 4, wall=True),
        scatter([2, 2, 42, 3], ["trashcan", "trashbags"], 3),
        decals([7, 6, 32, 16], ["papers", "papers", "stain", "blood"], 12),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=33), containers=(3, 8), ops=ops + street_dressing(W, H))


def clinic():
    """Eastgate clinic: chairs in rows in the waiting room, a reception desk, a corridor of consulting rooms, the dispensary at the back."""
    W, H = 48, 32
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        block([2, 6, 3, 17], roof="ROOF_LIGHT"),
        block([44, 6, 2, 17], roof="ROOF_LIGHT"),
        building([6, 5, 36, 18], id="clinic", floor="LINO", doors=[door("S", R(8, 12), 3), door("S", R(24, 28), 2), door("E", R(10, 13), 2)]),
        split("clinic", "h", 9, ["back", "front"], names=["", ""], doors=[gap(R(4, 7)), gap(R(18, 22)), gap(R(28, 30))], dead=[1.0, 1.0]),
        split("back", "v", 11, ["disp", "rest"], names=["dispensary", ""], floors=["TERRAZZO", "LINO"], doors=[gap(R(3, 5))], dead=[1.4, 1.0]),
        split("rest", "v", 11, ["exam1", "rest2"], names=["consulting room", ""], floors=["LINO", "LINO"], doors=[gap(R(5, 7), 2)], dead=[1.0, 1.0]),
        split("rest2", "v", 11, ["exam2", "exam3"], names=["consulting room", "ward"], floors=["LINO", "LINO"], doors=[gap(R(5, 7), 2)], dead=[1.0, 1.0]),
        split("front", "v", 18, ["waiting", "front2"], names=["waiting room", ""], floors=["LINO", "LINO"], doors=[gap(R(2, 4))], dead=[1.2, 1.0]),
        split("front2", "v", 8, ["reception", "staff"], names=["reception", "staff room"], floors=["LINO", "WOOD"], doors=[gap(R(2, 4))], dead=[1.0, 1.0]),
        # the dispensary: shelves and cabinets of everything
        line("disp", "N", ["cabinet"], container=True, gap=(0, 0)),
        rows("disp", ["shelf"], pitch=3, container=True, margin=1, y0=3),
        # the consulting rooms and the ward: a cot, a cabinet, a drip stand
        place("cot", into="exam1", anchor="NW", dx=1),
        place("cabinet", into="exam1", anchor="NE", container=True),
        place("ivstand", into="exam1", anchor="SW"),
        place("cot", into="exam2", anchor="NW", dx=1),
        place("cabinet", into="exam2", anchor="NE", container=True),
        place("ivstand", into="exam2", anchor="SE"),
        line("exam3", "N", ["cot"], gap=(1, 1)),
        place("cabinet", into="exam3", anchor="SE", container=True),
        # the waiting room: chairs (benches) in rows, a few things dropped in a hurry
        rows("waiting", ["bench"], pitch=2, margin=1, y0=1, n=3),
        place("counter", into="reception", anchor="N", container=True),
        place("desk", into="reception", anchor="SW", dx=1),
        office("staff"),
        # the ambulance bay on the east side
        area([42, 6, 4, 17], "bay", dead=0.5),
        cars([43, 8, 3, 14], 1, kinds=["car_v", "pickup_v"], container=True),
        scatter([2, 2, W - 4, 3], ["trashcan", "trashbags", "crate"], 4, container=0.5),
        decals([6, 5, 36, 18], ["papers", "stain", "blood"], 12),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=34), containers=(5, 12), ops=ops + street_dressing(W, H))


def church():
    """St. Aidan's: a nave of pews either side of an aisle with the altar at the end, a vestry, and a parish hall with its kitchen."""
    W, H = 48, 34
    ops = [
        fill([2, 2, W - 4, H - 11], "GRASS"),
        building([6, 4, 36, 21], id="church", floor="TERRAZZO", doors=[door("S", R(16, 18), 3), door("N", R(26, 30), 2), door("E", R(14, 16), 2)]),
        split("church", "v", 7, ["west", "rest"], doors=[gap(R(3, 5))]),
        split("rest", "v", 14, ["nave", "east"], doors=[gap(R(14, 16)), gap(R(3, 5))]),
        split("west", "h", 9, ["vestry", "store"], names=["vestry", "bell store"], floors=["WOOD", "CONCRETE"], doors=[gap(R(2, 4))], dead=[1.0, 1.0]),
        split("east", "h", 8, ["hall", "kitchen"], names=["parish hall", "kitchen"], floors=["WOOD", "KITCHEN"], doors=[gap(R(4, 6))], dead=[1.2, 1.0]),
        area("nave", "nave", dead=1.4, indoor=True),
        # the nave
        place("counter3", into="nave", anchor="N", dy=1, container=True, only=["food", "water", "meds"]),
        rows([15, 9, 6, 13], ["bench"], pitch=2, margin=0),
        rows([23, 9, 6, 13], ["bench"], pitch=2, margin=0),
        place("lamp", into="nave", anchor="NW"),
        place("lamp", into="nave", anchor="NE"),
        # the vestry and the store
        office("vestry"),
        place("cabinet", into="vestry", anchor="NW", dx=1, container=True),
        storeroom("store", kinds=("shelf_s",), crates=("cans", "crate", "waterpack"), n=4),
        # the hall and its kitchen
        rows("hall", ["longtable"], pitch=4, margin=1, y0=1),
        kitchen_room("kitchen"),
        place("fridge", into="kitchen", anchor="NE", container=True),
        place("waterpack", into="kitchen", anchor="SW", container=True),
        # the churchyard
        scatter([2, 4, 4, 20], ["shrub"], 4, apart=0),
        scatter([42, 4, 4, 20], ["shrub"], 4),
        trees([2, 4, 4, 20], 3, on=["GRASS"]),
        trees([42, 4, 4, 20], 3, on=["GRASS"]),
        scatter([2, 2, W - 4, 2], ["bench", "shrub"], 4),
        decals([6, 4, 36, 21], ["papers", "stain", "blood"], 9),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=36), containers=(3, 9), ops=ops + street_dressing(W, H))


def awning(x, y):
    """A striped awning over a shop front (drawn over the wall and the pavement, shuts nothing)."""
    return place(kinds=["awning_r", "awning_g", "awning_b"], at=[x, y], decor=True)


def fire_station():
    """Two engine bays (one engine gone), a locker room, a mess and an office behind them, a drill yard beside."""
    W, H = 52, 32
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        building([6, 4, 38, 19], id="fs", floor="CONCRETE", doors=[door("S", 5, 5), door("S", 21, 5), door("E", R(6, 9), 2), door("N", R(28, 31), 2)]),
        split("fs", "h", 6, ["back", "bays"], doors=[gap(R(5, 7)), gap(R(20, 22)), gap(R(30, 32))], floors=["WOOD", "CONCRETE"]),
        split("back", "v", 12, ["lockers", "rest"], names=["locker room", ""], floors=["TERRAZZO", "WOOD"], doors=[gap(R(2, 3))], dead=[1.0, 1.0]),
        split("rest", "v", 12, ["mess", "office"], names=["mess", "office"], floors=["KITCHEN", "WOOD"], doors=[gap(R(2, 3))], dead=[1.0, 1.0]),
        split("bays", "v", 18, ["bay1", "bay2"], names=["engine bay", "empty bay"], doors=[gap(R(3, 5), 3)], dead=[1.2, 1.2]),
        line("lockers", "N", ["locker"], container=True, gap=(0, 0)),
        line("lockers", "S", ["bench"], gap=(1, 2), n=3),
        kitchen_room("mess"),
        place("longtable", into="mess", anchor="S", dy=-1),
        office("office"),
        place("cont_red", at=[R(9, 11), 15], decor=False),
        line("bay1", "N", ["workbench"], container=True, gap=(1, 2), n=2),
        place("toolboard", at=[9, 12], decor=True),
        place("waterpump", into="bay1", anchor="SW", container=True),
        place("tires", into="bay1", anchor="SE"),
        place("waterpump", into="bay2", anchor="NE", container=True),
        scatter("bay2", ["crate", "waterpack", "tires", "barrel"], 5, container=True, wall=True),
        scatter("bay1", ["crate", "locker"], 3, container=True, wall=True),
        decals("bay2", ["stain", "stain", "papers"], 6),
        decals("bay1", ["stain", "papers"], 3),
        area([44, 4, 6, 19], "drill yard", dead=0.6),
        scatter([44, 4, 6, 19], ["crate", "barrel", "tires", "shrub", "waterpack"], 7, container=0.5),
        trees([44, 4, 6, 19], 3, on=["YARD", "GRASS"]),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=36), containers=(4, 10), ops=ops + street_dressing(W, H))


def police():
    """The police station: a lobby and a squad room at the front, cells and the armoury at the back, a fenced pound for the cars."""
    W, H = 50, 34
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        building([6, 4, 34, 21], id="pol", floor="TERRAZZO", doors=[door("S", R(13, 16), 3), door("N", R(24, 27), 2), door("E", R(13, 15), 2)]),
        split("pol", "h", 8, ["back", "front"], doors=[gap(R(1, 1), 2), gap(R(7, 7), 2), gap(R(13, 13), 2), gap(R(21, 22)), gap(R(26, 28))], floors=["TERRAZZO", "TERRAZZO"]),
        split("back", "v", 17, ["cells", "rest"], doors=[gap(R(2, 4))], floors=["CONCRETE", "WOOD"]),
        split("cells", "v", 5, ["c1", "crest"], names=["cell", ""], floors=["CONCRETE", "CONCRETE"], doors=[], dead=[0.8, 0.8]),
        split("crest", "v", 5, ["c2", "c3"], names=["cell", "cell"], floors=["CONCRETE", "CONCRETE"], doors=[], dead=[0.8, 0.8]),
        split("rest", "v", 6, ["interview", "armoury"], names=["interview room", "armoury"], floors=["WOOD", "CONCRETE"], doors=[gap(R(2, 4))], dead=[0.8, 1.4]),
        split("front", "v", 20, ["lobby", "squad"], names=["lobby", "squad room"], floors=["TERRAZZO", "WOOD"], doors=[gap(R(2, 4), 2)], dead=[1.2, 1.0]),
        place("cot", into="c1", anchor="NW", dx=1),
        place("cot", into="c2", anchor="NW", dx=1),
        place("cot", into="c3", anchor="NE", dx=-1),
        place("desk", into="interview", anchor="NW", dx=1, dy=1),
        place("desk2", into="interview", anchor="SE", dx=-1, dy=-1),
        line("armoury", "N", ["locker", "locker", "cabinet"], container=True, gap=(0, 0)),
        line("armoury", "S", ["locker", "crate_ammo"], container=True, gap=(0, 1), n=4),
        scatter("armoury", ["crate_ammo", "crate", "locker"], 4, container=True, wall=True),
        place("counter", into="lobby", anchor="N", dx=2, dy=3, container=True),
        rows("lobby", ["bench"], pitch=2, margin=1, y0=6, n=2),
        place("lamp", into="lobby", anchor="NE"),
        rows("squad", ["desk"], pitch=3, margin=1, y0=1, n=3),
        line("squad", "E", ["locker", "cabinet"], container=True, gap=(0, 1), n=3),
        decals("lobby", ["papers", "blood", "stain"], 6),
        decals("squad", ["papers", "papers"], 4),
        fence([41, 3, 8, 22], style="metal", gates=[{"side": "S", "at": 3, "w": 3}]),
        area([42, 4, 6, 20], "pound", dead=0.8, floor="CONCRETE"),
        place("car_police", at=[42, 7], container=True),
        place("car_police", at=[42, 12], container=True, p=0.8),
        place("car_police", at=[42, 17], container=True, p=0.6),
        scatter([42, 4, 6, 20], ["crate", "barrel", "tires"], 3, container=0.3),
        decals([2, 4, W - 4, 21], ["papers", "stain", "blood"], 8),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=36), containers=(6, 12), ops=ops + street_dressing(W, H))


def gas_station():
    """The crossing fuel stop: pumps in two rows under a canopy of awnings, a kiosk with its shop and store, cars left at the pumps."""
    W, H = 52, 34
    ops = [
        fill([2, 2, W - 4, H - 11], "GRASS"),
        fill([3, 12, 30, 13], "CONCRETE"),
        area([3, 12, 30, 13], "forecourt", dead=1.0),
        building([35, 10, 14, 15], id="kiosk", floor="LINO", wall="WALL_METAL", doors=[door("S", R(4, 6), 3), door("W", R(8, 10), 2)]),
        split("kiosk", "h", 7, ["back", "shop"], names=["", "kiosk shop"], floors=["CONCRETE", "LINO"], doors=[gap(R(1, 2)), gap(R(8, 9))], dead=[1.0, 1.0]),
        split("back", "v", 8, ["store", "toilets"], names=["store room", "toilets"], floors=["CONCRETE", "KITCHEN"], doors=[gap(R(2, 3), 2)], dead=[1.0, 1.0]),
        line("shop", "N", ["fridge", "fridge", "shelf_s", "cabinet"], container=True, gap=(0, 0)),
        place("counter", into="shop", anchor="SW", dx=1, dy=-1, container=True),
        scatter("shop", ["shelf_s", "cans", "waterpack"], 3, container=True, wall=True),
        scatter("store", ["crate", "shelf_s", "cans", "crate"], 5, container=True, wall=True),
        place("cabinet", into="toilets", anchor="NE", container=True),
        # the pumps, two islands, under a canopy of awnings with a post at each end
        line([6, 16, 24, 1], "N", ["pump"], container=True, gap=(3, 4), n=4),
        line([6, 20, 24, 1], "N", ["pump"], container=True, gap=(3, 4), n=4),
        fill([5, 14, 1, 1], "WALL_METAL", solid=True),
        fill([5, 22, 1, 1], "WALL_METAL", solid=True),
        fill([30, 14, 1, 1], "WALL_METAL", solid=True),
        fill([30, 22, 1, 1], "WALL_METAL", solid=True),
        place("awning_r", at=[5, 13]),
        place("awning_g", at=[11, 13]),
        place("awning_b", at=[18, 13]),
        place("awning_r", at=[24, 13]),
        place("awning_b", at=[5, 22]),
        place("awning_g", at=[11, 22]),
        place("awning_r", at=[18, 22]),
        place("awning_g", at=[24, 22]),
        place("car_h", at=[24, 17], jitter=2, container=True, if_="vehicle"),
        cars([3, 12, 30, 13], R(1, 2), kinds=["car_h"], container=0.8),
        scatter([3, 12, 30, 13], ["barrel", "trashcan", "bench"], 3, container=0.3),
        scatter([35, 5, 14, 5], ["barrel", "trashbags", "crate", "tires"], 4, container=0.4),
        trees([2, 2, W - 4, 10], 6, on=["GRASS"], gap=3),
        decals([3, 12, 30, 13], ["stain", "stain", "blood", "papers"], 9),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=36), containers=(5, 12), ops=ops + street_dressing(W, H))


def truck_stop():
    """The north road truck stop: a cafe and a shower block with the drivers' lockers, pumps under a canopy, trailers parked nose to tail."""
    W, H = 54, 36
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        building([4, 10, 22, 15], id="cafe", floor="LINO", doors=[door("S", R(5, 8), 3), door("E", R(5, 8), 2)]),
        split("cafe", "v", 12, ["front", "block"], doors=[gap(R(5, 7))], floors=["LINO", "TERRAZZO"]),
        split("front", "h", 6, ["kitchen", "dining"], names=["kitchen", "cafe"], floors=["KITCHEN", "LINO"], doors=[gap(R(3, 5))], dead=[1.0, 1.0]),
        split("block", "h", 6, ["lockers", "showers"], names=["drivers' lockers", "showers"], floors=["TERRAZZO", "KITCHEN"], doors=[gap(R(2, 3))], dead=[1.0, 1.0]),
        line("kitchen", "N", ["stove", "fridge", "counter2", "fridge"], container=True, gap=(0, 0)),
        place("workbench", into="kitchen", anchor="S", dy=-1, container=True, ckind="counter"),
        place("counter", into="dining", anchor="N", dx=1, container=True),
        rows("dining", ["desk2"], pitch=2, margin=1, y0=3, n=3, gap_every=2),
        place("bench", into="dining", anchor="SE", dx=-1),
        line("lockers", "N", ["locker"], container=True, gap=(0, 0)),
        line("lockers", "S", ["locker"], container=True, gap=(0, 0)),
        place("counter2", into="showers", anchor="NW"),
        place("cabinet", into="showers", anchor="NE", container=True),
        # the pumps and their canopy
        area([27, 10, 24, 9], "pumps", dead=1.0, floor="CONCRETE"),
        line([29, 14, 20, 1], "N", ["pump"], container=True, gap=(3, 4), n=4),
        fill([29, 12, 1, 1], "WALL_METAL", solid=True),
        fill([48, 12, 1, 1], "WALL_METAL", solid=True),
        fill([29, 16, 1, 1], "WALL_METAL", solid=True),
        fill([48, 16, 1, 1], "WALL_METAL", solid=True),
        place("awning_r", at=[30, 12]),
        place("awning_g", at=[36, 12]),
        place("awning_b", at=[43, 12]),
        # the lorry park: trailers nose to tail
        area([27, 19, 24, 5], "lorry park", dead=1.2),
        place("cont_red", at=[28, 20], container=True, ckind="trunk"),
        place("cont_blue", at=[41, 20], container=True, ckind="trunk"),
        scatter([4, 2, 22, 7], ["trashbags", "barrel", "crate", "tires"], 5, container=0.4),
        scatter([27, 3, 24, 6], ["barrel", "tires", "trashcan", "crate"], 5, container=0.4),
        cars([27, 3, 24, 7], R(2, 3), container=0.7),
        decals([2, 4, W - 4, 20], ["stain", "stain", "papers", "blood"], 12),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=40), containers=(6, 14), ops=ops + street_dressing(W, H))


def garage():
    """Dunne's garage: two bays, an office with a till, a parts store, and a yard of wrecks and tyres."""
    W, H = 46, 32
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        block([2, 6, 4, 17], roof="ROOF_LIGHT"),
        building([8, 6, 26, 17], id="gar", floor="CONCRETE", doors=[door("S", 3, 4), door("S", 15, 4), door("E", R(3, 5), 2), door("N", R(18, 20), 2)]),
        split("gar", "h", 4, ["front", "work"], doors=[gap(R(2, 3)), gap(R(15, 16))], floors=["WOOD", "CONCRETE"]),
        split("front", "v", 12, ["office", "parts"], names=["office", "parts store"], floors=["WOOD", "CONCRETE"], doors=[gap(R(1, 1))], dead=[1.0, 1.0]),
        split("work", "v", 11, ["bay1", "bay2"], names=["bay", "second bay"], doors=[gap(R(3, 5), 3)], dead=[1.2, 1.2]),
        place("counter", into="office", anchor="NW", dx=1, container=True),
        place("desk", into="office", anchor="SW", dx=1),
        place("shelf_s", into="office", anchor="NE", container=True),
        rows("parts", ["shelf"], pitch=3, margin=1, container=True),
        scatter("parts", ["crate", "tires", "locker"], 3, container=True, wall=True),
        line("bay1", "N", ["workbench"], container=True, gap=(0, 0), n=1),
        place("toolboard", at=[10, 11], decor=True),
        line("bay1", "W", ["locker"], container=True, gap=(0, 1), n=3),
        place("pickup_v", at=[R(14, 16), 14], container=True, jitter=2, if_="vehicle"),
        line("bay2", "N", ["workbench"], container=True, gap=(0, 0), n=1),
        scatter("bay2", ["tires", "crate", "locker", "barrel"], 6, container=True, wall=True),
        decals("work", ["stain", "stain", "stain", "papers"], 8),
        # the yard: wrecks, tyres, a pump
        area([35, 6, 10, 17], "yard", dead=0.9),
        cars([35, 6, 10, 17], R(3, 4), container=True),
        scatter([35, 6, 10, 17], ["tires", "scrap", "barrel", "crate"], 7, container=0.5),
        place("pump", at=[36, 21], container=True),
        decals([35, 6, 10, 17], ["stain", "stain", "blood"], 6),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=34), containers=(5, 12), ops=ops + street_dressing(W, H))


def supermarket():
    """The ring road supermarket: a car park full of the dead who came to shop, checkouts, long aisles, cold cabinets, and a stock room behind."""
    W, H = 56, 40
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        fill([2, 24, W - 4, 7], "YARD"),
        area([2, 24, W - 4, 7], "car park", dead=1.0),
        building([4, 6, 48, 18], id="store", floor="LINO", doors=[door("S", 17, 4), door("S", 27, 4), door("N", R(10, 14), 3), door("W", R(8, 11), 2)]),
        split("store", "h", 5, ["back", "sales"], doors=[gap(R(6, 8), 3), gap(R(22, 24), 3), gap(R(36, 38), 3)], floors=["CONCRETE", "LINO"]),
        area("back", "stock room", dead=1.3, indoor=True),
        area("sales", "sales floor", dead=1.0, indoor=True),
        line("sales", "N", ["fridge"], container=True, gap=(0, 0), n=40),
        line([5, 20, 46, 1], "N", ["counter2", "counter"], container=True, gap=(1, 3), start=1),
        rows([5, 14, 46, 6], ["shelf"], pitch=3, margin=1, gap_every=3, container=True),
        scatter("sales", ["cans", "waterpack", "crate"], 6, container=True, apart=0),
        place("rug", into="sales", anchor="SE", p=0.4),
        rows("back", ["shelf"], pitch=3, margin=1, container=True),
        scatter("back", ["cans", "waterpack", "crate", "cans", "waterpack"], 10, container=True, wall=True),
        group([
            decals("back", ["blood", "blood", "stain"], 12),
            scatter("back", ["corpse"], 4),
        ], if_="nest"),
        cars([3, 24, W - 6, 7], R(8, 11), container=0.5),
        place("van_h", at=[R(20, 40), 25], container=True, jitter=2, if_="vehicle"),
        scatter([2, 24, W - 4, 7], ["trashcan", "trashbags", "bench"], 5, container=0.4),
        scatter([2, 24, W - 4, 7], ["lamppost"], 4),
        decals([2, 24, W - 4, 7], ["blood", "blood", "stain", "papers", "crack"], 22),
        decals([4, 6, 48, 18], ["papers", "stain", "blood"], 10),
        trees([2, 2, W - 4, 4], 3, on=["GRASS", "YARD"]),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=44), containers=(8, 16), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def warehouse():
    """The distribution warehouse: roller doors along the front, racking in long aisles, crates and pallets of stock, offices in a corner."""
    W, H = 56, 36
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        building([8, 6, 40, 21], id="wh", floor="CONCRETE", wall="WALL_METAL", doors=[door("S", 6, 5), door("S", 17, 5), door("S", 28, 5), door("N", R(10, 24), 3), door("W", R(8, 12), 3)]),
        split("wh", "h", 4, ["offices", "floor"], floors=["WOOD", "CONCRETE"], doors=[gap(R(4, 8), 3), gap(R(22, 26), 3)]),
        split("offices", "v", 10, ["office", "orest"], names=["office", ""], floors=["WOOD", "KITCHEN"], doors=[gap(R(1, 2))], dead=[1.0, 1.0]),
        split("orest", "v", 12, ["break", "records"], names=["break room", "records room"], floors=["KITCHEN", "WOOD"], doors=[gap(R(1, 2))], dead=[1.0, 1.0]),
        area("floor", "warehouse floor", dead=1.4, indoor=True),
        office("office"),
        kitchen_room("break"),
        rows("records", ["shelf_s"], pitch=2, margin=1, container=True),
        rows([9, 13, 38, 12], ["shelf"], pitch=3, margin=1, gap_every=3, container=True),
        scatter("floor", ["crate", "cans", "waterpack", "scrap", "crate"], 14, container=True, apart=0),
        scatter("floor", ["barrel", "tires", "trashbags"], 4),
        decals("floor", ["stain", "stain", "papers", "blood"], 12),
        # the lots either side
        scatter([2, 6, 5, 20], ["shrub"], 3),
        place("cont_green_v", at=[3, 8], container=True, ckind="trunk", p=0.8),
        place("cont_orange_v", at=[50, 9], container=True, ckind="trunk", p=0.8),
        trees([2, 2, W - 4, 4], 3, on=["YARD", "GRASS"]),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=44), containers=(6, 14), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def scrapyard():
    """The scrapyard: a fenced yard of heaps, crushed cars and stacked containers, a gate at the front, the wrecker's shack."""
    W, H = 52, 34
    ops = [
        fill([2, 2, W - 4, H - 11], "DIRT"),
        fence([3, 3, 46, 22], style="metal", gates=[{"side": "S", "at": R(18, 32), "w": 4}]),
        area([4, 4, 44, 20], "the yard", dead=1.0),
        {"op": "patch", "rect": [4, 4, 44, 20], "t": "SOIL", "n": 8, "r": [1.5, 3.5]},
        # containers across the yard make the lanes
        place("cont_red", at=[6, 6]),
        place("cont_blue", at=[19, 6]),
        place("cont_red", at=[27, 6], p=0.9),
        place("cont_blue", at=[40, 6]),
        place("cont_red", at=[R(5, 8), 12], p=0.9),
        place("cont_blue", at=[R(22, 28), 12], p=0.7),
        place("cont_orange_v", at=[R(42, 44), 11], p=0.8),
        building([5, 18, 10, 6], id="shack", name="wrecker's shack", wall="WALL_METAL", floor="WOOD", doors=[door("E", 2, 2), door("N", 3, 2)]),
        place("counter2", into="shack", anchor="NW", container=True, dx=1),
        place("desk", into="shack", anchor="SE", dx=-1),
        place("locker", into="shack", anchor="NE", container=True),
        place("locker", into="shack", anchor="E", container=True),
        scatter([4, 4, 44, 20], ["scrap", "scrap", "scrap"], R(8, 11), container=True, apart=1),
        cars([4, 4, 44, 20], R(5, 7), container=0.6, kinds=["car_h", "car_v"]),
        scatter([4, 4, 44, 20], ["tires", "barrel", "crate", "trashbags"], R(8, 12), container=0.2),
        group([decals([4, 4, 44, 20], ["blood", "blood", "stain"], 14), scatter([4, 4, 44, 20], ["corpse"], 4)], if_="nest"),
        decals([4, 4, 44, 20], ["stain", "stain", "crack", "papers"], 14),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=14, entry_hi=36), containers=(7, 14), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def bus_depot():
    """The bus depot: a fenced yard of buses nose to tail in rows, the maintenance shed, and the canteen past all of them at the back."""
    W, H = 56, 38
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        fence([3, 2, 50, 27], style="metal", gates=[{"side": "S", "at": R(20, 30), "w": 5}]),
        area([4, 13, 48, 15], "bus park", dead=1.2),
        building([6, 3, 26, 9], id="canteen", floor="LINO", doors=[door("S", R(6, 10), 3), door("S", R(16, 20), 2)]),
        split("canteen", "v", 14, ["eat", "offices"], names=["canteen", "offices"], floors=["LINO", "WOOD"], doors=[gap(R(4, 5))], dead=[1.2, 1.0]),
        line("eat", "N", ["fridge", "stove", "counter2", "fridge", "shelf_s"], container=True, gap=(0, 0)),
        rows("eat", ["desk2"], pitch=2, margin=1, y0=3, n=2, gap_every=3),
        office("offices"),
        place("locker", into="offices", anchor="SE", container=True),
        building([36, 3, 14, 11], id="shed", name="maintenance shed", wall="WALL_METAL", floor="CONCRETE", doors=[door("S", 4, 4)]),
        line("shed", "N", ["workbench"], container=True, gap=(0, 0), n=2),
        scatter("shed", ["tires", "crate", "locker", "barrel"], 7, container=True, wall=True),
        decals("shed", ["stain", "stain"], 5),
        # the buses
        place("bus_h", at=[5, 16], container=True, p=0.9),
        place("bus_h", at=[17, 16], container=True, p=0.9),
        place("bus_h", at=[29, 16], container=True, p=0.9),
        place("bus_h", at=[41, 16], container=True, p=0.9),
        place("bus_h", at=[5, 21], container=True, p=0.9),
        place("bus_h", at=[17, 21], container=True, p=0.9),
        place("bus_h", at=[29, 21], container=True, p=0.9),
        place("bus_h", at=[41, 21], container=True, p=0.8),
        scatter([4, 13, 48, 15], ["barrel", "trashcan", "crate"], 4, container=0.4),
        group([decals([4, 4, 48, 24], ["blood", "blood", "stain"], 16), scatter([4, 13, 48, 15], ["corpse"], 5)], if_="nest"),
        decals([4, 4, 48, 24], ["stain", "stain", "crack", "papers"], 12),
        place("pump", at=[50, 11], container=True),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=14, entry_hi=42), containers=(7, 14), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def school_annex():
    """The school annex: a prefab block of three classrooms, a nurse's room, a lunch hall and its kitchen, in a fenced yard with a chewed hole."""
    W, H = 52, 36
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        fence([3, 3, 46, 23], style="chain", under="YARD", gates=[{"side": "S", "at": R(14, 30), "w": 4}, {"side": "W", "at": R(14, 17), "w": 2, "hole": True}]),
        area([4, 16, 44, 9], "the yard", dead=1.0),
        building([6, 4, 40, 12], id="annex", wall="WALL_PLASTER", floor="LINO", doors=[door("S", 8, 3), door("S", 24, 3), door("S", 38, 3)]),
        split("annex", "v", 27, ["classes", "hall"], doors=[gap(R(10, 11), 2)]),
        split("hall", "h", 4, ["kitchen", "lunch"], names=["kitchen", "lunch hall"], floors=["KITCHEN", "LINO"], doors=[gap(R(4, 5))], dead=[1.0, 1.2]),
        split("classes", "h", 6, ["rooms", "corridor"], names=["", "corridor"], floors=["LINO", "TERRAZZO"], doors=[gap(R(2, 3)), gap(R(12, 13)), gap(R(21, 22))], dead=[1.0, 1.0]),
        split("rooms", "v", 9, ["class1", "rrest"], names=["classroom", ""], doors=[], dead=[1.0, 1.0]),
        split("rrest", "v", 8, ["class2", "nurse"], names=["classroom", "nurse's room"], floors=["LINO", "KITCHEN"], doors=[], dead=[1.0, 0.8]),
        line("corridor", "N", ["locker"], container=True, gap=(0, 1)),
        rows("class1", ["desk2"], pitch=2, margin=1, y0=2, n=2),
        place("teacherdesk", into="class1", anchor="NE", dx=-1),
        place("chalkboard", at=[8, 5], decor=True),
        rows("class2", ["desk2"], pitch=2, margin=1, y0=2, n=2),
        place("teacherdesk", into="class2", anchor="NE", dx=-1),
        place("chalkboard", at=[18, 5], decor=True),
        place("shelf_s", into="class1", anchor="SW", container=True),
        place("shelf_s", into="class2", anchor="SW", container=True),
        place("cot", into="nurse", anchor="NW", dx=1),
        place("cot", into="nurse", anchor="NE", dx=-1),
        place("cabinet", into="nurse", anchor="SW", container=True),
        place("cabinet", into="nurse", anchor="SE", container=True),
        place("rug2", into="class1", anchor="SE", p=0.5),
        kitchen_room("kitchen"),
        place("fridge", into="kitchen", anchor="SE", container=True),
        rows("lunch", ["longtable"], pitch=3, margin=1, y0=0, n=1),
        place("bench", into="lunch", anchor="SW", dx=1),
        # the yard
        place("foursquare", at=[10, 18]),
        place("hopscotch", at=[20, 17]),
        scatter([4, 16, 44, 9], ["picnic", "bench", "shrub", "trashcan"], 6, container=0.4),
        trees([4, 16, 44, 9], 2, on=["YARD"]),
        group([decals([4, 14, 44, 11], ["blood", "blood", "stain"], 12), scatter([4, 16, 44, 9], ["corpse"], 4)], if_="nest"),
        decals([4, 4, 44, 21], ["papers", "stain", "crack"], 8),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=14, entry_hi=36), containers=(5, 12), ops=ops + street_dressing(W, H))


def farm_a():
    """Hollis farm: a dairy at the end of a long lane: the house, a big barn with a milking parlour and a grain store, a well, and fields behind."""
    W, H = 56, 38
    ops = [
        fill([2, 2, W - 4, 11], "SOIL"),
        fill([2, 13, W - 4, 16], "DIRT"),
        area([2, 2, W - 4, 10], "fields", dead=0.5),
        area([2, 13, W - 4, 16], "farmyard", dead=1.0),
        {"op": "patch", "rect": [2, 13, W - 4, 16], "t": "GRASS", "n": 5, "r": [1.5, 3]},
        rows([4, 3, 48, 9], ["garden_h"], pitch=3, margin=1),
        line([2, 12, W - 4, 1], "N", ["shrub"], gap=(0, 1), skip=0.1),
        stamp(["house_a", "house_b"], [4, 17], id="farmhouse"),
        building([22, 13, 28, 14], id="barn", name="", wall="WALL_METAL", floor="DIRT", doors=[door("S", 6, 5), door("S", 20, 4), door("N", R(10, 16), 3)]),
        split("barn", "v", 13, ["parlour", "grain"], names=["milking parlour", "grain store"], floors=["CONCRETE", "DIRT"], doors=[gap(R(4, 8), 3)], dead=[1.0, 1.2]),
        line("parlour", "N", ["fridge", "waterpump", "fridge"], container=True, gap=(0, 1)),
        scatter("parlour", ["crate", "waterpack", "barrel", "rainbarrel"], 5, container=True, wall=True),
        rows("grain", ["shelf"], pitch=3, margin=1, y0=1, container=True, only=["food", "water"]),
        scatter("grain", ["cans", "cans", "crate", "waterpack", "cans"], 9, container=True, apart=0),
        decals("barn", ["stain", "papers", "blood"], 6),
        # the yard
        place("waterpump", at=[R(18, 20), R(14, 16)], container=True, jitter=2),
        scatter([2, 13, W - 4, 16], ["rainbarrel", "wheelbarrow", "compost", "trashbags", "crate", "tires", "barrel"], R(8, 12), container=0.35),
        place("clothesline", at=[R(8, 12), 15], p=0.6),
        trees([2, 13, W - 4, 16], 4, on=["GRASS", "DIRT"], gap=3),
        group([decals([2, 13, W - 4, 16], ["blood", "blood", "stain"], 10), scatter([2, 13, W - 4, 16], ["corpse"], 3)], if_="nest"),
        decals([2, 2, W - 4, 27], ["papers", "stain", "crack"], 8),
    ]
    return recipe([W, H], approach=dict(LANE, entry_lo=12, entry_hi=40), containers=(7, 15), ops=ops + [
        cars([3, H - 7, W - 6, 7], R(0, 1), container=0.6),
        scatter([2, H - 9, W - 4, 2], ["shrub", "hydrant"], R(3, 6)),
    ])


def farm_b():
    """Tern Hill farm: a small hill farm: the house, a barn, a root cellar and a hand pump, vegetable beds behind."""
    W, H = 46, 34
    ops = [
        fill([2, 2, W - 4, 9], "SOIL"),
        fill([2, 11, W - 4, 14], "DIRT"),
        area([2, 2, W - 4, 8], "fields", dead=0.5),
        area([2, 11, W - 4, 14], "farmyard", dead=1.0),
        {"op": "patch", "rect": [2, 11, W - 4, 14], "t": "GRASS", "n": 4, "r": [1.5, 3]},
        rows([4, 3, 38, 7], ["garden_h"], pitch=3, margin=1),
        line([2, 10, W - 4, 1], "N", ["shrub"], gap=(0, 1), skip=0.15),
        stamp(["house_b", "house_a"], [3, 13], id="farmhouse"),
        building([20, 12, 18, 12], id="barn", name="barn", wall="WALL_METAL", floor="DIRT", doors=[door("S", 5, 5), door("N", R(8, 10), 3)]),
        rows("barn", ["shelf"], pitch=3, margin=1, y0=1, container=True, only=["food", "water"]),
        scatter("barn", ["cans", "cans", "crate", "waterpack", "waterpack"], 8, container=True, apart=0),
        place("fridge", into="barn", anchor="NE", container=True),
        building([40, 14, 5, 5], id="cellar", name="root cellar", wall="WALL_PLASTER", floor="CONCRETE", doors=[door("S", 1, 2)]),
        scatter("cellar", ["cans", "cans", "crate"], 3, container=True, only=["food"]),
        place("waterpump", at=[18, 24 - 1], container=True),
        place("waterpump", at=[R(16, 19), R(14, 16)], container=True, jitter=2, p=0.6),
        scatter([2, 11, W - 4, 14], ["rainbarrel", "wheelbarrow", "compost", "trashbags", "crate", "tires"], R(6, 9), container=0.35),
        trees([2, 11, W - 4, 14], 3, on=["GRASS", "DIRT"], gap=3),
        decals([2, 2, W - 4, 23], ["papers", "stain", "crack"], 7),
    ]
    return recipe([W, H], approach=dict(LANE, entry_lo=12, entry_hi=32), containers=(5, 12), ops=ops + [
        cars([3, H - 7, W - 6, 7], R(0, 1), container=0.6),
        scatter([2, H - 9, W - 4, 2], ["shrub", "hydrant"], R(2, 4)),
    ])


def water_works():
    """The water works: three settling tanks, a pump hall with its control room, and a chemical store behind a mesh fence."""
    W, H = 54, 36
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        fence([3, 3, 48, 24], style="metal", t="WALL_METAL", gates=[{"side": "S", "at": R(14, 30), "w": 4}]),
        fill([4, 4, 46, 22], "CONCRETE"),
        area([4, 4, 46, 22], "the works", dead=1.0),
        block([6, 5, 12, 8], wall="WALL_PLASTER", roof="ROOF"),
        block([21, 5, 12, 8], wall="WALL_PLASTER", roof="ROOF"),
        block([36, 5, 12, 8], wall="WALL_PLASTER", roof="ROOF"),
        building([6, 15, 26, 10], id="hall", floor="CONCRETE", doors=[door("S", R(5, 8), 3), door("S", R(15, 18), 3), door("N", R(12, 14), 2)]),
        split("hall", "v", 18, ["pumps", "control"], names=["pump hall", "control room"], floors=["CONCRETE", "WOOD"], doors=[gap(R(3, 5))], dead=[1.3, 1.0]),
        line("pumps", "N", ["generator", "waterpump", "generator", "waterpump"], container=True, gap=(0, 1)),
        scatter("pumps", ["waterpump", "waterpack", "workbench", "crate", "waterpack"], 6, container=True, wall=True),
        office("control"),
        place("radiodesk", into="control", anchor="S", dy=-1),
        building([36, 15, 12, 10], id="chem", name="chemical store", wall="WALL_METAL", floor="CONCRETE", doors=[door("S", 4, 3)]),
        scatter("chem", ["barrel", "crate", "locker", "scrap", "barrel", "cabinet"], 8, container=True, wall=True),
        scatter([4, 13, 46, 2], ["barrel", "trashbags"], 3),
        scatter([4, 4, 46, 22], ["waterpump", "crate", "rainbarrel"], R(3, 5), container=0.5),
        decals([4, 4, 46, 22], ["stain", "stain", "papers", "crack"], 12),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=14, entry_hi=40), containers=(6, 13), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def bunker():
    """The civil defence bunker: a concrete door in a hillside, sandbags, and inside an armoury, stores, a dormitory, a control room and a surgery."""
    W, H = 50, 34
    ops = [
        fill([2, 2, W - 4, H - 11], "GRASS"),
        {"op": "patch", "rect": [2, 2, W - 4, 23], "t": "DIRT", "n": 8, "r": [2, 4]},
        fill([17, 19, 6, 6], "DIRT"),
        building([10, 3, 30, 16], id="bunker", wall="WALL_PLASTER", floor="CONCRETE", doors=[door("S", R(8, 10), 3)]),
        split("bunker", "h", 8, ["back", "front"], doors=[gap(4, 2), gap(11, 2), gap(22, 2)]),
        split("back", "v", 9, ["armoury", "brest"], names=["armoury", ""], dead=[1.4, 1.0]),
        split("brest", "v", 9, ["stores", "dorm"], names=["stores", "dormitory"], floors=["CONCRETE", "WOOD"], dead=[1.2, 1.0]),
        split("front", "v", 12, ["control", "medical"], names=["control room", "surgery"], floors=["WOOD", "LINO"], doors=[gap(R(1, 2))], dead=[1.0, 1.0]),
        rows("armoury", ["locker"], pitch=2, margin=1, container=True, y0=0),
        scatter("armoury", ["crate_ammo", "crate_ammo", "crate", "cabinet"], 6, container=True, wall=True),
        rows("stores", ["shelf"], pitch=3, margin=1, container=True),
        scatter("stores", ["cans", "waterpack", "cans", "waterpack", "crate"], 7, container=True, wall=True),
        rows("dorm", ["cot"], pitch=3, margin=1, y0=0, n=1),
        line("dorm", "S", ["locker"], container=True, gap=(0, 1), n=3),
        place("radiodesk", into="control", anchor="N", container=True),
        place("desk", into="control", anchor="SW", dx=1),
        place("desk2", into="control", anchor="SE", dx=-1),
        place("generator", into="control", anchor="E"),
        line("medical", "N", ["cabinet", "cabinet", "cot"], container=True, gap=(0, 1)),
        place("ivstand", into="medical", anchor="S"),
        place("sandbags", at=[R(11, 13), 20]),
        place("sandbags", at=[R(26, 28), 20]),
        scatter([2, 19, W - 4, 6], ["barrel", "crate", "sandbags"], 3, container=0.3),
        trees([2, 2, W - 4, 16], R(7, 10), on=["GRASS", "DIRT"], gap=2),
        decals("bunker", ["papers", "stain", "blood"], 8),
    ]
    return recipe([W, H], approach=dict(LANE, entry_lo=12, entry_hi=36), containers=(8, 16), ops=ops + [
        scatter([2, H - 9, W - 4, 2], ["shrub", "hydrant"], R(2, 4)),
    ])


def chain(base, dir, ids, sizes, names=None, floors=None, doors=None, wall="WALL_PLASTER", dead=None):
    """Splits a room into len(ids) rooms side by side (dir "v") or one above the other ("h"): sizes[i] is how wide or
    deep the i-th is (the last has what is left); names, floors and doors (a list of gap lists, one for each wall) are optional."""
    ops = []
    cur = base
    n = len(ids)
    for i in range(n - 1):
        last = i == n - 2
        nxt = ids[-1] if last else "%s~%d" % (base, i)
        nm = [names[i], names[-1] if last else ""] if names else None
        fl = [floors[i], floors[-1] if last else ""] if floors else None
        dd = [dead[i], dead[-1] if last else 1.0] if dead else None
        ops.append(split(cur, dir, sizes[i], [ids[i], nxt], names=nm, floors=fl, doors=(doors[i] if doors else []), wall=wall, dead=dd))
        cur = nxt
    return ops


def terrace_house():
    """A narrow terrace house: a front room on the street and a kitchen behind, a back door onto the alley."""
    ops = [
        building([0, 0, 6, 12], id="t", floor="WOOD", doors=[door("S", R(2, 3), 2), door("N", R(2, 3), 2)]),
        split("t", "h", 5, ["tn", "ts"], names=["kitchen", "front room"], floors=["KITCHEN", "WOOD"], doors=[gap(R(1, 2))], dead=[1.0, 1.0]),
        line("tn", "N", ["fridge", "counter2", "stove"], container=True, gap=(0, 0), n=3),
        place("shelf_s", into="tn", anchor="SW", container=True),
        place("rug", into="ts", anchor="C", p=0.6),
        line("ts", "N", ["bench", "shelf_s", "bed"], container=0.5, gap=(0, 1), n=2),
        place("lamp", into="ts", anchor="SE"),
        decals("t", ["papers", "stain", "blood"], R(1, 3)),
    ]
    return {"size": [6, 12], "ops": ops}


TEMPLATES["terrace_house"] = terrace_house()
TEMPLATES["terrace_shut"] = {"size": [6, 12], "ops": [block([0, 0, 6, 12], roof="ROOF_LIGHT")]}


def estate_house(lived=True):
    """A new-build house on the estate: four rooms, the front door kicked in. Half of them never lived in: bare floors."""
    ops = [
        building([0, 0, 11, 9], id="e", floor="WOOD", doors=[door("S", R(2, 4), 2), door("N", R(6, 8), 2)]),
        split("e", "v", 4, ["w", "e"], doors=[gap(R(4, 5))]),
        split("w", "h", 3, ["wn", "ws"], names=["bedroom", "living room"], floors=["WOOD", "WOOD"], doors=[gap(R(1, 2))], dead=[1.0, 1.0]),
        split("e", "h", 3, ["en", "es"], names=["bathroom", "kitchen"], floors=["KITCHEN", "KITCHEN"], doors=[gap(R(1, 3))], dead=[1.0, 1.0]),
    ]
    if lived:
        ops += [
            place("bed", into="wn", anchor="NW"),
            place("shelf_s", into="wn", anchor="NE", container=True),
            place("rug", into="ws", anchor="C", p=0.6),
            line("ws", "N", ["bench", "shelf_s"], container=0.5, gap=(0, 1), n=2),
            place("cabinet", into="en", anchor="NE", container=True),
            line("es", "N", ["fridge", "counter2", "stove"], container=True, gap=(0, 0), n=3),
            place("desk2", into="es", anchor="SE"),
            decals("e", ["papers", "stain", "blood"], R(1, 3)),
        ]
    else:
        ops += [decals("e", ["stain", "crack"], 2)]
    return {"size": [11, 9], "ops": ops}


TEMPLATES["estate_lived"] = estate_house(True)
TEMPLATES["estate_bare"] = estate_house(False)


def terraces():
    """Millbank terraces: a long row of narrow houses on the street, every kitchen the same, an alley behind them."""
    W, H = 52, 34
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        fill([2, 24, W - 4, 1], "SIDEWALK"),
        block([2, 2, W - 4, 7], roof="ROOF_LIGHT"),
        area([2, 9, W - 4, 4], "back alley", dead=0.8),
    ]
    for k in range(8):
        ops.append(stamp(["terrace_house"] * 6 + ["terrace_shut"], [5 + 5 * k, 13], id="t%d" % k))
    ops += [
        scatter([2, 9, W - 4, 4], ["trashcan", "trashbags", "barrel", "crate", "wheelbarrow"], R(7, 10), container=0.4, apart=1),
        scatter([2, 25, W - 4, 2], ["trashcan", "trashbags"], 2),
        decals([2, 9, W - 4, 17], ["papers", "blood", "stain"], 12),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=40), containers=(7, 14), ops=ops + street_dressing(W, H))


def estate():
    """Larkfield estate: two rows of new houses, half of them never lived in, doors kicked in, cars left on the drives."""
    W, H = 56, 36
    ops = [
        fill([2, 2, W - 4, H - 11], "GRASS"),
        fill([2, 14, W - 4, 3], "ASPHALT"),
        area([2, 14, W - 4, 3], "the close", dead=0.8),
        area([2, 26, W - 4, 1], "front gardens", dead=0.4),
    ]
    for k in range(4):
        ops.append(stamp(["estate_lived", "estate_lived", "estate_bare"], [R(3 + 13 * k, 4 + 13 * k), 5], id="n%d" % k))
        ops.append(stamp(["estate_lived", "estate_lived", "estate_bare"], [R(3 + 13 * k, 4 + 13 * k), 17], id="s%d" % k))
    ops += [
        cars([2, 14, W - 4, 3], R(2, 3), container=0.6, kinds=["car_h"]),
        scatter([2, 26, W - 4, 1], ["shrub", "trashcan", "trashbags"], R(4, 7), container=0.4),
        scatter([2, 2, W - 4, 3], ["shrub", "trashbags"], 5),
        trees([2, 2, W - 4, 24], R(5, 8), on=["GRASS"], gap=3),
        decals([2, 2, W - 4, 25], ["papers", "blood", "stain"], 9),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=40), containers=(7, 14), ops=ops + street_dressing(W, H))


def flats():
    """Flats: a slab of eight small flats either side of a corridor, a lobby at the front with the letterboxes."""
    W, H = 52, 36
    top = [4, 15, 26, 37]
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        building([4, 5, 44, 22], id="flats", floor="TERRAZZO", wall="WALL_BRICK", doors=[door("S", 18, 4), door("E", 10, 2)]),
        split("flats", "h", 8, ["nflats", "rest"], doors=[gap(4), gap(15), gap(26), gap(36)]),
        split("rest", "h", 3, ["corridor", "sflats"], names=["corridor", ""], floors=["TERRAZZO", "WOOD"], doors=[gap(4), gap(15), gap(26), gap(36)]),
        chain("nflats", "v", ["n1", "n2", "n3", "n4"], [10, 10, 10], names=["flat", "flat", "flat", "flat"], floors=["WOOD"] * 4),
        chain("sflats", "v", ["s1", "s2", "s3", "s4"], [10, 10, 10], names=["flat", "lobby", "flat", "flat"], floors=["WOOD", "TERRAZZO", "WOOD", "WOOD"]),
    ]
    for f in ["n1", "n2", "n3", "n4"]:
        ops += [
            place("bed", into=f, anchor="NW", dx=1),
            place("shelf_s", into=f, anchor="NE", container=True),
            line(f, "S", ["fridge", "counter2", "stove"], container=True, gap=(0, 0), n=3),
            place("rug", into=f, anchor="C", p=0.6),
            place("desk2", into=f, anchor="E", dx=-1),
            decals(f, ["papers", "stain"], R(1, 3)),
        ]
    for f in ["s1", "s3", "s4"]:
        ops += [
            place("bed", into=f, anchor="SW", dx=1),
            place("shelf_s", into=f, anchor="SE", container=True),
            line(f, "N", ["fridge", "counter2", "stove"], container=True, gap=(0, 0), n=3),
            place("rug", into=f, anchor="C", p=0.6),
            decals(f, ["papers", "stain"], R(1, 3)),
        ]
    ops += [
        line("s2", "S", ["locker"], container=True, gap=(0, 0), n=6),
        place("bench", into="s2", anchor="N", dx=-2),
        place("lamp", into="s2", anchor="NE"),
        line("corridor", "N", ["locker", "cabinet"], container=0.5, gap=(2, 4), n=4),
        scatter([2, 2, W - 4, 3], ["shrub", "trashcan", "trashbags"], 5, container=0.3),
        trees([2, 2, W - 4, 3], 4, on=["YARD", "GRASS"]),
        decals([4, 5, 44, 22], ["papers", "blood", "stain"], 10),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=40), containers=(7, 14), ops=ops + street_dressing(W, H))


def lanes(rect, dir="h", **kw):
    d = {"op": "lanes", "rect": rect, "dir": dir}
    d.update(kw)
    return d


def checkpoint():
    """The checkpoint: the road shut with sandbags and concrete, a guard post and an armoury either side, a tent camp, wrecks in the road."""
    W, H = 46, 32
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        fill([14, 2, 18, 23], "ASPHALT"),
        lanes([14, 2, 18, 21], "v"),
        area([14, 2, 18, 21], "the road", dead=1.2),
        line([14, 9, 18, 1], "N", ["sandbags"], gap=(0, 2)),
        line([14, 14, 18, 1], "N", ["sandbags"], gap=(1, 3), start=2),
        place("blocks_v", at=[18, 4], jitter=2),
        place("blocks_v", at=[27, 10], jitter=2),
        building([4, 6, 9, 7], id="post", name="guard post", wall="WALL_PLASTER", floor="CONCRETE", doors=[door("E", 2, 2)]),
        place("desk", into="post", anchor="NW", dx=1),
        line("post", "S", ["locker", "locker"], container=True, gap=(0, 0)),
        place("crate_ammo", into="post", anchor="NE", container=True),
        building([33, 6, 9, 7], id="armoury", name="armoury", wall="WALL_PLASTER", floor="CONCRETE", doors=[door("W", 2, 2)]),
        line("armoury", "N", ["crate_ammo", "crate_ammo", "locker"], container=True, gap=(0, 0)),
        line("armoury", "S", ["locker", "cabinet"], container=True, gap=(0, 1)),
        area([3, 15, 10, 9], "west camp", dead=0.8),
        area([33, 15, 10, 9], "east camp", dead=0.8),
        scatter([3, 15, 10, 9], ["tent", "tent"], 2),
        scatter([3, 15, 10, 9], ["barrel", "crate", "crate_ammo", "sandbags"], 5, container=0.6),
        scatter([33, 15, 10, 9], ["tent", "generator"], 2),
        scatter([33, 15, 10, 9], ["barrel", "crate", "crate_ammo", "sandbags", "locker"], 5, container=0.6),
        cars([14, 3, 18, 20], R(4, 6), container=0.7, kinds=["car_v", "car_h", "pickup_v"]),
        scatter([14, 2, 18, 21], ["corpse"], R(3, 5)),
        decals([2, 2, W - 4, 22], ["blood", "blood", "stain", "papers", "crack"], 22),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=10, entry_hi=36), containers=(7, 14), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def cold_store():
    """The cold store: three cold rooms of racking and cabinets behind a loading dock, all white tile and frost."""
    W, H = 56, 36
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        building([4, 6, 48, 21], id="cs", floor="KITCHEN", wall="WALL_PLASTER", doors=[door("S", R(6, 10), 5), door("S", R(28, 32), 5), door("N", R(20, 24), 3)]),
        split("cs", "h", 13, ["chambers", "dock"], names=["", "loading dock"], floors=["KITCHEN", "CONCRETE"], doors=[gap(6, 3), gap(22, 3), gap(38, 3)], dead=[1.0, 1.0]),
        chain("chambers", "v", ["c1", "c2", "c3"], [15, 15], names=["cold room", "cold room", "cold room"], floors=["KITCHEN"] * 3,
              doors=[[gap(R(5, 8), 2)], [gap(R(5, 8), 2)]], dead=[1.3, 1.3, 1.5]),
    ]
    for c in ("c1", "c2", "c3"):
        ops += [
            line(c, "N", ["fridge"], container=True, gap=(0, 0)),
            rows(c, ["shelf"], pitch=3, margin=1, y0=3, container=True, only=["food", "water"]),
            scatter(c, ["cans", "waterpack", "crate", "cans"], 4, container=True, apart=0),
        ]
    ops += [
        scatter("dock", ["crate", "cans", "waterpack", "trashbags", "barrel"], 8, container=0.7, wall=True),
        place("desk", into="dock", anchor="SW", dx=1),
        group([decals("c3", ["blood", "blood", "stain"], 12), scatter("c3", ["corpse"], 5)], if_="nest"),
        decals([4, 6, 48, 21], ["stain", "papers"], 8),
        place("cont_green_v", at=[2, 6], container=True, ckind="trunk", p=0.7),
        place("cont_orange_v", at=[51, 7], container=True, ckind="trunk", p=0.7),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=44), containers=(7, 15), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def hospital():
    """The hospital: reception and the emergency room at the front, four wards behind a long corridor, theatre, pharmacy, laboratory and morgue at the back."""
    W, H = 56, 40
    ops = [
        fill([2, 2, W - 4, H - 11], "GRASS"),
        building([3, 5, 50, 26], id="hosp", floor="LINO", wall="WALL_BRICK", doors=[door("S", R(10, 14), 4), door("S", R(36, 40), 4), door("E", 21, 3)]),
        split("hosp", "h", 7, ["back", "r1"], doors=[gap(5, 2), gap(18, 2), gap(30, 2), gap(41, 2)]),
        split("r1", "h", 3, ["corr", "r2"], names=["corridor", ""], floors=["TERRAZZO", "LINO"], doors=[gap(5, 2), gap(17, 2), gap(29, 2), gap(41, 2)], dead=[1.2, 1.0]),
        split("r2", "h", 6, ["wards", "front"], doors=[gap(8, 3), gap(20, 2), gap(36, 3)]),
        chain("back", "v", ["ph", "op", "lab", "morgue"], [12, 12, 10], names=["pharmacy", "operating theatre", "laboratory", "morgue"],
              floors=["TERRAZZO", "KITCHEN", "LINO", "KITCHEN"], dead=[1.3, 1.0, 1.0, 1.2]),
        chain("wards", "v", ["w1", "w2", "w3", "w4"], [11, 11, 11], names=["ward", "ward", "ward", "ward"], floors=["LINO"] * 4, dead=[1.1] * 4),
        chain("front", "v", ["recep", "er"], [28], names=["reception", "emergency room"], floors=["TERRAZZO", "LINO"], doors=[[gap(R(1, 3), 2)]], dead=[1.2, 1.2]),
        line("ph", "N", ["cabinet"], container=True, gap=(0, 0)),
        rows("ph", ["shelf"], pitch=3, margin=1, y0=3, container=True),
        place("cot", into="op", anchor="C"),
        place("ivstand", into="op", anchor="C", dx=-2),
        place("ivstand", into="op", anchor="C", dx=2),
        line("op", "N", ["cabinet"], container=True, gap=(1, 2), n=3),
        rows("lab", ["workbench"], pitch=3, margin=1, y0=1, container=True),
        line("lab", "S", ["cabinet", "locker"], container=0.7, gap=(0, 1), n=4),
        line("morgue", "N", ["fridge"], container=True, gap=(0, 0)),
        rows("morgue", ["cot"], pitch=3, margin=1, y0=3, n=1),
        line("corr", "N", ["ivstand", "bench"], gap=(3, 5)),
        line("corr", "S", ["cabinet"], container=0.6, gap=(3, 6), n=3),
        place("counter", into="recep", anchor="N", dx=3, dy=2, container=True),
        rows("recep", ["bench"], pitch=2, margin=1, y0=3, n=2, gap_every=3),
        line("er", "N", ["cot", "cot", "cabinet"], gap=(1, 1), container=0.6, n=7),
        place("ivstand", into="er", anchor="SW", dx=2),
        place("lamp", into="recep", anchor="SW"),
        place("van_h", at=[R(36, 44), 31], container=True, jitter=1),
    ]
    for w in ("w1", "w2", "w3", "w4"):
        ops += [
            line(w, "N", ["cot"], gap=(1, 1), n=4),
            line(w, "S", ["cot"], gap=(1, 1), n=3),
            place("cabinet", into=w, anchor="E", container=True),
            place("ivstand", into=w, anchor="W", dx=1),
        ]
    ops += [
        trees([2, 2, W - 4, 3], 4, on=["GRASS"]),
        decals([3, 5, 50, 26], ["blood", "papers", "stain", "blood"], 18),
        scatter([4, 6, 48, 24], ["corpse"], R(3, 5)),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=44), containers=(10, 22), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def mall_unit(id, kind):
    """What stands in one shop unit of the mall."""
    if kind == "clothes":
        return [rows(id, ["shelf"], pitch=3, margin=1, y0=1, container=True), place("counter2", into=id, anchor="SW", container=True), place("rug", into=id, anchor="S", p=0.5)]
    if kind == "electronics":
        return [line(id, "N", ["shelf", "shelf_s"], container=True, gap=(0, 1)), line(id, "S", ["counter2", "counter2"], container=True, gap=(1, 2), n=2), scatter(id, ["crate", "desk"], 2, container=0.5, wall=True)]
    if kind == "toys":
        return [place("rug2", into=id, anchor="C"), line(id, "N", ["shelf"], container=True, gap=(0, 0)), scatter(id, ["crate", "cans"], 3, container=True, wall=True)]
    if kind == "pharmacy":
        return [line(id, "N", ["cabinet", "cabinet", "cabinet"], container=True, gap=(0, 0)), place("counter2", into=id, anchor="S", container=True), scatter(id, ["shelf_s"], 2, container=True, wall=True)]
    if kind == "food":
        return [line(id, "N", ["fridge", "stove", "counter2", "fridge"], container=True, gap=(0, 0)), rows(id, ["desk2"], pitch=2, margin=1, y0=3, n=2, gap_every=2)]
    if kind == "grocer":
        return [line(id, "N", ["fridge", "fridge", "shelf_s"], container=True, gap=(0, 0)), rows(id, ["shelf"], pitch=3, margin=1, y0=3, container=True), scatter(id, ["cans", "waterpack"], 3, container=True, apart=0)]
    if kind == "hall":
        return [place("rug2", into=id, anchor="C"), place("bench", into=id, anchor="N", dx=-2), place("lamp", into=id, anchor="NE"), scatter(id, ["shrub"], 2)]
    return [scatter(id, ["crate", "shelf"], 4, container=True, wall=True)]


def mall():
    """The mall: a car park, a long concourse with benches and planters, five units either side (a grocer, a pharmacy, a food court...)."""
    W, H = 56, 40
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        area([2, 27, W - 4, 4], "car park", dead=1.0),
        building([3, 5, 50, 22], id="mall", floor="TERRAZZO", wall="WALL_BRICK", doors=[door("S", 22, 6), door("N", R(20, 28), 3)]),
        split("mall", "h", 7, ["nrow", "r1"], doors=[gap(4, 2), gap(14, 2), gap(24, 2), gap(34, 2), gap(43, 2)]),
        split("r1", "h", 4, ["concourse", "srow"], names=["concourse", ""], floors=["TERRAZZO", "LINO"], doors=[gap(4, 2), gap(14, 2), gap(21, 6), gap(34, 2), gap(43, 2)], dead=[1.2, 1.0]),
        chain("nrow", "v", ["n1", "n2", "n3", "n4", "n5"], [9, 9, 9, 9], names=["grocer", "clothes shop", "electronics shop", "toy shop", "pharmacy"], floors=["LINO"] * 5, dead=[1.0] * 5),
        chain("srow", "v", ["s1", "s2", "s3", "s4", "s5"], [9, 9, 9, 9], names=["clothes shop", "electronics shop", "entrance hall", "food court", "grocer"], floors=["LINO", "LINO", "TERRAZZO", "KITCHEN", "LINO"], dead=[1.0] * 5),
    ]
    for uid, kind in (("n1", "grocer"), ("n2", "clothes"), ("n3", "electronics"), ("n4", "toys"), ("n5", "pharmacy"), ("s1", "clothes"), ("s2", "electronics"), ("s3", "hall"), ("s4", "food"), ("s5", "grocer")):
        ops += mall_unit(uid, kind)
    ops += [
        line("concourse", "N", ["bench", "shrub"], gap=(2, 4)),
        line("concourse", "S", ["bench", "shrub"], gap=(2, 4)),
        place("rug2", into="concourse", anchor="C", dx=-12),
        place("rug2", into="concourse", anchor="C", dx=12),
        cars([3, 27, W - 6, 4], R(8, 11), container=0.5),
        place("van_h", at=[R(20, 40), 28], container=True, jitter=2, if_="vehicle"),
        scatter([2, 27, W - 4, 4], ["trashcan", "trashbags", "bench", "lamppost"], 6, container=0.3),
        decals([2, 27, W - 4, 4], ["blood", "blood", "stain", "papers"], 16),
        decals([3, 5, 50, 22], ["papers", "stain", "blood"], 14),
        trees([2, 2, W - 4, 3], 4, on=["YARD", "GRASS"]),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=44), containers=(9, 18), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def university():
    """The university: a quad of lawn and paths between a lecture hall, a library, the laboratories and the admin block."""
    W, H = 56, 40
    ops = [
        fill([2, 2, W - 4, H - 11], "GRASS"),
        fill([27, 5, 3, 26], "CONCRETE"),
        fill([4, 18, 48, 3], "CONCRETE"),
        area([2, 2, W - 4, 29], "the quad", dead=1.0),
        building([4, 5, 22, 12], id="lecture", name="lecture hall", floor="WOOD", doors=[door("S", R(8, 12), 3), door("E", 5, 2)]),
        building([31, 5, 21, 12], id="lib", name="library", floor="TERRAZZO", doors=[door("S", R(6, 10), 3), door("W", 5, 2)]),
        building([4, 22, 20, 9], id="labs", name="laboratory", floor="LINO", doors=[door("N", R(6, 10), 3)]),
        building([32, 22, 20, 9], id="admin", floor="WOOD", doors=[door("N", R(6, 10), 3), door("S", R(8, 10), 2)]),
        chain("admin", "v", ["a1", "a2", "a3"], [5, 5], names=["office", "office", "records room"], floors=["WOOD"] * 3, doors=[[gap(R(5, 5), 2)], [gap(R(5, 5), 2)]], dead=[1.0] * 3),
        rows("lecture", ["desk2"], pitch=2, margin=1, y0=3),
        place("teacherdesk", into="lecture", anchor="N", dy=0),
        place("chalkboard", at=[10, 5], decor=True),
        line("lecture", "S", ["shelf_s", "cabinet"], container=True, gap=(0, 3), n=3),
        rows("lib", ["shelf"], pitch=3, margin=1, y0=1, container=0.3, only=["scrap", "meds"]),
        place("counter", into="lib", anchor="SW", dx=1, container=True, only=["scrap"]),
        place("longtable", into="lib", anchor="SE", dx=-2, dy=-1),
        rows("labs", ["workbench"], pitch=3, margin=1, y0=1, container=True),
        line("labs", "S", ["cabinet", "locker", "locker"], container=True, gap=(0, 1)),
        place("ivstand", into="labs", anchor="E"),
        place("shelf_s", into="a1", anchor="NE", container=True),
        place("desk", into="a1", anchor="SW"),
        place("locker", into="a2", anchor="NE", container=True),
        place("desk", into="a2", anchor="SW"),
        line("a3", "N", ["shelf_s", "locker"], container=True, gap=(0, 0)),
        scatter([2, 2, W - 4, 29], ["bench", "shrub", "shrub", "trashcan"], R(10, 14), container=0.2),
        trees([2, 2, W - 4, 29], R(8, 11), on=["GRASS"], gap=3),
        decals([2, 2, W - 4, 29], ["papers", "blood", "stain"], 14),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=44), containers=(8, 16), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def power_station():
    """The power station: a turbine hall of generators in rows, a transformer yard, a control building and heaps of scrap, behind a fence."""
    W, H = 56, 40
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        fence([3, 3, 50, 28], style="metal", gates=[{"side": "S", "at": R(30, 40), "w": 5}]),
        fill([4, 4, 48, 26], "CONCRETE"),
        area([4, 4, 48, 26], "the works", dead=1.0),
        building([6, 5, 30, 14], id="turbine", name="turbine hall", wall="WALL_METAL", floor="CONCRETE", doors=[door("S", R(6, 10), 4), door("S", R(18, 22), 4), door("E", 6, 3)]),
        rows("turbine", ["generator"], pitch=3, margin=2, y0=1, gap_every=2),
        line("turbine", "N", ["workbench"], container=True, gap=(1, 2), n=3),
        scatter("turbine", ["locker", "crate", "tires", "barrel"], 8, container=True, wall=True),
        decals("turbine", ["stain", "stain", "papers"], 8),
        area([38, 5, 13, 14], "transformer yard", dead=0.8),
        scatter([38, 5, 13, 14], ["generator", "ibc", "barrel", "scrap", "generator"], 10, container=0.5),
        building([6, 22, 20, 7], id="control", name="control room", wall="WALL_PLASTER", floor="WOOD", doors=[door("N", R(6, 10), 3)]),
        place("radiodesk", into="control", anchor="N", dx=-4),
        place("radiodesk", into="control", anchor="N", dx=4),
        rows("control", ["desk"], pitch=2, margin=1, y0=3, n=2, gap_every=4),
        line("control", "S", ["locker", "cabinet"], container=True, gap=(0, 1)),
        scatter([28, 22, 22, 8], ["scrap"], R(5, 7), container=True, apart=1),
        scatter([28, 22, 22, 8], ["tires", "barrel", "crate"], 4, container=0.4),
        cars([4, 20, 48, 10], R(1, 2), container=True, kinds=["car_h"]),
        group([decals([4, 4, 48, 26], ["blood", "blood", "stain"], 14), scatter([4, 4, 48, 26], ["corpse"], 5)], if_="nest"),
        decals([4, 4, 48, 26], ["stain", "stain", "crack", "papers"], 14),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=44), containers=(8, 16), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def fuel_depot():
    """The fuel depot: four storage tanks in a bund, a loading rack of pumps under a canopy, tankers waiting, an office, behind a fence."""
    W, H = 54, 36
    ops = [
        fill([2, 2, W - 4, H - 11], "YARD"),
        fence([3, 3, 48, 24], style="metal", gates=[{"side": "S", "at": R(24, 36), "w": 5}]),
        fill([4, 4, 46, 22], "CONCRETE"),
        area([4, 4, 46, 22], "the depot", dead=1.0),
        block([6, 5, 9, 9], wall="WALL_PLASTER", roof="ROOF"),
        block([17, 5, 9, 9], wall="WALL_PLASTER", roof="ROOF"),
        block([28, 5, 9, 9], wall="WALL_PLASTER", roof="ROOF"),
        block([39, 5, 9, 9], wall="WALL_PLASTER", roof="ROOF"),
        line([6, 16, 40, 1], "N", ["pump"], container=True, gap=(2, 3), n=9),
        fill([6, 14, 1, 1], "WALL_METAL", solid=True),
        fill([46, 14, 1, 1], "WALL_METAL", solid=True),
        fill([6, 19, 1, 1], "WALL_METAL", solid=True),
        fill([46, 19, 1, 1], "WALL_METAL", solid=True),
        place("awning_r", at=[7, 14]),
        place("awning_g", at=[14, 14]),
        place("awning_b", at=[22, 14]),
        place("awning_r", at=[29, 14]),
        place("awning_g", at=[36, 14]),
        place("awning_b", at=[7, 19]),
        place("awning_g", at=[14, 19]),
        place("awning_r", at=[22, 19]),
        place("awning_b", at=[29, 19]),
        place("awning_r", at=[36, 19]),
        building([5, 21, 16, 5], id="office", name="depot office", wall="WALL_PLASTER", floor="WOOD", doors=[door("S", 3, 2), door("E", 2, 2)]),
        place("desk", into="office", anchor="NW", dx=1),
        place("locker", into="office", anchor="NE", container=True),
        place("counter2", into="office", anchor="SE", container=True),
        place("cont_blue", at=[R(24, 28), 22], container=True, ckind="trunk", jitter=1),
        place("cont_blue", at=[R(34, 38), 22], container=True, ckind="trunk", jitter=1),
        place("van_h", at=[R(40, 44), 21], container=True, jitter=1, p=0.5),
        scatter([4, 4, 46, 22], ["barrel", "ibc", "crate", "trashcan"], 8, container=0.3),
        decals([4, 4, 46, 22], ["stain", "stain", "stain", "crack", "papers"], 16),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=40), containers=(5, 12), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def rail_yard():
    """The rail yard: goods wagons in rows on the gravel, an engine shed, a signal box, heaps of scrap between, behind a fence."""
    W, H = 56, 36
    ops = [
        fill([2, 2, W - 4, H - 11], "DIRT"),
        fence([3, 3, 50, 24], style="metal", gates=[{"side": "S", "at": R(14, 34), "w": 5}]),
        area([4, 4, 48, 22], "the sidings", dead=1.0),
        {"op": "patch", "rect": [4, 4, 48, 22], "t": "SOIL", "n": 10, "r": [1.5, 3.5]},
        place("cont_red", at=[5, 5], container=True, ckind="trunk"),
        place("cont_red", at=[18, 5], container=True, ckind="trunk", p=0.9),
        place("cont_blue", at=[31, 5], container=True, ckind="trunk"),
        place("cont_red", at=[38, 5], container=True, ckind="trunk", p=0.9),
        place("cont_blue", at=[5, 10], container=True, ckind="trunk", p=0.9),
        place("cont_red", at=[12, 10], container=True, ckind="trunk"),
        place("cont_red", at=[25, 10], container=True, ckind="trunk", p=0.9),
        place("cont_blue", at=[38, 10], container=True, ckind="trunk"),
        place("cont_red", at=[R(44, 45), 10], p=0.5),
        building([32, 16, 20, 9], id="shed", name="engine shed", wall="WALL_METAL", floor="CONCRETE", doors=[door("S", 6, 4), door("W", 3, 2)]),
        line("shed", "N", ["workbench"], container=True, gap=(1, 2), n=2),
        scatter("shed", ["tires", "locker", "crate", "barrel", "scrap"], 7, container=True, wall=True),
        building([5, 19, 9, 6], id="box", name="signal box", wall="WALL_PLASTER", floor="WOOD", doors=[door("E", 2, 2)]),
        place("radiodesk", into="box", anchor="N", container=True),
        place("locker", into="box", anchor="SW", container=True),
        scatter([4, 15, 27, 11], ["scrap"], R(6, 8), container=True, apart=1),
        scatter([4, 14, 27, 12], ["tires", "barrel", "crate"], 5, container=0.3),
        cars([4, 14, 27, 11], R(1, 2), container=0.6, kinds=["car_h", "pickup_v"]),
        group([decals([4, 4, 48, 22], ["blood", "blood", "stain"], 14), scatter([4, 4, 48, 22], ["corpse"], 4)], if_="nest"),
        decals([4, 4, 48, 22], ["stain", "stain", "crack", "papers"], 12),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=44), containers=(8, 16), ops=ops + street_dressing(W, H, cars_n=R(1, 2)))


def bridge():
    """The river bridge: a road deck over dark water with railings, wrecks and sandbags across it, a toll house on the bank. Nothing to find."""
    W, H = 46, 32
    ops = [
        fill([0, 0, W, H - 9], "ROOF", solid=True),
        fill([0, 16, 16, 7], "GRASS"),
        fill([30, 16, 16, 7], "GRASS"),
        fill([16, 0, 14, 25], "ASPHALT"),
        lanes([16, 0, 14, 23], "v"),
        fill([15, 0, 1, 16], "WALL_METAL", solid=True),
        fill([30, 0, 1, 16], "WALL_METAL", solid=True),
        area([16, 0, 14, 23], "the bridge", dead=1.2),
        line([16, 4, 14, 1], "N", ["sandbags"], gap=(0, 2)),
        cars([16, 5, 14, 17], R(4, 6), container=0, kinds=["car_v", "pickup_v"]),
        building([2, 16, 11, 7], id="toll", name="toll house", wall="WALL_BRICK", floor="WOOD", doors=[door("S", 3, 2), door("E", 2, 2)]),
        place("desk", into="toll", anchor="NW", dx=1),
        place("lamp", into="toll", anchor="SE"),
        scatter([31, 16, 14, 7], ["shrub", "trashcan"], 4),
        trees([31, 16, 14, 7], 3, on=["GRASS"]),
        scatter([16, 5, 14, 17], ["corpse"], R(2, 4)),
        decals([16, 0, 14, 23], ["blood", "stain", "crack", "papers"], 14),
    ]
    return recipe([W, H], approach=dict(STREET, entry_lo=12, entry_hi=33), border=None, containers=(0, 0), ops=ops + [
        scatter([2, H - 9, W - 4, 2], ["hydrant", "lamppost"], 3),
    ])


RECIPES["houses"] = houses()
RECIPES["pharmacy"] = pharmacy()
RECIPES["bakery"] = bakery()
RECIPES["hardware"] = hardware()
RECIPES["radio_shop"] = radio_shop()
RECIPES["library"] = library()
RECIPES["clinic"] = clinic()
RECIPES["church"] = church()
RECIPES["fire_station"] = fire_station()
RECIPES["police"] = police()
RECIPES["gas_station"] = gas_station()
RECIPES["truck_stop"] = truck_stop()
RECIPES["garage"] = garage()
RECIPES["supermarket"] = supermarket()
RECIPES["warehouse"] = warehouse()
RECIPES["scrapyard"] = scrapyard()
RECIPES["bus_depot"] = bus_depot()
RECIPES["school_annex"] = school_annex()
RECIPES["farm_a"] = farm_a()
RECIPES["farm_b"] = farm_b()
RECIPES["water_works"] = water_works()
RECIPES["bunker"] = bunker()
RECIPES["terraces"] = terraces()
RECIPES["estate"] = estate()
RECIPES["flats"] = flats()
RECIPES["checkpoint"] = checkpoint()
RECIPES["cold_store"] = cold_store()
RECIPES["hospital"] = hospital()
RECIPES["mall"] = mall()
RECIPES["university"] = university()
RECIPES["power_station"] = power_station()
RECIPES["fuel_depot"] = fuel_depot()
RECIPES["rail_yard"] = rail_yard()
RECIPES["bridge"] = bridge()

RECIPES["generic"] = recipe(
    [46, 32], approach=dict(STREET, entry_lo=14, entry_hi=30),
    ops=[
        fill([2, 2, 42, 21], "YARD"),
        building([8, 6, 30, 16], id="hall", name="hall", floor="CONCRETE", doors=[door("S", R(8, 20), 3)]),
        scatter("hall", ["crate", "shelf", "locker", "cabinet", "fridge"], 14, container=True, wall=True),
    ] + street_dressing(46, 32))

def main():
    doc = {
        "version": 1,
        "_doc": "The layouts of the raid sites (round 14): written by tools/make_site_layouts.py, read by scripts/raid/site_gen.gd. terrain: the wall and door ground made for sites (tools/make_site_art.py), added to the map's terrainTypes. caps, affinity, search: how many containers the loot calls for, which kind of container holds which stock, and how many seconds each takes. props: the catalogue (files in assets/<dir>, tiles: the footprint, dw/dh: the drawn size in tiles, ppt: pixels to the tile, layer, solid, loose: a flat thing that shuts nothing, container: the kind of container it can be, only: the stocks it can hold). templates and recipes: lists of ops (scripts/raid/site_canvas.gd), a recipe for each kind of place and for a few places that have their own.",
        "terrain": TERRAIN,
        "caps": CAPS,
        "affinity": AFFINITY,
        "search": SEARCH,
        "aliases": ALIASES,
        "props": PROPS,
        "templates": TEMPLATES,
        "recipes": RECIPES,
    }
    text = dump(doc)
    with open(OUT, "w") as f:
        f.write(text)
    print("wrote", OUT, len(text), "bytes;", len(RECIPES), "recipes,", len(TEMPLATES), "templates,", len(PROPS), "props")


def flat(ops):
    """Ops written as helper calls may come as lists of ops: one flat list (groups included). `if_` is the op's `if`."""
    out = []
    for o in ops:
        if isinstance(o, list):
            out.extend(flat(o))
        else:
            o = dict(o)
            for k in ("if_", "if_not_"):
                if k in o:
                    o[k[:-1]] = o.pop(k)
            if o.get("op") == "group":
                o["ops"] = flat(o["ops"])
            out.append(o)
    return out


def dump(doc):
    """JSON with one op to a line, so that a layout reads (and diffs) like a list."""
    out = ["{"]
    keys = list(doc.keys())
    for ki, k in enumerate(keys):
        v = doc[k]
        comma = "," if ki < len(keys) - 1 else ""
        if k in ("props", "terrain", "caps", "affinity", "search", "aliases"):
            out.append('  %s: {' % json.dumps(k))
            items = list(v.items())
            for i, (pk, pv) in enumerate(items):
                out.append("    %s: %s%s" % (json.dumps(pk), json.dumps(pv), "," if i < len(items) - 1 else ""))
            out.append("  }" + comma)
        elif k in ("templates", "recipes"):
            out.append('  %s: {' % json.dumps(k))
            items = list(v.items())
            for i, (rk, rv) in enumerate(items):
                out.append("    %s: {" % json.dumps(rk))
                fields = [f for f in rv.keys() if f != "ops"]
                for f in fields:
                    out.append("      %s: %s," % (json.dumps(f), json.dumps(rv[f])))
                out.append('      "ops": [')
                ops = flat(rv["ops"])
                for oi, o in enumerate(ops):
                    out.append("        %s%s" % (json.dumps(o), "," if oi < len(ops) - 1 else ""))
                out.append("      ]")
                out.append("    }" + ("," if i < len(items) - 1 else ""))
            out.append("  }" + comma)
        else:
            out.append("  %s: %s%s" % (json.dumps(k), json.dumps(v), comma))
    out.append("}")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    main()
