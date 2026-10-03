## The town: the board the settlement game plans on (round 8). Places on a map (assets/data/town.json),
## hidden until they are known, with roads between them, a distance in hours from the school, nests
## the nights lean towards, survivors who can be rescued, and outposts that a cleared place can
## become. The expeditions themselves are `scavenge.gd`'s (generalised for the settlement game);
## this module keeps the board's state and answers questions about it.
##
## Only the settlement game (a small start: `sim.crew_start == 3`) has a board (`on`); in the classic
## start every question has the old answer (nothing changes anywhere).
##
## THE BOARD. `board` {w, h}, `home` {x, y} (the school), `places` (see the data), `roads` [[a, b]...]
## between place ids and "home", `beats` (what happens on the way: see `beats()`). A place is
## "unknown" (not shown), "known", "cleared" (its danger is gone: a nest cleared, a place emptied of
## the dead) or "claimed" (an outpost). `hours_to(id)` is the road distance over SPEED.
##
## NESTS. A place with `nest.strength` sends the dead: `pressure(spawn_index)` is the strength of the
## nests whose bearing from the school is nearest that spawn point; `waves.gd` leans the night's main
## spawn point towards it, and `budget_mult()` shrinks the night by NEST_BUDGET for each point of
## strength that has been cleared.
##
## OUTPOSTS. A claimed place pays its `outpost.yield` at each dawn; each night it may be overrun
## (OUTPOST_RISK, more with the nests near it): a garrison (people sent to stay there) holds it, with a
## risk to them; without one it is lost. `garrison` is place id to person ids.
##
## Events: {"type": "revealed", "place": id}, {"type": "outpost", "place": id, "what": "claimed"|"lost"|"held"}.
extends RefCounted

const DATA_PATH := "res://assets/data/town.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

## Tiles of the board a party walks in an hour.
const SPEED := 9.0
## Hours spent searching a place, the radius a scouting trip reveals (board tiles), and what a trip's
## beats may add or take away.
const SEARCH_H := 1.5
const SCOUT_RADIUS := 20.0
## A nest this near an outpost raises the night's risk of losing it.
const NEST_NEAR := 26.0
## Each point of nest strength cleared takes this share off the night's size, and pulls the main
## spawn point towards a nest by this weight a point.
const NEST_BUDGET := 0.03
const NEST_PULL := 0.9
## An outpost's chance of being overrun in a night, a garrison's chance of a wound when it is, and how
## much nearer nests add.
const OUTPOST_RISK := 0.12
const NEST_RISK := 0.04
const GARRISON_WOUND := 0.5

var sim
var on := false
var board := {"w": 100.0, "h": 70.0}
var home := Vector2(50.0, 35.0)
var places: Array = []
var roads: Array = []
var _beats: Array = []
var _by_id := {}
var _hours := {}
## Place id -> {"known", "cleared", "claimed", "rescued"}; garrison: place id -> [person ids].
var state := {}
var garrison := {}
var _nest_heading := {}
var _dawn_day := 0
var _bell_day := 0


func setup(s) -> void:
	sim = s
	_load()


func _load() -> void:
	if not _cache.has(data_path):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		_cache[data_path] = raw if raw is Dictionary else {}
	var d: Dictionary = _cache[data_path]
	var b = d.get("board", {})
	board = {"w": float(b.get("w", 100.0)), "h": float(b.get("h", 70.0))} if b is Dictionary else board
	var h = d.get("home", [50.0, 35.0])
	home = Vector2(float(h[0]), float(h[1])) if h is Array and h.size() >= 2 else home
	places = []
	_by_id = {}
	for r in d.get("places", []):
		if not r is Dictionary or String(r.get("id", "")) == "":
			continue
		var p: Dictionary = r.duplicate(true)
		p["pos"] = Vector2(float(r.pos[0]), float(r.pos[1]))
		p["danger"] = int(r.get("danger", 1))
		p["loot"] = r.get("loot", {})
		p["extra"] = r.get("extra", {})
		places.append(p)
		_by_id[String(p.id)] = p
	roads = d.get("roads", [])
	_beats = d.get("beats", [])
	_compute_hours()


