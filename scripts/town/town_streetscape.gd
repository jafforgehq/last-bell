## The things of the streets and of the town's edge (One House, TOWNGEN): the solid ring of the world with a row of trees, the roadblocks where a street runs out of the town, parked cars
## along the kerbs (more on the main avenue) and here and there a wreck across a lane, street lamps and hydrants along the sidewalks, litter on the paving. The cars, wrecks, lamps,
## hydrants and litter are the art kit's (`kit` fields: scripts/town/town_kit.gd). `run(g)` works on a TownGen (scripts/town/town_gen.gd: its terrain, solid grid, objects, trees and the
## street canvas `_street_cv`), after every lot is stamped. Never on the start lot (the generator's `_clear_rect`), and no car within reach of the start's spawn roads.
extends RefCounted

const EDGE := 2
const AVENUE_W := 6
## How far round the entry no parked car or wreck of the streets stands (tiles): the stretch of the walk in that is left clear.
const ENTRY_CLEAR := 14.0
## Where the entry's wreck, car and painted chevrons were put when the avatar began 4.5 tiles in from the edge: they are put as far ahead of her now (`_entry` shifts them by how far she is in).
const ENTRY_WAS_IN := 4


## The pieces of `run`, for the stepped build (`TownGen.step` does one a step).
const Dressing := preload("res://scripts/town/town_dressing.gd")
const STEPS := 5 + Dressing.STEPS


static func run(g) -> void:
	for i in STEPS:
		step(g, i)


## The piece `i` (0 to STEPS - 1) of `run`: in this order the border, the road ends, the cars, the lamps, the litter, then WORLD3's dressing (the pavements, the roads, the camps and the fallen).
static func step(g, i: int) -> void:
	match i:
		0:
			_border(g)
		1:
			_road_ends(g)
		2:
			_cars(g)
		3:
			_lamps(g)
		4:
			_litter(g)
		_:
			Dressing.step(g, i - 5)


static func _border(g) -> void:
	var W: int = g._size
	var H: int = g._size
	var rng: RandomNumberGenerator = g._rng
	for y in H:
		for x in W:
			if x < EDGE or y < EDGE or x >= W - EDGE or y >= H - EDGE:
				var i := y * W + x
				g._terrain[i] = int(g._tids.GRASS)
				g._solid[i] = 1
	# a row of trees all round, a few tiles apart, in and out a little (the woods of the world's edge)
	for k in range(0, W, 5):
		for side in 4:
			var jitter := rng.randi_range(0, 2)
			var tx := 0
			var ty := 0
			match side:
				0:
					tx = k + rng.randi_range(0, 1)
					ty = jitter
				1:
					tx = k + rng.randi_range(0, 1)
					ty = H - 1 - jitter
				2:
					tx = jitter
					ty = k + rng.randi_range(0, 1)
				_:
					tx = W - 1 - jitter
					ty = k + rng.randi_range(0, 1)
			if rng.randf() < 0.9 and tx >= 0 and ty >= 0 and tx < W and ty < H:
				g._add_tree(tx, ty, false)


## A concrete barrier and a wreck where a street leaves the town.
static func _road_ends(g) -> void:
	var W: int = g._size
	var H: int = g._size
	var rng: RandomNumberGenerator = g._rng
	var cv = g._street_cv
	var arrival: Dictionary = g._layout.arrival
	for rd in g._layout.roads:
		if not bool(rd.through):
			continue
		var r: Rect2i = rd.rect
		var horiz := String(rd.dir) == "h"
		# (a street that runs out at one border only has the block there: it ends at the avenue or at the town's blocks at the other)
		var ends: Array = []
		if horiz:
			if r.position.x <= EDGE:
				ends.append([EDGE, true])
			if r.end.x >= W - EDGE:
				ends.append([W - EDGE - 1, false])
		else:
			if r.position.y <= EDGE:
				ends.append([EDGE, true])
			if r.end.y >= H - EDGE:
				ends.append([H - EDGE - 1, false])
		for e in ends:
			# ARRIVAL: the end of the avenue the avatar comes in at has no roadblock (the way in from the forest): `_entry` puts a wreck, a car and a sign on it
			if not arrival.is_empty() and int(rd.id) == int(g._layout.avenue) and bool(e[1]) != bool(arrival.east):
				continue
			var at: int = int(e[0])
			if horiz:
				for y0 in [r.position.y, r.end.y - 5]:
					var obj = cv._decor("blocks_v", at, y0, 0.0, 0.0)
					if obj != null:
						obj["solid"] = true
						g._objects.append(obj)
						g._street_objs += 1
					for yy in 5:
						g._solid[(y0 + yy) * W + at] = 1
				var wx := at + 3 if bool(e[1]) else at - 8
				_put_car(g, "car_h", wx, r.position.y + rng.randi_range(0, r.size.y - 2))
			else:
				for x0 in [r.position.x, r.end.x - 3]:
					var obj2 = cv._decor("sandbags", x0, at, 0.0, 0.0)
					if obj2 != null:
						obj2["solid"] = true
						g._objects.append(obj2)
						g._street_objs += 1
					for xx in 3:
						g._solid[at * W + x0 + xx] = 1
				var wy := at + 3 if bool(e[1]) else at - 8
				_put_car(g, "car_v", r.position.x + rng.randi_range(0, r.size.x - 2), wy)
	if not arrival.is_empty():
		_entry(g, arrival)


