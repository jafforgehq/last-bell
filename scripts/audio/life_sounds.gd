## The sounds of the living and the dead (the SOUND pass), a part of the soundscape (scripts/audio/soundscape.gd makes it, calls `tick` ten times a second while the game runs
## at its own speed, and hands it the rules' "bite" events). It READS the rules (the dead, Ruth, her breath) and never writes them: the golden tests' promise. It uses a random
## generator of its own.
##
##   THE DEAD'S STEPS   a shuffle by what is under them (a soft foot on earth and carpet, a harder one on the rest), softer than a person's, every `DEAD_STRIDE` tiles; one that
##                      limps (`z.limp`) drags the other foot (a step and a scrape in one file); a brute's is lower and heavier. At most two a tick, the nearest, at most `DEAD_REACH` tiles from the camera.
##   THE WIND-UP        a short growl before a bite: when a dead one's `attack_t` (the rules' beat of claw and bite: it counts down from 1.3 s and the bite is at 0) falls under
##                      `WINDUP_T`. A walker growls, a runner hisses (or, now and then, screeches), a brute's growl is lower and heavier. At most two at once, `GROWL_GAP` apart, fewer far off.
##   IDLE GROANS        now and then (every few seconds by day, oftener by night) one of the dead that is near enough to hear and not at a bite groans, if no groan has been heard in the
##                      last two and a half seconds: rate limited, with the soundscape's own cap of groan voices.
##   RUTH               a grunt of pain when she is bitten (not twice in `PAIN_GAP` s) and her breath when the sprint's tank is low (the rules' `avatar.sprint`: `stamina`, `active`, `winded`).
extends RefCounted

const Foley := preload("res://scripts/audio/foley.gd")
const Buses := preload("res://scripts/audio/buses.gd")

## A stride of the dead (tiles), how far from the camera their steps and their growls are heard, and the point of the bite beat at which the growl begins (seconds before the bite).
const DEAD_STRIDE := 0.62
const DEAD_REACH := 13.0
const GROWL_REACH := 14.0
const WINDUP_T := 0.42
const GROWL_GAP := 0.22
## The seconds between idle groans (by day, by night), and how near and how far the groaner may be (tiles).
const IDLE_GAP_DAY := Vector2(4.0, 9.0)
const IDLE_GAP_NIGHT := Vector2(2.4, 5.5)
const IDLE_MIN_D := 4.0
const IDLE_MAX_D := 26.0
const IDLE_AFTER_GROAN_S := 2.5
## Ruth: the least time between two grunts (seconds), the stamina (0 to 1) under which she is out of breath, and how long after a run the breath goes on.
const PAIN_GAP := 0.7
const BREATH_BELOW := 0.30
const BREATH_AFTER_S := 6.0

var sc
var played := {}

var _rng := RandomNumberGenerator.new()
var _last := {}
var _stride := {}
var _atk := {}
var _growl_t := -10.0
var _idle_t := 5.0
var _pain_t := -10.0
var _breath_t := 0.0
var _run_t := -100.0


func _init(scape = null) -> void:
	sc = scape
	_rng.randomize()


## A new game: nothing is remembered of the last.
func reset() -> void:
	_last.clear()
	_stride.clear()
	_atk.clear()
	_growl_t = -10.0
	_idle_t = 5.0
	_pain_t = -10.0
	_breath_t = 0.0
	_run_t = -100.0


## Ten times a second, from the soundscape, with the seconds since the last.
func tick(dt: float) -> void:
	var game = sc.game
	if game == null or game.get("sim") == null:
		return
	if int(game.get("speed")) != 1 or bool(game.get("menu_open")):
		_last.clear()
		_stride.clear()
		_atk.clear()
		return
	var sim = game.sim
	var cam: Vector2 = sc.listener_tile()
	_dead_tick(sim, cam)
	_breath_tick(sim, cam, dt)
	_idle_tick(sim, cam, dt)


func _count(kind: String) -> void:
	played[kind] = int(played.get(kind, 0)) + 1


