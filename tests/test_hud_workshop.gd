extends "res://tests/case.gd"
## Round 3, the workshop in the HUD: the Make ammo button (key M) for a person, lit while they are
## at the worktable, its tooltip (what it does, what it makes, the key, why not), the "Making ammo"
## tag in the person panel, the help table's M and the alert's icon. The rules are in
## tests/test_workshop.gd; here the module is Kit.FakeWorkshop, a table-driven stand-in with the
## real rates, and in one test the real module.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Workshop := preload("res://scripts/sim/workshop.gd")


func _lines(b: Button) -> PackedStringArray:
	return b.tooltip_text.split("\n")


## A person selected and the HUD updated.
func _person(ctx: Dictionary, id: String):
	var p = Kit.person(ctx, id)
	Kit.select(ctx, p)
	Kit.update(ctx)
	return p


func test_a_person_gets_a_make_ammo_button_with_its_name_key_and_icon() -> void:
	var ctx := Kit.build()
	_person(ctx, "dez")
	var b: Button = Kit.gizmo(ctx, "craft")
	check(b != null, "the button is there")
	check(Kit.texts(b).has("MAKE AMMO"), "named: %s" % str(Kit.texts(b)))
	check(Kit.texts(b).has("M"), "with its key")
	eq(b.get_meta("key"), "M", "the key is M")
	var icons: Array = b.find_children("*", "TextureRect", true, false)
	check(not icons.is_empty() and icons[0].texture == ctx.hud.icons["ammo"], "wearing the ammo store's icon")
	eq(Hud.GIZMO_ICON.get("craft"), "ammo", "by the icon table")
	Kit.free_all(ctx)


func test_it_comes_after_the_standing_order_and_before_the_modules_buttons() -> void:
	var ctx := Kit.build()
	var p = _person(ctx, "ana")
	ctx.sim.medical.treat[p.id] = true
	ctx.sim.medical.sendout[p.id] = true
	ctx.sim.scavenge.can = true
	Kit.update(ctx)
	var ids := Kit.gizmo_ids(ctx)
	eq(ids.slice(0, 6), ["draft", "post", "repair", "focus", "auto", "craft"], "the always-there buttons keep their places")
	eq(ids.slice(6), ["treat", "sendout", "scavenge"], "the ones that come and go are after them")
	Kit.free_all(ctx)


func test_the_tooltip_says_what_it_does_what_it_makes_and_its_key() -> void:
	var ctx := Kit.build()
	var p = _person(ctx, "ana")
	var lines := _lines(Kit.gizmo(ctx, "craft"))
	eq(lines.size(), 3, "three lines when nothing is against it: '%s'" % Kit.gizmo(ctx, "craft").tooltip_text)
	eq(lines[0], "Make ammo: turns scrap into ammo at the worktable", "what it does")
	var per: float = ctx.sim.workshop.AMMO_PER_SCRAP
	var hourly := int(roundf(ctx.sim.workshop.scrap_per_hour(p) * ctx.sim.perf(p) * per))
	eq(lines[1], "1 scrap makes %d ammo. Ana makes about %d ammo an hour." % [int(per), hourly], "the rate, from the workshop's own numbers")
	eq(lines[2], "Key: M", "the key")
	Kit.free_all(ctx)


func test_the_rate_follows_who_is_selected_and_how_well_they_are() -> void:
	var ctx := Kit.build()
	var dez = _person(ctx, "dez")
	var fast := _lines(Kit.gizmo(ctx, "craft"))[1]
	var hector = _person(ctx, "hector")
	var slow := _lines(Kit.gizmo(ctx, "craft"))[1]
	var per := int(ctx.sim.workshop.AMMO_PER_SCRAP)
	check(fast.begins_with("1 scrap makes %d ammo. Dez makes about " % per) and slow.begins_with("1 scrap makes %d ammo. Hector makes about " % per), "named: '%s' / '%s'" % [fast, slow])
	check(fast != slow.replace("Hector", "Dez"), "Dez the builder makes more than Hector: '%s' / '%s'" % [fast, slow])
	# hunger slows them: the words follow the rules' own factor
	_person(ctx, "dez")
	var before := _lines(Kit.gizmo(ctx, "craft"))[1]
	dez.hunger_h = 40.0
	Kit.update(ctx)
	var after := _lines(Kit.gizmo(ctx, "craft"))[1]
	check(after != before, "a starving Dez makes less: '%s' then '%s'" % [before, after])
	Kit.free_all(ctx)


