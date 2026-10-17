## EXPERIMENT (prison extraction): the hand-authored prison compound as a TownGen-shaped town dictionary, so that the town's World, TownRun (the real Sim: avatar, shooting, dormant dead)
## and renderer run it unchanged. A small generated town is made only as a TEMPLATE for the constant keys (pawn art, weapons, icons, sounds...); every grid, object and list the map owns
## is replaced here. No houses, no rooms, no containers: the base is a place to walk in, not to search.
extends RefCounted

const TownGen := preload("res://scripts/town/town_gen.gd")

const W := 67
const H := 70
# terrain ids of the generator (data.terrainTypes)
const T_ASPHALT := 1
const T_SIDEWALK := 2
const T_YARD := 3
const T_GRASS := 4
const T_SOIL := 5
const T_TERRAZZO := 7
const T_KITCHEN := 11
const T_CONCRETE := 12
const T_DIRT := 13
const T_BRICK := 20
const T_PLASTER := 21
const T_METAL := 22
# kit ground groups (TownArt.GROUNDS index)
const G_LAWN := 0
const G_ASPHALT := 1
const G_SIDEWALK := 2
const G_DIRT := 3
const G_GRAVEL := 4
const G_WOOD := 5
const G_HALL := 6
const G_KITCHEN := 7
const G_BATH := 9
# fence line codes (TownArt.LINES)
const L_CHAIN := 3
const L_HEDGE := 5
const L_WIRE := 6

