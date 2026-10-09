## The crew searches the houses (One House, CREW): `sim.crew_search`, a part of the town's sim only (scripts/town/town_sim.gd `PARTS`; the school and the no-player game never make it).
## Two ways, one rule set.
##
## THE ORDER, "Search a house" (the command wheel's Search slice, `radio.request(p, "search", {"at": a point of the house})`): the person walks to the house's front door, goes in, and searches
## every container that is not searched yet, nearest first, 4 s each (the container's own `search_s`), standing at the container's spot. The loot goes straight into `sim.stock` and the
## container is looted for good (`search.mark_looted`: the same as the avatar's session, so the pops over the container and the ticks work for them too). When the last one is done the
## order is over: they are back to their job or their rest spot, and the radio hears what they found. One house to an order.
## THE JOB, "Scavenger" (a station of two seats that the claim installs: jobs.gd `install_layout`; never filled by Auto-assign, Fill empty seats or the priorities): they take the nearest
## cleared house (to the base's middle, within FAR_TILES) that still has something to search, search it, and then the next, at any hour and in any weather. With
## nothing left they stand at their seat and the Jobs row says so ("Nothing left to search: clear another house"); then, if the town has a salvage module (`sim.salvage`, SALVAGE), they ask it for
## strip work: the furniture of the cleared houses (`salvage.candidates(house)`), then the wrecks of the street near the base (`salvage.street_candidates`), each piece with its own seconds, the scrap
## into the stores by `salvage.strip(id, person)`. Without that module this part does nothing of the kind.
##
## THE RULES (RULES2, the owner: "when I say someone to scavenge a house he must do that, it is not optional"): AN ORDER IS OBEYED. The radio asks `person_reason` (nothing, ever: no storm, no
##   rain, no dark, no curfew, no watch, no tiredness, no wound, no distrust, no fear, no distance, no dead about, no cap of two out at once) and `house_refusal`, which says no only to what cannot be
##   done: no house under the click, a house that is not cleared (there are dead in it: not a house to search), a house with nothing left to search (or whose last containers somebody else is on) and a
##   house with no way in. A person who cannot go at all (dead, down, away, in a breakdown, the one you play) is the radio's own hard reason. Each of those "no"s is said, with its reason, in the toast.
## A RUN ENDS only when the house is done, when the person is down or dead, when they cannot get there (stuck), or when the PLAYER takes it back (a new order, "Go back", the call to arms). Not by the
##   weather, the dark, a wound, a bite, or the dead near them: a person outside is a person (the dead near them wake, `field._wake_near`, a smaller circle than the avatar's, notice them and bite
##   them; they shoot what they see, as everyone does) and deaths are real. One exception, for the JOB's runs only and not for the order's: the base's own night posts (the call to arms, or an attack night:
##   `sim.posts_manned()`) take the scavengers to the wall, as they take everyone, and no job run starts then. An order keeps its person out through the posts too.
## THE CARS (PH3, SCAV3: "the scavenger should also check for cars automatically and loot them"). The parked cars and wrecks of the streets are containers (scripts/town/car_loot.gd, `sim.houses.cars`, the loot in
##   the `cars` block of assets/data/salvage.json; the avatar searches them with E). On a house run (the order or the job) the last container of the house is followed by a TRIP to the cars: the unsearched cars and
##   wrecks within `trip.radius` (14) tiles of the house, nearest first from where the person stands, each searched for its own `search_s` (the very number the avatar's session reads: `search.search_secs`) and then,
##   when salvage allows it (the street cell cap is not reached, no awake dead within salvage `danger_r`, the car is not the base's), stripped for scrap for the piece's seconds, up to `trip.most` (6) cars a trip.
##   A car that is already searched (the avatar, or an earlier trip) is not searched again (the same `looted` flag as a cupboard; a save keeps it), but is still stripped when it can be. The Scavenger job with no
##   house left to search takes a trip of its own from the car nearest the base (mode "cars", within FAR_TILES of the base, the radius round that first car); loot comes before strip work all through (houses, cars,
##   then the furniture and the street's other pieces). The report adds what the cars gave ("Femi searched 22 Elm St: 4 food; 2 cars: 6 ammo, 1 water"); the tally and the morning's line count it.
##   Nothing here is a refusal: no weather, hour, health or dead near stops a car trip (RULES2); the only thing skipped is a strip that salvage says cannot be done now.
## NOISE. They make none: nothing here calls the field's `noise`. (They shoot what they see, as every person does: that is the rules' own.)
## FOR OTHERS. `plan(house_id, room_idx, from_pos)` and `eta(plan, from_pos)` are LOOT's `RoomSearch.plan` and `eta` in name and shape: when scripts/town/room_search.gd exists they are its own order
## (a room finished before the next), else the nearest-first chain here.
##
## State: `runs` (person id to the run), saved with the day's tally. Each run: {"kind": "order"|"job", "mode": "search"|"strip"|"street"|"cars", "house" (-1 in the street), "stage": "door"|"search"|"strip"|"car",
## "cur" (the container's or piece's id, or ""), "t" (seconds into it), "found" (stock key to n), "n" (done), "total", "hp", "wounds", "stuck", and for a strip "spot", "at", "secs", "name", "skip";
## SCAV3, for the car stage: "anchor" (where the trip's radius is measured from), "cars" (cars visited), "cfound" (what they gave), "cdone" (the cars done or given up, ids), "cmode" "search"|"strip" with
## "spot", "at", "secs", "name" for the car in hand}.
## Events: {"type": "searched", ..., "who", "name"} for each container (search.gd `mark_looted`), {"type": "crew_search", "who", "name", "what", "text", "level", "house"} when a run ends
## ("done", "posts", "stuck") or an order does not begin ("stopped", with its reason): the town's HUD toasts the text.
extends RefCounted

const ROOM_SEARCH := "res://scripts/town/room_search.gd"
const SearchRules := preload("res://scripts/town/search.gd")
const CarLoot := preload("res://scripts/town/car_loot.gd")
## How far from the base's middle the JOB looks for a house (the job's own range, not a refusal: an order may name any cleared house).
const FAR_TILES := 35.0
## Hit points lost, or a new wound, that count as a bite in the run's record (nobody turns back for it).
const BITE_HP := 4.0
const STUCK_S := 4.0
const SEARCH_S := 4.0
const WALK := 3.0
const ARRIVE := 0.45
## The crew outside wake the dead near them: a share of the avatar's circle, a few at a time.
const WAKE_SHARE := 0.6
const WAKE_MOST := 2
const SLOW_S := 0.5
const CANDIDATES_S := 8.0
const MAX_HOUSE_ASK := 12
const BLOCKED_S := 60.0
const IDLE_S := 2.0
## A house (or a wreck) that gave no strip work when they got there is not tried again for this long (seconds of this part's own age).
const NOWORK_S := 300.0
const STOCKS := ["food", "water", "ammo", "scrap", "meds"]
## What the radio says when an order cannot be done at all (RULES2: the only reasons left; there is no reason of the weather, the dark, the person's state or the distance).
const R_NOT_CLEARED := "Not cleared yet: there are dead in it"
const R_SEARCHED := "Already searched"
const R_NO_HOUSE := "Click a house"
const R_NO_WAY := "No way in"
const NOTHING_LEFT := "Nothing left to search: clear another house"

var sim
var enabled := true
## Person id to the run.
var runs := {}
## Container (or piece) id to the id of the person who is on it.
var claims := {}
## The day's tally: {"day", "all" (stock key to n), "by" (person id to {stock key: n})} and yesterday's, kept for the briefing.
var tally := {"day": 0, "all": {}, "by": {}}
var yesterday := {"day": 0, "all": {}}
## What the job's people say they are doing when they have no run (person id to a line); not saved.
var job_note := {}
## Counters for the lab and the report: containers, houses, the loot, the runs by how they ended, the pieces stripped; SCAV3: the cars searched (`cars`), the cars stripped (`car_strips`) and what
## the cars gave (`car_loot`, searched and stripped together; it is part of `loot`).
var stats := {"containers": 0, "houses": 0, "loot": {}, "ended": {}, "bitten": 0, "stripped": 0, "cars": 0, "car_strips": 0, "car_loot": {}}
## The person the last `stage` sent (for a screenshot's camera).
var staged = null
## House id to the time (this part's own age) until which nobody is sent there: no way from where they stood.
var _blocked := {}
## House id (or piece id) to the time until which it is not tried for strip work: it had none to give.
var _nowork := {}
## Person id to the time (this part's own age) before which a scavenger with nothing to do does not look again.
var _idle_until := {}
var _acc := 0.0
var _cands: Array = []
var _cands_key := ""
var _cands_t := -1.0e9
var _age := 0.0
var _rs = null
var _rs_looked := false


