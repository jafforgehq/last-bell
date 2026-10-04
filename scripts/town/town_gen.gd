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
##   "data" also carries `kit`, what the art kit needs (scripts/town/town_world.gd reads it, all of it optional): "ground" (PackedByteArray W*H: the ground a tile has, an index into
##                 TownArt.GROUNDS + 1, 0 = by the terrain: the floors of the rooms by type, the paths), "wall" (PackedByteArray: the material of a wall top, TownArt.WALL_MATS), "line"
##                 (PackedByteArray: a fence or hedge cell, TownArt.LINES), "windows" ([{"x", "y", "orient": "h"|"v", "state": "intact"|"broken"|"boarded", "variant", "bar"}]), "gates"
##                 ([{"x", "y", "w", "orient"}]), "houses" ([[x, y, w, h] of each house's walls]); and each object of the kit has `kit` (the item), `facing` or `orient`, `variant`, `state`
##                 and, inside a house, `in` (the house's id).
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
const TownArt := preload("res://scripts/town/town_art.gd")

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
## What the art kit needs (see the header: `data.kit`).
var _kit_ground := PackedByteArray()
var _kit_wall := PackedByteArray()
var _kit_line := PackedByteArray()
var _windows: Array = []
var _gates: Array = []
## Its own dice for the choices of the art (variants, the dressing of the streets), so that the dead, the rescues and the doors do not depend on them.
var _art_rng := RandomNumberGenerator.new()


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
	_lay = _layouts()
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
	_kit_ground.resize(_size * _size)
	_kit_ground.fill(0)
	_kit_wall.resize(_size * _size)
	_kit_wall.fill(0)
	_kit_line.resize(_size * _size)
	_kit_line.fill(0)
	_windows = []
	_gates = []
	_art_rng.seed = seed_in * 40503 + 99
	_door_t = int(_tids.DOOR_WOOD)
	_kit_info = {}
	for k in _lay.props:
		var pr: Dictionary = _lay.props[k]
		if pr.has("kit"):
			_kit_info[k] = [int(pr.tiles[0]), int(pr.tiles[1]), bool(pr.get("solid", true)), bool(pr.get("loose", false))]


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


## One lot on a canvas of its own (the lot's size, no more): the yard, an optional fence, the house with its rooms, furniture and trees, and the yard's dressing (path, step, bushes,
## mailbox, bins, a shed...). Everything is the art kit's (`kit` fields on the objects, `_layouts`), the start lot only gets the path and the step in its clear ring.
func _build_lot(lot_seed: int, kind: String, lot: Rect2i, front: String, fenced: bool, start: bool = false) -> Dictionary:
	var lw := lot.size.x
	var lh := lot.size.y
	var hs: Vector2i = KINDS[kind]
	var lay := _layouts()
	var cv := Canvas.new()
	cv.setup(lw, lh, lot_seed, lay.props, _tids, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = lot_seed * 31 + 7
	var hx := 0 if kind == "terrace" else (lw - hs.x) >> 1    # (the start lot is four wider than its house: two tiles each side)
	var hy := 3 if front == "N" else lh - 3 - hs.y
	var back := "S" if front == "N" else "N"
	var fat := rng.randi_range(2, maxi(2, hs.x - 4))
	var bat := rng.randi_range(1, maxi(1, hs.x - 3))
	var ops: Array = []
	var gates: Array = []
	if fenced:
		var gate_at := clampi(hx + fat - 1, 1, lw - 5)
		ops.append({"op": "fence", "rect": [0, 0, lw, lh], "t": "WALL_METAL", "gates": [{"side": front, "at": gate_at, "w": 4}]})
		gates.append({"x": gate_at, "y": lh - 1 if front == "S" else 0, "w": 4, "orient": "h", "fenced": true})
	var doors: Array = [{"side": front, "at": fat, "w": 2}, {"side": back, "at": bat, "w": 2}]
	if kind == "shop":
		doors = [{"side": front, "at": mini(fat, 3), "w": 2}, {"side": back, "at": hs.x - 3, "w": 2}]
	ops.append({"op": "building", "rect": [hx, hy, hs.x, hs.y], "wall": "WALL_BRICK", "floor": "WOOD", "id": "h", "doors": doors})
	ops.append_array(_structure(kind))
	if kind != "terrace" and not start:
		ops.append({"op": "trees", "rect": [0, 0, lw, lh], "n": {"r": [0, 2]}, "on": ["GRASS"], "gap": 3})
	var door := Vector2i(hx + (fat if kind != "shop" else mini(fat, 3)), hy - 1 if front == "N" else hy + hs.y)
	var back_door := Vector2i(hx + (bat if kind != "shop" else hs.x - 3), hy + hs.y if front == "N" else hy - 1)
	cv.entry = door
	var t1 := Time.get_ticks_usec()
	cv.run({"ops": ops})
	_tick("lot_structure", t1)
	t1 = Time.get_ticks_usec()
	_furnish(cv, rng, kind, start)
	_tick("lot_furnish", t1)
	t1 = Time.get_ticks_usec()
	var dressing := _dress_lot(cv, rng, kind, lot, front, Rect2i(hx, hy, hs.x, hs.y), door, back_door, start, fenced)
	for g in gates:
		dressing.gates.append(g)
	_tick("lot_yard", t1)
	t1 = Time.get_ticks_usec()
	_kitify(cv, rng)
	var reach := cv.flood()
	_tick("lot_kit_flood", t1)
	return {"cv": cv, "house": Rect2i(hx, hy, hs.x, hs.y), "door": door, "reach": reach, "dressing": dressing}


## The rooms of a template as site-canvas ops (walls, doors, names, floors). The building's inner rectangle is "h". What goes in the rooms is `_furnish`'s.
static func _structure(kind: String) -> Array:
	var ops: Array = []
	match kind:
		"small":
			# 6 x 5 inside: a living room and, behind a wall, a bedroom and a bathroom
			ops.append({"op": "split", "id": "h", "dir": "v", "at": 3, "into": ["w", "e"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [1, 2]}, "w": 2}], "names": ["living room", "side"], "floors": ["WOOD", "WOOD"]})
			ops.append({"op": "split", "id": "e", "dir": "h", "at": 2, "into": ["en", "es"], "wall": "WALL_PLASTER", "doors": [{"at": 0, "w": 1}], "names": ["bedroom", "bathroom"], "floors": ["WOOD", "KITCHEN"]})
		"medium":
			# 8 x 6 inside: bedroom, living room, bathroom, kitchen
			ops.append({"op": "split", "id": "h", "dir": "v", "at": 4, "into": ["w", "e"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [1, 3]}, "w": 2}], "names": ["west", "east"], "floors": ["WOOD", "WOOD"]})
			ops.append({"op": "split", "id": "w", "dir": "h", "at": 3, "into": ["wn", "ws"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [0, 1]}, "w": 2}], "names": ["bedroom", "living room"], "floors": ["WOOD", "WOOD"]})
			ops.append({"op": "split", "id": "e", "dir": "h", "at": 3, "into": ["en", "es"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [0, 1]}, "w": 1}], "names": ["bathroom", "kitchen"], "floors": ["KITCHEN", "KITCHEN"]})
		"terrace":
			# 4 x 6 inside: a kitchen behind a front room
			ops.append({"op": "split", "id": "h", "dir": "h", "at": 3, "into": ["tn", "ts"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [1, 2]}, "w": 2}], "names": ["kitchen", "front room"], "floors": ["KITCHEN", "WOOD"]})
		_:
			# the corner shop, 8 x 7 inside: a shop floor and a storeroom
			ops.append({"op": "split", "id": "h", "dir": "v", "at": 5, "into": ["a", "b"], "wall": "WALL_PLASTER", "doors": [{"at": {"r": [3, 4]}, "w": 2}], "names": ["shop floor", "storeroom"], "floors": ["LINO", "WOOD"]})
	return ops


