extends "res://tests/case.gd"
## The deck (assets/data/events.json): every card is well formed, resolves with every one of its
## choices, and changes exactly what it says it changes: the stores, the morale, the wounds and
## fevers, the weather, the blackout, tonight's budget, the dead who arrive by day, the wall, the
## party on its errand.

const Helpers := preload("res://tests/helpers.gd")
const Storyteller := preload("res://scripts/sim/storyteller.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

## The effects a card may use, and the words a card may put in braces.
const VOCABULARY := ["stock", "morale", "wound", "sick", "weather", "blackout", "night_budget", "spawn_day", "wall_damage", "party", "chance", "tension", "say", "at_hour", "recruit", "reveal_place"]
const TOKENS := ["name", "pair", "section_name", "speaker", "lookout", "flavor", "day", "place"]


## Morale that only writes down what it is asked to do.
class SpyMorale:
	extends "res://scripts/sim/morale.gd"
	var spy_shocks: Array = []
	var spy_moods := {}

	func shock(p, delta: float, label: String) -> void:
		spy_shocks.append({"who": "all" if p == null else p.id, "delta": delta, "label": label})

	func mood(p) -> String:
		return String(spy_moods.get(p.id, "Steady"))


## A midday of a quiet day: the radio hour already held (only `force` brings a card), plenty in the
## stores, nobody about, morale a spy.
func _noon(day: int = 8, seed_value: int = 5) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.storyteller.enabled = true
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = day
	sim.minutes = 12.0 * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (12.0 * 60.0 - 420.0)
	sim.phase = "day"
	sim.bell_rung = false
	sim.supplies.sources_day = day
	sim.supplies.meal_day = day
	sim.supplies.meals_done = 1
	sim.stock = {"ammo": 200.0, "scrap": 30.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.morale = SpyMorale.new()
	sim.morale.setup(sim)
	sim.storyteller.radio_day = day
	Helpers.idle_stores(sim)    # the bench and the beds would change the stores the cards are measured by
	sim.events.clear()
	return g


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


func _stock(sim) -> Dictionary:
	return sim.stock.duplicate()


func _same_stock(sim, before: Dictionary, except: Array = []) -> bool:
	for k in before:
		if not except.has(k) and absf(float(sim.stock[k]) - float(before[k])) > 0.001:
			return false
	return true


func _events_of(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if e.type == type:
			out.append(e)
	return out


func _alive_dead(sim) -> Array:
	var out: Array = []
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			out.append(z)
	return out


# ----------------------------------------------------------------- the deck --

func test_the_deck_is_well_formed() -> void:
	var g := _noon()
	var deck: Array = g.sim.storyteller.cards
	check(deck.size() >= 13 and deck.size() <= 17, "about fourteen cards: %d" % deck.size())
	var ids := {}
	var kinds := {"boon": 0, "threat": 0, "choice": 0}
	for c in deck:
		var id: String = c.id
		check(id != "" and id == id.to_lower() and not id.contains(" "), "a plain id: '%s'" % id)
		check(not ids.has(id), "the id is unique: %s" % id)
		ids[id] = true
		kinds[c.kind] += 1
		check(c.title.length() > 0 and c.title.length() <= 36, "%s: a short title (%d)" % [id, c.title.length()])
		check(c.text.length() >= 8 and c.text.length() <= 420, "%s: a few lines of text (%d characters)" % [id, c.text.length()])
		# the survivors' call is only ever put up by recruits.gd (it has no weight and its own words, tested in test_recruits.gd)
		check(c.weight > 0.0 or id == "survivor_call", "%s: it has a weight" % id)
		check(c.min_day >= 2 and c.max_day <= 29 and c.min_day <= c.max_day, "%s: days %d to %d" % [id, c.min_day, c.max_day])
		check(c.hour >= 12.0 and c.hour <= 21.0, "%s: it comes at %.0f" % [id, c.hour])
		check(c.wait > 0.0 and c.wait <= 3.0, "%s: it waits %.1f hours" % [id, c.wait])
		_check_words(id, c.title)
		_check_words(id, c.text)
		for v in c.flavor.get("by_role", {}).values():
			_check_words(id, String(v))
		_check_effects(id, c.effects)
		if c.kind == "choice":
			check(c.choices.size() >= 2 and c.choices.size() <= 3, "%s: two or three choices" % id)
			check(c.effects.is_empty(), "%s: a choice card does its work in its choices" % id)
		else:
			check(c.choices.is_empty(), "%s: a boon or a threat has no choice" % id)
			check(not c.effects.is_empty(), "%s: and it does something" % id)
		check(c.bot >= 0 and c.bot < maxi(c.choices.size(), 1), "%s: a default that exists" % id)
		for ch in c.choices:
			check(ch.label.length() > 0 and ch.label.length() <= 44, "%s: a short label '%s'" % [id, ch.label])
			check(ch.hint.length() >= 8 and ch.hint.length() <= 230, "%s: a hint that says what it costs ('%s')" % [id, ch.hint])
			_check_words(id, ch.label)
			_check_words(id, ch.hint)
			_check_words(id, ch.result)
			_check_effects(id, ch.effects)
			if JSON.stringify(ch.effects).contains("\"chance\""):
				var hint: String = ch.hint.to_lower()
				check(hint.contains("chance") or hint.contains(" in ten") or hint.contains(" in four") or hint.contains(" in three") or hint.contains("may "), "%s: the hint of '%s' states its risk plainly: '%s'" % [id, ch.label, ch.hint])
	check(kinds.boon >= 3 and kinds.threat >= 4 and kinds.choice >= 4, "a mix of boons, threats and choices: %s" % str(kinds))
	g.world.free()


## The words of a card: every {token} is one the card's context fills in; no franchise names.
func _check_words(id: String, text: String) -> void:
	var rest := text
	while rest.contains("{"):
		var open := rest.find("{")
		var close := rest.find("}", open)
		check(close > open, "%s: an open brace in '%s'" % [id, text])
		if close <= open:
			return
		var token := rest.substr(open + 1, close - open - 1)
		check(TOKENS.has(token) or (id == "survivor_call" and token.begins_with("caller")), "%s: an unknown word {%s}" % [id, token])
		rest = rest.substr(close + 1)
	for banned in ["walking dead", "zombieland", "last of us", "resident evil", "rick grimes", "daryl", "fallout", "shaun of the dead"]:
		check(not text.to_lower().contains(banned), "%s: no franchise names ('%s')" % [id, banned])


## Every effect named is one the rules know.
func _check_effects(id: String, effects: Array) -> void:
	for e in effects:
		for key in e:
			check(VOCABULARY.has(String(key)), "%s: an effect '%s' the rules do not know" % [id, key])
			if key == "chance":
				_check_effects(id, e.chance.get("then", []))
				_check_effects(id, e.chance.get("else", []))
			elif key == "at_hour":
				_check_effects(id, e.at_hour.get("do", []))


func test_every_card_resolves_with_every_one_of_its_choices() -> void:
	var probe := _noon()
	var deck: Array = probe.sim.storyteller.cards.duplicate(true)
	probe.world.free()
	for card in deck:
		if card.id == "survivor_call" or card.id == "place_call":
			continue    # needs a caller (see test_recruits.gd) or the town board (see test_town.gd)
		var count: int = maxi(card.choices.size(), 1)
		for i in count:
			var g := _noon(8, 9)
			var sim = g.sim
			var label := "%s, choice %d" % [card.id, i]
			check(sim.storyteller.force(card.id), "%s: it is put up" % label)
			if card.hour > 12.01:
				Helpers.run_to_hour(sim, card.hour + 0.05)
			var up: Dictionary = sim.storyteller.pending()
			check(not up.is_empty(), "%s: it is waiting" % label)
			if up.is_empty():
				g.world.free()
				continue
			eq(up.id, card.id, label)
			check(not up.text.contains("{") and not up.title.contains("{"), "%s: no braces are left in the words: '%s'" % [label, up.text])
			eq(up.choices.size(), count, "%s: the choices are all shown" % label)
			for c in up.choices:
				check(c.label != "" and not c.label.contains("{") and not c.hint.contains("{"), "%s: '%s' is fully worded" % [label, c.label])
				check(c.enabled, "%s: '%s' can be made" % [label, c.label])
			check(sim.storyteller.choose(i), "%s: the choice is taken" % label)
			check(sim.storyteller.pending().is_empty(), "%s: and the card is put away" % label)
			var done := _events_of(sim, "story_resolved")
			check(done.size() >= 1 and done[done.size() - 1].id == card.id, "%s: the view is told it is settled" % label)
			check(sim.alerts.has("story-%s" % card.id), "%s: an alert keeps what came of it" % label)
			Helpers.run(sim, 3.0)
			g.world.free()


func test_every_card_can_be_drawn_on_some_day() -> void:
	var g := _noon()
	var sim = g.sim
	var seen := {}
	var deck: Array = sim.storyteller.cards
	for s in 400:
		sim.run_seed = s
		sim.storyteller.history.clear()
		sim.storyteller.recent.clear()
		sim.storyteller.tension = float((s % 5) * 25)
		for day in [3, 6, 9, 14, 20, 27]:
			var c: Dictionary = sim.storyteller.draw(day)
			if not c.is_empty():
				seen[c.id] = true
	for c in deck:
		if c.id == "survivor_call" or c.id == "place_call":
			continue    # only recruits.gd puts the first up, and the other needs the town board (the settlement game)
		check(seen.has(c.id), "%s comes up in the draw" % c.id)
	g.world.free()


# ----------------------------------------------------------------- the boons --

func test_heavy_rain_fills_the_barrels() -> void:
	var g := _noon()
	var sim = g.sim
	var before := _stock(sim)
	sim.storyteller.force("heavy_rain")
	eq(sim.weather, "rain", "it rains")
	near(float(sim.stock.water), float(before.water) + 20.0, 0.001, "twenty more water")
	check(_same_stock(sim, before, ["water"]), "and nothing else in the stores moves")
	eq(sim.storyteller.pending().changes, ["Rain tonight", "Water +20"], "the card says exactly that")
	eq(sim.storyteller.look().rain, true, "the lighting is told it rains")
	g.world.free()


func test_a_quiet_day_lifts_everyone() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("quiet_day")
	eq(sim.morale.spy_shocks, [{"who": "all", "delta": 8.0, "label": "A quiet day"}], "+8 morale for all, with its reason")
	check(_same_stock(sim, {"ammo": 200.0, "scrap": 30.0, "food": 40.0, "water": 50.0, "meds": 10.0}), "nothing else moves")
	g.world.free()


func test_old_friends_lift_one_person_and_the_words_are_about_them() -> void:
	var told := {}
	for s in range(1, 40):
		var g := _noon(8, s)
		var sim = g.sim
		sim.run_seed = s
		sim.storyteller.force("old_friends")
		var up: Dictionary = sim.storyteller.pending()
		eq(sim.morale.spy_shocks.size(), 1, "one person is lifted (seed %d)" % s)
		var shock: Dictionary = sim.morale.spy_shocks[0]
		eq(shock.delta, 12.0, "by 12")
		eq(shock.label, "Old friends on the radio", "for a reason the panel can show")
		var who = null
		for p in sim.people:
			if p.id == shock.who:
				who = p
		check(who != null and up.text.contains(who.first), "%s's name is in the card: '%s'" % [shock.who, up.text])
		check(who != null and not up.text.contains("A friendly voice comes through"), "the line for their role was used")
		told[shock.who] = true
		g.world.free()
	check(told.size() >= 4, "different people are chosen on different days: %s" % str(told.keys()))


# --------------------------------------------------------------- the threats --

func test_fog_shortens_the_guns_reach_from_dusk_to_dawn() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("fog")
	eq(sim.weather, "fog", "it is foggy")
	eq(sim.storyteller.pending().changes, ["Fog tonight: the guns reach 30% less far"], "the card says so")
	near(Storyteller.FOG_REACH, 0.7, 0.0001, "30% less far")
	var rifle: Dictionary = sim.weapons.rifle
	var pike: Dictionary = sim.weapons.pike
	near(sim.reach_of(rifle), float(rifle.range), 0.001, "by day the guns reach as far as ever")
	sim.minutes = 22.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	near(sim.reach_of(rifle), float(rifle.range) * 0.7, 0.001, "by night a rifle reaches 30% less far")
	near(sim.reach_of(pike), float(pike.range), 0.001, "a pike in the hand does not")
	check(sim.storyteller.look().fog >= 0.99, "the night is thick with it")
	# a walker 12 tiles from a rifle is in range on a clear night and out of it in the fog
	var dez = _person(sim, "Dez")
	dez.x = 40.0
	dez.y = 19.0
	var z = sim.spawn(40.0, 7.0, "wander")
	z.speed = 0.0
	sim.weather = "clear"
	eq(sim._find_target(dez), z, "clear: he picks the walker at 12 tiles")
	sim.weather = "fog"
	eq(sim._find_target(dez), null, "foggy: nothing in reach")
	z.y = 10.0
	eq(sim._find_target(dez), z, "at 9 tiles it is in reach again")
	g.world.free()


func test_the_bell_of_a_foggy_day_reminds_the_crew_and_a_clear_one_says_nothing() -> void:
	var g := _noon(8, 4)
	var sim = g.sim
	sim.storyteller.force("fog")
	sim.storyteller.radio_day = 8
	var told := false
	for i in 8 * 20 * 30:
		sim.update(1.0 / 30.0)
		if sim.phase == "dusk":
			told = told or sim.alerts.has("story-fog-night")
			if told:
				break
	check(told, "an alert at dusk says the guns reach less far tonight")
	check(String(sim.alerts["story-fog-night"].sub).contains("30% less far"), "and how much")
	g.world.free()
	var h := _noon(8, 4)
	var quiet := false
	for i in 8 * 20 * 30:
		h.sim.update(1.0 / 30.0)
		if h.sim.phase == "dusk":
			quiet = not h.sim.alerts.has("story-fog-night")
			break
	check(quiet, "a clear evening has no such word")
	h.world.free()


func test_fog_shows_in_the_fields_of_fire_and_ends_at_dawn() -> void:
	var g := _noon()
	var sim = g.sim
	sim.minutes = 22.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	var clear := 0
	for s in sim.segments:
		clear += sim.tactics.coverage_of(s)
	sim.weather = "fog"
	var foggy := 0
	for s in sim.segments:
		foggy += sim.tactics.coverage_of(s)
	check(foggy < clear, "fewer guns reach the wall in a fog: %d against %d" % [foggy, clear])
	# the new day rolls the weather again (rain or clear)
	sim.minutes = 6.45 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	Helpers.run(sim, 4.0)
	check(sim.weather != "fog", "the day after the fog it is %s" % sim.weather)
	near(sim.storyteller.reach_mult(), 1.0, 0.0001, "and the guns reach as far as ever")
	g.world.free()


func test_a_fever_makes_one_person_slower_until_ana_treats_it() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("fever")
	var sick: Array = []
	for p in sim.people:
		if sim.storyteller.is_sick(p):
			sick.append(p)
	eq(sick.size(), 1, "one person is sick")
	var p = sick[0]
	check(sim.storyteller.pending().text.contains(p.first), "and the card names them: '%s'" % sim.storyteller.pending().text)
	var healthy = _person(sim, "Hector") if p.first != "Hector" else _person(sim, "Dez")
	near(sim.perf(p), sim.perf(healthy) * 0.75, 0.0001, "they work at three quarters")
	var marks: Array = sim.status_of(p)
	var has_mark := false
	for m in marks:
		has_mark = has_mark or String(m.tip).contains("fever")
	check(has_mark, "with a mark that says so: %s" % str(marks))
	check(sim.medical.can_treat(p), "the Treat button is offered")
	var meds: float = sim.stock.meds
	check(sim.medical.gizmo("treat", {"kind": "person", "ref": p}), "Treat is pressed")
	near(float(sim.stock.meds), meds - 1.0, 0.0001, "one medicine is used")
	check(not sim.storyteller.is_sick(p), "the fever is over")
	near(sim.perf(p), sim.perf(healthy), 0.0001, "and they work as before")
	g.world.free()


func test_a_fever_cannot_be_treated_without_medicine_and_wears_off_by_itself() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("fever")
	var p = null
	for q in sim.people:
		if sim.storyteller.is_sick(q):
			p = q
	sim.stock.meds = 0.0
	check(not sim.storyteller.treat(p), "with no medicine there is no treatment")
	check(sim.storyteller.is_sick(p), "so they stay sick")
	Helpers.run(sim, 19.0 * 20.0)
	check(sim.storyteller.is_sick(p), "after 19 hours still sick")
	var told := false
	for i in 40 * 30:
		sim.update(1.0 / 30.0)
		told = told or sim.alerts.has("story-well-%s" % p.id)
		if not sim.storyteller.is_sick(p) and told:
			break
	check(not sim.storyteller.is_sick(p), "after 20 it has gone")
	check(told, "and the crew is told")
	g.world.free()


func test_mould_takes_fifteen_percent_of_the_food() -> void:
	var g := _noon()
	var sim = g.sim
	var before := _stock(sim)
	sim.storyteller.force("mould")
	near(float(sim.stock.food), 40.0 * 0.85, 0.06, "15% of the food is gone")
	check(_same_stock(sim, before, ["food"]), "and nothing else")
	check(String(sim.storyteller.pending().changes[0]).begins_with("Food -15%"), "the card says so: %s" % str(sim.storyteller.pending().changes))
	g.world.free()


func test_wall_rot_takes_a_third_off_one_piece_and_never_breaks_it() -> void:
	for s in range(1, 25):
		var g := _noon(8, s)
		var sim = g.sim
		var before := {}
		for seg in sim.segments:
			before[seg.id] = seg.hp
		sim.storyteller.force("wall_rot")
		var hurt: Array = []
		for seg in sim.segments:
			if absf(seg.hp - before[seg.id]) > 0.001:
				hurt.append(seg)
		eq(hurt.size(), 1, "one piece of the wall is hurt (seed %d)" % s)
		if hurt.size() == 1:
			var seg = hurt[0]
			near(before[seg.id] - seg.hp, seg.max_hp * 0.3, 0.001, "by 30%% of its health: %s" % seg.name)
			check(seg.kind != "door" and seg.state != 3, "not a door, and still standing")
			check(sim.storyteller.pending().text.contains(seg.name.to_lower()), "the card names it: '%s'" % sim.storyteller.pending().text)
		g.world.free()


func test_wall_rot_is_not_drawn_when_every_piece_is_too_worn() -> void:
	var g := _noon()
	var sim = g.sim
	for seg in sim.segments:
		seg.hp = seg.max_hp * 0.4
	var rot: Dictionary = sim.storyteller.card_named("wall_rot")
	check(not sim.storyteller._needs_ok(rot.needs), "nothing is worth rotting")
	g.world.free()


func test_stragglers_arrive_at_two_by_day_at_one_wall() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("stragglers")
	eq(_alive_dead(sim).size(), 0, "nobody yet at noon")
	var up: Dictionary = sim.storyteller.pending()
	check(up.text.contains("Marcus"), "the lookout speaks in the card: '%s'" % up.text)
	eq(up.changes, ["At 14:00 the dead reach the north wall"], "and says when")
	Helpers.run_to_hour(sim, 13.9)
	eq(_alive_dead(sim).size(), 0, "still nobody at 13:54")
	Helpers.run_to_hour(sim, 14.1)
	var dead := _alive_dead(sim)
	eq(dead.size(), 6 + 8 / 3, "six plus a third of the day, by the day: %d" % dead.size())
	var sections := {}
	for z in dead:
		check(z.state == "approach" or z.state == "attack", "they are on their way to the wall: %s" % z.state)
		eq(z.slot.seg.side, "N", "at the north wall")
		sections[z.slot.seg.id] = int(sections.get(z.slot.seg.id, 0)) + 1
	var most := 0
	for k in sections:
		most = maxi(most, int(sections[k]))
	eq(most, dead.size(), "all of them at one piece of it, there being room: %s" % str(sections))
	check(sim.alerts.has("story-dead"), "a daytime alarm is raised")
	check(sim.alerts["story-dead"].level == "danger", "a dangerous one")
	g.world.free()


func test_more_stragglers_come_later_in_the_game() -> void:
	var early := _noon(4)
	early.sim.storyteller.force("stragglers")
	Helpers.run_to_hour(early.sim, 14.1)
	var late := _noon(27)
	late.sim.storyteller.force("stragglers")
	Helpers.run_to_hour(late.sim, 14.1)
	eq(_alive_dead(early.sim).size(), 6 + 4 / 3, "day 4")
	eq(_alive_dead(late.sim).size(), 6 + 27 / 3, "day 27")
	early.world.free()
	late.world.free()


func test_a_warning_of_a_horde_makes_tonight_bigger_and_the_forecast_says_so() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.waves.enabled = true
	var normal: float = sim.waves.night_budget(8)
	var plan_before: int = sim.waves.plan_for(8).queue.size()
	sim.storyteller.force("horde_warning")
	near(sim.waves.night_budget(8), normal * 1.3, 0.0001, "tonight's budget is 30% more")
	var plan_after: int = sim.waves.plan_for(8).queue.size()
	check(plan_after > plan_before, "the plan was made again: %d dead, was %d" % [plan_after, plan_before])
	near(float(sim.waves.plan_for(8).budget), normal * 1.3, 0.0001, "with the new budget")
	near(sim.waves.night_budget(9), sim.waves.budget_for(9), 0.0001, "tomorrow night is as it was")
	eq(sim.storyteller.pending().changes, ["Tonight's dead: x1.3"], "the card says so")
	# the lookout's forecast at 17:00 counts the new number
	sim.waves.enabled = false
	Helpers.run_to_hour(sim, 17.1)
	var f: Dictionary = sim.tactics.forecast()
	check(f.given, "the forecast is given")
	eq(f.total, int(sim.waves.plan_for(8).shown), "and is of the bigger night")
	var plain := _noon(8)
	plain.sim.waves.enabled = false
	Helpers.run_to_hour(plain.sim, 17.1)
	check(f.total > int(plain.sim.tactics.forecast().total), "more than an ordinary night's: %d against %d" % [f.total, int(plain.sim.tactics.forecast().total)])
	plain.world.free()
	g.world.free()


func test_the_horde_warning_is_spent_by_the_next_day() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("horde_warning")
	eq(sim.storyteller.budget_mult(8), 1.3, "tonight")
	eq(sim.storyteller.budget_mult(9), 1.0, "not tomorrow")
	sim.storyteller.enabled = false
	eq(sim.storyteller.budget_mult(8), 1.0, "and not when it is off")
	g.world.free()


# --------------------------------------------------------------- the choices --

func test_the_supply_crate_sends_two_of_the_crew_out_and_brings_it_back_at_four() -> void:
	var g := _noon(8, 3)
	var sim = g.sim
	sim.storyteller.force("supply_drop")
	var up: Dictionary = sim.storyteller.pending()
	check(up.choices[0].label.begins_with("Send ") and up.choices[0].label.contains(" and "), "it names the two who go: '%s'" % up.choices[0].label)
	var crew: Array = [_person(sim, "Marcus"), _person(sim, "Walt")]
	eq(up.choices[0].label, "Send Marcus and Walt", "the two best shots, Ruth being at the radio")
	var ammo: float = sim.stock.ammo
	var scale: float = sim.scavenge.loot_scale("crate", crew)
	check(sim.storyteller.choose(0), "Send them")
	eq(sim.scavenge.parties.size(), 1, "a party is out")
	eq(sim.scavenge.parties[0].site, "crate", "to the crate")
	eq(sim.scavenge.parties[0].members, ["marcus", "walt"], "Marcus and Walt")
	var followers: int = sim.storyteller.errand.followers
	Helpers.run(sim, 12.0)
	for p in crew:
		check(p.away != null, "%s is away" % p.first)
	Helpers.run_to_hour(sim, 15.9)
	for p in crew:
		check(p.away != null, "%s is still away at 15:54" % p.first)
	Helpers.run_to_hour(sim, 16.2)
	for p in crew:
		check(p.away == null, "%s is back by 16:12" % p.first)
	eq(sim.scavenge.parties.size(), 0, "the party is home")
	eq(sim.storyteller.errand, {}, "and the errand is closed")
	var gained: float = float(sim.stock.ammo) - ammo
	check(gained >= 30.0 * scale - 1.01 and gained <= 50.0 * scale + 1.01, "30 to 50 ammo, as the crate says (times %.2f): %.1f" % [scale, gained])
	check(sim.alerts.keys().any(func(k): return String(k).begins_with("scav-")), "the crew is told what they brought")
	if followers == 0:
		eq(_alive_dead(sim).size(), 0, "nobody followed them")
	g.world.free()


func test_the_dead_follow_the_crate_party_home_about_one_time_in_three() -> void:
	var followed := 0
	var alone := 0
	var seen_dead := false
	for s in range(1, 31):
		var g := _noon(8, s)
		var sim = g.sim
		sim.storyteller.force("supply_drop")
		sim.storyteller.choose(0)
		var n: int = sim.storyteller.errand.get("followers", 0)
		if n > 0:
			followed += 1
			eq(n, 3, "three of them")
			if not seen_dead:
				seen_dead = true
				Helpers.run_to_hour(sim, 16.2)
				var dead := _alive_dead(sim)
				eq(dead.size(), 3, "three of the dead are at the gate")
				check(sim.alerts.has("story-dead"), "and the crew is told")
				for z in dead:
					check(Vector2(z.x, z.y).distance_to(sim.scavenge.gate_center()) < 14.0, "near the gate: %s" % str(Vector2(z.x, z.y)))
		else:
			alone += 1
		g.world.free()
	check(followed >= 4 and alone >= 14, "about one in three: %d of 30" % followed)


func test_leaving_the_crate_changes_nothing() -> void:
	var g := _noon()
	var sim = g.sim
	var before := _stock(sim)
	sim.storyteller.force("supply_drop")
	check(sim.storyteller.choose(1), "Leave it")
	check(_same_stock(sim, before), "the stores are as they were")
	eq(sim.scavenge.parties.size(), 0, "nobody goes")
	eq(sim.storyteller.errand, {}, "no errand")
	g.world.free()


func test_the_crate_is_not_offered_with_nobody_to_send() -> void:
	var g := _noon()
	var sim = g.sim
	for p in sim.people:
		if p.first != "Ruth" and p.first != "Walt":
			p.downed = true
	var card: Dictionary = sim.storyteller.card_named("supply_drop")
	check(not sim.storyteller._needs_ok(card.needs), "with one free besides Ruth there is no pair to send")
	g.world.free()


func test_the_stranger_traded_with_across_the_gate_is_a_fair_swap() -> void:
	var g := _noon()
	var sim = g.sim
	var before := _stock(sim)
	sim.storyteller.force("stranger")
	check(sim.storyteller.choose(1), "Trade across the gate")
	near(float(sim.stock.ammo), float(before.ammo) - 15.0, 0.001, "15 ammo go")
	near(float(sim.stock.meds), float(before.meds) + 3.0, 0.001, "3 medicine come")
	check(_same_stock(sim, before, ["ammo", "meds"]), "nothing else moves")
	eq(_alive_dead(sim).size(), 0, "and nothing comes in with them")
	g.world.free()


func test_sending_the_stranger_away_costs_morale() -> void:
	var g := _noon()
	var sim = g.sim
	var before := _stock(sim)
	sim.storyteller.force("stranger")
	check(sim.storyteller.choose(2), "Send them away")
	eq(sim.morale.spy_shocks, [{"who": "all", "delta": -3.0, "label": "A stranger turned away"}], "everyone feels it")
	check(_same_stock(sim, before), "the stores do not move")
	g.world.free()


## What letting the stranger in did: "meds", "thief" or "turn".
func _let_in(sim) -> String:
	var before := _stock(sim)
	var sched: int = sim.storyteller.schedule.size()
	sim.storyteller.force("stranger")
	sim.storyteller.choose(0)
	var out := ""
	if float(sim.stock.meds) > float(before.meds) + 0.001:
		out = "meds"
		check(absf(float(sim.stock.meds) - float(before.meds) - 4.0) < 0.001 and _same_stock(sim, before, ["meds"]), "four medicine, nothing else")
	elif float(sim.stock.food) < float(before.food) - 0.001:
		out = "thief"
		check(absf(float(sim.stock.food) - float(before.food) + 10.0) < 0.001 and absf(float(sim.stock.water) - float(before.water) + 10.0) < 0.001 and _same_stock(sim, before, ["food", "water"]), "ten food and ten water, nothing else")
	elif sim.storyteller.schedule.size() > sched:
		out = "turn"
		check(_same_stock(sim, before), "the stores are untouched")
	sim.storyteller.schedule.clear()
	sim.storyteller.sick.clear()
	sim.stock = before.duplicate()
	return out


func test_letting_the_stranger_in_is_a_gamble_with_the_odds_the_hint_gives() -> void:
	var g := _noon()
	var sim = g.sim
	var count := {"meds": 0, "thief": 0, "turn": 0, "": 0}
	for i in 400:
		sim.storyteller.history.clear()
		sim.storyteller._card = {}
		count[_let_in(sim)] += 1
	eq(count[""], 0, "every time one of the three things happens")
	check(count.meds > 130 and count.meds < 190, "four in ten bring medicine: %d of 400" % count.meds)
	check(count.thief > 110 and count.thief < 170, "a little over three in ten steal: %d of 400" % count.thief)
	check(count.turn > 70 and count.turn < 130, "one in four turn: %d of 400" % count.turn)
	g.world.free()


func test_a_stranger_who_was_bitten_turns_in_the_yard_at_two_in_the_morning() -> void:
	var found := false
	for s in range(1, 60):
		var g := _noon(8, s)
		var sim = g.sim
		sim.storyteller.force("stranger")
		sim.storyteller.choose(0)
		if sim.storyteller.schedule.is_empty():
			g.world.free()
			continue
		found = true
		check(String(JSON.stringify(sim.storyteller.schedule[0].do)).contains("spawn_day"), "a turning is on the books")
		Helpers.run_to_hour(sim, 1.9)
		eq(sim.zombies.size(), 0, "nothing at 01:54")
		var came := false
		for i in 600:
			sim.update(1.0 / 30.0)
			if sim.zombies.size() > 0:
				came = true
				break
		check(came, "one of the dead appears at two")
		check(sim.hour >= 1.99 and sim.hour < 2.1, "at two o'clock: %.2f" % sim.hour)
		eq(sim.zombies.size(), 1, "just the one")
		if sim.zombies.size() == 1:
			var z = sim.zombies[0]
			check(z.y > 19.0 and z.y < 30.0 and absf(z.x - 39.0) < 6.0, "just inside the gate: %s" % str(Vector2(z.x, z.y)))
			eq(z.turned_name, "The stranger", "the stranger")
		check(sim.alerts.has("story-dead"), "and the crew is told")
		g.world.free()
		break
	check(found, "some seed turns the stranger")


func test_the_cry_at_the_gate_comes_at_six_in_the_evening_and_waits_half_an_hour() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("cry_at_gate")
	check(sim.storyteller.pending().is_empty(), "nothing is said at noon")
	Helpers.run_to_hour(sim, 17.9)
	check(sim.storyteller.pending().is_empty(), "nor at 17:54")
	Helpers.run_to_hour(sim, 18.1)
	var up: Dictionary = sim.storyteller.pending()
	check(not up.is_empty(), "at six someone is at the gate")
	eq(up.choices.size(), 3, "three things to do")
	near(up.until, 18.5, 0.05, "and half an hour to do it")
	var morale_before: int = sim.morale.spy_shocks.size()
	Helpers.run_to_hour(sim, 18.7)
	check(sim.storyteller.pending().is_empty(), "left alone it is settled by its default")
	check(sim.morale.spy_shocks.size() > morale_before, "which was not the open gate")
	g.world.free()


func test_opening_the_gate_lets_in_the_runner_and_two_of_the_dead() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("cry_at_gate")
	Helpers.run_to_hour(sim, 18.1)
	var before := _stock(sim)
	check(sim.storyteller.choose(0), "Open the gate")
	eq(sim.morale.spy_shocks, [{"who": "all", "delta": 4.0, "label": "We opened the gate"}], "morale rises by 4")
	var dead := _alive_dead(sim)
	eq(dead.size(), 2, "two of the dead come in")
	for z in dead:
		eq(z.state, "breach", "they are in the yard, after somebody")
		check(Vector2(z.x, z.y).distance_to(sim.scavenge.gate_center()) < 5.0, "at the gate: %s" % str(Vector2(z.x, z.y)))
	check(_same_stock(sim, before), "and it costs no stores")
	g.world.free()


func test_covering_the_runner_from_the_wall_costs_ammo_and_may_cost_the_runner() -> void:
	var lucky := 0
	var unlucky := 0
	for s in range(1, 21):
		var g := _noon(8, s)
		var sim = g.sim
		sim.storyteller.force("cry_at_gate")
		Helpers.run_to_hour(sim, 18.1)
		var before := _stock(sim)
		var ammo: float = sim.stock.ammo
		check(sim.storyteller.choose(1), "Cover them")
		near(float(sim.stock.ammo), ammo - 14.0, 0.001, "14 ammo are spent")
		check(_same_stock(sim, before, ["ammo"]), "and nothing else")
		eq(_alive_dead(sim).size(), 0, "none of the dead come in")
		if sim.morale.spy_shocks.is_empty():
			lucky += 1
		else:
			unlucky += 1
			eq(sim.morale.spy_shocks, [{"who": "all", "delta": -5.0, "label": "We lost them at the gate"}], "if they did not make it, morale falls by 5")
		g.world.free()
	check(lucky > unlucky and unlucky >= 1, "three times in four they make it: %d of %d" % [lucky, lucky + unlucky])


func test_leaving_the_runner_costs_eight_morale_and_nothing_else() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("cry_at_gate")
	Helpers.run_to_hour(sim, 18.1)
	var before := _stock(sim)
	check(sim.storyteller.choose(2), "Leave them")
	eq(sim.morale.spy_shocks, [{"who": "all", "delta": -8.0, "label": "We left them at the gate"}], "morale falls by 8")
	check(_same_stock(sim, before), "the stores are as they were")
	eq(_alive_dead(sim).size(), 0, "nobody comes in")
	g.world.free()


func test_the_trade_on_the_radio_swaps_five_medicine_for_sixty_ammo() -> void:
	var g := _noon()
	var sim = g.sim
	var before := _stock(sim)
	sim.storyteller.force("radio_trade")
	check(sim.storyteller.choose(0), "Make the trade")
	near(float(sim.stock.meds), float(before.meds) - 5.0, 0.001, "five medicine go")
	near(float(sim.stock.ammo), float(before.ammo) + 60.0, 0.001, "sixty rounds come")
	check(_same_stock(sim, before, ["meds", "ammo"]), "nothing else moves")
	g.world.free()


func test_not_today_changes_nothing_and_the_trade_needs_the_medicine() -> void:
	var g := _noon()
	var sim = g.sim
	var before := _stock(sim)
	sim.storyteller.force("radio_trade")
	check(sim.storyteller.choose(1), "Not today")
	check(_same_stock(sim, before), "nothing changes")
	g.world.free()
	var poor := _noon()
	poor.sim.storyteller.force("radio_trade")
	poor.sim.stock.meds = 3.0
	var up: Dictionary = poor.sim.storyteller.pending()
	check(not up.choices[0].enabled, "with 3 medicine the trade cannot be made")
	check(String(up.choices[0].why).contains("5 medicine"), "and it says why: '%s'" % up.choices[0].why)
	check(not poor.sim.storyteller.choose(0), "it is refused")
	eq(float(poor.sim.stock.meds), 3.0, "and nothing was taken")
	poor.world.free()


func test_a_trade_card_waiting_with_too_little_medicine_takes_the_other_choice() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("radio_trade")
	sim.stock.meds = 3.0
	sim.storyteller.card_named("radio_trade")["bot"] = 0
	Helpers.run(sim, 2.5 * 20.0)
	check(sim.storyteller.pending().is_empty(), "it is settled after two hours")
	near(float(sim.stock.meds), 3.0, 0.01, "and the medicine is kept")
	near(float(sim.stock.ammo), 200.0, 0.01, "as is the ammo")
	g.world.free()


func test_an_argument_costs_the_referee_or_the_two_who_quarrel() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("argument")
	var up: Dictionary = sim.storyteller.pending()
	check(up.choices[0].hint.contains("Ruth"), "the hint names who pays: '%s'" % up.choices[0].hint)
	check(sim.storyteller.choose(0), "Step in")
	eq(sim.morale.spy_shocks, [{"who": "ruth", "delta": -3.0, "label": "Refereeing"}], "Ruth is 3 lower")
	g.world.free()
	var h := _noon()
	h.sim.storyteller.force("argument")
	check(h.sim.storyteller.choose(1), "Let them cool off")
	eq(h.sim.morale.spy_shocks, [{"who": "dez", "delta": -5.0, "label": "An argument"}, {"who": "hector", "delta": -5.0, "label": "An argument"}], "Dez and Hector are 5 lower")
	h.world.free()


func test_an_argument_needs_both_of_them_on_their_feet() -> void:
	var g := _noon()
	var sim = g.sim
	var card: Dictionary = sim.storyteller.card_named("argument")
	check(sim.storyteller._needs_ok(card.needs), "with both about it can be drawn")
	_person(sim, "Hector").downed = true
	check(not sim.storyteller._needs_ok(card.needs), "not with Hector down")
	_person(sim, "Hector").downed = false
	_person(sim, "Dez").dead = true
	check(not sim.storyteller._needs_ok(card.needs), "not with Dez gone")
	g.world.free()


# --------------------------------------------------------------- the blackout --

func test_the_generator_fails_at_nine_and_dez_mends_it_in_forty_minutes() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("blackout")
	check(sim.storyteller.choose(0), "Send Dez when it fails")
	eq(sim.storyteller.blackout_state(), "pending", "it is coming")
	eq(sim.storyteller.look().blackout, false, "the lights are still on")
	Helpers.run_to_hour(sim, 20.9)
	eq(sim.storyteller.blackout_state(), "pending", "not yet at 20:54")
	var dez = _person(sim, "Dez")
	check(dez.order == null, "Dez is where he was")
	Helpers.run_to_hour(sim, 21.05)
	eq(sim.storyteller.blackout_state(), "dark", "at nine the lights go out")
	eq(sim.storyteller.look().blackout, true, "the lighting is told")
	check(sim.alerts.has("story-blackout"), "an alert says so")
	var failed_at: float = sim.clock_min
	check(dez.order != null and dez.drafted, "Dez is sent, like an order")
	check(Vector2(dez.order.x, dez.order.y).distance_to(Storyteller.GENERATOR) < 2.0, "to the generator: %s" % str(dez.order))
	near(sim.storyteller.aim_mult(8.0), 0.75, 0.0001, "in the dark aim is a quarter worse far off")
	near(sim.storyteller.aim_mult(5.0), 1.0, 0.0001, "but not near")
	var guard := 0
	while sim.storyteller.blackout_state() == "dark" and guard < 3000:
		Helpers.run(sim, 0.1)
		guard += 1
	eq(sim.storyteller.blackout_state(), "", "the lights come back")
	var took: float = sim.clock_min - failed_at
	check(took >= 40.0 and took < 70.0, "after forty minutes of work and the walk: %.0f minutes" % took)
	check(not dez.drafted and dez.order == null, "Dez is let go")
	near(sim.storyteller.aim_mult(8.0), 1.0, 0.0001, "and aim is as before")
	check(sim.alerts.has("story-lights"), "the crew is told")
	g.world.free()


func test_holding_the_wall_in_the_dark_keeps_the_lights_out_until_morning() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("blackout")
	check(sim.storyteller.choose(1), "Hold the wall in the dark")
	Helpers.run_to_hour(sim, 21.1)
	eq(sim.storyteller.blackout_state(), "dark", "it is dark")
	var dez = _person(sim, "Dez")
	check(dez.order == null and not dez.drafted, "Dez stays at his post")
	Helpers.run_to_hour(sim, 3.0)
	eq(sim.storyteller.blackout_state(), "dark", "still dark at three")
	near(sim.storyteller.aim_mult(10.0), 0.75, 0.0001, "and the aim is worse")
	Helpers.run_to_hour(sim, 6.6)
	eq(sim.storyteller.blackout_state(), "", "by day it is mended")
	check(sim.alerts.has("story-lights"), "and the crew is told")
	g.world.free()


func test_when_dez_is_gone_the_best_builder_goes() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("blackout")
	sim.storyteller.choose(0)
	_person(sim, "Dez").dead = true
	Helpers.run_to_hour(sim, 21.1)
	var hector = _person(sim, "Hector")
	check(hector.order != null and hector.drafted, "Hector, the next builder, is sent")
	g.world.free()


func test_another_order_takes_the_mechanic_off_the_job_and_the_dark_stays() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("blackout")
	sim.storyteller.choose(0)
	Helpers.run_to_hour(sim, 21.1)
	var dez = _person(sim, "Dez")
	check(dez.order != null, "Dez is on his way")
	sim.order_move(dez, 30.0, 30.0)
	Helpers.run(sim, 40.0)
	eq(sim.storyteller.blackout_state(), "dark", "he was given another order, so it stays dark")
	Helpers.run_to_hour(sim, 6.6)
	eq(sim.storyteller.blackout_state(), "", "until morning")
	g.world.free()


func test_the_dark_costs_aim_beyond_six_tiles_in_the_shooting() -> void:
	var hits := {}
	for dark in [false, true]:
		for dist in [4.0, 9.0]:
			var g := _noon(8, 4)
			var sim = g.sim
			sim.minutes = 22.0 * 60.0
			sim.phase = "night"
			if dark:
				sim.storyteller.blackout = {"state": "dark", "at": 0.0, "send": false, "fixer": "", "work": 0.0}
			var dez = _person(sim, "Dez")
			dez.x = 40.0
			dez.y = 19.0
			var z = sim.spawn(40.0, 19.0 - dist, "wander")
			z.speed = 0.0
			z.hp = 1.0e9
			var start_hp: float = z.hp
			var shots := 700
			sim.stock.ammo = 1.0e6
			for i in shots:
				dez.mag = 20
				dez.cooldown = 0.0
				z.stagger = 0.0
				sim._fire(dez, z, -PI / 2.0)
			hits["%s-%d" % [dark, int(dist)]] = (start_hp - z.hp) / float(sim.weapons.rifle.dmg) / float(shots)
			g.world.free()
	var near_ratio: float = hits["true-4"] / hits["false-4"]
	var far_ratio: float = hits["true-9"] / hits["false-9"]
	check(near_ratio > 0.9 and near_ratio < 1.1, "within six tiles the dark changes nothing: %.2f" % near_ratio)
	check(far_ratio > 0.68 and far_ratio < 0.82, "beyond them a quarter of the hits are lost: %.2f" % far_ratio)


func test_the_blackout_survives_a_save() -> void:
	var g := _noon(8)
	var sim = g.sim
	sim.storyteller.force("blackout")
	sim.storyteller.choose(0)
	Helpers.run_to_hour(sim, 21.3)
	var saved: Dictionary = sim.storyteller.save()
	var other := _noon(8, 2)
	other.sim.storyteller.load_state(SaveGame.from_text(SaveGame.to_text({"story": saved})).story)
	eq(other.sim.storyteller.blackout_state(), "dark", "dark again after the load")
	eq(other.sim.storyteller.save(), saved, "the same state, through a text file")
	g.world.free()
	other.world.free()


# ------------------------------------------------------- the effect vocabulary --
# What no card of the deck uses yet is still part of what a card may say.

func _apply(sim, effects: Array, ctx: Dictionary = {}) -> Dictionary:
	return sim.storyteller._apply(effects, ctx)


func test_a_wound_bleeds_the_person_it_names() -> void:
	var g := _noon()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var out := _apply(sim, [{"wound": {"who": "dez", "kind": "scratch"}}])
	check(dez.bleeding > 0.0 and dez.wounds == 1, "Dez is bleeding from one wound: %s" % str(dez.bleeding))
	eq(out.changes, ["Dez is scratched"], "and the card says so")
	var ana = _person(sim, "Ana")
	sim.difficulty = 0
	_apply(sim, [{"wound": {"who": "ana", "kind": "bite"}}])
	check(ana.bleeding > dez.bleeding, "a bite bleeds more than a scratch")
	var named := _apply(sim, [{"wound": {"who": "@person", "kind": "bite"}}], {"person": "walt"})
	check(_person(sim, "Walt").wounds == 1 and named.changes == ["Walt is bitten"], "@person names the one the card chose")
	g.world.free()


func test_the_stores_move_by_a_number_or_a_share_and_never_below_nothing() -> void:
	var g := _noon()
	var sim = g.sim
	var out := _apply(sim, [{"stock": {"ammo": -50, "scrap": 5, "food": {"pct": -50}}}])
	near(float(sim.stock.ammo), 150.0, 0.001, "ammo by a number")
	near(float(sim.stock.scrap), 35.0, 0.001, "scrap by a number")
	near(float(sim.stock.food), 20.0, 0.06, "food by a share")
	eq(out.changes, ["Food -50% (-20)", "Scrap +5", "Ammo -50"], "told in the order of the stores")
	_apply(sim, [{"stock": {"meds": -999}}])
	eq(float(sim.stock.meds), 0.0, "never below nothing")
	g.world.free()


func test_morale_goes_to_everyone_one_person_a_role_or_the_speaker() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("quiet_day")
	sim.morale.spy_shocks.clear()
	sim.storyteller.choose(0)
	_apply(sim, [
		{"morale": {"who": "ana", "delta": 3, "label": "one"}},
		{"morale": {"who": "role:Lookout", "delta": -2, "label": "role"}},
		{"morale": {"who": "speaker", "delta": 1, "label": "speaker"}},
		{"morale": {"who": "nobody", "delta": 1, "label": "nobody"}},
	], {"speaker_id": "walt"})
	eq(sim.morale.spy_shocks, [
		{"who": "ana", "delta": 3.0, "label": "one"},
		{"who": "marcus", "delta": -2.0, "label": "role"},
		{"who": "walt", "delta": 1.0, "label": "speaker"},
	], "each reaches the one it names, and a name nobody has reaches nobody")
	g.world.free()


func test_the_dead_are_not_lifted_or_hurt() -> void:
	var g := _noon()
	var sim = g.sim
	_person(sim, "Hector").dead = true
	_apply(sim, [{"morale": {"who": "all", "delta": 5, "label": "x"}}, {"morale": {"who": "hector", "delta": 5, "label": "y"}}])
	eq(sim.morale.spy_shocks.size(), 1, "only the call for everyone: nothing for the one who is gone")
	g.world.free()


func test_weather_can_be_set_and_cleared() -> void:
	var g := _noon()
	var sim = g.sim
	_apply(sim, [{"weather": "fog"}])
	eq(sim.weather, "fog", "fog")
	var out := _apply(sim, [{"weather": "clear"}])
	eq(sim.weather, "clear", "and clear again")
	eq(out.changes, ["The sky clears"], "which the card says")
	_apply(sim, [{"weather": "hail"}])
	eq(sim.weather, "clear", "a weather the rules do not have is ignored")
	g.world.free()


func test_a_chance_of_one_always_happens_and_a_chance_of_nothing_never_does() -> void:
	var g := _noon()
	var sim = g.sim
	for i in 30:
		sim.stock.ammo = 100.0
		_apply(sim, [{"chance": {"p": 1.0, "then": [{"stock": {"ammo": 1}}], "else": [{"stock": {"ammo": 1000}}]}}])
		eq(float(sim.stock.ammo), 101.0, "p = 1: the first branch")
		sim.stock.ammo = 100.0
		_apply(sim, [{"chance": {"p": 0.0, "then": [{"stock": {"ammo": 1000}}], "else": [{"stock": {"ammo": 2}}]}}])
		eq(float(sim.stock.ammo), 102.0, "p = 0: the other")
	g.world.free()


func test_a_chance_is_settled_by_the_rules_dice() -> void:
	var g := _noon()
	var sim = g.sim
	var before: int = sim.rng.state
	_apply(sim, [{"chance": {"p": 0.5, "then": [], "else": []}}])
	check(sim.rng.state != before, "the rules' own dice were thrown")
	var other := _noon(8, 5)
	var seen := {}
	for i in 40:
		other.sim.stock.ammo = 0.0
		_apply(other.sim, [{"chance": {"p": 0.5, "then": [{"stock": {"ammo": 1}}], "else": []}}])
		seen[float(other.sim.stock.ammo)] = true
	eq(seen.size(), 2, "and both come up")
	g.world.free()
	other.world.free()


func test_what_is_said_replaces_what_the_card_says_and_changes_are_kept() -> void:
	var g := _noon()
	var sim = g.sim
	var out := _apply(sim, [{"say": "It went well."}, {"stock": {"scrap": 3}}, {"say": "Mostly."}])
	eq(out.say, ["It went well.", "Mostly."], "the lines")
	eq(out.changes, ["Scrap +3"], "and the change")
	g.world.free()


func test_the_tension_can_be_moved_by_a_card() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.tension = 50.0
	_apply(sim, [{"tension": 15}])
	eq(sim.storyteller.tension, 65.0, "up")
	_apply(sim, [{"tension": -100}])
	eq(sim.storyteller.tension, 0.0, "and not below nothing")
	_apply(sim, [{"tension": 500}])
	eq(sim.storyteller.tension, 100.0, "or over a hundred")
	g.world.free()


func test_two_warnings_in_a_day_stack() -> void:
	var g := _noon()
	var sim = g.sim
	_apply(sim, [{"night_budget": {"multiplier": 1.3}}])
	_apply(sim, [{"night_budget": {"multiplier": 2.0}}])
	near(sim.storyteller.budget_mult(8), 2.6, 0.0001, "1.3 and 2 make 2.6")
	g.world.free()


func test_the_dead_can_be_sent_to_any_side_or_a_named_wall_piece_or_the_yard() -> void:
	for spec in [["west", "W"], ["east", "E"], ["north", "N"]]:
		var g := _noon()
		var sim = g.sim
		_apply(sim, [{"spawn_day": {"count": 3, "at": spec[0]}}])
		var dead := _alive_dead(sim)
		eq(dead.size(), 3, "three come to the %s wall" % spec[0])
		for z in dead:
			if z.slot != null:
				eq(z.slot.seg.side, spec[1], "at the %s side" % spec[0])
		g.world.free()
	var h := _noon()
	_apply(h.sim, [{"spawn_day": {"count": 2, "at": "3"}}])
	for z in _alive_dead(h.sim):
		check(z.slot != null and z.slot.seg.id == 3, "at the piece named by its number")
	h.world.free()
	var y := _noon()
	_apply(y.sim, [{"spawn_day": {"count": 1, "at": "gate", "inside": true}}])
	var inside := _alive_dead(y.sim)
	eq(inside.size(), 1, "one in the yard")
	eq(inside[0].state, "breach", "after somebody")
	y.world.free()


func test_the_dead_are_not_sent_to_a_wall_that_is_down() -> void:
	var g := _noon()
	var sim = g.sim
	for s in sim.segments:
		if s.side == "N" and s.id != 3:
			sim._damage_segment(s, s.max_hp + 1.0)
	_apply(sim, [{"spawn_day": {"count": 2, "at": "north"}}])
	for z in _alive_dead(sim):
		if z.slot != null:
			eq(z.slot.seg.id, 3, "the one piece of the north wall still standing")
	g.world.free()


func test_a_wall_piece_can_be_hurt_by_name_and_a_breach_is_the_rules_breach() -> void:
	var g := _noon()
	var sim = g.sim
	var seg = sim.segments[3]
	var before: float = seg.hp
	_apply(sim, [{"wall_damage": {"section": "3", "fraction": 0.5}}])
	near(float(seg.hp), before - seg.max_hp * 0.5, 0.001, "half its health")
	_apply(sim, [{"wall_damage": {"section": "3", "fraction": 0.9}}])
	eq(seg.state, 3, "taken far enough it is down, as the rules have it")
	g.world.free()


func test_a_sickness_can_be_given_to_a_named_person_for_as_long_as_the_card_says() -> void:
	var g := _noon()
	var sim = g.sim
	_apply(sim, [{"sick": {"who": "walt", "hours": 3}}])
	var walt = _person(sim, "Walt")
	check(sim.storyteller.is_sick(walt), "Walt is sick")
	Helpers.run(sim, 2.5 * 20.0)
	check(sim.storyteller.is_sick(walt), "after two and a half hours")
	Helpers.run(sim, 1.0 * 20.0)
	check(not sim.storyteller.is_sick(walt), "and not after three")
	g.world.free()


func test_what_waits_for_its_hour_waits_and_then_happens_once() -> void:
	var g := _noon()
	var sim = g.sim
	var out := _apply(sim, [{"at_hour": {"hour": 15, "note": "At three", "do": [{"stock": {"scrap": 7}}]}}])
	eq(out.changes, ["At three"], "the card says when")
	var scrap: float = sim.stock.scrap
	Helpers.run_to_hour(sim, 14.9)
	near(float(sim.stock.scrap), scrap, 0.001, "nothing at 14:54")
	Helpers.run_to_hour(sim, 15.1)
	near(float(sim.stock.scrap), scrap + 7.0, 0.001, "7 scrap at three")
	Helpers.run(sim, 40.0)
	near(float(sim.stock.scrap), scrap + 7.0, 0.001, "and only once")
	g.world.free()


func test_a_card_that_comes_later_is_delayed_while_another_is_up() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("cry_at_gate")
	sim.storyteller.force("quiet_day")
	check(not sim.storyteller.pending().is_empty() and sim.storyteller.pending().id == "quiet_day", "another card is up at noon")
	# it is still pending at six: the evening's card waits its turn
	sim.storyteller._card["due"] = sim.clock_min + 100000.0
	Helpers.run_to_hour(sim, 18.2)
	eq(sim.storyteller.pending().id, "quiet_day", "the first is still up")
	check(sim.storyteller.schedule.size() >= 1, "and the cry is still to come")
	sim.storyteller.choose(0)
	Helpers.run(sim, 12.0)
	eq(sim.storyteller.pending().get("id", ""), "cry_at_gate", "it comes when the first is put away")
	g.world.free()


func test_a_card_forced_when_nobody_is_up_to_name_leaves_no_braces() -> void:
	var g := _noon()
	var sim = g.sim
	for p in sim.people:
		p.downed = true
	for id in ["old_friends", "fever", "argument", "radio_trade"]:
		sim.storyteller.force(id)
		var up: Dictionary = sim.storyteller.pending()
		if up.is_empty():
			continue
		check(not String(up.text).contains("{") and not String(up.title).contains("{"), "%s: no braces are left in '%s'" % [id, String(up.text)])
		sim.storyteller._close()
	g.world.free()


func test_a_card_that_names_someone_is_not_drawn_when_the_only_one_about_is_sick() -> void:
	var g := _noon()
	var sim = g.sim
	for p in sim.people:
		if p.first != "Ruth":
			p.dead = true
	var card: Dictionary = sim.storyteller.card_named("old_friends")
	check(sim.storyteller._needs_ok(card.needs), "with Ruth well it can be drawn")
	sim.storyteller.sick["ruth"] = sim.clock_min + 600.0
	check(sim.storyteller.is_sick(_person(sim, "Ruth")), "Ruth has a fever")
	check(not sim.storyteller._needs_ok(card.needs), "with her sick there is nobody well enough to name, and the card is not drawn")
	g.world.free()


func test_a_card_that_names_nobody_when_nobody_is_up_does_nothing_odd() -> void:
	var g := _noon()
	var sim = g.sim
	for p in sim.people:
		if p.first != "Ruth":
			p.dead = true
	var card: Dictionary = sim.storyteller.card_named("fever")
	check(not sim.storyteller._needs_ok(card.needs), "a fever needs two people about")
	sim.storyteller.force("old_friends")
	var up: Dictionary = sim.storyteller.pending()
	check(not String(up.text).contains("{"), "no braces are left")
	g.world.free()
