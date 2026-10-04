## The town (feature/town-core): ONE BIG OPEN TOWN, 192 x 192 tiles, made from a seed in the schema of assets/data/map.json that World and Sim are built on.
##
## `TownGen.make(seed)` does it in one go; `var g := TownGen.new(); g.begin(seed); while not g.step(8.0): await frame; g.result()` does it a few
## milliseconds a frame (a loading card; the web build is 3 to 4 times slower than the desktop's ~0.3 s). The same seed always gives the same town (`TownGen.digest`).
##
## LAYOUT. A street grid: a 4 tile road every 32 tiles (road k, x or y = 28 + 32 k .. +4), a 28 x 28 block between two roads with a one tile sidewalk ring
## and two rows of lots (the north row faces the north street, the south row the south one). Each lot is built on a SMALL LOCAL SiteCanvas
## (scripts/raid/site_canvas.gd, the generator of the raid sites: walls, doors, named rooms, furniture, containers) and stamped into the map. A
## canvas of the town's size cannot be used: `SiteCanvas._put` floods the whole canvas twice per prop. Houses are the templates of KINDS (small 8x7
## with 3 rooms, medium 10x8 with 4, terrace 6x8 with 2, corner shop 10x9 with 2), some with a fenced yard. Roofs are NOT in the ground: the view
## draws one roof per house over `rect` (scripts/town/town_roofs.gd) and hides it when the avatar is inside.
##
## THE RESULT, a Dictionary (tile coordinates everywhere; Rect2i is {position, size}, a Vector2i a tile, a Vector2 a point in tiles):
##   "seed", "version" (1), "size" (Vector2i 192 x 192)
##   "data"        the map in the schema (terrain, solidZ/solidP as Arrays of W*H ints, objects, marks, trees, rooms, spawns...): World.build / Sim.new take it
##   "houses"      [House]   (index == id)
##   "rooms"       [Room]    (index == `room` of the records and of the "tile_room" array)
##   "containers"  [Container]
##   "dead"        [DeadRecord]  (data only: the DormantDead field turns them into real dead near the avatar)
##   "start"       {"house": id, "pos": Vector2 (a free tile of the roomiest room), "room": room index}
##   "rescue"      [{"house", "pos": Vector2 (where the survivor waits), "room", "ring": 1..3, "dist": from the start house}] 12 candidates, near to far
##   "tile_house"  PackedInt32Array W*H: the id of the house whose walls' rectangle holds the tile, else -1   (which roof to lift, "am I inside?")
##   "tile_room"   PackedInt32Array W*H: the index of the room whose floor holds the tile, else -1 (a wall, a doorway, outside)
##   "streets"     {"pitch": 32, "block": 28, "road": 4, "names_x": [...], "names_y": [...]}  (road k runs along x = 28 + 32 k for names_x[k], along y for names_y[k])
##   "stats"       counts and the milliseconds each phase took
##
##   House      {"id", "kind": "small"|"medium"|"terrace"|"shop", "address": "14 Elm Street", "block": Vector2i, "rect": Rect2i (the outer walls = the footprint),
##               "lot": Rect2i, "front": "N"|"S" (the side its front door is on), "fenced": bool, "door": Vector2i (the tile outside the front door),
##               "doors": [Door], "rooms": [room indexes], "containers": [container ids], "dead": [record indexes] (the ones that stand in it at the start)}
##   Door       {"tiles": [Vector2i] (the doorway: no wall, two wide, one for a small interior door), "exterior": bool, "side": "N"|"S"|"E"|"W" (exterior: the wall
##               it is in; interior: "H" when the doorway runs along x, "V" along y), "out": Vector2i (the tile on the outer side, or the one on the first side),
##               "in": Vector2i (the tile on the other side)}
##   Room       {"id": "h17:kitchen", "house": 17, "name": "kitchen", "rect": Rect2i (the floor, the walls not included)}
##   Container  {"id", "house", "room": room index, "pos": Vector2 (where to stand), "at": Vector2 (the furniture's middle), "kind", "loot": {stock: n}, "search_s"}
##   DeadRecord {"pos": Vector2, "kind": "walker"|"runner"|"brute", "state": "still"|"wander", "house": id or -1 (the street), "room": room index or -1
##               (in the yard, or in the street), "group": street group or -1}   ("clear this room/house" = no record of it left alive: dormant_dead.gd counts them)
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const Canvas := preload("res://scripts/raid/site_canvas.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")

## The size of the full town (6 blocks a side); `make(seed, {"blocks": n})` makes a smaller one (2: 64 x 64, for tests).
const DEFAULT_SIZE := 192
const DEFAULT_BLOCKS := 6
const PITCH := 32
const BLOCK := 28
const ROAD := 4
const EDGE := 2
## Rows of lots inside a block (block-local y): the north row faces the north street, the south row the south one.
const NORTH_ROW := Vector2i(1, 13)
const SOUTH_ROW := Vector2i(14, 27)
const VERSION := 1
## The house templates: the outer size, the walls included.
const KINDS := {
	"small": Vector2i(8, 7),
	"medium": Vector2i(10, 8),
	"terrace": Vector2i(6, 8),
	"shop": Vector2i(10, 9),
}
const STREET_X := ["Elm", "Oak", "Birch", "Cedar", "Maple", "Pine"]
const STREET_Y := ["First", "Second", "Third", "Fourth", "Fifth", "Sixth"]
## Dead: how many (the owner's 600 to 800), the share that is in or beside the houses, and how many guard each house of the rescue list.
const DEAD_TOTAL := 700
const DEAD_NEAR_HOUSES := 0.6
const RESCUE_COUNT := 12

# ------------------------------------------------------------------ the build --

var seed_value := 1
var _size := 192
var _blocks := 6
var _start_block := Vector2i(3, 3)
var _start_house := -1
var _clear_rect := Rect2i()
var opts: Dictionary = {}
var _phase := 0
var _block := 0
var _rng := RandomNumberGenerator.new()
var _lay: Dictionary
var _base: Dictionary
var _terrain_types: Dictionary
var _tids := {}
var _terrain := PackedInt32Array()
var _solid := PackedByteArray()
var _objects: Array = []
var _trees: Array = []
var _houses: Array = []
var _rooms: Array = []
var _containers: Array = []
var _rooms_dict := {}
var _marks: Array = []
var _lot_index := 0
var _street_cv
var _street_objs := 0
var _ms := {}
var _started := 0
var _result := {}
var _tile_house := PackedInt32Array()
var _tile_room := PackedInt32Array()


