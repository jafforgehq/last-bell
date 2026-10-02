extends "res://tests/case.gd"
## Vehicles and fuel (round 13, scripts/sim/vehicles.gd and the vehicle parameter of scavenge.gd): fuel as loot and a
## store of its own, a vehicle found by looting its place, trips by vehicle (hours, fuel, seats, cargo, wear, loss),
## a place that cannot be reached on foot, saves. Settlement game only; the classic start has none of it.

const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const Vehicles := preload("res://scripts/sim/vehicles.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const FIXTURE := "user://test_vehicles_town.json"

## Home is at (50, 35). The houses are near; the garage holds a pickup; the gas station has fuel; the city is far and
## cannot be reached on foot.
const TOWN := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [59, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
		{"id": "garage", "name": "The garage", "kind": "garage", "pos": [41, 35], "blurb": "Grease and a pickup.", "danger": 2, "known": true,
			"loot": {"scrap": [10, 20]}, "extra": {}, "vehicle": "pickup"},
		{"id": "gas", "name": "The fuel stop", "kind": "gas_station", "pos": [50, 44], "blurb": "Pumps.", "danger": 1, "known": true,
			"loot": {"fuel": [20, 30]}, "extra": {}},
		{"id": "city", "name": "The hospital", "kind": "hospital", "pos": [140, 35], "blurb": "Across the river.", "danger": 3, "known": true,
			"loot": {"meds": [20, 30]}, "extra": {}, "needs_vehicle": true},
	],
	"roads": [["home", "houses"], ["home", "garage"], ["home", "gas"], ["home", "city"]],
	"beats": [],
}


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _game(hour: float = 7.0) -> Dictionary:
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


func _until_back(sim, limit: int = 2000) -> void:
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < limit:
		Helpers.run(sim, 1.0)
		n += 1


func test_the_classic_start_has_no_fleet() -> void:
	var g := Helpers.make(7, 1)
	eq(g.sim.vehicles.fleet.size(), 0, "no vehicles")
	near(g.sim.vehicles.fuel, 0.0, 0.0, "no fuel")
	g.world.free()


func test_the_kinds_are_sound() -> void:
	var g := _game()
	var kinds: Dictionary = g.sim.vehicles.kinds()
	eq(kinds.size(), 4, "four kinds")
	for id in kinds:
		var k: Dictionary = kinds[id]
		check(int(k.seats) >= 2 and int(k.seats) <= 8, "%s: seats" % id)
		check(float(k.speed) > 1.2 and float(k.speed) <= 3.0, "%s: faster than walking" % id)
		check(float(k.burn) > 0.0 and float(k.cargo) >= 1.0 and float(k.hp) > 0.0, "%s: burn, cargo, hp" % id)
		check(FileAccess.file_exists("res://assets/objects/%s.png" % String(k.art)), "%s: its picture exists" % id)
	g.world.free()


func test_fuel_is_found_as_loot_and_kept_in_its_own_tank_up_to_the_cap() -> void:
	var g := _game()
	var sim = g.sim
	var stocks_before: Dictionary = sim.stock.duplicate()
	check(sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "gas", "loot"), "to the fuel stop")
	_until_back(sim)
	check(sim.vehicles.fuel > 0.0, "fuel is in the tank: %.0f" % sim.vehicles.fuel)
	eq(sim.stock.has("fuel"), false, "and not among the stores")
	eq(sim.stock.size(), stocks_before.size(), "(the five stocks are the five stocks)")
	sim.vehicles.fuel = Vehicles.FUEL_CAP - 5.0
	near(sim.vehicles.add_fuel(30.0), 5.0, 0.0001, "the tank takes only what it can hold")
	near(sim.vehicles.fuel, Vehicles.FUEL_CAP, 0.0001, "and is full")
	g.world.free()


