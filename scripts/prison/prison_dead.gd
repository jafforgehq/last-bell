## EXPERIMENT (prison zombie motion, round 8): HOW THE DEAD MOVE. Owned by prison_game.gd (`zmove`), stepped around every `sim.update` (`pre`, `post`), and the only code that gives the
## dead of the prison a heading, a gait that follows the distance travelled, a pause, a rise from the ground and a lean on the fence. The rules (sim.gd, town_sim.gd, dormant_dead.gd) are untouched
## but for six plain fields on `Zombie` that nothing else reads; the One House and the classic game never call this, so their tests and goldens are what they were.
##
## PATTERN. The skills' options: NavigationAgent2D (rejected: the game has its own grid path finder and a baked polygon per agent costs far more than 105 walkers can spare, and its avoidance
## would fight the rules' own crowd pass), a behaviour tree or state machine per zombie (rejected: the rules already are the states; this only reads them), an AnimationTree (rejected: the dead
## are code-drawn, there is no AnimationPlayer). PICKED: steering as a thin layer over the rules: after each rules step the heading is turned at a limited rate toward where the rules wanted
## to go, the step is cut by how far off that heading still is (it turns before it walks), cut again by the rhythm of its stride (a lurch, not a glide), and the phase of the legs is moved
## by exactly the share of the step that was kept (no sliding). The drawing (pawn_node.gd, `PawnNode.zmove`) reads the heading, the phase, the rise and the lean; it is code-driven
## animation with state flags, the pattern of rounds 5 and 6.
extends RefCounted

const PM := preload("res://scripts/render/pawn_motion.gd")

## The turn rate in radians a second: a shambler is slow, a runner quick, a brute heavy (each one has its own share of it, 0.8 to 1.25).
const TURN := {"walker": 1.9, "runner": 6.0, "brute": 1.2}
## The share of the step's turn that must be done before it walks: [off by this much it walks fully, off by this much it does not walk (or walks at the floor)], and the floor.
const HOLD := {"walker": [0.5, 1.3, 0.0], "runner": [1.0, 2.2, 0.25], "brute": [0.35, 1.0, 0.0]}
const REACH := 34.0    # tiles a groan carries
const VOICES := 4
const NEAR_VOICES := 3    # (FEEL: only the nearest this many awake dead are heard groaning, placed in the world: louder, panned by where they stand)
const GROAN_FILES := {"walker": ["zgroan", 8], "far": ["zgroan_far", 3], "runner": ["zgrowl", 4], "brute": ["zbrute_growl", 2]}
const CELL_KEY := 1024

var game
var sim
var enabled := true
var on := true    # (--nozmove with --zombietest: the module is there for the check, the rules layer is off)
var stats := {"pauses": 0, "rises": 0, "held": 0}
var _prey := {}
var _rng := RandomNumberGenerator.new()
var _grid := {}
var _n := 0
var usec := 0    # microseconds spent in `pre` and `post` so far (--perf prints the share of a step)
var steps := 0
var _t0 := 0
var _players: Array = []
var _streams := {}


func setup(g) -> void:
	game = g
	_rng.seed = 8808
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		game.add_child(p)
		_players.append(p)
	_streams = {"walker": _load("zgroan", 8), "far": _load("zgroan_far", 3), "runner": _load("zgrowl", 4), "brute": _load("zbrute_growl", 2)}


func _load(prefix: String, n: int) -> Array:
	var out: Array = []
	for i in n:
		var path := "res://assets/audio/%s_%d.wav" % [prefix, i]
		if ResourceLoader.exists(path):
			out.append(load(path))
	return out


# ------------------------------------------------------------------ the step --

## Before the rules' step: where each awake one stands now.
func pre() -> void:
	if not on:
		return
	_t0 = Time.get_ticks_usec()
	sim = game.run.sim
	_prey.clear()
	for p in sim.people:
		_prey[String(p.id)] = p
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		z.ox = z.x
		z.oy = z.y
		z.oph = z.walk_phase
		if not z.head_ok:
			_first(z)
	usec += Time.get_ticks_usec() - _t0


