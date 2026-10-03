extends "res://tests/case.gd"
## Round 17, S1.4 YARD: the player's controls and look in the yard (scripts/main.gd, scripts/render/overlay_node.gd,
## scripts/render/pawn_node.gd and the readouts of scripts/ui/hud.gd). In avatar mode (`sim.player_id != ""`) W A S D and
## the arrows walk the avatar, the mouse's tile is the aim, the left button held is the trigger, R reloads, F swings, the
## camera follows (and comes back after a jump), and the old yard controls are gone: no panning, no right-click orders, no
## picking in the world, no hotkeys of the orders. Without it (Orientation Day, the tests) the old controls stay, but box
## select, which is gone altogether. The sim's own rules are tests/test_avatar.gd's.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const MainScript := preload("res://scripts/main.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Kinds := preload("res://tests/test_pawn_kinds.gd")

const DT := 1.0 / 30.0
const SPOT := Vector2(41.5, 30.5)
const ZOOM := 40.0
const ARENA := Rect2i(34, 26, 20, 12)


# ----------------------------------------------------------------- helpers --

## The real game (a classic start, six people) in a window of this size. `avatar` asks for avatar mode (the tests do not get it
## unless they say so), and the camera is put on the spot with the avatar standing in the middle of a clear arena.
func _game(avatar: bool = true, width: int = 1280, height: int = 800) -> Node:
	var meta := {"difficulty": 1, "seed": 7, "crew": 6}
	if avatar:
		meta["avatar"] = true
	var main = TutorialKit.start(meta, width, height)
	_arena(main)
	var sim = main.sim
	sim.zombies.clear()
	sim.jobs.clear()
	sim.tactics.chores = false
	if avatar:
		var p = _player(main)
		p.weapon = "rifle"
		p.gun = sim.weapons["rifle"]
		p.mag = int(p.gun.mag)
		_stand(main, p, SPOT)
	_look(main, SPOT)
	return main


func _arena(main: Node) -> void:
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			main.world.solid_p[ty * main.world.W + tx] = 0
			main.world.solid_z[ty * main.world.W + tx] = 0


func _look(main: Node, at: Vector2) -> void:
	main.cam_center = at
	main.zoom_px = ZOOM
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()


func _player(main: Node):
	return main.sim.avatar.player()


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
	p.order = null
	main._sync_views()


## One of the dead standing still at a spot.
func _dead_at(main: Node, x: float, y: float, hp: float = 1.0):
	var z = main.sim.spawn(x, y, "wander")
	z.hp = hp
	z.stagger = 1.0e6
	z.limp = false
	return z


func _alive(z) -> bool:
	return z.state != "dying" and z.state != "dead"


func _frames(main: Node, n: int, dt: float = DT) -> void:
	for i in n:
		main._process(dt)


func _at(main: Node, tile: Vector2) -> Vector2:
	return main._tile_to_screen(tile)


func _button(main: Node, at: Vector2, button: MouseButton, pressed: bool = true) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.pressed = pressed
	main._unhandled_input(ev)


