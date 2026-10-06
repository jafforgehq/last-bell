## THE MELEE SWING of the town (One House; a piece of `avatar.gd`: it makes one, `avatar.melee_rules`, and hands the F key to it). The town only: `sim.is_one_house()` is false in the school, the demo
## and the no-player sim, and there `avatar.gd` swings the blow it always did (MELEE_REACH, MELEE_ARC, MELEE_COOLDOWN, the butt's 1.1): nothing here runs, and nothing here is read by them.
## THE NUMBERS are assets/data/melee.json (its `_doc` says what each is, and what the pose and the effects read). `read()` gives them over the DEFAULTS below.
##
## THE SWING. F is taken at once and the swing runs on its own: the aim is locked on the nearest of the dead within `assist_range` tiles and `assist_arc_deg` of the pointer (the swing turns to it); at
## `swoosh_at_s` the whoosh and the trail begin; at `hit_at_s` (a wind-up of 0.14 s) the blow lands on the dead in the arc (`reach_tiles`, `arc_deg`), at most `max_targets` of them, the nearest in full and
## the second at `second_hit_frac`; then a recovery to `cycle_s` (0.35 s). A press of F during the swing is kept for `buffer_s` and starts the next the moment this one ends.
## THE HIT. A walker or a runner takes `damage_walker_frac` of an average walker's hit points (a walker dies in one hit three times in four and always in two, a runner in one); a brute takes
## `brute_chip_frac` of a brute's (about seven hits), and a plated one that again by its armour (`Nights.damage_to`: it is a gun's to kill). The struck one that lives is STAGGERED (`stagger_s`: it
## neither walks nor bites) and thrown back `knockback_tiles` over `knockback_s`; a brute is neither staggered nor thrown. A blow that is not a miss is told to the
## dead that stand or wander near (`field.noise`): `noise_hit` tiles, and `noise_kill` when it killed what it hit. The swing of a person who was running (or ran within `lunge_window_s`) lunges `lunge_tiles` forward
## and hits `lunge_damage_mult` times as hard.
## WHAT THE DRAWING READS: the person's meta "swing_t" (seconds since the key was taken, -1.0 when no swing runs), `thrust` (1 to 0 over `trail_s` from the whoosh: the pawn's crescent) and the trail and
## the hit that `sim.feel` is told (`blow`, `hit`, `kill`). Nothing here is saved: a swing in the air at a save is forgotten.
extends RefCounted

const Kinds := preload("res://scripts/sim/kinds.gd")
const PATH := "res://assets/data/melee.json"
const META := "swing_t"
## What a number is when the file has none (the file's own numbers, assets/data/melee.json).
const DEFAULTS := {
	"windup_s": 0.14, "hit_at_s": 0.14, "recover_s": 0.21, "cycle_s": 0.35, "buffer_s": 0.15, "swoosh_at_s": 0.09, "trail_s": 0.16,
	"reach_tiles": 1.6, "arc_deg": 100.0, "max_targets": 2, "second_hit_frac": 0.6,
	"damage_walker_frac": 1.1, "brute_chip_frac": 0.15,
	"stagger_s": 0.35, "knockback_tiles": 0.4, "knockback_s": 0.12,
	"noise_hit": 3.0, "noise_kill": 2.0,
	"assist_range": 2.0, "assist_arc_deg": 60.0,
	"lunge_tiles": 0.6, "lunge_damage_mult": 1.3, "lunge_window_s": 0.4,
	"hitstop_hit_s": 0.03, "hitstop_kill_s": 0.06, "hitstop_gap_s": 0.12, "camera_kick_px": 2.0,
}
## Where a blow comes from (the chest, this far above the feet) and where the body's middle is (as avatar.gd's CHEST and BODY).
const CHEST := 0.15
const BODY := 0.3
## The least a lunge leaves between her and one of the dead (tiles).
const LUNGE_STOP := 0.45
## A knock-back ends no farther than this many tiles inside the reach.
const KEEP_IN := 0.15

var sim
var avatar
var cfg: Dictionary = {}
## Seconds since the key was taken (-1.0: no swing runs).
var t := -1.0
var _hit_done := false
var _whoosh_done := false
## Seconds a press made during the swing is still kept for.
var _buffer := 0.0
## The direction the swing is locked on (radians, from the shoulder, as `aim`).
var _aim := 0.0
var _lunge_left := 0.0
var _lunged := false
## When she last ran (`sim.t`).
var _ran_at := -100.0
var _who := ""
## The dead being thrown back: [{"z", "d" (the way), "left" (tiles)}].
var _kb: Array = []
## Counters for a scripted run: swings begun, blows that hurt something, kills by a blow.
var swings := 0
var landed := 0
var kills := 0


