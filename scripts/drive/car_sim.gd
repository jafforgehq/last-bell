## The car of the live drive (round 21, slice 5): arcade top-down physics for the road between the base and a place, pure
## (no nodes, no clock, no random), stepped by the scene at a fixed 1/30 s. The same inputs always give the same path, to
## the bit. The scene owns what the car meets (the grid, the wrecks of a roadblock, the dead); the car asks it through ONE
## probe, `probe(p: Vector2) -> {"solid": bool, "ground": String, "dyn": String}` (the tile at the world point `p`: whether it
## stops a car, its ground ("ASPHALT", "SIDEWALK", "DIRT", "GRASS", "SOIL"), and the id of the wreck of the road that holds
## it, "" for none). A probe may add `"ram_hp"` for a `dyn`: the hp it costs the car to ram it (the data's 8 for a car, 15 for a
## bus); absent means RAM_HP, 0 means it cannot be rammed (it is a wall at any speed).
##
## THE CAR. `W` accelerate (throttle +1), `S` brake and then reverse (throttle -1), `A` / `D` steer (-1 / +1: D swings the nose
## clockwise on the screen, the heading grows; the picture's nose is the heading, 0 = east, -PI/2 = north). `cruise` is the
## walking speed times the kind's speed (a sedan 7.68 tiles/s, a pickup and a van 7.04, a bus 5.76), `top` is 1.5 times that.
## The engine pushes ACCEL a second against DRAG (a fraction of the speed a second), the brake takes BRAKE, a car left alone
## rolls to a stop at ROLL. The ground sets the share of `top` the car can hold (GROUND): the car slows toward it, it does not
## drop to it. It turns TURN_RATE rad/s at full bite: none at rest, all of it from 4 tiles/s, 0.45 of it at the top (so the
## turning radius grows with the speed); in reverse the nose swings the other way. No slip: the car goes where its nose points.
##
## THE BODY. The kind's `w` wide and `h` long (vehicles.json). `circles()` gives its three circles of radius w/2 along the
## heading (what the dead are held outside of), `footprint()` the rotated rectangle (the drawing's), `outline()` the points the
## collision looks at: the rectangle's rim with its corners rounded (0.5), a point every 0.75 tiles, so a wall is found as soon as
## the nose or a flank touches it; the car is then pushed out along the surface's normal and settled on it, and a long step
## (more than 1/30 s) is taken as equal short ones, so that nothing is jumped.
##
## HITS. The closing speed along the normal is the impact. Its normal part is lost down to BOUNCE (a frontal crash keeps
## BOUNCE of the speed), the nose swings toward the wall's line when the blow is glancing (so a scrape slides), and the car
## pays `(impact - SOFT_IMPACT) x IMPACT_HP` hp: nothing under SOFT_IMPACT, and once for a crash (CRASH_LOCK holds the next
## hundreds of milliseconds' bounces off the bill). A wreck of the road (`dyn`) struck at RAM_SPEED or more is rammed: it is
## reported in `ram` once, costs RAM_HP (or the probe's `ram_hp`), the car keeps RAM_KEEP of its speed and goes on through
## (the scene opens its tiles; the car never meets that id again). Struck slower, or with `ram_hp` 0, it is a wall. hp 0 is a
## wreck: the car stops for good (`wrecked`), reported by the step that did it (and by `damage`). The dead the scene finds
## on the road cost the car through `run_over`, `claws`; the scene keeps its own bookkeeping of the dead.
##
## ON FOOT (an empty kind: the avatar walks the road). The same interface with walking constants: `cruise` and `top` are the
## walking speed (no sprint), the start and the stop are at once, the nose turns on the spot, the ground does not slow, the
## body is one circle of 0.3, a wall or a wreck simply stops the walker (no hp is lost, nothing is rammed).
##
## FUEL AND PROGRESS. `progress(road)` is the distance along the road's centreline from its `start`, over the distance to its
## `end`, 0 to 1 (a car behind the start is at 0). `fuel_burnt(per_leg, progress)` is `per_leg x progress`: fuel is burnt by
## the DISTANCE driven along the road, never by the time, so an eventless drive there and back burns exactly the abstract
## trip's fuel (`vehicles.fuel_for`).
extends RefCounted