func setup(s) -> void:
	sim = s


func start() -> void:
	runs = {}
	claims = {}
	tally = {"day": 0, "all": {}, "by": {}}
	yesterday = {"day": 0, "all": {}}
	job_note = {}
	stats = {"containers": 0, "houses": 0, "loot": {}, "ended": {}, "bitten": 0, "stripped": 0, "cars": 0, "car_strips": 0, "car_loot": {}}
	_blocked = {}
	_nowork = {}
	_idle_until = {}
	_acc = 0.0
	_cands = []
	_cands_key = ""
	_cands_t = -1.0e9
	_age = 0.0


# ------------------------------------------------------------------------- the parts --

func _houses():
	return sim.get("houses")


func _search():
	return sim.get("search")


func _clearing():
	return sim.get("clearing")


func _base():
	return sim.get("base")


func _field():
	return sim.get("field")


## SALVAGE's module when the town has it and it speaks the crew's part of its API, else null.
func _salvage():
	var sv = sim.get("salvage")
	if sv != null and sv.has_method("candidates") and sv.has_method("strip") and sv.has_method("available") and sv.has_method("piece"):
		return sv
	return null


## LOOT's `RoomSearch` (the order a person searches a room in) when its file exists, else null.
func _room_search():
	if not _rs_looked:
		_rs_looked = true
		if ResourceLoader.exists(ROOM_SEARCH):
			var script = load(ROOM_SEARCH)
			if script != null and script.has_method("plan") and script.has_method("eta"):
				_rs = script
	return _rs


func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


## Whether this person is in a state to be sent anywhere (not the player, not lost, down or away, not in a breakdown).
func _able(p) -> bool:
	return p != null and not (p.dead or p.turned or p.downed or p.player) and p.away == null and not sim.morale.breakdown(p)


# ----------------------------------------------------------------------- the houses --

## The front door's spot: the tile just inside it (Vector2.ZERO when the house has no door that opens on the street).
func door_spot(h: int) -> Vector2:
	var base = _base()
	var hs = _houses()
	if hs == null or h < 0:
		return Vector2.ZERO
	var at: Vector2 = base.spot_of(h) if base != null else Vector2.ZERO
	if at == Vector2.ZERO:
		var d = hs.house(h).get("door")
		if d != null:
			at = Vector2(Vector2i(d)) + Vector2(0.5, 0.5)
	return at


func address(h: int) -> String:
	if h < 0:
		return "the street"
	var hs = _houses()
	var a := String(hs.house(h).get("address", "house %d" % h)) if hs != null else "house %d" % h
	return a.replace(" Street", " St").replace(" Road", " Rd").replace(" Avenue", " Ave").replace(" Lane", " Ln")


## The middle of a house's footprint (a point inside it when the footprint's middle is not).
func house_point(h: int) -> Vector2:
	var hs = _houses()
	if hs == null or h < 0:
		return Vector2.ZERO
	var r := Rect2i(hs.house(h).get("rect", Rect2i()))
	var mid := Vector2(r.position) + Vector2(r.size) * 0.5
	if int(hs.house_at(mid.x, mid.y)) == h:
		return mid
	var d = hs.house(h).get("door")
	return Vector2(Vector2i(d)) + Vector2(0.5, 0.5) if d != null else mid


## The house a point is in, or the nearest one within 2 tiles of it (a click on a roof's edge, on the lot's grass), else -1.
func house_of_point(at: Vector2) -> int:
	var hs = _houses()
	if hs == null:
		return -1
	var h: int = hs.house_at(at.x, at.y)
	if h >= 0:
		return h
	var best := -1
	var best_d := 2.0
	for i in int(hs.count()):
		var r := Rect2(Rect2i(hs.house(i).get("rect", Rect2i())))
		var near := Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.y, r.position.y, r.end.y))
		var d := near.distance_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best


## What the wheel's "click where" makes of a click at `tile`: {"at": a point of the house} or {"error": "Click a house"}. The houses' own reasons are the radio's, asked after the click.
func spot_for(tile: Vector2, _who = null) -> Dictionary:
	var h := house_of_point(tile)
	if h < 0:
		return {"error": R_NO_HOUSE}
	return {"at": house_point(h)}


## The containers of a house that are not searched yet, as dictionaries, in the order a person standing at `from_pos` would take them: the nearest first, then the nearest to that one, and so on
## (LOOT's `RoomSearch.plan` when that file exists: a room finished before the next). `room_idx` (not -1) keeps only that room's. The ones somebody else is on are left out (`for_id`: the person
## asking; their own stay). The same name and shape as `RoomSearch.plan`, but the containers themselves and not their ids.
func plan(house_id: int, room_idx: int, from_pos: Vector2, for_id: String = "") -> Array:
	var hs = _houses()
	var search = _search()
	var left: Array = []
	if hs == null or search == null or house_id < 0:
		return left
	var rs = _room_search()
	if rs != null:
		for id in rs.plan(sim, house_id, room_idx, from_pos):
			var owner = claims.get(String(id))
			if owner != null and String(owner) != for_id:
				continue
			var c: Dictionary = hs.container(String(id))
			if not c.is_empty():
				left.append(c)
		return left
	for c in hs.containers_of(house_id):
		var id := String(c.get("id", ""))
		if search.is_looted(id):
			continue
		if room_idx >= 0 and int(c.get("room", -1)) != room_idx:
			continue
		var owner = claims.get(id)
		if owner != null and String(owner) != for_id:
			continue
		left.append(c)
	var out: Array = []
	var at := from_pos
	while not left.is_empty():
		var bi := 0
		var bd := INF
		for i in left.size():
			var d := at.distance_squared_to(Vector2(left[i].pos))
			if d < bd:
				bd = d
				bi = i
		var c: Dictionary = left.pop_at(bi)
		out.append(c)
		at = Vector2(c.pos)
	return out


## How long a plan takes, in seconds: the walk from `from_pos` through the containers (WALK tiles a second, in straight lines) and each one's `search_s`. `the_plan`: containers or their ids.
func eta(the_plan: Array, from_pos: Vector2) -> float:
	var rs = _room_search()
	var hs = _houses()
	if rs != null and not the_plan.is_empty():
		var ids: Array = []
		for c in the_plan:
			ids.append(String(c.get("id", "")) if typeof(c) == TYPE_DICTIONARY else String(c))
		return float(rs.eta(sim, ids, from_pos))
	var secs := 0.0
	var at := from_pos
	for e in the_plan:
		var c: Dictionary = e if typeof(e) == TYPE_DICTIONARY else (hs.container(String(e)) if hs != null else {})
		if c.is_empty():
			continue
		secs += at.distance_to(Vector2(c.pos)) / WALK + SearchRules.search_secs(sim, c)
		at = Vector2(c.pos)
	return secs


func unsearched_count(h: int) -> int:
	return plan(h, -1, Vector2.ZERO).size()


## How many of the dead that are awake are within `radius` tiles of a point (not the dying, not the ones going back to the city).
func dead_about(at: Vector2, radius: float) -> int:
	var n := 0
	var r2 := radius * radius
	for z in sim.zombies:
		if z.state == "dead" or z.state == "dying" or z.state == "retreat":
			continue
		var dx: float = z.x - at.x
		var dy: float = z.y - at.y
		if dx * dx + dy * dy <= r2:
			n += 1
	return n


# ----------------------------------------------------------------------- the reasons --

func _no(why: String, hard: bool, line: String = "") -> Dictionary:
	return {"ok": false, "why": why, "line": line if line != "" else why + ".", "hard": hard}


