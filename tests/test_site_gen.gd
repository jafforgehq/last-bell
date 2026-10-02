extends "res://tests/case.gd"
## The sites of the played trips (round 14, scripts/raid/site_gen.gd, assets/data/site_layouts.json): the small map
## drawn for a place of the town. These tests walk every place of assets/data/town.json (whatever kinds the data has
## by now) through several seeds and both ways of arriving, and say the site is what the plan promised: every key,
## a map the world and the rules can be built from, containers that can be reached on foot and hold what the place's
## loot says, the dead by the rules, and the same site for the same inputs.

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")

const KEYS := ["name", "kind", "size", "data", "entry", "exit", "vehicle_spot", "containers", "dead", "rooms", "seed"]
const CONTAINER_KINDS := ["shelf", "crate", "cabinet", "fridge", "locker", "trunk", "pump", "counter", "bin"]
const STOCKS := ["food", "water", "scrap", "ammo", "meds", "fuel"]
const SEEDS := [1, 2, 3]

## Sites made once and kept for the next test of the same process: (place id, seed, squad, vehicle) to the site.
static var _made := {}


## The Sim of a raid without the colony's wall sections to seed the yard from.
class StubSim:
	extends "res://scripts/sim/sim.gd"

	func _seed() -> void:
		pass


func _places() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town.json"))
	return parsed.places


func _site(place: Dictionary, seed_value: int, squad: int = 3, vehicle: bool = false) -> Dictionary:
	var key := "%s|%d|%d|%s" % [String(place.id), seed_value, squad, str(vehicle)]
	if not _made.has(key):
		_made[key] = SiteGen.make(place, seed_value, squad, vehicle)
	return _made[key]


func _flood(site: Dictionary) -> PackedByteArray:
	var d: Dictionary = site.data
	var W := int(d.W)
	var H := int(d.H)
	var seen := PackedByteArray()
	seen.resize(W * H)
	var e: Vector2 = site.entry
	var start := int(e.y) * W + int(e.x)
	if int(d.solidP[start]) != 0:
		return seen
	var q: Array = [start]
	seen[start] = 1
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var x := i % W
		@warning_ignore("integer_division")
		var y := i / W
		for dd in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = x + dd[0]
			var ny: int = y + dd[1]
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if seen[j] == 0 and int(d.solidP[j]) == 0:
				seen[j] = 1
				q.append(j)
	return seen


func _id_of(v: Vector2) -> int:
	return floori(v.y) * 1000 + floori(v.x)


# ------------------------------------------------------------------ layouts --

func test_every_place_of_the_town_has_a_layout_of_its_own_kind() -> void:
	var lay := SiteGen.layouts()
	check(lay.has("recipes") and lay.recipes.has("generic"), "there is a generic layout")
	for p in _places():
		var name := SiteGen.recipe_name(p)
		check(lay.recipes.has(name), "%s: its layout '%s' exists" % [p.id, name])
		check(name != "generic", "%s (a %s) has a layout made for it, not the generic one" % [p.id, p.kind])
	eq(SiteGen.recipe_name({"id": "nowhere", "kind": "moon_base"}), "generic", "a kind nobody planned for gets the generic layout")


func test_the_generic_layout_makes_a_site_from_the_loot_alone() -> void:
	var place := {"id": "moon", "name": "Moon base", "kind": "moon_base", "danger": 2, "loot": {"meds": [4, 8], "ammo": [30, 60]}, "extra": {}}
	var site := SiteGen.make(place, 5, 3, false)
	check(site.containers.size() >= 2, "the generic site has containers (%d)" % site.containers.size())
	var meds := 0
	var ammo := 0
	for c in site.containers:
		meds += int(c.loot.get("meds", 0))
		ammo += int(c.loot.get("ammo", 0))
	eq(meds, roundi(8.0 * 1.0), "its meds")
	eq(ammo, roundi(60.0 * 1.0), "its ammo")


