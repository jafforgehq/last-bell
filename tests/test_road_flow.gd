extends "res://tests/case.gd"
## The flow of a live trip (round 21, slice 5, S21.4: scripts/raid/place_flow.gd): a trip the player leads is a drive, a place and
## a drive. The scene (scripts/drive/drive_scene.gd) is played by hand and is the DRIVE-SCENE builder's, so here a few lines stand in
## for it: they step the flow the way the scene does (`begin_leg`, `leg_step` once per scene step, `end_leg` with a leg's result)
## and the rest is the colony's own rules (scavenge.gd, vehicles.gd). What a leg's result looks like is in place_flow.gd's header.
## The old overlay's road (`road_step`) is tests/test_place_flow.gd's and stays as it was.

const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const DriveKit := preload("res://tests/drive_kit.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")

const FIXTURE := "user://test_r21_flow_town.json"
const DRIVE_SCENE := "res://scripts/drive/drive_scene.gd"
const STEP := 1.0 / 30.0

## Home is at (50, 35). The houses are an hour away on foot (9 tiles at 9 a hour), the pharmacy three. By pickup (speed 2.2) the
## houses are 27.3 minutes of road and the pharmacy 81.8.
const TOWN := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [59, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
		{"id": "pharmacy", "name": "The pharmacy", "kind": "pharmacy", "pos": [77, 35], "blurb": "Shelves and a shutter.", "danger": 2, "known": true,
			"loot": {"meds": [4, 8], "scrap": [6, 10]}, "extra": {}},
	],
	"roads": [["home", "houses"], ["home", "pharmacy"]],
	"beats": [],
}


## What the place's Sim is given every colony step (raid_sim.gd `mirror`): the colony's clock.
class FakeRunSim:
	extends RefCounted
	var mirrored := 0
	var clock_min := 0.0
	var phase := ""

	func mirror(colony) -> void:
		mirrored += 1
		clock_min = float(colony.clock_min)
		phase = String(colony.phase)


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game of three (Ruth, Dez, Marcus) at `hour` of day 3 with the small town above, Ruth the avatar, a pickup in the
## fleet and fuel in the tank. The live drive is switched ON (the round 17 tests switch it off and nothing puts it back).
func _game(hour: float = 8.0, avatar: bool = true) -> Dictionary:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	_write(FIXTURE, TOWN)
	Town.data_path = FIXTURE
	var g := Helpers.make(17, 1, 3)
	Town.data_path = Town.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	_set_hour(sim, hour)
	sim.bell_rung = false
	sim.supplies.sources_day = 3
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.events.clear()
	sim.vehicles.fuel = 40.0
	if avatar:
		sim.avatar.set_player("ruth")
		sim.radio.start()
	g["vehicle"] = String(sim.vehicles.add("pickup").id)
	sim.events.clear()
	return g


func _set_hour(sim, hour: float) -> void:
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.clock_min = (int(sim.day) - 1) * 1440.0 + fposmod(sim.minutes - 420.0, 1440.0)


func _end(g: Dictionary) -> void:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	g.world.free()


