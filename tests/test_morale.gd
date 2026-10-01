extends "res://tests/case.gd"
## Morale (scripts/sim/morale.gd): a value 0 to 100 for each person (70 to start) that
## drifts DRIFT_PER_HOUR points an hour toward 60 plus the continuous modifiers (fed, hungry,
## bleeding, near a friend, the leader, the dead at the wall, a quiet night); shocks (a kill, a
## breach, a friend down or dead...) move it at once and then drift away. Under SHAKEN_BELOW a
## person is Shaken, under BREAKING_BELOW Breaking, under BREAKDOWN_BELOW (from day 4, not on
## Story) they break down for an hour. `enabled = false` switches the whole thing off. The
## numbers the tests quote are read from the module (Morale.DRIFT_PER_HOUR and the rest), so a
## retune does not break them.

const Helpers := preload("res://tests/helpers.gd")
const Morale := preload("res://scripts/sim/morale.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")
const Supplies := preload("res://scripts/sim/supplies.gd")


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## Where `_alone` puts the crew: in the yard, at least 12 tiles from each other.
const SPOTS := [Vector2(22.0, 24.0), Vector2(34.0, 24.0), Vector2(46.0, 24.0), Vector2(58.0, 24.0), Vector2(22.0, 40.0), Vector2(46.0, 40.0)]


## A quiet day: no dead about, no nights, 09:00 on day 5, everyone at least 12 tiles from
## everyone (so no friend and no leader is near anybody).
func _alone(hour: float = 9.0, seed_value: int = 7, difficulty: int = 1) -> Dictionary:
	var g := Helpers.make(seed_value, difficulty)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 5
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.events.clear()
	for i in sim.people.size():
		sim.people[i].x = SPOTS[i].x
		sim.people[i].y = SPOTS[i].y
	return g


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


func _line(sim, p, label: String):
	for e in sim.morale.explain(p):
		if String(e.label).begins_with(label):
			return e
	return null


func _has(sim, p, label: String) -> bool:
	return _line(sim, p, label) != null


func _val(sim, p, label: String) -> float:
	var e = _line(sim, p, label)
	return float(e.value) if e != null else 0.0


## A value well inside each mood, whatever the thresholds are: the middle of its band.
func _inspired_value() -> float:
	return (Morale.INSPIRED_AT + 100.0) / 2.0


func _steady_value() -> float:
	return (Morale.SHAKEN_BELOW + Morale.INSPIRED_AT) / 2.0


func _shaken_value() -> float:
	return (Morale.BREAKING_BELOW + Morale.SHAKEN_BELOW) / 2.0


func _breaking_value() -> float:
	return Morale.BREAKING_BELOW / 2.0


## `n` of the dead clawing at the wall sections `segs`, each in a real place at the wall.
func _clawing(sim, segs: Array, n: int) -> Array:
	var out: Array = []
	for seg in sim.segments:
		if not segs.has(seg.id):
			continue
		for sl in seg.slots:
			if out.size() >= n:
				return out
			if sl.who != null:
				continue
			var z = sim.spawn(sl.x, sl.y, "attack")
			z.slot = sl
			sl.who = z
			z.facing = sl.face
			out.append(z)
	return out


# ----------------------------------------------------------------- the start --

func test_everyone_starts_at_seventy_and_steady() -> void:
	var g := _alone()
	var sim = g.sim
	for p in sim.people:
		near(sim.morale.value(p), 70.0, 0.0001, "%s starts at 70" % p.first)
		eq(sim.morale.mood(p), "Steady", "%s is steady" % p.first)
		near(sim.morale.perf(p), 1.0, 0.0001, "and works as usual")
		check(not sim.morale.breakdown(p), "and is not broken")
		eq(sim.morale.status_of(p), [], "and shows no mark")
	check(sim.morale.enabled, "morale is on")
	g.world.free()


func test_a_new_run_puts_morale_back_to_seventy() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	sim.morale.shock(dez, -50.0, "Test")
	sim.start_run(1, 3)
	near(sim.morale.value(dez), 70.0, 0.0001, "start_run starts it again")
	eq(sim.morale.explain(dez).size() > 0, true, "with its modifiers")
	check(not _has(sim, dez, "Test"), "and no old shocks")
	g.world.free()


# --------------------------------------------------------------------- the target --

