extends "res://tests/case.gd"
## Barks (scripts/sim/barks.gd, assets/data/barks.json): the short lines people say when
## something happens. Rules only: each one is a {"type": "bark", "who", "text", "context"}
## event. At most one bark a person every 25 seconds and one anywhere every 6, none while
## the game is over or in the tutorial, none from the dead, the down or the away; a line is
## never the one they used last time; the dead are spoken of by the others (`epitaph`).

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")
const Skills := preload("res://scripts/sim/skills.gd")

const PEOPLE := ["ruth", "dez", "ana", "marcus", "walt", "hector"]
## The contexts with at least four lines each, and the two that are written differently.
const FIRST_EIGHT := ["bell", "kill_streak", "wounded", "low_ammo", "friend_down", "breach", "dawn", "skill_up"]
const ALL := ["bell", "kill_streak", "wounded", "low_ammo", "friend_down", "breach", "dawn", "skill_up", "breakdown", "epitaph"]


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## A quiet day on day 5 (so breakdowns are possible): no dead about, no nights.
func _quiet(hour: float = 9.0, seed_value: int = 7) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 5
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.events.clear()
	sim.t = 1000.0
	return g


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


func _data() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/barks.json"))
	return parsed if parsed is Dictionary else {}


func _barks(sim) -> Array:
	var out: Array = []
	for e in sim.events:
		if e.type == "bark":
			out.append(e)
	return out


func _said(sim, context: String) -> Array:
	var out: Array = []
	for e in _barks(sim):
		if e.context == context:
			out.append(e)
	return out


## Sends someone into a breakdown (day 5, standard).
func _break(sim, p) -> void:
	sim.morale.set_value(p, 40.0)
	sim.morale.shock(p, -35.0, "Too much")


# ------------------------------------------------------------------- the data --

func test_everyone_has_the_lines_the_plan_asks_for() -> void:
	var data := _data()
	eq(data.keys().size(), 6, "six people")
	var seen := {}
	for id in PEOPLE:
		check(data.has(id), "%s has lines" % id)
		var mine: Dictionary = data.get(id, {})
		for ctx in FIRST_EIGHT:
			check(mine.get(ctx, []).size() >= 4, "%s: at least four lines for %s" % [id, ctx])
		check(mine.get("breakdown", []).size() >= 3, "%s: lines for a breakdown" % id)
		check(mine.get("epitaph", []).size() >= 2, "%s: at least two epitaphs" % id)
		for ctx in mine:
			check(ALL.has(ctx), "%s: %s is a context the rules know" % [id, ctx])
			for line in mine[ctx]:
				check(typeof(line) == TYPE_STRING, "%s/%s: a line is text" % [id, ctx])
				var text := String(line)
				check(text.length() >= 8 and text.length() <= 90, "%s/%s: short enough and not empty: %s" % [id, ctx, text])
				check(text == text.strip_edges(), "%s: no stray spaces: %s" % [id, text])
				for i in text.length():
					if text.unicode_at(i) > 126:
						failures.append("%s: a character the fonts may lack in: %s" % [id, text])
						break
				check(not seen.has(text), "%s: a line is only said by one person: %s" % [id, text])
				seen[text] = id
				for banned in ["zombie", "undead", "apocalypse", "walking dead"]:
					check(not text.to_lower().contains(banned), "%s: no '%s' in: %s" % [id, banned, text])
	var epitaph_count := 0
	for id in data:
		epitaph_count += data[id].get("epitaph", []).size()
	check(epitaph_count >= 12, "a dozen epitaphs or more")


# ------------------------------------------------------------------- saying --

func test_say_adds_a_bark_event_with_one_of_their_lines() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	sim.barks.say(ruth, "bell")
	var got := _barks(sim)
	eq(got.size(), 1, "one bark")
	if got.size() == 1:
		eq(got[0].who, "ruth", "Ruth said it")
		eq(got[0].context, "bell", "for the bell")
		check(_data().ruth.bell.has(got[0].text), "and it is one of her bell lines: %s" % got[0].text)
		eq(got[0].keys().size(), 4, "with a type, a speaker, the words and the context")
	g.world.free()