func _first(z) -> void:
	z.head_ok = true
	var h := _rng.randf()
	z.zph = h * TAU
	z.head = _rng.randf() * TAU - PI
	z.idle = z.head
	if z.state != "still" and z.state != "wander":
		z.head = PM.FACE_ANG.get(String(z.facing), z.head)
	if (game.clock > 4.0 or String(game.args.get("zombietest", "")) == "wake") and sim.field != null and sim.field.rec_of.has(z):
		z.rise = 0.0    # (it was asleep until a moment ago: it gets up)
		stats.rises += 1


## After the rules' step: heading, hold, lurch, pause, rise, lean on the fence, spread.
func post(dt: float) -> void:
	if not on:
		return
	sim = game.run.sim
	_t0 = Time.get_ticks_usec()
	_n += 1
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		_one(z, dt)
	if _n % 2 == 0:
		_spread()
	usec += Time.get_ticks_usec() - _t0
	steps += 1


func _one(z, dt: float) -> void:
	if not z.head_ok:
		return    # woken inside this very step: `pre` has not seen it yet, its `ox`/`oy` are 0 and the pull-back below would drag it to the map's corner, into walls
	var kind: String = z.kind
	var hsh := fposmod(z.zph / TAU * 7.31, 1.0)
	if sim.world.is_solid(sim.world.solid_z, z.x, z.y):
		_unstick(z)
	if z.pst != z.state:
		if z.pst == "still" and z.rise >= 1.0 and z.state != "still" and z.state != "attack":
			z.pause = maxf(z.pause, 0.2 + 0.4 * hsh)    # (it notices: the head comes round first)
		z.pst = z.state
	if z.press > 0.0:
		if z.state != "still":
			z.press = 0.0
		else:
			z.attack_t -= dt    # (it claws at the wire on the beat of a strike: the drawing reads `attack_t`)
			if z.attack_t <= 0.0:
				z.attack_t = 0.9 + 0.7 * hsh + _rng.randf() * 0.3
	if z.rise < 1.0:
		z.rise = minf(1.0, z.rise + dt / (1.1 + 0.9 * hsh))
	z.zcool -= dt
	var dx: float = z.x - z.ox
	var dy: float = z.y - z.oy
	var moved := dx * dx + dy * dy > 1e-8
	var has := _intent(z)
	if moved and not has:
		z.want = atan2(dy, dx)
		has = true
	var rate: float = float(TURN.get(kind, 1.9)) * (0.8 + 0.45 * hsh)
	if z.rise < 1.0:
		rate *= 0.3
	if has:
		z.head = PM.turn_at(z.head, z.want, dt, rate)
		if z.press <= 0.0:
			z.idle = z.head
	else:
		# standing about: it looks slowly this way and that
		z.head = PM.turn_at(z.head, z.idle + 0.8 * sin(z.t * 0.4 + z.zph), dt, rate * 0.3)
	if z.pause > 0.0:
		z.pause -= dt
	elif moved and z.state == "wander" and z.wander_t < 20.0 and z.zcool <= 0.0 and _rng.randf() < dt / 6.0:
		z.pause = 1.0 + _rng.randf() * 2.2    # (it stops, sniffs, looks about)
		z.zcool = 5.0 + _rng.randf() * 6.0
		stats.pauses += 1
	if not moved:
		return
	var k := 1.0
	if z.rise < 1.0 or z.pause > 0.0:
		k = 0.0
	else:
		var h: Array = HOLD.get(kind, HOLD.walker)
		var diff := absf(wrapf(z.want - z.head, -PI, PI))
		k = clampf(1.0 - (diff - float(h[0])) / (float(h[1]) - float(h[0])), float(h[2]), 1.0)
		k *= _lurch(z, kind)
	if k < 0.999:
		var nx: float = z.ox + dx * k
		var ny: float = z.oy + dy * k
		if sim.world.is_solid(sim.world.solid_z, nx, ny):
			return    # (never integrate a position into a blocked tile: keep the rules' step)
		z.x = nx
		z.y = ny
		z.walk_phase = z.oph + (z.walk_phase - z.oph) * k
		if k < 0.08:
			z.moving = false
			stats.held += 1


