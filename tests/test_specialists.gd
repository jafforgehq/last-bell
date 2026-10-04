extends "res://tests/case.gd"
## Specialists (round 20, slice 4: scripts/sim/specialists.gd, assets/data/titles.json): a title (the medic, the engineer,
## the marksman, the scout) is earned by skill and practice, held by one person at a time, and gives a small bonus on exactly
## that work. Avatar mode only, in the settlement game: with no avatar (or Orientation Day) every number is exactly neutral.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const TITLES := ["medic", "engineer", "marksman", "scout"]


# ----------------------------------------------------------------- helpers --

## A settlement game with an avatar (Ruth): Ruth, Dez, Marcus, Ana and Walt at 09:00 of day 4, no nights, no dead about. The
## other two round-20 modules are off, so that nothing but this module moves the News or the mood.
func _game(crew: int = 5, seed_value: int = 11) -> Dictionary:
	var g := Helpers.make(seed_value, 1, crew)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.relations.enabled = false
	sim.initiative.enabled = false
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	_at(sim, 4, 9.0)
	sim.events.clear()
	return g


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


func _at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## The practice each title asks for, read from assets/data/titles.json (never copied here: a retune of the data moves it).
var _needs := {}


func _need(title_id: String) -> float:
	if _needs.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/titles.json"))
		for t in parsed.get("titles", []):
			_needs[String(t.id)] = float(t.need)
	return float(_needs[title_id])


## What it takes: the skill and the practice for each title. A negative practice (the default) is exactly what the data asks for.
func _medic(p, medicine: int = 10, treated: int = -1) -> void:
	p.skills["Medicine"] = medicine
	p.stats["treated"] = int(ceil(_need("medic"))) if treated < 0 else treated


func _engineer(p, building: int = 9, work: float = -1.0) -> void:
	p.skills["Building"] = building
	p.stats["crafted"] = _need("engineer") if work < 0.0 else work
	p.stats["mended"] = 0.0


func _shot(p, shooting: int = 8, kills: int = -1) -> void:
	p.skills["Shooting"] = shooting
	p.stats["kills"] = int(ceil(_need("marksman"))) if kills < 0 else kills


## `n` trips home for each of these (a scout needs the number of trips the data names).
func _trips(sim, people: Array, n: int) -> void:
	for i in n:
		sim.specialists.on_trip(people, [], {})


func _news(sim, kind: String = "title") -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == kind:
			out.append(e)
	return out


func _shock_of(sim, p, label: String) -> float:
	for e in sim.morale.shocks.get(p.id, []):
		if String(e.label) == label:
			return float(e.value)
	return 0.0


func _json(d) -> String:
	return JSON.stringify(d, "", true)


# --------------------------------------------------------------- the rules --

func test_nobody_holds_a_title_at_the_start() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.specialists.active(), "an avatar game on a small start runs the module")
	sim.specialists.look()
	for t in TITLES:
		check(sim.specialists.holder(t) == null, "no %s yet" % t)
	for p in sim.people:
		check(sim.specialists.title_of(p).is_empty(), "%s has no title" % p.first)
	check(sim.specialists.gaps().is_empty(), "no gap: nothing was lost")
	g.world.free()


func test_the_module_runs_only_in_an_avatar_game_on_a_small_start() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.specialists.active(), "avatar, small start, enabled")
	sim.specialists.enabled = false
	check(not sim.specialists.active(), "Orientation Day switches it off")
	sim.specialists.enabled = true
	sim.recruits.small = false
	check(not sim.specialists.active(), "a classic six start has no specialists")
	sim.recruits.small = true
	sim.avatar.set_player(null)
	check(not sim.specialists.active(), "no avatar, no specialists")
	g.world.free()
	var h := Helpers.make(3, 1, 5)
	check(not h.sim.specialists.active(), "a game with no avatar (the harness, the old tests)")
	h.world.free()


func test_a_title_needs_the_skill_and_the_practice() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var walt = _p(sim, "walt")
	var marcus = _p(sim, "marcus")
	var dez = _p(sim, "dez")
	var m := int(_need("medic"))
	var k := int(_need("marksman"))
	var e := _need("engineer")
	_medic(ana, 10, m - 1)
	sim.specialists.look()
	check(sim.specialists.holder("medic") == null, "Medicine 10 and %d treated: not enough practice (%d)" % [m - 1, m])
	check(not sim.specialists.eligible(ana, "medic"), "and not eligible")
	ana.stats["treated"] = m
	check(sim.specialists.eligible(ana, "medic"), "%d treated: eligible" % m)
	_medic(walt, 5, 50 * m)
	check(not sim.specialists.eligible(walt, "medic"), "Medicine 5 is under the floor (6), whatever the practice")
	_shot(marcus, 8, k - 1)
	check(not sim.specialists.eligible(marcus, "marksman"), "%d kills: one short of %d" % [k - 1, k])
	marcus.stats["kills"] = k
	check(sim.specialists.eligible(marcus, "marksman"), "%d kills" % k)
	_engineer(dez, 9, 0.0)
	dez.stats["mended"] = 10.0 * e - 10.0
	check(not sim.specialists.eligible(dez, "engineer"), "a tenth of the HP mended, one under the %d" % int(e))
	dez.stats["mended"] = 10.0 * e
	check(sim.specialists.eligible(dez, "engineer"), "a tenth of the HP mended makes the %d" % int(e))
	dez.stats["mended"] = 100.0
	dez.stats["crafted"] = e - 10.0
	check(sim.specialists.eligible(dez, "engineer"), "10 mended and %d made add up to %d" % [int(e - 10.0), int(e)])
	_shot(dez, 5, 500)
	check(not sim.specialists.eligible(dez, "marksman"), "Shooting 5 is under the floor, whatever the kills")
	g.world.free()


