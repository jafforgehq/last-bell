## Searching the containers of the town's houses (One House, WP3, plan 1.14): the avatar stands within REACH of a container's spot, E begins a session of the
## container's `search_s` (4 s; skill-free, the hands off the keys: scripts/town/uses.gd), and when it is done the loot goes STRAIGHT into `sim.stock`
## (no bags: the stash is the stock), the container is looted for good, and `{"type": "searched", "container", "house", "loot": {stock: n}}` is told.
## It is the rules of raid_run.gd's `begin_search`, `_search_step` and `_open` against `sim.houses.containers_of(h)`, which RaidRun's own cannot serve
## in the colony's sim. A looted container is drawn open (WP2 reads `is_looted`). Candidates: kind "container". Saved: the ids that are looted.
## SCAV3: the parked cars and wrecks of the streets are containers too (scripts/town/car_loot.gd, kept by `sim.houses.cars`): outside every house the avatar's E offers "Search the car" within
## CarLoot.reach() tiles of the car's edge, the same 4 s session, the same `looted` flag (so a car the crew searched is not searched again and a saved game keeps it).
extends RefCounted

const CarLoot := preload("res://scripts/town/car_loot.gd")
const Inventory := preload("res://scripts/sim/inventory.gd")
const REACH := 0.9
const SEARCH_S := 4.0

var sim
var enabled := true
var looted := {}


func setup(s) -> void:
	sim = s


func start() -> void:
	looted = {}


## Whether this container has been SEARCHED (its session ran its course and its window was closed or emptied; a crew member's search counts). In the town's pack game it can still hold items she left
## (`has_left`): that is what the shimmer and the E prompt look at.
func is_looted(id: String) -> bool:
	return looted.has(id)


## INV-CORE: the pack game is on (the loot goes into containers' grids and the pack, scripts/town/inv.gd).
func _inv():
	var inv = sim.get("inv")
	return inv if inv != null and inv.active() else null


## Items she left in a container she searched.
func has_left(id: String) -> bool:
	var inv = _inv()
	return inv != null and looted.has(id) and inv.containers.has(id) and inv.items_left(id) > 0


## Searched and nothing worth coming back for: the shimmer and the green tick go by this, not by `is_looted`.
func is_spent(id: String) -> bool:
	return looted.has(id) and not has_left(id)


## How many items of a container show in the loot window (one more every 0.4 s of its search; all once it is searched). 0 in a game with no pack.
func revealed(id: String) -> int:
	var inv = _inv()
	return inv.revealed(id) if inv != null else 0


## {"looted": bool, "progress": 0 to 1 while the avatar is at it, "revealed": items showing, "items": items in it, "left": items left in a searched one}.
func state(id: String) -> Dictionary:
	var progress := 0.0
	var u = sim.get("uses")
	if u != null and u.in_session("container", id):
		var pr: Dictionary = u.progress()
		progress = clampf(float(pr.t) / maxf(float(pr.of), 0.001), 0.0, 1.0)
	var inv = _inv()
	if inv == null:
		return {"looted": looted.has(id), "progress": progress}
	return {"looted": looted.has(id), "progress": progress, "revealed": inv.revealed(id), "items": inv.items_left(id), "left": inv.items_left(id) if looted.has(id) else 0}


## The seconds a container takes to search: its own `search_s` (the generator's 4) times the run's `tempo.search_mult` (TEMPO, one_house.json: 0.625, 2.5 s a container). The avatar's session,
## the room search's walk and the crew's timer all ask this, so that they agree. 1.0 when the run has no scenario (a test's bare town).
static func search_secs(sim, cont: Dictionary) -> float:
	var base := float(cont.get("search_s", SEARCH_S))
	var sc = sim.get("scenario") if sim != null else null
	if sc != null and sc.has_method("tempo"):
		return maxf(base * float(sc.tempo("search_mult", 1.0)), 0.3)
	return base


