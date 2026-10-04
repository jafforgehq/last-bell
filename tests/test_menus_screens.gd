extends "res://tests/case.gd"
## What the menus do: the title's lines, the first-launch card, New game (difficulty and
## seed), the pause menu and the questions it asks, Esc and the keyboard, and the settings
## (kept and applied at once). The game is a stand-in that writes down what it is asked.

const Fakes := preload("res://tests/menu_fakes.gd")
const HudKit := preload("res://tests/hud_kit.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")
const Shell := preload("res://scripts/ui/shell.gd")
const NewGameMenu := preload("res://scripts/ui/new_game_menu.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Waves := preload("res://scripts/sim/waves.gd")
const Medical := preload("res://scripts/sim/medical.gd")
const Scavenge := preload("res://scripts/sim/scavenge.gd")
const Helpers := preload("res://tests/helpers.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const Kinds := preload("res://scripts/sim/kinds.gd")


func _done(ctx: Dictionary) -> void:
	Buses.hud_muted = false
	Fakes.free_all(ctx)
	Buses.apply_all()


# ------------------------------------------------------------------ the title --

func test_the_title_offers_every_way_in() -> void:
	var ctx := Fakes.build()
	ctx.shell.show_title()
	await HudKit.settle()
	var title = ctx.shell.title
	eq(title.items.keys(), ["continue", "new", "orientation", "load", "settings", "credits", "quit"], "the lines, in order")
	var words := {"continue": "Continue", "new": "New game", "orientation": "Orientation Day", "load": "Load", "settings": "Settings", "credits": "Credits", "quit": "Quit"}
	for key in words:
		eq(title.items[key].get_meta("title").text, words[key], "the line for %s" % key)
		eq(title.items[key].focus_mode, Control.FOCUS_ALL, "%s can be reached by the keyboard" % key)
	var texts := HudKit.texts(title)
	check(texts.has("THIRTY") and texts.has("BELLS"), "the name of the game")
	check(texts.has("Hold the schoolyard for thirty nights."), "and its line")
	check(is_instance_valid(title.bell), "with a bell")
	_done(ctx)


func test_quit_is_not_offered_on_the_web() -> void:
	var ctx := Fakes.build()
	ctx.shell.web = true
	ctx.shell.show_title()
	check(not ctx.shell.title.items.has("quit"), "no Quit in a browser")
	check(ctx.shell.title.items.has("settings"), "the rest is there")
	var pause = ctx.shell.open_pause()
	check(not pause.items.has("quit"), "nor in the pause menu")
	check(pause.items.has("menu"), "though the way back to the title is")
	_done(ctx)


func test_continue_is_off_without_a_save_and_shows_the_day_with_one() -> void:
	var ctx := Fakes.build()
	ctx.shell.show_title()
	await HudKit.settle()
	var title = ctx.shell.title
	var c: Button = title.items["continue"]
	check(c.disabled, "nothing to continue: the line is off")
	eq(c.get_meta("sub").text, "No saved game yet", "and says why")
	check(c.modulate.a < 1.0, "and is greyed")
	eq(Fakes.focused(), title.items["new"], "the keyboard starts on New game")
	Fakes.write_save(ctx.paths[0], 5, 9.0, 1)
	title.refresh()
	check(not c.disabled, "with a save the line is on")
	eq(c.get_meta("sub").text, "Day 5, 09:00, Standard", "and says which day")
	eq(c.modulate.a, 1.0, "and is not greyed")
	eq(title.default_focus(), c, "and is where the keyboard starts")
	c.pressed.emit()
	eq(ctx.main.last("load_run"), ["load_run", ctx.paths[0]], "pressing it loads the save")
	_done(ctx)


func test_orientation_day_is_gold_until_it_has_been_done() -> void:
	var ctx := Fakes.build()
	ctx.shell.show_title()
	check(ctx.shell.title.items["orientation"].get_meta("primary"), "not done: the line is the main choice")
	check(not ctx.shell.title.items["new"].get_meta("primary"), "and New game is not")
	ctx.shell.title.free()
	ctx.shell.title = null
	Prefs.set_flag("tutorial_done")
	ctx.shell.show_title()
	check(not ctx.shell.title.items["orientation"].get_meta("primary"), "done: it is a line like the others")
	_done(ctx)


func test_each_line_opens_its_screen_and_esc_comes_back_to_it() -> void:
	var ctx := Fakes.build()
	var shell = ctx.shell
	shell.show_title()
	await HudKit.settle()
	var title = shell.title
	for pair in [["new", "new"], ["load", "load"], ["settings", "settings"], ["credits", "credits"]]:
		var line: Button = title.items[pair[0]]
		HudKit.click_on(line)
		await HudKit.settle()
		eq(shell.kinds(), [pair[1]], "%s opens its screen" % pair[0])
		check(not title.board.visible, "the menu steps aside for %s" % pair[0])
		check(shell.top().is_ancestor_of(Fakes.focused()), "and the keyboard is in the screen")
		Fakes.key(KEY_ESCAPE)
		await HudKit.settle()
		eq(shell.kinds(), [], "Esc closes %s" % pair[0])
		check(title.board.visible, "the menu is back")
		eq(Fakes.focused(), line, "with the keyboard on the line that opened it")
	check(ctx.sound.ui_played.has("ui_open") and ctx.sound.ui_played.has("ui_close"), "the screens open and close with a sound")
	_done(ctx)


func test_a_menu_line_lights_up_under_the_mouse_and_the_keyboard() -> void:
	var ctx := Fakes.build()
	ctx.shell.show_title()
	await HudKit.settle()
	var line: Button = ctx.shell.title.items["load"]
	var word: Label = line.get_meta("title")
	var plain: Color = ctx.hud.INK
	eq(word.get_theme_color("font_color"), plain, "a line at rest is cream")
	line.mouse_entered.emit()
	eq(word.get_theme_color("font_color"), ctx.hud.ACCENT, "under the mouse it is gold")
	line.mouse_exited.emit()
	eq(word.get_theme_color("font_color"), plain, "and cream again when the mouse goes")
	line.grab_focus()
	eq(word.get_theme_color("font_color"), ctx.hud.ACCENT, "with the keyboard on it it is gold")
	line.mouse_entered.emit()
	line.mouse_exited.emit()
	eq(word.get_theme_color("font_color"), ctx.hud.ACCENT, "and stays gold when the mouse leaves but the keyboard is still there")
	ctx.shell.title.items["settings"].grab_focus()
	eq(word.get_theme_color("font_color"), plain, "and cream when the keyboard goes")
	# the gold line (Orientation Day) is dark on gold and does not change
	var gold: Label = ctx.shell.title.items["orientation"].get_meta("title")
	var before := gold.get_theme_color("font_color")
	ctx.shell.title.items["orientation"].mouse_entered.emit()
	eq(gold.get_theme_color("font_color"), before, "ink on gold stays ink on gold")
	# a line that is off does not light up
	var off: Button = ctx.shell.title.items["continue"]
	off.mouse_entered.emit()
	eq(off.get_meta("title").get_theme_color("font_color"), plain, "a line that is off stays as it is")
	_done(ctx)


func test_quit_asks_the_game_to_quit() -> void:
	var ctx := Fakes.build()
	ctx.shell.show_title()
	ctx.shell.title.items["quit"].pressed.emit()
	eq(ctx.main.last("quit"), ["quit"], "Quit")
	_done(ctx)


func test_orientation_day_starts_the_tutorial_or_says_it_is_coming() -> void:
	var ctx := Fakes.build(1280, 800, true)
	ctx.shell.show_title()
	ctx.shell.title.items["orientation"].pressed.emit()
	eq(ctx.main.last("start_tutorial"), ["start_tutorial"], "the game has it: it starts")
	_done(ctx)
	ctx = Fakes.build(1280, 800, false)
	ctx.shell.show_title()
	ctx.shell.title.items["orientation"].pressed.emit()
	check(ctx.main.last("start_tutorial").is_empty(), "a game without it asks for nothing")
	check(ctx.shell.toast_panel.visible and ctx.shell.toast_label.text.contains("coming soon"), "and says so: '%s'" % ctx.shell.toast_label.text)
	check(ctx.sound.ui_played.has("ui_error"), "with the sound of no")
	_done(ctx)


# ------------------------------------------------------- the first-launch card --

func test_the_first_launch_card_is_offered_once() -> void:
	var ctx := Fakes.build()
	Prefs.set_flag("tutorial_offered", false)
	ctx.shell.show_title()
	await HudKit.settle()
	eq(ctx.shell.kinds(), ["orientation"], "the first time: the card")
	check(Prefs.flag("tutorial_offered"), "and it is written down at once")
	Prefs.forget()
	check(Prefs.flag("tutorial_offered"), "in the file")
	var texts := HudKit.texts(ctx.shell.top())
	check(texts.has("First time here?"), "it asks")
	var said := false
	for t in texts:
		if String(t).begins_with("Orientation Day teaches the basics in about ten minutes"):
			said = true
	check(said, "and says what Orientation Day is: %s" % str(texts))
	eq(ctx.shell.top().start_button.text, "Start Orientation Day", "with the answer yes")
	eq(ctx.shell.top().later_button.text, "Not now", "and the answer no")
	check(ctx.shell.top().is_ancestor_of(Fakes.focused()), "the keyboard is on the card")
	check(ctx.shell.title.board.visible, "the menu stays in view behind it")
	# not now
	ctx.shell.top().later_button.pressed.emit()
	eq(ctx.shell.kinds(), [], "Not now closes it")
	check(ctx.main.last("start_tutorial").is_empty(), "and starts nothing")
	# the next launch: no card
	var shell2 = Shell.new()
	ctx.holder.add_child(shell2)
	shell2.setup(ctx.main, ctx.hud)
	Fakes.set_slots(shell2, ctx.paths)
	shell2.show_title()
	eq(shell2.kinds(), [], "the next time there is no card")
	_done(ctx)


func test_the_card_can_start_orientation_day_and_esc_is_not_now() -> void:
	var ctx := Fakes.build()
	Prefs.set_flag("tutorial_offered", false)
	ctx.shell.show_title()
	await HudKit.settle()
	ctx.shell.top().start_button.pressed.emit()
	eq(ctx.main.last("start_tutorial"), ["start_tutorial"], "Start Orientation Day starts it")
	eq(ctx.shell.kinds(), [], "and the card is gone")
	ctx.main.calls.clear()
	var card = ctx.shell.offer_orientation()
	await HudKit.settle()
	Fakes.key(KEY_ESCAPE)
	eq(ctx.shell.kinds(), [], "Esc is Not now")
	check(ctx.main.last("start_tutorial").is_empty(), "and starts nothing")
	_done(ctx)


# ---------------------------------------------------------------- new game --

func test_new_game_starts_the_run_with_the_chosen_difficulty_and_seed() -> void:
	var ctx := Fakes.build()
	ctx.shell.show_title()
	await HudKit.settle()
	HudKit.click_on(ctx.shell.title.items["new"])
	await HudKit.settle()
	var screen = ctx.shell.top()
	eq(screen.kind, "new", "the New game screen")
	eq(screen.difficulty, 1, "Standard to begin with")
	check(screen.cards[1].button_pressed and not screen.cards[0].button_pressed and not screen.cards[2].button_pressed, "its card is the one pressed")
	check(NewGameMenu.parse_seed(screen.seed_edit.text).ok, "a seed is shown: '%s'" % screen.seed_edit.text)
	eq(Fakes.focused(), screen.start_button, "Enter would start")
	HudKit.click_on(screen.cards[2])
	eq(screen.difficulty, 2, "a click on Brutal")
	check(screen.cards[2].button_pressed and not screen.cards[1].button_pressed, "lights its card and no other")
	screen.seed_edit.text = "4242"
	screen.seed_edit.text_changed.emit("4242")
	HudKit.click_on(screen.start_button)
	eq(ctx.main.last("start_run"), ["start_run", 2, 4242, 5], "the game is asked for a Brutal run on seed 4242, with the crew of five the menu begins on")
	check(ctx.sound.ui_played.has("ui_confirm"), "with the sound of yes")
	_done(ctx)


func test_new_game_can_be_picked_with_the_keyboard() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_new_game()
	await HudKit.settle()
	# Enter on the Start button the keyboard starts on: a Standard run on the seed shown
	var shown := int(screen.seed_edit.text)
	Fakes.key(KEY_ENTER)
	eq(ctx.main.last("start_run"), ["start_run", 1, shown, 5], "Enter starts a Standard run on the seed that was shown")
	ctx.main.calls.clear()
	# Enter in the seed box starts too
	var screen2 = ctx.shell.open_new_game()
	await HudKit.settle()
	screen2.cards[0].pressed.emit()
	screen2.seed_edit.text = "-17"
	screen2.seed_edit.text_changed.emit("-17")
	screen2.seed_edit.text_submitted.emit("-17")
	eq(ctx.main.last("start_run"), ["start_run", 0, -17, 5], "a Story run on seed -17 from the seed box")
	_done(ctx)


func test_new_game_checks_the_seed() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_new_game()
	await HudKit.settle()
	for bad in ["", "abc", "12.5", "1e5", "0x10", "12 34", "- 3"]:
		screen.seed_edit.text = bad
		screen.seed_edit.text_changed.emit(bad)
		check(screen.start_button.disabled, "'%s' is not a seed: Start is off" % bad)
		check(screen.seed_error.visible and screen.seed_error.text != "", "and the box says why: '%s'" % screen.seed_error.text)
		screen.start_button.pressed.emit()
		screen.seed_edit.text_submitted.emit(bad)
	check(ctx.main.last("start_run").is_empty(), "nothing was started with a bad seed")
	for good in ["0", "7", "482913", "-3", " 55 ", "123456789012"]:
		screen.seed_edit.text = good
		screen.seed_edit.text_changed.emit(good)
		check(not screen.start_button.disabled and not screen.seed_error.visible, "'%s' is a seed" % good)
	check(not NewGameMenu.parse_seed("9999999999999").ok, "thirteen characters is too long for a seed")
	eq(screen.seed_edit.max_length, NewGameMenu.MAX_SEED_CHARS, "the box does not take more than that")
	eq(NewGameMenu.parse_seed(" 55 ").value, 55, "spaces round it do not count")
	eq(NewGameMenu.parse_seed("-3").value, -3, "a minus sign does")
	# the Random button
	screen.seed_edit.text = "abc"
	screen.seed_edit.text_changed.emit("abc")
	screen.random_button.pressed.emit()
	check(NewGameMenu.parse_seed(screen.seed_edit.text).ok, "Random gives a seed: '%s'" % screen.seed_edit.text)
	check(not screen.start_button.disabled and not screen.seed_error.visible, "and Start is on again")
	var seen := {}
	for i in 12:
		screen.random_button.pressed.emit()
		seen[screen.seed_edit.text] = true
	check(seen.size() > 3, "and it is not always the same one: %d different in 12" % seen.size())
	_done(ctx)


func test_new_game_remembers_the_difficulty_last_chosen() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_new_game()
	await HudKit.settle()
	eq(screen.difficulty, 1, "Standard the first time")
	screen.cards[2].pressed.emit()
	screen.start_button.pressed.emit()
	eq(Prefs.get_value("ui", "difficulty", 1), 2, "Brutal was kept")
	var screen2 = ctx.shell.open_new_game()
	await HudKit.settle()
	eq(screen2.difficulty, 2, "and the next New game starts on it")
	check(screen2.cards[2].button_pressed, "with its card lit")
	Prefs.set_value("ui", "difficulty", 99)
	var screen3 = ctx.shell.open_new_game()
	eq(screen3.difficulty, 2, "a value that makes no sense is the last difficulty")
	_done(ctx)


func test_the_difficulty_words_are_true_to_the_rules() -> void:
	# the one-liners promise fewer of the dead and kinder wounds for Story, more for Brutal: the numbers agree
	check(Waves.DIFFICULTY[0] < Waves.DIFFICULTY[1] and Waves.DIFFICULTY[1] < Waves.DIFFICULTY[2], "more of the dead as it gets harder")
	check(Medical.INFECT_CHANCE[0] < Medical.INFECT_CHANCE[1] and Medical.INFECT_CHANCE[1] < Medical.INFECT_CHANCE[2], "more infection")
	check(Scavenge.DANGER_MULT[0] < Scavenge.DANGER_MULT[1] and Scavenge.DANGER_MULT[1] < Scavenge.DANGER_MULT[2], "more danger on trips")
	eq(Kit.difficulty_name(0), "Story", "Story")
	eq(Kit.difficulty_name(1), "Standard", "Standard")
	eq(Kit.difficulty_name(2), "Brutal", "Brutal")
	eq(Kit.difficulty_line(0), "Fewer of the dead, kinder wounds", "Story's line")
	eq(Kit.difficulty_line(1), "The intended game", "Standard's line")
	eq(Kit.difficulty_line(2), "For people who have won", "Brutal's line")
	# what is said under the cards is worked out from the numbers
	for i in 3:
		var g := Helpers.make(1, i)
		var first := roundi(g.sim.waves.budget_for(1))
		var facts := Kit.difficulty_facts(i)
		check(facts.contains("about %d " % first), "difficulty %d: the first night's %d is in the words: '%s'" % [i, first, facts])
		g.world.free()
	var story := Kit.difficulty_facts(0)
	var standard := Kit.difficulty_facts(1)
	var brutal := Kit.difficulty_facts(2)
	check(story.contains("%d%% fewer" % roundi((1.0 - Waves.DIFFICULTY[0]) * 100.0)), "Story: fewer of the dead: '%s'" % story)
	check(story.contains("infects %d times in 10" % roundi(Medical.INFECT_CHANCE[0] * 10.0)), "Story: how often a bite infects: '%s'" % story)
	check(story.contains("%d%% less dangerous" % roundi((1.0 - Scavenge.DANGER_MULT[0]) * 100.0)), "Story: trips: '%s'" % story)
	check(standard.begins_with("As designed"), "Standard is as designed: '%s'" % standard)
	check(standard.contains("infects %d times in 10" % roundi(Medical.INFECT_CHANCE[1] * 10.0)), "Standard: bites: '%s'" % standard)
	check(brutal.contains("%d%% more of the dead" % roundi((Waves.DIFFICULTY[2] - 1.0) * 100.0)), "Brutal: more of the dead: '%s'" % brutal)
	check(brutal.contains("Every bite infects"), "Brutal: every bite infects: '%s'" % brutal)
	check(brutal.contains("%d%% more dangerous" % roundi((Scavenge.DANGER_MULT[2] - 1.0) * 100.0)), "Brutal: trips: '%s'" % brutal)
	# and the screen shows them: the words follow the card chosen
	var ctx := Fakes.build()
	var screen = ctx.shell.open_new_game()
	for i in 3:
		screen.cards[i].pressed.emit()
		eq(screen.facts_label.text, Kit.difficulty_facts(i, screen.crew), "the words under the cards for %s" % Kit.difficulty_name(i))
	_done(ctx)


## The avatar game's nights (crews of 3 and 5: round 22, the QA's stale blurb): the words come from the rules of the avatar game's waves, not the
## classic game's "about 30 on the first night and 3 more each night".
func test_the_difficulty_words_for_an_avatar_crew_are_the_avatar_nights() -> void:
	for crew in [3, 5]:
		for i in 3:
			var g := Helpers.make(1, i, crew)
			var sim = g.sim
			check(sim.avatar.set_player("ruth"), "(the avatar)")
			var first: float = sim.waves.night_budget(1)
			var more: float = sim.waves.night_budget(2) - first
			var facts := Kit.difficulty_facts(i, crew)
			check(facts.contains("about %d of the dead on the first night" % roundi(first)) or facts.contains("about %d on the first night" % roundi(first)), "crew %d, difficulty %d: the first night's %.1f is in the words: '%s'" % [crew, i, first, facts])
			check(facts.contains("%d more each night" % roundi(more)), "crew %d, difficulty %d: the %.2f more a night is: '%s'" % [crew, i, more, facts])
			check(facts.contains("Big Night") and facts.contains("%dth" % int(NightData.num("big_every", 10.0))), "the Big Nights are told, every tenth: '%s'" % facts)
			check(facts.contains("From night %d a brute, worth %d of the dead" % [int(Kinds.KINDS.brute.first), int(Kinds.KINDS.brute.cost)]), "and the brutes, which make a night fewer bodies and no easier: '%s'" % facts)
			check(not facts.contains("3 more each night") or roundi(more) == 3, "and the old '3 more each night' is gone: '%s'" % facts)
			g.world.free()
	var classic := Kit.difficulty_facts(1, 6)
	eq(classic, Kit.difficulty_facts(1), "a full crew of six (no avatar) has the classic words")
	check(classic.contains("about 30 of the dead on the first night, 3 more each night after"), "which are true of it: '%s'" % classic)
	check(not classic.contains("Big Night"), "and have no Big Nights of the avatar game: '%s'" % classic)
	# the other words of a difficulty do not depend on the crew
	for i in 3:
		var a := Kit.difficulty_facts(i, 5)
		var b := Kit.difficulty_facts(i, 6)
		check(a.contains(b.substr(b.find("A bite") if b.contains("A bite") else b.find("Every bite"))), "difficulty %d: the bites and the trips are the same words" % i)


func test_the_words_under_the_difficulty_cards_follow_the_crew_too() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_new_game()
	await HudKit.settle()
	screen.cards[1].pressed.emit()
	screen.crew_cards[1].pressed.emit()
	eq(screen.crew, 5, "a crew of five")
	eq(screen.facts_label.text, Kit.difficulty_facts(1, 5), "the words are the avatar game's")
	check(not screen.facts_label.text.contains("about 30 of the dead"), "not the classic ones: '%s'" % screen.facts_label.text)
	screen.crew_cards[2].pressed.emit()
	eq(screen.crew, 6, "a full crew")
	eq(screen.facts_label.text, Kit.difficulty_facts(1, 6), "the words are the old game's")
	check(screen.facts_label.text.contains("about 30 of the dead"), "with its thirty: '%s'" % screen.facts_label.text)
	screen.crew_cards[0].pressed.emit()
	eq(screen.facts_label.text, Kit.difficulty_facts(1, 3), "a crew of three: the avatar game's again")
	_done(ctx)


# ------------------------------------------------------------------- pause --

func test_the_pause_menu_has_its_lines_and_its_caption() -> void:
	var ctx := Fakes.build()
	ctx.main.sim = ctx.sim
	var pause = ctx.shell.open_pause()
	await HudKit.settle()
	eq(pause.items.keys(), ["resume", "save", "load", "settings", "help", "menu", "quit"], "the lines, in order")
	var words := {"resume": "Resume", "save": "Save", "load": "Load", "settings": "Settings", "help": "How to play", "menu": "Main menu", "quit": "Quit"}
	for key in words:
		eq(pause.items[key].get_meta("title").text, words[key], "the line for %s" % key)
	eq(pause.title_label.text, "Paused", "the heading")
	eq(pause.caption_label.text, "DAY 1, 07:00", "the caption (the caps style) says where the game is")
	eq(Fakes.focused(), pause.items["resume"], "the keyboard starts on Resume")
	check(pause.items["resume"].get_meta("primary"), "which is the main choice")
	_done(ctx)


func test_the_pause_menus_save_and_resume() -> void:
	var ctx := Fakes.build()
	var pause = ctx.shell.open_pause()
	await HudKit.settle()
	pause.items["save"].pressed.emit()
	eq(ctx.main.last("quick_save"), ["quick_save"], "Save asks for the quick save")
	check(ctx.shell.toast_panel.visible and ctx.shell.toast_label.text.begins_with("Game saved"), "with a toast: '%s'" % ctx.shell.toast_label.text)
	check(ctx.sound.ui_played.has("ui_confirm"), "and a sound")
	eq(ctx.shell.kinds(), ["pause"], "and the menu stays open")
	ctx.main.save_ok = false
	ctx.sound.ui_played.clear()
	pause.items["save"].pressed.emit()
	check(ctx.shell.toast_label.text.begins_with("Could not save"), "a save that fails says so: '%s'" % ctx.shell.toast_label.text)
	check(ctx.sound.ui_played.has("ui_error"), "with the sound of no")
	pause.items["resume"].pressed.emit()
	eq(ctx.shell.kinds(), [], "Resume closes it")
	eq(ctx.main.last("resume"), ["resume", false], "and tells the game to go on")
	_done(ctx)


func test_load_and_settings_open_over_the_pause_menu_and_give_it_back() -> void:
	var ctx := Fakes.build()
	var pause = ctx.shell.open_pause()
	await HudKit.settle()
	for key in ["load", "settings"]:
		pause.items[key].pressed.emit()
		await HudKit.settle()
		eq(ctx.shell.kinds(), ["pause", key], "%s opens over the pause menu" % key)
		check(not pause.visible, "which steps out of sight")
		check(ctx.shell.top().is_ancestor_of(Fakes.focused()), "the keyboard is in the new screen")
		check(pause.items["resume"].focus_mode == Control.FOCUS_NONE, "and cannot wander back into the pause menu")
		if key == "load":
			check(ctx.shell.top().replaces_game, "the list knows it replaces the game")
		Fakes.key(KEY_ESCAPE)
		await HudKit.settle()
		eq(ctx.shell.kinds(), ["pause"], "Esc gives the pause menu back")
		check(pause.visible and pause.items["resume"].focus_mode == Control.FOCUS_ALL, "shown and reachable again")
		check(pause.is_ancestor_of(Fakes.focused()), "with the keyboard in it")
		check(ctx.main.last("resume").is_empty(), "and the game is still paused")
	Fakes.key(KEY_ESCAPE)
	eq(ctx.shell.kinds(), [], "Esc closes the pause menu")
	eq(ctx.main.last("resume"), ["resume", false], "and the game goes on")
	_done(ctx)


func test_the_main_menu_and_quit_ask_first() -> void:
	var ctx := Fakes.build()
	var pause = ctx.shell.open_pause()
	await HudKit.settle()
	pause.items["menu"].pressed.emit()
	await HudKit.settle()
	eq(ctx.shell.kinds(), ["pause", "confirm"], "Main menu asks")
	var confirm = ctx.shell.top()
	check(HudKit.texts(confirm).has("Leave this game?"), "the question: %s" % str(HudKit.texts(confirm)))
	eq(Fakes.focused(), confirm.stay_button, "the keyboard is on Stay, the safe answer")
	check(confirm.stay_button.get_meta("primary"), "which is the gold one")
	check(ctx.main.last("show_title").is_empty(), "nothing has happened yet")
	confirm.stay_button.pressed.emit()
	eq(ctx.shell.kinds(), ["pause"], "Stay is back to the pause menu")
	check(ctx.main.last("show_title").is_empty(), "and nothing happened")
	pause.items["menu"].pressed.emit()
	Fakes.key(KEY_ESCAPE)
	eq(ctx.shell.kinds(), ["pause"], "Esc is Stay")
	check(ctx.main.last("show_title").is_empty(), "and nothing happened")
	pause.items["menu"].pressed.emit()
	ctx.shell.top().ok_button.pressed.emit()
	eq(ctx.main.last("show_title"), ["show_title"], "yes goes back to the title")
	# quit
	ctx.main.calls.clear()
	pause.items["quit"].pressed.emit()
	check(HudKit.texts(ctx.shell.top()).has("Quit the game?"), "Quit asks too")
	check(ctx.main.last("quit").is_empty(), "and has not quit")
	ctx.shell.top().stay_button.pressed.emit()
	check(ctx.main.last("quit").is_empty(), "Stay does not quit")
	pause.items["quit"].pressed.emit()
	ctx.shell.top().ok_button.pressed.emit()
	eq(ctx.main.last("quit"), ["quit"], "yes quits")
	_done(ctx)


func test_how_to_play_shows_the_controls_and_closes_the_pause_menu() -> void:
	var ctx := Fakes.build()
	var pause = ctx.shell.open_pause()
	await HudKit.settle()
	check(not ctx.hud.help.visible, "the controls are not showing")
	pause.items["help"].pressed.emit()
	check(ctx.hud.help.visible, "the HUD's controls panel is up")
	eq(ctx.shell.kinds(), [], "and the menu is gone")
	eq(ctx.main.last("resume"), ["resume", true], "the game is told to stay paused")
	_done(ctx)


func test_esc_closes_one_screen_at_a_time_and_a_covered_one_cannot_be_reached() -> void:
	var ctx := Fakes.build()
	var shell = ctx.shell
	shell.show_title()
	await HudKit.settle()
	var title = shell.title
	var pause = shell.open_pause()
	pause.items["settings"].pressed.emit()
	await HudKit.settle()
	var settings = shell.top()
	eq(shell.kinds(), ["pause", "settings"], "two screens up")
	# Tab goes round the top screen and never leaves it
	var seen := {}
	for i in 14:
		Fakes.key(KEY_TAB)
		var f := Fakes.focused()
		check(f != null and settings.is_ancestor_of(f), "Tab %d is in the settings screen" % i)
		seen[f] = true
	check(seen.size() >= 6, "and visits them all: %d controls" % seen.size())
	for line in title.items.values():
		eq(line.focus_mode, Control.FOCUS_NONE, "a title line cannot take the keyboard under two screens")
	Fakes.key(KEY_ESCAPE)
	eq(shell.kinds(), ["pause"], "Esc closes the top one only")
	Fakes.key(KEY_ESCAPE)
	eq(shell.kinds(), [], "and then the next")
	await HudKit.settle()
	for line in title.items.values():
		eq(line.focus_mode, Control.FOCUS_ALL, "the title's lines are reachable again")
	check(title.is_ancestor_of(Fakes.focused()), "with the keyboard back on the title")
	Fakes.key(KEY_ESCAPE)
	eq(shell.kinds(), [], "Esc on the bare title does nothing")
	_done(ctx)


func test_an_arrow_key_with_nothing_focused_finds_the_first_control() -> void:
	var ctx := Fakes.build()
	var pause = ctx.shell.open_pause()
	await HudKit.settle()
	Fakes.focused().release_focus()
	check(Fakes.focused() == null, "nothing has the keyboard")
	Fakes.key(KEY_DOWN)
	eq(Fakes.focused(), pause.items["resume"], "a key of the menu lands on its first line")
	_done(ctx)


func test_the_toast_shows_for_a_moment() -> void:
	var ctx := Fakes.build()
	ctx.shell.toast_seconds = 0.3
	ctx.shell.toast("Hello there")
	check(ctx.shell.toast_panel.visible and ctx.shell.toast_label.text == "Hello there", "it shows")
	ctx.shell.toast("")
	eq(ctx.shell.toast_label.text, "Hello there", "an empty one changes nothing")
	await ctx.shell.get_tree().create_timer(0.8).timeout
	check(not ctx.shell.toast_panel.visible, "and it goes")
	# it stays above a screen that opens after it
	ctx.shell.toast("Again", "warn")
	ctx.shell.open_settings()
	eq(ctx.shell.get_child(ctx.shell.get_child_count() - 1), ctx.shell.toast_panel, "on top of the screens")
	_done(ctx)


# ---------------------------------------------------------------- settings --

func test_the_volumes_are_kept_and_applied_at_once() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_settings()
	await HudKit.settle()
	for key in ["master", "sfx", "ambience", "ui"]:
		near(screen.sliders[key].value, 1.0, 0.0001, "%s starts at full" % key)
		eq(screen.percents[key].text, "100%", "and says so")
	screen.sliders["master"].value = 0.4
	near(Prefs.number("audio", "master"), 0.4, 0.0001, "the master volume is kept")
	near(AudioServer.get_bus_volume_db(0), Buses.to_db(0.4), 0.01, "and heard at once")
	eq(screen.percents["master"].text, "40%", "the number follows")
	screen.sliders["sfx"].value = 0.0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "effects at nothing are muted")
	screen.sliders["ambience"].value = 0.55
	near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")), Buses.to_db(0.55), 0.01, "ambience on its own bus")
	screen.sliders["ui"].value = 0.25
	near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI")), Buses.to_db(0.25), 0.01, "the interface on its own")
	Prefs.forget()
	near(Prefs.number("audio", "master"), 0.4, 0.0001, "kept in the file: master")
	near(Prefs.number("audio", "sfx"), 0.0, 0.0001, "effects")
	near(Prefs.number("audio", "ambience"), 0.55, 0.0001, "ambience")
	near(Prefs.number("audio", "ui"), 0.25, 0.0001, "interface")
	# a screen opened afresh shows what was kept
	screen.close()
	var again = ctx.shell.open_settings()
	await HudKit.settle()
	near(again.sliders["master"].value, 0.4, 0.0001, "master as it was left")
	near(again.sliders["sfx"].value, 0.0, 0.0001, "effects")
	eq(again.percents["ambience"].text, "55%", "the words too")
	_done(ctx)


func test_a_volume_slider_works_from_the_keyboard_and_shows_where_it_is() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_settings()
	await HudKit.settle()
	var master: HSlider = screen.sliders["master"]
	eq(Fakes.focused(), master, "the keyboard starts on the first slider")
	var ring: PanelContainer = master.get_parent().get_parent()
	var lit: StyleBoxFlat = ring.get_theme_stylebox("panel")
	eq(lit.border_color, ctx.hud.ACCENT, "its row has a gold ring while it has the keyboard")
	Fakes.key(KEY_LEFT)
	near(master.value, 0.95, 0.0001, "Left turns it down a step")
	near(Prefs.number("audio", "master"), 0.95, 0.0001, "and keeps it")
	Fakes.key(KEY_RIGHT)
	near(master.value, 1.0, 0.0001, "Right turns it up")
	Fakes.key(KEY_DOWN)
	check(Fakes.focused() != master, "Down moves on to the next control")
	var unlit: StyleBoxFlat = ring.get_theme_stylebox("panel")
	eq(unlit.border_color.a, 0.0, "and the ring is gone")
	check(not master.scrollable, "the wheel does not move a slider in passing")
	_done(ctx)


func test_the_interface_size_goes_in_steps_from_80_to_150() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_settings()
	await HudKit.settle()
	eq(screen.scale_value.text, "100%", "normal to begin with")
	var want := [1.1, 1.2, 1.3, 1.4, 1.5, 1.5]
	var texts := ["110%", "120%", "130%", "140%", "150%", "150%"]
	for i in want.size():
		screen.scale_plus.pressed.emit()
		near(Prefs.number("ui", "scale"), want[i], 0.0001, "step up %d" % i)
		eq(screen.scale_value.text, texts[i], "says %s" % texts[i])
	check(screen.scale_plus.disabled, "at 150% there is no more")
	check(not screen.scale_minus.disabled, "but there is less")
	check(ctx.main.names().count("apply_settings") >= 5, "the game was told each time: %d" % ctx.main.names().count("apply_settings"))
	for i in 7:
		screen.scale_minus.pressed.emit()
	near(Prefs.number("ui", "scale"), 0.8, 0.0001, "down to 80%")
	eq(screen.scale_value.text, "80%", "says so")
	check(screen.scale_minus.disabled and not screen.scale_plus.disabled, "and no further down")
	Prefs.forget()
	near(Prefs.number("ui", "scale"), 0.8, 0.0001, "kept in the file")
	# a window too small for the size says so
	Prefs.set_value("ui", "scale", 1.4)
	ctx.main.scale_now = 1.0
	screen._refresh_scale()
	check(screen.scale_note.visible, "a window that cannot give 140% says so")
	ctx.main.scale_now = 1.4
	screen._refresh_scale()
	check(not screen.scale_note.visible, "and does not when it can")
	_done(ctx)


func test_hints_reduce_motion_and_fullscreen_are_switches() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_settings()
	await HudKit.settle()
	eq(screen.toggles.keys(), ["hints", "reduce_motion", "fullscreen"], "three switches")
	eq(screen.toggles["hints"].text, "On", "hints are on")
	eq(screen.toggles["reduce_motion"].text, "Off", "reduce motion is off")
	eq(screen.toggles["fullscreen"].text, "Off", "fullscreen is off")
	check(screen.toggles["hints"].button_pressed, "hints: pressed")
	for key in ["hints", "reduce_motion", "fullscreen"]:
		var before: int = ctx.main.names().count("apply_settings")
		var was: bool = Prefs.on("ui", key)
		screen.toggles[key].button_pressed = not was
		eq(Prefs.on("ui", key), not was, "%s flipped in the file's memory" % key)
		eq(screen.toggles[key].text, "Off" if was else "On", "%s says the new state" % key)
		eq(ctx.main.names().count("apply_settings"), before + 1, "%s: the game was told" % key)
		Prefs.forget()
		eq(Prefs.on("ui", key), not was, "%s kept in the file" % key)
		screen.toggles[key].button_pressed = was
		eq(Prefs.on("ui", key), was, "%s flipped back" % key)
	_done(ctx)


func test_there_is_no_fullscreen_switch_on_the_web() -> void:
	var ctx := Fakes.build()
	ctx.shell.web = true
	var screen = ctx.shell.open_settings()
	check(not screen.toggles.has("fullscreen"), "no fullscreen switch in a browser")
	check(screen.toggles.has("hints") and screen.toggles.has("reduce_motion"), "the others are there")
	_done(ctx)


func test_less_motion_stills_the_bell_on_the_title() -> void:
	var ctx := Fakes.build()
	ctx.shell.show_title()
	check(ctx.shell.title.bell.sway, "the bell sways")
	var screen = ctx.shell.open_settings()
	await HudKit.settle()
	screen.toggles["reduce_motion"].button_pressed = true
	check(not ctx.shell.title.bell.sway, "with less motion it hangs still")
	screen.toggles["reduce_motion"].button_pressed = false
	check(ctx.shell.title.bell.sway, "and sways again")
	_done(ctx)


func test_the_settings_screen_closes_with_back_and_esc() -> void:
	var ctx := Fakes.build()
	var screen = ctx.shell.open_settings()
	await HudKit.settle()
	screen.back_button.pressed.emit()
	eq(ctx.shell.kinds(), [], "Back closes it")
	ctx.shell.open_settings()
	Fakes.key(KEY_ESCAPE)
	eq(ctx.shell.kinds(), [], "Esc closes it")
	_done(ctx)
