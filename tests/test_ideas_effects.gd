extends "res://tests/case.gd"
## The thirteen ideas the community brings (round 20, scripts/sim/initiative.gd, assets/data/ideas.json): for each, when it is on the
## table (both sides of each boundary of its trigger), who brings it (the specialist first), what it says and costs, and that a yes
## does its thing for real through the action the game already has (the order is given, the site goes up, the setting changes, the
## job is assigned, the posts are exchanged, the party is sent, the lesson is taught...), and what a later and a no cost. How the
## module as a whole works (the schedule, the caps, the gaps, the records, saves) is in test_initiative.gd. The relations and
## specialists modules are the fakes of tests/initiative_kit.gd.

const Kit := preload("res://tests/initiative_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _free(g: Dictionary) -> void:
	g.world.free()


func _who(sim, kind: String) -> String:
	return String(Kit.candidate(sim, kind).get("who", ""))


## Answers the idea of this kind that is on the table with `option` and returns what the call says came of it ("" when none was raised).
func _answer(sim, kind: String, option: String) -> String:
	var id: int = Kit.raise(sim, kind)
	if id == 0:
		return ""
	check(sim.radio.answer(id, option), "%s: the answer is taken" % kind)
	return String(sim.radio._entry(id).result)


## Puts a building on its plot at once.
func _stand(sim, plot_id: String, building_id: String) -> void:
	sim.build.plot(plot_id).building = building_id
	sim.build.version += 1


func _mood(sim, value: float) -> void:
	for p in sim.people:
		sim.morale.set_value(p, value)


# ----------------------------------------------------------------------- fix_wall --

func test_fix_wall_is_on_the_table_for_a_worn_wall_that_nobody_is_on() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Kit.wear(sim, 5, 0.91)
	eq(_who(sim, "fix_wall"), "", "a wall at 91% is not worth it")
	Kit.wear(sim, 5, 0.89)
	eq(_who(sim, "fix_wall"), "dez", "at 89% Dez brings it (the best Building at the base)")
	Kit.at(sim, 3, 16.0)
	eq(_who(sim, "fix_wall"), "dez", "at 16:00, three hours before dusk, still")
	Kit.at(sim, 3, 16.2)
	eq(_who(sim, "fix_wall"), "", "not later")
	Kit.at(sim, 3, 9.0)
	Kit.wear(sim, 14, 0.5)
	Kit.wear(sim, 5, 1.0)
	eq(_who(sim, "fix_wall"), "", "a door is not mended this way")
	Kit.wear(sim, 14, 1.0)
	Kit.wear(sim, 5, 0.8)
	sim.order_repair(Kit.who(sim, "marcus"), sim.segments[5])
	eq(_who(sim, "fix_wall"), "", "somebody is on it already")
	_free(g)


func test_fix_wall_waits_for_the_scrap_and_leaves_the_walls_the_crew_will_mend() -> void:
	var g := Kit.game(5)
	var sim = g.sim
	Kit.wear(sim, 5, 0.8)    # (84 points: 9 scrap)
	sim.stock.scrap = 8.9
	eq(_who(sim, "fix_wall"), "", "8.9 scrap is not enough for the 9 it will cost")
	sim.stock.scrap = 9.0
	eq(_who(sim, "fix_wall"), "dez", "9 is")
	sim.jobs.assign(Kit.who(sim, "walt"), "builders")
	eq(_who(sim, "fix_wall"), "dez", "with a crew on the Builders: a wall over their line (70%) is still the idea's")
	Kit.wear(sim, 5, 0.6)
	sim.stock.scrap = 60.0
	eq(_who(sim, "fix_wall"), "", "a wall under their line: they will see to it")
	sim.jobs.unassign(Kit.who(sim, "walt"))
	eq(_who(sim, "fix_wall"), "dez", "and with nobody on the Builders, it is the idea's again")
	_free(g)


func test_fix_wall_says_what_it_costs() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Kit.wear(sim, 5, 0.8)
	var c := Kit.candidate(sim, "fix_wall")
	eq(c.text, "Dez: I could fix the blue container on the north wall properly. About 9 scrap.", "the words")
	eq(c.yes_label, "Yes: fix the blue container (9 scrap)", "the button")
	eq(c.cost, {"scrap": 9}, "the price")
	eq(c.others, [], "nobody else is in it")
	_free(g)


func test_a_yes_to_fix_wall_mends_the_wall_to_full_and_pays_for_it() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Helpers.idle_stores(sim)
	Kit.wear(sim, 5, 0.8)
	var seg = sim.segments[5]
	var missing: float = seg.max_hp - seg.hp
	var scrap: float = sim.stock.scrap
	var result := _answer(sim, "fix_wall", "yes")
	check(result.contains("Dez") and result.contains("blue container"), "the result: %s" % result)
	check(Kit.who(sim, "dez").repair == seg, "Dez has the order to repair it")
	Helpers.run(sim, 40.0)
	near(seg.hp, seg.max_hp, 0.001, "the wall is whole")
	near(scrap - sim.stock.scrap, missing / 10.0, 0.05, "and the scrap went as he worked")
	_free(g)


func test_the_mender_of_a_wall_idea_is_released_when_the_scrap_runs_out() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Helpers.idle_stores(sim)
	Kit.wear(sim, 5, 0.8)
	var seg = sim.segments[5]
	_answer(sim, "fix_wall", "yes")
	var dez = Kit.who(sim, "dez")
	check(dez.repair == seg, "Dez has the order to repair it")
	Helpers.run(sim, 3.0)
	check(dez.repair == seg and seg.hp < seg.max_hp, "he is at it (the wall is not whole yet)")
	sim.stock.scrap = 0.0
	Helpers.run(sim, 3.0)
	check(dez.repair == null, "the scrap is gone: he is let go, he does not stand at the wall")
	check(seg.hp < seg.max_hp, "(the wall is not whole)")
	_free(g)


func test_the_mender_of_a_wall_idea_goes_back_to_his_post_at_dusk() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Helpers.idle_stores(sim)
	Kit.wear(sim, 5, 0.8)
	_answer(sim, "fix_wall", "yes")
	var dez = Kit.who(sim, "dez")
	check(dez.repair != null, "he is on the wall")
	Kit.at(sim, 3, 19.6)
	Helpers.run(sim, 3.0)
	check(dez.repair == null, "at night the crew is at its posts: the order is over")
	_free(g)


func test_a_no_to_fix_wall_leaves_the_wall_alone() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Kit.wear(sim, 5, 0.8)
	var scrap: float = sim.stock.scrap
	_answer(sim, "fix_wall", "no")
	check(Kit.who(sim, "dez").repair == null, "nobody goes")
	near(sim.stock.scrap, scrap, 1e-9, "nothing is spent")
	_free(g)


# ------------------------------------------------------------------------- build --

## A game in which the crew is six (so there is no bed for the next caller), at 09:00.
func _full_house() -> Dictionary:
	var g := Kit.game(4)
	var sim = g.sim
	sim.add_person(sim.recruits.queue.pop_front())
	sim.add_person(sim.recruits.queue.pop_front())
	return g


func test_build_beds_for_a_caller_who_cannot_come() -> void:
	var g := _full_house()
	var sim = g.sim
	eq(sim.recruits.housing_free(), 0, "(the beds are all taken)")
	var c := Kit.candidate(sim, "build")
	check(not c.is_empty(), "somebody brings a building")
	eq(c.args.building, "tents", "tents first: they are cheap")
	eq(c.cost, {"scrap": int(sim.build.building("tents").scrap)}, "for what they cost")
	check(String(c.text).contains("Some tents would help") and String(c.text).contains("bed"), "in words: %s" % c.text)
	eq(c.who, "dez", "the best Building (nobody is the engineer)")
	g.spec.holders["engineer"] = "marcus"
	eq(_who(sim, "build"), "marcus", "the engineer brings it, if there is one")
	g.spec.holders.erase("engineer")
	g.rel.voice_id = "ana"
	eq(_who(sim, "build"), "ana", "else the voice")
	sim.stock.scrap = float(sim.build.building("tents").scrap) - 0.5
	eq(_who(sim, "build"), "", "and not when the scrap will not cover it")
	_free(g)


func test_build_has_a_need_for_each_thing() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	eq(Kit.candidate(sim, "build"), {}, "(nothing is wanted in a good morning)")
	# the food runs short: the greenhouse
	sim.stock.food = 15.9    # (under four days for four people)
	var c := Kit.candidate(sim, "build")
	eq(c.args.building, "greenhouse", "food under four days: a greenhouse")
	check(String(c.text).contains("A greenhouse would help") and String(c.text).contains("food"), "in words: %s" % c.text)
	sim.stock.food = 16.0
	eq(Kit.candidate(sim, "build"), {}, "at four days: no")
	sim.stock.ammo = 89.0
	eq(Kit.candidate(sim, "build").args.building, "workshop", "ammo under 90: a workshop")
	sim.stock.ammo = 90.0
	eq(Kit.candidate(sim, "build"), {}, "at 90: no")
	sim.stock.scrap = 39.0
	eq(Kit.candidate(sim, "build").args.building, "salvage_bench", "scrap running low: a salvage bench")
	sim.stock.scrap = 60.0
	_mood(sim, 54.0)
	eq(Kit.candidate(sim, "build").args.building, "bunk_house", "a crew under 55: a bunk house")
	_mood(sim, 55.0)
	eq(Kit.candidate(sim, "build"), {}, "at 55: no")
	_free(g)


func test_build_takes_the_needs_in_order_and_waits_for_a_free_site() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.stock.food = 10.0
	sim.stock.ammo = 50.0
	eq(Kit.candidate(sim, "build").args.building, "greenhouse", "food before ammo")
	check(sim.build.order(sim.build.home_for("greenhouse"), "greenhouse"), "(the greenhouse is ordered)")
	var c := Kit.candidate(sim, "build")
	eq(Kit.candidate(sim, "build"), {}, "with a site going up, there is no new one: %s" % str(c))
	_free(g)


func test_a_yes_to_build_pays_and_puts_a_site_up() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.stock.ammo = 50.0
	var scrap: float = sim.stock.scrap
	var cost := float(sim.build.building("workshop").scrap)
	var result := _answer(sim, "build", "yes")
	check(result.contains("workshop"), "the result: %s" % result)
	near(sim.stock.scrap, scrap - cost, 1e-9, "the scrap is paid")
	check(not sim.build.active_site().is_empty(), "a site is up")
	eq(String(sim.build.active_site().site.building), "workshop", "for the workshop")
	_free(g)


func test_a_yes_to_build_is_checked_again() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.stock.ammo = 50.0
	var id: int = Kit.raise(sim, "build")
	sim.stock.scrap = 3.0
	sim.radio.answer(id, "yes")
	var result := String(sim.radio._entry(id).result)
	check(result.begins_with("Not now: it needs"), "the building's own words: %s" % result)
	check(sim.build.active_site().is_empty(), "nothing goes up")
	_free(g)


# ------------------------------------------------------------------ bench_target --

func test_bench_target_when_the_ammo_is_at_the_line() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.stock.ammo = 290.0
	var c := Kit.candidate(sim, "bench_target")
	eq(c.who, "dez", "Dez (the bench crew's best Building)")
	eq(c.text, "Dez: The bench stops at 300. Let me run it to 400.", "the words")
	eq(c.cost, {}, "it costs nothing now")
	sim.stock.ammo = 289.0
	eq(_who(sim, "bench_target"), "", "ammo more than ten under the line: not yet")
	sim.stock.ammo = 350.0
	eq(_who(sim, "bench_target"), "dez", "over the line is as good (the bench has stopped)")
	sim.stock.ammo = 400.0
	eq(_who(sim, "bench_target"), "", "at 400 ammo there is enough")
	g.spec.holders["engineer"] = "marcus"
	sim.stock.ammo = 300.0
	eq(_who(sim, "bench_target"), "marcus", "the engineer, if there is one, brings it (though he is not on the bench)")
	_free(g)


func test_bench_target_needs_a_crew_a_low_line_and_scrap_to_spare() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.stock.ammo = 300.0
	sim.stock.scrap = 22.9
	eq(_who(sim, "bench_target"), "", "scrap under the reserve and twenty")
	sim.stock.scrap = 23.0
	eq(_who(sim, "bench_target"), "dez", "at the reserve (3) and 20")
	sim.jobs.set_setting("bench", "ammo_target", 600)
	sim.stock.ammo = 600.0
	eq(_who(sim, "bench_target"), "", "a line of 600 is high enough")
	sim.jobs.set_setting("bench", "ammo_target", 575)
	sim.stock.ammo = 575.0
	eq(_who(sim, "bench_target"), "", "(and ammo at 575 is over the 400 of the rule)")
	sim.jobs.set_setting("bench", "ammo_target", 300)
	sim.stock.ammo = 300.0
	sim.jobs.unassign(Kit.who(sim, "dez"))
	eq(_who(sim, "bench_target"), "", "with nobody on the bench there is nobody to ask")
	_free(g)


func test_a_yes_to_bench_target_raises_the_line() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	var scrap: float = sim.stock.scrap
	var result := _answer(sim, "bench_target", "yes")
	check(result.contains("400"), "the result: %s" % result)
	eq(int(sim.jobs.setting("bench", "ammo_target")), 400, "the bench's line is 400")
	eq(int(sim.workshop.target()), 400, "and the workshop reads it")
	near(sim.stock.scrap, scrap, 1e-9, "no scrap is spent")
	_free(g)


func test_a_later_or_a_no_to_bench_target_leaves_the_line() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	_answer(sim, "bench_target", "later")
	eq(int(sim.jobs.setting("bench", "ammo_target")), 300, "later leaves it")
	_free(g)


# --------------------------------------------------------------------- wall_line --

func _builders_game() -> Dictionary:
	var g := Kit.game(5)
	var sim = g.sim
	sim.jobs.assign(Kit.who(sim, "walt"), "builders")
	return g


func test_wall_line_for_a_wall_just_over_the_crews_line() -> void:
	var g := _builders_game()
	var sim = g.sim
	Kit.wear(sim, 5, 0.75)
	var c := Kit.candidate(sim, "wall_line")
	eq(c.who, "walt", "a Builders crew member brings it")
	eq(c.text, "Walt: The crew leaves walls at 70%. Mend them at 80.", "the words")
	eq(c.cost, {}, "no price")
	Kit.wear(sim, 5, 0.65)
	eq(_who(sim, "wall_line"), "", "a wall under the line: the crew mends it already")
	Kit.wear(sim, 5, 0.82)
	eq(_who(sim, "wall_line"), "", "a wall a line of 80 would not reach")
	Kit.wear(sim, 5, 0.75)
	sim.stock.scrap = 24.9
	eq(_who(sim, "wall_line"), "", "scrap under 25")
	sim.stock.scrap = 25.0
	eq(_who(sim, "wall_line"), "walt", "at 25")
	sim.jobs.set_setting("builders", "repair_below", 85)
	eq(_who(sim, "wall_line"), "", "a line of 85 or more is high enough")
	sim.jobs.set_setting("builders", "repair_below", 70)
	sim.jobs.unassign(Kit.who(sim, "walt"))
	eq(_who(sim, "wall_line"), "", "with nobody on the Builders there is nobody to ask")
	_free(g)


func test_a_yes_to_wall_line_sends_the_crew_to_the_wall() -> void:
	var g := _builders_game()
	var sim = g.sim
	var walt = Kit.who(sim, "walt")
	Kit.wear(sim, 5, 0.75)
	Helpers.run(sim, 3.0)
	check(walt.repair == null, "(at the old line the crew leaves the wall at 75%)")
	var result := _answer(sim, "wall_line", "yes")
	check(result.contains("80"), "the result: %s" % result)
	eq(int(sim.jobs.setting("builders", "repair_below")), 80, "the line is 80")
	Helpers.run(sim, 3.0)
	check(walt.repair != null and int(walt.repair.id) == 5, "and the crew goes to the wall")
	_free(g)


# -------------------------------------------------------------------------- desk --

func test_desk_the_radio_with_nobody_at_it_in_the_morning() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	eq(_who(sim, "desk"), "", "(the desk is staffed)")
	sim.jobs.unassign(Kit.who(sim, "marcus"))
	var c := Kit.candidate(sim, "desk")
	eq(c.who, "marcus", "the only one with no job")
	eq(c.text, "Marcus: Nobody is at the radio. I can sit with it.", "the words")
	Kit.at(sim, 3, 7.9)
	eq(_who(sim, "desk"), "", "before 08:00 no")
	Kit.at(sim, 3, 8.0)
	eq(_who(sim, "desk"), "marcus", "from 08:00")
	Kit.at(sim, 3, 10.9)
	eq(_who(sim, "desk"), "marcus", "to 11:00")
	Kit.at(sim, 3, 11.1)
	eq(_who(sim, "desk"), "", "not after")
	_free(g)


func test_desk_goes_to_the_best_fit_who_is_free_for_it() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.jobs.unassign(Kit.who(sim, "marcus"))
	sim.jobs.assign(Kit.who(sim, "dez"), "garden")
	eq(_who(sim, "desk"), "dez", "a hand at the garden is free for it, and leads better than Marcus")
	sim.jobs.assign(Kit.who(sim, "dez"), "bench")
	eq(_who(sim, "desk"), "marcus", "one on the bench is not")
	_free(g)


func test_desk_the_lookout_in_the_afternoon_and_the_infirmary_with_a_patient() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.jobs.unassign(Kit.who(sim, "dez"))
	Kit.at(sim, 3, 13.9)
	eq(_who(sim, "desk"), "", "the lookout is empty but it is not 14:00")
	Kit.at(sim, 3, 14.0)
	var c := Kit.candidate(sim, "desk")
	eq(c.text, "Dez: Nobody is on watch. I can take the lookout post.", "from 14:00 the lookout")
	Kit.at(sim, 3, 16.1)
	eq(_who(sim, "desk"), "", "to 16:00")
	Kit.at(sim, 3, 9.0)
	sim.jobs.unassign(Kit.who(sim, "ana"))
	eq(_who(sim, "desk"), "", "an empty infirmary with nobody in it is not a call")
	Kit.who(sim, "marcus").resting_bed = Vector2(48.0, 54.0)
	c = Kit.candidate(sim, "desk")
	eq(c.who, "ana", "with someone in a bed, the best at medicine")
	eq(c.text, "Ana: Nobody is at the infirmary and someone is in a bed. I can sit with them.", "the words")
	_free(g)


func test_a_yes_to_desk_gives_the_seat_and_is_checked_again() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	var marcus = Kit.who(sim, "marcus")
	sim.jobs.unassign(marcus)
	var result := _answer(sim, "desk", "yes")
	check(result.contains("Marcus"), "the result: %s" % result)
	eq(sim.jobs.job_of(marcus), "radio", "Marcus sits at the radio")
	# a seat that is taken meanwhile
	sim.jobs.unassign(marcus)
	sim.initiative.last_kind.clear()
	sim.initiative.records.clear()
	var id: int = Kit.raise(sim, "desk")
	check(id > 0, "(again)")
	sim.jobs.assign(Kit.who(sim, "dez"), "radio")
	sim.radio.answer(id, "yes")
	check(String(sim.radio._entry(id).result).begins_with("Not now"), "a desk with somebody at it: %s" % sim.radio._entry(id).result)
	eq(sim.jobs.job_of(marcus), "", "Marcus is not sent there")
	_free(g)


func test_the_medic_and_the_marksman_bring_their_own_desks_first() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.jobs.unassign(Kit.who(sim, "ana"))
	sim.jobs.unassign(Kit.who(sim, "dez"))
	Kit.who(sim, "marcus").resting_bed = Vector2(48.0, 54.0)
	var plain := Kit.candidate(sim, "desk")
	eq(plain.who, "ana", "(the best at medicine)")
	g.spec.holders["medic"] = "ana"
	check(float(Kit.candidate(sim, "desk").score) > float(plain.score), "the medic's own desk is worth more")
	_free(g)


# ------------------------------------------------------------------------ garden --

func _garden_game() -> Dictionary:
	var g := Kit.game(4)
	var sim = g.sim
	sim.jobs.assign(Kit.who(sim, "dez"), "garden")
	sim.jobs.unassign(Kit.who(sim, "marcus"))
	sim.stock.food = 19.0    # (4.75 days for four)
	return g


func test_garden_when_the_food_is_short_and_somebody_is_free() -> void:
	var g := _garden_game()
	var sim = g.sim
	var c := Kit.candidate(sim, "garden")
	eq(c.who, "dez", "the gardener")
	eq(c.others, ["marcus"], "with the one who has no job")
	eq(c.text, "Dez: The garden could feed two more if Marcus gave a hand.", "the words")
	eq(c.cost, {}, "no price")
	sim.stock.food = 20.0
	eq(_who(sim, "garden"), "", "five days of food is enough")
	sim.stock.food = 19.0
	sim.jobs.assign(Kit.who(sim, "ana"), "garden")
	eq(_who(sim, "garden"), "", "the beds are full")
	sim.jobs.assign(Kit.who(sim, "ana"), "infirmary")
	sim.jobs.assign(Kit.who(sim, "marcus"), "watch")
	eq(_who(sim, "garden"), "", "nobody is free to go")
	_free(g)


func test_garden_a_farmer_brings_it_when_nobody_tends_it() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	sim.jobs.unassign(Kit.who(sim, "marcus"))
	sim.stock.food = 19.0
	eq(_who(sim, "garden"), "", "(no gardener and no farmer)")
	var def: Dictionary = sim.recruits.make_def(0)
	def["role"] = "Farmer"
	def["station"] = ""
	var farmer = sim.add_person(def)
	var c := Kit.candidate(sim, "garden")
	eq(c.who, String(farmer.id), "a Farmer brings it")
	eq(c.others, ["marcus"], "with the one who is not the farmer")
	_free(g)


func test_a_yes_to_garden_sends_the_hand_to_the_beds() -> void:
	var g := _garden_game()
	var sim = g.sim
	var result := _answer(sim, "garden", "yes")
	check(result.contains("Marcus"), "the result: %s" % result)
	eq(sim.jobs.job_of(Kit.who(sim, "marcus")), "garden", "Marcus works the garden")
	_free(g)


# ------------------------------------------------------------------------ errand --

func _errand_game() -> Dictionary:
	var g := Kit.game(4)
	var sim = g.sim
	sim.stock.food = 10.0    # (2.5 days)
	Kit.at(sim, 3, 9.0)
	return g


func test_errand_for_a_short_stock_at_a_place_that_has_it() -> void:
	var g := _errand_game()
	var sim = g.sim
	var c := Kit.candidate(sim, "errand")
	eq(c.who, "marcus", "the best shot brings it")
	eq(c.others, ["dez"], "with the next best")
	eq(c.args.place, "houses", "to the nearest place with food and little danger")
	eq(c.text, "Marcus: Neighbourhood houses should have food. Dez and I could go. We'd find less without you.", "the words (round 18's errand terms: with the player away a trip finds less)")
	check(String(c.sub).contains("60%"), "and the line under them says how much: %s" % c.sub)
	eq(c.cost, {}, "the trip is the price")
	sim.stock.food = 16.0
	eq(_who(sim, "errand"), "", "four days of food is enough")
	sim.stock.food = 40.0
	sim.stock.water = 20.0
	eq(Kit.candidate(sim, "errand").args.place, "houses", "water short too: the same")
	sim.stock.water = 60.0
	sim.stock.meds = 2.0
	eq(_who(sim, "errand"), "", "meds are only at the pharmacy, which is too dangerous")
	sim.stock.meds = 10.0
	sim.stock.scrap = 9.0
	eq(_who(sim, "errand"), "", "scrap is only at the hardware store, which is too dangerous")
	_free(g)


func test_errand_while_the_trip_can_still_leave() -> void:
	var g := _errand_game()
	var sim = g.sim
	Kit.at(sim, 3, 9.4)
	check(_who(sim, "errand") != "", "at 09:24 there is time")
	Kit.at(sim, 3, 9.6)
	eq(_who(sim, "errand"), "", "at 09:36 the parties are about to stop leaving: no")
	Kit.at(sim, 3, 9.0)
	for i in 3:
		var z = sim.spawn(sim.scavenge.gate_center().x + float(i), sim.scavenge.gate_center().y - 2.0, "approach")
		z.hp = 10.0
	eq(_who(sim, "errand"), "", "with the dead at the gate nobody goes")
	_free(g)


func test_errand_is_the_scouts_then_the_most_travelled_and_takes_a_friend() -> void:
	var g := _errand_game()
	var sim = g.sim
	g.spec.holders["scout"] = "ana"
	eq(_who(sim, "errand"), "ana", "the scout")
	g.spec.holders.erase("scout")
	g.spec.trips["dez"] = 4
	eq(_who(sim, "errand"), "dez", "else the one who has been out most")
	var c := Kit.candidate(sim, "errand")
	eq(c.others, ["marcus"], "with the next best shot")
	g.rel.friends["dez"] = ["ana"]
	c = Kit.candidate(sim, "errand")
	eq(c.others, ["ana"], "with a friend, if he has one")
	_free(g)


func test_a_yes_to_errand_sends_the_party() -> void:
	var g := _errand_game()
	var sim = g.sim
	var id: int = Kit.raise(sim, "errand")
	var e: Dictionary = sim.radio._entry(id)
	near(float(e.due) - float(sim.clock_min), 60.0 - sim.game_hours(sim.radio.DELAY_SLOW) * 60.0, 0.01, "the call waits until the parties stop leaving (10:00) less the radio's longest delay (a yes at the last minute still sets off), not six hours")
	check(sim.radio.answer(id, "yes"), "the answer is taken")
	eq(sim.scavenge.parties.size(), 0, "nobody is out yet: the errand is in the radio's queue like any errand the player asks for")
	eq(sim.radio.errand_wait.size(), 1, "one errand waits")
	eq(sim.radio.errand_wait[0].ids, ["marcus", "dez"], "for Marcus and Dez")
	sim.radio.tick(sim.radio.DELAY_SLOW + 0.1)
	check(sim.radio.errand_wait.is_empty(), "after its delay it leaves the queue")
	eq(sim.scavenge.parties.size(), 1, "a party is out")
	eq(sim.scavenge.parties[0].members, ["marcus", "dez"], "Marcus and Dez")
	eq(String(sim.scavenge.parties[0].site), "houses", "to the houses")
	check(String(e.result).contains("Marcus and Dez"), "the result: %s" % e.result)
	check(sim.scavenge.is_errand(sim.scavenge.parties[0]), "it is an errand (the player is not along): round 18's penalty applies")
	check(bool(sim.scavenge.parties[0].result.get("errand", false)), "and its result says so")
	_free(g)


func test_a_yes_to_errand_at_the_last_minute_of_its_life_still_sets_off() -> void:
	var g := _errand_game()
	var sim = g.sim
	var id: int = Kit.raise(sim, "errand")
	var e: Dictionary = sim.radio._entry(id)
	Kit.at(sim, 3, (float(e.due) - 0.01 - float(sim.day - 1) * 1440.0 + 420.0) / 60.0)    # (the very last moment the call is open)
	check(sim.radio.answer(id, "yes"), "the answer is taken")
	check(String(sim.radio._entry(id).result).contains("set off"), "the yes is carried out: %s" % sim.radio._entry(id).result)
	Helpers.run(sim, sim.radio.DELAY_SLOW + 0.5)    # (the game's clock runs while the people answer)
	eq(sim.scavenge.parties.size(), 1, "the party is made after the radio's delay, before the parties stop leaving")
	for n in sim.radio.news:
		check(not String(n.text).begins_with("The errand could not start"), "no 'could not start': %s" % String(n.text))
	_free(g)


func test_a_yes_to_errand_is_counted_against_the_parties_the_radio_has_queued() -> void:
	var g := Kit.game(5)
	var sim = g.sim
	sim.stock.food = 10.0
	Kit.at(sim, 3, 9.0)
	var id: int = Kit.raise(sim, "errand")
	var c: Dictionary = sim.radio._entry(id)
	var party: Array = [String(c.data.who)] + c.data.others
	var rest: Array = []
	for who in ["dez", "marcus", "ana", "walt"]:
		if not party.has(who):
			rest.append(who)
	eq(rest.size(), 2, "(two others are left to ask)")
	for who in rest:
		check(sim.radio.request_errand([Kit.who(sim, who)], "houses").ok, "the player asks %s to go (the errand waits for its delay)" % who)
	eq(sim.radio.errand_wait.size(), 2, "two errands wait: as many as the parties the game allows")
	sim.radio.answer(id, "yes")
	var result := String(sim.radio._entry(id).result)
	check(result.begins_with("Not now: "), "a third does not fit: %s" % result)
	eq(sim.radio.errand_wait.size(), 2, "nothing was added to the queue")
	eq(sim.initiative.record_of(Kit.who(sim, String(c.data.who))).later, 1, "the yes counts as a later")
	eq(sim.initiative.record_of(Kit.who(sim, String(c.data.who))).yes, 0, "and not as a yes")
	sim.radio.tick(sim.radio.DELAY_SLOW + 0.1)
	check(not sim.scavenge.parties.is_empty(), "the errands the player asked for are on their way")
	for pt in sim.scavenge.parties:
		check(not pt.members.has(String(c.data.who)), "and the idea's party is not among them")
	_free(g)


func test_a_yes_to_errand_after_the_parties_have_stopped_leaving_is_not_now() -> void:
	var g := _errand_game()
	var sim = g.sim
	var id: int = Kit.raise(sim, "errand")
	Kit.at(sim, 3, 10.2)
	sim.radio.answer(id, "yes")
	check(String(sim.radio._entry(id).result).begins_with("Not now: "), "not now: %s" % sim.radio._entry(id).result)
	eq(sim.scavenge.parties.size(), 0, "nobody goes")
	_free(g)


# --------------------------------------------------------------------- swap_posts --

## The tower at the west of the gate is up, Dez holds a post it helps, Marcus (8 at Shooting) holds one it does not.
func _tower_game() -> Dictionary:
	var g := Kit.game(4)
	var sim = g.sim
	_stand(sim, "watchtower_home_1", "watchtower")
	var tower_post := ""
	for po in sim.jobs.posts():
		if tower_post == "" and sim.build.reach_bonus_at(Vector2(po.pos)) > 0.0:
			tower_post = String(po.id)
	check(tower_post != "", "(the tower helps a post)")
	sim.jobs.post_ids["dez"] = tower_post
	g["post"] = tower_post
	return g


func test_swap_posts_a_better_shot_asks_for_the_tower() -> void:
	var g := _tower_game()
	var sim = g.sim
	var c := Kit.candidate(sim, "swap_posts")
	eq(c.who, "marcus", "the better shot")
	eq(c.others, ["dez"], "who holds the post now")
	eq(c.args.post, g.post, "which post")
	eq(c.text, "Marcus: I shoot better than Dez. Give me the tower.", "the words")
	Kit.who(sim, "marcus").skills["Shooting"] = 7
	eq(_who(sim, "swap_posts"), "", "one point better is not enough")
	Kit.who(sim, "marcus").skills["Shooting"] = 8
	sim.jobs.post_ids["marcus"] = g.post
	sim.jobs.post_ids["dez"] = "bus"
	eq(_who(sim, "swap_posts"), "", "he has a tower post already")
	_free(g)


func test_a_yes_to_swap_posts_exchanges_the_posts_and_costs_the_loser() -> void:
	var g := _tower_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	var mood: float = sim.morale.value(dez)
	var result := _answer(sim, "swap_posts", "yes")
	check(result.contains("Marcus") and result.contains("Dez"), "the result: %s" % result)
	eq(String(sim.jobs.post_ids["marcus"]), g.post, "Marcus has the tower post")
	eq(String(sim.jobs.post_ids["dez"]), "tower_nw", "and Dez has Marcus's old one")
	near(sim.morale.value(dez), mood - 2.0, 1e-9, "Dez has lost a post: two points")
	near(g.rel.added("marcus", "dez"), -4.0, 1e-9, "and they are four points further apart")
	_free(g)


func test_a_no_to_swap_posts_costs_the_asker_a_little_with_the_holder() -> void:
	var g := _tower_game()
	var sim = g.sim
	_answer(sim, "swap_posts", "no")
	eq(String(sim.jobs.post_ids["dez"]), g.post, "the posts are as they were")
	near(g.rel.added("marcus", "dez"), -1.5, 1e-9, "a little cooler with Dez")
	_free(g)


func test_a_yes_to_swap_posts_is_checked_again() -> void:
	var g := _tower_game()
	var sim = g.sim
	var id: int = Kit.raise(sim, "swap_posts")
	sim.jobs.post_ids["dez"] = "bus"
	sim.jobs.post_ids["ana"] = g.post
	sim.radio.answer(id, "yes")
	check(String(sim.radio._entry(id).result).begins_with("Not now"), "the post is not Dez's any more: %s" % sim.radio._entry(id).result)
	eq(String(sim.jobs.post_ids["marcus"]), "tower_nw", "nothing moved")
	_free(g)


# -------------------------------------------------------------------- post_beside --

## Marcus (at the north-west tower) and Ana (at the west fence) are friends; Dez holds the post next to Ana's.
func _friends_game() -> Dictionary:
	var g := Kit.game(4)
	var sim = g.sim
	g.rel.friends = {"marcus": ["ana"], "ana": ["marcus"]}
	sim.jobs.post_ids["dez"] = "west_middle"
	return g


func test_post_beside_a_friend_far_along_the_wall_asks_to_stand_next_to_them() -> void:
	var g := _friends_game()
	var sim = g.sim
	var c := Kit.candidate(sim, "post_beside")
	eq(c.who, "marcus", "the one who is far from his friend")
	eq(c.others, ["ana", "dez"], "the friend and the one next to her")
	eq(c.text, "Marcus: Put me beside Ana on the wall.", "the words")
	sim.jobs.post_ids["marcus"] = "west_south"
	eq(_who(sim, "post_beside"), "", "five tiles apart is beside already")
	sim.jobs.post_ids["marcus"] = "tower_nw"
	sim.jobs.post_ids["dez"] = "bus"
	eq(_who(sim, "post_beside"), "", "with nobody on a post near her there is nobody to change with")
	_free(g)


func test_a_yes_to_post_beside_exchanges_the_posts_and_warms_the_friends() -> void:
	var g := _friends_game()
	var sim = g.sim
	var result := _answer(sim, "post_beside", "yes")
	check(result.contains("Marcus") and result.contains("Ana"), "the result: %s" % result)
	eq(String(sim.jobs.post_ids["marcus"]), "west_middle", "Marcus is next to Ana")
	eq(String(sim.jobs.post_ids["dez"]), "tower_nw", "Dez has the tower post")
	near(g.rel.added("marcus", "ana"), 3.0, 1e-9, "three points closer")
	_free(g)


func test_a_no_to_post_beside_changes_nothing() -> void:
	var g := _friends_game()
	var sim = g.sim
	_answer(sim, "post_beside", "no")
	eq(String(sim.jobs.post_ids["marcus"]), "tower_nw", "he stays")
	eq(g.rel.adds.size(), 0, "no change between them")
	_free(g)


# ---------------------------------------------------------------------- supper --

func test_supper_when_the_crew_is_low_or_has_lost_somebody() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Kit.at(sim, 3, 15.0)
	eq(_who(sim, "supper"), "", "(a crew at 70 does not need one)")
	_mood(sim, 61.9)
	var c := Kit.candidate(sim, "supper")
	eq(c.who, "ana", "the best Optimist brings it")
	eq(c.text, "Ana: Let's all eat together tonight. It would help.", "the words")
	eq(c.cost, {"food": 2}, "two food")
	_mood(sim, 62.0)
	eq(_who(sim, "supper"), "", "a crew at 62 does not")
	g.rel.loss = {"id": "hector", "name": "Hector Ruiz", "day": 3}
	eq(_who(sim, "supper"), "ana", "a loss within the day does")
	g.rel.loss = {"id": "hector", "name": "Hector Ruiz", "day": 1}
	eq(_who(sim, "supper"), "", "(not one of two days ago)")
	g.rel.loss = {}
	_mood(sim, 50.0)
	Kit.at(sim, 3, 13.9)
	eq(_who(sim, "supper"), "", "not before 14:00")
	Kit.at(sim, 3, 18.1)
	eq(_who(sim, "supper"), "", "nor after 18:00")
	Kit.at(sim, 3, 16.0)
	sim.stock.food = 11.9
	eq(_who(sim, "supper"), "", "with under twelve food there is no feast")
	_free(g)


func test_the_voice_then_the_cook_bring_the_supper() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Kit.at(sim, 3, 15.0)
	_mood(sim, 50.0)
	var def: Dictionary = sim.recruits.make_def(0)
	def["role"] = "Cook"
	var cook = sim.add_person(def)
	eq(_who(sim, "supper"), String(cook.id), "the Cook before the Optimist")
	g.rel.voice_id = "dez"
	eq(_who(sim, "supper"), "dez", "the voice before the Cook")
	_free(g)


func test_a_yes_to_supper_feeds_everyone_and_lifts_the_mood() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Kit.at(sim, 3, 15.0)
	_mood(sim, 50.0)
	var food: float = sim.stock.food
	var result := _answer(sim, "supper", "yes")
	check(result.contains("together"), "the result: %s" % result)
	near(sim.stock.food, food - 2.0, 1e-9, "two food are eaten")
	for p in sim.people:
		near(sim.morale.value(p), 54.0 + (sim.initiative.YES_MORALE if String(p.id) == "ana" else 0.0), 1e-9, "%s is four points better" % p.first)
	eq(g.rel.adds.size(), 3, "every pair at the base (three) is closer")
	for a in g.rel.adds:
		near(float(a.delta), 2.0, 1e-9, "by two")
	_free(g)


func test_a_yes_to_supper_is_checked_again() -> void:
	var g := Kit.game(4)
	var sim = g.sim
	Kit.at(sim, 3, 15.0)
	_mood(sim, 50.0)
	var id: int = Kit.raise(sim, "supper")
	sim.stock.food = 8.0
	sim.radio.answer(id, "yes")
	check(String(sim.radio._entry(id).result).begins_with("Not now"), "no food for it: %s" % sim.radio._entry(id).result)
	near(sim.stock.food, 8.0, 1e-9, "nothing eaten")
	_free(g)


# ---------------------------------------------------------------------- quarrel --

## Walt and Dez are rivals and both on the Builders; Ana is a friend of both.
func _quarrel_game() -> Dictionary:
	var g := Kit.game(5)
	var sim = g.sim
	g.rel.rivals = {"dez": ["walt"], "walt": ["dez"]}
	g.rel.friends = {"ana": ["dez", "walt"]}
	sim.jobs.assign(Kit.who(sim, "dez"), "builders")
	sim.jobs.assign(Kit.who(sim, "walt"), "builders")
	return g


func test_quarrel_two_rivals_on_one_station() -> void:
	var g := _quarrel_game()
	var sim = g.sim
	var c := Kit.candidate(sim, "quarrel")
	eq(c.who, "ana", "a friend of both brings it")
	eq(c.others, ["walt", "dez"], "the one who stays and the one who moves")
	eq(c.text, "Ana: Walt and Dez are at each other's throats. Put them apart?", "the words")
	g.rel.friends = {"ana": ["dez"]}
	eq(_who(sim, "quarrel"), "", "a friend of one is not enough")
	g.rel.voice_id = "marcus"
	eq(_who(sim, "quarrel"), "marcus", "but the voice brings it")
	sim.jobs.assign(Kit.who(sim, "dez"), "bench")
	eq(_who(sim, "quarrel"), "", "on different stations with posts far apart they are no problem")
	_free(g)


func test_quarrel_two_rivals_with_posts_side_by_side() -> void:
	var g := _quarrel_game()
	var sim = g.sim
	sim.jobs.assign(Kit.who(sim, "dez"), "bench")
	sim.jobs.post_ids["dez"] = "north_middle"
	sim.jobs.post_ids["walt"] = "bus"
	eq(_who(sim, "quarrel"), "ana", "posts 4 tiles apart")
	sim.jobs.post_ids["walt"] = "north_east"
	eq(_who(sim, "quarrel"), "", "8.5 tiles apart: more than six")
	sim.jobs.post_ids["walt"] = "bus"
	g.rel.rivals = {}
	eq(_who(sim, "quarrel"), "", "and not rivals: no quarrel")
	_free(g)


func test_a_yes_to_quarrel_on_a_station_moves_one_to_another() -> void:
	var g := _quarrel_game()
	var sim = g.sim
	var result := _answer(sim, "quarrel", "yes")
	check(result.contains("Dez"), "the result: %s" % result)
	eq(sim.jobs.job_of(Kit.who(sim, "walt")), "builders", "Walt stays")
	eq(sim.jobs.job_of(Kit.who(sim, "dez")), "bench", "Dez goes to the bench: the other station that suits him")
	near(g.rel.added("walt", "dez"), 2.0, 1e-9, "and they are two points closer for it")
	_free(g)


func test_a_yes_to_quarrel_at_the_wall_moves_one_post_far_away() -> void:
	var g := _quarrel_game()
	var sim = g.sim
	sim.jobs.assign(Kit.who(sim, "dez"), "bench")
	sim.jobs.post_ids["dez"] = "north_middle"
	sim.jobs.post_ids["walt"] = "bus"
	_answer(sim, "quarrel", "yes")
	var from: Vector2 = sim.jobs.post("bus").pos
	var to: Vector2 = sim.jobs.post(String(sim.jobs.post_ids["dez"])).pos
	check(from.distance_to(to) >= 9.0, "Dez's post is now at least nine tiles from Walt's: %s" % str(sim.jobs.post_ids["dez"]))
	eq(String(sim.jobs.post_ids["walt"]), "bus", "Walt's is as it was")
	_free(g)


func test_a_later_to_quarrel_lets_them_be() -> void:
	var g := _quarrel_game()
	var sim = g.sim
	_answer(sim, "quarrel", "later")
	eq(sim.jobs.job_of(Kit.who(sim, "dez")), "builders", "nobody moved")
	eq(g.rel.adds.size(), 0, "nothing said")
	_free(g)


# ----------------------------------------------------------------------- lesson --

## Gives a person a skill they started with (so that they can still learn it).
func _learns(p, skill: String, value: int) -> void:
	p.def = p.def.duplicate(true)    # (the roster's own entry is shared by every game of the run: never written to)
	p.skills[skill] = value
	p.def.skills[skill] = value


## Ana (medicine 10) is the medic, and may show Marcus (0) how to dress a wound.
func _lesson_game() -> Dictionary:
	var g := Kit.game(5)
	var sim = g.sim
	g.spec.holders["medic"] = "ana"
	return g


func test_lesson_a_title_holder_and_a_learner_who_is_far_behind() -> void:
	var g := _lesson_game()
	var sim = g.sim
	var c := Kit.candidate(sim, "lesson")
	eq(c.who, "ana", "the medic teaches")
	eq(c.others, ["marcus"], "the one who knows least of it")
	eq(c.text, "Ana: I could show Marcus how to dress a wound. An hour of both of us.", "the words")
	g.rel.affinities["ana|marcus"] = -1.0
	eq(Kit.candidate(sim, "lesson").others, ["dez"], "not with someone she is cold to: the next")
	g.rel.affinities["ana|marcus"] = 0.0
	for id in ["marcus", "dez", "walt"]:
		_learns(Kit.who(sim, id), "Medicine", 5)
	eq(_who(sim, "lesson"), "", "with nobody at 4 or under there is nobody to teach")
	_learns(Kit.who(sim, "marcus"), "Medicine", 4)
	eq(_who(sim, "lesson"), "ana", "at 4 there is")
	Kit.who(sim, "ana").skills["Medicine"] = 6
	eq(_who(sim, "lesson"), "", "a teacher under 7 does not")
	Kit.who(sim, "ana").skills["Medicine"] = 7
	eq(_who(sim, "lesson"), "ana", "at 7 she does")
	g.spec.holders.erase("medic")
	eq(_who(sim, "lesson"), "", "with no title there is no teacher")
	_free(g)


func test_lesson_needs_both_free_and_the_day() -> void:
	var g := _lesson_game()
	var sim = g.sim
	var marcus = Kit.who(sim, "marcus")
	marcus.drafted = true
	marcus.order = Vector3(40.0, 40.0, 0.0)
	eq(Kit.candidate(sim, "lesson").others, ["dez"], "not with someone at an order: the next who knows little of it")
	marcus.order = null
	marcus.drafted = false
	Kit.at(sim, 3, 17.0)
	eq(_who(sim, "lesson"), "ana", "an hour needs two before dusk: 17:00 is the last time")
	Kit.at(sim, 3, 17.2)
	eq(_who(sim, "lesson"), "", "and 17:12 is too late")
	_free(g)


func test_lesson_does_not_take_the_radio_or_the_lookout_from_their_hour() -> void:
	var g := _lesson_game()
	var sim = g.sim
	sim.jobs.unassign(Kit.who(sim, "walt"))
	check(sim.jobs.assign(Kit.who(sim, "marcus"), "radio"), "(Marcus is at the radio)")
	Kit.at(sim, 3, 10.0)
	eq(Kit.candidate(sim, "lesson").others, ["marcus"], "(at 10:00 Marcus can sit down: he is back by 11:00)")
	Kit.at(sim, 3, 10.6)
	eq(Kit.candidate(sim, "lesson").others, ["dez"], "at 10:36 an hour would take the radio's man into the noon hour: another")
	Kit.at(sim, 3, 12.7)
	eq(Kit.candidate(sim, "lesson").others, ["marcus"], "after the noon hour he may")
	check(sim.jobs.assign(Kit.who(sim, "marcus"), "watch"), "(and then at the lookout post)")
	Kit.at(sim, 3, 16.2)
	eq(Kit.candidate(sim, "lesson").others, ["dez"], "nor the lookout who has the forecast at 17:00")
	_free(g)


func test_a_lesson_gives_way_to_somebody_who_is_hurt() -> void:
	var g := _lesson_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	dez.bleeding = 1.0
	eq(_who(sim, "lesson"), "", "with somebody bleeding the healers are wanted: no lesson")
	dez.bleeding = 0.0
	var marcus = Kit.who(sim, "marcus")
	_answer(sim, "lesson", "yes")
	Helpers.run(sim, 3.0)
	eq(sim.initiative.lessons().size(), 1, "(the lesson is on)")
	dez.bleeding = 1.0
	Helpers.run(sim, 1.0)
	eq(sim.initiative.lessons().size(), 0, "somebody bleeds: it is over")
	check(marcus.order == null, "and the two are let go")
	_free(g)


func test_a_yes_to_lesson_sits_them_down_for_an_hour_and_teaches_a_point() -> void:
	var g := _lesson_game()
	var sim = g.sim
	var ana = Kit.who(sim, "ana")
	var marcus = Kit.who(sim, "marcus")
	var treated: int = int(ana.stats.treated) + int(marcus.stats.treated)
	var result := _answer(sim, "lesson", "yes")
	check(result.contains("Ana") and result.contains("Marcus"), "the result: %s" % result)
	check(ana.order != null and marcus.order != null, "both are sent to a place to sit: %s %s" % [str(ana.order), str(marcus.order)])
	check(Vector2(ana.order.x, ana.order.y) != Vector2(marcus.order.x, marcus.order.y), "not the same one")
	eq(sim.initiative.lessons().size(), 1, "a lesson is on")
	eq(int(marcus.skills.Medicine), 0, "(nothing learnt yet)")
	Helpers.run(sim, 10.0)    # (half an hour)
	eq(sim.initiative.lessons().size(), 1, "it is still on")
	check(ana.order != null and marcus.order != null, "and they are still sitting")
	Helpers.run(sim, 11.0)    # (an hour and more)
	eq(sim.initiative.lessons().size(), 0, "it is over after an hour")
	check(ana.order == null and marcus.order == null, "they are let go")
	eq(int(marcus.skills.Medicine), 1, "Marcus has a point more of Medicine")
	eq(int(ana.stats.treated) + int(marcus.stats.treated), treated, "(and a lesson is not practice: nobody has treated anyone)")
	near(g.rel.added("ana", "marcus"), 3.0, 1e-9, "they are three points closer")
	var cheered := false
	for s in sim.morale.shocks.get("ana", []):
		if float(s.value) > 0.0 and String(s.label).to_lower().contains("lesson"):
			cheered = true
	check(cheered, "and teaching has cheered Ana")
	_free(g)


func test_a_lesson_that_is_interrupted_teaches_nothing() -> void:
	var g := _lesson_game()
	var sim = g.sim
	var marcus = Kit.who(sim, "marcus")
	_answer(sim, "lesson", "yes")
	Helpers.run(sim, 4.0)
	sim.radio.alarm(true)
	Helpers.run(sim, 1.0)
	eq(sim.initiative.lessons().size(), 0, "the call to arms ends the lesson")
	eq(int(marcus.skills.Medicine), 0, "and teaches nothing")
	check(marcus.order == null or marcus.order.z > 0.5, "they are not kept at the lesson's place")
	_free(g)


func test_a_lesson_in_progress_is_saved_and_goes_on_after_a_load() -> void:
	var a := _lesson_game()
	var sim = a.sim
	_answer(sim, "lesson", "yes")
	Helpers.run(sim, 5.0)
	var d: Dictionary = SaveGame.to_dict(sim)
	var b := _lesson_game()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "the save loads")
	eq(b.sim.initiative.lessons(), sim.initiative.lessons(), "the lesson is as it was")
	Helpers.run(sim, 17.0)
	Helpers.run(b.sim, 17.0)
	eq(int(Kit.who(b.sim, "marcus").skills.Medicine), int(Kit.who(sim, "marcus").skills.Medicine), "and it ends the same")
	eq(int(Kit.who(b.sim, "marcus").skills.Medicine), 1, "with the point")
	eq(b.sim.initiative.lessons().size(), 0, "over")
	_free(a)
	_free(b)


