extends "res://tests/case.gd"
## Round 26, the demo ("Three Bells": scripts/demo.gd, scripts/sim/demo_run.gd, scripts/ui/demo_end_card.gd, assets/data/demo.json): the first three nights of
## one run, the same every time. A handful of checks of the core: the flag, what a demo run switches off and keeps short, the Big Night of the third day, the end
## of the run and its card, the Map page's two places, and that a game that is not the demo is the full game.
## (The balance of the three nights is `tools/demo_lab.gd`'s, not a test's: it plays them with the harness's bot.)

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Helpers := preload("res://tests/helpers.gd")
const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Demo := preload("res://scripts/demo.gd")
const DemoRun := preload("res://scripts/sim/demo_run.gd")
const DemoEndCard := preload("res://scripts/ui/demo_end_card.gd")
const GameOver := preload("res://scripts/ui/game_over.gd")
const MapPage := preload("res://scripts/ui/map_page.gd")
const RadioPanel := preload("res://scripts/ui/radio_panel.gd")
const RoadEvents := preload("res://scripts/drive/road_events.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const FIXTURE := "user://test_r26d_demo.json"


# --------------------------------------------------------------------- helpers --

## A demo run, as main.gd begins one: a new Sim, the scenario installed, the run started.
func _demo_game() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	DemoRun.begin(sim)
	return {"sim": sim, "world": world, "data": data}


func _ids(list: Array) -> Array:
	var out: Array = []
	for e in list:
		out.append(String(e.id))
	return out


func _free(g: Dictionary) -> void:
	g.world.free()


# ------------------------------------------------------------------------ tests --

func test_the_demo_is_on_by_the_flag_or_the_feature_and_its_data_is_what_the_owner_decided() -> void:
	Demo.force(null)
	check(not Demo.on(), "a test run is not the demo (no --demo, no `demo` feature)")
	Demo.force(true)
	check(Demo.on(), "forced on")
	Demo.force(false)
	check(not Demo.on(), "forced off")
	Demo.force(null)
	var d := Demo.data()
	eq(Demo.nights(), 3, "three nights")
	eq(Demo.big_night_day(), 3, "the third is the Big Night")
	eq(Demo.buildings(), ["salvage_bench", "workshop", "bunk_house", "tents", "floodlights", "watchtower"], "the Build page's short list")
	eq(Demo.places(), ["houses", "pharmacy"], "two places")
	eq(Demo.road_events(), ["ambush", "roadblock", "survivor", "wreck_supplies", "breakdown"], "five kinds of road event")
	eq(Demo.wishlist_url(), "", "no store page yet: the Wishlist button is hidden")
	check(String(d.copy.title).contains("Thirty Bells demo"), "the end card's thanks")
	# a damaged data file is the fallbacks
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	Demo.data_path = FIXTURE
	Demo.forget()
	eq(Demo.places(), ["houses", "pharmacy"], "a damaged file: the fallbacks")
	Demo.data_path = Demo.DATA_PATH
	Demo.forget()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
	# the export preset of the demo carries the feature tag, and the Web preset is as it was
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(cfg.contains("name=\"Web (demo)\"") and cfg.contains("custom_features=\"demo\"") and cfg.contains("build/web-demo/index.html"), "the demo's export preset")
	check(cfg.contains("name=\"Web\"") and cfg.contains("export_path=\"build/web/index.html\""), "the Web preset is left as it was")


func test_a_demo_run_switches_off_what_it_hides_and_keeps_a_short_list() -> void:
	var g := _demo_game()
	var sim = g.sim
	check(sim.is_demo(), "the scenario says so")
	eq(sim.player_id, "ruth", "Ruth is the player")
	eq(sim.people.size(), 5, "a crew of five")
	eq(sim.run_seed, Demo.run_seed(), "the fixed seed")
	for name in ["policies", "problems", "dilemmas", "relations", "specialists"]:
		check(not sim.get(name).enabled and not sim.get(name).active(), "%s is off" % name)
	for name in ["briefing", "priorities", "initiative"]:
		check(sim.get(name).enabled, "%s stays on" % name)
	check(sim.briefing.active() and sim.priorities.active() and sim.initiative.active(), "the briefing, the priorities and the ideas are in play")
	eq(sim.initiative.first_day(), 2, "ideas from the second day")
	check(not sim.lots.on and not sim.streets.enabled, "no lots, no streets of the dead")
	eq(_ids(sim.build.catalogue()), ["salvage_bench", "workshop", "bunk_house", "tents", "floodlights", "watchtower"], "the Build page's six buildings")
	var homes := {}
	for pl in sim.build.plots():
		homes[String(pl.home)] = true
	for home in homes:
		check(Demo.buildings().has(home), "the yard shows no plot for %s, which is not in the demo's short list" % home)
	check(homes.size() >= 5, "the plots of the six buildings are there: %s" % str(homes.keys()))
	eq(_ids(sim.town.places), ["houses", "pharmacy"], "two places on the board")
	eq(_ids(sim.town.known_places()), ["houses", "pharmacy"], "and both known")
	eq(sim.vehicles.fleet.size(), 1, "the pickup is in the motor pool")
	check(sim.vehicles.fuel > 0.0, "and fuelled")
	check(sim.alerts.has("demo_trip"), "the first morning puts the pharmacy's trip")
	eq(sim.scenario.total_days(), 3, "three days")
	# the road has five kinds of event
	var ctx := {"leg": "there", "danger": 2, "hour": 9.0, "road_min": 80.0, "leg_s": 90.0, "by_vehicle": true, "seats_free": 2, "seats": 3, "only": Demo.road_events()}
	var seen := {}
	for sd in 40:
		for e in RoadEvents.plan(sd, ctx):
			seen[String(e.id)] = true
	for id in seen:
		check(Demo.road_events().has(id), "the road's %s is not in the demo's deck" % id)
	check(seen.size() >= 3, "the short deck still brings variety: %s" % str(seen.keys()))
	_free(g)


func test_day_three_is_a_siege_with_a_plated_brute_and_the_first_two_are_gentle() -> void:
	var g := _demo_game()
	var sim = g.sim
	var plans: Array = []
	for day in [1, 2, 3]:
		plans.append(sim.waves.plan_for(day).duplicate(true))
	eq(String(plans[0].kind), "ordinary", "night 1 is ordinary")
	eq(String(plans[1].kind), "ordinary", "night 2 is ordinary")
	eq(String(plans[2].kind), "milestone", "night 3 is a Big Night")
	eq(String(plans[2].id), "siege", "a Siege")
	check(bool(plans[2].big) and bool(plans[2].plated), "big, with plated brutes")
	check(int(plans[2].counts.brute) >= 1 and int(plans[2].counts.brute) <= 2 + 3, "one or two plated brutes (a few more of the budget's own at most): %d" % int(plans[2].counts.brute))
	check(int(plans[0].counts.brute) == 0, "no brute on the first night")
	check(float(plans[2].budget) > 2.0 * float(plans[1].budget), "night 3 is far bigger than night 2: %.1f against %.1f" % [float(plans[2].budget), float(plans[1].budget)])
	check(float(plans[0].budget) < float(plans[1].budget) and float(plans[1].budget) < float(plans[2].budget), "the nights grow")
	var outlook: Dictionary = sim.waves.outlook(3)
	check(bool(outlook.needs_you) and int(outlook.plated) >= 1, "the lookout's forecast asks for the player")
	check(not bool(sim.waves.outlook(2).needs_you), "and does not on the second night")
	# the same every time: a second run of the demo plans the same three nights
	var g2 := _demo_game()
	for day in [1, 2, 3]:
		eq(g2.sim.waves.plan_for(day).queue, plans[day - 1].queue, "night %d is the same queue the next time" % day)
	_free(g)
	_free(g2)


func test_the_run_ends_at_the_dawn_of_day_four_on_the_end_card_and_a_defeat_is_the_ordinary_game_over() -> void:
	var g := _demo_game()
	var sim = g.sim
	sim.storyteller.enabled = false
	Helpers.at(sim, 3, 23.0)
	sim.update(1.0 / 30.0)
	eq(sim.over, "", "three nights are not yet held at night 3")
	Helpers.at(sim, 3, 6.4)
	sim.minutes = 6.5 * 60.0 - 0.05
	sim.phase = "dawn"
	for i in 30:
		sim.update(1.0 / 30.0)
		if sim.over != "":
			break
	eq(sim.day, 4, "the third night is over")
	eq(sim.over, "victory", "the run ends at the dawn of day four")
	var r: Dictionary = sim.scenario.report()
	eq(int(r.nights), 3, "three nights held")
	eq(int(r.alive), 5, "all five alive")
	# the card the HUD puts up
	var ctx := Kit.build(1280, 800, 1, true, 5)
	ctx.sim.scenario = sim.scenario
	ctx.sim.people = sim.people
	ctx.sim.over = "victory"
	ctx.hud._show_game_over(ctx.sim)
	check(ctx.hud.game_over is DemoEndCard, "the demo's three nights end on its own card")
	var card = ctx.hud.game_over
	await Kit.settle()
	var words := Kit.texts(card)
	var said := " | ".join(words)
	check(said.contains("Thanks for playing the Thirty Bells demo"), "the thanks: %s" % said)
	check(said.contains("thirty nights, with a convoy at the last bell"), "the line about the full game: %s" % said)
	eq(String(card.stat_values.nights.text), "3 of 3", "nights held")
	eq(String(card.stat_values.people.text), "5 alive", "people")
	check(card.stat_values.has("kills") and card.stat_values.has("trips") and card.stat_values.has("built"), "the dead put down, trips and buildings")
	check(card.wishlist_button == null, "no Wishlist button while there is no store page")
	check(card.again_button != null and card.title_button != null, "Play again and Quit to title")
	var sent := []
	ctx.hud.restart = func(meta): sent.append(meta)
	card.again_button.pressed.emit()
	eq(sent.size(), 1, "Play again asks for a run")
	check(bool(sent[0].get("demo", false)) and int(sent[0].seed) == Demo.run_seed(), "the same three nights again: %s" % str(sent[0]))
	# a store page brings the button
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"wishlist_url": "https://example.test/thirty-bells"}))
	f.close()
	Demo.data_path = FIXTURE
	Demo.forget()
	var card2 := DemoEndCard.new()
	ctx.holder.add_child(card2)
	card2.setup(ctx.hud, ctx.sim)
	check(card2.wishlist_button != null and card2.wishlist_button.tooltip_text == "https://example.test/thirty-bells", "a store page brings the Wishlist button")
	Demo.data_path = Demo.DATA_PATH
	Demo.forget()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
	Kit.free_all(ctx)
	# a defeat is the report card
	var lost := _demo_game()
	var ctx2 := Kit.build(1280, 800, 1, true, 5)
	ctx2.sim.scenario = lost.sim.scenario
	ctx2.sim.over = "defeat"
	ctx2.hud._show_game_over(ctx2.sim)
	check(ctx2.hud.game_over is GameOver, "a defeat in the demo is the ordinary game over")
	Kit.free_all(ctx2)
	_free(lost)
	_free(g)


