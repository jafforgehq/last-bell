extends "res://tests/case.gd"
## Saving and loading: a save reloads onto a fresh Sim to the same state, and
## then both play out the same way. The strongest check is to save a busy
## moment, load it, and step both games side by side.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const TMP_A := "user://test_save_a.json"
const TMP_B := "user://test_save_b.json"
## Reading a save back through JSON text loses about 1e-13 of a float (Godot's
## own number parser), so the file round trips are compared to within this.
const FILE_TOL := 1e-6


# ----------------------------------------------------------------- helpers --

## A Sim built the way main.gd builds one for a load: no start_run, so it still
## holds the old demo state (seed walkers already at the wall).
func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


## Runs the rules for `seconds` in coarse steps (10 a second): a cheap way to
## get a game into a state worth saving. The saved games are then played on at
## the usual 30 steps a second.
func _advance(sim, seconds: float) -> void:
	for i in int(seconds * 10.0):
		sim.update(0.1)


func _to_hour(sim, hour: float) -> void:
	var guard := 0
	while absf(fposmod(sim.hour - hour + 12.0, 24.0) - 12.0) > 0.01 and guard < 100000:
		sim.update(0.1)
		guard += 1


func _by_id(sim) -> Dictionary:
	var out := {}
	for p in sim.people:
		out[p.id] = p
	return out


## A game caught at about 21:30 on the first night: walkers at the wall and
## coming in, a section down, someone downed, someone infected, orders in force.
func _rich_night(seed_value: int, difficulty: int) -> Dictionary:
	var g := Helpers.make(seed_value, difficulty)
	var sim = g.sim
	_to_hour(sim, 21.5)
	var ppl := _by_id(sim)
	sim.order_move(ppl.ruth, 40.0, 23.0)
	sim.segments[8].hp = sim.segments[8].max_hp * 0.25
	sim._segment_state(sim.segments[8])
	sim.order_repair(ppl.dez, sim.segments[8])
	var hector = ppl.hector
	hector.hp = 0.0
	sim.medical.on_downed(hector, "bite")
	ppl.walt.infected_at = sim.clock_min
	ppl.walt.turn_at = sim.clock_min + 14.0 * 60.0
	_advance(sim, 8.0)
	sim._damage_segment(sim.segments[3], 1000.0)
	_advance(sim, 2.5)
	return g


## A game caught at 11:00 on the first day with a party out, if the scavenging
## module can send one, and a wall being repaired.
func _rich_day(seed_value: int) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	var ppl := _by_id(sim)
	sim.segments[4].hp = sim.segments[4].max_hp * 0.35
	sim._segment_state(sim.segments[4])
	sim.order_repair(ppl.hector, sim.segments[4])
	sim.order_post(ppl.ruth)
	if sim.scavenge.can_send():
		sim.scavenge.send([ppl.marcus, ppl.walt], "houses")
	_to_hour(sim, 11.0)
	return g


## "" when a and b are the same, else where they first differ. With tol > 0
## numbers are compared to within that (and an int equals a float); with 0
## they must match exactly, type included.
func _diff(a, b, tol: float = 0.0, path: String = "") -> String:
	var ta := typeof(a)
	var tb := typeof(b)
	var a_num: bool = ta == TYPE_INT or ta == TYPE_FLOAT
	var b_num: bool = tb == TYPE_INT or tb == TYPE_FLOAT
	if a_num and b_num:
		if tol > 0.0:
			return "" if absf(float(a) - float(b)) <= tol * maxf(1.0, absf(float(a))) else "%s: %s vs %s" % [path, str(a), str(b)]
		return "" if (ta == tb and a == b) else "%s: %s (type %d) vs %s (type %d)" % [path, str(a), ta, str(b), tb]
	if ta != tb:
		return "%s: type %d vs %d (%s vs %s)" % [path, ta, tb, str(a), str(b)]
	if ta == TYPE_ARRAY:
		if a.size() != b.size():
			return "%s: length %d vs %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := _diff(a[i], b[i], tol, "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if ta == TYPE_DICTIONARY:
		for k in a:
			if not b.has(k):
				return "%s: key %s is missing on the right" % [path, str(k)]
		for k in b:
			if not a.has(k):
				return "%s: key %s is missing on the left" % [path, str(k)]
		for k in a:
			var d := _diff(a[k], b[k], tol, "%s.%s" % [path, str(k)])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s vs %s" % [path, str(a), str(b)]


