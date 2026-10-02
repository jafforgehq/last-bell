extends "res://tests/case.gd"
## The data behind round 13 (vehicles and fuel): what assets/data/town.json says about the vehicles in the town, the
## fuel to run them and the city across the river that only they can reach, read against assets/data/vehicles.json.
## test_town_data.gd says the town's data is sound place by place; this file says the pieces FIT:
##   - every vehicle a place holds is a kind vehicles.json has, waits in a place that is not known at the start and
##     that a party can walk to, and is not in the near ring;
##   - fuel is found in three places or more, and the town gives enough to drive to the city several times;
##   - every place that `needs_vehicle` can be reached by road (over the bridge, and only over it), cannot be shown by
##     scouting from the town (it is farther than Town.SCOUT_RADIUS from every place of the town), can be shown by a
##     chain of scouting trips from the bridge, and is a road trip that fits a day by car.
## The rules are functions that return the problems they find (so that a doctored copy in memory can prove each of
## them fails when it should); the tests at the end run them on the real data, and one test plays the real town in a
## real game.
##
## THE DISTANCES. The plan wished the farthest city place to be 55 to 65 tiles from the school by road (3 hours by
## car one way). It cannot be: the city has to be farther than SCOUT_RADIUS (20) from the town's east edge (x 90),
## so its nearest place is already about 64 tiles away by road (7.1 hours on foot, 3 hours by sedan), and ten
## places that are six tiles apart or more spread to about 90 (10 hours on foot, 4.2 by sedan). What the data keeps
## is the point of the wish: by sedan a round trip with the search takes under ten hours, so it fits one day
## (the autumn day is twelve and a half hours: dusk at 19, the school left at 6.5 to 7).

const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const Vehicles := preload("res://scripts/sim/vehicles.gd")

const TOWN_PATH := "res://assets/data/town.json"
const VEHICLES_PATH := "res://assets/data/vehicles.json"

## The farthest city place, one way, by sedan (the quickest car): at most this many hours.
const FARTHEST_SEDAN_H := 4.3
## A round trip with the search, to any city place, by sedan, pickup or van: at most this many hours (the bus is
## slower and keeps to the nearer places, or sleeps out).
const DAY_TRIP_H := 11.0
const SEDAN_DAY_TRIP_H := 10.0
## The city is far: walking there would take at least this many hours one way (it is refused on foot anyway).
const FAR_ON_FOOT_H := 6.0
## "Several" trips: the fuel the town can give, at best, covers this many sedan round trips to the farthest place;
## on average (what a raid gives, not the most it can) this many.
const SEVERAL_BEST := 3.0
const SEVERAL_EXPECTED := 2.0
## The vehicles wait at least this far from the school (not in the near ring of 8 to 16 tiles) and one waits this far.
const VEHICLE_MIN_RING := 20.0
const VEHICLE_FAR_ONE := 35.0
## A bridge on foot is an overnight walk: this many hours one way.
const BRIDGE_H_MIN := 4.5
const BRIDGE_H_MAX := 6.0


# ---------------------------------------------------------------------- helpers --

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _town() -> Dictionary:
	var d := _read(TOWN_PATH)
	check(not d.is_empty(), "%s exists and parses as an object" % TOWN_PATH)
	return d


## The vehicle kinds of vehicles.json: id -> {seats, speed, burn, ...}.
func _kinds() -> Dictionary:
	var raw := _read(VEHICLES_PATH)
	check(raw.get("kinds") is Dictionary and not raw.kinds.is_empty(), "%s has its kinds" % VEHICLES_PATH)
	return raw.kinds if raw.get("kinds") is Dictionary else {}


func _vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _places(d: Dictionary) -> Array:
	var out: Array = []
	for p in d.get("places", []):
		if p is Dictionary:
			out.append(p)
	return out


func _by_id(d: Dictionary) -> Dictionary:
	var out := {}
	for p in _places(d):
		out[String(p.get("id", ""))] = p
	return out


