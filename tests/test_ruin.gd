extends "res://tests/case.gd"
## The stores live in the yard: while the dead are in it they ruin what is
## there, which is what falling back to the school costs.

const Helpers := preload("res://tests/helpers.gd")
const Supplies := preload("res://scripts/sim/supplies.gd")


## A game at 08:00 (no meal for hours) with the nights off.
func _quiet() -> Dictionary:
	var g := Helpers.make(61, 1)
	var sim = g.sim
	sim.waves.enabled = false
	# nobody mends a wall on their own: that would spend scrap
	sim.tactics.auto.clear()
	sim.zombies.clear()
	sim.minutes = 8.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	return g


func _stock(sim) -> Dictionary:
	return sim.stock.duplicate()


func test_nothing_is_lost_while_nobody_dead_is_in_the_yard() -> void:
	var g := _quiet()
	var sim = g.sim
	var z = sim.spawn(10.0, 30.0, "wander")
	z.speed = 0.0
	var before := _stock(sim)
	Helpers.run(sim, 30.0)
	eq(_stock(sim), before, "the stores are as they were")
	g.world.free()


func test_the_dead_in_the_yard_ruin_the_stores() -> void:
	var g := _quiet()
	var sim = g.sim
	sim._damage_segment(sim.segments[1], 1.0e6)
	for k in 20:
		var z = sim.spawn(28.0 + float(k % 10) * 2.0, 30.0 + float(k / 10) * 2.0, "wander")
		z.speed = 0.0
	var before := _stock(sim)
	Helpers.run(sim, 60.0)
	var share := 1.0 - exp(-Supplies.LOOT_RATE * 20.0 * 60.0)
	for k in ["ammo", "scrap", "food", "water", "meds"]:
		near(sim.stock[k], before[k] * (1.0 - share), before[k] * 0.02 + 0.05, "%s is ruined by about %d%%" % [k, roundi(share * 100.0)])
	check(sim.alerts.has("ruin"), "and the crew is told")
	g.world.free()


func test_the_dead_who_are_leaving_ruin_nothing() -> void:
	var g := _quiet()
	var sim = g.sim
	for k in 20:
		var z = sim.spawn(28.0 + float(k % 10) * 2.0, 30.0, "retreat")
		z.speed = 0.0
	var before := _stock(sim)
	Helpers.run(sim, 20.0)
	eq(_stock(sim), before, "nothing is lost")
	g.world.free()