# ----------------------------------------------------------------- the furniture --
# Rooms are small (a living room of 4 x 2, a bathroom of 2 x 2), so a recipe lists where each thing may go, in order of liking, and the canvas takes the first spot that does not shut a
# door or cut the floor in two (`_put` says no, and the next spot is tried). Everything stands with its back to a wall (`_kitify` turns it).

## Puts `kind` on the first of `spots` (top left tiles) that takes it; true when one did. `container`: it may be searched (the catalogue says what kind of container it is).
func _try(cv, kind: String, spots: Array, container: bool = false, keep: bool = false) -> bool:
	for sp in spots:
		if _put_kit(cv, kind, int(sp.x), int(sp.y), container, keep):
			return true
	return false


## One thing of the kit on a spot, by the town's rules (the site canvas's own are meant for rooms of a raid site: they keep two tiles clear of every door and test that nothing is cut off by
## flooding the whole canvas, which in a room of 4 x 2 leaves no spot and in a town of 180 lots costs seconds): nothing within a tile of a door cell, a spot that is free (and, for a yard,
## not in the kept path), and nothing that cuts the floor in two (`_safe`). `keep` makes the kept tiles of the canvas count (the yard's: the path from the door).
func _put_kit(cv, kind: String, tx: int, ty: int, container: bool = false, keep: bool = false) -> bool:
	var info: Array = _kit_info[kind]
	var fw: int = info[0]
	var fh: int = info[1]
	var W: int = cv.W
	if tx < 0 or ty < 0 or tx + fw > W or ty + fh > cv.H:
		return false
	var solid_item: bool = info[2]
	var loose: bool = info[3]
	var sol: PackedByteArray = cv.solid
	var terr: PackedInt32Array = cv.terrain
	if solid_item and not loose:
		for yy in range(ty, ty + fh):
			for xx in range(tx, tx + fw):
				if sol[yy * W + xx] != 0:
					return false
	elif loose:
		if sol[(ty + (fh >> 1)) * W + tx + (fw >> 1)] != 0:
			return false
	if solid_item:
		# (not on a doorway, and not in front of one: the four tiles round a door cell are left clear)
		var door_t := _door_t
		var kp: PackedByteArray = cv.keep
		for yy in range(ty, ty + fh):
			for xx in range(tx, tx + fw):
				var i: int = yy * W + xx
				if terr[i] == door_t:
					return false
				if (xx > 0 and terr[i - 1] == door_t) or (xx < W - 1 and terr[i + 1] == door_t) or (yy > 0 and terr[i - W] == door_t) or (yy < cv.H - 1 and terr[i + W] == door_t):
					return false
				if keep and kp[i] != 0:
					return false
		if not loose and not _safe(cv, tx, ty, fw, fh):
			return false
	var opts := {"force": true}
	if container:
		opts["container"] = true
	return cv._put(kind, tx, ty, opts) != null


## Whether shutting a footprint leaves the open tiles round it joined. First the cheap proof: if the open tiles of the ring round it are one run, nothing can be cut off; else if they are
## all joined to each other within 4 tiles of the footprint, without passing through it, nothing can; only when that fails is the exact test (flooding the canvas) made.
var _kit_info := {}
var _door_t := 23
var _ring := PackedByteArray()
var _seen := PackedByteArray()
var _queue := PackedInt32Array()


func _safe(cv, tx: int, ty: int, tw: int, th: int) -> bool:
	var W: int = cv.W
	var H: int = cv.H
	var sol: PackedByteArray = cv.solid
	var x0 := tx - 1
	var y0 := ty - 1
	var x1 := tx + tw
	var y1 := ty + th
	if _ring.size() < 64:
		_ring.resize(64)
		_seen.resize(400)
		_queue.resize(400)
	var n := 0
	for x in range(x0, x1 + 1):
		_ring[n] = 1 if (x >= 0 and x < W and y0 >= 0 and y0 < H and sol[y0 * W + x] == 0) else 0
		n += 1
	for y in range(y0 + 1, y1 + 1):
		_ring[n] = 1 if (x1 >= 0 and x1 < W and y >= 0 and y < H and sol[y * W + x1] == 0) else 0
		n += 1
	for x in range(x1 - 1, x0 - 1, -1):
		_ring[n] = 1 if (x >= 0 and x < W and y1 >= 0 and y1 < H and sol[y1 * W + x] == 0) else 0
		n += 1
	for y in range(y1 - 1, y0, -1):
		_ring[n] = 1 if (x0 >= 0 and x0 < W and y >= 0 and y < H and sol[y * W + x0] == 0) else 0
		n += 1
	var runs := 0
	var open_n := 0
	for i in n:
		if _ring[i] == 1:
			open_n += 1
			if _ring[(i + 1) % n] == 0:
				runs += 1
	if runs < 2 or open_n < 2:
		return true
	# a small flood in the window round the footprint
	var wx0 := maxi(0, x0 - 3)
	var wy0 := maxi(0, y0 - 3)
	var wx1 := mini(W, x1 + 4)
	var wy1 := mini(H, y1 + 4)
	var ww := wx1 - wx0
	var wh := wy1 - wy0
	if ww * wh > 400:
		return cv._stays_connected(tx, ty, tw, th)
	for i in ww * wh:
		_seen[i] = 0
	# start at the first open tile of the ring
	var sx := -1
	var sy := -1
	for yy in range(maxi(0, y0), mini(H, y1 + 1)):
		for xx in range(maxi(0, x0), mini(W, x1 + 1)):
			if sx < 0 and sol[yy * W + xx] == 0 and not (xx >= tx and xx < tx + tw and yy >= ty and yy < ty + th):
				sx = xx
				sy = yy
	var head := 0
	var tail := 0
	_queue[tail] = (sy - wy0) * ww + sx - wx0
	tail += 1
	_seen[_queue[0]] = 1
	var reached := 1
	while head < tail:
		var c := _queue[head]
		head += 1
		var cx := c % ww + wx0
		var cy := c / ww + wy0
		for k in 4:
			var nx := cx + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := cy + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < wx0 or ny < wy0 or nx >= wx1 or ny >= wy1:
				continue
			if nx >= tx and nx < tx + tw and ny >= ty and ny < ty + th:
				continue
			var si := (ny - wy0) * ww + nx - wx0
			if _seen[si] != 0 or sol[ny * W + nx] != 0:
				continue
			_seen[si] = 1
			_queue[tail] = si
			tail += 1
			if nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1:
				reached += 1
	if reached >= open_n:
		return true
	return cv._stays_connected(tx, ty, tw, th)


