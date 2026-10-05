## The art kit's things in the generated town (One House, ART2's work moved out of town_gen.gd by TOWNGEN, so that the building generator (scripts/town/building_gen.gd) and the streets
## (scripts/town/town_streetscape.gd) can use it): the table of the kit's props as site-canvas catalogue entries (`layouts`), the placement of a thing by the town's rules (`put`), the
## furnishing of a room by its name (`furnish_room`), the dressing of a lot's yard (`dress_lot`) and the fields the world reads of every kit object (`kitify`, `kit_set`).
##
## Everything is the art kit's (`kit` fields on the objects, drawn by scripts/town/town_world.gd from assets/data/town_art.json through scripts/town/town_art.gd). Rooms are small (a living
## room of 4 x 2, a bathroom of 2 x 2), so a recipe lists where each thing may go, in order of liking, and the first spot that does not shut a door or cut the floor in two takes it
## (`put` says no, and the next spot is tried). Everything stands with its back to a wall (`kitify` turns it); only what faces south, or is the same from all sides, can be searched.
## CLEARANCE (the bathroom bug: "I get stuck around the toilet"): the floor of every ROOM stays one piece of free tiles that a body can walk all over without going out (`room_stays_clear`,
## which `put` asks for every solid thing it sets; small rooms also keep a share of the floor free), so no door opens on a pocket and no bed, sofa or loveseat is set across a narrow room
## from wall to wall; and `solid` is the art's own (assets/data/town_art.json). `BuildingGen._unblock` is the net under it for what the canvas's own ops lay (the shops' shelves).
extends RefCounted

const SiteGen := preload("res://scripts/raid/site_gen.gd")
const TownArt := preload("res://scripts/town/town_art.gd")

## The layouts the town's lots are built from (assets/data/site_layouts.json plus the kit's things, built once): each kit thing a catalogue entry with its footprint (for the facing south),
## `kit` the item, `container` the kind the sim knows it by (the kit's item id, so that the picture of a searched one is the kit's `opened`), `orient` for the things drawn along an axis.
static var _town_lay := {}
## kind, folder of the picture, footprint w, h, layer (1 decal, 2 low, 4 tall), solid, the container kind
## (`solid` is the art's own, assets/data/town_art.json: a chair, a toolbox, a laundry basket and a wall cabinet are not solid there, "the dead and the people can walk over it", and they
## are not here either: they used to shut a tile of a small room and made pockets of it.)
const KIT_PROPS := [
	["fridge", "furniture", 1, 1, 2, true, "fridge"], ["kitchen_counter", "furniture", 1, 1, 2, true, "kitchen_counter"], ["kitchen_sink", "furniture", 1, 1, 2, true, ""],
	["stove", "furniture", 1, 1, 2, true, ""], ["cupboard", "furniture", 1, 1, 2, true, "cupboard"], ["wardrobe", "furniture", 2, 1, 2, true, "wardrobe"],
	["dresser", "furniture", 2, 1, 2, true, "dresser"], ["nightstand", "furniture", 1, 1, 2, true, "nightstand"], ["bed_single", "furniture", 1, 2, 2, true, ""],
	["bed_double", "furniture", 2, 2, 2, true, ""], ["sofa", "furniture", 3, 1, 2, true, ""], ["loveseat", "furniture", 2, 1, 2, true, ""], ["armchair", "furniture", 1, 1, 2, true, ""],
	["tv_stand", "furniture", 2, 1, 2, true, ""], ["coffee_table", "furniture", 2, 1, 2, true, ""], ["dining_table", "furniture", 2, 1, 2, true, ""], ["chair", "furniture", 1, 1, 2, false, ""],
	["bookshelf", "furniture", 2, 1, 2, true, "bookshelf"], ["desk", "furniture", 2, 1, 2, true, "desk"], ["toilet", "furniture", 1, 1, 2, true, ""],
	["bathtub", "furniture", 2, 1, 2, true, ""], ["washbasin", "furniture", 1, 1, 2, true, ""], ["medicine_cabinet", "furniture", 1, 1, 2, false, "medicine_cabinet"],
	["toolbox", "furniture", 1, 1, 2, false, "toolbox"], ["workbench", "furniture", 2, 1, 2, true, "workbench"], ["box", "furniture", 1, 1, 2, true, "box"],
	["crate", "furniture", 1, 1, 2, true, "crate"], ["laundry_basket", "furniture", 1, 1, 2, false, ""], ["shelf_tins", "furniture", 2, 1, 2, true, "shelf_tins"],
	["lamp_floor", "furniture", 1, 1, 2, false, ""],
	["rug_rect", "furniture", 3, 2, 1, false, ""], ["rug_round", "furniture", 2, 2, 1, false, ""], ["papers", "furniture", 1, 1, 1, false, ""],
	["broken_glass", "furniture", 1, 1, 1, false, ""], ["blood_stain", "furniture", 1, 1, 1, false, ""], ["dropped_bag", "furniture", 1, 1, 1, false, ""],
	["bedroll", "furniture", 1, 2, 1, false, "", "mattress"], ["step", "house", 3, 1, 1, false, ""],
	["bush", "outdoors", 1, 1, 4, true, ""], ["mailbox", "outdoors", 1, 1, 2, true, ""], ["bin", "outdoors", 1, 1, 2, true, ""], ["bike", "outdoors", 2, 1, 2, false, ""],
	["garden_bed", "outdoors", 3, 1, 2, true, ""], ["shed", "outdoors", 3, 2, 4, true, ""], ["swing_set", "outdoors", 3, 2, 4, true, ""], ["slide", "outdoors", 1, 3, 4, true, ""],
	["bench", "outdoors", 2, 1, 2, true, ""], ["car_wreck", "outdoors", 4, 3, 4, true, ""], ["hydrant", "street", 1, 1, 2, false, ""], ["streetlamp", "street", 1, 1, 4, false, ""],
	["market_stall", "outdoors", 3, 2, 4, true, ""],
	# (ARRIVAL: the arrows of the way in: double chevrons painted on the road at the entry, pointing into the town)
	["marker_enter", "marker", 1, 1, 1, false, ""],
]
## Things drawn along an axis (the manifest has `orient`, not `facing`, for them) and their axis; and the cars (the kit's `car`).
const KIT_ORIENT := {"bike": "h", "garden_bed": "h", "swing_set": "h"}
## The containers' loot: each new kind is like an old one of the raid sites' table (`affinity`), times a factor.
const KIT_LIKE := {
	"kitchen_counter": ["counter", 1.0], "cupboard": ["cabinet", 1.0], "wardrobe": ["cabinet", 0.8], "dresser": ["cabinet", 0.9], "nightstand": ["cabinet", 0.6],
	"bookshelf": ["shelf", 0.8], "shelf_tins": ["shelf", 1.3], "desk": ["cabinet", 0.7], "toolbox": ["locker", 1.0], "workbench": ["counter", 1.1],
	"medicine_cabinet": ["cabinet", 0.5], "box": ["crate", 1.0],
}
## The floor of a room by its name (the kit's ground ids): the names of the building programs (scripts/town/building_plans.gd). A name that is not here keeps the floor the terrain has.
const FLOOR_OF := {
	"living room": "floor_wood", "front room": "floor_wood", "study": "floor_wood", "dining room": "floor_wood", "nave": "floor_wood", "reading room": "floor_wood", "stacks": "floor_wood",
	"office": "floor_wood", "flat": "floor_wood", "nursery": "floor_carpet", "dormitory": "floor_carpet", "bedroom": "floor_carpet", "side": "floor_wood",
	"kitchen": "floor_kitchen", "pantry": "floor_kitchen", "shop floor": "floor_kitchen", "dining hall": "floor_kitchen", "classroom": "floor_kitchen", "bathroom": "floor_bath",
	"hall": "floor_hall", "lobby": "floor_hall", "narthex": "floor_hall", "storeroom": "floor_hall", "store": "floor_hall", "garage": "floor_hall", "workshop": "floor_hall", "utility": "floor_hall",
	"engine bay": "floor_hall", "gym": "floor_hall", "banking hall": "floor_hall", "reception": "floor_hall", "waiting room": "floor_hall", "ward": "floor_hall", "pharmacy": "floor_hall",
	"cell": "floor_hall", "armoury": "floor_hall", "vault": "floor_hall", "front desk": "floor_hall", "chancel": "floor_hall", "shed": "floor_wood", "room": "floor_wood",
	"barn": "dirt_path", "stable": "dirt_path",
}