func _motion(main: Node, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	main._unhandled_input(ev)


func _click(main: Node, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(main, at, button, true)
	_button(main, at, button, false)


func _drag(main: Node, from: Vector2, to: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(main, from, button, true)
	_motion(main, from.lerp(to, 0.5))
	_motion(main, to)
	_button(main, to, button, false)


func _press(main: Node, code: Key, mods: Dictionary = {}) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	ev.ctrl_pressed = bool(mods.get("ctrl", false))
	ev.shift_pressed = bool(mods.get("shift", false))
	main._unhandled_input(ev)


## Keys held down, as the engine's input state has them (the frame reads them).
func _hold(codes: Array, down: bool) -> void:
	for code in codes:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _toast(main: Node) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


# ------------------------------------------------------------ avatar mode --

func test_a_run_asked_for_it_starts_with_ruth_as_the_avatar() -> void:
	var main := _game()
	eq(main.sim.player_id, "ruth", "Ruth is the player")
	check(main.avatar_mode, "and the yard knows it")
	check(_person(main, "ruth").player, "flagged")
	eq(main.hud.avatar_ui, true, "the HUD too")
	await TutorialKit.leave(main)


func test_the_first_starter_is_the_avatar_when_ruth_is_not_there() -> void:
	# (a small start has Ruth; a game is built without her by taking her out of the crew before the pick)
	var picked: String = MainScript.first_starter_id([{"id": "dez"}, {"id": "ana"}])
	eq(picked, "dez", "the first of the crew when Ruth is not among them")
	eq(MainScript.first_starter_id([{"id": "dez"}, {"id": "ruth"}]), "ruth", "Ruth when she is")
	eq(MainScript.first_starter_id([]), "", "and nobody for an empty crew")


func test_avatar_mode_is_off_in_the_tests_the_title_the_tutorial_and_with_noavatar() -> void:
	var off := _game(false)
	eq(off.sim.player_id, "", "a test's game has no avatar unless it asks")
	check(not off.avatar_mode, "so avatar mode is off")
	await TutorialKit.leave(off)
	var title = TutorialKit.start({"title": true, "avatar": true})
	eq(title.sim.player_id, "", "the title's yard has none")
	await TutorialKit.leave(title)
	var tut = TutorialKit.start({"tutorial": true})
	eq(tut.sim.player_id, "", "Orientation Day in a test's scene has none unless it asks, like any run")
	await TutorialKit.leave(tut)
	var lesson = TutorialKit.start({"tutorial": true, "avatar": true})
	eq(lesson.sim.player_id, "ruth", "and the avatar's Orientation Day, which the title asks for, is played by Ruth")
	await TutorialKit.leave(lesson)
	check(MainScript.wants_avatar([], {}, false, false, true), "a real run wants one")
	check(not MainScript.wants_avatar(["--noavatar"], {}, false, false, true), "--noavatar does not")
	check(not MainScript.wants_avatar([], {}, true, false, true), "not the title")
	check(MainScript.wants_avatar([], {"tutorial": true}, false, true, true), "the real game's Orientation Day wants one (the --tutorial flag, the title's button)")
	check(MainScript.wants_avatar([], {"tutorial": true, "avatar": true}, false, true, false), "and a test's, when it asks")
	check(not MainScript.wants_avatar([], {"tutorial": true}, false, true, false), "but not when it does not")
	check(not MainScript.wants_avatar(["--noavatar"], {"tutorial": true, "avatar": true}, false, true, true), "--noavatar plays the old yard's Orientation Day")
	check(not MainScript.wants_avatar([], {}, false, false, false), "not a test's scene")
	check(MainScript.wants_avatar([], {"avatar": true}, false, false, false), "unless the run says so")
	check(not MainScript.wants_avatar([], {"avatar": false}, false, false, true), "or says not")


func test_a_saved_game_with_a_player_restores_the_avatar() -> void:
	var main := _game()
	var path := "user://yard_avatar_test_save.json"
	check(SaveGame.write(main.sim, path), "saved")
	await TutorialKit.leave(main)
	var again = TutorialKit.start({"load": path})
	eq(again.sim.player_id, "ruth", "Ruth is the player again")
	check(again.avatar_mode, "and the yard is in avatar mode")
	await TutorialKit.leave(again)
	OS.move_to_trash(ProjectSettings.globalize_path(path))


# -------------------------------------------------------------------- input --

func test_wasd_walks_the_avatar() -> void:
	var main := _game()
	var ruth = _player(main)
	var x0: float = ruth.x
	_hold([KEY_D], true)
	_frames(main, 15)
	_hold([KEY_D], false)
	check(ruth.x > x0 + 1.2, "D walks right: %.2f to %.2f" % [x0, ruth.x])
	var y0: float = ruth.y
	_hold([KEY_S], true)
	_frames(main, 15)
	_hold([KEY_S], false)
	check(ruth.y > y0 + 1.2, "S walks down")
	var y1: float = ruth.y
	_hold([KEY_W], true)
	_frames(main, 15)
	_hold([KEY_W], false)
	check(ruth.y < y1 - 1.2, "W walks up")
	var x1: float = ruth.x
	_hold([KEY_LEFT], true)
	_frames(main, 15)
	_hold([KEY_LEFT], false)
	check(ruth.x < x1 - 1.2, "and the left arrow walks left")
	await TutorialKit.leave(main)


func test_a_diagonal_is_no_faster_and_ctrl_with_a_key_does_not_walk() -> void:
	var main := _game()
	var ruth = _player(main)
	var at := Vector2(ruth.x, ruth.y)
	_hold([KEY_D, KEY_S], true)
	_frames(main, 30)
	_hold([KEY_D, KEY_S], false)
	var run: float = at.distance_to(Vector2(ruth.x, ruth.y))
	check(run > 2.5 and run < 3.4, "a second on the diagonal is about the walk of one: %.2f tiles" % run)
	_stand(main, ruth, SPOT)
	_hold([KEY_CTRL, KEY_D], true)
	_frames(main, 10)
	_hold([KEY_CTRL, KEY_D], false)
	near(ruth.x, SPOT.x, 0.01, "Ctrl and D is a command, not a step")
	await TutorialKit.leave(main)


func test_the_mouse_aims_the_avatar() -> void:
	var main := _game()
	var ruth = _player(main)
	_motion(main, _at(main, Vector2(47.5, 30.5)))
	_frames(main, 1)
	near(ruth.input_aim.x, 47.5, 0.01, "the aim is the tile under the mouse")
	near(ruth.input_aim.y, 30.5, 0.01, "both ways")
	_frames(main, 2)
	check(absf(ruth.aim) < 0.1, "the gun points right: %.3f" % ruth.aim)
	eq(ruth.facing, "E", "and the avatar faces that way")
	_motion(main, _at(main, Vector2(33.5, 30.5)))
	_frames(main, 3)
	eq(ruth.facing, "W", "then left")
	check(absf(absf(ruth.aim) - PI) < 0.1, "the gun points left")
	await TutorialKit.leave(main)


func test_the_aim_follows_the_world_when_the_camera_moves_under_a_still_mouse() -> void:
	var main := _game()
	var ruth = _player(main)
	_motion(main, _at(main, Vector2(46.5, 30.5)))
	_frames(main, 2)
	var first: float = ruth.input_aim.x
	_hold([KEY_D], true)
	_frames(main, 30)
	_hold([KEY_D], false)
	check(ruth.input_aim.x > first + 1.0, "the mouse stays where it is on the screen: its tile moves with the camera (%.2f to %.2f)" % [first, ruth.input_aim.x])
	await TutorialKit.leave(main)


func test_the_held_button_fires_and_the_dead_in_front_fall() -> void:
	var main := _game()
	var ruth = _player(main)
	var z = _dead_at(main, 46.5, 30.5, 1.0)
	_motion(main, _at(main, Vector2(47.5, 30.5)))
	_frames(main, 2)
	var mag0: int = ruth.mag
	var ammo0: float = main.sim.stock.ammo
	_button(main, _at(main, Vector2(47.5, 30.5)), MOUSE_BUTTON_LEFT, true)
	check(main.firing, "the press is the trigger")
	_frames(main, 30)
	_button(main, _at(main, Vector2(47.5, 30.5)), MOUSE_BUTTON_LEFT, false)
	check(not main.firing, "and the release lets it go")
	check(not _alive(z), "the one in front of the gun is down")
	check(ruth.mag < mag0, "a round left the magazine: %d to %d" % [mag0, ruth.mag])
	check(main.sim.stock.ammo < ammo0, "and the stock is lighter")
	await TutorialKit.leave(main)


func test_a_release_that_never_reached_the_world_still_lets_go_of_the_trigger() -> void:
	var main := _game()
	_button(main, _at(main, SPOT), MOUSE_BUTTON_LEFT, true)
	check(main.firing, "held")
	# the release over a HUD control goes to the control: only the early `_input` sees it
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = Vector2(20.0, 20.0)
	main._input(ev)
	check(not main.firing, "released")
	await TutorialKit.leave(main)


func test_r_reloads_and_f_swings() -> void:
	var main := _game()
	var ruth = _player(main)
	ruth.mag = 3
	_press(main, KEY_R)
	_frames(main, 3)
	check(ruth.reloading > 0.0, "R starts a reload")
	check(not ruth.drafted, "and does not draft anyone")
	var z = _dead_at(main, 42.6, 30.5, 1.0)
	_motion(main, _at(main, Vector2(46.5, 30.5)))
	_frames(main, 1)
	_press(main, KEY_F)
	_frames(main, 3)
	check(not _alive(z), "F swings at what is within reach")
	check(ruth.thrust > 0.0 or ruth.melee_t > 0.0, "and the swing is on the person")
	await TutorialKit.leave(main)


func test_a_menu_zeroes_the_walk_and_the_trigger() -> void:
	var main := _game()
	var ruth = _player(main)
	_hold([KEY_D], true)
	_button(main, _at(main, SPOT), MOUSE_BUTTON_LEFT, true)
	_frames(main, 3)
	check(ruth.input_move.x > 0.5 and ruth.input_fire, "walking and firing")
	main.open_pause()
	main.speed = 1    # (the pause menu holds the rules; this checks the input alone)
	_frames(main, 3)
	eq(ruth.input_move, Vector2.ZERO, "the pause menu: no walking")
	check(not ruth.input_fire, "and no trigger")
	check(not main.firing, "the flag is let go")
	main.shell.close_all()
	_hold([KEY_D], false)
	await TutorialKit.leave(main)


func test_a_page_over_the_yard_zeroes_the_input_too() -> void:
	var main := _game()
	var ruth = _player(main)
	main.toggle_jobs()
	_hold([KEY_D], true)
	_frames(main, 3)
	_hold([KEY_D], false)
	eq(ruth.input_move, Vector2.ZERO, "the Duty roster is up: nobody walks")
	main.toggle_jobs()
	await TutorialKit.leave(main)


func test_the_title_has_no_avatar_input() -> void:
	var main = TutorialKit.start({"title": true, "avatar": true})
	check(not main.avatar_mode, "no avatar mode in the title")
	await TutorialKit.leave(main)


# ------------------------------------------------------------------ camera --

func test_the_camera_follows_the_avatar_eased_and_leads_toward_the_aim() -> void:
	var main := _game()
	var ruth = _player(main)
	main.cam_center = SPOT + Vector2(6.0, -4.0)
	_frames(main, 1)
	var d1: float = main.cam_center.distance_to(SPOT)
	check(d1 > 0.5 and d1 < SPOT.distance_to(SPOT + Vector2(6.0, -4.0)), "one frame closes part of the way: %.2f" % d1)
	_frames(main, 60)
	check(main.cam_center.distance_to(Vector2(ruth.x, ruth.y)) < 0.25, "a second later it is on the avatar")
	# the mouse at the right edge of the window: a lead, but never more than two tiles
	main.mouse_screen = Vector2(main._vp().x - 4.0, main._vp().y / 2.0)
	_frames(main, 90)
	var lead: float = main.cam_center.x - ruth.x
	check(lead > 0.5 and lead <= 2.05, "the camera leans toward the aim, within two tiles: %.2f" % lead)
	await TutorialKit.leave(main)


func test_the_camera_walks_with_the_avatar() -> void:
	var main := _game()
	var ruth = _player(main)
	_hold([KEY_D], true)
	_frames(main, 60)
	_hold([KEY_D], false)
	_frames(main, 30)
	check(ruth.x > SPOT.x + 3.0, "the avatar went on")
	check(absf(main.cam_center.x - ruth.x) < 0.5, "and the camera with them")
	await TutorialKit.leave(main)


func test_a_focus_jumps_the_camera_and_it_comes_back_after_a_moment() -> void:
	var main := _game()
	var ruth = _player(main)
	var far := Vector2(46.0, 33.0)
	var from: Vector2 = main.cam_center
	main._focus(far)
	check(main.cam_center.distance_to(from) < 0.2 * from.distance_to(far), "the jump is a glide, not a cut (round 17, QA M4): %s" % str(main.cam_center))
	_frames(main, 30)
	check(main.cam_center.distance_to(far) < 0.5, "it is there in under a second and stays a while")
	_frames(main, 90)
	check(main.cam_center.distance_to(Vector2(ruth.x, ruth.y)) < 0.5, "and then eases back to the avatar: %s" % str(main.cam_center))
	await TutorialKit.leave(main)


func test_tab_and_a_card_double_click_are_a_focus_too() -> void:
	var main := _game()
	var ana = _person(main, "ana")
	_stand(main, ana, Vector2(46.5, 33.5))
	_press(main, KEY_TAB)
	_frames(main, 1)
	check(main.selection != null and main.selection.kind == "person", "Tab picks someone")
	var target = main.selection.ref
	check(main.cam_hold > 0.5, "and holds the camera off the avatar for a while")
	main.hud.on_focus.call(ana)
	check(main.cam_hold > 1.0, "a double-click on a card as well")
	await TutorialKit.leave(main)


func test_a_succession_moves_the_camera_to_the_new_player_and_says_so() -> void:
	var main := _game()
	var sim = main.sim
	for q in sim.people:
		q.trust = 40.0
	var ana = _person(main, "ana")
	ana.trust = 95.0
	_stand(main, ana, Vector2(48.5, 34.5))
	sim.medical.kill(_person(main, "ruth"), "bled out")
	_frames(main, 1)
	eq(sim.player_id, "ana", "Ana leads")
	_frames(main, 30)
	check(main.cam_center.distance_to(Vector2(ana.x, ana.y)) < 1.0, "the camera glides to her (a second later it is on her): %s" % str(main.cam_center))
	eq(main.hud.banner_title.text.to_lower(), "ana leads now", "the banner says it")
	eq(main.hud.banner_sub.text, "Ruth is gone", "and why")
	await TutorialKit.leave(main)


# ---------------------------------------------------- what is gone in avatar mode --

func test_a_right_click_orders_nobody_in_avatar_mode() -> void:
	var main := _game()
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(38.5, 30.5))
	main._try_select({"kind": "person", "ref": dez})
	main.hud.toast_panel.visible = false
	_click(main, _at(main, Vector2(46.5, 33.5)), MOUSE_BUTTON_RIGHT)
	check(dez.order == null, "Dez has no order")
	check(main.order_mark == null, "no mark of one")
	eq(_toast(main), "", "and no word about it")
	await TutorialKit.leave(main)


func test_a_left_click_picks_nothing_in_the_world_in_avatar_mode_but_a_card_does() -> void:
	var main := _game()
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(38.5, 30.5))
	_click(main, _at(main, Vector2(38.5, 30.2)))
	check(main.selection == null, "a click on a person in the yard selects nobody")
	main.hud.on_select.call({"kind": "person", "ref": dez})
	check(main.selection != null and main.selection.ref == dez, "a crew card does")
	await TutorialKit.leave(main)


func test_the_view_does_not_pan_in_avatar_mode() -> void:
	var main := _game()
	var ruth = _player(main)
	_drag(main, Vector2(600.0, 400.0), Vector2(300.0, 300.0), MOUSE_BUTTON_MIDDLE)
	main.mouse_screen = main._vp() / 2.0    # (the pointer in the middle: no lead)
	_frames(main, 20)
	check(main.cam_center.distance_to(Vector2(ruth.x, ruth.y)) < 0.3, "a middle drag does not take the camera away")
	_drag(main, Vector2(600.0, 400.0), Vector2(300.0, 300.0), MOUSE_BUTTON_LEFT)
	main.mouse_screen = main._vp() / 2.0
	_frames(main, 20)
	check(main.cam_center.distance_to(Vector2(ruth.x, ruth.y)) < 0.3, "nor a left drag")
	check(main.selection == null, "and a left drag selects no one: the box is gone")
	await TutorialKit.leave(main)


func test_the_order_hotkeys_are_off_in_avatar_mode_but_the_pages_stay() -> void:
	var main := _game()
	var ana = _person(main, "ana")
	main._try_select({"kind": "person", "ref": ana})
	var job: String = main.sim.jobs.job_of(ana)
	for k in [KEY_P, KEY_C, KEY_T, KEY_X, KEY_B, KEY_M]:
		_press(main, k)
	eq(main.sim.jobs.job_of(ana), job, "B and M give no job")
	check(ana.order == null and not ana.drafted, "P and R give no order")
	eq(_toast(main), "", "and none of them says a word")
	var fields: bool = main.fields
	_press(main, KEY_V)
	check(main.fields != fields, "V still flips the fields of fire")
	# (round 18: in avatar mode J and N open the radio panel on its Jobs and Build pages; Shift is the modal page)
	_press(main, KEY_J)
	eq(main.hud.radio_page(), "jobs", "J opens the radio panel on Jobs")
	check(main.hud.jobs_screen == null, "and not the modal page")
	_press(main, KEY_J, {"shift": true})
	check(main.hud.jobs_screen != null, "Shift+J opens the Duty roster")
	main.toggle_jobs()
	_press(main, KEY_N)
	eq(main.hud.radio_page(), "build", "N moves the panel to Build")
	_press(main, KEY_N, {"shift": true})
	check(main.hud.build_screen != null, "Shift+N opens Build")
	main.toggle_build()
	main.hud.close_radio()
	await TutorialKit.leave(main)


func test_the_wheel_still_zooms_in_avatar_mode() -> void:
	var main := _game()
	var z0: float = main.zoom_px
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = main._vp() / 2.0
	main._unhandled_input(wheel)
	check(main.zoom_px > z0, "the wheel zooms in")
	await TutorialKit.leave(main)


func test_space_pauses_and_escape_is_the_menu_in_avatar_mode() -> void:
	var main := _game()
	_press(main, KEY_SPACE)
	eq(main.speed, 0, "Space pauses")
	_press(main, KEY_SPACE)
	eq(main.speed, 1, "and goes on")
	_press(main, KEY_ESCAPE)
	check(main.shell.is_open(), "Esc is the menu")
	main.shell.close_all()
	await TutorialKit.leave(main)


# --------------------------------------------------------------- box select --

func test_box_select_is_gone_altogether() -> void:
	for avatar in [true, false]:
		var main := _game(avatar)
		var names: Array = []
		for prop in main.get_property_list():
			names.append(String(prop.name))
		check(not names.has("selected_people"), "no group of the selected (avatar %s)" % avatar)
		check(not names.has("shot_box"), "no staged box")
		for method in ["select_people", "box_people", "select_everyone", "order_group_move", "_pick_people", "_toggle_person", "_set_primary", "_prune_selection", "_gizmo_group"]:
			check(not main.has_method(method), "%s is gone" % method)
		check(not main.hud.has_method("set_group"), "the HUD has no group")
		check(not ("group" in main.hud), "and no group list")
		_drag(main, _at(main, Vector2(36.0, 28.0)), _at(main, Vector2(46.0, 33.0)))
		check(main.selection == null, "a left drag over the crew selects nobody (avatar %s)" % avatar)
		check(main.drag == null, "and leaves no drag behind")
		await TutorialKit.leave(main)


func test_ctrl_a_selects_no_one() -> void:
	var main := _game(false)
	_press(main, KEY_A, {"ctrl": true})
	check(main.selection == null, "Ctrl and A select nobody: there is no everyone to select")
	await TutorialKit.leave(main)


# ------------------------------------------------- the old controls, no avatar --

func test_without_avatar_mode_a_click_selects_and_a_right_click_orders() -> void:
	var main := _game(false)
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(38.5, 30.5))
	_click(main, _at(main, Vector2(38.5, 30.2)))
	check(main.selection != null and main.selection.ref == dez, "a click on Dez selects him")
	_click(main, _at(main, Vector2(46.5, 33.5)), MOUSE_BUTTON_RIGHT)
	check(dez.order != null, "and a right-click sends him")
	check(main.order_mark != null, "with its mark")
	await TutorialKit.leave(main)