const Avatar := preload("res://scripts/sim/avatar.gd")

# ----------------------------------------------------------------------------------------- the constants --
const ACCEL := 5.5             # tiles/s2 at full throttle
const BRAKE := 13.0            # tiles/s2 at full brake
const REVERSE_MAX := 2.5       # tiles/s backwards
const REVERSE_ACCEL := 3.0     # tiles/s2 backwards
const DRAG := 0.30             # the share of the speed lost a second
const ROLL := 0.8              # tiles/s2 of a car left alone
const TURN_RATE := 1.9         # rad/s at full bite
const TURN_FULL_AT := 4.0      # the speed from which the steering has all its bite
const TURN_AT_TOP := 0.45      # the share of the bite left at the top speed
const TOP_FACTOR := 1.5        # top = cruise x this
## The share of `top` the car can hold on that ground.
const GROUND := {"ASPHALT": 1.0, "SIDEWALK": 0.9, "DIRT": 0.75, "GRASS": 0.6, "SOIL": 0.5}
## How hard a car faster than its ground allows is slowed toward it (tiles/s2, besides drag).
const GROUND_DECEL := 6.0

const SOFT_IMPACT := 2.0       # tiles/s: a bump under this costs nothing
const IMPACT_HP := 1.4         # hp for each tile/s over it
const BOUNCE := 0.35           # the share of the speed kept in a frontal crash
const RAM_SPEED := 6.0         # tiles/s: a wreck of the road struck at this is knocked aside
const RAM_KEEP := 0.55         # the share of the speed kept
const RAM_HP := 8.0            # hp: a car wreck (the probe's `ram_hp` says 15 for a bus)
const RUN_OVER_SPEED := 4.0    # tiles/s: the dead run over above this
const RUN_OVER_HP := 0.35
const BRUTE_HP := 6.0          # a brute is not killed: it costs this and
const BRUTE_KEEP := 0.6        # this share of the speed
const CLAW_DPS := 0.8          # hp a second for each dead one in contact below CLAW_BELOW, at most CLAW_MAX of them
const CLAW_BELOW := 2.0
const CLAW_MAX := 6
## After a crash that cost hp, the bounces of the next seconds cost none.
const CRASH_LOCK := 0.25
## A blow that is not head-on turns the nose this share of the way to the wall's line.
const ALIGN := 0.5
const ALIGN_MIN_TANGENT := 0.35
const ALIGN_MIN_CLOSING := 0.4
## An impact of this many tiles/s is a knock (`hit_age` counts from it).
const KNOCK := 1.0

# on foot
const FOOT_RADIUS := 0.3
const FOOT_ACCEL := 18.0
const FOOT_BRAKE := 30.0
const FOOT_REVERSE_MAX := 1.6
const FOOT_TURN := 5.0

## The longest step taken whole.
const MAX_SUB := 1.0 / 30.0 + 1.0e-6

## The collision pushes the car out this much at a time, at most MAX_PUSH times.
const PUSH_STEP := 0.05
const MAX_PUSH := 60
## The outline is sampled about this far apart; the corners of the body are rounded to this radius.
const SAMPLE_GAP := 0.75
const CORNER := 0.5
## Under this speed a touch is not a scrape (a car standing against a wall is not scraping it).
const SCRAPE_MIN := 0.5
## A surface's normal is read from the open tiles this far around a point inside it.
const NORMAL_REACH := 0.6

