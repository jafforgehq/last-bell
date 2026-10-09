extends "res://tests/case.gd"
## The nights to hold (PH5, scripts/town/one_house.gd, `end.nights_to_hold` of assets/data/one_house.json): the run is won at the dawn that makes N attack nights held. 1 is the game as it was; a night that is
## not held does not count and the run goes on; the run keeps its own N in its save; the end card does not say one night and two survivors when N is more.

const Helpers := preload("res://tests/helpers.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


## A One House run on the mini town, staged to the day before the first attack night (`fourth`: the dead come from the next day's dusk).
func _run() -> Dictionary:
	var g := Helpers.town_game(1, {"blocks": 2})
	OneHouse.begin(g.sim, 1, 1)
	OneHouse.stage_to(g.sim, "fourth")
	return g


## The first moment of day `day` (the dawn after the night of day - 1), judged.
func _dawn(sim, day: int) -> void:
	sim.day = day
	sim.phase = "day"
	sim.scenario._watch_the_dawn()


func _types(sim) -> Array:
	var out: Array = []
	for e in sim.events:
		out.append(String(e.type))
	return out


func test_one_night_is_the_default_and_the_game_as_it_was() -> void:
	var g := _run()
	var sim = g.sim
	var s = sim.scenario
	eq(int(OneHouse.data().end.nights_to_hold), 1, "the data holds one night")
	eq(s.nights_to_hold(), 1, "so does the run")
	check(s.attacks_on() or s._attacks, "the attacks are on")
	var first: int = s._first_day
	sim.events.clear()
	_dawn(sim, first + 1)
	eq(sim.over, "victory", "one night held is the win")
	eq(s.stage(), "held", "held")
	var types := _types(sim)
	check(types.has("held") and types.has("over"), "the events are the old ones")
	eq(s.report().of, 1, "of one")
	eq(s.total_days(), maxi(int(OneHouse.data().total_days), first + 1), "the run's length is as it was")
	g.world.free()


func test_several_nights_are_held_one_dawn_at_a_time() -> void:
	var g := _run()
	var sim = g.sim
	var s = sim.scenario
	s.set_nights_to_hold(3)
	var first: int = s._first_day
	eq(s.total_days(), maxi(int(OneHouse.data().total_days), first + 3), "the run is as long as the nights to hold")
	sim.events.clear()
	_dawn(sim, first + 1)
	eq(sim.over, "", "one of three is not the end")
	eq(s.stage(), "fortify", "the stage goes on")
	eq(s.report().nights, 1, "one held")
	var types := _types(sim)
	check(not types.has("held") and not types.has("over"), "no end of the run yet (the 'held' event would put the morning card away)")
	check(types.has("banner"), "but the night is told")
	_dawn(sim, first + 2)
	eq(sim.over, "", "two of three is not the end")
	eq(s.report().nights, 2, "two held")
	_dawn(sim, first + 3)
	eq(sim.over, "victory", "three of three is the win")
	eq(s.report().nights, 3, "three held")
	eq(s.report().of, 3, "of three")
	eq(s.night_log().size(), 3, "three dawns judged")
	var card: Dictionary = s.end_card()
	eq(card.stats[0], ["Nights held", "3"], "the card counts them")
	check(String(card.title) != String(OneHouse.data().end.title) and not String(card.line).contains("Two survivors"), "and does not say one night and two survivors")
	check(not String(card.line).to_lower().contains("first night") and not String(card.title).to_lower().contains("first night"), "nor the first night")
	g.world.free()


func test_a_night_not_held_does_not_count_and_the_run_goes_on() -> void:
	var g := _run()
	var sim = g.sim
	var s = sim.scenario
	s.set_nights_to_hold(2)
	var first: int = s._first_day
	var down = null
	for seg in sim.segments:
		if int(seg.id) < 100:
			down = seg
	check(down != null, "the base has a section")
	if down == null:
		g.world.free()
		return
	var was: int = down.state
	down.state = 3
	_dawn(sim, first + 1)
	eq(sim.over, "", "a section down at the dawn: not the end")
	eq(s.report().nights, 0, "and not counted")
	eq(s.first_night_result(), "not_held", "the first night is said not held")
	eq(String(s.night_log()[0].why), "wall", "because of the wall")
	down.state = was
	_dawn(sim, first + 2)
	eq(sim.over, "", "mended, held: one of two")
	eq(s.report().nights, 1, "one held")
	_dawn(sim, first + 3)
	eq(sim.over, "victory", "the second held night is the win, a night later than it would have been")
	eq(s.report().nights, 2, "two held")
	g.world.free()


func test_the_run_keeps_its_own_nights_to_hold() -> void:
	var g := _run()
	var sim = g.sim
	var s = sim.scenario
	s.set_nights_to_hold(7)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	eq(int(saved.modules.scenario.to_hold), 7, "the save says seven")
	var f := Helpers.town_game(1, {"blocks": 2})
	OneHouse.install(f.sim)
	check(SaveGame.apply(f.sim, saved), "the save is read")
	eq(f.sim.scenario.nights_to_hold(), 7, "the run is still of seven nights, whatever the data says")
	# a save of before the nights to hold were the run's own has no such key: the data's
	var old: Dictionary = saved.duplicate(true)
	old.modules.scenario.erase("to_hold")
	var h := Helpers.town_game(1, {"blocks": 2})
	OneHouse.install(h.sim)
	check(SaveGame.apply(h.sim, old), "an old save is read")
	eq(h.sim.scenario.nights_to_hold(), int(OneHouse.data().end.nights_to_hold), "and takes the data's")
	g.world.free()
	f.world.free()
	h.world.free()
