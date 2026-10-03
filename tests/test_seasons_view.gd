extends "res://tests/case.gd"
## Round 10, what the player sees and chooses of the seasons (the rules are tests/test_seasons.gd, the core's): the
## new-game menu's second choice, how it reaches the run (the meta, `--campaign`, `--season=N`), the clock's
## day, its sun and dusk text and its temperature, the light and the snow, the end of the game, the one-line tip
## of each season and the words of the help.

const Kit := preload("res://tests/hud_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const MenuFakes := preload("res://tests/menu_fakes.gd")
const Main := preload("res://scripts/main.gd")
const NewGameMenu := preload("res://scripts/ui/new_game_menu.gd")
const Prefs := preload("res://scripts/prefs.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Lighting := preload("res://scripts/render/lighting.gd")
const Snow := preload("res://scripts/render/snow.gd")

const WIDTHS := [700, 980, 1280, 1920]


func _labels(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_labels(c, out)
	return out


# ------------------------------------------------------------------ the new-game menu --

func _menu(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := MenuFakes.build(width, height)
	ctx["screen"] = ctx.shell.open_new_game()
	await Kit.settle()
	return ctx


func test_the_menu_offers_autumn_and_the_campaign() -> void:
	var ctx: Dictionary = await _menu()
	var screen = ctx.screen
	eq(screen.length_cards.size(), 2, "two lengths to choose from")
	check(not screen.campaign, "Autumn, the game as it is, is the one chosen to begin with")
	check(screen.length_cards[0].button_pressed and not screen.length_cards[1].button_pressed, "its card is the one pressed")
	var autumn := Kit.texts(screen.length_cards[0])
	var campaign := Kit.texts(screen.length_cards[1])
	eq(autumn, ["Autumn: thirty nights", "Hold the wall for thirty nights."], "the first card: its name and its line")
	eq(campaign, ["Campaign: the four seasons", "Autumn, Winter, Spring and Summer, each with its own Big Night."], "the second")
	check(Kit.texts(screen.body).has("LENGTH"), "under a heading of its own: %s" % str(Kit.texts(screen.body)))
	MenuFakes.free_all(ctx)


func test_the_length_chosen_is_what_the_game_is_asked_for() -> void:
	var ctx: Dictionary = await _menu()
	var screen = ctx.screen
	screen.seed_edit.text = "4242"
	screen.seed_edit.text_changed.emit("4242")
	Kit.click_on(screen.start_button)
	eq(ctx.main.last("start_run"), ["start_run", 1, 4242, 5], "Start with what it showed: Autumn, asked for as it always was")
	ctx.main.calls.clear()
	var again = ctx.shell.open_new_game()
	await Kit.settle()
	Kit.click_on(again.length_cards[1])
	check(again.campaign, "a click on the campaign")
	check(again.length_cards[1].button_pressed and not again.length_cards[0].button_pressed, "lights its card and no other")
	again.seed_edit.text = "17"
	again.seed_edit.text_changed.emit("17")
	Kit.click_on(again.start_button)
	eq(ctx.main.last("start_run"), ["start_run", 1, 17, 5, true], "and asks for the campaign")
	MenuFakes.free_all(ctx)


func test_the_length_can_be_chosen_with_the_keyboard() -> void:
	var ctx: Dictionary = await _menu()
	var screen = ctx.screen
	screen.length_cards[1].grab_focus()
	MenuFakes.key(KEY_ENTER)
	check(screen.campaign, "Enter on the campaign's card picks it")
	screen.length_cards[0].grab_focus()
	MenuFakes.key(KEY_SPACE)
	check(not screen.campaign, "Space on Autumn's picks that")
	var focus_order: Array = []
	var f: Control = screen.length_cards[0]
	for i in 3:
		focus_order.append(f)
		f = f.find_next_valid_focus()
	check(focus_order.has(screen.length_cards[1]), "Tab reaches both cards")
	MenuFakes.free_all(ctx)


func test_the_last_length_chosen_is_remembered_like_the_crew() -> void:
	var ctx: Dictionary = await _menu()
	ctx.screen.length_cards[1].pressed.emit()
	ctx.screen.start_button.pressed.emit()
	eq(Prefs.get_value("ui", "campaign", false), true, "it was kept")
	var again = ctx.shell.open_new_game()
	await Kit.settle()
	check(again.campaign and again.length_cards[1].button_pressed, "and is the one chosen next time, its card pressed")
	Prefs.set_value("ui", "campaign", "yes please")
	var odd = ctx.shell.open_new_game()
	await Kit.settle()
	check(not odd.campaign, "a stored length that is not a yes or a no is Autumn")
	MenuFakes.free_all(ctx)


func test_the_menu_fits_and_works_at_every_width() -> void:
	for w in WIDTHS:
		var h := 800 if w < 1500 else 1080
		var ctx: Dictionary = await _menu(w, h)
		var screen = ctx.screen
		var win := Rect2(0, 0, w, h)
		check(win.encloses(Kit.rect(screen.panel).grow(-0.5)), "%d: the panel is in the window: %s" % [w, str(Kit.rect(screen.panel))])
		screen.scroll.ensure_control_visible(screen.length_cards[1])
		await Kit.settle()
		var autumn: Rect2 = Kit.rect(screen.length_cards[0])
		var long: Rect2 = Kit.rect(screen.length_cards[1])
		check(autumn.size.x >= 120.0 and long.size.x >= 120.0, "%d: the cards are wide enough to read: %s %s" % [w, str(autumn.size), str(long.size)])
		check(Kit.overlaps({"autumn": autumn, "campaign": long}).is_empty(), "%d: the two cards do not overlap" % w)
		for card in screen.length_cards:
			for l in _labels(card):
				check(l.get_theme_font_size("font_size") >= 12, "%d: '%s' is 12 px or more" % [w, l.text])
			# every word of a card is inside the card (nothing is cut off)
			for l in _labels(card):
				check(Kit.rect(card).grow(1.0).encloses(Kit.rect(l)), "%d: '%s' is inside its card" % [w, l.text])
		# with the mouse: a click on the campaign picks it, a click on Autumn takes it back
		Kit.click_on(screen.length_cards[1])
		check(screen.campaign, "%d: a click picks the campaign" % w)
		Kit.click_on(screen.length_cards[0])
		check(not screen.campaign, "%d: and a click on Autumn picks that" % w)
		MenuFakes.free_all(ctx)


# ---------------------------------------------------------------- how it reaches the run --

func test_a_new_run_asked_for_the_campaign_leaves_it_in_the_meta() -> void:
	var g := MenuFakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	var got: Array = []
	main.restart = func(meta): got.append(meta)
	main.start_run(2, 4242, 3)
	eq(got.back(), {"difficulty": 2, "seed": 4242, "crew": 3}, "no length asked for: nothing about it in the choice (it is Autumn)")
	main.start_run(2, 4242, 3, false)
	eq(got.back(), {"difficulty": 2, "seed": 4242, "crew": 3}, "Autumn asked for: the same")
	main.start_run(1, 5, 6, true)
	eq(got.back(), {"difficulty": 1, "seed": 5, "crew": 6, "campaign": true}, "the campaign is in it")
	main.start_run(1, 5, 0, true)
	eq(got.back(), {"difficulty": 1, "seed": 5, "campaign": true}, "with no crew asked for as well")
	await MenuFakes.leave(g)


func test_the_campaign_comes_from_the_command_line() -> void:
	check(not Main.campaign_from_args([]), "no flag: Autumn")
	check(not Main.campaign_from_args(["--shot=a.png", "--new=1", "--seed=4", "--crew=3"]), "the other flags leave it Autumn")
	check(Main.campaign_from_args(["--campaign"]), "--campaign")
	check(Main.campaign_from_args(["--shot=a.png", "--campaign", "--crew=3"]), "among others")
	check(Main.campaign_from_args(["--campaign=1"]) and Main.campaign_from_args(["--campaign=yes"]), "--campaign=1 and =yes")
	check(not Main.campaign_from_args(["--campaign=0"]) and not Main.campaign_from_args(["--campaign=no"]), "--campaign=0 and =no are Autumn")
	check(Main.campaign_from_args(["--season=2"]), "--season=N implies the campaign")
	check(not Main.campaign_from_args(["--season=lots"]), "words that are not a season are no choice")
	eq(Main.season_from_args([]), -1, "no season asked for")
	eq(Main.season_from_args(["--campaign"]), -1, "--campaign alone is no season")
	eq(Main.season_from_args(["--season=0"]), 0, "--season=0")
	eq(Main.season_from_args(["--season=1"]), 1, "--season=1")
	eq(Main.season_from_args(["--season=3"]), 3, "--season=3")
	eq(Main.season_from_args(["--season=7"]), 3, "past the last is the last")
	eq(Main.season_from_args(["--season=-2"]), 0, "before the first is the first")
	eq(Main.season_from_args(["--season=winter"]), 1, "a season by its name")
	eq(Main.season_from_args(["--season=Summer"]), 3, "in any case")
	eq(Main.season_from_args(["--season=lots"]), -1, "words that are not a season are no choice")


func test_the_meta_makes_a_campaign_and_nothing_else_does() -> void:
	for case in [
		[{"difficulty": 1, "seed": 7, "crew": 3, "campaign": true}, true, "a run asked for the campaign"],
		[{"difficulty": 1, "seed": 7, "crew": 3}, false, "a run that asked for nothing"],
		[{"difficulty": 1, "seed": 7, "crew": 6, "campaign": false}, false, "a run that said no"],
		[{"title": true}, false, "the title's yard"],
		[{"tutorial": true, "step": 0, "campaign": true}, false, "Orientation Day, whatever the meta says"],
	]:
		var g := MenuFakes.game(case[0])
		var main = g.main
		eq(main.sim.seasons.campaign, case[1], "%s: campaign" % case[2])
		eq(main.sim.seasons.index, 0, "%s: it begins in Autumn" % case[2])
		eq(main.sim.scenario.total_days(), 30, "%s: the first season is thirty days" % case[2])
		await MenuFakes.leave(g)


func test_a_season_asked_for_puts_the_game_at_its_first_morning() -> void:
	var g := MenuFakes.game({"difficulty": 1, "seed": 7, "crew": 3, "campaign": true})
	var main = g.main
	for i in 4:
		var sim = main.sim
		main.stage_season(i)
		eq(sim.seasons.index, i, "season %d: the season" % i)
		check(sim.seasons.campaign, "season %d: a campaign" % i)
		eq(sim.day, [1, 31, 55, 79][i], "season %d: its first day" % i)
		eq(sim.phase, "day", "season %d: it is day (the morning is after the dawn)" % i)
		check(sim.hour >= sim.seasons.dawn_hour() and sim.hour >= 7.0, "season %d: at %.1f, after the dawn at %.1f" % [i, sim.hour, sim.seasons.dawn_hour()])
		var day_before: int = sim.day
		for k in 150:
			main._sim_step()
		eq(sim.day, day_before, "season %d: and a few game minutes on it is still that day (no day is skipped)" % i)
		eq(sim.phase, "day", "season %d: still day" % i)
	await MenuFakes.leave(g)


# ------------------------------------------------------------------------- the clock --

## A HUD over a campaign at the first morning of season `i` (the day is the scenario's, which a test sets by hand).
func _clock(i: int, width: int = 1280, height: int = 800, campaign: bool = true) -> Dictionary:
	var ctx := Kit.build(width, height)
	if campaign:
		ctx.sim.seasons.jump_to(i)
		ctx.sim.scenario.today = ctx.sim.day
	return ctx


## Puts the game's clock at `hour` (the phase is the season's own).
func _at(ctx: Dictionary, hour: float, speed: int = 1) -> void:
	var sim = ctx.sim
	sim.minutes = hour * 60.0
	sim.phase = sim.seasons.phase_at(sim.minutes)
	Kit.update(ctx, speed)


func test_the_day_in_autumn_reads_as_it_always_did() -> void:
	var ctx := _clock(0, 1280, 800, false)
	ctx.sim.scenario.today = 7
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "DAY 7 OF 30", "a game that is not a campaign: the old words")
	ctx.sim.scenario.today = 30
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "DAY 30 OF 30", "to its last day")
	Kit.free_all(ctx)
	var narrow := _clock(0, 700, 800, false)
	narrow.sim.scenario.today = 7
	Kit.update(narrow)
	await Kit.settle()
	Kit.update(narrow)
	eq(narrow.hud.day_label.text, "DAY 7/30", "and the short form in a narrow window")
	Kit.free_all(narrow)


func test_the_day_in_a_campaign_names_the_season_and_the_day_in_it() -> void:
	var ctx := _clock(1)
	var sim = ctx.sim
	sim.scenario.today = 35
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "WINTER, DAY 5 OF 24", "Winter, its fifth day (the thirty-fifth of the game)")
	sim.scenario.today = 54
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "WINTER, DAY 24 OF 24", "its last")
	sim.seasons.jump_to(0)
	sim.scenario.today = 12
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "AUTUMN, DAY 12 OF 30", "Autumn of a campaign names itself too, thirty days long")
	sim.seasons.jump_to(2)
	sim.scenario.today = 55
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "SPRING, DAY 1 OF 24", "Spring")
	sim.seasons.jump_to(3)
	sim.scenario.today = 102
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "SUMMER, DAY 24 OF 24", "Summer, the last day of the game")
	Kit.free_all(ctx)
	var narrow := _clock(1, 700, 800)
	narrow.sim.scenario.today = 35
	Kit.update(narrow)
	await Kit.settle()
	Kit.update(narrow)
	eq(narrow.hud.day_label.text, "WINTER 5/24", "the short form in a narrow window")
	check(narrow.hud.day_label.text.length() < "WINTER, DAY 5 OF 24".length(), "which is shorter")
	Kit.free_all(narrow)


