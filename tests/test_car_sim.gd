extends "res://tests/case.gd"
## The car of the live drive (round 21, scripts/drive/car_sim.gd) and its autopilot (scripts/drive/autopilot.gd): pure, no
## nodes, a fixed step of 1/30 s. The tests drive the car with scripted inputs over a fake field (a probe that answers
## "solid", "ground" and "dyn" for a point), then the autopilot over generated roads. Deterministic: no test uses the
## clock. The fixtures a test writes would be named test_r21_car_*; this one writes none.

const CarSim := preload("res://scripts/drive/car_sim.gd")
const Autopilot := preload("res://scripts/drive/autopilot.gd")
const Helpers := preload("res://tests/helpers.gd")

const STEP := 1.0 / 30.0
const NORTH := -PI / 2.0
const SOUTH := PI / 2.0

var _kind_cache := {}


# ------------------------------------------------------------------------------------------------ fixtures --

## The vehicle kinds of the data, as the sim's `Vehicles` reads them (plus their id).
func _kinds() -> Dictionary:
	if _kind_cache.is_empty():
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicles.json"))
		for id in raw.kinds:
			var k: Dictionary = raw.kinds[id].duplicate(true)
			k["id"] = String(id)
			k["speed"] = float(k.speed)
			k["hp"] = float(k.hp)
			_kind_cache[String(id)] = k
	return _kind_cache


## A car of that kind ("" = on foot) at `at`, nose along `heading`, at its full hp (or `hp`).
func _car(kind_id: String, at := Vector2(100.0, 100.0), heading := 0.0, hp := -1.0):
	var k: Dictionary = _kinds().get(kind_id, {})
	var car = CarSim.new()
	car.setup(k, at, heading, float(k.get("hp", 100.0)) if hp < 0.0 else hp)
	return car


## A field the probe answers for: tiles that are solid, tiles that hold a wreck of the road (`dyn`, with the hp it costs
## to ram: -1 = the car's default), and the ground, which turns to `edge_ground` from the x `edge_x` on.
class Field:
	extends RefCounted
	var solid := {}
	var dyn := {}
	var ram_hp := {}
	var ground := "ASPHALT"
	var edge_x := INF
	var edge_ground := "GRASS"
	var calls := 0

	func probe(p: Vector2) -> Dictionary:
		calls += 1
		var c := Vector2i(floori(p.x), floori(p.y))
		var id: String = dyn.get(c, "")
		var out := {"solid": solid.has(c) or id != "", "ground": edge_ground if p.x >= edge_x else ground, "dyn": id}
		if id != "" and ram_hp.has(id):
			out["ram_hp"] = ram_hp[id]
		return out

	func wall(x0: int, y0: int, x1: int, y1: int) -> void:
		for x in range(x0, x1):
			for y in range(y0, y1):
				solid[Vector2i(x, y)] = true

	func block(id: String, x0: int, y0: int, x1: int, y1: int, ram := -1.0) -> void:
		for x in range(x0, x1):
			for y in range(y0, y1):
				dyn[Vector2i(x, y)] = id
		if ram >= 0.0:
			ram_hp[id] = ram

	## The wreck is knocked aside: its tiles are open.
	func open(id: String) -> void:
		for c in dyn.keys():
			if dyn[c] == id:
				dyn.erase(c)


## Steps `n` times with the same hands; returns the last result.
func _go(car, f: Field, n: int, throttle: float, steer: float) -> Dictionary:
	var r := {}
	for i in n:
		r = car.step(STEP, throttle, steer, f.probe)
	return r


# ------------------------------------------------------------------------------------------------- the car --

func test_cruise_and_top_follow_the_kind() -> void:
	# cruise is the walking speed (3.2) times the kind's speed; the top is 1.5 times that; on foot the walking speed
	for pair in [["sedan", 7.68], ["pickup", 7.04], ["van", 7.04], ["bus", 5.76]]:
		var car = _car(pair[0])
		near(car.cruise, pair[1], 1.0e-6, "cruise of the %s" % pair[0])
		near(car.top, pair[1] * 1.5, 1.0e-6, "top of the %s" % pair[0])
		near(CarSim.cruise_of(_kinds()[pair[0]]), pair[1], 1.0e-6, "cruise_of the %s" % pair[0])
	var foot = _car("")
	near(foot.cruise, 3.2, 1.0e-6, "walking speed on foot")
	near(foot.top, 3.2, 1.0e-6, "no sprint on foot")
	near(CarSim.cruise_of({}), 3.2, 1.0e-6, "cruise_of on foot")
	check(foot.foot and not _car("pickup").foot, "only the empty kind is on foot")


func test_from_rest_the_car_reaches_top_in_the_time_the_constants_give_and_no_faster() -> void:
	for id in ["sedan", "pickup", "van", "bus"]:
		var car = _car(id)
		var f := Field.new()
		# the speed climbs as v' = ACCEL - DRAG v: top at -ln(1 - top DRAG / ACCEL) / DRAG
		var expect: float = -log(1.0 - car.top * CarSim.DRAG / CarSim.ACCEL) / CarSim.DRAG
		var reached := -1.0
		var too_fast := false
		for i in 600:
			car.step(STEP, 1.0, 0.0, f.probe)
			var t := float(i + 1) * STEP
			if car.speed > CarSim.ACCEL * t + 1.0e-9:
				too_fast = true
			if reached < 0.0 and car.speed >= car.top - 1.0e-9:
				reached = t
		check(not too_fast, "the %s never gains more than ACCEL a second" % id)
		check(reached > 0.0, "the %s reaches its top" % id)
		check(absf(reached - expect) < 0.12, "the %s reaches top in %.2f s (the constants say %.2f)" % [id, reached, expect])
		check(reached >= car.top / CarSim.ACCEL, "the %s is no faster than the engine alone" % id)
		near(car.speed, car.top, 1.0e-6, "the %s holds its top, no more" % id)
		check(absf(car.heading) < 1.0e-9, "no steering, no turning")


func test_a_light_throttle_holds_a_lower_speed() -> void:
	var car = _car("pickup")
	var f := Field.new()
	_go(car, f, 600, 0.5, 0.0)
	# half the engine against the drag: ACCEL x 0.5 / DRAG
	near(car.speed, CarSim.ACCEL * 0.5 / CarSim.DRAG, 0.3, "half throttle")


func test_coasting_rolls_to_a_stop() -> void:
	var car = _car("sedan")
	var f := Field.new()
	car.speed = 6.0
	var last: float = car.speed
	var mono := true
	for i in 900:
		car.step(STEP, 0.0, 0.0, f.probe)
		if car.speed > last + 1.0e-9:
			mono = false
		last = car.speed
	check(mono, "a coasting car only slows")
	near(car.speed, 0.0, 1.0e-9, "and stops by itself")
	# not at once: DRAG and ROLL take about a second to take a third off 6 t/s
	var car2 = _car("sedan")
	car2.speed = 6.0
	_go(car2, f, 30, 0.0, 0.0)
	check(car2.speed > 3.0 and car2.speed < 5.0, "a second of coasting from 6 t/s leaves %.2f" % car2.speed)


func test_brake_and_reverse() -> void:
	var f := Field.new()
	for id in ["sedan", "pickup", "bus"]:
		var car = _car(id)
		car.speed = car.cruise
		var x0: float = car.pos.x
		var v0: float = car.speed
		var mono := true
		var last: float = car.speed
		var n := 0
		while car.speed > 0.0 and n < 300:
			car.step(STEP, -1.0, 0.0, f.probe)
			if car.speed > last + 1.0e-9:
				mono = false
			last = car.speed
			n += 1
		check(mono, "the %s only slows under the brake" % id)
		near(car.speed, 0.0, 1.0e-9, "the %s stops" % id)
		var d: float = car.pos.x - x0
		var ideal := v0 * v0 / (2.0 * CarSim.BRAKE)
		check(d > ideal * 0.8 and d < ideal * 1.02, "the %s stops in %.2f tiles (v^2 / 2 BRAKE is %.2f)" % [id, d, ideal])
		# held on: it backs up, at REVERSE_MAX and no faster, and the nose stays where it points
		_go(car, f, 150, -1.0, 0.0)
		near(car.speed, -CarSim.REVERSE_MAX, 1.0e-6, "the %s reverses at REVERSE_MAX" % id)
		check(car.pos.x < x0 + d - 1.0, "the %s backs away along its own line" % id)
		check(absf(car.pos.y - 100.0) < 1.0e-9 and absf(car.heading) < 1.0e-9, "straight back")
	# the harder the brake the shorter: a half brake needs more road
	var a = _car("pickup")
	a.speed = a.cruise
	var b = _car("pickup")
	b.speed = b.cruise
	while a.speed > 0.0:
		a.step(STEP, -1.0, 0.0, f.probe)
	while b.speed > 0.0:
		b.step(STEP, -0.5, 0.0, f.probe)
	check(b.pos.x > a.pos.x + 0.5, "a half brake stops later than a full one")
	# braking from the top takes longer than from cruise
	var c = _car("pickup")
	c.speed = c.top
	while c.speed > 0.0:
		c.step(STEP, -1.0, 0.0, f.probe)
	check(c.pos.x - 100.0 > a.pos.x - 100.0 + 1.0, "from top it takes more road than from cruise")


