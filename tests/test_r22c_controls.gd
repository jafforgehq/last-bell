extends "res://tests/case.gd"
## Round 22, CONTROLS: "it is hard to click anywhere since you are constantly aiming and rotating". The setting `ui.aim_mode`
## (scripts/aim_mode.gd): "Right button aims" (the default: the pointer is a free arrow, the survivor faces the way they walk, the right button or
## Shift aims and the left button fires only then, a left click picks people and uses what is in reach) and "Always aim at the mouse" (the way it
## was). Here the yard (scripts/main.gd, scripts/render/overlay_node.gd, scripts/ui/world_click.gd, the settings screen); the place and the road are
## tests/test_r22c_place.gd's.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const WorldClick := preload("res://scripts/ui/world_click.gd")
const Avatar := preload("res://scripts/sim/avatar.gd")
const Prefs := preload("res://scripts/prefs.gd")

const DT := 1.0 / 30.0
const SPOT := Vector2(41.5, 30.5)
const ZOOM := 40.0
const ARENA := Rect2i(34, 26, 20, 12)


## A stand-in for the rules' interact module (`TalkCard.interact_of` honours it): what is in reach and what is not are whatever a test says, and
## `use` only writes down what it was asked to use.
class FakeUse:
	extends RefCounted
	var sim
	var cands: Array = []
	var far: Array = []
	var used: Array = []

	func candidates() -> Array:
		return cands

	func far_things() -> Array:
		return far

	func best() -> Dictionary:
		return cands[0] if not cands.is_empty() else {}

	func needs_of(_p) -> Array:
		return []

	func use(cand: Dictionary = {}) -> Dictionary:
		var c := cand if not cand.is_empty() else best()
		used.append(c)
		if c.is_empty():
			return {"ok": false, "why": "Nothing here to use"}
		return {"ok": true, "kind": c.kind, "id": c.id, "line": "Used the %s." % c.kind, "why": ""}


# ----------------------------------------------------------------- helpers --

## The real game (a classic start, six people) with Ruth in the middle of a clear arena, the camera on her: in the setting `mode` ("right", the
## default, or "always").
func _game(mode: String = "right", width: int = 1280, height: int = 800) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 6, "avatar": true}, width, height)
	AimMode.set_mode(mode)
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			main.world.solid_p[ty * main.world.W + tx] = 0
			main.world.solid_z[ty * main.world.W + tx] = 0
	var sim = main.sim
	sim.zombies.clear()
	sim.waves.enabled = false
	sim.jobs.clear()
	sim.tactics.chores = false
	var p = _player(main)
	p.weapon = "rifle"
	p.gun = sim.weapons["rifle"]
	p.mag = int(p.gun.mag)
	_stand(main, p, SPOT)
	main.cam_center = SPOT
	main.zoom_px = ZOOM
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()
	return main


func _fake(main: Node) -> FakeUse:
	var f := FakeUse.new()
	f.sim = main.sim
	main.sim.set_meta("interact_stub", f)
	return f


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
	p.goal_key = ""
	p.order = null
	main._sync_views()


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


## A pointer event the way the game gets it: the HUD (`_input`) sees it first, and the world (`_unhandled_input`) only when no control took it.
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


func _draw_once(main: Node) -> void:
	main._process(DT)
	main.overlay.queue_redraw()
	await TutorialKit.settle()


func _cand(kind: String, id: String, pos: Vector2, label: String = "") -> Dictionary:
	return {"kind": kind, "id": id, "label": label if label != "" else "Use the %s" % kind, "pos": pos, "dist": 1.0, "ok": true, "why": ""}


# ------------------------------------------------------------ the setting --

func test_the_setting_defaults_to_the_right_button_and_keeps_what_it_is_given() -> void:
	TutorialKit.use_test_prefs()
	eq(AimMode.current(), "right", "the default")
	check(not AimMode.always(), "so the mouse does not aim all the time")
	AimMode.set_mode("always")
	eq(AimMode.current(), "always", "asked for")
	Prefs.forget()
	eq(AimMode.current(), "always", "and kept in the file")
	Prefs.set_value("ui", "aim_mode", "banana")
	eq(AimMode.current(), "right", "a word that is no mode is the default")
	AimMode.set_mode("nonsense")
	eq(AimMode.current(), "right", "and setting one is the default too")
	TutorialKit.restore_prefs()
	Prefs.reset()


