extends "res://tests/case.gd"
## Orientation Day, the rules' side (scripts/sim/orientation.gd): how it starts, that it can
## never be lost, that the nights are the script's and happen when they should, that the
## lookout tells the truth about them, and that it is saved with the run.

const Kit := preload("res://tests/tutorial_kit.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")
const Scenario := preload("res://scripts/sim/scenario.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Sim := preload("res://scripts/sim/sim.gd")


# ------------------------------------------------------------------- start --

func test_orientation_day_starts_the_way_it_was_designed() -> void:
	var g := Kit.make()
	var sim = g.sim
	check(Orientation.is_orientation(sim.scenario), "the run's scenario is Orientation Day")
	eq(sim.difficulty, 0, "Story")
	eq(sim.run_seed, Orientation.SEED, "the fixed seed")
	eq(sim.day, 1, "day 1")
	near(sim.hour, 7.0, 0.001, "at 07:00")
	eq(sim.clock_min, 0.0, "the game clock at zero")
	eq(sim.over, "", "not over")
	check(not sim.permadeath, "nobody dies for good")
	check(not sim.waves.enabled, "the normal nights are off")
	var bus = sim.segments[Orientation.BUS_ID]
	near(bus.hp / bus.max_hp, Orientation.BUS_START, 0.001, "the school bus is worn to 45%")
	eq(bus.state, 1, "and looks it")
	for s in sim.segments:
		if s != bus:
			near(s.hp, s.max_hp, 0.001, "%s is whole" % s.name)
	near(float(sim.stock.ammo), Orientation.START_AMMO, 0.001, "a smaller store of ammo")
	eq(sim.people.size(), 6, "the whole crew")
	for p in sim.people:
		check(not p.dead and not p.downed and not p.drafted and p.away == null, "%s is well and free" % p.first)
	check(sim.tactics.auto_repair(Kit.person(sim, "walt")) and sim.jobs.job_of(Kit.person(sim, "dez")) == "bench", "the roster's jobs are there before the first step")
	Kit.run(sim, 0.1)
	for p in sim.people:
		check(not sim.tactics.auto_repair(p) and not sim.workshop.crafting(p), "%s is not on the wall crew or the bench after the first step" % p.first)
	check(sim.jobs.job_of(Kit.person(sim, "hector")) == "" and not sim.tactics.chores, "nor in the garden, and nobody mends a wall as a chore: nobody mends the wall unasked")
	eq(sim.jobs.job_of(Kit.person(sim, "marcus")), "watch", "but the lookout keeps his post: his forecast is a lesson")
	eq(sim.zombies.size(), 4, "a quiet yard: four of the dead wander far off")
	g.world.free()


func test_the_bus_stays_worn_until_someone_is_told_to_mend_it() -> void:
	var g := Kit.make()
	var sim = g.sim
	var bus = sim.segments[Orientation.BUS_ID]
	Kit.run(sim, 20.0)
	near(bus.hp / bus.max_hp, Orientation.BUS_START, 0.001, "twenty seconds on, still worn: nobody mended it unasked")
	for p in sim.people:
		check(p.repair == null, "%s has no repair job" % p.first)
	var dez = Kit.person(sim, "dez")
	sim.order_repair(dez, bus)
	Kit.run(sim, 40.0)
	check(bus.hp >= bus.max_hp - 0.001, "told to, Dez mends it (%.0f of %.0f)" % [bus.hp, bus.max_hp])
	g.world.free()


func test_the_chores_are_back_when_the_lesson_is_over() -> void:
	var g := Kit.make()
	var sim = g.sim
	Kit.run(sim, 0.1)
	check(not sim.tactics.chores, "nobody mends a wall as a chore while the lesson is on")
	sim.scenario.finish()
	Kit.run(sim, 0.1)
	check(sim.tactics.chores, "but they do when the lesson is over")
	g.world.free()


## A lesson started in the middle (--tutorial=N, a test) has the world the earlier lessons would have left: the
## self-working jobs are off before the rules take their first step, as they are after it. (The duty roster's
## lesson holds the game from its first frame, so the rules never step before the page opens.)
func test_a_jump_leaves_the_self_working_jobs_off_before_the_rules_ever_step() -> void:
	var g := Kit.make()
	var sim = g.sim
	eq(sim.jobs.job_of(Kit.person(sim, "walt")), "builders", "(Walt is on the wall crew to begin with)")
	sim.scenario.jump({"hour": 7.0, "day": 2, "bus": 1.0})
	for id in ["dez", "walt", "hector"]:
		eq(sim.jobs.job_of(Kit.person(sim, id)), "", "%s has no day job after the jump" % id)
	eq(sim.jobs.job_of(Kit.person(sim, "marcus")), "watch", "but the lookout keeps his post")
	check(sim.tactics.auto_jobs.is_empty(), "and nobody is sent to a wall by the crew")
	# the first step of the rules neither undoes nor repeats it: what the player gives is kept
	sim.jobs.assign(Kit.person(sim, "hector"), "garden")
	Kit.run(sim, 0.2)
	eq(sim.jobs.job_of(Kit.person(sim, "hector")), "garden", "a job given before the first step stays")
	g.world.free()


## Skipping the lesson before the rules ever stepped (the cards hold the game) and then playing on is a normal
## game: the crew has the jobs the roster gave it, and what the player changes is not undone by the first step.
func test_a_lesson_that_ends_before_the_rules_ever_stepped_leaves_the_crew_their_jobs() -> void:
	var g := Kit.make()
	var sim = g.sim
	sim.jobs.assign(Kit.person(sim, "hector"), "bench")
	sim.scenario.finish()
	Kit.run(sim, 0.2)
	eq(sim.jobs.job_of(Kit.person(sim, "walt")), "builders", "Walt is on the wall crew")
	eq(sim.jobs.job_of(Kit.person(sim, "dez")), "bench", "Dez is at the bench")
	eq(sim.jobs.job_of(Kit.person(sim, "hector")), "bench", "and Hector is where the player put him")
	g.world.free()


func test_the_run_arguments_know_the_tutorial() -> void:
	eq(Scenario.run_from_args(["--tutorial"]), {"tutorial": true, "step": 0}, "the flag alone starts at the first step")
	eq(Scenario.run_from_args(["--tutorial=5"]), {"tutorial": true, "step": 5}, "or at a step")
	eq(Scenario.run_from_args(["--shot=a.png", "--tutorial=2", "--hour=9"]), {"tutorial": true, "step": 2}, "among other flags")
	eq(Scenario.run_from_args(["--tutorial=x"]), {"tutorial": true, "step": 0}, "a step that is not a number is the first")
	eq(Scenario.run_from_args(["--tutorial=-4"]), {"tutorial": true, "step": 0}, "a negative one too")
	eq(Scenario.run_from_args(["--new=2", "--tutorial=1"]), {"tutorial": true, "step": 1}, "it wins over a new run")
	eq(Scenario.run_from_args(["--tutorial=1", "--load=user://q.json"]), {"load": "user://q.json"}, "and a save to load wins over it")


# ------------------------------------------------------------ never lost --

func test_it_cannot_be_lost_whatever_happens_to_the_crew_and_the_walls() -> void:
	var g := Kit.make()
	var sim = g.sim
	Kit.run(sim, 1.0)
	for p in sim.people:
		p.downed = true
		p.hp = 0.0
		p.stabilised = false
		p.bleed_out = -1.0
		p.infected_at = sim.clock_min - 11.0 * 60.0
		p.turn_at = sim.clock_min + 1.0
	for s in sim.segments:
		s.hp = 0.0
		sim._segment_state(s)
	check(sim.segments[0].state == 3, "a wall section is down to start with")
	# five game hours: long enough for everyone to bleed out and for every turn to come
	Kit.run(sim, 5.0 * 20.0)
	eq(sim.over, "", "still not over")
	for p in sim.people:
		check(not p.dead and not p.turned, "%s is neither dead nor turned" % p.first)
	for s in sim.segments:
		check(s.hp >= s.max_hp * Orientation.WALL_FLOOR - 0.001, "%s is not below the floor (%.0f of %.0f)" % [s.name, s.hp, s.max_hp])
		check(s.state != 3, "%s is not breached" % s.name)
	check(sim.stock.food >= 0.0, "and the stores are whole")
	g.world.free()


func test_nobody_dies_of_bleeding_and_a_bite_cannot_turn_anyone() -> void:
	var g := Kit.make()
	var sim = g.sim
	var ruth = Kit.person(sim, "ruth")
	var dez = Kit.person(sim, "dez")
	sim.medical.add_wound(ruth, "bite")
	ruth.hp = 1.0
	sim.medical.on_downed(ruth, "bite")
	# nobody to bandage her: Ana is away on a trip
	var ana = Kit.person(sim, "ana")
	ana.away = {"kind": "party", "n": 99}
	Kit.run(sim, 4.0 * 20.0)
	check(not ruth.dead, "Ruth is not dead after bleeding for four hours")
	check(ruth.stabilised, "she was stabilised instead")
	# an infection whose turn is near
	dez.infected_at = 1.0
	dez.turn_at = sim.clock_min + 5.0
	Kit.run(sim, 30.0)
	check(not dez.dead and not dez.turned, "an infection never turns him")
	check(dez.turn_at - sim.clock_min >= Orientation.TURN_MARGIN_MIN - 1.0, "its turn was put off (infected %.0f, turn %.0f, now %.0f)" % [dez.infected_at, dez.turn_at, sim.clock_min])
	g.world.free()


func test_a_trip_never_hurts_or_loses_anyone_and_always_brings_something() -> void:
	var g := Kit.make()
	var sim = g.sim
	var ana = Kit.person(sim, "ana")
	# the pharmacy is the dangerous place
	Kit.run(sim, 0.2)
	check(sim.scavenge.send([ana], "pharmacy"), "a trip goes")
	var party = sim.scavenge.parties[0]
	party.result = {"loot": {}, "hurt": {ana.id: "bite"}, "lost": [ana.id]}
	var meds_before: float = sim.stock.meds
	Kit.run_to_clock(sim, 9.2 * 60.0 + 10.0)
	check(not ana.dead and ana.away == null, "Ana is back and well (hour %.1f)" % sim.hour)
	check(ana.wounds == 0 and ana.bleeding == 0.0, "unhurt")
	var gained: float = sim.stock.food + sim.stock.water - 36.0 - 54.0
	check(gained > -10.0, "the stores are not worse for it")
	check(sim.stock.food > 30.0 and sim.stock.water > 40.0 or sim.stock.meds > meds_before, "and something came back")
	g.world.free()


func test_a_trip_that_was_to_find_nothing_finds_something() -> void:
	var g := Kit.make()
	var sim = g.sim
	var ana = Kit.person(sim, "ana")
	Kit.run(sim, 0.2)
	check(sim.scavenge.send([ana], "houses"), "a trip goes")
	sim.scavenge.parties[0].result = {"loot": {}, "hurt": {}, "lost": []}
	Kit.run(sim, 0.1)
	check(not sim.scavenge.parties[0].result.loot.is_empty(), "the empty result was filled in")
	g.world.free()


func test_a_send_out_is_called_off() -> void:
	var g := Kit.make()
	var sim = g.sim
	var hector = Kit.person(sim, "hector")
	sim.scenario.fire("fever")
	check(sim.handle_gizmo("sendout", {"kind": "person", "ref": hector}), "the order is taken")
	Kit.run(sim, 60.0)
	check(not hector.dead and hector.away == null, "he is still here")
	check(sim.medical.sendouts.is_empty(), "and nobody is walking to the gate")
	g.world.free()


func test_a_treatment_of_an_infection_always_takes() -> void:
	var g := Kit.make()
	var sim = g.sim
	# the module's chance with a healer of no skill is 45%: fifty tries, all cured
	var healer = Kit.person(sim, "marcus")
	for i in 50:
		var patient = Kit.person(sim, "hector")
		patient.infected_at = sim.clock_min - 8.0 * 60.0
		patient.turn_at = sim.clock_min + 50.0 * 60.0
		check(sim.medical.try_cure(healer, patient), "treatment %d took" % i)
		check(patient.infected_at < 0.0, "and the fever is gone")
	g.world.free()


func test_treating_the_fever_in_the_game_cures_it() -> void:
	var g := Kit.make()
	var sim = g.sim
	var hector = Kit.person(sim, "hector")
	sim.scenario.fire("fever")
	var meds_before: float = sim.stock.meds
	check(sim.handle_gizmo("treat", {"kind": "person", "ref": hector}), "Treat is taken")
	Kit.run(sim, 90.0)
	check(hector.infected_at < 0.0, "Hector is cured")
	check(sim.stock.meds <= meds_before - 2.0 + 0.001, "it cost two medicine")
	g.world.free()


# ------------------------------------------------------------- the script --

func test_with_no_coach_the_beats_come_on_the_game_clock() -> void:
	var g := Kit.make()
	var sim = g.sim
	var when := {}
	var beats: Array = Orientation.BEATS
	var guard := 0
	while sim.clock_min < 940.0 and guard < 100000:
		sim.update(1.0 / 30.0)
		guard += 1
		for b in beats:
			if not when.has(b.id) and sim.scenario.has_fired(b.id):
				when[b.id] = sim.clock_min
	for b in beats:
		check(when.has(b.id), "%s came" % b.id)
		if when.has(b.id):
			near(float(when[b.id]), float(b.at), 0.2, "%s came on time (game minute %.1f)" % [b.id, when[b.id]])
	eq(sim.over, "", "and the run is not over")
	g.world.free()


func test_the_dusk_beat_sends_three_walkers_for_the_gate() -> void:
	var g := Kit.make()
	var sim = g.sim
	var before: int = Kit.living_dead(sim)
	check(sim.scenario.fire("dusk"), "the beat fires")
	eq(Kit.living_dead(sim), before + 3, "three more of the dead")
	var gate = sim.segments[Orientation.DUSK_WALL]
	var heading := 0
	for z in sim.zombies:
		if z.slot != null and z.slot.seg == gate:
			heading += 1
	eq(heading, 3, "all three have a place at the main gate")
	check(sim.alerts.has("horde-a"), "and an alert says so")
	check(not sim.scenario.fire("dusk"), "a beat comes once")
	eq(Kit.living_dead(sim), before + 3, "nothing more came")
	g.world.free()


func test_the_second_group_is_four_and_the_wounds_are_walt_and_hector() -> void:
	var g := Kit.make()
	var sim = g.sim
	Kit.run_to_clock(sim, 700.0)
	var before: int = Kit.living_dead(sim)
	check(sim.scenario.fire("more"), "the second group")
	eq(Kit.living_dead(sim), before + 4, "four more of the dead")
	var walt = Kit.person(sim, "walt")
	var hector = Kit.person(sim, "hector")
	check(walt.bleeding == 0.0 and hector.infected_at < 0.0, "nobody hurt yet")
	check(sim.scenario.fire("scratch"), "the scratch")
	check(walt.bleeding > 0.0 and walt.wounds == 1, "Walt bleeds from one wound")
	check(sim.alerts.has("scratch-walt"), "with an alert")
	check(sim.scenario.fire("fever"), "the fever")
	check(hector.infected_at >= 0.0, "Hector is infected")
	Kit.run(sim, 1.0)
	eq(sim.medical.infection_stage(hector), "feverish", "and it shows")
	check(sim.alerts.has("fever-hector"), "the module says so")
	check(not sim.scenario.fire("nonsense"), "there is no such beat")
	g.world.free()


func test_a_coach_takes_the_beats_over_from_the_clock() -> void:
	var g := Kit.make()
	var sim = g.sim
	sim.scenario.coached = true
	Kit.run_to_clock(sim, 960.0)
	for b in Orientation.BEATS:
		check(not sim.scenario.has_fired(b.id), "%s waited for the coach" % b.id)
	var before: int = Kit.living_dead(sim)
	check(sim.scenario.fire("dusk"), "the coach fires one")
	eq(Kit.living_dead(sim), before + 3, "and it came")
	g.world.free()


func test_the_script_ends_when_the_lesson_does() -> void:
	var g := Kit.make()
	var sim = g.sim
	sim.scenario.coached = true
	sim.scenario.finish()
	check(sim.waves.enabled, "the real nights are on")
	check(not sim.waves.scripted, "and the forecast is the real one")
	check(not sim.scenario.coached and sim.scenario.finished, "the lesson is over")
	Kit.run_to_clock(sim, 960.0)
	for b in Orientation.BEATS:
		check(not sim.scenario.has_fired(b.id), "%s did not come: the script is over" % b.id)
	check(sim.waves.night_day == 1, "the real night of day 1 began at dusk")
	check(Kit.living_dead(sim) > 7, "and it brought more than the script did: %d" % Kit.living_dead(sim))
	eq(sim.over, "", "though it still cannot be lost")
	g.world.free()


# --------------------------------------------------------------- forecast --

func test_the_lookout_tells_the_truth_about_the_script() -> void:
	var g := Kit.make()
	var sim = g.sim
	check(not sim.tactics.forecast().get("given", false), "nothing is said in the morning")
	Kit.run_to_clock(sim, 10.0 * 60.0 + 20.0)
	var f: Dictionary = sim.tactics.forecast()
	check(f.get("given", false), "Marcus has spoken by 17:20")
	eq(int(f.total), Orientation.DUSK_AT.size() + Orientation.MORE_AT.size(), "about as many as the script brings")
	eq(f.heading, "north", "from the north")
	check(not f.big and int(f.brutes) == 0 and not f.runners, "no brutes, no runners, and not the last night")
	eq(sim.waves.plan_for(1).queue.size(), 7, "the plan is seven walkers")
	g.world.free()


# ------------------------------------------------------------------ jumping --

func test_jump_puts_the_world_the_way_a_lesson_expects() -> void:
	var g := Kit.make()
	var sim = g.sim
	sim.scenario.jump({"hour": 18.5, "bus": 1.0, "stock": {"scrap": 22}, "post": ["hector"], "drafted": ["ruth"], "fired": ["dusk"]})
	near(sim.hour, 18.5, 0.001, "the hour")
	eq(sim.phase, "day", "the phase")
	check(not sim.bell_rung, "the bell has not rung")
	near(sim.clock_min, 18.5 * 60.0 - 420.0, 0.001, "the game clock follows")
	near(sim.segments[Orientation.BUS_ID].hp, sim.segments[Orientation.BUS_ID].max_hp, 0.001, "the bus is mended")
	near(float(sim.stock.scrap), 22.0, 0.001, "the scrap")
	var hector = Kit.person(sim, "hector")
	check(hector.order != null and hector.order.z > 0.5, "Hector has a post order")
	near(hector.x, float(hector.def.post.x), 0.001, "and stands at it")
	check(Kit.person(sim, "ruth").drafted, "Ruth is drafted")
	check(sim.scenario.has_fired("dusk"), "the dusk beat has happened")
	sim.scenario.jump({"hour": 6.6, "day": 2})
	eq(sim.day, 2, "day 2")
	near(sim.clock_min, 1440.0 - 420.0 + 6.6 * 60.0, 0.001, "its clock")
	check(sim.bell_rung == false, "no bell by day")
	g.world.free()


# --------------------------------------------------------------- the save --

func test_it_is_saved_with_the_run_and_a_load_resumes_it() -> void:
	var g := Kit.make()
	var sim = g.sim
	var scenario = sim.scenario
	Kit.run(sim, 5.0)
	scenario.step = 6
	scenario.coached = true
	scenario.coach_state = {"t": 12.5, "pan": 3.25, "did": {"gizmo:draft": 1.0}, "events": {"shot": 4.0}, "base": {"ammo": 149.0, "pos": {"ruth": [60.5, 46.6]}}}
	scenario.fire("dusk")
	var data := SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	check(Orientation.is_save(data), "the save says it is Orientation Day")
	var g2 := Kit.make()
	var sim2 = g2.sim
	check(SaveGame.apply(sim2, data), "it loads")
	var loaded = sim2.scenario
	check(Orientation.is_orientation(loaded), "the scenario is still Orientation Day")
	eq(loaded.step, 6, "the step")
	check(loaded.coached and not loaded.finished and loaded.prepared, "the flags")
	check(loaded.has_fired("dusk") and not loaded.has_fired("more"), "the beats that happened")
	eq(loaded.coach_state, scenario.coach_state, "what the coach kept for its step")
	check(not sim2.waves.enabled, "the nights are still the script's")
	check(not sim2.permadeath, "and nobody dies")
	eq(Kit.living_dead(sim2), Kit.living_dead(sim), "the dead of the first group came with it")
	g.world.free()
	g2.world.free()


func test_a_normal_save_is_not_an_orientation_save() -> void:
	var Helpers := load("res://tests/helpers.gd")
	var h = Helpers.make(3, 1)
	var data := SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(h.sim)))
	check(not Orientation.is_save(data), "an ordinary run is not Orientation Day")
	check(not Orientation.is_save({}), "nor is nothing")
	check(not Orientation.is_orientation(h.sim.scenario), "the default scenario says so")
	h.world.free()
	# the other way: an Orientation save loaded where the scenario is the default one is let be
	var g := Kit.make()
	var odata := SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(g.sim)))
	var h2 = Helpers.make(3, 1)
	check(SaveGame.apply(h2.sim, odata), "an Orientation save still loads into a plain game")
	h2.world.free()
	g.world.free()


func test_it_plays_the_same_game_every_time() -> void:
	var prints: Array = []
	for i in 2:
		var g := Kit.make()
		var sim = g.sim
		Kit.run(sim, 2.0 * 20.0 * 12.0 + 1.0)
		prints.append(Kit.fingerprint(sim))
		g.world.free()
	eq(prints[1], prints[0], "two runs of the same day end the same")