func test_a_person_does_not_say_the_line_they_said_last_time() -> void:
	var g := _quiet()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var spoken: Array = []
	for i in 14:
		sim.t += 30.0
		sim.barks.say(dez, "bell")
	for e in _barks(sim):
		spoken.append(e.text)
	eq(spoken.size(), 14, "he spoke each time")
	for i in range(1, spoken.size()):
		check(spoken[i] != spoken[i - 1], "line %d is not the one before it: %s" % [i, spoken[i]])
	var first_five: Dictionary = {}
	for i in 5:
		first_five[spoken[i]] = true
	eq(first_five.size(), 5, "and all five lines are used before any comes round again")
	g.world.free()


func test_a_person_speaks_at_most_once_in_twenty_five_seconds() -> void:
	var g := _quiet()
	var sim = g.sim
	var ana = _person(sim, "Ana")
	sim.t = 100.0
	sim.barks.say(ana, "bell")
	sim.t = 110.0
	sim.barks.say(ana, "dawn")
	sim.t = 124.9
	sim.barks.say(ana, "dawn")
	eq(_barks(sim).size(), 1, "nothing more within 25 seconds")
	sim.t = 125.0
	sim.barks.say(ana, "dawn")
	eq(_barks(sim).size(), 2, "and again at 25")
	g.world.free()


func test_nobody_speaks_more_than_once_in_six_seconds() -> void:
	var g := _quiet()
	var sim = g.sim
	sim.t = 100.0
	sim.barks.say(_person(sim, "Ruth"), "bell")
	sim.t = 103.0
	sim.barks.say(_person(sim, "Dez"), "bell")
	eq(_barks(sim).size(), 1, "Dez has to wait")
	sim.t = 105.9
	sim.barks.say(_person(sim, "Dez"), "bell")
	eq(_barks(sim).size(), 1, "still")
	sim.t = 106.0
	sim.barks.say(_person(sim, "Dez"), "bell")
	eq(_barks(sim).size(), 2, "and at six he may")
	g.world.free()


func test_the_dead_the_down_and_the_away_say_nothing() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var dez = _person(sim, "Dez")
	var ana = _person(sim, "Ana")
	ruth.dead = true
	dez.downed = true
	ana.away = {"kind": "party"}
	for p in [ruth, dez, ana]:
		sim.t += 100.0
		sim.barks.say(p, "bell")
	eq(_barks(sim).size(), 0, "no one of the three spoke")
	sim.t += 100.0
	sim.barks.say(_person(sim, "Walt"), "bell")
	eq(_barks(sim).size(), 1, "Walt can")
	sim.over = "defeat"
	sim.t += 100.0
	sim.barks.say(_person(sim, "Hector"), "bell")
	eq(_barks(sim).size(), 1, "and nobody once the game is over")
	g.world.free()


func test_nothing_is_said_in_the_tutorial() -> void:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	Orientation.begin(sim)
	sim.events.clear()
	sim.t = 500.0
	sim.barks.say(_person(sim, "Ruth"), "bell")
	sim.barks.on_bell()
	sim.medical.add_wound(_person(sim, "Walt"), "scratch")
	eq(_barks(sim).size(), 0, "no bark in Orientation Day")
	world.free()


func test_a_context_without_lines_and_a_missing_person_are_quietly_ignored() -> void:
	var g := _quiet()
	var sim = g.sim
	sim.barks.say(_person(sim, "Ruth"), "nonsense")
	sim.barks.say(null, "bell")
	eq(_barks(sim).size(), 0, "nothing")
	g.world.free()


func test_saying_things_does_not_touch_the_rules_dice() -> void:
	var g := _quiet()
	var sim = g.sim
	var state: int = sim.rng.state
	for p in sim.people:
		sim.t += 100.0
		sim.barks.say(p, "bell")
	sim.barks.on_bell()
	sim.barks.on_low_ammo()
	eq(sim.rng.state, state, "the run's random numbers are where they were")
	g.world.free()