## A dead one found on a blocked tile goes to the centre of the nearest free tile (rings of growing radius).
func _unstick(z) -> void:
	var tx := floori(z.x)
	var ty := floori(z.y)
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cx := float(tx + dx) + 0.5
				var cy := float(ty + dy) + 0.5
				if not sim.world.is_solid(sim.world.solid_z, cx, cy):
					z.x = cx
					z.y = cy
					z.path.clear()
					z.path_i = 0
					stats.unstuck = int(stats.get("unstuck", 0)) + 1
					return


## How much of a step it keeps by where its stride is (it can be above 1 mid swing: the phase of the legs moves with the distance, so the time spent in the slow part is longer and the averages
## below come to about 1 for a walker and a runner, 0.87 for a brute, 0.8 for one that limps): the fast part of a step is mid swing, the slow part is the foot landing.
func _lurch(z, kind: String) -> float:
	var v: float = z.walk_phase * PM.dead_stride(kind) + z.zph
	var a := absf(sin(v))
	var alt := 0.5 + 0.5 * sin(v * 0.5)
	match kind:
		"runner":
			return (0.78 + 0.4 * a) * (0.92 + 0.08 * alt)
		"brute":
			return 0.5 + a * a
		_:
			return (0.55 + 0.7 * pow(a, 0.8)) * ((0.7 + 0.3 * alt) if z.limp else (0.94 + 0.06 * alt))


## Where the rules want it to face: the fence it leans on, its slot at the wall, the prey it is at, the next point of its path. False when it has no wish.
func _intent(z) -> bool:
	if z.press > 0.0:
		z.want = z.aim
		return true
	var st: String = z.state
	if st == "attack" and z.slot != null:
		z.want = float(PM.FACE_ANG.get(String(z.slot.face), z.head))
		return true
	if st == "chase" or st == "hunt":
		var prey = _prey.get(String(z.hunt_id))
		if prey != null:
			var ex: float = prey.x - z.x
			var ey: float = prey.y - z.y
			if ex * ex + ey * ey < 2.6:
				z.want = atan2(ey, ex)
				return true
	if st != "still" and z.path_i < z.path.size():
		var t: Vector2 = z.path[z.path_i]
		var fx: float = t.x - z.x
		var fy: float = t.y - z.y
		if fx * fx + fy * fy > 0.0016:
			z.want = atan2(fy, fx)
			return true
	return false


## Two dead that stand still are not asked by the rules' crowd pass: here they are, once they are nearer than 0.42 tiles (a wave at one spot of the fence does not stack in one pixel).
func _spread() -> void:
	_grid.clear()
	var zs: Array = sim.zombies
	var n := zs.size()
	for i in n:
		var a = zs[i]
		if a.state != "still":
			continue
		var key := floori(a.y) * CELL_KEY + floori(a.x)
		var cell = _grid.get(key)
		if cell == null:
			_grid[key] = [i]
		else:
			cell.append(i)
	for key in _grid:
		var cx: int = int(key) % CELL_KEY
		var cy: int = int(key) / CELL_KEY
		for i in _grid[key]:
			var a = zs[i]
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var cell = _grid.get((cy + oy) * CELL_KEY + cx + ox)
					if cell == null:
						continue
					for j in cell:
						if j <= i:
							continue
						var b = zs[j]
						var ex: float = b.x - a.x
						var ey: float = b.y - a.y
						var d2 := ex * ex + ey * ey
						if d2 > 0.1764:
							continue
						var d := sqrt(d2)
						var ux := 1.0 if (i + j) % 2 == 0 else -1.0
						var uy := 0.4
						if d > 1e-4:
							ux = ex / d
							uy = ey / d
						var push := (0.46 - d) * 0.5
						sim._nudge(a, -ux * push, -uy * push)
						sim._nudge(b, ux * push, uy * push)


