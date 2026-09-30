extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const Medical := preload("res://scripts/sim/medical.gd")

## An open spot in the hall, a short walk from the infirmary door.
const HALL := Vector2(46.0, 46.5)
const COT_A := Vector2(47.0, 56.9)
const COT_B := Vector2(48.6, 56.9)


# ------------------------------------------------------------------ helpers --

## A new run with no walkers about: nothing bites or claws unless a test makes it.
func _clinic(seed_value: int = 1, difficulty: int = 1) -> Dictionary:
	var g := Helpers.make(seed_value, difficulty)
	g.sim.zombies.clear()
	return g


func _who(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## Puts `p` at (x, y) and, with `hold`, has them stand there on the player's
## order (so they neither walk off nor count as a free healer).
func _put(sim, p, x: float, y: float, hold: bool = true) -> void:
	p.x = x
	p.y = y
	p.path = []
	p.goal_key = ""
	if hold:
		sim.order_move(p, x, y)


## Everyone except the named people stands still on an order, so the named ones
## are the only free healers.
func _only_free(sim, ids: Array) -> void:
	for p in sim.people:
		if not ids.has(p.id):
			sim.order_move(p, p.x, p.y)


## Steps the rules until `done` is true; returns the seconds it took, or -1.
func _run_until(sim, seconds: float, done: Callable) -> float:
	var t := 0.0
	while t < seconds:
		if done.call():
			return t
		sim.update(1.0 / 30.0)
		t += 1.0 / 30.0
	return -1.0


func _sel(p) -> Dictionary:
	return {"kind": "person", "ref": p}


func _has_banner(sim, needle: String) -> bool:
	for e in sim.events:
		if e.type == "banner" and String(e.text).contains(needle):
			return true
	return false


## Infected `hours_ago` game hours ago, turning in `hours_left` (negative:
## overdue). Infection times are clock values (-1 means none), so a clock that
## has only just started is moved on far enough to hold them.
func _infect(sim, p, hours_ago: float, hours_left: float) -> void:
	sim.clock_min = maxf(sim.clock_min, hours_ago * 60.0 + 10.0)
	p.infected_at = sim.clock_min - hours_ago * 60.0
	p.turn_at = sim.clock_min + hours_left * 60.0


## The share of encounters that end in an infection at this difficulty, each
## made of `bites` bites a few seconds apart.
func _infection_rate(difficulty: int, bites: int, rounds: int) -> float:
	var g := _clinic(7, difficulty)
	var sim = g.sim
	var p = _who(sim, "hector")
	var infected := 0
	for i in rounds:
		sim.clock_min += 180.0
		p.infected_at = -1.0
		p.turn_at = -1.0
		for k in bites:
			sim.clock_min += 4.0
			sim.medical.add_wound(p, "bite")
		if p.infected_at >= 0.0:
			infected += 1
	g.world.free()
	return float(infected) / float(rounds)


# ------------------------------------------------------------------ wounds --

func test_a_bite_starts_a_wound_that_bleeds() -> void:
	var g := _clinic()
	var sim = g.sim
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, HALL.x, HALL.y)
	var z = sim.spawn(HALL.x + 0.4, HALL.y, "breach")
	sim._bite(z, marcus)
	check(marcus.hp < 91.5 and marcus.hp > 84.5, "a bite takes 9 to 15 health at once, got %s" % marcus.hp)
	eq(marcus.wounds, 1, "one wound")
	near(marcus.bleeding, 4.0, 0.0001, "a bite bleeds 4 an hour")
	sim._bite(z, marcus)
	eq(marcus.wounds, 2, "two wounds")
	near(marcus.bleeding, 8.0, 0.0001, "the wounds add up")
	sim.medical.add_wound(marcus, "scratch")
	eq(marcus.wounds, 3, "a scratch is a wound too")
	near(marcus.bleeding, 10.0, 0.0001, "a scratch bleeds 2 an hour")
	g.world.free()


func test_bleeding_costs_health_at_the_stated_rate() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.stock.meds = 0.0 # nobody can bandage
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, HALL.x, HALL.y)
	marcus.hp = 100.0
	sim.medical.add_wound(marcus, "bite")
	Helpers.run(sim, 20.0) # one game hour
	near(marcus.hp, 96.0, 0.05, "4 health in a game hour")
	sim.medical.add_wound(marcus, "scratch")
	Helpers.run(sim, 20.0)
	near(marcus.hp, 90.0, 0.05, "then 6 an hour")
	g.world.free()


func test_bleeding_does_not_depend_on_the_step_size() -> void:
	var a := _clinic(4, 1)
	var b := _clinic(4, 1)
	for g in [a, b]:
		g.sim.stock.meds = 0.0
		var p = _who(g.sim, "marcus")
		_put(g.sim, p, HALL.x, HALL.y)
		p.hp = 100.0
		g.sim.medical.add_wound(p, "bite")
	Helpers.run(a.sim, 20.0)
	for i in 200:
		b.sim.update(0.1)
	check(_who(a.sim, "marcus").hp < 97.0, "it bled")
	near(_who(a.sim, "marcus").hp, _who(b.sim, "marcus").hp, 0.05, "the same loss at 30 and at 10 steps a second")
	a.world.free()
	b.world.free()


func test_bleeding_to_zero_brings_the_person_down() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.stock.meds = 0.0
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, HALL.x, HALL.y)
	marcus.hp = 1.0
	sim.medical.add_wound(marcus, "bite") # 4 an hour: a quarter of an hour, 5 seconds
	Helpers.run(sim, 4.0)
	check(not marcus.downed, "still on his feet after 4 seconds")
	Helpers.run(sim, 2.0)
	check(marcus.downed, "down after 6 seconds")
	near(marcus.hp, 0.0, 0.001, "at zero health")
	check(marcus.bleed_out > 2.5 and marcus.bleed_out <= 3.0, "the three hours start when they fall: %s" % marcus.bleed_out)
	check(sim.alerts.has("down-marcus"), "the alert says so")
	g.world.free()


func test_a_bite_that_takes_the_last_health_downs_the_person() -> void:
	var g := _clinic()
	var sim = g.sim
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, HALL.x, HALL.y)
	marcus.hp = 5.0
	var z = sim.spawn(HALL.x + 0.4, HALL.y, "breach")
	sim._bite(z, marcus)
	check(marcus.downed, "downed by the bite")
	near(marcus.hp, 0.0, 0.001, "at zero")
	near(marcus.bleed_out, 3.0, 0.001, "three game hours to be stabilised")
	check(not marcus.stabilised, "not stabilised yet")
	check(not marcus.moving, "not walking")
	eq(marcus.order, null, "no orders left")
	check(not marcus.drafted, "and not drafted")
	eq(marcus.wounds, 1, "the bite left a wound")
	g.world.free()


# --------------------------------------------------------------- infection --

func test_a_bite_infects_at_the_difficultys_chance() -> void:
	near(_infection_rate(0, 1, 500), 0.3, 0.08, "story: 30%")
	near(_infection_rate(1, 1, 500), 0.6, 0.08, "standard: 60%")
	near(_infection_rate(2, 1, 100), 1.0, 0.0001, "brutal: always")


func test_a_run_of_bites_is_one_roll() -> void:
	# six bites in a row must not raise 30% to 88%
	near(_infection_rate(0, 6, 500), 0.3, 0.08, "the chance is per person, not per bite")


func test_a_scratch_never_infects() -> void:
	var g := _clinic(2, 2)
	var sim = g.sim
	var p = _who(sim, "hector")
	for i in 300:
		sim.clock_min += 180.0
		sim.medical.add_wound(p, "scratch")
	eq(p.infected_at, -1.0, "never infected by a scratch, even on brutal")
	eq(p.wounds, 300, "but every scratch is a wound")
	g.world.free()


