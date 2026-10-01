extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")


## The alert panels now in the feed, in order (a panel being freed is no longer a child).
func _panels(ctx: Dictionary) -> Array:
	var out: Array = []
	for c in ctx.hud.alerts_box.get_children():
		if not c.is_queued_for_deletion():
			out.append(c)
	return out


func _ids(ctx: Dictionary) -> Array:
	var out: Array = []
	for p in _panels(ctx):
		out.append(String(p.get_meta("id", "")))
	return out


func _raise(ctx: Dictionary, id: String, level: String = "warn", text: String = "Something happens", sub: String = "a line below") -> void:
	ctx.sim.alert(id, level, text, sub, null, 600.0)


func test_a_wall_alert_that_changes_every_claw_does_not_rebuild_the_feed() -> void:
	var ctx := Kit.build()
	_raise(ctx, "seg-3", "warn", "North wall under attack", "86% intact")
	Kit.update(ctx)
	var first := _panels(ctx)
	eq(first.size(), 1, "one alert")
	var panel = first[0]
	for pct in range(85, 60, -1):
		_raise(ctx, "seg-3", "warn", "North wall under attack", "%d%% intact" % pct)
		Kit.update(ctx)
		var now := _panels(ctx)
		check(now.size() == 1 and now[0] == panel, "%d%%: still the same panel node" % pct)
		check(Kit.texts(panel).has("%d%% intact" % pct), "%d%%: the new line is in it" % pct)
	check(not Kit.texts(panel).has("86% intact"), "and the old line is gone")
	Kit.free_all(ctx)


func test_the_title_can_change_in_place_too() -> void:
	var ctx := Kit.build()
	_raise(ctx, "low-food", "warn", "Food is running out", "about 2 days left")
	Kit.update(ctx)
	var panel = _panels(ctx)[0]
	_raise(ctx, "low-food", "warn", "Food is nearly gone", "about 1 day left")
	Kit.update(ctx)
	check(_panels(ctx)[0] == panel, "same panel")
	check(Kit.texts(panel).has("Food is nearly gone") and Kit.texts(panel).has("about 1 day left"), "both lines follow")
	Kit.free_all(ctx)


func test_the_other_panels_stay_when_one_comes_and_goes() -> void:
	var ctx := Kit.build()
	_raise(ctx, "a1", "danger", "Marcus is down", "Get them to Ana")
	_raise(ctx, "a2", "warn", "Food is running out", "about 2 days left")
	Kit.update(ctx)
	var before := _panels(ctx)
	eq(_ids(ctx), ["a1", "a2"], "danger above warn")
	_raise(ctx, "a3", "info", "The bell has rung", "Everyone is heading to their posts")
	Kit.update(ctx)
	var after := _panels(ctx)
	eq(_ids(ctx), ["a1", "a2", "a3"], "the new one goes last (info is the lowest)")
	check(after[0] == before[0] and after[1] == before[1], "the old panels are the same nodes")
	# a danger alert comes in and takes the top: the others are kept and moved
	_raise(ctx, "a4", "danger", "Breach at the north wall", "Walkers are getting in")
	Kit.update(ctx)
	eq(_ids(ctx), ["a4", "a1", "a2", "a3"], "newest danger first")
	check(_panels(ctx)[1] == before[0] and _panels(ctx)[2] == before[1], "and the old panels are still the same nodes")
	Kit.free_all(ctx)


func test_a_change_of_level_shows_in_the_panel() -> void:
	var ctx := Kit.build()
	_raise(ctx, "seg-1", "warn", "North wall under attack", "60% intact")
	Kit.update(ctx)
	var item: Dictionary = ctx.hud.alert_items["seg-1"]
	eq(item.icon.modulate, Hud.LEVEL_COLOR.warn, "orange at first")
	_raise(ctx, "seg-1", "danger", "North wall under attack", "30% intact")
	Kit.update(ctx)
	item = ctx.hud.alert_items["seg-1"]
	eq(item.icon.modulate, Hud.LEVEL_COLOR.danger, "red once it is in danger")
	eq(String(_panels(ctx)[0].get_meta("level")), "danger", "and the panel says so")
	Kit.free_all(ctx)


