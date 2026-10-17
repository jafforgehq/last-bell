extends "res://tests/case.gd"
## The town's data (round 8): assets/data/town.json, the board the settlement game plans on. These tests
## say the data is sound, not what the module does with it (test_town.gd): the places and their kinds,
## the map (positions, roads, the road distances in hours), the loot against distance and danger, the
## nests towards the spawn points, the survivors, the outposts, and the beats a trip can meet. The
## road distances are worked out here with a small Dijkstra of the test's own, and one test at the end
## checks that the real module (`sim.town`) agrees with it.
##
## ROUND 13 widened the board to 160 by 70 and put a CITY across the river on its east side: ten places that
## `needs_vehicle` (a party cannot walk there), a bridge (a place that can be walked to, with nothing in it, that
## scouting the east shows), and a few vehicles and fuel in the town. The tests of the town's own shape (its ring,
## its hours, its nests, its survivors) are about the GROUND (`_ground`: the places a party can walk to, and the
## roads between them); the city has tests of its own near the end, and the rules that join the two (that the
## city can only be found from the bridge, that there is fuel to get there) are test_vehicles_data.gd's.

const Helpers := preload("res://tests/helpers.gd")

const PATH := "res://assets/data/town.json"
const MAP_PATH := "res://assets/data/map.json"
const SITES_PATH := "res://assets/data/sites.json"

const KINDS := ["houses", "pharmacy", "hardware", "scrapyard", "church", "farm", "clinic", "police", "fire_station",
	"garage", "bakery", "warehouse", "bus_depot", "radio_shop", "bunker", "supermarket", "school_annex", "water_works",
	"gas_station", "library", "bridge"]
## The kinds the city adds (the mall is a "supermarket", the police headquarters "police", the flats "houses": the
## board already has icons for those). The Town Board's map has an icon for "hospital" and "fuel_depot" (a cross and
## a pump); the others are drawn as a plain pin until the view gives them one.
const CITY_KINDS := ["hospital", "university", "rail_yard", "power_station", "cold_store", "checkpoint", "fuel_depot"]
## What a place's loot and extras may be made of: the five stores and fuel (round 13: it goes to the vehicles' tank).
const STOCKS := ["food", "water", "scrap", "ammo", "meds", "fuel"]
## What an outpost may yield (fuel is not a store: the dawn would pay it into the stocks).
const STORES := ["food", "water", "scrap", "ammo", "meds"]
const OLD_IDS := ["pharmacy", "hardware", "houses", "scrapyard"]
const PLACE_KEYS := ["id", "name", "where", "kind", "pos", "blurb", "danger", "loot", "extra", "needs_vehicle", "vehicle",
	"known", "nest", "survivor", "outpost", "image"]
const BEAT_KEYS := ["id", "text", "weight", "min_hours", "effects"]
const EFFECT_KEYS := ["loot_pct", "hurt", "delay_h", "reveal", "morale", "lost"]
## Tiles of the board a party walks in an hour (Town.SPEED; the last test checks the module agrees).
const SPEED := 9.0
## What a unit of each stock is worth, for comparing one place's loot with another's.
## Fuel is worth half a meal a unit: it is not eaten, it is only the means of going farther.
const VALUE := {"food": 1.0, "water": 1.0, "scrap": 1.0, "ammo": 0.25, "meds": 4.0, "fuel": 0.5}
## The most a place of the town may give at its best (the top of its loot plus its extras).
const CAPS := {"scrap": 60.0, "ammo": 140.0, "food": 40.0, "water": 40.0, "meds": 15.0, "fuel": 45.0}
## The city is richer, so its caps are higher where the data says so: a hospital holds a hundred times what a
## cupboard does (meds up to 40, not 15); the police headquarters is an armoury (ammo up to 160); a rail yard is
## all steel (scrap up to 70); the fuel depot is the one place that fills a tank (fuel up to 70, and a tank holds 80).
const CITY_CAPS := {"scrap": 70.0, "ammo": 160.0, "food": 45.0, "water": 40.0, "meds": 40.0, "fuel": 70.0}
## The point the spawn points are seen from, as in Town.heading_of.
const SPAWN_CENTRE := Vector2(42.0, 32.0)

## The file under test (a check of these tests themselves points it at a doctored copy).
var data_path := PATH


# ---------------------------------------------------------------------- helpers --

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The town's data, or {} (and a failure) when the file is missing or does not parse.
func _town() -> Dictionary:
	var d := _read(data_path)
	check(not d.is_empty(), "%s exists and parses as an object" % data_path)
	return d


func _vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _is_whole(x) -> bool:
	return (typeof(x) == TYPE_FLOAT or typeof(x) == TYPE_INT) and float(x) == floorf(float(x))


func _is_number(x) -> bool:
	return typeof(x) == TYPE_FLOAT or typeof(x) == TYPE_INT


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


func _home(d: Dictionary) -> Vector2:
	return _vec(d.get("home", [50, 35]))


func _needs_vehicle(p: Dictionary) -> bool:
	return bool(p.get("needs_vehicle", false))


## The places of the city across the river (the ones a party cannot walk to).
func _city_places(d: Dictionary) -> Array:
	var out: Array = []
	for p in _places(d):
		if _needs_vehicle(p):
			out.append(p)
	return out


