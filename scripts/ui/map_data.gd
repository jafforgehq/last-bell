## The Map page's data (round 18, V2.4): what the paper map (town_map.gd) is given, and the small words and sums the page
## shares with it. These are COPIES of the Town Board's own `_refresh_map`, `_party_markers` and `route_to`
## (scripts/ui/town_board.gd keeps its own: the modal page serves the old game and the tests and is not touched), made static so
## that the page, the tests and anything else can ask a sim for the picture without a board.
##
##   MapData.build(sim, chosen_id, departures := {}, routes := {}) -> Dictionary   # what `TownMap.set_data` takes
##   MapData.route_to(sim, id, routes := {}) -> Array                               # the way a party takes from the school
##   MapData.party_markers(sim, departures, routes := {}) -> Array                  # the parties out, as the map draws them
##
## `departures` is the page's memory of when each party set off (party number to the game clock): the rules do not keep the
## hour, so the page keeps it, from the moment it first sees a party go (it is filled in here). `routes` is a cache of the
## routes (place id to its points): a page that lives long keeps one; without it every call works the routes out again.
extends RefCounted

const Map := preload("res://scripts/ui/town_map.gd")

## The hours of the day a party can set off (the rules' own), and the hour the day ends (dusk).
const FIRST_LIGHT_H := 6.5
const LEAVE_BY_H := 10.0
## The words for a place's danger (0 to 3).
const DANGER_WORDS := ["Quiet", "A few of the dead about", "The dead are thick here", "Overrun"]
## What a place may give, in the order its chips are shown: the stocks, and the fuel of round 13.
const LOOT_ORDER := ["food", "water", "scrap", "ammo", "meds", "fuel"]
const LOOT_NAME := {"food": "Food", "water": "Water", "scrap": "Scrap", "ammo": "Ammo", "meds": "Medicine", "fuel": "Fuel"}
## The order the outpost's yield is spoken in.
const YIELD_ORDER := ["food", "water", "scrap", "ammo", "meds", "fuel"]


# ------------------------------------------------------------------------ the map --

## The picture of the town for `TownMap.set_data`: {"board", "home", "places" (the known ones, with their marks), "roads" (the known
## ones inked, a faint stub from a known place to one that is not), "unknown" (where the "?" go), "streets", "parties" (the
## markers of the parties that are out), "chosen"}.
static func build(sim, chosen_id: String, departures: Dictionary = {}, routes: Dictionary = {}) -> Dictionary:
	var town = sim.town
	var shown: Array = []
	var unknown: Array = []
	var by_id := {}
	for e in town.all_places():
		var id := String(e.id)
		by_id[id] = e
		if String(e.state) == "unknown":
			unknown.append({"id": id, "pos": unknown_spot(e)})
		else:
			e["survivor"] = bool(e.get("survivor", false)) and not bool(e.get("rescued", false))
			shown.append(e)
	var roads: Array = []
	var streets: Array = []
	for r in town.roads:
		if not (r is Array) or r.size() < 2:
			continue
		var a := String(r[0])
		var b := String(r[1])
		var pa: Vector2 = town.home if a == "home" else Vector2(by_id[a].pos) if by_id.has(a) else Vector2.INF
		var pb: Vector2 = town.home if b == "home" else Vector2(by_id[b].pos) if by_id.has(b) else Vector2.INF
		if pa == Vector2.INF or pb == Vector2.INF:
			continue
		streets.append([pa, pb])
		var ka: bool = a == "home" or String(by_id[a].state) != "unknown"
		var kb: bool = b == "home" or String(by_id[b].state) != "unknown"
		if ka and kb:
			roads.append({"a": pa, "b": pb, "stub": false})
		elif ka:
			roads.append({"a": pa, "b": pa.lerp(pb, 0.42), "stub": true})
		elif kb:
			roads.append({"a": pb, "b": pb.lerp(pa, 0.42), "stub": true})
	return {
		"board": Vector2(float(town.board.w), float(town.board.h)), "home": town.home, "places": shown, "roads": roads,
		"unknown": unknown, "streets": streets, "parties": party_markers(sim, departures, routes), "chosen": chosen_id,
	}


## Where the "?" of a place that is not known goes: near it, not on it (a few tiles off, the same each time).
static func unknown_spot(e: Dictionary) -> Vector2:
	var h: int = String(e.id).hash()
	var dx := float((h % 9) - 4) / 4.0 * Map.UNKNOWN_SHIFT
	var dy := float(((h / 9) % 9) - 4) / 4.0 * Map.UNKNOWN_SHIFT
	return Vector2(e.pos) + Vector2(dx, dy)


