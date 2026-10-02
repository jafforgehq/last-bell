extends "res://tests/case.gd"
## The storyteller (scripts/sim/storyteller.gd): a hidden tension, a card a day at the radio
## hour (12:00) and the rules of the draw: about two days in three, never the first day or the
## last, at most two threats in a row, the same card not again within six days, leaning on the
## tension, the style of the difficulty; its own generator (the run's seed and the day), the
## radio's speaker, a card that waits for an answer and takes its default after two game hours,
## the off switch, and the saves.

const Helpers := preload("res://tests/helpers.gd")
const Storyteller := preload("res://scripts/sim/storyteller.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


## A card of the shape events.json gives (see Storyteller.normalise): `with` overrides its fields.
func _card(id: String, kind: String, weight: float = 1.0, with: Dictionary = {}) -> Dictionary:
	var raw := {"id": id, "kind": kind, "weight": weight, "title": "Card %s" % id, "text": "Text of %s." % id}
	raw.merge(with, true)
	return Storyteller.normalise(raw)


## `n` distinct cards of one kind, named `<kind>0`, `<kind>1`...
func _deck(kind: String, n: int, weight: float = 1.0) -> Array:
	var out: Array = []
	for i in n:
		out.append(_card("%s%d" % [kind, i], kind, weight))
	return out


## A quiet day on the chosen day and hour (the nights off, no dead about) with the storyteller on.
func _game(day: int = 5, hour: float = 11.5, seed_value: int = 11, difficulty: int = 1) -> Dictionary:
	var g := Helpers.make(seed_value, difficulty)
	var sim = g.sim
	sim.storyteller.enabled = true
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day
	sim.events.clear()
	return g


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## Plays `seconds` of the rules' time (a game hour is 20 seconds).
func _run(sim, seconds: float) -> void:
	Helpers.run(sim, seconds)


func _events_of(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if e.type == type:
			out.append(e)
	return out


## Sets the run's seed to one for which the draw gives a card on `day`.
func _seed_with_a_card(sim, day: int) -> void:
	for s in range(1, 200):
		sim.run_seed = s
		if not sim.storyteller.draw(day).is_empty():
			return
	check(false, "no seed gives a card on day %d" % day)


# ------------------------------------------------------------- the draw --

func test_there_is_no_card_on_the_first_day_or_on_the_last() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = _deck("boon", 12)
	for s in 60:
		sim.run_seed = s
		eq(sim.storyteller.draw(1), {}, "day 1 is a quiet start (seed %d)" % s)
		eq(sim.storyteller.draw(30), {}, "day 30 is the Big Night (seed %d)" % s)
		eq(sim.storyteller.draw(31), {}, "and nothing comes after it")
	g.world.free()


func test_about_two_days_in_three_bring_a_card() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = _deck("boon", 12)
	var days := 0
	var with_card := 0
	for s in 40:
		sim.run_seed = s
		for day in range(2, 30):
			days += 1
			if not sim.storyteller.draw(day).is_empty():
				with_card += 1
	var share := float(with_card) / float(days)
	check(share > 0.58 and share < 0.76, "%d of %d days had a card (%.2f)" % [with_card, days, share])
	g.world.free()


func test_a_card_only_comes_inside_its_days() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = [_card("late", "boon", 1.0, {"min_day": 8, "max_day": 12})]
	for s in 60:
		sim.run_seed = s
		for day in range(2, 30):
			if day < 8 or day > 12:
				eq(sim.storyteller.draw(day), {}, "no card on day %d (seed %d)" % [day, s])
	var any := false
	for s in 60:
		sim.run_seed = s
		for day in range(8, 13):
			any = any or not sim.storyteller.draw(day).is_empty()
	check(any, "but it does come on days 8 to 12")
	g.world.free()


func test_never_more_than_two_threats_in_a_row() -> void:
	var g := _game()
	var sim = g.sim
	var threats := _deck("threat", 8, 1.0)
	sim.storyteller.cards = threats + [_card("boon0", "boon", 0.25), _card("choice0", "choice", 0.25)]
	var worst := 0
	var threat_days := 0
	for s in 30:
		sim.run_seed = s
		sim.storyteller.history.clear()
		sim.storyteller.recent.clear()
		var run := 0
		for day in range(2, 30):
			var c: Dictionary = sim.storyteller.draw(day)
			if c.is_empty():
				continue
			sim.storyteller.remember(c, day)
			run = run + 1 if c.kind == "threat" else 0
			worst = maxi(worst, run)
			threat_days += 1 if c.kind == "threat" else 0
	check(threat_days > 100, "there were plenty of threats to count: %d" % threat_days)
	eq(worst, 2, "threats came two at a time, never three")
	g.world.free()


func test_a_card_is_not_drawn_again_within_six_days() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = _deck("boon", 4)
	var shortest := 99
	var drawn := 0
	for s in 30:
		sim.run_seed = s
		sim.storyteller.history.clear()
		sim.storyteller.recent.clear()
		var last := {}
		for day in range(2, 30):
			var c: Dictionary = sim.storyteller.draw(day)
			if c.is_empty():
				continue
			sim.storyteller.remember(c, day)
			drawn += 1
			if last.has(c.id):
				shortest = mini(shortest, day - int(last[c.id]))
			last[c.id] = day
	check(drawn > 100 and shortest < 99, "the same cards did come round again: %d draws" % drawn)
	check(shortest >= 6, "never sooner than six days later: %d" % shortest)
	g.world.free()


func test_low_tension_leans_to_threats_and_high_tension_to_boons() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = _deck("threat", 5) + _deck("boon", 5)
	var share := {}
	for tension in [10.0, 50.0, 90.0]:
		sim.storyteller.tension = tension
		var threats := 0
		var cards := 0
		for s in 400:
			sim.run_seed = s
			var c: Dictionary = sim.storyteller.draw(9)
			if c.is_empty():
				continue
			cards += 1
			threats += 1 if c.kind == "threat" else 0
		share[tension] = float(threats) / float(cards)
	check(share[10.0] > 0.58 and share[10.0] < 0.76, "under 20 threats are twice as likely: %.2f of the cards" % share[10.0])
	check(share[50.0] > 0.42 and share[50.0] < 0.58, "in the middle it is an even draw: %.2f" % share[50.0])
	check(share[90.0] > 0.24 and share[90.0] < 0.42, "over 70 boons are twice as likely: %.2f threats" % share[90.0])
	g.world.free()


func test_the_style_follows_the_difficulty() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = _deck("threat", 5) + _deck("boon", 5)
	sim.storyteller.tension = 50.0
	var share := {}
	for difficulty in [0, 1, 2]:
		sim.difficulty = difficulty
		var threats := 0
		var cards := 0
		for s in 400:
			sim.run_seed = s
			var c: Dictionary = sim.storyteller.draw(9)
			if c.is_empty():
				continue
			cards += 1
			threats += 1 if c.kind == "threat" else 0
		share[difficulty] = float(threats) / float(cards)
	check(share[0] > 0.30 and share[0] < 0.46, "Story is calm (threats x0.6): %.2f threats" % share[0])
	check(share[1] > 0.42 and share[1] < 0.58, "Standard is even: %.2f" % share[1])
	check(share[2] > 0.60 and share[2] < 0.76, "Brutal brings more threats and fewer boons: %.2f" % share[2])
	g.world.free()


func test_the_draw_has_its_own_generator_seeded_by_the_run_and_the_day() -> void:
	var g := _game(5, 11.5, 21)
	var sim = g.sim
	sim.storyteller.cards = _deck("boon", 6) + _deck("threat", 6)
	var before: int = sim.rng.state
	var picks: Array = []
	for day in range(2, 30):
		picks.append(sim.storyteller.draw(day).get("id", ""))
	eq(sim.rng.state, before, "the draw does not touch the rules' dice")
	var again: Array = []
	for day in range(2, 30):
		again.append(sim.storyteller.draw(day).get("id", ""))
	eq(again, picks, "the same run and day always give the same card")
	var other := _game(5, 11.5, 22)
	other.sim.storyteller.cards = _deck("boon", 6) + _deck("threat", 6)
	var differs := false
	for day in range(2, 30):
		if other.sim.storyteller.draw(day).get("id", "") != picks[day - 2]:
			differs = true
	check(differs, "another seed tells another story")
	other.world.free()
	g.world.free()


func test_the_same_seed_and_orders_play_the_same_story() -> void:
	var tales: Array = []
	for round in 2:
		var g := Helpers.make(31, 1)
		var sim = g.sim
		sim.storyteller.enabled = true
		sim.waves.enabled = false
		var told: Array = []
		var days := 0
		while sim.day < 9 and days < 400000:
			sim.update(1.0 / 15.0)
			days += 1
			var c: Dictionary = sim.storyteller.pending()
			if not c.is_empty() and not told.has("%d:%s" % [sim.day, c.id]):
				told.append("%d:%s" % [sim.day, c.id])
				sim.storyteller.choose(int(c.bot))
		tales.append(told)
		g.world.free()
	eq(tales[1], tales[0], "two runs of one seed tell the same cards on the same days")
	check(not tales[0].is_empty(), "and some cards were told: %s" % str(tales[0]))


func test_an_unusable_card_is_not_drawn() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.cards = [_card("trade", "choice", 1.0, {"needs": {"stock": {"meds": 5}}})]
	sim.stock.meds = 2.0
	for s in 40:
		sim.run_seed = s
		eq(sim.storyteller.draw(6), {}, "with 2 medicine there is no trade to offer")
	sim.stock.meds = 6.0
	_seed_with_a_card(sim, 6)
	eq(sim.storyteller.draw(6).id, "trade", "with 6 there is")
	g.world.free()


# ------------------------------------------------------------ the radio --

func test_ruth_takes_the_radio_at_noon_and_the_card_waits_for_an_answer() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = [_card("news", "choice", 1.0, {
		"choices": [{"label": "Yes", "hint": "Costs nothing."}, {"label": "No", "hint": "Costs nothing either."}], "bot": 1})]
	_seed_with_a_card(sim, 5)
	check(sim.storyteller.pending().is_empty(), "nothing before the hour")
	_run(sim, 1.0)
	check(sim.storyteller.pending().is_empty(), "still nothing at 11:57")
	_run(sim, 4.0)
	var card: Dictionary = sim.storyteller.pending()
	check(not card.is_empty(), "at noon the radio brings a card")
	eq(card.id, "news", "the one drawn")
	eq(card.speaker, "Ruth", "Ruth is at the radio")
	eq(card.title, "Card news", "with its title")
	eq(card.choices.size(), 2, "and two ways to answer")
	eq(card.choices[0].label, "Yes", "the first")
	eq(card.choices[1].hint, "Costs nothing either.", "and the second one's hint")
	eq(_events_of(sim, "story_card").size(), 1, "the view is told")
	check(sim.alerts.has("story"), "and an alert stays up while the card waits")
	eq(sim.storyteller.radio_day, 5, "the day's radio hour is spent")
	_run(sim, 4.0)
	eq(sim.storyteller.pending().id, "news", "the card waits: it is still there")
	eq(_events_of(sim, "story_card").size(), 1, "and was not told twice")
	g.world.free()


func test_the_speaker_is_the_person_at_the_radio_desk() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = _person(sim, "Ruth")
	var walt = _person(sim, "Walt")
	eq(sim.storyteller.speaker(), ruth, "Ruth, at the desk she is given to begin with")
	ruth.downed = true
	eq(sim.storyteller.speaker(), null, "with her down nobody is at the radio: the best leader does not take her place")
	ruth.downed = false
	sim.jobs.unassign(ruth)
	Helpers.seat(sim, walt, "radio")
	eq(sim.storyteller.speaker(), walt, "put Walt at the desk and he speaks")
	walt.away = {"kind": "party"}
	eq(sim.storyteller.speaker(), null, "away, he cannot")
	walt.away = null
	walt.dead = true
	eq(sim.storyteller.speaker(), null, "nor can the dead")
	g.world.free()


func test_with_nobody_at_the_radio_there_is_no_card() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = _deck("boon", 6)
	_seed_with_a_card(sim, 5)
	for p in sim.people:
		p.downed = true
	_run(sim, 5.0)
	check(sim.storyteller.pending().is_empty(), "radio silence")
	eq(sim.storyteller.radio_day, 5, "and the day is spent all the same")
	g.world.free()


func test_the_radio_hour_comes_once_a_day() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = _deck("boon", 6)
	_seed_with_a_card(sim, 5)
	_run(sim, 5.0)
	var first: Dictionary = sim.storyteller.pending()
	check(not first.is_empty(), "a card at noon")
	sim.storyteller.choose(0)
	_run(sim, 60.0)
	check(sim.storyteller.pending().is_empty() or sim.storyteller.pending().id == first.id, "no second card the same day")
	g.world.free()


func test_a_card_with_a_choice_is_settled_by_choose() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = [_card("deal", "choice", 1.0, {
		"choices": [
			{"label": "Take it", "hint": "Brings 10 ammo.", "result": "We took it.", "effects": [{"stock": {"ammo": 10}}]},
			{"label": "Leave it", "hint": "Nothing.", "result": "We left it.", "effects": []}],
		"bot": 1})]
	_seed_with_a_card(sim, 5)
	_run(sim, 5.0)
	sim.events.clear()
	var ammo: float = sim.stock.ammo
	check(not sim.storyteller.choose(2), "a choice that is not there is refused")
	check(not sim.storyteller.choose(-1), "so is a negative one")
	check(sim.storyteller.choose(0), "the first is taken")
	eq(float(sim.stock.ammo), ammo + 10.0, "and does what it says")
	check(sim.storyteller.pending().is_empty(), "the card is settled")
	check(not sim.alerts.has("story"), "so the waiting alert goes")
	var done := _events_of(sim, "story_resolved")
	eq(done.size(), 1, "the view is told it is settled")
	eq(done[0].id, "deal", "which card")
	eq(done[0].text, "We took it.", "and what came of it")
	check(sim.alerts.has("story-deal"), "an alert keeps the outcome")
	check(not sim.storyteller.choose(0), "nothing is pending any more")
	g.world.free()


func test_a_card_left_alone_takes_its_default_choice_two_game_hours_later() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = [_card("deal", "choice", 1.0, {
		"choices": [
			{"label": "Take it", "hint": "Brings 10 ammo.", "effects": [{"stock": {"ammo": 10}}]},
			{"label": "Leave it", "hint": "Nothing.", "effects": [{"stock": {"scrap": 5}}]}],
		"bot": 1})]
	_seed_with_a_card(sim, 5)
	_run(sim, 5.0)
	check(not sim.storyteller.pending().is_empty(), "the card is up")
	var ammo: float = sim.stock.ammo
	var scrap: float = sim.stock.scrap
	_run(sim, 36.0)
	check(not sim.storyteller.pending().is_empty(), "an hour and 48 minutes later it still waits")
	_run(sim, 6.0)
	check(sim.storyteller.pending().is_empty(), "after two hours it is settled")
	eq(float(sim.stock.scrap), scrap + 5.0, "by the choice the card names as its default")
	eq(float(sim.stock.ammo), ammo, "and not the other")
	g.world.free()


func test_a_card_with_no_choice_is_settled_at_once_and_waits_to_be_read() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = [_card("rain", "boon", 1.0, {"effects": [{"stock": {"water": 20}}], "result": "The barrels are full."})]
	_seed_with_a_card(sim, 5)
	var water: float = sim.stock.water
	_run(sim, 5.0)
	var card: Dictionary = sim.storyteller.pending()
	check(not card.is_empty(), "the card is up")
	eq(card.choices.size(), 1, "with one way to answer")
	eq(card.choices[0].label, "Understood", "Understood")
	check(card.resolved, "it says it has happened")
	eq(card.result, "The barrels are full.", "with what came of it")
	eq(card.changes, ["Water +20"], "and exactly what changed")
	check(float(sim.stock.water) >= water + 20.0 - 0.01, "the water is in the barrels already")
	var after: float = sim.stock.water
	check(sim.storyteller.choose(0), "Understood")
	eq(float(sim.stock.water), after, "reading it changes nothing more")
	check(sim.storyteller.pending().is_empty(), "and puts it away")
	g.world.free()


# -------------------------------------------------------- the off switch --

func test_switched_off_the_storyteller_does_nothing_at_all() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.enabled = false
	sim.storyteller.cards = _deck("boon", 6)
	_seed_with_a_card(sim, 5)
	sim.storyteller.tension = 40.0
	sim._damage_segment(sim.segments[1], 1000.0)
	_run(sim, 5.0)
	check(sim.storyteller.pending().is_empty(), "no card at noon")
	eq(sim.storyteller.tension, 40.0, "no change of tension, not even for a breach")
	# across a dawn
	sim.minutes = 6.45 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	var day: int = sim.day
	_run(sim, 4.0)
	eq(sim.day, day + 1, "the day turned")
	eq(sim.storyteller.report(), {}, "no assembly")
	eq(_events_of(sim, "dawn_report").size(), 0, "and no event for one")
	eq(_events_of(sim, "story_card").size(), 0, "no card event either")
	eq(sim.storyteller.tension, 40.0, "the quiet day did not move the tension")
	check(not sim.alerts.has("dawn") and not sim.alerts.has("story"), "no alerts")
	g.world.free()


func test_a_card_that_is_up_when_it_is_switched_off_is_not_forced_on_anyone() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = [_card("deal", "choice", 1.0, {
		"choices": [{"label": "Take it", "effects": [{"stock": {"ammo": 10}}]}, {"label": "Leave it", "effects": []}], "bot": 0})]
	_seed_with_a_card(sim, 5)
	_run(sim, 5.0)
	var ammo: float = sim.stock.ammo
	sim.storyteller.enabled = false
	_run(sim, 60.0)
	eq(float(sim.stock.ammo), ammo, "its default is not taken while it is off")
	g.world.free()


# -------------------------------------------------------------- tension --

func test_trouble_raises_the_tension_and_a_quiet_day_lowers_it() -> void:
	var g := _game(5, 9.0)
	var sim = g.sim
	sim.storyteller.cards = []
	sim.storyteller.tension = 50.0
	_run(sim, 2.0)
	eq(sim.storyteller.tension, 50.0, "a quiet morning changes nothing")
	sim._damage_segment(sim.segments[1], 1000.0)
	_run(sim, 1.0)
	eq(sim.storyteller.tension, 50.0 + Storyteller.T_BREACH, "a breach")
	_run(sim, 1.0)
	eq(sim.storyteller.tension, 50.0 + Storyteller.T_BREACH, "counted once")
	var ana = _person(sim, "Ana")
	sim.medical.kill(ana, "bled out")
	_run(sim, 1.0)
	eq(sim.storyteller.tension, 50.0 + Storyteller.T_BREACH + Storyteller.T_DEATH, "a death")
	var hector = _person(sim, "Hector")
	sim.medical.on_downed(hector, "bite")
	_run(sim, 1.0)
	eq(sim.storyteller.tension, 50.0 + Storyteller.T_BREACH + Storyteller.T_DEATH + Storyteller.T_DOWNED, "and someone downed")
	g.world.free()


func test_a_quiet_day_takes_eight_off() -> void:
	var g := _game(5, 6.4)
	var sim = g.sim
	sim.storyteller.cards = []
	sim.storyteller.tension = 50.0
	_run(sim, 4.0)
	eq(sim.day, 6, "dawn came")
	eq(sim.storyteller.tension, 42.0, "a day with no trouble: tension falls by eight")
	g.world.free()


func test_the_tension_stays_between_nothing_and_a_hundred() -> void:
	var g := _game(5, 6.4)
	var sim = g.sim
	sim.storyteller.cards = []
	sim.storyteller.tension = 3.0
	_run(sim, 4.0)
	eq(sim.storyteller.tension, 0.0, "it does not go under zero")
	g.world.free()


func test_a_day_with_trouble_does_not_count_as_quiet() -> void:
	var g := _game(5, 6.3)
	var sim = g.sim
	sim.storyteller.cards = []
	sim.storyteller.tension = 50.0
	_run(sim, 1.0)
	sim._damage_segment(sim.segments[1], 1000.0)
	_run(sim, 1.0)
	var raised: float = sim.storyteller.tension
	_run(sim, 4.0)
	eq(sim.day, 6, "dawn came")
	eq(sim.storyteller.tension, raised, "the breach spoiled the quiet: no fall")
	g.world.free()


func test_a_threat_card_adds_to_the_tension() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = [_card("bad", "threat", 1.0, {"effects": []})]
	_seed_with_a_card(sim, 5)
	sim.storyteller.tension = 50.0
	_run(sim, 5.0)
	eq(sim.storyteller.tension, 50.0 + Storyteller.T_THREAT, "a threat is trouble")
	g.world.free()


# ----------------------------------------------------------------- saves --

func test_the_storyteller_survives_a_save() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = [_card("deal", "choice", 1.0, {
		"choices": [{"label": "Take it", "effects": [{"stock": {"ammo": 10}}]}, {"label": "Leave it", "effects": []}], "bot": 1})]
	_seed_with_a_card(sim, 5)
	sim.storyteller.tension = 61.5
	_run(sim, 5.0)
	check(not sim.storyteller.pending().is_empty(), "a card is up when we save")
	var saved: Dictionary = sim.storyteller.save()
	var other := Helpers.make(8, 1)
	other.sim.storyteller.cards = sim.storyteller.cards.duplicate(true)
	other.sim.storyteller.load_state(saved)
	eq(other.sim.storyteller.save(), saved, "the same state comes back")
	eq(other.sim.storyteller.tension, 61.5, "the tension")
	eq(other.sim.storyteller.pending().id, "deal", "the card that was up")
	eq(other.sim.storyteller.radio_day, 5, "and the day's radio hour")
	g.world.free()
	other.world.free()


func test_a_whole_save_file_keeps_the_card_and_the_story_goes_on_the_same() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = [_card("deal", "choice", 1.0, {
		"choices": [{"label": "Take it", "effects": [{"stock": {"ammo": 10}}]}, {"label": "Leave it", "effects": [{"stock": {"scrap": 7}}]}], "bot": 1})]
	_seed_with_a_card(sim, 5)
	_run(sim, 6.0)
	var text := SaveGame.to_text(SaveGame.to_dict(sim))
	var other := Helpers.make(99, 1)
	other.sim.storyteller.enabled = true
	other.sim.storyteller.cards = sim.storyteller.cards.duplicate(true)
	check(SaveGame.apply(other.sim, SaveGame.from_text(text)), "the save loads")
	eq(other.sim.storyteller.pending().get("id", ""), "deal", "the card is still up")
	eq(other.sim.storyteller.save(), sim.storyteller.save(), "with the same state")
	_run(sim, 40.0)
	_run(other.sim, 40.0)
	eq(other.sim.storyteller.pending(), sim.storyteller.pending(), "both settle it the same way after two hours")
	eq(float(other.sim.stock.scrap), float(sim.stock.scrap), "and the stores agree")
	g.world.free()
	other.world.free()


func test_an_old_save_loads_with_defaults() -> void:
	var g := _game(5, 9.0)
	var sim = g.sim
	sim.storyteller.tension = 77.0
	sim.storyteller.load_state({})
	check(sim.storyteller.pending().is_empty(), "no card")
	eq(sim.storyteller.tension, Storyteller.TENSION_START, "the tension starts where a new run does")
	eq(sim.storyteller.history, {}, "no history")
	eq(sim.storyteller.report(), {}, "no assembly yet")
	eq(sim.storyteller.budget_mult(5), 1.0, "no multiplier")
	eq(sim.storyteller.reach_mult(), 1.0, "no fog")
	eq(sim.storyteller.look().get("blackout", false), false, "no blackout")
	_run(sim, 3.0)
	g.world.free()
	# and a module state with only some keys
	var h := _game(5, 9.0)
	h.sim.storyteller.load_state({"tension": 12.0})
	eq(h.sim.storyteller.tension, 12.0, "a save with only the tension keeps it")
	check(h.sim.storyteller.pending().is_empty(), "and has no card")
	h.world.free()


func test_a_whole_save_from_before_this_round_loads_with_the_storyteller_at_its_defaults() -> void:
	var g := _game(5, 9.0)
	var sim = g.sim
	sim.storyteller.tension = 80.0
	var data := SaveGame.to_dict(sim)
	data.modules.erase("storyteller")   # a save from before the storyteller knows nothing of it
	var other := Helpers.make(3, 1)
	other.sim.storyteller.enabled = true
	other.sim.storyteller.tension = 77.0
	other.sim.storyteller.history = {"fog": 3}
	check(SaveGame.apply(other.sim, SaveGame.from_text(SaveGame.to_text(data))), "the old save loads")
	eq(other.sim.storyteller.tension, Storyteller.TENSION_START, "the tension is where a new run starts")
	eq(other.sim.storyteller.history, {}, "with no history")
	check(other.sim.storyteller.enabled, "and the storyteller is on, as in any game")
	check(other.sim.storyteller.pending().is_empty(), "no card is waiting")
	_run(other.sim, 3.0)
	g.world.free()
	other.world.free()


func test_the_tutorials_storyteller_stays_off_through_a_save() -> void:
	var g := _game(5, 9.0)
	var sim = g.sim
	sim.storyteller.enabled = false
	var data := SaveGame.to_dict(sim)
	eq(data.modules.storyteller.enabled, false, "the save says it was off")
	var other := Helpers.make(3, 1)
	other.sim.storyteller.enabled = true
	check(SaveGame.apply(other.sim, SaveGame.from_text(SaveGame.to_text(data))), "it loads")
	eq(other.sim.storyteller.enabled, false, "and it is off again")
	# and an old save, which says nothing of it, leaves the game's own choice alone
	data.modules.erase("storyteller")
	var third := Helpers.make(4, 1)
	third.sim.storyteller.enabled = false
	SaveGame.apply(third.sim, SaveGame.from_text(SaveGame.to_text(data)))
	eq(third.sim.storyteller.enabled, false, "an old save does not switch it on")
	g.world.free()
	other.world.free()
	third.world.free()


# ------------------------------------------------------- the dawn assembly --

## Skills that only say what they are told they have gained.
class FakeSkills:
	extends "res://scripts/sim/skills.gd"
	var told := {}

	func gained(p) -> Dictionary:
		return told.get(p.id, {}).duplicate()


## Morale that only says what it is told.
class FakeMorale:
	extends "res://scripts/sim/morale.gd"
	var words := {}

	func mood(p) -> String:
		return String(words.get(p.id, "Steady"))


## The evening of a day, a little before dusk, with the nights off.
func _evening(day: int = 5, prepare: Callable = Callable()) -> Dictionary:
	var g := _game(day, 18.9)
	var sim = g.sim
	sim.storyteller.cards = []
	sim.skills = FakeSkills.new()
	sim.skills.setup(sim)
	sim.morale = FakeMorale.new()
	sim.morale.setup(sim)
	if prepare.is_valid():
		prepare.call(sim)
	_run(sim, 1.0)
	_run(sim, 2.0)
	return g


## Jumps to the last minutes of the night and lets the day turn.
func _to_dawn(sim) -> void:
	sim.minutes = 6.4 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	_run(sim, 4.0)


func test_the_assembly_comes_at_dawn_with_an_event_and_an_alert() -> void:
	var g := _evening()
	var sim = g.sim
	eq(sim.storyteller.report(), {}, "nothing before the first dawn")
	sim.events.clear()
	_to_dawn(sim)
	eq(sim.day, 6, "the day turned")
	var r: Dictionary = sim.storyteller.report()
	check(not r.is_empty(), "there is an assembly")
	eq(r.night, 5, "of night five")
	eq(r.day, 6, "on day six")
	eq(_events_of(sim, "dawn_report").size(), 1, "one event")
	check(sim.alerts.has("dawn"), "and an alert to read it again from")
	check(String(sim.alerts.dawn.text).contains("night 5"), "which names the night: '%s'" % sim.alerts.dawn.text)
	g.world.free()


func test_the_numbers_of_the_night_match_the_counters() -> void:
	# a wall piece that is worn before dusk, so that it can be mended in the night
	var g := _evening(5, func(sim):
		Helpers.no_work(sim)    # nobody mends it before the night: only what the test mends counts
		sim.segments[3].hp = sim.segments[3].max_hp - 100.0
		sim._segment_state(sim.segments[3]))
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var walt = _person(sim, "Walt")
	var seg_a = sim.segments[0]
	var seg_b = sim.segments[3]
	var kills_at_dusk: int = sim.kills
	# the night: 7 put down, Walt the most; a wall piece takes 120, another is mended by 35
	sim.kills += 7
	dez.stats.kills_night = 3
	walt.stats.kills_night = 4
	sim._damage_segment(seg_a, 120.0)
	_run(sim, 1.0)
	sim._repair_segment(seg_b, 35.0)
	_run(sim, 1.0)
	_to_dawn(sim)
	var r: Dictionary = sim.storyteller.report()
	eq(r.kills, sim.kills - kills_at_dusk, "what was put down is what the count says")
	eq(r.kills, 7, "seven")
	eq(r.mvp, {"who": "Walt", "kills": 4}, "Walt did the most")
	eq(r.wall_lost, 120, "the wall lost 120")
	eq(r.wall_mended, 35, "and was mended by 35")
	eq(r.breaches, 0, "no breach")
	g.world.free()


func test_a_quiet_night_has_no_mvp_and_no_losses() -> void:
	var g := _evening()
	var sim = g.sim
	_to_dawn(sim)
	var r: Dictionary = sim.storyteller.report()
	eq(r.kills, 0, "nobody put down")
	eq(r.mvp, {}, "so nobody led")
	eq(r.lost, [], "no one lost")
	eq(r.wall_lost, 0, "the wall is as it was")
	eq(r.skill_ups, [], "nothing learned")
	check(String(sim.alerts.dawn.sub).contains("quiet"), "the alert says it was quiet: '%s'" % sim.alerts.dawn.sub)
	g.world.free()


func test_the_lost_are_named_with_a_line_about_them() -> void:
	var g := _evening()
	var sim = g.sim
	var ana = _person(sim, "Ana")
	sim.medical.kill(ana, "bled out")
	_run(sim, 1.0)
	var marcus = _person(sim, "Marcus")
	marcus.dead = true
	marcus.turned = true
	_run(sim, 1.0)
	_to_dawn(sim)
	var r: Dictionary = sim.storyteller.report()
	eq(r.lost.size(), 2, "two were lost")
	eq(r.lost[0].who, "Ana", "Ana first")
	eq(r.lost[1].who, "Marcus", "then Marcus")
	eq(r.lost[1].how, "turned", "who turned")
	for l in r.lost:
		check(String(l.epitaph).length() > 8, "%s has a line said of them: '%s'" % [l.who, l.epitaph])
	check(String(sim.alerts.dawn.sub).contains("Ana") and String(sim.alerts.dawn.sub).contains("Marcus"), "the alert names them: '%s'" % sim.alerts.dawn.sub)
	# the next dawn does not tell it again
	sim.minutes = 18.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	_run(sim, 3.0)
	_to_dawn(sim)
	eq(sim.storyteller.report().lost, [], "a day later nobody is newly lost")
	g.world.free()


func test_skills_gained_since_the_last_assembly_are_listed_once() -> void:
	var g := _evening()
	var sim = g.sim
	var hector = _person(sim, "Hector")
	sim.skills.told = {"hector": {"Melee": 1}}
	_to_dawn(sim)
	var r: Dictionary = sim.storyteller.report()
	eq(r.skill_ups.size(), 1, "one gain")
	eq(r.skill_ups[0].who, "Hector", "Hector's")
	eq(r.skill_ups[0].skill, "Melee", "in Melee")
	eq(r.skill_ups[0].value, int(hector.skills.Melee) if hector.get("skills") != null and hector.skills.has("Melee") else int(hector.def.skills.Melee), "to the level he is at now")
	sim.minutes = 18.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	_run(sim, 3.0)
	_to_dawn(sim)
	eq(sim.storyteller.report().skill_ups, [], "the next one does not repeat it")
	sim.skills.told = {"hector": {"Melee": 2}}
	sim.minutes = 18.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	_run(sim, 3.0)
	_to_dawn(sim)
	eq(sim.storyteller.report().skill_ups.size(), 1, "but a new point is")
	g.world.free()


func test_the_crews_mood_is_told_in_a_few_words() -> void:
	var g := _evening()
	var sim = g.sim
	_to_dawn(sim)
	eq(sim.storyteller.report().mood, "Everyone is steady.", "all steady")
	sim.morale.words = {"marcus": "Shaken"}
	sim.minutes = 18.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	_run(sim, 3.0)
	_to_dawn(sim)
	eq(sim.storyteller.report().mood, "Mostly steady; Marcus is shaken.", "one shaken")
	sim.morale.words = {"marcus": "Breaking", "ana": "Breaking", "walt": "Inspired"}
	sim.minutes = 18.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	_run(sim, 3.0)
	_to_dawn(sim)
	var mood: String = sim.storyteller.report().mood
	check(mood.begins_with("Mostly steady;") and mood.contains("Ana and Marcus are breaking") and mood.contains("Walt is inspired"), "a mixed crew: '%s'" % mood)
	g.world.free()


func test_the_days_cards_are_in_the_assembly() -> void:
	var g := _game(5, 11.9)
	var sim = g.sim
	sim.storyteller.cards = [_card("rain", "boon", 1.0, {"title": "Heavy rain", "effects": [{"stock": {"water": 20}}], "result": "The barrels are full."})]
	_seed_with_a_card(sim, 5)
	_run(sim, 5.0)
	sim.storyteller.choose(0)
	sim.minutes = 18.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	_run(sim, 3.0)
	_to_dawn(sim)
	var r: Dictionary = sim.storyteller.report()
	eq(r.events, ["Heavy rain: The barrels are full."], "what the radio brought, in a line")
	sim.minutes = 18.9 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	_run(sim, 3.0)
	_to_dawn(sim)
	eq(sim.storyteller.report().events, [], "and not again the day after")
	g.world.free()


func test_a_breach_in_the_night_is_counted_and_makes_it_a_bad_one() -> void:
	var g := _evening()
	var sim = g.sim
	sim.storyteller.tension = 40.0
	sim._damage_segment(sim.segments[1], 1000.0)
	_run(sim, 1.0)
	var t: float = sim.storyteller.tension
	check(t >= 40.0 + Storyteller.T_BREACH - 0.001, "the breach raised the tension to %.1f" % t)
	_to_dawn(sim)
	var r: Dictionary = sim.storyteller.report()
	eq(r.breaches, 1, "one breach")
	check(r.wall_lost >= 120, "and the wall lost what it lost: %d" % r.wall_lost)
	g.world.free()


func test_a_night_that_costs_a_fifth_of_the_wall_is_a_bad_one() -> void:
	var g := _evening()
	var sim = g.sim
	sim.storyteller.tension = 40.0
	var total := 0.0
	for s in sim.segments:
		total += s.max_hp
	# wear it all down by a quarter, nowhere near a breach
	for s in sim.segments:
		sim._damage_segment(s, s.max_hp * 0.25)
	_run(sim, 1.0)
	eq(sim.storyteller.tension, 40.0, "the wear itself is not trouble")
	_to_dawn(sim)
	eq(sim.storyteller.tension, 40.0 + Storyteller.T_BAD_NIGHT, "but a night that takes a quarter of the wall is")
	near(float(sim.storyteller.report().wall_lost), total * 0.25, 1.0, "and the assembly says how much")
	g.world.free()


func test_the_assembly_survives_a_save() -> void:
	var g := _evening()
	var sim = g.sim
	sim.kills += 5
	_run(sim, 1.0)
	_to_dawn(sim)
	var report: Dictionary = sim.storyteller.report()
	check(not report.is_empty(), "there is an assembly to keep")
	var other := _game(6, 9.0, 3)
	other.sim.storyteller.load_state(SaveGame.from_text(SaveGame.to_text({"story": sim.storyteller.save()})).story)
	eq(other.sim.storyteller.report(), report, "the same assembly after a load")
	eq(other.sim.storyteller.save(), sim.storyteller.save(), "and the same state")
	g.world.free()
	other.world.free()


func test_a_real_night_is_counted_the_way_it_was_fought() -> void:
	var g := Helpers.make(17, 1)
	var sim = g.sim
	sim.storyteller.enabled = true
	sim.storyteller.cards = []
	Helpers.run_to_hour(sim, 18.5)
	var kills_at_dusk := 0
	var dusk_seen := false
	var hz := 15.0
	var guard := 0
	while sim.day < 2 and guard < 200000:
		sim.update(1.0 / hz)
		guard += 1
		if not dusk_seen and sim.phase == "dusk":
			dusk_seen = true
			kills_at_dusk = sim.kills
	eq(sim.day, 2, "the night passed")
	var r: Dictionary = sim.storyteller.report()
	check(not r.is_empty(), "there is an assembly")
	eq(r.kills, sim.kills - kills_at_dusk, "its kills are the night's kills")
	check(r.kills > 5, "and there were some: %d" % r.kills)
	var per_person := 0
	var most := 0
	var best := ""
	for p in sim.people:
		var n := int(p.stats.get("kills_night", 0))
		per_person += n
		if n > most:
			most = n
			best = p.first
	check(per_person > 0, "the people's own counters counted the night: %d" % per_person)
	eq(per_person, r.kills, "and they add up to the night's kills")
	eq(r.mvp.get("who", ""), best, "the most by the one the counters say")
	eq(r.mvp.get("kills", 0), most, "with their number")
	g.world.free()


# ------------------------------------------------------------------------ fuzz --

## What must always be so of a game with the storyteller in it.
func _sound(sim) -> String:
	for k in sim.stock:
		var v := float(sim.stock[k])
		if not is_finite(v) or v < -0.001:
			return "the %s stock is %s" % [k, str(v)]
	var st = sim.storyteller
	if not is_finite(st.tension) or st.tension < 0.0 or st.tension > 100.0:
		return "the tension is %s" % str(st.tension)
	if not sim.weather in ["clear", "rain", "fog"]:
		return "the weather is '%s'" % sim.weather
	if not String(st.blackout.get("state", "")) in ["", "pending", "dark"]:
		return "the blackout is '%s'" % str(st.blackout)
	for id in st.sick:
		var known := false
		for p in sim.people:
			known = known or p.id == id
		if not known or not is_finite(float(st.sick[id])):
			return "a fever for '%s'" % id
	for e in st.schedule:
		if not is_finite(float(e.at)):
			return "a scheduled thing at %s" % str(e.at)
	var up: Dictionary = st.pending()
	if not up.is_empty():
		if up.choices.is_empty() or int(up.bot) < 0 or int(up.bot) >= up.choices.size():
			return "a pending card with a bad default: %s" % str(up)
		if String(up.title).contains("{") or String(up.text).contains("{"):
			return "braces left in a card: %s" % str(up.title)
	if st.mult_ok() == false:
		return "the night's multiplier is %s" % str(st.night_mult)
	for p in sim.people:
		if not is_finite(p.x) or not is_finite(p.y) or not is_finite(p.hp):
			return "%s is nowhere (%s, %s, %s)" % [p.first, str(p.x), str(p.y), str(p.hp)]
	for z in sim.zombies:
		if not is_finite(z.x) or not is_finite(z.y):
			return "a walker is nowhere"
	return ""


func test_days_of_cards_with_random_orders_saves_and_loads_never_break_the_rules() -> void:
	for seed_value in [61, 62]:
		var g := Helpers.make(seed_value, 1)
		var sim = g.sim
		sim.storyteller.enabled = true
		var rnd := RandomNumberGenerator.new()
		rnd.seed = 7000 + seed_value
		var deck: Array = []
		for c in sim.storyteller.cards:
			if c.id != "survivor_call" and c.id != "place_call":    # (only recruits.gd puts the first up; the other is the settlement game's)
				deck.append(c.id)
		var bad := ""
		var answered := 0
		var forced := 0
		var loads := 0
		var seen := {}
		var states := {}
		var hz := 10.0
		var second := 0
		var last_save := 0
		var guard := 0
		while sim.day < 6 and sim.over == "" and bad == "" and guard < 200000:
			guard += 1
			sim.update(1.0 / hz)
			if guard % int(hz) != 0:
				continue
			second += 1
			# a card is forced now and then, at any hour
			if second % 90 == 45 and sim.storyteller.pending().is_empty():
				if sim.storyteller.force(deck[rnd.randi() % deck.size()]):
					forced += 1
			var up: Dictionary = sim.storyteller.pending()
			if not up.is_empty():
				seen[up.id] = true
				# the player answers, or tries to answer something that is not there, or waits
				var roll := rnd.randf()
				if roll < 0.35:
					if sim.storyteller.choose(rnd.randi_range(-1, 3)):
						answered += 1
				elif roll < 0.4:
					sim.storyteller.choose(0)
			# random orders
			var p = sim.people[rnd.randi() % sim.people.size()]
			var what := rnd.randi() % 8
			if what == 0:
				sim.toggle_draft(p)
			elif what == 1:
				sim.order_move(p, rnd.randf_range(22.0, 62.0), rnd.randf_range(20.0, 43.0))
			elif what == 2:
				sim.order_post(p)
			elif what == 3:
				sim.medical.gizmo("treat", {"kind": "person", "ref": p})
			elif what == 4 and sim.phase == "day":
				sim.order_repair(p, sim.segments[rnd.randi() % sim.segments.size()])
			# a save and a load, carrying on with the loaded game
			if second - last_save >= 70:
				last_save = second
				var before: Dictionary = sim.storyteller.save()
				var text := SaveGame.to_text(SaveGame.to_dict(sim))
				var other := Helpers.make(seed_value + 100, 1)
				if not SaveGame.apply(other.sim, SaveGame.from_text(text)):
					bad = "a save did not load"
					other.world.free()
					break
				if other.sim.storyteller.save() != before:
					bad = "the storyteller's state changed through a save at day %d %.1f" % [sim.day, sim.hour]
					other.world.free()
					break
				g.world.free()
				g = other
				sim = other.sim
				loads += 1
			states[sim.storyteller.blackout_state()] = true
			states[sim.weather] = true
			bad = _sound(sim)
		check(bad == "", "seed %d: %s (day %d, %.1f)" % [seed_value, bad, sim.day, sim.hour])
		check(sim.day >= 5 or sim.over != "", "seed %d: the days passed (day %d)" % [seed_value, sim.day])
		check(states.has("dark") and states.has("fog") and states.has("rain"), "seed %d: a blackout, a fog and a rain all came: %s" % [seed_value, str(states.keys())])
		check(forced >= 3 and answered >= 2 and loads >= 3, "seed %d: cards were forced (%d), answered (%d) and saved through (%d loads)" % [seed_value, forced, answered, loads])
		check(seen.size() >= 3, "seed %d: several cards were seen: %s" % [seed_value, str(seen.keys())])
		g.world.free()
