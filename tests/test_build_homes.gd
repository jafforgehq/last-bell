extends "res://tests/case.gd"
## Round 15: no more choosing a plot. Every building has its own home (a plot that names the building it is for, with a
## number when the building may stand more than once) and the Build screen is a list of buildings. These tests say the
## homes make sense: each building has the homes its `max` says; each home lies on ground that is free (never the
## basketball court, the garden, the hopscotch and the four-square, the motor pool's apron, the school doors' approach, a
## ladder's landing, the workbench's set, a solid tile, a prop, another home) by the map's own rectangles, and the
## guard is itself tested: each kind of bad spot is put under a home in memory and must be found; each home is
## where its building would be put by someone with a head (the greenhouse touches the garden, the workshop is beside the
## workbench, the salvage bench by the junk, the bunk houses against the school's front wall, the towers on the north wall
## either side of the gate and each reaching at least two night posts); `home_for` gives the first free home and then
## the next; a second home waits for the first; and a save from before has what it had refunded.

const Helpers := preload("res://tests/helpers.gd")
const Build := preload("res://scripts/sim/build.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const MOTOR_POOL := "res://assets/data/motor_pool.json"
## The yard (x 22 to 62, y 21 to 44: the rows in front of the walkways are shut) and the school's front wall.
const YARD := Rect2(22.0, 21.0, 40.0, 23.0)
## The kinds of prop that are not solid but are real things a home must not sit on.
const PROP_KINDS := ["tent", "tarp", "clothesline", "hoop", "bell", "sandbags", "shrub", "picnic", "bed", "pickup"]
## The painted ground a home must not step on (the pictures have a margin: a home may touch the edge, never go in).
const PAINTED := ["court", "hoop", "foursquare", "hopscotch"]
const TOUCH := 0.15
## How far apart two homes are kept (tiles): a person fits between them.
const LOT_GAP := 0.9
## The people at a site stand at the work spot and a step either side (build.gd's STAND_OFFSETS).
const STANDS := [Vector2(0.0, 0.0), Vector2(1.1, 0.0), Vector2(-1.1, 0.0)]
## How many homes each building has (its max, said here in words).
const HOMES := {"salvage_bench": 1, "greenhouse": 1, "workshop": 1, "bunk_house": 2, "tents": 2, "floodlights": 1, "watchtower": 2, "radio_mast": 1, "scrap_yard": 2}


# --------------------------------------------------------------------- helpers --

func _game(seed_value: int = 71, crew: int = 6) -> Dictionary:
	var g := Helpers.make(seed_value, 1, crew)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.stock.scrap = 500.0
	return g


## A settlement game with the lots claimed (the ring's homes are open).
func _town(claim: Array = ["north", "west", "east"]) -> Dictionary:
	var g := _game(71, 3)
	var sim = g.sim
	sim.day = 99
	for id in sim.town.state:
		sim.town.reveal(id)
		sim.town.state[id].cleared = true
	for l in claim:
		sim.stock.scrap = 1000.0
		sim.lots.claim(String(l))
	sim.stock.scrap = 500.0
	return g


func _lot(pl: Dictionary) -> Rect2:
	var size := Vector2(pl.size)
	return Rect2(Vector2(pl.pos) - size / 2.0, size)


## The picture of a map object: the box round all its pieces.
func _picture(o: Dictionary) -> Rect2:
	var r := Rect2()
	var first := true
	for p in o.pieces:
		var pr := Rect2(float(p.x), float(p.y), float(p.w), float(p.h))
		r = pr if first else r.merge(pr)
		first = false
	return r


## Whether a point is inside a map object's rectangle (the object's own turn undone).
func _in_object(o: Dictionary, p: Vector2) -> bool:
	var c := cos(-float(o.a))
	var s := sin(-float(o.a))
	var dx := p.x - float(o.cx)
	var dy := p.y - float(o.cy)
	return absf(dx * c - dy * s) <= float(o.w) / 2.0 and absf(dx * s + dy * c) <= float(o.h) / 2.0


## The ground each ladder needs in front of it: where people step off it.
func _landing(o: Dictionary) -> Rect2:
	var cx := float(o.cx)
	var cy := float(o.cy)
	if absf(sin(float(o.a))) < 0.5:
		return Rect2(cx - 0.9, cy + 0.6, 1.8, 1.6)
	if cx < 42.0:
		return Rect2(cx + 0.25, cy - 0.5, 1.9, 1.0)
	return Rect2(cx - 2.15, cy - 0.5, 1.9, 1.0)


## The ground in front of a school door (the way the crew crosses the yard to go in and out).
func _door_approach(o: Dictionary) -> Rect2:
	return Rect2(float(o.cx) - float(o.w) / 2.0 - 0.3, float(o.cy) - 4.0, float(o.w) + 0.6, 4.0)


## The motor pool's apron (the vehicle gate's room), read from the file the gate's task owns.
func _apron() -> Rect2:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(MOTOR_POOL)) if FileAccess.file_exists(MOTOR_POOL) else null
	if raw is Dictionary and raw.get("apron") is Array and raw.apron.size() >= 4:
		return Rect2(float(raw.apron[0]), float(raw.apron[1]), float(raw.apron[2]), float(raw.apron[3]))
	return Rect2(35.2, 19.8, 7.6, 12.2)


