extends "res://tests/case.gd"
## The flow of a played trip (round 17, slice 1, S1.6b: scripts/raid/place_flow.gd, and the scene in raid_scene.gd that
## shows it): the radio is asked who comes, the party begins (the colony people vanish from the base), the road there is run
## quickly under an overlay, the place is played while the colony goes on at one step in three, the way out finishes the
## party, the road home is run the same way and the colony view comes back with a report. The rules of the place are
## tests/test_raid_run.gd's, the colony's side of it tests/test_continuity.gd's, the scene's controls tests/test_raid_scene.gd's.

const GD := preload("res://scripts/game_data.gd")
const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")

const FIXTURE := "user://test_place_flow_town.json"
const STEP := 1.0 / 30.0

## Home is at (50, 35). The houses are an hour away on foot (9 tiles at 9 a hour); the garage holds a pickup.
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


## What the place's Sim is given every colony step (raid_sim.gd `mirror`): the colony's clock.
class FakeRunSim:
	extends RefCounted
	var mirrored := 0
	var clock_min := 0.0
	var day := 0
	var phase := ""

	func mirror(colony) -> void:
		mirrored += 1
		clock_min = float(colony.clock_min)
		day = int(colony.day)
		phase = String(colony.phase)


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game of three (Ruth, Dez, Marcus) at `hour` of day 3 with the small town above and Ruth as the avatar.
func _game(hour: float = 8.0, avatar: bool = true) -> Dictionary:
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
	if avatar:
		sim.avatar.set_player("ruth")
		sim.radio.start()
	return g


func _end(g: Dictionary) -> void:
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


## Runs the road (there or home) in frames of 1/60 s until it is done; returns how many frames it took (0: none, 100000: stuck).
func _road(flow, dt: float = 1.0 / 60.0) -> int:
	var frames := 0
	while frames < 100000:
		frames += 1
		if flow.road_step(dt):
			return frames
	return frames


# --------------------------------------------------------------- the party --

func test_the_radio_is_asked_who_comes_and_the_player_is_always_in_and_leads() -> void:
	var g := _game()
	var sim = g.sim
	var picked := PlaceFlow.pick_party(sim, [_person(sim, "dez"), _person(sim, "marcus")])
	eq(_ids(picked.going), ["ruth", "dez", "marcus"], "the avatar first, then those who said yes")
	check(picked.refused.is_empty() and picked.left_out.is_empty(), "nobody left out")
	picked = PlaceFlow.pick_party(sim, [_person(sim, "dez")])
	eq(_ids(picked.going), ["ruth", "dez"], "the player is added when the picker had not got them")
	picked = PlaceFlow.pick_party(sim, [])
	eq(_ids(picked.going), ["ruth"], "and goes alone when nobody else is chosen")
	picked = PlaceFlow.pick_party(sim, [_person(sim, "ruth"), _person(sim, "dez")])
	eq(_ids(picked.going), ["ruth", "dez"], "chosen twice they are in once")
	_end(g)


func test_someone_who_cannot_come_is_left_out_and_the_reason_is_the_radios() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _person(sim, "dez")
	dez.bleeding = 2.0
	var picked := PlaceFlow.pick_party(sim, [dez, _person(sim, "marcus")])
	eq(_ids(picked.going), ["ruth", "marcus"], "Dez stays")
	eq(picked.refused.size(), 1, "one refusal")
	eq(String(picked.refused[0].p.id), "dez", "Dez's")
	eq(String(picked.refused[0].why), String(sim.radio.willingness(dez, "come").why), "with the reason the radio gives")
	check(String(picked.refused[0].why).begins_with("Dez"), "which names them")
	eq(PlaceFlow.refusal_lines(picked), [String(picked.refused[0].why)], "the picker's line is that reason")
	check(not _person(sim, "dez").away, "(nobody is sent anywhere by asking)")
	_end(g)


func test_more_than_the_seats_and_the_last_of_the_chosen_stay_behind() -> void:
	var g := _game()
	var sim = g.sim
	var extra = sim.add_person(sim.recruits.make_def(0))
	var picked := PlaceFlow.pick_party(sim, [_person(sim, "dez"), _person(sim, "marcus"), extra])
	eq(_ids(picked.going), ["ruth", "dez", "marcus"], "three on foot with the player")
	eq(picked.left_out.size(), 1, "one stays")
	eq(String(picked.left_out[0].p.id), String(extra.id), "the last of the chosen")
	check(String(picked.left_out[0].why).contains("three"), "and is told why: %s" % picked.left_out[0].why)
	_end(g)


func test_with_no_avatar_nobody_is_asked_and_the_chosen_all_go_as_picked() -> void:
	var g := _game(8.0, false)
	var sim = g.sim
	var dez = _person(sim, "dez")
	dez.bleeding = 2.0
	var picked := PlaceFlow.pick_party(sim, [dez, _person(sim, "ruth")])
	eq(_ids(picked.going), ["dez", "ruth"], "as picked, bleeding or not: the old game")
	check(picked.refused.is_empty(), "no refusals")
	_end(g)


# ------------------------------------------------------------------ begin --

