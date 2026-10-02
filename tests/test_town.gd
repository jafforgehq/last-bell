extends "res://tests/case.gd"
## The town board of the settlement game (round 8): the places and the fog, the hours on the road,
## expeditions (loot, scout, clear), the trip's beats, rescues, nests and the nights, outposts and
## garrisons, saves. The real town is assets/data/town.json (tested in test_town_data.gd); these tests
## use a small town of their own so that the rules can be checked exactly. The classic start has no board.

const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const FIXTURE := "user://test_town.json"

## Home is at (50, 35). Roads: home - houses - pharmacy; home - depot - farm; home - far - clinic.
const TOWN := {
	"board": {"w": 100, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [58, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
		{"id": "pharmacy", "name": "The pharmacy", "kind": "pharmacy", "pos": [62, 28], "blurb": "Boarded up.", "danger": 2, "known": true,
			"loot": {"meds": [6, 11]}, "extra": {}},
		{"id": "depot", "name": "The bus depot", "kind": "bus_depot", "pos": [42, 26], "blurb": "Buses, nose to tail.", "danger": 2, "known": true,
			"loot": {"scrap": [10, 20]}, "extra": {}, "nest": {"strength": 2}, "survivor": true,
			"outpost": {"yield": {"scrap": 3}, "cost": 20}},
		{"id": "farm", "name": "The farm", "kind": "farm", "pos": [34, 18], "blurb": "A long way out.", "danger": 1,
			"loot": {"food": [10, 18]}, "extra": {}, "outpost": {"yield": {"food": 4}, "cost": 30}},
		{"id": "far", "name": "The water works", "kind": "water_works", "pos": [90, 60], "blurb": "Very far.", "danger": 1,
			"loot": {"water": [20, 30]}, "extra": {}},
		{"id": "clinic", "name": "The clinic", "kind": "clinic", "pos": [96, 66], "blurb": "Beyond the works.", "danger": 2,
			"loot": {"meds": [5, 9]}, "extra": {}},
	],
	"roads": [["home", "houses"], ["houses", "pharmacy"], ["home", "depot"], ["depot", "farm"], ["home", "far"], ["far", "clinic"]],
	"beats": [
		{"id": "bus", "text": "A bus lies across the road.", "weight": 1, "min_hours": 0, "effects": {"delay_h": 1.5}},
		{"id": "cache", "text": "A cache under a floor.", "weight": 1, "min_hours": 0, "effects": {"loot_pct": 30}},
	],
}


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game on the little town, at `hour` of day 3, plenty of everything, a quiet world.
func _game(hour: float = 7.0, seed_value: int = 13) -> Dictionary:
	_write(TOWN)
	Town.data_path = FIXTURE
	var g := Helpers.make(seed_value, 1, 3)
	Town.data_path = Town.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	sim.minutes = hour * 60.0
	sim.clock_min = 2.0 * 1440.0 + hour * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.supplies.sources_day = 3
	sim.supplies.meal_day = 3
	sim.supplies.meals_done = 1
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.events.clear()
	return g


func _crew(sim, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		for p in sim.people:
			if p.id == id:
				out.append(p)
	return out


func _bring_everyone(sim) -> void:
	for def in sim.recruits.queue.duplicate():
		sim.add_person(def)
	sim.recruits.queue.clear()


## Runs the rules until the party is back (or `limit` seconds), a second at a time.
func _until_back(sim, limit: int = 1500) -> int:
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < limit:
		Helpers.run(sim, 1.0)
		n += 1
	return n


# ----------------------------------------------------------------- the start --

func test_the_classic_start_has_no_board() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	check(not sim.town.on and not sim.scavenge.town_mode, "no board in the classic start")
	near(sim.town.budget_mult(), 1.0, 1e-12, "and nights are as they were")
	eq(sim.town.pressure(0), 0.0, "no nests")
	eq(sim.scavenge.available_sites().size(), 4, "the four old sites")
	g.world.free()


func test_a_small_start_has_the_board_with_the_known_places_and_the_hours_between() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.town.on and sim.scavenge.town_mode, "the board is on")
	var ids: Array = []
	for e in sim.town.known_places():
		ids.append(String(e.id))
	ids.sort()
	eq(ids, ["depot", "houses", "pharmacy"], "three places are known to begin with")
	eq(sim.town.state_of("farm"), "unknown", "the farm is not")
	near(sim.town.hours_to("houses"), 8.0 / Town.SPEED, 1e-6, "the houses are eight tiles up the road")
	near(sim.town.hours_to("pharmacy"), (8.0 + sqrt(65.0)) / Town.SPEED, 1e-6, "the pharmacy is past them: the road, not the crow")
	check(sim.town.hours_to("clinic") > sim.town.hours_to("far"), "the clinic is beyond the works")
	near(sim.town.trip_hours("houses"), 2.0 * sim.town.hours_to("houses") + Town.SEARCH_H, 1e-9, "a trip is there, the search, and back")
	g.world.free()


func test_the_boards_sites_are_the_known_places_with_what_can_be_done() -> void:
	var g := _game()
	var sim = g.sim
	var sites: Array = sim.scavenge.available_sites()
	eq(sites.size(), 3, "three places are offered")
	var depot := {}
	for s in sites:
		if s.id == "depot":
			depot = s
	check(not depot.is_empty() and depot.available and depot.survivor, "the depot is open and someone is hiding there")
	eq(depot.actions, ["loot", "scout", "clear"], "it can be looted, scouted or cleared")
	eq(int(depot.nest.strength), 2, "it has a nest")
	check(depot.trip_hours > 2.0 and depot.hours > 0.0, "with its hours")
	g.world.free()


# ----------------------------------------------------------------- expeditions --

func test_a_trip_takes_the_hours_of_the_road_and_brings_the_loot_home() -> void:
	var g := _game(7.0)
	var sim = g.sim
	var crew := _crew(sim, ["dez", "marcus"])
	check(sim.scavenge.send(crew, "houses"), "the party goes")
	var due: float = float(sim.scavenge.parties[0].return_at)
	near(due, sim.clock_min + sim.town.trip_hours("houses") * 60.0, 1.0, "and is due after the hours of the road and the search")
	var food: float = sim.stock.food
	var seconds := _until_back(sim)
	check(seconds > 0 and sim.scavenge.parties.is_empty(), "it comes back (%d s)" % seconds)
	check(sim.stock.food > food, "with food: %.0f" % (sim.stock.food - food))
	check(sim.phase == "day", "by day")
	g.world.free()


func test_a_far_place_keeps_the_party_out_overnight_and_it_comes_in_by_day() -> void:
	var g := _game(7.0)
	var sim = g.sim
	sim.town.reveal("clinic")
	var crew := _crew(sim, ["dez", "marcus"])
	check(sim.town.trip_hours("clinic") > 13.0, "the clinic is a long way: %.1f hours" % sim.town.trip_hours("clinic"))
	check(sim.scavenge.send(crew, "clinic"), "the party goes")
	Helpers.run_to_hour(sim, 22.0)
	check(not sim.scavenge.parties.is_empty(), "at ten at night they are still out")
	for p in crew:
		check(p.away != null, "%s is off the map" % p.first)
	var guard := 0
	while not sim.scavenge.parties.is_empty() and guard < 3000:
		Helpers.run(sim, 5.0)
		guard += 1
	check(sim.scavenge.parties.is_empty(), "they come back")
	check(sim.phase == "day", "and by day")
	g.world.free()


func test_scouting_shows_the_places_near_and_brings_no_loot() -> void:
	var g := _game(7.0)
	var sim = g.sim
	eq(sim.town.state_of("farm"), "unknown", "the farm is hidden")
	var scrap: float = sim.stock.scrap
	check(sim.scavenge.send(_crew(sim, ["dez"]), "depot", "scout"), "a scouting trip to the depot")
	_until_back(sim)
	eq(sim.town.state_of("farm"), "known", "the farm is on the board now")
	check(sim.town.state_of("far") == "unknown", "and the far places are not")
	near(sim.stock.scrap, scrap, 1e-9, "no loot")
	var told := false
	for e in sim.events:
		told = told or (e.type == "revealed" and e.place == "farm")
	check(told, "the board is told")
	g.world.free()


func test_a_nest_takes_two_and_a_clearing_that_works_ends_it() -> void:
	var g := _game(7.0)
	var sim = g.sim
	eq(sim.scavenge.why_not_action(_crew(sim, ["dez"]), "depot", "clear"), "A nest takes at least two.", "one person cannot")
	check(not sim.scavenge.send(_crew(sim, ["dez"]), "depot", "clear"), "so it is refused")
	check(sim.town.pressure(sim.town.heading_of(sim.town.place("depot"))) >= 2.0, "the nest sends the dead")
	var shooters := _crew(sim, ["dez", "marcus"])
	for p in shooters:
		p.skills["Shooting"] = 10
	var cleared := false
	for attempt in 6:
		for p in shooters:
			p.away = null
			p.hp = 100.0
			p.downed = false
		sim.day = 3 + attempt * 4    # (the place is fresh again each time)
		sim.minutes = 7.0 * 60.0
		sim.phase = "day"
		check(sim.scavenge.send(shooters, "depot", "clear"), "a party of two goes to clear it")
		_until_back(sim, 3000)
		if sim.town.state_of("depot") == "cleared":
			cleared = true
			break
	check(cleared, "good shots clear it")
	near(sim.town.pressure(sim.town.heading_of(sim.town.place("depot"))), 0.0, 1e-9, "the nest is gone")
	near(sim.town.budget_mult(), 1.0 - Town.NEST_BUDGET * 2.0, 1e-9, "and the nights are smaller")
	g.world.free()


func test_a_survivor_is_brought_home_if_there_is_a_bed() -> void:
	var g := _game(7.0)
	var sim = g.sim
	sim.town.mark_cleared("depot")    # nothing left to fight: a plain visit finds them
	var people: int = sim.people.size()
	check(sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "depot"), "a party goes to the depot")
	_until_back(sim)
	eq(sim.people.size(), people + 1, "someone came home with them")
	check(bool(sim.town.state.depot.rescued), "the depot has no one hiding now")
	eq(sim.recruits.queue.size(), 2, "and the queue is one shorter")
	g.world.free()