func test_a_vehicle_is_found_by_looting_its_place_and_only_once() -> void:
	var g := _game()
	var sim = g.sim
	var crew := _crew(sim, ["dez", "marcus"])
	for p in crew:
		p.skills["Building"] = 10
	check(sim.scavenge.send(crew, "garage", "loot"), "to the garage")
	sim.scavenge.parties[0].result["vehicle"] = "pickup"
	sim.scavenge.parties[0].result.hurt.clear()    # (nobody hurt: they can go again)
	sim.scavenge.parties[0].result.lost.clear()
	_until_back(sim)
	eq(sim.vehicles.fleet.size(), 1, "a vehicle is home")
	eq(String(sim.vehicles.fleet[0].kind), "pickup", "the pickup")
	eq(String(sim.vehicles.fleet[0].state), "parked", "parked")
	check(bool(sim.town.state["garage"].get("vehicle_taken", false)), "the garage is empty of it now")
	# a second party that is told it found one gets nothing more
	sim.scavenge.raids.clear()
	sim.minutes = 7.0 * 60.0    # (the next morning)
	sim.phase = sim.phase_at(sim.minutes)
	check(sim.scavenge.send(crew, "garage", "loot"), "to the garage again")
	sim.scavenge.parties[0].result["vehicle"] = "pickup"
	_until_back(sim)
	eq(sim.vehicles.fleet.size(), 1, "still one")
	g.world.free()


func test_the_chance_of_getting_a_vehicle_running_grows_with_building() -> void:
	near(Vehicles.start_chance(0.0), 0.5, 0.0001, "half")
	near(Vehicles.start_chance(4.0), 0.7, 0.0001, "more with Building")
	near(Vehicles.start_chance(100.0), 0.95, 0.0001, "never certain")


func test_a_trip_by_vehicle_takes_the_hours_the_fuel_and_the_seats_the_data_says() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	var on_foot: float = sim.scavenge.action_hours("houses", "loot")
	var by_car: float = sim.scavenge.action_hours("houses", "loot", String(v.id))
	var h: float = sim.town.hours_to("houses")
	near(on_foot, 2.0 * h + Town.SEARCH_H, 1e-9, "on foot: there, the search, back")
	near(by_car, 2.0 * h / 2.4 + Town.SEARCH_H, 1e-9, "by sedan the road is 2.4 times quicker")
	var burn: float = sim.vehicles.fuel_for("houses", String(v.id))
	near(burn, 3.0 * 2.0 * h / 2.4, 1e-9, "it burns 3 fuel for each hour driven")
	var crew := _crew(sim, ["ruth", "dez", "marcus"])
	check(sim.scavenge.send(crew, "houses", "loot", String(v.id)), "three go in the sedan")
	near(sim.vehicles.fuel, 30.0 - burn, 1e-9, "the fuel is burnt")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "out", "the sedan is out")
	near(float(sim.scavenge.parties[0].return_at), float(sim.scavenge.parties[0].depart) + by_car * 60.0, 1.5, "and they are due when the hours say")
	_until_back(sim)
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "it is home, parked")
	g.world.free()


func test_more_people_than_the_seats_or_the_fuel_allows_is_refused_with_the_reason() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var four := _crew(sim, ["ruth", "dez", "marcus"])
	# (only three people at the start: a fourth is added)
	for def in sim.recruits.queue.duplicate():
		sim.add_person(def)
		break
	sim.recruits.queue.clear()
	var all: Array = sim.people.duplicate()
	eq(all.size(), 4, "four people")
	sim.vehicles.fuel = 30.0
	eq(sim.scavenge.why_not_action(all, "houses", "loot", String(v.id)), "The sedan seats 3.", "the sedan seats three")
	check(not sim.scavenge.send(all, "houses", "loot", String(v.id)), "so it does not go")
	var bus: Dictionary = sim.vehicles.add("bus")
	check(sim.scavenge.send(all, "houses", "loot", String(bus.id)), "the bus takes all four (more than a party on foot)")
	_until_back(sim)
	check(not sim.scavenge.send(all, "houses", "loot"), "on foot four is too many")
	sim.vehicles.fuel = 0.0
	check(sim.scavenge.why_not_action(four, "houses", "loot", String(v.id)).contains("fuel"), "no fuel: %s" % sim.scavenge.why_not_action(four, "houses", "loot", String(v.id)))
	g.world.free()


