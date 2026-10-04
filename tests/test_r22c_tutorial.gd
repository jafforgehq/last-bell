extends "res://tests/case.gd"
## Round 22, CONTROLS in Orientation Day (assets/data/tutorial.json, scripts/ui/coach.gd, tests/tutorial_bot.gd): the shooting step teaches "hold the right
## mouse button to aim, then click to shoot" and its card follows the player (climb, then aim, then "now click to shoot"); with the setting "Always
## aim at the mouse" it says what it always said; the bot plays it with real inputs (the right button, then the left). The data scan of the
## avatar's lesson is tests/test_tutorial_avatar_data.gd's.

const Tut := preload("res://tests/tutorial_kit.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const AimMode := preload("res://scripts/aim_mode.gd")


func _step(main, id: String) -> Dictionary:
	for s in main.coach.steps:
		if String(s.id) == id:
			return s
	return {}


func test_the_shooting_step_has_the_words_for_both_settings_and_they_are_short() -> void:
	var steps: Array = Coach.load_steps(Coach.steps_path(true))
	var shoot := {}
	for s in steps:
		if String(s.id) == "shoot":
			shoot = s
	check(not shoot.is_empty(), "the lesson has the step")
	var text := String(shoot.get("text", ""))
	check(text.contains("right mouse button") and text.contains("click to shoot"), "it teaches the right button, then the click: %s" % text)
	check(not text.contains("left button"), "and not the left button held")
	var old := String(shoot.get("text_always", ""))
	check(old.contains("left button") and old.contains("aim with the mouse"), "the old setting's words are the old ones: %s" % old)
	for words in [text, old]:
		var n: int = Coach.words(words)
		check(n >= 8 and n <= Coach.MAX_WORDS, "%d words" % n)
	var goals: Array = shoot.get("goals", [])
	check(goals.size() == 2, "two goals: aim, then click")
	var said := " ".join(PackedStringArray(goals.map(func(g): return String(g.get("text", "")))))
	check(said.contains("right mouse button") and said.contains("click to shoot"), "they say so: %s" % said)
	var goals_old: Array = shoot.get("goals_always", [])
	check(goals_old.size() == 1 and String(goals_old[0].text).contains("left button"), "and the old setting's goal is the old one")


func test_the_card_follows_the_player_from_the_ladder_to_the_aim_to_the_shot() -> void:
	var main = Tut.avatar_game(2)
	await Tut.frames(main, 4)
	eq(main.coach.step_id(), "shoot", "on the shooting step")
	var me = main.sim.avatar.player()
	check(main.coach.text_label.text.contains("right mouse button"), "the card teaches it: %s" % main.coach.text_label.text)
	check(main.coach.goal_label.text.to_lower().contains("ladder"), "first the ladder: %s" % main.coach.goal_label.text)
	me.x = Bot.DECK_AT.x
	me.y = Bot.DECK_AT.y
	main._sync_views()
	await Tut.frames(main, 4)
	check(main.sim.world.on_deck(me.x, me.y), "(on the walkway)")
	check(main.coach.goal_label.text.to_lower().contains("right mouse button"), "then the right button: %s" % main.coach.goal_label.text)
	Bot.aim_button(main, true)
	await Tut.frames(main, 4)
	check(main.coach.goal_label.text.to_lower().contains("click to shoot"), "once the right button is held: %s" % main.coach.goal_label.text)
	Bot.aim_button(main, false)
	await Tut.frames(main, 2)
	check(main.coach.goal_label.text.to_lower().contains("click to shoot"), "and it stays so, the aim having been learnt: %s" % main.coach.goal_label.text)
	await Tut.leave(main)


func test_shift_is_the_aim_too_for_the_lesson() -> void:
	var main = Tut.avatar_game(2)
	await Tut.frames(main, 4)
	var me = main.sim.avatar.player()
	me.x = Bot.DECK_AT.x
	me.y = Bot.DECK_AT.y
	main._sync_views()
	var ev := InputEventKey.new()
	ev.keycode = KEY_SHIFT
	ev.physical_keycode = KEY_SHIFT
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await Tut.frames(main, 4)
	check(main.coach.goal_label.text.to_lower().contains("click to shoot"), "Shift held counts as the aim: %s" % main.coach.goal_label.text)
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await Tut.leave(main)


func test_with_the_old_setting_the_card_says_the_old_things() -> void:
	var main = Tut.avatar_game(2)
	AimMode.set_mode("always")
	main.coach._card_key = ""
	await Tut.frames(main, 4)
	eq(main.coach.step_id(), "shoot", "on the shooting step")
	check(main.coach.text_label.text.contains("left button"), "the old words: %s" % main.coach.text_label.text)
	var me = main.sim.avatar.player()
	me.x = Bot.DECK_AT.x
	me.y = Bot.DECK_AT.y
	main._sync_views()
	await Tut.frames(main, 4)
	check(main.coach.goal_label.text.to_lower().contains("left button"), "and the old goal: %s" % main.coach.goal_label.text)
	await Tut.leave(main)


func test_the_bot_shoots_the_walker_with_the_right_button_then_the_left() -> void:
	var main = Tut.avatar_game(2)
	await Tut.frames(main, 3)
	var me = main.sim.avatar.player()
	var saw_aim := false
	var saw_fire_aiming := false
	# play the step frame by frame, watching the hands
	var guard := 0
	while main.coach != null and main.coach.step_id() == "shoot" and guard < 9000:
		guard += 1
		if main.coach.phase == "active" or main.coach.phase == "wait":
			if main.coach.phase == "wait":
				main._set_speed(3)    # (round 24: the key is Shift and 3 with an avatar)
			else:
				if not main.coach.held and main.speed != 1:
					main._set_speed(1)
				Bot.act(main, "shoot", {})
		main._process(1.0 / 30.0)
		if main.aim_held:
			saw_aim = true
		if main.firing and main.aim_held:
			saw_fire_aiming = true
		if guard % 4 == 0:
			await Engine.get_main_loop().process_frame
	Bot.release_keys()
	Bot.trigger(main, false)
	Bot.aim_button(main, false)
	check(guard < 9000, "the step was finished")
	check(saw_aim, "the bot held the right button")
	check(saw_fire_aiming, "and fired with the left while it was held")
	check(int(me.stats.kills) >= 1, "her own shot put the walker down")
	await Tut.leave(main)


func test_the_bot_plays_the_shooting_step_with_the_old_setting_by_the_left_button_alone() -> void:
	var main = Tut.avatar_game(2)
	AimMode.set_mode("always")
	await Tut.frames(main, 3)
	var me = main.sim.avatar.player()
	var r: Dictionary = await Bot.play(main, "reload", 400000, true)
	eq(r.stuck, "", "never stuck")
	check(int(me.stats.kills) >= 1, "the shot put a walker down (%d)" % me.stats.kills)
	check(not main.aim_held, "with no right button")
	await Tut.leave(main)
