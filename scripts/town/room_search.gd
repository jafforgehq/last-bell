## SEARCH THE WHOLE ROOM (One House, LOOT): one hold of E in a cleared room searches every container of it that is not searched yet. A town module (`sim.room_search`, made from
## TownSim's PARTS) that sits on top of scripts/town/search.gd and uses.gd and changes none of their rules: each container is searched by the very session `sim.search.use` begins (4 s, the
## loot straight into the stores, the `searched` event and the looted flag), and this module only walks the avatar to the next one and begins it.
##
## THE RULES AS BUILT.
##   OFFER   `offer()`: the avatar stands in a room (not a doorway) of a house, the room is revealed, and it has TWO OR MORE containers not searched. {"show", "ok", "n", "secs", "why", ...}.
##           It is `ok` only when the room is CLEAR (`houses.dead_in_room(room) == 0`); with dead in it the offer is refused: "There are dead in this room".
##   BEGIN   `begin()`: refused (and nothing changes) with dead in the room ("There are dead in this room"), with an awake dead one that is after somebody within WAKE_R tiles ("The dead are
##           close"), with the keys, the trigger or another session in the hands, or when the avatar cannot act. A container of the room that is the session in hand (a tap of E has begun
##           it) is taken over as the first.
##   THE WALK  the containers in `plan()` order (nearest first, from the avatar). Between them the avatar walks herself along the walking grid (`sim.levels.find_path`): the rules ask
##           `pre_step()` before the step, which puts the way to walk where the hands' keys are for that step, and `post_step()` gives the keys back; at ARRIVE tiles from the container's
##           spot she stops and `sim.search.use` begins the container's own search. A way that does not get her nearer for a second is asked again, and after three the container is skipped.
##   THE END   it stops, undone from that container on, when: the avatar touches a walking key, the trigger or the swing (`pre_step`), is hurt (a drop of health of more than 0.4 in a step), goes
##           down, a dead one that was not awake when it began is within WAKE_R (12) tiles, a dead one is in the room, another thing takes the hands, or E (or anything) stops the search in hand.
##           It ends done when the last container is looted. Either way ONE event is told: {"type": "room_searched", "house", "room", "n" (containers done), "of" (in the plan), "loot": the
##           sum of what the containers gave, {stock: n}, "secs" (of the sim's time), "why": "done" | "moved" | "fired" | "hurt" | "down" | "woke" | "dead" | "stopped" | "stuck"}.
##
## FOR OTHER ACTORS. `RoomSearch.plan(sim, house_id, room_idx, from_pos)` is the order a person searches a room in (nearest container first, then nearest to that one...; `room_idx` -1 is the whole
## house: a room at a time, the nearest room first) as an Array of container ids, and `RoomSearch.eta(sim, ids, from_pos)` is the seconds the walk and the searches take. Both are pure (they read
## `sim.houses` and `sim.search.looted` and write nothing), and need no instance.
## Saved: nothing (a session is never resumed: the bench's rule).
extends RefCounted

const Avatar := preload("res://scripts/sim/avatar.gd")

## Seconds a container takes when the container does not say (scripts/town/search.gd).
const SEARCH_S := 4.0
## The avatar stops this many tiles from a container's spot (search.gd's REACH is 0.9, and a session breaks at 1.2).
const ARRIVE := 0.45
## A way is not a straight line: the walking time of the eta counts this much more than the distance.
const DETOUR := 1.55
## How near a dead one that woke stops the session, in tiles.
const WAKE_R := 12.0
## The seconds between two looks for the dead (the room, the wake radius).
const WATCH_EVERY := 0.25
## A drop of health in one step bigger than this is a blow (uses.gd HURT_DROP).
const HURT_DROP := 0.4
## The least of containers for an offer.
const MIN_CONTAINERS := 2
## The hold of the key, seconds: the view's number, kept here so that the words and the key agree.
const HOLD_S := 0.6
## A way that does not get nearer by this much in STUCK_S seconds is asked again; after REPATHS of them the container is skipped.
const STUCK_GAIN := 0.08
const STUCK_S := 1.0
const REPATHS := 3
const REFUSED_DEAD := "There are dead in this room"
const REFUSED_CLOSE := "The dead are close"

