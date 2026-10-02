extends "res://tests/case.gd"
## A trip by vehicle, seen from the rules (round 15, scripts/sim/scavenge.gd, vehicles.gd, convoy.gd): the people walk to the
## doors of the car, a door opens for each, the car drives out ("driving_out"), the trip's hours go by ("away"), the car
## drives in ("driving_in") and they get out one by one ("unloading"), and then the trip is told as ever. The sim never moves
## the car: its place is `drive_t / drive_len` along the route. A trip on foot is as it was. Settlement game only.

const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const Vehicles := preload("res://scripts/sim/vehicles.gd")
const Convoy := preload("res://scripts/sim/convoy.gd")
const Scavenge := preload("res://scripts/sim/scavenge.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const TOWN_FIXTURE := "user://test_trips_town.json"
const VEHICLES_FIXTURE := "user://test_trips_vehicles.json"
const STEP := 1.0 / 30.0

## Home is at (50, 35); the houses are near.
const TOWN := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [59, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
		{"id": "garage", "name": "The garage", "kind": "garage", "pos": [41, 35], "blurb": "Grease and a pickup.", "danger": 2, "known": true,
			"loot": {"scrap": [10, 20]}, "extra": {}, "vehicle": "pickup"},
	],
	"roads": [["home", "houses"], ["home", "garage"]],
	"beats": [],
}

## The four kinds with no doors in them: the side rule is what the rules fall back on.
const PLAIN_KINDS := {"version": 1, "kinds": {
	"sedan": {"name": "Sedan", "seats": 3, "speed": 2.4, "burn": 3.0, "cargo": 1.2, "hp": 70, "art": "174_car_s0", "w": 2.2, "h": 4.4},
	"pickup": {"name": "Pickup", "seats": 2, "speed": 2.2, "burn": 3.5, "cargo": 1.7, "hp": 90, "art": "116_pickup", "w": 2.2, "h": 4.15},
	"van": {"name": "Van", "seats": 4, "speed": 2.2, "burn": 4.0, "cargo": 1.5, "hp": 80, "art": "207_pickup", "w": 2.2, "h": 4.07},
	"bus": {"name": "Bus", "seats": 6, "speed": 1.8, "burn": 6.0, "cargo": 1.4, "hp": 100, "art": "175_bus_s0", "w": 2.6, "h": 8.07},
}}


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game at 07:00 of day 3 with the small town above, and `kinds` (a vehicles file) if given.
func _game(kinds: Dictionary = {}, fresh_seed: int = 17) -> Dictionary:
	_write(TOWN_FIXTURE, TOWN)
	Town.data_path = TOWN_FIXTURE
	if not kinds.is_empty():
		_write(VEHICLES_FIXTURE, kinds)
		Vehicles._cache.erase(VEHICLES_FIXTURE)    # (an earlier test may have read another file by this name)
		Vehicles.data_path = VEHICLES_FIXTURE
		Convoy.vehicles_path = VEHICLES_FIXTURE
		Convoy.forget()
	var g := Helpers.make(fresh_seed, 1, 3)
	Town.data_path = Town.DATA_PATH
	Vehicles.data_path = Vehicles.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	sim.minutes = 7.0 * 60.0
	sim.clock_min = 2.0 * 1440.0 + 7.0 * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.supplies.sources_day = 3
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.events.clear()
	sim.vehicles.fuel = 60.0
	return g


func _end(g: Dictionary) -> void:
	Vehicles.data_path = Vehicles.DATA_PATH
	Convoy.vehicles_path = Convoy.VEHICLES_PATH
	Convoy.forget()
	g.world.free()