var tids := {}
var kit_info := {}
var door_t := 23
var _ring := PackedByteArray()
var _seen := PackedByteArray()
var _queue := PackedInt32Array()


static func layouts() -> Dictionary:
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
	_town_lay = lay
	return _town_lay


func setup(lay: Dictionary, terrain_ids: Dictionary) -> void:
	tids = terrain_ids
	door_t = int(tids.DOOR_WOOD)
	kit_info = {}
	for k in lay.props:
		var pr: Dictionary = lay.props[k]
		if pr.has("kit"):
			kit_info[k] = [int(pr.tiles[0]), int(pr.tiles[1]), bool(pr.get("solid", true)), bool(pr.get("loose", false))]


# ------------------------------------------------------------------- placement --

## Puts `kind` on the first of `spots` (top left tiles) that takes it; true when one did. `container`: it may be searched (the catalogue says what kind of container it is).
func try_spots(cv, kind: String, spots: Array, container: bool = false, keep: bool = false) -> bool:
	for sp in spots:
		if put(cv, kind, int(sp.x), int(sp.y), container, keep):
			return true
	return false


## One thing of the kit on a spot, by the town's rules (the site canvas's own are meant for rooms of a raid site: they keep two tiles clear of every door and test that nothing is cut off by
## flooding the whole canvas, which in a room of 4 x 2 leaves no spot and in a town of 180 lots costs seconds): nothing within a tile of a door cell, a spot that is free (and, for a yard,
## not in the kept path), and nothing that cuts the floor in two (`safe`). `keep` makes the kept tiles of the canvas count (the yard's: the path from the door).
func put(cv, kind: String, tx: int, ty: int, container: bool = false, keep: bool = false) -> bool:
	var info: Array = kit_info[kind]
	var fw: int = info[0]
	var fh: int = info[1]
	var W: int = cv.W
	if tx < 0 or ty < 0 or tx + fw > W or ty + fh > cv.H:
		return false
	var solid_item: bool = info[2]
	var loose: bool = info[3]
	var sol: PackedByteArray = cv.solid
	var terr: PackedInt32Array = cv.terrain
	# (a thing of the yard, `keep`, is not put on the floor of a room: a bush in a bedroom was a pocket of its own)
	if keep and room_at(cv, tx, ty).size.x > 0:
		return false
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
		if not loose and not safe(cv, tx, ty, fw, fh):
			return false
		if not loose and not room_stays_clear(cv, Rect2i(tx, ty, fw, fh)):
			return false
	var opts := {"force": true}
	if container:
		opts["container"] = true
	return cv._put(kind, tx, ty, opts) != null


# ------------------------------------------------------------------ clearance --

## The floor of a room is one piece of free tiles, and a body (the avatar's box is 0.6 wide: it goes wherever a tile goes, four ways, never across a corner) can walk from any of them to
## any other without leaving the room. `safe` only asks that the town stays joined as a whole, which a pocket survives: a toilet and a basin on both sides of the tile behind a door,
## a bed or a loveseat across a narrow room from wall to wall, left one door on each side of a barrier, and whoever came in by one of them was shut in the half it opened on.
## Small rooms (up to 12 tiles) also keep a share of their floor free (`free_needed`).
const FREE_SHARE := 0.35
## (a room of up to 5 x 5 keeps its share of the floor free: the homes' rooms are 3 x 3 to 5 x 5)
const SMALL_ROOM := 25


## The floor rectangle of the indoor room that holds the tile (tx, ty), or an empty rectangle (a yard, a street, a wall).
func room_at(cv, tx: int, ty: int) -> Rect2i:
	var p := Vector2i(tx, ty)
	for a in cv.areas:
		if bool(a.get("indoor", false)):
			var rr: Rect2i = a.rect
			if rr.has_point(p):
				return rr
	return Rect2i()


