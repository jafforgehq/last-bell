## The vehicle gate, the deck bridge, the clear lane and the motor pool (round 15, task GATE): the numbers of
## assets/data/motor_pool.json against the real map, the gate node (scripts/render/gate_node.gd), the bridge over the gate,
## the street's lane and the apron kept clear, and the gate segment's rules left as they were.
extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const GateNode := preload("res://scripts/render/gate_node.gd")
const DeckFaces := preload("res://scripts/render/deck_faces.gd")
const Convoy := preload("res://scripts/sim/convoy.gd")

const POOL_PATH := "res://assets/data/motor_pool.json"
const DRESSING_PATH := "res://assets/data/dressing.json"
const OBJECTS := "res://assets/objects/"
## A car's body (tiles): along the nose, across.
const CAR_L := 4.4
const CAR_W := 2.2
## What lies on the ground (paint, stains, blood): a car drives over it, it is not in the way.
const GROUND_KINDS := ["blood", "crack", "papers", "stain", "scorch", "spray", "trail", "manhole", "leaves", "treeShadow", "tracks", "drain", "court", "foursquare", "hopscotch", "lanes", "apron"]
## Pieces of the map that are not in a car's way as props (the walkway's own planks and ladders, the bridge, the roofs and awnings).
const NOT_PROPS := ["walkway", "ladder", "bridge", "roof", "awning", "tarp"]
## The gate's own tiles: the wall (rows 15 to 17) between the posts: shut to the dead and to people, the opening is only a picture.
## (Rows 19 and 20 are the walkway's barrier, its rail and scaffold: the deck's lattice is checked as a box, with a gap under the bridge.)
const GATE_COLS := [36, 37, 38, 39, 40, 41]
const GATE_ROWS := [15, 16, 17]
const BARRIER_ROWS := [19, 20]
## The street (tiles): the eastbound lane that nothing may stand in (the turn at the gate is checked along the routes).
const LANE := Rect2(0.0, 9.9, 84.0, 2.7)


# --------------------------------------------------------------------------------------------------- geometry --

static func _corners(cx: float, cy: float, length: float, width: float, heading: float) -> PackedVector2Array:
	var c := cos(heading)
	var s := sin(heading)
	var out := PackedVector2Array()
	for k in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
		var fx: float = k.x * length / 2.0
		var fy: float = k.y * width / 2.0
		out.append(Vector2(cx + fx * c - fy * s, cy + fx * s + fy * c))
	return out


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _aabb(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## Whether two convex polygons overlap by more than `margin` (separating axes).
static func _overlap(a: PackedVector2Array, b: PackedVector2Array, margin: float = 0.02) -> bool:
	if not _aabb(a).grow(-margin).intersects(_aabb(b).grow(-margin)):
		return false
	for poly in [a, b]:
		for i in poly.size():
			var e: Vector2 = poly[(i + 1) % poly.size()] - poly[i]
			if e.length() < 0.000001:
				continue
			var n := Vector2(-e.y, e.x).normalized()
			var amin := INF
			var amax := -INF
			var bmin := INF
			var bmax := -INF
			for p in a:
				var d := n.dot(p)
				amin = minf(amin, d)
				amax = maxf(amax, d)
			for p in b:
				var d := n.dot(p)
				bmin = minf(bmin, d)
				bmax = maxf(bmax, d)
			if amax <= bmin + margin or bmax <= amin + margin:
				return false
	return true


static func _in_any(p: Vector2, zones: Array) -> bool:
	for z in zones:
		if p.x >= float(z[0]) - 0.001 and p.x <= float(z[2]) + 0.001 and p.y >= float(z[1]) - 0.001 and p.y <= float(z[3]) + 0.001:
			return true
	return false


## The route's samples: [{x, y, h (radians, the nose), rev}], one every `step` tiles (the nose from `h`, else the leg's direction).
static func _sample(route: Array, step: float) -> Array:
	var out: Array = []
	for i in range(1, route.size()):
		var p0: Dictionary = route[i - 1]
		var p1: Dictionary = route[i]
		var a := Vector2(float(p0.x), float(p0.y))
		var b := Vector2(float(p1.x), float(p1.y))
		var rev := bool(p1.get("rev", false))
		var n := maxi(1, int(ceil(a.distance_to(b) / step)))
		for k in n + (1 if i == route.size() - 1 else 0):
			var f := float(k) / float(n)
			var at := a.lerp(b, f)
			var h: float
			if p0.has("h") and p1.has("h"):
				h = deg_to_rad(float(p0.h) + wrapf(float(p1.h) - float(p0.h), -180.0, 180.0) * f)
			else:
				h = (b - a).angle() + (PI if rev else 0.0)
			out.append({"x": at.x, "y": at.y, "h": h, "rev": rev})
	return out


# ------------------------------------------------------------------------------------------------ the checks --

static func _pool() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(POOL_PATH))
	return raw if raw is Dictionary else {}