# --------------------------------------------------------------------- farewell --

## Hector (a friend of Dez's) has just died; it is 16:00 of the day.
func _funeral_game() -> Dictionary:
	var g := Kit.game(5)
	var sim = g.sim
	var hector = sim.add_person(sim.recruits.queue.pop_front())
	hector.dead = true
	g.rel.loss = {"id": "hector", "name": "Hector Ruiz", "day": 3}
	Kit.at(sim, 3, 16.0)
	return g


func test_farewell_for_somebody_lost_within_a_day_in_the_afternoon() -> void:
	var g := _funeral_game()
	var sim = g.sim
	var c := Kit.candidate(sim, "farewell")
	eq(c.who, "dez", "his closest friend brings it")
	eq(c.text, "Dez: Let's say a few words for Hector at dusk.", "the words")
	g.rel.voice_id = "ana"
	eq(_who(sim, "farewell"), "ana", "the voice, if there is one, before the friend")
	g.rel.voice_id = ""
	Kit.at(sim, 3, 14.9)
	eq(_who(sim, "farewell"), "", "not before 15:00")
	Kit.at(sim, 3, 18.4)
	eq(_who(sim, "farewell"), "dez", "until 18:30")
	Kit.at(sim, 3, 18.6)
	eq(_who(sim, "farewell"), "", "not after")
	Kit.at(sim, 4, 16.0)
	eq(_who(sim, "farewell"), "dez", "the day after it still is")
	Kit.at(sim, 5, 16.0)
	eq(_who(sim, "farewell"), "", "two days later it is too late")
	g.rel.loss = {}
	Kit.at(sim, 3, 16.0)
	eq(_who(sim, "farewell"), "", "and with nobody lost there is none")
	_free(g)


