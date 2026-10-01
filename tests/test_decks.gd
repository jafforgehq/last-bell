extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const DeckFaces := preload("res://scripts/render/deck_faces.gd")

## North walkway: the deck is row 18, the rail row 19 and the face hangs below it
## over row 20; the three ladders (x 24.5, 48.5 and 60.5) open columns 24, 48
## and 60 in both rows.
const NORTH_GAPS := [24, 48, 60]
const NORTH_ROWS := [19, 20]
## West walkway: the rail column is 21, the ladders (y 24.5, 30.5 and 35.5)
## open rows 24, 30 and 35. East: the rail column is 62 and the ladders (y 24.5,
## 33.5 and 41.5) open rows 24, 33 and 41.
const WEST_GAPS := [24, 30, 35]
const EAST_GAPS := [24, 33, 41]


func _solid(world, grid: PackedByteArray, x: int, y: int) -> bool:
	return grid[y * world.W + x] != 0


## Whether a walk (its waypoints, from `start`) passes through a ladder tile of
## any walkway. The waypoints are only the turns, so the straight stretches
## between them are sampled.
func _through_a_ladder(path: Array, start: Vector2) -> bool:
	var prev := start
	for pt in path:
		var n := int(prev.distance_to(pt) / 0.2) + 1
		for i in n + 1:
			var q: Vector2 = prev.lerp(pt, float(i) / float(n))
			var tx := floori(q.x)
			var ty := floori(q.y)
			if (ty in NORTH_ROWS and tx in NORTH_GAPS) or (tx == 21 and ty in WEST_GAPS) or (tx == 62 and ty in EAST_GAPS):
				return true
		prev = pt
	return false


func test_the_rail_and_the_face_are_shut_to_people_and_the_dead_except_at_the_ladders() -> void:
	var g := Helpers.make(1, 1)
	var w = g.world
	for y in NORTH_ROWS:
		for x in range(21, 63):
			var open: bool = x in NORTH_GAPS
			eq(_solid(w, w.solid_p, x, y), not open, "people at x=%d on row %d" % [x, y])
			eq(_solid(w, w.solid_z, x, y), not open, "the dead at x=%d on row %d" % [x, y])
	for x in range(20, 64):
		check(not _solid(w, w.solid_p, x, 18), "the deck itself (x=%d, row 18) is open" % x)
	for x in NORTH_GAPS:
		check(not _solid(w, w.solid_p, x, 21), "the foot of the ladder at column %d is open" % x)
	g.world.free()


func test_the_face_is_as_deep_as_the_barrier() -> void:
	# the face reaches down to the ground at y = deck edge + height; the tile rows
	# it covers are all shut, so nobody stands where it is drawn
	var data: Dictionary = Helpers.make(1, 1).data
	var edge := 0.0
	for o in data.objects:
		if o.kind == "walkway" and float(o.w) > float(o.h):
			edge = float(o.cy) + float(o.h) / 2.0
	var ground := edge + DeckFaces.WALKWAY_HEIGHT
	eq(floori(ground - 0.2), NORTH_ROWS[NORTH_ROWS.size() - 1], "the barrier's last row is the face's last row")
	check(ground <= float(NORTH_ROWS[NORTH_ROWS.size() - 1]) + 1.0, "and the face ends inside it")


func test_the_side_walkways_are_shut_along_their_rail_except_at_the_ladders() -> void:
	var g := Helpers.make(1, 1)
	var w = g.world
	for y in range(20, 44):
		eq(_solid(w, w.solid_p, 21, y), not (y in WEST_GAPS), "west rail column at y=%d" % y)
		check(not _solid(w, w.solid_p, 20, y), "the west deck (x=20, y=%d) is open" % y)
		eq(_solid(w, w.solid_p, 62, y), not (y in EAST_GAPS), "east rail column at y=%d" % y)
		check(not _solid(w, w.solid_p, 63, y), "the east deck (x=63, y=%d) is open" % y)
	g.world.free()


func test_nobody_stands_under_the_south_ends_of_the_side_walkways() -> void:
	var g := Helpers.make(1, 1)
	var w = g.world
	for y in [44, 45]:
		for x in [20, 21, 62, 63]:
			check(_solid(w, w.solid_p, x, y), "people cannot stand at (%d, %d) under a walkway's end" % [x, y])
			check(_solid(w, w.solid_z, x, y), "nor the dead")
	g.world.free()


func test_the_corners_where_decks_meet_stay_deck() -> void:
	var g := Helpers.make(1, 1)
	var w = g.world
	for y in NORTH_ROWS:
		check(not _solid(w, w.solid_p, 20, y), "the west deck meets the north deck (row %d)" % y)
		check(not _solid(w, w.solid_p, 63, y), "the east deck meets the north deck (row %d)" % y)
	g.world.free()


func test_everyone_gets_to_their_post_and_the_gate_by_a_ladder() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	var yard := Vector2(36.0, 26.0)
	for p in sim.people:
		var post: Dictionary = p.def.post
		var path: Array = sim.path_p.find(g.world.solid_p, yard.x, yard.y, float(post.x), float(post.y))
		check(not path.is_empty(), "%s can get from the yard to %s" % [p.first, post.what])
		# the way in passes through a ladder tile if the post is on a deck
		if float(post.y) < 19.0 or float(post.x) < 21.0 or float(post.x) > 62.0:
			check(_through_a_ladder(path, yard), "%s's way to %s goes up a ladder" % [p.first, post.what])
	g.world.free()


func test_a_click_on_the_rail_or_the_face_is_refused_and_one_on_the_deck_is_not() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	var p = sim.people[2]
	check(not sim.order_move(p, 33.5, 19.5), "the rail row is not somewhere to stand")
	check(not sim.order_move(p, 33.5, 20.5), "nor is the face below it")
	check(sim.order_move(p, 33.5, 18.5), "the deck is")
	g.world.free()


func test_the_dead_inside_the_yard_reach_the_deck_only_at_the_ladders() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	var path: Array = sim.path_z.find(g.world.solid_z, 36.0, 26.0, 39.0, 18.5)
	check(not path.is_empty(), "they can get to someone on the deck")
	check(_through_a_ladder(path, Vector2(36.0, 26.0)), "and they do it by a ladder")
	g.world.free()
