extends "res://tests/case.gd"
## The QA pass over rounds 19 to 21 found the right column of the HUD (the clock, the gun's readout, the alerts, the call card) laid out badly in
## avatar mode: an alert that was long made the column look taller than the window, so it was cut, and the cut stayed for good (a cap that was
## never lifted); at 700 x 560 the key legend lay over the third option of a call and the toolbar cut off the third option of the night's, and the
## forecast ate a third of the column. These tests put the real alert of the day ahead and a call of three options on every size the HUD has to
## fit, and read where the things are.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const NightKit := preload("res://scripts/ui/night_kit.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]

## The day-ahead alert as the radio desk raises it (main.gd ensure_notice, night_calls.gd _tell_tomorrow): a long second line.
const BIG_TITLE := "Big Night tomorrow: The Siege"
const BIG_SUB := "About 34 to 46 from the north side (the wrecked sedan, the school bus). 2 plated brutes after 00:30. Runners with them. Be home by 18:30."


# ---------------------------------------------------------------- helpers --

## A HUD over a quiet game in avatar mode (Ruth is the player), the HUD has seen it once.
func _ctx(width: int, height: int) -> Dictionary:
	var ctx := Kit.build(width, height)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "ruth is the player")
	Kit.update(ctx)
	return ctx


func _settle(ctx: Dictionary, rounds: int = 3) -> void:
	for i in rounds:
		Kit.update(ctx)
		await Kit.settle()


## The tonight of a Big Night: what the clock says of the Siege in avatar mode.
func _siege() -> Dictionary:
	return Kit.forecast({
		"kind": "milestone", "name": "The Siege", "total": 40, "low": 34, "high": 46, "side": "north", "heading": "north",
		"sections": [1], "section_text": "the north side", "brutes": 2, "plated": 2, "runners": true,
		"first_at": 21.0, "brute_at": 24.5, "needs_you": true, "big": false,
		"ready": {"walls": 1.0, "guns": 1, "manned": 1, "posts": 4, "holds": false},
	})


func _night_call(radio) -> int:
	return radio.raise_call("night", "Big Night tonight: The Siege", "Understood by default", [
		{"id": "ok", "label": "Understood"}, {"id": "alarm", "label": "Call to arms now"}, {"id": "pallet", "label": "Alarm on the pallet barricade until the brutes are down (3 scrap)"},
	], "ok", 60.0, {}, null)


