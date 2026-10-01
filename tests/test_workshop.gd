extends "res://tests/case.gd"
## The workshop: by day a person at the yard's worktable turns scrap into ammo.
## Ammo is what runs out first in a long run, and scrap is what the walls and the
## bench both eat.

const Helpers := preload("res://tests/helpers.gd")
const Workshop := preload("res://scripts/sim/workshop.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## A quiet game at `hour` with the nights off and `scrap` in the stock.
func _day(hour: float = 9.0, scrap: float = 40.0, ammo: float = 100.0) -> Dictionary:
	var g := Helpers.make(41, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.stock.scrap = scrap
	sim.stock.ammo = ammo
	sim.events.clear()
	return g


## Puts someone at the bench, so no time goes on the walk.
func _at_the_bench(sim, p) -> void:
	var b: Vector2 = sim.workshop.bench()
	p.x = b.x
	p.y = b.y


func test_the_bench_is_somewhere_a_person_can_stand() -> void:
	var g := _day()
	var sim = g.sim
	var b: Vector2 = sim.workshop.bench()
	check(not sim.world.is_solid(sim.world.solid_p, b.x, b.y), "the bench's spot is open ground: %s" % str(b))
	check(not sim.path_p.find(sim.world.solid_p, 39.0, 32.0, b.x, b.y).is_empty(), "and there is a way to it from the yard")
	g.world.free()


func test_a_person_at_the_bench_turns_scrap_into_ammo_at_the_stated_rate() -> void:
	var g := _day(9.0, 40.0, 100.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	_at_the_bench(sim, dez)
	check(sim.workshop.order_craft(dez), "the order is taken")
	check(sim.workshop.crafting(dez), "and he is on it")
	Helpers.run(sim, 20.0)   # one game hour
	var rate: float = sim.workshop.scrap_per_hour(dez)
	var tinkerer := Helpers.trait_effect("tinkerer", "craft")
	near(rate, (2.0 + 0.5 * float(dez.def.skills.Building)) * tinkerer, 0.0001, "an hour of Dez's work is 2 + Building/2 scrap, and a Tinkerer (Dez) gets through %d%% more" % roundi((tinkerer - 1.0) * 100.0))
	near(40.0 - float(sim.stock.scrap), rate, 0.35, "he used that much scrap in an hour: %.2f" % (40.0 - float(sim.stock.scrap)))
	near(float(sim.stock.ammo) - 100.0, rate * Workshop.AMMO_PER_SCRAP, 3.0, "and made %d ammo from each: %.1f" % [Workshop.AMMO_PER_SCRAP, float(sim.stock.ammo) - 100.0])
	eq(dez.activity, "Making ammo", "the card says what he is doing")
	g.world.free()


func test_the_slower_hands_make_less() -> void:
	var g := _day(9.0, 40.0, 100.0)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	_at_the_bench(sim, marcus)
	sim.workshop.order_craft(marcus)
	Helpers.run(sim, 20.0)
	near(40.0 - float(sim.stock.scrap), sim.workshop.scrap_per_hour(marcus), 0.35, "Marcus (Building 1) uses about 2.5 scrap an hour")
	check(sim.workshop.scrap_per_hour(marcus) < sim.workshop.scrap_per_hour(_person(sim, "Dez")), "slower than Dez")
	g.world.free()


func test_a_hungry_person_works_more_slowly() -> void:
	var g := _day(9.0, 40.0, 100.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	dez.hunger_h = 20.0   # hungry: works at 0.8
	_at_the_bench(sim, dez)
	sim.workshop.order_craft(dez)
	Helpers.run(sim, 20.0)
	near(40.0 - float(sim.stock.scrap), sim.workshop.scrap_per_hour(dez) * 0.8, 0.4, "a hungry person gets through 0.8 of the scrap")
	g.world.free()


func test_they_walk_to_the_bench_first_and_work_only_there() -> void:
	var g := _day(9.0, 40.0, 100.0)
	var sim = g.sim
	var hector = _person(sim, "Hector")
	hector.x = 53.5
	hector.y = 31.5
	sim.workshop.order_craft(hector)
	Helpers.run(sim, 0.5)
	near(float(sim.stock.scrap), 40.0, 0.001, "nothing is made on the walk")
	Helpers.run(sim, 10.0)
	check(Vector2(hector.x, hector.y).distance_to(sim.workshop.bench()) < 0.4, "he gets to the bench")
	check(float(sim.stock.scrap) < 40.0, "and then it is made")
	g.world.free()


func test_scrap_is_kept_back_for_the_walls() -> void:
	var g := _day(9.0, 8.0, 100.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	_at_the_bench(sim, dez)
	sim.workshop.order_craft(dez)
	var told := false
	for i in 40 * 30:
		sim.update(1.0 / 30.0)
		if sim.alerts.has("workshop-idle"):
			told = true
		if not sim.workshop.crafting(dez):
			break
	near(float(sim.stock.scrap), Workshop.RESERVE_SCRAP, 0.01, "the bench stops with the reserve left")
	check(not sim.workshop.crafting(dez), "he is off the order")
	check(told, "and the crew is told the bench is idle")
	near(float(sim.stock.ammo), 100.0 + (8.0 - Workshop.RESERVE_SCRAP) * Workshop.AMMO_PER_SCRAP, 0.01, "every spare scrap became ammo")
	g.world.free()


func test_the_stock_never_goes_below_nothing() -> void:
	var g := _day(9.0, 0.2, 5.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	_at_the_bench(sim, dez)
	check(not sim.workshop.order_craft(dez), "with next to no scrap it is refused")
	eq(sim.workshop.why_not_craft(dez), "there is no scrap to spare", "and says why")
	Helpers.run(sim, 10.0)
	check(float(sim.stock.scrap) >= 0.0 and float(sim.stock.ammo) >= 5.0, "nothing went negative")
	g.world.free()


func test_the_bell_calls_them_off_the_bench() -> void:
	var g := _day(18.9, 40.0, 100.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	_at_the_bench(sim, dez)
	sim.workshop.order_craft(dez)
	Helpers.run(sim, 2.0)
	check(sim.workshop.crafting(dez), "still at it before the bell")
	Helpers.run(sim, 8.0)
	check(sim.bell_rung, "the bell has rung")
	check(not sim.workshop.crafting(dez), "and he is off the order")
	var after: float = sim.stock.scrap
	Helpers.run(sim, 5.0)
	near(float(sim.stock.scrap), after, 0.0001, "nothing is made at night")
	g.world.free()


func test_any_other_order_ends_the_job() -> void:
	var g := _day()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	_at_the_bench(sim, dez)
	sim.workshop.order_craft(dez)
	check(sim.order_move(dez, 40.0, 33.0), "a move order")
	check(not sim.workshop.crafting(dez), "ends it")
	sim.workshop.order_craft(dez)
	sim.order_post(dez)
	check(not sim.workshop.crafting(dez), "so does a post")
	sim.workshop.order_craft(dez)
	sim.toggle_draft(dez)
	check(not sim.workshop.crafting(dez), "and a draft")
	sim.toggle_draft(dez)
	var seg = sim.segments[4]
	sim._damage_segment(seg, 100.0)
	sim.workshop.order_craft(dez)
	sim.order_repair(dez, seg)
	check(not sim.workshop.crafting(dez), "and a repair order")
	sim.workshop.order_craft(dez)
	check(dez.repair == null and not dez.drafted and dez.order == null, "taking the bench clears the other orders")
	g.world.free()


func test_the_bench_is_refused_for_the_wrong_people_and_hours() -> void:
	var g := _day(9.0, 40.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var ana = _person(sim, "Ana")
	var hector = _person(sim, "Hector")
	var walt = _person(sim, "Walt")
	eq(sim.workshop.why_not_craft(dez), "", "by day with scrap, anyone able may")
	ana.downed = true
	eq(sim.workshop.why_not_craft(ana), "they are down", "not the downed")
	check(not sim.workshop.order_craft(ana), "and the order is refused")
	hector.away = {"kind": "party"}
	eq(sim.workshop.why_not_craft(hector), "they are away", "not the away")
	walt.dead = true
	eq(sim.workshop.why_not_craft(walt), "they are gone", "not the dead")
	sim.minutes = 22.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = true
	eq(sim.workshop.why_not_craft(dez), "it is night: everyone is at their post", "not at night")
	g.world.free()


func test_the_gizmo_toggles_the_job_for_a_person_only() -> void:
	var g := _day()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	check(sim.handle_gizmo("craft", {"kind": "person", "ref": dez}), "the order button is taken")
	check(sim.workshop.crafting(dez), "he is on it")
	check(sim.handle_gizmo("craft", {"kind": "person", "ref": dez}), "pressed again")
	check(not sim.workshop.crafting(dez), "he is off it")
	check(not sim.handle_gizmo("craft", {"kind": "segment", "ref": sim.segments[0]}), "a wall section cannot make ammo")
	sim.stock.scrap = 0.0
	check(not sim.handle_gizmo("craft", {"kind": "person", "ref": dez}), "and with no scrap the button is refused")
	g.world.free()


func test_a_mark_shows_while_they_work() -> void:
	var g := _day()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	_at_the_bench(sim, dez)
	var plain := 0
	for m in sim.status_of(dez):
		if m.icon == "ammo":
			plain += 1
	eq(plain, 0, "no mark when idle")
	sim.workshop.order_craft(dez)
	Helpers.run(sim, 2.0)
	var marks := []
	for m in sim.status_of(dez):
		marks.append(m.icon)
	check(marks.has("ammo"), "the ammo mark while working: %s" % str(marks))
	g.world.free()


func test_the_work_is_heard() -> void:
	var g := _day()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	_at_the_bench(sim, dez)
	sim.workshop.order_craft(dez)
	var hammers := 0
	var crafts := 0
	for i in 5 * 30:
		sim.update(1.0 / 30.0)
		for e in sim.events:
			if e.type == "hammer":
				hammers += 1
			elif e.type == "craft":
				crafts += 1
		sim.events.clear()
	check(hammers >= 3, "the hammer rings at the bench: %d" % hammers)
	check(crafts >= 1, "and a craft event carries what was made: %d" % crafts)
	g.world.free()


func test_auto_repair_does_not_pull_a_worker_off_the_bench() -> void:
	var g := _day(9.0, 40.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	check(sim.tactics.auto_repair(dez), "Dez starts with auto-repair on")
	sim._damage_segment(sim.segments[4], 60.0)
	_at_the_bench(sim, dez)
	sim.workshop.order_craft(dez)
	Helpers.run(sim, 5.0)
	check(sim.workshop.crafting(dez) and dez.repair == null, "he stays at the bench while a wall is worn")
	g.world.free()


func test_a_save_keeps_the_workers_and_their_progress() -> void:
	var a := _day(9.0, 40.0, 100.0)
	var sim_a = a.sim
	var dez = _person(sim_a, "Dez")
	_at_the_bench(sim_a, dez)
	sim_a.workshop.order_craft(dez)
	Helpers.run(sim_a, 3.0)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := Helpers.make(99, 0)
	check(SaveGame.apply(b.sim, d), "it applies")
	var dez_b = _person(b.sim, "Dez")
	check(b.sim.workshop.crafting(dez_b), "he is still on the job after a load")
	Helpers.run(sim_a, 6.0)
	Helpers.run(b.sim, 6.0)
	near(float(b.sim.stock.scrap), float(sim_a.stock.scrap), 0.01, "and the loaded game goes on the same way")
	a.world.free()
	b.world.free()


func test_the_game_data_names_the_worktable() -> void:
	var g := _day()
	var sim = g.sim
	check(sim.d.has("workshop"), "map.json has a workshop entry")
	var w: Dictionary = sim.d.workshop
	check(w.has("x") and w.has("y") and String(w.get("what", "")) != "", "with a place and a few words")
	var table := {}
	for o in sim.d.objects:
		if o.kind == "worktable" and absf(float(o.cx) - 43.9) < 0.5:
			table = o
	check(not table.is_empty(), "the yard's worktable is where the entry says")
	check(absf(float(w.y) - float(table.cy)) < 2.5, "and the bench's spot is next to it")
	g.world.free()
