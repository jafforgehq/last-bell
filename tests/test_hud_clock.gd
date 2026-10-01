extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700]]


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


func test_a_paused_game_shows_a_pill_beside_the_phase_chip() -> void:
	var ctx := Kit.build()
	Kit.update(ctx, 1)
	check(not ctx.hud.paused_pill.visible, "running: no pill")
	Kit.update(ctx, 0)
	check(ctx.hud.paused_pill.visible, "paused: the pill")
	check(Kit.texts(ctx.hud.paused_pill).has("PAUSED"), "it says so")
	for speed in [1, 2, 3]:
		Kit.update(ctx, speed)
		check(not ctx.hud.paused_pill.visible, "speed %d: no pill" % speed)
	Kit.update(ctx, 0)
	check(ctx.hud.paused_pill.visible, "and back again")
	Kit.free_all(ctx)


func test_the_pill_sits_in_the_clock_between_the_day_and_the_phase() -> void:
	var ctx := Kit.build()
	Kit.update(ctx, 0)
	await Kit.settle()
	Kit.update(ctx, 0)
	await Kit.settle()
	var clock: Rect2 = Kit.rect(ctx.hud.clock)
	var pill: Rect2 = Kit.rect(ctx.hud.paused_pill)
	var chip: Rect2 = Kit.rect(ctx.hud.phase_chip)
	var day: Rect2 = Kit.rect(ctx.hud.day_label)
	check(pill.size != Vector2.ZERO, "the pill is on screen")
	check(clock.encloses(pill) and clock.encloses(chip) and clock.encloses(day), "the clock holds all three")
	eq(Kit.overlaps({"day": day, "pill": pill, "chip": chip}), [], "and they do not overlap")
	check(pill.end.x <= chip.position.x + 0.5, "the pill is to the left of the chip: %s %s" % [str(pill), str(chip)])
	check(pill.position.x >= day.end.x - 0.5, "and to the right of the day")
	Kit.free_all(ctx)


func test_the_clock_does_not_jump_when_the_game_pauses() -> void:
	# the pill has room in the clock's own row, even in the longest case (day 30, the
	# longest phase name): the clock's width, right edge and height stay the same
	for state in [[7, "day"], [30, "night"], [30, "dusk"], [12, "dawn"]]:
		var ctx := Kit.build()
		ctx.sim.scenario.today = state[0]
		ctx.sim.phase = state[1]
		Kit.update(ctx, 1)
		await Kit.settle()
		Kit.update(ctx, 1)
		await Kit.settle()
		var running: Rect2 = Kit.rect(ctx.hud.clock)
		Kit.update(ctx, 0)
		await Kit.settle()
		Kit.update(ctx, 0)
		await Kit.settle()
		var paused: Rect2 = Kit.rect(ctx.hud.clock)
		var where := "day %d, %s" % [state[0], state[1]]
		near(paused.end.x, running.end.x, 0.5, "%s: same right edge" % where)
		near(paused.size.y, running.size.y, 0.5, "%s: same height" % where)
		near(paused.size.x, running.size.x, 0.5, "%s: same width in the wide layout" % where)
		Kit.free_all(ctx)


func test_nothing_overlaps_while_paused_at_any_size() -> void:
	for size in SIZES:
		var ctx := Kit.build(size[0], size[1])
		var ana = Kit.person(ctx, "ana")
		ctx.sim.medical.treat[ana.id] = true
		ctx.sim.medical.sendout[ana.id] = true
		ctx.sim.scavenge.can = true
		ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
		ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
		ctx.sim.scenario.today = 30
		ctx.sim.phase = "night"
		Kit.select(ctx, ana)
		Kit.update(ctx, 0)
		await Kit.settle()
		Kit.update(ctx, 0)
		await Kit.settle()
		eq(Kit.overlaps(_rects(ctx)), [], "%d x %d, paused, night, day 30" % [size[0], size[1]])
		var win := Rect2(0, 0, size[0], size[1])
		check(win.encloses(Kit.rect(ctx.hud.clock).grow(-0.5)), "the clock is inside the %d px window" % size[0])
		var pill: Rect2 = Kit.rect(ctx.hud.paused_pill)
		check(pill.size != Vector2.ZERO and Kit.rect(ctx.hud.clock).encloses(pill), "the pill is inside the clock at %d px" % size[0])
		Kit.free_all(ctx)


func test_the_pill_text_is_readable() -> void:
	# a stamp: dark ink on a pale pill (see test_hud_text for the numbers)
	var ctx := Kit.build()
	var label: Label = ctx.hud.paused_label
	check(label.get_theme_font_size("font_size") >= 12, "12 px or more")
	Kit.free_all(ctx)
