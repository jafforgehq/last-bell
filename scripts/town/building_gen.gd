## The buildings of the town (One House, TOWNGEN): from a lot (a rectangle, the side its front is on, the kind of building) to a small SiteCanvas (scripts/raid/site_canvas.gd) holding
## the ground, the walls, the doors, the rooms and their furniture, the yard and what stands in it. TownGen (scripts/town/town_gen.gd) stamps the canvas into the town.
##
## FOOTPRINTS. A building is a set of PARTS: rectangles of outer walls that touch along a one tile wall they share (an L is two parts, a T two, a U three, a bungalow with its garage
## two, a church three: tower, nave, chancel; scripts/town/building_plans.gd draws them, the front at the top, and `build` turns a plan over for a lot whose front is south).
## Each part is partitioned into ROOMS (rectangles) by a BSP that follows a program of room names with shares of the floor (the entry room, the one the front door opens into,
## always touches the front wall of its part). Doors are cut in the partition walls where both sides are floor, between touching parts, and in the outer walls (a front door into the
## entry room, a back door); a repair pass opens a door to any room that cannot be reached. Then the rooms are furnished with the site canvas's ops and the yard is dressed (a path,
## a driveway, a car, lawn or garden or bare earth, trees, shrubs, a fence).
extends RefCounted

const Canvas := preload("res://scripts/raid/site_canvas.gd")
const Plans := preload("res://scripts/town/building_plans.gd")

const WALL_IN := "WALL_PLASTER"
const DOOR_T := "DOOR_WOOD"
## The tiles each side of a doorway that no furniture may stand on (one: the rooms are small).
const DOOR_KEEP := 1
## The kinds that are a yard and no building.
const YARD_KINDS := ["pocket", "park", "plaza", "field", "woods", "meadow"]
## Which stocks a room or a kind of building holds (multipliers on 1.0 for each of food, water, scrap, ammo, meds).
const LOOT_ROOM := {
	"kitchen": {"food": 3.0, "water": 2.0, "scrap": 0.3}, "pantry": {"food": 4.0, "water": 3.0}, "bedroom": {"scrap": 1.2, "meds": 1.2, "ammo": 0.6, "food": 0.3},
	"bathroom": {"meds": 3.5, "water": 1.0, "food": 0.2}, "living room": {"scrap": 1.0, "ammo": 0.5, "food": 0.5}, "front room": {"scrap": 1.0, "food": 0.6},
	"storeroom": {"food": 1.5, "water": 1.5, "scrap": 1.5}, "workshop": {"scrap": 3.0, "ammo": 0.5, "food": 0.1}, "armoury": {"ammo": 6.0, "scrap": 0.5},
	"cell": {"scrap": 1.0, "food": 0.5}, "front desk": {"ammo": 1.5, "scrap": 0.5}, "ward": {"meds": 2.5, "water": 1.0}, "pharmacy": {"meds": 6.0},
	"waiting room": {"meds": 0.8, "food": 0.5, "water": 0.5}, "vault": {"ammo": 2.0, "scrap": 3.0, "meds": 0.5}, "hall": {"scrap": 1.0, "food": 0.5, "water": 0.5},
	"engine bay": {"scrap": 2.0, "water": 1.5, "ammo": 0.3}, "dormitory": {"scrap": 1.0, "food": 0.6, "meds": 0.5}, "barn": {"food": 2.0, "scrap": 1.5, "water": 1.0},
	"classroom": {"scrap": 1.0, "food": 0.5}, "gym": {"water": 1.0, "scrap": 1.0}, "nave": {"food": 0.5}, "chancel": {"food": 1.0, "meds": 0.6}, "stacks": {"scrap": 0.6, "food": 0.2},
	"dining hall": {"food": 3.0, "water": 2.0}, "flat": {"food": 1.2, "water": 1.0, "scrap": 0.8, "meds": 0.8, "ammo": 0.4},
}
const LOOT_KIND := {
	"pharmacy": {"meds": 4.0, "food": 0.3}, "bakery": {"food": 4.0, "water": 1.5}, "hardware": {"scrap": 3.0, "ammo": 1.2}, "supermarket": {"food": 3.0, "water": 3.0},
	"shop": {"food": 1.5, "water": 1.2, "scrap": 0.8}, "cornershop": {"food": 1.8, "water": 1.4, "scrap": 0.6}, "diner": {"food": 2.0, "water": 1.5}, "warehouse": {"scrap": 2.0, "food": 1.5, "water": 1.5, "ammo": 0.4},
	"garage": {"scrap": 2.5}, "police": {"ammo": 2.0}, "clinic": {"meds": 2.0}, "fire_station": {"water": 1.5, "scrap": 1.2}, "bank": {"scrap": 1.2, "ammo": 1.0},
}

var props: Dictionary = {}
var tids: Dictionary = {}


func setup(prop_catalogue: Dictionary, terrain_ids: Dictionary) -> void:
	props = prop_catalogue
	tids = terrain_ids


## The weights of the five stocks for a container in a room of a building: {stock: weight}.
static func loot_weights(room_name: String, kind: String) -> Dictionary:
	var out := {"food": 1.0, "water": 1.0, "scrap": 1.0, "ammo": 1.0, "meds": 1.0}
	var a: Dictionary = LOOT_ROOM.get(room_name, {})
	var b: Dictionary = LOOT_KIND.get(kind, {})
	for k in out:
		out[k] = float(out[k]) * float(a.get(k, 1.0)) * float(b.get(k, 1.0))
	return out


# ============================================================== the partitioning ==

## Splits a floor rectangle into the rooms of `items`. Appends {"name", "rect", "floor", "entry"} to `rooms` and {"horiz": the wall runs along x, "pos": its row or column, "from",
## "to": the cells it spans} to `walls`. `front` is the side of the part the street is on ("N" or "S").
static func _partition(r: Rect2i, items: Array, front: String, rooms: Array, walls: Array, rng: RandomNumberGenerator) -> void:
	if items.is_empty():
		return
	var w := r.size.x
	var h := r.size.y
	var can_rows := h >= 5
	var can_cols := w >= 5
	if items.size() == 1 or (not can_rows and not can_cols):
		var pick: Dictionary = items[0]
		for o in items:
			if bool(o.entry):
				pick = o
				break
			if float(o.share) > float(pick.share) and not bool(pick.entry):
				pick = o
		rooms.append({"name": pick.name, "rect": r, "floor": pick.floor, "entry": bool(pick.entry)})
		return
	var cut_rows := can_rows
	if can_rows and can_cols:
		if float(h) >= float(w) * 1.1:
			cut_rows = true
		elif absf(float(w) - float(h)) < 0.9:
			cut_rows = rng.randf() < 0.5
		else:
			cut_rows = false
	var sorted: Array = items.duplicate()
	sorted.sort_custom(func(a, b):
		var ka: float = (-10.0 if bool(a.entry) else 0.0) + float(a.pref)
		var kb: float = (-10.0 if bool(b.entry) else 0.0) + float(b.pref)
		return ka < kb)
	if cut_rows:
		if front == "S":
			sorted.reverse()
	elif rng.randf() < 0.5:
		sorted.reverse()
	var total := 0.0
	for o in sorted:
		total += float(o.share)
	var acc := 0.0
	var k := 1
	var best_d := 1.0e9
	for i in range(1, sorted.size()):
		acc += float(sorted[i - 1].share)
		var dd := absf(acc - total * 0.5)
		if dd < best_d:
			best_d = dd
			k = i
	var ga: Array = sorted.slice(0, k)
	var gb: Array = sorted.slice(k)
	var share_a := 0.0
	for o in ga:
		share_a += float(o.share)
	if cut_rows:
		var ha := clampi(roundi(float(h - 1) * share_a / total), 2, h - 3)
		_partition(Rect2i(r.position.x, r.position.y, w, ha), ga, front, rooms, walls, rng)
		_partition(Rect2i(r.position.x, r.position.y + ha + 1, w, h - ha - 1), gb, front, rooms, walls, rng)
		walls.append({"horiz": true, "pos": r.position.y + ha, "from": r.position.x, "to": r.end.x - 1})
	else:
		var wa := clampi(roundi(float(w - 1) * share_a / total), 2, w - 3)
		_partition(Rect2i(r.position.x, r.position.y, wa, h), ga, front, rooms, walls, rng)
		_partition(Rect2i(r.position.x + wa + 1, r.position.y, w - wa - 1, h), gb, front, rooms, walls, rng)
		walls.append({"horiz": false, "pos": r.position.x + wa, "from": r.position.y, "to": r.end.y - 1})