# ---------------------------------------------------------------------- sound --

## A groan event of the rules: a voice by kind (a walker's groan, a near one or a far darker one; a runner's growl, higher; a brute's, lower), faded by the distance to Ruth.
func groan(e: Dictionary) -> void:
	if not enabled or game.sound.muted:
		return
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var d := me.distance_to(Vector2(float(e.x), float(e.y)))
	if d > REACH:
		return
	var kind := String(e.get("kind", "walker"))
	if game.audio != null and game.audio.enabled:
		_groan_placed(e, kind, d, me)
		return
	var pool: Array = _streams.get(kind, _streams.walker)
	if kind == "walker" and d > 16.0 and not (_streams.far as Array).is_empty():
		pool = _streams.far
	if pool.is_empty():
		return
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		return
	player.stream = pool[_rng.randi() % pool.size()]
	var base := -9.0 if bool(e.get("stray", false)) else -5.0
	player.volume_db = base - 28.0 * pow(d / REACH, 0.8)
	player.pitch_scale = (1.18 if kind == "runner" else (0.82 if kind == "brute" else 1.0)) * (0.92 + 0.16 * _rng.randf())
	player.play()


## The groan put where the groaner stands (PrisonAudio.sfx with a position: it pans by the screen and fades by the distance). Only the NEAR_VOICES nearest awake dead
## are heard, which also caps the sources.
func _groan_placed(e: Dictionary, kind: String, d: float, me: Vector2) -> void:
	var nearer := 0
	for z in game.run.sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var dx: float = float(z.x) - me.x
		var dy: float = float(z.y) - me.y
		if dx * dx + dy * dy < d * d - 0.01:
			nearer += 1
			if nearer >= NEAR_VOICES:
				return
	var f: Array = GROAN_FILES.get("far" if kind == "walker" and d > 16.0 else kind, GROAN_FILES.walker)
	var db := (-4.0 if bool(e.get("stray", false)) else 0.0)
	var pitch := (1.18 if kind == "runner" else (0.82 if kind == "brute" else 1.0)) * (0.92 + 0.16 * _rng.randf())
	game.audio.sfx("%s_%d" % [f[0], _rng.randi() % int(f[1])], db, pitch, "SFX", 0.0, Vector2(float(e.x), float(e.y)), REACH, game.audio.OLD)


# ---------------------------------------------------------------------- checks --

## --zombietest=walk|turn|attack|hit|wake|herd [--ztime=S] (with --cam on the spot, --seq=N,every for pictures, --nozmove to compare with the old dead): stages one thing in the yard and prints a ZTEST line.
## walk: a walker, a runner and a brute walk circles (jitter of the drawn position, turn rate, stride). turn: three still ones are told to go to a point behind them (the turn, and how long they stand
## before they walk). attack: one is sent at Ruth (lunge, recoil). hit: two walkers are shot, one from the west, one from the north, then killed (knock-back, stumble, the way they fall). wake: one
## is woken and sent east (the rise). herd: counts how many pairs stand nearer than 0.25 tiles (use with --siege=N --siegeseg=I).
var _tt := 0.0
var _zs: Array = []
var _log: Array = []
var _go_n := 0
var _marks := {}