func test_the_rules_of_who_is_aiming() -> void:
	# (mode, right held, shift held, pointer in the window, hands off, over the HUD)
	check(AimMode.aiming("right", true, false, true, false, false), "the right button aims")
	check(AimMode.aiming("right", false, true, true, false, false), "so does Shift")
	check(not AimMode.aiming("right", false, false, true, false, false), "nothing held: no")
	check(not AimMode.aiming("right", true, false, true, false, true), "not over a HUD control")
	check(not AimMode.aiming("right", true, false, true, true, false), "not under a menu or a page")
	check(not AimMode.aiming("right", true, false, false, false, false), "not out of the window")
	check(AimMode.aiming("always", false, false, true, false, false), "always: the pointer aims")
	check(not AimMode.aiming("always", true, false, false, false, false), "always: but not out of the window")
	near(Avatar.turn_toward(0.0, 1.0, 0.25), 0.25, 1.0e-6, "a turn is limited")
	near(Avatar.turn_toward(0.0, 0.1, 0.25), 0.1, 1.0e-6, "and arrives")
	near(Avatar.turn_toward(3.0, -3.0, 0.1), 3.1, 1.0e-6, "the short way round, through pi")


# ------------------------------------------------------- facing and aiming --

func test_the_survivor_faces_where_they_walk_and_keeps_it_standing() -> void:
	var main := _game()
	var ruth = _player(main)
	_hold([KEY_D], true)
	_frames(main, 12)
	eq(ruth.facing, "E", "walking east")
	eq(ruth.input_aim, Vector2.ZERO, "with no aim given: the pointer is free")
	_hold([KEY_D], false)
	_hold([KEY_A], true)
	_frames(main, 12)
	eq(ruth.facing, "W", "walking west")
	check(absf(absf(ruth.aim) - PI) < 0.3, "the gun turned to the way they go: %.2f" % ruth.aim)
	_hold([KEY_A], false)
	var facing := String(ruth.facing)
	var aim: float = ruth.aim
	_frames(main, 5)
	_hold([KEY_S], true)
	_frames(main, 12)
	eq(ruth.facing, "S", "walking south")
	_hold([KEY_S], false)
	_frames(main, 30)
	eq(ruth.facing, "S", "standing still keeps the last facing (it was %s, aim %.2f)" % [facing, aim])
	var kept: float = ruth.aim
	_frames(main, 30)
	near(ruth.aim, kept, 1.0e-6, "and the gun does not move")
	await TutorialKit.leave(main)


func test_the_gun_turns_smoothly_to_the_way_they_walk() -> void:
	var main := _game()
	var ruth = _player(main)
	ruth.aim = 0.0
	ruth.facing = "E"
	_hold([KEY_A], true)
	main._process(DT)
	# one step later the gun is part of the way, not all of it
	check(ruth.aim > 0.1 or ruth.aim < -0.1, "it has begun to turn: %.2f" % ruth.aim)
	check(absf(absf(ruth.aim) - PI) > 0.5, "and is not there yet: %.2f" % ruth.aim)
	_frames(main, 12)
	check(absf(absf(ruth.aim) - PI) < 0.05, "a fifth of a second later it points the way they walk: %.2f" % ruth.aim)
	_hold([KEY_A], false)
	await TutorialKit.leave(main)


