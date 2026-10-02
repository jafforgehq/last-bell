extends "res://tests/case.gd"
## The convoy (round 15, scripts/sim/convoy.gd): a route of assets/data/motor_pool.json turned into a smooth path (corners
## rounded by their radius, stretches driven in reverse, hand-set headings), its length, the pose of the car along it, and
## the place where a person stands at a door of a parked car. Exact numbers come from small files of the test's own; the
## real file is only checked for being sound (its `problems` is empty) and for what the others rely on.

const Convoy := preload("res://scripts/sim/convoy.gd")

const FIXTURE := "user://test_convoy_pool.json"
const VEHICLES_FIXTURE := "user://test_convoy_vehicles.json"

## One spot at (10, 20) whose out route is an L (right angle at (10, 0), radius 2) and whose in route is a reversing stretch.
const POOL := {
	"version": 1,
	"spots": [
		{
			"id": 0, "at": [10.0, 20.0],
			"out_route": [{"x": 10.0, "y": 20.0, "r": 0}, {"x": 10.0, "y": 0.0, "r": 2.0}, {"x": 30.0, "y": 0.0, "r": 0}],
			"in_route": [{"x": 30.0, "y": 0.0, "r": 0}, {"x": 10.0, "y": 0.0, "r": 0}, {"x": 10.0, "y": 10.0, "r": 0}, {"x": 10.0, "y": 20.0, "r": 0, "rev": true}],
		},
		{
			"id": 1, "at": [20.0, 20.0],
			"out_route": [{"x": 20.0, "y": 20.0}, {"x": 20.0, "y": 10.0}],
			"in_route": [{"x": 20.0, "y": 10.0}, {"x": 20.0, "y": 20.0}],
		},
	],
}


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## Points Convoy at the test's own pool (and, if given, vehicles file); `done` puts the real ones back.
func _use(pool: Dictionary, vehicles: Dictionary = {}) -> void:
	_write(FIXTURE, pool)
	Convoy.data_path = FIXTURE
	if not vehicles.is_empty():
		_write(VEHICLES_FIXTURE, vehicles)
		Convoy.vehicles_path = VEHICLES_FIXTURE
	Convoy.forget()


func _done() -> void:
	Convoy.data_path = Convoy.DATA_PATH
	Convoy.vehicles_path = Convoy.VEHICLES_PATH
	Convoy.forget()


## The angle between two headings, whichever way round they are written.
func _turn(a: float, b: float) -> float:
	return absf(angle_difference(a, b))


# ------------------------------------------------------------------ the real file --

func test_the_real_motor_pool_is_sound() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(Convoy.DATA_PATH))
	eq(Convoy.problems(raw), [], "assets/data/motor_pool.json")
	check(Convoy.spots() >= 1, "the motor pool has spots: %d" % Convoy.spots())


func test_every_real_route_starts_or_ends_in_its_bay_and_can_be_driven() -> void:
	for spot in Convoy.spots():
		var bay: Vector2 = Convoy.bay(spot)
		for dir in ["out", "in"]:
			var r: Array = Convoy.route(spot, dir)
			check(r.size() >= 2, "spot %d %s: a route of points" % [spot, dir])
			check(Convoy.length(r) > 5.0, "spot %d %s: it goes somewhere (%.1f tiles)" % [spot, dir, Convoy.length(r)])
			var start: Vector2 = Convoy.pose(r, 0.0).pos
			var end: Vector2 = Convoy.pose(r, 1.0).pos
			if dir == "out":
				near(start.distance_to(bay), 0.0, 0.01, "spot %d: the way out starts in the bay" % spot)
				check(end.x > 85.0 or end.x < -3.0, "spot %d: the way out ends off the map (%.1f)" % [spot, end.x])
			else:
				near(end.distance_to(bay), 0.0, 0.01, "spot %d: the way in ends in the bay" % spot)
				check(start.x < -3.0 or start.x > 85.0, "spot %d: the way in starts off the map (%.1f)" % [spot, start.x])
	eq(Convoy.route(-1, "out"), [], "no such spot: no route")
	eq(Convoy.route(Convoy.spots(), "in"), [], "(past the last one too)")


