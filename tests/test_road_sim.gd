extends "res://tests/case.gd"
## The simulation additions of round 21 (S21.1 EVENTS): scripts/sim/vehicles.gd `road_wear`, `wreck`, `fuel_per_leg` and
## scripts/sim/scavenge.gd `hold_on_road`, `amend_result`, `arrive_home`, `road_survivors`. Settlement game only; the dice and
## the old game do not change.

const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const FIXTURE := "user://test_r21_events_town.json"
const STEP := 1.0 / 30.0

## Home is at (50, 35). The houses are an hour away on foot; the garage holds a pickup; the city is across the river.
const TOWN := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [59, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
		{"id": "garage", "name": "The garage", "kind": "garage", "pos": [41, 35], "blurb": "Grease and a pickup.", "danger": 2, "known": true,
			"loot": {"scrap": [10, 20]}, "extra": {}, "vehicle": "pickup"},
		{"id": "city", "name": "The hospital", "kind": "hospital", "pos": [140, 35], "blurb": "Across the river.", "danger": 3, "known": true,
			"loot": {"meds": [20, 30]}, "extra": {}, "needs_vehicle": true},
	],
	"roads": [["home", "houses"], ["home", "garage"], ["home", "city"]],
	"beats": [],
}


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game (Ruth, Dez, Marcus) at `hour` of day 3 with the small town above, the waves off.
func _game(hour: float = 8.0) -> Dictionary:
	_write(TOWN)
	Town.data_path = FIXTURE
	var g := Helpers.make(17, 1, 3)
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


func _end(g: Dictionary) -> void:
	g.world.free()


## What a dice trip leaves behind, by a fixed seed: the numbers the additions must not move.
func _trace_dice() -> Dictionary:
	var g := _game(8.0)
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	sim.vehicles.fuel = 30.0
	var ok: bool = sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "houses", "loot", String(v.id))
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < 4000:
		Helpers.run(sim, 1.0)
		n += 1
	var out := {"ok": ok, "clock": snappedf(sim.clock_min, 0.001), "stock": sim.stock.duplicate(), "fuel": snappedf(sim.vehicles.fuel, 0.001), "hp": snappedf(float(sim.vehicles.vehicle(String(v.id)).hp), 0.001), "rng": str(sim.rng.state)}
	_end(g)
	return out


## What a played trip (the abstract road home) leaves behind.
func _trace_played() -> Dictionary:
	var g := _game(8.0)
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	sim.vehicles.fuel = 30.0
	var party: Dictionary = sim.scavenge.begin_played(_crew(sim, ["dez", "marcus"]), "houses", "loot", String(v.id))
	sim.scavenge.finish_played(party, {"loot": {"food": 14, "scrap": 6}, "hurt": {"dez": "scratch"}, "lost": [], "ammo_used": 3.0})
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < 4000:
		Helpers.run(sim, 1.0)
		n += 1
	var out := {"ok": not party.is_empty(), "clock": snappedf(sim.clock_min, 0.001), "stock": sim.stock.duplicate(), "fuel": snappedf(sim.vehicles.fuel, 0.001), "hp": snappedf(float(sim.vehicles.vehicle(String(v.id)).hp), 0.001), "rng": str(sim.rng.state)}
	_end(g)
	return out


## A played trip by pickup to the houses, finished in the place: the party is on the road home ("away").
func _on_the_road(sim, ids: Array = ["dez", "marcus"], vehicle: String = "pickup", played: Dictionary = {}) -> Dictionary:
	var vid := ""
	if vehicle != "":
		var v: Dictionary = sim.vehicles.add(vehicle)
		vid = String(v.id)
		sim.vehicles.fuel = 30.0
	var party: Dictionary = sim.scavenge.begin_played(_crew(sim, ids), "houses", "loot", vid)
	var result := {"loot": {"food": 14, "scrap": 6}, "hurt": {}, "lost": [], "ammo_used": 0.0}
	result.merge(played, true)
	sim.scavenge.finish_played(party, result)
	return party