## The compound was cut down on 2026-10-15 (owner: "the prison is too big"): 57 x 50 tiles inside the fence instead of 84 x 52, six clear-phase zones instead of ten, 62 dead instead of 99.
const FENCE := Rect2i(5, 4, 57, 50)    # x 5..61, y 4..53
const GATE_X := 21
const GATE_W := 4
const GATE_POS := Vector2(23.0, 53.5)
const SPAWN := Vector2(23.0, 47.0)
## CLEAR PHASE: the party walks in from the west road through a breach in the fence (`GAP`, closed in the managed phase) into the infirmary (a west door is cut for it).
const GAP := Rect2i(5, 28, 1, 3)
const START := Vector2(2.5, 29.5)
## VARIANT B (chosen by the run seed): the party comes in from the EAST road instead, through a breach in the east fence and a door cut in the east wall of the stores, so the clear order runs the other way round (stores first, infirmary last). Everything else is the same compound.
const GAP_E := Rect2i(61, 28, 1, 3)
const START_E := Vector2(64.5, 29.5)
const DOOR_E := Rect2i(58, 28, 1, 3)
static var east := false
## The buildings (tiles). Row one: the cell block and the canteen with its kitchen. Row two: the infirmary, the workshop and the stores. Row three: the gate yard and the garden.
const CELLS := Rect2i(9, 6, 26, 15)
const CANTEEN := Rect2i(37, 6, 20, 15)
const INFIRMARY := Rect2i(8, 24, 15, 13)
const WORKSHOP := Rect2i(26, 24, 18, 13)
const STORES := Rect2i(48, 24, 11, 11)
const GARDEN := Rect2i(40, 39, 18, 14)    # the wire fence round the beds
const WELL := Vector2(51.6, 37.6)    # the well, in the strip between the second row and the garden
const LAUNDRY := Vector2(14.0, 42.5)    # where the washing is done (the cleaner, the sound)
const PEN_Y := 54.6    # the pen of the dead outside the gate starts here (y of its first row)
## Where the art of the base's built tiers (prison_upgrades.gd) moved to, as offsets from the old, larger map.
const OFF_ROW2 := Vector2(-2.0, -5.0)    # infirmary, power shed, workshop, stores, radio
const OFF_CELLS := Vector2(-1.0, -2.0)
const OFF_KITCHEN := Vector2(-30.0, -2.0)    # the kitchen end of the canteen (range, larder)
const OFF_BARRELS := Vector2(-31.0, -2.0)
## The six zones of the clear phase: rect (tiles), dead (dormant records), dead_rect (where they stand: a rect or an array of rects), loot (containers), crew (roster ids freed when it is cleared), rel (where they
## appear), stash (the zone's first container holds this instead: a sure find). The infirmary's dead stand only in its east end so that the first room is a few dead for the party. The last zone
## is the gate. Since playtest 4 the party is five, so every zone after the first has two or three more dead.
const ZONES := [
	{"id": "infirmary", "name": "Infirmary", "rect": Rect2i(8, 24, 15, 13), "dead": 3, "dead_rect": Rect2i(15, 25, 7, 11), "loot": 3, "crew": ["ana", "tomas"], "rel": Vector2(14.5, 31.0), "keys": ["meds", "food", "scrap"]},
	{"id": "cells", "name": "Cell block", "rect": Rect2i(9, 6, 26, 15), "dead": 20, "loot": 5, "crew": ["june", "dez", "rae"], "rel": Vector2(22.0, 13.5), "keys": ["food", "water", "scrap", "ammo", "ammo"]},
	{"id": "canteen", "name": "Canteen and kitchen", "rect": Rect2i(37, 6, 20, 15), "dead": 13, "loot": 4, "crew": ["mia", "kit"], "rel": Vector2(44.5, 12.5), "keys": ["food", "water", "food", "scrap"]},
	{"id": "workshop", "name": "Workshop and stores", "rect": Rect2i(26, 24, 33, 13), "dead": 14, "dead_rect": [Rect2i(27, 25, 16, 11), Rect2i(49, 25, 9, 9)], "loot": 6, "crew": ["hector", "owen"], "rel": Vector2(34.5, 31.0), "keys": ["scrap", "ammo", "scrap", "food", "ammo", "meds"], "stash": {"scrap": 10}},
	{"id": "yard", "name": "Yard and garden", "rect": Rect2i(31, 38, 29, 15), "dead": 13, "loot": 4, "crew": ["marcus", "nia", "pip"], "rel": Vector2(36.0, 47.0), "keys": ["food", "water", "scrap", "ammo"]},
	{"id": "gate", "name": "Gate area", "rect": Rect2i(8, 40, 22, 13), "dead": 10, "loot": 3, "crew": ["walt", "sol"], "rel": Vector2(23.0, 45.0), "keys": ["ammo", "meds", "water"]},
]
## The doors: one in every doorway of a building (name = the building it shuts). The clear phase starts them all shut (prison_doors.gd); the managed base has them open.
const DOORS := [
	{"name": "Infirmary", "rect": Rect2i(8, 28, 1, 3)}, {"name": "Infirmary", "rect": Rect2i(14, 24, 3, 1)},
	{"name": "Cell block", "rect": Rect2i(9, 12, 1, 3)}, {"name": "Cell block", "rect": Rect2i(34, 12, 1, 3)},
	{"name": "Canteen", "rect": Rect2i(37, 12, 1, 3)}, {"name": "Canteen", "rect": Rect2i(44, 20, 4, 1)},
	{"name": "Workshop", "rect": Rect2i(32, 24, 5, 1)},
	{"name": "Stores", "rect": Rect2i(52, 24, 3, 1)}, {"name": "Stores", "rect": Rect2i(52, 34, 3, 1)},
	{"name": "Garden", "rect": Rect2i(41, 39, 2, 1)},
]
static func start() -> Vector2:
	return START_E if east else START


static func doors() -> Array:
	return DOORS + [{"name": "Stores", "rect": DOOR_E}] if east else DOORS


static func variant_for(seed_i: int) -> bool:
	return seed_i % 2 == 0


const LOOT_N := {"food": [3, 6], "water": [3, 6], "ammo": [6, 12], "meds": [1, 2], "scrap": [3, 6]}
const SEARCHABLE := {"nightstand": "nightstand", "medicine_cabinet": "cabinet", "shelf_tins": "shelf", "desk": "desk", "bed_single": "bunk", "fridge": "fridge", "kitchen_counter": "cupboard",
	"workbench": "bench", "toolbox": "toolbox", "tool_chest": "tool chest", "crate": "crate", "woodpile": "woodpile", "shop_shelf": "shelf", "cooler": "cooler", "veg_patch": "garden patch", "bin": "bin"}

var terrain := PackedInt32Array()
var solid := PackedByteArray()
var kg := PackedByteArray()
var kw := PackedByteArray()
var kl := PackedByteArray()
var low := PackedByteArray()
var objects: Array = []
var stations := {}    # name -> Vector2 (where a worker stands)
var towers: Array = []    # Rect2 (tiles) of each watchtower deck
var labels: Array = []
var fires: Array = []
var lamps: Array = []    # {pos, text} signs drawn over the base
var _next_id := 0
var _proto := {}