func test_an_infected_person_is_not_infected_again() -> void:
	var g := _clinic(2, 2)
	var sim = g.sim
	var p = _who(sim, "hector")
	sim.medical.add_wound(p, "bite")
	check(p.infected_at >= 0.0, "brutal bites always infect")
	var at: float = p.infected_at
	var turn: float = p.turn_at
	sim.clock_min += 120.0
	sim.medical.add_wound(p, "bite")
	eq(p.infected_at, at, "the infection time stays")
	eq(p.turn_at, turn, "so does the turn time")
	g.world.free()


func test_infection_stages() -> void:
	var g := _clinic()
	var sim = g.sim
	var p = _who(sim, "hector")
	eq(sim.medical.infection_stage(p), "", "healthy")
	p.infected_at = sim.clock_min
	p.turn_at = sim.clock_min + 18.0 * 60.0
	eq(sim.medical.infection_stage(p), "", "no sign at first")
	sim.clock_min = p.infected_at + 5.9 * 60.0
	eq(sim.medical.infection_stage(p), "", "nothing before 6 hours")
	sim.clock_min = p.infected_at + 6.0 * 60.0
	eq(sim.medical.infection_stage(p), "feverish", "feverish at 6 hours")
	sim.clock_min = p.infected_at + 9.9 * 60.0
	eq(sim.medical.infection_stage(p), "feverish", "still feverish before 10")
	sim.clock_min = p.infected_at + 10.0 * 60.0
	eq(sim.medical.infection_stage(p), "delirious", "delirious at 10 hours")
	p.dead = true
	eq(sim.medical.infection_stage(p), "", "nothing for the dead")
	g.world.free()


func test_the_fever_is_announced_once_per_stage() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.stock.meds = 0.0
	var p = _who(sim, "hector")
	_put(sim, p, HALL.x, HALL.y)
	_infect(sim, p, 5.9, 20.0)
	Helpers.run(sim, 1.0)
	check(not sim.alerts.has("fever-hector"), "no alert before the fever")
	Helpers.run(sim, 4.0)
	check(sim.alerts.has("fever-hector"), "an alert when the fever starts")
	sim.alerts.erase("fever-hector")
	Helpers.run(sim, 2.0)
	check(not sim.alerts.has("fever-hector"), "and not again")
	g.world.free()


func test_the_turn_comes_between_12_and_24_hours() -> void:
	var g := _clinic(5, 2)
	var sim = g.sim
	var p = _who(sim, "hector")
	var lo := 1.0e9
	var hi := 0.0
	var sum := 0.0
	var n := 300
	for i in n:
		sim.clock_min += 2000.0
		p.infected_at = -1.0
		sim.medical.add_wound(p, "bite")
		var span: float = p.turn_at - p.infected_at
		lo = minf(lo, span)
		hi = maxf(hi, span)
		sum += span
	check(lo >= 720.0, "never before 12 hours, got %s minutes" % lo)
	check(hi <= 1440.0, "never after 24 hours, got %s minutes" % hi)
	check(lo < 800.0 and hi > 1360.0, "and it spreads over the whole range: %s to %s" % [lo, hi])
	near(sum / n, 1080.0, 60.0, "about 18 hours on average")
	g.world.free()


func test_an_infected_person_turns_into_a_named_walker() -> void:
	var g := _clinic(3, 1)
	var sim = g.sim
	var walt = _who(sim, "walt")
	_put(sim, walt, HALL.x, HALL.y)
	_infect(sim, walt, 11.0, 1.0)
	sim.stock.meds = 0.0
	Helpers.run(sim, 19.0)
	check(not walt.turned and not walt.dead, "not yet, with a few seconds to go")
	eq(sim.zombies.size(), 0, "no walker yet")
	Helpers.run(sim, 2.0)
	check(walt.turned, "turned")
	check(walt.dead, "and gone from the living")
	eq(sim.zombies.size(), 1, "one new walker")
	var z = sim.zombies[0]
	eq(z.turned_name, "Walt Haney", "it has his name")
	eq(z.state, "breach", "and it hunts at once")
	check(Vector2(z.x, z.y).distance_to(HALL) < 1.0, "where he stood")
	check(sim.alerts.has("turned-walt"), "an alert")
	check(_has_banner(sim, "Walt has turned"), "and a banner")
	eq(walt.infected_at, -1.0, "the infection is over")
	g.world.free()


func test_a_person_resting_in_bed_turns_in_bed() -> void:
	var g := _clinic(3, 1)
	var sim = g.sim
	var walt = _who(sim, "walt")
	walt.x = COT_A.x
	walt.y = COT_A.y
	walt.hp = 12.0
	walt.downed = true
	walt.stabilised = true
	walt.resting_bed = COT_A
	_infect(sim, walt, 11.0, 0.1)
	Helpers.run(sim, 4.0)
	check(walt.turned and walt.dead, "turned")
	eq(sim.zombies.size(), 1, "one walker")
	check(Vector2(sim.zombies[0].x, sim.zombies[0].y).distance_to(COT_A) < 1.0, "in the bed")
	eq(walt.resting_bed, null, "the bed is free")
	g.world.free()


func test_an_infected_person_away_turns_when_back() -> void:
	var g := _clinic(3, 1)
	var sim = g.sim
	var walt = _who(sim, "walt")
	_put(sim, walt, HALL.x, HALL.y)
	sim.stock.meds = 0.0
	walt.away = {"kind": "party"}
	_infect(sim, walt, 13.0, -1.0) # overdue
	Helpers.run(sim, 3.0)
	check(not walt.turned, "nobody turns off the map")
	walt.away = null
	Helpers.run(sim, 1.0)
	check(walt.turned, "but at once when back")
	g.world.free()


# ---------------------------------------------------------------- scratches --

func test_a_claw_sometimes_scratches_a_defender_behind_the_wall() -> void:
	var g := _clinic(6, 2)
	var sim = g.sim
	var gate = sim.segments[2]
	var slot = gate.slots[3]
	var z = sim.spawn(slot.x, slot.y, "attack")
	var ruth = _who(sim, "ruth")
	_put(sim, ruth, z.x, gate.center.y)
	var n := 2000
	for i in n:
		sim.medical.on_wall_claw(z, gate)
	check(ruth.wounds >= 50 and ruth.wounds <= 115, "about 4%% of claws: %d in %d" % [ruth.wounds, n])
	near(ruth.bleeding, 2.0 * ruth.wounds, 0.001, "each one bleeds 2 an hour")
	eq(ruth.infected_at, -1.0, "a scratch never infects")
	check(sim.alerts.has("scratch-ruth"), "the alert")
	eq(sim.alerts["scratch-ruth"].text, "Ruth was scratched", "names her")
	g.world.free()


func test_nobody_is_scratched_unless_right_behind_the_wall() -> void:
	var g := _clinic(6, 2)
	var sim = g.sim
	var gate = sim.segments[2]
	var slot = gate.slots[3]
	var z = sim.spawn(slot.x, slot.y, "attack")
	var ruth = _who(sim, "ruth")
	_put(sim, ruth, z.x + 1.0, gate.center.y)
	for i in 1500:
		sim.medical.on_wall_claw(z, gate)
	check(ruth.wounds > 20, "a tile along the wall is still in reach: %d" % ruth.wounds)
	ruth.wounds = 0
	_put(sim, ruth, z.x, gate.center.y + 3.0)
	for i in 1500:
		sim.medical.on_wall_claw(z, gate)
	eq(ruth.wounds, 0, "three tiles back is safe")
	_put(sim, ruth, z.x + 4.0, gate.center.y)
	for i in 1500:
		sim.medical.on_wall_claw(z, gate)
	eq(ruth.wounds, 0, "and so is four tiles along the wall")
	_put(sim, ruth, z.x, gate.center.y, false)
	ruth.downed = true
	for i in 1500:
		sim.medical.on_wall_claw(z, gate)
	eq(ruth.wounds, 0, "the downed are not scratched again")
	ruth.downed = false
	ruth.away = {"kind": "party"}
	for i in 1500:
		sim.medical.on_wall_claw(z, gate)
	eq(ruth.wounds, 0, "and nobody who is away")
	g.world.free()