func _shut_tiles_in(g: Dictionary, r: Rect2) -> Array:
	var out: Array = []
	var w: int = g.world.W
	for ty in range(floori(r.position.y), ceili(r.end.y)):
		for tx in range(floori(r.position.x), ceili(r.end.x)):
			if g.world.solid_p[ty * w + tx] != 0:
				out.append(Vector2i(tx, ty))
	return out


## The tiles of the yard that are grass or soil: the garden's beds and lawn and the bushes along the school (a home is
## never on them).
func _green_tiles(g: Dictionary) -> Array:
	var ids := [int(g.data.terrainTypes.GRASS.id), int(g.data.terrainTypes.SOIL.id)]
	var out: Array = []
	var w: int = g.world.W
	for ty in range(int(YARD.position.y), int(YARD.end.y)):
		for tx in range(int(YARD.position.x), int(YARD.end.x)):
			if int(g.world.terrain[ty * w + tx]) in ids:
				out.append(Rect2(float(tx), float(ty), 1.0, 1.0))
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


## What is wrong with the homes of the compound (the yard's and the wall's; the ring's are in lots.json and are
## tested with the lots), as sentences: none when they are all right.
func _home_problems(g: Dictionary) -> Array:
	var out: Array = []
	var sim = g.sim
	var painted: Array = []
	var things: Array = []
	var ladders: Array = []
	var doors: Array = []
	var bench: Array = []
	for o in g.data.objects:
		var kind := String(o.kind)
		if kind in PAINTED:
			painted.append({"what": "the %s" % kind, "rect": _picture(o).grow(-TOUCH)})
		if bool(o.solid) or kind in PROP_KINDS:
			things.append(o)
		if kind == "ladder":
			ladders.append(o)
		elif kind == "door":
			doors.append(o)
		if kind in ["tarp", "worktable", "generator"] or (kind == "crate" and absf(float(o.cx) - 43.0) < 3.0 and absf(float(o.cy) - 27.0) < 3.0):
			bench.append(_picture(o).grow(-TOUCH))
	var green := _green_tiles(g)
	var apron := _apron()
	var homes: Array = []
	for pl in sim.build.plots():
		if String(pl.kind) in ["yard", "wall"]:
			homes.append(pl)
	for pl in homes:
		var id := String(pl.id)
		var lot := _lot(pl)
		if not YARD.encloses(lot):
			out.append("%s: the lot is not inside the yard %s" % [id, str(lot)])
		var shut := _shut_tiles_in(g, lot)
		if not shut.is_empty():
			out.append("%s: the lot covers shut ground %s" % [id, str(shut)])
		for z in painted:
			if lot.intersects(z.rect):
				out.append("%s: the lot is on %s" % [id, String(z.what)])
		for t in green:
			if lot.intersects(t):
				out.append("%s: the lot is on the garden or a bush at %s" % [id, str(t.position)])
				break
		for r in bench:
			if lot.intersects(r):
				out.append("%s: the lot is on the workbench's set" % id)
				break
		if lot.intersects(apron):
			out.append("%s: the lot is on the motor pool's apron %s" % [id, str(apron)])
		var hit := ""
		var y := lot.position.y
		while y <= lot.end.y and hit == "":
			var x := lot.position.x
			while x <= lot.end.x and hit == "":
				for o in things:
					if _in_object(o, Vector2(x, y)):
						hit = String(o.kind)
						break
				x += 0.25
			y += 0.25
		if hit != "":
			out.append("%s: the lot lies on a %s" % [id, hit])
		for o in ladders:
			if lot.intersects(_landing(o)):
				out.append("%s: the lot is where the ladder at (%.1f, %.1f) lets people off" % [id, float(o.cx), float(o.cy)])
		for o in doors:
			if lot.intersects(_door_approach(o)):
				out.append("%s: the lot is in front of the school door at (%.1f, %.1f)" % [id, float(o.cx), float(o.cy)])
		for q in homes:
			if String(q.id) < id and _lot(q).grow(LOT_GAP / 2.0).intersects(lot.grow(LOT_GAP / 2.0)):
				out.append("%s and %s lie closer than %.1f tiles" % [id, String(q.id), LOT_GAP])
		var sign_at: Vector2 = sim.build.sign_pos(id)
		if not lot.has_point(sign_at) or world_shut(g, sign_at):
			out.append("%s: the sign at %s is not on open ground inside the lot" % [id, str(sign_at)])
		for off in STANDS:
			var spot: Vector2 = Vector2(pl.work) + off
			if world_shut(g, spot):
				out.append("%s: nobody can stand at %s" % [id, str(spot)])
			elif not _reaches_gate(g, spot):
				out.append("%s: the crew cannot walk from the gate to %s" % [id, str(spot)])
		if Vector2(pl.work).distance_to(lot.get_center()) > 2.6:
			out.append("%s: the work spot %s is far from the lot" % [id, str(pl.work)])
	return out