func test_the_wall_and_door_textures_are_in_the_terrain_types_from_20_up() -> void:
	var site := _site(_places()[0], 1)
	var types: Dictionary = site.data.terrainTypes
	var base: Dictionary = GD.load_all().terrainTypes
	for k in ["WALL_BRICK", "WALL_PLASTER", "WALL_METAL", "DOOR_WOOD"]:
		check(types.has(k), "%s is a terrain type" % k)
		if types.has(k):
			check(int(types[k].id) >= 20, "%s has an id from 20 up" % k)
			check(not base.has(k), "the map's own terrain types are untouched (%s)" % k)
			var img := Image.load_from_file(ProjectSettings.globalize_path(String(types[k].file)))
			check(img != null and img.get_width() == 512 and img.get_height() == 512, "%s is a 512 x 512 atlas" % k)
	for k in base:
		check(types.has(k) and int(types[k].id) == int(base[k].id), "the map's terrain %s is still there" % k)
	check(not GD.load_all().terrainTypes.has("WALL_BRICK"), "the shared base data was not changed")


# ----------------------------------------------------------------- the site --

func test_a_site_has_every_key_of_the_contract_with_the_right_types() -> void:
	for p in _places():
		for seed_value in SEEDS:
			var vehicle: bool = seed_value % 2 == 0
			var s := _site(p, seed_value, 3, vehicle)
			var label := "%s seed %d" % [p.id, seed_value]
			for k in KEYS:
				check(s.has(k), "%s: has %s" % [label, k])
			if not s.has("seed"):
				continue
			eq(typeof(s.name), TYPE_STRING, label + ": name")
			eq(s.name, String(p.name), label + ": the place's name")
			eq(s.kind, String(p.kind), label + ": the place's kind")
			eq(typeof(s.size), TYPE_VECTOR2I, label + ": size")
			check(s.size.x >= 40 and s.size.x <= 56 and s.size.y >= 28 and s.size.y <= 40, "%s: size %s is about 40 to 56 by 28 to 40" % [label, str(s.size)])
			eq(typeof(s.data), TYPE_DICTIONARY, label + ": data")
			eq(typeof(s.entry), TYPE_VECTOR2, label + ": entry")
			eq(typeof(s.exit), TYPE_RECT2, label + ": exit")
			eq(typeof(s.vehicle_spot), TYPE_VECTOR2, label + ": vehicle_spot")
			eq(typeof(s.containers), TYPE_ARRAY, label + ": containers")
			eq(typeof(s.dead), TYPE_ARRAY, label + ": dead")
			eq(typeof(s.rooms), TYPE_ARRAY, label + ": rooms")
			eq(s.seed, seed_value, label + ": seed")
			check(not s.rooms.is_empty(), label + ": has rooms (an inside)")
			for r in s.rooms:
				check(typeof(r.name) == TYPE_STRING and typeof(r.rect) == TYPE_RECT2, label + ": a room is {name, rect}")
				check(Rect2(0, 0, s.size.x, s.size.y).encloses(r.rect), "%s: room %s is on the map" % [label, r.name])
			if vehicle:
				check(s.vehicle_spot.x >= 0.0 and s.vehicle_spot.y >= 0.0 and s.vehicle_spot.x < s.size.x and s.vehicle_spot.y < s.size.y, label + ": a vehicle's place on the map")
				check(s.vehicle_spot.distance_to(s.entry) < 9.0, label + ": the vehicle is by the entry")
			else:
				eq(s.vehicle_spot, Vector2(-1, -1), label + ": no vehicle, no spot")


func test_the_data_is_a_map_the_world_can_be_built_from() -> void:
	for p in _places():
		var s := _site(p, 1)
		var d: Dictionary = s.data
		var label := String(p.id)
		var W := int(d.W)
		var H := int(d.H)
		eq(Vector2i(W, H), s.size, label + ": W and H are the size")
		eq(d.terrain.size(), W * H, label + ": terrain")
		eq(d.solidZ.size(), W * H, label + ": solidZ")
		eq(d.solidP.size(), W * H, label + ": solidP")
		var ids := {}
		for k in d.terrainTypes:
			ids[int(d.terrainTypes[k].id)] = k
		var unknown := 0
		var worse := 0
		var shut := 0
		for i in W * H:
			if not ids.has(int(d.terrain[i])):
				unknown += 1
			# the dead are never freer than the people: what shuts a person shuts them
			if int(d.solidP[i]) == 1 and int(d.solidZ[i]) == 0:
				worse += 1
			shut += int(d.solidP[i])
		eq(unknown, 0, label + ": every terrain id is a terrain type")
		eq(worse, 0, label + ": nothing is open to the dead that is shut to the people")
		check(shut > W * H / 10, label + ": there are walls and things in the way (%d of %d)" % [shut, W * H])
		check(shut < W * H * 3 / 4, label + ": and there is room to walk (%d of %d shut)" % [shut, W * H])
		eq(d.segments, [], label + ": no wall sections")
		eq(d.people, [], label + ": nobody of the colony's")
		eq(d.spawns, [], label + ": no spawn points")
		eq(d.walls, [], label + ": no wall pictures")
		for k in ["objects", "marks", "trees", "lights", "rooms", "minPerSec", "zombieLooks", "weapons", "guns", "pawn", "tree", "weaponArt", "sounds"]:
			check(d.has(k), "%s: data has %s" % [label, k])
		for o in d.objects:
			check(not (String(o.kind) in ["walkway", "ladder", "tower", "door"]), "%s: no object of the kind %s (the world would take it for a deck)" % [label, o.kind])
			check(o.get("states") == null, label + ": no object with states (they belong to wall sections)")
			for pc in o.pieces:
				if not ResourceLoader.exists(String(pc.file)):
					failures.append("%s: the picture %s is missing" % [label, pc.file])
					break
		for t in d.trees:
			check(ResourceLoader.exists(String(t.file)), "%s: tree picture %s" % [label, t.file])
		for k in d.terrainTypes:
			check(ResourceLoader.exists(String(d.terrainTypes[k].file)), "%s: terrain picture of %s" % [label, k])