func test_the_rules_claw_reaches_the_medical_module() -> void:
	# the rules' own claw, with the gate kept whole: Ruth at her post behind it
	var g := _clinic(8, 1)
	var sim = g.sim
	sim.stock.meds = 0.0
	var gate = sim.segments[2]
	var z = sim.spawn(gate.slots[3].x, gate.slots[3].y, "attack")
	var ruth = _who(sim, "ruth")
	_put(sim, ruth, 39.25, 18.8)
	for i in 1500:
		gate.hp = gate.max_hp
		sim._claw(z, gate)
	check(ruth.wounds >= 35 and ruth.wounds <= 90, "about 4%% of 1500 claws: %d" % ruth.wounds)
	g.world.free()


# ------------------------------------------------------------------ healers --

func test_the_nurse_bandages_a_bleeding_person() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var ana = _who(sim, "ana")
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, HALL.x, HALL.y)
	sim.medical.add_wound(marcus, "bite")
	sim.medical.add_wound(marcus, "scratch")
	var meds: float = sim.stock.meds
	Helpers.run(sim, 0.2)
	eq(ana.activity, "Bandaging Marcus", "she sets out")
	var goal = sim.medical.goal_for(ana)
	check(goal != null and goal.what == "Bandaging Marcus", "her goal says what she is doing")
	check(Vector2(goal.x, goal.y).distance_to(Vector2(marcus.x, marcus.y)) <= 0.9, "and is within reach of him")
	eq(sim.medical.goal_for(marcus), null, "he has no duty of his own")
	var began := _run_until(sim, 30.0, func(): return sim.medical.jobs.size() == 1 and sim.medical.jobs[0].work > 0.0)
	check(began >= 0.0, "she got there and began")
	var worked := _run_until(sim, 10.0, func(): return marcus.wounds == 0)
	near(worked, 10.0 / 3.0, 0.15, "a bandage takes 10 game minutes, 3.3 seconds at normal speed")
	eq(marcus.bleeding, 0.0, "the bleeding stopped")
	eq(marcus.wounds, 0, "no wounds left")
	near(sim.stock.meds, meds - 1.0, 0.0001, "one medicine used")
	Helpers.run(sim, 0.5)
	eq(sim.medical.jobs.size(), 0, "nothing left to do")
	check(String(ana.activity) != "Bandaging Marcus", "she is back to her work: %s" % ana.activity)
	g.world.free()


func test_the_nearest_healer_with_medicine_goes_and_the_best_is_preferred() -> void:
	var g := _clinic()
	var sim = g.sim
	var hector = _who(sim, "hector")
	var marcus = _who(sim, "marcus")
	_put(sim, hector, HALL.x, HALL.y)
	_put(sim, marcus, HALL.x + 1.0, HALL.y, false) # right beside him, free, but no Medicine
	sim.medical.add_wound(hector, "scratch")
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs.size(), 1, "one job")
	eq(sim.medical.jobs[0].healer.id, "ana", "Ana first")
	# with Ana busy on an order, the next best goes (Ruth, Medicine 2)
	var g2 := _clinic()
	var s2 = g2.sim
	_put(s2, _who(s2, "hector"), HALL.x, HALL.y)
	_put(s2, _who(s2, "marcus"), HALL.x + 1.0, HALL.y, false)
	s2.order_move(_who(s2, "ana"), 48.5, 53.5)
	s2.medical.add_wound(_who(s2, "hector"), "scratch")
	Helpers.run(s2, 0.1)
	eq(s2.medical.jobs.size(), 1, "one job")
	eq(s2.medical.jobs[0].healer.id, "ruth", "then Ruth, not Marcus who stands next to him")
	# nobody with Medicine free: nobody goes
	for id in ["ruth", "dez", "walt"]:
		s2.order_move(_who(s2, id), _who(s2, id).x, _who(s2, id).y)
	Helpers.run(s2, 0.1)
	eq(s2.medical.jobs.size(), 0, "no free healer, no job (Marcus is free and right there, but has no Medicine)")
	# skill beats distance: Dez stands beside the patient, Ana is twelve tiles away, Ana goes
	var g3 := _clinic()
	var s3 = g3.sim
	_put(s3, _who(s3, "hector"), 43.5, 30.4)
	_put(s3, _who(s3, "dez"), 43.5, 29.4, false) # at his generator, a tile away
	_put(s3, _who(s3, "ana"), 43.5, 41.0, false)
	s3.medical.add_wound(_who(s3, "hector"), "scratch")
	Helpers.run(s3, 0.1)
	eq(s3.medical.jobs.size(), 1, "one job")
	eq(s3.medical.jobs[0].healer.id, "ana", "the better healer is worth a walk")
	g.world.free()
	g2.world.free()
	g3.world.free()


func test_a_drafted_healer_is_not_free_until_released() -> void:
	var g := _clinic()
	var sim = g.sim
	for p in sim.people:
		sim.order_move(p, p.x, p.y)
	var hector = _who(sim, "hector")
	sim.medical.add_wound(hector, "scratch")
	Helpers.run(sim, 0.5)
	eq(sim.medical.jobs.size(), 0, "everyone is on an order")
	sim.toggle_draft(_who(sim, "dez"))
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs.size(), 1, "released, Dez comes")
	eq(sim.medical.jobs[0].healer.id, "dez", "it is Dez")
	g.world.free()


func test_a_healer_takes_one_patient_at_a_time() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var hector = _who(sim, "hector")
	var marcus = _who(sim, "marcus")
	_put(sim, hector, HALL.x, HALL.y)
	_put(sim, marcus, HALL.x - 3.0, HALL.y)
	sim.medical.add_wound(hector, "bite")
	sim.medical.add_wound(marcus, "bite")
	var meds: float = sim.stock.meds
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs.size(), 1, "she takes one of them")
	var both := _run_until(sim, 60.0, func(): return hector.wounds == 0 and marcus.wounds == 0)
	check(both > 0.0, "and then the other")
	near(sim.stock.meds, meds - 2.0, 0.0001, "two bandages, two medicines")
	g.world.free()


func test_no_medicine_means_no_bandage_and_one_alert() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.stock.meds = 0.0
	_only_free(sim, ["ana"])
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, HALL.x, HALL.y)
	sim.medical.add_wound(marcus, "bite")
	Helpers.run(sim, 6.0)
	check(sim.alerts.has("no-meds"), "the alert")
	eq(sim.alerts["no-meds"].text, "No medicine", "says so")
	eq(sim.alerts["no-meds"].t, sim.alerts["no-meds"].born, "raised once in six seconds, not over and over")
	eq(marcus.wounds, 1, "the wound stays")
	check(marcus.bleeding > 0.0, "still bleeding")
	eq(sim.stock.meds, 0.0, "nothing went negative")
	check(String(_who(sim, "ana").activity) != "Bandaging Marcus", "Ana is not standing around waiting")
	# medicine arrives: she goes at once
	sim.stock.meds = 3.0
	var took := _run_until(sim, 30.0, func(): return marcus.wounds == 0)
	check(took > 0.0, "bandaged once there is medicine")
	near(sim.stock.meds, 2.0, 0.0001, "one used")
	g.world.free()


func test_one_medicine_serves_one_patient() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.stock.meds = 1.0
	_only_free(sim, ["ana", "ruth"])
	var hector = _who(sim, "hector")
	var marcus = _who(sim, "marcus")
	_put(sim, hector, HALL.x, HALL.y)
	_put(sim, marcus, HALL.x - 3.0, HALL.y)
	sim.medical.add_wound(hector, "bite")
	sim.medical.add_wound(marcus, "bite")
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs.size(), 1, "only one job: there is only one bandage")
	Helpers.run(sim, 40.0)
	eq(sim.stock.meds, 0.0, "used up, not below")
	check((hector.wounds == 0) != (marcus.wounds == 0), "exactly one of them was bandaged")
	check(sim.alerts.has("no-meds"), "and the other is told about")
	g.world.free()


