extends "res://tests/case.gd"
## The dressing of the streets (round 12, "the living streets"): the data (assets/data/dressing.json, made by
## tools/make_dressing.py) is sound (the pictures are there, nothing lies on shut ground, on a wall's footprint at a mouth,
## on a ring lot or a work spot, on a prop or a car, nothing covers anything else by more than a little), the node that draws
## it (scripts/render/dressing_node.gd) draws only in a settlement game and does not leak, and the quiet groans of the streets
## by day (scripts/audio/street_air.gd) come rarely, softly and only when they should.

const Helpers := preload("res://tests/helpers.gd")
const MenuFakes := preload("res://tests/menu_fakes.gd")
const DressingNode := preload("res://scripts/render/dressing_node.gd")
const StreetAir := preload("res://scripts/audio/street_air.gd")

const LOTS_PATH := "res://assets/data/lots.json"
## What the generator (tools/make_dressing.py) keeps true: the terrain ids of a street (asphalt, sidewalk, the dirt of an
## alley), how much two pieces may cover each other (of the smaller one's box, and a little more for the box's rounding),
## the part of a body's picture that is its own (the rest is a soft shadow) and the gate's front.
const STREET_TERRAIN := [1, 2, 13]
const OVERLAP_MAX := 0.35
const CORE := {"corpse": 0.75}
const GATE_FRONT := Rect2(36.0, 12.0, 6.0, 3.0)
## The map objects that are drawn on the ground and may be lain over (everything else is a thing a piece must keep off).
const GROUND_KINDS := ["leaves", "treeShadow", "crack", "tufts", "blood", "papers", "stain", "trail", "spray", "scorch", "tracks"]


# --------------------------------------------------------------- the data --

func _pieces() -> Array:
	return DressingNode.pieces()


func _kind(p: Dictionary) -> String:
	return String(p.f).get_slice("_", 1)


## The box a piece covers (tiles): its picture's, turned, and with `core` only the part of it that is its own.
func _box(p: Dictionary, core: bool = false) -> Rect2:
	var r := deg_to_rad(float(p.get("rot", 0.0)))
	var w := absf(cos(r)) * float(p.w) + absf(sin(r)) * float(p.h)
	var h := absf(sin(r)) * float(p.w) + absf(cos(r)) * float(p.h)
	if core:
		var k: float = CORE.get(_kind(p), 1.0)
		w *= k
		h *= k
	return Rect2(float(p.x) - w / 2.0, float(p.y) - h / 2.0, w, h)


func _overlap(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	if i.size.x <= 0.0 or i.size.y <= 0.0:
		return 0.0
	var small := minf(a.size.x * a.size.y, b.size.x * b.size.y)
	return i.size.x * i.size.y / small if small > 0.0 else 1.0


func _lots() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LOTS_PATH))


## The rectangle a mouth's wall shuts: the tiles of `rect` (inclusive).
func _mouth_rect(m: Dictionary) -> Rect2:
	var r: Array = m.rect
	return Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]) + 1.0, float(r[3]) - float(r[1]) + 1.0)


func test_the_data_is_there_with_pictures_and_numbers_that_make_sense() -> void:
	var list := _pieces()
	check(list.size() >= 120 and list.size() <= 170, "about a hundred and fifty pieces: %d" % list.size())
	var kinds := {}
	var flat := 0
	var standing := 0
	for p in list:
		var path := "res://assets/objects/%s.png" % String(p.f)
		check(FileAccess.file_exists(path) and ResourceLoader.exists(path), "the picture of %s is there" % String(p.f))
		check(float(p.w) > 0.2 and float(p.w) < 8.0 and float(p.h) > 0.2 and float(p.h) < 8.0, "%s has a size of a prop: %s x %s" % [String(p.f), str(p.w), str(p.h)])
		kinds[_kind(p)] = true
		if bool(p.get("flat", false)):
			flat += 1
			check(not p.has("sort"), "%s lies on the ground and has no feet to sort by" % String(p.f))
		else:
			standing += 1
			check(p.has("sort") and float(p.sort) > float(p.y) and float(p.sort) <= _box(p).end.y + 0.001, "%s stands on a line of its own inside its picture's lower part" % String(p.f))
	check(flat >= 30 and standing >= 30, "some lie and some stand: %d and %d" % [flat, standing])
	check(kinds.size() >= 12, "a good many kinds: %s" % str(kinds.keys()))
	for must in ["blood", "corpse", "papers", "trashbags", "trashcan", "crate", "tires", "scrap", "hydrant", "sandbags", "tarp"]:
		check(kinds.has(must), "there are %s about" % must)


