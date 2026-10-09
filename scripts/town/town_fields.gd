## CLEAR3, THE FIELDS OF FIRE of the candidates (scripts/town/town_layout.gd `FIELD`): the scrub that takes the tall things out of them, and the measure the probes and the overview use.
##
## A base's fence ring is the border of its lot, and the dead come at it across the ground round the lot. The layout (`_clear_fields`) makes every lot that touches a candidate's field vacant, so that there
## is no other building in it; this takes out of the field what the vacant lots, the streets and the dice left standing and tall: the trees, the bushes, the parked cars and wrecks (the entry's own
## pair too), the stalls, the sheds, every solid thing of the ground that is not a low prop (assets/data/prop_heights.json) and not inside a building. A candidate's own lot is not touched (it was built
## clear, and the base is made on it); nor is anything inside a building. What is left in a field is the ground (roads, sidewalks, grass, dirt, soil), the flat marks and the lamps and hydrants (which
## shut nothing), and a few low props (a bench, a bin, a crate), which a shot goes over.
extends RefCounted

const PropHeights := preload("res://scripts/town/prop_heights.gd")


## Whether tile (x, y) is in a field (and so to be kept clear): in the union of `fields`, outside every candidate lot of `own`.
static func in_field(fields: Array, own: Array, x: int, y: int) -> bool:
	var p := Vector2i(x, y)
	var inside := false
	for f in fields:
		if (f as Rect2i).has_point(p):
			inside = true
			break
	if not inside:
		return false
	for r in own:
		if (r as Rect2i).has_point(p):
			return false
	return true


## Whether a building of a built lot (`built.buildings`: each has `parts`, rectangles in the town's tiles, and `box`, the rectangle that holds them all, a ruined part's walls still standing in it) has a
## part or its box in a field.
static func touches(buildings: Array, fields: Array) -> bool:
	for b in buildings:
		# (a ruined building has lost a part, and the part's wall stumps stand where it was: in a lot of a field it is not kept)
		if String((b as Dictionary).get("state", "intact")) == "ruined":
			return true
		var rects: Array = []
		for p in (b as Dictionary).get("parts", []):
			rects.append(Rect2i(p))
		if (b as Dictionary).has("box"):
			rects.append(Rect2i((b as Dictionary).box))
		for r in rects:
			for f in fields:
				if (f as Rect2i).intersects(r):
					return true
	return false