func test_an_alert_the_rules_drop_stays_for_six_real_seconds() -> void:
	var ctx := Kit.build()
	eq(Hud.ALERT_HOLD_MS, 6000, "the rule is six seconds")
	_raise(ctx, "bell", "info", "The bell has rung", "Everyone is heading to their posts")
	Kit.update(ctx)
	eq(_ids(ctx), ["bell"], "shown")
	# at 3x speed the rules drop a 5 s alert in under two real seconds
	check(ctx.hud.alert_items["bell"].live, "the rules hold it")
	ctx.sim.alerts.erase("bell")
	Kit.update(ctx)
	eq(_ids(ctx), ["bell"], "the rules let it go, the panel stays")
	check(not ctx.hud.alert_items["bell"].live, "and the record says it is only lingering")
	ctx.hud.alert_items["bell"].first_ms -= 4500
	Kit.update(ctx)
	eq(_ids(ctx), ["bell"], "still there after four and a half seconds")
	ctx.hud.alert_items["bell"].first_ms -= 2000
	Kit.update(ctx)
	eq(_ids(ctx), [], "gone once it has had its six")
	check(not ctx.hud.alert_items.has("bell"), "and forgotten")
	Kit.free_all(ctx)


func test_the_six_seconds_count_from_when_it_first_appeared() -> void:
	var ctx := Kit.build()
	_raise(ctx, "scav-1", "info", "Ana left for the houses.", "Back by 16:00.")
	Kit.update(ctx)
	ctx.hud.alert_items["scav-1"].first_ms -= 7000
	# the rules still hold it: it stays, however long it has been up
	Kit.update(ctx)
	eq(_ids(ctx), ["scav-1"], "kept while the rules keep it")
	ctx.sim.alerts.erase("scav-1")
	Kit.update(ctx)
	eq(_ids(ctx), [], "dropped at once when the rules drop it after its six")
	Kit.free_all(ctx)


func test_an_alert_that_comes_back_is_a_new_one() -> void:
	var ctx := Kit.build()
	_raise(ctx, "rain", "info", "It rained in the night", "Barrels gave 12 water")
	Kit.update(ctx)
	ctx.sim.alerts.erase("rain")
	ctx.hud.alert_items["rain"].first_ms -= 7000
	Kit.update(ctx)
	eq(_ids(ctx), [], "gone")
	_raise(ctx, "rain", "info", "It rained in the night", "Barrels gave 9 water")
	Kit.update(ctx)
	eq(_ids(ctx), ["rain"], "and back")
	ctx.sim.alerts.erase("rain")
	Kit.update(ctx)
	eq(_ids(ctx), ["rain"], "with six seconds of its own")
	Kit.free_all(ctx)


func test_never_more_than_five_alerts_even_with_the_ones_that_linger() -> void:
	var ctx := Kit.build(1280, 800)
	for i in 8:
		_raise(ctx, "n%d" % i, "warn", "Alert %d" % i)
		Kit.update(ctx)
		check(_panels(ctx).size() <= 5, "%d alerts raised: at most five shown" % (i + 1))
	eq(_panels(ctx).size(), 5, "five of the eight")
	ctx.sim.alerts.clear()
	Kit.update(ctx)
	check(_panels(ctx).size() <= 5, "the lingering ones are capped too")
	for i in 3:
		_raise(ctx, "m%d" % i, "danger", "Danger %d" % i)
		Kit.update(ctx)
		check(_panels(ctx).size() <= 5, "new ones over the lingering ones: still at most five")
	var ids := _ids(ctx)
	check(ids.has("m0") and ids.has("m1") and ids.has("m2"), "the dangers are among them: %s" % str(ids))
	Kit.free_all(ctx)


func test_a_narrow_window_shows_three() -> void:
	var ctx := Kit.build(700, 700)
	for i in 6:
		_raise(ctx, "n%d" % i, "warn", "Alert %d" % i)
	Kit.update(ctx)
	eq(_panels(ctx).size(), 3, "three in a narrow window")
	Kit.free_all(ctx)


