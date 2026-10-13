## ROUND 11: the human combat animation (prison only, behind PawnNode.hanim; `--nohanim` turns it off). Everything is drawn live over the baked 4-view bust and the 16-heading renders alike (a
## person's render has no arms or gun, so the same overlay serves both): the raise, the kick of each gun, the head jerk, the arms, the magazine and the shell in the hand, the flinch and the
## blood on the clothes, the limp, the downed kneel and crawl, the grab of a bite, the fall in the direction of the blow and the pool under the body. This file holds the state and the pure
## pose maths; pawn_node.gd calls it from the human pose code (`_anim_person`, `_draw_person`, `_gun`, `_draw_downed`, `_draw_fallen`).
extends RefCounted

const S := preload("res://scripts/render/shapes.gd")
const PawnMotion := preload("res://scripts/render/pawn_motion.gd")

## Who is asked where a blow came from: Callable(at: Vector2 in tiles) -> Vector2, the way the nearest of the dead pushes at that place (zero when none is near). Set by prison_game.gd.
static var threat_cb := Callable()

const RAISE_S := 0.2
## The feel of each gun: body (the push back of the whole upper body, a share of the old one), rise (the muzzle's climb), roll (the upper body's rock, radians), head (the head's jerk, radians),
## keep (seconds the kick takes to settle), work ("pump", "bolt" or "": the hand on the fore-end after a shot), work_at/work_len (when and how long).
const PROFILE := {
	"shotgun": {"body": 1.9, "rise": 1.7, "roll": 0.10, "head": 0.20, "work": "pump", "work_at": 0.30, "work_len": 0.28},
	"hunting": {"body": 1.5, "rise": 1.4, "roll": 0.08, "head": 0.16, "work": "bolt", "work_at": 0.30, "work_len": 0.34},
	"rifle": {"body": 1.0, "rise": 1.0, "roll": 0.05, "head": 0.11, "work": "bolt", "work_at": 0.26, "work_len": 0.30},
	"service": {"body": 1.1, "rise": 1.1, "roll": 0.055, "head": 0.12, "work": "", "work_at": 0.0, "work_len": 0.0},
	"smg": {"body": 0.45, "rise": 0.5, "roll": 0.025, "head": 0.05, "work": "", "work_at": 0.0, "work_len": 0.0},
	"pistol": {"body": 0.7, "rise": 0.9, "roll": 0.04, "head": 0.08, "work": "", "work_at": 0.0, "work_len": 0.0},
}
const BRASS := Color("#d8a93a")
const BRASS_DK := Color("#8a6a1e")
const SHELL_RED := Color("#b6372e")
const MAG := Color("#2a2c30")
const BLOOD := Color(0.42, 0.04, 0.05)


static func profile(weapon: String) -> Dictionary:
	return PROFILE.get(weapon, PROFILE.rifle)


## One person's animation state (the clocks the rules do not keep).
class State:
	extends RefCounted
	var up := 0.0               # the raise: 0 carried, 1 shouldered (0.2 s)
	var hp_seen := -1.0
	var hurt_t := 9.0           # seconds since the last hit
	var hurt_dir := Vector2.ZERO    # the way the blow pushed (screen, unit)
	var stain := 0.0            # blood on the clothes, 0 to 1
	var bite_t := 0.0           # a grab: counts down while the biting goes on
	var dn_t := 0.0             # seconds downed
	var was_down := false
	var getup_t := 9.0          # seconds since the getup began
	var dead_t := -1.0          # seconds since the death (-1 alive)
	var fall_kind := 0          # 0 sideways, 1 toward the camera, 2 away
	var side := 1.0             # +1 falls to the right of the screen, -1 to the left
	var seed := 0.0
	var pool: PackedVector2Array = PackedVector2Array()
	var limp := false
	var first := true

	func _init(sd: float) -> void:
		seed = sd
		for i in 14:
			var a := float(i) / 14.0 * TAU
			var r := 0.78 + 0.22 * sin(a * 3.0 + seed * 11.0) + 0.12 * sin(a * 5.0 + seed * 5.0)
			pool.append(Vector2(cos(a), sin(a)) * r)

	## One frame. `up_want` the gun is shouldered; `at` where the person stands (tiles).
	func tick(p, dt: float, up_want: bool, at: Vector2, threat: Callable = Callable()) -> void:
		up = move_toward(up, 1.0 if up_want else 0.0, dt / RAISE_S)
		hurt_t += dt
		bite_t = maxf(0.0, bite_t - dt)
		var hp := float(p.hp)
		if hp_seen < 0.0:
			hp_seen = hp
		if hp < hp_seen - 0.5 and not p.dead:
			hurt_t = 0.0
			stain = minf(1.0, stain + (hp_seen - hp) / 45.0)
			bite_t = 1.1
			hurt_dir = push_from(at, threat)
		hp_seen = hp
		limp = hp < 35.0 and not p.dead and not p.downed
		if p.downed and not p.dead:
			dn_t += dt
			was_down = true
			if push_from(at, threat) != Vector2.ZERO:
				bite_t = 0.3    # (a dead one is on them: they fight it off)
		else:
			if was_down and not p.dead:
				getup_t = 0.0
			was_down = false
			dn_t = 0.0
		getup_t += dt
		if p.dead:
			if dead_t < 0.0:
				dead_t = 99.0 if first else 0.0
				var d := push_from(at, threat)
				if d == Vector2.ZERO:
					d = Vector2(1.0 if seed > 0.5 else -1.0, 0.0)
				hurt_dir = d
				side = 1.0 if d.x >= 0.0 else -1.0
				fall_kind = 0 if absf(d.x) > absf(d.y) * 0.8 else (1 if d.y > 0.0 else 2)
				stain = maxf(stain, 0.7)
			else:
				dead_t += dt
		else:
			dead_t = -1.0
		first = false

	func push_from(at: Vector2, threat: Callable) -> Vector2:
		if threat.is_valid():
			var d: Vector2 = threat.call(at)
			if d != Vector2.ZERO:
				return d.normalized()
		return Vector2.ZERO