func test_the_clock_holds_the_longest_day_at_every_size_paused_or_not() -> void:
	for wh in [[700, 700], [980, 700], [1280, 800], [1920, 1080]]:
		for state in [[3, "SUMMER", 102, 21.5], [3, "SUMMER", 102, 12.0], [1, "WINTER", 54, 3.0], [2, "SPRING", 78, 6.0]]:
			var ctx := _clock(int(state[0]), wh[0], wh[1])
			ctx.sim.scenario.today = state[2]
			_at(ctx, float(state[3]), 1)
			await Kit.settle()
			_at(ctx, float(state[3]), 1)
			await Kit.settle()
			var running: Rect2 = Kit.rect(ctx.hud.clock)
			var win := Rect2(0, 0, wh[0], wh[1])
			check(win.encloses(running.grow(-0.5)), "%s: the clock is in the window: %s" % [str(wh), str(running)])
			_at(ctx, float(state[3]), 0)
			await Kit.settle()
			_at(ctx, float(state[3]), 0)
			await Kit.settle()
			var paused: Rect2 = Kit.rect(ctx.hud.clock)
			near(paused.end.x, running.end.x, 0.5, "%s %s: the same right edge paused" % [str(wh), ctx.hud.day_label.text])
			near(paused.size.x, running.size.x, 0.5, "%s %s: the same width paused" % [str(wh), ctx.hud.day_label.text])
			near(paused.size.y, running.size.y, 0.5, "%s %s: the same height paused" % [str(wh), ctx.hud.day_label.text])
			var parts := {"day": Kit.rect(ctx.hud.day_label), "pill": Kit.rect(ctx.hud.paused_pill), "chip": Kit.rect(ctx.hud.phase_chip)}
			eq(Kit.overlaps(parts), [], "%s: the day, the pill and the phase do not overlap when paused" % str(wh))
			_at(ctx, float(state[3]), 1)
			await Kit.settle()
			_at(ctx, float(state[3]), 1)
			await Kit.settle()
			eq(Kit.overlaps({"day": Kit.rect(ctx.hud.day_label), "chip": Kit.rect(ctx.hud.phase_chip)}), [], "%s: nor the day and the phase while it runs" % str(wh))
			Kit.free_all(ctx)


