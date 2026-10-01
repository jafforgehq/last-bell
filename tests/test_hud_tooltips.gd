extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")

## The order buttons and their keys (main.gd's _unhandled_input).
const KEYS := {"draft": "R", "post": "P", "repair": "F", "focus": "C", "auto": "B", "treat": "T", "sendout": "X", "scavenge": "G"}


## Ana selected with every button on offer.
func _everything(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := Kit.build(width, height)
	var ana = Kit.person(ctx, "ana")
	ctx.sim.medical.treat[ana.id] = true
	ctx.sim.medical.sendout[ana.id] = true
	ctx.sim.scavenge.can = true
	Kit.select(ctx, ana)
	Kit.update(ctx)
	return ctx


func _lines(b: Button) -> PackedStringArray:
	return b.tooltip_text.split("\n")


func _check_all_eight(ctx: Dictionary, where: String) -> void:
	eq(Kit.gizmo_ids(ctx).size(), 8, "%s: all eight buttons" % where)
	for id in KEYS:
		var b: Button = Kit.gizmo(ctx, id)
		if b == null:
			failures.append("%s: no %s button" % [where, id])
			continue
		var lines := _lines(b)
		check(lines.size() >= 2, "%s: %s has a first line and a key line: '%s'" % [where, id, b.tooltip_text])
		if lines.size() < 2:
			continue
		check(lines[0].length() > 8 and not lines[0].begins_with("Key"), "%s: %s says what it does: '%s'" % [where, id, lines[0]])
		# the key is its own line: the second one, or the third when the order has a second line of its own (auto-repair)
		check(lines.has("Key: %s" % KEYS[id]), "%s: %s names its key: '%s'" % [where, id, b.tooltip_text])


func test_every_order_button_has_a_tooltip_in_the_full_size_too() -> void:
	var ctx := _everything()
	check(not ctx.hud.gizmo_mini, "the big buttons")
	_check_all_eight(ctx, "big")
	Kit.free_all(ctx)


func test_and_in_the_small_size() -> void:
	var ctx := _everything(700, 560)
	check(ctx.hud.gizmo_mini, "the small buttons")
	_check_all_eight(ctx, "small")
	Kit.free_all(ctx)


func test_the_first_line_names_the_order_in_plain_words() -> void:
	var ctx := _everything()
	var words := {"draft": "Draft", "post": "To post", "repair": "Repair", "focus": "Follow", "auto": "Auto-repair", "treat": "Treat", "sendout": "Send out", "scavenge": "Scavenge"}
	for id in words:
		var first: String = _lines(Kit.gizmo(ctx, id))[0]
		check(first.begins_with(words[id]), "%s starts with its name: '%s'" % [id, first])
		check(first.contains(":"), "and then says what it does: '%s'" % first)
	Kit.free_all(ctx)


func test_the_draft_tooltip_follows_the_draft() -> void:
	var ctx := _everything()
	var ana = Kit.person(ctx, "ana")
	check(_lines(Kit.gizmo(ctx, "draft"))[0].begins_with("Draft"), "draft first")
	ana.drafted = true
	Kit.update(ctx)
	var lines := _lines(Kit.gizmo(ctx, "draft"))
	check(lines[0].begins_with("Release"), "then release: '%s'" % lines[0])
	eq(lines[1], "Key: R", "same key")
	Kit.free_all(ctx)


func test_repair_says_why_when_nothing_is_damaged() -> void:
	var ctx := _everything()
	var tip: String = Kit.gizmo(ctx, "repair").tooltip_text
	check(tip.contains("nothing is damaged"), "all walls whole: '%s'" % tip)
	check(_lines(Kit.gizmo(ctx, "repair"))[2].begins_with("Not now"), "as its own line")
	ctx.sim.segments[3].hp = ctx.sim.segments[3].max_hp * 0.4
	Kit.update(ctx)
	tip = Kit.gizmo(ctx, "repair").tooltip_text
	check(not tip.contains("Not now"), "a damaged wall: nothing to say against it: '%s'" % tip)
	eq(_lines(Kit.gizmo(ctx, "repair")).size(), 2, "just the two lines")
	ctx.sim.stock.scrap = 0.0
	Kit.update(ctx)
	tip = Kit.gizmo(ctx, "repair").tooltip_text
	check(tip.contains("no scrap"), "no scrap: '%s'" % tip)
	Kit.free_all(ctx)


func test_a_downed_person_cannot_go_to_a_post_or_repair() -> void:
	var ctx := _everything()
	var ana = Kit.person(ctx, "ana")
	ctx.sim.segments[3].hp = 10.0
	ana.downed = true
	Kit.update(ctx)
	for id in ["post", "repair"]:
		var tip: String = Kit.gizmo(ctx, id).tooltip_text
		check(tip.contains("Ana is down"), "%s says why: '%s'" % [id, tip])
	ana.downed = false
	Kit.update(ctx)
	check(not Kit.gizmo(ctx, "post").tooltip_text.contains("Not now"), "up again: no objection")
	Kit.free_all(ctx)


func test_treat_says_when_the_medicine_is_short() -> void:
	var ctx := _everything()
	var ana = Kit.person(ctx, "ana")
	ana.infected_at = 5.0
	ctx.sim.stock.meds = 1.0
	Kit.update(ctx)
	var tip: String = Kit.gizmo(ctx, "treat").tooltip_text
	check(tip.contains("not enough medicine"), "an infection takes two: '%s'" % tip)
	ctx.sim.stock.meds = 5.0
	Kit.update(ctx)
	check(not Kit.gizmo(ctx, "treat").tooltip_text.contains("Not now"), "with enough: no objection")
	Kit.free_all(ctx)


func test_a_button_that_cannot_be_used_looks_ghosted_but_still_works() -> void:
	var ctx := _everything()
	var b: Button = Kit.gizmo(ctx, "repair")
	check(b.modulate.a < 0.9, "dimmed")
	check(not b.disabled, "but not disabled: the order still goes through")
	ctx.sim.segments[3].hp = 10.0
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "repair").modulate.a > 0.99, "and bright once it can be used")
	Kit.free_all(ctx)