const ERASE := "<erase>"
const POP := "<pop>"
const EMPTY := "<empty>"


## Sets the value at `path` (keys and indices) inside `data`; see the cases in
## the refusal test. Returns the changed data.
func _change(data: Dictionary, path: Array, value) -> Dictionary:
	if path.is_empty():
		return {} if str(value) == EMPTY else data
	var node = data
	for i in path.size() - 1:
		node = node[path[i]]
	var last = path[path.size() - 1]
	if typeof(value) == TYPE_STRING and value == ERASE:
		node.erase(last)
	elif typeof(value) == TYPE_STRING and value == POP:
		node[last].pop_back()
	else:
		node[last] = value
	return data


## "" when v is plain JSON-safe data, else what is not.
func _not_plain(v, path: String = "") -> String:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return ""
		TYPE_FLOAT:
			return "" if is_finite(v) else "%s: a float that is not finite" % path
		TYPE_ARRAY:
			for i in v.size():
				var d := _not_plain(v[i], "%s[%d]" % [path, i])
				if d != "":
					return d
			return ""
		TYPE_DICTIONARY:
			for k in v:
				if typeof(k) != TYPE_STRING:
					return "%s: a key that is not text (%s)" % [path, str(k)]
				var d := _not_plain(v[k], "%s.%s" % [path, k])
				if d != "":
					return d
			return ""
	return "%s: a %s" % [path, type_string(typeof(v))]


## Compares every variable of two Person or Zombie objects except `skip`.
func _same_fields(a, b, skip: Array, label: String, tol: float = 0.0) -> void:
	for prop in a.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or prop.name in skip:
			continue
		var d := _diff(a.get(prop.name), b.get(prop.name), tol, "%s.%s" % [label, prop.name])
		if d != "":
			failures.append("loaded state differs: %s" % d)


## Which zombie (by index) holds each wall slot, as [section id, slot index, index or -1].
func _slot_holders(sim) -> Array:
	var out: Array = []
	for s in sim.segments:
		for i in s.slots.size():
			out.append([s.id, i, sim.zombies.find(s.slots[i].who) if s.slots[i].who != null else -1])
	return out


