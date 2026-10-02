extends "res://tests/case.gd"
## Round 15 (R15.3): the car as a living thing (scripts/render/vehicle_actor.gd, run by scripts/render/parking_node.gd).
## What is looked at here is only what the player sees, and it is a pure function of the saved state: where a vehicle
## stands or drives (the party's state and fields, the route of the motor pool), which way its picture is turned, how far
## each door is open, the layer it is drawn on at the gate, the gate's demand, and the sounds that go with it. The rules are
## the fleet's (tests/test_trips_by_car.gd); the route's geometry is the convoy's.

const Helpers := preload("res://tests/helpers.gd")
const Vehicles := preload("res://scripts/sim/vehicles.gd")
const Actor := preload("res://scripts/render/vehicle_actor.gd")
const ParkingNode := preload("res://scripts/render/parking_node.gd")
const Tut := preload("res://tests/tutorial_kit.gd")

const FIXTURE := "user://test_vehicle_actor_kinds.json"
const CONVOY_PATH := "res://scripts/sim/convoy.gd"

## The kinds as the data will have them (art, nose, doors), with doors of the test's own numbers.
const KINDS := {
	"version": 1,
	"kinds": {
		"sedan": {"name": "Sedan", "seats": 3, "speed": 2.4, "burn": 3.0, "cargo": 1.2, "hp": 70, "art": "174_car_s0", "w": 2.2, "h": 4.4, "nose": "S",
			"doors": [
				{"id": "L1", "side": "L", "seats": [0], "panel": [10, 150, 40, 140], "hinge": [30, 150], "open_deg": 60},
				{"id": "R1", "side": "R", "seats": [1, 2], "panel": [240, 150, 40, 140], "hinge": [260, 150], "open_deg": -60},
			]},
		"pickup": {"name": "Pickup", "seats": 2, "speed": 2.2, "burn": 3.5, "cargo": 1.7, "hp": 90, "art": "116_pickup", "w": 2.2, "h": 4.15, "nose": "N",
			"doors": [{"id": "L1", "side": "L", "seats": [0], "panel": [40, 150, 30, 100], "hinge": [50, 150], "open_deg": -60}]},
		"van": {"name": "Van", "seats": 4, "speed": 2.2, "burn": 4.0, "cargo": 1.5, "hp": 80, "art": "207_pickup", "w": 2.2, "h": 4.07, "nose": "E",
			"doors": [{"id": "L1", "side": "L", "seats": [0], "panel": [270, 40, 100, 30], "hinge": [370, 50], "open_deg": -60}]},
		"bus": {"name": "Bus", "seats": 6, "speed": 1.8, "burn": 6.0, "cargo": 1.4, "hp": 100, "art": "175_bus_s0", "w": 2.6, "h": 8.07, "nose": "S",
			"doors": []},
	},
}


class FakeSound:
	extends RefCounted
	var streams := {"car_door_open": [1], "car_door_close": [1], "car_engine_start": [1], "car_gate_motor": [1]}
	var played: Array = []

	func play(sound_name: String, level: float = 1.0, _pitch_var: float = 0.04, _pitch: float = 1.0) -> void:
		played.append([sound_name, level])

	func names() -> Array:
		var out: Array = []
		for e in played:
			out.append(e[0])
		return out


class FakeGate:
	extends RefCounted
	var calls: Array = []

	func follow(target: float, dt: float) -> void:
		calls.append([target, dt])

	func last() -> float:
		return float(calls[calls.size() - 1][0]) if not calls.is_empty() else -1.0


class FakeFx:
	extends RefCounted
	var puffs := 0

	func smoke(_x: float, _y: float, _size: float, _dark: bool) -> void:
		puffs += 1


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## The convoy the view uses (scripts/sim/convoy.gd, over the real motor pool).
func _convoy():
	return load(CONVOY_PATH)


## A settlement game on the test's kinds.
func _game() -> Dictionary:
	_write(FIXTURE, KINDS)
	var was := Vehicles.data_path
	Vehicles.data_path = FIXTURE
	Vehicles._cache.erase(FIXTURE)
	var g := Helpers.make(7, 1, 3)
	Vehicles.data_path = was
	g.sim.waves.enabled = false
	g.sim.zombies.clear()
	return g


func _node(sim, extras: Dictionary = {}) -> Node2D:
	var node := ParkingNode.new()
	node.convoy = _convoy()
	if extras.has("sound"):
		node.sound = extras.sound
		node.vol_at = func(_x, _y): return 0.5
	if extras.has("fx"):
		node.fx = extras.fx
	Engine.get_main_loop().root.add_child(node)
	node.setup(sim)
	return node


## A party that holds the vehicle `id`, in a state, with these fields over it (the sim's own fields, as saved).
func _party(sim, id: String, state: String, extra: Dictionary = {}) -> Dictionary:
	var party := {"kind": "party", "n": 1, "members": [], "site": "houses", "state": state, "action": "loot", "return_at": 99999.0,
		"result": {}, "depart": 0.0, "vehicle": id, "doors": []}
	party.merge(extra, true)
	sim.scavenge.parties.append(party)
	sim.vehicles.vehicle(id)["state"] = "out"
	return party


func _add(sim, kind: String, spot: int = -1) -> String:
	var v: Dictionary = sim.vehicles.add(kind)
	if spot >= 0:
		v["spot"] = spot
	return String(v.id)


## A vehicle of the fleet that has no place of the motor pool (an old save): the view finds it one.
func _add_plain(sim, kind: String) -> String:
	var v: Dictionary = sim.vehicles.add(kind)
	v.erase("spot")
	return String(v.id)


func near_zero(v: float) -> bool:
	return absf(v) < 0.0001


func _nose_angle(nose: String) -> float:
	return {"N": -PI / 2.0, "S": PI / 2.0, "E": 0.0, "W": PI}[nose]


## Which way the picture's nose points on the screen now: a unit vector.
func _nose_vector(actor, nose: String) -> Vector2:
	return Vector2.from_angle(actor.body.rotation + _nose_angle(nose))


func _free(g: Dictionary, node: Node2D) -> void:
	node.free()
	g.world.free()


# -------------------------------------------------------------------- the pose --

