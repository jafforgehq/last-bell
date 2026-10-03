extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")


func _alive(sim) -> int:
	var n := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			n += 1
	return n


func test_the_budget_grows_with_the_day_and_the_difficulty() -> void:
	var g := Helpers.make(1, 1)
	var w = g.sim.waves
	near(w.budget_for(1), 30.0, 0.001, "the first night at standard")
	near(w.budget_for(11), 60.0, 0.001, "ten days later the night is twice as big")
	g.sim.difficulty = 0
	near(w.budget_for(1), 21.0, 0.001, "story is 70%")
	g.sim.difficulty = 2
	near(w.budget_for(1), 42.0, 0.001, "brutal is 140%")
	g.world.free()


func test_the_day_brings_nobody_and_the_night_brings_its_budget() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	Helpers.run_to_hour(sim, 18.9)
	eq(sim.waves.spawned, 0, "nobody is sent in the daytime")
	check(_alive(sim) <= 4, "the four wanderers of a quiet start are all there is")
	Helpers.run_to_hour(sim, 5.5)
	near(sim.waves.budget_total, 30.0, 0.001, "night one had a budget of 30")
	check(sim.waves.spawned >= 26 and sim.waves.spawned <= 30, "the night brought about its budget, not more: %d" % sim.waves.spawned)
	g.world.free()


func test_a_bigger_day_brings_a_bigger_night() -> void:
	var g := Helpers.make(4, 1)
	var sim = g.sim
	sim.day = 11
	sim.minutes = 18.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	Helpers.run_to_hour(sim, 19.1)
	near(sim.waves.budget_total, 60.0, 0.001, "night eleven has a budget of 60")
	g.world.free()


func test_no_more_than_the_cap_are_alive_at_once() -> void:
	var g := Helpers.make(5, 1)
	var sim = g.sim
	sim.minutes = 21.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.waves.night_day = sim.day
	sim.waves.budget_total = 400.0
	sim.waves.budget_left = 400.0
	Helpers.run(sim, 150.0)
	check(_alive(sim) <= 50, "at most 50 at night: %d" % _alive(sim))
	check(sim.waves.budget_left < 400.0, "and they did come")
	g.world.free()


func test_a_lost_run_brings_nobody() -> void:
	var g := Helpers.make(6, 1)
	var sim = g.sim
	sim.minutes = 21.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.over = "defeat"
	var before: int = sim.zombies.size()
	Helpers.run(sim, 30.0)
	eq(sim.zombies.size(), before, "the rules stand still")
	g.world.free()


func test_the_budget_survives_a_save() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	Helpers.run_to_hour(sim, 22.0)
	var saved: Dictionary = sim.waves.save()
	var other := Helpers.make(8, 1)
	other.sim.waves.load_state(saved)
	eq(other.sim.waves.save(), saved, "the same budget, left, day and count")
	g.world.free()
	other.world.free()


# ------------------------------------------------------------- round 19 --

func test_a_plan_has_its_kind_and_the_old_keys_and_nothing_big_without_an_avatar() -> void:
	var g := Helpers.make(9, 1, 5)
	var w = g.sim.waves
	for day in [1, 5, 10, 20, 29, 30]:
		var plan: Dictionary = w.plan_for(day)
		for key in ["day", "big", "budget", "queue", "counts", "heading", "shown"]:
			check(plan.has(key), "night %d has `%s`" % [day, key])
		eq(plan.kind, "final" if day == 30 else "ordinary", "night %d: no milestone without an avatar" % day)
		eq(plan.plated, false, "night %d: nothing is plated" % day)
		near(float(plan.main_share), w.MAIN_SHARE, 1e-12, "night %d: the old share" % day)
		eq(plan.big, day == 30, "night %d: only the last is big" % day)
	g.world.free()


func test_the_budget_and_the_cap_of_a_no_avatar_night_are_the_old_ones() -> void:
	var g := Helpers.make(9, 1, 5)
	var w = g.sim.waves
	near(w.night_budget(10), w.budget_for(10) * g.sim.storyteller.budget_mult(10) * g.sim.recruits.crew_scale() * g.sim.town.budget_mult(), 1e-9, "night 10 is no milestone")
	near(w.night_budget(30), w.budget_for(30) * g.sim.seasons.big_factor() * g.sim.storyteller.budget_mult(30) * g.sim.recruits.crew_scale() * g.sim.town.budget_mult(), 1e-9, "the last night has its factor")
	eq(int(w.plan_for(30).get("cap", -1)), 0, "and the cap is the phase's, as it was")
	g.world.free()


func test_a_big_night_of_an_avatar_game_survives_a_save() -> void:
	var g := Helpers.avatar_game(7, 5)
	var sim = g.sim
	Helpers.run_to_hour(sim, 22.0)
	var saved: Dictionary = sim.waves.save()
	var other := Helpers.avatar_game(8, 5)
	other.sim.waves.load_state(saved)
	eq(other.sim.waves.save(), saved, "the same budget, left, day and count")
	eq(other.sim.waves.big_night(10), sim.waves.big_night(10), "and the same Big Nights")
	g.world.free()
	other.world.free()