## The boxes of everything a car may not drive through, outside the apron's and the gate's own business: [[name, polygon]].
static func _obstacles(data: Dictionary) -> Array:
	var out: Array = []
	for o in data.objects:
		var kind := String(o.kind)
		if int(o.layer) <= 1 or kind in GROUND_KINDS or kind in NOT_PROPS or o.get("segment") != null:
			continue
		out.append(["%s %s" % [kind, str(o.id)], _corners(float(o.cx), float(o.cy), float(o.w), float(o.h), float(o.a))])
	var dressing = JSON.parse_string(FileAccess.get_file_as_string(DRESSING_PATH))
	if dressing is Dictionary:
		var i := 0
		for p in dressing.pieces:
			var f := String(p.f)
			if not bool(p.get("flat", false)) or f.contains("corpse") or f.contains("tarp"):
				out.append(["dressing %d %s" % [i, f], _corners(float(p.x), float(p.y), float(p.w), float(p.h), deg_to_rad(float(p.get("rot", 0.0))))])
			i += 1
	# the deck's lattice face under the north walkway, but under the bridge
	var gap := [36.0, 42.0]
	for o in data.objects:
		if String(o.kind) == "bridge":
			gap = [float(o.cx) - float(o.w) / 2.0, float(o.cx) + float(o.w) / 2.0]
	for o in data.objects:
		if String(o.kind) == "walkway" and float(o.w) >= float(o.h):
			var x0 := float(o.cx) - float(o.w) / 2.0
			var x1 := float(o.cx) + float(o.w) / 2.0
			var y1 := float(o.cy) + float(o.h) / 2.0
			out.append(["deck face (west)", _rect_poly(Rect2(x0, y1 + 0.05, float(gap[0]) - x0, DeckFaces.WALKWAY_HEIGHT - 0.05))])
			out.append(["deck face (east)", _rect_poly(Rect2(float(gap[1]), y1 + 0.05, x1 - float(gap[1]), DeckFaces.WALKWAY_HEIGHT - 0.05))])
	return out