# ------------------------------------------------------------------------------------------------ state --
var pos := Vector2.ZERO
var heading := 0.0
var speed := 0.0
var hp := 100.0
var kind := {}
var cruise := 3.2
var top := 3.2
var foot := false
var wrecked := false
var width := 2.2
var length := 4.4
## The autopilot's scratch (its path cache and timers); the car keeps it, nobody else reads it.
var ap := {}
## The probe the car was last stepped with (the autopilot looks ahead through it when the scene does not hand it another).
var last_probe := Callable()
## Seconds since the last knock (an impact of KNOCK or more); the autopilot backs away from a wall it has hit.
var hit_age := 99.0

var _samples: Array = []
var _centres: Array = []    # local x of the three circles
var _rammed := {}           # the wrecks of the road this car has knocked aside: it never meets them again
var _crash_cd := 0.0
var _accel := ACCEL
var _brake := BRAKE
var _roll := ROLL
var _drag := DRAG
var _rev_max := REVERSE_MAX
var _rev_accel := REVERSE_ACCEL

# the road's centreline, cached
var _road_key: Array = []
var _cl := PackedVector2Array()
var _cum := PackedFloat64Array()
var _s0 := 0.0
var _s1 := 0.0
var _hint := -1


## The cruise speed of a kind (tiles/s): the walking speed times its `speed`; on foot ({}) the walking speed.
static func cruise_of(k: Dictionary) -> float:
	if k.is_empty():
		return Avatar.WALK_SPEED
	return Avatar.WALK_SPEED * float(k.get("speed", 1.0))


## The kind (a `vehicles.json` kind, with its `speed`, `w`, `h`; {} = on foot) at `start`, its nose along `head`, at `hp_now`.
func setup(k: Dictionary, start: Vector2, head: float, hp_now: float) -> void:
	kind = k
	foot = k.is_empty()
	cruise = cruise_of(k)
	pos = start
	heading = head
	speed = 0.0
	hp = hp_now
	wrecked = false
	ap = {}
	_rammed = {}
	_crash_cd = 0.0
	hit_age = 99.0
	last_probe = Callable()
	_road_key = []
	_hint = -1
	if foot:
		width = FOOT_RADIUS * 2.0
		length = FOOT_RADIUS * 2.0
		top = cruise
		_accel = FOOT_ACCEL
		_brake = FOOT_BRAKE
		_roll = FOOT_BRAKE
		_drag = 0.0
		_rev_max = FOOT_REVERSE_MAX
		_rev_accel = FOOT_ACCEL
	else:
		width = float(k.get("w", 2.2))
		length = float(k.get("h", 4.4))
		top = cruise * TOP_FACTOR
		_accel = ACCEL
		_brake = BRAKE
		_roll = ROLL
		_drag = DRAG
		_rev_max = REVERSE_MAX
		_rev_accel = REVERSE_ACCEL
	_build_body()


# --------------------------------------------------------------------------------------------- the body --

func _build_body() -> void:
	var r := width / 2.0
	var d := maxf(0.0, length / 2.0 - r)
	_centres = [0.0] if foot else [-d, 0.0, d]
	var poly: Array = []
	if foot:
		for i in 16:
			poly.append(Vector2.from_angle(TAU * float(i) / 16.0) * r)
	else:
		var hl := length / 2.0
		var hw := width / 2.0
		var c := minf(CORNER, hw)
		# clockwise on the screen from the right shoulder: the right flank, the nose, the left flank, the tail
		poly.append(Vector2(-hl + c, hw))
		for arc in [[Vector2(hl - c, hw - c), 90.0, 0.0], [Vector2(hl - c, -hw + c), 0.0, -90.0],
				[Vector2(-hl + c, -hw + c), -90.0, -180.0], [Vector2(-hl + c, hw - c), 180.0, 90.0]]:
			for k in range(0, 7):
				var a := deg_to_rad(lerpf(float(arc[1]), float(arc[2]), float(k) / 6.0))
				poly.append(Vector2(arc[0]) + Vector2(cos(a), sin(a)) * c)
	_samples = [Vector2.ZERO]
	_samples.append_array(_resample(poly, SAMPLE_GAP))


