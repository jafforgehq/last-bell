## Which rooms of the town the avatar has opened, which are clear of the dead, and when a house is clear (One House, WP3, plan 1.4 and 2.2).
##
## REVEAL. A room is revealed when the avatar stands in it, when the avatar is within DOOR_REACH of one of its doors (the doorway tiles; both rooms
## of the door are opened: it is a door, not a wall), and when E at a door ("Look in", from LOOK_REACH) peeks through it. Doors never block: this is only what
## is known. The views read `is_revealed` (a dark veil on a room that is not; a dead one in it is not drawn).
## CLEAR. A revealed room that has no dead in it now (`houses.dead_in_room`, which counts the sleeping and the awake by where they stand) is clear, once:
## `room_clear`. When every room of a house is revealed and clear, `house_clear`, once. Both are saved. The claim also looks at the dead NOW
## (`claimable`): one that walked into a cleared house stops the claim.
## ENTERING. The avatar's house changes: `entered` (`first` the first time) and `left`.
##
## Events: {"type": "entered"|"left", "house", "first"}, {"type": "room_revealed", "room", "house", "name", "why"}, {"type": "room_clear", "room", "house",
## "name"}, {"type": "house_clear", "house"}. Candidates: kind "door", "Look in". Saved: the revealed and the clear rooms, the clear and the visited houses.
extends RefCounted

const EVERY := 0.25
const DOOR_REACH := 1.2
const LOOK_REACH := 2.6
## Houses farther than this from the avatar are not looked at for clear (a house the avatar left half explored is judged when it comes near again).
const JUDGE_R := 30.0
const NEAR := [Vector2(1.2, 0.0), Vector2(-1.2, 0.0), Vector2(0.0, 1.2), Vector2(0.0, -1.2)]
const NEAR_LOOK := [Vector2(2.6, 0.0), Vector2(-2.6, 0.0), Vector2(0.0, 2.6), Vector2(0.0, -2.6), Vector2(1.8, 1.8), Vector2(-1.8, 1.8), Vector2(1.8, -1.8), Vector2(-1.8, -1.8)]

var sim
var enabled := true
var revealed := {}
var cleared := {}
var done := {}
var seen := {}
## The avatar's house as of the last look (for the events).
var cur := -1
## Houses with a revealed room that are not clear yet.
var _open := {}
var _sides_of := {}
var _t := 0.0


func setup(s) -> void:
	sim = s


func start() -> void:
	revealed = {}
	cleared = {}
	done = {}
	seen = {}
	cur = -1
	_open = {}
	_t = 0.0


func _hs():
	return sim.get("houses")


func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


## An int from what `dead_in_room` gives (a number, or the field's {"left": n}).
static func _count(v) -> int:
	if typeof(v) == TYPE_DICTIONARY:
		return int(v.get("left", v.get("total", 0)))
	return int(v)


func _dead_in(room: int) -> int:
	return _count(_hs().dead_in_room(room))


# ------------------------------------------------------------------------ queries --

func is_revealed(room: int) -> bool:
	return revealed.has(room)


func is_clear(room: int) -> bool:
	return cleared.has(room)


func house_clear(h: int) -> bool:
	return done.has(h)


func visited(h: int) -> bool:
	return seen.has(h)


## The houses the avatar has been inside, for the map (house ids, ascending).
func explored() -> Array:
	var out: Array = seen.keys()
	out.sort()
	return out


## The avatar's house now (-1 outside every house, or with no avatar): read live, so a roof fades the moment a step is taken through a door.
func inside_house() -> int:
	var hs = _hs()
	var p = _lead()
	if hs == null or p == null:
		return -1
	return int(hs.house_at(p.x, p.y))


## {"ok", "why"}: may this house be claimed now. Every room looked into and clear, and none of the dead in it now ("There are still dead in the kitchen").
func claimable(h: int) -> Dictionary:
	var hs = _hs()
	if hs == null or h < 0:
		return {"ok": false, "why": "There is no house here"}
	var base = sim.get("base")
	if base != null and bool(base.claimed):
		return {"ok": false, "why": "You already have a base"}
	_check(h)
	for r in hs.rooms_of(h):
		var name := String(hs.room(r).get("name", "room"))
		if not revealed.has(r):
			return {"ok": false, "why": "You have not looked in the %s yet" % name}
		if _dead_in(r) > 0:
			return {"ok": false, "why": "There are still dead in the %s" % name}
	if int(hs.dead_in_house(h)) > 0:
		return {"ok": false, "why": "There are still dead in the house"}
	if not done.has(h):
		return {"ok": false, "why": "The house is not clear yet"}
	return {"ok": true, "why": ""}