func _city(d: Dictionary) -> Array:
	var out: Array = []
	for p in _places(d):
		if bool(p.get("needs_vehicle", false)):
			out.append(p)
	return out


## The places a party can walk to that are not the bridge: the town proper.
func _town_places(d: Dictionary) -> Array:
	var out: Array = []
	for p in _places(d):
		if not bool(p.get("needs_vehicle", false)) and String(p.get("kind", "")) != "bridge":
			out.append(p)
	return out


func _bridge(d: Dictionary) -> Dictionary:
	for p in _places(d):
		if String(p.get("kind", "")) == "bridge":
			return p
	return {}


## Road distances from the school in tiles (a place no road leads to is missing), by Dijkstra over the roads. The roads
## that touch `skip` (a place id) are left out, to ask what can be reached without it.
func _tiles(d: Dictionary, skip: String = "") -> Dictionary:
	var pos := {"home": _vec(d.get("home", [50, 35]))}
	for p in _places(d):
		pos[String(p.get("id", ""))] = _vec(p.pos)
	var edges := {}
	for r in d.get("roads", []):
		if not (r is Array and r.size() == 2 and pos.has(String(r[0])) and pos.has(String(r[1]))):
			continue
		var a := String(r[0])
		var b := String(r[1])
		if skip != "" and (a == skip or b == skip):
			continue
		var len: float = Vector2(pos[a]).distance_to(Vector2(pos[b]))
		edges[a] = edges.get(a, []) + [[b, len]]
		edges[b] = edges.get(b, []) + [[a, len]]
	var dist := {"home": 0.0}
	var done := {}
	while true:
		var cur := ""
		var best := INF
		for k in dist:
			if not done.has(k) and float(dist[k]) < best:
				best = float(dist[k])
				cur = String(k)
		if cur == "":
			break
		done[cur] = true
		for e in edges.get(cur, []):
			var nd: float = best + float(e[1])
			if nd < float(dist.get(e[0], INF)):
				dist[e[0]] = nd
	return dist


## The fuel a place gives as [at best, on average]: the top of its loot and its extra, and the middle of its loot
## and the chance of its extra times the amount.
func _fuel_of(p: Dictionary) -> Array:
	var best := 0.0
	var mean := 0.0
	var loot: Dictionary = p.get("loot", {})
	var extra: Dictionary = p.get("extra", {})
	if loot.has("fuel"):
		best += float(loot.fuel[1])
		mean += (float(loot.fuel[0]) + float(loot.fuel[1])) / 2.0
	if extra.has("fuel"):
		best += float(extra.fuel[1])
		mean += float(extra.fuel[0]) * float(extra.fuel[1])
	return [best, mean]


## The fuel a round trip burns (Vehicles.fuel_for): `burn` for each hour driven, there and back, the road's hours
## over the vehicle's speed.
func _burn(kind: Dictionary, road_hours: float) -> float:
	return float(kind.burn) * 2.0 * road_hours / float(kind.speed)


func _has(problems: Array, text: String) -> bool:
	return "; ".join(problems).contains(text)


# ------------------------------------------------------------------ the rules --

## The vehicles waiting in the town.
func _vehicle_problems(d: Dictionary, kinds: Dictionary) -> Array:
	var out: Array = []
	var home := _vec(d.get("home", [50, 35]))
	var held := {}
	var farthest := 0.0
	for p in _places(d):
		if not p.has("vehicle"):
			continue
		var id := String(p.id)
		var kind := String(p.vehicle)
		if not kinds.has(kind):
			out.append("%s holds a '%s', which vehicles.json does not have" % [id, kind])
		if bool(p.get("known", false)):
			out.append("%s holds a vehicle and is known at the start" % id)
		if bool(p.get("needs_vehicle", false)):
			out.append("%s holds a vehicle in a place that cannot be reached without one" % id)
		if held.has(kind):
			out.append("%s and %s both hold a %s" % [held[kind], id, kind])
		held[kind] = id
		var straight := home.distance_to(_vec(p.pos))
		if straight < VEHICLE_MIN_RING:
			out.append("%s holds a vehicle in the near ring (%.1f tiles from the school, at least %d)" % [id, straight, int(VEHICLE_MIN_RING)])
		farthest = maxf(farthest, straight)
	if held.size() < 3:
		out.append("only %d kinds of vehicle are to be found in the town (at least three)" % held.size())
	if farthest < VEHICLE_FAR_ONE:
		out.append("every vehicle is within %d tiles of the school (one should be farther than %d)" % [int(farthest), int(VEHICLE_FAR_ONE)])
	return out