func test_a_parked_vehicle_stands_on_its_spot_nose_to_the_north_whatever_its_picture() -> void:
	var g := _game()
	var sim = g.sim
	var cv = _convoy()
	var node := _node(sim)
	var ids := {}
	var n := 0
	for kind in ["sedan", "pickup", "van", "bus"]:
		ids[kind] = _add(sim, kind, n % cv.spots())
		n += 1
	node.update()
	for kind in ids:
		var id: String = ids[kind]
		var spot: int = int(sim.vehicles.vehicle(id).spot)
		var at: Vector2 = cv.bay(spot)
		var actor = node.actor_of(id)
		check(actor != null and actor.shown, "%s is drawn" % kind)
		near(actor.pose.pos.x, at.x, 0.001, "%s stands on its spot (x)" % kind)
		near(actor.pose.pos.y, at.y, 0.001, "%s stands on its spot (y)" % kind)
		near(_nose_vector(actor, String(KINDS.kinds[kind].nose)).dot(Vector2(0, -1)), 1.0, 0.001, "%s: the picture's nose points north" % kind)
		# feet: the node is at the lower edge of the car, in pixels
		var h: float = float(KINDS.kinds[kind].h)
		near(actor.position.y, (at.y + h / 2.0) * 64.0, 0.01, "%s: its feet are at the lower edge" % kind)
		near(actor.position.x, at.x * 64.0, 0.01, "%s: and in the middle" % kind)
		eq(actor.z_index, 6, "%s: on the layer of the people" % kind)
	_free(g, node)


func test_the_picture_is_as_long_and_as_wide_as_the_data_says_in_the_direction_it_is_turned() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node(sim)
	for kind in ["sedan", "pickup", "van", "bus"]:
		var id := _add(sim, kind, 0)
		node.update()
		var actor = node.actor_of(id)
		var tex: Texture2D = actor.body_sprite.texture
		var drawn: Vector2 = Vector2(tex.get_width(), tex.get_height()) * actor.body.scale
		var nose := String(KINDS.kinds[kind].nose)
		var along: float = drawn.x if nose == "E" else drawn.y
		var across: float = drawn.y if nose == "E" else drawn.x
		near(along, float(KINDS.kinds[kind].h) * 64.0, 0.6, "%s is as long as the data says" % kind)
		near(across, float(KINDS.kinds[kind].w) * 64.0, 0.6, "%s is as wide" % kind)
		sim.vehicles.fleet.clear()
		node.update()
	_free(g, node)


func test_the_pose_follows_the_party_state_for_every_state() -> void:
	var g := _game()
	var sim = g.sim
	var cv = _convoy()
	var node := _node(sim)
	var id := _add(sim, "sedan", 1)
	var spot_at: Vector2 = cv.bay(1)
	node.update()
	check(node.actor_of(id).shown, "parked, no party: drawn")
	# out and unloading: parked on its spot
	var party := _party(sim, id, "out")
	node.update()
	check(node.actor_of(id).shown and node.actor_of(id).pose.pos.is_equal_approx(spot_at), "out: on its spot, the people are walking to it")
	party.state = "unloading"
	node.update()
	check(node.actor_of(id).shown and node.actor_of(id).pose.pos.is_equal_approx(spot_at), "unloading: on its spot")
	# driving out: the convoy's pose of the out route
	var out_route: Array = cv.route(1, "out")
	for p in [0.0, 0.1, 0.35, 0.8, 1.0]:
		party.state = "driving_out"
		party["drive_len"] = 40.0
		party["drive_t"] = 40.0 * p
		node.update()
		var want: Dictionary = cv.pose(out_route, p)
		var a = node.actor_of(id)
		check(a.shown, "driving out at %.2f: drawn" % p)
		check(a.pose.pos.is_equal_approx(want.pos), "driving out at %.2f: at the route's point %s (got %s)" % [p, str(want.pos), str(a.pose.pos)])
		near(wrapf(a.pose.heading - float(want.heading), -PI, PI), 0.0, 0.0001, "driving out at %.2f: the route's heading" % p)
		near(_nose_vector(a, "S").dot(Vector2.from_angle(float(want.heading))), 1.0, 0.001, "driving out at %.2f: the picture's nose points along the heading" % p)
	# driving in: the in route, with its reversing stretch at the end
	var in_route: Array = cv.route(1, "in")
	var saw_reverse := false
	for p in [0.0, 0.5, 0.9, 0.95, 0.99, 1.0]:
		party.state = "driving_in"
		party["drive_len"] = 40.0
		party["drive_t"] = 40.0 * p
		node.update()
		var want: Dictionary = cv.pose(in_route, p)
		var a = node.actor_of(id)
		check(a.pose.pos.is_equal_approx(want.pos), "driving in at %.2f: at the route's point" % p)
		eq(bool(a.pose.reverse), bool(want.reverse), "driving in at %.2f: reversing as the route says" % p)
		saw_reverse = saw_reverse or bool(a.pose.reverse)
		near(_nose_vector(a, "S").dot(Vector2.from_angle(float(want.heading))), 1.0, 0.001, "driving in at %.2f: the nose is along the heading" % p)
	check(saw_reverse, "(the way into the bay is a reversing one)")
	# more than the whole (a late frame): the end of the route, no further
	party["drive_t"] = 55.0
	node.update()
	check(node.actor_of(id).pose.pos.is_equal_approx(cv.pose(in_route, 1.0).pos), "past the end: at the end")
	# away: not drawn; with no party but out: not drawn; parked again: on its spot
	party.state = "away"
	node.update()
	check(not node.actor_of(id).shown and not node.drawn_ids().has(id), "away: not drawn")
	sim.scavenge.parties.clear()
	node.update()
	check(not node.actor_of(id).shown, "out with no party: not drawn")
	sim.vehicles.vehicle(id)["state"] = "parked"
	node.update()
	check(node.actor_of(id).shown and node.actor_of(id).pose.pos.is_equal_approx(spot_at), "home: on its spot again")
	_free(g, node)