func test_the_world_and_the_rules_can_be_built_from_every_kind() -> void:
	var done := {}
	for p in _places():
		if done.has(p.kind):
			continue
		done[p.kind] = true
		var s := _site(p, 1)
		var world := World.new()
		Engine.get_main_loop().root.add_child(world)
		world.build(s.data)
		eq(world.W, int(s.data.W), "%s: the world's width" % p.kind)
		var e: Vector2 = s.entry
		check(not world.is_solid(world.solid_p, e.x, e.y), "%s: the entry is open in the world" % p.kind)
		var sim := StubSim.new(s.data, world, FxNull.new())
		eq(sim.people.size(), 0, "%s: a sim with no people" % p.kind)
		eq(sim.segments.size(), 0, "%s: no wall sections" % p.kind)
		# the real pathfinder gets from the entry to every container and finds the walls shut
		for c in s.containers:
			var path: Array = sim.path_p.find(world.solid_p, e.x, e.y, c.pos.x, c.pos.y)
			check(not path.is_empty(), "%s: the pathfinder finds a way to %s" % [p.kind, c.id])
		for z in s.dead:
			var path: Array = sim.path_z.find(world.solid_z, e.x, e.y, z.pos.x, z.pos.y)
			check(not path.is_empty(), "%s: a way from the entry to a dead one at %s" % [p.kind, str(z.pos)])
		world.free()


# --------------------------------------------------------------- containers --

func test_every_container_stands_on_open_ground_reachable_on_foot_beside_a_solid_prop() -> void:
	for p in _places():
		for seed_value in SEEDS:
			var s := _site(p, seed_value, 3, seed_value == 2)
			var d: Dictionary = s.data
			var W := int(d.W)
			var reach := _flood(s)
			var label := "%s seed %d" % [p.id, seed_value]
			var ids := {}
			for c in s.containers:
				for k in ["id", "pos", "at", "kind", "loot", "search_s", "room"]:
					check(c.has(k), "%s: a container has %s" % [label, k])
				check(not ids.has(c.id), "%s: container ids are unique (%s)" % [label, c.id])
				ids[c.id] = true
				check(String(c.kind) in CONTAINER_KINDS, "%s: %s is a container kind" % [label, c.kind])
				var pos: Vector2 = c.pos
				var at: Vector2 = c.at
				check(pos.x == floorf(pos.x) + 0.5 and pos.y == floorf(pos.y) + 0.5, "%s: %s's pos is the middle of a tile" % [label, c.id])
				var pi := floori(pos.y) * W + floori(pos.x)
				eq(int(d.solidP[pi]), 0, "%s: %s: the tile to stand on is open" % [label, c.id])
				eq(int(reach[pi]), 1, "%s: %s: it can be reached on foot from the entry" % [label, c.id])
				eq(int(d.solidP[floori(at.y) * W + floori(at.x)]), 1, "%s: %s: its prop is solid" % [label, c.id])
				check(pos.distance_to(at) <= 7.0, "%s: %s: the standing place (%s) is beside the prop (%s)" % [label, c.id, str(pos), str(at)])
				check(float(c.search_s) >= 3.0 and float(c.search_s) <= 9.0, "%s: %s: searching takes 3 to 9 seconds (%s)" % [label, c.id, str(c.search_s)])
				check(not c.loot.is_empty(), "%s: %s holds something" % [label, c.id])
				for k in c.loot:
					check(k in STOCKS and typeof(c.loot[k]) == TYPE_INT and int(c.loot[k]) > 0, "%s: %s holds a whole amount of a stock (%s)" % [label, c.id, str(c.loot)])
				check(String(c.room) != "", "%s: %s is in a room or outside" % [label, c.id])