## What is wrong with a motor pool (a dictionary as the file has it) on this world: one sentence each, [] when it is sound.
static func pool_problems(pool: Dictionary, world, data: Dictionary) -> Array:
	var bad: Array = []
	var zones_d: Dictionary = pool.get("zones", {})
	var zones: Array = zones_d.values()
	var spots: Array = pool.get("spots", [])
	if spots.is_empty() or spots.size() > 4:
		bad.append("a motor pool has one to four spots, this has %d" % spots.size())
	for need in ["lane", "junction", "gate", "posts", "bridge", "apron"]:
		if not zones_d.has(need):
			bad.append("zone `%s` is missing" % need)
	if not bad.is_empty():
		return bad
	var apron: Array = zones_d.apron
	var obstacles := _obstacles(data)
	var parked := {}
	for s in spots:
		parked[int(s.id)] = _corners(float(s.at[0]), float(s.at[1]), CAR_L, CAR_W, -PI / 2.0)
	var ids := parked.keys()
	for id in ids:
		for c in parked[id]:
			if not _in_any(c, [apron]):
				bad.append("spot %d: the parked car is not inside the apron (%s)" % [id, str(c)])
		for ob in obstacles:
			if _overlap(parked[id], ob[1]):
				bad.append("spot %d: the parked car overlaps %s" % [id, String(ob[0])])
		for other in ids:
			if int(other) > int(id) and _overlap(parked[id], parked[other], 0.01):
				bad.append("spots %d and %d overlap" % [id, other])
	# the aisle between the two side bays is 3 tiles or wider
	var west := -INF
	var east := INF
	var gate_x := float(pool.gate.x)
	for s in spots:
		if bool(s.get("long", false)):
			continue
		if float(s.at[0]) < gate_x:
			west = maxf(west, float(s.at[0]) + CAR_W / 2.0)
		else:
			east = minf(east, float(s.at[0]) - CAR_W / 2.0)
	if west > -INF and east < INF and east - west < 3.0 - 0.0001:
		bad.append("the aisle is %.2f wide, 3 wanted" % (east - west))
	var w: int = world.W
	for s in spots:
		for which in ["out", "in"]:
			var route: Array = s["%s_route" % which]
			var label := "spot %d %s" % [int(s.id), which]
			if route.size() < 2:
				bad.append("%s: a route has two points at least" % label)
				continue
			var first: Dictionary = route[0]
			var last: Dictionary = route[route.size() - 1]
			if which == "out":
				if Vector2(float(first.x), float(first.y)).distance_to(Vector2(float(s.at[0]), float(s.at[1]))) > 0.01:
					bad.append("%s does not start at the spot" % label)
				if absf(float(last.x) - float(pool.edge_east)) > 0.01:
					bad.append("%s does not end at the map's east edge" % label)
				for p in route:
					if bool(p.get("rev", false)):
						bad.append("%s reverses (a car leaves forward)" % label)
						break
			else:
				if absf(float(first.x) - float(pool.edge_west)) > 0.01:
					bad.append("%s does not start at the map's west edge" % label)
				if Vector2(float(last.x), float(last.y)).distance_to(Vector2(float(s.at[0]), float(s.at[1]))) > 0.01:
					bad.append("%s does not end at the spot" % label)
				if not bool(last.get("rev", false)):
					bad.append("%s: the last leg is not a reverse" % label)
				if absf(wrapf(float(last.get("h", 0.0)) - 270.0, -180.0, 180.0)) > 0.5:
					bad.append("%s ends with the nose at %s, not to the north" % [label, str(last.get("h"))])
				var gear := false
				var came_forward := false
				for p in route:
					if bool(p.get("rev", false)):
						gear = gear or came_forward
					else:
						came_forward = true
				if not gear:
					bad.append("%s: no reversing stretch after the forward drive in" % label)
			var seen := {}
			for smp in _sample(route, 0.25):
				var body := _corners(float(smp.x), float(smp.y), CAR_L, CAR_W, float(smp.h))
				var pts: Array = []
				for i in 4:
					pts.append(body[i])
					pts.append((body[i] + body[(i + 1) % 4]) / 2.0)
				for p in pts:
					if not _in_any(p, zones):
						seen["outside the zones at (%.2f, %.2f)" % [smp.x, smp.y]] = true
						break
				var box := _aabb(body)
				for ty in range(maxi(0, floori(box.position.y)), mini(world.H, floori(box.end.y) + 1)):
					for tx in range(maxi(0, floori(box.position.x)), mini(w, floori(box.end.x) + 1)):
						if world.solid_p[ty * w + tx] == 0 and world.solid_z[ty * w + tx] == 0:
							continue
						if (tx in GATE_COLS and ty in GATE_ROWS) or ty in BARRIER_ROWS:
							continue
						if _overlap(body, _rect_poly(Rect2(tx, ty, 1, 1))):
							seen["on the shut tile (%d, %d)" % [tx, ty]] = true
				for ob in obstacles:
					if _overlap(body, ob[1]):
						seen["through %s" % String(ob[0])] = true
				for id in ids:
					if int(id) != int(s.id) and _overlap(body, parked[id]):
						seen["through the car in spot %d" % id] = true
				if seen.size() > 6:
					break
			for what in seen:
				bad.append("%s: %s" % [label, what])
	return bad


# ------------------------------------------------------------------------------------------- the motor pool --

func test_the_motor_pool_file_is_sound_against_the_real_map() -> void:
	var g := Helpers.make(1, 1)
	var problems := pool_problems(_pool(), g.world, g.data)
	eq(problems, [], "the motor pool")
	g.world.free()


func test_the_pool_check_does_find_a_bad_pool() -> void:
	# (the check can fail: a route pushed sideways runs into the gate's post, a spot moved onto the workbench's table is found)
	var g := Helpers.make(1, 1)
	var pool := _pool()
	var shifted: Dictionary = pool.duplicate(true)
	for p in shifted.spots[0].in_route:
		p.x = float(p.x) + 2.0
	check(not pool_problems(shifted, g.world, g.data).is_empty(), "a route 2 tiles out of line is found")
	var onto: Dictionary = pool.duplicate(true)
	onto.spots[1].at = [43.9, 25.7]
	check(not pool_problems(onto, g.world, g.data).is_empty(), "a spot on the worktable is found")
	var narrow: Dictionary = pool.duplicate(true)
	narrow.spots[1].at = [39.4, 27.6]
	check(not pool_problems(narrow, g.world, g.data).is_empty(), "an aisle narrower than 3 is found")
	var short: Dictionary = pool.duplicate(true)
	short.spots[0].erase("out_route")
	short.spots[0].out_route = []
	check(not pool_problems(short, g.world, g.data).is_empty(), "a spot with no route out is found")
	g.world.free()


