extends "res://tests/case.gd"
## Recruits (round 7): the small start, the calls at the radio hour, the arrivals at the gate, the beds as
## the cap, the generated survivors, the night's size following the crew, saves. The classic start (six
## people) is untouched: nothing here happens in it. The data of the generated survivors (names, roles,
## looks) is tested in test_recruit_data.gd.

const Helpers := preload("res://tests/helpers.gd")
const Recruits := preload("res://scripts/sim/recruits.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _person(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _ids(sim) -> Array:
	var out: Array = []
	for p in sim.people:
		out.append(String(p.id))
	return out


## A small start at noon of `day`, the storyteller on and the radio hour not yet held, Ruth at her desk.
func _small(day: int = 2, seed_value: int = 41) -> Dictionary:
	var g := Helpers.make(seed_value, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.storyteller.enabled = true
	sim.day = day
	sim.minutes = 11.9 * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (11.9 * 60.0 - 420.0)
	sim.phase = "day"
	sim.bell_rung = false
	sim.supplies.sources_day = day
	sim.supplies.meal_day = day
	sim.supplies.meals_done = 1
	sim.stock = {"ammo": 300.0, "scrap": 30.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	Helpers.seat(sim, _person(sim, "ruth"))
	sim.events.clear()
	return g


func _at_noon(sim) -> void:
	Helpers.run_to_hour(sim, 12.2)


# ----------------------------------------------------------------- the start --

func test_a_small_start_has_three_people_and_the_rest_wait_in_story_order() -> void:
	var g := Helpers.make(7, 1, 3)
	var sim = g.sim
	eq(_ids(sim), ["ruth", "dez", "marcus"], "Ruth, Dez and Marcus")
	check(sim.recruits.small, "it is a small start")
	var waiting: Array = []
	for def in sim.recruits.queue:
		waiting.append(String(def.id))
	eq(waiting, ["ana", "walt", "hector"], "the other three wait, in story order")
	eq(sim.jobs.job_of(_person(sim, "ruth")), "radio", "Ruth is at the radio desk")
	eq(sim.jobs.job_of(_person(sim, "dez")), "bench", "Dez at the bench")
	check(sim.jobs.crew_of("infirmary").is_empty() and sim.jobs.crew_of("garden").is_empty(), "nobody is in the infirmary or the beds: Ana and Hector are not here")
	near(sim.morale.value(_person(sim, "ruth")), 70.0, 1e-9, "the mood starts as it always did")
	g.world.free()


func test_a_classic_start_is_untouched() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	eq(sim.people.size(), 6, "six people")
	check(not sim.recruits.small and sim.recruits.queue.is_empty(), "no recruits")
	near(sim.recruits.crew_scale(), 1.0, 1e-12, "nights are the nights they were")
	check(not sim.recruits.call_due(), "and no call comes")
	g.world.free()


# ---------------------------------------------------------------------- calls --

func test_a_call_comes_at_noon_with_someone_at_the_desk_and_a_bed_free() -> void:
	var g := _small()
	var sim = g.sim
	_at_noon(sim)
	var up: Dictionary = sim.storyteller.pending()
	eq(up.id, "survivor_call", "the radio brings a call")
	check(String(up.title) == "A voice on the radio" and not String(up.text).contains("{"), "worded: '%s'" % up.text)
	eq(up.choices.size(), 2, "two answers")
	check(up.choices[0].enabled, "the way in can be told: there are beds")
	check(String(up.choices[0].hint).contains("Ana"), "and it says who: '%s'" % up.choices[0].hint)
	g.world.free()


func test_no_call_comes_on_day_one_or_without_someone_at_the_desk() -> void:
	var g := _small(1)
	var sim = g.sim
	_at_noon(sim)
	check(sim.storyteller.pending().is_empty(), "day one is quiet")
	g.world.free()
	var h := _small(2)
	var s2 = h.sim
	s2.jobs.unassign(_person(s2, "ruth"))
	_at_noon(s2)
	check(s2.storyteller.pending().is_empty(), "and with nobody at the desk the radio stays silent")
	h.world.free()


func test_telling_them_the_way_in_brings_them_to_the_gate_at_seven_next_morning() -> void:
	var g := _small()
	var sim = g.sim
	_at_noon(sim)
	check(sim.storyteller.choose(0), "the way in is told")
	eq(sim.recruits.incoming.size(), 1, "someone is on the way")
	eq(sim.people.size(), 3, "and is not here yet")
	Helpers.run_to_hour(sim, 6.0)
	eq(sim.people.size(), 3, "not by dawn")
	var guard := 0
	while sim.people.size() < 4 and guard < 600:
		Helpers.run(sim, 1.0)
		guard += 1
	eq(sim.people.size(), 4, "at seven he or she is here")
	var ana = _person(sim, "ana")
	check(ana != null, "it is Ana, the first of the callers")
	check(sim.hour >= 7.0 and sim.hour < 9.0 and sim.day == 3, "on day 3 at %.1f" % sim.hour)
	check(Vector2(ana.x, ana.y).distance_to(Recruits.GATE_SPOT) < 6.0, "near the gate: (%.1f, %.1f)" % [ana.x, ana.y])
	var told := false
	for e in sim.events:
		told = told or (e.type == "arrived" and e.who == "ana")
	check(told, "the view is told")
	check(sim.alerts.has("arrived-ana"), "with an alert")
	eq(sim.traits.of(ana).size(), 2, "she has her two traits")
	near(sim.morale.value(ana), 70.0 + Recruits.ARRIVAL_MORALE, 2.5, "and is welcome")
	eq(sim.recruits.arrived.size(), 1, "the arrival is kept for a save")
	g.world.free()


func test_not_yet_is_asked_again_two_days_later() -> void:
	var g := _small()
	var sim = g.sim
	_at_noon(sim)
	check(sim.storyteller.choose(1), "not yet")
	eq(sim.recruits.incoming.size(), 0, "nobody is coming")
	eq(sim.recruits.queue.size(), 3, "the caller is still waiting")
	sim.day = 3
	check(not sim.recruits.call_due(), "not the next day")
	sim.day = 4
	check(sim.recruits.call_due(), "two days on")
	g.world.free()


func test_the_beds_are_the_cap() -> void:
	var g := _small()
	var sim = g.sim
	eq(sim.recruits.housing_free(), 3, "six beds, three people")
	for i in 3:
		var def: Dictionary = sim.recruits.queue.pop_front() if not sim.recruits.queue.is_empty() else sim.recruits.make_def(i)
		sim.add_person(def)
	eq(sim.people.size(), 6, "six people")
	eq(sim.recruits.housing_free(), 0, "no bed left")
	sim.day = 9
	check(not sim.recruits.call_due(), "so no call comes")
	sim.build.plot("bunk_house_home_1").building = "bunk_house"
	sim.build.version += 1
	eq(sim.recruits.housing_free(), 4, "a bunk house gives four")
	check(sim.recruits.call_due(), "and the calls come again")
	g.world.free()


func test_the_way_in_is_refused_when_there_is_no_bed() -> void:
	var g := _small()
	var sim = g.sim
	_at_noon(sim)
	for i in 3:
		sim.add_person(sim.recruits.make_def(i + 10))
	var up: Dictionary = sim.storyteller.pending()
	check(not up.is_empty(), "the card is up")
	check(not up.choices[0].enabled and String(up.choices[0].why) == "No bed for them", "the way in says there is no bed: '%s'" % up.choices[0].why)
	check(not sim.storyteller.choose(0), "and cannot be chosen")
	g.world.free()


func test_a_mast_shortens_the_wait_between_calls() -> void:
	var g := _small()
	var sim = g.sim
	eq(sim.recruits.gap_days(), 3, "three days to begin with")
	sim.build.plot("radio_mast_home").building = "radio_mast"
	sim.build.version += 1
	eq(sim.recruits.gap_days(), 2, "two with a mast")
	g.world.free()


# ------------------------------------------------------------------ generating --

func test_generated_survivors_are_playable_and_the_same_for_the_same_run() -> void:
	var a := Helpers.make(55, 1, 3)
	var b := Helpers.make(55, 1, 3)
	var c := Helpers.make(56, 1, 3)
	var seen_ids := {}
	for i in 12:
		var da: Dictionary = a.sim.recruits.make_def(i)
		var db: Dictionary = b.sim.recruits.make_def(i)
		eq(da, db, "the same run makes the same survivor %d" % i)
		check(not seen_ids.has(da.id), "ids are unique: %s" % da.id)
		seen_ids[da.id] = true
		check(String(da.name).contains(" ") and String(da.role) != "", "%s has a name and a role" % da.id)
		check(a.sim.weapons.has(String(da.weapon)), "%s has a weapon that exists: %s" % [da.id, da.weapon])
		eq(da.traits.size(), 2, "%s: two traits" % da.id)
		check(da.traits[0] != da.traits[1], "that differ")
		for t in da.traits:
			check(a.sim.traits.order.has(String(t)), "%s is a real trait: %s" % [da.id, t])
		for k in Recruits.SKILLS:
			check(int(da.skills[k]) >= 0 and int(da.skills[k]) <= 10, "%s: %s is a skill: %d" % [da.id, k, da.skills[k]])
		for k in ["skin", "hair", "hairColor", "top", "topStyle", "outer", "outerStyle", "pants", "shoes"]:
			check(da.look.has(k), "%s's look has %s" % [da.id, k])
	var differs := false
	for i in 4:
		differs = differs or c.sim.recruits.make_def(i) != a.sim.recruits.make_def(i)
	check(differs, "another run makes other people")
	a.world.free()
	b.world.free()
	c.world.free()


func test_a_generated_survivor_joins_like_anyone() -> void:
	var g := _small()
	var sim = g.sim
	var def: Dictionary = sim.recruits.make_def(0)
	def["bitten"] = false
	var p = sim.add_person(def)
	check(sim.people.has(p), "they are in the crew")
	eq(sim.traits.of(p).size(), 2, "with their traits")
	near(sim.morale.value(p), 70.0, 1e-9, "and a mood")
	eq(sim.jobs.job_of(p), "", "no job yet")
	check(String(sim.jobs.post_of(p).get("id", "")) != "", "but a night post")
	Helpers.run(sim, 20.0)    # a game hour with the newcomer in it
	check(not p.dead, "and they live through it")
	g.world.free()


func test_after_the_authored_three_the_callers_are_generated_up_to_the_most() -> void:
	var g := _small()
	var sim = g.sim
	for i in 3:
		sim.recruits.queue.pop_front()
	var ids := {}
	for i in Recruits.MAX_GENERATED:
		var def: Dictionary = sim.recruits.current_caller()
		check(not def.is_empty(), "caller %d is made" % i)
		ids[def.id] = true
		sim.recruits.queue.pop_front()
	eq(ids.size(), Recruits.MAX_GENERATED, "all different")
	eq(sim.recruits.current_caller(), {}, "and then there are no more")
	check(not sim.recruits.call_due(), "so no call")
	g.world.free()


func test_a_bitten_arrival_is_bitten() -> void:
	var g := _small()
	var sim = g.sim
	var def: Dictionary = sim.recruits.make_def(0)
	def["bitten"] = true
	sim.recruits.incoming.append({"def": def, "day": sim.day})
	sim.minutes = 7.2 * 60.0
	Helpers.run(sim, 1.0)
	var p = _person(sim, String(def.id))
	check(p != null, "they have arrived")
	check(p.wounds >= 1 and p.bleeding > 0.0, "and are bleeding from a bite")
	g.world.free()


# ------------------------------------------------------------- the night's size --

func test_nights_follow_the_crew_in_a_small_start_only() -> void:
	var g := _small()
	var sim = g.sim
	near(sim.recruits.crew_scale(), 0.2 + 0.8 * 3.0 / 6.0, 1e-9, "three people: %.2f" % sim.recruits.crew_scale())
	var plan_three: float = sim.waves.night_budget(5)
	for i in 3:
		sim.add_person(sim.recruits.make_def(i))
	near(sim.recruits.crew_scale(), 1.0, 1e-9, "six people: a night as it was")
	near(sim.waves.night_budget(5), plan_three / 0.6, 1e-6, "the budget follows")
	for i in 20:
		sim.add_person(sim.recruits.make_def(i + 3))
	near(sim.recruits.crew_scale(), Recruits.SCALE_MAX, 1e-9, "and is capped")
	g.world.free()
	var c := Helpers.make(41, 1)
	near(c.sim.waves.night_budget(5), c.sim.waves.budget_for(5) * c.sim.storyteller.budget_mult(5), 1e-9, "a classic night is the budget as it was")
	c.world.free()


# ----------------------------------------------------------------------- saves --

func test_a_save_keeps_the_recruits_who_came_and_the_one_on_the_way() -> void:
	var a := _small()
	var sim_a = a.sim
	var def_a: Dictionary = sim_a.recruits.queue.pop_front()
	sim_a.add_person(def_a)
	sim_a.recruits.arrived.append(def_a)
	sim_a.recruits.next_call_day = 6
	sim_a.recruits.incoming.append({"def": sim_a.recruits.queue.pop_front(), "day": 4})
	var gen: Dictionary = sim_a.recruits.make_def(0)
	sim_a.recruits.queue.append(gen)
	sim_a.recruits.generated = 1
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := Helpers.make(99, 1)    # a classic roster: six people, none of them what was saved
	check(SaveGame.apply(b.sim, d), "the save loads")
	eq(_ids(b.sim), _ids(sim_a), "the same people, in the same order")
	check(b.sim.recruits.small, "still a small start")
	eq(b.sim.recruits.incoming.size(), 1, "the one on the way is still on the way")
	eq(String(b.sim.recruits.incoming[0].def.id), "walt", "it is Walt")
	eq(b.sim.recruits.next_call_day, 6, "the counters")
	eq(String(b.sim.recruits.queue[0].id), "hector", "the queue: Hector next")
	eq(String(b.sim.recruits.queue[1].id), String(gen.id), "and the generated caller after him")
	eq(b.sim.recruits.make_def(5), sim_a.recruits.make_def(5), "the generator goes on from where it was")
	Helpers.run(sim_a, 5.0)
	Helpers.run(b.sim, 5.0)
	for p in sim_a.people:
		var q = _person(b.sim, String(p.id))
		near(q.x, p.x, 1e-6, "%s is where they would have been (x)" % p.id)
	a.world.free()
	b.world.free()


func test_generated_callers_have_first_names_nobody_else_has_and_a_look_that_matches_their_portrait() -> void:
	for seed_value in [88, 89, 90, 91]:
		var g := Helpers.make(seed_value, 1, 3)
		var sim = g.sim
		var names := {}
		var portraits := {}
		for p in sim.people:
			names[String(p.first)] = true
		for def in sim.recruits.queue:
			names[String(def.name).split(" ")[0]] = true
		var data: Dictionary = Recruits._data()
		for i in Recruits.MAX_GENERATED:
			var def: Dictionary = sim.recruits.make_def(i)
			sim.recruits.queue.append(def)
			var first := String(def.name).split(" ")[0]
			check(not names.has(first), "seed %d, caller %d: '%s' is a first name nobody here or waiting has" % [seed_value, i, first])
			names[first] = true
			check(not portraits.has(String(def.portrait)), "seed %d, caller %d: a portrait not used yet" % [seed_value, i])
			portraits[String(def.portrait)] = true
			var idx := int(String(def.portrait).get_file().trim_prefix("gen_").trim_suffix(".png"))
			var want: Dictionary = data.portrait_looks[idx].look
			eq(def.look.skin, want.skin, "the pawn's skin is the portrait's")
			eq(def.look.hair, want.hair, "and its hair")
			eq(def.look.top, want.top, "and its clothes")
		g.world.free()


func test_a_recruit_has_a_night_post_from_the_moment_they_arrive_and_a_save_keeps_it() -> void:
	var a := _small()
	var sim_a = a.sim
	var p = sim_a.add_person(sim_a.recruits.queue.pop_front())
	check(sim_a.jobs.post_ids.has(String(p.id)), "the post is given at once, not at the first dusk")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := Helpers.make(99, 1)
	check(SaveGame.apply(b.sim, d), "the save loads")
	eq(String(b.sim.jobs.post_of(_person(b.sim, String(p.id))).id), String(sim_a.jobs.post_of(p).id), "and the recruit holds the same post after it")
	for q in sim_a.people:
		eq(String(b.sim.jobs.post_of(_person(b.sim, String(q.id))).id), String(sim_a.jobs.post_of(q).id), "%s's post is unchanged" % q.id)
	a.world.free()
	b.world.free()


func test_a_night_does_not_change_when_someone_dies_in_it() -> void:
	var g := Helpers.make(41, 1, 3)
	var sim = g.sim
	for i in 3:
		sim.add_person(sim.recruits.queue.pop_front())
	sim.storyteller.enabled = false
	sim.day = 6
	sim.minutes = 19.2 * 60.0
	sim.phase = "dusk"
	sim.bell_rung = true
	var before: Dictionary = sim.waves.plan_for(6)
	var queue_before: int = before.queue.size()
	var shown_before: int = before.shown
	_person(sim, "ana").dead = true
	sim.phase = "night"
	var after: Dictionary = sim.waves.plan_for(6)
	eq(after.queue.size(), queue_before, "the night's queue is the one the bell found")
	eq(after.shown, shown_before, "and so is the number the forecast gave")
	sim.day = 7
	sim.phase = "day"
	sim.bell_rung = false
	check(sim.waves.plan_for(7).budget < before.budget * 1.5, "the next day's plan follows the crew as it is then")
	g.world.free()


func test_a_damaged_recruit_in_a_save_is_refused_cleanly() -> void:
	var a := _small()
	var sim_a = a.sim
	var def: Dictionary = sim_a.recruits.make_def(0)    # a generated one: the roster does not have them
	sim_a.add_person(def)
	sim_a.recruits.arrived.append(def)
	for damage in ["weapon", "job", "look", "skills", "name"]:
		var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
		d.modules.recruits.arrived[0].erase(damage)
		var b := Helpers.make(99, 1)
		check(not SaveGame.apply(b.sim, d), "a recruit with no %s is refused" % damage)
		eq(b.sim.people.size(), 6, "and the six are as they were")
		b.world.free()
	a.world.free()


func test_no_call_comes_on_the_last_day() -> void:
	var g := _small()
	var sim = g.sim
	sim.day = sim.scenario.total_days()
	check(not sim.recruits.call_due(), "nobody could arrive in time")
	g.world.free()


func test_a_friend_who_arrives_lifts_the_one_they_know_more() -> void:
	var g := Helpers.make(41, 1, 3)
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	var marcus = _person(sim, "marcus")
	var walt_def: Dictionary = {}
	for def in sim.recruits.queue:
		if def.id == "walt":
			walt_def = def
	var ruth_before: float = sim.morale.value(ruth)
	var marcus_before: float = sim.morale.value(marcus)
	sim.recruits.incoming.append({"def": walt_def, "day": sim.day})
	sim.minutes = 7.2 * 60.0
	Helpers.run(sim, 1.0)
	check(_person(sim, "walt") != null, "Walt has arrived")
	var gain_marcus: float = sim.morale.value(marcus) - marcus_before
	var gain_ruth: float = sim.morale.value(ruth) - ruth_before
	check(gain_marcus > gain_ruth + 1.0, "Marcus, who is bonded to him, is lifted more: %.1f against %.1f" % [gain_marcus, gain_ruth])
	g.world.free()


func test_a_save_that_is_no_good_leaves_the_people_as_they_were() -> void:
	var a := _small()
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	d["day"] = -4    # damaged
	var b := Helpers.make(99, 1)
	var before := _ids(b.sim)
	check(not SaveGame.apply(b.sim, d), "it is refused")
	eq(_ids(b.sim), before, "and the six are as they were")
	a.world.free()
	b.world.free()


func test_a_classic_save_with_a_person_missing_is_still_refused() -> void:
	var a := Helpers.make(61, 1)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	d.people.pop_back()
	var b := Helpers.make(99, 1)
	check(not SaveGame.apply(b.sim, d), "a save of the classic start with one of the six gone is damaged")
	eq(b.sim.people.size(), 6, "and the six are as they were")
	a.world.free()
	b.world.free()


func test_a_classic_save_still_loads_and_plays_on() -> void:
	var a := Helpers.make(61, 1)
	Helpers.run(a.sim, 10.0)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	d.modules.erase("recruits")    # a save from before this round
	var b := Helpers.make(99, 1)
	check(SaveGame.apply(b.sim, d), "it loads")
	eq(b.sim.people.size(), 6, "six people")
	check(not b.sim.recruits.small, "and no recruits")
	a.world.free()
	b.world.free()


# ------------------------------------------------------ a start of four or five (the crew's size is a choice) --

func test_a_start_of_five_has_the_first_five_and_the_rest_wait_in_story_order() -> void:
	var g := Helpers.make(41, 1, 5)
	var sim = g.sim
	var ids := _ids(sim)
	ids.sort()
	eq(ids, ["ana", "dez", "marcus", "ruth", "walt"], "the first five of the story begin")
	check(sim.recruits.small, "it is a settlement start (the board, the lots, the calls)")
	check(not sim.recruits.queue.is_empty(), "someone is still to call in")
	eq(String(sim.recruits.queue[0].get("id", "")), "hector", "the next caller is Hector, then strangers")
	near(sim.recruits.crew_scale(), 0.2 + 0.8 * 5.0 / 6.0, 0.001, "the nights follow the crew: a little under the full night")
	check(sim.town.on, "the Town Board is on")
	g.world.free()


func test_a_start_of_four_has_four_and_a_start_of_six_is_the_classic_yard() -> void:
	var g := Helpers.make(41, 1, 4)
	var four := _ids(g.sim)
	four.sort()
	eq(four, ["ana", "dez", "marcus", "ruth"], "four: the three and Ana")
	eq(String(g.sim.recruits.queue[0].get("id", "")), "walt", "then Walt calls")
	g.world.free()
	var c := Helpers.make(41, 1, 6)
	eq(_ids(c.sim).size(), 6, "six: all of them")
	check(not c.sim.recruits.small, "and it is the classic start: no recruits, no board")
	c.world.free()
	var t := Helpers.make(41, 1, 3)
	eq(_ids(t.sim), ["ruth", "dez", "marcus"], "three is as it was")
	t.world.free()


func test_a_crew_of_five_fills_the_beds_after_one_caller() -> void:
	var g := Helpers.make(41, 1, 5)
	var sim = g.sim
	eq(int(sim.recruits.housing_free()) if sim.recruits.has_method("housing_free") else int(sim.build.housing()) - sim.recruits.crew_size(), 1, "the school's six beds: one is free for the next caller")
	g.world.free()