static func make(seed_value_in: int = 1, opts_in: Dictionary = {}) -> Dictionary:
	var g = new()
	g.begin(seed_value_in, opts_in)
	while not g.step(1.0e9):
		pass
	return g.result()


func begin(seed_in: int, opts_in: Dictionary = {}) -> void:
	seed_value = seed_in
	opts = opts_in
	_phase = 0
	_block = 0
	_started = Time.get_ticks_usec()
	_rng.seed = seed_in * 7919 + 17
	_lay = SiteGen.layouts()
	_base = GD.load_all()
	_terrain_types = _base.terrainTypes.duplicate(true)
	for k in _lay.terrain:
		_terrain_types[k] = {"id": int(_lay.terrain[k].id), "file": String(_lay.terrain[k].file)}
	for k in _terrain_types:
		_tids[k] = int(_terrain_types[k].id)
	_blocks = clampi(int(opts_in.get("blocks", DEFAULT_BLOCKS)), 2, 6)
	_size = _blocks * PITCH
	_start_block = Vector2i(_blocks / 2, _blocks / 2)
	_start_house = -1
	_clear_rect = Rect2i()
	_terrain.resize(_size * _size)
	_terrain.fill(int(_tids.GRASS))
	_solid.resize(_size * _size)


## How far along the build is, 0 to 1 (a loading card's bar).
func progress() -> float:
	var n_blocks := float((_size / PITCH) * (_size / PITCH))
	match _phase:
		0:
			return 0.0
		1:
			return 0.05 + 0.75 * float(_block) / n_blocks
		2:
			return 0.85
		3:
			return 0.92
		4:
			return 0.97
	return 1.0


## Does about `budget_ms` of the work (always at least one piece of it) and says whether the town is done.
func step(budget_ms: float) -> bool:
	var t0 := Time.get_ticks_usec()
	while _phase < 5:
		match _phase:
			0:
				_streets()
				_phase = 1
			1:
				_blocks_until(t0, budget_ms)
				if _block >= (_size / PITCH) * (_size / PITCH):
					_phase = 2
			2:
				_edge_and_furniture()
				_phase = 3
			3:
				_finish_map()
				_phase = 4
			4:
				_people()
				_phase = 5
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	return _phase >= 5


func result() -> Dictionary:
	return _result


func _tick(name: String, t_in: int) -> void:
	_ms[name] = float(_ms.get(name, 0.0)) + float(Time.get_ticks_usec() - t_in) / 1000.0


# --------------------------------------------------------------------- streets --

func _streets() -> void:
	var t0 := Time.get_ticks_usec()
	var road := int(_tids.ASPHALT)
	var walk := int(_tids.SIDEWALK)
	for y in _size:
		var ly := y % PITCH
		for x in _size:
			var lx := x % PITCH
			var i := y * _size + x
			if lx >= BLOCK or ly >= BLOCK:
				_terrain[i] = road
			elif lx == 0 or lx == BLOCK - 1 or ly == 0 or ly == BLOCK - 1:
				_terrain[i] = walk
	var gaps: Array = []
	for j in _size / PITCH:
		gaps.append([float(BLOCK + PITCH * j), float(PITCH * (j + 1))])
	for k in _size / PITCH:
		var c := float(PITCH * k + BLOCK) + float(ROAD) / 2.0
		_marks.append({"kind": "lanes", "cx": float(_size) / 2.0, "cy": c, "w": float(_size), "h": float(ROAD), "dir": "h", "gaps": gaps.duplicate(true), "seed": 1000 + k})
		_marks.append({"kind": "lanes", "cx": c, "cy": float(_size) / 2.0, "w": float(ROAD), "h": float(_size), "dir": "v", "gaps": gaps.duplicate(true), "seed": 2000 + k})
	_street_cv = Canvas.new()
	_street_cv.setup(_size, _size, seed_value + 5, _lay.props, _tids, {})
	_tick("streets", t0)


# ------------------------------------------------------------------------ lots --

func _blocks_until(t0: int, budget_ms: float) -> void:
	var n := _size / PITCH
	while _block < n * n:
		_one_block(_block % n, _block / n)
		_block += 1
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			return


func _one_block(bx: int, by: int) -> void:
	var t_block := Time.get_ticks_usec()
	var ox := bx * PITCH
	var oy := by * PITCH
	for row in 2:
		var span: Vector2i = NORTH_ROW if row == 0 else SOUTH_ROW
		var front := "N" if row == 0 else "S"
		var x := 1
		var prev_fenced := false
		while x < BLOCK - 1:
			var remaining := BLOCK - 1 - x
			# the start house: the first lot of the south row of the middle block, a medium house with two tiles to spare all round, no fence,
			# no tree, no prop, no mark on its border and the tile inside it (a ring of free ground: the perimeter of the base goes there)
			var is_start: bool = row == 1 and x == 1 and bx == _start_block.x and by == _start_block.y
			var pick := "medium" if is_start else _pick_kind(remaining, x == 1)
			if pick == "":
				break
			# a lot left empty now and then: grass and a tree or two
			if not is_start and _rng.randf() < 0.07 and remaining > 8:
				x += mini(remaining, _rng.randi_range(3, 5))
				continue
			var hs: Vector2i = KINDS[pick]
			var lot_w := hs.x if pick == "terrace" else hs.x + 2
			if is_start:
				lot_w = hs.x + 4
			lot_w = mini(lot_w, remaining)
			var lot := Rect2i(ox + x, oy + span.x, lot_w, span.y - span.x)
			# (no fence on the north row of the top blocks: its gate would be on the world's edge, and the yard would be shut in)
			var fenced: bool = pick != "terrace" and not prev_fenced and _rng.randf() < 0.35 and not (by == 0 and row == 0) and not is_start
			var built := _build_lot(seed_value * 100003 + _lot_index, pick, lot, front, fenced, is_start)
			if is_start:
				_clear_rect = lot
				_start_house = _houses.size()
			_stamp(built, lot, pick, front, fenced, Vector2i(bx, by), row)
			_lot_index += 1
			x += lot_w
			prev_fenced = fenced
	_tick("blocks", t_block)


