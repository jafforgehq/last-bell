extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")


func _color(label: Label) -> Color:
	return label.get_theme_color("font_color")


func _open(ctx: Dictionary, id: String):
	var p = Kit.person(ctx, id)
	Kit.select(ctx, p)
	Kit.update(ctx)
	return p


func test_the_needs_row_reads_hunger_and_thirst() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "ana")
	var needs: Label = ctx.hud.inspect_refs.needs
	var cases := [
		[0.0, 0.0, "Fed", Hud.INK],
		[17.9, 13.9, "Fed", Hud.INK],
		[18.0, 0.0, "Hungry", Hud.WARN],
		[0.0, 14.0, "Thirsty", Hud.WARN],
		[36.0, 0.0, "Starving", Hud.DANGER_TEXT],
		[0.0, 24.0, "Parched", Hud.DANGER_TEXT],
		[20.0, 15.0, "Hungry, thirsty", Hud.WARN],
		[40.0, 15.0, "Starving, thirsty", Hud.DANGER_TEXT],
		[20.0, 30.0, "Hungry, parched", Hud.DANGER_TEXT],
	]
	for c in cases:
		p.hunger_h = c[0]
		p.thirst_h = c[1]
		Kit.update(ctx)
		eq(needs.text, c[2], "needs at hunger %s, thirst %s" % [c[0], c[1]])
		eq(_color(needs), c[3], "needs colour at hunger %s, thirst %s" % [c[0], c[1]])
	Kit.free_all(ctx)


func test_the_wounds_row_counts_open_wounds() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "marcus")
	var wounds: Label = ctx.hud.inspect_refs.wounds
	eq(wounds.text, "None", "no wounds")
	p.wounds = 1
	p.bleeding = 2.0
	Kit.update(ctx)
	eq(wounds.text, "1 wound, bleeding", "one wound")
	eq(_color(wounds), Hud.DANGER_TEXT, "in red (the brighter red that words use)")
	p.wounds = 3
	p.bleeding = 10.0
	Kit.update(ctx)
	eq(wounds.text, "3 wounds, bleeding", "three wounds")
	p.wounds = 0
	p.bleeding = 4.0
	Kit.update(ctx)
	eq(wounds.text, "Bleeding", "bleeding with no count")
	p.bleeding = 0.0
	Kit.update(ctx)
	eq(wounds.text, "None", "bandaged")
	Kit.free_all(ctx)


func test_the_infection_row_shows_only_the_fever_stage() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "walt")
	var refs: Dictionary = ctx.hud.inspect_refs
	check(not refs.infection.visible and not refs.infection_head.visible, "no infection row at first")
	p.infected_at = 10.0
	Kit.update(ctx)
	check(not refs.infection.visible, "infected but no symptoms yet: nothing is shown")
	ctx.sim.medical.stage[p.id] = "feverish"
	Kit.update(ctx)
	check(refs.infection.visible and refs.infection_head.visible, "the row appears with a fever")
	eq(refs.infection.text, "Feverish", "feverish")
	eq(_color(refs.infection), Hud.WARN, "in orange")
	ctx.sim.medical.stage[p.id] = "delirious"
	Kit.update(ctx)
	eq(refs.infection.text, "Delirious", "delirious")
	eq(_color(refs.infection), Hud.WARN, "also orange")
	ctx.sim.medical.stage[p.id] = ""
	Kit.update(ctx)
	check(not refs.infection.visible, "and it goes when the infection does")
	Kit.free_all(ctx)


func test_the_doing_row_tells_what_someone_is_doing_or_why_not() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "hector")
	var doing: Label = ctx.hud.inspect_refs.doing
	p.activity = "Sweeping the hall"
	Kit.update(ctx)
	eq(doing.text, "Sweeping the hall", "the activity")
	p.downed = true
	p.activity = "Down and bleeding"
	Kit.update(ctx)
	eq(doing.text, "Down and bleeding", "downed: what the medical module says")
	p.activity = "Collapsed from hunger"
	Kit.update(ctx)
	eq(doing.text, "Collapsed from hunger", "and not always the same words")
	p.activity = ""
	Kit.update(ctx)
	eq(doing.text, "Down and bleeding", "with nothing said, the plain words")
	p.stabilised = true
	p.resting_bed = Vector2(47.0, 56.9)
	p.activity = "Resting in the infirmary"
	Kit.update(ctx)
	eq(doing.text, "Resting in the infirmary", "in a bed")
	p.downed = false
	p.resting_bed = null
	p.activity = "Bandaging Marcus"
	Kit.update(ctx)
	eq(doing.text, "Bandaging Marcus", "a healer at work")
	Kit.free_all(ctx)


func test_the_doing_row_for_the_dead_and_the_away() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "dez")
	var doing: Label = ctx.hud.inspect_refs.doing
	ctx.sim.scavenge.sites = []
	p.away = {"kind": "party", "site": "pharmacy"}
	Kit.update(ctx)
	eq(doing.text, "Away scavenging", "a party member with no site name known")
	ctx.sim.scavenge.sites = [{"id": "pharmacy", "name": "The pharmacy", "where": "the pharmacy"}]
	Kit.update(ctx)
	eq(doing.text, "Scavenging at the pharmacy", "with the site's name")
	p.away = null
	p.dead = true
	Kit.update(ctx)
	eq(doing.text, "Dead", "dead")
	p.turned = true
	Kit.update(ctx)
	eq(doing.text, "Turned into one of the dead", "turned")
	p.turned = false
	p.away = {"kind": "exile"}
	Kit.update(ctx)
	eq(doing.text, "Left through the gate", "sent out")
	Kit.free_all(ctx)


func test_reloading_and_shooting_still_show() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "ruth")
	var doing: Label = ctx.hud.inspect_refs.doing
	p.reloading = 1.0
	Kit.update(ctx)
	eq(doing.text, "Reloading", "reloading")
	p.reloading = 0.0
	p.target = ctx.sim.zombies[0]
	Kit.update(ctx)
	eq(doing.text, "Shooting at a walker", "shooting")
	Kit.free_all(ctx)


func test_the_skills_list_shows_only_what_matters_in_version_one() -> void:
	var ctx := Kit.build()
	_open(ctx, "ana")
	var all := Kit.texts(ctx.hud.inspect)
	for name in ["Shooting", "Building", "Medicine"]:
		check(all.has(name), "%s is listed" % name)
	for name in ["Melee", "Leading"]:
		check(not all.has(name), "%s is hidden" % name)
	for name in ["NEEDS", "WOUNDS", "INFECTION"]:
		check(all.has(name), "%s has a row" % name)
	Kit.free_all(ctx)


func test_a_wall_and_a_walker_keep_their_panels() -> void:
	var ctx := Kit.build()
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
	Kit.update(ctx)
	check(Kit.texts(ctx.hud.inspect).has("INTEGRITY"), "a wall piece")
	check(not ctx.hud.inspect_refs.has("needs"), "without person rows")
	ctx.hud.select({"kind": "zombie", "ref": ctx.sim.zombies[0]})
	Kit.update(ctx)
	check(Kit.texts(ctx.hud.inspect).has("Walker"), "a walker")
	Kit.free_all(ctx)


func test_the_dead_have_no_needs_or_wounds() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "walt")
	p.hunger_h = 40.0
	p.wounds = 2
	p.bleeding = 4.0
	p.dead = true
	Kit.update(ctx)
	eq(ctx.hud.inspect_refs.needs.text, "–", "nothing about needs")
	eq(ctx.hud.inspect_refs.wounds.text, "–", "or wounds")
	Kit.free_all(ctx)
