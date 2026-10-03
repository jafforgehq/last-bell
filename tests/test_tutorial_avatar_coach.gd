extends "res://tests/case.gd"
## The coach on the real game scene as the avatar's Orientation Day: which lesson it reads, what its soft lock lets through in avatar
## mode (the hands always; the pages and the map only when a step teaches them), what it notes of the radio and of the player's own
## shots, that every step can be started at (`--tutorial=N`) with the world as it expects, and that its card never covers the person
## the player plays or the thing it points at, in a window of 1280 x 800 and in one of 700 x 560.

const Tut := preload("res://tests/tutorial_kit.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const MainScript := preload("res://scripts/main.gd")

const IDS := ["you", "walk", "shoot", "reload", "crew", "come", "refusal", "news", "map", "alarm", "dusk", "jobs", "wrap"]
const SIZES := [Vector2i(1280, 800), Vector2i(980, 700), Vector2i(700, 560)]


func _toast(main) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


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


func test_the_title_asks_for_the_avatars_lesson_and_noavatar_for_the_old_yards() -> void:
	var main = Tut.start({"title": true})
	await Tut.frames(main, 3)
	var picked: Array = []
	main.restart = func(meta): picked.append(meta)
	main.shell.start_orientation()
	eq(picked.size(), 1, "the title's Orientation Day begins a run")
	eq(picked[0], {"tutorial": true, "avatar": true}, "of the avatar's lesson")
	await Tut.leave(main)
	check(MainScript.wants_avatar([], picked[0], false, true, true), "which the real game plays with Ruth")
	check(not MainScript.wants_avatar(["--noavatar"], picked[0], false, true, true), "and --noavatar with the old yard's")
	check(MainScript.wants_avatar([], {"tutorial": true, "step": 0}, false, true, true), "the --tutorial flag too")



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
	for key in [KEY_J, KEY_N, KEY_G, KEY_V]:
		_clear_toast(main)
		main._key(key)
		eq(_toast(main), "Not yet: first walk six steps with W A S D.", "key %s is refused, gently, with what to do first" % OS.get_keycode_string(key))
	check(main.hud.jobs_screen == null and main.hud.build_screen == null and main.hud.scavenge_dialog == null and not main.fields, "and nothing opened")
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


func test_the_lessons_that_need_a_page_let_it_open() -> void:
	var main = Tut.avatar_game(Coach.load_steps(Coach.STEPS_PATH).size() - 2)
	await Tut.frames(main, 12)
	eq(main.coach.step_id(), "jobs", "the duty roster's lesson")
	main._key(KEY_J)
	await Tut.frames(main, 4)
	check(main.hud.jobs_screen != null, "J opens the page")
	main.hud.jobs_screen.close_button.pressed.emit()
	await Tut.leave(main)
	var map = Tut.avatar_game(IDS.find("map"))
	await Tut.frames(map, 12)
	eq(map.coach.step_id(), "map", "the map's lesson")
	map._key(KEY_G)
	await Tut.frames(map, 4)
	check(map.hud.town_board_open(), "G opens the Town Board (the avatar's lesson is played in a town)")
	await Tut.leave(map)


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
	var main = Tut.avatar_game(5)
	await Tut.frames(main, 6)
	var coach = main.coach
	eq(coach.step_id(), "come", "the lesson on asking")
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
	check(int(me.mag) < int(me.gun.mag) and int(me.mag) >= 1, "Reload and swing: the gun is low (%d)" % me.mag)
	await Tut.leave(reload)
	var refusal = Tut.avatar_game(IDS.find("refusal"))
	await Tut.frames(refusal, 6)
	var w: Dictionary = refusal.sim.radio.willingness(Bot.person(refusal, "ana"), "come")
	check(not w.ok and not w.hard, "A refusal: Ana cannot come, and the push could change it (%s)" % w.why)
	check(refusal.coach.held and refusal.speed == 0, "and the game waits for the player")
	await Tut.leave(refusal)
	var news = Tut.avatar_game(IDS.find("news"))
	await Tut.frames(news, 6)
	eq(news.sim.radio.open_calls().size(), 1, "News and calls: a call waits")
	check(news.coach.held and news.speed == 0, "and the game waits for the answer")
	await Tut.leave(news)


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
