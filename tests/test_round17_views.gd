extends "res://tests/case.gd"
## The seams of round 17's views that the independent review found (the review's numbers in the names): the reasons why someone
## was left out of a trip are SEEN (the road's overlay, the report, a toast in the colony view when the trip cannot begin: #1), a
## story card raised on a trip waits for the report and then holds the game (#6), the cursor is the arrow while the report is up
## (#13), no save in a place and the pause menu says so (#7), the call card counts in the place's own pace (#8), Insist is only
## offered where it can change something and a stale answer goes (#11, #12), the News the player has read is read everywhere
## (#13). The rules these lean on are tests/test_radio.gd's, tests/test_raid_run.gd's, tests/test_place_flow.gd's and
## tests/test_raid_scene.gd's.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const RadioVerbs := preload("res://scripts/ui/radio_verbs.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const STEP := 1.0 / 30.0
const SENTINEL := "user://test_round17_views_save.json"


## The real game (a small start, Ruth the avatar) with its own frames off and the old stubbed site.
func _main(crew: int = 3) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew, "avatar": true})
	main.raid_stub = true
	main.sim.waves.enabled = false
	return main


func _leave(main: Node) -> void:
	await TutorialKit.leave(main)


func _tick(scene: Node, seconds: float, dt: float = STEP) -> void:
	for i in int(seconds / dt):
		scene.tick(dt)


## A road (there or home) to its end.
func _drive_road(scene: Node, which: String) -> void:
	var frames := 0
	while scene.phase == which and frames < 5000:
		scene.tick(1.0 / 60.0)
		frames += 1


## Everyone alive of the squad into the exit, to leave the place.
func _leave_place(scene: Node) -> void:
	var lead = scene.leader()
	var spot: Vector2 = scene.site.exit.get_center()
	lead.x = spot.x + 7.0
	lead.path = []
	_tick(scene, 0.2)
	for p in scene.run.squad:
		if not p.dead and not p.downed:
			p.x = spot.x + randf_range(-0.8, 0.8)
			p.y = spot.y + randf_range(-0.6, 0.6)
			p.path = []
	_tick(scene, 0.5)


# ------------------------------------------------------------ #1: refusals seen --

func test_who_was_left_out_and_why_is_on_the_road_overlay_and_in_the_report() -> void:
	var main := _main()
	var sim = main.sim
	var dez = sim.people[1]
	dez.bleeding = 2.0
	var scene = main.open_raid([dez, sim.people[2]], sim.town.place("houses"), "", 1.0, Callable())
	check(scene != null, "the trip opens without Dez")
	if scene == null:
		await _leave(main)
		return
	var lines: Array = scene.flow.refusals
	eq(lines.size(), 1, "the flow keeps one line for the one who stayed")
	check(String(lines[0]).begins_with("Dez"), "which names them: '%s'" % str(lines))
	var h = scene.hud_layer
	check(h.road_panel.visible, "the road's overlay is up")
	eq(h.road_refusals, lines, "its list of the left out is that line")
	var labels: Array = h.road_refusal_box.get_children()
	eq(labels.size(), 1, "one label for it")
	check(labels[0].visible and labels[0].text == String(lines[0]), "reading the reason in words")
	check(labels[0].get_theme_font_size("font_size") >= 12, "not under 12 px")
	eq(labels[0].get_theme_color("font_color"), Hud.WARN, "in amber")
	await TutorialKit.settle()
	var bar_end: float = h.road_bar.get_global_rect().end.y
	check(labels[0].get_global_rect().position.y >= bar_end - 0.5, "under the progress bar")
	check(h.road_panel.get_global_rect().encloses(labels[0].get_global_rect()), "and inside the window")
	# and again in the report
	_drive_road(scene, "road_there")
	_leave_place(scene)
	_drive_road(scene, "road_home")
	eq(scene.phase, "report", "the report")
	check(h.end_rows.has("stayed"), "the report has a line for who stayed")
	if h.end_rows.has("stayed"):
		check(String(h.end_rows.stayed.text).begins_with("Dez"), "Dez's: '%s'" % h.end_rows.stayed.text)
		check(h.end_rows.stayed.get_theme_font_size("font_size") >= 12, "readable")
	scene.go_home()
	await _leave(main)


