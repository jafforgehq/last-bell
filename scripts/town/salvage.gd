## SALVAGE (One House): the furniture of a cleared house and the wrecks of the street can be STRIPPED for scrap, for good, once each. A sim part of the town (scripts/town/town_sim.gd PARTS:
## `sim.salvage`); every number is in assets/data/salvage.json (the yield and the seconds of each kind, the caps, the reach). Nothing here is the school's or the no-player sim's.
##
## THE PIECES. The town is made from its seed, so a piece of it is named by its place in the generator's object list: `"o123"` is `town_data.data.objects[123]` (stable for a seed; a save keeps the
## ids with their kind, and an id whose kind has changed under a newer generator is dropped on a load). Only the kinds of salvage.json are pieces, only solid ones. They are found lazily, the
## first time anyone asks (the title's town never does).
##
## WHAT MAY BE STRIPPED (`why_not`, "" when it may). A piece in a house: the house is CLEAR (`clearing.house_clear` and none of the dead in it now), is not the base (the claimed house, the
## rest of its lot, nor its compound), is not one of the houses the player is offered to claim until a base is claimed elsewhere, the piece is not in the room of a survivor who has not joined,
## a searchable piece (a container) has been searched, and the house's cap is not reached. A piece in the street: none of the awake dead within `danger_r` tiles of it, not in the base's
## compound, and the cap of its 32 x 32 cell is not reached. A piece that would go past a cap gives what is left of it. SCAV3: a car or a wreck of the street is a container too (scripts/town/car_loot.gd,
## `piece.container` is its "car<n>"), so, like a fridge, it can be stripped only after it has been searched ("Search it first"): by the avatar's E, or by the crew on a trip (scripts/town/crew_search.gd).
##
## THE PLAYER (E, kind "strip": `uses.gd` asks the provider of this part): "Strip the sofa (+3 scrap, 8 s)" within `reach` tiles of the piece's edge, a timed session like a search (the ring);
## it ends undone when she walks, fires, is hurt, or when the piece may no longer be stripped. When it ends done: `strip(id, her)`.
## THE CREW (the Scavenger job asks and calls these; the crew's own timer runs the seconds): `candidates(house_id, from_pos)`, `available(house_id)`, `strip(id, actor)`,
## `street_candidates(near_pos, radius)`, `piece(id)`.
##
## WHAT HAPPENS: the scrap goes to `sim.stock`, the piece's tiles are opened to walking, to the dead's path grid and to a shot (the world's solid grids, the shot_low grid, the pathfinders: `sim.block_tiles`),
## and `{"type": "stripped", "piece", "house", "scrap", "kind", "x", "y", "by", "clean"}` is told; scripts/render/salvage_marks.gd takes the piece out of the world's drawing and leaves rubble,
## the pop and the sound. Saved: the stripped ids with their kind and what they gave (the caps are worked out from them).
extends RefCounted

const DATA_PATH := "res://assets/data/salvage.json"
const Arrival := preload("res://scripts/town/arrival.gd")
const EPS := 1.0e-6
## The kind of the candidates of E and the kind of the session in hand (`uses.in_session`).
const KIND := "strip"
## How long (seconds of the rules, `sim.t`) the count of the dead in a house and the awake dead near a car are kept before they are counted again.
const LOOK_EVERY := 0.5

var sim
var enabled := true
## id -> [kind, scrap it gave]
var stripped := {}

var _data := {}
var _read := false
var _built := false
var _pieces := {}
var _by_house := {}
var _street := {}
var _cont_piece := {}
var _taken_house := {}
var _taken_cell := {}
var _dead_seen := {}
var _awake_seen := {}
var _provider
## The piece the avatar's session is at ("" when none).
var _session_id := ""


## What the avatar's E sees of this part (`uses.register`): `candidates(p)` and `use(c)`, which this part cannot have itself (`candidates(house_id, from_pos)` is the crew's).
class Provider:
	extends RefCounted
	var owner

	func candidates(p) -> Array:
		return owner.avatar_candidates(p)

	func use(c: Dictionary) -> Dictionary:
		return owner.avatar_use(c)


func setup(s) -> void:
	sim = s
	_register()