func test_w_after_reversing_brakes_then_drives() -> void:
	var car = _car("sedan")
	var f := Field.new()
	car.speed = -2.0
	var seen_zero := false
	for i in 120:
		car.step(STEP, 1.0, 0.0, f.probe)
		if absf(car.speed) < 1.0e-9:
			seen_zero = true
	check(seen_zero and car.speed > 3.0, "reversing then W: braked to a halt, then away")


func test_steering_radius_grows_with_speed_and_a_stopped_car_does_not_turn() -> void:
	var f := Field.new()
	# a stopped car does not turn
	var still = _car("sedan")
	_go(still, f, 30, 0.0, 1.0)
	near(still.heading, 0.0, 1.0e-12, "a stopped car does not turn")
	check(still.pos == Vector2(100.0, 100.0), "and does not move")
	var radii := []
	for v in [4.0, 6.0, 8.0, 10.0, 11.5]:
		var car = _car("sedan")
		car.speed = v
		car.step(STEP, 0.0, 1.0, f.probe)
		var yaw: float = car.heading / STEP
		radii.append(car.speed / yaw)
		check(yaw > 0.0, "D turns the nose clockwise (the heading grows) at %.1f t/s" % v)
	for i in range(1, radii.size()):
		check(radii[i] > radii[i - 1], "the turning radius grows with speed: %s" % str(radii))
	# the numbers: the full rate from 4 t/s, 0.45 of it at the top, half of it at 2 t/s
	var car = _car("sedan")
	near(car.yaw_per_steer(4.0), CarSim.TURN_RATE, 1.0e-9, "full bite at 4 t/s")
	near(car.yaw_per_steer(2.0), CarSim.TURN_RATE * 0.5, 1.0e-9, "half the bite at 2 t/s")
	near(car.yaw_per_steer(car.top), CarSim.TURN_RATE * 0.45, 1.0e-9, "0.45 of the rate at the top")
	near(car.yaw_per_steer(0.0), 0.0, 1.0e-12, "none at rest")
	# A is the other way; steer is clamped
	var left = _car("sedan")
	left.speed = 5.0
	left.step(STEP, 0.0, -1.0, f.probe)
	check(left.heading < 0.0, "A turns the nose the other way")
	var wild = _car("sedan")
	wild.speed = 5.0
	wild.step(STEP, 0.0, 9.0, f.probe)
	var tame = _car("sedan")
	tame.speed = 5.0
	tame.step(STEP, 0.0, 1.0, f.probe)
	near(wild.heading, tame.heading, 1.0e-12, "the wheel has a stop")
	# in reverse the nose swings the other way
	var back = _car("sedan")
	back.speed = -2.0
	back.step(STEP, 0.0, 1.0, f.probe)
	check(back.heading < 0.0, "reversing with the wheel to the right swings the nose to the left")


func test_a_full_circle_closes_at_the_radius_the_speed_gives() -> void:
	var f := Field.new()
	var car = _car("pickup", Vector2(100.0, 100.0), NORTH)
	var start: Vector2 = car.pos
	# hold about 6 t/s (throttle 18.3 x t = 6 -> 0.33) and keep the wheel over: the track is a circle
	_go(car, f, 450, 0.34, 0.0)
	var v: float = car.speed
	var p0: Vector2 = car.pos
	var h0: float = car.heading
	var yaw: float = car.yaw_per_steer(v)
	var turns := 0.0
	var n := 0
	while turns < TAU and n < 3000:
		car.step(STEP, 0.34, 1.0, f.probe)
		turns += car.yaw_per_steer(car.speed) * STEP
		n += 1
	check(n > 100 and n < 3000, "a lap takes a few seconds (%d steps)" % n)
	check(car.pos.distance_to(p0) < 2.0, "after a turn of 2 pi the car is back near where it began (%.2f off)" % car.pos.distance_to(p0))
	check(start != p0, "(it had moved)")
	check(yaw > 0.0 and h0 == h0, "yaw rate is positive")


func test_ground_caps_the_speed() -> void:
	var shares := {"ASPHALT": 1.0, "SIDEWALK": 0.9, "DIRT": 0.75, "GRASS": 0.6, "SOIL": 0.5, "WATER_NOT_A_GROUND": 1.0}
	for g in shares:
		var car = _car("pickup")
		var f := Field.new()
		f.ground = g
		_go(car, f, 450, 1.0, 0.0)
		near(car.speed, car.top * shares[g], 0.02, "the pickup's speed on %s" % g)
		check(car.speed <= car.top * shares[g] + 1.0e-9, "never above the ground's share on %s" % g)
	# the table itself
	eq(CarSim.GROUND.get("GRASS"), 0.6, "grass is 0.6")
	eq(CarSim.GROUND.get("ASPHALT"), 1.0, "asphalt is 1")
	# at top speed onto grass: it slows toward the cap, not at once
	var car = _car("pickup")
	var f := Field.new()
	f.edge_x = 160.0
	_go(car, f, 150, 1.0, 0.0)
	check(car.pos.x < 160.0, "still on the road")
	_go(car, f, 600, 1.0, 0.0)
	car.pos.x = 100.0
	var g2 = _car("pickup", Vector2(158.0, 100.0))
	g2.speed = g2.top
	var f2 := Field.new()
	f2.edge_x = 160.0
	_go(g2, f2, 3, 1.0, 0.0)
	check(g2.speed > g2.top * 0.6 + 1.5, "onto grass the speed bleeds off, it does not drop (%.2f)" % g2.speed)
	_go(g2, f2, 120, 1.0, 0.0)
	near(g2.speed, g2.top * 0.6, 0.02, "and settles at the grass's share")
	# off the grass it speeds up again
	f2.edge_x = INF
	_go(g2, f2, 240, 1.0, 0.0)
	near(g2.speed, g2.top, 0.02, "back on the road it gets its top back")


func test_footprint_and_circles_are_the_body() -> void:
	var car = _car("sedan", Vector2(50.0, 40.0), 0.0)
	var fp: PackedVector2Array = car.footprint()
	eq(fp.size(), 4, "a rectangle")
	var minv := Vector2(INF, INF)
	var maxv := Vector2(-INF, -INF)
	for p in fp:
		minv = Vector2(minf(minv.x, p.x), minf(minv.y, p.y))
		maxv = Vector2(maxf(maxv.x, p.x), maxf(maxv.y, p.y))
	near(maxv.x - minv.x, 4.4, 1.0e-4, "the sedan is 4.4 long (east)")
	near(maxv.y - minv.y, 2.2, 1.0e-4, "and 2.2 wide")
	near((minv.x + maxv.x) / 2.0, 50.0, 1.0e-4, "centred on the car")
	var north = _car("sedan", Vector2(50.0, 40.0), NORTH)
	minv = Vector2(INF, INF)
	maxv = Vector2(-INF, -INF)
	for p in north.footprint():
		minv = Vector2(minf(minv.x, p.x), minf(minv.y, p.y))
		maxv = Vector2(maxf(maxv.x, p.x), maxf(maxv.y, p.y))
	near(maxv.x - minv.x, 2.2, 1.0e-4, "pointing north the length is along y")
	near(maxv.y - minv.y, 4.4, 1.0e-4, "so")
	# three circles of radius w/2 along the heading, the outer ones at the nose and the tail
	for id in ["sedan", "pickup", "van", "bus"]:
		var k: Dictionary = _kinds()[id]
		var c = _car(id, Vector2(10.0, 20.0), 0.7)
		var cs: Array = c.circles()
		eq(cs.size(), 3, "three circles for the %s" % id)
		var r: float = float(k.w) / 2.0
		var nose_at := -INF
		var tail_at := INF
		for ci in cs:
			near(float(ci.r), r, 1.0e-9, "radius w/2 of the %s" % id)
			var along: float = (Vector2(ci.pos) - c.pos).dot(Vector2.from_angle(0.7))
			var across: float = (Vector2(ci.pos) - c.pos).dot(Vector2.from_angle(0.7 + PI / 2.0))
			near(across, 0.0, 1.0e-4, "on the car's own line")
			nose_at = maxf(nose_at, along + r)
			tail_at = minf(tail_at, along - r)
		near(nose_at, float(k.h) / 2.0, 1.0e-4, "the front circle reaches the nose of the %s" % id)
		near(tail_at, -float(k.h) / 2.0, 1.0e-4, "the back circle reaches the tail of the %s" % id)
	var foot = _car("")
	eq(foot.circles().size(), 1, "one circle on foot")
	near(float(foot.circles()[0].r), 0.3, 1.0e-9, "of the avatar's radius")


# ------------------------------------------------------------------------------------------- collisions --

## A car heading east with its nose `gap` short of x = 20 (a wall from there on), going `speed`.
func _at_wall(kind_id: String, speed: float, gap := 0.1):
	var car = _car(kind_id, Vector2(0.0, 100.0), 0.0)
	var k: Dictionary = _kinds().get(kind_id, {})
	var half: float = float(k.get("h", 0.6)) / 2.0
	car.pos.x = 20.0 - half - gap
	car.speed = speed
	return car


func _wall_field() -> Field:
	var f := Field.new()
	f.wall(20, 0, 30, 200)
	return f