func test_a_vehicle_without_a_spot_takes_the_first_free_one_and_keeps_it() -> void:
	var g := _game()
	var sim = g.sim
	var cv = _convoy()
	var node := _node(sim)
	var a := _add_plain(sim, "sedan")
	var b := _add_plain(sim, "van")
	node.update()
	eq(node.spot_of(a), 0, "the first on the first spot")
	eq(node.spot_of(b), 1, "the next on the next")
	sim.vehicles.vehicle(a)["state"] = "out"
	var c := _add_plain(sim, "pickup")
	node.update()
	eq(node.spot_of(c), 2, "a new one does not take the place of one that is out")
	sim.vehicles.vehicle(a)["state"] = "parked"
	node.update()
	eq(node.spot_of(a), 0, "the one that was out has its own place again")
	# a vehicle that has a spot (the fleet's) is where the fleet says
	var d: Dictionary = sim.vehicles.add("bus")
	var last: int = cv.spots() - 1
	d["spot"] = last
	node.update()
	eq(node.spot_of(String(d.id)), last, "the fleet's spot is the spot")
	near(node.actor_of(String(d.id)).pose.pos.y, float(cv.bay(last).y), 0.001, "and the car stands there")
	_free(g, node)


# --------------------------------------------------------------------- the doors --

func test_a_door_opens_in_the_first_third_stays_and_closes_in_the_last() -> void:
	near(Actor.door_amount(0.0, 12.0), 0.0, 0.0001, "shut at the start")
	near(Actor.door_amount(12.0, 12.0), 0.0, 0.0001, "shut at the end")
	near(Actor.door_amount(6.0, 12.0), 1.0, 0.0001, "wide in the middle")
	near(Actor.door_amount(4.0, 12.0), 1.0, 0.0001, "wide from the first third")
	near(Actor.door_amount(8.0, 12.0), 1.0, 0.0001, "and until the last third")
	near(Actor.door_amount(2.0, 12.0), 0.5, 0.0001, "half way open half way through the first third (an ease)")
	near(Actor.door_amount(10.0, 12.0), 0.5, 0.0001, "and half way shut in the last")
	var prev := -1.0
	for i in 21:
		var a := Actor.door_amount(float(i) * 0.2, 12.0)
		if i <= 20:
			check(a >= prev - 0.0001 or i > 10, "it only opens in the first half")
		prev = a
	near(Actor.door_amount(-1.0, 12.0), 0.0, 0.0001, "before the start: shut")
	near(Actor.door_amount(20.0, 12.0), 0.0, 0.0001, "after the end: shut")
	near(Actor.door_amount(3.0, 0.0), 0.0, 0.0001, "no time at all: nothing")


func test_the_doors_swing_about_their_hinges_by_the_party_doors_time() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node(sim)
	var id := _add(sim, "sedan", 0)
	var party := _party(sim, id, "out", {"doors": [{"pid": "dez", "door": "L1", "t": 0.0, "dur": 12.0, "dir": "in"}]})
	node.update()
	var a = node.actor_of(id)
	eq(a.door_ids(), ["L1", "R1"], "the sedan has its two doors")
	near(a.door_angle("L1"), 0.0, 0.0001, "t = 0: shut")
	near(a.door_angle("R1"), 0.0, 0.0001, "the other is shut")
	party.doors[0].t = 2.0
	node.update()
	near(a.door_angle("L1"), deg_to_rad(60.0) * 0.5, 0.0001, "a sixth of the way: half open, clockwise by the data's sign")
	party.doors[0].t = 6.0
	node.update()
	near(a.door_angle("L1"), deg_to_rad(60.0), 0.0001, "the middle: wide (60 degrees)")
	near(a.door_angle("R1"), 0.0, 0.0001, "the door nobody uses stays shut")
	party.doors[0].t = 12.0
	node.update()
	near(a.door_angle("L1"), 0.0, 0.0001, "the end: shut again")
	# the other door swings the other way (its open_deg is negative)
	party.doors = [{"pid": "ruth", "door": "R1", "t": 6.0, "dur": 12.0, "dir": "out"}]
	node.update()
	near(a.door_angle("R1"), deg_to_rad(-60.0), 0.0001, "the right door swings the other way")
	near(a.door_angle("L1"), 0.0, 0.0001, "and the left is shut")
	# two people at one door: the wider of the two
	party.doors = [{"pid": "a", "door": "R1", "t": 6.0, "dur": 12.0, "dir": "in"}, {"pid": "b", "door": "R1", "t": 1.0, "dur": 12.0, "dir": "in"}]
	node.update()
	near(a.door_angle("R1"), deg_to_rad(-60.0), 0.0001, "two at a door: the wider")
	# a door the data does not have is nothing
	party.doors = [{"pid": "a", "door": "XX", "t": 6.0, "dur": 12.0, "dir": "in"}]
	node.update()
	near(a.door_angle("L1"), 0.0, 0.0001, "an unknown door moves nothing")
	# while driving: every door shut, whatever the list says
	party.state = "driving_out"
	party["drive_len"] = 30.0
	party["drive_t"] = 5.0
	party.doors = [{"pid": "a", "door": "L1", "t": 6.0, "dur": 12.0, "dir": "in"}]
	node.update()
	near(a.door_angle("L1"), 0.0, 0.0001, "driving: the doors are shut")
	_free(g, node)


func test_the_hinge_is_the_point_the_panel_turns_about() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node(sim)
	var id := _add(sim, "sedan", 0)
	node.update()
	var a = node.actor_of(id)
	var tex: Texture2D = a.body_sprite.texture
	var size := Vector2(tex.get_width(), tex.get_height())
	# the door's node sits at the hinge (the picture's pixels from its middle) and its panel hangs from there
	var door: Dictionary = a.door_parts("L1")
	check(not door.is_empty(), "the door has its parts")
	check(door.pivot.position.is_equal_approx(Vector2(30.0, 150.0) - size / 2.0), "the pivot is at the hinge: %s" % str(door.pivot.position))
	check(door.sprite.offset.is_equal_approx(Vector2(-30.0, -150.0)) and not door.sprite.centered, "and the panel's picture hangs from it (its top left is the hinge back)")
	_free(g, node)