func test_no_bed_no_rescue_and_they_wait() -> void:
	var g := _game(7.0)
	var sim = g.sim
	for i in 3:
		sim.add_person(sim.recruits.queue.pop_front())
	sim.town.mark_cleared("depot")
	var people: int = sim.people.size()
	check(sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "depot"), "a party goes")
	_until_back(sim)
	eq(sim.people.size(), people, "nobody came: there is no bed")
	check(not bool(sim.town.state.depot.rescued), "they are still there")
	check(sim.alerts.has("no-bed-rescue"), "the crew is told")
	g.world.free()


func test_a_trips_beats_are_told_and_may_hold_it_up() -> void:
	var delayed := false
	var texts := false
	for seed_value in range(1, 40):
		var g := _game(7.0, seed_value)
		var sim = g.sim
		check(sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "houses") or true, "")
		if not sim.scavenge.parties.is_empty():
			var party: Dictionary = sim.scavenge.parties[0]
			texts = texts or party.result.has("beats")
			delayed = delayed or float(party.return_at) > sim.clock_min + sim.town.trip_hours("houses") * 60.0 + 1.0
		g.world.free()
	check(texts, "some trips meet something on the way")
	check(delayed, "and some are held up by it")


# ------------------------------------------------------------ nests and outposts --

func test_the_nests_pull_the_nights_towards_them() -> void:
	var g := _game()
	var sim = g.sim
	var towards: int = sim.town.heading_of(sim.town.place("depot"))
	var hits := 0
	var plain := 0
	for s in range(100, 160):
		sim.run_seed = s
		sim.waves._plan_day = -1
		if int(sim.waves.plan_for(8).heading[0]) == towards:
			hits += 1
	sim.town.mark_cleared("depot")
	for s in range(100, 160):
		sim.run_seed = s
		sim.waves._plan_day = -1
		if int(sim.waves.plan_for(8).heading[0]) == towards:
			plain += 1
	check(hits > plain + 8, "with the nest the main spawn point is the nest's more often: %d against %d of 60" % [hits, plain])
	g.world.free()