## What is wrong with the pieces' ground, as sentences (none when they are all right): each tile a piece's box touches is a
## street (asphalt, sidewalk, an alley's dirt) and open for the people and for the dead.
func _ground_problems(list: Array, world) -> Array:
	var bad: Array = []
	for p in list:
		var b := _box(p)
		var found := ""
		for ty in range(floori(b.position.y + 0.02), floori(b.end.y - 0.02) + 1):
			for tx in range(floori(b.position.x + 0.02), floori(b.end.x - 0.02) + 1):
				var ok: bool = tx >= 0 and ty >= 0 and tx < world.W and ty < world.H
				if ok:
					var i: int = ty * world.W + tx
					ok = STREET_TERRAIN.has(int(world.terrain[i])) and world.solid_z[i] == 0 and world.solid_p[i] == 0
				if not ok and found == "":
					found = "tile (%d, %d)" % [tx, ty]
		if found != "":
			bad.append("%s at (%s, %s) is on %s" % [String(p.f), str(p.x), str(p.y), found])
	return bad


## What is in the way of a wall or a building: a mouth's wall (and the post behind it), a ring lot, a work spot, the front
## of the gate.
func _footprint_problems(list: Array) -> Array:
	var lots := _lots()
	var rects: Array = []
	for m in lots.mouths:
		rects.append([String(m.id), _mouth_rect(m)])
		var post: Array = m.post.pos
		rects.append(["the post of " + String(m.id), Rect2(float(post[0]) - 0.5, float(post[1]) - 0.5, 1.0, 1.0)])
	for pl in lots.plots:
		var c: Array = pl.pos
		var s: Array = pl.size
		rects.append([String(pl.id), Rect2(float(c[0]) - float(s[0]) / 2.0, float(c[1]) - float(s[1]) / 2.0, float(s[0]), float(s[1]))])
		var wk: Array = pl.work
		rects.append(["the work spot of " + String(pl.id), Rect2(float(wk[0]) - 0.5, float(wk[1]) - 0.5, 1.0, 1.0)])
	rects.append(["the gate's front", GATE_FRONT])
	check(rects.size() > 14, "the lots are read: %d rectangles" % rects.size())
	var bad: Array = []
	for p in list:
		var b := _box(p)
		for r in rects:
			if b.intersects(r[1]):
				bad.append("%s at (%s, %s) is on %s" % [String(p.f), str(p.x), str(p.y), r[0]])
	return bad


## What lies on something of the map that is not ground: a prop, a car, a bench, a lamp post, an awning, a tree.
func _prop_problems(list: Array, data: Dictionary) -> Array:
	var bad: Array = []
	for p in list:
		var b := _box(p, true)
		var y := b.position.y
		var found := ""
		while y <= b.end.y + 0.001 and found == "":
			var x := b.position.x
			while x <= b.end.x + 0.001 and found == "":
				var at := Vector2(x, y)
				for o in data.objects:
					var k := String(o.kind)
					if GROUND_KINDS.has(k):
						continue
					var hit := false
					if k == "lamppost":
						hit = absf(at.x - float(o.cx)) <= 0.5 and absf(at.y - float(o.cy)) <= 0.5
					elif k == "awning":
						hit = absf(at.x - float(o.cx)) <= float(o.w) / 2.0 and absf(at.y - float(o.cy)) <= float(o.h) / 2.0
					else:
						var c := cos(-float(o.a))
						var s := sin(-float(o.a))
						var dx := at.x - float(o.cx)
						var dy := at.y - float(o.cy)
						hit = absf(dx * c - dy * s) <= float(o.w) / 2.0 and absf(dx * s + dy * c) <= float(o.h) / 2.0
					if hit:
						found = "a " + k
						break
				x += 0.25
			y += 0.25
		for t in data.trees:
			if b.has_point(Vector2(float(t.x), float(t.y))):
				found = "a tree"
		if found != "":
			bad.append("%s at (%s, %s) is on %s" % [String(p.f), str(p.x), str(p.y), found])
	return bad


func _overlap_problems(list: Array) -> Array:
	var bad: Array = []
	for i in list.size():
		for j in range(i + 1, list.size()):
			var o := _overlap(_box(list[i], true), _box(list[j], true))
			if o > OVERLAP_MAX:
				bad.append("%s (%s, %s) and %s (%s, %s): %.2f" % [String(list[i].f), str(list[i].x), str(list[i].y), String(list[j].f), str(list[j].x), str(list[j].y), o])
	return bad