func test_the_lists_of_the_left_out_fit_the_window_on_the_road_and_in_the_report_even_in_the_smallest() -> void:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true}, 700, 560)
	main.raid_stub = true
	var sim = main.sim
	sim.waves.enabled = false
	sim.people[1].bleeding = 2.0
	# four chosen, one cannot, and one of the three left does not fit on foot: two lines
	var scene = main.open_raid([sim.people[1], sim.people[2], sim.people[3], sim.people[4]], sim.town.place("houses"), "", 1.0, Callable())
	check(scene != null, "the trip opens")
	if scene == null:
		await _leave(main)
		return
	var h = scene.hud_layer
	eq(scene.flow.refusals.size(), 2, "two were left out: %s" % str(scene.flow.refusals))
	await TutorialKit.settle()
	var win := Rect2(Vector2.ZERO, Vector2(700, 560))
	for l in h.road_refusal_box.get_children():
		check(win.encloses(l.get_global_rect()), "the line fits the window: %s in %s" % [str(l.get_global_rect()), str(win)])
		check(l.get_theme_font_size("font_size") >= 12, "and is 12 px or more")
	check(win.encloses(h.road_hint_label.get_global_rect()), "and what is under it still fits")
	check(win.encloses(h.road_title_label.get_global_rect()), "as does the title above")
	var last_bottom: float = h.road_refusal_box.get_global_rect().end.y
	check(h.road_clock_label.get_global_rect().position.y >= last_bottom - 0.5, "the clock is under the list, not over it")
	_drive_road(scene, "road_there")
	_leave_place(scene)
	_drive_road(scene, "road_home")
	await TutorialKit.settle()
	check(h.end_card.visible and win.encloses(h.end_panel.get_global_rect()), "the report fits the window with the extra row: %s" % str(h.end_panel.get_global_rect()))
	scene.go_home()
	await _leave(main)


func test_a_trip_where_everyone_came_has_no_list_of_the_left_out() -> void:
	var main := _main()
	var sim = main.sim
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	eq(scene.flow.refusals, [], "nobody was left out")
	eq(scene.hud_layer.road_refusal_box.get_child_count(), 0, "so the overlay has no line for it")
	_drive_road(scene, "road_there")
	_leave_place(scene)
	_drive_road(scene, "road_home")
	check(not scene.hud_layer.end_rows.has("stayed"), "and the report none")
	scene.go_home()
	await _leave(main)


func test_a_trip_that_cannot_begin_says_who_was_left_out_in_the_colony_view() -> void:
	var main := _main()
	var sim = main.sim
	var dez = sim.people[1]
	dez.bleeding = 2.0
	sim.minutes = 21.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	var scene = main.open_raid([dez, sim.people[2]], sim.town.place("houses"), "", 1.0, Callable())
	check(scene == null and not main.raid_open(), "no trip after dark")
	check(main.hud.visible and main.hud.toast_panel.visible, "the toast is on the HUD that shows")
	var text: String = main.hud.toast_label.text
	check(text.contains("dark"), "it says why there is no trip: '%s'" % text)
	check(text.contains("Dez"), "and who would have stayed: '%s'" % text)
	await _leave(main)


# --------------------------------------------- #6: a card raised on a trip waits --

func test_a_story_card_raised_on_a_trip_waits_and_the_game_stays_paused_after_the_report() -> void:
	var main := _main()
	var sim = main.sim
	sim.storyteller.enabled = true
	main.speed = 1
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(scene, "road_there")
	check(sim.storyteller.force("stranger"), "a stranger's card is raised in the place")
	_tick(scene, 1.0)
	await TutorialKit.settle()
	check(main.story_ui.radio == null and not sim.storyteller.pending().is_empty(), "it is pending and not up while the place is played")
	_leave_place(scene)
	_drive_road(scene, "road_home")
	eq(scene.phase, "report", "the report")
	await TutorialKit.settle()
	check(main.story_ui.radio == null, "the card does not open over the report")
	eq(main.speed, 0, "the rules wait under the report")
	scene.go_home()
	await TutorialKit.settle()
	check(main.story_ui.radio != null, "the card is up when the colony is given back")
	eq(main.speed, 0, "and the game is paused until it is answered")
	check(not sim.storyteller.pending().is_empty(), "(it is still pending)")
	main.story_ui.radio._choose(0)
	await TutorialKit.settle()
	eq(main.speed, 1, "the answer gives the speed back as it was before the trip")
	await _leave(main)


