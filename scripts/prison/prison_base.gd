## EXPERIMENT (prison extraction): the hand-authored prison compound as a TownGen-shaped town dictionary, so that the town's World, TownRun (the real Sim: avatar, shooting, dormant dead)
## and renderer run it unchanged. A small generated town is made only as a TEMPLATE for the constant keys (pawn art, weapons, icons, sounds...); every grid, object and list the map owns
## is replaced here. No houses, no rooms, no containers: the base is a place to walk in, not to search.
extends RefCounted

const TownGen := preload("res://scripts/town/town_gen.gd")

const W := 96
const H := 72
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

const FENCE := Rect2i(6, 4, 84, 52)    # x 6..89, y 4..55
const GATE_X := 46
const GATE_W := 4
const GATE_POS := Vector2(48.0, 55.5)
const SPAWN := Vector2(48.0, 49.0)

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
	# 24 x 15: cells along north (y0+1..y0+4) and south (y0+10..y0+13), a corridor y0+6..y0+8, open at both ends
	var r := Rect2i(x0, y0, 24, 15)
	_building(r, T_CONCRETE, G_HALL, [Rect2i(x0, y0 + 6, 1, 3), Rect2i(x0 + 23, y0 + 6, 1, 3)])
	for row in 2:
		var wy := y0 + 5 if row == 0 else y0 + 9
		for x in range(x0 + 1, x0 + 23):
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
	labels.append({"pos": Vector2(x0 + 12, y0 + 7.4), "text": mirror_label})