func _person(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _ids(list: Array) -> Array:
	var out: Array = []
	for p in list:
		out.append(String(p.id))
	return out


## A live trip begun: `ids` go to `place` in `vehicle` (an id of the fleet, "" on foot).
func _trip(g: Dictionary, ids: Array, place: String = "houses", vehicle: String = "") -> Variant:
	var sim = g.sim
	var crew: Array = []
	for id in ids:
		crew.append(_person(sim, id))
	var flow = PlaceFlow.new(sim)
	check(flow.begin(crew, place, vehicle), "the trip begins: %s" % flow.error)
	flow.live = PlaceFlow.live_for(sim)
	return flow


## The scene's steps of a leg for `seconds` of its time (30 a second): what DriveScene's `_place_step` does. The colony steps taken.
func _drive(flow, run_sim, seconds: float) -> int:
	var took := 0
	for i in int(round(seconds * 30.0)):
		took += flow.leg_step(run_sim)
	return took


## A leg's result as the scene gives it, with what a test changes.
func _leg(extra: Dictionary = {}) -> Dictionary:
	var out := {"hp": {}, "lost": [], "hurt": {}, "ammo_used": 0.0, "vehicle_hp_lost": 0.0, "wrecked": false, "failed": false, "beats": [], "leader": ""}
	for k in extra:
		out[k] = extra[k]
	return out


## A place's result as a RaidRun gives it.
func _place(extra: Dictionary = {}) -> Dictionary:
	var out := {"loot": {"food": 14}, "hurt": {}, "lost": [], "ammo_used": 5.0, "beats": ["Dez opened the cabinet."], "hp": {"ruth": 90.0, "dez": 80.0}, "leader": "ruth"}
	for k in extra:
		out[k] = extra[k]
	return out


## Steps the colony until the scavenging module has no party left (or `limit` seconds of its time); true if it is home.
func _until_home(sim, limit: float = 4000.0) -> bool:
	var t := 0.0
	while not sim.scavenge.parties.is_empty() and t < limit:
		Helpers.run(sim, 1.0)
		t += 1.0
	return sim.scavenge.parties.is_empty()


func _news_text(flow) -> String:
	return "\n".join(flow.news_lines(20))


## Whether the scavenging module has the additions of EVENTS (S21.1: `hold_on_road`, `amend_result`, `arrive_home`) and the vehicles
## those of `road_wear`, `wreck` and `fuel_per_leg`: a test that needs them fails when they are not in.
func _has_events_api(sim) -> bool:
	var ok: bool = sim.scavenge.has_method("hold_on_road") and sim.scavenge.has_method("amend_result") and sim.scavenge.has_method("arrive_home") \
		and sim.vehicles.has_method("road_wear") and sim.vehicles.has_method("wreck") and sim.vehicles.has_method("fuel_per_leg")
	check(ok, "EVENTS' additions to scavenge.gd and vehicles.gd are in")
	return ok


func _kinds() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicles.json"))
	return parsed.get("kinds", {})


# ------------------------------------------------------------ the pace rule --

func test_the_pace_helpers_give_the_plans_numbers() -> void:
	near(PlaceFlow.leg_seconds(10.0), 30.0, 1e-9, "a short road takes at least 30 s")
	near(PlaceFlow.leg_seconds(80.0), 80.0, 1e-9, "an 80 minute road is 80 s")
	near(PlaceFlow.leg_seconds(185.0), 90.0, 1e-9, "and never more than 90")
	near(PlaceFlow.leg_seconds(400.0), 90.0, 1e-9, "(the longest walk too)")
	near(PlaceFlow.pace_for(80.0), 1.0, 1e-9, "pace 1.0: a game minute a real second, the place's own 1:3")
	near(PlaceFlow.pace_for(36.0), 1.0, 1e-9, "a 36 minute run is 36 s: pace 1.0 (the plan's '30 s, pace 1.2' contradicts its own clamp)")
	near(PlaceFlow.pace_for(24.0), 0.8, 1e-9, "a 24 minute run is held to 30 s: pace 0.8")
	near(PlaceFlow.pace_for(185.0), 185.0 / 90.0, 1e-9, "a 185 minute run is 90 s: pace 2.1")
	near(PlaceFlow.pace_for(400.0), 400.0 / 90.0, 1e-9, "the longest walk: pace 4.4")
	var kinds := _kinds()
	near(PlaceFlow.cruise_of(kinds.sedan), 3.2 * 2.4, 1e-9, "a sedan cruises at 7.7 tiles a second")
	near(PlaceFlow.cruise_of(kinds.pickup), 3.2 * 2.2, 1e-9, "a pickup at 7.0")
	near(PlaceFlow.cruise_of(kinds.van), 3.2 * 2.2, 1e-9, "a van at 7.0")
	near(PlaceFlow.cruise_of(kinds.bus), 3.2 * 1.8, 1e-9, "a bus at 5.8")
	near(PlaceFlow.cruise_of({}), 3.2, 1e-9, "on foot the avatar's own walk, 3.2")
	eq(PlaceFlow.strip_len(80.0, 7.04), 563, "an 80 minute pickup run is 563 tiles (80 s at cruise)")
	eq(PlaceFlow.strip_len(185.0, 3.2 * 2.4), 691, "a long one 90 s at cruise")
	eq(PlaceFlow.strip_len(400.0, 3.2), 288, "the longest walk 288 tiles")
	eq(PlaceFlow.strip_len(400.0, 20.0), PlaceFlow.MAX_STRIP, "and no strip is longer than the cap")
	eq(PlaceFlow.MAX_STRIP, 700, "(700)")
	near(PlaceFlow.TOP_FACTOR, 1.5, 1e-9, "top speed is 1.5 times cruise")
	near(PlaceFlow.LEG_MIN_S, 30.0, 1e-9, "the shortest leg")
	near(PlaceFlow.LEG_MAX_S, 90.0, 1e-9, "the longest")


func test_the_live_drive_is_for_a_player_with_an_avatar_and_the_overlay_stays_for_the_rest() -> void:
	var g := _game()
	var sim = g.sim
	check(PlaceFlow.live_for(sim), "an avatar, the drive on and no --fastroad: live")
	PlaceFlow.live_enabled = false
	check(not PlaceFlow.live_for(sim), "the tests of the overlay switch it off")
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = true
	check(not PlaceFlow.live_for(sim), "--fastroad keeps the overlay")
	PlaceFlow.fast_road = false
	sim.player_id = ""
	check(not PlaceFlow.live_for(sim), "with no avatar nothing changes: nobody drives")
	check(not PlaceFlow.no_events, "(and the roads' events are on by default)")
	_end(g)


# ----------------------------------------------------- the legs in sequence --

func test_a_trip_is_a_drive_a_place_and_a_drive_in_that_order() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	check(flow.live, "the flow is live")
	var run := FakeRunSim.new()
	eq(flow.stage, "road_there", "begun")
	flow.begin_leg("there")
	eq(flow.stage, "drive_there", "the drive there")
	_drive(flow, run, 4.0)
	flow.end_leg(_leg())
	eq(flow.stage, "place", "then the place")
	flow.arrive()
	eq(flow.stage, "place", "(arriving is the same stage)")
	var played: Dictionary = flow.merge_road(_place())
	flow.finish(played)
	flow.begin_leg("home")
	eq(flow.stage, "drive_home", "then the drive home")
	_drive(flow, run, 4.0)
	flow.end_leg(_leg())
	eq(flow.stage, "home", "and the base")
	flow.home()
	eq(flow.stage, "home", "home")
	check(not flow.failed, "nobody failed on the road")
	check(_until_home(sim), "and the colony takes them in")
	_end(g)


func test_the_party_is_in_place_from_the_gate_to_the_places_end() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	var dez = _person(sim, "dez")
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	eq(String(flow.party.state), "in_place", "in place from the gate")
	check(ruth.away != null and dez.away != null, "the people are gone from the base")
	eq(String(sim.vehicles.vehicle(g.vehicle).state), "out", "and the car is out")
	var run := FakeRunSim.new()
	flow.begin_leg("there")
	_drive(flow, run, 20.0)
	eq(String(flow.party.state), "in_place", "still in place on the road there")
	flow.end_leg(_leg())
	flow.arrive()
	eq(String(flow.party.state), "in_place", "and in the place")
	flow.finish(flow.merge_road(_place()))
	eq(String(flow.party.state), "away", "on the road home from the place's end")
	_end(g)


# ------------------------------------------------------ the colony behind it --

func test_the_colony_takes_a_step_for_every_three_of_the_legs_at_pace_one() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", "")
	flow.begin_leg("there")
	near(flow.leg_road_min, 60.0, 1e-6, "the houses on foot are an hour")
	near(flow.leg_pace, 1.0, 1e-9, "a 60 second leg: pace 1.0")
	var run := FakeRunSim.new()
	var clock0: float = sim.clock_min
	var took := _drive(flow, run, 30.0)
	eq(flow.leg_steps, 900, "900 steps of the scene")
	eq(took, 300, "300 of the colony's: one in three")
	eq(flow.leg_colony, 300, "counted")
	eq(run.mirrored, 300, "the road's scene is given the colony's clock after each one")
	near(float(sim.clock_min) - clock0, 30.0, 1e-6, "a second of the leg is a minute of the day")
	near(flow.elapsed_min(), 30.0, 1e-6, "and the clock says so: steps x 0.1")
	near(run.clock_min, float(sim.clock_min), 1e-9, "the scene has the colony's clock")
	_end(g)


func test_a_long_road_runs_the_colony_faster_and_no_remainder_is_lost() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "pharmacy", "")
	flow.begin_leg("there")
	near(flow.leg_road_min, 180.0, 1e-6, "the pharmacy on foot is three hours")
	near(flow.leg_pace, 2.0, 1e-9, "a 90 second leg: pace 2.0")
	var run := FakeRunSim.new()
	var total := 0
	for n in range(1, 8):
		total += flow.leg_step(run)
		eq(total, int(floor(float(n) * 2.0 / 3.0 + 1e-9)), "after %d steps the colony has floor(%d x pace / 3) of its own" % [n, n])
	var clock0: float = sim.clock_min
	var more := _drive(flow, run, 29.0)
	eq(flow.leg_colony, int(floor(float(flow.leg_steps) * 2.0 / 3.0 + 1e-9)), "the running total pays every remainder")
	near(float(sim.clock_min) - clock0, float(more) * STEP * 3.0, 1e-6, "and the clock moved as the steps say")
	_end(g)


func test_a_short_run_by_vehicle_is_slower_than_the_clock_and_a_foot_road_has_its_own_pace() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	near(flow.leg_road_min, sim.scavenge.road_minutes("houses", g.vehicle), 1e-9, "the road is the colony's own, by this vehicle")
	near(flow.leg_pace, PlaceFlow.pace_for(flow.leg_road_min), 1e-9, "its pace follows from it")
	check(flow.leg_pace < 1.0 and flow.leg_pace > 0.8, "a 27 minute run is held to 30 s: pace %.2f" % flow.leg_pace)
	var run := FakeRunSim.new()
	var took := _drive(flow, run, 30.0)
	eq(took, int(floor(900.0 * flow.leg_pace / 3.0 + 1e-9)), "the colony took floor(steps x pace / 3)")
	near(flow.elapsed_min(), flow.leg_road_min, 0.2, "a leg driven at cruise takes the road's minutes")
	_end(g)


func test_a_base_that_has_fallen_stands_still_while_the_leg_goes_on() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth"], "houses", "")
	flow.begin_leg("there")
	sim.over = "defeat"
	var clock0: float = sim.clock_min
	var run := FakeRunSim.new()
	_drive(flow, run, 3.0)
	near(float(sim.clock_min), clock0, 0.0, "nothing moves in a base that has fallen")
	_end(g)


func test_beginning_a_leg_starts_its_counters_again() -> void:
	var g := _game()
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	var run := FakeRunSim.new()
	flow.begin_leg("there")
	_drive(flow, run, 5.0)
	check(flow.leg_steps > 0 and flow.leg_colony > 0, "the leg counted")
	flow.end_leg(_leg())
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	flow.begin_leg("home")
	eq(flow.leg_steps, 0, "the way home counts from nothing")
	eq(flow.leg_colony, 0, "in both")
	near(flow.elapsed_min(), 0.0, 1e-9, "and has taken no time")
	_end(g)