func test_every_piece_lies_on_open_ground_of_the_street_for_the_people_and_the_dead() -> void:
	var g := Helpers.make(3, 1, 3)
	var bad := _ground_problems(_pieces(), g.world)
	eq(bad.size(), 0, "on shut or other ground: %s" % str(bad.slice(0, 6)))
	g.world.free()


func test_no_piece_is_on_a_walls_footprint_a_ring_lot_a_work_spot_or_the_gates_front() -> void:
	var bad := _footprint_problems(_pieces())
	eq(bad.size(), 0, "in the way of a wall or a building: %s" % str(bad.slice(0, 6)))


func test_no_piece_is_on_a_prop_a_car_a_post_a_tree_or_an_awning_of_the_map() -> void:
	var g := Helpers.make(3, 1, 3)
	var bad := _prop_problems(_pieces(), g.data)
	eq(bad.size(), 0, "on something: %s" % str(bad.slice(0, 6)))
	g.world.free()


func test_no_two_pieces_cover_each_other_by_more_than_a_little() -> void:
	var bad := _overlap_problems(_pieces())
	eq(bad.size(), 0, "too much on top of each other: %s" % str(bad.slice(0, 6)))


## A piece for the checks that find the wrong ones.
func _piece(f: String, x: float, y: float, w: float = 0.8, h: float = 0.8) -> Dictionary:
	return {"f": f, "x": x, "y": y, "w": w, "h": h, "sort": y + h * 0.4}


func test_a_piece_on_a_wall_a_lot_a_car_the_yard_or_another_piece_is_found() -> void:
	var g := Helpers.make(3, 1, 3)
	# on the yard, in a building's wall, on the compound's wall: not street
	var ground := _ground_problems([_piece("060_crate", 30.0, 30.0), _piece("060_crate", 2.0, 20.0), _piece("060_crate", 30.0, 16.5), _piece("060_crate", 10.0, 9.0)], g.world)
	eq(ground.size(), 3, "three of the four are on shut ground or not a street (the last is in the road): %s" % str(ground))
	# on a mouth's wall footprint, a ring lot, the gate's front, a post
	var lots := _lots()
	var m: Dictionary = lots.mouths[0]
	var r := _mouth_rect(m)
	var in_wall := _piece("060_crate", r.position.x + r.size.x / 2.0, r.position.y + r.size.y / 2.0)
	var pl: Dictionary = lots.plots[0]
	var in_lot := _piece("060_crate", float(pl.pos[0]), float(pl.pos[1]))
	var at_gate := _piece("060_crate", 39.0, 13.5)
	var on_post := _piece("060_crate", float(m.post.pos[0]), float(m.post.pos[1]))
	var clear := _piece("060_crate", 25.0, 11.0)
	eq(_footprint_problems([in_wall, in_lot, at_gate, on_post, clear]).size(), 4, "a wall's footprint, a lot, the gate's front and a post are found, the road is not")
	# on a car (the green one in the north street), a bench, a lamp post
	var car := _piece("060_crate", 17.0, 8.2)
	var lamp := _piece("060_crate", 24.0, 13.6)
	var bench := _piece("060_crate", 57.5, 4.7)
	var road := _piece("060_crate", 25.0, 11.0)
	eq(_prop_problems([car, lamp, bench, road], g.data).size(), 3, "a car, a lamp post and a bench are found, the road is not")
	# two on top of each other, and one that only touches
	var a := _piece("060_crate", 25.0, 11.0)
	eq(_overlap_problems([a, _piece("060_crate", 25.1, 11.1)]).size(), 1, "two on top of each other are found")
	eq(_overlap_problems([a, _piece("060_crate", 25.7, 11.0)]).size(), 0, "two that only touch are not")
	g.world.free()