## Road distances from the school by Dijkstra over the roads (a straight line to a place with no road).
func _compute_hours() -> void:
	_hours.clear()
	var pos := {"home": home}
	for p in places:
		pos[String(p.id)] = p.pos
	var dist := {"home": 0.0}
	var open: Array = ["home"]
	var edges := {}
	for r in roads:
		if r is Array and r.size() >= 2 and pos.has(String(r[0])) and pos.has(String(r[1])):
			var a := String(r[0])
			var b := String(r[1])
			var len: float = Vector2(pos[a]).distance_to(Vector2(pos[b]))
			edges[a] = edges.get(a, []) + [[b, len]]
			edges[b] = edges.get(b, []) + [[a, len]]
	while not open.is_empty():
		open.sort_custom(func(x, y): return float(dist[x]) < float(dist[y]))
		var cur: String = open.pop_front()
		for e in edges.get(cur, []):
			var nd: float = float(dist[cur]) + float(e[1])
			if not dist.has(e[0]) or nd < float(dist[e[0]]) - 1.0e-9:
				dist[e[0]] = nd
				if not open.has(e[0]):
					open.append(e[0])
	for p in places:
		var id := String(p.id)
		var tiles: float = float(dist[id]) if dist.has(id) else home.distance_to(p.pos) * 1.4
		_hours[id] = tiles / SPEED


func start() -> void:
	on = false
	state.clear()
	garrison.clear()
	_nest_heading.clear()
	_dawn_day = 0
	_bell_day = 0


## Called once a run has been set up (after every module's start): the settlement game gets its board. `force`: a game
## that is not a small start has it too (Orientation Day of the avatar, which teaches the board G opens).
func begin(force: bool = false) -> void:
	if not sim.recruits.small and not force:
		return
	on = true
	for p in places:
		state[String(p.id)] = {"known": bool(p.get("known", false)), "cleared": false, "claimed": false, "rescued": false}
	_nest_heading.clear()
	for p in places:
		if int(p.get("nest", {}).get("strength", 0)) > 0:
			_nest_heading[String(p.id)] = heading_of(p)
	sim.scavenge.use_town()


## Every step: the dawn pays the outposts, the bell tests them.
func update(_dt: float) -> void:
	if not on:
		return
	if sim.phase == "day" and sim.day != _dawn_day:
		_dawn_day = sim.day
		at_dawn()
	if sim.bell_rung and sim.day != _bell_day:
		_bell_day = sim.day
		at_the_bell()


# ------------------------------------------------------------------- the board --