## How many tiles of a room of this size must stay free.
static func free_needed(floor_tiles: int) -> int:
	if floor_tiles > SMALL_ROOM:
		return 1
	return maxi(2, ceili(FREE_SHARE * float(floor_tiles)))


## How the free floor of a room lies, with the tiles of `extra` counted as shut: {"free": tiles, "reached": the tiles of the piece the first one is in}. A room is clear when
## the two are the same number and `free_needed` is met.
func room_floor(cv, rr: Rect2i, extra: Rect2i = Rect2i()) -> Dictionary:
	var W: int = cv.W
	var sol: PackedByteArray = cv.solid
	var rw := rr.size.x
	var rh := rr.size.y
	var open := PackedByteArray()
	open.resize(rw * rh)
	var free := 0
	var first := -1
	for yy in rh:
		for xx in rw:
			var tx := rr.position.x + xx
			var ty := rr.position.y + yy
			if sol[ty * W + tx] == 0 and not extra.has_point(Vector2i(tx, ty)):
				open[yy * rw + xx] = 1
				free += 1
				if first < 0:
					first = yy * rw + xx
	if first < 0:
		return {"free": 0, "reached": 0}
	var queue := PackedInt32Array()
	queue.append(first)
	open[first] = 2
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		@warning_ignore("integer_division")
		var cy := c / rw
		var cx := c - cy * rw
		if cx > 0 and open[c - 1] == 1:
			open[c - 1] = 2
			queue.append(c - 1)
		if cx < rw - 1 and open[c + 1] == 1:
			open[c + 1] = 2
			queue.append(c + 1)
		if cy > 0 and open[c - rw] == 1:
			open[c - rw] = 2
			queue.append(c - rw)
		if cy < rh - 1 and open[c + rw] == 1:
			open[c + rw] = 2
			queue.append(c + rw)
	return {"free": free, "reached": queue.size()}


## Whether shutting a footprint leaves its room clear (a footprint that is not in a room is not this rule's business).
func room_stays_clear(cv, fp: Rect2i) -> bool:
	var rr := room_at(cv, fp.position.x, fp.position.y)
	if rr.size.x <= 0:
		return true
	var f := room_floor(cv, rr, fp)
	return int(f.free) >= free_needed(rr.size.x * rr.size.y) and int(f.reached) == int(f.free)


## Whether a room's floor is clear as it stands.
func room_is_clear(cv, rr: Rect2i) -> bool:
	var f := room_floor(cv, rr)
	return int(f.free) >= free_needed(rr.size.x * rr.size.y) and int(f.reached) == int(f.free)


## The tiles just inside a room where its doors open (a doorway cell of the ring and the floor tile next to it).
func door_tiles(cv, rr: Rect2i) -> Array:
	var out: Array = []
	var W: int = cv.W
	for yy in range(rr.position.y - 1, rr.end.y + 1):
		for xx in range(rr.position.x - 1, rr.end.x + 1):
			if not cv._in(xx, yy) or cv.terrain[yy * W + xx] != door_t:
				continue
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(xx, yy) + dv
				if rr.has_point(q) and not out.has(q):
					out.append(q)
	return out


## Whether shutting a footprint leaves the open tiles round it joined. First the cheap proof: if the open tiles of the ring round it are one run, nothing can be cut off; else if they are
## all joined to each other within 4 tiles of the footprint, without passing through it, nothing can; only when that fails is the exact test (flooding the canvas) made.
func safe(cv, tx: int, ty: int, tw: int, th: int) -> bool:
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


## Puts the things of `items` ([kind, container] each) along the row `y` between `x0` and `x1` (the end excluded), in order from the left (from the right when `rev`), each at the first
## free spot from where the last one ended (a doorway's front is skipped). Returns how many went in; the rest did not fit.
func line(cv, y: int, x0: int, x1: int, items: Array, rev: bool = false) -> int:
	var placed := 0
	var x := x0
	var xe := x1
	for it in items:
		var kind: String = it[0]
		var w: int = cv.tiles_of(kind).x
		var done := false
		if rev:
			while xe - w >= x0 and not done:
				if put(cv, kind, xe - w, y, bool(it[1])):
					done = true
					xe -= w
				else:
					xe -= 1
		else:
			while x + w <= x1 and not done:
				if put(cv, kind, x, y, bool(it[1])):
					done = true
					x += w
				else:
					x += 1
		if not done:
			break
		placed += 1
	return placed


## `items` along the north row of a room, what does not fit along its south row.
func rows_of(cv, r: Rect2i, items: Array, rev: bool = false) -> int:
	var n := line(cv, r.position.y, r.position.x, r.end.x, items, rev)
	if n < items.size() and r.size.y >= 2:
		n += line(cv, r.end.y - 1, r.position.x, r.end.x, items.slice(n), rev)
	return n


## `items` along the far wall of a room, the one away from the street (`front` is the side the street is on).
func far_row(cv, r: Rect2i, front: String, items: Array, rev: bool = false) -> int:
	var y := r.end.y - 1 if front == "N" else r.position.y
	var n := line(cv, y, r.position.x, r.end.x, items, rev)
	if n < items.size() and r.size.y >= 2:
		var y2 := r.position.y if front == "N" else r.end.y - 1
		n += line(cv, y2, r.position.x, r.end.x, items.slice(n), rev)
	return n


# ------------------------------------------------------------------ the rooms --