# ------------------------------------------------------------ where they happen --

func test_the_bell_makes_someone_say_something() -> void:
	var g := _quiet(18.9)
	var sim = g.sim
	sim.t = 10.0
	Helpers.run(sim, 10.0)
	check(sim.bell_rung, "the bell has rung")
	var got := _said(sim, "bell")
	eq(got.size(), 1, "one person says something about it")
	if got.size() == 1:
		check(_data()[got[0].who].bell.has(got[0].text), "from their own bell lines")
	g.world.free()


func test_five_kills_in_a_minute_are_a_streak() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	for i in 4:
		sim._hurt_zombie(sim.spawn(marcus.x + 8.0, marcus.y, "wander"), 1000.0, 0.0, marcus)
		sim.t += 5.0
	eq(_said(sim, "kill_streak").size(), 0, "four are not")
	sim._hurt_zombie(sim.spawn(marcus.x + 8.0, marcus.y, "wander"), 1000.0, 0.0, marcus)
	var got := _said(sim, "kill_streak")
	eq(got.size(), 1, "the fifth is")
	if got.size() == 1:
		eq(got[0].who, "marcus", "he says so")
	# the count starts again, and a slow five is no streak
	var h := _quiet(22.0)
	var s2 = h.sim
	var m2 = _person(s2, "Marcus")
	for i in 5:
		s2._hurt_zombie(s2.spawn(m2.x + 8.0, m2.y, "wander"), 1000.0, 0.0, m2)
		s2.t += 20.0
	eq(_said(s2, "kill_streak").size(), 0, "five kills over eighty seconds are not a streak")
	g.world.free()
	h.world.free()


func test_a_good_shot_is_not_heard_boasting_all_night() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	var walt = _person(sim, "Walt")
	var heard := 0
	for round in 3:
		for i in 5:
			sim._hurt_zombie(sim.spawn(walt.x + 8.0, walt.y, "wander"), 1000.0, 0.0, walt)
			sim.t += 1.0
		heard = _said(sim, "kill_streak").size()
		sim.t += 29.0   # half a minute between streaks
	eq(heard, 1, "three streaks in a minute and a half, and he is heard once (the same thing is said again after two minutes at the soonest)")
	sim.t += 120.0
	for i in 5:
		sim._hurt_zombie(sim.spawn(walt.x + 8.0, walt.y, "wander"), 1000.0, 0.0, walt)
		sim.t += 1.0
	eq(_said(sim, "kill_streak").size(), 2, "and again once the two minutes are up")
	g.world.free()


func test_a_wound_makes_the_wounded_person_say_so() -> void:
	var g := _quiet()
	var sim = g.sim
	sim.medical.add_wound(_person(sim, "Hector"), "scratch")
	var got := _said(sim, "wounded")
	eq(got.size(), 1, "one bark")
	if got.size() == 1:
		eq(got[0].who, "hector", "from Hector")
		check(_data().hector.wounded.has(got[0].text), "one of his lines")
	g.world.free()


func test_low_ammo_is_noticed() -> void:
	var g := _quiet()
	var sim = g.sim
	sim.stock.ammo = 40.0
	Helpers.run(sim, 1.0)
	check(sim.alerts.has("low-ammo"), "the alert is raised")
	var got := _said(sim, "low_ammo")
	eq(got.size(), 1, "and somebody says it too")
	if got.size() == 1:
		check(_data()[got[0].who].low_ammo.has(got[0].text), "in their words")
	g.world.free()


func test_a_friend_going_down_is_called_out_by_a_friend() -> void:
	var g := _quiet()
	var sim = g.sim
	var marcus = _person(sim, "Marcus")
	marcus.hp = 0.0
	sim.medical.on_downed(marcus, "bite")
	var got := _said(sim, "friend_down")
	eq(got.size(), 1, "one bark")
	if got.size() == 1:
		check(["ruth", "walt"].has(got[0].who), "from Ruth or Walt, who know him: %s" % got[0].who)
	var h := _quiet()
	var s2 = h.sim
	var dez = _person(s2, "Dez")
	dez.hp = 0.0
	s2.medical.on_downed(dez, "bite")
	var got2 := _said(s2, "friend_down")
	eq(got2.size(), 1, "Dez going down")
	if got2.size() == 1:
		eq(got2[0].who, "hector", "is called out by Hector")
	g.world.free()
	h.world.free()


