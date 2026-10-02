## The convoy (round 15, "the yard in motion"): where the colony's vehicles park in the motor pool, the smooth path each one
## drives out and in by, and where a person stands to use a door of a parked car. Pure and static: it only reads
## assets/data/motor_pool.json (the geometry, written by task GATE) and assets/data/vehicles.json (the size of each kind
## and, when it has them, its doors), and holds nothing of the game. The sim never moves a car: the view asks `pose` with
## `drive_t / drive_len` of the party (scripts/sim/scavenge.gd), so a car's place is a pure function of the saved state.
##
## The data (tiles; x east, y south; the file says it all):
##   spots[i] = {id: i, at: [x, y], out_route: [point], in_route: [point]}  `at` is the centre of the parked car (it
##              parks nose to the north), `out_route` starts there and ends off the map, `in_route` starts off the map
##              and ends there.
##   point    = {x, y, r?, rev?, h?}
##     r      the radius of the round given to the corner at this point (0 or none: a sharp one)
##     rev    true: the leg that ARRIVES at this point is driven in reverse (the nose keeps its heading while the car
##            moves backwards: heading = the way of travel plus half a turn). A change from forward to reverse (or back)
##            is a stop: no round is cut there and the nose swings across the following leg (see below).
##     h      the nose's heading at this point in degrees (0 east, 90 south, 270 north), for a hand-tuned swing.
## The nose follows the way of travel unless something is set. Where a point carries `h`, or sits next to one, or is a stop
## where the car changes gear (or the first point after one), the heading is interpolated by the distance driven between the
## points, from the heading the car has at one point to the heading it has at the next, the angles unwrapped by the
## shortest way (an exact half turn goes clockwise as drawn): the nose never jumps. Break a big swing into steps of up to
## 170 degrees (90, 180, 270) to say which way round it goes.
##
## `problems(raw)` says what is wrong with the contents of a file, a sentence each (an empty list: it is sound);
## tests/test_convoy.gd runs it on the real file, so a bad number is found by the suite and not in play, where a missing or
## broken file only means no spots.
##
## Calls:
##   spots() -> int                  how many places the motor pool has
##   bay(spot) -> Vector2            the centre of the parked car
##   route(spot, "out"|"in") -> Array   the points of the file as plain data (do not change them); [] for a spot that is not
##   length(route) -> float          tiles of the SMOOTH path
##   pose(route, progress) -> {pos: Vector2 (the car's centre, tiles), heading: float (radians, 0 east, 90 degrees south;
##                            the nose), reverse: bool}   progress 0 to 1 of the length, clamped
##   door_spot(spot, kind, door_id) -> Vector2   where a person stands beside that door of the car parked at that spot
extends RefCounted

const DATA_PATH := "res://assets/data/motor_pool.json"
const VEHICLES_PATH := "res://assets/data/vehicles.json"
const OBJECTS := "res://assets/objects/"
## Where the files are read from (the tests point them at files of their own and `forget` the cache).
static var data_path := DATA_PATH
static var vehicles_path := VEHICLES_PATH

## A person at a door stands this far outside the body of the car (tiles).
const DOOR_GAP := 0.45
## The size of a car of a kind the data does not know (tiles), and the place of a door nobody described, as a share of the
## body from the nose: the front doors a third of the way back, the rear doors two thirds, a bus's one door at the front.
const DEFAULT_W := 2.2
const DEFAULT_H := 4.4
const FRONT_DOOR := 1.0 / 3.0
const REAR_DOOR := 2.0 / 3.0
const BUS_DOOR := 0.12
## Where a spot that does not exist is taken to be (the gate, so nothing is thrown at the view).
const NOWHERE := Vector2(39.0, 18.9)

static var _pool_path := ""
static var _pool: Array = []
## The aisle's middle (x, tiles), or -1 when the file has none.
static var _aisle_x := -1.0
static var _kinds_path := ""
static var _kinds: Dictionary = {}
static var _sizes := {}
static var _compiled := {}


## Drops what was read (after a test changed `data_path` or `vehicles_path`).
static func forget() -> void:
	_pool_path = ""
	_pool = []
	_kinds_path = ""
	_kinds = {}
	_sizes = {}
	_compiled = {}