func test_a_yes_to_farewell_lifts_the_mourners_most() -> void:
	var g := _funeral_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	var marcus = Kit.who(sim, "marcus")
	var d: float = sim.morale.value(dez)
	var m: float = sim.morale.value(marcus)
	var result := _answer(sim, "farewell", "yes")
	check(result.contains("Hector"), "the result: %s" % result)
	near(sim.morale.value(dez) - d, 6.0 + 2.0 + sim.initiative.YES_MORALE, 1e-9, "Dez, who was close: six, and the camp's two, and his idea taken up")
	near(sim.morale.value(marcus) - m, 2.0, 1e-9, "Marcus: two")
	_free(g)


func test_a_no_to_farewell_hurts_the_mourners() -> void:
	var g := _funeral_game()
	var sim = g.sim
	var dez = Kit.who(sim, "dez")
	var marcus = Kit.who(sim, "marcus")
	var d: float = sim.morale.value(dez)
	var m: float = sim.morale.value(marcus)
	_answer(sim, "farewell", "no")
	near(sim.morale.value(dez) - d, -2.0 + sim.initiative.NO_MORALE, 1e-9, "Dez: nobody said a word, and his idea turned down")
	near(sim.morale.value(marcus) - m, 0.0, 1e-9, "Marcus is as he was")
	_free(g)