func test_a_vehicle_with_all_its_doors_shut_is_drawn_with_the_original_picture() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node(sim)
	var id := _add(sim, "sedan", 0)
	node.update()
	var a = node.actor_of(id)
	check(a.showing_original(), "parked and shut: the original picture")
	check(String(a.body_sprite.texture.resource_path).ends_with("174_car_s0.png"), "(the picture of its kind: %s)" % a.body_sprite.texture.resource_path)
	for pid in a.door_ids():
		check(not a.door_parts(pid).pivot.visible, "the panel of %s is not drawn" % pid)
	var party := _party(sim, id, "out", {"doors": [{"pid": "dez", "door": "L1", "t": 6.0, "dur": 12.0, "dir": "in"}]})
	node.update()
	if ResourceLoader.exists("res://assets/objects/174_car_s0_open.png"):
		check(not a.showing_original(), "a door open: the body with the cabin showing (the _open picture)")
		check(String(a.body_sprite.texture.resource_path).ends_with("174_car_s0_open.png"), "(%s)" % a.body_sprite.texture.resource_path)
		check(a.door_parts("L1").pivot.visible, "and the panel on it")
		check(a.door_parts("R1").pivot.visible and near_zero(a.door_angle("R1")), "(the doors that are shut are on it too, at angle 0: the picture is whole)")
		check(a.door_parts("L1").shadow == null or a.door_parts("L1").shadow.visible, "(the open door has its shadow)")
		check(a.door_parts("R1").shadow == null or not a.door_parts("R1").shadow.visible, "(the shut one has none)")
	else:
		check(a.showing_original(), "(no _open picture yet: the original, with no panels)")
	party.doors.clear()
	node.update()
	check(a.showing_original(), "the door shut again: the original once more")
	# a vehicle that is driving has all its doors shut
	party.state = "driving_out"
	party["drive_len"] = 30.0
	party["drive_t"] = 10.0
	node.update()
	check(a.showing_original(), "driving: the original")
	_free(g, node)


func test_the_art_of_every_kind_has_its_open_body_and_its_panels() -> void:
	# the real data: where the data has doors, the pictures are there to match
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicles.json"))
	var kinds: Dictionary = raw.kinds
	for kind in kinds:
		var k: Dictionary = kinds[kind]
		check(String(k.get("nose", "")) in ["N", "S", "E"], "%s: the data says which way its picture's nose points: '%s'" % [kind, str(k.get("nose", ""))])
		var doors: Array = k.get("doors", [])
		check(not doors.is_empty(), "%s has doors in the data" % kind)
		if doors.is_empty():
			continue
		check(ResourceLoader.exists("res://assets/objects/%s_open.png" % String(k.art)), "%s: the body with the doors out exists" % kind)
		for d in doors:
			check(ResourceLoader.exists("res://assets/objects/%s_door_%s.png" % [String(k.art), String(d.id)]), "%s: the panel of door %s exists" % [kind, String(d.id)])


func test_a_kind_with_no_doors_data_is_drawn_whole_and_nothing_moves() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node(sim)
	var id := _add(sim, "bus", 0)
	var party := _party(sim, id, "out", {"doors": [{"pid": "dez", "door": "L1", "t": 6.0, "dur": 12.0, "dir": "in"}]})
	node.update()
	var a = node.actor_of(id)
	eq(a.door_ids(), [], "the bus has no doors in the data")
	check(a.showing_original(), "and is drawn with the original, whatever the party says")
	_free(g, node)


# -------------------------------------------------------------------- the gate z --

func test_a_vehicle_in_the_gate_is_drawn_under_the_bridge_and_above_the_ground() -> void:
	var g := _game()
	var sim = g.sim
	var cv = _convoy()
	var node := _node(sim)
	var id := _add(sim, "sedan", 0)
	var party := _party(sim, id, "driving_out", {"drive_len": 40.0, "drive_t": 0.0})
	var zone: Rect2 = Actor.gate_zone()
	var z_car: int = Actor.gate_z()
	check(zone.size.x > 3.0 and zone.size.y > 3.0, "the gate's zone is a box of tiles: %s" % str(zone))
	check(z_car < 6 and z_car > 0, "the car's layer is under the people's (6) and over the ground: %d" % z_car)
	var route: Array = cv.route(0, "out")
	var inside := 0
	var outside := 0
	for i in 41:
		party["drive_t"] = float(i)
		node.update()
		var a = node.actor_of(id)
		var centre: Vector2 = a.pose.pos
		if a.rect().intersects(zone):
			inside += 1
			eq(a.z_index, z_car, "in the gate at %s: the car's layer" % str(centre))
			check(not a.z_as_relative, "(absolute: the people's node is not added to it)")
		else:
			outside += 1
			eq(a.z_index, 6, "out of the gate at %s: the people's layer" % str(centre))
	check(inside > 3 and outside > 3, "the drive crosses the zone (%d in, %d out)" % [inside, outside])
	# parked at its spot: not in the zone, the people's layer
	sim.scavenge.parties.clear()
	sim.vehicles.vehicle(id)["state"] = "parked"
	node.update()
	eq(node.actor_of(id).z_index, 6, "parked: the people's layer")
	_free(g, node)


# ------------------------------------------------------------------ gate demand --

func test_the_gate_wants_to_open_for_a_car_that_is_about_to_pass_it_and_for_nothing_else() -> void:
	var g := _game()
	var sim = g.sim
	var cv = _convoy()
	var node := _node(sim)
	var id := _add(sim, "sedan", 0)
	node.update()
	near(node.gate_demand(), 0.0, 0.0001, "a car parked: shut")
	var party := _party(sim, id, "out", {"doors": [{"pid": "dez", "door": "L1", "t": 6.0, "dur": 12.0, "dir": "in"}]})
	node.update()
	near(node.gate_demand(), 0.0, 0.0001, "people boarding: shut")
	party.state = "driving_out"
	party["drive_len"] = 100.0
	var out_route: Array = cv.route(0, "out")
	var len: float = cv.length(out_route)
	# along the way out, find where the car's centre crosses the line of the gate (y 17)
	var cross := -1.0
	for i in 1001:
		var p := float(i) / 1000.0
		if float(cv.pose(out_route, p).pos.y) <= Actor.GATE_LINE_Y:
			cross = p
			break
	check(cross > 0.0, "(the route crosses the gate's line)")
	var states := {}
	for p_dist in [0.0, 1.0, 3.0]:
		# the start of the drive: the bay is more than a car's length from the line, the gate waits
		party["drive_t"] = p_dist
		node.update()
	# far before the line: shut; near before: open; just after: open; well after: shut
	var before_far: float = clampf(cross - 20.0 / len, 0.0, 1.0)
	var before_near: float = cross - 3.0 / len
	var after_near: float = cross + 2.0 / len
	var after_far: float = clampf(cross + 14.0 / len, 0.0, 1.0)
	for case in [[before_near, 1.0, "3 tiles before the line"], [cross, 1.0, "at the line"],
			[after_near, 1.0, "2 tiles past the line"], [after_far, 0.0, "14 tiles past the line (the lane)"], [1.0, 0.0, "off the map"]]:
		party["drive_t"] = 100.0 * float(case[0])
		node.update()
		near(node.gate_demand(), float(case[1]), 0.0001, "driving out, %s" % case[2])
	# arriving: along the lane, east, not through the gate: shut; then turning in: open; backing into the bay: shut
	party.state = "driving_in"
	var in_route: Array = cv.route(0, "in")
	var in_len: float = cv.length(in_route)
	var in_cross := -1.0
	for i in 1001:
		var p := float(i) / 1000.0
		if float(cv.pose(in_route, p).pos.y) >= Actor.GATE_LINE_Y:
			in_cross = p
			break
	check(in_cross > 0.0, "(the way in crosses the line)")
	party["drive_t"] = 100.0 * 0.05
	node.update()
	near(node.gate_demand(), 0.0, 0.0001, "driving in, still on the lane far from the gate: shut")
	party["drive_t"] = 100.0 * (in_cross - 2.0 / in_len)
	node.update()
	near(node.gate_demand(), 1.0, 0.0001, "driving in, 2 tiles before the line: open")
	party["drive_t"] = 100.0 * 1.0
	node.update()
	near(node.gate_demand(), 0.0, 0.0001, "in the bay: shut")
	party.state = "unloading"
	node.update()
	near(node.gate_demand(), 0.0, 0.0001, "unloading: shut")
	# gone
	party.state = "away"
	node.update()
	near(node.gate_demand(), 0.0, 0.0001, "away: shut")
	_free(g, node)


