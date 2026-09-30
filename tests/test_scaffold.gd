extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")


func test_a_new_run_starts_on_day_one_at_seven() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	eq(sim.day, 1, "the run starts on day 1")
	near(sim.hour, 7.0, 0.001, "at 07:00")
	eq(sim.phase, "day", "in the daytime")
	eq(sim.stock.food, 41.0, "the starting food")
	eq(sim.stock.water, 120.0, "the starting water")
	eq(sim.people.size(), 6, "six survivors")
	check(sim.zombies.size() == 4, "a quiet yard: four wanderers")
	g.world.free()


func test_the_rules_are_reproducible_from_a_seed() -> void:
	var a := Helpers.make(11, 1)
	var b := Helpers.make(11, 1)
	var c := Helpers.make(12, 1)
	Helpers.run(a.sim, 40.0)
	Helpers.run(b.sim, 40.0)
	Helpers.run(c.sim, 40.0)
	var sig := func(sim) -> String:
		var out := ""
		for z in sim.zombies:
			out += "%.3f,%.3f;" % [z.x, z.y]
		return out
	eq(sig.call(a.sim), sig.call(b.sim), "the same seed gives the same walkers")
	check(sig.call(a.sim) != sig.call(c.sim), "another seed gives another run")
	a.world.free()
	b.world.free()
	c.world.free()


func test_a_game_day_passes_without_errors_with_the_stub_modules() -> void:
	var g := Helpers.make(5, 1)
	Helpers.run(g.sim, 480.0)
	check(g.sim.day >= 2, "a day later it is day 2 or more")
	g.world.free()


func test_the_rules_stop_when_the_run_is_over() -> void:
	var g := Helpers.make(1, 1)
	g.sim.over = "defeat"
	var before: float = g.sim.minutes
	Helpers.run(g.sim, 5.0)
	eq(g.sim.minutes, before, "the clock stands still")
	g.world.free()


func test_a_dead_person_is_out_of_play() -> void:
	var g := Helpers.make(2, 1)
	var p = g.sim.people[0]
	p.dead = true
	var x: float = p.x
	var y: float = p.y
	Helpers.run(g.sim, 10.0)
	eq([p.x, p.y], [x, y], "the dead do not walk")
	check(not g.sim.order_move(p, x + 2.0, y), "and take no orders")
	g.world.free()