## Stands a building on a plot at once, as if the crew had finished it (its footprint shut).
func _stand(sim, plot_id: String, building_id: String) -> void:
	var pl: Dictionary = sim.build.plot(plot_id)
	pl.building = building_id
	sim.build._block(pl)
	sim.build.version += 1


## The night posts a tower on this plot would reach (their ids), with the tower standing and a shooter at the post.
func _posts_reached(g: Dictionary, plot_id: String) -> Array:
	var sim = g.sim
	_stand(sim, plot_id, "watchtower")
	var out: Array = []
	for post in sim.jobs.posts():
		if sim.build.reach_bonus_at(Vector2(post.pos)) > 0.0:
			out.append(String(post.id))
	sim.build.plot(plot_id).building = ""
	sim.build._unblock(sim.build.plot(plot_id))
	return out


# --------------------------------------------------------------------- the data --

func test_every_building_has_the_homes_its_max_says() -> void:
	var g := _town()
	var sim = g.sim
	for id in HOMES:
		var b: Dictionary = sim.build.building(String(id))
		eq(int(b.max), int(HOMES[id]), "%s: the most there may be" % id)
		var homes: Array = sim.build.homes_of(String(id))
		eq(homes.size(), int(HOMES[id]), "%s has %d homes" % [id, int(HOMES[id])])
		var numbers: Array = []
		for pl in homes:
			numbers.append(int(pl.n))
			eq(String(pl.home), String(id), "%s: the home names its building" % String(pl.id))
		numbers.sort()
		eq(numbers, range(1, int(HOMES[id]) + 1), "%s: the homes are numbered 1 to %d" % [id, int(HOMES[id])])
	var seen_names := {}
	var seen_ids := {}
	var with_home := 0
	for pl in sim.build.plots():
		var id := String(pl.id)
		check(not seen_ids.has(id), "plot ids are unique: %s" % id)
		seen_ids[id] = true
		if String(pl.kind) == "mouth":
			eq(String(pl.get("home", "")), "", "%s: a wall across a street is nobody's home" % id)
			continue
		with_home += 1
		check(sim.build.building(String(pl.get("home", ""))).size() > 0, "%s is the home of a building that exists" % id)
		var name := String(pl.name)
		check(name != "" and name.length() <= 40, "%s has a name that fits a list: '%s'" % [id, name])
		check(not seen_names.has(name), "the name '%s' is used twice" % name)
		seen_names[name] = true
		var why := String(pl.get("why", ""))
		check(why.length() >= 20 and why.length() <= 130 and why.ends_with("."), "%s has a sentence that says why it is there: '%s'" % [id, why])
	eq(with_home, 13, "thirteen homes: eleven in the yard and on the wall, two in the streets")
	g.world.free()


func test_the_yard_has_eleven_homes_and_a_building_never_has_more_than_its_homes() -> void:
	var g := _game()
	var sim = g.sim
	eq(sim.build.plots().size(), 11, "eleven homes in the compound (the ring's are seen when its lots are claimed)")
	var yard_total := 0
	for b in sim.build.catalogue():
		yard_total += int(b.max)
		check(int(b.max) <= sim.build.homes_of(String(b.id)).size(), "%s may stand %d times and has %d homes" % [String(b.id), int(b.max), sim.build.homes_of(String(b.id)).size()])
	eq(yard_total, 11, "the classic start's catalogue is exactly what the eleven homes hold")
	g.world.free()