func test_the_pool_has_an_aisle_and_up_to_four_spots_and_the_bus_has_a_place() -> void:
	var pool := _pool()
	var spots: Array = pool.spots
	check(spots.size() >= 3 and spots.size() <= 4, "three or four spots: %d" % spots.size())
	for i in spots.size():
		eq(int(spots[i].id), i, "the spots are numbered in order")
	var longs := 0
	for s in spots:
		if bool(s.get("long", false)):
			longs += 1
			var apron_end := float(pool.apron[1]) + float(pool.apron[3])
			check(float(s.at[1]) + 8.07 / 2.0 <= apron_end + 0.01, "the bus's tail (its middle is the spot) is inside the apron: %.2f of %.2f" % [float(s.at[1]) + 8.07 / 2.0, apron_end])
			check(not s.has("long_dy"), "no separate offset for the bus: `at` is its middle")
	eq(longs, 1, "one spot takes the bus")
	var a: Array = pool.apron
	check(float(a[0]) >= 33.0 and float(a[0]) + float(a[2]) <= 42.7, "the apron is inside the yard's strip between the court and the workbench")
	near(float(pool.lane_y), 11.25, 0.0001, "the eastbound lane")
	check(float(pool.edge_west) < 0.0 and float(pool.edge_east) > 84.0, "the routes begin and end off the map")


func test_the_convoy_reads_the_pool_and_a_car_drives_the_points_as_they_are() -> void:
	var pool := _pool()
	eq(Convoy.problems(pool), [], "the convoy module finds nothing wrong with the file")
	eq(Convoy.spots(), (pool.spots as Array).size(), "and has the spots")
	for s in pool.spots:
		var inn: Array = Convoy.route(int(s.id), "in")
		var end: Dictionary = Convoy.pose(inn, 1.0)
		check(end.pos.distance_to(Vector2(float(s.at[0]), float(s.at[1]))) < 0.01, "spot %d: the car ends in the bay" % int(s.id))
		check(bool(end.reverse), "spot %d: reversing in" % int(s.id))
		near(absf(wrapf(rad_to_deg(float(end.heading)) - 270.0, -180.0, 180.0)), 0.0, 0.5, "spot %d: with the nose to the north" % int(s.id))
		var out: Array = Convoy.route(int(s.id), "out")
		var start: Dictionary = Convoy.pose(out, 0.0)
		check(not bool(start.reverse), "spot %d: and out forward" % int(s.id))
		near(absf(wrapf(rad_to_deg(float(start.heading)) - 270.0, -180.0, 180.0)), 0.0, 0.5, "spot %d: nose first, to the north" % int(s.id))
		# half way along the way in the car is on the polyline itself (the points are dense: nothing is left to round)
		var mid: Dictionary = Convoy.pose(inn, 0.5)
		var nearest := INF
		for i in range(1, inn.size()):
			var a := Vector2(float(inn[i - 1].x), float(inn[i - 1].y))
			var b := Vector2(float(inn[i].x), float(inn[i].y))
			var t := clampf((mid.pos - a).dot(b - a) / maxf((b - a).length_squared(), 0.000001), 0.0, 1.0)
			nearest = minf(nearest, mid.pos.distance_to(a.lerp(b, t)))
		check(nearest < 0.01, "spot %d: the car is on its road (%.3f off)" % [int(s.id), nearest])


func test_a_car_on_the_apron_can_reach_every_spot_from_the_gate_and_back() -> void:
	# every in route ends at its spot, and every out route starts there and runs on to the east edge: and they are one road in the gate
	var pool := _pool()
	for s in pool.spots:
		var out: Array = s.out_route
		var inn: Array = s.in_route
		var gate_y := 16.0
		var out_x := -1.0
		var in_x := -1.0
		for p in out:
			if float(p.y) <= gate_y and out_x < 0.0:
				out_x = float(p.x)
		for p in inn:
			if float(p.y) >= gate_y and in_x < 0.0:
				in_x = float(p.x)
		check(out_x > 36.58 and out_x < 41.42, "spot %d: the car leaves between the gate posts (x %.2f)" % [int(s.id), out_x])
		check(in_x > 36.58 and in_x < 41.42, "spot %d: and comes in between them (x %.2f)" % [int(s.id), in_x])


