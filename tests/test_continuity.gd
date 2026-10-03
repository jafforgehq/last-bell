extends "res://tests/case.gd"
## The colony keeps living while the player is in a place (round 17, slice 1, S1.3: scripts/sim/scavenge.gd `begin_played`,
## `finish_played`, `road_minutes`; scripts/sim/sim.gd `fast_forward`, `background_steps_for`; scripts/raid/raid_sim.gd
## `mirror`, `_hunt_allowed`). A played trip is "in_place" from the moment it begins to the moment the scene says what came
## of it; the people are away (they are gone from the base) all that time, the colony goes on (jobs, a night, the day's
## threat), and the road home is the abstract travel until the live drive (slice 5). Settlement game only.

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")
const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const CrewLoad := preload("res://scripts/sim/crew_load.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const FIXTURE := "user://test_continuity_town.json"
const STEP := 1.0 / 30.0

## Home is at (50, 35). The houses are an hour away on foot (9 tiles at 9 a hour); the garage holds a pickup; the city is
## across the river and cannot be reached on foot.
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


## A settlement game (three people: Ruth, Dez, Marcus) at `hour` of day 3 with the small town above, the waves off.
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


func _person(sim, id: String):
	return _crew(sim, [id])[0]


## Steps the colony until the scavenging module has no party left (or `limit` real seconds of its time).
func _until_home(sim, limit: float = 4000.0) -> void:
	var t := 0.0
	while not sim.scavenge.parties.is_empty() and t < limit:
		Helpers.run(sim, 1.0)
		t += 1.0


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


func _begin(sim, ids: Array, place: String = "houses", vehicle: String = "") -> Dictionary:
	return sim.scavenge.begin_played(_crew(sim, ids), place, "loot", vehicle)


func _played(extra: Dictionary = {}) -> Dictionary:
	var out := {"loot": {"food": 14, "scrap": 6}, "hurt": {}, "lost": [], "ammo_used": 0.0, "beats": ["Dez opened the cabinet."]}
	for k in extra:
		out[k] = extra[k]
	return out


func _end(g: Dictionary) -> void:
	g.world.free()


# ------------------------------------------------------------------ begin --

func test_begin_makes_the_people_away_and_the_party_in_place() -> void:
	var g := _game()
	var sim = g.sim
	var crew := _crew(sim, ["dez", "marcus"])
	var trips: int = sim.scavenge.trips
	var party: Dictionary = sim.scavenge.begin_played(crew, "houses", "loot", "")
	check(not party.is_empty(), "the party is made")
	eq(String(party.get("state", "")), "in_place", "in the place")
	check(bool(party.get("played", false)), "and played")
	eq(sim.scavenge.parties.size(), 1, "one party out")
	check(is_same(party, sim.scavenge.parties[0]), "the one the module keeps")
	eq(party.members, ["dez", "marcus"], "its members")
	eq(int(sim.scavenge.trips), trips + 1, "the trip is counted")
	for p in crew:
		check(p.away != null and is_same(p.away, party), "%s is away with the party at once" % p.first)
		check(sim.scavenge.goal_for(p) == null, "%s walks nowhere (they are gone)" % p.first)
		check(sim.scavenge.status_of(p).size() == 1, "%s is marked away" % p.first)
		check(String(sim.scavenge.status_of(p)[0].tip).contains("houses"), "and the tip says where: %s" % str(sim.scavenge.status_of(p)))
	check(sim.scavenge.raids.has("houses"), "the place is raided from now on")
	eq(sim.scavenge.party_in_place().get("n", -1), party.n, "the party being played is asked for")
	_end(g)


func test_begin_by_vehicle_takes_the_vehicle_and_burns_its_fuel_as_send_does() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	var need: float = sim.vehicles.fuel_for("houses", String(v.id))
	var party := _begin(sim, ["dez", "marcus"], "houses", String(v.id))
	check(not party.is_empty(), "it goes by sedan")
	near(sim.vehicles.fuel, 30.0 - need, 1e-9, "the fuel is burnt")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "out", "the sedan is out")
	eq(String(party.state), "in_place", "in the place (no walk to the car: the scene was the way)")
	eq(String(party.vehicle), String(v.id), "the party knows its vehicle")
	_end(g)


