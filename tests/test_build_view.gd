extends "res://tests/case.gd"
## The yard's view of the buildings (round 6): what the buildings shut when they stand (never a lane, never another home's
## work spot), the art each building is drawn from, and the node that draws the plots, the sites and the buildings
## (scripts/render/build_node.gd). Where the homes lie (on free ground, never on the court, the garden, the playground, the
## apron, a door's approach, a ladder's landing, the workbench's set, a prop, another home) is guarded by
## tests/test_build_homes.gd since round 15, which lists everything a home must avoid; round 11 had the guard here and it
## listed too few things (a lot on the basketball court passed it, and so did one in the middle of the playground).

const Helpers := preload("res://tests/helpers.gd")
const Build := preload("res://scripts/sim/build.gd")
const BuildNode := preload("res://scripts/render/build_node.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const MenuFakes := preload("res://tests/menu_fakes.gd")

## The ground the buildings must leave open, in tiles (see the map: world.gd's `_apply_deck_barriers` shuts the rows and
## columns in front of the walkways). The gate's lane, where the dead come in and the crew and the vehicles go out: the motor
## pool's apron (x 35.2 to 42.8, y 19.8 to 32) with a margin.
const GATE_LANE := Rect2(35.0, 19.6, 8.0, 12.6)
## The people at a site stand at the work spot and a step either side (build.gd's STAND_OFFSETS).
const STANDS := [Vector2(0.0, 0.0), Vector2(1.1, 0.0), Vector2(-1.1, 0.0)]


# --------------------------------------------------------------- the checks --

func _game(seed_value: int = 71) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	return g


## The lot of a plot as a rectangle, in tiles.
func _lot(pl: Dictionary) -> Rect2:
	var size := Vector2(pl.size)
	return Rect2(Vector2(pl.pos) - size / 2.0, size)


## Whether a point is inside a map object's rectangle (the object's own turn undone).
func _in_object(o: Dictionary, p: Vector2) -> bool:
	var c := cos(-float(o.a))
	var s := sin(-float(o.a))
	var dx := p.x - float(o.cx)
	var dy := p.y - float(o.cy)
	var lx := dx * c - dy * s
	var ly := dx * s + dy * c
	return absf(lx) <= float(o.w) / 2.0 and absf(ly) <= float(o.h) / 2.0


## The ground each ladder needs in front of it: where people step off it (the north ladders hang down the wall's face,
## the side ones lean out into the yard).
func _landing(o: Dictionary) -> Rect2:
	var cx := float(o.cx)
	var cy := float(o.cy)
	if absf(sin(float(o.a))) < 0.5:
		return Rect2(cx - 0.9, cy + 0.6, 1.8, 1.6)
	if cx < 42.0:
		return Rect2(cx + 0.25, cy - 0.5, 1.9, 1.0)
	return Rect2(cx - 2.15, cy - 0.5, 1.9, 1.0)


## The ground the school doors need in front of them (the apron the crew crosses to go in and out).
func _apron(o: Dictionary) -> Rect2:
	return Rect2(float(o.cx) - float(o.w) / 2.0 - 0.3, float(o.cy) - 4.0, float(o.w) + 0.6, 4.0)


## Whether any of the tiles whose middle is inside `r` is shut for people on the map as it was built.
func _shut_tiles_in(g: Dictionary, r: Rect2) -> Array:
	var out: Array = []
	var w: int = g.world.W
	for ty in range(floori(r.position.y), ceili(r.end.y)):
		for tx in range(floori(r.position.x), ceili(r.end.x)):
			var mid := Vector2(float(tx) + 0.5, float(ty) + 0.5)
			if r.has_point(mid) and g.world.solid_p[ty * w + tx] != 0:
				out.append(Vector2i(tx, ty))
	return out


func world_shut(g: Dictionary, at: Vector2) -> bool:
	return g.world.is_solid(g.world.solid_p, at.x, at.y)


## Whether the people's path grid has a way from just inside the gate to this point.
func _reaches_gate(g: Dictionary, to: Vector2) -> bool:
	var from := Vector2i(39, 22)
	var tile := Vector2i(floori(to.x), floori(to.y))
	if world_shut(g, to) or g.sim.path_p.grid.is_point_solid(tile):
		return false
	return not g.sim.path_p.grid.get_id_path(from, tile).is_empty()


# -------------------------------------------------------------------- the plots --

func test_the_homes_are_guarded_by_the_homes_test() -> void:
	var g := _game()
	eq(g.sim.build.plots().size(), 9, "nine homes: the guard of where they lie is tests/test_build_homes.gd")
	g.world.free()


# ------------------------------------------------------------------- footprints --

## Stands a building on a plot at once, as if the crew had finished it (its footprint shut).
func _finish_on(sim, plot_id: String, building_id: String) -> void:
	sim.stock.scrap = 1000.0
	check(sim.build.order(plot_id, building_id), "%s is ordered on %s: %s" % [building_id, plot_id, sim.build.why_not(plot_id, building_id)])
	sim.build._finish(sim.build.plot(plot_id))


## Puts a building on a plot whatever the catalogue's limits say (to see the worst the footprints can do together).
func _stand(sim, plot_id: String, building_id: String) -> void:
	var pl: Dictionary = sim.build.plot(plot_id)
	pl.building = building_id
	sim.build._block(pl)


## What the standing buildings of this game get wrong, as sentences: a footprint outside its lot or on a place where a
## crew stands, a work spot that can no longer be walked to from the gate, a lane that is shut. `base` is the walking
## grid of the map as it was built.
func _footprint_problems(g: Dictionary, base: PackedByteArray) -> Array:
	var out: Array = []
	var sim = g.sim
	var w: int = g.world.W
	var stands := {}
	for pl in sim.build.plots():
		for off in STANDS:
			var spot: Vector2 = Vector2(pl.work) + off
			stands[Vector2i(floori(spot.x), floori(spot.y))] = String(pl.id)
	for pl in sim.build.plots():
		if pl.building == "":
			continue
		var lot := _lot(pl)
		var tiles: Array = sim.build.footprint_tiles(String(pl.id))
		for i in tiles:
			var tile := Vector2i(int(i) % w, int(i) / w)
			if not lot.has_point(Vector2(tile) + Vector2(0.5, 0.5)):
				out.append("%s: the %s shuts %s, which is outside the lot" % [String(pl.id), String(pl.building), str(tile)])
			if stands.has(tile):
				out.append("%s: the %s shuts %s, where the crew of %s stands" % [String(pl.id), String(pl.building), str(tile), String(stands[tile])])
	for pl in sim.build.plots():
		for off in STANDS:
			var spot: Vector2 = Vector2(pl.work) + off
			if not _reaches_gate(g, spot):
				out.append("%s: nobody can walk from the gate to %s" % [String(pl.id), str(spot)])
	for ty in range(floori(GATE_LANE.position.y), ceili(GATE_LANE.end.y)):
		for tx in range(floori(GATE_LANE.position.x), ceili(GATE_LANE.end.x)):
			if g.world.solid_p[ty * w + tx] != base[ty * w + tx]:
				out.append("the gate's lane is shut at (%d, %d)" % [tx, ty])
	for o in g.data.objects:
		if String(o.kind) == "door":
			var apron := _apron(o)
			for ty in range(floori(apron.position.y), ceili(apron.end.y)):
				for tx in range(floori(apron.position.x), ceili(apron.end.x)):
					if g.world.solid_p[ty * w + tx] != base[ty * w + tx]:
						out.append("the school door's apron is shut at (%d, %d)" % [tx, ty])
	return out


func test_every_building_on_each_of_its_homes_leaves_the_crews_places_and_the_lanes_open() -> void:
	var g := _game()
	var sim = g.sim
	var base: PackedByteArray = g.world.solid_p.duplicate()
	var stood := 0
	for b in sim.build.catalogue():
		for pl in sim.build.homes_of(String(b.id)):
			_stand(sim, String(pl.id), String(b.id))
			stood += 1
			var problems := _footprint_problems(g, base)
			eq(problems, [], "%s on %s: %s" % [String(b.id), String(pl.id), "; ".join(problems)])
			check(sim.build.demolish(String(pl.id)), "and it comes down again")
			eq(g.world.solid_p, base, "%s on %s: the ground is as it was after it comes down" % [String(b.id), String(pl.id)])
	eq(stood, 9, "every home was tried")
	g.world.free()


func test_with_every_home_built_over_the_crews_places_and_the_lanes_are_still_open() -> void:
	var g := _game()
	var sim = g.sim
	var base: PackedByteArray = g.world.solid_p.duplicate()
	var area := 0.0
	var art: Dictionary = _art_file().buildings
	for pl in sim.build.plots():
		_stand(sim, String(pl.id), String(pl.home))
		var rect: Array = art.get(String(pl.home), {}).get("solid", [])
		if rect.size() == 4:
			area += (float(rect[2]) - float(rect[0])) * (float(rect[3]) - float(rect[1]))
	var problems := _footprint_problems(g, base)
	eq(problems, [], "all of them standing: %s" % "; ".join(problems))
	var shut := 0
	for i in base.size():
		shut += 1 if g.world.solid_p[i] != base[i] else 0
	eq(shut, roundi(area), "the footprints add up (%d tiles) and no tile is shared" % roundi(area))
	g.world.free()


func test_the_builders_walk_to_every_home_even_with_every_other_one_built_over() -> void:
	var worst := 0.0
	var probe := _game()
	var targets: Array = []
	for pl in probe.sim.build.plots():
		targets.append(String(pl.id))
	probe.world.free()
	for target in targets:
		var g := _game()
		var sim = g.sim
		sim.minutes = 8.0 * 60.0
		sim.phase = sim.phase_at(sim.minutes)
		sim.bell_rung = false
		sim.stock.scrap = 200.0
		Helpers.idle_stores(sim)
		for pl in sim.build.plots():
			if String(pl.id) != target:
				_stand(sim, String(pl.id), String(pl.home))
		var building := String(sim.build.plot(target).home)
		check(sim.build.order(target, building), "%s is ordered on %s: %s" % [building, target, sim.build.why_not(target, building)])
		var seconds := 0
		while sim.build.progress_of(target) <= 0.0 and seconds < 90:
			Helpers.run(sim, 1.0)
			seconds += 1
		check(sim.build.progress_of(target) > 0.0, "%s: the builders got there and began (%d seconds)" % [target, seconds])
		worst = maxf(worst, float(seconds))
		var walt = null
		for p in sim.people:
			if p.first == "Walt":
				walt = p
		check(walt != null and Vector2(walt.x, walt.y).distance_to(Vector2(sim.build.plot(target).work)) < 2.5, "%s: Walt is at the site" % target)
		g.world.free()
	check(worst < 80.0, "the farthest home took %d seconds to reach" % int(worst))


func test_a_footprint_that_shuts_a_work_spot_or_walls_one_in_is_found() -> void:
	# a workshop whose footprint takes the front row, where the crew stands
	var path := "user://test_building_art_view.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"buildings": {"workshop": {"solid": [-1.5, -1.5, 1.5, 1.5], "props": []}}}')
	f.close()
	Build.art_path = path
	var g := _game()
	var sim = g.sim
	var base: PackedByteArray = g.world.solid_p.duplicate()
	var first := "workshop_home"
	_finish_on(sim, first, "workshop")
	var text := "; ".join(_footprint_problems(g, base))
	check(text.contains("where the crew of %s stands" % first), "a footprint on the work spot is found: %s" % text)
	check(text.contains("nobody can walk from the gate to"), "and the work spot that can no longer be reached: %s" % text)
	g.world.free()
	Build.art_path = Build.ART_PATH
	# a ring of shut tiles round another plot's work spot
	var h := _game()
	var spot: Vector2 = h.sim.build.plot("salvage_bench_home").work
	var ring: Array = []
	for dy in range(-2, 3):
		for dx in range(-3, 4):
			if absi(dx) == 3 or absi(dy) == 2:
				ring.append((floori(spot.y) + dy) * h.world.W + floori(spot.x) + dx)
	var before := _reaches_gate(h, spot)
	h.sim.block_tiles(ring, true)
	check(before and not _reaches_gate(h, spot), "a ring of shut tiles cuts a work spot off and the check sees it")
	h.world.free()


func test_each_footprint_is_whole_tiles_in_the_back_two_rows() -> void:
	var g := _game()
	var sim = g.sim
	for b in sim.build.catalogue():
		var rect = _art_file().buildings.get(String(b.id), {}).get("solid", [])
		for pl in sim.build.homes_of(String(b.id)):
			_stand(sim, String(pl.id), String(b.id))
			var tiles: Array = sim.build.footprint_tiles(String(pl.id))
			if rect is Array and rect.size() == 4:
				var area := (float(rect[2]) - float(rect[0])) * (float(rect[3]) - float(rect[1]))
				eq(tiles.size(), roundi(area), "%s on %s: the footprint is whole tiles (%.1f tiles of ground, %d shut)" % [String(b.id), String(pl.id), area, tiles.size()])
				check(float(rect[3]) <= 0.5 + 1.0e-9, "%s keeps the front row open" % String(b.id))
			else:
				eq(tiles.size(), 0, "%s has no footprint" % String(b.id))
			sim.build.demolish(String(pl.id))
	g.world.free()


# -------------------------------------------------------------------------- the art --

func _art_file() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/building_art.json"))
	return raw if raw is Dictionary else {}


func _picture_problems(props: Array, what: String) -> Array:
	var out: Array = []
	for pr in props:
		for key in ["f", "x", "y", "w", "h"]:
			if not pr.has(key):
				out.append("%s: a prop has no %s" % [what, key])
		if not pr.has("f") or not pr.has("w") or not pr.has("h"):
			continue
		for file in [String(pr.f), String(pr.get("e", pr.f))]:
			if not ResourceLoader.exists("res://assets/objects/%s.png" % file):
				out.append("%s: there is no picture %s" % [what, file])
		if float(pr.w) <= 0.0 or float(pr.h) <= 0.0:
			out.append("%s: %s has no size" % [what, String(pr.f)])
		var feet := float(pr.get("sort", float(pr.get("y", 0.0)) - float(pr.get("foot", 0.0))))
		var top := float(pr.get("y", 0.0)) - float(pr.get("h", 0.0))
		if absf(float(pr.get("x", 0.0))) + float(pr.get("w", 0.0)) / 2.0 > 2.0:
			out.append("%s: %s reaches out of its lot sideways" % [what, String(pr.f)])
		if feet > 0.95:
			out.append("%s: %s stands in the front row, where the crew is (feet at %.2f)" % [what, String(pr.f), feet])
		if top < -5.0:
			out.append("%s: %s rises more than five tiles above the plot" % [what, String(pr.f)])
	return out


func test_every_building_has_its_art_and_every_picture_in_it_exists() -> void:
	var g := _game()
	var art: Dictionary = _art_file()
	check(art.has("scaffold") and art.scaffold.size() >= 2, "a scaffold of a few stages")
	var last := 0.0
	for stage in art.get("scaffold", []):
		check(float(stage.upto) > last, "the stages go on: %s" % str(stage.upto))
		last = float(stage.upto)
		eq(_picture_problems(stage.props, "scaffold"), [], "the scaffold's pictures")
	check(last > 1.0, "the last stage takes the site to the end")
	for b in g.sim.build.catalogue():
		var a: Dictionary = art.get("buildings", {}).get(String(b.id), {})
		check(not a.is_empty() and a.get("props", []).size() >= 2, "%s has art of a few props" % String(b.id))
		eq(_picture_problems(a.get("props", []), String(b.id)), [], "%s: its pictures" % String(b.id))
	g.world.free()


func test_the_bunk_house_has_four_beds_on_open_ground_inside_its_lot() -> void:
	var g := _game()
	var sim = g.sim
	for pl in sim.build.homes_of("bunk_house"):
		_stand(sim, String(pl.id), "bunk_house")
		var beds: Array = sim.build.bed_spots()
		eq(beds.size(), 4, "four beds on %s" % String(pl.id))
		var lot := _lot(pl)
		var tiles: Array = sim.build.footprint_tiles(String(pl.id))
		for i in beds.size():
			var at: Vector2 = beds[i]
			check(lot.has_point(at), "%s: bed %d is in the lot" % [String(pl.id), i])
			check(not world_shut(g, at), "%s: bed %d is on open ground" % [String(pl.id), i])
			check(not tiles.has(floori(at.y) * g.world.W + floori(at.x)), "%s: bed %d is not in a footprint" % [String(pl.id), i])
			for j in i:
				check(at.distance_to(beds[j]) >= 0.7, "%s: beds %d and %d are a body's width apart" % [String(pl.id), i, j])
		sim.build.demolish(String(pl.id))
	g.world.free()


func test_the_floodlights_carry_their_lamps_and_nothing_else_does() -> void:
	var art: Dictionary = _art_file().buildings
	var lamps: Array = art.floodlights.get("lights", [])
	check(lamps.size() >= 2, "two lamps or more on the floodlights")
	for l in lamps:
		check(float(l.r) >= 5.0 and float(l.energy) > 0.0 and absf(float(l.x)) <= 2.0 and float(l.y) >= -4.5 and float(l.y) <= 0.5, "a lamp that lights the yard from about where its post stands: %s" % str(l))
	for id in art:
		if id != "floodlights":
			check(not art[id].has("lights"), "%s has no lamps" % id)


# ------------------------------------------------------------------------ the node --

## What the node asks the game about (main.gd has all of these).
class FakeMain:
	extends Node
	var build_open := false
	var build_hover := {}
	var title_mode := false
	var tutorial := false
	var coach = null


## What the node asks the lighting module about.
class FakeLighting:
	extends Node2D
	var dark := 0.0
	var fog := 0.0


## A stand-in for a canvas item that only counts what it is asked to draw.
class Pen:
	extends RefCounted
	var rects := 0
	var circles := 0
	var arcs := 0
	var lines := 0
	var pictures := 0

	func draw_rect(_rect, _color, _filled = true, _width = -1.0) -> void:
		rects += 1

	func draw_circle(_at, _radius, _color) -> void:
		circles += 1

	func draw_arc(_at, _radius, _from, _to, _points, _color, _width = -1.0, _aa = false) -> void:
		arcs += 1

	func draw_multiline(_points, _color, _width = -1.0, _aa = false) -> void:
		lines += 1

	func draw_texture_rect(_texture, _rect, _tile, _modulate = Color.WHITE) -> void:
		pictures += 1

	func draw_set_transform(_at, _rotation, _scale) -> void:
		pass


## The node on a game, with a stand-in for main.gd and the lighting, and a y-sorted parent for what stands up.
func _node(g: Dictionary) -> Dictionary:
	var fake := FakeMain.new()
	var light := FakeLighting.new()
	var tall := Node2D.new()
	tall.y_sort_enabled = true
	g.world.add_child(fake)
	g.world.add_child(light)
	g.world.add_child(tall)
	var n := BuildNode.new()
	g.world.add_child(n)
	n.setup(fake, g.sim, tall, light)
	return {"node": n, "main": fake, "light": light, "tall": tall}


func test_the_node_makes_its_sprites_once_and_again_only_when_a_plot_changes() -> void:
	var g := _game()
	var sim = g.sim
	var h := _node(g)
	var n = h.node
	eq(n.sprite_count(), 0, "nothing built, nothing drawn")
	eq(n.rebuilds, 1, "made once at the start")
	n.update(0.0)
	n.update(0.1)
	eq(n.rebuilds, 1, "and not again while nothing changes")
	sim.stock.scrap = 100.0
	check(sim.build.order("salvage_bench_home", "salvage_bench"), "a site is ordered")
	n.update(0.2)
	eq(n.rebuilds, 2, "a site makes them again")
	var heap: int = n.sprite_count()
	check(heap >= 3, "a heap of planks, a crate and sandbags: %d" % heap)
	check("164_pallets_s3" in n.files(), "the first stage has the planks: %s" % str(n.files()))
	sim.build.plot("salvage_bench_home").site.progress = 1.0
	n.update(0.3)
	eq(n.rebuilds, 2, "work within a stage does not make them again")
	sim.build.plot("salvage_bench_home").site.progress = 7.5
	n.update(0.4)
	eq(n.rebuilds, 3, "a stage further on does")
	sim.build.plot("salvage_bench_home").site.progress = 13.5
	n.update(0.5)
	eq(n.rebuilds, 4, "and the last stage")
	check("058_workbench" in n.files() and "142_scrap" in n.files(), "a site far along shows the bench it will be, faintly: %s" % str(n.files()))
	sim.build._finish(sim.build.plot("salvage_bench_home"))
	n.update(0.6)
	eq(n.rebuilds, 5, "a finished building makes them again")
	check("058_workbench" in n.files() and not ("164_pallets_s3" in n.files()), "the bench stands and the planks are gone: %s" % str(n.files()))
	var standing: int = n.sprite_count()
	check(standing >= 4, "a bench with its heap, crates and tyres: %d" % standing)
	check(sim.build.demolish("salvage_bench_home"), "it comes down")
	n.update(0.7)
	eq(n.sprite_count(), 0, "and nothing of it is left")
	sim.build.order("workshop_home", "workshop")
	n.update(0.8)
	check(n.sprite_count() > 0, "a site again")
	check(sim.build.cancel("workshop_home"), "cancelled")
	n.update(0.9)
	eq(n.sprite_count(), 0, "and the site is gone")
	g.world.free()


func test_what_stands_up_is_among_the_people_and_what_lies_down_is_under_them() -> void:
	var g := _game()
	var sim = g.sim
	var h := _node(g)
	var n = h.node
	_stand(sim, "radio_mast_home", "radio_mast")
	_stand(sim, "bunk_house_home_1", "bunk_house")
	n.update(0.0)
	var standing: Array = []
	for c in h.tall.get_children():
		standing.append(String(c.texture.resource_path).get_file().get_basename())
	check("392_mast" in standing and "143_tent" in standing, "the mast and the tents are among the people: %s" % str(standing))
	check(not ("082_cot" in standing), "the cots are not: %s" % str(standing))
	var mast: Sprite2D = null
	for c in h.tall.get_children():
		if String(c.texture.resource_path).get_file().get_basename() == "392_mast":
			mast = c
	var at: Vector2 = Vector2(sim.build.plot("radio_mast_home").pos)
	near(mast.position.y / 64.0, at.y + 0.2, 1.0e-3, "its feet, which the people are sorted by, are on the ground at the foot of the mast")
	near(mast.position.x / 64.0, at.x + 0.38, 1.0e-3, "and it stands on the plot")
	var flat := 0
	for c in n._flat.get_children():
		flat += 1
	eq(flat, 4, "the four cots lie on the ground")
	g.world.free()


func test_the_node_follows_a_load_and_a_new_run() -> void:
	var a := _game()
	_stand(a.sim, "greenhouse_home", "greenhouse")
	a.sim.build.order("salvage_bench_home", "salvage_bench")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	var b := _game(99)
	var h := _node(b)
	var n = h.node
	eq(n.sprite_count(), 0, "a quiet yard")
	check(SaveGame.apply(b.sim, d), "the save loads over it")
	n.update(0.0)
	check("125_rainbarrel" in n.files() and "164_pallets_s3" in n.files(), "the greenhouse stands and the bench's site is up: %s" % str(n.files()))
	b.sim.start_run(1, 5)
	n.update(0.1)
	eq(n.sprite_count(), 0, "a new run has nothing in the yard")
	a.world.free()
	b.world.free()


## A point of the yard that is nowhere near a plot (tiles): the pointer parked there shows no sign.
const FAR_FROM_PLOTS := Vector2(-40.0, -40.0)


func test_an_empty_plot_shows_no_sign_and_no_outline_until_the_screen_is_open_the_pointer_is_near_or_a_site_is_up() -> void:
	var g := _game()
	var sim = g.sim
	var h := _node(g)
	var n = h.node
	var plots: Array = sim.build.plots()
	var a: Dictionary = sim.build.plot("greenhouse_home")
	var b: Dictionary = sim.build.plot("salvage_bench_home")
	var c: Dictionary = sim.build.plot("workshop_home")
	n.pointer = FAR_FROM_PLOTS
	var pen := Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_outlines, 0, "the yard in plain play has no outline on it")
	eq(n.drawn_signs, 0, "and no sign")
	eq(pen.lines, 0, "not one dashed line")
	eq(n.near_plot(), "", "(nobody is near a plot)")
	near(n.outline_alpha(a), 0.0, 1.0e-9, "an empty plot's outline is none")
	near(n.sign_alpha(a), 0.0, 1.0e-9, "and its sign")
	# the pointer in a lot: that plot, and only that one, has its outline and its sign
	n.pointer = Vector2(a.pos)
	eq(n.near_plot(), String(a.id), "the plot under the pointer is the near one")
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_outlines, 1, "it has its outline")
	eq(n.drawn_signs, 1, "and its sign")
	near(n.outline_alpha(a), BuildNode.ALPHA_NEAR, 1.0e-9, "at the strength of a plot the pointer is near")
	near(n.sign_alpha(a), BuildNode.SIGN_NEAR, 1.0e-9, "and its sign")
	near(n.outline_alpha(b), 0.0, 1.0e-9, "the others have none")
	# near means within NEAR_PLOT tiles of the lot's edge, the nearest plot only
	var half := Vector2(a.size) / 2.0
	near(n.gap(a, Vector2(a.pos) + Vector2(half.x + 2.0, 0.0)), 2.0, 1.0e-6, "the gap is measured from the lot's edge")
	near(n.gap(a, Vector2(a.pos) + Vector2(half.x * 0.5, half.y * 0.5)), 0.0, 1.0e-9, "and is nothing inside it")
	n.pointer = Vector2(a.pos) + Vector2(half.x + BuildNode.NEAR_PLOT + 0.5, 0.0)
	check(n.near_plot() != String(a.id), "more than NEAR_PLOT tiles from its edge it is not near")
	n.pointer = Vector2(a.pos) + Vector2(half.x + BuildNode.NEAR_PLOT - 0.3, 0.0)
	var nearest: String = n.near_plot()
	check(nearest == String(a.id) or sim.build.plot(nearest).has("pos"), "(a plot within NEAR_PLOT is found: %s)" % nearest)
	n.pointer = Vector2(a.pos)
	# a site keeps its outline and its sign wherever the pointer is
	sim.stock.scrap = 100.0
	check(sim.build.order(String(b.id), "salvage_bench"), "(a site is ordered on %s)" % String(b.id))
	n.pointer = FAR_FROM_PLOTS
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_outlines, 1, "a plot with a site keeps its outline")
	eq(n.drawn_signs, 1, "and its sign (a click on it opens the screen)")
	near(n.outline_alpha(b), BuildNode.ALPHA_SITE, 1.0e-9, "as faint as before")
	var air := Pen.new()
	n._paint_air(air)
	eq(n.drawn_bars, 1, "and its bar over it")
	# a building has none of its own, near or not
	_stand(sim, String(c.id), "workshop")
	n.pointer = Vector2(c.pos)
	n._paint_ground(pen)
	near(n.outline_alpha(c), 0.0, 1.0e-9, "a building's outline is none, with the pointer on it too")
	near(n.sign_alpha(c), 0.0, 1.0e-9, "and its sign")
	n.pointer = FAR_FROM_PLOTS
	# the Build screen open: every plot is outlined and signed, a building's too
	h.main.build_open = true
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_outlines, plots.size(), "with the Build screen open every plot is outlined")
	eq(n.drawn_signs, plots.size(), "and signed")
	near(n.outline_alpha(c), BuildNode.ALPHA_OPEN, 1.0e-9, "brighter, a building's too")
	h.main.build_hover = {"plot": String(a.id)}
	near(n.outline_alpha(a), BuildNode.ALPHA_HOVER, 1.0e-9, "and the one it points at brightest")
	near(n.sign_alpha(a), 1.0, 1.0e-9, "with its sign")
	h.main.build_open = false
	h.main.build_hover = {}
	# the --build-plots flag keeps them all lit, as the screen does
	n.show_plots = true
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_outlines, plots.size(), "the flag lights every plot with the screen shut")
	near(n.outline_alpha(c), BuildNode.ALPHA_OPEN, 1.0e-9, "as the screen does")
	n.show_plots = false
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_outlines, 1, "and without it, back to the site's")
	h.main.title_mode = true
	n._paint_ground(pen)
	eq(n.drawn_outlines, 0, "nothing on the title's yard")
	h.main.title_mode = false
	h.main.tutorial = true
	h.main.coach = Node.new()
	n._paint_ground(pen)
	eq(n.drawn_outlines + n.drawn_signs, 0, "nor in Orientation Day's lesson")
	h.main.coach.free()
	g.world.free()