# ------------------------------------------------------------------------------------------------ the node --

func _node(g: Dictionary):
	var gate = GateNode.new()
	g.world.add_child(gate)
	gate.setup(g.world, g.sim)
	return gate


func test_the_gate_node_has_the_numbers_of_the_plan() -> void:
	eq(GateNode.ZONE, Rect2(35.5, 14.0, 7.0, 7.5), "the gate's zone")
	eq(GateNode.Z_CAR, 3, "the z a car is drawn in")
	check(GateNode.OPEN_TIME > 0.6 and GateNode.OPEN_TIME < 1.0, "about 0.8 seconds (the demand comes about a second before the car)")


func test_the_leaves_ease_open_and_shut_in_about_a_second_and_a_fifth() -> void:
	var g := Helpers.make(1, 1)
	var gate = _node(g)
	check(gate.is_shut(), "it starts shut")
	near(gate.leaf_offset(), 0.0, 0.0001, "the leaves are where the picture has them")
	var left: Node2D = gate.leaves.get_node("LeafL")
	var right: Node2D = gate.leaves.get_node("LeafR")
	var left0 := left.position
	var right0 := right.position
	for i in 4:
		gate.follow(1.0, 0.1)
	near(gate.open, 0.5, 0.0001, "half way after 0.4 seconds")
	check(not gate.is_open() and not gate.is_shut(), "and neither open nor shut")
	for i in 7:
		gate.follow(1.0, 0.1)
	check(gate.is_open(), "open after 1.1 seconds")
	near(gate.open, 1.0, 0.0001, "and no more than open")
	near(left.position.x, left0.x - GateNode.TRAVEL * GateNode.TILE, 0.01, "the left leaf slid out to the left")
	near(right.position.x, right0.x + GateNode.TRAVEL * GateNode.TILE, 0.01, "the right leaf out to the right")
	near(left.position.y, left0.y, 0.0001, "and only sideways")
	for i in 9:
		gate.follow(0.0, 0.1)
	check(gate.is_shut(), "shut again after 0.9 seconds")
	near(left.position.x, left0.x, 0.01, "the left leaf is home")
	near(right.position.x, right0.x, 0.01, "and the right")
	# a frame that is too long still stops at the end, and one that is zero changes nothing
	gate.follow(1.0, 5.0)
	check(gate.is_open(), "a long frame opens it")
	gate.follow(0.0, 0.0)
	check(gate.is_open(), "no time, no change")
	# half-way back and then forward again: it turns round where it is
	gate.follow(0.0, 0.4)
	gate.follow(1.0, 0.2)
	near(gate.open, 0.75, 0.0001, "it turns round where it is")
	g.world.free()


func test_the_leaves_slide_in_behind_the_wall_pieces_and_the_posts_stay() -> void:
	var g := Helpers.make(1, 1)
	var gate = _node(g)
	var layer: Node = g.world.layers[4]
	var holder: Node = g.world.segment_holders[2]
	var pallets: Node = g.world.segment_holders[1]
	var bus: Node = g.world.segment_holders[3]
	check(gate.leaves.get_parent() == layer, "the leaves are in the big layer")
	check(gate.leaves.get_index() < pallets.get_index(), "before the pallets, which draw over them")
	check(gate.leaves.get_index() < bus.get_index(), "and before the school bus")
	check(pallets.get_index() < holder.get_index() and holder.get_index() < bus.get_index(), "the posts stay where the gate's picture was: over the pallets' end")
	eq(holder.get_child_count(), 2, "two posts")
	eq(gate.leaves.get_child_count(), 2, "two leaves")
	var post_l: Node2D = holder.get_node("PostL")
	var at := post_l.position
	gate.follow(1.0, 2.0)
	eq(holder.get_child_count(), 2, "the posts do not go when it opens")
	eq(holder.get_node("PostL").position, at, "and do not move")
	# the bridge's planks are before the leaves in the layer: the leaves (the gate's beam over the deck's edge) draw over them
	var bridge_at := -1
	for i in layer.get_child_count():
		var c: Node = layer.get_child(i)
		if c is Sprite2D and String(c.texture.resource_path).ends_with("155_bridge.png"):
			bridge_at = i
	check(bridge_at >= 0, "the bridge's picture is in the big layer")
	check(bridge_at < gate.leaves.get_index(), "before the leaves")
	g.world.free()


