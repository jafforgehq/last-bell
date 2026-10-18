## The feel of fighting, seen and heard (the polish wave, P-COMBAT): the muzzle flash and the light of a shot by weapon, the kick of the
## camera and the hit-stop of a close kill, blood, sparks and dust where a hit lands, the white flash, the knock-back and the fall of the
## struck dead, the plate-hit of a brute's steel, the splats on the ground that fade, the sounds of a hit and of a reload.
##
## EVERYTHING HERE IS RENDER AND AUDIO. The rules never read it: they only tell it what happened (`Sim.feel`, null in the tests and the
## balance harness: `shot`, `hit`, `kill` and the effects' own `fx.muzzle`, `fx.blood`, `fx.decal`, `fx.hit_material`), and it has a source
## of random numbers of its own and a clock of its own, so a run with it plays the same game, step for step, as one without (a test
## compares the two). The effects are pooled: particles live in fixed arrays (a ring: the oldest goes when the pool is full), the
## flashes and the splats have caps, and nothing is made or freed per shot but a few dictionaries.
##
## "Reduce motion" (Settings) turns off the camera's kick, the hit-stop, the sprite's nudge and the white flash of a hit; the light of the
## muzzle is half as bright and short, and the fall of the dead is plain.
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/render/pawn_art.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Access := preload("res://scripts/access.gd")
const PawnMotion := preload("res://scripts/render/pawn_motion.gd")
const BloodStore := preload("res://scripts/render/blood_store.gd")
const StepFx := preload("res://scripts/render/step_fx.gd")
const TILE := GD.TILE
const G := 9.8

# the kinds of particle
const K_BLOOD := 1    # a drop of blood in the air, a splat where it lands
const K_MIST := 2     # a puff of blood (drawn dark red, over the ground)
const K_SPARK := 3    # a streak of light (additive)
const K_DUST := 4     # a puff of dust or gun smoke
const K_CHIP := 5     # a chip of stone or wood
const K_STAR := 6     # a burst of light at a blow (additive)
const K_RING := 7     # a ring of light that grows (additive)
const K_GLOW := 8     # a soft patch of light that fades (additive)

## How many particles, flashes, splats, fallen and later things there can be at once. A pool that is full gives its oldest place to the newest.
const MAX_PARTS := 224
const MAX_FLASHES := 12
const MAX_BLOWS := 6
## How long the trail of a swing lasts (seconds of the game's time); the town's own is `blow_s`, from assets/data/melee.json (`set_melee`).
const BLOW_S := 0.16
const MAX_DECALS := 150
const MAX_FALLEN := 200
const MAX_LATER := 48
## A splat stays at full strength this long (seconds of the game's time), then fades, and is gone after DECAL_LIFE.
const DECAL_HOLD := 6.0
const DECAL_LIFE := 20.0
## The prison keeps stains until a cleaner comes (prison_game.gd sets these); the town's values are the constants.
var decal_hold := DECAL_HOLD
var decal_life := DECAL_LIFE
## At most this many drops of blood leave a splat of their own in one frame (a volley must not paint the ground).
const SPLATS_PER_FRAME := 4
## A hit on a plated brute that does less than this is the armour's (nights.json: armour 0.1, a head hit 3.0): it rings, it does not bleed.
const ARMOUR_BELOW := 0.9
## The hit-stop: how long it freezes the picture (real seconds), the farthest kill that earns one (tiles), the least time between two.
const HITSTOP_S := 0.05
const HITSTOP_RANGE := 3.0
const HITSTOP_GAP := 0.4
## FEEL: a kill by a shotgun (or the hunting rifle) freezes the picture for this long (real seconds) from as far as this (tiles), and pushes the camera this much (pixels) along the blast.
const HITSTOP_SHOTGUN_S := 0.026
const HITSTOP_SHOTGUN_RANGE := 6.0
const KILL_PUSH_PX := 1.6
## FEEL: every blast of the player's pump gun holds the picture this long (real seconds), unless "Screen shake" is off.
const HITSTOP_BLAST_S := 0.05
## How long the struck one is white (real seconds: two frames at 60 Hz and a little over).
const FLASH_S := 0.045
## The shake's decay (per second) and the farthest it can pull the picture (screen pixels at the 1280 x 800 window).
const KICK_DECAY := 15.0
const KICK_MAX := 8.0
## How far a body slides as it falls (tiles), and the knock-back of a hit that does not kill.
const SLIDE_TILES := 0.34

## What each gun does: the flash's length and glow (tiles), how long it lasts (seconds), how far its light reaches (tiles), the kick of the
## camera (pixels), the shake that comes with it (pixels), the sprite's nudge back (tiles), the cone of the blast (radians, 0: none) and
## the gun smoke. Names are the weapons' (map.json).
const GUNS := {
	"pistol": {"len": 0.72, "glow": 0.62, "dur": 0.070, "light": 2.8, "kick": 1.6, "shake": 0.0, "nudge": 0.035, "cone": 0.0, "smoke": 0.12},
	"rifle": {"len": 1.05, "glow": 0.85, "dur": 0.080, "light": 4.0, "kick": 2.6, "shake": 0.3, "nudge": 0.050, "cone": 0.0, "smoke": 0.15},
	"service": {"len": 1.15, "glow": 0.92, "dur": 0.085, "light": 4.4, "kick": 3.2, "shake": 0.5, "nudge": 0.060, "cone": 0.0, "smoke": 0.17},
	"hunting": {"len": 1.40, "glow": 1.10, "dur": 0.100, "light": 5.2, "kick": 4.6, "shake": 1.0, "nudge": 0.075, "cone": 0.0, "smoke": 0.22},
	"smg": {"len": 0.80, "glow": 0.70, "dur": 0.055, "light": 3.0, "kick": 1.4, "shake": 0.2, "nudge": 0.030, "cone": 0.0, "smoke": 0.10},
	"shotgun": {"len": 1.45, "glow": 1.25, "dur": 0.110, "light": 6.0, "kick": 5.6, "shake": 1.6, "nudge": 0.085, "cone": 0.27, "smoke": 0.26},
}
## FEEL: the light of a muzzle flash. Its strength by gun (a share of the light rig's flash energy: the pump gun is the whole of it), how far ahead of the muzzle (a share of its reach) its
## middle is, and its colour.
const FLASH_E := {"pistol": 0.62, "smg": 0.6, "rifle": 0.74, "service": 0.78, "hunting": 0.9, "shotgun": 1.0}
## The drawn flash (glow, cone, star, heart): the share of its strength it has on its first frame, and how long it takes to be full (seconds of the game's time: three frames at 60 Hz).
const FLASH_GLOW_FIRST := 0.45
const FLASH_GLOW_RAMP_S := 0.034
const FLASH_AHEAD := 0.30
const FLASH_LIGHT := Color(1.0, 0.72, 0.40)
const WARM := Color(1.0, 0.78, 0.42)
const PALE := Color(1.0, 0.94, 0.74)

# ---------------------------------------------------------------- the pools --
var _kind := PackedByteArray()
var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _z := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _vz := PackedFloat32Array()
var _life := PackedFloat32Array()
var _max := PackedFloat32Array()
var _size := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _col := PackedColorArray()
var _head := 0
var _live := 0

var _flashes: Array = []    # {x, y, ang, t, dur, gun, mine}
var _blows: Array = []      # {x, y, aim, reach, half, t}: a swing's trail, for a moment
var _later: Array = []      # {at, what, x, y, ...}: things that happen a moment after the rules said so
var _hurt := {}             # Zombie -> {t0, dir, kick, plate, flash}: the struck, for a moment
var _fallen := {}           # Zombie -> {dir, mag, flash, plate}: the killed, for as long as their bodies lie
var _fallen_order: Array = []