# ---------------------------------------------------------------- all thirteen --

## A game in which an idea of this kind is on the table.
func _on_the_table(kind: String) -> Dictionary:
	var g: Dictionary
	match kind:
		"fix_wall":
			g = Kit.game(4)
			Kit.wear(g.sim, 5, 0.8)
		"build":
			g = Kit.game(4)
			g.sim.stock.ammo = 50.0
		"bench_target":
			g = Kit.game(4)
		"wall_line":
			g = _builders_game()
			Kit.wear(g.sim, 5, 0.75)
		"desk":
			g = Kit.game(4)
			g.sim.jobs.unassign(Kit.who(g.sim, "marcus"))
		"garden":
			g = _garden_game()
		"errand":
			g = _errand_game()
		"swap_posts":
			g = _tower_game()
		"post_beside":
			g = _friends_game()
		"supper":
			g = Kit.game(4)
			Kit.at(g.sim, 3, 15.0)
			_mood(g.sim, 50.0)
		"quarrel":
			g = _quarrel_game()
		"lesson":
			g = _lesson_game()
		_:
			g = _funeral_game()
	return g


## What an idea can change, as plain data: the stocks, the jobs, the posts, the settings, the orders, the parties, the sites, the lessons
## (and the mood of everybody, when asked).
func _snapshot(sim, with_mood: bool) -> String:
	var orders := {}
	for p in sim.people:
		orders[String(p.id)] = [str(p.order), p.repair.id if p.repair != null else -1, p.drafted]
	var d := {
		"stock": sim.stock.duplicate(), "assignments": sim.jobs.assignments.duplicate(), "posts": sim.jobs.post_ids.duplicate(), "settings": sim.jobs.settings.duplicate(true),
		"orders": orders, "parties": sim.scavenge.parties.size(), "sites": sim.build.active_site().get("id", ""), "lessons": sim.initiative.lessons(),
	}
	if with_mood:
		var mood := {}
		for p in sim.people:
			mood[String(p.id)] = sim.morale.value(p)
		d["mood"] = mood
	return JSON.stringify(d)