## Points evenly spaced (about `gap` apart) along the closed polyline `poly`.
func _resample(poly: Array, gap: float) -> Array:
	var total := 0.0
	for i in poly.size():
		total += Vector2(poly[i]).distance_to(Vector2(poly[(i + 1) % poly.size()]))
	var n := maxi(8, ceili(total / gap))
	var out: Array = []
	var seg := 0
	var at := 0.0    # the arclength at the start of segment `seg`
	for k in n:
		var t := total * float(k) / float(n)
		while seg < poly.size() - 1 and at + Vector2(poly[seg]).distance_to(Vector2(poly[seg + 1])) < t:
			at += Vector2(poly[seg]).distance_to(Vector2(poly[seg + 1]))
			seg += 1
		var a: Vector2 = poly[seg]
		var b: Vector2 = poly[(seg + 1) % poly.size()]
		var l := a.distance_to(b)
		out.append(a.lerp(b, 0.0 if l < 1.0e-9 else clampf((t - at) / l, 0.0, 1.0)))
	return out


## The body's three circles (one on foot): [{"pos": Vector2, "r": float}], nose to tail.
func circles() -> Array:
	var fwd := Vector2.from_angle(heading)
	var out: Array = []
	for c in _centres:
		out.append({"pos": pos + fwd * float(c), "r": width / 2.0})
	out.reverse()
	return out


## The rotated rectangle of the body: front left, front right, back right, back left.
func footprint() -> PackedVector2Array:
	var fwd := Vector2.from_angle(heading)
	var right := Vector2(-fwd.y, fwd.x)
	var a := fwd * (length / 2.0)
	var b := right * (width / 2.0)
	return PackedVector2Array([pos + a - b, pos + a + b, pos - a + b, pos - a - b])


func forward() -> Vector2:
	return Vector2.from_angle(heading)


## What the driver's hands need to know of the engine: the push of full throttle and of full brake (tiles/s2), and the
## throttle that holds `v` against the drag.
func accel_rate() -> float:
	return _accel


func brake_rate() -> float:
	return _brake


func hold_throttle(v: float) -> float:
	return clampf(_drag * v / _accel, 0.0, 1.0)


## The points of the body's outline the collision looks at, in the world (a rounded rectangle, a circle on foot).
func outline() -> PackedVector2Array:
	var fwd := Vector2.from_angle(heading)
	var right := Vector2(-fwd.y, fwd.x)
	var out := PackedVector2Array()
	for i in range(1, _samples.size()):
		var q: Vector2 = _samples[i]
		out.append(pos + fwd * q.x + right * q.y)
	return out


## How fast the heading changes at full wheel at this speed (rad/s): none at rest and all of it from TURN_FULL_AT, falling
## to TURN_AT_TOP of it at the top. On foot a walker turns on the spot.
func yaw_per_steer(v: float) -> float:
	if foot:
		return FOOT_TURN
	var a := absf(v)
	var bite := clampf(a / TURN_FULL_AT, 0.0, 1.0)
	var high := 1.0 - (1.0 - TURN_AT_TOP) * clampf((a - TURN_FULL_AT) / maxf(top - TURN_FULL_AT, 0.001), 0.0, 1.0)
	return TURN_RATE * bite * high


# ---------------------------------------------------------------------------------------------- the step --