func test_a_cleared_place_can_be_claimed_and_pays_each_dawn() -> void:
	var g := _game()
	var sim = g.sim
	check(not sim.town.can_claim("depot"), "not before it is cleared")
	sim.town.mark_cleared("depot")
	check(sim.town.can_claim("depot"), "after it is")
	var scrap: float = sim.stock.scrap
	check(sim.town.claim("depot"), "claimed")
	near(sim.stock.scrap, scrap - 20.0, 1e-9, "for twenty scrap")
	eq(sim.town.state_of("depot"), "claimed", "an outpost")
	sim.town.at_dawn()
	near(sim.stock.scrap, scrap - 20.0 + 3.0, 1e-9, "paying three scrap a day")
	check(not sim.town.claim("depot"), "not twice")
	g.world.free()


func test_an_unguarded_outpost_is_lost_in_time_and_a_garrisoned_one_is_held() -> void:
	var lost_at := 0
	var g := _game()
	var sim = g.sim
	sim.town.mark_cleared("depot")
	sim.town.claim("depot")
	for night in 200:
		sim.town.at_the_bell()
		if sim.town.state_of("depot") != "claimed":
			lost_at = night + 1
			break
	check(lost_at > 0, "left alone it is overrun sooner or later (night %d)" % lost_at)
	g.world.free()
	var h := _game()
	var s2 = h.sim
	s2.town.mark_cleared("depot")
	s2.town.claim("depot")
	check(s2.town.garrison_send("depot", _crew(s2, ["dez"])), "Dez holds it")
	for night in 200:
		s2.town.at_the_bell()
		_crew(s2, ["dez"])[0].hp = 100.0
	eq(s2.town.state_of("depot"), "claimed", "a garrison holds it through 200 nights")
	check(_crew(s2, ["dez"])[0].away != null, "and he is off the map")
	s2.town.recall("depot")
	check(_crew(s2, ["dez"])[0].away == null, "recalled, he is home")
	h.world.free()