## Which template goes in the next lot: it must fit in `remaining` tiles of the row.
func _pick_kind(remaining: int, first: bool) -> String:
	var choices: Array = []
	var weights: Array = []
	for k in KINDS:
		var hs: Vector2i = KINDS[k]
		var need := hs.x if k == "terrace" else hs.x + 2
		if need > remaining:
			continue
		choices.append(k)
		weights.append({"small": 0.38, "medium": 0.3, "terrace": 0.26, "shop": 0.06 if first or remaining <= 12 else 0.0}[k])
	if choices.is_empty():
		return ""
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return String(choices[0])
	var at := _rng.randf() * total
	for i in choices.size():
		at -= float(weights[i])
		if at < 0.0:
			return String(choices[i])
	return String(choices[choices.size() - 1])


## One lot on a canvas of its own (the lot's size, no more): the yard, an optional fence, the house with its rooms, furniture and trees.
func _build_lot(lot_seed: int, kind: String, lot: Rect2i, front: String, fenced: bool, start: bool = false) -> Dictionary:
	var lw := lot.size.x
	var lh := lot.size.y
	var hs: Vector2i = KINDS[kind]
	var cv := Canvas.new()
	cv.setup(lw, lh, lot_seed, _lay.props, _tids, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = lot_seed * 31 + 7
	var hx := 0 if kind == "terrace" else (lw - hs.x) >> 1    # (the start lot is four wider than its house: two tiles each side)
	var hy := 3 if front == "N" else lh - 3 - hs.y
	var back := "S" if front == "N" else "N"
	var fat := rng.randi_range(2, maxi(2, hs.x - 4))
	var bat := rng.randi_range(1, maxi(1, hs.x - 3))
	var ops: Array = []
	if fenced:
		ops.append({"op": "fence", "rect": [0, 0, lw, lh], "t": "WALL_METAL", "gates": [{"side": front, "at": clampi(hx + fat - 1, 1, lw - 5), "w": 4}]})
	var doors: Array = [{"side": front, "at": fat, "w": 2}, {"side": back, "at": bat, "w": 2}]
	if kind == "shop":
		doors = [{"side": front, "at": mini(fat, 3), "w": 2}, {"side": back, "at": hs.x - 3, "w": 2}]
	ops.append({"op": "building", "rect": [hx, hy, hs.x, hs.y], "wall": "WALL_BRICK", "floor": "WOOD", "id": "h", "doors": doors})
	ops.append_array(_interior(kind))
	if kind != "terrace" and not start:
		ops.append({"op": "trees", "rect": [0, 0, lw, lh], "n": {"r": [0, 2]}, "on": ["GRASS"], "gap": 3})
	if not start:
		ops.append({"op": "decals", "rect": [0, 0, lw, lh], "kinds": ["papers", "stain", "blood", "crack"], "n": {"r": [1, 3]}})
	var door := Vector2i(hx + (fat if kind != "shop" else mini(fat, 3)), hy - 1 if front == "N" else hy + hs.y)
	cv.entry = door
	cv.run({"ops": ops})
	return {"cv": cv, "house": Rect2i(hx, hy, hs.x, hs.y), "door": door, "reach": cv.flood()}


## The rooms and the furniture of a template, as site-canvas ops. The building's inner rectangle is "h".
static func _interior(kind: String) -> Array:
	var ops: Array = []
	match kind:
		"small":
			# 6 x 5 inside: a living room and, behind a wall, a bedroom and a bathroom
			ops.append({"op": "split", "id": "h", "dir": "v", "at": 3, "into": ["w", "e"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [1, 2]}, "w": 2}], "names": ["living room", "side"], "floors": ["WOOD", "WOOD"]})
			ops.append({"op": "split", "id": "e", "dir": "h", "at": 2, "into": ["en", "es"], "wall": "WALL_PLASTER", "doors": [{"at": 0, "w": 1}], "names": ["bedroom", "bathroom"], "floors": ["WOOD", "KITCHEN"]})
			ops.append({"op": "line", "rect": "w", "side": "N", "kinds": ["fridge", "stove", "counter2"], "gap": [0, 0], "container": 0.7, "n": 2})
			ops.append({"op": "place", "kind": "shelf_s", "in": "w", "anchor": "SW", "container": true})
			ops.append({"op": "place", "kind": "rug", "in": "w", "anchor": "C", "p": 0.7})
			ops.append({"op": "place", "kind": "bed", "in": "en", "anchor": "NW"})
			ops.append({"op": "place", "kind": "cabinet", "in": "es", "anchor": "NE", "container": true})
		"medium":
			# 8 x 6 inside: bedroom, living room, bathroom, kitchen
			ops.append({"op": "split", "id": "h", "dir": "v", "at": 4, "into": ["w", "e"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [1, 3]}, "w": 2}], "names": ["west", "east"], "floors": ["WOOD", "WOOD"]})
			ops.append({"op": "split", "id": "w", "dir": "h", "at": 3, "into": ["wn", "ws"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [0, 1]}, "w": 2}], "names": ["bedroom", "living room"], "floors": ["WOOD", "WOOD"]})
			ops.append({"op": "split", "id": "e", "dir": "h", "at": 3, "into": ["en", "es"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [0, 1]}, "w": 1}], "names": ["bathroom", "kitchen"], "floors": ["KITCHEN", "KITCHEN"]})
			ops.append({"op": "place", "kind": "bed", "in": "wn", "anchor": "NW", "dx": {"r": [0, 1]}})
			ops.append({"op": "place", "kind": "shelf_s", "in": "wn", "anchor": "NE", "container": true})
			ops.append({"op": "place", "kind": "lamp", "in": "wn", "anchor": "SW"})
			ops.append({"op": "place", "kind": "rug", "in": "ws", "anchor": "C"})
			ops.append({"op": "line", "rect": "ws", "side": "S", "kinds": ["bench", "shelf_s", "desk"], "gap": [0, 1], "container": 0.5, "n": 2})
			ops.append({"op": "line", "rect": "es", "side": "S", "kinds": ["fridge", "counter2", "stove"], "gap": [0, 0], "container": true, "n": 2})
			ops.append({"op": "place", "kind": "cabinet", "in": "en", "anchor": "NE", "container": true})
		"terrace":
			# 4 x 6 inside: a kitchen behind a front room
			ops.append({"op": "split", "id": "h", "dir": "h", "at": 3, "into": ["tn", "ts"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [1, 2]}, "w": 2}], "names": ["kitchen", "front room"], "floors": ["KITCHEN", "WOOD"]})
			ops.append({"op": "line", "rect": "tn", "side": "N", "kinds": ["fridge", "counter2", "stove"], "gap": [0, 0], "container": true, "n": 3})
			ops.append({"op": "line", "rect": "ts", "side": "S", "kinds": ["bench", "shelf_s", "bed"], "gap": [0, 1], "container": 0.5, "n": 2})
			ops.append({"op": "place", "kind": "lamp", "in": "ts", "anchor": "SE"})
		_:
			# the corner shop, 8 x 7 inside: a shop floor and a storeroom
			ops.append({"op": "split", "id": "h", "dir": "v", "at": 5, "into": ["a", "b"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [3, 4]}, "w": 2}], "names": ["shop floor", "storeroom"], "floors": ["LINO", "WOOD"]})
			ops.append({"op": "rows", "rect": "a", "kinds": ["shelf"], "pitch": 3, "y0": 1, "margin": 1, "container": 0.8})
			ops.append({"op": "line", "rect": "a", "side": "N", "kinds": ["counter3", "fridge"], "gap": [0, 0], "container": true, "n": 2})
			ops.append({"op": "line", "rect": "b", "side": "N", "kinds": ["crate", "cans", "waterpack"], "gap": [0, 0], "container": true, "n": 3})
	ops.append({"op": "decals", "rect": "h", "kinds": ["papers", "blood", "stain"], "n": {"r": [1, 3]}})
	return ops