func _attack_call(radio) -> int:
	return radio.raise_call("attack", "North wall under attack", "3 of the dead at it, 40% intact", [
		{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send reinforcements"}, {"id": "fall_back", "label": "Fall back to the school"},
	], "hold", 90.0, {"seg": 1}, Vector2(40, 10))


## The panels of the alert feed that are on screen.
func _shown(ctx: Dictionary) -> Array:
	var out: Array = []
	for c in ctx.hud.alerts_box.get_children():
		if c is Control and c.is_visible_in_tree() and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _inside(win: Rect2, r: Rect2) -> bool:
	return win.grow(0.5).encloses(r)


# --------------------------------------------------------------- the alerts --

func test_the_day_ahead_alert_shows_in_the_column_at_every_size() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		ctx.sim.alert("bignight-next", "warn", BIG_TITLE, BIG_SUB, null, 60.0)
		await _settle(ctx, 4)
		var where := "%d x %d" % [size[0], size[1]]
		var shown := _shown(ctx)
		eq(shown.size(), 1, "%s: the alert is in the column" % where)
		if shown.size() == 1:
			var r: Rect2 = Kit.rect(shown[0])
			check(_inside(Rect2(0, 0, size[0], size[1]), r), "%s: and inside the window: %s" % [where, str(r)])
			check(r.position.y >= Kit.rect(h.ammo_panel).end.y - 0.5, "%s: under the gun's readout" % where)
			check(r.end.y <= Kit.rect(h.speed_panel).position.y + 0.5, "%s: and over the toolbar: %s, %s" % [where, str(r), str(Kit.rect(h.speed_panel))])
			check(Kit.texts(shown[0]).has(BIG_TITLE), "%s: it is the right one" % where)
		Kit.free_all(ctx)


func test_a_short_alert_shows_at_every_size_with_the_legend_up() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		ctx.sim.alert("wall", "danger", "North wall is down", "The dead are getting in", null, 60.0)
		await _settle(ctx, 4)
		var where := "%d x %d" % [size[0], size[1]]
		check(ctx.hud.hint.visible, "%s: the legend is up" % where)
		eq(_shown(ctx).size(), 1, "%s: the alert shows" % where)
		Kit.free_all(ctx)


func test_a_long_alert_that_goes_does_not_take_the_next_ones_with_it() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		ctx.sim.alert("bignight-next", "warn", BIG_TITLE, BIG_SUB, null, 60.0)
		await _settle(ctx, 3)
		ctx.sim.alerts.erase("bignight-next")
		h.alert_items["bignight-next"].first_ms -= 20000
		await _settle(ctx, 2)
		ctx.sim.alert("wall", "danger", "North wall is down", "The dead are getting in", null, 60.0)
		await _settle(ctx, 3)
		var where := "%d x %d" % [size[0], size[1]]
		var shown := _shown(ctx)
		eq(shown.size(), 1, "%s: the later alert shows" % where)
		if shown.size() == 1:
			check(Kit.texts(shown[0]).has("North wall is down"), "%s: and it is the later one" % where)
		Kit.free_all(ctx)


func test_the_alerts_that_do_not_fit_beside_the_news_come_back_when_it_is_shut() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 600.0)
		ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 600.0)
		await _settle(ctx, 3)
		var where := "%d x %d" % [size[0], size[1]]
		var before := _shown(ctx).size()
		check(before >= 1, "%s: some are up to begin with" % where)
		h.open_radio("news")
		await _settle(ctx, 3)
		h.close_radio()
		await _settle(ctx, 3)
		eq(_shown(ctx).size(), before, "%s: all of them are back when the panel is shut" % where)
		Kit.free_all(ctx)


func test_alerts_put_away_for_a_call_come_back_when_it_is_answered() -> void:
	# (a cap that had reached 0 stayed there for good: nothing lifted it)
	for size in [[700, 560], [960, 600], [700, 700]]:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 600.0)
		ctx.sim.alert("bignight-next", "warn", BIG_TITLE, BIG_SUB, null, 600.0)
		var id: int = _night_call(ctx.sim.radio)
		ctx.sim.tactics.told = _siege()
		await _settle(ctx, 4)
		var where := "%d x %d" % [size[0], size[1]]
		check(h.call_card.is_visible_in_tree(), "%s: the call is up" % where)
		var during := _shown(ctx).size()
		check(ctx.sim.radio.answer(id, "ok"), "%s: it is answered" % where)
		h.call_card.result_ms = 0
		for i in 3:
			await _settle(ctx, 3)
		check(not h.call_card.is_visible_in_tree(), "%s: the card is gone" % where)
		check(_shown(ctx).size() > during, "%s: more alerts are up now than beside the call: %d against %d" % [where, _shown(ctx).size(), during])
		eq(_shown(ctx).size(), 2, "%s: both are up again" % where)
		check(h.forecast_label.visible, "%s: and the clock has its forecast back" % where)
		Kit.free_all(ctx)


func test_the_alerts_never_push_the_column_over_the_toolbar() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		for i in 5:
			ctx.sim.alert("a%d" % i, "warn", "Something is going on %d" % i, "A second line that wraps in a narrow column of the clock", null, 600.0)
		ctx.sim.alert("bignight-next", "warn", BIG_TITLE, BIG_SUB, null, 600.0)
		await _settle(ctx, 4)
		var where := "%d x %d" % [size[0], size[1]]
		var col := Kit.rect(h.right_col)
		check(col.end.y <= Kit.rect(h.speed_panel).position.y + 0.5, "%s: the column ends over the toolbar: %s, %s" % [where, str(col), str(Kit.rect(h.speed_panel))])
		check(_shown(ctx).size() >= 1, "%s: at least one alert is up" % where)
		Kit.free_all(ctx)