## One step of `dt` seconds (a step longer than MAX_SUB is taken as equal sub-steps, so that nothing is jumped) with the hands
## `throttle` (-1 brake and reverse .. +1) and `steer` (-1 .. +1); the probe is described in the header. Returns {"hit": the worst
## impact (tiles/s, 0 for none), "hp_lost": what it cost, "scrape": the body touched something while moving, "ram": the ids of the
## wrecks of the road knocked aside, "wrecked": hp reached 0 on this step}.
func step(dt: float, throttle: float, steer: float, probe: Callable) -> Dictionary:
	var n := maxi(1, ceili(dt / MAX_SUB))
	if n == 1:
		return _step(dt, throttle, steer, probe)
	var out := {"hit": 0.0, "hp_lost": 0.0, "scrape": false, "ram": [], "wrecked": false}
	for i in n:
		var r := _step(dt / float(n), throttle, steer, probe)
		out["hit"] = maxf(out.hit, r.hit)
		out["hp_lost"] = float(out.hp_lost) + float(r.hp_lost)
		out["scrape"] = bool(out.scrape) or bool(r.scrape)
		out.ram.append_array(r.ram)
		out["wrecked"] = bool(out.wrecked) or bool(r.wrecked)
	return out


func _step(dt: float, throttle: float, steer: float, probe: Callable) -> Dictionary:
	var out := {"hit": 0.0, "hp_lost": 0.0, "scrape": false, "ram": [], "wrecked": false}
	last_probe = probe
	if wrecked:
		speed = 0.0
		return out
	_crash_cd = maxf(0.0, _crash_cd - dt)
	hit_age += dt
	throttle = clampf(throttle, -1.0, 1.0)
	steer = clampf(steer, -1.0, 1.0)
	var share := 1.0
	if not foot:
		share = float(GROUND.get(String(probe.call(pos).get("ground", "")), 1.0))
	_drive(dt, throttle, share)
	heading = wrapf(heading + steer * yaw_per_steer(speed) * (-1.0 if speed < 0.0 else 1.0) * dt, -PI, PI)
	pos += Vector2.from_angle(heading) * speed * dt
	_collide(probe, out)
	if out.hp_lost > 0.0:
		hp -= float(out.hp_lost)
		if hp <= 0.0:
			_wreck()
			out["wrecked"] = true
	return out


func _drive(dt: float, throttle: float, share: float) -> void:
	var cap := top * share
	var rcap := _rev_max * share
	var v := speed
	v -= v * _drag * dt
	if absf(throttle) < 1.0e-9:
		v = move_toward(v, 0.0, _roll * dt)
	elif throttle > 0.0:
		if v < 0.0:
			v = minf(0.0, v + _brake * throttle * dt)    # the brake takes the reverse first
		elif v < cap:
			v = minf(cap, v + _accel * throttle * dt)
	else:
		if v > 0.0:
			v = maxf(0.0, v + _brake * throttle * dt)
		elif v > -rcap:
			v = maxf(-rcap, v + _rev_accel * throttle * dt)
	if v > cap:
		v = maxf(cap, v - GROUND_DECEL * dt)
	elif v < -rcap:
		v = minf(-rcap, v + GROUND_DECEL * dt)
	if absf(v) < 1.0e-6:
		v = 0.0
	speed = v


func _wreck() -> void:
	hp = 0.0
	speed = 0.0
	wrecked = true


## A blow from outside the collision (a dead one run over, the claws, a puncture): hp falls; true when it made a wreck.
func damage(amount: float) -> bool:
	if wrecked or amount <= 0.0:
		return false
	hp -= amount
	if hp <= 0.0:
		_wreck()
		return true
	return false


## One of the dead is run over (the scene found it inside the body above RUN_OVER_SPEED): the hp it cost. A brute is not
## killed: it costs BRUTE_HP and slows the car. On foot nothing is run over.
func run_over(brute: bool) -> float:
	if foot or wrecked:
		return 0.0
	var cost := BRUTE_HP if brute else RUN_OVER_HP
	if brute:
		speed *= BRUTE_KEEP
	damage(cost)
	return cost


## `count` of the dead are clawing at the car for `dt` seconds: the hp it cost (only below CLAW_BELOW tiles/s, at most CLAW_MAX).
func claws(count: int, dt: float) -> float:
	if foot or wrecked or count <= 0 or absf(speed) >= CLAW_BELOW:
		return 0.0
	var cost := CLAW_DPS * float(mini(count, CLAW_MAX)) * dt
	damage(cost)
	return cost