# --------------------------------------------------------------- the clock --

func test_the_clock_is_the_bonus_a_fast_drive_saves_minutes_and_a_slow_one_loses_them() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "pharmacy", g.vehicle)
	flow.begin_leg("there")
	var road_min: float = flow.leg_road_min
	near(road_min, 81.8, 0.1, "the pharmacy by pickup")
	var leg_s := PlaceFlow.leg_seconds(road_min)
	var run := FakeRunSim.new()
	# at top speed (1.5 x cruise) the leg takes two thirds of its time
	_drive(flow, run, leg_s / PlaceFlow.TOP_FACTOR)
	near(flow.saved_min(), road_min / 3.0, 0.3, "a perfect run saves a third of the road's minutes: %.1f" % flow.saved_min())
	flow.end_leg(_leg())
	var text := _news_text(flow)
	check(text.contains("min early"), "the road's log says it arrived early: %s" % text)
	check(flow.last_leg.saved_min > 20.0, "the leg is kept for the report: %s" % str(flow.last_leg))
	# a slow one: 1.3 times the time
	var g2 := _game()
	var flow2 = _trip(g2, ["ruth", "dez"], "pharmacy", g2.vehicle)
	flow2.begin_leg("there")
	_drive(flow2, FakeRunSim.new(), PlaceFlow.leg_seconds(flow2.leg_road_min) * 1.3)
	check(flow2.saved_min() < -15.0, "a slow drive is behind the clock: %.1f" % flow2.saved_min())
	flow2.end_leg(_leg({"vehicle_hp_lost": 24.0}))
	var late := _news_text(flow2)
	check(late.contains("min late"), "and the log says so: %s" % late)
	check(late.contains("took a beating"), "with the car's beating: %s" % late)
	_end(g2)
	_end(g)


func test_ahead_of_the_clock_is_the_share_of_the_road_less_the_minutes_taken() -> void:
	var g := _game()
	var flow = _trip(g, ["ruth"], "pharmacy", "")
	flow.begin_leg("there")
	near(flow.leg_pace, 2.0, 1e-9, "a 90 second walk of 180 minutes")
	near(flow.delta_min(0.5), 90.0, 1e-9, "at the start, half way along is 90 minutes ahead")
	_drive(flow, FakeRunSim.new(), 20.0)
	near(flow.elapsed_min(), 40.0, 0.2, "twenty seconds are forty minutes at pace 2")
	near(flow.delta_min(0.5), 0.5 * 180.0 - flow.elapsed_min(), 1e-9, "the share of the road less the minutes taken")
	check(flow.delta_min(0.5) > 0.0, "half way after 20 s of 90 is ahead of the clock")
	check(flow.delta_min(0.1) < 0.0, "a tenth of the way after 20 s is behind it")
	near(flow.delta_min(2.0), flow.delta_min(1.0), 1e-9, "(the share is held between 0 and 1)")
	_end(g)


# ------------------------------------------------------- the leg's result --

func test_the_leg_there_feeds_the_people_the_stock_the_car_and_the_totals() -> void:
	var g := _game()
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	var dez = _person(sim, "dez")
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	var ammo0: float = sim.stock.ammo
	var hp0: float = float(sim.vehicles.vehicle(g.vehicle).hp)
	flow.begin_leg("there")
	_drive(flow, FakeRunSim.new(), 6.0)
	flow.end_leg(_leg({"hp": {"ruth": 70.0, "dez": 55.0}, "hurt": {"dez": "scratch"}, "ammo_used": 12.0, "vehicle_hp_lost": 6.0, "beats": ["Dez was scratched at the roadblock."], "leader": "ruth"}))
	near(ruth.hp, 70.0, 1e-6, "Ruth's health is what the road left")
	near(dez.hp, 55.0, 1e-6, "and Dez's")
	near(float(sim.stock.ammo), ammo0 - 12.0, 1e-6, "the ammo shot on the road is gone from the stores at once")
	near(float(sim.vehicles.vehicle(g.vehicle).hp), hp0 - 6.0, 1e-6, "the car has what the road took")
	eq(flow.road_hurt, {"dez": "scratch"}, "Dez is hurt, as the report will say")
	near(flow.road_ammo, 12.0, 1e-6, "the road's ammo is counted")
	eq(flow.road_beats, ["Dez was scratched at the roadblock."], "and its beats")
	eq(_ids(flow.going), ["ruth", "dez"], "both go on to the place")
	check(flow.vehicle_alive, "in the car")
	eq(String(flow.leader_id), "ruth", "Ruth leads")
	eq(flow.stage, "place", "the place is next")
	_end(g)


func test_a_person_lost_on_the_road_is_not_at_the_place_and_is_dead_when_the_party_is_home() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _person(sim, "dez")
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	_drive(flow, FakeRunSim.new(), 4.0)
	flow.end_leg(_leg({"lost": ["dez"], "hp": {"ruth": 66.0}, "leader": "ruth"}))
	eq(_ids(flow.going), ["ruth"], "only Ruth goes on to the place")
	eq(flow.road_lost, ["dez"], "Dez is lost on the road")
	check(dez.away != null and not dez.dead, "(he is not buried until the party is home: the colony does that)")
	check(_news_text(flow).contains("Dez"), "the road's log names him: %s" % _news_text(flow))
	flow.arrive()
	var merged: Dictionary = flow.merge_road(_place({"hp": {"ruth": 90.0}}))
	eq(merged.lost, ["dez"], "the place's result carries him as lost")
	flow.finish(merged)
	flow.begin_leg("home")
	_drive(flow, FakeRunSim.new(), 4.0)
	flow.end_leg(_leg())
	check(_until_home(sim), "the colony settles the party")
	check(dez.dead, "Dez did not come back")
	check(not _person(sim, "ruth").dead and _person(sim, "ruth").away == null, "Ruth did")
	_end(g)


func test_the_avatar_lost_on_the_road_hands_the_lead_on_and_the_base_is_told_once() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	_drive(flow, FakeRunSim.new(), 4.0)
	flow.end_leg(_leg({"lost": ["ruth"], "hp": {"dez": 80.0}, "leader": "dez"}))
	eq(String(flow.leader_id), "dez", "the run's succession: Dez leads from the road on")
	eq(String(sim.player_id), "ruth", "(the base is told at the end of the trip, not before)")
	flow.arrive()
	flow.finish(flow.merge_road(_place({"hp": {"dez": 80.0}, "leader": "dez"})))
	eq(String(sim.player_id), "dez", "the base's player is Dez now")
	flow.begin_leg("home")
	_drive(flow, FakeRunSim.new(), 4.0)
	flow.end_leg(_leg({"leader": "dez"}))
	check(_until_home(sim), "home")
	var successions := 0
	for e in sim.events:
		if String(e.get("type", "")) == "succession":
			successions += 1
	eq(successions, 1, "the succession was told once")
	check(_person(sim, "ruth").dead, "Ruth is dead")
	eq(String(sim.player_id), "dez", "and Dez is still the player")
	_end(g)


func test_the_avatar_lost_on_the_road_home_hands_the_lead_on_at_the_end_of_that_leg() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.end_leg(_leg())
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	flow.begin_leg("home")
	_drive(flow, FakeRunSim.new(), 3.0)
	flow.end_leg(_leg({"lost": ["ruth"], "hp": {"dez": 70.0}, "leader": "dez"}))
	eq(String(sim.player_id), "dez", "the base's player is the one who leads at the gate")
	check(_until_home(sim), "home")
	check(_person(sim, "ruth").dead, "Ruth is lost")
	check(not _person(sim, "dez").dead, "and Dez is home")
	_end(g)


