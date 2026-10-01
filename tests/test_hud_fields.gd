extends "res://tests/case.gd"
## The night tools drawn in the world (scripts/render/overlay_node.gd): the fields-of-fire
## view (every wall section tinted by how many guns reach it, each gun's reach, and the arrows
## where the dead come in) and the marker of the alarm. The numbers come from the rules'
## module (here the kit's table-driven one); these tests look at what is drawn from them.

const Kit := preload("res://tests/hud_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")

const NORTH_BUS := 3
const WEST_CONTAINER := 6


## What the overlay reads of main.gd.
class FakeMain:
	extends Node
	var sim
	var zoom_px := 12.0
	var selection = null
	var hover = null
	var order_mark = null
	var clock := 0.0
	var fields := false

	func view_pos(e) -> Vector2:
		return Vector2(e.x, e.y)


## An overlay in the tree over `ctx`'s game, drawing at `zoom` pixels a tile with the whole map
## in the window's corner (so nothing is out of view and every draw call runs).
func _overlay(ctx: Dictionary, zoom: float, fields: bool) -> Dictionary:
	var main := FakeMain.new()
	main.sim = ctx.sim
	main.zoom_px = zoom
	main.fields = fields
	var layer := CanvasLayer.new()
	var overlay := OverlayNode.new()
	overlay.main = main
	layer.add_child(overlay)
	main.add_child(layer)
	Engine.get_main_loop().root.add_child(main)
	overlay.get_viewport().canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * zoom / OverlayNode.TILE)
	return {"main": main, "overlay": overlay}


func _free_overlay(o: Dictionary) -> void:
	o.overlay.get_viewport().canvas_transform = Transform2D.IDENTITY
	o.main.free()


func _draw_once(o: Dictionary) -> void:
	o.overlay.queue_redraw()
	await Kit.settle()


# ------------------------------------------------------------- small helpers --

func test_the_tint_follows_how_many_guns_reach_a_section() -> void:
	eq(OverlayNode.cover_color(0), Color("#e0584a"), "none: red")
	eq(OverlayNode.cover_color(1), Color("#e8953a"), "one: amber")
	eq(OverlayNode.cover_color(2), Color("#8fb85a"), "two: green")
	eq(OverlayNode.cover_color(3), Color("#8fb85a"), "three: green")
	eq(OverlayNode.cover_color(9), Color("#8fb85a"), "and more")


func test_the_tint_is_pale_enough_to_leave_the_wall_art_showing() -> void:
	check(OverlayNode.COVER_FILL >= 0.2 and OverlayNode.COVER_FILL <= 0.3, "a fill of about a quarter: %.2f" % OverlayNode.COVER_FILL)
	check(OverlayNode.COVER_EDGE > OverlayNode.COVER_FILL, "with a firmer edge")
	check(OverlayNode.REACH_FILL <= 0.12 and OverlayNode.REACH_EDGE <= 0.3, "and the guns' reach is faint")


func test_the_numbers_and_words_in_the_world_are_not_under_the_floor() -> void:
	check(OverlayNode.FIELD_PX >= Fonts.MIN_PX, "%d px" % OverlayNode.FIELD_PX)


func test_a_sections_box_is_its_object_turned_with_it() -> void:
	var ctx := Kit.build()
	# the bus on the north wall: 11 by 2.6 tiles about (47.5, 16.7), lying along the wall
	var north := OverlayNode.section_rect(ctx.sim.segments[NORTH_BUS])
	near(north.position.x, 42.0, 0.001, "north bus left")
	near(north.position.y, 15.4, 0.001, "north bus top")
	near(north.size.x, 11.0, 0.001, "as long as it is")
	near(north.size.y, 2.6, 0.001, "and as deep")
	# the green container on the west wall: 12 by 2.44 turned a quarter, so it is tall
	var west := OverlayNode.section_rect(ctx.sim.segments[WEST_CONTAINER])
	near(west.size.x, 2.44, 0.001, "the west container is narrow")
	near(west.size.y, 12.0, 0.001, "and long")
	near(west.get_center().x, 18.78, 0.001, "about the same middle")
	near(west.get_center().y, 24.6, 0.001, "both ways")
	# every section has a box with some size, round the middle of its object
	for s in ctx.sim.segments:
		var r := OverlayNode.section_rect(s)
		check(r.size.x > 0.5 and r.size.y > 0.5, "%s has a box: %s" % [s.name, str(r)])
		near(r.get_center().x, float(s.obj.cx), 0.001, "%s: centred across" % s.name)
		near(r.get_center().y, float(s.obj.cy), 0.001, "%s: and down" % s.name)
	Kit.free_all(ctx)


func test_the_alarm_hangs_out_in_front_of_its_section_where_the_dead_gather() -> void:
	var ctx := Kit.build()
	var north = ctx.sim.segments[NORTH_BUS]
	var at := OverlayNode.alarm_anchor(north)
	near(at.x, 47.5, 0.01, "in line with the middle of the bus")
	check(at.y < 15.1 and at.y > 12.5, "and a step north of its attack places: %s" % str(at))
	var west = ctx.sim.segments[WEST_CONTAINER]
	var at_west := OverlayNode.alarm_anchor(west)
	check(at_west.x < 17.3 and at_west.x > 14.5, "west of the west wall: %s" % str(at_west))
	var east = ctx.sim.segments[12]
	check(OverlayNode.alarm_anchor(east).x > 66.9, "east of the east wall")
	Kit.free_all(ctx)