## Copies a built lot into the town's arrays and makes its House, Rooms, Doors and Containers.
func _stamp(built: Dictionary, lot: Rect2i, kind: String, front: String, fenced: bool, block: Vector2i, row: int) -> void:
	var cv = built.cv
	var ox := lot.position.x
	var oy := lot.position.y
	var lw := lot.size.x
	var lh := lot.size.y
	for y in lh:
		for x in lw:
			var i := (oy + y) * _size + ox + x
			var j := y * lw + x
			_terrain[i] = cv.terrain[j]
			_solid[i] = cv.solid[j]
	for o in cv.objects:
		o["cx"] = float(o.cx) + float(ox)
		o["cy"] = float(o.cy) + float(oy)
		for pc in o.pieces:
			pc["x"] = float(pc.x) + float(ox)
			pc["y"] = float(pc.y) + float(oy)
		_objects.append(o)
	for t in cv.trees:
		t["x"] = float(t.x) + float(ox)
		t["y"] = float(t.y) + float(oy)
		_trees.append(t)
	var hr: Rect2i = built.house
	var house_id := _houses.size()
	var rect := Rect2i(hr.position.x + ox, hr.position.y + oy, hr.size.x, hr.size.y)
	var room_ids: Array = []
	for a in cv.areas:
		if not bool(a.indoor):
			continue
		var r: Rect2i = a.rect
		var rr := Rect2i(r.position.x + ox, r.position.y + oy, r.size.x, r.size.y)
		var room := {"id": "h%d:%s" % [house_id, String(a.name)], "house": house_id, "name": String(a.name), "rect": rr}
		room_ids.append(_rooms.size())
		_rooms.append(room)
		_rooms_dict[String(room.id)] = [rr.position.x, rr.position.y, rr.end.x, rr.end.y]
	var door: Vector2i = built.door
	var reach: PackedByteArray = built.reach
	var rng := RandomNumberGenerator.new()
	rng.seed = _lot_index * 977 + 13
	var affinity: Dictionary = _lay.affinity
	var stocks := ["food", "water", "scrap", "ammo", "meds"]
	var cont_ids: Array = []
	for c in cv.cands:
		if rng.randf() > 0.8:
			continue
		var tile: Vector2i = SiteGen._stand_tile(cv, reach, c, rng)
		if tile.x < 0:
			continue
		var loot := {}
		for k in 2:
			var stock: String = stocks[rng.randi() % stocks.size()]
			if SiteGen._fit(c, stock, affinity) > 0.0:
				loot[stock] = int(loot.get(stock, 0)) + rng.randi_range(1, 3)
		if loot.is_empty():
			continue
		var room_idx := -1
		for ri in room_ids:
			if Rect2i(_rooms[ri].rect).has_point(Vector2i(tile.x + ox, tile.y + oy)):
				room_idx = ri
		var cid := "h%dc%d" % [house_id, cont_ids.size()]
		cont_ids.append(cid)
		_containers.append({
			"id": cid, "house": house_id, "room": room_idx,
			"pos": Vector2(float(tile.x + ox) + 0.5, float(tile.y + oy) + 0.5),
			"at": Vector2(float(c.obj.cx), float(c.obj.cy)),
			"kind": String(c.kind), "loot": loot, "search_s": 4.0,
		})
	var street_k := clampi((block.y - 1) if row == 0 else block.y, 0, _size / PITCH - 1)
	_houses.append({
		"id": house_id, "kind": kind,
		"address": "%d %s Street" % [lot.position.x, STREET_Y[street_k]],
		"block": block, "rect": rect, "lot": lot, "front": front, "fenced": fenced,
		"door": Vector2i(door.x + ox, door.y + oy),
		"doors": _doors_of(rect),
		"rooms": room_ids, "containers": cont_ids, "dead": [],
	})


