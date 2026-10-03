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
	for p in sim.people:
		check(not p.drafted, "%s is left at their station while there is daylight to work" % p.first)
	_at(sim, 18.3)
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


# ----------------------------------------------------------- beds first (round 16) --

## A settlement game of five whose school is full (Hector has come), a morning of day 3 with `scrap` in the stores.
func _full_school(scrap: float) -> Dictionary:
	var g := Helpers.make(75, 1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	_at(sim, 8.0)
	sim.stock.scrap = scrap
	sim.add_person(sim.recruits.queue.pop_front())
	return g


func test_the_informed_policy_builds_tents_first_when_the_school_is_full_and_someone_is_waiting() -> void:
	var g := _full_school(40.0)
	var sim = g.sim
	eq(int(sim.recruits.housing_free()), 0, "the six beds are taken")
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	policy.builds = true
	_play_seconds(sim, policy, 3)
	eq(String(sim.build.plot("tents_home_1").site.get("building", "")), "tents", "the first tent is ordered, before the salvage bench that comes first in the order")
	eq(sim.build.plot("salvage_bench_home").site, {}, "and nothing else")
	eq(policy.builds_ordered, 1, "one order")
	g.world.free()


func test_the_tent_waits_for_the_scrap_to_spare_and_the_policy_saves_for_it() -> void:
	var g := _full_school(15.0)
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	policy.builds = true
	_play_seconds(sim, policy, 3)
	eq(policy.builds_ordered, 0, "eight scrap and twelve to spare is twenty: not yet")
	eq(sim.build.plot("salvage_bench_home").site, {}, "and the others wait for it")
	g.world.free()


func test_a_second_tent_follows_the_first_and_the_bunk_house_after_them() -> void:
	var g := _full_school(100.0)
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	policy.builds = true
	sim.build.plot("tents_home_1").building = "tents"
	sim.build.version += 1
	sim.add_person(sim.recruits.make_def(0))
	sim.add_person(sim.recruits.make_def(1))    # the two new beds are taken
	eq(int(sim.recruits.housing_free()), 0, "full again")
	_play_seconds(sim, policy, 3)
	eq(String(sim.build.plot("tents_home_2").site.get("building", "")), "tents", "the second tent")
	g.world.free()


func test_with_a_bed_to_spare_or_in_the_classic_start_the_order_is_the_old_one() -> void:
	var g := Helpers.make(75, 1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.day = 3
	_at(sim, 8.0)
	sim.stock.scrap = 100.0
	eq(int(sim.recruits.housing_free()), 1, "one bed to spare")
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	policy.builds = true
	_play_seconds(sim, policy, 3)
	eq(sim.build.plot("tents_home_1").site, {}, "no tent")
	eq(String(sim.build.plot("salvage_bench_home").site.get("building", "")), "salvage_bench", "the salvage bench, as before")
	g.world.free()
	var c := Helpers.make(75, 1)
	c.sim.waves.enabled = false
	c.sim.day = 3
	_at(c.sim, 8.0)
	c.sim.stock.scrap = 100.0
	var p2 = Balance.Policy.new(c.sim)
	p2.informed = true
	p2.builds = true
	_play_seconds(c.sim, p2, 3)
	eq(c.sim.build.plot("tents_home_1").site, {}, "the classic start has no callers, so no tent")
	c.world.free()


func test_without_beds_first_the_informed_policy_builds_as_it_did_before_the_tents() -> void:
	var g := _full_school(40.0)
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	policy.builds = true
	policy.beds_first = false
	_play_seconds(sim, policy, 3)
	eq(sim.build.plot("tents_home_1").site, {}, "no tent (--nobeds)")
	eq(String(sim.build.plot("salvage_bench_home").site.get("building", "")), "salvage_bench", "the salvage bench, first of the order")
	g.world.free()


# ------------------------------------------------- round 19: the avatar is not a worker --

func test_the_policy_treats_the_player_as_nobody_to_give_work() -> void:
	var g := Helpers.avatar_game(76, 5)
	var sim = g.sim
	sim.waves.enabled = false
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	var me = sim.avatar.player()
	var other = null
	for p in sim.people:
		if p != me:
			other = p
	check(not policy._free(me), "the player is never free to be given a job, an errand or a post")
	check(policy._free(other), "anyone else on their feet is")
	eq(policy._hands_home(), sim.people.size() - 1, "the hands at home are everyone but the player")
	g.world.free()


func test_the_avatar_flag_is_off_by_default_and_a_game_without_it_has_no_player() -> void:
	eq(Balance.avatar_mode, "none", "no avatar unless --avatar says so")
	eq(Balance.nightstats_on, false, "and no night rows")
	var g := Helpers.make(77, 1, 5)
	eq(g.sim.player_id, "", "the harness's own game has nobody for a player")
	var policy = Balance.policy_for(g.sim, false, true)
	check(policy.informed and policy.builds, "the informed policy made by `policy_for` builds as it always did")
	g.world.free()
