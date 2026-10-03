## The autopilot of the live drive (round 21): Tab hands the wheel to the squad's best driver, who drives the road alone, at
## 0.8 of cruise, slower than the player can and careful at every stop. Pure (no nodes, no clock, no random): the same car and
## road give the same hands, to the bit. It is what an escape for a long trip is made of, so it must always get there.
##
##   Autopilot.drive(car, road, dt, aware) -> {"throttle": -1..1, "steer": -1..1}
##
## `car` is a CarSim (the autopilot keeps its scratch in `car.ap`), `road` is a road site's "road" (its `path`: a car-wide
## passable line from start to end, which the generator has proved). `aware` is what the scene knows and the car does not; every
## key is optional:
##   "probe"    Callable(Vector2) -> {"solid", "ground", "dyn"}: the same probe the car is stepped with (without it the car's own
##              last probe is used: `car.last_probe`)
##   "dead"     Array of the dead near the road: Vector2s, Dictionaries with "pos" (or "x" and "y") and optionally "kind" ("brute"
##              is the one that matters: the others are ploughed), or objects with x and y (and "kind")
##   "halt"     bool (alias "stop"): an open stop's card, a squad out working: stand still, and go on when it is false
##   "slow"     bool: something the scene saw: keep to CAUTION_SPEED
##   "stop_at"  float: the distance (tiles, from the car's middle) of something to stop short of
##
## HOW. Pure pursuit: the car aims at the point of `path` `max(6, 0.8 x speed, 0.9 x its length)` ahead of the nearest one, so a
## gap that the path goes through is taken, and a car that is off the path finds it again; where a solid stands close to the path
## the path is first nudged to the middle of the free space (a long body in a 4-wide gap must be in the middle of it). The speed
## is 0.8 of cruise (4.6 t/s and more, above the 4.0 that runs the dead over). The dead do NOT slow it: a car that creeps through them at
## 2.5 t/s kills none, shoves the ones in front of its nose along the road, and the leg takes three times as long (round 21 review:
## "the autopilot never recovers its speed"); the walkers, the runners and the brutes are ploughed as the player would plough them
## (RUN_OVER_HP each, BRUTE_HP a brute, which is the price of a leg that ends). Only a car too hurt to pay for the dead of its corridor
## (more than its hp less HP_RESERVE) creeps through them at CAUTION_SPEED (above the 2 t/s under which they claw): it must arrive as a
## car. Walls and wrecks are another matter: the speed is eased down to CAUTION_SPEED
## as the nose comes to a solid at the corridor's edge (a gap's wall). A solid IN the way (within the
## car's own width of the path) is a place to stop short of: the speed falls by what the brakes do comfortably so that the car
## stands STOP_MARGIN tiles from it and does not ram it (so does `stop_at`). An open card stops the car. A car that has been
## knocked, or has not moved for STUCK_S seconds while it wants to, backs away for BACK_S and goes on gently.
## The corridor is looked at CHECK_EVERY seconds apart (about 10 probes a step), not every step.
extends RefCounted

const TARGET_SHARE := 0.8
const CAUTION_SPEED := 2.5
## The car keeps this much hp after ploughing the dead of the corridor (a hurt car creeps through them instead).
const HP_RESERVE := 4.0
const LOOK_MIN := 6.0
const LOOK_MIN_FOOT := 3.0
const LOOK_GAIN := 0.8
const CORRIDOR_LEN := 14.0
## How far along the path (tiles) the corridor is looked at.
const LOOK_ROWS := [1, 2, 3, 4, 5, 6, 8, 10, 12, 14]
const CHECK_EVERY := 0.15
const COMFORT_BRAKE := 6.0
const STOP_MARGIN := 1.5
const STUCK_S := 1.5
const BACK_S := 1.2
const CAREFUL_S := 5.0
## The corridor is the body's width and this much either side of it (3 wide for a car): a solid in the body's own width is in the
## way, one in the margin is at the edge.
const EDGE_MARGIN := 0.4
## Centring the path in a tight place: look this far beyond the body's side, measure the room up to CENTRE_REACH in CENTRE_STEP steps,
## move by half the difference (at most CENTRE_MAX), the shifts averaged over this many points either side.
const CENTRE_NEAR := 1.0
const CENTRE_REACH := 2.5
const CENTRE_STEP := 0.25
const CENTRE_MAX := 1.0
const CENTRE_SMOOTH := 3
## What is at the edge of the corridor slows the car only when its nose is within EDGE_NEAR + (the speed it is held to - CAUTION)
## / EDGE_EASE tiles of it: 2.5 t/s at the wall, the full speed from about 11 tiles away.
const EDGE_NEAR := 2.0
const EDGE_EASE := 0.45