## Takes the tall things out of the fields of the generator `g` (a TownGen, after every lot and the streets' things are in, before the objects are put in their drawing order): its trees, its objects, the
## tiles of both in its solid grid. Returns {"trees": n, "objects": n, "tiles": n} of what was taken out.
static func scrub(g) -> Dictionary:
	var out := {"trees": 0, "objects": 0, "tiles": 0}
	var fields: Array = g._fields
	if fields.is_empty():
		return out
	var own: Array = g._clear_rects
	var W: int = g._size
	var H: int = g._size
	# the trees
	var kept_trees: Array = []
	for t in g._trees:
		var tx := floori(float(t.x))
		var ty := floori(float(t.y))
		if in_field(fields, own, tx, ty):
			out.trees += 1
			if tx >= 0 and ty >= 0 and tx < W and ty < H and g._solid[ty * W + tx] != 0 and not _wall_tile(g, tx, ty):
				g._solid[ty * W + tx] = 0
				out.tiles += 1
			continue
		kept_trees.append(t)
	g._trees = kept_trees
	# the objects: a solid one that is not low, not in a building, whose footprint touches a field
	var kept: Array = []
	for o in g._objects:
		if int(o.get("in", -1)) >= 0 or not bool(o.get("solid", false)) or PropHeights.is_low(String(o.kind)):
			kept.append(o)
			continue
		var tx0 := roundi(float(o.cx) - float(o.w) / 2.0)
		var ty0 := roundi(float(o.cy) - float(o.h) / 2.0)
		var touches := false
		var cells: Array = []
		for yy in int(o.h):
			for xx in int(o.w):
				var x := tx0 + xx
				var y := ty0 + yy
				if in_field(fields, own, x, y):
					touches = true
				cells.append(Vector2i(x, y))
		if not touches:
			kept.append(o)
			continue
		out.objects += 1
		for c in cells:
			var cc: Vector2i = c
			if cc.x >= 0 and cc.y >= 0 and cc.x < W and cc.y < H and g._solid[cc.y * W + cc.x] != 0 and not _wall_tile(g, cc.x, cc.y):
				g._solid[cc.y * W + cc.x] = 0
				out.tiles += 1
	g._objects = kept
	# what is left: the fence and hedge cells at the edge of a lot (`_kit_line`: a post or a stub of one that the lot's dressing left) and any other solid tile of the ground that is no building's and no low prop's
	var covered := PackedByteArray()
	covered.resize(W * H)
	for h in g._houses:
		for p in h.parts:
			var pr: Rect2i = p
			for y in range(maxi(pr.position.y, 0), mini(pr.end.y, H)):
				for x in range(maxi(pr.position.x, 0), mini(pr.end.x, W)):
					covered[y * W + x] = 1
	for o in g._objects:
		if not bool(o.get("solid", false)) or not (PropHeights.is_low(String(o.kind)) or int(o.get("in", -1)) >= 0):
			continue
		var ox0 := roundi(float(o.cx) - float(o.w) / 2.0)
		var oy0 := roundi(float(o.cy) - float(o.h) / 2.0)
		for yy in int(o.h):
			for xx in int(o.w):
				var px := ox0 + xx
				var py := oy0 + yy
				if px >= 0 and py >= 0 and px < W and py < H:
					covered[py * W + px] = 1
	for f in fields:
		var fr: Rect2i = f
		for y in range(maxi(fr.position.y, 0), mini(fr.end.y, H)):
			for x in range(maxi(fr.position.x, 0), mini(fr.end.x, W)):
				var i := y * W + x
				if g._solid[i] == 0 or covered[i] == 1 or not in_field(fields, own, x, y):
					continue
				g._solid[i] = 0
				g._kit_line[i] = 0
				out.tiles += 1
	return out


## The low props a vacant lot of a field is dressed with (a shot goes over each: assets/data/prop_heights.json), so that it reads as a yard or a bit of waste ground and not as a hole where a house was.
const DRESS_KINDS := ["bench", "bin", "garden_bed", "dining_table", "bench", "bin", "mailbox"]


## A few low props (DRESS_KINDS) on the grass of every lot the fields made vacant, two tiles in from its edge: one to three of them by its size. Returns how many stand. Uses the generator's art dice only
## (`_art_rng` and the street canvas's), so that nothing the rules read (the dead, the rescues, the doors) depends on it.
static func dress(g) -> int:
	var rng: RandomNumberGenerator = g._art_rng
	var props: Dictionary = g._street_cv.props
	var W: int = g._size
	var grass := int(g._tids.GRASS)
	var own: Array = g._clear_rects
	var placed := 0
	for lot in g._layout.lots:
		if not bool(lot.get("vacated", false)):
			continue
		var r: Rect2i = lot.rect
		var n := clampi(r.get_area() / 90, 1, 3)
		for k in n:
			var kind := String(DRESS_KINDS[rng.randi() % DRESS_KINDS.size()])
			if not props.has(kind) or not (props[kind] as Dictionary).has("kit"):
				continue
			var fp: Vector2i = g._street_cv.tiles_of(kind)
			var ok := false
			var tx := 0
			var ty := 0
			for attempt in 14:
				tx = rng.randi_range(r.position.x + 2, maxi(r.position.x + 2, r.end.x - 3 - fp.x))
				ty = rng.randi_range(r.position.y + 2, maxi(r.position.y + 2, r.end.y - 3 - fp.y))
				ok = true
				for yy in range(-1, fp.y + 1):
					for xx in range(-1, fp.x + 1):
						var i := (ty + yy) * W + tx + xx
						if i < 0 or i >= W * W or g._solid[i] != 0 or g._terrain[i] != grass:
							ok = false
				if ok:
					for rr in own:
						if (rr as Rect2i).intersects(Rect2i(tx, ty, fp.x, fp.y)):
							ok = false
				if ok:
					break
			if not ok:
				continue
			var obj = g._street_cv._decor(kind, tx, ty, 0.0, 0.0)
			if obj == null:
				continue
			g._kit.kit_set(obj, props[kind], rng)
			obj["solid"] = true
			g._objects.append(obj)
			for yy in fp.y:
				for xx in fp.x:
					g._solid[(ty + yy) * W + tx + xx] = 1
			g._street_objs += 1
			placed += 1
	return placed