func test_standing_with_a_free_pointer_the_gun_points_where_they_face_and_f_swings_that_way() -> void:
	var main := _game()
	var ruth = _player(main)
	# a facing and a gun that disagree (a start, a turn by the rules) are squared up
	ruth.facing = "W"
	ruth.aim = 0.0
	_frames(main, 2)
	check(absf(absf(ruth.aim) - PI) < 0.01, "the gun points west with them: %.2f" % ruth.aim)
	var west = _dead_at(main, SPOT.x - 1.0, SPOT.y, 5.0)
	var east = _dead_at(main, SPOT.x + 1.0, SPOT.y, 5.0)
	west.hp = 1.0
	east.hp = 1.0
	_motion(main, _at(main, Vector2(46.5, 30.5)))
	main._input(_key_event(KEY_F))
	main._unhandled_input(_key_event(KEY_F))
	_frames(main, 3)
	check(not _alive(west), "F swung west, the way they face")
	check(_alive(east), "and not east, where the pointer was")
	await TutorialKit.leave(main)


func _key_event(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func test_moving_the_mouse_about_neither_aims_nor_turns_the_survivor() -> void:
	var main := _game()
	var ruth = _player(main)
	ruth.facing = "E"
	ruth.aim = 0.0
	for tile in [Vector2(33.5, 28.5), Vector2(35.5, 36.5), Vector2(50.5, 27.5), Vector2(38.5, 30.5), Vector2(33.5, 30.5)]:
		_motion(main, _at(main, tile))
		_frames(main, 4)
		eq(ruth.facing, "E", "the facing stays with the mouse over %s" % str(tile))
		near(ruth.aim, 0.0, 1.0e-6, "and so does the gun")
		eq(ruth.input_aim, Vector2.ZERO, "nothing is aimed")
	# toward the HUD too
	_motion(main, Vector2(10.0, 10.0))
	_frames(main, 4)
	eq(ruth.facing, "E", "even over the HUD")
	await TutorialKit.leave(main)


func test_the_right_button_aims_and_the_left_fires_while_it_is_held() -> void:
	var main := _game()
	var ruth = _player(main)
	var z = _dead_at(main, 36.5, 30.5, 1.0)
	_motion(main, _at(main, Vector2(36.5, 30.5)))
	_frames(main, 2)
	eq(ruth.input_aim, Vector2.ZERO, "before the button: no aim")
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_RIGHT, true)
	check(main.aim_held and main.aiming(), "the right button is down: aiming")
	_frames(main, 1)
	near(ruth.input_aim.x, 36.5, 0.01, "the aim is the tile under the mouse")
	eq(ruth.facing, "W", "the survivor turned to it")
	check(absf(absf(ruth.aim) - PI) < 0.1, "and the gun with them")
	var mag0: int = ruth.mag
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_LEFT, true)
	check(main.firing, "the left press is the trigger while the right is held")
	_frames(main, 30)
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_LEFT, false)
	check(not _alive(z), "the dead in front of the gun is down")
	check(ruth.mag < mag0, "a round left the magazine")
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_RIGHT, false)
	check(not main.aim_held and not main.aiming(), "the right button let go: the aim is let go at once")
	_frames(main, 2)
	eq(ruth.input_aim, Vector2.ZERO, "no aim again")
	check(not ruth.input_fire, "and no trigger")
	eq(ruth.facing, "W", "the survivor stays as they were")
	await TutorialKit.leave(main)


func test_a_left_click_without_the_right_button_never_fires_and_never_turns_them() -> void:
	var main := _game()
	var ruth = _player(main)
	var z = _dead_at(main, 46.5, 30.5, 1.0)
	ruth.facing = "W"
	ruth.aim = PI
	var mag0: int = ruth.mag
	var shots0: int = int(ruth.stats.shots)
	for tile in [Vector2(46.5, 30.5), Vector2(36.5, 28.5), Vector2(44.5, 33.5)]:
		_motion(main, _at(main, tile))
		_click(main, _at(main, tile))
		_frames(main, 10)
		check(not main.firing, "a click is not the trigger (%s)" % str(tile))
		check(not ruth.input_fire, "and the survivor's trigger is not held")
	# the button held down for a good while is no trigger either
	_button(main, _at(main, Vector2(46.5, 30.5)), MOUSE_BUTTON_LEFT, true)
	_frames(main, 40)
	_button(main, _at(main, Vector2(46.5, 30.5)), MOUSE_BUTTON_LEFT, false)
	eq(ruth.facing, "W", "the survivor did not turn")
	near(ruth.aim, PI, 1.0e-6, "nor did the gun")
	eq(ruth.mag, mag0, "no round was fired")
	eq(int(ruth.stats.shots), shots0, "none counted")
	check(_alive(z), "the dead one is standing")
	await TutorialKit.leave(main)


