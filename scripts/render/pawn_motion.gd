## ANIM: the motion of the pawns, as pure functions (scripts/render/pawn_node.gd keeps the per-figure state and calls these). EVERYTHING HERE IS RENDER-SIDE: it reads what the rules
## already say (facing, aim, walk_phase, moving, recoil, thrust, reloading, the swing's `swing_t`, a zombie's state and `attack_t`) and never writes any of it, so a run with it plays the same game.
##
## THE IDEAS (the figure is one baked bust, a pair of baked legs and a weapon, so motion is made of transforms, never of new pictures):
##   TURNING. The rules give a facing of four (E, S, W, N). The figure keeps a drawn orientation (an angle) that eases to it in about 100 ms: the view changes where the angle crosses a quarter, and the
##   body is drawn a little narrower the farther the angle is from the middle of its view (a turn is a quick dip to about four fifths of the width, never a line), the weapon's shoulder slides
##   from one view's place to the next. So nothing pops between views.
##   WALKING. The legs' phase starts from the neutral pose when the figure sets off and runs on to the next neutral pose when it stops, so feet never snap from mid-stride to standing; the body
##   bobs at each step, sways with the stride, and leans into its (drawn) speed; the lean and the stride ease in over about 80 ms and out over about 70 ms.
##   WEIGHT. A shot kicks the body and the muzzle up and comes back over about 150 ms; a swing coils, strikes and recovers on the timings of assets/data/melee.json; a reload is a hand to the gun.
##   "Reduce motion" (Settings) damps the bobs, the sways, the leans and the swing's travel to 30 percent.
extends RefCounted

const Prefs := preload("res://scripts/prefs.gd")

## How fast the drawn facing eases to the rules' (per second, exponential): nine tenths of a quarter turn in about 95 ms.
const TURN_RATE := 24.0
## The narrowest the body is drawn in a turn (cos of 0.85 of the way to the edge of its view, at the most) and how much of that a reduced-motion player gets.
const TURN_K := 0.85
## How long a figure takes to get into its stride and out of it (seconds).
const GAIT_IN := 0.08
const GAIT_OUT := 0.07
## How fast the legs run on to the next neutral pose when the figure stops (radians a second).
const SETTLE_RATE := 20.0
## The speed a walk is drawn at (tiles a second: the avatar's), and the speed the lean is full at.
const WALK_V := 3.2
## Reduce motion keeps this share of a bob, a sway, a lean.
const REDUCED := 0.3
## The hips: the body leans and rolls about this line (tiles from the origin, y down).
const HIPS := 0.12
## The weapon's shoulder in each view (screen space, y down): E, S, W, N. (The rules' PIVOT, with the west one mirrored.)
const SHOULDER := [Vector2(0.08, -0.14), Vector2(-0.04, -0.08), Vector2(-0.08, -0.14), Vector2(0.26, -0.22)]
## The way a facing points, radians (E 0, S a quarter turn down the screen), and as a unit vector.
const FACE_ANG := {"E": 0.0, "S": PI / 2.0, "W": PI, "N": -PI / 2.0}
const FACE_DIR := {"E": Vector2(1.0, 0.0), "S": Vector2(0.0, 1.0), "W": Vector2(-1.0, 0.0), "N": Vector2(0.0, -1.0)}
## The swing's numbers if assets/data/melee.json has none.
const MELEE_PATH := "res://assets/data/melee.json"
const MELEE_DEFAULTS := {"hit_at_s": 0.14, "recover_s": 0.21, "arc_deg": 100.0, "swoosh_at_s": 0.09}

## Who is told of a heavy step or blow of one of the dead (a brute's): Callable(at: Vector2 in tiles, strength) (combat_fx.gd `thump`, which shakes the camera a hair); nobody when not set.
static var thump_cb := Callable()
static var _k := 1.0
static var _k_calls := 0
static var _melee := {}
## FEEL: who is told where a foot landed: Callable(at: Vector2 in tiles, dir: Vector2 (the way it goes), power: float) (combat_fx.gd `step_event`: footstep dust); nobody when not set.
static var step_cb := Callable()
## FEEL: the last few shots heard on the screen ({at, ms, who}: a ring), for the crew to turn to (`shot_near`).
const SHOT_MEMORY := 6
static var _shots: Array = []
## The smoothing of the drawn place of the crew and of the dead, worked out once for a frame's time (every figure of a frame has the same).
static var _pk_dt := -1.0
static var _pk_crew := 1.0
static var _pk_dead := 1.0


## 1 for full motion, REDUCED when the player asked for less (read now and then, not at every call: a figure asks a few times a frame).
static func motion() -> float:
	_k_calls += 1
	if _k_calls & 127 == 1:
		_k = REDUCED if Prefs.on("ui", "reduce_motion") else 1.0
	return _k