func test_without_avatar_mode_the_camera_pans_with_wasd_and_the_middle_button_and_a_left_drag_does_not() -> void:
	var main := _game(false)
	var c0: Vector2 = main.cam_center
	_hold([KEY_D, KEY_S], true)
	main._process(0.1)
	_hold([KEY_D, KEY_S], false)
	check(main.cam_center.x > c0.x + 0.5 and main.cam_center.y > c0.y + 0.5, "W A S D pan as ever")
	var c1: Vector2 = main.cam_center
	_drag(main, Vector2(600.0, 400.0), Vector2(300.0, 300.0), MOUSE_BUTTON_MIDDLE)
	check(main.cam_center.distance_to(c1) > 1.0, "and the middle button")
	var c2: Vector2 = main.cam_center
	_drag(main, Vector2(600.0, 400.0), Vector2(300.0, 300.0), MOUSE_BUTTON_LEFT)
	eq(main.cam_center, c2, "a left drag does nothing to the camera")
	check(main.selection == null, "and selects nothing")
	await TutorialKit.leave(main)


func test_without_avatar_mode_the_order_keys_still_work() -> void:
	var main := _game(false)
	var ana = _person(main, "ana")
	main._try_select({"kind": "person", "ref": ana})
	_press(main, KEY_R)
	check(ana.drafted, "R drafts")
	_press(main, KEY_R)
	check(not ana.drafted, "and releases")
	await TutorialKit.leave(main)