## A corridor with rooms along it (flats, classrooms): `double` rooms on both sides of a two wide corridor with a lobby on the front side, else the corridor along the front wall and
## the rooms behind it. A wall entry with "door": false only divides; one with "paint": false is a doorway to be cut in a wall that is already there (a door for each room).
static func _corridor(r: Rect2i, front: String, double: bool, room_name: String, room_floor: String, rooms: Array, walls: Array, rng: RandomNumberGenerator) -> void:
	var w := r.size.x
	var h := r.size.y
	if double and h >= 9:
		var hn := (h - 4) / 2
		var hs := h - 4 - hn
		var cor_y := r.position.y + hn + 1
		rooms.append({"name": "hall", "rect": Rect2i(r.position.x, cor_y, w, 2), "floor": "TERRAZZO", "entry": false})
		var wall_n := r.position.y + hn
		var wall_s := cor_y + 2
		walls.append({"horiz": true, "pos": wall_n, "from": r.position.x, "to": r.end.x - 1, "door": false})
		walls.append({"horiz": true, "pos": wall_s, "from": r.position.x, "to": r.end.x - 1, "door": false})
		for side in 2:
			var ry := r.position.y if side == 0 else wall_s + 1
			var rh := hn if side == 0 else hs
			var is_front := (side == 0 and front == "N") or (side == 1 and front == "S")
			var n := maxi(2, (w + 1) / 5)
			var widths := _widths(w, n)
			var lobby_at := rng.randi_range(0, n - 1) if is_front else -1
			var x := r.position.x
			for i in n:
				var rw: int = widths[i]
				var rr := Rect2i(x, ry, rw, rh)
				if i == lobby_at:
					rooms.append({"name": "lobby", "rect": rr, "floor": "TERRAZZO", "entry": true})
				else:
					rooms.append({"name": room_name, "rect": rr, "floor": room_floor, "entry": false})
				walls.append({"horiz": true, "pos": wall_n if side == 0 else wall_s, "from": rr.position.x, "to": rr.end.x - 1, "paint": false})
				if i < n - 1:
					walls.append({"horiz": false, "pos": x + rw, "from": ry, "to": ry + rh - 1, "door": false})
				x += rw + 1
		return
	var cy0 := r.position.y if front == "N" else r.end.y - 2
	rooms.append({"name": "hall", "rect": Rect2i(r.position.x, cy0, w, 2), "floor": "TERRAZZO", "entry": true})
	var wall_y := r.position.y + 2 if front == "N" else r.end.y - 3
	walls.append({"horiz": true, "pos": wall_y, "from": r.position.x, "to": r.end.x - 1, "door": false})
	var ry2 := r.position.y + 3 if front == "N" else r.position.y
	var rh2 := h - 3
	var n2 := maxi(1, (w + 1) / 5)
	var widths2 := _widths(w, n2)
	var x2 := r.position.x
	for i in n2:
		var rw2: int = widths2[i]
		var rr2 := Rect2i(x2, ry2, rw2, rh2)
		rooms.append({"name": room_name, "rect": rr2, "floor": room_floor, "entry": false})
		walls.append({"horiz": true, "pos": wall_y, "from": rr2.position.x, "to": rr2.end.x - 1, "paint": false})
		if i < n2 - 1:
			walls.append({"horiz": false, "pos": x2 + rw2, "from": ry2, "to": ry2 + rh2 - 1, "door": false})
		x2 += rw2 + 1


## `n` widths that add up to w - (n - 1) (the walls between them take the rest).
static func _widths(w: int, n: int) -> Array:
	var total := w - (n - 1)
	var base := total / n
	var out: Array = []
	for i in n:
		out.append(base)
	out[n - 1] = total - base * (n - 1)
	return out


# ================================================================== the building ==

## The footprint of a plan's parts on the lot: the plan is canonical (front north), a south front turns it over; the box's top left is at (bx, by) of the lot.
static func place_parts(plan_parts: Array, box: Vector2i, front: String, bx: int, by: int) -> Array:
	var out: Array = []
	for p in plan_parts:
		var r: Rect2i = p
		var y := r.position.y
		if front == "S":
			y = box.y - r.position.y - r.size.y
		out.append(Rect2i(bx + r.position.x, by + y, r.size.x, r.size.y))
	return out


func _door_cell(cv, x: int, y: int, horiz_wall: bool) -> void:
	cv._gap(x, y, DOOR_T)
	for dd in range(-DOOR_KEEP, DOOR_KEEP + 1):
		if horiz_wall:
			cv._keep_tile(x, y + dd)
		else:
			cv._keep_tile(x + dd, y)


## Everything of one lot. `spec`: {"kind", "district", "rect" (the lot, in the town), "front", "plan", "seed", "start", "wall" (terrain name), "fenced", "yard" (a yard type), "ruin",
## "barricade", "shed"}. Returns {"cv": the canvas, "buildings": [{"kind", "parts": [Rect2i] (in the town), "box": Rect2i, "door": the tile outside the front door, "front_door": [tiles],
## "landmark": "", "state": "intact"|"ruined", "drive": Rect2i (town) or empty}] (the main building first, then a shed), "reach": the flood from the entry}. The rooms of the canvas's
## `areas` say which building they are in ("b"). A lot with no building has none.
func build(spec: Dictionary) -> Dictionary:
	var lot: Rect2i = spec.rect
	var cv := Canvas.new()
	cv.setup(lot.size.x, lot.size.y, int(spec.seed), props, tids, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed) * 31 + 7
	var out := {"cv": cv, "buildings": [], "state": "intact", "drive": Rect2i(), "reach": PackedByteArray()}
	if String(spec.kind) in YARD_KINDS:
		_yard_lot(cv, rng, spec, out)
		out.reach = cv.flood()
		return out
	_building_lot(cv, rng, spec, out)
	out.reach = cv.flood()
	return out


