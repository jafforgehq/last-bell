## One person or one of the dead on the map. Its position is the character's feet,
## so a y-sorted parent puts whoever stands further south in front. Draws the baked
## body sprite plus live legs, arms and weapon, the way the web version did. The
## dead come in kinds (walker, runner, brute): the same figure scaled, leaned and
## tinted by pawn_art.gd's STYLES, so a kind reads at a glance; a walker is drawn
## exactly as ever.
##
## ANIM (render side only: the rules are read, never written): every figure keeps a drawn facing that eases to the rules' in about 100 ms (the body is a little narrower
## across the seam between two views, the weapon's shoulder slides), a person's legs run from a neutral pose to a neutral pose, the body bobs, sways and leans into its speed, a shot kicks
## the body and the muzzle, a reload is a hand to the gun, a swing coils, strikes and recovers on assets/data/melee.json's timings; the dead have a gait of their own, rear back and lunge on the
## rules' own beat of claw and bite (`attack_t`), flinch from a hit, and fall in a quarter of a second. All of it is in `_anim*` (state) and the `_draw_*` (transforms) here, with the pure
## maths in scripts/render/pawn_motion.gd; "Reduce motion" keeps 30 percent of every bob, sway, lean and swing.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/render/pawn_art.gd")
const S := preload("res://scripts/render/shapes.gd")
const WorkAnim := preload("res://scripts/render/work_anim.gd")
const PawnMesh := preload("res://scripts/render/pawn_mesh.gd")
const Combat := preload("res://scripts/render/combat_fx.gd")
const Prefs := preload("res://scripts/prefs.gd")
const PawnMotion := preload("res://scripts/render/pawn_motion.gd")
const TILE := GD.TILE
## How the dead are dimmed (a person who died lies where they fell).
const DEAD_TINT := Color(0.62, 0.6, 0.6)
const PIVOT := {"S": Vector2(-0.04, -0.08), "E": Vector2(0.08, -0.14), "N": Vector2(0.26, -0.22)}
## A jump of more than this many tiles between two steps (back from a trip, a
## walker risen where a survivor fell) is a jump, not a walk: no sliding.
const SNAP_TILES := 3.0
## ANIM: how much of the way to where the rules put them the crew and the dead are drawn at each step (the rest is kept for the next).
const STEP_FOLLOW_CREW := 0.65
const STEP_FOLLOW_DEAD := 0.55
## `_strike_seen` before any blow has been counted.
const NO_STRIKE := -1000000000

var entity # Sim.Person or Sim.Zombie
var zombie := false
## How a zombie is drawn: its kind when pawn_art.gd has a build for it, else "walker".
var kind := "walker"
var tex := {} # view -> Texture2D
var pawn_rect: Rect2
var weapon_tex: Texture2D
## The prison's figures (set by prison_game.gd, off everywhere else): `smooth_turn` keeps a continuous drawn angle that turns at a limited rate toward the way the figure goes or aims
## (the walkers' 4 baked views are crossfaded across each seam, the weapon is drawn at the exact angle); `rifles_ready` draws a guard's "watch" as the rifle at the low ready, not binoculars.
static var smooth_turn := false
static var rifles_ready := false
const TURN_PERSON := deg_to_rad(220.0)
const TURN_AIM := deg_to_rad(360.0)
const TURN_BUSY := deg_to_rad(130.0)
const TURN_DEAD := deg_to_rad(120.0)
## The low ready: how far a rifle that is not being aimed is carried toward the low carry (0 shouldered at the aim, 1 fully low), eased (`_rdy`).
const READY_LOW := 0.5
var _rdy := 0.0
var _zpos := Vector2.ZERO
## A person whose def says `unarmed` (the prison's kids) never draws a weapon, in hand, put away or at work.
var unarmed := false
var weapon_rect: Rect2
var gun_front = null
var anim_t := 0.0
var pal: Dictionary
var beds: Array = [] # the cots and mattresses of the map, to find the blanket colour
var _bed_key := ""
var _bed_col := Color("#9a9070")
var _m := Transform2D.IDENTITY
## Where the rules had the character at their last two steps, in tiles: they
## move once per step, and the node is drawn between the two (see sync).
var _prev := Vector2.ZERO
var _cur := Vector2.ZERO
var _steps_seen := -1
var _frame_seen := 0
## The step of the rules the picture was last made for (-2: none yet). One of the dead is drawn from what the rules have of it, which
## changes once a step, so it is not drawn again until the next step: its place on the screen is the node's own position, moved every frame.
var _drawn_steps := -2
## How many times a node has drawn, over all nodes (what a test reads, in `draw_count`, to see that a node out of sight was left
## alone; an underscore, so that the tests' guard of the shared state takes it for a counter, not a setting).
static var _draws := 0
var _style: Dictionary = Art.WALKER
var _meshes := {} # view -> the warped sprite of this kind, or null for the plain one
## Where the drawing goes: this node, or a stand-in that records the calls (tests).
var _pen = self
## Whether the live parts (shadow, legs, arms, hands) are drawn as baked meshes (scripts/render/pawn_mesh.gd) rather than
## command by command (pawn_art.gd): on the screen they are; a stand-in for the canvas gets the commands (what the tests
## of the figure's look read), unless `meshes_on_tape` asks for the meshes (what the tests of the cached drawing read).
var cached := true
var meshes_on_tape := false
var _fast := false
## The colours of this figure for the meshes: one texel for each of the palette's colours.
var _pal_tex: Texture2D

## The material this figure wears when it is not flashing (the tint of its kind, or none), and when a hit's flash ends (real milliseconds).
var _base_material: Material = null
var _flash_end_ms := 0

## Round 16, people at work (scripts/render/work_anim.gd): the pose is kept in one object and the work clock is shown between the
## rules' steps. `_wk` is how far into the pose the person is (0 the ordinary figure, 1 the pose), moved over WorkAnim.EASE seconds
## of the screen's clock (`anim_t`) toward where `Person.work` says it should be, so a person who stops working is back to normal
## within 0.2 s. `on_work_strike(word, x, y)`, when set, is called as a tool lands (the sound, which main.gd may play).
var _wpose := WorkAnim.Pose.new()
var _wk := 0.0
var _w_word := ""
var _w_last := ""
var _work_phase := 0.0
var _wt_prev := 0.0
var _wt_cur := 0.0
var _w_steps := -1
var _w_alpha := 1.0
var _anim_prev := -1.0
var _strike_seen := NO_STRIKE
var on_work_strike: Callable = Callable()
## A job staged for a screenshot (`--work=<id>:<word>[@seconds]`): the word to show whatever the rules say, and a work time to hold
## (negative: let it run on the clock).
var work_stage := ""
var work_stage_t := -1.0
## Whether `Person.work` is drawn at all: false in a trip played by hand (scripts/raid), where the base's rules do not run.
var work_poses := true