## The share of the way the drawn place of a figure goes to the rules' in `dt` seconds (the dead's, or the crew's: `crew` rate and `dead` rate, per second).
static func pos_k(dead: bool, dt: float, crew_rate: float, dead_rate: float) -> float:
	if dt != _pk_dt:
		_pk_dt = dt
		_pk_crew = 1.0 - exp(-crew_rate * dt)
		_pk_dead = 1.0 - exp(-dead_rate * dt)
	return _pk_dead if dead else _pk_crew


## The swing's numbers: {"hit": seconds to the blow, "cycle": seconds in all, "half": half the arc in radians, "swoosh": seconds to the whoosh}.
static func melee() -> Dictionary:
	if _melee.is_empty():
		var d := MELEE_DEFAULTS.duplicate()
		if FileAccess.file_exists(MELEE_PATH):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(MELEE_PATH)) == OK and typeof(json.data) == TYPE_DICTIONARY:
				for k in d:
					var v = json.data.get(k)
					if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
						d[k] = float(v)
		_melee = {"hit": float(d.hit_at_s), "cycle": float(d.hit_at_s) + float(d.recover_s), "half": deg_to_rad(float(d.arc_deg)) * 0.5, "swoosh": float(d.swoosh_at_s)}
	return _melee


static func smooth(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## The share of the way a value that eases at `rate` a second has gone in `dt`.
static func ease_k(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)


# ------------------------------------------------------------------- turning --

## The drawn orientation `ori` one frame nearer the rules' `target` (both radians, E 0, S a quarter turn, W a half, N three quarters), the short way, or round the front when the turn is
## a half (so that the face is seen, not the back).
static func turn(ori: float, target: float, dt: float) -> float:
	var d := wrapf(target - ori, -PI, PI)
	if absf(d) > PI - 0.08:
		d = PI if ori < PI * 0.25 else -PI
	if absf(d) < 0.015:
		return target
	return wrapf(ori + d * ease_k(TURN_RATE, dt), -PI, PI)


## The view an orientation shows: "E", "S", "N", and "W" (the east view mirrored).
static func view_of(ori: float) -> String:
	var q := int(roundf(ori / (PI * 0.5)))
	if q == 0:
		return "E"
	if q == 1:
		return "S"
	if q == -1:
		return "N"
	return "W"


## How far an orientation is from the middle of the view it shows, radians (0 to a quarter of a half turn).
static func off_mid(ori: float) -> float:
	return absf(ori - roundf(ori / (PI * 0.5)) * PI * 0.5)


## How wide the body is drawn at an orientation: 1 in the middle of a view, about four fifths at the seam (less so with reduced motion).
static func width(ori: float, k: float) -> float:
	return lerpf(1.0, cos(off_mid(ori) * TURN_K), k)


## Where the weapon's shoulder is at an orientation (screen space): the view's own place, slid to the next view's across the turn.
static func shoulder(ori: float) -> Vector2:
	var u := fposmod(ori, TAU) / (PI * 0.5)
	var i := int(u)
	var t := smooth(u - float(i))
	return SHOULDER[i % 4].lerp(SHOULDER[(i + 1) % 4], t)


# ---------------------------------------------------------------------- body --

## The body's lean about the hips as a transform (screen space): the head goes `lean.x` across and `lean.y` down for each tile it is above the hips.
static func lean_xf(lean: Vector2) -> Transform2D:
	return Transform2D(Vector2(1.0, 0.0), Vector2(-lean.x, 1.0 - lean.y), Vector2(lean.x * HIPS, lean.y * HIPS))


## The legs' phase for a figure that was moving and has stopped: on to the next neutral pose (a multiple of half a turn).
static func settle(phase: float, dt: float) -> float:
	var goal := ceilf(phase / PI - 0.001) * PI
	return minf(goal, phase + SETTLE_RATE * dt)


## Whether a phase is on a neutral pose (legs together).
static func neutral(phase: float) -> bool:
	return absf(phase / PI - roundf(phase / PI)) < 0.012


# --------------------------------------------------------------------- swing --

## What the drawn swing is at one instant: the weapon's angle off the aim (radians), the body's lean along the aim (a share of a full lean), how far the body goes forward along it (tiles), the roll
## of the body, how much it is stretched, and how far the sweep has gone (0 before it, 1 when it is over: the crescent follows it).
class Swing:
	extends RefCounted
	var off := 0.0
	var lean := 0.0
	var step := 0.0
	var roll := 0.0
	var stretch := 0.0
	var sweep := -1.0


## Fills `s` with the swing at `t` seconds from the key. The wind-up (0 to the sweep's start) cocks the weapon back and up and coils the body; the sweep (0.06 s either side of the hit) crosses the
## arc and lunges; the recovery eases back to the carry. `k` is `motion()`.
static func swing_pose(s: Swing, t: float, k: float) -> void:
	var m := melee()
	var hit: float = m.hit
	var cyc: float = m.cycle
	var half: float = m.half
	var a0 := maxf(0.02, hit - 0.06)
	var a1 := hit + 0.06
	s.sweep = -1.0
	if t < 0.0 or t >= cyc:
		s.off = 0.0
		s.lean = 0.0
		s.step = 0.0
		s.roll = 0.0
		s.stretch = 0.0
		return
	if t < a0:
		var u := smooth(t / a0)
		s.off = -half * 1.2 * u * k
		s.lean = -0.55 * u * k
		s.step = -0.03 * u * k
		s.roll = -0.10 * u * k
		s.stretch = -0.03 * u * k
	elif t < a1:
		var v := (t - a0) / (a1 - a0)
		var e := v * v * (3.0 - 2.0 * v)
		s.off = lerpf(-half * 1.2, half * 0.95, e) * k
		s.lean = lerpf(-0.55, 1.0, e) * k
		s.step = lerpf(-0.03, 0.14, e) * k
		s.roll = lerpf(-0.10, 0.12, e) * k
		s.stretch = lerpf(-0.03, 0.05, e) * k
		s.sweep = v
	else:
		var u2 := smooth((t - a1) / (cyc - a1))
		var back := 1.0 - u2
		s.off = half * 0.95 * back * back * k
		s.lean = back * back * k
		s.step = 0.14 * back * back * k
		s.roll = 0.12 * back * back * k
		s.stretch = 0.05 * back * k
		s.sweep = 1.0


# ----------------------------------------------------------------- FEEL: shots --

## A shot was fired at `at` (tiles) by `who` (combat_fx.gd `shot`): the crew near it turn to look for a moment (`shot_near`).
static func note_shot(at: Vector2, who) -> void:
	_shots.append({"at": at, "ms": Time.get_ticks_msec(), "who": who})
	if _shots.size() > SHOT_MEMORY:
		_shots.pop_front()


## Where a shot was fired that `me` (standing at `pos`) is to turn to: the nearest of the last `max_age` seconds' within `reach` tiles that `me` did not fire; Vector2.INF when none.
static func shot_near(pos: Vector2, me, reach: float, max_age: float) -> Vector2:
	if _shots.is_empty():
		return Vector2.INF
	var now := Time.get_ticks_msec()
	var best := Vector2.INF
	var best_d := reach * reach
	for s in _shots:
		if s.who == me or float(now - int(s.ms)) > max_age * 1000.0:
			continue
		var d: float = pos.distance_squared_to(s.at)
		if d < best_d and d > 0.25:
			best_d = d
			best = s.at
	return best


## The facing (E, S, W, N) that looks toward `to` from `from`.
static func facing_toward(from: Vector2, to: Vector2) -> String:
	var d := to - from
	if absf(d.x) > absf(d.y):
		return "E" if d.x > 0.0 else "W"
	return "S" if d.y > 0.0 else "N"


# ------------------------------------------------------- FEEL: a dead one's own --

## A number in [0, 1) from a seed and a salt: an integer hash, so the same figure always gets the same ones and its neighbours others.
static func rnd(seed_i: int, salt: int) -> float:
	var h: int = (seed_i * 2654435761 + salt * 40503 + 12345) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 2246822519) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 3266489917) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


