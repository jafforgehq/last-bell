## The buildings of the town (One House, TOWNGEN): from a lot (a rectangle, the side its front is on, the kind of building) to a small SiteCanvas (scripts/raid/site_canvas.gd) holding
## the ground, the walls, the doors, the rooms and their furniture, the yard and what stands in it. TownGen (scripts/town/town_gen.gd) stamps the canvas into the town.
##
## FOOTPRINTS. A building is a set of PARTS: rectangles of outer walls that touch along a one tile wall they share (an L is two parts, a T two, a U three, a bungalow with its garage
## two, a church three: tower, nave, chancel; scripts/town/building_plans.gd draws them, the front at the top, and `build` turns a plan over for a lot whose front is south).
## Each part is partitioned into ROOMS (rectangles) by a BSP that follows a program of room names with shares of the floor (the entry room, the one the front door opens into,
## always touches the front wall of its part). Doors are cut in the partition walls where both sides are floor, between touching parts, and in the outer walls (a front door into the
## entry room, a back door); a repair pass opens a door to any room that cannot be reached. Then the rooms are furnished and the yard is dressed with the ART KIT's things
## (scripts/town/town_kit.gd: the furniture of each room by its name, the path, the step, bushes, a mailbox, a fence or hedge, a car on gravel...).
##
## The outside walls are the terrain WALL_BRICK and the walls inside WALL_PLASTER (what the world draws as walls); the MATERIAL of the outside wall (brick, white or blue siding, stucco...)
## is the generator's `data.kit.wall` code of the house, chosen by district (scripts/town/town_districts.gd).
##
## CLEARANCE. Every room of every house can be walked all over by the avatar, the survivors and the dead from any of its doors: the free floor of a room is ONE piece (4-connected: a body 0.6
## wide goes wherever a tile does, and never across a corner) and a small room keeps a share of it free. The kit's `put` keeps it so as it furnishes (scripts/town/town_kit.gd), and `_unblock`
## checks every room again at the end and takes away what the canvas's own rows and lines laid across one.
extends RefCounted

const Canvas := preload("res://scripts/raid/site_canvas.gd")
const Plans := preload("res://scripts/town/building_plans.gd")

const WALL_OUT := "WALL_BRICK"
const WALL_IN := "WALL_PLASTER"
const DOOR_T := "DOOR_WOOD"
## The tiles each side of a doorway that no furniture may stand on (one: the rooms are small).
const DOOR_KEEP := 1
## The kinds that are a yard and no building.
const YARD_KINDS := ["pocket", "park", "plaza", "field", "woods", "meadow"]
## The kinds whose lot is a home (a yard with a path, bushes, a mailbox...): the rest are shops, works and public buildings.
const HOME_KINDS := ["start", "small", "medium", "bungalow", "lhouse", "thouse", "uhouse", "twowing", "terrace", "terrace_ext", "cottage", "farmhouse"]
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
## The kit's toolbox (scripts/town/town_kit.gd).
var kit
var _size := 192


func setup(prop_catalogue: Dictionary, terrain_ids: Dictionary, kit_in, world_size: int = 192) -> void:
	props = prop_catalogue
	tids = terrain_ids
	kit = kit_in
	_size = world_size


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