func test_a_long_second_line_is_kept_short_and_the_whole_of_it_is_in_the_tooltip() -> void:
	var ctx := _ctx(700, 560)
	ctx.sim.alert("bignight-next", "warn", BIG_TITLE, BIG_SUB, null, 60.0)
	await _settle(ctx, 4)
	var shown := _shown(ctx)
	eq(shown.size(), 1, "it shows")
	if shown.size() == 1:
		var item: Dictionary = ctx.hud.alert_items["bignight-next"]
		var lines: int = item.subl.get_line_count()
		check(lines <= 4, "four lines of it at most: %d" % lines)
		check(item.subl.text.contains("Be home by 18:30"), "and the hour to be home by is kept: '%s'" % item.subl.text)
		check(String(shown[0].tooltip_text).contains("Runners with them"), "the whole of it is in the tooltip: '%s'" % shown[0].tooltip_text)
	Kit.free_all(ctx)


# ---------------------------------------------------------------- the calls --

## The buttons of the call card, in order, with what stops each from being used: empty when every one is fully in view and nothing is over it.
func _blocked_options(ctx: Dictionary, size: Array) -> Array:
	var h = ctx.hud
	var out: Array = []
	var win := Rect2(0, 0, size[0], size[1])
	var covers := {"toolbar": h.speed_panel, "legend": h.hint, "stores": h.res_panel, "cards": h.bar, "selection": h.inspect, "dock": h.gizmos, "clock": h.clock, "ammo": h.ammo_panel, "help": h.help}
	for id in h.call_card.view.buttons:
		var b: Button = h.call_card.view.buttons[id]
		var r: Rect2 = Kit.rect(b)
		if r.size.x < 40.0 or r.size.y < 16.0:
			out.append("%s has no size: %s" % [id, str(r)])
			continue
		if not _inside(win, r):
			out.append("%s leaves the window: %s" % [id, str(r)])
		if not h.call_card.is_visible_in_tree() or not Kit.rect(h.call_card).grow(0.5).encloses(r):
			out.append("%s is outside its card: %s in %s" % [id, str(r), str(Kit.rect(h.call_card))])
		for name in covers:
			var c: Control = covers[name]
			var cr: Rect2 = Kit.rect(c)
			if cr.size != Vector2.ZERO and cr.intersection(r).size.x > 0.5 and cr.intersection(r).size.y > 0.5:
				out.append("%s is under the %s: %s over %s" % [id, name, str(cr), str(r)])
	return out


func _with_call(size: Array, kind: String) -> Dictionary:
	var ctx := _ctx(size[0], size[1])
	var h = ctx.hud
	ctx.sim.phase = "day"
	ctx.sim.tactics.told = _siege()
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 600.0)
	ctx.sim.alert("bignight-next", "warn", BIG_TITLE, BIG_SUB, null, 600.0)
	ctx["call"] = _night_call(ctx.sim.radio) if kind == "night" else _attack_call(ctx.sim.radio)
	await _settle(ctx, 4)
	return ctx


func test_a_call_of_three_options_is_whole_and_clear_at_every_size_with_the_forecast_up() -> void:
	for kind in ["night", "attack"]:
		for size in SIZES:
			var ctx: Dictionary = await _with_call(size, kind)
			var h = ctx.hud
			var where := "%s call at %d x %d" % [kind, size[0], size[1]]
			check(h.call_card.is_visible_in_tree(), "%s: the card is up" % where)
			eq(h.call_card.view.buttons.size(), 3, "%s: three options" % where)
			eq(_blocked_options(ctx, size), [], where)
			var card := Kit.rect(h.call_card)
			check(card.end.y <= Kit.rect(h.speed_panel).position.y + 0.5, "%s: the card ends over the toolbar: %s, %s" % [where, str(card), str(Kit.rect(h.speed_panel))])
			Kit.free_all(ctx)