func _crew(sim, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		for p in sim.people:
			if p.id == id:
				out.append(p)
	return out


## Everyone there is: the three of the start and the three who come over the radio.
func _full_crew(sim) -> Array:
	for def in sim.recruits.queue.duplicate():
		sim.add_person(def)
	sim.recruits.queue.clear()
	var out: Array = []
	for p in sim.people:
		out.append(p)
	return out


func _go(sim, steps: int) -> void:
	for i in steps:
		sim.update(STEP)


## Steps until `cond` holds; the number of steps it took, or -1 if it never did within `limit`.
func _until(sim, cond: Callable, limit: int = 20000) -> int:
	var n := 0
	while not cond.call() and n < limit:
		sim.update(STEP)
		n += 1
	return n if cond.call() else -1


func _party(sim) -> Dictionary:
	return sim.scavenge.parties[0] if not sim.scavenge.parties.is_empty() else {}


func _state(sim) -> String:
	return String(_party(sim).get("state", "done"))


## The place where a member of the party stands to use their door.
func _door_spot_of(sim, party: Dictionary, id: String) -> Vector2:
	var v: Dictionary = sim.vehicles.vehicle(String(party.vehicle))
	var seat := int(party.seats[id])
	return Convoy.door_spot(int(v.spot), String(v.kind), sim.vehicles.seat_door(String(v.kind), seat, int(v.spot)))


## Puts everyone of the party where their door is, still, so that a test need not wait for the walk.
func _at_doors(sim, party: Dictionary) -> void:
	for id in party.members:
		for p in sim.people:
			if p.id == id:
				var at := _door_spot_of(sim, party, String(id))
				p.x = at.x
				p.y = at.y
				p.moving = false
				p.path = []
				p.goal_key = ""


## Sends the crew in the vehicle to the houses with the dice's result and returns the party.
func _send(sim, ids: Array, vehicle_id: String) -> Dictionary:
	check(sim.scavenge.send(_crew(sim, ids), "houses", "loot", vehicle_id), "the party goes")
	return _party(sim)


## Runs the whole trip and says what happened: {"states": the states in order, "events": the events of the trip,
## "seconds": steps used}. The people are put at their doors at once.
func _run_trip(sim, quick: bool = true) -> Dictionary:
	var states: Array = []
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < 60000:
		var party := _party(sim)
		var st := String(party.state)
		if states.is_empty() or states[states.size() - 1] != st:
			states.append(st)
			if st == "out" and quick:
				_at_doors(sim, party)
		sim.update(STEP)
		n += 1
	return {"states": states, "events": sim.events.duplicate(), "steps": n}


func _events(list: Array, type: String) -> Array:
	var out: Array = []
	for e in list:
		if String(e.type) == type:
			out.append(e)
	return out


# ----------------------------------------------------------------- seats and doors --

func test_a_seat_has_a_door_by_the_side_rule_when_the_data_has_none() -> void:
	var g := _game(PLAIN_KINDS)
	var v = g.sim.vehicles
	eq(v.door_ids("sedan"), ["L1", "R1", "L2", "R2"], "a sedan's four doors")
	eq([v.seat_door("sedan", 0), v.seat_door("sedan", 1), v.seat_door("sedan", 2)], ["L1", "R1", "L2"], "three seats of a sedan: front left, front right, back left")
	eq(v.door_ids("pickup"), ["L1", "R1"], "a pickup has two doors")
	eq([v.seat_door("pickup", 0), v.seat_door("pickup", 1)], ["L1", "R1"], "and two seats")
	eq([v.seat_door("van", 0), v.seat_door("van", 1), v.seat_door("van", 2), v.seat_door("van", 3)], ["L1", "R1", "L2", "R2"], "a van's four seats use four doors")
	eq(v.door_ids("bus"), ["F"], "a bus has one door")
	for seat in 6:
		eq(v.seat_door("bus", seat), "F", "bus seat %d: the one door" % seat)
	eq([v.seats("sedan"), v.seats("pickup"), v.seats("van"), v.seats("bus")], [3, 2, 4, 6], "the seats are the data's")
	check(not v.door_ids("hovercraft").is_empty() and v.seat_door("hovercraft", 0) != "", "a kind that is not known still has a door to use")
	_end(g)


func test_a_seat_uses_the_door_the_data_names() -> void:
	var kinds: Dictionary = PLAIN_KINDS.duplicate(true)
	kinds.kinds.sedan["nose"] = "N"
	kinds.kinds.sedan["doors"] = [
		{"id": "FL", "side": "L", "seats": [0], "panel": [0, 30, 20, 40], "hinge": [0, 30], "open_deg": -70},
		{"id": "FR", "side": "R", "seats": [1], "panel": [80, 30, 20, 40], "hinge": [100, 30], "open_deg": 70},
		{"id": "BL", "side": "L", "seats": [2], "panel": [0, 80, 20, 40], "hinge": [0, 80], "open_deg": -70},
		{"id": "BR", "side": "R", "seats": [], "panel": [80, 80, 20, 40], "hinge": [100, 80], "open_deg": 70},
	]
	var g := _game(kinds)
	var v = g.sim.vehicles
	eq(v.door_ids("sedan"), ["FL", "FR", "BL", "BR"], "the doors of the data, in its order")
	eq([v.seat_door("sedan", 0), v.seat_door("sedan", 1), v.seat_door("sedan", 2)], ["FL", "FR", "BL"], "each seat uses the door that lists it")
	check(v.door_ids("sedan").has(v.seat_door("sedan", 5)), "a seat no door lists uses a door all the same")
	eq(v.door_ids("pickup"), ["L1", "R1"], "a kind with no doors in the data keeps the rule")
	_end(g)


# ----------------------------------------------------------------------- the spots --

func test_a_new_vehicle_takes_the_lowest_free_spot_and_keeps_it_through_a_trip() -> void:
	var g := _game()
	var sim = g.sim
	var a: Dictionary = sim.vehicles.add("sedan")
	var b: Dictionary = sim.vehicles.add("van")
	var c: Dictionary = sim.vehicles.add("pickup")
	eq([a.spot, b.spot, c.spot], [0, 1, 2], "spots 0, 1, 2 in the order they came")
	# the sedan goes out and the van's neighbour is lost: a new one takes the free place
	sim.vehicles.take(String(a.id), "houses")
	eq(int(a.spot), 0, "a vehicle that is out keeps its place")
	sim.vehicles.come_home(String(b.id), 9, 9, true)
	eq(sim.vehicles.fleet.size(), 2, "the van is lost")
	var d: Dictionary = sim.vehicles.add("bus")
	eq(int(d.spot), 2, "the bus takes the long place (the aisle's end)")
	eq(int(c.spot), 1, "and the pickup that stood there has moved to the bay the van left")
	sim.vehicles.come_home(String(a.id), 0, 0, false)
	eq(int(a.spot), 0, "the sedan comes home to its own place")
	_end(g)


func test_a_vehicle_that_comes_home_to_a_taken_place_is_given_the_lowest_free_one() -> void:
	var g := _game()
	var sim = g.sim
	var a: Dictionary = sim.vehicles.add("sedan")
	var b: Dictionary = sim.vehicles.add("van")
	b["spot"] = 0    # (something put it in the sedan's place)
	sim.vehicles.take(String(a.id), "houses")
	sim.vehicles.come_home(String(a.id), 0, 0, false)
	check(int(a.spot) != int(b.spot), "two vehicles never share a place while there is a free one: %d and %d" % [a.spot, b.spot])
	eq(int(a.spot), 1, "the lowest that was free")
	_end(g)


func test_a_fifth_vehicle_has_a_spot_and_can_make_a_trip() -> void:
	var g := _game()
	var sim = g.sim
	var ids: Array = []
	for kind in ["sedan", "van", "pickup", "bus", "sedan"]:
		ids.append(String(sim.vehicles.add(kind).id))
	var n: int = Convoy.spots()
	for id in ids:
		var spot := int(sim.vehicles.vehicle(id).spot)
		check(spot >= 0 and spot < n, "%s has a spot of the motor pool: %d of %d" % [id, spot, n])
	var held := {}
	for id in ids:
		var at := int(sim.vehicles.vehicle(id).spot)
		held[at] = int(held.get(at, 0)) + 1
	var fewest := 99
	var most := 0
	for i in n:
		fewest = mini(fewest, int(held.get(i, 0)))
		most = maxi(most, int(held.get(i, 0)))
	check(most - fewest <= 1, "with no place free the newcomers share them out evenly (a place in the yard, not a gap in the data): %s" % str(held))
	var party := _send(sim, ["dez", "marcus"], ids[4])
	var run := _run_trip(sim)
	eq(run.states, ["out", "driving_out", "away", "driving_in", "unloading"], "it makes the trip all the same")
	eq(String(sim.vehicles.vehicle(ids[4]).state), "parked", "and is parked at the end")
	check(not party.is_empty(), "(the party was made)")
	_end(g)


func test_the_spots_are_saved_and_an_old_save_without_them_gets_them() -> void:
	var a := _game()
	var sim = a.sim
	sim.vehicles.add("sedan")
	sim.vehicles.add("van")
	sim.vehicles.fleet[0]["spot"] = 2
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var b := _game()
	check(SaveGame.apply(b.sim, d), "it loads")
	eq([int(b.sim.vehicles.fleet[0].spot), int(b.sim.vehicles.fleet[1].spot)], [2, 1], "the spots come back as they were")
	# an old save: no spots at all
	var old: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	for e in old.modules.vehicles.fleet:
		e.erase("spot")
	var c := _game()
	check(SaveGame.apply(c.sim, old), "the old save loads")
	eq([int(c.sim.vehicles.fleet[0].spot), int(c.sim.vehicles.fleet[1].spot)], [0, 1], "and the vehicles are given places in order")
	# a save with two vehicles in one place: the second is moved
	var twice: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	twice.modules.vehicles.fleet[0]["spot"] = 1
	twice.modules.vehicles.fleet[1]["spot"] = 1
	var e := _game()
	check(SaveGame.apply(e.sim, twice), "that loads too")
	check(int(e.sim.vehicles.fleet[0].spot) != int(e.sim.vehicles.fleet[1].spot), "no two share a place")
	a.world.free()
	b.world.free()
	c.world.free()
	e.world.free()


# ------------------------------------------------------------------- the states --

func test_a_trip_by_car_goes_through_its_states_in_order_and_tells_the_story_in_events() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["ruth", "dez", "marcus"], String(v.id))
	eq(String(party.state), "out", "they start by walking to the car")
	eq(party.doors, [], "no door is open yet")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "out", "the vehicle is out")
	for p in _crew(sim, ["ruth", "dez", "marcus"]):
		check(p.away == null, "%s is still to be seen" % p.first)
	var run := _run_trip(sim)
	eq(run.states, ["out", "driving_out", "away", "driving_in", "unloading"], "the states, in order")
	var types: Array = []
	for e in run.events:
		if ["board", "seated", "depart", "arrive", "parked", "alight"].has(String(e.type)):
			types.append(String(e.type))
	eq(types.slice(0, 7), ["board", "board", "seated", "seated", "board", "seated", "depart"], "two doors open at once, the third person waits for a door (the bay is on the aisle side: two doors for three people), the doors shut behind them, and the car leaves")
	eq(types.slice(7), ["arrive", "parked", "alight", "alight", "alight"], "it comes back, stops, and three get out")
	for e in _events(run.events, "board"):
		eq(String(e.vehicle), String(v.id), "the event names the vehicle")
		check(["ruth", "dez", "marcus"].has(String(e.person)) and String(e.door) != "", "and who and by which door")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the sedan is parked again")
	for p in _crew(sim, ["ruth", "dez", "marcus"]):
		check(p.away == null, "%s is home" % p.first)
	_end(g)