func test_the_loot_of_all_the_containers_is_what_the_place_would_give_at_its_best() -> void:
	for p in _places():
		var base := SiteGen.loot_base(p)
		var extras := SiteGen.loot_extras(p)
		for seed_value in SEEDS:
			var s := _site(p, seed_value)
			var label := "%s seed %d" % [p.id, seed_value]
			var got := {}
			for c in s.containers:
				for k in c.loot:
					got[k] = int(got.get(k, 0)) + int(c.loot[k])
			# the rule: the top of each span x (0.8 + 0.1 x danger) ...
			var scale := 0.8 + 0.1 * float(int(p.danger))
			for k in p.loot:
				check(base.has(k), "%s: loot_base has %s" % [label, k])
				eq(int(base.get(k, 0)), roundi(float(p.loot[k][1]) * scale), "%s: %s at its best, scaled" % [label, k])
			# ... plus each extra that came up
			for k in got:
				var low := int(base.get(k, 0))
				var amount := int(extras[k][1]) if extras.has(k) else 0
				check(got[k] == low or (amount > 0 and got[k] == low + amount), "%s: %s adds up to %d (or %d with the extra), not %d" % [label, k, low, low + amount, got[k]])
			for k in base:
				check(got.has(k), "%s: the %s the place has is in a container" % [label, k])
			for k in got:
				check(base.has(k) or extras.has(k), "%s: no stock the place does not have (%s)" % [label, k])
			if p.loot.is_empty() and p.extra.is_empty():
				eq(s.containers.size(), 0, "%s: a place with nothing to find has no containers" % label)
			else:
				check(s.containers.size() >= 1, "%s: a place with loot has containers" % label)


func test_a_site_has_as_many_containers_as_its_loot_calls_for() -> void:
	# (a layout whose props could not be reached would give a site with one or two: the loot has to be somewhere)
	var lay := SiteGen.layouts()
	for p in _places():
		var recipe: Dictionary = lay.recipes[SiteGen.recipe_name(p)]
		var base := SiteGen.loot_base(p)
		if base.is_empty():
			continue
		var want := 0.0
		for k in base:
			want += float(base[k]) / float(lay.caps[k])
		var need := mini(int(recipe.containers[0]), ceili(want))
		for seed_value in SEEDS:
			var s := _site(p, seed_value)
			check(s.containers.size() >= need - 1, "%s seed %d: %d containers, the loot calls for %d" % [p.id, seed_value, s.containers.size(), need])


func test_the_extras_come_up_by_their_chances_over_many_seeds() -> void:
	var place := {"id": "extras", "name": "Extras", "kind": "pharmacy", "danger": 1, "loot": {"meds": [6, 10]}, "extra": {"food": [0.5, 4]}}
	var hits := 0
	var n := 80
	for i in n:
		var s := SiteGen.make(place, i + 100, 3, false)
		var food := 0
		for c in s.containers:
			food += int(c.loot.get("food", 0))
		if food == 4:
			hits += 1
		else:
			eq(food, 0, "the extra is all or nothing")
	check(hits > n * 0.25 and hits < n * 0.75, "a half chance came up %d times in %d" % [hits, n])


func test_fuel_is_in_the_pumps_where_there_are_pumps() -> void:
	var seen_pump := false
	for p in _places():
		if not (p.loot.has("fuel") and p.kind in ["gas_station", "fuel_depot"]):
			continue
		var s := _site(p, 1)
		var fuel := 0
		var in_pumps := 0
		for c in s.containers:
			if c.loot.has("fuel"):
				fuel += int(c.loot.fuel)
				if c.kind == "pump":
					in_pumps += int(c.loot.fuel)
		check(fuel > 0, "%s: fuel is found" % p.id)
		check(in_pumps * 2 >= fuel, "%s: most of the fuel (%d of %d) is in the pumps" % [p.id, in_pumps, fuel])
		seen_pump = seen_pump or in_pumps > 0
	check(seen_pump or _places().filter(func(q): return q.loot.has("fuel")).is_empty(), "somewhere there is a pump with fuel")