func test_shift_is_the_right_button_for_one_hand() -> void:
	var main := _game()
	var ruth = _player(main)
	var z = _dead_at(main, 36.5, 30.5, 1.0)
	_motion(main, _at(main, Vector2(36.5, 30.5)))
	_hold([KEY_SHIFT], true)
	_frames(main, 1)
	check(main.aiming(), "Shift held: aiming")
	main._process(DT)
	near(ruth.input_aim.x, 36.5, 0.6, "at the tile under the mouse")
	eq(ruth.facing, "W", "facing it")
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_LEFT, true)
	_frames(main, 30)
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_LEFT, false)
	check(not _alive(z), "the left button fired with Shift held")
	_hold([KEY_SHIFT], false)
	_frames(main, 2)
	check(not main.aiming(), "Shift let go: not aiming")
	eq(ruth.input_aim, Vector2.ZERO, "no aim")
	await TutorialKit.leave(main)


func test_the_aim_is_let_go_over_the_hud_under_a_menu_out_of_the_window_and_on_focus_loss() -> void:
	var main := _game()
	var ruth = _player(main)
	_motion(main, _at(main, Vector2(36.5, 30.5)))
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_RIGHT, true)
	_frames(main, 2)
	check(main.aiming(), "aiming")
	# over a HUD control: the early `_input` has the motion and nothing reaches the world
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(30.0, 30.0)
	main._input(ev)
	_frames(main, 2)
	check(not main.aiming(), "over the HUD: not aiming")
	eq(ruth.input_aim, Vector2.ZERO, "no aim given")
	check(not ruth.input_fire, "and no trigger")
	_motion(main, _at(main, Vector2(36.5, 30.5)))
	_frames(main, 2)
	check(main.aiming(), "back over the world with the button still down: aiming again")
	# the pointer leaves the window
	main._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	_frames(main, 2)
	check(not main.aiming(), "out of the window: not aiming")
	_motion(main, _at(main, Vector2(36.5, 30.5)))
	check(main.aiming(), "and back")
	# a menu
	main.open_pause()
	main.speed = 1
	_frames(main, 2)
	check(not main.aiming() and not main.aim_held, "under a menu: not aiming, and the held button is forgotten")
	main.shell.close_all()
	# the focus
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_RIGHT, true)
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_LEFT, true)
	check(main.aiming() and main.firing, "the right button down and the trigger held")
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not main.aim_held and not main.firing, "the window lost the focus: both are let go")
	_frames(main, 2)
	check(not main.aiming(), "not aiming")
	eq(ruth.input_aim, Vector2.ZERO, "no aim")
	await TutorialKit.leave(main)


func test_the_aim_follows_the_pointer_not_a_stale_tile() -> void:
	var main := _game()
	var ruth = _player(main)
	_motion(main, _at(main, Vector2(46.5, 30.5)))
	_button(main, _at(main, Vector2(46.5, 30.5)), MOUSE_BUTTON_RIGHT, true)
	_frames(main, 2)
	eq(ruth.facing, "E", "east")
	_motion(main, _at(main, Vector2(36.5, 30.5)))
	_frames(main, 2)
	eq(ruth.facing, "W", "and as the pointer moves the survivor turns with it")
	_button(main, _at(main, Vector2(36.5, 30.5)), MOUSE_BUTTON_RIGHT, false)
	await TutorialKit.leave(main)


