extends "res://tests/case.gd"
## Round 21 "The live drive", integration (the plan's phase 3, written by FIXER-21 after the independent review): a whole live trip through
## the REAL flow, scene, road generator and events as the Town Board opens it (`main.open_raid`): the road there, the place, the road home,
## the report, and the books of the colony reconciled by what the trip recorded (the tank, the vehicle's hp, every store, the rounds, the
## people, the clock); a trip with a survivor, a toll, a search and a siphon; a night arrival (dusk falls at the place; the way home is a night
## road and the party is let in); the avatar dying on the road (the lead passes on, the base hears it once); the old overlay's road with no
## avatar (and with `--fastroad`); a round 17 save that loads and drives. The shared parts are in tests/drive_kit.gd.
## Seeds: with the pharmacy by van and two of the crew, seed 26 is a survivor on the way there and a wreck's search on the way home, 13 a
## checkpoint (its toll) and a search, 5 a fuel stash (a siphon) and a checkpoint.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const DriveKit := preload("res://tests/drive_kit.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const R17_SAVE := "res://tests/fixtures/round17_avatar_save.json"
const STEP := 1.0 / 30.0


func _game(avatar: bool = true, crew: int = 3) -> Node:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	PlaceFlow.no_events = false
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew, "avatar": avatar})
	main.sim.waves.enabled = false
	return main


func _end(main: Node) -> void:
	DriveScene.stand_ins = {}
	await TutorialKit.leave(main)


## The books of a settled trip: every one of them says what it should.
func _balanced(t: Dictionary, danger: int, label: String) -> void:
	var books: Dictionary = DriveKit.reconcile(t, danger)
	for k in books:
		near(float(books[k][1]), float(books[k][0]), 1.0e-6, "%s, the books: %s expected %.3f, the colony has %.3f" % [label, k, float(books[k][0]), float(books[k][1])])


# ------------------------------------------------------------------------ the test files' own flags --

## Review of round 21: three test files turned the live road off for the overlay's trips and never put it back; every test ends with
## it on now (`TutorialKit.leave`), so that what runs after them starts from the live road. (It reads as true in any order of the files.)
func test_the_live_road_is_on_when_a_test_starts() -> void:
	check(PlaceFlow.live_enabled, "live_enabled is on")
	check(not PlaceFlow.fast_road, "fast_road is off")
	check(not PlaceFlow.no_events, "the roads' events are on")


# ----------------------------------------------------------------------------------- a whole trip --

func test_a_whole_trip_with_a_survivor_and_a_search_the_books_balance_and_the_survivor_joins() -> void:
	var main := _game()
	var sim = main.sim
	var t := DriveKit.open(main, "pharmacy", "van", 2, 26, true, 50.0)
	var scene = t.scene
	check(scene != null and scene.phase == "place" and scene.leg == "there", "the live trip opens on the road there")
	if scene == null:
		await _end(main)
		return
	var crew0: int = sim.recruits.crew_size()
	var queued0: int = sim.recruits.queue.size()
	check(sim.recruits.housing_free() >= 1, "(there is a bed for the survivor)")
	check(not scene.road.is_empty() and scene.road.dir == -1 and scene.car != null, "a car on a road that runs north")
	eq(t.flow.stage, "drive_there", "the flow is on the road")
	var fuel0: float = t.before.fuel
	var need: float = sim.vehicles.fuel_for("pharmacy", t.vehicle)
	near(sim.vehicles.fuel, fuel0 - need, 1e-9, "both legs' fuel was taken at the gate, once")
	# the road there, then the place
	var steps := DriveKit.play(t, {}, DriveKit.place_gave({"meds": 4, "scrap": 6}, 5.0), 60000, func(s): return s.leg == "place")
	eq(scene.leg, "place", "at the place (%d steps)" % steps)
	eq(String(t.answered[0]), "survivor:take", "the survivor was taken in on the way there")
	eq(t.flow.road_survivors, 1, "the flow counts them")
	eq(t.flow.legs.size(), 1, "one leg is done")
	check(float(t.flow.legs[0].elapsed_min) > 20.0, "it took minutes (%.1f)" % float(t.flow.legs[0].elapsed_min))
	check(scene.phase == "place" and String(scene.site.kind) != "road", "the place is the generator's own")
	eq(scene.run.squad.size(), 3, "three of them, Ruth leading")
	# the place, and the road home
	DriveKit.play(t, {}, DriveKit.place_gave({"meds": 4, "scrap": 6}, 5.0), 60000, func(s): return s.leg == "home")
	eq(scene.leg, "home", "the way home")
	eq(scene.road.dir, 1, "the same road, south")
	check(bool(t.flow.party.get("road_live", false)), "the colony does not bring the party in by its own clock")
	DriveKit.play(t, {}, Callable(), 60000)
	eq(scene.phase, "report", "the report")
	eq(t.flow.stage, "home", "the flow is home")
	eq(t.flow.legs.size(), 2, "both legs")
	eq(String(t.answered[1]), "wreck_supplies:search", "the wreck was searched on the way home")
	# the report and the News tell the road
	var kinds: Array = []
	for n in t.flow.news():
		kinds.append(String(n.get("kind", "")))
	check(kinds.has("road"), "the News has the road's lines: %s" % str(kinds))
	var said := "\n".join(t.flow.news_lines())
	check(said.contains("Arrived"), "the log says how each leg went: %s" % said)
	check(main.trip_report == scene, "the colony counts the report as a page")
	# the colony brings them in; the books
	var settled := DriveKit.settle(sim)
	check(sim.scavenge.parties.is_empty(), "the party is home (%d colony steps)" % settled)
	eq(sim.recruits.crew_size(), crew0 + 1, "the survivor joined the crew")
	eq(sim.recruits.queue.size(), queued0 - 1, "and left the queue of callers")
	check(sim.recruits.arrived.size() >= 1, "they came in at the gate")
	_balanced(t, int(sim.town.place("pharmacy").danger), "survivor and search")
	eq(String(sim.vehicles.vehicle(t.vehicle).state), "parked", "the van is parked")
	check(float(sim.vehicles.vehicle(t.vehicle).hp) < float(t.before.hp), "worn by the road and the place")
	var done: Array = []
	scene.finished.connect(func(r): done.append(r))
	scene.go_home()
	eq(done.size(), 1, "the trip's result is given once")
	eq(int(done[0].get("road_survivors", 0)), 1, "with the survivor in it")
	check(main.raid == null, "the colony is back")
	await _end(main)


