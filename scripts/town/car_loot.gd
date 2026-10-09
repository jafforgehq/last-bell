## LOOT IN THE STREET'S CARS (PH3, SCAV3): the parked cars and wrecks of the streets are containers. Before this the generator made containers only inside walls, so a car could be stripped for
## scrap (scripts/town/salvage.gd) but never searched. Static helpers; every number is the `cars` block of assets/data/salvage.json (read once).
##
## `containers(town)` makes the list of them from the town's object list (`town.data.objects`): one container for each object of a kind in `cars.chance` that stands in the street. It is a pure
## function of the town (the roll is seeded by the town's seed and the object's place in the list), so a town always has the same cars with the same things in them and a save needs to keep
## nothing but the `looted` flag (scripts/town/search.gd: a car is looted once, whoever searched it). The list is NOT added to `town.containers` or to a house: scripts/town/houses.gd keeps it
## beside them (`cars`, `container(id)` finds one, `cars_near`), so no house, room or generator figure changes.
## A car container is {"id": "car<n>", "house": -1, "room": -1, "pos" (a free tile beside it), "at" (its middle), "kind" (car_h, car_v, car_wreck), "name" ("car" | "wreck"), "loot": {stock: n},
## "search_s", "car": true, "rect" (Rect2i, its tiles), "obj" (n), "piece" (the salvage piece's id: "o<n>")}.
extends RefCounted

const DATA_PATH := "res://assets/data/salvage.json"
const ID_PREFIX := "car"
const DEFAULT_SEARCH_S := 4.0
const DEFAULT_REACH := 1.0
const DEFAULT_RADIUS := 14.0
const DEFAULT_MOST := 6

static var _cfg := {}
static var _read := false