var sim
var enabled := true
## The session: {house, room, ids, idx, state ("walk" | "search"), loot, found, t, hp, known, watch, path, best, stuck, repaths, tries}, {} for none.
var _s := {}
## The hands' own keys for the step, set aside while the way is put in their place.
var _raw := Vector2.ZERO
var _raw_set := false
## What the last session ended as: {"why", "n", "of", "loot", "secs"} ({} before the first).
var last := {}
var _offer := {}
var _offer_key := ""
var _offer_t := -10.0


func setup(s) -> void:
	sim = s


func start() -> void:
	_s = {}
	_raw = Vector2.ZERO
	_raw_set = false
	last = {}
	_offer = {}
	_offer_key = ""
	_offer_t = -10.0


# --------------------------------------------------------------- the pure part --

## The containers of a house's room that are not searched, as the dictionaries (`room_idx` -1: every room of the house).
static func unsearched(sim, house_id: int, room_idx: int) -> Array:
	var out: Array = []
	var hs = sim.get("houses")
	if hs == null or house_id < 0:
		return out
	var search = sim.get("search")
	for c in hs.containers_of(house_id):
		if room_idx >= 0 and int(c.get("room", -1)) != room_idx:
			continue
		if search != null and search.is_looted(String(c.id)):
			continue
		out.append(c)
	return out


## The order to search a room in: the container nearest `from_pos` first, then the one nearest to that, and so on, as container ids (the spots to stand at are what is measured). With
## `room_idx` -1 it is the whole house, a room at a time: the room that has the container nearest `from_pos` first, and in it the same chain, then the room nearest to where that left off.
static func plan(sim, house_id: int, room_idx: int, from_pos: Vector2) -> Array:
	var left: Array = unsearched(sim, house_id, room_idx)
	var out: Array = []
	var at := from_pos
	var room := -2
	while not left.is_empty():
		var best := -1
		var best_d := INF
		for i in left.size():
			var c: Dictionary = left[i]
			# (a room is finished before the next is begun: only the room in hand is asked, and the first of a new room is the nearest of all)
			if room >= -1 and int(c.get("room", -1)) != room and _any_in(left, room):
				continue
			var d := at.distance_to(Vector2(c.pos))
			if d < best_d - 0.0001 or (absf(d - best_d) <= 0.0001 and best >= 0 and String(c.id) < String(left[best].id)):
				best_d = d
				best = i
		var pick: Dictionary = left[best]
		out.append(String(pick.id))
		room = int(pick.get("room", -1))
		at = Vector2(pick.pos)
		left.remove_at(best)
	return out


static func _any_in(list: Array, room: int) -> bool:
	for c in list:
		if int(c.get("room", -1)) == room:
			return true
	return false


## The seconds the containers `ids` take in that order from `from_pos` (`Vector2.INF`: from the first of them): the walk between the spots (a way is DETOUR times the line, at the avatar's
## pace, less the ARRIVE she stops short by) and each container's own search.
static func eta(sim, ids: Array, from_pos: Vector2 = Vector2.INF) -> float:
	var hs = sim.get("houses")
	var t := 0.0
	var at := from_pos
	if hs == null:
		return t
	for id in ids:
		var c: Dictionary = hs.container(String(id))
		if c.is_empty():
			continue
		var pos := Vector2(c.pos)
		if not at.is_finite():
			at = pos
		t += maxf(at.distance_to(pos) - ARRIVE, 0.0) * DETOUR / Avatar.WALK_SPEED
		t += float(c.get("search_s", SEARCH_S))
		at = pos
	return t


# ------------------------------------------------------------------ the offer --

func _lead():
	if sim == null or String(sim.player_id) == "":
		return null
	return sim.avatar.player()


func _can_act(p) -> bool:
	return p != null and not (p.dead or p.turned or p.downed or p.away != null)


func active() -> bool:
	return not _s.is_empty()


## What the prompt says (cached for a quarter of a second of the sim's time, and until the avatar's step, the looted ones or the dead of the room change):
## {} where there is nothing to offer (not in a room, fewer than two containers, or a session is running), else {"show": true, "ok": bool, "why": String, "n", "secs", "room", "house", "ids"}.
func offer() -> Dictionary:
	var p = _lead()
	if p == null or not enabled or not _can_act(p) or not _s.is_empty():
		return {}
	var hs = sim.get("houses")
	var search = sim.get("search")
	if hs == null or search == null:
		return {}
	var h: int = hs.house_at(p.x, p.y)
	var r: int = hs.room_at(p.x, p.y)
	if h < 0 or r < 0:
		return {}
	var key := "%d:%d:%d:%d:%d" % [h, r, search.looted.size(), floori(p.x * 2.0), floori(p.y * 2.0)]
	if key == _offer_key and float(sim.t) - _offer_t < WATCH_EVERY:
		return _offer
	_offer_key = key
	_offer_t = float(sim.t)
	_offer = _make_offer(p, h, r)
	return _offer