## The skin and dirt of a walker: the picture times one of these (a few percent either way), so a crowd is not a copy.
const DEAD_TINTS := [Color(1.0, 1.0, 1.0), Color(0.88, 0.85, 0.78), Color(0.92, 0.98, 0.86), Color(0.88, 0.92, 0.97), Color(1.0, 0.88, 0.85), Color(0.82, 0.80, 0.76)]


## What one of the dead has of its own (made once from its seed; nothing in it is read by the rules or saved): its gait (how fast its limbs cycle, where in the cycle it starts), how it
## stands (a lean and a tilt of the head), how it moves its arms and legs (the arms' carry, a leg it drags, which), how big it is and the dirt on it, how hard its steps land.
class Dead:
	extends RefCounted
	var gait := 1.0
	var ph := 0.0
	var bob := 1.0
	var sway := 1.0
	var lean := 0.0
	var tilt := 0.0
	var gimp := false
	var side := 1.0
	var arm := 0.0
	var size := 1.0
	var tint := Color.WHITE
	var weight := 0.0
	var breath := 0.0


## `kind` walker, runner or brute. A runner cycles its limbs a good deal faster, leans harder into it and is drawn grey and gaunt; a brute is slower, heavier (its steps land) and darker.
static func dead_variant(seed_i: int, kind: String) -> Dead:
	var d := Dead.new()
	var r := func(k: int) -> float: return rnd(seed_i, k)
	d.ph = float(r.call(1)) * TAU
	d.breath = float(r.call(2)) * TAU
	d.side = 1.0 if float(r.call(3)) < 0.5 else -1.0
	var jit := 0.96 + 0.08 * float(r.call(4))
	match kind:
		"runner":
			d.gait = lerpf(1.2, 1.5, float(r.call(5)))
			d.bob = lerpf(0.85, 1.2, float(r.call(6)))
			d.sway = lerpf(0.6, 1.0, float(r.call(7)))
			d.lean = lerpf(0.05, 0.13, float(r.call(8)))
			d.tilt = (float(r.call(9)) - 0.5) * 0.06
			d.arm = lerpf(-0.1, 0.1, float(r.call(10)))
			d.size = lerpf(0.95, 1.04, float(r.call(11)))
			d.tint = Color(0.90, 0.94, 0.97) * jit
			d.weight = 0.0
		"brute":
			d.gait = lerpf(0.72, 0.88, float(r.call(5)))
			d.bob = lerpf(0.9, 1.2, float(r.call(6)))
			d.sway = lerpf(1.1, 1.5, float(r.call(7)))
			d.lean = lerpf(0.0, 0.05, float(r.call(8)))
			d.tilt = (float(r.call(9)) - 0.5) * 0.04
			d.arm = lerpf(-0.05, 0.2, float(r.call(10)))
			d.size = lerpf(0.97, 1.05, float(r.call(11)))
			d.tint = Color(0.93, 0.92, 0.89) * jit
			d.weight = 1.0
		_:
			d.gait = lerpf(0.8, 1.2, float(r.call(5)))
			d.bob = lerpf(0.7, 1.3, float(r.call(6)))
			d.sway = lerpf(0.7, 1.3, float(r.call(7)))
			d.lean = lerpf(-0.03, 0.09, float(r.call(8)))
			d.tilt = (float(r.call(9)) - 0.5) * 0.18
			d.arm = lerpf(-0.30, 0.40, float(r.call(10)))
			d.size = lerpf(0.94, 1.06, float(r.call(11)))
			d.gimp = float(r.call(12)) < 0.22
			d.tint = (DEAD_TINTS[int(float(r.call(13)) * float(DEAD_TINTS.size())) % DEAD_TINTS.size()] as Color) * jit
			d.weight = 0.25
	d.tint.a = 1.0
	return d


