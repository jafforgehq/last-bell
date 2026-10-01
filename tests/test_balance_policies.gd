extends "res://tests/case.gd"
## The harness's second policy: hide in the school from the bell to dawn. The
## audit used it to show that hiding beat defending; it stays as the check that
## hiding does not.

const Helpers := preload("res://tests/helpers.gd")
const Balance := preload("res://tools/balance.gd")


func test_the_hide_policy_takes_everyone_into_the_school_at_night_and_lets_them_out_at_dawn() -> void:
	var g := Helpers.make(71, 1)
	var sim = g.sim
	sim.waves.enabled = false
	var policy = Balance.Policy.new(sim)
	policy.hide = true
	sim.minutes = 19.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = true
	for i in 45 * 30:
		sim.update(1.0 / 30.0)
		if i % 30 == 0:
			policy.tick()
	for p in sim.people:
		check(sim.in_school(p), "%s is in the school at night (y=%.1f)" % [p.first, p.y])
	sim.minutes = 6.4 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	for i in 5 * 30:
		sim.update(1.0 / 30.0)
		if i % 30 == 0:
			policy.tick()
	for p in sim.people:
		check(not p.drafted, "%s is let out at dawn" % p.first)
	g.world.free()


func test_a_game_played_with_the_hide_policy_still_counts_a_victory_as_survived() -> void:
	var r: Dictionary = Balance.play(72, 0, 1, 15.0, true, func(sim): sim.waves.enabled = false, true)
	eq(r.outcome, "survived", "one quiet day is survived")
	eq(r.day, 1, "on day 1")
