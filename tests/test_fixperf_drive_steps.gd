extends "res://tests/case.gd"
## The build of a trip in parts (scripts/drive/drive_scene.gd `step_build`, scripts/raid/raid_scene.gd `setup_world`, `setup_run`, `setup_ui`,
## `setup_finish`, `node_budget`): in a real window the road, the arrival at the place and the way home were each one frame of 80 to 320 ms
## behind a card that was drawn once. Now they are built a part a frame behind the card, and the scripts they need are read in the
## background a few seconds into a run. Headless keeps its one call (the other tests take the scene as it is returned), so these tests ask
## for the parts with `step_build`.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")
const MainScript := preload("res://scripts/main.gd")

const STEP := 1.0 / 30.0


func _game() -> Node:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	PlaceFlow.no_events = false
	return TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": true}, 1280, 800)


func _leave(main: Node) -> void:
	PlaceFlow.live_enabled = true
	PlaceFlow.no_events = false
	DriveScene.stand_ins = {}
	await TutorialKit.leave(main)


## A scene opened behind its card, the parts asked for. {"scene", "flow", "main"}.
func _opened(main: Node) -> Dictionary:
	var sim = main.sim
	sim.vehicles.fuel = 60.0
	sim.waves.enabled = false
	sim.town.reveal("pharmacy")
	var vid := String(sim.vehicles.add("pickup").id)
	var party: Array = [sim.people[0], sim.people[1]]
	var flow = PlaceFlow.new(sim)
	check(flow.begin(party, "pharmacy", vid), "the trip begins: %s" % flow.error)
	flow.live = true
	var place: Dictionary = sim.town.place("pharmacy")
	var scene := DriveScene.new()
	scene.step_build = true
	main.add_child(scene)
	scene.set_process(false)
	var maker := func(size: int, by_vehicle: bool) -> Dictionary: return SiteGen.make(place, 5, size, by_vehicle)
	scene.open_trip(main, main.hud, main.data, flow, place, maker, party, float(sim.stock.ammo), "pickup", 1.0, false)
	return {"scene": scene, "flow": flow, "main": main}


## Ticks until `done` (at most `limit`): the ticks taken and the longest of them in ms.
func _until(scene: Node, done: Callable, limit: int = 400) -> Dictionary:
	var n := 0
	var worst := 0.0
	while n < limit and not bool(done.call()):
		var t0 := Time.get_ticks_usec()
		scene.tick(STEP)
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		n += 1
	return {"n": n, "worst": worst}


func test_the_road_is_built_a_part_a_frame_behind_the_card() -> void:
	var main := _game()
	var t := _opened(main)
	var scene = t.scene
	check(not scene.built() and scene._hitch_layer.visible, "the card is up and nothing is built at the click")
	scene.tick(STEP)
	check(not scene.built(), "the frame the card was drawn in builds nothing")
	var r := _until(scene, func(): return scene.built())
	check(scene.built(), "it is built in the end")
	check(int(r.n) >= 5, "in at least five frames, not one (%d)" % int(r.n))
	print("    the road in parts: %d frames after the card, the longest %.0f ms (headless)" % [int(r.n), float(r.worst)])
	check(float(r.worst) < 700.0, "none of them is the whole build: the longest took %.0f ms" % float(r.worst))
	check(not scene._hitch_layer.visible and scene._steps.is_empty(), "the card is gone")
	check(scene.car != null and scene.car_node != null and scene.leg == "there" and scene.mode == "drive", "and the leg there is on, as when it is built at once")
	eq(String(t.flow.stage), "drive_there", "the flow counts it")
	check(scene.camera.is_current() and scene.hud_layer != null and scene.overlay != null, "the camera, the drive's HUD and its overlay are up")
	check(scene.pawn_nodes.has(scene.run.squad[0]), "the squad has pawns")
	check(scene.node_budget == -1, "and the budget of the dead's nodes is lifted")
	await _leave(main)


func test_the_scene_is_held_still_and_takes_no_key_while_it_is_built() -> void:
	var main := _game()
	var t := _opened(main)
	var scene = t.scene
	scene.tick(STEP)
	scene.tick(STEP)
	check(not scene.built() and scene._held_still(), "held still in the middle of the build")
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	scene._input(ev)
	_until(scene, func(): return scene.built())
	check(scene.built() and not scene._held_still(), "and let go when it is built")
	await _leave(main)


