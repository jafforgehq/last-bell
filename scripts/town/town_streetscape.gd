## The things of the streets and of the town's edge (One House, TOWNGEN): the solid ring of the world with a row of trees, the roadblocks where a street runs out of the town, parked cars
## along the kerbs (more on the main avenue) and here and there a wreck across a lane, street lamps and hydrants along the sidewalks, litter on the paving. The cars, wrecks, lamps,
## hydrants and litter are the art kit's (`kit` fields: scripts/town/town_kit.gd). `run(g)` works on a TownGen (scripts/town/town_gen.gd: its terrain, solid grid, objects, trees and the
## street canvas `_street_cv`), after every lot is stamped. Never on the start lot (the generator's `_clear_rect`), and no car within reach of the start's spawn roads.
extends RefCounted

const EDGE := 2


static func run(g) -> void:
	_border(g)
	_road_ends(g)
	_cars(g)
	_lamps(g)
	_litter(g)


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
	var start_c := Vector2(-1000.0, -1000.0)
	if g._start_house >= 0:
		start_c = Vector2(Rect2i(g._houses[g._start_house].rect).get_center())
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
		var sd: float = Vector2(tx, ty).distance_to(start_c)
		if sd > 33.0 and sd < 63.0:
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
				if g._terrain[t.y * W + t.x] != walk or g._clear_rect.has_point(t):
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
			if g._solid[ti] != 0 or (g._terrain[ti] != walk and g._terrain[ti] != road) or (g._clear_rect.size.x > 0 and g._clear_rect.grow(2).has_point(Vector2i(tx, ty))):
				continue
			var obj = g._street_cv._decor(kind, tx, ty, rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
			if obj != null:
				g._kit.kit_set(obj, props[kind], rng)
				g._objects.append(obj)
				g._street_objs += 1