func test_a_whole_trip_with_a_siphon_and_a_toll_the_books_balance() -> void:
	var main := _game()
	var sim = main.sim
	var t := DriveKit.open(main, "pharmacy", "van", 2, 5, true, 50.0)
	var scene = t.scene
	check(scene != null, "the trip opens")
	if scene == null:
		await _end(main)
		return
	DriveKit.play(t, {}, DriveKit.place_gave({"meds": 4, "scrap": 6}, 5.0))
	eq(scene.phase, "report", "the report")
	eq(t.answered.size(), 2, "two cards were answered: %s" % str(t.answered))
	check(String(t.answered[0]).begins_with("fuel_stash") and String(t.answered[1]).begins_with("checkpoint"), "a siphon and a toll: %s" % str(t.answered))
	check(float(t.rec.fuel) >= 4.0, "the siphon put fuel in the tank (%.1f)" % float(t.rec.fuel))
	check(float(t.rec.stock.get("food", 0.0)) <= -10.0 + 1e-9, "the toll was paid at once (%s)" % str(t.rec.stock))
	DriveKit.settle(sim)
	_balanced(t, int(sim.town.place("pharmacy").danger), "siphon and toll")
	scene.go_home()
	await _end(main)


# ---------------------------------------------------------------------------- a night arrival --

func test_dusk_falls_at_the_place_the_way_home_is_a_night_road_and_the_party_is_let_in() -> void:
	var main := _game()
	var sim = main.sim
	var t := DriveKit.open(main, "pharmacy", "van", 2, 5, true, 50.0)
	var scene = t.scene
	check(scene != null, "the trip opens")
	if scene == null:
		await _end(main)
		return
	var danger := int(sim.town.place("pharmacy").danger)
	var day: Callable = DriveKit.place_gave({"meds": 4, "scrap": 6}, 5.0)
	var at_place := func(s: Node) -> void:
		day.call(s)
		s.stage("hour:21")    # (the place took the whole day)
	check(scene.road.ambient.is_empty(), "the road there is a day road")
	DriveKit.play(t, {}, at_place, 60000, func(s): return s.leg == "home")
	eq(scene.leg, "home", "the way home")
	check(not scene.road.ambient.is_empty() and String(scene.road.ambient[0].id) == "night_road", "it is a night road: %s" % str(scene.road.ambient))
	check(scene._has_headlights(), "with its headlights")
	check(sim.is_night(), "it is night at the base")
	DriveKit.play(t, {}, Callable(), 60000)
	eq(scene.phase, "report", "the report")
	check(bool(t.flow.party.get("night_ok", false)), "the party is let in at night")
	var settled := DriveKit.settle(sim)
	check(sim.scavenge.parties.is_empty(), "and comes in at the gate (%d steps)" % settled)
	check(not sim.people[1].dead and not sim.people[2].dead and sim.people[1].away == null, "everyone is home")
	_balanced(t, danger, "night arrival")
	scene.go_home()
	await _end(main)


# ----------------------------------------------------------------------- the avatar dies on the road --

