extends "res://tests/case.gd"
## Briefing (round 25, S25.1: scripts/sim/briefing.gd): the base's concerns, ranked, from the sim's own state; the morning briefing (once a day at the first
## slow look from 06:30, day 2 on, never pausing); the evening debrief (what got done and what slipped); and what each station waits on. Avatar mode in the
## settlement game only.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


## A stand-in for the problems module: a jammed generator (the bench makes nothing) with its marker at the second stage.
class FakeProblems:
	extends RefCounted
	var jam := true

	func blocks(what: String) -> bool:
		return jam and what == "bench"

	func perf_mult(_p) -> float:
		return 1.0

	func mood_lines(_p) -> Array:
		return []

	func update(_dt) -> void:
		pass

	func open() -> Array:
		return [{"id": "p1", "kind": "jam"}] if jam else []

	func marks() -> Array:
		return [{"id": "p1", "kind": "jam", "at": Vector2(46.8, 28.2), "label": "Jam: 9 h left", "stage": 2, "pct": 0.5, "state": "idle"}] if jam else []


# ----------------------------------------------------------------- helpers --

func _game(day: int = 3, hour: float = 7.0) -> Dictionary:
	var g := Helpers.avatar_game(11, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.initiative.enabled = false
	Helpers.at(sim, day, hour)
	sim.events.clear()
	return g


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	return {"sim": sim, "world": world, "data": data}


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## The concern with this id ({} when it is not among them).
func _c(sim, id: String) -> Dictionary:
	for c in sim.briefing.concerns():
		if String(c.id) == id:
			return c
	return {}


## The unit of a stock: what one day of it costs the crew (so that a test sets "3.98 days" whatever the season's use).
func _per_day(sim, kind: String) -> float:
	return float(sim.stock[kind]) / float(sim.supplies.days_left(kind))


func _news(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == kind:
			out.append(e)
	return out


func _json(x) -> String:
	return JSON.stringify(x, "", true)


# ----------------------------------------------------------------- concerns --

func test_each_threshold_of_a_concern_has_two_sides() -> void:
	var g := _game()
	var sim = g.sim
	check(_c(sim, "water").is_empty() and _c(sim, "food").is_empty() and _c(sim, "ammo").is_empty() and _c(sim, "walls").is_empty(), "a well stocked base: nothing to say about the stores")
	# days of water and food: warn under 4, alarm under 2
	for kind in ["water", "food"]:
		var unit := _per_day(sim, kind)
		sim.stock[kind] = unit * 4.001
		check(_c(sim, kind).is_empty(), "%s: four days is fine" % kind)
		sim.stock[kind] = unit * 3.98
		eq([_c(sim, kind).get("level"), _c(sim, kind).get("text")], ["warn", "%s: 3 days left" % kind.capitalize()], "%s under four days" % kind)
		sim.stock[kind] = unit * 2.001
		eq(_c(sim, kind).get("level"), "warn", "%s: two days is a warning" % kind)
		sim.stock[kind] = unit * 1.99
		eq([_c(sim, kind).get("level"), _c(sim, kind).get("text")], ["alarm", "%s: 1 day left" % kind.capitalize()], "%s under two days" % kind)
		sim.stock[kind] = unit * 10.0
	# ammo against the bench's target: warn under 90, alarm under 40, and only while the bench would make more
	sim.stock.ammo = 90.0
	check(_c(sim, "ammo").is_empty(), "ammo: 90 is fine")
	sim.stock.ammo = 89.0
	eq([_c(sim, "ammo").get("level"), _c(sim, "ammo").get("text")], ["warn", "Ammo: 89"], "ammo under 90")
	sim.stock.ammo = 40.0
	eq(_c(sim, "ammo").get("level"), "warn", "ammo: 40 is a warning")
	sim.stock.ammo = 39.0
	eq(_c(sim, "ammo").get("level"), "alarm", "ammo under 40")
	sim.jobs.set_setting("bench", "ammo_target", 25)
	check(_c(sim, "ammo").is_empty(), "with the target under the stock the player has what they asked for")
	sim.jobs.set_setting("bench", "ammo_target", 300)
	sim.stock.ammo = 400.0
	# the lowest wall: warn under 70%, alarm under 50%
	var east = null
	for s in sim.segments:
		if s.id == 10:
			east = s
	east.hp = 294.5
	check(_c(sim, "walls").is_empty(), "walls: 70% is fine")
	east.hp = east.max_hp * 0.54
	eq([_c(sim, "walls").get("level"), _c(sim, "walls").get("text")], ["warn", "East wall at 54%"], "the wall under 70%")
	east.hp = east.max_hp * 0.499
	eq([_c(sim, "walls").get("level"), _c(sim, "walls").get("text")], ["alarm", "East wall at 49%"], "and under 50%")
	east.hp = east.max_hp
	# scrap under 12, medicine under 3
	sim.stock.scrap = 12.0
	check(_c(sim, "scrap").is_empty(), "scrap: 12 is fine")
	sim.stock.scrap = 11.0
	eq(_c(sim, "scrap").get("level"), "warn", "scrap under 12")
	sim.stock.scrap = 2.0
	eq(_c(sim, "scrap").get("level"), "alarm", "and under 3")
	sim.stock.scrap = 40.0
	sim.stock.meds = 3.0
	check(_c(sim, "meds").is_empty(), "medicine: 3 is fine")
	sim.stock.meds = 2.0
	eq(_c(sim, "meds").get("level"), "warn", "medicine under 3")
	sim.stock.meds = 10.0
	# the hurt and the empty desk
	_p(sim, "ana").bleeding = 1.0
	eq([_c(sim, "bleeding").get("level"), _c(sim, "bleeding").get("text")], ["warn", "Hurt: Ana (bleeding)"], "someone bleeding")
	_p(sim, "ana").downed = true
	eq(_c(sim, "bleeding").get("level"), "alarm", "someone down")
	_p(sim, "ana").downed = false
	_p(sim, "ana").bleeding = 0.0
	check(_c(sim, "bleeding").is_empty(), "and no more")
	sim.jobs.unassign(_p(sim, "walt"))
	var desk := _c(sim, "station:radio")
	check(String(desk.get("text", "")).begins_with("Nobody at the radio desk: ") and desk.get("level") == "warn" and desk.get("page") == "jobs" and desk.get("focus") == "radio", "the empty radio desk, with its price and where to mend it: %s" % str(desk))
	g.world.free()


func test_the_concerns_are_ranked_by_level_then_by_the_weight_of_a_priority() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.water = _per_day(sim, "water") * 3.9
	for s in sim.segments:
		if s.id == 10:
			s.hp = s.max_hp * 0.54
	var ids: Array = sim.briefing.concerns().map(func(c): return String(c.id))
	check(ids.find("walls") >= 0 and ids.find("water") >= 0 and ids.find("walls") < ids.find("water"), "two warnings, no priority: by id (%s)" % str(ids))
	sim.priorities.set_order(["water"])
	ids = sim.briefing.concerns().map(func(c): return String(c.id))
	check(ids.find("water") < ids.find("walls"), "Water first: its line goes above (%s)" % str(ids))
	near(float(_c(sim, "water").score), 23.0, 1.0e-9, "10 for a warning + 3 for the weight of the first")
	near(float(_c(sim, "walls").score), 20.0, 1.0e-9, "and the wall has no priority behind it")
	sim.priorities.set_order(["rest", "defence"])
	near(float(_c(sim, "walls").score), 22.0, 1.0e-9, "Defence second: +2")
	# an alarm stays above a warning whatever the priorities
	sim.stock.food = _per_day(sim, "food") * 1.0
	check(String(sim.briefing.concerns()[0].id) == "food", "an alarm is first")
	var asked: Array = sim.priorities.suggested()
	eq(asked.size(), 2, "two are suggested")
	eq(asked[0], "food", "the first from the top concern")
	check(asked.has("defence") or asked.has("water"), "and the next from the ones below")
	g.world.free()


# ------------------------------------------------------------------ the morning --

func test_the_briefing_comes_once_a_day_at_0630_and_never_when_it_should_not() -> void:
	var g := _game(1, 7.0)
	var sim = g.sim
	eq(sim.briefing.compose(), {}, "not on day 1")
	Helpers.at(sim, 2, 6.0)
	eq(sim.briefing.compose(), {}, "not before 06:30")
	Helpers.at(sim, 2, 22.0)
	eq(sim.briefing.compose(), {}, "not at night")
	Helpers.at(sim, 2, 6.5)
	sim.radio.alarm_on = true
	eq(sim.briefing.compose(), {}, "not under the alarm")
	sim.radio.alarm_on = false
	sim.scavenge.parties = [{"state": "in_place", "members": []}]
	eq(sim.briefing.compose(), {}, "not while the player is in a place")
	sim.scavenge.parties = []
	sim.briefing.enabled = false
	eq(sim.briefing.compose(), {}, "not in Orientation Day (switched off)")
	sim.briefing.enabled = true
	var morning: Dictionary = sim.briefing.compose()
	eq(int(morning.get("day", 0)), 2, "at 06:30 of day 2 it comes")
	check(morning.lines.size() >= 1 and morning.lines.size() <= 7, "with at most seven lines")
	eq(morning.order, [], "the order the priorities have")
	eq(morning.suggested.size(), 2, "and the two suggested")
	var heard := _news(sim, "briefing")
	eq(heard.size(), 1, "one News entry")
	eq([heard[0].text, heard[0].sub], ["Morning, day 2", String(morning.lines[0].text)], "'Morning, day 2', the top line under it")
	eq(heard[0].data.lines.size(), morning.lines.size(), "the lines are in the entry")
	var event := false
	for e in sim.events:
		if String(e.type) == "briefing" and int(e.day) == 2:
			event = true
	check(event, "and an event, for the card")
	eq(sim.briefing.current.get("day"), 2, "the card has what it shows")
	eq(sim.briefing.compose(), {}, "once a day")
	Helpers.at(sim, 2, 15.0)
	eq(sim.briefing.compose(), {}, "still once")
	Helpers.at(sim, 3, 14.0)
	eq(sim.briefing.compose(), {}, "too late in the day to be a morning")
	Helpers.at(sim, 3, 8.0)
	sim.briefing.update(10.0)
	eq(_news(sim, "briefing").size(), 2, "the next day at a slow look, from update, it comes again")
	g.world.free()
	# no avatar: nothing
	var plain := Helpers.make(3, 1, 5)
	Helpers.at(plain.sim, 3, 7.0)
	eq([plain.sim.briefing.compose(), plain.sim.briefing.concerns(), plain.sim.briefing.facilities()], [{}, [], []], "no avatar, no briefing, no concerns, no labels")
	plain.world.free()


# ------------------------------------------------------------------ the evening --

func test_the_debrief_counts_the_day_and_grades_what_was_asked_for() -> void:
	var g := _game(3, 6.5)
	var sim = g.sim
	var pr = sim.priorities
	var dez = _p(sim, "dez")
	sim.stock.water = _per_day(sim, "water") * 2.5
	sim.stock.food = _per_day(sim, "food") * 7.0
	sim.stock.ammo = 100.0
	var morning: Dictionary = sim.briefing.compose()
	check(not morning.is_empty() and not _c(sim, "water").is_empty(), "the morning says the water is low")
	# the day: someone sits at the bench for an hour, the water is found, the food goes down, a building is finished, walls are mended and then lost
	Helpers.at(sim, 3, 9.0)
	Helpers.seat(sim, dez)
	pr.look()
	pr.look()
	pr.set_order(["food", "defence", "rebuild", "rest"])
	sim.stock.water = _per_day(sim, "water") * 5.3
	sim.stock.food = _per_day(sim, "food") * 6.0
	sim.stock.ammo = 160.0
	sim.stock.scrap = 40.0
	check(sim.build.order("salvage_bench_home", "salvage_bench"), "a building is ordered")
	sim.build._finish(sim.build.plot("salvage_bench_home"))
	dez.stats["mended"] = float(dez.stats.get("mended", 0.0)) + 85.0
	for s in sim.segments:
		if s.id == 10:
			s.hp = s.max_hp * 0.6
	eq(sim.briefing.debrief(), {}, "not before the evening")
	Helpers.at(sim, 3, 18.8)
	var out: Dictionary = sim.briefing.debrief()
	check(not out.is_empty(), "at dusk less a quarter of an hour it says its piece")
	eq(int(out.day), 3, "of day 3")
	near(float(out.deltas.ammo), 60.0, 1.0e-6, "the ammo is up 60")
	near(float(out.deltas.water), snappedf(_per_day(sim, "water") * 2.8, 0.1), 0.15, "and the water by what was found")
	eq(out.built, ["Salvage bench"], "the building that was finished")
	near(float(out.mended), 85.0, 1.0e-6, "the hit points mended")
	eq(out.treated, 0, "nobody was treated")
	near(float(out.hours.get("bench", 0.0)), 1.0, 1.0e-6, "Dez worked the bench for an hour (two looks of half an hour)")
	var done := _join(out.done)
	var slipped := _join(out.slipped)
	check(done.contains("Rebuilding: finished the salvage bench"), "Rebuilding is done by the building: %s" % done)
	check(done.contains("Rest: nobody is worn"), "Rest: %s" % done)
	check(done.contains("Water: 5 days left"), "the water concern is done, in the words of now: %s" % done)
	check(slipped.contains("Food: down to 6.0 days (was 7.0)"), "Food slipped: %s" % slipped)
	check(slipped.contains("Defence: the walls fell to 60%"), "Defence slipped on the wall, not on the ammo: %s" % slipped)
	var entry: Dictionary = _news(sim, "debrief")[0]
	eq(entry.text, "Evening: %d done, %d slipped" % [out.done.size(), out.slipped.size()], "the News counts them")
	eq(entry.data.lines.size(), out.done.size() + out.slipped.size(), "its lines are the done ones, then the slipped ones")
	eq([entry.data.lines[0].level, entry.data.lines[entry.data.lines.size() - 1].level], ["ok", "warn"], "marked as such")
	eq(sim.briefing.debrief(), {}, "once a day")
	# the scavenging priority: an errand sent and home is done, none sent says why
	Helpers.at(sim, 4, 6.5)
	for s in sim.segments:
		if s.id == 10:
			s.hp = 0.0
	sim.briefing.compose()
	pr.set_order(["scavenge", "defence"])
	pr.last_why = {"day": 4, "why": "Nobody is free to go."}
	Helpers.at(sim, 4, 18.8)
	var evening4: Dictionary = sim.briefing.debrief()
	check(_join(evening4.slipped).contains("Scavenging: no errand went out (nobody is free to go)"), "no errand: the reason")
	check(_join(evening4.slipped).contains("Defence: the east wall is still down"), "a wall that is down and stays down is not 'held': %s" % _join(evening4.slipped))
	Helpers.at(sim, 5, 6.5)
	sim.briefing.compose()
	pr.last_errand = {"day": 5, "line": "Standing order: Dez and Ana set off for Pell's bakery (Scavenging)", "ids": ["dez", "ana"], "place": "bakery", "stock": "food", "names": ["Dez", "Ana"], "where": "Pell's bakery"}
	Helpers.at(sim, 5, 18.8)
	check(_join(sim.briefing.debrief().done).contains("Scavenging: Dez and Ana went to Pell's bakery and are home"), "an errand sent and home")
	# a morning that never came has no evening
	Helpers.at(sim, 6, 18.8)
	eq(sim.briefing.debrief(), {}, "no briefing, no debrief")
	g.world.free()


func _join(lines: Array) -> String:
	return "\n".join(lines.map(func(l): return String(l)))


# ----------------------------------------------------------------- facilities --

func test_each_station_says_what_it_waits_on() -> void:
	var g := _game(3, 10.0)
	var sim = g.sim
	var dez = _p(sim, "dez")
	var f := func(id: String) -> Dictionary:
		for e in sim.briefing.facilities():
			if String(e.id) == id:
				return e
		return {}
	var bench: Dictionary = f.call("bench")
	eq([bench.ok, bench.line], [true, "Workshop: ammo at its target"], "the bench has what it needs")
	check(bench.pos == Vector2(sim.jobs.station("bench").pos), "and stands at its worktable")
	sim.stock.ammo = 100.0
	eq(f.call("bench").line, "Workshop: making ammo", "ammo under the target, scrap and a hand: making ammo")
	sim.stock.scrap = float(sim.workshop.reserve())
	var wait: Dictionary = f.call("bench")
	eq([wait.ok, wait.bottleneck, wait.line, wait.fix], [false, "waiting on scrap", "Workshop: waiting on scrap", {"page": "map", "focus": ""}], "no scrap above the reserve")
	sim.stock.scrap = 40.0
	sim.jobs.unassign(dez)
	var empty: Dictionary = f.call("bench")
	eq([empty.ok, empty.bottleneck, empty.fix], [false, "nobody at the bench", {"page": "jobs", "focus": "bench"}], "nobody at the bench")
	sim.jobs.assign(dez, "bench")
	var real = sim.problems
	sim.problems = FakeProblems.new()
	var jam: Dictionary = f.call("bench")
	eq([jam.ok, jam.bottleneck, jam.fix], [false, "the generator is jammed", {"page": "base", "focus": "p1"}], "a jammed generator, and the Trouble list is where to go")
	var trouble := _c(sim, "problem:p1")
	eq([trouble.get("level"), trouble.get("text"), trouble.get("page")], ["alarm", "Jam: 9 h left", "base"], "and it is a concern at the second stage")
	sim.problems = real
	eq(f.call("garden").line, "Garden: nobody tending", "the beds have nobody")
	sim.jobs.assign(_p(sim, "ana"), "garden")
	eq([f.call("garden").ok, f.call("garden").line], [true, "Garden: growing food"], "and then someone")
	# the builders: nothing to build; a worn wall nobody mends; a worn wall and no scrap
	eq([f.call("builders").ok, f.call("builders").line], [true, "Builders: nothing to build"], "no site and no worn wall")
	for s in sim.segments:
		if s.id == 10:
			s.hp = s.max_hp * 0.4
	eq([f.call("builders").ok, f.call("builders").bottleneck], [false, "nobody on the Builders job"], "a worn wall and nobody on the job")
	sim.jobs.assign(_p(sim, "marcus"), "builders")
	sim.stock.scrap = 2.0
	eq(f.call("builders").bottleneck, "waiting on scrap", "the crew with no scrap to mend with")
	sim.stock.scrap = 40.0
	eq(f.call("builders").line, "Builders: mending the wall", "and with scrap")
	# the infirmary: a patient and no medicine, no one on duty
	sim.jobs.assign(_p(sim, "ana"), "infirmary")
	eq(f.call("infirmary").line, "Infirmary: no patients", "no patients")
	_p(sim, "walt").bleeding = 1.0
	sim.stock.meds = 0.0
	eq([f.call("infirmary").ok, f.call("infirmary").bottleneck, f.call("infirmary").fix.page], [false, "no medicine", "map"], "a patient and no medicine")
	sim.stock.meds = 6.0
	sim.jobs.unassign(_p(sim, "ana"))
	eq(f.call("infirmary").bottleneck, "nobody on duty", "a patient and nobody on duty")
	sim.jobs.assign(_p(sim, "ana"), "infirmary")
	eq(f.call("infirmary").line, "Infirmary: treating", "treated")
	# the desks
	sim.jobs.unassign(_p(sim, "walt"))
	eq([f.call("radio").bottleneck, f.call("radio").fix], ["nobody at the desk", {"page": "jobs", "focus": "radio"}], "the radio desk")
	sim.jobs.unassign(_p(sim, "marcus"))
	eq(f.call("watch").bottleneck, "nobody on watch", "the lookout post")
	check(f.call("salvage").is_empty(), "no salvage bench, no label")
	# the labels are the page's: the same list, and every line is "name: what"
	for e in sim.briefing.facilities():
		check(String(e.line).begins_with(String(e.name) + ": ") and (e.ok or String(e.line) == "%s: %s" % [e.name, e.bottleneck]), "%s says what it says" % e.id)
	Helpers.at(sim, 3, 22.0)
	eq([f.call("bench").ok, f.call("bench").line, f.call("radio").ok], [true, "Workshop: closed for the night", true], "at night nothing waits")
	g.world.free()


# --------------------------------------------------------------------- save --

func test_a_save_keeps_the_briefing_and_a_damaged_one_is_mended() -> void:
	var a := _game(3, 6.5)
	var sim = a.sim
	sim.stock.water = _per_day(sim, "water") * 2.5
	var morning: Dictionary = sim.briefing.compose()
	check(not morning.is_empty(), "a morning")
	var d := SaveGame.to_dict(sim)
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(SaveGame.to_text(d))), "it loads from text")
	var sb = b.sim.briefing
	eq(_json(sb.save()), _json(sim.briefing.save()), "the same state, key for key")
	eq(_json(sb.current), _json(sim.briefing.current), "the card has what it had")
	eq(sb.compose(), {}, "and the morning is not told again")
	Helpers.at(sim, 3, 18.8)
	Helpers.at(b.sim, 3, 18.8)
	var da: Dictionary = sim.briefing.debrief()
	var db: Dictionary = sb.debrief()
	check(not da.is_empty() and _json(da) == _json(db), "the evening is the same from the saved game")
	# a save from before is a fresh module; a damaged one is mended
	var fresh := _bare()
	var d2 := SaveGame.to_dict(sim)
	d2.modules.erase("briefing")
	check(SaveGame.apply(fresh.sim, d2), "a save from before loads")
	eq(fresh.sim.briefing.current, {}, "no briefing")
	sb.load_state({
		"current": 5, "snap": {"day": 2, "stock": {"ammo": NAN, "scrap": 1.0e12}, "built": {"p": "tents", "q": 7}, "mended": "lots", "walls": 9.0,
			"concerns": [{"id": "water", "level": "warn", "text": "Water", "priority": "water", "done": "ok"}, {"level": "warn"}, {"id": "x", "level": "nonsense"}, 4]},
		"composed_day": 9999, "debriefed_day": -3, "acc": INF,
	})
	eq(sb.current, {}, "a card that is not a dictionary is dropped")
	var snap: Dictionary = sb._snap
	check(is_finite(float(snap.stock.ammo)) and float(snap.stock.scrap) <= 1.0e6, "the numbers of the snapshot are finite and held to a range")
	eq(snap.built, {"p": "tents"}, "a building that is not a name is dropped")
	eq(snap.concerns.size(), 1, "and a concern that is not one")
	eq([float(snap.mended), float(snap.walls)], [0.0, 1.0], "a number that is not one is zero, one that is is held to its range (a share is at most one)")
	var saved: Dictionary = sb.save()
	eq([saved.composed_day, saved.debriefed_day, saved.acc], [3, 0, 0.0], "the days and the look are held to their range")
	sb.load_state({"current": {"day": 9999, "lines": [{"text": "x", "level": "warn"}]}, "last_debrief": {"day": "x"}})
	eq([sb.current, sb.last_debrief], [{}, {}], "a card or a debrief from a day that has not come is dropped")
	sb.load_state({"current": {"day": 2, "lines": [{"text": "Water: 3 days left", "level": "warn", "id": "water", "score": INF, "page": 7}, {"level": "warn"}, 5], "order": ["food", "bogus"], "suggested": 4}})
	eq([sb.current.day, sb.current.lines.size(), sb.current.lines[0].score, sb.current.lines[0].page, sb.current.order], [2, 1, 0.0, "", ["food"]], "a card is rebuilt from what is sound in it")
	sb.load_state({"snap": {"day": 99}})
	eq(sb._snap, {}, "a snapshot from the future is dropped")
	a.world.free()
	b.world.free()
	fresh.world.free()