## The doorways of a building: runs of door tiles in its rectangle (DOOR_WOOD), exterior ones on the ring.
func _doors_of(rect: Rect2i) -> Array:
	var door_t := int(_tids.DOOR_WOOD)
	var seen := {}
	var out: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if _terrain[y * _size + x] != door_t or seen.has(Vector2i(x, y)):
				continue
			var tiles: Array = [Vector2i(x, y)]
			seen[Vector2i(x, y)] = true
			# a run along x, else along y
			var horiz := x + 1 < rect.end.x and _terrain[y * _size + x + 1] == door_t
			var vert := y + 1 < rect.end.y and _terrain[(y + 1) * _size + x] == door_t
			var cx := x
			var cy := y
			while horiz and cx + 1 < rect.end.x and _terrain[cy * _size + cx + 1] == door_t:
				cx += 1
				tiles.append(Vector2i(cx, cy))
				seen[Vector2i(cx, cy)] = true
			while not horiz and vert and cy + 1 < rect.end.y and _terrain[(cy + 1) * _size + cx] == door_t:
				cy += 1
				tiles.append(Vector2i(cx, cy))
				seen[Vector2i(cx, cy)] = true
			var first: Vector2i = tiles[0]
			var side := ""
			var out_tile: Vector2i
			var in_tile: Vector2i
			var exterior := false
			if first.y == rect.position.y and not (not horiz and vert):
				side = "N"
				exterior = true
				out_tile = Vector2i(first.x, first.y - 1)
				in_tile = Vector2i(first.x, first.y + 1)
			elif first.y == rect.end.y - 1 and not (not horiz and vert):
				side = "S"
				exterior = true
				out_tile = Vector2i(first.x, first.y + 1)
				in_tile = Vector2i(first.x, first.y - 1)
			elif first.x == rect.position.x:
				side = "W"
				exterior = true
				out_tile = Vector2i(first.x - 1, first.y)
				in_tile = Vector2i(first.x + 1, first.y)
			elif first.x == rect.end.x - 1:
				side = "E"
				exterior = true
				out_tile = Vector2i(first.x + 1, first.y)
				in_tile = Vector2i(first.x - 1, first.y)
			elif horiz:
				side = "H"
				out_tile = Vector2i(first.x, first.y - 1)
				in_tile = Vector2i(first.x, first.y + 1)
			else:
				side = "V"
				out_tile = Vector2i(first.x - 1, first.y)
				in_tile = Vector2i(first.x + 1, first.y)
			out.append({"tiles": tiles, "exterior": exterior, "side": side, "out": out_tile, "in": in_tile})
	return out


# ----------------------------------------------------------- the edge, the streets' things --

func _edge_and_furniture() -> void:
	var t0 := Time.get_ticks_usec()
	var W := _size
	var H := _size
	var rng := _rng
	var road := int(_tids.ASPHALT)
	for y in H:
		for x in W:
			if x < EDGE or y < EDGE or x >= W - EDGE or y >= H - EDGE:
				var i := y * W + x
				_terrain[i] = int(_tids.GRASS)
				_solid[i] = 1
	for k in range(0, W, 3):
		for side in 4:
			var jitter := rng.randi_range(0, 1)
			var tx := 0
			var ty := 0
			match side:
				0:
					tx = k
					ty = jitter
				1:
					tx = k
					ty = H - 1 - jitter
				2:
					tx = jitter
					ty = k
				_:
					tx = W - 1 - jitter
					ty = k
			if rng.randf() < 0.7:
				_add_tree(tx, ty, false)
	# cars on the roads, lying along the kerb
	var block_n := _size / PITCH
	var cars := int(opts.get("cars", 70))
	var placed := 0
	var tries := cars * 30
	while placed < cars and tries > 0:
		tries -= 1
		var horiz := rng.randf() < 0.5
		var seg := rng.randi_range(0, block_n - 1)
		var cell := rng.randi_range(0, block_n - 1)
		var kind := "car_h" if horiz else "car_v"
		var fp: Vector2i = _street_cv.tiles_of(kind)
		var tx := 0
		var ty := 0
		if horiz:
			ty = PITCH * seg + BLOCK + rng.randi_range(0, 1) * 2
			tx = PITCH * cell + rng.randi_range(3, BLOCK - fp.x - 3)
		else:
			tx = PITCH * seg + BLOCK + rng.randi_range(0, 1) * 2
			ty = PITCH * cell + rng.randi_range(3, BLOCK - fp.y - 3)
		if tx < EDGE + 1 or ty < EDGE + 1 or tx + fp.x > W - EDGE - 1 or ty + fp.y > H - EDGE - 1:
			continue
		var clash := false
		for yy in fp.y:
			for xx in fp.x:
				var i := (ty + yy) * W + tx + xx
				if _solid[i] != 0 or _terrain[i] != road:
					clash = true
		if clash:
			continue
		var obj = _street_cv._decor(kind, tx, ty, 0.0, 0.0)
		if obj == null:
			continue
		obj["solid"] = true
		_objects.append(obj)
		for yy in fp.y:
			for xx in fp.x:
				_solid[(ty + yy) * W + tx + xx] = 1
		placed += 1
		_street_objs += 1
	# lamp posts and hydrants on the sidewalks, trees along them
	for by in block_n:
		for bx in block_n:
			var ox := bx * PITCH
			var oy := by * PITCH
			for k in 3:
				for kind in ["lamppost", "hydrant"]:
					if kind == "hydrant" and rng.randf() < 0.5:
						continue
					var tx := 0
					var ty := 0
					if rng.randf() < 0.5:
						tx = ox + rng.randi_range(2, BLOCK - 3)
						ty = oy + (0 if rng.randf() < 0.5 else BLOCK - 1)
					else:
						tx = ox + (0 if rng.randf() < 0.5 else BLOCK - 1)
						ty = oy + rng.randi_range(2, BLOCK - 3)
					if tx < EDGE or ty < EDGE or tx >= W - EDGE or ty >= H - EDGE:
						continue
					var obj = _street_cv._decor(kind, tx, ty, 0.0, 0.0)
					if obj != null:
						_objects.append(obj)
						_street_objs += 1
			for k in 4:
				var tx := ox + rng.randi_range(2, BLOCK - 3)
				var ty := oy + (1 if rng.randf() < 0.5 else BLOCK - 2)
				if rng.randf() < 0.5:
					tx = ox + (1 if rng.randf() < 0.5 else BLOCK - 2)
					ty = oy + rng.randi_range(2, BLOCK - 3)
				var i := ty * W + tx
				if tx < EDGE + 1 or ty < EDGE + 1 or tx >= W - EDGE - 1 or ty >= H - EDGE - 1:
					continue
				if _solid[i] != 0 or _terrain[i] != int(_tids.GRASS) or _clear_rect.has_point(Vector2i(tx, ty)):
					continue
				_add_tree(tx, ty, true)
	_tick("street_furniture", t0)