## The furniture of one room by its name. `kind` the kind of building, `front` the side of the street ("N" or "S"), `start` the start house, `kitchenette` a living room that has the
## kitchen of a house with none of its own, `has_kitchen` whether the building has a kitchen.
func furnish_room(cv, rng: RandomNumberGenerator, name: String, r: Rect2i, front: String, kind: String, start: bool, kitchenette: bool) -> void:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	match name:
		"kitchen":
			kitchen(cv, rng, r, true)
		"bathroom":
			bathroom(cv, rng, r)
		"bedroom":
			bedroom(cv, rng, r, start)
		"living room":
			living(cv, rng, r, kitchenette, start)
		"front room":
			living(cv, rng, r, false, start)
		"shop floor":
			shop(cv, rng, r)
		"storeroom", "store":
			storeroom(cv, rng, r)
		"shed":
			rows_of(cv, r, [["shelf_tins", true], ["crate", true], ["box", true]], rng.randf() < 0.5)
		"nursery":
			try_spots(cv, "bed_single", _along(x, w - 1, y))
			try_spots(cv, "dresser", _along(x, w - 1, y + h - 1), true)
			try_spots(cv, "lamp_floor", [Vector2i(x + w - 1, y), Vector2i(x, y + h - 1)])
			if w >= 3 and h >= 3:
				put(cv, "rug_round", x + (w - 2) / 2, y + (h - 2) / 2 + 1)
		"utility":
			# the washing and the tools: a bench, shelves of tins and a cupboard along the far wall (the floor before them is left free: the base's worktable is set up here), the basket and a crate
			# in the corners of the near one
			far_row(cv, r, front, [["workbench", true], ["shelf_tins", true], ["cupboard", true]], rng.randf() < 0.5)
			try_spots(cv, "laundry_basket", [Vector2i(x + w - 1, y + h - 1), Vector2i(x, y + h - 1), Vector2i(x + w - 1, y), Vector2i(x, y)])
			try_spots(cv, "crate" if rng.randf() < 0.5 else "box", [Vector2i(x, y + h - 1), Vector2i(x + w - 1, y + h - 1), Vector2i(x, y), Vector2i(x + w - 1, y)], true)
		"hall" when w <= 3 and h >= 6:
			# a hall down the middle of a house: a lamp at the front, a cupboard and a chest against the long walls (never in front of a door: `put` leaves those tiles free), a bin at the far end
			try_spots(cv, "lamp_floor", [Vector2i(x, y), Vector2i(x + w - 1, y)])
			var sides: Array = []
			for yy in range(y + 1, y + h):
				sides.append(Vector2i(x, yy))
				sides.append(Vector2i(x + w - 1, yy))
			for si in range(sides.size() - 1, 0, -1):
				var sj := rng.randi_range(0, si)
				var tmp = sides[si]
				sides[si] = sides[sj]
				sides[sj] = tmp
			try_spots(cv, "cupboard", sides, true)
			if rng.randf() < 0.7:
				try_spots(cv, "bookshelf" if w >= 3 else "box", sides, true)
			if rng.randf() < 0.5:
				try_spots(cv, "bin", [Vector2i(x + w - 1, y + h - 1), Vector2i(x, y + h - 1)])
		"hall", "lobby", "narthex":
			if kind == "warehouse":
				var ty := y + 1
				while ty + 1 <= r.end.y - 2:
					var tx := x + 1
					while tx + 2 <= r.end.x - 1:
						if rng.randf() < 0.85:
							put(cv, "shelf_tins" if rng.randf() < 0.75 else "crate", tx, ty, rng.randf() < 0.85)
						tx += 3 if rng.randf() < 0.5 else 2
					ty += 3
				for k in 4:
					put(cv, "crate" if rng.randf() < 0.6 else "box", rng.randi_range(x, r.end.x - 1), rng.randi_range(y, r.end.y - 1), rng.randf() < 0.7)
			else:
				try_spots(cv, "lamp_floor", [Vector2i(x, y), Vector2i(x + w - 1, y)])
				if w >= 4 and rng.randf() < 0.7:
					try_spots(cv, "bench", _along(x, w - 1, y + h - 1))
				if rng.randf() < 0.5:
					try_spots(cv, "bin", [Vector2i(x + w - 1, y + h - 1), Vector2i(x, y + h - 1)])
				if rng.randf() < 0.5:
					try_spots(cv, "cupboard", _along(x, w, y), true)
		"study", "office", "reception":
			var d := desk_with_chair(cv, x, x + w, y, true)
			if not d:
				d = desk_with_chair(cv, x, x + w, y + h - 1, true)
			try_spots(cv, "bookshelf", _along(x, w - 1, y + h - 1 if h >= 3 else y), true)
			if rng.randf() < 0.6:
				try_spots(cv, "lamp_floor", [Vector2i(x + w - 1, y + h - 1), Vector2i(x, y + h - 1)])
			if kind == "office" and w >= 5 and h >= 4:
				desk_with_chair(cv, x, x + w, y + h - 2, rng.randf() < 0.5)
		"dining room":
			if w >= 3 and h >= 3:
				var ty := y + h / 2
				var tx := x + (w - 2) / 2
				if put(cv, "dining_table", tx, ty):
					put(cv, "chair", tx - 1, ty)
					put(cv, "chair", tx + 2, ty)
					if h >= 5:
						put(cv, "chair", tx, ty - 1)
						put(cv, "chair", tx + 1, ty + 1)
			try_spots(cv, "cupboard", _along(x, w, y), true)
			if w >= 4 and rng.randf() < 0.6:
				try_spots(cv, "cupboard", _along(x, w, y + h - 1), true)
			if rng.randf() < 0.5:
				try_spots(cv, "lamp_floor", [Vector2i(x + w - 1, y + h - 1), Vector2i(x, y + h - 1), Vector2i(x, y)])
		"pantry":
			rows_of(cv, r, [["cupboard", true], ["shelf_tins", true], ["crate", true], ["cupboard", true]], rng.randf() < 0.5)
		"garage":
			if w >= 4 and h >= 2:
				var cy := y + h - 2 if front == "N" else y
				put(cv, "car_h", x, cy, rng.randf() < 0.6)
			far_row(cv, r, front, [["workbench", true], ["toolbox", true], ["crate", true]], rng.randf() < 0.5)
		"workshop":
			rows_of(cv, r, [["workbench", true], ["toolbox", true], ["workbench", true], ["crate", true]], rng.randf() < 0.5)
			for k in 3:
				put(cv, "box" if rng.randf() < 0.5 else "crate", rng.randi_range(x, r.end.x - 1), rng.randi_range(y + 1, r.end.y - 1), rng.randf() < 0.5)
			if kind == "garage" and w >= 6 and h >= 4:
				put(cv, "car_h", x + 1, y + h / 2, rng.randf() < 0.5)
		"engine bay":
			if w >= 5 and h >= 3:
				put(cv, "car_h", x + (w - 4) / 2, y + h / 2, true)
			rows_of(cv, r, [["workbench", true], ["toolbox", true], ["crate", true]], rng.randf() < 0.5)
		"dining hall":
			var ty := y + 1
			while ty < r.end.y - 1:
				var tx := x + 1
				while tx + 3 <= r.end.x - 1:
					if put(cv, "dining_table", tx, ty):
						put(cv, "chair", tx - 1, ty)
						put(cv, "chair", tx + 2, ty)
					tx += 5
				ty += 3
			far_row(cv, r, front, [["fridge", true], ["kitchen_counter", true], ["kitchen_counter", false], ["kitchen_sink", false], ["stove", false]])
		"banking hall":
			far_row(cv, r, front, [["kitchen_counter", true], ["kitchen_counter", false], ["kitchen_counter", true]])
			try_spots(cv, "bench", _along(x, w - 1, y if front == "S" else y + h - 1))
			try_spots(cv, "lamp_floor", [Vector2i(x, y + h / 2), Vector2i(x + w - 1, y + h / 2)])
		"vault", "armoury":
			rows_of(cv, r, [["wardrobe", true], ["toolbox", true], ["crate", true], ["wardrobe", true]], rng.randf() < 0.5)
		"dormitory":
			rows_of(cv, r, [["bed_single", false], ["nightstand", false], ["bed_single", false], ["nightstand", true], ["bed_single", false], ["bed_single", false]])
			try_spots(cv, "wardrobe", _along(x, w - 1, y + h - 1), true)
		"ward":
			rows_of(cv, r, [["bed_single", false], ["nightstand", true], ["bed_single", false], ["bed_single", false]])
			try_spots(cv, "medicine_cabinet", _along(x, w, y + h - 1), true)
		"waiting room":
			far_row(cv, r, front, [["bench", false], ["bench", false], ["bench", false]])
			if w >= 4 and h >= 4:
				put(cv, "coffee_table", x + (w - 2) / 2, y + h / 2)
			try_spots(cv, "lamp_floor", [Vector2i(x, y), Vector2i(x + w - 1, y)])
		"pharmacy":
			rows_of(cv, r, [["medicine_cabinet", true], ["cupboard", true], ["shelf_tins", true], ["medicine_cabinet", true], ["shelf_tins", true]], rng.randf() < 0.5)
		"cell":
			try_spots(cv, "bed_single", _along(x, w - 1, y))
			try_spots(cv, "toilet", [Vector2i(x + w - 1, y + h - 1), Vector2i(x, y + h - 1)])
		"front desk":
			far_row(cv, r, front, [["kitchen_counter", true], ["kitchen_counter", true], ["desk", true]])
			try_spots(cv, "bench", _along(x, w - 1, y if front == "S" else y + h - 1))
		"classroom":
			desk_with_chair(cv, x, x + w, y, rng.randf() < 0.5)
			var ty := y + 2
			while ty + 1 < r.end.y:
				var tx := x
				while tx + 2 <= r.end.x:
					if rng.randf() < 0.85:
						if put(cv, "desk", tx, ty, rng.randf() < 0.12):
							put(cv, "chair", tx, ty + 1)
					tx += 3
				ty += 3
		"gym":
			rows_of(cv, r, [["bench", false], ["toolbox", true], ["bench", false]])
			for k in 3:
				put(cv, "box" if rng.randf() < 0.5 else "crate", rng.randi_range(x, r.end.x - 1), rng.randi_range(y, r.end.y - 1), rng.randf() < 0.5)
		"flat":
			bedroom(cv, rng, r, false)
			if h >= 3:
				line(cv, y + h - 1, x, r.end.x, [["fridge", true], ["stove", false]], rng.randf() < 0.5)
		"reading room":
			if w >= 4 and h >= 3:
				var ty := y + h / 2
				for k in range(0, w - 2, 3):
					if put(cv, "dining_table", x + k, ty):
						put(cv, "chair", x + k, ty + 1)
			far_row(cv, r, front, [["bookshelf", true], ["bookshelf", true], ["desk", true]])
		"stacks":
			var ty := y
			while ty < r.end.y:
				var tx := x
				while tx + 2 <= r.end.x:
					put(cv, "bookshelf", tx, ty, rng.randf() < 0.55)
					tx += 2
				ty += 3
		"nave":
			# pews either side of a middle aisle, two rows apart
			var aisle := x + w / 2
			var ty := y + (2 if front == "N" else 1)
			while ty < r.end.y - 1:
				var tx := x
				while tx + 2 <= aisle:
					put(cv, "bench", tx, ty)
					tx += 3
				tx = aisle + 1
				while tx + 2 <= r.end.x:
					put(cv, "bench", tx, ty)
					tx += 3
				ty += 2
		"chancel":
			put(cv, "desk", x + (w - 2) / 2, y + (h / 2), rng.randf() < 0.5)
			try_spots(cv, "cupboard", _along(x, w, y), true)
		"barn", "stable":
			var n := 6 if name == "barn" else 3
			for k in n:
				put(cv, "crate" if rng.randf() < 0.5 else "box", rng.randi_range(x, r.end.x - 1), rng.randi_range(y, r.end.y - 1), rng.randf() < 0.45)
			if name == "barn":
				for k in 2:
					put(cv, "garden_bed", rng.randi_range(x, r.end.x - 3), rng.randi_range(y, r.end.y - 1))
	# the clutter of a place somebody left: papers, glass, a stain
	if name != "bathroom" and rng.randf() < 0.55:
		cv._run_ops([{"op": "decals", "rect": [x, y, w, h], "kinds": ["papers", "broken_glass", "blood_stain"], "n": {"r": [0, 1]}}])