func test_the_sun_and_dusk_text_counts_to_the_seasons_hours() -> void:
	var ctx := _clock(0, 1280, 800, false)
	_at(ctx, 12.0)
	eq(ctx.hud.until_label.text, "Dusk in 7h 00m", "Autumn at noon: dusk at 19:00")
	_at(ctx, 20.0)
	eq(ctx.hud.until_label.text, "Dawn in 10h 30m", "Autumn at 20:00: the day at 6:30")
	Kit.free_all(ctx)
	for case in [[1, 12.0, "Dusk in 4h 30m"], [1, 20.0, "Dawn in 11h 30m"], [1, 8.0, "Dusk in 8h 30m"],
			[2, 12.0, "Dusk in 7h 30m"], [2, 22.0, "Dawn in 8h 00m"],
			[3, 12.0, "Dusk in 9h 00m"], [3, 23.0, "Dawn in 6h 30m"]]:
		var camp := _clock(int(case[0]))
		# the dawn of the first morning is the season's from the dusk before (see seasons.on_dusk)
		camp.sim.seasons.on_dusk()
		_at(camp, float(case[1]))
		eq(camp.hud.until_label.text, case[2], "%s at %.0f:00" % [camp.sim.seasons.current().name, case[1]])
		Kit.free_all(camp)
	# in a campaign's Autumn the text is the old one, too
	var a := _clock(0)
	_at(a, 12.0)
	eq(a.hud.until_label.text, "Dusk in 7h 00m", "Autumn of a campaign")
	Kit.free_all(a)


func test_the_temperature_follows_the_season_in_a_campaign_and_says_the_weather() -> void:
	var ctx := _clock(0, 1280, 800, false)
	_at(ctx, 15.0)
	eq(ctx.hud.temp_label.text, "17°C, clear", "Autumn, not a campaign: the old formula")
	_at(ctx, 3.0)
	eq(ctx.hud.temp_label.text, "9°C, clear", "and at night")
	ctx.sim.weather = "rain"
	_at(ctx, 3.0)
	eq(ctx.hud.temp_label.text, "9°C, rain", "with the rain")
	Kit.free_all(ctx)
	var w := _clock(1)
	_at(w, 15.0)
	eq(w.hud.temp_label.text, "3°C, clear", "Winter at 15:00: the season's mean and swing")
	_at(w, 3.0)
	eq(w.hud.temp_label.text, "-5°C, clear", "and below freezing at 3:00")
	w.sim.weather = "snow"
	_at(w, 3.0)
	eq(w.hud.temp_label.text, "-5°C, snow", "snow shows as snow")
	var s := _clock(3)
	_at(s, 15.0)
	eq(s.hud.temp_label.text, "30°C, clear", "Summer at 15:00")
	Kit.free_all(s)
	Kit.free_all(w)