## The numbers: the file over the DEFAULTS, with the times that follow from each other made so (the hit lands where the wind-up ends and the swing lasts until the recovery is over).
static func read() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(PATH):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(PATH)) == OK and typeof(json.data) == TYPE_DICTIONARY:
			for k in json.data:
				if DEFAULTS.has(k) and (typeof(json.data[k]) == TYPE_FLOAT or typeof(json.data[k]) == TYPE_INT):
					out[k] = float(json.data[k])
	out["windup_s"] = out["hit_at_s"]
	out["cycle_s"] = float(out["hit_at_s"]) + float(out["recover_s"])
	return out


func setup(av, s) -> void:
	avatar = av
	sim = s
	cfg = read()


func start() -> void:
	reset()
	swings = 0
	landed = 0
	kills = 0


## Forgets the swing in the air and the dead being thrown (a new run, a load, a person who is not the player any more).
func reset() -> void:
	t = -1.0
	_hit_done = false
	_whoosh_done = false
	_buffer = 0.0
	_lunge_left = 0.0
	_lunged = false
	_kb.clear()
	_who = ""


func active() -> bool:
	return sim != null and sim.is_one_house()


## Whether a swing is running.
func busy() -> bool:
	return t >= 0.0


## The reach and the whole arc (degrees) of the blow, for the views that draw them.
func reach_tiles() -> float:
	return float(cfg.reach_tiles)


func arc_degrees() -> float:
	return float(cfg.arc_deg)


## The swing is dropped (the person is down, or gone): no blow lands, nothing is kept for later.
func cancel(p = null) -> void:
	if t >= 0.0 or _buffer > 0.0:
		t = -1.0
		_buffer = 0.0
		_lunge_left = 0.0
		if p != null:
			p.set_meta(META, -1.0)


## The F key, taken at the step: a swing begins when none runs; during one the press is kept for `buffer_s`.
func press(p) -> void:
	if t < 0.0:
		_begin(p)
	else:
		_buffer = float(cfg.buffer_s)


func _begin(p) -> void:
	t = 0.0
	_hit_done = false
	_whoosh_done = false
	swings += 1
	_aim = _assisted(p)
	_lunged = float(cfg.lunge_tiles) > 0.0 and (avatar.sprint.active or float(sim.t) - _ran_at <= float(cfg.lunge_window_s))
	_lunge_left = float(cfg.lunge_tiles) if _lunged else 0.0
	p.cooldown = maxf(p.cooldown, float(cfg.cycle_s))
	_face(p)


## One step of the swing (called by `Avatar.update` for the player, after walking and aiming, every step: also for the dead being thrown back).
func step(p, dt: float) -> void:
	var id := String(p.id)
	if id != _who:
		var keep: Array = _kb.duplicate()
		reset()
		_kb = keep
		_who = id
	if avatar.sprint.active:
		_ran_at = float(sim.t)
	_step_kb(dt)
	if _buffer > 0.0:
		_buffer = maxf(0.0, _buffer - dt)
	if t < 0.0:
		return
	t += dt
	var half := dt * 0.5 + 1.0e-4    # (the rules take whole steps: each moment is the nearest step to its time)
	if _lunge_left > 0.0:
		_lunge(p, dt)
	if not _whoosh_done and t + half >= float(cfg.swoosh_at_s):
		_whoosh_done = true
		_whoosh(p)
	if not _hit_done and t + half >= float(cfg.hit_at_s):
		_hit_done = true
		_land(p)
	if not _hit_done:
		_face(p)    # (the aim is locked until the blow: a pointer that swings away takes nothing from it)
	var trail := float(cfg.trail_s)
	if _whoosh_done and trail > 0.0:
		p.thrust = clampf(1.0 - (t - float(cfg.swoosh_at_s)) / trail, 0.0, 1.0)
	p.melee_t = maxf(0.0, float(cfg.cycle_s) - t)
	p.set_meta(META, t)
	if t + half >= float(cfg.cycle_s):
		t = -1.0
		p.melee_t = 0.0
		p.set_meta(META, -1.0)
		if _buffer > 0.0:
			_buffer = 0.0
			_begin(p)
			p.set_meta(META, 0.0)


## The swing turns to the nearest of the dead within `assist_range` tiles of her and `assist_arc_deg` of where the pointer is (a wall between does not count); else it goes where the pointer is.
func _assisted(p) -> float:
	var base: float = p.aim
	var from := Vector2(p.x, p.y - CHEST)
	var limit := deg_to_rad(float(cfg.assist_arc_deg))
	var range_ := float(cfg.assist_range)
	var best := INF
	var out := base
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var v := Vector2(z.x, z.y - BODY) - from
		var d := v.length()
		if d > range_ or d < 0.3 or d >= best:
			continue
		if absf(sim.ang_diff(base, v.angle())) > limit:
			continue
		if avatar.blocked_line(from, from + v):
			continue
		best = d
		out = v.angle()
	return out


func _face(p) -> void:
	p.aim = _aim
	p.facing = sim.facing_of(cos(_aim), sin(_aim), p.facing)