func test_begin_refuses_what_send_refuses_and_changes_nothing() -> void:
	var g := _game()
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 0.0
	var trips: int = sim.scavenge.trips
	var dez = _person(sim, "dez")
	var cases := {
		"nobody": [[], "houses", "loot", ""],
		"four people": [sim.people.duplicate() + sim.people.duplicate(), "houses", "loot", ""],
		"an unknown place": [[dez], "nowhere", "loot", ""],
		"a place across the river on foot": [[dez], "city", "loot", ""],
		"a vehicle with an empty tank": [[dez], "houses", "loot", String(v.id)],
		"a vehicle that does not exist": [[dez], "houses", "loot", "v99"],
		"a scouting trip (it is not played)": [[dez], "houses", "scout", ""],
		"an errand that is not one": [[dez], "houses", "dance", ""],
		"the same person twice": [[dez, dez], "houses", "loot", ""],
	}
	for what in cases:
		var c: Array = cases[what]
		check(not (c[0] as Array).is_empty() or what == "nobody", "(the case %s is made)" % what)
		var why: String = sim.scavenge.why_not_played(c[0], c[1], c[2], c[3])
		check(why != "", "%s: a reason is given" % what)
		check(sim.scavenge.begin_played(c[0], c[1], c[2], c[3]).is_empty(), "%s: refused" % what)
		if c[2] != "scout":
			check(not sim.scavenge.send(c[0], c[1], c[2], c[3]), "%s: send refuses it too" % what)
	eq(sim.scavenge.parties.size(), 0, "no party was made")
	eq(int(sim.scavenge.trips), trips, "no trip was counted")
	check(dez.away == null, "nobody is away")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the vehicle is still parked")
	near(sim.vehicles.fuel, 0.0, 1e-9, "no fuel was burnt")
	_end(g)


func test_begin_refuses_a_person_who_cannot_go_the_hour_the_dead_at_the_gate_and_a_second_place() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _person(sim, "dez")
	var marcus = _person(sim, "marcus")
	dez.downed = true
	check(_begin(sim, ["dez"]).is_empty(), "someone who is down cannot go")
	dez.downed = false
	# the departure hours of send
	sim.minutes = 11.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	check(_begin(sim, ["dez"]).is_empty(), "too late in the morning, as for send")
	sim.minutes = 22.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	check(_begin(sim, ["dez"]).is_empty(), "nobody goes out after dark")
	sim.minutes = 8.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	# the dead at the gate
	var gate: Vector2 = sim.scavenge.gate_center()
	for i in 3:
		sim.spawn(gate.x + float(i), gate.y - 8.0, "wander")
	check(_begin(sim, ["dez"]).is_empty(), "too many of the dead at the gate")
	sim.zombies.clear()
	check(not _begin(sim, ["dez"]).is_empty(), "and when they are gone, it goes")
	check(sim.scavenge.why_not_played([marcus], "garage", "loot", "") != "", "a second place is not played while one is")
	check(_begin(sim, ["marcus"], "garage").is_empty(), "so it is refused")
	check(_begin(sim, ["dez"]).is_empty(), "and the one who is gone cannot go again")
	_end(g)


func test_a_delegated_errand_may_go_while_the_player_is_in_a_place() -> void:
	var g := _game()
	var sim = g.sim
	check(not _begin(sim, ["dez"]).is_empty(), "the player's trip begins")
	check(sim.scavenge.send([_person(sim, "marcus")], "garage", "loot", ""), "and the dice's errand goes beside it")
	eq(sim.scavenge.parties.size(), 2, "two parties out")
	_end(g)


# --------------------------------------------------------- the base lives --

func test_the_colony_goes_on_while_they_are_in_the_place_and_a_night_falls_without_them() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var party := _begin(sim, ["dez", "marcus"])
	var dez = _person(sim, "dez")
	var marcus = _person(sim, "marcus")
	var ruth = _person(sim, "ruth")
	var at_dez := Vector2(dez.x, dez.y)
	var at_marcus := Vector2(marcus.x, marcus.y)
	var clock: float = sim.clock_min
	Helpers.run(sim, 60.0)    # three game hours
	near(float(sim.clock_min) - clock, 180.0, 1.0, "the colony's clock ran")
	eq(String(party.state), "in_place", "the party is still in the place (nothing calls it home)")
	eq(sim.scavenge.parties.size(), 1, "and still out")
	# the night
	Helpers.run_to_hour(sim, 21.5)
	eq(String(sim.phase), "night", "a night came")
	check(sim.bell_rung, "the bell rang")
	check(dez.away != null and marcus.away != null, "they are still away")
	near(Vector2(dez.x, dez.y).distance_to(at_dez), 0.0, 1e-9, "Dez did not move")
	near(Vector2(marcus.x, marcus.y).distance_to(at_marcus), 0.0, 1e-9, "nor did Marcus")
	check(ruth.away == null, "Ruth is home")
	check(Vector2(ruth.x, ruth.y).distance_to(sim.jobs.post_pos(ruth)) < 1.5, "and at her post on the wall")
	eq(String(party.state), "in_place", "the party is in the place all night")
	_end(g)