## Whether a tile is a wall or a fence of the terrain (the grass and the asphalt under a tree are not): those are not taken out with a prop.
static func _wall_tile(g, x: int, y: int) -> bool:
	var t: int = g._terrain[y * g._size + x]
	return t == int(g._tids.WALL_METAL) or t == int(g._tids.get("WALL_BRICK", -1)) or t == int(g._tids.get("WALL", -1))


## The report the probes print for candidate house `hid` of a finished town: {"ring": [left, right, top, bottom] tiles from the walls to the lot's border (where the fence stands), "buildings": the
## other houses with a part in the field (ids), "tall": the number of tall solid tiles in the field outside every building and the candidate's lot, "kinds": text}.
static func report(town: Dictionary, hid: int, grow: int) -> Dictionary:
	var h: Dictionary = town.houses[hid]
	var lot: Rect2i = h.lot
	var rect: Rect2i = h.rect
	var zone := lot.grow(grow)
	var W: int = int(town.data.W)
	var Hh: int = int(town.data.H)
	var ring := [rect.position.x - lot.position.x, lot.end.x - rect.end.x, rect.position.y - lot.position.y, lot.end.y - rect.end.y]
	var found: Array = []
	for o in town.houses:
		if int(o.id) == hid:
			continue
		for p in o.parts:
			if Rect2i(p).intersects(zone):
				found.append(int(o.id))
				break
	var sz = town.data.solidZ
	var low = town.data.shot_low
	var th: PackedInt32Array = town.tile_house
	var tree_at := {}
	for t in town.data.trees:
		tree_at[Vector2i(floori(float(t.x)), floori(float(t.y)))] = true
	var obj_at := {}
	for o in town.data.objects:
		if int(o.get("in", -1)) >= 0 or not bool(o.get("solid", false)):
			continue
		var ox0 := roundi(float(o.cx) - float(o.w) / 2.0)
		var oy0 := roundi(float(o.cy) - float(o.h) / 2.0)
		for yy in int(o.h):
			for xx in int(o.w):
				obj_at[Vector2i(ox0 + xx, oy0 + yy)] = String(o.kind)
	var line = town.data.kit.line
	var kinds := {}
	var tall := 0
	for y in range(maxi(zone.position.y, 0), mini(zone.end.y, Hh)):
		for x in range(maxi(zone.position.x, 0), mini(zone.end.x, W)):
			var i := y * W + x
			if int(sz[i]) == 0 or int(low[i]) != 0 or th[i] >= 0 or lot.has_point(Vector2i(x, y)):
				continue
			tall += 1
			var k := "other"
			if tree_at.has(Vector2i(x, y)):
				k = "tree"
			elif obj_at.has(Vector2i(x, y)):
				k = String(obj_at[Vector2i(x, y)])
			elif int(line[i]) != 0:
				k = "line"
			kinds[k] = int(kinds.get(k, 0)) + 1
	return {"ring": ring, "buildings": found, "tall": tall, "kinds": kinds}
