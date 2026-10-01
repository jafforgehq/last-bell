extends "res://tests/case.gd"
## The Menu button at the right end of the toolbar (it opens the pause menu, like Esc with nothing
## selected), the help's line for Esc, the one-line hint that follows the player's "hints" setting
## and the fades and swings that follow the "reduce motion" setting. (The key and the pause menu
## themselves are the shell's: tests/test_menus_*.gd; the button wired to main.gd is in
## test_hud_keys.gd.)

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const GD := preload("res://scripts/game_data.gd")
const Prefs := preload("res://scripts/prefs.gd")

const TEST_PREFS := "user://prefs_test.cfg"
const SIZES := [[700, 700], [980, 700], [1280, 800]]


## The settings back to their defaults in the tests' own file (never the player's).
func _fresh() -> void:
	Prefs.path = TEST_PREFS
	Prefs.reset()


## The toolbar's keys, left to right, by name.
func _keys(h) -> Dictionary:
	var out := {}
	for i in h.speed_buttons.size():
		out["speed %d" % i] = Kit.rect(h.speed_buttons[i])
	out["fields"] = Kit.rect(h.fields_button)
	out["sound"] = Kit.rect(h.sound_button)
	out["help"] = Kit.rect(h.help_button)
	out["menu"] = Kit.rect(h.menu_button)
	return out


# ------------------------------------------------------------ the Menu button --

func test_the_menu_button_is_the_last_key_of_the_toolbar_and_says_what_it_is() -> void:
	var ctx := Kit.build()
	var h = ctx.hud
	check(h.menu_button != null, "there is a Menu button")
	var row: Node = h.menu_button.get_parent()
	eq(h.sound_button.get_parent(), row, "in the toolbar's row, with the sound and the help")
	eq(h.menu_button.get_index(), h.help_button.get_index() + 1, "right after the help")
	eq(h.menu_button.get_index(), row.get_child_count() - 1, "and last")
	eq(h.menu_button.tooltip_text, "Menu\nKey: Esc", "named, with its key")
	eq(h.menu_button.custom_minimum_size, h.help_button.custom_minimum_size, "as big as its neighbours")
	check(h.menu_button.get_child_count() == 1 and h.menu_button.get_meta("icon") is TextureRect, "icon only, like them")
	eq(h.menu_button.get_meta("icon").texture, h.icons["menu"], "wearing the menu icon")
	eq(h.menu_button.focus_mode, Control.FOCUS_NONE, "and, like them, not a stop for the keyboard")
	Kit.free_all(ctx)


func test_the_menu_icon_is_white_on_clear_and_64_pixels_like_the_others() -> void:
	var path: String = Hud.EXTRA_ICONS["menu"]
	check(ResourceLoader.exists(path), "the picture is imported: %s" % path)
	var tex: Texture2D = GD.tex(path)
	check(tex != null, "it loads")
	if tex == null:
		return
	eq(tex.get_size(), Vector2(64, 64), "64 by 64, as every icon is")
	var img: Image = tex.get_image()
	var opaque := 0
	var tinted := 0
	for y in 64:
		for x in 64:
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				opaque += 1
			if c.a > 0.02 and (c.r < 0.98 or c.g < 0.98 or c.b < 0.98):
				tinted += 1
	check(opaque > 300 and opaque < 2400, "a sensible amount of ink: %d px" % opaque)
	eq(tinted, 0, "pure white with alpha: the HUD tints it")
	# three bars: the middle column has three runs of ink with clear between
	var runs := 0
	var inside := false
	for y in 64:
		var on: bool = img.get_pixel(32, y).a > 0.5
		if on and not inside:
			runs += 1
		inside = on
	eq(runs, 3, "three bars")


func test_pressing_menu_calls_the_menu_callback_and_does_nothing_without_one() -> void:
	var ctx := Kit.build()
	var h = ctx.hud
	check(not h.on_open_menu.is_valid(), "nobody listens at first")
	h.menu_button.pressed.emit()
	check(true, "a press with nobody listening breaks nothing")
	var opened: Array = []
	h.on_open_menu = func(): opened.append(true)
	h.menu_button.pressed.emit()
	eq(opened.size(), 1, "a press asks for the menu once")
	await Kit.settle()
	await Kit.settle()
	Kit.click_on(h.menu_button)
	eq(opened.size(), 2, "and so does a click of the mouse")
	Kit.free_all(ctx)