func test_away_people_do_not_hunger_bleed_or_turn_in_the_base_and_hold_no_post() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var marcus = _person(sim, "marcus")
	marcus.hunger_h = 3.0
	marcus.thirst_h = 2.0
	_begin(sim, ["marcus"])
	Helpers.run(sim, 90.0)
	near(marcus.hunger_h, 3.0, 1e-9, "no hunger while out (as for any trip)")
	near(marcus.thirst_h, 2.0, 1e-9, "no thirst")
	check(not sim.morale.breakdown(marcus), "no breakdown")
	eq(sim.morale.status_of(marcus).size(), 0, "no mood marks on a card that is away")
	# the day's threat: the crew goes to its posts, the one who is out does not
	sim.tactics.threat_until = float(sim.clock_min) + 200.0
	check(sim.threat_by_day(), "the dead are at the wall by day")
	var at := Vector2(marcus.x, marcus.y)
	Helpers.run(sim, 10.0)
	near(Vector2(marcus.x, marcus.y).distance_to(at), 0.0, 1e-9, "Marcus is not sent to a post from a place")
	check(sim.posts_manned(), "the others hold the posts")
	_end(g)


func test_the_seat_a_person_holds_is_theirs_again_and_free_meanwhile_the_duty_roster_marks_them_away() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var dez = _person(sim, "dez")
	var job: String = sim.jobs.job_of(dez)
	check(job != "", "(Dez has a seat: %s)" % job)
	var seats_free: int = sim.jobs.seats_left(job)
	_begin(sim, ["dez"])
	eq(sim.jobs.seats_left(job), seats_free + 1, "the seat counts as free while they are away")
	check(CrewLoad.on_trip(sim, dez), "the Duty roster counts them as on a trip")
	check(CrewLoad.away_in(sim, job).has("Dez"), "and says who is away from the station: %s" % str(CrewLoad.away_in(sim, job)))
	eq(sim.jobs.job_of(dez), job, "the job is kept")
	sim.scavenge.finish_played(sim.scavenge.party_in_place(), _played())
	_until_home(sim)
	check(dez.away == null, "Dez is back")
	eq(sim.jobs.job_of(dez), job, "and has the seat as before")
	eq(sim.jobs.seats_left(job), seats_free, "the station is as it was")
	_end(g)


func test_the_beds_still_count_the_people_who_are_in_a_place() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var size: int = sim.recruits.crew_size()
	var free: int = sim.recruits.housing_free()
	_begin(sim, ["dez", "marcus"])
	eq(sim.recruits.crew_size(), size, "they are still the crew")
	eq(sim.recruits.housing_free(), free, "and their beds are still taken")
	_end(g)


func test_the_player_may_lead_a_played_trip_though_the_dice_never_send_them() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	check(not sim.scavenge.can_go(ruth), "the dice's party never takes the player")
	check(not sim.scavenge.free_survivors().has(ruth), "and they are not among those who can be sent")
	check(not sim.scavenge.send([ruth], "houses", "loot", ""), "send refuses them")
	eq(sim.scavenge.why_not_played([ruth], "houses", "loot", ""), "", "a played trip takes them")
	var party := _begin(sim, ["ruth", "dez"])
	check(not party.is_empty(), "the player's trip begins")
	check(ruth.away != null, "Ruth is away")
	eq(sim.player_id, "ruth", "and is still the player: the avatar is in the place")
	_end(g)


func test_when_the_player_does_not_come_back_the_next_in_line_takes_over_on_the_return() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	var party := _begin(sim, ["ruth", "dez"])
	sim.scavenge.finish_played(party, _played({"lost": ["ruth"], "hp": {"dez": 50.0}}))
	var ruth = _person(sim, "ruth")
	check(not ruth.dead, "nobody knows on the road")
	_until_home(sim)
	check(ruth.dead, "Ruth did not come back")
	check(sim.player_id != "ruth" and sim.player_id != "", "someone else is the player now: %s" % sim.player_id)
	var players := 0
	for p in sim.people:
		if p.player:
			players += 1
			check(not p.dead, "the player lives")
	eq(players, 1, "exactly one player")
	_end(g)


func test_a_radio_stance_is_cleared_when_someone_leaves_for_a_place_and_the_others_keep_theirs() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _person(sim, "dez")
	var marcus = _person(sim, "marcus")
	dez.stance = "follow"
	marcus.stance = "hold"
	_begin(sim, ["dez"])
	eq(dez.stance, "", "no stance once they are gone")
	eq(marcus.stance, "hold", "the one at home keeps theirs")
	sim.scavenge.finish_played(sim.scavenge.party_in_place(), _played())
	_until_home(sim)
	eq(dez.stance, "", "and none when they are home")
	_end(g)


# ----------------------------------------------------------------- finish --