func test_each_of_the_thirteen_kinds_can_be_on_the_table_and_is_whole() -> void:
	for kind in _kinds():
		var g := _on_the_table(kind)
		var sim = g.sim
		for fn in ["_find_", "_why_", "_apply_"]:
			check(sim.initiative.has_method(fn + kind), "%s has %s" % [kind, fn])
		var kd: Dictionary = sim.initiative._kd(kind)
		for key in ["base", "line", "yes", "sub", "done", "params"]:
			if kind != "desk" or key in ["base", "params"]:
				check(kd.has(key), "%s has %s in its data" % [kind, key])
		var c := Kit.candidate(sim, kind)
		check(not c.is_empty(), "%s is on the table" % kind)
		if c.is_empty():
			_free(g)
			continue
		check(String(c.text).length() > 12 and String(c.text).contains(": "), "%s has words: %s" % [kind, c.text])
		check(String(c.yes_label).begins_with("Yes: "), "%s: the button says yes: %s" % [kind, c.yes_label])
		check(is_finite(float(c.score)), "%s has a score" % kind)
		check(Kit.who(sim, String(c.who)) != null, "%s: the proposer is somebody" % kind)
		for id in c.others:
			check(Kit.who(sim, String(id)) != null, "%s: %s is somebody" % [kind, id])
		for k in c.cost:
			check(float(c.cost[k]) > 0.0 and ["scrap", "food"].has(String(k)), "%s: a price in scrap or food" % kind)
			check(String(c.text).contains(k) or String(c.yes_label).contains(k), "%s says its price (%s): %s | %s" % [kind, k, c.text, c.yes_label])
		var before := JSON.stringify(SaveGame.to_dict(sim))
		sim.initiative.candidates()
		eq(JSON.stringify(SaveGame.to_dict(sim)), before, "%s: a look at the candidates changes nothing in the game" % kind)
		_free(g)