## The spots along a row `y` from `x` for `n` tiles (top left tiles).
func _along(x: int, n: int, y: int) -> Array:
	var out: Array = []
	for sx in range(x, x + maxi(1, n)):
		out.append(Vector2i(sx, y))
	return out


## A desk (two wide) with its chair in front of it on the row `y` between `x0` and `x1`; true when it stood.
func desk_with_chair(cv, x0: int, x1: int, y: int, container: bool) -> bool:
	for sx in range(x0, x1 - 1):
		if put(cv, "desk", sx, y, container):
			put(cv, "chair", sx, y + 1)
			return true
	return false


## A kitchen: a fridge, counters (one may be a sink), a stove, a cupboard when the room is wide, along the north wall (the south one when a door is in the way); a table and chairs when it is deep.
func kitchen(cv, rng: RandomNumberGenerator, r: Rect2i, table: bool) -> void:
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
	var n := line(cv, r.position.y, r.position.x, r.end.x, items, rev)
	if n < items.size() and r.size.y >= 2:
		line(cv, r.end.y - 1, r.position.x, r.end.x, items.slice(n), rev)
	if table and r.size.y >= 3 and w >= 4:
		var ty := r.end.y - 1
		if put(cv, "dining_table", r.position.x + 1, ty):
			put(cv, "chair", r.position.x, ty)
			put(cv, "chair", r.position.x + 3, ty)


