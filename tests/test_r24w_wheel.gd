extends "res://tests/case.gd"
## Round 24, WHEEL: the command wheel (scripts/ui/command_wheel.gd the ring, scripts/ui/wheel_ctl.gd what the keys and the mouse do to it): hold C or the
## middle button and a ring of the radio's six verbs opens at the pointer; release over a slice and the person it is for is asked through the dock's own
## path. The person is the one picked, else the one under the pointer, else the nearest within six tiles; Shift is the second ring (everyone within eight
## tiles, one request each, one line of answers); 1 to 5 pick the crew by card order; Z asks the last order again; a person who carries an order wears a
## glyph pill over their head (scripts/render/stance_marks.gd). Here the yard (scripts/main.gd) and one place (scripts/raid/raid_scene.gd).

const GD := preload("res://scripts/game_data.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")
const WheelCtl := preload("res://scripts/ui/wheel_ctl.gd")
const CommandWheel := preload("res://scripts/ui/command_wheel.gd")
const StanceMarks := preload("res://scripts/render/stance_marks.gd")

const DT := 1.0 / 30.0
const SPOT := Vector2(41.5, 30.5)
const ZOOM := 40.0
const ARENA := Rect2i(34, 26, 20, 12)
const FAR := Vector2(41.5, 52.5)


# ----------------------------------------------------------------- helpers --

## The real game (a classic start, six people) with Ruth in the middle of a clear arena, "Right button aims", everyone else far away (each test brings
## the ones it needs near).
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
	for q in WheelCtl.crew_of(sim.people):
		_stand(main, q, FAR)
	main._sync_views()
	for i in 4:
		main._process(DT)    # (the HUD sees the game: its dock has a radio to ask)
	for q in WheelCtl.crew_of(sim.people):
		_stand(main, q, FAR)
	return main


func _crew(main: Node) -> Array:
	return WheelCtl.crew_of(main.sim.people)