# ---------------------------------------------------------------- decals --
var decal_parent: Node2D
## FEEL (the town only, `set_town`): the blood that stays, one MultiMesh (scripts/render/blood_store.gd), and the footstep dust (scripts/render/step_fx.gd). null elsewhere.
var store = null
var steps = null
var _blood_tex: Array = []
var _decals: Array = []     # {node, size, grow, age, alpha}
var _spare: Array = []
var _decal_dt := 0.0

# --------------------------------------------------------------- the rest --
var radial: Texture2D
var puff_light: Texture2D
var puff_dark: Texture2D
var rng := RandomNumberGenerator.new()
## The effects' own clock (seconds of the game's time, advanced by `update`), and a real one (advanced by `tick_real`).
var t := 0.0
var real_t := 0.0
## Whether any of it is drawn and heard (a test and the benchmark switch it off; the rules do not care).
var enabled := true
## The sound node, and where the camera is (tiles): a hit is heard by its distance.
var sound = null
var listener := Vector2.ZERO
var calm := false
## "Reduce flashes" (Settings): the white wash of a hit is a pale tint over a tenth of a second, the muzzle's flash and light are dim and short, the burst at a wound is faint
## (the camera's kick and the hit-stop are Reduce motion's: `calm`). Read with `calm`, twice a second.
var soft := false
## How much bigger the flashes, stars and glows are drawn than their size in tiles (main.gd: more when the camera is far, so that a flash is as big
## on the screen as it is up close: 1 at about 52 pixels a tile).
var zoom_k := 1.0
var _calm_at := -10.0
## The next `blood` is not wanted (the hit that came just before it rang on steel).
var _skip_blood := false
var _ctx_weapon := ""
var _ctx_mine := false
var _ctx_seen := true
## Whether a person or one of the dead is seen (Callable(entity) -> bool: main.gd, from the picture's own nodes): what is under a roof or in a room that is
## not shown has no flash, no blood and no light on the screen. Not set (a test, a place): everything is seen.
var seen_cb := Callable()
var _splat_budget := SPLATS_PER_FRAME
## The camera's push (screen pixels) and the freeze of the picture (real seconds left).
var _push := Vector2.ZERO
var hitstop := 0.0
var shake_k := 1.0    # the "Screen shake" setting (scripts/access.gd): how much of the camera's push is kept
var _hitstop_gap := 0.0
## The town's melee numbers (assets/data/melee.json, `Melee.read()`: main.gd gives them in the town and nowhere else): {} everywhere else, and then the blow feels as it always did. `blow_s` is the trail's life.
var melee_cfg: Dictionary = {}
var blow_s := BLOW_S
## The last dry pull of the trigger (real time; -1000: none) and what it said ("empty" or "reloading").
var dry_t := -1000.0
var dry_word := ""
## The reload being shown (see `reload_tick`).
var _rl_on := false
var _rl_total := 1.0
var _rl_m0 := 0
var _rl_cap := 0
var _rl_prev := 0.0
var _rl_notch := 0
var _rl_gun := ""
## The sounds' last times (real), so that a burst does not stack the same sound a dozen deep.
var _snd_at := {}
## Counts for the tests: particles made, the most there were at once, hit-stops asked.
var made := 0
var peak_live := 0
var hitstops_asked := 0


func _init() -> void:
	rng.seed = 90210
	_kind.resize(MAX_PARTS)
	_x.resize(MAX_PARTS)
	_y.resize(MAX_PARTS)
	_z.resize(MAX_PARTS)
	_vx.resize(MAX_PARTS)
	_vy.resize(MAX_PARTS)
	_vz.resize(MAX_PARTS)
	_life.resize(MAX_PARTS)
	_max.resize(MAX_PARTS)
	_size.resize(MAX_PARTS)
	_grow.resize(MAX_PARTS)
	_col.resize(MAX_PARTS)
	calm = Prefs.on("ui", "reduce_motion")
	soft = Access.reduce_flashes()
	shake_k = Access.shake_k()


func setup(blood_textures: Array, parent: Node2D, radial_tex: Texture2D, light_puff: Texture2D, dark_puff: Texture2D) -> void:
	_blood_tex = blood_textures
	decal_parent = parent
	radial = radial_tex
	puff_light = light_puff
	puff_dark = dark_puff
	PawnMotion.thump_cb = thump    # (ANIM: a brute's heavy step or blow shakes the camera a hair: scripts/render/pawn_node.gd)


## FEEL, the town only (main.gd, when the run is the One House): the blood that stays (blood_store.gd), footstep dust (step_fx.gd: `wet` says how wet the ground is) and the dead's and the
## crew's pawns telling where a foot landed. A run that is not the town keeps the old splats and has no dust.
func set_town(world, data: Dictionary, wet: Callable = Callable()) -> void:
	if store == null and decal_parent != null:
		var s = BloodStore.new()
		if s.setup(decal_parent, _blood_tex):
			store = s
	if steps == null:
		var st = StepFx.new()
		st.setup(world, data, puff_light)
		st.wet_cb = wet
		steps = st
	PawnMotion.step_cb = step_event


## A foot landed (pawn_node.gd, through `PawnMotion.step_cb`): where (tiles, the figure's origin), which way it goes, and how hard (0.4 a slow walker to 1.0 a run, 1.4 a brute).
func step_event(at: Vector2, dir: Vector2, power: float) -> void:
	if steps != null and enabled:
		steps.calm = calm
		steps.step(at.x, at.y, dir, power)


## Painted over the ground, under the people (fx.gd `draw_ground_bits`): the footstep dust.
func draw_ground(ci: CanvasItem) -> void:
	if steps != null and enabled:
		steps.draw(ci)


## Forgets everything that is in the air and on the ground (a new run in the same scene, a test).
func clear() -> void:
	if store != null:
		store.clear()
	if steps != null:
		steps.clear()
	for i in MAX_PARTS:
		_life[i] = 0.0
	_live = 0
	_flashes.clear()
	_blows.clear()
	_later.clear()
	_hurt.clear()
	_fallen.clear()
	_fallen_order.clear()
	for d in _decals:
		d.node.visible = false
		_spare.append(d.node)
	_decals.clear()
	_push = Vector2.ZERO
	hitstop = 0.0


func live_count() -> int:
	return _live


func decal_count() -> int:
	return _decals.size() + (store.count() if store != null else 0)


func flash_count() -> int:
	return _flashes.size()


func fallen_count() -> int:
	return _fallen.size()


# ---------------------------------------------------------------- clocks --

## The game's time moved on by `dt` (the frames of the game at its speed: nothing while it is paused).
func update(dt: float) -> void:
	t += dt
	_splat_budget = SPLATS_PER_FRAME
	if store != null:
		store.update(dt)
	if steps != null:
		steps.update(dt)
	if _live > 0:
		_step_parts(dt)
	if not _flashes.is_empty():
		for f in _flashes:
			f.t += dt
		_flashes = _flashes.filter(func(f): return f.t < f.dur)
	if not _blows.is_empty():
		for b in _blows:
			b.t += dt
		_blows = _blows.filter(func(b): return b.t < blow_s)
	if not _later.is_empty():
		var keep: Array = []
		for w in _later:
			if t >= float(w.at):
				_happen(w)
			else:
				keep.append(w)
		_later = keep
	if not _hurt.is_empty():
		var gone: Array = []
		for z in _hurt:
			if t - float(_hurt[z].t0) > 0.5:
				gone.append(z)
		for z in gone:
			_hurt.erase(z)
	# (the splats grow over three seconds and fade over fourteen: fifteen times a second is smooth enough, and costs a quarter)
	if not _decals.is_empty():
		_decal_dt += dt
		if _decal_dt >= 0.066:
			_age_decals(_decal_dt)
			_decal_dt = 0.0