func _cleanup() -> void:
	for path in [TMP_A, TMP_B, TMP_A + ".tmp", TMP_B + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# ------------------------------------------------------------------- format --

func test_a_save_is_versioned_plain_json_data() -> void:
	var g := Helpers.make(3, 1)
	Helpers.run(g.sim, 3.0)
	var d := SaveGame.to_dict(g.sim)
	eq(d.get("version"), 1, "version 1")
	for key in ["day", "minutes", "clock_min", "t", "phase", "bell_rung", "spawn_t", "kills", "weather", "over", "stock", "difficulty", "permadeath", "run_seed", "rng_state", "rng_seed", "people", "zombies", "segments", "modules", "alerts"]:
		check(d.has(key), "the save has %s" % key)
	eq(typeof(d.get("rng_state")), TYPE_STRING, "the 64-bit rng state is text")
	eq(d.people.size(), 6, "six people")
	eq(d.segments.size(), 14, "fourteen wall sections")
	eq(d.zombies.size(), g.sim.zombies.size(), "every zombie")
	for name in ["supplies", "medical", "scavenge", "scenario"]:
		check(d.modules.has(name), "the %s module has a place" % name)
	eq(_not_plain(d), "", "only plain data")
	# through real JSON text
	var text := JSON.stringify(d, "", true, true)
	var back = JSON.parse_string(text)
	eq(typeof(back), TYPE_DICTIONARY, "it is JSON")
	eq(_diff(d, back, FILE_TOL), "", "and reads back the same")
	g.world.free()


func test_people_and_zombies_are_saved_in_the_documented_shape() -> void:
	var g := _rich_night(4, 1)
	var sim = g.sim
	var d := SaveGame.to_dict(sim)
	var ruth: Dictionary = {}
	var hector: Dictionary = {}
	for pd in d.people:
		if pd.id == "ruth":
			ruth = pd
		if pd.id == "hector":
			hector = pd
	check(ruth.order is Array and ruth.order.size() == 3, "an order is [x, y, z]: %s" % str(ruth.get("order")))
	eq(ruth.drafted, true, "drafted")
	eq(hector.downed, true, "downed")
	eq(hector.repair, null, "no repair order is null")
	var dez: Dictionary = {}
	for pd in d.people:
		if pd.id == "dez":
			dez = pd
	eq(dez.repair, 8, "a repair order is the section id")
	var walt: Dictionary = {}
	for pd in d.people:
		if pd.id == "walt":
			walt = pd
	check(walt.infected_at >= 0.0 and walt.turn_at > walt.infected_at, "the infection is saved")
	var with_slot := 0
	for zd in d.zombies:
		if zd.slot != null:
			with_slot += 1
			check(zd.slot is Array and zd.slot.size() == 2, "a slot is [section id, slot index]")
	check(with_slot > 0, "some walkers are at the wall")
	var breached := 0
	for sd in d.segments:
		if int(sd.state) == 3:
			breached += 1
	check(breached >= 1, "a section is down")
	g.world.free()


# ---------------------------------------------------------------- round trip --

func test_a_fresh_run_round_trips_onto_a_bare_sim() -> void:
	var a := Helpers.make(3, 2)
	var b := _bare()
	var d := SaveGame.to_dict(a.sim)
	check(SaveGame.apply(b.sim, d), "it applies")
	eq(_diff(SaveGame.to_dict(b.sim), d), "", "the loaded sim saves the same")
	eq(b.sim.difficulty, 2, "difficulty")
	eq(b.sim.run_seed, 3, "seed")
	eq(b.sim.day, 1, "day")
	eq(b.sim.zombies.size(), a.sim.zombies.size(), "the demo walkers are replaced")
	a.world.free()
	b.world.free()


func test_the_rules_roll_the_same_dice_after_a_load() -> void:
	var a := Helpers.make(14, 1)
	Helpers.run(a.sim, 7.0)
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.to_dict(a.sim)), "it applies")
	for i in 6:
		eq(b.sim.rng.randf(), a.sim.rng.randf(), "the same number comes up (%d)" % i)
	eq(b.sim.rng.state, a.sim.rng.state, "in the same place")
	a.world.free()
	b.world.free()