func test_the_clocks_strip_follows_the_seasons_hours() -> void:
	var ctx := _clock(0, 1280, 800, false)
	Kit.update(ctx)
	var strip = ctx.hud.strip
	for h in [0.0, 5.0, 6.5, 12.0, 19.0, 20.5, 23.9]:
		check(strip.colour_at(h).is_equal_approx(strip.gradient.sample(h / 24.0)), "not a campaign: the colour at %.1f is the day's own" % h)
	Kit.free_all(ctx)
	var w := _clock(1)
	w.sim.seasons.on_dusk()
	Kit.update(w)
	var strip2 = w.hud.strip
	check(strip2.colour_at(16.5).is_equal_approx(strip2.gradient.sample(19.0 / 24.0)), "Winter: the dusk begins at 16:30 and the strip is as the standard day at 19:00")
	check(strip2.colour_at(7.5).is_equal_approx(strip2.gradient.sample(6.5 / 24.0)), "and the dawn is at 7:30")
	check(not strip2.colour_at(18.0).is_equal_approx(strip2.gradient.sample(18.0 / 24.0)), "so 18:00 is deep in the dusk here, not the evening of Autumn")
	Kit.free_all(w)


func test_the_forecast_of_a_season_that_is_not_the_last_calls_the_night_the_big_one() -> void:
	var told := Kit.forecast({"big": true, "total": 120})
	var a := _clock(0, 1280, 800, false)
	a.sim.tactics.told = told
	_at(a, 17.5)
	eq(a.hud.forecast_label.text, "The last night: about 120, from everywhere", "Autumn alone: the last night, as ever")
	Kit.free_all(a)
	for i in 4:
		var c := _clock(i)
		c.sim.tactics.told = told
		_at(c, 17.5 if i != 1 else 15.5)
		eq(c.hud.forecast_label.text, "The last night: about 120, from everywhere" if i == 3 else "The Big Night: about 120, from everywhere", "season %d" % i)
		Kit.free_all(c)


# ------------------------------------------------------------------------- the light --

## A lighting rig over a game's lights, as the world has it: {"rig", "holder", "game", "cm"}.
func _rig(campaign: bool = true, season: int = 0) -> Dictionary:
	var game := Helpers.make(1, 1, 6, campaign)
	if campaign:
		game.sim.seasons.jump_to(season)
		# (the dawn of the first morning is the old season's until a dusk comes: the light follows the season's day)
		game.sim.seasons.on_dusk()
	var holder := Node2D.new()
	Engine.get_main_loop().root.add_child(holder)
	var cm := CanvasModulate.new()
	holder.add_child(cm)
	var rig := Lighting.new()
	holder.add_child(rig)
	rig.setup(game.data, cm)
	rig.seasons = game.sim.seasons
	return {"rig": rig, "holder": holder, "game": game, "cm": cm}


func _free_rig(ctx: Dictionary) -> void:
	ctx.holder.free()
	ctx.game.world.free()


func test_autumn_is_lit_as_it_always_was() -> void:
	var old := _rig(false)
	var camp := _rig(true, 0)
	var bare := _rig(false)
	bare.rig.seasons = null
	for h in [0.0, 4.0, 5.6, 6.4, 7.2, 12.0, 17.6, 18.4, 19.0, 19.6, 20.3, 21.0, 23.5]:
		for ctx in [old, camp, bare]:
			ctx.rig.update(h, h >= 19.0 or h < 6.0, 1.0, [])
		var want: Color = bare.cm.color
		check(old.cm.color.is_equal_approx(want), "not a campaign, %.1f: the colour of the sky as it was (%s, not %s)" % [h, str(old.cm.color), str(want)])
		check(camp.cm.color.is_equal_approx(want), "Autumn of a campaign, %.1f: the same (%s, not %s)" % [h, str(camp.cm.color), str(want)])
		near(old.rig.lamp_level, bare.rig.lamp_level, 0.0001, "%.1f: the lamps as they were" % h)
		near(camp.rig.lamp_level, bare.rig.lamp_level, 0.0001, "%.1f: and in the campaign's Autumn" % h)
		near(camp.rig.dark, bare.rig.dark, 0.0001, "%.1f: as dark" % h)
	bare.rig.update(12.0, false, 1.0, [])
	check(bare.cm.color.is_equal_approx(Lighting.sky_at(12.0)), "noon in Autumn is the keyframe's own colour: no tint")
	camp.rig.update(12.0, false, 1.0, [])
	check(camp.cm.color.is_equal_approx(Lighting.sky_at(12.0)), "and in the campaign's Autumn: its tint is white")
	for ctx in [old, camp, bare]:
		_free_rig(ctx)


func test_winters_light_is_cold_and_its_dusk_comes_early() -> void:
	var w := _rig(true, 1)
	var a := _rig(false)
	var tint: Color = w.game.sim.seasons.tint()
	w.rig.update(12.0, false, 1.0, [])
	a.rig.update(12.0, false, 1.0, [])
	var noon: Color = Lighting.sky_at(w.game.sim.seasons.light_hour(12.0)) * tint
	check(w.cm.color.is_equal_approx(noon), "noon in Winter is the day's colour through the season's tint: %s, not %s" % [str(w.cm.color), str(noon)])
	check(w.cm.color.b > w.cm.color.r and w.cm.color.r < a.cm.color.r - 0.1, "colder (bluer, less red) than Autumn's noon: %s against %s" % [str(w.cm.color), str(a.cm.color)])
	check(not w.cm.color.is_equal_approx(a.cm.color), "and not the colour of Autumn's noon")
	# the dusk begins at 16:30 here: the sky at 16:30 is the standard day's at 19:00 (through the tint)
	w.rig.update(16.5, true, 1.0, [])
	var standard: Color = Lighting.sky_at(19.0) * tint
	check(w.cm.color.is_equal_approx(standard), "16:30 in Winter is the standard dusk at 19:00: %s, not %s" % [str(w.cm.color), str(standard)])
	check(w.rig.lamp_level > 0.5, "the lamps are on at 16:30 in Winter: %.2f" % w.rig.lamp_level)
	a.rig.update(16.5, false, 1.0, [])
	check(a.rig.lamp_level < 0.01 and a.cm.color.is_equal_approx(Lighting.sky_at(16.5)), "and are not in Autumn at the same hour (%.2f)" % a.rig.lamp_level)
	# the day's first light is the standard dawn: 7:30 here is 6:30 of Autumn
	w.rig.update(7.5, false, 1.0, [])
	check(w.cm.color.is_equal_approx(Lighting.sky_at(6.5) * tint), "7:30 in Winter is the dawn of the standard day: %s" % str(w.cm.color))
	# a night stays a night until the dawn
	w.rig.update(3.0, true, 1.0, [])
	check(w.rig.lamp_level > 0.99 and w.rig.floods_on, "3:00 is night, the floodlights are on")
	w.rig.update(7.0, false, 1.0, [])
	check(w.rig.dark > 0.1, "and 7:00, before the dawn, is still dark (%.2f)" % w.rig.dark)
	_free_rig(w)
	_free_rig(a)