## Everything of one lot. `spec`: {"kind", "district", "rect" (the lot, in the town), "front", "plan", "seed", "start", "fenced", "yard" (a yard type), "ruin", "burnt", "barricade", "shed"}.
## Returns {"cv": the canvas, "buildings": [{"kind", "parts": [Rect2i] (in the town), "box": Rect2i, "door": the tile outside the front door, "front_door": [tiles],
## "landmark": "", "state": "intact"|"ruined"|"burnt", "drive": Rect2i (town) or empty}] (the main building first, then a shed), "reach": the flood from the entry, "dressing": {"ground":
## [[x, y, code]], "lines": [[x, y, code]], "gates": [...]} (lot coordinates, for the kit's data)}. The rooms of the canvas's `areas` say which building they are in ("b").
## A lot with no building has none.
func build(spec: Dictionary) -> Dictionary:
	var lot: Rect2i = spec.rect
	var cv := Canvas.new()
	cv.setup(lot.size.x, lot.size.y, int(spec.seed), props, tids, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed) * 31 + 7
	var out := {"cv": cv, "buildings": [], "state": "intact", "reach": PackedByteArray(), "dressing": {"ground": [], "lines": [], "gates": []}}
	if String(spec.kind) in YARD_KINDS:
		_yard_lot(cv, rng, spec, out)
	else:
		_building_lot(cv, rng, spec, out)
	kit.kitify(cv, rng)
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
		# two tiles of clear ground to the sides and behind, and the step before the door (a tile beyond the ring) in front
		bx = 2
		by = 3 if front == "N" else lh - box.y - 3
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
					cv._wall(x, y, WALL_OUT)
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
	var fence_gates := _fence(cv, spec, parts, front_pair, doors, front, fenced)
	# the furniture of every room, by its name
	var has_kitchen := false
	for rm in rooms:
		if String(rm.name) == "kitchen":
			has_kitchen = true
	for rm in rooms:
		var rn := String(rm.name)
		kit.furnish_room(cv, rng, rn, rm.rect, front, kind, start, rn == "living room" and not has_kitchen and kind in ["small", "cottage"])
	if start:
		kit.start_extras(cv, rng)
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
	var bb := Rect2i(x0, y0, x1 - x0, y1 - y0)
	out.buildings.append({"kind": kind, "parts": town_parts, "box": Rect2i(x0 + lot.position.x, y0 + lot.position.y, x1 - x0, y1 - y0),
		"door": Vector2i(cv.entry.x + lot.position.x, cv.entry.y + lot.position.y), "front_door": fdt, "landmark": String(plan.get("landmark", "")), "state": String(out.state), "drive": Rect2i()})
	if bool(spec.get("shed", false)) and not start:
		_add_shed(cv, rng, spec, out, bb, front)
	# the yard: the path, the step, bushes, a fence or hedge, a car on gravel (the kit's)
	var back_dir := Vector2i(0, 1) if front == "N" else Vector2i(0, -1)
	var back_door := Vector2i(-1, -1)
	for k in range(1, doors.all.size()):
		if Vector2i(doors.dirs[k]) == back_dir:
			back_door = Vector2i(doors.all[k][0]) + back_dir
			break
	var garage := Vector2i(doors.garage[0]) if not (doors.garage as Array).is_empty() else Vector2i(-1, -1)
	var dressing: Dictionary = kit.dress_lot(cv, rng, kind, lot, front, bb, cv.entry, back_door, garage, start, fenced, kind in HOME_KINDS, _size)
	out.dressing.ground.append_array(dressing.ground)
	out.dressing.lines.append_array(dressing.lines)
	out.dressing.gates.append_array(dressing.gates)
	out.dressing.gates.append_array(fence_gates)
	out.buildings[0].drive = dressing.drive
	_dress_extra(cv, rng, spec, bb, front, front_pair)
	_unblock(cv)


## The clearance check, run on every building after its furnishing (the safety net: the kit's `put` keeps each room clear as it sets a thing, but the site canvas's own rows and lines of
## shelves and the scatter of crates do not ask). A body must be able to walk from any free tile of a room to any other WITHOUT leaving it, and from the tile behind every door, so
## (1) every room can be reached from the way in at all, else the furniture of the rooms is taken away, the last put first, until it can; and (2) the free floor of every room is one piece
## and a small room has a share of it free (`TownKit.room_is_clear`): from the room's things the one whose going mends the most is taken away (the least needed first, the last put
## first of those), until it is. The avatar's box (0.6 wide) goes wherever a tile does, four ways: so a floor of one piece of tiles is one it can walk all over; there is no need
## to erode the grid by its radius, which is under half a tile.
func _unblock(cv) -> void:
	var lw: int = cv.W
	for round in 14:
		var reach: PackedByteArray = cv.flood()
		var lost := false
		for a in cv.areas:
			if not bool(a.indoor):
				continue
			var rr: Rect2i = a.rect
			var seen := false
			for y in range(rr.position.y, rr.end.y):
				for x in range(rr.position.x, rr.end.x):
					if reach[y * lw + x] != 0:
						seen = true
			if not seen:
				lost = true
		if not lost:
			break
		for k in range(cv.objects.size() - 1, -1, -1):
			var o: Dictionary = cv.objects[k]
			if not bool(o.get("solid", false)):
				continue
			var tx := roundi(float(o.cx) - float(o.w) / 2.0)
			var ty := roundi(float(o.cy) - float(o.h) / 2.0)
			var inside := false
			for a in cv.areas:
				if bool(a.indoor) and Rect2i(a.rect).has_point(Vector2i(tx, ty)):
					inside = true
			if not inside:
				continue
			_take_away(cv, k)
			break
	for a in cv.areas:
		if not bool(a.indoor):
			continue
		var rr2: Rect2i = a.rect
		for round in 24:
			if kit.room_is_clear(cv, rr2):
				break
			if not _mend_room(cv, rr2):
				break