func test_begin_makes_the_party_and_the_people_vanish_from_the_base_and_sets_the_road() -> void:
	var g := _game()
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	var crew: Array = [_person(sim, "ruth"), _person(sim, "dez")]
	check(flow.begin(crew, "houses", ""), "it begins")
	eq(flow.error, "", "with no error")
	eq(flow.stage, "road_there", "on the road there")
	eq(String(flow.party.get("state", "")), "in_place", "the colony has them in the place")
	for p in crew:
		check(p.away != null, "%s is gone from the base" % p.first)
	near(flow.road_total, sim.scavenge.road_minutes("houses", ""), 1e-9, "the road is the colony's")
	near(flow.road_left, flow.road_total, 1e-9, "all of it ahead")
	eq(flow.action, "loot", "a trip to loot")
	_end(g)


func test_a_trip_the_rules_refuse_says_why_and_nobody_goes() -> void:
	var g := _game(21.0)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	check(not flow.begin([_person(sim, "ruth"), _person(sim, "dez")], "houses", ""), "not after dark")
	check(flow.error != "", "it says why: '%s'" % flow.error)
	eq(flow.stage, "idle", "the flow did not start")
	eq(sim.scavenge.parties.size(), 0, "nobody is away")
	_end(g)


# -------------------------------------------------------------------- road --

func test_the_road_there_is_run_in_chunks_and_the_clock_moves_exactly_as_far_as_the_road() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth"), _person(sim, "dez")], "houses", "")
	var clock0: float = sim.clock_min
	var steps0: float = sim.t
	var chunks: Array = []
	var frames := 0
	while not flow.road_step(1.0 / 60.0) and frames < 100000:
		frames += 1
		chunks.append(flow.road_progress())
	check(frames > 20, "a road is not one jump: %d frames" % frames)
	for i in range(1, chunks.size()):
		check(chunks[i] >= chunks[i - 1], "the progress only goes forward")
	near(float(sim.clock_min) - clock0, flow.road_total, 1e-6, "the colony ran the road's minutes, no more and no less")
	near(flow.road_progress(), 1.0, 1e-9, "and the road is all behind")
	var steps := int(round((float(sim.t) - steps0) / STEP))
	check(steps <= int(flow.road_total / (sim.min_per_sec * STEP)) + 1, "in steps of the rules' own: %d" % steps)
	_end(g)


func test_a_frame_of_the_road_takes_at_most_sixty_steps_and_the_road_lasts_a_few_seconds_on_screen() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth")], "houses", "")
	var most := 0
	var frames := 0
	var t0: float = sim.t
	var last: float = t0
	while not flow.road_step(1.0 / 60.0) and frames < 100000:
		frames += 1
		var took := int(round((float(sim.t) - last) / STEP))
		most = maxi(most, took)
		last = sim.t
	check(most <= PlaceFlow.MAX_STEPS_PER_FRAME, "no frame took more than %d steps (%d)" % [PlaceFlow.MAX_STEPS_PER_FRAME, most])
	check(float(frames) / 60.0 >= PlaceFlow.MIN_ROAD_S * 0.8, "an hour's road plays for about %.1f seconds: %.2f" % [PlaceFlow.MIN_ROAD_S, float(frames) / 60.0])
	# a long road is held to the cap instead
	var long = PlaceFlow.new(sim)
	long.road_total = 30.0 * 60.0
	long.road_left = long.road_total
	eq(long.road_budget(1.0 / 60.0), PlaceFlow.MAX_STEPS_PER_FRAME, "a thirty hours' road is held to the budget")
	check(long.road_budget(0.0) >= 1, "and a frame always takes one step")
	_end(g)


func test_news_that_comes_in_during_the_road_is_there_for_the_overlay_to_show() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth"), _person(sim, "dez")], "houses", "")
	check(flow.news().is_empty(), "nothing at the start")
	_road(flow)
	sim.radio.log_news("story", "A voice on the radio asks for help.", "")
	var lines: Array = flow.news_lines()
	check(lines.has("A voice on the radio asks for help."), "the news since the trip began: %s" % str(lines))
	eq(flow.news_lines(0), [], "and none when none are asked for")
	_end(g)


# ------------------------------------------------------------------- place --

func test_the_colony_takes_a_step_for_every_three_of_the_places_and_no_remainder_is_lost() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth")], "houses", "")
	flow.arrive()
	var run := FakeRunSim.new()
	var clock0: float = sim.clock_min
	var took := 0
	for i in 100:
		took += flow.place_step(run)
	eq(flow.place_steps, 100, "a hundred steps of the place")
	eq(took, 33, "thirty-three of the colony's: the remainder waits")
	eq(flow.colony_steps, 33, "and is counted")
	eq(run.mirrored, 33, "the place is given the colony's clock after each one")
	near(float(sim.clock_min) - clock0, 33.0 * STEP * sim.min_per_sec, 1e-6, "the colony's clock moved that much")
	near(run.clock_min, float(sim.clock_min), 1e-9, "and the place has it")
	for i in 2:
		took += flow.place_step(run)
	eq(took, 34, "two more of the place: the thirty-fourth is paid")
	_end(g)