## Why this person would not go and search anything now: never a reason ({}), whatever the weather, the hour, their health, their trust or the dead about (RULES2: an order is obeyed).
## What cannot be done at all (they are down, gone, away, in a breakdown) is the radio's own hard reason, asked before this. Kept so that the radio's call and the tests' still have it.
func person_reason(_p) -> Dictionary:
	return {}


## Why this person cannot be sent: "down", "has turned"... in words for the toast, "" when they can go (the same list as the radio's hard reasons).
func unable_why(p) -> String:
	if p == null:
		return "nobody answers"
	if p.turned:
		return "has turned"
	if p.dead:
		return "is gone"
	if p.downed:
		return "is down"
	if p.away != null:
		return "is away"
	if p.player:
		return "that is you"
	if sim.morale.breakdown(p):
		return "is having a breakdown"
	return ""


## Why this house cannot be searched (`containers`: or stripped, when false) by this person now ({} when it can): {"ok": false, "why", "line", "hard"}. Only what cannot be done: no house, dead in it,
## nothing left to search, no way in. Not the distance, not the dead near the door or the person (RULES2). The person's own reasons are `person_reason` (none).
func house_refusal(p, h: int, containers: bool = true) -> Dictionary:
	var hs = _houses()
	var cl = _clearing()
	if hs == null or h < 0:
		return _no(R_NO_HOUSE, true)
	if cl == null or not cl.house_clear(h) or int(hs.dead_in_house(h)) > 0:
		return _no(R_NOT_CLEARED, true)
	if containers:
		var left := plan(h, -1, Vector2(p.x, p.y), String(p.id) if p != null else "")
		if left.is_empty():
			var anyone := false
			for c in hs.containers_of(h):
				if not _search().is_looted(String(c.id)):
					anyone = true
			return _no("Somebody is already searching it" if anyone else R_SEARCHED, true)
	var door := door_spot(h)
	if door == Vector2.ZERO or float(_blocked.get(h, 0.0)) > _age:
		return _no(R_NO_WAY, true)
	return {}


# ------------------------------------------------------------------------ the order --

## An order the radio has agreed to takes effect (`radio._take_effect`): `at` is a point of the house. True when they set off. Not true when the world has changed while they thought about it
## (the dead came, the bell is near): the order is dropped and the radio is told in a toast.
func begin_order(p, at: Vector2) -> bool:
	var h := house_of_point(at)
	if p == null:
		return false
	if not _able(p):
		# (RULES2: said, with its reason: a person who is down, gone, away or in a breakdown cannot go)
		_say(p, "stopped", "%s did not go: %s" % [String(p.first), unable_why(p)], "warn", h)
		return false
	# (only what cannot be done stops it now: a house that is not a house to search any more, the dead came into it while they thought about it; no way in)
	var why := ""
	var hr := house_refusal(p, h)
	if not hr.is_empty():
		why = String(hr.why).substr(0, 1).to_lower() + String(hr.why).substr(1)
	if why != "":
		_say(p, "stopped", "%s did not go: %s" % [String(p.first), why], "warn", h)
		return false
	runs.erase(String(p.id))
	_release(String(p.id))
	if not _start_run(p, "order", h):
		_say(p, "stopped", "%s did not go: no way in" % String(p.first), "warn", h)
		return false
	sim.radio.set_stance(p, "search", house_point(h))
	return true


# ------------------------------------------------------------------------- the runs --

## Sets a person off. `mode` "search": the house's containers; "strip": the furniture of the house (SALVAGE); "street": the one wreck `piece` of the street (`h` is -1). False when there is no way.
func _start_run(p, kind: String, h: int, mode: String = "search", piece: Dictionary = {}) -> bool:
	var run := {"kind": kind, "mode": mode, "house": h, "stage": "door", "cur": "", "t": 0.0, "found": {}, "n": 0, "total": 0, "hp": float(p.hp), "wounds": int(p.wounds), "stuck": 0.0,
		"anchor": house_point(h) if h >= 0 else Vector2.ZERO, "cars": 0, "csearched": 0, "cfound": {}, "cdone": [], "cmode": "search"}
	var aim := Vector2.ZERO
	if mode == "street":
		var spot := _stand_spot(piece, Vector2(p.x, p.y))
		if spot == Vector2.ZERO:
			return false
		aim = spot
		run.stage = "strip"
		run.cur = String(piece.id)
		run.piece = String(piece.id)
		run.spot = spot
		run.at = Vector2(piece.cx, piece.cy) if piece.has("cx") else spot
		run.secs = float(piece.get("seconds", 10.0))
		run.name = String(piece.get("name", "a wreck"))
		run.total = 1
	else:
		aim = door_spot(h)
		if aim == Vector2.ZERO:
			return false
		var sv = _salvage()
		run.total = unsearched_count(h) if mode == "search" else (sv.candidates(h).size() if sv != null else 0)
		if mode == "strip" and int(run.total) == 0:
			_nowork[h] = _age + NOWORK_S    # (its furniture is there but nothing can be stripped now: not asked for a while)
			return false
	if sim.path_p.find(sim.world.solid_p, p.x, p.y, aim.x, aim.y).is_empty():
		_blocked[h] = _age + BLOCKED_S    # (no way from where they stand: not asked again for a minute)
		return false
	runs[String(p.id)] = run
	if mode == "street":
		claims[String(run.cur)] = String(p.id)
	job_note.erase(String(p.id))
	return true


## Whether the person is on a run.
func is_out(p) -> bool:
	return runs.has(String(p.id))


## The words of a person's run for their chip, the wheel and the Jobs row: "Searching 22 Elm St: 3 of 6", or "" when they are not on one.
func run_text(p) -> String:
	var run = runs.get(String(p.id))
	if run == null:
		return ""
	var h := int(run.house)
	var of := maxi(int(run.total), 1)
	var at := mini(int(run.n) + 1, of)
	if String(run.mode) == "street":
		return "Stripping %s in the street" % String(run.get("name", "a wreck"))
	if String(run.stage) == "car":
		# (SCAV3: "Searching a car near 22 Elm St", "Stripping a wreck in the street")
		var where := " near %s" % address(h) if h >= 0 else " in the street"
		return "%s %s %s%s" % ["Stripping" if String(run.get("cmode", "search")) == "strip" else "Searching", "a", String(run.get("name", "car")), where]
	if String(run.stage) == "door":
		return "Going to %s" % address(h)
	if String(run.mode) == "strip":
		return "Stripping %s: %d of %d" % [address(h), at, of]
	return "Searching %s: %d of %d" % [address(h), at, of]


## What they have found on this run, as words ("4 food, 2 scrap"), "" when nothing.
func found_text(found: Dictionary) -> String:
	var parts: Array = []
	for k in STOCKS:
		var n := int(found.get(k, 0))
		if n > 0:
			parts.append("%d %s" % [n, k])
	return ", ".join(parts)


## Two stock records added together.
func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = int(out.get(k, 0)) + int(b[k])
	return out


## What the cars of a run gave, in words: "2 cars: 6 ammo, 1 water", "1 car: nothing of use"; "" when the run visited none. A run with no house is "2 cars in the street: ...".
func cars_text(run: Dictionary) -> String:
	var n := int(run.get("cars", 0))
	if n <= 0:
		return ""
	var found := found_text(run.get("cfound", {}))
	return "%d car%s%s: %s" % [n, "" if n == 1 else "s", " in the street" if int(run.house) < 0 else "", found if found != "" else "nothing of use"]


func _container(id: String) -> Dictionary:
	var hs = _houses()
	return hs.container(id) if hs != null else {}


## The goal of a person on a run (the radio's `stance_goal` and the jobs module's `goal_for` ask): the front door, then each container's spot. null when they are not on one.
func goal_for(p):
	var run = runs.get(String(p.id))
	if run == null:
		return null
	return _run_goal(p, run)


