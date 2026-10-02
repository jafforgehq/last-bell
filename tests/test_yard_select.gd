extends "res://tests/case.gd"
## Round 15, R15.1: a classic-RTS selection in the yard (scripts/main.gd, scripts/render/overlay_node.gd and the strip of
## scripts/ui/hud.gd). A left-drag draws a box and selects every person inside it (shift adds); a click is as it was
## (shift toggles a person in the group); the camera pans with the middle button, Alt and the left button, or W A S D (a
## left-drag no longer pans); Ctrl or Cmd and A selects everyone; Esc lets go of the group before it opens the menu; a
## right-click sends the group, spread round the click; R, P and F do the sensible thing for each of them and C, T, X, G,
## B and M the primary (the first pick); the HUD shows a strip of badges while two or more are selected; the raid gives the
## group back exactly. The raid's own box is tests/test_raid_scene.gd's (this copies its style).

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Kit := preload("res://tests/hud_kit.gd")
const RaidTests := preload("res://tests/test_raid_scene.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## Where the yard is looked at in these tests: open ground, with the camera zoomed in so nobody is out of the window.
const LOOK := Vector2(41.0, 30.0)
const ZOOM := 40.0


## The real game (the classic start: six people) in a window of this size, its own frames off (the tests drive them).
func _game(width: int = 1280, height: int = 800, crew: int = 6) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew}, width, height)
	look(main)
	return main


func look(main: Node, at: Vector2 = LOOK) -> void:
	main.cam_center = at
	main.zoom_px = ZOOM
	main._clamp_camera()
	main._apply_camera()
	main._sync_views()