func _building_lot(cv, rng: RandomNumberGenerator, spec: Dictionary, out: Dictionary) -> void:
	var lot: Rect2i = spec.rect
	var lw := lot.size.x
	var lh := lot.size.y
	var kind := String(spec.kind)
	var front := String(spec.front)
	var plan: Dictionary = spec.plan
	var box: Vector2i = plan.box
	var fy := int(plan.fy)
	var margin := lw - box.x
	var start := bool(spec.get("start", false))
	var fenced := bool(spec.get("fenced", false)) and margin >= 2 and not start
	var bx := 0
	var by := fy if front == "N" else lh - fy - box.y
	var attached := kind in ["terrace", "terrace_ext", "rowshop", "kiosk", "cornershop", "shop", "pharmacy", "bakery", "hardware", "diner", "bank", "office", "apartments"]
	if start:
		bx = 2
		by = (lh - box.y) / 2
	elif attached:
		bx = 0 if margin < 4 else rng.randi_range(0, margin)
	elif kind == "scrapyard" or kind == "containers":
		bx = rng.randi_range(1, 3)
		by = 1 if front == "N" else lh - 1 - box.y
	else:
		bx = rng.randi_range(maxi(0, margin / 2 - 1), mini(margin, (margin + 1) / 2 + 1))
	if fenced:
		bx = clampi(bx, 1, maxi(1, margin - 1))
		by = clampi(by, 1, maxi(1, lh - box.y - 1))
	bx = clampi(bx, 0, maxi(0, lw - box.x))
	by = clampi(by, 0, maxi(0, lh - box.y))
	var parts := place_parts(plan.parts, box, front, bx, by)
	var wall_name := String(spec.wall)
	if not tids.has(wall_name):
		wall_name = "WALL_BRICK"
	var programs: Array = Plans.programs(kind, rng)
	var ruin_part := -1
	if bool(spec.get("ruin", false)) and parts.size() >= 2:
		ruin_part = parts.size() - 1
		out.state = "ruined"
	_ground_base(cv, rng, spec, by, box)
	# walls, floors, rooms
	var rooms: Array = []
	var walls: Array = []
	for i in parts.size():
		if i == ruin_part:
			continue
		var pr: Rect2i = parts[i]
		var prog: Array = programs[i] if i < programs.size() else []
		var first_floor := String(prog[0].floor) if not prog.is_empty() else "WOOD"
		for y in range(pr.position.y, pr.end.y):
			for x in range(pr.position.x, pr.end.x):
				if x == pr.position.x or y == pr.position.y or x == pr.end.x - 1 or y == pr.end.y - 1:
					cv._wall(x, y, wall_name)
				else:
					cv._paint(x, y, first_floor, false)
		var inner := pr.grow(-1)
		var rs: Array = []
		if kind == "apartments" or (kind == "school" and i == 0):
			_corridor(inner, front, kind == "apartments", "flat" if kind == "apartments" else "classroom", "WOOD" if kind == "apartments" else "LINO", rs, walls, rng)
		else:
			var n_rooms := clampi(inner.size.x * inner.size.y / 7, 1, maxi(1, prog.size()))
			if start:
				n_rooms = prog.size()
			var use: Array = prog.slice(0, n_rooms)
			if use.is_empty():
				use = [Plans.it("room", 1.0, "WOOD", "ef")]
			_partition(inner, use, front, rs, walls, rng)
		for rm in rs:
			rooms.append(rm)
			cv.fill(rm.rect, String(rm.floor))
	for w3 in walls:
		if not bool(w3.get("paint", true)):
			continue
		for t in range(int(w3.from), int(w3.to) + 1):
			var x := int(w3.pos) if not bool(w3.horiz) else t
			var y := t if not bool(w3.horiz) else int(w3.pos)
			cv._wall(x, y, WALL_IN)
	var room_at := PackedInt32Array()
	room_at.resize(lw * lh)
	room_at.fill(-1)
	for i in rooms.size():
		var rr: Rect2i = rooms[i].rect
		cv.rects["r%d" % i] = rr
		cv.areas.append({"name": String(rooms[i].name), "rect": rr, "dead": 1.0, "indoor": true, "b": 0})
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				room_at[y * lw + x] = i
	# doors: inside each part, between the parts, and the outer ones
	for w5 in walls:
		if bool(w5.get("door", true)):
			_door_in_wall(cv, w5, rng)
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			if i != ruin_part and j != ruin_part:
				_door_between(cv, parts[i], parts[j], rng)
	var doors := _outer_doors(cv, parts, rooms, room_at, front, kind, rng, start)
	var front_pair: Array = doors.front
	var fd: Vector2i = front_pair[0] if not front_pair.is_empty() else Vector2i(lw / 2, by)
	var out_dir := Vector2i(0, -1) if front == "N" else Vector2i(0, 1)
	cv.entry = fd + out_dir
	var fdt: Array = []
	for t in front_pair:
		fdt.append(Vector2i(t.x + lot.position.x, t.y + lot.position.y))
	_repair(cv, rooms, room_at)
	if ruin_part >= 0:
		_rubble(cv, parts, ruin_part, rng)
	_dress_ground(cv, rng, spec, out, parts, front_pair, doors, front, fenced)
	var ops: Array = []
	for i in rooms.size():
		ops.append_array(_ops_for(String(rooms[i].name), "r%d" % i, rooms[i].rect, front, kind, rng))
	cv.run({"ops": ops})
	if bool(spec.get("burnt", false)):
		# a burnt house: soot and cracks over every room
		var burn: Array = []
		for rm in rooms:
			var br: Rect2i = rm.rect
			burn.append({"op": "decals", "rect": [br.position.x, br.position.y, br.size.x, br.size.y], "kinds": ["scorch", "scorch", "crack"], "n": {"r": [3, 6]}})
		cv.run({"ops": burn})
		out.state = "burnt"
	var x0 := 99999
	var y0 := 99999
	var x1 := -1
	var y1 := -1
	var town_parts: Array = []
	for i in parts.size():
		if i == ruin_part:
			continue
		var pr: Rect2i = parts[i]
		town_parts.append(Rect2i(pr.position.x + lot.position.x, pr.position.y + lot.position.y, pr.size.x, pr.size.y))
		x0 = mini(x0, pr.position.x)
		y0 = mini(y0, pr.position.y)
		x1 = maxi(x1, pr.end.x)
		y1 = maxi(y1, pr.end.y)
	out.buildings.append({"kind": kind, "parts": town_parts, "box": Rect2i(x0 + lot.position.x, y0 + lot.position.y, x1 - x0, y1 - y0),
		"door": Vector2i(cv.entry.x + lot.position.x, cv.entry.y + lot.position.y), "front_door": fdt, "landmark": String(plan.get("landmark", "")), "state": String(out.state), "drive": Rect2i()})
	if bool(spec.get("shed", false)) and not start:
		_add_shed(cv, rng, spec, out, Rect2i(x0, y0, x1 - x0, y1 - y0), front)
	_dress_yard(cv, rng, spec, out, parts, front_pair, front, fenced)
	out.buildings[0].drive = out.drive


## The ground under and round a building by district: paving in the town, concrete at the works, the earth of the yard.
func _ground_base(cv, rng: RandomNumberGenerator, spec: Dictionary, by: int, box: Vector2i) -> void:
	var lw: int = cv.W
	var lh: int = cv.H
	var all := Rect2i(0, 0, lw, lh)
	var district := String(spec.district)
	var kind := String(spec.kind)
	var front := String(spec.front)
	var fy := by if front == "N" else lh - by - box.y
	var front_strip := Rect2i(0, 0, lw, fy) if front == "N" else Rect2i(0, lh - fy, lw, fy)
	match district:
		"industrial":
			cv.fill(all, "DIRT" if kind == "scrapyard" else "CONCRETE")
		"main":
			cv.fill(all, "CONCRETE")
			cv.fill(front_strip, "SIDEWALK")
		"oldtown":
			cv.fill(front_strip, "SIDEWALK")
		"civic":
			cv.fill(front_strip, "SIDEWALK")
		"suburb", "edge":
			var yard := String(spec.get("yard", "lawn"))
			match yard:
				"bare":
					cv.run({"ops": [{"op": "patch", "rect": [0, 0, lw, lh], "t": "DIRT", "n": 4, "r": [2, 3.5]}]})
				"garden":
					var gy := (by + box.y + 1) if front == "N" else 1
					var gh := lh - gy - 1 if front == "N" else by - 2
					if gh >= 2 and lw >= 5:
						cv.fill(Rect2i(1, gy, mini(6, lw - 2), mini(3, gh)), "SOIL")
				"overgrown":
					cv.run({"ops": [{"op": "patch", "rect": [0, 0, lw, lh], "t": "SOIL", "n": 2, "r": [1.5, 2.5]}]})
	if kind == "supermarket":
		cv.fill(front_strip, "CONCRETE")