## The parties out as the map draws them: the route from the school, how far along it they are, and which way.
static func party_markers(sim, departures: Dictionary, routes: Dictionary = {}) -> Array:
	var town = sim.town
	var scav = sim.scavenge
	var out: Array = []
	for party_out in scav.parties:
		var id := String(party_out.site)
		if town.place(id).is_empty():
			continue
		var action := String(party_out.get("action", "loot"))
		var ride := String(party_out.get("vehicle", ""))
		var trip_h: float = maxf(scav.action_hours(id, action, ride), 0.01)
		var one_way: float = (sim.vehicles.drive_hours(id, ride) / 2.0) if ride != "" else town.hours_to(id)
		var search := maxf(0.0, trip_h - 2.0 * one_way)
		# how much of the trip is gone: from when they set off (the rules do not keep the hour: the page does, from
		# the moment it sees them go; a party seen first later is taken to have set off one trip's time before it is due,
		# which is a little early if the road held them up) to when they are due
		var n := int(party_out.n)
		var depart: float
		if party_out.has("depart"):
			depart = float(party_out.depart)
		elif departures.has(n):
			depart = float(departures[n])
		elif String(party_out.state) == "out" or String(party_out.state) == "driving_out":
			depart = float(sim.clock_min)    # still walking to the gate (or driving out): they have only just been sent
		else:
			depart = float(party_out.return_at) - trip_h * 60.0
		departures[n] = depart
		var span := maxf(float(party_out.return_at) - depart, 1.0)
		var share := clampf((float(sim.clock_min) - depart) / span, 0.0, 1.0)
		var there := one_way / trip_h
		var searched := (one_way + search) / trip_h
		var at := 0.0
		var mode := "out"
		if String(party_out.state) == "out" or String(party_out.state) == "driving_out":
			at = 0.0    # (the car's drive out is not on the map: the trip's hours start when it has left)
		elif share < there:
			at = share / maxf(there, 0.0001)
		elif share < searched:
			at = 1.0
			mode = "search"
		else:
			at = 1.0 - (share - searched) / maxf(1.0 - searched, 0.0001)
			mode = "back"
		out.append({"n": int(party_out.n), "count": party_out.members.size(), "path": route_to(sim, id, routes), "at": clampf(at, 0.0, 1.0), "mode": mode, "vehicle": String(sim.vehicles.kind_of(ride).get("name", "")) if ride != "" else ""})
	return out


## The way a party takes from the school to a place: the roads of the board (the shortest by length), as points in
## board tiles; a straight line if the place has no road. `routes` (optional) is a cache the caller keeps.
static func route_to(sim, id: String, routes: Dictionary = {}) -> Array:
	if routes.has(id):
		return routes[id]
	var town = sim.town
	var pos := {"home": town.home}
	for p in town.places:
		pos[String(p.id)] = Vector2(p.pos)
	var edges := {}
	for r in town.roads:
		if r is Array and r.size() >= 2 and pos.has(String(r[0])) and pos.has(String(r[1])):
			var a := String(r[0])
			var b := String(r[1])
			var len := Vector2(pos[a]).distance_to(pos[b])
			edges[a] = edges.get(a, []) + [[b, len]]
			edges[b] = edges.get(b, []) + [[a, len]]
	var dist := {"home": 0.0}
	var prev := {}
	var open: Array = ["home"]
	while not open.is_empty():
		open.sort_custom(func(x, y): return float(dist[x]) < float(dist[y]))
		var cur: String = open.pop_front()
		for e in edges.get(cur, []):
			var nd: float = float(dist[cur]) + float(e[1])
			if not dist.has(e[0]) or nd < float(dist[e[0]]) - 1.0e-9:
				dist[e[0]] = nd
				prev[e[0]] = cur
				if not open.has(e[0]):
					open.append(e[0])
	var path: Array = []
	if pos.has(id):
		if prev.has(id):
			var at := id
			while at != "home":
				path.push_front(Vector2(pos[at]))
				at = String(prev[at])
			path.push_front(town.home)
		else:
			path = [town.home, Vector2(pos[id])]
	routes[id] = path
	return path


# ------------------------------------------------------------------ the words --