## A frame of real time (the camera's push dies away and the freeze counts down, paused or not).
func tick_real(dt: float) -> void:
	real_t += dt
	if real_t - _calm_at >= 0.5 or real_t < _calm_at:
		_calm_at = real_t
		calm = Prefs.on("ui", "reduce_motion")
		soft = Access.reduce_flashes()
		shake_k = Access.shake_k()
	if calm:
		_push = Vector2.ZERO
		hitstop = 0.0
	else:
		_push *= exp(-KICK_DECAY * dt)
		if _push.length_squared() < 0.0004:
			_push = Vector2.ZERO
		hitstop = maxf(0.0, hitstop - dt)
	_hitstop_gap = maxf(0.0, _hitstop_gap - dt)


## Where the camera is pushed to now, in screen pixels (nothing under "reduce motion").
func camera_push() -> Vector2:
	return _push * shake_k if enabled and not calm else Vector2.ZERO


## A jolt of the camera from outside a shot (the avatar bitten): `v` screen pixels, capped like a shot's kick; nothing under "reduce motion".
func jolt(v: Vector2) -> void:
	if enabled and not calm:
		_push = (_push + v).limit_length(KICK_MAX)


## Whether the picture is frozen for a close kill (real seconds left); nothing under "reduce motion".
func frozen() -> bool:
	return enabled and not calm and hitstop > 0.0


# ------------------------------------------------------------- the pools --

func _add(kind: int, x: float, y: float, z: float, vx: float, vy: float, vz: float, life: float, size: float, col: Color, grow: float = 0.0) -> void:
	var i := _head
	_head = (_head + 1) % MAX_PARTS
	if _life[i] <= 0.0:
		_live += 1
	_kind[i] = kind
	_x[i] = x
	_y[i] = y
	_z[i] = z
	_vx[i] = vx
	_vy[i] = vy
	_vz[i] = vz
	_life[i] = life
	_max[i] = life
	_size[i] = size
	_grow[i] = grow
	_col[i] = col
	made += 1
	if _live > peak_live:
		peak_live = _live


func _step_parts(dt: float) -> void:
	for i in MAX_PARTS:
		var l := _life[i]
		if l <= 0.0:
			continue
		l -= dt
		if l <= 0.0:
			_life[i] = 0.0
			_live -= 1
			continue
		_life[i] = l
		var k := _kind[i]
		if k == K_BLOOD or k == K_SPARK or k == K_CHIP:
			_x[i] += _vx[i] * dt
			_y[i] += _vy[i] * dt
			_vz[i] -= G * dt
			_z[i] += _vz[i] * dt
			if k == K_BLOOD:
				_vx[i] *= 1.0 - minf(1.0, 1.4 * dt)
				_vy[i] *= 1.0 - minf(1.0, 1.4 * dt)
			if _z[i] <= 0.0:
				if k == K_BLOOD:
					if _splat_budget > 0 and rng.randf() < 0.45:
						_splat_budget -= 1
						decal(_x[i], _y[i], _size[i] * 3.0 + 0.04, 0.0, 0.7)
					_life[i] = 0.0
					_live -= 1
				elif k == K_SPARK:
					_life[i] = minf(l, 0.04)
				else:
					_z[i] = 0.0
					if _vz[i] < -1.0:
						_vz[i] = -_vz[i] * 0.3
						_vx[i] *= 0.4
						_vy[i] *= 0.4
					else:
						_vz[i] = 0.0
						_vx[i] = 0.0
						_vy[i] = 0.0
		elif k == K_DUST or k == K_MIST:
			_x[i] += _vx[i] * dt
			_y[i] += _vy[i] * dt
			_vx[i] *= 1.0 - minf(1.0, 2.0 * dt)
			_vy[i] *= 1.0 - minf(1.0, 2.0 * dt)
			_size[i] += _grow[i] * dt
		elif k == K_RING:
			_size[i] += _grow[i] * dt


# --------------------------------------------------------------- settings --

func _pace() -> float:
	return 0.5 if calm else 1.0


func _rand_range(a: float, b: float) -> float:
	return a + (b - a) * rng.randf()


# ---------------------------------------------------------------- the shot --

## The rules say who fires what (before `fx.muzzle`, which draws the flash): the camera kicks for the player's own shot.
func shot(p, weapon: String, ang: float) -> void:
	_ctx_weapon = weapon
	_ctx_mine = bool(p.player)
	_ctx_seen = _seen(p)
	if enabled and _ctx_seen:
		PawnMotion.note_shot(Vector2(float(p.x), float(p.y)), p)    # (FEEL: the crew near it turn to look: pawn_node.gd)
	if not enabled or not _ctx_mine or calm:
		return
	var g: Dictionary = GUNS.get(weapon, GUNS.rifle)
	var dir := Vector2.from_angle(ang)
	var push := -dir * float(g.kick) + dir.orthogonal() * (rng.randf() - 0.5) * float(g.kick) * 0.35
	push += Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * 2.0 * float(g.shake)
	_push += push
	if _push.length() > KICK_MAX:
		_push = _push.normalized() * KICK_MAX
	if weapon == "shotgun" and shake_k > 0.0:
		hitstop = maxf(hitstop, HITSTOP_BLAST_S)
		hitstops_asked += 1


## The flash at the muzzle (fx.muzzle): a star and a glow by weapon, a cone for the pump gun, the gun's smoke, and the light.
func muzzle(x: float, y: float, ang: float, big: bool) -> void:
	var weapon := _ctx_weapon if _ctx_weapon != "" else ("shotgun" if big else "rifle")
	var mine := _ctx_mine
	var seen := _ctx_seen or _ctx_weapon == ""
	_ctx_weapon = ""
	_ctx_mine = false
	_ctx_seen = true
	if not enabled or not seen:
		return
	var g: Dictionary = GUNS.get(weapon, GUNS.rifle)
	_flashes.append({"x": x, "y": y, "ang": ang, "t": 0.0, "dur": float(g.dur) * (0.55 if soft else (0.7 if calm else 1.0)), "gun": weapon, "mine": mine, "rot": rng.randf() * 0.5})
	if _flashes.size() > MAX_FLASHES:
		_flashes.pop_front()
	var dir := Vector2.from_angle(ang)
	var s := float(g.smoke)
	_add(K_DUST, x + dir.x * 0.18, y + dir.y * 0.18, 0.0, dir.x * 0.9 + _rand_range(-0.15, 0.15), dir.y * 0.9 + _rand_range(-0.15, 0.15) - 0.1, 0.0, _rand_range(0.55, 0.85), s, Color(0.86, 0.84, 0.78, 0.30), 0.35)
	if weapon == "shotgun" or weapon == "hunting":
		_add(K_DUST, x + dir.x * 0.5, y + dir.y * 0.5, 0.0, dir.x * 0.5, dir.y * 0.5 - 0.15, 0.0, _rand_range(0.8, 1.1), s * 0.8, Color(0.82, 0.80, 0.74, 0.22), 0.45)