# ------------------------------------------------------------------------ reveal --

## Opens a room to the avatar. True when it was news. `why` ("inside", "door", "peek") is for whoever reads the event.
func reveal(room: int, why: String = "") -> bool:
	var hs = _hs()
	if hs == null or room < 0 or revealed.has(room):
		return false
	var rm: Dictionary = hs.room(room)
	if rm.is_empty():
		return false
	revealed[room] = true
	var h := int(rm.get("house", -1))
	if h >= 0 and not done.has(h):
		_open[h] = true
	sim.events.append({"type": "room_revealed", "room": room, "house": h, "name": String(rm.get("name", "")), "why": why})
	return true


func _door_tiles(d: Dictionary) -> Array:
	var t = d.get("tiles", [])
	return t if typeof(t) == TYPE_ARRAY else []


func _door_dist(d: Dictionary, me: Vector2) -> float:
	var best := INF
	for t in _door_tiles(d):
		best = minf(best, me.distance_to(Vector2(float(t.x) + 0.5, float(t.y) + 0.5)))
	return best


func _door_mid(d: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for t in _door_tiles(d):
		sum += Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
		n += 1
	return sum / float(n) if n > 0 else Vector2.ZERO


## The rooms beside a door ([room, ...], never the street): the floor next to any tile of the doorway, on any of its four sides (a doorway two wide may stand in a wall
## where one tile of it opens on a room and the other on the wall's end, so the generator's `out`/`in` tiles are not enough). Worked out once per door.
func _sides(d: Dictionary) -> Array:
	var tiles := _door_tiles(d)
	if tiles.is_empty():
		return []
	var key: Vector2i = tiles[0]
	if _sides_of.has(key):
		return _sides_of[key]
	var hs = _hs()
	var out: Array = []
	for t in tiles:
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var r := int(hs.room_at(float(t.x + o.x) + 0.5, float(t.y + o.y) + 0.5))
			if r >= 0 and not out.has(r):
				out.append(r)
	_sides_of[key] = out
	return out


## Opens both sides of a door; true when either was news.
func _peek(d: Dictionary, why: String) -> bool:
	var news := false
	for r in _sides(d):
		if r >= 0 and reveal(r, why):
			news = true
	return news


func _unseen_side(d: Dictionary) -> bool:
	for r in _sides(d):
		if r >= 0 and not revealed.has(r):
			return true
	return false


# ------------------------------------------------------------------------ the look --

func update(dt: float) -> void:
	if not enabled:
		return
	_t += dt
	if _t < EVERY:
		return
	_t = 0.0
	scan()


## One look at where the avatar is (update does it every EVERY seconds; tests and the claim call it to be up to the minute).
func scan() -> void:
	var hs = _hs()
	var p = _lead()
	if hs == null or p == null:
		return
	var me := Vector2(p.x, p.y)
	var h: int = hs.house_at(p.x, p.y)
	_track(h)
	var near: Array = []
	if h >= 0:
		near.append(h)
	for o in NEAR:
		var n: int = hs.house_at(p.x + o.x, p.y + o.y)
		if n >= 0 and not near.has(n):
			near.append(n)
	var r: int = hs.room_at(p.x, p.y)
	if r >= 0:
		reveal(r, "inside")
	for n in near:
		for d in hs.doors_of(n):
			if _door_dist(d, me) <= DOOR_REACH:
				_peek(d, "door")
	# judged: the houses at hand, and the half explored ones within reach of the avatar
	var judge: Array = near.duplicate()
	for n in _open.keys():
		if not judge.has(n) and _house_mid(int(n)).distance_to(me) <= JUDGE_R:
			judge.append(n)
	for n in judge:
		_check(int(n))


func _house_mid(h: int) -> Vector2:
	var rect: Rect2i = _hs().house(h).get("rect", Rect2i())
	return Vector2(rect.position) + Vector2(rect.size) * 0.5


func _track(h: int) -> void:
	if h == cur:
		return
	if cur >= 0:
		sim.events.append({"type": "left", "house": cur, "first": false})
	cur = h
	if h >= 0:
		var first := not seen.has(h)
		seen[h] = true
		sim.events.append({"type": "entered", "house": h, "first": first})


## Marks the rooms of `h` that are revealed and empty as clear, and the house when all of them are.
func _check(h: int) -> void:
	var hs = _hs()
	if hs == null or done.has(h):
		return
	var rooms: Array = hs.rooms_of(h)
	var all := not rooms.is_empty()
	for r in rooms:
		if not revealed.has(r):
			all = false
			continue
		if cleared.has(r):
			continue
		if _dead_in(r) == 0:
			cleared[r] = true
			sim.events.append({"type": "room_clear", "room": r, "house": h, "name": String(hs.room(r).get("name", ""))})
		else:
			all = false
	# (a dead one in the passage between the rooms is in no room, but it is in the house)
	if all and int(hs.dead_in_house(h)) > 0:
		all = false
	if all:
		done[h] = true
		_open.erase(h)
		sim.events.append({"type": "house_clear", "house": h})
		var sc = sim.scenario
		if sc != null and sc.has_method("on_house_clear"):
			sc.on_house_clear(h)


# ----------------------------------------------------------------------- E at a door --

func _door_id(h: int, i: int) -> String:
	return "d%d_%d" % [h, i]


## "Look in" at each door within LOOK_REACH with a side not yet seen (one that is within DOOR_REACH is opened by the look itself).
func candidates(p) -> Array:
	var out: Array = []
	var hs = _hs()
	if hs == null or not enabled:
		return out
	var me := Vector2(p.x, p.y)
	var houses: Array = []
	var h: int = hs.house_at(p.x, p.y)
	if h >= 0:
		houses.append(h)
	for o in NEAR_LOOK:
		var n: int = hs.house_at(p.x + o.x, p.y + o.y)
		if n >= 0 and not houses.has(n):
			houses.append(n)
	for n in houses:
		var i := 0
		for d in hs.doors_of(n):
			var dist := _door_dist(d, me)
			if dist <= LOOK_REACH and _unseen_side(d):
				out.append({"kind": "door", "id": _door_id(int(n), i), "label": "Look in", "pos": _door_mid(d), "dist": dist, "ok": true, "why": ""})
			i += 1
	return out


func use(c: Dictionary) -> Dictionary:
	if String(c.get("kind", "")) != "door":
		return {}
	var hs = _hs()
	var parts := String(c.get("id", "")).trim_prefix("d").split("_")
	if hs == null or parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return {"ok": false, "line": "", "why": "There is no door there"}
	var doors: Array = hs.doors_of(int(parts[0]))
	var i := int(parts[1])
	if i < 0 or i >= doors.size():
		return {"ok": false, "line": "", "why": "There is no door there"}
	var news := _peek(doors[i], "peek")
	scan()
	return {"ok": true, "line": "You look in." if news else "", "why": ""}


# -------------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {"revealed": _sorted(revealed), "cleared": _sorted(cleared), "done": _sorted(done), "seen": _sorted(seen)}


static func _sorted(d: Dictionary) -> Array:
	var out: Array = d.keys()
	out.sort()
	return out


static func _ints(v) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for e in v:
		if (typeof(e) == TYPE_INT or typeof(e) == TYPE_FLOAT) and is_finite(float(e)) and float(e) >= 0.0:
			out.append(int(e))
	return out


func load_state(d: Dictionary) -> void:
	start()
	for r in _ints(d.get("revealed")):
		revealed[r] = true
	for r in _ints(d.get("cleared")):
		cleared[r] = true
	for h in _ints(d.get("done")):
		done[h] = true
	for h in _ints(d.get("seen")):
		seen[h] = true
	var hs = _hs()
	if hs != null:
		for r in revealed:
			var h := int(hs.room(int(r)).get("house", -1))
			if h >= 0 and not done.has(h):
				_open[h] = true