## A container as a Dictionary ({} when `id` is none of the house's): `containers_of` may give the containers or their ids.
func _find(h: int, id: String) -> Dictionary:
	if h < 0:
		var hs = sim.get("houses")
		var car: Dictionary = hs.container(id) if hs != null else {}    # (outside every house: a car or a wreck of the street)
		return car if bool(car.get("car", false)) else {}
	for c in _list(h):
		if String(c.get("id", "")) == id:
			return c
	return {}


func _list(h: int) -> Array:
	var hs = sim.get("houses")
	var out: Array = []
	if hs == null or h < 0:
		return out
	var town = hs.get("town")
	for c in hs.containers_of(h):
		if typeof(c) == TYPE_DICTIONARY:
			out.append(c)
		elif town != null and typeof(town) == TYPE_DICTIONARY:
			for t in town.get("containers", []):
				if String(t.get("id", "")) == String(c):
					out.append(t)
					break
	return out


func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


## "Search the cupboard" for each container of the avatar's house within REACH, "Stop searching" for the one in hand; none that is looted.
func candidates(p) -> Array:
	var out: Array = []
	var hs = sim.get("houses")
	if hs == null or not enabled:
		return out
	var h: int = hs.house_at(p.x, p.y)
	if h < 0:
		return _car_candidates(p)
	var me := Vector2(p.x, p.y)
	var u = sim.get("uses")
	for c in _list(h):
		var id := String(c.get("id", ""))
		var d := me.distance_to(Vector2(c.pos))
		if d > REACH:
			continue
		var kind := String(c.get("kind", "container")).replace("_", " ")
		var again := _again_candidate(id, kind, Vector2(c.pos), d)
		if not again.is_empty():
			out.append(again)
			continue
		if looted.has(id):
			continue
		var stop: bool = u != null and u.in_session("container", id)
		out.append({"kind": "container", "id": id, "label": ("Stop searching" if stop else "Search the %s" % kind), "pos": Vector2(c.pos), "dist": d, "ok": true, "why": "", "session": true})
	return out


## INV-CORE: E at a container that is already searched: "Close the cupboard" while its window is up, "Open the cupboard" when she left items in it. No session (nothing to search again). {} otherwise.
func _again_candidate(id: String, kind: String, pos: Vector2, d: float) -> Dictionary:
	var inv = _inv()
	if inv == null:
		return {}
	if inv.open_id == id and inv.searched.has(id):
		return {"kind": "container", "id": id, "label": "Close the %s" % kind, "pos": pos, "dist": d, "ok": true, "why": "", "session": false}
	if has_left(id):
		return {"kind": "container", "id": id, "label": "Open the %s" % kind, "pos": pos, "dist": d, "ok": true, "why": "", "session": false}
	return {}


## SCAV3: "Search the car" (or the wreck) for each unsearched car of the street within reach of the avatar, who is outside every house.
func _car_candidates(p) -> Array:
	var out: Array = []
	var hs = sim.get("houses")
	if hs == null or not hs.has_method("cars_near") or not enabled:
		return out
	var me := Vector2(p.x, p.y)
	var u = sim.get("uses")
	var reach := CarLoot.reach()
	for c in hs.cars_near(me, reach):
		var id := String(c.get("id", ""))
		var d := CarLoot.rect_dist(me, c.rect)
		if d > reach:
			continue
		var again := _again_candidate(id, String(c.get("name", "car")), Vector2(c.at), d)
		if not again.is_empty():
			out.append(again)
			continue
		if looted.has(id):
			continue
		var stop: bool = u != null and u.in_session("container", id)
		out.append({"kind": "container", "id": id, "label": "Stop searching" if stop else "Search the %s" % String(c.get("name", "car")), "pos": Vector2(c.at), "dist": d, "ok": true, "why": "", "session": true})
	return out