func test_the_avatar_who_dies_on_the_road_hands_the_lead_on_and_the_base_is_told_once() -> void:
	var main := _game()
	var sim = main.sim
	var t := DriveKit.open(main, "pharmacy", "van", 2, 5, true, 50.0)
	var scene = t.scene
	check(scene != null, "the trip opens")
	if scene == null:
		await _end(main)
		return
	DriveKit.play(t, {}, Callable(), 60000, func(s): return s.road_progress() > 0.3)
	var ruth = scene.run.person("ruth")
	ruth.dead = true    # (a friend who is only down is got up at the next stop: this is the death)
	ruth.hp = 0.0
	DriveKit.play(t, {}, Callable(), 60000, func(s): return s.leader() != ruth)
	check(scene.leader() != ruth and scene.leader() != null, "the lead passes on at once: %s" % str(scene.leader().id if scene.leader() != null else null))
	eq(String(sim.player_id), "ruth", "(the base is told at the end of the trip)")
	DriveKit.play(t, {}, DriveKit.place_gave({"meds": 4}, 3.0), 60000, func(s): return s.leg == "place")
	eq(scene.run.squad.size(), 2, "the place is played by the two who are left")
	DriveKit.play(t, {}, DriveKit.place_gave({"meds": 4}, 3.0))
	eq(scene.phase, "report", "the trip goes on and ends")
	check(String(sim.player_id) != "ruth" and String(sim.player_id) in ["dez", "marcus"], "the base's player is the heir now: %s" % sim.player_id)
	DriveKit.settle(sim)
	var ruth_home = null
	for p in sim.people:
		if String(p.id) == "ruth":
			ruth_home = p
	check(ruth_home.dead, "Ruth did not come home")
	var successions := 0
	for e in sim.events:
		if String(e.get("type", "")) == "succession":
			successions += 1
	check(successions <= 1, "the succession was told once (%d)" % successions)
	check(sim.scavenge.parties.is_empty(), "the others are home")
	scene.go_home()
	await _end(main)


# ------------------------------------------------------------------------------ the old road --

func test_no_avatar_or_fastroad_keeps_the_overlays_road_and_the_old_trip_runs() -> void:
	# the classic game: no avatar, no live drive
	var main := _game(false)
	main.raid_stub = true
	var sim = main.sim
	check(not PlaceFlow.live_for(sim), "no avatar: the live road is not for this game")
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	check(scene != null and not scene.flow.live, "the trip opens as the old one: not live")
	eq(String(scene.phase), "road_there", "under the overlay's road")
	check(scene.get("car") == null, "no car in it")
	var frames := 0
	while String(scene.phase) == "road_there" and frames < 6000:
		scene.tick(1.0 / 30.0)
		frames += 1
	eq(String(scene.phase), "place", "the overlay's road ends in the place")
	var party: Dictionary = sim.scavenge.party_in_place()
	scene.free()
	if not party.is_empty():
		sim.scavenge.finish_played(party, {})
		for p in sim.people:
			p.away = null
		sim.scavenge.parties.clear()
	await _end(main)
	# `--fastroad` with an avatar: the overlay's road too
	var main2 := _game(true)
	main2.raid_stub = true
	PlaceFlow.fast_road = true
	var scene2 = main2.open_raid([main2.sim.people[1]], main2.sim.town.place("houses"), "", 1.0, Callable())
	check(scene2 != null and not scene2.flow.live, "--fastroad: not live, with an avatar")
	eq(String(scene2.phase), "road_there", "the overlay's road")
	var party2: Dictionary = main2.sim.scavenge.party_in_place()
	scene2.free()
	if not party2.is_empty():
		main2.sim.scavenge.finish_played(party2, {})
		for p in main2.sim.people:
			p.away = null
		main2.sim.scavenge.parties.clear()
	PlaceFlow.fast_road = false
	await _end(main2)


# -------------------------------------------------------------------------- a round 17 save --

func test_a_round_17_save_loads_and_a_live_trip_runs_in_it() -> void:
	var path := "user://test_r21_integ_r17.json"
	var text := FileAccess.get_file_as_string(R17_SAVE)
	check(text != "", "the fixture is there")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	check(SaveGame.is_loadable(path), "the save is one this version can load")
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	PlaceFlow.no_events = false
	var main = TutorialKit.start({"load": path}, 1280, 800)
	var sim = main.sim
	check(not main.load_failed, "it loaded")
	eq(sim.player_id, "ruth", "Ruth is still the player")
	check(PlaceFlow.live_for(sim), "and the live road is for this game")
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.storyteller.enabled = false
	sim.town.reveal("houses")
	sim.vehicles.fuel = 40.0
	var vehicle := String(sim.vehicles.add("pickup").id)
	var rec := DriveKit.Recorder.new()
	rec.sim = sim
	rec.vehicle_id = vehicle
	DriveScene.stand_ins = {"road_events": rec}
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), vehicle, 1.0, Callable())
	check(scene != null and scene.flow.live, "a live trip opens in the old save")
	if scene != null:
		scene.set_process(false)
		var t := {"scene": scene, "flow": scene.flow, "sim": sim, "main": main, "vehicle": vehicle, "rec": rec, "before": DriveKit.books(sim, vehicle), "answered": [], "place_id": "houses", "crew": [sim.people[1]]}
		DriveKit.play(t, {}, DriveKit.place_gave({"food": 9}, 2.0))
		eq(scene.phase, "report", "the old game's party drove, played and came back to the report")
		DriveKit.settle(sim)
		check(sim.scavenge.parties.is_empty(), "and is home")
		scene.go_home()
	await _end(main)