func test_the_people_walk_to_their_own_doors() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["ruth", "dez", "marcus"], String(v.id))
	eq(party.seats, {"ruth": 0, "dez": 1, "marcus": 2}, "a seat for each, in the party's order")
	var doors := {}
	for p in _crew(sim, ["ruth", "dez", "marcus"]):
		var goal = sim.scavenge.goal_for(p)
		check(goal != null, "%s has somewhere to go" % p.first)
		var spot := _door_spot_of(sim, party, String(p.id))
		var door := String(sim.vehicles.seat_door("sedan", int(party.seats[p.id]), int(v.spot)))
		# the third person shares the first's door (a sedan in a bay has two doors on the aisle side): they wait a step behind
		var behind := 0.6 * float(doors.get(door, 0))
		near(float(goal.x), spot.x, 0.001, "%s goes to their door (x)" % p.first)
		near(float(goal.y), spot.y + behind, 0.001, "%s goes to their door (y)" % p.first)
		eq(String(goal.what), "Heading for the car", "and says so")
		doors[door] = int(doors.get(door, 0)) + 1
	eq(doors.size(), 2, "three people, the two doors on the aisle side (the third waits behind the first)")
	# they get there by walking
	var got := _until(sim, func(): return _state(sim) != "out", 12000)
	check(got > 0, "they reach the car and it drives off (%d steps)" % got)
	_end(g)


func test_a_door_opens_for_each_person_and_they_go_in_at_the_middle() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["dez"], String(v.id))
	var dez = _crew(sim, ["dez"])[0]
	_at_doors(sim, party)
	var x0: float = dez.x
	var y0: float = dez.y
	_go(sim, 1)
	eq(party.doors.size(), 1, "the door opens as they arrive")
	var e: Dictionary = party.doors[0]
	eq([String(e.pid), String(e.dir)], ["dez", "in"], "for Dez, going in")
	eq(String(e.door), String(sim.vehicles.seat_door("sedan", 0, int(v.spot))), "by the door of their seat (on the aisle side of the bay)")
	near(float(e.dur), Scavenge.BOARD_MIN, 1e-9, "for as long as the data says")
	check(dez.away == null, "they can still be seen")
	near(dez.x, x0, 1e-6, "and stand still")
	near(dez.y, y0, 1e-6, "(both ways)")
	var goal = sim.scavenge.goal_for(dez)
	check(goal != null and absf(float(goal.x) - x0) < 0.01 and absf(float(goal.y) - y0) < 0.01, "their goal is where they are: they are held at the door")
	_until(sim, func(): return dez.away != null)
	check(dez.away != null, "they go in")
	var t_in := float(e.t)
	check(t_in >= Scavenge.BOARD_MIN / 2.0 and t_in < Scavenge.BOARD_MIN / 2.0 + 0.5, "half way through the door's time: %.2f of %.2f" % [t_in, Scavenge.BOARD_MIN])
	eq(_events(sim.events, "board").size(), 1, "and the rules say so")
	eq(_events(sim.events, "seated").size(), 0, "(the door is still open)")
	eq(party.doors.size(), 1, "the door is still open")
	eq(String(party.state), "out", "the car has not moved")
	_until(sim, func(): return party.doors.is_empty())
	eq(_events(sim.events, "seated").size(), 1, "the door shuts and they are seated")
	eq(String(party.state) if sim.scavenge.parties.has(party) else "gone", "driving_out", "and the car goes at once, with everyone in")
	_end(g)


func test_the_car_waits_for_the_last_person_and_the_doors_to_shut() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["ruth", "dez", "marcus"], String(v.id))
	var all = _crew(sim, ["ruth", "dez", "marcus"])
	# two are at their doors, the third is a long way off
	for p in all:
		var at := _door_spot_of(sim, party, String(p.id))
		p.x = at.x
		p.y = at.y
		p.path = []
	var far = all[2]
	far.x = 20.0
	far.y = 45.0
	_go(sim, 100)
	eq(String(party.state), "out", "two are in and the car waits for the third")
	check(all[0].away != null and all[1].away != null, "the two went in")
	check(far.away == null, "the third is still on the way")
	var at := _door_spot_of(sim, party, String(far.id))
	far.x = at.x
	far.y = at.y
	far.path = []
	var pending := _until(sim, func(): return _state(sim) == "driving_out")
	check(pending > 0, "the car goes when the third is in")
	check(party.doors.is_empty(), "with every door shut")
	check(sim.scavenge._all_through(party), "and everyone aboard")
	_end(g)


func test_the_drive_out_takes_about_six_seconds_and_the_hours_start_when_it_ends() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["dez", "marcus"], String(v.id))
	var trip: float = float(party.return_at) - float(party.depart)
	check(trip > 60.0, "(the trip's own hours: %.0f minutes)" % trip)
	_at_doors(sim, party)
	_until(sim, func(): return _state(sim) == "driving_out")
	eq(String(party.state), "driving_out", "driving out")
	near(float(party.drive_t), 0.0, 0.2, "from the start of the route")
	var route: Array = Convoy.route(int(v.spot), "out")
	near(float(party.drive_len), Convoy.length(route) / Scavenge.CAR_SPEED_TPM, 1e-9, "its length is the route's over the car's speed")
	var seconds: float = float(party.drive_len) / float(sim.min_per_sec)
	check(seconds > 4.0 and seconds < 8.0, "about six seconds at the normal speed: %.1f" % seconds)
	var events := _events(sim.events, "depart")
	eq(events.size(), 1, "one departure")
	eq(String(events[0].vehicle), String(v.id), "of this vehicle")
	var before := float(party.return_at)
	# half way: the drive moves with the game's minutes
	var t0 := float(party.drive_t)
	_go(sim, 30)
	near(float(party.drive_t) - t0, 30.0 * STEP * float(sim.min_per_sec), 0.01, "it moves by the game minutes that pass")
	check(String(party.state) == "driving_out", "still driving")
	_until(sim, func(): return _state(sim) == "away")
	eq(String(party.state), "away", "then away")
	near(float(party.return_at) - float(sim.clock_min), trip, 1.5, "the trip's hours start now: %.1f minutes still to go of %.1f" % [float(party.return_at) - float(sim.clock_min), trip])
	check(float(party.return_at) > before, "so it is due later than the plain sum said")
	near(float(party.return_at) - float(party.depart), trip, 1.5, "and it is the same length from its new start")
	check(not party.has("drive_t"), "no drive is kept while away")
	check(sim.alerts.has("scav-out-%d" % int(party.n)), "the player is told they have left, now that the car is gone")
	_end(g)