## A bathroom: the fittings stand along ONE wall, the north or the south row, whichever has fewer doors in it, each on the spot farthest from the doors (the tub, two long, takes a corner
## of it); the other row is the lane from the doors, and the wall cabinet and the basket (walkable, as in the art) stand on it. A room of 3 x 3 and more has a tub, a smaller one a toilet and
## a basin and no more. `put` keeps the floor in one piece, so a fitting that would shut a door's pocket in, or leave a one tile gap between two of them that leads nowhere, is not set.
func bathroom(cv, rng: RandomNumberGenerator, r: Rect2i) -> void:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	if w < 2 or h < 2:
		return
	var doors := door_tiles(cv, r)
	var north := 0
	var south := 0
	for d in doors:
		if d.y == y:
			north += 1
		if d.y == r.end.y - 1:
			south += 1
	var row_y := y if (north < south or (north == south and rng.randf() < 0.5)) else r.end.y - 1
	var lane_y := r.end.y - 1 if row_y == y else y
	var fittings: Array = ["bathtub", "toilet", "washbasin"] if (w >= 3 and h >= 3) else ["toilet", "washbasin"]
	for kind in fittings:
		var fw: int = cv.tiles_of(kind).x
		if not try_spots(cv, kind, _far_from(_row_spots(x, w, row_y, fw), doors, rng)):
			try_spots(cv, kind, _far_from(_row_spots(x, w, lane_y, fw), doors, rng))
	# the wall cabinet and the basket are not solid (they are walkable in the art), so they must not share a tile
	var taken: Array = []
	for sp in _far_from(_row_spots(x, w, lane_y, 1) + _row_spots(x, w, row_y, 1), doors, rng):
		if cv.solid[int(sp.y) * cv.W + int(sp.x)] == 0 and put(cv, "medicine_cabinet", int(sp.x), int(sp.y), true):
			taken.append(sp)
			break
	if rng.randf() < 0.5:
		for sp in _far_from(_row_spots(x, w, lane_y, 1), doors, rng):
			if not taken.has(sp) and put(cv, "laundry_basket", int(sp.x), int(sp.y)):
				break


## The top left spots along a row `y` from `x` for `w` tiles for a footprint `fw` wide.
func _row_spots(x: int, w: int, y: int, fw: int) -> Array:
	var out: Array = []
	for sx in range(x, x + w - fw + 1):
		out.append(Vector2i(sx, y))
	return out


## `spots` with the one farthest from the given tiles (the doors' inside tiles) first, a little at random among those about as far.
func _far_from(spots: Array, from: Array, rng: RandomNumberGenerator) -> Array:
	var keyed: Array = []
	for sp in spots:
		var d := 99
		for f in from:
			d = mini(d, absi(int(sp.x) - int(f.x)) + absi(int(sp.y) - int(f.y)))
		keyed.append([float(d) + rng.randf() * 0.5, sp])
	keyed.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var out: Array = []
	for k in keyed:
		out.append(k[1])
	return out


func bedroom(cv, rng: RandomNumberGenerator, r: Rect2i, _start: bool) -> void:
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
		if put(cv, "bed_double" if double else "bed_single", sp.x, sp.y):
			bed_x = sp.x
			break
	if bed_x < 0 and not double:
		# a bed with its foot to the north wall (the head at the south): along the south wall
		for sx in range(x, x + w):
			if put(cv, "bed_single", sx, r.end.y - 2):
				bed_x = sx
				break
	if bed_x >= 0:
		try_spots(cv, "nightstand", [Vector2i(bed_x + bw, y), Vector2i(bed_x - 1, y)], rng.randf() < 0.7)
	var along: Array = []
	for sx in range(x, x + w - 1):
		along.append(Vector2i(sx, y))
	try_spots(cv, "wardrobe" if rng.randf() < 0.55 else "dresser", along, true)
	if h >= 3:
		var low: Array = []
		for sx in range(x, x + w - 1):
			low.append(Vector2i(sx, y + h - 1))
		try_spots(cv, "dresser" if rng.randf() < 0.5 else "wardrobe", low, false)
	if rng.randf() < 0.55:
		try_spots(cv, "lamp_floor", [Vector2i(x + w - 1, y + h - 1), Vector2i(x, y + h - 1), Vector2i(x + w - 1, y)])
	if w >= 3 and h >= 3:
		put(cv, "rug_round", x + (w - 2) / 2, y + (h - 2) / 2 + (1 if h >= 4 else 0))