func test_the_dead_nodes_are_made_a_few_a_look_while_a_budget_is_set() -> void:
	var main := _game()
	var t := _opened(main)
	var scene = t.scene
	_until(scene, func(): return scene.built())
	var run = scene.run
	var before := 0
	for z in run.sim.zombies:
		if scene.pawn_nodes.has(z):
			before += 1
	for i in 10:
		run.sim.spawn(30.0 + float(i), 30.0, "approach", "walker")
	scene.node_budget = 3
	scene._sync_views(true)
	var made := 0
	for z in run.sim.zombies:
		if scene.pawn_nodes.has(z):
			made += 1
	eq(made - before, 3, "three nodes of the ten that are new")
	check(scene.nodes_missing, "and the rest are still to come")
	var looks := 1
	while scene.nodes_missing and looks < 10:
		scene._sync_views(true)
		looks += 1
	check(not scene.nodes_missing and looks <= 5, "all of them in four looks (%d)" % looks)
	for z in run.sim.zombies:
		check(scene.pawn_nodes.has(z), "a node each")
		break
	scene.node_budget = -1
	await _leave(main)


func test_the_arrival_and_the_way_home_are_built_in_parts_too() -> void:
	var main := _game()
	var t := _opened(main)
	var scene = t.scene
	_until(scene, func(): return scene.built())
	check(scene.built(), "(the road is up)")
	scene.stage("at:0.5")
	scene._end_leg()
	check(not scene._steps.is_empty() and scene._hitch_layer.visible, "the leg's end puts the card up with the arrival in parts")
	check(scene.leg == "there", "and nothing of the place is made yet")
	var r := _until(scene, func(): return scene._steps.is_empty())
	check(scene._steps.is_empty(), "the arrival is built")
	check(int(r.n) >= 4, "in at least four frames (%d)" % int(r.n))
	print("    the arrival in parts: %d frames, the longest %.0f ms (headless)" % [int(r.n), float(r.worst)])
	eq(scene.leg, "place", "the place is next")
	eq(scene.phase, "place", "still a place")
	eq(String(t.flow.stage), "place", "the flow says so")
	check(String(scene.site.kind) != "road" and scene.vehicle_node != null, "the place's own site, with the car by the entry")
	eq(scene.run.squad.size(), 2, "the squad came with the car")
	check(not scene._hitch_layer.visible, "the card is gone")
	# the way home
	scene.stage("exit")
	var go := _until(scene, func(): return not scene._steps.is_empty() or scene.leg == "home" or scene.phase == "report", 300)
	check(go.n < 300, "the place is over")
	if not scene._steps.is_empty():
		check(scene._hitch_layer.visible and scene.leg == "place", "the card is up and the road home is not yet")
		var home := _until(scene, func(): return scene._steps.is_empty())
		check(int(home.n) >= 4, "the way home in at least four frames (%d)" % int(home.n))
	eq(scene.leg, "home", "the way home")
	eq(String(t.flow.stage), "drive_home", "the flow's")
	check(scene.car != null and scene.mode == "drive" and scene.aboard().size() == 2, "in the car, both aboard")
	await _leave(main)


func test_a_staged_screenshot_gets_the_finished_scene() -> void:
	# (`stage` finishes what is left of a build in parts: the screenshots of the drive take the scene as the step left it)
	var main := _game()
	var t := _opened(main)
	var scene = t.scene
	_until(scene, func(): return scene.built())
	scene.stage("end")
	eq(scene.leg, "place", "`end` leaves the place built, not half built")
	check(scene._steps.is_empty() and scene.run != null and scene.pawn_nodes.size() >= 2, "with its squad and nothing left to build")
	await _leave(main)


func test_the_scripts_warmed_in_the_background_are_the_ones_a_trip_loads() -> void:
	var wanted := {}
	for k in DriveScene.PATHS:
		wanted[DriveScene.PATHS[k]] = true
	wanted[MainScript.DRIVE_SCENE] = true
	wanted[MainScript.SITE_GEN] = true
	for path in wanted:
		check(MainScript.TRIP_SCRIPTS.has(path), "%s is warmed" % path)
	for path in MainScript.TRIP_SCRIPTS:
		check(ResourceLoader.exists(path), "%s exists" % path)