func _person(main: Node, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


## `id` stands still at `at` (and the pawns are told, as a frame would).
func _stand(main: Node, id: String, at: Vector2):
	var p = _person(main, id)
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.order = null
	main._sync_views()
	return p


func _ids(list: Array) -> Array:
	var out: Array = []
	for p in list:
		out.append(String(p.id))
	return out


func _at(main: Node, tile: Vector2) -> Vector2:
	return main._tile_to_screen(tile)


## A mouse button as the viewport hands it to `_unhandled_input`.
func _button(main: Node, at: Vector2, button: MouseButton, pressed: bool = true, mods: Dictionary = {}) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.pressed = pressed
	ev.shift_pressed = bool(mods.get("shift", false))
	ev.alt_pressed = bool(mods.get("alt", false))
	ev.ctrl_pressed = bool(mods.get("ctrl", false))
	main._unhandled_input(ev)


func _motion(main: Node, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	main._unhandled_input(ev)


func _click(main: Node, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, mods: Dictionary = {}) -> void:
	_button(main, at, button, true, mods)
	_button(main, at, button, false, mods)


## A left-drag from `from` to `to` (screen points) with a stop half way, as a hand does it.
func _drag(main: Node, from: Vector2, to: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, mods: Dictionary = {}) -> void:
	_button(main, from, button, true, mods)
	_motion(main, from.lerp(to, 0.5))
	_motion(main, to)
	_button(main, to, button, false, mods)


## A box from tile `a` to tile `b`.
func _box(main: Node, a: Vector2, b: Vector2, mods: Dictionary = {}) -> void:
	_drag(main, _at(main, a), _at(main, b), MOUSE_BUTTON_LEFT, mods)


func _press(main: Node, code: Key, mods: Dictionary = {}) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = bool(mods.get("ctrl", false))
	ev.meta_pressed = bool(mods.get("meta", false))
	ev.shift_pressed = bool(mods.get("shift", false))
	main._unhandled_input(ev)


func _toast(main: Node) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


func _clear_toast(main: Node) -> void:
	main.hud.toast_panel.visible = false
	main.hud.toast_label.text = ""


## The HUD has had its first update, as main.gd's frames give it (the order buttons need to have seen the game).
func _hud_up(main: Node) -> void:
	main.hud.update_hud(main.sim, main.speed, true, 0)


## Ruth, Dez and Ana stand in a row on open ground, Marcus, Walt and Hector further off, and the camera looks at them.
func _row(main: Node) -> Array:
	var ruth = _stand(main, "ruth", Vector2(38.0, 30.0))
	var dez = _stand(main, "dez", Vector2(40.0, 30.0))
	var ana = _stand(main, "ana", Vector2(42.0, 30.0))
	_stand(main, "marcus", Vector2(46.0, 36.0))
	_stand(main, "walt", Vector2(34.0, 36.0))
	_stand(main, "hector", Vector2(41.0, 24.0))
	return [ruth, dez, ana]


func _badge(main: Node, id: String):
	for b in main.hud.group_badges:
		if String(b.p.id) == id:
			return b.node
	return null


func _badge_click(main: Node, id: String, shift: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.shift_pressed = shift
	_badge(main, id).gui_input.emit(ev)


# ----------------------------------------------------------------------- the box --

func test_a_box_selects_those_inside_it_and_not_those_outside() -> void:
	var main := _game()
	_row(main)
	_box(main, Vector2(37.0, 28.5), Vector2(41.0, 31.5))
	eq(_ids(main.selected_people), ["ruth", "dez"], "the two inside the box are selected, in the order of the crew")
	check(main.selection != null and main.selection.kind == "person" and main.selection.ref == _person(main, "ruth"), "the first of them is the primary")
	check(main.drag == null, "the drag is over")
	check(not main.menu_open, "and nothing opened")
	await TutorialKit.leave(main)


func test_a_box_can_start_on_a_person_and_goes_in_any_direction() -> void:
	var main := _game()
	var row := _row(main)
	# from the right of Ana, over her head, back to the left of Ruth: up and to the left
	_drag(main, _at(main, Vector2(43.0, 31.5)), _at(main, Vector2(37.0, 28.0)))
	eq(_ids(main.selected_people), ["ruth", "dez", "ana"], "all three: a drag that began on Ana is a box, not a click on her")
	var ruth = row[0]
	_click(main, _at(main, Vector2(ruth.x, ruth.y - 0.3)))
	eq(_ids(main.selected_people), ["ruth"], "a click on one of the group picks just them")
	await TutorialKit.leave(main)


func test_a_box_that_holds_nobody_lets_go_as_a_click_on_the_ground_does() -> void:
	var main := _game()
	_row(main)
	_box(main, Vector2(37.0, 28.5), Vector2(41.0, 31.5))
	eq(main.selected_people.size(), 2, "two are selected")
	_box(main, Vector2(30.0, 26.0), Vector2(33.0, 28.0))
	check(main.selected_people.is_empty() and main.selection == null, "an empty box lets go")
	await TutorialKit.leave(main)


func test_a_box_is_only_a_box_after_six_pixels() -> void:
	var main := _game()
	var row := _row(main)
	var ruth = row[0]
	var from := _at(main, Vector2(ruth.x, ruth.y - 0.3))
	_button(main, from, MOUSE_BUTTON_LEFT, true)
	_motion(main, from + Vector2(4.0, 0.0))
	check(main.drag != null and not main.drag.moved, "four pixels are still a click")
	_button(main, from + Vector2(4.0, 0.0), MOUSE_BUTTON_LEFT, false)
	eq(_ids(main.selected_people), ["ruth"], "so the click selected her")
	_button(main, from, MOUSE_BUTTON_LEFT, true)
	_motion(main, from + Vector2(8.0, 0.0))
	check(main.drag != null and main.drag.moved, "eight are a box")
	check(main.drag.box.size.x >= 7.9, "with a size: %s" % str(main.drag.box))
	_button(main, from + Vector2(8.0, 0.0), MOUSE_BUTTON_LEFT, false)
	await TutorialKit.leave(main)


func test_shift_adds_a_box_to_the_group_and_a_shift_click_toggles_a_person() -> void:
	var main := _game()
	var row := _row(main)
	_box(main, Vector2(37.0, 28.5), Vector2(39.0, 31.5))
	eq(_ids(main.selected_people), ["ruth"], "Ruth")
	_box(main, Vector2(41.0, 28.5), Vector2(43.0, 31.5), {"shift": true})
	eq(_ids(main.selected_people), ["ruth", "ana"], "shift adds Ana: the group is kept and the box goes after it")
	check(main.selection.ref == row[0], "the primary is still Ruth")
	var dez = row[1]
	_click(main, _at(main, Vector2(dez.x, dez.y - 0.3)), MOUSE_BUTTON_LEFT, {"shift": true})
	eq(_ids(main.selected_people), ["ruth", "ana", "dez"], "a shift-click adds Dez")
	_click(main, _at(main, Vector2(dez.x, dez.y - 0.3)), MOUSE_BUTTON_LEFT, {"shift": true})
	eq(_ids(main.selected_people), ["ruth", "ana"], "and takes her away again")
	_click(main, _at(main, Vector2(37.0, 26.0)), MOUSE_BUTTON_LEFT, {"shift": true})
	eq(_ids(main.selected_people), ["ruth", "ana"], "a shift-click on the ground keeps the group")
	_click(main, _at(main, Vector2(37.0, 26.0)))
	check(main.selected_people.is_empty() and main.selection == null, "a plain click on the ground lets go of it")
	await TutorialKit.leave(main)


func test_taking_the_primary_out_with_shift_gives_the_next_the_panel() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1], row[2]])
	_click(main, _at(main, Vector2(row[0].x, row[0].y - 0.3)), MOUSE_BUTTON_LEFT, {"shift": true})
	eq(_ids(main.selected_people), ["dez", "ana"], "Ruth is out")
	check(main.selection.ref == row[1], "and Dez, the next, is the primary")
	check(main.hud.selection == main.selection, "the panel follows")
	await TutorialKit.leave(main)