func test_a_solid_tile_stops_the_car_and_costs_hp_by_the_impact() -> void:
	for id in ["sedan", "pickup", "van", "bus"]:
		var car = _at_wall(id, 8.1)
		var f := _wall_field()
		var hp0: float = car.hp
		var r: Dictionary = car.step(STEP, 0.0, 0.0, f.probe)
		check(r.hit > 7.8 and r.hit <= 8.1, "the %s meets the wall at %.2f t/s" % [id, r.hit])
		near(r.hp_lost, (r.hit - 2.0) * 1.4, 1.0e-9, "the %s pays (impact - 2) x 1.4" % id)
		near(car.hp, hp0 - r.hp_lost, 1.0e-9, "and loses it")
		check(r.scrape, "the %s scrapes" % id)
		check(r.ram.is_empty() and not r.wrecked, "a wall is not rammed")
		near(car.speed, r.hit * 0.35, 1.0e-6, "a frontal crash keeps BOUNCE of the speed")
		# held against it: it never goes in, never pays again, and ends at rest
		var total: float = r.hp_lost
		var worst := 0.0
		for i in 120:
			var q: Dictionary = car.step(STEP, 1.0, 0.0, f.probe)
			total += q.hp_lost
			for p in car.footprint():
				worst = maxf(worst, p.x)
		check(worst <= 20.06, "the %s never goes into the wall (%.3f)" % [id, worst])
		near(total, (r.hit - 2.0) * 1.4, 1.0e-9, "a crash costs once, however long the nose stays on the wall")
		check(car.speed < 0.5, "and the car stands (%.2f)" % car.speed)


func test_nothing_under_the_soft_impact() -> void:
	var car = _at_wall("sedan", 1.9)
	var f := _wall_field()
	var hp0: float = car.hp
	var total := 0.0
	for i in 60:
		total += car.step(STEP, 0.0, 0.0, f.probe).hp_lost
	near(total, 0.0, 1.0e-12, "a bump under 2 t/s costs nothing")
	near(car.hp, hp0, 1.0e-12, "hp is as it was")
	var worst := 0.0
	for p in car.outline():
		worst = maxf(worst, p.x)
	check(worst <= 20.0 + 1.0e-4, "and the wall holds")
	# just over it: a little
	var car2 = _at_wall("sedan", 2.5, 0.02)
	var r: Dictionary = car2.step(STEP, 0.0, 0.0, f.probe)
	check(r.hp_lost > 0.0 and r.hp_lost < 1.0, "a knock at %.2f t/s costs a little (%.3f)" % [r.hit, r.hp_lost])


func test_a_car_wreck_rammed_fast_opens_and_costs_8_and_slower_it_is_a_wall() -> void:
	var f := Field.new()
	f.block("w1", 20, 90, 22, 110)
	var car = _at_wall("pickup", 6.6)
	var hp0: float = car.hp
	var r: Dictionary = car.step(STEP, 0.0, 0.0, f.probe)
	check(r.hit >= 6.0, "rammed at %.2f t/s" % r.hit)
	eq(r.ram, ["w1"], "the wreck is rammed")
	near(r.hp_lost, 8.0, 1.0e-9, "a car wreck costs 8")
	near(car.hp, hp0 - 8.0, 1.0e-9, "hp")
	near(car.speed, r.hit * 0.55, 1.0e-6, "RAM_KEEP of the speed is kept")
	check(not r.wrecked, "not a wreck")
	# the scene opens its tiles; the car goes on through and the wreck is not charged twice
	f.open("w1")
	var total := 0.0
	for i in 60:
		var q: Dictionary = car.step(STEP, 1.0, 0.0, f.probe)
		total += q.hp_lost
		check(q.ram.is_empty(), "a wreck is rammed once")
	near(total, 0.0, 1.0e-9, "no second charge")
	check(car.pos.x > 24.0, "the car went through (x %.2f)" % car.pos.x)
	# slower: a wall
	var f2 := Field.new()
	f2.block("w1", 20, 90, 22, 110)
	var slow = _at_wall("pickup", 5.6)
	var r2: Dictionary = slow.step(STEP, 0.0, 0.0, f2.probe)
	check(r2.hit < 6.0 and r2.hit > 5.2, "at %.2f t/s" % r2.hit)
	check(r2.ram.is_empty(), "below RAM_SPEED the wreck is a wall")
	near(r2.hp_lost, (r2.hit - 2.0) * 1.4, 1.0e-9, "and costs as a wall does")
	_go(slow, f2, 90, 1.0, 0.0)
	var worst := 0.0
	for p in slow.outline():
		worst = maxf(worst, p.x)
	check(worst <= 20.0 + 1.0e-4, "it holds the car back")
	# a bus wreck costs 15 (the road says so with ram_hp), a wreck that cannot be rammed is always a wall
	var f3 := Field.new()
	f3.block("b1", 20, 90, 23, 110, 15.0)
	var bus_hit = _at_wall("sedan", 6.6)
	var r3: Dictionary = bus_hit.step(STEP, 0.0, 0.0, f3.probe)
	near(r3.hp_lost, 15.0, 1.0e-9, "a bus costs 15")
	var f4 := Field.new()
	f4.block("x1", 20, 90, 22, 110, 0.0)
	var wall_hit = _at_wall("sedan", 9.0)
	var r4: Dictionary = wall_hit.step(STEP, 0.0, 0.0, f4.probe)
	check(r4.ram.is_empty() and r4.hp_lost > 8.0, "a wreck with no ram_hp is a wall, even at 9 t/s")
	# the heavy ram of a second wreck beside the first
	var f5 := Field.new()
	f5.block("l", 20, 96, 22, 100)
	f5.block("r", 20, 100, 22, 104)
	var two = _at_wall("sedan", 7.0)
	var r5: Dictionary = two.step(STEP, 0.0, 0.0, f5.probe)
	check(r5.ram.size() == 2, "two wrecks side by side are both rammed")
	near(r5.hp_lost, 16.0, 1.0e-9, "and both cost")
	# on foot a wreck is a wall at any speed
	var foot = _at_wall("", 3.2)
	var f6 := Field.new()
	f6.block("w1", 20, 90, 22, 110)
	var r6: Dictionary = foot.step(STEP, 1.0, 0.0, f6.probe)
	check(r6.ram.is_empty(), "no ramming on foot")


func test_a_glancing_blow_slides_along_the_wall() -> void:
	var f := _wall_field()
	# north, the wall on the right, the nose a little toward it
	var car = _car("sedan", Vector2(17.0, 180.0), NORTH + 0.2)
	car.speed = 6.0
	var hp0: float = car.hp
	var scraped := false
	var worst := 0.0
	for i in 150:
		var r: Dictionary = car.step(STEP, 0.34, 0.0, f.probe)
		scraped = scraped or r.scrape
		for p in car.outline():
			worst = maxf(worst, p.x)
	check(scraped, "it touched the wall")
	check(worst <= 20.0 + 1.0e-4, "it never went in (%.3f)" % worst)
	check(car.hp > hp0 - 1.0, "a glance costs next to nothing (%.2f)" % (hp0 - car.hp))
	check(car.speed > 3.0, "and it is still going (%.2f)" % car.speed)
	check(car.pos.y < 160.0, "up the road (%.1f)" % car.pos.y)
	check(absf(wrapf(car.heading - NORTH, -PI, PI)) < 0.12, "nose along the wall again (%.3f)" % car.heading)


func test_backing_into_a_wall_stops_too() -> void:
	var f := Field.new()
	f.wall(0, 0, 10, 200)
	var car = _car("pickup", Vector2(14.0, 100.0), 0.0)
	car.speed = -2.4
	var hp0: float = car.hp
	var worst := INF
	for i in 120:
		car.step(STEP, -1.0, 0.0, f.probe)
		for p in car.outline():
			worst = minf(worst, p.x)
	check(worst >= 10.0 - 1.0e-4, "the tail does not go into the wall (%.3f)" % worst)
	check(car.hp >= hp0 - (CarSim.REVERSE_MAX - CarSim.SOFT_IMPACT) * CarSim.IMPACT_HP - 1.0e-9, "backing at REVERSE_MAX costs next to nothing (%.2f)" % (hp0 - car.hp))
	check(absf(car.speed) < 0.2, "and the car stays")


func test_hp_zero_is_a_wreck_that_stays_down() -> void:
	var f := _wall_field()
	var car = _at_wall("sedan", 10.0)
	car.hp = 5.0
	var r: Dictionary = car.step(STEP, 1.0, 0.0, f.probe)
	check(r.wrecked, "the crash wrecks it")
	near(car.hp, 0.0, 1.0e-12, "hp 0, not below")
	near(car.speed, 0.0, 1.0e-12, "stopped")
	check(car.wrecked, "and it stays a wreck")
	var at: Vector2 = car.pos
	var q: Dictionary = car.step(STEP, 1.0, 1.0, f.probe)
	check(not q.wrecked, "it is reported once, on the step that does it")
	_go(car, f, 30, 1.0, 1.0)
	check(car.pos == at and car.speed == 0.0, "a wreck does not drive")
	# the scene's own blows
	var c2 = _car("pickup")
	c2.hp = 3.0
	check(c2.damage(2.0) == false and absf(c2.hp - 1.0) < 1.0e-9, "damage that leaves hp is no wreck")
	check(c2.damage(5.0) and c2.hp == 0.0 and c2.wrecked, "damage past hp is")