func test_the_pointer_is_read_from_the_window_unless_a_test_or_a_screenshot_puts_it_somewhere() -> void:
	var g := _game()
	var h := _node(g)
	var n = h.node
	n.pointer = Vector2(12.0, 7.5)
	eq(n.pointer_tile(), Vector2(12.0, 7.5), "the pointer that was put is the pointer")
	n.pointer = null
	check(n.pointer_tile().is_finite(), "else it is where the window has the mouse: %s" % str(n.pointer_tile()))
	g.world.free()


func test_a_site_has_a_bar_that_fills_with_the_work_and_waits_at_night() -> void:
	var g := _game()
	var sim = g.sim
	var h := _node(g)
	var n = h.node
	var pen := Pen.new()
	n._paint_air(pen)
	eq(n.drawn_bars, 0, "no site, no bar")
	sim.stock.scrap = 100.0
	sim.build.order("salvage_bench_home", "salvage_bench")
	sim.build.order("workshop_home", "workshop")
	n._paint_air(pen)
	eq(n.drawn_bars, 2, "a bar for each site")
	var rects := pen.rects
	sim.build.plot("salvage_bench_home").site.progress = 7.0
	pen.rects = 0
	n._paint_air(pen)
	check(pen.rects > 0, "and a fill for the one with work done")
	check(n._day(), "it is day")
	sim.minutes = 22.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = true
	check(not n._day(), "and at night the crew holds the posts: the bar waits")
	g.world.free()