# ------------------------------------------------------------ the car ------

func test_the_vehicles_hp_is_the_roads_wear_and_the_places_and_it_ends_parked() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	var hp0: float = float(sim.vehicles.vehicle(g.vehicle).hp)
	flow.begin_leg("there")
	flow.end_leg(_leg({"vehicle_hp_lost": 7.0}))
	near(float(sim.vehicles.vehicle(g.vehicle).hp), hp0 - 7.0, 1e-6, "the road there took 7")
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	flow.begin_leg("home")
	flow.end_leg(_leg({"vehicle_hp_lost": 5.0}))
	near(float(sim.vehicles.vehicle(g.vehicle).hp), hp0 - 12.0, 1e-6, "and the road home 5")
	check(_until_home(sim), "home")
	var v: Dictionary = sim.vehicles.vehicle(g.vehicle)
	eq(String(v.state), "parked", "the pickup is parked in its bay")
	near(float(v.hp), hp0 - 12.0 - sim.vehicles.WEAR_PER_DANGER * 1.0, 1e-6, "worn by the road and by the place's danger, as `come_home` does")
	_end(g)


func test_a_car_never_wears_below_one_and_a_wreck_loses_it_and_the_way_on_is_on_foot() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "pharmacy", g.vehicle)
	flow.begin_leg("there")
	near(flow.leg_pace, 1.0, 0.02, "by pickup the pharmacy is about 82 s")
	_drive(flow, FakeRunSim.new(), 10.0)
	flow.end_leg(_leg({"wrecked": true, "vehicle_hp_lost": 90.0, "hp": {"ruth": 80.0, "dez": 75.0}, "leader": "ruth"}))
	check(not flow.vehicle_alive, "the car is wrecked")
	check(sim.vehicles.vehicle(g.vehicle).is_empty(), "it is gone from the fleet")
	var lost_seen := false
	for e in sim.events:
		if String(e.get("type", "")) == "vehicle" and String(e.get("what", "")) == "lost":
			lost_seen = true
	check(lost_seen, "the colony was told it is lost")
	eq(String(flow.party.get("vehicle", "x")), "", "the party walks the rest (no car to drive in)")
	eq(_ids(flow.going), ["ruth", "dez"], "nobody was lost with it")
	flow.arrive()
	flow.finish(flow.merge_road(_place({"hp": {"ruth": 90.0, "dez": 80.0}})))
	flow.begin_leg("home")
	near(flow.leg_road_min, sim.scavenge.road_minutes("pharmacy", ""), 1e-6, "the way home is the whole way on foot")
	near(flow.leg_pace, PlaceFlow.pace_for(180.0), 1e-9, "at the foot road's pace (2.0)")
	_drive(flow, FakeRunSim.new(), 5.0)
	flow.end_leg(_leg())
	check(_until_home(sim), "they walk in at the gate")
	check(not _person(sim, "ruth").dead and not _person(sim, "dez").dead, "both are home")
	check(sim.vehicles.fleet.size() == 0, "and the fleet has no pickup")
	_end(g)


func test_road_wear_never_takes_a_car_below_one_hp() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.end_leg(_leg({"vehicle_hp_lost": 400.0}))
	var v: Dictionary = sim.vehicles.vehicle(g.vehicle)
	check(v.is_empty() or float(v.hp) >= 1.0, "a car is at one hp at the least, or it is wrecked")
	_end(g)


## Review of round 21, minor 4: a car at 1.0 hp (the floor of the fleet's hp, after a "Run it" on the leg there) that the scene drove all the
## way home with a scrape (0.3 hp lost, `wrecked` false) was declared a wreck at the gate: `road_wear` says false for a car that was at 1
## already. The scene knows whether its car is a wreck, and says so in `wrecked`.
func test_a_car_at_one_hp_that_the_scene_says_survived_is_not_wrecked() -> void:
	var g := _game()
	var sim = g.sim
	sim.vehicles.vehicle(g.vehicle)["hp"] = 1.0
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.end_leg(_leg({"vehicle_hp_lost": 0.3, "wrecked": false}))
	check(flow.vehicle_alive, "the car drove on")
	check(not bool(flow.last_leg.wrecked), "and the leg's entry does not call it a wreck")
	check(not sim.vehicles.vehicle(g.vehicle).is_empty(), "it is still in the fleet")
	near(float(sim.vehicles.vehicle(g.vehicle).hp), 1.0, 1e-9, "at the floor of one hp")
	check(not _news_text(flow).contains("wreck"), "and the log does not say it is a wreck: %s" % _news_text(flow))
	_end(g)


## Review of round 21, minor 10: `leg_result` had no `trust`: what the road's own radio moved (a push to go on, an order insisted on, a bite
## while following) was never paid to the colony's people. It is paid when the leg ends (the place and the colony read it from them).
func test_the_trust_the_road_moved_is_paid_when_the_leg_ends() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", "")
	var dez = _person(sim, "dez")
	dez.trust = 60.0
	var ruth_before: float = float(_person(sim, "ruth").trust)
	flow.begin_leg("there")
	flow.end_leg(_leg({"trust": {"dez": -4.0, "ruth": 0.0, "nobody": 9.0}}))
	near(float(dez.trust), 56.0, 1e-9, "the push cost him 4")
	near(float(_person(sim, "ruth").trust), ruth_before, 1e-9, "a zero moves nobody")
	flow.arrive()
	flow.finish(flow.merge_road(_place({"trust": {"dez": 1.0}})))
	near(float(dez.trust), 57.0, 1e-9, "and the place's own is paid on top, once")
	flow.begin_leg("home")
	flow.end_leg(_leg({"trust": {"dez": 2.5}}))
	near(float(dez.trust), 59.5, 1e-9, "the road home's too")
	_end(g)


func test_a_foot_trip_has_no_car_to_wear_and_the_same_flow() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez", "marcus"], "houses", "")
	var hp0: float = float(sim.vehicles.vehicle(g.vehicle).hp)
	var fuel0: float = sim.vehicles.fuel
	near(flow.leg_cruise(), 3.2, 1e-9, "the walk is 3.2 tiles a second")
	flow.begin_leg("there")
	flow.end_leg(_leg({"vehicle_hp_lost": 30.0, "wrecked": true}))
	near(float(sim.vehicles.vehicle(g.vehicle).hp), hp0, 1e-9, "a car left at the base is not worn by a walk")
	near(sim.vehicles.fuel, fuel0, 1e-9, "nor fuelled")
	check(flow.vehicle_alive == false or String(flow.vehicle_id) == "", "(a foot trip has no car)")
	check(not _news_text(flow).contains("beating"), "and the log has no car's beating")
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	flow.begin_leg("home")
	near(flow.leg_road_min, 60.0, 1e-6, "the way home is the same walk")
	flow.end_leg(_leg())
	check(_until_home(sim), "home")
	_end(g)