func test_the_camera_leans_toward_the_pointer_only_while_aiming() -> void:
	var main := _game()
	var ruth = _player(main)
	main.mouse_screen = Vector2(main._vp().x - 4.0, main._vp().y / 2.0)
	_frames(main, 90)
	var free: float = main.cam_center.x - ruth.x
	check(absf(free) < 0.3, "a free pointer at the edge of the window does not move the camera: %.2f" % free)
	main.aim_held = true
	_frames(main, 90)
	var aimed: float = main.cam_center.x - ruth.x
	check(aimed > 0.5, "aiming toward the edge leans the camera: %.2f" % aimed)
	main.aim_held = false
	await TutorialKit.leave(main)


# --------------------------------------------------------------- the pointer --

func test_the_pointer_is_a_free_arrow_until_the_right_button_and_is_the_crosshair_then() -> void:
	var main := _game()
	_motion(main, _at(main, Vector2(46.5, 30.5)))
	_frames(main, 2)
	eq(main.pointer_mode(), Input.MOUSE_MODE_VISIBLE, "a free arrow over the bare world")
	_button(main, _at(main, Vector2(46.5, 30.5)), MOUSE_BUTTON_RIGHT, true)
	eq(main.pointer_mode(), Input.MOUSE_MODE_HIDDEN, "the crosshair is drawn instead while the right button is down")
	_button(main, _at(main, Vector2(46.5, 30.5)), MOUSE_BUTTON_RIGHT, false)
	eq(main.pointer_mode(), Input.MOUSE_MODE_VISIBLE, "and the arrow is back at once")
	await TutorialKit.leave(main)
	var old := _game("always")
	_motion(old, _at(old, Vector2(46.5, 30.5)))
	eq(old.pointer_mode(), Input.MOUSE_MODE_HIDDEN, "\"Always aim at the mouse\": the crosshair over the bare world, as it was")
	await TutorialKit.leave(old)


func test_the_crosshair_and_the_aim_line_show_only_while_aiming() -> void:
	var main := _game()
	_motion(main, _at(main, Vector2(46.5, 30.5)))
	_frames(main, 2)
	await _draw_once(main)
	check(not main.overlay.drew_crosshair, "no crosshair on a free pointer")
	check(not main.overlay.drew_aim_line, "and no aim line")
	check(main.overlay.drew_you, "(the YOU tag is there)")
	_button(main, _at(main, Vector2(46.5, 30.5)), MOUSE_BUTTON_RIGHT, true)
	await _draw_once(main)
	check(main.overlay.drew_crosshair, "the crosshair while the right button is down")
	check(main.overlay.drew_aim_line, "and the line from the gun")
	check(main.overlay.crosshair_at.distance_to(main.mouse_screen) < 1.0, "the crosshair is where the pointer is")
	_button(main, _at(main, Vector2(46.5, 30.5)), MOUSE_BUTTON_RIGHT, false)
	await _draw_once(main)
	check(not main.overlay.drew_crosshair and not main.overlay.drew_aim_line, "gone with the button")
	await TutorialKit.leave(main)


# ------------------------------------------------- "Always aim at the mouse" --

func test_always_aim_at_the_mouse_is_the_old_behaviour_exactly() -> void:
	var main := _game("always")
	var ruth = _player(main)
	var z = _dead_at(main, 46.5, 30.5, 1.0)
	_motion(main, _at(main, Vector2(47.5, 30.5)))
	_frames(main, 1)
	near(ruth.input_aim.x, 47.5, 0.01, "the mouse aims with no button")
	eq(ruth.facing, "E", "the survivor faces it")
	_motion(main, _at(main, Vector2(33.5, 30.5)))
	_frames(main, 3)
	eq(ruth.facing, "W", "and turns with it")
	_motion(main, _at(main, Vector2(47.5, 30.5)))
	_frames(main, 3)
	var mag0: int = ruth.mag
	_button(main, _at(main, Vector2(47.5, 30.5)), MOUSE_BUTTON_LEFT, true)
	check(main.firing, "the left press is the trigger, with no right button")
	_frames(main, 30)
	_button(main, _at(main, Vector2(47.5, 30.5)), MOUSE_BUTTON_LEFT, false)
	check(not _alive(z) and ruth.mag < mag0, "and it fires")
	await _draw_once(main)
	check(main.overlay.drew_crosshair and main.overlay.drew_aim_line, "the crosshair and the line are drawn with no button")
	# a left click on a person picks nobody
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(44.5, 33.5))
	main._select(null)
	_click(main, _at(main, Vector2(44.5, 33.5)))
	check(main.selection == null, "a click in the world picks nobody")
	await TutorialKit.leave(main)