func test_the_floodlights_burn_while_they_stand_and_it_is_dark_blackout_or_not() -> void:
	var g := _game()
	var sim = g.sim
	var h := _node(g)
	var n = h.node
	eq(n.lamp_count(), 0, "no floodlights, no lamps")
	_stand(sim, "floodlights_home", "floodlights")
	n.update(0.0)
	eq(n.lamp_count(), 2, "two lamps")
	var lamps: Array = []
	for c in n.get_children():
		if c is PointLight2D:
			lamps.append(c)
	eq(lamps.size(), 2, "as light nodes")
	for l in lamps:
		check(not l.visible and l.energy < 0.01, "by day they are off")
	h.light.dark = 0.67
	n.update(0.1)
	for l in lamps:
		check(l.visible and l.energy > 0.85, "at night they burn: %.2f" % l.energy)
		var home: Vector2 = Vector2(sim.build.plot("floodlights_home").pos) * 64.0
		check(l.position.distance_to(home) < 5.0 * 64.0, "from the plot")
	h.light.dark = 0.2
	n.update(0.2)
	for l in lamps:
		check(l.visible and l.energy > 0.2 and l.energy < 0.85, "at dusk they are rising: %.2f" % l.energy)
	h.light.dark = 0.67
	h.light.fog = 1.0
	n.update(0.3)
	for l in lamps:
		check(l.energy < 0.8, "a fog dims them: %.2f" % l.energy)
	h.light.fog = 0.0
	check(sim.build.demolish("floodlights_home"), "the floodlights come down")
	n.update(0.4)
	eq(n.lamp_count(), 0, "and the lamps with them")
	g.world.free()