func test_a_wall_piece_has_tooltips_for_repair_and_focus() -> void:
	var ctx := Kit.build()
	var seg = ctx.sim.segments[3]
	ctx.hud.select({"kind": "segment", "ref": seg})
	Kit.update(ctx)
	var repair: Button = Kit.gizmo(ctx, "repair")
	var focus: Button = Kit.gizmo(ctx, "focus")
	eq(_lines(repair)[1], "Key: F", "repair key")
	eq(_lines(focus)[1], "Key: C", "focus key")
	check(repair.tooltip_text.contains("not damaged"), "a whole piece: '%s'" % repair.tooltip_text)
	seg.hp = seg.max_hp * 0.5
	Kit.update(ctx)
	check(not Kit.gizmo(ctx, "repair").tooltip_text.contains("Not now"), "a damaged one can be repaired")
	for p in ctx.sim.people:
		p.downed = true
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "repair").tooltip_text.contains("nobody is free"), "with everyone down: '%s'" % Kit.gizmo(ctx, "repair").tooltip_text)
	Kit.free_all(ctx)


func test_a_dead_person_and_a_walker_have_a_focus_tooltip() -> void:
	var ctx := Kit.build()
	var hector = Kit.person(ctx, "hector")
	hector.dead = true
	Kit.select(ctx, hector)
	Kit.update(ctx)
	eq(_lines(Kit.gizmo(ctx, "focus"))[1], "Key: C", "a body")
	ctx.hud.select({"kind": "zombie", "ref": ctx.sim.zombies[0]})
	Kit.update(ctx)
	eq(_lines(Kit.gizmo(ctx, "focus"))[1], "Key: C", "a walker")
	Kit.free_all(ctx)


func test_the_speed_buttons_say_what_they_do_and_their_keys() -> void:
	var ctx := Kit.build()
	var keys := ["Space", "1", "2", "3"]
	for i in 4:
		var lines := _lines(ctx.hud.speed_buttons[i])
		check(lines.size() == 2 and lines[0].length() > 6, "speed %d has a first line: '%s'" % [i, ctx.hud.speed_buttons[i].tooltip_text])
		if lines.size() == 2:
			eq(lines[1], "Key: %s" % keys[i], "speed %d key" % i)
	Kit.free_all(ctx)