func test_a_car_parks_nose_to_the_north_and_leaves_forward() -> void:
	for spot in Convoy.spots():
		var out: Dictionary = Convoy.pose(Convoy.route(spot, "out"), 0.0)
		near(_turn(float(out.heading), -PI / 2.0), 0.0, 0.05, "spot %d: it sits nose to the north" % spot)
		eq(bool(out.reverse), false, "spot %d: and pulls out forward" % spot)
		var home: Dictionary = Convoy.pose(Convoy.route(spot, "in"), 1.0)
		near(_turn(float(home.heading), -PI / 2.0), 0.0, 0.05, "spot %d: it comes in and ends nose to the north" % spot)
		eq(bool(home.reverse), true, "spot %d: backing into the bay" % spot)


func test_the_headings_along_every_real_route_never_jump() -> void:
	for spot in Convoy.spots():
		for dir in ["out", "in"]:
			var r: Array = Convoy.route(spot, dir)
			var last: Dictionary = Convoy.pose(r, 0.0)
			var worst := 0.0
			var jump := 0.0
			var steps := 600
			for i in range(1, steps + 1):
				var pose: Dictionary = Convoy.pose(r, float(i) / float(steps))
				jump = maxf(jump, last.pos.distance_to(pose.pos))
				worst = maxf(worst, _turn(float(pose.heading), float(last.heading)))
				last = pose
			check(jump < Convoy.length(r) / float(steps) * 1.5 + 0.01, "spot %d %s: the car never leaps (%.3f tiles in one step)" % [spot, dir, jump])
			check(worst < deg_to_rad(25.0), "spot %d %s: the nose turns smoothly (%.1f degrees in one step)" % [spot, dir, rad_to_deg(worst)])


# ------------------------------------------------------------------ the soundness check --

func test_a_pool_with_a_hole_in_it_is_found() -> void:
	var good: Dictionary = POOL.duplicate(true)
	eq(Convoy.problems(good), [], "the test's own pool first")
	check(not Convoy.problems(null).is_empty(), "not an object")
	check(not Convoy.problems({"spots": []}).is_empty(), "no spots")
	var c := good.duplicate(true)
	c.spots[0].erase("out_route")
	check(str(Convoy.problems(c)).contains("out_route"), "a spot without its way out: %s" % str(Convoy.problems(c)))
	c = good.duplicate(true)
	c.spots[0].erase("at")
	check(str(Convoy.problems(c)).contains("at"), "a spot without a place")
	c = good.duplicate(true)
	c.spots[0].in_route = [{"x": 1.0, "y": 1.0}]
	check(str(Convoy.problems(c)).contains("in_route"), "a route of one point")
	c = good.duplicate(true)
	c.spots[0].out_route[1].erase("y")
	check(str(Convoy.problems(c)).contains("out_route"), "a point with no y: %s" % str(Convoy.problems(c)))
	c = good.duplicate(true)
	c.spots[0].out_route[1]["r"] = -1.0
	check(str(Convoy.problems(c)).contains("radius"), "a negative radius: %s" % str(Convoy.problems(c)))
	c = good.duplicate(true)
	c.spots[0].out_route[1]["rev"] = "yes"
	check(str(Convoy.problems(c)).contains("rev"), "rev that is not true or false")
	c = good.duplicate(true)
	c.spots[0].out_route[1]["h"] = "north"
	check(str(Convoy.problems(c)).contains("h"), "a heading that is not a number")
	c = good.duplicate(true)
	c.spots[0].out_route[0]["x"] = 11.0
	check(str(Convoy.problems(c)).contains("bay"), "a way out that does not start in the bay: %s" % str(Convoy.problems(c)))
	c = good.duplicate(true)
	c.spots[0].in_route[3]["y"] = 19.0
	check(str(Convoy.problems(c)).contains("bay"), "a way in that does not end in the bay")
	c = good.duplicate(true)
	c.spots[1]["id"] = 5
	check(str(Convoy.problems(c)).contains("id"), "ids that are not 0, 1, 2 ...")
	c = good.duplicate(true)
	c.spots[0].out_route.insert(1, {"x": 10.0, "y": 20.0})
	check(str(Convoy.problems(c)).contains("twice"), "two points in the same place: %s" % str(Convoy.problems(c)))


# ------------------------------------------------------------------ the smooth path --