## The flinch: how far (0 to 1) the body has snapped away from a hit; falls away in about 0.35 s.
static func flinch_k(st: State) -> float:
	return exp(-st.hurt_t * 8.0) if st.hurt_t < 0.6 else 0.0


## The fall as a pose at `t` seconds: {"rot": radians about the feet, "sy": the squash, "off": tiles, "flung": the arms thrown (0 to 1)}. Six beats: the hit, the knees, the topple, the landing,
## the bounce, the rest. `kind` 0 sideways, 1 toward the camera, 2 away; `side` +-1.
static func fall_pose(t: float, kind: int, side: float, dir: Vector2) -> Dictionary:
	var rot := 0.0
	var sy := 1.0
	var off := Vector2.ZERO
	var flung := 0.0
	var end_rot := PI / 2.0 * side
	if t < 0.10:
		var b := t / 0.10
		rot = side * 0.10 * b
		off = dir * 0.05 * b
		flung = 0.3 * b
	elif t < 0.28:
		var u := (t - 0.10) / 0.18
		rot = side * (0.10 + 0.14 * u)
		sy = 1.0 - 0.22 * u
		off = dir * (0.05 + 0.04 * u)
		flung = 0.3 + 0.2 * u
	elif t < 0.55:
		var u2 := (t - 0.28) / 0.27
		var e := u2 * u2
		rot = lerpf(side * 0.24, end_rot, e)
		sy = lerpf(0.78, 1.0, e)
		off = dir * lerpf(0.09, 0.2, e)
		flung = 0.5 + 0.5 * u2
	elif t < 0.70:
		var u3 := (t - 0.55) / 0.15
		rot = end_rot * (1.0 + 0.06 * sin(u3 * PI))
		off = dir * 0.2
		flung = 1.0
	else:
		rot = end_rot
		off = dir * 0.2
		flung = 1.0
	if kind != 0:
		# toward or away from the camera: it does not turn on the screen, it folds and goes flat
		var k := clampf(t / 0.62, 0.0, 1.0)
		var e2 := k * k
		rot = side * lerpf(0.0, 0.2, minf(1.0, t / 0.3)) * (1.0 - e2) + side * 0.12 * e2
		sy = lerpf(1.0, 0.42, e2) if t >= 0.1 else 1.0 - 0.1 * (t / 0.1)
		off = Vector2(dir.x * 0.1 * e2, (0.3 if kind == 1 else -0.3) * e2)
		if t > 0.62:
			sy = 0.42 + 0.03 * sin((t - 0.62) / 0.12 * PI) * (1.0 if t < 0.74 else 0.0)
	return {"rot": rot, "sy": sy, "off": off, "flung": flung}


## The downed pose: kneel (0 to 0.35 s), topple (to 0.8 s), then lie with a hand to the wound and crawl or thrash. `getup` > 0: the way back (0 lying, 1 standing).
static func down_pose(t: float, bitten: bool, seed: float, side: float) -> Dictionary:
	var rot := 0.0
	var sy := 1.0
	var off := Vector2.ZERO
	var lie := 0.0
	if t < 0.35:
		var u := PawnMotion.smooth(t / 0.35)
		sy = lerpf(1.0, 0.78, u)
		rot = side * 0.16 * u
		off = Vector2(0.0, 0.05 * u)
	elif t < 0.8:
		var u2 := PawnMotion.smooth((t - 0.35) / 0.45)
		sy = lerpf(0.78, 1.0, u2)
		rot = lerpf(side * 0.16, side * PI / 2.0, u2 * u2)
		lie = u2
	else:
		rot = side * PI / 2.0
		lie = 1.0
		var w := t - 0.8
		if bitten:
			rot += sin(w * 24.0) * 0.07 + sin(w * 9.0 + seed * 9.0) * 0.06
			off = Vector2(sin(w * 19.0) * 0.025, 0.0)
		else:
			# a slow crawl: it drags itself a hand's width forward and rests, with the head lifting
			var c := sin(w * 1.9 + seed * 6.0)
			off = Vector2(side * 0.06 * c, 0.0)
			rot += sin(w * 3.8 + seed * 6.0) * 0.035
	return {"rot": rot, "sy": sy, "off": off, "lie": lie}