func _until_home(sim, limit: int = 4000) -> void:
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < limit:
		Helpers.run(sim, 1.0)
		n += 1


## The party's states, in the order it went through them, until it is home.
func _states_until_home(sim, limit_steps: int = 120000) -> Array:
	var states: Array = []
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < limit_steps:
		var st := String(sim.scavenge.parties[0].state)
		if states.is_empty() or states[states.size() - 1] != st:
			states.append(st)
		sim.update(STEP)
		n += 1
	return states


# ----------------------------------------------------------- the dice are as they were --

func test_a_dice_trip_leaves_the_numbers_it_always_left() -> void:
	var t := _trace_dice()
	check(bool(t.ok), "the trip went")
	near(float(t.clock), 3156.0, 0.001, "the clock when it is home")
	near(float(t.fuel), 26.818, 0.001, "the fuel the trip burnt")
	near(float(t.hp), 85.0, 0.001, "the pickup's wear")
	eq(t.stock, {"ammo": 300.0, "food": 59.0, "meds": 10.0, "scrap": 60.0, "water": 67.0}, "what it brought")
	eq(String(t.rng), "2461460299140785399", "the dice thrown (the rules' random number stream)")


func test_a_played_trip_with_the_abstract_road_home_leaves_the_numbers_it_always_left() -> void:
	var t := _trace_played()
	check(bool(t.ok), "the trip began")
	near(float(t.clock), 2991.0, 0.001, "the clock when it is home")
	near(float(t.fuel), 26.818, 0.001, "the fuel")
	near(float(t.hp), 82.0, 0.001, "the pickup's wear")
	eq(t.stock, {"ammo": 297.0, "food": 54.0, "meds": 10.0, "scrap": 66.0, "water": 50.0}, "what it brought")
	eq(String(t.rng), "-2316917734999333153", "the dice thrown")


# ---------------------------------------------------------------------- vehicles --

func test_road_wear_takes_hp_and_never_goes_below_one() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	var id := String(v.id)
	check(sim.vehicles.road_wear(id, 10.0), "a knock the pickup survives")
	near(float(sim.vehicles.vehicle(id).hp), 80.0, 1e-9, "its hp is down by what it took")
	check(sim.vehicles.road_wear(id, 0.0), "nothing lost, nothing happens")
	near(float(sim.vehicles.vehicle(id).hp), 80.0, 1e-9, "(unchanged)")
	check(sim.vehicles.road_wear(id, 500.0), "a knock that takes it to the floor: it limps on")
	near(float(sim.vehicles.vehicle(id).hp), 1.0, 1e-9, "its hp stops at 1")
	check(not sim.vehicles.road_wear(id, 0.5), "at 1 every further knock says so: the caller wrecks it")
	near(float(sim.vehicles.vehicle(id).hp), 1.0, 1e-9, "(still 1)")
	check(sim.vehicles.road_wear("v99", 5.0), "a vehicle that is not there is nothing to wreck")
	eq(sim.vehicles.fleet.size(), 1, "road_wear itself never loses a vehicle")
	_end(g)


func test_wreck_loses_the_vehicle_and_says_where() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	var id := String(v.id)
	sim.vehicles.fuel = 30.0
	var party: Dictionary = sim.scavenge.begin_played(_crew(sim, ["dez", "marcus"]), "houses", "loot", id)
	sim.events.clear()
	sim.alerts.clear()
	sim.vehicles.wreck(id, "left on the road to the houses")
	eq(sim.vehicles.fleet.size(), 0, "the pickup is off the fleet")
	var lost := false
	for e in sim.events:
		if e.type == "vehicle" and String(e.id) == id and String(e.what) == "lost":
			lost = true
	check(lost, "a vehicle event says it is lost")
	check(sim.alerts.has("vehicle-%s" % id), "and an alert")
	if sim.alerts.has("vehicle-%s" % id):
		var a: Dictionary = sim.alerts["vehicle-%s" % id]
		check(String(a.text).to_lower().contains("pickup") and String(a.text).contains("lost"), "it names the pickup and says it is lost")
		check((String(a.text) + " " + String(a.sub)).contains("left on the road to the houses"), "and why: %s" % String(a.text))
	eq(String(party.get("vehicle", "x")), "", "the party it carried is on foot now")
	check(not party.has("seats") and not party.has("doors"), "with no seats or doors of the car")
	sim.vehicles.wreck(id, "twice")
	sim.vehicles.wreck("v99", "no such thing")
	eq(sim.events.size(), 1, "a second wreck, or one that is not there, says nothing")
	_end(g)