func test_a_ring_home_is_seen_only_when_its_lot_is_claimed() -> void:
	var g := _game(71, 3)
	var sim = g.sim
	eq(sim.build.plots().size(), 11, "no lot claimed: the compound's eleven")
	eq(sim.build.home_for("scrap_yard"), "", "the scrap yard has no home to build on yet")
	check(sim.build.why_not_build("scrap_yard") != "", "and says so: %s" % sim.build.why_not_build("scrap_yard"))
	g.world.free()
	var t := _town(["north"])
	eq(t.sim.build.plots().size(), 11 + 1 + t.sim.lots.mouths_of("north").size(), "the north lot's home and its streets")
	eq(t.sim.build.home_for("scrap_yard"), "scrap_yard_home_1", "the scrap yard's first home is out in the north")
	t.world.free()


# ------------------------------------------------------------------- the ground --

func test_every_home_is_on_free_ground_with_a_work_spot_the_crew_can_reach() -> void:
	var g := _game()
	var problems := _home_problems(g)
	eq(problems, [], "the homes are all right: %s" % "; ".join(problems))
	g.world.free()


## The guard that the old test did not have: every kind of bad spot is put under a home and must be found.
func test_the_guard_finds_the_court_the_garden_the_playground_the_apron_the_doors_and_the_workbench() -> void:
	var g := _game()
	var sim = g.sim
	var home: Dictionary = sim.build.plot("workshop_home")
	var pos: Vector2 = home.pos
	var cases := {
		"the basketball court": [Vector2(29.5, 30.5), "on the court"],
		"the hoop": [Vector2(29.5, 37.5), "on the hoop"],
		"a bed of the garden": [Vector2(55.5, 27.5), "garden"],
		"the garden's lawn": [Vector2(59.5, 34.5), "garden"],
		"a bush along the school": [Vector2(25.5, 42.5), "bush"],
		"the hopscotch": [Vector2(44.5, 34.5), "hopscotch"],
		"the four-square": [Vector2(39.5, 32.5), "four"],
		"the motor pool's apron": [Vector2(38.5, 27.5), "apron"],
		"the workbench's tarp": [Vector2(45.5, 27.5), "workbench"],
		"a school door's approach": [Vector2(31.5, 41.5), "school door"],
		"the other school door's approach": [Vector2(52.5, 41.5), "school door"],
		"a ladder's landing": [Vector2(24.5, 22.5), "ladder"],
		"a fire barrel": [Vector2(44.5, 22.5), "barrel"],
		"a picnic table": [Vector2(41.5, 40.5), "picnic"],
		"a tent of the camp": [Vector2(33.5, 37.5), "closer than"],
		"the school's own wall": [Vector2(38.5, 44.5), "not inside the yard"],
	}
	for name in cases:
		home.pos = cases[name][0]
		home.work = home.pos + Vector2(0.0, 1.0)
		var text := "; ".join(_home_problems(g))
		check(text.contains(String(cases[name][1])), "a home on %s is found (%s): %s" % [name, String(cases[name][1]), text])
	# two homes on one another
	home.pos = Vector2(sim.build.plot("watchtower_home_1").pos)
	home.work = home.pos + Vector2(0.0, 1.0)
	check("; ".join(_home_problems(g)).contains("lie closer than"), "two homes on one another are found")
	# a work spot inside a prop
	home.pos = pos
	home.work = Vector2(43.9, 25.7)
	check("; ".join(_home_problems(g)).contains("nobody can stand at"), "a work spot on the worktable is found")
	home.work = pos + Vector2(0.0, 1.0)
	eq(_home_problems(g), [], "and with the home put back, nothing is wrong")
	g.world.free()


func test_every_building_stood_on_its_home_leaves_the_doors_the_ladders_and_the_lane_open() -> void:
	var g := _town()
	var sim = g.sim
	var w: int = g.world.W
	var base: PackedByteArray = g.world.solid_p.duplicate()
	for pl in sim.build.plots():
		if String(pl.get("home", "")) != "":
			_stand(sim, String(pl.id), String(pl.home))
	var problems: Array = []
	for pl in sim.build.plots():
		if String(pl.get("home", "")) == "":
			continue
		for off in STANDS:
			if not _reaches_gate(g, Vector2(pl.work) + off) and String(pl.kind) != "ring":
				problems.append("nobody can walk from the gate to the work of %s" % String(pl.id))
	for o in g.data.objects:
		var spots: Array = []
		if String(o.kind) == "door":
			spots = [Vector2(float(o.cx), float(o.cy) - 1.2), Vector2(float(o.cx) - 0.6, float(o.cy) - 1.2), Vector2(float(o.cx) + 0.6, float(o.cy) - 1.2)]
		elif String(o.kind) == "ladder":
			var land := _landing(o)
			spots = [land.get_center()]
		for s in spots:
			if not _reaches_gate(g, s):
				problems.append("with every home built, nobody can walk from the gate to %s (%s at %.1f, %.1f)" % [str(s), String(o.kind), float(o.cx), float(o.cy)])
	var apron := _apron()
	for ty in range(floori(apron.position.y), ceili(apron.end.y)):
		for tx in range(floori(apron.position.x), ceili(apron.end.x)):
			if g.world.solid_p[ty * w + tx] != base[ty * w + tx]:
				problems.append("a building shuts the apron's tile (%d, %d)" % [tx, ty])
	eq(problems, [], "every home built at once leaves the ways open: %s" % "; ".join(problems))
	g.world.free()