func test_nobody_away_or_dead_is_treated_and_none_of_them_treats() -> void:
	var g := _clinic()
	var sim = g.sim
	var marcus = _who(sim, "marcus")
	var hector = _who(sim, "hector")
	_put(sim, marcus, HALL.x, HALL.y)
	sim.medical.add_wound(marcus, "bite")
	marcus.away = {"kind": "party"}
	Helpers.run(sim, 1.0)
	eq(sim.medical.jobs.size(), 0, "an away patient is not treated")
	marcus.away = null
	marcus.dead = true
	Helpers.run(sim, 1.0)
	eq(sim.medical.jobs.size(), 0, "a dead one neither")
	marcus.dead = false
	# away or dead healers are not sent
	for id in ["ana", "ruth", "dez", "walt"]:
		var p = _who(sim, id)
		if id == "ana" or id == "ruth":
			p.away = {"kind": "party"}
		else:
			p.dead = true
	_put(sim, hector, HALL.x + 2.0, HALL.y, false)
	Helpers.run(sim, 1.0)
	eq(sim.medical.jobs.size(), 1, "Marcus is treated, by the only healer left")
	eq(sim.medical.jobs[0].healer.id, "hector", "the only one of them left, and a healer, is Hector")
	check(sim.medical.jobs[0].patient != hector, "not himself")
	g.world.free()


func test_a_healer_does_not_treat_themselves() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var ana = _who(sim, "ana")
	sim.medical.add_wound(ana, "bite")
	Helpers.run(sim, 1.0)
	eq(sim.medical.jobs.size(), 0, "Ana cannot bandage herself, and nobody else is free")
	sim.toggle_draft(_who(sim, "dez"))
	Helpers.run(sim, 0.2)
	eq(sim.medical.jobs.size(), 1, "Dez can")
	g.world.free()


func test_the_downed_come_before_the_bleeding() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var hector = _who(sim, "hector")
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, HALL.x, HALL.y)
	_put(sim, hector, HALL.x + 4.0, HALL.y)
	sim.medical.add_wound(marcus, "bite") # bleeding
	hector.hp = 0.0
	sim.medical.on_downed(hector, "bite") # down
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs.size(), 1, "one healer, one job")
	eq(sim.medical.jobs[0].patient.id, "hector", "the downed man first")
	g.world.free()


func test_a_healer_on_the_way_to_a_scratch_is_turned_to_the_downed() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var hector = _who(sim, "hector")
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, 28.0, HALL.y) # far off
	_put(sim, hector, 52.0, HALL.y)
	sim.medical.add_wound(marcus, "scratch")
	Helpers.run(sim, 0.5)
	eq(sim.medical.jobs.size(), 1, "on her way")
	eq(sim.medical.jobs[0].patient.id, "marcus", "to Marcus")
	hector.hp = 0.0
	sim.medical.on_downed(hector, "bite")
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs.size(), 1, "still one job")
	eq(sim.medical.jobs[0].patient.id, "hector", "turned around to the man who is down")
	var done := _run_until(sim, 60.0, func(): return hector.stabilised)
	check(done > 0.0, "and she stabilised him")
	var both := _run_until(sim, 60.0, func(): return marcus.wounds == 0)
	check(both > 0.0, "then she got to Marcus")
	g.world.free()


func test_a_bandage_in_progress_is_not_taken_away() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var ana = _who(sim, "ana")
	var hector = _who(sim, "hector")
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, 49.0, 50.5) # in the infirmary, right by her
	sim.medical.add_wound(marcus, "scratch")
	Helpers.run(sim, 1.5)
	check(Vector2(ana.x, ana.y).distance_to(Vector2(marcus.x, marcus.y)) <= 0.9, "she is at his side")
	check(sim.medical.jobs.size() == 1 and sim.medical.jobs[0].work > 0.0, "and at work")
	_put(sim, hector, HALL.x, HALL.y)
	hector.hp = 0.0
	sim.medical.on_downed(hector, "bite")
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs[0].patient.id, "marcus", "she finishes the one she started")
	g.world.free()


func test_a_patient_who_shifts_a_little_is_still_reached() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	sim.medical.add_wound(hector, "bite")
	Helpers.run(sim, 0.3) # she has set out, and worked out where to wait
	_put(sim, hector, HALL.x - 0.35, HALL.y) # he steps aside
	var done := _run_until(sim, 30.0, func(): return hector.wounds == 0)
	check(done > 0.0, "she still gets to him and bandages him")
	g.world.free()


func test_a_healer_at_a_spot_out_of_reach_finds_a_new_one() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var ana = _who(sim, "ana")
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	sim.medical.add_wound(hector, "bite")
	Helpers.run(sim, 0.2)
	var job = sim.medical.jobs[0]
	var bad := Vector2(HALL.x + 1.6, HALL.y) # a waiting spot that is too far off
	job.stand = bad
	job.anchor = Vector2(hector.x, hector.y)
	ana.x = bad.x
	ana.y = bad.y
	ana.path = []
	ana.goal_key = ""
	var done := _run_until(sim, 30.0, func(): return hector.wounds == 0)
	check(done > 0.0, "she works out a better spot and finishes")
	g.world.free()


func test_a_healer_who_goes_down_drops_the_job() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana", "ruth"])
	var ana = _who(sim, "ana")
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, HALL.x, HALL.y)
	sim.medical.add_wound(marcus, "bite")
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs[0].healer.id, "ana", "Ana is on it")
	ana.hp = 0.0
	sim.medical.on_downed(ana, "bite")
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs.size(), 1, "the job passed on")
	eq(sim.medical.jobs[0].healer.id, "ruth", "to Ruth")
	eq(sim.medical.goal_for(ana), null, "Ana has no goal while down")
	g.world.free()


# ------------------------------------------------------------------- downed --

func test_a_downed_person_is_stabilised_put_to_bed_and_gets_up() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	hector.hp = 0.0
	sim.medical.on_downed(hector, "bite")
	check(hector.downed, "down")
	near(hector.bleed_out, 3.0, 0.0001, "three hours")
	eq(sim.alerts["down-hector"].sub, "Get them to Ana", "the alert names Ana")
	eq(hector.activity, "Down and bleeding", "what the panel says")
	var meds: float = sim.stock.meds
	var took := _run_until(sim, 40.0, func(): return hector.stabilised)
	check(took > 0.0, "stabilised in time")
	eq(hector.bleed_out, -1.0, "the clock stops")
	check(hector.downed, "still down")
	eq(hector.resting_bed, COT_A, "in the first cot")
	eq(Vector2(hector.x, hector.y), COT_A, "carried there")
	eq(hector.activity, "Resting in the infirmary", "resting")
	near(sim.stock.meds, meds - 1.0, 0.0001, "one medicine")
	check(not sim.alerts.has("down-hector"), "the alert is gone")
	near(hector.hp, 0.0, 0.5, "no health yet")
	Helpers.run(sim, 20.0)
	near(hector.hp, 10.0, 0.6, "10 health an hour in bed")
	var up := _run_until(sim, 70.0, func(): return not hector.downed)
	check(up > 0.0, "gets up")
	check(hector.hp >= 40.0 and hector.hp < 41.0, "at 40 health: %s" % hector.hp)
	eq(hector.resting_bed, null, "out of bed")
	eq(hector.dead, false, "alive")
	check(sim.alerts.has("up-hector"), "an alert that he is up")
	Helpers.run(sim, 4.0)
	check(Vector2(hector.x, hector.y).distance_to(COT_A) > 1.0, "and back to work")
	g.world.free()