# ------------------------------------------------------------------------ the data --

## What is wrong with the contents of a motor pool file, one sentence each; empty when it is sound.
static func problems(raw) -> Array:
	var out: Array = []
	if not raw is Dictionary:
		return ["the file is not an object"]
	var spots = raw.get("spots")
	if not spots is Array or spots.is_empty():
		return ["there are no spots"]
	for i in spots.size():
		var s = spots[i]
		var tag := "spot %d" % i
		if not s is Dictionary:
			out.append("%s is not an object" % tag)
			continue
		if not _is_number(s.get("id")) or int(s.id) != i:
			out.append("%s: id must be %d (the spots are numbered from 0 in order)" % [tag, i])
		var at = s.get("at")
		var at_ok: bool = at is Array and at.size() == 2 and _is_number(at[0]) and _is_number(at[1])
		if not at_ok:
			out.append("%s: `at` must be [x, y]" % tag)
		for key in ["out_route", "in_route"]:
			var route = s.get(key)
			if not route is Array or route.size() < 2:
				out.append("%s: %s must be a list of at least two points" % [tag, key])
				continue
			var good := true
			for j in route.size():
				var p = route[j]
				var where := "%s: %s point %d" % [tag, key, j]
				if not p is Dictionary or not _is_number(p.get("x")) or not _is_number(p.get("y")):
					out.append("%s needs a number x and a number y" % where)
					good = false
					continue
				if p.has("r") and (not _is_number(p.r) or float(p.r) < 0.0):
					out.append("%s: the radius `r` must be a number, 0 or more" % where)
				if p.has("rev") and typeof(p.rev) != TYPE_BOOL:
					out.append("%s: `rev` must be true or false" % where)
				if p.has("h") and not _is_number(p.h):
					out.append("%s: `h` must be a number of degrees" % where)
				if j > 0 and route[j - 1] is Dictionary and _is_number(route[j - 1].get("x")) and _is_number(route[j - 1].get("y")):
					if Vector2(float(p.x), float(p.y)).distance_to(Vector2(float(route[j - 1].x), float(route[j - 1].y))) < 0.001:
						out.append("%s is in the same place as the one before it (the same point twice)" % where)
			if good and at_ok:
				var bay := Vector2(float(at[0]), float(at[1]))
				var end: Dictionary = route[0] if key == "out_route" else route[route.size() - 1]
				if Vector2(float(end.x), float(end.y)).distance_to(bay) > 0.05:
					out.append("%s: %s must %s in the bay (`at`)" % [tag, key, "start" if key == "out_route" else "end"])
	return out


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _spots_data() -> Array:
	if _pool_path != data_path:
		_pool_path = data_path
		_pool = []
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		if raw is Dictionary and problems(raw).is_empty():
			for s in raw.spots:
				_pool.append({"at": Vector2(float(s.at[0]), float(s.at[1])), "out_route": _points(s.out_route), "in_route": _points(s.in_route),
						"long": bool(s.get("long", false))})
			var gate = raw.get("gate")
			_aisle_x = float(gate.get("aisle_x", -1.0)) if gate is Dictionary else -1.0
	return _pool


## The points as plain data: floats, `rev` a bool, `h` only when it was given.
static func _points(list: Array) -> Array:
	var out: Array = []
	for e in list:
		var p := {"x": float(e.x), "y": float(e.y), "r": maxf(0.0, float(e.get("r", 0.0))), "rev": bool(e.get("rev", false))}
		if e.has("h"):
			p["h"] = float(e.h)
		out.append(p)
	return out


## A vehicle this long (tiles) does not fit a bay (a sedan is 4.4, a pickup 4.15, a van 4.07; the bus is 8.07).
const LONG_FROM := 5.2
## How far from the aisle's middle a bay's car has to be for the aisle to be on one side of it.
const SIDE_MARGIN := 0.5


## The place of the pool that takes a vehicle too long for a bay (the aisle end), or -1 when the pool has none.
static func long_spot() -> int:
	var all := _spots_data()
	for i in all.size():
		if bool(all[i].get("long", false)):
			return i
	return -1


## Whether a vehicle of this kind (its data: `h`, its length in tiles) needs the long place.
static func is_long(kind_data: Dictionary) -> bool:
	return float(kind_data.get("h", 0.0)) >= LONG_FROM