static func drive(car, road: Dictionary, dt: float, aware: Dictionary) -> Dictionary:
	var st: Dictionary = car.ap
	var path: Dictionary = _path(car, road, st, aware)
	if path.is_empty():
		return {"throttle": 0.0, "steer": 0.0}
	var near: Dictionary = _nearest(path, car.pos, st)
	var v: float = car.speed
	var look: float = maxf(maxf(LOOK_MIN_FOOT if car.foot else LOOK_MIN, LOOK_GAIN * maxf(v, 0.0)), 0.9 * car.length)
	var target: Vector2 = _point_at(path, float(near.s) + look)
	var to: Vector2 = target - car.pos
	var err: float = wrapf(to.angle() - car.heading, -PI, PI)
	# the steering that makes the curve through the target at this speed
	var chord: float = maxf(to.length(), 1.0)
	var need: float = 2.0 * sin(clampf(err, -1.2, 1.2)) * maxf(v, 1.0) / chord
	var avail: float = maxf(car.yaw_per_steer(maxf(v, 0.5)), 0.05)
	var steer: float = clampf(need / avail, -1.0, 1.0)
	if car.foot:
		steer = clampf(err * 3.0, -1.0, 1.0)

	# what is ahead
	st["timer"] = float(st.get("timer", 0.0)) - dt
	if st.timer <= 0.0 or not st.has("caution"):
		st["timer"] = CHECK_EVERY
		st["caution"] = _look(car, path, float(near.s), aware)
	var caution: Dictionary = st.caution
	var vt: float = TARGET_SHARE * car.cruise
	var halt: bool = bool(aware.get("halt", aware.get("stop", false)))
	var stop_at: float = minf(float(caution.stop), float(aware.get("stop_at", INF)))
	if halt:
		vt = 0.0
	else:
		if stop_at < INF:
			var room: float = maxf(0.0, stop_at - car.length * 0.5 - STOP_MARGIN)
			vt = minf(vt, sqrt(2.0 * COMFORT_BRAKE * room))
		var hurt: bool = float(caution.cost) > 0.0 and float(caution.cost) > float(car.hp) - HP_RESERVE
		if hurt or bool(aware.get("slow", false)):
			vt = minf(vt, CAUTION_SPEED)
		if float(caution.edge) < INF:
			# something at the edge of the corridor (a gap's wall): the nearer the nose is to it the slower
			var reach: float = maxf(0.0, float(caution.edge) - car.length * 0.5 - EDGE_NEAR)
			vt = minf(vt, CAUTION_SPEED + EDGE_EASE * reach)
	if absf(err) > 0.6:
		vt = minf(vt, 3.0)    # pointing well off the path: sort that out slowly
	if float(st.get("careful", 0.0)) > 0.0:
		st["careful"] = float(st.careful) - dt    # after a knock: gently for a while
		vt = minf(vt, CAUTION_SPEED)

	# the speed
	var throttle := 0.0
	var gap: float = vt - v
	if vt < 0.05:
		throttle = -clampf(v * 1.5, 0.0, 1.0) if v > 0.05 else 0.0
	elif gap > 0.0:
		throttle = clampf(car.hold_throttle(vt) + gap * 0.8 * car.ACCEL / car.accel_rate(), 0.0, 1.0)
	elif gap > -0.3:
		throttle = car.hold_throttle(vt) * 0.5
	else:
		throttle = -clampf(-gap * car.BRAKE / car.brake_rate(), 0.0, 1.0)

	# a knock, or stuck (wants to go and does not, for a while): back a little, the wheel the other way (the nose swings
	# the other way in reverse), then try again, gently
	if halt:
		st["back"] = 0.0
		st["still"] = 0.0
		return {"throttle": throttle, "steer": 0.0 if absf(v) < 0.3 else steer}
	if car.hit_age < 0.05 and float(st.get("back", 0.0)) <= 0.0:
		st["back"] = BACK_S
		st["careful"] = CAREFUL_S
	if float(st.get("back", 0.0)) > 0.0:
		st["back"] = float(st.back) - dt
		return {"throttle": -1.0, "steer": -steer}
	if vt > 1.0 and absf(v) < 0.4:
		st["still"] = float(st.get("still", 0.0)) + dt
		if float(st.still) >= STUCK_S:
			st["still"] = 0.0
			st["back"] = BACK_S
			st["careful"] = CAREFUL_S
	else:
		st["still"] = 0.0
	return {"throttle": throttle, "steer": steer}


# ----------------------------------------------------------------------------------------------- the path --

