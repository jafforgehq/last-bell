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
