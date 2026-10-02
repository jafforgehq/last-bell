extends "res://tests/case.gd"
## What the standing buildings do to the modules that own the thing (round 6): the greenhouse's beds pay
## more food at dawn, the workshop quickens the bench and gets more ammo out of a scrap, the bunk house gives
## the hurt four beds and the crew a steadier mood, the floodlights lengthen the guns' reach by night and
## stop a blackout costing aim, the watchtower lengthens the reach of those near it, the radio mast tilts the
## radio's draw. Everything is read through `sim.build` (`bonus`, `factor`, `bed_spots`, `reach_bonus_at`,
## `version`); the buildings themselves (plots, orders, construction, seats, the salvage station, footprints,
## saves) are tested in test_build.gd. Each effect is tested with its building standing and again with nothing
## built: then every number is exactly what it was before there were buildings. The numbers a test quotes are
## read from assets/data/buildings.json (`_fx`), so a retune of the data does not break it.

const Helpers := preload("res://tests/helpers.gd")
const Kit := preload("res://tests/hud_kit.gd")
const Supplies := preload("res://scripts/sim/supplies.gd")
const Workshop := preload("res://scripts/sim/workshop.gd")
const Medical := preload("res://scripts/sim/medical.gd")
const Morale := preload("res://scripts/sim/morale.gd")
const Storyteller := preload("res://scripts/sim/storyteller.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## Sets the clock to `hour` with the phase and the bell to match.
func _clock(sim, hour: float) -> void:
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.5


## A quiet game at `hour`: no waves, no dead about, the storyteller off, scrap in the stock, and the bench
## and the beds idle.
func _game(hour: float = 9.0, seed_value: int = 71) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	_clock(sim, hour)
	sim.stock.scrap = 100.0
	Helpers.idle_stores(sim)
	sim.events.clear()
	return g


## Puts a building on a plot at once, as if it had been built.
func _stand(sim, plot_id: String, building_id: String) -> void:
	var pl: Dictionary = sim.build.plot(plot_id)
	pl.building = building_id
	sim.build.version += 1


## Builds a building the way the game does: the scrap is paid, the site goes up and is finished at once (its
## footprint shut, the crew told).
func _build_now(sim, plot_id: String, building_id: String) -> void:
	sim.stock.scrap = float(sim.stock.scrap) + float(sim.build.building(building_id).scrap)
	check(sim.build.order(plot_id, building_id), "the %s is ordered on %s" % [building_id, plot_id])
	sim.build._finish(sim.build.plot(plot_id))


## A number a building's data gives (so a retune does not break a test).
func _fx(sim, building_id: String, key: String) -> float:
	return float(sim.build.building(building_id).effects[key])


## A person who was downed, stabilised and carried to a bed, with no health yet.
func _patient(sim, first: String):
	var p = _person(sim, first)
	p.hp = 0.0
	sim.medical.on_downed(p, "bite")
	sim.medical.stabilise(p)
	return p


func _by_id(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## A bed (or any place that may be missing) as a point: a missing one is far away, so that a comparison with it
## fails cleanly.
func _at(v) -> Vector2:
	return Vector2(v) if v != null else Vector2(-1.0e6, -1.0e6)


func _near_spot(at: Vector2, spots: Array) -> bool:
	for s in spots:
		if Vector2(s).distance_to(at) < 0.05:
			return true
	return false


# ----------------------------------------------------------------- the greenhouse --

func test_the_greenhouse_beds_pay_a_little_more_each_dawn() -> void:
	var g := _game(6.4)
	var sim = g.sim
	_stand(sim, "east_lot", "greenhouse")
	var food: float = sim.stock.food
	sim.supplies.roll_dawn()
	near(float(sim.stock.food) - food, Supplies.GARDEN_BASE + _fx(sim, "greenhouse", "garden_base"), 1.0e-9, "the beds' own share and the greenhouse's")
	for p in sim.people:
		p.away = {"kind": "test"}
	food = sim.stock.food
	sim.supplies.roll_dawn()
	eq(float(sim.stock.food), food, "with nobody home to tend them the beds pay nothing, greenhouse or not")
	g.world.free()


func test_the_greenhouse_pays_when_the_day_turns_over_in_a_real_run() -> void:
	var g := _game(6.45)
	var sim = g.sim
	_stand(sim, "east_lot", "greenhouse")
	var food: float = sim.stock.food
	Helpers.run(sim, 4.0)    # across 06:30, twelve game minutes
	eq(sim.day, 2, "the day turned over")
	near(float(sim.stock.food) - food, Supplies.GARDEN_BASE + _fx(sim, "greenhouse", "garden_base"), 1.0e-9, "and the dawn paid the beds' share and the greenhouse's, once")
	g.world.free()


func test_with_no_greenhouse_the_dawn_pays_exactly_what_it_did() -> void:
	var g := _game(6.4)
	var sim = g.sim
	var food: float = sim.stock.food
	sim.supplies.roll_dawn()
	eq(float(sim.stock.food), food + Supplies.GARDEN_BASE, "the unattended share and nothing else")
	g.world.free()


# ------------------------------------------------------------------- the workshop --

## An hour (20 seconds) of Dez at the bench with 100 scrap and 100 ammo: what it took and what it made.
func _bench_hour(with_workshop: bool) -> Dictionary:
	var g := _game()
	var sim = g.sim
	if with_workshop:
		_stand(sim, "south_lot", "workshop")
	var dez = _person(sim, "Dez")
	check(Helpers.seat(sim, dez, "bench"), "Dez is at the bench")
	sim.stock.ammo = 100.0
	var scrap: float = sim.stock.scrap
	Helpers.run(sim, 20.0)
	var out := {"scrap": scrap - float(sim.stock.scrap), "ammo": float(sim.stock.ammo) - 100.0, "rate": float(sim.workshop.scrap_per_hour(dez))}
	g.world.free()
	return out


func test_the_workshop_quickens_the_bench() -> void:
	var plain := _bench_hour(false)
	var quick := _bench_hour(true)
	var g := _game()
	var mult := _fx(g.sim, "workshop", "craft_mult")
	g.world.free()
	near(float(quick.rate), float(plain.rate) * mult, 1.0e-9, "an hour at the bench is worth more scrap")
	check(float(plain.scrap) > 1.0, "the plain bench worked through scrap: %.2f" % float(plain.scrap))
	near(float(quick.scrap) / float(plain.scrap), mult, 0.01, "and in play it used that much more in the hour: %.2f against %.2f" % [float(quick.scrap), float(plain.scrap)])


func test_the_workshop_makes_more_ammo_from_a_scrap_and_stops_at_the_target() -> void:
	var g := _game()
	var sim = g.sim
	_stand(sim, "south_lot", "workshop")
	var per: float = Workshop.AMMO_PER_SCRAP + _fx(sim, "workshop", "ammo_per_scrap")
	near(float(sim.workshop.ammo_per_scrap()), per, 1.0e-9, "the module says what a scrap makes now")
	check(per > Workshop.AMMO_PER_SCRAP, "more than before")
	var dez = _person(sim, "Dez")
	Helpers.seat(sim, dez, "bench")
	sim.stock.ammo = sim.workshop.target() - 60.0
	var scrap: float = sim.stock.scrap
	sim.events.clear()
	Helpers.run(sim, 20.0)
	near(float(sim.stock.ammo), sim.workshop.target(), 1.0e-6, "it makes up to the target and no more")
	near(scrap - float(sim.stock.scrap), 60.0 / per, 1.0e-6, "from the scrap the better rate asks for (not %.2f)" % (60.0 / Workshop.AMMO_PER_SCRAP))
	var crafted := 0
	for e in sim.events:
		if e.type == "craft":
			crafted += 1
			near(float(e.ammo), float(e.scrap) * per, 1.0e-6, "the number floating over the bench says what was made")
	check(crafted >= 2, "there were craft events: %d" % crafted)
	g.world.free()


func test_the_workshops_ammo_per_scrap_is_what_a_scrap_makes_in_play() -> void:
	var plain := _bench_hour(false)
	var quick := _bench_hour(true)
	near(float(plain.ammo) / float(plain.scrap), Workshop.AMMO_PER_SCRAP, 1.0e-6, "a scrap makes eight rounds with nothing built")
	var g := _game()
	var per: float = Workshop.AMMO_PER_SCRAP + _fx(g.sim, "workshop", "ammo_per_scrap")
	g.world.free()
	near(float(quick.ammo) / float(quick.scrap), per, 1.0e-6, "and one more with the workshop")


func test_the_workbench_tooltip_follows_the_workshop() -> void:
	var ctx := Kit.build()
	var sim = ctx.sim
	var ana = Kit.person(ctx, "ana")
	Kit.select(ctx, ana)
	Kit.update(ctx)
	var before: String = Kit.gizmo(ctx, "job_bench").tooltip_text.split("\n")[2]
	check(before.begins_with("1 scrap makes %d ammo." % int(Workshop.AMMO_PER_SCRAP)), "nothing built: '%s'" % before)
	_stand(sim, "south_lot", "workshop")
	Kit.update(ctx)
	var per: float = Workshop.AMMO_PER_SCRAP + _fx(sim, "workshop", "ammo_per_scrap")
	var hourly: float = sim.workshop.scrap_per_hour(ana) * sim.perf(ana) * per
	eq(Kit.gizmo(ctx, "job_bench").tooltip_text.split("\n")[2], "1 scrap makes %s ammo. Ana makes about %s ammo an hour." % [ctx.hud._num(per), ctx.hud._num(hourly)], "with the workshop the words say what it now makes")
	Kit.free_all(ctx)


func test_with_no_workshop_the_bench_is_exactly_what_it_was() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	eq(float(sim.workshop.scrap_per_hour(dez)), (Workshop.BASE_SCRAP_PER_HOUR + Workshop.BUILDING_SHARE * float(dez.skills.Building)) * sim.traits.mult(dez, "craft"), "the scrap an hour is the old formula")
	eq(float(sim.workshop.ammo_per_scrap()), Workshop.AMMO_PER_SCRAP, "a scrap makes what it made")
	g.world.free()


# ------------------------------------------------------------------- the bunk house --

func test_the_bunk_house_adds_four_beds_after_the_others() -> void:
	var g := _game()
	var sim = g.sim
	var before: Array = sim.medical.beds.duplicate()
	eq(before.size(), 6, "two cots and four bunks to begin with")
	_stand(sim, "south_east_corner", "bunk_house")
	Helpers.run(sim, 0.1)
	var beds: Array = sim.medical.beds
	eq(beds.size(), 6 + int(_fx(sim, "bunk_house", "beds")), "four more")
	for i in before.size():
		eq(beds[i], before[i], "the old beds are first, as they were (%d)" % i)
	var spots: Array = sim.build.bed_spots()
	eq(spots.size(), 4, "the bunk house has four spots")
	for i in spots.size():
		eq(String(beds[6 + i].kind), "bunk house", "bed %d is a bunk house bed" % i)
		eq(Vector2(beds[6 + i].pos), Vector2(spots[i]), "at the spot the building gives")
	_stand(sim, "north_east_lot", "bunk_house")
	Helpers.run(sim, 0.1)
	eq(sim.medical.beds.size(), 14, "a second bunk house has four more")
	sim.build.demolish("south_east_corner")
	Helpers.run(sim, 0.1)
	eq(sim.medical.beds.size(), 10, "and when one comes down its beds go")
	sim.build.demolish("north_east_lot")
	Helpers.run(sim, 0.1)
	eq(sim.medical.beds, before, "with both gone the beds are the old six")
	g.world.free()


func test_a_patient_goes_to_the_bunk_house_when_the_other_beds_are_full() -> void:
	var g := _game()
	var sim = g.sim
	var cot = sim.medical.beds[0]
	sim.medical.beds = [cot]    # one cot is all the infirmary has
	_stand(sim, "south_east_corner", "bunk_house")
	var walt = _patient(sim, "Walt")
	eq(_at(walt.resting_bed), Vector2(cot.pos), "the first goes to the cot")
	eq(String(walt.activity), "Resting in the infirmary", "and says so")
	var hector = _patient(sim, "Hector")
	check(hector.resting_bed != null and _near_spot(_at(hector.resting_bed), sim.build.bed_spots()), "the second goes to a bed of the bunk house: %s" % str(hector.resting_bed))
	eq(Vector2(hector.x, hector.y), _at(hector.resting_bed), "carried to it")
	eq(String(hector.activity), "Resting in the bunk house", "and says where he is")
	var ruth = _patient(sim, "Ruth")
	check(ruth.resting_bed != null and _at(ruth.resting_bed).distance_to(_at(hector.resting_bed)) > 0.5, "the third has a bed of her own")
	g.world.free()


func test_the_cots_and_the_bunks_come_before_the_bunk_house_whatever_the_distance() -> void:
	var g := _game()
	var sim = g.sim
	_stand(sim, "south_east_corner", "bunk_house")
	var walt = _person(sim, "Walt")
	var spot: Vector2 = sim.build.bed_spots()[0]
	walt.x = spot.x
	walt.y = spot.y + 0.3    # he fell next to a bunk house bed
	walt.hp = 0.0
	sim.medical.on_downed(walt, "bite")
	sim.medical.stabilise(walt)
	eq(String(walt.activity), "Resting in the infirmary", "he is carried to a cot all the same")
	g.world.free()


func test_a_patient_in_a_bed_that_comes_down_is_put_in_another_one() -> void:
	var g := _game()
	var sim = g.sim
	var cot = sim.medical.beds[0]
	sim.medical.beds = [cot]
	_stand(sim, "south_east_corner", "bunk_house")
	var walt = _patient(sim, "Walt")
	var hector = _patient(sim, "Hector")
	check(_near_spot(_at(hector.resting_bed), sim.build.bed_spots()), "Hector is in the bunk house")
	walt.hp = 100.0
	Helpers.run(sim, 0.1)
	check(not walt.downed and walt.resting_bed == null, "Walt is up and the cot is free")
	check(sim.build.demolish("south_east_corner"), "the bunk house comes down")
	Helpers.run(sim, 0.1)
	check(hector.downed and hector.stabilised, "Hector is still a patient")
	eq(_at(hector.resting_bed), Vector2(cot.pos), "and he is in the cot")
	eq(String(hector.activity), "Resting in the infirmary", "which he says")
	eq(Vector2(hector.x, hector.y), Vector2(cot.pos), "carried there")
	g.world.free()


func test_a_patient_whose_bunk_house_comes_down_with_no_bed_free_rests_where_he_lies_and_gets_up() -> void:
	var g := _game()
	var sim = g.sim
	sim.medical.beds = []
	sim.jobs.unassign(_person(sim, "Ana"))    # nobody on duty in the infirmary: plain rest
	_stand(sim, "south_east_corner", "bunk_house")
	var hector = _patient(sim, "Hector")
	check(hector.resting_bed != null, "Hector is in a bed of the bunk house")
	var at := Vector2(hector.x, hector.y)
	check(sim.build.demolish("south_east_corner"), "the bunk house comes down")
	Helpers.run(sim, 0.1)
	eq(hector.resting_bed, null, "he is out of a bed that is gone")
	eq(String(hector.activity), "Resting", "and rests where he lies")
	eq(Vector2(hector.x, hector.y), at, "which is where the bed was")
	check(hector.downed and hector.stabilised and not hector.dead, "he is still a patient")
	var hp: float = hector.hp
	Helpers.run(sim, 20.0)
	near(float(hector.hp) - hp, Medical.REST_HEAL_H, 0.3, "he heals as fast as in any bed")
	var guard := 0
	while hector.downed and guard < 100:
		Helpers.run(sim, 1.0)
		guard += 1
	check(not hector.downed and hector.hp + 0.001 >= Medical.GET_UP_HP, "and gets up: hp %.2f after %d more seconds" % [float(hector.hp), guard])
	g.world.free()


func test_a_patient_in_the_bunk_house_heals_like_any_other_and_gets_up() -> void:
	var g := _game()
	var sim = g.sim
	sim.medical.beds = []
	sim.jobs.unassign(_person(sim, "Ana"))
	_stand(sim, "south_east_corner", "bunk_house")
	var hector = _patient(sim, "Hector")
	check(hector.resting_bed != null, "in a bunk house bed")
	Helpers.run(sim, 20.0)    # one game hour
	near(float(hector.hp), Medical.REST_HEAL_H, 0.3, "ten an hour in bed")
	var guard := 0
	while hector.downed and guard < 100:
		Helpers.run(sim, 1.0)
		guard += 1
	check(not hector.downed and hector.resting_bed == null, "he gets up at %d (after %d more seconds)" % [int(Medical.GET_UP_HP), guard])
	check(sim.alerts.has("up-%s" % hector.id), "and the crew is told")
	g.world.free()


func test_a_patient_in_the_bunk_house_is_still_there_after_a_save() -> void:
	var a := _game()
	var sim_a = a.sim
	sim_a.medical.beds = []
	_stand(sim_a, "south_east_corner", "bunk_house")
	var hector = _patient(sim_a, "Hector")
	check(hector.resting_bed != null, "Hector is in a bed of the bunk house")
	var bed: Vector2 = _at(hector.resting_bed)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := _game(8.0, 99)
	check(SaveGame.apply(b.sim, d), "the save loads")
	var hector_b = _person(b.sim, "Hector")
	eq(_at(hector_b.resting_bed), bed, "he is in the same bed")
	Helpers.run(b.sim, 1.0)
	eq(_at(hector_b.resting_bed), bed, "and the bed is still there a second later")
	check(_near_spot(bed, b.sim.build.bed_spots()), "the bunk house stands in the loaded game")
	var heard := false
	for bd in b.sim.medical.beds:
		heard = heard or (String(bd.kind) == "bunk house" and Vector2(bd.pos).distance_to(bed) < 0.05)
	check(heard, "and the medical module has its beds")
	a.world.free()
	b.world.free()


## The beds as the module has them and as the people lie in them, checked: nobody lies in a bed but a patient,
## nobody in a bed that is not there, no two in one, nobody on the floor while a bed is free.
func _check_beds(sim, tag: String) -> void:
	var taken := {}
	for p in sim.people:
		if p.resting_bed == null:
			continue
		check(p.downed and p.stabilised and not p.dead, "%s lies in a bed only as a patient (%s)" % [p.first, tag])
		var key := "%.2f,%.2f" % [Vector2(p.resting_bed).x, Vector2(p.resting_bed).y]
		check(not taken.has(key), "two people in one bed at %s (%s)" % [key, tag])
		taken[key] = true
		var there := false
		for b in sim.medical.beds:
			there = there or Vector2(b.pos).distance_to(Vector2(p.resting_bed)) < 0.05
		check(there, "%s lies in a bed that is gone: %s (%s)" % [p.first, str(p.resting_bed), tag])
	for p in sim.people:
		if p.downed and p.stabilised and not p.dead and p.resting_bed == null:
			for b in sim.medical.beds:
				var key := "%.2f,%.2f" % [Vector2(b.pos).x, Vector2(b.pos).y]
				check(taken.has(key), "%s lies on the floor while the bed at %s is free (%s)" % [p.first, key, tag])


func test_putting_up_and_pulling_down_bunk_houses_among_the_hurt_leaves_nobody_stuck() -> void:
	var g := _game()
	var sim = g.sim
	sim.medical.beds = [sim.medical.beds[0], sim.medical.beds[1]]    # two cots: the bunk houses are needed
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261002
	var plots := ["south_east_corner", "north_east_lot"]
	var ups := 0
	var downs := 0
	var rehomed := 0
	for i in 240:
		var op := rng.randi() % 7
		var plot: String = plots[rng.randi() % 2]
		match op:
			0, 1:
				if sim.build.plot(plot).building == "":
					_stand(sim, plot, "bunk_house")
					ups += 1
			2:
				if sim.build.plot(plot).building != "":
					var lying := 0
					for p in sim.people:
						lying += 1 if p.resting_bed != null and _near_spot(Vector2(p.resting_bed), sim.build.bed_spots()) else 0
					sim.build.demolish(plot)
					downs += 1
					rehomed += lying
			3, 4:
				var p = sim.people[rng.randi() % sim.people.size()]
				if not p.dead and p.away == null and not p.downed:
					p.hp = 0.0
					sim.medical.on_downed(p, "bite")
					sim.medical.stabilise(p)
			5:
				var p = sim.people[rng.randi() % sim.people.size()]
				if p.downed and p.stabilised:
					p.hp = Medical.GET_UP_HP - 0.5    # nearly well
			_:
				Helpers.run(sim, rng.randf_range(0.2, 3.0))
		Helpers.run(sim, 0.1)
		_check_beds(sim, "step %d, op %d" % [i, op])
	check(ups >= 5 and downs >= 5, "the fuzz really built and pulled down: %d and %d" % [ups, downs])
	check(rehomed >= 1, "and some patient lay in a bunk house when it came down: %d" % rehomed)
	# in the end everyone who lies gets up
	var guard := 0
	while guard < 400:
		var any := false
		for p in sim.people:
			any = any or p.downed
		if not any:
			break
		Helpers.run(sim, 1.0)
		guard += 1
	for p in sim.people:
		check(not p.downed and not p.dead, "%s is up in the end (hp %.1f)" % [p.first, float(p.hp)])
	g.world.free()


func _line(sim, p, label: String):
	for e in sim.morale.explain(p):
		if String(e.label) == label:
			return e
	return null


func test_the_bunk_house_steadies_everyones_mood() -> void:
	var g := _game()
	var sim = g.sim
	var before := {}
	for p in sim.people:
		before[p.id] = float(sim.morale.target(p))
		check(_line(sim, p, "A proper bed") == null, "%s has no bed to be glad of yet" % p.first)
	_stand(sim, "south_east_corner", "bunk_house")
	var lift: float = _fx(sim, "bunk_house", "morale")
	for p in sim.people:
		near(float(sim.morale.target(p)), float(before[p.id]) + lift, 1.0e-9, "%s's mood heads %.0f higher" % [p.first, lift])
		var line = _line(sim, p, "A proper bed")
		check(line != null, "%s's mood tooltip lists it" % p.first)
		if line != null:
			near(float(line.value), lift, 0.05, "with its sign: +%.0f" % lift)
			eq(bool(line.recent), false, "a steady thing, not a shock that fades")
	_stand(sim, "north_east_lot", "bunk_house")
	for p in sim.people:
		near(float(sim.morale.target(p)), float(before[p.id]) + 2.0 * lift, 1.0e-9, "a second bunk house, a second bed each")
	var ruth = _person(sim, "Ruth")
	ruth.dead = true
	near(float(sim.morale.target(ruth)), Morale.BASE_TARGET, 1.0e-9, "the dead have no mood to lift")
	ruth.dead = false
	sim.build.demolish("south_east_corner")
	sim.build.demolish("north_east_lot")
	for p in sim.people:
		eq(float(sim.morale.target(p)), float(before[p.id]), "%s's target is exactly what it was once the beds are gone" % p.first)
		check(_line(sim, p, "A proper bed") == null, "and the line is gone")
	g.world.free()


func test_the_bunk_house_moves_the_mood_to_its_new_target() -> void:
	var values := []
	var lift := 0.0
	for built in [false, true]:
		var g := _game()
		var sim = g.sim
		Helpers.no_work(sim)    # everyone stands where they are: nothing else changes the targets
		var from := {}
		for p in sim.people:
			from[p.id] = float(sim.morale.target(p))
		lift = _fx(sim, "bunk_house", "morale")
		if built:
			_stand(sim, "south_east_corner", "bunk_house")
		for p in sim.people:
			sim.morale.set_value(p, float(from[p.id]))    # each rests exactly at the plain target
		Helpers.run(sim, 30.0)    # one and a half game hours: drift is 2.5 an hour
		var row := {}
		for p in sim.people:
			row[p.id] = float(sim.morale.value(p))
		values.append(row)
		g.world.free()
	var rose := 0
	for id in values[0]:
		var gain: float = float(values[1][id]) - float(values[0][id])
		near(gain, lift, 0.2, "%s's mood climbed to the new target: %.2f" % [id, gain])
		rose += 1 if gain > lift - 1.0 else 0
	check(rose == 6, "all six rose")


func test_with_no_bunk_house_the_beds_and_the_mood_are_what_they_were() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.run(sim, 0.1)
	var found := _find_beds_of(sim)
	eq(sim.medical.beds, found, "the beds are the cots and the bunks of the map and no more")
	for p in sim.people:
		check(_line(sim, p, "A proper bed") == null, "%s has no such reason" % p.first)
	g.world.free()


## The cots, then the mattresses of the map, as the module has always found them.
func _find_beds_of(sim) -> Array:
	var cots: Array = []
	var bunks: Array = []
	for o in sim.d.objects:
		if o.kind == "cot":
			cots.append({"pos": Vector2(o.cx, o.cy), "kind": "cot"})
		elif o.kind == "mattress":
			bunks.append({"pos": Vector2(o.cx, o.cy), "kind": "mattress"})
	return cots + bunks


# ------------------------------------------------------------------ the floodlights --

func test_the_floodlights_lengthen_the_guns_reach_from_the_bell_to_dawn() -> void:
	var g := _game(22.0)
	var sim = g.sim
	var rifle: Dictionary = sim.weapons.rifle
	var pike: Dictionary = sim.weapons.pike
	var more := _fx(sim, "floodlights", "night_reach_mult")
	near(sim.reach_of(rifle), float(rifle.range), 1.0e-9, "with no floodlights a rifle reaches its own range")
	_stand(sim, "north_east_lot", "floodlights")
	near(sim.reach_of(rifle), float(rifle.range) * more, 1.0e-9, "at night the floodlights lengthen it")
	near(sim.reach_of(pike), float(pike.range), 1.0e-9, "a pike in the hand does not reach further")
	near(sim.reach_of(sim.BUTT), float(sim.BUTT.range), 1.0e-9, "nor the butt of a gun")
	_clock(sim, 10.0)
	near(sim.reach_of(rifle), float(rifle.range), 1.0e-9, "by day it is as ever")
	_clock(sim, 19.5)
	sim.bell_rung = false
	near(sim.reach_of(rifle), float(rifle.range), 1.0e-9, "before the bell the lights are not yet needed")
	sim.bell_rung = true
	near(sim.reach_of(rifle), float(rifle.range) * more, 1.0e-9, "from the bell on they are")
	_clock(sim, 6.0)
	near(sim.reach_of(rifle), float(rifle.range) * more, 1.0e-9, "until the day comes")
	_clock(sim, 6.6)
	near(sim.reach_of(rifle), float(rifle.range), 1.0e-9, "and then they are not")
	# the fog of a card is a night's thing too: the two multiply
	sim.storyteller.enabled = true
	sim.weather = "fog"
	_clock(sim, 22.0)
	near(sim.reach_of(rifle), float(rifle.range) * Storyteller.FOG_REACH * more, 1.0e-9, "in a fog the floodlights lengthen what the fog left")
	g.world.free()


func test_floodlit_guns_pick_a_target_further_out_at_night() -> void:
	var g := _game(22.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	dez.x = 40.0
	dez.y = 19.0
	var range_tiles := float(dez.gun.range)
	var z = sim.spawn(40.0, 19.0 - range_tiles * 1.06, "wander")
	z.speed = 0.0
	eq(sim._find_target(dez), null, "a walker 6% beyond the rifle's range is out of reach")
	_stand(sim, "north_east_lot", "floodlights")
	eq(sim._find_target(dez), z, "under the floodlights he is in reach")
	_clock(sim, 10.0)
	eq(sim._find_target(dez), null, "by day he is not again")
	g.world.free()


## How many of the crew's guns cover each wall section (the fields-of-fire numbers) and the sum, with
## everyone but `who` set aside and `who` standing at `at` on an order.
func _coverage_of(sim, who, at: Vector2) -> Dictionary:
	for q in sim.people:
		q.away = null if q == who else {"kind": "test"}
	who.drafted = true
	who.order = Vector3(at.x, at.y, 0.0)
	var each := {}
	var total := 0
	for s in sim.segments:
		each[s.id] = sim.tactics.coverage_of(s)
		total += int(each[s.id])
	return {"each": each, "total": total}


func test_the_floodlights_count_in_the_fields_of_fire() -> void:
	var g := _game(22.0)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")    # the hunting rifle reaches 22 tiles, 12% more is 2.6
	var gained := 0
	var posts: Array = []
	for po in sim.jobs.posts():
		posts.append(Vector2(po.pos))
	var plain: Array = []
	for at in posts:
		plain.append(_coverage_of(sim, marcus, at))
	_stand(sim, "north_east_lot", "floodlights")
	for i in posts.size():
		var lit := _coverage_of(sim, marcus, posts[i])
		for id in plain[i].each:
			check(int(lit.each[id]) >= int(plain[i].each[id]), "section %s is never covered by fewer under the lights (post %d)" % [str(id), i])
		gained += 1 if int(lit.total) > int(plain[i].total) else 0
	check(gained >= 1, "from some post the lights bring a section into reach: %d of %d" % [gained, posts.size()])
	var lit_by_night: Array = []
	for i in posts.size():
		lit_by_night.append(int(_coverage_of(sim, marcus, posts[i]).total))
	_clock(sim, 10.0)
	for i in posts.size():
		eq(int(_coverage_of(sim, marcus, posts[i]).total), lit_by_night[i], "by day the view shows tonight's reach, the lit one (post %d)" % i)
	g.world.free()


func test_the_fields_view_draws_the_floodlit_reach() -> void:
	var g := _game(22.0)
	var sim = g.sim
	var o := OverlayNode.new()
	var plain: Array = o.fields_plan(sim).reach
	_stand(sim, "north_east_lot", "floodlights")
	var lit: Array = o.fields_plan(sim).reach
	check(not plain.is_empty() and plain.size() == lit.size(), "every gun that can shoot has a ring")
	var longer := 0
	for i in plain.size():
		var who = _by_id(sim, String(plain[i].id))
		if who.gun.get("melee", false):
			near(float(lit[i].r), float(plain[i].r), 1.0e-9, "%s's pike has the ring it had" % plain[i].id)
			continue
		longer += 1
		near(float(lit[i].r), float(plain[i].r) * _fx(sim, "floodlights", "night_reach_mult"), 1.0e-9, "%s's ring is the floodlit one, as the guns have it" % plain[i].id)
	check(longer >= 3, "most of the crew has a gun the lights lengthen")
	_clock(sim, 10.0)
	var by_day: Array = o.fields_plan(sim).reach
	for i in lit.size():
		near(float(by_day[i].r), float(lit[i].r), 1.0e-9, "by day %s's ring is tonight's, the lit one" % plain[i].id)
	o.free()
	g.world.free()


## A blackout that is on, with nothing to mend it.
func _dark(sim) -> void:
	sim.storyteller.enabled = true
	sim.storyteller.blackout = {"state": "dark", "at": sim.clock_min, "send": false, "fixer": "", "work": 0.0}


func test_a_blackout_costs_no_aim_while_the_floodlights_stand() -> void:
	var g := _game(22.0)
	var sim = g.sim
	_dark(sim)
	near(sim.storyteller.aim_mult(8.0), Storyteller.DARK_AIM, 1.0e-9, "in the dark aim is worse far off")
	_stand(sim, "north_east_lot", "floodlights")
	near(sim.storyteller.aim_mult(8.0), 1.0, 1.0e-9, "with the floodlights it is not")
	near(sim.storyteller.aim_mult(20.0), 1.0, 1.0e-9, "at any distance")
	eq(sim.storyteller.blackout_state(), "dark", "the blackout itself goes on")
	eq(bool(sim.storyteller.look().blackout), true, "and the lamps are out")
	sim.build.demolish("north_east_lot")
	near(sim.storyteller.aim_mult(8.0), Storyteller.DARK_AIM, 1.0e-9, "without them it costs aim again")
	g.world.free()


func test_the_blackout_card_still_comes_and_says_the_floodlights_hold() -> void:
	var texts := []
	for floodlit in [false, true]:
		var g := _game(20.5)
		var sim = g.sim
		sim.storyteller.enabled = true
		sim.day = 8
		sim.clock_min = 7.0 * 1440.0 + (20.5 * 60.0 - 420.0)
		sim.storyteller.radio_day = 8
		sim.supplies.sources_day = 8
		sim.supplies.meal_day = 8
		sim.supplies.meals_done = 1
		if floodlit:
			_stand(sim, "north_east_lot", "floodlights")
		check(sim.storyteller.force("blackout"), "the card is put up")
		check(sim.storyteller.choose(1), "and the crew holds the wall in the dark")
		Helpers.run_to_hour(sim, 21.1)
		eq(sim.storyteller.blackout_state(), "dark", "the lights go out all the same")
		check(sim.alerts.has("story-blackout"), "an alert says so")
		texts.append(String(sim.alerts["story-blackout"].sub))
		g.world.free()
	check(String(texts[0]).contains("Aim is worse"), "without the floodlights the alert says aim is worse: '%s'" % texts[0])
	check(not String(texts[1]).contains("Aim is worse") and String(texts[1]).to_lower().contains("floodlight"), "with them it says they hold: '%s'" % texts[1])


func test_with_no_floodlights_the_reach_and_the_blackout_are_what_they_were() -> void:
	var g := _game(22.0)
	var sim = g.sim
	var dez = _person(sim, "Dez")
	for name in ["rifle", "shotgun", "pistol", "hunting", "service", "pike"]:
		var gun: Dictionary = sim.weapons[name]
		eq(sim.reach_of(gun), float(gun.range), "%s: the reach is the range, by night" % name)
		eq(sim.reach_of(gun, dez), float(gun.range), "%s: and for a person too" % name)
	sim.storyteller.enabled = true
	sim.weather = "fog"
	eq(sim.reach_of(sim.weapons.rifle), float(sim.weapons.rifle.range) * Storyteller.FOG_REACH, "fog does what it did")
	_dark(sim)
	eq(sim.storyteller.aim_mult(8.0), Storyteller.DARK_AIM, "and so does the blackout")
	eq(sim.storyteller.aim_mult(5.0), 1.0, "near or far")
	g.world.free()


# ------------------------------------------------------------------ the watchtower --

func test_a_watchtower_lengthens_the_reach_of_those_near_it() -> void:
	var g := _game(10.0)
	var sim = g.sim
	var rifle: Dictionary = sim.weapons.rifle
	var pike: Dictionary = sim.weapons.pike
	var dez = _person(sim, "Dez")
	_stand(sim, "west_wall", "watchtower")
	var more := _fx(sim, "watchtower", "reach_bonus")
	var radius := _fx(sim, "watchtower", "reach_radius")
	var tower: Vector2 = sim.build.plot("west_wall").pos
	dez.x = tower.x + radius - 0.5
	dez.y = tower.y
	near(sim.reach_of(rifle, dez), float(rifle.range) + more, 1.0e-9, "within the radius the guns reach %.0f tiles further" % more)
	near(sim.reach_of(rifle), float(rifle.range), 1.0e-9, "asked of the gun alone, the reach is the gun's")
	near(sim.reach_of(pike, dez), float(pike.range), 1.0e-9, "a pike does not reach further")
	near(sim.reach_at(rifle, tower), float(rifle.range) + more, 1.0e-9, "asked for a spot (a post), the same")
	dez.x = tower.x + radius + 0.5
	near(sim.reach_of(rifle, dez), float(rifle.range), 1.0e-9, "outside it, not")
	near(sim.reach_at(rifle, Vector2(tower.x + radius + 0.5, tower.y)), float(rifle.range), 1.0e-9, "for a spot outside, not")
	dez.x = tower.x + radius - 0.5
	_clock(sim, 22.0)
	near(sim.reach_of(rifle, dez), float(rifle.range) + more, 1.0e-9, "by night it is the same")
	sim.storyteller.enabled = true
	sim.weather = "fog"
	near(sim.reach_of(rifle, dez), float(rifle.range) * Storyteller.FOG_REACH + more, 1.0e-9, "in a fog the tower's tiles are still tiles")
	_stand(sim, "north_east_lot", "floodlights")
	near(sim.reach_of(rifle, dez), float(rifle.range) * Storyteller.FOG_REACH * _fx(sim, "floodlights", "night_reach_mult") + more, 1.0e-9, "and with the floodlights too")
	g.world.free()


func test_a_shooter_near_the_tower_picks_a_target_further_out() -> void:
	var g := _game(22.0)
	var sim = g.sim
	_stand(sim, "west_wall", "watchtower")
	var tower: Vector2 = sim.build.plot("west_wall").pos
	var dez = _person(sim, "Dez")
	dez.x = tower.x
	dez.y = tower.y
	var range_tiles := float(dez.gun.range)
	var z = sim.spawn(tower.x, tower.y - range_tiles - 2.0, "wander")
	z.speed = 0.0
	eq(sim._find_target(dez), z, "a walker two tiles beyond the rifle's range is in reach from the tower")
	dez.x = tower.x + _fx(sim, "watchtower", "reach_radius") + 1.0
	z.x = dez.x
	z.y = dez.y - range_tiles - 2.0
	eq(sim._find_target(dez), null, "from beyond its radius he is not")
	g.world.free()


func test_the_watchtower_counts_in_the_fields_of_fire() -> void:
	var g := _game(22.0)
	var sim = g.sim
	var ruth = _person(sim, "Ruth")    # a shotgun reaches 7.5 tiles: three more is a great deal
	var tower: Vector2 = sim.build.plot("west_wall").pos
	var radius := _fx(sim, "watchtower", "reach_radius")
	# places within the tower's radius, a tile apart (where the plots are is the view's business: wherever it is, some
	# place near it has a section the tower brings into the shotgun's reach)
	var spots: Array = []
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var at := tower + Vector2(float(dx), float(dy))
			if at.distance_to(tower) <= radius - 0.1:
				spots.append(at)
	var plain: Array = []
	for at in spots:
		plain.append(_coverage_of(sim, ruth, at))
	_stand(sim, "west_wall", "watchtower")
	var gained := 0
	for i in spots.size():
		var raised := _coverage_of(sim, ruth, spots[i])
		for id in plain[i].each:
			check(int(raised.each[id]) >= int(plain[i].each[id]), "section %s is never covered by fewer with the tower (spot %s)" % [str(id), str(spots[i])])
		gained += 1 if int(raised.total) > int(plain[i].total) else 0
	check(gained >= 1, "from some place near the tower the shotgun covers more of the wall: %d of %d places" % [gained, spots.size()])
	var far := _coverage_of(sim, ruth, tower + Vector2(radius + 3.0, 0.0))
	var far_with: int = int(far.total)
	sim.build.demolish("west_wall")
	eq(int(_coverage_of(sim, ruth, tower + Vector2(radius + 3.0, 0.0)).total), far_with, "far from the tower it made no difference")
	_stand(sim, "west_wall", "watchtower")
	_coverage_of(sim, ruth, tower)
	var o := OverlayNode.new()
	var rings: Array = o.fields_plan(sim).reach
	for r in rings:
		var who = _by_id(sim, String(r.id))
		near(float(r.r), sim.reach_at(who.gun, sim.tactics.post_pos(who)), 1.0e-9, "%s's ring is the reach the guns have at their post" % r.id)
		if who == ruth:
			near(float(r.r), float(who.gun.range) + _fx(sim, "watchtower", "reach_bonus"), 1.0e-9, "Ruth's ring is three tiles longer: she stands at the tower")
	o.free()
	g.world.free()


func test_with_no_watchtower_nobody_reaches_further() -> void:
	var g := _game(10.0)
	var sim = g.sim
	for p in sim.people:
		eq(sim.reach_of(p.gun, p), float(p.gun.range), "%s reaches as far as their gun" % p.first)
		eq(sim.reach_at(p.gun, Vector2(p.x, p.y)), float(p.gun.range), "(by position too)")
	g.world.free()


# ------------------------------------------------------------------- the radio mast --

func _card(id: String, kind: String, weight: float = 1.0) -> Dictionary:
	return Storyteller.normalise({"id": id, "kind": kind, "weight": weight, "title": "Card %s" % id, "text": "Text of %s." % id})


func _deck(kind: String, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(_card("%s%d" % [kind, i], kind))
	return out


func test_the_radio_mast_weighs_the_boons_and_the_threats_of_the_draw() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = _deck("threat", 5) + _deck("boon", 5) + [_card("choice0", "choice")]
	sim.storyteller.tension = 50.0
	var threat: Dictionary = sim.storyteller.cards[0]
	var boon: Dictionary = sim.storyteller.cards[5]
	var choice: Dictionary = sim.storyteller.cards[10]
	var t0: float = sim.storyteller._weight(threat)
	var b0: float = sim.storyteller._weight(boon)
	var c0: float = sim.storyteller._weight(choice)
	_stand(sim, "south_lot", "radio_mast")
	near(float(sim.storyteller._weight(threat)), t0 * _fx(sim, "radio_mast", "threat_mult"), 1.0e-9, "a threat is less likely")
	near(float(sim.storyteller._weight(boon)), b0 * _fx(sim, "radio_mast", "boon_mult"), 1.0e-9, "a boon is more")
	near(float(sim.storyteller._weight(choice)), c0, 1.0e-9, "a choice is as it was")
	sim.build.demolish("south_lot")
	eq(float(sim.storyteller._weight(threat)), t0, "with the mast gone the weights are as they were (threat)")
	eq(float(sim.storyteller._weight(boon)), b0, "(boon)")
	g.world.free()


func test_the_radio_mast_shifts_what_the_radio_brings() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = _deck("threat", 5) + _deck("boon", 5)
	sim.storyteller.tension = 50.0
	var share := {}
	for built in [false, true]:
		if built:
			_stand(sim, "south_lot", "radio_mast")
		var threats := 0
		var cards := 0
		for s in 400:
			sim.run_seed = s
			var c: Dictionary = sim.storyteller.draw(9)
			if c.is_empty():
				continue
			cards += 1
			threats += 1 if c.kind == "threat" else 0
		share[built] = float(threats) / float(cards)
	check(share[false] > 0.42 and share[false] < 0.58, "an even draw without the mast: %.2f threats" % share[false])
	var t: float = _fx(sim, "radio_mast", "threat_mult")
	var b: float = _fx(sim, "radio_mast", "boon_mult")
	var expected: float = t / (t + b)
	near(float(share[true]), expected, 0.06, "with it threats are %.2f of the cards: %.2f" % [expected, float(share[true])])
	check(float(share[true]) < float(share[false]) - 0.04, "fewer threats than without it")
	g.world.free()


func test_with_no_mast_the_draw_weights_are_what_they_were() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = _deck("threat", 2) + _deck("boon", 2) + [_card("choice0", "choice", 0.5)]
	for tension in [10.0, 50.0, 90.0]:
		sim.storyteller.tension = tension
		for c in sim.storyteller.cards:
			var style: Dictionary = Storyteller.STYLE[1]
			var want := float(c.weight)
			if c.kind == "threat":
				want *= float(style.threat)
				if tension < Storyteller.LEAN_BELOW:
					want *= Storyteller.LEAN
			elif c.kind == "boon":
				want *= float(style.boon)
				if tension > Storyteller.LEAN_ABOVE:
					want *= Storyteller.LEAN
			eq(float(sim.storyteller._weight(c)), want, "%s at tension %d" % [c.id, int(tension)])
	g.world.free()


# ------------------------------------------------------------------------ together --

## What every effect of the buildings changes, as numbers, for a game at night with the cards and a blackout.
func _numbers(sim) -> Dictionary:
	var out := {}
	var dez = _person(sim, "Dez")
	var marcus = _person(sim, "Marcus")
	var tower: Vector2 = sim.build.plot("west_wall").pos    # Dez stands where a tower would help him
	dez.x = tower.x
	dez.y = tower.y
	_clock(sim, 22.0)
	sim.storyteller.enabled = true
	sim.storyteller.cards = _deck("threat", 2) + _deck("boon", 2) + [_card("choice0", "choice")]
	sim.storyteller.blackout = {"state": "dark", "at": sim.clock_min, "send": false, "fixer": "", "work": 0.0}
	out["reach"] = [sim.reach_of(dez.gun, dez), sim.reach_of(marcus.gun, marcus), sim.reach_of(sim.weapons.pike)]
	out["aim"] = [sim.storyteller.aim_mult(3.0), sim.storyteller.aim_mult(9.0)]
	out["bench"] = [sim.workshop.scrap_per_hour(dez), sim.workshop.ammo_per_scrap()]
	out["mood"] = [sim.morale.target(dez), sim.morale.target(marcus)]
	var weights := []
	for c in sim.storyteller.cards:
		weights.append(sim.storyteller._weight(c))
	out["weights"] = weights
	sim.medical.update(0.0)
	out["beds"] = sim.medical.beds.size()
	var food: float = sim.stock.food
	sim.supplies.roll_dawn()
	out["dawn"] = float(sim.stock.food) - food
	return out


func test_pulling_every_building_down_puts_every_number_back() -> void:
	var a := _game()
	var plain := _numbers(a.sim)
	a.world.free()
	var b := _game()
	var sim = b.sim
	var plots := {"south_east_corner": "workshop", "north_east_lot": "bunk_house", "east_lot": "greenhouse", "junk_corner": "salvage_bench", "south_lot": "radio_mast", "north_wall": "floodlights", "west_wall": "watchtower"}
	for id in plots:
		_stand(sim, id, plots[id])
	var built := _numbers(sim)
	check(built != plain, "with everything built the numbers are not the plain ones")
	for key in ["reach", "aim", "bench", "mood", "weights"]:
		check(built[key] != plain[key], "%s changes" % key)
	check(int(built.beds) > int(plain.beds), "there are more beds: %d against %d" % [int(built.beds), int(plain.beds)])
	check(float(built.dawn) > float(plain.dawn), "and the dawn pays more")
	for id in plots:
		check(sim.build.demolish(id), "%s comes down" % plots[id])
	var after := _numbers(sim)
	for key in plain:
		eq(after[key], plain[key], "%s is exactly what it was" % key)
	b.world.free()


func test_with_everything_built_a_day_and_a_night_run_without_errors() -> void:
	var g := Helpers.make(73, 1)
	var sim = g.sim
	sim.storyteller.enabled = true
	sim.day = 3
	sim.minutes = 7.0 * 60.0
	sim.clock_min = 2.0 * 1440.0
	sim.phase = "day"
	sim.bell_rung = false
	sim.supplies.sources_day = 3
	sim.supplies.meal_day = 3
	sim.supplies.meals_done = 1
	sim.storyteller.radio_day = 2
	var plots := {"south_east_corner": "workshop", "north_east_lot": "bunk_house", "east_lot": "greenhouse", "junk_corner": "salvage_bench", "south_lot": "radio_mast", "north_wall": "floodlights", "west_wall": "watchtower"}
	for id in plots:
		_build_now(sim, id, plots[id])
	sim.medical.beds = [sim.medical.beds[0]]    # a one-cot infirmary: the second patient goes to the bunk house
	sim.events.clear()
	var downed_once := false
	var steps := 0
	while sim.over == "" and sim.day < 4 and steps < 20000:
		sim.update(1.0 / 15.0)    # as fast as the harness steps the rules
		steps += 1
		if not downed_once and sim.hour >= 15.0 and sim.day == 3:
			downed_once = true
			for first in ["Marcus", "Walt"]:
				var hurt = _person(sim, first)
				hurt.hp = 0.0
				sim.medical.on_downed(hurt, "bite")
				sim.medical.stabilise(hurt)
			check(String(_person(sim, "Walt").activity) == "Resting in the bunk house", "the second of two patients lies in the bunk house: %s" % _person(sim, "Walt").activity)
		if steps % 300 == 0:
			for p in sim.people:
				if p.resting_bed != null:
					check(p.downed and p.stabilised and not p.dead, "%s lies in a bed only as a patient (day %d, %.1f)" % [p.first, sim.day, sim.hour])
	check(sim.over != "" or sim.day >= 4, "the day went by (day %d, %.1f)" % [sim.day, sim.hour])
	for kind in sim.stock:
		check(is_finite(float(sim.stock[kind])) and float(sim.stock[kind]) >= 0.0, "%s is a sound number: %s" % [kind, str(sim.stock[kind])])
	for p in sim.people:
		check(is_finite(p.x) and is_finite(p.y) and is_finite(p.hp), "%s is somewhere sound" % p.first)
		check(float(sim.morale.value(p)) >= 0.0 and float(sim.morale.value(p)) <= 100.0, "and their mood too")
	for id in plots:
		eq(String(sim.build.plot(id).building), plots[id], "the %s still stands" % plots[id])
	check(downed_once, "someone was hurt and put to bed on the way")
	g.world.free()


# ------------------------------------------------------------ the accuracy of the longer reach --

func test_with_nothing_built_a_shot_hits_as_often_as_it_did() -> void:
	var g := _game(10.0)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	for name in ["rifle", "shotgun", "pistol", "hunting", "service"]:
		var gun: Dictionary = sim.weapons[name]
		for dist in [1.0, float(gun.range) * 0.5, float(gun.range)]:
			var skill: float = float(marcus.skills.Shooting) / 10.0 * sim.perf(marcus)
			var was: float = float(gun.acc) * (0.75 + skill * 0.35) * (1.0 - 0.5 * pow(dist / float(gun.range), 2.0))
			eq(sim.hit_chance(gun, marcus, dist), was, "%s at %.1f tiles: the chance is exactly the old one" % [name, dist])
	g.world.free()


func test_the_reach_a_tower_or_the_floodlights_add_is_shot_at_a_fair_accuracy() -> void:
	var g := _game(22.0)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	_stand(sim, "west_wall", "watchtower")
	_stand(sim, "north_east_lot", "floodlights")
	var tower: Vector2 = sim.build.plot("west_wall").pos
	marcus.x = tower.x + 1.0
	marcus.y = tower.y
	for name in ["rifle", "shotgun", "pistol", "hunting", "service"]:
		var gun: Dictionary = sim.weapons[name]
		var edge: float = sim.reach_of(gun, marcus)
		var plain: float = float(gun.range)
		check(edge > plain, "%s: it does reach further here (%.1f against %.1f)" % [name, edge, plain])
		var at_edge: float = sim.hit_chance(gun, marcus, edge)
		var skill: float = float(marcus.skills.Shooting) / 10.0 * sim.perf(marcus)
		var base: float = float(gun.acc) * (0.75 + skill * 0.35)
		check(at_edge >= base * 0.45, "%s: at the very edge of the longer reach a shot still has about the chance the gun's own edge has (%.3f of %.3f)" % [name, at_edge, base])
		var old_way: float = base * (1.0 - 0.5 * pow(edge / plain, 2.0))
		check(at_edge > old_way, "%s: better than measuring it against the gun's plain range (%.3f against %.3f)" % [name, at_edge, old_way])
	var rifle: Dictionary = sim.weapons.rifle
	marcus.x = 50.0    # far from the tower: only the floodlights, by night
	near(sim.accuracy_range(rifle, marcus), float(rifle.range) * _fx(sim, "floodlights", "night_reach_mult"), 1.0e-9, "away from the tower the floodlights alone lengthen it")
	_clock(sim, 10.0)
	near(sim.accuracy_range(rifle, marcus), float(rifle.range), 1.0e-9, "and by day nothing does")
	sim.storyteller.enabled = true
	sim.weather = "fog"
	near(sim.accuracy_range(rifle, marcus), float(rifle.range), 1.0e-9, "a fog shortens what the guns see, not the accuracy")
	near(sim.accuracy_range(sim.weapons.pike, marcus), float(sim.weapons.pike.range), 1.0e-9, "a pike is not helped")
	g.world.free()