func _stand(main: Node, p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.goal_key = ""
	p.order = null
	p.stance = ""
	main._sync_views()


func _at(main: Node, tile: Vector2) -> Vector2:
	return main._tile_to_screen(tile)


func _key(main: Node, code: Key, pressed: bool = true, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	ev.shift_pressed = shift
	main._input(ev)
	if pressed:
		main._unhandled_input(ev)


func _button(main: Node, at: Vector2, button: MouseButton, pressed: bool = true) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.pressed = pressed
	main._input(ev)
	if pressed and button != MOUSE_BUTTON_MIDDLE:
		main._unhandled_input(ev)    # (the middle button does nothing in the world: the wheel takes it, or it is nobody's)


func _motion(main: Node, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	main._input(ev)
	main._unhandled_input(ev)


func _toast(main: Node) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


## The pointer over the middle of slice `i` of the wheel that is up.
func _on_slice(main: Node, i: int) -> void:
	var w = main.hud.wheel
	_motion(main, w.centre + CommandWheel.slice_mid(i))


func _verb_index(verb: String) -> int:
	return WheelCtl.TIPS.keys().find(verb)


func near_v(a: Vector2, b: Vector2, msg: String) -> void:
	if a.distance_to(b) > 0.01:
		failures.append("%s: expected %s, got %s" % [msg, str(b), str(a)])


# ------------------------------------------------------------------- opening --

func test_c_and_the_middle_button_open_the_wheel_a_tap_keeps_it_up_and_esc_or_the_centre_cancel() -> void:
	var main := _game()
	var dez = _crew(main)[0]
	_stand(main, dez, SPOT + Vector2(2.0, 0.0))
	var ctl = main.wheel_ctl
	var wheel = main.hud.wheel
	check(not wheel.visible and not ctl.is_open(), "the wheel is shut at first (and draws nothing)")
	main.mouse_screen = _at(main, SPOT + Vector2(3.0, 2.0))
	_key(main, KEY_C)
	check(ctl.is_open() and wheel.visible and wheel.active, "C opens it")
	eq(wheel.slices.size(), 6, "six slices")
	var names: Array = []
	for s in wheel.slices:
		names.append(String(s.name))
	eq(names, ["Come with me", "Hold here", "Cover me", "Search that", "Go back", "To the walls"], "the radio's verbs, in its order")
	eq(wheel.title, "Dez", "the person is named at its centre")
	near_v(wheel.origin, main.mouse_screen, "it opened at the pointer")
	# the hands are let go while it is up: no aim, no fire; the game is not paused
	main.aim_held = true
	main.firing = true
	main._process(DT)
	check(not main.aiming() and not main.firing and not main.aim_held, "the avatar does not aim or fire while the wheel is up")
	check(not main.aim_shown(), "no crosshair")
	check(main.speed > 0, "and the game is not paused")
	# a tap (let go at once, the pointer on no slice) leaves it up for a click
	ctl._open_ms = Time.get_ticks_msec()
	_key(main, KEY_C, false)
	check(ctl.is_open() and wheel.latched, "a tap of the key leaves the wheel up")
	_key(main, KEY_ESCAPE)
	check(not ctl.is_open() and not wheel.visible, "Esc shuts it")
	eq(main.sim.radio.pending.size(), 0, "and nobody was asked")
	# the middle button (on the bare world), held and let go in the middle after a while: nothing is asked
	_button(main, _at(main, SPOT + Vector2(0.0, 3.0)), MOUSE_BUTTON_MIDDLE, true)
	check(ctl.is_open(), "the middle button opens it too")
	ctl._open_ms -= 600
	_button(main, _at(main, SPOT + Vector2(0.0, 3.0)), MOUSE_BUTTON_MIDDLE, false)
	check(not ctl.is_open(), "let go in the middle after more than a tap, it is cancelled")
	eq(main.sim.radio.pending.size(), 0, "nobody was asked")
	# nobody near: it does not open, and says why
	_stand(main, dez, FAR)
	main.hud.toast_panel.visible = false
	_key(main, KEY_C)
	check(not ctl.is_open(), "with nobody picked, pointed at or within six tiles it does not open")
	check(_toast(main).begins_with("Nobody is near"), "and says so: %s" % _toast(main))
	_key(main, KEY_C, false)
	await TutorialKit.leave(main)


func test_the_wheel_acts_on_the_person_picked_then_the_one_pointed_at_then_the_nearest_within_six_tiles() -> void:
	var main := _game()
	var crew := _crew(main)
	var a = crew[0]
	var b = crew[1]
	var c = crew[2]
	_stand(main, a, SPOT + Vector2(2.0, 0.0))    # nearest
	_stand(main, b, SPOT + Vector2(-4.0, 1.0))
	_stand(main, c, SPOT + Vector2(0.0, 5.5))
	var ctl = main.wheel_ctl
	# nobody picked, the pointer on the ground: the nearest
	main._select(null)
	main.mouse_screen = _at(main, SPOT + Vector2(0.0, -3.0))
	_key(main, KEY_C)
	check(ctl.target() == a, "the nearest within six tiles: %s" % a.first)
	eq(main.hud.wheel.title, String(a.first), "named at the centre")
	ctl.cancel()
	# the pointer on someone: them
	main.mouse_screen = _at(main, Vector2(b.x, b.y - 0.3))
	_key(main, KEY_C)
	check(ctl.target() == b, "the person under the pointer: %s" % b.first)
	ctl.cancel()
	# someone picked: them, wherever they are
	main._try_select({"kind": "person", "ref": c})
	_stand(main, c, SPOT + Vector2(-7.0, 0.0))
	_key(main, KEY_C)
	check(ctl.target() == c, "the person picked, even beyond six tiles: %s" % c.first)
	ctl.cancel()
	await TutorialKit.leave(main)


# ---------------------------------------------------------------------- asking --

func test_a_slice_asks_through_the_dock_a_refusal_is_greyed_with_its_reason_and_a_soft_one_is_marked_insist() -> void:
	var main := _game()
	var crew := _crew(main)
	var dez = crew[0]
	var ana = crew[1]
	_stand(main, dez, SPOT + Vector2(2.0, 0.0))
	_stand(main, ana, SPOT + Vector2(-2.5, 0.0))
	var radio = main.sim.radio
	var ctl = main.wheel_ctl
	# Dez picked; the wheel opened over a spot of the ground; Hold here lit and let go
	main._try_select({"kind": "person", "ref": dez})
	var spot_screen := _at(main, Vector2(46.7, 33.2))
	main.mouse_screen = spot_screen
	_key(main, KEY_C)
	check(not bool(main.hud.wheel.slices[_verb_index("hold")].soft) and bool(main.hud.wheel.slices[_verb_index("hold")].enabled), "Hold here is open to Dez")
	_on_slice(main, _verb_index("hold"))
	eq(main.hud.wheel.hover, _verb_index("hold"), "the slice under the pointer is lit")
	main.hud.toast_panel.visible = false
	_key(main, KEY_C, false)
	check(not ctl.is_open(), "let go over a slice, the wheel is shut")
	eq(radio.pending.size(), 1, "one request waits on the radio")
	eq(String(radio.pending[0].verb), "hold", "Hold here")
	near_v(Vector2(radio.pending[0].at), Vector2(46.5, 33.5), "at the tile the wheel was opened on, not where the pointer went")
	var last: Dictionary = main.hud.radio_verbs.last
	check(bool(last.ok) and String(last.verb) == "hold" and String(last.who) == String(dez.id), "the dock has Dez's answer")
	check(main.hud.radio_verbs.reply.text.begins_with("%s: " % dez.first), "in its reply line: %s" % main.hud.radio_verbs.reply.text)
	check(_toast(main).begins_with("%s: " % dez.first), "and in a toast: %s" % _toast(main))
	check(main.order_flag != null and main.order_flag.kind == "hold" and main.order_flag.x == 46.5, "a flag is put on the tile")
	# Dez is down: every slice is greyed with the radio's own reason; a release over one asks nobody and says why
	dez.downed = true
	radio.pending.clear()
	main.mouse_screen = _at(main, SPOT + Vector2(0.0, -3.0))
	_key(main, KEY_C)
	var why := String(radio.willingness(dez, "come").why)
	check(why != "", "(the radio has a reason: %s)" % why)
	for s in main.hud.wheel.slices:
		check(not bool(s.enabled) and String(s.tip) == why, "%s is greyed with the reason (%s)" % [s.verb, s.tip])
	_on_slice(main, _verb_index("come"))
	main.hud.toast_panel.visible = false
	_key(main, KEY_C, false)
	eq(radio.pending.size(), 0, "a greyed slice asks nobody")
	eq(_toast(main), why, "and says why")
	dez.downed = false
	# Ana is bleeding: Come with me is a soft refusal, marked Insist; choosing it asks, and she says so, with Insist in the dock
	ana.bleeding = 2.0
	main._try_select({"kind": "person", "ref": ana})
	_key(main, KEY_C)
	var come: Dictionary = main.hud.wheel.slices[_verb_index("come")]
	check(bool(come.enabled) and bool(come.soft), "Come with me is open but marked Insist for her")
	check(String(come.tip).begins_with(String(radio.willingness(ana, "come").why)), "its line is her reason: %s" % come.tip)
	check(not bool(main.hud.wheel.slices[_verb_index("hold")].soft), "Hold here is not refused for a wound")
	_on_slice(main, _verb_index("come"))
	_key(main, KEY_C, false)
	var asked: Dictionary = main.hud.radio_verbs.last
	check(not bool(asked.ok) and String(asked.verb) == "come", "Come with me was asked and refused")
	eq(radio.pending.size(), 0, "nothing waits")
	check(main.hud.radio_verbs.insist_button.visible, "the dock offers Insist")
	main.hud.radio_verbs.insist_button.pressed.emit()
	eq(radio.pending.size(), 1, "Insist asks again")
	await TutorialKit.leave(main)


func test_shift_is_the_second_ring_everyone_near_is_asked_and_their_answers_are_one_line() -> void:
	var main := _game()
	var crew := _crew(main)
	var dez = crew[0]
	var ana = crew[1]
	var marcus = crew[2]
	var walt = crew[3]
	_stand(main, dez, SPOT + Vector2(2.0, 0.0))
	_stand(main, ana, SPOT + Vector2(0.0, 3.0))
	_stand(main, marcus, SPOT + Vector2(-5.0, 0.0))
	_stand(main, walt, SPOT + Vector2(0.0, -8.5))    # (not near: more than eight tiles)
	marcus.bleeding = 2.0
	var radio = main.sim.radio
	var ctl = main.wheel_ctl
	main._select(null)
	main.mouse_screen = _at(main, SPOT + Vector2(4.0, -3.0))
	_key(main, KEY_C)
	check(not main.hud.wheel.group, "one person at first")
	_key(main, KEY_SHIFT, true, true)
	check(main.hud.wheel.group and bool(ctl.info.group), "Shift turns on the second ring")
	eq(main.hud.wheel.title, "Everyone", "the centre says so")
	eq(ctl.info.members.size(), 3, "everyone within eight tiles, not Walt")
	_on_slice(main, _verb_index("come"))
	_key(main, KEY_C, false)
	eq(radio.pending.size(), 2, "one request each for the two who can")
	var line := _toast(main)
	eq(line, "%s and %s: on my way; %s" % [dez.first, ana.first, String(radio.willingness(marcus, "come").why)], "one line: who agreed, then the refusal in the radio's words")
	# the summary on its own
	var sum := WheelCtl.summarize([
		{"p": dez, "ok": true, "line": "On my way.", "why": ""},
		{"p": ana, "ok": true, "line": "On my way.", "why": ""},
		{"p": walt, "ok": true, "line": "Fine. Coming.", "why": ""},
		{"p": marcus, "ok": false, "line": "", "why": "Marcus: tending a patient, can't come"},
	])
	eq(sum.text, "%s and %s: on my way; %s: fine, coming; Marcus: tending a patient, can't come" % [dez.first, ana.first, walt.first], "the lines are grouped by what they said")
	eq(WheelCtl.join_names(["A", "B", "C", "D"]), "A, B and 2 more", "and long lists are cut")
	await TutorialKit.leave(main)


# ---------------------------------------------------------- the keys 1 to 5 and Z --

func test_the_number_keys_pick_the_crew_by_card_order_tab_goes_on_round_and_z_asks_the_last_order_again() -> void:
	var main := _game()
	var crew := _crew(main)
	var ruth = main.sim.avatar.player()
	_key(main, KEY_1)
	check(main.selection != null and main.selection.ref == crew[0] and crew[0] != ruth, "1 picks the first card that is not you")
	_key(main, KEY_3)
	check(main.selection.ref == crew[2], "3 picks the third")
	_key(main, KEY_TAB)
	check(main.selection.ref != crew[2] and main.selection.kind == "person", "Tab still goes on round")
	var picked = main.selection.ref
	_key(main, KEY_2, true, true)
	eq(main.speed, 2, "Shift and 2 is the speed")
	check(main.selection.ref == picked, "(and picks nobody)")
	check(main.hud.speed_buttons[2].tooltip_text.contains("Shift+2"), "the speed buttons' tips say Shift+2")
	main.hud.update_hud(main.sim, main.speed, true, 0)
	var card_key := ""
	for c in main.hud.cards:
		if c.p == crew[0]:
			card_key = c.key.text
	eq(card_key, "1", "the first card carries its number")
	# Z: the last order on the next person picked
	var a = crew[0]
	var b = crew[1]
	_stand(main, a, SPOT + Vector2(2.0, 0.0))
	_stand(main, b, SPOT + Vector2(-2.0, 0.0))
	var radio = main.sim.radio
	main._try_select({"kind": "person", "ref": a})
	main.mouse_screen = _at(main, Vector2(46.7, 33.2))
	_key(main, KEY_C)
	_on_slice(main, _verb_index("hold"))
	_key(main, KEY_C, false)
	eq(radio.pending.size(), 1, "(the first Hold here is asked)")
	check(main.wheel_ctl.last_order.get("verb", "") == "hold", "(and remembered)")
	_key(main, KEY_2)
	check(main.selection.ref == b, "2 picks the next person")
	_key(main, KEY_Z)
	var again := false
	for r in radio.pending:
		if String(r.who) == String(b.id) and String(r.verb) == "hold":
			near_v(Vector2(r.at), Vector2(46.5, 33.5), "the same point")
			again = true
	check(again, "Z asks %s to hold the same point" % b.first)
	check(_toast(main).ends_with("(again)") and _toast(main).begins_with("%s: " % b.first), "and says so: %s" % _toast(main))
	await TutorialKit.leave(main)


# ---------------------------------------------------------------- the status marks --

func test_a_person_who_carries_an_order_wears_a_glyph_pill_and_a_dotted_line_to_the_spot() -> void:
	var main := _game()
	var crew := _crew(main)
	var dez = crew[0]
	var walt = crew[1]
	_stand(main, dez, SPOT + Vector2(2.0, 0.0))
	_stand(main, walt, SPOT + Vector2(15.0, 0.0))    # (on the screen, but farther than the marks reach: twelve tiles)
	var spot := SPOT + Vector2(4.5, 2.5)
	main.sim.radio.set_stance(dez, "hold", spot)
	main.sim.radio.set_stance(walt, "cover", Vector2.ZERO)
	eq(StanceMarks.of_person(dez), "hold", "a hold is a hold")
	eq(StanceMarks.of_person(walt), "cover", "a cover is a cover")
	main.sim.radio.set_stance(walt, "follow", Vector2.ZERO)
	eq(StanceMarks.of_person(walt), "come", "and a follow is Come with me")
	near_v(StanceMarks.spot_of(dez, "hold"), spot, "the spot of a hold")
	check(StanceMarks.spot_of(walt, "come") == Vector2.INF, "following points nowhere")
	main.overlay.queue_redraw()
	await TutorialKit.settle()
	check(main.overlay.drawn_stance_marks >= 1 and main.overlay.stance_kinds.has("hold"), "the pill is drawn over Dez (%s)" % str(main.overlay.stance_kinds))
	check(main.overlay.drawn_stance_links >= 1, "with a dotted line to the spot")
	check(not main.overlay.stance_people.has(walt), "not over Walt, who is far off and not picked")
	main._try_select({"kind": "person", "ref": walt})
	main.overlay.queue_redraw()
	await TutorialKit.settle()
	check(main.overlay.stance_people.has(walt), "but over the person picked, wherever they are")
	await TutorialKit.leave(main)


# --------------------------------------------------------------------- a place --

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


func _scene_key(scene: Node, code: Key, pressed: bool = true, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = pressed
	ev.shift_pressed = shift
	scene._input(ev)


func _scene_motion(scene: Node, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	scene._input(ev)
	scene._unhandled_input(ev)


func test_in_a_place_the_wheel_asks_the_squad_search_that_needs_a_container_and_the_road_says_not_here() -> void:
	PlaceFlow.live_enabled = false
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": true}, 1280, 800)
	AimMode.set_mode("right")
	var party: Array = []
	for i in 3:
		party.append(main.sim.people[i])
	var scene := RaidScene.new()
	main.add_child(scene)
	scene.set_process(false)
	scene.setup(main, main.hud, main.data, _site(), party, 300.0, "", 1.0, false)
	var lead = scene.leader()
	var friend = null
	for p in scene.run.squad:
		if p != lead:
			friend = p
	friend.x = lead.x + 2.0
	friend.y = lead.y
	scene.hud_layer.pick_contact("squad", friend)
	var radio = scene.run.sim.radio
	var wheel = scene.hud_layer.wheel
	# the pointer on the cabinet: C opens the wheel, Search that is open, let go over it asks the friend to search that container
	scene._mouse = scene.to_screen(Vector2(16.5, 6.5))
	_scene_key(scene, KEY_C)
	check(scene.wheel_ctl != null and scene.wheel_ctl.is_open() and wheel.visible, "C opens the wheel in a place")
	eq(wheel.title, String(friend.first), "for the contact picked")
	var search: Dictionary = wheel.slices[_verb_index("search")]
	check(bool(search.enabled), "Search that is open with a container under the pointer")
	_scene_motion(scene, wheel.centre + CommandWheel.slice_mid(_verb_index("search")))
	_scene_key(scene, KEY_C, false)
	check(not scene.wheel_ctl.is_open(), "let go over a slice, it shuts")
	check(not radio.pending.is_empty() and String(radio.pending[0].verb) == "search", "the friend is asked to search")
	near_v(Vector2(radio.pending[0].at), Vector2(16.5, 6.5), "that container")
	# the pointer on bare ground far from any container: Search that is greyed with its reason; Esc shuts the wheel
	radio.pending.clear()
	scene._mouse = scene.to_screen(Vector2(19.5, 10.5))
	_scene_key(scene, KEY_C)
	check(scene.wheel_ctl.is_open(), "it opens again")
	var none: Dictionary = wheel.slices[_verb_index("search")]
	check(not bool(none.enabled) and String(none.tip) == "Aim at a shelf or a crate first", "Search that is greyed: %s" % none.tip)
	_scene_key(scene, KEY_ESCAPE)
	check(not scene.wheel_ctl.is_open() and radio.pending.is_empty(), "Esc cancels and nobody is asked")
	# while it is up the hands do not fire
	_scene_key(scene, KEY_C)
	scene.fire_held = true
	scene.aim_held = true
	scene._hands()
	check(not scene.fire_held and not scene.aiming(), "no aim and no fire while the wheel is up")
	_scene_key(scene, KEY_ESCAPE)
	AimMode.set_holstered(false)
	PlaceFlow.live_enabled = true
	DriveScene.stand_ins = {}
	await TutorialKit.leave(main)