## ARRIVAL: the way in. The avenue's end the avatar stands at has no roadblock: a wreck across the lane nearer the north side, a car in the other lane a few tiles on (so that the way in
## winds between them and stays at least three tiles wide) and, for the road sign (the kit has none), three double chevrons painted on the lane the avatar stands in, pointing into the town
## (the kit's `marker_enter`). `g._entry_arrows` are their middles (tiles), `g._entry_sign` the middle one, (-1, -1) when none stands.
static func _entry(g, arrival: Dictionary) -> void:
	var rng: RandomNumberGenerator = g._art_rng
	var W: int = g._size
	var east: bool = bool(arrival.east)
	var ay: int = int(arrival.ay)
	var wreck_fp: Vector2i = g._street_cv.tiles_of("car_wreck")
	var car_fp: Vector2i = g._street_cv.tiles_of("car_h")
	# (EARLY: she begins `inward` tiles in from the edge, on the forest lane's end: the wreck, the car and the chevrons are as far ahead of her as they always were)
	var inward: int = (W - 1 - int(Vector2(arrival.pos).x)) if east else int(Vector2(arrival.pos).x)
	var shift: int = inward - ENTRY_WAS_IN
	_entry_cover(g, arrival)
	var wx := EDGE + 8 + shift + rng.randi_range(0, 2)
	var cx := EDGE + 16 + shift + rng.randi_range(0, 3)
	for wy in [ay, ay + 1]:
		if _put_wreck(g, true, W - wx - wreck_fp.x if east else wx, wy):
			break
	_put_car(g, "car_h", W - cx - car_fp.x if east else cx, ay + 4)
	# the sign: three double chevrons painted on the avatar's lane, pointing into the town (the kit's `marker_enter`)
	g._entry_arrows = []
	for ax0 in [8, 12, 16]:
		var ax: int = ax0 + shift
		var tx: int = W - 1 - ax if east else ax
		var o = g._street_cv._decor("marker_enter", tx, ay + 3, 0.0, 0.0)
		if o == null:
			continue
		g._kit.kit_set(o, g._street_cv.props["marker_enter"], rng)
		o["facing"] = "w" if east else "e"
		o["solid"] = false
		g._objects.append(o)
		g._street_objs += 1
		g._entry_arrows.append(Vector2(float(tx) + 0.5, float(ay) + 3.5))
	g._entry_sign = g._entry_arrows[g._entry_arrows.size() >> 1] if not g._entry_arrows.is_empty() else Vector2(-1.0, -1.0)


## EARLY4, COVER FOR THE OPENING. CLEAR3 took every tall thing out of the entry's strip (the wreck, the car, the parked cars: they stand in the field of the candidate beside it), so the scripted opening's
## walker (scripts/town/opening.gd) came out of nothing on a bare road. A LOW piece stands there instead, which the fields leave (`prop_heights.json`: sandbags are low, a shot goes over them): two
## lengths of sandbags end to end along each KERB of the avenue (its first row and its last: the way in runs to the first house's door on one side or the other, the nearest candidate is the best one in
## seven runs of eight and the other candidate in the eighth, so both kerbs have them and the opening takes the one near its way), the middle of them about `COVER_AHEAD` tiles ahead of the avatar
## (the walker's `walker_ahead` is 10, the trigger 12: the place the car was; the opening's walker may not be put nearer than 6 tiles to the door, so the first length is the nearer one). The four
## middle rows of the avenue stay free. The opening takes a length as the thing the walker steps out from (`cover_big` false). Returns how many lengths stand (0: the kerbs are taken).
const COVER_AHEAD := 16
const COVER_LENGTHS := 2