func test_every_season_has_a_light_of_its_own() -> void:
	var seen: Array = []
	for i in 4:
		var ctx := _rig(true, i)
		ctx.rig.update(12.0, false, 1.0, [])
		var tint: Color = ctx.game.sim.seasons.tint()
		var want: Color = Lighting.sky_at(ctx.game.sim.seasons.light_hour(12.0)) * tint
		check(ctx.cm.color.is_equal_approx(want), "%s: noon is the day's colour through the tint of its season: %s" % [ctx.game.sim.seasons.current().name, str(ctx.cm.color)])
		for c in seen:
			check(not ctx.cm.color.is_equal_approx(c) or i == 0, "%s: no two seasons have the same noon" % ctx.game.sim.seasons.current().name)
		seen.append(ctx.cm.color)
		_free_rig(ctx)
	check(seen[2].g > seen[2].r and seen[2].g > seen[2].b, "Spring a little green: %s" % str(seen[2]))
	check(seen[3].r > seen[3].b, "Summer warm: %s" % str(seen[3]))
	check(seen[1].b > seen[1].r, "Winter cold: %s" % str(seen[1]))


func test_the_fog_and_the_blackout_still_work_in_a_season() -> void:
	var ctx := _rig(true, 1)
	var rig = ctx.rig
	for i in 200:
		rig.update(22.0, true, i * 0.05, [], {"fog": 1.0, "blackout": false})
	check(rig.fog > 0.99 and rig.veil.visible, "the fog comes in Winter")
	for i in 200:
		rig.update(22.0, true, 10.0 + i * 0.05, [], {"fog": 0.0, "blackout": true})
	check(rig.power < 0.01 and rig.lamp_level < 0.01, "and the blackout takes the lamps")
	_free_rig(ctx)


# ------------------------------------------------------------------------------- snow --

func test_snow_comes_on_a_snow_day_and_goes_with_it() -> void:
	var snow := Snow.new()
	Engine.get_main_loop().root.add_child(snow)
	snow.size = Vector2(1280, 800)
	check(not snow.falling() and not snow.visible, "no snow to begin with")
	for i in 120:
		snow.follow({"fog": 0.0, "rain": true, "snow": false, "blackout": false}, true, 0.0, 1.0 / 30.0)
	check(not snow.falling(), "rain is not snow")
	for i in 150:
		snow.follow({"snow": true}, true, 0.0, 1.0 / 30.0)
	check(snow.falling() and snow.visible and snow.intensity > 0.99, "snow on a snow day: %.2f" % snow.intensity)
	check(snow.ground > 0.99, "with the ground under it deep (%.2f)" % snow.ground)
	for i in 300:
		snow.follow({"snow": false}, true, 0.0, 1.0 / 30.0)
	check(not snow.falling() and not snow.visible, "gone when the day is clear")
	check(snow.ground > 0.5 and snow.ground < 0.6, "but Winter's ground keeps a light cover (%.2f)" % snow.ground)
	for i in 300:
		snow.follow({"snow": false}, false, 0.0, 1.0 / 30.0)
	check(snow.ground == 0.0, "and none outside a snowy season")
	snow.free()


func test_the_flakes_are_slow_wide_soft_and_sway() -> void:
	var snow := Snow.new()
	Engine.get_main_loop().root.add_child(snow)
	snow.size = Vector2(1280, 800)
	for i in 100:
		snow.follow({"snow": true}, true, 0.0, 1.0 / 30.0)
	# slow: a rain streak is 600 pixels a second or more
	check(Snow.fall_speed(1.0) <= 80.0 and Snow.fall_speed(0.0) >= 10.0, "slow: %.0f to %.0f px a second" % [Snow.fall_speed(0.0), Snow.fall_speed(1.0)])
	# wide: soft dots, not streaks (a dot is as wide as it is tall, and bigger than a speck)
	check(Snow.flake_size(0.0) >= 3.0 and Snow.flake_size(1.0) >= 8.0, "wide: %.0f to %.0f px across" % [Snow.flake_size(0.0), Snow.flake_size(1.0)])
	check(Snow.flake_size(1.0) > Snow.flake_size(0.0), "the near ones are bigger")
	# white: by day pure white, by night dimmed towards the blue of the night
	check(Snow.flake_color(0.0).is_equal_approx(Color.WHITE), "white by day")
	var night := Snow.flake_color(0.6)
	check(night.b > night.r and night.get_luminance() < 0.9 and night.get_luminance() > 0.45, "and dim, a little blue, at night: %s" % str(night))
	# the flakes fall, drift sideways and sway
	var f: Dictionary = snow.flakes[0]
	f.z = 0.7
	f.x = 0.5
	f.y = 0.1
	var ys: Array = []
	var xs: Array = []
	var offs: Array = []
	for i in 240:
		snow.advance(1.0 / 20.0)
		ys.append(float(f.y))
		xs.append(float(f.x))
		offs.append(snow.screen_pos(f).x - float(f.x) * snow.size.x)
	check(ys[10] > ys[0] or ys[10] < 0.1, "it falls")
	var fall_px := (float(ys[19]) - float(ys[0])) * snow.size.y
	check(fall_px > 10.0 and fall_px < 120.0, "about %.0f px in a second: slowly" % fall_px)
	check(float(xs[100]) > float(xs[0]) or float(xs[100]) < 0.1, "the wind carries it sideways")
	var turns := 0
	for i in range(2, offs.size()):
		if (float(offs[i]) - float(offs[i - 1])) * (float(offs[i - 1]) - float(offs[i - 2])) < 0.0:
			turns += 1
	check(turns >= 3, "and it sways to one side and the other: %d turns in twelve seconds" % turns)
	var widest := 0.0
	for o in offs:
		widest = maxf(widest, absf(float(o)))
	check(widest > 6.0, "by a few pixels: %.1f" % widest)
	# every flake stays on the screen's square
	for k in snow.flakes:
		check(k.x >= 0.0 and k.x <= 1.0 and k.y >= 0.0 and k.y <= 1.0, "a flake is inside the screen")
	snow.free()