## A living room (a front room): a sofa at one long wall, a television or a bookshelf at the other, an armchair, a lamp, a rug; `kitchenette` the kitchen of a house that has none of its own.
func living(cv, rng: RandomNumberGenerator, r: Rect2i, kitchenette: bool, start: bool) -> void:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var top := y
	if kitchenette:
		kitchen(cv, rng, Rect2i(x, y, w, 1), false)
		top = y + 2
	var rh := r.end.y - top
	if w >= 3 and rh >= 2:
		put(cv, "rug_rect", x, top + (rh - 2) / 2)
	var seat := "sofa" if w >= 3 else "loveseat"
	var seat_w := 3 if w >= 3 else 2
	var south_first := rng.randf() < 0.6 or kitchenette or start
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
		if try_spots(cv, seat, spots):
			seat_row = row
			break
	if seat_row < 0 and w >= 2 and not start:
		# no room for the sofa between the doors: a loveseat
		for row in rows:
			if row >= top and try_spots(cv, "loveseat", [Vector2i(x, row), Vector2i(x + w - 2, row), Vector2i(x + 1, row)]):
				seat_row = row
				break
	var other := top if seat_row != top else r.end.y - 1
	if seat_row >= 0 and other != seat_row and not kitchenette:
		var spots: Array = []
		for k in range(0, w - 1):
			spots.append(Vector2i(x + k, other))
		if rng.randf() < 0.6:
			try_spots(cv, "tv_stand", spots)
		else:
			try_spots(cv, "bookshelf", spots, other == top)
	if rh >= 3 and w >= 3:
		try_spots(cv, "armchair", [Vector2i(x + w - 1, top + 1), Vector2i(x, top + 1)])
	if rh >= 4 and w >= 3:
		put(cv, "coffee_table", x + (w - 2) / 2, top + rh / 2)
	if rng.randf() < 0.55:
		try_spots(cv, "lamp_floor", [Vector2i(x + w - 1, top), Vector2i(x, top), Vector2i(x + w - 1, r.end.y - 1)])
	# something to search in a living room too (a cupboard along a wall, where nothing in it can be)
	if not kitchenette and w >= 3 and not _has_container(cv, r):
		var cs: Array = []
		for sx in range(x, x + w):
			cs.append(Vector2i(sx, top))
			cs.append(Vector2i(sx, r.end.y - 1))
		try_spots(cv, "cupboard", cs, true)


## Whether a container (a thing that may be searched) stands in the rectangle.
func _has_container(cv, r: Rect2i) -> bool:
	for c in cv.cands:
		var o: Dictionary = c.obj
		if r.has_point(Vector2i(floori(float(o.cx)), floori(float(o.cy)))):
			return true
	return false