func test_the_target_is_sixty_plus_the_continuous_modifiers() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	near(sim.morale.target(dez), 65.0, 0.001, "alone and fed: 60 + 5")
	check(_has(sim, dez, "Well fed and watered"), "the five is listed")
	near(_val(sim, dez, "Well fed and watered"), 5.0, 0.001, "as +5")
	dez.hunger_h = Supplies.HUNGRY_H
	near(sim.morale.target(dez), 52.0, 0.001, "hungry: -8, and no longer well fed")
	check(_has(sim, dez, "Hungry") and not _has(sim, dez, "Well fed"), "listed as Hungry")
	dez.hunger_h = Supplies.STARVING_H
	near(sim.morale.target(dez), 40.0, 0.001, "starving: -20")
	check(_has(sim, dez, "Starving"), "listed")
	dez.hunger_h = 0.0
	dez.thirst_h = Supplies.THIRSTY_H
	near(sim.morale.target(dez), 52.0, 0.001, "thirsty: -8")
	check(_has(sim, dez, "Thirsty"), "listed")
	dez.thirst_h = Supplies.PARCHED_H
	near(sim.morale.target(dez), 40.0, 0.001, "parched: -20")
	check(_has(sim, dez, "Parched"), "listed")
	dez.hunger_h = Supplies.HUNGRY_H
	near(sim.morale.target(dez), 60.0 - 8.0 - 20.0, 0.001, "hungry and parched: -28")
	dez.hunger_h = 0.0
	dez.thirst_h = 0.0
	dez.bleeding = 2.0
	near(sim.morale.target(dez), 59.0, 0.001, "bleeding: -6")
	dez.bleeding = 0.0
	dez.infected_at = 10.0
	near(sim.morale.target(dez), 57.0, 0.001, "infected: -8")
	dez.infected_at = -1.0
	dez.downed = true
	near(sim.morale.target(dez), 50.0, 0.001, "down: -15")
	g.world.free()


func test_a_friend_near_lifts_a_person_by_five() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var hector = _person(sim, "Hector")
	hector.x = dez.x + 5.0
	hector.y = dez.y
	near(sim.morale.target(dez), 70.0, 0.001, "65 and a friend within six tiles")
	check(_has(sim, dez, "Near Hector"), "the line names him")
	near(_val(sim, dez, "Near Hector"), 5.0, 0.001, "+5")
	hector.x = dez.x + 7.0
	near(sim.morale.target(dez), 65.0, 0.001, "at seven tiles it is gone")
	g.world.free()


func test_the_leader_lifts_those_within_ten_tiles() -> void:
	var g := _alone()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var dez = _person(sim, "Dez")
	dez.x = ruth.x + 9.0
	dez.y = ruth.y
	near(_val(sim, dez, "Ruth is leading"), 5.4, 0.001, "Ruth, Leading 9: 9 x 0.6")
	near(sim.morale.target(dez), 65.0 + 5.4, 0.001, "on top of 65")
	dez.x = ruth.x + 10.5
	check(not _has(sim, dez, "Ruth is leading"), "past ten tiles nothing")
	dez.x = ruth.x + 9.0
	ruth.skills.Leading = 12
	near(_val(sim, dez, "Ruth is leading"), 6.0, 0.001, "at most 6")
	ruth.skills.Leading = 9
	ruth.downed = true
	check(not _has(sim, dez, "Ruth is leading"), "not while she is down")
	ruth.downed = false
	ruth.dead = true
	check(not _has(sim, dez, "Ruth is leading"), "nor dead")
	ruth.dead = false
	ruth.away = {"kind": "party"}
	check(not _has(sim, dez, "Ruth is leading"), "nor away")
	ruth.away = null
	check(not _has(sim, ruth, "Ruth is leading"), "a leader is not lifted by herself")
	g.world.free()


func test_when_ruth_is_down_the_next_best_leader_steadies_those_near_them() -> void:
	var g := _alone()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var walt = _person(sim, "Walt")
	var dez = _person(sim, "Dez")
	ruth.downed = true
	dez.x = walt.x + 4.0
	dez.y = walt.y
	near(_val(sim, dez, "Walt is leading"), 3.0, 0.001, "Walt, Leading 5: 3")
	g.world.free()


func test_the_dead_clawing_at_the_wall_weigh_on_those_within_ten_tiles() -> void:
	var g := _alone(22.0)
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	ruth.x = 39.0
	ruth.y = 20.0
	sim.traits.give(ruth, [])
	_clawing(sim, [1, 2, 3], 10)
	# (the reasons morale lists are rounded to a tenth of a point, hence the tolerances)
	var ten := maxf(Morale.DEAD_MAX, Morale.DEAD_EACH * 10.0)
	near(_val(sim, ruth, "The dead at the wall"), ten, 0.06, "ten of them: %s each" % -Morale.DEAD_EACH)
	# those not at the wall, and those far off, do not count
	for i in 5:
		sim.spawn(39.0 + float(i), 25.0, "approach")
	for i in 5:
		sim.spawn(39.0, 40.0 + float(i) * 0.1, "attack").slot = null
	near(_val(sim, ruth, "The dead at the wall"), ten, 0.06, "walkers on their way, or ten tiles off, add nothing")
	var more: Array = _clawing(sim, [0, 4, 5], 40)
	for z in more:
		z.x = 39.0
		z.y = 18.0
	var for_the_cap := ceili(Morale.DEAD_MAX / Morale.DEAD_EACH)
	check(10 + more.size() > for_the_cap, "enough walkers for the cap, and one to spare: %d of the %d it takes" % [10 + more.size(), for_the_cap])
	near(_val(sim, ruth, "The dead at the wall"), Morale.DEAD_MAX, 0.06, "at most %s" % -Morale.DEAD_MAX)
	var one = sim.zombies[0]
	one.state = "dying"
	near(_val(sim, ruth, "The dead at the wall"), Morale.DEAD_MAX, 0.06, "still the cap with one less")
	g.world.free()