func test_the_damage_pictures_follow_the_segment_and_the_wreck_has_no_leaves() -> void:
	var g := Helpers.make(1, 1)
	var gate = _node(g)
	gate.follow(1.0, 2.0)
	for state in [1, 2]:
		g.world.set_segment_state(2, state)
		eq(gate.state, state, "the node knows the state")
		var holder: Node = g.world.segment_holders[2]
		eq(holder.get_child_count(), 2, "posts of state %d" % state)
		eq(gate.leaves.get_child_count(), 2, "leaves of state %d" % state)
		check(String(gate.leaves.get_node("LeafL").texture.resource_path).contains("165_gate_s%d_l" % state), "the left leaf of state %d" % state)
		check(String(holder.get_node("PostR").texture.resource_path).contains("165_gate_s%d_pr" % state), "the right post of state %d" % state)
		# the new pictures are as open as the gate was
		var piece: Dictionary = g.world.segment_states[2][state][0]
		var shut_x := (float(piece.x) + float(GateNode.CUTS[0]) * float(piece.w) / GateNode.SRC_W) * GateNode.TILE
		near(gate.leaves.get_node("LeafL").position.x, shut_x - GateNode.TRAVEL * GateNode.TILE, 0.01, "state %d is as open as the gate is" % state)
	g.world.set_segment_state(2, 3)
	eq(gate.leaves.get_child_count(), 0, "a wrecked gate has no leaves")
	var holder3: Node = g.world.segment_holders[2]
	eq(holder3.get_child_count(), 1, "a heap")
	check(String(holder3.get_child(0).texture.resource_path).contains("165_gate_s3"), "the picture of the wreck")
	g.world.set_segment_state(2, 0)
	eq(gate.leaves.get_child_count(), 2, "and a gate mended has them again")
	g.world.free()


func test_a_node_made_for_a_gate_that_is_already_damaged_draws_that_state() -> void:
	var g := Helpers.make(1, 1)
	for s in g.sim.segments:
		if int(s.id) == 2:
			s.state = 2
	var gate = _node(g)
	eq(gate.state, 2, "it starts from the segment's state")
	check(String(gate.leaves.get_node("LeafR").texture.resource_path).contains("165_gate_s2_r"), "and its picture")
	g.world.free()


func test_the_four_pieces_of_each_gate_picture_make_the_picture_again() -> void:
	for s in [0, 1, 2]:
		var whole := Image.load_from_file(ProjectSettings.globalize_path(OBJECTS + "165_gate_s%d.png" % s))
		var x := 0
		for name in ["pl", "l", "r", "pr"]:
			var part := Image.load_from_file(ProjectSettings.globalize_path(OBJECTS + "165_gate_s%d_%s.png" % [s, name]))
			eq(part.get_height(), whole.get_height(), "piece %s of state %d is as tall" % [name, s])
			var differs := 0
			for yy in range(0, whole.get_height(), 3):
				for xx in range(0, part.get_width(), 3):
					if part.get_pixel(xx, yy) != whole.get_pixel(x + xx, yy):
						differs += 1
			eq(differs, 0, "piece %s of state %d is the picture's own pixels" % [name, s])
			x += part.get_width()
		eq(x, whole.get_width(), "the four pieces of state %d are as wide as the picture" % s)
	eq(GateNode.CUTS[2] < GateNode.SRC_W, true, "the cuts are inside the picture")


# ------------------------------------------------------------------------------------------- the bridge --

func test_the_walkway_is_still_walkable_from_end_to_end_across_the_gate() -> void:
	var g := Helpers.make(1, 1)
	var w = g.world
	for x in range(20, 64):
		check(w.on_deck(float(x) + 0.5, 18.5), "the deck is there at x=%d" % x)
		check(w.solid_p[18 * w.W + x] == 0 and w.solid_z[18 * w.W + x] == 0, "and open at x=%d" % x)
	for x in GATE_COLS:
		check(w.solid_p[19 * w.W + x] != 0 and w.solid_z[19 * w.W + x] != 0, "the rail's row under the bridge stays shut at x=%d (nobody steps off it into the lane)" % x)
	var walk := {}
	for o in g.data.objects:
		if String(o.kind) == "walkway" and float(o.w) > float(o.h):
			walk = o
	near(float(walk.cx), 42.0, 0.0001, "the walkway's own box did not change")
	near(float(walk.w), 44.0, 0.0001, "(width)")
	near(float(walk.h), 1.55, 0.0001, "(depth)")
	w.free()