func test_a_busy_night_loads_and_plays_out_identically() -> void:
	var a := _rich_night(5, 1)
	var sim_a = a.sim
	var at_wall := 0
	var hunting := 0
	for z in sim_a.zombies:
		if z.slot != null:
			at_wall += 1
		if z.state == "breach":
			hunting += 1
	check(at_wall >= 1 and hunting >= 1, "the moment is busy: %d walkers at the wall, %d hunting inside" % [at_wall, hunting])
	var breached := false
	for s in sim_a.segments:
		breached = breached or s.state == 3
	check(breached, "a section is down")
	var d := SaveGame.to_dict(sim_a)
	# one copy straight from the data, one through JSON text, both onto sims
	# that did not start from this run (other seed and difficulty)
	var b := _bare()
	var c := _bare()
	check(SaveGame.apply(b.sim, d), "it applies")
	var text := JSON.stringify(d, "", true, true)
	check(SaveGame.apply(c.sim, JSON.parse_string(text)), "it applies from JSON text")
	eq(_diff(SaveGame.to_dict(b.sim), d), "", "the loaded sim saves exactly the same")
	eq(_diff(SaveGame.to_dict(c.sim), d, FILE_TOL), "", "and the one read from text to within float rounding")
	# slots, targets, orders and tiles follow
	eq(_slot_holders(b.sim), _slot_holders(sim_a), "the wall slots are held by the same walkers")
	eq(b.world.solid_z, a.world.solid_z, "the breach has opened the same tiles for walkers")
	eq(b.world.solid_p, a.world.solid_p, "and for people")
	# every variable of every person and walker came back
	for i in sim_a.people.size():
		_same_fields(sim_a.people[i], b.sim.people[i], ["def", "look", "gun", "target", "repair", "away"], "person %s" % sim_a.people[i].id)
		eq(sim_a.zombies.find(sim_a.people[i].target), b.sim.zombies.find(b.sim.people[i].target), "%s keeps the same target" % sim_a.people[i].id)
		eq(sim_a.people[i].repair.id if sim_a.people[i].repair != null else -1, b.sim.people[i].repair.id if b.sim.people[i].repair != null else -1, "%s keeps the repair order" % sim_a.people[i].id)
	for i in sim_a.zombies.size():
		_same_fields(sim_a.zombies[i], b.sim.zombies[i], ["look", "slot"], "zombie %d" % i)
	# play both out for a minute, side by side
	sim_a.events.clear()
	var when_c := ""
	for second in 60:
		Helpers.run(sim_a, 1.0)
		Helpers.run(b.sim, 1.0)
		var da := SaveGame.to_dict(sim_a)
		var exact := _diff(da, SaveGame.to_dict(b.sim))
		if exact != "":
			failures.append("after %d s the loaded game differs: %s" % [second + 1, exact])
			break
		if second < 20 and when_c == "":
			Helpers.run(c.sim, 1.0)
			when_c = _diff(da, SaveGame.to_dict(c.sim), FILE_TOL)
			if when_c != "":
				failures.append("after %d s the game loaded from text differs: %s" % [second + 1, when_c])
	eq(_diff(sim_a.events, b.sim.events), "", "they made the same sounds and banners")
	eq(b.world.solid_z, a.world.solid_z, "and ended with the same walkable ground")
	for x in [a, b, c]:
		x.world.free()


func test_a_day_with_a_party_out_loads_and_plays_out_identically() -> void:
	var a := _rich_day(6)
	var sim_a = a.sim
	var d := SaveGame.to_dict(sim_a)
	var b := _bare()
	check(SaveGame.apply(b.sim, JSON.parse_string(JSON.stringify(d, "", true, true))), "it applies from JSON text")
	eq(_diff(SaveGame.to_dict(b.sim), d, FILE_TOL), "", "the same state")
	var ppl_a := _by_id(sim_a)
	var ppl_b := _by_id(b.sim)
	for id in ppl_a:
		eq(ppl_a[id].away != null, ppl_b[id].away != null, "%s is away or not as before" % id)
		if ppl_a[id].away != null and ppl_a[id].away is Dictionary and ppl_a[id].away.has("members"):
			# a party member's away record is the party the module holds
			var parties: Array = b.sim.scavenge.parties
			var linked := false
			for party in parties:
				linked = linked or is_same(party, ppl_b[id].away)
			check(linked, "%s's away record is one of the loaded parties" % id)
	for i in sim_a.people.size():
		_same_fields(sim_a.people[i], b.sim.people[i], ["def", "look", "gun", "target", "repair", "away"], "person %s" % sim_a.people[i].id, FILE_TOL)
	for second in 40:
		Helpers.run(sim_a, 1.0)
		Helpers.run(b.sim, 1.0)
		var diff := _diff(SaveGame.to_dict(sim_a), SaveGame.to_dict(b.sim), FILE_TOL)
		if diff != "":
			failures.append("after %d s the loaded game differs: %s" % [second + 1, diff])
			break
	a.world.free()
	b.world.free()