## The `cars` block of salvage.json ({} when there is none: no car holds anything and the crew do not look at cars).
static func config() -> Dictionary:
	if not _read:
		_read = true
		if FileAccess.file_exists(DATA_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if typeof(parsed) == TYPE_DICTIONARY and typeof((parsed as Dictionary).get("cars")) == TYPE_DICTIONARY:
				_cfg = parsed.cars
	return _cfg


## Puts the block aside for a lab or a test (null: read the file again).
static func set_config(c) -> void:
	if c == null:
		_read = false
		_cfg = {}
	else:
		_read = true
		_cfg = c


static func reach() -> float:
	return float(config().get("reach", DEFAULT_REACH))


## How far from the house (or from the first car of a trip with no house) the crew look for cars, tiles.
static func radius() -> float:
	var trip = config().get("trip", {})
	return float(trip.get("radius", DEFAULT_RADIUS)) if typeof(trip) == TYPE_DICTIONARY else DEFAULT_RADIUS


## The most cars one trip visits.
static func most() -> int:
	var trip = config().get("trip", {})
	return int(trip.get("most", DEFAULT_MOST)) if typeof(trip) == TYPE_DICTIONARY else DEFAULT_MOST


## The distance from a point to the nearest point of a rectangle of tiles (0 inside it).
static func rect_dist(at: Vector2, rect: Rect2i) -> float:
	var dx := maxf(maxf(float(rect.position.x) - at.x, at.x - float(rect.end.x)), 0.0)
	var dy := maxf(maxf(float(rect.position.y) - at.y, at.y - float(rect.end.y)), 0.0)
	return sqrt(dx * dx + dy * dy)


# --------------------------------------------------------------------------------- the list --

## The car containers of a town (`TownGen.make` result), in the order of the object list. [] for a town with no objects or a data file with no `cars` block.
static func containers(town: Dictionary) -> Array:
	var out: Array = []
	var cfg := config()
	var chance = cfg.get("chance", {})
	if town.is_empty() or typeof(chance) != TYPE_DICTIONARY or (chance as Dictionary).is_empty() or typeof(town.get("data")) != TYPE_DICTIONARY:
		return out
	var objs: Array = town.data.get("objects", [])
	var seed_v := int(town.get("seed", 0))
	var size = town.get("size", Vector2i.ZERO)
	var W := int(Vector2i(size).x) if typeof(size) == TYPE_VECTOR2I else 0
	var H := int(Vector2i(size).y) if typeof(size) == TYPE_VECTOR2I else 0
	var solid = town.data.get("solidP", [])
	var search_s := float(cfg.get("search_s", DEFAULT_SEARCH_S))
	for i in objs.size():
		var o: Dictionary = objs[i]
		var k := String(o.get("kind", ""))
		if not chance.has(k) or not bool(o.get("solid", false)) or int(o.get("in", -1)) >= 0:
			continue
		var w := maxi(1, int(o.get("w", 1)))
		var h := maxi(1, int(o.get("h", 1)))
		var cx := float(o.cx)
		var cy := float(o.cy)
		var rect := Rect2i(roundi(cx - float(w) / 2.0), roundi(cy - float(h) / 2.0), w, h)
		out.append({
			"id": "%s%d" % [ID_PREFIX, i], "house": -1, "room": -1, "pos": stand_tile(rect, solid, W, H, cx), "at": Vector2(cx, cy), "kind": k,
			"name": "wreck" if k == "car_wreck" else "car", "loot": roll(seed_v, i, k), "search_s": search_s, "car": true, "rect": rect, "obj": i, "piece": "o%d" % i,
		})
	return out


## What car number `index` of kind `kind` holds in a town of this seed: {stock: n}, mostly {}.
static func roll(seed_v: int, index: int, kind: String) -> Dictionary:
	var cfg := config()
	var loot := {}
	var chance = cfg.get("chance", {})
	var table = cfg.get("table", {})
	if typeof(chance) != TYPE_DICTIONARY or typeof(table) != TYPE_DICTIONARY or (table as Dictionary).is_empty():
		return loot
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_v * 1000003 + index * 7919 + 4242)
	if rng.randf() >= float(chance.get(kind, 0.0)):
		return loot
	var keys: Array = (table as Dictionary).keys()
	keys.sort()
	var items := 2 if rng.randf() < float(cfg.get("second", 0.0)) else 1
	for _n in items:
		var sum := 0.0
		for key in keys:
			if not loot.has(key):
				sum += float(table[key].get("w", 1.0))
		if sum <= 0.0:
			break
		var at := rng.randf() * sum
		var pick := ""
		for key in keys:
			if loot.has(key):
				continue
			at -= float(table[key].get("w", 1.0))
			pick = String(key)
			if at < 0.0:
				break
		var range_n = table[pick].get("n", [1, 1])
		loot[pick] = rng.randi_range(int(range_n[0]), int(range_n[1]))
	return loot


## A free tile beside a car (south side first, the nearest to its middle), from the people's solid grid; the tile south of its middle when nothing is free (or there is no grid).
static func stand_tile(rect: Rect2i, solid, W: int, H: int, cx: float) -> Vector2:
	var fallback := Vector2(cx, float(rect.end.y) + 0.5)
	if W <= 0 or H <= 0 or not (solid is Array or solid is PackedByteArray or solid is PackedInt32Array) or solid.size() < W * H:
		return fallback
	var best := fallback
	var best_score := INF
	for y in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			if rect.has_point(Vector2i(x, y)) or x < 0 or y < 0 or x >= W or y >= H:
				continue
			if (x == rect.position.x - 1 or x == rect.end.x) and (y == rect.position.y - 1 or y == rect.end.y):
				continue    # (the corners are no place to stand at it)
			if int(solid[y * W + x]) != 0:
				continue
			var south := 0.0 if y >= rect.end.y and x >= rect.position.x and x < rect.end.x else 100.0
			var score := south + absf(float(x) + 0.5 - cx)
			if score < best_score:
				best_score = score
				best = Vector2(float(x) + 0.5, float(y) + 0.5)
	return best