func test_a_vacant_title_goes_to_the_best_score_at_once() -> void:
	var g := _game()
	var sim = g.sim
	var marcus = _p(sim, "marcus")
	var walt = _p(sim, "walt")
	var k := _need("marksman")
	_shot(marcus, 8, int(k * 1.5))    # 8 + 1.5
	_shot(walt, 7, int(k * 50.0))     # 7 + 2.0: the practice counts up to two points and no more
	near(sim.specialists.score(marcus, "marksman"), 9.5, 1e-9, "skill plus practice over need, here one and a half times the need")
	near(sim.specialists.score(walt, "marksman"), 9.0, 1e-9, "fifty times the need is worth two points, not fifty")
	sim.specialists.look()
	check(sim.specialists.holder("marksman") == marcus, "the best score takes the vacant title at the first look")
	eq(String(sim.specialists.title_of(marcus).id), "marksman", "and says so")
	check(sim.specialists.title_of(walt).is_empty(), "Walt has none")
	g.world.free()


func test_a_tie_goes_by_id() -> void:
	var g := _game()
	var sim = g.sim
	var marcus = _p(sim, "marcus")
	var walt = _p(sim, "walt")
	var k := int(_need("marksman"))
	_shot(marcus, 8, k)        # 9.0
	_shot(walt, 7, 2 * k)      # 9.0
	sim.specialists.look()
	check(sim.specialists.holder("marksman") == marcus, "a tie: the lower id, always")
	g.world.free()


func test_a_holder_is_displaced_only_by_a_clear_margin() -> void:
	var g := _game()
	var sim = g.sim
	var marcus = _p(sim, "marcus")
	var walt = _p(sim, "walt")
	var k := int(_need("marksman"))
	_shot(marcus, 8, k)    # 9.0
	sim.specialists.look()
	check(sim.specialists.holder("marksman") == marcus, "Marcus is the marksman")
	_shot(walt, 8, int(k * 1.5))      # 9.5: better, but not by a point
	sim.specialists.look()
	check(sim.specialists.holder("marksman") == marcus, "9.5 against 9.0: he keeps it (no flip-flop)")
	walt.stats["kills"] = 2 * k - 1    # just under 10.0
	sim.specialists.look()
	check(sim.specialists.holder("marksman") == marcus, "just under a point above: still his")
	walt.stats["kills"] = 2 * k    # 10.0
	sim.specialists.look()
	check(sim.specialists.holder("marksman") == walt, "10.0 against 9.0: a point above, Walt takes it")
	check(sim.specialists.title_of(marcus).is_empty(), "and Marcus is not the marksman")
	check(sim.specialists.gaps().is_empty(), "nothing was lost: the camp still has a marksman")
	eq(sim.morale.shocks.get(_p(sim, "dez").id, []).size(), 0, "no shock for a change of hands")
	g.world.free()


func test_a_person_holds_one_title() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	_engineer(dez, 9)    # 10.0
	_shot(dez, 6)              # 7.0 as a marksman
	_shot(marcus, 8)           # 9.0
	sim.specialists.look()
	eq(String(sim.specialists.title_of(dez).id), "engineer", "Dez takes the title he is best at")
	check(sim.specialists.holder("marksman") == marcus, "the other title goes to the next best")
	g.world.free()


func test_the_scout_needs_trips_and_more_than_anyone() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	var ruth = _p(sim, "ruth")
	var n := int(_need("scout"))
	_trips(sim, [dez, marcus], n)
	eq(int(sim.specialists.record_of(dez).trips), n, "each of those who came home has a trip")
	eq(int(sim.specialists.record_of(ruth).trips), 0, "and nobody else")
	sim.specialists.look()
	check(sim.specialists.holder("scout") == null, "the same number of trips each: nobody has more than the other")
	sim.specialists.on_trip([dez], [], {})
	sim.specialists.look()
	check(sim.specialists.holder("scout") == dez, "one more than the other: the scout")
	sim.specialists.on_trip([marcus], [], {})
	sim.specialists.look()
	check(sim.specialists.holder("scout") == dez, "a tie later does not take it from him")
	g.world.free()


func test_a_scout_needs_the_trips_the_data_asks_for() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var n := int(_need("scout"))
	_trips(sim, [dez], n - 1)
	sim.specialists.look()
	check(sim.specialists.holder("scout") == null, "%d trips are not enough, though nobody else has any" % (n - 1))
	sim.specialists.on_trip([dez], [], {})
	sim.specialists.look()
	check(sim.specialists.holder("scout") == dez, "%d are" % n)
	g.world.free()


func test_the_trips_of_those_who_were_lost_are_not_counted() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	sim.specialists.on_trip([dez], [marcus], {})
	eq(int(sim.specialists.record_of(marcus).trips), 0, "the one who did not come back")
	eq(int(sim.specialists.record_of(dez).trips), 1, "the one who did")
	g.world.free()


# --------------------------------------------------------------- the effects --