## (The flow takes the abstract trip's fuel once, at the gate, and burns no more on the road: what the gauge and the car's own `fuel_burnt`
## say over a whole eventless trip is the whole-trip test's below, through the real scene; here nothing could burn fuel after the gate.)
func test_fuel_is_taken_once_at_the_gate_and_the_flow_burns_no_more() -> void:
	var g := _game()
	var sim = g.sim
	var fuel0: float = sim.vehicles.fuel
	var need: float = sim.vehicles.fuel_for("pharmacy", g.vehicle)
	check(need > 5.0, "the pharmacy by pickup burns real fuel: %.2f" % need)
	var flow = _trip(g, ["ruth", "dez"], "pharmacy", g.vehicle)
	near(sim.vehicles.fuel, fuel0 - need, 1e-9, "both legs' fuel is burnt at the gate")
	flow.begin_leg("there")
	_drive(flow, FakeRunSim.new(), 60.0)
	flow.end_leg(_leg())
	near(sim.vehicles.fuel, fuel0 - need, 1e-9, "the road there burns nothing more")
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	flow.begin_leg("home")
	_drive(flow, FakeRunSim.new(), 60.0)
	flow.end_leg(_leg())
	check(_until_home(sim), "home")
	near(sim.vehicles.fuel, fuel0 - need, 1e-9, "the tank is what the gate left, to the end")
	near(sim.vehicles.fuel_per_leg("pharmacy", g.vehicle) * 2.0, need, 1e-9, "(a leg is half the trip's fuel)")
	_end(g)


# --------------------------------------------------- the colony's hold on it --

func test_the_party_is_not_due_on_the_road_home_and_comes_in_when_the_drive_ends() -> void:
	var g := _game()
	var sim = g.sim
	if not _has_events_api(sim):
		_end(g)
		return
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.end_leg(_leg())
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	var due: float = float(flow.party.return_at)
	flow.begin_leg("home")
	check(bool(flow.party.get("road_live", false)), "the party is on a live road")
	# the colony runs far past the abstract return time and nobody comes in
	var run := FakeRunSim.new()
	var steps := 0
	while float(sim.clock_min) < due + 300.0 and steps < 100000:
		sim.update(STEP)
		steps += 1
	check(float(sim.clock_min) >= due + 300.0, "the clock ran well past the abstract return")
	eq(sim.scavenge.parties.size(), 1, "the party is still out (the drive is not over)")
	check(String(sim.scavenge.parties[0].state) == "away", "on the road")
	check(_person(sim, "ruth").away != null, "Ruth is still away")
	flow.end_leg(_leg())
	check(not bool(flow.party.get("road_live", false)), "the drive is over: the road is not held")
	near(float(flow.party.return_at), float(sim.clock_min), 1.0, "they are due now")
	check(_until_home(sim, 600.0), "and the colony takes them in")
	check(run.mirrored == 0, "(the fake place was not used)")
	_end(g)


func test_a_party_that_gets_home_at_night_is_let_in() -> void:
	var g := _game()
	var sim = g.sim
	if not _has_events_api(sim):
		_end(g)
		return
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.end_leg(_leg())
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	_set_hour(sim, 18.6)
	flow.begin_leg("home")
	var run := FakeRunSim.new()
	var guard := 0
	while String(sim.phase) == "day" and guard < 20000:
		flow.leg_step(run)
		guard += 1
	check(String(sim.phase) != "day", "the drive crossed dusk: %s at %.2f" % [sim.phase, sim.hour])
	flow.end_leg(_leg())
	check(_until_home(sim, 900.0), "the party is let in at night: %s" % str(sim.scavenge.parties.size()))
	check(_person(sim, "ruth").away == null and _person(sim, "dez").away == null, "and they are at the base")
	_end(g)


# ------------------------------------------------------------- the result --

func test_what_the_road_found_goes_in_the_places_result_and_comes_home_in_the_bags() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.road_loot = {"scrap": 6}
	flow.road_hurt = {"dez": "scratch"}
	flow.road_beats = ["A wreck with its boot full: 6 scrap."]
	flow.end_leg(_leg({"hurt": {"ruth": "bite"}, "ammo_used": 4.0}))
	flow.arrive()
	var merged: Dictionary = flow.merge_road(_place({"loot": {"food": 14, "scrap": 2}, "hurt": {"dez": "bite"}, "ammo_used": 5.0}))
	eq(merged.loot, {"food": 14, "scrap": 8}, "the loot is summed")
	eq(merged.hurt.get("dez", ""), "bite", "a bite is worse than a scratch")
	eq(merged.hurt.get("ruth", ""), "bite", "and both are in")
	near(float(merged.ammo_used), 9.0, 1e-9, "the ammo shot is the road's and the place's")
	check(merged.beats.has("Dez opened the cabinet.") and merged.beats.has("A wreck with its boot full: 6 scrap."), "the beats of both: %s" % str(merged.beats))
	eq(String(merged.get("leader", "")), "ruth", "the leader is the place's")
	eq(merged.hp, {"ruth": 90.0, "dez": 80.0}, "and so is the health")
	var scrap0: float = sim.stock.scrap
	var food0: float = sim.stock.food
	var ammo0: float = sim.stock.ammo
	flow.finish(merged)
	eq(flow.party.result.loot, {"food": 14, "scrap": 8}, "the colony has it as the party's loot")
	eq(String(flow.party.result.hurt.get("dez", "")), "bite", "and the wounds")
	near(float(sim.stock.ammo), ammo0 - 5.0, 1e-6, "(the road's ammo was paid at the end of its leg, so only the place's is taken now)")
	flow.begin_leg("home")
	flow.end_leg(_leg())
	check(_until_home(sim), "home")
	near(float(sim.stock.scrap), scrap0 + 8.0, 1e-6, "the scrap is in the stores once")
	near(float(sim.stock.food), food0 + 14.0, 1e-6, "with the food")
	_end(g)


func test_the_roads_mood_and_its_words_go_to_the_colony_with_the_result() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.road_morale = -2.0    # (what `RoadEvents.apply` writes: the people on the road are away and the base's shock would not reach them)
	flow.end_leg(_leg())
	flow.arrive()
	var merged: Dictionary = flow.merge_road(_place())
	near(float(merged.get("morale", 0.0)), -2.0, 1e-9, "the road's mood is in the result")
	check(merged.get("road", []).size() == 1 and String(merged.road[0]).begins_with("Arrived"), "and the leg's words: %s" % str(merged.get("road", [])))
	flow.finish(merged)
	near(float(flow.party.result.get("morale", 0.0)), -2.0, 1e-9, "the colony has it as the party's")
	flow.begin_leg("home")
	flow.road_morale -= 1.0
	flow.end_leg(_leg())
	near(float(flow.party.result.get("morale", 0.0)), -3.0, 1e-9, "the road home's mood is amended in")
	eq(flow.party.result.get("road", []).size(), 2, "and its words")
	near(float(flow.result.get("morale", 0.0)), -3.0, 1e-9, "the report's result has them too")
	check(_until_home(sim), "home")
	var seen := 0.0
	for e in sim.morale.shocks.get("ruth", []):
		if String(e.label) == "On the road":
			seen = float(e.value)
	near(seen, -3.0, 0.3, "and the colony shocks those who came home by it")
	_end(g)


func test_the_ammo_the_whole_trip_shot_is_taken_from_the_stores_exactly_once() -> void:
	var g := _game()
	var sim = g.sim
	var ammo0: float = sim.stock.ammo
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.end_leg(_leg({"ammo_used": 12.0}))
	flow.arrive()
	flow.finish(flow.merge_road(_place({"ammo_used": 5.0})))
	flow.begin_leg("home")
	flow.end_leg(_leg({"ammo_used": 3.0}))
	check(_until_home(sim), "home")
	near(float(sim.stock.ammo), ammo0 - 20.0, 1e-6, "12 on the road there, 5 in the place, 3 on the road home: 20, not more")
	near(flow.road_ammo, 15.0, 1e-9, "(the road's share is counted for the report)")
	_end(g)