func test_a_corner_is_rounded_by_its_radius_and_the_path_gets_shorter() -> void:
	_use(POOL)
	var r: Array = Convoy.route(0, "out")
	eq(r.size(), 3, "the route is the three points of the file")
	# 20 up, 20 across, minus the two tangents of the round (2 each), plus the quarter circle of radius 2
	near(Convoy.length(r), 36.0 + PI, 1e-6, "the length of the rounded path")
	var a: Dictionary = Convoy.pose(r, 0.0)
	near(a.pos.distance_to(Vector2(10.0, 20.0)), 0.0, 1e-6, "it starts in the bay")
	near(_turn(float(a.heading), -PI / 2.0), 0.0, 1e-6, "pointing north")
	var b: Dictionary = Convoy.pose(r, 1.0)
	near(b.pos.distance_to(Vector2(30.0, 0.0)), 0.0, 1e-6, "it ends at the last point")
	near(_turn(float(b.heading), 0.0), 0.0, 1e-6, "pointing east")
	# half way round the corner: the middle of the quarter circle
	var mid: Dictionary = Convoy.pose(r, (18.0 + PI / 2.0) / (36.0 + PI))
	near(mid.pos.distance_to(Vector2(10.0 + 2.0 - 2.0 * cos(PI / 4.0), 2.0 - 2.0 * sin(PI / 4.0))), 0.0, 1e-6, "the middle of the corner: %s" % str(mid.pos))
	near(_turn(float(mid.heading), -PI / 4.0), 0.0, 1e-6, "the nose is half way round")
	eq(bool(mid.reverse), false, "driving forward")
	# the car cuts the corner: it is never at the sharp vertex
	var closest := 1.0e9
	for i in 400:
		closest = minf(closest, Convoy.pose(r, float(i) / 399.0).pos.distance_to(Vector2(10.0, 0.0)))
	check(closest > 0.5, "the car does not go through the sharp corner (%.2f tiles away at the nearest)" % closest)
	_done()


func test_a_corner_too_big_for_its_legs_is_made_smaller_not_broken() -> void:
	# two corners of radius 5 on a leg of 4 tiles: the rounds shrink to fit and the path still joins up
	_use({"version": 1, "spots": [{"id": 0, "at": [0.0, 0.0],
		"out_route": [{"x": 0.0, "y": 0.0}, {"x": 0.0, "y": -10.0, "r": 5.0}, {"x": 4.0, "y": -10.0, "r": 5.0}, {"x": 4.0, "y": -20.0}],
		"in_route": [{"x": 4.0, "y": -20.0}, {"x": 0.0, "y": 0.0}]}]})
	var r: Array = Convoy.route(0, "out")
	var last: Dictionary = Convoy.pose(r, 0.0)
	var jump := 0.0
	for i in range(1, 501):
		var pose: Dictionary = Convoy.pose(r, float(i) / 500.0)
		jump = maxf(jump, pose.pos.distance_to(last.pos))
		last = pose
	check(jump < Convoy.length(r) / 500.0 * 1.5 + 1e-3, "no gap in the path (%.4f)" % jump)
	near(Convoy.pose(r, 1.0).pos.distance_to(Vector2(4.0, -20.0)), 0.0, 1e-6, "and it still ends where it should")
	check(Convoy.length(r) < 10.0 + 4.0 + 10.0, "shorter than the corners of the polyline")
	_done()


func test_a_route_with_no_radius_keeps_its_sharp_corners() -> void:
	_use(POOL)
	var r: Array = Convoy.route(0, "in")
	near(Convoy.length(r), 20.0 + 10.0 + 10.0, 1e-9, "no rounding: the plain sum of the legs")
	_done()


func test_the_pose_is_clamped_to_the_route() -> void:
	_use(POOL)
	var r: Array = Convoy.route(1, "out")
	near(Convoy.pose(r, -3.0).pos.y, 20.0, 1e-9, "before the start: the start")
	near(Convoy.pose(r, 7.0).pos.y, 10.0, 1e-9, "after the end: the end")
	near(Convoy.pose(r, 0.5).pos.y, 15.0, 1e-9, "half way: half way")
	var empty: Dictionary = Convoy.pose([], 0.5)
	eq(empty.pos, Vector2.ZERO, "no route: nowhere")
	near(Convoy.length([]), 0.0, 1e-12, "and no length")
	_done()


