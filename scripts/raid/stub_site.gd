## TODO-SITEGEN: a stand-in for the site generator (scripts/raid/site_gen.gd, the SITES builder's) until that exists.
## main.gd's `open_raid` uses SiteGen when its file is there and this when it is not; delete this file (and the
## fallback in `open_raid`) once site_gen.gd has landed. One layout for every kind of place: a street along the foot of
## the map, a house across the middle with a wall all round and a door in its south wall, four things to search inside
## (real props of the base map, moved), a few of the dead in and about it. The same place, seed and squad make the same
## site. The contract of a site is in docs/superpowers/plans/2026-10-02-round-14.md.
extends RefCounted

const GD := preload("res://scripts/game_data.gd")

const W := 44
const H := 30
## The house: x 12 to 33, y 3 to 15 (its wall is the outer ring of tiles), the door in the south wall at x 17.
const HOUSE := Rect2i(12, 3, 22, 13)
const DOOR_X := 17
## What there is to search, in the order they are laid out: the prop's kind and where its middle is.
const THINGS := [["shelf", Vector2(17.0, 5.2)], ["cabinet", Vector2(30.5, 5.6)], ["crate", Vector2(28.0, 12.5)], ["fridge", Vector2(14.2, 11.8)]]
const SEARCH_S := {"shelf": 6.0, "cabinet": 4.0, "crate": 5.0, "fridge": 7.0}


static func make(place: Dictionary, seed_value: int, squad_size: int, by_vehicle: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base: Dictionary = GD.load_all()
	var data: Dictionary = base.duplicate(true)
	var terrain: Array = []
	var solid: Array = []
	for y in H:
		for x in W:
			var inside: bool = HOUSE.has_point(Vector2i(x, y))
			var wall: bool = inside and (x == HOUSE.position.x or x == HOUSE.end.x - 1 or y == HOUSE.position.y or y == HOUSE.end.y - 1) and not (x == DOOR_X and y == HOUSE.end.y - 1)
			var tile := 1 if y >= H - 8 else (2 if y >= H - 10 else 4)
			if inside:
				tile = 12 if wall else 8
			if y == HOUSE.end.y - 1 and x == DOOR_X:
				tile = 2
			terrain.append(tile)
			solid.append(1 if wall else 0)
	var objects: Array = []
	var containers: Array = []
	var loot_total := _loot_total(place)
	var i := 0
	for thing in THINGS:
		var o := _prop(base, String(thing[0]), thing[1])
		if o.is_empty():
			continue
		objects.append(o)
		var c: Vector2 = thing[1]
		var stand := Vector2(floorf(c.x) + 0.5, floorf(c.y + float(o.h) / 2.0 - 0.001) + 1.5)
		if bool(o.solid):
			for ty in range(floori(float(o.cy) - float(o.h) / 2.0), floori(float(o.cy) + float(o.h) / 2.0 - 0.001) + 1):
				for tx in range(floori(float(o.cx) - float(o.w) / 2.0), floori(float(o.cx) + float(o.w) / 2.0 - 0.001) + 1):
					solid[ty * W + tx] = 1
		containers.append({"id": "c%d" % i, "pos": stand, "at": Vector2(float(o.cx), float(o.cy)), "kind": String(thing[0]), "loot": {}, "search_s": float(SEARCH_S.get(String(thing[0]), 5.0)), "room": "house"})
		i += 1
	# the loot is shared among the containers, the first stock to the first, and so on
	var stocks: Array = loot_total.keys()
	for k in stocks.size():
		var share: int = int(loot_total[stocks[k]])
		for j in containers.size():
			var part: int = share / containers.size() + (1 if j < share % containers.size() else 0)
			if part > 0:
				containers[(j + k) % containers.size()].loot[stocks[k]] = int(containers[(j + k) % containers.size()].loot.get(stocks[k], 0)) + part
	data["W"] = W
	data["H"] = H
	data["terrain"] = terrain
	data["solidZ"] = solid.duplicate()
	data["solidP"] = solid.duplicate()
	data["objects"] = objects
	data["walls"] = []
	data["marks"] = []
	data["lights"] = []
	data["trees"] = []
	data["segments"] = []
	data["people"] = []
	data["spawns"] = []
	var danger := int(place.get("danger", 1))
	var dead: Array = []
	for n in 6 + 4 * danger:
		var at := Vector2(rng.randf_range(HOUSE.position.x + 2.0, HOUSE.end.x - 2.0), rng.randf_range(HOUSE.position.y + 2.0, HOUSE.end.y - 3.0)) if n % 3 != 0 else Vector2(rng.randf_range(20.0, W - 4.0), rng.randf_range(H - 7.0, H - 2.0))
		dead.append({"pos": at.floor() + Vector2(0.5, 0.5), "kind": "runner" if (danger >= 2 and n % 4 == 1) else "walker", "state": "still" if n % 5 != 0 else "wander"})
	return {
		"name": String(place.get("name", "A place")), "kind": String(place.get("kind", "houses")), "danger": danger, "size": Vector2i(W, H), "data": data,
		"entry": Vector2(6.5, H - 5.5), "entry_spread": 0.9, "exit": Rect2(1.0, H - 8.5, 10.0, 6.5),
		"vehicle_spot": Vector2(8.5, H - 3.4) if by_vehicle else Vector2(-1, -1),
		"containers": containers, "dead": dead, "rooms": [{"name": "house", "rect": Rect2(HOUSE.position.x + 1, HOUSE.position.y + 1, HOUSE.size.x - 2, HOUSE.size.y - 2)}], "seed": seed_value,
	}


## What the place holds, each stock at the top of its span (the dice's best), as whole numbers.
static func _loot_total(place: Dictionary) -> Dictionary:
	var out := {}
	var loot: Dictionary = place.get("loot", {})
	for k in loot:
		out[String(k)] = int(loot[k][1]) if loot[k] is Array else int(loot[k])
	if out.is_empty():
		out["food"] = 10
	return out


## A prop of the base map of this kind, moved so that its middle is at `at`; {} when the map has none.
static func _prop(base: Dictionary, kind: String, at: Vector2) -> Dictionary:
	for o in base.objects:
		if String(o.kind) != kind or o.get("states") != null:
			continue
		var c: Dictionary = o.duplicate(true)
		var d := at - Vector2(float(o.cx), float(o.cy))
		c["cx"] = at.x
		c["cy"] = at.y
		for p in c.pieces:
			p["x"] = float(p.x) + d.x
			p["y"] = float(p.y) + d.y
		return c
	return {}