func test_a_dead_or_away_person_is_never_boxed_or_toggled_in() -> void:
	var main := _game()
	var row := _row(main)
	row[1].dead = true
	row[2].away = {"kind": "party"}
	_box(main, Vector2(36.0, 28.0), Vector2(44.0, 32.0))
	eq(_ids(main.selected_people), ["ruth"], "only the one who is here and alive")
	_click(main, _at(main, Vector2(row[1].x, row[1].y - 0.3)), MOUSE_BUTTON_LEFT, {"shift": true})
	eq(_ids(main.selected_people), ["ruth"], "a shift-click on a dead one does not add them")
	row[1].dead = false
	row[1].turned = true
	_box(main, Vector2(36.0, 28.0), Vector2(44.0, 32.0))
	eq(_ids(main.selected_people), ["ruth"], "nor one who turned")
	await TutorialKit.leave(main)


func test_a_downed_person_is_still_a_person_in_the_box() -> void:
	var main := _game()
	var row := _row(main)
	row[1].downed = true
	_box(main, Vector2(36.0, 28.0), Vector2(44.0, 32.0))
	eq(_ids(main.selected_people), ["ruth", "dez", "ana"], "the downed are alive: they are in it")
	await TutorialKit.leave(main)


func test_esc_in_the_middle_of_a_box_cancels_it() -> void:
	var main := _game()
	_row(main)
	var from := _at(main, Vector2(37.0, 28.5))
	_button(main, from, MOUSE_BUTTON_LEFT, true)
	_motion(main, _at(main, Vector2(41.0, 31.5)))
	check(main.drag != null and main.drag.moved, "a box is being drawn")
	_press(main, KEY_ESCAPE)
	check(main.drag == null, "Esc ended it")
	check(not main.shell.is_open(), "and did not open the menu")
	_button(main, _at(main, Vector2(41.0, 31.5)), MOUSE_BUTTON_LEFT, false)
	check(main.selected_people.is_empty(), "the release selected nobody")
	await TutorialKit.leave(main)


# ---------------------------------------------------------------------- the camera --

func test_the_middle_button_drags_the_camera() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1]])
	var c0: Vector2 = main.cam_center
	_drag(main, Vector2(600.0, 400.0), Vector2(500.0, 350.0), MOUSE_BUTTON_MIDDLE)
	var moved: Vector2 = main.cam_center - c0
	near(moved.x, 100.0 / main.zoom_px, 0.05, "the ground follows the hand in x")
	near(moved.y, 50.0 / main.zoom_px, 0.05, "and in y")
	eq(_ids(main.selected_people), ["ruth", "dez"], "and the selection is left alone")
	check(main.drag == null, "the drag is over")
	await TutorialKit.leave(main)


func test_a_middle_click_without_moving_does_nothing() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1]])
	_click(main, _at(main, Vector2(37.0, 26.0)), MOUSE_BUTTON_MIDDLE)
	eq(_ids(main.selected_people), ["ruth", "dez"], "it does not let go as a left click would")
	await TutorialKit.leave(main)


func test_alt_and_the_left_button_drag_the_camera() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1]])
	var c0: Vector2 = main.cam_center
	_drag(main, Vector2(600.0, 400.0), Vector2(500.0, 350.0), MOUSE_BUTTON_LEFT, {"alt": true})
	var moved: Vector2 = main.cam_center - c0
	near(moved.x, 100.0 / main.zoom_px, 0.05, "Option and the left button pan in x")
	near(moved.y, 50.0 / main.zoom_px, 0.05, "and in y")
	eq(_ids(main.selected_people), ["ruth", "dez"], "with no box: the selection is as it was")
	check(main.drag == null, "the drag is over")
	await TutorialKit.leave(main)


func test_a_plain_left_drag_no_longer_pans() -> void:
	var main := _game()
	_row(main)
	var c0: Vector2 = main.cam_center
	_drag(main, Vector2(600.0, 400.0), Vector2(500.0, 350.0))
	eq(main.cam_center, c0, "the camera stays where it is")
	await TutorialKit.leave(main)


func test_the_pans_are_told_to_the_coach() -> void:
	var main := TutorialKit.game(0)
	await TutorialKit.frames(main, 4)
	var seen: float = float(main.coach.state.get("pan", 0.0))
	_drag(main, Vector2(600.0, 400.0), Vector2(300.0, 300.0), MOUSE_BUTTON_MIDDLE)
	check(float(main.coach.state.get("pan", 0.0)) > seen + 2.0, "a middle drag counts as a pan for the lesson: %s" % str(main.coach.state.get("pan")))
	await TutorialKit.leave(main)