func test_the_car_drives_in_when_the_hours_are_up_and_they_get_out_one_by_one() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["ruth", "dez", "marcus"], String(v.id))
	_at_doors(sim, party)
	_until(sim, func(): return _state(sim) == "away")
	var due := float(party.return_at)
	_until(sim, func(): return _state(sim) != "away")
	eq(String(party.state), "driving_in", "driving in")
	check(float(sim.clock_min) >= due and float(sim.clock_min) < due + 1.0, "at the hour it was due: %.1f against %.1f" % [sim.clock_min, due])
	var route: Array = Convoy.route(int(v.spot), "in")
	near(float(party.drive_len), Convoy.length(route) / Scavenge.CAR_SPEED_TPM, 1e-9, "the way in over the car's speed")
	near(float(party.drive_t), 0.0, 0.2, "from the start of it")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "out", "the car is not home yet")
	for p in _crew(sim, ["ruth", "dez", "marcus"]):
		check(p.away != null, "%s is in the car" % p.first)
	_until(sim, func(): return _state(sim) == "unloading")
	eq(String(party.state), "unloading", "unloading")
	eq(_events(sim.events, "arrive").size(), 1, "the car came back")
	eq(_events(sim.events, "parked").size(), 1, "and stopped in its bay")
	near(float(party.drive_t), float(party.drive_len), 1e-9, "(the car is at the end of its route)")
	# one gets out at once, the next a gap later, the last another gap later
	var out_at: Array = []
	var came := {}
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < 3000:
		sim.update(STEP)
		n += 1
		for p in _crew(sim, ["ruth", "dez", "marcus"]):
			if p.away == null and not came.has(p.id) and not sim.scavenge.parties.is_empty():
				came[p.id] = true
				out_at.append([String(p.id), float(sim.clock_min), Vector2(p.x, p.y)])
	eq(out_at.size(), 3, "all three got out before the report: %s" % str(out_at))
	if out_at.size() == 3:
		near(float(out_at[1][1]) - float(out_at[0][1]), Scavenge.UNLOAD_GAP_MIN, 0.4, "a gap between the first and the second")
		near(float(out_at[2][1]) - float(out_at[1][1]), Scavenge.UNLOAD_GAP_MIN, 0.4, "and the second and the third")
		eq([out_at[0][0], out_at[1][0], out_at[2][0]], ["ruth", "dez", "marcus"], "in the order of their seats")
		for e in out_at:
			var spot := _door_spot_of(sim, party, String(e[0]))
			check((e[2] as Vector2).distance_to(spot) < 0.5, "%s steps out at their own door: %s against %s" % [e[0], str(e[2]), str(spot)])
	eq(_events(sim.events, "alight").size(), 3, "three alighting events")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the sedan is parked at the end")
	_end(g)


func test_survivors_stand_at_their_doors_and_the_report_comes_when_the_last_door_shuts() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["dez", "marcus"], String(v.id))
	var food := float(sim.stock.food)
	_at_doors(sim, party)
	_until(sim, func(): return _state(sim) == "unloading")
	check(not sim.alerts.has("scav-%d" % int(party.n)), "nothing is told while they are still in the car")
	var marcus = _crew(sim, ["marcus"])[0]
	_until(sim, func(): return marcus.away == null)
	check(not party.doors.is_empty() and sim.scavenge.parties.size() == 1, "Marcus is out and his door is still open: the trip is not over")
	_until(sim, func(): return sim.scavenge.parties.is_empty())
	check(sim.alerts.has("scav-%d" % int(party.n)), "the report is told at the end")
	check(float(sim.stock.food) > food - 5.0, "and the loot is in the stores")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "and the car is parked")
	_end(g)


func test_a_trip_by_car_takes_longer_than_its_hours_by_the_time_of_the_drives_and_the_doors() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["ruth", "dez", "marcus"], String(v.id))
	var planned := float(party.return_at)
	_at_doors(sim, party)
	var run_start := float(sim.clock_min)
	_run_trip(sim, false)
	var home := float(sim.clock_min)
	var out_len: float = Convoy.length(Convoy.route(int(v.spot), "out")) / Scavenge.CAR_SPEED_TPM
	var in_len: float = Convoy.length(Convoy.route(int(v.spot), "in")) / Scavenge.CAR_SPEED_TPM
	var expected: float = Scavenge.BOARD_MIN + out_len + in_len + 2.0 * Scavenge.UNLOAD_GAP_MIN + Scavenge.BOARD_MIN
	var extra := home - planned
	check(extra > expected - 3.0 and extra < expected + 3.0, "home %.1f minutes after the plain return time (the doors and drives come to %.1f)" % [extra, expected])
	check(home - run_start > planned - run_start, "later than it was")
	_end(g)


# ------------------------------------------------------------------ the seats --

## The van as the data now has it: two doors, each for two of the four seats.
func _two_door_van_kinds() -> Dictionary:
	var kinds: Dictionary = PLAIN_KINDS.duplicate(true)
	kinds.kinds.van["nose"] = "N"
	kinds.kinds.van["doors"] = [
		{"id": "L1", "side": "L", "seats": [0, 2], "panel": [0, 30, 20, 40], "hinge": [0, 30], "open_deg": -70},
		{"id": "R1", "side": "R", "seats": [1, 3], "panel": [80, 30, 20, 40], "hinge": [100, 30], "open_deg": 70},
	]
	return kinds


func _ids_of_crew(crew: Array) -> Array:
	var ids: Array = []
	for p in crew:
		ids.append(String(p.id))
	return ids


func test_a_van_with_four_doors_uses_the_two_on_the_aisle_side_at_once() -> void:
	var g := _game(PLAIN_KINDS)
	var sim = g.sim
	var crew := _full_crew(sim)
	check(crew.size() >= 4, "a crew of at least four: %d" % crew.size())
	var van: Dictionary = sim.vehicles.add("van")
	var party := _send(sim, _ids_of_crew(crew).slice(0, 4), String(van.id))
	eq(party.seats.size(), 4, "four seats taken")
	var used := {}
	for id in party.members:
		used[sim.vehicles.seat_door("van", int(party.seats[id]), int(van.spot))] = true
	eq(used.size(), 2, "four people use the two doors on the aisle side of the bay (the far doors are behind the car)")
	_at_doors(sim, party)
	_go(sim, 1)
	eq(party.doors.size(), 2, "two doors open at once, the other two wait for them")
	var run := _run_trip(sim)
	eq(run.states, ["out", "driving_out", "away", "driving_in", "unloading"], "the van's trip")
	eq(_events(run.events, "board").size(), 4, "four went in")
	eq(_events(run.events, "alight").size(), 4, "and four got out")
	_end(g)