func test(dt: float) -> void:
	sim = game.run.sim
	var mode := String(game.args.zombietest)
	var c := Vector2(11.0, 64.0)
	if _zs.is_empty() and mode != "herd":
		_stage(mode, c)
	_tt += dt
	sim.field.wake_r = 0.1    # (nobody else wakes: the check has its own dead)
	if game.crew != null:
		for m in game.crew.members:
			if not m.p.player:
				m.p.x = 30.0 + float(m.p.get_instance_id() % 7)    # (the crew are kept in the yard, away from the staged dead)
				m.p.y = 22.0
	var T := float(game.args.get("ztime", 8.0))
	match mode:
		"walk":
			for i in _zs.size():
				var z = _zs[i]
				if z.path_i >= z.path.size():
					z.path = _circle(c, 3.0 + 1.6 * float(i), float(i) * 2.0, z)
					z.path_i = 0
				z.wander_t = 99.0
		"turn":
			if _tt >= 1.5 and _go_n == 0:
				_go_n = 1
				for z in _zs:
					sim.field._investigate(z, Vector2(z.x, z.y) + Vector2(0.0, -7.0))
					_marks[z] = {"t0": _tt, "x0": z.x, "y0": z.y, "h0": z.head, "moved": -1.0}
		"attack":
			if _tt >= 1.0 and _go_n == 0:
				_go_n = 1
				for z in _zs:
					sim.start_chase(z, game.run.avatar_p)
		"hit":
			if _tt >= 1.2 and _go_n == 0:
				_go_n = 1
				sim._hurt_zombie(_zs[0], 6.0, 0.0, null)
				sim._hurt_zombie(_zs[1], 6.0, -PI / 2.0, null)
			if _tt >= 2.6 and _go_n == 1:
				_go_n = 2
				sim._hurt_zombie(_zs[0], 999.0, 0.0, null)
				sim._hurt_zombie(_zs[1], 999.0, -PI / 2.0, null)
			for z in _zs:
				if z.state == "wander":
					z.wander_t = 99.0
					if z.path_i >= z.path.size():
						z.path = _circle(c, 3.0, 0.0, z)
						z.path_i = 0
		"wake":
			if _tt >= 3.0 and _go_n == 0:
				_go_n = 1
				for z in _zs:
					sim.field._investigate(z, Vector2(z.x + 6.0, z.y))
	# sample the drawn figures
	var row := {}
	for z in sim.zombies:
		var n = game.pawn_nodes.get(z)
		if n != null and (_zs.has(z) or mode == "herd"):
			row[z] = [n.position, n._ori, float(z.rise), String(z.state)]
	_log.append(row)
	if mode == "herd" and int(game.frames) % 60 == 0:
		var pr := 0
		var at := Vector2.ZERO
		for z in sim.zombies:
			if z.press > 0.0:
				pr += 1
				at += Vector2(z.x, z.y)
		print("ZTEST herd overlaps<0.25: ", overlaps(0.25), " <0.4: ", overlaps(0.4), " awake ", sim.zombies.size(), " leaning ", pr, " at ", (at / maxf(1.0, float(pr))).snapped(Vector2(0.1, 0.1)))
	if _tt >= T and not _marks.has("done"):
		_marks["done"] = true
		_report(mode)


func _stage(mode: String, c: Vector2) -> void:
	var specs: Array = []
	match mode:
		"walk":
			specs = [["walker", c + Vector2(3, 0)], ["runner", c + Vector2(4.6, 0)], ["brute", c + Vector2(6.2, 0)]]
		"turn":
			specs = [["walker", c + Vector2(-4, 0)], ["runner", c], ["brute", c + Vector2(4, 0)]]
		"attack":
			specs = [["walker", c + Vector2(-6, -1.0)], ["walker", c + Vector2(-6, 1.0)], ["brute", c + Vector2(6, 0)]]
		"hit":
			specs = [["walker", c + Vector2(3, 0)], ["walker", c + Vector2(0, 3)]]
		"wake":
			specs = [["walker", c], ["walker", c + Vector2(2, 1.5)]]
	for sp in specs:
		var z
		if mode == "wake":
			var rec: int = sim.field.add_record(sp[1], sp[0], true)
			z = sim.field._wake(rec)
		else:
			z = sim.spawn(sp[1].x, sp[1].y, "wander" if mode in ["walk", "hit"] else "still", sp[0])
		z.hp = 40.0 if mode == "hit" else z.hp
		z.speed = 1.0 if sp[0] == "walker" else z.speed
		z.groan_t = 999.0
		if mode == "turn" or mode == "attack":
			z.head_ok = true
			z.head = PI / 2.0 if mode == "turn" else 0.0
			z.idle = z.head
			z.rise = 1.0
		_zs.append(z)
	if mode == "attack":
		game.run.avatar_p.x = c.x
		game.run.avatar_p.y = c.y
		game.run.invulnerable = true