func test_beds_go_to_cots_first_then_the_bunks() -> void:
	var g := _clinic()
	var sim = g.sim
	var spots := []
	for id in ["hector", "marcus", "walt", "dez"]:
		var p = _who(sim, id)
		_put(sim, p, HALL.x, HALL.y, false)
		p.hp = 0.0
		sim.medical.on_downed(p, "bite")
		sim.medical.stabilise(p)
		spots.append(p.resting_bed)
	eq(spots[0], COT_A, "the nearest cot first")
	eq(spots[1], COT_B, "then the other cot")
	check(spots[2] != null and spots[2].x < 44.0 and absf(spots[2].y - 56.6) < 0.001, "then the bunks: %s" % str(spots[2]))
	check(spots[3] != null and spots[3] != spots[2], "a different mattress")
	for id in ["hector", "marcus", "walt", "dez"]:
		var p = _who(sim, id)
		eq(Vector2(p.x, p.y), p.resting_bed, "carried to the bed")
	g.world.free()


func test_with_no_bed_free_the_patient_stays_put_and_still_heals() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.medical.beds = []
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y, false)
	hector.hp = 0.0
	sim.medical.on_downed(hector, "bite")
	sim.medical.stabilise(hector)
	check(hector.stabilised and hector.downed, "stabilised and down")
	eq(hector.resting_bed, null, "no bed")
	eq(Vector2(hector.x, hector.y), HALL, "where they were")
	var up := _run_until(sim, 90.0, func(): return not hector.downed)
	check(up > 0.0, "gets up all the same")
	g.world.free()


func test_left_alone_the_downed_die_after_three_hours() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.stock.meds = 0.0
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	hector.hp = 0.0
	sim.medical.on_downed(hector, "bite")
	Helpers.run(sim, 59.0)
	check(not hector.dead, "alive after 2 hours 57")
	check(hector.bleed_out > 0.0 and hector.bleed_out < 0.1, "with minutes left: %s" % hector.bleed_out)
	Helpers.run(sim, 2.0)
	check(hector.dead, "dead after three hours")
	eq(hector.turned, false, "not turned")
	check(sim.alerts.has("dead-hector"), "an alert")
	eq(sim.alerts["dead-hector"].text, "Hector died", "says so")
	check(_has_banner(sim, "Hector died"), "and a banner")
	g.world.free()


func test_with_permadeath_off_nobody_dies_of_bleeding() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.permadeath = false
	sim.stock.meds = 0.0
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	hector.hp = 0.0
	sim.medical.on_downed(hector, "bite")
	Helpers.run(sim, 62.0)
	check(not hector.dead, "alive")
	check(hector.stabilised, "stabilised by themselves")
	eq(hector.resting_bed, COT_A, "and taken to bed")
	var up := _run_until(sim, 90.0, func(): return not hector.downed)
	check(up > 0.0, "and they get up again")
	g.world.free()


func test_the_down_alert_names_ana_only_while_she_can_help() -> void:
	var g := _clinic()
	var sim = g.sim
	var hector = _who(sim, "hector")
	var ana = _who(sim, "ana")
	sim.medical.on_downed(hector, "bite")
	eq(sim.alerts["down-hector"].sub, "Get them to Ana", "Ana is able")
	var g2 := _clinic()
	var s2 = g2.sim
	_who(s2, "ana").away = {"kind": "party"}
	s2.medical.on_downed(_who(s2, "hector"), "bite")
	eq(s2.alerts["down-hector"].sub, "Stabilise them", "Ana is away")
	var g3 := _clinic()
	var s3 = g3.sim
	s3.medical.on_downed(_who(s3, "ana"), "bite")
	eq(s3.alerts["down-ana"].sub, "Stabilise them", "Ana herself is down")
	g.world.free()
	g2.world.free()
	g3.world.free()


func test_nobody_bleeds_while_resting() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.stock.meds = 0.0
	var hector = _who(sim, "hector")
	hector.hp = 10.0
	hector.downed = true
	hector.stabilised = true
	hector.bleeding = 8.0
	hector.wounds = 2
	Helpers.run(sim, 20.0)
	near(hector.hp, 20.0, 0.6, "it only heals")
	g.world.free()


func test_going_down_twice_changes_nothing() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.stock.meds = 0.0
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	hector.hp = 0.0
	sim.medical.on_downed(hector, "hunger")
	Helpers.run(sim, 10.0)
	var left: float = hector.bleed_out
	sim.medical.on_downed(hector, "hunger")
	near(hector.bleed_out, left, 0.0001, "the clock goes on")
	g.world.free()


func test_a_downed_healer_is_not_sent() -> void:
	var g := _clinic()
	var sim = g.sim
	var ana = _who(sim, "ana")
	ana.hp = 0.0
	sim.medical.on_downed(ana, "bite")
	var marcus = _who(sim, "marcus")
	_put(sim, marcus, HALL.x, HALL.y)
	sim.medical.add_wound(marcus, "scratch")
	Helpers.run(sim, 0.2)
	check(sim.medical.jobs.size() >= 1, "somebody is sent")
	for j in sim.medical.jobs:
		check(j.healer.id != "ana", "not Ana, who is down")
	check(not sim.order_move(ana, 40.0, 46.5), "and she takes no orders")
	g.world.free()


# ---------------------------------------------------------------- infection --

func test_treating_an_infection_costs_two_medicines_and_takes_fifteen_minutes() -> void:
	var g := _clinic(12, 1)
	var sim = g.sim
	_only_free(sim, ["ana"])
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	_infect(sim, hector, 8.0, 10.0)
	check(sim.medical.can_treat(hector), "the button is offered")
	var meds: float = sim.stock.meds
	check(sim.medical.gizmo("treat", _sel(hector)), "the order is taken")
	Helpers.run(sim, 0.2)
	eq(sim.medical.jobs.size(), 1, "Ana is sent")
	eq(sim.medical.jobs[0].kind, "infection", "to treat the infection")
	eq(_who(sim, "ana").activity, "Treating Hector", "what she is doing")
	var began := _run_until(sim, 40.0, func(): return sim.medical.jobs.size() == 1 and sim.medical.jobs[0].work > 0.0)
	check(began >= 0.0, "Ana gets there and begins")
	var worked := _run_until(sim, 10.0, func(): return sim.medical.jobs.is_empty())
	near(worked, 5.0, 0.15, "15 game minutes is 5 seconds at normal speed")
	near(sim.stock.meds, meds - 2.0, 0.0001, "two medicines used, win or lose")
	check(not sim.medical.treat_orders.has("hector"), "the order is used up")
	if hector.infected_at < 0.0:
		eq(hector.turn_at, -1.0, "cured: no turn time either")
		eq(sim.medical.infection_stage(hector), "", "and no fever")
	else:
		check(sim.medical.can_treat(hector), "failed: it can be ordered again")
	g.world.free()


func test_the_cure_chance_is_thirty_percent_plus_ten_a_point_of_medicine() -> void:
	var g := _clinic()
	var m = g.sim.medical
	near(m.cure_chance(_who(g.sim, "ana")), 0.9, 0.0001, "Ana, Medicine 10: capped at 90%")
	near(m.cure_chance(_who(g.sim, "ruth")), 0.5, 0.0001, "Ruth, Medicine 2")
	near(m.cure_chance(_who(g.sim, "walt")), 0.5, 0.0001, "Walt, Medicine 2")
	near(m.cure_chance(_who(g.sim, "dez")), 0.4, 0.0001, "Dez, Medicine 1")
	near(m.cure_chance(_who(g.sim, "marcus")), 0.3, 0.0001, "Medicine 0")
	g.world.free()