## Takes the thing `k` of the canvas away: its tiles are open again and it is no container.
func _take_away(cv, k: int) -> void:
	var lw: int = cv.W
	var o: Dictionary = cv.objects[k]
	var tx := roundi(float(o.cx) - float(o.w) / 2.0)
	var ty := roundi(float(o.cy) - float(o.h) / 2.0)
	for yy in int(o.h):
		for xx in int(o.w):
			cv.solid[(ty + yy) * lw + tx + xx] = 0
			cv.pmask[(ty + yy) * lw + tx + xx] = 0
	cv.objects.remove_at(k)
	var keep: Array = []
	for c in cv.cands:
		if c.obj != o:
			keep.append(c)
	cv.cands = keep


## How little a kind of furniture is missed (0 first to go).
const KEEP_RANK := {
	"crate": 0, "box": 0, "bin": 0, "bench": 0, "armchair": 0, "coffee_table": 0, "nightstand": 0, "kitchen_counter": 0, "cupboard": 0, "shelf_tins": 0, "bookshelf": 0,
	"wardrobe": 1, "dresser": 1, "tv_stand": 1, "desk": 1, "workbench": 1, "dining_table": 1, "kitchen_sink": 1, "loveseat": 1,
	"toilet": 2, "washbasin": 2, "bathtub": 2, "fridge": 2, "stove": 2, "sofa": 2, "bed_single": 2, "bed_double": 2,
}


## Takes away from a room the one thing whose going mends its floor the most (a piece joined, tiles freed); false when nothing in it can be.
func _mend_room(cv, rr: Rect2i) -> bool:
	var need: int = kit.free_needed(rr.size.x * rr.size.y)
	var f: Dictionary = kit.room_floor(cv, rr)
	var best := -1
	var best_score := -1.0e9
	for k in range(cv.objects.size() - 1, -1, -1):
		var o: Dictionary = cv.objects[k]
		if not bool(o.get("solid", false)):
			continue
		var tx := roundi(float(o.cx) - float(o.w) / 2.0)
		var ty := roundi(float(o.cy) - float(o.h) / 2.0)
		if not rr.has_point(Vector2i(tx, ty)):
			continue
		var fp := Rect2i(tx, ty, int(o.w), int(o.h))
		# the floor as it would lie with this thing gone: the tiles of the thing, which are shut now, count as free
		var after := _floor_without(cv, rr, fp)
		var clear: bool = int(after.free) >= need and int(after.reached) == int(after.free)
		var gain := float(after.reached) - float(f.reached) + float(after.free) - float(f.free) * 0.5
		var score := (1000.0 if clear else 0.0) + gain - float(int(KEEP_RANK.get(String(o.kind), 1))) * 20.0 - float(fp.size.x * fp.size.y) * 0.5 + float(k) * 0.001
		if score > best_score:
			best_score = score
			best = k
	if best < 0:
		return false
	_take_away(cv, best)
	return true


## `TownKit.room_floor` with the tiles of `fp` made free for a moment.
func _floor_without(cv, rr: Rect2i, fp: Rect2i) -> Dictionary:
	var lw: int = cv.W
	var saved: Array = []
	for yy in range(fp.position.y, fp.end.y):
		for xx in range(fp.position.x, fp.end.x):
			saved.append(cv.solid[yy * lw + xx])
			cv.solid[yy * lw + xx] = 0
	var out: Dictionary = kit.room_floor(cv, rr)
	var i := 0
	for yy in range(fp.position.y, fp.end.y):
		for xx in range(fp.position.x, fp.end.x):
			cv.solid[yy * lw + xx] = saved[i]
			i += 1
	return out