# ------------------------------------------------------------------ reversing ---

func test_a_stretch_in_reverse_points_the_nose_the_other_way_and_says_so() -> void:
	# the car sits at (10, 0) nose to the north and backs south 10 tiles, and then drives forward east 10
	_use({"version": 1, "spots": [{"id": 0, "at": [10.0, 0.0],
		"out_route": [{"x": 10.0, "y": 0.0}, {"x": 10.0, "y": 10.0, "rev": true}],
		"in_route": [{"x": 0.0, "y": 0.0}, {"x": 10.0, "y": 0.0}]}]})
	var back: Dictionary = Convoy.pose(Convoy.route(0, "out"), 0.5)
	eq(bool(back.reverse), true, "the leg is in reverse")
	near(back.pos.y, 5.0, 1e-9, "half way down it")
	near(_turn(float(back.heading), -PI / 2.0), 0.0, 1e-6, "moving south, the nose still to the north")
	var fwd: Dictionary = Convoy.pose(Convoy.route(0, "in"), 0.5)
	eq(bool(fwd.reverse), false, "forward again on the other route")
	near(_turn(float(fwd.heading), 0.0), 0.0, 1e-6, "driving east, nose to the east")
	# a reverse that goes on round a rounded corner keeps the nose opposite to the way of travel
	_use({"version": 1, "spots": [{"id": 0, "at": [0.0, 0.0],
		"out_route": [{"x": 0.0, "y": 0.0}, {"x": 0.0, "y": 10.0, "r": 2.0, "rev": true}, {"x": 10.0, "y": 10.0, "rev": true}],
		"in_route": [{"x": 5.0, "y": 0.0}, {"x": 0.0, "y": 0.0}]}]})
	var r: Array = Convoy.route(0, "out")
	var corner: Dictionary = Convoy.pose(r, (8.0 + PI / 2.0) / (16.0 + PI))
	near(_turn(float(corner.heading), 5.0 * PI / 4.0), 0.0, 1e-6, "round the corner the nose is opposite to the way of travel")
	eq(bool(corner.reverse), true, "still in reverse")
	_done()


func test_the_nose_swings_across_the_stop_where_the_car_changes_gear() -> void:
	# south (forward) and then backing away to the east: the nose cannot jump, it swings from south to the west
	_use({"version": 1, "spots": [{"id": 0, "at": [0.0, 0.0],
		"out_route": [{"x": 0.0, "y": 0.0}, {"x": 0.0, "y": 10.0}, {"x": 4.0, "y": 10.0, "rev": true}],
		"in_route": [{"x": 0.0, "y": 10.0}, {"x": 0.0, "y": 0.0}]}]})
	var r: Array = Convoy.route(0, "out")
	var before: Dictionary = Convoy.pose(r, 9.99 / 14.0)
	near(_turn(float(before.heading), PI / 2.0), 0.0, 0.01, "driving south: nose to the south")
	var at_stop: Dictionary = Convoy.pose(r, 10.0 / 14.0)
	near(_turn(float(at_stop.heading), PI / 2.0), 0.0, 0.01, "stopped: still to the south")
	var half: Dictionary = Convoy.pose(r, 12.0 / 14.0)
	near(_turn(float(half.heading), 3.0 * PI / 4.0), 0.0, 0.01, "half way through the swing: south-west")
	eq(bool(half.reverse), true, "in reverse")
	var end: Dictionary = Convoy.pose(r, 1.0)
	near(_turn(float(end.heading), PI), 0.0, 0.01, "backing east: the nose to the west")
	_done()


# ------------------------------------------------------------------ the set headings ---

func test_a_point_with_a_heading_pulls_the_nose_round_to_it_and_back() -> void:
	_use({"version": 1, "spots": [{"id": 0, "at": [0.0, 0.0],
		"out_route": [{"x": 0.0, "y": 0.0}, {"x": 10.0, "y": 0.0, "h": 90.0}, {"x": 20.0, "y": 0.0}],
		"in_route": [{"x": 1.0, "y": 0.0}, {"x": 0.0, "y": 0.0}]}]})
	var r: Array = Convoy.route(0, "out")
	near(_turn(float(Convoy.pose(r, 0.0).heading), 0.0), 0.0, 1e-9, "east at the start (no heading: the way it is going)")
	near(_turn(float(Convoy.pose(r, 0.25).heading), PI / 4.0), 0.0, 1e-9, "half way to the set point: half way round")
	near(_turn(float(Convoy.pose(r, 0.5).heading), PI / 2.0), 0.0, 1e-9, "at the set point: the set heading (90 degrees: south)")
	near(_turn(float(Convoy.pose(r, 0.75).heading), PI / 4.0), 0.0, 1e-9, "and back")
	near(_turn(float(Convoy.pose(r, 1.0).heading), 0.0), 0.0, 1e-9, "east again at the end")
	_done()


