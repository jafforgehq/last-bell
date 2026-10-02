extends "res://tests/case.gd"
## The lots' data (round 9): assets/data/lots.json, the three lots of the ring of streets round the compound, the
## ten places the dead come in (the mouths, each closed by a wall plot, or two), the ring plots to build on, and
## the kits the walls are made of. These tests say the data is sound against the map (assets/data/map.json), not
## what the module does with it (test_lots.gd): the mouths' tiles are open ground clear of props and old walls, a
## wall on them closes its street (a flood fill of the dead's grid from the spawn point does not get past it,
## with the other mouths shut too), the slots are on the outer face and the posts behind it, the ring plots are
## 3 by 3 on open ground that people can walk to from the Main gate, the kits are the compound's own sections
## with their health, and every mouth has a kit that fits it.
##
## Every rule is a function that returns the sentences of what is wrong with a set of data (none when it is
## sound), so that the tests at the end can doctor a copy in memory and prove each rule fails when it should.
## The last test checks that the real module (`sim.lots`) reads the file the way these tests do.

const Helpers := preload("res://tests/helpers.gd")

const PATH := "res://assets/data/lots.json"
const MAP_PATH := "res://assets/data/map.json"
const PLOTS_PATH := "res://assets/data/plots.json"

const LOT_IDS := ["north", "west", "east"]
const LOT_KEYS := ["id", "name", "blurb", "claim", "mouths", "plots", "sealed_bonus"]
const MOUTH_KEYS := ["id", "name", "lot", "spawn", "dir", "side", "rect", "center", "anchor", "length", "kits", "slots", "post", "outside", "inside"]
const PLOT_KEYS := ["id", "name", "kind", "lot", "pos", "size", "work"]
const KIT_KEYS := ["name", "blurb", "dir", "length", "hp", "scrap", "work", "template", "thick", "stand"]
const SLOT_KEYS := ["x", "y", "ax", "ay", "face"]
## The walls the kits are made from (the `kind` of the compound's own sections).
const KIT_KINDS := ["container", "pallets", "bus", "car", "chainlink", "blocks"]

## How thick a wall is, in tiles (the old walls are three tiles thick too).
const THICK := 3
## How much a kit may be stretched or squeezed along its length to fit a mouth (a share of its own length).
const SCALE_MAX := 0.15
## How near the spawn point a wall may stand, in tiles, from the point to the wall's outer face. The ends of the
## north street and the two alleys at the sides have their spawn point on the map's edge (x 0.5 and 83.5) and the
## street goes on at the third tile (x 3), so the wall can only stand 2.5 tiles from it: the dead have two free
## tiles to stand in before it.
const MIN_FROM_SPAWN := 2.5
## What the old sections do (read from the map by `_convention`, these are what the file's numbers are compared with).
const SLOT_SPACING := 0.9
## The people at a site stand at the work spot and a step either side (build.gd's STAND_OFFSETS).
const STANDS := [Vector2(0.0, 0.0), Vector2(1.1, 0.0), Vector2(-1.1, 0.0)]
## How far apart two lots are kept (tiles): a person fits between them (as the yard's own plots).
const LOT_GAP := 0.9
## Where a second lot may stand beside "a lot": a tile of open ground between them (found by trying: the street
## to the west of the wreck is open ground clear of everything).
const GAP_SPOT := Vector2(-4.0, 0.0)
## The tile just outside the Main gate: where the people come out into the ring.
const GATE_OUTSIDE := Vector2i(39, 14)
## The ground in front of the gate, where the crew goes out and the recruits come in.
const GATE_LANE := Rect2(36.0, 4.0, 6.0, 11.0)
## The compound (yard with its walls and corner towers) and the school, in tiles: never ring ground.
const YARD := Rect2(17.0, 15.0, 50.0, 30.0)
const SCHOOL := Rect2(20.0, 45.0, 44.0, 15.0)
## The things of the map that stand on the ground. A wall (and a lot) is never on one of them; a lot is never on the
## flat marks or the awnings either, nor under the crown of a tree.
const SOLID_PROPS := ["car", "pickup", "lamppost", "hydrant", "trashcan", "trashbags", "bench"]
const FLAT_PROPS := ["corpse", "manhole", "awning"]
## The streets by which the ring plots are shared out: the north street and the top of both roads (to this row)
## are the north lot's, the rest by the side of the map.
const NORTH_ROWS := 30.0
const MIDDLE := 42.0
## The mouths that fit one kit only (the rest at least two): the east alley on the north row is three tiles of
## sidewalk between a tree trunk and a bench.
const ONE_KIT_OK := ["north_alley_east"]

static var _map_cache := {}
static var _grid_cache := {}

## The file under test (a check of these tests themselves points a function at a doctored copy instead).
var data_path := PATH


# ---------------------------------------------------------------------- helpers --

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The lots' data, or {} (and a failure) when the file is missing or does not parse.
func _data() -> Dictionary:
	var d := _read(data_path)
	check(not d.is_empty(), "%s exists and parses as an object" % data_path)
	return d


func _map() -> Dictionary:
	if _map_cache.is_empty():
		_map_cache = _read(MAP_PATH)
	return _map_cache


func _w() -> int:
	return int(_map().get("W", 84))


func _h() -> int:
	return int(_map().get("H", 64))


## A copy of one of the map's walking grids (`solidZ` for the dead, `solidP` for people), 1 where it is shut.
func _grid(key: String) -> PackedByteArray:
	if not _grid_cache.has(key):
		var src: Array = _map().get(key, [])
		var g := PackedByteArray()
		g.resize(src.size())
		for i in src.size():
			g[i] = int(src[i])
		_grid_cache[key] = g
	return (_grid_cache[key] as PackedByteArray).duplicate()


func _spawns() -> Array:
	var s = _map().get("spawns", [])
	return s if s is Array else []


func _spawn_tile(i: int) -> Vector2i:
	var s: Array = _spawns()[i]
	return Vector2i(floori(float(s[0])), floori(float(s[1])))


func _is_number(x) -> bool:
	return typeof(x) == TYPE_FLOAT or typeof(x) == TYPE_INT


func _is_whole(x) -> bool:
	return _is_number(x) and float(x) == floorf(float(x))


func _is_pair(x) -> bool:
	return x is Array and x.size() == 2 and _is_number(x[0]) and _is_number(x[1])


func _dicts(a) -> Array:
	var out: Array = []
	if a is Array:
		for x in a:
			if x is Dictionary:
				out.append(x)
	return out


func _vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _tile(a) -> Vector2i:
	return Vector2i(floori(float(a[0])), floori(float(a[1])))


## Sentence breaks inside a text (a full stop, a question or an exclamation mark, a space and a capital).
func _inner_breaks(text: String) -> int:
	var re := RegEx.create_from_string("[.!?]\\s+[A-Z]")
	return re.search_all(text).size()