## ANIM (scripts/render/pawn_motion.gd says what each is for). The figure's own render-side state, moved every frame by `_anim` (called from `sync`, with the screen's clock): the drawn
## facing, the stride, the speed, the kick of a shot, the swing, the reload, and for the dead the attack, the flinch and the fall. None of it is read by the rules and none is saved.
var _a_prev := -1.0
var _ori := PI / 2.0
var _ori_ok := false
## The view drawn ("E", "S", "N"; the west is "E" mirrored: `_mir`) and how wide the body is drawn across it (1, less across a turn).
var _vw := "S"
var _mir := false
var _wid := 1.0
## Walking: 0 standing to 1 striding (eased), the stride's phase as drawn (it starts and ends on a neutral pose), the rules' phase a step ago and now, whether the legs are drawn striding.
var _gait := 0.0
var _rph := 0.0
var _ph_prev := 0.0
var _ph_cur := 0.0
var _ph_off := 0.0
var _stepping := false
var _moving_draw := false
## How fast the figure is drawn going (tiles a second, smoothed) and where its node was a frame ago.
var _vel := Vector2.ZERO
var _pos_last := Vector2.ZERO
var _pos_ok := false
## The kick of the last shot as drawn (1 at the shot, falling over about 150 ms), seconds since it, the weapon lowered (a run, the holster) and the holster alone (both eased).
var _rk := 0.0
var _shot_age := 9.0
var _lowk := 0.0
var _holk := 0.0
## The swing's clock as drawn (seconds from the key, -1 none) and its pose, and the reload's (the seconds it was started with, the rounds in the gun then) and its pose.
var _sw := -1.0
var _sw_pose: PawnMotion.Swing = null
var _thrust_seen := 0.0
var _rl_total := 0.0
var _rl_m0 := 0
var _rl: PawnMotion.Reload = null## A figure's own place in things (0 to 1, from the entity): its breath, the dead's gait.
var _seed := 0.0
## The dead: how far into an attack (eased), the zombie's `attack_t` at the last look, seconds since it struck, the flinch (seconds since the hit and the way it was thrown), the stagger seen,
## the thump a heavy step or blow asks the camera for, and the step of the stride it is in.
var _atk := 0.0
var _at_seen := 0.0
var _strike_age := 9.0
var _fl_t := 9.0
var _fl_dir := Vector2.ZERO
var _stag_seen := 0.0
var _thump := 0.0
var _step_i := 0
## FEEL: the figure's integer seed (its entity's instance id), what a dead one has of its own (pawn_motion.gd `dead_variant`), the legs' phase as drawn (the rules' times its gait plus its own
## start), whether the last frame of a person's stride was a stride (a step is told only when the foot changes), and how startled a person is by a shot near them (1 at the shot, to 0).
var _seed_i := 0
var _dv: PawnMotion.Dead = null
var _vphase := 0.0
var _step_ok := false
var _alert := 0.0
var _alert_t := 0.0
var _land := 0.0
## Whether the figure is changing fast (a strike, a flinch, a turn): one of the dead is then drawn every frame, not once a step.
var _hot := false
## The dead's facing: the rules' last, the angle it is, and whether the drawn facing is still on its way.
var _acc_dt := 0.0
var _face_seen := ""
var _tgt_ori := PI / 2.0
var _turning := true
## The kind of build the legs have: a person's livelier stride, or the dead's own kind.
var _leg_kind := "person"


func setup(e, is_zombie: bool, data: Dictionary, key: String) -> void:
	entity = e
	zombie = is_zombie
	var box: Array = data.pawn.box
	pawn_rect = Rect2(box[0], box[1], box[2] - box[0], box[3] - box[1])
	for v in ["S", "E", "N"]:
		tex[v] = GD.tex(data.pawn.files[key][v])
	pal = Art.palette(e.look)
	_pal_tex = PawnMesh.palette_texture(pal)
	_seed_i = int(e.get_instance_id())
	_seed = fposmod(float(e.get_instance_id()) * 0.6180339887, 1.0)    # (as it was: a person's breath and a walker's idle sway read it)
	if zombie:
		kind = Art.kind_of(e)
		_leg_kind = kind
		_style = Art.style(kind)
		_dv = PawnMotion.dead_variant(_seed_i, kind)    # (FEEL: its own gait, lean, tilt, carry, size and dirt, from its seed)
		var tinted := Art.material(kind)
		if tinted != null:
			material = tinted
			_base_material = tinted
	if not zombie:
		_style = Art.PERSON
		_sw_pose = PawnMotion.Swing.new()
		_rl = PawnMotion.Reload.new()
		_work_phase = WorkAnim.phase_of(String(e.id))
		var wb: Array = data.weaponArt.box
		weapon_rect = Rect2(wb[0], wb[1], wb[2] - wb[0], wb[3] - wb[1])
		weapon_tex = GD.tex(data.weaponArt.files[e.weapon])
		gun_front = data.guns[e.weapon].front
		unarmed = bool((e.def as Dictionary).get("unarmed", false))
		for o in data.objects:
			if o.kind == "cot" or o.kind == "mattress":
				beds.append(o)
	sync()


## A hit lands on this one: it is washed with `mat` (the white of a hit, steel blue for a plate) for `secs` real seconds, then its own material is back
## (sync does that). With `soft` (Settings, reduce motion) nothing flashes.
func flash(mat: Material, secs: float, soft: bool = false) -> void:
	if soft:
		return
	material = mat
	_flash_end_ms = Time.get_ticks_msec() + int(secs * 1000.0)


## The weapon in this person's hands changed (a screenshot's `--weapon=`): its picture and where the hands go on it.
func set_weapon(data: Dictionary, id: String) -> void:
	weapon_tex = GD.tex(data.weaponArt.files[id])
	gun_front = data.guns[id].front
	queue_redraw()


## `steps` is how many steps the rules have taken, `alpha` how far the time has
## run into the next one: the node is drawn that far from where the character
## stood one step ago to where they stand now, so a 144 Hz screen shows smooth
## walking though the rules move 30 times a second. Called without them it is
## drawn where the character is, as it is on a first look, when the node was out
## of sight a frame ago, and after a jump of more than SNAP_TILES.
func sync(redraw: bool = true, steps: int = -1, alpha: float = 1.0) -> void:
	var t_sync := Time.get_ticks_usec()
	_sync_inner(redraw, steps, alpha)
	_sync_us += Time.get_ticks_usec() - t_sync


## The microseconds all nodes have spent in `sync` so far (a measurement's, like `draw_usec`).
static var _sync_us := 0


static func sync_usec() -> int:
	return _sync_us