## The lights of the flashes now: [{x, y, r}], for the light rig (lighting.gd): warm, short, and as wide as the gun is loud.
func flash_lights() -> Array:
	var out: Array = []
	if not enabled:
		return out
	var dim := 0.4 if soft else (0.7 if calm else 1.0)
	for f in _flashes:
		var g: Dictionary = GUNS.get(f.gun, GUNS.rifle)
		var u: float = clampf(float(f.t) / float(f.dur), 0.0, 1.0)
		# (FEEL: the pool holds its strength through the first third of the flash and dies away after it (the first frames' climb is the light rig's: lighting.gd); its middle is a little
		# AHEAD of the muzzle, so the shooter stands on the soft edge of it and the ground and the walls in front of her take the light; `e` is the gun's share of the rig's strength)
		var env := 1.0 if u < 0.3 else pow(1.0 - (u - 0.3) / 0.7, 1.3)
		var r := float(g.light) * (0.62 + 0.38 * (1.0 - u)) * dim
		var ahead := Vector2.from_angle(float(f.ang)) * r * FLASH_AHEAD
		out.append({"x": float(f.x) + ahead.x, "y": float(f.y) + ahead.y, "r": r, "e": float(FLASH_E.get(f.gun, 0.5)) * env * dim, "c": FLASH_LIGHT})
	return out


## The town's melee numbers (`Melee.read()`), or {} for a game with the old blow: the trail lives `trail_s`, and a hit and a kill of the player's own blow freeze the picture and push the camera (`_melee_impact`).
func set_melee(cfg: Dictionary) -> void:
	melee_cfg = cfg
	blow_s = maxf(0.05, float(cfg.get("trail_s", BLOW_S))) if not cfg.is_empty() else BLOW_S


## The weight of the player's blow landing (the town): the picture holds for a moment and the camera is pushed along the blow, more at a kill. Nothing under "reduce motion" (`calm`: the freeze and the push are
## that setting's); the least time between two freezes is `hitstop_gap_s`, so that a run of blows is not a stutter.
func _melee_impact(dir: Vector2, lethal: bool) -> void:
	if melee_cfg.is_empty() or calm or not enabled:
		return
	var s := float(melee_cfg.get("hitstop_kill_s" if lethal else "hitstop_hit_s", 0.0))
	if s > 0.0 and (lethal or _hitstop_gap <= 0.0):
		hitstop = maxf(hitstop, s)
		_hitstop_gap = float(melee_cfg.get("hitstop_gap_s", 0.12))
		hitstops_asked += 1
	var kick := float(melee_cfg.get("camera_kick_px", 0.0)) * (1.5 if lethal else 1.0)
	if kick > 0.0:
		_push += dir * kick
		if _push.length() > KICK_MAX:
			_push = _push.normalized() * KICK_MAX


## The avatar swings (the rules' blow: the butt, the pike's thrust, F): a bright trail sweeps across the arc for a moment. `age` is how far into
## the swing to begin (a screenshot's).
func blow(p, reach: float, half_arc: float, age: float = 0.0) -> void:
	if not enabled:
		return
	_blows.append({"x": float(p.x), "y": float(p.y) - 0.3, "aim": float(p.aim), "reach": reach, "half": half_arc, "t": age})
	if _blows.size() > MAX_BLOWS:
		_blows.pop_front()


# ----------------------------------------------------------------- blood --

## Blood from a wound at (x, y) going the way (dx, dy): a spray of drops that fly, fall and leave a speck, and a puff.
func blood(x: float, y: float, dx: float, dy: float, n: int = 10) -> void:
	if _skip_blood:
		_skip_blood = false
		return
	if not enabled:
		return
	var base := atan2(dy, dx)
	# (a blow on one of the dead is told twice, here and by `hit`: the spray is shared)
	for i in (n + 1) / 2:
		var sp := _rand_range(1.2, 4.2)
		var a := base + (rng.randf() - 0.5) * 1.3
		var c := Color(0.50, 0.07, 0.06) if rng.randf() < 0.6 else Color(0.68, 0.10, 0.08)
		_add(K_BLOOD, x, y, _rand_range(0.4, 0.6), cos(a) * sp, sin(a) * sp, _rand_range(0.0, 2.2), 2.0, _rand_range(0.03, 0.065), c)
	if n >= 5:
		_mist(Vector2(x, y), Vector2(dx, dy).normalized(), 1 + n / 5)


func _mist(at: Vector2, dir: Vector2, n: int) -> void:
	for i in n:
		var d := dir.rotated(_rand_range(-0.5, 0.5)) * _rand_range(0.4, 1.3)
		_add(K_MIST, at.x + d.x * 0.1, at.y + d.y * 0.1, 0.0, d.x, d.y, 0.0, _rand_range(0.22, 0.38), _rand_range(0.10, 0.16), Color(0.55, 0.08, 0.07, 0.55), 0.8)


# ------------------------------------------------------------------ hits --

## Whether `e` (a person, one of the dead) is seen on the screen now (see `seen_cb`).
func _seen(e) -> bool:
	return not seen_cb.is_valid() or bool(seen_cb.call(e))


## The rules hurt one of the dead: `ang` is the way the blow went, `dmg` what it did, `shooter` who struck it.
func hit(z, ang: float, dmg: float, melee: bool, shooter) -> void:
	if not enabled:
		return
	if not _seen(z):
		_skip_blood = true    # (the rules tell of the blood right after: not of this one's either)
		return
	var size := float(z.size)
	var dir := Vector2.from_angle(ang)
	# (the wound is on the body, a little above the feet: the particles start on the ground under it at that height; what is drawn flat
	# (stars, rings, puffs) goes where the wound is on the screen)
	var ground := Vector2(float(z.x), float(z.y)) - dir * 0.1 * size
	var height := 0.5 * size
	var wound := ground + Vector2(0.0, -height * 0.6)
	var plated: bool = bool(z.plated)
	var armoured: bool = plated and dmg < ARMOUR_BELOW
	var head: bool = plated and not armoured
	var kick := clampf(0.05 + dmg * 0.045, 0.05, 0.24) / maxf(size, 0.6)
	_skip_blood = armoured
	if armoured:
		kick *= 0.35
		_plate_hit(ground, height, wound, dir)
		_say("hit_plate", wound, 1.0, 0.05, 1.0, 0.05)
	else:
		_flesh_hit(ground, height + (0.25 * size if head else 0.0), wound, dir, melee, head)
		if melee:
			_say("melee_hit", wound, 0.95, 0.06, 1.0, 0.05)
		else:
			_say("hit_flesh", wound, 0.95 if not head else 1.1, 0.06, 0.92 if size > 1.1 else 1.0, 0.05)
	if melee and not armoured and shooter != null and bool(shooter.player):
		_melee_impact(dir, false)    # (the town: the weight of the player's blow, none on steel; a kill adds to it in `kill`)
	_hurt[z] = {"t0": t, "dir": dir, "kick": kick, "plate": armoured, "flash": true}


func _flesh_hit(ground: Vector2, height: float, wound: Vector2, dir: Vector2, melee: bool, head: bool) -> void:
	var n := 6 if not melee else 4
	for i in n:
		var a := dir.angle() + (rng.randf() - 0.5) * 1.1
		var sp := _rand_range(1.5, 4.8)
		var c := Color(0.52, 0.07, 0.06) if rng.randf() < 0.55 else Color(0.70, 0.11, 0.08)
		_add(K_BLOOD, ground.x, ground.y, height + _rand_range(-0.1, 0.1), cos(a) * sp, sin(a) * sp, _rand_range(0.2, 2.4), 2.0, _rand_range(0.035, 0.07), c)
	# a couple of drops thrown back at the shooter
	for i in 2:
		var a2 := dir.angle() + PI + (rng.randf() - 0.5) * 1.4
		_add(K_BLOOD, ground.x, ground.y, height, cos(a2) * 1.2, sin(a2) * 1.2, 1.0, 1.6, _rand_range(0.03, 0.05), Color(0.55, 0.08, 0.07))
	_mist(wound + dir * 0.15, dir, 3)
	_add(K_GLOW, wound.x, wound.y, 0.0, 0.0, 0.0, 0.0, 0.10, 0.42 if head else 0.32, Color(1.0, 0.50, 0.44))
	# the burst of light at the wound (a white-pink flash, short)
	var burst: Color = Color(1.0, 0.82, 0.78) if not melee else PALE
	if soft:
		burst.a *= 0.35    # ("Reduce flashes": the burst at a wound is faint)
	_add(K_STAR, wound.x, wound.y, 0.0, 0.0, 0.0, 0.0, 0.09, 0.26 if not head else 0.38, burst)
	if melee:
		# the thud of a blow: dust and a bigger sparkle ("Reduce flashes": a faint one)
		var thud_star: Color = PALE
		if soft:
			thud_star.a *= 0.35
		_add(K_STAR, wound.x, wound.y, 0.0, 0.0, 0.0, 0.0, 0.14, 0.42, thud_star)
		_add(K_DUST, wound.x, wound.y, 0.0, dir.x * 0.3, dir.y * 0.3, 0.0, 0.5, 0.09, Color(0.80, 0.76, 0.68, 0.30), 0.5)