func _furnish(cv, rng: RandomNumberGenerator, kind: String, start: bool) -> void:
	for a in cv.areas:
		if not bool(a.indoor):
			continue
		var r: Rect2i = a.rect
		match String(a.name):
			"kitchen":
				_kitchen(cv, rng, r, true)
			"bathroom":
				_bathroom(cv, rng, r)
			"bedroom":
				_bedroom(cv, rng, r, start)
			"living room":
				_living(cv, rng, r, kind == "small", start)
			"front room":
				_living(cv, rng, r, false, start)
			"shop floor":
				_shop(cv, rng, r)
			"storeroom":
				_storeroom(cv, rng, r)
	# the clutter of a house somebody left: papers, glass, a stain or two
	var h: Rect2i = cv.rects.get("h", Rect2i())
	if h.size.x > 0:
		cv._run_ops([{"op": "decals", "rect": [h.position.x, h.position.y, h.size.x, h.size.y], "kinds": ["papers", "broken_glass", "blood_stain"], "n": {"r": [1, 3]}}])
	if start:
		_start_house_extras(cv, rng, h)


## Puts the things of `items` ([kind, container] each) along the row `y` between `x0` and `x1` (the end excluded), in order from the left (from the right when `rev`), each at the first
## free spot from where the last one ended (a doorway's front is skipped). Returns how many went in; the rest did not fit.
func _line(cv, y: int, x0: int, x1: int, items: Array, rev: bool = false) -> int:
	var placed := 0
	var x := x0
	var xe := x1
	for it in items:
		var kind: String = it[0]
		var w: int = cv.tiles_of(kind).x
		var done := false
		if rev:
			while xe - w >= x0 and not done:
				if _put_kit(cv, kind, xe - w, y, bool(it[1])):
					done = true
					xe -= w
				else:
					xe -= 1
		else:
			while x + w <= x1 and not done:
				if _put_kit(cv, kind, x, y, bool(it[1])):
					done = true
					x += w
				else:
					x += 1
		if not done:
			break
		placed += 1
	return placed


## A kitchen: a fridge, counters (one may be a sink), a stove, a cupboard when the room is wide, along the north wall (the south one when a door is in the way); a table and chairs when it is deep.
func _kitchen(cv, rng: RandomNumberGenerator, r: Rect2i, table: bool) -> void:
	var w := r.size.x
	var items: Array = []
	if w >= 5:
		items = [["fridge", true], ["kitchen_counter", rng.randf() < 0.8], ["kitchen_sink", false], ["stove", false], ["cupboard", rng.randf() < 0.8]]
	elif w == 4:
		items = [["fridge", true], ["kitchen_counter", rng.randf() < 0.8], ["kitchen_sink", false], ["stove", false]]
	elif w == 3:
		items = [["fridge", true], ["kitchen_sink", false] if rng.randf() < 0.5 else ["kitchen_counter", rng.randf() < 0.8], ["stove", false]]
	elif w == 2:
		items = [["fridge", true], ["stove", false]]
	else:
		items = [["fridge", true]]
	var rev := rng.randf() < 0.3
	var n := _line(cv, r.position.y, r.position.x, r.end.x, items, rev)
	if n < items.size() and r.size.y >= 2:
		_line(cv, r.end.y - 1, r.position.x, r.end.x, items.slice(n), rev)
	if table and r.size.y >= 3 and w >= 4:
		var ty := r.end.y - 1
		if _put_kit(cv, "dining_table", r.position.x + 1, ty):
			_put_kit(cv, "chair", r.position.x, ty)
			_put_kit(cv, "chair", r.position.x + 3, ty)


func _bathroom(cv, rng: RandomNumberGenerator, r: Rect2i) -> void:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var rev := rng.randf() < 0.5
	if w >= 3 and h >= 3:
		var n := _line(cv, y, x, r.end.x, [["bathtub", false], ["toilet", false]], rev)
		if n < 2:
			_line(cv, r.end.y - 1, x, r.end.x, [["bathtub", false], ["toilet", false]].slice(n), rev)
		_try(cv, "washbasin", [Vector2i(x + w - 1, y + 1), Vector2i(x, y + 1), Vector2i(x + w - 1, y + h - 1), Vector2i(x, y + h - 1)])
		_try(cv, "medicine_cabinet", [Vector2i(x, y + h - 1), Vector2i(x + w - 1, y + h - 1)], true)
	elif w >= 2:
		var n := _line(cv, y, x, r.end.x, [["toilet", false], ["washbasin", false]], rev)
		if n < 2:
			_line(cv, r.end.y - 1, x, r.end.x, [["toilet", false], ["washbasin", false]].slice(n), rev)
		if h >= 2 and rng.randf() < 0.5:
			_try(cv, "laundry_basket", [Vector2i(x, y + h - 1), Vector2i(x + w - 1, y + h - 1), Vector2i(x, y)])


func _bedroom(cv, rng: RandomNumberGenerator, r: Rect2i, start: bool) -> void:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var double := w >= 4 and h >= 3 and rng.randf() < 0.4
	var bw := 2 if double else 1
	var left: Array = []
	for sx in range(x, x + w - bw + 1):
		left.append(Vector2i(sx, y))
	if rng.randf() < 0.5:
		left.reverse()
	var bed_x := -1
	for sp in left:
		if _put_kit(cv, "bed_double" if double else "bed_single", sp.x, sp.y):
			bed_x = sp.x
			break
	if bed_x < 0 and not double:
		# a bed with its foot to the north wall (the head at the south): along the south wall
		for sx in range(x, x + w):
			if _put_kit(cv, "bed_single", sx, r.end.y - 2):
				bed_x = sx
				break
	if bed_x >= 0:
		_try(cv, "nightstand", [Vector2i(bed_x + bw, y), Vector2i(bed_x - 1, y)], rng.randf() < 0.7)
	var along: Array = []
	for sx in range(x, x + w - 1):
		along.append(Vector2i(sx, y))
	_try(cv, "wardrobe" if rng.randf() < 0.55 else "dresser", along, true)
	if h >= 3:
		var low: Array = []
		for sx in range(x, x + w - 1):
			low.append(Vector2i(sx, y + h - 1))
		_try(cv, "dresser" if rng.randf() < 0.5 else "wardrobe", low, false)
	if rng.randf() < 0.55:
		_try(cv, "lamp_floor", [Vector2i(x + w - 1, y + h - 1), Vector2i(x, y + h - 1), Vector2i(x + w - 1, y)])
	if w >= 3 and h >= 3:
		_put_kit(cv, "rug_round", x + (w - 2) / 2, y + (h - 2) / 2 + (1 if h >= 4 else 0))