## Which side of a car parked at this spot (nose to the north) the aisle is on: "R" for a bay west of the aisle, "L" for one
## east of it, "" for a place in the aisle itself or that is not there. People get in and out on this side, so that nobody has to
## walk through the car to a door on the far side.
static func aisle_side(spot: int) -> String:
	var all := _spots_data()
	if spot < 0 or spot >= all.size() or _aisle_x < 0.0:
		return ""
	var x: float = all[spot].at.x
	if x < _aisle_x - SIDE_MARGIN:
		return "R"
	if x > _aisle_x + SIDE_MARGIN:
		return "L"
	return ""


## How many places the motor pool has.
static func spots() -> int:
	return _spots_data().size()


## The centre of the car parked at this spot (it stands nose to the north). A spot that does not exist is NOWHERE.
static func bay(spot: int) -> Vector2:
	var all := _spots_data()
	if spot < 0 or spot >= all.size():
		return NOWHERE
	return all[spot].at


## The points of the way out ("out": from the bay to the far side of the map) or in ("in": the way back and into the bay).
## [] for a spot that does not exist.
static func route(spot: int, dir: String) -> Array:
	var all := _spots_data()
	if spot < 0 or spot >= all.size():
		return []
	return all[spot].out_route if dir == "out" else all[spot].in_route


# --------------------------------------------------------------------- the smooth path --

## The length in tiles of the smooth path of a route (corners rounded, so a little shorter than the polyline).
static func length(r: Array) -> float:
	return float(_path(r).total)


## Where the car is and which way it points at `progress` (0 to 1) of the route's length.
static func pose(r: Array, progress: float) -> Dictionary:
	var path := _path(r)
	var total: float = path.total
	if total <= 0.0:
		var start := Vector2.ZERO
		if not r.is_empty() and r[0] is Dictionary:
			start = Vector2(float(r[0].get("x", 0.0)), float(r[0].get("y", 0.0)))
		return {"pos": start, "heading": 0.0, "reverse": false}
	var s := clampf(progress, 0.0, 1.0) * total
	var at := _at(path, s)
	var heading := _heading_of(at)
	for link in path.links:
		if s >= float(link.s0) and s <= float(link.s1):
			var f := 1.0 if float(link.s1) <= float(link.s0) else (s - float(link.s0)) / (float(link.s1) - float(link.s0))
			heading = lerpf(float(link.a), float(link.b), f)
			break
	return {"pos": at.pos, "heading": wrapf(heading, -PI, PI), "reverse": at.rev}


static func _heading_of(at: Dictionary) -> float:
	return (at.dir as Vector2).angle() + (PI if bool(at.rev) else 0.0)


## The route made into pieces (straight lines and arcs of the rounded corners), with the distance to each point, and the
## stretches where the heading is interpolated. Kept, because the view asks every frame for the same few routes.
static func _path(r: Array) -> Dictionary:
	var key := hash(r)
	if _compiled.has(key):
		return _compiled[key]
	if _compiled.size() > 64:
		_compiled.clear()
	var path := _make_path(r)
	_compiled[key] = path
	return path