func test_an_hour_in_the_place_is_a_minute_of_the_days_twenty() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth")], "houses", "")
	var run := FakeRunSim.new()
	var clock0: float = sim.clock_min
	for i in 30 * 60:
		flow.place_step(run)
	near(float(sim.clock_min) - clock0, 60.0, 0.2, "a minute of the place's time is an hour of the colony's")
	_end(g)


func test_a_night_falls_in_the_colony_while_the_place_is_played() -> void:
	var g := _game(18.5)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth")], "houses", "")
	var run := FakeRunSim.new()
	var day: int = sim.day
	var phases: Dictionary = {}
	for i in 30 * 90:
		flow.place_step(run)
		phases[String(run.phase)] = true
	check(phases.has("night") or phases.has("dusk"), "the place saw the dusk come: %s" % str(phases.keys()))
	eq(String(run.phase), String(sim.phase), "it has the colony's phase now")
	check(sim.hour > 19.0 or sim.day > day, "the colony's clock is past nightfall: %.2f" % sim.hour)
	_end(g)


func test_the_colony_stands_when_its_run_is_over() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth")], "houses", "")
	var run := FakeRunSim.new()
	sim.over = "defeat"
	var clock0: float = sim.clock_min
	for i in 60:
		flow.place_step(run)
	near(float(sim.clock_min), clock0, 0.0, "nothing moves in a base that has fallen")
	eq(flow.colony_steps, 20, "(the count still goes: the place is not told to stop here)")
	_end(g)


# ------------------------------------------------------------------ finish --

func test_finishing_puts_the_party_on_the_road_home_and_the_radio_hears_of_the_trip() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	var dez = _person(sim, "dez")
	var flow = PlaceFlow.new(sim)
	flow.begin([ruth, dez], "houses", "")
	_road(flow)
	flow.arrive()
	var trust_before: float = dez.trust
	var food: float = sim.stock.food
	flow.finish({"loot": {"food": 14}, "hurt": {}, "lost": [], "ammo_used": 10.0, "beats": ["Dez opened the cabinet."], "hp": {"dez": 80.0}, "trust_delta": {"dez": -3.0}})
	eq(flow.stage, "road_home", "the road home")
	eq(String(flow.party.state), "away", "the colony has them on the road")
	near(flow.road_total, sim.scavenge.road_minutes("houses", "") + PlaceFlow.ARRIVAL_MARGIN_MIN, 1e-9, "the same road, and a little over")
	near(dez.trust, trust_before - 3.0, 1e-6, "Dez: what the place counted (it paid the trip's bonus into its own sum: only one is paid)")
	near(dez.hp, 80.0, 1e-6, "his health as he left the place")
	_road(flow)
	var left := 0
	while not sim.scavenge.parties.is_empty() and left < 6000:
		sim.update(STEP)
		left += 1
	check(sim.scavenge.parties.is_empty(), "the party comes home")
	check(dez.away == null and ruth.away == null, "and they are at the base")
	check(sim.stock.food > food, "with the food")
	_end(g)


func test_the_road_home_does_not_take_the_road_twice() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth"), _person(sim, "dez")], "houses", "")
	_road(flow)
	flow.arrive()
	flow.finish({"loot": {"food": 5}, "hurt": {}, "lost": [], "ammo_used": 0.0, "beats": []})
	var due: float = float(flow.party.return_at)
	_road(flow)
	check(float(sim.clock_min) >= due, "when the road home is done the party's time is up (%.1f of %.1f)" % [sim.clock_min, due])
	check(sim.scavenge.parties.is_empty() or String(sim.scavenge.parties[0].state) != "away", "and they have reached the gate")
	# a step or two more and they are at the gate: not another hour
	for i in 600:
		sim.update(STEP)
	check(sim.scavenge.parties.is_empty() or String(sim.scavenge.parties[0].state) != "away", "they are in sight of the gate, not still out on the road")
	_end(g)