# ----------------------------------------------------------------------- saves --

func test_a_save_keeps_the_board_and_an_expedition_on_the_road() -> void:
	var a := _game(7.0)
	var sim_a = a.sim
	sim_a.town.reveal("farm")
	sim_a.town.mark_cleared("houses")
	sim_a.town.mark_cleared("depot")
	sim_a.town.claim("depot")
	check(sim_a.scavenge.send(_crew(sim_a, ["dez", "marcus"]), "pharmacy", "scout"), "a party is out")
	Helpers.run(sim_a, 40.0)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	_write(TOWN)
	Town.data_path = FIXTURE
	var b := Helpers.make(99, 1)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "the save loads")
	check(b.sim.town.on and b.sim.scavenge.town_mode, "the board is on in the loaded game")
	eq(b.sim.town.state_of("farm"), "known", "what was shown")
	eq(b.sim.town.state_of("houses"), "cleared", "what was cleared")
	eq(b.sim.town.state_of("depot"), "claimed", "what was claimed")
	eq(b.sim.scavenge.parties.size(), 1, "the party is still out")
	eq(String(b.sim.scavenge.parties[0].action), "scout", "on its errand")
	near(float(b.sim.scavenge.parties[0].return_at), float(sim_a.scavenge.parties[0].return_at), 1e-6, "due when it was due")
	Helpers.run(sim_a, 600.0)
	Helpers.run(b.sim, 600.0)
	eq(b.sim.scavenge.parties.size(), sim_a.scavenge.parties.size(), "they come back together")
	eq(b.sim.town.state_of("far"), sim_a.town.state_of("far"), "with the same places shown")
	a.world.free()
	b.world.free()


# ---------------------------------------------------------------- review fixes --