func test_it_says_why_not_and_is_ghosted_but_still_pressable() -> void:
	var ctx := Kit.build()
	_person(ctx, "ruth")
	var b: Button = Kit.gizmo(ctx, "craft")
	check(b.modulate.a > 0.99, "bright while they can go")
	ctx.sim.workshop.why = "it is night: everyone is at their post"
	Kit.update(ctx)
	var lines := _lines(b)
	eq(lines.size(), 4, "a fourth line when it cannot start: '%s'" % b.tooltip_text)
	eq(lines[2], "Key: M", "the key stays where it was")
	eq(lines[3], "Not now: it is night: everyone is at their post.", "and the reason is the workshop's own")
	check(b.modulate.a < 0.9, "ghosted")
	check(not b.disabled, "but not disabled: the order goes through and the game says why")
	ctx.sim.workshop.why = ""
	Kit.update(ctx)
	check(b.modulate.a > 0.99 and _lines(b).size() == 3, "and bright again when it can")
	Kit.free_all(ctx)


func test_it_lights_while_they_work_and_can_always_call_them_back() -> void:
	var ctx := Kit.build()
	var ruth = _person(ctx, "ruth")
	var b: Button = Kit.gizmo(ctx, "craft")
	eq(b.get_meta("on"), false, "dark at first")
	var off_box: StyleBox = b.get_theme_stylebox("normal")
	if off_box is StyleBoxFlat:
		eq(off_box.bg_color, Hud.PANEL, "like the others")
	ctx.sim.workshop.at_bench[ruth.id] = true
	# at night they would be refused a new order, but someone at the bench can always be called off it
	ctx.sim.workshop.why = "it is night: everyone is at their post"
	Kit.update(ctx)
	b = Kit.gizmo(ctx, "craft")
	eq(b.get_meta("on"), true, "lit while the workshop says they are at it")
	var on_box: StyleBox = b.get_theme_stylebox("normal")
	if on_box is StyleBoxFlat:
		eq(on_box.bg_color, Hud.ACCENT, "gold, like Auto when it is on")
	check(b.modulate.a > 0.99, "not ghosted: pressing it calls them back")
	var lines := _lines(b)
	check(lines[0].begins_with("Make ammo:") and lines[0].contains("worktable"), "the first line still names the order: '%s'" % lines[0])
	check(not b.tooltip_text.contains("Not now"), "and has no objection: '%s'" % b.tooltip_text)
	ctx.sim.workshop.at_bench.erase(ruth.id)
	Kit.update(ctx)
	eq(Kit.gizmo(ctx, "craft").get_meta("on"), false, "dark again when they stop")
	Kit.free_all(ctx)


func test_pressing_it_reaches_main_and_a_real_click_does_too() -> void:
	var ctx := Kit.build()
	_person(ctx, "hector")
	Kit.gizmo(ctx, "craft").pressed.emit()
	eq(ctx.pressed, ["craft"], "a press reaches main.gd by its id")
	await Kit.settle()
	await Kit.settle()
	Kit.click_on(Kit.gizmo(ctx, "craft"))
	eq(ctx.pressed, ["craft", "craft"], "and a mouse click does")
	Kit.free_all(ctx)


func test_only_a_person_has_it_and_only_one_who_is_here() -> void:
	var ctx := Kit.build()
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "craft") == null, "not for a wall piece")
	ctx.hud.select({"kind": "zombie", "ref": ctx.sim.zombies[0]})
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "craft") == null, "nor for a walker")
	var walt = _person(ctx, "walt")
	walt.dead = true
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "craft") == null, "nor for the dead")
	walt.dead = false
	walt.away = {"kind": "party", "site": "houses"}
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "craft") == null, "nor for someone away")
	Kit.free_all(ctx)