func test_without_avatar_mode_nobody_walks_with_the_keys() -> void:
	var main := _game(false)
	var ruth = _person(main, "ruth")
	var at := Vector2(ruth.x, ruth.y)
	_hold([KEY_D], true)
	_frames(main, 10)
	_hold([KEY_D], false)
	eq(Vector2(ruth.x, ruth.y), at, "Ruth stays where she is")
	await TutorialKit.leave(main)


## (What the round-15 tests of the yard's pan, click and order kept: the old controls, one person at a time.)

func test_without_avatar_mode_the_middle_button_and_alt_with_the_left_drag_the_camera() -> void:
	var main := _game(false)
	var ana = _person(main, "ana")
	main._select({"kind": "person", "ref": ana})
	var c0: Vector2 = main.cam_center
	_drag(main, Vector2(600.0, 400.0), Vector2(500.0, 350.0), MOUSE_BUTTON_MIDDLE)
	var moved: Vector2 = main.cam_center - c0
	near(moved.x, 100.0 / main.zoom_px, 0.05, "the ground follows the hand in x")
	near(moved.y, 50.0 / main.zoom_px, 0.05, "and in y")
	check(main.selection != null and main.selection.ref == ana, "and the selection is left alone")
	check(main.drag == null, "the drag is over")
	_click(main, _at(main, Vector2(37.0, 26.0)), MOUSE_BUTTON_MIDDLE)
	check(main.selection != null, "a middle click without moving lets go of nothing")
	var c1: Vector2 = main.cam_center
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.alt_pressed = true
	press.position = Vector2(600.0, 400.0)
	main._unhandled_input(press)
	_motion(main, Vector2(500.0, 350.0))
	press.pressed = false
	press.position = Vector2(500.0, 350.0)
	main._unhandled_input(press)
	near(main.cam_center.x - c1.x, 100.0 / main.zoom_px, 0.05, "Option and the left button pan too")
	await TutorialKit.leave(main)


