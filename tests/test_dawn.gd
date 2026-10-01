extends "res://tests/case.gd"
## At dawn the dead go back to the city, a few a step rather than all in one
## step (each leaving is a path search).

const Helpers := preload("res://tests/helpers.gd")
const Sim := preload("res://scripts/sim/sim.gd")


func _retreating(sim) -> int:
	var n := 0
	for z in sim.zombies:
		if z.state == "retreat":
			n += 1
	return n


func test_the_dead_leave_a_few_at_a_time_and_all_of_them_by_the_end_of_dawn() -> void:
	var g := Helpers.make(51, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	for k in 40:
		var z = sim.spawn(30.0 + float(k % 10) * 3.0, 6.0 + float(k / 10) * 2.0, "approach")
		z.speed = 0.6
	sim.minutes = 5.5 * 60.0 - 0.5
	sim.phase = sim.phase_at(sim.minutes)
	var peak := 0
	var before := _retreating(sim)
	eq(before, 0, "nobody is leaving in the night")
	# the first step that starts the dawn
	for i in 60:
		sim.update(1.0 / 30.0)
		if sim.phase == "dawn":
			break
	eq(sim.phase, "dawn", "it is dawn")
	var first := _retreating(sim)
	check(first <= Sim.DAWN_LEAVES_PER_STEP, "at most %d leave in the step that starts the dawn: %d" % [Sim.DAWN_LEAVES_PER_STEP, first])
	check(first > 0, "and some do")
	Helpers.run(sim, 14.0)
	var left := 0
	for z in sim.zombies:
		if z.state != "retreat" and z.state != "dead" and z.state != "dying":
			left += 1
	eq(left, 0, "within the dawn every one of them is on its way out (or gone)")
	g.world.free()