func place(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Every place as the board shows it: the data plus "state" ("unknown", "known", "cleared" or "claimed"),
## "hours" (one way), "garrison" (person ids). Unknown places are included (the board draws them faint).
func all_places() -> Array:
	var out: Array = []
	for p in places:
		var e: Dictionary = p.duplicate(true)
		var id := String(p.id)
		e["state"] = state_of(id)
		e["hours"] = hours_to(id)
		e["garrison"] = garrison.get(id, []).duplicate()
		e["rescued"] = bool(state.get(id, {}).get("rescued", false))
		out.append(e)
	return out


func known_places() -> Array:
	var out: Array = []
	for e in all_places():
		if e.state != "unknown":
			out.append(e)
	return out


func state_of(id: String) -> String:
	var s: Dictionary = state.get(id, {})
	if s.is_empty() or not bool(s.known):
		return "unknown"
	if bool(s.claimed):
		return "claimed"
	if bool(s.cleared):
		return "cleared"
	return "known"


func hours_to(id: String) -> float:
	return float(_hours.get(id, 0.0)) * sim.seasons.mult("travel")


## The hours of a trip to a place: there, the search, back.
func trip_hours(id: String) -> float:
	return 2.0 * hours_to(id) + SEARCH_H


func is_known(id: String) -> bool:
	return bool(state.get(id, {}).get("known", false))


func reveal(id: String) -> void:
	if state.has(id) and not bool(state[id].known):
		state[id].known = true
		sim.events.append({"type": "revealed", "place": id})


## Shows the places within `radius` board tiles of a place (and the place itself).
func reveal_around(id: String, radius: float) -> Array:
	var shown: Array = []
	var at: Vector2 = place(id).get("pos", home)
	for p in places:
		var pid := String(p.id)
		if state.has(pid) and not bool(state[pid].known) and Vector2(p.pos).distance_to(at) <= radius:
			reveal(pid)
			shown.append(pid)
	reveal(id)
	return shown


func mark_cleared(id: String) -> void:
	if state.has(id):
		state[id].cleared = true


# ----------------------------------------------------------------------- nests --

## The spawn point (an index into sim.spawns) a place lies towards, from the school.
func heading_of(p: Dictionary) -> int:
	var dir: Vector2 = (Vector2(p.pos) - home).normalized()
	var best := 0
	var best_dot := -2.0
	var centre := Vector2(42.0, 32.0)
	for i in sim.spawns.size():
		var v: Vector2 = (Vector2(sim.spawns[i]) - centre).normalized()
		var d := dir.dot(v)
		if d > best_dot:
			best_dot = d
			best = i
	return best


## The nest strength (uncleared) that sends the dead from this spawn point.
func pressure(spawn_index: int) -> float:
	if not on:
		return 0.0
	var total := 0.0
	for id in _nest_heading:
		if int(_nest_heading[id]) == spawn_index and not bool(state[id].cleared):
			total += float(place(id).nest.strength)
	return total


## How much the nests cleared have shrunk the night (1 at the start of a game).
func budget_mult() -> float:
	if not on:
		return 1.0
	var cleared := 0.0
	for id in _nest_heading:
		if bool(state[id].cleared):
			cleared += float(place(id).nest.strength)
	return 1.0 - NEST_BUDGET * cleared


func nest_strength(id: String) -> int:
	return int(place(id).get("nest", {}).get("strength", 0))


# --------------------------------------------------------------------- outposts --

func can_claim(id: String) -> bool:
	var p := place(id)
	return on and not p.is_empty() and state_of(id) == "cleared" and p.has("outpost") and float(sim.stock.scrap) >= float(p.outpost.get("cost", 0))


func claim(id: String) -> bool:
	if not can_claim(id):
		return false
	sim.stock.scrap = float(sim.stock.scrap) - float(place(id).outpost.get("cost", 0))
	state[id].claimed = true
	sim.events.append({"type": "outpost", "place": id, "what": "claimed"})
	return true


## A place where someone is hiding that the board has not been told of (the radio may say so), or "". The first by
## the data's order, so that the radio's word is the same whenever it is asked.
func tip_place() -> String:
	if not on:
		return ""
	for p in places:
		var id := String(p.id)
		if bool(p.get("survivor", false)) and state_of(id) == "unknown" and not bool(state.get(id, {}).get("rescued", false)):
			# (a place across the river is told of only once the colony has a vehicle to go there in)
			if bool(p.get("needs_vehicle", false)) and sim.vehicles.fleet.is_empty():
				continue
			return id
	return ""


## How many places have been cleared (a claimed outpost was cleared first).
func cleared_count() -> int:
	var n := 0
	for id in state:
		if bool(state[id].get("cleared", false)) or bool(state[id].get("claimed", false)):
			n += 1
	return n


func claimed() -> Array:
	var out: Array = []
	for p in places:
		if state_of(String(p.id)) == "claimed":
			out.append(String(p.id))
	return out


## People who stay at a claimed place (the party that went to garrison it).
func set_garrison(id: String, ids: Array) -> void:
	garrison[id] = ids.duplicate()


func garrison_of(id: String) -> Array:
	return garrison.get(id, [])


## Sends people (Person objects) to stay at a claimed outpost until recalled. They are off the map as
## on a trip (`p.away`: {"kind": "garrison", "place": id}). False if the place is not claimed or
## someone cannot go.
func garrison_send(id: String, people: Array) -> bool:
	if not on or state_of(id) != "claimed" or people.is_empty() or sim.phase != "day":
		return false
	# a place across the river is too far to walk to and hold: it takes a trip by vehicle (round 13), not this
	if bool(place(id).get("needs_vehicle", false)):
		return false
	for p in people:
		if not sim.scavenge.can_go(p):
			return false
	var ids: Array = garrison.get(id, []).duplicate()
	for p in people:
		p.drafted = false
		p.order = null
		p.repair = null
		p.goal_key = ""
		p.away = {"kind": "garrison", "place": id}
		p.activity = "Holding %s" % String(place(id).name)
		if not ids.has(p.id):
			ids.append(p.id)
	garrison[id] = ids
	return true


## Why the garrison cannot be recalled now ("" when it can): not in the dark, when the wall needs everyone and the
## outpost's night is in the garrison's hands.
func why_not_recall(id: String) -> String:
	if garrison.get(id, []).is_empty():
		return "Nobody is holding it."
	if sim.phase != "day":
		return "Not in the dark: they hold it until morning."
	return ""


## Brings the garrison of an outpost home, to the gate (by day only).
func recall(id: String) -> void:
	if why_not_recall(id) != "":
		return
	var gate: Vector2 = sim.scavenge.gate_center()
	var i := 0
	for pid in garrison.get(id, []):
		var p = _person(String(pid))
		if p != null and p.away is Dictionary and p.away.get("kind", "") == "garrison":
			p.away = null
			p.x = gate.x + float(i) * 0.7 - 0.7
			p.y = gate.y + 1.0
			p.moving = false
			p.path = []
			p.goal_key = ""
			i += 1
	garrison.erase(id)


## The dawn: each outpost pays its yield. (The night's risk is rolled at the bell: `at_the_bell`.)
func at_dawn() -> void:
	if not on:
		return
	for id in claimed():
		var y: Dictionary = place(id).outpost.get("yield", {})
		for k in y:
			sim.stock[k] = float(sim.stock.get(k, 0.0)) + float(y[k])


## The bell: each claimed outpost may be overrun in the night; a garrison holds it (and may be hurt),
## no garrison loses it.
func at_the_bell() -> void:
	if not on:
		return
	for id in claimed():
		var near := 0.0
		for nid in _nest_heading:
			if not bool(state[nid].cleared) and Vector2(place(nid).pos).distance_to(place(id).pos) < NEST_NEAR:
				near += float(place(nid).nest.strength)
		var risk := OUTPOST_RISK + NEST_RISK * near
		if sim.rng.randf() >= risk:
			continue
		var crew: Array = garrison_of(id)
		if crew.is_empty():
			state[id].claimed = false
			sim.events.append({"type": "outpost", "place": id, "what": "lost"})
			sim.alert("outpost-%s" % id, "danger", "%s was overrun" % String(place(id).name), "Nobody was there to hold it", null, 20.0)
		else:
			sim.events.append({"type": "outpost", "place": id, "what": "held"})
			sim.alert("outpost-%s" % id, "warn", "%s held" % String(place(id).name), "The garrison fought the night off", null, 20.0)
			if sim.rng.randf() < GARRISON_WOUND:
				var who = _person(String(crew[sim.rng.randi() % crew.size()]))
				if who != null and not who.dead:
					sim.medical.add_wound(who, "scratch")


func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


# ------------------------------------------------------------------------ beats --

## The events a trip may meet (data): [{"id", "text", "weight", "min_hours", "effects": {...}}].
func beats() -> Array:
	return _beats


# ------------------------------------------------------------------------ save --

func save() -> Dictionary:
	return {"on": on, "state": state.duplicate(true), "garrison": garrison.duplicate(true), "dawn_day": _dawn_day, "bell_day": _bell_day}


func load_state(d: Dictionary) -> void:
	start()
	on = bool(d.get("on", false))
	if not on:
		return
	var saved = d.get("state", {})
	for p in places:
		var id := String(p.id)
		var s = saved.get(id, {}) if saved is Dictionary else {}
		state[id] = {"known": bool(s.get("known", bool(p.get("known", false)))), "cleared": bool(s.get("cleared", false)),
			"claimed": bool(s.get("claimed", false)), "rescued": bool(s.get("rescued", false))}
		if bool(s.get("vehicle_taken", false)):
			state[id]["vehicle_taken"] = true
		if int(p.get("nest", {}).get("strength", 0)) > 0:
			_nest_heading[id] = heading_of(p)
	_dawn_day = int(d.get("dawn_day", 0))
	_bell_day = int(d.get("bell_day", 0))
	sim.scavenge.use_town()
	var g = d.get("garrison", {})
	if g is Dictionary:
		for id in g:
			if g[id] is Array:
				garrison[String(id)] = g[id].duplicate()