## "Walt", "Walt and Hector", "Walt, Hector and Dez".
static func join(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


## The first names of Person objects, joined.
static func names(people: Array) -> String:
	var list: Array = []
	for p in people:
		list.append(String(p.first))
	return join(list)


## "14:30": an hour of the day, to the nearest quarter of an hour.
static func clock_text(hour: float) -> String:
	var q := roundi(fposmod(hour, 24.0) * 4.0)
	return "%02d:%02d" % [(q / 4) % 24, (q % 4) * 15]


## "8-14" or "8": what a place may give of one stock.
static func range_text(r) -> String:
	if r is Array and r.size() >= 2:
		var lo := int(r[0])
		var hi := int(r[1])
		return "%d" % lo if lo == hi else "%d–%d" % [lo, hi]
	return str(r)


## "4 food and 2 water", "0.8 medicine": what an outpost yields.
static func yield_text(y) -> String:
	var parts: Array = []
	if y is Dictionary:
		for k in YIELD_ORDER:
			if y.has(k):
				var n := float(y[k])
				var count := str(roundi(n)) if absf(n - roundf(n)) < 0.05 else "%.1f" % n
				parts.append("%s %s" % [count, String(LOOT_NAME.get(k, k)).to_lower()])
	if parts.is_empty():
		return "nothing"
	return join(parts)


## "7" or "7.5": a number of fuel.
static func num(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")


## When a party out is due, in words: "back about 14:30", "back tomorrow", "back in 2 days". (A party comes in by day: one that is
## due after dusk is in at first light.)
static func due_text(sim, party_out: Dictionary) -> String:
	if party_out.is_empty():
		return ""
	var due_abs := float(party_out.return_at) + 420.0
	var due_day := floori(due_abs / 1440.0)
	var due_h := fposmod(due_abs / 60.0, 24.0)
	var now_day := floori((float(sim.clock_min) + 420.0) / 1440.0)
	var arrives := due_day + (1 if due_h >= float(sim.seasons.dusk_hour()) else 0)
	var days := arrives - now_day
	if days <= 0:
		return "back about %s" % clock_text(maxf(due_h, FIRST_LIGHT_H))
	if days == 1:
		return "back tomorrow"
	return "back in %d days" % days


## The day a place is picked over until, from the rules' own note ("Picked over. Ready again on day 5."): 0 when it is not.
static func picked_over_until(note: String) -> int:
	if not note.begins_with("Picked over"):
		return 0
	var rx := RegEx.new()
	rx.compile("day (\\d+)")
	var m := rx.search(note)
	return int(m.get_string(1)) if m != null else 0


## What each way to go says for the place that is chosen: [{"id" ("" on foot), "name", "l2", "l3", "warn", "tip"}]. The fuel and the hours
## are those of the trip to the place `s` (a site of `scavenge.available_sites`, or {} with none chosen: then the vehicle's burn is
## told); `going` is how many people would ride (a vehicle that seats fewer is a warning).
static func ride_entries(sim, s: Dictionary, going: int, action: String = "loot") -> Array:
	var scav = sim.scavenge
	var site_id := String(s.get("id", ""))
	var has := not s.is_empty()
	var far: bool = has and bool(s.get("needs_vehicle", false))
	var out: Array = []
	var foot := {"id": "", "name": "On foot", "l2": "Up to %d people" % int(scav.MAX_PARTY_TOWN), "l3": "", "warn": far,
		"tip": "On foot: up to %d people, the road at a walking pace, no fuel." % int(scav.MAX_PARTY_TOWN)}
	if far:
		foot.l3 = "Too far to walk"
	elif has:
		foot.l3 = Map.hours_text(scav.action_hours(site_id, action, ""))
	out.append(foot)
	for v in sim.vehicles.parked():
		var k: Dictionary = sim.vehicles.kind_of(String(v.id))
		var l2 := "%d seats" % int(k.seats)
		var l3 := ""
		var warn := false
		if has:
			var need: float = sim.vehicles.fuel_for(site_id, String(v.id))
			l2 += ", fuel %s" % num(need)
			l3 = Map.hours_text(scav.action_hours(site_id, action, String(v.id)))
			warn = float(sim.vehicles.fuel) + 1.0e-9 < need
		else:
			l3 = "burns %s an hour" % num(float(k.burn))
		if going > int(k.seats):
			warn = true
		var worn := int(roundf(100.0 * float(v.hp) / maxf(float(k.hp), 1.0)))
		out.append({"id": String(v.id), "name": String(k.name), "l2": l2, "l3": l3, "warn": warn,
			"tip": "%s: %d seats, %s times a walker's pace, burns %s fuel an hour, brings back %s times the loot. Condition %d%%." % [String(k.name), int(k.seats), num(float(k.speed)), num(float(k.burn)), num(float(k.cargo)), worn]})
	return out