## Keys held down, as the engine's input state has them (the camera reads them each frame).
func _hold(codes: Array, down: bool, mods: Dictionary = {}) -> void:
	for code in codes:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		ev.ctrl_pressed = bool(mods.get("ctrl", false))
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func test_the_keys_w_a_s_d_and_the_arrows_still_pan() -> void:
	var main := _game()
	var c0: Vector2 = main.cam_center
	_hold([KEY_D, KEY_S], true)
	main._process(0.1)
	_hold([KEY_D, KEY_S], false)
	var moved: Vector2 = main.cam_center - c0
	check(moved.x > 0.5 and moved.y > 0.5, "D and S pan right and down: %s" % str(moved))
	var c1: Vector2 = main.cam_center
	_hold([KEY_LEFT], true)
	main._process(0.1)
	_hold([KEY_LEFT], false)
	check(main.cam_center.x < c1.x - 0.5, "and the left arrow pans left")
	await TutorialKit.leave(main)


func test_ctrl_a_does_not_pan_as_a_held_a_would() -> void:
	var main := _game()
	var c0: Vector2 = main.cam_center
	_hold([KEY_CTRL, KEY_A], true, {"ctrl": true})
	main._process(0.1)
	_hold([KEY_CTRL, KEY_A], false)
	eq(main.cam_center, c0, "the camera did not move")
	_hold([KEY_A], true)
	main._process(0.1)
	_hold([KEY_A], false)
	check(main.cam_center.x < c0.x - 0.5, "(and A alone does pan left)")
	await TutorialKit.leave(main)


func test_the_wheel_and_the_trackpad_still_zoom() -> void:
	var main := _game()
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


# ------------------------------------------------------------------- the keys --

func test_ctrl_a_and_cmd_a_select_everyone_who_is_here() -> void:
	var main := _game()
	_row(main)
	_press(main, KEY_A)
	check(main.selected_people.is_empty(), "A alone selects nobody (it pans)")
	_person(main, "walt").away = {"kind": "party"}
	_person(main, "hector").dead = true
	_press(main, KEY_A, {"ctrl": true})
	eq(_ids(main.selected_people), ["ruth", "dez", "ana", "marcus"], "Ctrl and A: everyone in the yard, alive: not the away or the dead")
	eq(main.selection.ref, _person(main, "ruth"), "Ruth is the primary")
	main._select(null)
	_press(main, KEY_A, {"meta": true})
	eq(main.selected_people.size(), 4, "Cmd and A the same")
	await TutorialKit.leave(main)


func test_esc_lets_go_of_the_group_first_then_opens_the_menu() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1], row[2]])
	_press(main, KEY_ESCAPE)
	check(main.selected_people.is_empty() and main.selection == null, "the first Esc clears the group")
	check(not main.shell.is_open(), "and the menu is not open")
	_press(main, KEY_ESCAPE)
	check(main.shell.is_open(), "the second opens it")
	await TutorialKit.leave(main)


func test_tab_still_goes_round_one_person_at_a_time() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[1], row[2]])
	_press(main, KEY_TAB)
	eq(main.selected_people.size(), 1, "Tab picks one person")
	check(main.selection.ref != row[1], "the next one after the primary")
	await TutorialKit.leave(main)


func test_a_click_on_a_wall_section_or_a_walker_takes_the_group_away() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1]])
	var seg = main.sim.segments[3]
	main._try_select({"kind": "segment", "ref": seg})
	check(main.selected_people.is_empty() and main.selection.kind == "segment", "a wall piece is the selection, and there is no group")
	await TutorialKit.leave(main)


func test_the_selection_and_the_group_keep_in_step() -> void:
	var main := _game()
	var row := _row(main)
	main._select({"kind": "person", "ref": row[0]})
	eq(_ids(main.selected_people), ["ruth"], "selecting one person is a group of one")
	main._select(null)
	check(main.selected_people.is_empty(), "no selection, no group")
	main.select_people([row[1], row[2]])
	main.selection = null
	main._prune_selection()
	check(main.selected_people.is_empty(), "a selection set to nothing by hand is noticed")
	main.selection = {"kind": "person", "ref": row[0]}
	main._prune_selection()
	eq(_ids(main.selected_people), ["ruth"], "and a person put in by hand too")
	await TutorialKit.leave(main)


func test_whoever_goes_away_or_dies_drops_out_of_the_group() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1], row[2]])
	row[2].away = {"kind": "party"}
	main._process(1.0 / 30.0)
	eq(_ids(main.selected_people), ["ruth", "dez"], "Ana left on a trip: out of the group")
	row[0].dead = true
	main._process(1.0 / 30.0)
	eq(_ids(main.selected_people), ["dez"], "Ruth died: out of it")
	check(main.selection.ref == row[1], "and Dez is the primary now")
	check(main.hud.selection == main.selection, "the panel shows Dez")
	row[1].dead = true
	main._process(1.0 / 30.0)
	check(main.selection != null and main.selection.ref == row[1], "the last one stays as a single selection, as it always did (their panel says what became of them)")
	await TutorialKit.leave(main)


