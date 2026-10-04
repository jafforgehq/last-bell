extends "res://tests/case.gd"
## Round 23, ORDERS: "we can't unequip the weapon so we can properly issue orders". Q puts the weapon away or draws it (scripts/aim_mode.gd's
## `holstered`: no crosshair, no aim, no fire, R reloads nothing, F still shoves); a right click that is TAPPED (let go within AimMode.TAP_S without
## moving) is an order by radio for the person picked: the ground is Hold here at that tile, a night post To the walls, a person Come with me, and in a
## place a container is Search that and the exit Go back. The answer, the reason and Insist are the dock's own (scripts/ui/radio_verbs.gd `order`).
## Here the yard (scripts/main.gd) and one place (scripts/raid/raid_scene.gd).

const GD := preload("res://scripts/game_data.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")

const DT := 1.0 / 30.0
const SPOT := Vector2(41.5, 30.5)
const ZOOM := 40.0
const ARENA := Rect2i(34, 26, 20, 12)


# ----------------------------------------------------------------- helpers --

## The real game (a classic start, six people) with Ruth in the middle of a clear arena, in the default setting ("Right button aims").
func _game() -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 6, "avatar": true}, 1280, 800)
	AimMode.set_mode("right")
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			main.world.solid_p[ty * main.world.W + tx] = 0
			main.world.solid_z[ty * main.world.W + tx] = 0
	var sim = main.sim
	sim.zombies.clear()
	sim.waves.enabled = false
	sim.jobs.clear()
	sim.tactics.chores = false
	var p = sim.avatar.player()
	p.weapon = "rifle"
	p.gun = sim.weapons["rifle"]
	p.mag = int(p.gun.mag)
	p.x = SPOT.x
	p.y = SPOT.y
	p.facing = "E"
	p.aim = 0.0
	main.cam_center = SPOT
	main.zoom_px = ZOOM
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()
	_frames(main, 4)    # (the HUD sees the game: its dock has a radio to ask)
	return main