## The data as a party on foot sees it: the places that can be walked to (the town, and the bridge) and the roads
## between them. The tests of the town's own shape are about this.
func _ground(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return d
	var keep := {"home": true}
	var places: Array = []
	for p in _places(d):
		if not _needs_vehicle(p):
			places.append(p)
			keep[String(p.get("id", ""))] = true
	var roads: Array = []
	for r in d.get("roads", []):
		if r is Array and r.size() == 2 and keep.has(String(r[0])) and keep.has(String(r[1])):
			roads.append(r)
	var out := d.duplicate(true)
	out["places"] = places
	out["roads"] = roads
	return out


## Road distances from the school in tiles, by Dijkstra over the roads (a place with no road is missing).
func _tile_distances(d: Dictionary) -> Dictionary:
	var pos := {"home": _home(d)}
	for p in _places(d):
		pos[String(p.get("id", ""))] = _vec(p.pos)
	var edges := {}
	for r in d.get("roads", []):
		if r is Array and r.size() == 2 and pos.has(String(r[0])) and pos.has(String(r[1])):
			var a := String(r[0])
			var b := String(r[1])
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


## Hours one way to each place (INF when no road leads there).
func _hours(d: Dictionary) -> Dictionary:
	var dist := _tile_distances(d)
	var out := {}
	for p in _places(d):
		var id := String(p.get("id", ""))
		out[id] = float(dist[id]) / SPEED if dist.has(id) else INF
	return out


func _straight(d: Dictionary, p: Dictionary) -> float:
	return _home(d).distance_to(_vec(p.pos))


## The place ids nearest the school first, by the straight line.
func _nearest_first(d: Dictionary) -> Array:
	var rows: Array = []
	for p in _places(d):
		rows.append([_straight(d, p), String(p.id)])
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for r in rows:
		out.append(r[1])
	return out


func _value(p: Dictionary) -> float:
	var v := 0.0
	var loot: Dictionary = p.get("loot", {})
	for k in loot:
		v += float(VALUE.get(k, 0.0)) * (float(loot[k][0]) + float(loot[k][1])) / 2.0
	var extra: Dictionary = p.get("extra", {})
	for k in extra:
		v += float(VALUE.get(k, 0.0)) * float(extra[k][0]) * float(extra[k][1])
	return v


## What a place gives at its best, by stock.
func _best(p: Dictionary) -> Dictionary:
	var out := {}
	var loot: Dictionary = p.get("loot", {})
	for k in loot:
		out[k] = float(out.get(k, 0.0)) + float(loot[k][1])
	var extra: Dictionary = p.get("extra", {})
	for k in extra:
		out[k] = float(out.get(k, 0.0)) + float(extra[k][1])
	return out


func _mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / float(xs.size())


func _corr(xs: Array, ys: Array) -> float:
	var mx := _mean(xs)
	var my := _mean(ys)
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in xs.size():
		sxy += (float(xs[i]) - mx) * (float(ys[i]) - my)
		sxx += (float(xs[i]) - mx) * (float(xs[i]) - mx)
		syy += (float(ys[i]) - my) * (float(ys[i]) - my)
	if sxx <= 0.0 or syy <= 0.0:
		return 0.0
	return sxy / sqrt(sxx * syy)


## The spawn point (an index into the map's spawns) a position lies towards, seen from the school
## (the same rule as Town.heading_of: the spawn point whose direction from the middle of the map is
## closest to the position's direction from the school).
func _heading(d: Dictionary, at: Vector2, spawns: Array) -> int:
	var dir: Vector2 = (at - _home(d)).normalized()
	var best := 0
	var best_dot := -2.0
	for i in spawns.size():
		var v: Vector2 = (_vec(spawns[i]) - SPAWN_CENTRE).normalized()
		var dot := dir.dot(v)
		if dot > best_dot:
			best_dot = dot
			best = i
	return best


func _spawns() -> Array:
	var m := _read(MAP_PATH)
	return m.get("spawns", []) if m.get("spawns", []) is Array else []


## Sentence breaks inside a text (a full stop, a question or an exclamation mark, a space and a capital).
func _inner_breaks(text: String) -> int:
	var re := RegEx.create_from_string("[.!?]\\s+[A-Z]")
	return re.search_all(text).size()


func _nest_places(d: Dictionary) -> Array:
	var out: Array = []
	for p in _places(d):
		if p.has("nest"):
			out.append(p)
	return out


## "good" (only gains), "bad" (only losses) or "neutral" (nothing happens to the party's fortunes, or a bit of both).
func _beat_class(e: Dictionary) -> String:
	var up := false
	var down := false
	if e.has("loot_pct"):
		if float(e.loot_pct) > 0.0:
			up = true
		elif float(e.loot_pct) < 0.0:
			down = true
	if e.has("morale"):
		if float(e.morale) > 0.0:
			up = true
		elif float(e.morale) < 0.0:
			down = true
	if e.has("reveal"):
		up = true
	if e.has("hurt") or e.has("delay_h") or e.has("lost"):
		down = true
	if up and not down:
		return "good"
	if down and not up:
		return "bad"
	return "neutral"


# --------------------------------------------------------------------- the file --

func test_the_file_parses_and_has_its_parts() -> void:
	var d := _town()
	if d.is_empty():
		return
	for k in ["board", "home", "places", "roads", "beats"]:
		check(d.has(k), "the data has '%s'" % k)
	var b = d.get("board", {})
	check(b is Dictionary and float(b.get("w", 0)) == 160.0 and float(b.get("h", 0)) == 70.0, "the board is 160 by 70 (the town on the west, the city across the river on the east): %s" % str(b))
	var h = d.get("home", [])
	check(h is Array and h.size() == 2, "home is a point")
	if h is Array and h.size() == 2:
		eq(_home(d), Vector2(50.0, 35.0), "the school is where it was: in the middle of the town, west of the river")
	check(d.get("places", []) is Array and d.get("roads", []) is Array and d.get("beats", []) is Array, "places, roads and beats are lists")


func test_thirty_five_places_each_with_what_the_board_needs() -> void:
	var d := _town()
	if d.is_empty():
		return
	var places := _places(d)
	eq(places.size(), 35, "thirty-five places: the town's twenty-four, the bridge and the city's ten")
	eq(_city_places(d).size(), 10, "ten of them need a vehicle")
	eq(_ground(d).places.size(), 25, "and twenty-five can be walked to")
	var re := RegEx.create_from_string("^[a-z][a-z_]*$")
	var ids := {}
	var kinds := {}
	for p in places:
		var id := String(p.get("id", ""))
		check(re.search(id) != null, "the id '%s' is lowercase with no spaces" % id)
		check(not ids.has(id), "ids are unique: %s" % id)
		check(id != "home", "no place is called home")
		ids[id] = true
		for k in p.keys():
			check(k in PLACE_KEYS, "%s has only known keys, not '%s'" % [id, k])
		for k in ["id", "name", "kind", "pos", "blurb", "danger", "loot", "extra"]:
			check(p.has(k), "%s has '%s'" % [id, k])
		if p.has("where"):
			check(typeof(p.where) == TYPE_STRING and String(p.where).strip_edges() != "" and String(p.where).length() <= 40, "%s: where is a short phrase: %s" % [id, str(p.where)])
		if p.has("needs_vehicle"):
			check(typeof(p.needs_vehicle) == TYPE_BOOL and p.needs_vehicle == true, "%s: needs_vehicle is true when present" % id)
		if p.has("vehicle"):
			check(typeof(p.vehicle) == TYPE_STRING and not _needs_vehicle(p), "%s: a vehicle is a kind's name, and waits in a place a party can walk to" % id)
		check(String(p.get("name", "")).strip_edges() != "", "%s has a name" % id)
		var kind := String(p.get("kind", ""))
		check(kind in KINDS or kind in CITY_KINDS, "%s has a kind from the list: %s" % [id, kind])
		kinds[kind] = true
		var danger = p.get("danger", -1)
		check(_is_whole(danger) and int(danger) >= 0 and int(danger) <= 3, "%s: danger is 0 to 3: %s" % [id, str(danger)])
		var blurb := String(p.get("blurb", ""))
		check(blurb.length() >= 40 and blurb.length() <= 230, "%s: the blurb is one or two sentences, not %d characters" % [id, blurb.length()])
		check(_inner_breaks(blurb) <= 1, "%s: the blurb is at most two sentences" % id)
		check(blurb.ends_with(".") and not blurb.contains("{") and not blurb.contains("}"), "%s: the blurb is plain text ending in a full stop" % id)
		check(not p.has("image"), "%s: no place has a picture (the cards draw their placeholder)" % id)
	for k in KINDS + CITY_KINDS:
		check(kinds.has(k), "the board has a place of kind %s" % k)
	for id in OLD_IDS:
		check(ids.has(id), "the old place %s is on the board" % id)
	var dangers := {}
	for p in places:
		dangers[int(p.get("danger", 0))] = int(dangers.get(int(p.get("danger", 0)), 0)) + 1
	for lvl in [0, 1, 2, 3]:
		check(int(dangers.get(lvl, 0)) >= 1, "some place has danger %d" % lvl)


func test_the_old_four_keep_their_loot_and_their_pictures() -> void:
	var d := _town()
	if d.is_empty():
		return
	var by := _by_id(d)
	var old := _read(SITES_PATH)
	var seen := 0
	for s in old.get("sites", []):
		var id := String(s.id)
		check(by.has(id), "%s is on the board" % id)
		if not by.has(id):
			continue
		seen += 1
		var p: Dictionary = by[id]
		eq(p.loot, s.loot, "%s: the same loot" % id)
		eq(p.extra, s.extra, "%s: the same extras" % id)
		eq(int(p.danger), int(s.danger), "%s: the same danger" % id)
		eq(String(p.get("image", "")), String(s.get("image", "")), "%s: the same picture" % id)
		eq(String(p.blurb), String(s.blurb), "%s: the same blurb" % id)
	eq(seen, 4, "all four old sites were found in sites.json")


# ------------------------------------------------------------------ the map --

func test_places_lie_on_the_board_and_apart() -> void:
	var d := _town()
	if d.is_empty():
		return
	var places := _places(d)
	var w := float(d.board.w)
	var h := float(d.board.h)
	var home := _home(d)
	var quadrants := {}
	for p in places:
		var id := String(p.id)
		check(p.pos is Array and p.pos.size() == 2, "%s has a position" % id)
		if not (p.pos is Array and p.pos.size() == 2):
			continue
		var at := _vec(p.pos)
		check(at.x >= 2.0 and at.x <= w - 2.0 and at.y >= 2.0 and at.y <= h - 2.0, "%s (%s) is inside the board" % [id, str(at)])
		check(at.distance_to(home) >= 8.0, "%s is at least 8 tiles from the school: %.1f" % [id, at.distance_to(home)])
		var q := "%s%s" % ["w" if at.x < home.x else "e", "n" if at.y < home.y else "s"]
		quadrants[q] = int(quadrants.get(q, 0)) + 1
	for i in places.size():
		for j in range(i + 1, places.size()):
			var dist: float = _vec(places[i].pos).distance_to(_vec(places[j].pos))
			check(dist >= 6.0, "%s and %s are %.1f tiles apart (at least 6)" % [places[i].id, places[j].id, dist])
	for q in ["wn", "en", "ws", "es"]:
		check(int(quadrants.get(q, 0)) >= 3, "the %s quarter of the town has at least three places: %d" % [q, int(quadrants.get(q, 0))])


func test_the_town_has_a_shape() -> void:
	var d := _town()
	if d.is_empty():
		return
	var by := _by_id(d)
	var home := _home(d)
	for id in by:
		var p: Dictionary = by[id]
		if String(p.kind) == "farm":
			check(_straight(d, p) >= 30.0, "the farm %s is out in the farm belt (30 tiles or more): %.1f" % [id, _straight(d, p)])
	check(by.has("scrapyard") and by.has("warehouse"), "the industrial corner has its scrapyard and warehouse")
	if by.has("scrapyard") and by.has("warehouse"):
		var a := _vec(by.scrapyard.pos)
		var b := _vec(by.warehouse.pos)
		check(a.distance_to(b) <= 25.0, "the scrapyard and the warehouse are in one corner: %.1f apart" % a.distance_to(b))
		check(a.x > home.x + 20.0 and b.x > home.x + 20.0, "and it is on the east side")
	# a main street: a run of places along the row of the school
	var along := 0
	for id in by:
		if absf(_vec(by[id].pos).y - home.y) <= 9.0:
			along += 1
	check(along >= 5, "a main street: at least five places within nine rows of the school: %d" % along)


func test_roads_are_well_formed() -> void:
	var d := _town()
	if d.is_empty():
		return
	var by := _by_id(d)
	var roads: Array = d.get("roads", [])
	var in_town: int = _ground(d).roads.size()
	check(in_town >= 26 and in_town <= 34, "about thirty roads on the ground (the town's and the one to the bridge): %d" % in_town)
	check(roads.size() - in_town >= 12 and roads.size() - in_town <= 18, "and a short network of roads in the city: %d" % (roads.size() - in_town))
	var seen := {}
	var touched := {}
	for r in roads:
		check(r is Array and r.size() == 2, "a road joins two ids: %s" % str(r))
		if not (r is Array and r.size() == 2):
			continue
		var a := String(r[0])
		var b := String(r[1])
		check(a == "home" or by.has(a), "road end '%s' is a place or home" % a)
		check(b == "home" or by.has(b), "road end '%s' is a place or home" % b)
		check(a != b, "no road from %s to itself" % a)
		var key := "%s|%s" % [_lesser(a, b), _greater(a, b)]
		check(not seen.has(key), "no road twice: %s" % key)
		seen[key] = true
		touched[a] = true
		touched[b] = true
	for id in by:
		check(touched.has(id), "%s has a road" % id)
	check(touched.has("home"), "the school has a road")


func _lesser(a: String, b: String) -> String:
	return a if a < b else b


func _greater(a: String, b: String) -> String:
	return b if a < b else a


func test_every_place_is_reachable_and_some_only_the_long_way_round() -> void:
	var d := _town()
	if d.is_empty():
		return
	var dist := _tile_distances(d)
	var longer := 0
	var ratios: Array = []
	for p in _places(d):
		var id := String(p.id)
		check(dist.has(id), "%s can be reached from the school along the roads" % id)
		if not dist.has(id):
			continue
		var straight := _straight(d, p)
		check(float(dist[id]) >= straight - 1.0e-6, "%s: the road (%.1f) is not shorter than the straight line (%.1f)" % [id, float(dist[id]), straight])
		var ratio: float = float(dist[id]) / straight
		ratios.append(ratio)
		check(ratio <= 2.0, "%s: the road is not absurdly long: %.2f times the straight line" % [id, ratio])
		if ratio >= 1.25:
			longer += 1
	check(longer >= 5, "at least five places are only reachable the long way round (1.25 times the straight line or more): %d" % longer)
	var mean := _mean(ratios)
	check(mean >= 1.1 and mean <= 1.45, "the roads wind a fair amount: %.2f on average" % mean)


func test_the_hours_to_the_nearest_and_the_farthest_places() -> void:
	var d := _ground(_town())
	if d.is_empty():
		return
	var hours := _hours(d)
	var by := _by_id(d)
	var order := _nearest_first(d)
	for i in 5:
		var id := String(order[i])
		check(float(hours[id]) >= 0.7 and float(hours[id]) <= 2.5, "%s, among the five nearest, is %.2f hours away (0.7 to 2.5)" % [id, float(hours[id])])
		var s := _straight(d, by[id])
		check(s >= 8.0 and s <= 16.0, "%s is in the nearest ring (8 to 16 tiles): %.1f" % [id, s])
	# the farthest four by the road, and by the straight line
	var rows: Array = []
	for id in hours:
		rows.append([float(hours[id]), String(id)])
	rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for i in 4:
		check(float(rows[i][0]) >= 4.0 and float(rows[i][0]) <= 7.0, "%s, among the farthest four, is %.2f hours away (4 to 7)" % [rows[i][1], float(rows[i][0])])
	for id in hours:
		check(float(hours[id]) <= 7.0, "no place is more than seven hours away: %s %.2f" % [id, float(hours[id])])
	for i in 4:
		var id := String(order[order.size() - 1 - i])
		var s := _straight(d, by[id])
		check(s >= 40.0 and s <= 55.0, "%s, among the farthest four, is %.1f tiles away in a straight line (40 to 55)" % [id, s])
	# the places in between: a spread, not two heaps
	var mid := 0
	for id in hours:
		if float(hours[id]) > 2.5 and float(hours[id]) < 4.5:
			mid += 1
	check(mid >= 6, "at least six places a trip of between 2.5 and 4.5 hours away: %d" % mid)


func test_exactly_five_places_are_known_and_they_are_the_nearest() -> void:
	var d := _town()
	if d.is_empty():
		return
	var by := _by_id(d)
	var known: Array = []
	for id in by:
		if bool(by[id].get("known", false)):
			known.append(String(id))
	eq(known.size(), 5, "five places are known from the start: %s" % str(known))
	check("houses" in known, "the houses are known")
	var order := _nearest_first(d)
	for i in 5:
		check(String(order[i]) in known, "%s is among the five nearest and is known" % order[i])
	check(not bool(by.get("scrapyard", {}).get("known", false)), "the scrapyard has to be found")
	# and the sixth nearest is clearly farther than the fifth: the line between near and far is clear
	var hours := _hours(d)
	var by_hours: Array = []
	for id in hours:
		by_hours.append([float(hours[id]), String(id)])
	by_hours.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in 5:
		check(String(by_hours[i][1]) in known, "%s is among the five nearest by road and is known" % by_hours[i][1])
	check(float(by_hours[5][0]) >= float(by_hours[4][0]) + 0.3, "the sixth by road (%s, %.2f h) is clearly farther than the fifth (%.2f h)" % [by_hours[5][1], float(by_hours[5][0]), float(by_hours[4][0])])


## Scouting shows the places within a radius of the place a party went to (Town.SCOUT_RADIUS, 26 at the
## time of writing). Whatever the radius is tuned to (down to this), scouting alone can uncover the whole
## town from the five known places: no place is left out of reach in the fog.
func test_scouting_can_uncover_the_whole_town() -> void:
	var d := _town()
	if d.is_empty():
		return
	var radius := 20.0
	var places := _places(d)
	var shown := {}
	var frontier: Array = []
	for p in places:
		if bool(p.get("known", false)):
			shown[String(p.id)] = true
			frontier.append(p)
	var rounds := 0
	while not frontier.is_empty():
		rounds += 1
		var next: Array = []
		for a in frontier:
			for b in places:
				if not shown.has(String(b.id)) and _vec(a.pos).distance_to(_vec(b.pos)) <= radius:
					shown[String(b.id)] = true
					next.append(b)
		frontier = next
	for p in places:
		check(shown.has(String(p.id)), "%s can be found by scouting (a radius of %d tiles)" % [p.id, int(radius)])
	check(rounds >= 3, "the fog takes at least two rounds of scouting to clear: %d" % (rounds - 1))
	# and the first scouting trips do not show everything at once
	var after_one := {}
	for p in places:
		if bool(p.get("known", false)):
			after_one[String(p.id)] = true
			for b in places:
				if _vec(p.pos).distance_to(_vec(b.pos)) <= radius:
					after_one[String(b.id)] = true
	check(after_one.size() <= 18, "scouting each near place once does not show the whole town: %d of %d" % [after_one.size(), places.size()])


# ----------------------------------------------------------------------- loot --

func test_loot_is_in_the_format_of_sites_json_and_within_the_caps() -> void:
	var d := _town()
	if d.is_empty():
		return
	for p in _places(d):
		var id := String(p.id)
		var loot = p.get("loot", {})
		var extra = p.get("extra", {})
		# the bridge is only a place to scout from: it is the one place with nothing in it
		var bridge := String(p.get("kind", "")) == "bridge"
		check(loot is Dictionary and (not loot.is_empty() or bridge), "%s has loot" % id)
		check(not bridge or (loot is Dictionary and loot.is_empty() and extra is Dictionary and extra.is_empty()), "%s: a bridge holds nothing" % id)
		check(extra is Dictionary, "%s has an extra (it may be empty)" % id)
		if not (loot is Dictionary and extra is Dictionary):
			continue
		for k in loot:
			check(k in STOCKS, "%s: '%s' is a stock" % [id, k])
			var r = loot[k]
			check(r is Array and r.size() == 2 and _is_number(r[0]) and _is_number(r[1]), "%s: loot %s is [min, max]" % [id, k])
			if r is Array and r.size() == 2:
				check(float(r[0]) > 0.0 and float(r[0]) <= float(r[1]), "%s: loot %s has 0 < min <= max: %s" % [id, k, str(r)])
		for k in extra:
			check(k in STOCKS, "%s: extra '%s' is a stock" % [id, k])
			var r = extra[k]
			check(r is Array and r.size() == 2 and _is_number(r[0]) and _is_number(r[1]), "%s: extra %s is [chance, amount]" % [id, k])
			if r is Array and r.size() == 2:
				check(float(r[0]) > 0.0 and float(r[0]) <= 1.0 and float(r[1]) > 0.0, "%s: extra %s has a chance in (0, 1] and an amount: %s" % [id, k, str(r)])
		var best := _best(p)
		var caps: Dictionary = CITY_CAPS if _needs_vehicle(p) else CAPS
		for k in caps:
			check(float(best.get(k, 0.0)) <= float(caps[k]), "%s gives at most %d %s at its best: %s" % [id, int(caps[k]), k, str(best.get(k, 0.0))])
		for k in best:
			check(caps.has(k), "%s: %s has a cap" % [id, k])


func test_the_farther_and_the_more_dangerous_a_place_the_richer_it_is() -> void:
	var d := _ground(_town())
	if d.is_empty():
		return
	var hours := _hours(d)
	var xs: Array = []
	var ds: Array = []
	var vs: Array = []
	var by_danger := {0: [], 1: [], 2: [], 3: []}
	var rows: Array = []
	for p in _places(d):
		var id := String(p.id)
		if p.loot.is_empty():
			continue    # the bridge: nothing in it, and not a place to be paid for
		var v := _value(p)
		xs.append(float(hours[id]))
		ds.append(float(p.danger))
		vs.append(v)
		by_danger[int(p.danger)].append(v)
		rows.append([float(hours[id]), v])
	var c_hours := _corr(xs, vs)
	var c_danger := _corr(ds, vs)
	check(c_hours >= 0.5, "loot value rises with distance: correlation %.2f" % c_hours)
	check(c_danger >= 0.5, "and with danger: correlation %.2f" % c_danger)
	var prev := -1.0
	for lvl in [0, 1, 2, 3]:
		var m := _mean(by_danger[lvl])
		check(m > prev, "the mean value at danger %d (%.1f) is above that at the level below (%.1f)" % [lvl, m, prev])
		prev = m
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var near: Array = []
	var far: Array = []
	for i in 8:
		near.append(rows[i][1])
		far.append(rows[rows.size() - 1 - i][1])
	check(_mean(far) >= 1.4 * _mean(near), "the eight farthest places are worth much more (%.1f) than the eight nearest (%.1f)" % [_mean(far), _mean(near)])
	var top := 0.0
	for v in vs:
		top = maxf(top, float(v))
	check(top <= 120.0, "no place is worth more than 120 of the value scale: %.1f" % top)


# ---------------------------------------------------------------------- nests --

func test_nests_lean_towards_every_side_of_the_map() -> void:
	var d := _ground(_town())
	if d.is_empty():
		return
	var spawns := _spawns()
	check(spawns.size() >= 8, "the map has its spawn points: %d" % spawns.size())
	var nests := _nest_places(d)
	check(nests.size() >= 5 and nests.size() <= 9, "five to nine nests: %d" % nests.size())
	var home := _home(d)
	var total := 0
	var headings := {}
	var halves := {"west": 0, "east": 0, "north": 0, "south": 0}
	for p in nests:
		var id := String(p.id)
		check(p.nest is Dictionary and p.nest.keys() == ["strength"], "%s: a nest has only a strength" % id)
		var s = p.nest.get("strength", 0)
		check(_is_whole(s) and int(s) >= 1 and int(s) <= 3, "%s: nest strength 1 to 3: %s" % [id, str(s)])
		total += int(s)
		check(int(p.danger) >= 2, "%s: a place with a nest is dangerous (2 or 3): %d" % [id, int(p.danger)])
		check(not bool(p.get("known", false)), "%s: a nest is not in the near ring" % id)
		var at := _vec(p.pos)
		var h := _heading(d, at, spawns)
		headings[h] = int(headings.get(h, 0)) + 1
		if at.x < home.x:
			halves.west += 1
		else:
			halves.east += 1
		if at.y < home.y:
			halves.north += 1
		else:
			halves.south += 1
	var most := 0
	for h in headings:
		most = maxi(most, int(headings[h]))
	check(most * 2 <= nests.size(), "no more than half the nests lean towards one spawn point: %d of %d (%s)" % [most, nests.size(), str(headings)])
	check(headings.size() >= 6, "the nests lean towards at least six different spawn points: %d (%s)" % [headings.size(), str(headings)])
	for side in halves:
		check(int(halves[side]) >= 2, "at least two nests lie to the %s of the school: %d" % [side, int(halves[side])])
	check(total >= 8 and total <= 16, "the nests' strength adds up to a sensible amount to clear (8 to 16): %d" % total)


# ------------------------------------------------------------------ survivors --

func test_survivors_are_hiding_in_four_to_six_places() -> void:
	var d := _ground(_town())
	if d.is_empty():
		return
	var spawns := _spawns()
	var hours := _hours(d)
	var n := 0
	var headings := {}
	var nearest := INF
	var farthest := 0.0
	for p in _places(d):
		if not p.has("survivor"):
			continue
		var id := String(p.id)
		check(typeof(p.survivor) == TYPE_BOOL and p.survivor == true, "%s: survivor is true when present" % id)
		n += 1
		var h := _heading(d, _vec(p.pos), spawns)
		headings[h] = true
		nearest = minf(nearest, float(hours[id]))
		farthest = maxf(farthest, float(hours[id]))
	check(n >= 4 and n <= 6, "four to six survivors: %d" % n)
	check(nearest <= 2.5, "the first rescue is within reach of the start: %.2f hours" % nearest)
	check(farthest >= 4.0, "and one waits far away: %.2f hours" % farthest)
	check(headings.size() >= 3, "the survivors are spread over at least three directions: %d" % headings.size())


# ------------------------------------------------------------------- outposts --

func test_outposts_have_modest_yields_and_costs() -> void:
	var d := _town()
	if d.is_empty():
		return
	var ranges := {"food": [2.0, 5.0], "water": [2.0, 5.0], "scrap": [2.0, 4.0], "meds": [0.5, 1.0], "ammo": [3.0, 6.0]}
	var fits := {"farm": "food", "garage": "scrap", "scrapyard": "scrap", "clinic": "meds", "police": "ammo", "water_works": "water", "bakery": "food",
		"hospital": "meds", "cold_store": "food"}
	var n := 0
	var made := {}
	for p in _places(d):
		if not p.has("outpost"):
			continue
		n += 1
		var id := String(p.id)
		var o = p.outpost
		check(o is Dictionary and o.has("yield") and o.has("cost") and o.size() == 2, "%s: an outpost is {yield, cost}" % id)
		if not (o is Dictionary and o.has("yield") and o.has("cost")):
			continue
		var y: Dictionary = o.yield
		check(not y.is_empty(), "%s: it yields something" % id)
		for k in y:
			check(ranges.has(k), "%s: '%s' is a stock" % [id, k])
			if ranges.has(k):
				var lo: float = ranges[k][0]
				var hi: float = ranges[k][1]
				check(float(y[k]) >= lo and float(y[k]) <= hi, "%s: %s a day is %s (%s to %s)" % [id, k, str(y[k]), str(lo), str(hi)])
				made[k] = true
		var cost = o.cost
		check(_is_whole(cost) and float(cost) >= 20.0 and float(cost) <= 60.0, "%s: it costs 20 to 60 scrap: %s" % [id, str(cost)])
		var kind := String(p.kind)
		if fits.has(kind):
			check(y.has(fits[kind]), "%s (%s) makes sense of its yield: it gives %s" % [id, kind, fits[kind]])
	check(n >= 6 and n <= 10, "six to ten places can become outposts (the town's eight and two in the city): %d" % n)
	for k in STORES:
		check(made.has(k), "some outpost makes %s" % k)


# ---------------------------------------------------------------------- beats --

func test_beats_are_well_formed() -> void:
	var d := _town()
	if d.is_empty():
		return
	var beats: Array = d.get("beats", [])
	check(beats.size() >= 28 and beats.size() <= 34, "about thirty beats (the town's twenty-five and six for the long road): %d" % beats.size())
	var ids := {}
	var texts := {}
	var re := RegEx.create_from_string("^[a-z][a-z_]*$")
	for e in beats:
		check(e is Dictionary, "a beat is an object")
		if not e is Dictionary:
			continue
		var id := String(e.get("id", ""))
		check(re.search(id) != null, "beat id '%s' is lowercase with no spaces" % id)
		check(not ids.has(id), "beat ids are unique: %s" % id)
		ids[id] = true
		for k in e.keys():
			check(k in BEAT_KEYS, "%s has only known keys, not '%s'" % [id, k])
		for k in BEAT_KEYS:
			check(e.has(k), "%s has '%s'" % [id, k])
		var text = e.get("text", "")
		check(typeof(text) == TYPE_STRING, "%s: the text is a string" % id)
		var t := String(text)
		check(not texts.has(t), "%s: no two beats say the same thing" % id)
		texts[t] = true
		check(t.length() >= 40 and t.length() <= 175, "%s: the text is one sentence, not %d characters" % [id, t.length()])
		check(t.ends_with(".") and not t.contains("{") and not t.contains("}") and not t.contains("%"), "%s: the text is plain, with no braces, ending in a full stop" % id)
		check(_inner_breaks(t) == 0, "%s: the text is one sentence" % id)
		check(not t.contains("\n") and not t.contains("  "), "%s: no stray whitespace" % id)
		var w = e.get("weight", 0)
		check(_is_whole(w) and int(w) >= 1 and int(w) <= 3, "%s: weight 1 to 3: %s" % [id, str(w)])
		var mh = e.get("min_hours", -1)
		check(_is_number(mh) and float(mh) >= 0.0 and float(mh) <= 6.0, "%s: min_hours 0 to 6: %s" % [id, str(mh)])
		var fx = e.get("effects", null)
		check(fx is Dictionary, "%s: effects is a flat dictionary" % id)
		if not fx is Dictionary:
			continue
		for k in fx:
			check(k in EFFECT_KEYS, "%s: '%s' is an effect the module knows" % [id, k])
			var v = fx[k]
			check(not (v is Dictionary or v is Array), "%s: effect %s is flat" % [id, k])
			match String(k):
				"loot_pct":
					check(_is_number(v) and float(v) >= -40.0 and float(v) <= 40.0 and float(v) != 0.0, "%s: loot_pct is -40 to +40: %s" % [id, str(v)])
				"hurt":
					check(String(v) in ["scratch", "bite"], "%s: hurt is a scratch or a bite: %s" % [id, str(v)])
				"delay_h":
					check(_is_number(v) and float(v) >= 0.5 and float(v) <= 3.0, "%s: delay_h is 0.5 to 3: %s" % [id, str(v)])
				"reveal":
					check(String(v) == "near", "%s: reveal is 'near': %s" % [id, str(v)])
				"morale":
					check(_is_number(v) and float(v) >= -6.0 and float(v) <= 6.0 and float(v) != 0.0, "%s: morale is -6 to +6: %s" % [id, str(v)])
				"lost":
					check(typeof(v) == TYPE_BOOL and v == true, "%s: lost is true when present: %s" % [id, str(v)])


func test_the_beats_mix_good_neutral_and_bad_and_lose_people_rarely() -> void:
	var d := _town()
	if d.is_empty():
		return
	var beats: Array = d.get("beats", [])
	var count := {"good": 0, "neutral": 0, "bad": 0}
	var weight := {"good": 0, "neutral": 0, "bad": 0}
	var lost := 0
	var short := 0
	var pct_sum := 0.0
	var weight_sum := 0.0
	var reveals := 0
	var bites := 0
	for e in beats:
		var cls := _beat_class(e.effects)
		count[cls] += 1
		weight[cls] += int(e.weight)
		weight_sum += float(e.weight)
		pct_sum += float(e.effects.get("loot_pct", 0.0)) * float(e.weight)
		if e.effects.has("lost"):
			lost += 1
			check(float(e.min_hours) >= 4.0, "%s: a beat that loses someone needs a trip of 4 hours or more: %s" % [e.id, str(e.min_hours)])
		if float(e.min_hours) <= 2.0:
			short += 1
		if e.effects.has("reveal"):
			reveals += 1
		if String(e.effects.get("hurt", "")) == "bite":
			bites += 1
	check(lost >= 1 and lost <= 2, "one or two beats may lose someone: %d" % lost)
	for cls in count:
		check(int(count[cls]) >= 6 and int(count[cls]) <= 12, "about a third of the beats are %s: %d of %d" % [cls, int(count[cls]), beats.size()])
	var g: float = float(weight.good)
	var b: float = float(weight.bad)
	check(g >= 0.7 * b and b >= 0.7 * g, "good and bad beats weigh about the same: %d against %d" % [int(g), int(b)])
	check(short >= 12, "a short trip can meet at least twelve of them (min_hours 2 or less): %d" % short)
	var mean_pct := pct_sum / maxf(weight_sum, 1.0)
	check(mean_pct >= -8.0 and mean_pct <= 8.0, "the beats do not push the loot one way on average: %.1f percent" % mean_pct)
	check(reveals >= 2 and reveals <= 5, "a few beats reveal a place: %d" % reveals)
	check(bites >= 1 and bites <= 2, "a bite is rare: %d" % bites)


# ------------------------------------------------------------------- the city --

## What the city's places are, by id: [kind, danger, {stock: [lowest the loot's minimum may be, highest its maximum may be]}].
## The hospital's medicine, the police headquarters' armoury, the rail yard's steel and the fuel depot's tanks are what
## the trip across the river is for.
const CITY_SPEC := {
	"hospital": ["hospital", 3, {"meds": [20.0, 35.0]}],
	"mall": ["supermarket", 2, {"food": [20.0, 45.0], "water": [10.0, 30.0]}],
	"university": ["university", 2, {"scrap": [15.0, 40.0], "meds": [4.0, 15.0]}],
	"police_hq": ["police", 3, {"ammo": [90.0, 160.0]}],
	"rail_yard": ["rail_yard", 3, {"scrap": [40.0, 70.0]}],
	"power_station": ["power_station", 3, {"scrap": [25.0, 60.0]}],
	"fuel_depot": ["fuel_depot", 2, {"fuel": [40.0, 70.0]}],
	"cold_store": ["cold_store", 2, {"food": [20.0, 35.0], "water": [8.0, 20.0]}],
	"flats": ["houses", 2, {"food": [14.0, 30.0], "meds": [2.0, 8.0]}],
	"checkpoint": ["checkpoint", 3, {"ammo": [50.0, 100.0]}],
}


func test_the_bridge_is_a_place_on_foot_that_shows_the_east() -> void:
	var d := _town()
	if d.is_empty():
		return
	var bridges: Array = []
	for p in _places(d):
		if String(p.get("kind", "")) == "bridge":
			bridges.append(p)
	eq(bridges.size(), 1, "one bridge")
	if bridges.size() != 1:
		return
	var b: Dictionary = bridges[0]
	var at := _vec(b.pos)
	check(not _needs_vehicle(b), "the bridge can be walked to: that is how the city is found")
	check(not bool(b.get("known", false)), "the bridge has to be found (by scouting the east)")
	eq(int(b.danger), 1, "a bridge is danger 1")
	check(b.loot.is_empty() and b.extra.is_empty(), "a bridge holds nothing")
	check(at.x >= 92.0 and at.x <= 99.0, "the bridge is at about x 95, on the river: %s" % str(at))
	check(not b.has("nest") and not b.has("survivor") and not b.has("outpost"), "no nest, survivor or outpost on a bridge")
	# the hours on foot: an overnight walk (about five hours one way)
	var h := float(_hours(d)[String(b.id)])
	check(h >= 4.5 and h <= 6.0, "the bridge is about five hours away on foot: %.2f" % h)
	# the town's east-most place shows it to a scouting party
	var east: Dictionary = {}
	for p in _ground(d).places:
		if String(p.id) != String(b.id) and (east.is_empty() or _vec(p.pos).x > _vec(east.pos).x):
			east = p
	check(_vec(east.pos).distance_to(at) <= 20.0, "the town's east-most place (%s) is within 20 tiles of the bridge: %.1f" % [east.id, _vec(east.pos).distance_to(at)])
	# the long road: from the town's east side over the bridge to the city's places
	var from_town := 0
	var to_city := 0
	var by := _by_id(d)
	for r in d.roads:
		var other := ""
		if String(r[0]) == String(b.id):
			other = String(r[1])
		elif String(r[1]) == String(b.id):
			other = String(r[0])
		if other == "":
			continue
		if other != "home" and by.has(other) and _needs_vehicle(by[other]):
			to_city += 1
		else:
			from_town += 1
	check(from_town >= 1 and to_city >= 2, "roads join the bridge to the town (%d) and to the city (%d)" % [from_town, to_city])


func test_the_city_has_ten_places_across_the_river() -> void:
	var d := _town()
	if d.is_empty():
		return
	var city := _city_places(d)
	eq(city.size(), 10, "ten places in the city")
	var w := float(d.board.w)
	var home := _home(d)
	var kinds := {}
	for p in city:
		var id := String(p.id)
		var at := _vec(p.pos)
		check(at.x >= 100.0 and at.x <= w - 2.0 and at.y >= 2.0 and at.y <= float(d.board.h) - 2.0, "%s (%s) is in the city, past the river on the east side of the board" % [id, str(at)])
		check(not bool(p.get("known", false)), "%s: no city place is known at the start" % id)
		check(p.has("where") and String(p.where) != "", "%s has a `where` for the board's sentences" % id)
		check(not p.has("image"), "%s: no pictures for the city" % id)
		kinds[String(p.kind)] = true
	check(kinds.size() >= 9, "the city is not all one kind of place: %d kinds" % kinds.size())
	for id in CITY_SPEC:
		var by := _by_id(d)
		check(by.has(id), "the city has %s" % id)
		if not by.has(id):
			continue
		var p: Dictionary = by[id]
		var spec: Array = CITY_SPEC[id]
		check(_needs_vehicle(p), "%s needs a vehicle" % id)
		eq(String(p.kind), String(spec[0]), "%s: its kind" % id)
		eq(int(p.danger), int(spec[1]), "%s: its danger" % id)
		var stocks: Dictionary = spec[2]
		for k in stocks:
			check(p.loot.has(k), "%s has %s among its loot" % [id, k])
			if p.loot.has(k):
				check(float(p.loot[k][0]) >= float(stocks[k][0]) and float(p.loot[k][1]) <= float(stocks[k][1]), "%s: %s is %s (a minimum of at least %d and a maximum of at most %d)" % [id, k, str(p.loot[k]), int(stocks[k][0]), int(stocks[k][1])])
	# the police headquarters' armoury and the hospital's medicine are the best in the board
	var by2 := _by_id(d)
	if by2.has("police_hq") and by2.has("hospital"):
		check(float(by2.police_hq.loot.ammo[0]) >= 90.0 and float(by2.police_hq.loot.ammo[1]) <= 160.0, "the headquarters holds 90 to 160 ammo")
		check(float(by2.hospital.loot.meds[0]) >= 20.0 and float(by2.hospital.loot.meds[1]) <= 35.0, "the hospital holds 20 to 35 medicine")
	# the city is dearer to take: nobody goes there for nothing
	var mean_danger := 0.0
	var threes := 0
	for p in city:
		mean_danger += float(p.danger)
		if int(p.danger) == 3:
			threes += 1
		check(int(p.danger) >= 2, "%s: the city is no place for danger 1 or less" % p.id)
	mean_danger /= maxf(1.0, float(city.size()))
	var ground_mean_danger := 0.0
	var ground_n := 0
	for p in _ground(d).places:
		if not p.loot.is_empty():
			ground_mean_danger += float(p.danger)
			ground_n += 1
	ground_mean_danger /= maxf(1.0, float(ground_n))
	check(mean_danger >= ground_mean_danger + 0.4, "the city (%.2f) is more dangerous than the town (%.2f) on average" % [mean_danger, ground_mean_danger])
	check(threes >= 4, "at least four places of the city are danger 3: %d" % threes)
	var city_values: Array = []
	var ground_values: Array = []
	for p in city:
		city_values.append(_value(p))
		check(_value(p) <= 130.0, "%s is not worth more than 130 of the value scale: %.1f" % [p.id, _value(p)])
	for p in _ground(d).places:
		if not p.loot.is_empty():
			ground_values.append(_value(p))
	check(_mean(city_values) >= 1.3 * _mean(ground_values), "the city is richer: %.1f a place against the town's %.1f" % [_mean(city_values), _mean(ground_values)])
	check(home.distance_to(Vector2(w, 35.0)) > 90.0, "(the board has room for it)")


func test_the_city_has_two_nests_two_survivors_and_two_outposts() -> void:
	var d := _town()
	if d.is_empty():
		return
	var spawns := _spawns()
	var city := _city_places(d)
	var nests: Array = []
	var survivors := 0
	var outposts := 0
	for p in city:
		if p.has("nest"):
			nests.append(p)
		if p.has("survivor"):
			survivors += 1
		if p.has("outpost"):
			outposts += 1
	eq(nests.size(), 2, "two nests in the city")
	eq(survivors, 2, "two survivors in the city")
	eq(outposts, 2, "two places of the city can become outposts")
	# each nest sends the dead from a different spawn point (the headings from the school: from there the whole city lies
	# to the east, so only a few spawn points are in reach: the north-east, the east and the south-east ones)
	var headings := {}
	for p in nests:
		check(int(p.nest.strength) >= 2 and int(p.nest.strength) <= 3, "%s: a city nest has strength 2 or 3: %s" % [p.id, str(p.nest)])
		check(int(p.danger) >= 2, "%s: a nest is dangerous" % p.id)
		headings[_heading(d, _vec(p.pos), spawns)] = true
	eq(headings.size(), nests.size(), "the two nests lean towards different spawn points: %s" % str(headings.keys()))
	# and they add to what the town's nests do: neither piles on the point that already has the most
	var town_pressure := {}
	for p in _nest_places(_ground(d)):
		var h := _heading(d, _vec(p.pos), spawns)
		town_pressure[h] = int(town_pressure.get(h, 0)) + int(p.nest.strength)
	var top := 0
	for h in town_pressure:
		top = maxi(top, int(town_pressure[h]))
	for h in headings:
		check(int(town_pressure.get(h, 0)) < top, "a city nest does not lean on the spawn point (%d) that the town's nests already weigh on most" % h)


func test_the_road_beats_belong_to_the_long_road() -> void:
	var d := _town()
	if d.is_empty():
		return
	var road := ["lorry_shed_its_load", "roadblock_of_cars", "clear_road", "curtain_lorry", "repainted_signs", "bridge_queue"]
	var by := {}
	for e in d.get("beats", []):
		by[String(e.id)] = e
	var delays := 0
	var scratches := 0
	var morale := 0
	var finds := 0
	var reveals := 0
	var flavour := 0
	for id in road:
		check(by.has(id), "the road beat %s exists" % id)
		if not by.has(id):
			continue
		var e: Dictionary = by[id]
		# the near places' trips take 3 to 5 hours on foot: a beat of the long road is for the trips beyond them
		check(float(e.min_hours) >= 5.0, "%s: a beat of the long road needs a trip of five hours or more: %s" % [id, str(e.min_hours)])
		check(not e.effects.has("lost"), "%s: the road does not lose people (the old beats do, rarely)" % id)
		if e.effects.has("delay_h"):
			delays += 1
		if String(e.effects.get("hurt", "")) == "scratch":
			scratches += 1
		if float(e.effects.get("morale", 0.0)) > 0.0:
			morale += 1
		if float(e.effects.get("loot_pct", 0.0)) > 0.0:
			finds += 1
		if e.effects.has("reveal"):
			reveals += 1
		if e.effects.is_empty():
			flavour += 1
		# a beat meets a party on foot as well as one in a car (the core does not tell them apart): its words must fit both
		var t := String(e.text).to_lower()
		for word in ["tyre", "tire", "petrol", "fuel", "engine", "bumper", "seat", "windscreen", "dashboard"]:
			check(not t.contains(word), "%s: the text names a car's part ('%s'), which would be nonsense for a party on foot" % [id, word])
	check(delays >= 2 and scratches >= 1 and morale >= 1 and finds >= 1 and reveals >= 1 and flavour >= 1, "the road has delays (%d), a scratch (%d), a lift (%d), a find (%d), a sign (%d) and a bare scene (%d)" % [delays, scratches, morale, finds, reveals, flavour])
	# only a handful of the older beats can be met on a trip of five hours or more, so the near places keep to their own
	var far_beats := 0
	for e in d.get("beats", []):
		if float(e.min_hours) >= 5.0:
			far_beats += 1
	check(far_beats == road.size() + 1, "the six road beats and the lit window are the only beats that need five hours or more: %d" % far_beats)


# ------------------------------------------------------- the real module agrees --

## Once scripts/sim/town.gd is wired into the sim, the module's own distances, positions and headings
## must be the ones this file works out.
func test_the_module_reads_the_data_the_way_these_tests_do() -> void:
	var d := _town()
	if d.is_empty():
		return
	var g := Helpers.make(1, 1, 3)
	var sim = g.sim
	if sim.get("town") == null:
		print("        note: sim.town is not wired yet; the module cross-check was skipped")
		g.world.free()
		return
	var town = sim.town
	check(bool(town.on), "the small start has a board")
	eq(town.places.size(), 35, "the module loaded all 35 places")
	var hours := _hours(d)
	var spawns := _spawns()
	var known: Array = []
	for id in hours:
		near(float(town.hours_to(id)), float(hours[id]), 1.0e-6, "the module's hours to %s are the road distance over %s" % [id, str(SPEED)])
		near(float(town.trip_hours(id)), 2.0 * float(hours[id]) + float(town.SEARCH_H), 1.0e-6, "and its trip to %s is there, the search and back" % id)
		var p: Dictionary = town.place(id)
		check(not p.is_empty(), "the module knows %s" % id)
		if p.is_empty():
			continue
		if p.has("nest"):
			eq(int(town.heading_of(p)), _heading(d, _vec(_by_id(d)[id].pos), spawns), "the module's heading for the nest at %s" % id)
		eq(bool(p.get("needs_vehicle", false)), _needs_vehicle(_by_id(d)[id]), "the module knows whether %s needs a vehicle" % id)
		if bool(p.get("known", false)):
			known.append(id)
		eq(String(town.state_of(id)), "known" if bool(p.get("known", false)) else "unknown", "%s starts %s" % [id, "known" if bool(p.get("known", false)) else "unknown"])
	eq(known.size(), 5, "and five places start known")
	eq(town.beats().size(), d.beats.size(), "the module has all the beats")
	var strength := 0.0
	for i in sim.spawns.size():
		strength += float(town.pressure(i))
	var total := 0.0
	for p in _nest_places(d):
		total += float(p.nest.strength)
	near(strength, total, 1.0e-9, "every nest's strength is felt at some spawn point")
	g.world.free()