func test_the_sound_button_says_what_a_press_will_do() -> void:
	var ctx := Kit.build()
	ctx.hud.update_hud(ctx.sim, 1, true, 4)
	var on_tip: String = ctx.hud.sound_button.tooltip_text
	check(on_tip.to_lower().contains("sound") and on_tip.to_lower().contains("off"), "sound is on: it offers to turn it off: '%s'" % on_tip)
	ctx.hud.update_hud(ctx.sim, 1, false, 4)
	var off_tip: String = ctx.hud.sound_button.tooltip_text
	check(off_tip.to_lower().contains("sound") and off_tip.to_lower().contains(" on"), "sound is off: it offers to turn it on: '%s'" % off_tip)
	check(not off_tip.contains("Key:"), "there is no key for it")
	Kit.free_all(ctx)


func test_the_help_button_has_a_tooltip() -> void:
	var ctx := Kit.build()
	check(ctx.hud.help_button != null and ctx.hud.help_button.tooltip_text.to_lower().contains("controls"), "it names the controls")
	Kit.free_all(ctx)


func test_the_tooltip_looks_like_the_hud() -> void:
	var ctx := Kit.build()
	var theme: Theme = ctx.hud.theme
	check(theme != null, "the HUD carries a small theme for its tooltips")
	if theme != null:
		check(theme.has_stylebox("panel", "TooltipPanel"), "a panel look")
		var sb = theme.get_stylebox("panel", "TooltipPanel")
		check(sb is StyleBoxFlat and sb.bg_color.a >= 0.9, "dark and solid enough to read")
		check(theme.get_font_size("font_size", "TooltipLabel") >= 12, "at least 12 px")
		eq(theme.get_color("font_color", "TooltipLabel"), Hud.INK, "in the HUD's ink")
		check(theme.has_font("font", "TooltipLabel"), "in the HUD's font")
	# the theme reaches the buttons: they find it through their parents
	var b: Button = ctx.hud.speed_buttons[0]
	check(b.get_theme_stylebox("panel", "TooltipPanel") != null and b.get_theme_font_size("font_size", "TooltipLabel") >= 12, "and the controls under the HUD see it")
	Kit.free_all(ctx)


## Moves the mouse over `c` and waits for the tooltip delay, as a player resting the cursor does.
func _hover(c: Control) -> void:
	var tree := Engine.get_main_loop()
	var pos := c.get_global_rect().get_center()
	for step in 3:
		var ev := InputEventMouseMotion.new()
		ev.position = pos + Vector2(step, 0)
		ev.global_position = ev.position
		ev.relative = Vector2(1, 0)
		tree.root.push_input(ev, true)
		await tree.process_frame
	await tree.create_timer(0.8).timeout
	await tree.process_frame


## The tooltip popup now up in the window, or null.
func _tooltip_popup() -> Node:
	for n in Engine.get_main_loop().root.find_children("*", "PopupPanel", true, false):
		if n.theme_type_variation == "TooltipPanel" and n.visible:
			return n
	return null


func test_resting_the_mouse_on_a_button_shows_its_tooltip_in_the_huds_look() -> void:
	var ctx := _everything()
	await Kit.settle()
	var draft: Button = Kit.gizmo(ctx, "draft")
	await _hover(draft)
	var popup := _tooltip_popup()
	check(popup != null, "a tooltip is up")
	if popup != null:
		var label: Label = popup.find_children("*", "Label", true, false)[0]
		eq(label.text, draft.tooltip_text, "it says what the button's tooltip says")
		check(label.get_theme_font_size("font_size") >= 12, "at 12 px or more")
		eq(label.get_theme_color("font_color"), Hud.INK, "in the HUD's ink")
		var box = popup.get_theme_stylebox("panel")
		check(box is StyleBoxFlat and box.bg_color.a >= 0.9 and box.bg_color.v < 0.2, "on a dark, solid panel like the HUD's")
	Kit.free_all(ctx)
	await Kit.settle()


func test_the_small_buttons_show_theirs_too() -> void:
	var ctx := _everything(700, 560)
	await Kit.settle()
	await Kit.settle()
	var repair: Button = Kit.gizmo(ctx, "repair")
	await _hover(repair)
	var popup := _tooltip_popup()
	check(popup != null, "a tooltip is up")
	if popup != null:
		var label: Label = popup.find_children("*", "Label", true, false)[0]
		check(label.text.begins_with("Repair") and label.text.contains("Key: F") and label.text.contains("Not now: nothing is damaged"), "with the name, the key and the reason: '%s'" % label.text)
	Kit.free_all(ctx)
	await Kit.settle()
