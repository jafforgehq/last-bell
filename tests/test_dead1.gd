extends "res://tests/case.gd"
## DEAD1 (PH10, 2026-10-10, the owner's "more zombies"): about 60 percent more dead in the streets of the generated town (assets/data/town_dead.json), the night's cap of the dead alive at once raised
## from 40 to 70 and made data (one_house.json `big_night.cap`, `night.cap_dusk`, `night.cap_night`), and what the peak of 70 cost the rules: a place that cannot be walked to is known without a search
## (`TownRules._walled_off`: the barred doors lie inside a whole ring, and the search for a way read the whole of the town, 4 ms for each ask), the count of the dead inside, and the adaptive cap that
## holds the night's dead to a share on a slow machine.

const Helpers := preload("res://tests/helpers.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const Arrival := preload("res://scripts/town/arrival.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const TownPerf := preload("res://scripts/town/town_perf.gd")
const Waves := preload("res://scripts/sim/waves.gd")
const PerimeterStage := preload("res://scripts/town/perimeter_stage.gd")

var _town: Dictionary = {}


func _make() -> Dictionary:
	if _town.is_empty():
		_town = TownGen.make(1)
	return _town


## The points the street's dead keep away from (the generator's calm points: the entry and the middle of every candidate).
func _calm(t: Dictionary) -> Array:
	var out: Array = [Vector2(Arrival.spawn(t).pos)]
	for c in Arrival.candidates(t):
		out.append(Vector2(Rect2i(t.houses[int(c.house)].rect).get_center()))
	return out


func _street(t: Dictionary) -> Array:
	var out: Array = []
	for d in t.dead:
		if int(d.house) < 0:
			out.append(d)
	return out


# --------------------------------------------------------------- the streets --

func test_the_data_is_read_over_the_defaults() -> void:
	var cfg := TownGen.dead_data()
	eq(int(cfg.total), 700, "the total of a whole town")
	near(float(cfg.yard_share), 0.12, 0.0001, "the yards' share")
	near(float(cfg.street.extra), 0.6, 0.0001, "the street has 60 percent more than it had")
	check(int(cfg.street.group[0]) == 1 and int(cfg.street.group[1]) == 4, "groups of one to four")
	check((cfg.street.ramp as Array).size() >= 1, "a ramp by the distance from the calm points (as it stands one point: every place past the calm radius)")
	near(float(TownGen.DEAD_DEFAULTS.street.extra), 0.0, 0.0001, "and the generator's own default has none: a missing file is the town as it was")
	eq(int(TownGen.VERSION), 4, "the town version was bumped (the list of the dead is longer: docs/save-compat.md)")


func test_the_ramp_is_linear_between_its_points() -> void:
	var ramp := [[25.0, 0.0], [40.0, 0.4], [70.0, 1.0]]
	near(TownGen.dead_ramp(ramp, 0.0), 0.0, 0.0001, "none inside the first point")
	near(TownGen.dead_ramp(ramp, 25.0), 0.0, 0.0001, "none at it")
	near(TownGen.dead_ramp(ramp, 32.5), 0.2, 0.0001, "half way to the second point")
	near(TownGen.dead_ramp(ramp, 40.0), 0.4, 0.0001, "the second point")
	near(TownGen.dead_ramp(ramp, 55.0), 0.7, 0.0001, "between the last two")
	near(TownGen.dead_ramp(ramp, 70.0), 1.0, 0.0001, "the last point")
	near(TownGen.dead_ramp(ramp, 300.0), 1.0, 0.0001, "held beyond it")
	near(TownGen.dead_ramp([], 5.0), 1.0, 0.0001, "no ramp is everywhere")


func test_the_streets_have_sixty_percent_more_dead() -> void:
	var t := _make()
	var street := _street(t).size()
	# (the first ones are what the town had: 700 less the houses' and the yards' left about 410 in the streets; 60 percent more is about 650)
	check(street >= 600 and street <= 720, "the street has about 650 of the dead: %d" % street)
	check(t.dead.size() >= 900 and t.dead.size() <= 1000, "900 to 1000 dead in the town: %d" % t.dead.size())
	# (a count of the caller's is exact: no extra on top of it)
	var plain := TownGen.make(1, {"dead": 700})
	var plain_street := _street(plain).size()
	check(plain_street >= 380 and plain_street <= 440, "with `dead` given the street is as it was: %d" % plain_street)
	near(float(street) / float(plain_street), 1.6, 0.05, "so the extra is 60 percent of that")
	# (the old ones are the first of the list, in the same places: the extra come from a stream of their own, after them)
	var same := true
	for i in plain.dead.size():
		if Vector2(plain.dead[i].pos).distance_to(Vector2(t.dead[i].pos)) > 0.001 or String(plain.dead[i].kind) != String(t.dead[i].kind):
			same = false
			break
	check(same, "the dead the town had are where they were")
	var tail_street := 0
	for i in range(plain.dead.size(), t.dead.size()):
		if int(t.dead[i].house) < 0:
			tail_street += 1
	eq(tail_street, t.dead.size() - plain.dead.size(), "and what is new is all street")


## The new dead (everything past the first `plain.dead.size()` records of a town), as how many lie within 40 tiles, 40 to 70 and 70 or more of the nearest calm point; `all_far` is the smallest
## distance of any of them.
func _bands(t: Dictionary, from: int) -> Dictionary:
	var calm := _calm(t)
	var out := {"near": 0, "mid": 0, "far": 0, "least": INF}
	for i in range(from, t.dead.size()):
		var p := Vector2(t.dead[i].pos)
		var d := INF
		for c in calm:
			d = minf(d, Vector2(c).distance_to(p))
		out["least"] = minf(float(out.least), d)
		if d < 40.0:
			out["near"] += 1
		elif d < 70.0:
			out["mid"] += 1
		else:
			out["far"] += 1
	return out


func test_the_new_dead_keep_off_the_first_ground() -> void:
	var t := _make()
	var plain := TownGen.make(1, {"dead": 700})
	var b := _bands(t, plain.dead.size())
	# (the centre of a group is kept 25 tiles off, its dead stand up to 3.5 tiles either way from it, as the street's first ones always did)
	check(float(b.least) >= 20.0, "a new one is not within 20 tiles of the entry or a candidate: %.1f" % float(b.least))
	var extra: int = t.dead.size() - plain.dead.size()
	check(extra > 200, "there are new ones: %d" % extra)
	check(int(b.far) > int(b.mid) and int(b.mid) > int(b.near), "more of them the farther out (there is more town there): %d near, %d between, %d far" % [int(b.near), int(b.mid), int(b.far)])
	var calm := _calm(t)
	for d in _street(t):
		var least := INF
		for c in calm:
			least = minf(least, Vector2(c).distance_to(Vector2(d.pos)))
		check(least >= 20.0, "no street dead within the calm radius of a calm point")


func test_the_ramp_can_thin_the_first_ground() -> void:
	# (the data asks for every place beyond the calm radius; a ramp of [[25, 0], [40, 0.4], [70, 1]] spares the first houses and puts the rest of the extra farther out)
	var keep: Dictionary = TownGen.dead_data()
	var cfg: Dictionary = keep.duplicate(true)
	cfg.street.ramp = [[25.0, 0.0], [40.0, 0.4], [70.0, 1.0]]
	TownGen._dead_cfg = cfg
	var thin := TownGen.make(1)
	TownGen._dead_cfg = keep
	var plain := TownGen.make(1, {"dead": 700})
	var flat := _make()
	var bt := _bands(thin, plain.dead.size())
	var bf := _bands(flat, plain.dead.size())
	eq(thin.dead.size() - plain.dead.size(), flat.dead.size() - plain.dead.size(), "the same number of new ones")
	check(int(bt.near) < int(bf.near), "fewer of them on the first ground with the ramp (%d against %d)" % [int(bt.near), int(bf.near)])
	check(int(bt.far) > int(bf.far), "and more of them far out (%d against %d)" % [int(bt.far), int(bf.far)])
	check(float(bt.least) >= 20.0, "none inside the calm radius")


func test_the_same_seed_makes_the_same_dead() -> void:
	var a := TownGen.make(3)
	var b := TownGen.make(3)
	eq(TownGen.digest(a), TownGen.digest(b), "the same seed, the same town and the same dead")
	eq(a.dead.size(), b.dead.size(), "the same number")
	check(TownGen.digest(TownGen.make(4)) != TownGen.digest(a), "another seed, another town")


# ------------------------------------------------------------------- the caps --

func _night_run(blocks: int = 2) -> Dictionary:
	var g := Helpers.town_game(1, {"blocks": blocks})
	OneHouse.begin(g.sim, 1, 1)
	OneHouse.stage_to(g.sim, "night")
	return g


func test_the_caps_are_data_and_70() -> void:
	var data: Dictionary = OneHouse.data()
	eq(int(data.big_night.cap), 70, "the first night's cap went from 40 to 70")
	eq(int(data.night.cap_dusk), 50, "an ordinary night's dusk")
	eq(int(data.night.cap_night), 70, "an ordinary night's dark")
	var g := _night_run()
	var s = g.sim.scenario
	eq(int(s.big_night_for(s._first_day).cap), 70, "the plan of the first night carries it")
	eq(s.night_cap(false, false, 30), 50, "dusk: the data's, not the colony's 30")
	eq(s.night_cap(true, false, 50), 70, "night: the data's, not the colony's 50")
	eq(s.night_cap(true, true, 90), 90, "a final night is the colony's own")
	eq(Waves.CAP_DUSK, 30, "the colony's caps are as they were")
	eq(Waves.CAP_NIGHT, 50, "")
	eq(Waves.CAP_BIG, 90, "")
	# (a damaged data file leaves the colony's)
	s.d()["night"].erase("cap_night")
	eq(s.night_cap(true, false, 50), 50, "no key, the colony's number")
	g.world.free()


## The most of the night's dead alive at once over a night of `steps` steps with the cap `cap` and a night much bigger than it (`night.first`).
func _most_alive(cap: int, steps: int) -> int:
	var g := Helpers.town_game(1, {"blocks": 6})
	var sim = g.sim
	OneHouse.begin(sim, 1, 1)
	var d: Dictionary = sim.scenario.d()
	d["night"]["first"] = 8.0
	d["night"]["surges"] = [{"at": 0.1, "share": 1.0}]
	d["big_night"]["cap"] = cap
	OneHouse.stage_to(sim, "night")
	var me = sim.avatar.player()
	var most := 0
	for i in steps:
		me.hp = 100.0
		sim.update(1.0 / 30.0)
		sim.events.clear()
		most = maxi(most, int(sim.alive_for_cap()))
	var plan: Dictionary = sim.waves.plan_for(sim.scenario._first_day)
	check(plan.queue.size() > cap + 10, "the night is bigger than the cap (%d of the dead for a cap of %d)" % [plan.queue.size(), cap])
	g.world.free()
	return most


func test_the_night_keeps_to_its_cap_and_reaches_it() -> void:
	var low := _most_alive(25, 1500)
	check(low <= 25 and low >= 20, "a cap of 25 holds the night to 25 alive at once, and the night reaches it: %d" % low)
	var high := _most_alive(70, 2400)
	check(high <= 70 and high >= 55, "the cap of 70 lets 55 to 70 of the night's dead be alive at once (the 40 is gone): %d" % high)


func test_a_slow_machine_holds_the_wave_to_a_share() -> void:
	var g := _night_run()
	var sim = g.sim
	eq(sim.wave_cap(70), 70, "on a machine that keeps up the cap is the night's own")
	sim.wave_scale = 0.5
	eq(sim.wave_cap(70), 35, "half of it after one halving")
	sim.wave_scale = 0.05
	eq(sim.wave_cap(70), 24, "never under the floor of 24")
	eq(sim.wave_cap(20), 20, "nor over what the night asked: a cap under the floor stays")
	sim.wave_scale = 1.0
	# the adaptive cap sets the share: slow frames halve it, quick ones give it back
	var perf := TownPerf.new()
	perf.setup(sim)
	eq(sim.wave_scale, 1.0, "no change at the start")
	for i in 100:
		perf.step(0.040)    # (25 fps)
	check(perf.halved >= 1, "slow frames halve the cap")
	check(sim.wave_scale < 1.0, "and the night's share with it (%.2f)" % sim.wave_scale)
	near(sim.wave_scale, float(perf.cap) / float(perf.full), 0.0001, "the same share")
	for i in 5000:
		perf.step(0.010)
	near(sim.wave_scale, 1.0, 0.0001, "quick frames give it all back")
	g.world.free()


# ------------------------------------------------------------- the peak's cost --

## A staged night with the whole fence up, in a whole town (the barred doors lie inside the ring).
func _fenced_night() -> Dictionary:
	var g := Helpers.town_game(1, {"blocks": 6})
	OneHouse.begin(g.sim, 1, 1)
	OneHouse.stage_to(g.sim, "night")
	PerimeterStage.apply(g.sim, "built")
	return g


func test_a_place_with_no_way_to_it_is_known_without_a_search() -> void:
	var g := _fenced_night()
	var sim = g.sim
	var door = null
	for s in sim.segments:
		if String(s.kind) == "door" and not s.slots.is_empty():
			door = s.slots[0]
			break
	check(door != null, "the base has a barred door with a place at it")
	if door == null:
		g.world.free()
		return
	var out = sim.spawn(float(sim.spawns[0].x), float(sim.spawns[0].y), "approach", "walker")
	var way: Array = sim.path_z.find(sim.world.solid_z, out.x, out.y, door.ax, door.ay)
	check(way.is_empty(), "with the ring whole there is no way on foot from the street to a barred door")
	check(not sim._walled_off(door, out), "nothing is known before a search has found none")
	sim._note_no_way(door)
	check(sim._walled_off(door, out), "after one it is known, for the next one who asks")
	var inside = sim.spawn(float(door.ax), float(door.ay), "approach", "walker")
	check(not sim._walled_off(door, inside), "one that stands in the pocket is not walled off")
	# the walking grid changes (a section falls, a gate opens): what was known is let go
	var before: int = sim.path_z.rev
	sim.path_z.set_solid(5 * sim.W + 5, sim.world.solid_z[5 * sim.W + 5] != 0)
	check(sim.path_z.rev > before, "a change of the grid moves the revision")
	check(not sim._walled_off(door, out), "and the knowledge is let go with it")
	g.world.free()


func test_what_is_walled_off_has_no_way_and_the_fence_places_have_one() -> void:
	var g := _fenced_night()
	var sim = g.sim
	var out = sim.spawn(float(sim.spawns[0].x), float(sim.spawns[0].y), "approach", "walker")
	var walled := 0
	var open := 0
	for s in sim._siege_sections():
		for sl in s.slots:
			var way: Array = sim.path_z.find(sim.world.solid_z, out.x, out.y, sl.ax, sl.ay)
			if way.is_empty():
				sim._note_no_way(sl)
				if sim._walled_off(sl, out):
					walled += 1
			else:
				check(not sim._walled_off(sl, out), "a place with a way to it is never walled off")
				open += 1
	check(open > 0, "the fence has places the dead can walk to (%d)" % open)
	check(walled > 0, "the doors do not (%d)" % walled)
	g.world.free()


func test_the_count_of_the_dead_inside_is_the_one_it_was() -> void:
	var g := _fenced_night()
	var sim = g.sim
	var b = sim.base
	var yard := Rect2(b.yard_rect())
	var mid := yard.get_center()
	for k in 5:
		sim.spawn(mid.x + float(k) * 0.4 - 1.0, mid.y, "approach", "walker")    # in the yard
	var house: Rect2i = sim.houses.house(int(b.house)).rect
	sim.spawn(float(house.get_center().x), float(house.get_center().y), "approach", "walker")    # in the house
	sim.spawn(float(sim.spawns[0].x), float(sim.spawns[0].y), "approach", "walker")    # in the street
	var dying = sim.spawn(mid.x, mid.y + 1.0, "approach", "walker")
	dying.state = "dying"
	var want := 0
	var per = sim.perimeter
	var fenced: bool = per == null or not bool(per.no_outer_wall())
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead" or z.state == "retreat":
			continue
		if (fenced and sim._in_yard(z.x, z.y)) or sim.inside_school(z.x, z.y):
			want += 1
	check(want >= 6, "the yard and the house have the dead put there (%d)" % want)
	eq(sim.dead_inside(), want, "the count is the one made one by one")
	g.world.free()