func _make_offer(p, h: int, r: int) -> Dictionary:
	var hs = sim.get("houses")
	var clearing = sim.get("clearing")
	if clearing != null and not clearing.is_revealed(r):
		return {}
	var here := Vector2(p.x, p.y)
	var ids := plan(sim, h, r, here)
	if ids.size() < MIN_CONTAINERS:
		return {}
	var dead: int = hs.dead_in_room(r)
	var why := REFUSED_DEAD if dead > 0 else ""
	return {"show": true, "ok": dead == 0, "why": why, "n": ids.size(), "secs": eta(sim, ids, here), "room": r, "house": h, "ids": ids}


# ---------------------------------------------------------------------- begin --

## Holds E in the room: the session begins, or {"ok": false, "why"} says why not. {"ok": true, "n", "secs", "line"} on a go.
func begin() -> Dictionary:
	var p = _lead()
	if p == null:
		return {"ok": false, "why": "You are not here"}
	if not _can_act(p):
		return {"ok": false, "why": "You cannot do that now"}
	if not _s.is_empty():
		return {"ok": false, "why": "Already searching the room"}
	var hs = sim.get("houses")
	var search = sim.get("search")
	var u = sim.get("uses")
	if hs == null or search == null or u == null:
		return {"ok": false, "why": "Nothing to search here"}
	var h: int = hs.house_at(p.x, p.y)
	var r: int = hs.room_at(p.x, p.y)
	if h < 0 or r < 0:
		return {"ok": false, "why": "Go into a room first"}
	var clearing = sim.get("clearing")
	if clearing != null and not clearing.is_revealed(r):
		return {"ok": false, "why": "You have not looked in here yet"}
	var here := Vector2(p.x, p.y)
	var ids := plan(sim, h, r, here)
	if ids.size() < MIN_CONTAINERS:
		return {"ok": false, "why": "Nothing more to search here"}
	if hs.dead_in_room(r) > 0:
		return {"ok": false, "why": REFUSED_DEAD}
	if _danger_at(here, {}, true) != "":
		return {"ok": false, "why": REFUSED_CLOSE}
	# a container of this room that a tap of E has begun is where the room search starts (its seconds so far count)
	var adopted := ""
	if u.busy():
		for id in ids:
			if u.in_session("container", String(id)):
				adopted = String(id)
		if adopted == "":
			# a tap of E that began the strip of a piece of furniture (salvage.gd) is let go: the hold is the word that counts (nothing is lost, a strip undone gives nothing and takes nothing)
			var held = u.get("_s")
			if typeof(held) == TYPE_DICTIONARY and String(held.get("kind", "")) == "strip":
				u.cancel("room search")
			else:
				return {"ok": false, "why": "Finish what you are doing first"}
	elif p.input_move.length() > uses_hands_on() or p.input_fire or p.input_melee:
		return {"ok": false, "why": "Stand still first"}
	if adopted != "":
		ids.erase(adopted)
		ids.push_front(adopted)
	var known := {}
	for z in sim.zombies:
		known[z.get_instance_id()] = true
	var secs := eta(sim, ids, here)
	_s = {"house": h, "room": r, "ids": ids, "idx": 0, "state": "search" if adopted != "" else "walk", "loot": {}, "found": 0, "t": 0.0, "hp": float(p.hp), "known": known,
			"watch": 0.0, "path": [], "best": INF, "stuck": 0.0, "repaths": 0, "tries": 0, "t0": float(sim.t), "cap": 3.0 * secs + 60.0}
	return {"ok": true, "n": ids.size(), "secs": secs, "why": "", "line": "Searching the room: %d containers, about %d s" % [ids.size(), roundi(secs)]}


func uses_hands_on() -> float:
	var u = sim.get("uses")
	return float(u.HANDS_ON) if u != null else 0.25


