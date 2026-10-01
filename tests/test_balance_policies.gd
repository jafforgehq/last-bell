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


## Sets the clock without waiting for it.
func _at(sim, hour: float) -> void:
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0


func _play_seconds(sim, policy, seconds: int) -> void:
	for i in seconds * 30:
		sim.update(1.0 / 30.0)
		if i % 30 == 0:
			policy.tick()


func test_the_informed_policy_stands_the_crew_on_the_decks_and_rings_the_alarm_at_dusk() -> void:
	var g := Helpers.make(73, 1)
	var sim = g.sim
	sim.waves.enabled = false
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	_at(sim, 17.2)
	_play_seconds(sim, policy, 4)
	var on_decks := 0
	for p in sim.people:
		if p.drafted and p.order != null and sim.world.on_deck(p.order.x, p.order.y):
			on_decks += 1
	eq(on_decks, sim.people.size(), "everyone is sent to a deck once the evening comes")
	var scrap_before: float = sim.stock.scrap
	_at(sim, 19.1)
	_play_seconds(sim, policy, 3)
	check(sim.tactics.lure_seg() != null, "the alarm is ringing at dusk")
	near(float(sim.stock.scrap), scrap_before - sim.tactics.LURE_COST, 0.01, "and cost its scrap")
	_at(sim, 6.4)
	_play_seconds(sim, policy, 3)
	for p in sim.people:
		check(not p.drafted, "%s is released by day" % p.first)
	g.world.free()


func test_the_default_policy_does_not_stand_anyone_on_a_deck_or_ring_the_alarm() -> void:
	var g := Helpers.make(73, 1)
	var sim = g.sim
	sim.waves.enabled = false
	var policy = Balance.Policy.new(sim)
	_at(sim, 17.2)
	_play_seconds(sim, policy, 4)
	_at(sim, 19.1)
	_play_seconds(sim, policy, 3)
	eq(sim.tactics.lure_seg(), null, "no alarm")
	for p in sim.people:
		check(not (p.drafted and p.order != null and sim.world.on_deck(p.order.x, p.order.y)), "%s was not sent up" % p.first)
	g.world.free()