func test_a_far_place_is_refused_on_foot_and_open_by_vehicle() -> void:
	var g := _game()
	var sim = g.sim
	var crew := _crew(sim, ["dez", "marcus"])
	eq(sim.scavenge.why_not_action(crew, "city", "loot"), "Too far to go on foot: take a vehicle.", "not on foot")
	check(not sim.scavenge.send(crew, "city", "loot"), "and it does not go")
	var v: Dictionary = sim.vehicles.add("van")
	sim.vehicles.fuel = 60.0
	eq(sim.scavenge.why_not_action(crew, "city", "loot", String(v.id)), "", "by van it can")
	var meds: float = sim.stock.meds
	check(sim.scavenge.send(crew, "city", "loot", String(v.id)), "the van goes")
	_until_back(sim)
	check(sim.stock.meds > meds, "with medicine from the hospital")
	g.world.free()


func test_a_vehicle_carries_more_loot_and_is_worn_by_the_place() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	var members: Array = ["dez", "marcus"]
	var plain := 0
	var carried := 0
	for i in 300:
		sim.rng.seed = 900 + i
		plain += int(sim.scavenge._decide_town({"site": "houses", "members": members, "action": "loot"}).loot.get("food", 0))
		sim.rng.seed = 900 + i
		carried += int(sim.scavenge._decide_town({"site": "houses", "members": members, "action": "loot", "vehicle": String(v.id)}).loot.get("food", 0))
	check(float(carried) > float(plain) * 1.5 and float(carried) < float(plain) * 1.9, "a pickup carries about 1.7 times: %d against %d" % [carried, plain])
	# wear: a danger-2 trip with one wounded
	sim.vehicles.come_home(String(v.id), 2, 1, false)
	near(float(sim.vehicles.vehicle(String(v.id)).hp), 90.0 - 10.0 - 3.0, 0.0001, "the place's danger and the wounded wear it")
	g.world.free()


func test_a_vehicle_is_lost_when_its_party_is_or_when_it_is_worn_out() -> void:
	var g := _game()
	var sim = g.sim
	var a: Dictionary = sim.vehicles.add("sedan")
	a["state"] = "out"
	sim.vehicles.come_home(String(a.id), 1, 0, true)
	eq(sim.vehicles.fleet.size(), 0, "a party lost: the sedan is lost")
	var b: Dictionary = sim.vehicles.add("sedan")
	b["state"] = "out"
	b["hp"] = 6.0
	sim.vehicles.come_home(String(b.id), 2, 0, false)
	eq(sim.vehicles.fleet.size(), 0, "worn out: gone")
	check(sim.alerts.size() > 0, "and the player is told")
	g.world.free()


func test_the_fleet_the_fuel_and_a_trip_in_a_vehicle_are_saved() -> void:
	var a := _game()
	var sim = a.sim
	var v: Dictionary = sim.vehicles.add("van")
	sim.vehicles.fuel = 33.0
	check(sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "houses", "loot", String(v.id)), "out in the van")
	var fuel_left: float = sim.vehicles.fuel
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	_write(TOWN)
	Town.data_path = FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "it loads")
	eq(b.sim.vehicles.fleet.size(), 1, "the fleet is kept")
	eq(String(b.sim.vehicles.fleet[0].state), "out", "out")
	near(b.sim.vehicles.fuel, fuel_left, 1e-9, "the fuel is kept")
	eq(String(b.sim.scavenge.parties[0].get("vehicle", "")), String(v.id), "the party knows its vehicle")
	_until_back(b.sim)
	eq(String(b.sim.vehicles.fleet[0].state), "parked", "it comes home after the load")
	a.world.free()
	b.world.free()