## Cuts a door in a wall of partitions (or a doorway to a corridor): where both sides are floor.
func _door_in_wall(cv, w: Dictionary, rng: RandomNumberGenerator) -> void:
	var horiz := bool(w.horiz)
	var cands: Array = []
	for t in range(int(w.from), int(w.to) + 1):
		var x := int(w.pos) if not horiz else t
		var y := t if not horiz else int(w.pos)
		var a := Vector2i(x, y - 1) if horiz else Vector2i(x - 1, y)
		var b := Vector2i(x, y + 1) if horiz else Vector2i(x + 1, y)
		if cv.is_open(a.x, a.y) and cv.is_open(b.x, b.y) and not cv.is_open(x, y):
			cands.append(t)
	if cands.is_empty():
		return
	var pair: Array = []
	for i in cands.size() - 1:
		if int(cands[i + 1]) == int(cands[i]) + 1:
			pair.append(i)
	if not pair.is_empty() and rng.randf() < 0.7 and int(w.to) - int(w.from) >= 3:
		var i2: int = pair[rng.randi() % pair.size()]
		_cut(cv, horiz, int(w.pos), int(cands[i2]), 2)
		return
	_cut(cv, horiz, int(w.pos), int(cands[rng.randi() % cands.size()]), 1)


func _cut(cv, horiz: bool, pos: int, t0: int, width: int) -> void:
	for k in width:
		var t := t0 + k
		_door_cell(cv, pos if not horiz else t, t if not horiz else pos, horiz)


## A door between two parts that share a wall.
func _door_between(cv, a: Rect2i, b: Rect2i, rng: RandomNumberGenerator) -> void:
	var inter := a.intersection(b)
	if inter.size.x <= 0 or inter.size.y <= 0:
		return
	var horiz := inter.size.y == 1
	if not horiz and inter.size.x != 1:
		return
	var cands: Array = []
	for t in (range(inter.position.x, inter.end.x) if horiz else range(inter.position.y, inter.end.y)):
		var x: int = t if horiz else inter.position.x
		var y: int = inter.position.y if horiz else t
		var p := Vector2i(x, y - 1) if horiz else Vector2i(x - 1, y)
		var q := Vector2i(x, y + 1) if horiz else Vector2i(x + 1, y)
		if cv.is_open(p.x, p.y) and cv.is_open(q.x, q.y):
			cands.append(t)
	if cands.is_empty():
		return
	var pair: Array = []
	for i in cands.size() - 1:
		if int(cands[i + 1]) == int(cands[i]) + 1:
			pair.append(i)
	var pos := inter.position.y if horiz else inter.position.x
	if not pair.is_empty() and rng.randf() < 0.8:
		_cut(cv, horiz, pos, int(cands[pair[rng.randi() % pair.size()]]), 2)
	else:
		_cut(cv, horiz, pos, int(cands[rng.randi() % cands.size()]), 1)


func _in_parts_except(parts: Array, p: Vector2i, skip: int) -> bool:
	for i in parts.size():
		if i != skip and Rect2i(parts[i]).has_point(p):
			return true
	return false


## The pairs of wall cells of the outer walls where a two wide door may go: {"tiles": [a, b], "dir": outward, "room": index}.
func _outer_candidates(cv, parts: Array, room_at: PackedInt32Array) -> Array:
	var out: Array = []
	var lw: int = cv.W
	for pi in parts.size():
		var pr: Rect2i = parts[pi]
		for side in 4:
			var dir := Vector2i(0, -1)
			var cells: Array = []
			match side:
				0:
					for x in range(pr.position.x + 1, pr.end.x - 1):
						cells.append(Vector2i(x, pr.position.y))
				1:
					dir = Vector2i(0, 1)
					for x in range(pr.position.x + 1, pr.end.x - 1):
						cells.append(Vector2i(x, pr.end.y - 1))
				2:
					dir = Vector2i(-1, 0)
					for y in range(pr.position.y + 1, pr.end.y - 1):
						cells.append(Vector2i(pr.position.x, y))
				_:
					dir = Vector2i(1, 0)
					for y in range(pr.position.y + 1, pr.end.y - 1):
						cells.append(Vector2i(pr.end.x - 1, y))
			var ok: Array = []
			for c in cells:
				var cc: Vector2i = c
				var o := cc + dir
				var inn := cc - dir
				if not cv._in(o.x, o.y) or not cv._in(inn.x, inn.y):
					ok.append(null)
				elif _in_parts_except(parts, o, -1) or _in_parts_except(parts, cc, pi):
					ok.append(null)
				elif cv.is_open(cc.x, cc.y) or not cv.is_open(o.x, o.y) or not cv.is_open(inn.x, inn.y) or room_at[inn.y * lw + inn.x] < 0:
					ok.append(null)
				else:
					ok.append(cc)
			for i in ok.size() - 1:
				if ok[i] != null and ok[i + 1] != null:
					var a: Vector2i = ok[i]
					var b: Vector2i = ok[i + 1]
					var ra := room_at[(a - dir).y * lw + (a - dir).x]
					var rb := room_at[(b - dir).y * lw + (b - dir).x]
					if ra == rb:
						out.append({"tiles": [a, b], "dir": dir, "room": ra})
	return out


## The outer doors: the front one (into the entry room, on the front side when it can be) and a back door or two. {"front": [tiles], "all": [[tiles]], "garage": [tiles]}.
func _outer_doors(cv, parts: Array, rooms: Array, room_at: PackedInt32Array, front: String, kind: String, rng: RandomNumberGenerator, start: bool) -> Dictionary:
	var res := {"front": [], "all": [], "dirs": [], "garage": []}
	var cands := _outer_candidates(cv, parts, room_at)
	var front_dir := Vector2i(0, -1) if front == "N" else Vector2i(0, 1)
	var pool: Array = []
	for c in cands:
		if Vector2i(c.dir) == front_dir and bool(rooms[int(c.room)].entry):
			pool.append(c)
	if pool.is_empty():
		for c in cands:
			if Vector2i(c.dir) == front_dir:
				pool.append(c)
	if pool.is_empty():
		for c in cands:
			if bool(rooms[int(c.room)].entry):
				pool.append(c)
	if pool.is_empty():
		pool = cands
	if pool.is_empty():
		return res
	var pick: Dictionary = pool[rng.randi() % pool.size()]
	_cut_outer(cv, pick)
	res.front = pick.tiles
	res.all.append(pick.tiles)
	res.dirs.append(pick.dir)
	# a garage door in front of the garage
	if kind == "bungalow":
		var gp: Array = []
		for c in _outer_candidates(cv, parts, room_at):
			if String(rooms[int(c.room)].name) == "garage" and Vector2i(c.dir) == front_dir:
				gp.append(c)
		if not gp.is_empty():
			var g: Dictionary = gp[rng.randi() % gp.size()]
			_cut_outer(cv, g)
			res.garage = g.tiles
			res.all.append(g.tiles)
			res.dirs.append(g.dir)
	var back_n := 1
	var front_extra := 0
	match kind:
		"warehouse":
			back_n = 2
			front_extra = 1
		"fire_station":
			front_extra = 1
		"church":
			back_n = 0
	if kind != "warehouse" and not start and rng.randf() < 0.15:
		back_n = 0
	for n in back_n + front_extra:
		var want_front := n >= back_n
		var tries: Array = []
		for c in _outer_candidates(cv, parts, room_at):
			var is_front_side := Vector2i(c.dir) == front_dir
			if is_front_side != want_front:
				continue
			var far := true
			for done in res.all:
				for t in done:
					for u in c.tiles:
						if Vector2(t).distance_to(Vector2(u)) < 4.0:
							far = false
			if far:
				tries.append(c)
		if tries.is_empty():
			continue
		var extra: Dictionary = tries[rng.randi() % tries.size()]
		_cut_outer(cv, extra)
		res.all.append(extra.tiles)
		res.dirs.append(extra.dir)
	return res