func test_the_gate_opens_for_a_party_on_foot_that_is_close_to_it() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node(sim)
	node.update()
	near(node.gate_demand(), 0.0, 0.0001, "nobody: shut")
	var gate: Vector2 = sim.scavenge.gate_center()
	var p = sim.people[0]
	var party := {"kind": "party", "n": 1, "members": [p.id], "site": "houses", "state": "out", "action": "loot", "return_at": 99999.0, "result": {}, "depart": 0.0, "vehicle": ""}
	sim.scavenge.parties.append(party)
	p.x = gate.x
	p.y = gate.y + 8.0
	node.update()
	near(node.gate_demand(), 0.0, 0.0001, "a party on foot 8 tiles off: shut")
	p.y = gate.y + 2.5
	node.update()
	near(node.gate_demand(), 1.0, 0.0001, "2.5 tiles off: open")
	party.state = "away"
	node.update()
	near(node.gate_demand(), 0.0, 0.0001, "away: shut")
	_free(g, node)


func test_the_classic_start_has_no_gate_demand_and_nothing_drawn() -> void:
	var classic := Helpers.make(7, 1, 6)
	classic.sim.vehicles.add("sedan")
	var node := _node(classic.sim)
	node.update()
	eq(node.drawn_ids(), [], "the classic start draws no vehicles")
	eq(node.actor_ids(), [], "and holds no actor")
	near(node.gate_demand(), 0.0, 0.0001, "and wants no gate")
	node.free()
	classic.world.free()
	var tut := Tut.make()
	tut.sim.vehicles.add("sedan")
	var node2 := _node(tut.sim)
	node2.update()
	eq(node2.drawn_ids(), [], "the tutorial draws none")
	node2.free()
	tut.world.free()


# ----------------------------------------------------------- the fleet and the click --

func test_an_actor_is_made_for_each_vehicle_of_the_fleet_and_freed_with_it() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node(sim)
	eq(node.actor_ids(), [], "no fleet, no actors")
	var a := _add(sim, "sedan")
	var b := _add(sim, "pickup")
	node.update()
	var ids: Array = node.actor_ids()
	ids.sort()
	eq(ids, [a, b], "two vehicles, two actors")
	var made: int = node.makes
	node.update()
	eq(node.makes, made, "nothing is made again")
	var actor_a = node.actor_of(a)
	check(is_instance_valid(actor_a) and actor_a.get_parent() != null, "(a is in the tree)")
	# one is out far away: its actor stays, not drawn
	sim.vehicles.vehicle(a)["state"] = "out"
	node.update()
	check(node.actor_ids().has(a) and not node.drawn_ids().has(a), "a vehicle that is out has its actor but is not drawn")
	# lost: its actor is freed
	sim.vehicles.fleet.erase(sim.vehicles.vehicle(a))
	node.update()
	await Engine.get_main_loop().process_frame
	check(not node.actor_ids().has(a), "a vehicle that is lost has no actor")
	check(not is_instance_valid(actor_a), "(and its node is freed)")
	# a new run's first vehicle may have an old one's id and be of another kind: it is drawn as its own
	sim.vehicles.fleet.clear()
	sim.vehicles.fleet.append({"id": b, "kind": "van", "hp": 80.0, "state": "parked"})
	node.update()
	eq(String(node.actor_of(b).kind.id), "van", "the same id with another kind: a new actor of that kind")
	# the settlement game ends (a classic run): all gone
	sim.town.on = false
	node.update()
	await Engine.get_main_loop().process_frame
	eq(node.actor_ids(), [], "no settlement game: no actors")
	_free(g, node)


func test_a_worn_vehicle_is_darker_and_a_nearly_done_one_has_a_spanner() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node(sim)
	var fresh := _add(sim, "van", 0)
	var worn := _add(sim, "pickup", 1)
	var wreck := _add(sim, "sedan", 2)
	sim.vehicles.vehicle(worn)["hp"] = float(sim.vehicles.kind("pickup").hp) * 0.4
	sim.vehicles.vehicle(wreck)["hp"] = float(sim.vehicles.kind("sedan").hp) * 0.1
	node.update()
	eq(node.sprite_of(fresh).modulate, Color.WHITE, "a vehicle in good order is as drawn")
	check(not node.has_spanner(fresh), "with no spanner")
	var tint: Color = node.sprite_of(worn).modulate
	check(tint.r < 1.0 and tint.g < 1.0 and tint.b < 1.0, "a worn one is darker: %s" % str(tint))
	var darker: Color = node.sprite_of(wreck).modulate
	check(darker.r < tint.r, "a worse one more so")
	check(node.has_spanner(wreck) and not node.has_spanner(worn), "and only the nearly done one has the spanner")
	# the doors' panels are as dark as the body
	var door: Dictionary = node.actor_of(wreck).door_parts("L1")
	eq(door.sprite.modulate, darker, "(the panel too)")
	sim.vehicles.vehicle(wreck)["hp"] = float(sim.vehicles.kind("sedan").hp)
	node.update()
	eq(node.sprite_of(wreck).modulate, Color.WHITE, "mended: as drawn again")
	check(not node.has_spanner(wreck), "no spanner")
	_free(g, node)


