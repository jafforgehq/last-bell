extends "res://tests/case.gd"
## Fix of the review of round 19, F4: the road-home rule for a trip the player drives (round 21's live drive). The rule the radio, the Map and
## the place's line explained was "a party that cannot be home before the dusk is out until morning" (`Scavenge._is_due`); a trip the avatar
## leads is a live drive: the party is held on its road (`road_live`) and arrives by night as well (`night_ok`), so he is NOT out until
## morning, he drives home in the dark and the base holds the first of the night until he is back. The words and `road_status` must say
## what the game does: for a live trip, "home after the dusk", for a trip that is not driven (an errand, the old overlay) "out until
## morning" as before. And `road_status` treated the road THERE as if the party were already at the place.
## Numbers are read through NightData and the town; the waves' Big Night is made by hand (tests/test_night_calls.gd's fake).

const Helpers := preload("res://tests/helpers.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const NightCalls := preload("res://scripts/sim/night_calls.gd")
const NightKit := preload("res://scripts/ui/night_kit.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const Calls := preload("res://tests/test_night_calls.gd")

const DAY := 10


func _game(big: bool = true, hour: float = 8.0) -> Dictionary:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
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


## A trip begun through the flow, as the game does it (a live drive: `PlaceFlow.live_for`): Ruth and Dez to the houses.
func _flow_trip(sim, place: String = "houses", vehicle: String = ""):
	var flow = PlaceFlow.new(sim)
	check(flow.begin([_p(sim, "ruth"), _p(sim, "dez")], place, vehicle), "the trip begins: %s" % flow.error)
	return flow


## A trip begun by the scavenging module alone (nothing drives it: what an overlay road or a test does).
func _plain_trip(sim) -> Dictionary:
	var party: Dictionary = sim.scavenge.begin_played([_p(sim, "ruth"), _p(sim, "dez")], "houses", "loot", "")
	check(not party.is_empty(), "the trip begins")
	return party


func _news(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if e.kind == kind:
			out.append(e)
	return out


func _end(g: Dictionary) -> void:
	PlaceFlow.live_enabled = true
	g.world.free()


# ------------------------------------------------------------ the party knows it is driven --

func test_a_trip_the_flow_begins_is_marked_live_and_one_the_module_begins_is_not() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _flow_trip(sim)
	check(bool(flow.party.get("live", false)), "the avatar's trip is a live drive")
	_end(g)
	var h := _game()
	var s2 = h.sim
	check(not bool(_plain_trip(s2).get("live", false)), "a trip nobody drives is not")
	_end(h)
	PlaceFlow.live_enabled = false
	var k := _game()
	PlaceFlow.live_enabled = false
	var s3 = k.sim
	var overlay = _flow_trip(s3)
	check(not bool(overlay.party.get("live", false)), "the old overlay's road (`live_enabled` off, `--fastroad`) is not either")
	_end(k)


# ------------------------------------------------------------ what the rule really is --

func test_a_live_party_on_its_road_home_comes_in_by_night_so_it_is_not_out_until_morning() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _flow_trip(sim)
	var party: Dictionary = flow.party
	Helpers.at(sim, DAY, 18.5)    # (the dusk is on them: the road home begins after it)
	sim.scavenge.finish_played(party, {"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0})
	flow.begin_leg("home")
	Helpers.at(sim, DAY, 20.5)
	Helpers.run(sim, 1.0)
	eq(sim.scavenge.parties.size(), 1, "the drive is on, in the dark: the colony does not bring them in by its own clock")
	sim.scavenge.arrive_home(party)
	var guard := 0
	while not sim.scavenge.parties.is_empty() and guard < 200:
		Helpers.run(sim, 1.0)
		guard += 1
	check(sim.scavenge.parties.is_empty(), "the drive ends at the gate and they come in, at night")
	check(String(sim.phase) != "day", "(it is night: %s)" % sim.phase)
	_end(g)


# ----------------------------------------------------------------- road_status --

func test_a_live_trip_that_is_late_says_home_after_the_dusk_not_out_tonight() -> void:
	var g := _game()
	var sim = g.sim
	_flow_trip(sim)
	var road: float = sim.scavenge.road_minutes("houses", "")
	Helpers.at(sim, DAY, sim.seasons.dusk_hour() - 0.2)    # (in the place, 12 minutes to the dusk: home after it)
	var st: Dictionary = sim.radio.night.road_status()
	eq(st.state, "late", "it cannot be home before the dusk")
	check(bool(st.live), "and it is driven")
	var text := String(st.text)
	check(not text.to_lower().contains("out tonight") and not text.to_lower().contains("until morning"), "it does not say he is out tonight: %s" % text)
	check(text.to_lower().contains("after the dusk"), "it says he will be home after the dusk: %s" % text)
	check(text.contains(NightCalls.clock_text(NightCalls.hour_of(float(sim.clock_min) + road))), "and about when: %s" % text)
	check(text.to_lower().contains("until you are back") or text.to_lower().contains("until you are home"), "and what the base does until then: %s" % text)
	_end(g)
	var h := _game()
	var s2 = h.sim
	_plain_trip(s2)
	Helpers.at(s2, DAY, s2.seasons.dusk_hour() - 0.2)
	var plain: Dictionary = s2.radio.night.road_status()
	eq(plain.state, "late", "(a trip nobody drives: late too)")
	check(String(plain.text).begins_with("You will be out tonight"), "and for it the words are the old ones, they are true: %s" % String(plain.text))
	_end(h)


func test_the_bell_with_a_live_trip_still_out_is_not_you_stayed_out() -> void:
	var g := _game()
	var sim = g.sim
	_flow_trip(sim)
	Helpers.at(sim, DAY, sim.seasons.dusk_hour() + 0.2)
	Helpers.run(sim, 0.2)
	var told := _news(sim, "night_road")
	eq(told.size(), 1, "the radio says so once")
	if not told.is_empty():
		check(String(told[0].text) != "You stayed out", "not the old line: %s" % String(told[0].text))
		check(String(told[0].text).to_lower().contains("still out"), "he is still out: %s" % String(told[0].text))
		check(String(told[0].sub).to_lower().contains("until you are back"), "and the base holds it until he is back: %s" % String(told[0].sub))
		check(not String(told[0].sub).to_lower().contains("alone"), "not alone for the night: %s" % String(told[0].sub))
	_end(g)
	var h := _game()
	var s2 = h.sim
	_plain_trip(s2)
	Helpers.at(s2, DAY, s2.seasons.dusk_hour() + 0.2)
	Helpers.run(s2, 0.2)
	var told2 := _news(s2, "night_road")
	check(not told2.is_empty() and String(told2[0].text) == "You stayed out", "a trip nobody drives: the old line")
	_end(h)


func test_the_road_there_is_not_the_place_a_party_on_it_is_still_driving_out() -> void:
	var g := _game()
	var sim = g.sim
	var margin: float = NightData.num("forecast.road_margin_min")
	sim.town.reveal("scrapyard")    # (a long way: 4 h 40 on foot; trips begin by ten in the morning, so only a long road meets the dusk)
	var road: float = sim.scavenge.road_minutes("scrapyard", "")
	Helpers.at(sim, DAY, 9.0)
	var flow = _flow_trip(sim, "scrapyard")
	var st: Dictionary = sim.radio.night.road_status()
	var home_by: float = float(sim.seasons.dusk_hour()) * 60.0 - margin    # (hour of the day, in minutes)
	check(road > 250.0 and 9.0 * 60.0 + 2.0 * road > home_by - 60.0, "(the trip is a long one: %.0f minutes of road, home at %.1f, to be home by %.1f)" % [road, 9.0 + 2.0 * road / 60.0, home_by / 60.0])
	eq(String(st.stage), "there", "the car is driving out")
	near(float(st.arrival), float(sim.clock_min) + 2.0 * road, 0.5, "the soonest it can be home is a whole round trip away, not one road")
	eq(String(st.state), "soon", "a round trip that ends within the hour before the leave-by hour is 'soon' (it was 'free': one road was counted)")
	check(not String(st.state) in ["free", "now"], "(nothing can be asked of the road there)")
	Helpers.run(sim, 0.3)
	eq(_asks(sim).size(), 0, "no 'time to head home' call while the car is still driving out")
	# they are at the place, at the hour to leave by: now is the time
	Helpers.at(sim, DAY, NightCalls.hour_of(float(flow.party.depart) + road + 1.0))
	var at_place: Dictionary = sim.radio.night.road_status()
	eq(String(at_place.stage), "place", "at the place")
	Helpers.at(sim, DAY, float(sim.seasons.dusk_hour()) - (margin + road) / 60.0)
	eq(String(sim.radio.night.road_status().state), "now", "with no time to spare: now")
	Helpers.run(sim, 0.1)
	eq(_asks(sim).size(), 1, "and the call comes now")
	_end(g)


## The night_road calls that wait for an answer.
func _asks(sim) -> Array:
	var out: Array = []
	for e in _news(sim, "night_road"):
		if not e.options.is_empty():
			out.append(e)
	return out


func test_a_party_that_began_before_the_hour_and_has_time_is_free_while_it_drives_out() -> void:
	var g := _game()
	var sim = g.sim
	_flow_trip(sim)
	var st: Dictionary = sim.radio.night.road_status()
	eq(String(st.stage), "there", "driving out at eight")
	eq(String(st.state), "free", "with the whole day: free")
	_end(g)


func test_the_call_to_head_home_of_a_live_trip_says_the_dark_road_not_that_the_base_is_alone() -> void:
	var g := _game()
	var sim = g.sim
	_flow_trip(sim)
	var road: float = sim.scavenge.road_minutes("houses", "")
	var margin: float = NightData.num("forecast.road_margin_min")
	Helpers.at(sim, DAY, float(sim.seasons.dusk_hour()) - (margin + road) / 60.0)    # (in the place, at the hour to leave by)
	Helpers.run(sim, 0.1)
	var asks := _asks(sim)
	eq(asks.size(), 1, "the call is raised at the hour to leave by")
	if not asks.is_empty():
		var c: Dictionary = asks[0]
		check(String(c.sub).to_lower().contains("in the dark"), "it says the road home is then in the dark: %s" % String(c.sub))
		check(not String(c.sub).to_lower().contains("holds the night alone"), "and not that the base holds the night alone: %s" % String(c.sub))
		check(not String(c.options[1].label).contains("holds alone"), "the stay option is honest too: %s" % String(c.options[1].label))
		eq(c.default, "stay", "the default is still to stay")
	_end(g)
	var h := _game()
	var s2 = h.sim
	_plain_trip(s2)
	Helpers.at(s2, DAY, float(s2.seasons.dusk_hour()) - (margin + road) / 60.0)
	Helpers.run(s2, 0.1)
	var plain := _asks(s2)
	check(not plain.is_empty() and String(plain[0].sub).contains("holds the night alone"), "a trip nobody drives: the old words, they are true")
	_end(h)


# ---------------------------------------------------------- the words of the Map and the HUD --

func test_the_maps_note_says_a_late_trip_is_driven_home_in_the_dark_or_left_to_an_errand_until_morning() -> void:
	var g := _game(true, 8.0)
	var sim = g.sim
	var long_trip: Dictionary = sim.scavenge.night_warning("houses", "", 12.0)
	check(not bool(long_trip.makes_it), "twelve hours there are not home before the dusk")
	var text := String(long_trip.text)
	check(text.to_lower().contains("in the dark"), "the Map says it can be driven home in the dark: %s" % text)
	check(not text.to_lower().contains("stay out and the base holds alone"), "and does not offer 'staying out' as the way: %s" % text)
	_end(g)
	var h := _game(false, 8.0)
	var s2 = h.sim
	var w: Dictionary = s2.scavenge.night_warning("houses", "", 12.0)
	var plain := String(w.text)
	check(plain.contains("out until morning"), "an errand the community goes on is out until morning, and the note says so: %s" % plain)
	check(plain.to_lower().contains("in the dark"), "and a trip you drive is home in the dark: %s" % plain)
	_end(h)
	var k := _game(true, 8.0)
	var s3 = k.sim
	var fine: Dictionary = s3.scavenge.night_warning("houses", "", 1.0)
	var road: float = s3.scavenge.road_minutes("houses", "")
	check(String(fine.text).begins_with("Big Night tonight: leave the place by %s" % NightCalls.clock_text(float(fine.leave_by))), "a trip that makes it keeps its leave-by line: %s" % String(fine.text))
	check(String(fine.text).contains(NightCalls.duration_text(road)), "with the road: %s" % String(fine.text))
	check(not String(fine.text).to_lower().contains("holds alone"), "(but it no longer says the base holds alone)")
	_end(k)


func test_the_place_line_of_a_live_late_trip_is_not_out_tonight() -> void:
	var late := {"on": true, "in_place": true, "live": true, "state": "late", "dusk": 600.0, "road_min": 80.0, "leave_by": 440.0, "text": "Home about 19:10, after the dusk: the base holds the Big Night until you are back", "big": true}
	var line: Dictionary = NightKit.road_line(late, 580.0)
	check(String(line.text) != "You will be out tonight", "a driven trip: not out tonight (%s)" % String(line.text))
	check(String(line.text).to_lower().contains("after the dusk"), "it says home after the dusk: %s" % String(line.text))
	eq(String(line.tone), "warn", "in amber")
	var plain := late.duplicate()
	plain["live"] = false
	plain["text"] = "You will be out tonight: the base holds the Big Night alone"
	eq(String(NightKit.road_line(plain, 580.0).text), "You will be out tonight", "a trip nobody drives: as before")