func test_a_van_with_two_doors_lets_the_other_two_wait_for_theirs() -> void:
	var g := _game(_two_door_van_kinds())
	var sim = g.sim
	var crew := _full_crew(sim)
	var van: Dictionary = sim.vehicles.add("van")
	var party := _send(sim, _ids_of_crew(crew).slice(0, 4), String(van.id))
	_at_doors(sim, party)
	_go(sim, 1)
	eq(party.doors.size(), 1, "one door on the aisle side: one person goes in at a time")
	for id in party.members:
		if _entry_of_pid(party, String(id)).is_empty():
			var goal = sim.scavenge.goal_for(_crew(sim, [id])[0])
			check(goal != null and String(goal.what) == "Heading for the car", "the others wait for their doors")
	var run := _run_trip(sim)
	eq(run.states, ["out", "driving_out", "away", "driving_in", "unloading"], "all four make the trip")
	var boards := _events(run.events, "board")
	eq(boards.size(), 4, "four went in")
	eq(_events(run.events, "alight").size(), 4, "and four got out")
	_end(g)


func _entry_of_pid(party: Dictionary, id: String) -> Dictionary:
	for e in party.doors:
		if String(e.pid) == id:
			return e
	return {}


func test_a_bus_takes_six_through_its_one_door_one_after_another() -> void:
	var g := _game()
	var sim = g.sim
	var crew := _full_crew(sim)
	check(crew.size() >= 6, "a crew of six: %d" % crew.size())
	var bus: Dictionary = sim.vehicles.add("bus")
	sim.vehicles.fuel = 80.0
	var party := _send(sim, _ids_of_crew(crew), String(bus.id))
	eq(party.seats.size(), 6, "six seats taken")
	var door := String(sim.vehicles.seat_door("bus", 0))
	for seat in 6:
		eq(String(sim.vehicles.seat_door("bus", seat)), door, "one door for every seat")
	_at_doors(sim, party)
	var starts: Array = []
	var seen := {}
	var open_at_once := 0
	var n := 0
	while String(party.state) == "out" and n < 3000:
		sim.update(STEP)
		n += 1
		open_at_once = maxi(open_at_once, party.doors.size())
		for e in party.doors:
			var key := "%s" % e.pid
			if not seen.has(key):
				seen[key] = float(sim.clock_min)
				starts.append(float(sim.clock_min))
	eq(starts.size(), 6, "six went through the door")
	for i in range(1, starts.size()):
		check(starts[i] - starts[i - 1] > Scavenge.BOARD_MIN / 2.0 - 0.4, "one at a time: the next starts when the one before is in (%.2f)" % (starts[i] - starts[i - 1]))
	eq(String(party.state), "driving_out", "then the bus goes")
	var run := _run_trip(sim)
	eq(_events(run.events, "alight").size(), 6, "six got out")
	_end(g)


func test_every_kind_makes_the_trip_with_as_many_as_it_seats() -> void:
	for kind in ["pickup", "sedan", "van", "bus"]:
		var g := _game()
		var sim = g.sim
		var crew := _full_crew(sim)
		var v: Dictionary = sim.vehicles.add(kind)
		sim.vehicles.fuel = 80.0
		var n: int = sim.vehicles.seats(kind)
		var party := _send(sim, _ids_of_crew(crew).slice(0, n), String(v.id))
		eq(party.members.size(), n, "%s: a full load" % kind)
		var run := _run_trip(sim)
		eq(run.states, ["out", "driving_out", "away", "driving_in", "unloading"], "%s: the states" % kind)
		eq(_events(run.events, "board").size(), n, "%s: all go in" % kind)
		eq(_events(run.events, "alight").size(), n, "%s: all get out" % kind)
		eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "%s: parked at the end" % kind)
		_end(g)


# ------------------------------------------------------------- let go and called off --

func test_someone_given_an_order_on_the_way_to_the_car_is_let_go_and_the_rest_go_without_them() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["ruth", "dez", "marcus"], String(v.id))
	var marcus = _crew(sim, ["marcus"])[0]
	marcus.order = {"x": 30.0, "y": 30.0, "z": 0.0}
	_go(sim, 1)
	eq(party.members, ["ruth", "dez"], "Marcus is let go")
	check(not party.seats.has("marcus") and party.seats.has("ruth"), "and his seat goes with him")
	check(not party.result.lost.has("marcus") and not party.result.hurt.has("marcus"), "his part of the result too")
	var run := _run_trip(sim)
	eq(run.states, ["out", "driving_out", "away", "driving_in", "unloading"], "the others go on")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the car comes home")
	_end(g)


func test_someone_given_an_order_at_the_door_is_let_go_and_the_door_shuts() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["ruth", "dez"], String(v.id))
	_at_doors(sim, party)
	_go(sim, 1)
	eq(party.doors.size(), 2, "two doors are open")
	var dez = _crew(sim, ["dez"])[0]
	dez.order = {"x": 30.0, "y": 30.0, "z": 0.0}
	_go(sim, 1)
	eq(party.members, ["ruth"], "Dez is let go")
	eq(party.doors.size(), 1, "and his door shuts")
	check(dez.away == null, "he is still at home")
	_until(sim, func(): return _state(sim) == "driving_out")
	eq(_state(sim), "driving_out", "Ruth goes alone")
	_end(g)


func test_a_trip_where_everyone_is_let_go_is_called_off_and_the_car_and_the_fuel_come_back() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var fuel: float = sim.vehicles.fuel
	_send(sim, ["dez", "marcus"], String(v.id))
	check(sim.vehicles.fuel < fuel, "the fuel is burnt at the start")
	for p in _crew(sim, ["dez", "marcus"]):
		p.order = {"x": 30.0, "y": 30.0, "z": 0.0}
	_go(sim, 2)
	check(sim.scavenge.parties.is_empty(), "the trip is off")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the car is parked")
	near(sim.vehicles.fuel, fuel, 1e-6, "the fuel is given back")
	check(sim.alerts.has("scav-1") or not sim.alerts.is_empty(), "the player is told")
	_end(g)


func test_a_trip_that_comes_due_before_anyone_reached_the_car_never_left() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var fuel: float = sim.vehicles.fuel
	var party := _send(sim, ["dez"], String(v.id))
	var dez = _crew(sim, ["dez"])[0]
	dez.x = 5.0
	dez.y = 5.0
	dez.path = []
	party["return_at"] = float(sim.clock_min) + 1.0    # (stuck far away until it is due)
	_go(sim, 60)
	_until(sim, func(): return sim.scavenge.parties.is_empty(), 6000)
	check(sim.scavenge.parties.is_empty(), "the party is over")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the car never left")
	near(sim.vehicles.fuel, fuel, 1e-6, "and the fuel is given back")
	check(dez.away == null, "and Dez is at home")
	_end(g)