func test_the_engineer_is_quicker_at_the_bench_and_the_hammer() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var ruth = _p(sim, "ruth")
	var scrap0: float = sim.workshop.scrap_per_hour(dez)
	var rate0: float = sim.build.rate(dez)
	var ruth_scrap: float = sim.workshop.scrap_per_hour(ruth)
	_engineer(dez, 9)
	sim.specialists.look()
	eq(String(sim.specialists.title_of(dez).id), "engineer", "Dez is the engineer")
	near(sim.workshop.scrap_per_hour(dez) / scrap0, 1.15, 1e-9, "15% more scrap through the bench in an hour")
	near(sim.build.rate(dez) / rate0, 1.2, 1e-9, "20% more builder-hours")
	check(sim.workshop.scrap_per_hour(ruth) == ruth_scrap, "nobody else changes (exactly)")
	g.world.free()


func test_the_engineer_mends_a_wall_faster() -> void:
	var rates: Array = []
	for titled in [false, true]:
		var g := _game()
		var sim = g.sim
		sim.stock.scrap = 200.0
		var dez = _p(sim, "dez")
		_engineer(dez, 9)
		if titled:
			sim.specialists.look()
			check(sim.specialists.holder("engineer") == dez, "Dez is the engineer")
		var seg = sim.segments[4]
		sim._damage_segment(seg, 150.0)
		var hp0: float = seg.hp
		var spot: Vector2 = sim.repair_spot(seg)
		dez.x = spot.x
		dez.y = spot.y
		sim.order_repair(dez, seg)
		Helpers.run(sim, 3.0)
		rates.append(seg.hp - hp0)
		g.world.free()
	check(rates[0] > 30.0, "Dez mends a good deal in three seconds: %.1f" % rates[0])
	near(rates[1] / rates[0], 1.2, 0.01, "the engineer mends 20%% faster: %.1f against %.1f" % [rates[1], rates[0]])


func test_the_medic_bandages_faster_and_cures_more_often() -> void:
	var worked: Array = []
	var cures: Array = []
	for titled in [false, true]:
		var g := _game()
		var sim = g.sim
		sim.stock.meds = 10.0
		var ana = _p(sim, "ana")
		var hector = _p(sim, "walt")
		sim.traits.give(ana, [])
		_medic(ana, 10)
		if titled:
			sim.specialists.look()
			check(sim.specialists.holder("medic") == ana, "Ana is the medic")
		cures.append(sim.medical.cure_chance(ana))
		hector.x = ana.x + 0.3
		hector.y = ana.y
		sim.medical.add_wound(hector, "scratch")
		sim.medical.jobs.append({"healer": ana, "patient": hector, "kind": "bandage", "work": 0.0, "stand": null, "anchor": Vector2.ZERO})
		sim.medical._update_jobs(1.0)
		check(not sim.medical.jobs.is_empty(), "the job is still going")
		worked.append(float(sim.medical.jobs[0].work))
		g.world.free()
	near(worked[1] / worked[0], 1.25, 0.001, "25% faster with a bandage")
	near(cures[1] - cures[0], 0.08, 1e-9, "8 points on the chance of a cure")


func test_the_marksman_aims_a_little_better() -> void:
	var g := _game()
	var sim = g.sim
	var marcus = _p(sim, "marcus")
	var walt = _p(sim, "walt")
	var before: float = sim.aim_factor(marcus)
	var walt_before: float = sim.aim_factor(walt)
	_shot(marcus, 8)
	sim.specialists.look()
	check(sim.specialists.holder("marksman") == marcus, "Marcus is the marksman")
	near(sim.aim_factor(marcus) / before, 1.04, 1e-9, "4% on the aim")
	check(sim.aim_factor(walt) == walt_before, "Walt's aim is not touched (exactly)")
	g.world.free()


func test_a_title_gives_a_bonus_only_for_its_own_work() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	_medic(ana, 10)
	sim.specialists.look()
	check(sim.specialists.holder("medic") == ana, "Ana is the medic")
	for key in ["aim", "craft", "repair", "reload", "wound", "xp", "morale_recover", "grief", "dead_morale"]:
		check(sim.specialists.mult(ana, key) == 1.0, "the medic has nothing on '%s'" % key)
	check(sim.specialists.add(ana, "bond") == 0.0, "nor on a friend's bond")
	check(sim.specialists.mult(ana, "bandage") == 1.25, "her bandage")
	check(sim.specialists.add(ana, "cure") == 0.08, "her cure")
	for p in sim.people:
		if p != ana:
			for key in ["bandage", "craft", "repair", "aim"]:
				check(sim.specialists.mult(p, key) == 1.0, "%s has no bonus on '%s'" % [p.first, key])
			check(sim.specialists.add(p, "cure") == 0.0, "%s has no cure bonus" % p.first)
	g.world.free()


func test_traits_and_a_title_multiply() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var tinker := Helpers.trait_effect("tinkerer", "repair")
	check(sim.traits.mult(dez, "repair") == tinker, "Dez with his Tinkerer, no title")
	_engineer(dez, 9)
	sim.specialists.look()
	near(sim.traits.mult(dez, "repair"), tinker * 1.2, 1e-12, "the trait and the title multiply")
	g.world.free()