func test_finish_puts_the_result_in_applies_wounds_hp_and_skills_and_sets_the_road_home() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var dez = _person(sim, "dez")
	var marcus = _person(sim, "marcus")
	var party := _begin(sim, ["dez", "marcus"])
	var ammo: float = sim.stock.ammo
	var food: float = sim.stock.food
	var shooting := int(dez.skills.Shooting)
	var result := _played({"hurt": {"marcus": "bite"}, "hp": {"dez": 62.0, "marcus": 31.0}, "skills": {"dez": {"Shooting": 1}}, "ammo_used": 40.0, "clear": true})
	Helpers.run(sim, 30.0)    # an hour and a half in the place
	var now: float = sim.clock_min
	sim.scavenge.finish_played(party, result)
	eq(String(party.state), "away", "on the road home")
	near(float(party.return_at) - now, sim.town.hours_to("houses") * 60.0, 1.0, "the road is the way there: %.1f minutes" % (float(party.return_at) - now))
	near(float(party.return_at) - now, 60.0, 1.0, "an hour on foot to the houses")
	near(sim.stock.ammo, ammo - 40.0, 0.001, "the ammo they used is gone")
	eq(int(dez.skills.Shooting), shooting + 1, "Dez shoots better for the day")
	near(dez.hp, 62.0, 0.001, "Dez's health is what it was when he left the place")
	near(marcus.hp, 31.0, 0.001, "and Marcus's")
	check(dez.away != null and marcus.away != null, "they are still on the road")
	check(party.result.loot.has("food"), "the loot is in the party's result")
	check(bool(party.result.get("clear", false)), "and the clearing")
	_until_home(sim)
	check(dez.away == null and marcus.away == null, "they are home")
	var gate: Vector2 = sim.scavenge.gate_center()
	check(Vector2(dez.x, dez.y).distance_to(gate) < 3.0, "at the gate")
	check(marcus.wounds >= 1 and marcus.bleeding > 0.0, "Marcus was bitten: a wound is on him")
	check(sim.stock.food > food + 8.0, "the food is in the stores (less what the base ate): %.1f from %.1f" % [sim.stock.food, food])
	eq(sim.town.state_of("houses"), "cleared", "the place is cleared")
	_end(g)


func test_finish_cuts_a_forged_result_down_and_tolerates_a_result_with_no_new_keys() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var dez = _person(sim, "dez")
	var party := _begin(sim, ["dez"])
	var shooting := int(dez.skills.Shooting)
	var leading := int(dez.skills.Leading)
	sim.scavenge.finish_played(party, {
		"loot": {"food": 99999, "bogus": 5}, "hurt": {"nobody": "bite"}, "lost": ["ghost"], "ammo_used": -500.0,
		"hp": {"dez": 9999.0, "ghost": 3.0}, "skills": {"dez": {"Shooting": 99, "Leading": 5, "Bogus": 2}, "ghost": {"Shooting": 3}},
	})
	eq(int(party.result.loot.food), 400, "the loot is capped")
	check(not party.result.loot.has("bogus") and party.result.hurt.is_empty() and party.result.lost.is_empty(), "names that are not the party's are dropped")
	near(dez.hp, 100.0, 0.001, "health stays within 100")
	eq(int(dez.skills.Shooting), mini(shooting + 3, int(sim.skills.cap_of(dez, "Shooting"))), "a skill gains at most what a run can give")
	eq(int(dez.skills.Leading), leading, "Leading does not grow")
	_end(g)
	var h := _game(8.0)
	var s2 = h.sim
	var p2 := _begin(s2, ["dez"])
	var hp: float = _person(s2, "dez").hp
	s2.scavenge.finish_played(p2, {"loot": {"food": 5}, "hurt": {}, "lost": []})
	near(_person(s2, "dez").hp, hp, 1e-9, "a result with no hp keeps the health as it was")
	eq(String(p2.state), "away", "and the party is on the road")
	_end(h)


func test_a_trip_by_vehicle_comes_home_by_vehicle_after_half_the_round_trip() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	var party := _begin(sim, ["dez", "marcus"], "houses", String(v.id))
	var now: float = sim.clock_min
	var road: float = sim.vehicles.drive_hours("houses", String(v.id)) / 2.0 * 60.0
	near(sim.scavenge.road_minutes("houses", String(v.id)), road, 1e-9, "road_minutes is half the round trip")
	sim.scavenge.finish_played(party, _played({"hurt": {"marcus": "scratch"}}))
	eq(String(party.state), "away", "on the road")
	near(float(party.return_at) - now, road, 1.0, "back after the sedan's half hour or so")
	check(float(party.return_at) - now < 60.0, "shorter than on foot")
	var states := _states_until_home(sim)
	eq(states, ["away", "driving_in", "unloading"], "the car drives in and they get out")
	eq(String(sim.vehicles.vehicle(String(v.id)).state), "parked", "the sedan is parked")
	for p in _crew(sim, ["dez", "marcus"]):
		check(p.away == null, "%s is home" % p.first)
	_end(g)