func test_the_places_own_trust_count_is_paid_alone_and_with_none_the_radios_bonus_is() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var dez = _person(sim, "dez")
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth"), dez], "houses", "")
	var t0: float = dez.trust
	flow.finish({"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0, "beats": []})
	near(dez.trust, t0 + sim.radio.TRIP_BONUS, 1e-6, "no count: the radio's bonus for a trip led")
	var g2 := _game(8.0)
	var s2 = g2.sim
	var dez2 = _person(s2, "dez")
	var flow2 = PlaceFlow.new(s2)
	flow2.begin([_person(s2, "ruth"), dez2], "houses", "")
	var t2: float = dez2.trust
	flow2.finish({"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0, "beats": [], "trust_delta": {"dez": 2.0}})
	near(dez2.trust, t2 + 2.0, 1e-6, "a count of two: two, not four")
	var g3 := _game(8.0)
	var s3 = g3.sim
	var dez3 = _person(s3, "dez")
	var flow3 = PlaceFlow.new(s3)
	flow3.begin([_person(s3, "ruth"), dez3], "houses", "")
	var t3: float = dez3.trust
	flow3.finish({"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0, "beats": [], "trust_delta": 1.5})
	near(dez3.trust, t3 + 1.5, 1e-6, "one number is for them all")
	_end(g)
	_end(g2)
	_end(g3)


func test_those_who_were_lost_get_no_trip_bonus() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var dez = _person(sim, "dez")
	var marcus = _person(sim, "marcus")
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth"), dez, marcus], "houses", "")
	var t0: float = dez.trust
	var m0: float = marcus.trust
	flow.finish({"loot": {}, "hurt": {}, "lost": ["marcus"], "ammo_used": 0.0, "beats": []})
	near(dez.trust, t0 + sim.radio.TRIP_BONUS, 1e-6, "Dez came back")
	near(marcus.trust, m0, 1e-6, "Marcus did not")
	_end(g)


func test_the_base_is_told_who_led_at_the_end_when_it_was_not_told_before() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var flow = PlaceFlow.new(sim)
	flow.begin([_person(sim, "ruth"), _person(sim, "dez")], "houses", "")
	flow.finish({"loot": {}, "hurt": {}, "lost": ["ruth"], "ammo_used": 0.0, "beats": [], "leader": "dez"})
	eq(sim.player_id, "dez", "the leader at the end is the base's player")
	_end(g)
	var g2 := _game(8.0)
	var s2 = g2.sim
	var flow2 = PlaceFlow.new(s2)
	flow2.begin([_person(s2, "ruth"), _person(s2, "dez")], "houses", "")
	flow2.finish({"loot": {}, "hurt": {}, "lost": ["ruth", "dez"], "ammo_used": 0.0, "beats": [], "leader": "dez"})
	eq(s2.player_id, "marcus", "a leader who is lost is not made the player: with nobody coming home the base's own succession takes the next one at home")
	_end(g2)


func test_the_old_leader_who_is_lost_costs_the_setback_at_the_finish_and_the_place_chooses_the_heir() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	var dez = _person(sim, "dez")
	var marcus = _person(sim, "marcus")
	dez.trust = 40.0
	marcus.trust = 90.0    # (the base's own order would pick Marcus: the place's pick is Dez)
	var flow = PlaceFlow.new(sim)
	flow.begin([ruth, dez], "houses", "")
	var m0: float = marcus.trust
	flow.finish({"loot": {}, "hurt": {}, "lost": ["ruth"], "ammo_used": 0.0, "beats": [], "leader": "dez", "trust_delta": {"dez": 0.0}})
	eq(sim.player_id, "dez", "the place's pick, whatever the base's own order would be")
	near(marcus.trust, m0 - 10.0, 0.01, "everyone's trust fell ten")
	sim.update(STEP)    # (the radio reads the events of a step)
	check(not sim.radio.news.filter(func(e): return String(e.kind) == "succession").is_empty(), "and the base heard of the loss")
	_end(g)


func test_a_leader_who_lived_hands_over_to_the_last_leader_without_the_setback() -> void:
	var g := _game(8.0)
	var sim = g.sim
	var ruth = _person(sim, "ruth")
	var dez = _person(sim, "dez")
	var marcus = _person(sim, "marcus")
	var flow = PlaceFlow.new(sim)
	flow.begin([ruth, dez], "houses", "")
	var m0: float = marcus.trust
	var d0: float = dez.trust
	flow.finish({"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0, "beats": [], "leader": "dez", "trust_delta": {}})
	eq(sim.player_id, "dez", "Dez is the base's player: he led at the end")
	check(dez.player and not ruth.player, "Ruth is not")
	near(marcus.trust, m0, 0.01, "no setback for the others")
	near(dez.trust, d0, 0.01, "or for him")
	check(sim.radio.news.filter(func(e): return String(e.kind) == "succession").is_empty(), "no news of a loss: nobody was lost")
	check(not ruth.dead, "and Ruth lives")
	_end(g)


# -------------------------------------------------------------------- base --

func test_the_base_state_reads_the_walls_the_alarm_and_the_night() -> void:
	var g := _game(10.0)
	var sim = g.sim
	eq(String(PlaceFlow.base_state(sim).key), "ok", "a quiet day")
	sim.radio.alarm(true)
	eq(String(PlaceFlow.base_state(sim).key), "alarm", "the alarm is up")
	sim.radio.alarm(false)
	var z = sim.spawn(30.0, 20.0, "wander")
	z.state = "attack"
	eq(String(PlaceFlow.base_state(sim).key), "attack", "the dead at the wall")
	check(String(PlaceFlow.base_state(sim).text).contains("attack"), "in words")
	z.state = "dead"
	sim.phase = "night"
	eq(String(PlaceFlow.base_state(sim).key), "night", "a night held")
	sim.over = "defeat"
	eq(String(PlaceFlow.base_state(sim).key), "fallen", "a base that has fallen")
	check(PlaceFlow.clock_text(sim).begins_with("Day 3, "), "the clock reads: %s" % PlaceFlow.clock_text(sim))
	_end(g)


# ================================================================== the whole trip, in the scene ==
# The real game (a small start, Ruth the avatar) opens a trip with `main.open_raid` as the Town Board does, and the scene is driven
# by hand (its own frames are off): the road there, the place, the road home and the report.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _main(crew: int = 3, avatar: bool = true) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew, "avatar": avatar})
	main.raid_stub = true
	main.sim.waves.enabled = false
	return main


func _leave(main: Node) -> void:
	await TutorialKit.leave(main)


func _tick(scene: Node, seconds: float, dt: float = STEP) -> void:
	for i in int(seconds / dt):
		scene.tick(dt)


## The road (there or home) to its end: how many frames it took and the most colony steps one frame took.
func _drive_road(main: Node, scene: Node, which: String) -> Dictionary:
	var frames := 0
	var most := 0
	var last_t: float = main.sim.t
	while scene.phase == which and frames < 5000:
		scene.tick(1.0 / 60.0)
		frames += 1
		most = maxi(most, int(round((float(main.sim.t) - last_t) / STEP)))
		last_t = main.sim.t
	return {"frames": frames, "most": most}


## Walks the one you lead out of the exit and back into it with everyone, to leave.
func _leave_place(scene: Node) -> void:
	var lead = scene.leader()
	var spot: Vector2 = scene.site.exit.get_center()
	lead.x = spot.x + 7.0
	lead.path = []
	_tick(scene, 0.2)
	for p in scene.run.squad:
		if not p.dead and not p.downed:
			p.x = spot.x + randf_range(-0.8, 0.8)
			p.y = spot.y + randf_range(-0.6, 0.6)
			p.path = []
	_tick(scene, 0.5)


func test_a_whole_trip_the_road_there_the_place_the_road_home_and_the_report() -> void:
	var main := _main()
	var sim = main.sim
	var done: Array = []
	var ruth = sim.people[0]
	var dez = sim.people[1]
	var marcus = sim.people[2]
	main.cam_center = Vector2(37.5, 22.0)
	main.zoom_px = 44.0
	main.speed = 2
	var clock0: float = sim.clock_min
	var scene = main.open_raid([dez], sim.town.place("houses"), "", 1.0, func(r): done.append(r))
	check(scene != null, "the trip begins")
	# --- the road there
	eq(scene.phase, "road_there", "on the road there")
	check(ruth.away != null and dez.away != null and marcus.away == null, "Ruth and Dez are gone from the base, Marcus is not")
	check(scene.hud_layer.road_panel.visible, "the overlay is up")
	var road_minutes: float = sim.scavenge.road_minutes("houses", "")
	var progress: Array = []
	var seen_news := false
	var frames := 0
	var most := 0
	var last_t: float = sim.t
	while scene.phase == "road_there" and frames < 5000:
		scene.tick(1.0 / 60.0)
		frames += 1
		most = maxi(most, int(round((float(sim.t) - last_t) / STEP)))
		last_t = sim.t
		progress.append(scene.flow.road_progress())
		if frames == 30:
			sim.radio.log_news("story", "A voice on the radio asks for help.", "")
		if frames == 31:
			seen_news = scene.hud_layer.road_news.has("A voice on the radio asks for help.")
		if frames == 10:
			check(scene.hud_layer.road_bar.value > 0.0 and scene.hud_layer.road_clock_label.text.begins_with("Day 1, "), "the bar and the clock move: %s" % scene.hud_layer.road_clock_label.text)
	check(frames > 60, "the road takes a few seconds on the screen: %d frames" % frames)
	check(most <= PlaceFlow.MAX_STEPS_PER_FRAME, "at most 60 colony steps in a frame (%d)" % most)
	for i in range(1, progress.size()):
		if progress[i] < progress[i - 1]:
			failures.append("the road's progress went back")
			break
	check(seen_news, "news that came in on the road was shown as it came")
	near(float(sim.clock_min) - clock0, road_minutes, 0.5, "the colony ran the road's minutes")
	# --- the place
	eq(scene.phase, "place", "at the place")
	check(not scene.hud_layer.road_panel.visible and scene.root.visible, "the road's overlay is gone and the place shows")
	eq(String(scene.leader().id), "ruth", "Ruth leads")
	eq(scene.run.squad.size(), 2, "with Dez")
	check(scene.run.sim.day == sim.day and absf(float(scene.run.sim.minutes) - float(sim.minutes)) < 0.01, "the place has the base's clock")
	var c1: float = sim.clock_min
	var day_before: int = sim.day
	_tick(scene, 20.0)
	near(float(sim.clock_min) - c1, 20.0, 1.0, "twenty seconds in the place are twenty minutes of the day: %.2f" % (float(sim.clock_min) - c1))
	near(float(scene.run.sim.minutes), float(sim.minutes), 0.31, "and the place's clock keeps in step with the base's")
	# the base lives meanwhile: Marcus goes about his day and the yard's own views do not follow it
	check(marcus.away == null, "Marcus is at the base, living")
	# a night falls while they are out
	sim.minutes = 18.8 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	_tick(scene, 20.0)
	check(String(sim.phase) in ["dusk", "night"], "dusk fell at the base: %s" % sim.phase)
	check(String(scene.run.sim.phase) == String(sim.phase), "and in the place")
	check(scene.hud_layer.mood_label.text in ["DUSK", "NIGHT"], "the HUD says so: %s" % scene.hud_layer.mood_label.text)
	check(scene.light_now().dark > 0.2, "the place is lit by it")
	# a call arrives
	var id: int = sim.radio.raise_call("sick", "Marcus has a fever", "Keep him apart?", [{"id": "treat", "label": "Treat him"}, {"id": "apart", "label": "Keep him apart"}], "treat", 60.0)
	scene.hud_layer.refresh()
	check(scene.hud_layer.call_card.visible and scene.hud_layer.call_card.shown_id == id, "the call card shows it")
	scene.hud_layer.call_card.view.buttons["treat"].pressed.emit()
	eq(String(sim.radio._entry(id).answered), "treat", "and answering reaches the base")
	# --- the way out
	var food: float = sim.stock.food
	_leave_place(scene)
	eq(scene.phase, "road_home", "the place ends and the road home begins")
	eq(String(scene.flow.party.state), "away", "the colony has the party on the road")
	var home := _drive_road(main, scene, "road_home")
	check(home.frames > 60 and home.most <= PlaceFlow.MAX_STEPS_PER_FRAME, "the road home is run the same way")
	eq(scene.phase, "report", "the report")
	check(main.raid == null and not main.raid_open() and main.world.visible and main.hud.visible, "the colony's view is back")
	eq(main.speed, 0, "its rules held under the report")
	check(scene.hud_layer.end_card != null and scene.hud_layer.end_card.visible, "the report card is up")
	# the party is home (or at the gate) after the road
	var steps := 0
	while not sim.scavenge.parties.is_empty() and steps < 30000:    # (a party that is out after dark comes in at dawn)
		sim.update(STEP)
		steps += 1
	check(dez.away == null and ruth.away == null, "they are home")
	check(sim.stock.food >= food, "with what they brought")
	# --- dismiss
	scene.go_home()
	eq(done.size(), 1, "the trip's result is given once")
	for k in ["loot", "hurt", "lost", "ammo_used", "beats", "hp"]:
		check(done[0].has(k), "with %s" % k)
	eq(main.speed, 2, "the speed is as it was")
	eq(main.cam_center, Vector2(37.5, 22.0), "the yard's camera is where it was")
	near(main.zoom_px, 44.0, 0.001, "and its zoom")
	await TutorialKit.frames(main, 2)
	check(not is_instance_valid(scene), "the scene is gone")
	await _leave(main)


func test_the_yard_does_not_update_draw_save_or_sound_while_the_place_is_played() -> void:
	var main := _main()
	var sim = main.sim
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	scene.set_process(false)
	_tick(scene, 3.0, 1.0 / 60.0)
	_drive_road(main, scene, "road_there")
	eq(scene.phase, "place", "in the place")
	var marcus = sim.people[2]
	var node = main.pawn_nodes[marcus]
	var seen_at: Vector2 = node.position
	var auto_before := 0
	if FileAccess.file_exists(SaveGame.AUTO_PATH):
		auto_before = FileAccess.get_modified_time(SaveGame.AUTO_PATH)
	sim.events.append({"type": "day_start", "day": 9})
	_tick(scene, 6.0)
	for i in 30:
		main._process(STEP)
	eq(node.position, seen_at, "the yard's pawn of a man at the base is not moved while the place is played")
	var t: float = sim.t
	main._process(STEP)
	near(sim.t, t, 0.0001, "the game's own frame does not step the colony")
	main._autosave()
	var auto_after := 0
	if FileAccess.file_exists(SaveGame.AUTO_PATH):
		auto_after = FileAccess.get_modified_time(SaveGame.AUTO_PATH)
	eq(auto_after, auto_before, "and nothing is saved from the yard while the place is played")
	scene.free()
	await _leave(main)


func test_a_pause_pauses_the_place_and_the_base_and_only_that() -> void:
	var main := _main()
	var sim = main.sim
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(main, scene, "road_there")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	scene._input(key)
	var t: float = sim.t
	var e: float = scene.run.elapsed
	_tick(scene, 3.0)
	near(sim.t, t, 0.0001, "the base did not move")
	near(scene.run.elapsed, e, 0.0001, "nor the place")
	scene._input(key)
	_tick(scene, 3.0)
	check(sim.t > t + 0.5 and scene.run.elapsed > e + 2.0, "both go on when it is lifted")
	scene.free()
	await _leave(main)


func test_the_colony_is_given_back_exactly_after_a_whole_trip() -> void:
	var main := _main()
	var sim = main.sim
	main.cam_center = Vector2(40.5, 20.0)
	main.zoom_px = 36.0
	main.speed = 3
	main._select({"kind": "person", "ref": sim.people[2]})
	var chosen = main.selection
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(main, scene, "road_there")
	_tick(scene, 3.0)
	_leave_place(scene)
	_drive_road(main, scene, "road_home")
	scene.go_home()
	eq(main.speed, 3, "the speed")
	eq(main.cam_center, Vector2(40.5, 20.0), "the camera")
	near(main.zoom_px, 36.0, 0.001, "the zoom")
	check(main.selection == chosen, "the selection")
	check(main.world.visible and main.overlay.visible and main.glow.visible and main.hud.visible, "everything shown")
	check(main.camera.is_current() and not main.menu_open, "the yard's camera is the current one and nothing holds the keys")
	await TutorialKit.frames(main, 2)
	await _leave(main)


func test_the_fall_of_the_leader_in_the_trip_hands_the_place_over_at_once_and_the_base_is_told_when_the_trip_ends() -> void:
	var main := _main()
	var sim = main.sim
	var ruth = sim.people[0]
	var dez = sim.people[1]
	dez.trust = 80.0
	var scene = main.open_raid([dez], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(main, scene, "road_there")
	var marcus = sim.people[2]
	var t0: float = marcus.trust
	var ruth_run = scene.leader()
	ruth_run.downed = true
	ruth_run.hp = 0.0
	_tick(scene, 0.3)
	eq(String(scene.leader().id), "dez", "Dez leads in the place")
	# she is only DOWN: the base is not told (she may be got up), nobody mourns yet
	eq(sim.player_id, "ruth", "the base's player is still Ruth: she is only down")
	near(marcus.trust, t0, 0.01, "nobody has lost any trust in the player: %.1f from %.1f" % [marcus.trust, t0])
	check(sim.radio.news.filter(func(e): return String(e.kind) == "succession").is_empty(), "and there is no word of a loss")
	_leave_place(scene)
	check(scene.final_result.lost.has("ruth"), "Ruth is lost in the result")
	eq(sim.player_id, "dez", "the trip is over and she is lost: the base is told, and hands over to the one the place chose")
	near(marcus.trust, t0 - 10.0, 1.0, "the base trusts the player ten less: %.1f from %.1f" % [marcus.trust, t0])
	_drive_road(main, scene, "road_home")
	var steps := 0
	while not sim.scavenge.parties.is_empty() and steps < 6000:
		sim.update(STEP)
		steps += 1
	check(ruth.dead, "Ruth did not come home")
	eq(sim.player_id, "dez", "and the base's player is still Dez: no second succession")
	check(not dez.dead and dez.away == null, "Dez is home")
	check(marcus.trust > t0 - 14.0, "(trust fell once)")
	eq(sim.radio.news.filter(func(e): return String(e.kind) == "succession").size(), 1, "one line of news about it")
	scene.go_home()
	await _leave(main)


func test_a_leader_who_was_got_up_and_came_home_is_no_loss_to_the_base() -> void:
	var main := _main()
	var sim = main.sim
	var ruth = sim.people[0]
	var dez = sim.people[1]
	var marcus = sim.people[2]
	var scene = main.open_raid([dez], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(main, scene, "road_there")
	var t0: float = marcus.trust
	var ruth_run = scene.leader()
	ruth_run.downed = true
	ruth_run.hp = 0.0
	_tick(scene, 0.3)
	eq(String(scene.leader().id), "dez", "Dez leads in the place")
	eq(sim.player_id, "ruth", "the base has not been told")
	# Dez gets her up (what the place's helping ends in)
	ruth_run.downed = false
	ruth_run.hp = 30.0
	_tick(scene, 0.2)
	_leave_place(scene)
	check(not scene.final_result.lost.has("ruth"), "Ruth is not lost")
	eq(String(scene.final_result.leader), "dez", "Dez led at the end")
	eq(sim.player_id, "dez", "the base's player is the one who led at the end")
	check(dez.player and not ruth.player, "(and Ruth is no longer the player)")
	near(marcus.trust, t0, 0.5, "with no setback: nobody trusts the player less: %.1f from %.1f" % [marcus.trust, t0])
	check(sim.radio.news.filter(func(e): return String(e.kind) == "succession").is_empty(), "and no news of a loss")
	_drive_road(main, scene, "road_home")
	var steps := 0
	while not sim.scavenge.parties.is_empty() and steps < 6000:
		sim.update(STEP)
		steps += 1
	check(not ruth.dead and ruth.away == null, "Ruth came home")
	eq(sim.player_id, "dez", "and Dez is still the player")
	check(marcus.trust >= t0 - 0.5, "no mourning came with her return: %.1f from %.1f" % [marcus.trust, t0])
	scene.go_home()
	await _leave(main)


func test_when_nobody_in_the_place_can_stand_the_base_is_told_and_goes_on_with_whoever_is_home() -> void:
	var main := _main()
	var sim = main.sim
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(main, scene, "road_there")
	for p in scene.run.squad:
		p.downed = true
		p.hp = 0.0
	_tick(scene, 0.5)
	check(scene.phase in ["road_home", "report"], "the place is over")
	check(scene.final_result.lost.size() == 2, "both are lost")
	_drive_road(main, scene, "road_home")
	check(scene.hud_layer.end_title.text == "Nobody came back", "the report says so: %s" % scene.hud_layer.end_title.text)
	var steps := 0
	while not sim.scavenge.parties.is_empty() and steps < 6000:
		sim.update(STEP)
		steps += 1
	check(sim.people[0].dead and sim.people[1].dead, "the base lost them")
	check(sim.player_id != "ruth" and sim.player_id != "", "the next at the base is the player: %s" % sim.player_id)
	check(sim.over == "", "and the run goes on")
	scene.go_home()
	await _leave(main)


func test_a_base_that_falls_while_the_place_is_played_ends_the_trip_and_the_game_shows_it() -> void:
	var main := _main()
	var sim = main.sim
	var done: Array = []
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, func(r): done.append(r))
	_drive_road(main, scene, "road_there")
	sim.over = "defeat"
	_tick(scene, 0.5)
	check(scene.phase in ["road_home", "report"], "the trip is turned back (a base that is over has no road to drive)")
	_drive_road(main, scene, "road_home")
	eq(scene.phase, "report", "and ends in its report")
	scene.go_home()
	eq(done.size(), 1, "the result is given")
	await _leave(main)


func test_a_trip_that_cannot_begin_leaves_the_game_as_it_was() -> void:
	var main := _main()
	var sim = main.sim
	sim.minutes = 22.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	check(scene == null and not main.raid_open(), "no trip after dark")
	check(main.world.visible and main.hud.visible, "the yard shows")
	eq(sim.scavenge.parties.size(), 0, "nobody went")
	check(sim.people[0].away == null and sim.people[1].away == null, "and nobody is away")
	await _leave(main)


func test_a_generated_site_is_played_through_the_whole_flow_for_each_kind_of_place() -> void:
	# the generator's own sites (no stand-in), through `open_raid` as the Town Board calls it: the road, a scripted search of the
	# nearest thing (the leader stands at it and presses E), the way out, the road home and the report
	for kind in ["houses", "pharmacy", "gas_station", "scrapyard"]:
		var main := _main()
		main.raid_stub = false
		var sim = main.sim
		var place := {}
		for pl in sim.town.all_places():
			if String(pl.kind) == kind:
				place = pl
				break
		check(not place.is_empty(), "the town has a %s" % kind)
		var place_id := String(place.id)
		if sim.town.state_of(place_id) == "unknown":
			sim.town.reveal(place_id)
		var done: Array = []
		var scene = main.open_raid([sim.people[1]], place, "", 1.0, func(r): done.append(r))
		if scene == null:
			failures.append("%s: the trip did not begin: %s" % [kind, main.hud.toast_label.text])
			await _leave(main)
			continue
		_drive_road(main, scene, "road_there")
		eq(scene.phase, "place", "%s: at the place" % kind)
		check(scene.run.containers.size() > 0, "%s: a site with things to search" % kind)
		var lead = scene.leader()
		# (this is about the flow, not the dead: a leader put among them would not live to press E)
		scene.run.sim.zombies.clear()
		scene.run._sleeping.clear()
		# the nearest thing to search: the leader walks to it (put there: the walk is the run's and the generator's) and presses E
		var best := {}
		var best_d := INF
		for c in scene.run.containers:
			if String(c.kind) == "survivor":
				continue
			var d := Vector2(c.pos).distance_to(Vector2(lead.x, lead.y))
			if d < best_d:
				best_d = d
				best = c
		# (the dead of the place may push them off the spot or wake: they go back to it and press E again, a few times at most)
		var e_key := InputEventKey.new()
		e_key.keycode = KEY_E
		e_key.pressed = true
		for attempt in 5:
			if bool(scene.run.container(String(best.id)).looted):
				break
			lead.x = best.pos.x
			lead.y = best.pos.y
			lead.path = []
			_tick(scene, 0.2)
			scene._input(e_key)
			_tick(scene, float(best.search_s) + 1.0)
		check(bool(scene.run.container(String(best.id)).looted), "%s: the %s was searched" % [kind, best.kind])
		_leave_place(scene)
		eq(scene.phase, "road_home", "%s: the way out ends the place" % kind)
		_drive_road(main, scene, "road_home")
		eq(scene.phase, "report", "%s: the report" % kind)
		scene.go_home()
		eq(done.size(), 1, "%s: the result is given once" % kind)
		for k in ["loot", "hurt", "lost", "ammo_used", "beats"]:
			check(done[0].has(k), "%s: the result has %s" % [kind, k])
		await _leave(main)


func test_a_trip_by_van_drives_there_and_home_and_the_van_comes_back() -> void:
	var main := _main()
	var sim = main.sim
	sim.vehicles.fleet.append({"id": "raid_van", "kind": "van", "hp": 80.0, "state": "parked"})
	sim.vehicles.fuel = 40.0
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "raid_van", 1.0, Callable())
	check(scene != null, "the trip begins: %s" % main.hud.toast_label.text)
	if scene == null:
		await _leave(main)
		return
	eq(String(sim.vehicles.vehicle("raid_van").state), "out", "the van is out")
	check(scene.hud_layer.road_title_label.text.begins_with("Driving to "), "'%s'" % scene.hud_layer.road_title_label.text)
	_drive_road(main, scene, "road_there")
	eq(scene.phase, "place", "at the place")
	check(scene.vehicle_node != null, "the van is drawn there")
	_tick(scene, 2.0)
	_leave_place(scene)
	eq(scene.phase, "road_home", "the way out")
	check(scene.hud_layer.road_title_label.text.begins_with("Driving home"), "'%s'" % scene.hud_layer.road_title_label.text)
	_drive_road(main, scene, "road_home")
	eq(scene.phase, "report", "the report")
	scene.go_home()
	var steps := 0
	while not sim.scavenge.parties.is_empty() and steps < 30000:
		sim.update(STEP)
		steps += 1
	eq(String(sim.vehicles.vehicle("raid_van").state), "parked", "the van is parked at the base again")
	check(sim.people[0].away == null and sim.people[1].away == null, "and the people are home")
	await _leave(main)