func test_everything_is_exactly_neutral_when_the_module_is_off() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var ana = _p(sim, "ana")
	var marcus = _p(sim, "marcus")
	_engineer(dez, 9)
	_medic(ana, 10)
	_shot(marcus, 8)
	sim.specialists.on_trip([dez], [], {})
	sim.specialists.look()
	check(sim.specialists.holder("engineer") == dez and sim.specialists.holder("medic") == ana, "the titles are held")
	check(sim.traits.mult(dez, "craft") != Helpers.trait_effect("tinkerer", "craft"), "on: the engineer's bench is not the trait's alone")
	sim.specialists.enabled = false
	for p in [dez, ana, marcus]:
		for key in ["craft", "repair", "bandage", "aim"]:
			check(sim.specialists.mult(p, key) == 1.0, "mult is exactly 1.0 when off: %s %s" % [p.id, key])
		check(sim.specialists.add(p, "cure") == 0.0, "add is exactly 0.0 when off")
		check(sim.specialists.fit_bonus(p, "infirmary") == 0.0 and sim.specialists.fit_bonus(p, "bench") == 0.0 and sim.specialists.fit_bonus(p, "watch") == 0.0, "no fit bonus when off")
		check(sim.specialists.title_of(p).is_empty(), "no title shown when off")
		eq(sim.specialists.opinion_title(p), "", "no opinion title when off")
	check(sim.specialists.party_mult([dez, ana]) == 1.0, "no loot bonus when off")
	check(sim.specialists.holder("engineer") == null and sim.specialists.gaps().is_empty(), "no holder, no gap when off")
	check(sim.traits.mult(dez, "craft") == Helpers.trait_effect("tinkerer", "craft"), "Dez's bench is the trait's alone, to the last bit")
	check(sim.traits.mult(dez, "repair") == Helpers.trait_effect("tinkerer", "repair"), "and his hammer")
	check(sim.traits.mult(ana, "bandage") == Helpers.trait_effect("triage", "bandage"), "Ana's bandage")
	check(sim.traits.add(ana, "cure") == Helpers.trait_effect("triage", "cure"), "Ana's cure, added")
	check(sim.traits.mult(marcus, "aim") == 1.0, "Marcus's aim (Nervous only counts among a crowd)")
	# and the look and the clock do nothing at all while it is off
	var shown: Array = _news(sim).duplicate()
	sim.specialists.update(60.0)
	sim.specialists.on_trip([dez], [], {})
	eq(_news(sim).size(), shown.size(), "nothing is told")
	eq(int(sim.specialists.record_of(dez).trips), 1, "and the trip that came in while it was off is not counted")
	g.world.free()