func test_a_click_finds_the_vehicle_by_the_box_it_takes_where_it_is_now() -> void:
	var g := _game()
	var sim = g.sim
	var cv = _convoy()
	var node := _node(sim)
	var id := _add(sim, "sedan", 0)
	node.update()
	var at: Vector2 = cv.bay(0)
	var r: Rect2 = node.rect_of(id)
	near(r.size.x, 2.2, 0.001, "parked, nose north: as wide as the data says")
	near(r.size.y, 4.4, 0.001, "and as long")
	check(r.get_center().is_equal_approx(at), "round its spot")
	eq(node.vehicle_at(r.get_center()), id, "the middle of it is the vehicle")
	eq(node.vehicle_at(r.position + Vector2(0.1, 0.1)), id, "and its corner")
	eq(node.vehicle_at(r.position - Vector2(0.5, 0.5)), "", "beside it is not")
	eq(node.vehicle_at(Vector2(60.0, 9.0)), "", "the street elsewhere is not")
	# driving east in the lane: the box is long the other way, round where it is
	var party := _party(sim, id, "driving_out", {"drive_len": 100.0, "drive_t": 90.0})
	node.update()
	var a = node.actor_of(id)
	var rd: Rect2 = node.rect_of(id)
	check(rd.size.x > rd.size.y, "driving east: the box lies down: %s" % str(rd.size))
	check(rd.get_center().is_equal_approx(a.pose.pos), "round the car")
	eq(node.vehicle_at(a.pose.pos), id, "a click on it while it drives finds it")
	eq(node.vehicle_at(at), "", "and not where it stood")
	party.state = "away"
	node.update()
	eq(node.vehicle_at(a.pose.pos), "", "away: nothing there")
	eq(node.rect_of(id), Rect2(), "(no box)")
	_free(g, node)


# --------------------------------------------------------------- save and load --

func test_a_save_and_a_load_in_the_middle_of_a_drive_give_the_same_pose() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node(sim)
	var id := _add(sim, "sedan", 1)
	var party := _party(sim, id, "driving_in", {"drive_len": 40.0, "drive_t": 33.0, "members": ["dez"]})
	node.update()
	var before: Dictionary = node.actor_of(id).pose.duplicate(true)
	# through the rules' own save of the parties and the fleet, and through the text a save file is
	var saved_parties: Dictionary = JSON.parse_string(JSON.stringify(sim.scavenge.save()))
	var saved_fleet: Dictionary = JSON.parse_string(JSON.stringify(sim.vehicles.save()))
	var g2 := _game()
	var sim2 = g2.sim
	sim2.scavenge.load_state(saved_parties)
	sim2.vehicles.load_state(saved_fleet)
	var node2 := _node(sim2)
	node2.update()
	var a2 = node2.actor_of(id)
	check(a2 != null and a2.shown, "after the load: the car is drawn")
	if a2 != null:
		check(a2.pose.pos.is_equal_approx(before.pos), "the same place: %s then %s" % [str(before.pos), str(a2.pose.pos)])
		near(wrapf(float(a2.pose.heading) - float(before.heading), -PI, PI), 0.0, 0.0001, "the same heading")
		eq(bool(a2.pose.reverse), bool(before.reverse), "the same reversing")
	# and a door in the middle of its swing
	party.state = "unloading"
	party.doors = [{"pid": "dez", "door": "L1", "t": 3.0, "dur": 12.0, "dir": "out"}]
	node.update()
	var angle: float = node.actor_of(id).door_angle("L1")
	var again: Dictionary = JSON.parse_string(JSON.stringify(sim.scavenge.save()))
	sim2.scavenge.load_state(again)
	sim2.vehicles.load_state(JSON.parse_string(JSON.stringify(sim.vehicles.save())))
	node2.update()
	near(node2.actor_of(id).door_angle("L1"), angle, 0.0001, "a door half open is half open after the load")
	check(absf(angle) > 0.1, "(it was open)")
	node2.free()
	g2.world.free()
	_free(g, node)


# ------------------------------------------------------------------------ sounds --

func test_the_sounds_follow_the_doors_the_engine_and_the_gate_and_skip_what_is_not_there() -> void:
	var g := _game()
	var sim = g.sim
	var sound := FakeSound.new()
	var node := _node(sim, {"sound": sound})
	var id := _add(sim, "sedan", 0)
	var party := _party(sim, id, "out", {"doors": [{"pid": "dez", "door": "L1", "t": 0.0, "dur": 12.0, "dir": "in"}]})
	node.update()
	eq(sound.names(), [], "a car that stands: no sound")
	party.doors[0].t = 2.0
	node.update()
	eq(sound.names(), ["car_door_open"], "the door starts to open: its sound")
	check(float(sound.played[0][1]) > 0.0 and float(sound.played[0][1]) <= 1.0, "at a level")
	party.doors[0].t = 6.0
	node.update()
	party.doors[0].t = 9.0
	node.update()
	eq(sound.names(), ["car_door_open"], "open and swinging back: nothing new")
	party.doors[0].t = 12.0
	node.update()
	eq(sound.names(), ["car_door_open", "car_door_close"], "the door is shut: its sound")
	party.doors.clear()
	party.state = "driving_out"
	party["drive_len"] = 100.0
	party["drive_t"] = 0.5
	node.update()
	eq(sound.names().count("car_engine_start"), 1, "the car starts: the engine")
	party["drive_t"] = 1.5
	node.update()
	eq(sound.names().count("car_engine_start"), 1, "once")
	# (the demand comes as the car leaves the bay now: the leaves need their time before the nose gets there, so the motor
	# has already started with the engine)
	check(sound.names().count("car_gate_motor") <= 1, "the gate's motor starts once as the car pulls out")
	party["drive_t"] = 5.0
	node.update()
	eq(sound.names().count("car_gate_motor"), 1, "the gate's motor as the demand rises: %s" % str(sound.names()))
	party["drive_t"] = 6.0
	node.update()
	eq(sound.names().count("car_gate_motor"), 1, "once")
	# a stream that is not loaded is skipped (no error)
	sound.streams.erase("car_door_open")
	sound.played.clear()
	party.state = "out"
	party.doors = [{"pid": "dez", "door": "L1", "t": 2.0, "dur": 12.0, "dir": "out"}]
	node.update()
	check(not sound.names().has("car_door_open"), "a sound with no stream is not asked for")
	_free(g, node)
	# a car that is already driving when the game loads makes no start-up noise
	var g2 := _game()
	var sound2 := FakeSound.new()
	var node2 := _node(g2.sim, {"sound": sound2})
	var id2 := _add(g2.sim, "sedan", 0)
	_party(g2.sim, id2, "driving_out", {"drive_len": 100.0, "drive_t": 30.0})
	node2.update()
	eq(sound2.names(), [], "a car found mid-drive: no engine start")
	_free(g2, node2)