func _cut_outer(cv, c: Dictionary) -> void:
	var d: Vector2i = c.dir
	for t in c.tiles:
		_door_cell(cv, t.x, t.y, d.y != 0)
		cv._keep_tile(t.x + d.x, t.y + d.y)
		cv._keep_tile(t.x + 2 * d.x, t.y + 2 * d.y)


## Opens a door to every room that cannot be reached from the way in.
func _repair(cv, rooms: Array, room_at: PackedInt32Array) -> void:
	var lw: int = cv.W
	for round in 6:
		var reach: PackedByteArray = cv.flood()
		var lost: Array = []
		for i in rooms.size():
			var rr: Rect2i = rooms[i].rect
			var seen := false
			for y in range(rr.position.y, rr.end.y):
				for x in range(rr.position.x, rr.end.x):
					if reach[y * lw + x] != 0:
						seen = true
			if not seen:
				lost.append(i)
		if lost.is_empty():
			return
		for i in lost:
			var rr: Rect2i = rooms[i].rect
			var done := false
			for y in range(rr.position.y - 1, rr.end.y + 1):
				for x in range(rr.position.x - 1, rr.end.x + 1):
					if done:
						continue
					var inside_x := x >= rr.position.x and x < rr.end.x
					var inside_y := y >= rr.position.y and y < rr.end.y
					if inside_x == inside_y or cv.is_open(x, y) or not cv._in(x, y):
						continue
					var dir := Vector2i(0, 0)
					if inside_x:
						dir = Vector2i(0, -1) if y < rr.position.y else Vector2i(0, 1)
					else:
						dir = Vector2i(-1, 0) if x < rr.position.x else Vector2i(1, 0)
					var far := Vector2i(x, y) - dir
					var near := Vector2i(x, y) + dir
					if cv.is_open(near.x, near.y) and cv.is_open(far.x, far.y) and reach[near.y * lw + near.x] != 0 and room_at[far.y * lw + far.x] == i:
						_door_cell(cv, x, y, dir.y != 0)
						done = true


## A collapsed wing: its cells are rubble (earth, scorch marks, piles of scrap), a few stumps of wall left standing.
func _rubble(cv, parts: Array, ruin: int, rng: RandomNumberGenerator) -> void:
	var pr: Rect2i = parts[ruin]
	for y in range(pr.position.y, pr.end.y):
		for x in range(pr.position.x, pr.end.x):
			var p := Vector2i(x, y)
			var shared := false
			for j in parts.size():
				if j != ruin and Rect2i(parts[j]).has_point(p):
					shared = true
			if shared:
				continue
			var edge := x == pr.position.x or y == pr.position.y or x == pr.end.x - 1 or y == pr.end.y - 1
			if edge and rng.randf() < 0.3:
				cv._wall(x, y, "WALL_BRICK")
			else:
				cv._paint(x, y, "DIRT" if rng.randf() < 0.7 else "CONCRETE", false)
	var inner := pr.grow(-1)
	cv.run({"ops": [
		{"op": "decals", "rect": [inner.position.x, inner.position.y, inner.size.x, inner.size.y], "kinds": ["scorch", "crack", "stain"], "n": 5},
		{"op": "scatter", "rect": [inner.position.x, inner.position.y, inner.size.x, inner.size.y], "kinds": ["scrap", "crate", "tires"], "n": 2, "container": 0.5},
	]})


## A shed in the back yard: 5 x 5 outer (a room of 3 x 3), a two wide door on the side that faces the house, a shelf and a crate. A building of its own (the next of `buildings`).
func _add_shed(cv, rng: RandomNumberGenerator, spec: Dictionary, out: Dictionary, bb: Rect2i, front: String) -> void:
	var lot: Rect2i = spec.rect
	var lw := lot.size.x
	var lh := lot.size.y
	# (beside or behind the house, never in front of it)
	var y_lo := bb.position.y + 1 if front == "N" else 2
	var y_hi := lh - 7 if front == "N" else bb.end.y - 6
	if y_hi < y_lo or lw < 11:
		return
	var spot := Vector2i(-1, -1)
	for attempt in 24:
		var x := rng.randi_range(2, lw - 9)
		var y := rng.randi_range(y_lo, y_hi)
		var free := true
		for yy in range(y - 1, y + 6):
			for xx in range(x - 1, x + 8):
				var i: int = yy * lw + xx
				if not cv._in(xx, yy) or cv.solid[i] != 0 or cv.keep[i] != 0 or cv.terrain[i] == int(tids.SIDEWALK) or cv.terrain[i] == int(tids.CONCRETE):
					free = false
		if free:
			spot = Vector2i(x, y)
			break
	if spot.x < 0:
		return
	var wall_name := String(spec.wall)
	if not tids.has(wall_name) or wall_name == "WALL_METAL":
		wall_name = "WALL_PLASTER"
	for yy in 5:
		for xx in 7:
			if xx == 0 or yy == 0 or xx == 6 or yy == 4:
				cv._wall(spot.x + xx, spot.y + yy, wall_name)
			else:
				cv._paint(spot.x + xx, spot.y + yy, "WOOD", false)
	# two small rooms: the shed and a store behind a partition with a doorway
	var inner := Rect2i(spot.x + 1, spot.y + 1, 5, 3)
	var rs: Array = []
	var ws: Array = []
	_partition(inner, Plans.programs("shed", rng)[0], front, rs, ws, rng)
	var bi: int = out.buildings.size()
	var ri := 0
	for rm in rs:
		cv.fill(rm.rect, "WOOD")
		cv.rects["shed%d" % ri] = rm.rect
		cv.areas.append({"name": String(rm.name), "rect": rm.rect, "dead": 1.0, "indoor": true, "b": bi})
		ri += 1
	for w3 in ws:
		for t in range(int(w3.from), int(w3.to) + 1):
			cv._wall(int(w3.pos) if not bool(w3.horiz) else t, t if not bool(w3.horiz) else int(w3.pos), WALL_IN)
	for w4 in ws:
		_door_in_wall(cv, w4, rng)
	var dir := Vector2i(0, -1) if front == "N" else Vector2i(0, 1)
	var dy := 0 if front == "N" else 4
	var dx := 1 if rng.randf() < 0.5 else 4    # (not over the partition, which stands at column 3)
	var door_tiles: Array = []
	for k in 2:
		_door_cell(cv, spot.x + dx + k, spot.y + dy, true)
		cv._keep_tile(spot.x + dx + k, spot.y + dy + dir.y)
		cv._keep_tile(spot.x + dx + k, spot.y + dy + 2 * dir.y)
		door_tiles.append(Vector2i(spot.x + dx + k + lot.position.x, spot.y + dy + lot.position.y))
	var shed_ops: Array = []
	for k in ri:
		shed_ops.append({"op": "place", "kind": "shelf_s", "in": "shed%d" % k, "anchor": "NW" if front == "S" else "SW", "container": true})
		shed_ops.append({"op": "place", "kind": "crate", "in": "shed%d" % k, "anchor": "NE" if front == "S" else "SE", "container": 0.8})
	cv.run({"ops": shed_ops})
	var door_out := Vector2i(spot.x + dx + lot.position.x, spot.y + dy + dir.y + lot.position.y)
	var box := Rect2i(spot.x + lot.position.x, spot.y + lot.position.y, 7, 5)
	out.buildings.append({"kind": "shed", "parts": [box], "box": box, "door": door_out, "front_door": door_tiles, "landmark": "", "state": "intact", "drive": Rect2i()})


# ================================================================== the furniture ==