# ------------------------------------------------------------------- the orders --

func test_a_right_click_sends_the_group_spread_round_the_click() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1], row[2]])
	var goal := Vector2(41.5, 33.5)
	_click(main, _at(main, goal), MOUSE_BUTTON_RIGHT)
	var spots: Array = []
	for p in row:
		check(p.order != null and p.drafted, "%s has an order and is drafted" % p.first)
		var at := Vector2(p.order.x, p.order.y)
		check(at.distance_to(goal) <= main.GROUP_SPREAD * 2.0, "within the spread of the click: %s" % str(at))
		spots.append(at)
	check(spots[0].distance_to(spots[1]) > 0.3 and spots[1].distance_to(spots[2]) > 0.3 and spots[0].distance_to(spots[2]) > 0.3, "and not on top of each other")
	check(main.order_mark != null and Vector2(main.order_mark.x, main.order_mark.y).distance_to(goal) < 0.01, "one mark at the click")
	var others := [_person(main, "marcus"), _person(main, "walt"), _person(main, "hector")]
	for q in others:
		check(q.order == null, "%s was not selected and has no order" % q.first)
	await TutorialKit.leave(main)


func test_a_single_person_is_sent_to_the_click_itself_as_before() -> void:
	var main := _game()
	var row := _row(main)
	main._select({"kind": "person", "ref": row[0]})
	var goal := Vector2(41.5, 33.5)
	_click(main, _at(main, goal), MOUSE_BUTTON_RIGHT)
	check(row[0].order != null and Vector2(row[0].order.x, row[0].order.y).distance_to(goal) < 0.001, "no spread for one")
	await TutorialKit.leave(main)


func test_a_group_order_that_is_refused_for_some_says_so_once_and_the_rest_go() -> void:
	var main := _game()
	var row := _row(main)
	row[1].downed = true
	main.select_people([row[0], row[1], row[2]])
	_click(main, _at(main, Vector2(41.5, 33.5)), MOUSE_BUTTON_RIGHT)
	check(row[0].order != null and row[2].order != null, "the two who can go, go")
	check(row[1].order == null, "Dez is down and stays")
	eq(_toast(main), "Dez is down", "and one toast says why")
	_clear_toast(main)
	row[2].downed = true
	row[0].order = null
	row[2].order = null
	_click(main, _at(main, Vector2(41.5, 33.5)), MOUSE_BUTTON_RIGHT)
	check(_toast(main).begins_with("Dez is down"), "two refused: the first reason: '%s'" % _toast(main))
	check(_toast(main).contains("1 more"), "and the count of the others: '%s'" % _toast(main))
	await TutorialKit.leave(main)


func test_a_group_sent_where_nobody_can_stand_says_so() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1]])
	var bus = main.sim.segments[3]
	var wall := Vector2(bus.obj.cx, bus.obj.cy)
	check(main.world.is_solid(main.world.solid_p, wall.x, wall.y), "(the middle of the bus is solid)")
	look(main, Vector2(41.0, 22.0))
	_click(main, _at(main, wall), MOUSE_BUTTON_RIGHT)
	check(row[0].order == null and row[1].order == null, "nobody went")
	check(_toast(main) != "", "and a toast says why: '%s'" % _toast(main))
	await TutorialKit.leave(main)


func test_a_right_click_with_nobody_selected_still_says_who_to_click_first() -> void:
	var main := _game()
	_click(main, _at(main, Vector2(41.5, 33.5)), MOUSE_BUTTON_RIGHT)
	eq(_toast(main), "Click someone first, then right-click where they should go", "as it always did")
	await TutorialKit.leave(main)


func test_r_drafts_everyone_if_anyone_is_not_and_releases_everyone_when_all_are() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	row[0].drafted = true
	row[0].order = Vector3(row[0].x, row[0].y, 0)
	main.select_people([row[0], row[1], row[2]])
	_press(main, KEY_R)
	for p in row:
		check(p.drafted, "%s is drafted: one was not, so all are" % p.first)
	_press(main, KEY_R)
	for p in row:
		check(not p.drafted, "%s is released: all were drafted, so all are let go" % p.first)
	check(not _person(main, "marcus").drafted, "Marcus was not touched")
	await TutorialKit.leave(main)


func test_p_sends_each_to_their_own_night_post() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	main.select_people([row[0], row[1], row[2]])
	_press(main, KEY_P)
	for p in row:
		var post: Vector2 = main.sim.jobs.post_pos(p)
		check(p.drafted and p.order != null and is_equal_approx(p.order.z, 1.0), "%s is ordered to a post" % p.first)
		check(Vector2(p.order.x, p.order.y).distance_to(post) < 0.01, "and to their own: %s" % str(post))
	await TutorialKit.leave(main)