func test_a_party_whose_car_was_wrecked_walks_in_at_the_gate() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	sim.vehicles.fuel = 30.0
	var party: Dictionary = sim.scavenge.begin_played(_crew(sim, ["dez", "marcus"]), "houses", "loot", String(v.id))
	sim.vehicles.wreck(String(v.id), "left on the road")
	sim.scavenge.finish_played(party, {"loot": {"food": 14}})
	near(float(party.return_at) - float(sim.clock_min), 60.0, 1.0, "the road home is the whole way on foot")
	var states := _states_until_home(sim)
	eq(states, ["away"], "no car drives in")
	for p in _crew(sim, ["dez", "marcus"]):
		check(p.away == null and not p.dead, "%s is home" % p.first)
	eq(sim.vehicles.fleet.size(), 0, "and there is no pickup")
	_end(g)


func test_fuel_per_leg_is_half_of_the_trips_fuel_for_every_kind_and_place() -> void:
	var g := _game()
	var sim = g.sim
	for kind_id in sim.vehicles.kinds():
		var v: Dictionary = sim.vehicles.add(String(kind_id))
		for place in ["houses", "garage", "city"]:
			var whole: float = sim.vehicles.fuel_for(place, String(v.id))
			check(whole > 0.0, "%s to %s burns fuel" % [kind_id, place])
			near(float(sim.vehicles.fuel_per_leg(place, String(v.id))) * 2.0, whole, 1e-9, "%s to %s: two legs are the trip" % [kind_id, place])
			var burn := float(sim.vehicles.kind(String(kind_id)).burn)
			near(float(sim.vehicles.fuel_per_leg(place, String(v.id))), burn * float(sim.scavenge.road_minutes(place, String(v.id))) / 60.0, 1e-9, "%s to %s: burn x road_min / 60" % [kind_id, place])
	near(float(sim.vehicles.fuel_per_leg("houses", "v99")), 0.0, 1e-9, "no such vehicle: no fuel")
	_end(g)


# -------------------------------------------------------------------- the party --

func test_a_party_held_on_the_road_is_never_due() -> void:
	var g := _game()
	var sim = g.sim
	var party := _on_the_road(sim)
	check(not bool(party.get("road_live", false)), "(not held yet)")
	sim.scavenge.hold_on_road(party, true)
	check(bool(party.road_live), "held")
	Helpers.run(sim, 100.0)    # five hours: well past the abstract road's end
	eq(sim.scavenge.parties.size(), 1, "they are still out")
	eq(String(party.state), "away", "on the road")
	Helpers.run_to_hour(sim, 22.0)
	Helpers.run(sim, 30.0)
	eq(sim.scavenge.parties.size(), 1, "and through the night too")
	sim.scavenge.hold_on_road(party, false)
	check(not bool(party.get("road_live", false)), "let go")
	_end(g)


func test_a_party_let_go_of_comes_in_as_any_trip_does() -> void:
	var g := _game()
	var sim = g.sim
	var party := _on_the_road(sim)
	sim.scavenge.hold_on_road(party, true)
	Helpers.run(sim, 100.0)
	check(not sim.scavenge.parties.is_empty(), "held")
	sim.scavenge.hold_on_road(party, false)
	var states := _states_until_home(sim)
	eq(states, ["away", "driving_in", "unloading"], "the pickup drives in and they get out")
	_end(g)