static func _entry_cover(g, arrival: Dictionary) -> int:
	var props: Dictionary = g._street_cv.props
	if not props.has("sandbags"):
		return 0
	var W: int = g._size
	var east: bool = bool(arrival.east)
	var ay: int = int(arrival.ay)
	var fp: Vector2i = g._street_cv.tiles_of("sandbags")
	var start_x: int = floori(float(Vector2(arrival.pos).x))
	var road := int(g._tids.ASPHALT)
	var placed := 0
	for ty in [ay, ay + 5]:
		for k in COVER_LENGTHS:
			var tx: int = (start_x - COVER_AHEAD - fp.x * (k + 1) + 1) if east else (start_x + COVER_AHEAD + fp.x * k)
			var free := tx > EDGE and tx + fp.x < W - EDGE
			for xx in fp.x:
				var i: int = ty * W + tx + xx
				if not free or g._solid[i] != 0 or g._terrain[i] != road:
					free = false
			if not free:
				continue
			var obj = g._street_cv._decor("sandbags", tx, ty, 0.0, 0.0)
			if obj == null:
				continue
			obj["solid"] = true
			g._objects.append(obj)
			for xx in fp.x:
				g._solid[ty * W + tx + xx] = 1
			g._street_objs += 1
			placed += 1
	return placed


## Puts a car on the asphalt at a top left tile when its tiles are free road. True when it stands.
static func _put_car(g, kind: String, tx: int, ty: int) -> bool:
	var W: int = g._size
	var H: int = g._size
	var fp: Vector2i = g._street_cv.tiles_of(kind)
	if tx < EDGE + 1 or ty < EDGE + 1 or tx + fp.x > W - EDGE - 1 or ty + fp.y > H - EDGE - 1:
		return false
	var road := int(g._tids.ASPHALT)
	for yy in fp.y:
		for xx in fp.x:
			var i := (ty + yy) * W + tx + xx
			if g._solid[i] != 0 or g._terrain[i] != road:
				return false
	var obj = g._street_cv._decor(kind, tx, ty, 0.0, 0.0)
	if obj == null:
		return false
	g._kit.kit_set(obj, g._street_cv.props[kind], g._art_rng)
	obj["solid"] = true
	g._objects.append(obj)
	for yy in fp.y:
		for xx in fp.x:
			g._solid[(ty + yy) * W + tx + xx] = 1
	g._street_objs += 1
	return true


## A wreck across a lane: 4 x 3 (the picture is turned, so a wreck along y is told its footprint the other way round), a tile of road kept clear all round it so that the way past is open.
static func _put_wreck(g, horiz: bool, tx: int, ty: int) -> bool:
	var W: int = g._size
	var H: int = g._size
	var fp: Vector2i = g._street_cv.tiles_of("car_wreck")
	if not horiz:
		fp = Vector2i(fp.y, fp.x)
	if tx < EDGE + 1 or ty < EDGE + 1 or tx + fp.x > W - EDGE - 1 or ty + fp.y > H - EDGE - 1:
		return false
	var road := int(g._tids.ASPHALT)
	for yy in range(-1, fp.y + 1):
		for xx in range(-1, fp.x + 1):
			var i := (ty + yy) * W + tx + xx
			var inside := yy >= 0 and yy < fp.y and xx >= 0 and xx < fp.x
			if i < 0 or i >= W * H or g._solid[i] != 0 or (inside and g._terrain[i] != road):
				return false
	var obj = g._street_cv._decor("car_wreck", tx, ty, 0.0, 0.0)
	if obj == null:
		return false
	if not horiz:
		obj["w"] = float(fp.x)
		obj["h"] = float(fp.y)
		obj["cx"] = float(tx) + float(fp.x) / 2.0
		obj["cy"] = float(ty) + float(fp.y) / 2.0
		obj["turn"] = 1
	g._kit.kit_set(obj, g._street_cv.props["car_wreck"], g._art_rng)
	obj["solid"] = true
	g._objects.append(obj)
	for yy in fp.y:
		for xx in fp.x:
			g._solid[(ty + yy) * W + tx + xx] = 1
	g._street_objs += 1
	return true


