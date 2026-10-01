extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700]]

## Every key and mouse button the game answers to (main.gd's _unhandled_input).
const KEYS := ["R", "P", "F", "C", "T", "X", "G", "B", "L", "V", "Tab", "Space", "1", "2", "3", "Esc", "F5", "F9", "W", "A", "S", "D", "Arrows"]
const MOUSE := ["Click", "Right-click", "Drag", "Scroll"]


func _texts(ctx: Dictionary) -> Array:
	return Kit.texts(ctx.hud.help)


func test_the_help_lists_every_key() -> void:
	var ctx := Kit.build()
	var all := _texts(ctx)
	for k in KEYS:
		check(all.has(k), "the key %s is listed" % k)
	Kit.free_all(ctx)


func test_the_help_lists_the_mouse() -> void:
	var ctx := Kit.build()
	var all := _texts(ctx)
	for k in MOUSE:
		check(all.has(k), "%s is listed" % k)
	var joined := " ".join(all).to_lower()
	for word in ["select", "move", "pan", "zoom", "pause", "save", "load", "speed", "deselect", "next person", "draft", "post", "repair", "follow", "treat", "send out", "scavenge", "auto-repair", "lure", "fields of fire"]:
		check(joined.contains(word), "and says what '%s' is for" % word)
	Kit.free_all(ctx)


func test_every_key_is_a_chip_with_twelve_pixel_text() -> void:
	var ctx := Kit.build()
	var chips := 0
	for l in ctx.hud.help.find_children("*", "Label", true, false):
		check(l.get_theme_font_size("font_size") >= 12, "'%s' is 12 px or more" % l.text)
		if KEYS.has(l.text) or MOUSE.has(l.text):
			chips += 1
			check(l.get_parent() is PanelContainer, "'%s' sits in a chip" % l.text)
	check(chips >= KEYS.size() + MOUSE.size(), "all of them: %d chips" % chips)
	Kit.free_all(ctx)


func test_the_help_is_grouped() -> void:
	var ctx := Kit.build()
	var caps: Array = []
	for t in _texts(ctx):
		if t == t.to_upper() and t.length() > 3 and not KEYS.has(t):
			caps.append(t)
	check(caps.size() >= 3, "at least three group captions: %s" % str(caps))
	Kit.free_all(ctx)


func test_the_help_opens_with_its_button_and_shuts_again() -> void:
	var ctx := Kit.build()
	check(not ctx.hud.help.visible, "shut at first")
	ctx.hud.help_button.pressed.emit()
	check(ctx.hud.help.visible, "open")
	ctx.hud.help_button.pressed.emit()
	check(not ctx.hud.help.visible, "shut")
	Kit.free_all(ctx)


func test_the_help_is_compact() -> void:
	var ctx := Kit.build(1280, 800)
	ctx.hud.help.visible = true
	await Kit.settle()
	var r := Kit.rect(ctx.hud.help)
	check(r.size.x <= 420.0, "not wide: %s" % str(r.size))
	check(r.size.y <= 460.0, "not tall: %s" % str(r.size))
	Kit.free_all(ctx)


func test_the_help_stays_clear_of_the_clock_and_the_stores_in_a_short_window() -> void:
	for size in SIZES:
		var ctx := Kit.build(size[0], size[1])
		var ana = Kit.person(ctx, "ana")
		ctx.sim.medical.treat[ana.id] = true
		ctx.sim.medical.sendout[ana.id] = true
		ctx.sim.scavenge.can = true
		Kit.select(ctx, ana)
		ctx.hud.help.visible = true
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var h = ctx.hud
		var rects := {"help": Kit.rect(h.help), "clock": Kit.rect(h.clock), "stores": Kit.rect(h.res_panel), "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos), "speed": Kit.rect(h.speed_panel)}
		eq(Kit.overlaps(rects), [], "%d x %d with the help open" % [size[0], size[1]])
		check(Rect2(0, 0, size[0], size[1]).encloses(rects.help.grow(-0.5)), "inside the %d px window" % size[0])
		Kit.free_all(ctx)