## The ops that furnish a room of this name. `id` is the room's rectangle's name on the canvas.
func _ops_for(name: String, id: String, r: Rect2i, front: String, kind: String, rng: RandomNumberGenerator) -> Array:
	var ops: Array = []
	var w := r.size.x
	var h := r.size.y
	var back := "S" if front == "N" else "N"
	var near := "N" if front == "N" else "S"
	match name:
		"living room", "front room":
			if w >= 4 and h >= 3:
				ops.append({"op": "place", "kind": "rug", "in": id, "anchor": "C", "p": 0.7})
			ops.append({"op": "line", "rect": id, "side": back, "kinds": ["bench", "shelf_s", "desk"], "gap": [0, 1], "container": 0.5, "n": 2})
			ops.append({"op": "place", "kind": "lamp", "in": id, "anchor": back + "E", "p": 0.5})
			if kind == "small" or kind == "terrace" or kind == "cottage":
				ops.append({"op": "line", "rect": id, "side": "N" if back == "S" else "S", "kinds": ["fridge", "stove", "counter2"], "gap": [0, 0], "container": 0.7, "n": 2, "start": 1})
		"kitchen":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["fridge", "counter2", "stove"], "gap": [0, 0], "container": true, "n": 3})
			if w >= 4 and h >= 4:
				ops.append({"op": "place", "kind": "cans", "in": id, "anchor": "SW", "container": true, "p": 0.5})
		"bedroom":
			ops.append({"op": "place", "kind": "bed", "in": id, "anchor": "NW", "dx": {"r": [0, 1]}})
			ops.append({"op": "place", "kind": "cabinet", "in": id, "anchor": "NE", "container": true})
			ops.append({"op": "place", "kind": "lamp", "in": id, "anchor": "SW", "p": 0.5})
			if w >= 4 and h >= 4:
				ops.append({"op": "place", "kind": "rug", "in": id, "anchor": "C", "p": 0.5})
		"nursery":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["cot"], "gap": [0, 1], "n": 2})
			ops.append({"op": "place", "kind": "lamp", "in": id, "anchor": "SE", "p": 0.5})
		"bathroom":
			ops.append({"op": "place", "kind": "cabinet", "in": id, "anchor": "NE", "container": 0.9})
		"hall", "lobby", "narthex":
			if kind == "warehouse":
				ops.append({"op": "rows", "rect": id, "kinds": ["shelf", "shelf", "crate"], "pitch": 3, "y0": 2 if front == "N" else 1, "margin": 1, "gap_every": 3, "container": 0.8})
				ops.append({"op": "scatter", "rect": id, "kinds": ["crate", "barrel", "cans", "waterpack"], "n": 5, "container": 0.7})
			else:
				ops.append({"op": "place", "kind": "lamp", "in": id, "anchor": back + "W", "p": 0.6})
				ops.append({"op": "place", "kind": "shelf_s", "in": id, "anchor": "NE", "container": 0.4, "p": 0.5})
				ops.append({"op": "place", "kind": "trashcan", "in": id, "anchor": back + "E", "container": 0.5, "p": 0.4})
		"study", "office", "reception":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["desk", "desk2", "shelf_s"], "gap": [0, 1], "container": 0.6, "n": 3})
			ops.append({"op": "place", "kind": "lamp", "in": id, "anchor": "SE", "p": 0.6})
		"dining room":
			ops.append({"op": "place", "kind": "longtable" if (w >= 6 and h >= 4) else "desk2", "in": id, "anchor": "C"})
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["shelf_s", "cabinet"], "gap": [0, 1], "container": 0.6, "n": 2})
		"pantry":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["shelf_s", "cans", "waterpack"], "gap": [0, 0], "container": true, "n": 4})
		"garage":
			if w >= 5 and h >= 2:
				ops.append({"op": "place", "kind": "car_h", "in": id, "anchor": back + "W", "container": 0.7, "p": 0.7})
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["workbench", "tires", "barrel"], "gap": [0, 1], "container": 0.7, "n": 2})
		"shop floor":
			ops.append({"op": "rows", "rect": id, "kinds": ["shelf"], "pitch": 3, "y0": 2 if front == "N" else 1, "margin": 1, "container": 0.8})
			ops.append({"op": "line", "rect": id, "side": back, "kinds": ["counter3", "fridge", "counter2"], "gap": [0, 0], "container": true, "n": 2})
		"storeroom":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["crate", "cans", "waterpack", "shelf_s"], "gap": [0, 0], "container": true, "n": 4})
			if h >= 4 and w >= 4:
				ops.append({"op": "rows", "rect": id, "kinds": ["crate", "barrel"], "pitch": 3, "y0": 2, "margin": 1, "n": 1, "container": 0.6})
		"dining hall":
			ops.append({"op": "rows", "rect": id, "kinds": ["picnic"], "pitch": 3, "y0": 2 if front == "N" else 1, "margin": 1, "n": 2, "container": false})
			ops.append({"op": "line", "rect": id, "side": back, "kinds": ["counter", "fridge"], "gap": [0, 0], "container": true, "n": 2})
		"banking hall":
			ops.append({"op": "line", "rect": id, "side": back, "kinds": ["counter", "counter3"], "gap": [0, 0], "container": 0.6, "n": 2})
			ops.append({"op": "place", "kind": "bench", "in": id, "anchor": near + "W", "dy": 2 if front == "N" else -2})
		"vault", "armoury":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["locker", "crate_ammo", "locker"], "gap": [0, 0], "container": true, "n": 4})
		"engine bay":
			ops.append({"op": "place", "kind": "van_h", "in": id, "anchor": "C", "p": 0.8, "container": 0.8})
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["locker", "toolboard", "barrel"], "gap": [0, 1], "container": 0.6, "n": 3})
		"dormitory":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["cot", "cot", "locker"], "gap": [0, 1], "container": 0.5, "n": 4})
		"ward":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["cot"], "gap": [0, 1], "n": 3})
			ops.append({"op": "place", "kind": "ivstand", "in": id, "anchor": "SE"})
			ops.append({"op": "place", "kind": "locker", "in": id, "anchor": "SW", "container": 0.7})
		"waiting room":
			ops.append({"op": "line", "rect": id, "side": back, "kinds": ["bench"], "gap": [0, 1], "n": 3})
		"pharmacy":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["cabinet", "fridge", "shelf_s"], "gap": [0, 0], "container": true, "n": 4})
		"cell":
			ops.append({"op": "place", "kind": "cot", "in": id, "anchor": "NW"})
			ops.append({"op": "place", "kind": "bench", "in": id, "anchor": "SE"})
		"front desk":
			ops.append({"op": "line", "rect": id, "side": back, "kinds": ["counter3", "desk"], "gap": [0, 1], "container": 0.7, "n": 2})
			ops.append({"op": "place", "kind": "bench", "in": id, "anchor": near + "E", "dy": 2 if front == "N" else -2})
		"classroom":
			ops.append({"op": "rows", "rect": id, "kinds": ["desk"], "pitch": 2, "y0": 1, "margin": 1, "skip": 0.15, "container": 0.15})
			ops.append({"op": "place", "kind": "teacherdesk", "in": id, "anchor": "NE", "container": 0.5})
		"gym":
			ops.append({"op": "scatter", "rect": id, "kinds": ["crate", "bench", "locker"], "n": 4, "wall": true, "container": 0.5})
		"flat":
			ops.append({"op": "place", "kind": "bed", "in": id, "anchor": "NW"})
			ops.append({"op": "place", "kind": "cabinet", "in": id, "anchor": "NE", "container": true})
			ops.append({"op": "line", "rect": id, "side": "S", "kinds": ["fridge", "counter2", "stove"], "gap": [0, 0], "container": 0.6, "n": 2})
		"reading room":
			ops.append({"op": "rows", "rect": id, "kinds": ["desk2"], "pitch": 3, "y0": 2, "margin": 1, "n": 2, "container": 0.2})
			ops.append({"op": "line", "rect": id, "side": back, "kinds": ["counter3", "shelf"], "gap": [0, 0], "container": 0.6, "n": 2})
		"stacks":
			ops.append({"op": "rows", "rect": id, "kinds": ["shelf"], "pitch": 3, "y0": 1, "margin": 1, "container": 0.5})
		"nave":
			# pews either side of a middle aisle
			var c := w / 2
			var y := r.position.y + 2
			while y <= r.end.y - 2:
				var xl := r.position.x + 1
				while xl + 2 <= r.position.x + c:
					ops.append({"op": "place", "kind": "bench", "at": [xl, y]})
					xl += 3
				var xr := r.position.x + c + 1
				while xr + 2 <= r.end.x - 1:
					ops.append({"op": "place", "kind": "bench", "at": [xr, y]})
					xr += 3
				y += 2
		"chancel":
			ops.append({"op": "place", "kind": "counter3", "in": id, "anchor": "C", "container": 0.6})
		"workshop":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["workbench", "worktable", "generator"], "gap": [0, 1], "container": 0.8, "n": 3})
			ops.append({"op": "scatter", "rect": id, "kinds": ["tires", "barrel", "crate"], "n": 4, "container": 0.5})
			if kind == "garage" and w >= 7 and h >= 4:
				ops.append({"op": "place", "kind": "car_h", "in": id, "anchor": "C", "container": 0.6, "p": 0.7})
		"barn", "stable":
			ops.append({"op": "scatter", "rect": id, "kinds": ["crate", "barrel", "wheelbarrow", "compost"], "n": 6 if name == "barn" else 3, "container": 0.5})
		"shed", "store":
			ops.append({"op": "line", "rect": id, "side": "N", "kinds": ["shelf_s", "crate", "barrel"], "gap": [0, 0], "container": 0.8, "n": 2})
	ops.append({"op": "decals", "rect": [r.position.x, r.position.y, w, h], "kinds": ["papers", "blood", "stain"], "n": {"r": [0, 1]}})
	var _unused := rng
	return ops


