## The sites of the played trips (round 14): `SiteGen.make(place, seed, squad_size, by_vehicle)` draws the small map of
## one place of the town (a street of houses, a pharmacy, a gas station, a farm...) from its layout in
## assets/data/site_layouts.json, puts the place's loot in containers on it and its dead about it, and gives back the
## site that `RaidRun` plays and `RaidScene` shows:
##
##   {"name", "kind", "size": Vector2i, "data": a map in the schema of assets/data/map.json (see scripts/world.gd),
##    "entry": Vector2, "entry_spread": float, "exit": Rect2, "vehicle_spot": Vector2 (or (-1, -1)),
##    "containers": [{"id", "pos", "at", "kind", "loot", "search_s", "room"}],
##    "dead": [{"pos", "kind", "state"}], "rooms": [{"name", "rect"}], "seed": int, "danger": int}
##
## The same place, seed and arguments always give the same site. The loot of all the containers adds up to what the
## dice would give the place at its best (the top of each span of its `loot`) times 0.8 + 0.1 x its danger, plus its
## `extra` stocks, each rolled once. The dead are 8 + 5 for each point of danger + 3 for each point of the nest's
## strength: a quarter runners from danger 2, one or two brutes at danger 3, the rest walkers; two or three stand by
## the entry and the others are 8 tiles or more away.
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const Canvas := preload("res://scripts/raid/site_canvas.gd")

const LAYOUTS_PATH := "res://assets/data/site_layouts.json"
const STOCKS := ["food", "water", "scrap", "ammo", "meds", "fuel"]
## How near the entry the dead may stand but for the few meant for the arrival.
const NEAR_ENTRY := 11.0
## Share of the dead that wander (the others stand until they notice).
const WANDER_SHARE := 0.22
## The share of the dead that are runners from this danger on.
const RUNNER_SHARE := 0.25
const RUNNER_FROM_DANGER := 2
const BRUTE_FROM_DANGER := 3

static var _layouts: Dictionary = {}


static func layouts() -> Dictionary:
	if _layouts.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(LAYOUTS_PATH))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Could not read %s" % LAYOUTS_PATH)
			return {}
		_layouts = parsed
	return _layouts


## The layout a place is drawn from: one made for that very place (the truck stop, the terraces), else the one of its
## kind, else the one of what its kind is like (a hospital is a clinic), else the generic one.
static func recipe_name(place: Dictionary) -> String:
	var lay := layouts()
	var recipes: Dictionary = lay.recipes
	var id := String(place.get("id", ""))
	if recipes.has(id):
		return id
	var kind := String(place.get("kind", ""))
	if recipes.has(kind):
		return kind
	var alias := String(lay.get("aliases", {}).get(kind, ""))
	if alias != "" and recipes.has(alias):
		return alias
	return "generic"


## The stocks the place's loot would give at its best, scaled by its danger: {stock: int}.
static func loot_base(place: Dictionary) -> Dictionary:
	var scale := 0.8 + 0.1 * float(int(place.get("danger", 1)))
	var out := {}
	var loot: Dictionary = place.get("loot", {})
	for k in STOCKS:
		if loot.has(k):
			var span: Array = loot[k]
			var top := int(span[1])
			var amount := roundi(float(top) * scale)
			if amount > 0:
				out[k] = amount
	return out


## What the place's extras add when the dice come up (the amounts, whatever the dice): {stock: [chance, amount]}.
static func loot_extras(place: Dictionary) -> Dictionary:
	var out := {}
	var extra: Dictionary = place.get("extra", {})
	for k in STOCKS:
		if extra.has(k):
			var pair: Array = extra[k]
			out[k] = [float(pair[0]), int(pair[1])]
	return out


## How many dead a place has: {"walker", "runner", "brute"} (the brutes are one or two at danger 3, by the dice).
static func dead_counts(place: Dictionary, dice: RandomNumberGenerator) -> Dictionary:
	var danger := int(place.get("danger", 1))
	var nest: int = int(place.get("nest", {}).get("strength", 0)) if place.get("nest") is Dictionary else 0
	var total := 8 + 5 * danger + 3 * nest
	if bool(place.get("cleared", false)):
		return {"walker": 2, "runner": 0, "brute": 0}    # a cleared place: a couple of strays
	var brutes := 0
	if danger >= BRUTE_FROM_DANGER:
		brutes = 1 + (dice.randi() & 1)
	var runners := 0
	if danger >= RUNNER_FROM_DANGER:
		runners = roundi(RUNNER_SHARE * float(total))
	return {"walker": total - brutes - runners, "runner": runners, "brute": brutes}


