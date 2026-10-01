extends "res://tests/case.gd"
## The player's tools for a night: the alarm that draws the dead, auto-repair,
## how well the guns cover the wall, and the lookout's forecast.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Tactics := preload("res://scripts/sim/tactics.gd")

const NORTH_BUS := 3
const EAST_BUS := 12


func _seg(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## `n` of the dead on their way in from the east, each with a place at the wall.
func _from_the_east(sim, n: int) -> Array:
	sim.waves.enabled = false
	sim.zombies.clear()
	var out := []
	for i in n:
		var z = sim.spawn(76.0, 28.0 + float(i % 6), "approach")
		z.speed = 0.7
		sim._assign_slot(z)
		out.append(z)
	return out


func _on(zs: Array, seg) -> int:
	var n := 0
	for z in zs:
		if z.slot != null and z.slot.seg == seg:
			n += 1
	return n


# ------------------------------------------------------------------- lure --

func test_the_alarm_costs_scrap_lasts_three_hours_and_only_one_rings() -> void:
	var g := Helpers.make(11, 1)
	var sim = g.sim
	var before: float = sim.stock.scrap
	var north = _seg(sim, NORTH_BUS)
	check(sim.tactics.order_lure(north), "the alarm is set")
	near(sim.stock.scrap, before - Tactics.LURE_COST, 0.0001, "for three scrap")
	eq(sim.tactics.lure_seg(), north, "on that section")
	near(sim.tactics.lure_left_min(), Tactics.LURE_HOURS * 60.0, 0.01, "for three game hours")
	check(not sim.tactics.order_lure(_seg(sim, EAST_BUS)), "a second one is refused while it rings")
	Helpers.run(sim, 61.0)
	check(sim.tactics.lure_seg() == null, "and it stops after the three hours")
	g.world.free()


func test_the_alarm_needs_scrap_and_a_wall_that_stands() -> void:
	var g := Helpers.make(12, 1)
	var sim = g.sim
	sim.stock.scrap = 2.0
	check(not sim.tactics.order_lure(_seg(sim, NORTH_BUS)), "not with two scrap")
	check(sim.tactics.why_not_lure(_seg(sim, NORTH_BUS)).contains("scrap"), "and it says why")
	sim.stock.scrap = 20.0
	var down = _seg(sim, EAST_BUS)
	sim._damage_segment(down, down.hp + 1.0)
	check(not sim.tactics.order_lure(down), "not on a section that is down")
	for s in sim.segments:
		if s.kind == "door":
			check(not sim.tactics.order_lure(s), "not on a school door")
	g.world.free()


func test_the_dead_choose_the_alarm() -> void:
	var g := Helpers.make(13, 1)
	var sim = g.sim
	var plain := _from_the_east(sim, 20)
	var north = _seg(sim, NORTH_BUS)
	check(_on(plain, north) <= 2, "without it hardly any of the dead from the east go to the north bus: %d" % _on(plain, north))
	g.world.free()
	var h := Helpers.make(13, 1)
	var sim2 = h.sim
	sim2.stock.scrap = 20.0
	sim2.tactics.order_lure(_seg(sim2, NORTH_BUS))
	var drawn := _from_the_east(sim2, 20)
	check(_on(drawn, _seg(sim2, NORTH_BUS)) >= 10, "with it most of them do: %d of 20" % _on(drawn, _seg(sim2, NORTH_BUS)))
	h.world.free()


func test_the_dead_already_on_their_way_switch_to_a_new_alarm() -> void:
	var g := Helpers.make(14, 1)
	var sim = g.sim
	var zs := _from_the_east(sim, 20)
	var north = _seg(sim, NORTH_BUS)
	var before := _on(zs, north)
	sim.stock.scrap = 20.0
	check(sim.tactics.order_lure(north), "the alarm is set")
	check(_on(zs, north) >= before + 6, "a good many switch to it: %d, were %d" % [_on(zs, north), before])
	g.world.free()


func test_the_alarm_and_auto_repair_survive_a_save() -> void:
	var g := Helpers.make(15, 1)
	var sim = g.sim
	sim.tactics.order_lure(_seg(sim, NORTH_BUS))
	sim.tactics.toggle_auto(_person(sim, "Ana"))
	var saved := SaveGame.to_dict(sim)
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var other := Sim.new(data, world, FxNull.new())
	check(SaveGame.apply(other, saved), "the save loads")
	eq(other.tactics.lure_id, NORTH_BUS, "the alarm is still on the north bus")
	near(other.tactics.lure_left_min(), sim.tactics.lure_left_min(), 0.001, "with the same time left")
	check(other.tactics.auto_repair(_person(other, "Ana")), "and Ana's auto-repair is on")
	check(other.tactics.auto_repair(_person(other, "Dez")), "and Dez's still is")
	world.free()
	g.world.free()


# ------------------------------------------------------- standing orders --

func test_dez_and_hector_start_with_auto_repair_and_ana_does_not() -> void:
	var g := Helpers.make(16, 1)
	var sim = g.sim
	check(sim.tactics.auto_repair(_person(sim, "Dez")) and sim.tactics.auto_repair(_person(sim, "Hector")), "the builders")
	check(not sim.tactics.auto_repair(_person(sim, "Ana")), "not the nurse")
	g.world.free()


func test_auto_repair_mends_a_worn_section_by_day_without_an_order() -> void:
	var g := Helpers.make(17, 1)
	var sim = g.sim
	sim.waves.enabled = false
	var seg = _seg(sim, 4)
	seg.hp = seg.max_hp * 0.4
	sim._segment_state(seg)
	sim.stock.scrap = 30.0
	var before: float = seg.hp
	Helpers.run(sim, 40.0)
	check(seg.hp > before + 20.0, "somebody mended it: %.0f to %.0f" % [before, seg.hp])
	g.world.free()


func test_auto_repair_stops_when_scrap_is_low_and_by_night() -> void:
	var g := Helpers.make(18, 1)
	var sim = g.sim
	sim.waves.enabled = false
	var seg = _seg(sim, 4)
	seg.hp = seg.max_hp * 0.4
	sim._segment_state(seg)
	sim.stock.scrap = 4.0
	Helpers.run(sim, 10.0)
	for p in sim.people:
		check(p.repair == null, "%s is not sent with under five scrap" % p.first)
	sim.stock.scrap = 30.0
	sim.minutes = 21.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	Helpers.run(sim, 5.0)
	for p in sim.people:
		check(p.repair == null, "%s is not sent by night" % p.first)
	g.world.free()


func test_a_repair_goes_faster_with_the_building_skill() -> void:
	var g := Helpers.make(19, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.tactics.auto.clear()
	var gained := {}
	for who in ["Dez", "Marcus"]:
		var p = _person(sim, who)
		var seg = _seg(sim, 5)
		seg.hp = 100.0
		sim._segment_state(seg)
		sim.stock.scrap = 100.0
		sim.order_repair(p, seg)
		p.x = seg.center.x
		p.y = seg.center.y
		var start: float = seg.hp
		Helpers.run(sim, 4.0)
		gained[who] = seg.hp - start
		p.repair = null
	check(gained.Dez >= 2.0 * gained.Marcus, "Dez mends over twice as fast: %.0f against %.0f" % [gained.Dez, gained.Marcus])
	g.world.free()


# --------------------------------------------------------------- coverage --

func test_coverage_counts_the_guns_that_reach_a_section_and_follows_the_crew() -> void:
	var g := Helpers.make(20, 1)
	var sim = g.sim
	var map: Dictionary = sim.tactics.coverage_map()
	eq(map.size(), sim.segments.size(), "every section has a count")
	var east = _seg(sim, EAST_BUS)
	var before: int = sim.tactics.coverage_of(east)
	var ana = _person(sim, "Ana")
	# stand her right at the east bus: one more gun reaches it
	ana.drafted = true
	ana.order = Vector3(61.0, 34.7, 0)
	var after: int = sim.tactics.coverage_of(east)
	check(after >= before, "moving someone close never lowers it")
	ana.order = Vector3(40.0, 30.0, 0)
	var away: int = sim.tactics.coverage_of(east)
	check(away <= after, "and moving her off does not raise it")
	for s in sim.segments:
		check(sim.tactics.coverage_of(s) >= 0, "never negative")
	g.world.free()


# --------------------------------------------------------------- forecast --

func _at_hour(sim, hour: float) -> void:
	sim.waves.enabled = false
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.events.clear()


func test_the_lookout_forecasts_tonight_at_five() -> void:
	var g := Helpers.make(21, 1)
	var sim = g.sim
	_at_hour(sim, 16.9)
	Helpers.run(sim, 1.0)
	check(not sim.tactics.forecast().given, "nothing before 17:00")
	Helpers.run(sim, 20.0)
	var f: Dictionary = sim.tactics.forecast()
	check(f.given, "the forecast is given after 17:00")
	eq(f.who, "Marcus", "by the lookout")
	check(String(f.heading) != "", "it says where from: %s" % f.heading)
	var plan: Dictionary = sim.waves.plan_for(sim.day)
	check(absf(float(f.total) - float(plan.queue.size())) <= 0.16 * float(plan.queue.size()) + 2.5, "the number is within about 15%% of what comes: %d against %d" % [f.total, plan.queue.size()])
	check(sim.alerts.has("forecast"), "an alert carries it")
	var said := false
	for e in sim.events:
		if e.type == "banner" and String(e.text).contains("Marcus"):
			said = true
	check(said, "and a banner")
	g.world.free()


func test_without_the_lookout_there_is_no_forecast() -> void:
	var g := Helpers.make(22, 1)
	var sim = g.sim
	_person(sim, "Marcus").dead = true
	_at_hour(sim, 16.9)
	var told := ""
	for i in 12 * 30:
		sim.update(1.0 / 30.0)
		if sim.alerts.has("forecast"):
			told = String(sim.alerts["forecast"].text)
			break
	check(not sim.tactics.forecast().given, "none")
	eq(told, "No forecast", "and the crew is told that nobody is watching")
	g.world.free()


func test_the_forecast_is_given_once_a_day_and_a_late_night_still_has_it() -> void:
	var g := Helpers.make(23, 1)
	var sim = g.sim
	_at_hour(sim, 16.95)
	Helpers.run(sim, 5.0)
	sim.events.clear()
	Helpers.run(sim, 30.0)
	var again := 0
	for e in sim.events:
		if e.type == "banner" and String(e.text).contains("reports"):
			again += 1
	eq(again, 0, "not told a second time")
	_at_hour(sim, 3.0)
	check(sim.tactics.forecast().given, "at 03:00 the same night's forecast is still there")
	g.world.free()


# ------------------------------------------------------------------- decks --

func test_a_defender_on_a_raised_deck_is_scratched_far_less_than_one_on_the_ground() -> void:
	var counts := {}
	for spot_name in ["deck", "ground"]:
		var spot := Vector2(39.0, 18.8) if spot_name == "deck" else Vector2(39.0, 21.2)
		var g := Helpers.make(24, 1)
		var sim = g.sim
		sim.waves.enabled = false
		sim.zombies.clear()
		for p in sim.people:
			p.dead = true
		var ruth = sim.people[0]
		ruth.dead = false
		ruth.x = spot.x
		ruth.y = spot.y
		ruth.hp = 1000.0
		var seg = null
		for s in sim.segments:
			if s.id == 2:
				seg = s
		var z = sim.spawn(39.0, 15.4, "wander")
		z.speed = 0.0
		var scratched := 0
		for i in 600:
			var before: int = ruth.wounds
			sim.medical.on_wall_claw(z, seg)
			if ruth.wounds > before:
				scratched += 1
		counts[spot_name] = scratched
		g.world.free()
	check(counts.ground >= 40, "on the ground about one claw in nine scratches: %d of 600" % counts.ground)
	check(counts.deck * 3 <= counts.ground, "on the deck far fewer: %d against %d" % [counts.deck, counts.ground])