func _plate_hit(ground: Vector2, height: float, wound: Vector2, dir: Vector2) -> void:
	for i in 14:
		var a := dir.angle() + PI + (rng.randf() - 0.5) * 2.6
		var sp := _rand_range(2.0, 6.5)
		var c := Color(0.82, 0.92, 1.0) if rng.randf() < 0.55 else Color(1.0, 0.92, 0.70)
		_add(K_SPARK, ground.x, ground.y, height + _rand_range(-0.15, 0.15), cos(a) * sp, sin(a) * sp, _rand_range(0.5, 2.5), _rand_range(0.25, 0.45), 0.05, c)
	_add(K_RING, wound.x, wound.y, 0.0, 0.0, 0.0, 0.0, 0.18, 0.08, Color(0.70, 0.86, 1.0), 3.4)
	_add(K_STAR, wound.x, wound.y, 0.0, 0.0, 0.0, 0.0, 0.14, 0.55, Color(0.88, 0.95, 1.0))
	_add(K_GLOW, wound.x, wound.y, 0.0, 0.0, 0.0, 0.0, 0.16, 0.55, Color(0.62, 0.80, 1.0))


## The rules killed one of the dead: it falls, slides away from the blow, throws more blood, raises dust where it lands; a kill close to the
## shooter freezes the picture for a moment (not the rules).
func kill(z, ang: float, melee: bool, shooter) -> void:
	if not enabled or not _seen(z):
		return
	var size := float(z.size)
	var dir := Vector2.from_angle(ang)
	var wound := Vector2(float(z.x), float(z.y) - 0.3 * size)
	for i in 6:
		var a := dir.angle() + (rng.randf() - 0.5) * 1.6
		var sp := _rand_range(1.0, 4.0)
		_add(K_BLOOD, float(z.x), float(z.y), 0.5 * size + _rand_range(-0.1, 0.2), cos(a) * sp, sin(a) * sp, _rand_range(0.4, 3.0), 2.0, _rand_range(0.04, 0.08), Color(0.55, 0.07, 0.06))
	_mist(wound, dir, 3)
	var plate := false
	if _hurt.has(z):
		plate = bool(_hurt[z].plate)
		_hurt.erase(z)
	var mag := SLIDE_TILES / maxf(size, 0.7) * (1.25 if melee else 1.0)
	_fallen[z] = {"dir": dir, "mag": mag, "flash": true, "plate": plate}
	_fallen_order.append(z)
	if _fallen_order.size() > MAX_FALLEN:
		_fallen.erase(_fallen_order.pop_front())
	# where it comes down, a moment later: the dust of the body and its thud
	if _later.size() < MAX_LATER:
		_later.append({"at": t + 0.30, "what": "land", "x": float(z.x) + dir.x * mag * 0.8, "y": float(z.y) + 0.12})
	if melee:
		_say("melee_kill", Vector2(float(z.x), float(z.y)), 0.8, 0.05, 1.0, 0.05)    # (the SOUND pass: a wetter blow laid on the thud of the hit)
	if melee and shooter != null and bool(shooter.player) and not melee_cfg.is_empty():
		_melee_impact(dir, true)    # (the town's blow: its own, longer, freeze and its push, whatever the gap since the last)
	elif shooter != null and bool(shooter.player) and not calm and _hitstop_gap <= 0.0:
		var shotgun := String(shooter.weapon) == "shotgun" or String(shooter.weapon) == "hunting"
		if Vector2(float(shooter.x) - float(z.x), float(shooter.y) - float(z.y)).length() <= (HITSTOP_SHOTGUN_RANGE if shotgun else HITSTOP_RANGE):
			hitstop = maxf(hitstop, HITSTOP_SHOTGUN_S if shotgun else HITSTOP_S)
			_hitstop_gap = HITSTOP_GAP
			hitstops_asked += 1
			if shotgun:
				# (FEEL: a pump gun's kill is a beat, not a stutter: 26 ms, and the camera takes a tiny push along the blast, on top of the gun's own kick back)
				_push += dir * KILL_PUSH_PX
				if _push.length() > KICK_MAX:
					_push = _push.normalized() * KICK_MAX


func _happen(w: Dictionary) -> void:
	match String(w.what):
		"land":
			_add(K_DUST, w.x, w.y, 0.0, _rand_range(-0.25, 0.25), _rand_range(-0.2, 0.0), 0.0, _rand_range(0.45, 0.7), 0.10, Color(0.80, 0.76, 0.66, 0.34), 0.55)
			_add(K_DUST, w.x - 0.15, w.y + 0.04, 0.0, _rand_range(-0.3, 0.0), _rand_range(-0.1, 0.1), 0.0, _rand_range(0.4, 0.6), 0.07, Color(0.78, 0.74, 0.66, 0.28), 0.5)
		"sound":
			_say(String(w.name), Vector2(w.x, w.y), float(w.level), float(w.get("var", 0.05)), float(w.get("pitch", 1.0)), 0.0)


## A casing bounced on the ground (fx.gd): a small bright tick, if it is close.
func casing_tink(x: float, y: float) -> void:
	if sound == null or not enabled or Vector2(x, y).distance_to(listener) > 14.0:
		return
	_say("casing", Vector2(x, y), 0.55, 0.1, 1.0, 0.07)


## A bullet stopped by a wall (fx.hit_material, kind "bullet"): warm sparks, chips, dust and the zing of a ricochet.
func hit_wall(x: float, y: float) -> void:
	if not enabled:
		return
	for i in 6:
		var a := rng.randf() * TAU
		var sp := _rand_range(1.5, 4.5)
		_add(K_SPARK, x, y, _rand_range(0.4, 0.6), cos(a) * sp, sin(a) * sp, _rand_range(0.5, 2.0), _rand_range(0.14, 0.28), 0.028, Color(1.0, 0.82, 0.46))
	for i in 3:
		var a2 := rng.randf() * TAU
		var sp2 := _rand_range(0.6, 1.8)
		_add(K_CHIP, x, y, 0.5, cos(a2) * sp2, sin(a2) * sp2, _rand_range(0.8, 2.2), 0.9, _rand_range(0.025, 0.045), Color(0.66, 0.64, 0.60))
	_add(K_DUST, x, y, 0.0, _rand_range(-0.2, 0.2), _rand_range(-0.3, 0.0), 0.0, _rand_range(0.45, 0.65), 0.09, Color(0.78, 0.74, 0.66, 0.34), 0.6)
	_add(K_STAR, x, y, 0.0, 0.0, 0.0, 0.0, 0.07, 0.2, Color(1.0, 0.9, 0.62))
	_add(K_GLOW, x, y - 0.3, 0.0, 0.0, 0.0, 0.0, 0.09, 0.36, Color(1.0, 0.72, 0.38))
	_say("hit_wall", Vector2(x, y), 0.8, 0.08, 1.0, 0.12)