# --------------------------------------------------------------- the way out --

func test_the_entry_and_the_exit_are_on_open_ground_at_the_edge() -> void:
	for p in _places():
		for squad in [1, 3, 6]:
			var s := _site(p, 2, squad, squad == 6)
			var d: Dictionary = s.data
			var W := int(d.W)
			var H := int(d.H)
			var e: Vector2 = s.entry
			var ex: Rect2 = s.exit
			var label := "%s squad %d" % [p.id, squad]
			eq(int(d.solidP[floori(e.y) * W + floori(e.x)]), 0, label + ": the entry is open")
			check(ex.has_point(e), label + ": the exit takes in the entry")
			check(Rect2(0, 0, W, H).encloses(ex), label + ": the exit is on the map")
			check(ex.end.y >= float(H) - 1.0, label + ": the exit touches the road's edge")
			var shut := 0
			for y in range(floori(ex.position.y), floori(ex.end.y)):
				for x in range(floori(ex.position.x), floori(ex.end.x)):
					shut += int(d.solidP[y * W + x])
			eq(shut, 0, label + ": every tile of the exit is open")
			# room for the whole squad to stand about the entry, in a row
			var members: int = squad
			for i in members:
				var at := e + Vector2(float(i) - float(members - 1) / 2.0, 0.0) * 0.9
				eq(int(d.solidP[floori(at.y) * W + floori(at.x)]), 0, "%s: member %d has open ground to stand on" % [label, i])
			check(float(s.entry_spread) > 0.0, label + ": the squad is spread a little")


func test_a_vehicle_has_open_road_to_stand_on_by_the_entry() -> void:
	for p in _places():
		for seed_value in SEEDS:
			var s := _site(p, seed_value, 3, true)
			var W := int(s.data.W)
			var spot: Vector2 = s.vehicle_spot
			var shut := 0
			for y in range(floori(spot.y - 2.5), ceili(spot.y + 2.5)):
				for x in range(floori(spot.x - 1.5), ceili(spot.x + 1.5)):
					shut += int(s.data.solidP[y * W + x])
			eq(shut, 0, "%s seed %d: room for a vehicle at %s" % [p.id, seed_value, str(spot)])
			# a long one lying along the road (a bus) fits too
			var long_shut := 0
			for y in range(floori(spot.y - 1.5), ceili(spot.y + 1.5)):
				for x in range(floori(spot.x - 5.5), ceili(spot.x + 5.5)):
					long_shut += int(s.data.solidP[y * W + x])
			eq(long_shut, 0, "%s seed %d: and a bus along the road" % [p.id, seed_value])


# ------------------------------------------------------------------- the dead --

func test_the_dead_are_placed_by_the_rules() -> void:
	for p in _places():
		for seed_value in SEEDS:
			var s := _site(p, seed_value)
			var d: Dictionary = s.data
			var W := int(d.W)
			var reach := _flood(s)
			var label := "%s seed %d" % [p.id, seed_value]
			var danger := int(p.danger)
			var nest := int(p.get("nest", {}).get("strength", 0))
			var total := 8 + 5 * danger + 3 * nest
			eq(s.dead.size(), total, label + ": 8 + 5 x danger + 3 x nest dead")
			var kinds := {"walker": 0, "runner": 0, "brute": 0}
			var near := 0
			var still := 0
			var taken := {}
			for z in s.dead:
				check(z.has("pos") and z.has("kind") and z.has("state"), label + ": a dead one has pos, kind and state")
				check(z.kind in kinds, "%s: %s is a kind of the dead" % [label, z.kind])
				check(z.state in ["still", "wander"], "%s: %s is a state" % [label, z.state])
				kinds[z.kind] = int(kinds[z.kind]) + 1
				var pos: Vector2 = z.pos
				var pi := floori(pos.y) * W + floori(pos.x)
				eq(int(d.solidP[pi]), 0, "%s: a dead one on open ground (%s)" % [label, str(pos)])
				eq(int(reach[pi]), 1, "%s: reachable from the entry (%s)" % [label, str(pos)])
				if pos.distance_to(s.entry) < SiteGen.NEAR_ENTRY:
					near += 1
				if z.state == "still":
					still += 1
				check(not taken.has(_id_of(pos)), "%s: two dead ones in a tile (%s)" % [label, str(pos)])
				taken[_id_of(pos)] = true
			check(near >= 2 and near <= 3, "%s: two or three dead by the entry, the rest %s tiles off (%d near)" % [label, str(SiteGen.NEAR_ENTRY), near])
			if danger >= 2:
				eq(kinds.runner, roundi(0.25 * float(total)), label + ": a quarter runners from danger 2")
			else:
				eq(kinds.runner, 0, label + ": no runners below danger 2")
			if danger >= 3:
				check(kinds.brute == 1 or kinds.brute == 2, "%s: one or two brutes at danger 3 (%d)" % [label, kinds.brute])
			else:
				eq(kinds.brute, 0, label + ": no brutes below danger 3")
			check(still * 10 >= s.dead.size() * 6, "%s: most of the dead stand still (%d of %d)" % [label, still, s.dead.size()])