func test_a_card_raised_on_a_trip_that_began_paused_leaves_the_game_paused() -> void:
	var main := _main()
	var sim = main.sim
	sim.storyteller.enabled = true
	main.speed = 0
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(scene, "road_there")
	sim.storyteller.force("stranger")
	_tick(scene, 1.0)
	_leave_place(scene)
	_drive_road(scene, "road_home")
	scene.go_home()
	await TutorialKit.settle()
	eq(main.speed, 0, "paused as it was")
	check(main.story_ui.radio != null, "and the card is up")
	main.story_ui.radio._choose(0)
	await TutorialKit.settle()
	eq(main.speed, 0, "and paused after the answer, as the player left it")
	await _leave(main)


# ----------------------------------------------------- #13: the cursor, the report --

func test_the_cursor_is_the_arrow_while_the_report_is_up() -> void:
	var main := _main()
	var sim = main.sim
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(scene, "road_there")
	check(main.raid_open(), "in the place the scene has the pointer")
	_leave_place(scene)
	_drive_road(scene, "road_home")
	eq(scene.phase, "report", "the report")
	check(not main.raid_open(), "(the colony's view is back under it)")
	check(main.avatar_hands_off(), "the avatar's hands are off while the report is up")
	eq(main.pointer_mode(), Input.MOUSE_MODE_VISIBLE, "so the pointer is the system's arrow, over the HUD or the world")
	main.mouse_screen = Vector2(300, 300)
	main.over_hud = false
	eq(main.pointer_mode(), Input.MOUSE_MODE_VISIBLE, "even over the bare world")
	scene.go_home()
	await TutorialKit.frames(main, 2)
	check(not main.avatar_hands_off(), "the report gone, the hands are the avatar's again")
	eq(main.pointer_mode(), Input.MOUSE_MODE_HIDDEN, "and the crosshair replaces the arrow over the world")
	await _leave(main)


# ------------------------------------------------------------------ #7: no save out --

func test_the_game_does_not_save_in_a_place_and_the_pause_menu_says_so() -> void:
	var main := _main()
	var sim = main.sim
	# (the tests' own save file: the real quick save is never touched)
	main.tutorial_save_path = SENTINEL
	main.tutorial = true
	var f := FileAccess.open(SENTINEL, FileAccess.WRITE)
	f.store_string("untouched")
	f.close()
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(scene, "road_there")
	check(not main.quick_save(), "no quick save while a trip is up")
	eq(FileAccess.get_file_as_string(SENTINEL), "untouched", "nothing was written")
	eq(scene.hud_layer.toast_label.text, "Not while you are out", "and the place's own HUD says so")
	check(scene.hud_layer.toast_panel.visible, "where it can be seen")
	# the pause menu in the place: Save is greyed with the reason
	main.open_pause()
	var pause = main.shell.top()
	eq(String(pause.kind), "pause", "the pause menu is up over the place")
	var save: Button = pause.items["save"]
	check(save.disabled, "its Save line is off")
	var sub: Label = save.get_meta("sub")
	check(sub.text.contains("Not while you are out"), "with the reason: '%s'" % sub.text)
	# a press that gets through anyway (a key, a click on a greyed line) is refused too
	check(not main.shell.save_game(), "and the shell's own Save refuses")
	eq(FileAccess.get_file_as_string(SENTINEL), "untouched", "still nothing written")
	pause.close()
	scene.free()
	# at the base it saves
	check(main.quick_save(), "back at the base the quick save is written")
	check(FileAccess.get_file_as_string(SENTINEL) != "untouched", "to the file")
	main.tutorial = false
	main.open_pause()
	var pause2 = main.shell.top()
	check(not pause2.items["save"].disabled, "and the pause menu's Save is on again")
	pause2.close()
	await _leave(main)


# -------------------------------------------------------- #8: the call card's pace --