func test_a_game_with_no_avatar_never_gives_a_title() -> void:
	var g := Helpers.make(5, 1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	var ana = _p(sim, "ana")
	_medic(ana, 10, 60)
	Helpers.run(sim, 40.0)
	check(sim.specialists.holder("medic") == null, "no avatar: no medic, though Ana qualifies")
	check(_news(sim).is_empty(), "and no news")
	var plain: float = sim.traits.mult(ana, "bandage")
	check(plain == Helpers.trait_effect("triage", "bandage"), "her bandage is the trait's, to the last bit")
	g.world.free()


# ------------------------------------------------------------------ the seat --

## A crew of six at the base (Ruth is the player) in which only Ana (Medicine 6) and Walt (Medicine 7) are free when Auto-assign
## comes to the infirmary: Dez has the bench, Marcus the wall crew, one of the two newcomers the garden and the other the lookout post.
func _seat_game(titled: bool) -> Dictionary:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var walt = _p(sim, "walt")
	var marcus = _p(sim, "marcus")
	for q in [ana, walt]:
		sim.traits.give(q, [])
		q.skills["Building"] = 0
	ana.skills["Medicine"] = 6
	walt.skills["Medicine"] = 7
	marcus.skills["Building"] = 1
	for i in 2:
		var def: Dictionary = marcus.def.duplicate(true)
		def["id"] = "extra%d" % (i + 1)
		def["name"] = "Extra %d" % (i + 1)
		def["skills"] = {"Shooting": 9 if i == 1 else 0, "Melee": 0, "Building": 0, "Medicine": 0, "Leading": 0}
		def["traits"] = []
		def.erase("station")
		def.erase("post_id")
		sim.add_person(def)
	_medic(ana, 6)
	if titled:
		sim.specialists.look()
		check(sim.specialists.holder("medic") == ana, "Ana is the medic")
	return g


func test_the_title_holder_has_first_call_on_the_seat() -> void:
	var g := _seat_game(true)
	var sim = g.sim
	var ana = _p(sim, "ana")
	var walt = _p(sim, "walt")
	near(sim.jobs._fit(walt, "infirmary"), 7.0, 1e-9, "Walt, Medicine 7, suits the infirmary at 7")
	near(sim.jobs._fit(ana, "infirmary"), 7.5, 1e-9, "Ana, Medicine 6, at 6 and the seat's point and a half")
	near(sim.jobs._fit(ana, "bench"), float(ana.skills.Building), 1e-9, "and no more at the bench")
	near(sim.specialists.fit_bonus(ana, "infirmary"), 1.5, 1e-9, "fit_bonus: 1.5 for the title's own seat")
	check(sim.specialists.fit_bonus(ana, "bench") == 0.0 and sim.specialists.fit_bonus(ana, "watch") == 0.0, "and 0.0 for the others")
	check(sim.specialists.fit_bonus(walt, "infirmary") == 0.0, "and 0.0 for anybody without the title")
	sim.jobs.clear()
	check(sim.jobs._best_free("infirmary") == ana, "of the people with no job the medic is first for the seat")
	sim.jobs.auto_assign()
	eq(sim.jobs.job_of(ana), "infirmary", "Auto-assign sits the medic in the infirmary")
	check(sim.jobs.job_of(walt) != "infirmary", "and not the one with the better Medicine alone")
	g.world.free()
	var h := _seat_game(false)
	var s2 = h.sim
	s2.jobs.auto_assign()
	eq(s2.jobs.job_of(_p(s2, "walt")), "infirmary", "the same crew with no title: the better Medicine takes the seat")
	check(s2.jobs.job_of(_p(s2, "ana")) != "infirmary", "and she does not")
	h.world.free()


func test_the_engineer_and_the_marksman_have_their_seats_too() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	_engineer(dez, 9)
	_shot(marcus, 8)
	sim.specialists.look()
	near(sim.specialists.fit_bonus(dez, "bench"), 1.5, 1e-9, "the engineer at the bench")
	near(sim.specialists.fit_bonus(marcus, "watch"), 1.5, 1e-9, "the marksman at the lookout post")
	check(sim.specialists.fit_bonus(dez, "watch") == 0.0 and sim.specialists.fit_bonus(marcus, "bench") == 0.0, "not each other's")
	g.world.free()


func test_the_scout_has_no_seat_and_a_party_with_them_finds_more() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	var ruth = _p(sim, "ruth")
	_trips(sim, [dez], int(_need("scout")))
	sim.specialists.look()
	check(sim.specialists.holder("scout") == dez, "Dez is the scout")
	for id in ["bench", "builders", "garden", "watch", "infirmary", "radio", "salvage"]:
		check(sim.specialists.fit_bonus(dez, id) == 0.0, "no seat of the scout's: %s" % id)
	check(sim.specialists.party_mult([marcus, ruth]) == 1.0, "a party without the scout: 1.0 exactly")
	near(sim.specialists.party_mult([marcus, dez]), 1.12, 1e-9, "a party with the scout: 12% more")
	near(sim.specialists.party_mult([dez]), 1.12, 1e-9, "alone too")
	check(sim.specialists.party_mult([]) == 1.0, "nobody, nothing")
	var loot: float = sim.scavenge.loot_scale("houses", [marcus, ruth])
	near(sim.scavenge.loot_scale("houses", [marcus, ruth, dez]) / loot, 1.12, 1e-9, "loot_scale has it in")
	sim.specialists.enabled = false
	near(sim.scavenge.loot_scale("houses", [marcus, ruth, dez]), loot, 1e-12, "and not when the module is off")
	g.world.free()


func test_a_real_trip_counts_for_each_who_came_home() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	Helpers.no_work(sim)
	_at(sim, 4, 7.5)
	check(sim.scavenge.send([dez, marcus], "houses"), "a party is sent")
	var party: Dictionary = sim.scavenge.parties[0]
	party.result = {"loot": {}, "hurt": {}, "lost": []}
	var guard := 0
	while not sim.scavenge.parties.is_empty() and guard < 40000:
		sim.update(1.0 / 30.0)
		guard += 1
	check(sim.scavenge.parties.is_empty(), "the party is home")
	eq(int(sim.specialists.record_of(dez).trips), 1, "Dez has one trip")
	eq(int(sim.specialists.record_of(marcus).trips), 1, "and Marcus has one")
	eq(int(sim.specialists.record_of(_p(sim, "ruth")).trips), 0, "Ruth stayed")
	g.world.free()


func test_a_trip_the_player_led_counts_too() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = _p(sim, "ruth")
	var dez = _p(sim, "dez")
	Helpers.no_work(sim)
	_at(sim, 4, 7.5)
	var party: Dictionary = sim.scavenge.begin_played([ruth, dez], "houses")
	check(not party.is_empty(), "the trip begins in its place")
	sim.scavenge.finish_played(party, {})
	var guard := 0
	while not sim.scavenge.parties.is_empty() and guard < 60000:
		sim.update(1.0 / 30.0)
		guard += 1
	check(sim.scavenge.parties.is_empty(), "and ends at home")
	eq(int(sim.specialists.record_of(ruth).trips), 1, "the leader has a trip")
	eq(int(sim.specialists.record_of(dez).trips), 1, "and so has the one who went with them")
	g.world.free()


# ------------------------------------------------------------------ becoming --

func test_becoming_is_told_in_the_news_an_alert_and_a_bark() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var treated := int(_need("medic")) + 2
	_medic(ana, 10, treated)
	sim.events.clear()
	sim.specialists.look()
	var news := _news(sim)
	eq(news.size(), 1, "one News line")
	if news.size() == 1:
		eq(String(news[0].text), "Ana is the camp's medic now", "in the camp's words")
		eq(String(news[0].sub), "Medicine 10, %d treated" % treated, "with what earned it")
	check(sim.alerts.has("title-medic"), "an alert")
	if sim.alerts.has("title-medic"):
		near(float(sim.alerts["title-medic"].ttl), 60.0, 0.001, "for a minute")
	var barked := false
	for e in sim.events:
		if e.type == "bark" and e.who == "ana":
			barked = true
	check(barked, "and Ana says something")
	sim.specialists.look()
	eq(_news(sim).size(), 1, "told once")
	var t: Dictionary = sim.specialists.title_of(ana)
	eq(String(t.name), "the medic", "the name")
	eq(int(t.since_day), 4, "since the day it was earned")
	eq(sim.specialists.opinion_title(ana), "the medic", "opinion_title")
	eq(sim.specialists.opinion_title(_p(sim, "dez")), "", "nobody else has one")
	g.world.free()


func test_a_title_tells_what_it_gives_in_words() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	_medic(ana, 10)
	sim.specialists.look()
	var t: Dictionary = sim.specialists.title_of(ana)
	eq(String(t.short), "Medic", "the short name")
	eq(String(t.skill), "Medicine", "the skill")
	eq(String(t.bonus), "Bandages 25% faster, cures 8% more often", "what it gives")
	eq(String(t.practice), "Medicine 10, %d treated" % int(_need("medic")), "what earned it")
	check(String(t.blurb) != "", "a line about it")
	near(float(t.score), 11.0, 1e-9, "and the score: skill 10 and the practice (need / need, one point)")
	eq(sim.specialists.bonus_text("engineer"), "Makes ammo 15% faster, mends and builds 20% faster", "the engineer's")
	eq(sim.specialists.bonus_text("marksman"), "Shoots 4% truer", "the marksman's")
	eq(sim.specialists.bonus_text("scout"), "Finds 12% more on trips", "the scout's")
	eq(sim.specialists.bonus_text("nothing"), "", "an unknown title gives nothing")
	g.world.free()


func test_the_slow_look_and_the_dawn_evaluate() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	_medic(ana, 10)
	sim.specialists.update(sim.specialists.TICK_S - 0.5)
	check(sim.specialists.holder("medic") == null, "not before the slow look (10 s of rules time)")
	sim.specialists.update(1.0)
	check(sim.specialists.holder("medic") == ana, "at it")
	# a new title earned just before the dawn is named at the dawn
	var marcus = _p(sim, "marcus")
	_shot(marcus, 8)
	sim.phase = "night"
	sim.specialists.update(0.1)
	sim.phase = "dawn"
	sim.specialists.update(0.1)
	check(sim.specialists.holder("marksman") == marcus, "the dawn is a look of its own")
	g.world.free()


func test_a_look_does_not_touch_the_dice() -> void:
	var g := _game()
	var sim = g.sim
	_medic(_p(sim, "ana"), 10)
	_shot(_p(sim, "marcus"), 8)
	var state: int = sim.rng.state
	for i in 20:
		sim.specialists.update(10.0)
	sim.specialists.on_trip([_p(sim, "dez")], [], {})
	sim.specialists.title_of(_p(sim, "ana"))
	eq(sim.rng.state, state, "no use of sim.rng")
	g.world.free()


# -------------------------------------------------------------------- losing --

func _medic_game() -> Dictionary:
	var g := _game()
	var sim = g.sim
	_medic(_p(sim, "ana"), 10)
	sim.specialists.look()
	check(sim.specialists.holder("medic") == _p(sim, "ana"), "Ana is the medic")
	sim.radio.news.clear()
	sim.morale.shocks.clear()
	return g


func test_the_medic_dies_and_the_camp_has_no_medic() -> void:
	var g := _medic_game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var dez = _p(sim, "dez")
	sim.medical.kill(ana, "bled")
	sim.morale.shocks.clear()
	sim.specialists.look()
	check(sim.specialists.holder("medic") == null, "no medic")
	check(sim.specialists.title_of(ana).is_empty(), "the dead one holds nothing")
	var news := _news(sim)
	eq(news.size(), 1, "one line")
	if news.size() == 1:
		eq(String(news[0].text), "Ana was the medic. The camp has no medic now.", "the camp says so")
	near(_shock_of(sim, dez, "No medic: Ana is gone"), -3.0, 1e-9, "everyone at the base takes a shock of 3")
	near(_shock_of(sim, _p(sim, "marcus"), "No medic: Ana is gone"), -3.0, 1e-9, "all of them")
	check(sim.specialists.mult(ana, "bandage") == 1.0, "and the bonus is gone")
	var gaps: Array = sim.specialists.gaps()
	eq(gaps.size(), 1, "the gap shows")
	if gaps.size() == 1:
		eq(String(gaps[0].id), "medic", "which title")
		eq(String(gaps[0].name), "the medic", "its name")
		eq(int(gaps[0].since_day), 4, "since which day")
		eq(String(gaps[0].was), "ana", "who it was")
	sim.specialists.look()
	eq(_news(sim).size(), 1, "told once")
	g.world.free()


func test_the_medic_turns() -> void:
	var g := _medic_game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	sim.medical._turn(ana)
	sim.morale.shocks.clear()
	sim.specialists.look()
	check(sim.specialists.holder("medic") == null, "a turned medic is no medic")
	eq(sim.specialists.gaps().size(), 1, "the gap")
	g.world.free()


func test_the_medic_leaves_through_the_gate() -> void:
	var g := _medic_game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	sim.medical._exile(ana)
	sim.morale.shocks.clear()
	sim.specialists.look()
	check(sim.specialists.holder("medic") == null, "one who left is no medic")
	eq(sim.specialists.gaps().size(), 1, "the gap")
	var news := _news(sim)
	check(news.size() == 1 and String(news[0].text).begins_with("Ana was the medic"), "News")
	g.world.free()


func test_a_medic_away_for_more_than_three_days_loses_the_title() -> void:
	var g := _medic_game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	ana.away = {"kind": "party", "site": "houses"}
	sim.specialists.look()
	check(sim.specialists.holder("medic") == ana, "away, but only just: still the medic")
	sim.clock_min += 2.0 * 1440.0 + 600.0
	sim.specialists.look()
	check(sim.specialists.holder("medic") == ana, "two and a half days: still")
	sim.clock_min += 1440.0
	sim.specialists.look()
	check(sim.specialists.holder("medic") == null, "more than three days: lost")
	eq(sim.specialists.gaps().size(), 1, "the gap")
	g.world.free()


func test_a_short_trip_does_not_cost_the_title() -> void:
	var g := _medic_game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	ana.away = {"kind": "party", "site": "houses"}
	sim.specialists.look()
	sim.clock_min += 2.0 * 1440.0
	sim.specialists.look()
	ana.away = null
	sim.specialists.look()
	sim.clock_min += 2.0 * 1440.0
	sim.specialists.look()
	check(sim.specialists.holder("medic") == ana, "coming home resets the count: two days and two days are not four")
	ana.away = {"kind": "party", "site": "houses"}
	sim.specialists.look()
	sim.clock_min += 2.0 * 1440.0
	sim.specialists.look()
	check(sim.specialists.holder("medic") == ana, "a second trip starts from zero")
	g.world.free()


func test_an_heir_is_named_and_the_gap_closes() -> void:
	var g := _medic_game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var walt = _p(sim, "walt")
	sim.medical.kill(ana, "bled")
	sim.specialists.look()
	eq(sim.specialists.gaps().size(), 1, "a gap")
	_medic(walt, 6)
	sim.specialists.look()
	check(sim.specialists.holder("medic") == walt, "Walt is the new medic")
	check(sim.specialists.gaps().is_empty(), "no gap now")
	var texts: Array = []
	for e in _news(sim):
		texts.append(String(e.text))
	check(texts.has("Walt is the camp's medic now"), "and the News says so: %s" % str(texts))
	g.world.free()


func test_an_heir_at_once_means_no_gap_and_no_shock() -> void:
	var g := _medic_game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	var walt = _p(sim, "walt")
	_medic(walt, 6)
	check(sim.specialists.holder("medic") == ana, "Ana holds it, Walt is behind her")
	sim.medical.kill(ana, "bled")
	sim.morale.shocks.clear()
	sim.specialists.look()
	check(sim.specialists.holder("medic") == walt, "Walt takes it at the same look")
	check(sim.specialists.gaps().is_empty(), "so there was no gap")
	near(_shock_of(sim, _p(sim, "dez"), "No medic: Ana is gone"), 0.0, 1e-9, "and no shock for a lack of a medic")
	var texts: Array = []
	for e in _news(sim):
		texts.append(String(e.text))
	check(texts.has("Ana was the medic.") and texts.has("Walt is the camp's medic now"), "the News tells both: %s" % str(texts))
	check(not texts.has("Ana was the medic. The camp has no medic now."), "and does not say there is none")
	g.world.free()


func test_a_gap_is_remembered_for_six_days() -> void:
	var g := _medic_game()
	var sim = g.sim
	sim.medical.kill(_p(sim, "ana"), "bled")
	sim.specialists.look()
	eq(sim.specialists.gaps().size(), 1, "the day it happened")
	sim.day += 5
	eq(sim.specialists.gaps().size(), 1, "five days on")
	sim.day += 1
	eq(sim.specialists.gaps().size(), 0, "six days on it is not listed")
	g.world.free()


func test_the_shock_is_given_once_and_only_to_those_at_the_base() -> void:
	var g := _medic_game()
	var sim = g.sim
	var walt = _p(sim, "walt")
	walt.away = {"kind": "party", "site": "houses"}
	sim.medical.kill(_p(sim, "ana"), "bled")
	sim.morale.shocks.clear()
	sim.specialists.look()
	sim.specialists.look()
	near(_shock_of(sim, _p(sim, "dez"), "No medic: Ana is gone"), -3.0, 1e-9, "once, not twice")
	near(_shock_of(sim, walt, "No medic: Ana is gone"), 0.0, 1e-9, "not for one who is away")
	g.world.free()


func test_a_lost_scout_leaves_no_loot_bonus() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	_trips(sim, [dez], int(_need("scout")))
	sim.specialists.look()
	near(sim.specialists.party_mult([dez]), 1.12, 1e-9, "the scout")
	sim.medical.kill(dez, "bled")
	sim.specialists.look()
	check(sim.specialists.party_mult([dez, _p(sim, "marcus")]) == 1.0, "gone")
	var texts: Array = []
	for e in _news(sim):
		texts.append(String(e.text))
	check(texts.has("Dez was the scout. The camp has no scout now."), "told: %s" % str(texts))
	g.world.free()


# ---------------------------------------------------------------------- save --

func test_a_save_keeps_the_titles_the_trips_and_the_gaps() -> void:
	var a := _game()
	var sim = a.sim
	_medic(_p(sim, "ana"), 10)
	_engineer(_p(sim, "dez"), 9, _need("engineer") + 1.0)
	sim.specialists.look()
	var trips := int(_need("scout")) + 1
	_trips(sim, [_p(sim, "walt")], trips)
	sim.specialists.look()
	sim.medical.kill(_p(sim, "ana"), "bled")
	sim.specialists.look()
	check(sim.specialists.holder("engineer") == _p(sim, "dez") and sim.specialists.holder("scout") == _p(sim, "walt"), "an engineer and a scout")
	eq(sim.specialists.gaps().size(), 1, "and a gap")
	var d := SaveGame.to_dict(sim)
	check(d.modules.has("specialists"), "the module is in the save")
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads from text")
	var sb = b.sim.specialists
	eq(_json(sb.save()), _json(sim.specialists.save()), "the same state, key for key")
	check(sb.holder("engineer") != null and sb.holder("engineer").id == "dez", "Dez is still the engineer")
	check(sb.holder("scout") != null and sb.holder("scout").id == "walt", "Walt is still the scout")
	eq(int(sb.record_of(_p(b.sim, "walt")).trips), trips, "the trips are kept")
	eq(sb.gaps().size(), 1, "the gap")
	eq(int(sb.title_of(_p(b.sim, "dez")).since_day), 4, "since the same day")
	var before: int = _news(b.sim).size()
	sb.look()
	eq(_news(b.sim).size(), before, "a save with module data names nothing again")
	a.world.free()
	b.world.free()


func test_the_first_look_after_a_save_with_no_module_data_is_silent() -> void:
	var a := _game()
	var sim = a.sim
	_medic(_p(sim, "ana"), 10)
	_shot(_p(sim, "marcus"), 8)
	var d := SaveGame.to_dict(sim)
	d.modules.erase("specialists")
	var b := _bare()
	check(SaveGame.apply(b.sim, d), "a save from before loads")
	var sb = b.sim.specialists
	check(sb.holder("medic") == null, "nothing yet")
	var before: int = _news(b.sim).size()
	b.sim.events.clear()
	sb.look()
	check(sb.holder("medic") != null and sb.holder("medic").id == "ana", "the first look names the medic")
	check(sb.holder("marksman") != null and sb.holder("marksman").id == "marcus", "and the marksman")
	eq(_news(b.sim).size(), before, "with no News line")
	check(not b.sim.alerts.has("title-medic"), "no alert")
	var barks := 0
	for e in b.sim.events:
		if e.type == "bark":
			barks += 1
	eq(barks, 0, "no bark")
	# and the silence is used up: a title earned later is announced
	var walt = _p(b.sim, "walt")
	_trips(b.sim, [walt], int(_need("scout")))
	sb.look()
	eq(_news(b.sim).size(), before + 1, "the next new title is told")
	a.world.free()
	b.world.free()


func test_a_loaded_game_goes_on_the_same() -> void:
	var a := _game()
	var sim = a.sim
	_medic(_p(sim, "ana"), 10)
	Helpers.run(sim, 12.0)
	var d := SaveGame.to_dict(sim)
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads")
	var seeds := [sim, b.sim]
	_shot(_p(sim, "marcus"), 8)
	_shot(_p(b.sim, "marcus"), 8)
	for s in seeds:
		Helpers.run(s, 25.0)
	eq(_json(b.sim.specialists.save()), _json(sim.specialists.save()), "both have the same state after the same play")
	check(sim.specialists.holder("marksman") != null, "and the marksman was named by the slow look")
	a.world.free()
	b.world.free()


func test_a_damaged_save_is_cleaned() -> void:
	var g := _game()
	var sim = g.sim
	_medic(_p(sim, "ana"), 10)
	_shot(_p(sim, "marcus"), 8, int(_need("marksman")) - 1)    # not enough practice: a claim of the title is false
	var bad := {
		"holders": {"medic": "ana", "marksman": "marcus", "wizard": "ana", "scout": "nobody", "engineer": 7},
		"since": {"medic": "soon", "marksman": 3.0, "wizard": 2.0},
		"records": {"ana": {"trips": NAN}, "dez": {"trips": -4}, "ghost": {"trips": 9}, "walt": {"trips": 1.0e30}, "marcus": "x", "ruth": {"trips": 2.0}},
		"lost": {"scout": {"day": NAN, "was": "ana"}, "wizard": {"day": 1.0, "was": "ana"}, "engineer": {"day": 3.0, "was": 5}},
		"away": {"ana": INF, "ghost": 3.0},
		"acc": NAN,
		"phase": 7,
	}
	sim.specialists.load_state(bad)
	var sp = sim.specialists
	check(sp.holder("medic") == _p(sim, "ana"), "a true claim stands")
	check(sp.holder("marksman") == null, "a claim he has not earned does not")
	check(sp.holder("scout") == null and sp.holder("engineer") == null, "nobody, and not a number, holds a title")
	eq(int(sp.record_of(_p(sim, "dez")).trips), 0, "a negative count is nothing")
	check(int(sp.record_of(_p(sim, "walt")).trips) <= 100000, "a silly count is clamped")
	eq(int(sp.record_of(_p(sim, "ana")).trips), 0, "NaN is nothing")
	eq(int(sp.record_of(_p(sim, "ruth")).trips), 2, "a good count is kept")
	var out: Dictionary = sp.save()
	check(not out.holders.has("wizard"), "no unknown title")
	check(not out.records.has("ghost"), "no unknown person")
	check(is_finite(float(out.acc)), "the clock is a number")
	# the damage is survivable: the module goes on
	sp.look()
	sp.update(11.0)
	for junk in [{}, {"holders": [1, 2], "records": 5, "lost": "x"}, {"holders": null}]:
		sp.load_state(junk)
		sp.look()
	check(true, "garbage of any shape loads")
	g.world.free()


func test_a_holder_who_is_dead_in_the_save_is_not_a_holder() -> void:
	var g := _game()
	var sim = g.sim
	var ana = _p(sim, "ana")
	_medic(ana, 10)
	sim.specialists.look()
	var d: Dictionary = sim.specialists.save()
	ana.dead = true
	sim.specialists.load_state(d)
	check(sim.specialists.holder("medic") == null, "the dead hold nothing")
	g.world.free()