func test_the_planks_over_the_gate_are_their_own_object_drawn_above_the_cars() -> void:
	var g := Helpers.make(1, 1)
	var bridge := {}
	var walk := {}
	for o in g.data.objects:
		if String(o.kind) == "bridge":
			bridge = o
		if String(o.kind) == "walkway" and float(o.w) > float(o.h):
			walk = o
	check(not bridge.is_empty(), "there is a bridge")
	near(float(bridge.cx) - float(bridge.w) / 2.0, 36.0, 0.0001, "from the gate's west edge")
	near(float(bridge.cx) + float(bridge.w) / 2.0, 42.0, 0.0001, "to its east edge")
	check(int(bridge.layer) > GateNode.Z_CAR, "drawn over the cars (z %d, the cars %d)" % [int(bridge.layer), GateNode.Z_CAR])
	# the walkway's own pieces leave the bridge's span bare
	for p in walk.pieces:
		var x0 := float(p.x)
		var x1 := float(p.x) + float(p.w)
		check(x1 <= 36.01 or x0 >= 41.99 or x1 - x0 < 0.001, "no plank of the walkway over the gate (%s: %.2f to %.2f)" % [String(p.file), x0, x1])
	var covered := 0.0
	for p in walk.pieces:
		covered += float(p.w)
	for p in bridge.pieces:
		covered += float(p.w)
	near(covered, 44.27, 0.05, "the walkway's pieces and the bridge together are as long as the walkway's pictures were (14.75 + 14.76 + 14.76)")
	for p in bridge.pieces:
		var tex: Texture2D = load(String(p.file))
		check(tex != null, "the bridge's picture loads")
		near(float(tex.get_width()) / 96.0, float(p.w), 0.02, "and is laid out at its own size")
	g.world.free()


func test_the_deck_has_no_scaffold_under_the_bridge() -> void:
	var data: Dictionary = Helpers.make(1, 1).data
	var f := DeckFaces.new()
	f.setup(data, ["walkway"])
	var north: Dictionary = f.decks[0]
	eq(north.gaps.size(), 1, "one gap in the north face")
	near(float(north.gaps[0][0]), 36.0, 0.0001, "from the gate's west edge")
	near(float(north.gaps[0][1]), 42.0, 0.0001, "to its east edge")
	near(float(north.x0), 20.0, 0.1, "the deck itself is as long as ever")
	near(float(north.x1), 64.0, 0.1, "(its east end)")
	eq(f.decks[1].gaps.size(), 0, "the west walkway has no gap")
	eq(f.decks[2].gaps.size(), 0, "nor the east one")
	f.free()


# ---------------------------------------------------------------------------------------------- the street --

func test_nothing_stands_in_the_eastbound_lane_or_the_turn_into_the_gate() -> void:
	var g := Helpers.make(1, 1)
	var data: Dictionary = g.data
	var bad: Array = []
	for ob in _obstacles(data):
		var name := String(ob[0])
		if name.begins_with("deck face"):
			continue
		if _overlap(ob[1], _rect_poly(LANE), 0.0):
			bad.append("%s is in the lane" % name)
	eq(bad, [], "things in the lane")
	# no shut tile in the lane's rows
	var w: int = g.world.W
	var shut: Array = []
	for ty in range(9, 13):
		for tx in w:
			if g.world.solid_p[ty * w + tx] != 0 or g.world.solid_z[ty * w + tx] != 0:
				shut.append(Vector2i(tx, ty))
	eq(shut, [], "shut tiles in the lane's rows")
	g.world.free()


func test_the_wrecks_that_stood_in_the_lane_are_still_in_the_street_in_the_north_lane() -> void:
	var g := Helpers.make(1, 1)
	var wrecks := 0
	for o in g.data.objects:
		if String(o.kind) in ["car", "pickup"] and float(o.cy) > 5.0 and float(o.cy) < 9.9 and float(o.cx) > 0.0 and float(o.cx) < 84.0:
			wrecks += 1
	check(wrecks >= 5, "the street still holds its wrecks (%d in the north lane)" % wrecks)
	# the burning car's fire went with it
	var fire := false
	for l in g.data.lights:
		if bool(l.get("fire", false)) and bool(l.get("big", false)):
			fire = fire or (float(l.y) < 9.0 and float(l.x) > 20.0 and float(l.x) < 40.0)
	check(fire, "the burning car's fire burns where the car is")
	g.world.free()


