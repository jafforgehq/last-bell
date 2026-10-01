extends "res://tests/case.gd"
## The night tools in the HUD: the Lure (alarm) and Auto-repair buttons and the tag in the
## person panel, the lookout's forecast under the clock, the fields-of-fire button and its
## legend, the icons of the new alerts, and the kind of the dead in their panel. (The drawing
## in the world is in test_hud_fields.gd, the keys in test_hud_keys.gd.)

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Tactics := preload("res://scripts/sim/tactics.gd")
const Kinds := preload("res://scripts/sim/kinds.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]
const NORTH_BUS := 3
const DOOR := 14


func _lines(b: Button) -> PackedStringArray:
	return b.tooltip_text.split("\n")


## A wall section selected (the sections' ids are their places in the list), the HUD updated.
func _wall(ctx: Dictionary, id: int):
	var seg = ctx.sim.segments[id]
	eq(seg.id, id, "section %d is where its id says" % id)
	ctx.hud.select({"kind": "segment", "ref": seg})
	Kit.update(ctx)
	return seg


## A person selected and the HUD updated.
func _person(ctx: Dictionary, id: String):
	var p = Kit.person(ctx, id)
	Kit.select(ctx, p)
	Kit.update(ctx)
	return p


# ------------------------------------------------------------------- the lure --

func test_a_wall_section_gets_a_lure_button_with_its_name_and_key() -> void:
	var ctx := Kit.build()
	_wall(ctx, NORTH_BUS)
	eq(Kit.gizmo_ids(ctx), ["repair", "focus", "lure"], "the alarm after the usual two")
	var b: Button = Kit.gizmo(ctx, "lure")
	check(Kit.texts(b).has("LURE"), "it is named")
	check(Kit.texts(b).has("L"), "and shows its key")
	Kit.free_all(ctx)


func test_the_lure_tooltip_says_what_it_does_what_it_costs_and_its_key() -> void:
	var ctx := Kit.build()
	_wall(ctx, NORTH_BUS)
	var lines := _lines(Kit.gizmo(ctx, "lure"))
	eq(lines.size(), 3, "three lines when nothing is against it: '%s'" % Kit.gizmo(ctx, "lure").tooltip_text)
	eq(lines[0], "Alarm: draws the dead to this wall for %d hours" % int(Tactics.LURE_HOURS), "what it does")
	eq(lines[1], "Costs %d scrap. One at a time." % int(Tactics.LURE_COST), "what it costs")
	eq(lines[2], "Key: L", "the key")
	Kit.free_all(ctx)


func test_the_lure_says_why_not_and_is_ghosted_but_still_pressable() -> void:
	var ctx := Kit.build()
	_wall(ctx, NORTH_BUS)
	var b: Button = Kit.gizmo(ctx, "lure")
	check(b.modulate.a > 0.99, "bright while it can be set")
	ctx.sim.tactics.why = "an alarm is already ringing"
	Kit.update(ctx)
	var lines := _lines(b)
	eq(lines.size(), 4, "a fourth line when it cannot: '%s'" % b.tooltip_text)
	eq(lines[2], "Key: L", "the key stays where it was")
	eq(lines[3], "Not now: an alarm is already ringing.", "and the reason is the rules' own")
	check(b.modulate.a < 0.9, "ghosted")
	check(not b.disabled, "but not disabled: the order goes through and the game says why")
	ctx.sim.tactics.why = ""
	Kit.update(ctx)
	check(b.modulate.a > 0.99 and _lines(b).size() == 3, "and bright again when it can")
	Kit.free_all(ctx)


func test_pressing_lure_reaches_main_and_a_real_click_does_too() -> void:
	var ctx := Kit.build()
	_wall(ctx, NORTH_BUS)
	Kit.gizmo(ctx, "lure").pressed.emit()
	eq(ctx.pressed, ["lure"], "a press reaches main.gd by its id")
	await Kit.settle()
	await Kit.settle()
	Kit.click_on(Kit.gizmo(ctx, "lure"))
	eq(ctx.pressed, ["lure", "lure"], "and a mouse click does")
	Kit.free_all(ctx)


func test_the_lure_shows_for_a_door_with_the_rules_reason() -> void:
	var ctx := Kit.build()
	ctx.sim.tactics.why = "the dead are not drawn to the school doors"
	_wall(ctx, DOOR)
	var b: Button = Kit.gizmo(ctx, "lure")
	check(b != null and b.modulate.a < 0.9, "there, and ghosted")
	check(b.tooltip_text.ends_with("Not now: the dead are not drawn to the school doors."), "with the reason: '%s'" % b.tooltip_text)
	Kit.free_all(ctx)


func test_a_person_and_a_walker_get_no_lure_button() -> void:
	var ctx := Kit.build()
	_person(ctx, "ruth")
	check(Kit.gizmo(ctx, "lure") == null, "not for a person")
	ctx.hud.select({"kind": "zombie", "ref": ctx.sim.zombies[0]})
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "lure") == null and Kit.gizmo(ctx, "auto") == null, "nor for a walker")
	Kit.free_all(ctx)