func test_the_ring_is_dressed_denser_at_the_mouths_and_the_north_street_than_by_the_school() -> void:
	var lots := _lots()
	var spawns := {}
	for m in lots.mouths:
		spawns[int(m.spawn)] = true
	eq(spawns.size(), 10, "ten ways in")
	# the remains of a barricade near each of the ten: pieces within seven tiles of the wall's rectangle
	for sp in spawns:
		var near := 0
		for m in lots.mouths:
			if int(m.spawn) != sp:
				continue
			var r := _mouth_rect(m).grow(7.0)
			for p in _pieces():
				if r.has_point(Vector2(float(p.x), float(p.y))):
					near += 1
		check(near >= 4, "spawn point %d has the remains of a barricade near it: %d pieces" % [sp, near])
	# the middle stretch (x 25 to 59, clear of the corners' mouths) of the north street and of the street along the school
	var north := 0
	var south := 0
	for p in _pieces():
		if float(p.x) < 25.0 or float(p.x) > 59.0:
			continue
		if float(p.y) < 15.0:
			north += 1
		elif float(p.y) >= 59.0:
			south += 1
	check(north >= 2 * south, "the north street is dressed at least twice as thick as the school's side: %d against %d" % [north, south])
	check(south >= 3, "and the school's side is not bare: %d" % south)


func test_the_pieces_are_not_solid_and_the_walking_grids_are_the_maps_own() -> void:
	var g := Helpers.make(3, 1, 3)
	var world = g.world
	var before := [hash(world.solid_z), hash(world.solid_p), world.solid_z.size()]
	var tall := Node2D.new()
	tall.y_sort_enabled = true
	world.add_child(tall)
	var n := DressingNode.new()
	world.add_child(n)
	n.setup(g.sim, tall)
	n.update()
	check(n.sprite_count() > 100, "the pieces are made")
	eq([hash(world.solid_z), hash(world.solid_p), world.solid_z.size()], before, "the walking grids are as they were")
	world.free()


# --------------------------------------------------------------- the node --

## {"game", "node", "tall"}: the node on a game of this crew (3: a settlement game, 6: the classic start), the way
## main.gd makes it: in the world, with the people's y-sorted node as its stand-in.
func _node(crew: int, seed_value: int = 5) -> Dictionary:
	var g := Helpers.make(seed_value, 1, crew)
	g.sim.waves.enabled = false
	var tall := Node2D.new()
	tall.y_sort_enabled = true
	g.world.add_child(tall)
	var n := DressingNode.new()
	g.world.add_child(n)
	n.setup(g.sim, tall)
	return {"game": g, "node": n, "tall": tall}


func test_a_settlement_game_has_the_dressing_lying_under_the_people_and_standing_among_them() -> void:
	var h := _node(3)
	var n = h.node
	var tall: Node2D = h.tall
	check(h.game.sim.town.on, "a game of the small crew is a settlement game")
	eq(n.sprite_count(), n.piece_count(), "every piece is made")
	eq(n.visible_count(), n.piece_count(), "and shown")
	var lying := 0
	var standing := 0
	for p in _pieces():
		if bool(p.get("flat", false)):
			lying += 1
		else:
			standing += 1
	eq(n._flat.get_child_count(), lying, "what lies is in its own layer")
	eq(tall.get_child_count(), standing, "what stands is among the people")
	check(n._flat.z_index < 6, "the layer is under the people (z 6)")
	var feet_ok := true
	for c in tall.get_children():
		if c.get_child_count() != 1 or not (c.get_child(0) is Sprite2D):
			feet_ok = false
	check(feet_ok, "each standing piece is a node at its feet with its picture on it")
	# the first standing piece's feet are where the data says
	var first: Dictionary = {}
	for p in _pieces():
		if not bool(p.get("flat", false)):
			first = p
			break
	var node0: Node2D = tall.get_child(0)
	near(node0.position.x / 64.0, float(first.x), 0.001, "stands where it is put")
	near(node0.position.y / 64.0, float(first.sort), 0.001, "and is sorted by its feet")
	h.game.world.free()


func test_a_classic_game_shows_nothing_and_has_no_sprites_at_all() -> void:
	var h := _node(6)
	var n = h.node
	check(not h.game.sim.town.on, "the classic start is not a settlement game")
	eq(n.sprite_count(), 0, "no sprites are made")
	eq(n.visible_count(), 0, "none is shown")
	eq(h.tall.get_child_count(), 0, "nothing is among the people")
	eq(n._flat.get_child_count(), 0, "and nothing under them")
	n.update()
	n.update()
	eq(n.sprite_count(), 0, "frames go by and still nothing")
	h.game.world.free()