func test_the_menu_key_is_in_the_help_as_esc_deselect_or_the_menu() -> void:
	var ctx := Kit.build()
	var found := ""
	for group in Hud.HELP:
		for entry in group[2]:
			if entry[0] == "Esc":
				found = String(entry[1])
	eq(found, "Deselect, or the menu", "what Esc does")
	check(Kit.texts(ctx.hud.help).has("Deselect, or the menu"), "and the panel says so")
	check(Kit.texts(ctx.hud.help).has("Esc"), "next to its key")
	Kit.free_all(ctx)


func test_the_help_with_the_longer_esc_line_still_fits_and_stays_clear() -> void:
	# the line wraps to two lines rather than widening the panel
	for size in SIZES:
		var ctx := Kit.build(size[0], size[1])
		ctx.hud.help.visible = true
		await Kit.settle()
		await Kit.settle()
		var help := Kit.rect(ctx.hud.help)
		check(help.size.x <= 420.0 and help.size.y <= 460.0, "%d px: the help is still compact: %s" % [size[0], str(help.size)])
		check(Rect2(0, 0, size[0], size[1]).encloses(help.grow(-0.5)), "%d px: inside the window" % size[0])
		eq(Kit.overlaps({"help": help, "toolbar": Kit.rect(ctx.hud.speed_panel), "clock": Kit.rect(ctx.hud.clock)}), [], "%d px: clear of the toolbar and the clock" % size[0])
		for l in ctx.hud.help.find_children("*", "Label", true, false):
			if l.text == "Deselect, or the menu":
				check(l.get_line_count() <= 2, "%d px: on one line or two, not three" % size[0])
		Kit.free_all(ctx)


# ----------------------------------------------------------- the toolbar still fits --

func _busy(width: int, height: int) -> Dictionary:
	var ctx := Kit.build(width, height)
	var ana = Kit.person(ctx, "ana")
	ctx.sim.medical.treat[ana.id] = true
	ctx.sim.medical.sendout[ana.id] = true
	ctx.sim.scavenge.can = true
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
	ctx.sim.tactics.told = Kit.forecast({"brutes": 2, "heading": "north and west"})
	ctx.hud.set_fields(true)
	Kit.select(ctx, ana)
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	return ctx