## The step forward of a swing begun at a run: spread over the wind-up, along the aim, never into a wall and never onto one of the dead.
func _lunge(p, dt: float) -> void:
	var d := minf(_lunge_left, float(cfg.lunge_tiles) / maxf(float(cfg.hit_at_s), 0.05) * dt)
	var dir := Vector2.from_angle(_aim)
	var here := Vector2(p.x, p.y)
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var at := Vector2(z.x, z.y)
		var after := at.distance_to(here + dir * d)
		if after < LUNGE_STOP and after < at.distance_to(here):
			_lunge_left = 0.0    # (a step that would close on one of the dead stops the lunge here)
			return
	var nx: float = p.x + dir.x * d
	if not avatar.walls_at(nx, p.y):
		p.x = nx
	var ny: float = p.y + dir.y * d
	if not avatar.walls_at(p.x, ny):
		p.y = ny
	_lunge_left -= d


## The whoosh of the blow in the air and the trail across the arc.
func _whoosh(p) -> void:
	sim.events.append({"type": "stab", "x": p.x, "y": p.y})
	if sim.feel != null:
		sim.feel.blow(p, float(cfg.reach_tiles), deg_to_rad(float(cfg.arc_deg)) / 2.0)


## The blow lands.
func _land(p) -> void:
	var from := Vector2(p.x, p.y - CHEST)
	var reach := float(cfg.reach_tiles)
	var half := deg_to_rad(float(cfg.arc_deg)) / 2.0
	var found: Array = []
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var c := Vector2(z.x, z.y - BODY)
		var v := c - from
		var d := v.length()
		if d > reach + 0.35 * (float(z.size) - 1.0):
			continue
		if d > 0.3 and absf(sim.ang_diff(_aim, v.angle())) > half:
			continue
		if avatar.blocked_line(from, c):
			continue
		found.append([d, z, v.angle()])
	if found.is_empty():
		return
	found.sort_custom(func(a, b): return a[0] < b[0])
	var struck := 0
	var killed := 0
	for i in mini(found.size(), int(cfg.max_targets)):
		var z = found[i][1]
		var raw := _base_damage(z) * (1.0 if i == 0 else float(cfg.second_hit_frac)) * (float(cfg.lunge_damage_mult) if _lunged else 1.0)
		var was_stunned: float = z.stagger
		sim._hurt_zombie(z, sim.nights.damage_to(z, raw, false), float(found[i][2]), p, true)
		struck += 1
		if z.state == "dying" or z.state == "dead":
			killed += 1
		elif z.kind == Kinds.BRUTE:
			z.stagger = was_stunned    # (a brute is chipped, not staggered: the flinch that every hit gives is taken back)
		else:
			_shove(z, p, float(found[i][2]), float(found[i][0]))
	landed += 1
	kills += killed
	var field = sim.get("field")
	if field != null and field.has_method("noise"):
		field.noise(Vector2(p.x, p.y), p, float(cfg.noise_kill) if killed == struck else float(cfg.noise_hit))


## What one hit takes from this kind: a share of an average walker's hit points (a runner is as frail), a brute's share of a brute's.
func _base_damage(z) -> float:
	if z.kind == Kinds.BRUTE:
		return float(cfg.brute_chip_frac) * _mean_hp(Kinds.BRUTE)
	return float(cfg.damage_walker_frac) * _mean_hp(Kinds.WALKER)


func _mean_hp(kind: String) -> float:
	var hp: Array = Kinds.KINDS[kind].hp
	return (float(hp[0]) + float(hp[1])) * 0.5


## The struck one is stunned and thrown back from her: `knockback_tiles`, but never farther than where it would be KEEP_IN tiles inside the reach (`dist` is how far it was from her
## chest), so that the next swing, 0.33 s on, still reaches it: the one hit at the end of the reach is stunned and stays, the one at her elbow is thrown the whole way.
func _shove(z, p, ang: float, dist: float) -> void:
	z.stagger = maxf(z.stagger, float(cfg.stagger_s))
	var tiles := minf(float(cfg.knockback_tiles), maxf(0.0, float(cfg.reach_tiles) - KEEP_IN - dist))
	if tiles < 0.02:
		return
	var away := Vector2(z.x - p.x, z.y - p.y)
	var d := away.normalized() if away.length() > 0.05 else Vector2.from_angle(ang)
	for e in _kb:
		if e.z == z:
			e.d = d
			e.left = tiles
			return
	_kb.append({"z": z, "d": d, "left": tiles})


func _step_kb(dt: float) -> void:
	if _kb.is_empty():
		return
	var speed := float(cfg.knockback_tiles) / maxf(float(cfg.knockback_s), 0.02)
	for e in _kb:
		var z = e.z
		if z.state == "dying" or z.state == "dead" or z.remove:
			e.left = 0.0
			continue
		var adv := minf(float(e.left), speed * dt)
		var nx: float = z.x + e.d.x * adv
		var ny: float = z.y + e.d.y * adv
		if sim.world.is_solid(sim.world.solid_z, nx, ny):
			e.left = 0.0
			continue
		z.x = nx
		z.y = ny
		e.left = float(e.left) - adv
	_kb = _kb.filter(func(e): return float(e.left) > 1.0e-6)