func test_an_arrow_at_the_map_edge_points_inward() -> void:
	eq(OverlayNode.inward(Vector2(0.5, 9.5), 84.0, 64.0), Vector2(1, 0), "from the west edge: east")
	eq(OverlayNode.inward(Vector2(83.5, 9.5), 84.0, 64.0), Vector2(-1, 0), "from the east edge: west")
	eq(OverlayNode.inward(Vector2(8.5, 0.5), 84.0, 64.0), Vector2(0, 1), "from the north edge: south")
	eq(OverlayNode.inward(Vector2(8.5, 63.5), 84.0, 64.0), Vector2(0, -1), "from the south edge: north")
	eq(OverlayNode.inward(Vector2(83.5, 41.0), 84.0, 64.0), Vector2(-1, 0), "the east gap in the street")


func test_the_alarms_time_is_hours_and_minutes() -> void:
	eq(OverlayNode.time_text(130.0), "2h 10m", "two hours ten")
	eq(OverlayNode.time_text(180.0), "3h 00m", "the whole three hours")
	eq(OverlayNode.time_text(45.0), "45m", "under an hour: minutes")
	eq(OverlayNode.time_text(59.2), "1h 00m", "a part of a minute counts as one")
	eq(OverlayNode.time_text(0.0), "0m", "none left")
	eq(OverlayNode.time_text(-5.0), "0m", "and never less")


# ----------------------------------------------------------------- the plan --

func test_the_plan_tints_every_section_by_the_rules_coverage() -> void:
	var ctx := Kit.build()
	for s in ctx.sim.segments:
		ctx.sim.tactics.cover[s.id] = s.id % 4
	var o := OverlayNode.new()
	var plan: Dictionary = o.fields_plan(ctx.sim)
	eq(plan.sections.size(), ctx.sim.segments.size(), "every section, the school doors too")
	for item in plan.sections:
		eq(item.n, item.id % 4, "section %d says how many guns the rules count" % item.id)
		eq(item.color, OverlayNode.cover_color(item.n), "section %d has its tint" % item.id)
		check(item.rect.size.x > 0.0, "section %d has a box" % item.id)
	o.free()
	Kit.free_all(ctx)


func test_the_plan_marks_a_worn_section_so_its_number_clears_the_damage_bar() -> void:
	var ctx := Kit.build()
	var seg = ctx.sim.segments[NORTH_BUS]
	var o := OverlayNode.new()
	var worn := func() -> bool:
		for item in o.fields_plan(ctx.sim).sections:
			if item.id == NORTH_BUS:
				return item.damaged
		return false
	check(not worn.call(), "a whole section is not damaged")
	seg.hp = seg.max_hp * 0.5
	check(worn.call(), "a worn one is")
	o.free()
	Kit.free_all(ctx)


func test_the_plan_has_a_reach_for_each_gun_that_is_standing_at_its_post() -> void:
	var ctx := Kit.build()
	var o := OverlayNode.new()
	var plan: Dictionary = o.fields_plan(ctx.sim)
	eq(plan.reach.size(), 6, "all six")
	for r in plan.reach:
		var p = Kit.person(ctx, r.id)
		eq(r.at, ctx.sim.tactics.post_pos(p), "%s: at their post" % r.id)
		eq(r.r, float(p.gun.range), "%s: as far as their gun reaches" % r.id)
	# someone who is down, gone or away has no reach
	Kit.person(ctx, "ana").downed = true
	Kit.person(ctx, "walt").dead = true
	Kit.person(ctx, "hector").away = {"kind": "party", "site": "pharmacy"}
	plan = o.fields_plan(ctx.sim)
	var ids: Array = []
	for r in plan.reach:
		ids.append(r.id)
	ids.sort()
	eq(ids, ["dez", "marcus", "ruth"], "the three still on their feet and here")
	# a drafted person's reach is where they were sent
	var ruth = Kit.person(ctx, "ruth")
	ruth.drafted = true
	ruth.order = Vector3(30.0, 25.0, 0.0)
	for r in o.fields_plan(ctx.sim).reach:
		if r.id == "ruth":
			eq(r.at, Vector2(30.0, 25.0), "round the spot they were ordered to")
	o.free()
	Kit.free_all(ctx)


func test_the_plan_has_arrows_only_when_the_lookout_has_spoken() -> void:
	var ctx := Kit.build()
	var o := OverlayNode.new()
	eq(o.fields_plan(ctx.sim).spawns.size(), 0, "nothing told: no arrows")
	ctx.sim.tactics.told = Kit.forecast({"spawns": [Vector2(0.5, 9.5), Vector2(8.5, 0.5)]})
	var spawns: Array = o.fields_plan(ctx.sim).spawns
	eq(spawns.size(), 2, "told: one for each main spawn point")
	eq(spawns[0].at, Vector2(0.5, 9.5), "at the point")
	eq(spawns[0].dir, Vector2(1, 0), "pointing in from the west edge")
	eq(spawns[1].dir, Vector2(0, 1), "and in from the north edge")
	ctx.sim.tactics.told = {"given": false}
	eq(o.fields_plan(ctx.sim).spawns.size(), 0, "and none again when he cannot tell it")
	o.free()
	Kit.free_all(ctx)