func test_the_road_home_on_foot_is_the_way_there_and_a_party_finished_at_night_comes_in_by_day() -> void:
	var g := _game(8.0)
	var sim = g.sim
	near(sim.scavenge.road_minutes("houses", ""), 60.0, 1e-6, "an hour to the houses")
	near(sim.scavenge.road_minutes("garage", ""), 60.0, 1e-6, "an hour to the garage")
	var party := _begin(sim, ["dez"])
	Helpers.run_to_hour(sim, 22.0)
	eq(String(sim.phase), "night", "it is night")
	sim.scavenge.finish_played(party, _played())
	Helpers.run(sim, 90.0)    # four and a half hours of the dark
	check(sim.scavenge.parties.size() == 1, "they do not walk in through the night")
	Helpers.run_to_hour(sim, 8.0)
	_until_home(sim, 200.0)
	check(sim.scavenge.parties.is_empty(), "they come in after dawn")
	_end(g)


func test_finish_twice_or_on_what_is_not_in_a_place_is_harmless() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var dez = _person(sim, "dez")
	var party := _begin(sim, ["dez"])
	var ammo: float = sim.stock.ammo
	var shooting := int(dez.skills.Shooting)
	sim.scavenge.finish_played(party, _played({"ammo_used": 10.0, "skills": {"dez": {"Shooting": 1}}}))
	var due: float = float(party.return_at)
	var loot: int = int(party.result.loot.food)
	var ammo_after: float = sim.stock.ammo
	near(ammo_after, ammo - 10.0, 0.001, "the ammo of the first finish")
	sim.scavenge.finish_played(party, _played({"loot": {"food": 300}, "ammo_used": 50.0, "skills": {"dez": {"Shooting": 2}}}))
	sim.scavenge.finish_played(int(party.n), _played({"loot": {"food": 300}, "ammo_used": 50.0}))
	near(float(party.return_at), due, 1e-9, "the return is not moved")
	eq(int(party.result.loot.food), loot, "the result is not replaced")
	near(sim.stock.ammo, ammo_after, 1e-9, "the ammo is not taken twice")
	eq(int(dez.skills.Shooting), mini(shooting + 1, int(sim.skills.cap_of(dez, "Shooting"))), "the skill is not gained twice")
	_until_home(sim)
	var food: float = sim.stock.food
	sim.scavenge.finish_played(party, _played({"loot": {"food": 300}}))
	sim.scavenge.finish_played(7, {})
	sim.scavenge.finish_played({}, {})
	sim.scavenge.finish_played("nonsense", {})
	near(sim.stock.food, food, 1e-9, "a party that is home is not finished again")
	# a trip of the dice's is not one to finish
	var g2 := _game(8.0)
	var s2 = g2.sim
	check(s2.scavenge.send([_person(s2, "dez")], "houses", "loot", ""), "(a dice trip)")
	var dice: Dictionary = s2.scavenge.parties[0]
	var state := String(dice.state)
	s2.scavenge.finish_played(dice, _played())
	eq(String(dice.state), state, "a dice trip is not touched")
	_end(g2)
	_end(g)


func test_everyone_lost_in_the_place_is_told_at_once_and_the_vehicle_is_lost_with_them() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	var party := _begin(sim, ["dez", "marcus"], "houses", String(v.id))
	sim.alerts.clear()
	sim.events.clear()
	sim.scavenge.finish_played(party, _played({"loot": {"food": 20}, "lost": ["dez", "marcus"]}))
	eq(sim.scavenge.parties.size(), 0, "nobody is coming home: the party is settled at once")
	for p in _crew(sim, ["dez", "marcus"]):
		check(p.dead, "%s is dead" % p.first)
		check(p.away is Dictionary and String(p.away.get("kind", "")) == "lost", "and left at the place")
	eq(sim.vehicles.fleet.size(), 0, "the sedan is lost with them")
	var told := false
	for e in sim.events:
		if e.type == "banner" and String(e.text).contains("did not come back"):
			told = true
	check(told, "the banner says so")
	check(sim.alerts.has("scav-%d" % int(party.n)), "and the alert")
	check(sim.stock.food <= 40.0 + 1e-6, "(no loot came of it)")
	_end(g)


func test_one_lost_and_one_home_the_lost_is_told_on_the_return() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var party := _begin(sim, ["dez", "marcus"])
	sim.scavenge.finish_played(party, _played({"lost": ["marcus"], "hp": {"dez": 40.0}}))
	var marcus = _person(sim, "marcus")
	check(not marcus.dead, "not yet: they do not know on the road")
	eq(sim.scavenge.parties.size(), 1, "the party walks home")
	_until_home(sim)
	check(marcus.dead, "Marcus did not come back")
	check(not _person(sim, "dez").dead and _person(sim, "dez").away == null, "Dez did")
	_end(g)