# --------------------------------------------------------------------------------------------- the dead --

func _dead_tick(sim, cam: Vector2) -> void:
	var zs = sim.get("zombies")
	if zs == null:
		return
	var last2 := {}
	var stride2 := {}
	var atk2 := {}
	var steps: Array = []
	var growls: Array = []
	var reach2 := GROWL_REACH * GROWL_REACH
	var step2 := DEAD_REACH * DEAD_REACH
	for z in zs:
		var st := String(z.state)
		if st == "dead" or st == "dying":
			continue
		var dx: float = float(z.x) - cam.x
		var dy: float = float(z.y) - cam.y
		var d2 := dx * dx + dy * dy
		if d2 > reach2:
			continue
		var here := Vector2(z.x, z.y)
		# the wind-up of a bite: attack_t has just fallen under WINDUP_T (it only runs down while the dead one is at its prey or its wall)
		var a: float = float(z.attack_t)
		if _atk.has(z):
			var prev: float = _atk[z]
			if prev > WINDUP_T and a <= WINDUP_T and a > 0.0:
				growls.append([d2, z])
		atk2[z] = a
		# a stride
		if d2 <= step2:
			if _last.has(z):
				var moved := here.distance_to(_last[z])
				var acc: float = float(_stride.get(z, 0.0))
				if moved <= 2.0 and moved >= 0.004:
					acc += moved
				if acc >= DEAD_STRIDE:
					acc -= DEAD_STRIDE
					steps.append([d2, z])
				stride2[z] = acc
			last2[z] = here
	_last = last2
	_stride = stride2
	_atk = atk2
	_play_steps(steps, cam)
	_play_growls(growls, cam)


func _play_steps(steps: Array, cam: Vector2) -> void:
	if steps.is_empty():
		return
	steps.sort_custom(func(a, b): return a[0] < b[0])
	var made := 0
	for item in steps:
		if made >= 2:
			break
		var z = item[1]
		var here := Vector2(z.x, z.y)
		var ground: String = sc.ground_at(here.x, here.y)
		var key := "dead:drag" if bool(z.limp) else ("dead:soft" if Foley.is_soft(ground) else "dead:hard")
		var stream = sc.pick_group(key)
		if stream == null:
			continue
		var size := float(z.size)
		var vol: float = float(Foley.LEVEL_DB["step_dead"]) + _rng.randf_range(-1.5, 1.0) + (3.5 if size > 1.3 else 0.0)
		var pitch := _rng.randf_range(0.92, 1.08) * (0.82 if size > 1.3 else 1.0)
		if sc.play_at("zstep", stream, here, cam, vol, pitch, -sqrt(float(item[0])), DEAD_REACH, Buses.category_bus(Buses.STEPS)):
			made += 1
			_count("dead_step")


func _play_growls(growls: Array, cam: Vector2) -> void:
	if growls.is_empty() or sc._t - _growl_t < GROWL_GAP:
		return
	growls.sort_custom(func(a, b): return a[0] < b[0])
	var made := 0
	for item in growls:
		if made >= 2:
			break
		var d := sqrt(float(item[0]))
		# (a bite near the camera is always heard; far off, one in three)
		if _rng.randf() > lerpf(1.0, 0.3, clampf((d - 5.0) / 9.0, 0.0, 1.0)):
			continue
		var z = item[1]
		var kind := String(z.kind)
		var key := "voice:zgrowl"
		var db: float = float(Foley.LEVEL_DB["growl"])
		var pitch := _rng.randf_range(0.93, 1.08)
		if kind == "brute":
			key = "voice:zbrute_growl"
			db = float(Foley.LEVEL_DB["brute_growl"])
		elif kind == "runner":
			if _rng.randf() < 0.3:
				key = "voice:zrun_screech"
				db = float(Foley.LEVEL_DB["screech"])
			else:
				key = "voice:zrun_hiss"
				db = float(Foley.LEVEL_DB["hiss"])
		var stream = sc.pick_group(key)
		if stream == null:
			continue
		if sc.play_at("growl", stream, Vector2(z.x, z.y), cam, db + _rng.randf_range(-1.5, 0.5), pitch, -d, GROWL_REACH, Buses.category_bus(Buses.VOICES)):
			made += 1
			_growl_t = sc._t
			_count("growl")


