## The DRESSING of the town (WORLD3, "add more life to the world"): the things that say people lived here and the fall came. Cosmetic, seeded and cheap: a picture and nothing more. Everything is
## a kit object of tools/make_town_life.py's sheet (one texture, so a street of them is one batch), NONE of them blocks anyone (the dead and the people walk over it; the bins, benches and bushes
## that do are the kit's old ones, which the yards already had) and none changes a rule: every dice roll here is from a generator of its own (seeded from the town's seed), never the town's, never
## the sim's, so the town it dresses is the town it would have been, and the dead stand where they stood.
##
##   `step(g, i)`    the streets and the open ground (TownGen's street furniture phase, after the cars, lamps and litter): by district, along the sidewalks and in the road: rubbish, signs,
##                   post boxes, shopping trolleys, suitcases and rucksacks, cones, potholes, cracks, puddles, graffiti, flyers, blood, a few of the fallen; makeshift camps (tents, a fire, chairs,
##                   pallets); a body by a few of the cars.
##   `yard(...)`     what a lot has beyond the kit's own yard (BuildingGen, after the yard): by the kind of building and the yard's state: washing lines, a trampoline, a barbecue, gnomes, toys, a
##                   sandpit, a paddling pool, flower beds, a vegetable patch, weeds, a wood pile, a rain barrel, a kennel, deck chairs; at the door pots, a note; at a shop trolleys and flyers; at the
##                   works tyres and pallets; at a farm a wood pile, a barrow, a barrel.
extends RefCounted

const TownArt := preload("res://scripts/town/town_art.gd")

const STEPS := 3

## [kind, weight] for the pavement and for the road.
const WALK := [["flyers", 3.0], ["bin_bag", 2.0], ["suitcase", 1.0], ["backpack", 1.0], ["cart", 1.0], ["postbox", 0.5], ["news_box", 0.7], ["parking_meter", 0.7], ["stop_sign", 0.35],
	["bus_sign", 0.35], ["debris", 2.0], ["puddle", 1.5], ["graffiti", 0.8], ["pave_crack", 2.0], ["body", 0.5], ["blood_pool", 0.7], ["pram", 0.25], ["flowers", 0.2], ["rubble", 1.0]]
const ROAD := [["cone", 3.0], ["barrier_fallen", 0.8], ["debris", 3.0], ["tire", 1.2], ["pothole", 3.0], ["pave_crack", 3.0], ["puddle", 3.0], ["graffiti", 0.8], ["blood_smear", 1.5], ["body", 1.0],
	["blood_pool", 1.0], ["suitcase", 0.8], ["flyers", 1.5], ["cart_fallen", 0.8], ["bin_bag", 0.8], ["blood_prints", 0.6]]
## How many things a block gets, by district, and how the kinds are leaned: {kind: multiplier}.
const PER_BLOCK := {"main": 16, "oldtown": 11, "industrial": 10, "civic": 8, "suburb": 6, "park": 5, "edge": 3}
const LEAN := {
	"main": {"postbox": 2.0, "news_box": 2.5, "parking_meter": 3.0, "stop_sign": 2.0, "bus_sign": 2.5, "cart": 2.0, "graffiti": 1.5},
	"oldtown": {"graffiti": 3.0, "flyers": 1.5, "bin_bag": 1.5, "news_box": 1.5, "pram": 2.0},
	"industrial": {"tire": 3.0, "debris": 1.6, "graffiti": 2.5, "barrier_fallen": 2.0, "cone": 1.6, "rubble": 2.0},
	"civic": {"flowers": 4.0, "bus_sign": 2.0, "flyers": 1.5, "stop_sign": 1.5},
	"suburb": {"flowers": 2.5, "pram": 2.0, "stop_sign": 1.5, "puddle": 1.3},
	"park": {"flowers": 3.0, "bin_bag": 1.5},
}
## No body or blood within this many tiles of the entry (the opening is meant to be quiet), and no thing of any kind within ENTRY_R of it.
const QUIET_R := 22.0
const ENTRY_R := 7.0