func _run_goal(p, run: Dictionary) -> Dictionary:
	var h := int(run.house)
	if String(run.stage) == "car":
		# (SCAV3: the tile beside the car in hand, facing it; between two cars, where they stand)
		if String(run.cur) == "" or not run.has("spot"):
			return {"x": p.x, "y": p.y, "face": "", "what": run_text(p), "work": ""}
		var cspot: Vector2 = run.spot
		var cto: Vector2 = Vector2(run.get("at", cspot)) - cspot
		return {"x": cspot.x, "y": cspot.y, "face": sim.facing_of(cto.x, cto.y, String(p.facing)) if cto.length() > 0.2 else "", "what": run_text(p), "work": "hammer" if String(run.get("cmode", "search")) == "strip" else "sort"}
	if String(run.stage) == "strip" and String(run.cur) != "":
		var spot: Vector2 = run.spot
		var to: Vector2 = Vector2(run.get("at", spot)) - spot
		return {"x": spot.x, "y": spot.y, "face": sim.facing_of(to.x, to.y, String(p.facing)) if to.length() > 0.2 else "", "what": run_text(p), "work": "hammer"}
	if String(run.stage) == "search" and String(run.cur) != "":
		var c := _container(String(run.cur))
		if not c.is_empty():
			var at := Vector2(c.pos)
			var face := ""
			var to := Vector2(c.at) - at
			if to.length() > 0.2:
				face = sim.facing_of(to.x, to.y, String(p.facing))
			return {"x": at.x, "y": at.y, "face": face, "what": run_text(p), "work": "sort"}
	var door := door_spot(h)
	return {"x": door.x, "y": door.y, "face": "", "what": "Going to %s" % address(h), "work": ""}


## The job's goal: the run's when they are on one, else standing at their seat with the line the job says ("Nothing left to search: clear another house").
func job_goal(p) -> Dictionary:
	var run = runs.get(String(p.id))
	if run != null:
		return _run_goal(p, run)
	var at: Vector2 = sim.jobs.seat_pos(p)
	return {"x": at.x, "y": at.y, "face": "", "what": String(job_note.get(String(p.id), "Ready to go out")), "work": ""}


func update(dt: float) -> void:
	if not enabled:
		return
	_age += dt
	_roll_day()
	_acc += dt
	var slow := _acc >= SLOW_S
	if slow:
		_acc = 0.0
	for id in runs.keys():
		_step(String(id), dt, slow)
	if slow:
		_jobs()
		_orphans()


func _step(id: String, dt: float, slow: bool) -> void:
	var run: Dictionary = runs[id]
	var p = _person(id)
	if p == null or not _able(p):
		_end(p, id, "down")
		return
	if String(run.kind) == "order" and String(p.stance) != "search":
		_end(p, id, "stopped")
		return
	if String(run.kind) == "job" and String(sim.jobs.job_of(p)) != "scavenger":
		_end(p, id, "stopped")
		return
	if sim.medical.goal_for(p) != null:
		_end(p, id, "down")
		return
	if float(p.hp) > float(run.hp):
		run.hp = float(p.hp)
	if float(p.hp) <= float(run.hp) - BITE_HP or int(p.wounds) > int(run.wounds):
		# (RULES2: a bite is counted, and nobody turns back for it: the run goes on until the house is done, or the medical rules take them down)
		stats.bitten = int(stats.bitten) + 1
		run.hp = float(p.hp)
		run.wounds = int(p.wounds)
	if String(run.kind) == "job" and sim.posts_manned():
		# (the one thing a job run yields to: the base's night posts, the call to arms or an attack night, which take every hand to the wall; an order does not)
		_end(p, id, "posts")
		return
	if slow:
		_wake_round(Vector2(p.x, p.y))
	var h := int(run.house)
	if String(run.stage) == "door":
		var door := door_spot(h)
		if Vector2(p.x, p.y).distance_to(door) <= 0.9:
			run.stuck = 0.0
			if String(run.mode) == "strip":
				run.stage = "strip"
				if not _pick_piece(p, run):
					_finish_house(p, run)
			else:
				run.stage = "search"
				if not _pick(p, run):
					_house_done(p, run)
		elif _stuck(p, run, dt):
			_blocked[h] = _age + BLOCKED_S
			_end(p, id, "stuck")
		return
	if String(run.stage) == "car":
		_step_car(p, run, id, dt)
		return
	if String(run.stage) == "strip":
		_step_strip(p, run, id, dt)
		return
	# the search: at the container's spot, 4 s
	var cur := String(run.cur)
	if cur == "" or _search().is_looted(cur):
		_release(id)
		if not _pick(p, run):
			_house_done(p, run)
		return
	var c := _container(cur)
	if c.is_empty():
		run.cur = ""    # (a damaged save: a container that is none)
		return
	var spot := Vector2(c.pos)
	if Vector2(p.x, p.y).distance_to(spot) <= ARRIVE and not bool(p.moving):
		run.stuck = 0.0
		run.t = float(run.t) + dt
		if float(run.t) >= SearchRules.search_secs(sim, c):
			_search_done(p, run, cur)
	elif _stuck(p, run, dt):
		_blocked[h] = _age + BLOCKED_S
		_end(p, id, "stuck")


func _stuck(p, run: Dictionary, dt: float) -> bool:
	if bool(p.moving):
		run.stuck = 0.0
		return false
	run.stuck = float(run.stuck) + dt
	return float(run.stuck) >= STUCK_S


## The dead near a person who is outside wake (a smaller circle than the avatar's, a few at a time), so that the street is not an empty one for them.
func _wake_round(here: Vector2) -> void:
	var f = _field()
	var base = _base()
	if f == null or (base != null and base.at_base(here)):
		return
	f._wake_near(here, float(f.wake_r) * WAKE_SHARE, "", null, true, WAKE_MOST)


## Takes the next container of the house (the nearest to where they stand). False when none is left.
func _pick(p, run: Dictionary) -> bool:
	var list := plan(int(run.house), -1, Vector2(p.x, p.y), String(p.id))
	if list.is_empty():
		run.cur = ""
		return false
	var c: Dictionary = list[0]
	run.cur = String(c.id)
	run.t = 0.0
	run.stuck = 0.0
	claims[String(c.id)] = String(p.id)
	return true


func _release(id: String) -> void:
	for cid in claims.keys():
		if String(claims[cid]) == id:
			claims.erase(cid)


## What a run brings in is added to the run's, the day's and the person's tallies. `into` is the run's record it goes in: "found" (the house) or "cfound" (the cars of the trip: SCAV3).
func _credit(p, run: Dictionary, loot: Dictionary, into: String = "found") -> void:
	var id := String(p.id)
	for k in loot:
		run[into][k] = int(run[into].get(k, 0)) + int(loot[k])
		stats.loot[k] = int(stats.loot.get(k, 0)) + int(loot[k])
		if into == "cfound":
			stats.car_loot[k] = int(stats.car_loot.get(k, 0)) + int(loot[k])
		tally.all[k] = int(tally.all.get(k, 0)) + int(loot[k])
		var mine: Dictionary = tally.by.get(id, {})
		mine[k] = int(mine.get(k, 0)) + int(loot[k])
		tally.by[id] = mine


func _search_done(p, run: Dictionary, cur: String) -> void:
	var loot: Dictionary = _search().mark_looted(cur, p)
	claims.erase(cur)
	run.n = int(run.n) + 1
	run.cur = ""
	run.t = 0.0
	stats.containers = int(stats.containers) + 1
	_credit(p, run, loot)
	if not _pick(p, run):
		_house_done(p, run)


# ---------------------------------------------------------------------------- the cars --

## Whether the crew look at cars at all (the `cars` block of salvage.json is there, the town has cars, the trip allows one).
func _cars_on() -> bool:
	var hs = _houses()
	return hs != null and hs.get("cars") is Array and not (hs.cars as Array).is_empty() and CarLoot.most() > 0


## The last container of the house is done: the trip goes on to the cars round it (SCAV3) when there are any to do, else the run is over.
func _house_done(p, run: Dictionary) -> void:
	if String(run.mode) == "search" and _cars_on():
		run.stage = "car"
		if _car_pick(p, run):
			return
	_finish_house(p, run)


## What the crew would do at a car now: "search" (not searched yet), "strip" (searched, and salvage lets it be stripped now) or "" (nothing).
func _car_work(c: Dictionary) -> String:
	if not _search().is_looted(String(c.id)):
		return "search"
	return "strip" if _car_strippable(c) else ""