func use(c: Dictionary) -> Dictionary:
	if String(c.get("kind", "")) != "container":
		return {}
	var id := String(c.get("id", ""))
	var u = sim.get("uses")
	var p = _lead()
	if u == null or p == null:
		return {"ok": false, "line": "", "why": "You are not here", "session": true}
	if u.in_session("container", id):
		u.cancel("stopped")
		return {"ok": true, "line": "Stopped searching.", "why": "", "session": true, "stopped": true}
	var hs = sim.get("houses")
	var h: int = hs.house_at(p.x, p.y) if hs != null else -1
	var cont := _find(h, id)
	var inv = _inv()
	if inv != null and not cont.is_empty():
		# (INV-CORE: E at a container that is open closes it; at one she left items in it opens its window again, with no search)
		if inv.open_id == id and inv.searched.has(id):
			inv.close_container()
			return {"ok": true, "line": "Closed.", "why": "", "session": false}
		if has_left(id):
			inv.open_container(id)
			return {"ok": true, "line": "Opening the %s" % String(cont.get("kind", "container")).replace("_", " "), "why": "", "session": false}
	if cont.is_empty() or looted.has(id):
		return {"ok": false, "line": "", "why": "Nothing to search here", "session": true}
	if bool(cont.get("car", false)):
		# (SCAV3: a car of the street: the reach is from its edge, the session is held where she stands)
		if CarLoot.rect_dist(Vector2(p.x, p.y), cont.rect) > CarLoot.reach() + 0.3:
			return {"ok": false, "line": "", "why": "Too far from it", "session": true}
		var car_s := search_secs(sim, cont)
		var cr: Dictionary = u.begin_session("container", id, "Searching", car_s, Vector2(p.x, p.y), 0.7, Callable(self, "_finish").bind(-1, id))
		if not bool(cr.get("ok", false)):
			return {"ok": false, "line": "", "why": String(cr.get("why", "")), "session": true}
		if inv != null:
			inv.on_search_begin(id)
		return {"ok": true, "line": "Searching the %s" % String(cont.get("name", "car")), "why": "", "session": true, "seconds": car_s}
	if Vector2(p.x, p.y).distance_to(Vector2(cont.pos)) > REACH:
		return {"ok": false, "line": "", "why": "Too far from it", "session": true}
	var seconds := search_secs(sim, cont)
	var kind := String(cont.get("kind", "container")).replace("_", " ")
	var r: Dictionary = u.begin_session("container", id, "Searching", seconds, Vector2(cont.pos), REACH + 0.3, Callable(self, "_finish").bind(h, id))
	if not bool(r.get("ok", false)):
		return {"ok": false, "line": "", "why": String(r.get("why", "")), "session": true}
	if inv != null:
		inv.on_search_begin(id)
	return {"ok": true, "line": "Searching the %s" % kind, "why": "", "session": true, "seconds": seconds}


## The session ran its course: the loot to the stores, the container looted. (INV-CORE: in the pack game its scrap goes to the stores and its items to the loot window, or to the pack at once when a
## hand takes everything: the room search, the lab's bot; the container is looted when its grid is empty or its window closes.)
func _finish(h: int, id: String) -> void:
	var cont := _find(h, id)
	if cont.is_empty() or looted.has(id):
		return
	var inv = _inv()
	if inv != null:
		_finish_pack(inv, h, id, cont)
		return
	looted[id] = true
	var loot := {}
	var loot_in = cont.get("loot", {})
	if typeof(loot_in) == TYPE_DICTIONARY:
		for k in loot_in:
			var n := float(loot_in[k])
			if n > 0.0 and sim.stock.has(k):
				sim.stock[k] = float(sim.stock[k]) + n
				loot[String(k)] = int(n)
	sim.events.append({"type": "searched", "container": id, "house": h, "loot": loot})