# ---------------------------------------------------------------- foot, and played --

func test_a_trip_on_foot_is_what_it_was() -> void:
	var g := _game()
	var sim = g.sim
	var crew := _crew(sim, ["dez", "marcus"])
	check(sim.scavenge.send(crew, "houses", "loot"), "they go on foot")
	var party := _party(sim)
	check(not party.has("seats") and not party.has("doors"), "a party on foot has no seats and no doors: %s" % str(party.keys()))
	var goal = sim.scavenge.goal_for(crew[0])
	var gate: Vector2 = sim.scavenge.gate_center()
	check(goal != null and absf(float(goal.x) - gate.x) < 1e-9 and absf(float(goal.y) - gate.y) < 1e-9, "they walk to the gate")
	eq(String(goal.what), "Heading for the gate", "(and say so)")
	var states: Array = []
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < 20000:
		var st := _state(sim)
		if states.is_empty() or states[states.size() - 1] != st:
			states.append(st)
		sim.update(STEP)
		n += 1
	eq(states, ["out", "away"], "out, away, home: no other state")
	for p in crew:
		check(p.away == null, "%s is back" % p.first)
		near(p.y, gate.y, 1.5, "at the gate")
	check(sim.events.filter(func(e): return ["board", "seated", "depart", "arrive", "parked", "alight"].has(String(e.type))).is_empty(), "no car events")
	_end(g)


func test_a_played_trip_by_car_skips_the_departure_and_comes_home_by_car() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var crew := _crew(sim, ["dez", "marcus"])
	var played := {"loot": {"food": 14}, "hurt": {}, "lost": [], "clear": true, "ammo_used": 0.0, "beats": []}
	var food := float(sim.stock.food)
	check(sim.scavenge.send_played(crew, "houses", "loot", String(v.id), played), "the played party goes")
	var party := _party(sim)
	eq(String(party.state), "away", "they are away at once: the raid screen was the departure")
	for p in crew:
		check(p.away != null, "%s is off the map" % p.first)
	eq(_events(sim.events, "depart").size() + _events(sim.events, "board").size(), 0, "no departure to show")
	near(float(party.return_at) - float(party.depart), sim.scavenge.action_hours("houses", "loot", String(v.id)) * 60.0, 1.5, "the trip's hours are the sedan's")
	check(sim.scavenge.raids.has("houses"), "the place is raided")
	var run := _run_trip(sim)
	eq(run.states, ["away", "driving_in", "unloading"], "it comes back by car")
	eq(_events(run.events, "alight").size(), 2, "and they get out")
	check(float(sim.stock.food) > food + 10.0, "with what was played: %.1f from %.1f" % [sim.stock.food, food])
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the sedan is parked")
	_end(g)


func test_a_party_lost_with_its_vehicle_does_not_drive_home() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["dez", "marcus"], String(v.id))
	party.result = {"loot": {}, "hurt": {}, "lost": ["dez", "marcus"]}
	var run := _run_trip(sim)
	eq(run.states, ["out", "driving_out", "away"], "out and away, and nobody comes home")
	eq(sim.vehicles.fleet.size(), 0, "the sedan is lost with them")
	eq(_events(run.events, "arrive").size() + _events(run.events, "parked").size(), 0, "it does not come back")
	_end(g)


func test_a_party_with_one_lost_brings_the_rest_home_by_car() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["ruth", "dez", "marcus"], String(v.id))
	party.result = {"loot": {"food": 5}, "hurt": {}, "lost": ["dez"]}
	var run := _run_trip(sim)
	eq(run.states, ["out", "driving_out", "away", "driving_in", "unloading"], "the car comes home")
	eq(_events(run.events, "alight").size(), 2, "with two: the third is not in it")
	var dez = _crew(sim, ["dez"])[0]
	check(dez.dead or (dez.away is Dictionary and String(dez.away.get("kind", "")) == "lost"), "Dez is lost")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the car is parked")
	_end(g)


# --------------------------------------------------------------------------- saves --

## Saves `a`'s game and loads it into a new one (the same town), which is returned.
func _reload(a: Dictionary) -> Dictionary:
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	_write(TOWN_FIXTURE, TOWN)
	Town.data_path = TOWN_FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "the save loads")
	return b


## Plays on the loaded game to the end of its trip: the car is parked, everyone is home and the party is over.
func _finish_and_check(b: Dictionary, id: String, ids: Array, label: String) -> void:
	var sim = b.sim
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < 40000:
		sim.update(STEP)
		n += 1
	check(sim.scavenge.parties.is_empty(), "%s: the trip ends after the load" % label)
	eq(String(sim.vehicles.vehicle(id).get("state", "")), "parked", "%s: the vehicle is parked at the end" % label)
	for p in _crew(sim, ids):
		check(p.away == null, "%s: %s is home" % [label, p.first])


func _compare(a: Dictionary, b: Dictionary, label: String) -> void:
	var pa := _party(a.sim)
	var pb := _party(b.sim)
	check(not pa.is_empty() and not pb.is_empty(), "%s: there is a party on both sides" % label)
	if pa.is_empty() or pb.is_empty():
		return
	for key in ["state", "vehicle", "site", "action", "members", "seats", "doors", "aboard", "unload"]:
		eq(pb.get(key), pa.get(key), "%s: party %s" % [label, key])
	for key in ["drive_t", "drive_len", "return_at", "depart", "unload_wait"]:
		if pa.has(key):
			near(float(pb.get(key, -1.0)), float(pa[key]), 1e-6, "%s: party %s" % [label, key])
	for id in pa.members:
		var qa = _crew(a.sim, [id])[0]
		var qb = _crew(b.sim, [id])[0]
		eq(qb.away != null, qa.away != null, "%s: %s is %s" % [label, id, "off the map" if qa.away != null else "on it"])
		if qa.away == null:
			near(qb.x, qa.x, 1e-6, "%s: %s x" % [label, id])
	eq(String(b.sim.vehicles.fleet[0].state), String(a.sim.vehicles.fleet[0].state), "%s: the vehicle's state" % label)
	eq(int(b.sim.vehicles.fleet[0].spot), int(a.sim.vehicles.fleet[0].spot), "%s: its spot" % label)


## A game with the sedan sent out with Ruth, Dez and Marcus, played on to `stage`.
func _game_at(stage: String) -> Dictionary:
	var a := _game()
	var sim = a.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	var party := _send(sim, ["ruth", "dez", "marcus"], String(v.id))
	if stage != "walking":
		_at_doors(sim, party)
	var reached := true
	match stage:
		"boarding":
			reached = _until(sim, func(): return not party.doors.is_empty() and not _through(sim, party).is_empty() and _through(sim, party).size() < 3) >= 0
		"driving_out":
			reached = _until(sim, func(): return String(party.state) == "driving_out" and float(party.drive_t) > float(party.drive_len) / 2.0) >= 0
		"away":
			reached = _until(sim, func(): return String(party.state) == "away" and float(sim.clock_min) > float(party.depart) + 10.0) >= 0
		"driving_in":
			reached = _until(sim, func(): return String(party.state) == "driving_in" and float(party.drive_t) > float(party.drive_len) / 2.0) >= 0
		"unloading":
			reached = _until(sim, func(): return String(party.state) == "unloading" and _through(sim, party).size() == 2) >= 0
	check(reached, "(the trip reached %s)" % stage)
	return a