## Whether salvage would let this car be stripped now (the street cell cap, no awake dead near, not the base's; the car is searched already).
func _car_strippable(c: Dictionary) -> bool:
	var sv = _salvage()
	if sv == null or float(_nowork.get(String(c.id), 0.0)) > _age:
		return false
	var pc: Dictionary = sv.piece(String(c.get("piece", "")))
	return not pc.is_empty() and sv.why_not(pc) == ""


## Takes the next car of the trip: the nearest unsearched one within the trip's radius of its anchor, from where the person stands (a car that only wants stripping comes after the unsearched ones), and
## sets the run to walk to it. `only` (a car) is the one to take, whatever the radius (the first car of a trip from the base). False when the trip is over: the most cars were visited, or none is left.
func _car_pick(p, run: Dictionary, only: Dictionary = {}) -> bool:
	run.cur = ""
	var hs = _houses()
	if hs == null or int(run.cars) >= CarLoot.most():
		return false
	var anchor: Vector2 = run.anchor
	var radius := CarLoot.radius()
	var from := Vector2(p.x, p.y)
	var done: Array = run.cdone
	var best: Dictionary = {}
	var best_score := INF
	var best_spot := Vector2.ZERO
	var best_work := ""
	var list: Array = [only] if not only.is_empty() else hs.cars_near(anchor, radius)
	for c in list:
		var cid := String(c.id)
		if done.has(cid) or float(_nowork.get(cid, 0.0)) > _age:
			continue
		var owner = claims.get(cid)
		if owner != null and String(owner) != String(p.id):
			continue
		if only.is_empty() and Vector2(c.at).distance_to(anchor) > radius:
			continue
		var work := _car_work(c)
		if work == "":
			continue
		var spot := _stand_spot(c, from)
		if spot == Vector2.ZERO:
			done.append(cid)
			continue
		var score := from.distance_to(spot) + (200.0 if work == "strip" else 0.0)
		if score < best_score:
			best_score = score
			best = c
			best_spot = spot
			best_work = work
	if best.is_empty():
		return false
	run.cur = String(best.id)
	_car_begin(p, run, best, best_spot, best_work)
	return true


## Sets the run's car in hand: where to stand, how long, what to do there.
func _car_begin(p, run: Dictionary, c: Dictionary, spot: Vector2, work: String) -> void:
	run.cmode = work
	run.spot = spot
	run.at = Vector2(c.at)
	run.name = String(c.get("name", "car"))
	run.t = 0.0
	run.stuck = 0.0
	if work == "strip":
		var pc: Dictionary = _salvage().piece(String(c.get("piece", "")))
		run.secs = float(pc.get("seconds", 10.0))
	else:
		run.secs = SearchRules.search_secs(sim, c)
	claims[String(c.id)] = String(p.id)


## A car is done or given up: the trip's count goes up (when it was visited) and the next is picked, or the trip is over.
func _car_next(p, run: Dictionary, visited: bool) -> void:
	var cid := String(run.cur)
	if cid != "":
		(run.cdone as Array).append(cid)
		if claims.get(cid) == String(p.id):
			claims.erase(cid)
	if visited:
		run.cars = int(run.cars) + 1
	run.cur = ""
	run.t = 0.0
	if not _car_pick(p, run):
		_finish_house(p, run)


func _step_car(p, run: Dictionary, id: String, dt: float) -> void:
	var cur := String(run.cur)
	if cur == "":
		if not _car_pick(p, run):
			_finish_house(p, run)
		return
	var c := _container(cur)
	if c.is_empty():
		(run.cdone as Array).append(cur)    # (a damaged save: a car that is none)
		run.cur = ""
		return
	var search = _search()
	var strip: bool = String(run.cmode) == "strip"
	if not strip and search.is_looted(cur):
		# (somebody else searched it first, the avatar: its loot is theirs; the strip, if it can be, is still ours)
		if _car_strippable(c):
			_car_begin(p, run, c, run.spot, "strip")
		else:
			_car_next(p, run, false)
		return
	if strip and not _car_strippable(c):
		_car_next(p, run, true)    # (the cap was reached or the dead came near while they walked: no strip, the next car; the car was searched)
		return
	var spot: Vector2 = run.spot
	if Vector2(p.x, p.y).distance_to(spot) <= ARRIVE and not bool(p.moving):
		run.stuck = 0.0
		run.t = float(run.t) + dt
		if float(run.t) >= float(run.secs):
			_car_done(p, run, c)
	elif _stuck(p, run, dt):
		_nowork[cur] = _age + NOWORK_S    # (no way to this one from here: the next car, not the end of the trip)
		_car_next(p, run, false)


## The seconds at the car are up: the search (its loot to the stores) and then, when it can, the strip (its scrap).
func _car_done(p, run: Dictionary, c: Dictionary) -> void:
	var cid := String(c.id)
	if String(run.cmode) == "search":
		var loot: Dictionary = _search().mark_looted(cid, p)
		stats.cars = int(stats.cars) + 1
		run.csearched = int(run.get("csearched", 0)) + 1
		_credit(p, run, loot, "cfound")
		if _car_strippable(c):
			_car_begin(p, run, c, run.spot, "strip")
		else:
			_car_next(p, run, true)
		return
	var sv = _salvage()
	var r: Dictionary = sv.strip(String(c.piece), p) if sv != null else {}
	if bool(r.get("ok", false)):
		stats.car_strips = int(stats.car_strips) + 1
		_credit(p, run, {"scrap": int(r.get("scrap", 0))}, "cfound")
	else:
		_nowork[cid] = _age + NOWORK_S
	_car_next(p, run, true)


## A trip that begins at a car and not at a house (the Scavenger job with every house done): the first car is `car`. False when there is no way there.
func _start_cars(p, kind: String, car: Dictionary) -> bool:
	var run := {"kind": kind, "mode": "cars", "house": -1, "stage": "car", "cur": "", "t": 0.0, "found": {}, "n": 0, "total": 0, "hp": float(p.hp), "wounds": int(p.wounds), "stuck": 0.0,
		"anchor": Vector2(car.at), "cars": 0, "csearched": 0, "cfound": {}, "cdone": [], "cmode": "search"}
	var work := _car_work(car)
	var spot := _stand_spot(car, Vector2(p.x, p.y))
	if work == "" or spot == Vector2.ZERO:
		_nowork[String(car.id)] = _age + NOWORK_S
		return false
	if sim.path_p.find(sim.world.solid_p, p.x, p.y, spot.x, spot.y).is_empty():
		_nowork[String(car.id)] = _age + NOWORK_S
		return false
	run.cur = String(car.id)
	_car_begin(p, run, car, spot, work)
	runs[String(p.id)] = run
	job_note.erase(String(p.id))
	return true


# ------------------------------------------------------------------------ stripping --

## A tile beside a piece of furniture or a wreck that a person can stand on (not solid, in the piece's house when it is in one), the nearest to `from`; Vector2.ZERO when there is none.
func _stand_spot(pc: Dictionary, from: Vector2) -> Vector2:
	var rect := Rect2i(pc.get("rect", Rect2i()))
	if rect.size == Vector2i.ZERO:
		return Vector2.ZERO
	var hs = _houses()
	var h := int(pc.get("house", -1))
	var best := Vector2.ZERO
	var best_d := INF
	for ring in [1, 2]:    # (the tiles next to it; two away when they are all taken: a bed in a corner)
		for y in range(rect.position.y - ring, rect.end.y + ring):
			for x in range(rect.position.x - ring, rect.end.x + ring):
				if x >= rect.position.x - ring + 1 and x < rect.end.x + ring - 1 and y >= rect.position.y - ring + 1 and y < rect.end.y + ring - 1:
					continue    # (only the ring's own tiles)
				var at := Vector2(float(x) + 0.5, float(y) + 0.5)
				if sim.world.is_solid(sim.world.solid_p, at.x, at.y):
					continue
				if h >= 0 and hs != null and int(hs.house_at(at.x, at.y)) != h:
					continue
				var d := at.distance_squared_to(from)
				if d < best_d:
					best_d = d
					best = at
		if best != Vector2.ZERO:
			break
	return best