func _open(grid: PackedByteArray, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < _w() and y < _h() and grid[y * _w() + x] == 0


func _reached(mask: PackedByteArray, t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < _w() and t.y < _h() and mask[t.y * _w() + t.x] != 0


## The tiles (as a mask) a walker can get to from `start` over the open tiles of `grid`. Four ways: the path grids
## only go diagonally where both the tiles beside the step are free, so that finds nothing more.
func _flood(grid: PackedByteArray, start: Vector2i) -> PackedByteArray:
	var w := _w()
	var h := _h()
	var seen := PackedByteArray()
	seen.resize(w * h)
	if start.x < 0 or start.y < 0 or start.x >= w or start.y >= h or grid[start.y * w + start.x] != 0:
		return seen
	var queue := PackedInt32Array()
	queue.append(start.y * w + start.x)
	seen[start.y * w + start.x] = 1
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % w
		@warning_ignore("integer_division")
		var y := i / w
		if x > 0 and seen[i - 1] == 0 and grid[i - 1] == 0:
			seen[i - 1] = 1
			queue.append(i - 1)
		if x < w - 1 and seen[i + 1] == 0 and grid[i + 1] == 0:
			seen[i + 1] = 1
			queue.append(i + 1)
		if y > 0 and seen[i - w] == 0 and grid[i - w] == 0:
			seen[i - w] = 1
			queue.append(i - w)
		if y < h - 1 and seen[i + w] == 0 and grid[i + w] == 0:
			seen[i + w] = 1
			queue.append(i + w)
	return seen


## Shuts the tiles of these [x0, y0, x1, y1] rectangles.
func _shut(grid: PackedByteArray, rects: Array) -> void:
	var w := _w()
	var h := _h()
	for r in rects:
		for ty in range(int(r[1]), int(r[3]) + 1):
			for tx in range(int(r[0]), int(r[2]) + 1):
				if tx >= 0 and ty >= 0 and tx < w and ty < h:
					grid[ty * w + tx] = 1


func _rect(m: Dictionary) -> Array:
	var r: Array = m.get("rect", [0, 0, 0, 0])
	return [int(r[0]), int(r[1]), int(r[2]), int(r[3])]


func _rects(ms: Array) -> Array:
	var out: Array = []
	for m in ms:
		out.append(_rect(m))
	return out


func _rect2(r: Array) -> Rect2:
	return Rect2(float(r[0]), float(r[1]), float(r[2] - r[0] + 1), float(r[3] - r[1] + 1))


## The way the dead come from, as a compass side: where the spawn point is seen from the wall.
func _side(m: Dictionary) -> String:
	var r := _rect(m)
	var sp: Array = _spawns()[int(m.get("spawn", 0))]
	if String(m.get("dir", "h")) == "h":
		return "N" if float(sp[1]) < float(r[1]) else "S"
	return "W" if float(sp[0]) < float(r[0]) else "E"


## The line of the wall's outer face, the side the dead stand on (a row for a wall running east to west, else a column).
func _outer(m: Dictionary) -> float:
	var r := _rect(m)
	match _side(m):
		"N":
			return float(r[1])
		"S":
			return float(r[3] + 1)
		"W":
			return float(r[0])
	return float(r[2] + 1)


## The line of its inner face.
func _inner(m: Dictionary) -> float:
	var r := _rect(m)
	match _side(m):
		"N":
			return float(r[3] + 1)
		"S":
			return float(r[1])
		"W":
			return float(r[2] + 1)
	return float(r[0])


## Which way is away from the dead: +1 when the inside lies towards larger coordinates.
func _inward(m: Dictionary) -> float:
	return 1.0 if _side(m) in ["N", "W"] else -1.0


## Where along the wall the ground just outside its outer face is open for the dead (coordinates of the tiles).
func _open_span(m: Dictionary, z: PackedByteArray) -> Array:
	var r := _rect(m)
	var side := _side(m)
	var out: Array = []
	if String(m.get("dir", "h")) == "h":
		var ty: int = r[1] - 1 if side == "N" else r[3] + 1
		for tx in range(r[0], r[2] + 1):
			if _open(z, tx, ty):
				out.append(tx)
	else:
		var tx: int = r[0] - 1 if side == "W" else r[2] + 1
		for ty in range(r[1], r[3] + 1):
			if _open(z, tx, ty):
				out.append(ty)
	return out


## The tiles of every section the compound's walls are made of (the old walls: never ground of a mouth).
func _old_wall_tiles() -> Dictionary:
	var out := {}
	for s in _map().get("segments", []):
		for t in s.tiles:
			out[int(t)] = true
	return out


func _segment(id: int) -> Dictionary:
	for s in _map().get("segments", []):
		if int(s.id) == id:
			return s
	return {}


## What the old sections do, read from the first of them (the north container): how far inside the wall's
## outer face the dead stand, how far outside it they are met, and how far apart they stand.
func _convention() -> Dictionary:
	var s := _segment(0)
	var top := 1000000
	for t in s.tiles:
		@warning_ignore("integer_division")
		top = mini(top, int(t) / _w())
	var a: Dictionary = s.slots[0]
	var b: Dictionary = s.slots[1]
	return {
		"stand": float(a.y) - float(top),
		"approach": float(top) - float(a.ay),
		"spacing": float(b.x) - float(a.x),
	}


## The inner face of an old section (the line its people stand behind) and the section's outer face.
func _faces(s: Dictionary) -> Dictionary:
	var lo_x := 1000000
	var hi_x := -1
	var lo_y := 1000000
	var hi_y := -1
	for t in s.tiles:
		var x := int(t) % _w()
		@warning_ignore("integer_division")
		var y := int(t) / _w()
		lo_x = mini(lo_x, x)
		hi_x = maxi(hi_x, x)
		lo_y = mini(lo_y, y)
		hi_y = maxi(hi_y, y)
	match String(s.side):
		"N":
			return {"inner": float(hi_y + 1), "outer": float(lo_y)}
		"S":
			return {"inner": float(lo_y), "outer": float(hi_y + 1)}
		"W":
			return {"inner": float(hi_x + 1), "outer": float(lo_x)}
	return {"inner": float(lo_x), "outer": float(hi_x + 1)}


## The map objects of these kinds that are not decoration of the ground.
func _objects(kinds: Array) -> Array:
	var out: Array = []
	for o in _map().get("objects", []):
		if String(o.kind) in kinds:
			out.append(o)
	return out


## Whether a point is inside a map object's rectangle (the object's own turn undone).
func _in_object(o: Dictionary, p: Vector2) -> bool:
	var c := cos(-float(o.a))
	var s := sin(-float(o.a))
	var dx := p.x - float(o.cx)
	var dy := p.y - float(o.cy)
	var lx := dx * c - dy * s
	var ly := dx * s + dy * c
	return absf(lx) <= float(o.w) / 2.0 and absf(ly) <= float(o.h) / 2.0


## The kind of the first of these objects that has a point of `area` in it ("" for none), sampled as the yard's lots are.
func _object_under(area: Rect2, things: Array) -> String:
	var y := area.position.y
	while y <= area.end.y + 1.0e-9:
		var x := area.position.x
		while x <= area.end.x + 1.0e-9:
			for o in things:
				if _in_object(o, Vector2(x, y)):
					return String(o.kind)
			x += 0.3
		y += 0.3
	return ""


## The crown of the tree in the map that overlaps this area ("" for none).
func _crown_over(area: Rect2) -> String:
	var box: Array = _map().get("tree", {}).get("box", [-1.4, -2.9, 1.4, 0.3])
	for t in _map().get("trees", []):
		var crown := Rect2(float(t.x) + float(box[0]), float(t.y) + float(box[1]), float(box[2]) - float(box[0]), float(box[3]) - float(box[1]))
		if crown.intersects(area):
			return "tree at (%s, %s)" % [str(t.x), str(t.y)]
	return ""


func _ids_of(plots_json: Array) -> Dictionary:
	var out := {}
	for p in plots_json:
		if p is Dictionary:
			out[String(p.get("id", ""))] = true
	return out


## The ids the yard's own plots use (plots.json): a ring plot or mouth may not take one.
func _yard_plots() -> Array:
	var d := _read(PLOTS_PATH)
	return _dicts(d.get("plots", []))


func _snake(id: String) -> bool:
	return RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(id) != null


# ---------------------------------------------------------------------- the doc (rule) --

## What the doc does not say: it names every field of the file.
func _doc_problems(d: Dictionary) -> Array:
	var out: Array = []
	var doc := String(d.get("_doc", ""))
	if doc.length() < 1500:
		out.append("the doc is a real explanation, not a line: %d characters" % doc.length())
	var words: Array = []
	words.append_array(LOT_KEYS)
	words.append_array(MOUTH_KEYS)
	words.append_array(PLOT_KEYS)
	words.append_array(KIT_KEYS)
	words.append_array(["passage", "claim", "scrap", "cleared", "day", "ax", "ay", "face", "pos", "what", "work", "size", "kind", "ring", "spawn"])
	for k in words:
		if not doc.contains(String(k)):
			out.append("the doc does not explain '%s'" % String(k))
	return out


# --------------------------------------------------------------- the lots (rules) --

## What is wrong with the lots, the claim, and who owns which mouth and plot.
func _lot_problems(d: Dictionary) -> Array:
	var out: Array = []
	for k in ["lots", "mouths", "plots", "kits", "passage", "_doc"]:
		if not d.has(k):
			out.append("the data has no '%s'" % k)
	var lots := _dicts(d.get("lots", []))
	var mouths := _dicts(d.get("mouths", []))
	var plots := _dicts(d.get("plots", []))
	var mouth_ids := _ids_of(mouths)
	var plot_ids := _ids_of(plots)
	var ids: Array = []
	for l in lots:
		ids.append(String(l.get("id", "")))
	if ids != LOT_IDS:
		out.append("the lots are north, west and east, in that order: %s" % str(ids))
	var listed_mouths := {}
	var listed_plots := {}
	for l in lots:
		var id := String(l.get("id", ""))
		for k in l.keys():
			if not k in LOT_KEYS:
				out.append("%s: unknown key '%s'" % [id, k])
		for k in LOT_KEYS:
			if not l.has(k):
				out.append("%s: has no '%s'" % [id, k])
		if String(l.get("name", "")).strip_edges() == "":
			out.append("%s: has no name" % id)
		var blurb := String(l.get("blurb", ""))
		if blurb.length() < 40 or blurb.length() > 230 or _inner_breaks(blurb) > 1 or not blurb.ends_with(".") or blurb.contains("{") or blurb.contains("}"):
			out.append("%s: the blurb is one or two plain sentences of 40 to 230 characters ending in a full stop" % id)
		var c = l.get("claim", {})
		if not (c is Dictionary and c.keys().size() == 3 and c.has("scrap") and c.has("cleared") and c.has("day")):
			out.append("%s: the claim is {scrap, cleared, day}" % id)
		else:
			if not (_is_whole(c.scrap) and int(c.scrap) >= 20 and int(c.scrap) <= 120):
				out.append("%s: the claim's scrap is a whole 20 to 120: %s" % [id, str(c.scrap)])
			if not (_is_whole(c.cleared) and int(c.cleared) >= 0 and int(c.cleared) <= 4):
				out.append("%s: the claim's cleared places are a whole 0 to 4: %s" % [id, str(c.cleared)])
			if not (_is_whole(c.day) and int(c.day) >= 2 and int(c.day) <= 15):
				out.append("%s: the claim's day is a whole 2 to 15: %s" % [id, str(c.day)])
		if not (_is_number(l.get("sealed_bonus")) and float(l.sealed_bonus) >= 1.0 and float(l.sealed_bonus) <= 6.0):
			out.append("%s: the sealed bonus is a small lift of 1 to 6" % id)
		var lm = l.get("mouths", [])
		var lp = l.get("plots", [])
		if not (lm is Array and not lm.is_empty() and lp is Array and not lp.is_empty()):
			out.append("%s: has mouths and plots" % id)
			continue
		for m in lm:
			var mid := String(m)
			if not mouth_ids.has(mid):
				out.append("%s lists the mouth '%s', which is not in the data" % [id, mid])
			if listed_mouths.has(mid):
				out.append("the mouth '%s' is listed by two lots" % mid)
			listed_mouths[mid] = id
		for p in lp:
			var pid := String(p)
			if not plot_ids.has(pid):
				out.append("%s lists the plot '%s', which is not in the data" % [id, pid])
			if listed_plots.has(pid):
				out.append("the plot '%s' is listed by two lots" % pid)
			listed_plots[pid] = id
	for m in mouths:
		var mid := String(m.get("id", ""))
		if listed_mouths.get(mid, "") != String(m.get("lot", "-")):
			out.append("%s: belongs to lot '%s' but is listed by '%s'" % [mid, String(m.get("lot", "")), str(listed_mouths.get(mid, "no lot"))])
	for p in plots:
		var pid := String(p.get("id", ""))
		if listed_plots.get(pid, "") != String(p.get("lot", "-")):
			out.append("%s: belongs to lot '%s' but is listed by '%s'" % [pid, String(p.get("lot", "")), str(listed_plots.get(pid, "no lot"))])
	# the claim: the north street first and cheapest, the others later and dearer
	if lots.size() == 3 and out.is_empty():
		var a: Dictionary = lots[0].claim
		var b: Dictionary = lots[1].claim
		var e: Dictionary = lots[2].claim
		if not (int(a.scrap) < int(b.scrap) and int(a.scrap) < int(e.scrap)):
			out.append("the north lot is the cheapest: %s against %s and %s scrap" % [str(a.scrap), str(b.scrap), str(e.scrap)])
		if not (int(a.day) < int(b.day) and int(b.day) <= int(e.day)):
			out.append("the lots open one after another: day %s, %s, %s" % [str(a.day), str(b.day), str(e.day)])
		if not (int(a.cleared) <= int(b.cleared) and int(b.cleared) <= int(e.cleared)):
			out.append("each lot asks as many cleared places as the one before: %s, %s, %s" % [str(a.cleared), str(b.cleared), str(e.cleared)])
		if int(a.day) > 4 or int(a.scrap) > 60 or int(a.cleared) > 1:
			out.append("the north lot is the first and a modest claim (day 4, 60 scrap, one place at the most)")
	return out


# -------------------------------------------------------------- the mouths (rules) --

## What is wrong with each mouth (a wall plot) in itself: its fields, its tiles on the map, how far it is from
## its spawn point, and how the plots of one spawn point share the street.
func _mouth_problems(d: Dictionary) -> Array:
	var out: Array = []
	var z := _grid("solidZ")
	var pg := _grid("solidP")
	var w := _w()
	var h := _h()
	var spawns := _spawns()
	var old := _old_wall_tiles()
	var props := _objects(SOLID_PROPS)
	var lot_ids := {}
	for l in _dicts(d.get("lots", [])):
		lot_ids[String(l.get("id", ""))] = true
	var yard_ids := _ids_of(_yard_plots())
	var ring_ids := _ids_of(_dicts(d.get("plots", [])))
	var seen := {}
	var names := {}
	var kept: Array = []
	for m in _dicts(d.get("mouths", [])):
		var id := String(m.get("id", ""))
		if not _snake(id):
			out.append("the mouth id '%s' is lowercase with no spaces" % id)
		if seen.has(id) or yard_ids.has(id) or ring_ids.has(id):
			out.append("%s: the id is used twice" % id)
		seen[id] = true
		for k in m.keys():
			if not k in MOUTH_KEYS:
				out.append("%s: unknown key '%s'" % [id, k])
		var complete := true
		for k in MOUTH_KEYS:
			if not m.has(k):
				out.append("%s: has no '%s'" % [id, k])
				complete = false
		if not complete:
			continue
		if String(m.name).strip_edges() == "" or String(m.name).length() > 48:
			out.append("%s: has a name of at most 48 characters" % id)
		if names.has(String(m.name)):
			out.append("%s: the name '%s' is used twice" % [id, String(m.name)])
		names[String(m.name)] = true
		if not lot_ids.has(String(m.lot)):
			out.append("%s: lot '%s' is not a lot" % [id, String(m.lot)])
		var dir := String(m.dir)
		var r = m.rect
		if not (dir in ["h", "v"] and r is Array and r.size() == 4 and _is_whole(r[0]) and _is_whole(r[1]) and _is_whole(r[2]) and _is_whole(r[3]) and _is_whole(m.spawn) and int(m.spawn) >= 0 and int(m.spawn) < spawns.size()):
			out.append("%s: dir is h or v, rect is [x0, y0, x1, y1] in whole tiles and spawn is the index of a spawn point" % id)
			continue
		var rc := _rect(m)
		if rc[0] > rc[2] or rc[1] > rc[3] or rc[0] < 0 or rc[1] < 0 or rc[2] >= w or rc[3] >= h:
			out.append("%s: the rect %s is not a rectangle on the map" % [id, str(rc)])
			continue
		var long_side: int = (rc[2] - rc[0] + 1) if dir == "h" else (rc[3] - rc[1] + 1)
		var thick: int = (rc[3] - rc[1] + 1) if dir == "h" else (rc[2] - rc[0] + 1)
		if thick != THICK:
			out.append("%s: the wall is %d tiles thick, not %d" % [id, thick, THICK])
		if not (_is_number(m.length) and float(m.length) == float(long_side)):
			out.append("%s: the length is the long side of the rect (%d tiles): %s" % [id, long_side, str(m.length)])
		var mid := Vector2(float(rc[0] + rc[2] + 1) / 2.0, float(rc[1] + rc[3] + 1) / 2.0)
		if not (_is_pair(m.center) and _vec(m.center).is_equal_approx(mid)):
			out.append("%s: the centre is the middle of the rect, %s: %s" % [id, str(mid), str(m.center)])
		if String(m.side) != _side(m):
			out.append("%s: the side the dead come from is %s: %s" % [id, _side(m), str(m.side)])
		# the tiles
		var shut_tiles: Array = []
		var old_tiles: Array = []
		for ty in range(rc[1], rc[3] + 1):
			for tx in range(rc[0], rc[2] + 1):
				if z[ty * w + tx] != 0 or pg[ty * w + tx] != 0:
					shut_tiles.append(Vector2i(tx, ty))
				if old.has(ty * w + tx):
					old_tiles.append(Vector2i(tx, ty))
		if not shut_tiles.is_empty():
			out.append("%s: the wall covers shut ground %s" % [id, str(shut_tiles.slice(0, 4))])
		if not old_tiles.is_empty():
			out.append("%s: the wall covers an old wall section %s" % [id, str(old_tiles.slice(0, 4))])
		var area := _rect2(rc).grow(-0.01)
		var hit := _object_under(area, props)
		if hit != "":
			out.append("%s: the wall is under a %s" % [id, hit])
		if _rect2(rc).intersects(YARD) or _rect2(rc).intersects(SCHOOL):
			out.append("%s: the wall is inside the compound" % id)
		# the spawn point: outside the wall, and at least MIN_FROM_SPAWN tiles from it
		var sp := _vec(spawns[int(m.spawn)])
		var box := _rect2(rc)
		var nearest := Vector2(clampf(sp.x, box.position.x, box.end.x), clampf(sp.y, box.position.y, box.end.y))
		var far := sp.distance_to(nearest)
		if far < MIN_FROM_SPAWN - 1.0e-9:
			out.append("%s: the wall is within %.1f tiles of the spawn point %s (at least %.1f)" % [id, far, str(sp), MIN_FROM_SPAWN])
		# the tile outside and the tile inside: one each side of the wall, across its face
		var side := _side(m)
		var oi = m.outside
		var ii = m.inside
		if not (_is_pair(oi) and _is_pair(ii) and _is_whole(oi[0]) and _is_whole(oi[1]) and _is_whole(ii[0]) and _is_whole(ii[1])):
			out.append("%s: outside and inside are tiles [x, y]" % id)
		else:
			var ot := Vector2i(int(oi[0]), int(oi[1]))
			var it := Vector2i(int(ii[0]), int(ii[1]))
			var across_o: bool = (ot.y == int(_outer(m)) + (-1 if side == "N" else 0) and ot.x >= rc[0] and ot.x <= rc[2]) if dir == "h" else (ot.x == int(_outer(m)) + (-1 if side == "W" else 0) and ot.y >= rc[1] and ot.y <= rc[3])
			var across_i: bool = (it.y == int(_inner(m)) + (0 if side == "N" else -1) and it.x >= rc[0] and it.x <= rc[2]) if dir == "h" else (it.x == int(_inner(m)) + (0 if side == "W" else -1) and it.y >= rc[1] and it.y <= rc[3])
			if not across_o:
				out.append("%s: the outside tile %s is not the tile across the outer face from the wall" % [id, str(ot)])
			if not across_i:
				out.append("%s: the inside tile %s is not the tile across the inner face from the wall" % [id, str(it)])
			if not (_open(z, ot.x, ot.y) and _open(pg, ot.x, ot.y)):
				out.append("%s: the outside tile %s is not open ground" % [id, str(ot)])
			if not (_open(z, it.x, it.y) and _open(pg, it.x, it.y)):
				out.append("%s: the inside tile %s is not open ground" % [id, str(it)])
		for q in kept:
			if _rect2(rc).intersects(_rect2(q.rect)):
				out.append("%s and %s overlap (their sections would shut the same tiles)" % [id, q.id])
		kept.append({"id": id, "rect": rc})
	# the mouth groups: one for each spawn point, in one or two plots
	var groups := {}
	for m in _dicts(d.get("mouths", [])):
		if _is_whole(m.get("spawn")):
			if not groups.has(int(m.spawn)):
				groups[int(m.spawn)] = []
			groups[int(m.spawn)].append(m)
	for i in spawns.size():
		if not groups.has(i):
			out.append("spawn point %d has no mouth: the dead would walk in there" % i)
	for i in groups:
		if int(i) < 0 or int(i) >= spawns.size():
			out.append("spawn %d is not a spawn point" % int(i))
			continue
		var g: Array = groups[i]
		var first: Dictionary = g[0]
		for m in g:
			if String(m.get("lot", "")) != String(first.get("lot", "")) or String(m.get("dir", "")) != String(first.get("dir", "")):
				out.append("the mouths of spawn point %d are in one lot and run the same way" % int(i))
				break
		if g.size() > 2:
			out.append("spawn point %d has %d wall plots, at most two" % [int(i), g.size()])
		elif g.size() == 2 and out.is_empty():
			var ids: Array = [String(g[0].id), String(g[1].id)]
			ids.sort()
			if not (ids[0].ends_with("_a") and ids[1].ends_with("_b") and ids[0].trim_suffix("_a") == ids[1].trim_suffix("_b")):
				out.append("the two wall plots of spawn point %d are called <name>_a and <name>_b: %s" % [int(i), str(ids)])
			var ra := _rect(g[0])
			var rb := _rect(g[1])
			var horizontal: bool = String(first.dir) == "h"
			var touching: bool = (ra[2] + 1 == rb[0] or rb[2] + 1 == ra[0]) if horizontal else (ra[3] + 1 == rb[1] or rb[3] + 1 == ra[1])
			var aligned: bool = (ra[1] == rb[1] and ra[3] == rb[3]) if horizontal else (ra[0] == rb[0] and ra[2] == rb[2])
			if not (touching and aligned):
				out.append("the two wall plots of spawn point %d lie end to end across the street" % int(i))
			if float(g[0].length) + float(g[1].length) <= 12.0:
				out.append("spawn point %d is split in two but is no wider than the longest kit (12 tiles)" % int(i))
		elif g.size() == 1:
			if String(first.id).ends_with("_a") or String(first.id).ends_with("_b"):
				out.append("%s: a mouth in one piece has no suffix" % String(first.id))
			if float(first.get("length", 0.0)) > 12.0 * (1.0 + SCALE_MAX):
				out.append("%s: a mouth wider than the longest kit is split in two" % String(first.id))
	return out


## The groups the lots are made of: the spawn points of each lot's mouths.
func _lot_spawns(d: Dictionary, lot_id: String) -> Array:
	var out: Array = []
	for m in _dicts(d.get("mouths", [])):
		if String(m.get("lot", "")) == lot_id and not int(m.spawn) in out:
			out.append(int(m.spawn))
	out.sort()
	return out


# --------------------------------------------------- a built wall closes its street --

## What is wrong with how the walls close the ring, found by flood fills of the dead's grid from the spawn points:
## with none built the dead get to every inside tile; with the walls of every mouth built they get to none of the
## ring; and each wall plot is needed (the others built and this one not, the dead get in by it).
func _seal_problems(d: Dictionary) -> Array:
	var out: Array = []
	var z := _grid("solidZ")
	var spawns := _spawns()
	var ms := _dicts(d.get("mouths", []))
	for m in ms:
		if not (m.get("rect") is Array and _is_whole(m.get("spawn")) and int(m.spawn) < spawns.size() and _is_pair(m.get("inside")) and _is_pair(m.get("outside"))):
			return ["the mouths are not in shape to be tested (see the other tests)"]
	var all: Array = _rects(ms)
	# 1. nothing built: every spawn point reaches every inside tile (the ring is open, and these are its mouths)
	var open_reach := {}
	for i in spawns.size():
		open_reach[i] = _flood(z, _spawn_tile(i))
	for m in ms:
		var from: PackedByteArray = open_reach[int(m.spawn)]
		for q in ms:
			if not _reached(from, _tile(q.inside)):
				out.append("%s: with no wall built the dead from spawn point %d do not reach the inside of %s %s" % [String(m.id), int(m.spawn), String(q.id), str(q.inside)])
				break
	# 2. every wall built: the dead keep to their pockets, and the ring is whole
	var shut := z.duplicate()
	_shut(shut, all)
	var ring := _flood(shut, GATE_OUTSIDE)
	if not _reached(ring, GATE_OUTSIDE):
		out.append("the tile outside the Main gate is not open ground")
	for m in ms:
		for key in ["inside"]:
			if not _reached(ring, _tile(m[key])):
				out.append("%s: the ring does not reach the %s tile %s with the walls built" % [String(m.id), key, str(m[key])])
		if not _reached(ring, _tile(m.post.pos)):
			out.append("%s: the post %s is cut off from the rest of the ring with the walls built" % [String(m.id), str(m.post.pos)])
	var w := _w()
	for i in spawns.size():
		var pocket := _flood(shut, _spawn_tile(i))
		if not _reached(pocket, _spawn_tile(i)):
			out.append("spawn point %d is on shut ground" % i)
			continue
		for m in ms:
			if int(m.spawn) == i and not _reached(pocket, _tile(m.outside)):
				out.append("%s: the dead of spawn point %d cannot get to the outside tile %s" % [String(m.id), i, str(m.outside)])
		var leaked := 0
		var first := Vector2i(-1, -1)
		for k in w * _h():
			if pocket[k] != 0 and ring[k] != 0:
				leaked += 1
				if leaked == 1:
					first = Vector2i(k % w, int(k / w))
		if leaked > 0:
			out.append("with every wall built the dead of spawn point %d still reach the ring (%d tiles, the first at %s)" % [i, leaked, str(first)])
	# 3. each wall plot is needed: with all the others built, the dead get in through its gap
	for m in ms:
		var others: Array = []
		for q in ms:
			if String(q.id) != String(m.id):
				others.append(_rect(q))
		var g := z.duplicate()
		_shut(g, others)
		var reach := _flood(g, _spawn_tile(int(m.spawn)))
		if not _reached(reach, _tile(m.inside)):
			out.append("%s: with every other wall built the dead of spawn point %d cannot get in by this one: it is not a gap" % [String(m.id), int(m.spawn)])
	return out


# ----------------------------------------------------------------- the slots (rules) --

## What is wrong with the places the dead stand at each wall: on its outer face, spaced as the old ones are,
## on the ground the dead can get to, and all the open ground of the face used.
func _slot_problems(d: Dictionary) -> Array:
	var out: Array = []
	var z := _grid("solidZ")
	var conv := _convention()
	var spawns := _spawns()
	var ms := _dicts(d.get("mouths", []))
	var shut := z.duplicate()
	_shut(shut, _rects(ms))
	for m in ms:
		var id := String(m.get("id", ""))
		var slots := _dicts(m.get("slots", []))
		if slots.is_empty() or slots.size() != (m.get("slots", []) as Array).size():
			out.append("%s: has no slots" % id)
			continue
		var side := _side(m)
		var r := _rect(m)
		var horizontal: bool = String(m.dir) == "h"
		var face: String = {"N": "S", "S": "N", "W": "E", "E": "W"}[side]
		var outer := _outer(m)
		var span := _open_span(m, z)
		if span.is_empty():
			out.append("%s: there is no open ground outside the wall" % id)
			continue
		var lo := float(span[0])
		var hi := float(span[span.size() - 1] + 1)
		if hi - lo != float(span.size()):
			out.append("%s: the open ground outside the wall is not in one piece" % id)
		var count := int(floor((hi - lo) / SLOT_SPACING + 1.0e-9))
		if slots.size() != count:
			out.append("%s: has %d slots, the open face (%d tiles) takes %d" % [id, slots.size(), int(hi - lo), count])
		var pocket := _flood(shut, _spawn_tile(int(m.spawn)))
		var prev := -1.0e9
		for i in slots.size():
			var s: Dictionary = slots[i]
			var complete := true
			for k in SLOT_KEYS:
				if not s.has(k):
					complete = false
			if not (complete and s.keys().size() == SLOT_KEYS.size()):
				out.append("%s: slot %d is {x, y, ax, ay, face}" % [id, i])
				continue
			if String(s.face) != face:
				out.append("%s: slot %d faces %s (the dead face %s on the %s side)" % [id, i, String(s.face), face, side])
			var along: float = float(s.x) if horizontal else float(s.y)
			var across_stand: float = float(s.y) if horizontal else float(s.x)
			var along_a: float = float(s.ax) if horizontal else float(s.ay)
			var across_a: float = float(s.ay) if horizontal else float(s.ax)
			if absf(along - along_a) > 1.0e-6:
				out.append("%s: slot %d is met straight out from where it stands: %s and %s" % [id, i, str(along), str(along_a)])
			var dir_in := _inward(m)
			if absf((across_stand - outer) * dir_in - float(conv.stand)) > 1.0e-6:
				out.append("%s: slot %d stands %.2f inside the outer face, the old sections' dead stand %.2f" % [id, i, (across_stand - outer) * dir_in, float(conv.stand)])
			if absf((outer - across_a) * dir_in - float(conv.approach)) > 1.0e-6:
				out.append("%s: slot %d is met %.2f outside the outer face, the old sections' dead are met %.2f" % [id, i, (outer - across_a) * dir_in, float(conv.approach)])
			if i > 0 and absf(along - prev - SLOT_SPACING) > 1.0e-6:
				out.append("%s: slot %d is %.2f from the one before, the places are %.2f apart" % [id, i, along - prev, SLOT_SPACING])
			prev = along
			if along < lo - 1.0e-9 or along > hi + 1.0e-9:
				out.append("%s: slot %d (%s) is not in front of open ground (%s to %s)" % [id, i, str(along), str(lo), str(hi)])
			var at := Vector2i(floori(float(s.ax)), floori(float(s.ay)))
			if not _open(z, at.x, at.y) or at.x >= r[0] and at.x <= r[2] and at.y >= r[1] and at.y <= r[3]:
				out.append("%s: slot %d is met at %s, which is not open ground outside the wall" % [id, i, str(at)])
			elif not _reached(pocket, at):
				out.append("%s: slot %d is met at %s, which the dead of spawn point %d cannot get to" % [id, i, str(at), int(m.spawn)])
			var st := Vector2i(floori(float(s.x)), floori(float(s.y)))
			var in_outer_row: bool = (st.y == int(outer) + (0 if side == "N" else -1) and st.x >= r[0] and st.x <= r[2]) if horizontal else (st.x == int(outer) + (0 if side == "W" else -1) and st.y >= r[1] and st.y <= r[3])
			if not in_outer_row:
				out.append("%s: slot %d stands at %s, not in the tile row along the outer face" % [id, i, str(st)])
		if slots.size() >= 2 and slots.size() == count and not out.any(func(t): return String(t).begins_with(id + ": slot")):
			var first: float = float(slots[0].x) if horizontal else float(slots[0].y)
			var last: float = float(slots[slots.size() - 1].x) if horizontal else float(slots[slots.size() - 1].y)
			if absf((first - lo) - (hi - last)) > 1.0e-6:
				out.append("%s: the slots are not centred on the open face (%.2f from one end, %.2f from the other)" % [id, first - lo, hi - last])
	if absf(float(conv.spacing) - SLOT_SPACING) > 1.0e-6:
		out.append("the old sections' dead are %.2f apart, not %.2f" % [float(conv.spacing), SLOT_SPACING])
	if spawns.is_empty():
		out.append("the map has no spawn points")
	return out


# ------------------------------------------------------------------ the posts (rules) --

## What is wrong with the posts behind the walls: where they are, that people can stand there with a step either
## side, that the guns reach the places of the dead from there, and that people can walk there from the gate.
func _post_problems(d: Dictionary) -> Array:
	var out: Array = []
	var z := _grid("solidZ")
	var pg := _grid("solidP")
	var ms := _dicts(d.get("mouths", []))
	var shotgun := float(_map().get("weapons", {}).get("shotgun", {}).get("range", 7.5))
	var open_walk := _flood(pg, GATE_OUTSIDE)
	var shut := pg.duplicate()
	_shut(shut, _rects(ms))
	var built_walk := _flood(shut, GATE_OUTSIDE)
	var posts: Array = []
	for m in ms:
		var id := String(m.get("id", ""))
		var po = m.get("post", {})
		if not (po is Dictionary and po.keys().size() == 2 and po.has("pos") and po.has("what") and _is_pair(po.pos)):
			out.append("%s: the post is {pos, what}" % id)
			continue
		var what := String(po.what)
		if what.strip_edges() == "" or what.length() > 40 or what.contains("{"):
			out.append("%s: the post says what the shooter is doing in at most 40 characters: '%s'" % [id, what])
		var at := _vec(po.pos)
		var r := _rect(m)
		var horizontal: bool = String(m.dir) == "h"
		var inner := _inner(m)
		var depth := (at.y - inner if horizontal else at.x - inner) * _inward(m)
		var low := 0.5 if horizontal else 1.1
		if depth < low - 1.0e-9 or depth > 1.6:
			out.append("%s: the post is %.2f behind the inner face (%.1f to 1.6)" % [id, depth, low])
		var along := at.x if horizontal else at.y
		if along < float(r[0] if horizontal else r[1]) or along > float((r[2] if horizontal else r[3]) + 1):
			out.append("%s: the post is not along the wall" % id)
		for off in STANDS:
			var spot: Vector2 = at + off
			var t := Vector2i(floori(spot.x), floori(spot.y))
			if not (_open(z, t.x, t.y) and _open(pg, t.x, t.y)):
				out.append("%s: nobody can stand at %s (the post and a step either side)" % [id, str(spot)])
			elif not _reached(open_walk, t):
				out.append("%s: people cannot walk from the gate to %s" % [id, str(spot)])
			elif not _reached(built_walk, t):
				out.append("%s: people cannot walk from the gate to %s once every wall stands" % [id, str(spot)])
		for q in posts:
			if _vec(q.pos).distance_to(at) < 2.0:
				out.append("%s and %s: two posts closer than 2 tiles" % [id, q.id])
		posts.append({"id": id, "pos": po.pos})
		for s in _dicts(m.get("slots", [])):
			var reach := at.distance_to(Vector2(float(s.get("x", 0.0)), float(s.get("y", 0.0))))
			if reach > shotgun:
				out.append("%s: the post is %.1f tiles from the slot at (%s, %s), beyond the shotgun's %.1f" % [id, reach, str(s.get("x")), str(s.get("y")), shotgun])
				break
	return out


# ------------------------------------------------------------ the ring plots (rules) --

## The three tiles deep back of a ring plot's lot that a building shuts (building_art.json's biggest 'solid':
## the back two rows), as a rectangle of tiles.
func _footprint(pos: Vector2) -> Array:
	var x0 := floori(pos.x - 1.5)
	var y0 := floori(pos.y - 1.5)
	return [x0, y0, x0 + 2, y0 + 1]


## What is wrong with the ring plots: where each one lies, its lot, its work spot and the ways to it.
func _plot_problems(d: Dictionary) -> Array:
	var out: Array = []
	var z := _grid("solidZ")
	var pg := _grid("solidP")
	var ms := _dicts(d.get("mouths", []))
	var plots := _dicts(d.get("plots", []))
	var lot_ids := {}
	for l in _dicts(d.get("lots", [])):
		lot_ids[String(l.get("id", ""))] = true
	var yard_ids := _ids_of(_yard_plots())
	var mouth_ids := _ids_of(ms)
	var things: Array = _objects(SOLID_PROPS)
	things.append_array(_objects(FLAT_PROPS))
	var terrain: Array = _map().get("terrain", [])
	var seen := {}
	var names := {}
	var open_walk := _flood(pg, GATE_OUTSIDE)
	var shut_walk := pg.duplicate()
	_shut(shut_walk, _rects(ms))
	var worst := shut_walk.duplicate()
	var built: Array = []
	for pl in plots:
		var id := String(pl.get("id", ""))
		if not _snake(id):
			out.append("the plot id '%s' is lowercase with no spaces" % id)
		if seen.has(id) or yard_ids.has(id) or mouth_ids.has(id):
			out.append("%s: the id is used twice" % id)
		seen[id] = true
		for k in pl.keys():
			if not k in PLOT_KEYS:
				out.append("%s: unknown key '%s'" % [id, k])
		var complete := true
		for k in PLOT_KEYS:
			if not pl.has(k):
				out.append("%s: has no '%s'" % [id, k])
				complete = false
		if not complete:
			continue
		if String(pl.name).strip_edges() == "" or String(pl.name).length() > 40:
			out.append("%s: has a name of at most 40 characters" % id)
		if names.has(String(pl.name)):
			out.append("%s: the name '%s' is used twice" % [id, String(pl.name)])
		names[String(pl.name)] = true
		if String(pl.kind) != "ring":
			out.append("%s: the kind is ring, not '%s'" % [id, String(pl.kind)])
		if not lot_ids.has(String(pl.lot)):
			out.append("%s: lot '%s' is not a lot" % [id, String(pl.lot)])
		if not (_is_pair(pl.pos) and _is_pair(pl.size) and _is_pair(pl.work)):
			out.append("%s: pos, size and work are points" % id)
			continue
		var pos := _vec(pl.pos)
		var size := _vec(pl.size)
		var work := _vec(pl.work)
		if size != Vector2(3.0, 3.0):
			out.append("%s: a lot is three tiles by three: %s" % [id, str(size)])
		if not (is_equal_approx(pos.x - floorf(pos.x), 0.5) and is_equal_approx(pos.y - floorf(pos.y), 0.5)):
			out.append("%s: a lot is centred on the middle of a tile: %s" % [id, str(pos)])
			continue
		var wanted := "north" if pos.y < NORTH_ROWS else ("west" if pos.x < MIDDLE else "east")
		if String(pl.lot) != wanted:
			out.append("%s: lies in the %s lot's streets but belongs to '%s'" % [id, wanted, String(pl.lot)])
		var lot := Rect2(pos - size / 2.0, size)
		var shut: Array = []
		for ty in range(floori(lot.position.y), ceili(lot.end.y)):
			for tx in range(floori(lot.position.x), ceili(lot.end.x)):
				if not (_open(z, tx, ty) and _open(pg, tx, ty)):
					shut.append(Vector2i(tx, ty))
		if not shut.is_empty():
			out.append("%s: the lot covers shut ground %s" % [id, str(shut.slice(0, 4))])
		var hit := _object_under(lot.grow(-0.01), things)
		if hit != "":
			out.append("%s: the lot lies on a %s" % [id, hit])
		var crown := _crown_over(lot)
		if crown != "":
			out.append("%s: the lot is under the %s" % [id, crown])
		if lot.intersects(GATE_LANE):
			out.append("%s: the lot is in the gate's lane" % id)
		if lot.intersects(YARD) or lot.intersects(SCHOOL):
			out.append("%s: the lot is inside the compound" % id)
		for q in _yard_plots():
			var yl := Rect2(_vec(q.pos) - _vec(q.size) / 2.0, _vec(q.size))
			if yl.grow(LOT_GAP / 2.0).intersects(lot.grow(LOT_GAP / 2.0)):
				out.append("%s and the yard's %s lie closer than %.1f tiles" % [id, String(q.id), LOT_GAP])
		for m in ms:
			if lot.grow(1.0).intersects(_rect2(_rect(m))):
				out.append("%s: the lot is up against the wall at %s (a tile is kept free behind a wall)" % [id, String(m.id)])
			var po = m.get("post", {})
			if po is Dictionary and _is_pair(po.get("pos")):
				for off in STANDS:
					if lot.grow(0.9).has_point(_vec(po.pos) + off):
						out.append("%s: the lot is in the way of the post at %s" % [id, String(m.id)])
						break
		for q in built:
			if Rect2(q.lot).grow(LOT_GAP / 2.0).intersects(lot.grow(LOT_GAP / 2.0)):
				out.append("%s and %s lie closer than %.1f tiles" % [String(q.id), id, LOT_GAP])
		built.append({"id": id, "lot": lot})
		# the work spot: the middle of the front row, open, a step either side too, and a way there
		if not work.is_equal_approx(Vector2(pos.x, pos.y + 1.0)):
			out.append("%s: the work spot is the middle of the front row, %s: %s" % [id, str(Vector2(pos.x, pos.y + 1.0)), str(work)])
		for off in STANDS:
			var spot: Vector2 = work + off
			var t := Vector2i(floori(spot.x), floori(spot.y))
			if not (_open(z, t.x, t.y) and _open(pg, t.x, t.y)):
				out.append("%s: nobody can stand at %s" % [id, str(spot)])
			elif not _reached(open_walk, t):
				out.append("%s: people cannot walk from the gate to %s" % [id, str(spot)])
		if work.distance_to(lot.get_center()) > 2.6:
			out.append("%s: the work spot %s is far from the lot" % [id, str(work)])
		_shut(worst, [_footprint(pos)])
		var ctile := Vector2i(int(pos.x), int(pos.y))
		var tid: int = int(terrain[ctile.y * _w() + ctile.x]) if ctile.y * _w() + ctile.x < terrain.size() else -1
		if tid <= 0:
			out.append("%s: the middle of the lot has no ground under it" % id)
	# with every wall built and every lot built over, the crew can still get to every work spot and post
	var reach := _flood(worst, GATE_OUTSIDE)
	for pl in plots:
		if _is_pair(pl.get("work")):
			for off in STANDS:
				var t := _tile(_vec(pl.work) + off)
				if not _reached(reach, t):
					out.append("%s: with every lot built over and every wall up, nobody can walk to %s" % [String(pl.get("id", "")), str(_vec(pl.work) + off)])
					break
	for m in ms:
		var po = m.get("post", {})
		if po is Dictionary and _is_pair(po.get("pos")):
			for off in STANDS:
				if not _reached(reach, _tile(_vec(po.pos) + off)):
					out.append("%s: with every lot built over, nobody can walk to the post %s" % [String(m.get("id", "")), str(_vec(po.pos) + off)])
					break
	# and with every wall built, none of the dead can get to a lot
	var spawns := _spawns()
	var shut_dead := z.duplicate()
	_shut(shut_dead, _rects(ms))
	for i in spawns.size():
		var pocket := _flood(shut_dead, _spawn_tile(i))
		for pl in plots:
			if not _is_pair(pl.get("pos")):
				continue
			var fp := _footprint(_vec(pl.pos))
			var bad := false
			for ty in range(fp[1], fp[3] + 2):
				for tx in range(fp[0], fp[2] + 1):
					if _reached(pocket, Vector2i(tx, ty)):
						bad = true
			if bad:
				out.append("%s: the dead of spawn point %d could stand on this lot with every wall built" % [String(pl.get("id", "")), i])
	return out


# ----------------------------------------------------------------- the kits (rules) --

## What is wrong with the kits: each is one of the compound's own sections, moved and scaled.
func _kit_problems(d: Dictionary) -> Array:
	var out: Array = []
	var kits = d.get("kits", {})
	if not (kits is Dictionary and not kits.is_empty()):
		return ["the kits are a table of id to kit"]
	var templates := {}
	var scrap_by_hp: Array = []
	for id in kits:
		var k = kits[id]
		if not _snake(String(id)):
			out.append("the kit id '%s' is lowercase with no spaces" % String(id))
		if not k is Dictionary:
			out.append("%s: a kit is an object" % String(id))
			continue
		for key in k.keys():
			if not key in KIT_KEYS:
				out.append("%s: unknown key '%s'" % [String(id), key])
		var complete := true
		for key in KIT_KEYS:
			if not k.has(key):
				out.append("%s: has no '%s'" % [String(id), key])
				complete = false
		if not complete:
			continue
		if String(k.name).strip_edges() == "" or String(k.name).length() > 30:
			out.append("%s: has a name of at most 30 characters" % String(id))
		var blurb := String(k.blurb)
		if blurb.length() < 20 or blurb.length() > 120 or _inner_breaks(blurb) > 0 or not blurb.ends_with(".") or blurb.contains("{"):
			out.append("%s: the blurb is one plain sentence of 20 to 120 characters ending in a full stop" % String(id))
		if not String(k.dir) in ["h", "v"]:
			out.append("%s: dir is h or v" % String(id))
		if not _is_whole(k.template):
			out.append("%s: template is the id of an old wall section" % String(id))
			continue
		var s := _segment(int(k.template))
		if s.is_empty():
			out.append("%s: the map has no wall section %d" % [String(id), int(k.template)])
			continue
		if templates.has(int(k.template)):
			out.append("%s and %s move the same section %d" % [String(id), String(templates[int(k.template)]), int(k.template)])
		templates[int(k.template)] = id
		if not String(s.kind) in KIT_KINDS:
			out.append("%s: section %d is a %s, not one of the compound's wall kinds" % [String(id), int(k.template), String(s.kind)])
		var want_dir := "h" if String(s.side) == "N" else "v"
		if String(k.dir) != want_dir:
			out.append("%s: section %d is on the %s side, so a kit of it is %s (it is %s)" % [String(id), int(k.template), String(s.side), want_dir, String(k.dir)])
		if not _is_number(k.hp) or float(k.hp) != float(s.hp):
			out.append("%s: the health is the section's, %s: %s" % [String(id), str(s.hp), str(k.hp)])
		var natural := float(s.to) - float(s["from"])
		if not _is_number(k.length) or absf(float(k.length) - natural) > 1.0e-6:
			out.append("%s: the length is the section's, %s: %s" % [String(id), str(natural), str(k.length)])
		if not _is_number(k.thick) or absf(float(k.thick) - float(s.thick)) > 1.0e-6:
			out.append("%s: the thickness is the section's, %s: %s" % [String(id), str(s.thick), str(k.thick)])
		var faces := _faces(s)
		var first: Dictionary = s.slots[0]
		var depth: float = absf(float(faces.inner) - (float(first.y) if want_dir == "h" else float(first.x)))
		if not _is_number(k.stand) or absf(float(k.stand) - depth) > 1.0e-6:
			out.append("%s: the dead stand %s in front of the inner face (the section's slots): %s" % [String(id), str(depth), str(k.stand)])
		if _is_number(k.stand) and (float(k.stand) < 0.5 or float(k.stand) > float(THICK)):
			out.append("%s: the dead stand %s in front of the inner face, inside the wall's %d tiles" % [String(id), str(k.stand), THICK])
		if not (_is_whole(k.scrap) and int(k.scrap) >= 5 and int(k.scrap) <= 40):
			out.append("%s: the scrap is a whole 5 to 40: %s" % [String(id), str(k.scrap)])
		if not (_is_number(k.work) and float(k.work) >= 8.0 and float(k.work) <= 20.0):
			out.append("%s: the work is 8 to 20 builder-hours: %s" % [String(id), str(k.work)])
		if _is_number(k.scrap) and _is_number(k.hp) and float(k.hp) > 0.0:
			var ratio := float(k.scrap) / float(k.hp)
			if ratio < 0.04 or ratio > 0.09:
				out.append("%s: %s scrap for %s health is %.3f a point (0.04 to 0.09)" % [String(id), str(k.scrap), str(k.hp), ratio])
			scrap_by_hp.append([float(k.hp), float(k.scrap), String(id)])
	for a in scrap_by_hp:
		for b in scrap_by_hp:
			if float(a[0]) > float(b[0]) and float(a[1]) < float(b[1]):
				out.append("%s has more health than %s and costs less" % [str(a[2]), str(b[2])])
	return out


## The kits that fit a mouth: the ones that run its way and are within SCALE_MAX of its length.
func _fitting(d: Dictionary, m: Dictionary) -> Array:
	var out: Array = []
	var kits: Dictionary = d.get("kits", {})
	for id in kits:
		var k: Dictionary = kits[id]
		if String(k.get("dir", "")) == String(m.get("dir", "-")) and float(k.get("length", 0.0)) > 0.0 and absf(float(m.get("length", 0.0)) / float(k.length) - 1.0) <= SCALE_MAX + 1.0e-9:
			out.append(String(id))
	out.sort()
	return out


## What is wrong with which kits each mouth offers: all those that fit and no other, at least two of them (one
## where there is a reason).
func _fit_problems(d: Dictionary) -> Array:
	var out: Array = []
	var kits: Dictionary = d.get("kits", {})
	for m in _dicts(d.get("mouths", [])):
		var id := String(m.get("id", ""))
		var listed: Array = []
		for k in m.get("kits", []):
			listed.append(String(k))
		for k in listed:
			if not kits.has(k):
				out.append("%s: offers '%s', which is not a kit" % [id, k])
			elif String(kits[k].get("dir", "")) != String(m.get("dir", "")):
				out.append("%s: offers '%s', which runs the other way" % [id, k])
			elif absf(float(m.get("length", 0.0)) / float(kits[k].get("length", 1.0)) - 1.0) > SCALE_MAX + 1.0e-9:
				out.append("%s: offers '%s' (%s long) for a mouth of %s tiles, more than %d percent stretched or squeezed" % [id, k, str(kits[k].get("length")), str(m.get("length")), int(SCALE_MAX * 100.0)])
		listed.sort()
		var fits := _fitting(d, m)
		if listed != fits:
			out.append("%s: offers %s, the kits that fit are %s" % [id, str(listed), str(fits)])
		if fits.size() < 1 or (fits.size() < 2 and not id in ONE_KIT_OK):
			out.append("%s: only %d kit(s) fit" % [id, fits.size()])
	return out


# ------------------------------------------------------------------------ the file --

func test_the_file_parses_and_has_its_parts() -> void:
	var d := _data()
	if d.is_empty():
		return
	for k in ["version", "_doc", "passage", "lots", "mouths", "plots", "kits"]:
		check(d.has(k), "the data has '%s'" % k)
	check(d.get("lots", []) is Array and d.get("mouths", []) is Array and d.get("plots", []) is Array and d.get("kits", {}) is Dictionary, "lots, mouths and plots are lists and the kits a table")
	eq(_dicts(d.get("lots", [])).size(), 3, "three lots")
	eq(_dicts(d.get("mouths", [])).size(), 12, "twelve wall plots")
	var ring := _dicts(d.get("plots", []))
	eq(ring.size(), 6, "six ring plots (round 11: the ring is room for a few more buildings, not a map of signs)")
	var kits: Dictionary = d.get("kits", {})
	check(kits.size() >= 10 and kits.size() <= 13, "a dozen kits: %d" % kits.size())
	eq(int(d.get("passage", -1)), 2, "the passage is the old section 2")
	var gate := _segment(int(d.get("passage", -1)))
	eq(String(gate.get("kind", "")), "gate", "and that is the gate")
	eq(String(gate.get("name", "")), "Main gate", "the Main gate")


func test_the_doc_explains_every_field() -> void:
	var d := _data()
	if d.is_empty():
		return
	var problems := _doc_problems(d)
	eq(problems, [], "the doc is all right: %s" % "; ".join(problems))


func test_the_lots_and_who_owns_what() -> void:
	var d := _data()
	if d.is_empty():
		return
	var problems := _lot_problems(d)
	eq(problems, [], "the lots are all right: %s" % "; ".join(problems))
	eq(_lot_spawns(d, "north"), [0, 1, 2, 4, 6, 7], "the north lot has six mouths: the ends of the street, the tops of the roads and the alleys")
	eq(_lot_spawns(d, "west"), [3, 8], "the west lot: the foot of the west road and the west alley")
	eq(_lot_spawns(d, "east"), [5, 9], "the east lot: the foot of the east road and the east alley")
	var counts: Array = []
	for l in _dicts(d.get("lots", [])):
		counts.append((l.plots as Array).size())
	eq(counts, [3, 2, 1], "the lots list three, two and one ring plots")


# ----------------------------------------------------------------------- the mouths --

func test_ten_mouths_one_for_each_spawn_point_and_each_in_its_place_on_the_map() -> void:
	var d := _data()
	if d.is_empty():
		return
	eq(_spawns().size(), 10, "the map has ten spawn points")
	var problems := _mouth_problems(d)
	eq(problems, [], "the mouths are all right: %s" % "; ".join(problems))


func test_a_wall_at_every_mouth_closes_the_ring_and_each_is_needed() -> void:
	var d := _data()
	if d.is_empty():
		return
	var problems := _seal_problems(d)
	eq(problems, [], "the walls close the ring: %s" % "; ".join(problems))


func test_the_ring_is_one_open_space_so_one_open_mouth_lets_the_dead_to_every_lot() -> void:
	var d := _data()
	if d.is_empty():
		return
	# the lots interlock: a lot is sealed in the module's sense when its own mouths stand, but its streets are
	# only free of the dead when all ten stand (the roads and the north street are one open space)
	var z := _grid("solidZ")
	var ms := _dicts(d.get("mouths", []))
	var ring := _flood(z, GATE_OUTSIDE)
	for open in ms:
		var others: Array = []
		for q in ms:
			if String(q.id) != String(open.id):
				others.append(_rect(q))
		var g := z.duplicate()
		_shut(g, others)
		var reach := _flood(g, _spawn_tile(int(open.spawn)))
		for pl in _dicts(d.get("plots", [])):
			check(_reached(reach, _tile(pl.work)), "with only %s open the dead reach the work spot of %s" % [String(open.id), String(pl.id)])
		for m in ms:
			check(_reached(reach, _tile(m.post.pos)), "with only %s open the dead reach the post of %s" % [String(open.id), String(m.id)])
	check(_reached(ring, GATE_OUTSIDE), "and the tile outside the gate is on the ring")


func test_with_every_wall_built_the_dead_are_kept_to_small_pockets_and_the_ring_is_big() -> void:
	var d := _data()
	if d.is_empty():
		return
	var z := _grid("solidZ")
	var ms := _dicts(d.get("mouths", []))
	_shut(z, _rects(ms))
	var ring := _flood(z, GATE_OUTSIDE)
	var inside := 0
	for k in ring.size():
		inside += int(ring[k])
	# the yard (44 by 26) and the school (42 by 14) are what the colony starts with
	check(inside >= 1700, "the ring inside the walls is a base of its own: %d open tiles" % inside)
	var pockets := {}
	for i in _spawns().size():
		var pocket := _flood(z, _spawn_tile(i))
		var n := 0
		for k in pocket.size():
			n += int(pocket[k])
		pockets[i] = n
		check(n >= 6, "the dead of spawn point %d have a pocket of at least six tiles to stand in: %d" % [i, n])
	# the south strip is the one wide place outside, where both the south spawn points stand
	eq(pockets[3], pockets[5], "both south spawn points stand on the same strip")
	for i in [0, 1, 2, 4, 6, 7, 8, 9]:
		check(int(pockets[i]) <= 50, "the pocket of spawn point %d is small: %d" % [i, int(pockets[i])])
	check(int(pockets[3]) <= 400, "and the strip is not much: %d" % int(pockets[3]))


# ------------------------------------------------------------------------ the slots --

func test_the_dead_stand_on_the_outer_face_as_they_do_at_the_old_walls() -> void:
	var d := _data()
	if d.is_empty():
		return
	var conv := _convention()
	near(float(conv.stand), 0.26, 1.0e-6, "the old container's dead stand 0.26 inside the face")
	near(float(conv.approach), 0.5, 1.0e-6, "and are met 0.5 outside it")
	near(float(conv.spacing), SLOT_SPACING, 1.0e-6, "0.9 apart")
	var problems := _slot_problems(d)
	eq(problems, [], "the slots are all right: %s" % "; ".join(problems))
	var total := 0
	for m in _dicts(d.get("mouths", [])):
		total += _dicts(m.get("slots", [])).size()
	check(total >= 40, "the walls have places for the dead enough to matter: %d" % total)


# ------------------------------------------------------------------------- the posts --

func test_a_shooter_stands_behind_each_wall_where_people_can_walk_and_the_guns_reach() -> void:
	var d := _data()
	if d.is_empty():
		return
	var problems := _post_problems(d)
	eq(problems, [], "the posts are all right: %s" % "; ".join(problems))
	eq(float(_map().weapons.shotgun.range), 7.5, "the shotgun's reach is what the posts are measured against")


func test_people_who_come_out_of_the_main_gate_can_walk_the_whole_ring() -> void:
	var d := _data()
	if d.is_empty():
		return
	var gate := _segment(int(d.get("passage", -1)))
	var pg := _grid("solidP")
	# the gate shut on the people's grid, as the map has it, then opened as the claim of a lot opens it
	var tiles: Array = gate.get("tiles", [])
	check(not tiles.is_empty(), "the gate has tiles")
	for t in tiles:
		check(pg[int(t)] != 0, "a tile of the gate is shut for people until a lot is claimed")
		pg[int(t)] = 0
	var inside := _flood(pg, Vector2i(39, 19))
	check(_reached(inside, GATE_OUTSIDE), "from just inside the gate people walk out to the tile outside it (39, 14)")
	# and the dead's grid keeps the gate shut: opening it for people only
	var z := _grid("solidZ")
	for t in tiles:
		check(z[int(t)] != 0, "and a tile of the gate stays shut for the dead")
	for m in _dicts(d.get("mouths", [])):
		check(_reached(inside, _tile(m.post.pos)), "from inside the gate people walk to the post of %s" % String(m.id))
	for pl in _dicts(d.get("plots", [])):
		check(_reached(inside, _tile(pl.work)), "from inside the gate people walk to the work spot of %s" % String(pl.id))


# ------------------------------------------------------------------- the ring plots --

func test_the_ring_plots_lie_on_open_ground_with_work_spots_the_crew_can_walk_to() -> void:
	var d := _data()
	if d.is_empty():
		return
	var problems := _plot_problems(d)
	eq(problems, [], "the plots are all right: %s" % "; ".join(problems))


func test_the_ring_plots_are_spread_over_the_streets_and_the_lots() -> void:
	var d := _data()
	if d.is_empty():
		return
	var plots := _dicts(d.get("plots", []))
	var by_lot := {"north": 0, "west": 0, "east": 0}
	var quarters := {"wn": 0, "en": 0, "ws": 0, "es": 0}
	var terrain: Array = _map().get("terrain", [])
	var kinds := {}
	var street := 0
	for pl in plots:
		by_lot[String(pl.lot)] = int(by_lot.get(String(pl.lot), 0)) + 1
		var pos := _vec(pl.pos)
		quarters["%s%s" % ["w" if pos.x < MIDDLE else "e", "n" if pos.y < NORTH_ROWS else "s"]] += 1
		kinds[int(terrain[int(pos.y) * _w() + int(pos.x)])] = true
		if pos.y < 15.0:
			street += 1
	eq(int(by_lot.north), 3, "the north lot has three plots")
	eq(int(by_lot.west), 2, "the west lot has two")
	eq(int(by_lot.east), 1, "the east lot has one")
	for q in quarters:
		check(int(quarters[q]) >= 1, "the %s quarter of the ring has a plot: %d" % [q, int(quarters[q])])
	eq(street, 3, "the north lot's three plots all stand in the north street, near the Main gate")
	check(kinds.has(1) and kinds.has(2) and kinds.has(4), "the plots stand on asphalt, on sidewalk and on a verge (terrain 1, 2 and 4): %s" % str(kinds.keys()))
	# a person can pass between any two plots and the plots do not crowd one another
	for i in plots.size():
		var near_one := INF
		for j in plots.size():
			if i != j:
				near_one = minf(near_one, _vec(plots[i].pos).distance_to(_vec(plots[j].pos)))
		check(near_one >= 4.0, "%s has a neighbour %.1f tiles away (at least 4)" % [String(plots[i].id), near_one])


# ------------------------------------------------------------------------- the kits --

func test_the_kits_are_the_compounds_own_sections_with_their_health() -> void:
	var d := _data()
	if d.is_empty():
		return
	var problems := _kit_problems(d)
	eq(problems, [], "the kits are all right: %s" % "; ".join(problems))
	var kits: Dictionary = d.get("kits", {})
	var h := 0
	var v := 0
	var kinds := {}
	for id in kits:
		if String(kits[id].dir) == "h":
			h += 1
		else:
			v += 1
		kinds[String(_segment(int(kits[id].template)).get("kind", ""))] = true
	check(h >= 4 and v >= 6, "kits for walls that run both ways: %d and %d" % [h, v])
	for k in KIT_KINDS:
		check(kinds.has(k), "there is a %s kit" % k)


func test_every_mouth_offers_the_kits_that_fit_it_and_every_kit_fits_somewhere() -> void:
	var d := _data()
	if d.is_empty():
		return
	var problems := _fit_problems(d)
	eq(problems, [], "the kits fit: %s" % "; ".join(problems))
	var used := {}
	for m in _dicts(d.get("mouths", [])):
		for k in m.get("kits", []):
			used[String(k)] = true
	for id in d.get("kits", {}):
		check(used.has(String(id)), "the kit %s is offered at some mouth" % String(id))
	var cheap := 0
	var strong := 0
	for m in _dicts(d.get("mouths", [])):
		for k in m.get("kits", []):
			if int(d.kits[k].scrap) <= 16:
				cheap += 1
			if float(d.kits[k].hp) >= 300.0:
				strong += 1
	check(cheap >= 12 and strong >= 8, "there are cheap and strong choices to make: %d cheap, %d strong" % [cheap, strong])


# ----------------------------------------------- the rules can fail: doctored copies --

## A copy of the data to doctor in memory.
func _copy(d: Dictionary) -> Dictionary:
	return d.duplicate(true)


func _mouth_of(d: Dictionary, id: String) -> Dictionary:
	for m in d.mouths:
		if String(m.id) == id:
			return m
	return {}


func _plot_of(d: Dictionary, id: String) -> Dictionary:
	for p in d.plots:
		if String(p.id) == id:
			return p
	return {}


func _has(problems: Array, text: String) -> bool:
	return "; ".join(problems).contains(text)


func test_a_lot_with_a_wrong_claim_or_owner_is_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var c := _copy(d)
	c.lots[0].claim.scrap = 90
	check(_has(_lot_problems(c), "the north lot is the cheapest"), "a dear north lot is found: %s" % "; ".join(_lot_problems(c)))
	c = _copy(d)
	c.lots[1].claim.day = 2
	check(_has(_lot_problems(c), "one after another"), "a west lot before the north is found")
	c = _copy(d)
	c.lots[2].claim.erase("cleared")
	check(_has(_lot_problems(c), "the claim is {scrap, cleared, day}"), "a claim with no cleared places is found")
	c = _copy(d)
	(c.lots[0].mouths as Array).erase("north_west_end")
	check(_has(_lot_problems(c), "north_west_end"), "a mouth that no lot lists is found")
	c = _copy(d)
	(c.lots[1].mouths as Array).append("north_west_end")
	check(_has(_lot_problems(c), "listed by two lots"), "a mouth listed by two lots is found")
	c = _copy(d)
	c.mouths[0].lot = "east"
	check(_has(_lot_problems(c), "belongs to lot 'east'"), "a mouth in the wrong lot is found")
	c = _copy(d)
	c.lots[0].blurb = "Short."
	check(_has(_lot_problems(c), "the blurb"), "a bare blurb is found")
	c = _copy(d)
	c.lots.remove_at(2)
	check(_has(_lot_problems(c), "north, west and east"), "a missing lot is found")


func test_a_mouth_on_a_prop_on_old_ground_or_on_its_spawn_point_is_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var base := _mouth_problems(d)
	eq(base, [], "the real data first: %s" % "; ".join(base))
	# on the spawn point of the west end
	var c := _copy(d)
	_mouth_of(c, "north_west_end").rect = [0, 4, 2, 14]
	var text := "; ".join(_mouth_problems(c))
	check(text.contains("north_west_end: the wall is within") and text.contains("of the spawn point"), "a wall on its spawn point is found: %s" % text)
	# one tile too near it
	c = _copy(d)
	_mouth_of(c, "north_west_end").rect = [2, 4, 4, 14]
	check(_has(_mouth_problems(c), "north_west_end: the wall is within"), "a wall 1.5 tiles from its spawn point is found")
	# on an old wall (the north wall of the yard at the Main gate)
	c = _copy(d)
	_mouth_of(c, "west_road_top").rect = [30, 14, 40, 16]
	text = "; ".join(_mouth_problems(c))
	check(text.contains("west_road_top: the wall covers an old wall section") and text.contains("west_road_top: the wall covers shut ground"), "a wall on the compound's wall is found: %s" % text)
	# on a car: the burnt car at (28.8 to 33.2, 9.4 to 11.4)
	c = _copy(d)
	_mouth_of(c, "north_alley_west").rect = [28, 8, 32, 10]
	check(_has(_mouth_problems(c), "north_alley_west: the wall is under a"), "a wall under a car is found")
	# two walls on the same tiles
	c = _copy(d)
	_mouth_of(c, "west_road_top").rect = [5, 4, 15, 6]
	check(_has(_mouth_problems(c), "overlap"), "two walls on the same tiles are found")
	# the wrong thickness, length, centre and side
	c = _copy(d)
	_mouth_of(c, "west_road_top").rect = [6, 4, 16, 5]
	check(_has(_mouth_problems(c), "tiles thick, not 3"), "a wall two tiles thick is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").length = 10
	check(_has(_mouth_problems(c), "the length is the long side"), "a wrong length is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").center = [11.5, 4.5]
	check(_has(_mouth_problems(c), "the centre is the middle"), "a wrong centre is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").side = "S"
	check(_has(_mouth_problems(c), "the side the dead come from"), "a wrong side is found")
	# the tiles each side
	c = _copy(d)
	_mouth_of(c, "west_road_top").outside = [10, 2]
	check(_has(_mouth_problems(c), "outside tile"), "an outside tile that is not across the face is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").inside = [10, 9]
	check(_has(_mouth_problems(c), "inside tile"), "an inside tile that is not across the face is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").inside = [10, 7]
	_mouth_of(c, "west_road_top").outside = [14, 3]
	check(_has(_mouth_problems(c), "outside tile"), "an outside tile that is shut is found")
	# in the compound
	c = _copy(d)
	_mouth_of(c, "west_alley").rect = [20, 30, 22, 34]
	text = "; ".join(_mouth_problems(c))
	check(text.contains("the wall is inside the compound"), "a wall in the yard is found: %s" % text)
	# off the map
	c = _copy(d)
	_mouth_of(c, "west_alley").rect = [80, 40, 84, 42]
	check(_has(_mouth_problems(c), "not a rectangle on the map"), "a wall off the map is found")


func test_a_spawn_point_without_a_mouth_or_with_a_badly_split_one_is_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var c := _copy(d)
	c.mouths.erase(_mouth_of(c, "north_alley_east"))
	check(_has(_mouth_problems(c), "spawn point 7 has no mouth"), "a spawn point with no mouth is found")
	c = _copy(d)
	_mouth_of(c, "south_west_b").id = "south_west_c"
	check(_has(_mouth_problems(c), "are called <name>_a and <name>_b"), "wall plots not called _a and _b are found")
	c = _copy(d)
	_mouth_of(c, "south_west_b").rect = [16, 57, 19, 59]
	_mouth_of(c, "south_west_b").length = 4
	_mouth_of(c, "south_west_b").center = [18.0, 58.5]
	check(_has(_mouth_problems(c), "lie end to end"), "two walls with a gap between are found")
	c = _copy(d)
	_mouth_of(c, "south_west_b").lot = "east"
	check(_has(_mouth_problems(c), "in one lot"), "two walls of one spawn point in two lots are found")
	c = _copy(d)
	_mouth_of(c, "north_alley_west").id = "north_alley_west_a"
	check(_has(_mouth_problems(c), "has no suffix"), "a suffix on a mouth in one piece is found")
	# a street wider than the longest kit left whole
	c = _copy(d)
	var a := _mouth_of(c, "south_west_a")
	a.rect = [3, 57, 19, 59]
	a.length = 17
	a.center = [11.5, 58.5]
	c.mouths.erase(_mouth_of(c, "south_west_b"))
	check(_has(_mouth_problems(c), "split in two"), "a mouth wider than the longest kit left whole is found")


func test_a_wall_that_does_not_span_its_street_or_is_not_needed_is_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var base := _seal_problems(d)
	eq(base, [], "the real data first: %s" % "; ".join(base))
	# a wall one tile short of the street's end: the dead walk round it
	var c := _copy(d)
	var m := _mouth_of(c, "north_west_end")
	m.rect = [3, 4, 5, 13]
	m.length = 10
	m.center = [4.5, 9.0]
	var text := "; ".join(_seal_problems(c))
	check(text.contains("still reach the ring"), "a wall that stops a tile short lets the dead round: %s" % text)
	# a wall off the street: the gap is open
	c = _copy(d)
	m = _mouth_of(c, "north_alley_west")
	m.rect = [31, 4, 35, 6]
	text = "; ".join(_seal_problems(c))
	check(text.contains("still reach the ring"), "a wall beside the alley instead of across it is found: %s" % text)
	# a wall that closes the tile the dead come out at but leaves the street open beside it
	c = _copy(d)
	m = _mouth_of(c, "south_east_b")
	m.rect = [64, 57, 66, 59]
	m.length = 3
	m.center = [65.5, 58.5]
	text = "; ".join(_seal_problems(c))
	check(text.contains("still reach the ring"), "half a wall across the foot of a road is found: %s" % text)
	# a spare wall, in a place the dead cannot come by: not needed
	c = _copy(d)
	m = _mouth_of(c, "west_alley")
	m.rect = [3, 20, 5, 24]
	m.inside = [6, 22]
	m.outside = [2, 22]
	text = "; ".join(_seal_problems(c))
	check(text.contains("west_alley:"), "a wall that closes nothing is found: %s" % text)
	# an inside tile in a place the dead can never reach
	c = _copy(d)
	_mouth_of(c, "west_alley").inside = [17, 40]
	check(_has(_seal_problems(c), "do not reach the inside"), "an inside tile behind the compound's wall is found")
	# a pocket that is not the spawn point's
	c = _copy(d)
	_mouth_of(c, "west_alley").outside = [9, 20]
	check(_has(_seal_problems(c), "cannot get to the outside tile"), "an outside tile the spawn point's dead cannot reach is found")
	# a mouth for a spawn point it does not close
	c = _copy(d)
	_mouth_of(c, "west_alley").spawn = 9
	check(not _seal_problems(c).is_empty(), "a wall given the wrong spawn point is found")
	# two walls across one alley: each is a spare, neither is a gap
	c = _copy(d)
	var twin: Dictionary = _mouth_of(c, "north_alley_west").duplicate(true)
	twin.id = "north_alley_west_twin"
	c.mouths.append(twin)
	text = "; ".join(_seal_problems(c))
	check(text.contains("north_alley_west: with every other wall built the dead of spawn point 6 cannot get in by this one: it is not a gap") and text.contains("north_alley_west_twin: with every other wall built"), "two walls across one alley are found: %s" % text)
	# an inside tile the dead can never get to is not a gap either
	c = _copy(d)
	_mouth_of(c, "west_alley").inside = [17, 40]
	check(_has(_seal_problems(c), "west_alley: with every other wall built the dead of spawn point 8 cannot get in by this one: it is not a gap"), "an inside tile behind the compound's wall is not a gap")


func test_slots_off_the_face_out_of_step_or_out_of_reach_are_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var base := _slot_problems(d)
	eq(base, [], "the real data first: %s" % "; ".join(base))
	var c := _copy(d)
	_mouth_of(c, "west_road_top").slots[2].x = 8.5
	check(_has(_slot_problems(c), "west_road_top: slot 2 is met straight out"), "a slot that is not straight in front of its approach is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").slots[3].face = "N"
	check(_has(_slot_problems(c), "west_road_top: slot 3 faces N"), "a slot that faces the wrong way is found")
	c = _copy(d)
	var s: Dictionary = _mouth_of(c, "west_road_top").slots[4]
	s.y = 4.6
	check(_has(_slot_problems(c), "west_road_top: slot 4 stands"), "a slot the wrong depth in the face is found")
	c = _copy(d)
	s = _mouth_of(c, "west_road_top").slots[4]
	s.ay = 3.0
	check(_has(_slot_problems(c), "west_road_top: slot 4 is met"), "a slot met at the wrong distance is found")
	c = _copy(d)
	for i in range(3, _mouth_of(c, "west_road_top").slots.size()):
		_mouth_of(c, "west_road_top").slots[i].x += 0.1
		_mouth_of(c, "west_road_top").slots[i].ax += 0.1
	check(_has(_slot_problems(c), "west_road_top: slot 3 is"), "slots out of step are found")
	c = _copy(d)
	(_mouth_of(c, "west_road_top").slots as Array).remove_at(7)
	check(_has(_slot_problems(c), "west_road_top: has 7 slots"), "a slot too few is found")
	c = _copy(d)
	(_mouth_of(c, "north_alley_west").slots as Array).append({"x": 30.45, "y": 4.26, "ax": 30.45, "ay": 3.5, "face": "S"})
	check(_has(_slot_problems(c), "north_alley_west: has 3 slots"), "a slot too many is found")
	c = _copy(d)
	for sl in _mouth_of(c, "west_road_top").slots:
		sl.x += 6.0
		sl.ax += 6.0
	_expect(_slot_problems(c), "west_road_top: slot", "slots in front of a building's wall are found")
	c = _copy(d)
	s = _mouth_of(c, "west_alley").slots[0]
	s.ax = 4.0
	check(_has(_slot_problems(c), "west_alley: slot 0"), "a slot met inside the wall is found")
	c = _copy(d)
	_mouth_of(c, "west_alley").slots[1].erase("face")
	check(_has(_slot_problems(c), "west_alley: slot 1 is {x, y, ax, ay, face}"), "a slot with no face is found")
	c = _copy(d)
	_mouth_of(c, "west_alley").slots = []
	check(_has(_slot_problems(c), "west_alley: has no slots"), "a wall with no places for the dead is found")


func _expect(problems: Array, text: String, msg: String) -> void:
	check(_has(problems, text), "%s: %s" % [msg, "; ".join(problems)])


func test_posts_in_a_wall_out_of_reach_or_cut_off_are_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var base := _post_problems(d)
	eq(base, [], "the real data first: %s" % "; ".join(base))
	var c := _copy(d)
	_mouth_of(c, "west_road_top").post.pos = [10.0, 5.0]
	var text := "; ".join(_post_problems(c))
	check(text.contains("west_road_top: people cannot walk from the gate to (10.0, 5.0) once every wall stands") and text.contains("behind the inner face"), "a post in the wall is found: %s" % text)
	c = _copy(d)
	_mouth_of(c, "west_road_top").post.pos = [10.0, 9.5]
	check(_has(_post_problems(c), "behind the inner face"), "a post too far behind the wall is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").post.pos = [18.0, 7.8]
	check(_has(_post_problems(c), "not along the wall"), "a post beside the wall is found")
	c = _copy(d)
	_mouth_of(c, "north_west_end").post.pos = [6.6, 9.5]
	check(_has(_post_problems(c), "north_west_end: people cannot walk from the gate to (5.5, 9.5) once every wall stands"), "a post whose step either side is in the wall is found")
	c = _copy(d)
	_mouth_of(c, "north_east_end").post.pos = [78.4, 9.5]
	check(_has(_post_problems(c), "north_east_end: people cannot walk from the gate to (79.5, 9.5) once every wall stands"), "a post tight against an east wall is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").post.pos = [10.0, 2.5]
	check(not _post_problems(c).is_empty(), "a post on the dead's side of the wall is found")
	c = _copy(d)
	_mouth_of(c, "south_west_a").post.pos = [9.0, 56.2 - 6.0]
	check(_has(_post_problems(c), "beyond the shotgun's"), "a post too far for the guns is found")
	c = _copy(d)
	_mouth_of(c, "north_alley_west").post.pos = [29.0, 7.8]
	_mouth_of(c, "north_alley_east").post.pos = [29.5, 7.8]
	check(_has(_post_problems(c), "two posts closer than 2 tiles"), "two posts on top of each other are found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").post["what"] = ""
	check(_has(_post_problems(c), "what the shooter is doing"), "a post that says nothing is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").post["pos"] = [10.0, 7.8, 1.0]
	check(_has(_post_problems(c), "the post is {pos, what}"), "a post with a bad position is found")
	# a pocket of ground behind a lot that people cannot walk to: a post inside the sealed corner of the school's wall
	c = _copy(d)
	_mouth_of(c, "west_alley").post.pos = [18.5, 40.0]
	check(not _post_problems(c).is_empty(), "a post behind the compound's wall is found")


func test_plots_on_a_car_a_wall_or_each_other_or_with_no_way_to_them_are_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var base := _plot_problems(d)
	eq(base, [], "the real data first: %s" % "; ".join(base))
	# two of the north street's plots are taken in turn and put in the wrong places (round 11 left six: "a" is the
	# one by the wreck, "b" the one past the gate)
	var a := "street_wreck"
	var b := "street_gate"
	var c := _copy(d)
	var p := _plot_of(c, a)
	# on the car at (14.8 to 19.2, 7.2 to 9.2)
	p.pos = [16.5, 8.5]
	p.work = [16.5, 9.5]
	var text := "; ".join(_plot_problems(c))
	check(text.contains("%s: the lot lies on a car" % a) or text.contains("%s: the lot covers shut ground" % a), "a lot on a car is found: %s" % text)
	# in the gate's lane
	c = _copy(d)
	p = _plot_of(c, a)
	p.pos = [39.5, 9.5]
	p.work = [39.5, 10.5]
	check(_has(_plot_problems(c), "%s: the lot is in the gate's lane" % a), "a lot in the gate's lane is found")
	# on shut ground and inside the compound
	c = _copy(d)
	p = _plot_of(c, a)
	p.pos = [30.5, 16.5]
	p.work = [30.5, 17.5]
	text = "; ".join(_plot_problems(c))
	check(text.contains("%s: the lot covers shut ground" % a) and text.contains("%s: the lot is inside the compound" % a), "a lot on the compound's wall is found: %s" % text)
	c = _copy(d)
	p = _plot_of(c, a)
	p.pos = [30.5, 25.5]
	p.work = [30.5, 26.5]
	check(_has(_plot_problems(c), "%s: the lot is inside the compound" % a), "a lot in the yard is found")
	# on another lot
	c = _copy(d)
	p = _plot_of(c, b)
	var at := _vec(_plot_of(c, a).pos) + Vector2(1.0, 0.0)
	p.pos = [at.x, at.y]
	p.work = [at.x, at.y + 1.0]
	check(_has(_plot_problems(c), "lie closer than"), "two lots on each other are found")
	# off the centre of a tile, the wrong size, the wrong kind
	c = _copy(d)
	_plot_of(c, b).pos = [43.0, 6.5]
	check(_has(_plot_problems(c), "%s: a lot is centred on the middle of a tile" % b), "a lot off the middle of a tile is found")
	c = _copy(d)
	_plot_of(c, b).size = [3.0, 2.0]
	check(_has(_plot_problems(c), "%s: a lot is three tiles by three" % b), "a lot of another size is found")
	c = _copy(d)
	_plot_of(c, b).kind = "yard"
	check(_has(_plot_problems(c), "%s: the kind is ring" % b), "a lot of another kind is found")
	# the work spot
	c = _copy(d)
	p = _plot_of(c, b)
	var mid := _vec(p.pos)
	p.work = [mid.x, mid.y - 1.0]
	check(_has(_plot_problems(c), "%s: the work spot is the middle of the front row" % b), "a work spot in the lot's own back rows is found")
	c = _copy(d)
	p = _plot_of(c, b)
	p.work = [mid.x, mid.y + 5.0]
	check(_has(_plot_problems(c), "%s: the work spot is the middle of the front row" % b) and _has(_plot_problems(c), "far from the lot"), "a work spot far from the lot is found")
	# the lot against a wall and in the way of a post
	c = _copy(d)
	p = _plot_of(c, a)
	p.pos = [9.5, 9.5]
	p.work = [9.5, 10.5]
	text = "; ".join(_plot_problems(c))
	check(text.contains("%s: the lot is up against the wall" % a) or text.contains("%s: the lot is in the way of the post" % a), "a lot against a wall or in the way of a post is found: %s" % text)
	# under a tree, on a lamp post, on the flat marks
	c = _copy(d)
	p = _plot_of(c, a)
	p.pos = [18.5, 6.5]
	p.work = [18.5, 7.5]
	check(_has(_plot_problems(c), "%s: the lot is under the tree" % a), "a lot under a tree is found")
	c = _copy(d)
	p = _plot_of(c, a)
	p.pos = [24.5, 13.5]
	p.work = [24.5, 14.5]
	check(_has(_plot_problems(c), "%s: the lot lies on a lamppost" % a), "a lot on a lamp post is found")
	# on the dead's side of a wall: a lot in the south strip
	c = _copy(d)
	p = _plot_of(c, a)
	p.pos = [12.5, 61.5]
	p.work = [12.5, 62.5]
	text = "; ".join(_plot_problems(c))
	check(text.contains("%s: the dead of spawn point" % a) or text.contains("people cannot walk from the gate"), "a lot outside the walls is found: %s" % text)
	# the wrong lot, an id twice, a missing key
	c = _copy(d)
	_plot_of(c, a).lot = "east"
	check(_has(_plot_problems(c), "%s: lies in the north lot's streets but belongs to 'east'" % a), "a lot of the wrong lot is found")
	c = _copy(d)
	_plot_of(c, a).id = "junk_corner"
	check(_has(_plot_problems(c), "the id is used twice"), "an id the yard already has is found")
	c = _copy(d)
	_plot_of(c, a).erase("work")
	check(_has(_plot_problems(c), "%s: has no 'work'" % a), "a lot without a work spot is found")
	# lots that wall each other in once they are built: a lot whose back rows cover the next one's step
	c = _copy(d)
	var step := _vec(_plot_of(c, a).work) + Vector2(1.1, 0.0)
	var q := _plot_of(c, b)
	q.pos = [float(floori(step.x)) + 1.5, float(floori(step.y)) + 1.5]
	q.work = [float(floori(step.x)) + 1.5, float(floori(step.y)) + 2.5]
	text = "; ".join(_plot_problems(c))
	check(text.contains("%s: with every lot built over and every wall up, nobody can walk to (%.1f, %.1f)" % [a, step.x, step.y]), "a lot built over the step of another is found: %s" % text)
	# two lots with a tile between them are fine
	c = _copy(d)
	q = _plot_of(c, b)
	var apart := _vec(_plot_of(c, a).pos) + GAP_SPOT
	q.pos = [apart.x, apart.y]
	q.work = [apart.x, apart.y + 1.0]
	eq(_plot_problems(c), [], "two lots with a tile between them are not found wrong: %s" % "; ".join(_plot_problems(c)))
	q.pos = [apart.x + 1.0, apart.y]
	q.work = [apart.x + 1.0, apart.y + 1.0]
	check(_has(_plot_problems(c), "lie closer than"), "and with no tile between them they are")


func test_kits_with_the_wrong_health_template_or_price_are_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var base := _kit_problems(d)
	eq(base, [], "the real data first: %s" % "; ".join(base))
	var c := _copy(d)
	c.kits.bus_n.hp = 400
	check(_has(_kit_problems(c), "bus_n: the health is the section's"), "a kit with another health than its section is found")
	c = _copy(d)
	c.kits.bus_n.template = 12
	check(_has(_kit_problems(c), "bus_n: section 12 is on the E side, so a kit of it is v"), "a kit of a section on the other axis is found")
	c = _copy(d)
	c.kits.bus_n.template = 99
	check(_has(_kit_problems(c), "bus_n: the map has no wall section 99"), "a kit of a section that is not there is found")
	c = _copy(d)
	c.kits.bus_n.template = 2
	check(_has(_kit_problems(c), "bus_n: section 2 is a gate"), "a kit of the gate is found")
	c = _copy(d)
	c.kits.bus_n.length = 9
	check(_has(_kit_problems(c), "bus_n: the length is the section's"), "a kit of another length than its section is found")
	c = _copy(d)
	c.kits.bus_n.thick = 1.0
	check(_has(_kit_problems(c), "bus_n: the thickness is the section's"), "a kit of another thickness is found")
	c = _copy(d)
	c.kits.bus_n.stand = 1.0
	check(_has(_kit_problems(c), "bus_n: the dead stand"), "a kit with another standing depth is found")
	c = _copy(d)
	c.kits.bus_n.stand = 3.5
	check(_has(_kit_problems(c), "inside the wall's 3 tiles"), "a kit whose dead stand outside the wall is found")
	c = _copy(d)
	c.kits.bus_n.scrap = 200
	check(_has(_kit_problems(c), "bus_n: the scrap is a whole 5 to 40"), "a kit that costs too much is found")
	c = _copy(d)
	c.kits.car_n.scrap = 30
	check(_has(_kit_problems(c), "a point (0.04 to 0.09)") or _has(_kit_problems(c), "has more health than"), "a car dearer than its health is found")
	c = _copy(d)
	c.kits.pallets_n.scrap = 39
	check(_has(_kit_problems(c), "has more health than"), "a weak kit dearer than a strong one is found")
	c = _copy(d)
	c.kits.bus_n.work = 90
	check(_has(_kit_problems(c), "bus_n: the work is 8 to 20"), "a kit that takes too long is found")
	c = _copy(d)
	c.kits.pallets_n.template = 0
	check(_has(_kit_problems(c), "move the same section 0"), "two kits of one section are found")
	c = _copy(d)
	c.kits.bus_n.erase("blurb")
	check(_has(_kit_problems(c), "bus_n: has no 'blurb'"), "a kit with no blurb is found")
	c = _copy(d)
	c.kits["Bus N"] = c.kits.bus_n.duplicate(true)
	check(_has(_kit_problems(c), "the kit id 'Bus N' is lowercase"), "a kit id with capitals is found")
	c = _copy(d)
	c.kits = {}
	check(_has(_kit_problems(c), "the kits are a table"), "no kits are found")


func test_a_mouth_with_the_wrong_kits_or_none_that_fit_is_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var base := _fit_problems(d)
	eq(base, [], "the real data first: %s" % "; ".join(base))
	var c := _copy(d)
	(_mouth_of(c, "west_road_top").kits as Array).append("pallets_n")
	var text := "; ".join(_fit_problems(c))
	check(text.contains("west_road_top: offers 'pallets_n'") and text.contains("percent stretched or squeezed"), "a kit three times too short is found: %s" % text)
	c = _copy(d)
	(_mouth_of(c, "west_road_top").kits as Array).append("bus_e")
	check(_has(_fit_problems(c), "west_road_top: offers 'bus_e', which runs the other way"), "a kit that runs the other way is found")
	c = _copy(d)
	(_mouth_of(c, "west_road_top").kits as Array).append("no_such_kit")
	check(_has(_fit_problems(c), "no_such_kit', which is not a kit"), "a kit that does not exist is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").kits = ["bus_n"]
	check(_has(_fit_problems(c), "west_road_top: offers [\"bus_n\"], the kits that fit are") and _has(_fit_problems(c), "west_road_top: only 2 kit(s) fit") == false, "a kit left out is found")
	c = _copy(d)
	_mouth_of(c, "west_road_top").kits = []
	_mouth_of(c, "west_road_top").length = 8
	_mouth_of(c, "west_road_top").rect = [6, 4, 13, 6]
	check(_has(_fit_problems(c), "west_road_top: only 0 kit(s) fit"), "a mouth no kit fits is found")
	c = _copy(d)
	c.kits.container_short.length = 20
	check(_has(_fit_problems(c), "north_alley_west"), "a kit that no longer fits is found")
	c = _copy(d)
	_mouth_of(c, "west_alley").kits = ["chainlink_w", "blocks_w", "pallets_w", "car_e"]
	check(not _fit_problems(c).is_empty(), "a mouth that lists too few of the kits that fit is found")
	# one kit only where there is no reason for it
	c = _copy(d)
	_mouth_of(c, "south_west_a").kits = ["container_n"]
	_mouth_of(c, "south_west_a").length = 12
	c.kits.bus_n.length = 4
	check(_has(_fit_problems(c), "south_west_a: only 1 kit(s) fit"), "one kit where two are wanted is found")


func test_a_doc_that_leaves_a_field_out_is_found() -> void:
	var d := _data()
	if d.is_empty():
		return
	var c := _copy(d)
	c["_doc"] = "A doc that says almost nothing."
	check(_has(_doc_problems(c), "not a line") and _has(_doc_problems(c), "does not explain 'anchor'"), "a short doc is found: %s" % "; ".join(_doc_problems(c)))
	# a long doc that forgets one field
	c = _copy(d)
	c["_doc"] = String(d._doc).replace("anchor", "ancho")
	check(_has(_doc_problems(c), "does not explain 'anchor'"), "a doc that forgets the anchor is found")
	c = _copy(d)
	c["_doc"] = String(d._doc).replace("sealed_bonus", "sealed bonus")
	check(_has(_doc_problems(c), "does not explain 'sealed_bonus'"), "a doc that forgets the sealed bonus is found")


# ------------------------------------------------- the real engine agrees with the flood fills --

## The game's own path searches (Pathfinder over the world's walking grids, as the dead and the people use them)
## find the same: the dead come in at every mouth while no wall stands, and with every wall up they come to the
## places of the wall they belong to and to no inside tile; people walk from the gate to every post and work spot.
func test_the_engines_own_path_search_agrees_with_the_flood_fills() -> void:
	var d := _data()
	if d.is_empty():
		return
	var g := Helpers.make(1, 1, 6)
	var sim = g.sim
	var w = g.world
	var ms := _dicts(d.mouths)
	# the world's walking grids are the map's outside the compound: only the yard (and the top row of the school
	# under the walkways' south ends) has deck barriers
	var z := _grid("solidZ")
	var p := _grid("solidP")
	var strays := 0
	for i in w.solid_z.size():
		if int(w.solid_z[i]) != int(z[i]) or int(w.solid_p[i]) != int(p[i]):
			var at := Vector2(float(i % _w()) + 0.5, float(int(i / _w())) + 0.5)
			if not (YARD.has_point(at) or SCHOOL.has_point(at)):
				strays += 1
	eq(strays, 0, "the world's grids differ from the map's only inside the compound (the yard's deck barriers)")
	for m in ms:
		var sp: Vector2 = sim.spawns[int(m.spawn)]
		var way: Array = sim.path_z.find(w.solid_z, sp.x, sp.y, float(m.inside[0]) + 0.5, float(m.inside[1]) + 0.5)
		check(not way.is_empty(), "with no wall built the dead of spawn point %d find a way in to %s" % [int(m.spawn), String(m.id)])
	var tiles: Array = []
	for m in ms:
		var r := _rect(m)
		for ty in range(r[1], r[3] + 1):
			for tx in range(r[0], r[2] + 1):
				tiles.append(ty * _w() + tx)
	sim.block_tiles(tiles, true)
	for m in ms:
		var sp: Vector2 = sim.spawns[int(m.spawn)]
		for q in ms:
			var way: Array = sim.path_z.find(w.solid_z, sp.x, sp.y, float(q.inside[0]) + 0.5, float(q.inside[1]) + 0.5)
			check(way.is_empty(), "with every wall built the dead of spawn point %d find no way to the inside of %s" % [int(m.spawn), String(q.id)])
		for s in m.slots:
			var to_slot: Array = sim.path_z.find(w.solid_z, sp.x, sp.y, float(s.ax), float(s.ay))
			check(not to_slot.is_empty(), "the dead of spawn point %d find the way to a place at %s" % [int(m.spawn), String(m.id)])
		var to_post: Array = sim.path_p.find(w.solid_p, 39.5, 14.5, float(m.post.pos[0]), float(m.post.pos[1]))
		check(not to_post.is_empty(), "people find the way from the gate to the post of %s" % String(m.id))
	for pl in _dicts(d.plots):
		var to_work: Array = sim.path_p.find(w.solid_p, 39.5, 14.5, float(pl.work[0]), float(pl.work[1]))
		check(not to_work.is_empty(), "people find the way from the gate to the work spot of %s" % String(pl.id))
	g.world.free()


# ------------------------------------------------------- the real module agrees --

## Once sim.lots reads this file, its mouths, kits, plots and slots must be the ones these tests check.
func test_the_module_reads_the_data_the_way_these_tests_do() -> void:
	var d := _data()
	if d.is_empty():
		return
	var g := Helpers.make(1, 1, 3)
	var sim = g.sim
	if sim.get("lots") == null:
		print("        note: sim.lots is not wired yet; the module cross-check was skipped")
		g.world.free()
		return
	var lots = sim.lots
	for method in ["lots", "mouths", "mouth", "kits", "kits_for"]:
		if not lots.has_method(method):
			print("        note: sim.lots has no %s() yet; the module cross-check was skipped" % method)
			g.world.free()
			return
	check(bool(lots.on), "the small start has lots")
	eq(lots.lots().size(), 3, "the module has the three lots")
	eq(lots.mouths().size(), _dicts(d.mouths).size(), "the module has all the mouths")
	eq(lots.kits().size(), (d.kits as Dictionary).size(), "the module has all the kits")
	for m in _dicts(d.mouths):
		var id := String(m.id)
		var mm: Dictionary = lots.mouth(id)
		check(not mm.is_empty(), "the module knows %s" % id)
		if mm.is_empty():
			continue
		eq(mm.slots.size(), _dicts(m.slots).size(), "%s: the same number of slots" % id)
		near(float(mm.length), float(m.length), 1.0e-9, "%s: the same length" % id)
		eq(String(mm.dir), String(m.dir), "%s: the same direction" % id)
		eq(String(mm.lot), String(m.lot), "%s: the same lot" % id)
		var want: Array = []
		for k in m.kits:
			want.append("wall_%s" % String(k))
		want.sort()
		var got: Array = lots.kits_for(id)
		got.sort()
		eq(got, want, "%s: the kits the module offers" % id)
		var pl: Dictionary = sim.build.plot(id)
		check(not pl.is_empty(), "%s is a plot of the build module" % id)
		if not pl.is_empty():
			eq(String(pl.kind), "mouth", "%s is a mouth plot" % id)
	for p in _dicts(d.plots):
		var pl2: Dictionary = sim.build.plot(String(p.id))
		check(not pl2.is_empty(), "%s is a plot of the build module" % String(p.id))
		if not pl2.is_empty():
			eq(String(pl2.kind), "ring", "%s is a ring plot" % String(p.id))
			eq(String(pl2.lot), String(p.lot), "%s: the same lot" % String(p.id))
			check(Vector2(pl2.pos).is_equal_approx(_vec(p.pos)), "%s: the same place" % String(p.id))
	g.world.free()
