extends "res://tests/case.gd"
## The four dials (round 25, S25.2: scripts/sim/policies.gd, assets/data/policies.json): rations, work hours, scavenger boldness, strangers at the gate.
## Each dial's effect at its option, the defaults and the inactive game exactly neutral, weariness, the consequence lines, one change a dial a day, saves.
## (A handful of checks: the rules the other modules read, not the pages that show them.)

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const Helpers := preload("res://tests/helpers.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const TICK := 10.0


## A small start with Ruth as the player (Ruth, Dez, Marcus; Ana, Walt and Hector wait on the radio), day 3, 09:00, the other round 25 modules off, the
## storyteller and the waves off, a plenty of stores.
func _game(avatar: bool = true, seed_value: int = 7) -> Dictionary:
	var g: Dictionary = Helpers.avatar_game(seed_value, 3) if avatar else Helpers.make(seed_value, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	for m in ["briefing", "priorities", "problems", "dilemmas"]:
		if sim.get(m) != null:
			sim.get(m).enabled = false
	Helpers.at(sim, 3, 9.0)
	sim.supplies.meal_day = 3
	sim.supplies.meals_done = 3
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 80.0, "water": 90.0, "meds": 10.0}
	sim.events.clear()
	return g


func _bare() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	return {"sim": Sim.new(data, world, FxNull.new()), "world": world}


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _free(g: Dictionary) -> void:
	g.world.free()


## The last News entry of the kind "policy" ({} if none).
func _policy_news(sim) -> Dictionary:
	for i in range(sim.radio.news.size() - 1, -1, -1):
		if String(sim.radio.news[i].kind) == "policy":
			return sim.radio.news[i]
	return {}


## `n` slow looks, with whoever is named at work (`work` words by person id: "bench" at work, "rest" at a rest spot, "" idle).
func _looks(sim, n: int, work := {}) -> void:
	for _i in n:
		for p in sim.people:
			p.work = String(work.get(p.id, ""))
		sim.policies.update(TICK)


# ----------------------------------------------------------------- the data --

func test_the_data_carries_the_numbers_of_the_plan_and_every_option_has_its_words() -> void:
	var g := _game()
	var pol = g.sim.policies
	var table := {
		"rations": {"full": {"food": 1.0, "water": 1.0, "mood": 0.0, "perf": 1.0, "fever": 0.0}, "half": {"food": 0.75, "water": 0.85, "mood": -3.0, "perf": 1.0, "fever": 0.01},
			"hungry": {"food": 0.5, "water": 0.7, "mood": -8.0, "perf": 0.92, "fever": 0.03}},
		"hours": {"normal": {"work": 1.0, "mood": 0.0}, "overtime": {"work": 1.25, "mood": -3.0}},
		"boldness": {"careful": {"loot": 0.5, "wound": 1.2, "loss_per_danger": 0.015, "clear": -0.3, "max_danger": 1}, "bold": {"loot": 0.8, "wound": 2.0, "loss_per_danger": 0.05, "clear": -0.1}},
	}
	for dial in table:
		for option in table[dial]:
			var o: Dictionary = pol._opt(dial, option)
			for k in table[dial][option]:
				near(float(o.get(k, -99.0)), float(table[dial][option][k]), 1e-9, "%s %s %s" % [dial, option, k])
	var w: Dictionary = pol._wear()
	near(float(w.gain_per_h), 2.5, 1e-9, "weariness gained an hour at work")
	near(float(w.decay_per_h), 0.6, 1e-9, "and shed")
	near(float(w.worn.at), 60.0, 1e-9, "worn out at")
	near(float(w.spent.at), 85.0, 1e-9, "spent at")
	check(pol._opt("boldness", "usual").get("loot") == null, "usual carries no numbers: it is scavenge's own constants")
	for dial in pol.OPTIONS:
		for option in pol.OPTIONS[dial]:
			var d: Dictionary = pol.describe(dial, option)
			check(String(d.name) != "" and String(d.blurb) != "" and not (d.pros as Array).is_empty() and not (d.cons as Array).is_empty(), "%s %s has its words" % [dial, option])
			check(String(pol._opt(dial, option).get("news", "")) != "", "%s %s has its News line" % [dial, option])
	eq(pol.describe("rations", "nonsense").name, "", "an option it does not know has no words")
	_free(g)


# ------------------------------------------------------------------ neutrality --

## The defaults are today's game exactly (each reading with the module on equals the module off), and a game with no avatar ignores even a dial that is
## forced to its extreme; the module draws no random number in three game days of looks.
func test_the_defaults_and_the_inactive_game_are_exactly_neutral() -> void:
	var g := _game()
	var sim = g.sim
	var pol = sim.policies
	var base := {"loot": 0.6, "wound": 1.5, "loss_per_danger": 0.03, "clear": -0.2, "extras": false}
	var readings := func() -> Array:
		var out: Array = [sim.supplies.days_left("food"), sim.supplies.days_left("water"), sim.scavenge.errand_terms()]
		for p in sim.people:
			out.append([sim.perf(p), sim.morale.target(p), sim.traits.mult(p, "craft"), sim.traits.mult(p, "repair"), sim.traits.mult(p, "garden"), sim.traits.mult(p, "aim")])
		return out
	var on: Array = readings.call()
	pol.enabled = false
	var off: Array = readings.call()
	pol.enabled = true
	eq(on, off, "with every dial at its default the readings are the game without the module")
	eq(pol.current, pol.DEFAULTS, "the defaults")
	check(is_same(pol.errand_terms(base), base), "usual boldness hands back the base itself")
	eq([pol.ration_mult("food"), pol.ration_mult("water"), pol.work_mult(null, "garden"), pol.perf_mult(_p(sim, "dez")), pol.mood_lines(_p(sim, "dez")), pol.errand_limit("pharmacy"),
		pol.strangers_call_ok(), pol.arrival_delay_days(), pol.caught_at_gate({"id": "mia", "name": "Mia Hale", "bitten": true}), pol.fever_risk()],
		[1.0, 1.0, 1.0, 1.0, [], "", true, 0, false, 0.0], "every hook says its neutral value")
	# three game days of looks at the defaults change nothing, and the random source is not touched
	var state: int = sim.rng.state
	_looks(sim, 144, {"dez": "bench", "marcus": "hammer"})
	eq(sim.rng.state, state, "no random number was drawn")
	for id in pol.weary:
		near(float(pol.weary[id]), 0.0, 1e-12, "%s is no wearier at the defaults" % id)
	# a game with no avatar: the dials forced to their extreme change nothing at all
	var n := _game(false)
	var off_pol = n.sim.policies
	off_pol.current = {"rations": "hungry", "hours": "overtime", "boldness": "bold", "strangers": "turn_away"}
	check(not off_pol.active(), "no avatar: not active")
	eq([off_pol.ration_mult("food"), off_pol.ration_mult("water"), off_pol.work_mult(_p(n.sim, "dez"), "craft"), off_pol.perf_mult(_p(n.sim, "dez")), off_pol.mood_lines(_p(n.sim, "dez")),
		off_pol.errand_limit("pharmacy"), off_pol.strangers_call_ok(), off_pol.arrival_delay_days(), off_pol.fever_risk()], [1.0, 1.0, 1.0, 1.0, [], "", true, 0, 0.0], "inactive: neutral")
	check(is_same(off_pol.errand_terms(base), base), "inactive: the base terms")
	check(not off_pol.set_dial("rations", "half").ok, "and a dial cannot be set")
	var w: Dictionary = n.sim.policies.weary.duplicate()
	_looks(n.sim, 30, {"dez": "bench"})
	eq(n.sim.policies.weary, w, "and no weariness is counted")
	_free(g)
	_free(n)


# -------------------------------------------------------------------- rations --

func test_rations_stretch_the_stores_and_cost_mood_and_work() -> void:
	var g := _game()
	var sim = g.sim
	var pol = sim.policies
	var dez = _p(sim, "dez")
	var full_days: float = sim.supplies.days_left("food")
	var full_water: float = sim.supplies.days_left("water")
	var eaten := func() -> Array:
		sim.stock.food = 80.0
		sim.stock.water = 90.0
		sim.supplies._serve_meal()
		return [80.0 - float(sim.stock.food), 90.0 - float(sim.stock.water)]
	var full_meal: Array = eaten.call()
	check(float(full_meal[0]) > 0.0 and float(full_meal[1]) > 0.0, "a meal takes food and water")
	var mood_before: float = sim.morale.value(dez)
	var target_before: float = sim.morale.target(dez)
	var perf_before: float = sim.perf(dez)
	var r: Dictionary = pol.set_dial("rations", "half")
	check(r.ok, "half rations can be set: %s" % str(r))
	eq(r.line, "Rations: half. Everyone eats a quarter less.", "and says what it does")
	var news := _policy_news(sim)
	eq(news.get("text"), r.line, "the News says it")
	eq(news.get("data", {}).get("dial"), "rations", "with its dial")
	var half_meal: Array = eaten.call()
	near(float(half_meal[0]) / float(full_meal[0]), 0.75, 1e-9, "a meal takes three quarters of the food")
	near(float(half_meal[1]) / float(full_meal[1]), 0.85, 1e-9, "and 85% of the water")
	sim.stock.food = 80.0
	sim.stock.water = 90.0
	near(sim.supplies.days_left("food"), full_days / 0.75, 1e-9, "the food's days stretch")
	near(sim.supplies.days_left("water"), full_water / 0.85, 1e-9, "and the water's")
	eq(pol.mood_lines(dez), [{"label": "Half rations", "value": -3.0}], "a standing mood line")
	near(sim.morale.target(dez), target_before - 3.0, 1e-9, "the mood heads 3 lower")
	near(sim.morale.value(dez), mood_before - 3.0, 1e-9, "and drops by the same at once")
	near(sim.perf(dez), perf_before, 1e-9, "half rations do not slow the work")
	check(sim.events.any(func(e): return e.type == "policy" and e.dial == "rations" and e.option == "half"), "the event")
	Helpers.at(sim, 4, 9.0)
	var h: Dictionary = pol.set_dial("rations", "hungry")
	check(h.ok, "hungry")
	eq(pol.mood_lines(dez), [{"label": "Hungry on purpose", "value": -8.0}], "its mood line")
	near(sim.morale.value(dez), mood_before - 8.0, 1e-9, "the shock is the difference between the two lines (-5 more)")
	near(sim.perf(dez), perf_before * 0.92, 1e-9, "work and aim 8% worse")
	var hungry_meal: Array = eaten.call()
	near(float(hungry_meal[0]) / float(full_meal[0]), 0.5, 1e-9, "half the food")
	near(float(hungry_meal[1]) / float(full_meal[1]), 0.7, 1e-9, "and 70% of the water")
	near(pol.fever_risk(), 0.03, 1e-12, "and the fever risk of hungry")
	Helpers.at(sim, 5, 9.0)
	check(pol.set_dial("rations", "full").ok, "back to full")
	near(sim.morale.value(dez), mood_before, 1e-9, "the mood comes back at once")
	near(pol.fever_risk(), 0.0, 1e-12, "no risk")
	_free(g)


# --------------------------------------------------------------------- hours --

func test_overtime_makes_more_and_wears_the_crew_out() -> void:
	var g := _game()
	var sim = g.sim
	var pol = sim.policies
	var dez = _p(sim, "dez")
	var marcus = _p(sim, "marcus")
	var craft: float = sim.traits.mult(dez, "craft")
	var repair: float = sim.traits.mult(dez, "repair")
	var aim: float = sim.traits.mult(dez, "aim")
	check(pol.set_dial("hours", "overtime").ok, "overtime can be set")
	near(sim.traits.mult(dez, "craft"), craft * 1.25, 1e-9, "the bench makes 25% more")
	near(sim.traits.mult(dez, "repair"), repair * 1.25, 1e-9, "the crew mends and builds 25% more")
	near(pol.work_mult(null, "garden"), 1.25, 1e-9, "and the beds grow 25% more")
	near(sim.traits.mult(dez, "aim"), aim, 1e-9, "nothing else changes (aim)")
	eq(pol.mood_lines(dez), [{"label": "Overtime", "value": -3.0}], "a standing mood line")
	# weariness: +2.5 an hour at work, -0.6 an hour always; ten hours of work, none for the rest of the day
	_looks(sim, 20, {"dez": "bench", "marcus": "", "ruth": "radio"})
	near(pol.weariness(dez), 19.0, 1e-6, "ten hours at work: 10 x (2.5 - 0.6)")
	near(pol.weariness(marcus), 0.0, 1e-9, "someone idle gains nothing")
	near(pol.weariness(_p(sim, "ruth")), 0.0, 1e-9, "and the player is not counted")
	check(not pol.weary.has("ruth"), "the player has no entry")
	_looks(sim, 28)
	near(pol.weariness(dez), 19.0 - 14.0 * 0.6, 1e-6, "and the other fourteen hours take 0.6 an hour: 10.6 a day in all")
	# rest sheds faster with the Rest priority (the weight of the stand-in is 3.0: four times as fast)
	var before: float = pol.weariness(dez)
	_looks(sim, 2, {"dez": "rest"})
	near(pol.weariness(dez), before - 0.6, 1e-6, "an hour at a rest spot with no Rest priority: the usual 0.6")
	var stand_in := GDScript.new()
	stand_in.source_code = "extends RefCounted\nfunc weight(_id) -> float:\n\treturn 3.0\n"
	check(stand_in.reload() == OK, "(the stand-in loads)")
	var priorities = sim.priorities
	sim.priorities = stand_in.new()
	before = pol.weariness(dez)
	_looks(sim, 2, {"dez": "rest"})
	near(pol.weariness(dez), before - 0.6 * 4.0, 1e-6, "with Rest first (weight 3) it falls four times as fast")
	sim.priorities = priorities
	# worn out at 60 and spent at 85: told once, in one line for everyone crossing together; mood and work follow
	pol.weary["dez"] = 59.5
	pol.weary["marcus"] = 59.9
	_looks(sim, 1, {"dez": "bench", "marcus": "hammer"})
	var worn := _policy_news(sim)
	eq(worn.get("text"), "Dez and Marcus are worn out", "one line for both")
	eq(pol.tier_of(dez), "worn", "worn out")
	eq(pol.mood_lines(dez), [{"label": "Overtime", "value": -3.0}, {"label": "Worn out", "value": -4.0}], "mood -4 more")
	near(pol.perf_mult(dez), 0.9, 1e-9, "work x0.9")
	var count: int = sim.radio.news.size()
	_looks(sim, 1, {"dez": "bench", "marcus": "hammer"})
	eq(sim.radio.news.size(), count, "and not told again")
	pol.weary["dez"] = 84.9
	_looks(sim, 1, {"dez": "bench"})
	eq(_policy_news(sim).get("text"), "Dez is spent", "spent")
	eq(pol.mood_lines(dez)[1], {"label": "Spent", "value": -8.0}, "mood -8")
	near(pol.perf_mult(dez), 0.8, 1e-9, "work x0.8")
	near(sim.perf(dez), sim.supplies.perf(dez) * sim.medical.perf(dez) * sim.morale.perf(dez) * sim.storyteller.perf(dez) * 0.8, 1e-9, "and sim.perf carries it")
	eq(pol.worn_out(), ["dez", "marcus"], "the worn out, the most weary first")
	near(pol.fever_risk(), 0.02, 1e-12, "overtime with someone worn out raises the fever risk")
	# normal hours: nobody gains, the worn recover
	Helpers.at(sim, 4, 9.0)
	check(pol.set_dial("hours", "normal").ok, "back to normal hours")
	near(pol.work_mult(null, "garden"), 1.0, 1e-12, "the usual work")
	var spent: float = pol.weariness(dez)
	_looks(sim, 20, {"dez": "bench"})
	near(pol.weariness(dez), spent - 6.0, 1e-6, "at work it only falls, 0.6 an hour")
	_free(g)


## About six days: at ten working hours a day overtime reaches 60 on the sixth day.
func test_overtime_wears_a_worker_out_in_about_six_days() -> void:
	var g := _game()
	var sim = g.sim
	var pol = sim.policies
	check(pol.set_dial("hours", "overtime").ok, "overtime")
	var dez = _p(sim, "dez")
	var day := 0
	while pol.tier_of(dez) == "" and day < 12:
		day += 1
		_looks(sim, 20, {"dez": "bench"})
		_looks(sim, 28)
	check(day >= 5 and day <= 7, "worn out on day %d of overtime" % day)
	_free(g)


# ------------------------------------------------------------------- boldness --

func test_boldness_sets_the_terms_of_an_errand_and_careful_keeps_to_quiet_places() -> void:
	var g := _game()
	var sim = g.sim
	var pol = sim.policies
	var base: Dictionary = {"loot": 0.6, "wound": 1.5, "loss_per_danger": 0.03, "clear": -0.2, "extras": false, "rescue": false, "vehicle": false}
	var careful: Dictionary = {}
	var bold: Dictionary = {}
	Helpers.at(sim, 3, 8.0)
	for p in sim.people:
		p.skills["Shooting"] = 6
	var quiet := ""
	var wild := ""
	for s in sim.scavenge.available_sites():
		if not bool(s.available) or bool(s.get("needs_vehicle", false)):
			continue
		if int(s.danger) <= 1 and quiet == "" and not (s.loot as Dictionary).is_empty():
			quiet = String(s.id)
		if int(s.danger) >= 2 and wild == "":
			wild = String(s.id)
	check(quiet != "" and wild != "", "the town has a quiet place and a dangerous one (%s, %s)" % [quiet, wild])
	var dez = _p(sim, "dez")
	var party: Array = [dez, _p(sim, "marcus")]
	var usual_clear: float = sim.scavenge.clear_chance([dez], quiet, true)
	var loot := func(seed_value: int) -> float:
		sim.scavenge.parties.clear()
		sim.scavenge.raids.clear()
		for p in sim.people:
			p.away = null
		sim.rng.seed = seed_value
		if not sim.scavenge.send(party, quiet, "loot"):
			return -1.0
		var total := 0.0
		for k in sim.scavenge.parties[0].result.loot:
			total += float(sim.scavenge.parties[0].result.loot[k])
		return total
	var usual_loot: float = loot.call(11)
	check(usual_loot > 0.0, "an errand to %s brings something" % quiet)
	check(pol.set_dial("boldness", "careful").ok, "careful")
	careful = pol.errand_terms(base)
	eq([careful.loot, careful.wound, careful.loss_per_danger, careful.clear], [0.5, 1.2, 0.015, -0.3], "careful's four numbers")
	eq([careful.extras, careful.rescue, careful.vehicle], [false, false, false], "the rest of the base is kept")
	check(String(pol.errand_limit(wild)).begins_with("Careful: not to a place this dangerous"), "careful refuses a place of danger 2 or more: %s" % pol.errand_limit(wild))
	eq(pol.errand_limit(quiet), "", "and goes to a quiet one")
	check(sim.scavenge.why_not_errand([dez], wild) == pol.errand_limit(wild), "the trip's refusal is the policy's words")
	near(sim.scavenge.clear_chance([dez], quiet, true), usual_clear - 0.1, 1e-9, "careful clears 10 points less often")
	var careful_loot: float = loot.call(11)
	Helpers.at(sim, 4, 8.0)
	check(pol.set_dial("boldness", "bold").ok, "bold")
	bold = pol.errand_terms(base)
	eq([bold.loot, bold.wound, bold.loss_per_danger, bold.clear], [0.8, 2.0, 0.05, -0.1], "bold's four numbers")
	eq(pol.errand_limit(wild), "", "bold goes anywhere")
	near(sim.scavenge.clear_chance([dez], quiet, true), usual_clear + 0.1, 1e-9, "bold clears 10 points more often")
	check(float(sim.scavenge.errand_terms().loot) == 0.8, "scavenge reads it")
	var bold_loot: float = loot.call(11)
	check(careful_loot < usual_loot and usual_loot < bold_loot, "the same dice bring %.0f careful, %.0f usual, %.0f bold" % [careful_loot, usual_loot, bold_loot])
	Helpers.at(sim, 5, 8.0)
	check(pol.set_dial("boldness", "usual").ok, "back to usual")
	check(is_same(pol.errand_terms(base), base), "usual is the base itself")
	_free(g)


# ------------------------------------------------------------------- strangers --

func test_strangers_at_the_gate_are_turned_away_or_checked() -> void:
	var g := _game()
	var sim = g.sim
	var pol = sim.policies
	var rec = sim.recruits
	var stranger: Dictionary = rec.make_def(0)
	stranger["bitten"] = false
	var bitten: Dictionary = rec.make_def(1)
	bitten["bitten"] = true
	var stranger_name := String(stranger.name).split(" ")[0]
	var bitten_name := String(bitten.name).split(" ")[0]
	# turn away: no stranger's call, but Ana (the front of the queue) and the other authored ones always come
	check(pol.set_dial("strangers", "turn_away").ok, "turn away")
	eq(rec.queue[0].id, "ana", "Ana is the next caller")
	check(pol.strangers_call_ok() and rec.call_due(), "Ana's call is still raised")
	rec.queue.clear()
	rec.generated = 0
	check(not pol.strangers_call_ok(), "a stranger's call is not")
	check(not rec.call_due(), "so the radio hour has no call")
	eq(rec.queue.size(), 0, "and nobody was made up to ask")
	rec.queue.append(stranger)
	check(not rec.call_due(), "a made-up stranger at the front of the queue is turned away too")
	# let in: as today
	Helpers.at(sim, 4, 9.0)
	check(pol.set_dial("strangers", "let_in").ok, "let in")
	check(rec.call_due(), "the call comes")
	eq(pol.arrival_delay_days(), 0, "and the caller arrives the next morning")
	# check: a day later, a bitten stranger turned back
	Helpers.at(sim, 5, 9.0)
	check(pol.set_dial("strangers", "check").ok, "check")
	eq(pol.arrival_delay_days(), 1, "a day's delay")
	rec.queue.clear()
	rec.queue.append(stranger)
	check(rec.accept(), "a caller is told the way in")
	eq(int(rec.incoming[0].day), sim.day + 2, "and arrives the day after tomorrow")
	var crew: int = sim.people.size()
	rec._arrive(stranger)
	eq(sim.people.size(), crew + 1, "a clear stranger is let in")
	check(String(_policy_news(sim).get("text", "")).ends_with("checked %s at the gate: clear" % stranger_name), "after a check the News says so: %s" % _policy_news(sim).get("text"))
	sim.events.clear()
	rec.next_call_day = 0
	rec._arrive(bitten)
	eq(sim.people.size(), crew + 1, "a bitten one is turned back: nobody is added")
	check(String(_policy_news(sim).get("text", "")).ends_with("checked %s at the gate: bitten" % bitten_name), "the News says who checked and what they found: %s" % _policy_news(sim).get("text"))
	eq(rec.next_call_day, sim.day + rec.REFUSE_DAYS, "the next call waits")
	check(sim.events.any(func(e): return e.type == "turned_away" and e.name == bitten_name), "the event")
	var authored := {"id": "walt", "name": "Walt Brandt", "bitten": true}
	check(not pol.caught_at_gate(authored), "the authored survivors are never turned back")
	_free(g)


# ----------------------------------------------------- one change a day, saves --

func test_one_change_a_dial_a_day_and_a_dial_that_is_not_one() -> void:
	var g := _game()
	var pol = g.sim.policies
	check(pol.set_dial("rations", "half").ok, "the first change")
	var again: Dictionary = pol.set_dial("rations", "hungry")
	check(not again.ok, "a second change the same day is refused")
	eq(again.why, "Changed today: again tomorrow", "in those words")
	eq(pol.current.rations, "half", "and nothing changed")
	check(pol.set_dial("hours", "overtime").ok, "another dial may still be set")
	eq(pol.set_dial("hours", "overtime").why, "Already set", "the same option is not a change")
	check(not pol.set_dial("rations", "feast").ok and not pol.set_dial("moon", "full").ok, "an option or a dial that does not exist")
	Helpers.at(g.sim, 4, 9.0)
	check(pol.set_dial("rations", "hungry").ok, "tomorrow it may be changed again")
	eq(pol.why_not_set("rations", "full"), "Changed today: again tomorrow", "and why_not_set says the same")
	_free(g)


func test_the_dials_and_the_weariness_survive_a_save_and_a_damaged_one_loads() -> void:
	var a := _game()
	var sim = a.sim
	var pol = sim.policies
	check(pol.set_dial("rations", "half").ok and pol.set_dial("hours", "overtime").ok and pol.set_dial("boldness", "bold").ok and pol.set_dial("strangers", "check").ok, "four dials set")
	_looks(sim, 6, {"dez": "bench"})
	pol.update(4.0)
	var text := SaveGame.to_text(SaveGame.to_dict(sim))
	var b := _bare()
	check(SaveGame.apply(b.sim, SaveGame.from_text(text)), "the save loads")
	var bp = b.sim.policies
	eq(bp.current, {"rations": "half", "hours": "overtime", "boldness": "bold", "strangers": "check"}, "the dials")
	eq(bp.changed_day, pol.changed_day, "the days they were changed")
	near(bp.weariness(_p(b.sim, "dez")), pol.weariness(_p(sim, "dez")), 1e-12, "the weariness")
	check(pol.weariness(_p(sim, "dez")) > 0.0, "(which is something)")
	near(bp._acc, pol._acc, 1e-12, "and the time to the next look")
	eq(bp.ration_mult("food"), 0.75, "the loaded game's rations bite")
	# a save from before the dials: fresh, every dial at its default
	var old: Dictionary = SaveGame.from_text(text)
	old.modules.erase("policies")
	var c := _bare()
	check(SaveGame.apply(c.sim, old), "a save from before loads")
	eq(c.sim.policies.current, pol.DEFAULTS, "with the defaults")
	check(c.sim.policies.weary.is_empty(), "and nobody worn")
	# a damaged one: what is not sound is left out
	var bad: Dictionary = SaveGame.from_text(text)
	bad.modules.policies = {"current": {"rations": "feast", "hours": "overtime", "moon": "full", "boldness": 5}, "weary": {"dez": 1.0e9, "marcus": NAN, "nobody": 40.0, "ruth": -5.0, "x": "bad"},
		"changed_day": {"rations": 99999, "moon": 3, "hours": "soon"}, "acc": "later"}
	var d := _bare()
	check(SaveGame.apply(d.sim, bad), "a damaged one loads")
	var dp = d.sim.policies
	eq(dp.current, {"rations": "full", "hours": "overtime", "boldness": "usual", "strangers": "let_in"}, "unknown options and dials are dropped, the sound one kept")
	near(dp.weariness(_p(d.sim, "dez")), 100.0, 1e-9, "weariness is kept between 0 and 100")
	check(not dp.weary.has("marcus") and not dp.weary.has("nobody") and not dp.weary.has("x"), "a number that is not finite, an unknown person and a word are dropped")
	check(dp.changed_day.get("rations", 0) <= d.sim.day and not dp.changed_day.has("moon") and not dp.changed_day.has("hours"), "a change day is never after today, and the unsound ones are dropped")
	near(dp._acc, 0.0, 1e-12, "no time to the next look")
	_free(a)
	_free(b)
	_free(c)
	_free(d)