func test_every_room_can_be_walked_into_from_the_entry() -> void:
	for p in _places():
		for seed_value in SEEDS:
			var s := _site(p, seed_value)
			var W := int(s.data.W)
			var reach := _flood(s)
			for r in s.rooms:
				var rect: Rect2 = r.rect
				var open := 0
				var got := 0
				for y in range(floori(rect.position.y), floori(rect.end.y)):
					for x in range(floori(rect.position.x), floori(rect.end.x)):
						if int(s.data.solidP[y * W + x]) == 0:
							open += 1
							got += int(reach[y * W + x])
				check(open > 0, "%s seed %d: the %s has floor to stand on" % [p.id, seed_value, r.name])
				check(got * 10 >= open * 9, "%s seed %d: the %s is open to the entry (%d of %d tiles)" % [p.id, seed_value, r.name, got, open])


func test_the_dead_are_in_the_rooms_and_outside() -> void:
	for p in _places():
		var s := _site(p, 1)
		var inside := 0
		var outside := 0
		for z in s.dead:
			var in_room := false
			for r in s.rooms:
				if (r.rect as Rect2).has_point(z.pos):
					in_room = true
			if in_room:
				inside += 1
			else:
				outside += 1
		check(inside >= 1 and outside >= 1, "%s: dead both in the rooms (%d) and outside (%d)" % [p.id, inside, outside])


# ---------------------------------------------------------------- repeatable --

func test_the_same_inputs_make_the_same_site_and_other_seeds_other_sites() -> void:
	for p in _places():
		var a := SiteGen.make(p, 7, 3, true)
		var b := SiteGen.make(p, 7, 3, true)
		check(var_to_str(a) == var_to_str(b), "%s: the same place, seed and arguments make the same site" % p.id)
		var c := SiteGen.make(p, 8, 3, true)
		check(var_to_str(c.data.terrain) != var_to_str(a.data.terrain) or var_to_str(c.data.objects) != var_to_str(a.data.objects), "%s: another seed makes another site" % p.id)
	# the way of arriving does not change the map, only where the vehicle stands
	var p0: Dictionary = _places()[0]
	var on_foot := SiteGen.make(p0, 4, 3, false)
	var by_car := SiteGen.make(p0, 4, 3, true)
	check(var_to_str(on_foot.data.terrain) == var_to_str(by_car.data.terrain), "the ground is the same on foot or by vehicle")
	check(var_to_str(on_foot.containers) == var_to_str(by_car.containers), "so are the containers")
	check(by_car.vehicle_spot.x >= 0.0 and on_foot.vehicle_spot.x < 0.0, "but the vehicle has its place")


func test_a_site_is_made_quickly() -> void:
	var t0 := Time.get_ticks_msec()
	var n := 0
	for p in _places():
		SiteGen.make(p, 99, 3, false)
		n += 1
	var per := float(Time.get_ticks_msec() - t0) / float(maxi(1, n))
	check(per < 600.0, "a site takes %d ms to make (under 600)" % per)


func test_a_cleared_place_has_only_a_couple_of_strays() -> void:
	var town: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town.json"))
	var place: Dictionary = {}
	for p in town.places:
		if String(p.id) == "supermarket":
			place = p.duplicate(true)
	var s: Dictionary = SiteGen.make(place, 5, 3, false)
	check(s.dead.size() > 10, "an uncleared supermarket has a crowd (%d)" % s.dead.size())
	place["cleared"] = true
	var c: Dictionary = SiteGen.make(place, 5, 3, false)
	eq(c.dead.size(), 2, "a cleared one two strays")