# ---------------------------------------------------------------------------------------------- the apron --

func test_the_apron_is_clear_of_props_and_shut_tiles() -> void:
	var g := Helpers.make(1, 1)
	var pool := _pool()
	var z: Array = pool.zones.apron
	var rect := Rect2(float(z[0]), float(z[1]), float(z[2]) - float(z[0]), float(z[3]) - float(z[1]))
	var w: int = g.world.W
	var shut: Array = []
	for ty in range(ceili(rect.position.y), ceili(rect.end.y)):
		for tx in range(floori(rect.position.x), ceili(rect.end.x)):
			if g.world.solid_p[ty * w + tx] != 0 or g.world.solid_z[ty * w + tx] != 0:
				shut.append(Vector2i(tx, ty))
	eq(shut, [], "shut tiles on the apron (its rows from the first whole one under the deck's foot)")
	var props: Array = []
	for ob in _obstacles(g.data):
		if String(ob[0]).begins_with("deck face"):
			continue
		if _overlap(ob[1], _rect_poly(rect), 0.03):
			props.append(String(ob[0]))
	eq(props, [], "props on the apron")
	for o in g.data.objects:
		check(String(o.kind) != "pickup" or float(o.cy) < 20.0, "no parked pickup left in the yard (object %s)" % str(o.id))
		check(int(o.id) != 115, "the old tyre mark is gone (the apron's ground has them)")
	g.world.free()


func test_the_workbench_keeps_its_place_and_the_apron_has_its_own_ground() -> void:
	var g := Helpers.make(1, 1)
	var found := {}
	for o in g.data.objects:
		match String(o.kind):
			"worktable":
				found["worktable"] = [float(o.cx), float(o.cy)]
			"tarp":
				if float(o.cy) > 20.0:
					found["tarp"] = [float(o.cx), float(o.cy)]
			"generator":
				found["generator"] = [float(o.cx), float(o.cy)]
			"crate":
				if absf(float(o.cx) - 43.0) < 0.1:
					found["crate"] = [float(o.cx), float(o.cy)]
			"apron":
				found["apron"] = o
	eq(found.get("worktable"), [43.9, 25.7], "the worktable has not moved")
	eq(found.get("tarp"), [45.0, 26.7], "nor the tarp")
	eq(found.get("generator"), [46.8, 28.2], "nor the generator")
	eq(found.get("crate"), [43.0, 27.9], "nor the crate")
	check(found.has("apron"), "the apron has a ground picture")
	if found.has("apron"):
		var a: Dictionary = found.apron
		eq(int(a.layer), 1, "on the ground, under the people and the cars")
		var pool := _pool()
		var z: Array = pool.zones.apron
		check(float(a.cx) - float(a.w) / 2.0 <= float(z[0]) and float(a.cx) + float(a.w) / 2.0 >= float(z[2]), "wide enough for the apron")
		check(float(a.cy) - float(a.h) / 2.0 <= 13.0 and float(a.cy) + float(a.h) / 2.0 >= float(z[3]), "and long enough: from the street's kerb to the aisle's end")
		for p in a.pieces:
			check(load(String(p.file)) != null, "its picture loads")
	g.world.free()


# ----------------------------------------------------------------------------------------- the segment --

func test_the_gate_segment_is_what_it_was_for_the_rules() -> void:
	var g := Helpers.make(1, 1)
	var sim = g.sim
	var seg = null
	for s in sim.segments:
		if int(s.id) == 2:
			seg = s
	check(seg != null, "the Main gate is segment 2")
	eq(String(seg.kind), "gate", "a gate")
	eq(String(seg.name), "Main gate", "its name")
	near(float(seg.max_hp), 220.0, 0.0001, "220 hp")
	near(float(seg.hp), 220.0, 0.0001, "whole")
	near(float(seg.from), 36.0, 0.0001, "from x 36")
	near(float(seg.to), 42.0, 0.0001, "to x 42")
	eq(seg.tiles.size(), 18, "its eighteen tiles")
	for i in seg.tiles:
		eq(int(g.world.solid_z[int(i)]), 1, "tile %d is shut to the dead" % int(i))
		eq(int(g.world.solid_p[int(i)]), 1, "and to people (until a lot is claimed: lots.gd opens it for them)")
	var gate_obj = seg.obj
	eq(int(gate_obj.id), 165, "its object")
	eq(gate_obj.states.size(), 4, "with four damage pictures")
	g.world.free()