## Takes the next piece of the house that can be stripped (the nearest to where they stand, as `salvage.candidates` gives them). False when none is left.
func _pick_piece(p, run: Dictionary) -> bool:
	var sv = _salvage()
	run.cur = ""
	if sv == null:
		return false
	var skip: Array = run.get("skip", [])
	var from := Vector2(p.x, p.y)
	for e in sv.candidates(int(run.house), from):
		var id := String(e.id)
		var owner = claims.get(id)
		if skip.has(id) or float(_nowork.get(id, 0.0)) > _age or (owner != null and String(owner) != String(p.id)):
			continue
		var pc: Dictionary = sv.piece(id)
		var spot := _stand_spot(pc, from)
		if spot == Vector2.ZERO:
			skip.append(id)
			continue
		run.skip = skip
		run.cur = id
		run.spot = spot
		run.at = Vector2(float(pc.get("cx", spot.x)), float(pc.get("cy", spot.y)))
		run.secs = float(e.get("seconds", 10.0))
		run.name = String(e.get("name", "furniture"))
		run.t = 0.0
		run.stuck = 0.0
		claims[id] = String(p.id)
		return true
	run.skip = skip
	return false


func _step_strip(p, run: Dictionary, id: String, dt: float) -> void:
	var sv = _salvage()
	if sv == null:
		_end(p, id, "stopped")
		return
	var cur := String(run.cur)
	if cur == "":
		if String(run.mode) == "street" or not _pick_piece(p, run):
			_finish_house(p, run)
		return
	if sv.stripped.has(cur):
		_release(id)    # (somebody else stripped it first)
		run.cur = ""
		return
	var spot: Vector2 = run.spot
	if Vector2(p.x, p.y).distance_to(spot) <= ARRIVE and not bool(p.moving):
		run.stuck = 0.0
		run.t = float(run.t) + dt
		if float(run.t) >= float(run.secs):
			_strip_done(p, run, sv, cur)
	elif _stuck(p, run, dt):
		_end(p, id, "stuck")


func _strip_done(p, run: Dictionary, sv, cur: String) -> void:
	var r: Dictionary = sv.strip(cur, p)
	_release(String(p.id))
	run.cur = ""
	run.t = 0.0
	if bool(r.get("ok", false)):
		run.n = int(run.n) + 1
		stats.stripped = int(stats.stripped) + 1
		_credit(p, run, {"scrap": int(r.get("scrap", 0))})
	else:
		var skip: Array = run.get("skip", [])
		skip.append(cur)    # (it cannot be stripped now: the next piece)
		run.skip = skip
		_nowork[cur] = _age + NOWORK_S
	if String(run.mode) == "street":
		_finish_house(p, run)


## The last container (or piece) of the house is done: an order is over (the stance goes, they are back at their work); a job goes to the next house when there is time.
func _finish_house(p, run: Dictionary) -> void:
	var id := String(p.id)
	var h := int(run.house)
	var mode := String(run.mode)
	var street := mode == "street"
	var cars_only := mode == "cars"
	var stripping := mode == "strip" or street
	if not cars_only:
		stats.houses = int(stats.houses) + 1
	if stripping and int(run.n) == 0:
		# (nothing could be stripped there after all: no word of it, and not that house or wreck again for a while)
		_nowork[String(run.get("piece", "")) if street else h] = _age + NOWORK_S
		_end(p, id, "empty")
		return
	if cars_only and int(run.cars) == 0:
		_end(p, id, "empty")    # (SCAV3: a trip to cars that visited none: no word of it)
		return
	var found := found_text(run.found)
	var text := ""
	if cars_only:
		text = "%s %s %s" % [String(p.first), "searched" if int(run.get("csearched", 0)) > 0 else "stripped", cars_text(run)]    # (a trip that only stripped cars somebody had searched says so)
	else:
		text = "%s %s %s: %s" % [String(p.first), "stripped" if stripping else "searched", address(h) if not street else "a %s in the street" % String(run.get("name", "wreck")), found if found != "" else "nothing of use"]
		var ct := cars_text(run)
		if ct != "":
			text += "; " + ct    # (SCAV3: "Femi searched 22 Elm St: 4 food, 2 scrap; 2 cars: 6 ammo, 1 water")
	sim.radio.log_news("crew_search", text, "")
	_end(p, id, "done", text)
	if String(run.kind) == "job" and p != null:
		_idle_until.erase(id)
		_job_try(p)


## A run is over: `why` is "done", "posts" (a job run, the night posts are manned), "stuck", "empty", "stopped" (their order was replaced or taken back: nothing is said) or "down" (the medical rules have them: nothing is said).
func _end(p, id: String, why: String, text: String = "") -> void:
	var run = runs.get(id)
	runs.erase(id)
	_release(id)
	stats.ended[why] = int(stats.ended.get(why, 0)) + 1
	if p == null or run == null:
		return
	if String(run.kind) == "order" and String(p.stance) == "search":
		sim.radio.clear_stance(p)
	var h := int(run.house)
	match why:
		"done":
			_say(p, why, text, "info", h, false)
		"posts":
			_say(p, why, "%s is back at the wall: the dead are coming" % String(p.first), "info", h)
		"stuck":
			_say(p, why, "%s cannot get to %s: heading home" % [String(p.first), address(h)], "warn", h)
	var brought := found_text(_merge(run.found, run.get("cfound", {})))
	if why != "done" and why != "stopped" and why != "down" and brought != "":
		sim.radio.log_news("crew_search", "%s came back from %s with %s" % [String(p.first), address(h), brought], "")


func _say(p, what: String, text: String, level: String, h: int, news: bool = false) -> void:
	sim.events.append({"type": "crew_search", "who": String(p.id), "name": String(p.first), "what": what, "text": text, "level": level, "house": h})
	if news:
		sim.radio.log_news("crew_search", text, "")


## A search stance with no run behind it (a load that lost one, a request taken after the run ended) is dropped.
func _orphans() -> void:
	for p in sim.people:
		if String(p.stance) == "search" and not runs.has(String(p.id)):
			var waiting := false
			for e in sim.radio.pending:
				if String(e.who) == String(p.id) and String(e.verb) == "search":
					waiting = true
			if not waiting:
				sim.radio.clear_stance(p)


# -------------------------------------------------------------------------- the job --

## The houses a scavenger would go to, nearest to the base's middle first: cleared, with something left to search, within FAR_TILES: [{"h", "d"}]. Kept a few seconds.
func candidates() -> Array:
	var cl = _clearing()
	var hs = _houses()
	var search = _search()
	var base = _base()
	if cl == null or hs == null or search == null or base == null or not base.claimed:
		return []
	var key := "%d|%d" % [search.looted.size(), cl.done.size()]
	if key == _cands_key and _age - _cands_t < CANDIDATES_S:
		return _cands
	_cands_key = key
	_cands_t = _age
	_cands = []
	var mid: Vector2 = base.center()
	for h in cl.done.keys():
		var hp := house_point(int(h))
		var d := mid.distance_to(hp)
		if d > FAR_TILES:
			continue
		var any := false
		for c in hs.containers_of(int(h)):
			if not search.is_looted(String(c.id)):
				any = true
				break
		if any:
			_cands.append({"h": int(h), "d": d})
	_cands.sort_custom(func(a, b): return float(a.d) < float(b.d) or (is_equal_approx(float(a.d), float(b.d)) and int(a.h) < int(b.h)))
	return _cands


## Every job scavenger without a run looks for a house (twice a second): the note says why not when there is none.
func _jobs() -> void:
	for p in sim.jobs.crew_of("scavenger"):
		if not runs.has(String(p.id)) and _able(p):
			_job_try(p)


## A job scavenger goes to the next house, or says why not (`job_note`). True when they set off.
func _job_try(p) -> bool:
	var id := String(p.id)
	if p.player or runs.has(id):
		return false
	# (RULES2: any hour, any weather, whatever their health: the one thing it waits for is the base's night posts, which take every hand to the wall)
	if sim.posts_manned():
		job_note[id] = "At the wall: the dead are coming"
		return false
	if float(_idle_until.get(id, 0.0)) > _age:
		return false    # (looked a moment ago and found nothing: the note stands)
	_idle_until[id] = _age + IDLE_S
	var asked := 0
	for e in candidates():
		asked += 1
		if asked > MAX_HOUSE_ASK:
			break
		if not house_refusal(p, int(e.h)).is_empty():
			continue
		if _start_run(p, "job", int(e.h)):
			return true
	if _cars_try(p):
		return true
	if _salvage_try(p) == 1:
		return true
	job_note[id] = NOTHING_LEFT
	return false


