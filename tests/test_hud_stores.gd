extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")


func _color(label: Label) -> Color:
	return label.get_theme_color("font_color")


func test_food_and_water_show_the_days_left_under_the_number() -> void:
	var ctx := Kit.build()
	ctx.sim.supplies.days = {"food": 6.4, "water": 13.9}
	ctx.sim.stock.food = 41.0
	Kit.update(ctx)
	eq(ctx.hud.res_days.food.text, "6 d", "food days, rounded down")
	eq(ctx.hud.res_days.water.text, "13 d", "water days")
	check(not ctx.hud.res_days.has("ammo"), "only food and water get a days line")
	eq(ctx.hud.res_values.food.text, "41", "the stock itself is still shown")
	Kit.free_all(ctx)


func test_days_left_are_grey_then_orange_under_three_then_red_under_one() -> void:
	var ctx := Kit.build()
	# the red is DANGER_TEXT, the brighter one for words (DANGER is for bars and icons)
	var cases := [[6.0, "6 d", Hud.INK3], [3.0, "3 d", Hud.INK3], [2.9, "2 d", Hud.WARN], [1.0, "1 d", Hud.WARN], [0.99, "<1 d", Hud.DANGER_TEXT], [0.0, "<1 d", Hud.DANGER_TEXT]]
	for c in cases:
		ctx.sim.supplies.days = {"food": c[0], "water": c[0]}
		Kit.update(ctx)
		for kind in ["food", "water"]:
			eq(ctx.hud.res_days[kind].text, c[1], "%s at %s days" % [kind, c[0]])
			eq(_color(ctx.hud.res_days[kind]), c[2], "%s colour at %s days" % [kind, c[0]])
	Kit.free_all(ctx)


func test_a_huge_number_of_days_reads_as_a_plain_cap() -> void:
	var ctx := Kit.build()
	ctx.sim.supplies.days = {"food": 99.0, "water": 250.0}
	Kit.update(ctx)
	eq(ctx.hud.res_days.food.text, "99+ d", "nobody left to feed")
	eq(ctx.hud.res_days.water.text, "99+ d", "a very full store")
	Kit.free_all(ctx)


func test_medicine_and_ammo_keep_their_warning_colours() -> void:
	var ctx := Kit.build()
	var sim = ctx.sim
	sim.stock.meds = 2.0
	sim.stock.ammo = 59.0
	sim.stock.scrap = 24.0
	Kit.update(ctx)
	eq(_color(ctx.hud.res_values.meds), Hud.WARN, "meds under 3")
	eq(_color(ctx.hud.res_values.ammo), Hud.WARN, "ammo under 60")
	sim.stock.meds = 3.0
	sim.stock.ammo = 60.0
	Kit.update(ctx)
	eq(_color(ctx.hud.res_values.meds), Hud.INK, "meds at 3")
	eq(_color(ctx.hud.res_values.ammo), Hud.INK, "ammo at 60")
	eq(ctx.hud.res_values.scrap.text, "24", "scrap is just shown")
	Kit.free_all(ctx)


func test_the_clock_says_the_day_of_the_run() -> void:
	var ctx := Kit.build()
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "DAY 7 OF 30", "from the scenario")
	ctx.sim.scenario.today = 30
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "DAY 30 OF 30", "the last day")
	Kit.free_all(ctx)


func test_the_clock_is_shorter_in_a_narrow_window() -> void:
	var ctx := Kit.build(700, 700)
	ctx.sim.scenario.today = 30
	Kit.update(ctx)
	eq(ctx.hud.day_label.text, "DAY 30/30", "compact form")
	Kit.free_all(ctx)


func test_the_weather_line_uses_the_weather_of_the_day() -> void:
	var ctx := Kit.build()
	Kit.update(ctx)
	check(ctx.hud.temp_label.text.ends_with("C, clear"), "a clear day: %s" % ctx.hud.temp_label.text)
	ctx.sim.weather = "rain"
	Kit.update(ctx)
	check(ctx.hud.temp_label.text.ends_with("C, rain"), "a rainy day: %s" % ctx.hud.temp_label.text)
	Kit.free_all(ctx)