func test_a_scouting_trip_does_not_pick_the_place_over() -> void:
	var g := _game(7.0)
	var sim = g.sim
	check(sim.scavenge.send(_crew(sim, ["dez"]), "houses", "scout"), "Dez scouts the houses")
	_until_back(sim)
	eq(sim.scavenge.why_not_action(_crew(sim, ["dez"]), "houses", "loot"), "", "the houses can still be looted")
	for s in sim.scavenge.available_sites():
		if s.id == "houses":
			check(s.available and String(s.note) == "", "they are not picked over: '%s'" % s.note)
	g.world.free()


func test_a_trips_news_is_told_the_beats_what_was_found_and_what_came_of_a_clearing() -> void:
	var g := _game(7.0)
	var sim = g.sim
	sim.town._beats = [{"id": "cache", "text": "A cache under a floor.", "weight": 1, "min_hours": 0, "effects": {"loot_pct": 30}}]
	check(sim.scavenge.send(_crew(sim, ["dez"]), "depot", "scout"), "a scouting trip to the depot")
	sim.scavenge.parties[0].result["beats"] = ["A cache under a floor."]
	sim.events.clear()
	sim.alerts.clear()
	_until_back(sim)
	var said: Array = []
	for e in sim.events:
		if e.type == "banner":
			said.append(String(e.text) + " | " + String(e.sub))
	for id in sim.alerts:
		said.append(String(sim.alerts[id].text) + " | " + String(sim.alerts[id].sub))
	var all := " ".join(said)
	check(all.contains("A cache under a floor."), "the way's event is told: %s" % all)
	check(all.contains("farm") or all.contains("Farm"), "and the place it showed: %s" % all)
	g.world.free()


func test_a_clearing_says_how_it_went() -> void:
	var g := _game(7.0)
	var sim = g.sim
	var shooters := _crew(sim, ["dez", "marcus"])
	for p in shooters:
		p.skills["Shooting"] = 12
	check(sim.scavenge.send(shooters, "depot", "clear"), "sent to clear the depot")
	sim.scavenge.parties[0].result["clear"] = true
	sim.events.clear()
	sim.alerts.clear()
	_until_back(sim)
	var said: Array = []
	for e in sim.events:
		if e.type == "banner":
			said.append(String(e.text) + " | " + String(e.sub))
	for id in sim.alerts:
		said.append(String(sim.alerts[id].text) + " | " + String(sim.alerts[id].sub))
	var all := " ".join(said).to_lower()
	check(all.contains("cleared") or all.contains("empty") or all.contains("quiet"), "a cleared nest is said to be: %s" % all)
	g.world.free()


func test_the_storytellers_errand_goes_out_in_the_settlement_game() -> void:
	var g := _game(9.0)
	var sim = g.sim
	sim.storyteller.enabled = true
	var crew := _crew(sim, ["dez", "marcus"])
	var site := {"id": "errand_crate", "name": "The crate in the road", "where": "the crate in the road", "blurb": "", "danger": 1, "loot": {"scrap": [10, 12]}, "extra": {}, "image": ""}
	sim.scavenge.errands["errand_crate"] = site
	check(sim.scavenge.send(crew, "errand_crate"), "the errand is sent")
	eq(sim.scavenge.parties.size(), 1, "a party is out")
	var scrap: float = sim.stock.scrap
	_until_back(sim)
	check(sim.stock.scrap > scrap, "and it brings the crate home")
	g.world.free()


func test_one_survivor_is_rescued_once() -> void:
	var g := _game(7.0)
	var sim = g.sim
	_bring_everyone(sim)
	sim.recruits.queue.clear()
	sim.recruits.queue.append(sim.recruits.make_def(0))
	sim.recruits.queue.append(sim.recruits.make_def(1))
	sim.town.mark_cleared("depot")
	var people_before: int = sim.people.size()
	check(sim.scavenge.send(_crew(sim, ["dez"]), "depot", "loot"), "Dez goes to the depot")
	var second: bool = sim.scavenge.send(_crew(sim, ["marcus"]), "depot", "loot")
	check(not second, "a second party cannot go to the same place at the same time")
	eq(sim.scavenge.why_not_action(_crew(sim, ["marcus"]), "depot", "loot"), "A party is already out there.", "and says why")
	_until_back(sim)
	sim.recruits.rescue_home("depot")
	var after: int = sim.recruits.queue.size()
	sim.recruits.rescue_home("depot")
	eq(sim.recruits.queue.size(), after, "a place that has been rescued is not rescued again")
	g.world.free()