## The pack game's end of a search: the scrap (and whatever is not an item) to the stores now; the items to her hands. The `searched` event says what she found (`loot`), whether it is already in the pack
## (`taken`: the hand that takes everything) and that the pack game is on (`inv`), so that the window's pops are not those of a crew member's abstract search.
func _finish_pack(inv, h: int, id: String, cont: Dictionary) -> void:
	if inv.searched.has(id):
		return
	var loot := {}
	var loose := Inventory.loose_units(cont.get("loot", {}) if typeof(cont.get("loot", {})) == TYPE_DICTIONARY else {})
	for k in loose:
		if sim.stock.has(k):
			sim.stock[k] = float(sim.stock[k]) + float(loose[k])
			loot[String(k)] = int(loose[k])
	var found: Dictionary = inv.units_in(id)
	var auto: bool = inv.auto_take or inv._room_search_running()
	inv.on_search_done(id)
	var shown: Dictionary = (inv.last_taken.get(id, {}) as Dictionary) if auto else found
	for k in shown:
		loot[String(k)] = int(loot.get(String(k), 0)) + int(shown[k])
	sim.events.append({"type": "searched", "container": id, "house": h, "loot": loot, "inv": true, "taken": auto, "items": inv.items_left(id)})


# --------------------------------------------------------------- whoever searches --

## The loot a container holds that is not taken yet, as the stock would get it ({stock key: int}; {} when it is looted, unknown or has nothing). For anyone who searches that is
## not the avatar's session: a crew member (scripts/town/crew_search.gd) asks what is there before they go. In the pack game it is what is still in the container's grid, and the scrap if she
## has not searched it.
func loot_of(id: String) -> Dictionary:
	var out := {}
	if looted.has(id):
		return out
	var inv = _inv()
	if inv != null:
		var hs0 = sim.get("houses")
		var cont0: Dictionary = hs0.container(id) if hs0 != null else {}
		if cont0.is_empty():
			return out
		for k in inv.units_in(id):
			if sim.stock.has(k):
				out[String(k)] = int(inv.units_in(id)[k])
		if not inv.searched.has(id):
			var loose := Inventory.loose_units(cont0.get("loot", {}) if typeof(cont0.get("loot", {})) == TYPE_DICTIONARY else {})
			for k in loose:
				if sim.stock.has(k):
					out[String(k)] = int(out.get(String(k), 0)) + int(loose[k])
		return out
	var hs = sim.get("houses")
	var cont: Dictionary = hs.container(id) if hs != null else {}
	var loot_in = cont.get("loot", {})
	if typeof(loot_in) != TYPE_DICTIONARY:
		return out
	for k in loot_in:
		var n := float(loot_in[k])
		if n > 0.0 and sim.stock.has(k):
			out[String(k)] = int(n)
	return out


## A container searched by somebody who is not in a session (a crew member, scripts/town/crew_search.gd): looted for good, its loot straight into the stock and `searched` told,
## with the searcher's id and first name (`who`, `name`; the avatar's own `_finish` tells neither). Returns the loot ({stock key: int}); {} when it was looted already or is none.
func mark_looted(id: String, who = null) -> Dictionary:
	var hs = sim.get("houses")
	var cont: Dictionary = hs.container(id) if hs != null else {}
	if cont.is_empty() or looted.has(id):
		return {}
	var loot := {}
	var loot_in = cont.get("loot", {})
	var inv = _inv()
	if inv != null:
		# (INV-CORE: a crew member's abstract search takes what is still in the container, straight to the stores; the window, if it is open on it, closes)
		loot_in = loot_of(id)
		inv.forget(id)
	looted[id] = true
	if typeof(loot_in) == TYPE_DICTIONARY:
		for k in loot_in:
			var n := float(loot_in[k])
			if n > 0.0 and sim.stock.has(k):
				sim.stock[k] = float(sim.stock[k]) + n    # (as `_finish` does)
				loot[String(k)] = int(n)
	var e := {"type": "searched", "container": id, "house": int(cont.get("house", -1)), "loot": loot}
	if who != null:
		e["who"] = String(who.id)
		e["name"] = String(who.first)
	sim.events.append(e)
	return loot


# -------------------------------------------------------------------------- save --

func save() -> Dictionary:
	var ids: Array = looted.keys()
	ids.sort()
	return {"looted": ids}


func load_state(d: Dictionary) -> void:
	start()
	var l = d.get("looted", [])
	if typeof(l) == TYPE_ARRAY:
		for id in l:
			if typeof(id) == TYPE_STRING and String(id) != "":
				looted[String(id)] = true