func test_the_legend_steps_aside_while_a_call_is_up_and_returns() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		await _settle(ctx, 2)
		var where := "%d x %d" % [size[0], size[1]]
		check(h.hint.visible, "%s: the legend is up with nothing to decide" % where)
		var id: int = _attack_call(ctx.sim.radio)
		await _settle(ctx, 2)
		check(not h.hint.visible, "%s: and gone while a call waits" % where)
		check(ctx.sim.radio.answer(id, "hold"), "%s: the call is answered" % where)
		h.call_card.result_ms = 0
		await _settle(ctx, 3)
		await _settle(ctx, 2)
		check(h.hint.visible, "%s: and back once it is settled" % where)
		Kit.free_all(ctx)


func test_the_third_option_can_be_clicked_at_700_x_560() -> void:
	var ctx: Dictionary = await _with_call([700, 560], "night")
	var h = ctx.hud
	var third: Button = h.call_card.view.buttons["pallet"]
	Kit.click_on(third)
	await Kit.settle()
	var e := {}
	for n in ctx.sim.radio.news:
		if int(n.id) == int(ctx.call):
			e = n
	eq(String(e.get("answered", "")), "pallet", "the click reached the third button")
	Kit.free_all(ctx)


# ------------------------------------------------------------ the forecast --

func test_the_forecast_is_short_in_a_narrow_window_and_whole_in_a_wide_one() -> void:
	var f := _siege()
	var wide := NightKit.forecast_line(f, true)
	var narrow := NightKit.forecast_line_compact(f, true)
	check(narrow.length() < wide.length() * 0.7, "the narrow line is much shorter: '%s'" % narrow)
	check(narrow.begins_with("The Siege"), "and starts with the night's name: '%s'" % narrow)
	check(narrow.contains("34 to 46"), "with the size: '%s'" % narrow)
	check(narrow.contains("north"), "and the side: '%s'" % narrow)
	check(narrow.contains("plated"), "and the plated brutes: '%s'" % narrow)
	var ready := NightKit.ready_line_compact(f)
	check(ready.text.length() < 44, "the readiness is short too: '%s'" % ready.text)
	check(ready.text.contains("1 of 4") or ready.text.contains("1/4"), "it has the posts: '%s'" % ready.text)
	check(not bool(ready.holds), "and says it will not hold")


func test_the_forecast_takes_at_most_four_lines_of_a_narrow_clock_and_the_whole_clock_stays_short() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		ctx.sim.phase = "day"
		ctx.sim.tactics.told = _siege()
		await _settle(ctx, 3)
		var where := "%d x %d" % [size[0], size[1]]
		check(h.forecast_label.visible and h.ready_label.visible, "%s: both lines are up" % where)
		if h.compact:
			var lines: int = h.forecast_label.get_line_count() + h.ready_label.get_line_count()
			check(lines <= 4, "%s: four lines of the forecast at most in the narrow clock: %d" % [where, lines])
			# (with the whole lines it was 256 tall in this state)
			check(Kit.rect(h.clock).size.y <= 230.0, "%s: the clock is %.0f tall" % [where, Kit.rect(h.clock).size.y])
		else:
			eq(h.forecast_label.text, NightKit.forecast_line(_siege(), true), "%s: the whole line in a wide window" % where)
		Kit.free_all(ctx)


# ------------------------------------------------------------------ the map --

const TutorialKit := preload("res://tests/tutorial_kit.gd")


## The real game scene as an avatar's settlement run at `width` x `height`, the Map page of the radio panel open on a place.
func _map_main(width: int, height: int) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": true}, width, height)
	main.sim.waves.enabled = false
	main.sim.zombies.clear()
	main.hud.update_hud(main.sim, 1, true, 0)
	main.hud.open_radio("map")
	for i in 3:
		main.hud.update_hud(main.sim, 1, true, 0)
		await Kit.settle()
	return main


func _place_of(page) -> String:
	for id in ["pharmacy", "houses", "bakery"]:
		if page.sites.has(id):
			return id
	return String(page.sites.keys()[0])