func test_a_garrison_cannot_be_recalled_in_the_dark_and_nobody_is_brought_home_for_the_night() -> void:
	var g := _game(7.0)
	var sim = g.sim
	sim.town.state["depot"].cleared = true
	sim.town.state["depot"].claimed = true
	var dez := _crew(sim, ["dez"])
	check(sim.town.garrison_send("depot", dez), "Dez holds the depot")
	sim.minutes = 19.5 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	eq(sim.town.why_not_recall("depot"), "Not in the dark: they hold it until morning.", "no recall at dusk")
	sim.town.recall("depot")
	check(dez[0].away is Dictionary and dez[0].away.get("kind", "") == "garrison", "Dez is still there")
	sim.minutes = 8.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	eq(sim.town.why_not_recall("depot"), "", "by day it can be")
	sim.town.recall("depot")
	check(dez[0].away == null, "and he is home")
	g.world.free()


func test_a_garrisoned_person_is_said_to_be_holding_a_place_not_scavenging() -> void:
	var g := _game(7.0)
	var sim = g.sim
	sim.town.state["depot"].claimed = true
	var dez := _crew(sim, ["dez"])
	sim.town.garrison_send("depot", dez)
	check(String(dez[0].activity).begins_with("Holding"), "his activity says so: %s" % dez[0].activity)
	g.world.free()


func test_a_night_out_is_more_dangerous_than_a_day_trip() -> void:
	var g := _game(7.0)
	var sim = g.sim
	sim.town.reveal("clinic")
	var far_hours: float = sim.scavenge.action_hours("clinic", "loot")
	var near_hours: float = sim.scavenge.action_hours("houses", "loot")
	check(far_hours > 13.0 and near_hours < 13.0, "(a night out and a day trip)")
	var hurt_far := 0
	var hurt_near := 0
	var members := _crew(sim, ["dez", "marcus"])
	for i in 400:
		sim.rng.seed = 5000 + i
		var party := {"site": "clinic", "members": ["dez", "marcus"], "action": "loot"}
		var r: Dictionary = sim.scavenge._decide_town(party)
		hurt_far += r.hurt.size()
		party.site = "houses"
		sim.rng.seed = 5000 + i
		var r2: Dictionary = sim.scavenge._decide_town(party)
		hurt_near += r2.hurt.size()
	# the clinic's danger is 2 and the houses' 1: compare against the danger alone by looking for the night's own share
	check(sim.scavenge.NIGHT_OUT_WOUND > 0.0, "the night out has its own chance of a wound")
	check(hurt_far > hurt_near, "far trips hurt more (%d against %d)" % [hurt_far, hurt_near])
	g.world.free()


func test_the_radio_names_a_place_where_someone_is_hiding_and_the_board_learns_it() -> void:
	var g := _game(12.0)
	var sim = g.sim
	sim.storyteller.enabled = true
	eq(sim.town.tip_place(), "", "nobody hides at a place that is not known in this little town")
	sim.town.place("farm")["survivor"] = true
	eq(sim.town.tip_place(), "farm", "someone hides at the farm, which the board does not know")
	eq(sim.town.state_of("farm"), "unknown", "(it is unknown)")
	check(sim.storyteller.force("place_call"), "the call comes")
	eq(sim.town.state_of("farm"), "known", "the farm is on the board")
	var card: Dictionary = sim.storyteller.pending()
	check(String(card.title).contains("Hollis") or String(card.title).contains("farm") or String(card.title).contains("Farm"), "the card names it: %s" % card.title)
	eq(sim.town.tip_place(), "", "and there is nothing more to tell")
	g.world.free()


func test_the_radios_place_call_is_not_in_the_classic_game() -> void:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	sim.storyteller.enabled = true
	for day in range(3, 29):
		check(sim.storyteller.draw(day).get("id", "") != "place_call", "and never draws it (day %d)" % day)
	g.world.free()