# ------------------------------------------------------------------ the sense --

func test_each_home_is_where_its_building_belongs() -> void:
	var g := _game()
	var sim = g.sim
	var by_home := {}
	for pl in sim.build.plots():
		by_home[String(pl.id)] = pl
	var objs: Array = g.data.objects
	# the greenhouse touches the garden: a tile of the garden is within half a tile of the lot
	var green := _green_tiles(g)
	var gh := _lot(sim.build.plot("greenhouse_home")).grow(0.5)
	var touches := false
	for t in green:
		if gh.intersects(t) and t.position.y >= 24.0 and t.position.y < 38.0:
			touches = true
	check(touches, "the greenhouse's lot touches the garden")
	# the workshop is beside the workbench: its lot is within a tile and a half of the worktable (the tarp over it was taken out)
	var ws := _lot(sim.build.plot("workshop_home"))
	var table := Rect2()
	for o in objs:
		if String(o.kind) == "worktable" or String(o.kind) == "generator":
			table = _picture(o) if table.size == Vector2.ZERO else table.merge(_picture(o))
	check(ws.grow(1.5).intersects(table), "the workshop is beside the workbench set (%s and %s)" % [str(ws), str(table)])
	# the salvage bench is by the junk: a crate or the scrap pile within 3 tiles of its lot
	var sb := _lot(sim.build.plot("salvage_bench_home")).grow(3.0)
	var junk := false
	for o in objs:
		if (String(o.kind) in ["crate", "scrap", "tires"]) and float(o.cx) < 30.0 and float(o.cy) > 36.0 and sb.has_point(Vector2(float(o.cx), float(o.cy))):
			junk = true
	check(junk, "the salvage bench stands by the crates and the scrap pile")
	# the bunk houses are against the school's front wall (their lots end within a tile of it), side by side
	for id in ["bunk_house_home_1", "bunk_house_home_2"]:
		var l := _lot(sim.build.plot(id))
		check(l.end.y >= 43.0, "%s is against the school's front wall" % id)
	# the radio mast is near the radio desk
	var desk := Vector2()
	for o in objs:
		if String(o.kind) == "radiodesk":
			desk = Vector2(float(o.cx), float(o.cy))
	check(sim.build.plot("radio_mast_home").pos.distance_to(desk) <= 8.0, "the radio mast is close to the radio desk")
	# the floodlights and the towers are on the north wall (their lots start at the first open row)
	for id in ["floodlights_home", "watchtower_home_1", "watchtower_home_2"]:
		eq(String(sim.build.plot(id).kind), "wall", "%s is on the wall" % id)
		near(_lot(sim.build.plot(id)).position.y, YARD.position.y, 0.001, "%s is up against the north walkway" % id)
	g.world.free()


func test_each_watchtower_reaches_at_least_two_night_posts_and_the_two_reach_different_ones() -> void:
	var g := _game()
	var sim = g.sim
	var west := _posts_reached(g, "watchtower_home_1")
	var east := _posts_reached(g, "watchtower_home_2")
	check(west.size() >= 2, "the west tower reaches at least two posts: %s" % str(west))
	check(east.size() >= 2, "the east tower reaches at least two posts: %s" % str(east))
	var both := {}
	for id in west + east:
		both[id] = true
	check(both.size() >= west.size() + east.size() - 1, "the two cover posts of their own: %s and %s" % [str(west), str(east)])
	var gate: bool = sim.build.plot("watchtower_home_1").pos.x < 36.0 and sim.build.plot("watchtower_home_2").pos.x > 42.0
	check(gate, "one tower stands west of the gate (x under 36) and one east of it (x over 42)")
	# the posts they help are on the north wall, at the gate's side
	for id in west:
		check(Vector2(sim.jobs.post(id).pos).x < 40.0, "the west tower helps a post on the west side: %s" % id)
	for id in east:
		check(Vector2(sim.jobs.post(id).pos).x > 44.0, "the east tower helps a post on the east side: %s" % id)
	g.world.free()