# ----------------------------------------------------------------------------------------- idle groans --

func _idle_tick(sim, cam: Vector2, dt: float) -> void:
	_idle_t -= dt
	if _idle_t > 0.0:
		return
	var phase := String(sim.get("phase")) if sim.get("phase") != null else "day"
	var night := phase == "night" or phase == "dusk"
	var gap: Vector2 = IDLE_GAP_NIGHT if night else IDLE_GAP_DAY
	_idle_t = _rng.randf_range(gap.x, gap.y)
	var zs = sim.get("zombies")
	if zs == null or sc._t - float(sc.last_groan_t) < IDLE_AFTER_GROAN_S:
		return
	# one of the dead that is at a good distance and not at its bite (chosen at random among them)
	var pool: Array = []
	for z in zs:
		var st := String(z.state)
		if st == "dead" or st == "dying" or st == "attack":
			continue
		var d := Vector2(z.x, z.y).distance_to(cam)
		if d >= IDLE_MIN_D and d <= IDLE_MAX_D:
			pool.append(z)
	if pool.is_empty():
		return
	var pick = pool[_rng.randi() % pool.size()]
	if sc.groan_play(Vector2(pick.x, pick.y), String(pick.kind), false, cam):
		_count("idle_groan")


# ------------------------------------------------------------------------------------------------ Ruth --

func _player(sim):
	var avatar = sim.get("avatar")
	if avatar == null or not avatar.has_method("player"):
		return null
	return avatar.player()


## The rules' "bite" event: if it is Ruth's, a grunt, a hair after the bite's own sound.
func on_bite(e: Dictionary) -> void:
	var game = sc.game
	if game == null or game.get("sim") == null:
		return
	var me = _player(game.sim)
	if me == null or String(e.get("who", "")) != String(me.id):
		return
	if sc._t - _pain_t < PAIN_GAP:
		return
	_pain_t = sc._t
	sc.schedule(0.07, _pain)


func _pain() -> void:
	var stream = sc.pick_group("voice:ruth_pain")
	if stream == null:
		return
	var cam: Vector2 = sc.listener_tile()
	if sc.play_at("ruth", stream, cam, cam, float(Foley.LEVEL_DB["ruth_pain"]) + _rng.randf_range(-1.0, 1.0), _rng.randf_range(0.96, 1.05), 500.0, 24.0, Buses.category_bus(Buses.VOICES), 1.0):
		_count("pain")


func _breath_tick(sim, cam: Vector2, dt: float) -> void:
	var avatar = sim.get("avatar")
	var sprint = avatar.get("sprint") if avatar != null else null
	if sprint == null or _player(sim) == null:
		return
	var stamina := float(sprint.stamina)
	var active: bool = bool(sprint.active)
	if active:
		_run_t = sc._t
	var recent: bool = sc._t - _run_t < BREATH_AFTER_S
	if stamina >= BREATH_BELOW or not (active or bool(sprint.winded) or recent):
		_breath_t = minf(_breath_t, 0.15)
		return
	_breath_t -= dt
	if _breath_t > 0.0:
		return
	var k := clampf(stamina / BREATH_BELOW, 0.0, 1.0)
	_breath_t = lerpf(0.62, 1.15, k) * (1.0 if active else 1.3) + _rng.randf_range(0.0, 0.15)
	var stream = sc.pick_group("voice:ruth_breath")
	if stream == null:
		return
	# (the emptier the tank, the louder and the quicker the breath)
	var db: float = float(Foley.LEVEL_DB["ruth_breath"]) - 5.0 * k + _rng.randf_range(-1.0, 1.0)
	if sc.play_at("ruth", stream, cam, cam, db, _rng.randf_range(0.96, 1.05), 400.0, 24.0, Buses.category_bus(Buses.VOICES), 1.0):
		_count("breath")
