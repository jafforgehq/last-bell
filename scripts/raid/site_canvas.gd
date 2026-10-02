## The tile canvas a site is drawn on (round 14, see site_gen.gd): the ground, the walls and doors, the props, the
## trees, the rooms and the containers that a layout's ops (assets/data/site_layouts.json) lay down, in tiles.
## It keeps the walking grid (a tile is shut by a wall or by a solid prop) and never lets a prop cut the way from the
## entry to anything that could be reached before the prop was put down.
##
## A layout is a list of ops, run in order (see `run`). Every op is a Dictionary with "op" and its own fields; a field
## that names a rectangle is [x, y, w, h] in tiles, or the id of one made earlier (the room of a building, the two
## halves of a split...), and any number may be {"r": [lo, hi]} for a whole number drawn from the site's seed.
extends RefCounted

const GD := preload("res://scripts/game_data.gd")

## What a door keeps clear on each side of its gap (tiles), so that no prop stands in a doorway.
const DOOR_KEEP := 2
## How far each way from the entry the street is kept clear of props (tiles).
const APRON_HALF := 11

var W := 0
var H := 0
var rng := RandomNumberGenerator.new()
## The prop catalogue (the layouts' "props") and the terrain names with their ids.
var props: Dictionary = {}
var tids: Dictionary = {}
var terrain := PackedInt32Array()
## 1 where a wall, a solid prop or the edge of the world shuts the tile.
var solid := PackedByteArray()
## 1 where no prop may stand (doors, the entry's apron).
var keep := PackedByteArray()
## 1 where a solid prop (not a wall) stands.
var pmask := PackedByteArray()
var objects: Array = []
## The props that may hold loot: {"obj", "kind" (the container kind), "tx", "ty", "tw", "th", "w"}.
var cands: Array = []
var trees: Array = []
var marks: Array = []
## The named places: {"name", "rect": Rect2i, "dead": weight, "indoor": bool}.
var areas: Array = []
var rects: Dictionary = {}
var entry := Vector2i(-1, -1)
var street := Rect2i()
var apron := Rect2i()

var _next_id := 0
var _org := Vector2i.ZERO
var _pre := ""
var _stamps := 0
var templates: Dictionary = {}
## What is true of the place being drawn: "vehicle" (it holds one), "nest", "survivor"; ops may ask for them with "if".
var flags: Dictionary = {}
var danger := 1


func setup(width: int, height: int, seed_value: int, catalogue: Dictionary, terrain_ids: Dictionary, tmpl: Dictionary = {}) -> void:
	W = width
	H = height
	rng.seed = seed_value
	props = catalogue
	tids = terrain_ids
	templates = tmpl
	terrain.resize(W * H)
	solid.resize(W * H)
	keep.resize(W * H)
	pmask.resize(W * H)
	var fill_id := int(tids.get("GRASS", 4))
	for i in W * H:
		terrain[i] = fill_id


# ------------------------------------------------------------------ numbers --

func _n(v) -> int:
	if v is Dictionary:
		var r: Array = v.r
		return rng.randi_range(int(r[0]), int(r[1]))
	return int(v)


func _f(v) -> float:
	if v is Dictionary:
		var r: Array = v.r
		return rng.randf_range(float(r[0]), float(r[1]))
	return float(v)


func _r(spec, inset = null) -> Rect2i:
	var r := Rect2i()
	if spec is String:
		var key: String = _pre + String(spec)
		if not rects.has(key):
			key = String(spec)
		if not rects.has(key):
			push_error("site layout: no rectangle called '%s'" % String(spec))
			return Rect2i()
		r = rects[key]
	else:
		var a: Array = spec
		r = Rect2i(_n(a[0]) + _org.x, _n(a[1]) + _org.y, _n(a[2]), _n(a[3]))
	if inset != null:
		if inset is Array:
			var s: Array = inset
			r = Rect2i(r.position.x + int(s[0]), r.position.y + int(s[1]), r.size.x - int(s[0]) - int(s[2]), r.size.y - int(s[1]) - int(s[3]))
		else:
			var k := int(inset)
			r = Rect2i(r.position.x + k, r.position.y + k, r.size.x - 2 * k, r.size.y - 2 * k)
	return r


func _clip(r: Rect2i) -> Rect2i:
	return r.intersection(Rect2i(0, 0, W, H))


func _pick(list, weights_key: String = "w") -> String:
	## One of a list of names, or of {"k": name, "w": weight}.
	var total := 0.0
	for it in list:
		total += float(it.get(weights_key, 1.0)) if it is Dictionary else 1.0
	var at := rng.randf() * total
	for it in list:
		at -= float(it.get(weights_key, 1.0)) if it is Dictionary else 1.0
		if at < 0.0:
			return String(it.k) if it is Dictionary else String(it)
	var last = list[list.size() - 1]
	return String(last.k) if last is Dictionary else String(last)


func _tid(name: String) -> int:
	if not tids.has(name):
		push_error("site layout: unknown terrain '%s'" % name)
		return int(tids.get("GRASS", 4))
	return int(tids[name])