func test_a_tower_reaches_from_its_body_not_its_middle() -> void:
	var g := _game()
	var sim = g.sim
	_stand(sim, "watchtower_home_1", "watchtower")
	var pl: Dictionary = sim.build.plot("watchtower_home_1")
	var radius := float(sim.build.building("watchtower").effects.reach_radius)
	var more := float(sim.build.building("watchtower").effects.reach_bonus)
	# the footprint is x pos-1.5 to pos+1.5, y pos-1.5 to pos+0.5 (building_art.json)
	var edge := Vector2(float(pl.pos.x) + 1.5 + radius - 0.1, float(pl.pos.y) - 0.5)
	near(sim.build.reach_bonus_at(edge), more, 1.0e-9, "just inside the radius of the tower's east wall")
	near(sim.build.reach_bonus_at(edge + Vector2(0.4, 0.0)), 0.0, 1.0e-9, "just outside it")
	near(sim.build.reach_bonus_at(Vector2(pl.pos)), more, 1.0e-9, "at the middle of the lot")
	g.world.free()


# ---------------------------------------------------------------------- home_for --

func test_home_for_gives_the_first_free_home_then_the_next_then_none() -> void:
	var g := _game()
	var sim = g.sim
	eq(sim.build.home_for("watchtower"), "watchtower_home_1", "the first tower goes to its first home")
	check(sim.build.order(sim.build.home_for("watchtower"), "watchtower"), "it is ordered")
	eq(sim.build.home_for("watchtower"), "watchtower_home_2", "the next goes to the second")
	check(sim.build.order(sim.build.home_for("watchtower"), "watchtower"), "and it too")
	eq(sim.build.home_for("watchtower"), "", "a third has no home")
	check(sim.build.why_not_build("watchtower").contains("most"), "and the reason says there are the most: %s" % sim.build.why_not_build("watchtower"))
	# a home that is freed is the first again
	sim.build.cancel("watchtower_home_1")
	eq(sim.build.home_for("watchtower"), "watchtower_home_1", "a cancelled site frees its home, which is the first again")
	eq(sim.build.home_for("greenhouse"), "greenhouse_home", "a building with one home")
	eq(sim.build.home_for("not_a_building"), "", "no such building, no home")
	g.world.free()


func test_the_second_home_waits_for_the_first() -> void:
	var g := _game()
	var sim = g.sim
	var why: String = sim.build.why_not("bunk_house_home_2", "bunk_house")
	check(why.contains("first"), "the second bunk house waits for the first: %s" % why)
	check(not sim.build.order("bunk_house_home_2", "bunk_house"), "and cannot be ordered on the second home")
	check(sim.build.order("bunk_house_home_1", "bunk_house"), "the first can")
	eq(sim.build.why_not("bunk_house_home_2", "bunk_house"), "", "then the second can")
	g.world.free()


func test_a_building_is_ordered_on_its_own_home_only_and_the_words_say_what_the_place_is_for() -> void:
	var t := _town(["north"])
	var sim = t.sim
	var why: String = sim.build.why_not("scrap_yard_home_1", "watchtower")
	check(not why.contains("cannot stand") and not why.contains("on the yard"), "a tower on a street plot is not 'on the yard' any more (the old wrong words): %s" % why)
	check(why.to_lower().contains("scrap yard"), "it says what the place is for: %s" % why)
	why = sim.build.why_not("greenhouse_home", "scrap_yard")
	check(why.to_lower().contains("greenhouse"), "a scrap yard on the greenhouse's home: %s" % why)
	check(not sim.build.order("workshop_home", "greenhouse"), "a greenhouse cannot be ordered on the workshop's home")
	check(sim.build.order(sim.build.home_for("greenhouse"), "greenhouse"), "on its own it can")
	eq(String(sim.build.title_of("watchtower_home_2")), "Watchtower 2 of 2", "a building with two homes is numbered")
	eq(String(sim.build.title_of("greenhouse_home")), "Greenhouse beds", "one with a single home is not")
	t.world.free()


func test_the_ring_homes_follow_the_claims() -> void:
	var t := _town(["north"])
	var sim = t.sim
	eq(sim.build.home_for("scrap_yard"), "scrap_yard_home_1", "the first scrap yard goes to the north")
	check(sim.build.order("scrap_yard_home_1", "scrap_yard"), "ordered")
	eq(sim.build.home_for("scrap_yard"), "", "the second home's lot is not claimed: there is none yet")
	check(sim.build.why_not_build("scrap_yard").to_lower().contains("claim"), "the reason says to claim its lot: %s" % sim.build.why_not_build("scrap_yard"))
	sim.stock.scrap = 1000.0
	sim.lots.claim("west")
	eq(sim.build.home_for("scrap_yard"), "scrap_yard_home_2", "claiming the west road opens the second home")
	t.world.free()


