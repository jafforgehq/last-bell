extends "res://tests/case.gd"
## The dead in the streets by day (round 12, scripts/sim/streets.gd): stragglers each morning in the settlement
## game, never in the classic start; they hunt a survivor they see outside the walls and are shot at by day;
## a sealed ring has none inside it.

const Helpers := preload("res://tests/helpers.gd")
const Streets := preload("res://scripts/sim/streets.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _game(small: bool = true) -> Dictionary:
	var g := Helpers.make(5, 1, 3 if small else 6)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 4
	sim.minutes = 8.0 * 60.0
	sim.clock_min = 3.0 * 1440.0 + 8.0 * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.supplies.sources_day = 4
	sim.events.clear()
	return g


func _living(sim) -> Array:
	var out: Array = []
	for z in sim.zombies:
		if z.state != "dying" and z.state != "dead":
			out.append(z)
	return out


func test_the_classic_start_has_no_stragglers() -> void:
	var g := _game(false)
	var sim = g.sim
	sim.streets.on_dawn()
	eq(sim.zombies.size(), 0, "nobody is put in the streets of a classic game")
	g.world.free()


func test_the_number_of_stragglers_grows_with_the_days_to_a_cap() -> void:
	var g := _game()
	var s = g.sim.streets
	eq(s.target_count(1), 2, "two on the first morning")
	check(s.target_count(21) > s.target_count(1), "more later")
	eq(s.target_count(200), Streets.DAY_MAX, "never more than the cap")
	g.world.free()


func test_a_morning_puts_the_stragglers_on_streets_away_from_the_people() -> void:
	var g := _game()
	var sim = g.sim
	sim.streets.on_dawn()
	var n := _living(sim).size()
	eq(n, sim.streets.target_count(4), "the day's number")
	for z in _living(sim):
		check(z.state == "wander", "they wander")
		var t: int = int(sim.world.terrain[floori(z.y) * sim.W + floori(z.x)])
		check(Streets.STREET_TERRAIN.has(t), "on asphalt or sidewalk (%d)" % t)
		check(sim.world.solid_z[floori(z.y) * sim.W + floori(z.x)] == 0, "on open ground")
		for p in sim.people:
			check(Vector2(p.x, p.y).distance_to(Vector2(z.x, z.y)) >= Streets.SAFE_FROM_PEOPLE, "away from %s" % p.first)
	# a second morning adds only what is missing
	sim.streets.on_dawn()
	eq(_living(sim).size(), n, "those still about count towards the number")
	check(sim.alerts.has("streets"), "an alert says so")
	g.world.free()


func test_a_sealed_ring_has_no_stragglers_inside_it() -> void:
	var g := Helpers.make(3, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 12
	sim.stock.scrap = 2000.0
	var i := 0
	for id in sim.town.state:
		if i < 4:
			sim.town.state[id].cleared = true
			i += 1
	for l in sim.lots.lots():
		sim.lots.claim(String(l.id))
	for m in sim.lots.mouths():
		var kits: Array = sim.lots.kits_for(String(m.id))
		if kits.is_empty() or not sim.build.order(String(m.id), String(kits[0])):
			continue
		var pl: Dictionary = sim.build.plot(String(m.id))
		pl.site.progress = float(pl.site.work)
		sim.build._finish(pl)
	eq(sim.lots.open_streets(), 0, "every street has its wall")
	var ring: int = sim.region_at(39.0, 13.0)
	for day in range(5, 14):
		sim.day = day
		sim.streets.on_dawn()
	for z in _living(sim):
		check(sim.region_at(z.x, z.y) != ring, "no straggler in the sealed ring (%.1f, %.1f)" % [z.x, z.y])
	g.world.free()


func test_a_straggler_hunts_a_survivor_outside_the_walls_and_the_survivor_shoots_back() -> void:
	var g := _game()
	var sim = g.sim
	# open the Main gate's side: put Ruth in the north street, a straggler six tiles off, in the same stretch of street
	var ruth = sim.people[0]
	ruth.x = 40.0
	ruth.y = 12.0
	ruth.moving = false
	ruth.path = []
	ruth.drafted = false
	ruth.order = null
	ruth.order = Vector3(ruth.x, ruth.y, 0.0)    # (so that she stays where she is put: with no job she would walk to a rest spot, round 16)
	var z = sim.spawn(46.0, 12.0, "wander")
	sim.streets._look_t = 0.0
	sim.streets.update(0.1)
	eq(z.state, "hunt", "it has seen her")
	eq(z.hunt_id, String(ruth.id), "and hunts her")
	var shots_before: int = ruth.stats.shots
	for i in 150:
		ruth.x = 40.0
		ruth.y = 12.0
		sim.update(1.0 / 30.0)
		if z.state == "dying" or z.state == "dead":
			break
	check(ruth.stats.shots > shots_before, "by day Ruth shoots at what hunts her")
	g.world.free()


func test_a_straggler_loses_someone_who_goes_back_inside_the_walls() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = sim.people[0]
	ruth.x = 40.0
	ruth.y = 12.0
	var z = sim.spawn(46.0, 12.0, "wander")
	sim.streets._look_t = 0.0
	sim.streets.update(0.1)
	eq(z.state, "hunt", "hunting")
	ruth.x = 40.0
	ruth.y = 26.0
	sim.update(1.0 / 30.0)
	eq(z.state, "wander", "it cannot reach her any more: it wanders")
	g.world.free()


func test_the_hunt_ends_at_dusk_and_a_save_keeps_it() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = sim.people[0]
	ruth.x = 40.0
	ruth.y = 12.0
	var z = sim.spawn(46.0, 12.0, "wander")
	sim.streets._look_t = 0.0
	sim.streets.update(0.1)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var b := Helpers.make(9, 1, 3)
	check(SaveGame.apply(b.sim, d), "it loads")
	var kept := false
	for zz in b.sim.zombies:
		if zz.state == "hunt" and zz.hunt_id == String(ruth.id):
			kept = true
	check(kept, "the hunt is in the save: %s" % str(b.sim.zombies.map(func(q): return [q.state, q.hunt_id])))
	sim.minutes = 19.5 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.update(1.0 / 30.0)
	eq(z.state, "wander", "at dusk it is only wandering again (and will join the night)")
	g.world.free()
	b.world.free()


func test_a_save_keeps_the_look_timer_so_a_loaded_game_notices_when_the_saved_one_does() -> void:
	# (the stragglers look about every LOOK_EVERY seconds; a load that started the timer afresh gave a loaded game its own moments of
	# noticing: the same camp, saved and loaded, did not go on the same way, the digest of the round-20 integration test found it)
	var g := _game()
	var sim = g.sim
	var half: float = Streets.LOOK_EVERY * 0.6
	sim.streets._look_t = half
	var text := SaveGame.to_text(SaveGame.to_dict(sim))
	var b := Helpers.make(9, 1, 3)
	check(SaveGame.apply(b.sim, SaveGame.from_text(text)), "it loads")
	near(float(b.sim.streets._look_t), half, 1.0e-9, "the timer is where it was")
	# a save from before the timer was kept (no streets in it) looks about at once, as a new game does
	var old: Dictionary = SaveGame.from_text(text)
	(old.modules as Dictionary).erase("streets")
	var c := Helpers.make(9, 1, 3)
	check(SaveGame.apply(c.sim, old), "an old save loads")
	near(float(c.sim.streets._look_t), 0.0, 1.0e-9, "and its timer is the start's")
	# and a damaged value is the start's too, never a timer that would not run out
	var bad: Dictionary = SaveGame.from_text(text)
	bad.modules["streets"] = {"look_t": 1.0e9}
	var e := Helpers.make(9, 1, 3)
	check(SaveGame.apply(e.sim, bad), "a save with a silly timer loads")
	check(float(e.sim.streets._look_t) <= Streets.LOOK_EVERY, "and the timer is no longer than a look: %s" % str(e.sim.streets._look_t))
	g.world.free()
	b.world.free()
	c.world.free()
	e.world.free()


func test_a_shot_by_day_draws_only_the_stragglers_close_by_and_not_to_the_walls() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = sim.people[0]
	ruth.x = 40.0
	ruth.y = 12.0
	ruth.order = Vector3(ruth.x, ruth.y, 0.0)    # (stays where she is put: with no job she would walk to a rest spot, round 16)
	var hunter = sim.spawn(46.0, 12.0, "wander")
	sim.streets._look_t = 0.0
	sim.streets.update(0.1)
	var far: Array = []
	for x in [12.5, 14.5, 66.5, 70.5]:
		far.append(sim.spawn(x, 9.5, "wander"))
	var near_one = sim.spawn(36.0, 11.0, "wander")
	for i in 90:
		ruth.x = 40.0
		ruth.y = 12.0
		sim.update(1.0 / 30.0)
	check(ruth.stats.shots > 0, "Ruth fired")
	for z in far:
		check(z.state == "wander", "a straggler 25 tiles off is not drawn by the shots (%s)" % z.state)
	check(near_one.state == "hunt" or near_one.state == "dying" or near_one.state == "dead", "but the one beside her hears it and comes for her (%s)" % near_one.state)
	for z in sim.zombies:
		check(z.state != "approach" and z.state != "attack", "nobody goes for the walls by day")
	g.world.free()


func test_the_stragglers_still_about_at_dusk_come_off_the_nights_budget_not_on_top_of_it() -> void:
	var g := _game()
	var sim = g.sim
	sim.waves.enabled = true
	sim.day = 6
	sim.minutes = 19.05 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	for i in 5:
		sim.spawn(10.0 + float(i), 9.5, "wander")
	sim.update(1.0 / 30.0)
	check(sim.waves.budget_total > 0.0, "a night is planned")
	near(sim.waves.budget_left, sim.waves.budget_total - 5.0, 1.0, "five of the dead are already out: five fewer are sent")
	g.world.free()