func test_arrive_home_brings_a_party_in_at_night_at_once() -> void:
	var g := _game()
	var sim = g.sim
	var party := _on_the_road(sim)
	sim.scavenge.hold_on_road(party, true)
	Helpers.run_to_hour(sim, 21.0)
	eq(String(sim.phase), "night", "it is night")
	sim.scavenge.arrive_home(party)
	check(not bool(party.get("road_live", false)), "no longer held")
	check(bool(party.get("night_ok", false)), "the player brought them to the gate: night or not")
	check(float(party.return_at) <= float(sim.clock_min) + 1e-6, "they are due now")
	Helpers.run(sim, 0.2)
	eq(String(party.state), "driving_in", "the pickup drives in at once")
	var states := _states_until_home(sim)
	eq(states, ["driving_in", "unloading"], "and they get out")
	for p in _crew(sim, ["dez", "marcus"]):
		check(p.away == null, "%s is home" % p.first)
	_end(g)


func test_a_party_that_is_not_held_still_waits_for_day() -> void:
	var g := _game()
	var sim = g.sim
	var party: Dictionary = sim.scavenge.begin_played(_crew(sim, ["dez"]), "houses", "loot", "")
	Helpers.run_to_hour(sim, 22.0)
	sim.scavenge.finish_played(party, {"loot": {"food": 4}})
	Helpers.run(sim, 60.0)    # three hours of the dark
	check(not party.has("night_ok"), "no night pass without arrive_home")
	eq(sim.scavenge.parties.size(), 1, "they do not walk in through the night")
	_end(g)


func test_arrive_home_on_foot_puts_them_at_the_gate() -> void:
	var g := _game()
	var sim = g.sim
	var party := _on_the_road(sim, ["dez"], "")
	sim.scavenge.hold_on_road(party, true)
	Helpers.run_to_hour(sim, 21.0)
	sim.scavenge.arrive_home(party)
	Helpers.run(sim, 0.2)
	eq(sim.scavenge.parties.size(), 0, "home at once")
	var dez = _crew(sim, ["dez"])[0]
	check(dez.away == null and not dez.dead, "Dez is home")
	_end(g)


func test_road_live_is_not_saved_and_a_load_falls_back_to_the_abstract_return() -> void:
	var a := _game()
	var sim = a.sim
	var party := _on_the_road(sim)
	sim.scavenge.hold_on_road(party, true)
	Helpers.run(sim, 10.0)
	var entry: Dictionary = sim.scavenge.save().parties[0]
	check(not entry.has("road_live"), "the save has no road_live")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	_write(TOWN)
	Town.data_path = FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "it loads")
	var s2 = b.sim
	eq(s2.scavenge.parties.size(), 1, "the party is there")
	check(not bool(s2.scavenge.parties[0].get("road_live", false)), "and not held")
	var states := _states_until_home(s2)
	eq(states, ["away", "driving_in", "unloading"], "it comes in by the abstract clock")
	_end(a)
	_end(b)


func test_night_ok_is_saved_so_that_a_save_at_the_gate_still_comes_in() -> void:
	var a := _game()
	var sim = a.sim
	var party := _on_the_road(sim, ["dez"], "")
	sim.scavenge.hold_on_road(party, true)
	Helpers.run_to_hour(sim, 21.0)
	sim.scavenge.arrive_home(party)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	_write(TOWN)
	Town.data_path = FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "it loads")
	var s2 = b.sim
	check(bool(s2.scavenge.parties[0].get("night_ok", false)), "the night pass is kept")
	Helpers.run(s2, 0.2)
	eq(s2.scavenge.parties.size(), 0, "and they come in")
	_end(a)
	_end(b)


# ------------------------------------------------------------------ amend_result --