## A living room (a front room): a sofa at one long wall, a television or a bookshelf at the other, an armchair, a lamp, a rug; `kitchen` the kitchenette of a small house.
func _living(cv, rng: RandomNumberGenerator, r: Rect2i, kitchen: bool, start: bool) -> void:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var top := y
	if kitchen:
		_kitchen(cv, rng, Rect2i(x, y, w, 1), false)
		top = y + 2
	var rh := r.end.y - top
	if w >= 3 and rh >= 2:
		_put_kit(cv, "rug_rect", x, top + (rh - 2) / 2)
	var seat := "sofa" if w >= 3 else "loveseat"
	var seat_w := 3 if w >= 3 else 2
	var south_first := rng.randf() < 0.6 or kitchen or start
	var rows: Array = [r.end.y - 1, top] if south_first else [top, r.end.y - 1]
	var seat_row := -1
	for row in rows:
		if row < top:
			continue
		var spots: Array = []
		for k in range(0, w - seat_w + 1):
			spots.append(Vector2i(x + k, row))
		if start:
			spots.reverse()
			spots = [spots[spots.size() - 1]]
		if _try(cv, seat, spots):
			seat_row = row
			break
	if seat_row < 0 and w >= 2 and not start:
		# no room for the sofa between the doors: a loveseat
		for row in rows:
			if row >= top and _try(cv, "loveseat", [Vector2i(x, row), Vector2i(x + w - 2, row), Vector2i(x + 1, row)]):
				seat_row = row
				break
	if start:
		return
	var other := top if seat_row != top else r.end.y - 1
	if seat_row >= 0 and other != seat_row and not kitchen:
		var spots: Array = []
		for k in range(0, w - 1):
			spots.append(Vector2i(x + k, other))
		if rng.randf() < 0.6:
			_try(cv, "tv_stand", spots)
		else:
			_try(cv, "bookshelf", spots, other == top)
	if rh >= 3 and w >= 3:
		_try(cv, "armchair", [Vector2i(x + w - 1, top + 1), Vector2i(x, top + 1)])
	if rh >= 4 and w >= 3:
		_put_kit(cv, "coffee_table", x + (w - 2) / 2, top + rh / 2)
	if rng.randf() < 0.55:
		_try(cv, "lamp_floor", [Vector2i(x + w - 1, top), Vector2i(x, top), Vector2i(x + w - 1, r.end.y - 1)])