## The fence round a lot (a band of WALL_METAL cells the world draws as the kit's fence), gates for the front and for every side or back door that opens on it. Returns the gates for
## the kit's data.
func _fence(cv, spec: Dictionary, _parts: Array, front_pair: Array, doors: Dictionary, front: String, fenced: bool) -> Array:
	var out: Array = []
	if not fenced:
		return out
	var lot: Rect2i = spec.rect
	var lw := lot.size.x
	var lh := lot.size.y
	var gate_x := 1
	if not front_pair.is_empty():
		gate_x = clampi((front_pair[0] as Vector2i).x - 1, 1, maxi(1, lw - 5))
	var gates: Array = [{"side": front, "at": gate_x, "w": 4}]
	out.append({"x": gate_x, "y": lh - 1 if front == "S" else 0, "w": 4, "orient": "h", "fenced": true})
	# a side or back door that opens on the fence line gets a gate of its own
	for k in range(1, doors.all.size()):
		var tiles: Array = doors.all[k]
		var dir: Vector2i = doors.dirs[k]
		var o: Vector2i = Vector2i(tiles[0]) + dir
		if o.x <= 0:
			gates.append({"side": "W", "at": o.y, "w": 2})
			out.append({"x": 0, "y": o.y, "w": 2, "orient": "v", "fenced": true})
		elif o.x >= lw - 1:
			gates.append({"side": "E", "at": o.y, "w": 2})
			out.append({"x": lw - 1, "y": o.y, "w": 2, "orient": "v", "fenced": true})
		elif o.y <= 0:
			gates.append({"side": "N", "at": o.x, "w": 2})
			out.append({"x": o.x, "y": 0, "w": 2, "orient": "h", "fenced": true})
		elif o.y >= lh - 1:
			gates.append({"side": "S", "at": o.x, "w": 2})
			out.append({"x": o.x, "y": lh - 1, "w": 2, "orient": "h", "fenced": true})
	cv.run({"ops": [{"op": "fence", "rect": [0, 0, lw, lh], "t": "WALL_METAL", "gates": gates}]})
	return out


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
				"overgrown":
					cv.run({"ops": [{"op": "patch", "rect": [0, 0, lw, lh], "t": "SOIL", "n": 2, "r": [1.5, 2.5]}]})
	if kind == "supermarket":
		cv.fill(front_strip, "CONCRETE")


## What a lot has beyond the kit's yard: trees, and by the kind of building a car park, a school's grounds, a church's graves, a scrapyard's wrecks, sandbags before a barricaded door.
func _dress_extra(cv, rng: RandomNumberGenerator, spec: Dictionary, bb: Rect2i, front: String, front_pair: Array) -> void:
	var lot: Rect2i = spec.rect
	var lw := lot.size.x
	var lh := lot.size.y
	var kind := String(spec.kind)
	var district := String(spec.district)
	var yard := String(spec.get("yard", "lawn"))
	var start := bool(spec.get("start", false))
	if start:
		return
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
	if yard == "overgrown":
		for k in 3:
			kit.scatter(cv, rng, "bush", 0, lw - 1, 0, lh - 1)
	match kind:
		"scrapyard":
			for k in 8:
				kit.scatter(cv, rng, ["crate", "box", "toolbox"][rng.randi() % 3], 1, lw - 2, 1, lh - 2)
			for k in 2:
				kit.scatter(cv, rng, "car_wreck", 1, lw - 5, 1, lh - 4)
		"containers":
			ops.append({"op": "scatter", "rect": all, "kinds": ["cont_red", "cont_blue", "cont_green_v", "cont_orange_v"], "n": 5, "apart": 1})
			for k in 4:
				kit.scatter(cv, rng, ["crate", "box"][rng.randi() % 2], 1, lw - 2, 1, lh - 2)
		"supermarket":
			var by0 := 1 if front == "N" else bb.end.y + 1
			var hh := bb.position.y - 2 if front == "N" else lh - bb.end.y - 2
			if hh >= 4:
				ops.append({"op": "cars", "rect": [0, by0, lw, hh], "n": 7, "kinds": ["car_h"]})
		"school":
			# the grounds behind the school: a court with its hoop, a four square, a hopscotch, a swing set
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
			if back_h >= 4:
				kit.scatter(cv, rng, "swing_set", 1, lw - 4, back_y, back_y + back_h - 2)
				kit.scatter(cv, rng, "slide", 1, lw - 2, back_y, back_y + back_h - 3)
		"church":
			for k in 5:
				kit.scatter(cv, rng, "bush", 0, lw - 1, 0, lh - 1)
			ops.append({"op": "trees", "rect": all, "n": 6, "on": ["GRASS"], "gap": 3})
			for k in 2:
				kit.scatter(cv, rng, "bench", 1, lw - 3, 1, lh - 2)
	if rng.randf() < 0.5:
		ops.append({"op": "decals", "rect": all, "kinds": ["papers", "broken_glass", "blood_stain"], "n": {"r": [0, 2]}})
	# sandbags in front of the door of a barricaded house (the back is left open)
	if bool(spec.get("barricade", false)) and not front_pair.is_empty():
		var d0: Vector2i = front_pair[0]
		var oy := d0.y - 2 if front == "N" else d0.y + 2
		ops.append({"op": "place", "kind": "sandbags", "at": [d0.x - 1, oy]})
	if not ops.is_empty():
		cv.run({"ops": ops})


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