## The getup (`t` seconds since it began): lying to kneeling to standing, in 0.55 s. Returns {"rot","sy","off"} or {} when it is over.
static func getup_pose(t: float, side: float) -> Dictionary:
	if t >= 0.55:
		return {}
	var k := 1.0 - t / 0.55
	return down_pose(0.35 + 0.45 * k, false, 0.0, side)


## How far the pool under a body has spread: 0 to 1 over about 5 seconds, after a pause of 0.3 s.
static func pool_k(t: float) -> float:
	return PawnMotion.smooth((t - 0.3) / 5.0)


# ------------------------------------------------------------------ drawing helpers --

## A pool of blood on the ground at the figure's feet: an irregular, flattened blob of radius `r` tiles with a wet highlight.
static func draw_pool(pen, st: State, r: float, alpha: float = 1.0) -> void:
	if r <= 0.02:
		return
	var pts := PackedVector2Array()
	for v in st.pool:
		pts.append(Vector2(v.x * r, v.y * r * 0.55))
	pen.draw_colored_polygon(pts, Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.9 * alpha))
	var pts2 := PackedVector2Array()
	for v in st.pool:
		pts2.append(Vector2(v.x * r * 0.7 - r * 0.08, v.y * r * 0.38 - r * 0.05))
	pen.draw_colored_polygon(pts2, Color(0.55, 0.07, 0.08, 0.6 * alpha))
	pen.draw_circle(Vector2(-r * 0.25, -r * 0.12), r * 0.1, Color(0.8, 0.3, 0.3, 0.25 * alpha))


## Blood on the clothes: a few blots on the trunk, more as the person is hurt (positions fixed by the person's seed).
static func draw_stains(pen, st: State) -> void:
	var n := int(ceilf(st.stain * 5.0))
	for i in n:
		var a := st.seed * 17.0 + float(i) * 2.399
		var c := Vector2(0.14 * sin(a * 3.1), -0.06 + 0.16 * sin(a * 1.7 + 1.0))
		var r := 0.035 + 0.03 * fposmod(a * 7.0, 1.0) * (0.5 + st.stain)
		pen.draw_circle(c, r, Color(0.5, 0.04, 0.05, 0.85))
		pen.draw_circle(c + Vector2(0.015, 0.02), r * 0.5, Color(0.32, 0.02, 0.03, 0.9))


## A sleeve and a hand from the point `a` to the point `b` (the frame the caller has set).
static func draw_arm(pen, a: Vector2, b: Vector2, sleeve: Color, skin: Color, hand: bool = true) -> void:
	var d := b - a
	var end := b - d.normalized() * 0.03 if d.length() > 0.05 else b
	pen.draw_line(a, end, S.INK, 0.15, true)
	pen.draw_line(a, end, sleeve, 0.1, true)
	if hand:
		pen.draw_circle(b, 0.075, S.INK)
		pen.draw_circle(b, 0.055, skin)


## A magazine (a slim dark box with a brass tip) at `at`, turned by `rot`.
static func draw_mag(pen, at: Vector2, rot: float) -> void:
	var xf := Transform2D(rot, at)
	var pts := PackedVector2Array([Vector2(-0.035, -0.09), Vector2(0.035, -0.09), Vector2(0.035, 0.09), Vector2(-0.035, 0.09)])
	var out := PackedVector2Array()
	for p in pts:
		out.append(xf * p)
	pen.draw_colored_polygon(out, MAG)
	pen.draw_polyline(PackedVector2Array([out[0], out[1], out[2], out[3], out[0]]), S.INK, 0.025, true)
	pen.draw_circle(xf * Vector2(0.0, -0.075), 0.022, BRASS)


## A shotgun shell (a red tube with a brass base).
static func draw_shell(pen, at: Vector2, rot: float) -> void:
	var xf := Transform2D(rot, at)
	var tube := PackedVector2Array([xf * Vector2(-0.03, -0.07), xf * Vector2(0.03, -0.07), xf * Vector2(0.03, 0.02), xf * Vector2(-0.03, 0.02)])
	var base := PackedVector2Array([xf * Vector2(-0.03, 0.02), xf * Vector2(0.03, 0.02), xf * Vector2(0.03, 0.07), xf * Vector2(-0.03, 0.07)])
	pen.draw_colored_polygon(tube, SHELL_RED)
	pen.draw_colored_polygon(base, BRASS)
	pen.draw_polyline(PackedVector2Array([tube[0], tube[1], base[2], base[3], tube[0]]), S.INK, 0.02, true)
