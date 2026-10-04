extends "res://tests/case.gd"
## How the game starts and how it is paused: a cold start shows the title and a run that
## was chosen does not; the title's yard holds still and is not played; Esc clears the
## selection and then opens the pause menu, which stops the rules and gives the speed back;
## a run, a load and the way back to the title go to the scene as a choice; the settings
## put the interface size and the hints to work.

const Fakes := preload("res://tests/menu_fakes.gd")
const Main := preload("res://scripts/main.gd")
const Prefs := preload("res://scripts/prefs.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _fresh() -> void:
	Prefs.path = "user://prefs_test.cfg"
	Prefs.reset()
	# the first-launch card is the business of its own test
	Prefs.set_flag("tutorial_offered")


func _person(main: Node, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


# ------------------------------------------------------------ the decision --

func test_the_test_run_never_touches_the_players_own_settings() -> void:
	check(Prefs.path != Prefs.DEFAULT_PATH, "the tests have a settings file of their own: %s" % Prefs.path)


func test_a_cold_start_with_nothing_chosen_shows_the_title() -> void:
	check(Main.wants_title([], false), "no arguments and no run: the title")
	check(Main.wants_title(["a_word_that_is_no_flag"], false), "a bare word is not a choice")


func test_a_run_that_was_chosen_goes_straight_into_the_yard() -> void:
	for flag in ["--new=1", "--seed=7", "--load=user://quicksave.json", "--shot=a.png", "--tutorial", "--hour=21", "--advance=30", "--calm", "--select=ruth", "--size=980x700", "--only=menus", "--frames=40", "--something-nobody-knows"]:
		check(not Main.wants_title([flag], false), "%s is a choice" % flag)
	check(not Main.wants_title(["--shot=a.png", "--new=0", "--seed=3"], false), "several flags")
	check(not Main.wants_title([], true), "a run in Engine meta is a choice")
	check(not Main.wants_title(["--new=1"], true), "and so is a run in meta with a flag")


func test_the_title_can_be_asked_for_outright() -> void:
	check(Main.wants_title(["--title"], false), "--title")
	check(Main.wants_title(["--shot=title.png", "--title", "--size=980x700"], false), "--title among the screenshot flags")
	check(Main.wants_title(["--title"], true), "outright means outright")


func test_a_run_in_meta_does_not_show_the_title() -> void:
	_fresh()
	var g := Fakes.game({"difficulty": 0, "seed": 3})
	var main = g.main
	check(not main.title_mode, "no title")
	eq(main.sim.difficulty, 0, "the difficulty that was chosen")
	eq(main.sim.run_seed, 3, "and the seed")
	check(main.hud.visible and main.overlay.visible, "the HUD and the names are there")
	check(main.shell != null and main.shell.title == null and not main.shell.is_open(), "the shell is built and shows nothing")
	check(not main.menu_open, "no menu is open")
	await Fakes.leave(g)


# --------------------------------------------------------------- the title --

func test_the_title_holds_the_clock_and_hides_the_hud() -> void:
	_fresh()
	var g := Fakes.game({"title": true})
	var main = g.main
	check(main.title_mode, "the title is up")
	check(main.shell.title != null, "and drawn")
	check(not main.hud.visible, "the HUD is hidden")
	check(not main.overlay.visible, "and the names")
	near(main.sim.hour, Main.TITLE_HOUR, 0.001, "dusk")
	near(main.sim.clock_min, (Main.TITLE_HOUR - 7.0) * 60.0, 0.01, "and the game's own count of minutes (from 07:00) agrees")
	check(main.sim.zombies.size() >= 9, "some of the dead shuffle about: %d" % main.sim.zombies.size())
	var before: float = main.sim.minutes
	var clock_before: float = main.sim.clock_min
	var cam_before: Vector2 = main.cam_center
	for i in 300:
		main._process(1.0 / 30.0)
	near(main.sim.minutes, before, 0.0001, "the clock stands still")
	near(main.sim.clock_min, clock_before, 0.0001, "so does the game's own count of minutes")
	eq(main.sim.day, 1, "no day goes by")
	check(not main.sim.bell_rung, "the bell does not ring")
	check(main.sim_steps > 200, "the rules did run: %d steps" % main.sim_steps)
	check(main.cam_center != cam_before, "the camera drifts")
	await Fakes.leave(g)


func test_with_less_motion_the_title_camera_stays_still() -> void:
	_fresh()
	Prefs.set_value("ui", "reduce_motion", true)
	var g := Fakes.game({"title": true})
	var main = g.main
	main._process(1.0 / 30.0)
	var c: Vector2 = main.cam_center
	for i in 200:
		main._process(1.0 / 30.0)
	eq(main.cam_center, c, "no drift")
	check(not main.shell.title.bell.sway, "and the bell hangs still")
	await Fakes.leave(g)


func test_the_title_is_not_played() -> void:
	_fresh()
	var g := Fakes.game({"title": true})
	var main = g.main
	main._key(KEY_SPACE)
	eq(main.speed, 1, "Space does not pause the yard")
	main._key(KEY_3)
	eq(main.speed, 1, "nor 3 speed it")
	main._key(KEY_ESCAPE)
	check(not main.shell.is_open(), "Esc opens nothing on the title")
	main.open_pause()
	check(not main.shell.is_open(), "and there is no pause menu to open")
	var ruth = _person(main, "ruth")
	main._click(main._tile_to_screen(Vector2(ruth.x, ruth.y - 0.3)), MOUSE_BUTTON_LEFT)
	check(main.selection == null, "nobody can be selected")
	main._click(main._tile_to_screen(Vector2(ruth.x + 3, ruth.y + 3)), MOUSE_BUTTON_RIGHT)
	check(not ruth.drafted, "and nobody is ordered about")
	await Fakes.leave(g)


func test_the_title_saves_nothing() -> void:
	_fresh()
	var g := Fakes.game({"title": true})
	var main = g.main
	var existed := FileAccess.file_exists(SaveGame.AUTO_PATH)
	var when := FileAccess.get_modified_time(SaveGame.AUTO_PATH)
	main._autosave()
	eq(FileAccess.file_exists(SaveGame.AUTO_PATH), existed, "no autosave appears")
	eq(FileAccess.get_modified_time(SaveGame.AUTO_PATH), when, "and none is written over")
	await Fakes.leave(g)


## The control the mouse is over at `at` (the test window is tiny, so a spot inside it).
func _hovered_at(at: Vector2) -> Control:
	var root: Window = Engine.get_main_loop().root
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	root.push_input(ev, true)
	return root.gui_get_hovered_control()


## Whether `c` is the node or something inside it.
func _in(node: Node, c: Control) -> bool:
	return c != null and (c == node or node.is_ancestor_of(c))


func test_the_shell_catches_the_mouse_only_while_a_screen_is_open() -> void:
	# the shell's layer is above the HUD's: when nothing is open the mouse must go through it
	_fresh()
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	await Fakes.Kit.settle()
	var spot := Vector2(32, 32)
	var over := _hovered_at(spot)
	check(not _in(main.shell, over), "nothing open: the mouse goes through the shell (it is over %s)" % str(over))
	main.open_pause()
	await Fakes.Kit.settle()
	over = _hovered_at(spot)
	check(_in(main.shell, over), "the pause menu open: the shell has the mouse, the HUD under it does not (%s)" % str(over))
	Fakes.key(KEY_ESCAPE)
	await Fakes.Kit.settle()
	over = _hovered_at(spot)
	check(not _in(main.shell, over), "and lets go of it again (%s)" % str(over))
	await Fakes.leave(g)


# ---------------------------------------------------------------- the pause --

func test_esc_clears_the_selection_first_and_then_opens_the_pause_menu() -> void:
	_fresh()
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	main._select({"kind": "person", "ref": _person(main, "ruth")})
	main._key(KEY_ESCAPE)
	check(main.selection == null, "the first Esc lets go of the selection")
	check(not main.shell.is_open(), "and opens nothing")
	main._key(KEY_ESCAPE)
	eq(main.shell.kinds(), ["pause"], "the second opens the pause menu")
	await Fakes.leave(g)


func test_the_pause_menu_stops_the_rules_and_gives_the_speed_back() -> void:
	_fresh()
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	main.speed = 3
	main.open_pause()
	eq(main.speed, 0, "the rules stand still")
	check(main.menu_open, "a menu is open")
	var steps: int = main.sim_steps
	var minutes: float = main.sim.minutes
	for i in 90:
		main._process(1.0 / 30.0)
	eq(main.sim_steps, steps, "no step is taken while it is open")
	near(main.sim.minutes, minutes, 0.0001, "and the clock does not move")
	Fakes.key(KEY_ESCAPE)
	check(not main.shell.is_open(), "Esc closes it")
	eq(main.speed, 3, "the speed the game had comes back")
	for i in 30:
		main._process(1.0 / 30.0)
	check(main.sim_steps > steps, "and the rules go on")
	# a game that was paused stays paused
	main.speed = 0
	main.open_pause()
	Fakes.key(KEY_ESCAPE)
	eq(main.speed, 0, "paused before, paused after")
	await Fakes.leave(g)


func test_the_keys_of_the_game_do_not_reach_the_yard_while_a_menu_is_open() -> void:
	_fresh()
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	main.speed = 2
	main.open_pause()
	main._key(KEY_SPACE)
	main._key(KEY_1)
	eq(main.speed, 0, "the speed keys do nothing")
	main._select({"kind": "person", "ref": _person(main, "dez")})
	main._key(KEY_R)
	check(not _person(main, "dez").drafted, "nor does the draft key")
	check(main.menu_open, "a menu is open")
	Fakes.key(KEY_ESCAPE)
	await Fakes.leave(g)


func test_the_pause_menu_does_not_open_over_a_dialog_or_the_end() -> void:
	_fresh()
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	var dialog := Control.new()
	main.hud.scavenge_dialog = dialog
	main.open_pause()
	check(not main.shell.is_open(), "not over the scavenging dialog")
	main.hud.scavenge_dialog = null
	main.hud.game_over = dialog
	main.open_pause()
	check(not main.shell.is_open(), "nor over the end of the run")
	main.hud.game_over = null
	dialog.free()
	main.open_pause()
	check(main.shell.is_open(), "but over the game it does")
	main.open_pause()
	eq(main.shell.kinds(), ["pause"], "and only once")
	Fakes.key(KEY_ESCAPE)
	await Fakes.leave(g)


func test_how_to_play_leaves_the_game_paused_and_shows_the_controls() -> void:
	_fresh()
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	main.speed = 2
	main.open_pause()
	check(not main.hud.help.visible, "the controls are not showing")
	var pause = main.shell.top()
	pause.items["help"].pressed.emit()
	check(main.hud.help.visible, "the controls panel is up")
	check(not main.shell.is_open(), "the menu is gone")
	eq(main.speed, 0, "the game stays paused so the keys can be read")
	check(main.hud.toast_panel.visible and main.hud.toast_label.text.contains("Space"), "and a toast says how to go on: '%s'" % main.hud.toast_label.text)
	await Fakes.leave(g)


# ------------------------------------------------------ run, load and title --

func test_a_run_a_load_and_the_title_are_handed_to_the_scene_as_a_choice() -> void:
	_fresh()
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	var got: Array = []
	main.restart = func(meta): got.append(meta)
	main.start_run(2, 4242)
	eq(got.back(), {"difficulty": 2, "seed": 4242}, "a new run")
	main.start_run(9, -5)
	eq(got.back(), {"difficulty": 2, "seed": -5}, "a difficulty past the end is the last")
	main.start_run(-1, 1)
	eq(got.back(), {"difficulty": 0, "seed": 1}, "and one before the start is the first")
	main.show_title()
	eq(got.back(), {"title": true}, "the way back to the title")
	var n := got.size()
	check(not main.load_run("user://this_save_is_not_there.json"), "a save that is not there is refused")
	eq(got.size(), n, "and nothing is begun")
	var path := "user://test_menu_boot_%d.json" % OS.get_process_id()
	Fakes.write_save(path)
	check(main.load_run(path), "a save is taken")
	eq(got.back(), {"load": path}, "and its path is the choice")
	# a damaged one is not
	Fakes.write_text(path, "{ this is not a save")
	n = got.size()
	check(not main.load_run(path), "a damaged save is refused")
	eq(got.size(), n, "and the game that is running goes on")
	Fakes.clean([path])
	await Fakes.leave(g)


func test_without_a_hook_the_choice_is_left_in_engine_meta_for_the_reload() -> void:
	_fresh()
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	main.start_run(0, 5)
	check(Engine.has_meta("run"), "the choice is in meta")
	eq(Engine.get_meta("run"), {"difficulty": 0, "seed": 5}, "the one that was asked for")
	Engine.remove_meta("run")
	main.show_title()
	eq(Engine.get_meta("run"), {"title": true}, "the title is a choice too")
	Engine.remove_meta("run")
	await Fakes.leave(g)


func test_the_title_of_the_real_game_starts_a_run_through_its_menus() -> void:
	# the whole way, with the real game under the menus: the choice is left in Engine meta for the reload
	_fresh()
	var g := Fakes.game({"title": true})
	var main = g.main
	var paths := Fakes.slot_paths("boot")
	Fakes.set_slots(main.shell, paths)
	await Fakes.Kit.settle()
	var screen = main.shell.open_new_game()
	await Fakes.Kit.settle()
	screen.cards[2].pressed.emit()
	screen.seed_edit.text = "4242"
	screen.seed_edit.text_changed.emit("4242")
	screen.start_button.pressed.emit()
	check(Engine.has_meta("run"), "the choice is in Engine meta")
	# (the real game's New game starts the town, One House: no crew and no length to choose, so the choice is the difficulty, the seed and the town; the school's
	# start with its crew is reached only by `--school`, and the menus' own tests drive it through a stand-in game)
	eq(Engine.get_meta("run"), {"difficulty": 2, "seed": 4242, "town": true}, "a Brutal town run on seed 4242")
	Engine.remove_meta("run")
	# Continue: the newest save
	Fakes.write_save(paths[0], 6, 12.0, 1)
	main.shell.title.refresh()
	check(main.shell.continue_game(), "Continue goes")
	eq(Engine.get_meta("run"), {"load": paths[0]}, "to the save that is there")
	Engine.remove_meta("run")
	# a damaged save is never begun
	Fakes.write_text(paths[0], "{ not a save")
	check(not main.shell.load_slot(paths[0]), "a damaged one is refused")
	check(not Engine.has_meta("run"), "and nothing is left for the reload")
	# Orientation Day: through the game's own start_tutorial (the tutorial builder's)
	if main.has_method("start_tutorial"):
		main.shell.start_orientation()
		check(Engine.has_meta("run"), "Orientation Day leaves its choice too")
		eq(Engine.get_meta("run").get("tutorial"), true, "the tutorial")
		Engine.remove_meta("run")
	Fakes.clean(paths)
	await Fakes.leave(g)


# ------------------------------------------------------------ interface size --

func test_the_interface_size_is_held_back_in_a_window_too_small_for_it() -> void:
	near(Main.effective_ui_scale(Vector2(1280, 800), 1.0, 1.0), 1.0, 0.0001, "normal is normal")
	near(Main.effective_ui_scale(Vector2(1280, 800), 1.0, 0.8), 0.8, 0.0001, "smaller is always possible")
	near(Main.effective_ui_scale(Vector2(640, 400), 1.0, 0.8), 0.8, 0.0001, "even in a small window")
	near(Main.effective_ui_scale(Vector2(1920, 1200), 1.0, 1.5), 1.5, 0.0001, "bigger fits a big window")
	near(Main.effective_ui_scale(Vector2(2880, 1800), 2.0, 1.5), 1.5, 0.0001, "the display's own scale counts: 1440x900 points")
	near(Main.effective_ui_scale(Vector2(2560, 1600), 2.0, 1.5), 800.0 / 560.0, 0.0001, "and 1280x800 points hold it back to 800 / 560")
	near(Main.effective_ui_scale(Vector2(1000, 800), 1.0, 1.5), 1000.0 / 700.0, 0.0001, "bigger stops where the window would be under 700 wide")
	near(Main.effective_ui_scale(Vector2(1600, 600), 1.0, 1.5), 600.0 / 560.0, 0.0001, "or under 560 tall")
	near(Main.effective_ui_scale(Vector2(700, 560), 1.0, 1.5), 1.0, 0.0001, "the smallest window gets the normal size")
	near(Main.effective_ui_scale(Vector2(500, 400), 1.0, 1.5), 1.0, 0.0001, "a window below that is not squeezed further")
	near(Main.effective_ui_scale(Vector2(1920, 1200), 1.0, 3.0), 1.5, 0.0001, "past 150% is 150%")
	near(Main.effective_ui_scale(Vector2(1920, 1200), 1.0, 0.1), 0.8, 0.0001, "and under 80% is 80%")
	near(Main.effective_ui_scale(Vector2(1920, 1200), 0.0, 1.0), 1.0, 0.0001, "a display that reports no scale is not divided by")


func test_the_settings_put_the_interface_size_to_work() -> void:
	_fresh()
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	var win: Window = Engine.get_main_loop().root
	var s := DisplayServer.screen_get_scale()
	if s <= 0.0:
		s = 1.0
	for pref in [1.0, 1.25, 0.8, 1.5]:
		Prefs.set_value("ui", "scale", pref)
		main.apply_settings()
		var k: float = Main.effective_ui_scale(Vector2(win.size), s, pref)
		near(main.ui_scale_in_use(), k, 0.0001, "the size in use for %.2f" % pref)
		eq(win.content_scale_size, Vector2i(maxi(1, int(win.size.x / (s * k))), maxi(1, int(win.size.y / (s * k)))), "the window's logical size for %.2f" % pref)
	await Fakes.leave(g)


func test_the_size_is_read_when_the_game_starts() -> void:
	_fresh()
	Prefs.set_value("ui", "scale", 0.8)
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var win: Window = Engine.get_main_loop().root
	var s := DisplayServer.screen_get_scale()
	if s <= 0.0:
		s = 1.0
	eq(win.content_scale_size, Vector2i(maxi(1, int(win.size.x / (s * 0.8))), maxi(1, int(win.size.y / (s * 0.8)))), "80% from the first frame")
	await Fakes.leave(g)


func test_hints_off_hides_the_hint_and_on_leaves_it() -> void:
	_fresh()
	Prefs.set_value("ui", "hints", false)
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	check(not g.main.hud.hint.visible, "with hints off the one-line hint is not shown")
	await Fakes.leave(g)
	_fresh()
	g = Fakes.game({"difficulty": 1, "seed": 7})
	var wide: bool = not g.main.hud.compact
	if wide:
		check(g.main.hud.hint.visible, "with hints on it is")
	await Fakes.leave(g)


func test_a_screenshot_run_keeps_its_settings_apart_from_the_players() -> void:
	eq(Main.prefs_file_for([]), "", "a normal start uses the player's own file")
	eq(Main.prefs_file_for(["--new=1", "--seed=3"]), "", "so does a chosen run")
	eq(Main.prefs_file_for(["--shot=a.png"]), "user://prefs_shot.cfg", "a screenshot run has a file of its own")
	eq(Main.prefs_file_for(["--shot=a.png", "--prefs=user://x.cfg"]), "user://x.cfg", "unless it names one")
	eq(Main.prefs_file_for(["--prefs=user://y.cfg"]), "user://y.cfg", "a named file is used")