# ---------------------------------------------------------------- clicking --

func test_a_left_click_on_a_person_selects_them_and_opens_their_dock() -> void:
	var main := _game()
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(45.5, 33.5))
	_frames(main, 1)
	_click(main, _at(main, Vector2(45.5, 33.5)))
	check(main.selection != null and main.selection.kind == "person" and main.selection.ref == dez, "Dez is selected")
	check(not main.firing, "and nothing was fired")
	await _draw_once(main)
	check(main.hud.dock_rect().size != Vector2.ZERO, "their dock is up (the radio's verbs)")
	# a click on the bare ground does nothing (and does not clear)
	_click(main, _at(main, Vector2(38.5, 27.5)))
	check(main.selection != null and main.selection.ref == dez, "the ground does nothing")
	# not the survivor you are
	var me = _player(main)
	main._select(null)
	_click(main, _at(main, Vector2(me.x, me.y)))
	check(main.selection == null, "a click on yourself picks nobody")
	await TutorialKit.leave(main)


func test_a_click_while_aiming_picks_nobody() -> void:
	var main := _game()
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(45.5, 33.5))
	_button(main, _at(main, Vector2(45.5, 33.5)), MOUSE_BUTTON_RIGHT, true)
	_click(main, _at(main, Vector2(45.5, 33.5)))
	check(main.selection == null, "with the right button held a left click is the trigger, not a pick")
	_button(main, _at(main, Vector2(45.5, 33.5)), MOUSE_BUTTON_RIGHT, false)
	await TutorialKit.leave(main)


func test_a_click_on_a_person_in_reach_also_talks_to_them() -> void:
	var main := _game()
	var f := _fake(main)
	var dez = _person(main, "dez")
	var me = _player(main)
	_stand(main, dez, Vector2(me.x + 1.2, me.y))
	f.cands = [_cand("person", "dez", Vector2(dez.x, dez.y), "Talk to Dez")]
	_frames(main, 1)
	_click(main, _at(main, Vector2(dez.x, dez.y)))
	check(main.selection != null and main.selection.ref == dez, "selected")
	eq(f.used.size(), 1, "and used, as E would")
	check(main.hud.talk_open(), "the talk card is open")
	_click(main, _at(main, Vector2(dez.x, dez.y)))
	eq(f.used.size(), 1, "a second click on the same person does not talk again")
	await TutorialKit.leave(main)


func test_a_left_click_on_a_thing_in_reach_uses_it_like_e_and_out_of_reach_says_so() -> void:
	var main := _game()
	var f := _fake(main)
	var gate_at := Vector2(me_x(main) + 1.0, me_y(main) + 1.5)
	f.cands = [_cand("gate", "gate", gate_at, "Open the gate")]
	_frames(main, 1)
	_click(main, _at(main, gate_at))
	eq(f.used.size(), 1, "the gate in reach is used")
	eq(String(f.used[0].kind), "gate", "it is the gate")
	eq(_toast(main), "Used the gate.", "and its answer is the toast, as E has it")
	# a click beside it, on the bare ground, does nothing
	f.used.clear()
	_click(main, _at(main, Vector2(me_x(main) - 4.0, me_y(main) - 2.0)))
	eq(f.used.size(), 0, "the ground does nothing")
	# a post out of reach: the toast says so and nothing is used
	var far_at := Vector2(me_x(main) + 6.0, me_y(main) + 2.0)
	f.far = [_cand("post", "gate", far_at, "The gate post")]
	_click(main, _at(main, far_at))
	eq(f.used.size(), 0, "a post that is out of reach is not used")
	eq(_toast(main), "Too far: walk closer", "the toast says why")
	await TutorialKit.leave(main)