func test_the_why_for_a_wall_or_nobody_is_plain() -> void:
	var ctx := Kit.build()
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
	Kit.update(ctx)
	eq(ctx.hud.why_not("craft"), "pick one of the crew first", "a wall piece cannot make ammo")
	_person(ctx, "ana")
	eq(ctx.hud.why_not("craft"), "", "a person who can: nothing against it")
	ctx.sim.workshop.why = "there is no scrap to spare"
	eq(ctx.hud.why_not("craft"), "there is no scrap to spare", "and when they cannot, the workshop says why")
	Kit.free_all(ctx)


func test_a_game_with_no_workshop_has_no_button_and_nothing_breaks() -> void:
	# an older stand-in for the sim, with the other modules but no `workshop` (a plain Dictionary
	# answers `sim.get("workshop")` with null, as an object with no such property does)
	var ctx := Kit.build()
	var ana = _person(ctx, "ana")
	var real_sim = ctx.hud.sim_ref
	ctx.hud.sim_ref = {"medical": ctx.sim.medical, "scavenge": ctx.sim.scavenge, "tactics": ctx.sim.tactics, "stock": ctx.sim.stock, "segments": ctx.sim.segments}
	check(ctx.hud._workshop() == null, "the HUD finds no module")
	ctx.hud._build_gizmos()
	check(Kit.gizmo(ctx, "craft") == null, "no button without a worktable")
	eq(Kit.gizmo_ids(ctx), ["draft", "post", "repair", "focus", "auto"], "the usual buttons only")
	eq(ctx.hud.why_not("craft"), "", "nothing to say about it")
	check(not ctx.hud._crafting_on(ana), "nobody is at a bench that is not there")
	check(ctx.hud._gizmo_sig() != "", "the buttons' signature still works")
	ctx.hud.sim_ref = real_sim
	Kit.free_all(ctx)


# ------------------------------------------------------------------ the tag --

func test_the_person_panel_tags_making_ammo_while_the_workshop_mark_is_on_them() -> void:
	var ctx := Kit.build()
	var dez = _person(ctx, "dez")
	var tag: PanelContainer = ctx.hud.inspect_refs.craft_tag
	check(not tag.visible, "no tag while they are not at it")
	ctx.sim.workshop.at_bench[dez.id] = true
	Kit.update(ctx)
	tag = ctx.hud.inspect_refs.craft_tag
	check(tag.visible, "the tag shows with the mark")
	check(Kit.texts(tag).has("Making ammo"), "and says so: %s" % str(Kit.texts(tag)))
	eq(tag.tooltip_text, "Making ammo at the worktable", "with the mark's own tip")
	dez.dead = true
	Kit.update(ctx)
	check(not ctx.hud.inspect_refs.craft_tag.visible, "not for someone who is gone")
	Kit.free_all(ctx)


func test_the_card_shows_the_ammo_mark_too() -> void:
	var ctx := Kit.build()
	var dez = Kit.person(ctx, "dez")
	ctx.sim.workshop.at_bench[dez.id] = true
	Kit.update(ctx)
	var c := Kit.card(ctx, dez)
	var found := false
	for m in c.marks.get_children():
		if m.texture == ctx.hud.icons["ammo"]:
			found = true
			eq(m.tooltip_text, "Making ammo at the worktable", "with the tip")
	check(found, "an ammo icon among the marks on the card")
	Kit.free_all(ctx)