# -------------------------------------------------------- the struck dead --

## A heavy blow or step of one of the dead at `at` (tiles) with strength `k` (1 a blow, less a footfall): the camera is pushed a hair, less the farther it is, nothing under "reduce motion".
func thump(at: Vector2, k: float) -> void:
	if not enabled or calm:
		return
	var near := 1.0 - at.distance_to(listener) / 12.0
	if near <= 0.0:
		return
	_push += Vector2.from_angle(rng.randf() * TAU) * (1.6 * k * near)
	if _push.length() > KICK_MAX:
		_push = _push.normalized() * KICK_MAX


## Moves and lights the picture of one of the dead for the effects on it: knock-back, the slide of a fall, the white flash. `node` is its pawn
## (scripts/render/pawn_node.gd), already placed this frame. Most of the dead have nothing on them: a lookup in two dictionaries.
func apply(z, node) -> void:
	if not enabled:
		return
	var st: String = z.state
	if st == "dying" or st == "dead":
		var rec = _fallen.get(z)
		if rec == null:
			return
		if bool(rec.flash):
			rec.flash = false
			_wash(node, bool(rec.plate))
		if rec.has("off"):
			node.position += rec.off    # (settled: where it lies is worked out once)
			return
		var f := clampf(float(z.fall), 0.0, 1.0)
		var e := 1.0 - (1.0 - f) * (1.0 - f)
		var off: Vector2 = rec.dir * float(rec.mag) * e * TILE
		if not calm:
			off.y -= sin(f * PI) * 0.06 * TILE
		if f >= 1.0 or st == "dead":
			rec["off"] = off
		node.position += off
		return
	if _hurt.is_empty():
		return
	var hrec = _hurt.get(z)
	if hrec == null:
		return
	var age := t - float(hrec.t0)
	if age < 0.5 and not calm:
		node.position += hrec.dir * float(hrec.kick) * exp(-age * 16.0) * TILE
	if bool(hrec.flash):
		hrec.flash = false
		if node.has_method("flinch"):
			node.flinch(hrec.dir)    # (ANIM: it jerks away from the blow for a couple of frames)
		_wash(node, bool(hrec.plate))


static var _flash_flesh: ShaderMaterial
static var _flash_plate: ShaderMaterial
static var _flash_soft: ShaderMaterial
## How long the gentle wash of "Reduce flashes" is worn (real seconds): a tenth, not a blink.
const FLASH_SOFT_S := 0.11


## The white wash of a hit on `node`: nothing under Reduce motion, a pale tint over a tenth of a second under Reduce flashes, else the blink.
func _wash(node, plate: bool) -> void:
	if soft and not calm:
		node.flash(flash_material_soft(), FLASH_SOFT_S, false)
		return
	node.flash(flash_material(plate), FLASH_S, calm)


## The pale tint a hit leaves under "Reduce flashes" (a fifth of the way to white, steel or flesh alike).
static func flash_material_soft() -> ShaderMaterial:
	if _flash_soft == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform vec3 tint = vec3(1.0);\nuniform float amount = 0.2;\nvoid fragment() {\n\tCOLOR.rgb = mix(COLOR.rgb, tint, amount * step(0.02, COLOR.a));\n}\n"
		_flash_soft = ShaderMaterial.new()
		_flash_soft.shader = sh
		_flash_soft.set_shader_parameter("tint", Vector3(1.0, 0.97, 0.94))
	return _flash_soft


## The material of the white flash of a hit (cold and blue for steel): the pawn wears it for a few frames.
static func flash_material(plate: bool) -> ShaderMaterial:
	if _flash_flesh == null:
		var code := "shader_type canvas_item;\nuniform vec3 tint = vec3(1.0);\nuniform float amount = 0.85;\nvoid fragment() {\n\tCOLOR.rgb = mix(COLOR.rgb, tint, amount * step(0.02, COLOR.a));\n}\n"
		var sh := Shader.new()
		sh.code = code
		_flash_flesh = ShaderMaterial.new()
		_flash_flesh.shader = sh
		_flash_flesh.set_shader_parameter("tint", Vector3(1.0, 0.97, 0.94))
		_flash_plate = ShaderMaterial.new()
		_flash_plate.shader = sh
		_flash_plate.set_shader_parameter("tint", Vector3(0.74, 0.88, 1.0))
		_flash_plate.set_shader_parameter("amount", 0.7)
	return _flash_plate if plate else _flash_flesh


# ------------------------------------------------------------- the sounds --

## A sound of the fight, by distance to the camera, with a little wobble of pitch and loudness (never under the rules' random source).
func _say(name: String, at: Vector2, level: float, pitch_var: float, pitch: float, min_gap: float) -> void:
	if sound == null or not enabled:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if min_gap > 0.0:
		var last: float = _snd_at.get(name, -10.0)
		if now - last < min_gap:
			return
		_snd_at[name] = now
	var vol := clampf(1.0 - at.distance_to(listener) / 50.0, 0.12, 1.0) * level * _rand_range(0.88, 1.0)
	sound.play(name, vol, pitch_var, pitch)


## A sound `delay` seconds (of the game's time) from now.
func say_later(name: String, at: Vector2, level: float, delay: float, pitch: float = 1.0) -> void:
	if _later.size() < MAX_LATER:
		_later.append({"at": t + delay, "what": "sound", "name": name, "x": at.x, "y": at.y, "level": level, "pitch": pitch})


## The shot's own sound (main.gd, from the rules' "shot" event): the weapon by name, a little louder or softer and higher or lower each time.
func shot_sound(e: Dictionary) -> void:
	if sound == null or not enabled:
		return
	var gun := String(e.get("gun", ""))
	var name := "shot_%s" % (gun if gun != "" else String(e.weapon))
	if not sound.streams.has(name) or sound.streams[name].is_empty():
		name = "shot_%s" % String(e.weapon)
	if sound.get("gunfight") != null and sound.gunfight.shot(e, listener):
		return    # (the SOUND pass: the pump gun's blast, in a room or in the open: scripts/audio/fight_sounds.gd)
	var at := Vector2(float(e.x), float(e.y))
	var vol := clampf(1.0 - at.distance_to(listener) / 50.0, 0.12, 1.0) * 0.8 * _rand_range(0.9, 1.0)
	sound.play(name, vol * float(e.get("vol", 1.0)), 0.045, float(e.get("pitch", 1.0)))


## The sound of the dead one's fall (main.gd, from the "thud" event): the body comes down a moment after the blow.
func thud_sound(e: Dictionary) -> void:
	if not enabled:
		return
	if sound != null and not calm:
		say_later("thud", Vector2(float(e.x), float(e.y)), 1.0, 0.28)
	elif sound != null:
		_say("thud", Vector2(float(e.x), float(e.y)), 1.0, 0.05, 1.0, 0.0)


# ------------------------------------------------------- the trigger, reload --

## The trigger pulled on a gun that cannot fire (the magazine is empty or being filled): a dry click, and the word at the avatar for a moment.
func dry_fire(me) -> bool:
	var now := real_t
	if now - dry_t < 0.32:
		return false
	dry_t = now
	dry_word = "reloading" if float(me.reloading) > 0.0 else "empty"
	if sound != null and enabled:
		sound.play("dry_click", 0.85, 0.04)
	return true


## How long ago the last dry pull was (real seconds; large when there is none).
func dry_age() -> float:
	return real_t - dry_t