func test_f_sends_the_group_to_mend_the_worn_walls_worst_first() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	var worst = main.sim.segments[3]
	var worse = main.sim.segments[4]
	worst.hp = worst.max_hp * 0.2
	worse.hp = worse.max_hp * 0.6
	main.sim.stock.scrap = 50.0
	main.select_people([row[0], row[1], row[2]])
	_press(main, KEY_F)
	check(row[0].repair == worst, "the first goes to the worst piece")
	check(row[1].repair == worse, "the next to the next worst")
	check(row[2].repair == worst, "and round again")
	await TutorialKit.leave(main)


func test_f_for_a_group_says_why_when_nothing_is_damaged() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	for s in main.sim.segments:
		s.hp = s.max_hp
	main.select_people([row[0], row[1]])
	_press(main, KEY_F)
	check(row[0].repair == null and row[1].repair == null, "nobody was sent")
	eq(_toast(main), "Not now: nothing is damaged", "the same words as for one person")
	await TutorialKit.leave(main)


func test_c_follows_the_primary_only() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	main.select_people([row[1], row[0], row[2]])
	_press(main, KEY_C)
	check(main.follow == row[1], "the view follows the primary")
	await TutorialKit.leave(main)


func test_b_and_m_act_on_the_primary_only() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	var jobs = main.sim.jobs
	var before_dez: String = jobs.job_of(row[1])
	var before_ruth: String = jobs.job_of(row[0])
	main.select_people([row[2], row[1], row[0]])
	_press(main, KEY_B)
	eq(jobs.job_of(row[2]), "builders", "Ana, the primary, took the Builders job")
	eq(jobs.job_of(row[1]), before_dez, "Dez was not touched")
	eq(jobs.job_of(row[0]), before_ruth, "nor Ruth")
	await TutorialKit.leave(main)


func test_the_buttons_say_who_they_are_for_when_there_is_a_group() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	main.select_people([row[0], row[1], row[2]])
	_hud_up(main)
	var draft: Button = null
	var follow: Button = null
	var post: Button = null
	for b in main.hud.gizmos.get_children():
		if b is Button and b.has_meta("id"):
			match String(b.get_meta("id")):
				"draft":
					draft = b
				"focus":
					follow = b
				"post":
					post = b
	check(draft != null and draft.tooltip_text.contains("all 3"), "Draft names the three: '%s'" % (draft.tooltip_text if draft != null else ""))
	check(post != null and post.tooltip_text.contains("their own"), "To post says each has their own: '%s'" % (post.tooltip_text if post != null else ""))
	check(follow != null and follow.tooltip_text.contains("Ruth"), "Follow names the primary: '%s'" % (follow.tooltip_text if follow != null else ""))
	main.sim.toggle_draft(row[0])
	main.sim.toggle_draft(row[1])
	main.sim.toggle_draft(row[2])
	_hud_up(main)
	for b in main.hud.gizmos.get_children():
		if b is Button and b.has_meta("id") and String(b.get_meta("id")) == "draft":
			check(b.get_meta("on") == true and String(b.get_meta("label")) == "Release", "once all are drafted the button reads Release and is lit")
	await TutorialKit.leave(main)


func test_a_button_that_would_do_nothing_for_the_whole_group_is_ghosted_with_the_reason() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	for s in main.sim.segments:
		s.hp = s.max_hp
	main.select_people([row[0], row[1]])
	_hud_up(main)
	var repair: Button = null
	for b in main.hud.gizmos.get_children():
		if b is Button and b.has_meta("id") and String(b.get_meta("id")) == "repair":
			repair = b
	check(repair != null and repair.modulate.a < 0.9, "Repair is a ghost")
	check(repair.tooltip_text.contains("Not now: nothing is damaged"), "with the reason: '%s'" % repair.tooltip_text)
	await TutorialKit.leave(main)


# ---------------------------------------------------------------------- the tutorial --

func test_in_the_tutorial_a_box_takes_only_who_the_step_allows() -> void:
	var main := TutorialKit.game(1)
	await TutorialKit.frames(main, 30)
	var ruth = Bot.person(main, "ruth")
	var hector = Bot.person(main, "hector")
	ruth.x = 38.0
	ruth.y = 30.0
	hector.x = 40.0
	hector.y = 30.0
	look(main)
	_box(main, Vector2(37.0, 28.5), Vector2(41.0, 31.5))
	eq(_ids(main.selected_people), ["ruth"], "Hector's card is refused in this lesson and so is a box that holds him: only Ruth")
	await TutorialKit.leave(main)


# --------------------------------------------------------------------- the view --