static func _hash(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return h


# ------------------------------------------------------------------- make --

static func make(place: Dictionary, seed: int, squad_size: int, by_vehicle: bool) -> Dictionary:
	var lay := layouts()
	var rname := recipe_name(place)
	var recipe: Dictionary = lay.recipes[rname]
	var size: Array = recipe.size
	var W := int(size[0])
	var H := int(size[1])
	var base := GD.load_all()
	var terrain_types: Dictionary = base.terrainTypes.duplicate(true)
	for k in lay.terrain:
		terrain_types[k] = {"id": int(lay.terrain[k].id), "file": String(lay.terrain[k].file)}
	var tids := {}
	for k in terrain_types:
		tids[k] = int(terrain_types[k].id)
	var key := _hash("%s|%d" % [String(place.get("id", "")), seed])

	var cv := Canvas.new()
	cv.setup(W, H, key, lay.props, tids, lay.get("templates", {}))
	cv.danger = int(place.get("danger", 1))
	cv.flags = {
		"vehicle": String(place.get("vehicle", "")) != "",
		"nest": place.get("nest") is Dictionary and int(place.nest.get("strength", 0)) > 0,
		"survivor": bool(place.get("survivor", false)),
	}
	cv.run(recipe)
	if bool(recipe.get("mirror", true)) and (_hash("mirror|%d" % key) & 1) == 1:
		cv.mirror()

	var reach := cv.flood()
	var loot_rng := RandomNumberGenerator.new()
	loot_rng.seed = _hash("loot|%d" % key)
	var dead_rng := RandomNumberGenerator.new()
	dead_rng.seed = _hash("dead|%d" % key)

	var containers := _containers(cv, reach, place, recipe, lay, loot_rng)
	var entry := Vector2(float(cv.entry.x) + 0.5, float(cv.entry.y) + 0.5)
	var dead := _dead(cv, reach, place, recipe, entry, containers, dead_rng)

	# the squad's way out: the road's mouth round the entry
	var half := 3 + maxi(0, squad_size - 3)
	var exit_rect := Rect2(float(cv.entry.x - half), float(H - 5), float(2 * half + 1), 5.0)
	var side := 1.0 if float(cv.entry.x) < float(W) / 2.0 else -1.0
	var spot := Vector2(-1.0, -1.0)
	if by_vehicle:
		spot = Vector2(entry.x + side * 5.0, float(H) - 4.0)

	var rooms: Array = []
	var rooms_dict := {}
	for a in cv.areas:
		if not bool(a.indoor):
			continue
		var r: Rect2i = a.rect
		rooms.append({"name": String(a.name), "rect": Rect2(float(r.position.x), float(r.position.y), float(r.size.x), float(r.size.y))})
		var nm := String(a.name)
		var n := 2
		while rooms_dict.has(nm):
			nm = "%s_%d" % [String(a.name), n]
			n += 1
		rooms_dict[nm] = [r.position.x, r.position.y, r.end.x, r.end.y]

	var data := _data(base, cv, terrain_types, rooms_dict, entry, W, H)
	return {
		"name": String(place.get("name", rname)),
		"kind": String(place.get("kind", "")),
		"size": Vector2i(W, H),
		"data": data,
		"entry": entry,
		"entry_spread": 0.9,
		"exit": exit_rect,
		"vehicle_spot": spot,
		"containers": containers,
		"dead": dead,
		"rooms": rooms,
		"seed": seed,
		"danger": int(place.get("danger", 1)),
	}


## The map dictionary the world and the rules are built from: the base data (the pawns, the guns, the sounds...) with
## the map fields replaced by the site's.
static func _data(base: Dictionary, cv, terrain_types: Dictionary, rooms: Dictionary, entry: Vector2, W: int, H: int) -> Dictionary:
	var d := base.duplicate(false)
	d["W"] = W
	d["H"] = H
	d["terrainTypes"] = terrain_types
	d["terrain"] = Array(cv.terrain)
	var shut := Array(cv.solid)
	d["solidZ"] = shut
	d["solidP"] = shut.duplicate()
	var zeros: Array = []
	zeros.resize(W * H)
	zeros.fill(0)
	d["wall"] = zeros
	var objs: Array = cv.objects.duplicate()
	objs.sort_custom(func(a, b):
		var ka: float = float(a.layer) * 1000.0 + float(a.cy) + float(a.h) / 2.0
		var kb: float = float(b.layer) * 1000.0 + float(b.cy) + float(b.h) / 2.0
		if ka != kb:
			return ka < kb
		return int(a.id) < int(b.id))
	for i in objs.size():
		objs[i]["id"] = i
		objs[i]["order"] = i
	d["objects"] = objs
	d["marks"] = cv.marks
	d["walls"] = []
	d["segments"] = []
	d["trees"] = cv.trees
	d["lights"] = []
	d["rooms"] = rooms
	d["spawns"] = []
	d["yard"] = [1, 1, W - 1, H - 1]
	d["workshop"] = {"x": entry.x, "y": entry.y - 1.0, "what": "At the road"}
	d["people"] = []
	d["bonds"] = []
	return d


# -------------------------------------------------------------- containers --

## The container candidates that can be stood at, given loot: which stay, what each holds, how long it takes.
static func _containers(cv, reach: PackedByteArray, place: Dictionary, recipe: Dictionary, lay: Dictionary, rng: RandomNumberGenerator) -> Array:
	var targets := loot_base(place)
	for k in loot_extras(place):
		var pair: Array = loot_extras(place)[k]
		if rng.randf() < float(pair[0]):
			targets[k] = int(targets.get(k, 0)) + int(pair[1])
	for k in targets.keys():
		if int(targets[k]) <= 0:
			targets.erase(k)
	# the ones that can be reached
	var usable: Array = []
	for c in cv.cands:
		var pos := _stand_tile(cv, reach, c, rng)
		if pos.x < 0:
			continue
		var entry := {"c": c, "pos": pos}
		usable.append(entry)
	var out: Array = []
	if targets.is_empty() or usable.is_empty():
		return out
	var affinity: Dictionary = lay.affinity
	var caps: Dictionary = lay.caps
	# how many containers the loot calls for
	var want := 0.0
	for k in targets:
		want += float(targets[k]) / float(caps.get(k, 5))
	var bounds: Array = recipe.get("containers", [4, 14])
	var n := clampi(ceili(want), int(bounds[0]), int(bounds[1]))
	n = mini(n, usable.size())
	# one for each stock first, the best fit; then the rest as the dice go
	var chosen: Array = []
	for k in targets:
		var best = null
		var best_w := 0.0
		for e in usable:
			if chosen.has(e):
				continue
			var w := _fit(e.c, k, affinity) * rng.randf_range(0.8, 1.2)
			if w > best_w:
				best_w = w
				best = e
		if best != null and chosen.size() < n:
			chosen.append(best)
	while chosen.size() < n:
		var pool: Array = []
		var weights: Array = []
		for e in usable:
			if chosen.has(e):
				continue
			var w := 0.0
			for k in targets:
				w += _fit(e.c, k, affinity)
			pool.append(e)
			weights.append(maxf(w, 0.05) * float(e.c.w))
		if pool.is_empty():
			break
		chosen.append(pool[_weighted(weights, rng)])
	# split each stock among them
	var shares: Array = []
	for e in chosen:
		shares.append({})
	for k in targets:
		var weights: Array = []
		var total := 0.0
		for e in chosen:
			var w := _fit(e.c, k, affinity) * rng.randf_range(0.6, 1.4)
			weights.append(w)
			total += w
		if total <= 0.0:
			weights.clear()
			for e in chosen:
				weights.append(1.0)
		var parts := _split(int(targets[k]), weights)
		for i in chosen.size():
			if parts[i] > 0:
				shares[i][k] = parts[i]
	var kept: Array = []
	for i in chosen.size():
		if not shares[i].is_empty():
			kept.append({"e": chosen[i], "loot": shares[i]})
	kept.sort_custom(func(a, b):
		var pa: Vector2i = a.e.pos
		var pb: Vector2i = b.e.pos
		if pa.y != pb.y:
			return pa.y > pb.y
		return pa.x < pb.x)
	var search: Dictionary = lay.search
	for i in kept.size():
		var e: Dictionary = kept[i].e
		var c: Dictionary = e.c
		var loot: Dictionary = kept[i].loot
		var units := 0.0
		for k in loot:
			units += float(loot[k]) / float(caps.get(k, 5))
		var secs := float(search.get(c.kind, 5.0)) + minf(2.0, units * 0.6) + rng.randf_range(-0.5, 0.8)
		out.append({
			"id": "c%d" % i,
			"pos": Vector2(float(e.pos.x) + 0.5, float(e.pos.y) + 0.5),
			"at": Vector2(float(c.obj.cx), float(c.obj.cy)),
			"kind": String(c.kind),
			"loot": loot,
			"search_s": clampf(snappedf(secs, 0.5), 3.0, 9.0),
			"room": _room_of(cv, c),
		})
	return out


static func _room_of(cv, c: Dictionary) -> String:
	var name: String = cv.area_at(int(c.tx), int(c.ty))
	if name == "":
		name = "outside"
	return name


## How well a container's kind holds a stock (0 when it would not).
static func _fit(c: Dictionary, stock: String, affinity: Dictionary) -> float:
	if c.has("only") and not (stock in c.only):
		return 0.0
	var table: Dictionary = affinity.get(stock, {})
	return float(table.get(c.kind, 0.0))


static func _weighted(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var at := rng.randf() * total
	for i in weights.size():
		at -= float(weights[i])
		if at < 0.0:
			return i
	return weights.size() - 1


## A whole amount split in proportion to weights, the parts adding up to the amount exactly.
static func _split(amount: int, weights: Array) -> Array:
	var total := 0.0
	for w in weights:
		total += float(w)
	var parts: Array = []
	var fracs: Array = []
	var given := 0
	for w in weights:
		var exact := float(amount) * float(w) / total
		var part := int(floor(exact))
		parts.append(part)
		fracs.append(exact - float(part))
		given += part
	var left := amount - given
	while left > 0:
		var best := 0
		for i in fracs.size():
			if fracs[i] > fracs[best]:
				best = i
		parts[best] += 1
		fracs[best] = -1.0
		left -= 1
	return parts


## The open tile beside a prop where a person stands to search it: reachable on foot, with the most room round it.
static func _stand_tile(cv, reach: PackedByteArray, c: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var W: int = cv.W
	var tx: int = c.tx
	var ty: int = c.ty
	var tw: int = c.tw
	var th: int = c.th
	var options: Array = []
	for x in tw:
		options.append(Vector2i(tx + x, ty - 1))
		options.append(Vector2i(tx + x, ty + th))
	for y in th:
		options.append(Vector2i(tx - 1, ty + y))
		options.append(Vector2i(tx + tw, ty + y))
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	for p in options:
		if not cv.is_open(p.x, p.y) or reach[p.y * W + p.x] == 0:
			continue
		var score := rng.randf() * 0.5
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if cv.is_open(p.x + dx, p.y + dy):
					score += 1.0
		if score > best_score:
			best_score = score
			best = p
	return best


# --------------------------------------------------------------------- dead --

static func _dead(cv, reach: PackedByteArray, place: Dictionary, recipe: Dictionary, entry: Vector2, containers: Array, rng: RandomNumberGenerator) -> Array:
	var W: int = cv.W
	var H: int = cv.H
	var counts := dead_counts(place, rng)
	var total: int = int(counts.walker) + int(counts.runner) + int(counts.brute)
	var kinds: Array = []
	for k in ["brute", "runner", "walker"]:
		for i in int(counts[k]):
			kinds.append(k)
	var pos_taken: Array = []
	var stand: Dictionary = {}
	for c in containers:
		stand[Vector2i(int(c.pos.x), int(c.pos.y))] = true
	# which place each open reachable tile belongs to
	var zones: Array = []
	var zone_tiles: Array = []
	for i in cv.areas.size():
		zones.append(cv.areas[i])
		zone_tiles.append([])
	var loose: Array = []
	for y in H:
		for x in W:
			if reach[y * W + x] == 0 or cv.keep[y * W + x] != 0 or stand.has(Vector2i(x, y)):
				continue
			var found := -1
			var p := Vector2i(x, y)
			for i in range(cv.areas.size() - 1, -1, -1):
				if cv.areas[i].rect.has_point(p):
					found = i
					break
			if found >= 0:
				zone_tiles[found].append(p)
			else:
				loose.append(p)
	var indoor: Array = []
	var indoor_w: Array = []
	var outdoor: Array = []
	var outdoor_w: Array = []
	for i in zones.size():
		var n: int = zone_tiles[i].size()
		if n == 0:
			continue
		if bool(zones[i].indoor):
			indoor.append(i)
			indoor_w.append(float(zones[i].dead) * float(n))
		else:
			outdoor.append(i)
			outdoor_w.append(float(zones[i].dead) * float(n) * 0.5)
	if not loose.is_empty():
		outdoor.append(-1)
		outdoor_w.append(float(loose.size()) * 0.2)
	var out: Array = []
	var inside_share := float(recipe.get("dead_inside", 0.55))
	# the ones meant for the arrival: two, or three at a place of more than a little danger
	var arrivals := 3 if int(place.get("danger", 1)) >= 2 else 2
	var arrive_tiles: Array = []
	for y in range(maxi(0, int(entry.y) - 12), H):
		for x in range(maxi(0, int(entry.x) - 12), mini(W, int(entry.x) + 13)):
			if reach[y * W + x] == 0:
				continue
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(entry)
			if d >= 7.8 and d <= 10.6:
				arrive_tiles.append(Vector2i(x, y))
	for i in arrivals:
		if arrive_tiles.is_empty() or kinds.is_empty():
			break
		var spot := Vector2(-1.0, -1.0)
		for t in 30:
			var tile: Vector2i = arrive_tiles[rng.randi() % arrive_tiles.size()]
			var cand := Vector2(float(tile.x) + rng.randf_range(0.25, 0.75), float(tile.y) + rng.randf_range(0.25, 0.75))
			var dist := cand.distance_to(entry)
			if dist >= 7.8 and dist < NEAR_ENTRY - 0.2 and _clear_of(cand, pos_taken, 2.5):
				spot = cand
				break
		if spot.x < 0.0:
			continue
		var kind := _take_kind(kinds, "walker")
		pos_taken.append(spot)
		out.append({"pos": spot, "kind": kind, "state": "still"})
	# the rest: the brutes first, in the roomiest places; a fixed share of them indoors, in the rooms by their size
	var rest := kinds.size()
	var in_n := roundi(inside_share * float(rest)) if not indoor.is_empty() else 0
	var modes: Array = []
	for i in rest:
		modes.append(i < in_n)
	for i in range(modes.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var tmp = modes[i]
		modes[i] = modes[k]
		modes[k] = tmp
	for mode in modes:
		var kind: String = kinds[0]
		var placed := false
		var tries := 0
		while not placed and tries < 160:
			tries += 1
			var in_house: bool = bool(mode) if tries < 80 else not bool(mode)
			var zlist: Array = indoor if in_house else outdoor
			var wlist: Array = indoor_w if in_house else outdoor_w
			if zlist.is_empty():
				zlist = indoor if not indoor.is_empty() else outdoor
				wlist = indoor_w if not indoor.is_empty() else outdoor_w
			if zlist.is_empty():
				break
			var zi: int = zlist[_weighted(wlist, rng)]
			var tiles: Array = loose if zi < 0 else zone_tiles[zi]
			var tile: Vector2i = tiles[rng.randi() % tiles.size()]
			var cand := Vector2(float(tile.x) + rng.randf_range(0.25, 0.75), float(tile.y) + rng.randf_range(0.25, 0.75))
			if cand.distance_to(entry) < NEAR_ENTRY + 0.3:
				continue
			var spacing := 1.8 if tries < 100 else 1.1
			if not _clear_of(cand, pos_taken, spacing):
				continue
			if kind == "brute" and not _roomy(cv, tile):
				continue
			placed = true
			kinds.remove_at(0)
			pos_taken.append(cand)
			out.append({"pos": cand, "kind": kind, "state": "still"})
	# a share of them wander (the first of the arrival always does), the rest stand until they notice
	var wanderers := maxi(1, roundi(WANDER_SHARE * float(out.size())))
	var order: Array = range(out.size())
	for i in range(order.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[k]
		order[k] = tmp
	var first := 0
	for i in wanderers:
		var idx: int = first if i == 0 else int(order[i])
		out[idx]["state"] = "wander"
	return out


static func _take_kind(kinds: Array, want: String) -> String:
	var i := kinds.find(want)
	if i < 0:
		i = kinds.size() - 1
	var k: String = kinds[i]
	kinds.remove_at(i)
	return k


static func _clear_of(p: Vector2, taken: Array, d: float) -> bool:
	for q in taken:
		if p.distance_to(q) < d:
			return false
	return true


static func _roomy(cv, tile: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not cv.is_open(tile.x + dx, tile.y + dy):
				return false
	return true