## Parked cars along the kerbs of the streets, clear of the junctions; the main avenue has the most; a few wrecks lie across the lanes.
static func _cars(g) -> void:
	var rng: RandomNumberGenerator = g._rng
	var roads: Array = g._layout.roads
	var total := int(g.opts.get("cars", 70))
	var wrecks := int(g.opts.get("wrecks", roundi(10.0 * float(g._size * g._size) / float(192 * 192))))
	var list: Array = []
	var weights: Array = []
	for rd in roads:
		if String(rd.kind) == "alley":
			continue
		var r: Rect2i = rd.rect
		var length := r.size.x if String(rd.dir) == "h" else r.size.y
		list.append(rd)
		weights.append(float(length) * (3.0 if String(rd.kind) == "avenue" else (0.4 if String(rd.kind) == "cul" else 1.0)))
	if list.is_empty():
		return
	var sum := 0.0
	for w in weights:
		sum += float(w)
	var placed := 0
	var wrecked := 0
	var tries := (total + wrecks) * 40
	# (the houses whose spawn roads are kept clear: the start house, and in a town with an arrival every candidate)
	var base_centers: Array = g._base_centers()
	# (ARRIVAL: the way in from the entry is left clear of parked cars and wrecks for ENTRY_CLEAR tiles: the walk in is not a hunt for a gap; the entry's own wreck and car are `_entry`'s. EARLY: the walk in is
	# shorter, so is the clear stretch: the first parked car is one the scripted opening's walker can step out from, 14 to 24 tiles along the way)
	var entry_pos := Vector2(-1000.0, -1000.0)
	if not g._layout.arrival.is_empty():
		entry_pos = Vector2(g._layout.arrival.pos)
	while (placed < total or wrecked < wrecks) and tries > 0:
		tries -= 1
		var at := rng.randf() * sum
		var pick := 0
		for i in weights.size():
			at -= float(weights[i])
			if at < 0.0:
				pick = i
				break
		var rd: Dictionary = list[pick]
		var r: Rect2i = rd.rect
		var horiz := String(rd.dir) == "h"
		var wreck := placed >= total or (wrecked < wrecks and rng.randf() < 0.12)
		var kind := "car_h" if horiz else "car_v"
		var tx := 0
		var ty := 0
		var wide := (r.size.y if horiz else r.size.x)
		if wreck:
			# 4 x 3: one lane and a half of a road of 4 (the way past is the rest)
			var off := rng.randi_range(0, maxi(0, wide - 3))
			if horiz:
				tx = r.position.x + rng.randi_range(3, maxi(3, r.size.x - 8))
				ty = r.position.y + off
			else:
				tx = r.position.x + off
				ty = r.position.y + rng.randi_range(3, maxi(3, r.size.y - 8))
		else:
			var lane := rng.randi_range(0, 1) * (wide - 2)
			if horiz:
				tx = r.position.x + rng.randi_range(2, maxi(2, r.size.x - 7))
				ty = r.position.y + lane
			else:
				tx = r.position.x + lane
				ty = r.position.y + rng.randi_range(2, maxi(2, r.size.y - 7))
		# not in a junction: no crossing street within two tiles of the car
		var clash := false
		for o in roads:
			if o.id == rd.id or String(o.dir) == String(rd.dir) or String(o.kind) == "alley":
				continue
			var q: Rect2i = o.rect
			var car := Rect2i(tx - 2, ty - 2, 9, 6) if horiz else Rect2i(tx - 2, ty - 2, 6, 9)
			if car.intersects(q):
				clash = true
		if clash:
			continue
		# no cars on the streets 34 to 62 tiles from the start house: the base's spawns want clear stretches of road there (scripts/town/base_layout.gd `_spawns`)
		if Vector2(tx, ty).distance_to(entry_pos) < ENTRY_CLEAR:
			continue
		var on_spawn_road := false
		for bc in base_centers:
			var sd: float = Vector2(tx, ty).distance_to(bc)
			if sd > 33.0 and sd < 63.0:
				on_spawn_road = true
		if on_spawn_road:
			continue
		if wreck:
			if wrecked < wrecks and _put_wreck(g, horiz, tx, ty):
				wrecked += 1
		elif _put_car(g, kind, tx, ty):
			placed += 1


