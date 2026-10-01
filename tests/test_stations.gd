extends "res://tests/case.gd"
## What each station does (round 5): the workbench makes ammo, the wall crew mends the walls, the
## vegetable beds grow food by the hour, the infirmary heals faster and is preferred as the healer,
## the radio desk brings the noon call and the lookout post gives the forecast. A station works
## through the people `sim.jobs.working(...)` lists: those assigned to it who are at their seat and
## free. The assignments themselves (seats, posts, saves) are tested in test_jobs.gd.

const Helpers := preload("res://tests/helpers.gd")
const Storyteller := preload("res://scripts/sim/storyteller.gd")
const Supplies := preload("res://scripts/sim/supplies.gd")
const Medical := preload("res://scripts/sim/medical.gd")
const Workshop := preload("res://scripts/sim/workshop.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

## An open spot in the hall, a short walk from the infirmary door (as in test_medical).
const HALL := Vector2(46.0, 46.5)


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


func _seg(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


## A quiet game at `hour`: no nights, no dead about, the storyteller off (as Helpers.make has it).
func _game(hour: float = 9.0, seed_value: int = 61) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.events.clear()
	return g


## A wall section worn to `share` of its health.
func _wear(sim, id: int, share: float):
	var seg = _seg(sim, id)
	seg.hp = seg.max_hp * share
	sim._segment_state(seg)
	return seg


## Everyone but the named people stands still on an order, so those are the only ones free.
func _busy(sim, free: Array) -> void:
	for p in sim.people:
		if not free.has(p.first):
			sim.order_move(p, p.x, p.y)


# ------------------------------------------------------------------ the workbench --

func test_the_bench_makes_ammo_until_the_target_and_not_a_scrap_more() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.scrap = 60.0
	sim.stock.ammo = 100.0
	sim.jobs.set_setting("bench", "ammo_target", 150)
	var dez = _person(sim, "Dez")
	Helpers.seat(sim, dez)
	check(sim.workshop.can_make(), "there is something to make")
	check(sim.workshop.crafting(dez), "Dez is at it")
	Helpers.run(sim, 25.0)   # 1.25 game hours; the 50 ammo take about 0.8 of one
	near(float(sim.stock.ammo), 150.0, 0.01, "the ammo stops at the target")
	near(60.0 - float(sim.stock.scrap), 50.0 / Workshop.AMMO_PER_SCRAP, 0.01, "after 6.25 scrap, eight ammo to each")
	check(not sim.workshop.can_make(), "and the bench has nothing to make")
	check(not sim.workshop.crafting(dez), "so he is not making ammo any more")
	var scrap: float = sim.stock.scrap
	Helpers.run(sim, 5.0)
	near(float(sim.stock.scrap), scrap, 0.0001, "nothing more is used")
	sim.jobs.set_setting("bench", "ammo_target", 300)
	check(sim.workshop.can_make(), "a higher target gives him work again")
	g.world.free()


func test_the_bench_keeps_back_the_scrap_the_reserve_setting_names() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.scrap = 24.0
	sim.stock.ammo = 100.0
	sim.jobs.set_setting("bench", "scrap_reserve", 20)
	Helpers.seat(sim, _person(sim, "Dez"))
	var told := 0
	var was_up := false
	for i in 25 * 30:
		sim.update(1.0 / 30.0)
		var up: bool = sim.alerts.has("workshop-idle")
		if up and not was_up:
			told += 1
		was_up = up
	near(float(sim.stock.scrap), 20.0, 0.01, "the bench stops with the reserve left")
	near(float(sim.stock.ammo), 100.0 + 4.0 * Workshop.AMMO_PER_SCRAP, 0.05, "every scrap above it became ammo")
	eq(told, 1, "and the crew is told the bench is idle, once")
	check(not sim.workshop.can_make(), "it cannot make any more")
	g.world.free()


func test_the_bench_needs_someone_sitting_at_it() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.scrap = 40.0
	sim.stock.ammo = 100.0
	var dez = _person(sim, "Dez")
	sim.jobs.unassign(dez)
	Helpers.run(sim, 10.0)
	near(float(sim.stock.scrap), 40.0, 0.0001, "with nobody assigned, nothing is made")
	sim.jobs.assign(dez, "bench")
	dez.x = 38.0
	dez.y = 36.0
	Helpers.run(sim, 1.0)
	near(float(sim.stock.scrap), 40.0, 0.0001, "and nothing is made on the walk to it")
	Helpers.run(sim, 10.0)
	check(Vector2(dez.x, dez.y).distance_to(sim.jobs.seat_pos(dez)) < 0.6, "he gets to the bench")
	check(float(sim.stock.scrap) < 40.0, "and then it is made")
	g.world.free()


func test_two_people_at_the_bench_make_twice_as_much() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.scrap = 100.0
	sim.stock.ammo = 100.0
	var dez = _person(sim, "Dez")
	var hector = _person(sim, "Hector")
	Helpers.seat(sim, dez)
	check(Helpers.seat(sim, hector, "bench"), "Hector takes the other seat")
	check(sim.jobs.working("bench").size() == 2, "both are at work")
	Helpers.run(sim, 20.0)   # one game hour
	var want: float = sim.workshop.scrap_per_hour(dez) + sim.workshop.scrap_per_hour(hector)
	near(100.0 - float(sim.stock.scrap), want, 0.5, "they use the sum of what each gets through in an hour: %.2f" % (100.0 - float(sim.stock.scrap)))
	near(float(dez.stats.crafted) + float(hector.stats.crafted), 100.0 - float(sim.stock.scrap), 0.01, "and each is credited with their own")
	g.world.free()


func test_a_bench_worker_with_nothing_to_make_mends_only_what_is_under_half() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 400.0    # over the target: nothing to make
	sim.jobs.unassign(_person(sim, "Walt"))   # and nobody on the wall crew
	var dez = _person(sim, "Dez")
	Helpers.seat(sim, dez)
	check(not sim.workshop.can_make(), "the bench has nothing to make")
	check(sim.jobs.idle(dez), "so Dez is idle, and does chores")
	var seg = _wear(sim, 4, 0.6)
	Helpers.run(sim, 3.0)
	check(dez.repair == null and is_equal_approx(seg.hp, seg.max_hp * 0.6), "a section at 60% is not a chore")
	seg = _wear(sim, 4, 0.4)
	Helpers.run(sim, 3.0)
	check(dez.repair == seg, "one at 40% is: Dez is on his way to it")
	g.world.free()


func test_a_bench_worker_with_something_to_make_is_not_pulled_off_it() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	sim.jobs.unassign(_person(sim, "Walt"))
	var dez = _person(sim, "Dez")
	Helpers.seat(sim, dez)
	_wear(sim, 4, 0.2)
	Helpers.run(sim, 5.0)
	check(sim.workshop.crafting(dez) and dez.repair == null, "he stays at the bench while a wall is worn")
	g.world.free()


# --------------------------------------------------------------------- the wall crew --

func test_the_wall_crew_mends_the_most_worn_section_by_day() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0   # the bench has work, so Dez is not on chores
	var a = _wear(sim, 4, 0.6)
	var b = _wear(sim, 5, 0.3)
	var walt = _person(sim, "Walt")
	check(sim.jobs.job_of(walt) == "builders", "Walt is on the wall crew")
	Helpers.run(sim, 1.5)
	check(walt.repair == b, "he goes to the most worn section")
	Helpers.run(sim, 12.0)
	check(b.hp > 40.0, "and mends it: %.0f" % b.hp)
	check(a.hp >= a.max_hp * 0.6, "the other is not made worse")
	g.world.free()


func test_the_wall_crew_mends_under_the_threshold_the_station_sets() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	var seg = _wear(sim, 4, 0.6)
	var walt = _person(sim, "Walt")
	sim.jobs.set_setting("builders", "repair_below", 50)
	Helpers.run(sim, 3.0)
	check(walt.repair == null, "a section at 60% is left alone when the crew mends under 50%")
	sim.jobs.set_setting("builders", "repair_below", 70)
	Helpers.run(sim, 3.0)
	check(walt.repair == seg, "and at 70% it is mended")
	g.world.free()


func test_nobody_is_sent_with_the_scrap_under_the_minimum() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	_wear(sim, 4, 0.3)
	sim.stock.scrap = 4.0
	Helpers.run(sim, 5.0)
	for p in sim.people:
		check(p.repair == null, "%s is not sent with under five scrap" % p.first)
	g.world.free()


func test_a_crew_member_under_an_order_or_down_is_not_sent() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	_wear(sim, 4, 0.3)
	var walt = _person(sim, "Walt")
	sim.order_move(walt, walt.x, walt.y)
	Helpers.run(sim, 4.0)
	check(walt.repair == null, "an ordered Walt stays where he was put")
	sim.toggle_draft(walt)
	walt.downed = true
	Helpers.run(sim, 4.0)
	check(walt.repair == null, "and a downed one is not sent")
	g.world.free()


func test_someone_with_no_job_mends_only_a_section_under_half() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	var walt = _person(sim, "Walt")
	sim.jobs.unassign(walt)
	var seg = _wear(sim, 4, 0.6)
	check(sim.jobs.idle(walt), "Walt has no job, so he is idle")
	Helpers.run(sim, 3.0)
	check(walt.repair == null and is_equal_approx(seg.hp, seg.max_hp * 0.6), "nobody mends a section at 60% without a job for it")
	seg = _wear(sim, 4, 0.4)
	Helpers.run(sim, 3.0)
	check(walt.repair == seg, "but one at 40% is a chore for whoever is idle")
	g.world.free()


func test_a_person_with_a_job_of_their_own_does_not_do_chores() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	sim.jobs.assign(_person(sim, "Walt"), "garden")   # everyone has a job, and nobody a wall crew
	_wear(sim, 4, 0.3)
	Helpers.run(sim, 4.0)
	for p in sim.people:
		check(p.repair == null, "%s has a job: no chores" % p.first)
	g.world.free()


func test_the_crew_holds_the_posts_at_night_and_is_called_off_the_wall_at_the_bell() -> void:
	var g := _game(18.9)
	var sim = g.sim
	sim.stock.ammo = 100.0
	_wear(sim, 4, 0.3)
	var walt = _person(sim, "Walt")
	Helpers.run(sim, 1.5)
	check(walt.repair != null, "by day Walt is sent")
	Helpers.run(sim, 4.0)
	check(sim.bell_rung, "the bell has rung")
	check(walt.repair == null, "and he is called off the wall")
	sim.stock.scrap = 30.0
	Helpers.run(sim, 20.0)
	for p in sim.people:
		check(p.repair == null, "%s is not sent by night" % p.first)
	g.world.free()


func test_the_crew_is_called_back_from_the_wall_when_the_scrap_runs_out() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	_wear(sim, 4, 0.3)
	var walt = _person(sim, "Walt")
	Helpers.run(sim, 1.5)
	check(walt.repair != null, "Walt is sent to the worn section")
	sim.stock.scrap = 0.0
	Helpers.run(sim, 2.0)
	check(walt.repair == null, "with the scrap gone he is called back, not left hammering at nothing")
	Helpers.run(sim, 40.0)
	check(walt.repair == null, "and he is not sent again while there is none")
	check(Vector2(walt.x, walt.y).distance_to(sim.jobs.seat_pos(walt)) < 0.7, "he is back at his station")
	g.world.free()


func test_an_order_to_repair_still_waits_at_the_wall_for_the_scrap() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	var seg = _wear(sim, 4, 0.3)
	var ana = _person(sim, "Ana")
	sim.stock.scrap = 0.0
	sim.order_repair(ana, seg)
	Helpers.run(sim, 5.0)
	check(ana.repair == seg, "an order of the player's is kept until the wall is mended")
	g.world.free()


func test_a_new_job_calls_the_person_off_the_wall_the_crew_sent_them_to() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	_wear(sim, 4, 0.3)
	var walt = _person(sim, "Walt")
	Helpers.run(sim, 1.5)
	check(walt.repair != null, "Walt is sent")
	check(sim.jobs.assign(walt, "garden"), "he is given the beds")
	check(walt.repair == null, "and is off the wall at once")
	Helpers.run(sim, 3.0)
	check(walt.repair == null, "and not sent back: the wall crew is no longer his")
	sim.jobs.assign(walt, "builders")
	Helpers.run(sim, 1.5)
	check(walt.repair != null, "back on the crew he is sent again")
	sim.jobs.unassign(walt)
	check(walt.repair == null, "and with no job at all he is off the wall again")
	g.world.free()


func test_a_loaded_game_sends_the_wall_crew_at_the_same_moment_as_the_saved_one() -> void:
	var a := _game(9.0)
	var sim_a = a.sim
	sim_a.stock.ammo = 100.0
	_wear(sim_a, 4, 0.3)
	Helpers.run(sim_a, 0.37)    # part way through the second the crew is sent on
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := _game(9.0, 99)
	check(SaveGame.apply(b.sim, d), "the save loads")
	near(float(b.sim.tactics._t), float(sim_a.tactics._t), 1e-9, "the point the crew's second has reached is saved")
	Helpers.run(sim_a, 4.0)
	Helpers.run(b.sim, 4.0)
	var walt_a = _person(sim_a, "Walt")
	var walt_b = _person(b.sim, "Walt")
	near(walt_b.x, walt_a.x, 1e-6, "Walt is where he would have been (x)")
	near(walt_b.y, walt_a.y, 1e-6, "and (y)")
	a.world.free()
	b.world.free()


func test_a_new_job_does_not_cancel_a_repair_the_player_ordered_after_the_crews_own_ended() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	var seg4 = _wear(sim, 4, 0.3)
	var seg5 = _wear(sim, 5, 0.9)    # above the crew's threshold: the crew sends nobody to it
	var walt = _person(sim, "Walt")
	Helpers.run(sim, 1.5)
	check(walt.repair == seg4, "the crew sends Walt to the most worn section")
	seg4.hp = seg4.max_hp
	sim._segment_state(seg4)
	Helpers.run(sim, 8.0)    # he gets there, finds it whole, and the crew's trip is over
	check(walt.repair == null, "the crew's trip is over")
	sim.order_repair(walt, seg5)
	check(sim.jobs.assign(walt, "garden"), "he is given the beds")
	check(walt.repair == seg5, "the repair the player ordered stands: an order beats a job")
	g.world.free()


func test_an_order_to_repair_the_section_the_crew_had_sent_them_to_is_the_players_now() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	var seg = _wear(sim, 4, 0.3)
	var walt = _person(sim, "Walt")
	Helpers.run(sim, 1.5)
	check(walt.repair == seg, "the crew sends Walt")
	sim.order_repair(walt, seg)
	sim.jobs.assign(walt, "garden")
	check(walt.repair == seg, "the player's order for the same section is not undone by a new job")
	g.world.free()


func test_a_section_the_dead_were_mending_is_mended_again() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.stock.ammo = 100.0
	var seg = _wear(sim, 4, 0.3)
	var walt = _person(sim, "Walt")
	Helpers.run(sim, 1.5)
	check(walt.repair == seg, "Walt is mending it")
	walt.dead = true
	walt.turned = true
	var dez = _person(sim, "Dez")
	check(sim.jobs.assign(dez, "builders"), "Dez joins the wall crew")
	Helpers.run(sim, 3.0)
	check(dez.repair == seg, "and is sent to the section, not left to think it is taken")
	g.world.free()


func test_auto_repair_means_being_on_the_wall_crew() -> void:
	var g := _game(9.0)
	var sim = g.sim
	var walt = _person(sim, "Walt")
	var ana = _person(sim, "Ana")
	check(sim.tactics.auto_repair(walt), "Walt is on the wall crew from the start")
	for first in ["Ruth", "Dez", "Ana", "Marcus", "Hector"]:
		check(not sim.tactics.auto_repair(_person(sim, first)), "%s is not" % first)
	sim.tactics.toggle_auto(ana)
	check(sim.tactics.auto_repair(ana) and sim.jobs.job_of(ana) == "builders", "toggling it puts Ana on the crew")
	sim.tactics.toggle_auto(ana)
	check(not sim.tactics.auto_repair(ana) and sim.jobs.job_of(ana) == "", "and toggling again takes her off it")
	g.world.free()


func test_the_old_ids_of_the_two_orders_are_answered_by_the_jobs() -> void:
	var g := _game(9.0)
	var sim = g.sim
	var ana = _person(sim, "Ana")
	var sel := {"kind": "person", "ref": ana}
	check(sim.handle_gizmo("auto", sel), "the old standing order's id is taken")
	check(sim.tactics.auto_repair(ana), "it puts Ana on the wall crew")
	check(sim.handle_gizmo("auto", sel), "and again")
	check(not sim.tactics.auto_repair(ana) and sim.jobs.job_of(ana) == "", "it takes her off")
	check(sim.handle_gizmo("craft", sel), "the old worktable order's id is taken")
	eq(sim.jobs.job_of(ana), "bench", "it gives her the bench")
	check(not sim.handle_gizmo("auto", {"kind": "segment", "ref": sim.segments[0]}), "a wall section has no job")
	g.world.free()


# ---------------------------------------------------------------- the vegetable beds --

func test_a_gardener_grows_food_by_the_hour_at_the_garden_only() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var hector = _person(sim, "Hector")
	var rate: float = Supplies.GARDEN_FOOD_PER_HOUR
	var food: float = sim.stock.food
	Helpers.seat(sim, hector)
	Helpers.run(sim, 20.0)   # one game hour (08:00 to 09:00, between the meals)
	near(float(sim.stock.food) - food, rate, 0.01, "an hour of one gardener grows %.2f food" % rate)
	var h := _game(8.0)
	var s2 = h.sim
	var hector2 = _person(s2, "Hector")
	s2.jobs.unassign(hector2)
	var food2: float = s2.stock.food
	Helpers.run(s2, 20.0)
	near(float(s2.stock.food), food2, 0.0001, "with nobody on the beds nothing grows by the hour")
	var k := _game(8.0)
	var s3 = k.sim
	var dez = _person(s3, "Dez")
	var hector3 = _person(s3, "Hector")
	check(s3.jobs.assign(dez, "garden"), "a second gardener takes the other seat")
	Helpers.seat(s3, dez)
	Helpers.seat(s3, hector3)
	var food3: float = s3.stock.food
	Helpers.run(s3, 20.0)
	near(float(s3.stock.food) - food3, 2.0 * rate, 0.02, "two gardeners grow twice as much")
	g.world.free()
	h.world.free()
	k.world.free()


func test_the_beds_are_worked_only_once_the_gardener_is_there() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var hector = _person(sim, "Hector")
	hector.x = 40.0
	hector.y = 36.0
	var food: float = sim.stock.food
	Helpers.run(sim, 2.0)
	near(float(sim.stock.food), food, 0.0001, "nothing grows while he is on the walk")
	Helpers.run(sim, 10.0)
	check(Vector2(hector.x, hector.y).distance_to(sim.jobs.seat_pos(hector)) < 0.6, "he reaches the beds")
	check(float(sim.stock.food) > food, "and then it grows")
	g.world.free()


func test_a_day_in_the_garden_is_worth_what_the_beds_gave_when_they_paid_a_fixed_three() -> void:
	var days: Array = []
	var base := 0.0
	var rate := 0.0
	for gardeners in [[], ["Hector"], ["Hector", "Dez"]]:
		var g := _game(6.5)
		var sim = g.sim
		base = Supplies.GARDEN_BASE
		rate = Supplies.GARDEN_FOOD_PER_HOUR
		sim.jobs.clear()    # nobody else grows, makes or mends anything
		for first in gardeners:
			sim.jobs.assign(_person(sim, first), "garden")
		for first in gardeners:
			Helpers.seat(sim, _person(sim, first))
		var food: float = sim.stock.food
		Helpers.run(sim, 12.4 * 20.0)   # 06:30 to 18:54: the two meals (07:00 and 13:00) are in it
		days.append(float(sim.stock.food) - food)
		g.world.free()
	near(float(days[1]) - float(days[0]), rate * 12.4, 0.05, "one gardener's day (12.4 hours): %.2f" % (float(days[1]) - float(days[0])))
	near(float(days[2]) - float(days[1]), rate * 12.4, 0.05, "and the second one's")
	near(base + rate * 12.0, 3.0, 0.25, "the dawn share and about twelve hours of one gardener make the three food the beds gave")
	near(base + 2.0 * rate * 12.0, 5.4, 0.25, "and two gardeners five and a half")


func test_the_dawn_pays_the_unattended_share_only_if_someone_is_home() -> void:
	var g := _game(6.4)
	var sim = g.sim
	var base: float = Supplies.GARDEN_BASE
	var food: float = sim.stock.food
	sim.supplies.roll_dawn()
	near(float(sim.stock.food) - food, base, 1.0e-9, "the beds give their small share at dawn")
	for p in sim.people:
		p.away = {"kind": "test"}
	food = sim.stock.food
	sim.supplies.roll_dawn()
	near(float(sim.stock.food), food, 1.0e-9, "with everyone away it is not paid")
	g.world.free()


func test_a_gardener_who_is_ordered_away_stops_the_growing() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var hector = _person(sim, "Hector")
	Helpers.seat(sim, hector)
	sim.order_move(hector, hector.x, hector.y)
	var food: float = sim.stock.food
	Helpers.run(sim, 10.0)
	near(float(sim.stock.food), food, 0.0001, "an ordered Hector is not at work on the beds")
	sim.toggle_draft(hector)
	Helpers.run(sim, 10.0)
	check(float(sim.stock.food) > food, "and when he is let go he goes back to it")
	g.world.free()


# ------------------------------------------------------------------------ the infirmary --

## A patient who has been stabilised and carried to a bed, with no health yet.
func _patient(sim, first: String):
	var p = _person(sim, first)
	p.hp = 0.0
	sim.medical.on_downed(p, "bite")
	sim.medical.stabilise(p)
	return p


func test_patients_in_the_beds_heal_one_and_a_half_times_as_fast_while_the_infirmary_is_staffed() -> void:
	var gains: Array = []
	for staffed in [false, true]:
		var g := _game(9.0)
		var sim = g.sim
		var ana = _person(sim, "Ana")
		if staffed:
			Helpers.seat(sim, ana)
		else:
			sim.jobs.unassign(ana)
		var hector = _patient(sim, "Hector")
		check(hector.resting_bed != null, "Hector is in a bed")
		check(sim.jobs.working("infirmary").is_empty() != staffed, "the infirmary is %s" % ("staffed" if staffed else "not staffed"))
		Helpers.run(sim, 20.0)   # one game hour
		gains.append(hector.hp)
		g.world.free()
	near(gains[0], 10.0, 0.6, "alone, a patient heals 10 health an hour: %.1f" % gains[0])
	near(gains[1], 10.0 * Medical.INFIRMARY_HEAL_MULT, 0.9, "with someone on duty in the infirmary, %.1f times as fast: %.1f" % [Medical.INFIRMARY_HEAL_MULT, gains[1]])
	check(gains[1] > gains[0] * 1.4, "that is half as fast again")


func test_someone_lying_with_no_bed_gets_no_better_care() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.medical.beds = []
	Helpers.seat(sim, _person(sim, "Ana"))
	var hector = _patient(sim, "Hector")
	check(hector.resting_bed == null, "no bed")
	Helpers.run(sim, 20.0)
	near(hector.hp, 10.0, 0.6, "he heals at the plain rate")
	g.world.free()


func test_the_bonus_goes_when_the_infirmary_has_nobody_at_their_seat() -> void:
	var g := _game(9.0)
	var sim = g.sim
	var ana = _person(sim, "Ana")
	Helpers.seat(sim, ana)
	var hector = _patient(sim, "Hector")
	Helpers.run(sim, 10.0)    # half an hour on duty
	var first: float = hector.hp
	ana.x = 40.0
	ana.y = 40.0
	sim.order_move(ana, 40.0, 40.0)    # called away from her desk
	Helpers.run(sim, 10.0)
	near(hector.hp - first, 5.0, 0.4, "with the desk empty the next half hour is at the plain rate: %.1f" % (hector.hp - first))
	near(first, 7.5, 0.6, "the first half hour was half as fast again: %.1f" % first)
	g.world.free()


func test_the_infirmary_crew_is_preferred_when_a_healer_is_chosen() -> void:
	# Ruth and Walt (both Medicine 2) are the same distance from the patient; Ana is busy
	var picks: Array = []
	for crew in [false, true]:
		var g := _game(9.0)
		var sim = g.sim
		var hector = _person(sim, "Hector")
		hector.x = HALL.x
		hector.y = HALL.y
		var ruth = _person(sim, "Ruth")
		var walt = _person(sim, "Walt")
		ruth.x = HALL.x + 3.0
		ruth.y = HALL.y
		walt.x = HALL.x - 3.0
		walt.y = HALL.y
		ruth.goal_key = ""
		walt.goal_key = ""
		_busy(sim, ["Ruth", "Walt"])
		if crew:
			check(sim.jobs.assign(walt, "infirmary"), "Walt joins the infirmary crew")
		sim.medical.add_wound(hector, "scratch")
		Helpers.run(sim, 0.1)
		check(sim.medical.jobs.size() == 1, "one job")
		picks.append(String(sim.medical.jobs[0].healer.id) if not sim.medical.jobs.is_empty() else "")
		g.world.free()
	eq(picks[0], "ruth", "level, the first of the crew goes")
	eq(picks[1], "walt", "with Walt on the infirmary crew he goes instead")


func test_the_preference_is_small_next_to_skill() -> void:
	# Ana (Medicine 10) is on the bench, twelve tiles from the patient; Walt, on the infirmary crew, stands
	# three tiles from him with Medicine 2: the better healer is still worth the walk
	var g := _game(9.0)
	var sim = g.sim
	var hector = _person(sim, "Hector")
	hector.x = HALL.x
	hector.y = HALL.y
	var ana = _person(sim, "Ana")
	var walt = _person(sim, "Walt")
	sim.jobs.assign(ana, "bench")
	sim.jobs.assign(walt, "infirmary")
	ana.x = HALL.x + 12.0
	ana.y = HALL.y
	walt.x = HALL.x - 3.0
	walt.y = HALL.y
	ana.goal_key = ""
	walt.goal_key = ""
	_busy(sim, ["Ana", "Walt"])
	sim.medical.add_wound(hector, "scratch")
	Helpers.run(sim, 0.1)
	check(sim.medical.jobs.size() == 1, "one job")
	eq(String(sim.medical.jobs[0].healer.id), "ana", "Ana goes all the same")
	g.world.free()


# ---------------------------------------------------------------------------- the radio --

## A card of the shape events.json gives, with a choice (so it waits for an answer).
func _news() -> Dictionary:
	return Storyteller.normalise({"id": "news", "kind": "choice", "weight": 1.0, "title": "News", "text": "Something on the radio.",
		"choices": [{"label": "Yes", "hint": ""}, {"label": "No", "hint": ""}], "bot": 1})


## The day before the radio hour, the storyteller on and a seed that draws the card.
func _radio_game(day: int = 5, hour: float = 11.9) -> Dictionary:
	var g := _game(hour)
	var sim = g.sim
	sim.storyteller.enabled = true
	sim.day = day
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.supplies.sources_day = day
	sim.storyteller.cards = [_news()]
	var found := false
	for s in range(1, 200):
		sim.run_seed = s
		if not sim.storyteller.draw(day).is_empty():
			found = true
			break
	check(found, "a seed gives a card on day %d" % day)
	return g


func test_the_speaker_is_whoever_works_the_radio_desk() -> void:
	var g := _game(9.0)
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var walt = _person(sim, "Walt")
	eq(sim.storyteller.speaker(), ruth, "Ruth sits at the desk to begin with")
	sim.jobs.unassign(ruth)
	eq(sim.storyteller.speaker(), null, "with nobody assigned there is nobody at the radio")
	Helpers.seat(sim, walt, "radio")
	eq(sim.storyteller.speaker(), walt, "and Walt, once he sits there, is who speaks")
	ruth.x = sim.jobs.seat_pos(walt).x
	ruth.y = sim.jobs.seat_pos(walt).y
	eq(sim.storyteller.speaker(), walt, "being at the desk is not enough without the job")
	walt.downed = true
	eq(sim.storyteller.speaker(), null, "a downed operator does not speak")
	walt.downed = false
	sim.order_move(walt, walt.x, walt.y)
	eq(sim.storyteller.speaker(), null, "nor one who is under an order")
	g.world.free()


func test_the_stragglers_card_names_whoever_is_on_watch() -> void:
	var g := _game(12.0)
	var sim = g.sim
	sim.storyteller.enabled = true
	sim.storyteller.force("stragglers")
	check(String(sim.storyteller.pending().text).contains("Marcus"), "Marcus has the lookout post to begin with and is the one who speaks")
	g.world.free()
	var h := _game(12.0)
	var s2 = h.sim
	s2.storyteller.enabled = true
	s2.jobs.unassign(_person(s2, "Marcus"))
	s2.jobs.assign(_person(s2, "Walt"), "watch")
	s2.storyteller.force("stragglers")
	var text := String(s2.storyteller.pending().text)
	check(text.contains("Walt") and not text.contains("Marcus"), "with Walt on watch it is Walt who sees them coming: '%s'" % text)
	h.world.free()
	var k := _game(12.0)
	var s3 = k.sim
	s3.storyteller.enabled = true
	s3.jobs.unassign(_person(s3, "Marcus"))
	s3.storyteller.force("stragglers")
	check(String(s3.storyteller.pending().text).contains("The lookout"), "with nobody on watch it is only the lookout")
	k.world.free()


func test_the_workshop_remembers_that_it_has_told_the_crew_it_is_idle() -> void:
	var a := _game(9.0)
	var sim_a = a.sim
	sim_a.stock.scrap = 3.0
	sim_a.stock.ammo = 100.0
	Helpers.seat(sim_a, _person(sim_a, "Dez"), "bench")
	Helpers.run(sim_a, 2.0)
	check(sim_a.alerts.has("workshop-idle"), "with the scrap down to the reserve the crew is told")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := _game(9.0, 99)
	check(SaveGame.apply(b.sim, d), "the save loads")
	check(bool(b.sim.workshop._told_idle), "and it is not told again after a load")
	a.world.free()
	b.world.free()


func test_the_noon_call_comes_from_the_person_at_the_desk() -> void:
	var g := _radio_game()
	var sim = g.sim
	sim.jobs.unassign(_person(sim, "Ruth"))
	var walt = _person(sim, "Walt")
	Helpers.seat(sim, walt, "radio")
	check(sim.storyteller.pending().is_empty(), "nothing before the hour")
	Helpers.run(sim, 5.0)
	var card: Dictionary = sim.storyteller.pending()
	check(not card.is_empty(), "at noon the radio brings a card")
	eq(card.speaker, "Walt", "from the person at the desk")
	eq(card.speaker_id, "walt", "who the card names by id")
	check(String(sim.alerts.get("story", {}).get("text", "")).begins_with("Walt"), "and the alert says so: '%s'" % String(sim.alerts.get("story", {}).get("text", "")))
	g.world.free()


func test_with_nobody_at_the_desk_at_noon_there_is_no_card_that_day() -> void:
	var g := _radio_game()
	var sim = g.sim
	sim.jobs.unassign(_person(sim, "Ruth"))
	Helpers.run(sim, 5.0)
	check(sim.storyteller.pending().is_empty(), "radio silence")
	eq(sim.storyteller.radio_day, 5, "and the day's radio hour is spent all the same")
	Helpers.run(sim, 60.0)
	check(sim.storyteller.pending().is_empty(), "nobody sits down later and brings it")
	g.world.free()


func test_the_operator_must_be_at_the_desk_and_not_on_the_way() -> void:
	var g := _radio_game()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	ruth.x -= 8.0    # eight tiles away: she is still walking back at noon
	ruth.goal_key = ""
	Helpers.run(sim, 5.0)
	check(sim.storyteller.pending().is_empty(), "Ruth on her way to the desk brings no card")
	var h := _radio_game()
	Helpers.run(h.sim, 5.0)
	check(not h.sim.storyteller.pending().is_empty(), "and Ruth at the desk does")
	eq(h.sim.storyteller.pending().speaker, "Ruth", "in her own words")
	g.world.free()
	h.world.free()


# ------------------------------------------------------------------- the lookout post --

func _at_hour(sim, hour: float) -> void:
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.events.clear()


func test_the_forecast_is_given_by_whoever_is_on_watch() -> void:
	var g := _game(16.9)
	var sim = g.sim
	eq(sim.tactics.lookout(), _person(sim, "Marcus"), "Marcus keeps watch to begin with")
	Helpers.run(sim, 1.0)
	check(not sim.tactics.forecast().given, "nothing before 17:00")
	Helpers.run(sim, 20.0)
	var f: Dictionary = sim.tactics.forecast()
	check(f.given, "the forecast is given at five")
	eq(f.who, "Marcus", "by the person on watch")
	check(sim.alerts.has("forecast") and String(sim.alerts.forecast.text) != "No forecast", "an alert carries it")
	g.world.free()
	var h := _game(16.9)
	var s2 = h.sim
	var marcus = _person(s2, "Marcus")
	var walt = _person(s2, "Walt")
	s2.jobs.unassign(marcus)
	Helpers.seat(s2, walt, "watch")
	eq(s2.tactics.lookout(), walt, "with Walt on the lookout post he is the lookout")
	Helpers.run(s2, 21.0)
	var f2: Dictionary = s2.tactics.forecast()
	check(f2.given, "the forecast is given")
	eq(f2.who, "Walt", "and it is Walt who reports")
	var said := false
	for e in s2.events:
		if e.type == "banner" and String(e.text).contains("Walt"):
			said = true
	check(said, "in a banner with his name")
	h.world.free()


func test_with_nobody_on_watch_at_five_there_is_no_forecast() -> void:
	var g := _game(16.9)
	var sim = g.sim
	sim.jobs.unassign(_person(sim, "Marcus"))
	var told := ""
	for i in 12 * 30:
		sim.update(1.0 / 30.0)
		if sim.alerts.has("forecast"):
			told = String(sim.alerts["forecast"].text)
			break
	check(not sim.tactics.forecast().given, "none")
	eq(told, "No forecast", "and the crew is told that nobody is watching")
	g.world.free()


func test_a_lookout_still_on_the_way_to_the_post_at_five_gives_no_forecast() -> void:
	var g := _game(16.95)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	marcus.x = 30.0    # on the north walkway, eleven tiles from the post; five o'clock is a second off
	marcus.y = 18.8
	marcus.goal_key = ""
	Helpers.run(sim, 5.0)
	check(not sim.tactics.forecast().given, "he is not at the post at five")
	check(sim.alerts.has("forecast") and sim.alerts.forecast.text == "No forecast", "so the crew is told there is none")
	g.world.free()


func test_the_forecast_stays_up_all_night_whoever_gave_it() -> void:
	var g := _game(16.95)
	var sim = g.sim
	Helpers.run(sim, 5.0)
	check(sim.tactics.forecast().given, "given at five")
	var marcus = _person(sim, "Marcus")
	sim.order_move(marcus, marcus.x + 5.0, marcus.y)    # he leaves the post
	_at_hour(sim, 23.0)
	var f: Dictionary = sim.tactics.forecast()
	check(f.given, "at night, with nobody working the post, it is still the night's forecast")
	eq(f.who, "Marcus", "and still his")
	_at_hour(sim, 3.0)
	check(sim.tactics.forecast().given, "at three in the morning too")
	g.world.free()


func test_a_save_keeps_who_gave_the_forecast() -> void:
	var a := _game(16.95)
	var sim_a = a.sim
	sim_a.jobs.unassign(_person(sim_a, "Marcus"))
	Helpers.seat(sim_a, _person(sim_a, "Walt"), "watch")
	Helpers.run(sim_a, 5.0)
	eq(sim_a.tactics.forecast().who, "Walt", "Walt gave it")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := Helpers.make(99, 0)
	check(SaveGame.apply(b.sim, d), "it applies")
	check(b.sim.tactics.forecast().given, "the forecast is still given after a load")
	eq(b.sim.tactics.forecast().who, "Walt", "and it is still Walt's")
	a.world.free()
	b.world.free()


func test_an_old_save_without_the_reporter_still_has_its_forecast() -> void:
	var a := _game(16.95)
	var sim_a = a.sim
	Helpers.run(sim_a, 5.0)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	d.modules.tactics.erase("forecast_who")
	d.modules.tactics.erase("auto_jobs")
	d.modules.tactics["auto"] = {"dez": true, "hector": true}
	d.modules.workshop = {"crafters": {"dez": {"hammer": 0.0, "scrap": 0.0, "since": 0.0}}}
	var b := Helpers.make(98, 1)
	check(SaveGame.apply(b.sim, d), "it applies, the old workshop and standing orders ignored")
	check(b.sim.tactics.forecast().given, "the forecast is still there")
	eq(b.sim.tactics.forecast().who, "Marcus", "told by the lookout, as it used to be")
	check(not b.sim.tactics.auto_repair(_person(b.sim, "Dez")), "Dez's old standing order is not a job")
	check(b.sim.tactics.auto_repair(_person(b.sim, "Walt")), "Walt is on the wall crew")
	a.world.free()
	b.world.free()