# ------------------------------------------------------------------ saves --

func test_a_save_in_the_place_loads_as_a_trip_that_came_back_with_nothing() -> void:
	var a := _game(8.0)
	var sim = a.sim
	var v: Dictionary = sim.vehicles.add("sedan")
	sim.vehicles.fuel = 30.0
	var party := _begin(sim, ["dez", "marcus"], "houses", String(v.id))
	Helpers.run(sim, 20.0)
	var text: String = SaveGame.to_text(SaveGame.to_dict(sim))
	var d: Dictionary = SaveGame.from_text(text)
	_write(TOWN)
	Town.data_path = FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "it loads")
	var s2 = b.sim
	eq(s2.scavenge.parties.size(), 1, "the party is there")
	eq(String(s2.scavenge.parties[0].state), "in_place", "in the place (the scene is not saved)")
	check(bool(s2.scavenge.parties[0].get("played", false)), "and played")
	for p in _crew(s2, ["dez", "marcus"]):
		check(p.away != null and is_same(p.away, s2.scavenge.parties[0]), "%s is away with it" % p.first)
	eq(String(s2.vehicles.vehicle(String(v.id)).state), "out", "the sedan is out")
	# the next step: the place is gone, so they turn back with nothing
	var food: float = s2.stock.food
	s2.update(STEP)
	eq(String(s2.scavenge.parties[0].state), "away", "they are on the road home")
	check(s2.scavenge.parties[0].result.loot.is_empty(), "with nothing")
	near(float(s2.scavenge.parties[0].return_at) - float(s2.clock_min), s2.scavenge.road_minutes("houses", String(v.id)), 1.0, "after the road")
	var states := _states_until_home(s2)
	eq(states, ["away", "driving_in", "unloading"], "the car comes in")
	for p in _crew(s2, ["dez", "marcus"]):
		check(p.away == null and not p.dead, "%s is home, whole" % p.first)
	eq(String(s2.vehicles.vehicle(String(v.id)).state), "parked", "the sedan is parked")
	check(s2.stock.food <= food, "nothing was brought")
	_end(a)
	_end(b)


func test_a_save_in_the_place_on_foot_loads_and_the_people_come_home() -> void:
	var a := _game(8.0)
	var sim = a.sim
	_begin(sim, ["dez"])
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	_write(TOWN)
	Town.data_path = FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "it loads")
	var s2 = b.sim
	eq(String(s2.scavenge.parties[0].state), "in_place", "in the place after the load")
	_until_home(s2)
	var dez = _person(s2, "dez")
	check(dez.away == null and not dez.dead, "Dez is home")
	_end(a)
	_end(b)


# ----------------------------------------------------------- fast_forward --

func test_fast_forward_runs_the_colony_the_minutes_asked_and_returns_what_is_left() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var c0: float = sim.clock_min
	var left: float = sim.fast_forward(30.0)
	near(left, 0.0, 1e-6, "nothing left of thirty minutes")
	near(float(sim.clock_min) - c0, 30.0, 1e-6, "exactly thirty minutes passed")
	near(float(sim.hour), 8.5, 1e-6, "the clock says so")
	# the cap: 500 steps are 50 game minutes
	c0 = sim.clock_min
	left = sim.fast_forward(180.0, 500)
	near(float(sim.clock_min) - c0, 50.0, 1e-6, "a call does at most its steps: 50 minutes")
	near(left, 130.0, 1e-6, "and says how much is left")
	# spread over frames
	var calls := 0
	while left > 1e-6 and calls < 20:
		left = sim.fast_forward(left, 500)
		calls += 1
	near(left, 0.0, 1e-6, "all done")
	eq(calls, 3, "in three more calls of 50, 50 and 30")
	near(float(sim.clock_min) - c0, 180.0, 1e-6, "180 minutes in all")
	near(sim.fast_forward(0.0), 0.0, 0.0, "nothing to do is nothing left")
	near(sim.fast_forward(-5.0), 0.0, 0.0, "and a negative number is nothing too")
	_end(g)


func test_fast_forward_crosses_a_night_and_the_base_goes_through_it() -> void:
	var g := _game(17.0)
	var sim = g.sim
	var days: int = sim.day
	var left: float = sim.fast_forward(15.0 * 60.0, 20000)
	near(left, 0.0, 1e-6, "fifteen hours")
	check(sim.day > days, "the next day began")
	check(sim.events.filter(func(e): return e.type == "bell").size() >= 1, "the bell was among the events kept")
	_end(g)