func test_amend_result_merges_what_the_road_home_found() -> void:
	var g := _game()
	var sim = g.sim
	var party := _on_the_road(sim, ["dez", "marcus"], "pickup", {"hurt": {"dez": "scratch"}})
	sim.scavenge.amend_result(party, {"hurt": {"marcus": "scratch"}, "lost": [], "loot": {"food": 5, "meds": 2}})
	eq(int(party.result.loot.food), 19, "the road's food is added to the place's")
	eq(int(party.result.loot.scrap), 6, "the rest is as it was")
	eq(int(party.result.loot.meds), 2, "a new stock is added")
	eq(String(party.result.hurt.dez), "scratch", "Dez as the place left him")
	eq(String(party.result.hurt.marcus), "scratch", "and Marcus hurt on the road")
	sim.scavenge.amend_result(party, {"hurt": {"dez": "bite"}})
	eq(String(party.result.hurt.dez), "bite", "a bite is worse than a scratch")
	sim.scavenge.amend_result(party, {"hurt": {"dez": "scratch"}})
	eq(String(party.result.hurt.dez), "bite", "and a scratch does not make a bite better")
	_end(g)


func test_amend_result_is_sanitised_as_a_played_result_is() -> void:
	var g := _game()
	var sim = g.sim
	var party := _on_the_road(sim, ["dez", "marcus"])
	sim.scavenge.amend_result(party, {
		"hurt": {"ghost": "bite", "dez": "something odd"},
		"lost": ["ghost", "marcus", "marcus"],
		"loot": {"gold": 50, "scrap": 99999, "water": -5, "ammo": 0, "fuel": 3},
	})
	check(not party.result.hurt.has("ghost"), "a name that is not a member's is dropped")
	eq(String(party.result.hurt.dez), "bite", "a hurt that is not a scratch is a bite (as the place's are)")
	eq(party.result.lost, ["marcus"], "a loss is a member's, once")
	check(not party.result.loot.has("gold"), "a stock that does not exist is dropped")
	eq(int(party.result.loot.scrap), 400, "a forged amount is capped as the place's are (%d)" % 400)
	check(not party.result.loot.has("water") and not party.result.loot.has("ammo"), "nothing negative or empty")
	eq(int(party.result.loot.fuel), 3, "fuel is a stock too")
	sim.scavenge.amend_result(party, {})
	sim.scavenge.amend_result({}, {"loot": {"food": 3}})
	sim.scavenge.amend_result({"kind": "party", "n": 77, "members": [], "result": {}}, {"loot": {"food": 3}})
	eq(party.result.lost, ["marcus"], "an empty amend, or one for no party, changes nothing")
	_end(g)


func test_amend_result_ignores_a_dice_trip() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.scavenge.send(_crew(sim, ["dez"]), "houses", "loot", ""), "(a dice trip)")
	var dice: Dictionary = sim.scavenge.parties[0]
	var before: Dictionary = dice.result.duplicate(true)
	sim.scavenge.amend_result(dice, {"loot": {"food": 50}, "lost": ["dez"]})
	eq(dice.result, before, "the dice's party is not amended")
	_end(g)


func test_a_person_lost_on_the_road_home_is_dead_when_they_get_in() -> void:
	var g := _game()
	var sim = g.sim
	var party := _on_the_road(sim, ["dez", "marcus"])
	sim.scavenge.hold_on_road(party, true)
	sim.scavenge.amend_result(party, {"lost": ["marcus"], "loot": {"food": 4}})
	var marcus = _crew(sim, ["marcus"])[0]
	check(not marcus.dead, "nobody knows yet")
	var food: float = sim.stock.food
	sim.scavenge.arrive_home(party)
	_until_home(sim, 200)
	check(marcus.dead, "Marcus did not come back")
	check(not _crew(sim, ["dez"])[0].dead, "Dez did")
	near(float(sim.stock.food), food + 14.0 + 4.0, 1e-6, "with the place's food and the road's")
	_end(g)