func test_the_map_page_offers_the_two_places_alone_and_none_of_the_errands() -> void:
	var g := _demo_game()
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	var holder := Control.new()
	holder.size = Vector2(1280, 900)
	Engine.get_main_loop().root.add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	hud.on_select = func(_s): pass
	hud.on_focus = func(_p): pass
	hud.on_speed = func(_s): pass
	hud.on_gizmo = func(_id): pass
	hud.on_alert = func(_id): pass
	hud.on_sound = func(): pass
	hud.setup(g.data, sim.people)
	hud.update_hud(sim, 1, true, 0)
	var page := MapPage.new()
	holder.add_child(page)
	page.size = Vector2(440, 700)
	page.setup(hud, func(): return sim, {})
	page.refresh(true)
	await Engine.get_main_loop().process_frame
	var ids: Array = page.sites.keys()
	ids.sort()
	eq(ids, ["houses", "pharmacy"], "the Map page offers the houses and the pharmacy and nothing else")
	eq(page.chosen(), "pharmacy", "the first morning's place is already the one chosen")
	check(page.select_place("pharmacy"), "the pharmacy can be chosen")
	page.refresh(true)
	await Engine.get_main_loop().process_frame
	check(page.buttons.go.visible, "Take control is there")
	check(not page.buttons.errand.visible, "Ask to go is not")
	check(not page.segments.loot.get_parent().visible, "the errand switch (Loot, Scout, Clear) is not")
	check(not page.claim_row.visible and not page.buttons.insist.visible, "Claim, Recall and Insist are not")
	# the radio panel has no Jobs tab and the Base page has neither the dials nor the trouble
	var panel := RadioPanel.new()
	hud.add_child(panel)
	panel.setup(hud, func(): return sim)
	panel._sync_tabs()
	check(not panel.tab_button("jobs").visible, "no Jobs tab in the demo")
	check(panel.tab_button("base").visible and panel.tab_button("build").visible and panel.tab_button("map").visible and panel.tab_button("news").visible, "the other four tabs are")
	check(panel.page_available("jobs"), "but the Jobs page can still be had")
	var base = panel.page_node("base")
	check(base != null and not base.sections.policies.visible and not base.sections.trouble.visible, "the Base page has no dials and no trouble")
	check(base.sections.priorities.visible and base.sections.today.visible, "but its briefing and its priorities")
	await Engine.get_main_loop().process_frame    # (the page's deferred centring has run before it is freed)
	await Engine.get_main_loop().process_frame
	holder.free()
	_free(g)


