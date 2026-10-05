## How high the town's things stand (the shot-over-furniture fix): in a top-down game a bed, a sofa, a table or a counter must not stop a bullet, a blow or the dead's eye, while a wall, a
## wardrobe, a fridge, a bookshelf, a locker or a machine does. The lists are DATA (assets/data/prop_heights.json: a kind is `low` or `tall`; a kind in neither is tall, what it did before).
##
## `shot_low_grid(objects, W, H)` is what the generator keeps as `data.shot_low` (scripts/town/town_gen.gd `_finish_data`): a byte per tile, 1 on the footprint of a LOW solid prop, 0 everywhere
## else. It is only the tiles that are low: whatever the world's solid grids say is shut (`solid_p`, `solid_z`) stays shut for walking, for the dead and for the pathfinder, and a tile of
## `solid_p` blocks a shot unless this grid says it is a low prop's; so a wall, a barricade or a fence that is built later (the perimeter changes `solid_p`) still stops a bullet. The grid is
## made from the seed with the town (saved nowhere); a game without it (the school, the raid sites) shoots exactly as before.
extends RefCounted

const PATH := "res://assets/data/prop_heights.json"

## kind -> true when LOW (a lazy cache of the file; a kind that is not a key is tall).
static var _low := {}
static var _read := false


## Whether a prop of this kind is low (a shot, a blow and a look go over it).
static func is_low(kind: String) -> bool:
	if not _read:
		_read = true
		if FileAccess.file_exists(PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				for k in parsed.get("low", []):
					_low[String(k)] = true
				for k in parsed.get("tall", []):
					_low.erase(String(k))    # (a kind named in both lists is tall)
	return _low.has(kind)


## The grid of the tiles under low props: 1 on the footprint (`w` x `h` tiles round the centre `cx`, `cy`) of every solid object whose kind is low, except where a tall solid object also
## stands (a tile that any tall thing shuts is not let through).
static func shot_low_grid(objects: Array, w: int, h: int) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(w * h)
	var tall: Array = []
	for o in objects:
		if not bool(o.get("solid", false)):
			continue
		if not is_low(String(o.kind)):
			tall.append(o)
			continue
		_stamp(grid, o, w, h, 1)
	for o in tall:
		_stamp(grid, o, w, h, 0)
	return grid


## Sets the tiles of an object's footprint to `value`.
static func _stamp(grid: PackedByteArray, o: Dictionary, w: int, h: int, value: int) -> void:
	var tx := roundi(float(o.cx) - float(o.w) / 2.0)
	var ty := roundi(float(o.cy) - float(o.h) / 2.0)
	for yy in int(o.h):
		for xx in int(o.w):
			var x := tx + xx
			var y := ty + yy
			if x >= 0 and y >= 0 and x < w and y < h:
				grid[y * w + x] = value


## How many solid props of each class a list of objects has: {"low": n, "tall": n}.
static func count(objects: Array) -> Dictionary:
	var out := {"low": 0, "tall": 0}
	for o in objects:
		if bool(o.get("solid", false)):
			out["low" if is_low(String(o.kind)) else "tall"] += 1
	return out