# ---------------------------------------------------------------------- old saves --

func test_a_save_from_before_has_what_it_had_refunded() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 10.0
	var old := {"plots": {
		"north_east_lot": {"building": "greenhouse", "site": {}},
		"junk_corner": {"building": "", "site": {"building": "salvage_bench", "progress": 3.0, "work": 14.0, "scrap": 18.0}},
		"west_wall": {"building": "watchtower", "site": {}},
		"street_wreck": {"building": "scrap_yard", "site": {}},
	}, "queue": ["junk_corner"]}
	sim.build.load_state(old)
	for pl in sim.build.plots():
		eq(String(pl.building), "", "%s is empty: nothing of the old plots stands on a new home" % String(pl.id))
		check(pl.site.is_empty(), "%s has no site" % String(pl.id))
	var back: float = 18.0 + float(sim.build.building("greenhouse").scrap) * 0.5 + float(sim.build.building("watchtower").scrap) * 0.5 + float(sim.build.building("scrap_yard").scrap) * 0.5
	near(float(sim.stock.scrap), 10.0 + back, 1.0e-9, "the site back in full, the buildings by half")
	check(sim.alerts.has("refund"), "and the page says so")
	eq(sim.build.active_site(), {}, "nothing is going up")
	g.world.free()


func test_a_building_on_a_plot_that_is_another_buildings_home_is_refunded_too() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 0.0
	sim.build.load_state({"plots": {
		"greenhouse_home": {"building": "greenhouse", "site": {}},
		"workshop_home": {"building": "greenhouse", "site": {}},
	}, "queue": []})
	eq(String(sim.build.plot("greenhouse_home").building), "greenhouse", "the greenhouse on its own home stays")
	eq(String(sim.build.plot("workshop_home").building), "", "a greenhouse on the workshop's home is not kept")
	near(float(sim.stock.scrap), float(sim.build.building("greenhouse").scrap) * 0.5, 1.0e-9, "its scrap comes back by half")
	g.world.free()


func test_a_save_of_the_new_homes_loads_as_it_was() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.build.order("watchtower_home_1", "watchtower"), "a tower is ordered")
	sim.build._finish(sim.build.plot("watchtower_home_1"))
	check(sim.build.order("workshop_home", "workshop"), "a workshop is ordered")
	sim.build.plot("workshop_home").site.progress = 5.0
	var saved: Dictionary = sim.build.save()
	var g2 := _game()
	g2.sim.build.load_state(saved)
	eq(String(g2.sim.build.plot("watchtower_home_1").building), "watchtower", "the tower stands")
	eq(float(g2.sim.build.plot("workshop_home").site.progress), 5.0, "the workshop's progress is kept")
	check(not g2.sim.alerts.has("refund"), "nothing is refunded")
	g.world.free()
	g2.world.free()


# --------------------------------------------------------------- tents (round 16) --
## Two beds each, two of them: cheap beds so that the crew can grow past the school's six. They give the people a bed and
## nothing else: no patients' beds and no mood, which are the bunk house's.

func test_the_tents_are_cheap_two_beds_each_and_give_nothing_else() -> void:
	var g := _game(71, 3)
	var sim = g.sim
	var t: Dictionary = sim.build.building("tents")
	check(not t.is_empty(), "there is a building 'tents'")
	eq(String(t.name), "Tents", "called Tents")
	eq(int(t.max), 2, "two of them may stand")
	eq(int(t.scrap), 8, "eight scrap")
	near(float(t.work), 6.0, 1.0e-9, "six builder-hours")
	eq(String(t.requires), "", "and nothing must stand first")
	eq(String(t.blurb), "Two beds. Cheap, and cold in winter.", "in plain words")
	eq(t.effects.keys(), ["housing"], "the tents give beds for people and nothing else: no patients' beds, no mood")
	eq(int(t.effects.housing), 2, "two beds each")
	check(int(t.scrap) < int(sim.build.building("bunk_house").scrap) and float(t.work) < float(sim.build.building("bunk_house").work), "cheaper than a bunk house")
	check(not bool(t.get("lots_only", false)) and not t.has("wall_kit"), "an ordinary building of the yard")
	eq(sim.build.homes_of("tents").size(), 2, "with two homes")
	g.world.free()


func test_the_housing_counts_the_tents() -> void:
	var g := _game(71, 3)
	var sim = g.sim
	eq(sim.build.housing(), 6, "the school's six")
	_stand(sim, "tents_home_1", "tents")
	eq(sim.build.housing(), 8, "a tent gives two")
	_stand(sim, "tents_home_2", "tents")
	eq(sim.build.housing(), 10, "and the second two more")
	_stand(sim, "bunk_house_home_1", "bunk_house")
	eq(sim.build.housing(), 14, "with a bunk house, fourteen")
	check(sim.build.bed_spots().size() == 4, "but only the bunk house has beds for patients (%d)" % sim.build.bed_spots().size())
	sim.build.demolish("tents_home_1")
	eq(sim.build.housing(), 12, "and a tent taken down takes its two beds away")
	g.world.free()