## The fuel: where it is, and whether the town gives enough to drive to the city several times.
func _fuel_problems(d: Dictionary, kinds: Dictionary) -> Array:
	var out: Array = []
	if not kinds.has("sedan"):
		return ["vehicles.json has no sedan to reckon the fuel by"]
	var best := 0.0
	var mean := 0.0
	var places := 0
	for p in _places(d):
		var f := _fuel_of(p)
		if float(f[0]) <= 0.0:
			continue
		for k in ["loot", "extra"]:
			if p.get(k, {}).has("fuel"):
				var top: float = float(p[k].fuel[1])
				if top > Vehicles.FUEL_CAP:
					out.append("%s gives up to %d fuel in one raid, more than the tank holds (%d)" % [p.id, int(top), int(Vehicles.FUEL_CAP)])
		if not bool(p.get("needs_vehicle", false)):
			places += 1
			best += float(f[0])
			mean += float(f[1])
	if places < 3:
		out.append("fuel is found in %d places of the town (at least three)" % places)
	var tiles := _tiles(d)
	var far := 0.0
	var far_id := ""
	for p in _city(d):
		if tiles.has(String(p.id)) and float(tiles[String(p.id)]) > far:
			far = float(tiles[String(p.id)])
			far_id = String(p.id)
	if far_id == "":
		out.append("there is no city to drive to")
		return out
	var trip := _burn(kinds.sedan, far / Town.SPEED)
	if best < SEVERAL_BEST * trip:
		out.append("the town gives at most %.0f fuel, which is fewer than %d round trips by sedan to %s (%.1f each)" % [best, int(SEVERAL_BEST), far_id, trip])
	if mean < SEVERAL_EXPECTED * trip:
		out.append("the town gives %.0f fuel on average, which is fewer than %d round trips by sedan to %s (%.1f each)" % [mean, int(SEVERAL_EXPECTED), far_id, trip])
	# a full tank covers the farthest trip for any vehicle
	for k in kinds:
		var need := _burn(kinds[k], far / Town.SPEED)
		if need > Vehicles.FUEL_CAP:
			out.append("a %s needs %.0f fuel to go to %s and back, more than the tank holds (%d)" % [k, need, far_id, int(Vehicles.FUEL_CAP)])
	# the depot pays for its own trip
	for p in _city(d):
		var f := _fuel_of(p)
		if float(p.get("loot", {}).get("fuel", [0, 0])[1]) > 0.0 and tiles.has(String(p.id)):
			var cost := _burn(kinds.sedan, float(tiles[String(p.id)]) / Town.SPEED)
			if float(f[1]) < 1.5 * cost:
				out.append("%s gives %.0f fuel and the trip there by sedan burns %.1f: it does not pay for itself" % [p.id, float(f[1]), cost])
	return out