# ======================================================================= the yard ==

## The path from the door to the street, a driveway, the fence.
func _dress_ground(cv, rng: RandomNumberGenerator, spec: Dictionary, out: Dictionary, parts: Array, front_pair: Array, doors: Dictionary, front: String, fenced: bool) -> void:
	var garage_pair: Array = doors.garage
	var lot: Rect2i = spec.rect
	var lw := lot.size.x
	var lh := lot.size.y
	var kind := String(spec.kind)
	var start := bool(spec.get("start", false))
	var district := String(spec.district)
	var bb: Rect2i = parts[0]
	for p in parts:
		bb = bb.merge(p)
	if not front_pair.is_empty():
		var d0: Vector2i = front_pair[0]
		var y_a := 0 if front == "N" else d0.y + 1
		var y_b := d0.y if front == "N" else lh
		var span := Rect2i(d0.x, y_a, 2, y_b - y_a)
		if span.size.y > 0:
			cv.fill(span, "SIDEWALK")
			cv._keep_rect(span, true)
	# a driveway: to the garage when there is one, else beside the house (suburb)
	var drive := Rect2i()
	if district == "suburb" and not start and kind != "terrace":
		if not garage_pair.is_empty():
			var g0: Vector2i = garage_pair[0]
			var ya := 0 if front == "N" else g0.y + 1
			var yb := g0.y if front == "N" else lh
			drive = Rect2i(g0.x, ya, 2, yb - ya)
		elif rng.randf() < 0.5:
			var left_room := bb.position.x
			var right_room := lw - bb.end.x
			if maxi(left_room, right_room) >= 3:
				var dx := bb.position.x - 3 if left_room >= right_room else bb.end.x + 1
				var ya2 := 0 if front == "N" else bb.position.y + bb.size.y / 2
				var yb2 := bb.position.y + bb.size.y / 2 if front == "N" else lh
				drive = Rect2i(dx, ya2, 2, yb2 - ya2)
		if drive.size.x > 0 and drive.size.y >= 2 and drive.position.x >= 0 and drive.end.x <= lw:
			cv.fill(drive, "CONCRETE")
			out.drive = Rect2i(drive.position.x + lot.position.x, drive.position.y + lot.position.y, drive.size.x, drive.size.y)
	if fenced:
		var gate_x := 1
		if not front_pair.is_empty():
			gate_x = clampi((front_pair[0] as Vector2i).x - 1, 1, maxi(1, lw - 5))
		var gates: Array = [{"side": front, "at": gate_x, "w": 4}]
		# a side or back door that opens on the fence line gets a gate of its own
		for k in range(1, doors.all.size()):
			var tiles: Array = doors.all[k]
			var dir: Vector2i = doors.dirs[k]
			var o: Vector2i = Vector2i(tiles[0]) + dir
			if o.x <= 0:
				gates.append({"side": "W", "at": o.y, "w": 2})
			elif o.x >= lw - 1:
				gates.append({"side": "E", "at": o.y, "w": 2})
			elif o.y <= 0:
				gates.append({"side": "N", "at": o.x, "w": 2})
			elif o.y >= lh - 1:
				gates.append({"side": "S", "at": o.x, "w": 2})
		cv.run({"ops": [{"op": "fence", "rect": [0, 0, lw, lh], "t": "WALL_METAL", "gates": gates}]})


## Trees, shrubs, a parked car, the odd mark on the ground, by the kind of building and yard.
func _dress_yard(cv, rng: RandomNumberGenerator, spec: Dictionary, out: Dictionary, parts: Array, front_pair: Array, front: String, _fenced: bool) -> void:
	var lot: Rect2i = spec.rect
	var lw := lot.size.x
	var lh := lot.size.y
	var kind := String(spec.kind)
	if bool(spec.get("start", false)):
		return
	var district := String(spec.district)
	var yard := String(spec.get("yard", "lawn"))
	var bb: Rect2i = parts[0]
	for p in parts:
		bb = bb.merge(p)
	var all := [0, 0, lw, lh]
	var ops: Array = []
	var trees_n := 0
	match district:
		"suburb":
			trees_n = rng.randi_range(0, 2)
		"edge":
			trees_n = rng.randi_range(1, 3)
	if yard == "overgrown":
		trees_n += 2
	elif yard == "bare":
		trees_n = 0
	if trees_n > 0:
		ops.append({"op": "trees", "rect": all, "n": trees_n, "on": ["GRASS"], "gap": 3})
	if district == "suburb" or district == "edge":
		ops.append({"op": "scatter", "rect": all, "kinds": ["shrub"], "n": {"r": [0, 2]} if yard != "overgrown" else 4, "wall": true, "apart": 1})
		if yard == "garden":
			ops.append({"op": "place", "kind": "garden_h", "at": [1, (bb.end.y + 1) if front == "N" else 1], "p": 0.8})
	var drive: Rect2i = out.drive
	if drive.size.x > 0 and rng.randf() < 0.5:
		var dl := Rect2i(drive.position.x - lot.position.x, drive.position.y - lot.position.y, drive.size.x, drive.size.y)
		if dl.size.y >= 5:
			ops.append({"op": "place", "kind": "car_v", "at": [dl.position.x, dl.position.y if front == "N" else dl.end.y - 5], "container": 0.6})
	match kind:
		"scrapyard":
			ops.append({"op": "scatter", "rect": all, "kinds": ["scrap", "tires", "barrel", "crate"], "n": 10, "container": 0.7, "apart": 1})
			ops.append({"op": "scatter", "rect": all, "kinds": ["cont_blue", "cont_red"], "n": 1})
		"containers":
			ops.append({"op": "scatter", "rect": all, "kinds": ["cont_red", "cont_blue", "cont_green_v", "cont_orange_v"], "n": 5, "apart": 1})
			ops.append({"op": "scatter", "rect": all, "kinds": ["crate", "barrel"], "n": 4, "container": 0.6})
		"supermarket":
			var by0 := 1 if front == "N" else bb.end.y + 1
			var hh := bb.position.y - 2 if front == "N" else lh - bb.end.y - 2
			if hh >= 4:
				ops.append({"op": "cars", "rect": [0, by0, lw, hh], "n": 7, "kinds": ["car_h"]})
		"school":
			# the grounds behind the school: a court with its hoop, a four square, a hopscotch
			var back_y := bb.end.y + 1 if front == "N" else 1
			var back_h := lh - bb.end.y - 1 if front == "N" else bb.position.y - 2
			if back_h >= 12 and lw >= 14:
				ops.append({"op": "place", "kind": "court", "at": [1, back_y]})
				ops.append({"op": "place", "kind": "hoop", "at": [6, back_y + 1]})
				if lw >= 22:
					ops.append({"op": "place", "kind": "foursquare", "at": [15, back_y + 2]})
					ops.append({"op": "place", "kind": "hopscotch", "at": [lw - 3, back_y + 2]})
			elif back_h >= 6 and lw >= 10:
				ops.append({"op": "place", "kind": "foursquare", "at": [1, back_y + 1]})
				ops.append({"op": "place", "kind": "hopscotch", "at": [7, back_y + 1]})
		"church":
			ops.append({"op": "scatter", "rect": all, "kinds": ["shrub"], "n": 5, "wall": true})
			ops.append({"op": "trees", "rect": all, "n": 6, "on": ["GRASS"], "gap": 3})
			ops.append({"op": "scatter", "rect": all, "kinds": ["bench"], "n": 2, "apart": 2})
		"farmhouse":
			ops.append({"op": "place", "kind": "clothesline", "at": [1, lh - 3 if front == "N" else 2], "p": 0.4})
	ops.append({"op": "decals", "rect": all, "kinds": ["papers", "stain", "blood", "crack"], "n": {"r": [0, 2]}})
	# a hedge along the street side of a few suburban lawns (kept off the path, the driveway and the gate)
	if district == "suburb" and yard == "lawn" and not bool(spec.get("fenced", false)) and rng.randf() < 0.22:
		var hy := 0 if front == "N" else lh - 1
		var skip: Array = []
		for t in front_pair:
			skip.append((t as Vector2i).x)
		var dr := Rect2i(drive.position.x - lot.position.x, drive.position.y - lot.position.y, drive.size.x, drive.size.y)
		var hx := 0
		while hx < lw:
			if not (hx in skip or (hx + 1) in skip or (hx - 1) in skip) and not (dr.size.x > 0 and hx >= dr.position.x - 1 and hx <= dr.end.x):
				ops.append({"op": "place", "kind": "shrub", "at": [hx, hy]})
			hx += 2
	# sandbags in front of the door of a barricaded house (the back is left open)
	if bool(spec.get("barricade", false)) and not front_pair.is_empty():
		var d0: Vector2i = front_pair[0]
		var oy := d0.y - 2 if front == "N" else d0.y + 2
		ops.append({"op": "place", "kind": "sandbags", "at": [d0.x - 1, oy]})
	if not ops.is_empty():
		cv.run({"ops": ops})