func test_headings_are_unwrapped_so_350_to_10_is_a_small_turn() -> void:
	_use({"version": 1, "spots": [{"id": 0, "at": [0.0, 0.0],
		"out_route": [{"x": 0.0, "y": 0.0, "h": 350.0}, {"x": 10.0, "y": 0.0, "h": 10.0}],
		"in_route": [{"x": 1.0, "y": 0.0}, {"x": 0.0, "y": 0.0}]}]})
	var r: Array = Convoy.route(0, "out")
	near(_turn(float(Convoy.pose(r, 0.5).heading), 0.0), 0.0, 1e-9, "half way between 350 and 10 is 0, not 180")
	near(_turn(float(Convoy.pose(r, 0.0).heading), deg_to_rad(350.0)), 0.0, 1e-9, "the first heading")
	near(_turn(float(Convoy.pose(r, 1.0).heading), deg_to_rad(10.0)), 0.0, 1e-9, "the second heading")
	_done()


func test_a_hand_set_swing_in_steps_turns_the_long_way_round_when_the_data_says_so() -> void:
	# 90 (south) to 180 (west) to 270 (north) in three points: a U-turn that goes clockwise as drawn
	_use({"version": 1, "spots": [{"id": 0, "at": [0.0, 0.0],
		"out_route": [{"x": 0.0, "y": 0.0, "h": 90.0}, {"x": 5.0, "y": 0.0, "h": 180.0}, {"x": 10.0, "y": 0.0, "h": 270.0}],
		"in_route": [{"x": 1.0, "y": 0.0}, {"x": 0.0, "y": 0.0}]}]})
	var r: Array = Convoy.route(0, "out")
	near(_turn(float(Convoy.pose(r, 0.25).heading), deg_to_rad(135.0)), 0.0, 1e-9, "a quarter of the way: 135 degrees")
	near(_turn(float(Convoy.pose(r, 0.5).heading), deg_to_rad(180.0)), 0.0, 1e-9, "half way: 180")
	near(_turn(float(Convoy.pose(r, 0.75).heading), deg_to_rad(225.0)), 0.0, 1e-9, "three quarters: 225")
	near(_turn(float(Convoy.pose(r, 1.0).heading), deg_to_rad(270.0)), 0.0, 1e-9, "and the nose to the north")
	_done()


# ------------------------------------------------------------------ the doors ---

## A bay at (10, 20) for a sedan of 2 by 4 tiles (nose to the north): its body spans x 9 to 11, y 18 to 22.
const VEHICLES_NO_DOORS := {"version": 1, "kinds": {
	"sedan": {"name": "Sedan", "seats": 3, "speed": 2.4, "burn": 3.0, "cargo": 1.2, "hp": 70, "art": "174_car_s0", "w": 2.0, "h": 4.0},
	"bus": {"name": "Bus", "seats": 6, "speed": 1.8, "burn": 6.0, "cargo": 1.4, "hp": 100, "art": "175_bus_s0", "w": 2.6, "h": 8.0},
}}