## The city across the river, and the way to it.
func _city_problems(d: Dictionary, kinds: Dictionary) -> Array:
	var out: Array = []
	var city := _city(d)
	var bridge := _bridge(d)
	if city.is_empty():
		return ["there is no city"]
	if bridge.is_empty():
		return ["there is no bridge"]
	var bid := String(bridge.id)
	if bool(bridge.get("known", false)):
		out.append("the bridge is known at the start (scouting the east is what shows it)")
	if bool(bridge.get("needs_vehicle", false)):
		out.append("the bridge needs a vehicle (it is the place a party on foot reaches to find the city)")
	var town := _town_places(d)
	# the bridge is shown by scouting the east: a place of the town is within the radius of it
	var shown_by := ""
	for p in town:
		if _vec(p.pos).distance_to(_vec(bridge.pos)) <= Town.SCOUT_RADIUS:
			shown_by = String(p.id)
	if shown_by == "":
		out.append("no place of the town is within %d tiles of the bridge, so scouting the east does not show it" % int(Town.SCOUT_RADIUS))
	var tiles := _tiles(d)
	var tiles_dry := _tiles(d, bid)
	if not tiles.has(bid):
		out.append("no road leads to the bridge")
	else:
		var h: float = float(tiles[bid]) / Town.SPEED
		if h < BRIDGE_H_MIN or h > BRIDGE_H_MAX:
			out.append("the bridge is %.2f hours away on foot (%.1f to %.1f: an overnight walk)" % [h, BRIDGE_H_MIN, BRIDGE_H_MAX])
	var far := 0.0
	var far_id := ""
	for p in city:
		var id := String(p.id)
		if not tiles.has(id):
			out.append("%s cannot be reached by road from the school" % id)
			continue
		if tiles_dry.has(id):
			out.append("%s can be reached without crossing the bridge" % id)
		for q in town:
			var gap: float = _vec(p.pos).distance_to(_vec(q.pos))
			if gap <= Town.SCOUT_RADIUS:
				out.append("%s is %.1f tiles from %s: scouting there would show it (the radius is %d)" % [id, gap, q.id, int(Town.SCOUT_RADIUS)])
		var hours: float = float(tiles[id]) / Town.SPEED
		if hours < FAR_ON_FOOT_H:
			out.append("%s is only %.1f hours away on foot (the city is at least %d)" % [id, hours, int(FAR_ON_FOOT_H)])
		if hours > far:
			far = hours
			far_id = id
		if bool(p.get("known", false)):
			out.append("%s is known at the start" % id)
	# a chain of scouting trips from the bridge shows the whole city, and not in one
	var shown := {bid: true}
	var frontier: Array = [bridge]
	var rounds := 0
	var first := 0
	while not frontier.is_empty():
		var next: Array = []
		for a in frontier:
			for b in city:
				if not shown.has(String(b.id)) and _vec(a.pos).distance_to(_vec(b.pos)) <= Town.SCOUT_RADIUS:
					shown[String(b.id)] = true
					next.append(b)
		if rounds == 0:
			first = next.size()
		if not next.is_empty():
			rounds += 1
		frontier = next
	for p in city:
		if not shown.has(String(p.id)):
			out.append("%s cannot be found by scouting from the bridge (no place of the city within %d tiles of the bridge or of another that can be found)" % [p.id, int(Town.SCOUT_RADIUS)])
	if rounds < 3:
		out.append("the city is shown in %d rounds of scouting from the bridge (at least three: it should take some finding)" % rounds)
	if first > 4:
		out.append("scouting the bridge alone shows %d city places (at most four)" % first)
	# a road trip by car fits a day
	if far_id != "" and kinds.has("sedan"):
		var sedan: Dictionary = kinds.sedan
		var one_way: float = far / float(sedan.speed)
		if one_way > FARTHEST_SEDAN_H:
			out.append("%s is %.2f hours away by sedan (at most %.1f)" % [far_id, one_way, FARTHEST_SEDAN_H])
		for k in kinds:
			var trip: float = 2.0 * far / float(kinds[k].speed) + Town.SEARCH_H
			var limit := SEDAN_DAY_TRIP_H if k == "sedan" else DAY_TRIP_H
			if k != "bus" and trip > limit:
				out.append("a trip to %s by %s takes %.1f hours with the search (at most %.1f)" % [far_id, k, trip, limit])
	return out


# -------------------------------------------------------------- the real data --