func test_the_node_follows_the_rules_made_once_and_shown_or_hidden_as_the_game_changes() -> void:
	# the nodes are built before a run is started (town.on turns true in start_run or a load): a classic game first
	var h := _node(6)
	var n = h.node
	var sim = h.game.sim
	eq(n.visible_count(), 0, "a classic game shows nothing")
	sim.crew_start = 3
	sim.start_run(1, 9)
	check(sim.town.on, "the run is now a settlement game")
	eq(n.sprite_count(), 0, "the node has not looked yet")
	n.update()
	eq(n.sprite_count(), n.piece_count(), "it makes them when it looks")
	eq(n.makes, 1, "once")
	eq(n.visible_count(), n.piece_count(), "and shows them")
	var kids: int = h.tall.get_child_count()
	for i in 3:
		sim.town.on = false
		n.update()
		eq(n.visible_count(), 0, "a game that is not a settlement game hides them")
		eq(h.tall.get_child_count(), kids, "(they are not taken out: they are only hidden)")
		sim.town.on = true
		n.update()
		eq(n.visible_count(), n.piece_count(), "and a settlement game shows them again")
	eq(n.makes, 1, "made once, whatever the runs")
	eq(h.tall.get_child_count(), kids, "and not made again on top of themselves")
	eq(n.sprite_count(), n.piece_count(), "the same number of sprites")
	h.game.world.free()


func test_the_node_does_not_leak_when_it_goes_or_the_run_restarts() -> void:
	var g := Helpers.make(5, 1, 3)
	var tall := Node2D.new()
	tall.y_sort_enabled = true
	g.world.add_child(tall)
	await Engine.get_main_loop().process_frame
	var before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var n := DressingNode.new()
	g.world.add_child(n)
	n.setup(g.sim, tall)
	var after_make := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	check(after_make > before + 100, "the node has its sprites: %d more nodes" % (after_make - before))
	for i in 4:
		g.sim.start_run(1, 40 + i)
		n.update()
	eq(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), after_make, "a run that restarts makes no new nodes")
	n.free()
	await Engine.get_main_loop().process_frame
	eq(tall.get_child_count(), 0, "when the node goes the standing pieces go out of the people's node with it")
	eq(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), before, "and nothing is left over")
	g.world.free()


func test_the_game_has_the_node_in_the_world_and_only_a_settlement_game_shows_it() -> void:
	var s := MenuFakes.game({"difficulty": 1, "seed": 7, "crew": 3})
	var main = s.main
	check(main.dressing_view != null and main.dressing_view.get_parent() == main.world, "main has the node, in the world's space")
	check(main.dressing_view._tall == main.entities, "and what stands is sorted among the people")
	check(main.sim.town.on, "a game of the small crew is a settlement game")
	eq(main.dressing_view.visible_count(), main.dressing_view.piece_count(), "all of it is shown")
	check(main.street_air != null and main.street_air.get_parent() == main.world, "main has the quiet groans too")
	await MenuFakes.leave(s)
	for meta in [{"difficulty": 1, "seed": 7}, {"title": true}, {"tutorial": true, "difficulty": 0, "seed": 3}]:
		var c := MenuFakes.game(meta)
		var cm = c.main
		check(not cm.sim.town.on, "%s is not a settlement game" % str(meta))
		eq(cm.dressing_view.sprite_count(), 0, "%s has no dressing made" % str(meta))
		eq(cm.dressing_view.visible_count(), 0, "or shown")
		eq(cm.dressing_view._flat.get_child_count(), 0, "%s has nothing under the people" % str(meta))
		await MenuFakes.leave(c)


# ----------------------------------------------------------- the quiet groans --

class FakeSound:
	extends RefCounted
	var muted := false
	var streams := {"groan": []}


class FakeGame:
	extends RefCounted
	var sim
	var speed := 1
	var menu_open := false
	var sound = FakeSound.new()
	var cam_center := Vector2(42.0, 30.0)


## {"game", "air", "world", "fake"}: the groans on a game of this crew, a straggler (a wanderer) in the street far from the
## camera if `straggler`.
func _air(crew: int, straggler: bool = true) -> Dictionary:
	var g := Helpers.make(11, 1, crew)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	if straggler:
		var z = sim.spawn(8.5, 20.5, "wander")
		z.wander_t = 100.0
	var fake := FakeGame.new()
	fake.sim = sim
	fake.sound.streams = {"groan": [load("res://assets/audio/groan_0.wav"), load("res://assets/audio/groan_1.wav")]}
	var air := StreetAir.new()
	g.world.add_child(air)
	air.setup(fake)
	return {"game": g, "air": air, "fake": fake}