func test_without_avatar_mode_the_pans_are_told_to_the_coach() -> void:
	var main = TutorialKit.game(0)
	await TutorialKit.frames(main, 4)
	var seen: float = float(main.coach.state.get("pan", 0.0))
	_drag(main, Vector2(600.0, 400.0), Vector2(300.0, 300.0), MOUSE_BUTTON_MIDDLE)
	check(float(main.coach.state.get("pan", 0.0)) > seen + 2.0, "a middle drag counts as a pan for the lesson: %s" % str(main.coach.state.get("pan")))
	var pan_was: float = float(main.coach.state.pan)
	_drag(main, Vector2(600.0, 400.0), Vector2(300.0, 300.0), MOUSE_BUTTON_LEFT)
	eq(float(main.coach.state.pan), pan_was, "a left drag is no pan")
	await TutorialKit.leave(main)


func test_without_avatar_mode_ctrl_a_does_not_pan_as_a_held_a_would() -> void:
	var main := _game(false)
	var c0: Vector2 = main.cam_center
	_hold([KEY_CTRL, KEY_A], true)
	main._process(0.1)
	_hold([KEY_CTRL, KEY_A], false)
	eq(main.cam_center, c0, "the camera did not move")
	_hold([KEY_A], true)
	main._process(0.1)
	_hold([KEY_A], false)
	check(main.cam_center.x < c0.x - 0.5, "(and A alone does pan left)")
	await TutorialKit.leave(main)