## The road's path from the car's end of it, as {"pts", "cum", "total", "centred"} (cached in the car's scratch). Once a probe is
## at hand the path is nudged toward the middle of the free space where a solid stands close to it (the walls of a roadblock's
## gap: a car in a 4-wide gap with a 4-long body needs to be in its middle, whatever the road's slant): see `_centre`.
static func _path(car, road: Dictionary, st: Dictionary, aware: Dictionary) -> Dictionary:
	var probe: Callable = aware.get("probe", car.last_probe)
	if st.has("path") and is_same(st.get("road"), road) and (bool(st.path.centred) or not probe.is_valid()):
		return st.path
	var raw = road.get("path", PackedVector2Array())
	var pts: PackedVector2Array = PackedVector2Array(raw) if not raw is PackedVector2Array else raw
	if pts.size() < 2:
		return {}
	var start := Vector2(road.get("start", pts[0]))
	if pts[0].distance_to(start) > pts[pts.size() - 1].distance_to(start):
		var rev := PackedVector2Array()
		for i in range(pts.size() - 1, -1, -1):
			rev.append(pts[i])
		pts = rev
	var centred := false
	if probe.is_valid():
		pts = _centre(pts, probe, car.width * 0.5)
		centred = true
	var cum := PackedFloat64Array()
	cum.resize(pts.size())
	cum[0] = 0.0
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	st["road"] = road
	st["path"] = {"pts": pts, "cum": cum, "total": cum[cum.size() - 1], "centred": centred}
	st["hint"] = -1
	st["caution"] = {"stop": INF, "edge": INF, "cost": 0.0}
	return st.path


## The path nudged to the middle of the free space: at each point, if there is a solid within a body's half width and CENTRE_NEAR
## of it to either side, it moves by half the difference of the room each side has (at most CENTRE_MAX), the shifts smoothed over
## a few points so that the line stays gentle.
static func _centre(pts: PackedVector2Array, probe: Callable, half: float) -> PackedVector2Array:
	var n := pts.size()
	var shift := PackedFloat64Array()
	shift.resize(n)
	var sides := PackedVector2Array()
	sides.resize(n)
	var any := false
	for i in n:
		var dir: Vector2 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x)
		sides[i] = side
		var p: Vector2 = pts[i]
		if not (_solid(probe.call(p + side * (half + CENTRE_NEAR))) or _solid(probe.call(p - side * (half + CENTRE_NEAR)))):
			continue
		var right := _room(probe, p, side, half)
		var left := _room(probe, p, -side, half)
		shift[i] = clampf((right - left) * 0.5, -CENTRE_MAX, CENTRE_MAX)
		any = any or shift[i] != 0.0
	if not any:
		return pts
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var sum := 0.0
		var cnt := 0.0
		for j in range(maxi(0, i - CENTRE_SMOOTH), mini(n, i + CENTRE_SMOOTH + 1)):
			sum += shift[j]
			cnt += 1.0
		out[i] = pts[i] + sides[i] * (sum / cnt)
	return out


## The room (tiles) between the edge of a body of half-width `half` at `p` and the first solid in the direction `dir`, up to CENTRE_REACH.
static func _room(probe: Callable, p: Vector2, dir: Vector2, half: float) -> float:
	var o := half
	while o < half + CENTRE_REACH:
		if _solid(probe.call(p + dir * o)):
			return o - half
		o += CENTRE_STEP
	return CENTRE_REACH


## The nearest point is looked for this far (tiles of path) either side of the last one, then three times as far, then everywhere.
const WINDOW := 3.0


## The point of the path nearest `p`: {"s": the distance along the path, "d": how far off it is}.
static func _nearest(path: Dictionary, p: Vector2, st: Dictionary) -> Dictionary:
	var pts: PackedVector2Array = path.pts
	var cum: PackedFloat64Array = path.cum
	var last := pts.size() - 2
	var hint: int = int(st.get("hint", -1))
	var best := {}
	if hint >= 0:
		var reach := WINDOW
		while reach < 200.0:
			var lo := hint
			while lo > 0 and cum[hint] - cum[lo] < reach:
				lo -= 1
			var hi := hint
			while hi < last and cum[hi + 1] - cum[hint] < reach:
				hi += 1
			best = _scan(pts, cum, p, lo, hi)
			if not ((best.i == lo and lo > 0) or (best.i == hi and hi < last)):
				st["hint"] = best.i
				return best
			reach *= 4.0
	best = _scan(pts, cum, p, 0, last)
	st["hint"] = best.i
	return best