func test_the_strip_shows_with_two_or_more_people_and_not_with_one() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	main._select({"kind": "person", "ref": row[0]})
	check(main.hud.group_strip == null or not main.hud.group_strip.visible, "one person: no strip")
	main.select_people([row[0], row[1], row[2]])
	await TutorialKit.settle()
	check(main.hud.group_strip != null and main.hud.group_strip.visible, "three: the strip is there")
	eq(main.hud.group_badges.size(), 3, "a badge for each")
	check(Kit.texts(main.hud.group_strip).has("3 selected"), "and the words '3 selected': %s" % str(Kit.texts(main.hud.group_strip)))
	main.select_people([row[0], row[1]])
	await TutorialKit.settle()
	check(Kit.texts(main.hud.group_strip).has("2 selected"), "two")
	main._select(null)
	await TutorialKit.settle()
	check(main.hud.group_strip == null or not main.hud.group_strip.visible, "nobody: no strip")
	main._select({"kind": "segment", "ref": main.sim.segments[3]})
	check(main.hud.group_strip == null or not main.hud.group_strip.visible, "a wall piece: no strip")
	await TutorialKit.leave(main)


func test_a_badge_click_makes_that_person_the_primary_and_shift_removes_them() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	main.select_people([row[0], row[1], row[2]])
	await TutorialKit.settle()
	_badge_click(main, "dez")
	eq(_ids(main.selected_people), ["ruth", "dez", "ana"], "the group is as it was")
	check(main.selection.ref == row[1], "Dez is the primary")
	check(main.hud.selection.ref == row[1], "and the panel is Dez's")
	await TutorialKit.settle()
	_badge_click(main, "ana", true)
	eq(_ids(main.selected_people), ["ruth", "dez"], "a shift-click takes Ana out")
	check(main.selection.ref == row[1], "the primary is as it was")
	await TutorialKit.settle()
	_badge_click(main, "ruth", true)
	eq(_ids(main.selected_people), ["dez"], "down to one")
	check(main.hud.group_strip == null or not main.hud.group_strip.visible, "and the strip is gone")
	await TutorialKit.leave(main)


func test_a_shift_click_on_a_crew_card_toggles_that_person_in_the_group() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	main._select({"kind": "person", "ref": row[0]})
	for c in main.hud.cards:
		if c.p == row[1]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.shift_pressed = true
			c.card.gui_input.emit(ev)
	eq(_ids(main.selected_people), ["ruth", "dez"], "shift and the card of Dez adds him")
	Bot.card_click(main, "dez")
	eq(_ids(main.selected_people), ["dez"], "a plain click on a card picks that one person")
	await TutorialKit.leave(main)


func test_the_cards_of_the_group_are_lit() -> void:
	var main := _game()
	var row := _row(main)
	_hud_up(main)
	main.select_people([row[0], row[2]])
	_hud_up(main)
	var lit: Array = []
	for c in main.hud.cards:
		if c.sel:
			lit.append(String(c.p.id))
	eq(lit, ["ruth", "ana"], "the cards of the people selected are lit")
	await TutorialKit.leave(main)


func test_the_overlay_marks_everyone_selected_and_draws_the_box() -> void:
	var main := _game()
	var row := _row(main)
	main.select_people([row[0], row[1], row[2]])
	await TutorialKit.frames(main, 2)
	main.overlay.queue_redraw()
	await Kit.settle()
	eq(main.overlay.drawn_selected, 3, "a ring and brackets for each of the three")
	eq(main.overlay.drawn_reach, 0, "and no reach circle: it is for one person")
	check(not main.overlay.drew_box, "no box while nobody drags")
	main._select({"kind": "person", "ref": row[0]})
	main.overlay.queue_redraw()
	await Kit.settle()
	eq(main.overlay.drawn_selected, 1, "one person: one mark")
	_button(main, _at(main, Vector2(36.0, 27.0)), MOUSE_BUTTON_LEFT, true)
	_motion(main, _at(main, Vector2(41.0, 31.5)))
	main.overlay.queue_redraw()
	await Kit.settle()
	check(main.overlay.drew_box, "the box is drawn while it is dragged")
	eq(main.overlay.drawn_box_hits, 2, "with a mark on those it holds now (Ruth and Dez)")
	_button(main, _at(main, Vector2(41.0, 31.5)), MOUSE_BUTTON_LEFT, false)
	await TutorialKit.leave(main)


