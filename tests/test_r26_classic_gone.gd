extends "res://tests/case.gd"
## Round 26: the classic game (no avatar, the old yard) is gone for players. A real run is always an avatar game and never six people (no
## flag or choice changes that), the New game screen has no Full crew, and a save from before (no player, or a Full crew run with no town)
## loads as an avatar game and says so, with a Map page that says there is no town. The simulation's own no-player mode, which the harness
## and the golden tests run on, is not touched (tests/test_nights_regression.gd and test_round20_noavatar.gd pin it).

const Tut := preload("res://tests/tutorial_kit.gd")
const Kit := preload("res://tests/hud_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const MenuFakes := preload("res://tests/menu_fakes.gd")
const Main := preload("res://scripts/main.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Prefs := preload("res://scripts/prefs.gd")
const MapPage := preload("res://scripts/ui/map_page.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")

const OLD_SAVE := "user://test_r26c_old_save.json"
const OLD_LESSON := "user://test_r26c_old_lesson.json"


## A classic game of `crew` people (the simulation's no-player mode: nobody is the player) a little way into day 1, saved as the old
## game would have saved it. `ruth_gone` leaves Ruth dead in it.
func _write_old_save(crew: int, ruth_gone: bool = false) -> void:
	var g := Helpers.make(3, 1, crew)
	var sim = g.sim
	Helpers.run(sim, 6.0)
	if ruth_gone:
		for p in sim.people:
			if p.id == "ruth":
				sim.medical.kill(p, "lost")
	eq(sim.player_id, "", "(the old save has no player)")
	check(SaveGame.write(sim, OLD_SAVE), "(the old save is written)")
	g.world.free()


func _trash(path: String) -> void:
	if FileAccess.file_exists(path):
		OS.move_to_trash(ProjectSettings.globalize_path(path))


func test_a_real_run_is_always_an_avatar_game_of_three_to_five() -> void:
	# a real run: the game's own scene (the tree's current scene), whatever its choice or the command line says
	for run in [{}, {"crew": 6}, {"crew": 3}, {"avatar": false}, {"tutorial": true}, {"load": "user://x.json"}]:
		check(Main.wants_avatar(run, false, true), "a real run of %s is an avatar game" % str(run))
	check(not Main.wants_avatar({}, true, true), "(the title's yard is nobody's)")
	eq(Main.start_crew({}, true), 5, "a real run with no crew in its choice is the five of the New game screen")
	eq(Main.start_crew({"crew": 6}, true), 5, "and never six")
	eq(Main.start_crew({"crew": 3}, true), 3, "a small crew stays small")
	eq(Main.start_crew({}, false), 6, "(a test's scene, a screenshot's or the title's yard with none are the classic six)")
	# a test's helper scene is the no-player mode unless its run says, or the tests-only switch is set
	check(not Main.wants_avatar({}, false, false), "a test's scene has none by default")
	check(Main.wants_avatar({"avatar": true}, false, false), "unless it asks")
	Main.avatar_for_tests = true
	check(Main.wants_avatar({}, false, false) and not Main.wants_avatar({"avatar": false}, false, false), "the tests-only switch changes what it does when its run says nothing")
	Main.avatar_for_tests = false
	# (the flag is gone from the code: nothing in the game reads the command line for it)
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	check(not source.contains("\"--noavatar\""), "main.gd does not read --noavatar")


func test_the_new_game_screen_has_no_full_crew() -> void:
	var ctx := MenuFakes.build(1280, 800)
	Prefs.set_value("ui", "crew", 6)    # (a six remembered from the days of the full crew)
	var screen = ctx.shell.open_new_game()
	await Kit.settle()
	eq(screen.CREWS, [3, 5], "two crews to choose from")
	eq(screen.crew_cards.size(), 2, "two cards")
	eq(screen.crew, 5, "a remembered six is the usual five")
	var words: Array = []
	for card in screen.crew_cards:
		words.append_array(Kit.texts(card))
	words.append(screen.crew_facts_label.text)
	var all := " ".join(PackedStringArray(words)).to_lower()
	check(all.contains("small crew (3)") and all.contains("crew of five"), "the small crew and the crew of five are there: %s" % all)
	check(not all.contains("full crew") and not all.contains("no avatar") and not all.contains("plays as before") and not all.contains("classic"), "and nothing of the classic game: %s" % all)
	Kit.click_on(screen.start_button)
	eq(ctx.main.last("start_run")[3], 5, "Start asks for five")
	MenuFakes.free_all(ctx)


func test_an_old_save_with_no_player_loads_as_an_avatar_game_and_goes_on() -> void:
	_write_old_save(6)
	var main = Tut.start({"load": OLD_SAVE, "avatar": true})    # (a test's scene asks for what the real game's scene always does)
	check(not main.load_failed, "the save loaded")
	eq(main.sim.player_id, "ruth", "Ruth is the player now")
	check(main.avatar_mode and main.hud.avatar_ui, "and the yard and the HUD are in avatar mode")
	check(main.sim.people.size() == 6 and not main.sim.recruits.small, "of the same crew of six, with no town")
	await Tut.frames(main, 2)
	check(main.hud.toast_panel.visible and main.hud.toast_label.text == "Old save: you are now Ruth", "the toast tells the player: '%s'" % main.hud.toast_label.text)
	# it goes on through a dusk and a night with the avatar's rules (nothing breaks), and a second save of it keeps the player
	main.sim.storyteller.enabled = false
	main.sim.minutes = 17.0 * 60.0
	await Tut.frames(main, 700)
	check(main.sim.day >= 1 and main.sim.player_id == "ruth", "it plays on: day %d, %s" % [main.sim.day, main.sim.player_id])
	check(SaveGame.write(main.sim, OLD_SAVE), "(saved again)")
	check(Main.save_has_player(SaveGame.read(OLD_SAVE)), "the new save has a player")
	await Tut.leave(main)
	var again = Tut.start({"load": OLD_SAVE, "avatar": true})
	eq(again.sim.player_id, "ruth", "and it loads with the same one, with no toast about an old save")
	await Tut.frames(again, 2)
	check(not (again.hud.toast_panel.visible and again.hud.toast_label.text.begins_with("Old save")), "no toast")
	await Tut.leave(again)
	# the no-avatar fixture of a test's scene (what the old game's tests run on) does not turn a save into an avatar game
	_write_old_save(6)
	var classic = Tut.start({"load": OLD_SAVE})
	eq(classic.sim.player_id, "", "a test's scene that does not ask keeps the save as it was")
	await Tut.leave(classic)
	# without Ruth (she died in it) the first of the living takes over
	_write_old_save(6, true)
	var heir = Tut.start({"load": OLD_SAVE, "avatar": true})
	check(heir.sim.player_id != "" and heir.sim.player_id != "ruth", "with Ruth gone the first living person leads: %s" % heir.sim.player_id)
	check(not heir.sim.avatar.player().dead, "and they are alive")
	await Tut.frames(heir, 2)
	check(heir.hud.toast_label.text.begins_with("Old save: you are now ") and not heir.hud.toast_label.text.contains("Ruth"), "the toast names them: '%s'" % heir.hud.toast_label.text)
	await Tut.leave(heir)
	_trash(OLD_SAVE)


func test_the_map_page_of_a_save_with_no_town_says_so() -> void:
	_write_old_save(6)
	var main = Tut.start({"load": OLD_SAVE, "avatar": true})
	check(not main.sim.town.on, "(an old Full crew save has no town)")
	await Tut.frames(main, 3)
	main.page_key("map")    # G
	await Tut.settle()
	eq(main.hud.radio_page(), "map", "G opens the Map page")
	var page = main.hud.radio_panel.page_node("map")
	check(page.message_label.visible and page.message_label.text == MapPage.NO_TOWN, "which says: '%s'" % page.message_label.text)
	check(MapPage.NO_TOWN == "This old save has no town: start a new game to take trips.", "in the words the player is given")
	check(not page.body.visible, "and has no trips to offer")
	main.page_key("map")
	check(not main.hud.radio_open(), "the same key shuts it")
	main.page_key("map", true)    # Shift+G, the full page
	check(main.hud.scavenge_dialog == null and main.hud.radio_page() == "map", "Shift+G is not the old scavenging dialog: the same page")
	await Tut.leave(main)
	_trash(OLD_SAVE)


func test_an_old_orientation_day_is_not_resumed_in_a_game_with_an_avatar() -> void:
	# the old yard's lesson, saved: its steps are not the avatar's, so nothing of it is loaded and the avatar's lesson begins
	var t := Tut.make()
	Tut.run(t.sim, 3.0)
	check(SaveGame.write(t.sim, OLD_LESSON), "(the old lesson is saved)")
	check(Orientation.is_save(SaveGame.read(OLD_LESSON)), "(it is an Orientation Day save)")
	check(not Main.save_has_player(SaveGame.read(OLD_LESSON)), "it has no player")
	t.world.free()
	var main = Tut.start({"load": OLD_LESSON, "avatar": true})
	await Tut.frames(main, 3)
	check(main.tutorial and main.avatar_mode and main.sim.player_id == "ruth", "the avatar's Orientation Day begins, with Ruth")
	check(main.load_failed, "and the banner says the save could not be loaded")
	eq(main.coach.step_id(), "you", "from its first card")
	await Tut.leave(main)
	_trash(OLD_LESSON)