static func _scan(pts: PackedVector2Array, cum: PackedFloat64Array, p: Vector2, lo: int, hi: int) -> Dictionary:
	var best_d := INF
	var best_i := lo
	var best_s: float = cum[lo]
	for i in range(lo, hi + 1):
		var a: Vector2 = pts[i]
		var ab: Vector2 = pts[i + 1] - a
		var l2: float = ab.length_squared()
		var t: float = 0.0 if l2 < 1.0e-12 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var d: float = (a + ab * t).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best_i = i
			best_s = cum[i] + t * (cum[i + 1] - cum[i])
	return {"i": best_i, "s": best_s, "d": sqrt(best_d)}


## The point `s` along the path (past its end: on along its last direction).
static func _point_at(path: Dictionary, s: float) -> Vector2:
	var pts: PackedVector2Array = path.pts
	var cum: PackedFloat64Array = path.cum
	var n := pts.size()
	if s <= 0.0:
		return pts[0]
	if s >= float(path.total):
		var dir: Vector2 = (pts[n - 1] - pts[n - 2]).normalized()
		return pts[n - 1] + dir * (s - float(path.total))
	var i: int = clampi(cum.bsearch(s) - 1, 0, n - 2)
	var seg: float = cum[i + 1] - cum[i]
	return pts[i].lerp(pts[i + 1], 0.0 if seg < 1.0e-9 else (s - cum[i]) / seg)


# --------------------------------------------------------------------------------------------- what is ahead --

## {"stop": the distance of what is in the way (INF for nothing), "edge": the distance of the first thing at the edge of the
## corridor, "cost": the hp that ploughing the dead in it ahead would cost (RUN_OVER_HP each, BRUTE_HP a brute)}.
static func _look(car, path: Dictionary, s: float, aware: Dictionary) -> Dictionary:
	var stop := INF
	var edge := INF
	var cost := 0.0
	var probe: Callable = aware.get("probe", car.last_probe)
	var half: float = car.width * 0.5
	var block_offs := [0.0, -half + 0.3, half - 0.3]
	var edge_offs := [-half - EDGE_MARGIN, half + EDGE_MARGIN]
	if probe.is_valid():
		var pts: PackedVector2Array = path.pts
		var cum: PackedFloat64Array = path.cum
		var last := pts.size() - 2
		# every tile for the first six, every second one beyond: a wall is never thinner than two
		for k in LOOK_ROWS:
			var at_s: float = s + float(k)
			if at_s >= float(path.total):
				break
			var i: int = clampi(cum.bsearch(at_s) - 1, 0, last)
			var a: Vector2 = pts[i]
			var seg: Vector2 = pts[i + 1] - a
			var l: float = cum[i + 1] - cum[i]
			var at: Vector2 = a + seg * (0.0 if l < 1.0e-9 else (at_s - cum[i]) / l)
			var dir: Vector2 = seg.normalized()
			var side := Vector2(-dir.y, dir.x)
			var blocked := false
			for off in block_offs:
				if _solid(probe.call(at + side * float(off))):
					blocked = true
					break
			if blocked:
				stop = float(k)
				break
			if edge == INF:
				for off in edge_offs:
					if _solid(probe.call(at + side * float(off))):
						edge = float(k)
						break
	var dead = aware.get("dead", [])
	if dead is Array and not dead.is_empty() and not car.foot:    # (on foot nothing is run over: the walk is as slow as the caution)
		var fwd: Vector2 = car.forward()
		var right := Vector2(-fwd.y, fwd.x)
		for z in dead:
			var rel: Vector2 = _pos_of(z) - car.pos
			var f: float = rel.dot(fwd)
			if f > 0.0 and f <= CORRIDOR_LEN + car.length * 0.5 and absf(rel.dot(right)) <= half + EDGE_MARGIN + 0.3:
				cost += car.BRUTE_HP if _is_brute(z) else car.RUN_OVER_HP
	return {"stop": stop, "edge": edge, "cost": cost}


static func _is_brute(z) -> bool:
	if z is Dictionary:
		return String(z.get("kind", "")) == "brute"
	if z is Object:
		return String(z.get("kind")) == "brute"
	return false


static func _solid(q: Dictionary) -> bool:
	return bool(q.get("solid", false)) or String(q.get("dyn", "")) != ""


static func _pos_of(z) -> Vector2:
	if z is Vector2:
		return z
	if z is Dictionary:
		if z.has("pos"):
			return Vector2(z.pos)
		return Vector2(float(z.get("x", 0.0)), float(z.get("y", 0.0)))
	if z is Object:
		return Vector2(float(z.get("x")), float(z.get("y")))
	return Vector2.ZERO