func test_the_cure_rate_follows_the_healers_medicine() -> void:
	var g := _clinic(9, 1)
	var sim = g.sim
	var hector = _who(sim, "hector")
	for spec in [["ana", 0.9], ["ruth", 0.5], ["walt", 0.5], ["dez", 0.4]]:
		var healer = _who(sim, spec[0])
		var ok := 0
		var n := 400
		for i in n:
			sim.stock.meds = 10.0
			_infect(sim, hector, 8.0, 10.0)
			if sim.medical.try_cure(healer, hector):
				ok += 1
				eq(hector.infected_at, -1.0, "cured means not infected")
			near(sim.stock.meds, 8.0, 0.0001, "each try costs 2")
		near(float(ok) / float(n), spec[1], 0.07, "%s: 30%% plus 10%% a point, at most 90%%" % spec[0])
	g.world.free()


func test_a_failed_cure_can_be_ordered_again() -> void:
	var g := _clinic(14, 1)
	var sim = g.sim
	_only_free(sim, ["dez"]) # Medicine 1: a 40% chance
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	sim.stock.meds = 100.0
	var failures := 0
	var tries := 0
	for attempt in 40:
		tries += 1
		_infect(sim, hector, 8.0, 10.0)
		check(sim.medical.gizmo("treat", _sel(hector)), "ordered, try %d" % attempt)
		var took := _run_until(sim, 40.0, func(): return sim.medical.jobs.is_empty() and not sim.medical.treat_orders.has("hector"))
		check(took >= 0.0, "try %d ended" % attempt)
		if hector.infected_at >= 0.0:
			failures += 1
			check(sim.medical.can_treat(hector), "after a failure it can be ordered again")
			if failures >= 2:
				break
	check(failures >= 2, "with 40%% chances, two failures turn up in 40 tries: %d" % failures)
	near(sim.stock.meds, 100.0 - 2.0 * float(tries), 0.0001, "two medicines every time")
	g.world.free()


func test_treating_a_person_with_no_medicine_left_waits() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	sim.stock.meds = 1.0 # one is not enough for an infection
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	_infect(sim, hector, 8.0, 10.0)
	check(sim.medical.gizmo("treat", _sel(hector)), "taken")
	Helpers.run(sim, 2.0)
	eq(sim.medical.jobs.size(), 0, "no job without the medicine")
	check(sim.alerts.has("no-meds"), "an alert")
	Helpers.run(sim, 8.0)
	eq(sim.medical.jobs.size(), 0, "still none")
	eq(sim.stock.meds, 1.0, "untouched")
	sim.stock.meds = 5.0
	var took := _run_until(sim, 40.0, func(): return sim.medical.jobs.is_empty() and not sim.medical.treat_orders.has("hector"))
	check(took > 0.0, "done when it arrives")
	near(sim.stock.meds, 3.0, 0.0001, "two used")
	g.world.free()


func test_bleeding_people_are_treated_before_an_infection() -> void:
	var g := _clinic()
	var sim = g.sim
	_only_free(sim, ["ana"])
	var hector = _who(sim, "hector")
	var marcus = _who(sim, "marcus")
	_put(sim, hector, HALL.x, HALL.y)
	_put(sim, marcus, HALL.x + 4.0, HALL.y)
	_infect(sim, hector, 8.0, 10.0)
	sim.medical.gizmo("treat", _sel(hector))
	sim.medical.add_wound(marcus, "bite")
	Helpers.run(sim, 0.1)
	eq(sim.medical.jobs.size(), 1, "one job")
	eq(sim.medical.jobs[0].patient.id, "marcus", "the bleeding man first, even though she had set out for the cure")
	var both := _run_until(sim, 60.0, func(): return marcus.wounds == 0 and sim.medical.treat_orders.is_empty())
	check(both > 0.0, "then the cure")
	g.world.free()


func test_sending_out_walks_to_the_gate_and_removes_them() -> void:
	var g := _clinic()
	var sim = g.sim
	var walt = _who(sim, "walt") # his job spot is on the wall walk, a few tiles from the gate
	_infect(sim, walt, 7.0, 10.0)
	check(sim.medical.can_send_out(walt), "offered for an infected person")
	check(sim.medical.gizmo("sendout", _sel(walt)), "the order is taken")
	Helpers.run(sim, 0.3)
	eq(walt.activity, "Leaving through the gate", "what he is doing")
	check(not walt.dead and walt.away == null, "still here")
	var took := _run_until(sim, 30.0, func(): return walt.away != null)
	check(took > 0.0, "he gets there and leaves")
	check(walt.dead, "gone for good")
	eq(walt.away.kind, "exile", "as an exile")
	check(Vector2(walt.x, walt.y).distance_to(sim.segments[2].center) <= 1.3, "at the gate")
	check(sim.alerts.has("exile-walt"), "an alert")
	eq(sim.alerts["exile-walt"].text, "Walt left through the gate", "says so")
	check(not sim.order_move(walt, 40.0, 30.0), "no more orders")
	eq(sim.zombies.size(), 0, "he did not turn")
	var t: int = sim.medical.sendouts.size()
	eq(t, 0, "the order is finished")
	g.world.free()


func test_a_new_order_cancels_a_send_out() -> void:
	var g := _clinic()
	var sim = g.sim
	var walt = _who(sim, "walt")
	_infect(sim, walt, 7.0, 10.0)
	sim.medical.gizmo("sendout", _sel(walt))
	Helpers.run(sim, 0.3)
	check(sim.order_move(walt, 52.0, 22.0), "the player changes their mind")
	Helpers.run(sim, 0.2)
	eq(sim.medical.sendouts.size(), 0, "the send-out is off")
	Helpers.run(sim, 20.0)
	check(walt.away == null and not walt.dead, "he is still here")
	g.world.free()


func test_a_resting_infected_person_can_be_sent_out_and_gets_up() -> void:
	var g := _clinic()
	var sim = g.sim
	var walt = _who(sim, "walt")
	walt.x = COT_A.x
	walt.y = COT_A.y
	walt.hp = 12.0
	walt.downed = true
	walt.stabilised = true
	walt.resting_bed = COT_A
	_infect(sim, walt, 7.0, 10.0)
	check(sim.medical.can_send_out(walt), "a patient in bed can be sent out")
	check(sim.medical.gizmo("sendout", _sel(walt)), "taken")
	check(not walt.downed, "he is on his feet")
	eq(walt.resting_bed, null, "and out of the bed")
	var took := _run_until(sim, 60.0, func(): return walt.away != null)
	check(took > 0.0, "and leaves")
	g.world.free()


func test_the_buttons_follow_the_state() -> void:
	var g := _clinic()
	var sim = g.sim
	var m = sim.medical
	var p = _who(sim, "hector")
	check(not m.can_treat(p) and not m.can_send_out(p), "a healthy person offers neither")
	check(not m.gizmo("treat", _sel(p)) and not m.gizmo("sendout", _sel(p)), "and the orders are refused")
	check(not m.gizmo("treat", {"kind": "segment", "ref": sim.segments[0]}), "nothing for a wall")
	check(not m.gizmo("draft", _sel(p)), "it does not take other buttons")
	m.add_wound(p, "scratch")
	check(m.can_treat(p) and not m.can_send_out(p), "bleeding: treat")
	p.bleeding = 0.0
	p.wounds = 0
	check(not m.can_treat(p), "bandaged")
	p.downed = true
	p.stabilised = false
	check(m.can_treat(p), "down and not stabilised: treat")
	check(not m.can_send_out(p), "but not send out")
	_infect(sim, p, 1.0, 14.0)
	check(not m.can_send_out(p), "and not when infected and down: they cannot walk")
	p.stabilised = true
	check(m.can_send_out(p), "stabilised, they can be sent out")
	p.downed = false
	p.stabilised = false
	check(m.can_treat(p) and m.can_send_out(p), "infected: both")
	p.away = {"kind": "party"}
	check(not m.can_treat(p) and not m.can_send_out(p), "away: neither")
	p.away = null
	p.dead = true
	check(not m.can_treat(p) and not m.can_send_out(p), "dead: neither")
	g.world.free()


# --------------------------------------------------------------- the rest ----