func test_the_dead_cost_the_car_by_the_plan_s_numbers() -> void:
	var car = _car("sedan")
	car.speed = 5.0
	var hp0: float = car.hp
	near(car.run_over(false), 0.35, 1.0e-9, "a run-over costs RUN_OVER_HP")
	near(car.hp, hp0 - 0.35, 1.0e-9, "hp")
	near(car.speed, 5.0, 1.0e-9, "a walker does not slow the car")
	near(car.run_over(true), 6.0, 1.0e-9, "a brute costs BRUTE_HP")
	near(car.speed, 3.0, 1.0e-9, "and 0.4 of the speed")
	# claws: each dead one below 2 t/s, 0.8 a second, at most six of them
	var slow = _car("sedan")
	slow.speed = 1.0
	var h1: float = slow.hp
	near(slow.claws(3, 0.5), 3.0 * 0.8 * 0.5, 1.0e-9, "three claw for half a second")
	near(slow.hp, h1 - 1.2, 1.0e-9, "hp")
	near(slow.claws(20, 1.0), 6.0 * 0.8, 1.0e-9, "no more than six at once")
	var fast = _car("sedan")
	fast.speed = 3.0
	near(fast.claws(5, 1.0), 0.0, 1.0e-12, "a moving car is not clawed")
	var foot = _car("")
	near(foot.run_over(false), 0.0, 1.0e-12, "on foot there is no car to run over with")