func test_tents_are_ordered_one_after_the_other_on_their_own_homes() -> void:
	var g := _game(71, 3)
	var sim = g.sim
	eq(sim.build.home_for("tents"), "tents_home_1", "the first goes to the first home")
	check(sim.build.why_not("tents_home_2", "tents").contains("first"), "the second waits for the first: %s" % sim.build.why_not("tents_home_2", "tents"))
	sim.stock.scrap = 20.0
	check(sim.build.order(sim.build.home_for("tents"), "tents"), "ordered")
	near(float(sim.stock.scrap), 12.0, 1.0e-9, "for eight scrap")
	eq(sim.build.home_for("tents"), "tents_home_2", "the next to the second")
	check(sim.build.order(sim.build.home_for("tents"), "tents"), "and the second")
	eq(sim.build.home_for("tents"), "", "a third has no home")
	check(sim.build.why_not_build("tents").contains("most"), "the most there may be: %s" % sim.build.why_not_build("tents"))
	eq(String(sim.build.title_of("tents_home_2")), "Tents 2 of 2", "numbered on the list")
	g.world.free()


func test_the_tent_homes_are_by_the_fire_barrel_off_the_motor_pool() -> void:
	var g := _game()
	var sim = g.sim
	var barrels: Array = []
	for o in g.data.objects:
		if String(o.kind) == "barrel":
			barrels.append(Vector2(float(o.cx), float(o.cy)))
	var apron := _apron()
	for id in ["tents_home_1", "tents_home_2"]:
		var pl: Dictionary = sim.build.plot(id)
		eq(String(pl.kind), "yard", "%s lies in the yard" % id)
		eq(String(pl.home), "tents", "%s is for the tents" % id)
		var near_fire := false
		for b in barrels:
			near_fire = near_fire or Vector2(pl.pos).distance_to(b) <= 4.5
		check(near_fire, "%s is by a fire barrel (the camp's fire)" % id)
		check(_lot(pl).position.y >= apron.end.y, "%s is south of the motor pool's apron (%s)" % [id, str(apron)])
	check(String(sim.build.plot("tents_home_1").name) != String(sim.build.plot("tents_home_2").name), "each home has a name of its own")
	g.world.free()


func test_a_standing_tent_shuts_its_back_two_rows_and_leaves_the_front_one_open() -> void:
	var g := _game()
	var sim = g.sim
	for id in ["tents_home_1", "tents_home_2"]:
		var pl: Dictionary = sim.build.plot(id)
		_stand(sim, id, "tents")
		var shut := 0
		var w: int = g.world.W
		for ty in range(floori(_lot(pl).position.y), ceili(_lot(pl).end.y)):
			for tx in range(floori(_lot(pl).position.x), ceili(_lot(pl).end.x)):
				if g.world.solid_p[ty * w + tx] != 0:
					shut += 1
		eq(shut, 6, "%s: a tent is three tiles wide and two deep" % id)
		check(_reaches_gate(g, Vector2(pl.work)), "the builders can still reach the front of %s" % id)
	g.world.free()


func test_a_save_without_tents_loads_and_a_save_with_them_keeps_them() -> void:
	var g := _game(71, 3)
	var sim = g.sim
	sim.build.load_state({"plots": {"workshop_home": {"building": "workshop", "site": {}}}, "queue": []})
	eq(sim.build.count("tents"), 0, "a save from before has no tents")
	eq(sim.build.housing(), 6, "and the school's six beds")
	check(not sim.alerts.has("refund"), "nothing is refunded")
	check(sim.build.order("tents_home_1", "tents"), "a tent is ordered")
	sim.build._finish(sim.build.plot("tents_home_1"))
	check(sim.build.order("tents_home_2", "tents"), "and a second")
	sim.build.plot("tents_home_2").site.progress = 2.0
	var saved: Dictionary = sim.build.save()
	var g2 := _game(71, 3)
	g2.sim.build.load_state(saved)
	eq(String(g2.sim.build.plot("tents_home_1").building), "tents", "the first tent stands")
	eq(g2.sim.build.housing(), 8, "its two beds count")
	near(float(g2.sim.build.plot("tents_home_2").site.progress), 2.0, 1.0e-9, "the second is half begun")
	g.world.free()
	g2.world.free()