func test_saving_at_arbitrary_moments_loads_to_the_same_game() -> void:
	# a few seeds, each saved after a different stretch of play and with a
	# different mishap, then played on for ten seconds
	var moments := [[31, 0, 95.0], [32, 1, 250.0], [33, 2, 330.0]]
	for m in moments:
		var a := Helpers.make(m[0], m[1])
		_advance(a.sim, m[2])
		if m[0] == 32:
			a.sim._damage_segment(a.sim.segments[11], 1000.0)
			_advance(a.sim, 4.0)
		if m[0] == 33:
			var states := {}
			for z in a.sim.zombies:
				states[z.state] = true
			check(states.has("approach"), "seed 33 is caught with walkers on their way (%s)" % str(states.keys()))
			a.sim.people[3].hp = 0.0
			a.sim.medical.on_downed(a.sim.people[3], "bite")
			a.sim.toggle_draft(a.sim.people[0])
		var b := _bare()
		var d := SaveGame.to_dict(a.sim)
		check(SaveGame.apply(b.sim, d), "seed %d: it applies" % m[0])
		eq(_diff(SaveGame.to_dict(b.sim), d), "", "seed %d: same state after the load" % m[0])
		for second in 10:
			Helpers.run(a.sim, 1.0)
			Helpers.run(b.sim, 1.0)
			var diff := _diff(SaveGame.to_dict(a.sim), SaveGame.to_dict(b.sim))
			if diff != "":
				failures.append("seed %d: after %d s the loaded game differs: %s" % [m[0], second + 1, diff])
				break
		a.world.free()
		b.world.free()


func test_a_repaired_breach_closes_its_tiles_again_on_load() -> void:
	# applying onto a sim with a section down restores a standing wall
	var a := Helpers.make(8, 1)
	var b := Helpers.make(9, 1)
	b.sim._damage_segment(b.sim.segments[5], 1000.0)
	var tile: int = int(b.sim.segments[5].tiles[0])
	eq(b.world.solid_z[tile], 0, "the breach opened the ground")
	check(SaveGame.apply(b.sim, SaveGame.to_dict(a.sim)), "it applies")
	eq(b.sim.segments[5].state, 0, "the section stands")
	eq(b.world.solid_z[tile], 1, "and is solid for walkers again")
	eq(b.world.solid_p[tile], 1, "and for people")
	check(b.sim.path_z.grid.is_point_solid(Vector2i(tile % b.sim.W, tile / b.sim.W)), "and in the path grid")
	a.world.free()
	b.world.free()


func test_a_breach_opens_the_ground_in_the_path_grids_and_tells_the_drawing() -> void:
	var a := Helpers.make(8, 1)
	a.sim._damage_segment(a.sim.segments[6], 1000.0)
	a.sim._damage_segment(a.sim.segments[9], a.sim.segments[9].max_hp * 0.5)
	var b := _bare()
	var changed: Array = []
	b.sim.on_segment_change = func(s): changed.append([s.id, s.state])
	check(SaveGame.apply(b.sim, SaveGame.to_dict(a.sim)), "it applies")
	var tile: int = int(b.sim.segments[6].tiles[0])
	eq(b.world.solid_z[tile], 0, "the tile is open in the world")
	check(not b.sim.path_z.grid.is_point_solid(Vector2i(tile % b.sim.W, tile / b.sim.W)), "the walkers' path grid is open")
	check(not b.sim.path_p.grid.is_point_solid(Vector2i(tile % b.sim.W, tile / b.sim.W)), "the people's path grid is open")
	check([6, 3] in changed, "the drawing is told about the broken section: %s" % str(changed))
	check([9, 1] in changed, "and about the damaged one")
	check(changed.size() == 2, "and only about sections that changed")
	a.world.free()
	b.world.free()