func _person(main: Node, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


func _stand(main: Node, p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.goal_key = ""
	p.order = null
	main._sync_views()


func _frames(main: Node, n: int) -> void:
	for i in n:
		main._process(DT)


func _at(main: Node, tile: Vector2) -> Vector2:
	return main._tile_to_screen(tile)


## A pointer event the way the game gets it: the HUD (`_input`) sees it first, and the world (`_unhandled_input`) when no control took it.
func _button(main: Node, at: Vector2, button: MouseButton, pressed: bool = true) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.pressed = pressed
	main._input(ev)
	if pressed:
		main._unhandled_input(ev)


func _motion(main: Node, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	main._input(ev)
	main._unhandled_input(ev)


func _click(main: Node, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(main, at, button, true)
	_button(main, at, button, false)


func _key(main: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	main._unhandled_input(ev)


func _toast(main: Node) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


func _dead_at(main: Node, x: float, y: float, hp: float):
	var z = main.sim.spawn(x, y, "wander")
	z.hp = hp
	z.stagger = 1.0e6
	z.limp = false
	return z


func _alive(z) -> bool:
	return z.state != "dying" and z.state != "dead"


func _pick(main: Node, p) -> void:
	main._try_select({"kind": "person", "ref": p})


# ------------------------------------------------------------ the holster --

func test_q_puts_the_weapon_away_and_draws_it_again_and_the_button_is_the_key() -> void:
	var main := _game()
	var ruth = main.sim.avatar.player()
	check(not AimMode.holstered, "a run begins with the weapon drawn")
	eq(main.hud.holster_button.text, AimMode.BUTTON_DRAWN, "the readout's button says so")
	_key(main, KEY_Q)
	check(AimMode.holstered and ruth.holstered, "Q puts it away (and the pawn carries it low)")
	eq(_toast(main), AimMode.NOW_AWAY, "a toast says so")
	eq(main.hud.holster_button.text, AimMode.BUTTON_AWAY, "the button says: put away")
	main.hud.holster_button.pressed.emit()
	check(not AimMode.holstered and not ruth.holstered, "the button is Q: it draws it again")
	eq(main.hud.holster_button.text, AimMode.BUTTON_DRAWN, "and says so")
	main.toggle_holster(false)
	await TutorialKit.leave(main)


func test_with_the_weapon_put_away_nothing_aims_or_fires_r_reloads_nothing_and_f_still_shoves() -> void:
	var main := _game()
	var ruth = main.sim.avatar.player()
	var z = _dead_at(main, SPOT.x - 3.0, SPOT.y, 1.0)
	_key(main, KEY_Q)
	var mag0: int = ruth.mag
	var tile := Vector2(z.x, z.y)
	_motion(main, _at(main, tile))
	_button(main, _at(main, tile), MOUSE_BUTTON_RIGHT, true)
	_frames(main, 2)
	check(main.aim_held and not main.aiming() and not main.aim_shown(), "the right button is down and nothing is aimed")
	eq(ruth.input_aim, Vector2.ZERO, "no aim is given")
	main.overlay.queue_redraw()
	await TutorialKit.settle()
	check(not main.overlay.drew_crosshair and not main.overlay.drew_aim_line, "no crosshair and no aim line")
	eq(main.pointer_mode(), Input.MOUSE_MODE_VISIBLE, "the pointer is the arrow")
	_button(main, _at(main, tile), MOUSE_BUTTON_LEFT, true)
	check(not main.firing, "the left button is only a click: the trigger is not held")
	_frames(main, 30)
	_button(main, _at(main, tile), MOUSE_BUTTON_LEFT, false)
	check(ruth.mag == mag0 and not ruth.input_fire and ruth.activity != "Firing", "Ruth shot nothing")
	_button(main, _at(main, tile), MOUSE_BUTTON_RIGHT, false)
	# R: nothing to reload, and the toast says why
	ruth.mag = maxi(1, mag0 - 3)
	main.hud.toast_panel.visible = false
	_key(main, KEY_R)
	_frames(main, 3)
	eq(_toast(main), AimMode.PUT_AWAY, "R says the weapon is put away")
	check(ruth.reloading <= 0.0 and ruth.mag == maxi(1, mag0 - 3), "and reloads nothing")
	# F: the shove is still there
	_key(main, KEY_F)
	_frames(main, 2)
	check(ruth.melee_t > 0.0 or ruth.thrust > 0.0, "F still swings")
	main.toggle_holster(false)
	await TutorialKit.leave(main)


func test_drawn_again_the_held_right_button_aims_and_a_hold_is_never_an_order() -> void:
	var main := _game()
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(38.5, 30.5))
	_pick(main, dez)
	var tile := Vector2(46.5, 33.5)
	_motion(main, _at(main, tile))
	_button(main, _at(main, tile), MOUSE_BUTTON_RIGHT, true)
	_frames(main, 20)    # (two thirds of a second)
	check(main.aiming() and main.aim_shown(), "held, the right button aims")
	check(main.sim.avatar.player().input_aim != Vector2.ZERO, "at the tile under the pointer")
	_button(main, _at(main, tile), MOUSE_BUTTON_RIGHT, false)
	eq(main.sim.radio.pending.size(), 0, "and a hold longer than a tap asks nobody anything")
	check(main.hud.radio_verbs.last.is_empty(), "the dock has no answer")
	await TutorialKit.leave(main)


func near_v(a: Vector2, b: Vector2, msg: String) -> void:
	check(a.distance_to(b) < 0.01, "%s (%s vs %s)" % [msg, str(a), str(b)])


# --------------------------------------------------------------- the orders --

func test_a_tapped_right_click_asks_the_person_picked_to_hold_that_tile_weapon_away_or_drawn() -> void:
	var main := _game()
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(38.5, 30.5))
	_pick(main, dez)
	main.toggle_holster(true)
	main.hud.toast_panel.visible = false
	_click(main, _at(main, Vector2(46.7, 33.2)), MOUSE_BUTTON_RIGHT)
	var radio = main.sim.radio
	eq(radio.pending.size(), 1, "one request is waiting on the radio")
	eq(String(radio.pending[0].verb), "hold", "Hold here")
	near_v(Vector2(radio.pending[0].at), Vector2(46.5, 33.5), "at the tile that was clicked")
	var last: Dictionary = main.hud.radio_verbs.last
	check(bool(last.ok) and String(last.verb) == "hold" and String(last.who) == "dez", "the dock has Dez's answer")
	check(main.hud.radio_verbs.reply.text.begins_with("Dez: "), "in its reply line: %s" % main.hud.radio_verbs.reply.text)
	check(_toast(main).begins_with("Dez: "), "and in a toast: %s" % _toast(main))
	check(main.order_flag != null and main.order_flag.kind == "hold" and main.order_flag.x == 46.5 and main.order_flag.y == 33.5, "a flag is put on the tile")
	main.overlay.queue_redraw()
	await TutorialKit.settle()
	check(main.overlay.drew_flag, "and drawn")
	check(dez.order == null, "Dez is not drafted the old way")
	_frames(main, 150)
	eq(String(dez.stance), "hold", "after the radio's delay Dez holds")
	near_v(dez.stance_at, Vector2(46.5, 33.5), "that tile")
	# the weapon drawn: the same tap, with somebody picked, is the same order (a hold is the aim)
	main.toggle_holster(false)
	_click(main, _at(main, Vector2(36.5, 28.5)), MOUSE_BUTTON_RIGHT)
	eq(String(radio.pending[0].verb) if not radio.pending.is_empty() else "", "hold", "drawn, a tap with Dez picked asks too")
	near_v(Vector2(radio.pending[0].at), Vector2(36.5, 28.5), "at the new tile")
	await TutorialKit.leave(main)


func test_a_tap_on_a_person_is_come_with_me_and_a_refusal_shows_its_reason_with_insist() -> void:
	var main := _game()
	var ana = _person(main, "ana")
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(38.5, 30.5))
	_stand(main, ana, Vector2(44.5, 33.5))
	ana.bleeding = 2.0
	_pick(main, ana)
	main.toggle_holster(true)
	main.hud.toast_panel.visible = false
	_click(main, _at(main, Vector2(38.5, 30.2)), MOUSE_BUTTON_RIGHT)
	var why := String(main.sim.radio.willingness(ana, "come").why)
	check(why != "", "(the radio has a reason: %s)" % why)
	var last: Dictionary = main.hud.radio_verbs.last
	check(not bool(last.ok) and String(last.verb) == "come", "Come with me was asked and refused")
	eq(String(last.why), why, "with the radio's own reason, not one of the view's")
	eq(main.hud.radio_verbs.reply.text, why, "in the dock's reply line")
	eq(_toast(main), why, "and in a toast")
	check(main.hud.radio_verbs.insist_button.visible, "Insist is offered (it is a soft refusal)")
	check(main.order_flag == null, "no flag for a refusal")
	eq(main.sim.radio.pending.size(), 0, "and nothing waits")
	main.hud.radio_verbs.insist_button.pressed.emit()
	eq(main.sim.radio.pending.size(), 1, "Insist asks again")
	main.toggle_holster(false)
	await TutorialKit.leave(main)


func test_a_tap_on_a_night_post_sends_them_to_the_walls_at_that_post() -> void:
	var main := _game()
	var dez = _person(main, "dez")
	_pick(main, dez)
	var jobs = main.sim.jobs
	var own := String(jobs.post_of(dez).id)
	var other := ""
	for po in jobs.posts():
		if String(po.id) != own and bool(main.sim.radio.post_willingness(dez, String(po.id)).ok):
			other = String(po.id)
			break
	check(other != "", "(a free post to send him to)")
	var at := Vector2(jobs.post(other).pos)
	main.order_at(dez, at + Vector2(0.3, 0.2))
	eq(String(jobs.post_of(dez).id), other, "the post is his now")
	eq(String(main.sim.radio.pending[0].verb), "post", "and he is sent to the walls")
	check(main.order_flag != null and main.order_flag.kind == "post", "a flag marks the post")
	await TutorialKit.leave(main)


func test_with_nobody_picked_a_right_click_says_to_pick_someone_when_the_weapon_is_away() -> void:
	var main := _game()
	main._select(null)
	main.hud.toast_panel.visible = false
	_click(main, _at(main, Vector2(46.5, 33.5)), MOUSE_BUTTON_RIGHT)
	eq(_toast(main), "", "drawn, a tap with nobody picked is only a short aim: no word")
	main.toggle_holster(true)
	main.hud.toast_panel.visible = false
	_click(main, _at(main, Vector2(46.5, 33.5)), MOUSE_BUTTON_RIGHT)
	eq(_toast(main), AimMode.NO_ONE, "put away, it says what to do")
	eq(main.sim.radio.pending.size(), 0, "and asks nobody")
	main.toggle_holster(false)
	await TutorialKit.leave(main)


# ------------------------------------------------------------------- a place --

const W := 30
const H := 16


func _site() -> Dictionary:
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
		],
		"dead": [], "rooms": [{"name": "hall", "rect": Rect2(15, 4, 9, 8)}], "seed": 1,
	}