func test_the_groans_are_for_the_day_of_a_settlement_game_with_the_dead_in_the_streets() -> void:
	var h := _air(3)
	var air = h.air
	var fake = h.fake
	var sim = h.game.sim
	check(air.quiet_day(), "a settlement game, by day, a straggler in the street")
	sim.phase = "night"
	check(not air.quiet_day(), "not at night, when the real ones are loud")
	sim.phase = "dusk"
	check(not air.quiet_day(), "nor at dusk")
	sim.phase = "dawn"
	check(not air.quiet_day(), "nor at dawn")
	sim.phase = "day"
	fake.speed = 0
	check(not air.quiet_day(), "not while the game is paused")
	fake.speed = 1
	fake.menu_open = true
	check(not air.quiet_day(), "nor under a menu")
	fake.menu_open = false
	fake.sound.muted = true
	check(not air.quiet_day(), "nor with the sound off")
	fake.sound.muted = false
	sim.over = "lost"
	check(not air.quiet_day(), "nor when the game is over")
	sim.over = ""
	check(air.quiet_day(), "and again when all is as it was")
	sim.zombies.clear()
	check(not air.quiet_day(), "not with nobody about the streets")
	h.game.world.free()
	var c := _air(6)
	check(not c.game.sim.town.on, "the classic start")
	c.game.sim.zombies.clear()
	c.game.sim.spawn(8.5, 20.5, "wander")
	check(c.game.sim.streets.street_dead() > 0, "(with a wanderer about)")
	check(not c.air.quiet_day(), "has none of this")
	c.game.world.free()


func test_one_groan_every_twelve_to_twenty_five_seconds_at_most_and_soft_and_low() -> void:
	var h := _air(3)
	var air = h.air
	var times: Array = []
	var t := 0.0
	var seen := 0
	while t < 900.0:
		air.update(1.0 / 30.0)
		t += 1.0 / 30.0
		if air.plays > seen:
			seen = air.plays
			times.append(t)
			check(float(air.last.db) <= StreetAir.LEVEL_DB and float(air.last.db) >= StreetAir.LEVEL_DB - 3.0 - 0.001, "quiet: %s dB" % str(air.last.db))
			check(float(air.last.pitch) >= StreetAir.PITCH_MIN - 0.001 and float(air.last.pitch) <= StreetAir.PITCH_MAX + 0.001 and float(air.last.pitch) < 1.0, "and low: %s" % str(air.last.pitch))
			near(float(air.last.x), 8.5, 0.01, "from where the straggler is")
	check(times.size() >= 900 / 25 - 1 and times.size() <= 900 / 12, "rare: %d in 900 seconds" % times.size())
	check(times[0] >= StreetAir.GAP_MIN - 0.1 and times[0] <= StreetAir.GAP_MAX + 0.1, "the first comes after a gap, not at once: %s" % str(times[0]))
	for i in range(1, times.size()):
		var gap: float = times[i] - times[i - 1]
		check(gap >= StreetAir.GAP_MIN - 0.1 and gap <= StreetAir.GAP_MAX + 0.1, "gap %d is %.1f seconds" % [i, gap])
	h.game.world.free()


func test_the_groans_wait_while_the_game_is_paused_and_never_play_at_night_or_in_a_classic_game() -> void:
	var h := _air(3)
	var air = h.air
	var fake = h.fake
	var timer: float = air._t
	fake.speed = 0
	for i in 3000:
		air.update(1.0 / 30.0)
	eq(air.plays, 0, "none while paused")
	near(air._t, timer, 1.0e-9, "and the wait has not run down")
	fake.speed = 1
	h.game.sim.phase = "night"
	for i in 3000:
		air.update(1.0 / 30.0)
	eq(air.plays, 0, "none at night")
	h.game.world.free()
	var c := _air(6)
	for i in 3000:
		c.air.update(1.0 / 30.0)
	eq(c.air.plays, 0, "none in a classic game, wanderer or not")
	c.game.world.free()
	var e := _air(3, false)
	for i in 3000:
		e.air.update(1.0 / 30.0)
	eq(e.air.plays, 0, "none with the streets empty")
	e.game.world.free()


func test_the_groan_is_from_one_of_the_dead_out_of_sight_not_the_ones_the_real_groans_cover() -> void:
	var h := _air(3)
	var air = h.air
	var sim = h.game.sim
	var fake = h.fake
	check(air.pick() != null, "a straggler far from the camera is picked")
	fake.cam_center = Vector2(8.5, 20.5)
	check(air.pick() == null, "one at the camera is left to the real groans")
	var far = sim.spawn(70.5, 40.5, "wander")
	far.wander_t = 100.0
	check(air.pick() == far, "another far off is the one")
	far.state = "dead"
	check(air.pick() == null, "a dead one is not")
	h.game.world.free()