func _sync_inner(redraw: bool, steps: int, alpha: float) -> void:
	var now := Vector2(entity.x, entity.y)
	var frame := Engine.get_process_frames()
	var jumped := false
	var stepped := steps != _steps_seen
	if _steps_seen < 0 or frame - _frame_seen > 1 or now.distance_to(_cur) > SNAP_TILES:
		_prev = now
		_cur = now
		_ph_prev = entity.walk_phase
		_ph_cur = entity.walk_phase
		jumped = true
	elif steps != _steps_seen:
		_prev = _cur
		# (ANIM: the crew and the dead are drawn a little behind where the rules put them, by a share of a step: a corner, a stop and a shove in a crowd are rounded off; the avatar is exact)
		_cur = now if (not zombie and entity.player) else _cur.lerp(now, STEP_FOLLOW_DEAD if zombie else STEP_FOLLOW_CREW)
		_ph_prev = _ph_cur
		_ph_cur = entity.walk_phase
	_steps_seen = steps
	_frame_seen = frame
	if _flash_end_ms > 0 and Time.get_ticks_msec() >= _flash_end_ms:
		_flash_end_ms = 0
		material = _base_material
	if not zombie:
		_work_sync(steps, alpha)
	var dt := 0.0
	if _a_prev >= 0.0 and not jumped:
		dt = clampf(anim_t - _a_prev, 0.0, 0.1)
	position = _prev.lerp(_cur, alpha) * TILE
	if zombie:
		_anim_dead(dt, jumped, stepped or steps < 0)
	else:
		_anim(jumped, alpha, dt)
	var tint := DEAD_TINT if (not zombie and entity.dead) else Color.WHITE
	if _dv != null:
		tint = _dv.tint
	if modulate != tint:
		modulate = tint
	if redraw and (not zombie or steps < 0 or steps != _drawn_steps or _hot):
		_drawn_steps = steps
		queue_redraw()


## How many times any node has drawn so far.
static func draw_count() -> int:
	return _draws


## Where the node is drawn, in tiles: the overlay's brackets and names go here.
func tile_pos() -> Vector2:
	return position / TILE


# ----------------------------------------------------------------- the motion --