func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func is_open(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and solid[y * W + x] == 0


func _paint(x: int, y: int, name: String, shut: bool) -> void:
	if not _in(x, y):
		return
	var i := y * W + x
	terrain[i] = _tid(name)
	solid[i] = 1 if shut else 0
	pmask[i] = 0


# ---------------------------------------------------------------------- run --

## Runs a layout: its optional "approach" (the street the squad arrives on), its "border", then its ops.
func run(recipe: Dictionary) -> void:
	if recipe.has("ground"):
		fill(Rect2i(0, 0, W, H), String(recipe.ground))
	if recipe.has("approach"):
		_approach(recipe.approach)
	if recipe.has("border"):
		_border(recipe.border)
	_run_ops(recipe.get("ops", []))


func _run_ops(ops: Array) -> void:
	for op in ops:
		if op.has("if") and not bool(flags.get(String(op["if"]), false)):
			continue
		if op.has("if_not") and bool(flags.get(String(op["if_not"]), false)):
			continue
		if op.has("min_danger") and danger < int(op.min_danger):
			continue
		if op.has("max_danger") and danger > int(op.max_danger):
			continue
		if op.has("p") and rng.randf() >= float(op.p):
			continue
		match String(op.op):
			"fill": _op_fill(op)
			"patch": _op_patch(op)
			"lanes": _op_lanes(op)
			"building": _op_building(op)
			"block": _op_block(op)
			"wall": _op_wall(op)
			"split": _op_split(op)
			"area": _op_area(op)
			"fence": _op_fence(op)
			"keep": _keep_rect(_r(op.rect), true)
			"place": _op_place(op)
			"line": _op_line(op)
			"rows": _op_rows(op)
			"scatter": _op_scatter(op)
			"trees": _op_trees(op)
			"cars": _op_cars(op)
			"decals": _op_decals(op)
			"stamp": _op_stamp(op)
			"group": _run_ops(op.ops)
			_: push_error("site layout: unknown op '%s'" % String(op.op))


# ---------------------------------------------------------------- approach --

## The street along the bottom edge (or a lane), its verge, the entry and the apron the squad and a vehicle use.
func _approach(a: Dictionary) -> void:
	var rows := int(a.get("rows", 7))
	var vrows := int(a.get("verge_rows", 2))
	var road := String(a.get("road", "ASPHALT"))
	var verge := String(a.get("verge", "SIDEWALK"))
	fill(Rect2i(0, H - rows - vrows, W, vrows), verge)
	fill(Rect2i(0, H - rows, W, rows), road)
	street = Rect2i(0, H - rows - vrows, W, rows + vrows)
	rects["street"] = street
	areas.append({"name": "street", "rect": street, "dead": float(a.get("dead", 1.0)), "indoor": false})
	if bool(a.get("lanes", road == "ASPHALT")):
		marks.append({"kind": "lanes", "cx": float(W) / 2.0, "cy": float(H) - float(rows) / 2.0, "w": float(W), "h": float(rows), "dir": "h", "gaps": [], "seed": rng.randi() % 2000000})
	# (the apron is 23 wide: a bus lying along the road beside the entry, the squad standing about it, all on open road)
	var lo := maxi(APRON_HALF + 3, int(a.get("entry_lo", 12)))
	var hi := mini(W - APRON_HALF - 4, int(a.get("entry_hi", W - 13)))
	entry = Vector2i(rng.randi_range(lo, maxi(lo, hi)), H - 3)
	apron = Rect2i(entry.x - APRON_HALF, H - rows, 2 * APRON_HALF + 1, rows)
	_keep_rect(apron, true)
	match String(a.get("ends", "barricade")):
		"barricade":
			_barricade(rows)
		"open":
			pass


## Both ends of the street are shut with concrete barriers and a wreck.
func _barricade(rows: int) -> void:
	for side in 2:
		var x := 0 if side == 0 else W - 1
		for y in range(H - rows, H):
			solid[y * W + x] = 1
		for y0 in [H - rows, H - 5]:
			_decor("blocks_v", x, y0, 0.0, 0.0)
		if props.has("car_v"):
			var cx := 1 if side == 0 else W - 3
			_put("car_v", cx, H - rows + rng.randi_range(0, 1), {"force": true})


## The world's edge: a ring of solid ground with trees and hedges standing on it.
func _border(b: Dictionary) -> void:
	var t := String(b.get("t", "GRASS"))
	var l := int(b.get("l", 2))
	var r := int(b.get("r", 2))
	var u := int(b.get("u", 2))
	var bottom := street.position.y if street.size.y > 0 else H
	for y in range(0, bottom):
		for x in W:
			if x < l or x >= W - r or y < u:
				_paint(x, y, t, true)
	var tree_p := float(b.get("trees", 0.5))
	var shrub_p := float(b.get("shrubs", 0.5))
	var gap := int(b.get("gap", 2))
	var last_x := -99
	for x in range(0, W):
		if rng.randf() < tree_p and x - last_x >= gap and props.has("tree"):
			_add_tree(x, rng.randi_range(0, maxi(0, u - 1)))
			last_x = x
		if shrub_p > 0.0 and rng.randf() < shrub_p:
			_decor("shrub", x, rng.randi_range(0, maxi(0, u - 1)), 0.0, 0.0)
	for side in 2:
		var last_y := -99
		for y in range(u, bottom):
			var x0 := 0 if side == 0 else W - 1
			var xx := x0 + (rng.randi_range(0, maxi(0, l - 1)) if side == 0 else -rng.randi_range(0, maxi(0, r - 1)))
			if rng.randf() < tree_p and y - last_y >= gap:
				_add_tree(xx, y)
				last_y = y
			if shrub_p > 0.0 and rng.randf() < shrub_p:
				_decor("shrub", xx, y, 0.0, 0.0)


# -------------------------------------------------------------------- ground --

func fill(r: Rect2i, name: String, shut: bool = false) -> void:
	var c := _clip(r)
	for y in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			_paint(x, y, name, shut)


func _op_fill(op: Dictionary) -> void:
	var r := _clip(_r(op.rect, op.get("inset")))
	var shut := bool(op.get("solid", false))
	if op.has("mix"):
		var names: Array = []
		for k in op.mix:
			names.append({"k": String(k), "w": float(op.mix[k])})
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_paint(x, y, _pick(names), shut)
	else:
		fill(r, String(op.t), shut)


## Round patches of another ground (dirt in the grass, oil on the concrete).
func _op_patch(op: Dictionary) -> void:
	var r := _clip(_r(op.rect))
	var n := _n(op.get("n", 3))
	var span: Array = op.get("r", [2, 4])
	for k in n:
		var cx := rng.randi_range(r.position.x, r.end.x - 1)
		var cy := rng.randi_range(r.position.y, r.end.y - 1)
		var rad := rng.randf_range(float(span[0]), float(span[1]))
		for y in range(int(cy - rad) - 1, int(cy + rad) + 2):
			for x in range(int(cx - rad) - 1, int(cx + rad) + 2):
				if not r.has_point(Vector2i(x, y)) or not is_open(x, y):
					continue
				var d := Vector2(x - cx, (y - cy) * 1.2).length() + rng.randf() * 0.8
				if d <= rad:
					terrain[y * W + x] = _tid(String(op.t))


func _op_lanes(op: Dictionary) -> void:
	var r := _r(op.rect)
	var horiz := String(op.get("dir", "h")) == "h"
	marks.append({"kind": "lanes", "cx": float(r.position.x) + float(r.size.x) / 2.0, "cy": float(r.position.y) + float(r.size.y) / 2.0, "w": float(r.size.x), "h": float(r.size.y), "dir": "h" if horiz else "v", "gaps": op.get("gaps", []), "seed": rng.randi() % 2000000})


# ----------------------------------------------------------------- structure --

func _wall(x: int, y: int, name: String) -> void:
	_paint(x, y, name, true)


func _gap(x: int, y: int, name: String) -> void:
	_paint(x, y, name, false)


## A building: a ring of wall one tile thick round a floor, with doors. The id names the floor (its inner rectangle).
func _op_building(op: Dictionary) -> void:
	var r := _clip(_r(op.rect))
	var wall := String(op.get("wall", "WALL_BRICK"))
	var floor_name := String(op.get("floor", "LINO"))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			if edge:
				_wall(x, y, wall)
			else:
				_paint(x, y, floor_name, false)
	var inner := r.grow(-1)
	if op.has("id"):
		rects[_pre + String(op.id)] = inner
	for d in op.get("doors", []):
		_door_in_ring(r, d, String(op.get("door_t", "DOOR_WOOD")))
	if String(op.get("name", "")) != "":
		areas.append({"name": String(op.name), "rect": inner, "dead": float(op.get("dead", 1.0)), "indoor": true})


## A door in the ring of a rect: {"side": "N"|"S"|"E"|"W", "at": tiles from the corner, "w": width}.
func _door_in_ring(r: Rect2i, d: Dictionary, name: String) -> void:
	var side := String(d.side)
	var w := _n(d.get("w", 2))
	var span := r.size.x if (side == "N" or side == "S") else r.size.y
	var at: int
	var raw = d.get("at", "mid")
	if raw is String:
		at = floori((span - w) / 2.0)
	else:
		at = _n(raw)
	at = clampi(at, 1, maxi(1, span - 1 - w))
	for k in w:
		var x := 0
		var y := 0
		match side:
			"N": x = r.position.x + at + k; y = r.position.y
			"S": x = r.position.x + at + k; y = r.end.y - 1
			"W": x = r.position.x; y = r.position.y + at + k
			_: x = r.end.x - 1; y = r.position.y + at + k
		_gap(x, y, String(d.get("t", name)))
		for dd in range(-DOOR_KEEP, DOOR_KEEP + 1):
			if side == "N" or side == "S":
				_keep_tile(x, y + dd)
			else:
				_keep_tile(x + dd, y)


## A building the dead and the squad cannot enter: its walls and a roof.
func _op_block(op: Dictionary) -> void:
	var r := _clip(_r(op.rect))
	var wall := String(op.get("wall", "WALL_BRICK"))
	var roof := String(op.get("roof", "ROOF"))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			_paint(x, y, wall if edge else roof, true)


## A straight wall from one tile to another (inclusive) with doors at offsets along it.
func _op_wall(op: Dictionary) -> void:
	var a: Array = op["from"]
	var b: Array = op["to"]
	var x0 := _n(a[0]) + _org.x
	var y0 := _n(a[1]) + _org.y
	var x1 := _n(b[0]) + _org.x
	var y1 := _n(b[1]) + _org.y
	_wall_line(x0, y0, x1, y1, String(op.get("t", "WALL_PLASTER")), op.get("doors", []), String(op.get("door_t", "DOOR_WOOD")))


func _wall_line(x0: int, y0: int, x1: int, y1: int, name: String, doors: Array, door_name: String) -> void:
	var horiz := y0 == y1
	var n := (absi(x1 - x0) if horiz else absi(y1 - y0)) + 1
	var gaps := {}
	for d in doors:
		var w := _n(d.get("w", 2))
		var at := clampi(_n(d.at), 0, maxi(0, n - w))
		for k in w:
			gaps[at + k] = true
	for k in n:
		var x := mini(x0, x1) + k if horiz else x0
		var y := y0 if horiz else mini(y0, y1) + k
		if gaps.has(k):
			_gap(x, y, door_name)
			for dd in range(-DOOR_KEEP, DOOR_KEEP + 1):
				if horiz:
					_keep_tile(x, y + dd)
				else:
					_keep_tile(x + dd, y)
		else:
			_wall(x, y, name)


## Splits a room with a wall: "dir" "h" runs the wall across (north and south parts), "v" down (west and east
## parts); "at" is tiles from the top or left of the room, or a share of it; "into" names the two parts.
func _op_split(op: Dictionary) -> void:
	var r := _r(op.id)
	var horiz := String(op.dir) == "h"
	var span := r.size.y if horiz else r.size.x
	var off := 0
	var raw = op.at
	if raw is float and float(raw) < 1.0 and float(raw) > 0.0:
		off = roundi(float(raw) * float(span))
	else:
		off = _n(raw)
	off = clampi(off, 1, span - 2)
	var name := String(op.get("wall", "WALL_PLASTER"))
	var a: Rect2i
	var b: Rect2i
	if horiz:
		_wall_line(r.position.x, r.position.y + off, r.end.x - 1, r.position.y + off, name, op.get("doors", []), String(op.get("door_t", "DOOR_WOOD")))
		a = Rect2i(r.position.x, r.position.y, r.size.x, off)
		b = Rect2i(r.position.x, r.position.y + off + 1, r.size.x, r.size.y - off - 1)
	else:
		_wall_line(r.position.x + off, r.position.y, r.position.x + off, r.end.y - 1, name, op.get("doors", []), String(op.get("door_t", "DOOR_WOOD")))
		a = Rect2i(r.position.x, r.position.y, off, r.size.y)
		b = Rect2i(r.position.x + off + 1, r.position.y, r.size.x - off - 1, r.size.y)
	var into: Array = op.get("into", [])
	var names: Array = op.get("names", [])
	var floors: Array = op.get("floors", [])
	var parts := [a, b]
	var parent_name := ""
	for k in 2:
		if k < into.size():
			rects[_pre + String(into[k])] = parts[k]
		if k < floors.size() and String(floors[k]) != "":
			fill(parts[k], String(floors[k]))
	# the parent's name goes to the parts when they have their own
	if names.size() > 0:
		for i in range(areas.size() - 1, -1, -1):
			if areas[i].rect == r and bool(areas[i].indoor):
				areas.remove_at(i)
				break
		var dead_w: Array = op.get("dead", [1.0, 1.0])
		for k in 2:
			if k < names.size() and String(names[k]) != "":
				areas.append({"name": String(names[k]), "rect": parts[k], "dead": float(dead_w[k]), "indoor": true})


## A named place (outdoors unless "indoor") for the dead and the containers to be put in.
func _op_area(op: Dictionary) -> void:
	var r := _clip(_r(op.rect, op.get("inset")))
	if op.has("id"):
		rects[_pre + String(op.id)] = r
	if op.has("floor"):
		fill(r, String(op.floor))
	if String(op.get("name", "")) != "":
		areas.append({"name": String(op.name), "rect": r, "dead": float(op.get("dead", 0.6)), "indoor": bool(op.get("indoor", false))})


## A fence round a rectangle: a band of sheet metal (or chain-link on the east and west sides) one tile thick, with gates.
func _op_fence(op: Dictionary) -> void:
	var r := _clip(_r(op.rect))
	var name := String(op.get("t", "WALL_METAL"))
	var sides := String(op.get("sides", "NSEW"))
	var chain := String(op.get("style", "metal")) == "chain"
	var ground := String(op.get("ground", ""))
	var gates: Array = op.get("gates", [])
	var gap_set := {}
	for g in gates:
		var side := String(g.side)
		var w := _n(g.get("w", 3))
		var span := r.size.x if (side == "N" or side == "S") else r.size.y
		var at := clampi(_n(g.get("at", "mid")) if not (g.get("at", "mid") is String) else floori((span - w) / 2.0), 1, maxi(1, span - 1 - w))
		for k in w:
			var x := 0
			var y := 0
			match side:
				"N": x = r.position.x + at + k; y = r.position.y
				"S": x = r.position.x + at + k; y = r.end.y - 1
				"W": x = r.position.x; y = r.position.y + at + k
				_: x = r.end.x - 1; y = r.position.y + at + k
			gap_set[Vector2i(x, y)] = side
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var side := ""
			if y == r.position.y and "N" in sides:
				side = "N"
			elif y == r.end.y - 1 and "S" in sides:
				side = "S"
			elif x == r.position.x and "W" in sides:
				side = "W"
			elif x == r.end.x - 1 and "E" in sides:
				side = "E"
			if side == "":
				continue
			var p := Vector2i(x, y)
			if gap_set.has(p):
				if ground != "":
					_gap(x, y, ground)
				else:
					solid[y * W + x] = 0
				for dd in range(-DOOR_KEEP, DOOR_KEEP + 1):
					if side == "N" or side == "S":
						_keep_tile(x, y + dd)
					else:
						_keep_tile(x + dd, y)
				continue
			if chain and (side == "W" or side == "E"):
				_paint(x, y, ground if ground != "" else String(op.get("under", "YARD")), true)
			else:
				_wall(x, y, name)
	if chain:
		for side in ["W", "E"]:
			if not (side in sides):
				continue
			var x := r.position.x if side == "W" else r.end.x - 1
			var y := r.position.y
			while y < r.end.y:
				var hole := false
				for yy in range(y, mini(y + 5, r.end.y)):
					if gap_set.has(Vector2i(x, yy)):
						hole = true
				if not hole:
					_decor("chain_v", x, y, 0.0, 0.0)
				y += 5


func _keep_rect(r: Rect2i, on: bool) -> void:
	var c := _clip(r)
	for y in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			keep[y * W + x] = 1 if on else 0


func _keep_tile(x: int, y: int) -> void:
	if _in(x, y):
		keep[y * W + x] = 1


# --------------------------------------------------------------------- props --

## Footprint in tiles of a catalogue kind.
func tiles_of(kind: String) -> Vector2i:
	var t: Array = props[kind].tiles
	return Vector2i(int(t[0]), int(t[1]))


## Lays one prop with the top left of its footprint on tile (tx, ty). Returns the object, or null when the tiles are
## taken, kept clear, or the prop would cut the way to something. opts: "force" (ignore the clear tiles), "file",
## "container" (make it a candidate for loot, with the kind given or the catalogue's), "flip".
func _put(kind: String, tx: int, ty: int, opts: Dictionary = {}):
	if not props.has(kind):
		push_error("site layout: no prop called '%s'" % kind)
		return null
	var p: Dictionary = props[kind]
	var fp := tiles_of(kind)
	if tx < 0 or ty < 0 or tx + fp.x > W or ty + fp.y > H:
		return null
	var is_solid := bool(p.get("solid", true))
	var force := bool(opts.get("force", false))
	var loose := bool(p.get("loose", false))
	if not loose:
		for yy in fp.y:
			for xx in fp.x:
				var i := (ty + yy) * W + tx + xx
				if solid[i] != 0:
					return null
				if is_solid and keep[i] != 0 and not force:
					return null
	else:
		var ci := (ty + (fp.y >> 1)) * W + tx + (fp.x >> 1)
		if solid[ci] != 0:
			return null
	if is_solid and not force:
		if _ring_arcs(tx, ty, fp.x, fp.y) >= 2 and not _stays_connected(tx, ty, fp.x, fp.y):
			return null
	var files: Array = p.files
	var file := String(opts.get("file", files[rng.randi() % files.size()]))
	var obj = _add_obj(kind, p, float(tx) + float(fp.x) / 2.0, float(ty) + float(fp.y) / 2.0, fp.x, fp.y, file, is_solid, opts)
	if obj == null:
		return null
	if is_solid:
		for yy in fp.y:
			for xx in fp.x:
				solid[(ty + yy) * W + tx + xx] = 1
				pmask[(ty + yy) * W + tx + xx] = 1
	var cont = opts.get("container", false)
	var ckind := ""
	if cont is String:
		ckind = String(cont)
	elif bool(cont):
		ckind = String(p.get("container", ""))
	if ckind != "":
		var cand := {"obj": obj, "kind": ckind, "tx": tx, "ty": ty, "tw": fp.x, "th": fp.y, "w": float(opts.get("cw", 1.0))}
		if opts.has("only"):
			cand["only"] = opts.only
		elif p.has("only"):
			cand["only"] = p.only
		cands.append(cand)
	return obj


## A picture with no footprint on the walking grid (what lies on a wall, a hedge on solid ground).
func _decor(kind: String, tx: int, ty: int, ox: float, oy: float, opts: Dictionary = {}):
	if not props.has(kind):
		return null
	var p: Dictionary = props[kind]
	var fp := tiles_of(kind)
	var files: Array = p.files
	var file := String(opts.get("file", files[rng.randi() % files.size()]))
	return _add_obj(kind, p, float(tx) + float(fp.x) / 2.0 + ox, float(ty) + float(fp.y) / 2.0 + oy, fp.x, fp.y, file, false, opts)


func _add_obj(kind: String, p: Dictionary, cx: float, cy: float, tw: int, th: int, file: String, is_solid: bool, opts: Dictionary):
	var dir := String(p.get("dir", "objects"))
	var path := "res://assets/%s/%s.png" % [dir, file]
	var tex: Texture2D = GD.tex(path)
	if tex == null:
		push_error("site layout: no picture %s" % path)
		return null
	var pw := float(tex.get_width())
	var ph := float(tex.get_height())
	var ppt := float(p.get("ppt", 96))
	var w := pw / ppt
	var h := ph / ppt
	if p.has("dw"):
		w = float(p.dw)
		h = w * ph / pw
	elif p.has("dh"):
		h = float(p.dh)
		w = h * pw / ph
	var dx := float(p.get("dx", 0.03))
	var dy := float(p.get("dy", 0.08))
	var piece := {"file": path, "x": cx - w / 2.0 + dx, "y": cy - h / 2.0 + dy, "w": w, "h": h}
	if bool(opts.get("flip", false)) or bool(p.get("flip", false)) and rng.randf() < 0.5:
		piece["flip_h"] = true
	var obj := {"id": _next_id, "kind": kind, "layer": int(p.get("layer", 2)), "order": _next_id, "cx": cx, "cy": cy, "w": float(tw), "h": float(th), "a": 0.0, "solid": is_solid, "pieces": [piece]}
	_next_id += 1
	objects.append(obj)
	return obj


func _add_tree(tx: int, ty: int) -> void:
	if not _in(tx, ty):
		return
	var n := rng.randi_range(0, 12)
	trees.append({"x": float(tx) + 0.5, "y": float(ty) + 0.55, "variant": n % 3, "file": "res://assets/trees/tree_%d.png" % n})
	solid[ty * W + tx] = 1
	pmask[ty * W + tx] = 1


## The number of separate runs of open tiles round a footprint: with at most one, putting something there cannot cut anything off.
func _ring_arcs(tx: int, ty: int, tw: int, th: int) -> int:
	var x0 := tx - 1
	var y0 := ty - 1
	var x1 := tx + tw
	var y1 := ty + th
	var open: Array = []
	for x in range(x0, x1 + 1):
		open.append(is_open(x, y0))
	for y in range(y0 + 1, y1 + 1):
		open.append(is_open(x1, y))
	for x in range(x1 - 1, x0 - 1, -1):
		open.append(is_open(x, y1))
	for y in range(y1 - 1, y0, -1):
		open.append(is_open(x0, y))
	var n := open.size()
	var runs := 0
	for i in n:
		if open[i] and not open[(i + 1) % n]:
			runs += 1
	return runs


## The tiles reachable on foot from the entry (a mask).
func flood() -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(W * H)
	if entry.x < 0 or solid[entry.y * W + entry.x] != 0:
		return seen
	var q := PackedInt32Array()
	var start := entry.y * W + entry.x
	q.append(start)
	seen[start] = 1
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % W
		@warning_ignore("integer_division")
		var y := i / W
		if x > 0 and seen[i - 1] == 0 and solid[i - 1] == 0:
			seen[i - 1] = 1
			q.append(i - 1)
		if x < W - 1 and seen[i + 1] == 0 and solid[i + 1] == 0:
			seen[i + 1] = 1
			q.append(i + 1)
		if y > 0 and seen[i - W] == 0 and solid[i - W] == 0:
			seen[i - W] = 1
			q.append(i - W)
		if y < H - 1 and seen[i + W] == 0 and solid[i + W] == 0:
			seen[i + W] = 1
			q.append(i + W)
	return seen


func _count(mask: PackedByteArray) -> int:
	var n := 0
	for v in mask:
		n += v
	return n


## Whether shutting these tiles leaves every other tile that could be reached still reachable.
func _stays_connected(tx: int, ty: int, tw: int, th: int) -> bool:
	var before := flood()
	var nb := _count(before)
	if nb == 0:
		return true
	var lost := 0
	for yy in th:
		for xx in tw:
			var i := (ty + yy) * W + tx + xx
			lost += before[i]
			solid[i] = 1
	var after := flood()
	var na := _count(after)
	for yy in th:
		for xx in tw:
			solid[(ty + yy) * W + tx + xx] = 0
	return na == nb - lost


# ------------------------------------------------------------- furniture ops --

func _chance_container(op: Dictionary) -> bool:
	var c = op.get("container", false)
	if typeof(c) == TYPE_BOOL:
		return c
	if typeof(c) == TYPE_FLOAT or typeof(c) == TYPE_INT:
		return rng.randf() < float(c)
	return false


func _kind_opts(op: Dictionary) -> Dictionary:
	var o := {}
	if _chance_container(op):
		o["container"] = true
		if op.has("ckind"):
			o["container"] = String(op.ckind)
	if op.has("only"):
		o["only"] = op.only
	if op.has("cw"):
		o["cw"] = float(op.cw)
	return o


func _op_place(op: Dictionary) -> void:
	var kind := _pick(op.kinds) if op.has("kinds") else String(op.kind)
	var fp := tiles_of(kind)
	var tx := 0
	var ty := 0
	if op.has("at"):
		var a: Array = op["at"]
		tx = _n(a[0]) + _org.x
		ty = _n(a[1]) + _org.y
	else:
		var r := _r(op["in"], op.get("inset"))
		var anchor := String(op.get("anchor", "C"))
		tx = r.position.x + ((r.size.x - fp.x) >> 1)
		if "W" in anchor:
			tx = r.position.x
		elif "E" in anchor:
			tx = r.end.x - fp.x
		ty = r.position.y + ((r.size.y - fp.y) >> 1)
		if "N" in anchor:
			ty = r.position.y
		elif "S" in anchor:
			ty = r.end.y - fp.y
		tx += _n(op.get("dx", 0))
		ty += _n(op.get("dy", 0))
	var o := _kind_opts(op)
	if op.has("file"):
		o["file"] = String(op.file)
	if bool(op.get("force", false)):
		o["force"] = true
	if bool(op.get("decor", false)):
		_decor(kind, tx, ty, 0.0, 0.0, o)
		return
	if _put(kind, tx, ty, o) != null:
		return
	# not there: a few tiles either way
	var j := int(op.get("jitter", 0))
	if j > 0:
		var offsets: Array = []
		for dy in range(-j, j + 1):
			for dx in range(-j, j + 1):
				if dx != 0 or dy != 0:
					offsets.append(Vector2i(dx, dy))
		# (shuffled with the site's own dice: `Array.shuffle` would use the global ones)
		for i in range(offsets.size() - 1, 0, -1):
			var k := rng.randi_range(0, i)
			var tmp: Vector2i = offsets[i]
			offsets[i] = offsets[k]
			offsets[k] = tmp
		for off in offsets:
			if _put(kind, tx + off.x, ty + off.y, o) != null:
				return


## A row of props along one side of a room (side "N", "S", "W" or "E"): each next to the last, with the gaps given.
func _op_line(op: Dictionary) -> void:
	var r := _r(op.rect, op.get("inset"))
	var side := String(op.get("side", "N"))
	var horiz := side == "N" or side == "S"
	var limit := _n(op.get("n", 99))
	var pos := _n(op.get("start", 0))
	var span := r.size.x if horiz else r.size.y
	var gaps: Array = op.get("gap", [0, 0])
	var skip_p := float(op.get("skip", 0.0))
	var placed := 0
	var guard := 0
	while pos < span and placed < limit and guard < 200:
		guard += 1
		var kind := _pick(op.kinds)
		var fp := tiles_of(kind)
		var along := fp.x if horiz else fp.y
		if pos + along > span:
			var smaller := _smaller_kind(op.kinds, span - pos, horiz)
			if smaller == "":
				break
			kind = smaller
			fp = tiles_of(kind)
			along = fp.x if horiz else fp.y
		var tx := 0
		var ty := 0
		match side:
			"N": tx = r.position.x + pos; ty = r.position.y
			"S": tx = r.position.x + pos; ty = r.end.y - fp.y
			"W": tx = r.position.x; ty = r.position.y + pos
			_: tx = r.end.x - fp.x; ty = r.position.y + pos
		if skip_p > 0.0 and rng.randf() < skip_p:
			pos += along
			continue
		var o := _kind_opts(op)
		var obj = _put(kind, tx, ty, o)
		if obj != null:
			placed += 1
			pos += along + rng.randi_range(int(gaps[0]), int(gaps[1]))
		else:
			pos += 1


func _smaller_kind(kinds: Array, room: int, horiz: bool) -> String:
	var best := ""
	var best_len := 0
	for it in kinds:
		var k := String(it.k) if it is Dictionary else String(it)
		var fp := tiles_of(k)
		var along := fp.x if horiz else fp.y
		if along <= room and along > best_len:
			best = k
			best_len = along
	return best


## Rows of shelving across a room with aisles between them (the pitch counts the shelf's own row).
func _op_rows(op: Dictionary) -> void:
	var r := _r(op.rect, op.get("inset"))
	var pitch := int(op.get("pitch", 3))
	var y0 := _n(op.get("y0", 0))
	var margin := int(op.get("margin", 1))
	var every := int(op.get("gap_every", 0))
	var rows_max := _n(op.get("n", 99))
	var skip_p := float(op.get("skip", 0.0))
	var y := r.position.y + y0
	var row := 0
	while row < rows_max:
		var kind0 := _pick(op.kinds)
		var th: int = tiles_of(kind0).y
		if y + th > r.end.y:
			break
		var x := r.position.x + margin
		var units := 0
		while true:
			var kind := _pick(op.kinds) if units > 0 else kind0
			var fp := tiles_of(kind)
			if x + fp.x > r.end.x - margin:
				break
			if skip_p > 0.0 and rng.randf() < skip_p:
				x += fp.x
				units += 1
				continue
			var o := _kind_opts(op)
			var obj = _put(kind, x, y, o)
			x += fp.x
			units += 1
			if every > 0 and units % every == 0:
				x += 1
		y += pitch
		row += 1


## Props scattered over open floor: "n" of them in the rect, "wall" to keep them against a wall, "apart" tiles clear of other props.
func _op_scatter(op: Dictionary) -> void:
	var r := _clip(_r(op.rect, op.get("inset")))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var n := _n(op.get("n", 3))
	var apart := int(op.get("apart", 0))
	var against := bool(op.get("wall", false))
	var placed := 0
	var tries := n * 40
	var onlist: Array = op.get("on", [])
	while placed < n and tries > 0:
		tries -= 1
		var kind := _pick(op.kinds)
		var fp := tiles_of(kind)
		if r.size.x < fp.x or r.size.y < fp.y:
			continue
		var tx := rng.randi_range(r.position.x, r.end.x - fp.x)
		var ty := rng.randi_range(r.position.y, r.end.y - fp.y)
		if against and not _touches_wall(tx, ty, fp.x, fp.y):
			continue
		if apart > 0 and _props_near(tx, ty, fp.x, fp.y, apart):
			continue
		if onlist.size() > 0:
			var tname: String = String(tids_by_id().get(terrain[ty * W + tx], ""))
			if not (tname in onlist):
				continue
		var o := _kind_opts(op)
		if _put(kind, tx, ty, o) != null:
			placed += 1


var _names_by_id := {}


func tids_by_id() -> Dictionary:
	if _names_by_id.is_empty():
		for k in tids:
			_names_by_id[int(tids[k])] = String(k)
	return _names_by_id


## Whether a footprint has a wall (or the world's edge) on one of its four sides.
func _touches_wall(tx: int, ty: int, tw: int, th: int) -> bool:
	for x in tw:
		if _wall_at(tx + x, ty - 1) or _wall_at(tx + x, ty + th):
			return true
	for y in th:
		if _wall_at(tx - 1, ty + y) or _wall_at(tx + tw, ty + y):
			return true
	return false


func _wall_at(x: int, y: int) -> bool:
	return not _in(x, y) or (solid[y * W + x] != 0 and pmask[y * W + x] == 0)


func _props_near(tx: int, ty: int, tw: int, th: int, d: int) -> bool:
	for y in range(ty - d, ty + th + d):
		for x in range(tx - d, tx + tw + d):
			if _in(x, y) and pmask[y * W + x] != 0:
				return true
	return false


func _op_trees(op: Dictionary) -> void:
	var r := _clip(_r(op.rect, op.get("inset")))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var n := _n(op.get("n", 4))
	var gap := int(op.get("gap", 3))
	var onlist: Array = op.get("on", [])
	var tries := n * 40
	var placed := 0
	while placed < n and tries > 0:
		tries -= 1
		var tx := rng.randi_range(r.position.x, r.end.x - 1)
		var ty := rng.randi_range(r.position.y, r.end.y - 1)
		if solid[ty * W + tx] != 0 or keep[ty * W + tx] != 0:
			continue
		if onlist.size() > 0 and not (String(tids_by_id().get(terrain[ty * W + tx], "")) in onlist):
			continue
		if _props_near(tx, ty, 1, 1, gap - 1):
			continue
		if _ring_arcs(tx, ty, 1, 1) >= 2 and not _stays_connected(tx, ty, 1, 1):
			continue
		_add_tree(tx, ty)
		placed += 1


## Parked or wrecked cars on the open ground, lying either way, some of them with a boot to search.
func _op_cars(op: Dictionary) -> void:
	var r := _clip(_r(op.rect, op.get("inset")))
	var n := _n(op.get("n", 2))
	var kinds: Array = op.get("kinds", ["car_h", "car_v"])
	var placed := 0
	var tries := n * 40
	while placed < n and tries > 0:
		tries -= 1
		var kind := _pick(kinds)
		var fp := tiles_of(kind)
		if r.size.x < fp.x or r.size.y < fp.y:
			continue
		var tx := rng.randi_range(r.position.x, r.end.x - fp.x)
		var ty := rng.randi_range(r.position.y, r.end.y - fp.y)
		if _props_near(tx, ty, fp.x, fp.y, 1):
			continue
		var o := _kind_opts(op)
		if _put(kind, tx, ty, o) != null:
			placed += 1


## Marks on the floor (blood, paper, stains, cracks): flat pictures that shut nothing.
func _op_decals(op: Dictionary) -> void:
	var r := _clip(_r(op.rect, op.get("inset")))
	var n := _n(op.get("n", 4))
	var kinds: Array = op.get("kinds", [op.get("kind", "blood")])
	for k in n:
		var kind := _pick(kinds)
		var tx := rng.randi_range(r.position.x, r.end.x - 1)
		var ty := rng.randi_range(r.position.y, r.end.y - 1)
		if solid[ty * W + tx] != 0:
			continue
		var p: Dictionary = props[kind]
		var files: Array = p.files
		var file := String(files[rng.randi() % files.size()])
		var obj = _add_obj(kind, p, float(tx) + rng.randf_range(0.2, 0.8), float(ty) + rng.randf_range(0.2, 0.8), 1, 1, file, false, {})
		if obj != null and rng.randf() < 0.5:
			obj.pieces[0]["flip_h"] = true


## Stamps a template (a small layout in the layouts' "templates", its coordinates from its own corner) at a place.
func _op_stamp(op: Dictionary) -> void:
	var name := _pick(op.templates) if op.has("templates") else String(op.template)
	if not templates.has(name):
		push_error("site layout: no template called '%s'" % name)
		return
	var t: Dictionary = templates[name]
	var at: Array = op["at"]
	var saved_org := _org
	var saved_pre := _pre
	_stamps += 1
	_org = Vector2i(_n(at[0]) + saved_org.x, _n(at[1]) + saved_org.y)
	_pre = "%s#%d/" % [saved_pre, _stamps]
	# what the stamp names for the outside to use
	_run_ops(t.get("ops", []))
	if op.has("id"):
		var size: Array = t.get("size", [0, 0])
		rects[saved_pre + String(op.id)] = Rect2i(_org.x, _org.y, int(size[0]), int(size[1]))
	_org = saved_org
	_pre = saved_pre


# -------------------------------------------------------------------- mirror --

## Turns the whole canvas over left to right (the pictures stay as they are).
func mirror() -> void:
	var nt := PackedInt32Array()
	var ns := PackedByteArray()
	var nk := PackedByteArray()
	var nm := PackedByteArray()
	nt.resize(W * H)
	ns.resize(W * H)
	nk.resize(W * H)
	nm.resize(W * H)
	for y in H:
		for x in W:
			var j := y * W + (W - 1 - x)
			nt[j] = terrain[y * W + x]
			ns[j] = solid[y * W + x]
			nk[j] = keep[y * W + x]
			nm[j] = pmask[y * W + x]
	terrain = nt
	solid = ns
	keep = nk
	pmask = nm
	for o in objects:
		o.cx = float(W) - float(o.cx)
		for pc in o.pieces:
			pc.x = float(W) - (float(pc.x) + float(pc.w))
	for t in trees:
		t.x = float(W) - float(t.x)
	for m in marks:
		m.cx = float(W) - float(m.cx)
		if String(m.dir) == "h":
			var g: Array = []
			for pair in m.gaps:
				g.append([float(W) - float(pair[1]), float(W) - float(pair[0])])
			m.gaps = g
	for a in areas:
		var r: Rect2i = a.rect
		a.rect = Rect2i(W - r.end.x, r.position.y, r.size.x, r.size.y)
	for c in cands:
		c.tx = W - int(c.tx) - int(c.tw)
	entry = Vector2i(W - 1 - entry.x, entry.y)
	apron = Rect2i(W - apron.end.x, apron.position.y, apron.size.x, apron.size.y)
	street = Rect2i(W - street.end.x, street.position.y, street.size.x, street.size.y)
	for k in rects:
		var rr: Rect2i = rects[k]
		rects[k] = Rect2i(W - rr.end.x, rr.position.y, rr.size.x, rr.size.y)


## The name of the room or place that holds a tile ("" for open ground that has none).
func area_at(x: int, y: int) -> String:
	var p := Vector2i(x, y)
	for i in range(areas.size() - 1, -1, -1):
		if areas[i].rect.has_point(p):
			return String(areas[i].name)
	return ""