func _kinds() -> Array:
	return ["fix_wall", "build", "bench_target", "wall_line", "desk", "garden", "errand", "swap_posts", "post_beside", "supper", "quarrel", "lesson", "farewell"]


func test_a_later_and_a_no_change_nothing_in_the_game_whatever_the_kind() -> void:
	for kind in _kinds():
		for option in ["later", "no"]:
			var g := _on_the_table(kind)
			var sim = g.sim
			var before := _snapshot(sim, false)
			var id: int = Kit.raise(sim, kind)
			check(id > 0, "%s is raised" % kind)
			sim.radio.answer(id, option)
			eq(_snapshot(sim, false), before, "%s: %s changes nothing of the stocks, jobs, posts, orders" % [kind, option])
			_free(g)


func test_a_yes_changes_something_real_whatever_the_kind() -> void:
	for kind in _kinds():
		var g := _on_the_table(kind)
		var sim = g.sim
		var before := _snapshot(sim, true)
		var id: int = Kit.raise(sim, kind)
		check(id > 0, "%s is raised" % kind)
		sim.radio.answer(id, "yes")
		var e: Dictionary = sim.radio._entry(id)
		check(not String(e.result).begins_with("Not now"), "%s was done: %s" % [kind, e.result])
		check(_snapshot(sim, true) != before, "%s: a yes changed the game" % kind)
		eq(sim.initiative.stats().yes, 1, "%s: one yes counted" % kind)
		_free(g)