## Where the session is, for the ring: {"active", "n" (the one at hand, 1 to of), "of", "t" (0 to 1 of the work), "left" (seconds, the eta of what is left), "label", "state", "target" (the
## spot of the container at hand to stand at), "at" (its furniture), "id", "found", "loot" (so far)}. {"active": false} with none.
func progress() -> Dictionary:
	if _s.is_empty():
		return {"active": false}
	var ids: Array = _s.ids
	var of := ids.size()
	var idx := mini(int(_s.idx), of - 1)
	var frac := 0.0
	var u = sim.get("uses")
	if String(_s.state) == "search" and u != null and u.in_session("container", String(ids[idx])):
		var pr: Dictionary = u.progress()
		frac = clampf(float(pr.t) / maxf(float(pr.of), 0.001), 0.0, 1.0)
	var c: Dictionary = sim.houses.container(String(ids[idx]))
	var rest: Array = ids.slice(idx)
	var p = _lead()
	var left := eta(sim, rest, Vector2(p.x, p.y) if p != null else Vector2.INF)
	if String(_s.state) == "search":
		left = maxf(left - frac * float(c.get("search_s", SEARCH_S)), 0.0)
	return {"active": true, "n": idx + 1, "of": of, "t": clampf((float(idx) + frac) / float(of), 0.0, 1.0), "left": left, "label": "Searching: %d of %d" % [idx + 1, of],
			"state": String(_s.state), "target": Vector2(c.get("pos", Vector2.ZERO)), "at": Vector2(c.get("at", c.get("pos", Vector2.ZERO))), "id": String(ids[idx]), "found": int(_s.found),
			"loot": (_s.loot as Dictionary).duplicate()}


## Stops the session (it tells `room_searched`); the search in hand, if it is one of its own, is let go too.
func cancel(why: String = "stopped") -> void:
	_end(why)


# ------------------------------------------------------------------- the step --

## Before the rules' step: the keys of the hands break the session; while it walks, the way to the next container is put where the keys are for this step (the avatar's own step then
## walks it, with its facing and its feet).
func pre_step() -> void:
	_raw_set = false
	if _s.is_empty():
		return
	var p = _lead()
	if not _can_act(p):
		return
	var raw: Vector2 = p.input_move
	if raw.length() > uses_hands_on():
		_end("moved")
		return
	if p.input_fire or p.input_melee:
		_end("fired")
		return
	if String(_s.state) != "walk":
		return
	var dir := _heading(p)
	if dir == Vector2.ZERO:
		return
	_raw = raw
	_raw_set = true
	p.input_move = dir


## After the rules' step: the hands have their keys back.
func post_step() -> void:
	if not _raw_set:
		return
	_raw_set = false
	var p = _lead()
	if p != null:
		p.input_move = _raw


func update(dt: float) -> void:
	if _s.is_empty():
		return
	var p = _lead()
	var why := _stop_reason(p, dt)
	if why != "":
		_end(why)
		return
	var search = sim.get("search")
	var u = sim.get("uses")
	var ids: Array = _s.ids
	_s.t = float(_s.t) + dt
	# whatever is looted since is done (this one, or one that somebody else searched)
	while int(_s.idx) < ids.size() and search.is_looted(String(ids[int(_s.idx)])):
		# (only a search of the session's own gave it its loot: a container that somebody else searched meanwhile is not counted)
		if String(_s.state) == "search":
			_tally(String(ids[int(_s.idx)]))
		_next()
	if int(_s.idx) >= ids.size():
		_end("done")
		return
	var id := String(ids[int(_s.idx)])
	if String(_s.state) == "search":
		if not u.in_session("container", id):
			# the search in hand is gone and its container is not looted: it was stopped (E at it), or something else has the hands
			_end("stopped")
		return
	# walking
	if u.busy():
		_end("stopped")
		return
	var me := Vector2(p.x, p.y)
	var stand := _stand(id)
	if me.distance_to(stand) <= ARRIVE:
		var r: Dictionary = search.use({"kind": "container", "id": id})
		if bool(r.get("ok", false)):
			_s.state = "search"
			_s.tries = 0
		else:
			_s.tries = int(_s.tries) + 1
			if int(_s.tries) >= 5:
				_skip()
		return
	# not nearer for a second: another way, and the third time the container is let go
	var d := me.distance_to(stand)
	if d < float(_s.best) - STUCK_GAIN:
		_s.best = d
		_s.stuck = 0.0
	else:
		_s.stuck = float(_s.stuck) + dt
		if float(_s.stuck) >= STUCK_S:
			_s.stuck = 0.0
			_s.best = d
			_s.path = []
			_s.repaths = int(_s.repaths) + 1
			if int(_s.repaths) >= REPATHS:
				_skip()