## SCAV3: no house left to search (loot comes before strip work): a trip to the cars and wrecks of the street, from the one nearest the base within FAR_TILES of it (an unsearched one first). True when they set off.
func _cars_try(p) -> bool:
	var base = _base()
	var hs = _houses()
	if not _cars_on() or base == null or not base.claimed:
		return false
	var mid: Vector2 = base.center()
	var from := Vector2(p.x, p.y)
	var list: Array = []
	for c in hs.cars_near(mid, FAR_TILES):
		var cid := String(c.id)
		if Vector2(c.at).distance_to(mid) > FAR_TILES or claims.has(cid) or float(_nowork.get(cid, 0.0)) > _age:
			continue
		var work := _car_work(c)
		if work == "":
			continue
		list.append([from.distance_to(Vector2(c.at)) + (200.0 if work == "strip" else 0.0), c])
	list.sort_custom(func(a, b): return float(a[0]) < float(b[0]) or (is_equal_approx(float(a[0]), float(b[0])) and String(a[1].id) < String(b[1].id)))
	var asked := 0
	for e in list:
		asked += 1
		if asked > MAX_HOUSE_ASK:
			break
		if _start_cars(p, "job", e[1]):
			return true
	return false


## With nothing left to search, the town's salvage module (SALVAGE, when there is one) may have strip work: the furniture of the cleared houses near the base, nearest first, then the wrecks of the
## street. 1 when they set off, else 0 (RULES2: the dead about are no reason to wait).
func _salvage_try(p) -> int:
	var sv = _salvage()
	var cl = _clearing()
	var base = _base()
	if sv == null or cl == null or base == null or not base.claimed:
		return 0
	var mid: Vector2 = base.center()
	var list: Array = []
	for h in cl.done.keys():
		var d := mid.distance_to(house_point(int(h)))
		if d <= FAR_TILES and int(sv.available(int(h))) > 0:
			list.append([d, int(h)])
	list.sort_custom(func(a, b): return float(a[0]) < float(b[0]) or (is_equal_approx(float(a[0]), float(b[0])) and int(a[1]) < int(b[1])))
	var asked := 0
	for e in list:
		if float(_nowork.get(int(e[1]), 0.0)) > _age:
			continue
		asked += 1
		if asked > MAX_HOUSE_ASK:
			break
		if not house_refusal(p, int(e[1]), false).is_empty():
			continue
		if _start_run(p, "job", int(e[1]), "strip"):
			return 1
	if sv.has_method("street_candidates"):
		for e in sv.street_candidates(mid, FAR_TILES):
			var id := String(e.id)
			if claims.has(id) or float(_nowork.get(id, 0.0)) > _age:
				continue
			var pc: Dictionary = sv.piece(id)
			if pc.is_empty():
				continue
			pc["seconds"] = float(e.get("seconds", 10.0))
			pc["name"] = String(e.get("name", "a wreck"))
			if _start_run(p, "job", -1, "street", pc):
				return 1
			_nowork[id] = _age + NOWORK_S    # (no place to stand, or no way there)
			asked += 1
			if asked > MAX_HOUSE_ASK:
				break
	return 0


# -------------------------------------------------------------------- the day's tally --

func _roll_day() -> void:
	var day := int(sim.day)
	if int(tally.day) == day:
		return
	if int(tally.day) == day - 1:
		yesterday = {"day": int(tally.day), "all": (tally.all as Dictionary).duplicate()}
	elif int(tally.day) != 0:
		yesterday = {"day": 0, "all": {}}
	tally = {"day": day, "all": {}, "by": {}}


## What this person has found today, in words ("Found today: 4 food, 2 scrap"), "" for a person who is not a scavenger and has found nothing.
func today_text(p) -> String:
	var mine: Dictionary = tally.by.get(String(p.id), {})
	var found := found_text(mine)
	if found != "":
		return "Found today: %s" % found
	return "Found today: nothing yet" if String(sim.jobs.job_of(p)) == "scavenger" else ""


## The morning summary's line ("Scavengers found: 12 food, 6 scrap yesterday", scripts/ui/dawn_tally.gd), "" when nothing was found yesterday.
func yesterday_text() -> String:
	if int(yesterday.day) != int(sim.day) - 1:
		return ""
	var found := found_text(yesterday.all)
	return "Scavengers found: %s yesterday" % found if found != "" else ""


# ------------------------------------------------------------------------ staging --

## A screenshot's or a lab's staging: `<who>@<house>[:inside][:clear]` (who: a person id, a first name or `#n`, the nth of the crew after the avatar; house: an id, `near` for the nearest cleared house with
## something left, or `base`). `:clear` puts the house's dead down and counts it cleared first; `:inside` puts them at the first container; the order is given with no delay. True when they set off.
func stage(spec: String) -> bool:
	var parts := spec.split(":")
	var left := String(parts[0]).split("@")
	var who = _find_person(String(left[0]))
	var hs = _houses()
	var base = _base()
	if who == null or hs == null:
		return false
	var h := -1
	var want := String(left[1]) if left.size() > 1 else "near"
	if want.is_valid_int():
		h = int(want)
	elif want == "base" and base != null and base.claimed:
		h = int(base.house)
	else:
		var from := Vector2(who.x, who.y)
		var best_d := INF
		var want_cars := parts.has("car")    # (SCAV3: a picture of the cars: only a house that has some within the trip's radius)
		for e in candidates():
			var d := from.distance_to(house_point(int(e.h)))
			if d < best_d and (not want_cars or not hs.cars_near(house_point(int(e.h)), CarLoot.radius() - 3.0).is_empty()):
				best_d = d
				h = int(e.h)
		if h < 0 and parts.has("clear"):
			for i in int(hs.count()):
				var d := from.distance_to(house_point(i))
				if i != int(hs.start_house()) and d < best_d and unsearched_count(i) > 0 and base != null and base.center().distance_to(house_point(i)) <= FAR_TILES \
						and (not want_cars or not hs.cars_near(house_point(i), CarLoot.radius() - 3.0).is_empty()):
					best_d = d
					h = i
	if h < 0:
		return false
	if parts.has("clear"):
		_clear_house(h)
	if not _start_run(who, "order", h):
		return false
	sim.radio.set_stance(who, "search", house_point(h))
	staged = who
	if parts.has("inside"):
		var run: Dictionary = runs[String(who.id)]
		run.stage = "search"
		if _pick(who, run):
			var c := _container(String(run.cur))
			who.x = float(c.pos.x)
			who.y = float(c.pos.y)
			who.path = []
			who.moving = false
	if parts.has("car"):
		# (SCAV3, a picture of the trip to the cars: the house taken as done, the person at the nearest car with the search half run; `near` prefers a house with cars within the trip's radius)
		var run2: Dictionary = runs[String(who.id)]
		run2.stage = "car"
		run2.cur = ""
		if _car_pick(who, run2):
			var spot2: Vector2 = run2.spot
			who.x = spot2.x
			who.y = spot2.y
			who.path = []
			who.moving = false
			run2.t = float(run2.secs) * 0.45
	return true


func _find_person(word: String):
	var crew: Array = []
	for p in sim.people:
		if not p.player and not p.dead and not p.turned:
			crew.append(p)
	if word.begins_with("#") and word.trim_prefix("#").is_valid_int():
		var i := int(word.trim_prefix("#")) - 1
		return crew[i] if i >= 0 and i < crew.size() else null
	for p in sim.people:
		if String(p.id) == word or String(p.first).to_lower() == word.to_lower():
			return p
	return null