func _add_tree(tx: int, ty: int, shut: bool) -> void:
	var n := _rng.randi_range(0, 12)
	_trees.append({"x": float(tx) + 0.5, "y": float(ty) + 0.55, "variant": n % 3, "file": "res://assets/trees/tree_%d.png" % n})
	if shut:
		_solid[ty * _size + tx] = 1


# ------------------------------------------------------------------ the map, the indexes --

func _finish_map() -> void:
	var t0 := Time.get_ticks_usec()
	var W := _size
	var H := _size
	_objects.sort_custom(func(a, b):
		var ka: float = float(a.layer) * 1000.0 + float(a.cy) + float(a.h) / 2.0
		var kb: float = float(b.layer) * 1000.0 + float(b.cy) + float(b.h) / 2.0
		if ka != kb:
			return ka < kb
		return int(a.id) < int(b.id))
	for i in _objects.size():
		_objects[i]["id"] = i
		_objects[i]["order"] = i
	var shut: Array = Array(_solid)
	var zeros: Array = []
	zeros.resize(W * H)
	zeros.fill(0)
	var d := _base.duplicate(false)
	d["W"] = W
	d["H"] = H
	d["terrainTypes"] = _terrain_types
	d["terrain"] = Array(_terrain)
	d["solidZ"] = shut
	d["solidP"] = shut.duplicate()
	d["wall"] = zeros
	d["objects"] = _objects
	d["marks"] = _marks
	d["walls"] = []
	d["segments"] = []
	d["trees"] = _trees
	d["lights"] = []
	d["rooms"] = _rooms_dict
	d["spawns"] = [[float(PITCH * (_blocks / 2 - 1) + BLOCK) + 2.5, float(EDGE) + 1.5]]
	d["yard"] = [1, 1, W - 1, H - 1]
	d["people"] = []
	d["bonds"] = []
	d["workshop"] = {"x": 0.0, "y": 0.0, "what": "At home"}
	_result = {"data": d}
	# which house and which room holds each tile
	_tile_house.resize(W * H)
	_tile_house.fill(-1)
	_tile_room.resize(W * H)
	_tile_room.fill(-1)
	for h in _houses:
		var r: Rect2i = h.rect
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_tile_house[y * W + x] = int(h.id)
	for ri in _rooms.size():
		var rr: Rect2i = _rooms[ri].rect
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				_tile_room[y * W + x] = ri
	_tick("finish", t0)


# ------------------------------------------------------- the start, the rescues, the dead --

func _people() -> void:
	var t0 := Time.get_ticks_usec()
	var W := _size
	var H := _size
	var rng := _rng
	var d: Dictionary = _result.data
	# the start house: the medium one of the clear lot the block loop made (the middle block's south row)
	var start_house := _start_house
	if start_house < 0:
		start_house = 0
	var start_room := _roomiest(start_house)
	var start_pos := _free_spot(start_room)
	d["workshop"] = {"x": start_pos.x, "y": start_pos.y - 1.0, "what": "At home"}
	var start_c := Vector2(Rect2i(_houses[start_house].rect).get_center())
	# the rescue candidates, one ring after another round the start (the rings are 22 to 48 tiles, 48 to 80, 80 and more in the full town, a third of that
	# in a small one), spread apart: RESCUE_COUNT of the full town, `opts.rescue` of any
	var rescue: Array = []
	var scale := float(_size) / float(DEFAULT_SIZE)
	var want := int(opts.get("rescue", RESCUE_COUNT if _blocks >= 6 else 2))
	var apart_min := 18.0 if _blocks >= 6 else 8.0
	var rings := [[22.0 * scale, 48.0 * scale], [48.0 * scale, 80.0 * scale], [80.0 * scale, 400.0]]
	var per_ring := int(ceil(float(want) / 3.0))
	for ri in rings.size():
		var pool: Array = []
		for h in _houses:
			if int(h.id) == start_house or h.rooms.size() < 2:
				continue
			var dist := Vector2(Rect2i(h.rect).get_center()).distance_to(start_c)
			if dist >= rings[ri][0] and dist < rings[ri][1]:
				pool.append(int(h.id))
		var picked := 0
		var guard := 0
		while picked < per_ring and rescue.size() < want and not pool.is_empty() and guard < 200:
			guard += 1
			var hid: int = pool[rng.randi() % pool.size()]
			var c := Vector2(Rect2i(_houses[hid].rect).get_center())
			var apart := true
			for r in rescue:
				if Vector2(Rect2i(_houses[int(r.house)].rect).get_center()).distance_to(c) < apart_min:
					apart = false
			if not apart:
				pool.erase(hid)
				continue
			var room := _roomiest(hid)
			rescue.append({"house": hid, "pos": _free_spot(room), "room": room, "ring": ri + 1, "dist": c.distance_to(start_c)})
			pool.erase(hid)
			picked += 1
	rescue.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
	var dead := _dead(start_house, rescue)
	for i in dead.size():
		var hid := int(dead[i].house)
		if hid >= 0:
			_houses[hid].dead.append(i)
	_tick("people_and_dead", t0)
	var by_kind := {}
	for h in _houses:
		by_kind[h.kind] = int(by_kind.get(h.kind, 0)) + 1
	_ms["total"] = float(Time.get_ticks_usec() - _started) / 1000.0
	_result["seed"] = seed_value
	_result["version"] = VERSION
	_result["size"] = Vector2i(W, H)
	_result["houses"] = _houses
	_result["rooms"] = _rooms
	_result["containers"] = _containers
	_result["dead"] = dead
	_result["start"] = {"house": start_house, "pos": start_pos, "room": start_room, "ring": _ring_report(start_house)}
	_result["rescue"] = rescue
	_result["tile_house"] = _tile_house
	_result["tile_room"] = _tile_room
	_result["streets"] = {"pitch": PITCH, "block": BLOCK, "road": ROAD, "names_x": STREET_X, "names_y": STREET_Y}
	_result["stats"] = {"houses": _houses.size(), "by_kind": by_kind, "rooms": _rooms.size(), "containers": _containers.size(), "dead": dead.size(), "objects": _objects.size(), "trees": _trees.size(), "street_objects": _street_objs, "ms": _ms}


