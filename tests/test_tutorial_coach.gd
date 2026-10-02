extends "res://tests/case.gd"
## The coach on the real game scene: the soft lock (what it refuses and allows, through the real
## handlers), the game waiting while a card is read, the wait cards, the escalation after idling, the
## last card and its buttons, Skip at every step, and the cards' places at three window widths.

const Tut := preload("res://tests/tutorial_kit.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Hud := preload("res://scripts/ui/hud.gd")


func _toast(main) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


func _clear_toast(main) -> void:
	main.hud.toast_panel.visible = false
	main.hud.toast_label.text = ""
	main.coach._toast_text = ""


func _step_index(coach, id: String) -> int:
	for i in coach.steps.size():
		if String(coach.steps[i].id) == id:
			return i
	return -1


# ------------------------------------------------------------- the soft lock --

func test_the_soft_lock_refuses_what_the_step_does_not_teach_and_allows_what_it_does() -> void:
	var main = Tut.game(1)
	var sim = main.sim
	await Tut.frames(main, 30)
	var coach = main.coach
	eq(coach.step_id(), "send", "the lesson on giving an order")
	check(coach.held and main.speed == 0, "the game waits while the player decides")
	var ruth = Bot.person(main, "ruth")
	var hector = Bot.person(main, "hector")
	# an order the step does not teach, with nobody selected
	main._key(KEY_P)
	eq(_toast(main), "Not yet: first select Ruth, then right-click the ground.", "P is refused, gently, with what to do first")
	check(hector.order == null, "and nothing happened")
	# the speed keys while the card is up
	_clear_toast(main)
	main._key(KEY_3)
	eq(main.speed, 0, "the game stays still")
	eq(_toast(main), "The game waits while you read.", "and says so")
	# someone else cannot be selected, Ruth can
	_clear_toast(main)
	Bot.card_click(main, "hector")
	check(main.selection == null, "Hector's card is refused")
	check(_toast(main).begins_with("Not yet: first select Ruth"), "with the same goal")
	Bot.card_click(main, "ruth")
	check(Bot.selected(main, "ruth"), "Ruth's card is taken")
	# with Ruth selected, an order that is not the step's is refused
	_clear_toast(main)
	main._key(KEY_R)
	check(not ruth.drafted, "R is refused: nobody was drafted")
	check(_toast(main).begins_with("Not yet: first"), "with a toast")
	main._key(KEY_B)
	check(not sim.tactics.auto_repair(ruth), "so is B")
	_clear_toast(main)
	main._key(KEY_X)
	eq(_toast(main), "Not in the tutorial: X sends someone out for good.", "X is explained, not used")
	# the buttons are ghosts
	await Tut.frames(main, 8)
	var draft: Button = null
	for b in main.hud.gizmos.get_children():
		if b.has_meta("id") and b.get_meta("id") == "draft":
			draft = b
	check(draft != null and draft.modulate.a < 0.5, "the Draft button is a ghost")
	for b in main.hud.speed_buttons:
		if b != main.hud.speed_buttons[0]:
			check(b.modulate.a < 0.5, "and so is a speed button while the game waits")
	# the camera, Esc and the wheel always work
	var zoom_was: float = main.zoom_px
	Bot.pan_and_zoom(main)
	check(not is_equal_approx(main.zoom_px, zoom_was), "the wheel zooms")
	check(float(coach.state.pan) > 0.0 and float(coach.state.zoom) > 0.0, "and the coach saw the camera move")
	main._key(KEY_ESCAPE)
	check(main.selection == null, "Esc lets go of the selection")
	# an order to walk, outside the walls or far off, is refused; a few steps away is taken
	Bot.card_click(main, "ruth")
	main._focus(Vector2(ruth.x, ruth.y))
	main._apply_camera()
	_clear_toast(main)
	main._click(main._tile_to_screen(Vector2(40.0, 10.0)), MOUSE_BUTTON_RIGHT)
	eq(_toast(main), "Pick a spot inside the yard.", "outside the wall is refused")
	check(ruth.order == null, "and nobody walks")
	_clear_toast(main)
	main._click(main._tile_to_screen(Vector2(ruth.x + 20.0, ruth.y + 12.0)), MOUSE_BUTTON_RIGHT)
	eq(_toast(main), "Pick a spot a little closer to Ruth.", "far away is too")
	main._click(main._tile_to_screen(Vector2(ruth.x + 4.0, ruth.y)), MOUSE_BUTTON_RIGHT)
	check(ruth.order != null and ruth.drafted, "a few steps away is taken: Ruth has her order")
	check(float(coach.state.did.get("move", 0.0)) == 1.0, "and the coach was told")
	await Tut.frames(main, 4)
	check(not coach.held and main.speed == 1, "the game runs again at the speed it had")
	await Tut.leave(main)


func test_a_step_with_no_lock_to_speak_of_lets_the_player_look_but_not_order() -> void:
	# the card that waits for the afternoon: people may be looked at, nothing may be ordered
	var main = Tut.game(0)
	await Tut.frames(main, 4)
	var coach = main.coach
	coach._begin(_step_index(coach, "report"))
	await Tut.frames(main, 6)
	eq(coach.phase, "wait", "it waits for its moment")
	check(not coach.held and main.speed == 1, "the day runs")
	Bot.card_click(main, "ruth")
	check(Bot.selected(main, "ruth"), "a person can be looked at")
	main._key(KEY_R)
	check(not Bot.person(main, "ruth").drafted, "but not ordered")
	eq(_toast(main), "Not yet: let the day go on first.", "and the toast says to let the day go on")
	check(coach.speed_button.visible, "there is a Speed up button")
	coach.speed_button.pressed.emit()
	eq(main.speed, 3, "it sets the fastest speed")
	main._key(KEY_1)
	eq(main.speed, 1, "and the speed keys are the player's")
	await Tut.leave(main)


func test_orders_flow_normally_with_no_coach() -> void:
	# a normal run: the gate is open and the HUD has no lock
	var main = Tut.start({"difficulty": 1, "seed": 5})
	await Tut.frames(main, 3)
	check(main.coach == null and not main.tutorial, "no coach, no tutorial")
	check(main._allows("gizmo", "post") and main._allows("move", Vector2(1, 1)) and main._allows("speed", 3), "every gate is open")
	check(not main.hud.lock_allowed.is_valid(), "the HUD has no lock")
	Bot.card_click(main, "hector")
	check(Bot.selected(main, "hector"), "anyone can be selected")
	main._key(KEY_P)
	check(Bot.person(main, "hector").order != null, "and given an order")
	main._key(KEY_3)
	eq(main.speed, 3, "the speed keys work")
	check(main._save_path() == "user://quicksave.json", "F5 writes the quick save")
	await Tut.leave(main)


# --------------------------------------------------------------- the holds --

func test_the_game_waits_while_a_card_is_up_and_goes_on_at_the_speed_it_had() -> void:
	var main = Tut.game(0)
	await Tut.frames(main, 4)
	var coach = main.coach
	check(coach.held and main.speed == 0, "the first card holds the game")
	var steps_before: int = main.sim_steps
	await Tut.frames(main, 30)
	eq(main.sim_steps, steps_before, "no step of the rules was taken while it was read")
	# the player chooses the double speed while the day runs on towards the afternoon
	coach._begin(_step_index(coach, "report"))
	await Tut.frames(main, 4)
	check(not coach.held, "a wait lets the day run")
	main._key(KEY_2)
	eq(main.speed, 2, "the player's own speed")
	# a card to be read holds it again, and remembers
	coach._begin(_step_index(coach, "stores"))
	await Tut.frames(main, 4)
	check(coach.held and main.speed == 0, "a card to be read holds the game")
	eq(coach.held_speed, 2, "remembering the speed")
	coach.next_button.pressed.emit()
	eq(coach.step_id(), "scavenge", "Got it moves on")
	await Tut.frames(main, 4)
	check(coach.held and main.speed == 0, "the next card holds as well, with no run of the rules between")
	# the end of it all gives the game back at the speed it had
	coach.skip_button.pressed.emit()
	coach.stay_button.pressed.emit()
	eq(main.speed, 2, "the game goes on at double speed")
	await Tut.leave(main)


func test_the_first_cards_ask_for_a_pause_and_the_run_steps_do_not_pause_after_the_order() -> void:
	for s in Coach.load_steps():
		var pauses: bool = bool(s.get("pause", false)) or s.has("pause_until")
		if ["look", "release", "stores", "scavenge", "report", "fields", "alarm", "save", "jobs", "wrap"].has(String(s.id)):
			check(pauses, "%s waits for the player" % s.id)
		if ["scratch"].has(String(s.id)):
			check(not pauses, "%s needs time to pass" % s.id)


# ----------------------------------------------------------- idle and arrows --

func test_after_twenty_seconds_of_nothing_the_ring_pulses_and_show_me_brings_an_arrow() -> void:
	var main = Tut.game(1)
	await Tut.frames(main, 30)
	var coach = main.coach
	check(coach.target_rect.size.x > 0.0, "the card's portrait is lit")
	eq(coach.target_name, "card:ruth", "it is Ruth's picture")
	check(not coach.spot.pulse and not coach.spot.arrow and not coach.show_button.visible, "at first it is calm")
	for i in 42:
		coach.tick(0.5)
	check(coach.spot.pulse, "after 20 seconds the ring pulses")
	check(coach.show_button.visible, "and Show me appears")
	check(not coach.spot.arrow, "but no arrow yet")
	coach.show_button.pressed.emit()
	await Tut.frames(main, 3)
	check(coach.spot.arrow, "Show me brings the arrow")
	# anything the player does starts the quiet again
	Bot.card_click(main, "ruth")
	await Tut.frames(main, 3)
	check(not coach.spot.pulse and not coach.show_button.visible, "a click is somebody being there")
	await Tut.leave(main)


func test_after_forty_five_seconds_the_arrow_comes_by_itself() -> void:
	var main = Tut.game(1)
	await Tut.frames(main, 30)
	var coach = main.coach
	for i in 92:
		coach.tick(0.5)
	check(coach.spot.arrow, "the arrow is up")
	await Tut.leave(main)


# ------------------------------------------------------------- the last card --

func test_the_last_card_offers_a_real_run_a_replay_and_staying() -> void:
	var main = Tut.game(_index_of("wrap"))
	var picked: Array = []
	main.restart = func(meta): picked.append(meta)
	await Tut.frames(main, 40)
	var coach = main.coach
	eq(coach.step_id(), "wrap", "the last card")
	eq(coach.phase, "wrap", "in the wrap-up phase")
	check(Prefs.flag("tutorial_done"), "reaching it sets the flag")
	check(coach.wrap_box.visible and not coach.skip_button.visible, "three buttons, and no Skip any more")
	check(coach.held and main.speed == 0, "the game waits")
	eq(coach.title_label.text, "Well done", "its words")
	eq([coach.real_button.text, coach.replay_button.text, coach.stay_button.text], ["Start a real run", "Replay", "Keep playing here"], "the three buttons")
	coach.real_button.pressed.emit()
	eq(picked.size(), 1, "Start a real run begins a run")
	eq(int(picked[0].difficulty), 1, "a Standard one")
	check(picked[0].has("seed"), "with a seed")
	eq(int(picked[0].get("crew", 6)), 3, "and the small crew a new game begins with")
	coach.replay_button.pressed.emit()
	eq(picked.size(), 2, "Replay begins one too")
	eq(picked[1], {"tutorial": true}, "of Orientation Day")
	check(main.coach == coach, "the coach is still there until one is chosen to stay")
	coach.stay_button.pressed.emit()
	check(main.coach == null, "Keep playing here lets the coach go")
	check(not main.hud.lock_allowed.is_valid(), "and lifts the lock")
	check(main.speed > 0, "the game runs")
	check(main.sim.scenario.finished, "the scenario takes over")
	main.hud.select(null)
	main._key(KEY_3)
	eq(main.speed, 3, "and every key is the player's")
	await Tut.leave(main)


# ------------------------------------------------------------------- skipping --

func test_skip_works_at_every_step_and_sets_the_flag() -> void:
	var count := Coach.load_steps().size()
	for i in count:
		var main = Tut.game(i)
		await Tut.frames(main, 12)
		var coach = main.coach
		var id: String = coach.step_id()
		check(coach.skip_button.is_visible_in_tree() or id == "wrap", "%s: Skip is always there" % id)
		if id != "wrap":
			Prefs.reset()
			check(not Prefs.flag("tutorial_done"), "%s: the flag was not set before" % id)
			coach.skip_button.pressed.emit()
			await Tut.frames(main, 4)
			check(Prefs.flag("tutorial_done"), "%s: Skip sets the flag" % id)
			eq(coach.phase, "wrap", "%s: Skip goes to the last card" % id)
			check(coach.skipped and coach.title_label.text == "Skipped", "%s: which says it was skipped" % id)
			check(coach.wrap_box.visible and not coach.skip_button.visible, "%s: and offers the three things to do" % id)
			check(coach.held and main.speed == 0, "%s: the game waits for the choice" % id)
		coach.stay_button.pressed.emit()
		await Tut.frames(main, 4)
		check(main.coach == null and main.speed > 0, "%s: the game goes on after Skip and Keep playing" % id)
		check(not main.hud.lock_allowed.is_valid(), "%s: with nothing locked" % id)
		eq(main.sim.over, "", "%s: and the run is not over" % id)
		await Tut.leave(main)


func test_skip_during_a_wait_works_too() -> void:
	var main = Tut.game(0)
	await Tut.frames(main, 4)
	var coach = main.coach
	coach._begin(_step_index(coach, "report"))
	await Tut.frames(main, 6)
	eq(coach.phase, "wait", "waiting for the afternoon")
	coach.skip_button.pressed.emit()
	eq(coach.phase, "wrap", "Skip works while waiting")
	check(Prefs.flag("tutorial_done"), "and sets the flag")
	await Tut.leave(main)


# ---------------------------------------------------- the cards' places --

## The coach's picture of where it has put things, checked for one step in the present window.
func _check_picture(main, label: String, w: int, h: int) -> void:
	var coach = main.coach
	var card: Rect2 = coach.card.get_global_rect()
	var screen := Rect2(0, 0, w, h)
	check(coach.card.visible, "%s: the card is up" % label)
	check(screen.grow(1.0).encloses(card), "%s: the card is inside the window %s %s" % [label, str(card), str(screen)])
	if coach.target_rect.size.x > 0.0:
		check(not card.intersects(coach.target_rect.grow(1.0)), "%s: the card does not cover what it points at (%s over %s)" % [label, str(card), str(coach.target_rect)])
	check(card.size.y < float(h) * 0.5, "%s: the card is not tall (%.0f in %d)" % [label, card.size.y, h])
	check(card.size.x >= 340.0 and card.size.x <= 400.0, "%s: the card is its width (%.0f)" % [label, card.size.x])


func test_every_step_points_at_something_and_its_card_stays_clear_of_it() -> void:
	var steps := Coach.load_steps()
	for width in [1280, 980, 1920, 900]:
		var height := {980: 700, 1280: 800, 1920: 1080, 900: 640}[width] as int
		var main = Tut.game(0, width, height)
		await Tut.frames(main, 6)
		var coach = main.coach
		for i in steps.size():
			if i > 0:
				coach.begin(i)
			await Tut.frames(main, 24)
			var id: String = coach.step_id()
			var label := "%dx%d %s" % [width, height, id]
			eq(id, String(steps[i].id), "%s: the step is the one asked for" % label)
			if coach.phase == "wait":
				check(coach.target_rect.size.x > 0.0 or not steps[i].has("wait_anchor"), "%s: the wait points at something" % label)
				_check_picture(main, label + " (waiting)", width, height)
				# let the moment come: the day goes by
				main._key(KEY_3)
				var guard := 0
				while coach.phase == "wait" and guard < 4000:
					await Tut.frames(main, 10)
					guard += 10
				await Tut.frames(main, 24)
			var wants: bool = not (steps[i].get("anchor", []) as Array).is_empty()
			if wants:
				check(coach.target_rect.size.x > 0.0, "%s: the lesson points at something (%s)" % [label, coach.target_name])
			_check_picture(main, label, width, height)
		await Tut.leave(main)


func test_a_wait_card_keeps_clear_of_what_it_points_at() -> void:
	for id in ["shoot", "workshop", "report"]:
		var main = Tut.game(0, 1280, 800)
		await Tut.frames(main, 4)
		var coach = main.coach
		main.sim.scenario.jump({"hour": 17.3 if id != "report" else 15.0, "bus": 1.0})
		coach._begin(_step_index(coach, id))
		await Tut.frames(main, 40)
		eq(coach.phase, "wait", "%s waits" % id)
		check(coach.target_rect.size.x > 0.0, "%s: the wait points at the %s" % [id, coach.target_name])
		_check_picture(main, "wait of " + id, 1280, 800)
		await Tut.leave(main)


func test_while_the_scavenging_dialog_is_open_the_card_is_one_line_at_the_top() -> void:
	var main = Tut.game(4, 1280, 800)
	await Tut.frames(main, 40)
	var coach = main.coach
	eq(coach.step_id(), "scavenge", "the trip lesson")
	var normal: Rect2 = coach.card.get_global_rect()
	Bot.card_click(main, "ana")
	main._key(KEY_G)
	await Tut.frames(main, 40)
	check(main.hud.scavenge_dialog != null, "the dialog is open")
	eq(coach.target_name, "dialog.site:houses", "the lit part is the houses")
	var small: Rect2 = coach.card.get_global_rect()
	check(small.size.y < normal.size.y, "the card is smaller (%.0f against %.0f)" % [small.size.y, normal.size.y])
	check(small.position.y <= 20.0, "at the top")
	check(not small.intersects(coach.target_rect), "off the houses")
	check(not coach.dim_rect.visible, "the dialog is not dimmed a second time")
	main.hud.scavenge_dialog.choose_site("houses")
	await Tut.frames(main, 10)
	eq(coach.target_name, "dialog.send", "once a place is chosen the lit part is Send")
	await Tut.leave(main)


# ------------------------------------------------------------ the card's words --

func test_the_card_names_the_next_part_of_a_step_that_has_several() -> void:
	var main = Tut.game(1)
	await Tut.frames(main, 20)
	var coach = main.coach
	eq(coach.goal_label.text, "Select Ruth, then right-click the ground", "at first the whole of it")
	Bot.card_click(main, "ruth")
	await Tut.frames(main, 8)
	eq(coach.goal_label.text, "Right-click the ground nearby", "once Ruth is selected only what is left")
	main._key(KEY_ESCAPE)
	await Tut.frames(main, 8)
	eq(coach.goal_label.text, "Select Ruth, then right-click the ground", "and the whole again if she is let go")
	# the trip has three parts after the card is clicked
	coach._begin(_step_index(coach, "scavenge"))
	await Tut.frames(main, 8)
	main._select(null)
	await Tut.frames(main, 8)
	eq(coach.goal_label.text, "Select Ana, press G, choose a place, then Send", "the trip, from the start")
	Bot.card_click(main, "ana")
	await Tut.frames(main, 8)
	eq(coach.goal_label.text, "Press G", "G")
	main._key(KEY_G)
	await Tut.frames(main, 8)
	eq(coach.goal_label.text, "", "in the dialog the card has its own short line")
	eq(coach.text_label.text, "In the box, click the houses, then press Send.", "which says what to do")
	main.hud.scavenge_dialog.choose_site("houses")
	await Tut.frames(main, 8)
	await Tut.leave(main)


func test_a_card_that_waits_has_its_own_title_and_words() -> void:
	var main = Tut.game(0)
	await Tut.frames(main, 4)
	var coach = main.coach
	coach._begin(_step_index(coach, "report"))
	await Tut.frames(main, 8)
	eq(coach.phase, "wait", "waiting")
	eq(coach.title_label.text, "The day goes on", "its title is not the lesson's")
	check(coach.text_label.text.begins_with("Ana is due back at 16:00"), "its words are the wait's")
	check(not coach.goal_label.visible, "and it asks for nothing")
	await Tut.leave(main)


func test_a_spot_too_near_to_walk_to_is_refused() -> void:
	var main = Tut.game(1)
	await Tut.frames(main, 20)
	var ruth = Bot.person(main, "ruth")
	Bot.card_click(main, "ruth")
	main._focus(Vector2(ruth.x, ruth.y))
	main._apply_camera()
	_clear_toast(main)
	main._click(main._tile_to_screen(Vector2(ruth.x + 1.0, ruth.y)), MOUSE_BUTTON_RIGHT)
	eq(_toast(main), "Pick a spot a bit further from Ruth.", "a step of a tile is no walk")
	check(ruth.order == null, "and nobody was ordered")
	await Tut.leave(main)


# ------------------------------------------------------ the arrow and the calm --

func test_the_arrow_comes_from_a_side_with_room_and_never_from_under_the_card() -> void:
	var steps := Coach.load_steps()
	for width in [1280, 980]:
		var height := {980: 700, 1280: 800}[width] as int
		var main = Tut.game(0, width, height)
		await Tut.frames(main, 6)
		var coach = main.coach
		for i in steps.size():
			if i > 0:
				coach.begin(i)
			await Tut.frames(main, 18)
			if coach.target_rect.size.x <= 0.0 or coach.phase == "wrap":
				continue
			var spot = coach.spot
			var r: Rect2 = coach.target_rect.grow(6.0)
			var dir: Vector2 = spot._arrow_dir(r)
			var base: Vector2 = spot._edge_point(r, dir)
			var box := Rect2(base, Vector2.ZERO).expand(base + dir * 62.0).grow(14.0)
			var label := "%dx%d %s" % [width, height, coach.step_id()]
			check(is_equal_approx(dir.length(), 1.0), "%s: the arrow has a direction" % label)
			check(Rect2(0, 0, width, height).encloses(box.grow(-14.0)), "%s: the arrow stays in the window (%s)" % [label, str(box)])
			check(not box.intersects(coach.card.get_global_rect().grow(-2.0)), "%s: and out from under the card" % label)
		await Tut.leave(main)


func test_a_player_who_asked_for_less_motion_gets_a_still_ring_and_a_card_that_does_not_slide() -> void:
	var main = Tut.game(1)
	await Tut.frames(main, 4)
	var coach = main.coach
	Prefs.set_value("ui", "reduce_motion", true)
	for i in 42:
		coach.tick(0.5)
	check(coach.spot.reduce_motion, "the ring knows")
	check(coach.spot.pulse, "it is still asked to pulse (a steady swell, not a throb)")
	# a new card is there at once, in its place, not fading in or sliding to it
	coach._begin(_step_index(coach, "stores"))
	await Tut.frames(main, 1, 1.0 / 30.0, 99)
	check(coach.card.modulate.a == 1.0, "the card has no fade-in")
	check(coach.card.position.is_equal_approx(coach._card_rect.position), "and no slide: it is where it will stay (%s, %s)" % [str(coach.card.position), str(coach._card_rect.position)])
	# with the setting off, a card that changes place slides
	Prefs.set_value("ui", "reduce_motion", false)
	coach._begin(_step_index(coach, "post"))
	await Tut.frames(main, 1, 1.0 / 30.0, 99)
	check(coach.card.modulate.a < 1.0, "with motion allowed a new card fades in")
	await Tut.leave(main)


# ------------------------------------------------------- events and sounds --

func test_every_event_of_the_rules_reaches_the_coach() -> void:
	var main = Tut.game(1)
	await Tut.frames(main, 4)
	var coach = main.coach
	main.sim.events.append({"type": "shot", "weapon": "rifle", "x": 30.0, "y": 20.0})
	main.sim.events.append({"type": "shot", "weapon": "rifle", "x": 30.0, "y": 20.0})
	main.sim.events.append({"type": "bell"})
	main._handle_events()
	eq(float(coach.state.events.get("shot", 0.0)), 2.0, "two shots were counted")
	eq(float(coach.state.events.get("bell", 0.0)), 1.0, "and a bell")
	check(main.sim.events.is_empty(), "the events were used up as before")
	await Tut.leave(main)


class FakeUiSound:
	extends Node
	var heard: Array = []

	func play(_n: String, _level: float = 1.0, _var: float = 0.04, _pitch: float = 1.0) -> void:
		pass

	func set_ambience(_a: float, _b: float, _c: float) -> void:
		pass

	func set_muted(_m: bool) -> void:
		pass

	func ui(sound_name: String, level: float = 1.0, _var: float = 0.02) -> void:
		heard.append([sound_name, level])


func test_a_done_step_and_a_refusal_make_a_soft_sound() -> void:
	var main = Tut.game(2)
	await Tut.frames(main, 4)
	var coach = main.coach
	main.sound.queue_free()
	var fake := FakeUiSound.new()
	main.sound = fake
	main.add_child(fake)
	main._key(KEY_P)
	check(fake.heard.size() == 1 and fake.heard[0][0] == "ui_error", "a refusal: the error sound, quietly (%s)" % str(fake.heard))
	Bot.card_click(main, "ruth")
	main._key(KEY_R)
	await Tut.frames(main, 40)
	check(not fake.heard.is_empty() and fake.heard[fake.heard.size() - 1][0] == "ui_confirm", "a step that is done: the confirm sound (%s)" % str(fake.heard))
	await Tut.leave(main)


# ------------------------------------------------------------------- legibility --

const HudText := preload("res://tests/test_hud_text.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")


## The size and the colour of every word on a card: nothing under the HUD's floor, and every colour
## reads on the panel even over the brightest ground.
func _check_words(card: Control, label: String) -> void:
	var panel := Color(Hud.PANEL, 1.0)
	var worst := HudText.over(Hud.PANEL, Color.WHITE)
	var seen := 0
	var nodes: Array = [card]
	while not nodes.is_empty():
		var n: Node = nodes.pop_back()
		nodes.append_array(n.get_children())
		if not (n is Label or n is Button):
			continue
		if n is Button and (n as Button).text == "":
			continue
		if n is Label and (n as Label).text == "":
			continue
		var size_px: int = n.get_theme_font_size("font_size")
		check(size_px >= Fonts.MIN_PX, "%s: '%s' is %d px (the floor is %d)" % [label, n.text, size_px, Fonts.MIN_PX])
		var key := "font_color"
		var colour: Color = n.get_theme_color(key)
		# a gold button carries dark ink on the gold: the HUD's own rule
		if n is Button and (n as Button).text != "" and colour == Hud.ACCENT_INK:
			check(HudText.contrast(colour, Hud.ACCENT) >= HudText.AA, "%s: '%s' reads on the gold" % [label, n.text])
		else:
			for ground in [panel, worst]:
				var ratio := HudText.contrast(colour, ground)
				check(ratio >= HudText.AA, "%s: '%s' is %.2f:1 on the panel" % [label, n.text, ratio])
		seen += 1
	check(seen >= 3, "%s: some words were looked at (%d)" % [label, seen])


func test_every_word_on_the_card_is_big_enough_and_reads_on_the_panel() -> void:
	var main = Tut.game(1)
	await Tut.frames(main, 10)
	var coach = main.coach
	_check_words(coach.card, "a lesson")
	coach._begin(_step_index(coach, "report"))
	await Tut.frames(main, 6)
	_check_words(coach.card, "a wait")
	coach.skip_button.pressed.emit()
	await Tut.frames(main, 6)
	_check_words(coach.card, "the last card")
	await Tut.leave(main)


func test_a_step_that_is_to_be_watched_runs_at_normal_speed_but_the_player_may_hurry_it() -> void:
	var main = Tut.game(0)
	await Tut.frames(main, 4)
	var coach = main.coach
	coach._begin(_step_index(coach, "shoot"))
	await Tut.frames(main, 4)
	eq(coach.phase, "wait", "waiting for the bell")
	main._key(KEY_3)
	eq(main.speed, 3, "the player hurries the day")
	main.sim.scenario.set_time(19.05, 1)
	await Tut.frames(main, 6)
	eq(coach.phase, "active", "the bell has rung")
	check(coach.held and main.speed == 0, "the game waits for Marcus to be chosen")
	Bot.card_click(main, "marcus")
	await Tut.frames(main, 4)
	check(not coach.held, "and goes on")
	eq(main.speed, 1, "at the normal speed: it is to be watched")
	main._key(KEY_3)
	eq(main.speed, 3, "the player may press a faster one")
	# a step with no hold (a scratch) takes the cap as it begins
	coach._begin(_step_index(coach, "scratch"))
	await Tut.frames(main, 4)
	eq(main.speed, 1, "a step that is only watched begins at the normal speed")
	await Tut.leave(main)


func test_the_huds_one_line_hint_stays_away_while_the_coach_teaches() -> void:
	var main = Tut.game(0)
	await Tut.frames(main, 20)
	check(not main.hud.hint.visible, "the basics line is not up beside the coach's cards")
	main.coach.skip_button.pressed.emit()
	main.coach.stay_button.pressed.emit()
	await Tut.frames(main, 20)
	check(not main.hud.hint.visible, "and does not come back when the coach has gone: its job was done")
	await Tut.leave(main)


func test_a_lesson_the_player_does_is_done_at_once_and_one_that_was_done_already_waits_to_be_read() -> void:
	var main = Tut.game(2)
	await Tut.frames(main, 20)
	var coach = main.coach
	eq(coach.step_id(), "release", "the release lesson")
	check(not bool(coach.state.get("pre", false)), "it was not done as it began")
	Bot.card_click(main, "ruth")
	main._key(KEY_R)
	await Tut.frames(main, 2, 1.0 / 30.0, 99)
	eq(coach.phase, "done", "two frames after R it is done: no second of waiting")
	await Tut.leave(main)
	# a lesson that is already done when it begins: Ruth is let go before the card comes
	var main2 = Tut.game(0)
	await Tut.frames(main2, 4)
	var coach2 = main2.coach
	coach2._begin(_step_index(coach2, "release"))
	await Tut.frames(main2, 4)
	check(bool(coach2.state.get("pre", false)), "this one was done already (nobody was drafted)")
	eq(coach2.phase, "active", "but it stays up a moment so it can be read")
	await Tut.frames(main2, 40)
	check(coach2.phase != "active", "and goes on after a second")
	await Tut.leave(main2)


# ------------------------------------------------------------ the duty roster --

func _index_of(id: String) -> int:
	var steps := Coach.load_steps()
	for i in steps.size():
		if String(steps[i].id) == id:
			return i
	return -1


## The short line a step's goal (the one whose condition is `when`) has for the card over a page of the HUD.
func _line_of(step: Dictionary, when: String) -> String:
	for g in step.get("goals", []):
		if String(g.get("when", "")) == when:
			return String(g.get("line", ""))
	return ""


## The real game on the lesson about the Duty roster (key J), in a window of `width` x `height`, after its first frames.
func _roster_game(width: int = 1280, height: int = 800) -> Node:
	var at := _index_of("jobs")
	check(at >= 0, "there is a lesson on the duty roster")
	if at < 0:
		return null
	var main = Tut.game(at, width, height)
	await Tut.frames(main, 12)
	return main


func test_the_duty_roster_lesson_asks_for_the_page_then_a_job_then_the_page_shut() -> void:
	var main = await _roster_game()
	if main == null:
		return
	var coach = main.coach
	var sim = main.sim
	eq(coach.step_id(), "jobs", "the lesson is up")
	eq(coach.phase, "active", "and begun")
	check(coach.held and main.speed == 0, "the game waits while the card is read")
	# the world the lesson expects: Walt and Hector have no day job to begin with
	check(sim.jobs.job_of(Bot.person(main, "walt")) == "" and sim.jobs.job_of(Bot.person(main, "hector")) == "", "Walt and Hector have no day job")
	eq(coach.target_name, "jobs", "the clipboard in the toolbar is lit")
	check(coach.target_rect.size.x > 0.0, "and it is on the screen")
	check(coach.dim_rect.visible, "with the screen dimmed round it, as for any part of the HUD")
	_check_words(coach.card, "the roster lesson")
	eq(float(coach.state.events.get("assigned:job", 0.0)), 0.0, "(the three jobs taken off at the very start are not jobs given)")
	# the lock: the Jobs screen is the one thing allowed
	check(main._allows("jobs"), "the Jobs screen is allowed")
	check(not main._allows("gizmo", "job_bench"), "M is not: a job is given on the page")
	check(main.hud.jobs_button.modulate.a > 0.9, "the clipboard is not a ghost")
	# J opens it
	main._key(KEY_J)
	await Tut.frames(main, 8)
	check(main.hud.jobs_screen != null, "J opens the Duty roster")
	var screen = main.hud.jobs_screen
	eq(float(coach.state.did.get("jobs", 0.0)), 1.0, "the coach saw it opened")
	eq(coach.phase, "active", "opening it is not the whole lesson")
	eq(coach.target_name, "jobs.auto", "Auto-assign is lit now")
	var step: Dictionary = coach.current_step()
	check(_line_of(step, "jobs_open") != "", "(the lesson has a line for the page)")
	eq(coach.text_label.text, _line_of(step, "jobs_open"), "the card says its short line for this part")
	check(not coach.title_label.visible and not coach.goal_label.visible, "and no more: a line at the top")
	_check_words(coach.card, "the line over the Duty roster")
	check(not coach.dim_rect.visible, "the page is not dimmed a second time")
	var small: Rect2 = coach.card.get_global_rect()
	check(small.position.y <= 20.0, "at the top of the window, over the page's heading")
	check(not small.intersects(coach.target_rect), "off Auto-assign")
	# a job given on the page
	check(screen.choose_job(Bot.person(main, "walt"), "garden"), "Walt is given the vegetable beds")
	await Tut.frames(main, 4)
	eq(float(coach.state.events.get("assigned:job", 0.0)), 1.0, "the coach counted the job given")
	eq(coach.target_name, "jobs.close", "Close is lit now")
	check(_line_of(step, "jobs_given") != "" and _line_of(step, "jobs_given") != _line_of(step, "jobs_open"), "(the lesson has another line for that)")
	eq(coach.text_label.text, _line_of(step, "jobs_given"), "and the card says so: the line is not the one for a job to be given")
	eq(coach.phase, "active", "but the page is still open: not done")
	# Close
	screen.close_button.pressed.emit()
	await Tut.frames(main, 6)
	eq(coach.phase, "done", "the page shut after a job: the lesson is done")
	await Tut.frames(main, 40)
	eq(coach.step_id(), "wrap", "and the last card comes")
	await Tut.leave(main)


func test_over_the_duty_roster_a_slow_player_gets_the_ring_and_the_arrow_but_the_card_stays_one_line() -> void:
	var main = await _roster_game(700, 560)
	if main == null:
		return
	var coach = main.coach
	main._key(KEY_J)
	await Tut.frames(main, 8)
	check(main.hud.jobs_screen != null, "the page is open")
	var one_line: float = coach.card.get_global_rect().size.y
	check(not coach.show_button.visible and not coach.spot.pulse and not coach.spot.arrow, "at first there is only the ring")
	coach.idle_t = 21.0
	await Tut.frames(main, 8)
	check(coach.spot.pulse, "after twenty seconds the ring pulses")
	check(not coach.show_button.visible, "but Show me is not offered: it would make the line a card that hides the first rows of the page")
	check(coach.card.get_global_rect().size.y <= one_line + 1.0, "the card is still one line (%.0f px)" % coach.card.get_global_rect().size.y)
	_check_rows_are_free(main, "after twenty seconds")
	coach.idle_t = 46.0
	await Tut.frames(main, 8)
	check(coach.spot.arrow, "after forty-five the arrow comes by itself")
	check(not coach.show_button.visible, "still without Show me")
	await Tut.leave(main)


func test_looking_at_the_page_or_taking_a_job_away_is_not_the_lesson() -> void:
	var main = await _roster_game()
	if main == null:
		return
	var coach = main.coach
	# opened and shut with nothing done
	main._key(KEY_J)
	await Tut.frames(main, 6)
	main.hud.jobs_screen.close_button.pressed.emit()
	await Tut.frames(main, 40)
	eq(coach.step_id(), "jobs", "a look at the page does not finish the lesson")
	eq(coach.phase, "active", "it is still up")
	eq(coach.target_name, "jobs", "and points at the button again")
	# a job taken away is not a job given
	main._key(KEY_J)
	await Tut.frames(main, 6)
	var screen = main.hud.jobs_screen
	check(screen.choose_job(Bot.person(main, "marcus"), ""), "Marcus is taken off the lookout post")
	await Tut.frames(main, 4)
	check(float(coach.state.events.get("assigned", 0.0)) >= 1.0, "the rules said so")
	eq(float(coach.state.events.get("assigned:job", 0.0)), 0.0, "but it is not a job given")
	eq(coach.target_name, "jobs.auto", "Auto-assign is still what is lit")
	screen.close_button.pressed.emit()
	await Tut.frames(main, 40)
	eq(coach.step_id(), "jobs", "so the lesson goes on")
	await Tut.leave(main)


func test_auto_assign_is_a_job_given_too() -> void:
	var main = await _roster_game()
	if main == null:
		return
	var coach = main.coach
	main._key(KEY_J)
	await Tut.frames(main, 6)
	var screen = main.hud.jobs_screen
	screen.auto_button.pressed.emit()
	await Tut.frames(main, 4)
	check(float(coach.state.events.get("assigned:job", 0.0)) >= 1.0, "Auto-assign gave jobs: the coach counted them")
	for id in ["walt", "hector"]:
		check(main.sim.jobs.job_of(Bot.person(main, id)) != "", "%s has a job now" % id)
	eq(coach.target_name, "jobs.close", "Close is lit")
	screen.close_button.pressed.emit()
	await Tut.frames(main, 6)
	eq(coach.phase, "done", "and the page shut: done")
	await Tut.leave(main)


func test_the_duty_roster_is_refused_in_the_lessons_that_do_not_teach_it() -> void:
	var main = Tut.game(0)
	await Tut.frames(main, 12)
	var coach = main.coach
	check(main.hud.jobs_button.modulate.a < 0.5, "the clipboard is a ghost in the first lesson")
	main._key(KEY_J)
	check(main.hud.jobs_screen == null, "J does not open the page")
	eq(_toast(main), "Not yet: first pan and zoom the view.", "and says what comes first")
	eq(float(coach.state.did.get("jobs", 0.0)), 0.0, "and the coach was not told it was opened")
	# the toolbar's button asks the same gate
	_clear_toast(main)
	main.hud.jobs_button.pressed.emit()
	check(main.hud.jobs_screen == null, "so does the clipboard")
	check(_toast(main).begins_with("Not yet"), "with the same toast")
	await Tut.leave(main)


func test_the_rules_events_that_give_a_job_are_counted_for_the_coach() -> void:
	var main = Tut.game(1)
	await Tut.frames(main, 4)
	var coach = main.coach
	var before := float(coach.state.events.get("assigned", 0.0))
	main.sim.events.append({"type": "assigned", "who": "walt", "station": "garden"})
	main.sim.events.append({"type": "assigned", "who": "dez", "station": ""})
	main._handle_events()
	eq(float(coach.state.events.get("assigned", 0.0)) - before, 2.0, "both are counted as the events they are")
	eq(float(coach.state.events.get("assigned:job", 0.0)), 1.0, "and the one that names a station is a job given")
	await Tut.leave(main)


## The card over the Duty roster is a line at the top of the window: it hides no one's Day job or Night post.
func _check_rows_are_free(main, label: String) -> void:
	var card: Rect2 = main.coach.card.get_global_rect()
	for id in main.hud.jobs_screen.rows:
		var row: Dictionary = main.hud.jobs_screen.rows[id]
		for key in ["job", "post"]:
			var button: Rect2 = row[key].get_global_rect()
			check(not card.intersects(button), "%s: the card does not hide %s's %s button (%s over %s)" % [label, id, key, str(card), str(button)])


func test_the_card_over_the_duty_roster_stays_in_the_window_and_off_the_buttons() -> void:
	for size in [Vector2i(1280, 800), Vector2i(980, 700), Vector2i(1920, 1080), Vector2i(900, 640), Vector2i(700, 560)]:
		var main = await _roster_game(size.x, size.y)
		if main == null:
			return
		var coach = main.coach
		var label := "%dx%d" % [size.x, size.y]
		_check_picture(main, label + " (the button)", size.x, size.y)
		main._key(KEY_J)
		await Tut.frames(main, 12)
		check(main.hud.jobs_screen != null, "%s: the page is open" % label)
		eq(coach.target_name, "jobs.auto", "%s: Auto-assign is lit" % label)
		_check_picture(main, label + " (Auto-assign)", size.x, size.y)
		_check_rows_are_free(main, label + " (Auto-assign)")
		main.hud.jobs_screen.choose_job(Bot.person(main, "hector"), "builders")
		await Tut.frames(main, 12)
		eq(coach.target_name, "jobs.close", "%s: Close is lit" % label)
		_check_picture(main, label + " (Close)", size.x, size.y)
		_check_rows_are_free(main, label + " (Close)")
		await Tut.leave(main)