func idx(x: int, y: int) -> int:
	return y * W + x


func _put(x: int, y: int, t: int, g: int = -1, s: int = 0) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	var i := idx(x, y)
	terrain[i] = t
	solid[i] = s
	if g >= 0:
		kg[i] = g
	kw[i] = 0
	kl[i] = 0


func _fill(r: Rect2i, t: int, g: int = -1) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_put(x, y, t, g, 0)


func _wall(x: int, y: int, mat: int = 1) -> void:
	_put(x, y, T_BRICK, G_HALL, 1)
	kw[idx(x, y)] = mat


func _fence(x: int, y: int, line: int = L_CHAIN) -> void:
	_put(x, y, T_METAL, G_LAWN, 1)
	kl[idx(x, y)] = line


## A building: a ring of wall, a floor inside, doors (rects of floor cut through the wall).
func _building(r: Rect2i, floor_t: int, floor_g: int, doors: Array, mat: int = 1) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			if edge:
				_wall(x, y, mat)
			else:
				_put(x, y, floor_t, floor_g, 0)
	for d in doors:
		var dr: Rect2i = d
		for y in range(dr.position.y, dr.end.y):
			for x in range(dr.position.x, dr.end.x):
				_put(x, y, floor_t, floor_g, 0)


func _obj(kind: String, cx: float, cy: float, facing: String = "s", variant: int = 0) -> void:
	var p: Dictionary = _proto.get(kind, {})
	if p.is_empty():
		push_warning("prison_base: no prototype for %s" % kind)
		return
	var o: Dictionary = p.duplicate(true)
	o["id"] = _next_id
	o["order"] = _next_id
	_next_id += 1
	o["cx"] = cx
	o["cy"] = cy
	o["facing"] = facing
	o["variant"] = variant
	o.erase("in")
	for pc in o.pieces:    # an old-style picture keeps its place relative to the object
		pc["x"] = float(pc.x) + cx - float(p.cx)
		pc["y"] = float(pc.y) + cy - float(p.cy)
	objects.append(o)
	if bool(o.solid):
		var w := int(round(float(o.w)))
		var h := int(round(float(o.h)))
		if facing == "e" or facing == "w":
			var tmp := w
			w = h
			h = tmp
		var x0 := int(floor(cx - float(w) / 2.0 + 0.01))
		var y0 := int(floor(cy - float(h) / 2.0 + 0.01))
		for yy in range(y0, y0 + h):
			for xx in range(x0, x0 + w):
				if xx >= 0 and yy >= 0 and xx < W and yy < H:
					solid[idx(xx, yy)] = 1
					low[idx(xx, yy)] = 1


func _row(kind: String, x0: float, y: float, n: int, step: float = 1.0, facing: String = "s") -> void:
	for i in n:
		_obj(kind, x0 + float(i) * step, y, facing, i % 2)


func _cell_block(x0: int, y0: int, mirror_label: String) -> void:
	# 26 x 15: six cells along the north (y0+1..y0+4) and the south (y0+10..y0+13), a corridor y0+6..y0+8, open at both ends
	var r := Rect2i(x0, y0, 26, 15)
	_building(r, T_CONCRETE, G_HALL, [Rect2i(x0, y0 + 6, 1, 3), Rect2i(x0 + 25, y0 + 6, 1, 3)])
	for row in 2:
		var wy := y0 + 5 if row == 0 else y0 + 9
		for x in range(x0 + 1, x0 + 25):
			_wall(x, wy)
		for c in 6:
			var cx := x0 + 1 + c * 4    # cell interior x cx..cx+2, the wall column at cx+3 (not after the last)
			if c < 5:
				for y in range(y0 + 1, y0 + 5) if row == 0 else range(y0 + 10, y0 + 14):
					_wall(cx + 3, y)
			_put(cx + 1, wy, T_CONCRETE, G_HALL, 0)    # the cell's door
			var by := float(y0 + 2) if row == 0 else float(y0 + 11)
			_obj("bed_single", float(cx) + 0.5, by + 0.5, "s" if row == 0 else "n")
			_obj("toilet", float(cx) + 2.5, float(y0 + 4) if row == 0 else float(y0 + 10) + 0.5, "s" if row == 0 else "n")
	labels.append({"pos": Vector2(x0 + 13, y0 + 7.4), "text": mirror_label})


