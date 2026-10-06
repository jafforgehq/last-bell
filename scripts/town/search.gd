## Searching the containers of the town's houses (One House, WP3, plan 1.14): the avatar stands within REACH of a container's spot, E begins a session of the
## container's `search_s` (4 s; skill-free, the hands off the keys: scripts/town/uses.gd), and when it is done the loot goes STRAIGHT into `sim.stock`
## (no bags: the stash is the stock), the container is looted for good, and `{"type": "searched", "container", "house", "loot": {stock: n}}` is told.
## It is the rules of raid_run.gd's `begin_search`, `_search_step` and `_open` against `sim.houses.containers_of(h)`, which RaidRun's own cannot serve
## in the colony's sim. A looted container is drawn open (WP2 reads `is_looted`). Candidates: kind "container". Saved: the ids that are looted.
extends RefCounted

const REACH := 0.9
const SEARCH_S := 4.0

var sim
var enabled := true
var looted := {}


func setup(s) -> void:
	sim = s


func start() -> void:
	looted = {}


func is_looted(id: String) -> bool:
	return looted.has(id)


## {"looted": bool, "progress": 0 to 1 while the avatar is at it}.
func state(id: String) -> Dictionary:
	var progress := 0.0
	var u = sim.get("uses")
	if u != null and u.in_session("container", id):
		var pr: Dictionary = u.progress()
		progress = clampf(float(pr.t) / maxf(float(pr.of), 0.001), 0.0, 1.0)
	return {"looted": looted.has(id), "progress": progress}


## A container as a Dictionary ({} when `id` is none of the house's): `containers_of` may give the containers or their ids.
func _find(h: int, id: String) -> Dictionary:
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
		return out
	var me := Vector2(p.x, p.y)
	var u = sim.get("uses")
	for c in _list(h):
		var id := String(c.get("id", ""))
		if looted.has(id):
			continue
		var d := me.distance_to(Vector2(c.pos))
		if d > REACH:
			continue
		var stop: bool = u != null and u.in_session("container", id)
		var kind := String(c.get("kind", "container")).replace("_", " ")
		out.append({"kind": "container", "id": id, "label": ("Stop searching" if stop else "Search the %s" % kind), "pos": Vector2(c.pos), "dist": d, "ok": true, "why": "", "session": true})
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
	if cont.is_empty() or looted.has(id):
		return {"ok": false, "line": "", "why": "Nothing to search here", "session": true}
	if Vector2(p.x, p.y).distance_to(Vector2(cont.pos)) > REACH:
		return {"ok": false, "line": "", "why": "Too far from it", "session": true}
	var secs := float(cont.get("search_s", SEARCH_S))
	var kind := String(cont.get("kind", "container")).replace("_", " ")
	var r: Dictionary = u.begin_session("container", id, "Searching", secs, Vector2(cont.pos), REACH + 0.3, Callable(self, "_finish").bind(h, id))
	if not bool(r.get("ok", false)):
		return {"ok": false, "line": "", "why": String(r.get("why", "")), "session": true}
	return {"ok": true, "line": "Searching the %s" % kind, "why": "", "session": true, "seconds": secs}


## The session ran its course: the loot to the stores, the container looted.
func _finish(h: int, id: String) -> void:
	var cont := _find(h, id)
	if cont.is_empty() or looted.has(id):
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


# --------------------------------------------------------------- whoever searches --

## The loot a container holds that is not taken yet, as the stock would get it ({stock key: int}; {} when it is looted, unknown or has nothing). For anyone who searches that is
## not the avatar's session: a crew member (scripts/town/crew_search.gd) asks what is there before they go.
func loot_of(id: String) -> Dictionary:
	var out := {}
	if looted.has(id):
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