func test_what_the_road_home_found_and_lost_is_amended_into_the_settled_result() -> void:
	var g := _game()
	var sim = g.sim
	if not _has_events_api(sim):
		_end(g)
		return
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.road_loot = {"scrap": 6}
	flow.end_leg(_leg())
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	flow.begin_leg("home")
	flow.road_loot["fuel"] = 3
	flow.road_loot["meds"] = 2
	flow.end_leg(_leg({"lost": ["dez"], "hurt": {"ruth": "scratch"}, "hp": {"ruth": 60.0}, "leader": "ruth"}))
	var result: Dictionary = flow.party.result
	eq(int(result.loot.get("scrap", 0)), 6, "the road there's scrap is in once")
	eq(int(result.loot.get("fuel", 0)), 3, "the road home's fuel is amended in")
	eq(int(result.loot.get("meds", 0)), 2, "and its meds")
	eq(result.lost, ["dez"], "Dez, lost on the way home, is in the lost")
	eq(String(result.hurt.get("ruth", "")), "scratch", "and Ruth's scratch")
	var fuel0: float = sim.vehicles.fuel
	var meds0: float = sim.stock.meds
	check(_until_home(sim), "home")
	near(sim.vehicles.fuel, minf(fuel0 + 3.0, sim.vehicles.FUEL_CAP), 1e-6, "the fuel went to the tank")
	near(float(sim.stock.meds), meds0 + 2.0, 1e-6, "the meds to the stores")
	check(_person(sim, "dez").dead, "Dez is dead")
	_end(g)


func test_a_survivor_taken_in_on_the_road_is_in_the_result_and_joins_when_there_is_a_bed() -> void:
	var g := _game()
	var sim = g.sim
	if not _has_events_api(sim):
		_end(g)
		return
	sim.recruits.current_caller()
	var crew0: int = sim.recruits.crew_size()
	var beds: int = sim.recruits.housing_free()
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.road_survivors = 1
	flow.end_leg(_leg())
	flow.arrive()
	var merged: Dictionary = flow.merge_road(_place())
	eq(int(merged.get("road_survivors", 0)), 1, "the place's result carries the person taken in")
	flow.finish(merged)
	eq(int(flow.party.result.get("road_survivors", 0)), 1, "and so does the colony's party")
	flow.begin_leg("home")
	flow.end_leg(_leg())
	check(_until_home(sim), "home")
	if beds >= 1:
		eq(sim.recruits.crew_size(), crew0 + 1, "with a bed free they join the crew at the gate")
	else:
		eq(sim.recruits.crew_size(), crew0, "with no bed they stay where they are")
		check(sim.alerts.has("no-bed-road"), "and the alert says there is no bed")
	_end(g)


func test_a_survivor_waits_when_there_is_no_bed() -> void:
	var g := _game()
	var sim = g.sim
	if not _has_events_api(sim):
		_end(g)
		return
	sim.recruits.current_caller()
	# fill the beds
	while sim.recruits.housing_free() >= 1:
		sim.add_person(sim.recruits.make_def(sim.people.size()))
	var crew0: int = sim.recruits.crew_size()
	var queued: int = sim.recruits.queue.size()
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	flow.road_survivors = 1
	flow.end_leg(_leg())
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	flow.begin_leg("home")
	flow.end_leg(_leg())
	check(_until_home(sim), "home")
	eq(sim.recruits.crew_size(), crew0, "nobody joins a full house")
	eq(sim.recruits.queue.size(), queued, "the caller stays queued")
	check(sim.alerts.has("no-bed-road"), "and the alert says why")
	_end(g)


# ---------------------------------------------------------------- failure --

func test_all_down_on_the_road_there_means_no_place_and_no_road_home_and_the_colony_settles_the_party() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	flow.begin_leg("there")
	_drive(flow, FakeRunSim.new(), 5.0)
	flow.end_leg(_leg({"failed": true, "lost": ["ruth", "dez"], "wrecked": true, "vehicle_hp_lost": 90.0}))
	check(flow.failed, "the trip failed on the road")
	eq(flow.stage, "home", "there is no place to play and no road home to drive")
	eq(sim.scavenge.parties.size(), 0, "the colony has settled the party")
	check(_person(sim, "ruth").dead and _person(sim, "dez").dead, "nobody came back")
	check(not flow.result.is_empty(), "the report has a result")
	eq(flow.result.lost.size(), 2, "with both lost")
	eq(String(sim.player_id), "marcus", "the base's player is who is left")
	check(sim.vehicles.vehicle(g.vehicle).is_empty(), "the car is lost")
	check(_news_text(flow).contains("Nobody got through"), "the road's log says nobody got through: %s" % _news_text(flow))
	var again := {"stage": flow.stage, "lost": flow.result.lost.duplicate(), "trust": _person(sim, "marcus").trust}
	flow.finish(flow.merge_road({"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0, "beats": []}))
	eq(flow.stage, again.stage, "a scene that finishes a failed trip again changes nothing")
	eq(flow.result.lost, again.lost, "(the result is the same)")
	near(float(_person(sim, "marcus").trust), float(again.trust), 1e-9, "(and nobody's trust is paid twice)")
	_end(g)


# ------------------------------------------------------------ the report --

func test_the_report_has_the_roads_events_and_the_legs_in_the_news() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "pharmacy", g.vehicle)
	sim.radio.log_news("road", "A herd on the road: you ploughed through", "6 walkers")
	flow.begin_leg("there")
	_drive(flow, FakeRunSim.new(), 40.0)
	flow.end_leg(_leg({"vehicle_hp_lost": 3.0}))
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	flow.begin_leg("home")
	_drive(flow, FakeRunSim.new(), 40.0)
	flow.end_leg(_leg())
	var text := _news_text(flow)
	check(text.contains("A herd on the road"), "an event of the road is in the report's news: %s" % text)
	check(text.contains("Arrived"), "and the arrival at the place: %s" % text)
	check(text.contains("Home"), "and the road home: %s" % text)
	var kinds: Dictionary = {}
	for e in flow.news():
		kinds[String(e.kind)] = true
	check(kinds.has("road"), "they are the radio's own 'road' entries: %s" % str(kinds.keys()))
	eq(flow.legs.size(), 2, "both legs are kept for the report")
	eq(String(flow.legs[0].leg), "there", "the first")
	eq(String(flow.legs[1].leg), "home", "and the second")
	_end(g)


func test_the_scene_asks_the_flow_for_the_roads_own_lines_and_the_vehicle_it_has_now() -> void:
	var g := _game()
	var sim = g.sim
	var flow = _trip(g, ["ruth", "dez"], "houses", g.vehicle)
	eq(String(flow.vehicle_kind_now()), "pickup", "the pickup drives")
	flow.begin_leg("there")
	sim.radio.log_news("story", "A voice on the radio asks for help.", "")
	flow.end_leg(_leg())
	var road: Array = flow.road_news_lines()
	check(road.size() == 1 and String(road[0]).begins_with("Arrived"), "only the road's own lines: %s" % str(road))
	flow.begin_leg("home")
	eq(String(flow.vehicle_kind_now()), "pickup", "still")
	flow.arrive()
	flow.end_leg(_leg({"wrecked": true, "vehicle_hp_lost": 90.0}))
	eq(String(flow.vehicle_kind_now()), "", "a wrecked car is nobody's vehicle: the rest is on foot")
	_end(g)
	var g2 := _game()
	var foot = _trip(g2, ["ruth"], "houses", "")
	eq(String(foot.vehicle_kind_now()), "", "and a foot trip never had one")
	_end(g2)


# ------------------------------------------------------- the old game as it was --

func test_a_trip_with_no_avatar_has_no_live_drive_and_the_overlays_road_is_unchanged() -> void:
	var g := _game(8.0, false)
	var sim = g.sim
	check(not PlaceFlow.live_for(sim), "no avatar, no drive")
	var crew: Array = [_person(sim, "dez"), _person(sim, "marcus")]
	var flow = PlaceFlow.new(sim)
	check(flow.begin(crew, "houses", ""), "it begins: %s" % flow.error)
	check(not flow.live, "a flow is not live unless it is told so")
	var clock0: float = sim.clock_min
	var frames := 0
	while not flow.road_step(1.0 / 60.0) and frames < 100000:
		frames += 1
	near(float(sim.clock_min) - clock0, flow.road_total, 1e-6, "the overlay's road runs the abstract minutes exactly as before")
	flow.arrive()
	flow.finish({"loot": {"food": 5}, "hurt": {}, "lost": [], "ammo_used": 4.0, "beats": []})
	eq(flow.stage, "road_home", "the road home is the overlay's")
	near(float(sim.stock.ammo), 296.0, 1e-6, "and the ammo is settled by `finish_played` as it always was")
	check(_until_home(sim), "home")
	_end(g)


func test_the_overlays_flow_is_still_the_default_of_a_flow_that_nobody_made_live() -> void:
	var g := _game()
	var sim = g.sim
	PlaceFlow.live_enabled = false
	var flow = PlaceFlow.new(sim)
	check(flow.begin([_person(sim, "ruth"), _person(sim, "dez")], "houses", ""), "begins")
	check(not PlaceFlow.live_for(sim), "the overlay tests' switch")
	check(not flow.live, "not live")
	check(flow.road_step(1.0 / 60.0) == false and flow.road_left < flow.road_total, "the old road steps")
	_end(g)


# ------------------------------------------------------------------ saves --

func test_a_save_made_on_the_road_home_loads_as_the_abstract_return_and_a_save_on_the_road_there_turns_back() -> void:
	# the road home: the party is "away" with its due hour; `road_live` is not saved, so a load brings it in by the clock
	var a := _game()
	var sim = a.sim
	var flow = _trip(a, ["ruth", "dez"], "houses", a.vehicle)
	flow.begin_leg("there")
	flow.end_leg(_leg())
	flow.arrive()
	flow.finish(flow.merge_road(_place()))
	flow.begin_leg("home")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var party_saved: Dictionary = {}
	for entry in d.get("modules", {}).get("scavenge", {}).get("parties", []):
		party_saved = entry
	check(not party_saved.is_empty(), "the party is in the save")
	check(not party_saved.has("road_live"), "the live road is not saved")
	_write(FIXTURE, TOWN)
	Town.data_path = FIXTURE
	var b := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(b.sim, d), "it loads")
	var s2 = b.sim
	eq(s2.scavenge.parties.size(), 1, "the party is there")
	check(not bool(s2.scavenge.parties[0].get("road_live", false)), "not held on a road that is gone")
	eq(String(s2.scavenge.parties[0].state), "away", "on the abstract road home")
	var steps := 0
	while not s2.scavenge.parties.is_empty() and steps < 200000:
		s2.update(STEP)
		steps += 1
	check(s2.scavenge.parties.is_empty(), "it arrives by the clock")
	_end(a)
	_end(b)
	# the road there (and the place): in_place, the next step turns back with nothing
	var c := _game()
	var flow2 = _trip(c, ["ruth", "dez"], "houses", c.vehicle)
	flow2.begin_leg("there")
	_drive(flow2, FakeRunSim.new(), 5.0)
	var d2: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(c.sim)))
	_write(FIXTURE, TOWN)
	Town.data_path = FIXTURE
	var e := Helpers.make(3, 1, 3)
	Town.data_path = Town.DATA_PATH
	check(SaveGame.apply(e.sim, d2), "the second loads")
	eq(String(e.sim.scavenge.parties[0].state), "in_place", "in place after the load")
	e.sim.update(STEP)
	eq(String(e.sim.scavenge.parties[0].state), "away", "and turned back with nothing")
	check(e.sim.scavenge.parties[0].result.loot.is_empty(), "empty handed")
	_end(c)
	_end(e)