func test_a_breach_is_called_out() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	sim._damage_segment(sim.segments[4], 1000.0)
	var got := _said(sim, "breach")
	eq(got.size(), 1, "one bark")
	if got.size() == 1:
		check(_data()[got[0].who].breach.has(got[0].text), "in their words")
	g.world.free()


func test_surviving_the_night_is_remarked_on_at_dawn() -> void:
	var g := _quiet(5.4)
	var sim = g.sim
	Helpers.run(sim, 5.0)
	eq(sim.phase, "dawn", "it is dawn")
	var got := _said(sim, "dawn")
	eq(got.size(), 1, "somebody says so, once")
	Helpers.run(sim, 5.0)
	eq(_said(sim, "dawn").size(), 1, "and not again")
	g.world.free()


func test_a_better_skill_is_remarked_on_by_the_one_who_gained_it() -> void:
	var g := _quiet()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	for i in ceili(float(Skills.KINDS.kills.per) - Skills.EPS):   # the kills that make a point
		sim.skills.credit(ruth, "kills", 1.0)
	var got := _said(sim, "skill_up")
	eq(got.size(), 1, "one bark")
	if got.size() == 1:
		eq(got[0].who, "ruth", "from Ruth")
	g.world.free()


func test_a_breakdown_is_heard() -> void:
	var g := _quiet(22.0)
	var sim = g.sim
	var walt = _person(sim, "Walt")
	_break(sim, walt)
	var got := _said(sim, "breakdown")
	eq(got.size(), 1, "one bark")
	if got.size() == 1:
		eq(got[0].who, "walt", "from Walt")
		check(_data().walt.breakdown.has(got[0].text), "one of his")
	g.world.free()


func test_the_dead_are_spoken_of_by_the_others() -> void:
	var g := _quiet()
	var sim = g.sim
	var ana = _person(sim, "Ana")
	eq(sim.barks.epitaph(ana), "", "nothing is said about the living")
	sim.medical.kill(ana, "bled out")
	var line: String = sim.barks.epitaph(ana)
	check(_data().ana.epitaph.has(line), "her epitaph is one of hers: %s" % line)
	var got := _said(sim, "epitaph")
	eq(got.size(), 1, "one of the others says it")
	if got.size() == 1:
		eq(got[0].text, line, "the same words")
		eq(got[0].who, "ruth", "Ruth, her friend")
	eq(sim.barks.epitaph(ana), line, "and it stays the same")
	g.world.free()


func test_someone_who_turns_is_spoken_of_too() -> void:
	var g := _quiet()
	var sim = g.sim
	var hector = _person(sim, "Hector")
	sim.medical._turn(hector)
	check(_data().hector.epitaph.has(sim.barks.epitaph(hector)), "an epitaph for Hector")
	var got := _said(sim, "epitaph")
	eq(got.size(), 1, "said by one")
	if got.size() == 1:
		eq(got[0].who, "dez", "Dez, his friend")
	g.world.free()


func test_a_death_is_remembered_even_when_nobody_can_say_it_now() -> void:
	var g := _quiet()
	var sim = g.sim
	for p in sim.people:
		if p.first != "Ana":
			p.downed = true
	sim.medical.kill(_person(sim, "Ana"), "bled out")
	eq(_said(sim, "epitaph").size(), 0, "nobody is able to speak")
	check(sim.barks.epitaph(_person(sim, "Ana")) != "", "but the line is kept for the dawn")
	g.world.free()