func test_a_quiet_night_lifts_morale_by_two() -> void:
	var g := _alone(22.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	near(_val(sim, dez, "A quiet night"), 2.0, 0.001, "after the bell with no dead within 15 tiles: +2")
	near(sim.morale.target(dez), 67.0, 0.001, "65 and two")
	var z = sim.spawn(dez.x + 14.0, dez.y, "wander")
	check(not _has(sim, dez, "A quiet night"), "one of the dead within 15 tiles spoils it")
	z.x = dez.x + 16.0
	check(_has(sim, dez, "A quiet night"), "sixteen tiles off it does not")
	var h := _alone(9.0)
	check(not _has(h.sim, _person(h.sim, "Dez"), "A quiet night"), "and by day there is no such thing")
	g.world.free()
	h.world.free()


# ----------------------------------------------------------------------- drift --

func test_the_value_drifts_toward_the_target_at_the_drift_rate_an_hour() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var rate: float = Morale.DRIFT_PER_HOUR
	sim.morale.set_value(dez, 40.0)
	Helpers.run(sim, 20.0)   # one game hour
	near(sim.morale.value(dez), 40.0 + rate, 0.1, "up %s in an hour" % rate)
	Helpers.run(sim, 10.0)
	near(sim.morale.value(dez), 40.0 + rate * 1.5, 0.1, "and half as much again in half an hour more")
	sim.morale.set_value(dez, 100.0)
	var before: float = sim.morale.value(dez)
	Helpers.run(sim, 20.0)
	near(before - sim.morale.value(dez), rate, 0.15, "and down %s from above" % rate)
	g.world.free()


func test_the_value_stops_at_the_target() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	for p in sim.people:
		sim.order_move(p, p.x, p.y)   # everybody stands still: the target does not change
	var target: float = sim.morale.target(dez)
	near(target, 65.0, 0.001, "alone and fed")
	sim.morale.set_value(dez, 64.0)
	Helpers.run(sim, 20.0)
	near(sim.morale.value(dez), target, 1e-6, "from below it stops at the target, not past it")
	sim.morale.set_value(dez, 66.0)
	Helpers.run(sim, 20.0)
	near(sim.morale.value(dez), target, 1e-6, "and from above too")
	Helpers.run(sim, 20.0)
	near(sim.morale.value(dez), target, 1e-6, "and stays")
	g.world.free()


# ---------------------------------------------------------------------- shocks --

func test_a_shock_moves_the_value_at_once_and_is_listed() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	sim.morale.shock(dez, -12.0, "A bad moment")
	near(sim.morale.value(dez), 58.0, 0.0001, "70 less 12")
	var e = _line(sim, dez, "A bad moment")
	check(e != null, "it is listed")
	if e != null:
		near(float(e.value), -12.0, 0.05, "with its sign")
	near(sim.morale.value(_person(sim, "Ana")), 70.0, 0.0001, "and nobody else is touched")
	sim.morale.shock(dez, 3.0, "A good one")
	near(sim.morale.value(dez), 61.0, 0.0001, "a good shock raises it")
	g.world.free()


func test_a_shock_for_everyone_skips_the_dead_and_the_away() -> void:
	var g := _alone()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var walt = _person(sim, "Walt")
	ruth.dead = true
	walt.away = {"kind": "party"}
	sim.morale.shock(null, -10.0, "News")
	for p in sim.people:
		if p == ruth or p == walt:
			near(sim.morale.value(p), 70.0, 0.0001, "%s did not hear" % p.first)
		else:
			near(sim.morale.value(p), 60.0, 0.0001, "%s did" % p.first)
	g.world.free()


func test_a_shock_fades_out_of_the_list_as_the_value_comes_back() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	# a shock the size of five hours of drift: it fades by the drift rate, so it is gone in five
	var rate: float = Morale.DRIFT_PER_HOUR
	sim.morale.shock(dez, -5.0 * rate, "A bad moment")
	Helpers.run(sim, 20.0 * 2.0)   # two game hours
	var e = _line(sim, dez, "A bad moment")
	check(e != null, "still listed after two hours")
	if e != null:
		near(float(e.value), -3.0 * rate, 0.4, "two hours' worth of the five have gone: %.1f" % float(e.value))
	Helpers.run(sim, 20.0 * 4.0)
	check(_line(sim, dez, "A bad moment") == null, "gone after six hours")
	g.world.free()


func test_explain_is_biggest_first_with_signs() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	dez.hunger_h = Supplies.HUNGRY_H
	dez.bleeding = 2.0
	sim.morale.shock(dez, 2.0, "Small good")
	sim.morale.shock(dez, -15.0, "Big bad")
	var lines: Array = sim.morale.explain(dez)
	check(lines.size() >= 4, "four lines: %s" % str(lines))
	var last := INF
	for e in lines:
		check(e.has("label") and e.has("value"), "each has a label and a value")
		check(absf(float(e.value)) <= last + 0.0001, "%s is not bigger than the one before" % e.label)
		last = absf(float(e.value))
	eq(lines[0].label, "Big bad", "the biggest comes first")
	check(float(lines[0].value) < 0.0 and float(lines[lines.size() - 1].value) != 0.0, "signs are kept")
	g.world.free()


func test_a_kill_is_a_small_lift_but_only_up_to_a_cap_a_night() -> void:
	var g := _alone(22.0)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	# the kills that still count in a night, and what they add up to
	var counted := int(floorf(Morale.KILL_MAX / Morale.KILL + 1.0e-6))
	var cap: float = float(counted) * Morale.KILL
	sim.morale.set_value(marcus, 30.0)
	var z = sim.spawn(marcus.x + 8.0, marcus.y, "wander")
	sim._hurt_zombie(z, 1000.0, 0.0, marcus)
	near(sim.morale.value(marcus), 30.0 + Morale.KILL, 0.0001, "a kill: +%s" % Morale.KILL)
	check(_has(sim, marcus, "Put the dead down"), "it is listed")
	for i in counted + 20:
		var w = sim.spawn(marcus.x + 8.0, marcus.y, "wander")
		sim._hurt_zombie(w, 1000.0, 0.0, marcus)
	near(sim.morale.value(marcus), 30.0 + cap, 0.0001, "after %d kills: only +%s for the night" % [counted + 21, cap])
	sim.skills.on_bell()
	var more = sim.spawn(marcus.x + 8.0, marcus.y, "wander")
	sim._hurt_zombie(more, 1000.0, 0.0, marcus)
	near(sim.morale.value(marcus), 30.0 + cap + Morale.KILL, 0.0001, "the next night counts again")
	var ruth = _person(sim, "Ruth")
	near(sim.morale.value(ruth), 70.0, 0.0001, "and only the one who shot is lifted")
	g.world.free()


func test_a_breach_shakes_everyone() -> void:
	var g := _alone()
	var sim = g.sim
	sim._damage_segment(sim.segments[4], 1000.0)
	var shaken: float = Morale.START_VALUE + Morale.BREACH
	for p in sim.people:
		near(sim.morale.value(p), shaken, 0.0001, "%s: %s" % [p.first, Morale.BREACH])
		check(_has(sim, p, "The wall was breached"), "%s: listed" % p.first)
	sim._damage_segment(sim.segments[4], 1000.0)
	near(sim.morale.value(_person(sim, "Dez")), shaken, 0.0001, "a section that is already down is not a new breach")
	g.world.free()


func test_a_finished_repair_lifts_the_repairer() -> void:
	var g := _alone(9.0)
	var sim = g.sim
	sim.stock.scrap = 100.0
	var seg = sim.segments[4]
	sim._damage_segment(seg, 3.0)
	var dez = _person(sim, "Dez")
	var ruth = _person(sim, "Ruth")
	dez.x = seg.center.x
	dez.y = seg.center.y
	sim.morale.set_value(dez, 50.0)
	sim.order_repair(dez, seg)
	Helpers.run(sim, 2.0)
	check(seg.hp >= seg.max_hp, "the wall is whole")
	check(_has(sim, dez, "Finished a repair"), "Dez has the shock")
	check(sim.morale.value(dez) > 51.5, "+2 (and a little drift): %.2f" % sim.morale.value(dez))
	check(not _has(sim, ruth, "Finished a repair"), "and Ruth does not")
	# an order on a wall that needs nothing is not a repair
	var h := _alone(9.0)
	var s2 = h.sim
	var d2 = _person(s2, "Dez")
	d2.x = s2.segments[4].center.x
	d2.y = s2.segments[4].center.y
	s2.morale.set_value(d2, 50.0)
	s2.order_repair(d2, s2.segments[4])
	Helpers.run(s2, 2.0)
	check(not _has(s2, d2, "Finished a repair"), "a wall that was whole needs no thanks")
	g.world.free()
	h.world.free()


func test_a_friend_down_dead_turned_or_gone_shakes_those_who_knew_them() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var hector = _person(sim, "Hector")
	var ruth = _person(sim, "Ruth")
	hector.hp = 0.0
	sim.medical.on_downed(hector, "bite")
	var down: float = Morale.START_VALUE + Morale.FRIEND_DOWN
	near(sim.morale.value(dez), down, 0.001, "Dez, his friend, is down %s" % -Morale.FRIEND_DOWN)
	near(sim.morale.value(ruth), Morale.START_VALUE, 0.001, "Ruth is not")
	check(_has(sim, dez, "Hector is down"), "and it says why")
	sim.medical.kill(hector, "bled out")
	near(sim.morale.value(dez), down + Morale.FRIEND_LOST * sim.traits.mult(dez, "grief"), 0.001, "then he dies: %s more" % -Morale.FRIEND_LOST)
	near(sim.morale.value(ruth), Morale.START_VALUE + Morale.OTHER_LOST, 0.001, "and Ruth, who was not close, loses %s" % -Morale.OTHER_LOST)
	check(_has(sim, dez, "Hector died"), "the line says so")
	g.world.free()


# ------------------------------------------------------------------- the moods --

func test_the_mood_words_and_what_they_do_to_work() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	# value, word, work, aim: each word starts at its threshold and holds just under the next one
	var cases := [[100.0, "Inspired", 1.05, 1.05], [Morale.INSPIRED_AT, "Inspired", 1.05, 1.05], [Morale.INSPIRED_AT - 0.1, "Steady", 1.0, 1.0], [Morale.SHAKEN_BELOW, "Steady", 1.0, 1.0], [Morale.SHAKEN_BELOW - 0.1, "Shaken", 0.9, 0.9], [Morale.BREAKING_BELOW, "Shaken", 0.9, 0.9], [Morale.BREAKING_BELOW - 0.1, "Breaking", 0.75, 0.9], [Morale.BREAKDOWN_BELOW, "Breaking", 0.75, 0.9], [0.0, "Breaking", 0.75, 0.9]]
	for c in cases:
		sim.morale.set_value(dez, c[0])
		eq(sim.morale.mood(dez), c[1], "%.1f is %s" % [c[0], c[1]])
		near(sim.morale.perf(dez), c[2], 1e-9, "%.1f works at %.2f" % [c[0], c[2]])
		near(sim.morale.aim_mult(dez), c[3], 1e-9, "%.1f aims at %.2f" % [c[0], c[3]])
		near(sim.aim_factor(dez), c[3], 1e-9, "and the rules' aim says so")
	g.world.free()


func test_a_shaken_person_hits_less_often() -> void:
	var hits: Array = []
	for value in [Morale.START_VALUE, _shaken_value()]:
		var g := _alone(22.0, 5)
		var sim = g.sim
		sim.stock.ammo = 100000.0
		var ana = _person(sim, "Ana")
		sim.traits.give(ana, [])
		sim.morale.set_value(ana, value)
		var z = sim.spawn(ana.x + 4.0, ana.y, "wander")
		z.hp = 1.0e9
		for i in 6000:
			ana.mag = int(ana.gun.mag)
			ana.cooldown = 0.0
			sim._fire(ana, z, 0.0)
		hits.append(roundi((1.0e9 - z.hp) / float(ana.gun.dmg)))
		g.world.free()
	var ratio := float(hits[1]) / float(hits[0])
	# aim x0.9, and perf x0.9 on the skill term (0.75 + 0.35 x 0.4 x 0.9) / (0.75 + 0.35 x 0.4)
	check(ratio > 0.84 and ratio < 0.91, "a shaken shot hits about 12 percent less often: %d against %d (x%.3f)" % [hits[1], hits[0], ratio])


func test_morale_goes_into_the_rules_perf() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	near(sim.perf(dez), 1.0, 1e-9, "a steady, fed, whole person")
	sim.morale.set_value(dez, _shaken_value())
	near(sim.perf(dez), 0.9, 1e-9, "shaken: 0.9")
	dez.hunger_h = 20.0
	near(sim.perf(dez), 0.9 * 0.8, 1e-9, "and hungry too: they multiply")
	dez.hunger_h = 0.0
	sim.morale.set_value(dez, _inspired_value())
	near(sim.perf(dez), 1.05, 1e-9, "inspired: 1.05")
	g.world.free()


func test_a_shaken_person_mends_more_slowly() -> void:
	var mended: Array = []
	for value in [Morale.START_VALUE, _shaken_value()]:
		var g := _alone(9.0)
		var sim = g.sim
		sim.stock.scrap = 100.0
		var seg = sim.segments[4]
		sim._damage_segment(seg, 150.0)
		var hp0: float = seg.hp
		var hector = _person(sim, "Hector")
		hector.x = seg.center.x
		hector.y = seg.center.y
		sim.morale.set_value(hector, value)
		sim.order_repair(hector, seg)
		Helpers.run(sim, 3.0)
		mended.append(seg.hp - hp0)
		g.world.free()
	check(mended[0] > 20.0, "Hector mends something: %.1f" % mended[0])
	near(mended[1] / mended[0], 0.9, 0.03, "a shaken one mends a tenth less: %.1f against %.1f" % [mended[1], mended[0]])


func test_status_marks_show_while_shaken_breaking_or_broken() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	sim.morale.set_value(dez, _inspired_value())
	eq(sim.morale.status_of(dez), [], "inspired: no mark")
	sim.morale.set_value(dez, _steady_value())
	eq(sim.morale.status_of(dez), [], "steady: no mark")
	sim.morale.set_value(dez, _shaken_value())
	var marks: Array = sim.morale.status_of(dez)
	eq(marks.size(), 1, "shaken: one mark")
	if marks.size() == 1:
		eq(marks[0].icon, "mood", "the mood icon")
		check(String(marks[0].tip).begins_with("Shaken"), "its tip says Shaken: %s" % marks[0].tip)
		check(marks[0].has("color"), "and has a colour")
	sim.morale.set_value(dez, _breaking_value())
	marks = sim.morale.status_of(dez)
	check(marks.size() == 1 and String(marks[0].tip).begins_with("Breaking"), "breaking: Breaking")
	eq(sim.status_of(dez).filter(func(m): return m.icon == "mood").size(), 1, "and the rules' marks carry it")
	dez.dead = true
	eq(sim.morale.status_of(dez), [], "the dead have none")
	g.world.free()


func test_the_crews_mood_in_a_few_words() -> void:
	var g := _alone()
	var sim = g.sim
	near(sim.morale.crew_value(), 70.0, 0.0001, "the crew starts at 70")
	eq(sim.morale.crew_mood(), "Steady", "steady")
	var high := _inspired_value()
	for p in sim.people:
		sim.morale.set_value(p, high)
	eq(sim.morale.crew_mood(), "Inspired", "everyone high: inspired")
	sim.people[0].dead = true
	sim.morale.set_value(sim.people[0], 0.0)
	near(sim.morale.crew_value(), high, 0.0001, "the dead do not count")
	var low := _shaken_value()
	for p in sim.people:
		sim.morale.set_value(p, low)
	eq(sim.morale.crew_mood(), "Shaken", "everyone low: shaken")
	sim.morale.enabled = false
	eq(sim.morale.crew_mood(), "Steady", "and steady when it is off")
	g.world.free()


func test_explain_says_which_lines_are_recent_shocks() -> void:
	var g := _alone()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	sim.morale.shock(dez, -6.0, "A bad moment")
	for e in sim.morale.explain(dez):
		eq(e.recent, e.label == "A bad moment", "%s: recent only if it was a shock" % e.label)
	g.world.free()


# ------------------------------------------------------------------ breakdowns --

func _break(sim, p) -> void:
	sim.morale.set_value(p, 40.0)
	sim.morale.shock(p, -35.0, "Too much")


func test_under_the_breakdown_line_a_person_has_a_breakdown_for_an_hour_and_then_sits_at_thirty_five() -> void:
	var g := _alone(22.0)
	var sim = g.sim
	sim.day = 5
	var walt = _person(sim, "Walt")
	_break(sim, walt)
	check(sim.morale.breakdown(walt), "Walt is having a breakdown")
	var a: Dictionary = sim.alerts.get("breakdown-walt", {})
	check(not a.is_empty(), "an alert says so")
	eq(a.get("level"), "danger", "a red one")
	check(String(a.get("text", "")).contains("Walt"), "naming him: %s" % str(a.get("text")))
	var marks: Array = sim.morale.status_of(walt)
	check(marks.size() == 1 and String(marks[0].tip).begins_with("Having a breakdown"), "and the mark says it")
	Helpers.run(sim, 18.0)
	check(sim.morale.breakdown(walt), "still going after 54 minutes")
	Helpers.run(sim, 3.0)
	check(not sim.morale.breakdown(walt), "over after the hour")
	near(sim.morale.value(walt), 35.0, 1.0, "and he sits at 35: %.1f" % sim.morale.value(walt))
	check(not sim.alerts.has("breakdown-walt"), "the alert is taken down")
	g.world.free()


func test_in_a_breakdown_they_do_not_shoot_and_cannot_be_ordered() -> void:
	var shots: Array = []
	for broken in [false, true]:
		var g := _alone(22.0)
		var sim = g.sim
		sim.stock.ammo = 1000.0
		var walt = _person(sim, "Walt")
		walt.x = 65.2
		walt.y = 16.9
		var z = sim.spawn(walt.x - 6.0, walt.y, "wander")
		z.hp = 1.0e9
		z.speed = 0.0
		if broken:
			_break(sim, walt)
		Helpers.run(sim, 5.0)
		shots.append(int(walt.stats.shots))
		if broken:
			check(walt.target == null, "he has no target")
			check(not sim.order_move(walt, 64.0, 17.0), "an order to move is refused")
			sim.toggle_draft(walt)
			check(not walt.drafted, "so is a draft")
			sim.order_post(walt)
			check(walt.order == null, "and a post")
			sim.order_repair(walt, sim.segments[4])
			check(walt.repair == null, "and a repair")
			check(not sim.scavenge.can_go(walt), "and a trip")
		g.world.free()
	check(shots[0] > 0, "a steady Walt fires: %d" % shots[0])
	eq(shots[1], 0, "a broken one does not")


func test_a_broken_person_stops_what_they_were_doing() -> void:
	var g := _alone(9.0)
	var sim = g.sim
	sim.stock.scrap = 50.0
	var seg = sim.segments[4]
	sim._damage_segment(seg, 100.0)
	var dez = _person(sim, "Dez")
	sim.order_repair(dez, seg)
	check(dez.repair != null, "Dez has a repair order")
	_break(sim, dez)
	check(dez.repair == null and dez.order == null and not dez.drafted, "all his orders are gone")
	sim.stock.ammo = 100.0    # something to make
	Helpers.seat(sim, dez)    # at the bench, where his job is
	check(sim.jobs.job_of(dez) == "bench", "his job is still the bench")
	check(not sim.workshop.crafting(dez), "but he does not work it")
	eq(sim.workshop.why_not_craft(dez), "they cannot work right now", "and the bench says why")
	check(not sim.scavenge.can_go(dez), "or on a trip")
	var before := Vector2(dez.x, dez.y)
	Helpers.run(sim, 3.0)
	near(Vector2(dez.x, dez.y).distance_to(before), 0.0, 0.01, "and he stays where he is")
	check(not dez.moving, "not walking on the spot")
	g.world.free()


func test_a_broken_person_is_no_help_to_the_wounded() -> void:
	var g := _alone(9.0)
	var sim = g.sim
	sim.stock.meds = 10.0
	var ana = _person(sim, "Ana")
	var hector = _person(sim, "Hector")
	hector.x = ana.x + 0.4
	hector.y = ana.y
	_break(sim, ana)
	sim.medical.add_wound(hector, "scratch")
	Helpers.run(sim, 8.0)
	for j in sim.medical.jobs:
		check(j.healer != ana, "Ana is given no patient while she is broken")
	eq(ana.stats.treated, 0, "and treats nobody")
	g.world.free()


func test_no_breakdowns_on_story_or_before_day_four() -> void:
	var g := _alone(22.0, 7, 0)
	var sim = g.sim
	var walt = _person(sim, "Walt")
	_break(sim, walt)
	check(not sim.morale.breakdown(walt), "none on Story")
	eq(sim.morale.mood(walt), "Breaking", "a person on Story can still be Breaking")
	g.world.free()
	for day in [1, 2, 3]:
		var h := _alone(22.0)
		h.sim.day = day
		var w = _person(h.sim, "Walt")
		_break(h.sim, w)
		check(not h.sim.morale.breakdown(w), "none on day %d" % day)
		h.world.free()
	var k := _alone(22.0)
	k.sim.day = 4
	var w4 = _person(k.sim, "Walt")
	_break(k.sim, w4)
	check(k.sim.morale.breakdown(w4), "but on day 4 there can be")
	k.world.free()
	# a person who is low before day four is not broken the moment the day comes: the value is
	# checked every step, so they break as soon as it is day four
	var m := _alone(22.0)
	m.sim.day = 3
	var w3 = _person(m.sim, "Walt")
	_break(m.sim, w3)
	m.sim.day = 4
	Helpers.run(m.sim, 1.0)
	check(m.sim.morale.breakdown(w3), "someone still under the breakdown line when day four begins breaks")
	m.world.free()


func test_the_downed_and_the_away_do_not_break_down() -> void:
	var g := _alone(22.0)
	var sim = g.sim
	var walt = _person(sim, "Walt")
	var hector = _person(sim, "Hector")
	walt.downed = true
	hector.away = {"kind": "party"}
	sim.morale.set_value(walt, 5.0)
	sim.morale.set_value(hector, 5.0)
	Helpers.run(sim, 1.0)
	check(not sim.morale.breakdown(walt), "someone who is down has nothing to break")
	check(not sim.morale.breakdown(hector), "and nobody off the map")
	g.world.free()


# -------------------------------------------------------------- the neutral switch --

func test_switched_off_morale_has_no_effect_and_no_shocks() -> void:
	var g := _alone(22.0)
	var sim = g.sim
	sim.morale.enabled = false
	var dez = _person(sim, "Dez")
	sim.morale.shock(dez, -50.0, "A bad moment")
	sim.morale.shock(null, -50.0, "News")
	near(sim.morale.value(dez), 70.0, 0.0001, "no shocks")
	eq(sim.morale.mood(dez), "Steady", "always steady")
	near(sim.morale.perf(dez), 1.0, 1e-9, "works as usual")
	eq(sim.morale.explain(dez), [], "nothing to explain")
	eq(sim.morale.status_of(dez), [], "no marks")
	check(not sim.morale.breakdown(dez), "no breakdowns")
	near(sim.perf(dez), 1.0, 1e-9, "and the rules' perf is untouched")
	sim.morale.set_value(dez, 5.0)
	check(not sim.morale.breakdown(dez), "not even with a low number")
	eq(sim.morale.mood(dez), "Steady", "the word is still Steady")
	near(sim.morale.perf(dez), 1.0, 1e-9, "and the work")
	# the events that would shock do nothing
	sim._damage_segment(sim.segments[4], 1000.0)
	sim.medical.kill(_person(sim, "Hector"), "bled out")
	Helpers.run(sim, 5.0)
	for p in sim.people:
		eq(sim.morale.status_of(p), [], "%s: no marks after a night's news" % p.first)
		check(not sim.alerts.has("breakdown-%s" % p.id), "%s: no breakdown alert" % p.id)
	g.world.free()


func test_orientation_day_has_morale_and_the_storyteller_off() -> void:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	Orientation.begin(sim)
	check(not sim.morale.enabled, "morale is off in the tutorial")
	check(not sim.storyteller.enabled, "and so is the storyteller")
	var walt = _person(sim, "Walt")
	sim.morale.shock(null, -60.0, "Test")
	near(sim.morale.value(walt), 70.0, 0.0001, "so nothing shakes anyone")
	world.free()
	# a tutorial save loaded the way main.gd loads one (the scenario is installed first)
	var b := _bare()
	Orientation.install(b.sim)
	check(not b.sim.morale.enabled, "installing it is enough")
	b.world.free()


# ------------------------------------------------------------ numbers and saves --

func test_the_value_stays_between_zero_and_a_hundred_and_is_a_number() -> void:
	var g := _alone(22.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	sim.morale.shock(dez, 1.0e9, "Huge")
	check(sim.morale.value(dez) <= 100.0, "capped at 100: %f" % sim.morale.value(dez))
	sim.morale.shock(dez, -1.0e9, "Huge")
	check(sim.morale.value(dez) >= 0.0, "floored at 0: %f" % sim.morale.value(dez))
	var before: float = sim.morale.value(dez)
	sim.morale.shock(dez, NAN, "Not a number")
	sim.morale.shock(dez, INF, "Infinite")
	sim.morale.shock(dez, -INF, "Infinite")
	near(sim.morale.value(dez), before, 0.0, "a shock that is not a number does nothing")
	sim.morale.set_value(dez, NAN)
	check(is_finite(sim.morale.value(dez)), "nor can the value be set to one")
	sim.morale.set_value(dez, 500.0)
	near(sim.morale.value(dez), 100.0, 0.0, "set_value clamps")
	for e in sim.morale.explain(dez):
		check(is_finite(float(e.value)), "every line is a number: %s" % str(e))
	g.world.free()


func test_a_bad_stretch_keeps_every_value_in_range() -> void:
	# nothing to eat or drink, a night of the dead, shocks: for two days
	var g := Helpers.make(17, 1)
	var sim = g.sim
	sim.stock.food = 0.0
	sim.stock.water = 0.0
	sim.stock.ammo = 400.0
	var worst := 100.0
	var best := 0.0
	var bad := 0
	for second in 960:
		Helpers.run(sim, 1.0)
		for p in sim.people:
			var v: float = sim.morale.value(p)
			if not is_finite(v) or v < 0.0 or v > 100.0:
				bad += 1
			worst = minf(worst, v)
			best = maxf(best, v)
			for e in sim.morale.explain(p):
				if not is_finite(float(e.value)):
					bad += 1
			if not is_finite(sim.morale.perf(p)):
				bad += 1
	eq(bad, 0, "no value out of range or not a number in two days")
	check(worst < 40.0, "a bad stretch does shake people: the lowest was %.1f" % worst)
	g.world.free()


func test_the_same_seed_and_orders_give_the_same_morale() -> void:
	var runs: Array = []
	for i in 2:
		var g := Helpers.make(23, 1)
		var sim = g.sim
		sim.stock.ammo = 1000.0
		Helpers.run_to_hour(sim, 19.5)
		var seen: Array = []
		for step in 12:
			Helpers.run(sim, 10.0)
			var row: Array = []
			for p in sim.people:
				row.append(sim.morale.value(p))
			seen.append(row)
		runs.append(seen)
		g.world.free()
	eq(runs[0], runs[1], "the same morale at every sample")


func test_morale_is_saved_and_a_loaded_game_plays_on_the_same() -> void:
	var a := Helpers.make(29, 1)
	var sim = a.sim
	sim.stock.ammo = 1000.0
	Helpers.run_to_hour(sim, 21.0)
	Helpers.run(sim, 20.0)
	sim.morale.shock(_person(sim, "Dez"), -33.0, "A bad moment")
	sim.morale.shock(null, -4.0, "News")
	var d := SaveGame.to_dict(sim)
	check(d.modules.has("morale"), "the module has a place in the save")
	check(not d.modules.morale.is_empty(), "with something in it")
	var b := _bare()
	var c := _bare()
	check(SaveGame.apply(b.sim, d), "it applies")
	check(SaveGame.apply(c.sim, SaveGame.from_text(SaveGame.to_text(d))), "and from text")
	for p in sim.people:
		near(b.sim.morale.value(_person(b.sim, p.first)), sim.morale.value(p), 0.0, "%s: the value" % p.first)
		eq(b.sim.morale.explain(_person(b.sim, p.first)), sim.morale.explain(p), "%s: the reasons" % p.first)
	for second in 30:
		Helpers.run(sim, 1.0)
		Helpers.run(b.sim, 1.0)
		Helpers.run(c.sim, 1.0)
	for p in sim.people:
		near(b.sim.morale.value(_person(b.sim, p.first)), sim.morale.value(p), 1e-9, "%s: the same after 30 more seconds" % p.first)
		near(c.sim.morale.value(_person(c.sim, p.first)), sim.morale.value(p), 1e-6, "%s: and from text" % p.first)
	a.world.free()
	b.world.free()
	c.world.free()


func test_an_old_save_or_damaged_morale_data_loads_with_the_defaults() -> void:
	var a := Helpers.make(30, 1)
	var d := SaveGame.to_dict(a.sim)
	d.modules.erase("morale")
	var b := _bare()
	check(SaveGame.apply(b.sim, d), "a save from before morale loads")
	for p in b.sim.people:
		near(b.sim.morale.value(p), 70.0, 0.0001, "%s starts at 70" % p.first)
	var e := _bare()
	d.modules["morale"] = {"values": {"dez": "high", "ruth": NAN, "nobody": 5.0, "ana": 250.0}, "until": {"walt": "later"}, "shocks": {"dez": [5, {"label": 3}], "ruth": "x"}, "acc": -4.0}
	check(SaveGame.apply(e.sim, d), "damaged morale data does not refuse the save")
	for p in e.sim.people:
		var v: float = e.sim.morale.value(p)
		check(is_finite(v) and v >= 0.0 and v <= 100.0, "%s has a sound value: %f" % [p.first, v])
	near(e.sim.morale.value(_person(e.sim, "Ana")), 100.0, 0.0001, "a value over a hundred is cut to it")
	near(e.sim.morale.value(_person(e.sim, "Dez")), 70.0, 0.0001, "and one that is not a number is the start")
	check(not e.sim.morale.breakdown(_person(e.sim, "Walt")), "a breakdown end that is not a time is none")
	a.world.free()
	b.world.free()
	e.world.free()
