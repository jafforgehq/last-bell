extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")


func _mark(icon: String, color: Color, tip: String) -> Dictionary:
	return {"icon": icon, "color": color, "tip": tip}


func test_a_card_shows_the_status_marks_of_its_person() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	ctx.sim.supplies.marks[ana.id] = [_mark("hungry", Hud.WARN, "Hungry")]
	ctx.sim.medical.marks[ana.id] = [_mark("wound", Hud.DANGER, "Bleeding")]
	Kit.update(ctx)
	var c := Kit.card(ctx, ana)
	eq(c.marks.get_child_count(), 2, "two marks on Ana's card")
	var first: TextureRect = c.marks.get_child(0)
	var second: TextureRect = c.marks.get_child(1)
	eq(first.texture, ctx.hud.icons["hungry"], "the hungry icon")
	eq(first.modulate, Hud.WARN, "tinted by the mark's colour")
	eq(first.tooltip_text, "Hungry", "with the tip as its tooltip")
	eq(second.texture, ctx.hud.icons["wound"], "the wound icon")
	eq(second.modulate, Hud.DANGER, "in red")
	eq(second.tooltip_text, "Bleeding", "and its tip")
	check(c.marks_box.visible, "the row is shown")
	var other := Kit.card(ctx, Kit.person(ctx, "ruth"))
	check(not other.marks_box.visible, "nobody else has a row")
	Kit.free_all(ctx)


func test_marks_follow_the_state_and_go_away() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	ctx.sim.medical.marks[ana.id] = [_mark("fever", Hud.WARN, "Feverish")]
	Kit.update(ctx)
	eq(Kit.card(ctx, ana).marks.get_child_count(), 1, "a fever mark")
	ctx.sim.medical.marks[ana.id] = []
	Kit.update(ctx)
	eq(Kit.card(ctx, ana).marks.get_child_count(), 0, "gone when the state is")
	check(not Kit.card(ctx, ana).marks_box.visible, "and the row hides")
	Kit.free_all(ctx)


func test_more_marks_than_fit_are_cut_to_what_the_card_can_hold() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	var many: Array = []
	for icon in ["hungry", "thirsty", "wound", "fever", "down", "resting"]:
		many.append(_mark(icon, Hud.WARN, icon))
	ctx.sim.medical.marks[ana.id] = many
	Kit.update(ctx)
	var n: int = Kit.card(ctx, ana).marks.get_child_count()
	check(n >= 3 and n <= 4, "three or four marks fit, got %d" % n)
	Kit.free_all(ctx)


func test_an_unknown_icon_still_gets_a_mark() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	ctx.sim.medical.marks[ana.id] = [_mark("no-such-icon", Hud.INFO, "Something odd")]
	Kit.update(ctx)
	var c := Kit.card(ctx, ana)
	eq(c.marks.get_child_count(), 1, "a placeholder mark")
	eq(c.marks.get_child(0).tooltip_text, "Something odd", "with the tip")
	Kit.free_all(ctx)


func test_a_dead_person_has_a_dimmed_card_with_a_word() -> void:
	var ctx := Kit.build()
	var walt = Kit.person(ctx, "walt")
	var c := Kit.card(ctx, walt)
	Kit.update(ctx)
	check(not c.veil.visible, "a living person's card is not dimmed")
	eq(c.word.text, "", "and says nothing")
	walt.dead = true
	Kit.update(ctx)
	check(c.veil.visible, "a dead person's card is dimmed")
	eq(c.word.text, "Died", "died")
	walt.turned = true
	Kit.update(ctx)
	eq(c.word.text, "Turned", "turned")
	walt.turned = false
	walt.away = {"kind": "exile"}
	Kit.update(ctx)
	eq(c.word.text, "Left", "sent out through the gate")
	check(c.veil.visible, "still dimmed")
	Kit.free_all(ctx)


func test_an_away_person_shows_away_and_is_not_marked_dead() -> void:
	var ctx := Kit.build()
	var dez = Kit.person(ctx, "dez")
	var c := Kit.card(ctx, dez)
	dez.away = {"kind": "party", "site": "pharmacy"}
	Kit.update(ctx)
	check(c.veil.visible, "the card is dimmed while they are out")
	eq(c.word.text, "Away", "away")
	dez.away = null
	Kit.update(ctx)
	check(not c.veil.visible, "back again")
	eq(c.word.text, "", "no word")
	Kit.free_all(ctx)


func test_the_badges_stay_for_the_living_and_hide_for_the_dead() -> void:
	var ctx := Kit.build()
	var marcus = Kit.person(ctx, "marcus")
	var c := Kit.card(ctx, marcus)
	marcus.drafted = true
	marcus.target = ctx.sim.zombies[0]
	Kit.update(ctx)
	check(c.badge.visible, "the draft badge")
	check(c.fight.visible, "the fight badge")
	marcus.dead = true
	Kit.update(ctx)
	check(not c.badge.visible, "no draft badge on the dead")
	check(not c.fight.visible, "no fight badge on the dead")
	check(not c.marks_box.visible, "and no marks")
	Kit.free_all(ctx)


func test_the_health_bar_stays() -> void:
	var ctx := Kit.build()
	var ruth = Kit.person(ctx, "ruth")
	ruth.hp = 50.0
	Kit.update(ctx)
	var c := Kit.card(ctx, ruth)
	near(c.hp.size.x, c.hp_bg.size.x * 0.5, 0.01, "half a bar")
	Kit.free_all(ctx)


func test_clicking_a_card_selects_the_person() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	Kit.update(ctx)
	await Kit.settle()
	var c := Kit.card(ctx, ana)
	var r: Rect2 = c.card.get_global_rect()
	Kit.click(r.position + Vector2(r.size.x * 0.5, 8.0))
	await Kit.settle()
	eq(ctx.selected.size(), 1, "one selection came through")
	Kit.free_all(ctx)


func test_clicking_a_status_mark_still_selects_the_person() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	ctx.sim.medical.marks[ana.id] = [_mark("wound", Hud.DANGER, "Bleeding")]
	Kit.update(ctx)
	await Kit.settle()
	var c := Kit.card(ctx, ana)
	var mark: Control = c.marks.get_child(0)
	check(mark.get_global_rect().size.x > 4.0, "the mark has a size: %s" % str(mark.get_global_rect()))
	Kit.click(mark.get_global_rect().get_center())
	await Kit.settle()
	eq(ctx.selected.size(), 1, "one selection came through")
	if ctx.selected.size() == 1:
		eq(ctx.selected[0].ref, ana, "it is Ana")
	Kit.free_all(ctx)