## The outer doors: the front one (into the entry room, on the front side when it can be) and a back door or two. {"front": [tiles], "all": [[tiles]], "dirs": [outward], "garage": [tiles]}.
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
				cv._wall(x, y, WALL_OUT)
			else:
				cv._paint(x, y, "DIRT" if rng.randf() < 0.7 else "CONCRETE", false)
	var inner := pr.grow(-1)
	cv.run({"ops": [
		{"op": "decals", "rect": [inner.position.x, inner.position.y, inner.size.x, inner.size.y], "kinds": ["scorch", "crack", "blood_stain"], "n": 5},
		{"op": "scatter", "rect": [inner.position.x, inner.position.y, inner.size.x, inner.size.y], "kinds": ["box", "crate"], "n": 2, "container": 0.5},
	]})


## A shed beside or behind the house: 7 x 5 outer (two small rooms, the shed and a store), a two wide door on the street side. A building of its own (the next of `buildings`).
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
	for yy in 5:
		for xx in 7:
			if xx == 0 or yy == 0 or xx == 6 or yy == 4:
				cv._wall(spot.x + xx, spot.y + yy, WALL_OUT)
			else:
				cv._paint(spot.x + xx, spot.y + yy, "WOOD", false)
	# two small rooms: the shed and a store behind a partition with a doorway
	var inner := Rect2i(spot.x + 1, spot.y + 1, 5, 3)
	var rs: Array = []
	var ws: Array = []
	_partition(inner, Plans.programs("shed", rng)[0], front, rs, ws, rng)
	var bi: int = out.buildings.size()
	for rm in rs:
		cv.fill(rm.rect, "WOOD")
		cv.areas.append({"name": String(rm.name), "rect": rm.rect, "dead": 1.0, "indoor": true, "b": bi})
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
	for rm in rs:
		kit.furnish_room(cv, rng, String(rm.name), rm.rect, front, "shed", false, false)
	var door_out := Vector2i(spot.x + dx + lot.position.x, spot.y + dy + dir.y + lot.position.y)
	var box := Rect2i(spot.x + lot.position.x, spot.y + lot.position.y, 7, 5)
	out.buildings.append({"kind": "shed", "parts": [box], "box": box, "door": door_out, "front_door": door_tiles, "landmark": "", "state": "intact", "drive": Rect2i()})


# ================================================================= lots without a building ==