func test_a_lesson_is_broken_off_when_somebody_is_asked_to_come_along() -> void:
	var g := _lesson_game()
	var sim = g.sim
	var marcus = Kit.who(sim, "marcus")
	_answer(sim, "lesson", "yes")
	Helpers.run(sim, 2.0)
	sim.radio.set_stance(marcus, "follow")
	Helpers.run(sim, 1.0)
	eq(sim.initiative.lessons().size(), 0, "the lesson is over")
	eq(int(marcus.skills.Medicine), 0, "and nothing was learnt")
	_free(g)


## The idea says what the errand finds less of from the scavenging module's terms (round 18's `errand_terms`), not from a number of its
## own: a module with other terms (a stand-in that finds half) changes the words.
func test_errand_says_what_it_finds_less_of_from_the_terms_of_the_scavenging_module() -> void:
	var g := _errand_game()
	var sim = g.sim
	var stand_in := GDScript.new()
	stand_in.source_code = "extends \"res://scripts/sim/scavenge.gd\"\nfunc errand_terms() -> Dictionary:\n\treturn {\"loot\": 0.5}\n"
	check(stand_in.reload() == OK, "(the stand-in loads)")
	var scavenge = stand_in.new()
	scavenge.setup(sim)
	scavenge.start()
	scavenge.use_town()
	sim.scavenge = scavenge
	var c := Kit.candidate(sim, "errand")
	eq(c.text, "Marcus: Neighbourhood houses should have food. Dez and I could go. We'd find less without you.", "the words")
	check(String(c.sub).contains("50%"), "and the line under them: %s" % c.sub)
	_free(g)


