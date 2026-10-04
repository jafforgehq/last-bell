extends "res://tests/case.gd"
## The One House run (scripts/town/one_house.gd, assets/data/one_house.json): the solo start, the guide and the objective, the fourth voice, the first attack night and the end,
## and the save. The town is Helpers.town_game's small one; the modules of other packages that are not there yet are fakes that answer what the scenario asks of them.

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Helpers := preload("res://tests/helpers.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


## The clearing module as the scenario reads it: which rooms are open and clear, which houses have been entered.
class FakeClearing:
	extends RefCounted
	var revealed := {}
	var clear := {}
	var explored_ids: Array = []

	func is_revealed(r: int) -> bool:
		return revealed.has(r)

	func is_clear(r: int) -> bool:
		return clear.has(r)

	func explored() -> Array:
		return explored_ids

	func reveal(r: int, _why: String = "") -> bool:
		revealed[r] = true
		return true


## The search module as the scenario reads it.
class FakeSearch:
	extends RefCounted
	var looted := {}

	func is_looted(id: String) -> bool:
		return looted.has(id)


func _at(p) -> Vector2:
	return Vector2(p.x, p.y)


func _step(sim, n: int) -> void:
	for i in n:
		sim.update(1.0 / 30.0)


## A new One House run on the mini town. Free `world` when done.
func _run() -> Dictionary:
	var g := Helpers.town_game(1, {"blocks": 2})
	OneHouse.begin(g.sim, 1, 1)
	return g


## One of the survivors that the rescue module would bring: a person added with a made-up roster entry, and the scenario told.
func _join(sim, n: int) -> void:
	var def: Dictionary = sim.recruits.make_def(60 + n)
	var p = sim.add_person(def)
	sim.recruits.arrived.append(def)
	sim.scenario.on_survivor_joined(p, n)


## Every dead one of a house put down (they are woken first: the town's dead are records until the avatar is near).
func _kill_house(sim, h: int) -> void:
	sim.field.wake_house(h)
	for z in sim.zombies.duplicate():
		if z.state != "dying" and z.state != "dead" and sim.houses.house_at(z.x, z.y) == h:
			sim._hurt_zombie(z, 9999.0, 0.0, sim.avatar.player())


# ------------------------------------------------------------------------ tests --

func test_begin_is_one_person_a_small_stock_and_a_quiet_start() -> void:
	var g := _run()
	var sim = g.sim
	var run: Dictionary = OneHouse.data()
	var s = sim.scenario
	eq(sim.people.size(), 1, "one person")
	eq(sim.player_id, "ruth", "Ruth, the player")
	check(Vector2(sim.people[0].x, sim.people[0].y).distance_to(g.town.start.pos) < 2.0, "in the start house")
	for k in run.start.stock:
		near(float(sim.stock[k]), float(run.start.stock[k]), 0.001, "the stock of %s is the data's" % k)
	eq(sim.day, 1, "day 1")
	near(float(sim.hour), float(run.start.hour), 0.01, "at the data's hour")
	near(float(sim.min_per_sec), float(run.min_per_sec), 0.001, "the data's clock")
	check(sim.zombies.is_empty(), "none of the school's dead")
	check(not sim.waves.enabled and not sim.town.on and not sim.lots.on and not sim.streets.enabled and not sim.gate.enabled, "no waves, board, lots, streets or school gate")
	check(sim.recruits.small and sim.recruits.queue.is_empty(), "a small start with nobody to call")
	for name in run.modules_from_crew:
		eq(sim.get(name).enabled, 1 >= int(run.modules_from_crew[name]), "%s is as the table says for a crew of one" % name)
	check(not sim.is_demo() and not s.has_method("is_demo") and not s.has_method("after_step"), "it is not the demo and not Orientation Day")
	eq(s.stage(), "alone", "alone")
	check(not s.attacks_on() and not s.forecast_on(), "no attacks, no forecast")
	eq(s.guide().id, "walk", "the first lesson is to walk")
	eq(s.objective().id, "clear", "the objective is to clear the house")
	eq(s.rescued(), 0, "nobody rescued")
	g.world.free()


func test_the_guide_and_the_objective_follow_play() -> void:
	var g := _run()
	var sim = g.sim
	var s = sim.scenario
	sim.clearing = FakeClearing.new()
	sim.search = FakeSearch.new()
	var h: int = sim.houses.start_house()
	var rooms: Array = sim.houses.rooms_of(h)
	var me = sim.avatar.player()
	_step(sim, 2)
	# a few steps with the real hands: east, west, east, west (a room is not wide)
	for i in 120:
		sim.avatar.set_input(Vector2(1.0 if floori(i / 30.0) % 2 == 0 else -1.0, 0.0), _at(me) + Vector2(5.0, 0.0), false)
		sim.update(1.0 / 30.0)
	sim.avatar.set_input(Vector2.ZERO, Vector2.ZERO, false)
	_step(sim, 10)
	var gd: Dictionary = s.guide()
	check(gd.id == "walk" and gd.done, "walking a few steps ends the first lesson, shown as done for a moment")
	sim.t += 4.0
	eq(s.guide().id, "shoot", "then the next")
	sim.kills = 1
	_step(sim, 10)
	sim.t += 4.0
	eq(s.guide().id, "door", "a dead one put down: now the door")
	# two rooms open, all but one of them clear: the lesson that follows and the objective say how far it is
	sim.clearing.revealed[int(rooms[0])] = true
	sim.clearing.revealed[int(rooms[1])] = true
	for i in rooms.size() - 1:
		sim.clearing.clear[int(rooms[i])] = true
	_step(sim, 10)
	sim.t += 4.0
	var gc: Dictionary = s.guide()
	eq(gc.id, "clear", "the lesson is to clear the house")
	eq(gc.progress, "%d of %d rooms clear" % [rooms.size() - 1, rooms.size()], "with its count")
	var ob: Dictionary = s.objective()
	eq(ob.id, "clear", "the objective is the same")
	eq(ob.sub, gc.progress, "and says the same")
	eq(ob.step, rooms.size() - 1, "its step")
	check(typeof(ob.at) == TYPE_VECTOR2, "it points at the room that is not clear")
	# the house is clear: the claim
	sim.clearing.clear[int(rooms[rooms.size() - 1])] = true
	s.on_house_clear(h)
	eq(s.stage(), "cleared", "cleared")
	var oc: Dictionary = s.objective()
	eq(oc.id, "claim", "the objective is to claim it")
	check(typeof(oc.at) == TYPE_VECTOR2, "at the front door")
	_step(sim, 10)
	sim.t += 4.0
	eq(s.guide().id, "search", "a lesson done early is skipped when its turn comes: the search is next")
	var first_container = sim.houses.containers_of(h)[0]
	sim.search.looted[String(first_container.id)] = true
	_step(sim, 10)
	sim.t += 4.0
	eq(s.guide().id, "claim", "then the claim")
	s.on_claimed(h)
	eq(s.stage(), "claimed", "claimed")
	_step(sim, 10)
	sim.t += 4.0
	check(s.guide().is_empty(), "the six lessons are done and the guide has nothing more")
	var orr: Dictionary = s.objective()
	eq(orr.text, "Find survivors: 0 of 4", "now the survivors")
	eq([orr.step, orr.of], [0, 4], "counted")
	g.world.free()


func test_the_fourth_voice_makes_the_dead_come_and_the_crew_switches_the_modules() -> void:
	var g := _run()
	var sim = g.sim
	var s = sim.scenario
	# the real modules: the house cleared and claimed through clearing and base, then four survivors found, talked to and sent ahead through rescue
	check(OneHouse.stage_to(sim, "claimed"), "staged to the claim")
	eq(s.stage(), "claimed", "claimed")
	check(sim.base.claimed, "by the base module")
	Helpers.at(sim, 2, 10.0)
	var recs: Array = sim.rescue.list()
	var told := []
	for i in 4:
		if i < recs.size():
			# (the mini town has two of the twelve: the rescue module does these)
			var rec: Dictionary = recs[i]
			_kill_house(sim, int(rec.house))
			sim.clearing.reveal(int(rec.room), "test")
			_step(sim, 10)
			check(not sim.rescue.talk(String(rec.id)).is_empty(), "%s can be talked to" % rec.id)
			var answer: Dictionary = sim.rescue.choose(String(rec.id), "come")
			check(bool(answer.ok) and bool(answer.joined), "%s comes: %s" % [rec.id, str(answer.get("why", ""))])
			var guard := 0
			while sim.rescue.arrived_count() < i + 1 and guard < 60:
				sim.fast_forward(10.0)
				guard += 1
		else:
			_join(sim, i + 1)
		eq(s.rescued(), i + 1, "the scenario counts %d" % (i + 1))
		told.append([sim.briefing.enabled, sim.relations.enabled])
		if i == 2:
			check(not s.attacks_on() and not s.forecast_on() and not sim.waves.enabled, "three voices: the dead do not come")
	eq(told[0], [false, false], "two people: no briefing")
	eq(told[1], [true, false], "three: the briefing, not relations")
	eq(told[2], [true, true], "four: relations too")
	check(s.attacks_on() and s.forecast_on() and sim.waves.enabled, "the fourth: attacks, forecast, waves")
	eq(s.stage(), "fortify", "fortify")
	var types: Array = []
	var banner := ""
	for e in sim.events:
		types.append(String(e.type))
		if e.type == "banner" and String(e.text) == "Four voices on the radio":
			banner = String(e.sub)
	check(types.has("attacks_on"), "the event says so")
	eq(banner, "The dead will come tonight", "and the banner")
	eq(s.objective().id, "fortify", "fortify before dark")
	near(s.night_mult(2), float(OneHouse.data().night.first), 0.001, "the first night is the data's size")
	check(s.night_mult(3) > s.night_mult(2), "and the next a little more")
	eq(s.big_night_for(2), {}, "an ordinary night")
	check(s.total_days() > 2, "the run is longer than the night")
	# people lost: the crew falls below three and the community modules go off again
	for i in range(1, sim.people.size() - 1):
		sim.people[i].dead = true
	_step(sim, 10)
	check(not sim.briefing.enabled and not sim.relations.enabled, "two left: the community modules are off")
	g.world.free()
	# a fourth voice after the cutoff hour: the first night is tomorrow's
	var late := _run()
	var ls = late.sim.scenario
	Helpers.at(late.sim, 2, 18.0)
	for n in 4:
		_join(late.sim, n + 1)
	check(not ls.attacks_on() and not late.sim.waves.enabled, "tonight is quiet")
	Helpers.at(late.sim, 3, 8.0)
	_step(late.sim, 10)
	check(ls.attacks_on() and late.sim.waves.enabled, "tomorrow night is the first")
	late.world.free()


func test_the_first_attack_night_ends_the_run() -> void:
	# a colony game with the school's wall as the stub base and four people made up as the survivors: the sim's own defenders
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	OneHouse.begin(sim, 1, 5)
	eq(sim.people.size(), 1, "the roster is cut to Ruth")
	check(OneHouse.stage_to(sim, "night"), "staged to the night")
	var s = sim.scenario
	eq(s.stage(), "fortify", "fortify")
	eq(s.rescued(), 4, "four rescued")
	check(s.attacks_on() and sim.waves.enabled, "the dead come")
	var first_day: int = sim.day
	var guard := 0
	while sim.over == "" and guard < 40:
		sim.fast_forward(60.0 * 14.0)
		guard += 1
	eq(sim.over, "victory", "the night is held at the dawn")
	eq(s.stage(), "held", "held")
	check(sim.day > first_day, "a day later")
	var types: Array = []
	for e in sim.events:
		types.append(String(e.type))
	check(types.has("held") and types.has("over"), "the events")
	var card: Dictionary = s.end_card()
	eq(card.stats.size(), 6, "six numbers on the card")
	eq(card.stats[0], ["Nights held", "1"], "one night held")
	eq(s.report().nights, 1, "the report says so")
	# the other end: nobody left
	var lost := Sim.new(data, world, FxNull.new())
	OneHouse.begin(lost, 1, 5)
	lost.people[0].dead = true
	_step(lost, 10)
	eq(lost.over, "defeat", "nobody left is a defeat")
	world.free()


func test_a_save_keeps_the_stage_the_counters_and_the_switches() -> void:
	var g := _run()
	var sim = g.sim
	check(OneHouse.stage_to(sim, "fourth"), "staged to the fourth voice")
	var s = sim.scenario
	eq(s.stage(), "fortify", "fortify")
	eq(sim.people.size(), 5, "Ruth and four")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	check(OneHouse.is_save(saved), "the save says it is a One House save")
	eq(OneHouse.town_seed_of(saved), 1, "and which town")
	check(not OneHouse.is_save({"modules": {"scenario": {}}}), "another save is not")
	var f := Helpers.town_game(1, {"blocks": 2})
	OneHouse.install(f.sim)
	check(SaveGame.apply(f.sim, saved), "the save is read")
	var t = f.sim.scenario
	eq(t.stage(), "fortify", "the stage is kept")
	eq(t.rescued(), 4, "the rescued")
	check(t.attacks_on() and f.sim.waves.enabled, "the dead still come")
	eq(f.sim.people.size(), 5, "the people")
	near(float(f.sim.min_per_sec), 2.0, 0.001, "the clock")
	check(f.sim.briefing.enabled and f.sim.relations.enabled and not f.sim.policies.enabled, "the modules are as the crew says")
	eq(t.night_mult(3), s.night_mult(3), "the nights are the same size")
	eq(t.guide().is_empty(), s.guide().is_empty(), "the guide is where it was")
	g.world.free()
	f.world.free()