func me_x(main: Node) -> float:
	return _player(main).x


func me_y(main: Node) -> float:
	return _player(main).y


func test_a_click_on_a_real_post_takes_it_and_far_away_it_does_not() -> void:
	var main := _game()
	var sim = main.sim
	var posts: Array = sim.jobs.posts()
	check(not posts.is_empty(), "the yard has night posts")
	var po: Dictionary = posts[0]
	var at := Vector2(po.pos)
	var me = _player(main)
	# out of reach first
	_stand(main, me, Vector2(41.5, 30.5))
	main.cam_center = at
	main._clamp_camera()
	main._apply_camera()
	_frames(main, 2)
	if main._screen_to_tile(Vector2.ZERO).distance_to(at) < 100.0 and Rect2(Vector2.ZERO, main._vp()).has_point(_at(main, at)):
		_click(main, _at(main, at))
		eq(sim.interact.posted, "", "too far to take a post")
		eq(_toast(main), "Too far: walk closer", "and the toast says so")
	# and in reach
	_stand(main, me, at + Vector2(0.4, 0.0))
	main.cam_center = at
	main._clamp_camera()
	main._apply_camera()
	_frames(main, 2)
	var cands: Array = sim.interact.candidates()
	var listed := false
	for c in cands:
		if String(c.kind) == "post" and String(c.id) == String(po.id):
			listed = true
	check(listed, "the post is in reach now")
	_click(main, _at(main, at))
	var took: bool = sim.interact.posted == String(po.id)
	var refused := _toast(main)
	check(took or refused != "", "the click used the post (or the rules said why not: %s)" % refused)
	await TutorialKit.leave(main)


func test_hovering_a_thing_shows_a_ring_and_the_pill_and_out_of_reach_a_tag() -> void:
	var main := _game()
	var f := _fake(main)
	var me = _player(main)
	var near_at := Vector2(me.x + 2.5, me.y + 1.5)
	var near_other := Vector2(me.x - 2.0, me.y + 2.0)
	f.cands = [_cand("post", "a", near_other, "Take the A post"), _cand("bench", "bench", near_at, "Work the bench")]
	f.cands[0]["dist"] = 0.5
	f.cands[1]["dist"] = 2.0
	_motion(main, _at(main, near_at))
	await _draw_once(main)
	check(main.overlay.drew_hover_ring, "a ring on the thing under the pointer")
	eq(main.overlay.hover_key, "bench:bench", "it is the bench, not the nearer post")
	check(main.overlay.prompt_text.contains("Work the bench"), "and the pill says what a click does: %s" % main.overlay.prompt_text)
	check(main.pointed.kind == "thing" and main.pointed.near, "the game knows")
	eq(main.cursor_shape, Input.CURSOR_POINTING_HAND, "the cursor is a hand")
	# off it: the pill is on the nearest again and there is no hover ring
	_motion(main, _at(main, Vector2(me.x - 5.0, me.y - 3.0)))
	await _draw_once(main)
	check(not main.overlay.drew_hover_ring, "no hover ring off it")
	check(main.overlay.drew_prompt, "the pill is still on the nearest thing")
	eq(main.cursor_shape, Input.CURSOR_ARROW, "and the cursor is the arrow")
	# out of reach
	var far_at := Vector2(me.x + 5.0, me.y - 3.0)
	f.far = [_cand("post", "z", far_at, "The Z post")]
	_motion(main, _at(main, far_at))
	await _draw_once(main)
	check(main.overlay.drew_far_tag, "a thing out of reach says \"Too far\" under the pointer")
	check(not main.overlay.drew_hover_ring or main.overlay.hover_key != "post:z", "and is not offered as something to use")
	# while aiming: none of it
	_button(main, _at(main, far_at), MOUSE_BUTTON_RIGHT, true)
	await _draw_once(main)
	check(not main.overlay.drew_far_tag and not main.overlay.drew_hover_ring, "no hover marks while aiming")
	_button(main, _at(main, far_at), MOUSE_BUTTON_RIGHT, false)
	await TutorialKit.leave(main)


