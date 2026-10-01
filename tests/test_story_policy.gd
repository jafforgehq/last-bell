extends "res://tests/case.gd"
## The balance harness and the storyteller (tools/balance.gd): when a card is waiting the policy takes
## the answer the card names as its default, once for each card (a card with no choice is read), and
## says so in its notes; the default and the informed policy both do; a daytime alarm (stragglers
## at the wall) stands the best shooters to their posts until the dead are gone; a game can be played
## with the storyteller off (`story` false) to see what it changes.

const Helpers := preload("res://tests/helpers.gd")
const Balance := preload("res://tools/balance.gd")


## Midday of day 8, the storyteller on, the radio hour already held, plenty in the stores.
func _noon(seed_value: int = 5) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.storyteller.enabled = true
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 8
	sim.minutes = 12.0 * 60.0
	sim.clock_min = 7.0 * 1440.0 + 300.0
	sim.phase = "day"
	sim.bell_rung = false
	sim.supplies.sources_day = 8
	sim.supplies.meal_day = 8
	sim.supplies.meals_done = 1
	sim.storyteller.radio_day = 8
	sim.stock = {"ammo": 300.0, "scrap": 30.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	Helpers.idle_stores(sim)    # the bench and the beds would change the stores the cards are measured by
	sim.events.clear()
	return g


func _alive_dead(sim) -> Array:
	var out: Array = []
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			out.append(z)
	return out


func test_the_default_policy_answers_a_card_with_the_choice_the_card_names() -> void:
	var g := _noon()
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	sim.storyteller.force("stranger")
	eq(sim.storyteller.pending().bot, 1, "the stranger's default is the trade")
	var ammo: float = sim.stock.ammo
	policy.tick()
	check(sim.storyteller.pending().is_empty(), "the card is answered")
	near(float(sim.stock.ammo), ammo - 15.0, 0.001, "with the trade across the gate")
	eq(policy.cards, 1, "and counted")
	var said := false
	for n in policy.notes:
		if String(n.text).contains("Someone at the gate") and String(n.text).contains("Trade across the gate"):
			said = true
	check(said, "and the notes say what it answered: %s" % str(policy.notes))
	g.world.free()


func test_the_informed_policy_answers_too() -> void:
	var g := _noon()
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	sim.storyteller.force("radio_trade")
	policy.tick()
	check(sim.storyteller.pending().is_empty(), "the card is answered")
	eq(policy.cards, 1, "once")
	g.world.free()


func test_the_hiding_policy_answers_too() -> void:
	var g := _noon()
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	policy.hide = true
	sim.storyteller.force("argument")
	policy.tick()
	check(sim.storyteller.pending().is_empty(), "the card is answered")
	g.world.free()


func test_a_card_with_no_choice_is_read() -> void:
	var g := _noon()
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	sim.storyteller.force("quiet_day")
	check(not sim.storyteller.pending().is_empty(), "the card is up")
	policy.tick()
	check(sim.storyteller.pending().is_empty(), "read and put away")
	eq(policy.cards, 1, "counted")
	g.world.free()


## How many of the policy's notes are about the radio (it also notes the jobs it gives).
func _radio_notes(policy) -> int:
	var n := 0
	for note in policy.notes:
		if String(note.text).contains("radio"):
			n += 1
	return n


func test_each_card_is_answered_once() -> void:
	var g := _noon()
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	sim.storyteller.force("stranger")
	policy.tick()
	policy.tick()
	policy.tick()
	eq(policy.cards, 1, "three ticks, one answer")
	eq(_radio_notes(policy), 1, "and one note about it")
	g.world.free()


func test_a_choice_that_cannot_be_made_is_left_to_the_default_and_not_tried_again() -> void:
	var g := _noon()
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	sim.storyteller.card_named("radio_trade")["bot"] = 0
	sim.storyteller.force("radio_trade")
	sim.stock.meds = 2.0
	policy.tick()
	policy.tick()
	check(not sim.storyteller.pending().is_empty(), "the card still waits")
	eq(policy.cards, 0, "nothing was answered")
	eq(_radio_notes(policy), 1, "it said so once")
	g.world.free()


func test_a_new_card_a_few_days_later_is_answered_again() -> void:
	var g := _noon()
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	sim.storyteller.force("quiet_day")
	policy.tick()
	sim.day = 10
	sim.storyteller.force("heavy_rain")
	policy.tick()
	eq(policy.cards, 2, "two cards, two answers")
	g.world.free()


func test_a_game_has_cards_and_plays_the_same_from_the_same_seed_and_has_none_with_the_storyteller_off() -> void:
	var quiet := func(sim): sim.waves.enabled = false
	var a: Dictionary = Balance.play(41, 1, 5, 10.0, true, quiet)
	var b: Dictionary = Balance.play(41, 1, 5, 10.0, true, quiet)
	check(a.cards >= 1, "in five days the radio brought cards: %d answered" % a.cards)
	eq(b.cards, a.cards, "the same seed, the same cards")
	eq(b.rows, a.rows, "and the same colony, day by day")
	var off: Dictionary = Balance.play(41, 1, 5, 10.0, true, quiet, false, false, false)
	eq(off.cards, 0, "with the storyteller off, no card is answered")
	var notes := ""
	for n in off.notes:
		notes += String(n.text)
	check(not notes.contains("radio"), "and none is told")
	var told := false
	for n in a.notes:
		told = told or String(n.text).contains("radio")
	check(told, "with it on the notes say what was answered")


func test_with_no_orders_a_card_is_left_to_its_default_after_two_hours() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("stranger")
	var ammo: float = sim.stock.ammo
	Helpers.run(sim, 2.5 * 20.0)
	check(sim.storyteller.pending().is_empty(), "nobody answered, and the card is settled")
	near(float(sim.stock.ammo), ammo - 15.0, 0.001, "by its default, the trade")
	g.world.free()


# ------------------------------------------------------------ the daytime alarm --

func test_the_policy_stands_the_best_shooters_to_the_wall_against_dead_by_day() -> void:
	var g := _noon()
	var sim = g.sim
	var policy = Balance.Policy.new(sim)
	sim.storyteller.force("stragglers")
	policy.tick()
	var drafted_peak := 0
	var breached := false
	for i in 90 * 30:
		sim.update(1.0 / 30.0)
		if i % 30 == 0:
			policy.tick()
		var drafted := 0
		for p in sim.people:
			if p.drafted and p.order != null:
				drafted += 1
		drafted_peak = maxi(drafted_peak, drafted)
		for s in sim.segments:
			breached = breached or s.state == 3
	check(drafted_peak >= 2 and drafted_peak <= 3, "two or three of the crew stood to: %d" % drafted_peak)
	eq(_alive_dead(sim).size(), 0, "and the dead were put down")
	var still := 0
	for p in sim.people:
		if p.drafted and p.order != null:
			still += 1
	eq(still, 0, "afterwards everyone is let go")
	check(not breached, "and the wall held")
	check(sim.kills >= 8, "the stragglers were shot: %d" % sim.kills)
	var said := false
	for n in policy.notes:
		said = said or String(n.text).contains("stands")
	check(said, "and the notes say so: %s" % str(policy.notes))
	g.world.free()


func test_without_the_alarm_response_the_stragglers_stay_at_the_wall_and_cost_scrap() -> void:
	var g := _noon()
	var sim = g.sim
	sim.storyteller.force("stragglers")
	Helpers.run_to_hour(sim, 16.5)
	eq(_alive_dead(sim).size(), 8, "left alone by day all eight are still at the wall at 16:30")
	check(float(sim.stock.scrap) < 20.0, "and the builders have been mending what they claw: %.1f scrap left of 30" % float(sim.stock.scrap))
	g.world.free()