func test_take_control_and_ask_are_in_view_without_scrolling_once_a_place_is_chosen() -> void:
	for size in SIZES:
		var main: Node = await _map_main(size[0], size[1])
		var h = main.hud
		var page = h.radio_panel.page_node("map")
		var id := _place_of(page)
		page.select_place(id)
		for i in 4:
			h.update_hud(main.sim, 1, true, 0)
			await Kit.settle()
		var where := "%d x %d" % [size[0], size[1]]
		var panel: Rect2 = Kit.rect(h.radio_panel)
		var scroll: ScrollContainer = h.radio_panel.scroll
		for name in ["go", "errand"]:
			var b: Button = page.buttons[name]
			var r: Rect2 = Kit.rect(b)
			check(b.is_visible_in_tree() and r.size.x > 80.0 and r.size.y > 20.0, "%s: %s is on screen: %s" % [where, name, str(r)])
			check(panel.grow(0.5).encloses(r), "%s: %s is inside the panel: %s in %s" % [where, name, str(r), str(panel)])
			# (not inside the scrolling part: the strip stays when the page scrolls)
			check(not scroll.is_ancestor_of(b), "%s: %s is not in the part that scrolls" % [where, name])
		var place_name := String(page.sites[id].name)
		check(Kit.texts(page.pin).has(place_name), "%s: the strip names the place: %s" % [where, str(Kit.texts(page.pin))])
		var pin_rect: Rect2 = Kit.rect(page.pin)
		check(pin_rect.size.y > 40.0 and panel.grow(0.5).encloses(pin_rect), "%s: the strip is in the panel: %s" % [where, str(pin_rect)])
		check(Kit.rect(h.radio_panel.scroll).size.y >= 60.0, "%s: and the page still has room above it: %s" % [where, str(Kit.rect(h.radio_panel.scroll))])
		# the page scrolled to its end or its top, the strip has not moved
		scroll.scroll_vertical = 0
		await Kit.settle()
		var before: Rect2 = Kit.rect(page.buttons.go)
		scroll.scroll_vertical = 100000
		await Kit.settle()
		eq(Kit.rect(page.buttons.go), before, "%s: Take control stays where it is when the page scrolls" % where)
		await TutorialKit.leave(main)


func test_the_strip_follows_the_choice_and_is_not_there_before_one() -> void:
	var main: Node = await _map_main(1280, 800)
	var h = main.hud
	var page = h.radio_panel.page_node("map")
	page.site_id = ""
	page.refresh(true)
	await Kit.settle()
	check(not page.pin.is_visible_in_tree(), "nothing is chosen: no strip")
	page.select_place(_place_of(page))
	await Kit.settle()
	check(page.pin.is_visible_in_tree(), "a place is chosen: the strip is up")
	h.open_radio("news")
	await Kit.settle()
	check(not page.pin.is_visible_in_tree(), "another page: the strip is gone with the page")
	h.open_radio("map")
	await Kit.settle()
	check(page.pin.is_visible_in_tree(), "and back with it")
	h.close_radio()
	await Kit.settle()
	check(not page.pin.is_visible_in_tree(), "the panel is shut: no strip")
	await TutorialKit.leave(main)


func test_the_strips_ask_button_asks_and_the_answer_is_in_the_strip() -> void:
	var main: Node = await _map_main(1280, 800)
	var h = main.hud
	var page = h.radio_panel.page_node("map")
	page.select_place(_place_of(page))
	page.toggle_person(Kit.person({"sim": main.sim}, "dez"))
	for i in 3:
		h.update_hud(main.sim, 1, true, 0)
		await Kit.settle()
	var ask: Button = page.buttons.errand
	check(not ask.disabled, "Dez would go: the button is on (%s)" % ask.tooltip_text)
	ask.pressed.emit()
	for i in 2:
		h.update_hud(main.sim, 1, true, 0)
		await Kit.settle()
	check(page.answer_label.is_visible_in_tree(), "the answer is up")
	check(Kit.rect(h.radio_panel).grow(0.5).encloses(Kit.rect(page.answer_label)), "inside the panel, by the button: %s" % str(Kit.rect(page.answer_label)))
	check(page.pin.is_ancestor_of(page.answer_label), "in the strip")
	await TutorialKit.leave(main)