## A lot with no building: the ground and what grows or stands on it (the kit's benches, stalls, swings and bushes).
func _yard_lot(cv, rng: RandomNumberGenerator, spec: Dictionary, _out: Dictionary) -> void:
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
			for k in rng.randi_range(0, 2):
				kit.scatter(cv, rng, "bush", 0, lw - 1, 0, lh - 1)
			if lw >= 5 and rng.randf() < 0.4:
				kit.scatter(cv, rng, "bench", 1, lw - 3, 1, lh - 2)
		"park":
			var px := lw / 2
			var py := lh / 2
			cv.fill(Rect2i(px - 1, 0, 2, lh), "DIRT")
			cv.fill(Rect2i(0, py - 1, lw, 2), "DIRT")
			var feature := rng.randi() % 3
			if feature == 0 and lw >= 18 and lh >= 18:
				# a clearing: bare earth round a ring of benches
				var cx := (4 if rng.randf() < 0.5 else lw - 6) + 0
				var cy := (4 if rng.randf() < 0.5 else lh - 6) + 0
				for yy in range(cy - 3, cy + 4):
					for xx in range(cx - 3, cx + 4):
						if Vector2(xx - cx, yy - cy).length() <= 3.2 and cv._in(xx, yy):
							cv._paint(xx, yy, "DIRT", false)
				kit.put(cv, "bench", cx - 1, cy - 3)
				kit.put(cv, "bench", cx - 1, cy + 3)
				kit.put(cv, "dining_table", cx - 1, cy)
			elif feature == 1 and lw >= 20 and lh >= 20:
				var cx2 := 2 if rng.randf() < 0.5 else lw - 14
				var cy2 := 2 if rng.randf() < 0.5 else lh - 14
				ops.append({"op": "place", "kind": "court", "at": [cx2, cy2]})
				ops.append({"op": "place", "kind": "hoop", "at": [cx2 + 5, cy2 + 1]})
			else:
				# a playground: swings, a slide, a bench for the parents
				var qx := 3 if rng.randf() < 0.5 else lw - 8
				var qy := 3 if rng.randf() < 0.5 else lh - 8
				kit.put(cv, "swing_set", qx, qy)
				kit.put(cv, "slide", qx + 4, qy)
				kit.put(cv, "bench", qx, qy + 3)
				kit.put(cv, "bin", qx + 3, qy + 3)
			for k in rng.randi_range(3, 5):
				kit.scatter(cv, rng, "bench" if rng.randf() < 0.5 else "dining_table", 1, lw - 3, 1, lh - 2)
			ops.append({"op": "trees", "rect": all, "n": {"r": [10, 16]}, "on": ["GRASS"], "gap": 3})
			for k in rng.randi_range(2, 4):
				kit.scatter(cv, rng, "bush", 0, lw - 1, 0, lh - 1)
		"plaza":
			cv.fill(Rect2i(0, 0, lw, lh), "SIDEWALK")
			var n := mini(3, (lw - 2) / 5)
			for i in n:
				var sx := 1 + i * 5
				var sy := 2 if String(spec.front) == "N" else lh - 4
				kit.put(cv, "market_stall", sx, sy)
				kit.put(cv, "crate", sx + 3, sy, rng.randf() < 0.7)
				kit.put(cv, "box", sx + 3, sy + 1, rng.randf() < 0.5)
			for k in 3:
				kit.scatter(cv, rng, ["bench", "bin"][rng.randi() % 2], 1, lw - 3, 1, lh - 2)
			ops.append({"op": "trees", "rect": all, "n": 2, "on": ["SIDEWALK"], "gap": 4})
		"field":
			var y := 1
			while y + 2 <= lh - 1:
				cv.fill(Rect2i(1, y, lw - 2, 2), "SOIL")
				y += 3
			ops.append({"op": "trees", "rect": all, "n": {"r": [0, 2]}, "on": ["GRASS"], "gap": 4})
		"woods":
			ops.append({"op": "trees", "rect": all, "n": maxi(3, lw * lh / 14), "on": ["GRASS"], "gap": 2})
			for k in rng.randi_range(2, 4):
				kit.scatter(cv, rng, "bush", 0, lw - 1, 0, lh - 1)
		"meadow":
			ops.append({"op": "trees", "rect": all, "n": {"r": [2, 4]}, "on": ["GRASS"], "gap": 4})
			for k in rng.randi_range(2, 4):
				kit.scatter(cv, rng, "bush", 0, lw - 1, 0, lh - 1)
			ops.append({"op": "patch", "rect": all, "t": "DIRT", "n": 2, "r": [1.5, 3]})
	if not ops.is_empty():
		cv.run({"ops": ops})