# ------------------------------------------------------------- drawing it --

func test_the_view_draws_at_every_coverage_and_with_the_alarm_set() -> void:
	var ctx := Kit.build()
	var sim = ctx.sim
	# a damaged section, someone down, someone away: the odd cases
	sim.segments[NORTH_BUS].hp = sim.segments[NORTH_BUS].max_hp * 0.4
	Kit.person(ctx, "ana").downed = true
	Kit.person(ctx, "hector").away = {"kind": "party", "site": "pharmacy"}
	sim.tactics.told = Kit.forecast({"spawns": [Vector2(0.5, 9.5), Vector2(8.5, 0.5), Vector2(83.5, 41.0), Vector2(8.5, 63.5)]})
	sim.tactics.ringing = 12
	sim.tactics.left_min = 130.0
	# zoomed out (the whole map), at a normal zoom (part of it) and close in
	for zoom in [12.0, 40.0, 84.0]:
		for pattern in ["none", "one", "three", "mixed"]:
			for s in sim.segments:
				sim.tactics.cover[s.id] = {"none": 0, "one": 1, "three": 3, "mixed": s.id % 4}[pattern]
			var o := _overlay(ctx, zoom, true)
			await _draw_once(o)
			if zoom == 12.0:
				eq(o.overlay.drawn_sections, sim.segments.size(), "%s at zoom %d: every section is drawn" % [pattern, zoom])
				eq(o.overlay.drawn_reach, 4, "%s: a reach for each of the four gun still here" % pattern)
				eq(o.overlay.drawn_spawns, 4, "%s: and an arrow for each spawn point" % pattern)
				check(o.overlay.drew_alarm, "%s: and the alarm" % pattern)
			else:
				check(o.overlay.drawn_sections <= sim.segments.size(), "%s at zoom %d: part of the wall is in view" % [pattern, zoom])
			_free_overlay(o)
	Kit.free_all(ctx)


func test_the_view_off_draws_no_tint_but_the_alarm_still_shows() -> void:
	var ctx := Kit.build()
	var sim = ctx.sim
	sim.tactics.told = Kit.forecast()
	var o := _overlay(ctx, 12.0, false)
	await _draw_once(o)
	eq(o.overlay.drawn_sections, 0, "no tint with the view off")
	eq(o.overlay.drawn_reach, 0, "no reach")
	eq(o.overlay.drawn_spawns, 0, "no arrows")
	check(not o.overlay.drew_alarm, "and no alarm while none rings")
	sim.tactics.ringing = NORTH_BUS
	sim.tactics.left_min = 95.0
	await _draw_once(o)
	check(o.overlay.drew_alarm, "the alarm is drawn without the view: it is the world's, not the view's")
	eq(o.overlay.drawn_sections, 0, "still no tint")
	# and it stops with the alarm
	sim.tactics.ringing = -1
	await _draw_once(o)
	check(not o.overlay.drew_alarm, "gone when it stops ringing")
	_free_overlay(o)
	Kit.free_all(ctx)


func test_a_gun_whose_reach_is_off_the_screen_is_not_drawn() -> void:
	var ctx := Kit.build()
	var o := _overlay(ctx, 84.0, true)
	# the whole viewport is a few tiles of the map's top left corner: the guns at their posts are away
	var k := 84.0 / OverlayNode.TILE
	o.overlay.get_viewport().canvas_transform = Transform2D(Vector2(k, 0.0), Vector2(0.0, k), Vector2(-3000.0, -3000.0))
	await _draw_once(o)
	check(o.overlay.drawn_reach < 6, "not every reach: %d drawn" % o.overlay.drawn_reach)
	eq(o.overlay.drawn_spawns, 0, "no arrows: none told")
	_free_overlay(o)
	Kit.free_all(ctx)


func test_the_real_rules_module_gives_the_view_something_sensible() -> void:
	# the kit's table is for the HUD tests: the real module has to give the view numbers it can draw
	var ctx := Kit.build()
	var real = load("res://scripts/sim/tactics.gd").new()
	real.setup(ctx.sim)
	real.start()
	ctx.sim.tactics = real
	var o := OverlayNode.new()
	var plan: Dictionary = o.fields_plan(ctx.sim)
	eq(plan.sections.size(), ctx.sim.segments.size(), "a tint for every section")
	var seen := {}
	for item in plan.sections:
		check(item.n >= 0 and item.n <= 6, "section %d: %d guns" % [item.id, item.n])
		seen[item.n] = true
	check(seen.size() >= 2, "the crew does not cover everything the same: %s" % str(seen.keys()))
	eq(plan.reach.size(), 6, "all six guns have a reach")
	o.free()
	Kit.free_all(ctx)