func shop(cv, _rng: RandomNumberGenerator, r: Rect2i) -> void:
	cv._run_ops([
		{"op": "rows", "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "kinds": ["shelf_tins"], "pitch": 3, "y0": 1, "margin": 1, "container": 0.8},
		{"op": "line", "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "side": "N", "kinds": ["kitchen_counter", "fridge"], "gap": [0, 0], "container": true, "n": 3},
	])


func storeroom(cv, _rng: RandomNumberGenerator, r: Rect2i) -> void:
	cv._run_ops([
		{"op": "line", "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "side": "N", "kinds": ["crate", "box", "toolbox"], "gap": [0, 0], "container": true, "n": 3},
		{"op": "scatter", "rect": [r.position.x, r.position.y + 2, r.size.x, maxi(1, r.size.y - 2)], "kinds": ["box", "crate"], "n": 2, "wall": true, "container": 0.7},
	])


## A home left in a hurry (the demo starts in it): a mattress on the floor of the living room, a bag, boxes in a corner, glass under them.
func start_extras(cv, _rng: RandomNumberGenerator) -> void:
	for a in cv.areas:
		if not bool(a.indoor):
			continue
		var r: Rect2i = a.rect
		match String(a.name):
			"living room":
				put(cv, "bedroll", r.end.x - 1, r.position.y)
				put(cv, "dropped_bag", r.end.x - 2, r.end.y - 1)
				put(cv, "papers", r.position.x, r.end.y - 1)
			"kitchen":
				try_spots(cv, "box", [Vector2i(r.end.x - 1, r.end.y - 1), Vector2i(r.end.x - 1, r.position.y)], true)
				put(cv, "papers", r.position.x + 1, r.end.y - 1)
			"bedroom":
				try_spots(cv, "box", [Vector2i(r.end.x - 1, r.end.y - 1), Vector2i(r.position.x, r.end.y - 1)], true)
				put(cv, "broken_glass", r.position.x + 1, r.end.y - 1)
			"utility":
				try_spots(cv, "crate", [Vector2i(r.end.x - 1, r.end.y - 1), Vector2i(r.position.x, r.end.y - 1), Vector2i(r.end.x - 1, r.position.y)], true)
				put(cv, "papers", r.position.x + 1, r.end.y - 1)


# --------------------------------------------------------------------- the yard --

## The path from the door to the street, the step, bushes beside it, a mailbox, a bin, then in the back whatever fits (a garden bed, a shed, a bench, a swing set), a car on gravel, a fence or
## hedge across the front. The start lot gets only the path and the front step. `home`: a house (a yard); else a shop, a works, a public building (the path, the steps, a bin or a bike).
## `door`: the tile outside the front door (lot coordinates), `back_door` the tile outside a back door on the far side (or (-1, -1)), `house` the bounding box of the building,
## `garage` the tile of a garage door's first cell (or (-1, -1)). Returns {"ground": [[x, y, code]], "lines": [[x, y, code]], "gates": [...], "drive": Rect2i} (lot coordinates).
func dress_lot(cv, rng: RandomNumberGenerator, kind: String, lot: Rect2i, front: String, house: Rect2i, door: Vector2i, back_door: Vector2i, garage: Vector2i, start: bool, fenced: bool, home: bool, size_limit: int) -> Dictionary:
	var lw := lot.size.x
	var lh := lot.size.y
	var out := {"ground": [], "lines": [], "gates": [], "drive": Rect2i()}
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
	if back_door.x >= 0 and back_door.y >= 0 and back_door.y < lh:
		var bo = cv._decor("step", back_door.x - 1, back_door.y, 0.0, 0.0)
		if bo != null:
			bo["facing"] = "n" if south else "s"
			bo["variant"] = step_variant
	# a garage's drive: gravel from its door to the street
	if garage.x >= 0:
		var gy0 := (garage.y + 1) if south else 0
		var gy1 := lh if south else garage.y
		var dr := Rect2i(garage.x, gy0, 2, gy1 - gy0)
		if dr.size.y >= 1:
			for yy in range(dr.position.y, dr.end.y):
				for xx in [dr.position.x, dr.position.x + 1]:
					out.ground.append([xx, yy, gravel_code])
			cv._keep_rect(dr, true)
			out.drive = Rect2i(dr.position.x + lot.position.x, dr.position.y + lot.position.y, dr.size.x, dr.size.y)
	var row_front := lh - 2 if south else 1
	var row_edge := lh - 1 if south else 0
	var row_door := door.y
	# a lot that fronts the edge of the map has no street: its front yard is only reached along its sides, so nothing is put across it
	var closed_front := (not south and lot.position.y <= 2) or (south and lot.end.y >= size_limit - 2)
	if not home:
		if not closed_front and rng.randf() < 0.4:
			try_spots(cv, "bin", [Vector2i(house.position.x - 1, row_door), Vector2i(house.end.x, row_door)], false, true)
		if rng.randf() < 0.1:
			put(cv, "bike", dx0 + 3, row_door + dir, false, true)
		return out
	# a fence or hedge across the front, with a gap for the path (a third of the open lots)
	if not fenced and not closed_front and rng.randf() < 0.34:
		var styles := [1, 1, 2, 2, 3, 4, 5]
		var style: int = styles[rng.randi() % styles.size()]
		var gx := dx0 - 1
		for xx in lw:
			if xx >= gx and xx < gx + 4:
				continue
			if cv.is_open(xx, row_front) and cv.terrain[row_front * lw + xx] == int(tids.GRASS):
				cv.solid[row_front * lw + xx] = 1
				out.lines.append([xx, row_front, style])
		if style <= 2:
			out.gates.append({"x": gx, "y": row_front, "w": 4, "orient": "h"})
	# beside the step
	if not closed_front:
		for bx in [dx0 - 2, dx0 + 3]:
			if rng.randf() < 0.6:
				put(cv, "bush", bx, row_door, false, true)
		if rng.randf() < 0.7:
			try_spots(cv, "mailbox", [Vector2i(dx0 + 3, row_edge), Vector2i(dx0 - 2, row_edge), Vector2i(dx0 + 4, row_edge)], false, true)
		if rng.randf() < 0.55:
			try_spots(cv, "bin", [Vector2i(house.position.x - 1, row_door), Vector2i(house.end.x, row_door), Vector2i(house.end.x, row_door - dir)], false, true)
	if rng.randf() < 0.12:
		put(cv, "bike", dx0 + 3, row_door + dir, false, true)
	# a car on a gravel pad in the front yard
	if kind != "terrace" and not closed_front and garage.x < 0 and rng.randf() < 0.14:
		var cars: Array = [Vector2i(dx0 + 3, row_edge if south else 0), Vector2i(dx0 - 5, row_edge if south else 0)]
		for cp in cars:
			var cy: int = cp.y - 1 if south else cp.y
			if cp.x >= 0 and cp.x + 4 <= lw and put(cv, "car_h", cp.x, cy, false, true):
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
			ground_round(cv, out, scatter(cv, rng, "garden_bed", 1, lw - 4, back_y0, back_y0 + back_rows - 1), TownArt.GROUNDS.find("dirt_path") + 1)
		if back_rows >= 2 and rng.randf() < 0.2:
			ground_round(cv, out, scatter(cv, rng, "shed", 1, lw - 4, back_y0, back_y0 + back_rows - 2), gravel_code)
		if back_rows >= 2 and kind != "terrace" and rng.randf() < 0.1:
			scatter(cv, rng, "swing_set", 1, lw - 4, back_y0, back_y0 + back_rows - 2)
		if rng.randf() < 0.14:
			scatter(cv, rng, "bench", 1, lw - 3, back_y0, back_y0 + back_rows - 1)
		if rng.randf() < 0.12:
			scatter(cv, rng, "bin", 0, lw - 1, back_y0, back_y0 + back_rows - 1)
	# litter in the grass
	# (not near the lot's edge: a decal is a picture a little wider than its tile, and the start lot's clear ring must stay clear of its neighbours' litter)
	cv._run_ops([{"op": "decals", "rect": [2, 2, maxi(1, lw - 4), maxi(1, lh - 4)], "kinds": ["papers", "dropped_bag"], "n": {"r": [0, 2]}}])
	return out


## `kind` on a free spot of a region of the lot (a few tries); the thing, or null.
func scatter(cv, rng: RandomNumberGenerator, kind: String, x0: int, x1: int, y0: int, y1: int):
	for t in 10:
		var tx := rng.randi_range(x0, maxi(x0, x1))
		var ty := rng.randi_range(y0, maxi(y0, y1))
		if put(cv, kind, tx, ty, false, true):
			return cv.objects[cv.objects.size() - 1]
	return null


## The ground round a thing of the back yard (bare soil round a garden bed, gravel before a shed), as codes for the lot's `ground` list.
func ground_round(cv, out: Dictionary, o, code: int) -> void:
	if o == null:
		return
	var x0 := int(round(float(o.cx) - float(o.w) / 2.0)) - 1
	var y0 := int(round(float(o.cy) - float(o.h) / 2.0)) - 1
	for yy in range(y0, y0 + int(o.h) + 2):
		for xx in range(x0, x0 + int(o.w) + 2):
			if cv._in(xx, yy) and cv.terrain[yy * cv.W + xx] == int(tids.GRASS) and cv.solid[yy * cv.W + xx] == 0:
				out.ground.append([xx, yy, code])


# ------------------------------------------------------------------ the objects --

## Gives the objects of a canvas their kit fields: the item, the variant, the facing (the back to the wall it stands at), and the container's `closed` state.
func kitify(cv, rng: RandomNumberGenerator) -> void:
	var props: Dictionary = cv.props
	for o in cv.objects:
		var p: Dictionary = props.get(String(o.kind), {})
		if p.has("kit"):
			kit_set(o, p, rng)
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


func kit_set(o: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
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