func test_a_demo_save_is_the_demo_again_and_a_game_that_is_not_the_demo_is_the_full_game() -> void:
	var g := _demo_game()
	var saved := SaveGame.to_dict(g.sim)
	check(DemoRun.is_save(saved), "a demo save says so")
	var data := GD.load_all()
	var world2 := World.new()
	Engine.get_main_loop().root.add_child(world2)
	world2.build(data)
	var sim2 := Sim.new(data, world2, FxNull.new())
	DemoRun.install(sim2)
	check(SaveGame.apply(sim2, saved), "a demo save loads onto a demo installed before it is read")
	check(sim2.is_demo() and not sim2.policies.active() and sim2.build.catalogue().size() == 6, "and is the demo")
	world2.free()
	_free(g)
	# the full game, in the same process: nothing of the demo is in it
	var full := Helpers.avatar_game(7, 5)
	var fs = full.sim
	check(not fs.is_demo(), "an ordinary run is not the demo")
	check(fs.waves.big_night(3).is_empty(), "day 3 is no Big Night in the full game")
	check(fs.build.catalogue().size() >= 8, "the full catalogue: %d" % fs.build.catalogue().size())
	check(fs.town.places.size() > 30 and fs.town.known_places().size() >= 4, "and the whole town")
	check(fs.scenario.total_days() == 30, "thirty days")
	check(fs.policies.enabled and fs.problems.enabled and fs.dilemmas.enabled and fs.relations.enabled and fs.specialists.enabled, "every module on")
	check(RoadEvents.deck().size() == 9, "all nine kinds of road event")
	var ctx := {"leg": "there", "danger": 2, "hour": 9.0, "road_min": 80.0, "leg_s": 90.0, "by_vehicle": true, "seats_free": 2, "seats": 3}
	var kinds := {}
	for sd in 80:
		for e in RoadEvents.plan(sd, ctx):
			kinds[String(e.id)] = true
	check(kinds.size() > 5, "the full deck has more than five kinds on the road: %s" % str(kinds.keys()))
	full.world.free()