func test_the_toolbar_with_the_menu_button_fits_at_700_980_and_1280() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1])
		var h = ctx.hud
		var where := "%d x %d" % [size[0], size[1]]
		var bar := Kit.rect(h.speed_panel)
		var win := Rect2(0, 0, size[0], size[1])
		check(bar.size != Vector2.ZERO and win.encloses(bar.grow(-0.5)), "%s: the toolbar is inside the window: %s" % [where, str(bar)])
		var keys := _keys(h)
		var names: Array = keys.keys()
		for name in names:
			var r: Rect2 = keys[name]
			check(r.size != Vector2.ZERO and bar.encloses(r), "%s: %s is on the toolbar: %s in %s" % [where, name, str(r), str(bar)])
		eq(Kit.overlaps(keys), [], "%s: no key of the toolbar overlaps another" % where)
		# left to right, in order, the menu at the end
		for i in range(1, names.size()):
			var a: Rect2 = keys[names[i - 1]]
			var b: Rect2 = keys[names[i]]
			check(b.position.x >= a.end.x - 0.5, "%s: %s comes after %s" % [where, names[i], names[i - 1]])
		check(keys["menu"].end.x <= bar.end.x + 0.5 and keys["menu"].end.x >= bar.end.x - 12.0, "%s: the menu key is at the right end of the toolbar" % where)
		# nothing else on the screen is under it
		var others := {"toolbar": bar, "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos), "stores": Kit.rect(h.res_panel), "legend": Kit.rect(h.fields_legend), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock), "alerts": Kit.rect(h.alerts_box)}
		eq(Kit.overlaps(others), [], "%s: the toolbar and the rest of the screen do not overlap" % where)
		# with the controls help open as well
		h.help.visible = true
		await Kit.settle()
		var with_help := others.duplicate()
		with_help["help"] = Kit.rect(h.help)
		with_help.erase("alerts")
		with_help.erase("cards")
		eq(Kit.overlaps(with_help), [], "%s: and with the help open" % where)
		Kit.free_all(ctx)


func test_a_full_row_of_order_buttons_still_sits_beside_the_panel_at_1280() -> void:
	# nine buttons (the nurse in the morning with a fever to treat): the toolbar's new key must not
	# push them above the selection panel in the usual window
	var ctx: Dictionary = await _busy(1280, 800)
	eq(Kit.gizmo_ids(ctx).size(), 9, "all nine are offered")
	var buttons := Kit.rect(ctx.hud.gizmos)
	var panel := Kit.rect(ctx.hud.inspect)
	check(buttons.position.x >= panel.end.x, "beside the selection panel: %s, %s" % [str(buttons), str(panel)])
	check(Kit.rect(ctx.hud.speed_panel).position.x >= buttons.end.x + 4.0, "with room before the toolbar: %s then %s" % [str(buttons), str(Kit.rect(ctx.hud.speed_panel))])
	Kit.free_all(ctx)


# ------------------------------------------------------------------------ hints --

func test_hints_off_hide_the_one_line_hint_and_on_bring_it_back() -> void:
	_fresh()
	var ctx := Kit.build()
	var h = ctx.hud
	Kit.update(ctx)
	check(h.hint.visible, "hints on (the default): the hint is up")
	Prefs.set_value("ui", "hints", false)
	Kit.update(ctx)
	check(not h.hint.visible, "hints turned off: it goes at the next update")
	Prefs.set_value("ui", "hints", true)
	Kit.update(ctx)
	check(h.hint.visible, "turned on again before anything is selected: it is back")
	Kit.free_all(ctx)
	_fresh()


func test_a_game_started_with_hints_off_never_shows_the_hint() -> void:
	_fresh()
	Prefs.set_value("ui", "hints", false)
	var ctx := Kit.build()
	check(not ctx.hud.hint.visible, "hidden from the first frame")
	await Kit.settle()
	Kit.update(ctx)
	check(not ctx.hud.hint.visible, "and still after an update")
	Kit.free_all(ctx)
	_fresh()


func test_the_hint_that_has_done_its_job_stays_gone_whatever_the_setting() -> void:
	_fresh()
	var ctx := Kit.build()
	var h = ctx.hud
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx)
	check(not h.hint.visible and h.hint_spent, "the first selection takes it away")
	Prefs.set_value("ui", "hints", false)
	Kit.update(ctx)
	Prefs.set_value("ui", "hints", true)
	Kit.update(ctx)
	check(not h.hint.visible, "and switching hints off and on does not bring it back")
	Kit.free_all(ctx)
	# a window too narrow for it, and the end of the run, spend it as well
	ctx = Kit.build(700, 700)
	check(not ctx.hud.hint.visible, "narrow: no hint")
	Kit.free_all(ctx)
	ctx = Kit.build()
	ctx.hud.save_paths = []
	ctx.sim.over = "defeat"
	Kit.update(ctx)
	check(not ctx.hud.hint.visible, "game over: no hint")
	Prefs.set_value("ui", "hints", false)
	Prefs.set_value("ui", "hints", true)
	Kit.update(ctx)
	check(not ctx.hud.hint.visible, "and it does not come back over the report card")
	Kit.free_all(ctx)
	_fresh()


func test_the_toast_sits_lower_when_the_hint_is_off() -> void:
	_fresh()
	var ctx := Kit.build(1280, 800)
	Kit.update(ctx)
	ctx.hud.toast("Nothing is damaged", "warn")
	await Kit.settle()
	await Kit.settle()
	var with_hint := Kit.rect(ctx.hud.toast_panel)
	Prefs.set_value("ui", "hints", false)
	Kit.update(ctx)
	await Kit.settle()
	await Kit.settle()
	var without := Kit.rect(ctx.hud.toast_panel)
	check(without.end.y > with_hint.end.y, "without the hint the toast drops to where it sits then: %s, then %s" % [str(with_hint), str(without)])
	Kit.free_all(ctx)
	_fresh()


# ---------------------------------------------------------------- reduced motion --

func test_the_banner_fades_by_default_and_with_reduced_motion_is_simply_there() -> void:
	_fresh()
	var ctx := Kit.build()
	ctx.hud.show_banner("Dusk falls", "The bell has rung")
	check(ctx.hud.banner.modulate.a < 0.5, "by default it begins clear and fades in: %.2f" % ctx.hud.banner.modulate.a)
	await Engine.get_main_loop().create_timer(0.35).timeout
	var half: float = ctx.hud.banner.modulate.a
	check(half > 0.05 and half < 0.95, "partway after a third of a second: %.2f" % half)
	Kit.free_all(ctx)
	Prefs.set_value("ui", "reduce_motion", true)
	ctx = Kit.build()
	ctx.hud.show_banner("Dusk falls", "The bell has rung")
	near(ctx.hud.banner.modulate.a, 1.0, 0.0001, "reduced motion: there at once")
	await Engine.get_main_loop().create_timer(0.35).timeout
	near(ctx.hud.banner.modulate.a, 1.0, 0.0001, "and not partway at all")
	eq(ctx.hud.banner_title.text, "DUSK FALLS", "with the same words")
	Kit.free_all(ctx)
	_fresh()