## The clear ring of the start lot, for the tests and the layout: the lot's rectangle, and how many tiles of its border and the row inside it are free (open ground,
## no picture of a prop, a tree or a mark on them). `free == total` is the promise.
func _ring_report(house_id: int) -> Dictionary:
	var lot: Rect2i = _houses[house_id].lot
	var taken := {}
	for o in _objects:
		var x0 := floori(float(o.cx) - float(o.w) / 2.0 + 0.01)
		var x1 := ceili(float(o.cx) + float(o.w) / 2.0 - 0.01)
		var y0 := floori(float(o.cy) - float(o.h) / 2.0 + 0.01)
		var y1 := ceili(float(o.cy) + float(o.h) / 2.0 - 0.01)
		for y in range(y0, y1):
			for x in range(x0, x1):
				taken[Vector2i(x, y)] = true
	for t in _trees:
		taken[Vector2i(floori(float(t.x)), floori(float(t.y)))] = true
	var total := 0
	var free := 0
	for y in range(lot.position.y, lot.end.y):
		for x in range(lot.position.x, lot.end.x):
			var edge := mini(mini(x - lot.position.x, lot.end.x - 1 - x), mini(y - lot.position.y, lot.end.y - 1 - y))
			if edge > 1:
				continue
			total += 1
			if _solid[y * _size + x] == 0 and not taken.has(Vector2i(x, y)):
				free += 1
	return {"rect": lot, "total": total, "free": free}


## The index of the roomiest room of a house.
func _roomiest(house_id: int) -> int:
	var best := -1
	var best_area := -1
	for ri in _houses[house_id].rooms:
		var rr: Rect2i = _rooms[ri].rect
		if rr.size.x * rr.size.y > best_area:
			best_area = rr.size.x * rr.size.y
			best = int(ri)
	return best


## A free tile near the middle of a room, as a point in tiles.
func _free_spot(room: int) -> Vector2:
	var rr: Rect2i = _rooms[room].rect
	var mid := Vector2(rr.get_center())
	var best := Vector2(mid.x + 0.5, mid.y + 0.5)
	var best_d := INF
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			if _solid[y * _size + x] != 0:
				continue
			var dd := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(mid)
			if dd < best_d:
				best_d = dd
				best = Vector2(float(x) + 0.5, float(y) + 0.5)
	return best