func _circle(c: Vector2, r: float, a0: float, z) -> Array:
	var pts: Array = []
	var a := atan2(z.y - c.y, z.x - c.x)
	for i in 24:
		pts.append(c + Vector2.from_angle(a + float(i + 1) * TAU / 48.0 * 1.0) * r)
	return pts


## Pairs of awake dead nearer than `d` tiles.
func overlaps(d: float) -> int:
	var n := 0
	var zs: Array = sim.zombies
	for i in zs.size():
		for j in range(i + 1, zs.size()):
			var dx: float = zs[i].x - zs[j].x
			if absf(dx) < d and Vector2(dx, zs[i].y - zs[j].y).length() < d:
				n += 1
	return n


func _report(mode: String) -> void:
	for z in _zs:
		var jit := 0.0
		var spd := 0.0
		var rate := 0.0
		var cnt := 0
		var prev2 = null
		var prev = null
		var hprev := 0.0
		var hs := 0.0
		var err := 0.0
		var errn := 0
		var hist: Array = []
		var skip := 0
		for row in _log:
			skip += 1
			if not row.has(z) or skip < 12:
				continue
			var cur: Vector2 = row[z][0]
			if prev != null:
				spd += cur.distance_to(prev)
				if cur.distance_to(prev) > 0.05:
					err += absf(wrapf(float(row[z][1]) - (cur - prev).angle(), -PI, PI))
					errn += 1
				var dh := absf(wrapf(float(row[z][1]) - hprev, -PI, PI))
				hs += dh
				hist.append(float(row[z][1]))
				if hist.size() > 15:
					rate = maxf(rate, absf(wrapf(hist[hist.size() - 1] - hist[hist.size() - 16], -PI, PI)) * 4.0)
			if prev2 != null:
				jit += (cur - 2.0 * prev + prev2).length()
				cnt += 1
			prev2 = prev
			prev = cur
			hprev = row[z][1]
		var line := "ZTEST %s %s state=%s jitter=%.3f px/frame2 speed=%.2f px/frame max_turn=%.0f deg/s heading_travel=%.0f deg face_vs_motion_err=%.0f deg" % [mode, z.kind, z.state, jit / maxf(1.0, float(cnt)), spd / maxf(1.0, float(cnt)), rad_to_deg(rate), rad_to_deg(hs), rad_to_deg(err / maxf(1.0, float(errn)))]
		if _marks.has(z):
			var m: Dictionary = _marks[z]
			var th := -1.0
			var tm := -1.0
			var k := 0
			var p0 = null
			for row in _log:
				k += 1
				if not row.has(z) or float(k) / 60.0 < float(m.t0) + 0.1:
					continue
				if p0 == null:
					p0 = row[z][0]
				if th < 0.0 and absf(wrapf(float(row[z][1]) - float(m.h0), -PI, PI)) > PI * 0.8:
					th = float(k) / 60.0 - float(m.t0)
				if tm < 0.0 and (row[z][0] as Vector2).distance_to(p0) > 3.0:
					tm = float(k) / 60.0 - float(m.t0)
			line += " turned_180_after=%.2fs first_step_after=%.2fs" % [th, tm]
		print(line)
	print("ZTEST ", mode, " overlaps<0.25=", overlaps(0.25), " stats=", stats)