# -------------------------------------------------- main.gd: the hand-off ----

## Ends a trip a test opened: the party is settled with nothing and everyone is home (as tests/test_raid_scene.gd's `_abandon`).
func _abandon(main: Node, scene: Node) -> void:
	var party: Dictionary = main.sim.scavenge.party_in_place()
	scene.free()
	if not party.is_empty():
		main.sim.scavenge.finish_played(party, {})
		for p in main.sim.people:
			p.away = null
		main.sim.scavenge.parties.clear()


func test_open_raid_drives_when_live_and_keeps_the_overlay_when_it_is_not_and_a_trip_out_cannot_be_saved() -> void:
	if not ResourceLoader.exists(DRIVE_SCENE):
		print("        (the drive scene is not in: the hand-off is not tested)")
		return
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": true})
	main.raid_stub = true
	main.sim.waves.enabled = false
	var script = main._drive_scene_script()
	check(script != null, "the drive scene loads and compiles")
	if script == null:
		await TutorialKit.leave(main)
		return
	# the overlay when the drive is off
	PlaceFlow.live_enabled = false
	var plain = main.open_raid([main.sim.people[1]], main.sim.town.place("houses"), "", 1.0, Callable())
	check(plain != null, "the overlay's trip opens")
	if plain != null:
		eq(String(plain.phase), "road_there", "with the old overlay when the drive is off")
		check(not plain.flow.live, "its flow is not live")
		_abandon(main, plain)
	# ... and with --fastroad
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = true
	var fast = main.open_raid([main.sim.people[1]], main.sim.town.place("houses"), "", 1.0, Callable())
	check(fast != null and not fast.flow.live and String(fast.phase) == "road_there", "--fastroad keeps the overlay")
	if fast != null:
		_abandon(main, fast)
	PlaceFlow.fast_road = false
	# the drive
	var scene = main.open_raid([main.sim.people[1]], main.sim.town.place("houses"), "", 1.0, Callable())
	check(scene != null, "a live trip opens")
	if scene != null:
		check(scene.flow.live, "its flow is live")
		check(scene is RaidScene, "(a place's scene with a road: it is a RaidScene)")
		eq(String(scene.flow.stage), "drive_there", "on the road there")
		eq(String(scene.phase), "place", "(the scene's phase is a place's for the whole trip)")
		check(main.raid_open() and main.raid == scene, "the colony's view is under the trip")
		check(not main.quick_save(), "a save is refused while out")
		eq(String(main.shell.save_blocked()), "Not while you are out", "and the menu says so")
		check(main.sim.people[0].away != null, "the avatar is gone from the base")
		_abandon(main, scene)
	PlaceFlow.live_enabled = true
	await TutorialKit.leave(main)


func test_a_trip_with_no_avatar_never_opens_a_drive() -> void:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": false})
	main.raid_stub = true
	main.sim.waves.enabled = false
	PlaceFlow.live_enabled = true
	var scene = main.open_raid([main.sim.people[1]], main.sim.town.place("houses"), "", 1.0, Callable())
	check(scene != null, "the classic game's trip opens")
	if scene != null:
		check(not scene.flow.live, "its flow is not live")
		eq(String(scene.phase), "road_there", "with the overlay's road")
		_abandon(main, scene)
	await TutorialKit.leave(main)


## Ticks the scene (its own frames are off) until `done` says so or `limit` seconds of its time have passed; true if it did.
func _tick_until(scene: Node, limit: float, done: Callable) -> bool:
	var n := 0
	while n < int(limit * 30.0):
		if done.call():
			return true
		scene.tick(STEP)
		n += 1
	return done.call()