# ----------------------------------------------------------------- the real loop --

func test_two_games_played_through_bring_and_answer_the_same_ideas() -> void:
	var a := Kit.game(5, 7, false)
	var b := Kit.game(5, 7, false)
	for g in [a, b]:
		Kit.wear(g.sim, 5, 0.8)
		g.sim.stock.food = 18.0
	var logs := [[], []]
	var games := [a, b]
	for step in 5400:    # (a hundred and eighty seconds of the rules' time: nine game hours)
		for i in 2:
			var sim = games[i].sim
			sim.update(1.0 / 30.0)
			sim.events.clear()
			for e in sim.radio.open_calls():
				if String(e.kind) == "idea" and float(sim.clock_min) - float(e.t) >= 15.0:
					logs[i].append([int(e.id), String(e.data.idea), String(e.data.who), String(e.text)])
					sim.radio.answer(int(e.id), "yes" if int(e.id) % 2 == 0 else "no")
	check(not logs[0].is_empty(), "ideas came and were answered")
	eq(logs[0], logs[1], "the same ideas, from the same people, in the same words")
	eq(JSON.stringify(SaveGame.to_dict(a.sim)), JSON.stringify(SaveGame.to_dict(b.sim)), "and the two games are the same game")
	eq(a.sim.rng.state, b.sim.rng.state, "with the same dice thrown")
	_free(a)
	_free(b)
