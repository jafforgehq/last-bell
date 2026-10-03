extends "res://tests/case.gd"
## The forecast as a tool (round 19, S3.1 and S3.4, tactics.gd): what the lookout's forecast says in avatar mode (the outlook of the
## night, the sections it will break on, whether the community will hold), `readiness`, the alarm that every brute obeys, and that
## without an avatar the forecast is what it was. Numbers are read from NightData, never copied.

const Helpers := preload("res://tests/helpers.gd")
const Kinds := preload("res://scripts/sim/kinds.gd")
const Waves := preload("res://scripts/sim/waves.gd")
const NightData := preload("res://scripts/sim/night_data.gd")

## The keys the forecast has always had.
const OLD_KEYS := ["given", "total", "low", "high", "heading", "spawns", "runners", "brutes", "big", "who"]
const NEW_KEYS := ["kind", "name", "side", "sections", "section_text", "plated", "first_at", "brute_at", "needs_you", "ready"]


func _seg(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## The four who are not the player, in the order of the crew list.
func _others(sim) -> Array:
	var out: Array = []
	for p in sim.people:
		if not p.player and not p.dead:
			out.append(p)
	return out


## The forecast given by Marcus on `day` at 17:00 with the lookout in his seat (the stations' own way), the clock at 17:00.
func _given(sim, day: int) -> void:
	Helpers.at(sim, day, 16.9)
	sim.waves.enabled = false
	sim.events.clear()
	var lookout = _person(sim, "Marcus")
	Helpers.seat(sim, lookout, "watch")
	Helpers.run(sim, 3.0)


## Puts `who` at a spot of the wall for the night (an order of the post kind: where `post_pos` looks first).
func _post(who, at: Vector2) -> void:
	who.drafted = true
	who.order = Vector3(at.x, at.y, 1.0)
	who.x = at.x
	who.y = at.y


# ---------------------------------------------------------------- the keys --

func test_without_an_avatar_the_forecast_has_the_old_keys_and_no_others() -> void:
	var g := Helpers.make(21, 1, 6)
	var sim = g.sim
	_given(sim, 9)
	var f: Dictionary = sim.tactics.forecast()
	check(f.given, "the forecast is given")
	var keys := f.keys()
	keys.sort()
	var old := OLD_KEYS.duplicate()
	old.sort()
	eq(keys, old, "exactly the old keys")
	g.world.free()


func test_an_avatar_forecast_keeps_every_old_key_and_adds_the_new_ones() -> void:
	var g := Helpers.avatar_game(21, 5)
	var sim = g.sim
	_given(sim, 9)
	var f: Dictionary = sim.tactics.forecast()
	check(f.given, "the forecast is given")
	for key in OLD_KEYS:
		check(f.has(key), "it still has `%s`" % key)
	for key in NEW_KEYS:
		check(f.has(key), "and now `%s`" % key)
	var plan: Dictionary = sim.waves.plan_for(sim.day)
	eq(f.total, int(plan.shown), "the number is the plan's")
	eq(f.heading, sim.waves.heading_text(plan), "the heading is the plan's")
	eq(f.big, bool(plan.big), "`big` is what it was")
	var o: Dictionary = sim.waves.outlook(sim.day)
	eq(f.kind, o.kind, "the kind")
	eq(f.name, o.name, "the name")
	eq(f.side, o.side, "the side")
	eq(f.sections, o.sections, "the sections")
	eq(f.section_text, o.section_text, "the sentence about them")
	eq(f.plated, o.plated, "plated")
	near(float(f.first_at), float(o.first_at), 0.0, "the first")
	near(float(f.brute_at), float(o.brute_at), 0.0, "the brutes")
	eq(f.needs_you, o.needs_you, "whether it needs the player")
	eq(f.ready, sim.tactics.readiness(o.sections), "and the readiness of those sections")
	g.world.free()


func test_a_forecast_not_given_is_still_only_not_given_in_avatar_mode() -> void:
	var g := Helpers.avatar_game(22, 5)
	var sim = g.sim
	Helpers.at(sim, 9, 12.0)
	eq(sim.tactics.forecast(), {"given": false}, "before 17:00")
	for p in sim.people:
		if p.first == "Marcus":
			p.dead = true
	Helpers.at(sim, 9, 16.9)
	sim.waves.enabled = false
	Helpers.run(sim, 3.0)
	eq(sim.tactics.forecast(), {"given": false}, "and with nobody on watch")
	eq(String(sim.alerts.forecast.text), "No forecast", "which the crew is told as ever")
	g.world.free()


func test_a_big_night_needs_the_player_and_an_ordinary_one_does_not() -> void:
	var g := Helpers.avatar_game(23, 5)
	var sim = g.sim
	_given(sim, 9)
	var nine: Dictionary = sim.tactics.forecast()
	eq(nine.kind, "ordinary", "night 9")
	eq(nine.needs_you, false, "does not need him")
	eq(nine.plated, 0, "and has no plated brute")
	_given(sim, 10)
	var ten: Dictionary = sim.tactics.forecast()
	eq(ten.kind, "milestone", "night 10")
	eq(ten.needs_you, true, "needs him")
	check(ten.plated >= 2, "has plated brutes: %d" % ten.plated)
	check(ten.sections.size() >= 1, "and names the walls it will break on")
	g.world.free()


func test_an_avatar_orientation_day_forecasts_the_script_and_the_outlook_agrees() -> void:
	var Kit := load("res://tests/tutorial_kit.gd")
	var g = Kit.make()
	var sim = g.sim
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	Kit.run_to_clock(sim, 10.0 * 60.0 + 20.0)
	var f: Dictionary = sim.tactics.forecast()
	check(f.get("given", false), "Marcus has spoken by 17:20")
	eq(int(f.total), 7, "the script's seven")
	eq(f.heading, "north", "from the north")
	for key in NEW_KEYS:
		check(f.has(key), "the avatar forecast has `%s` here too" % key)
	eq(f.kind, "ordinary", "an ordinary night")
	eq(f.needs_you, false, "that does not need the player")
	var o: Dictionary = sim.waves.outlook(sim.day)
	eq(o.size, 7, "the outlook is the script's too")
	eq(o.side, "north", "from the north")
	g.world.free()


# --------------------------------------------------------------- readiness --

func test_readiness_of_a_hand_made_state() -> void:
	var g := Helpers.avatar_game(24, 5)
	var sim = g.sim
	Helpers.at(sim, 9, 17.5)
	sim.waves.enabled = false
	sim.zombies.clear()
	var east = _seg(sim, 12)
	var north = _seg(sim, 3)
	east.hp = east.max_hp * 0.9
	north.hp = north.max_hp * 0.6
	sim._segment_state(east)
	sim._segment_state(north)
	var others := _others(sim)
	eq(others.size(), 4, "four people besides the player")
	# three guns at the east bus, one at the north: coverage 3 and 1
	var at_east: Vector2 = sim.repair_spot(east)
	var at_north: Vector2 = sim.repair_spot(north)
	for i in 3:
		_post(others[i], at_east + Vector2(0.0, 0.3 * float(i)))
	_post(others[3], at_north)
	eq(sim.tactics.coverage_without_player(east), 3, "three guns reach the east bus")
	eq(sim.tactics.coverage_without_player(north), 1, "one the north bus")
	var r: Dictionary = sim.tactics.readiness([12, 3])
	near(float(r.walls), 0.6, 1e-9, "walls: the lowest of 90% and 60%")
	eq(r.guns, 1, "guns: the fewest of 3 and 1")
	eq(r.posts, 4, "four posts")
	eq(r.manned, 4, "four manned (the bell has not rung: all four are able)")
	check(not r.holds, "it does not hold")
	eq(sim.tactics.readiness([east, north]), r, "sections may be given as sections too")
	# the east bus alone: three guns and 90%
	var alone: Dictionary = sim.tactics.readiness([12])
	near(float(alone.walls), 0.9, 1e-9, "the east bus alone: 90%")
	eq(alone.guns, 3, "three guns")
	check(alone.holds, "and it holds, with every post manned: %s" % str(alone))
	# the north bus mended above the line and a second gun on it
	north.hp = north.max_hp * 0.8
	sim._segment_state(north)
	_post(others[2], at_north + Vector2(0.0, 0.3))
	var both: Dictionary = sim.tactics.readiness([12, 3])
	near(float(both.walls), 0.8, 1e-9, "walls 80%")
	eq(both.guns, 2, "guns 2: the east has two now and the north two")
	check(both.holds, "holds")
	var below := float(NightData.num("forecast.decent_walls"))
	north.hp = north.max_hp * (below - 0.05)
	sim._segment_state(north)
	check(not sim.tactics.readiness([12, 3]).holds, "a wall under the line does not hold")
	north.hp = north.max_hp * (below + 0.05)
	sim._segment_state(north)
	check(sim.tactics.readiness([12, 3]).holds, "and one over it does")
	var guns_needed := int(NightData.num("forecast.decent_guns"))
	_post(others[2], at_east)    # north has one again
	eq(sim.tactics.readiness([12, 3]).guns, 1, "one gun at the north")
	check(guns_needed > 1 and not sim.tactics.readiness([12, 3]).holds, "fewer guns than the line does not hold")
	g.world.free()


func test_readiness_with_no_sections_reads_every_wall_of_the_compound() -> void:
	var g := Helpers.avatar_game(25, 5)
	var sim = g.sim
	Helpers.at(sim, 9, 17.5)
	var all: Dictionary = sim.tactics.readiness()
	var lowest := 1.0
	var fewest := 999
	for s in sim.segments:
		if s.id < 100 and s.kind != sim.DOOR_KIND:
			lowest = minf(lowest, s.hp / s.max_hp)
			fewest = mini(fewest, sim.tactics.coverage_without_player(s))
	near(float(all.walls), lowest, 1e-9, "the lowest hp share of the compound's walls")
	eq(all.guns, fewest, "the fewest guns")
	var worn = _seg(sim, 5)
	worn.hp = worn.max_hp * 0.3
	sim._segment_state(worn)
	near(float(sim.tactics.readiness().walls), 0.3, 1e-9, "a worn wall anywhere shows")
	near(float(sim.tactics.readiness([5]).walls), 0.3, 1e-9, "and in its own")
	worn.hp = 0.0
	sim._segment_state(worn)
	near(float(sim.tactics.readiness().walls), 0.0, 1e-9, "a fallen one is 0%")
	g.world.free()


func test_readiness_does_not_count_the_player_a_downed_one_or_one_away() -> void:
	var g := Helpers.avatar_game(26, 5)
	var sim = g.sim
	Helpers.at(sim, 9, 17.5)
	sim.waves.enabled = false
	var others := _others(sim)
	var base: Dictionary = sim.tactics.readiness()
	eq(base.posts, 4, "four posts: the player is not one of them")
	eq(base.manned, 4, "all manned")
	# a gun in the player's hands at a wall does not count for the community
	var east = _seg(sim, 12)
	var ruth = sim.people[0]
	check(ruth.player, "Ruth is the player")
	_post(ruth, sim.repair_spot(east))
	eq(sim.tactics.coverage_of(east), sim.tactics.coverage_without_player(east) + 1, "the old count has the player's gun in it, and it is left out when asked")
	eq(sim.tactics.readiness([12]).guns, sim.tactics.coverage_without_player(east), "the community's guns are the ones without him")
	others[0].downed = true
	var down: Dictionary = sim.tactics.readiness()
	eq(down.posts, 4, "one down still has a post to go to")
	eq(down.manned, 3, "but nobody mans it")
	check(not down.holds, "and the community does not hold")
	others[0].downed = false
	others[1].away = {"trip": true}
	var away: Dictionary = sim.tactics.readiness()
	eq(away.posts, 3, "one away on a trip is not at the base: no post to man")
	eq(away.manned, 3, "and the rest are")
	g.world.free()


func test_after_the_bell_a_post_is_manned_when_its_person_is_at_it() -> void:
	var g := Helpers.avatar_game(27, 5)
	var sim = g.sim
	Helpers.at(sim, 9, 19.5)
	sim.waves.enabled = false
	sim.phase = "dusk"
	check(sim.posts_manned(), "the crew holds its posts now")
	var others := _others(sim)
	var spot := Vector2(40.0, 40.0)
	for i in others.size():
		_post(others[i], spot + Vector2(float(i) * 2.0, 0.0))
	var r: Dictionary = sim.tactics.readiness()
	eq(r.posts, 4, "four posts")
	eq(r.manned, 4, "all four at theirs")
	others[2].x += 6.0
	r = sim.tactics.readiness()
	eq(r.manned, 3, "one who is not at their post is not manning it")
	others[2].x -= 6.0
	others[3].y += 1.0
	eq(sim.tactics.readiness().manned, 4, "a step off is still at it")
	g.world.free()


# ---------------------------------------------------------- the forecast's say --

func test_the_lookout_says_the_siege_in_avatar_mode_with_the_outlook_text() -> void:
	var g := Helpers.avatar_game(28, 5)
	var sim = g.sim
	_given(sim, 10)
	var o: Dictionary = sim.waves.outlook(10)
	var want := Waves.outlook_text(o)
	eq(String(sim.alerts.forecast.text), "Tonight's forecast", "the alert is the lookout's")
	eq(String(sim.alerts.forecast.sub), want, "and says the outlook of the Big Night")
	check(want.begins_with(String(o.name)), "which begins with the night's name: %s" % want)
	var banner := ""
	for e in sim.events:
		if e.type == "banner" and String(e.text).contains("reports"):
			banner = String(e.sub)
	eq(banner, want, "the banner says it too")
	g.world.free()


func test_an_ordinary_night_in_avatar_mode_is_told_in_the_old_words() -> void:
	var g := Helpers.avatar_game(28, 5)
	var sim = g.sim
	_given(sim, 3)
	var f: Dictionary = sim.tactics.forecast()
	var want := "About %d tonight, mostly from the %s" % [int(f.total), String(f.heading)]
	if int(f.brutes) > 0:
		want += ", and %s" % ("a brute" if int(f.brutes) == 1 else "%d brutes" % int(f.brutes))
	elif bool(f.runners):
		want += ", with runners"
	eq(String(sim.alerts.forecast.sub), want, "as it has always been told")
	g.world.free()


func test_without_an_avatar_the_big_night_is_told_as_it_always_was() -> void:
	var g := Helpers.make(28, 1, 6)
	var sim = g.sim
	_given(sim, 30)
	var f: Dictionary = sim.tactics.forecast()
	check(f.big, "night 30 is the last")
	eq(String(sim.alerts.forecast.sub), "The last night: about %d, from everywhere" % int(f.total), "in the old words")
	_given(sim, 9)
	check(not sim.tactics.forecast().big, "and night 9 is an ordinary one")
	g.world.free()


# --------------------------------------------------------------------- lure --

func _approaching(sim, kind: String, n: int, toward) -> Array:
	var out: Array = []
	for i in n:
		var z = sim.spawn(76.0, 28.0 + float(i % 6), "approach", kind)
		z.speed = 0.7
		sim._assign_slot(z)
		out.append(z)
	return out


func test_every_brute_obeys_the_alarm_in_avatar_mode_and_not_every_walker_does() -> void:
	var turned := 0
	var all_obeyed := 0
	for seed_value in range(1, 13):
		var g := Helpers.avatar_game(seed_value, 5)
		var sim = g.sim
		sim.waves.enabled = false
		sim.zombies.clear()
		var north = _seg(sim, 3)
		var brute = _approaching(sim, Kinds.BRUTE, 1, north)[0]
		var walkers := _approaching(sim, Kinds.WALKER, 5, north)
		if brute.slot != null and brute.slot.seg == north:
			g.world.free()
			continue
		sim.stock.scrap = 20.0
		check(sim.tactics.order_lure(north), "the alarm is set")
		turned += 1
		if brute.slot != null and brute.slot.seg == north:
			all_obeyed += 1
		g.world.free()
	check(turned >= 10, "the trials were made: %d" % turned)
	eq(all_obeyed, turned, "the brute went to the alarm every time")


func test_a_brute_without_an_avatar_switches_by_the_old_die_and_the_dice_are_counted() -> void:
	var plain := Helpers.make(31, 1, 5)
	var sim = plain.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	var north = _seg(sim, 3)
	# the alarm's section is full, so that nobody can switch and `assign_slot` throws no die: the dice are the switching's alone
	for sl in north.slots:
		sl.who = sim.spawn(sl.x, sl.y, "attack")
	var coming := _approaching(sim, Kinds.BRUTE, 3, north) + _approaching(sim, Kinds.WALKER, 4, north)
	var candidates := 0
	for z in coming:
		if z.state == "approach" and z.slot != null and z.slot.seg != north:
			candidates += 1
	var ref := RandomNumberGenerator.new()
	ref.seed = sim.rng.seed
	ref.state = sim.rng.state
	sim.stock.scrap = 20.0
	check(sim.tactics.order_lure(north), "the alarm is set")
	for i in candidates:
		ref.randf()
	eq(sim.rng.state, ref.state, "one die for each of the %d on their way (the brutes too), as it was" % candidates)
	plain.world.free()
	var g := Helpers.avatar_game(31, 5)
	var asim = g.sim
	asim.waves.enabled = false
	asim.zombies.clear()
	var anorth = _seg(asim, 3)
	for sl in anorth.slots:
		sl.who = asim.spawn(sl.x, sl.y, "attack")
	var acoming := _approaching(asim, Kinds.BRUTE, 3, anorth) + _approaching(asim, Kinds.WALKER, 4, anorth)
	var dice := 0
	for z in acoming:
		if z.state == "approach" and z.slot != null and z.slot.seg != anorth and z.kind != Kinds.BRUTE:
			dice += 1
	var aref := RandomNumberGenerator.new()
	aref.seed = asim.rng.seed
	aref.state = asim.rng.state
	asim.stock.scrap = 20.0
	check(asim.tactics.order_lure(anorth), "the alarm is set in avatar mode")
	for i in dice:
		aref.randf()
	eq(asim.rng.state, aref.state, "in avatar mode one die for each of the %d that is not a brute" % dice)
	g.world.free()


func test_a_brute_that_comes_in_while_the_alarm_rings_goes_to_it() -> void:
	var g := Helpers.avatar_game(32, 5)
	var sim = g.sim
	Helpers.at(sim, 10, 18.9)
	sim.zombies.clear()
	var plan: Dictionary = sim.waves.plan_for(10)
	var from: Vector2 = sim.spawns[int(plan.heading[0])]
	# the alarm on the wall farthest from where they come in: farther than the alarm's own pull (LURE_PULL) can make up
	var far = null
	var far_d := 0.0
	var near_d := INF
	for s in sim.segments:
		if s.id >= 100 or s.kind == sim.DOOR_KIND:
			continue
		var d := INF
		for sl in s.slots:
			d = minf(d, from.distance_to(Vector2(sl.ax, sl.ay)))
		near_d = minf(near_d, d)
		if d > far_d:
			far_d = d
			far = s
	check(far_d - near_d > sim.tactics.LURE_PULL + 4.0, "the far wall is too far for the pull alone: %.0f against %.0f" % [far_d, near_d])
	sim.stock.scrap = 20.0
	check(sim.tactics.order_lure(far), "the alarm is set on it")
	var brutes := 0
	var lured := 0
	var walkers_there := 0
	sim.waves.night_day = -1
	sim.waves.update(1.0 / 30.0)
	sim.phase = "dusk"
	sim.waves.update(1.0 / 30.0)
	sim.phase = "night"
	var guard := 0
	while sim.waves.spawned < plan.queue.size() and guard < 40000:
		var before: int = sim.zombies.size()
		sim.waves.update(1.0 / 30.0)
		for i in range(before, sim.zombies.size()):
			var z = sim.zombies[i]
			if z.kind == Kinds.BRUTE:
				brutes += 1
				if z.slot != null and z.slot.seg == far:
					lured += 1
			elif z.slot != null and z.slot.seg == far:
				walkers_there += 1
		guard += 1
	check(brutes >= 2, "the siege brings brutes: %d" % brutes)
	eq(lured, brutes, "every brute went to the alarm's wall")
	g.world.free()