func _shop(cv, rng: RandomNumberGenerator, r: Rect2i) -> void:
	cv._run_ops([
		{"op": "rows", "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "kinds": ["shelf_tins"], "pitch": 3, "y0": 1, "margin": 1, "container": 0.8},
		{"op": "line", "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "side": "N", "kinds": ["kitchen_counter", "fridge"], "gap": [0, 0], "container": true, "n": 3},
	])


func _storeroom(cv, rng: RandomNumberGenerator, r: Rect2i) -> void:
	cv._run_ops([
		{"op": "line", "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "side": "N", "kinds": ["crate", "box", "toolbox"], "gap": [0, 0], "container": true, "n": 3},
		{"op": "scatter", "rect": [r.position.x, r.position.y + 2, r.size.x, maxi(1, r.size.y - 2)], "kinds": ["box", "crate"], "n": 2, "wall": true, "container": 0.7},
	])


## A home left in a hurry (the demo starts in it): a mattress on the floor of the living room, a bag, boxes in a corner, a window or two barricaded, glass under them.
func _start_house_extras(cv, rng: RandomNumberGenerator, h: Rect2i) -> void:
	for a in cv.areas:
		if not bool(a.indoor):
			continue
		var r: Rect2i = a.rect
		match String(a.name):
			"living room":
				_put_kit(cv, "bedroll", r.end.x - 1, r.position.y)
				_put_kit(cv, "dropped_bag", r.end.x - 2, r.end.y - 1)
				_put_kit(cv, "papers", r.position.x, r.end.y - 1)
			"kitchen":
				_try(cv, "box", [Vector2i(r.end.x - 1, r.end.y - 1), Vector2i(r.end.x - 1, r.position.y)], true)
				_put_kit(cv, "papers", r.position.x + 1, r.end.y - 1)
			"bedroom":
				_try(cv, "box", [Vector2i(r.end.x - 1, r.end.y - 1), Vector2i(r.position.x, r.end.y - 1)], true)
				_put_kit(cv, "broken_glass", r.position.x + 1, r.end.y - 1)


# ------------------------------------------------------------------- the yard --

## The path from the door to the street, the step, bushes beside it, a mailbox, a bin, then in the back whatever fits (a garden bed, a shed, a bench, a swing set), a car on gravel, a fence or
## hedge across the front. The start lot gets only the path and the front step. Returns {"ground": [[x, y, code]], "lines": [[x, y, code]], "gates": [...]} (lot coordinates).
func _dress_lot(cv, rng: RandomNumberGenerator, kind: String, lot: Rect2i, front: String, house: Rect2i, door: Vector2i, back_door: Vector2i, start: bool, fenced: bool) -> Dictionary:
	var lw := lot.size.x
	var lh := lot.size.y
	var out := {"ground": [], "lines": [], "gates": []}
	var south := front == "S"
	var dir := 1 if south else -1
	var path_code := TownArt.GROUNDS.find("sidewalk") + 1
	var gravel_code := TownArt.GROUNDS.find("gravel") + 1
	var dx0 := door.x
	var rows := (lh - door.y) if south else (door.y + 1)
	for k in rows:
		var yy := door.y + dir * k
		for xx in [dx0, dx0 + 1]:
			out.ground.append([xx, yy, path_code])
	cv._keep_rect(Rect2i(dx0 - 1, (door.y if south else 0), 4, rows), true)
	var step_variant := rng.randi_range(0, 1)
	var o = cv._decor("step", dx0 - 1, door.y, 0.0, 0.0)
	if o != null:
		o["facing"] = "s" if south else "n"
		o["variant"] = step_variant
	if start:
		return out
	# the back door's step
	if back_door.y >= 0 and back_door.y < lh:
		var bo = cv._decor("step", back_door.x - 1, back_door.y, 0.0, 0.0)
		if bo != null:
			bo["facing"] = "n" if south else "s"
			bo["variant"] = step_variant
	var row_front := lh - 2 if south else 1
	var row_edge := lh - 1 if south else 0
	var row_door := door.y
	# a lot that fronts the edge of the map has no street: its front yard is only reached along its sides, so nothing is put across it
	var closed_front := (not south and lot.position.y <= EDGE) or (south and lot.end.y >= _size - EDGE)
	# a fence or hedge across the front, with a gap for the path (a third of the open lots)
	if not fenced and not closed_front and rng.randf() < 0.34:
		var styles := [1, 1, 2, 2, 3, 4, 5]
		var style: int = styles[rng.randi() % styles.size()]
		var gx := dx0 - 1
		for xx in lw:
			if xx >= gx and xx < gx + 4:
				continue
			if cv.is_open(xx, row_front) and cv.terrain[row_front * lw + xx] == int(_tids.GRASS):
				cv.solid[row_front * lw + xx] = 1
				out.lines.append([xx, row_front, style])
		if style <= 2:
			out.gates.append({"x": gx, "y": row_front, "w": 4, "orient": "h"})
	# beside the step
	if not closed_front:
		for bx in [dx0 - 2, dx0 + 3]:
			if rng.randf() < 0.6:
				_put_kit(cv, "bush", bx, row_door, false, true)
		if rng.randf() < 0.7:
			_try(cv, "mailbox", [Vector2i(dx0 + 3, row_edge), Vector2i(dx0 - 2, row_edge), Vector2i(dx0 + 4, row_edge)], false, true)
		if rng.randf() < 0.55:
			_try(cv, "bin", [Vector2i(house.position.x - 1, row_door), Vector2i(house.end.x, row_door), Vector2i(house.end.x, row_door - dir)], false, true)
	if rng.randf() < 0.12:
		_put_kit(cv, "bike", dx0 + 3, row_door + dir, false, true)
	# a car on a gravel pad in the front yard
	if kind != "terrace" and not closed_front and rng.randf() < 0.14:
		var cars: Array = [Vector2i(dx0 + 3, row_edge if south else 0), Vector2i(dx0 - 5, row_edge if south else 0)]
		for cp in cars:
			var cy: int = cp.y - 1 if south else cp.y
			if cp.x >= 0 and cp.x + 4 <= lw and _put_kit(cv, "car_h", cp.x, cy, false, true):
				for yy in [cy, cy + 1]:
					for xx in range(cp.x - 1, cp.x + 5):
						if xx >= 0 and xx < lw:
							out.ground.append([xx, yy, gravel_code])
				break
	# the back yard: the rows on the other side of the house
	var back_y0 := 0 if south else house.end.y
	var back_rows := house.position.y if south else lh - house.end.y
	if back_rows >= 1:
		if rng.randf() < 0.3:
			_ground_round(cv, out, _scatter(cv, rng, "garden_bed", 1, lw - 4, back_y0, back_y0 + back_rows - 1), TownArt.GROUNDS.find("dirt_path") + 1)
		if back_rows >= 2 and rng.randf() < 0.2:
			_ground_round(cv, out, _scatter(cv, rng, "shed", 1, lw - 4, back_y0, back_y0 + back_rows - 2), gravel_code)
		if back_rows >= 2 and kind != "terrace" and rng.randf() < 0.1:
			_scatter(cv, rng, "swing_set", 1, lw - 4, back_y0, back_y0 + back_rows - 2)
		if rng.randf() < 0.14:
			_scatter(cv, rng, "bench", 1, lw - 3, back_y0, back_y0 + back_rows - 1)
		if rng.randf() < 0.12:
			_scatter(cv, rng, "bin", 0, lw - 1, back_y0, back_y0 + back_rows - 1)
	# litter in the grass
	# (not near the lot's edge: a decal is a picture a little wider than its tile, and the start lot's clear ring must stay clear of its neighbours' litter)
	cv._run_ops([{"op": "decals", "rect": [2, 2, maxi(1, lw - 4), maxi(1, lh - 4)], "kinds": ["papers", "dropped_bag"], "n": {"r": [0, 2]}}])
	return out


## `kind` on a free spot of a region of the lot (a few tries); the thing, or null.
func _scatter(cv, rng: RandomNumberGenerator, kind: String, x0: int, x1: int, y0: int, y1: int):
	for t in 10:
		var tx := rng.randi_range(x0, maxi(x0, x1))
		var ty := rng.randi_range(y0, maxi(y0, y1))
		if _put_kit(cv, kind, tx, ty, false, true):
			return cv.objects[cv.objects.size() - 1]
	return null


## The ground round a thing of the back yard (bare soil round a garden bed, gravel before a shed), as codes for the lot's `ground` list.
func _ground_round(cv, out: Dictionary, o, code: int) -> void:
	if o == null:
		return
	var x0 := int(round(float(o.cx) - float(o.w) / 2.0)) - 1
	var y0 := int(round(float(o.cy) - float(o.h) / 2.0)) - 1
	for yy in range(y0, y0 + int(o.h) + 2):
		for xx in range(x0, x0 + int(o.w) + 2):
			if cv._in(xx, yy) and cv.terrain[yy * cv.W + xx] == int(_tids.GRASS) and cv.solid[yy * cv.W + xx] == 0:
				out.ground.append([xx, yy, code])


# ---------------------------------------------------------------- the art kit --

## The layouts the town's lots are built from (assets/data/site_layouts.json plus the kit's things, built once): each kit thing a catalogue entry with its footprint (for the facing south),
## `kit` the item, `container` the kind the sim knows it by (the kit's item id, so that the picture of a searched one is the kit's `opened`), `orient` for the things drawn along an axis.
static var _town_lay := {}
## kind, folder of the picture, footprint w, h, layer (1 decal, 2 low, 4 tall), solid, the container kind
const KIT_PROPS := [
	["fridge", "furniture", 1, 1, 2, true, "fridge"], ["kitchen_counter", "furniture", 1, 1, 2, true, "kitchen_counter"], ["kitchen_sink", "furniture", 1, 1, 2, true, ""],
	["stove", "furniture", 1, 1, 2, true, ""], ["cupboard", "furniture", 1, 1, 2, true, "cupboard"], ["wardrobe", "furniture", 2, 1, 2, true, "wardrobe"],
	["dresser", "furniture", 2, 1, 2, true, "dresser"], ["nightstand", "furniture", 1, 1, 2, true, "nightstand"], ["bed_single", "furniture", 1, 2, 2, true, ""],
	["bed_double", "furniture", 2, 2, 2, true, ""], ["sofa", "furniture", 3, 1, 2, true, ""], ["loveseat", "furniture", 2, 1, 2, true, ""], ["armchair", "furniture", 1, 1, 2, true, ""],
	["tv_stand", "furniture", 2, 1, 2, true, ""], ["coffee_table", "furniture", 2, 1, 2, true, ""], ["dining_table", "furniture", 2, 1, 2, true, ""], ["chair", "furniture", 1, 1, 2, true, ""],
	["bookshelf", "furniture", 2, 1, 2, true, "bookshelf"], ["desk", "furniture", 2, 1, 2, true, "desk"], ["toilet", "furniture", 1, 1, 2, true, ""],
	["bathtub", "furniture", 2, 1, 2, true, ""], ["washbasin", "furniture", 1, 1, 2, true, ""], ["medicine_cabinet", "furniture", 1, 1, 2, true, "medicine_cabinet"],
	["toolbox", "furniture", 1, 1, 2, true, "toolbox"], ["workbench", "furniture", 2, 1, 2, true, "workbench"], ["box", "furniture", 1, 1, 2, true, "box"],
	["crate", "furniture", 1, 1, 2, true, "crate"], ["laundry_basket", "furniture", 1, 1, 2, true, ""], ["shelf_tins", "furniture", 2, 1, 2, true, "shelf_tins"],
	["lamp_floor", "furniture", 1, 1, 2, false, ""],
	["rug_rect", "furniture", 3, 2, 1, false, ""], ["rug_round", "furniture", 2, 2, 1, false, ""], ["papers", "furniture", 1, 1, 1, false, ""],
	["broken_glass", "furniture", 1, 1, 1, false, ""], ["blood_stain", "furniture", 1, 1, 1, false, ""], ["dropped_bag", "furniture", 1, 1, 1, false, ""],
	["bedroll", "furniture", 1, 2, 1, false, "", "mattress"], ["step", "house", 3, 1, 1, false, ""],
	["bush", "outdoors", 1, 1, 4, true, ""], ["mailbox", "outdoors", 1, 1, 2, true, ""], ["bin", "outdoors", 1, 1, 2, true, ""], ["bike", "outdoors", 2, 1, 2, false, ""],
	["garden_bed", "outdoors", 3, 1, 2, true, ""], ["shed", "outdoors", 3, 2, 4, true, ""], ["swing_set", "outdoors", 3, 2, 4, true, ""], ["slide", "outdoors", 1, 3, 4, true, ""],
	["bench", "outdoors", 2, 1, 2, true, ""], ["car_wreck", "outdoors", 4, 3, 4, true, ""], ["hydrant", "street", 1, 1, 2, false, ""], ["streetlamp", "street", 1, 1, 4, false, ""],
]
## Things drawn along an axis (the manifest has `orient`, not `facing`, for them) and their axis; and the cars (the kit's `car`).
const KIT_ORIENT := {"bike": "h", "garden_bed": "h", "swing_set": "h"}
## The containers' loot: each new kind is like an old one of the raid sites' table (`affinity`), times a factor.
const KIT_LIKE := {
	"kitchen_counter": ["counter", 1.0], "cupboard": ["cabinet", 1.0], "wardrobe": ["cabinet", 0.8], "dresser": ["cabinet", 0.9], "nightstand": ["cabinet", 0.6],
	"bookshelf": ["shelf", 0.8], "shelf_tins": ["shelf", 1.3], "desk": ["cabinet", 0.7], "toolbox": ["locker", 1.0], "workbench": ["counter", 1.1],
	"medicine_cabinet": ["cabinet", 0.5], "box": ["crate", 1.0],
}


static func _layouts() -> Dictionary:
	if not _town_lay.is_empty():
		return _town_lay
	var base: Dictionary = SiteGen.layouts()
	var lay: Dictionary = base.duplicate(false)
	var props: Dictionary = (base.props as Dictionary).duplicate(false)
	lay["props"] = props
	lay["affinity"] = (base.affinity as Dictionary).duplicate(true)
	for row in KIT_PROPS:
		var kind: String = row[0]
		# (the kit's item may go by another name than the thing's: a "bedroll" is the kit's mattress, but not what the sim calls a mattress, a bed for the sick: scripts/sim/medical.gd)
		var item: String = String(row[7]) if row.size() > 7 else kind
		var e := {"files": [item], "dir": "town/%s" % String(row[1]), "tiles": [int(row[2]), int(row[3])], "layer": int(row[4]), "solid": bool(row[5]), "kit": item}
		if not bool(row[5]):
			e["loose"] = true
		if String(row[6]) != "":
			e["container"] = String(row[6])
		if KIT_ORIENT.has(kind):
			e["orient"] = KIT_ORIENT[kind]
		props[kind] = e
	for k in ["car_h", "car_v"]:
		var horiz: bool = k == "car_h"
		props[k] = {"files": ["car"], "dir": "town/outdoors", "tiles": [4, 2] if horiz else [2, 4], "layer": 4, "solid": true, "kit": "car", "orient": "h" if horiz else "v", "container": "trunk"}
	var aff: Dictionary = lay.affinity
	for stock in aff:
		var table: Dictionary = aff[stock]
		for k in KIT_LIKE:
			var like: Array = KIT_LIKE[k]
			table[k] = float(table.get(like[0], 0.0)) * float(like[1])
	aff.meds["medicine_cabinet"] = 4.0
	aff.meds["nightstand"] = 2.0
	# a car on the road is not searched for its boot in the town, as the raid sites' are not either
	_town_lay = lay
	return _town_lay


## Gives the objects of a canvas their kit fields: the item, the variant, the facing (the back to the wall it stands at), and the container's `closed` state.
func _kitify(cv, rng: RandomNumberGenerator) -> void:
	var props: Dictionary = cv.props
	for o in cv.objects:
		var p: Dictionary = props.get(String(o.kind), {})
		if p.has("kit"):
			_kit_set(o, p, rng)
			_face(cv, o, p)
	# a searched container is shown open by the view of the base (scripts/render/base_props_view.gd) drawn facing south: only what faces south, or is the same from all sides, can be one
	var keep: Array = []
	for c in cv.cands:
		var it: Dictionary = c.obj
		var facing := String(it.get("facing", "s"))
		if facing == "s":
			keep.append(c)
		elif String(it.get("kit", "")) in ["crate", "box", "toolbox"]:
			it["facing"] = "s"
			keep.append(c)
	cv.cands = keep


func _kit_set(o: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	o["kit"] = String(p.kit)
	var n := TownArt.variants_of(String(p.kit))
	o["variant"] = rng.randi() % n if n > 1 else 0
	if p.has("orient"):
		o["orient"] = String(p.orient)
	if p.has("container"):
		o["state"] = "closed"
	o["pieces"] = []


## The way a thing faces: its back to the wall it stands against (the longest run of wall along one side; only north and south for what is not square).
func _face(cv, o: Dictionary, p: Dictionary) -> void:
	if p.has("orient") or int(o.layer) == 1:
		return
	var w := int(o.w)
	var h := int(o.h)
	var tx := roundi(float(o.cx) - float(w) / 2.0)
	var ty := roundi(float(o.cy) - float(h) / 2.0)
	var n := 0
	var s := 0
	var we := 0
	var ea := 0
	for k in w:
		if cv._wall_at(tx + k, ty - 1):
			n += 1
		if cv._wall_at(tx + k, ty + h):
			s += 1
	for k in h:
		if cv._wall_at(tx - 1, ty + k):
			we += 1
		if cv._wall_at(tx + w, ty + k):
			ea += 1
	var best := "s"
	var score := 0
	if n > score:
		best = "s"
		score = n
	if s > score:
		best = "n"
		score = s
	if w == h:
		if we > score:
			best = "e"
			score = we
		if ea > score:
			best = "w"
	o["facing"] = best


## Copies a built lot into the town's arrays and makes its House, Rooms, Doors and Containers.
func _stamp(built: Dictionary, lot: Rect2i, kind: String, front: String, fenced: bool, block: Vector2i, row: int) -> void:
	var cv = built.cv
	var ox := lot.position.x
	var oy := lot.position.y
	var lw := lot.size.x
	var lh := lot.size.y
	var metal := int(_tids.WALL_METAL)
	var fence_style := _fence_style(_lot_index)
	for y in lh:
		for x in lw:
			var i := (oy + y) * _size + ox + x
			var j := y * lw + x
			_terrain[i] = cv.terrain[j]
			_solid[i] = cv.solid[j]
			if cv.terrain[j] == metal:
				_kit_line[i] = fence_style
	var dressing: Dictionary = built.dressing
	for g in dressing.ground:
		_kit_ground[(oy + int(g[1])) * _size + ox + int(g[0])] = int(g[2])
	for l in dressing.lines:
		_kit_line[(oy + int(l[1])) * _size + ox + int(l[0])] = int(l[2])
	for g in dressing.gates:
		# (a gate's leaves are drawn for the picket fences only: a chain link or a low wall has an opening)
		if bool(g.get("fenced", false)) and fence_style > 2:
			continue
		_gates.append({"x": ox + int(g.x), "y": oy + int(g.y), "w": int(g.w), "orient": String(g.orient)})
	var hr: Rect2i = built.house
	var house_id := _houses.size()
	var rect := Rect2i(hr.position.x + ox, hr.position.y + oy, hr.size.x, hr.size.y)
	for o in cv.objects:
		o["cx"] = float(o.cx) + float(ox)
		o["cy"] = float(o.cy) + float(oy)
		for pc in o.pieces:
			pc["x"] = float(pc.x) + float(ox)
			pc["y"] = float(pc.y) + float(oy)
		if o.has("kit") and rect.has_point(Vector2i(floori(float(o.cx)), floori(float(o.cy)))):
			o["in"] = house_id
		_objects.append(o)
	for t in cv.trees:
		t["x"] = float(t.x) + float(ox)
		t["y"] = float(t.y) + float(oy)
		_trees.append(t)
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
	var doors := _doors_of(rect)
	_kit_house(house_id, rect, cv.areas, ox, oy, doors)
	_houses.append({
		"id": house_id, "kind": kind,
		"address": "%d %s Street" % [lot.position.x, STREET_Y[street_k]],
		"block": block, "rect": rect, "lot": lot, "front": front, "fenced": fenced,
		"door": Vector2i(door.x + ox, door.y + oy),
		"doors": doors,
		"rooms": room_ids, "containers": cont_ids, "dead": [],
	})


## The line of a fenced lot (a code of TownArt.LINES): picket (white or brown), chain link or a low brick wall.
func _fence_style(lot_index: int) -> int:
	var h := (lot_index * 2246822519 + seed_value * 3266489917) & 0xffff
	var pick := h % 100
	if pick < 30:
		return 1
	if pick < 55:
		return 2
	if pick < 80:
		return 3
	return 4


## The wall material of a house (a code of TownArt.WALL_MATS): the start house is brick, the others by a hash of their id.
func _wall_material(house_id: int) -> int:
	if house_id == _start_house:
		return 1
	var h := (house_id * 2654435761 + seed_value * 40503) & 0xffff
	var pick := h % 100
	if pick < 34:
		return 1
	if pick < 48:
		return 2
	if pick < 58:
		return 3
	if pick < 74:
		return 4
	if pick < 84:
		return 5
	return 6


## The kit's data of one house: the floor of each room by its name, the material of the outside walls, the windows (on the outside walls, away from the corners and the doors).
func _kit_house(house_id: int, rect: Rect2i, areas: Array, ox: int, oy: int, doors: Array) -> void:
	for a in areas:
		if not bool(a.indoor):
			continue
		var code := TownArt.GROUNDS.find(String(TownArt.FLOOR_OF_ROOM.get(String(a.name), "floor_wood"))) + 1
		var fr: Rect2i = a.rect
		for yy in range(fr.position.y, fr.end.y):
			for xx in range(fr.position.x, fr.end.x):
				_kit_ground[(yy + oy) * _size + xx + ox] = code
	var mat := _wall_material(house_id)
	var wall_t := int(_tids.WALL_BRICK)
	var door_set := {}
	for dd in doors:
		for t in dd.tiles:
			door_set[t] = true
	# the walls inside: plaster mostly, a sage or sand wash in some houses (the start house keeps the plaster of the kit's sample)
	var inside := 7
	if house_id != _start_house:
		var ih := (house_id * 40503 + seed_value * 977) % 100
		inside = 7 if ih < 60 else (5 if ih < 80 else 4)
	var plaster_t := int(_tids.WALL_PLASTER)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var edge := x == rect.position.x or y == rect.position.y or x == rect.end.x - 1 or y == rect.end.y - 1
			if edge and _terrain[y * _size + x] == wall_t:
				_kit_wall[y * _size + x] = mat
			elif _terrain[y * _size + x] == plaster_t:
				_kit_wall[y * _size + x] = inside
	var wrng := RandomNumberGenerator.new()
	wrng.seed = house_id * 7919 + seed_value * 131 + 5
	var boarded_bias := 0.05 if house_id != _start_house else 0.0
	for side in 4:
		var horiz := side < 2
		var span := rect.size.x if horiz else rect.size.y
		var pos := 2 + wrng.randi_range(0, 1)
		while pos < span - 2:
			var x := rect.position.x + pos if horiz else (rect.position.x if side == 2 else rect.end.x - 1)
			var y := (rect.position.y if side == 0 else rect.end.y - 1) if horiz else rect.position.y + pos
			var free := true
			for k in range(-1, 2):
				var q := Vector2i(x + k, y) if horiz else Vector2i(x, y + k)
				if door_set.has(q) or _terrain[q.y * _size + q.x] != wall_t:
					free = false
			# (not where a wall of the inside meets this one)
			var inward := Vector2i(x, y + (1 if side == 0 else -1)) if horiz else Vector2i(x + (1 if side == 2 else -1), y)
			if _terrain[inward.y * _size + inward.x] == int(_tids.WALL_PLASTER):
				free = false
			if free:
				var r := wrng.randf()
				var state := "intact" if r < 0.74 - boarded_bias else ("broken" if r < 0.86 else "boarded")
				_windows.append({"x": x, "y": y, "orient": "h" if horiz else "v", "state": state, "variant": wrng.randi_range(0, 1), "bar": false, "house": house_id})
			pos += 3 + wrng.randi_range(0, 1)
	# the start house: somebody has boarded up the windows on the street side (the west wall) and put planks over one of them
	if house_id == _start_house:
		var west: Array = []
		for w in _windows:
			if int(w.house) == house_id and int(w.x) == rect.position.x:
				west.append(w)
		for k in west.size():
			west[k]["state"] = "boarded"
			west[k]["bar"] = k == 0


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
	# cars on the roads (the kit's, 4 tiles long), lying along the kerb; here and there a wreck across a lane
	var block_n := _size / PITCH
	var cars := int(opts.get("cars", 70))
	var wrecks := int(opts.get("wrecks", roundi(10.0 * float(block_n * block_n) / 36.0)))
	var placed := 0
	var wrecked := 0
	var tries := (cars + wrecks) * 30
	var props: Dictionary = _street_cv.props
	while (placed < cars or wrecked < wrecks) and tries > 0:
		tries -= 1
		var wreck := placed >= cars or (wrecked < wrecks and rng.randf() < 0.12)
		var horiz := rng.randf() < 0.5
		var seg := rng.randi_range(0, block_n - 1)
		var cell := rng.randi_range(0, block_n - 1)
		var kind := "car_wreck" if wreck else ("car_h" if horiz else "car_v")
		var fp: Vector2i = _street_cv.tiles_of(kind)
		var tx := 0
		var ty := 0
		if wreck:
			# 4 x 3, one lane and a half of the road (the road is 4 tiles wide: the way past is the rest), along x or along y
			if horiz:
				ty = PITCH * seg + BLOCK + rng.randi_range(0, 1)
				tx = PITCH * cell + rng.randi_range(3, BLOCK - fp.x - 3)
			else:
				fp = Vector2i(fp.y, fp.x)
				tx = PITCH * seg + BLOCK + rng.randi_range(0, 1)
				ty = PITCH * cell + rng.randi_range(3, BLOCK - fp.y - 3)
		elif horiz:
			ty = PITCH * seg + BLOCK + rng.randi_range(0, 1) * 2
			tx = PITCH * cell + rng.randi_range(3, BLOCK - fp.x - 3)
		else:
			tx = PITCH * seg + BLOCK + rng.randi_range(0, 1) * 2
			ty = PITCH * cell + rng.randi_range(3, BLOCK - fp.y - 3)
		if tx < EDGE + 1 or ty < EDGE + 1 or tx + fp.x > W - EDGE - 1 or ty + fp.y > H - EDGE - 1:
			continue
		var clash := false
		var pad := 1 if wreck else 0
		for yy in range(-pad, fp.y + pad):
			for xx in range(-pad, fp.x + pad):
				var i := (ty + yy) * W + tx + xx
				var inside := yy >= 0 and yy < fp.y and xx >= 0 and xx < fp.x
				if i < 0 or i >= W * H or _solid[i] != 0 or (inside and _terrain[i] != road):
					clash = true
		if clash:
			continue
		var obj = _street_cv._decor(kind, tx, ty, 0.0, 0.0)
		if obj == null:
			continue
		if wreck and not horiz:
			# (a wreck lying along y: the same picture turned, so it is told its footprint the other way round)
			obj["w"] = float(fp.x)
			obj["h"] = float(fp.y)
			obj["cx"] = float(tx) + float(fp.x) / 2.0
			obj["cy"] = float(ty) + float(fp.y) / 2.0
			obj["turn"] = 1
		_kit_set(obj, props[kind], _art_rng)
		obj["solid"] = true
		_objects.append(obj)
		for yy in fp.y:
			for xx in fp.x:
				_solid[(ty + yy) * W + tx + xx] = 1
		if wreck:
			wrecked += 1
		else:
			placed += 1
		_street_objs += 1
	# lamp posts and hydrants on the sidewalks (the arm of a lamp leans out over the street), trees along them
	for by in block_n:
		for bx in block_n:
			var ox := bx * PITCH
			var oy := by * PITCH
			for k in 4:
				for kind in ["streetlamp", "hydrant"]:
					if kind == "hydrant" and rng.randf() < 0.55:
						continue
					var tx := 0
					var ty := 0
					var arm := "n"
					if rng.randf() < 0.5:
						tx = ox + rng.randi_range(2, BLOCK - 3)
						if rng.randf() < 0.5:
							ty = oy
						else:
							ty = oy + BLOCK - 1
							arm = "s"
					else:
						ty = oy + rng.randi_range(2, BLOCK - 3)
						if rng.randf() < 0.5:
							tx = ox
							arm = "w"
						else:
							tx = ox + BLOCK - 1
							arm = "e"
					if tx < EDGE or ty < EDGE or tx >= W - EDGE or ty >= H - EDGE:
						continue
					var obj = _street_cv._decor(kind, tx, ty, 0.0, 0.0)
					if obj != null:
						_kit_set(obj, props[kind], _art_rng)
						if kind == "streetlamp":
							obj["facing"] = arm
						else:
							obj["variant"] = 0 if _art_rng.randf() < 0.85 else 1
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
	# litter and stains on the pavement and in the road (a few to a block): papers, a dropped bag, glass, a stain
	var litter := ["papers", "papers", "dropped_bag", "broken_glass", "blood_stain", "broken_glass"]
	var walk := int(_tids.SIDEWALK)
	for by in block_n:
		for bx in block_n:
			for k in 6:
				var kind: String = litter[_art_rng.randi() % litter.size()]
				var tx := bx * PITCH + _art_rng.randi_range(2, PITCH - 3)
				var ty := by * PITCH + _art_rng.randi_range(2, PITCH - 3)
				# (sidewalks are the block's border rows and columns, the road is the last four of the 32)
				if _art_rng.randf() < 0.55:
					if _art_rng.randf() < 0.5:
						ty = by * PITCH + (0 if _art_rng.randf() < 0.5 else BLOCK - 1)
					else:
						tx = bx * PITCH + (0 if _art_rng.randf() < 0.5 else BLOCK - 1)
				else:
					if _art_rng.randf() < 0.5:
						ty = by * PITCH + BLOCK + _art_rng.randi_range(0, 3)
					else:
						tx = bx * PITCH + BLOCK + _art_rng.randi_range(0, 3)
				if tx < EDGE + 1 or ty < EDGE + 1 or tx >= W - EDGE - 1 or ty >= H - EDGE - 1:
					continue
				var ti := ty * W + tx
				if _solid[ti] != 0 or (_terrain[ti] != walk and _terrain[ti] != road) or (_clear_rect.size.x > 0 and _clear_rect.grow(2).has_point(Vector2i(tx, ty))):
					continue
				var obj = _street_cv._decor(kind, tx, ty, _art_rng.randf_range(-0.25, 0.25), _art_rng.randf_range(-0.25, 0.25))
				if obj != null:
					_kit_set(obj, props[kind], _art_rng)
					_objects.append(obj)
					_street_objs += 1
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
	var house_rects: Array = []
	for h in _houses:
		var hr: Rect2i = h.rect
		house_rects.append([hr.position.x, hr.position.y, hr.size.x, hr.size.y])
	d["kit"] = {"ground": _kit_ground, "wall": _kit_wall, "line": _kit_line, "windows": _windows, "gates": _gates, "houses": house_rects}
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
			rescue.append({"house": hid, "pos": _hide_spot(room, hid), "room": room, "ring": ri + 1, "dist": c.distance_to(start_c)})
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


## Where a survivor hides in their room: the free tile farthest from every doorway of the house, a corner by preference (one who has barred themselves in keeps clear of the
## way in: not in the line of the front door, where the avatar walks in and the dead stand). The middle of the room (`_free_spot`) when the room has no free tile.
func _hide_spot(room: int, house_id: int) -> Vector2:
	var rr: Rect2i = _rooms[room].rect
	var best := _free_spot(room)
	var best_score := -INF
	var ways: Array = []
	for d in _houses[house_id].doors:
		for t in d.tiles:
			ways.append(Vector2(float(t.x) + 0.5, float(t.y) + 0.5))
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			if _solid[y * _size + x] != 0:
				continue
			var at := Vector2(float(x) + 0.5, float(y) + 0.5)
			var near := INF
			for w in ways:
				near = minf(near, at.distance_to(w))
			var corners := 0
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _solid[(y + dv.y) * _size + (x + dv.x)] != 0:
					corners += 1
			var score := (near if near < INF else 0.0) + 0.4 * float(corners)
			if score > best_score:
				best_score = score
				best = at
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