func test_a_defeated_run_loads_as_defeated() -> void:
	var a := Helpers.make(2, 1)
	for p in a.sim.people:
		p.dead = true
	Helpers.run(a.sim, 1.0)
	eq(a.sim.over, "defeat", "the run is lost")
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.to_dict(a.sim)), "it applies")
	eq(b.sim.over, "defeat", "and stays lost")
	var before: float = b.sim.t
	Helpers.run(b.sim, 3.0)
	eq(b.sim.t, before, "the rules stand still")
	a.world.free()
	b.world.free()


func test_modules_keep_their_own_state_through_a_save() -> void:
	var a := _rich_night(12, 1)
	var b := _bare()
	var d := SaveGame.to_dict(a.sim)
	check(SaveGame.apply(b.sim, JSON.parse_string(JSON.stringify(d, "", true, true))), "it applies")
	for name in ["supplies", "medical", "scavenge", "scenario"]:
		var saved: Dictionary = a.sim.get(name).save()
		eq(_not_plain(saved), "", "%s saves plain data" % name)
		eq(_diff(saved, b.sim.get(name).save(), FILE_TOL), "", "%s comes back as it was" % name)
	a.world.free()
	b.world.free()


# ------------------------------------------------------------------ refusals --

func test_a_wrong_version_or_damaged_data_is_refused_without_a_change() -> void:
	var a := Helpers.make(5, 1)
	Helpers.run(a.sim, 20.0)
	var good := SaveGame.to_dict(a.sim)
	var b := Helpers.make(6, 2)
	Helpers.run(b.sim, 15.0)
	var before := SaveGame.to_dict(b.sim)
	var zombie_before: int = b.sim.zombies.size()
	# each case: a label and the changes to make to a copy of the good data,
	# [path, value]; the value ERASE removes the key and POP drops the last
	# element of the list
	var cases := [
		["empty", [[[], EMPTY]]],
		["future version", [[["version"], 2]]],
		["no version", [[["version"], ERASE]]],
		["version as text", [[["version"], "1"]]],
		["no people", [[["people"], ERASE]]],
		["people not a list", [[["people"], "ruth"]]],
		["a person missing", [[["people"], POP]]],
		["an unknown person", [[["people", 2, "id"], "nobody"]]],
		["a person twice", [[["people", 1, "id"], "ruth"]]],
		["x not a number", [[["people", 0, "x"], "left"]]],
		["hp not finite", [[["people", 0, "hp"], INF]]],
		["mag a fraction", [[["people", 0, "mag"], 1.5]]],
		["order the wrong shape", [[["people", 0, "order"], [1.0, 2.0]]]],
		["repair names no section", [[["people", 0, "repair"], 99]]],
		["target beyond the walkers", [[["people", 0, "target"], 9999]]],
		["a walker's state is nonsense", [[["zombies", 0, "state"], "flying"]]],
		["a walker at the wall without a slot", [[["zombies", 0, "state"], "attack"], [["zombies", 0, "slot"], null]]],
		["a walker without a position", [[["zombies", 0, "x"], ERASE]]],
		["a walker's look is out of range", [[["zombies", 0, "look_index"], 500]]],
		["a slot in no section", [[["zombies", 0, "slot"], [77, 0]]]],
		["a slot that does not exist", [[["zombies", 0, "slot"], [0, 99]]]],
		["two walkers in one slot", [[["zombies", 0, "slot"], [1, 1]], [["zombies", 1, "slot"], [1, 1]]]],
		["a path that is not points", [[["zombies", 0, "path"], [[1.0, 2.0, 3.0]]]]],
		["a missing section", [[["segments"], POP]]],
		["a section hp below zero", [[["segments", 0, "hp"], -5.0]]],
		["a section state out of range", [[["segments", 0, "state"], 7]]],
		["no stock", [[["stock"], ERASE]]],
		["a stock missing", [[["stock", "meds"], ERASE]]],
		["a negative stock", [[["stock", "food"], -1.0]]],
		["a phase that is no phase", [[["phase"], "noon"]]],
		["minutes past midnight", [[["minutes"], 1500.0]]],
		["the day is zero", [[["day"], 0]]],
		["difficulty out of range", [[["difficulty"], 5]]],
		["rng state not a number", [[["rng_state"], "abc"]]],
		["modules not a dictionary", [[["modules"], []]]],
		["a module's data not a dictionary", [[["modules", "supplies"], 5]]],
	]
	for c in cases:
		var label: String = c[0]
		var data: Dictionary = good.duplicate(true)
		for change in c[1]:
			data = _change(data, change[0], change[1])
		var ok := SaveGame.apply(b.sim, data)
		eq(ok, false, "refused: %s" % label)
		var diff := _diff(SaveGame.to_dict(b.sim), before)
		if diff != "":
			failures.append("%s changed the sim: %s" % [label, diff])
	eq(b.sim.zombies.size(), zombie_before, "the walkers were not replaced")
	# and a good one still applies afterwards
	check(SaveGame.apply(b.sim, good), "the good data applies")
	a.world.free()
	b.world.free()