func test_perf_drops_when_badly_hurt() -> void:
	var g := _clinic()
	var sim = g.sim
	var p = _who(sim, "hector")
	p.hp = 100.0
	near(sim.medical.perf(p), 1.0, 0.0001, "healthy")
	p.hp = 40.0
	near(sim.medical.perf(p), 1.0, 0.0001, "40 is fine")
	p.hp = 39.9
	near(sim.medical.perf(p), 0.85, 0.0001, "under 40 is 0.85")
	p.hp = 1.0
	near(sim.perf(p), 0.85, 0.0001, "the rules use it")
	g.world.free()


func test_status_marks() -> void:
	var g := _clinic()
	var sim = g.sim
	var m = sim.medical
	var p = _who(sim, "hector")
	var icons := func(person) -> Array:
		var out := []
		for s in m.status_of(person):
			out.append(s.icon)
			check(s.color is Color, "a colour")
			check(String(s.tip) != "", "and a tip")
		return out
	eq(icons.call(p), [], "nothing when well")
	p.bleeding = 4.0
	p.wounds = 1
	eq(icons.call(p), ["wound"], "bleeding")
	p.bleeding = 0.0
	p.wounds = 0
	_infect(sim, p, 2.0, 14.0)
	eq(icons.call(p), [], "an infection shows nothing for six hours")
	_infect(sim, p, 7.0, 10.0)
	eq(icons.call(p), ["fever"], "then a fever")
	eq(m.status_of(p)[0].tip, "Feverish", "the tip names the stage")
	_infect(sim, p, 11.0, 6.0)
	eq(m.status_of(p)[0].tip, "Delirious", "delirious later")
	p.infected_at = -1.0
	p.turn_at = -1.0
	p.downed = true
	eq(icons.call(p), ["down"], "down")
	p.stabilised = true
	eq(icons.call(p), ["resting"], "resting once stabilised")
	p.bleeding = 4.0
	_infect(sim, p, 7.0, 10.0)
	eq(icons.call(p), ["wound", "fever", "resting"], "all together, in this order")
	p.dead = true
	eq(icons.call(p), [], "nothing for the dead")
	g.world.free()


func test_kill() -> void:
	var g := _clinic()
	var sim = g.sim
	var p = _who(sim, "hector")
	p.x = COT_A.x
	p.y = COT_A.y
	p.downed = true
	p.stabilised = true
	p.resting_bed = COT_A
	p.bleeding = 4.0
	p.wounds = 1
	sim.medical.kill(p, "bled out")
	check(p.dead and p.downed, "dead and lying")
	eq(p.resting_bed, null, "the bed is free")
	eq(p.bleeding, 0.0, "no more bleeding")
	eq(sim.alerts["dead-hector"].text, "Hector died", "the alert")
	check(String(sim.alerts["dead-hector"].sub).to_lower().contains("bled out"), "gives the cause: %s" % sim.alerts["dead-hector"].sub)
	check(_has_banner(sim, "Hector died"), "a banner")
	var banners := 0
	for e in sim.events:
		if e.type == "banner":
			banners += 1
	sim.medical.kill(p, "bled out")
	var after := 0
	for e in sim.events:
		if e.type == "banner":
			after += 1
	eq(after, banners, "dying twice is one death")
	# a loss on a trip has its own story: no second banner
	var q = _who(sim, "marcus")
	sim.events.clear()
	sim.medical.kill(q, "scavenging")
	check(q.dead, "dead")
	check(sim.alerts.has("dead-marcus"), "still recorded")
	check(not _has_banner(sim, "Marcus died"), "the trip's own banner tells it")
	g.world.free()


func test_the_dead_are_left_alone() -> void:
	var g := _clinic()
	var sim = g.sim
	var p = _who(sim, "hector")
	_put(sim, p, HALL.x, HALL.y)
	sim.medical.add_wound(p, "bite")
	sim.medical.kill(p, "bled out")
	sim.stock.meds = 7.0
	Helpers.run(sim, 10.0)
	eq(sim.medical.jobs.size(), 0, "no job for the dead")
	eq(sim.stock.meds, 7.0, "no medicine wasted")
	check(not sim.alerts.has("no-meds"), "no alert either")
	g.world.free()


func test_a_bite_from_a_walker_leads_to_a_bandage() -> void:
	# the whole chain through the rules' own bite, with no shortcuts
	var g := _clinic(31, 0)
	var sim = g.sim
	_only_free(sim, ["ana"])
	var hector = _who(sim, "hector")
	_put(sim, hector, HALL.x, HALL.y)
	hector.hp = 60.0
	var z = sim.spawn(HALL.x + 0.5, HALL.y, "breach")
	z.attack_t = 0.0
	var bitten := _run_until(sim, 5.0, func(): return hector.wounds > 0)
	check(bitten >= 0.0, "the walker bit him")
	z.state = "dying" # and is shot
	z.fall = 0.0
	check(hector.bleeding >= 4.0, "he bleeds")
	var meds: float = sim.stock.meds
	var done := _run_until(sim, 60.0, func(): return hector.wounds == 0)
	check(done > 0.0, "Ana bandaged him")
	near(sim.stock.meds, meds - 1.0, 0.0001, "for one medicine")
	check(hector.hp > 30.0 and hector.hp < 52.0, "he is weaker for it: %s" % hector.hp)
	g.world.free()


# --------------------------------------------------------------------- save --

func test_save_and_load_state_round_trip() -> void:
	var a := _clinic(3, 1)
	var sim = a.sim
	_only_free(sim, ["ana"])
	var hector = _who(sim, "hector")
	var marcus = _who(sim, "marcus")
	_put(sim, hector, HALL.x, HALL.y)
	_put(sim, marcus, HALL.x - 5.0, HALL.y)
	sim.medical.add_wound(hector, "bite")
	sim.medical.add_wound(marcus, "scratch")
	_infect(sim, marcus, 8.0, 9.0)
	sim.medical.gizmo("treat", _sel(marcus))
	var at := _run_until(sim, 20.0, func(): return sim.medical.jobs.size() == 1 and sim.medical.jobs[0].work > 2.0)
	check(at >= 0.0, "a treatment is under way")
	var data: Dictionary = sim.medical.save()
	var parsed = JSON.parse_string(JSON.stringify(data))
	check(typeof(parsed) == TYPE_DICTIONARY, "it survives JSON")
	check(parsed.jobs.size() == 1 and parsed.jobs[0].has("stand"), "with the job and its waiting spot")
	# another sim, the people's own fields copied (the save module's job) and the module restored
	var b := _clinic(3, 1)
	var other = b.sim
	other.clock_min = sim.clock_min
	other.minutes = sim.minutes
	other.rng.state = sim.rng.state
	other.stock = sim.stock.duplicate()
	for p in sim.people:
		var q = _who(other, p.id)
		q.x = p.x
		q.y = p.y
		q.hp = p.hp
		q.bleeding = p.bleeding
		q.wounds = p.wounds
		q.infected_at = p.infected_at
		q.turn_at = p.turn_at
		q.drafted = p.drafted
		q.order = p.order
		q.facing = p.facing
	other.medical.load_state(parsed)
	eq(JSON.stringify(other.medical.save()), JSON.stringify(data), "the same module state")
	Helpers.run(sim, 20.0)
	Helpers.run(other, 20.0)
	for p in sim.people:
		var q = _who(other, p.id)
		near(q.hp, p.hp, 0.001, "%s hp" % p.id)
		eq(q.wounds, p.wounds, "%s wounds" % p.id)
		eq(q.infected_at, p.infected_at, "%s infection" % p.id)
		near(q.x, p.x, 0.001, "%s x" % p.id)
		near(q.y, p.y, 0.001, "%s y" % p.id)
	near(other.stock.meds, sim.stock.meds, 0.0001, "the same medicine")
	check(sim.stock.meds < 7.0, "and something was used")
	a.world.free()
	b.world.free()