## Puts a house's dead down (their records are removed) and counts it cleared, for a screenshot or a lab.
func _clear_house(h: int) -> void:
	var f = _field()
	var hs = _houses()
	var cl = _clearing()
	if f != null:
		for z in sim.zombies.duplicate():
			if z.state != "dying" and z.state != "dead" and int(hs.house_at(z.x, z.y)) == h:
				sim._hurt_zombie(z, 9999.0, 0.0, null)
		var i := int(f.n) - 1
		while i >= 0:
			if int(f.status[i]) == f.DORMANT and int(hs.house_at(f.xs[i], f.ys[i])) == h:
				f.remove_record(i)
			i -= 1
	if cl != null:
		cl.done[h] = true
		for r in hs.rooms_of(h):
			cl.revealed[int(r)] = true
			cl.cleared[int(r)] = true
	_cands_key = ""


## The lab's way to give the scavengers houses to go to (a player who has cleared the street round the base): the `n` houses nearest the base's middle, within FAR_TILES, that have containers and
## are not the base, are cleared as `_clear_house` does (their dead put down). Returns their ids.
func stage_cleared(n: int) -> Array:
	var hs = _houses()
	var base = _base()
	var out: Array = []
	if hs == null or base == null or not base.claimed:
		return out
	var mid: Vector2 = base.center()
	var list: Array = []
	for i in int(hs.count()):
		if i == int(base.house) or hs.containers_of(i).is_empty():
			continue
		var d := mid.distance_to(house_point(i))
		if d <= FAR_TILES:
			list.append([d, i])
	list.sort_custom(func(a, b): return float(a[0]) < float(b[0]) or (is_equal_approx(float(a[0]), float(b[0])) and int(a[1]) < int(b[1])))
	for k in mini(n, list.size()):
		_clear_house(int(list[k][1]))
		out.append(int(list[k][1]))
	return out


## The people the lab and a screenshot take for the Scavenger job, first to last: the ones with no job, then the work that costs the base least in the first days (the radio desk, the lookout, the
## infirmary), the bench and the builders last.
const GIVE_ORDER := ["", "radio", "watch", "infirmary", "garden", "salvage", "builders", "bench"]


## The lab's and a screenshot's way to staff the job: `n` people of the crew (the avatar aside) on the Scavenger job, as far as there are seats and hands. Nobody is taken off the job.
func stage_job(n: int) -> int:
	var jobs = sim.jobs
	var have := 0
	for p in jobs.crew_of("scavenger"):
		if not p.player:
			have += 1
	while have < n:
		var best = null
		var best_rank := 99
		for p in sim.people:
			if p.player or p.dead or p.turned or p.away != null or p.downed or jobs.job_of(p) == "scavenger":
				continue
			var rank: int = GIVE_ORDER.find(String(jobs.job_of(p)))
			if rank < 0:
				rank = GIVE_ORDER.size()
			if rank < best_rank:
				best_rank = rank
				best = p
		if best == null or not jobs.assign(best, "scavenger"):
			break
		have += 1
	return have


# -------------------------------------------------------------------------- the save --

func save() -> Dictionary:
	var r := {}
	for id in runs:
		r[String(id)] = (runs[id] as Dictionary).duplicate(true)
	return {"v": 2, "runs": r, "tally": tally.duplicate(true), "yesterday": yesterday.duplicate(true), "stats": stats.duplicate(true)}


func load_state(d: Dictionary) -> void:
	start()
	var raw = d.get("runs", {})
	if typeof(raw) == TYPE_DICTIONARY:
		for id in raw:
			var e = raw[id]
			if typeof(e) != TYPE_DICTIONARY or _person(String(id)) == null:
				continue
			var kind := String(e.get("kind", "order"))
			var mode := String(e.get("mode", "search"))
			var h := int(e.get("house", -1))
			var hs = _houses()
			if (kind != "order" and kind != "job") or not ["search", "strip", "street", "cars"].has(mode) or hs == null or h >= int(hs.count()) or (h < 0 and mode != "street" and mode != "cars"):
				continue
			var stage := String(e.get("stage", "door"))
			var run := {"kind": kind, "mode": mode, "house": h, "stage": stage if ["door", "search", "strip", "car"].has(stage) else "door", "cur": String(e.get("cur", "")), "t": clampf(float(e.get("t", 0.0)), 0.0, 600.0),
				"found": _clean_stock(e.get("found", {})), "n": maxi(0, int(e.get("n", 0))), "total": maxi(0, int(e.get("total", 0))), "hp": clampf(float(e.get("hp", 100.0)), 0.0, 100.0),
				"wounds": maxi(0, int(e.get("wounds", 0))), "stuck": 0.0}
			# (SCAV3: the trip to the cars: the cars done so far and what they gave; the car in hand is picked again, nothing of it is resumed)
			var anchor := _vec(e.get("anchor"))
			var cdone: Array = []
			if typeof(e.get("cdone")) == TYPE_ARRAY:
				for s2 in e.cdone:
					cdone.append(String(s2))
			run["anchor"] = anchor if anchor != Vector2.ZERO else (house_point(h) if h >= 0 else Vector2.ZERO)
			run["cars"] = clampi(int(e.get("cars", 0)), 0, 99)
			run["csearched"] = clampi(int(e.get("csearched", 0)), 0, 99)
			run["cfound"] = _clean_stock(e.get("cfound", {}))
			run["cdone"] = cdone
			run["cmode"] = "search"
			if String(run.stage) == "car":
				if mode == "strip" or mode == "street" or Vector2(run.anchor) == Vector2.ZERO:
					continue    # (not a stage of theirs, or a trip with nowhere to measure from)
				run.cur = ""
			elif mode == "cars":
				continue    # (a trip that begins at a car is always at the car stage)
			if mode == "strip" or mode == "street":
				var spot = _vec(e.get("spot"))
				if spot == Vector2.ZERO or String(run.stage) == "search":
					continue    # (a strip with no place to stand: not resumed)
				run["spot"] = spot
				run["at"] = _vec(e.get("at")) if _vec(e.get("at")) != Vector2.ZERO else spot
				run["secs"] = clampf(float(e.get("secs", 10.0)), 0.5, 600.0)
				run["name"] = String(e.get("name", "furniture"))
				var skip: Array = []
				if typeof(e.get("skip")) == TYPE_ARRAY:
					for s in e.skip:
						skip.append(String(s))
				run["skip"] = skip
			elif String(run.stage) == "strip":
				run.stage = "door"
			runs[String(id)] = run
			if String(run.cur) != "":
				claims[String(run.cur)] = String(id)
	var t = d.get("tally", {})
	if typeof(t) == TYPE_DICTIONARY:
		var by := {}
		var raw_by = t.get("by", {})
		if typeof(raw_by) == TYPE_DICTIONARY:
			for k in raw_by:
				by[String(k)] = _clean_stock(raw_by[k])
		tally = {"day": maxi(0, int(t.get("day", 0))), "all": _clean_stock(t.get("all", {})), "by": by}
	var y = d.get("yesterday", {})
	if typeof(y) == TYPE_DICTIONARY:
		yesterday = {"day": maxi(0, int(y.get("day", 0))), "all": _clean_stock(y.get("all", {}))}
	var s = d.get("stats", {})
	if typeof(s) == TYPE_DICTIONARY:
		stats = {"containers": maxi(0, int(s.get("containers", 0))), "houses": maxi(0, int(s.get("houses", 0))), "loot": _clean_stock(s.get("loot", {})), "ended": {}, "bitten": maxi(0, int(s.get("bitten", 0))),
			"stripped": maxi(0, int(s.get("stripped", 0))), "cars": maxi(0, int(s.get("cars", 0))), "car_strips": maxi(0, int(s.get("car_strips", 0))), "car_loot": _clean_stock(s.get("car_loot", {}))}
		var en = s.get("ended", {})
		if typeof(en) == TYPE_DICTIONARY:
			for k in en:
				stats.ended[String(k)] = maxi(0, int(en[k]))


static func _vec(v) -> Vector2:
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


func _clean_stock(v) -> Dictionary:
	var out := {}
	if typeof(v) == TYPE_DICTIONARY:
		for k in v:
			if STOCKS.has(String(k)) and (typeof(v[k]) == TYPE_INT or typeof(v[k]) == TYPE_FLOAT):
				out[String(k)] = maxi(0, int(v[k]))
	return out