## The reload of the avatar's gun, frame by frame (main.gd): its notches, the click of each shell, the pump or the bolt at the end. `me` is the
## person, `sim` the rules, `dt` the real frame. A magazine gun gets its magazine's out and in; the shotgun and the other guns with a few
## rounds get a shell for each notch. (The rules fill the magazine in one go at the end of the time; this is the picture and the sound.)
func reload_tick(me, sim, dt: float) -> void:
	if me == null or not enabled:
		_rl_on = false
		return
	var rl := float(me.reloading)
	var gun: Dictionary = me.gun
	if rl > 0.0:
		if not _rl_on:
			_rl_on = true
			_rl_gun = String(me.weapon)
			_rl_cap = int(gun.get("mag", 0))
			_rl_m0 = int(me.mag)
			_rl_total = maxf(0.01, float(gun.get("reload", 1.0)) * float(sim.traits.mult(me, "reload")))
			_rl_notch = 0
			if _rl_m0 <= 0:
				dry_t = real_t
				dry_word = "empty"
			if not _shell_gun():
				_say_now("mag_out", 0.8)
		var p := clampf(1.0 - rl / _rl_total, 0.0, 1.0)
		if _shell_gun():
			var n := maxi(1, _rl_cap - _rl_m0)
			var due := mini(n, int(floor(p * float(n) + 0.02)))
			while _rl_notch < due:
				_rl_notch += 1
				_say_now("shell_in", 0.85)
		elif _rl_notch == 0 and p >= 0.55:
			_rl_notch = 1
			_say_now("mag_in", 0.85)
	elif _rl_on:
		_rl_on = false
		_say_now("pump" if _shell_gun() else "bolt", 0.9)
	_rl_prev = rl


func _shell_gun() -> bool:
	return _rl_cap > 0 and _rl_cap <= 8 and _rl_gun != "pistol"


func _say_now(name: String, level: float) -> void:
	if sound != null:
		sound.play(name, level * _rand_range(0.9, 1.0), 0.04)


## The sound at the start of a reload (the rules' "reload" event): false when the avatar's own reload has its sounds (reload_tick) and the old
## all-in-one sample is not wanted.
func reload_event(e: Dictionary, me) -> bool:
	if me == null or not enabled:
		return false
	return Vector2(float(e.x), float(e.y)).distance_to(Vector2(float(me.x), float(me.y))) < 0.01


## The reload being shown: {"on", "notches" (0: a plain ring), "filled", "progress"}; the overlay draws the ring from it.
func reload_view(me, sim) -> Dictionary:
	if not _rl_on or me == null:
		return {"on": false, "notches": 0, "filled": 0, "progress": 0.0}
	var p := clampf(1.0 - float(me.reloading) / _rl_total, 0.0, 1.0)
	var notches := maxi(1, _rl_cap - _rl_m0) if _shell_gun() else 0
	return {"on": true, "notches": notches, "filled": mini(notches, int(floor(p * float(maxi(notches, 1)) + 0.02))), "progress": p}


# ---------------------------------------------------------------- decals --

## A splat of blood on the ground (fx.decal): a pooled sprite that grows a little, holds, and fades away; the oldest goes at the cap.
func decal(x: float, y: float, size: float, grow: float = 0.0, alpha: float = 0.85) -> void:
	if decal_parent == null or _blood_tex.is_empty() or not enabled:
		return
	if store != null:
		# (FEEL, the town: a kill's splat (it grows) is a pool that stays for about 80 s, a drop's a speck for about 50; both in one draw: blood_store.gd)
		store.add(x, y, size * 3.0, alpha, grow > 0.0, grow)
		return
	var s: Sprite2D
	if not _spare.is_empty():
		s = _spare.pop_back()
	elif _decals.size() >= MAX_DECALS:
		s = _decals.pop_front().node
	else:
		s = Sprite2D.new()
		decal_parent.add_child(s)
	s.texture = _blood_tex[rng.randi() % _blood_tex.size()]
	s.position = Vector2(x, y) * TILE
	s.rotation = rng.randf() * TAU
	s.modulate = Color(1, 1, 1, alpha)
	s.visible = true
	var d := {"node": s, "size": size, "grow": grow, "age": 0.0, "alpha": alpha}
	_scale_decal(d)
	_decals.append(d)


func _scale_decal(d: Dictionary) -> void:
	# the splat's picture spans three decal sizes
	var s: Sprite2D = d.node
	s.scale = Vector2.ONE * (float(d.size) * 3.0 * TILE / float(s.texture.get_width()))


func _age_decals(dt: float) -> void:
	if _decals.is_empty():
		return
	var expired := 0
	for d in _decals:
		d.age += dt
		var age: float = d.age
		if float(d.grow) > 0.0 and age < 3.0:
			d.size += float(d.grow) * dt / 3.0
			_scale_decal(d)
		if age > decal_hold:
			var k := clampf((age - decal_hold) / (decal_life - decal_hold), 0.0, 1.0)
			var a := float(d.alpha) * (1.0 - k * k * (3.0 - 2.0 * k))
			d.node.modulate.a = a
			if age >= decal_life:
				expired += 1
	if expired > 0:
		var keep: Array = []
		for d in _decals:
			if float(d.age) >= decal_life:
				d.node.visible = false
				_spare.append(d.node)
			else:
				keep.append(d)
		_decals = keep


# ---------------------------------------------------------------- drawing --
# Painters are called by nodes (fx.gd's); they draw in tile units.