func test_a_car_pulling_away_raises_a_little_dust() -> void:
	var g := _game()
	var sim = g.sim
	var fx := FakeFx.new()
	var node := _node(sim, {"fx": fx})
	var id := _add(sim, "sedan", 0)
	var party := _party(sim, id, "out", {})
	node.update()
	eq(fx.puffs, 0, "standing: no dust")
	party.state = "driving_out"
	party["drive_len"] = 100.0
	for i in 12:
		party["drive_t"] = 0.4 + float(i) * 0.4
		node.update(0.1)
	check(fx.puffs >= 1, "pulling away: dust (%d)" % fx.puffs)
	var seen: int = fx.puffs
	for i in 12:
		party["drive_t"] = 40.0 + float(i) * 0.4
		node.update(0.1)
	eq(fx.puffs, seen, "far down the road: no more")
	_free(g, node)


# ------------------------------------------------------------ a whole trip, from the real rules --

func test_a_whole_trip_by_car_from_the_real_rules_is_drawn_from_the_doors_to_the_doors() -> void:
	var g := Helpers.make(17, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	sim.minutes = 7.0 * 60.0
	sim.clock_min = 2.0 * 1440.0 + 7.0 * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.supplies.sources_day = 3
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.events.clear()
	sim.vehicles.fuel = 60.0
	var id := String(sim.vehicles.add("sedan").id)
	var sound := FakeSound.new()
	var node := _node(sim, {"sound": sound})
	node.update()
	var cv = _convoy()
	var home: Vector2 = cv.bay(int(sim.vehicles.vehicle(id).spot))
	var crew: Array = [sim.people[0], sim.people[1]]
	check(sim.scavenge.send(crew, "houses", "loot", id), "the party is sent in the sedan")
	var states: Array = []
	var opened := {}
	var drove := false
	var leapt := 0.0
	var gate_open_frames := {"driving_out": 0, "driving_in": 0}
	var last_pos := home
	var was_shown := true
	var shown_away := 0
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < 60000:
		sim.update(1.0 / 30.0)
		node.update(1.0 / 30.0)
		n += 1
		var party: Dictionary = sim.scavenge.parties[0] if not sim.scavenge.parties.is_empty() else {}
		var state := String(party.get("state", "done"))
		if states.is_empty() or states[states.size() - 1] != state:
			states.append(state)
		var a = node.actor_of(id)
		if state == "away":
			if a.shown:
				shown_away += 1
		if a.shown:
			var angle := 0.0
			for did in a.door_ids():
				angle = maxf(angle, absf(a.door_angle(did)))
			if angle > 0.05:
				opened[state] = int(opened.get(state, 0)) + 1
			if state == "driving_out" or state == "driving_in":
				drove = true
				if was_shown:
					leapt = maxf(leapt, a.pose.pos.distance_to(last_pos))
				if node.gate_demand() > 0.5:
					gate_open_frames[state] += 1
			last_pos = a.pose.pos
		was_shown = a.shown
	check(n < 60000, "the trip ended (%d steps)" % n)
	eq(states.slice(0, 6), ["out", "driving_out", "away", "driving_in", "unloading", "done"], "the trip's states, one after another")
	check(int(opened.get("out", 0)) > 20, "the doors opened while they got in (%d frames)" % int(opened.get("out", 0)))
	check(int(opened.get("unloading", 0)) > 20, "and again while they got out (%d frames)" % int(opened.get("unloading", 0)))
	check(not opened.has("driving_out") and not opened.has("driving_in"), "no door was open while the car drove")
	check(drove, "the car drove")
	check(leapt < 1.0, "it never leapt more than a tile between two frames (%.2f)" % leapt)
	eq(shown_away, 0, "away: never drawn")
	check(int(gate_open_frames.driving_out) > 10 and int(gate_open_frames.driving_in) > 10, "the gate wanted to open for the way out and the way in: %s" % str(gate_open_frames))
	var actor = node.actor_of(id)
	check(actor != null and actor.shown and actor.pose.pos.is_equal_approx(home), "at the end the car is on its spot")
	check(actor.showing_original(), "with its doors shut: the picture as it is")
	var names: Array = sound.names()
	check(names.count("car_door_open") >= 3, "a door opened for those who got in and out (a door two people use stays open between them) (%d)" % names.count("car_door_open"))
	check(names.count("car_door_close") >= 4, "and shut again (%d)" % names.count("car_door_close"))
	eq(names.count("car_engine_start"), 1, "the engine started once")
	check(names.count("car_gate_motor") >= 2, "the gate's motor ran for the way out and the way in (%d)" % names.count("car_gate_motor"))
	node.free()
	g.world.free()


func test_the_gate_node_is_told_the_demand_every_frame_in_any_game() -> void:
	var g := _game()
	var sim = g.sim
	var cv = _convoy()
	var node := _node(sim)
	var gate := FakeGate.new()
	node.gate = gate
	var id := _add(sim, "sedan", 0)
	node.update(0.05)
	near(gate.last(), 0.0, 0.0001, "a car parked: the gate is told shut")
	near(float(gate.calls[gate.calls.size() - 1][1]), 0.05, 0.0001, "with the frame's seconds")
	var party := _party(sim, id, "driving_out", {"drive_len": 100.0, "drive_t": 6.0})
	node.update(0.05)
	near(gate.last(), 1.0, 0.0001, "a car about to pass: told open")
	party["drive_t"] = 90.0
	node.update(0.05)
	near(gate.last(), 0.0, 0.0001, "gone down the lane: told shut again")
	_free(g, node)
	# the classic start has no vehicles, but a party on foot at the gate still has it open
	var classic := Helpers.make(7, 1, 6)
	var node2 := _node(classic.sim)
	var gate2 := FakeGate.new()
	node2.gate = gate2
	node2.update(0.05)
	near(gate2.last(), 0.0, 0.0001, "the classic start: shut")
	var at: Vector2 = classic.sim.scavenge.gate_center()
	var p = classic.sim.people[0]
	p.x = at.x
	p.y = at.y + 1.5
	classic.sim.scavenge.parties.append({"kind": "party", "n": 1, "members": [p.id], "site": "x", "state": "out", "return_at": 99999.0, "result": {}, "vehicle": ""})
	node2.update(0.05)
	near(gate2.last(), 1.0, 0.0001, "a party on foot at the gate: open, vehicles or not")
	eq(node2.drawn_ids(), [], "(and still no vehicles drawn)")
	node2.free()
	classic.world.free()


func test_the_real_scene_has_the_gate_follow_a_car_and_the_car_pass_under_the_bridge() -> void:
	var main = Tut.start({"difficulty": 1, "seed": 7, "crew": 3}, 1280, 800)
	main.speed = 0    # (the rules wait: only the views are driven)
	await Tut.frames(main, 3)
	check(main.gate_node != null and main.parking_view.gate == main.gate_node, "the vehicle view is told to drive the gate's node")
	near(float(main.gate_node.open), 0.0, 0.001, "the gate is shut with nothing about")
	var sim = main.sim
	var cv = _convoy()
	var id := String(sim.vehicles.add("sedan").id)
	var spot := int(sim.vehicles.vehicle(id).spot)
	# the car on its way out, a little way from the bay: the gate is coming open
	var party := _party(sim, id, "driving_out", {"drive_len": 100.0, "drive_t": 9.0})
	await Tut.frames(main, 70)
	var actor = main.parking_view.actor_of(id)
	check(actor != null and actor.shown, "the car is drawn")
	check(float(main.gate_node.open) > 0.95, "the gate has opened for it: %.2f" % float(main.gate_node.open))
	# in the gate's mouth the car is on the layer under the bridge
	for i in 100:
		party["drive_t"] = 100.0 * float(i) / 99.0
		await Tut.frames(main, 1)
		var inside: bool = actor.rect().intersects(main.gate_node.ZONE)
		if inside:
			eq(actor.z_index, main.gate_node.Z_CAR, "in the gate's zone the car is on the gate's layer (at %s)" % str(actor.pose.pos))
		else:
			eq(actor.z_index, 6, "outside it, the people's layer (at %s)" % str(actor.pose.pos))
	# well down the lane the gate shuts again
	party["drive_t"] = 95.0
	await Tut.frames(main, 70)
	check(float(main.gate_node.open) < 0.05, "and shut again once the car is down the lane: %.2f" % float(main.gate_node.open))
	await Tut.leave(main)


# ------------------------------------------------------------- review fixes: the gate's timing, the layer --

func test_the_gate_has_time_to_open_before_a_car_gets_to_it() -> void:
	# the car drives CAR_SPEED_TPM tiles in a game minute and the game runs min_per_sec game minutes in a real second at speed 1;
	# the gate hears the demand DEMAND_REACH tiles ahead of the nose and takes OPEN_TIME seconds to open (the view feeds it the
	# frame's seconds times the game's speed, so the speeds cancel: one speed is enough)
	var Scavenge = load("res://scripts/sim/scavenge.gd")
	var Gate = load("res://scripts/render/gate_node.gd")
	var g := _game()
	var node := _node(g.sim)
	var tiles_per_second: float = float(Scavenge.CAR_SPEED_TPM) * float(g.sim.min_per_sec)
	var lead: float = float(Actor.DEMAND_REACH) / tiles_per_second
	check(lead >= float(Gate.OPEN_TIME) + 0.2, "the demand comes %.2f s before the nose reaches the gate; the leaves need %.2f s" % [lead, float(Gate.OPEN_TIME)])
	# and the leaves are far enough apart for a car by the time it is there: the gap at the opening's share the lead allows
	var o: float = minf(lead / float(Gate.OPEN_TIME), 1.0)
	var slid: float = float(Gate.TRAVEL) * Gate.ease_of(o)
	check(slid >= 2.2 + 0.2, "each leaf has slid %.2f tiles when the nose arrives (a car is 2.2 wide)" % slid)
	_free(g, node)


func test_the_game_speed_scales_the_gates_seconds_with_the_cars() -> void:
	var Main = load("res://scripts/main.gd")
	eq(Main.gate_rate(0), 1.0, "paused: the gate still moves at its own pace")
	eq(Main.gate_rate(1), 1.0, "speed 1")
	eq(Main.gate_rate(2), 2.0, "speed 2: twice as fast, like the car")
	eq(Main.gate_rate(3), 3.0, "speed 3")


func test_a_car_is_under_the_bridge_as_soon_as_any_part_of_it_is_in_the_gate_zone() -> void:
	var g := _game()
	var sim = g.sim
	var cv = _convoy()
	var node := _node(sim)
	var id := _add(sim, "sedan", 0)
	var party := _party(sim, id, "driving_out", {"drive_len": 400.0, "drive_t": 0.0})
	var zone: Rect2 = Actor.gate_zone()
	var z_car: int = Actor.gate_z()
	var nose_in_while_centre_out := 0
	for i in 401:
		party["drive_t"] = float(i)
		node.update()
		var a = node.actor_of(id)
		var touching: bool = a.rect().intersects(zone)
		eq(a.z_index, z_car if touching else 6, "at %s the box %s %s the zone: the layer follows the box, not the middle" % [str(a.pose.pos), str(a.rect()), "touches" if touching else "is clear of"])
		if touching and not zone.has_point(a.pose.pos):
			nose_in_while_centre_out += 1
	check(nose_in_while_centre_out > 2, "(the drive has frames where only the nose or the tail is in the zone: %d)" % nose_in_while_centre_out)
	_free(g, node)