# -------------------------------------------------------------------- reload --

## What a reload shows at one instant: how far the weapon is lowered to be loaded (0 to 1), where the loading hand is (in the weapon's own frame, with how far along its trip it is; `hand_on`
## false while it is away), how far the fore-end is pumped (-1 to 1), and a small lift of the whole figure at the end.
class Reload:
	extends RefCounted
	var low := 0.0
	var hand := Vector2.ZERO
	var hand_on := false
	var pump := 0.0
	var click := 0.0


## Fills `r` with the reload at progress `p` (0 to 1) of `n` loadings (a shell gun loads one at a time; a magazine gun, n 1, has the magazine out and in).
static func reload_pose(r: Reload, p: float, n: int, shell: bool) -> void:
	var lead := smooth(p / 0.08)
	var tail := 1.0 - smooth((p - 0.92) / 0.08)
	r.low = lead * tail
	r.pump = 0.0
	r.click = 0.0
	r.hand_on = false
	var body_p := clampf((p - 0.06) / 0.80, 0.0, 1.0)
	var cycles := maxi(n, 1)
	var c := body_p * float(cycles)
	var u := c - floorf(c)
	if p > 0.06 and p < 0.86:
		r.hand_on = true
		# belt to receiver (0 to 0.45), the shell goes in (0.45 to 0.6), back to the belt (0.6 to 1)
		var go := smooth(u / 0.45)
		var back := smooth((u - 0.6) / 0.4)
		var at := go - back
		var belt := Vector2(-0.02, 0.46)
		var rec := Vector2(0.24, 0.06)
		r.hand = belt.lerp(rec, at)
		if u > 0.45 and u < 0.62:
			r.click = sin((u - 0.45) / 0.17 * PI)
	if p >= 0.86 and p < 1.0:
		# the pump (a bolt): the fore-end goes back and forward
		var q := (p - 0.86) / 0.14
		r.pump = sin(q * PI * 2.0) * (1.0 - q * 0.3)
		if shell:
			r.click = maxf(r.click, absf(r.pump))