func test_a_call_counts_down_at_the_pace_of_the_place_not_the_yards() -> void:
	var main := _main()
	var sim = main.sim
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(scene, "road_there")
	eq(scene.phase, "place", "in the place")
	var id: int = sim.radio.raise_call("attack", "The east wall is under attack", "Three at the boards", [{"id": "hold", "label": "Hold"}, {"id": "help", "label": "Send help"}], "hold", 30.0)
	var e: Dictionary = sim.radio._entry(id)
	near(RadioKit.left_seconds(sim.radio, e, 1.0), 10.0, 0.5, "in the yard at the normal speed a half hour is ten seconds")
	near(RadioKit.left_seconds(sim.radio, e, 3.0), 3.33, 0.2, "at the top speed three and a bit")
	near(RadioKit.left_seconds(sim.radio, e, 1.0 / 3.0), 30.0, 1.0, "in a place, a third of that rate, thirty seconds")
	near(RadioKit.left_seconds(sim.radio, e, 2), 5.0, 0.3, "(a whole number of speed still works)")
	near(RadioKit.total_seconds(sim.radio, e, 1.0 / 3.0), 30.0, 1.0, "the whole wait too")
	scene.hud_layer.refresh()
	var card = scene.hud_layer.call_card
	check(card.visible, "the call card is up in the place")
	var left: float = card.view.seconds_left()
	check(left > 28.0 and left <= 30.5, "it says about thirty seconds, not ten: %.1f" % left)
	# a minute of the place is an hour of the day: ten place seconds take ten game minutes off the call
	_tick(scene, 10.0)
	scene.hud_layer.refresh()
	var later: float = card.view.seconds_left()
	near(left - later, 10.0, 1.5, "ten seconds of the place take ten seconds off it: %.1f to %.1f" % [left, later])
	scene.hud_layer.open_news(true)
	var news = scene.hud_layer.news_panel
	check(news.call_views.size() == 1, "the News panel has it as an open call")
	if news.call_views.size() == 1:
		near(news.call_views[0].seconds_left(), later, 1.5, "and its countdown is the same")
	scene.free()
	await _leave(main)


# -------------------------------------------------- #11, #12: the verbs' answer line --

## A radio that is asked and refuses as a place does before the radio is asked at all: the willingness says nothing is wrong, the
## answer says "hard".
class FakeRadio:
	extends RefCounted
	const VERBS := ["come", "hold", "cover", "search", "back", "post"]
	var answer: Dictionary = {}

	func verb_name(verb: String) -> String:
		return verb.capitalize()

	func willingness(_contact, _verb: String) -> Dictionary:
		return {"ok": true, "why": "", "line": "On it.", "delay_s": 0.5, "tone": "willing", "hard": false}

	func request(_contact, _verb: String, _args: Dictionary = {}) -> Dictionary:
		return answer.duplicate()

	func leader():
		return null


func _verbs(ctx: Dictionary, radio) -> Control:
	var v := RadioVerbs.new()
	ctx.hud.add_child(v)
	v.setup(ctx.hud, func(): return radio, {"place": true})
	v.set_contact(Kit.person(ctx, "dez"))
	return v


func test_insist_is_not_offered_on_a_refusal_the_answer_calls_hard() -> void:
	var ctx := Kit.build(1280, 800)
	var radio := FakeRadio.new()
	var v := _verbs(ctx, radio)
	radio.answer = {"ok": false, "line": "", "why": "Already searched", "delay_s": 0.0, "tone": "refused", "insisted": false, "hard": true}
	v.press("search")
	check(bool(v.last.hard), "the answer says it is hard")
	check(not v.insist_button.visible, "so there is no Insist to press")
	eq(v.reply.text, "Already searched", "the reason shows")
	# an answer that a push can change is offered one
	radio.answer = {"ok": false, "line": "", "why": "Dez: bleeding, can't come", "delay_s": 0.0, "tone": "refused", "insisted": false, "hard": false}
	v.press("come")
	check(not bool(v.last.hard) and v.insist_button.visible, "a soft refusal still has Insist")
	# an answer with no word on it (a radio that does not say) is judged by the willingness as before
	radio.answer = {"ok": false, "line": "", "why": "Dez: busy", "delay_s": 0.0, "tone": "refused", "insisted": false}
	v.press("hold")
	check(v.insist_button.visible, "no 'hard' in it: the radio's willingness (not hard) decides, as before")
	Kit.free_all(ctx)