## A hit lands on one of the dead (combat_fx.gd `apply`, with the way the blow went): it flinches away from it for a moment.
func flinch(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		_fl_dir = dir.normalized()
	_fl_t = 0.0
	_hot = true


## One frame of this figure's own motion (called by `sync`, after the node is placed, on the screen's clock): the drawn facing, the speed, and for a person the stride, the kick, the swing and
## the reload, for the dead the attack, the flinch and the thump. `jumped`: the figure was just put somewhere (a first look, a long jump): nothing eases from where it was.
## `alpha` is how far the time has run into the rules' next step.
func _anim(jumped: bool, alpha: float, dt: float) -> void:
	var e = entity
	_a_prev = anim_t
	var rm := PawnMotion.motion()
	var tgt: float = PawnMotion.FACE_ANG.get(String(e.facing), PI / 2.0)
	# FEEL: a crew member standing about, who did not fire it, turns to look at a shot fired near them for about 0.4 s (and starts a little); not the avatar, not one who is at work or walking
	if not e.player and float(e.recoil) <= 0.1 and not e.downed and not e.dead and rm >= 1.0:    # (none under Reduce motion)
		var at := PawnMotion.shot_near(Vector2(e.x, e.y), e, 16.0, 0.4)
		if at != Vector2.INF:
			if _alert_t <= 0.0:
				_alert = 1.0    # (the start: a hitch of the body as the head comes round; a walker on their way is startled too, and goes on)
			_alert_t = 0.4
			if not e.moving and _wk <= 0.0 and e.target == null and float(e.reloading) <= 0.0:
				tgt = PawnMotion.FACE_ANG.get(PawnMotion.facing_toward(Vector2(e.x, e.y), at), tgt)
	if _alert_t > 0.0:
		_alert_t = maxf(0.0, _alert_t - dt)
	_alert = maxf(0.0, _alert - dt * 6.0)
	var rate := 0.0
	if smooth_turn:
		var h := _heading(tgt)
		tgt = h[0]
		rate = h[1]
	if jumped or dt <= 0.0 or not _ori_ok:
		_ori = tgt
		_ori_ok = true
	elif smooth_turn:
		_ori = PawnMotion.turn_at(_ori, tgt, dt, rate)
	else:
		_ori = PawnMotion.turn(_ori, tgt, dt)
	var v := PawnMotion.view_of(_ori)
	_mir = v == "W"
	_vw = "E" if _mir else v
	_wid = 1.0 if smooth_turn else PawnMotion.width(_ori, rm)
	if smooth_turn:
		e.set_meta("drawn_ori", _ori)
	if _pos_ok and dt > 0.0:
		var inst := (position - _pos_last) / (TILE * dt)
		if inst.length_squared() > 81.0:
			inst = inst.limit_length(9.0)
		_vel = _vel.lerp(inst, PawnMotion.ease_k(16.0, dt))
	elif jumped:
		_vel = Vector2.ZERO
	_pos_last = position
	_pos_ok = true
	_anim_person(dt, jumped, alpha, rm)


## The prison's heading: [the angle the figure wants to face, how fast it may turn]. Gun up (aiming, recoil, reload) or Ruth: the aim. Walking: the way it goes. A guard on watch: slowly
## looks about. Standing: where it is, until the rules give it a new facing.
func _heading(face_tgt: float) -> Array:
	var e = entity
	var armed := not unarmed
	var rate := TURN_PERSON
	var word := _work_word()
	if _wk > 0.0 or word == "haul":
		rate = TURN_BUSY
	if armed and (e.player or e.target != null or float(e.recoil) > 0.05 or float(e.reloading) > 0.0):
		return [float(e.aim), TURN_AIM]
	var fs: String = e.facing
	var changed := fs != _face_seen
	_face_seen = fs
	if e.moving and _vel.length() > 0.4:
		return [_vel.angle(), rate]
	if armed and rifles_ready and word == "watch" and not e.moving:
		return [face_tgt + 0.9 * sin(anim_t * 0.35 + _seed * TAU), rate * 0.4]
	if changed or not _ori_ok:
		return [face_tgt, rate]
	return [_ori, rate]


func _anim_person(dt: float, jumped: bool, alpha: float, rm: float) -> void:
	var p = entity
	# the stride: it starts from a neutral pose and runs on to one when the person stops, so the feet never snap from mid-stride to standing
	var ph := lerpf(_ph_prev, _ph_cur, alpha)
	if jumped:
		_stepping = false
	if p.moving:
		if not _stepping:
			_stepping = true
			_rph = roundf(_rph / PI) * PI
			_ph_off = ph - _rph
		_rph = ph - _ph_off
	else:
		_stepping = false
		if not PawnMotion.neutral(_rph):
			_rph = PawnMotion.settle(_rph, dt)
	_moving_draw = _stepping or not PawnMotion.neutral(_rph)
	# FEEL: a foot lands each time the stride passes a neutral pose: told to the footstep dust (a run is harder; the dead's own go the same way in `_anim_dead`)
	var si := int(floorf(_rph / PI + 0.001))
	if _stepping and _step_ok and si > _step_i and not jumped and PawnMotion.step_cb.is_valid():
		var spd := _vel.length()
		var run: float = float(p.get_meta(RUN_META, 0.0)) if p.player else 0.0
		PawnMotion.step_cb.call(position / TILE, _vel / spd if spd > 0.05 else Vector2.ZERO, 1.0 if run > 0.3 else 0.5)
	_step_i = si
	_step_ok = _stepping
	_gait = move_toward(_gait, 1.0 if p.moving else 0.0, dt / (PawnMotion.GAIT_IN if p.moving else PawnMotion.GAIT_OUT))
	# the kick of a shot: it jumps to 1 with the rules' recoil and falls on its own clock (about 150 ms)
	var rc: float = p.recoil
	if rc > _rk + 0.3:
		_shot_age = 0.0
	_shot_age += dt
	_rk = maxf(rc, _rk - dt * 6.5)
	# the weapon carried low (a run, the holster), eased
	var run: float = float(p.get_meta(RUN_META, 0.0)) if p.player else 0.0
	var hol: bool = p.get("holstered") == true
	_lowk = move_toward(_lowk, 1.0 if (run > 0.3 or hol) else 0.0, dt / 0.09)
	_holk = move_toward(_holk, 1.0 if hol else 0.0, dt / 0.12)
	var low_ready: bool = smooth_turn and not unarmed and not p.player and p.target == null and float(p.recoil) <= 0.05 and float(p.reloading) <= 0.0
	_rdy = move_toward(_rdy, 1.0 if low_ready else 0.0, dt / 0.2)
	# the swing (the town's: the rules' `swing_t`; the old game's: the blow's own `thrust` as it begins), on the screen's clock from the moment it is seen
	var st: float = float(p.get_meta("swing_t", -1.0)) if p.player else -1.0
	var thr: float = p.thrust
	if _sw < 0.0:
		if st >= 0.0:
			_sw = st
		elif p.player and thr > _thrust_seen + 0.4 and p.weapon != "pike":
			_sw = maxf(0.0, float(PawnMotion.melee().hit) - 0.04)
	else:
		_sw += dt
		if st >= 0.0 and st + 0.06 < _sw:
			_sw = st    # (a swing begun the moment the last one ended)
		elif st < 0.0 and _sw >= float(PawnMotion.melee().cycle):
			_sw = -1.0
	_thrust_seen = thr
	if _sw >= 0.0:
		PawnMotion.swing_pose(_sw_pose, _sw, rm)
	# the reload: how far it has gone, as a pose
	if float(p.reloading) > 0.0:
		if _rl_total <= 0.0:
			_rl_total = maxf(float(p.reloading), 0.01)
			_rl_m0 = int(p.mag)
		var cap := int(p.gun.get("mag", 0))
		var shell: bool = cap > 0 and cap <= 8 and p.weapon != "pistol"
		PawnMotion.reload_pose(_rl, clampf(1.0 - float(p.reloading) / _rl_total, 0.0, 1.0), maxi(1, cap - _rl_m0) if shell else 1, shell)
	else:
		_rl_total = 0.0


## The motion of one of the dead for a frame: the drawn facing (worked out only while it turns), the attack's beat, the flinch and the thump. The dead are many, so this reads as little of the
## rules as it can.
func _anim_dead(dt: float, jumped: bool, stepped: bool) -> void:
	var z = entity
	_a_prev = anim_t
	_fl_t += dt
	_strike_age += dt
	_acc_dt += dt
	_land = maxf(0.0, _land - dt * 7.0)
	if not (stepped or jumped or _turning):
		# (a frame between two steps of the rules: what the rules say has not changed, only the clocks of the flinch and the strike run on)
		_hot = _fl_t < 0.3 or (_atk > 0.0 and _strike_age < 0.25) or _land > 0.0
		return
	var st: String = z.state
	var down: bool = st == "dying" or st == "dead"
	var f: String = z.facing
	if smooth_turn:
		# (the prison: the heading is the way it goes, turned at a fixed rate; a part of a step of change is enough to know)
		if jumped:
			_zpos = position
			_tgt_ori = PawnMotion.FACE_ANG.get(f, PI / 2.0)
			_ori = _tgt_ori
		elif stepped:
			var dp := position - _zpos
			_zpos = position
			if z.moving and dp.length() > 0.8 and dp.length() < TILE:
				_tgt_ori = dp.angle()
		_turning = _ori != _tgt_ori or jumped
	elif jumped or f != _face_seen:
		_face_seen = f
		_tgt_ori = PawnMotion.FACE_ANG.get(f, PI / 2.0)
		_turning = true
	if _turning:
		if jumped or dt <= 0.0 or down:
			_ori = _tgt_ori
		elif smooth_turn:
			_ori = PawnMotion.turn_at(_ori, _tgt_ori, dt, TURN_DEAD)
		else:
			_ori = PawnMotion.turn(_ori, _tgt_ori, dt)
		_turning = _ori != _tgt_ori
		var v := PawnMotion.view_of(_ori)
		_mir = v == "W"
		_vw = "E" if _mir else v
		_wid = 1.0 if smooth_turn else PawnMotion.width(_ori, PawnMotion.motion())
	if down:
		_hot = false
		_acc_dt = 0.0
		return
	if not (stepped or jumped):
		_hot = true    # (a turn, drawn each frame)
		return
	var sg: float = z.stagger
	if jumped:
		_at_seen = z.attack_t
		_stag_seen = sg
	# a hit that staggers it: a flinch away from the blow (combat_fx.gd tells the way; with none told it is back from where it looks)
	if sg > _stag_seen + 0.1 and _fl_t - dt > 0.12:
		_fl_t = 0.0
		_fl_dir = -(PawnMotion.FACE_DIR.get(f, Vector2(0.0, 1.0)) as Vector2)
	_stag_seen = sg
	var fighting: bool = st == "attack" or st == "chase" or st == "hunt" or st == "breach"
	if fighting or _atk > 0.0:
		# a strike is the rules' `attack_t` being set back after a claw or a bite: the figure rears back as it runs down and lunges when it is reset
		var at: float = z.attack_t
		if at > _at_seen + 0.25:
			_strike_age = 0.0
			if kind == "brute":
				_thump = 1.0
		_at_seen = at
		_atk = move_toward(_atk, 1.0 if (st == "attack" or (fighting and not z.moving)) else 0.0, _acc_dt / 0.1)
	# FEEL: the legs' phase as this one draws it (its own gait and its own start in the cycle: no two in step), and a foot landing as it passes a neutral pose: dust under it, and a
	# brute's weight: the body sinks as the foot lands (and the camera is shaken a hair, as before)
	_vphase = float(z.walk_phase) * _dv.gait + _dv.ph
	if z.moving:
		var si := int(floorf(_vphase / PI))
		if si != _step_i:
			if not jumped:
				if kind == "brute":
					_thump = maxf(_thump, 0.3)
					_land = 1.0
				if PawnMotion.step_cb.is_valid() and (kind != "walker" or PawnMotion.rnd(_seed_i, si) < 0.6):
					PawnMotion.step_cb.call(position / TILE, PawnMotion.FACE_DIR.get(f, Vector2.DOWN), 0.42 if kind == "walker" else (0.85 if kind == "runner" else 1.4))
			_step_i = si
	if kind == "brute" and _thump > 0.0:
		if PawnMotion.thump_cb.is_valid():
			PawnMotion.thump_cb.call(position / TILE, _thump)
		_thump = 0.0
	_acc_dt = 0.0
	_hot = _turning or _fl_t < 0.3 or (_atk > 0.0 and _strike_age < 0.25) or _land > 0.0


# a tiny canvas-context emulation: translate / rotate / scale in local units
func _reset() -> void:
	_m = Transform2D.IDENTITY.scaled(Vector2(TILE, TILE))


func _tr(x: float, y: float) -> void:
	_m = _m.translated_local(Vector2(x, y))


func _rot(a: float) -> void:
	_m = _m.rotated_local(a)


func _sc(x: float, y: float) -> void:
	_m = _m.scaled_local(Vector2(x, y))


func _apply() -> void:
	_pen.draw_set_transform_matrix(_m)


## Scales the figure about its feet (what is drawn after grows from the ground up).
func _fit_figure(fs: Vector2) -> void:
	_tr(0, Art.FOOT_Y)
	_sc(fs.x, fs.y)
	_tr(0, -Art.FOOT_Y)


## How the body leans into its stride: from the hips toward where it faces in side
## view (a shear, so the hem stays level and the head goes forward), and shorter on
## its feet facing the player (it comes toward them).
func _lean(view: String) -> void:
	var lean: float = _style.lean
	if lean == 0.0:
		return
	if view == "E":
		var k := tan(lean)
		_m = _m * Transform2D(Vector2(1.0, 0.0), Vector2(-k, 1.0), Vector2(k * 0.12, 0.0))
		return
	var dip: float = _style.dip_s if view == "S" else _style.dip_n
	if dip != 1.0:
		_tr(0, Art.FOOT_Y)
		_sc(1.0, dip)
		_tr(0, -Art.FOOT_Y)


## The baked body for one view: the sprite, or for a figure with a hunch (a brute)
## the sprite warped by its build. `col` fades it (a corpse going).
func _draw_body(view: String, col: Color = Color.WHITE) -> void:
	if not _meshes.has(view):
		_meshes[view] = Art.sprite_mesh(kind, view, pawn_rect)
	var mesh = _meshes[view]
	if mesh != null:
		_pen.draw_mesh(mesh, tex[view], Transform2D.IDENTITY, col)
	else:
		_pen.draw_texture_rect(tex[view], pawn_rect, false, col)


## How big this character is drawn, across and up: 1 for a person and a walker, the
## rules' size times the kind's build for the other dead.
func figure_scale_xy() -> Vector2:
	if not zombie or entity == null:
		return Vector2.ONE
	return Art.figure_scale(kind, Art.size_of(entity))


## How tall the figure is drawn against a walker (1 for a person or a walker): what
## something placed above the head, a label or a bar, multiplies its offset by.
func figure_scale() -> float:
	if not zombie or entity == null:
		return 1.0
	return Art.height_ratio(kind, Art.size_of(entity))


## The box that is the figure, in tiles from where it stands: what a click is
## tested against and a selection ring is drawn around. A person's and a walker's
## are the same (0.42 either side, 0.95 up, 0.42 down).
func hit_box() -> Rect2:
	if not zombie or entity == null:
		return Art.hit_box("walker", 1.0)
	return Art.hit_box(kind, Art.size_of(entity))


func _draw() -> void:
	if entity == null:
		return
	_draws += 1
	var t0 := Time.get_ticks_usec()
	_fast = cached and (_pen == self or meshes_on_tape)
	if zombie:
		if entity.state == "dying" or entity.state == "dead":
			_draw_dead()
		else:
			_draw_zombie()
	elif entity.turned:
		return # the walker standing there now is drawn instead
	elif entity.resting_bed != null:
		_draw_resting()
	elif entity.downed:
		_draw_downed()
	else:
		_draw_person()
	_draw_us += Time.get_ticks_usec() - t0


## The microseconds all nodes have spent in their `_draw` so far (a measurement's: a frame's share is the difference between two looks).
static var _draw_us := 0


static func draw_usec() -> int:
	return _draw_us


func _view() -> String:
	return "E" if entity.facing == "W" else entity.facing


## The legs (and, drawn with them, the shadow when `shadow`) of this figure in the stride at `phase`: the mesh nearest that pose,
## or, for a stand-in that wants the commands, the commands themselves (whose shadow is drawn by the caller, before the mirror).
func _legs(view: String, phase: float, moving: bool, limp: bool, alpha: float, shadow: bool) -> void:
	if _fast:
		_pen.draw_mesh(PawnMesh.legs(_leg_kind, view, phase, moving, limp, shadow), _pal_tex, Transform2D.IDENTITY, Color(1.0, 1.0, 1.0, alpha))
	else:
		Art.legs(_pen, pal, view, phase, moving, limp, alpha, _style)


## One layer of a walker's arms (see Art.arms), as a baked mesh or as commands.
func _arms(view: String, t: float, attacking: bool, layer: String, phase: float) -> void:
	if _fast:
		var mesh := PawnMesh.arms(kind, view, layer, t, attacking, phase)
		if mesh != null:
			_pen.draw_mesh(mesh, _pal_tex)
	else:
		Art.arms(_pen, pal, view, t, attacking, layer, _style, phase)


## Where a weapon that is put away points (radians in the figure's own frame: down and a little forward), and the strength it is drawn at.
const LOW_AIM := 1.25
## The lean of a run (radians at full run), how much shorter she is drawn facing the screen or away, and the person's meta that carries the eased run (scripts/sim/sprint.gd `META`).
const RUN_LEAN := 0.11
const RUN_DIP := 0.03
const RUN_META := "sprint_lean"


func _draw_person() -> void:
	var p = entity
	if _work_update(p):
		_draw_working()
		return
	var rm := PawnMotion.motion()
	var view := _vw
	var mirror := _mir
	var g := _gait
	# (PACE: the run, scripts/sim/sprint.gd `lean`, 0 to 1 and set on the avatar only: the legs go faster by themselves (the stride is longer for each tile), the body bobs a little more, leans into it and the gun is carried low)
	var run: float = float(p.get_meta(RUN_META, 0.0)) if p.player else 0.0
	# ANIM. The body: a bounce at each step, a sway with the stride, a lean into the way it is going (the drawn speed), a breath and a slow shift of weight when it stands.
	var breath := 0.5 + 0.5 * sin(anim_t * 2.5 + _seed * TAU)
	var stepk := absf(sin(_rph))
	var off := Vector2((sin(_rph) * 0.014 * g + sin(anim_t * 0.7 + _seed * 9.0) * 0.006 * (1.0 - g)) * rm, -(stepk * 0.06 * (1.0 + 0.5 * run) * g + breath * 0.02 * (1.0 - g)) * rm)
	var roll := sin(_rph) * 0.04 * g * rm
	var sy := 1.0 - (1.0 - stepk) * 0.035 * g * rm    # (a little squashed as a foot lands, stretched in mid-stride)
	if _alert > 0.0:
		sy += 0.035 * _alert * rm    # (FEEL: a shot near them: the body starts up as the head comes round)
		off.y -= 0.02 * _alert * rm
	var lean := Vector2.ZERO
	var spd := _vel.length()
	if spd > 0.05:
		lean = (_vel / spd) * ((0.045 + 0.08 * run) * minf(spd / PawnMotion.WALK_V, 1.6) * rm)
	var aim: float = p.aim
	if smooth_turn and _rdy > 0.0 and not p.player:
		aim = lerp_angle(aim, _ori, _rdy)    # (a rifle that is not aimed points where the figure goes, at the low ready)
	var aim_v := Vector2.from_angle(aim)
	var kick := _rk * _rk
	if kick > 0.0:
		# (the kick of a shot: the body is pushed back from the way the gun points and settles over about 150 ms)
		off -= Vector2(aim_v.x, aim_v.y * 0.6) * (kick * float(Combat.GUNS.get(p.weapon, Combat.GUNS.rifle).nudge) * 1.5 * rm)
	if _sw >= 0.0:
		# (the swing: the body coils back, lunges along the blow and comes back, with the weapon: pawn_motion.gd)
		off += aim_v * _sw_pose.step
		lean += Vector2(aim_v.x, aim_v.y * 0.7) * (_sw_pose.lean * 0.3)
		roll += _sw_pose.roll
		sy += _sw_pose.stretch
	var xf := Transform2D(0.0, Vector2.ONE, 0.0, off) * PawnMotion.lean_xf(lean)
	if roll != 0.0 or sy != 1.0:
		xf = xf.translated_local(Vector2(0.0, PawnMotion.HIPS)).rotated_local(roll).scaled_local(Vector2(1.0, sy)).translated_local(Vector2(0.0, -PawnMotion.HIPS))
	_reset()
	var base := _m
	_apply()
	if not _fast:
		Art.shadow(_pen)
	if mirror:
		_sc(-1, 1)
	_apply()
	_legs(view, _rph, _moving_draw, false, 1.0, true)
	var sm: Array = PawnMotion.seam(_ori) if smooth_turn else ["", 0.0]
	var nv := String(sm[0])
	var nmir := nv == "W"
	if nv != "":
		nv = "E" if nmir else nv
		_m = base
		if nmir:
			_sc(-1, 1)
		_apply()
		_legs(nv, _rph, _moving_draw, false, float(sm[1]), false)
	var body := base * xf
	if view == "N" and not unarmed:
		_gun(body, aim, view)
	_m = body
	if _wid != 1.0:
		_m = _m * Transform2D(Vector2(_wid, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)    # (a turn: narrower across the seam between two views)
	if mirror:
		_sc(-1, 1)
	_apply()
	_pen.draw_texture_rect(tex[view], pawn_rect, false)
	if nv != "":
		_m = body
		if nmir:
			_sc(-1, 1)
		_apply()
		_pen.draw_texture_rect(tex[nv], pawn_rect, false, Color(1.0, 1.0, 1.0, float(sm[1])))
	if view != "N" and not unarmed:
		_gun(body, aim, view)
	if p.thrust > 0.0:
		_m = body
		_swing(view, aim)


## Where a weapon that is carried low points (radians, screen space: down and forward of a side view, down across the body from the front or the back).
const CARRY_E := 0.95
const CARRY_SN := 1.35


## The weapon in the hands, drawn in the frame `m` (the body's, without the turn's narrowing): at the aim, kicked up by a shot, swung through its arc, lowered for a reload or a run (the carry,
## eased), or put away (low, the hands off it, a little faded; round 23, Q).
func _gun(m: Transform2D, aim: float, view: String) -> void:
	if unarmed:
		return
	var p = entity
	var rm := PawnMotion.motion()
	var a := aim
	var reload := float(p.reloading) > 0.0
	var kick := _rk * _rk
	if kick > 0.0:
		a -= signf(cos(aim)) * kick * float(Combat.GUNS.get(p.weapon, Combat.GUNS.rifle).nudge) * 2.4 * rm
	if _sw >= 0.0:
		a += _sw_pose.off
	var lw := maxf(_lowk, _rdy * READY_LOW)
	if reload:
		lw = maxf(lw, _rl.low * 0.85)
	if lw > 0.0:
		var carry := CARRY_SN
		if view == "E":
			carry = (PI - CARRY_E) if _mir else CARRY_E
		a += angle_difference(a, carry) * lw
		a += sin(_rph) * 0.06 * _lowk * _gait * rm
	var pv := PawnMotion.shoulder(_ori)
	var pump := 0.0
	if reload:
		pump = _rl.pump
	elif p.weapon == "shotgun" and _shot_age > 0.3 and _shot_age < 0.55:
		pump = sin((_shot_age - 0.3) / 0.25 * PI) * rm
	_m = m
	_tr(pv.x, pv.y)
	_rot(a)
	if cos(a) < 0.0:
		_sc(1, -1)
	var push: float = sin(p.thrust * PI) * 0.6 if p.weapon == "pike" else -kick * 0.10 * rm
	_tr(push, 0)
	_apply()
	_pen.draw_texture_rect(weapon_tex, weapon_rect, false, Color(1.0, 1.0, 1.0, lerpf(0.94, 0.75, _holk)))
	if _holk < 0.5:
		if pump == 0.0 and not reload:
			_hands_on(null)
		else:
			_hands_on(Vector2(0.0, 0.05), true)
			if gun_front != null:
				_hands_on(Vector2(float(gun_front) - pump * 0.12, 0.02), true)
			if reload and _rl.hand_on:
				_hands_on(_rl.hand, true)
	_m = m
	_apply()


## The hands on a weapon: both (the baked pair), or with `at` one hand there in the weapon's frame.
func _hands_on(at, single: bool = false) -> void:
	if not single:
		if _fast:
			_pen.draw_mesh(PawnMesh.hands(gun_front), _pal_tex)
		else:
			Art.hands(_pen, gun_front, pal.skin)
		return
	var saved := _m
	_tr(at.x, at.y - 0.05)
	_apply()
	if _fast:
		_pen.draw_mesh(PawnMesh.hands(null), _pal_tex)
	else:
		Art.hands(_pen, null, pal.skin)
	_m = saved
	_apply()


## A blow in the air (round 17: the avatar's F, and the pike's thrust and the butt of a gun for everyone): a pale crescent that
## sweeps across the way the weapon points while `thrust` runs out (1 at the start of the blow, 0 at the end), the whole arc for
## a swing and a narrow one for the pike's thrust, fading as it goes. The weapon in the hand does what it did.
func _swing(view: String, aim: float) -> void:
	var p = entity
	var done: float = clampf(1.0 - p.thrust, 0.0, 1.0)
	var half := deg_to_rad(18.0 if p.weapon == "pike" else 50.0)
	var lead := lerpf(-half, half, done)
	var tail := maxf(-half, lead - 1.2)
	var saved := _m
	var pv := PawnMotion.shoulder(_ori)
	_tr(pv.x, pv.y)
	_apply()
	var steps := 8
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		pts.append(Vector2.from_angle(aim + lerpf(tail, lead, float(i) / steps)) * 1.15)
	for i in range(steps, -1, -1):
		pts.append(Vector2.from_angle(aim + lerpf(tail, lead, float(i) / steps)) * 0.6)
	_pen.draw_colored_polygon(pts, Color(1.0, 0.97, 0.88, 0.2 + 0.4 * p.thrust))
	var edge := PackedVector2Array()
	for i in range(steps + 1):
		edge.append(Vector2.from_angle(aim + lerpf(tail, lead, float(i) / steps)) * 1.15)
	_pen.draw_polyline(edge, Color(1.0, 0.98, 0.9, 0.35 + 0.5 * p.thrust), 0.03, true)
	_m = saved
	_apply()


## What the person is doing, for the pose: the word staged for a screenshot, else the rules' own (`Person.work`).
func _work_word() -> String:
	if work_stage != "":
		return work_stage
	return String(entity.work) if work_poses else ""


## The work time to draw, in seconds: the rules' clock shown between their last two steps (a staged job's own).
func work_time() -> float:
	if work_stage != "":
		return work_stage_t if work_stage_t >= 0.0 else anim_t
	return lerpf(_wt_prev, _wt_cur, _w_alpha)


## Follows the rules' work clock the way the position follows their steps: from where it stood a step ago to where it stands now.
func _work_sync(steps: int, alpha: float) -> void:
	var wt: float = entity.work_t
	var word := _work_word()
	if steps < 0:
		_wt_prev = wt
		_wt_cur = wt
		_w_alpha = 1.0
	elif steps != _w_steps:
		_wt_prev = _wt_cur if (word == _w_last and wt >= _wt_cur) else wt
		_wt_cur = wt
		_w_alpha = alpha
	else:
		if word != _w_last or wt < _wt_cur:
			_wt_prev = wt
			_wt_cur = wt
		_w_alpha = alpha
	_w_steps = steps
	_w_last = word


## Whether the person is to be drawn at their work, and how far into the pose they are (`_wk`, eased with the screen's clock). Someone
## walking, or in the sights of a weapon, or with a gun going off, is not at work, whatever word the rules have left on them.
func _work_update(p) -> bool:
	var word := _work_word()
	var busy: bool = word != "" and WorkAnim.CYCLE.has(word) and not (rifles_ready and word == "watch" and not unarmed) and not p.moving and p.target == null and p.reloading <= 0.0 and p.recoil <= 0.0
	var dt := 0.0
	if _anim_prev >= 0.0:
		dt = clampf(anim_t - _anim_prev, 0.0, 0.1)
	_anim_prev = anim_t
	if busy:
		if word != _w_word:
			_strike_seen = NO_STRIKE
			if _wk > 0.0:
				_wk = 0.0    # (one job to another with no pause: the pose starts again)
		_w_word = word
	_wk = WorkAnim.weight(_wk, busy, dt)
	return _wk > 0.0 and _w_word != ""


func _draw_working() -> void:
	var p = entity
	var o := WorkAnim.solve(_wpose, _w_word, work_time(), _work_phase, WorkAnim.reduced())
	if on_work_strike.is_valid() and _wk >= 1.0 and o.fx != "" and not WorkAnim.reduced():
		if _strike_seen != NO_STRIKE and o.strike == _strike_seen + 1:
			on_work_strike.call(_w_word, p.x, p.y)
		_strike_seen = o.strike
	WorkAnim.draw_person(self, o, WorkAnim.eased(_wk), "W" if _mir else _vw, p.aim)


## The weapon drawn at the strength `fade` (1 in hand, less as it is put away for work); `aim` is the rules' angle.
func _weapon_faded(view: String, aim: float, fade: float, mirror: bool) -> void:
	if fade <= 0.02 or unarmed:
		return
	var a: float = PI - aim if mirror else aim
	var saved := _m
	var pv: Vector2 = PIVOT[view]
	_tr(pv.x, pv.y)
	_rot(a)
	if cos(a) < 0.0:
		_sc(1, -1)
	_apply()
	_pen.draw_texture_rect(weapon_tex, weapon_rect, false, Color(1.0, 1.0, 1.0, fade))
	_m = saved
	_apply()


func _draw_zombie() -> void:
	var z = entity
	var st := _style
	var view := _vw
	var mirror := _mir
	var rm := PawnMotion.motion()
	var thump: float = st.claw_thump
	var dv := _dv
	var phase: float = _vphase
	var walking: bool = z.moving
	# ANIM. Each of the dead has its own gait: how much it rocks and bounces; one that limps drags a leg (it bobs on one step only); standing it rocks a little and breathes.
	# FEEL: and its own (pawn_motion.gd `dead_variant`, from its seed): how fast its limbs cycle and where in the cycle it is (`_vphase`), how much it bobs and sways, which leg it drags
	# (the rules' limp, or a limp of its own for about one in five), a lean and a tilt of the head, how it carries its arms, a few percent of size and of dirt.
	var limp: bool = z.limp or dv.gimp
	var stride := sin(phase)
	var bob := 0.0
	var roll: float = sin(z.t * 1.7 * dv.gait + dv.breath) * 0.06 * dv.sway
	if walking:
		bob = (maxf(0.0, stride) * 0.06 if limp else absf(stride) * 0.035) * float(st.bob) * dv.bob
		roll += stride * 0.075 * dv.sway * (0.5 if view == "E" else 1.0)
	else:
		bob = (0.5 + 0.5 * sin(anim_t * 2.2 + dv.breath)) * 0.008
	bob *= rm
	roll *= rm
	# the attack follows the rules' own beat (`attack_t`, set back at each claw or bite): rear back as it runs down, lunge when it is reset, settle (the heavier kinds rear longer and hit harder)
	var windup := 0.0
	var hump := 0.0
	if _atk > 0.0:
		var rear := 0.5 if kind == "brute" else 0.3
		if _strike_age < 0.25:
			hump = sin(pow(clampf(_strike_age / 0.22, 0.0, 1.0), 0.6) * PI) * _atk
		elif _at_seen < rear:
			windup = PawnMotion.smooth(1.0 - _at_seen / rear) * _atk
	var lf := (0.04 if walking else 0.0) * rm - 0.28 * windup + 0.42 * hump * minf(thump, 1.4) + dv.lean
	var lean := Vector2(lf + dv.tilt * 0.4, 0.0)
	if view == "S":
		lean = Vector2(dv.tilt, lf * 0.8)
	elif view == "N":
		lean = Vector2(dv.tilt, -lf * 0.5)
	var sy := 1.0 - 0.06 * hump * minf(thump, 1.4) - 0.035 * _land * dv.weight * rm
	bob -= 0.012 * _land * dv.weight * rm
	if _fl_t < 0.3:
		# a flinch: it jerks away from the blow and comes back (a couple of frames)
		var fk := exp(-_fl_t * 14.0) * rm
		lean += Vector2(-_fl_dir.x if mirror else _fl_dir.x, _fl_dir.y * 0.5) * (0.34 * fk)
		sy -= 0.06 * fk
		bob -= 0.02 * fk
	_reset()
	var fs := figure_scale_xy() * dv.size
	if fs != Vector2.ONE:
		_fit_figure(fs)
	_apply()
	if not _fast:
		Art.shadow(_pen, st)
	if mirror:
		_sc(-1, 1)
	_apply()
	if dv.side < 0.0 and limp and view != "E":
		# (FEEL: which leg drags: from the front and the back the legs are a pair, so the other leg is the same mesh turned over; in side view the near one drags, as the rules' limp has it)
		var kept := _m
		_sc(-1, 1)
		_apply()
		_legs(view, phase, walking, limp, 1.0, true)
		_m = kept
		_apply()
	else:
		_legs(view, phase, walking, limp, 1.0, true)
	_tr(0, 0.3)
	_rot(roll)
	_tr(0, -0.3 - bob)
	_lean(view)
	_m = _m * PawnMotion.lean_xf(lean)
	if sy != 1.0:
		_tr(0, Art.FOOT_Y)
		_sc(1.0, sy)
		_tr(0, -Art.FOOT_Y)
	var step := hump * 0.10 * minf(thump, 1.4) * rm
	if view == "E":
		_tr(step, 0)
	else:
		_tr(0, step * 0.5 if view == "S" else -step * 0.5)
	if _wid != 1.0:
		_sc(_wid, 1.0)
	_apply()
	var reach: bool = _atk > 0.5 and st.pose == "sprint"
	_arms_layer(view, "back", reach, phase, windup, hump, walking)
	_draw_body(view)
	if smooth_turn:
		var sm: Array = PawnMotion.seam(_ori)
		if String(sm[0]) != "":
			var nmir: bool = sm[0] == "W"
			if nmir != mirror:
				_sc(-1, 1)
				_apply()
			_draw_body("E" if nmir else String(sm[0]), Color(1.0, 1.0, 1.0, float(sm[1])))
			if nmir != mirror:
				_sc(-1, 1)
				_apply()
	_arms_layer(view, "front", reach, phase, windup, hump, walking)


## One layer of the arms of one of the dead, raised as it rears back and slammed down as it strikes (the pose of the arms is moved about the shoulders, the picture of them is the one at rest),
## and lagging a little behind the body's bounce as it walks.
func _arms_layer(view: String, layer: String, reach: bool, phase: float, windup: float, hump: float, walking: bool) -> void:
	var raise := windup - 0.8 * hump + _dv.arm    # (FEEL: how this one carries its arms: lower or higher than the rest)
	if raise == 0.0:
		_arms(view, 0.0, reach, layer, phase)
		return
	var saved := _m
	if view == "E":
		_tr(0, -0.2)
		_rot(-raise * 0.9)
		_tr(0, 0.2)
	elif view == "S":
		# (from the front the hands go up past the shoulders and come down in front of the belly: the arms are lifted and a little folded, never turned through flat)
		_tr(0, -0.26 * raise)
		_tr(0, -0.2)
		_sc(1.0, 1.0 - 0.3 * raise)
		_tr(0, 0.2)
	else:
		_tr(0, -0.2)
		_sc(1.0, 1.0 + 0.6 * raise)
		_tr(0, 0.2)
	_apply()
	_arms(view, 0.0, reach, layer, phase)
	_m = saved
	_apply()


func _draw_dead() -> void:
	var z = entity
	var view := _vw
	var rm := PawnMotion.motion()
	# ANIM. The rules' fall runs 0.45 s; the collapse is drawn in the first 0.26 s of it: the knees buckle (a rock back and a drop), it topples with the weight of a body (slow, then fast) and
	# lands with a small bounce; the shadow stays where it stood and fades as the body goes over it.
	var f: float = clampf(float(z.fall) / 0.58, 0.0, 1.0)
	var rot := 0.0
	var sy := 1.0
	if f < 0.25:
		var b := PawnMotion.smooth(f / 0.25)
		rot = -0.10 * b * rm
		sy = 1.0 - 0.10 * b * rm
	elif f < 0.85:
		var u := (f - 0.25) / 0.6
		rot = lerpf(-0.10 * rm, PI / 2.0, u * u)
		sy = lerpf(1.0 - 0.10 * rm, 1.0, u)
	else:
		rot = PI / 2.0 * (1.0 + 0.05 * sin((f - 0.85) / 0.15 * PI) * rm)
	var alpha := 1.0
	if z.state == "dead" and z.dead_t > 55.0:
		alpha = maxf(0.0, 1.0 - (z.dead_t - 55.0) / 15.0)
	_reset()
	var fs := figure_scale_xy() * _dv.size
	if z.state == "dying" and _fast and f < 1.0:
		if fs != Vector2.ONE:
			_fit_figure(fs)
		_apply()
		_pen.draw_mesh(PawnMesh.shadow(kind), _pal_tex, Transform2D.IDENTITY, Color(1.0, 1.0, 1.0, (1.0 - f) * alpha))
		_reset()
	_tr(0, 0.3)
	_rot(z.fall_dir * rot)
	if _mir:
		_sc(-1, 1)
	if fs != Vector2.ONE:
		_sc(fs.x, fs.y)
	if sy != 1.0:
		_sc(1.0, sy)
	_tr(0, -0.3)
	_apply()
	_legs(view, 0.0, false, false, alpha, false)
	_draw_body(view, Color(1, 1, 1, alpha))


func _draw_downed() -> void:
	var p = entity
	_wk = 0.0
	_reset()
	_tr(0, 0.3)
	_rot(PI / 2.0)
	_tr(0, -0.3)
	_apply()
	_legs("S", 0.0, false, false, 1.0, false)
	_pen.draw_texture_rect(tex["S"], pawn_rect, false)


## In bed: the head and shoulders on the pillow and the bed's own blanket over
## the rest (the body is drawn upright, so it lies along the bed, not across it).
func _draw_resting() -> void:
	var blanket := _blanket_color()
	_wk = 0.0
	_reset()
	_tr(0, -0.16) # the head lands on the pillow
	_apply()
	_pen.draw_texture_rect(tex["S"], pawn_rect, false)
	_reset()
	_apply()
	var hump := S.rrect(-0.34, -0.3, 0.68, 1.22, 0.2, 4)
	_pen.draw_colored_polygon(hump, blanket.lightened(0.05))
	_pen.draw_polyline(S.closed(hump), Color(S.INK.r, S.INK.g, S.INK.b, 0.5), S.LW, true)
	_pen.draw_line(Vector2(-0.29, -0.27), Vector2(0.29, -0.27), blanket.lightened(0.28), 0.06, true)


## The colour of the blanket of the bed they lie in, read from the bed's art.
func _blanket_color() -> Color:
	var bed: Vector2 = entity.resting_bed
	var key := "%.2f,%.2f" % [bed.x, bed.y]
	if key == _bed_key:
		return _bed_col
	_bed_key = key
	for o in beds:
		if absf(float(o.cx) - bed.x) < 0.05 and absf(float(o.cy) - bed.y) < 0.05 and not o.pieces.is_empty():
			var img: Image = GD.tex(o.pieces[0].file).get_image()
			if img != null:
				_bed_col = img.get_pixel(int(img.get_width() * 0.5), int(img.get_height() * 0.6))
			break
	return _bed_col