# ------------------------------------------------------------------------------------------- collisions --

func _is_solid(q: Dictionary) -> bool:
	return bool(q.get("solid", false)) or String(q.get("dyn", "")) != ""


## The sample points of the body that are inside something: [{"p", "dyn", "ram"}].
func _contacts(probe: Callable) -> Array:
	var fwd := Vector2.from_angle(heading)
	var right := Vector2(-fwd.y, fwd.x)
	var hits: Array = []
	for s in _samples:
		var p: Vector2 = pos + fwd * s.x + right * s.y
		var q: Dictionary = probe.call(p)
		var id := String(q.get("dyn", ""))
		if id != "" and _rammed.has(id):
			continue
		if bool(q.get("solid", false)) or id != "":
			hits.append({"p": p, "dyn": id, "ram": float(q.get("ram_hp", -1.0))})
	return hits


## The way out of the thing a point is inside: away from the open tiles around it.
func _normal_at(p: Vector2, probe: Callable) -> Vector2:
	var n := Vector2.ZERO
	for k in 8:
		var d := Vector2.from_angle(TAU * float(k) / 8.0) * NORMAL_REACH
		var q: Dictionary = probe.call(p + d)
		var id := String(q.get("dyn", ""))
		if (id != "" and _rammed.has(id)) or not _is_solid(q):
			n += d
	return n


func _collide(probe: Callable, out: Dictionary) -> void:
	var hits := _contacts(probe)
	if hits.is_empty():
		return
	out["scrape"] = absf(speed) >= SCRAPE_MIN
	var fwd := Vector2.from_angle(heading)
	# the hits by what they hit: one group for the ground's solids and one for each wreck of the road
	var groups := {}
	for h in hits:
		var key := String(h.dyn)
		if not groups.has(key):
			groups[key] = {"hits": [], "n": Vector2.ZERO, "ram": float(h.ram)}
		groups[key].hits.append(h)
		groups[key].n += _normal_at(h.p, probe)
	var wall_n := Vector2.ZERO
	var wall_hits := 0
	var rammed_now := false
	for key in groups:
		var g: Dictionary = groups[key]
		var n: Vector2 = g.n
		if n.length() < 1.0e-6:
			for h in g.hits:
				n += pos - Vector2(h.p)
		n = n.normalized() if n.length() > 1.0e-9 else -fwd
		g["n"] = n
		var closing := -(fwd * speed).dot(n)
		if key != "" and not foot and closing >= RAM_SPEED and float(g.ram) != 0.0:
			# a wreck of the road, struck hard: knocked aside, the car goes on through
			_rammed[key] = true
			out.ram.append(key)
			out["hit"] = maxf(out.hit, closing)
			out["hp_lost"] = float(out.hp_lost) + (float(g.ram) if float(g.ram) > 0.0 else RAM_HP)
			rammed_now = true
		else:
			wall_n += n * float(g.hits.size())
			wall_hits += g.hits.size()
	if rammed_now:
		speed *= RAM_KEEP
	if wall_hits == 0:
		return
	var n := wall_n.normalized() if wall_n.length() > 1.0e-9 else -fwd
	# out of the wall along its normal
	var again := _contacts(probe)
	var pushed := 0
	var before := pos
	while not again.is_empty() and pushed < MAX_PUSH:
		before = pos
		pos += n * PUSH_STEP
		pushed += 1
		again = _contacts(probe)
	if pushed > 0 and again.is_empty():
		# the last push may have gone up to PUSH_STEP too far: settle on the surface
		var lo := before
		var hi := pos
		for k in 4:
			pos = (lo + hi) * 0.5
			if _contacts(probe).is_empty():
				hi = pos
			else:
				lo = pos
		pos = hi
	# what the blow does to the car
	var closing := -(fwd * speed).dot(n)
	if closing <= 0.0:
		return
	out["hit"] = maxf(out.hit, closing)
	if closing >= KNOCK:
		hit_age = 0.0
	if not foot and closing > SOFT_IMPACT and _crash_cd <= 0.0:
		out["hp_lost"] = float(out.hp_lost) + (closing - SOFT_IMPACT) * IMPACT_HP
		_crash_cd = CRASH_LOCK
	var keep := 0.0 if foot else BOUNCE
	speed += closing * (1.0 - keep) * n.dot(fwd)
	if not foot and speed > 0.0 and closing > ALIGN_MIN_CLOSING:
		var along := fwd - n * fwd.dot(n)
		if along.length() > ALIGN_MIN_TANGENT:
			heading = lerp_angle(heading, along.angle(), ALIGN)