func test_every_vehicle_named_exists_and_waits_where_it_makes_sense() -> void:
	var d := _town()
	var kinds := _kinds()
	if d.is_empty() or kinds.is_empty():
		return
	var problems := _vehicle_problems(d, kinds)
	eq(problems, [], "the vehicles: %s" % "; ".join(problems))
	var by := _by_id(d)
	# the plan's four, where they were put
	for pair in [["garage", "pickup"], ["bus_depot", "bus"], ["gas_station", "sedan"], ["supermarket", "van"]]:
		check(by.has(pair[0]) and String(by[pair[0]].get("vehicle", "")) == pair[1], "%s holds a %s" % [pair[0], pair[1]])
	for k in kinds:
		var n := 0
		for p in _places(d):
			if String(p.get("vehicle", "")) == String(k):
				n += 1
		eq(n, 1, "one place holds the %s" % k)


func test_fuel_is_found_in_three_places_and_enough_to_drive_to_the_city_several_times() -> void:
	var d := _town()
	var kinds := _kinds()
	if d.is_empty() or kinds.is_empty():
		return
	var problems := _fuel_problems(d, kinds)
	eq(problems, [], "the fuel: %s" % "; ".join(problems))
	var by := _by_id(d)
	for id in ["gas_station", "truck_stop", "garage", "fuel_depot"]:
		check(by.has(id) and _fuel_of(by[id])[0] > 0.0, "%s has fuel" % id)
	check(float(by.truck_stop.loot.fuel[0]) == 25.0 and float(by.truck_stop.loot.fuel[1]) == 40.0, "the truck stop gives 25 to 40")
	check(float(by.gas_station.loot.fuel[0]) == 20.0 and float(by.gas_station.loot.fuel[1]) == 35.0, "the crossing fuel stop gives 20 to 35")
	check(by.garage.extra.has("fuel") and float(by.garage.extra.fuel[1]) <= 10.0, "the garage has a little")
	check(float(by.fuel_depot.loot.fuel[0]) == 40.0 and float(by.fuel_depot.loot.fuel[1]) == 70.0, "the fuel depot gives 40 to 70")
	# none of the near ring has any: the first fuel is found, not handed out
	for p in _places(d):
		if bool(p.get("known", false)):
			check(_fuel_of(p)[0] == 0.0, "%s is known at the start and has no fuel: the first tank is a find" % p.id)


func test_the_city_is_reached_over_the_bridge_and_found_from_it() -> void:
	var d := _town()
	var kinds := _kinds()
	if d.is_empty() or kinds.is_empty():
		return
	var problems := _city_problems(d, kinds)
	eq(problems, [], "the city: %s" % "; ".join(problems))
	var tiles := _tiles(d)
	var n := 0
	for p in _city(d):
		n += 1
		check(tiles.has(String(p.id)), "%s has a road" % p.id)
	eq(n, 10, "ten places need a vehicle")
	# what the numbers come to, for the record: the nearest and the farthest city place by sedan
	var lo := INF
	var hi := 0.0
	for p in _city(d):
		var h: float = float(tiles[String(p.id)]) / Town.SPEED / float(kinds.sedan.speed)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	check(lo >= 2.5 and hi <= FARTHEST_SEDAN_H, "the city is %.2f to %.2f hours away by sedan, one way" % [lo, hi])