func test_the_wheel_and_the_trackpad_zoom_in_the_old_yard() -> void:
	var main := _game(false)
	var z0: float = main.zoom_px
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = main._vp() / 2.0
	main._unhandled_input(wheel)
	check(main.zoom_px > z0, "the wheel zooms in")
	var z1: float = main.zoom_px
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 0.8
	pinch.position = main._vp() / 2.0
	main._unhandled_input(pinch)
	check(main.zoom_px < z1, "and a pinch zooms out")
	var z2: float = main.zoom_px
	var scroll := InputEventPanGesture.new()
	scroll.delta = Vector2(0.0, -2.0)
	scroll.position = main._vp() / 2.0
	main._unhandled_input(scroll)
	check(main.zoom_px > z2, "and the two-finger scroll zooms")
	await TutorialKit.leave(main)


func test_without_avatar_mode_esc_lets_go_of_the_selection_then_opens_the_menu_and_tab_goes_round() -> void:
	var main := _game(false)
	var dez = _person(main, "dez")
	main._select({"kind": "person", "ref": dez})
	_press(main, KEY_ESCAPE)
	check(main.selection == null, "the first Esc lets go")
	check(not main.shell.is_open(), "and the menu is not open")
	_press(main, KEY_TAB)
	check(main.selection != null and main.selection.kind == "person", "Tab picks one person")
	_press(main, KEY_ESCAPE)
	_press(main, KEY_ESCAPE)
	check(main.shell.is_open(), "the second Esc opens the menu")
	main.shell.close_all()
	await TutorialKit.leave(main)


func test_without_avatar_mode_one_person_is_sent_to_the_click_and_with_nobody_the_toast_says_who_to_click_first() -> void:
	var main := _game(false)
	_click(main, _at(main, Vector2(41.5, 33.5)), MOUSE_BUTTON_RIGHT)
	eq(_toast(main), "Click someone first, then right-click where they should go", "as it always did")
	var ruth = _person(main, "ruth")
	main._select({"kind": "person", "ref": ruth})
	var goal := Vector2(41.5, 33.5)
	_click(main, _at(main, goal), MOUSE_BUTTON_RIGHT)
	check(ruth.order != null and Vector2(ruth.order.x, ruth.order.y).distance_to(goal) < 0.001, "sent to the click itself")
	await TutorialKit.leave(main)


func test_a_selected_person_wears_one_mark_and_the_crosshair_is_not_drawn_in_the_old_yard() -> void:
	var main := _game(false)
	main._select({"kind": "person", "ref": _person(main, "ruth")})
	_frames(main, 2)
	await _draw_once(main)
	eq(main.overlay.drawn_selected, 1, "one person, one mark")
	check(not main.overlay.drew_crosshair, "and no crosshair")
	await TutorialKit.leave(main)


# --------------------------------------------------------------------- look --

func _draw_once(main: Node) -> void:
	main.overlay.queue_redraw()
	await TutorialKit.settle()


func test_the_crosshair_and_the_aim_line_are_drawn_and_the_line_hides_while_reloading() -> void:
	var main := _game()
	var ruth = _player(main)
	_motion(main, _at(main, Vector2(47.5, 30.5)))
	_frames(main, 3)
	await _draw_once(main)
	check(main.overlay.drew_crosshair, "the crosshair is at the mouse")
	check(main.overlay.drew_aim_line, "and the line from the gun")
	check(not main.overlay.drew_reload_ring, "no reload ring while the gun is loaded")
	check(main.overlay.drew_you, "the avatar wears the YOU tag")
	check(main.overlay.crosshair_at.distance_to(main.mouse_screen) < 1.0, "the crosshair is where the mouse is")
	ruth.reloading = 1.0
	await _draw_once(main)
	check(not main.overlay.drew_aim_line, "the line is hidden while reloading")
	check(main.overlay.drew_reload_ring, "and the ring shows the reload")
	check(main.overlay.reload_progress > 0.0 and main.overlay.reload_progress < 1.0, "part of the way: %.2f" % main.overlay.reload_progress)
	await TutorialKit.leave(main)