func test_a_save_with_extra_or_older_fields_still_loads() -> void:
	var a := Helpers.make(5, 1)
	Helpers.run(a.sim, 20.0)
	var d := SaveGame.to_dict(a.sim)
	var b := _bare()
	d.something_new = {"a": 1}
	d.people[0].a_field_from_the_future = 3
	d.zombies[0].another = "x"
	d.stock.antibiotics = 2.0
	d.people[1].erase("recoil")
	d.zombies[1].erase("limp")
	check(SaveGame.apply(b.sim, d), "unknown keys are ignored and missing optional ones keep their defaults")
	eq(b.sim.people[0].x, a.sim.people[0].x, "the rest came through")
	eq(b.sim.stock.get("antibiotics"), 2.0, "an extra stock is kept")
	a.world.free()
	b.world.free()


# --------------------------------------------------------------------- files --

func test_files_are_written_and_read_back() -> void:
	_cleanup()
	var a := Helpers.make(15, 1)
	Helpers.run(a.sim, 30.0)
	check(SaveGame.write(a.sim, TMP_A), "it writes")
	check(FileAccess.file_exists(TMP_A), "the file is there")
	check(not FileAccess.file_exists(TMP_A + ".tmp"), "without a temporary file left behind")
	var back := SaveGame.read(TMP_A)
	eq(back.get("version"), 1, "it reads back as a save")
	eq(_diff(SaveGame.to_dict(a.sim), back, FILE_TOL), "", "with the same content")
	check(SaveGame.is_loadable(TMP_A), "it can be loaded")
	var b := _bare()
	check(SaveGame.apply(b.sim, back), "and applied")
	# writing again replaces it
	Helpers.run(a.sim, 5.0)
	check(SaveGame.write(a.sim, TMP_A), "it writes over the old one")
	eq(SaveGame.read(TMP_A).get("t"), a.sim.t, "the new state")
	_cleanup()
	a.world.free()
	b.world.free()


func test_a_missing_or_damaged_file_is_refused_quietly() -> void:
	_cleanup()
	eq(SaveGame.read(TMP_A), {}, "nothing at a missing path")
	check(not SaveGame.is_loadable(TMP_A), "and nothing to load")
	for text in ["", "not json at all", "{\"version\": 1,", "[1, 2, 3]", "{\"version\": 1}", "{\"version\": 9, \"people\": []}"]:
		var f := FileAccess.open(TMP_B, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		check(not SaveGame.is_loadable(TMP_B), "not loadable: %s" % text)
		var b := _bare()
		check(not SaveGame.apply(b.sim, SaveGame.read(TMP_B)), "not applied: %s" % text)
		b.world.free()
	_cleanup()
	var g := Helpers.make(16, 1)
	check(not SaveGame.write(g.sim, "user://no_such_folder/save.json"), "a path that cannot be written says so")
	g.world.free()