func test_fast_forward_drops_the_sounds_and_the_drawing_and_gives_the_effects_back() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	ruth.drafted = true    # (she shoots what is in reach, by day too)
	for i in 3:
		sim.spawn(ruth.x + 4.0 + float(i), ruth.y, "wander")
	var fx_before = sim.fx
	var counter := FxCounter.new()
	sim.fx = counter
	Helpers.run(sim, 4.0)
	check(counter.n > 0, "(sanity: a step of the colony does draw: %d calls)" % counter.n)
	counter.n = 0
	sim.events.clear()
	for i in 4:
		sim.spawn(ruth.x + 4.0 + float(i), ruth.y + 1.0, "wander")
	sim.fast_forward(120.0)
	check(is_same(sim.fx, counter), "the effects are put back")
	eq(counter.n, 0, "nothing was drawn meanwhile")
	for e in sim.events:
		check(not ["groan", "shot", "claw", "hammer", "stab", "thud", "reload"].has(String(e.type)), "no sound-only event is kept: %s" % e.type)
	sim.fx = fx_before
	_end(g)


func test_fast_forward_stops_when_the_run_is_over() -> void:
	var g := _game(8.0)
	var sim = g.sim
	sim.over = "defeat"
	var c0: float = sim.clock_min
	near(sim.fast_forward(60.0), 0.0, 0.0, "nothing is left to ask for")
	near(float(sim.clock_min), c0, 0.0, "and the clock stood")
	_end(g)


func test_the_radio_runs_during_a_fast_forward_once_a_step_and_collects_its_news() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var counting := CountingRadio.new()
	counting.setup(sim)
	counting.start()
	sim.radio = counting
	var left: float = sim.fast_forward(20.0)
	near(left, 0.0, 1e-6, "twenty minutes")
	eq(counting.updates, 200, "the radio took its turn in every one of the 200 colony steps (it collects its news inside `update`)")
	_end(g)


## The radio of the colony with a count of its turns (the module collects its news inside `update`, which the fast-forward
## runs like any step).
class CountingRadio:
	extends "res://scripts/sim/radio.gd"
	var updates := 0

	func update(dt: float) -> void:
		updates += 1
		super.update(dt)


class FxCounter:
	extends RefCounted
	var n := 0

	func blood(_x: float, _y: float, _dx: float, _dy: float, _c: int = 10) -> void:
		n += 1

	func decal(_x: float, _y: float, _s: float, _g: float = 0.0) -> void:
		n += 1

	func hit_material(_x: float, _y: float, _k: String) -> void:
		n += 1

	func muzzle(_x: float, _y: float, _a: float, _b: bool) -> void:
		n += 1

	func tracer(_a: float, _b: float, _c: float, _d: float) -> void:
		n += 1

	func casing(_x: float, _y: float, _a: float, _b: bool) -> void:
		n += 1

	func smoke(_x: float, _y: float, _s: float, _d: bool) -> void:
		n += 1

	func ember(_x: float, _y: float) -> void:
		n += 1

	func update(_dt: float) -> void:
		pass


func test_the_place_steps_to_colony_steps_ratio_is_one_game_minute_per_real_second() -> void:
	eq(Sim.PLACE_STEP_RATIO, 3, "one colony step in three place steps")
	eq(Sim.background_steps_for(0), 0, "none")
	eq(Sim.background_steps_for(2), 0, "two place steps are not yet a colony step")
	eq(Sim.background_steps_for(3), 1, "three are one")
	eq(Sim.background_steps_for(7), 2, "seven are two")
	eq(Sim.background_steps_for(300), 100, "ten seconds of place are a hundred colony steps")
	eq(Sim.background_steps_for(-4), 0, "never negative")
	var g := _game(8.0)
	near(float(g.sim.min_per_sec) / float(Sim.PLACE_STEP_RATIO), 1.0, 1e-9, "one game minute per real second at the place's 30 steps a second")
	var c0: float = g.sim.clock_min
	for i in Sim.background_steps_for(30 * 10):
		g.sim.update(STEP)
	near(float(g.sim.clock_min) - c0, 10.0, 1e-6, "ten seconds in a place are ten game minutes in the base")
	_end(g)


# --------------------------------------------------- the place's own clock --