## A lot with no building: the ground and what grows or stands on it.
func _yard_lot(cv, rng: RandomNumberGenerator, spec: Dictionary, out: Dictionary) -> void:
	var lot: Rect2i = spec.rect
	var lw := lot.size.x
	var lh := lot.size.y
	var kind := String(spec.kind)
	var ops: Array = []
	var all := [0, 0, lw, lh]
	cv.entry = Vector2i(lw / 2, 0)
	match kind:
		"pocket":
			ops.append({"op": "trees", "rect": all, "n": {"r": [1, 3]}, "on": ["GRASS"], "gap": 3})
			ops.append({"op": "scatter", "rect": all, "kinds": ["shrub"], "n": {"r": [0, 2]}, "apart": 1})
			if lw >= 5 and rng.randf() < 0.4:
				ops.append({"op": "place", "kind": "bench", "at": [lw / 2 - 1, lh / 2]})
			ops.append({"op": "decals", "rect": all, "kinds": ["papers", "stain", "crack"], "n": {"r": [0, 2]}})
		"park":
			var px := lw / 2
			var py := lh / 2
			cv.fill(Rect2i(px - 1, 0, 2, lh), "DIRT")
			cv.fill(Rect2i(0, py - 1, lw, 2), "DIRT")
			var feature := rng.randi() % 3
			if feature == 0 and lw >= 20 and lh >= 20:
				var qx := 3 if rng.randf() < 0.5 else lw - 12
				var qy := 3 if rng.randf() < 0.5 else lh - 10
				_pond(cv, Vector2i(qx + 4, qy + 3), 4.5, 3.2)
			elif feature == 1 and lw >= 20 and lh >= 20:
				var cx := 2 if rng.randf() < 0.5 else lw - 14
				var cy := 2 if rng.randf() < 0.5 else lh - 14
				ops.append({"op": "place", "kind": "court", "at": [cx, cy]})
				ops.append({"op": "place", "kind": "hoop", "at": [cx + 5, cy + 1]})
				ops.append({"op": "place", "kind": "foursquare", "at": [clampi(cx + (-5 if cx > lw / 2 else 13), 0, lw - 4), clampi(cy + 2, 0, lh - 4)]})
			ops.append({"op": "scatter", "rect": all, "kinds": ["picnic", "bench"], "n": {"r": [3, 5]}, "apart": 2})
			ops.append({"op": "trees", "rect": all, "n": {"r": [10, 16]}, "on": ["GRASS"], "gap": 3})
			ops.append({"op": "scatter", "rect": all, "kinds": ["shrub"], "n": {"r": [2, 4]}})
		"plaza":
			cv.fill(Rect2i(0, 0, lw, lh), "SIDEWALK")
			var n := mini(3, (lw - 2) / 5)
			for i in n:
				var sx := 1 + i * 5
				var sy := 2 if String(spec.front) == "N" else lh - 4
				ops.append({"op": "place", "kind": "counter3", "at": [sx, sy], "container": true})
				ops.append({"op": "place", "kind": "awning_r" if i % 2 == 0 else "awning_b", "at": [sx - 1, sy - 1], "decor": true})
				ops.append({"op": "place", "kind": "crate", "at": [sx + 3, sy], "container": 0.7})
			ops.append({"op": "scatter", "rect": all, "kinds": ["bench", "trashcan"], "n": 3, "apart": 2})
			ops.append({"op": "trees", "rect": all, "n": 2, "on": ["SIDEWALK"], "gap": 4})
		"field":
			var y := 1
			while y + 2 <= lh - 1:
				cv.fill(Rect2i(1, y, lw - 2, 2), "SOIL")
				y += 3
			ops.append({"op": "trees", "rect": all, "n": {"r": [0, 2]}, "on": ["GRASS"], "gap": 4})
		"woods":
			ops.append({"op": "trees", "rect": all, "n": maxi(3, lw * lh / 14), "on": ["GRASS"], "gap": 2})
			ops.append({"op": "scatter", "rect": all, "kinds": ["shrub"], "n": {"r": [2, 4]}})
		"meadow":
			ops.append({"op": "trees", "rect": all, "n": {"r": [2, 4]}, "on": ["GRASS"], "gap": 4})
			ops.append({"op": "scatter", "rect": all, "kinds": ["shrub"], "n": {"r": [2, 4]}})
			ops.append({"op": "patch", "rect": all, "t": "DIRT", "n": 2, "r": [1.5, 3]})
	if not ops.is_empty():
		cv.run({"ops": ops})


## A round pond of the WATER ground (a base ground when the picture is missing: see TownDistricts.terrains) that shuts the way.
func _pond(cv, centre: Vector2i, rx: float, ry: float) -> void:
	for y in range(centre.y - int(ry) - 1, centre.y + int(ry) + 2):
		for x in range(centre.x - int(rx) - 1, centre.x + int(rx) + 2):
			var dx := (float(x) + 0.5 - float(centre.x)) / rx
			var dy := (float(y) + 0.5 - float(centre.y)) / ry
			if dx * dx + dy * dy <= 1.0 and cv._in(x, y):
				cv._paint(x, y, "WATER", true)
