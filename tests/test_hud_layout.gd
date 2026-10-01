extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")

## The window sizes the HUD has to fit: wide, the compact threshold and narrow.
const SIZES := [[1280, 800], [980, 700], [700, 700]]


## A selected person with every button on offer and some alerts, settled.
func _busy(width: int, height: int) -> Dictionary:
	var ctx := Kit.build(width, height)
	var ana = Kit.person(ctx, "ana")
	ctx.sim.medical.treat[ana.id] = true
	ctx.sim.medical.sendout[ana.id] = true
	ctx.sim.medical.stage[ana.id] = "feverish"
	ctx.sim.scavenge.can = true
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
	ctx.sim.alert("a3", "info", "The bell has rung", "Everyone is heading to their posts", null, 60.0)
	Kit.select(ctx, ana)
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	return ctx


func _rects(ctx: Dictionary) -> Dictionary:
	var h = ctx.hud
	return {
		"stores": Kit.rect(h.res_panel),
		"cards": Kit.rect(h.bar),
		"clock": Kit.rect(h.clock),
		"alerts": Kit.rect(h.alerts_box),
		"selection": Kit.rect(h.inspect),
		"buttons": Kit.rect(h.gizmos),
		"speed": Kit.rect(h.speed_panel),
	}


func test_nothing_overlaps_with_everything_showing() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1])
		eq(Kit.gizmo_ids(ctx).size(), 7, "%d wide: all seven buttons" % size[0])
		var over := Kit.overlaps(_rects(ctx))
		eq(over, [], "%d x %d" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_everything_stays_inside_the_window() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1])
		var win := Rect2(0, 0, size[0], size[1])
		var rects := _rects(ctx)
		for name in rects:
			var r: Rect2 = rects[name]
			if r.size == Vector2.ZERO:
				continue
			check(win.encloses(r.grow(-0.5)), "%s inside the %d px window: %s" % [name, size[0], str(r)])
		Kit.free_all(ctx)


func test_the_help_panel_clears_the_buttons_and_the_speed_controls() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1])
		ctx.hud.help.visible = true
		await Kit.settle()
		var rects := _rects(ctx)
		rects["help"] = Kit.rect(ctx.hud.help)
		rects.erase("alerts")
		rects.erase("cards")
		eq(Kit.overlaps(rects), [], "%d x %d with the controls help open" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_the_hint_clears_the_bar_and_the_speed_controls() -> void:
	var ctx := Kit.build(1280, 800)
	Kit.update(ctx)
	await Kit.settle()
	var rects := _rects(ctx)
	rects["hint"] = Kit.rect(ctx.hud.hint)
	check(rects["hint"].size != Vector2.ZERO, "the hint shows with nothing selected")
	eq(Kit.overlaps(rects), [], "1280 x 800 with the hint")
	Kit.free_all(ctx)


func test_the_buttons_sit_beside_the_panel_when_there_is_room_and_above_it_when_not() -> void:
	var wide: Dictionary = await _busy(1280, 800)
	var w := _rects(wide)
	check(w.buttons.position.x >= w.selection.end.x, "1280: beside the selection panel")
	Kit.free_all(wide)
	var narrow: Dictionary = await _busy(700, 700)
	var n := _rects(narrow)
	check(n.buttons.end.y <= n.selection.position.y + 0.5, "700: above the selection panel")
	Kit.free_all(narrow)


func test_resizing_the_window_relays_the_dock() -> void:
	var ctx: Dictionary = await _busy(1280, 800)
	Kit.resize(ctx, 700, 700)
	await Kit.settle()
	await Kit.settle()
	eq(Kit.overlaps(_rects(ctx)), [], "after shrinking to 700")
	Kit.resize(ctx, 1280, 800)
	await Kit.settle()
	await Kit.settle()
	eq(Kit.overlaps(_rects(ctx)), [], "after growing back")
	var r := _rects(ctx)
	check(r.buttons.position.x >= r.selection.end.x, "and the buttons are beside the panel again")
	Kit.free_all(ctx)


func test_a_short_window_gets_small_buttons_that_still_clear_the_stores() -> void:
	for size in [[960, 600], [700, 560]]:
		var ctx: Dictionary = await _busy(size[0], size[1])
		check(ctx.hud.gizmo_mini, "small buttons at %d x %d" % [size[0], size[1]])
		eq(Kit.gizmo_ids(ctx).size(), 7, "all seven are still there")
		# the small buttons show no names: the tooltip carries the name, what it does, and the key
		var tip: PackedStringArray = Kit.gizmo(ctx, "treat").tooltip_text.split("\n")
		check(tip[0].begins_with("Treat"), "named in the tooltip: '%s'" % tip[0])
		eq(tip[1], "Key: T", "with its key")
		eq(Kit.overlaps(_rects(ctx)), [], "%d x %d" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_the_big_buttons_come_back_when_the_window_grows() -> void:
	var ctx: Dictionary = await _busy(700, 560)
	check(ctx.hud.gizmo_mini, "small at first")
	Kit.resize(ctx, 700, 700)
	await Kit.settle()
	await Kit.settle()
	check(not ctx.hud.gizmo_mini, "big again")
	check(Kit.texts(Kit.gizmo(ctx, "treat")).has("TREAT"), "with their names")
	eq(Kit.overlaps(_rects(ctx)), [], "and nothing overlaps")
	Kit.free_all(ctx)


## A sweep: every width from 700 to 1400, with 4 to 7 buttons and the help panel
## open or shut, and nothing on the screen overlaps anything else.
func test_nothing_overlaps_at_any_width_with_any_number_of_buttons() -> void:
	var ctx := Kit.build(1280, 760)
	var ana = Kit.person(ctx, "ana")
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 600.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 600.0)
	Kit.select(ctx, ana)
	var bad: Array = []
	for width in range(700, 1401, 35):
		Kit.resize(ctx, width, 760)
		for extra in [0, 1, 2, 3]:
			ctx.sim.medical.treat[ana.id] = extra >= 1
			ctx.sim.medical.sendout[ana.id] = extra >= 2
			ctx.sim.scavenge.can = extra >= 3
			for help_open in [false, true]:
				ctx.hud.help.visible = help_open
				Kit.update(ctx)
				await Kit.settle()
				var rects := _rects(ctx)
				rects["help"] = Kit.rect(ctx.hud.help)
				var found := Kit.overlaps(rects)
				if not found.is_empty():
					bad.append("%d px, %d buttons, help %s: %s" % [width, 4 + extra, help_open, found])
	eq(bad, [], "overlaps found")
	Kit.free_all(ctx)