func _through(sim, party: Dictionary) -> Array:
	var out: Array = []
	for id in party.members:
		for p in sim.people:
			if p.id == id and sim.scavenge._is_through(p, party):
				out.append(id)
	return out


func _save_in(stage: String) -> void:
	var a := _game_at(stage)
	var b := _reload(a)
	_compare(a, b, stage)
	eq(_state(b.sim), _state(a.sim), "%s: the same state after the load" % stage)
	_finish_and_check(b, String(b.sim.vehicles.fleet[0].id), ["ruth", "dez", "marcus"], stage)
	_finish_and_check(a, String(a.sim.vehicles.fleet[0].id), ["ruth", "dez", "marcus"], stage + " (the original)")
	a.world.free()
	b.world.free()


func test_a_save_while_they_walk_to_the_car_loads_and_the_trip_goes_on() -> void:
	_save_in("walking")


func test_a_save_at_the_doors_with_one_in_and_a_door_open_loads_and_the_trip_goes_on() -> void:
	_save_in("boarding")


func test_a_save_while_the_car_drives_out_loads_and_the_trip_goes_on() -> void:
	_save_in("driving_out")


func test_a_save_while_they_are_away_loads_and_the_trip_goes_on() -> void:
	_save_in("away")


func test_a_save_while_the_car_drives_in_loads_and_the_trip_goes_on() -> void:
	_save_in("driving_in")


func test_a_save_while_they_get_out_loads_and_the_rest_get_out() -> void:
	_save_in("unloading")


func test_a_save_from_before_this_round_with_a_party_out_in_a_vehicle_still_loads_and_drives_home() -> void:
	# the old shape of a party: no seats, no doors, no drive; the state "away" with the people through the gate
	var a := _game_at("away")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	for e in d.modules.scavenge.parties:
		for key in ["seats", "doors", "drive_t", "drive_len", "aboard", "unload", "unload_wait"]:
			e.erase(key)
	for e in d.modules.vehicles.fleet:
		e.erase("spot")
	_write(TOWN_FIXTURE, TOWN)
	Town.data_path = TOWN_FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "the old save loads")
	eq(_state(b.sim), "away", "still away")
	check(int(b.sim.vehicles.fleet[0].spot) >= 0, "the vehicle has a place now")
	_finish_and_check(b, String(b.sim.vehicles.fleet[0].id), ["ruth", "dez", "marcus"], "old save")
	# and an old save made while they were still walking to the gate: they go to the car all the same
	var c := _game_at("walking")
	var d2: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(c.sim)))
	for e in d2.modules.scavenge.parties:
		for key in ["seats", "doors", "drive_t", "drive_len", "aboard", "unload", "unload_wait"]:
			e.erase(key)
	var f := _game_at("walking")
	f.world.free()
	_write(TOWN_FIXTURE, TOWN)
	Town.data_path = TOWN_FIXTURE
	var e2 := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(e2.sim, d2), "the other old save loads")
	var party := _party(e2.sim)
	eq(_state(e2.sim), "out", "walking")
	var ruth = _crew(e2.sim, ["ruth"])[0]
	var goal = e2.sim.scavenge.goal_for(ruth)
	check(goal != null and String(goal.what) == "Heading for the car", "to the car: %s" % str(goal))
	_at_doors(e2.sim, party)
	_finish_and_check(e2, String(e2.sim.vehicles.fleet[0].id), ["ruth", "dez", "marcus"], "old save while walking")
	a.world.free()
	b.world.free()
	c.world.free()
	e2.world.free()


# ------------------------------------------- review fixes: the real data's seats, the aisle side, the bus's place --

## The kinds with doors as JSON gives them (numbers come back as floats: a list [2.0] does not "have" 2 in GDScript 4.7).
func _kinds_with_doors() -> Dictionary:
	var kinds: Dictionary = PLAIN_KINDS.duplicate(true)
	kinds.kinds.sedan["nose"] = "S"
	kinds.kinds.sedan["doors"] = [
		{"id": "L1", "side": "L", "seats": [0], "panel": [0, 30, 20, 40], "hinge": [0, 30], "open_deg": 70},
		{"id": "R1", "side": "R", "seats": [1], "panel": [80, 30, 20, 40], "hinge": [100, 30], "open_deg": -70},
		{"id": "L2", "side": "L", "seats": [], "panel": [0, 80, 20, 40], "hinge": [0, 80], "open_deg": 66},
		{"id": "R2", "side": "R", "seats": [2], "panel": [80, 80, 20, 40], "hinge": [100, 80], "open_deg": -66},
	]
	kinds.kinds.pickup["doors"] = [
		{"id": "L1", "side": "L", "seats": [0], "panel": [0, 30, 20, 40], "hinge": [0, 30], "open_deg": 70},
		{"id": "R1", "side": "R", "seats": [1], "panel": [80, 30, 20, 40], "hinge": [100, 30], "open_deg": -70},
	]
	return kinds


func test_a_seat_finds_its_door_in_data_that_came_from_json() -> void:
	var g := _game(_kinds_with_doors())
	var v = g.sim.vehicles
	eq([v.seat_door("sedan", 0), v.seat_door("sedan", 1), v.seat_door("sedan", 2)], ["L1", "R1", "R2"],
			"the third seat uses R2 as the data says (the old comparison of 2 with 2.0 fell back to L2)")
	_end(g)


func test_people_use_the_doors_on_the_aisle_side_of_their_bay() -> void:
	# the west bay's car has the aisle on its right, the east bay's on its left: nobody walks through a car to a far door
	var g := _game(_kinds_with_doors())
	var v = g.sim.vehicles
	eq(Convoy.aisle_side(0), "R", "the west bay: the aisle is on the right of a car facing north")
	eq(Convoy.aisle_side(1), "L", "the east bay: on the left")
	eq(Convoy.aisle_side(2), "", "the aisle's end: the bus stands in the aisle itself")
	eq(Convoy.aisle_side(9), "", "a place that is not there: no side")
	eq([v.seat_door("sedan", 0, 0), v.seat_door("sedan", 1, 0), v.seat_door("sedan", 2, 0)], ["R1", "R2", "R1"], "west bay: the right-hand doors, in turn")
	eq([v.seat_door("sedan", 0, 1), v.seat_door("sedan", 1, 1), v.seat_door("sedan", 2, 1)], ["L1", "L2", "L1"], "east bay: the left-hand doors")
	eq([v.seat_door("sedan", 0), v.seat_door("sedan", 1), v.seat_door("sedan", 2)], ["L1", "R1", "R2"], "no place given: the data's own")
	eq([v.seat_door("pickup", 0, 0), v.seat_door("pickup", 1, 0), v.seat_door("pickup", 0, 1), v.seat_door("pickup", 1, 1)], ["R1", "R1", "L1", "L1"], "a pickup's two doors")
	eq(v.seat_door("bus", 3, 2), "F", "the bus keeps its one door")
	# and the door's spot is on the aisle side of the car, in the aisle (x between the bays)
	var west: Vector2 = Convoy.door_spot(0, "sedan", v.seat_door("sedan", 0, 0))
	var east: Vector2 = Convoy.door_spot(1, "sedan", v.seat_door("sedan", 0, 1))
	check(west.x > Convoy.bay(0).x, "west bay: the person stands east of the car, in the aisle (%.2f of %.2f)" % [west.x, Convoy.bay(0).x])
	check(east.x < Convoy.bay(1).x, "east bay: west of the car, in the aisle (%.2f of %.2f)" % [east.x, Convoy.bay(1).x])
	_end(g)