func test_an_important_bark_that_is_blocked_is_said_a_moment_later() -> void:
	var g := _quiet()
	var sim = g.sim
	sim.t = 100.0
	sim.barks.say(_person(sim, "Dez"), "bell")
	sim.t = 101.0
	var marcus = _person(sim, "Marcus")
	marcus.hp = 0.0
	sim.medical.on_downed(marcus, "bite")
	eq(_said(sim, "friend_down").size(), 0, "blocked for now")
	Helpers.run(sim, 6.0)
	eq(_said(sim, "friend_down").size(), 1, "said once the six seconds are over")
	g.world.free()


# --------------------------------------------------------- determinism and saves --

func _night_barks(seed_value: int) -> Array:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.stock.ammo = 1000.0
	Helpers.run_to_hour(sim, 19.0)
	Helpers.run(sim, 60.0)
	var out: Array = []
	for e in sim.events:
		if e.type == "bark":
			out.append([e.who, e.text, e.context])
	g.world.free()
	return out


func test_the_same_seed_and_orders_say_the_same_things() -> void:
	var a := _night_barks(31)
	var b := _night_barks(31)
	check(a.size() >= 2, "a night is not silent: %d barks" % a.size())
	eq(a, b, "the same barks, in the same order")


func test_barks_are_saved_and_a_loaded_game_goes_on_the_same() -> void:
	var a := Helpers.make(37, 1)
	var sim = a.sim
	sim.stock.ammo = 1000.0
	Helpers.run_to_hour(sim, 19.0)
	Helpers.run(sim, 25.0)
	var d := SaveGame.to_dict(sim)
	check(d.modules.has("barks"), "the module has a place in the save")
	var b := _bare()
	var c := _bare()
	check(SaveGame.apply(b.sim, d), "it applies")
	check(SaveGame.apply(c.sim, SaveGame.from_text(SaveGame.to_text(d))), "and from text")
	eq(b.sim.barks.save(), sim.barks.save(), "the loaded module holds the same")
	sim.events.clear()
	b.sim.events.clear()
	c.sim.events.clear()
	for second in 40:
		Helpers.run(sim, 1.0)
		Helpers.run(b.sim, 1.0)
		Helpers.run(c.sim, 1.0)
		if second == 10:
			for s in [sim, b.sim, c.sim]:
				s._damage_segment(s.segments[4], 1000.0)
	var x: Array = []
	var y: Array = []
	var z: Array = []
	for e in _barks(sim):
		x.append([e.who, e.text, e.context])
	for e in _barks(b.sim):
		y.append([e.who, e.text, e.context])
	for e in _barks(c.sim):
		z.append([e.who, e.text, e.context])
	eq(y, x, "the loaded game says the same things")
	eq(z, x, "and so does the one loaded from text")
	check(x.size() >= 1, "and they said something: %d" % x.size())
	a.world.free()
	b.world.free()
	c.world.free()


func test_an_epitaph_survives_a_save_and_an_old_save_gets_one() -> void:
	var a := _quiet()
	var sim = a.sim
	var ana = _person(sim, "Ana")
	sim.medical.kill(ana, "bled out")
	var line: String = sim.barks.epitaph(ana)
	var d := SaveGame.to_dict(sim)
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it applies")
	eq(b.sim.barks.epitaph(_person(b.sim, "Ana")), line, "the same line after a load")
	d.modules.erase("barks")
	var c := _bare()
	check(SaveGame.apply(c.sim, d), "a save from before barks loads")
	check(_data().ana.epitaph.has(c.sim.barks.epitaph(_person(c.sim, "Ana"))), "and the dead still have a line: %s" % c.sim.barks.epitaph(_person(c.sim, "Ana")))
	eq(c.sim.barks.epitaph(_person(c.sim, "Ruth")), "", "the living have none")
	d.modules["barks"] = {"last_said": {"ruth": "soon"}, "bag": 5, "queue": [1, {"who": "nobody"}], "memorial": {"ana": 5}, "rng_state": "abc"}
	var e := _bare()
	check(SaveGame.apply(e.sim, d), "damaged barks data does not refuse the save")
	check(_data().ana.epitaph.has(e.sim.barks.epitaph(_person(e.sim, "Ana"))), "the dead still have a line")
	a.world.free()
	b.world.free()
	c.world.free()
	e.world.free()