func test_the_strip_fits_every_window_beside_everything_else() -> void:
	for size in [[1280, 800], [980, 700], [700, 560]]:
		var ctx := Kit.build(size[0], size[1], 1, true, 6)
		var people: Array = ctx.sim.people
		ctx.sim.medical.treat["ana"] = true
		ctx.sim.medical.sendout["ana"] = true
		ctx.sim.scavenge.can = true
		ctx.hud.select({"kind": "person", "ref": people[2]}, people.duplicate())
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var h = ctx.hud
		check(h.group_strip != null and h.group_strip.visible, "%d x %d: the strip is there" % [size[0], size[1]])
		eq(h.group_badges.size(), 6, "a badge for each of six")
		var rects := {
			"stores": Kit.rect(h.res_panel), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock), "alerts": Kit.rect(h.alerts_box),
			"selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos), "speed": Kit.rect(h.speed_panel),
		}
		eq(Kit.overlaps(rects), [], "%d x %d with a group selected" % [size[0], size[1]])
		var win := Rect2(0, 0, size[0], size[1])
		for name in rects:
			var r: Rect2 = rects[name]
			if r.size.x > 1.0 and r.size.y > 1.0:
				check(win.encloses(r.grow(-0.5)), "%s is inside the %d x %d window: %s" % [name, size[0], size[1], str(r)])
		var strip := Kit.rect(h.group_strip)
		check(Kit.rect(h.inspect).encloses(strip.grow(-0.5)), "the strip is inside the panel at %d: %s in %s" % [size[0], str(strip), str(Kit.rect(h.inspect))])
		for b in h.group_badges:
			var br := Kit.rect(b.node)
			check(br.size.x >= 24.0 and br.size.y >= 24.0, "a badge is big enough to hit: %s" % str(br.size))
			check(strip.encloses(br.grow(-0.5)), "and inside the strip: %s in %s" % [str(br), str(strip)])
		for l in h.group_strip.find_children("*", "Label", true, false):
			check(l.get_theme_font_size("font_size") >= Fonts.MIN_PX, "'%s' is 12 px or more" % l.text)
		Kit.free_all(ctx)


func test_the_strip_wraps_for_a_crowd_and_still_fits() -> void:
	var ctx := Kit.build(1280, 800, 1, true, 6)
	var people: Array = ctx.sim.people
	ctx.hud.select({"kind": "person", "ref": people[0]}, people.duplicate())
	Kit.update(ctx)
	await Kit.settle()
	var narrow := Kit.rect(ctx.hud.inspect).size.x
	ctx.hud.select({"kind": "person", "ref": people[0]}, people.duplicate())
	await Kit.settle()
	eq(Kit.rect(ctx.hud.inspect).size.x, narrow, "the panel is as wide each time")
	check(narrow <= 340.0, "and not wider than a panel with a long name: %s" % str(narrow))
	Kit.free_all(ctx)


# ------------------------------------------------------------------------ the raid --

func test_the_raid_gives_the_group_back_exactly() -> void:
	var main := _game(1280, 800, 3)
	var crew: Array = main.sim.people
	main.select_people([crew[2], crew[0], crew[1]])
	var group: Array = main.selected_people.duplicate()
	var chosen = main.selection
	var scene := RaidScene.new()
	main.add_child(scene)
	scene.set_process(false)
	var tests := RaidTests.new()
	scene.setup(main, main.hud, main.data, tests._site([]), [crew[0], crew[1], crew[2]], 300.0, "", 1.0, false)
	# while the raid is up the colony's frames still run: somebody leaves the group's world, and the group is held all the same
	crew[1].away = {"kind": "party"}
	for i in 5:
		main._process(1.0 / 30.0)
	eq(_ids(main.selected_people), _ids(group), "the group is held while the raid is up")
	main.drag = null
	scene.select_all()
	scene.retreat()
	for i in 900:
		scene.tick(1.0 / 30.0)
	scene.go_home()
	crew[1].away = null
	eq(_ids(main.selected_people), _ids(group), "the group is back, the same people in the same order")
	check(main.selection == chosen, "and the primary is the same")
	check(main.selected_people is Array and main.selected_people.size() == 3, "an array of three")
	await TutorialKit.leave(main)


func test_the_raid_keeps_a_box_that_was_being_drawn() -> void:
	var main := _game(1280, 800, 3)
	var crew: Array = main.sim.people
	main.select_people([crew[0], crew[1]])
	main.drag = {"pos": Vector2(10.0, 10.0), "center": main.cam_center, "moved": true, "button": MOUSE_BUTTON_LEFT, "box": Rect2(10.0, 10.0, 40.0, 30.0), "shift": false, "pan": false}
	var drag_was = main.drag
	var scene := RaidScene.new()
	main.add_child(scene)
	scene.set_process(false)
	var tests := RaidTests.new()
	scene.setup(main, main.hud, main.data, tests._site([]), [crew[0], crew[1], crew[2]], 300.0, "", 1.0, false)
	check(main.drag == null, "the raid ends the drag while it is up")
	scene.select_all()
	scene.retreat()
	for i in 900:
		scene.tick(1.0 / 30.0)
	scene.go_home()
	check(main.drag == drag_was, "and gives it back as it was")
	await TutorialKit.leave(main)