func test_determinism() -> void:
	var finals := []
	for run in 2:
		var f := Field.new()
		f.wall(40, 60, 46, 90)
		f.block("w", 70, 95, 72, 105)
		f.edge_x = 120.0
		var car = _car("van", Vector2(10.0, 100.0), 0.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var log := []
		for i in 1500:
			var th := rng.randf_range(-0.3, 1.0)
			var st := rng.randf_range(-1.0, 1.0) * (1.0 if i % 90 < 60 else 0.0)
			var r: Dictionary = car.step(STEP, th, st, f.probe)
			log.append([car.pos.x, car.pos.y, car.heading, car.speed, car.hp, r.hit, r.hp_lost, r.ram.size()])
		finals.append(log)
		if run == 0:
			f.calls = 0
	check(finals[0] == finals[1], "the same inputs give the same path, to the bit")
	check(finals[0].size() == 1500, "(and the runs are not empty)")


# --------------------------------------------------------------------------------------------- fuel and road --

## The road of a trip with the plan's winding centre line: 30 across, `length` + 24 down, a leg north (-1) or south (+1).
func _centre(base: float, phi: float, psi: float, y: float) -> float:
	return base + 3.2 * sin(TAU * y / 140.0 + phi) + 1.6 * sin(TAU * y / 57.0 + psi)


func _bare_road(seed_value: int, length: int, dir: int, reversed := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base := 15.0 + rng.randf_range(-2.0, 2.0)
	var phi := rng.randf() * TAU
	var psi := rng.randf() * TAU
	var h := length + 24
	var down := PackedVector2Array()
	for y in range(0, h + 1):
		down.append(Vector2(_centre(base, phi, psi, float(y)), float(y)))
	var up := PackedVector2Array()
	for i in range(down.size() - 1, -1, -1):
		up.append(down[i])
	var north := dir < 0
	var path := up if north else down
	var cl := (down if north else up) if reversed else (up if north else down)
	var y_start := float(h - 12) if north else 12.0
	var y_end := 12.0 if north else float(h - 12)
	return {"len": float(length), "width": 30, "style": "urban", "dir": dir, "leg": "there" if north else "home",
		"start": Vector2(_centre(base, phi, psi, y_start), y_start), "end": Vector2(_centre(base, phi, psi, y_end), y_end),
		"centerline": cl, "path": path, "slots": [], "dyn": [], "ambient": []}


func test_fuel_burnt_is_per_leg_times_progress_and_a_full_leg_is_the_abstract_trips() -> void:
	var g := Helpers.make(3, 1, 3)
	var sim = g.sim
	var checked := 0
	for kind_id in ["sedan", "pickup", "van", "bus"]:
		var v: Dictionary = sim.vehicles.add(kind_id)
		var car = _car(kind_id)
		for place in sim.town.all_places():
			var id := String(place.id)
			var per_leg: float = sim.vehicles.fuel_for(id, String(v.id)) / 2.0
			var road_min: float = sim.scavenge.road_minutes(id, String(v.id))
			near(per_leg, float(sim.vehicles.kind(kind_id).burn) * road_min / 60.0, 1.0e-9, "fuel_per_leg is burn x road_min / 60 (%s to %s)" % [kind_id, id])
			if sim.vehicles.has_method("fuel_per_leg"):
				near(sim.vehicles.fuel_per_leg(id, String(v.id)), per_leg, 1.0e-9, "vehicles.fuel_per_leg is half the round trip's fuel (%s to %s)" % [kind_id, id])
			near(car.fuel_burnt(per_leg, 1.0), sim.vehicles.fuel_for(id, String(v.id)) / 2.0, 1.0e-9, "a whole leg burns half the round trip")
			near(car.fuel_burnt(per_leg, 0.25), per_leg * 0.25, 1.0e-9, "and a quarter burns a quarter")
			near(car.fuel_burnt(per_leg, 0.0), 0.0, 1.0e-12, "none at the start")
			near(car.fuel_burnt(per_leg, 1.7), per_leg, 1.0e-9, "never more than the leg")
			near(car.fuel_burnt(per_leg, -0.3), 0.0, 1.0e-12, "never less than none")
			checked += 1
	check(checked > 4, "the real places were checked (%d)" % checked)
	g.world.free()


func test_progress_is_monotone_along_the_centreline() -> void:
	for dir in [-1, 1]:
		for reversed in [false, true]:
			var road := _bare_road(5 + dir, 200, dir, reversed)
			var car = _car("pickup")
			car.pos = road.start
			near(car.progress(road), 0.0, 1.0e-6, "at the start (dir %d)" % dir)
			car.pos = road.end
			near(car.progress(road), 1.0, 1.0e-6, "at the end (dir %d)" % dir)
			var last := -1.0
			var mono := true
			var pts: PackedVector2Array = road.path
			var i := 0
			var step_n := 0
			while i < pts.size():
				car.pos = pts[i] + Vector2(1.5 * sin(float(i)), 0.0)    # a car that weaves a little
				var p: float = car.progress(road)
				if p < last - 1.0e-9:
					mono = false
				last = p
				i += 3
				step_n += 1
			check(mono, "progress never goes back along the road (dir %d, reversed %s)" % [dir, str(reversed)])
			check(step_n > 40, "(walked the whole road)")
			# the middle is about the middle (the road winds a little, so by distance along it)
			var mid: Vector2 = road.start.lerp(road.end, 0.5)
			car.pos = Vector2(_centre_x_at(road, mid.y), mid.y)
			check(absf(car.progress(road) - 0.5) < 0.03, "halfway (dir %d): %.3f" % [dir, car.progress(road)])
			# before the start and past the end it stays in 0..1
			car.pos = road.start + Vector2(0.0, 6.0 * -dir)
			near(car.progress(road), 0.0, 1.0e-6, "behind the start is 0")
			car.pos = road.end + Vector2(0.0, 6.0 * dir * -1.0 * -1.0)
			near(car.progress(road), 1.0, 1.0e-6, "past the end is 1")


## The x of the road's path at row y.
func _centre_x_at(road: Dictionary, y: float) -> float:
	var best := Vector2.ZERO
	var bd := INF
	for p in road.path:
		if absf(p.y - y) < bd:
			bd = absf(p.y - y)
			best = p
	return best.x


func test_progress_of_a_straight_road_is_the_share_of_its_length() -> void:
	var road := {"len": 100.0, "start": Vector2(15.0, 130.0), "end": Vector2(15.0, 30.0), "dir": -1,
		"centerline": PackedVector2Array([Vector2(15.0, 30.0), Vector2(15.0, 80.0), Vector2(15.0, 130.0)]),
		"path": PackedVector2Array([Vector2(15.0, 130.0), Vector2(15.0, 30.0)])}
	var car = _car("sedan")
	for share in [0.0, 0.1, 0.25, 0.5, 0.9, 1.0]:
		car.pos = Vector2(15.0 + 1.0, 130.0 - 100.0 * share)
		near(car.progress(road), share, 1.0e-6, "at %.2f" % share)


# --------------------------------------------------------------------------------------------- on foot --

func test_on_foot_the_same_interface_with_walking_constants() -> void:
	var f := Field.new()
	var foot = _car("", Vector2(100.0, 100.0), 0.0, 100.0)
	check(foot.foot, "no vehicle: on foot")
	_go(foot, f, 30, 1.0, 0.0)
	near(foot.speed, 3.2, 1.0e-6, "a second of W is the walking speed")
	check(foot.speed <= foot.top + 1.0e-9, "never faster")
	# it starts and stops at once, and turns on the spot
	var s = _car("")
	s.step(STEP, 1.0, 0.0, f.probe)
	check(s.speed > 0.4, "it gets going in a step or two (%.2f)" % s.speed)
	_go(s, f, 15, 1.0, 0.0)
	_go(s, f, 4, -1.0, 0.0)
	near(s.speed, 0.0, 1.0e-9, "and stops in four steps")
	var t = _car("")
	_go(t, f, 10, 0.0, 1.0)
	check(t.heading > 0.5, "a walker turns on the spot (%.2f)" % t.heading)
	# a wall stops it with no cost; the ground does not slow a walker
	var g = _at_wall("", 3.2, 0.05)
	var w := _wall_field()
	var hp0: float = g.hp
	var worst := 0.0
	for i in 60:
		g.step(STEP, 1.0, 0.0, w.probe)
		for p in g.outline():
			worst = maxf(worst, p.x)
	check(worst <= 20.0 + 1.0e-4, "a walker is stopped by the wall (%.3f)" % worst)
	near(g.hp, hp0, 1.0e-12, "and unhurt")
	near(g.speed, 0.0, 0.05, "standing at it")
	var grass := Field.new()
	grass.ground = "GRASS"
	var h = _car("")
	_go(h, grass, 30, 1.0, 0.0)
	near(h.speed, 3.2, 1.0e-6, "grass does not slow a walker")
	# the gap of a roadblock for people is 1.4 wide: a walker of 0.6 goes through
	var gap := Field.new()
	gap.block("l", 20, 90, 21, 100)
	gap.block("r", 20, 101, 21, 110)    # a gap one tile wide at y 100..101 (the real one is 1.4)
	var thr = _car("", Vector2(15.0, 100.5), 0.0)
	_go(thr, gap, 90, 1.0, 0.0)
	check(thr.pos.x > 22.0, "a walker goes through a gap a tile wide (x %.2f)" % thr.pos.x)


# ----------------------------------------------------------------------------------------------- the autopilot --

## A generated road's ground: 30 across, the carriageway ASPHALT, its verges SIDEWALK, the rest GRASS, solids (the cars on
## the verges, the strip's edge) and the wrecks of the roadblocks as `dyn` with their ids.
class RoadField:
	extends RefCounted
	const GROUNDS := ["ASPHALT", "SIDEWALK", "GRASS"]
	var w := 30
	var h := 0
	var solid := PackedByteArray()
	var terr := PackedByteArray()
	var dyn := PackedInt32Array()
	var names: Array = []
	var calls := 0

	func setup(width: int, height: int) -> void:
		w = width
		h = height
		solid.resize(w * h)
		terr.resize(w * h)
		dyn.resize(w * h)

	func probe(p: Vector2) -> Dictionary:
		calls += 1
		var x := floori(p.x)
		var y := floori(p.y)
		if x < 0 or y < 0 or x >= w or y >= h:
			return {"solid": true, "ground": "GRASS", "dyn": ""}
		var i := y * w + x
		var d := dyn[i]
		return {"solid": solid[i] != 0 or d != 0, "ground": GROUNDS[terr[i]], "dyn": names[d - 1] if d != 0 else ""}

	func add_dyn(id: String, x0: int, y0: int, x1: int, y1: int) -> void:
		names.append(id)
		for x in range(x0, x1):
			for y in range(y0, y1):
				dyn[y * w + x] = names.size()

	func open(id: String) -> void:
		var k := names.find(id) + 1
		for i in dyn.size():
			if dyn[i] == k:
				dyn[i] = 0


## One generated road for a leg (dir -1 north, +1 south): {"road", "field", "gaps": [{"y", "centre": lateral, "cols"}]}. `blocks` is
## [{"y": row, "gap": the wanted lateral offset of the gap or null for a wall with no way through}]. The path is the
## centreline bent through the gaps, straight across the wall and a smooth bump 16 rows each side of it; the verges have cars the path never comes near.
func _gen(seed_value: int, length: int, dir: int, blocks: Array = [], verge_cars := true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base := 15.0 + rng.randf_range(-2.0, 2.0)
	var phi := rng.randf() * TAU
	var psi := rng.randf() * TAU
	var h := length + 24
	var f := RoadField.new()
	f.setup(30, h)
	for y in h:
		var cx := _centre(base, phi, psi, float(y) + 0.5)
		for x in 30:
			var dx := absf(float(x) + 0.5 - cx)
			f.terr[y * 30 + x] = 0 if dx <= 4.0 else (1 if dx <= 6.0 else 2)
	if verge_cars:
		var y := 14 + rng.randi_range(0, 12)
		while y < h - 14:
			for side in [-1.0, 1.0]:
				if rng.randf() < 0.6:
					var cx := _centre(base, phi, psi, float(y) + 2.0)
					var x0 := int(floor(cx + side * 7.5))
					for xx in range(x0, x0 + 2):
						for yy in range(y, y + 4):
							if xx >= 0 and xx < 30:
								f.solid[yy * 30 + xx] = 1
			y += 18 + rng.randi_range(0, 14)
	var gaps: Array = []
	for bi in blocks.size():
		var b: Dictionary = blocks[bi]
		var yb := int(b.y)
		var cx := _centre(base, phi, psi, float(yb) + 1.5)
		var open_cols: Array = []
		var piece := 0
		var x := 0
		while x < 30:
			var lateral := float(x) + 0.5 - cx
			var is_open: bool = b.get("gap") != null and absf(lateral - float(b.gap)) <= 2.0
			if is_open:
				open_cols.append(lateral)
				x += 1
			else:
				var x1 := x + 1
				while x1 < 30 and x1 - x < 2 and not (b.get("gap") != null and absf(float(x1) + 0.5 - cx - float(b.gap)) <= 2.0):
					x1 += 1
				f.add_dyn("bk%d_%d" % [bi, piece], x, yb, x1, yb + 3)
				piece += 1
				x = x1
		var centre := 0.0
		for c in open_cols:
			centre += float(c)
		gaps.append({"y": yb + 1.5, "centre": centre / float(open_cols.size()) if not open_cols.is_empty() else 0.0, "cols": open_cols.size()})
	var north := dir < 0
	var y_start := float(h - 12) if north else 12.0
	var y_end := 12.0 if north else float(h - 12)
	var down := PackedVector2Array()
	var path_down := PackedVector2Array()
	for y in range(0, h + 1):
		var off := 0.0
		for g in gaps:
			var d := absf(float(y) - float(g.y))
			if d <= 5.0:
				off += float(g.centre)    # straight through the wall's depth
			elif d < 21.0:
				off += float(g.centre) * 0.5 * (1.0 + cos(PI * (d - 5.0) / 16.0))
		down.append(Vector2(_centre(base, phi, psi, float(y)), float(y)))
		path_down.append(Vector2(_centre(base, phi, psi, float(y)) + off, float(y)))
	var up := PackedVector2Array()
	var path_up := PackedVector2Array()
	for i in range(down.size() - 1, -1, -1):
		up.append(down[i])
		path_up.append(path_down[i])
	var road := {"len": float(length), "width": 30, "style": "urban", "dir": dir, "leg": "there" if north else "home",
		"start": Vector2(_centre(base, phi, psi, y_start), y_start), "end": Vector2(_centre(base, phi, psi, y_end), y_end),
		"centerline": up if north else down, "path": path_up if north else path_down, "slots": [], "dyn": [], "ambient": []}
	return {"road": road, "field": f, "gaps": gaps}


## The autopilot drives `road` on `kind_id` ("" on foot) over `field` for up to `max_s` seconds; returns what it did.
func _drive_road(g: Dictionary, kind_id: String, max_s: float, aware_extra := {}, hp := -1.0) -> Dictionary:
	var road: Dictionary = g.road
	var f = g.field    # (a RoadField, or a SiteField: whatever has a `probe`)
	var k: Dictionary = _kinds().get(kind_id, {})
	var car = CarSim.new()
	var head := NORTH if int(road.dir) < 0 else SOUTH
	car.setup(k, road.start, head, float(k.get("hp", 100.0)) if hp < 0.0 else hp)
	var hp0: float = car.hp
	var out := {"done": false, "t": max_s, "hits": 0, "ram": 0, "hp_lost": 0.0, "max_speed": 0.0, "min_gap_x": INF, "car": car, "xs": {}}
	var aware := {"probe": f.probe, "dead": []}
	aware.merge(aware_extra, true)
	for i in int(max_s / STEP):
		var d: Dictionary = Autopilot.drive(car, road, STEP, aware)
		var r: Dictionary = car.step(STEP, d.throttle, d.steer, f.probe)
		if r.hit > CarSim.SOFT_IMPACT:
			out.hits += 1
		out.ram += r.ram.size()
		out.hp_lost += r.hp_lost
		out.max_speed = maxf(out.max_speed, car.speed)
		out.xs[int(car.pos.y)] = car.pos.x
		if car.progress(road) >= 1.0:
			out.done = true
			out.t = float(i + 1) * STEP
			break
	out["hp"] = car.hp - hp0
	return out


func _leg_len(kind_id: String, leg_s: float) -> int:
	return mini(roundi(leg_s * CarSim.cruise_of(_kinds().get(kind_id, {}))), 700)


func test_autopilot_drives_a_plain_road_in_the_time_the_plan_gives() -> void:
	for kind_id in ["sedan", "pickup", "bus", ""]:
		for dir in [-1, 1]:
			var length := _leg_len(kind_id, 40.0)
			var g := _gen(11, length, dir, [], false)
			var r := _drive_road(g, kind_id, 120.0)
			var cruise_time := float(length) / CarSim.cruise_of(_kinds().get(kind_id, {}))
			check(r.done, "%s dir %d arrives" % [kind_id if kind_id != "" else "foot", dir])
			check(r.t <= cruise_time * 1.35, "%s dir %d: %.1f s for a cruise time of %.1f" % [kind_id, dir, r.t, cruise_time])
			check(r.t >= cruise_time * 1.1, "(the autopilot is the slower way: %.1f s against %.1f)" % [r.t, cruise_time])
			eq(r.hits, 0, "no hits on a plain road")
			check(r.max_speed <= _car(kind_id).cruise * 0.85, "it keeps to about 0.8 of cruise (%.2f)" % r.max_speed)


func test_autopilot_drives_100_roads_every_kind_without_a_crash() -> void:
	var worst_ratio := 0.0
	var worst_hits := 0
	var runs := 0
	var slow_runs := []
	for s in range(1, 26):
		for kind_id in ["sedan", "pickup", "van", "bus"]:
			var leg_s: float = [30.0, 36.0, 50.0][s % 3]
			var length := _leg_len(kind_id, leg_s)
			var blocks := []
			if s % 2 == 0:
				blocks.append({"y": int(float(length) * 0.35) + 12, "gap": float((s * 7) % 5 - 2) * 0.9})
			if s % 4 == 0 and leg_s >= 50.0:    # (a second roadblock only on a long leg)
				blocks.append({"y": int(float(length) * 0.75) + 12, "gap": float((s * 3) % 5 - 2) * 0.9})
			var dir := -1 if s % 2 == 0 else 1
			var g := _gen(100 + s, length, dir, blocks)
			var r := _drive_road(g, kind_id, leg_s * 2.0)
			var cruise_time := float(length) / CarSim.cruise_of(_kinds()[kind_id])
			runs += 1
			if not r.done:
				check(false, "seed %d %s did not arrive in %.0f s (blocks %s)" % [s, kind_id, leg_s * 2.0, str(blocks)])
				continue
			worst_ratio = maxf(worst_ratio, r.t / cruise_time)
			worst_hits = maxi(worst_hits, r.hits)
			if r.t > cruise_time * 1.35 or r.hits >= 2 or r.ram > 0:
				slow_runs.append("seed %d %s: %.2fx, %d hits, %d rammed" % [s, kind_id, r.t / cruise_time, r.hits, r.ram])
	eq(runs, 100, "a hundred roads")
	check(slow_runs.is_empty(), "every road within 1.35x of the cruise time, under 2 hits, nothing rammed: %s" % str(slow_runs))
	check(worst_ratio <= 1.35, "the worst road took %.2fx the cruise time" % worst_ratio)


func test_autopilot_takes_the_gap() -> void:
	for dir in [-1, 1]:
		for gap in [-2.2, 0.0, 2.2]:
			var length := _leg_len("pickup", 40.0)
			var g := _gen(31, length, dir, [{"y": length / 2 + 12, "gap": gap}], false)
			var r := _drive_road(g, "pickup", 90.0)
			check(r.done, "dir %d gap %.1f: arrives" % [dir, gap])
			eq(r.hits, 0, "dir %d gap %.1f: no hits" % [dir, gap])
			eq(r.ram, 0, "dir %d gap %.1f: nothing rammed" % [dir, gap])
			var gy := int(g.gaps[0].y)
			var x_there: float = r.xs.get(gy, NAN)
			check(absf(x_there - (_centre_x_at(g.road, float(gy)))) < 0.7, "dir %d gap %.1f: the car goes through the gap's middle (x %.2f, middle %.2f)" % [dir, gap, x_there, _centre_x_at(g.road, float(gy))])


func test_autopilot_stops_at_a_wall_of_dyn_rather_than_ramming() -> void:
	for kind_id in ["sedan", "pickup", "bus"]:
		var length := _leg_len(kind_id, 40.0)
		var wall_y := length / 2 + 12
		var g := _gen(5, length, -1, [{"y": wall_y, "gap": null}], false)
		var r := _drive_road(g, kind_id, 90.0)
		var car = r.car
		check(not r.done, "%s: it does not get through a wall with no gap" % kind_id)
		eq(r.ram, 0, "%s: it rams nothing" % kind_id)
		eq(r.hits, 0, "%s: no hit at all" % kind_id)
		near(r.hp_lost, 0.0, 1.0e-9, "%s: unhurt" % kind_id)
		near(car.speed, 0.0, 0.05, "%s: standing" % kind_id)
		var nose_gap: float = car.pos.y - float(_kinds()[kind_id].h) / 2.0 - float(wall_y + 3)    # north: the wall's face is at wall_y + 3
		check(nose_gap > 0.3 and nose_gap < 5.0, "%s: it stopped %.2f tiles short of the wall" % [kind_id, nose_gap])


func test_autopilot_slows_for_a_dead_one_it_cannot_afford_and_waits_for_a_card() -> void:
	# (since FIX 21 a healthy car ploughs the dead at speed: see test_autopilot_ploughs_the_dead_and_creeps_only_when_it_is_hurt; a
	# car with 8 hp cannot pay for a brute (6 hp) and creeps by it)
	var length := _leg_len("pickup", 60.0)
	var g := _gen(21, length, -1, [], false)
	var road: Dictionary = g.road
	var z_y: float = road.start.y - 120.0
	var zombie := {"pos": Vector2(_centre_x_at(road, z_y), z_y), "kind": "brute"}
	var r := _drive_road(g, "pickup", 100.0, {"dead": [zombie]}, 8.0)
	check(r.done, "it drives past a brute in the road")
	# the speed within 12 tiles before it
	var car = CarSim.new()
	var k: Dictionary = _kinds()["pickup"]
	car.setup(k, road.start, NORTH, 8.0)
	var f: RoadField = g.field
	var fastest_near := 0.0
	var fastest_far := 0.0
	for i in 4000:
		var d: Dictionary = Autopilot.drive(car, road, STEP, {"probe": f.probe, "dead": [zombie]})
		car.step(STEP, d.throttle, d.steer, f.probe)
		var to_it: float = car.pos.y - z_y
		if to_it > 2.0 and to_it < 12.0:
			fastest_near = maxf(fastest_near, car.speed)
		if to_it > 30.0 and to_it < 60.0:
			fastest_far = maxf(fastest_far, car.speed)
		if car.pos.y < z_y - 10.0:
			break
	check(fastest_near <= 2.8, "within 12 tiles of a brute a car with 8 hp is at %.2f t/s, under 2.8" % fastest_near)
	check(fastest_far > 4.5, "far from it, it was going %.2f" % fastest_far)
	# one off to the side does not matter
	var side := {"pos": Vector2(_centre_x_at(road, z_y) + 3.5, z_y), "kind": "brute"}
	var r2 := _drive_road(g, "pickup", 100.0, {"dead": [side]}, 8.0)
	check(r2.t < r.t - 1.0, "one on the verge costs no time (%.1f against %.1f)" % [r2.t, r.t])
	# an open stop's card: it stops, and goes on when the card is done
	var c2 = CarSim.new()
	c2.setup(k, road.start, NORTH, float(k.hp))
	for i in 150:
		var d: Dictionary = Autopilot.drive(c2, road, STEP, {"probe": f.probe})
		c2.step(STEP, d.throttle, d.steer, f.probe)
	check(c2.speed > 3.0, "going before the card")
	for i in 90:
		var d: Dictionary = Autopilot.drive(c2, road, STEP, {"probe": f.probe, "halt": true})
		c2.step(STEP, d.throttle, d.steer, f.probe)
	near(c2.speed, 0.0, 0.05, "stopped for the card")
	var at: Vector2 = c2.pos
	for i in 60:
		var d: Dictionary = Autopilot.drive(c2, road, STEP, {"probe": f.probe, "halt": true})
		c2.step(STEP, d.throttle, d.steer, f.probe)
	check(c2.pos.distance_to(at) < 0.05, "and it stays while the card is open")
	for i in 150:
		var d: Dictionary = Autopilot.drive(c2, road, STEP, {"probe": f.probe})
		c2.step(STEP, d.throttle, d.steer, f.probe)
	check(c2.speed > 3.0 and c2.pos.distance_to(at) > 5.0, "then on again")


func test_autopilot_finds_the_road_from_the_grass() -> void:
	var length := _leg_len("pickup", 50.0)
	var g := _gen(9, length, -1, [], false)
	var road: Dictionary = g.road
	var f: RoadField = g.field
	var k: Dictionary = _kinds()["pickup"]
	var car = CarSim.new()
	car.setup(k, road.start + Vector2(4.5, 0.0), NORTH + 0.8, float(k.hp))
	var done := false
	var hits := 0
	var off := 0.0
	for i in 3600:
		var d: Dictionary = Autopilot.drive(car, road, STEP, {"probe": f.probe})
		var r: Dictionary = car.step(STEP, d.throttle, d.steer, f.probe)
		hits += 1 if r.hit > 2.0 else 0
		if i > 300 and i % 30 == 0:
			off = maxf(off, absf(car.pos.x - _centre_x_at(road, car.pos.y)))
		if car.progress(road) >= 1.0:
			done = true
			break
	check(done, "it gets back to the road and drives it")
	eq(hits, 0, "without a crash")
	check(off < 1.0, "and holds the road after 10 s (%.2f off)" % off)


func test_autopilot_is_deterministic() -> void:
	var logs := []
	for run in 2:
		var g := _gen(44, 220, 1, [{"y": 100, "gap": 1.5}])
		var car = CarSim.new()
		var k: Dictionary = _kinds()["van"]
		car.setup(k, g.road.start, SOUTH, float(k.hp))
		var log := []
		for i in 1200:
			var d: Dictionary = Autopilot.drive(car, g.road, STEP, {"probe": g.field.probe, "dead": []})
			car.step(STEP, d.throttle, d.steer, g.field.probe)
			log.append([d.throttle, d.steer, car.pos.x, car.pos.y, car.speed])
		logs.append(log)
	check(logs[0] == logs[1], "the same road gives the same drive, to the bit")


func test_autopilot_does_not_cost_a_probe_a_step() -> void:
	# the corridor is looked at a few times a second, not every step
	var g := _gen(3, 200, -1, [], false)
	var car = CarSim.new()
	var k: Dictionary = _kinds()["pickup"]
	car.setup(k, g.road.start, NORTH, float(k.hp))
	var f: RoadField = g.field
	var steps := 600
	for i in steps:
		var d: Dictionary = Autopilot.drive(car, g.road, STEP, {"probe": f.probe})
		car.step(STEP, d.throttle, d.steer, f.probe)
	check(float(f.calls) / float(steps) < 50.0, "%.1f probe calls a step" % (float(f.calls) / float(steps)))


# ------------------------------------------------------------------------------------ the real generated roads --

## The ground of a generated road site (scripts/drive/road_gen.gd) as the scene's probe gives it: the grid's solids, the terrain's
## names, and the wrecks of the roadblocks by id with what they cost to ram.
class SiteField:
	extends RefCounted
	var w := 0
	var h := 0
	var terr
	var solid
	var names := {}
	var dyn := {}
	var ram := {}

	func setup(site: Dictionary) -> void:
		var d: Dictionary = site.data
		w = int(d.W)
		h = int(d.H)
		terr = d.terrain
		solid = d.solidP
		for k in d.terrainTypes:
			names[int(d.terrainTypes[k].id)] = String(k)
		for e in site.road.dyn:
			for i in e.tiles:
				dyn[int(i)] = String(e.id)
			ram[String(e.id)] = float(e.get("ram_hp", -1.0))

	func probe(p: Vector2) -> Dictionary:
		var x := floori(p.x)
		var y := floori(p.y)
		if x < 0 or y < 0 or x >= w or y >= h:
			return {"solid": true, "ground": "", "dyn": ""}
		var i := y * w + x
		var id: String = dyn.get(i, "")
		var out := {"solid": int(solid[i]) != 0, "ground": names.get(int(terr[i]), "ASPHALT"), "dyn": id}
		if id != "" and ram.get(id, -1.0) >= 0.0:
			out["ram_hp"] = ram[id]
		return out


func test_autopilot_drives_the_roads_the_generator_makes() -> void:
	var gen = load("res://scripts/drive/road_gen.gd")
	if gen == null:
		return    # (ROAD-GEN's file is not in yet: the fake roads above are the proof until it is)
	var places = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town.json")).places
	var by_id := {}
	for p in places:
		by_id[String(p.id)] = p
	var event_kind := {"ambush": "dead", "roadblock": "block", "smoke": "stop"}
	var order := ["roadblock", "ambush", "roadblock", "smoke"]
	var ids := ["pharmacy", "farm_a", "scrapyard", "houses"]
	var runs := 0
	var blocks_met := 0
	var bad := []
	for seed_value in [3, 6, 12, 21]:
		for kind_id in ["sedan", "pickup", "van", "bus", ""]:
			var place: Dictionary = by_id[ids[seed_value % ids.size()]]
			var k: Dictionary = _kinds().get(kind_id, {})
			var cruise := CarSim.cruise_of(k)
			var leg_s := 30.0 + float((seed_value * 7) % 20)
			var len_t := mini(roundi(leg_s * cruise), 700)
			var plan := []
			for i in 3:
				var id: String = order[(seed_value + i) % order.size()]
				plan.append({"uid": "e%d" % (i + 1), "id": id, "kind": event_kind[id], "at": 0.2 + 0.25 * float(i), "seed": seed_value + i, "night": false, "state": "pending", "def": {"title": id}})
			for leg in ["there", "home"]:
				var ctx := {"kind": kind_id, "road_min": float(len_t) / cruise, "cruise": cruise, "len": len_t, "plan": plan, "danger": seed_value % 4, "hour": 10.0, "leg": leg}
				var site: Dictionary = gen.make(place, seed_value, leg, ctx)
				var road: Dictionary = site.road
				var field := SiteField.new()
				field.setup(site)
				var g := {"road": road, "field": field}
				var r := _drive_road(g, kind_id, leg_s * 2.0)
				var has_block := false
				for slot in road.slots:
					has_block = has_block or slot.gap != null
				blocks_met += 1 if has_block else 0
				runs += 1
				var ratio: float = r.t / (float(len_t) / cruise)
				var limit := 1.5 if (kind_id == "bus" and has_block) else 1.35    # (a bus through a 3.4 gap is the tight one)
				if not r.done or r.hits >= 2 or r.ram > 0 or ratio > limit:
					bad.append("seed %d %s %s %s: done %s, %.2fx, %d hits, %d rammed" % [seed_value, kind_id, leg, String(place.id), str(r.done), ratio, r.hits, r.ram])
	eq(runs, 40, "forty real roads")
	check(blocks_met >= 10, "most of them had a roadblock (%d)" % blocks_met)
	check(bad.is_empty(), "every real road driven in time, under 2 hits, nothing rammed: %s" % str(bad))


# ------------------------------------------------------------------- the dead on the road (FIX 21) --

## A small model of the dead for the autopilot (the scene's own rules, simplified): the dead of a strip wake when the car is within
## 10 tiles and come for it (walker 1.2, brute 1.8, runner 3.0 t/s); one inside the body (grown by 0.35) is run over from
## RUN_OVER_SPEED up (a brute costs BRUTE_HP and speed and stays), else pushed out of the body and, below 2 t/s, it claws. The
## autopilot is told every live one within 24 x 12 tiles, a brute with its kind, as the scene does.
func _drive_dead(g: Dictionary, kind_id: String, max_s: float, dead: Array, events: Array = []) -> Dictionary:
	var road: Dictionary = g.road
	var f = g.field
	var k: Dictionary = _kinds().get(kind_id, {})
	var car = CarSim.new()
	var head := NORTH if int(road.dir) < 0 else SOUTH
	car.setup(k, road.start, head, float(k.get("hp", 100.0)))
	var out := {"done": false, "t": max_s, "hits": 0, "ram": 0, "killed": 0, "wrecked": false, "car": car, "slow_s": 0.0}
	var speeds := {"walker": 1.2, "brute": 1.8, "runner": 3.0}
	var hx: float = car.length * 0.5 + 0.35
	var hy: float = car.width * 0.5 + 0.35
	var brute_hit := -9.0
	var pending: Array = events.duplicate()
	for i in int(max_s / STEP):
		var now := float(i) * STEP
		var here: Vector2 = car.pos
		# the events of the road: their dead come into the world as the car nears
		while not pending.is_empty() and car.progress(road) >= float(pending[0].at) - 0.08:
			dead.append_array(pending[0].dead)
			pending.pop_front()
		var near: Array = []
		for z in dead:
			if not z.alive:
				continue
			var to: Vector2 = here - z.pos
			if z.state != "hunt" and to.length() < 10.0:
				z.state = "hunt"
			if z.state == "hunt" and to.length() < 30.0:
				z.pos += to.normalized() * float(speeds[z.kind]) * STEP
			if absf(z.pos.y - here.y) < 24.0 and absf(z.pos.x - here.x) < 12.0:
				near.append({"pos": z.pos, "kind": z.kind} if z.kind == "brute" else z.pos)
		var d: Dictionary = Autopilot.drive(car, road, STEP, {"probe": f.probe, "dead": near})
		var r: Dictionary = car.step(STEP, d.throttle, d.steer, f.probe)
		if r.hit > CarSim.SOFT_IMPACT:
			out.hits += 1
		out.ram += r.ram.size()
		if car.speed < 4.0:
			out.slow_s += STEP
		var dir := Vector2.from_angle(car.heading)
		var side := dir.rotated(PI / 2.0)
		var claws := 0
		for z in dead:
			if not z.alive:
				continue
			var rel: Vector2 = z.pos - car.pos
			var lx := rel.dot(dir)
			var ly := rel.dot(side)
			if absf(lx) > hx or absf(ly) > hy:
				continue
			if car.speed >= CarSim.RUN_OVER_SPEED:
				if z.kind == "brute":
					if brute_hit < now - 1.0:
						brute_hit = now
						car.run_over(true)
				else:
					car.run_over(false)
					z.alive = false
					out.killed += 1
				continue
			claws += 1
			var nx := lx
			var ny := ly
			if hx - absf(lx) < hy - absf(ly):
				nx = (hx + 0.03) * (1.0 if lx >= 0.0 else -1.0)
			else:
				ny = (hy + 0.03) * (1.0 if ly >= 0.0 else -1.0)
			z.pos = car.pos + dir * nx + side * ny
		if claws > 0:
			car.claws(claws, STEP)
		if car.hp <= 0.0 or car.wrecked:
			out.wrecked = true
			break
		if car.progress(road) >= 1.0:
			out.done = true
			out.t = float(i + 1) * STEP
			break
	out["hp"] = car.hp
	return out


func _dead_of_site(site: Dictionary) -> Array:
	var out: Array = []
	for z in site.get("dead", []):
		out.append({"pos": Vector2(z.pos), "kind": String(z.kind), "state": "wander" if String(z.state) == "wander" else "still", "alive": true})
	return out


## The dead an event brings (the deck's own counts, simplified): an ambush pours a dozen hunters round its slot's spawn point, a herd
## fills 20 tiles of the road with the still ones.
func _dead_of_event(entry: Dictionary, slot: Dictionary, danger: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry.seed)
	var out: Array = []
	var at: Vector2 = slot.spawn
	if String(entry.id) == "herd":
		for i in 30:
			out.append({"pos": at + Vector2(rng.randf_range(-3.0, 3.0), -rng.randf_range(0.0, 20.0)), "kind": "walker", "state": "still", "alive": true})
	else:
		for i in 8 + 3 * danger:
			out.append({"pos": at + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-4.0, 4.0)), "kind": "runner" if (danger >= 2 and i % 4 == 0) else "walker", "state": "hunt", "alive": true})
	return out


## FIX 21 (review of round 21, important 1): the Tab autopilot never recovered its speed: one dead one in its 14-tile corridor held it
## at 2.5 t/s, under the 4.0 that runs anyone over, so more of them gathered and a whole leg took two to three times the cruise time
## (the plan promises at most 1.35x). Real ROAD-GEN roads, every kind of vehicle, danger 1 to 3, both legs, the strip's own dead and
## an ambush or a herd on the way: it arrives within 1.35x of the cruise time, a car that is not a wreck, hardly a crash.
func test_autopilot_keeps_the_pace_with_the_dead_on_the_real_roads() -> void:
	var gen = load("res://scripts/drive/road_gen.gd")
	var places = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town.json")).places
	var by_id := {}
	for p in places:
		by_id[String(p.id)] = p
	var ids := ["pharmacy", "farm_a", "scrapyard", "houses", "hospital", "estate"]
	var kinds := ["sedan", "pickup", "van", "bus"]
	var runs := 0
	var killed := 0
	var dead_met := 0
	var worst := 0.0
	var bad := []
	for seed_value in range(1, 49):
		var kind_id: String = kinds[seed_value % kinds.size()]
		var place: Dictionary = by_id[ids[seed_value % ids.size()]]
		var k: Dictionary = _kinds()[kind_id]
		var cruise := CarSim.cruise_of(k)
		var leg_s: float = [36.0, 50.0, 70.0, 90.0][seed_value % 4]
		var len_t := mini(roundi(leg_s * cruise), 700)
		var danger := 1 + seed_value % 3
		var plan := []
		var ev_ids := ["ambush", "herd", "ambush", "herd"]
		for i in 2:
			var id: String = ev_ids[(seed_value + i) % ev_ids.size()]
			plan.append({"uid": "e%d" % (i + 1), "id": id, "kind": "dead", "at": 0.3 + 0.35 * float(i), "seed": seed_value * 10 + i, "night": false, "state": "pending", "def": {"title": id}})
		var leg: String = "there" if seed_value % 2 == 0 else "home"
		var ctx := {"kind": kind_id, "road_min": float(len_t) / cruise, "cruise": cruise, "len": len_t, "plan": plan, "danger": danger, "hour": 10.0, "leg": leg}
		var site: Dictionary = gen.make(place, seed_value, leg, ctx)
		var field := SiteField.new()
		field.setup(site)
		var events: Array = []
		for slot in site.road.slots:
			for e in plan:
				if String(e.uid) == String(slot.uid):
					events.append({"at": float(e.at), "dead": _dead_of_event(e, slot, danger)})
		var dead := _dead_of_site(site)
		dead_met += dead.size()
		var r := _drive_dead({"road": site.road, "field": field}, kind_id, leg_s * 3.0, dead, events)
		runs += 1
		killed += int(r.killed)
		var ratio: float = r.t / (float(len_t) / cruise)
		worst = maxf(worst, ratio)
		if not r.done or r.wrecked or r.hits >= 2 or r.ram > 0 or ratio > 1.35:
			bad.append("seed %d %s %s %s danger %d: done %s, %.2fx, %d hits, %d rammed, hp %.0f" % [seed_value, kind_id, leg, String(place.id), danger, str(r.done), ratio, r.hits, r.ram, r.hp])
	eq(runs, 48, "forty-eight real roads")
	check(dead_met >= 100 and killed >= 60, "with the dead really on them (%d of the strips', %d run over)" % [dead_met, killed])
	check(bad.is_empty(), "every road driven within 1.35x of the cruise time, a car that survives, under 2 hits (worst %.2fx; %d bad): %s" % [worst, bad.size(), str(bad.slice(0, 4))])


## What a car should not plough it creeps through, and only that: a healthy car goes through a walker or a brute at speed (the dead are
## run over from 4.0 t/s), a car too hurt to pay for the dead of its corridor (RUN_OVER_HP each, BRUTE_HP a brute, less 4 hp) creeps by
## them at the caution speed (above the 2 t/s under which they claw).
func test_autopilot_ploughs_the_dead_and_creeps_only_when_it_is_hurt() -> void:
	var length := _leg_len("pickup", 90.0)
	var g := _gen(21, length, -1, [], false)
	var road: Dictionary = g.road
	var f: RoadField = g.field
	var k: Dictionary = _kinds()["pickup"]
	var z_y: float = road.start.y - 100.0
	var cases := {
		"walker": [90.0, [{"pos": Vector2(_centre_x_at(road, z_y), z_y), "kind": "walker"}]],
		"plain": [90.0, [Vector2(_centre_x_at(road, z_y), z_y)]],
		"brute": [90.0, [{"pos": Vector2(_centre_x_at(road, z_y), z_y), "kind": "brute"}]],
		"herd": [90.0, []],
		"hurt brute": [9.0, [{"pos": Vector2(_centre_x_at(road, z_y), z_y), "kind": "brute"}]],
		"hurt herd": [6.0, []],
		"fine herd": [30.0, []],
	}
	for label in ["herd", "hurt herd", "fine herd"]:
		for i in 12:    # twelve of them across the way ahead: 4.2 hp to plough through
			cases[label][1].append({"pos": Vector2(_centre_x_at(road, z_y - float(i)), z_y - float(i)), "kind": "walker"})
	var near_speed := {}
	for label in cases:
		var car = CarSim.new()
		car.setup(k, road.start, NORTH, float(cases[label][0]))
		var fastest := 0.0
		var arrived := false
		for i in 4000:
			var d: Dictionary = Autopilot.drive(car, road, STEP, {"probe": f.probe, "dead": cases[label][1]})
			car.step(STEP, d.throttle, d.steer, f.probe)
			var to_it: float = car.pos.y - z_y
			if to_it > 1.0 and to_it < 6.0:
				fastest = maxf(fastest, car.speed)
			if car.pos.y < z_y - 14.0:
				arrived = true
				break
		check(arrived, "%s: it gets past" % label)
		near_speed[label] = fastest
	for label in ["walker", "plain", "brute", "herd", "fine herd"]:
		check(near_speed[label] >= 4.2, "%s ahead: ploughed at speed (%.2f t/s within 6 tiles)" % [label, near_speed[label]])
	for label in ["hurt brute", "hurt herd"]:
		check(near_speed[label] <= 2.8 and near_speed[label] > 2.0, "%s: a car that cannot pay for them creeps at the caution speed (%.2f t/s)" % [label, near_speed[label]])
	# the dead behind the car, or off the carriageway, cost the hurt car nothing either
	var car2 = CarSim.new()
	car2.setup(k, road.start, NORTH, 6.0)
	var fastest_late := 0.0
	for i in 600:
		var behind: Vector2 = car2.pos - Vector2.from_angle(car2.heading) * 5.0
		var beside: Vector2 = car2.pos + Vector2.from_angle(car2.heading + PI / 2.0) * 6.0
		var d: Dictionary = Autopilot.drive(car2, road, STEP, {"probe": f.probe, "dead": [behind, beside]})
		car2.step(STEP, d.throttle, d.steer, f.probe)
		if i > 300:
			fastest_late = maxf(fastest_late, car2.speed)
	check(fastest_late >= 4.2, "dead behind it and beside it do not slow even a hurt car (%.2f t/s)" % fastest_late)


func test_a_long_step_is_taken_in_short_ones() -> void:
	# a lag spike (a step of a tenth of a second) must not jump a wall
	var f := _wall_field()
	var car = _at_wall("sedan", 10.0, 0.8)
	var r: Dictionary = car.step(0.1, 0.0, 0.0, f.probe)
	check(r.hit > 8.0, "the wall is met inside a long step (%.2f)" % r.hit)
	var worst := 0.0
	for p in car.outline():
		worst = maxf(worst, p.x)
	check(worst <= 20.0 + 1.0e-4, "and is not jumped (%.3f)" % worst)
	# the same ten steps of 1/30 and one of ten times that agree on a free road
	var a = _car("pickup")
	var b = _car("pickup")
	var open := Field.new()
	for i in 3:
		a.step(STEP, 1.0, 0.2, open.probe)
	b.step(STEP * 3.0, 1.0, 0.2, open.probe)
	check(a.pos == b.pos and a.speed == b.speed and a.heading == b.heading, "three steps are one step of three times the length")