func test_hovering_a_person_marks_them_and_the_hand_shows() -> void:
	var main := _game()
	var dez = _person(main, "dez")
	_stand(main, dez, Vector2(45.5, 33.5))
	_motion(main, _at(main, Vector2(45.5, 33.5)))
	_frames(main, 2)
	check(main.hover == dez, "the old mark of the person under the pointer")
	eq(main.cursor_shape, Input.CURSOR_POINTING_HAND, "a hand over a person")
	_motion(main, _at(main, Vector2(38.5, 27.5)))
	_frames(main, 2)
	check(main.hover == null, "and none off them")
	await TutorialKit.leave(main)


func test_world_click_finds_what_a_point_is_on() -> void:
	var things := [
		_cand("post", "a", Vector2(10.0, 10.0)), _cand("bench", "bench", Vector2(14.0, 10.0)),
		_cand("wall", "3", Vector2(30.0, 10.0)), _cand("vehicle", "van", Vector2(40.0, 10.0)), _cand("gate", "gate", Vector2(50.0, 10.0)),
		_cand("person", "dez", Vector2(10.0, 10.0)),
	]
	things[2]["seg"] = 3
	eq(String(WorldClick.under(Vector2(10.4, 10.3), things).get("id", "")), "a", "on the post")
	eq(WorldClick.under(Vector2(12.0, 10.0), things), {}, "between them: nothing")
	eq(String(WorldClick.under(Vector2(14.9, 10.0), things).get("id", "")), "bench", "on the bench")
	eq(String(WorldClick.under(Vector2(50.5, 10.5), things).get("id", "")), "gate", "on the gate, a kind that has no table entry")
	eq(WorldClick.under(Vector2(33.5, 10.0), things), {}, "a wall's spot is not where its picture is")
	eq(String(WorldClick.under(Vector2(33.5, 10.0), things, {"seg": 3}).get("id", "")), "3", "but the picture says it is the wall")
	eq(String(WorldClick.under(Vector2(44.0, 12.0), things, {"vehicle": "van"}).get("id", "")), "van", "likewise a vehicle")
	eq(WorldClick.under(Vector2(10.0, 10.0), [things[5]]), {}, "a person is the yard's own pick, never this")
	eq(String(WorldClick.listed({"kind": "post", "id": "a"}, things).get("kind", "")), "post", "listed finds the same kind and id")
	eq(WorldClick.listed({"kind": "post", "id": "zz"}, things), {}, "and nothing for another")


# -------------------------------------------------------------- the settings --

func test_the_settings_screen_offers_the_choice_with_its_words() -> void:
	var main := _game()
	main.open_pause()
	var menu = main.shell.open_settings()
	await TutorialKit.settle()
	if menu == null:
		await TutorialKit.leave(main)
		check(false, "the settings screen is open")
		return
	check(menu.aim_buttons.has("right") and menu.aim_buttons.has("always"), "a button for each way")
	check(menu.aim_buttons.right.button_pressed, "\"Right button aims\" is the one on")
	eq(menu.aim_buttons.right.text, "Right button aims", "its label")
	eq(menu.aim_buttons.always.text, "Always aim at the mouse", "the other's")
	check(menu.aim_note.text.to_lower().contains("right button") and menu.aim_note.text.contains("Shift"), "the line says how: %s" % menu.aim_note.text)
	menu.aim_buttons.always.pressed.emit()
	await TutorialKit.settle()
	eq(AimMode.current(), "always", "choosing it is kept at once")
	check(menu.aim_buttons.always.button_pressed and not menu.aim_buttons.right.button_pressed, "and shown")
	check(menu.aim_note.text.contains("all the time"), "the line changes: %s" % menu.aim_note.text)
	menu.aim_buttons.right.pressed.emit()
	eq(AimMode.current(), "right", "and back")
	main.shell.close_all()
	await TutorialKit.leave(main)