## FIX 21 (review of round 21): the whole-trip test above runs with `no_events`. This one runs a seeded trip with the REAL events (a
## checkpoint's toll on the way there, a wreck's search on the way home), the autopilot driving and the place stood in for by its loot and
## its shots, and reconciles the books: the tank, the vehicle's hp, every store and the rounds, from what the trip itself recorded.
func test_a_whole_live_trip_with_the_real_events_balances_its_books() -> void:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": true})
	var t := DriveKit.open(main, "pharmacy", "van", 2, 13, true, 50.0)
	var scene = t.scene
	check(scene != null and main.raid_open(), "the live trip opens")
	if scene == null:
		DriveScene.stand_ins = {}
		await TutorialKit.leave(main)
		return
	var sim = main.sim
	var danger := int(sim.town.place("pharmacy").danger)
	var steps := DriveKit.play(t, {}, DriveKit.place_gave({"meds": 4, "scrap": 6}, 5.0))
	check(steps < 60000 and String(scene.phase) == "report", "the trip ends in the report (%d steps)" % steps)
	eq(t.rec.planned.size(), 2, "both legs were planned by the real events: %s" % str(t.rec.planned))
	check(t.answered.size() >= 2 and String(t.answered[0]).begins_with("checkpoint") and String(t.answered[1]).begins_with("wreck_supplies"), "a toll and a search were answered: %s" % str(t.answered))
	eq(t.flow.legs.size(), 2, "two legs")
	var settled := DriveKit.settle(sim)
	check(sim.scavenge.parties.is_empty(), "the colony brought the party in (%d steps)" % settled)
	var books: Dictionary = DriveKit.reconcile(t, danger)
	for k in books:
		near(float(books[k][1]), float(books[k][0]), 1e-6, "the books: %s expected %.3f, the colony has %.3f" % [k, float(books[k][0]), float(books[k][1])])
	check(float(t.rec.stock.get("food", 0.0)) <= -10.0 + 1e-9, "(the toll was really paid: %s)" % str(t.rec.stock))
	check(int(t.flow.result.loot.get("meds", 0)) >= 4 + 4, "(the wreck's boot is in the bags with what the place gave: %s)" % str(t.flow.result.loot))
	# the clock: each leg took the colony steps it took, a tenth of a minute each
	var legs_min := 0.0
	for leg in t.flow.legs:
		legs_min += float(leg.elapsed_min)
		near(float(leg.elapsed_min), float(leg.road_min) - float(leg.saved_min), 1e-9, "a leg's minutes are the road's less what it saved")
	check(legs_min > 30.0 and float(sim.clock_min) - float(t.before.clock) >= legs_min, "the clock moved by at least the legs' minutes (%.1f of %.1f)" % [legs_min, float(sim.clock_min) - float(t.before.clock)])
	check(sim.people[1].away == null and sim.people[2].away == null and not sim.people[1].dead and not sim.people[2].dead, "everyone is home")
	DriveScene.stand_ins = {}
	scene.go_home()
	PlaceFlow.no_events = false
	await TutorialKit.leave(main)


func test_a_whole_live_trip_through_the_real_scene_is_a_drive_a_place_and_a_drive() -> void:
	if not ResourceLoader.exists(DRIVE_SCENE):
		print("        (the drive scene is not in: the whole trip is not tested)")
		return
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": true})
	main.raid_stub = true
	var sim = main.sim
	sim.waves.enabled = false
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	PlaceFlow.no_events = true
	var vehicle := String(sim.vehicles.add("pickup").id)
	sim.vehicles.fuel = 40.0
	var fuel0: float = sim.vehicles.fuel
	var need: float = sim.vehicles.fuel_for("houses", vehicle)
	var done: Array = []
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), vehicle, 1.0, func(r): done.append(r))
	check(scene != null and main.raid_open(), "the live trip opens")
	if scene == null:
		PlaceFlow.no_events = false
		await TutorialKit.leave(main)
		return
	scene.set_process(false)
	var flow = scene.flow
	check(flow.live and String(flow.stage) == "drive_there", "on the road there")
	near(sim.vehicles.fuel, fuel0 - need, 1e-9, "the fuel of both legs was taken at the gate")
	var clock0: float = sim.clock_min
	# the way there (the autopilot drives: no real hands in a headless run). The gauge (the HUD's trip tank draining by distance) and the car's
	# own `fuel_burnt` are read all the way: over the whole trip they burn exactly what the abstract trip's `fuel_for` took at the gate.
	var per_leg: float = sim.vehicles.fuel_per_leg("houses", vehicle)
	var gauge := {"there": 0.0, "home": 0.0}
	var car_burnt := {"there": 0.0, "home": 0.0}
	var sample := func() -> void:
		var which := String(scene.leg)
		if (which == "there" or which == "home") and scene.car != null:
			var f: Dictionary = scene.hud_layer.fuel_now()
			if not f.is_empty():
				var burnt: float = float(f.total) - float(f.left)
				gauge[which] = maxf(float(gauge[which]), burnt - (per_leg if which == "home" else 0.0))
			car_burnt[which] = maxf(float(car_burnt[which]), float(scene.car.fuel_burnt(per_leg, scene.car.progress(scene.road))))
	check(_tick_until(scene, 200.0, func():
		sample.call()
		return String(scene.leg) != "there"), "the way there ends: %s" % scene.leg)
	eq(String(scene.leg), "place", "at the place")
	eq(String(flow.stage), "place", "the flow says so")
	eq(flow.legs.size(), 1, "one leg is behind")
	var there: Dictionary = flow.legs[0]
	near(float(there.elapsed_min), float(sim.clock_min) - clock0, 0.2, "the colony's clock is the leg's minutes: %.1f of %.1f" % [there.elapsed_min, there.road_min])
	check(float(there.elapsed_min) > 5.0, "a drive takes game minutes")
	check(String(scene.phase) == "place", "(the scene's phase stays a place's)")
	# the place: everyone to the exit
	scene.stage("exit")
	check(_tick_until(scene, 20.0, func(): return String(scene.leg) == "home" or String(scene.phase) == "report"), "the place ends")
	eq(String(scene.leg), "home", "the way home begins")
	eq(String(flow.stage), "drive_home", "the flow too")
	check(bool(flow.party.get("road_live", false)), "and the colony does not bring the party in by its own clock")
	check(_tick_until(scene, 200.0, func():
		sample.call()
		return String(scene.phase) == "report"), "the way home ends in the report")
	eq(String(flow.stage), "home", "the base")
	eq(flow.legs.size(), 2, "both legs are in the report")
	near(sim.vehicles.fuel, fuel0 - need, 1e-9, "an eventless drive left the base tank exactly as the abstract trip's gate did")
	near(float(gauge.there), per_leg, per_leg * 0.01, "the gauge burnt a leg's fuel on the road there (%.3f of %.3f)" % [gauge.there, per_leg])
	near(float(gauge.home), per_leg, per_leg * 0.01, "and a leg's on the road home (%.3f of %.3f)" % [gauge.home, per_leg])
	near(float(car_burnt.there) + float(car_burnt.home), need, need * 0.01, "the car's own `fuel_burnt` over both legs is the abstract `fuel_for` (%.3f of %.3f)" % [float(car_burnt.there) + float(car_burnt.home), need])
	check(per_leg > 1.0, "(a real amount of fuel: %.2f a leg)" % per_leg)
	var steps := 0
	while not sim.scavenge.parties.is_empty() and steps < 60000:
		sim.update(STEP)
		steps += 1
	check(sim.scavenge.parties.is_empty(), "the colony brought the party in")
	check(sim.people[0].away == null and sim.people[1].away == null, "they are home")
	eq(String(sim.vehicles.vehicle(vehicle).state), "parked", "the pickup is parked")
	scene.go_home()
	eq(done.size(), 1, "the trip's result is given once")
	PlaceFlow.no_events = false
	await TutorialKit.leave(main)