# ----------------------------------------------------------------- auto-repair --

func test_a_person_gets_an_auto_button_that_lights_while_it_is_on() -> void:
	var ctx := Kit.build()
	var ana = _person(ctx, "ana")
	var b: Button = Kit.gizmo(ctx, "auto")
	check(b != null, "the Auto button is there")
	check(Kit.texts(b).has("AUTO") and Kit.texts(b).has("B"), "named, with its key B (A pans the view)")
	eq(b.get_meta("on"), false, "off at first")
	eq((b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, Hud.PANEL, "dark like the others")
	ctx.sim.tactics.toggle_auto(ana)
	Kit.update(ctx)
	b = Kit.gizmo(ctx, "auto")
	eq(b.get_meta("on"), true, "on once the order is on")
	eq((b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, Hud.ACCENT, "lit gold, like a drafted person's Release")
	check(Kit.texts(b).has("AUTO"), "still named Auto")
	ctx.sim.tactics.toggle_auto(ana)
	Kit.update(ctx)
	eq(Kit.gizmo(ctx, "auto").get_meta("on"), false, "and dark again when it is turned off")
	Kit.free_all(ctx)


func test_the_auto_tooltip_says_what_it_does_and_its_key() -> void:
	var ctx := Kit.build()
	_person(ctx, "dez")
	var lines := _lines(Kit.gizmo(ctx, "auto"))
	eq(lines.size(), 3, "three lines: '%s'" % Kit.gizmo(ctx, "auto").tooltip_text)
	eq(lines[0], "Auto-repair: by day, mends the most worn wall under %d%%" % roundi(Tactics.AUTO_BELOW * 100.0), "what it does")
	eq(lines[1], "while scrap is %d or more." % int(Tactics.AUTO_MIN_SCRAP), "and when")
	eq(lines[2], "Key: B", "the key")
	Kit.free_all(ctx)


func test_pressing_auto_reaches_main() -> void:
	var ctx := Kit.build()
	_person(ctx, "hector")
	Kit.gizmo(ctx, "auto").pressed.emit()
	eq(ctx.pressed, ["auto"], "by its id")
	Kit.free_all(ctx)


func test_the_person_panel_tags_auto_repair_while_it_is_on() -> void:
	var ctx := Kit.build()
	var dez = _person(ctx, "dez")
	var tag: PanelContainer = ctx.hud.inspect_refs.auto_tag
	check(not tag.visible, "no tag while it is off")
	check(not Kit.texts(ctx.hud.inspect).has("Auto-repair: on") or not tag.visible, "and no words")
	ctx.sim.tactics.toggle_auto(dez)
	Kit.update(ctx)
	tag = ctx.hud.inspect_refs.auto_tag
	check(tag.visible, "the tag shows when it is on")
	check(Kit.texts(tag).has("Auto-repair: on"), "and says so: %s" % str(Kit.texts(tag)))
	dez.dead = true
	Kit.update(ctx)
	check(not ctx.hud.inspect_refs.auto_tag.visible, "not for someone who is gone")
	Kit.free_all(ctx)


func test_the_tag_fits_beside_every_name_in_the_panel() -> void:
	var ctx := Kit.build()
	for p in ctx.sim.people:
		ctx.sim.tactics.autos[p.id] = true
	for p in ctx.sim.people:
		Kit.select(ctx, p)
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var tag: Rect2 = Kit.rect(ctx.hud.inspect_refs.auto_tag)
		var panel: Rect2 = Kit.rect(ctx.hud.inspect)
		check(tag.size != Vector2.ZERO and panel.encloses(tag), "%s: the tag is inside the panel" % p.first)
		var names: Array = []
		for l in ctx.hud.inspect.find_children("*", "Label", true, false):
			if l.text == p.name or l.text.begins_with(p.def.role):
				names.append(Kit.rect(l))
		for r in names:
			check(r.end.x <= tag.position.x + 0.5, "%s: the tag clears '%s' (%s, %s)" % [p.first, p.name, str(r), str(tag)])
		eq(panel.size.x, float(Hud.INSPECT_W), "%s: the tag does not widen the panel" % p.first)
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the forecast --

func test_the_forecast_line_is_absent_until_it_is_given() -> void:
	var ctx := Kit.build()
	Kit.update(ctx)
	check(not ctx.hud.forecast_label.visible and ctx.hud.forecast_label.text == "", "morning, nothing told: no line")
	ctx.sim.tactics.told = {"given": false}
	ctx.sim.phase = "night"
	Kit.update(ctx)
	check(not ctx.hud.forecast_label.visible, "at night with nobody to tell it: still none")
	Kit.free_all(ctx)


func test_the_forecast_line_says_how_many_and_from_where() -> void:
	var ctx := Kit.build()
	ctx.sim.tactics.told = Kit.forecast()
	Kit.update(ctx)
	var l: Label = ctx.hud.forecast_label
	check(l.visible, "given: the line is there")
	eq(l.text, "Tonight: about 55 from the north east", "the number and the way")
	ctx.sim.tactics.told = Kit.forecast({"total": 30, "heading": "north and west"})
	Kit.update(ctx)
	eq(l.text, "Tonight: about 30 from the north and west", "two ways, and it follows the rules")
	Kit.free_all(ctx)


func test_the_forecast_line_names_a_brute_or_runners_or_the_last_night() -> void:
	var ctx := Kit.build()
	var l: Label = ctx.hud.forecast_label
	var cases := [
		[{"brutes": 1}, "Tonight: about 55 from the north east, a brute"],
		[{"brutes": 2}, "Tonight: about 55 from the north east, 2 brutes"],
		[{"runners": true}, "Tonight: about 55 from the north east, runners"],
		[{"brutes": 1, "runners": true}, "Tonight: about 55 from the north east, a brute"],
		[{"big": true, "total": 120}, "The last night: about 120, from everywhere"],
		[{"heading": ""}, "Tonight: about 55"],
	]
	for c in cases:
		ctx.sim.tactics.told = Kit.forecast(c[0])
		Kit.update(ctx)
		eq(l.text, c[1], str(c[0]))
		check(l.visible, "%s is shown" % str(c[0]))
	Kit.free_all(ctx)


func test_the_forecast_line_stays_from_dusk_until_dawn() -> void:
	var ctx := Kit.build()
	ctx.sim.tactics.told = Kit.forecast()
	for phase in ["day", "dusk", "night"]:
		ctx.sim.phase = phase
		Kit.update(ctx)
		check(ctx.hud.forecast_label.visible, "still up in the %s" % phase)
	ctx.sim.phase = "dawn"
	Kit.update(ctx)
	check(not ctx.hud.forecast_label.visible, "gone at dawn: the night is over")
	ctx.sim.phase = "night"
	ctx.sim.tactics.told = {"given": false}
	Kit.update(ctx)
	check(not ctx.hud.forecast_label.visible, "and gone when he can no longer tell it (hurt, or away)")
	Kit.free_all(ctx)


func test_the_forecast_line_is_twelve_pixel_text_in_the_clocks_style() -> void:
	var ctx := Kit.build()
	var l: Label = ctx.hud.forecast_label
	eq(l.get_theme_font_size("font_size"), 12, "12 px")
	eq(l.get_theme_color("font_color"), Hud.INK2, "in the colour of the weather line")
	check(l.get_parent().get_parent() == ctx.hud.clock, "inside the clock, under its other rows")
	var rows: Array = l.get_parent().get_children()
	eq(rows[rows.size() - 1], l, "as the last row")
	Kit.free_all(ctx)


func test_the_forecast_line_pushes_the_alerts_down_instead_of_covering_them() -> void:
	for size in SIZES:
		var ctx := Kit.build(size[0], size[1])
		ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
		ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var before: Rect2 = Kit.rect(ctx.hud.alerts_box)
		ctx.sim.tactics.told = Kit.forecast({"brutes": 2, "heading": "north and west"})
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var clock: Rect2 = Kit.rect(ctx.hud.clock)
		var label: Rect2 = Kit.rect(ctx.hud.forecast_label)
		var alerts: Rect2 = Kit.rect(ctx.hud.alerts_box)
		var where := "%d x %d" % [size[0], size[1]]
		check(label.size != Vector2.ZERO and clock.encloses(label), "%s: the line is inside the clock (%s in %s)" % [where, str(label), str(clock)])
		var font: Font = ctx.hud.forecast_label.get_theme_font("font")
		var line_h := float(font.get_height(12))
		check(label.size.y + 0.5 >= float(ctx.hud.forecast_label.get_line_count()) * line_h, "%s: room for all %d lines of it" % [where, ctx.hud.forecast_label.get_line_count()])
		eq(Kit.overlaps({"clock": clock, "alerts": alerts}), [], "%s: the alerts clear the clock" % where)
		check(alerts.position.y > before.position.y - 0.5, "%s: and sit as low or lower than before" % where)
		check(Rect2(0, 0, size[0], size[1]).encloses(clock.grow(-0.5)), "%s: the clock is in the window" % where)
		Kit.free_all(ctx)


# ---------------------------------------------------------------- alert icons --

func test_the_new_alerts_wear_their_icons() -> void:
	var ctx := Kit.build()
	var expected := {"brute": "walker", "runners": "walker", "lure": "bell", "forecast": "bell", "bignight": "bell"}
	for id in expected:
		# the level's own icon would be the warning triangle: the id has to win
		eq(ctx.hud._alert_icon_name({"id": id, "level": "warn"}), expected[id], "%s is told by its id" % id)
	for id in expected:
		ctx.sim.alert(id, "warn", "Alert %s" % id, "line", null, 60.0)
	Kit.update(ctx)
	for id in expected:
		var it: Dictionary = ctx.hud.alert_items.get(id, {})
		check(not it.is_empty() and it.panel != null, "%s is in the feed" % id)
		if not it.is_empty() and it.panel != null:
			eq((it.icon as TextureRect).texture, ctx.hud.icons[expected[id]], "%s shows the %s icon" % [id, expected[id]])
	Kit.free_all(ctx)


func test_the_old_alert_icons_are_still_theirs() -> void:
	var ctx := Kit.build()
	var expected := {"seg-3": "wall", "horde": "walker", "bell": "bell", "no-ammo": "ammo", "rain": "water"}
	for id in expected:
		eq(ctx.hud._alert_icon_name({"id": id, "level": "warn"}), expected[id], id)
	Kit.free_all(ctx)


# ----------------------------------------------------- fields-of-fire button --

func test_the_fields_button_sits_with_the_speed_controls_and_says_its_key() -> void:
	var ctx := Kit.build()
	var b: Button = ctx.hud.fields_button
	check(b != null and b.get_parent().get_parent() == ctx.hud.speed_panel, "in the speed panel")
	var lines := _lines(b)
	check(lines.size() == 2 and lines[0].begins_with("Fields of fire") and lines[0].length() > 20, "says what it shows: '%s'" % b.tooltip_text)
	eq(lines[1], "Key: V", "and its key")
	Kit.free_all(ctx)


func test_the_fields_view_lights_its_button_and_shows_the_legend() -> void:
	var ctx := Kit.build()
	var b: Button = ctx.hud.fields_button
	check(not ctx.hud.fields_legend.visible, "no legend while the view is off")
	eq(b.get_meta("icon").modulate, Hud.INK2, "the button is dark")
	ctx.hud.set_fields(true)
	check(ctx.hud.fields_legend.visible, "the legend is up with the view")
	eq(b.get_meta("icon").modulate, Hud.ACCENT, "and the button is lit")
	eq((b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, Color(Hud.ACCENT, 0.16), "with the glow of the active speed")
	ctx.hud.set_fields(false)
	check(not ctx.hud.fields_legend.visible, "gone with it")
	eq(b.get_meta("icon").modulate, Hud.INK2, "dark again")
	Kit.free_all(ctx)


func test_pressing_the_fields_button_asks_main_to_flip_the_view() -> void:
	var ctx := Kit.build()
	ctx.hud.fields_button.pressed.emit()
	check(true, "with nobody listening a press does nothing and breaks nothing")
	var seen: Array = []
	ctx.hud.on_fields = func(): seen.append(true)
	ctx.hud.fields_button.pressed.emit()
	eq(seen.size(), 1, "main.gd is asked once")
	await Kit.settle()
	await Kit.settle()
	Kit.click_on(ctx.hud.fields_button)
	eq(seen.size(), 2, "and a click does too")
	Kit.free_all(ctx)


func test_the_legend_explains_the_three_tints() -> void:
	var ctx := Kit.build()
	ctx.hud.set_fields(true)
	var all := Kit.texts(ctx.hud.fields_legend)
	check(all.has("FIELDS OF FIRE"), "titled: %s" % str(all))
	check(all.has("Red: no gun reaches it"), "red is no gun")
	check(all.has("Amber: one gun"), "amber is one")
	check(all.has("Green: two or more"), "green is two or more")
	eq(ctx.hud.fields_legend.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks pass through it to the world")
	Kit.free_all(ctx)


func test_the_legend_and_the_world_use_the_same_three_colours() -> void:
	for i in 3:
		eq(Hud.FIELDS_LEGEND[i][0], OverlayNode.cover_color(i), "tint %d" % i)
	eq(OverlayNode.cover_color(7), Hud.OK, "and more than two guns is still green")
	eq(OverlayNode.cover_color(-1), Hud.DANGER, "and nonsense reads as none")


func test_the_legend_leaves_the_rest_of_the_screen_alone_at_every_size() -> void:
	for size in SIZES:
		var ctx := Kit.build(size[0], size[1])
		var ana = Kit.person(ctx, "ana")
		ctx.sim.medical.treat[ana.id] = true
		ctx.sim.medical.sendout[ana.id] = true
		ctx.sim.scavenge.can = true
		ctx.sim.tactics.told = Kit.forecast({"brutes": 2, "heading": "north and west"})
		ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
		ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
		ctx.hud.set_fields(true)
		Kit.select(ctx, ana)
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var h = ctx.hud
		var where := "%d x %d" % [size[0], size[1]]
		eq(h.fields_legend.visible, float(size[1]) >= Hud.LEGEND_MIN_H, "%s: the legend shows when the window is tall enough" % where)
		var rects := {"stores": Kit.rect(h.res_panel), "legend": Kit.rect(h.fields_legend), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock), "alerts": Kit.rect(h.alerts_box), "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos), "speed": Kit.rect(h.speed_panel)}
		eq(Kit.overlaps(rects), [], "%s: nothing overlaps with the legend and the forecast up" % where)
		var win := Rect2(0, 0, size[0], size[1])
		for name in rects:
			if rects[name].size != Vector2.ZERO:
				check(win.encloses(rects[name].grow(-0.5)), "%s: %s is inside the window: %s" % [where, name, str(rects[name])])
		# with the controls help open as well (it may cover the alerts, as before)
		h.help.visible = true
		await Kit.settle()
		rects["help"] = Kit.rect(h.help)
		rects.erase("alerts")
		rects.erase("cards")
		eq(Kit.overlaps(rects), [], "%s: and with the controls open" % where)
		Kit.free_all(ctx)


func test_the_legend_comes_and_goes_when_the_window_is_resized() -> void:
	var ctx := Kit.build(1280, 800)
	ctx.hud.set_fields(true)
	check(ctx.hud.fields_legend.visible, "up in a tall window")
	Kit.resize(ctx, 1280, 560)
	await Kit.settle()
	await Kit.settle()
	check(not ctx.hud.fields_legend.visible, "away in a short one: it would not fit above the dock")
	check(ctx.hud.fields_on, "though the view itself stays on")
	Kit.resize(ctx, 1280, 800)
	await Kit.settle()
	await Kit.settle()
	check(ctx.hud.fields_legend.visible, "and back when the window grows")
	Kit.free_all(ctx)


# ---------------------------------------------------------- kinds of the dead --

func test_the_panel_of_a_runner_and_a_brute_names_what_it_is() -> void:
	var ctx := Kit.build()
	var runner = ctx.sim.spawn(40.0, 30.0, "approach", "runner")
	var brute = ctx.sim.spawn(44.0, 30.0, "approach", "brute")
	ctx.hud.select({"kind": "zombie", "ref": ctx.sim.zombies[0]})
	Kit.update(ctx)
	check(Kit.texts(ctx.hud.inspect).has("Walker"), "a walker is still a walker")
	ctx.hud.select({"kind": "zombie", "ref": runner})
	Kit.update(ctx)
	check(Kit.texts(ctx.hud.inspect).has("Runner"), "a runner: %s" % str(Kit.texts(ctx.hud.inspect)))
	check(not Kit.texts(ctx.hud.inspect).has("Walker"), "and not a walker")
	eq(ctx.hud.inspect_refs.doing.text, "Running toward the wall", "it runs")
	ctx.hud.select({"kind": "zombie", "ref": brute})
	Kit.update(ctx)
	check(Kit.texts(ctx.hud.inspect).has("Brute"), "a brute")
	eq(ctx.hud.inspect_refs.doing.text, "Lumbering toward the wall", "it lumbers")
	# its health bar is for a thing with a good many hit points, not five: full at the middle of its range
	var fresh := (float(Kinds.KINDS.brute.hp[0]) + float(Kinds.KINDS.brute.hp[1])) / 2.0
	brute.hp = fresh
	Kit.update(ctx)
	eq(ctx.hud.inspect_refs.hpv.text, "100%", "fresh")
	brute.hp = fresh / 2.0
	Kit.update(ctx)
	eq(ctx.hud.inspect_refs.hpv.text, "50%", "half")
	Kit.free_all(ctx)