func test_the_snow_waits_with_the_game_and_calms_under_reduced_motion() -> void:
	Prefs.path = "user://prefs_test.cfg"
	Prefs.reset()
	var snow := Snow.new()
	Engine.get_main_loop().root.add_child(snow)
	snow.size = Vector2(1280, 800)
	for i in 100:
		snow.follow({"snow": true}, true, 0.0, 1.0 / 30.0)
	var y0: float = snow.flakes[3].y
	var t0 := snow.screen_pos(snow.flakes[3])
	snow.advance(0.0)
	eq(float(snow.flakes[3].y), y0, "no game time, no fall")
	snow.advance(1.0)
	var moved: float = (float(snow.flakes[3].y) - y0) * 800.0
	if moved < 0.0:
		moved += 800.0
	Prefs.set_value("ui", "reduce_motion", true)
	snow.advance(1.0)
	var calm: float = (float(snow.flakes[3].y) - y0) * 800.0 - moved
	if calm < 0.0:
		calm += 800.0
	check(calm < moved * 0.6, "reduced motion: slower (%.1f px, not %.1f)" % [calm, moved])
	var s1 := snow.screen_pos(snow.flakes[3])
	near(s1.x, float(snow.flakes[3].x) * snow.size.x, 0.001, "reduced motion: no sway about the flake's place")
	check(t0 != s1, "(it moved)")
	Prefs.set_value("ui", "reduce_motion", false)
	Prefs.reset()
	snow.free()


func test_snow_shows_only_on_a_snow_day_in_a_campaign() -> void:
	# the storyteller's look says "snow" on a snow day (the storyteller is on in a real game)
	var g := Helpers.make(3, 1, 6, true)
	var sim = g.sim
	sim.storyteller.enabled = true
	sim.weather = "snow"
	check(bool(sim.storyteller.look().snow), "the look has snow on a snow day")
	sim.weather = "rain"
	check(not bool(sim.storyteller.look().snow) and bool(sim.storyteller.look().rain), "not on a rain day")
	sim.weather = "clear"
	check(not bool(sim.storyteller.look().snow), "nor on a clear one")
	g.world.free()
	# and the weather of the days: snow comes in Winter (and in no other season), never when the run is not a campaign
	var snowy := 0
	var other_snow := 0
	for seed_value in 12:
		var c := Helpers.make(seed_value, 1, 6, true)
		for i in [0, 1, 2, 3]:
			c.sim.seasons.jump_to(i)
			for day in 24:
				c.sim.supplies.roll_dawn()
				if c.sim.weather == "snow":
					if i == 1:
						snowy += 1
					else:
						other_snow += 1
		c.world.free()
	check(snowy > 0, "it snows in Winter (%d snow days over twelve games)" % snowy)
	eq(other_snow, 0, "and in no other season")
	for seed_value in 8:
		var plain := Helpers.make(seed_value, 1, 6, false)
		for day in 60:
			plain.sim.supplies.roll_dawn()
			check(plain.sim.weather != "snow", "a game that is not a campaign never snows")
		plain.world.free()


## What a painter draws on, written down: the rectangles and their colours.
class Recorder:
	extends RefCounted
	var rects: Array = []
	var transforms := 0

	func draw_set_transform(_pos: Vector2, _rot: float = 0.0, _scale: Vector2 = Vector2.ONE) -> void:
		transforms += 1

	func draw_set_transform_matrix(_xform: Transform2D) -> void:
		transforms += 1

	func draw_rect(rect: Rect2, color: Color, _filled: bool = true) -> void:
		rects.append([rect, color])


func test_the_ground_has_a_light_cover_drawn_in_code() -> void:
	var g := Helpers.make(1, 1)
	var rec := Recorder.new()
	Snow.paint_ground(rec, g.world)
	var w: int = g.world.W
	var h: int = g.world.H
	check(rec.rects.size() > 1500, "a cover over the ground: %d tiles" % rec.rects.size())
	check(rec.rects.size() < w * h, "and not over every tile (%d of %d): the floors indoors are bare" % [rec.rects.size(), w * h])
	var lo := 1.0
	var hi := 0.0
	var whiteish := true
	for r in rec.rects:
		var c: Color = r[1]
		lo = minf(lo, c.a)
		hi = maxf(hi, c.a)
		if c.r < 0.85 or c.g < 0.9 or c.b < 0.95:
			whiteish = false
	check(whiteish, "white")
	check(lo >= 0.15 and hi <= 0.7 and hi > lo, "light, and not the same everywhere: alpha %.2f to %.2f" % [lo, hi])
	# only outdoor ground: every rectangle is on a tile of a kind that takes snow
	var outdoor := {}
	for name in ["GRASS", "YARD", "SOIL", "DIRT", "SIDEWALK", "CONCRETE", "ASPHALT"]:
		outdoor[int(g.world.d.terrainTypes[name].id)] = true
	for r in rec.rects:
		var rect: Rect2 = r[0]
		var tile := int(g.world.terrain[int(rect.position.y) * w + int(rect.position.x)])
		if not outdoor.has(tile):
			check(false, "a cover on a tile of the kind %d" % tile)
			break
	g.world.free()


# --------------------------------------------------------------------- the end of the game --

func _over(ctx: Dictionary, result: String) -> void:
	ctx.sim.over = result
	Kit.update(ctx)


func _button(ctx: Dictionary, text: String) -> Button:
	for b in ctx.hud.game_over.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func test_the_thirty_nights_end_in_the_old_words() -> void:
	var won := _clock(0, 1280, 800, false)
	_over(won, "victory")
	var go = won.hud.game_over
	eq(go.title_label.text, "The thirty days are over", "a win of the thirty-night game")
	eq(go.sub_label.text, "A convoy is on the road at dawn. You held.", "and its line")
	Kit.free_all(won)
	var lost := _clock(0, 1280, 800, false)
	lost.sim.scenario.today = 12
	_over(lost, "defeat")
	eq(lost.hud.game_over.title_label.text, "Everyone is gone", "a defeat of it")
	eq(lost.hud.game_over.sub_label.text, "Nobody is left to ring the bell.", "and its line: no season in it")
	Kit.free_all(lost)


