extends "res://tests/case.gd"
## Round 22, CONTROLS in a place and on the road (scripts/raid/raid_scene.gd, scripts/drive/drive_scene.gd; the setting is scripts/aim_mode.gd's, the
## yard's tests are tests/test_r22c_controls.gd): with "Right button aims" (the default) the pointer is free, the survivor faces the way they walk,
## the right button or Shift aims and the left button fires only then; a left click picks a friend and uses the container in reach ("Too far: walk
## closer" when it is not). "Always aim at the mouse" is the old behaviour. On the road the mouse is free and W A S D drive; the survivor's own shot
## is the right button's and then the left's.

const GD := preload("res://scripts/game_data.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
const RaidHud := preload("res://scripts/raid/raid_hud.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")
const DriveHud := preload("res://scripts/drive/drive_hud.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")
const AimMode := preload("res://scripts/aim_mode.gd")

const W := 30
const H := 16
const STEP := 1.0 / 30.0


func _site(dead: Array = []) -> Dictionary:
	var data: Dictionary = GD.load_all().duplicate(true)
	var terrain: Array = []
	var solid: Array = []
	for y in H:
		for x in W:
			terrain.append(1)
			var wall := (x >= 14 and x <= 24 and y >= 3 and y <= 12) and (x == 14 or x == 24 or y == 3 or y == 12) and not (x == 14 and y == 8)
			solid.append(1 if wall else 0)
	data["W"] = W
	data["H"] = H
	data["terrain"] = terrain
	data["solidZ"] = solid.duplicate()
	data["solidP"] = solid.duplicate()
	for k in ["objects", "walls", "marks", "lights", "trees", "segments", "people", "spawns"]:
		data[k] = []
	return {
		"name": "The test house", "kind": "houses", "danger": 2, "size": Vector2i(W, H), "data": data,
		"entry": Vector2(3.5, 8.5), "exit": Rect2(1.0, 6.5, 5.0, 4.0), "vehicle_spot": Vector2(3.5, 12.5),
		"containers": [
			{"id": "c1", "pos": Vector2(16.5, 6.5), "at": Vector2(16.5, 5.5), "kind": "cabinet", "loot": {"food": 10, "meds": 4}, "search_s": 4.0, "room": "hall"},
			{"id": "c2", "pos": Vector2(21.5, 9.5), "at": Vector2(21.5, 10.5), "kind": "shelf", "loot": {"scrap": 25, "ammo": 60}, "search_s": 6.0, "room": "back"},
			{"id": "c3", "pos": Vector2(10.5, 3.5), "at": Vector2(10.5, 2.5), "kind": "crate", "loot": {"water": 12}, "search_s": 3.0, "room": "yard"},
		],
		"dead": dead, "rooms": [{"name": "hall", "rect": Rect2(15, 4, 9, 8)}], "seed": 1,
	}


## The real game (a small start) with the avatar, in the setting `mode` ("right", the default, or "always").
func _game(mode: String = "right") -> Node:
	PlaceFlow.live_enabled = false
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": true}, 1280, 800)
	AimMode.set_mode(mode)
	return main


func _open(main: Node, dead: Array = []) -> Node:
	var party: Array = []
	for i in 3:
		party.append(main.sim.people[i])
	var scene := RaidScene.new()
	main.add_child(scene)
	scene.set_process(false)
	scene.setup(main, main.hud, main.data, _site(dead), party, 300.0, "", 1.0, false)
	return scene


func _leave(main: Node) -> void:
	PlaceFlow.live_enabled = true
	DriveScene.stand_ins = {}
	await TutorialKit.leave(main)


func _play(scene: Node, seconds: float) -> void:
	for i in int(seconds * 30.0):
		scene.tick(STEP)


func _key(scene: Node, code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = down
	scene._input(ev)


## A pointer event the way the window hands it: `_input` first (the HUD's early look), then `_unhandled_input` when nothing took it.
func _button(scene: Node, at: Vector2, button: MouseButton, pressed: bool = true) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.pressed = pressed
	scene._input(ev)
	if pressed:
		scene._unhandled_input(ev)


func _click(scene: Node, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(scene, at, button, true)
	_button(scene, at, button, false)


func _motion(scene: Node, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	scene._unhandled_input(ev)


func _put(p, x: float, y: float) -> void:
	p.x = x
	p.y = y
	p.path = []
	p.moving = false


func _quiet(scene: Node, keep) -> void:
	for p in scene.run.squad:
		if p != keep:
			_put(p, 2.5, 6.5)
			p.drafted = false
			p.stance = "hold"
			p.stance_at = Vector2(p.x, p.y)


func _toast(scene: Node) -> String:
	var h = scene.hud_layer
	return h.toast_label.text if h.toast_panel.visible else ""


# ------------------------------------------------------------------- a place --

func test_in_a_place_the_pointer_is_free_and_walking_turns_the_survivor() -> void:
	var main := _game()
	var scene := _open(main)
	var lead = scene.leader()
	_put(lead, 5.5, 8.5)
	_quiet(scene, lead)
	lead.facing = "E"
	lead.aim = 0.0
	for tile in [Vector2(2.5, 3.5), Vector2(12.5, 12.5), Vector2(6.5, 8.5)]:
		_motion(scene, scene.to_screen(tile))
		_play(scene, 0.2)
		eq(lead.input_aim, Vector2.ZERO, "no aim with the pointer over %s" % str(tile))
		eq(lead.facing, "E", "and the survivor does not turn")
		check(not scene.crosshair_shown() and not scene.aiming(), "no crosshair")
	_key(scene, KEY_A, true)
	_play(scene, 0.4)
	_key(scene, KEY_A, false)
	eq(lead.facing, "W", "walking west faces west")
	check(absf(absf(lead.aim) - PI) < 0.1, "with the gun")
	_play(scene, 0.5)
	eq(lead.facing, "W", "and standing keeps it")
	await _leave(main)


func test_in_a_place_the_right_button_aims_and_the_left_fires_only_then() -> void:
	var main := _game()
	var scene := _open(main, [{"pos": Vector2(9.5, 8.5), "kind": "walker", "state": "still"}])
	var lead = scene.leader()
	_put(lead, 5.5, 8.5)
	_quiet(scene, lead)
	var at: Vector2 = scene.to_screen(Vector2(9.5, 8.4))
	_motion(scene, at)
	var mag0: int = lead.mag
	# a click: no trigger, no turn
	lead.facing = "W"
	lead.aim = PI
	_click(scene, at)
	_play(scene, 0.5)
	check(not scene.fire_held and not lead.input_fire, "a left click is no trigger")
	eq(lead.facing, "W", "and no turn")
	eq(lead.mag, mag0, "no round")
	# the right button
	_button(scene, at, MOUSE_BUTTON_RIGHT, true)
	check(scene.aim_held and scene.aiming() and scene.crosshair_shown(), "aiming: the crosshair shows")
	_play(scene, 0.1)
	near(lead.input_aim.x, 9.5, 0.1, "at the tile under the pointer")
	eq(lead.facing, "E", "the survivor turned to it")
	_button(scene, at, MOUSE_BUTTON_LEFT, true)
	check(scene.fire_held, "the left press is the trigger now")
	_play(scene, 1.0)
	check(lead.mag < mag0 or lead.reloading > 0.0, "rounds left the gun")
	_button(scene, at, MOUSE_BUTTON_LEFT, false)
	_button(scene, at, MOUSE_BUTTON_RIGHT, false)
	check(not scene.aim_held and not scene.aiming(), "the aim is let go at once")
	_play(scene, 0.1)
	check(not lead.input_fire and lead.input_aim == Vector2.ZERO, "no trigger, no aim")
	await _leave(main)


func test_in_a_place_shift_aims_and_the_aim_is_let_go_over_the_hud_and_on_focus_loss() -> void:
	var main := _game()
	var scene := _open(main)
	var lead = scene.leader()
	_put(lead, 5.5, 8.5)
	_quiet(scene, lead)
	_motion(scene, scene.to_screen(Vector2(9.5, 8.4)))
	_key(scene, KEY_SHIFT, true)
	_play(scene, 0.1)
	check(scene.aiming(), "Shift held: aiming")
	_key(scene, KEY_SHIFT, false)
	check(not scene.aiming(), "Shift let go")
	_button(scene, scene.to_screen(Vector2(9.5, 8.4)), MOUSE_BUTTON_RIGHT, true)
	check(scene.aiming(), "the right button")
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1200.0, 100.0)
	scene._input(ev)
	check(not scene.aiming(), "over the HUD: no aim")
	_play(scene, 0.1)
	eq(lead.input_aim, Vector2.ZERO, "none given")
	_motion(scene, scene.to_screen(Vector2(9.5, 8.4)))
	check(scene.aiming(), "back on the place with the button still down: aiming again")
	scene._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not scene.aim_held and not scene.fire_held, "the focus is lost: the button is let go")
	_motion(scene, scene.to_screen(Vector2(9.5, 8.4)))
	check(not scene.aiming(), "and the aim is not back until it is pressed again")
	await _leave(main)


func test_in_a_place_a_click_searches_what_is_in_reach_and_says_so_when_it_is_not() -> void:
	var main := _game()
	var scene := _open(main)
	var lead = scene.leader()
	_quiet(scene, lead)
	# c1 is at (16.5, 6.5): out of reach from the entry
	_put(lead, 4.5, 8.5)
	_play(scene, 0.2)
	_click(scene, scene.to_screen(Vector2(16.5, 5.9)))
	eq(_toast(scene), "Too far: walk closer", "a container out of reach says so")
	eq(scene.run.searching_of(lead), "", "and nothing is searched")
	# beside it
	_put(lead, 16.5, 7.1)
	scene.cam_center = Vector2(16.5, 7.1)
	_play(scene, 0.3)
	_click(scene, scene.to_screen(Vector2(16.5, 5.9)))
	eq(scene.run.searching_of(lead), "c1", "in reach it is searched, as E would")
	# the ground does nothing
	scene.run.stop_search(lead)
	_click(scene, scene.to_screen(Vector2(19.5, 8.5)))
	eq(scene.run.searching_of(lead), "", "the bare ground does nothing")
	await _leave(main)


func test_in_a_place_a_click_on_a_friend_asks_them_over_the_radio() -> void:
	var main := _game()
	var scene := _open(main)
	var lead = scene.leader()
	_put(lead, 5.5, 8.5)
	var friend = null
	for p in scene.run.squad:
		if p != lead:
			friend = p
			break
	_put(friend, 8.5, 6.5)
	friend.stance = "hold"
	friend.stance_at = Vector2(friend.x, friend.y)
	_play(scene, 0.1)
	_click(scene, scene.to_screen(Vector2(friend.x, friend.y)))
	check(scene.is_selected(friend), "the friend is the radio's contact")
	_motion(scene, scene.to_screen(Vector2(friend.x, friend.y)))
	_play(scene, 0.1)
	eq(scene.pointed.get("kind", ""), "friend", "the hand is over them")
	# yourself is no contact
	scene.clear_contact()
	_click(scene, scene.to_screen(Vector2(lead.x, lead.y)))
	check(not scene.is_selected(lead), "you are not a contact")
	await _leave(main)


func test_in_a_place_always_aim_at_the_mouse_is_the_old_behaviour() -> void:
	var main := _game("always")
	var scene := _open(main, [{"pos": Vector2(9.5, 8.5), "kind": "walker", "state": "still"}])
	var lead = scene.leader()
	_put(lead, 5.5, 8.5)
	_quiet(scene, lead)
	var at: Vector2 = scene.to_screen(Vector2(9.5, 8.4))
	_motion(scene, at)
	_play(scene, 0.2)
	near(lead.input_aim.x, 9.5, 0.1, "the pointer aims with no button")
	check(scene.crosshair_shown(), "the crosshair is on the pointer")
	var mag0: int = lead.mag
	_button(scene, at, MOUSE_BUTTON_LEFT, true)
	check(scene.fire_held, "the left press is the trigger")
	_play(scene, 1.0)
	check(lead.mag < mag0 or lead.reloading > 0.0, "and it fires")
	_button(scene, at, MOUSE_BUTTON_LEFT, false)
	await _leave(main)


func test_the_legend_of_a_place_says_the_new_controls_and_the_old_ones_with_the_old_setting() -> void:
	var main := _game()
	var scene := _open(main)
	var words := " ".join(PackedStringArray(scene.hud_layer.legend_panel.find_children("*", "Label", true, false).map(func(l): return l.text)))
	check(words.contains("aim") and words.contains("shoot"), "the legend says aim and shoot: %s" % words)
	await _leave(main)
	var old := _game("always")
	var scene2 := _open(old)
	var words2 := " ".join(PackedStringArray(scene2.hud_layer.legend_panel.find_children("*", "Label", true, false).map(func(l): return l.text)))
	check(not words2.contains("aim") and words2.contains("shoot"), "with the old setting there is no aim key: %s" % words2)
	await _leave(old)


# ------------------------------------------------------------------ the road --

## A live trip to the pharmacy in a pickup with the squad aboard (as tests/test_drive_scene.gd has it).
func _trip(main: Node, kind: String = "pickup") -> Node:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	PlaceFlow.no_events = true
	var sim = main.sim
	sim.vehicles.fuel = 60.0
	sim.waves.enabled = false
	sim.town.reveal("pharmacy")
	var vid := ""
	if kind != "":
		vid = String(sim.vehicles.add(kind).id)
	var party: Array = []
	for i in 2:
		party.append(sim.people[i])
	var flow = PlaceFlow.new(sim)
	check(flow.begin(party, "pharmacy", vid), "the trip begins: %s" % flow.error)
	flow.live = true
	var place: Dictionary = sim.town.place("pharmacy")
	var scene := DriveScene.new()
	scene.no_events = true
	main.add_child(scene)
	scene.set_process(false)
	var maker := func(size: int, by_vehicle: bool) -> Dictionary: return SiteGen.make(place, 5, size, by_vehicle)
	scene.setup_trip(main, main.hud, main.data, flow, place, maker, party, float(sim.stock.ammo), kind, 1.0, false)
	scene.begin_trip(flow)
	return scene


func test_on_the_road_the_mouse_is_free_and_w_a_s_d_drive() -> void:
	var main := _game()
	var scene := _trip(main)
	_play(scene, 0.5)
	var lead = scene.leader()
	check(scene.in_car(), "aboard")
	_motion(scene, Vector2(400.0, 300.0))
	_key(scene, KEY_W, true)
	_play(scene, 1.5)
	_key(scene, KEY_W, false)
	check(scene.speed_now() > 0.5, "W drives the car (%.2f)" % scene.speed_now())
	eq(lead.input_aim, Vector2.ZERO, "the mouse aims nothing")
	check(not scene.crosshair_shown(), "and shows no crosshair")
	# a click is no shot
	_click(scene, Vector2(400.0, 300.0))
	_play(scene, 0.2)
	check(not scene.fire_held and not lead.input_fire, "a click does not fire")
	await _leave(main)


func test_on_the_road_the_survivors_own_shot_is_the_right_buttons_and_then_the_lefts() -> void:
	var main := _game()
	var scene := _trip(main)
	_play(scene, 0.5)
	var lead = scene.leader()
	var at := Vector2(500.0, 250.0)
	_motion(scene, at)
	_button(scene, at, MOUSE_BUTTON_RIGHT, true)
	_button(scene, at, MOUSE_BUTTON_LEFT, true)
	_play(scene, 0.1)
	check(scene.crosshair_shown(), "the crosshair while the right button is down")
	check(lead.input_fire, "the trigger is held: the survivor shoots from the car")
	check(lead.input_aim != Vector2.ZERO, "at the pointer's tile")
	_button(scene, at, MOUSE_BUTTON_LEFT, false)
	_button(scene, at, MOUSE_BUTTON_RIGHT, false)
	_play(scene, 0.1)
	check(not lead.input_fire and not scene.crosshair_shown(), "let go: free again")
	await _leave(main)


func test_on_the_road_always_aim_at_the_mouse_is_the_old_behaviour() -> void:
	var main := _game("always")
	var scene := _trip(main)
	_play(scene, 0.5)
	var lead = scene.leader()
	var at := Vector2(500.0, 250.0)
	_motion(scene, at)
	_play(scene, 0.1)
	check(scene.crosshair_shown() and lead.input_aim != Vector2.ZERO, "the pointer aims with no button")
	_button(scene, at, MOUSE_BUTTON_LEFT, true)
	_play(scene, 0.1)
	check(lead.input_fire, "and the left button fires")
	_button(scene, at, MOUSE_BUTTON_LEFT, false)
	await _leave(main)


func test_the_roads_legend_says_aim_and_the_old_setting_does_not() -> void:
	check(DriveHud.CAR_LEGEND.size() > DriveHud.CAR_LEGEND_ALWAYS.size() and DriveHud.FOOT_LEGEND.size() > DriveHud.FOOT_LEGEND_ALWAYS.size(), "one more key each")
	var main := _game()
	var scene := _trip(main)
	_play(scene, 0.3)
	var line: String = scene.hud_layer.legend_text()
	check(line.contains("aim") and line.contains("shoot"), "the road's legend: %s" % line)
	await _leave(main)
	var old := _game("always")
	var scene2 := _trip(old)
	_play(scene2, 0.3)
	var line2: String = scene2.hud_layer.legend_text()
	check(not line2.contains("aim") and line2.contains("shoot"), "the old setting's: %s" % line2)
	await _leave(old)