# ------------------------------------------------------------------------------------------ the road --

## How far along the road the car is: the distance along the road's centreline from `start`, over the distance from
## `start` to `end`, 0 to 1. (The centreline may run either way; a car behind the start is 0, one past the end is 1.)
func progress(road: Dictionary) -> float:
	if not _prepare(road):
		return 0.0
	var s := _project(pos)
	var span := _s1 - _s0
	if absf(span) < 1.0e-6:
		return 0.0
	return clampf((s - _s0) / span, 0.0, 1.0)


## `per_leg x progress`: the trip tank drains by distance, so a whole leg burns the abstract trip's `fuel_for / 2`.
func fuel_burnt(per_leg: float, share: float) -> float:
	return per_leg * clampf(share, 0.0, 1.0)


func _prepare(road: Dictionary) -> bool:
	var raw = road.get("centerline", PackedVector2Array())
	var start := Vector2(road.get("start", Vector2.ZERO))
	var end := Vector2(road.get("end", Vector2.ZERO))
	var cl: PackedVector2Array = PackedVector2Array(raw) if not raw is PackedVector2Array else raw
	if cl.size() < 2:
		cl = PackedVector2Array([start, end])
	var key := [cl.size(), cl[0], cl[cl.size() - 1], start, end]
	if key == _road_key:
		return true
	_road_key = key
	_cl = cl
	_cum.resize(cl.size())
	_cum[0] = 0.0
	for i in range(1, cl.size()):
		_cum[i] = _cum[i - 1] + cl[i].distance_to(cl[i - 1])
	_hint = -1
	_s0 = _project(start)
	_s1 = _project(end)
	_hint = -1
	return _cl.size() >= 2


## The nearest point is looked for this far (tiles of centreline) either side of the last one, then four times as far, then
## everywhere.
const WINDOW := 6.0


## The distance along the centreline of the point of it nearest `p`.
func _project(p: Vector2) -> float:
	var last := _cl.size() - 2
	var best := {}
	if _hint >= 0:
		var reach := WINDOW
		while reach < 200.0:
			var lo := _hint
			while lo > 0 and _cum[_hint] - _cum[lo] < reach:
				lo -= 1
			var hi := _hint
			while hi < last and _cum[hi + 1] - _cum[_hint] < reach:
				hi += 1
			best = _scan(p, lo, hi)
			if not ((best.i == lo and lo > 0) or (best.i == hi and hi < last)):
				_hint = best.i
				return best.s
			reach *= 4.0
	best = _scan(p, 0, last)
	_hint = best.i
	return best.s


func _scan(p: Vector2, lo: int, hi: int) -> Dictionary:
	var best_d := INF
	var best_i := lo
	var best_s := _cum[lo]
	for i in range(lo, hi + 1):
		var a := _cl[i]
		var ab := _cl[i + 1] - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1.0e-12 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var d := (a + ab * t).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best_i = i
			best_s = _cum[i] + t * (_cum[i + 1] - _cum[i])
	return {"i": best_i, "s": best_s}