static func step(g, i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(g.seed_value) * 40503 + 9100 + i * 131
	match i:
		0:
			_walks(g, rng)
		1:
			_roads(g, rng)
		_:
			_camps(g, rng)
			_by_cars(g, rng)


## What is taken: a byte for each tile, 1 where the world has something (solid, a wall) or a thing of the kit stands. Made once.
static func _occ(g) -> PackedByteArray:
	if g.has_meta("life_occ"):
		return g.get_meta("life_occ")
	var W: int = g._size
	var occ: PackedByteArray = (g._solid as PackedByteArray).duplicate()
	for o in g._objects:
		var tx := roundi(float(o.cx) - float(o.w) / 2.0)
		var ty := roundi(float(o.cy) - float(o.h) / 2.0)
		for yy in int(o.h):
			for xx in int(o.w):
				var x := tx + xx
				var y := ty + yy
				if x >= 0 and y >= 0 and x < W and y < W:
					occ[y * W + x] = 1
	g.set_meta("life_occ", occ)
	return occ


static func _pick(list: Array, lean: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for e in list:
		total += float(e[1]) * float(lean.get(String(e[0]), 1.0))
	var at := rng.randf() * total
	for e in list:
		at -= float(e[1]) * float(lean.get(String(e[0]), 1.0))
		if at < 0.0:
			return String(e[0])
	return String(list[list.size() - 1][0])


static func _entry(g) -> Vector2:
	var arr: Dictionary = g._layout.arrival
	return Vector2(arr.pos) if not arr.is_empty() else Vector2(-1000.0, -1000.0)


## Puts `kind` with its top left at (tx, ty) when every tile of its footprint is of one of `terr`, free (not taken, not solid) and clear of the arrival's rings. The kit object, or null.
static func _put(g, occ: PackedByteArray, rng: RandomNumberGenerator, kind: String, tx: int, ty: int, terr: Array, variant: int = -1):
	var W: int = g._size
	var fp: Vector2i = g._street_cv.tiles_of(kind)
	if tx < g.EDGE + 1 or ty < g.EDGE + 1 or tx + fp.x >= W - g.EDGE - 1 or ty + fp.y >= W - g.EDGE - 1:
		return null
	var here := Vector2(float(tx) + float(fp.x) * 0.5, float(ty) + float(fp.y) * 0.5)
	var entry := _entry(g)
	if here.distance_to(entry) < ENTRY_R:
		return null
	if kind in ["body", "blood_smear", "blood_pool", "blood_prints"] and here.distance_to(entry) < QUIET_R:
		return null
	for yy in fp.y:
		for xx in fp.x:
			var i := (ty + yy) * W + tx + xx
			if occ[i] != 0 or not (int(g._terrain[i]) in terr):
				return null
	if g._in_clear(Vector2i(tx, ty), 2):
		return null
	var obj = g._street_cv._decor(kind, tx, ty, 0.0, 0.0)
	if obj == null:
		return null
	g._kit.kit_set(obj, g._street_cv.props[kind], rng)
	if variant >= 0:
		obj["variant"] = variant % TownArt.variants_of(String(obj.kit))
	obj["solid"] = false
	g._objects.append(obj)
	g._street_objs += 1
	for yy in fp.y:
		for xx in fp.x:
			occ[(ty + yy) * W + tx + xx] = 1
	return obj


## The things of the pavement: round every block, by its district.
static func _walks(g, rng: RandomNumberGenerator) -> void:
	var occ := _occ(g)
	var terr := [int(g._tids.SIDEWALK), int(g._tids.CONCRETE)]
	for b in g._layout.blocks:
		var r: Rect2i = b.rect
		var d := String(b.district)
		var n := roundi(float(int(PER_BLOCK.get(d, 6))) * float(r.size.x + r.size.y) / 70.0)
		var lean: Dictionary = LEAN.get(d, {})
		for k in n:
			var tx := 0
			var ty := 0
			# the sidewalk ring of the block
			if rng.randf() < 0.5:
				tx = r.position.x + rng.randi_range(1, maxi(1, r.size.x - 3))
				ty = r.position.y if rng.randf() < 0.5 else r.end.y - 1
			else:
				ty = r.position.y + rng.randi_range(1, maxi(1, r.size.y - 3))
				tx = r.position.x if rng.randf() < 0.5 else r.end.x - 1
			_put(g, occ, rng, _pick(WALK, lean, rng), tx, ty, terr)


## The things of the road: on the asphalt, by how much road there is.
static func _roads(g, rng: RandomNumberGenerator) -> void:
	var occ := _occ(g)
	var terr := [int(g._tids.ASPHALT)]
	var roads: Array = g._layout.roads
	if roads.is_empty():
		return
	var total := 0.0
	for rd in roads:
		var rr: Rect2i = rd.rect
		total += float(rr.size.x * rr.size.y)
	var want := roundi(total / 40.0)
	var guard := want * 6
	var placed := 0
	while placed < want and guard > 0:
		guard -= 1
		var rd: Dictionary = roads[rng.randi() % roads.size()]
		var rr: Rect2i = rd.rect
		var tx := rr.position.x + rng.randi_range(0, maxi(0, rr.size.x - 1))
		var ty := rr.position.y + rng.randi_range(0, maxi(0, rr.size.y - 1))
		var lean := {}
		if String(rd.kind) == "alley":
			lean = {"graffiti": 3.0, "bin_bag": 2.0, "debris": 1.5, "body": 1.5}
		elif String(rd.kind) == "avenue":
			lean = {"cone": 1.3, "barrier_fallen": 1.5, "suitcase": 1.5}
		if _put(g, occ, rng, _pick(ROAD, lean, rng), tx, ty, terr) != null:
			placed += 1


## A few camps of people who lived in the open: tents, a fire ring, chairs, pallets, a tarp and a trolley of what they had, on open ground (a park, a pocket of grass, a yard, a square).
static func _camps(g, rng: RandomNumberGenerator) -> void:
	var occ := _occ(g)
	var W: int = g._size
	var terr := [int(g._tids.GRASS), int(g._tids.DIRT), int(g._tids.SIDEWALK), int(g._tids.CONCRETE)]
	var want := 2 if W < 128 else 4
	var made := 0
	var entry := _entry(g)
	var tries := 260
	while made < want and tries > 0:
		tries -= 1
		var x0 := rng.randi_range(g.EDGE + 6, W - g.EDGE - 14)
		var y0 := rng.randi_range(g.EDGE + 6, W - g.EDGE - 12)
		if Vector2(float(x0), float(y0)).distance_to(entry) < 40.0:
			continue
		# (a quick look at the middle and the corners first: most of the town is not open ground)
		if occ[(y0 + 3) * W + x0 + 5] != 0 or occ[y0 * W + x0] != 0 or occ[(y0 + 5) * W + x0 + 9] != 0 or occ[y0 * W + x0 + 9] != 0 or occ[(y0 + 5) * W + x0] != 0:
			continue
		# an open 10 x 6 of ground
		var ok := true
		for yy in 6:
			for xx in 10:
				var i := (y0 + yy) * W + x0 + xx
				if occ[i] != 0 or not (int(g._terrain[i]) in terr):
					ok = false
					break
			if not ok:
				break
		if not ok or g._in_clear(Vector2i(x0 + 5, y0 + 3), 8):
			continue
		var tv := rng.randi() % 3
		_put(g, occ, rng, "camp_tent", x0, y0, terr, tv)
		if rng.randf() < 0.7:
			_put(g, occ, rng, "camp_tent", x0 + 4, y0, terr, (tv + 1) % 3)
		_put(g, occ, rng, "campfire", x0 + 2, y0 + 3, terr, rng.randi() % 2)
		_put(g, occ, rng, "camp_chair", x0 + 1, y0 + 3, terr)
		_put(g, occ, rng, "camp_chair", x0 + 4, y0 + 4, terr)
		_put(g, occ, rng, "pallet", x0 + 6, y0 + 3, terr, rng.randi() % 2)
		if rng.randf() < 0.6:
			_put(g, occ, rng, "tarp_lean", x0 + 7, y0, terr, rng.randi() % 2)
		_put(g, occ, rng, "bin_bag", x0 + 3, y0 + 5, terr, rng.randi() % 2)
		if rng.randf() < 0.5:
			_put(g, occ, rng, "cart", x0 + 8, y0 + 4, terr)
		_put(g, occ, rng, "backpack", x0, y0 + 3, terr, rng.randi() % 2)
		made += 1


## Somebody who did not get away, beside some of the parked cars.
static func _by_cars(g, rng: RandomNumberGenerator) -> void:
	var occ := _occ(g)
	var terr := [int(g._tids.ASPHALT), int(g._tids.SIDEWALK)]
	var cars: Array = []
	for o in g._objects:
		if String(o.get("kit", "")) == "car":
			cars.append(o)
	if cars.is_empty():
		return
	var n := 0
	var want := mini(cars.size() / 4, 14)
	var tries := cars.size() * 3
	while n < want and tries > 0:
		tries -= 1
		var o: Dictionary = cars[rng.randi() % cars.size()]
		var w := int(o.w)
		var h := int(o.h)
		var left := roundi(float(o.cx) - float(w) / 2.0)
		var top := roundi(float(o.cy) - float(h) / 2.0)
		var side := -1 if rng.randf() < 0.5 else 1
		var bx := 0
		var by := 0
		if w > h:
			bx = left + rng.randi_range(0, maxi(0, w - 3))
			by = top - 1 if side < 0 else top + h
		else:
			bx = left - 2 if side < 0 else left + w
			by = top + rng.randi_range(0, maxi(0, h - 2))
		var body = _put(g, occ, rng, "body", bx, by, terr, rng.randi() % 5)
		if body != null:
			n += 1
			if rng.randf() < 0.6:
				_put(g, occ, rng, "blood_pool", bx + 2, by, terr, rng.randi() % 2)
			if rng.randf() < 0.5:
				_put(g, occ, rng, "suitcase", bx - 1, by + (1 if side > 0 else -1), terr, rng.randi() % 3)


# ================================================================================== a lot ==

const YARD_TERR := ["GRASS", "SOIL", "DIRT", "YARD", "SIDEWALK", "CONCRETE"]


## Free ground for a `fw` x `fh` thing with its top left at (tx, ty) on the canvas of a lot: inside it, no solid, no kept tile (the path), nothing of the dressing there, on the ground of a yard.
static func _free(cv, occ: Dictionary, tids: Dictionary, tx: int, ty: int, fw: int, fh: int) -> bool:
	if tx < 0 or ty < 0 or tx + fw > cv.W or ty + fh > cv.H:
		return false
	for yy in fh:
		for xx in fw:
			var i: int = (ty + yy) * cv.W + tx + xx
			if cv.solid[i] != 0 or cv.keep[i] != 0 or occ.has(i):
				return false
			var t: int = cv.terrain[i]
			var ok := false
			for n in YARD_TERR:
				if t == int(tids.get(n, -1)):
					ok = true
			if not ok:
				return false
	return true


## `kind` somewhere in the rows y0 to y1 and columns x0 to x1 of the lot (a few tries). True when it was put.
static func _drop(cv, occ: Dictionary, tids: Dictionary, rng: RandomNumberGenerator, kind: String, x0: int, x1: int, y0: int, y1: int) -> bool:
	if y1 < y0 or x1 < x0:
		return false
	var fp: Vector2i = cv.tiles_of(kind)
	for t in 10:
		var tx := rng.randi_range(x0, maxi(x0, x1 - fp.x + 1))
		var ty := rng.randi_range(y0, maxi(y0, y1 - fp.y + 1))
		if not _free(cv, occ, tids, tx, ty, fp.x, fp.y):
			continue
		var o = cv._decor(kind, tx, ty, 0.0, 0.0)
		if o == null:
			return false
		for yy in fp.y:
			for xx in fp.x:
				occ[(ty + yy) * cv.W + tx + xx] = true
		return true
	return false


## What a lot has besides the kit's own yard. `spec` the lot's spec (kind, district, yard, boarded, barricade, seed), `bb` the building's box (lot coordinates), `door` the tile outside the front door.
static func yard(cv, tids: Dictionary, spec: Dictionary, bb: Rect2i, front: String, door: Vector2i, home: bool, clear: bool) -> void:
	if clear:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed) * 977 + 3
	var occ := {}
	var lw: int = cv.W
	var lh: int = cv.H
	var kind := String(spec.kind)
	var district := String(spec.district)
	var yard_type := String(spec.get("yard", "lawn"))
	var south := front == "S"
	var dir := 1 if south else -1
	# the front yard: between the street and the walls; the back: the other side of the house
	var fy0 := bb.end.y if south else 0
	var fy1 := (lh - 1) if south else (bb.position.y - 1)
	var by0 := 0 if south else bb.end.y
	var by1 := (bb.position.y - 1) if south else (lh - 1)
	var front_rows := fy1 - fy0 + 1
	var back_rows := by1 - by0 + 1
	var wild := yard_type == "overgrown"
	var garden := yard_type == "garden"
	if home:
		# at the door: pots beside the step, a note on a door that somebody boarded
		if door.y >= 0 and door.y < lh and front_rows >= 1:
			for bx in [door.x - 2, door.x + 3]:
				if rng.randf() < 0.28 and _free(cv, occ, tids, bx, door.y, 1, 1):
					cv._decor("plant_pot", bx, door.y, 0.0, 0.0)
					occ[door.y * lw + bx] = true
			var nprob := 0.65 if (bool(spec.get("boarded", false)) or bool(spec.get("barricade", false))) else 0.1
			if rng.randf() < nprob and door.x + 1 < lw:
				var ny := door.y + (dir if front_rows >= 2 else 0)
				if ny >= 0 and ny < lh:
					cv._decor("note", door.x + 1, ny, 0.0, 0.0)
		# the front yard
		if front_rows >= 2:
			if garden or rng.randf() < 0.3:
				_drop(cv, occ, tids, rng, "flower_bed", 1, lw - 3, fy0, fy1)
			if rng.randf() < 0.1:
				_drop(cv, occ, tids, rng, "gnome", 1, lw - 2, fy0, fy1)
			if rng.randf() < 0.08:
				_drop(cv, occ, tids, rng, "toys", 1, lw - 2, fy0, fy1)
			if rng.randf() < 0.05:
				_drop(cv, occ, tids, rng, "birdbath", 1, lw - 2, fy0, fy1)
			if wild:
				for k in rng.randi_range(2, 5):
					_drop(cv, occ, tids, rng, "weeds", 0, lw - 1, fy0, fy1)
		# the back and the sides
		if back_rows >= 2:
			if rng.randf() < 0.16:
				_drop(cv, occ, tids, rng, "laundry", 1, lw - 4, by0, by1)
			if back_rows >= 3 and rng.randf() < 0.06:
				_drop(cv, occ, tids, rng, "trampoline", 1, lw - 3, by0, by1)
			if rng.randf() < 0.12:
				_drop(cv, occ, tids, rng, "bbq", 1, lw - 2, by0, by1)
			if rng.randf() < 0.18:
				_drop(cv, occ, tids, rng, "toys", 1, lw - 2, by0, by1)
				if rng.randf() < 0.5:
					_drop(cv, occ, tids, rng, "toys", 1, lw - 2, by0, by1)
			if back_rows >= 3 and rng.randf() < 0.05:
				_drop(cv, occ, tids, rng, "sandpit", 1, lw - 3, by0, by1)
			if back_rows >= 3 and rng.randf() < 0.05:
				_drop(cv, occ, tids, rng, "paddling_pool", 1, lw - 3, by0, by1)
			if garden or rng.randf() < 0.2:
				_drop(cv, occ, tids, rng, "veg_patch", 1, lw - 4, by0, by1)
			if rng.randf() < 0.22:
				_drop(cv, occ, tids, rng, "flower_bed", 1, lw - 3, by0, by1)
			if rng.randf() < 0.08:
				_drop(cv, occ, tids, rng, "woodpile", 1, lw - 3, by0, by1)
			if rng.randf() < 0.1:
				_drop(cv, occ, tids, rng, "rain_barrel", 1, lw - 2, by0, by1)
			if rng.randf() < 0.06:
				_drop(cv, occ, tids, rng, "barrow", 1, lw - 2, by0, by1)
			if rng.randf() < 0.09:
				_drop(cv, occ, tids, rng, "deck_chair", 1, lw - 2, by0, by1)
				_drop(cv, occ, tids, rng, "deck_chair", 1, lw - 2, by0, by1)
			if back_rows >= 3 and rng.randf() < 0.05:
				_drop(cv, occ, tids, rng, "picnic_table", 1, lw - 4, by0, by1)
			if rng.randf() < 0.06:
				_drop(cv, occ, tids, rng, "kennel", 1, lw - 2, by0, by1)
			if rng.randf() < 0.06:
				_drop(cv, occ, tids, rng, "compost_heap", 1, lw - 2, by0, by1)
			if wild:
				for k in rng.randi_range(3, 7):
					_drop(cv, occ, tids, rng, "weeds", 0, lw - 1, by0, by1)
			if rng.randf() < 0.07:
				_drop(cv, occ, tids, rng, "gnome", 1, lw - 2, by0, by1)
		return
	# a shop, an office, a works, a public building: what lies in front of it
	match district:
		"main", "oldtown", "civic":
			for k in 2:
				if front_rows >= 1 and rng.randf() < 0.35:
					_drop(cv, occ, tids, rng, "flyers", 0, lw - 1, fy0, fy1)
			if rng.randf() < 0.18 and kind in ["shop", "supermarket", "cornershop", "rowshop", "strip", "kiosk", "diner", "cafe"]:
				_drop(cv, occ, tids, rng, "cart" if rng.randf() < 0.6 else "cart_fallen", 0, lw - 2, fy0, fy1)
			if rng.randf() < 0.1:
				_drop(cv, occ, tids, rng, "graffiti", 0, lw - 2, fy0, fy1)
			if rng.randf() < 0.07:
				_drop(cv, occ, tids, rng, "bin_bag", 0, lw - 1, fy0, fy1)
			if rng.randf() < 0.05:
				_drop(cv, occ, tids, rng, "body", 0, lw - 2, fy0, fy1)
		"industrial":
			for k in rng.randi_range(1, 4):
				_drop(cv, occ, tids, rng, ["tire", "pallet", "cone", "jerrycan", "debris", "barrier_fallen"][rng.randi() % 6], 0, lw - 2, 0, lh - 1)
		"edge":
			for k in rng.randi_range(1, 3):
				_drop(cv, occ, tids, rng, ["woodpile", "barrow", "rain_barrel", "pallet", "weeds", "tire"][rng.randi() % 6], 1, lw - 3, 0, lh - 1)