static func _make_path(r: Array) -> Dictionary:
	# the points, the same place twice taken as one
	var pts: Array = []
	for e in r:
		if not e is Dictionary:
			continue
		var p := Vector2(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
		if not pts.is_empty() and (pts[pts.size() - 1].p as Vector2).distance_to(p) < 0.0001:
			var last: Dictionary = pts[pts.size() - 1]
			last.rev = last.rev or bool(e.get("rev", false))
			if e.has("h"):
				last.h = float(e.h)
				last.has_h = true
			continue
		pts.append({"p": p, "r": maxf(0.0, float(e.get("r", 0.0))), "rev": bool(e.get("rev", false)), "has_h": e.has("h"), "h": float(e.get("h", 0.0))})
	var n := pts.size()
	var path := {"total": 0.0, "pieces": [], "links": []}
	if n < 2:
		return path
	# the legs: direction, length, and whether it is driven in reverse (the point it arrives at says so)
	var dirs: Array = []
	var lens: Array = []
	var revs: Array = []
	for k in n - 1:
		var d: Vector2 = pts[k + 1].p - pts[k].p
		lens.append(d.length())
		dirs.append(d.normalized())
		revs.append(bool(pts[k + 1].rev))
	# how far each corner cuts in (its tangent length): no round at a stop where the car changes gear, none at the ends
	var turn: Array = []
	var cut: Array = []
	for i in n:
		turn.append(0.0)
		cut.append(0.0)
	for i in range(1, n - 1):
		var a: Vector2 = dirs[i - 1]
		var b: Vector2 = dirs[i]
		var theta := atan2(absf(a.cross(b)), a.dot(b))
		turn[i] = theta
		if float(pts[i].r) > 0.0 and theta > 0.0001 and theta < PI - 0.01 and revs[i - 1] == revs[i]:
			cut[i] = float(pts[i].r) * tan(theta / 2.0)
	# two corners on one leg must not need more of it than it has: both are made smaller
	for k in n - 1:
		var need: float = float(cut[k]) + float(cut[k + 1])
		if need > float(lens[k]) and need > 0.0:
			var f: float = float(lens[k]) / need
			cut[k] = float(cut[k]) * f
			cut[k + 1] = float(cut[k + 1]) * f
	# the pieces and the distance of each point (the middle of its round)
	var pieces: Array = []
	var anchors: Array = []
	for i in n:
		anchors.append(0.0)
	var s := 0.0
	for k in n - 1:
		var from: Vector2 = pts[k].p + (dirs[k] as Vector2) * float(cut[k])
		var to: Vector2 = pts[k + 1].p - (dirs[k] as Vector2) * float(cut[k + 1])
		var run := from.distance_to(to)
		if run > 1.0e-9:
			pieces.append({"line": true, "a": from, "d": dirs[k], "len": run, "s0": s, "rev": revs[k]})
			s += run
		var i: int = k + 1
		if i <= n - 2 and float(cut[i]) > 0.0:
			var d1: Vector2 = dirs[k]
			var d2: Vector2 = dirs[i]
			var side: float = 1.0 if d1.cross(d2) > 0.0 else -1.0
			var radius: float = float(cut[i]) / tan(float(turn[i]) / 2.0)
			var start: Vector2 = pts[i].p - d1 * float(cut[i])
			var centre: Vector2 = start + Vector2(-d1.y, d1.x) * radius * side
			var arc: float = radius * float(turn[i])
			pieces.append({"line": false, "c": centre, "radius": radius, "phi0": (start - centre).angle(), "sweep": side * float(turn[i]), "len": arc, "s0": s, "rev": revs[k], "side": side})
			anchors[i] = s + arc / 2.0
			s += arc
		else:
			anchors[i] = s
	anchors[n - 1] = s
	path.total = s
	path.pieces = pieces
	# the points whose heading is held: set by the data, stops, and the points beside those
	var keys := {}
	for i in n:
		if bool(pts[i].has_h):
			keys[i] = deg_to_rad(float(pts[i].h))
	var held: Array = []
	for i in n:
		if keys.has(i):
			held.append(i - 1)
			held.append(i + 1)
		elif i >= 1 and i <= n - 2 and revs[i - 1] != revs[i]:
			held.append(i)
			held.append(i + 1)
	for i in held:
		if i >= 0 and i < n and not keys.has(i):
			keys[i] = _heading_of(_at(path, maxf(0.0, float(anchors[i]) - 1.0e-7)))
	var links: Array = []
	for i in n - 1:
		if keys.has(i) and keys.has(i + 1):
			var a: float = keys[i]
			var swing := fposmod(float(keys[i + 1]) - a, TAU)
			if swing > PI:
				swing -= TAU
			links.append({"s0": anchors[i], "s1": anchors[i + 1], "a": a, "b": a + swing})
	path.links = links
	return path


## The piece of the path at distance `s`: {pos, dir (the way of travel), rev}.
static func _at(path: Dictionary, s: float) -> Dictionary:
	var pieces: Array = path.pieces
	var piece: Dictionary = pieces[pieces.size() - 1]
	for p in pieces:
		if s <= float(p.s0) + float(p.len):
			piece = p
			break
	var u: float = clampf(s - float(piece.s0), 0.0, float(piece.len))
	if bool(piece.line):
		return {"pos": (piece.a as Vector2) + (piece.d as Vector2) * u, "dir": piece.d, "rev": piece.rev}
	var phi: float = float(piece.phi0) + float(piece.sweep) * (u / float(piece.len))
	var radius: float = piece.radius
	var pos: Vector2 = (piece.c as Vector2) + Vector2(cos(phi), sin(phi)) * radius
	var dir := Vector2(-sin(phi), cos(phi)) * float(piece.side)
	return {"pos": pos, "dir": dir, "rev": piece.rev}


# --------------------------------------------------------------------------- the doors --

## Where a person stands to use door `door_id` of a car of `kind` parked at `spot`: the point just outside the body, beside
## the door. The car's size and the doors come from vehicles.json (`w`, `h` in tiles, nose to the north; `nose` and `doors`
## with each door's `side` ("L" or "R" looking along the nose) and its `panel` in the picture's pixels, when the kind has
## them). A door nobody described is placed by the usual rule: "L1" and "R1" a third of the body back from the nose, "L2"
## and "R2" two thirds, a bus's "F" on the right at the front; a kind nobody knows is a sedan.
static func door_spot(spot: int, kind: String, door_id: String) -> Vector2:
	var at := bay(spot)
	var data: Dictionary = _kind_data(kind)
	var w := float(data.get("w", DEFAULT_W))
	var h := float(data.get("h", DEFAULT_H))
	var d := _door(data, door_id)
	var x: float = at.x + (-1.0 if String(d.side) == "L" else 1.0) * (w / 2.0 + DOOR_GAP)
	return Vector2(x, at.y - h / 2.0 + float(d.u) * h)


## {side: "L"|"R", u: 0..1 the share of the body's length from the nose to the door}.
static func _door(data: Dictionary, door_id: String) -> Dictionary:
	for e in data.get("doors", []):
		if e is Dictionary and String(e.get("id", "")) == door_id:
			var u := _door_u(data, e)
			if u >= 0.0:
				return {"side": "R" if String(e.get("side", "L")) == "R" else "L", "u": u}
			return {"side": "R" if String(e.get("side", "L")) == "R" else "L", "u": _rule(door_id).u}
	return _rule(door_id)


static func _rule(door_id: String) -> Dictionary:
	if door_id == "F":
		return {"side": "R", "u": BUS_DOOR}
	var side := "R" if door_id.begins_with("R") else "L"
	return {"side": side, "u": REAR_DOOR if door_id.ends_with("2") else FRONT_DOOR}


## How far along the body from the nose a door's panel is centred, from its place in the picture; -1 when it cannot be told.
static func _door_u(data: Dictionary, door: Dictionary) -> float:
	var panel = door.get("panel")
	if not panel is Array or panel.size() < 4:
		return -1.0
	var size := _picture_size(String(data.get("art", "")))
	if size.x <= 0.0 or size.y <= 0.0:
		return -1.0
	var cx := float(panel[0]) + float(panel[2]) / 2.0
	var cy := float(panel[1]) + float(panel[3]) / 2.0
	var u := -1.0
	match String(data.get("nose", "N")):
		"S":
			u = 1.0 - cy / size.y
		"E":
			u = 1.0 - cx / size.x
		_:
			u = cy / size.y
	return clampf(u, 0.0, 1.0)


static func _picture_size(art: String) -> Vector2:
	if art == "":
		return Vector2.ZERO
	if not _sizes.has(art):
		var tex = load(OBJECTS + art + ".png") if ResourceLoader.exists(OBJECTS + art + ".png") else null
		_sizes[art] = (tex as Texture2D).get_size() if tex is Texture2D else Vector2.ZERO
	return _sizes[art]


static func _kind_data(kind: String) -> Dictionary:
	if _kinds_path != vehicles_path:
		_kinds_path = vehicles_path
		_kinds = {}
		var raw = JSON.parse_string(FileAccess.get_file_as_string(vehicles_path)) if FileAccess.file_exists(vehicles_path) else null
		if raw is Dictionary and raw.get("kinds") is Dictionary:
			_kinds = raw.kinds
	var d = _kinds.get(kind, {})
	return d if d is Dictionary else {}