func test_with_the_stores_dry_the_butt_is_in_the_hand_and_the_line_goes() -> void:
	var main := _game()
	main.sim.stock.ammo = 0.0
	_motion(main, _at(main, Vector2(47.5, 30.5)))
	_frames(main, 3)
	await _draw_once(main)
	check(not main.overlay.drew_aim_line, "no line for a gun that cannot fire")
	check(main.overlay.drew_crosshair, "but the pointer is still the crosshair")
	await TutorialKit.leave(main)


func test_the_reload_ring_fills_as_the_reload_goes() -> void:
	var main := _game()
	var ruth = _player(main)
	var total: float = float(ruth.gun.reload) * main.sim.traits.mult(ruth, "reload")
	ruth.reloading = total * 0.75
	await _draw_once(main)
	near(main.overlay.reload_progress, 0.25, 0.02, "a quarter of the way")
	ruth.reloading = total * 0.25
	await _draw_once(main)
	near(main.overlay.reload_progress, 0.75, 0.02, "three quarters")
	await TutorialKit.leave(main)


func test_no_crosshair_without_avatar_mode_or_over_a_menu() -> void:
	var off := _game(false)
	await _draw_once(off)
	check(not off.overlay.drew_crosshair and not off.overlay.drew_aim_line and not off.overlay.drew_you, "none of it in the old game")
	await TutorialKit.leave(off)
	var main := _game()
	main.open_pause()
	await _draw_once(main)
	check(not main.overlay.drew_crosshair, "none under the menu")
	main.shell.close_all()
	await TutorialKit.leave(main)


func test_the_aim_line_ends_at_the_first_thing_the_shot_would_hit() -> void:
	var main := _game()
	_dead_at(main, 44.5, 30.5, 5.0)
	_motion(main, _at(main, Vector2(50.5, 30.5)))
	_frames(main, 3)
	await _draw_once(main)
	var stop: Vector2 = main.overlay.aim_end
	check(stop.x > 43.5 and stop.x < 45.5, "it stops at the dead in front: %s" % str(stop))
	check(main.overlay.aim_on_target, "and says so")
	await TutorialKit.leave(main)


func test_the_crew_card_of_the_avatar_says_you() -> void:
	var main := _game()
	main.hud.update_hud(main.sim, 1, true, 0)
	var seen := 0
	for c in main.hud.cards:
		if c.p.player:
			seen += 1
			check(c.you.visible, "%s's card says YOU" % c.p.first)
			check(c.you.get_child(0).get_theme_font_size("font_size") >= 12, "in twelve pixels at least")
			check(c.you.size.y >= 15.0, "on a tag that is not under fifteen pixels high")
		else:
			check(not c.you.visible, "and no other card does (%s)" % c.p.first)
	eq(seen, 1, "one card")
	await TutorialKit.leave(main)


func test_the_you_tag_moves_with_a_succession() -> void:
	var main := _game()
	main.sim.medical.kill(_person(main, "ruth"), "bled out")
	_frames(main, 2)
	main.hud.update_hud(main.sim, 1, true, 0)
	var who := ""
	for c in main.hud.cards:
		if c.you.visible:
			who = String(c.p.id)
	eq(who, main.sim.player_id, "the tag is on the new player's card")
	await TutorialKit.leave(main)


func test_a_swing_is_drawn_for_a_gun_as_well_as_a_pike() -> void:
	var main := _game()
	var ruth = _player(main)
	var node = main.pawn_nodes[ruth]
	var still := _record(node)
	ruth.thrust = 0.8
	var swung := _record(node)
	check(swung > still, "a swing adds strokes to the drawing: %d against %d" % [swung, still])
	ruth.thrust = 0.0
	eq(_record(node), still, "and none when it is over")
	await TutorialKit.leave(main)


func _record(node) -> int:
	var tape = Kinds.Tape.new()
	node._pen = tape
	node._draw()
	node._pen = node
	return tape.cmds.size()


# ---------------------------------------------------------- the ammo readout --

func test_the_ammo_readout_shows_magazine_and_stock_and_the_weapon() -> void:
	var main := _game()
	var ruth = _player(main)
	ruth.mag = 12
	main.sim.stock.ammo = 340.0
	main.hud.update_hud(main.sim, 1, true, 0)
	check(main.hud.ammo_panel.visible, "the readout is up in avatar mode")
	eq(main.hud.ammo_label.text, "12 / 340", "magazine over stock")
	eq(main.hud.ammo_name.text, "Carbine", "and the weapon's name")
	await TutorialKit.leave(main)


func test_the_ammo_readout_is_amber_when_the_magazine_is_low_and_red_when_the_stock_is_dry() -> void:
	var main := _game()
	var ruth = _player(main)
	main.sim.stock.ammo = 100.0
	ruth.mag = 20
	main.hud.update_hud(main.sim, 1, true, 0)
	var calm: Color = main.hud.ammo_label.get_theme_color("font_color")
	ruth.mag = 3
	main.hud.update_hud(main.sim, 1, true, 0)
	eq(main.hud.ammo_label.get_theme_color("font_color"), Hud.WARN, "amber with three rounds left of twenty")
	check(calm != Hud.WARN, "and it was not before")
	main.sim.stock.ammo = 0.0
	main.hud.update_hud(main.sim, 1, true, 0)
	eq(main.hud.ammo_label.get_theme_color("font_color"), Hud.DANGER_TEXT, "red when there is nothing to reload with")
	eq(main.hud.ammo_label.text, "0 / 0", "and the numbers say it: with the stores dry there is nothing in the magazine to fire (round 17, QA I7)")
	await TutorialKit.leave(main)