func test_amend_result_puts_the_healths_in_as_the_finish_does() -> void:
	var g := _game()
	var sim = g.sim
	var party := _on_the_road(sim, ["dez", "marcus"])
	sim.scavenge.amend_result(party, {"hp": {"dez": 33.0, "marcus": 500.0, "ghost": 5.0}})
	near(float(_crew(sim, ["dez"])[0].hp), 33.0, 1e-9, "Dez's health as the road left it")
	near(float(_crew(sim, ["marcus"])[0].hp), 100.0, 1e-9, "never past the top")
	_end(g)


# ------------------------------------------------------------------ road survivors --

func test_road_survivors_survive_the_copy_and_the_save() -> void:
	var a := _game()
	var sim = a.sim
	var party := _on_the_road(sim, ["dez"], "pickup", {"road_survivors": 1})
	eq(int(party.result.get("road_survivors", 0)), 1, "the finish keeps the count")
	sim.scavenge.amend_result(party, {"road_survivors": 1})
	eq(int(party.result.road_survivors), 2, "and the road home adds to it")
	var copy: Dictionary = sim.scavenge._copy_result({"loot": {}, "hurt": {}, "lost": [], "road_survivors": 3.0})
	eq(int(copy.road_survivors), 3, "_copy_result keeps it as a whole number")
	check(not sim.scavenge._copy_result({"loot": {}, "hurt": {}, "lost": []}).has("road_survivors"), "and adds none")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	_write(TOWN)
	Town.data_path = FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "it loads")
	eq(int(b.sim.scavenge.parties[0].result.get("road_survivors", 0)), 2, "the save keeps it")
	_end(a)
	_end(b)


func test_survivors_met_on_the_road_join_the_crew_when_the_party_gets_in() -> void:
	var g := _game()
	var sim = g.sim
	var before: int = sim.recruits.crew_size()
	var queued: int = sim.recruits.queue.size()
	var party := _on_the_road(sim, ["dez"], "pickup", {"road_survivors": 2})
	_until_home(sim, 200)
	eq(sim.recruits.crew_size(), before + 2, "two joined the crew")
	eq(sim.recruits.queue.size(), queued - 2, "from the queue of callers")
	var told := false
	for e in sim.events:
		if e.type == "arrived":
			told = true
	check(told, "an arrival is told as ever")
	_end(g)


func test_a_survivor_with_no_bed_stays_a_caller_and_the_alert_says_so() -> void:
	var g := _game()
	var sim = g.sim
	# fill the beds: six beds, three people; three more come
	while sim.recruits.housing_free() > 1:
		sim.add_person(sim.recruits.make_def(sim.recruits.generated))
		sim.recruits.generated += 1
	eq(sim.recruits.housing_free(), 1, "one bed left")
	var caller := String(sim.recruits.current_caller().get("name", ""))
	var queued: int = sim.recruits.queue.size()
	var before: int = sim.recruits.crew_size()
	sim.alerts.clear()
	_on_the_road(sim, ["dez"], "pickup", {"road_survivors": 2})
	_until_home(sim, 200)
	eq(sim.recruits.crew_size(), before + 1, "one fits")
	eq(sim.recruits.queue.size(), queued - 1, "and one stays a caller")
	check(String(sim.recruits.current_caller().get("name", "")) != caller or queued == 1, "(the next one is the caller)")
	var said := false
	for id in sim.alerts:
		if String(sim.alerts[id].text).to_lower().contains("road") or String(sim.alerts[id].sub).to_lower().contains("bed"):
			said = true
	check(said, "an alert says there was no bed for the other")
	_end(g)


func test_road_survivors_are_the_news_of_the_trip() -> void:
	var g := _game()
	var sim = g.sim
	_on_the_road(sim, ["dez"], "pickup", {"road_survivors": 1})
	var banner := ""
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < 300:
		Helpers.run(sim, 1.0)
		n += 1
	for e in sim.events:
		if e.type == "banner" and String(e.text).begins_with("Back from"):
			banner = String(e.sub)
	check(banner.to_lower().contains("road"), "the report line says someone joined on the road: '%s'" % banner)
	_end(g)