func test_a_campaign_says_the_seasons_are_over_and_where_it_fell() -> void:
	var won := _clock(3)
	won.sim.scenario.today = 103
	_over(won, "victory")
	eq(won.hud.game_over.title_label.text, "The seasons are over", "a win of the campaign")
	check(won.hud.game_over.sub_label.text.contains("convoy") and won.hud.game_over.sub_label.text.contains("four seasons"), "and its line: %s" % won.hud.game_over.sub_label.text)
	Kit.free_all(won)
	for case in [[1, 41, "Winter"], [0, 12, "Autumn"], [2, 60, "Spring"], [3, 90, "Summer"]]:
		var lost := _clock(int(case[0]))
		lost.sim.scenario.today = int(case[1])
		_over(lost, "defeat")
		var go = lost.hud.game_over
		eq(go.title_label.text, "Everyone is gone", "a defeat in %s" % case[2])
		check(go.sub_label.text.begins_with("You fell in %s, on day %d." % [case[2], case[1]]), "it says where: '%s'" % go.sub_label.text)
		check(go.sub_label.text.ends_with("Nobody is left to ring the bell."), "and keeps its old line: '%s'" % go.sub_label.text)
		Kit.free_all(lost)


func test_a_new_game_after_a_campaign_is_a_campaign_again() -> void:
	for camp in [false, true]:
		var ctx := _clock(1, 1280, 800, camp)
		var meta: Array = []
		ctx.hud.restart = func(m): meta.append(m)
		_over(ctx, "defeat")
		var again := _button(ctx, "New game")
		check(again != null, "a New game button")
		again.pressed.emit()
		eq(meta.size(), 1, "one run asked for")
		check(meta[0].has("campaign") == camp, "campaign=%s: the choice says so only when it was one: %s" % [str(camp), str(meta[0])])
		Kit.free_all(ctx)


func test_the_game_over_card_fits_with_the_longer_words() -> void:
	for wh in [[700, 700], [980, 700], [1280, 800], [1920, 1080]]:
		var ctx := _clock(1, wh[0], wh[1])
		ctx.sim.scenario.today = 41
		_over(ctx, "defeat")
		await Kit.settle()
		await Kit.settle()
		var win := Rect2(0, 0, wh[0], wh[1])
		var go = ctx.hud.game_over
		check(win.encloses(Kit.rect(go.panel).grow(-0.5)), "%s: the card is inside the window: %s" % [str(wh), str(Kit.rect(go.panel))])
		check(Kit.rect(go.panel).encloses(Kit.rect(go.sub_label)), "%s: and its line is inside it" % str(wh))
		for l in _labels(go):
			check(l.get_theme_font_size("font_size") >= 12, "%s: '%s' is 12 px or more" % [str(wh), l.text])
		Kit.free_all(ctx)


# ------------------------------------------------------------------------------ the tips --