func test_the_ammo_readout_has_a_reload_bar_that_follows_the_reload() -> void:
	var main := _game()
	var ruth = _player(main)
	var total: float = float(ruth.gun.reload) * main.sim.traits.mult(ruth, "reload")
	ruth.reloading = total * 0.5
	main.hud.update_hud(main.sim, 1, true, 0)
	near(main.hud.ammo_bar.value, 0.5, 0.02, "half way")
	ruth.reloading = 0.0
	ruth.mag = 10
	main.hud.update_hud(main.sim, 1, true, 0)
	near(main.hud.ammo_bar.value, 0.5, 0.02, "and with the gun ready, the bar is how full the magazine is")
	await TutorialKit.leave(main)


func test_the_ammo_readout_follows_the_player_and_is_gone_without_one() -> void:
	var main := _game()
	main.hud.update_hud(main.sim, 1, true, 0)
	check(main.hud.ammo_panel.visible, "up")
	main.sim.avatar.set_player(null)
	main.hud.update_hud(main.sim, 1, true, 0)
	check(not main.hud.ammo_panel.visible, "not when nobody is the player")
	await TutorialKit.leave(main)
	var off := _game(false)
	off.hud.update_hud(off.sim, 1, true, 0)
	check(not off.hud.ammo_panel.visible, "and not in the old game")
	await TutorialKit.leave(off)


func test_a_pike_has_no_magazine_to_show() -> void:
	var main := _game()
	var ruth = _player(main)
	ruth.weapon = "pike"
	ruth.gun = main.sim.weapons["pike"]
	main.hud.update_hud(main.sim, 1, true, 0)
	eq(main.hud.ammo_name.text, "Broom-handle pike", "its name")
	check(main.hud.ammo_label.text != "0 / %d" % int(main.sim.stock.ammo), "and no empty magazine")
	await TutorialKit.leave(main)


# ---------------------------------------------------------------- help, hint --

func test_the_help_and_the_hint_describe_the_avatar_controls_in_avatar_mode() -> void:
	var main := _game()
	main.hud.update_hud(main.sim, 1, true, 0)
	var help: String = " ".join(_texts(main.hud.help)).to_lower()
	for word in ["move", "aim", "fire", "reload", "melee", "zoom", "pause", "jobs", "build"]:
		check(help.contains(word), "the help says '%s'" % word)
	for gone in ["select a box", "everyone", "draft", "repair", "treat", "workbench", "builders"]:
		check(not help.contains(gone), "and no longer '%s'" % gone)
	var hint: String = " ".join(_texts(main.hud.hint)).to_lower()
	for word in ["move", "aim", "fire", "reload"]:
		check(hint.contains(word), "the hint says '%s'" % word)
	check(not hint.contains("pick a group"), "and not the group")
	await TutorialKit.leave(main)


func test_the_old_help_and_hint_say_nothing_of_a_group() -> void:
	var main := _game(false)
	main.hud.update_hud(main.sim, 1, true, 0)
	var help: String = " ".join(_texts(main.hud.help)).to_lower()
	check(not help.contains("select a box") and not help.contains("everyone") and not help.contains("add to it"), "no box in the help")
	check(help.contains("draft") and help.contains("pan"), "the old controls are still there")
	var hint: String = " ".join(_texts(main.hud.hint)).to_lower()
	check(not hint.contains("group"), "no group in the hint: %s" % hint)
	check(hint.contains("click") and hint.contains("send"), "but the old hint is")
	await TutorialKit.leave(main)


func test_the_avatar_help_fits_beside_the_clock_in_a_small_window() -> void:
	var main := _game(true, 700, 560)
	main.hud.update_hud(main.sim, 1, true, 0)
	main.hud.help.visible = true
	await TutorialKit.frames(main, 4)
	var help: Rect2 = main.hud.help.get_global_rect()
	var clock: Rect2 = main.hud.clock.get_global_rect()
	check(not help.intersects(clock), "the help does not cover the clock: %s and %s" % [str(help), str(clock)])
	check(Rect2(Vector2.ZERO, main._vp()).encloses(help.grow(-0.5)), "and is inside the window")
	await TutorialKit.leave(main)


func test_the_tips_of_an_avatar_run_do_not_name_the_controls_that_are_gone() -> void:
	var Hints = load("res://scripts/ui/hints.gd")
	var Coach = load("res://scripts/ui/coach.gd")
	for h in Hints.load_hints():
		var words := String(h.get("text_avatar", h.text))
		for gone in ["Select someone", "Select them", "Select it", "press T", "press M", "press X", "press F", "(F)"]:
			check(not words.contains(gone), "%s: no '%s' in the avatar words: %s" % [h.id, gone, words])
		var n: int = Coach.words(words)
		check(n >= 8 and n <= Coach.MAX_WORDS, "%s: %d words" % [h.id, n])
	var main := _game()
	check(main.hints != null, "a real run has its tips")
	for h in Hints.load_hints():
		if String(h.id) == "ammo":
			main.hints._show(h)
	check(main.hints.text_label.text.contains("Duty roster"), "the ammo tip says it with the avatar's words: %s" % main.hints.text_label.text)
	await TutorialKit.leave(main)
	var off := _game(false)
	for h in Hints.load_hints():
		if String(h.id) == "ammo":
			off.hints._show(h)
	check(off.hints.text_label.text.contains("press M"), "and the old words without one")
	await TutorialKit.leave(off)


func _texts(c: Node) -> Array:
	var out: Array = []
	for l in c.find_children("*", "Label", true, false):
		out.append(l.text)
	return out
