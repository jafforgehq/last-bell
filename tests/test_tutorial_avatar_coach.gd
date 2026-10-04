extends "res://tests/case.gd"
## The coach on the real game scene as the avatar's Orientation Day: which lesson it reads, what its soft lock lets through in avatar
## mode (the hands always; the pages and the map only when a step teaches them), what it notes of the radio and of the player's own
## shots, that every step can be started at (`--tutorial=N`) with the world as it expects, that its card never covers the person
## the player plays or the thing it points at (for each of the eight steps, in a window of 1280 x 800 and in one of 700 x 560), what a step
## brings when it begins (a time of day, the gate, the person picked) or when its moment comes (the dead at the bell), and that the lesson can
## be skipped at any step, from the card and from the Esc menu, and then goes on as a normal game.

const Tut := preload("res://tests/tutorial_kit.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const MainScript := preload("res://scripts/main.gd")
const Prefs := preload("res://scripts/prefs.gd")

const IDS := ["you", "walk", "shoot", "reload", "ask", "wheel", "dusk", "wrap"]
const SIZES := [Vector2i(1280, 800), Vector2i(980, 700), Vector2i(700, 560)]


func _toast(main) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


## How many of the dead are on their way to a wall or at it (the wanderers at the edges of the map are not).
func _coming(sim) -> int:
	var n := 0
	for z in sim.zombies:
		if z.state == "approach" or z.state == "attack":
			n += 1
	return n


func _clear_toast(main) -> void:
	main.hud.toast_panel.visible = false
	main.hud.toast_label.text = ""
	main.coach._toast_text = ""


func _hold(codes: Array, down: bool) -> void:
	for code in codes:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


# ------------------------------------------------------------ which lesson --

func test_the_avatars_game_reads_the_avatars_lesson_and_the_old_yard_the_old_one() -> void:
	var main = Tut.avatar_game()
	await Tut.frames(main, 3)
	check(main.avatar_mode and main.tutorial, "the avatar's Orientation Day")
	var ids: Array = []
	for s in main.coach.steps:
		ids.append(String(s.id))
	eq(ids, IDS, "its steps")
	eq(Coach.steps_path(true), Coach.STEPS_PATH, "from tutorial.json")
	eq(main.coach.step_id(), "you", "it begins with who you are")
	check(main.hud.avatar_ui and main.hud.ammo_panel.visible, "the HUD is the avatar's (the gun's readout is up)")
	await Tut.leave(main)
	var old = Tut.game()
	await Tut.frames(old, 3)
	check(not old.avatar_mode, "the old yard's Orientation Day has no avatar")
	eq(old.coach.step_id(), "look", "and begins with looking around")
	eq(Coach.steps_path(false), Coach.CLASSIC_PATH, "from tutorial_classic.json")
	await Tut.leave(old)


func test_the_title_asks_for_the_avatars_lesson() -> void:
	var main = Tut.start({"title": true})
	await Tut.frames(main, 3)
	var picked: Array = []
	main.restart = func(meta): picked.append(meta)
	main.shell.start_orientation()
	eq(picked.size(), 1, "the title's Orientation Day begins a run")
	eq(picked[0], {"tutorial": true, "avatar": true}, "of the avatar's lesson")
	await Tut.leave(main)
	check(MainScript.wants_avatar(picked[0], false, true), "which the real game plays with Ruth")
	check(MainScript.wants_avatar({"tutorial": true, "step": 0}, false, true), "the --tutorial flag too (a real run has no other lesson)")



# ----------------------------------------------------------------- the lock --

func test_the_hands_are_never_locked_but_the_pages_and_the_map_wait_for_their_lesson() -> void:
	var main = Tut.avatar_game(1)
	await Tut.frames(main, 30)
	var coach = main.coach
	eq(coach.step_id(), "walk", "the lesson on walking")
	check(not coach.held and main.speed == 1, "the game runs, at normal speed")
	var me = main.sim.avatar.player()
	# the hands: the keys walk, and the wheel zooms
	var x0: float = me.x
	_hold([KEY_D], true)
	await Tut.frames(main, 8)
	_hold([KEY_D], false)
	check(me.x > x0 + 0.5, "D walks Ruth (%.2f to %.2f)" % [x0, me.x])
	var zoom_was: float = main.zoom_px
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 1.0
	main._unhandled_input(wheel)
	check(not is_equal_approx(main.zoom_px, zoom_was), "the wheel zooms")
	# the pages and the map and the fields view are for their own lessons
	for key in [KEY_J, KEY_N, KEY_G, KEY_V, KEY_C, KEY_E, KEY_L]:
		_clear_toast(main)
		main._key(key)
		eq(_toast(main), "Not yet: first walk six steps with W A S D.", "key %s is refused, gently, with what to do first" % OS.get_keycode_string(key))
	check(main.hud.jobs_screen == null and main.hud.build_screen == null and main.hud.scavenge_dialog == null and not main.fields and not main.wheel_ctl.is_open(), "and nothing opened (not the wheel either)")
	check(not main.sim.radio.alarm_on, "and the alarm was not rung")
	# a crew card is not for this lesson
	_clear_toast(main)
	Bot.card_click(main, "dez")
	check(main.selection == null, "Dez's card is refused")
	check(_toast(main).begins_with("Not yet: first walk"), "with the same goal")
	# the order keys and the right button are not there at all
	main._key(KEY_P)
	main._key(KEY_X)
	check(Bot.person(main, "hector").order == null, "P does nothing in avatar mode")
	await Tut.leave(main)


func test_the_wheel_and_the_lever_are_for_their_own_lessons_and_work_in_them() -> void:
	var main = Tut.avatar_game(IDS.find("wheel"))
	await Tut.frames(main, 12)
	var coach = main.coach
	eq(coach.step_id(), "wheel", "the lesson of the wheel")
	check(coach.would_allow("wheel") and not coach.would_allow("interact"), "the wheel is allowed in it, and E is not")
	check(Bot.selected(main, "dez"), "Dez is picked as it begins (the ring is for the one picked)")
	# hold C: the ring opens and the card says where to go next
	var me = main.sim.avatar.player()
	Bot.pointer_to(main, main._tile_to_screen(Vector2(me.x + 2.5, me.y + 1.5)))
	Bot.key(main, KEY_C, true)
	await Tut.frames(main, 3)
	check(main.wheel_ctl.is_open(), "C opens the ring in its lesson")
	check(coach.goal_label.text.to_lower().contains("hold here"), "and the card says where to go next: %s" % coach.goal_label.text)
	main.wheel_ctl.cancel()
	Bot.key(main, KEY_C, false)
	await Tut.leave(main)
	var lever = Tut.avatar_game(IDS.find("dusk"))
	await Tut.frames(lever, 12)
	check(lever.coach.would_allow("interact") and not lever.coach.would_allow("wheel"), "in the lesson of the gate E is allowed and the wheel is not")
	_clear_toast(lever)
	lever._key(KEY_G)
	check(_toast(lever).begins_with("Not yet: first walk to the gate lever"), "and G is refused, with what to do first: %s" % _toast(lever))
	await Tut.leave(lever)


# --------------------------------------------------------------- what it notes --

func test_the_coach_notes_what_the_players_own_person_has_done_when_a_step_begins() -> void:
	var main = Tut.avatar_game(2)
	await Tut.frames(main, 6)
	var me = main.sim.avatar.player()
	var base: Dictionary = main.coach.state.base
	check(base.has("mine"), "the player's shots and kills are noted")
	eq(int(base.mine.shots), int(me.stats.shots), "the shots")
	eq(int(base.mine.kills), int(me.stats.kills), "the kills")
	eq(int(base.news), int(main.sim.radio.latest_id()), "and how far the radio's log had got")
	await Tut.leave(main)


func test_what_the_radio_answers_reaches_the_coach_as_who_what_and_whether() -> void:
	var main = Tut.avatar_game(IDS.find("ask"))
	await Tut.frames(main, 6)
	var coach = main.coach
	eq(coach.step_id(), "ask", "the lesson on asking")
	var dez = Bot.person(main, "dez")
	var ana = Bot.person(main, "ana")
	Bot.card_click(main, "dez")
	main.hud.radio_verbs.buttons["come"].pressed.emit()
	await Tut.frames(main, 2)
	check(float(coach.state.events.get("radio_line:dez:come:ok", 0.0)) >= 1.0, "a yes is counted for Dez and the verb")
	# a refusal
	main.sim.medical.jobs.append({"healer": ana, "patient": Bot.person(main, "walt"), "kind": "bandage", "work": 0.0, "stand": null, "anchor": Vector2.ZERO})
	var r: Dictionary = main.sim.radio.request(ana, "come")
	check(not r.ok, "Ana refuses")
	await Tut.frames(main, 2)
	check(float(coach.state.events.get("radio_line:ana:come:no", 0.0)) >= 1.0, "and a refusal is counted, as one")
	await Tut.leave(main)


# ------------------------------------------------------------ every step starts --

func test_every_step_can_be_started_at_with_the_world_it_expects() -> void:
	for i in IDS.size():
		var main = Tut.avatar_game(i)
		await Tut.frames(main, 12)
		var coach = main.coach
		check(coach != null, "step %s: the coach is there" % IDS[i])
		if coach == null:
			await Tut.leave(main)
			continue
		eq(coach.step_id(), IDS[i], "step %d is %s" % [i, IDS[i]])
		eq(main.sim.player_id, "ruth", "%s: Ruth is the player" % IDS[i])
		check(coach.card.visible and coach.title_label.text != "", "%s: the card is up" % IDS[i])
		var jump: Dictionary = coach.step.get("jump", {})
		if jump.has("at"):
			var me = main.sim.avatar.player()
			near(me.x, float(jump.at[0]), 0.5, "%s: Ruth is where the step puts her (x)" % IDS[i])
			near(me.y, float(jump.at[1]), 0.5, "%s: and (y)" % IDS[i])
		if jump.has("day"):
			eq(main.sim.day, int(jump.day), "%s: the day" % IDS[i])
		if jump.has("hour"):
			near(main.sim.hour, float(jump.hour), 0.25, "%s: the hour" % IDS[i])
		eq(main.sim.over, "", "%s: not over" % IDS[i])
		await Tut.leave(main)


func test_the_steps_that_stage_something_do_it_when_they_begin() -> void:
	var shoot = Tut.avatar_game(IDS.find("shoot"))
	await Tut.frames(shoot, 6)
	var coming := 0
	for z in shoot.sim.zombies:
		if z.state == "approach":
			coming += 1
	eq(coming, 1, "Aim and shoot: a walker is coming")
	await Tut.leave(shoot)
	var reload = Tut.avatar_game(IDS.find("reload"))
	await Tut.frames(reload, 6)
	var me = reload.sim.avatar.player()
	check(int(me.mag) < int(me.gun.mag) and int(me.mag) >= 1, "Reload and put away: the gun is low (%d)" % me.mag)
	await Tut.leave(reload)
	var ask = Tut.avatar_game(IDS.find("ask"))
	await Tut.frames(ask, 6)
	var w: Dictionary = ask.sim.radio.willingness(Bot.person(ask, "ana"), "come")
	check(not w.ok and not w.hard, "Ask, do not order: Ana cannot come, and the push could change it (%s)" % w.why)
	check(ask.coach.held and ask.speed == 0, "and the game waits for the player (until Ana has been pushed)")
	await Tut.leave(ask)
	var dusk = Tut.avatar_game(IDS.find("dusk"))
	await Tut.frames(dusk, 6)
	check(dusk.sim.gate.active() and dusk.sim.scenario.gate_on, "The gate and the bell: the gate's real rules are on")
	check(dusk.sim.gate.held == "open" and dusk.sim.gate.wants_open(), "and the gate stands open, for the player to shut")
	near(dusk.sim.hour, 17.0, 0.25, "in the late afternoon")
	check(not dusk.sim.bell_rung and _coming(dusk.sim) == 0, "before the bell, with none of the dead on their way to a wall (the wanderers at the map's edges are not)")
	check(dusk.hud.gate_text() != "", "the clock has the gate's lamp (%s)" % dusk.hud.gate_text())
	check(not dusk.coach.speed_button.visible, "and no Speed up yet (the gate is open: first walk to the lever)")
	await Tut.leave(dusk)


## The step that brings its own afternoon does it when it BEGINS, as the lesson goes, not only when it is started at; the dead of the dusk come once,
## when the bell rings (not before), and the bell shuts a gate that was left open.
func test_the_lesson_of_the_gate_brings_its_afternoon_and_its_dead_by_itself() -> void:
	var main = Tut.avatar_game(IDS.find("wheel"))
	await Tut.frames(main, 6)
	var sim = main.sim
	check(not sim.gate.enabled and not sim.scenario.gate_on, "before the lesson of the gate the gate is the old shut wall")
	near(sim.hour, 7.6, 0.25, "in the morning")
	# the lesson of the wheel is passed by (the next lesson begins as the lesson goes on)
	main.coach._advance()
	await Tut.frames(main, 6)
	eq(main.coach.step_id(), "dusk", "the next lesson is the gate and the bell")
	near(sim.hour, 17.0, 0.25, "it brought the afternoon as it began")
	check(sim.gate.enabled and sim.gate.active() and sim.gate.held == "open", "and the gate, open")
	eq(_coming(sim), 0, "no dead on their way yet")
	# the bell is near: the gate is left open, and the bell rings
	sim.scenario.set_time(18.9, 1)
	var guard := 0
	while not sim.bell_rung and guard < 4000:
		guard += 1
		await Tut.frames(main, 4)
	check(sim.bell_rung, "the bell rang")
	await Tut.frames(main, 4)
	check(sim.scenario.has_fired("dusk") and sim.scenario.has_fired("more"), "and the dead of the dusk came, both groups")
	guard = 0
	while main.coach != null and main.coach.step_id() == "dusk" and guard < 4000:
		guard += 1
		await Tut.frames(main, 4)
	check(main.coach != null and main.coach.step_id() == "wrap", "the gate was shut by the bell, and the lesson is on its last card")
	eq(sim.gate.held, "", "(the bell's keeper shut it: nobody locked it)")
	near(sim.gate.open, 0.0, 0.001, "shut")
	check(_coming(sim) >= 7 and _coming(sim) <= 9, "(seven, with a wanderer or two: %d)" % _coming(sim))
	await Tut.leave(main)


# --------------------------------------------------------------------- skip --

## Skip is on every card but the last, is a visible control, and ends the lesson cleanly: the last card says it was skipped, and Keep playing here lets the
## game go on as a normal one (the lock lifted, the game let go, the scenario over and the nights real, the flag set), whichever step it was.
func test_skip_is_on_every_card_and_what_follows_is_a_normal_game() -> void:
	for i in IDS.size() - 1:
		var main = Tut.avatar_game(i)
		await Tut.frames(main, 8)
		var coach = main.coach
		check(coach != null and coach.skip_button.is_visible_in_tree() and coach.skip_button.text.begins_with("Skip"), "%s: Skip is there" % IDS[i])
		if coach == null:
			await Tut.leave(main)
			continue
		var rect: Rect2 = coach.skip_button.get_global_rect()
		check(Rect2(Vector2.ZERO, main._vp()).encloses(rect), "%s: and it is in the window (%s)" % [IDS[i], str(rect)])
		Prefs.set_flag("tutorial_done", false)
		coach.skip_button.pressed.emit()
		await Tut.frames(main, 4)
		eq(coach.phase, "wrap", "%s: Skip goes to the last card" % IDS[i])
		check(coach.skipped and coach.title_label.text == "Skipped", "%s: which says it was skipped" % IDS[i])
		check(coach.wrap_box.visible and not coach.skip_button.visible, "%s: and offers Start a real run, Replay and Keep playing here" % IDS[i])
		check(Prefs.flag("tutorial_done"), "%s: the flag is set" % IDS[i])
		coach.stay_button.pressed.emit()
		await Tut.frames(main, 4)
		check(main.coach == null, "%s: Keep playing here ends it" % IDS[i])
		var sim = main.sim
		check(sim.scenario.finished and not sim.scenario.coached, "%s: the scenario is over" % IDS[i])
		check(sim.waves.enabled and not sim.waves.scripted, "%s: the nights are real" % IDS[i])
		check(sim.gate.enabled and sim.gate.active(), "%s: and the gate is the real one" % IDS[i])
		check(main.speed > 0, "%s: the game runs again (speed %d)" % [IDS[i], main.speed])
		check(not main.hud.lock_allowed.is_valid(), "%s: the lock is lifted" % IDS[i])
		check(main._allows("alarm") and main._allows("gizmo", "post") and main._allows("wheel") and main._allows("interact"), "%s: every key works" % IDS[i])
		eq(sim.over, "", "%s: the run is not over" % IDS[i])
		await Tut.frames(main, 30)
		eq(sim.over, "", "%s: and goes on" % IDS[i])
		await Tut.leave(main)


## The Esc menu has Skip tutorial while the coach is up (and not on its last card, nor once the lesson is over): it closes the menu, which gives the
## speed back, and the coach goes to its last card.
func test_the_pause_menu_has_skip_tutorial_while_the_lesson_is_on() -> void:
	var main = Tut.avatar_game(IDS.find("reload"))
	await Tut.frames(main, 8)
	var coach = main.coach
	check(main.speed > 0 and not coach.held, "the game runs in the lesson of the reload")
	var speed_before: int = main.speed
	main.open_pause()
	await Tut.settle()
	var pause = main.shell.top()
	eq(pause.kind, "pause", "Esc opens the pause menu")
	check(pause.items.has("skip"), "it has Skip tutorial (%s)" % str(pause.items.keys()))
	var keys: Array = pause.items.keys()
	check(keys.find("skip") == keys.find("help") + 1 and keys.find("menu") == keys.find("skip") + 1, "between How to play and Main menu (%s)" % str(keys))
	eq(main.speed, 0, "the game waits while it is open")
	pause.items["skip"].pressed.emit()
	await Tut.frames(main, 4)
	check(not main.shell.is_open(), "the menu is gone")
	eq(coach.phase, "wrap", "the coach is on its last card")
	check(coach.skipped and coach.title_label.text == "Skipped", "which says it was skipped")
	check(main.speed == 0 and coach.held, "held for the card (the game waits for Start a real run, Replay or Keep playing here)")
	coach.stay_button.pressed.emit()
	await Tut.frames(main, 4)
	eq(main.speed, speed_before, "Keep playing here gives the game the speed it had")
	check(main.coach == null, "and the lesson is over")
	# once the lesson is over there is no line
	main.open_pause()
	await Tut.settle()
	check(not main.shell.top().items.has("skip"), "once the lesson is over the menu has no Skip tutorial")
	main.shell.top().items["resume"].pressed.emit()
	await Tut.leave(main)
	# the last card has none either (its own buttons are the way out)
	var wrap = Tut.avatar_game(IDS.size() - 1)
	await Tut.frames(wrap, 8)
	wrap.open_pause()
	await Tut.settle()
	check(not wrap.shell.top().items.has("skip"), "the last card: no Skip tutorial in the menu")
	wrap.shell.top().items["resume"].pressed.emit()
	await Tut.leave(wrap)


func test_every_step_that_points_at_something_finds_it_in_the_real_hud() -> void:
	for i in IDS.size():
		var main = Tut.avatar_game(i)
		await Tut.frames(main, 12)
		var coach = main.coach
		var entries: Array = coach.step.get("anchor", [])
		if not entries.is_empty() and coach.phase == "active":
			check(coach.target_name != "" and coach.target_rect.size.x > 0.0, "%s: it lights something (%s)" % [IDS[i], coach.target_name])
			var vp: Vector2 = main._vp()
			check(Rect2(Vector2.ZERO, vp).intersects(coach.target_rect), "%s: and it is in the window (%s)" % [IDS[i], str(coach.target_rect)])
		await Tut.leave(main)


# ------------------------------------------------------------------- the card --

## The person the player plays, as the card must not cover them: the figure and its YOU tag, in screen pixels.
func _figure(main) -> Rect2:
	var me = main.sim.avatar.player()
	var at: Vector2 = main.view_pos(me)
	var a: Vector2 = main._tile_to_screen(at + Vector2(-0.5, -1.9))
	var b: Vector2 = main._tile_to_screen(at + Vector2(0.5, 0.4))
	return Rect2(a, b - a).abs()


func test_the_card_never_covers_the_person_the_player_plays_or_what_it_points_at() -> void:
	for size in SIZES:
		for i in IDS.size():
			var main = Tut.avatar_game(i, size.x, size.y)
			await Tut.frames(main, 24)
			var coach = main.coach
			if coach == null:
				check(false, "%s at %s: the coach is there" % [IDS[i], str(size)])
				await Tut.leave(main)
				continue
			var card: Rect2 = coach._card_rect
			var vp: Vector2 = main._vp()
			check(Rect2(Vector2.ZERO, vp).encloses(card.grow(-1.0)), "%s at %s: the card is in the window (%s)" % [IDS[i], str(size), str(card)])
			var figure := _figure(main)
			check(not card.intersects(figure), "%s at %s: the card (%s) does not cover Ruth (%s)" % [IDS[i], str(size), str(card), str(figure)])
			var target: Rect2 = coach.target_rect
			if target.size.x > 0.0 and Rect2(Vector2.ZERO, vp).intersects(target):
				check(not card.intersects(target), "%s at %s: nor what it points at, %s (%s, the card %s)" % [IDS[i], str(size), coach.target_name, str(target), str(card)])
			await Tut.leave(main)