func test_in_a_place_q_and_the_tapped_right_click_work_too() -> void:
	PlaceFlow.live_enabled = false
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": true}, 1280, 800)
	AimMode.set_mode("right")
	AimMode.set_holstered(true)
	var party: Array = []
	for i in 3:
		party.append(main.sim.people[i])
	var scene := RaidScene.new()
	main.add_child(scene)
	scene.set_process(false)
	scene.setup(main, main.hud, main.data, _site(), party, 300.0, "", 1.0, false)
	check(not AimMode.holstered, "a place begins with the weapon drawn")
	var lead = scene.leader()
	var friend = null
	for p in scene.run.squad:
		if p != lead:
			friend = p
	scene.hud_layer.pick_contact("squad", friend)
	var radio = scene.run.sim.radio
	# Q: put away; nothing aims; R says so
	var q := InputEventKey.new()
	q.keycode = KEY_Q
	q.pressed = true
	scene._input(q)
	check(AimMode.holstered and lead.holstered, "Q puts the weapon away in a place")
	scene.aim_held = true
	scene._mouse = Vector2(400.0, 300.0)
	check(not scene.aiming(), "and the right button aims at nothing")
	scene.aim_held = false
	# a tap on the container asks the squad member to search it; the ground to hold; the exit to go back
	var sp := scene.to_screen(Vector2(16.5, 6.5))
	_scene_click(scene, sp)
	check(not radio.pending.is_empty() and String(radio.pending[0].verb) == "search", "a tap on the container: Search that")
	_scene_click(scene, scene.to_screen(Vector2(19.5, 9.5)))
	check(not radio.pending.is_empty() and String(radio.pending[0].verb) == "hold", "a tap on the ground: Hold here")
	near_v(Vector2(radio.pending[0].at), Vector2(19.5, 9.5), "at that tile")
	_scene_click(scene, scene.to_screen(Vector2(5.5, 10.0)))
	check(not radio.pending.is_empty() and String(radio.pending[0].verb) == "back", "a tap on the exit: Go back")
	AimMode.set_holstered(false)
	PlaceFlow.live_enabled = true
	DriveScene.stand_ins = {}
	await TutorialKit.leave(main)


func _scene_click(scene: Node, at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.position = at
	ev.pressed = true
	scene._input(ev)
	scene._unhandled_input(ev)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.position = at
	up.pressed = false
	scene._input(up)
