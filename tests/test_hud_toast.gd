extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700]]


func _wait(seconds: float) -> void:
	await Engine.get_main_loop().create_timer(seconds).timeout


func test_a_toast_shows_one_line_of_text() -> void:
	var ctx := Kit.build()
	check(not ctx.hud.toast_panel.visible, "nothing at first")
	ctx.hud.toast("Nothing is damaged")
	check(ctx.hud.toast_panel.visible, "it shows")
	eq(ctx.hud.toast_label.text, "Nothing is damaged", "with the words")
	check(not ctx.hud.toast_label.text.contains("\n"), "on one line")
	eq(ctx.hud.toast_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks go through it")
	Kit.free_all(ctx)


func test_an_empty_toast_shows_nothing() -> void:
	var ctx := Kit.build()
	ctx.hud.toast("")
	ctx.hud.toast("   ", "warn")
	check(not ctx.hud.toast_panel.visible, "no empty box")
	ctx.hud.toast("Game saved")
	ctx.hud.toast("")
	eq(ctx.hud.toast_label.text, "Game saved", "and an empty one does not wipe a real one")
	Kit.free_all(ctx)


func test_the_next_toast_replaces_it() -> void:
	var ctx := Kit.build()
	ctx.hud.toast("Nothing is damaged")
	ctx.hud.toast("Ana is down", "warn")
	eq(ctx.hud.toast_label.text, "Ana is down", "only the latest")
	var n := 0
	for c in ctx.hud.get_children():
		if c == ctx.hud.toast_panel:
			n += 1
	eq(n, 1, "one toast panel, reused")
	Kit.free_all(ctx)


func test_info_and_warn_have_their_own_colours() -> void:
	var ctx := Kit.build()
	ctx.hud.toast("Game saved", "info")
	var info: Color = ctx.hud.toast_label.get_theme_color("font_color")
	var info_edge: Color = ctx.hud.toast_col
	var info_box: StyleBox = ctx.hud.toast_panel.get_theme_stylebox("panel")
	ctx.hud.toast("Nothing is damaged", "warn")
	var warn: Color = ctx.hud.toast_label.get_theme_color("font_color")
	var warn_edge: Color = ctx.hud.toast_col
	var warn_box: StyleBox = ctx.hud.toast_panel.get_theme_stylebox("panel")
	check(info != warn, "the words differ")
	eq(warn, Hud.WARN, "warn is the HUD's orange")
	check(info_edge != warn_edge, "and the edge too: the bar down the side (on a frame) or the board's edge (flat)")
	if info_box is StyleBoxFlat and warn_box is StyleBoxFlat:
		check(info_box.border_color != warn_box.border_color, "flat: the whole edge differs")
		eq(warn_box.border_color, Hud.LEVEL_COLOR.warn, "in the level's colour")
	ctx.hud.toast("Game saved")
	eq(ctx.hud.toast_label.get_theme_color("font_color"), info, "the default is info")
	ctx.hud.toast("Something odd", "no-such-level")
	check(ctx.hud.toast_panel.visible, "an unknown level still shows")
	Kit.free_all(ctx)


func test_a_toast_fades_and_goes() -> void:
	var ctx := Kit.build()
	eq(ctx.hud.toast_seconds, 2.5, "about two and a half seconds")
	ctx.hud.toast_seconds = 1.0
	ctx.hud.toast("Nothing is damaged")
	check(ctx.hud.toast_panel.modulate.a > 0.99, "fully there at first")
	await _wait(0.8)
	check(ctx.hud.toast_panel.visible and ctx.hud.toast_panel.modulate.a < 0.99, "fading at the end: alpha %.2f" % ctx.hud.toast_panel.modulate.a)
	await _wait(0.5)
	check(not ctx.hud.toast_panel.visible, "gone")
	Kit.free_all(ctx)


func test_a_new_toast_starts_the_time_again() -> void:
	var ctx := Kit.build()
	ctx.hud.toast_seconds = 0.6
	ctx.hud.toast("First")
	await _wait(0.4)
	ctx.hud.toast("Second")
	check(ctx.hud.toast_panel.modulate.a > 0.99, "fully there again")
	await _wait(0.3)
	check(ctx.hud.toast_panel.visible and ctx.hud.toast_label.text == "Second", "the first one's timer did not take it away")
	await _wait(0.6)
	check(not ctx.hud.toast_panel.visible, "and the second goes in its time")
	Kit.free_all(ctx)


func test_a_toast_sits_at_the_bottom_centre_above_the_hint() -> void:
	var ctx := Kit.build(1280, 800)
	Kit.update(ctx)
	ctx.hud.toast("Nothing is damaged", "warn")
	await Kit.settle()
	await Kit.settle()
	var toast := Kit.rect(ctx.hud.toast_panel)
	var hint := Kit.rect(ctx.hud.hint)
	check(hint.size != Vector2.ZERO, "the hint is showing")
	check(toast.size != Vector2.ZERO, "and so is the toast")
	check(toast.end.y <= hint.position.y + 0.5, "the toast is above the hint: %s %s" % [str(toast), str(hint)])
	near(toast.get_center().x, 640.0, 1.0, "centred")
	check(toast.position.y > 400.0, "in the lower half")
	eq(Kit.overlaps({"toast": toast, "hint": hint}), [], "no overlap")
	# the hint goes at the first selection: the toast drops to where it was
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx)
	await Kit.settle()
	await Kit.settle()
	var lower := Kit.rect(ctx.hud.toast_panel)
	check(lower.end.y > toast.end.y, "without the hint the toast sits lower: %s then %s" % [str(toast), str(lower)])
	check(lower.end.y <= 800.0 - 12.0, "still inside the window")
	Kit.free_all(ctx)


func test_a_toast_stays_clear_of_the_controls_at_any_size() -> void:
	for size in SIZES:
		var ctx := Kit.build(size[0], size[1])
		var ana = Kit.person(ctx, "ana")
		ctx.sim.medical.treat[ana.id] = true
		ctx.sim.medical.sendout[ana.id] = true
		ctx.sim.scavenge.can = true
		Kit.select(ctx, ana)
		Kit.update(ctx)
		ctx.hud.toast("Ana can't repair: nothing is damaged right now", "warn")
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var h = ctx.hud
		var rects := {"toast": Kit.rect(h.toast_panel), "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos), "speed": Kit.rect(h.speed_panel), "stores": Kit.rect(h.res_panel), "clock": Kit.rect(h.clock), "cards": Kit.rect(h.bar)}
		check(rects.toast.size != Vector2.ZERO, "%d px: the toast shows" % size[0])
		eq(Kit.overlaps(rects), [], "%d x %d" % [size[0], size[1]])
		check(Rect2(0, 0, size[0], size[1]).encloses(rects.toast.grow(-0.5)), "inside the %d px window: %s" % [size[0], str(rects.toast)])
		Kit.free_all(ctx)


func test_the_toast_text_is_big_enough() -> void:
	var ctx := Kit.build()
	check(ctx.hud.toast_label.get_theme_font_size("font_size") >= 12, "12 px or more")
	Kit.free_all(ctx)
