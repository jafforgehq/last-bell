extends "res://tests/case.gd"
## Stay home on purpose, or drive back in time (round 19, slice 3, S3.4: `Scavenge.night_warning`, `NightCalls.road_status`, the
## `night_road` news and call in scripts/sim/night_calls.gd). A trip that is out when the dusk comes with a Big Night is the player's
## choice to make: the Map page says when a trip would have to leave the place, the place's line says how long is left, the radio
## warns at "soon", asks at "now", and a party that cannot be home before the dusk is out until morning (the rule of
## `Scavenge._is_due`, pinned here) while the base holds the night alone. Numbers are read through NightData and the town, never
## copied; the waves' `big_night` is a fake (a Big Night made by hand: tests/test_night_calls.gd).

const Helpers := preload("res://tests/helpers.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const NightCalls := preload("res://scripts/sim/night_calls.gd")
const Calls := preload("res://tests/test_night_calls.gd")

const DAY := 10    # the day of tonight's Big Night


# ----------------------------------------------------------------- helpers --

## A game with an avatar at 08:00 of the Big Night's day (the dead are away, the guns dry), the waves saying that tonight is a Siege
## when `big` (they say nothing special otherwise).
func _game(big: bool = true, hour: float = 8.0) -> Dictionary:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.stock.ammo = 0.0
	var w := Calls.FakeWaves.new()
	w.setup(sim)
	w.start()
	w.enabled = false
	if big:
		w.bigs[DAY] = Calls.big_siege()
		w.outlooks[DAY] = Calls.siege(DAY)
	sim.waves = w
	Helpers.at(sim, DAY, hour)
	sim.events.clear()
	return g


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## Ruth and Dez set out for the houses (an hour on foot, a little more) at the hour of the game, by `vehicle` ("" on foot).
func _trip(sim, vehicle: String = "", place: String = "houses") -> Dictionary:
	var party: Dictionary = sim.scavenge.begin_played([_p(sim, "ruth"), _p(sim, "dez")], place, "loot", vehicle)
	check(not party.is_empty(), "the trip begins (%s)" % sim.scavenge.why_not_played([_p(sim, "ruth"), _p(sim, "dez")], place, "loot", vehicle))
	return party


## The clock set to `left` minutes before the hour the party must leave the place by (negative: after it).
func _left(sim, left: float) -> void:
	var st: Dictionary = sim.radio.night.road_status()
	var clock: float = float(st.leave_by) - left
	Helpers.at(sim, DAY, NightCalls.hour_of(clock))


func _news(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if e.kind == kind:
			out.append(e)
	return out


func _ids(c: Dictionary) -> Array:
	var out: Array = []
	for o in c.options:
		out.append(String(o.id))
	return out


# ------------------------------------------------------------- night_warning --

func test_a_big_night_says_by_when_the_party_must_leave_the_place() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var road: float = sim.scavenge.road_minutes("houses", "")
	var margin: float = NightData.num("forecast.road_margin_min")
	var w: Dictionary = sim.scavenge.night_warning("houses", "", 1.0)
	check(bool(w.big), "tonight is a Big Night")
	near(float(w.dusk), sim.seasons.dusk_hour(), 1e-9, "the dusk")
	near(float(w.leave_by), sim.seasons.dusk_hour() - (road + margin) / 60.0, 1e-6, "it must leave by the dusk less the road and the margin")
	near(float(w.home_by), 8.0 + 2.0 * road / 60.0 + 1.0, 1e-6, "home after the road there, the hour in the place and the road back")
	check(bool(w.makes_it), "an hour there and back by noon makes it")
	var text := String(w.text)
	check(text.begins_with("Big Night tonight: leave the place by %s" % NightCalls.clock_text(float(w.leave_by))), "the text says when: %s" % text)
	check(text.contains("the road home takes %s" % NightCalls.duration_text(road)), "and how long the road is: %s" % text)
	check(text.contains("stay out and the base holds alone"), "and that staying out is allowed: %s" % text)
	g.world.free()


func test_a_trip_that_cannot_be_home_in_time_says_so() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var w: Dictionary = sim.scavenge.night_warning("houses", "", 12.0)
	check(not bool(w.makes_it), "twelve hours at the houses is not home before the dusk")
	check(String(w.text).contains("cannot be home in time") and String(w.text).contains("stay out"), "it says so: %s" % String(w.text))
	g.world.free()
	var h := _game(false, 8.0)
	var s2 = h.sim
	var w2: Dictionary = s2.scavenge.night_warning("houses", "", 12.0)
	check(not bool(w2.big), "an ordinary night")
	check(not bool(w2.makes_it), "that trip is still too long")
	check(String(w2.text).contains("out until morning"), "the text says what it costs: %s" % String(w2.text))
	var w3: Dictionary = s2.scavenge.night_warning("houses", "", 1.0)
	eq(String(w3.text), "", "an ordinary night and a trip that is home in time: nothing to say")
	h.world.free()


func test_the_warning_counts_the_vehicles_road() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	var on_foot: Dictionary = sim.scavenge.night_warning("houses", "", 1.0)
	var by_car: Dictionary = sim.scavenge.night_warning("houses", String(v.id), 1.0)
	var road: float = sim.scavenge.road_minutes("houses", String(v.id))
	check(road < sim.scavenge.road_minutes("houses", ""), "the car is quicker (%.1f minutes)" % road)
	check(float(by_car.leave_by) > float(on_foot.leave_by), "so it may leave the place later")
	near(float(by_car.leave_by), sim.seasons.dusk_hour() - (road + NightData.num("forecast.road_margin_min")) / 60.0, 1e-6, "by the car's road")
	check(String(by_car.text).contains(NightCalls.duration_text(road)), "and says it: %s" % String(by_car.text))
	g.world.free()


func test_the_warning_is_pure_and_silent_without_an_avatar() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var clock: float = sim.clock_min
	var trips: int = sim.scavenge.trips
	sim.scavenge.night_warning("houses", "", 1.0)
	near(sim.clock_min, clock, 1e-9, "it changes no time")
	eq(sim.scavenge.trips, trips, "and makes no trip")
	eq(sim.scavenge.parties.size(), 0, "nor a party")
	g.world.free()
	var h := Helpers.make(1, 1, 5)
	var s2 = h.sim
	eq(s2.player_id, "", "no avatar")
	var w: Dictionary = s2.scavenge.night_warning("houses", "", 1.0)
	check(not bool(w.big), "no Big Night without an avatar")
	eq(String(w.text), "", "and nothing to say")
	h.world.free()


# --------------------------------------------------------------- road_status --

func test_there_is_no_road_without_a_trip() -> void:
	var g := _game()
	var st: Dictionary = g.sim.radio.night.road_status()
	check(not bool(st.on), "nobody is out")
	g.world.free()


func test_a_party_in_its_place_has_its_hour_to_leave_by_and_its_four_states() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	_trip(sim)
	var road: float = sim.scavenge.road_minutes("houses", "")
	var margin: float = NightData.num("forecast.road_margin_min")
	var warn: float = NightData.num("forecast.road_warn_min")
	var st: Dictionary = sim.radio.night.road_status()
	check(bool(st.on), "a trip is out")
	near(float(st.road_min), road, 1e-6, "the road home")
	near(float(st.dusk) - float(st.leave_by), road + margin, 1e-6, "it must leave by the dusk less the road and the margin")
	check(bool(st.big), "tonight is a Big Night")
	eq(st.state, "free", "plenty of time at eight")
	_left(sim, warn + 5.0)
	eq(sim.radio.night.road_status().state, "free", "more than the warning's time left: free")
	_left(sim, warn - 1.0)
	eq(sim.radio.night.road_status().state, "soon", "within the warning's time: soon")
	_left(sim, 1.0)
	eq(sim.radio.night.road_status().state, "soon", "a minute to go: still soon")
	_left(sim, 0.0)
	eq(sim.radio.night.road_status().state, "now", "no time left: now")
	near(float(sim.radio.night.road_status().left_min), 0.0, 0.01, "(and the minutes say it)")
	_left(sim, -margin + 1.0)
	eq(sim.radio.night.road_status().state, "now", "using the margin: still now")
	_left(sim, -margin - 1.0)
	eq(sim.radio.night.road_status().state, "late", "past the margin they cannot be home before the dusk: late")
	check(float(sim.radio.night.road_status().left_min) < -margin, "(a negative number of minutes)")
	g.world.free()


func test_the_text_of_the_status_says_dusk_and_the_hour_to_leave_by() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	_trip(sim)
	_left(sim, 50.0)
	var st: Dictionary = sim.radio.night.road_status()
	var by := NightCalls.clock_text(NightCalls.hour_of(float(st.leave_by)))
	check(String(st.text).contains("a Big Night with it") and String(st.text).contains("leave by %s" % by), "soon: %s" % String(st.text))
	check(String(st.text).begins_with("Dusk in %s" % NightCalls.duration_text(float(st.dusk) - sim.clock_min)), "and how long until the dusk: %s" % String(st.text))
	_left(sim, -60.0)
	check(String(sim.radio.night.road_status().text).begins_with("You will be out tonight"), "late: %s" % String(sim.radio.night.road_status().text))
	g.world.free()
	var h := _game(false, 8.0)
	_trip(h.sim)
	_left(h.sim, 50.0)
	var plain: Dictionary = h.sim.radio.night.road_status()
	check(not bool(plain.big), "an ordinary night is not big")
	check(not String(plain.text).contains("Big Night") and String(plain.text).contains("leave by"), "and its line does not say Big Night: %s" % String(plain.text))
	h.world.free()


func test_a_party_by_vehicle_has_the_vehicles_road() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	_trip(sim, String(v.id))
	var st: Dictionary = sim.radio.night.road_status()
	near(float(st.road_min), sim.scavenge.road_minutes("houses", String(v.id)), 1e-6, "the car's road, not the walk")
	check(float(st.road_min) < sim.scavenge.road_minutes("houses", ""), "which is shorter")
	g.world.free()


func test_a_party_on_the_road_home_is_free_when_it_gets_in_before_the_dusk_and_late_when_it_does_not() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var party := _trip(sim)
	Helpers.at(sim, DAY, 15.0)
	sim.scavenge.finish_played(party, {"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0})
	eq(String(party.state), "away", "on the road home")
	var st: Dictionary = sim.radio.night.road_status()
	check(bool(st.on), "still the trip's road")
	eq(st.state, "free", "back at about four: before the dusk")
	check(String(st.text).begins_with("On the road home: back by %s" % NightCalls.clock_text(NightCalls.hour_of(float(party.return_at)))), "and says when: %s" % String(st.text))
	g.world.free()
	var h := _game(true, 8.0)
	var s2 = h.sim
	var p2 := _trip(s2)
	Helpers.at(s2, DAY, 18.5)
	s2.scavenge.finish_played(p2, {"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0})
	eq(s2.radio.night.road_status().state, "late", "a road that begins at half past six cannot end before the dusk")
	h.world.free()


# --------------------------------------------------- the news, the call, the line --

func test_soon_is_a_line_in_the_news_once_and_only_for_a_big_night() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	_trip(sim)
	_left(sim, NightData.num("forecast.road_warn_min") - 1.0)
	Helpers.run(sim, 0.1)
	var lines := _news(sim, "night_road")
	eq(lines.size(), 1, "the radio says the dusk is coming")
	check(String(lines[0].text).contains("a Big Night with it") and String(lines[0].text).contains("leave by"), "with the hour: %s" % str(lines[0].text))
	check(lines[0].options.is_empty(), "it is news, not a call")
	Helpers.run(sim, 1.0)
	eq(_news(sim, "night_road").size(), 1, "once")
	g.world.free()
	var h := _game(false, 8.0)
	_trip(h.sim)
	_left(h.sim, NightData.num("forecast.road_warn_min") - 1.0)
	Helpers.run(h.sim, 0.1)
	eq(_news(h.sim, "night_road").size(), 0, "an ordinary night: the community holds it, no warning")
	h.world.free()


func test_now_is_a_call_to_head_home_or_stay_with_stay_by_default() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	_trip(sim)
	_left(sim, 0.0)
	Helpers.run(sim, 0.1)
	var calls := _news(sim, "night_road")
	var asks: Array = []
	for e in calls:
		if not e.options.is_empty():
			asks.append(e)
	eq(asks.size(), 1, "one call at the hour to leave")
	var c: Dictionary = asks[0]
	eq(_ids(c), ["home", "stay"], "head home now, or stay out")
	eq(c.default, "stay", "the default is to stay")
	near(float(c.due) - float(c.t), NightData.num("forecast.road_margin_min"), 0.001, "it waits until it is too late")
	check(String(c.options[1].label).contains("base holds alone"), "staying says what it means: %s" % str(c.options[1]))
	Helpers.run(sim, 1.0)
	var again := 0
	for e in _news(sim, "night_road"):
		if not e.options.is_empty():
			again += 1
	eq(again, 1, "only once")
	g.world.free()


func test_heading_home_asks_the_place_to_leave_and_staying_does_not() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	_trip(sim)
	_left(sim, 0.0)
	Helpers.run(sim, 0.1)
	var c: Dictionary = {}
	for e in _news(sim, "night_road"):
		if not e.options.is_empty():
			c = e
	check(not sim.radio.night.leave_requested, "nothing is asked yet")
	check(sim.radio.answer(int(c.id), "home"), "the player says home")
	check(sim.radio.night.leave_requested, "the place's scene is asked to leave")
	eq(c.result, "Heading home", "and the line says so")
	sim.radio.night.leave_requested = false
	g.world.free()
	var h := _game(true, 8.0)
	var s2 = h.sim
	_trip(s2)
	_left(s2, 0.0)
	Helpers.run(s2, 0.1)
	var d: Dictionary = {}
	for e in _news(s2, "night_road"):
		if not e.options.is_empty():
			d = e
	check(s2.radio.answer(int(d.id), "stay"), "the player stays")
	check(not s2.radio.night.leave_requested, "and nobody is asked to leave")
	h.world.free()


func test_the_request_to_leave_does_not_outlive_the_place() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var party := _trip(sim)
	sim.radio.night.leave_requested = true
	Helpers.run(sim, 0.1)
	check(sim.radio.night.leave_requested, "while the place is being played it stands")
	sim.scavenge.finish_played(party, {"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0})
	Helpers.run(sim, 0.1)
	check(not sim.radio.night.leave_requested, "the party is on the road: nothing is asked of the place any more")
	g.world.free()


func test_an_unanswered_call_to_head_home_stays_out() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	_trip(sim)
	_left(sim, 0.0)
	Helpers.run(sim, 0.1)
	var c: Dictionary = {}
	for e in _news(sim, "night_road"):
		if not e.options.is_empty():
			c = e
	Helpers.run(sim, NightData.num("forecast.road_margin_min") / sim.min_per_sec + 1.0)
	eq(c.answered, "stay", "left alone it takes its default")
	check(c.by_default, "by default")
	check(not sim.radio.night.leave_requested, "and nobody leaves")
	g.world.free()


func test_the_radio_notes_that_he_stayed_out_when_the_bell_has_rung() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	_trip(sim)
	Helpers.at(sim, DAY, sim.seasons.dusk_hour() + 0.2)
	Helpers.run(sim, 0.2)
	var found: Array = []
	for e in _news(sim, "night_road"):
		if String(e.text) == "You stayed out":
			found.append(e)
	eq(found.size(), 1, "the radio says so")
	check(String(found[0].sub).contains("base holds the night alone"), "and what it means: %s" % str(found[0].sub))
	Helpers.run(sim, 2.0)
	var again := 0
	for e in _news(sim, "night_road"):
		if String(e.text) == "You stayed out":
			again += 1
	eq(again, 1, "once")
	g.world.free()
	var h := _game(false, 8.0)
	_trip(h.sim)
	Helpers.at(h.sim, DAY, h.sim.seasons.dusk_hour() + 0.2)
	Helpers.run(h.sim, 0.2)
	eq(_news(h.sim, "night_road").size(), 0, "an ordinary night: no word of it")
	h.world.free()


func test_a_party_that_got_in_before_the_dusk_did_not_stay_out() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var party := _trip(sim)
	Helpers.at(sim, DAY, 15.0)
	sim.scavenge.finish_played(party, {"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0})
	Helpers.at(sim, DAY, sim.seasons.dusk_hour() + 0.2)    # (it is unloading at the bell: nothing to say)
	Helpers.run(sim, 0.2)
	var told := 0
	for e in _news(sim, "night_road"):
		if String(e.text) == "You stayed out":
			told += 1
	eq(told, 0, "somebody who was due in before the dusk has not stayed out")
	g.world.free()


func test_no_road_news_without_an_avatar() -> void:
	var g := Helpers.make(17, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, DAY, 8.0)
	var dez = _p(sim, "dez")
	var party: Dictionary = sim.scavenge.begin_played([dez, _p(sim, "marcus")], "houses", "loot", "")
	check(not party.is_empty(), "a trip is begun (no avatar: nobody leads it)")
	Helpers.at(sim, DAY, 17.0)
	Helpers.run(sim, 0.5)
	Helpers.at(sim, DAY, 19.5)
	Helpers.run(sim, 0.5)
	check(sim.radio.news.is_empty(), "the radio says nothing")
	check(not bool(sim.radio.night.road_status().on), "and there is no road to speak of")
	g.world.free()


# ------------------------------------------------- the rule the warning explains --

func test_a_trip_that_reaches_the_gate_after_the_dusk_is_out_until_morning() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var party := _trip(sim)
	Helpers.at(sim, DAY, 18.5)
	sim.scavenge.finish_played(party, {"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0})
	var dez = _p(sim, "dez")
	check(float(party.return_at) > sim.clock_min + 60.0, "the road home ends after the dusk")
	Helpers.run_to_hour(sim, 22.0)
	eq(String(sim.phase), "night", "it is night")
	eq(sim.scavenge.parties.size(), 1, "they have not come in: the dead are out")
	check(dez.away != null, "Dez is still out")
	Helpers.run_to_hour(sim, 8.0)
	var guard := 0
	while not sim.scavenge.parties.is_empty() and guard < 200:
		Helpers.run(sim, 1.0)
		guard += 1
	check(sim.scavenge.parties.is_empty(), "they come in after the dawn")
	check(dez.away == null, "and Dez is home")
	g.world.free()


func test_a_trip_that_reaches_the_gate_before_the_dusk_comes_in_the_same_day() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var party := _trip(sim)
	Helpers.at(sim, DAY, 15.0)
	sim.scavenge.finish_played(party, {"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0})
	check(float(party.return_at) < sim.clock_min + (sim.seasons.dusk_hour() - 15.0) * 60.0, "the road home ends before the dusk")
	var guard := 0
	while not sim.scavenge.parties.is_empty() and guard < 400:
		Helpers.run(sim, 1.0)
		guard += 1
	check(sim.scavenge.parties.is_empty(), "they are in")
	check(sim.hour < sim.seasons.dusk_hour(), "before the dusk (%.2f)" % sim.hour)
	g.world.free()


func test_the_real_waves_make_the_milestone_night_a_big_one_for_the_warning() -> void:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, DAY, 8.0)
	if sim.waves.big_night(DAY).is_empty():
		g.world.free()
		return    # (the real Big Nights are not in yet: the fake's tests above stand for them)
	var w: Dictionary = sim.scavenge.night_warning("houses", "", 1.0)
	check(bool(w.big), "tonight is a Big Night by the real waves")
	check(String(w.text).begins_with("Big Night tonight"), "and the Map says so: %s" % String(w.text))
	Helpers.at(sim, DAY - 1, 8.0)
	check(not bool(sim.scavenge.night_warning("houses", "", 1.0).big), "the night before it is an ordinary one")
	g.world.free()