func test_a_damaged_save_is_ignored() -> void:
	var g := _clinic()
	var sim = g.sim
	sim.medical.load_state({})
	sim.medical.load_state({"jobs": [{"healer": "nobody", "patient": "ana", "kind": "bandage", "work": 1.0}], "orders": ["ghost"], "sendouts": {"ghost": 1.0}})
	eq(sim.medical.jobs.size(), 0, "a job with an unknown healer is dropped")
	eq(sim.medical.sendouts.size(), 0, "and so is an unknown send-out")
	Helpers.run(sim, 1.0)
	g.world.free()


# --------------------------------------------------------------------- runs --

## Plays `days` quiet days (no walkers), biting and scratching random people
## and ordering treatment or send-outs for the feverish; returns what it saw.
func _soak(seed_value: int, difficulty: int, days: int, permadeath: bool = true) -> Dictionary:
	var g := _clinic(seed_value, difficulty)
	var sim = g.sim
	sim.permadeath = permadeath
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_value * 7919
	var step := 0.1
	var out := {"worst_down": 0.0, "worst_rest": 0.0, "worst_infected": 0.0, "worst_job": 0.0, "worst_sendout": 0.0, "bad": [], "turned": 0, "exiled": 0, "died": 0, "bandaged": 0, "bites": 0, "cured": 0}
	var down_h := {}
	var rest_h := {}
	var job_h := {}
	var last_day := 1
	for i in int(days * 480.0 / step):
		sim.zombies.clear()
		sim.update(step)
		if sim.day != last_day:
			last_day = sim.day
			sim.stock.meds = maxf(sim.stock.meds, 4.0) # the odd trip brings some back
		var gh: float = sim.game_hours(step)
		# about one injury every two and a half minutes of play (7 game hours)
		if dice.randf() < step / 150.0:
			var living := []
			for p in sim.people:
				if not p.dead and p.away == null and not p.downed:
					living.append(p)
			if not living.is_empty():
				var victim = living[dice.randi() % living.size()]
				if dice.randf() < 0.6:
					sim.medical.add_wound(victim, "bite")
					victim.hp = maxf(0.0, victim.hp - 9.0 - dice.randf() * 6.0)
					out.bites += 1
					if victim.hp <= 0.0:
						sim.medical.on_downed(victim, "bite")
				else:
					sim.medical.add_wound(victim, "scratch")
		for p in sim.people:
			if p.dead or p.away != null:
				continue
			# the player's answer to a fever
			if sim.medical.infection_stage(p) != "" and dice.randf() < step / 4.0 and not sim.medical.treat_orders.has(p.id) and not sim.medical.sendouts.has(p.id):
				if dice.randf() < 0.75:
					sim.medical.gizmo("treat", _sel(p))
				else:
					sim.medical.gizmo("sendout", _sel(p))
			# state rules that must hold at every step
			if p.downed and not p.stabilised:
				if p.bleed_out < 0.0 or p.bleed_out > 3.0001:
					out.bad.append("%s down with bleed_out %s" % [p.id, p.bleed_out])
				down_h[p.id] = float(down_h.get(p.id, 0.0)) + gh
				out.worst_down = maxf(out.worst_down, down_h[p.id])
			else:
				down_h[p.id] = 0.0
			if p.downed and p.stabilised:
				if p.bleed_out != -1.0:
					out.bad.append("%s stabilised with bleed_out %s" % [p.id, p.bleed_out])
				rest_h[p.id] = float(rest_h.get(p.id, 0.0)) + gh
				out.worst_rest = maxf(out.worst_rest, rest_h[p.id])
			else:
				rest_h[p.id] = 0.0
			if p.resting_bed != null and not (p.downed and p.stabilised):
				out.bad.append("%s in bed but not resting" % p.id)
			if p.infected_at >= 0.0:
				out.worst_infected = maxf(out.worst_infected, (sim.clock_min - p.infected_at) / 60.0)
		for p in sim.people:
			if p.dead and (p.bleeding != 0.0 or p.resting_bed != null):
				out.bad.append("%s dead but still bleeding or in bed" % p.id)
		var alive_jobs := {}
		for j in sim.medical.jobs:
			var key: String = "%s>%s" % [j.healer.id, j.patient.id]
			alive_jobs[key] = true
			job_h[key] = float(job_h.get(key, 0.0)) + gh
			out.worst_job = maxf(out.worst_job, job_h[key])
			if job_h[key] > 2.5 and not out.has("stuck"):
				var stand = sim.medical.goal_for(j.healer)
				out["stuck"] = "%s -> %s (%s) after %.1f h: healer at %.2f,%.2f moving %s path %d/%d goal %s; patient at %.2f,%.2f downed %s bed %s; work %.1f; day %d hour %.1f; order %s repair %s" % [j.healer.id, j.patient.id, j.kind, job_h[key], j.healer.x, j.healer.y, j.healer.moving, j.healer.path_i, j.healer.path.size(), str(stand), j.patient.x, j.patient.y, j.patient.downed, str(j.patient.resting_bed), j.work, sim.day, sim.hour, str(j.healer.order), str(j.healer.repair)]
			if j.healer.dead or j.patient.dead or j.healer.away != null or j.patient.away != null:
				out.bad.append("job with a dead or away person: %s" % key)
		for key in job_h.keys():
			if not alive_jobs.has(key):
				job_h.erase(key)
		for id in sim.medical.sendouts.keys():
			out.worst_sendout = maxf(out.worst_sendout, (sim.clock_min - float(sim.medical.sendouts[id])) / 60.0)
		if sim.stock.meds < 0.0:
			out.bad.append("negative medicine")
		var alive := 0
		for p in sim.people:
			if not p.dead:
				alive += 1
		if alive == 0:
			break
	for p in sim.people:
		if p.turned:
			out.turned += 1
		elif p.away != null and p.dead:
			out.exiled += 1
		elif p.dead:
			out.died += 1
	out["sig"] = _signature(sim)
	g.world.free()
	return out


func _signature(sim) -> String:
	var s := "%.3f|" % sim.stock.meds
	for p in sim.people:
		s += "%s:%.3f,%.3f,%.3f,%d,%d,%d,%d,%.3f;" % [p.id, p.hp, p.x, p.y, p.wounds, int(p.downed), int(p.dead), int(p.turned), p.infected_at]
	return s


func test_a_ten_day_run_with_injuries_never_leaves_anyone_stuck() -> void:
	var r := _soak(21, 0, 10)
	eq(r.bad, [], "no broken state")
	check(r.worst_down <= 3.02, "nobody lay unstabilised for more than three hours: %s" % r.worst_down)
	check(r.worst_rest <= 4.2, "nobody rested for more than it takes to reach 40 health: %s" % r.worst_rest)
	check(r.worst_infected <= 24.05, "every infection ended within 24 hours: %s" % r.worst_infected)
	check(r.worst_job <= 2.5, "no job dragged on: %s game hours (%s)" % [r.worst_job, r.get("stuck", "")])
	check(r.worst_sendout <= 1.6, "nobody walked to the gate for ever: %s" % r.worst_sendout)
	check(r.bites > 5, "it did test something: %d bites" % r.bites)


func test_with_the_permadeath_off_nobody_bleeds_to_death_in_ten_days() -> void:
	var r := _soak(22, 2, 10, false)
	eq(r.bad, [], "no broken state")
	eq(r.died, 0, "nobody died (some turned or were sent out)")
	check(r.worst_down <= 3.02, "and nobody lay unstabilised for more than three hours: %s" % r.worst_down)


func test_a_seeded_run_with_injuries_is_identical_twice() -> void:
	var a := _soak(5, 1, 3)
	var b := _soak(5, 1, 3)
	eq(a.sig, b.sig, "the same seed and the same injuries give the same people")
	var c := _soak(6, 1, 3)
	check(a.sig != c.sig, "another seed gives another story")
