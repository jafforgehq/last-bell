extends "res://tests/case.gd"
## The goal: holding out thirty nights ends the run in victory at the dawn that
## starts day 31.

const Helpers := preload("res://tests/helpers.gd")


## A game with the clock at `hour` on `day`, the nights switched off.
func _at(day: int, hour: float) -> Dictionary:
	var g := Helpers.make(31, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.day = day
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.events.clear()
	return g


func _overs(sim) -> Array:
	var out := []
	for e in sim.events:
		if e.type == "over":
			out.append(e.result)
	return out


func test_holding_out_thirty_nights_wins_at_the_dawn_of_day_31() -> void:
	var g := _at(30, 6.4)
	var sim = g.sim
	Helpers.run(sim, 10.0)
	eq(sim.over, "victory", "the run is won")
	eq(sim.day, 31, "on the morning of day 31")
	eq(_overs(sim), ["victory"], "announced once")
	g.world.free()


func test_the_run_is_not_won_before_that() -> void:
	var g := _at(30, 12.0)
	var sim = g.sim
	Helpers.run(sim, 30.0)
	eq(sim.over, "", "still day 30")
	g.world.free()


func test_nobody_left_at_the_dawn_is_a_defeat_not_a_victory() -> void:
	var g := _at(30, 6.4)
	var sim = g.sim
	for p in sim.people:
		p.dead = true
	Helpers.run(sim, 10.0)
	eq(sim.over, "defeat", "nobody to rescue")
	eq(_overs(sim), ["defeat"], "and only that")
	g.world.free()


func test_someone_away_on_a_trip_still_counts_as_alive() -> void:
	var g := _at(30, 6.4)
	var sim = g.sim
	for p in sim.people:
		p.dead = true
	sim.people[0].dead = false
	sim.people[0].away = {"party": true}
	Helpers.run(sim, 10.0)
	eq(sim.over, "victory", "one survivor is enough")
	g.world.free()


func test_the_rules_stand_still_after_the_victory() -> void:
	var g := _at(30, 6.4)
	var sim = g.sim
	Helpers.run(sim, 10.0)
	var minutes: float = sim.minutes
	var day: int = sim.day
	Helpers.run(sim, 30.0)
	near(sim.minutes, minutes, 0.0001, "the clock stopped")
	eq(sim.day, day, "and the day")
	eq(_overs(sim), ["victory"], "no second announcement")
	g.world.free()