## The real module against the real data: the same answers the rules above work out by hand.
func test_the_real_town_in_a_real_game() -> void:
	var d := _town()
	if d.is_empty():
		return
	var g := Helpers.make(5, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	sim.minutes = 7.0 * 60.0
	sim.clock_min = 2.0 * 1440.0 + 7.0 * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.supplies.sources_day = 3
	sim.events.clear()
	check(sim.town.on, "a settlement game")
	var city_ids: Array = []
	for p in _city(d):
		city_ids.append(String(p.id))
	# nothing of the city is known, nor the bridge; the vehicles' places are not known
	for id in city_ids:
		eq(String(sim.town.state_of(id)), "unknown", "%s is hidden at the start" % id)
	eq(String(sim.town.state_of("river_bridge")), "unknown", "the bridge is hidden")
	for p in _places(d):
		if p.has("vehicle"):
			eq(String(sim.town.state_of(String(p.id))), "unknown", "%s, with a vehicle in it, is hidden" % p.id)
	# scouting every place of the town (what a scouting party does) shows the bridge and nothing of the city
	for p in _town_places(d):
		sim.town.reveal_around(String(p.id), Town.SCOUT_RADIUS)
	eq(String(sim.town.state_of("river_bridge")), "known", "scouting the east shows the bridge")
	for id in city_ids:
		eq(String(sim.town.state_of(id)), "unknown", "scouting the town does not show %s" % id)
	# the bridge shows the first of the city, and a chain of trips the rest
	var shown: Array = sim.town.reveal_around("river_bridge", Town.SCOUT_RADIUS)
	check(shown.size() >= 1 and shown.size() <= 4, "scouting the bridge shows a few places of the city: %s" % str(shown))
	var rounds := 1
	var changed := true
	while changed and rounds < 12:
		changed = false
		for id in city_ids:
			if String(sim.town.state_of(id)) != "unknown":
				var more: Array = sim.town.reveal_around(id, Town.SCOUT_RADIUS)
				if not more.is_empty():
					changed = true
		rounds += 1
	for id in city_ids:
		check(String(sim.town.state_of(id)) != "unknown", "%s was found by scouting from the bridge" % id)
	# on foot the city is refused; by sedan it is open, with the fuel
	var crew: Array = []
	for p in sim.people:
		if crew.size() < 2:
			crew.append(p)
	for id in city_ids:
		eq(String(sim.scavenge.why_not_action(crew, id, "loot")), "Too far to go on foot: take a vehicle.", "%s on foot" % id)
	var sedan: Dictionary = sim.vehicles.add("sedan")
	var pickup: Dictionary = sim.vehicles.add("pickup")
	var van: Dictionary = sim.vehicles.add("van")
	var bus: Dictionary = sim.vehicles.add("bus")
	sim.vehicles.fuel = Vehicles.FUEL_CAP
	var worst := 0.0
	for id in city_ids:
		for v in [sedan, pickup, van, bus]:
			var why: String = sim.scavenge.why_not_action(crew, id, "loot", String(v.id))
			eq(why, "", "%s by %s with a full tank: %s" % [id, v.kind, why])
		worst = maxf(worst, float(sim.scavenge.action_hours(id, "loot", String(sedan.id))))
	check(worst <= SEDAN_DAY_TRIP_H, "the longest trip by sedan, with the search, is %.1f hours: it fits a day" % worst)
	# and a trip by sedan to the hospital is due when the hours say
	var fuel_before: float = sim.vehicles.fuel
	check(sim.scavenge.send(crew, "hospital", "loot", String(sedan.id)), "the sedan goes to the hospital")
	var party: Dictionary = sim.scavenge.parties[0]
	var due: float = float(party.return_at) - float(party.depart)
	var hours_by_data: float = sim.scavenge.action_hours("hospital", "loot", String(sedan.id)) * 60.0
	check(due >= hours_by_data - 1.5 and due <= hours_by_data + 4.0 * 60.0 + 1.5, "it is due by the hours the data gives, and no more than the road's delays later: %.0f against %.0f minutes" % [due, hours_by_data])
	check(sim.vehicles.fuel < fuel_before - 10.0, "and the fuel is burnt: %.1f of %.1f left" % [sim.vehicles.fuel, fuel_before])
	g.world.free()


# ----------------------------------------------- the rules can fail: doctored copies --

func _copy(d: Dictionary) -> Dictionary:
	return d.duplicate(true)


func _p(d: Dictionary, id: String) -> Dictionary:
	return _by_id(d).get(id, {})


func test_a_vehicle_that_does_not_exist_or_waits_in_the_wrong_place_is_found() -> void:
	var d := _town()
	var kinds := _kinds()
	if d.is_empty() or kinds.is_empty():
		return
	eq(_vehicle_problems(d, kinds), [], "the real data first")
	var c := _copy(d)
	_p(c, "garage").vehicle = "tractor"
	check(_has(_vehicle_problems(c, kinds), "'tractor', which vehicles.json does not have"), "a vehicle that does not exist is found")
	c = _copy(d)
	_p(c, "garage").known = true
	check(_has(_vehicle_problems(c, kinds), "garage holds a vehicle and is known at the start"), "a vehicle in a known place is found")
	c = _copy(d)
	_p(c, "hospital").vehicle = "van"
	var text := "; ".join(_vehicle_problems(c, kinds))
	check(text.contains("hospital holds a vehicle in a place that cannot be reached without one"), "a vehicle in the city is found: %s" % text)
	check(text.contains("both hold a van"), "two places holding the same kind are found: %s" % text)
	c = _copy(d)
	_p(c, "houses").vehicle = "sedan"
	text = "; ".join(_vehicle_problems(c, kinds))
	check(text.contains("houses holds a vehicle in the near ring"), "a vehicle in the near ring is found: %s" % text)
	check(text.contains("houses holds a vehicle and is known at the start"), "(and it is a known place)")
	c = _copy(d)
	_p(c, "garage").erase("vehicle")
	_p(c, "supermarket").erase("vehicle")
	check(_has(_vehicle_problems(c, kinds), "only 2 kinds of vehicle"), "too few kinds are found")
	c = _copy(d)
	_p(c, "bus_depot").erase("vehicle")
	_p(c, "supermarket").erase("vehicle")
	_p(c, "garage").pos = [30, 40]
	check(_has(_vehicle_problems(c, kinds), "every vehicle is within"), "vehicles all in the near part of the town are found")


func test_fuel_that_is_scarce_or_too_much_is_found() -> void:
	var d := _town()
	var kinds := _kinds()
	if d.is_empty() or kinds.is_empty():
		return
	eq(_fuel_problems(d, kinds), [], "the real data first")
	# fuel only in two places of the town
	var c := _copy(d)
	_p(c, "garage").extra.erase("fuel")
	_p(c, "bus_depot").extra.erase("fuel")
	check(_has(_fuel_problems(c, kinds), "fuel is found in 2 places of the town"), "fuel in two places is found")
	# fuel that does not add up to several trips
	c = _copy(d)
	_p(c, "gas_station").loot.fuel = [4, 8]
	_p(c, "truck_stop").loot.fuel = [4, 8]
	var text := "; ".join(_fuel_problems(c, kinds))
	check(text.contains("fewer than 3 round trips") and text.contains("fewer than 2 round trips"), "too little fuel is found: %s" % text)
	# no fuel at all
	c = _copy(d)
	for p in _places(c):
		p.loot.erase("fuel")
		p.extra.erase("fuel")
	text = "; ".join(_fuel_problems(c, kinds))
	check(text.contains("fuel is found in 0 places"), "no fuel is found: %s" % text)
	# a raid that gives more than the tank holds
	c = _copy(d)
	_p(c, "fuel_depot").loot.fuel = [60, 120]
	check(_has(_fuel_problems(c, kinds), "more than the tank holds (80)"), "a raid that overflows the tank is found")
	# a depot that does not pay for the trip
	c = _copy(d)
	_p(c, "fuel_depot").loot.fuel = [8, 12]
	check(_has(_fuel_problems(c, kinds), "does not pay for itself"), "a depot that costs more than it gives is found")
	# a vehicle that cannot make the trip on a full tank
	var heavy := kinds.duplicate(true)
	heavy.bus.burn = 20.0
	check(_has(_fuel_problems(d, heavy), "a bus needs"), "a vehicle that burns more than a tank holds is found")


func test_a_city_that_can_be_scouted_from_the_town_or_not_reached_or_not_found_is_caught() -> void:
	var d := _town()
	var kinds := _kinds()
	if d.is_empty() or kinds.is_empty():
		return
	eq(_city_problems(d, kinds), [], "the real data first")
	# a city place near enough to a town place for scouting there to show it
	var c := _copy(d)
	_p(c, "checkpoint").pos = [105, 36]
	var text := "; ".join(_city_problems(c, kinds))
	check(text.contains("checkpoint is") and text.contains("scouting there would show it"), "a city place within the radius of the town is found: %s" % text)
	# no road to a city place
	c = _copy(d)
	var kept: Array = []
	for r in c.roads:
		if String(r[0]) != "rail_yard" and String(r[1]) != "rail_yard":
			kept.append(r)
	c.roads = kept
	check(_has(_city_problems(c, kinds), "rail_yard cannot be reached by road from the school"), "a place with no road is found")
	# a road that goes round the bridge
	c = _copy(d)
	c.roads.append(["estate", "hospital"])
	check(_has(_city_problems(c, kinds), "hospital can be reached without crossing the bridge"), "a road round the bridge is found")
	# a city place that scouting from the bridge cannot find (too far from the rest)
	c = _copy(d)
	_p(c, "rail_yard").pos = [155, 66]
	text = "; ".join(_city_problems(c, kinds))
	check(text.contains("rail_yard cannot be found by scouting from the bridge"), "a place out of the chain's reach is found: %s" % text)
	# the whole city within one scouting trip of the bridge
	c = _copy(d)
	var i := 0
	for p in _city(c):
		p.pos = [100 + 6 * (i % 3), 30 + 6 * floori(float(i) / 3.0)]
		i += 1
	text = "; ".join(_city_problems(c, kinds))
	check(text.contains("scouting the bridge alone shows") or text.contains("rounds of scouting"), "a city found in one trip is found: %s" % text)
	# too far: the farthest city place is beyond a day by car
	c = _copy(d)
	_p(c, "rail_yard").pos = [150, 62]
	_p(c, "fuel_depot").pos = [150, 20]
	text = "; ".join(_city_problems(c, kinds))
	check(text.contains("by sedan (at most") or text.contains("with the search (at most"), "a city too far for a day is found: %s" % text)
	# a city place that is a short walk from the school
	c = _copy(d)
	_p(c, "flats").pos = [101, 40]
	check(_has(_city_problems(c, kinds), "flats is only"), "a city place that is a short walk away is found")
	# a road that makes a city place reachable without the bridge
	c = _copy(d)
	c.roads.append(["bus_depot", "checkpoint"])
	c.roads.append(["home", "checkpoint"])
	text = "; ".join(_city_problems(c, kinds))
	check(text.contains("checkpoint can be reached without crossing the bridge"), "a road that makes the city reachable round the bridge is found: %s" % text)
	# the bridge known at the start; the bridge that needs a vehicle; no bridge
	c = _copy(d)
	_p(c, "river_bridge").known = true
	check(_has(_city_problems(c, kinds), "the bridge is known at the start"), "a known bridge is found")
	c = _copy(d)
	_p(c, "river_bridge").needs_vehicle = true
	check(_has(_city_problems(c, kinds), "the bridge needs a vehicle"), "a bridge that needs a vehicle is found")
	c = _copy(d)
	_p(c, "river_bridge").kind = "houses"
	check(_has(_city_problems(c, kinds), "there is no bridge"), "no bridge is found")
	# the bridge too far from the town to be shown by scouting the east
	c = _copy(d)
	_p(c, "river_bridge").pos = [112, 38]
	check(_has(_city_problems(c, kinds), "scouting the east does not show it"), "a bridge that the town's scouting cannot reach is found")
	# a city place known at the start
	c = _copy(d)
	_p(c, "hospital").known = true
	check(_has(_city_problems(c, kinds), "hospital is known at the start"), "a known city place is found")
	# the bridge on foot is not an overnight walk: too near, or too far
	c = _copy(d)
	_p(c, "river_bridge").pos = [80, 30]
	c.roads.append(["home", "river_bridge"])
	check(_has(_city_problems(c, kinds), "hours away on foot (4.5 to 6.0"), "a bridge that is too near on foot is found")
	c = _copy(d)
	_p(c, "river_bridge").pos = [99, 60]
	check(_has(_city_problems(c, kinds), "hours away on foot (4.5 to 6.0"), "a bridge that is too far on foot is found")