func build(seed_i: int = 1) -> Dictionary:
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
	_fill(Rect2i(0, 58, W, 6), T_ASPHALT, G_ASPHALT)
	_fill(Rect2i(GATE_X - 1, 55, GATE_W + 2, 3), T_ASPHALT, G_ASPHALT)
	# inside the fence: packed dirt yard, paths of concrete
	_fill(Rect2i(FENCE.position.x + 1, FENCE.position.y + 1, FENCE.size.x - 2, FENCE.size.y - 2), T_DIRT, G_DIRT)
	_fill(Rect2i(GATE_X - 1, 24, GATE_W + 2, 31), T_CONCRETE, G_SIDEWALK)    # the road from the gate north to the blocks
	_fill(Rect2i(8, 23, 80, 3), T_CONCRETE, G_SIDEWALK)    # the walk between the cell blocks and the shops
	# the perimeter fence and the gate (the gate is shut: E there takes you out)
	for x in range(FENCE.position.x, FENCE.end.x):
		_fence(x, FENCE.position.y)
		if x < GATE_X or x >= GATE_X + GATE_W:
			_fence(x, FENCE.end.y - 1)
		else:
			_fence(x, FENCE.end.y - 1, L_WIRE)
	for y in range(FENCE.position.y, FENCE.end.y):
		_fence(FENCE.position.x, y)
		_fence(FENCE.end.x - 1, y)
	# a hedge pen closes the sides of the field in front of the gate, so the dead stay where they are shown
	for y in range(FENCE.end.y, H):
		for x in [0, 1, 2, 3, 4, 5, W - 6, W - 5, W - 4, W - 3, W - 2, W - 1]:
			_fence(x, y, L_HEDGE)
	for x in range(0, W):
		_fence(x, H - 1, L_HEDGE)
	for y in range(0, FENCE.end.y):
		for x in [0, 1, W - 2, W - 1]:
			_fence(x, y, L_HEDGE)
	for x in range(0, W):
		_fence(x, 0, L_HEDGE)
		_fence(x, 1, L_HEDGE)
	# the cell blocks
	_cell_block(10, 8, "CELL BLOCK A")
	_cell_block(38, 8, "CELL BLOCK B")
	# the canteen and its kitchen
	_building(Rect2i(66, 8, 21, 15), T_TERRAZZO, G_HALL, [Rect2i(74, 22, 4, 1), Rect2i(66, 16, 1, 3)])
	for y in range(9, 14):
		for x in range(67, 86):
			_put(x, y, T_KITCHEN, G_KITCHEN, 0)
	_row("kitchen_counter", 68.5, 9.5, 9, 1.0, "s")
	_obj("stove", 78.5, 9.5, "s")
	_obj("stove", 79.5, 9.5, "s")
	_obj("fridge", 82.5, 9.5, "s")
	_obj("fridge", 83.5, 9.5, "s")
	_obj("kitchen_sink", 84.5, 9.5, "s")
	_row("kitchen_counter", 70.5, 12.5, 6, 1.0, "n")
	for r in 2:
		for c in 3:
			_obj("dining_table", 70.0 + float(c) * 5.0, 16.5 + float(r) * 3.0, "s")
	stations["fridge"] = Vector2(82.5, 11.2)
	stations["stove"] = Vector2(78.5, 11.0)
	stations["serve"] = Vector2(72.0, 12.0)
	stations["canteen"] = Vector2(76.0, 18.0)
	labels.append({"pos": Vector2(76.5, 9.2), "text": "CANTEEN"})
	# the infirmary
	_building(Rect2i(10, 29, 15, 13), T_TERRAZZO, G_BATH, [Rect2i(16, 29, 3, 1)])
	for i in 4:
		_obj("bed_single", 12.5 + float(i) * 3.0, 32.5, "s")
		_obj("nightstand", 13.5 + float(i) * 3.0, 31.5, "s")
	_row("medicine_cabinet", 12.5, 30.5, 3, 4.0, "s")
	_obj("desk", 20.0, 38.0, "s")
	_obj("shelf_tins", 12.0, 39.5, "n")
	stations["bed"] = Vector2(14.5, 34.6)
	stations["meds"] = Vector2(20.5, 36.6)
	labels.append({"pos": Vector2(17.5, 29.4), "text": "INFIRMARY"})
	# the workshop (a wide garage door on the walk side)
	_building(Rect2i(28, 29, 18, 13), T_CONCRETE, G_HALL, [Rect2i(34, 29, 5, 1)])
	_obj("workbench", 31.0, 32.0, "s")
	_obj("workbench", 41.0, 32.0, "s")
	_obj("tool_chest", 44.0, 34.0, "w")
	_obj("toolbox", 30.5, 38.5, "s")
	_obj("woodpile", 38.0, 39.5, "n")
	_obj("crate", 43.5, 39.5, "n")
	_obj("crate", 29.5, 36.5, "e")
	stations["bench1"] = Vector2(31.0, 33.9)
	stations["bench2"] = Vector2(41.0, 33.9)
	labels.append({"pos": Vector2(36.5, 29.4), "text": "WORKSHOP"})
	# the stores: where the loot is banked
	_building(Rect2i(50, 29, 11, 11), T_CONCRETE, G_HALL, [Rect2i(54, 29, 3, 1), Rect2i(54, 39, 3, 1)])
	_row("shop_shelf", 52.0, 31.5, 4, 2.0, "s")
	_row("shelf_tins", 52.0, 35.5, 4, 2.0, "s")
	_obj("cooler", 59.5, 33.5, "w")
	_obj("crate", 51.5, 38.5, "n")
	_obj("crate", 59.5, 38.5, "n")
	stations["stores_in"] = Vector2(55.5, 31.4)
	stations["stores_out"] = Vector2(55.5, 37.0)
	stations["stores"] = Vector2(55.5, 34.0)
	labels.append({"pos": Vector2(55.5, 29.4), "text": "STORES"})
	# the garden: rows of soil in the east of the yard, a plain wire fence round it
	_fill(Rect2i(64, 29, 22, 20), T_SOIL, G_DIRT)
	for y in [30, 34, 38, 42, 46]:
		for x in range(66, 85, 3):
			_obj("veg_patch", float(x) + 1.0, float(y) + 1.0, "s", (x + y) % 3)
	for y in range(28, 50):
		_fence(63, y, L_WIRE)
		_fence(86, y, L_WIRE)
	for x in range(63, 87):
		_fence(x, 28, L_WIRE)
		_fence(x, 49, L_WIRE)
	_put(74, 28, T_SOIL, G_DIRT, 0)
	_put(75, 28, T_SOIL, G_DIRT, 0)
	_put(74, 49, T_SOIL, G_DIRT, 0)
	_put(75, 49, T_SOIL, G_DIRT, 0)
	stations["garden1"] = Vector2(68.5, 32.2)
	stations["garden2"] = Vector2(79.5, 36.2)
	stations["garden3"] = Vector2(70.5, 44.2)
	stations["well"] = Vector2(75.0, 27.0)
	labels.append({"pos": Vector2(74.5, 28.4), "text": "GARDEN"})
	# watchtowers: a 3 x 3 footprint, drawn by the game; the guard stands on the deck
	for t in [Vector2i(8, 6), Vector2i(86, 6), Vector2i(8, 52), Vector2i(86, 52), Vector2i(42, 52), Vector2i(53, 52)]:
		towers.append(Rect2(t.x - 1, t.y - 1, 3, 3))
		for yy in range(t.y - 1, t.y + 2):
			for xx in range(t.x - 1, t.x + 2):
				solid[idx(xx, yy)] = 1
	# the gate: sandbags inside, the truck that goes out, lamps
	_obj("sandbags", 44.5, 50.5, "s")
	_obj("sandbags", 51.5, 50.5, "s")
	_obj("car_h", 40.0, 46.0, "e")
	_obj("lamp_floor", 44.5, 40.5)
	_obj("lamp_floor", 51.5, 40.5)
	_obj("crate", 57.5, 46.5, "s")
	_obj("crate", 58.5, 46.5, "s")
	_obj("bin", 38.5, 24.5, "e")
	stations["chat_a1"] = Vector2(45.2, 27.5)
	stations["chat_a2"] = Vector2(46.7, 27.5)
	stations["chat_b1"] = Vector2(73.7, 26.6)
	stations["chat_b2"] = Vector2(75.2, 26.6)
	fires = [Vector2(35.5, 45.5), Vector2(61.0, 44.0), Vector2(26.0, 27.0)]
	lamps = [Vector2(44.5, 40.5), Vector2(51.5, 40.5), Vector2(48.0, 25.0), Vector2(20.0, 25.0), Vector2(76.0, 24.5)]
	for f in fires:
		_obj("campfire", f.x, f.y)
	stations["gate"] = Vector2(48.0, 52.0)
	stations["truck"] = Vector2(40.0, 48.0)
	stations["fence_w"] = Vector2(14.0, 54.0)
	stations["fence_m"] = Vector2(26.0, 54.0)
	stations["fence_e"] = Vector2(72.0, 54.0)
	stations["fence_e2"] = Vector2(84.0, 20.0)
	stations["yard"] = Vector2(48.0, 27.0)
	labels.append({"pos": Vector2(48.5, 53.6), "text": "GATE"})
	# trees round the outside, from the template
	var trees: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var greens := [0, 2, 5, 7, 8, 11, 0, 2, 14, 14, 13, 18, 18, 19, 20]
	var spots: Array = []
	for x in range(3, W - 2, 4):
		spots.append(Vector2(x + rng.randf_range(-1.2, 1.2), rng.randf_range(2.2, 3.6)))
	for y in range(8, 55, 5):
		spots.append(Vector2(rng.randf_range(2.0, 4.0), y + rng.randf_range(-1.0, 1.0)))
		spots.append(Vector2(W - rng.randf_range(3.0, 5.0), y + rng.randf_range(-1.0, 1.0)))
	for x in range(6, W - 4, 6):
		if absi(x - 48) > 14:
			spots.append(Vector2(x + rng.randf_range(-1.5, 1.5), rng.randf_range(69.5, 71.0)))
	for k in 10:
		spots.append(Vector2(rng.randf_range(8.0, W - 8.0), rng.randf_range(60.0, 68.0)))    # scrub in the pen
	for sp in spots:
		var pen: bool = sp.y > 59.0 and sp.y < 69.0
		var n: int = [18, 19, 20][rng.randi() % 3] if pen else greens[rng.randi() % greens.size()]
		if pen and n == 20:
			n = 18
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
	d["marks"] = [{"kind": "lanes", "cx": 48.0, "cy": 61.0, "w": 92.0, "h": 6.0, "dir": "h", "gaps": [], "seed": 1000}]
	d["walls"] = []
	d["segments"] = []
	d["trees"] = trees
	d["lights"] = []
	d["rooms"] = {}
	d["spawns"] = [[SPAWN.x, SPAWN.y]]
	d["yard"] = [8, 24, 80, 30]
	d["kit"] = {"ground": kg, "wall": kw, "line": kl, "windows": [], "gates": [], "houses": []}
	town["data"] = d
	town["size"] = Vector2i(W, H)
	# one stand-in house (the stores) so that the colony's modules that ask for "the base house" find one; no tile belongs to it
	var fake := {"id": 0, "kind": "civic", "type": "civic", "rect": Rect2i(50, 29, 11, 11), "lot": Rect2i(6, 4, 84, 52), "rooms": [], "containers": [], "dead": [], "doors": [], "door": Vector2i(55, 40),
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
	town["start"] = {"house": 0, "pos": SPAWN, "room": -1, "ring": {"rect": Rect2i(6, 4, 84, 52), "total": 0, "free": 0}}
	town["entry"] = {"pos": SPAWN, "face": "N", "road": Rect2i(46, 55, 4, 3), "label": "The gate", "sign": Vector2(-1, -1), "arrows": []}
	town["dead"] = _crowd(seed_i)
	return town


func _zeros() -> Array:
	var a: Array = []
	a.resize(W * H)
	a.fill(0)
	return a


## The mass in front of the gate: about 70 dead in the pen (y 57..70), a third of them standing, the rest shuffling in place.
func _crowd(seed_i: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 7919 + 13
	var out: Array = []
	for i in 72:
		var x := rng.randf_range(8.0, W - 8.0)
		var y := rng.randf_range(56.8, 69.0)
		# thicker at the gate
		if i % 2 == 0:
			x = clampf(48.0 + rng.randfn(0.0, 9.0), 8.0, W - 8.0)
			y = rng.randf_range(56.6, 63.0)
		var k := "walker"
		if i % 17 == 0:
			k = "runner"
		out.append({"pos": Vector2(x, y), "kind": k, "state": "still", "house": -1, "room": -1, "group": -1})
	return out