## Street lamps (the arm leans out over the street) and hydrants along the sidewalks that border a street.
static func _lamps(g) -> void:
	var rng: RandomNumberGenerator = g._art_rng
	var W: int = g._size
	var road := int(g._tids.ASPHALT)
	var walk := int(g._tids.SIDEWALK)
	var props: Dictionary = g._street_cv.props
	for b in g._layout.blocks:
		var r: Rect2i = b.rect
		for side in 4:
			var cells: Array = []
			var arm := "n"
			match side:
				0:
					arm = "n"
					for x in range(r.position.x + 2, r.end.x - 2):
						cells.append([Vector2i(x, r.position.y), Vector2i(x, r.position.y - 1)])
				1:
					arm = "s"
					for x in range(r.position.x + 2, r.end.x - 2):
						cells.append([Vector2i(x, r.end.y - 1), Vector2i(x, r.end.y)])
				2:
					arm = "w"
					for y in range(r.position.y + 2, r.end.y - 2):
						cells.append([Vector2i(r.position.x, y), Vector2i(r.position.x - 1, y)])
				_:
					arm = "e"
					for y in range(r.position.y + 2, r.end.y - 2):
						cells.append([Vector2i(r.end.x - 1, y), Vector2i(r.end.x, y)])
			if cells.size() < 8:
				continue
			var n := cells.size() / 13
			if n == 0 and rng.randf() < 0.5:
				n = 1
			for k in n:
				var c: Array = cells[rng.randi_range(0, cells.size() - 1)]
				var t: Vector2i = c[0]
				var o: Vector2i = c[1]
				if o.x < 0 or o.y < 0 or o.x >= W or o.y >= W or g._terrain[o.y * W + o.x] != road:
					continue
				if g._terrain[t.y * W + t.x] != walk or g._in_clear(t, 0):
					continue
				var kind := "streetlamp" if rng.randf() < 0.8 else "hydrant"
				var obj = g._street_cv._decor(kind, t.x, t.y, 0.0, 0.0)
				if obj != null:
					g._kit.kit_set(obj, props[kind], rng)
					if kind == "streetlamp":
						obj["facing"] = arm
					else:
						obj["variant"] = 0 if rng.randf() < 0.85 else 1
					g._objects.append(obj)
					g._street_objs += 1


## Litter and stains on the pavement and in the road: papers, a dropped bag, glass, a stain, a few to a block.
static func _litter(g) -> void:
	var rng: RandomNumberGenerator = g._art_rng
	var W: int = g._size
	var road := int(g._tids.ASPHALT)
	var walk := int(g._tids.SIDEWALK)
	var props: Dictionary = g._street_cv.props
	var litter := ["papers", "papers", "dropped_bag", "broken_glass", "blood_stain", "broken_glass"]
	for b in g._layout.blocks:
		var r: Rect2i = b.rect
		for k in 5:
			var kind: String = litter[rng.randi() % litter.size()]
			var tx := 0
			var ty := 0
			# the sidewalk ring of the block, or the road just outside it
			var out_ := rng.randf() < 0.4
			if rng.randf() < 0.5:
				tx = r.position.x + rng.randi_range(1, maxi(1, r.size.x - 2))
				ty = (r.position.y if rng.randf() < 0.5 else r.end.y - 1)
				if out_:
					ty += -1 if ty == r.position.y else 1
			else:
				ty = r.position.y + rng.randi_range(1, maxi(1, r.size.y - 2))
				tx = (r.position.x if rng.randf() < 0.5 else r.end.x - 1)
				if out_:
					tx += -1 if tx == r.position.x else 1
			if tx < EDGE + 1 or ty < EDGE + 1 or tx >= W - EDGE - 1 or ty >= W - EDGE - 1:
				continue
			var ti := ty * W + tx
			if g._solid[ti] != 0 or (g._terrain[ti] != walk and g._terrain[ti] != road) or g._in_clear(Vector2i(tx, ty), 2):
				continue
			var obj = g._street_cv._decor(kind, tx, ty, rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
			if obj != null:
				g._kit.kit_set(obj, props[kind], rng)
				g._objects.append(obj)
				g._street_objs += 1