## A site 30 x 16 of open ground with a house, as tests/test_raid_run.gd makes one.
func _site(dead: Array = []) -> Dictionary:
	var w := 30
	var h := 16
	var data: Dictionary = GD.load_all().duplicate(true)
	var terrain: Array = []
	var solid: Array = []
	for y in h:
		for x in w:
			terrain.append(1)
			var wall := (x >= 14 and x <= 24 and y >= 3 and y <= 12) and (x == 14 or x == 24 or y == 3 or y == 12) and not (x == 14 and y == 8)
			solid.append(1 if wall else 0)
	data["W"] = w
	data["H"] = h
	data["terrain"] = terrain
	data["solidZ"] = solid.duplicate()
	data["solidP"] = solid.duplicate()
	data["objects"] = []
	data["walls"] = []
	data["marks"] = []
	data["lights"] = []
	data["trees"] = []
	data["segments"] = []
	data["people"] = []
	data["spawns"] = []
	return {
		"name": "A test house", "kind": "houses", "danger": 2, "size": Vector2i(w, h), "data": data,
		"entry": Vector2(3.5, 8.5), "exit": Rect2(1.0, 6.5, 5.0, 4.0), "vehicle_spot": Vector2(-1, -1),
		"containers": [{"id": "c1", "pos": Vector2(16.5, 6.5), "at": Vector2(16.5, 5.5), "kind": "cabinet", "loot": {"food": 10}, "search_s": 4.0, "room": "hall"}],
		"dead": dead, "rooms": [{"name": "hall", "rect": Rect2(15, 4, 9, 8)}], "seed": 1,
	}


func _place(g: Dictionary, size: int = 2) -> Dictionary:
	var site := _site()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(site.data)
	var members: Array = []
	for i in size:
		var p = g.sim.people[i]
		members.append({"def": p.def, "hp": 100.0, "skills": p.skills})
	var run = RaidRun.new(site, world, FxNull.new(), members, 300.0, "", 1.0, false)
	return {"run": run, "world": world}


func test_a_place_mirrors_the_colonys_clock() -> void:
	var g := _game(8.0)
	var colony = g.sim
	var p := _place(g)
	var place = p.run.sim
	colony.day = 5
	colony.minutes = 22.5 * 60.0
	colony.clock_min = 4.0 * 1440.0 + 22.5 * 60.0 - 420.0
	colony.phase = "night"
	colony.bell_rung = true
	place.mirror(colony)
	eq(place.day, 5, "the day")
	near(float(place.minutes), 22.5 * 60.0, 1e-9, "the minutes of the day")
	near(float(place.clock_min), float(colony.clock_min), 1e-9, "the run's clock")
	near(float(place.hour), 22.5, 1e-9, "the hour")
	eq(String(place.phase), "night", "the phase")
	check(place.bell_rung, "the bell")
	colony.update(STEP)
	place.mirror(colony)
	near(float(place.minutes), float(colony.minutes), 1e-9, "and again after a step")
	colony.bell_rung = false
	colony.phase = "day"
	place.mirror(colony)
	check(not place.bell_rung and String(place.phase) == "day", "each call copies it all")
	p.world.free()
	_end(g)


func test_the_dead_of_a_place_hunt_at_night_but_the_yards_stragglers_still_give_up_after_dark() -> void:
	var g := _game(8.0)
	var colony = g.sim
	colony.minutes = 23.0 * 60.0
	colony.phase = "night"
	colony.bell_rung = true
	# the yard's rule stays as it was: a straggler that hunts someone gives up at night
	var z0 = colony.spawn(10.0, 10.0, "hunt")
	z0.hunt_id = "ruth"
	colony.update(STEP)
	eq(String(z0.state), "wander", "in the yard a hunt ends at nightfall")
	# in a place it goes on
	var p := _place(g)
	var run = p.run
	run.sim.mirror(colony)
	eq(String(run.sim.phase), "night", "the place is at night")
	var victim = run.squad[0]
	var z = run.sim.spawn(victim.x + 5.0, victim.y, "hunt")
	z.hunt_id = String(victim.id)
	z.hp = 10000.0    # (a hunter the squad cannot put down in the seconds this takes)
	for i in 120:
		run.update(STEP)
		run.sim.mirror(colony)
		if z.state != "hunt":
			failures.append("the hunter gave up at night, step %d: %s" % [i, z.state])
			break
	p.world.free()
	_end(g)


func test_the_squad_stands_where_it_is_at_night_not_off_to_a_wall_post() -> void:
	var g := _game(8.0)
	var colony = g.sim
	colony.minutes = 23.0 * 60.0
	colony.phase = "night"
	colony.bell_rung = true
	var p := _place(g)
	var run = p.run
	run.sim.mirror(colony)
	var first = run.squad[0]
	var at := Vector2(first.x, first.y)
	check(not run.sim.posts_manned(), "a place has no posts to man")
	for i in 90:
		run.update(STEP)
	near(Vector2(first.x, first.y).distance_to(at), 0.0, 0.2, "nobody was sent to the yard's posts")
	# and the yard's own rule is as it was
	check(colony.posts_manned(), "the yard mans its posts at night")
	p.world.free()
	_end(g)