func test_a_door_without_data_stands_a_step_outside_the_body_on_its_side() -> void:
	_use(POOL, VEHICLES_NO_DOORS)
	var l1: Vector2 = Convoy.door_spot(0, "sedan", "L1")
	var r1: Vector2 = Convoy.door_spot(0, "sedan", "R1")
	var l2: Vector2 = Convoy.door_spot(0, "sedan", "L2")
	var r2: Vector2 = Convoy.door_spot(0, "sedan", "R2")
	check(l1.x < 9.0 and l1.x > 7.5, "the left doors are on the west side, outside the body: %s" % str(l1))
	check(r1.x > 11.0 and r1.x < 12.5, "the right doors are on the east side, outside the body: %s" % str(r1))
	near(l1.x, l2.x, 1e-9, "both left doors are on one line")
	near(r1.x, r2.x, 1e-9, "both right doors too")
	near(l1.y, r1.y, 1e-9, "the front doors face each other")
	near(l1.y, 18.0 + 4.0 / 3.0, 1e-4, "the front doors are a third of the way back from the nose")
	near(l2.y, 18.0 + 8.0 / 3.0, 1e-4, "the back doors two thirds")
	var bus: Vector2 = Convoy.door_spot(0, "bus", "F")
	check(bus.x > 10.0 + 1.3 and bus.x < 10.0 + 2.2, "the bus door is on the right: %s" % str(bus))
	check(bus.y < 20.0 - 4.0 + 2.0, "and at the front of it: %s" % str(bus))
	# another spot: the same shape somewhere else
	near(Convoy.door_spot(1, "sedan", "L1").x - l1.x, 10.0, 1e-4, "spot 1 is ten tiles east of spot 0")
	# a kind and a door nobody knows still give a place beside the car, not an error
	var odd: Vector2 = Convoy.door_spot(0, "hovercraft", "R9")
	check(odd.x > 10.0 and odd.distance_to(Vector2(10.0, 20.0)) < 6.0, "an unknown kind: still beside the bay: %s" % str(odd))
	var none: Vector2 = Convoy.door_spot(99, "sedan", "L1")
	check(none.y > 0.0, "a spot that does not exist: somewhere sensible, not an error: %s" % str(none))
	_done()


func test_a_door_with_data_stands_where_its_panel_is() -> void:
	# the picture the sedan really has: panels are given as fractions of it, so that this test does not depend on its size
	var px: Vector2 = (load("res://assets/objects/174_car_s0.png") as Texture2D).get_size()
	var vehicles: Dictionary = VEHICLES_NO_DOORS.duplicate(true)
	vehicles.kinds.sedan["nose"] = "N"
	# nose up: A is a door on the left a quarter of the way down from the nose, B on the right three quarters down
	vehicles.kinds.sedan["doors"] = [
		{"id": "A", "side": "L", "seats": [0], "panel": [0.0, px.y * 0.2, px.x * 0.2, px.y * 0.1], "hinge": [0, px.y * 0.2], "open_deg": -60},
		{"id": "B", "side": "R", "seats": [1, 2], "panel": [px.x * 0.8, px.y * 0.7, px.x * 0.2, px.y * 0.1], "hinge": [px.x, px.y * 0.7], "open_deg": 60},
	]
	_use(POOL, vehicles)
	var a: Vector2 = Convoy.door_spot(0, "sedan", "A")
	var b: Vector2 = Convoy.door_spot(0, "sedan", "B")
	check(a.x < 9.0, "A is on the left: %s" % str(a))
	check(b.x > 11.0, "B is on the right: %s" % str(b))
	near(a.y, 18.0 + 4.0 * 0.25, 1e-6, "A is a quarter of the way from the nose")
	near(b.y, 18.0 + 4.0 * 0.75, 1e-6, "B three quarters")
	# a picture drawn nose to the south has the nose at the bottom: the same panels sit the other way round
	vehicles.kinds.sedan["nose"] = "S"
	_use(POOL, vehicles)
	near(Convoy.door_spot(0, "sedan", "A").y, 18.0 + 4.0 * 0.75, 1e-6, "nose S: A is near the tail")
	near(Convoy.door_spot(0, "sedan", "B").y, 18.0 + 4.0 * 0.25, 1e-6, "nose S: B is near the nose")
	# a picture drawn nose to the east: the length runs along x, the nose is at the right
	vehicles.kinds.sedan["nose"] = "E"
	vehicles.kinds.sedan["doors"] = [{"id": "A", "side": "L", "seats": [0], "panel": [px.x * 0.7, 0.0, px.x * 0.1, px.y * 0.2], "hinge": [px.x * 0.7, 0], "open_deg": -60}]
	_use(POOL, vehicles)
	near(Convoy.door_spot(0, "sedan", "A").y, 18.0 + 4.0 * 0.25, 1e-6, "nose E: a panel centred 75 per cent of the way across is a quarter from the nose")
	_done()