func test_the_lamps_have_a_glow_at_night_and_none_by_day_or_without_the_lights() -> void:
	var g := _game()
	var sim = g.sim
	var h := _node(g)
	var n = h.node
	var pen := Pen.new()
	_stand(sim, "floodlights_home", "floodlights")
	n.update(0.0)
	n._paint_glow(pen)
	eq(pen.pictures, 0, "no glow by day")
	h.light.dark = 0.67
	n.update(0.1)
	n._paint_glow(pen)
	eq(pen.pictures, 2, "a glow on each lamp at night")
	h.light.visible = false
	n.update(0.2)
	pen.pictures = 0
	n._paint_glow(pen)
	eq(pen.pictures, 0, "and none, nor any lamp, when the lights are switched off (--nolights)")
	for c in n.get_children():
		if c is PointLight2D:
			check(not c.visible, "the lamp is off")
	g.world.free()


# ---------------------------------------------------------- main.gd and its sounds --

func test_the_game_has_the_node_and_a_finished_building_makes_a_noise_and_some_dust() -> void:
	var g := MenuFakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	check(main.build_view != null and main.build_view.sim == main.sim, "main has the node, on its rules")
	check(main.build_view.get_parent() == main.world, "in the world's space")
	check(main.build_view._tall == main.entities, "and tall things are sorted among the people")
	var dust: int = main.fx.parts.size()
	main.sim.events.append({"type": "built", "plot": "salvage_bench_home", "building": "salvage_bench"})
	main._handle_events()
	eq(main.sim.events.size(), 0, "the event is dealt with")
	check(main.fx.parts.size() > dust, "dust where it stands: %d" % (main.fx.parts.size() - dust))
	dust = main.fx.parts.size()
	main.sim.events.append({"type": "demolished", "plot": "salvage_bench_home", "building": "salvage_bench"})
	main._handle_events()
	check(main.fx.parts.size() > dust, "and where it came down")
	main.sim.stock.scrap = 100.0
	main.sim.build.order("salvage_bench_home", "salvage_bench")
	var chips: int = main.fx.parts.size()
	var at: Vector2 = main.sim.build.plot("salvage_bench_home").work
	main.sim.events.append({"type": "hammer", "x": at.x + 0.5, "y": at.y})
	main._handle_events()
	check(main.fx.parts.size() > chips, "wood chips fly where the builders hammer")
	chips = main.fx.parts.size()
	main.sim.events.append({"type": "hammer", "x": 30.0, "y": 19.0})
	main._handle_events()
	eq(main.fx.parts.size(), chips, "and none where someone mends a wall")
	main.sim.events.append({"type": "built", "plot": "nowhere", "building": "nothing"})
	main._handle_events()
	await MenuFakes.leave(g)