func test_a_played_trips_result_stands_where_the_dice_would_and_costs_the_ammo_it_used() -> void:
	var g := _game()
	var sim = g.sim
	var crew := _crew(sim, ["dez", "marcus"])
	var ammo_before: float = sim.stock.ammo
	var food_before: float = sim.stock.food
	var played := {"loot": {"food": 14, "scrap": 6}, "hurt": {"marcus": "bite"}, "lost": [], "clear": true, "ammo_used": 40.0, "beats": ["Dez opened the cabinet."]}
	check(not sim.scavenge.send_played(crew, "houses", "scout", "", played), "a scout is not played")
	check(sim.scavenge.send_played(crew, "houses", "loot", "", played), "the party goes with the played result")
	near(sim.stock.ammo, ammo_before - 40.0, 0.001, "the ammo they used is gone")
	check(bool(sim.scavenge.parties[0].get("played", false)), "the party is marked as played")
	_until_back(sim)
	check(sim.stock.food > food_before + 10.0, "the food they brought is in the stores (less the meals eaten meanwhile): %.1f from %.1f" % [sim.stock.food, food_before])
	eq(sim.town.state_of("houses"), "cleared", "the place is cleared")
	g.world.free()


func test_a_place_with_nothing_to_take_offers_no_loot_and_a_far_one_cannot_be_garrisoned() -> void:
	var g := _game()
	var sim = g.sim
	sim.town.place("houses")["loot"] = {}
	sim.town.place("houses")["extra"] = {}
	sim.scavenge.use_town()
	var offered := {}
	for s in sim.scavenge.available_sites():
		offered[String(s.id)] = s
	check(not (offered["houses"].actions as Array).has("loot"), "no loot to be had: no Go")
	eq(sim.scavenge.why_not_action(_crew(sim, ["dez"]), "houses", "loot"), "There is nothing here to take.", "and it says why")
	check(bool(offered["city"].needs_vehicle), "the board is told a place needs a vehicle")
	sim.town.state["city"].cleared = true
	sim.town.state["city"].claimed = true
	check(not sim.town.garrison_send("city", _crew(sim, ["dez"])), "nobody can garrison a place across the river by walking there")
	g.world.free()


func test_a_played_result_stands_when_someone_is_let_go_and_a_trip_called_off_gives_the_vehicle_back() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	var crew := _crew(sim, ["dez", "marcus"])
	var played := {"loot": {"food": 14}, "hurt": {}, "lost": ["marcus"], "clear": true, "ammo_used": 10.0, "beats": []}
	# on foot (a played trip by vehicle is away at once: the raid screen was the way out): Dez is ordered about before the
	# gate and the played result is not thrown away for a dice roll
	check(sim.scavenge.send_played(crew, "houses", "loot", "", played), "the played party goes")
	crew[0].order = {"x": 30.0, "y": 30.0, "z": 0.0}
	Helpers.run(sim, 1.0)
	var party: Dictionary = sim.scavenge.parties[0] if not sim.scavenge.parties.is_empty() else {}
	check(not party.is_empty(), "the party is still out")
	check(not party.members.has("dez"), "Dez is let go")
	check(party.result.lost.has("marcus"), "Marcus is still lost: the result stands")
	eq(int(party.result.loot.get("food", 0)), 14, "the played loot is what it was")
	# a trip that never leaves gives the vehicle and the fuel back
	var a = sim.vehicles.vehicle(String(v.id))
	sim.vehicles.take(String(v.id), "houses")
	eq(String(a.state), "out", "out")
	var fuel_left: float = sim.vehicles.fuel
	check(fuel_left < 30.0, "with the fuel burnt")
	sim.scavenge._call_off({"vehicle": String(v.id), "site": "houses", "n": 9})
	eq(String(a.state), "parked", "parked again")
	near(sim.vehicles.fuel, 30.0, 0.0001, "the fuel is given back")
	g.world.free()