func test_each_alert_gets_the_icon_of_what_it_is_about() -> void:
	var ctx := Kit.build()
	var cases := {
		"seg-4": "wall", "breach-4": "wall", "fever-ana": "fever", "scav-2": "scavenge", "scav-out-2": "scavenge",
		"low-food": "food", "low-water": "water", "bell": "bell", "horde": "walker", "hurt-ruth": "wound",
		"down-marcus": "down", "turned-walt": "turned", "no-meds": "meds", "no-scrap": "scrap", "exile-walt": "sendout",
		"rain": "water", "no-ammo": "ammo",
	}
	for id in cases:
		_raise(ctx, id, "warn", "text of %s" % id)
	# more than the feed shows: look at the items, not the panels
	Kit.update(ctx)
	for id in cases:
		var item: Dictionary = ctx.hud.alert_items[id]
		eq(ctx.hud._alert_icon_name(item), cases[id], "%s shows the %s icon" % [id, cases[id]])
	Kit.free_all(ctx)


func test_an_alert_of_no_known_kind_falls_back_to_its_level() -> void:
	var ctx := Kit.build()
	for pair in [["danger", "warn"], ["warn", "warn"], ["info", "bell"]]:
		var id := "zzz-%s" % pair[0]
		_raise(ctx, id, pair[0])
		Kit.update(ctx)
		eq(ctx.hud._alert_icon_name(ctx.hud.alert_items[id]), pair[1], "%s alert of no known kind" % pair[0])
	Kit.free_all(ctx)


func test_the_icon_in_the_panel_is_the_one_for_its_kind() -> void:
	var ctx := Kit.build()
	_raise(ctx, "seg-9", "warn", "West wall under attack", "70% intact")
	Kit.update(ctx)
	eq(ctx.hud.alert_items["seg-9"].icon.texture, ctx.hud.icons["wall"], "the brick wall")
	Kit.free_all(ctx)


func test_an_alert_with_no_second_line_shows_no_empty_line() -> void:
	var ctx := Kit.build()
	_raise(ctx, "exile-walt", "warn", "Walt left through the gate", "")
	Kit.update(ctx)
	check(not ctx.hud.alert_items["exile-walt"].subl.visible, "the empty line is hidden")
	_raise(ctx, "exile-walt", "warn", "Walt left through the gate", "He did not look back")
	Kit.update(ctx)
	check(ctx.hud.alert_items["exile-walt"].subl.visible, "and shows once there is something to say")
	Kit.free_all(ctx)


func test_the_feed_leaves_no_orphan_nodes_behind() -> void:
	var ctx := Kit.build()
	await Kit.settle()
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 40:
		_raise(ctx, "k%d" % (i % 5), ["danger", "warn", "info"][i % 3], "Alert %d" % i, "line %d" % i)
		Kit.update(ctx)
	ctx.sim.alerts.clear()
	for id in ctx.hud.alert_items.keys():
		ctx.hud.alert_items[id].first_ms -= 7000
	Kit.update(ctx)
	await Kit.settle()
	var after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(after <= before, "no node was left without a parent: %d before, %d after" % [before, after])
	Kit.free_all(ctx)


func test_a_click_on_an_alert_reaches_on_alert_with_its_id() -> void:
	var ctx := Kit.build()
	var got: Array = []
	ctx.hud.on_alert = func(id): got.append(id)
	_raise(ctx, "seg-3", "warn", "North wall under attack", "86% intact")
	Kit.update(ctx)
	await Kit.settle()
	_raise(ctx, "seg-3", "warn", "North wall under attack", "85% intact")
	Kit.update(ctx)
	Kit.click_on(_panels(ctx)[0])
	eq(got, ["seg-3"], "the click lands, even though the text changed a moment before")
	Kit.free_all(ctx)