func start() -> void:
	stripped = {}
	_taken_house = {}
	_taken_cell = {}
	_dead_seen = {}
	_awake_seen = {}
	_session_id = ""
	_register()


## The time the counts are kept by (the rules' clock).
func _now() -> float:
	return float(sim.t) if sim != null else 0.0


func _register() -> void:
	var u = sim.get("uses") if sim != null else null
	if u == null or not u.has_method("register"):
		return
	if _provider == null:
		_provider = Provider.new()
		_provider.owner = self
	u.register(_provider)


# ----------------------------------------------------------------------------- the data --

func _cfg() -> Dictionary:
	if not _read:
		_read = true
		if FileAccess.file_exists(DATA_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


func _num(path: String, fallback: float) -> float:
	var cur = _cfg()
	for k in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not (cur as Dictionary).has(k):
			return fallback
		cur = cur[k]
	return float(cur) if typeof(cur) == TYPE_INT or typeof(cur) == TYPE_FLOAT else fallback


func _hs():
	return sim.get("houses")


func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


## The pieces of the town: id -> {id, idx (in data.objects), kind, name, stuff, scrap, seconds, house (-1: the street), room, cx, cy, rect (Rect2i, the tiles), cell, container (id or "")}.
func _build() -> void:
	_built = true
	_pieces = {}
	_by_house = {}
	_street = {}
	_cont_piece = {}
	var town = sim.get("town_data")
	if typeof(town) != TYPE_DICTIONARY or town.is_empty() or typeof(town.get("data")) != TYPE_DICTIONARY:
		return
	var objs: Array = town.data.get("objects", [])
	var kinds: Dictionary = _cfg().get("kinds", {})
	var cell := maxi(1, int(_num("caps.cell_size", 32.0)))
	var conts := {}
	for c in town.get("containers", []):
		var at: Vector2 = c.at
		conts["%.3f,%.3f" % [at.x, at.y]] = String(c.id)
	var hs = _hs()
	var car_ids: bool = hs != null and hs.has_method("car_id_of")
	# (TEMPO: every piece's seconds times salvage.json `seconds_mult`: the hands' time, and the crew's timer reads the same number)
	var seconds_mult := maxf(_num("seconds_mult", 1.0), 0.1)
	for i in objs.size():
		var o: Dictionary = objs[i]
		var k := String(o.get("kind", ""))
		if not kinds.has(k) or not bool(o.get("solid", false)) or String(o.get("kit", "")) == "":
			continue
		var def: Dictionary = kinds[k]
		var w := maxi(1, int(o.w))
		var h := maxi(1, int(o.h))
		var cx := float(o.cx)
		var cy := float(o.cy)
		var rect := Rect2i(roundi(cx - float(w) / 2.0), roundi(cy - float(h) / 2.0), w, h)
		var house := int(o.get("in", -1))
		var id := "o%d" % i
		var cont: String = String(conts.get("%.3f,%.3f" % [cx, cy], ""))
		if cont == "" and car_ids:
			cont = String(hs.car_id_of(i))    # (SCAV3: a car of the street is a container too: it is searched before it is stripped, like a fridge)
		var pc := {
			"id": id, "idx": i, "kind": k, "name": String(def.get("name", k.replace("_", " "))), "stuff": String(def.get("stuff", "wood")),
			"scrap": int(def.get("scrap", 0)), "seconds": float(def.get("seconds", 5.0)) * seconds_mult, "house": house,
			"room": int(hs.room_at(cx, cy)) if hs != null and house >= 0 else -1,
			"cx": cx, "cy": cy, "rect": rect, "cell": floori(cy / float(cell)) * 1000 + floori(cx / float(cell)), "container": cont,
		}
		if int(pc.scrap) <= 0:
			continue
		_pieces[id] = pc
		if cont != "":
			_cont_piece[cont] = id
		if house >= 0:
			if not _by_house.has(house):
				_by_house[house] = []
			_by_house[house].append(id)
		else:
			if not _street.has(pc.cell):
				_street[pc.cell] = []
			_street[pc.cell].append(id)
	_recount()


## The sums taken from each house and each street cell, from `stripped` (a load, or the pieces built after the strips).
func _recount() -> void:
	_taken_house = {}
	_taken_cell = {}
	for id in stripped:
		var pc: Dictionary = _pieces.get(id, {})
		if pc.is_empty():
			continue
		var n := int(stripped[id][1])
		if int(pc.house) >= 0:
			_taken_house[int(pc.house)] = int(_taken_house.get(int(pc.house), 0)) + n
		else:
			_taken_cell[int(pc.cell)] = int(_taken_cell.get(int(pc.cell), 0)) + n


func _ensure() -> void:
	if not _built:
		_build()


# ------------------------------------------------------------------------------- the caps --

## The most scrap the furniture of house `h` can give.
func cap_of(h: int) -> int:
	var hs = _hs()
	var type := String(hs.house(h).get("type", "")) if hs != null else ""
	var by_type = _cfg().get("caps", {}).get("by_type", {})
	if typeof(by_type) == TYPE_DICTIONARY and (by_type as Dictionary).has(type):
		return int(by_type[type])
	return int(_num("caps.house", 14.0))


## What is left under the cap of house `h` (the cap less what was taken: no rules about whether the house may be stripped now).
func cap_left(h: int) -> int:
	return maxi(0, cap_of(h) - int(_taken_house.get(h, 0)))


func _cell_left(cell: int) -> int:
	return maxi(0, int(_num("caps.street_cell", 12.0)) - int(_taken_cell.get(cell, 0)))


func _left_of(pc: Dictionary) -> int:
	return cap_left(int(pc.house)) if int(pc.house) >= 0 else _cell_left(int(pc.cell))


## What stripping `pc` gives now: its scrap, or what is left under the cap when that is less.
func _yield_of(pc: Dictionary) -> int:
	return mini(int(pc.scrap), _left_of(pc))


# ----------------------------------------------------------------------------- the rules --

func _is_base_lot(h: int) -> bool:
	var base = sim.get("base")
	var hs = _hs()
	if base == null or hs == null or not bool(base.get("claimed")):
		return false
	var bh := int(base.house)
	if h == bh:
		return true
	var a: Dictionary = hs.house(h)
	var b: Dictionary = hs.house(bh)
	return not a.is_empty() and not b.is_empty() and a.get("lot") == b.get("lot")


func _in_compound(x: float, y: float) -> bool:
	var base = sim.get("base")
	return base != null and bool(base.get("claimed")) and base.compound().has_point(Vector2(x, y))


## The dead in a house now (the field counts every record: kept for LOOK_EVERY seconds).
func _dead_in(h: int) -> int:
	var e = _dead_seen.get(h)
	var now := _now()
	if e != null and now >= float(e[0]) and now - float(e[0]) < LOOK_EVERY:
		return int(e[1])
	var n := int(_hs().dead_in_house(h)) if _hs() != null else 0
	_dead_seen[h] = [now, n]
	return n


func _survivor_here(pc: Dictionary) -> bool:
	var rs = sim.get("rescue")
	if rs == null or not rs.has_method("list"):
		return false
	for rec in rs.list():
		var st := String(rec.get("state", ""))
		if st == "joined" or st == "lost":
			continue
		if int(rec.get("room", -2)) == int(pc.room) and int(pc.room) >= 0:
			return true
	return false


## Why the house cannot be stripped now ("" when it can): not clear, the base's, a house to be claimed, the dead are in it.
func house_why_not(h: int) -> String:
	var cl = sim.get("clearing")
	if cl == null or h < 0 or not cl.house_clear(h):
		return "The house is not clear"
	if _is_base_lot(h):
		return "That is your home"
	var base = sim.get("base")
	var town = sim.get("town_data")
	if (base == null or not bool(base.get("claimed"))) and typeof(town) == TYPE_DICTIONARY and not town.is_empty():
		if Arrival.is_candidate(town, h) or h == int(_hs().start_house()):
			return "Claim a house first"
	if _dead_in(h) > 0:
		return "There are dead in the house"
	return ""


func _awake_near(x: float, y: float, r: float) -> bool:
	var key := floori(x / 4.0) * 100000 + floori(y / 4.0)
	var e = _awake_seen.get(key)
	var now := _now()
	if e != null and now >= float(e[0]) and now - float(e[0]) < LOOK_EVERY:
		return bool(e[1])
	var r2 := r * r
	var found := false
	for z in sim.zombies:
		if z.state == "dead" or z.state == "dying":
			continue
		var dx: float = z.x - x
		var dy: float = z.y - y
		if dx * dx + dy * dy <= r2:
			found = true
			break
	_awake_seen[key] = [now, found]
	return found


## Why a piece cannot be stripped now ("" when it can).
func why_not(pc: Dictionary) -> String:
	if not enabled:
		return "Not here"
	if stripped.has(pc.id):
		return "Already stripped"
	var h := int(pc.house)
	if h >= 0:
		var why := house_why_not(h)
		if why != "":
			return why
		if cap_left(h) <= 0:
			return "Picked clean"
		if String(pc.container) != "":
			var search = sim.get("search")
			if search != null and not search.is_looted(String(pc.container)):
				return "Search it first"
		if _survivor_here(pc):
			return "Somebody is hiding here"
		return ""
	if _in_compound(float(pc.cx), float(pc.cy)):
		return "That is your home"
	if _cell_left(int(pc.cell)) <= 0:
		return "Picked clean"
	if String(pc.container) != "":
		var search2 = sim.get("search")
		if search2 != null and not search2.is_looted(String(pc.container)):
			return "Search it first"    # (SCAV3: a car or a wreck of the street is searched before it is stripped)
	if _awake_near(float(pc.cx), float(pc.cy), _num("danger_r", 15.0)):
		return "The dead are near"
	return ""


# ------------------------------------------------------------------------------ the crew --

## The pieces of house `house_id` that can be stripped now, nearest first from `from_pos` (the house's middle when none is given): [{id, kind, name, pos (the piece's middle), scrap (what it gives now),
## seconds}]. [] when the house cannot be stripped (not clear, the base's, picked clean...). A piece the avatar has in hand is left out.
func candidates(house_id: int, from_pos: Vector2 = Vector2.INF) -> Array:
	_ensure()
	var out: Array = []
	if not enabled or house_id < 0 or house_why_not(house_id) != "" or cap_left(house_id) <= 0:
		return out
	var at := from_pos
	if at == Vector2.INF:
		var rect: Rect2i = _hs().house(house_id).get("rect", Rect2i())
		at = Vector2(rect.position) + Vector2(rect.size) * 0.5
	var u = sim.get("uses")
	for id in _by_house.get(house_id, []):
		var pc: Dictionary = _pieces[id]
		if why_not(pc) != "" or (u != null and u.in_session(KIND, id)):
			continue
		out.append(_entry(pc, at))
	out.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
	return out


## How much scrap a hand could still get from house `house_id` now: the cap left, or less if the pieces that can be stripped do not add up to it; 0 when the house cannot be stripped now.
func available(house_id: int) -> int:
	_ensure()
	var left := cap_left(house_id)
	if not enabled or left <= 0 or house_why_not(house_id) != "":
		return 0
	var sum := 0
	for id in _by_house.get(house_id, []):
		var pc: Dictionary = _pieces[id]
		if why_not(pc) == "":
			sum += int(pc.scrap)
	return mini(left, sum)


## The pieces in the street (cars, wrecks, sheds, benches) within `radius` tiles of `near_pos` that can be stripped now, nearest first, in the shape of `candidates`.
func street_candidates(near_pos: Vector2, radius: float) -> Array:
	_ensure()
	var out: Array = []
	if not enabled:
		return out
	var cell := maxi(1, int(_num("caps.cell_size", 32.0)))
	var u = sim.get("uses")
	var x0 := floori((near_pos.x - radius) / float(cell))
	var x1 := floori((near_pos.x + radius) / float(cell))
	var y0 := floori((near_pos.y - radius) / float(cell))
	var y1 := floori((near_pos.y + radius) / float(cell))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			for id in _street.get(cy * 1000 + cx, []):
				var pc: Dictionary = _pieces[id]
				if Vector2(pc.cx, pc.cy).distance_to(near_pos) > radius or why_not(pc) != "" or (u != null and u.in_session(KIND, id)):
					continue
				out.append(_entry(pc, near_pos))
	out.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
	return out


func _entry(pc: Dictionary, from: Vector2) -> Dictionary:
	var at := Vector2(pc.cx, pc.cy)
	return {"id": String(pc.id), "kind": String(pc.kind), "name": String(pc.name), "pos": at, "scrap": _yield_of(pc), "seconds": float(pc.seconds), "dist": at.distance_to(from)}


## A piece of the town ({} for an id that is none): {id, idx, kind, name, stuff, scrap, seconds, house, room, cx, cy, rect, cell, container}. A copy.
func piece(id: String) -> Dictionary:
	_ensure()
	return (_pieces[id] as Dictionary).duplicate() if _pieces.has(id) else {}


## Whether the furniture of container `container_id` (scripts/town/houses.gd) has been stripped: it is gone, and the view draws no open look over it.
func container_stripped(container_id: String) -> bool:
	if stripped.is_empty():
		return false
	_ensure()
	return _cont_piece.has(container_id) and stripped.has(String(_cont_piece[container_id]))


## The pieces of one kind of the town (ids), for the stagings and the reports.
func pieces_of_kind(kind: String) -> Array:
	_ensure()
	var out: Array = []
	for id in _pieces:
		if String(_pieces[id].kind) == kind:
			out.append(id)
	return out


## Strips piece `id` now (the crew's own timer calls it when its seconds are up; the avatar's session calls it when it is done): {"ok", "scrap" (what it gave), "why"}. `actor` is a person, an id or null.
func strip(id: String, actor = null) -> Dictionary:
	_ensure()
	if not _pieces.has(id):
		return {"ok": false, "scrap": 0, "why": "There is nothing there to strip"}
	var pc: Dictionary = _pieces[id]
	var why := why_not(pc)
	if why != "":
		return {"ok": false, "scrap": 0, "why": why}
	var n := _yield_of(pc)
	if n <= 0:
		return {"ok": false, "scrap": 0, "why": "Picked clean"}
	_apply(pc, n, actor)
	return {"ok": true, "scrap": n, "why": ""}


func _apply(pc: Dictionary, n: int, actor) -> void:
	var id := String(pc.id)
	stripped[id] = [String(pc.kind), n]
	var h := int(pc.house)
	if h >= 0:
		_taken_house[h] = int(_taken_house.get(h, 0)) + n
	else:
		_taken_cell[int(pc.cell)] = int(_taken_cell.get(int(pc.cell), 0)) + n
	if sim.stock.has("scrap"):
		sim.stock["scrap"] = float(sim.stock["scrap"]) + float(n)
	_open_tiles(pc)
	var who := ""
	if typeof(actor) == TYPE_OBJECT and actor != null and "id" in actor:
		who = String(actor.id)
	elif typeof(actor) == TYPE_STRING:
		who = String(actor)
	sim.events.append({"type": "stripped", "piece": id, "house": h, "scrap": n, "kind": String(pc.kind), "x": float(pc.cx), "y": float(pc.cy), "by": who, "clean": _left_of(pc) <= 0})


## The piece's tiles are free ground: walking, the dead's path grid, the shot over them. A tile that another solid thing stands on (a second prop on a corner, a wall, a fence) stays shut.
func _open_tiles(pc: Dictionary) -> void:
	var world = sim.get("world")
	if world == null:
		return
	var W: int = world.W
	var rect: Rect2i = pc.rect
	var shared := {}
	var town = sim.get("town_data")
	if typeof(town) == TYPE_DICTIONARY and not town.is_empty():
		var objs: Array = town.data.get("objects", [])
		for j in objs.size():
			if j == int(pc.idx) or not bool(objs[j].get("solid", false)) or stripped.has("o%d" % j):
				continue
			var o: Dictionary = objs[j]
			var ow := int(o.w)
			var oh := int(o.h)
			var r2 := Rect2i(roundi(float(o.cx) - float(ow) / 2.0), roundi(float(o.cy) - float(oh) / 2.0), ow, oh)
			if r2.intersects(rect):
				for y in range(maxi(rect.position.y, r2.position.y), mini(rect.end.y, r2.end.y)):
					for x in range(maxi(rect.position.x, r2.position.x), mini(rect.end.x, r2.end.x)):
						shared[y * W + x] = true
	var tiles: Array = []
	var grp = world.get("grp")
	var fence = world.get("fence")
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := y * W + x
			if x < 0 or y < 0 or x >= W or y >= int(world.H) or shared.has(i):
				continue
			if grp is PackedByteArray and (grp as PackedByteArray).size() > i and int(grp[i]) == 255:
				continue    # (a wall's top)
			if fence is PackedByteArray and (fence as PackedByteArray).size() > i and int(fence[i]) != 0:
				continue    # (a fence or a hedge)
			tiles.append(i)
	if tiles.is_empty():
		return
	sim.block_tiles(tiles, false)
	var low = world.get("shot_low")
	if low is PackedByteArray and (low as PackedByteArray).size() == W * int(world.H):
		for i in tiles:
			world.shot_low[int(i)] = 0


# ---------------------------------------------------------------------------- the avatar --

## The distance from a point to the nearest point of a rectangle of tiles (0 inside it).
static func rect_dist(at: Vector2, rect: Rect2i) -> float:
	var dx := maxf(maxf(float(rect.position.x) - at.x, at.x - float(rect.end.x)), 0.0)
	var dy := maxf(maxf(float(rect.position.y) - at.y, at.y - float(rect.end.y)), 0.0)
	return sqrt(dx * dx + dy * dy)


func _nearby(here: Vector2, h: int) -> Array:
	var out: Array = []
	if h >= 0:
		for id in _by_house.get(h, []):
			out.append(_pieces[id])
		return out
	var cell := maxi(1, int(_num("caps.cell_size", 32.0)))
	var cx := floori(here.x / float(cell))
	var cy := floori(here.y / float(cell))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for id in _street.get((cy + dy) * 1000 + cx + dx, []):
				out.append(_pieces[id])
	return out


func _label(pc: Dictionary, n: int, stop: bool) -> String:
	if stop:
		return "Stop stripping"
	return "Strip the %s (+%d scrap, %d s)" % [String(pc.name), n, roundi(float(pc.seconds))]


## E's candidates of this part ({kind "strip", ...}: the shape of the town's other uses): every piece within `reach` tiles of the avatar that may be stripped, in the house she is in (or, outside every house, in the street).
func avatar_candidates(p) -> Array:
	var out: Array = []
	if not enabled or p == null or _hs() == null:
		return out
	_ensure()
	var here := Vector2(p.x, p.y)
	var h: int = _hs().house_at(p.x, p.y)
	var reach := _num("reach", 1.0)
	var u = sim.get("uses")
	for pc in _nearby(here, h):
		var d := rect_dist(here, pc.rect)
		if d > reach:
			continue
		var id := String(pc.id)
		var stop: bool = u != null and u.in_session(KIND, id)
		if not stop and why_not(pc) != "":
			continue
		out.append({"kind": KIND, "id": id, "label": _label(pc, _yield_of(pc), stop), "pos": Vector2(pc.cx, pc.cy), "dist": d, "ok": true, "why": "", "session": true})
	return out


## E at a candidate of this part: the session begun (E again stops it); {} for a kind that is not this part's.
func avatar_use(c: Dictionary) -> Dictionary:
	if String(c.get("kind", "")) != KIND:
		return {}
	_ensure()
	var id := String(c.get("id", ""))
	var u = sim.get("uses")
	var p = _lead()
	if u == null or p == null or not _pieces.has(id):
		return {"ok": false, "line": "", "why": "There is nothing there to strip", "session": true}
	if u.in_session(KIND, id):
		u.cancel("stopped")
		return {"ok": true, "line": "Stopped.", "why": "", "session": true, "stopped": true}
	var pc: Dictionary = _pieces[id]
	var why := why_not(pc)
	if why != "":
		return {"ok": false, "line": "", "why": why, "session": true}
	var here := Vector2(p.x, p.y)
	if rect_dist(here, pc.rect) > _num("reach", 1.0) + 0.3:
		return {"ok": false, "line": "", "why": "Too far from it", "session": true}
	var secs := float(pc.seconds)
	var r: Dictionary = u.begin_session(KIND, id, "Stripping", secs, here, 0.7, Callable(self, "_finish").bind(id))
	if not bool(r.get("ok", false)):
		return {"ok": false, "line": "", "why": String(r.get("why", "")), "session": true}
	_session_id = id
	return {"ok": true, "line": "Stripping the %s" % String(pc.name), "why": "", "session": true, "seconds": secs}


## The avatar's session ran its course.
func _finish(id: String) -> void:
	strip(id, _lead())


# -------------------------------------------------------------------------------- the step --

## Looks every step while the avatar is stripping: a house that has the dead in it, a dead one come near a car, a cap reached by somebody else end the session undone.
func update(_dt: float) -> void:
	if _session_id == "":
		return
	var u = sim.get("uses")
	if u == null or not u.in_session(KIND, _session_id):
		_session_id = ""
		return
	if why_not(_pieces[_session_id]) != "":
		u.cancel("blocked")
		_session_id = ""


## The piece the avatar's session is at now ({} when she is not stripping): the view's work sounds read what it is made of.
func session_piece() -> Dictionary:
	if _session_id == "":
		return {}
	var u = sim.get("uses")
	if u == null or not u.in_session(KIND, _session_id):
		return {}
	return _pieces.get(_session_id, {})


# ---------------------------------------------------------------------------------- numbers --

## For the balance report (tools and the stagings, not the game): {"houses": houses with something to strip, "scrap": sum over the houses of what they can give under their caps, "raw": the same
## with no cap, "street": pieces in the street, "street_scrap": what they can give under the cell cap}. Every house counted, whether it is clear or not.
func potential() -> Dictionary:
	_ensure()
	var houses := 0
	var scrap := 0
	var raw := 0
	for h in _by_house:
		var sum := 0
		for id in _by_house[h]:
			sum += int(_pieces[id].scrap)
		houses += 1
		raw += sum
		scrap += mini(sum, cap_of(int(h)))
	var cells := {}
	var s_n := 0
	var s_secs := 0.0
	for cell in _street:
		var sum2 := 0
		for id in _street[cell]:
			sum2 += int(_pieces[id].scrap)
			s_secs += float(_pieces[id].seconds)
			s_n += 1
		cells[cell] = mini(sum2, int(_num("caps.street_cell", 12.0)))
	var s_scrap := 0
	for cell in cells:
		s_scrap += int(cells[cell])
	# (RULES2: the longest any piece takes the avatar's hands, which must stay about 15 s or less, and what the street's pieces take in all)
	var longest := 0.0
	for id in _pieces:
		longest = maxf(longest, float(_pieces[id].seconds))
	return {"houses": houses, "scrap": scrap, "raw": raw, "street": s_n, "street_scrap": s_scrap, "street_secs": s_secs, "longest_s": longest}


## The raw scrap and the seconds of the pieces of house `h` (all of them, no rules): {"scrap", "seconds" (the avatar's hands, `seconds` x `seconds_mult` of each), "pieces", "capped" (the scrap
## under the house's cap), "s_per_scrap" (seconds for a capped scrap: 8.9 in a town of seed 1, RULES2)}.
func house_sum(h: int) -> Dictionary:
	_ensure()
	var scrap := 0
	var secs := 0.0
	var n := 0
	for id in _by_house.get(h, []):
		scrap += int(_pieces[id].scrap)
		secs += float(_pieces[id].seconds)
		n += 1
	var capped := mini(scrap, cap_of(h))
	return {"scrap": scrap, "seconds": secs, "pieces": n, "capped": capped, "s_per_scrap": secs / maxf(float(capped), 1.0)}


# ------------------------------------------------------------------------------------ save --

func save() -> Dictionary:
	var ids: Array = stripped.keys()
	ids.sort()
	var out := {}
	for id in ids:
		out[id] = [String(stripped[id][0]), int(stripped[id][1])]
	return {"stripped": out}


## The stripped ids come back with their solid tiles opened (the world is made from the seed again: the view takes the pieces out of its drawing from `stripped`, scripts/render/salvage_marks.gd).
func load_state(d: Dictionary) -> void:
	start()
	_ensure()
	var s = d.get("stripped", {})
	if typeof(s) != TYPE_DICTIONARY:
		return
	for id in s:
		var v = s[id]
		var pc: Dictionary = _pieces.get(String(id), {})
		if pc.is_empty() or typeof(v) != TYPE_ARRAY or (v as Array).size() < 2 or String(v[0]) != String(pc.kind):
			continue
		stripped[String(id)] = [String(v[0]), maxi(0, int(v[1]))]
	_recount()
	for id in stripped:
		_open_tiles(_pieces[id])