## The zone (index into ZONES) that holds a point, or -1.
static func zone_at(x: float, y: float) -> int:
	for i in ZONES.size():
		if Rect2(ZONES[i].rect).has_point(Vector2(x, y)):
			return i
	return -1


func build(seed_i: int = 1, clear: bool = false) -> Dictionary:
	# the template: constant keys and the prototype objects
	var town: Dictionary = TownGen.make(1, {"blocks": 2})
	var d: Dictionary = town.data
	for src in [d, TownGen.make(3, {"blocks": 3}).data]:
		for o in src.objects:
			if not _proto.has(String(o.kind)):
				_proto[String(o.kind)] = (o as Dictionary).duplicate(true)
	terrain.resize(W * H)
	solid.resize(W * H)
	kg.resize(W * H)
	kw.resize(W * H)
	kl.resize(W * H)
	low.resize(W * H)
	terrain.fill(T_GRASS)
	# outside: grass; the road across the south; the pen for the dead in front of the gate
	_fill(Rect2i(0, 0, W, H), T_GRASS, G_LAWN)
	_fill(Rect2i(0, 56, W, 6), T_ASPHALT, G_ASPHALT)
	_fill(Rect2i(GATE_X - 1, FENCE.end.y - 1, GATE_W + 2, 3), T_ASPHALT, G_ASPHALT)
	# inside the fence: packed dirt yard, paths of concrete
	_fill(Rect2i(FENCE.position.x + 1, FENCE.position.y + 1, FENCE.size.x - 2, FENCE.size.y - 2), T_DIRT, G_DIRT)
	_fill(Rect2i(GATE_X - 1, 37, GATE_W + 2, 17), T_CONCRETE, G_SIDEWALK)    # the road from the gate north to the second row
	_fill(Rect2i(6, 21, 55, 3), T_CONCRETE, G_SIDEWALK)    # the walk between the cell block, the canteen and the second row
	# the perimeter fence and the gate (the gate is shut: E there takes you out)
	for x in range(FENCE.position.x, FENCE.end.x):
		_fence(x, FENCE.position.y)
		if x < GATE_X or x >= GATE_X + GATE_W:
			_fence(x, FENCE.end.y - 1)
		else:
			_fence(x, FENCE.end.y - 1, L_WIRE)
	for y in range(FENCE.position.y, FENCE.end.y):
		if not (clear and not east and GAP.has_point(Vector2i(FENCE.position.x, y))):
			_fence(FENCE.position.x, y)
		if not (clear and east and GAP_E.has_point(Vector2i(FENCE.end.x - 1, y))):
			_fence(FENCE.end.x - 1, y)
	if clear:
		_fill(Rect2i(59, GAP_E.position.y, 6, GAP_E.size.y) if east else Rect2i(2, GAP.position.y, 6, GAP.size.y), T_CONCRETE, G_SIDEWALK)    # the road in through the breach
	# a hedge pen closes the sides of the field in front of the gate, so the dead stay where they are shown
	for y in range(FENCE.end.y, H):
		for x in [0, 1, 2, 3, 4, W - 5, W - 4, W - 3, W - 2, W - 1]:
			_fence(x, y, L_HEDGE)
	for x in range(0, W):
		_fence(x, H - 1, L_HEDGE)
	for y in range(0, FENCE.end.y):
		for x in [0, 1, W - 2, W - 1]:
			_fence(x, y, L_HEDGE)
	for x in range(0, W):
		_fence(x, 0, L_HEDGE)
		_fence(x, 1, L_HEDGE)
	# the cell block
	_cell_block(CELLS.position.x, CELLS.position.y, "CELL BLOCK")
	# the canteen and its kitchen (kitchen on the north wall at the east end, the dining hall below)
	_building(CANTEEN, T_TERRAZZO, G_HALL, [Rect2i(44, 20, 4, 1), Rect2i(37, 12, 1, 3)])
	for y in range(7, 12):
		for x in range(38, 56):
			_put(x, y, T_KITCHEN, G_KITCHEN, 0)
	_row("kitchen_counter", 38.5, 7.5, 9, 1.0, "s")
	_obj("stove", 48.5, 7.5, "s")
	_obj("stove", 49.5, 7.5, "s")
	_obj("fridge", 52.5, 7.5, "s")
	_obj("fridge", 53.5, 7.5, "s")
	_obj("kitchen_sink", 54.5, 7.5, "s")
	_row("kitchen_counter", 40.5, 10.5, 6, 1.0, "n")
	for r in 2:
		for c in 3:
			_obj("dining_table", 41.0 + float(c) * 5.0, 14.5 + float(r) * 3.0, "s")
	stations["fridge"] = Vector2(52.5, 9.2)
	stations["stove"] = Vector2(48.5, 9.0)
	stations["serve"] = Vector2(42.0, 10.0)
	stations["canteen"] = Vector2(46.0, 16.0)
	labels.append({"pos": Vector2(46.5, 7.2), "text": "CANTEEN"})
	# the infirmary
	_building(INFIRMARY, T_TERRAZZO, G_BATH, [Rect2i(14, 24, 3, 1), Rect2i(8, 28, 1, 3)])    # the second door: the west one, where the party comes in
	for i in 4:
		_obj("bed_single", 10.5 + float(i) * 3.0, 27.5, "s")
		_obj("nightstand", 11.5 + float(i) * 3.0, 26.5, "s")
	for x in [10.5, 12.5, 19.5]:    # (none at 14.5: that one stood in the swing of the north door's leaves)
		_obj("medicine_cabinet", x, 25.5, "s")
	_obj("desk", 18.0, 33.0, "s")
	_obj("shelf_tins", 10.0, 34.5, "n")
	stations["bed"] = Vector2(12.5, 29.6)
	stations["meds"] = Vector2(18.5, 31.6)
	labels.append({"pos": Vector2(15.5, 24.4), "text": "INFIRMARY"})
	# the workshop (a wide garage door on the walk side)
	_building(WORKSHOP, T_CONCRETE, G_HALL, [Rect2i(32, 24, 5, 1)])
	_obj("workbench", 29.0, 27.0, "s")
	_obj("workbench", 39.0, 27.0, "s")
	_obj("tool_chest", 42.0, 29.0, "w")
	_obj("toolbox", 28.5, 33.5, "s")
	_obj("woodpile", 36.0, 34.5, "n")
	_obj("crate", 41.5, 34.5, "n")
	_obj("crate", 27.5, 31.5, "e")
	stations["bench1"] = Vector2(29.0, 28.9)
	stations["bench2"] = Vector2(39.0, 28.9)
	labels.append({"pos": Vector2(34.5, 24.4), "text": "WORKSHOP"})
	# the stores: where the loot is banked
	_building(STORES, T_CONCRETE, G_HALL, [Rect2i(52, 24, 3, 1), Rect2i(52, 34, 3, 1)] + ([DOOR_E] if east else []))
	_row("shop_shelf", 50.0, 26.5, 4, 2.0, "s")
	_row("shelf_tins", 50.0, 30.5, 4, 2.0, "s")
	_obj("cooler", 57.5, 25.5 if east else 28.5, "w")    # (clear of the east door in variant B)
	_obj("crate", 49.5, 33.5, "n")
	_obj("crate", 57.5, 33.5, "n")
	stations["stores_in"] = Vector2(53.5, 26.4)
	stations["stores_out"] = Vector2(53.5, 32.0)
	stations["stores"] = Vector2(53.5, 29.0)
	labels.append({"pos": Vector2(53.5, 24.4), "text": "STORES"})
	# the garden: rows of soil in the south-east of the yard, a plain wire fence round it (one gate, at the north)
	var g := GARDEN
	_fill(Rect2i(g.position.x + 1, g.position.y + 1, g.size.x - 2, g.size.y - 2), T_SOIL, G_DIRT)
	for y in [g.position.y + 2, g.position.y + 6, g.position.y + 10]:
		for x in range(g.position.x + 3, g.position.x + 16, 3):
			_obj("veg_patch", float(x) + 1.0, float(y) + 1.0, "s", (x + y) % 3)
	for y in range(g.position.y, g.end.y):
		_fence(g.position.x, y, L_WIRE)
		_fence(g.end.x - 1, y, L_WIRE)
	for x in range(g.position.x, g.end.x):
		_fence(x, g.position.y, L_WIRE)
		_fence(x, g.end.y - 1, L_WIRE)
	for gx in [g.position.x + 1, g.position.x + 2]:
		_put(gx, g.position.y, T_SOIL, G_DIRT, 0)
	stations["garden1"] = Vector2(44.5, 43.2)
	stations["garden2"] = Vector2(53.5, 47.2)
	stations["garden3"] = Vector2(47.5, 51.2)
	stations["well"] = Vector2(49.0, 37.4)
	labels.append({"pos": Vector2(48.5, 39.4), "text": "GARDEN"})
	# watchtowers: a 3 x 3 footprint, drawn by the game; the guard stands on the deck
	for t in [Vector2i(7, 6), Vector2i(59, 6), Vector2i(7, 50), Vector2i(59, 50), Vector2i(GATE_X - 4, 50), Vector2i(GATE_X + 7, 50)]:
		towers.append(Rect2(t.x - 1, t.y - 1, 3, 3))
		for yy in range(t.y - 1, t.y + 2):
			for xx in range(t.x - 1, t.x + 2):
				solid[idx(xx, yy)] = 1
	# the gate: sandbags inside, the truck that goes out, lamps
	_obj("sandbags", 19.5, 48.5, "s")
	_obj("sandbags", 26.5, 48.5, "s")
	_obj("car_h", 15.0, 46.0, "e")
	_obj("lamp_floor", 19.5, 38.5)
	_obj("lamp_floor", 26.5, 38.5)
	_obj("crate", 27.5, 44.5, "s")
	_obj("crate", 28.5, 44.5, "s")
	_obj("bin", 33.0, 22.5, "e")
	for c in [Vector2(12.5, 22.5), Vector2(56.5, 22.5), Vector2(34.5, 41.5), Vector2(36.5, 50.5), Vector2(10.5, 44.5), Vector2(13.5, 50.5)]:
		_obj("crate", c.x, c.y, "s")
	stations["chat_a1"] = Vector2(49.5, 22.5)
	stations["chat_a2"] = Vector2(51.0, 22.5)
	stations["chat_b1"] = Vector2(43.5, 37.4)
	stations["chat_b2"] = Vector2(45.0, 37.4)
	fires = [Vector2(35.0, 43.5), Vector2(10.5, 38.5), Vector2(24.0, 22.5)]
	lamps = [Vector2(19.5, 38.5), Vector2(26.5, 38.5), Vector2(30.0, 22.0), Vector2(14.0, 22.0), Vector2(50.0, 22.0)]
	for f in fires:
		_obj("campfire", f.x, f.y)
	stations["gate"] = Vector2(23.0, 50.0)
	stations["truck"] = Vector2(15.0, 48.0)
	stations["fence_w"] = Vector2(10.0, 52.0)
	stations["fence_m"] = Vector2(16.0, 52.0)
	stations["fence_e"] = Vector2(34.0, 52.0)
	stations["fence_e2"] = Vector2(60.0, 30.0)
	stations["yard"] = Vector2(30.0, 22.0)
	labels.append({"pos": Vector2(23.5, 51.6), "text": "GATE"})
	# trees round the outside, from the template
	var trees: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var greens := [24, 24, 24, 24, 22, 22, 21, 23, 23, 0, 2]
	var spots: Array = []
	for x in range(3, W - 2, 4):
		spots.append(Vector2(x + rng.randf_range(-1.2, 1.2), rng.randf_range(2.2, 3.6)))
	for y in range(8, FENCE.end.y, 5):
		spots.append(Vector2(rng.randf_range(2.0, 4.0), y + rng.randf_range(-1.0, 1.0)))
		spots.append(Vector2(W - rng.randf_range(3.0, 5.0), y + rng.randf_range(-1.0, 1.0)))
	for x in range(6, W - 4, 6):
		if absi(x - int(GATE_POS.x)) > 14:
			spots.append(Vector2(x + rng.randf_range(-1.5, 1.5), rng.randf_range(float(H) - 2.5, float(H) - 1.0)))
	for k in 10:
		spots.append(Vector2(rng.randf_range(8.0, W - 8.0), rng.randf_range(58.0, 66.0)))    # scrub in the pen
	for sp in spots:
		if (sp.x > float(W) - 7.0 if east else sp.x < 7.0) and sp.y > 26.0 and sp.y < 33.0:
			continue    # the west road in
		var pen: bool = sp.y > 57.0 and sp.y < 67.0
		var n: int = 23 if pen else greens[rng.randi() % greens.size()]
		trees.append({"x": sp.x, "y": sp.y, "variant": n, "file": "res://assets/trees/tree_%d.png" % n})
	# the data
	d["W"] = W
	d["H"] = H
	d["terrain"] = Array(terrain)
	d["wall"] = Array(PackedInt32Array(_zeros()))
	d["solidZ"] = Array(solid)
	d["solidP"] = Array(solid)
	d["shot_low"] = low
	d["objects"] = objects
	d["marks"] = [{"kind": "lanes", "cx": float(W) / 2.0, "cy": 59.0, "w": float(W) - 4.0, "h": 6.0, "dir": "h", "gaps": [], "seed": 1000}]
	d["walls"] = []
	d["segments"] = []
	d["trees"] = trees
	d["lights"] = []
	d["rooms"] = {}
	d["spawns"] = [[SPAWN.x, SPAWN.y]]
	d["yard"] = [6, 21, 55, 32]
	d["kit"] = {"ground": kg, "wall": kw, "line": kl, "windows": [], "gates": [], "houses": []}
	town["data"] = d
	town["size"] = Vector2i(W, H)
	# one stand-in house (the stores) so that the colony's modules that ask for "the base house" find one; no tile belongs to it
	var fake := {"id": 0, "kind": "civic", "type": "civic", "rect": STORES, "lot": FENCE, "rooms": [], "containers": [], "dead": [], "doors": [], "door": Vector2i(53, 35),
		"main": true, "front": "S", "fenced": true, "state": "intact", "wall": 1, "roof": "flat", "boarded": false, "barricaded": false, "number": 1, "street": "Prison Road", "address": "1 Prison Road"}
	town["houses"] = [fake]
	town["rooms"] = []
	town["containers"] = []
	town["candidates"] = [{"house": 0, "kind": "civic", "label": "The prison", "rooms": 0, "yard": "big", "dist": 0.0, "tier": "best"}]
	town["rescue_for"] = {}
	town["rescue"] = []
	var th := PackedInt32Array()
	th.resize(W * H)
	th.fill(-1)
	town["tile_house"] = th
	town["tile_room"] = th.duplicate()
	town["fields"] = []
	town["streets"] = []
	town["lots"] = []
	town["landmarks"] = []
	town["start"] = {"house": 0, "pos": SPAWN, "room": -1, "ring": {"rect": FENCE, "total": 0, "free": 0}}
	town["entry"] = {"pos": SPAWN, "face": "N", "road": Rect2i(GATE_X, FENCE.end.y - 1, GATE_W, 3), "label": "The gate", "sign": Vector2(-1, -1), "arrows": []}
	town["dead"] = _crowd(seed_i)
	if clear:
		_zones(town, seed_i)
	return town


