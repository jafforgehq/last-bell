extends "res://tests/case.gd"
## Three places the view has to follow what the storyteller does to the rules: the fields-of-fire
## view and the selected gun's ring show the reach the guns really have in fog, the Treat tooltip
## says a fever costs one medicine (a cure costs two), and a card of the radio gets the radio's icon.

const Kit := preload("res://tests/hud_kit.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")
const Hud := preload("res://scripts/ui/hud.gd")


func test_the_fields_view_draws_the_reach_the_guns_have_in_fog() -> void:
	var ctx := Kit.build()
	var sim = ctx.sim
	sim.storyteller.enabled = true
	sim.minutes = 22.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	var o := OverlayNode.new()
	sim.weather = "clear"
	var clear: Array = o.fields_plan(sim).reach
	sim.weather = "fog"
	var fog: Array = o.fields_plan(sim).reach
	check(not clear.is_empty() and clear.size() == fog.size(), "every gun that can shoot has a ring")
	var shrunk := 0
	for i in clear.size():
		var who = Kit.person(ctx, String(clear[i].id))
		if who.gun.get("melee", false):
			near(float(fog[i].r), float(clear[i].r), 0.001, "%s's pike reaches as far in fog as it did" % fog[i].id)
			continue
		shrunk += 1
		near(float(fog[i].r), float(clear[i].r) * sim.storyteller.FOG_REACH, 0.001, "%s's ring shrinks to %d%% in fog" % [fog[i].id, roundi(sim.storyteller.FOG_REACH * 100.0)])
	check(shrunk >= 3, "most of the crew has a gun that fog shortens")
	o.free()
	Kit.free_all(ctx)


func test_treat_says_a_fever_costs_one_medicine() -> void:
	var ctx := Kit.build()
	var sim = ctx.sim
	sim.storyteller.enabled = true
	Kit.update(ctx)
	var p = Kit.person(ctx, "ruth")
	sim.storyteller.sick[String(p.id)] = sim.clock_min + 600.0
	eq(ctx.hud._meds_needed(p), float(sim.storyteller.SICK_MEDS), "a fever takes what the card says")
	p.infected_at = sim.clock_min + 600.0
	eq(ctx.hud._meds_needed(p), float(sim.medical.CURE_MEDS), "an infection takes the cure's")
	Kit.free_all(ctx)


func test_the_radios_alerts_wear_its_icon() -> void:
	var found := {}
	for pair in Hud.ALERT_ICONS:
		found[pair[0]] = pair[1]
	eq(found.get("story"), "radio", "a card waiting")
	eq(found.get("story-"), "radio", "what came of one")
	check(Hud.EXTRA_ICONS.has("radio"), "and the HUD loads the icon")