func test_the_party_boards_by_the_aisle_doors() -> void:
	var g := _game(_kinds_with_doors())
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	v["spot"] = 0
	sim.vehicles.fuel = 60.0
	var crew: Array = []
	for p in sim.people:
		if crew.size() < 2 and p.id != "ruth":
			crew.append(p)
	var ok: bool = sim.scavenge.send(crew, "houses", "loot", String(v.id))
	check(ok, "the party is sent in the sedan")
	if ok:
		var party: Dictionary = sim.scavenge.parties[sim.scavenge.parties.size() - 1]
		for p in crew:
			var door := String(sim.scavenge._door_of(party, String(p.id)))
			check(door.begins_with("R"), "%s uses a right-hand door (the aisle side of the west bay): %s" % [p.id, door])
	_end(g)


func test_a_bus_always_has_the_long_place_and_nothing_else_stands_on_it() -> void:
	var g := _game(PLAIN_KINDS)
	var v = g.sim.vehicles
	eq(Convoy.long_spot(), 2, "the pool's aisle end is the long place")
	check(Convoy.is_long({"h": 8.07}) and not Convoy.is_long({"h": 4.4}), "a vehicle is long when it does not fit a bay")
	var sedan: Dictionary = v.add("sedan")
	var pickup: Dictionary = v.add("pickup")
	var van: Dictionary = v.add("van")
	eq([int(sedan.spot), int(pickup.spot), int(van.spot)], [0, 1, 2], "with no bus the three take the three places")
	var bus: Dictionary = v.add("bus")
	eq(int(bus.spot), 2, "the bus takes the long place")
	check(int(van.spot) != 2, "and the van that stood there has been moved off it (it shares a bay now: %d)" % int(van.spot))
	check(int(sedan.spot) != 2 and int(pickup.spot) != 2, "nobody else is on it")
	eq(v.ensure_spot(bus), 2, "ensure_spot keeps the bus there")
	# a bus first: the others never take its place
	var h := _game(PLAIN_KINDS)
	var w = h.sim.vehicles
	var bus2: Dictionary = w.add("bus")
	var a: Dictionary = w.add("sedan")
	var b: Dictionary = w.add("pickup")
	var c: Dictionary = w.add("van")
	eq([int(bus2.spot), int(a.spot), int(b.spot)], [2, 0, 1], "bus, sedan, pickup: 2, 0, 1")
	check(int(c.spot) != 2, "the fourth shares a bay, never the bus's place")
	# a bus that comes home to find its place taken gets it back
	var d := _game(PLAIN_KINDS)
	var x = d.sim.vehicles
	var bus3: Dictionary = x.add("bus")
	bus3["spot"] = 0
	var van3: Dictionary = x.add("van")
	van3["spot"] = 2
	eq(x.ensure_spot(bus3), 2, "a bus that is not on the long place is put on it")
	check(int(van3.spot) != 2, "the van is moved off")
	_end(g)
	_end(h)
	_end(d)


# -------------------------------------------------------------- a parked car is in people's way --

## Whether the ground at a point (tiles) is shut to people.
func _shut_at(sim, p: Vector2) -> bool:
	return int(sim.world.solid_p[floori(p.y) * sim.world.W + floori(p.x)]) != 0


func test_a_car_standing_in_its_bay_is_in_the_way_and_the_doors_are_not() -> void:
	# people walk round a parked car, not across its roof: its body is shut ground while it stands (parked, or its party
	# boarding or getting out), and open when it is driving or away; the places where people stand at its doors stay open
	var g := _game(_kinds_with_doors())
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	v["spot"] = 0
	sim.vehicles.sync_blocks()
	var body: Array = sim.vehicles.footprint_tiles(v)
	check(body.size() >= 6, "the sedan covers a handful of tiles: %d" % body.size())
	for i in body:
		check(int(sim.world.solid_p[int(i)]) != 0, "tile %d under the parked car is shut" % int(i))
	var centre: Vector2 = Convoy.bay(0)
	check(_shut_at(sim, centre), "the middle of the car is shut ground")
	for door in ["R1", "R2", "L1", "L2"]:
		var at: Vector2 = Convoy.door_spot(0, "sedan", door)
		check(not _shut_at(sim, at), "the place beside door %s (%.2f, %.2f) is open: people can stand there" % [door, at.x, at.y])
	# a party boarding it: still in the way; driving away: the ground is open again
	var party := _send(sim, ["dez"], String(v.id))
	sim.vehicles.sync_blocks()
	check(_shut_at(sim, centre), "while the party walks to it and boards: shut")
	party.state = "driving_out"
	sim.vehicles.sync_blocks()
	check(not _shut_at(sim, centre), "driving out: open")
	party.state = "away"
	sim.vehicles.sync_blocks()
	check(not _shut_at(sim, centre), "away: open")
	party.state = "driving_in"
	sim.vehicles.sync_blocks()
	check(not _shut_at(sim, centre), "driving in: open")
	party.state = "unloading"
	sim.vehicles.sync_blocks()
	check(_shut_at(sim, centre), "unloading: shut again, they step out beside it")
	# a car that is lost leaves nothing behind, and what was a wall stays a wall
	var wall_at := Vector2(36.0, 16.0)
	check(_shut_at(sim, wall_at), "(the wall is shut)")
	sim.vehicles.fleet.erase(v)
	sim.scavenge.parties.clear()
	sim.vehicles.sync_blocks()
	check(not _shut_at(sim, centre), "a car that is gone: open")
	check(_shut_at(sim, wall_at), "and the wall is as it was")
	_end(g)


func test_the_game_keeps_the_ground_under_parked_cars_shut_as_it_runs() -> void:
	var g := _game(_kinds_with_doors())
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("pickup")
	v["spot"] = 1
	_go(sim, 3)
	check(_shut_at(sim, Convoy.bay(1)), "after a few steps the pickup's bay is shut (the rules keep it so: no one has to ask)")
	_end(g)


func test_the_bay_ground_is_not_shut_in_a_game_with_no_vehicles() -> void:
	var g := _game()
	var sim = g.sim
	_go(sim, 3)
	for spot in Convoy.spots():
		check(not _shut_at(sim, Convoy.bay(spot)), "bay %d is open ground with no car in it" % spot)
	_end(g)