## Over the ground, under the light of the night: blood in the air and as mist, dust and smoke, chips.
func draw_air(ci: CanvasItem) -> void:
	if not enabled or _live <= 0:
		return
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for i in MAX_PARTS:
		var l := _life[i]
		if l <= 0.0:
			continue
		var k := _kind[i]
		if k == K_BLOOD:
			ci.draw_circle(Vector2(_x[i], _y[i] - _z[i] * 0.6), _size[i], _col[i])
		elif k == K_MIST or k == K_DUST:
			var c: Color = _col[i]
			var fade := l / _max[i]
			c.a *= fade * minf(1.0, (1.0 - fade) * 8.0 + 0.3)
			var r := _size[i]
			var tex := puff_dark if k == K_MIST else puff_light
			ci.draw_texture_rect(tex, Rect2(_x[i] - r, _y[i] - r, r * 2.0, r * 2.0), false, c)
		elif k == K_CHIP:
			var c2: Color = _col[i]
			c2.a = minf(1.0, l * 3.0)
			var s := _size[i]
			ci.draw_rect(Rect2(_x[i] - s, _y[i] - _z[i] * 0.6 - s * 0.6, s * 2.0, s * 1.2), c2)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Added to the picture, over the night: the muzzle flashes (a star, a glow, the pump gun's cone), sparks, the stars and rings of a hit, the
## steel of a plated brute lit by a hit.
func draw_add(ci: CanvasItem) -> void:
	if not enabled:
		return
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for f in _flashes:
		_draw_flash(ci, f)
	for b in _blows:
		_draw_blow(ci, b)
	if _live > 0:
		for i in MAX_PARTS:
			var l := _life[i]
			if l <= 0.0:
				continue
			var k := _kind[i]
			if k == K_SPARK:
				var a := Vector2(_x[i], _y[i] - _z[i] * 0.6)
				var tail := Vector2(_vx[i], _vy[i] - _vz[i] * 0.6) * 0.07
				var c: Color = _col[i]
				c.a = minf(1.0, l * 6.0)
				ci.draw_line(a, a - tail, c, _size[i], true)
			elif k == K_STAR:
				var fade := l / _max[i]
				var r := _size[i] * (1.0 + (1.0 - fade) * 0.7) * zoom_k
				var c2: Color = _col[i]
				c2.a = fade
				ci.draw_colored_polygon(_star(Vector2(_x[i], _y[i]), r, r * 0.28, 4, float(i) * 0.7), c2)
				ci.draw_circle(Vector2(_x[i], _y[i]), r * 0.35, Color(1, 1, 1, fade))
			elif k == K_GLOW:
				var fade3 := l / _max[i]
				var gr := _size[i] * (1.0 + (1.0 - fade3) * 0.5) * zoom_k
				var c4: Color = _col[i]
				c4.a = 0.9 * fade3
				ci.draw_texture_rect(radial, Rect2(_x[i] - gr, _y[i] - gr, gr * 2.0, gr * 2.0), false, c4)
			elif k == K_RING:
				var fade2 := l / _max[i]
				var c3: Color = _col[i]
				c3.a = fade2
				ci.draw_arc(Vector2(_x[i], _y[i]), _size[i] * zoom_k, 0.0, TAU, 16, c3, 0.03 * zoom_k, true)
	if not _hurt.is_empty():
		for z in _hurt:
			var rec: Dictionary = _hurt[z]
			if bool(rec.plate):
				_draw_plate_glow(ci, z, rec)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## The trail of a swing: a crescent band whose bright head runs across the arc in the first half of `blow_s` and whose tail fades behind it, then the whole
## of it fades. (Under "reduce motion" the head does not sweep: the band is there, whole, and fades; under "reduce flashes" it is about half as bright.)
func _draw_blow(ci: CanvasItem, b: Dictionary) -> void:
	var k: float = clampf(float(b.t) / blow_s, 0.0, 1.0)
	var amp := 0.55 if soft else 1.0
	var half: float = b.half
	var reach: float = b.reach
	var head := 1.0 if calm else clampf(k * 2.2, 0.0, 1.0)
	var lead: float = lerpf(-half, half, head)
	var tail: float = maxf(-half, lead - 1.5) if not calm else -half
	var fade := 1.0 - k * k
	var steps := 10
	var inner := reach * 0.45
	var outer_pts := PackedVector2Array()
	var inner_pts := PackedVector2Array()
	var cols := PackedColorArray()
	var o := Vector2(b.x, b.y)
	for i in steps + 1:
		var a := float(b.aim) + lerpf(tail, lead, float(i) / float(steps))
		var u := float(i) / float(steps)    # 0 at the tail, 1 at the head
		outer_pts.append(o + Vector2.from_angle(a) * reach)
		inner_pts.append(o + Vector2.from_angle(a) * inner)
		cols.append(Color(1.0, 0.96, 0.84, 0.8 * u * fade * amp))
	var pts := PackedVector2Array()
	var colors := PackedColorArray()
	for i in steps + 1:
		pts.append(outer_pts[i])
		colors.append(cols[i])
	for i in range(steps, -1, -1):
		pts.append(inner_pts[i])
		colors.append(Color(cols[i].r, cols[i].g, cols[i].b, cols[i].a * 0.25))
	ci.draw_polygon(pts, colors)
	ci.draw_polyline(outer_pts, Color(1.0, 0.98, 0.9, 0.9 * fade * amp), 0.04, true)


func _draw_flash(ci: CanvasItem, f: Dictionary) -> void:
	var g: Dictionary = GUNS.get(f.gun, GUNS.rifle)
	var k: float = clampf(1.0 - float(f.t) / float(f.dur), 0.0, 1.0)
	var dim := 0.3 if soft else (0.6 if calm else 1.0)
	# (FEEL, from LIGHT: the first frame of a flash is a little under half the strength, and it is full by the third (about 34 ms), so that the additive glow does not wash the shooter out)
	var ramp := lerpf(FLASH_GLOW_FIRST, 1.0, clampf(float(f.t) / FLASH_GLOW_RAMP_S, 0.0, 1.0))
	dim *= ramp
	var at := Vector2(f.x, f.y)
	var ang: float = f.ang
	var reach_len: float = float(g.len) * (0.65 + 0.35 * k) * zoom_k
	var gr: float = float(g.glow) * (0.6 + 0.4 * k) * zoom_k
	ci.draw_texture_rect(radial, Rect2(at.x - gr, at.y - gr, gr * 2.0, gr * 2.0), false, Color(WARM.r, WARM.g, WARM.b, 0.9 * k * dim))
	# the cone of the pump gun: a fan from the muzzle that is gone in a few frames
	var cone: float = float(g.cone)
	if cone > 0.0:
		var reach := reach_len * 1.8
		var pts := PackedVector2Array([at])
		var cols := PackedColorArray([Color(1.0, 0.9, 0.6, 0.65 * k * dim)])
		for j in 7:
			var a := ang + lerpf(-cone, cone, float(j) / 6.0)
			pts.append(at + Vector2.from_angle(a) * reach)
			cols.append(Color(1.0, 0.7, 0.35, 0.0))
		ci.draw_polygon(pts, cols)
	# the star: a long spike along the barrel, shorter ones to the sides and back, in orange, then pale yellow, then a white heart
	var rot: float = float(f.rot)
	var outer := _flash_star(at, ang + rot * 0.15, reach_len, 1.0)
	ci.draw_colored_polygon(outer, Color(1.0, 0.62, 0.22, 0.85 * k * dim))
	var inner := _flash_star(at, ang + rot * 0.15, reach_len * 0.62, 0.7)
	ci.draw_colored_polygon(inner, Color(PALE.r, PALE.g, PALE.b, k * dim))
	ci.draw_circle(at, float(g.glow) * 0.22 * (0.5 + 0.5 * k), Color(1.0, 1.0, 0.95, k * dim))


## The star of a muzzle flash as a polygon: spikes at 0 (forward, `len`), +-30, +-80 and +-140 degrees and straight back.
func _flash_star(at: Vector2, ang: float, tip: float, width: float) -> PackedVector2Array:
	var spikes := [[0.0, 1.0], [0.52, 0.5], [1.4, 0.3], [2.45, 0.2], [PI, 0.16], [-2.45, 0.2], [-1.4, 0.3], [-0.52, 0.5]]
	var pts := PackedVector2Array()
	for j in spikes.size():
		var a0: float = spikes[j][0]
		var a1: float = spikes[(j + 1) % spikes.size()][0]
		if a1 < a0:
			a1 += TAU
		pts.append(at + Vector2.from_angle(ang + a0) * tip * float(spikes[j][1]))
		pts.append(at + Vector2.from_angle(ang + (a0 + a1) * 0.5) * tip * 0.13 * width)
	return pts


func _star(c: Vector2, r_out: float, r_in: float, spikes: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in spikes * 2:
		var r := r_out if j % 2 == 0 else r_in
		pts.append(c + Vector2.from_angle(rot + PI * float(j) / float(spikes)) * r)
	return pts


## The steel of a plated brute shown lit for a moment by a hit that rang on it (the same plates the overlay draws: shoulders and a chest).
func _draw_plate_glow(ci: CanvasItem, z, rec: Dictionary) -> void:
	var age := t - float(rec.t0)
	if age > 0.22:
		return
	var k := 1.0 - age / 0.22
	var size := float(z.size)
	var box: Rect2 = Art.hit_box(Art.kind_of(z), Art.size_of(z))
	var hw := box.size.x * 0.5
	var top := box.position.y
	var h := box.size.y
	var y0 := top + h * 0.38
	var y1 := top + h * 0.68
	var xw := hw * 0.6
	var o := Vector2(float(z.x), float(z.y))
	var chest := PackedVector2Array([o + Vector2(-xw, y0), o + Vector2(xw, y0), o + Vector2(xw * 0.82, y1), o + Vector2(-xw * 0.82, y1)])
	ci.draw_colored_polygon(chest, Color(0.70, 0.86, 1.0, 0.9 * k))
	for side in [-1.0, 1.0]:
		ci.draw_circle(o + Vector2(side * xw, y0 + h * 0.03), hw * 0.27, Color(0.72, 0.88, 1.0, 0.55 * k))
