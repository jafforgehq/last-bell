extends "res://tests/case.gd"
## The seasons (round 10): Autumn is the 30-night game as it was (every answer the old one), the campaign goes
## on through Winter, Spring and Summer, each with its own hours of day, weather, garden, appetite, roads and
## nights, each ending with its Big Night; the season turns at the dawn after it. Data: assets/data/seasons.json.

const Helpers := preload("res://tests/helpers.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _game(campaign: bool = true, crew: int = 6) -> Dictionary:
	var g := Helpers.make(7, 1, crew, campaign)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	return g


## Puts a campaign into the first day of Winter, at `hour`.
func _winter(sim, hour: float = 8.0) -> void:
	sim.seasons.index = 1
	sim.seasons._start_day = 31
	sim.seasons._dusk = 16.5
	sim.seasons._dawn = 7.5
	sim.day = 31
	sim.minutes = hour * 60.0
	sim.clock_min = 30.0 * 1440.0 + hour * 60.0 - 420.0
	sim.phase = sim.seasons.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.events.clear()


func _events(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if e.get("type", "") == type:
			out.append(e)
	return out


func test_the_data_has_four_seasons_and_autumn_is_the_old_game() -> void:
	var g := _game()
	var s = g.sim.seasons
	eq(s.count(), 4, "four seasons in a campaign")
	var names: Array = []
	for i in 4:
		names.append(String(s.season(i).id))
	eq(names, ["autumn", "winter", "spring", "summer"], "in turn")
	var a: Dictionary = s.season(0)
	eq(int(a.days), 30, "Autumn is thirty days")
	near(float(a.dusk), 19.0, 0.0001, "dusk at 19")
	near(float(a.dawn), 6.5, 0.0001, "day at 6.5")
	near(float(a.rain), 1.0 / 3.0, 0.0, "a third of the days rain")
	near(float(a.big), 2.4, 0.0, "the Big Night 2.4 times")
	for k in ["garden", "food", "water", "travel", "waves"]:
		near(float(a[k]), 1.0, 0.0, "Autumn's %s is 1" % k)
	for i in 4:
		check(String(s.season(i).blurb) != "" and s.season(i).tint is Array and s.season(i).temperature is Dictionary, "season %d is complete" % i)
	g.world.free()


func test_a_run_that_is_not_a_campaign_is_autumn_for_ever() -> void:
	var g := _game(false)
	var sim = g.sim
	var s = sim.seasons
	check(not s.campaign, "not a campaign")
	eq(s.count(), 1, "one season")
	eq(sim.scenario.total_days(), 30, "thirty days")
	for m in range(0, 24 * 60, 10):
		eq(s.phase_at(float(m)), Sim.phase_at(float(m)), "the old phases at minute %d" % m)
	for h in [0.0, 5.5, 6.5, 12.0, 19.0, 20.5, 23.9]:
		near(s.light_hour(h), h, 0.0, "the lighting's hour is the real one")
	for d in [1, 2, 10, 30]:
		near(sim.waves.budget_for(d), 30.0 * (1.0 + 0.1 * float(d - 1)), 0.0001, "the old budget of day %d" % d)
	near(sim.waves.night_budget(30), sim.waves.budget_for(30) * 2.4, 0.001, "the old Big Night")
	near(s.mult("garden"), 1.0, 0.0, "no season's multipliers")
	near(s.night_scale(), 1.0, 0.0, "the night is the night")
	near(sim.tactics.forecast_hour(), 17.0, 0.0, "the forecast at 17:00")
	# a non-campaign run does not change season even past its thirtieth day
	sim.day = 31
	s.on_new_day()
	eq(s.index, 0, "still Autumn")
	g.world.free()


func test_a_campaign_begins_in_autumn_with_the_schedule_of_autumn() -> void:
	var g := _game()
	var sim = g.sim
	var s = sim.seasons
	eq(s.index, 0, "Autumn")
	eq(s.end_day(), 30, "its last day is 30")
	eq(s.season_day(1), 1, "day 1")
	eq(s.season_day(12), 12, "day 12")
	eq(s.effective_day(12), 12, "the nights are sized by the day")
	near(s.dusk_hour(), 19.0, 0.0, "dusk at 19")
	near(s.dawn_hour(), 6.5, 0.0, "day at 6.5")
	eq(sim.scenario.total_days(), 30, "the Big Night is the thirtieth")
	check(sim.waves.is_big(30) and not sim.waves.is_big(29), "the Big Night is night 30")
	g.world.free()


func test_the_season_turns_at_the_dawn_after_its_last_night() -> void:
	var g := _game()
	var sim = g.sim
	sim.day = 30
	sim.minutes = 4.0 * 60.0
	sim.clock_min = 29.0 * 1440.0 + 21.0 * 60.0
	sim.phase = sim.seasons.phase_at(sim.minutes)
	sim.bell_rung = true
	sim.events.clear()
	var guard := 0
	while sim.day == 30 and guard < 6000:
		sim.update(1.0 / 30.0)
		guard += 1
	eq(sim.day, 31, "the thirty-first day has begun")
	eq(sim.seasons.index, 1, "it is Winter")
	eq(sim.over, "", "the run is not over: it is not victory yet")
	eq(_events(sim, "season").size(), 1, "one season event")
	eq(String(_events(sim, "season")[0].season), "winter", "the event names it")
	var banner := ""
	for e in _events(sim, "banner"):
		if String(e.text).contains("Winter"):
			banner = String(e.text)
	eq(banner, "Winter begins", "a banner says so")
	eq(sim.scenario.total_days(), 54, "Winter's last day is 54")
	eq(sim.seasons.season_day(), 1, "the first day of Winter")
	eq(sim.seasons.effective_day(31), 7, "its nights start as Autumn's seventh")
	near(sim.seasons.dusk_hour(), 16.5, 0.0, "dusk is early from today")
	near(sim.seasons.dawn_hour(), 6.5, 0.0, "but today's dawn was Autumn's: the day is not run twice")
	g.world.free()


func test_a_day_is_never_run_twice_across_the_turn_of_the_season() -> void:
	var g := _game()
	var sim = g.sim
	sim.day = 30
	sim.minutes = 17.0 * 60.0
	sim.clock_min = 29.0 * 1440.0 + 10.0 * 60.0
	sim.phase = sim.seasons.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.events.clear()
	var starts: Array = []
	var bells: Array = []
	var phases: Array = []
	var last := ""
	# from 17:00 of day 30 to 12:00 of day 33: three nights
	var steps := int((3.0 * 24.0 - 5.0) * 20.0 * 30.0)
	for i in steps:
		sim.update(1.0 / 30.0)
		for e in sim.events:
			if e.type == "day_start":
				starts.append([int(e.day), snappedf(sim.hour, 0.1)])
			elif e.type == "bell":
				bells.append([sim.day, snappedf(sim.hour, 0.1)])
		sim.events.clear()
		if sim.phase != last:
			phases.append(sim.phase)
			last = sim.phase
	eq(starts.size(), 3, "three mornings: %s" % str(starts))
	eq(starts.map(func(a): return a[0]), [31, 32, 33], "the days are 31, 32, 33")
	near(float(starts[0][1]), 6.5, 0.15, "the first morning of Winter is at the old dawn")
	near(float(starts[1][1]), 7.5, 0.15, "the second is at the winter's")
	eq(bells.size(), 3, "a bell each night: %s" % str(bells))
	near(float(bells[1][1]), 16.5, 0.15, "the winter's bell is at 16:30")
	# day, dusk, night, dawn, day ... in order
	var expect := ["dusk", "night", "dawn", "day", "dusk", "night", "dawn", "day", "dusk", "night", "dawn", "day"]
	eq(phases.slice(1), expect, "the phases follow each other, each night once")
	g.world.free()


func test_the_winter_schedule_and_the_light_that_follows_it() -> void:
	var g := _game()
	var sim = g.sim
	_winter(sim)
	var s = sim.seasons
	eq(s.phase_at(16.6 * 60.0), "dusk", "16:36 is dusk")
	eq(s.phase_at(18.1 * 60.0), "night", "18:06 is night")
	eq(s.phase_at(3.0 * 60.0), "night", "03:00 is night")
	eq(s.phase_at(6.9 * 60.0), "dawn", "06:54 is dawn")
	eq(s.phase_at(7.6 * 60.0), "day", "07:36 is day")
	near(s.night_hours(), 24.0 - 18.0 + 6.5, 0.0001, "a long night")
	check(s.night_scale() > 1.2, "the night is longer than Autumn's")
	near(s.light_hour(16.5), 19.0, 0.0001, "dusk looks like dusk")
	near(s.light_hour(18.0), 20.5, 0.0001, "night falls as it does")
	near(s.light_hour(7.5), 6.5, 0.0001, "the day begins as it does")
	near(s.light_hour(6.5), 5.5, 0.0001, "an hour before it, the dawn")
	near(s.light_hour(12.0), 12.75, 0.001, "noon is a little past noon")
	near(sim.tactics.forecast_hour(), 14.5, 0.0, "the forecast comes two hours before dusk")
	g.world.free()


func test_the_bell_rings_at_the_seasons_dusk() -> void:
	var g := _game()
	var sim = g.sim
	_winter(sim, 16.0)
	sim.supplies.sources_day = sim.day
	var guard := 0
	while not sim.bell_rung and guard < 4000:
		sim.update(1.0 / 30.0)
		guard += 1
	check(sim.bell_rung, "the bell has rung")
	near(sim.hour, 16.5, 0.1, "at half past four")
	g.world.free()


func test_the_last_season_ends_in_victory_and_the_others_do_not() -> void:
	var g := _game()
	var sim = g.sim
	# Autumn's dawn after day 30 turns the season, it does not win
	sim.day = 31
	sim.seasons.on_new_day()
	sim.scenario.update(0.1)
	eq(sim.over, "", "no victory at the end of Autumn in a campaign")
	eq(sim.seasons.index, 1, "Winter")
	# the last season: past its last day is victory
	sim.seasons.index = 3
	sim.seasons._start_day = 79
	sim.day = 103
	sim.seasons.on_new_day()
	eq(sim.seasons.index, 3, "Summer is the last")
	sim.scenario.update(0.1)
	eq(sim.over, "victory", "the campaign is won")
	g.world.free()
	var h := _game(false)
	h.sim.day = 31
	h.sim.scenario.update(0.1)
	eq(h.sim.over, "victory", "the 30-night game is won at its thirty-first dawn as before")
	h.world.free()


func test_each_seasons_nights_are_sized_by_its_own_days() -> void:
	var g := _game()
	var sim = g.sim
	_winter(sim)
	near(sim.waves.budget_for(31), 30.0 * (1.0 + 0.1 * 6.0) * 1.15, 0.001, "Winter's first night is Autumn's seventh, 15% bigger")
	near(sim.waves.budget_for(54), 30.0 * (1.0 + 0.1 * 29.0) * 1.15, 0.001, "its last is Autumn's thirtieth, 15% bigger")
	check(sim.waves.is_big(54) and not sim.waves.is_big(53), "its Big Night is night 54")
	near(sim.waves.night_budget(54), sim.waves.budget_for(54) * 2.6, 0.001, "with the Winter's own factor")
	var plan: Dictionary = sim.waves.plan_for(31)
	check(float(plan.budget) > 0.0, "a plan is made")
	g.world.free()


func test_the_dead_are_spread_over_a_longer_winter_night() -> void:
	var g := _game()
	var sim = g.sim
	var a: float = sim.seasons.night_scale()
	_winter(sim)
	var w: float = sim.seasons.night_scale()
	near(a, 1.0, 0.0001, "Autumn's night is the standard one")
	check(w > a, "Winter's night is longer: %.2f" % w)
	g.world.free()


func test_winter_starves_the_beds_and_spring_and_summer_feed_them() -> void:
	var g := _game()
	var sim = g.sim
	Helpers.idle_stores(sim)
	var gardener = sim.people[0]
	check(Helpers.seat(sim, gardener, "garden"), "someone at the beds")
	var yields := {}
	for i in 4:
		sim.seasons.index = i
		sim.stock.food = 10.0
		sim.supplies._garden(1.0)
		yields[i] = float(sim.stock.food) - 10.0
	near(yields[0], 0.2, 0.0001, "Autumn: a gardener an hour grows 0.2")
	near(yields[1], 0.2 * 0.15, 0.0001, "Winter: 0.03")
	near(yields[2], 0.2 * 0.8, 0.0001, "Spring: 0.16")
	near(yields[3], 0.2 * 1.3, 0.0001, "Summer: 0.26")
	g.world.free()


func test_the_seasons_change_what_people_eat_and_drink() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.food = 36.0
	sim.stock.water = 54.0
	var autumn_food: float = sim.supplies.days_left("food")
	var autumn_water: float = sim.supplies.days_left("water")
	sim.seasons.index = 1
	near(sim.supplies.days_left("food"), autumn_food / 1.15, 0.001, "Winter: the food lasts less")
	near(sim.supplies.days_left("water"), autumn_water / 0.9, 0.001, "and the water more")
	sim.seasons.index = 3
	near(sim.supplies.days_left("water"), autumn_water / 1.3, 0.001, "Summer: the water goes")
	# a meal takes more in Winter
	sim.seasons.index = 1
	sim.stock.food = 36.0
	sim.supplies.meals_done = 0
	var before: float = sim.stock.food
	sim.supplies._serve_meal()
	var eaten: float = before - float(sim.stock.food)
	near(eaten, float(sim.people.size()) * (1.0 / 3.0) * 1.15, 0.001, "a meal in Winter is 15% bigger")
	g.world.free()


func test_the_weather_has_snow_only_in_winter() -> void:
	var g := _game()
	var sim = g.sim
	var seen := {"clear": 0, "rain": 0, "snow": 0}
	for i in 80:
		sim.seasons.index = 1
		sim.supplies.roll_dawn()
		seen[sim.weather] += 1
	check(seen.snow > 10, "Winter has snow (%s)" % str(seen))
	check(seen.clear > 10 and seen.rain > 0, "and clear days and rain (%s)" % str(seen))
	var other := {"clear": 0, "rain": 0, "snow": 0}
	for idx in [0, 2, 3]:
		for i in 60:
			sim.seasons.index = idx
			sim.supplies.roll_dawn()
			other[sim.weather] += 1
	eq(other.snow, 0, "no snow in the other seasons")
	sim.seasons.index = 3
	var wet := 0
	for i in 200:
		sim.supplies.roll_dawn()
		if sim.weather != "clear":
			wet += 1
	check(wet < 60, "Summer is dry (%d wet days in 200)" % wet)
	g.world.free()


func test_the_look_of_the_snow_reaches_the_lighting() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.enabled = true
	sim.weather = "snow"
	var look: Dictionary = sim.storyteller.look()
	eq(bool(look.snow), true, "snow is told to the lighting")
	eq(bool(look.rain), false, "and it is not rain")
	g.world.free()


func test_the_road_is_slower_in_winter_and_quicker_in_summer() -> void:
	var g := _game(true, 3)
	var sim = g.sim
	var base: float = sim.town.hours_to("houses")
	check(base > 0.0, "the houses are on the road")
	sim.seasons.index = 1
	near(sim.town.hours_to("houses"), base * 1.3, 0.0001, "Winter: 30% more")
	sim.seasons.index = 3
	near(sim.town.hours_to("houses"), base * 0.9, 0.0001, "Summer: 10% less")
	sim.seasons.index = 0
	near(sim.town.hours_to("houses"), base, 0.0001, "Autumn: as it was")
	g.world.free()


func test_the_temperature_follows_the_season_and_the_hour() -> void:
	var g := _game()
	var s = g.sim.seasons
	s.index = 1
	check(s.temperature(15.0) < 5.0, "Winter is cold")
	s.index = 3
	check(s.temperature(15.0) > 20.0, "Summer is warm")
	check(s.temperature(15.0) > s.temperature(4.0), "the afternoon is the warmest")
	g.world.free()


func test_a_save_keeps_the_season_and_the_schedule() -> void:
	var g := _game()
	var sim = g.sim
	_winter(sim, 10.0)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var b := _game(false)
	check(SaveGame.apply(b.sim, d), "the save loads")
	var s = b.sim.seasons
	check(s.campaign, "still a campaign")
	eq(s.index, 1, "Winter")
	eq(s.end_day(), 54, "its last day")
	near(s.dusk_hour(), 16.5, 0.0, "the winter dusk")
	near(s.dawn_hour(), 7.5, 0.0, "the winter dawn")
	g.world.free()
	b.world.free()


func test_an_old_save_loads_as_autumn() -> void:
	var g := _game(false)
	var sim = g.sim
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	d["modules"].erase("seasons")
	var b := _game(true)
	_winter(b.sim)
	check(SaveGame.apply(b.sim, d), "the save loads")
	check(not b.sim.seasons.campaign, "not a campaign")
	eq(b.sim.seasons.index, 0, "Autumn")
	eq(b.sim.scenario.total_days(), 30, "thirty days")
	g.world.free()
	b.world.free()


func test_the_clock_and_the_phase_agree_after_a_load_in_the_dark() -> void:
	var g := _game()
	var sim = g.sim
	_winter(sim, 18.5)
	check(sim.phase == "night", "18:30 in Winter is night (%s)" % sim.phase)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var b := _game(false)
	check(SaveGame.apply(b.sim, d), "the save loads")
	b.sim.update(1.0 / 30.0)
	eq(b.sim.phase, "night", "still night after the load")
	g.world.free()
	b.world.free()


func test_every_season_is_sound() -> void:
	var g := _game()
	var s = g.sim.seasons
	var ids := {}
	for i in 4:
		var x: Dictionary = s.season(i)
		check(not ids.has(String(x.id)), "ids are unique")
		ids[String(x.id)] = true
		check(int(x.days) >= 20 and int(x.days) <= 40, "%s: a sensible length" % x.id)
		check(float(x.dusk) >= 15.0 and float(x.dusk) + 1.5 <= 23.0, "%s: dusk is in the evening" % x.id)
		check(float(x.dawn) >= 4.5 and float(x.dawn) <= 8.5, "%s: the day begins in the morning" % x.id)
		var night: float = (24.0 - float(x.dusk) - 1.5) + (float(x.dawn) - 1.0)
		check(night >= 6.0 and night <= 16.0, "%s: a night of %.1f hours" % [x.id, night])
		for k in ["garden", "food", "water", "travel", "waves"]:
			check(float(x[k]) >= 0.1 and float(x[k]) <= 1.6, "%s: %s is within reason" % [x.id, k])
		check(float(x.big) >= 2.0 and float(x.big) <= 3.5, "%s: the Big Night's factor" % x.id)
		check(float(x.rain) >= 0.0 and float(x.rain) <= 1.0 and float(x.snow) >= 0.0 and float(x.snow) <= 1.0, "%s: chances are chances" % x.id)
		for c in x.tint:
			check(float(c) >= 0.5 and float(c) <= 1.0, "%s: a tint that is a light filter" % x.id)
	g.world.free()


func test_the_big_night_is_named_and_only_the_last_is_the_last_night() -> void:
	var g := _game()
	var sim = g.sim
	sim.waves.enabled = true
	sim.day = 30
	sim.minutes = 19.05 * 60.0
	sim.phase = sim.seasons.phase_at(sim.minutes)
	sim.events.clear()
	sim.update(1.0 / 30.0)
	var banners: Array = []
	for e in _events(sim, "banner"):
		banners.append(String(e.text))
	check(banners.has("The Big Night"), "Autumn's last night is a Big Night in a campaign: %s" % str(banners))
	check(not banners.has("The last night"), "not the last night")
	g.world.free()
	var h := _game(false)
	h.sim.waves.enabled = true
	h.sim.day = 30
	h.sim.minutes = 19.05 * 60.0
	h.sim.phase = h.sim.seasons.phase_at(h.sim.minutes)
	h.sim.events.clear()
	h.sim.update(1.0 / 30.0)
	var old: Array = []
	for e in _events(h.sim, "banner"):
		old.append(String(e.text))
	check(old.has("The last night"), "the 30-night game keeps its words: %s" % str(old))
	h.world.free()


func test_every_season_has_cards_on_the_radio() -> void:
	var g := _game()
	var sim = g.sim
	sim.storyteller.enabled = true
	for i in 4:
		sim.seasons.jump_to(i)
		var first: int = sim.seasons._start_day
		var last: int = sim.seasons.end_day()
		var cards := 0
		for d in range(first, last + 1):
			var c: Dictionary = sim.storyteller.draw(d)
			if not c.is_empty():
				cards += 1
				check(d > first and d < last, "no card on a season's first or last day (%s, day %d)" % [sim.seasons.current().id, d])
		check(cards >= 3, "%s has cards on the radio (%d)" % [sim.seasons.current().id, cards])
	g.world.free()


func test_a_horde_card_counts_by_the_days_of_the_nights_not_the_calendar() -> void:
	var g := _game()
	var sim = g.sim
	sim.seasons.jump_to(3)
	sim.day = sim.seasons._start_day + 10
	# a card that adds a walker for every N days: by the effective day (11 + 18), not by day 90
	var before: int = sim.zombies.size()
	sim.storyteller._fx_spawn({"count": 2, "at": "north", "plus_day_div": 3}, {"day": sim.day}, {"changes": []})
	var came: int = sim.zombies.size() - before
	eq(came, 2 + floori(float(sim.seasons.effective_day(sim.day)) / 3.0), "by the effective day")
	g.world.free()


func test_the_lookouts_empty_post_is_said_before_the_seasons_forecast() -> void:
	var g := _game()
	var sim = g.sim
	_winter(sim, 14.1)
	for p in sim.people:
		sim.jobs.unassign(p) if sim.jobs.has_method("unassign") else null
	var watch = sim.jobs.operator("watch")
	if watch != null:
		sim.jobs.assign(watch, "")
	sim.alerts.clear()
	sim.jobs._alert_day = {"radio": 99, "watch": 0}
	sim.jobs.update(1.0 / 30.0)
	check(sim.alerts.has("job-watch"), "Winter: the empty post is said at 14:06, half an hour before the forecast at 14:30")
	g.world.free()
	var h := _game(false)
	h.sim.day = 5
	h.sim.minutes = 16.6 * 60.0
	h.sim.phase = "day"
	var w2 = h.sim.jobs.operator("watch")
	if w2 != null:
		h.sim.jobs.assign(w2, "")
	h.sim.alerts.clear()
	h.sim.jobs._alert_day = {"radio": 99, "watch": 0}
	h.sim.jobs.update(1.0 / 30.0)
	check(h.sim.alerts.has("job-watch"), "Autumn: as before, at 16:36")
	h.world.free()


func test_a_save_with_a_broken_schedule_loads_with_the_seasons_own() -> void:
	var g := _game()
	var sim = g.sim
	for bad in [{"dusk": 0.0, "dawn": 7.5}, {"dusk": 16.5, "dawn": 16.5}, {"dusk": 30.0, "dawn": 6.5}, {"dusk": 19.0, "dawn": -2.0}, {"dusk": 12.0, "dawn": 2.0}]:
		var d := {"campaign": true, "index": 1, "start_day": 31}
		d.merge(bad)
		sim.seasons.load_state(d)
		near(sim.seasons.dusk_hour(), 16.5, 0.0, "Winter's own dusk after %s" % str(bad))
		near(sim.seasons.dawn_hour(), 7.5, 0.0, "and its dawn after %s" % str(bad))
	# a sound one is kept (the dawn that waits for the dusk)
	sim.seasons.load_state({"campaign": true, "index": 1, "start_day": 31, "dusk": 16.5, "dawn": 6.5})
	near(sim.seasons.dawn_hour(), 6.5, 0.0, "the old dawn of the first morning is kept")
	g.world.free()