## CLEAR PHASE: every zone is a "house" (so that the real search and the indoor wake rule work), with its containers (on furniture) and its dormant dead.
## Dead in a zone: the zone next to the breach holds only 3 so the first minute teaches the controls. On the east entry that is the stores, and its 9 extra dead go to the cells and the canteen (the total stays 62).
static func dead_n(zi: int) -> int:
	var n: int = int(ZONES[zi].dead)
	if east:
		match String(ZONES[zi].id):
			"workshop": return 3
			"cells": return n + 5
			"canteen": return n + 4
	return n


func _zones(town: Dictionary, seed_i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 31 + 7
	var houses: Array = []
	var containers: Array = []
	var th: PackedInt32Array = town.tile_house
	var dead: Array = town.dead
	var tmpl: Dictionary = (town.houses[0] as Dictionary)
	for zi in ZONES.size():
		var z: Dictionary = ZONES[zi]
		var r: Rect2i = z.rect
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				th[idx(x, y)] = zi
		var h: Dictionary = tmpl.duplicate(true)
		h["id"] = zi
		h["rect"] = r
		h["lot"] = r
		h["containers"] = []
		h["address"] = String(z.name)
		h["main"] = zi == 0
		houses.append(h)
		# containers: furniture of the zone, spread out
		var cands: Array = []
		for o in objects:
			if SEARCHABLE.has(String(o.kind)) and r.has_point(Vector2i(int(floor(float(o.cx))), int(floor(float(o.cy))))):
				cands.append(o)
		for i in range(cands.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = cands[i]
			cands[i] = cands[j]
			cands[j] = t
		var chosen: Array = []
		for o in cands:
			if chosen.size() >= int(z.loot):
				break
			var far := true
			for c in chosen:
				if Vector2(float(c.cx), float(c.cy)).distance_to(Vector2(float(o.cx), float(o.cy))) < 3.0:
					far = false
			var st := _stand_for(o, zi)
			if far and st.x >= 0.0:
				chosen.append(o)
				var key := String(z.keys[chosen.size() % (z.keys as Array).size()])
				var n: Array = LOOT_N[key]
				var cid := "z%d_%d" % [zi, chosen.size()]
				(h.containers as Array).append(cid)
				var lt: Dictionary = {key: rng.randi_range(n[0], n[1])}
				if chosen.size() == 1 and z.has("stash"):
					lt = (z.stash as Dictionary).duplicate()
				containers.append({"id": cid, "house": zi, "room": -1, "pos": st, "at": Vector2(float(o.cx), float(o.cy)), "kind": SEARCHABLE[String(o.kind)], "loot": lt, "search_s": 3.0})
		# dead
		var drs = z.get("dead_rect", r.grow(-1))
		if east and String(z.id) == "workshop":
			drs = [Rect2i(27, 25, 16, 11), Rect2i(49, 25, 5, 9)]
		var tiles: Array = []
		for dr in (drs if drs is Array else [drs]):
			for y in range(dr.position.y, dr.end.y):
				for x in range(dr.position.x, dr.end.x):
					if solid[idx(x, y)] == 0 and th[idx(x, y)] == zi:
						tiles.append(Vector2(float(x) + 0.5, float(y) + 0.5))
		var placed: Array = []
		var tries := 0
		while placed.size() < dead_n(zi) and tries < 600 and not tiles.is_empty():
			tries += 1
			var tp: Vector2 = tiles[rng.randi_range(0, tiles.size() - 1)]
			var ok := true
			for q in placed:
				if Vector2(q).distance_to(tp) < 1.6:
					ok = false
					break
			if ok:
				placed.append(tp)
				dead.append({"pos": tp, "kind": "runner" if rng.randi() % 12 == 0 else "walker", "state": "still", "house": zi, "room": -1, "group": -1})
	town["tile_house"] = th
	town["houses"] = houses
	town["containers"] = containers


## A free tile next to a piece of furniture where a person can stand to search it ((-1, -1) when there is none), south side first.
func _stand_for(o: Dictionary, zi: int) -> Vector2:
	var cx := int(floor(float(o.cx)))
	var cy := int(floor(float(o.cy)))
	for rr in [1, 2]:
		for dy in [rr, 0, -rr]:
			for dx in [0, -rr, rr]:
				var x: int = cx + dx
				var y: int = cy + dy
				if x < 0 or y < 0 or x >= W or y >= H:
					continue
				if solid[idx(x, y)] == 0 and zone_at(float(x), float(y)) == zi:
					return Vector2(float(x) + 0.5, float(y) + 0.5)
	return Vector2(-1.0, -1.0)


func _zeros() -> Array:
	var a: Array = []
	a.resize(W * H)
	a.fill(0)
	return a


## The mass in front of the gate: about 70 dead in the pen (y 55..68), a third of them standing, the rest shuffling in place.
func _crowd(seed_i: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 7919 + 13
	var out: Array = []
	for i in 72:
		var x := rng.randf_range(8.0, W - 8.0)
		var y := rng.randf_range(PEN_Y + 0.2, float(H) - 2.0)
		# thicker at the gate
		if i % 2 == 0:
			x = clampf(GATE_POS.x + rng.randfn(0.0, 9.0), 8.0, W - 8.0)
			y = rng.randf_range(PEN_Y, PEN_Y + 6.4)
		var k := "walker"
		if i % 17 == 0:
			k = "runner"
		out.append({"pos": Vector2(x, y), "kind": k, "state": "still", "house": -1, "room": -1, "group": -1})
	return out
