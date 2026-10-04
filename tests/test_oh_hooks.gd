extends "res://tests/case.gd"
## The neutral hooks of the One House work package (WP5 phase A) in the school's shared files, and the town's rules class (scripts/town/town_rules.gd):
## each hook answers as the school always did in a school Sim, and TownRules answers for a base that is a claimed house. (The two golden tests
## prove the school's whole game is unchanged; these name each hook.)

const Helpers := preload("res://tests/helpers.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const Waves := preload("res://scripts/sim/waves.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const World := preload("res://scripts/world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")


## A stand-in for a town module: answers what the rules ask, and says what it was asked.
class Fake:
	extends RefCounted
	var claimed := true
	var house := 0
	var attacks := false
	var gate := false
	var no_wall := false
	var calls: Array = []
	var rec_of := {}

	func attacks_on() -> bool:
		return attacks

	func gate_open() -> bool:
		return gate

	func no_outer_wall() -> bool:
		return no_wall

	func center() -> Vector2:
		return Vector2(100.0, 90.0)

	func yard_middle() -> Vector2:
		return Vector2(101.0, 91.0)

	func compound() -> Rect2:
		return Rect2(90.0, 80.0, 20.0, 20.0)

	func yard_rect() -> Rect2:
		return Rect2(94.0, 84.0, 12.0, 12.0)

	func house_at(x: float, y: float) -> int:
		return house if Vector2(x, y).distance_to(Vector2(100.0, 90.0)) < 4.0 else -1

	func prepare_load(_data: Dictionary):
		calls.append("prepare")
		return "before"

	func restore(before) -> void:
		calls.append("restore:%s" % str(before))


## The town's rules on the real generated town, with the town's own modules as variables (a class made here: TownSim declares them in the game).
func _town() -> Dictionary:
	var s := GDScript.new()
	s.source_code = "extends \"res://scripts/town/town_rules.gd\"\nvar base\nvar perimeter\nvar field\nvar houses\n"
	s.reload()
	var town := TownGen.make(1)
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(town.data)
	var sim = s.new(town.data, world, FxNull.new())
	return {"sim": sim, "world": world, "town": town}


func test_the_school_answers_as_ever() -> void:
	var g := Helpers.make(3, 1, 6)
	var sim = g.sim
	check(not sim.is_one_house(), "a school game is not the town")
	eq(sim.base_center(), Vector2(42.0, 32.0), "the compound's middle")
	eq(sim.yard_middle(), sim.nights.YARD_MIDDLE, "the yard's middle")
	check(sim._wanderers_rally(), "the bell rallies the wanderers")
	check(not sim._any_gate_open(), "the gate is shut at the start")
	check(sim._is_open_gate(sim.segments[2]) and not sim._is_open_gate(sim.segments[3]), "the gate is wall section 2 and only it")
	sim.zombies[0].state = "dead"
	var by_hand := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			by_hand += 1
	eq(sim.alive_for_cap(), by_hand, "the cap counts every dead one that is alive")
	eq(Waves.direction_name(Vector2(60.0, 32.0)), "east", "the default centre is the compound's")
	eq(Waves.direction_name(Vector2(60.0, 32.0), Vector2(100.0, 32.0)), "west", "another centre moves the compass")
	check(not sim.lots.on and not sim.build.catalogue().is_empty(), "the classic start has no lots and a catalogue")
	# a layout goes in and out and leaves the school's plots, stations and posts as they were
	var plots_n: int = sim.build._plots.size()
	var cat_n: int = sim.build.catalogue().size()
	var stations_n: int = sim.jobs.stations().size()
	var posts: Array = sim.jobs.posts()
	sim.build.install_layout([{"id": "slot_x", "name": "X", "kind": "slot", "pos": [5, 5], "size": [2, 1], "work": [5, 6], "kits": ["kit_fence"]}],
		[{"id": "kit_fence", "name": "Fence", "scrap": 5, "work": 3.0, "max": 99, "slot_kit": "fence", "hp": 120.0}])
	sim.jobs.install_layout([{"id": "bench", "name": "Bench", "pos": [3, 3], "seats": 1}], [{"id": "p0", "name": "Post", "pos": [4, 4], "face": "S"}], {"spots": []})
	check(not sim.build.plot("slot_x").is_empty() and sim.build.catalogue().size() == cat_n, "a slot kit is not on the Build page")
	eq(sim.jobs.stations().size(), 1, "the layout's stations replace the file's")
	eq(sim.jobs.post_of(sim.people[0]).id, "p0", "everyone's post is made again from the layout")
	sim.build.clear_layout()
	sim.jobs.clear_layout()
	eq(sim.build._plots.size(), plots_n, "the plots are the file's again")
	eq(sim.jobs.stations().size(), stations_n, "the stations are the file's again")
	eq(sim.jobs.posts().size(), posts.size(), "the posts are the file's again")
	check(sim.build.plot("slot_x").is_empty(), "the slot is gone")
	g.world.free()


func test_the_tactics_and_save_hooks_wait_for_the_town() -> void:
	var g := Helpers.make(4, 1, 6)
	var sim = g.sim
	# H10: a scenario that says no forecast silences the lookout; one without the call does not
	var who = sim.people[0]
	sim.tactics.forecast_day = sim.day
	sim.tactics.forecast_who = String(who.id)
	check(bool(sim.tactics.forecast().given), "the school's lookout gives the forecast")
	var quiet := Fake.new()
	sim.scenario = quiet    # (no forecast_on: as the school's scenario)
	check(bool(sim.tactics.forecast().given), "a scenario with no forecast_on changes nothing")
	var s := GDScript.new()
	s.source_code = "extends RefCounted\nfunc forecast_on() -> bool:\n\treturn false\n"
	s.reload()
	sim.scenario = s.new()
	check(not bool(sim.tactics.forecast().given), "forecast_on false: no forecast")
	sim.alerts.clear()
	sim.tactics._tell_the_forecast()
	check(not sim.alerts.has("forecast"), "forecast_on false: no 'No forecast' alert either")
	# H11: a school Sim has no prepare_load, so a refused save is refused as ever
	check(not sim.has_method("prepare_load"), "the school's Sim has no town hook")
	check(not SaveGame.apply(sim, {}), "a save with nothing in it is refused")
	g.world.free()


func test_the_town_rules_answer_for_the_base() -> void:
	var t := _town()
	var sim = t.sim
	check(sim.is_one_house(), "the town")
	eq(sim.zombies.size(), 0, "nothing is seeded round a school that is not there")
	sim.start_run(1, 5)
	eq(sim.zombies.size(), 0, "a new run puts no dead at the school's corners")
	eq(sim.segments.size(), 0, "a town starts without wall sections")
	# before a claim: the base is nowhere, the rules are quiet
	check(not sim.posts_manned() and not sim._wanderers_rally() and not sim._in_yard(100.0, 90.0) and sim.dead_inside() == 0, "quiet before a claim")
	check(not sim.yard_open(), "no perimeter module: no outer wall to miss")
	var base := Fake.new()
	sim.base = base
	sim.houses = base
	eq(sim.base_center(), Vector2(100.0, 90.0), "the base's middle")
	eq(sim.yard_middle(), Vector2(101.0, 91.0), "the base's yard")
	check(sim._in_yard(100.0, 90.0) and not sim._in_yard(92.0, 90.0), "the yard is the base's rectangle")
	check(sim.inside_school(100.0, 90.0), "the house is the base's house")
	var z = sim.spawn(100.0, 90.0, "approach")
	var out = sim.spawn(60.0, 60.0, "wander")
	eq(sim.dead_inside(), 1, "one dead one in the yard")
	check(sim._dead_coming(), "an approaching one within THREAT_R of the compound is coming")
	out.state = "approach"
	z.state = "wander"
	check(not sim._dead_coming(), "one far from the compound is not")
	# the perimeter and the scenario
	var per := Fake.new()
	sim.perimeter = per
	sim.scenario = per
	check(not sim.yard_open(), "an outer wall stands")
	per.no_wall = true
	check(sim.yard_open(), "with no outer wall the doors are the wall: the yard is open")
	check(not sim._any_gate_open() and not sim._breached(), "the gate is shut")
	per.gate = true
	check(sim._any_gate_open() and sim._breached() and sim.yard_open(), "an open gate is a way in")
	var seg := Sim.Segment.new()
	seg.kind = "gate"
	check(sim._is_open_gate(seg), "a section of kind gate is the gate")
	seg.kind = "fence"
	check(not sim._is_open_gate(seg), "a fence is not")
	check(not sim._wanderers_rally() and not sim.posts_manned(), "no attack: wanderers stay wanderers and nobody mans the posts")
	per.attacks = true
	check(sim._wanderers_rally(), "the attacks are on: the bell rallies")
	sim.radio.alarm_on = true
	check(sim.posts_manned(), "the alarm mans the posts")
	t.world.free()


func test_the_nights_count_and_sweep_only_the_waves_dead() -> void:
	var t := _town()
	var sim = t.sim
	var field := Fake.new()
	sim.field = field
	var street = sim.spawn(50.0, 50.0, "wander")
	var wave = sim.spawn(60.0, 50.0, "approach")
	field.rec_of[street] = {"id": 1}
	eq(sim.zombies.size(), 2, "two dead")
	eq(sim.alive_for_cap(), 1, "the cap counts the wave's dead, not the street's")
	sim._dawn_sweep()
	eq(wave.state, "retreat", "the wave's dead go back to the city at dawn")
	eq(street.state, "wander", "the town's own stay")
	# the hunt rules of a place
	check(sim._hunt_allowed(), "the dead hunt at every hour")
	var p := Sim.Person.new()
	p.id = "ruth"
	street.state = "chase"
	street.hunt_id = String(p.id)
	check(sim._hunted(p), "a chase is a hunt")
	t.world.free()


func test_a_save_asks_the_town_first_and_gives_back_when_refused() -> void:
	var t := _town()
	var sim = t.sim
	var base := Fake.new()
	var per := Fake.new()
	sim.base = base
	sim.perimeter = per
	check(sim.has_method("prepare_load") and sim.has_method("restore_load"), "the town has the generic hook")
	check(not SaveGame.apply(sim, {}), "a refused save")
	eq(base.calls, ["prepare", "restore:before"], "the base is asked first and put back when the save is refused")
	eq(per.calls, ["prepare", "restore:before"], "the perimeter likewise")
	t.world.free()