func test_a_played_trip_by_vehicle_is_away_at_once_and_burns_the_fuel() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	var played := {"loot": {"food": 14}, "hurt": {}, "lost": [], "clear": true, "ammo_used": 0.0, "beats": []}
	check(sim.scavenge.send_played(_crew(sim, ["dez", "marcus"]), "houses", "loot", String(v.id), played), "the played party goes by sedan")
	check(30.0 - sim.vehicles.fuel > 0.0, "fuel was burnt")
	eq(String(sim.scavenge.parties[0].state), "away", "away at once: the raid screen was the way out")
	for p in _crew(sim, ["dez", "marcus"]):
		check(p.away != null, "%s is off the map" % p.first)
	_until_back(sim)
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the sedan is home")
	g.world.free()


func test_a_forged_played_result_is_cut_down_to_what_the_party_could_have_brought() -> void:
	var g := _game()
	var sim = g.sim
	var crew := _crew(sim, ["dez"])
	var ammo: float = sim.stock.ammo
	var forged := {"loot": {"food": 99999, "bogus": 5}, "hurt": {"nobody": "bite"}, "lost": ["ghost"], "ammo_used": -500.0}
	check(sim.scavenge.send_played(crew, "houses", "loot", "", forged), "it goes")
	var r: Dictionary = sim.scavenge.parties[0].result
	eq(int(r.loot.food), 400, "the loot is capped")
	check(not r.loot.has("bogus") and r.hurt.is_empty() and r.lost.is_empty(), "names that are not the party's and stocks that are not stocks are dropped")
	check(sim.stock.ammo <= ammo, "no ammo is made by a negative number")
	g.world.free()


func test_a_vehicle_taken_from_a_place_stays_taken_through_a_save() -> void:
	var a := _game()
	var sim = a.sim
	sim.town.state["garage"]["vehicle_taken"] = true
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	_write(TOWN)
	Town.data_path = FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "it loads")
	check(bool(b.sim.town.state["garage"].get("vehicle_taken", false)), "the garage is still empty of its pickup")
	for s in b.sim.scavenge.available_sites():
		if s.id == "garage":
			eq(String(s.vehicle_here), "", "and the board does not offer it again")
	a.world.free()
	b.world.free()


func test_fuel_that_does_not_fit_the_tank_is_said_and_a_full_tank_is_not_reported_as_zero() -> void:
	var g := _game()
	var sim = g.sim
	sim.vehicles.fuel = Vehicles.FUEL_CAP
	check(sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "gas", "loot"), "to the fuel stop with a full tank")
	sim.alerts.clear()
	sim.events.clear()
	_until_back(sim)
	check(sim.alerts.has("tank-full"), "the player is told the tank was full")
	var said := ""
	for e in sim.events:
		if e.type == "banner":
			said += String(e.sub)
	check(not said.contains("0 fuel"), "and the report does not say '0 fuel': %s" % said)
	g.world.free()


func test_a_party_that_never_left_and_comes_due_does_not_lose_its_vehicle() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	check(sim.scavenge.send(_crew(sim, ["dez"]), "houses", "loot", String(v.id)), "out in the sedan")
	var party: Dictionary = sim.scavenge.parties[0]
	party.members.clear()    # (nobody is left in it, nobody went through)
	sim.scavenge._come_back(party)
	check(sim.vehicles.fleet.size() == 1, "the sedan is not lost: %s" % str(sim.vehicles.fleet))
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "it is parked")
	g.world.free()


func test_a_failed_played_clear_does_not_bring_a_vehicle_home_but_a_good_one_may() -> void:
	var g := _game()
	var sim = g.sim
	var crew := _crew(sim, ["dez", "marcus"])
	for p in crew:
		p.skills["Building"] = 10
	check(sim.scavenge.send_played(crew, "garage", "clear", "", {"loot": {}, "hurt": {}, "lost": [], "clear": false}), "a played clear that failed")
	check(not sim.scavenge.parties[0].result.has("vehicle"), "no vehicle comes of it")
	g.world.free()