const Hints := preload("res://scripts/ui/hints.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const Tut := preload("res://tests/tutorial_kit.gd")


func _tip(id: String) -> Dictionary:
	for h in Hints.load_hints():
		if String(h.id) == id:
			return h
	return {}


func test_each_season_after_autumn_has_a_one_line_tip_that_says_what_changes() -> void:
	var list := Hints.load_hints()
	var ids: Array = []
	for h in list:
		ids.append(String(h.id))
	for id in ["winter", "spring", "summer"]:
		check(ids.has(id), "a tip for %s" % id)
		var h := _tip(id)
		var n := Coach.words(String(h.get("text", "")))
		check(n >= 8 and n <= Coach.MAX_WORDS, "%s: %d words, a line" % [id, n])
		check(not String(h.get("text", "")).contains("\n"), "%s: one line" % id)
		check(String(h.text).begins_with(String(h.title)) or String(h.title).to_lower().contains(id), "%s: its title names it: %s" % [id, h.title])
	check(String(_tip("winter").text).to_lower().contains("greenhouse"), "Winter's tip points at the greenhouse: %s" % _tip("winter").text)
	check(String(_tip("summer").text).to_lower().contains("water"), "Summer's says the water goes fast: %s" % _tip("summer").text)
	eq(ids[ids.size() - 1], "build", "the build tip is still last, so that none of these is hidden by it")
	check(ids.find("winter") < ids.find("build") and ids.find("summer") < ids.find("build"), "and these come before it")


func test_a_season_tip_is_set_off_by_the_season_of_a_campaign_only() -> void:
	var camp := Helpers.make(5, 1, 6, true)
	var sim = camp.sim
	for id in ["winter", "spring", "summer"]:
		check(not Conditions.check(_tip(id).start, sim, {}), "%s: not in Autumn" % id)
	for i in [1, 2, 3]:
		sim.seasons.jump_to(i)
		for k in 3:
			var id: String = ["winter", "spring", "summer"][k]
			eq(Conditions.check(_tip(id).start, sim, {}), k + 1 == i, "season %d: the tip of %s is %s" % [i, id, "due" if k + 1 == i else "not"])
	camp.world.free()
	var plain := Helpers.make(5, 1, 6, false)
	plain.sim.seasons.index = 1    # (not a campaign: the season does not count)
	for id in ["winter", "spring", "summer"]:
		check(not Conditions.check(_tip(id).start, plain.sim, {}), "%s: never when it is not a campaign" % id)
	plain.world.free()


func test_a_season_tip_comes_once_in_its_season_and_not_again() -> void:
	var main = Tut.start({"difficulty": 1, "seed": 5, "campaign": true})
	await Tut.frames(main, 3)
	var hints = main.hints
	hints.armed = true
	main.sim.t = 60.0
	main.sim.stock.ammo = 400.0
	Prefs.set_flag("hint_build")    # (the tip about building is not this test's: it would come on any day after the third)
	await Tut.frames(main, 40)
	eq(hints.shown_id(), "", "Autumn of a campaign has no tip of its own")
	var seen: Array = []
	for i in [1, 2, 3]:
		hints.quiet_s = 0.0
		main.stage_season(i)
		main.sim.t = 60.0
		await Tut.frames(main, 40)
		var id: String = ["winter", "spring", "summer"][i - 1]
		eq(hints.shown_id(), id, "season %d: its tip is up" % i)
		check(Prefs.flag("hint_%s" % id), "%s: marked as shown the moment it was" % id)
		check(hints.text_label.text == String(_tip(id).text), "%s: with its words" % id)
		seen.append(hints.shown_id())
		hints.ok_button.pressed.emit()
		hints.quiet_s = 0.0
		await Tut.frames(main, 40)
		eq(hints.shown_id(), "", "%s: Got it takes it away, and nothing else comes (the tip was the only thing to say)" % id)
	# the seasons come round again (a later game, a load): the tips have been told
	main.stage_season(1)
	main.sim.t = 60.0
	hints.quiet_s = 0.0
	await Tut.frames(main, 40 + 45 * 30)
	eq(hints.shown_id(), "", "back in Winter: the tip does not come twice")
	eq(seen, ["winter", "spring", "summer"], "each season had its tip")
	await Tut.leave(main)


func test_the_season_banner_is_not_covered_by_the_day_banner() -> void:
	var main = Tut.start({"difficulty": 1, "seed": 5, "campaign": true})
	await Tut.frames(main, 3)
	main.sim.events.clear()
	main.sim.events.append({"type": "season", "season": "winter", "index": 1})
	main.sim.events.append({"type": "banner", "text": "Winter begins", "sub": "Short days, long nights."})
	main.sim.events.append({"type": "day_start", "day": 31})
	main.sim.events.append({"type": "banner", "text": "Day 31", "sub": "Repair the wall before dusk"})
	main._handle_events()
	eq(main.hud.banner_title.text, "WINTER BEGINS", "the banner of the season is the one shown, not the day's that follows it")
	main.sim.events.append({"type": "banner", "text": "Day 32", "sub": "Repair the wall before dusk"})
	main._handle_events()
	eq(main.hud.banner_title.text, "DAY 32", "an ordinary day's banner is the day's")
	await Tut.leave(main)


func test_every_new_text_is_12_px_or_more_and_reads_on_its_panel() -> void:
	var HudText := load("res://tests/test_hud_text.gd")
	var Hud := load("res://scripts/ui/hud.gd")
	var ctx := _clock(1)
	ctx.sim.scenario.today = 35
	_at(ctx, 9.0)
	for l in [ctx.hud.day_label, ctx.hud.until_label, ctx.hud.temp_label, ctx.hud.forecast_label]:
		check(l.get_theme_font_size("font_size") >= 12, "'%s' is 12 px or more" % l.text)
	var panel_color: Color = HudText.over(Hud.PANEL, Color.WHITE)
	check(HudText.contrast(Hud.INK2, Color(Hud.PANEL, 1.0)) >= HudText.AA and HudText.contrast(Hud.INK2, panel_color) >= HudText.AA, "the clock's lines read on the panel")
	Kit.free_all(ctx)
	# the new-game cards: lit or not, their words read on their cards
	var menu: Dictionary = await _menu()
	var screen = menu.screen
	for i in 2:
		screen.length_cards[i].pressed.emit()
		for k in 2:
			var card: Button = screen.length_cards[k]
			var on := k == i
			var title: Label = card.get_meta("title")
			var sub: Label = card.get_meta("sub")
			var back: Color = Hud.ACCENT if on else Color(Hud.PANEL, 1.0)
			check(HudText.contrast(title.get_theme_color("font_color"), back) >= HudText.AA, "card %d (lit=%s): its name reads" % [k, str(on)])
			check(HudText.contrast(Color(sub.get_theme_color("font_color"), 1.0), back) >= HudText.AA, "card %d (lit=%s): its line reads" % [k, str(on)])
	MenuFakes.free_all(menu)


func test_nothing_overlaps_with_a_campaigns_clock_at_any_size() -> void:
	for wh in [[700, 700], [980, 700], [1280, 800], [1920, 1080]]:
		for state in [[3, 102, "night", 23.0], [1, 54, "day", 10.0]]:
			for speed in [1, 0]:
				var ctx := _clock(int(state[0]), wh[0], wh[1])
				var ana = Kit.person(ctx, "ana")
				ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
				ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
				ctx.sim.scenario.today = int(state[1])
				Kit.select(ctx, ana)
				_at(ctx, float(state[3]), speed)
				await Kit.settle()
				_at(ctx, float(state[3]), speed)
				await Kit.settle()
				var h = ctx.hud
				var rects := {"stores": Kit.rect(h.res_panel), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock), "alerts": Kit.rect(h.alerts_box), "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos), "speed": Kit.rect(h.speed_panel)}
				eq(Kit.overlaps(rects), [], "%s, %s, speed %d: nothing overlaps" % [str(wh), h.day_label.text, speed])
				check(Rect2(0, 0, wh[0], wh[1]).encloses(Kit.rect(h.clock).grow(-0.5)), "%s, %s: the clock is inside the window" % [str(wh), h.day_label.text])
				Kit.free_all(ctx)


func test_a_campaign_save_loads_back_into_its_season_and_the_clock_says_so() -> void:
	var path := "user://test_seasons_view_%d.json" % OS.get_process_id()
	var g := Helpers.make(5, 1, 6, true)
	g.sim.seasons.jump_to(2)
	g.sim.minutes = 10.0 * 60.0
	g.sim.phase = g.sim.seasons.phase_at(g.sim.minutes)
	g.sim.day = 60
	check(SaveGame.write(g.sim, path), "(a campaign save is written)")
	g.world.free()
	var run := MenuFakes.game({"load": path})
	var main = run.main
	eq(main.sim.seasons.campaign, true, "the loaded game is a campaign")
	eq(main.sim.seasons.index, 2, "in Spring")
	main.hud.compact = false    # (the headless window is tiny: the clock would be in its short form)
	main.hud.update_hud(main.sim, 1, true, 0)
	eq(main.hud.day_label.text, "SPRING, DAY 6 OF 24", "and the clock says where it is")
	check(is_equal_approx(main.lighting.seasons.dusk_hour(), 19.5) and main.lighting.seasons == main.sim.seasons, "the light follows the season's hours")
	await MenuFakes.leave(run)
	MenuFakes.clean([path])
	# a save of the thirty-night game loads as Autumn, as ever
	var plain := Helpers.make(5, 1, 6, false)
	check(SaveGame.write(plain.sim, path), "(a plain save is written)")
	plain.world.free()
	var again := MenuFakes.game({"load": path})
	eq(again.main.sim.seasons.campaign, false, "a plain save is not a campaign")
	again.main.hud.compact = false
	again.main.hud.update_hud(again.main.sim, 1, true, 0)
	eq(again.main.hud.day_label.text, "DAY 1 OF 30", "and the clock is the old one")
	await MenuFakes.leave(again)
	MenuFakes.clean([path])