func test_in_a_place_insist_is_not_offered_for_what_the_place_itself_refuses() -> void:
	var main := _main()
	var sim = main.sim
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(scene, "road_there")
	eq(scene.phase, "place", "in the place")
	var dez = scene.squad_contacts()[0]
	scene.select_contact("squad", dez)
	var h = scene.hud_layer
	var v = h.radio_verbs
	# a thing that was searched already
	var c: Dictionary = scene.run.containers[0]
	c["looted"] = true
	var r: Dictionary = scene.squad_request(dez, "search", {"at": Vector2(c.pos)})
	check(not bool(r.ok) and bool(r.get("hard", false)), "'%s' is a hard refusal: %s" % [String(r.get("why", "")), str(r)])
	# nothing under the pointer to search (the verbs ask for what the pointer is on)
	for k in scene.run.containers:
		k["looted"] = true
	r = v.press("search")
	check(not bool(r.ok), "the radio says no: %s" % str(r))
	check(bool(v.last.hard), "'%s' is hard" % String(v.last.why))
	check(not v.insist_button.visible, "so there is no Insist for it")
	# a soft one (Dez bleeding) still has it
	dez.bleeding = 3.0
	r = v.press("come")
	check(not bool(r.ok) and not bool(v.last.hard) and v.insist_button.visible, "a bleeding man's refusal can be insisted on: %s" % str(v.last))
	scene.free()
	await _leave(main)


func test_the_answer_that_no_longer_matches_the_contact_goes_and_the_reason_takes_its_place() -> void:
	var ctx := Kit.build(1280, 800)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.avatar.set_player("ruth")
	var dez = Kit.person(ctx, "dez")
	Kit.update(ctx)
	Kit.select(ctx, dez)
	Kit.update(ctx)
	var v = ctx.hud.radio_verbs
	check(v.contact == dez, "Dez is the contact")
	var r: Dictionary = v.press("come")
	check(bool(r.ok), "he agrees: %s" % str(r))
	check(v.reply.text.begins_with("Dez:"), "his line is up: '%s'" % v.reply.text)
	# the request has its delay: until it takes effect the line stays
	Kit.update(ctx)
	check(v.reply.text.begins_with("Dez:"), "kept while he is on his way")
	sim.radio.tick(10.0)
	eq(String(dez.stance), "follow", "he follows now")
	Kit.update(ctx)
	check(v.reply.text.begins_with("Dez:"), "kept while he does it")
	# he is sent back to his work (the stance ends): the line no longer says what he does
	sim.radio.clear_stance(dez)
	Kit.update(ctx)
	check(v.last.is_empty() and not v.reply.text.begins_with("Dez:"), "gone once the stance is: '%s'" % v.reply.text)
	# and when he is down all the buttons are off and the reason is what it says
	v.press("come")
	sim.radio.tick(10.0)
	dez.downed = true
	dez.hp = 0.0
	Kit.update(ctx)
	check(v.last.is_empty(), "downed: no stale answer")
	check(v.reply.text.to_lower().contains("down"), "the reason is: '%s'" % v.reply.text)
	for verb in v.buttons:
		check(v.buttons[verb].disabled, "%s is off" % verb)
	Kit.free_all(ctx)


# ------------------------------------------------------------- #13: News is shared --

func test_the_news_read_in_the_place_is_read_in_the_yards_panel_too() -> void:
	var main := _main()
	var sim = main.sim
	sim.radio.log_news("story", "A voice on the radio", "")
	sim.radio.log_news("recruit", "Hector has joined the crew", "")
	await TutorialKit.frames(main, 2)
	var yard = main.hud.news_panel
	check(yard.unread() >= 2, "in the yard two lines are unread: %d" % yard.unread())
	var scene = main.open_raid([sim.people[1]], sim.town.place("houses"), "", 1.0, Callable())
	_drive_road(scene, "road_there")
	var place = scene.hud_layer.news_panel
	check(place.unread() >= 2, "and in the place's panel too")
	scene.hud_layer.open_news(true)
	scene.hud_layer.open_news(false)
	eq(place.unread(), 0, "read in the place")
	eq(yard.unread(), 0, "and read in the yard's panel as well")
	sim.radio.log_news("alarm", "Call to arms", "")
	eq(yard.unread(), 1, "a new line is unread for both")
	eq(place.unread(), 1, "(the same one)")
	scene.free()
	await _leave(main)