func test_both_tags_fit_beside_every_name() -> void:
	var ctx := Kit.build()
	for p in ctx.sim.people:
		ctx.sim.tactics.autos[p.id] = true
		ctx.sim.workshop.at_bench[p.id] = true
	for p in ctx.sim.people:
		Kit.select(ctx, p)
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var panel: Rect2 = Kit.rect(ctx.hud.inspect)
		var auto: Rect2 = Kit.rect(ctx.hud.inspect_refs.auto_tag)
		var craft: Rect2 = Kit.rect(ctx.hud.inspect_refs.craft_tag)
		check(auto.size != Vector2.ZERO and craft.size != Vector2.ZERO, "%s: both tags show" % p.first)
		check(panel.encloses(auto) and panel.encloses(craft), "%s: both are inside the panel (%s %s in %s)" % [p.first, str(auto), str(craft), str(panel)])
		eq(Kit.overlaps({"auto": auto, "craft": craft}), [], "%s: and do not overlap" % p.first)
		for l in ctx.hud.inspect.find_children("*", "Label", true, false):
			if l.text == p.name or l.text.begins_with(p.def.role):
				var r := Kit.rect(l)
				check(r.end.x <= minf(auto.position.x, craft.position.x) + 0.5, "%s: the tags clear '%s' (%s)" % [p.first, l.text, str(r)])
		eq(panel.size.x, float(Hud.INSPECT_W), "%s: and do not widen the panel" % p.first)
	Kit.free_all(ctx)


# ------------------------------------------------------------ help and alerts --

func test_the_help_table_lists_m() -> void:
	var ctx := Kit.build()
	var found := false
	for group in Hud.HELP:
		for entry in group[2]:
			if entry[0] == "M":
				found = true
				eq(entry[1], "Make ammo", "what M does")
	check(found, "M is in the orders group")
	check(Kit.texts(ctx.hud.help).has("Make ammo"), "and on the panel")
	Kit.free_all(ctx)


func test_the_idle_worktable_alert_wears_the_ammo_icon() -> void:
	var ctx := Kit.build()
	eq(ctx.hud._alert_icon_name({"id": "workshop-idle", "level": "info"}), "ammo", "by its id")
	ctx.sim.alert("workshop-idle", "info", "The worktable is idle", "Only 3 scrap is left; it is kept for the walls", null, 60.0)
	Kit.update(ctx)
	var it: Dictionary = ctx.hud.alert_items.get("workshop-idle", {})
	check(not it.is_empty() and it.panel != null, "it is in the feed")
	if not it.is_empty() and it.panel != null:
		eq((it.icon as TextureRect).texture, ctx.hud.icons["ammo"], "with the ammo icon")
	Kit.free_all(ctx)


# ----------------------------------------------------------- the real module --

func test_with_the_real_workshop_the_button_tag_and_card_follow_the_rules() -> void:
	var ctx := Kit.build()
	var real = Workshop.new()
	real.setup(ctx.sim)
	ctx.sim.workshop = real
	var ana = _person(ctx, "ana")
	var b: Button = Kit.gizmo(ctx, "craft")
	check(b != null and b.get_meta("on") == false, "dark by day with scrap in the stock")
	eq(_lines(b).size(), 3, "and nothing against it: '%s'" % b.tooltip_text)
	check(_lines(b)[1].begins_with("1 scrap makes %d ammo." % int(real.AMMO_PER_SCRAP)), "the real rate: '%s'" % _lines(b)[1])
	# the order, as main sends it
	check(ctx.sim.handle_gizmo("craft", ctx.hud.selection), "the module takes the order")
	Kit.update(ctx)
	check(real.crafting(ana), "she is at it")
	b = Kit.gizmo(ctx, "craft")
	eq(b.get_meta("on"), true, "the button is lit")
	check(ctx.hud.inspect_refs.craft_tag.visible, "the tag shows")
	check(Kit.card(ctx, ana).marks_box.visible, "and the card carries the mark")
	# at night a new order is refused and the button says why
	real.stop(ana)
	ctx.sim.minutes = 22.0 * 60.0
	ctx.sim.phase = "night"
	Kit.update(ctx)
	b = Kit.gizmo(ctx, "craft")
	check(b.modulate.a < 0.9 and b.tooltip_text.contains("Not now: it is night"), "night: '%s'" % b.tooltip_text)
	eq(ctx.hud.why_not("craft"), real.why_not_craft(ana), "the HUD's why is the rules' why")
	Kit.free_all(ctx)