func test_the_toast_fades_by_default_and_with_reduced_motion_goes_without_a_fade() -> void:
	_fresh()
	var ctx := Kit.build()
	ctx.hud.toast_seconds = 0.6
	ctx.hud.toast("Nothing is damaged")
	await Engine.get_main_loop().create_timer(0.45).timeout
	check(ctx.hud.toast_panel.visible and ctx.hud.toast_panel.modulate.a < 0.95, "by default it is fading near its end: %.2f" % ctx.hud.toast_panel.modulate.a)
	Kit.free_all(ctx)
	Prefs.set_value("ui", "reduce_motion", true)
	ctx = Kit.build()
	ctx.hud.toast_seconds = 0.6
	ctx.hud.toast("Nothing is damaged")
	await Engine.get_main_loop().create_timer(0.45).timeout
	check(ctx.hud.toast_panel.visible, "reduced motion: still up")
	near(ctx.hud.toast_panel.modulate.a, 1.0, 0.0001, "and as clear as at the start")
	await Engine.get_main_loop().create_timer(0.4).timeout
	check(not ctx.hud.toast_panel.visible, "then gone, in its time")
	Kit.free_all(ctx)
	_fresh()


func test_the_bell_swings_by_default_and_not_with_reduced_motion() -> void:
	_fresh()
	var ctx := Kit.build()
	ctx.sim.bell_rung = true
	ctx.sim.phase = "night"
	Kit.update(ctx)
	await Engine.get_main_loop().create_timer(0.12).timeout
	check(absf(ctx.hud.clock_bell.rotation) > 0.01, "by default it swings: %.3f rad" % ctx.hud.clock_bell.rotation)
	Kit.free_all(ctx)
	Prefs.set_value("ui", "reduce_motion", true)
	ctx = Kit.build()
	ctx.sim.bell_rung = true
	ctx.sim.phase = "night"
	Kit.update(ctx)
	check(ctx.hud.clock_bell.visible, "reduced motion: the bell is on the clock")
	await Engine.get_main_loop().create_timer(0.3).timeout
	near(ctx.hud.clock_bell.rotation, 0.0, 0.0001, "and hangs still")
	Kit.free_all(ctx)
	_fresh()


func test_the_fight_badge_pulses_by_default_and_holds_steady_with_reduced_motion() -> void:
	_fresh()
	var ctx := Kit.build()
	var marcus = Kit.person(ctx, "marcus")
	marcus.target = ctx.sim.zombies[0]
	var seen := {}
	for i in 12:
		Kit.update(ctx)
		seen["%.2f" % Kit.card(ctx, marcus).fight.modulate.a] = true
		await Engine.get_main_loop().create_timer(0.09).timeout
	check(seen.size() > 2, "by default its brightness moves: %s" % str(seen.keys()))
	Kit.free_all(ctx)
	Prefs.set_value("ui", "reduce_motion", true)
	ctx = Kit.build()
	marcus = Kit.person(ctx, "marcus")
	marcus.target = ctx.sim.zombies[0]
	seen = {}
	for i in 6:
		Kit.update(ctx)
		seen["%.2f" % Kit.card(ctx, marcus).fight.modulate.a] = true
		await Engine.get_main_loop().create_timer(0.09).timeout
	eq(seen.keys(), ["1.00"], "reduced motion: always the same")
	check(Kit.card(ctx, marcus).fight.visible, "still shown")
	Kit.free_all(ctx)
	_fresh()


func test_alerts_come_and_go_without_a_fade_whatever_the_setting() -> void:
	# nothing in the feed is animated: a slip is there at full strength the moment it is shown
	for calm in [false, true]:
		_fresh()
		Prefs.set_value("ui", "reduce_motion", calm)
		var ctx := Kit.build()
		ctx.sim.alert("a1", "warn", "Food is running out", "about 2 days left", null, 60.0)
		Kit.update(ctx)
		var slip: Control = ctx.hud.alert_items["a1"].panel
		near(slip.modulate.a, 1.0, 0.0001, "reduce_motion %s: shown at full strength" % calm)
		Kit.free_all(ctx)
	_fresh()