## The dead, the blow, the fall: why the session must stop now ("" for none).
func _stop_reason(p, dt: float) -> String:
	if not _can_act(p):
		return "down"
	if float(p.hp) < float(_s.hp) - HURT_DROP:
		return "hurt"
	_s.hp = float(p.hp)
	_s.watch = float(_s.watch) - dt
	if float(_s.watch) <= 0.0:
		_s.watch = WATCH_EVERY
		if sim.houses.dead_in_room(int(_s.room)) > 0:
			return "dead"
		if _danger_at(Vector2(p.x, p.y), _s.known, false) != "":
			return "woke"
	# (no rule here lets it run forever: a session that has taken three times its time and a minute is ended)
	if float(_s.t) > float(_s.cap):
		return "stuck"
	return ""


## "woke" for a dead one within WAKE_R that is not one of `known` (or one that is after somebody), "" when none. `at_start`: only the ones that are after somebody count (`known` is empty).
func _danger_at(me: Vector2, known: Dictionary, at_start: bool) -> String:
	for z in sim.zombies:
		if z.remove or z.state == "dying" or z.state == "dead" or float(z.hp) <= 0.0:
			continue
		if Vector2(z.x, z.y).distance_to(me) > WAKE_R:
			continue
		var hostile: bool = z.state != "still" and z.state != "wander"
		if hostile or (not at_start and not known.has(z.get_instance_id())):
			return "woke"
	return ""


func _stand(id: String) -> Vector2:
	var c: Dictionary = sim.houses.container(id)
	return Vector2(c.get("pos", Vector2.ZERO))


## The way's next step as a direction (zero when she has come to the container's spot).
func _heading(p) -> Vector2:
	var ids: Array = _s.ids
	if int(_s.idx) >= ids.size():
		return Vector2.ZERO
	var me := Vector2(p.x, p.y)
	var stand := _stand(String(ids[int(_s.idx)]))
	if me.distance_to(stand) <= ARRIVE:
		return Vector2.ZERO
	var path: Array = _s.path
	if path.is_empty():
		var got: Array = sim.levels.find_path(p, stand.x, stand.y)
		path = got if not got.is_empty() else [stand]
		_s.path = path
	while path.size() > 1 and me.distance_to(Vector2(path[0])) <= 0.2:
		path.pop_front()
	var to: Vector2 = Vector2(path[0]) - me
	if to.length() < 0.02:
		return Vector2.ZERO
	return to.normalized()


## On to the next container of the plan.
func _next() -> void:
	_s.idx = int(_s.idx) + 1
	_s.state = "walk"
	_s.path = []
	_s.best = INF
	_s.stuck = 0.0
	_s.repaths = 0
	_s.tries = 0


## A container that cannot be got to is let go (the session goes on with the others).
func _skip() -> void:
	_next()


## What a container gave, added to the session's sum (search.gd's own rule: what the stores have a place for, whole numbers).
func _tally(id: String) -> void:
	var cont: Dictionary = sim.houses.container(id)
	var loot_in = cont.get("loot", {})
	_s.found = int(_s.found) + 1
	if typeof(loot_in) != TYPE_DICTIONARY:
		return
	var sum: Dictionary = _s.loot
	for k in loot_in:
		var n := float(loot_in[k])
		if n > 0.0 and sim.stock.has(k):
			sum[String(k)] = int(sum.get(String(k), 0)) + int(n)


func _end(why: String) -> void:
	if _s.is_empty():
		return
	var s := _s
	_s = {}
	var u = sim.get("uses")
	var ids: Array = s.ids
	# a container still in hand is let go unless the session ran its course; E at it has done that already
	if why != "done" and u != null and u.busy():
		for id in ids:
			if u.in_session("container", String(id)):
				u.cancel(why)
	var secs: float = float(sim.t) - float(s.t0)
	last = {"why": why, "n": int(s.found), "of": ids.size(), "loot": (s.loot as Dictionary).duplicate(), "secs": secs}
	sim.events.append({"type": "room_searched", "house": int(s.house), "room": int(s.room), "n": int(s.found), "of": ids.size(), "loot": (s.loot as Dictionary).duplicate(), "secs": secs, "why": why})


# -------------------------------------------------------------------------- save --

## Nothing is saved: a session is never resumed.
func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	start()