func test_a_long_second_line_does_not_widen_the_feed() -> void:
	var ctx := Kit.build(700, 700)
	_raise(ctx, "treated-ana", "warn", "The treatment did not take", "Ana is still infected. Try again (2 medicine) and keep her away from the others")
	Kit.update(ctx)
	await Kit.settle()
	await Kit.settle()
	var box := Kit.rect(ctx.hud.alerts_box)
	var win := Rect2(0, 0, 700, 700)
	check(win.encloses(box.grow(-0.5)), "the feed stays inside the window: %s" % str(box))
	check(box.size.x <= 200.0, "and keeps its narrow width: %s" % str(box.size))
	Kit.free_all(ctx)


## Alerts raised, changed and dropped at random, with the window growing and shrinking and
## the clock jumping: the feed must always show exactly the top few of what it knows, in
## order, with the words of the rules, and never more than the maximum.
func test_random_alerts_never_break_the_feed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var ctx := Kit.build(1280, 800)
	var ids := ["seg-1", "seg-2", "breach-1", "fever-ana", "fever-walt", "scav-1", "scav-out-1", "low-food", "low-water", "bell", "horde", "no-ammo", "hurt-ruth", "mystery-7"]
	var levels := ["danger", "warn", "info", "odd"]
	for round in 300:
		for i in rng.randi() % 4:
			var id: String = ids[rng.randi() % ids.size()]
			ctx.sim.alert(id, levels[rng.randi() % levels.size()], "Text %d" % rng.randi_range(0, 99), "" if rng.randf() < 0.2 else "Sub %d" % rng.randi_range(0, 99), null, 600.0)
		if rng.randf() < 0.3 and not ctx.sim.alerts.is_empty():
			ctx.sim.alerts.erase(ctx.sim.alerts.keys()[rng.randi() % ctx.sim.alerts.size()])
		if rng.randf() < 0.25 and not ctx.hud.alert_items.is_empty():
			var item: Dictionary = ctx.hud.alert_items.values()[rng.randi() % ctx.hud.alert_items.size()]
			item.first_ms -= rng.randi_range(0, 8000)
		if rng.randf() < 0.1:
			Kit.resize(ctx, 700 if rng.randf() < 0.5 else 1280, 800)
			await Kit.settle()
		Kit.update(ctx, rng.randi() % 4)
		_check_the_feed(ctx, round)
	check(true, "it got through")
	Kit.free_all(ctx)


func _check_the_feed(ctx: Dictionary, round: int) -> void:
	var hud = ctx.hud
	var limit: int = 3 if hud.compact else 5
	var panels := _panels(ctx)
	if panels.size() > limit:
		failures.append("round %d: %d panels, at most %d allowed" % [round, panels.size(), limit])
	# what the feed should show: the top of everything it knows, in order
	var known: Array = hud.alert_items.values()
	known.sort_custom(hud._alert_before)
	var want: Array = []
	for it in known.slice(0, limit):
		want.append(String(it.id))
	var got := _ids(ctx)
	if got != want:
		failures.append("round %d: shows %s, should show %s" % [round, str(got), str(want)])
		return
	for p in panels:
		var it: Dictionary = hud.alert_items.get(String(p.get_meta("id")), {})
		if it.is_empty() or it.panel != p:
			failures.append("round %d: a panel for %s that the feed has no record of" % [round, p.get_meta("id")])
			continue
		if it.live and (it.title.text != it.text or it.subl.text != it.sub):
			failures.append("round %d: %s shows '%s' / '%s', the rules say '%s' / '%s'" % [round, it.id, it.title.text, it.subl.text, it.text, it.sub])
		if String(p.get_meta("level")) != String(it.level):
			failures.append("round %d: %s is %s in the panel, %s in the record" % [round, it.id, p.get_meta("level"), it.level])
	var with_panel := 0
	for it in hud.alert_items.values():
		if it.panel != null:
			with_panel += 1
		if not it.live and not it.seen:
			failures.append("round %d: %s lingers but was never shown" % [round, it.id])
	if with_panel != panels.size():
		failures.append("round %d: %d records hold a panel but the feed has %d" % [round, with_panel, panels.size()])