## The dead as data records: about 60% in or beside the houses, 40% in the streets in loose groups; three in the start house, a guard of two to
## four in every house of the rescue list.
func _dead(start_house: int, rescue: Array) -> Array:
	var rng := _rng
	var W := _size
	var H := _size
	var total := int(opts.get("dead", maxi(40, roundi(float(DEAD_TOTAL) * float(_blocks * _blocks) / 36.0))))
	var keep_clear := 22.0 * maxf(float(_size) / float(DEFAULT_SIZE), 0.4)    # (how near the start the yards and the streets hold none)
	var out: Array = []
	var near_house := roundi(float(total) * DEAD_NEAR_HOUSES)
	var in_street := total - near_house
	var taken := {}
	var start_c := Vector2(Rect2i(_houses[start_house].rect).get_center())
	var kinds_for := func(r: float) -> String:
		return "brute" if r < 0.03 else ("runner" if r < 0.15 else "walker")
	var road := int(_tids.ASPHALT)
	var walk := int(_tids.SIDEWALK)
	var floor_tiles: Array = []
	var weights: Array = []
	for h in _houses:
		var tiles: Array = []
		var r: Rect2i = h.rect
		for y in range(r.position.y + 1, r.end.y - 1):
			for x in range(r.position.x + 1, r.end.x - 1):
				if _solid[y * W + x] == 0 and _tile_room[y * W + x] >= 0:
					tiles.append(Vector2i(x, y))
		floor_tiles.append(tiles)
		weights.append(float(tiles.size()) if int(h.id) != start_house else 0.0)
	var total_w := 0.0
	for w in weights:
		total_w += float(w)
	var made_in := 0
	var guarded := {}
	for r in rescue:
		guarded[int(r.house)] = true
		total_w -= float(weights[int(r.house)])
		weights[int(r.house)] = 0.0
	# `room` >= 0 puts it in that room, -1 anywhere in the house
	var put_inside := func(hid: int, kind: String, state: String, room: int, avoid: int) -> bool:
		var tiles: Array = floor_tiles[hid]
		if room >= 0:
			tiles = tiles.filter(func(t): return _tile_room[t.y * W + t.x] == room)
		elif avoid >= 0:
			var others: Array = tiles.filter(func(t): return _tile_room[t.y * W + t.x] != avoid)
			if not others.is_empty():
				tiles = others
		if tiles.is_empty():
			return false
		for attempt in 40:
			var tile: Vector2i = tiles[rng.randi() % tiles.size()]
			var p := Vector2(float(tile.x) + rng.randf_range(0.25, 0.75), float(tile.y) + rng.randf_range(0.25, 0.75))
			if Vector2(_houses[hid].door).distance_to(p) < 2.5 or not _spaced(taken, p, 1.6):
				continue
			_take(taken, p)
			out.append({"pos": p, "kind": kind, "state": state, "house": hid, "room": _tile_room[tile.y * W + tile.x], "group": -1})
			return true
		return false
	# the three of the start house, then the guards of the rescue houses: two to four, the first in the room of the survivor (who stands where it is
	# not taken: the survivor's tile is kept clear of them)
	for k in 3:
		if put_inside.call(start_house, "walker", "still", -1, -1):
			made_in += 1
	for r in rescue:
		_take(taken, Vector2(r.pos))
	for r in rescue:
		for k in 2 + rng.randi() % 3:
			var in_room: int = int(r.room) if k == 0 else -1
			if put_inside.call(int(r.house), "walker" if rng.randf() < 0.85 else "runner", "still", in_room, int(r.room)):
				made_in += 1
	var inside_n := roundi(float(near_house) * 0.78)
	var guard := 0
	while made_in < inside_n and guard < inside_n * 60:
		guard += 1
		var at := rng.randf() * total_w
		var hi := 0
		for i in weights.size():
			at -= float(weights[i])
			if at < 0.0:
				hi = i
				break
		if floor_tiles[hi].is_empty():
			continue
		if put_inside.call(hi, kinds_for.call(rng.randf()), "still" if rng.randf() < 0.85 else "wander", -1, -1):
			made_in += 1
	# beside the houses: grass of the lots, front and back
	var yard_n := near_house - made_in
	var made := 0
	guard = 0
	while made < yard_n and guard < yard_n * 80:
		guard += 1
		var hi := rng.randi() % _houses.size()
		if hi == start_house or guarded.has(hi):
			continue
		var lot: Rect2i = _houses[hi].lot
		var x := rng.randi_range(lot.position.x, lot.end.x - 1)
		var y := rng.randi_range(lot.position.y, lot.end.y - 1)
		if _solid[y * W + x] != 0 or _terrain[y * W + x] != int(_tids.GRASS) or _tile_house[y * W + x] >= 0:
			continue
		var p := Vector2(float(x) + rng.randf_range(0.25, 0.75), float(y) + rng.randf_range(0.25, 0.75))
		if p.distance_to(start_c) < keep_clear or not _spaced(taken, p, 1.6):
			continue
		_take(taken, p)
		out.append({"pos": p, "kind": kinds_for.call(rng.randf()), "state": "still" if rng.randf() < 0.8 else "wander", "house": hi, "room": -1, "group": -1})
		made += 1
	# the streets: loose groups of three to eight on the paving
	made = 0
	var group := 0
	guard = 0
	while made < in_street and guard < 400:
		guard += 1
		var cx := rng.randi_range(EDGE + 4, W - EDGE - 5)
		var cy := rng.randi_range(EDGE + 4, H - EDGE - 5)
		var ci := cy * W + cx
		if (_terrain[ci] != road and _terrain[ci] != walk) or _solid[ci] != 0:
			continue
		var centre := Vector2(float(cx) + 0.5, float(cy) + 0.5)
		if centre.distance_to(start_c) < keep_clear * 1.2:
			continue
		var n := mini(rng.randi_range(3, 8), in_street - made)
		var got := 0
		var t2 := 0
		while got < n and t2 < 60:
			t2 += 1
			var p := centre + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
			var pi := floori(p.y) * W + floori(p.x)
			if pi < 0 or pi >= W * H or _solid[pi] != 0 or (_terrain[pi] != road and _terrain[pi] != walk):
				continue
			if not _spaced(taken, p, 1.2):
				continue
			_take(taken, p)
			out.append({"pos": p, "kind": kinds_for.call(rng.randf()), "state": "still" if rng.randf() < 0.6 else "wander", "house": -1, "room": -1, "group": group})
			got += 1
		made += got
		group += 1
	return out


static func _spaced(taken: Dictionary, p: Vector2, d: float) -> bool:
	var gx := floori(p.x / 2.0)
	var gy := floori(p.y / 2.0)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell: Array = taken.get(Vector2i(gx + dx, gy + dy), [])
			for q in cell:
				if Vector2(q).distance_to(p) < d:
					return false
	return true


static func _take(taken: Dictionary, p: Vector2) -> void:
	var key := Vector2i(floori(p.x / 2.0), floori(p.y / 2.0))
	if not taken.has(key):
		taken[key] = []
	taken[key].append(p)


# ----------------------------------------------------------------------- helpers --

## The house whose walls hold a tile (point in tiles), or -1.
static func house_at(town: Dictionary, x: float, y: float) -> int:
	var tx := floori(x)
	var ty := floori(y)
	var w := int(town.size.x)
	if tx < 0 or ty < 0 or tx >= w or ty >= int(town.size.y):
		return -1
	return int(town.tile_house[ty * w + tx])


## The room (index) whose floor holds a point, or -1 (a wall, a doorway, outside).
static func room_at(town: Dictionary, x: float, y: float) -> int:
	var tx := floori(x)
	var ty := floori(y)
	var w := int(town.size.x)
	if tx < 0 or ty < 0 or tx >= w or ty >= int(town.size.y):
		return -1
	return int(town.tile_room[ty * w + tx])


## A number that is the same for the same town: the terrain, the houses, the containers and the dead (a test pins it for a seed).
static func digest(town: Dictionary) -> int:
	var h := 2166136261
	for v in town.data.terrain:
		h = ((h ^ int(v)) * 16777619) & 0xFFFFFFFF
	for hs in town.houses:
		var r: Rect2i = hs.rect
		for v in [r.position.x, r.position.y, r.size.x, r.size.y, hs.doors.size(), hs.rooms.size()]:
			h = ((h ^ int(v)) * 16777619) & 0xFFFFFFFF
	for c in town.containers:
		h = ((h ^ roundi(float(c.pos.x) * 4.0)) * 16777619) & 0xFFFFFFFF
		h = ((h ^ roundi(float(c.pos.y) * 4.0)) * 16777619) & 0xFFFFFFFF
	for dd in town.dead:
		h = ((h ^ roundi(float(dd.pos.x) * 100.0)) * 16777619) & 0xFFFFFFFF
		h = ((h ^ roundi(float(dd.pos.y) * 100.0)) * 16777619) & 0xFFFFFFFF
	return h
