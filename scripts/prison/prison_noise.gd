## ROUND 12 (prison only): NOISE AND HORDES. One call, `Noise.emit(pos, loudness_tiles, kind)`, is how everything that makes a sound tells the dead: a shot, a blow, a step at the run, a search,
## breaking glass, hammering at the base, the generator, the bell, a thrown bottle, a car alarm, a screamer. The town's own rules (scripts/town/dormant_dead.gd `noise`, which a shot, a blow and a run
## already call) are handed to this module by one hook (`field.noise_hook`), so nothing else had to change; `--nonoise` leaves the hook off and the rules as they were.
##
## WHAT A NOISE DOES (numbers: assets/data/prison_noise.json). Every noise warms the heat of the 16-tile region it is in (heat falls at a steady rate: the HUD chip "Noise: quiet / loud / very loud"
## reads it, and a loud region lets one noise call more dead). The dead that stand or wander within the radius, and the sleeping ones (their records), each hear it with a chance that falls with the
## distance as heard: the distance plus a few tiles for every wall between (a line of the walking grid, at most three walls). The nearest `cap` that heard it walk to the spot (`field._investigate`),
## mill about there 8 to 20 seconds and lose interest. Past `join_n` dead called, the nearest others in `join_r` follow (a horde, marked red on the ground and on the map). The ones already chasing
## somebody keep chasing; the dead of a siege wave are left to their fence. HORDES (raid: crosses the town; base: comes at a fence segment on some nights) live here too, and so do the thrown
## distractions (G), the car alarms and the placeholder sounds (made in code: free, no files; `# SOUND hook` calls `sound.sting(name)` or the `Audio` autoload when there is one).
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const Inventory := preload("res://scripts/sim/inventory.gd")
const Base := preload("res://scripts/prison/prison_base.gd")
const PATH := "res://assets/data/prison_noise.json"
const RATE := 22050

static var cfg := {}
static var inst

var game
var enabled := true
var rng := RandomNumberGenerator.new()
var heat := {}    # region key -> heat
var inv := {}    # Zombie -> {tgt, arrived, mill, horde}: the dead that went to look
var ripples: Array = []    # {pos, r, t, life, col}
var throws: Array = []    # thrown things in the air
var pops: Array = []    # firecrackers and flares going on at a spot: {pos, left, t, gap, loud, flare}
var alarms: Array = []    # car alarms: {pos, t, dur, next}
var cars: Array = []    # {pos, used}
var hordes: Array = []    # {members, dest, kind, side, name, t, warned}
var stats := {"emits": 0, "alerted": 0, "woke": 0, "joined": 0, "lost": 0}
var last_alert := 0
var _hooked = null
var _shot_t := 0.0
var _build_t := 0.0
var _gen_t := 0.0
var _players: Array = []
var _siren: AudioStreamPlayer
var _streams := {}
var _toasted := {}
var _hold_msg := ""
var test_log := false
var usec := 0    # microseconds spent in `update` (--perf prints the share of a frame)


static func load_cfg() -> void:
	if not cfg.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	cfg = parsed if parsed is Dictionary else {}


## The call everything uses. `goto` (optional) is where the called dead walk when that is not the noise's own place (a scream calls them to whoever was seen). Returns how many were called.
static func emit(pos: Vector2, loudness_tiles: float, kind: String = "shot", goto: Vector2 = Vector2.INF) -> int:
	if inst == null:
		return 0
	return inst.emit_at(pos, loudness_tiles, kind, goto)


func _init(g = null) -> void:
	game = g
	load_cfg()
	rng.seed = 1212
	enabled = g == null or not g.args.has("nonoise")
	inst = self
	if g != null:
		_make_sounds()


func setup() -> void:
	# (nothing to build: the sounds are made in _init; the field is bound lazily in `bind`)
	pass


## Called every frame: puts the hook on this run's field (the sim is made anew for every raid and for the base).
func bind() -> void:
	var run = game.run
	if run == null or run.sim == null or run.sim.field == null:
		return
	var f = run.sim.field
	if _hooked != f:
		_hooked = f
		if enabled:
			f.noise_hook = Callable(self, "_on_field")
		_reset_run()


func _reset_run() -> void:
	inv.clear()
	hordes.clear()
	alarms.clear()
	pops.clear()
	throws.clear()
	cars.clear()
	var td = game.town
	if game.mode == "raid" and td is Dictionary and td.has("data"):
		for o in (td.data as Dictionary).get("objects", []):
			var k := String(o.get("kind", ""))
			if k.begins_with("car") and int(o.get("in", -1)) < 0:
				cars.append({"pos": Vector2(float(o.cx), float(o.cy)), "used": false})


func _on_field(at: Vector2, _prey, radius: float) -> void:
	var r := radius if radius > 0.0 else 16.0
	var kind := "shot"
	if r <= 4.0:
		kind = "melee"
	elif r <= 8.5:
		kind = "step"
	emit_at(at, r, kind, Vector2.INF)


# ----------------------------------------------------------------------------- the noise --

func _kind(kind: String) -> Dictionary:
	return cfg.kinds.get(kind, cfg.kinds.shot)


func _hkey(p: Vector2) -> int:
	var c := float(cfg.heat.cell)
	return int(floor(p.y / c)) * 1000 + int(floor(p.x / c))


## The heat round a point: its own region and half of each neighbour.
func heat_at(p: Vector2) -> float:
	var c := float(cfg.heat.cell)
	var cx := int(floor(p.x / c))
	var cy := int(floor(p.y / c))
	var h := float(heat.get(cy * 1000 + cx, 0.0))
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		h += 0.35 * float(heat.get((cy + d.y) * 1000 + cx + d.x, 0.0))
	return h


func level(p: Vector2) -> int:
	var h := heat_at(p)
	return 0 if h < float(cfg.heat.loud_at) else (1 if h < float(cfg.heat.very_at) else 2)


func level_word() -> String:
	return ["quiet", "loud", "very loud"][level(Vector2(game.run.avatar_p.x, game.run.avatar_p.y))]


func emit_at(pos: Vector2, loud: float, kind: String, goto: Vector2) -> int:
	last_alert = 0
	if not enabled or game == null or game.run == null or game.run.sim.field == null:
		return 0
	var k: Dictionary = _kind(kind)
	var field = game.run.sim.field
	stats.emits += 1
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var r: float = (loud if loud > 0.0 else float(k.loud)) * float(field.noise_mult) * (float(game.loot.noise_mult()) if game.mode == "raid" and game.loot != null else 1.0)
	heat[_hkey(pos)] = float(heat.get(_hkey(pos), 0.0)) + float(k.heat)
	r *= 1.0 + minf(0.5, heat_at(pos) * 0.025)    # (a loud place carries sound farther: continued shooting calls more)
	if bool(k.ripple) and (pos.distance_to(me) < 3.0 or kind == "throw"):
		ripples.append({"pos": pos, "r": minf(r, 14.0), "t": 0.0, "life": 1.1, "col": Color(1, 1, 1, 0.28) if kind != "throw" else Color(1.0, 0.9, 0.5, 0.4)})
	if kind == "shot" or kind == "glass":
		_car_shot(pos)
	if int(k.cap) <= 0 or r <= 0.5:
		return 0
	if kind == "shot":    # (an SMG emptying a magazine asks the question a few times a second, not thirty)
		if _shot_t > 0.0:
			return 0
		_shot_t = 0.2
	var cap := int(round(float(k.cap) * (1.0 + minf(heat_at(pos) * float(cfg.heat.cap_per_heat), float(cfg.heat.cap_max)))))
	var waves := _wave_set()
	var cand: Array = []    # [heard, zombie or null, record]
	var w: Dictionary = cfg.wake
	var see := float(k.see)
	for z in game.run.sim.zombies:
		var st: String = z.state
		if st != "still" and st != "wander":
			continue
		if waves.has(z) or (game.special != null and game.special.locked(z)):
			continue
		var dd := Vector2(z.x - pos.x, z.y - pos.y).length()
		if dd >= r:
			continue
		var heard := dd + float(_walls(pos, Vector2(z.x, z.y))) * float(w.wall)
		if heard >= r:
			continue
		var p := float(k.wake) * pow(1.0 - heard / r, float(w.fall)) * 1.15
		if rng.randf() < minf(p, 1.0) and rng.randf() < see + (1.0 - see) * 0.3:
			cand.append([heard, z, -1])
	if not field.pause_wake:
		var C: int = field.CELL
		var c0 := clampi(floori((pos.x - r) / float(C)), 0, field.cols - 1)
		var c1 := clampi(floori((pos.x + r) / float(C)), 0, field.cols - 1)
		var r0 := clampi(floori((pos.y - r) / float(C)), 0, field.rows - 1)
		var r1 := clampi(floori((pos.y + r) / float(C)), 0, field.rows - 1)
		for cy in range(r0, r1 + 1):
			for cx in range(c0, c1 + 1):
				for i in field.cells[cy * field.cols + cx]:
					var q := Vector2(field.xs[i], field.ys[i])
					var dd2 := q.distance_to(pos)
					if dd2 >= r:
						continue
					var heard2 := dd2 + float(_walls(pos, q)) * float(w.wall)
					if heard2 >= r:
						continue
					if rng.randf() < float(k.wake) * pow(1.0 - heard2 / r, float(w.fall)):
						cand.append([heard2, null, int(i)])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var room: int = maxi(0, field.active_cap - field.active_of.size())
	var target := goto if goto != Vector2.INF else pos
	var called: Array = []
	for e in cand:
		if called.size() >= cap:
			break
		var z = e[1]
		if z == null:
			if room <= 0:
				continue
			z = field._wake(int(e[2]))
			if z == null:
				continue
			room -= 1
			stats.woke += 1
		_go(z, _where(z, kind, target, k))
		called.append(z)
	last_alert = called.size()
	stats.alerted += called.size()
	# the swell: past join_n the nearest others follow, and a horde that heard it turns as one
	var hc: Dictionary = cfg.horde
	if called.size() + inv.size() > int(hc.join_n) and not called.is_empty() and kind != "tower":
		var more: Array = []
		for z in game.run.sim.zombies:
			if (z.state == "still" or z.state == "wander") and not inv.has(z) and not waves.has(z) and not called.has(z):
				var d := Vector2(z.x, z.y).distance_to(pos)
				if d < float(hc.join_r):
					more.append([d, z])
		more.sort_custom(func(a, b): return a[0] < b[0])
		for i in mini(more.size(), int(hc.join_max)):
			var z2 = more[i][1]
			_go(z2, _where(z2, kind, target, k), true)
			stats.joined += 1
	for h in hordes:
		for z in called:
			if (h.members as Array).has(z):
				_turn_horde(h, target)
				break
	if test_log:
		print("NOISE ", kind, " r=", snappedf(r, 0.1), " called ", called.size(), " at ", pos.snapped(Vector2(0.1, 0.1)))
	return called.size()


## Where a called dead one goes: the spot, or for a noise made at the base (hammering, the generator, the bell) the nearest fence segment's outer spot.
func _where(z, _kind_name: String, target: Vector2, k: Dictionary) -> Vector2:
	var to := String(k.get("to", "spot"))
	if to == "fence" and game.mode == "base" and game.siege != null and float(z.y) > 56.0:
		var best := target
		var bd := 1.0e9
		for s in game.siege.segs:
			if float(s.hp) <= 0.0:
				continue
			var d := Vector2(z.x, z.y).distance_to(Vector2(s.spot))
			if d < bd:
				bd = d
				best = Vector2(s.spot) + Vector2(s.along) * rng.randf_range(-3.0, 3.0)
		return best
	return target + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))


func _go(z, target: Vector2, horde := false) -> void:
	game.run.sim.field._investigate(z, target)
	inv[z] = {"tgt": target, "arrived": -1.0, "mill": 0.0, "horde": horde, "t": 0.0}


## The nearest free ground to a point of the world (a few tries round it).
func _free(at: Vector2) -> Vector2:
	var w = game.world
	var a := Vector2(clampf(at.x, 2.5, float(w.W) - 2.5), clampf(at.y, 2.5, float(w.H) - 2.5))
	for k in 14:
		if not w.is_solid(w.solid_z, a.x, a.y):
			return a
		a = Vector2(clampf(at.x + rng.randf_range(-3.0, 3.0), 2.5, float(w.W) - 2.5), clampf(at.y + rng.randf_range(-3.0, 3.0), 2.5, float(w.H) - 2.5))
	return a


func _wave_set() -> Dictionary:
	var out := {}
	if game.siege != null:
		for w in game.siege.wave:
			out[w.z] = true
	return out


## Walls between two points: how many separate runs of solid tiles the line crosses (at most `wall_max`).
func _walls(a: Vector2, b: Vector2) -> int:
	var d := a.distance_to(b)
	var n := clampi(int(ceil(d)), 1, 40)
	var w := 0
	var prev := false
	var world = game.world
	for i in range(1, n):
		var q := a.lerp(b, float(i) / float(n))
		var s: bool = world.is_solid(world.solid_z, q.x, q.y)
		if s and not prev:
			w += 1
		prev = s
	return mini(w, int(cfg.wake.wall_max))


## A table row for the report: the chance one dead one at `d` tiles (and `walls` walls between) hears a noise of radius `r` of this kind.
static func hear_p(r: float, d: float, walls: int, kind: String = "shot") -> float:
	load_cfg()
	var k: Dictionary = cfg.kinds.get(kind, cfg.kinds.shot)
	var heard := d + float(mini(walls, int(cfg.wake.wall_max))) * float(cfg.wake.wall)
	if heard >= r:
		return 0.0
	return minf(1.0, float(k.wake) * pow(1.0 - heard / r, float(cfg.wake.fall)) * 1.15)


# ----------------------------------------------------------------------------- the step --

func update(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_update(dt)
	usec += Time.get_ticks_usec() - t0
	if game.args.has("perf") and game.frames == 1799:
		print("NOISEPERF module ms/frame ", snappedf(float(usec) / 1799.0 / 1000.0, 0.001), " emits ", stats.emits, " alerted ", stats.alerted, " special ms/frame ", snappedf(float(game.special.usec) / 1799.0 / 1000.0, 0.001))


func _update(dt: float) -> void:
	bind()
	if game.run == null:
		return
	_shot_t = maxf(0.0, _shot_t - dt)
	var dec := float(cfg.heat.decay) * dt
	for kk in heat.keys():
		heat[kk] = float(heat[kk]) - dec * (1.0 + float(heat[kk]) * 0.08)
		if float(heat[kk]) <= 0.0:
			heat.erase(kk)
	_interest(dt)
	_throws(dt)
	_pops(dt)
	_alarms(dt)
	_hordes(dt)
	_base_noises(dt)
	for r in ripples:
		r.t = float(r.t) + dt
	ripples = ripples.filter(func(r): return float(r.t) < float(r.life))
	if game.args.has("noisetest"):
		_test(dt)


func _interest(dt: float) -> void:
	var ic: Dictionary = cfg.interest
	for z in inv.keys():
		var e: Dictionary = inv[z]
		var st: String = z.state
		if st == "dying" or st == "dead" or z.remove or (st != "wander" and st != "still"):
			inv.erase(z)
			continue
		e.t = float(e.t) + dt
		var near: bool = Vector2(z.x, z.y).distance_to(e.tgt) < 1.6 or (float(e.t) > float(ic.arrive) and z.path_i >= z.path.size())
		if float(e.arrived) < 0.0:
			if near:
				e.arrived = float(e.t)
				e.mill = rng.randf_range(float(ic.min), float(ic.max))
		elif float(e.t) - float(e.arrived) > float(e.mill):
			# it loses interest: it stands where it is, and is free to go back to sleep
			z.state = "still"
			z.path = []
			z.wander_t = 0.0
			stats.lost += 1
			inv.erase(z)


# ----------------------------------------------------------------------------- the base's own noise --

func _base_noises(dt: float) -> void:
	if game.mode != "base" or game.phase != "managed" or game.crew == null:
		return
	_build_t -= dt
	if _build_t <= 0.0:
		_build_t = 1.3
		for m in game.crew.members:
			if String(m.p.work) == "hammer":
				emit_at(Vector2(m.p.x, m.p.y), 0.0, "build", Vector2.INF)
				break
	_gen_t -= dt
	if _gen_t <= 0.0:
		_gen_t = 4.0
		if game.upg != null and game.upg.has_method("_lit") and bool(game.upg._lit()):
			emit_at(Vector2(30.0, 53.0), 0.0, "generator", Vector2.INF)


## The bell of the siege (prison_siege.gd `_bells`): a loud noise from the middle of the compound.
func bell() -> void:
	emit_at(Vector2(48.0, 50.0), 0.0, "bell", Vector2.INF)


# ----------------------------------------------------------------------------- thrown things --

func has_throwable() -> bool:
	return game.pack != null and not game.pack.grid.is_empty() and Inventory.count_of(game.pack.grid, "distraction") > 0


func _take_one() -> bool:
	var cells: Array = game.pack.grid.cells
	for i in cells.size():
		if String(cells[i].item) == "distraction":
			if int(cells[i].count) > 1:
				cells[i].count = int(cells[i].count) - 1
			else:
				Inventory.remove(game.pack.grid, i)
			if game.pack.inv != null:
				game.pack.inv.version = int(game.pack.inv.version) + 1
			return true
	return false


## G: throw a bottle, a can, a firecracker or a flare to `at` (at most `range` tiles from her). False when she has nothing to throw.
func throw_at(at: Vector2) -> bool:
	if game.run == null or game.busy:
		return false
	if not _take_one():
		game._say("Nothing to throw. Bottles and cans turn up in houses and shops.", 2.5)
		return false
	var tc: Dictionary = cfg.throw
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var d := at - me
	if d.length() > float(tc.range):
		d = d.normalized() * float(tc.range)
	var to := me + d
	var tot := 0.0
	for kn in tc.kinds:
		tot += float(tc.kinds[kn].w)
	var pick := rng.randf() * tot
	var kind := "bottle"
	for kn in tc.kinds:
		pick -= float(tc.kinds[kn].w)
		if pick <= 0.0:
			kind = String(kn)
			break
	throws.append({"from": me, "to": to, "t": 0.0, "kind": kind})
	game.run.avatar_p.facing = game.run.sim.facing_of(d.x, d.y, game.run.avatar_p.facing)
	_play("whoosh", -14.0, me)
	return true


func _throws(dt: float) -> void:
	var tc: Dictionary = cfg.throw
	for th in throws:
		th.t = float(th.t) + dt
		if float(th.t) >= float(tc.flight) and not th.has("done"):
			th["done"] = true
			var kd: Dictionary = tc.kinds[th.kind]
			var to: Vector2 = th.to
			emit_at(to, float(kd.loud), "throw", Vector2.INF)
			_play("smash" if th.kind == "bottle" else ("clink" if th.kind == "can" else "pop"), -4.0, to)
			game.fx.hit_material(to.x, to.y, "metal")
			if kd.has("pops"):
				pops.append({"pos": to, "left": int(kd.pops), "t": 0.5, "gap": float(kd.get("gap", 0.45)), "loud": float(kd.loud), "flare": th.kind == "flare", "age": 0.0})
	throws = throws.filter(func(t): return not t.has("done"))


func _pops(dt: float) -> void:
	for p in pops:
		p.age = float(p.age) + dt
		p.t = float(p.t) - dt
		if float(p.t) <= 0.0 and int(p.left) > 0:
			p.t = float(p.gap) * rng.randf_range(0.6, 1.2)
			p.left = int(p.left) - 1
			emit_at(p.pos, float(p.loud) * 0.9, "throw", Vector2.INF)
			_play("pop" if not p.flare else "hiss", -6.0, p.pos)
	pops = pops.filter(func(p): return int(p.left) > 0 or (bool(p.flare) and float(p.age) < 14.0))


# ----------------------------------------------------------------------------- car alarms --

func _car_shot(pos: Vector2) -> void:
	var ac: Dictionary = cfg.alarm
	for c in cars:
		if not bool(c.used) and (c.pos as Vector2).distance_to(pos) < float(ac.shot_r) and rng.randf() < float(ac.shot_chance):
			start_alarm(c)


## A container was searched: a car may go off.
func on_search(container: String, at: Vector2) -> void:
	emit_at(at, 0.0, "search", Vector2.INF)
	if container.begins_with("car"):
		for c in cars:
			if not bool(c.used) and (c.pos as Vector2).distance_to(at) < 3.5 and rng.randf() < (game.loot.alarm_open(float(cfg.alarm.open_chance)) if game.loot != null else float(cfg.alarm.open_chance)):
				start_alarm(c)


func start_alarm(c: Dictionary) -> void:
	c.used = true
	var ac: Dictionary = cfg.alarm
	alarms.append({"pos": c.pos, "t": 0.0, "dur": rng.randf_range(float(ac.secs[0]), float(ac.secs[1])), "next": 0.0})
	game._say("A car alarm goes off!", 4.0)
	sting("alarm")


func _alarms(dt: float) -> void:
	var ac: Dictionary = cfg.alarm
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var near := 1.0e9
	for a in alarms:
		a.t = float(a.t) + dt
		a.next = float(a.next) - dt
		if float(a.next) <= 0.0:
			a.next = float(ac.every)
			emit_at(a.pos, float(ac.loud), "alarm", Vector2.INF)
		near = minf(near, (a.pos as Vector2).distance_to(me))
	alarms = alarms.filter(func(a): return float(a.t) < float(a.dur))
	if _siren != null:
		if alarms.is_empty():
			_siren.stop()
		else:
			if not _siren.playing:
				_siren.play()
			_siren.volume_db = -6.0 - 30.0 * pow(clampf(near / 40.0, 0.0, 1.0), 0.8)


# ----------------------------------------------------------------------------- hordes --

func _horde_alive(h: Dictionary) -> Array:
	var out: Array = []
	for z in h.members:
		if z.state != "dying" and z.state != "dead" and not z.remove:
			out.append(z)
	h.members = out
	return out


func centroid(h: Dictionary) -> Vector2:
	var c := Vector2.ZERO
	for z in h.members:
		c += Vector2(z.x, z.y)
	return c / maxf(1.0, float((h.members as Array).size()))


func _turn_horde(h: Dictionary, target: Vector2) -> void:
	h.dest = target
	var i := 0
	for z in h.members:
		if z.state == "wander" or z.state == "still":
			i += 1
			if i > 60:
				break
			game.run.sim.field._investigate(z, target + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)))
			inv[z] = {"tgt": target, "arrived": -1.0, "mill": 0.0, "horde": true, "t": 0.0}


func _hordes(dt: float) -> void:
	for h in hordes:
		h.t = float(h.t) + dt
		var alive := _horde_alive(h)
		if alive.is_empty():
			h["gone"] = true
			continue
		h["acc"] = float(h.get("acc", 0.0)) + dt    # (how fast it really goes: the base of the ETA)
		if float(h.acc) >= 2.0:
			var cn := centroid(h)
			if h.has("last"):
				var v := cn.distance_to(h.last) / float(h.acc)
				h["rate"] = lerpf(float(h.get("rate", v)), v, 0.4)
			h["last"] = cn
			h["acc"] = 0.0
	hordes = hordes.filter(func(h): return not h.has("gone"))


## A horde of `n` dead appears at `from` (spread over a few tiles) and walks to `to` at `speed` tiles a second. Returns the horde, or {} when the town has no room for them.
func spawn_horde(n: int, from: Vector2, to: Vector2, speed: float, kind_name: String, spread := 4.0) -> Dictionary:
	var field = game.run.sim.field
	var members: Array = []
	var room: int = maxi(0, field.active_cap - field.active_of.size())
	for i in mini(n, room):
		var at: Vector2 = _free(from + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)))
		var rec: int = field.add_record(at, "runner" if rng.randf() < 0.05 else "walker", false)
		var z = field._wake(rec)
		if z == null:
			continue
		var ri: int = field.rec_of.get(z, -1)    # (a horde is the sim's own: the field would put the far ones back to sleep)
		if ri >= 0:
			field.rec_of.erase(z)
			field.active_of.erase(ri)
			field.status[ri] = field.KILLED
		z.speed = speed / 0.55    # (the wander walk is 0.55 of the speed)
		z.groan_t = rng.randf() * 4.0
		field._investigate(z, to + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-3.0, 3.0)))
		inv[z] = {"tgt": to, "arrived": -1.0, "mill": 0.0, "horde": true, "t": 0.0}
		members.append(z)
	if members.is_empty():
		return {}
	var h := {"members": members, "dest": to, "kind": kind_name, "t": 0.0, "n0": members.size(), "speed": speed}
	hordes.append(h)
	return h


## A raid has begun: maybe a horde crosses the town (never on the first days).
func on_raid_begin() -> void:
	_reset_run()
	var hc: Dictionary = cfg.raid_horde
	var day := int(game.econ.day) if game.econ != null else 1
	var forced: bool = game.args.has("noisetest") and String(game.args.noisetest) == "horde"
	if not forced and (day < int(hc.min_day) or rng.randf() > float(hc.chance)):
		return
	var W := float(game.world.W)
	var H := float(game.world.H)
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var sim = game.run.sim
	for tries in 60:    # (a start and an end the dead can really walk between: an open road, not a yard shut by walls)
		var side := rng.randi() % 4
		var t := rng.randf_range(0.15, 0.85)
		var cand := _free(Vector2(8.0 if side == 0 else (W - 8.0 if side == 1 else t * W), 8.0 if side == 2 else (H - 8.0 if side == 3 else t * H)))
		if cand.distance_to(me) < float(hc.far):
			continue
		var dest := _free(Vector2(W, H) - cand + Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0)))
		if sim.path_z.find(game.world.solid_z, cand.x, cand.y, dest.x, dest.y).size() > 2:
			from = cand
			to = dest
			break
	if from == Vector2.ZERO:
		return
	var n := rng.randi_range(int(hc.size[0]), int(hc.size[1]))
	if game.args.has("horde"):
		n = int(game.args.horde)
	var h := spawn_horde(n, from, to, float(hc.speed), "raid")
	if h.is_empty():
		return
	h["name"] = _dir_word(from - Vector2(W, H) / 2.0)
	_toast_once("horde_raid", "A horde is crossing the town from the %s." % String(h.name), Color(1.0, 0.5, 0.4))
	sting("horde")


## The base's night: on the horde nights a horde comes at one fence segment from one side (and walks round the outside to it).
func on_attack(n: int, _picked: Array) -> void:
	bind()
	var bc: Dictionary = cfg.base_horde
	var forced: bool = game.args.has("horde") or (game.args.has("noisetest") and String(game.args.noisetest) == "horde")
	if not forced and not (bc.nights as Array).has(n):
		return
	var size := mini(int(bc.max), int(bc.size[0]) + int(bc.per_night) * maxi(0, n - 3))
	if game.args.has("horde"):
		size = int(game.args.horde)
	var side: String = ["E", "W", "N"][rng.randi() % 3]
	var pool: Array = game.siege.segs.filter(func(s): return s.side == side and float(s.hp) > 0.0)
	if pool.is_empty():
		return
	var seg: Dictionary = pool[rng.randi() % pool.size()]
	var from := Vector2(93.2, 68.0) if side == "E" else (Vector2(2.8, 68.0) if side == "W" else Vector2(92.0, 1.6))
	var h := spawn_horde(size, from, Vector2(seg.spot), float(bc.speed), "base", 2.5)
	if game.args.has("log"):
		print("NOISE base horde side ", side, " seg ", seg.name, " size ", size, " got ", h.get("members", []).size(), " room ", game.run.sim.field.active_cap - game.run.sim.field.active_of.size())
	if h.is_empty():
		return
	h["name"] = {"E": "east", "W": "west", "N": "north"}[side]
	for z in h.members:
		game.siege.wave.append({"z": z, "seg": seg, "spot": game.siege._spot(seg, 3.0)})
		inv.erase(z)
	game.siege.stats.n = int(game.siege.stats.n) + h.members.size()
	_toast_once("horde_base" + str(n), "Night %d: a horde of %d from the %s." % [n, h.members.size(), String(h.name)], Color(1.0, 0.5, 0.4))
	sting("horde")


## The top bar's attack chip: "Horde from the east in 40 s" while one walks in (empty otherwise).
func horde_text() -> String:
	for h in hordes:
		if String(h.kind) != "base":
			continue
		var alive: Array = h.members
		if alive.is_empty():
			continue
		var d := centroid(h).distance_to(Vector2(h.dest))
		if d < 5.0:
			return "Horde at the %s fence" % String(h.name)
		var rate: float = float(h.get("rate", 0.0))
		if rate < 0.05:
			rate = float(h.speed) * 0.4
		return "Horde from the %s in %d s" % [String(h.name), int(ceil(d / maxf(0.25, rate)))]
	return ""


func raid_horde_text() -> String:
	for h in hordes:
		if String(h.kind) == "raid" and not (h.members as Array).is_empty():
			var d := centroid(h).distance_to(Vector2(game.run.avatar_p.x, game.run.avatar_p.y))
			return "Horde %s: %d tiles" % [String(h.name), int(d)]
	return ""


static func _dir_word(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "east" if v.x > 0.0 else "west"
	return "south" if v.y > 0.0 else "north"


func _toast_once(key: String, text: String, col: Color) -> void:
	if _toasted.has(key):
		return
	_toasted[key] = true
	game.board.toast(text, col)
	game._say(text, 5.0)


## First time a kind of special is seen: the line that teaches it (prison_special.gd calls this).
func toast_first(kind: String) -> void:
	if cfg.toasts.has(kind):
		_toast_once("first_" + kind, String(cfg.toasts[kind]), Color(1.0, 0.75, 0.4))


# ----------------------------------------------------------------------------- the HUD --

## The top bar's noise chip: [main, sub, state, tip, meter].
func chip() -> Array:
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var lv := level(me)
	var h := heat_at(me)
	var words := ["quiet", "loud", "very loud"]
	var txt := "Quiet. Nothing is listening." if lv == 0 else ("Loud here. Shots are calling the dead." if lv == 1 else "Very loud. Stop shooting or move: more dead come with each shot.")
	var sub := String(words[lv])
	var hz := raid_horde_text()
	if hz != "":
		sub = hz
		txt += " " + hz + "."
	elif not alarms.is_empty():
		sub = "ALARM"
		txt += " A car alarm is going."
	return ["Noise", sub, ["ok", "warn", "danger"][lv], txt, clampf(h / (float(cfg.heat.very_at) * 1.3), 0.0, 1.0)]


func paint(c: CanvasItem) -> void:
	var T: float = game.TILE
	var font := ThemeDB.fallback_font
	for r in ripples:
		var u := float(r.t) / float(r.life)
		var col: Color = r.col
		col.a *= (1.0 - u)
		c.draw_arc(Vector2(r.pos) * T, float(r.r) * T * (0.15 + 0.85 * sqrt(u)), 0.0, TAU, 48, col, 3.0)
	for th in throws:
		var u := clampf(float(th.t) / float(cfg.throw.flight), 0.0, 1.0)
		var gp := (Vector2(th.from) as Vector2).lerp(th.to, u) * T
		var hh := sin(u * PI) * 1.6 * T
		c.draw_circle(gp, 4.0, Color(0, 0, 0, 0.35))
		c.draw_circle(gp - Vector2(0, hh + 10.0), 5.0, Color(0.7, 0.9, 0.8) if th.kind == "bottle" else Color(0.8, 0.8, 0.85))
	for p in pops:
		if bool(p.flare):
			var fl: float = 0.7 + 0.3 * sin(float(game.clock) * 18.0)
			c.draw_circle(Vector2(p.pos) * T, 2.6 * T * fl, Color(1.0, 0.25, 0.15, 0.16))
			c.draw_circle(Vector2(p.pos) * T, 0.9 * T * fl, Color(1.0, 0.7, 0.4, 0.5))
	var blink: bool = int(game.clock * 4.0) % 2 == 0
	for a in alarms:
		var ap := Vector2(a.pos) * T
		c.draw_circle(ap + Vector2(-12, -18), 5.0, Color(1, 0.15, 0.1, 0.95) if blink else Color(1, 0.8, 0.2, 0.3))
		c.draw_circle(ap + Vector2(12, -18), 5.0, Color(1, 0.8, 0.2, 0.3) if blink else Color(0.2, 0.4, 1.0, 0.95))
		c.draw_circle(ap, 3.2 * T, Color(1, 0.2, 0.1, 0.1 if blink else 0.04))
		var pu := fposmod(float(a.t), float(cfg.alarm.every)) / float(cfg.alarm.every)
		c.draw_arc(ap, (1.0 + 7.0 * pu) * T, 0.0, TAU, 40, Color(1, 0.4, 0.3, 0.45 * (1.0 - pu)), 2.5)
	# the horde: a red ring under each of them and the word over the front of it
	for h in hordes:
		var n := 0
		for z in h.members:
			if z.state == "wander" or z.state == "still":
				c.draw_arc(Vector2(z.x, z.y) * T, 0.42 * T, 0.0, TAU, 12, Color(1.0, 0.25, 0.2, 0.55), 2.0)
				n += 1
		if n > 0:
			var cc := centroid(h) * T
			c.draw_string(font, cc + Vector2(-80, -1.6 * T), "HORDE x%d" % n, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, Color(1.0, 0.45, 0.4, 0.9))
	# the dead that went to look: a faint ring where they go
	var shown := {}
	for z in inv:
		var e: Dictionary = inv[z]
		var key := Vector2i((e.tgt as Vector2).round())
		if not shown.has(key) and not bool(e.horde):
			shown[key] = true
			c.draw_arc(Vector2(e.tgt) * T, 0.6 * T, 0.0, TAU, 16, Color(1.0, 0.8, 0.3, 0.25), 2.0)


## On the minimap: the awake chasers brighter, the horde as a red blob, the alarms flashing.
func mini(bars: CanvasItem, o: Vector2, sc: float) -> void:
	for z in game.run.sim.zombies:
		if z.state == "chase":
			bars.draw_circle(o + Vector2(z.x, z.y) * sc, 2.2, Color(1.0, 0.7, 0.2))
	var pulse: float = 0.5 + 0.5 * sin(float(game.clock) * 5.0)
	for h in hordes:
		if (h.members as Array).is_empty():
			continue
		var cc := centroid(h)
		bars.draw_circle(o + cc * sc, 3.0 + sqrt(float((h.members as Array).size())) * 0.9, Color(0.9, 0.1, 0.1, 0.35 + 0.25 * pulse))
		bars.draw_arc(o + cc * sc, 4.0 + sqrt(float((h.members as Array).size())), 0.0, TAU, 20, Color(1.0, 0.3, 0.25), 1.5)
		if String(h.kind) == "raid":
			var dd := (Vector2(h.dest) - cc).normalized()
			bars.draw_line(o + cc * sc, o + (cc + dd * 5.0) * sc, Color(1.0, 0.35, 0.3), 2.0)
	for a in alarms:
		bars.draw_circle(o + Vector2(a.pos) * sc, 3.0 + 2.0 * pulse, Color(1, 0.8, 0.2) if int(game.clock * 4.0) % 2 == 0 else Color(1, 0.2, 0.1))


# ----------------------------------------------------------------------------- sounds, made in code --

func _make_sounds() -> void:
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in 5:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		game.add_child(p)
		_players.append(p)
	_siren = AudioStreamPlayer.new()
	_siren.bus = bus
	game.add_child(_siren)
	_streams["siren"] = _wav(_siren_data(), true)
	_siren.stream = _streams["siren"]
	_streams["smash"] = _wav(_noise_burst(0.5, 14.0, 0.9, 2400.0))
	_streams["clink"] = _wav(_tone(1900.0, 1500.0, 0.3, 11.0, 0.6))
	_streams["pop"] = _wav(_noise_burst(0.14, 40.0, 1.0, 5000.0))
	_streams["hiss"] = _wav(_noise_burst(1.0, 3.0, 0.35, 4000.0))
	_streams["whoosh"] = _wav(_noise_burst(0.3, 6.0, 0.3, 900.0))
	_streams["scream"] = _wav(_scream_data())
	_streams["roar"] = _wav(_tone(110.0, 70.0, 0.9, 2.2, 0.8))
	_streams["burst"] = _wav(_noise_burst(1.0, 3.5, 0.8, 1500.0))
	_streams["thud"] = _wav(_tone(80.0, 40.0, 0.35, 9.0, 1.0))
	_streams["growl"] = _wav(_tone(190.0, 120.0, 0.7, 2.5, 0.7))
	_streams["warn"] = _wav(_tone(220.0, 170.0, 1.4, 1.2, 0.7))


func _wav(data: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	var b := PackedByteArray()
	b.resize(data.size() * 2)
	for i in data.size():
		b.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	s.data = b
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = data.size()
	return s


func _tone(f0: float, f1: float, secs: float, decay: float, vol: float) -> PackedFloat32Array:
	var n := int(secs * float(RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var u := float(i) / float(n)
		ph += TAU * lerpf(f0, f1, u) / float(RATE)
		out[i] = (sin(ph) + 0.4 * sin(ph * 2.0)) * exp(-decay * u) * vol * 0.6
	return out


func _noise_burst(secs: float, decay: float, vol: float, bright: float) -> PackedFloat32Array:
	var n := int(secs * float(RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var a := clampf(bright / float(RATE) * 2.0, 0.02, 0.95)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in n:
		var u := float(i) / float(n)
		lp += (r.randf_range(-1.0, 1.0) - lp) * a
		out[i] = lp * exp(-decay * u) * vol
	return out


func _siren_data() -> PackedFloat32Array:
	var n := int(1.6 * float(RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var u := float(i) / float(n)
		var f: float = 760.0 + 260.0 * sin(u * TAU * 2.0)
		ph += TAU * f / float(RATE)
		out[i] = (sin(ph) + 0.3 * sin(ph * 3.0)) * 0.45
	return out


func _scream_data() -> PackedFloat32Array:
	var n := int(1.4 * float(RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in n:
		var u := float(i) / float(n)
		var f := (620.0 + 900.0 * pow(u, 0.7)) * (1.0 + 0.04 * sin(u * 90.0))
		ph += TAU * f / float(RATE)
		var env := minf(u * 12.0, 1.0) * (1.0 - pow(u, 3.0))
		out[i] = (sin(ph) * 0.5 + sin(ph * 2.01) * 0.3 + r.randf_range(-0.25, 0.25)) * env * 0.8
	return out


## One of the made sounds, faded by the distance from Ruth to `at`.
func _play(name: String, base_db: float, at: Vector2) -> void:
	if game.sound != null and game.sound.muted:
		return
	var s = _streams.get(name)
	if s == null:
		return
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var d := me.distance_to(at)
	if d > 45.0:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.volume_db = base_db - 26.0 * pow(d / 45.0, 0.8)
			p.pitch_scale = rng.randf_range(0.93, 1.07)
			p.play()
			return


## SOUND hook: the sound agent's stings (`Audio.sting("screamer")` or `sound.sting(name)` when they exist), else the made sound of that name.
func sting(name: String, at := Vector2.INF) -> void:
	var a = game.get_node_or_null("/root/Audio")
	if a != null and a.has_method("sting"):
		a.sting(name)
		return
	if game.sound != null and game.sound.has_method("sting"):
		game.sound.sting(name)
		return
	var where := at if at != Vector2.INF else Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	match name:
		"screamer":
			_play("scream", -3.0, where)
		"horde":
			_play("warn", -6.0, Vector2(game.run.avatar_p.x, game.run.avatar_p.y))
		"alarm":
			pass    # (the siren loop is the alarm)
		"bloater_burst":
			_play("burst", -4.0, where)
		"hunter", "hunter_leap":
			_play("growl", -4.0, where)
		"breacher":
			_play("roar", -3.0, where)
		_:
			_play(name, -6.0, where)


# ----------------------------------------------------------------------------- the checks --

var _tt := 0.0
var _tstate := 0
var _kills0 := 0
var _tlog := 0.0


## --noisetest=shot|alarm|throw|horde|alert (with --raid, or --managed --siege=3 for horde at the base): stages one thing and prints NTEST lines.
func _test(dt: float) -> void:
	_tt += dt
	var mode := String(game.args.noisetest)
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	game.run.invulnerable = true
	test_log = true
	match mode:
		"shot":    # a burst of shots with dead sleeping round: how many come
			if _tstate == 0 and _tt > 1.0:
				_tstate = 1
				_stage_dead(me, 40, 6.0, 26.0)
				for i in 6:
					await game.get_tree().create_timer(0.3).timeout
					emit_at(me, 14.0, "shot", Vector2.INF)
				print("NTEST shot heat=", snappedf(heat_at(me), 0.1), " level=", level_word(), " called_total=", stats.alerted, " inv=", inv.size())
		"throw":
			if _tstate == 0 and _tt > 1.0:
				_tstate = 1
				_stage_dead(me + Vector2(10, 0), 14, 3.0, 12.0)
				Inventory.auto_add(game.pack.grid, "distraction", 4)
				throw_at(me + Vector2(10, 0))
			if _tstate == 1 and _tt > 8.0:
				_tstate = 2
				var near := 0
				for z in inv:
					if Vector2(z.x, z.y).distance_to(me + Vector2(10, 0)) < 4.0:
						near += 1
				print("NTEST throw investigating=", inv.size(), " near_spot=", near, " heat=", snappedf(heat_at(me), 0.1))
			if _tstate == 2 and _tt > 32.0:
				_tstate = 3
				print("NTEST throw after interest: investigating=", inv.size(), " lost=", stats.lost)
		"alarm":
			if _tstate == 0 and _tt > 1.0:
				_tstate = 1
				_stage_dead(me + Vector2(8, 0), 30, 4.0, 22.0)
				cars.append({"pos": me + Vector2(8, 0), "used": false})
				emit_at(me + Vector2(8, 1), 14.0, "shot", Vector2.INF)
				for c in cars:
					if (c.pos as Vector2).distance_to(me) < 12.0 and not bool(c.used):
						start_alarm(c)
			if _tstate == 1 and _tt > 20.0:
				_tstate = 2
				print("NTEST alarm alerted_total=", stats.alerted, " investigating=", inv.size(), " heat=", snappedf(heat_at(me), 0.1), " alarms_left=", alarms.size())
		"horde":
			if _tstate == 0 and _tt > 1.0:
				_tstate = 1
				if game.mode == "raid":
					on_raid_begin()
				print("NTEST horde count=", hordes.size(), " members=", (hordes[0].members as Array).size() if not hordes.is_empty() else 0)
			if game.args.has("maphorde") and _tstate == 1:
				game.map_view = true
				game.zoom_px = 8.0
			_tlog -= dt
			if _tstate == 1 and _tlog <= 0.0:
				_tlog = 5.0
				if not hordes.is_empty():
					print("NTEST horde wall=", Time.get_ticks_msec() / 1000, " frames=", game.frames, " t=", snappedf(_tt, 0.1), " centroid=", centroid(hordes[0]).snapped(Vector2(0.1, 0.1)), " dest=", Vector2(hordes[0].dest).snapped(Vector2(0.1, 0.1)), " alive=", (hordes[0].members as Array).size(), " text='", horde_text() + raid_horde_text(), "'")
		"kills":    # a shooter that stands still with 80 dead asleep round her: how many she kills in 60 s (run it with and without --nonoise)
			if _tstate == 0 and _tt > 1.0:
				_tstate = 1
				_stage_dead(me, 80, 5.0, 34.0)
				_kills0 = game.run.sim.kills
			var best = null
			var bd := 11.0
			for z in game.run.sim.zombies:
				if z.state == "dying" or z.state == "dead":
					continue
				var dz := Vector2(z.x, z.y).distance_to(me)
				if dz < bd and game.run.sim.clear_shot(me, Vector2(z.x, z.y), 0.15):
					bd = dz
					best = z
			if best != null:
				game._bot_in = {"move": Vector2.ZERO, "aim": Vector2(best.x, best.y), "fire": true}
			else:
				game._bot_in = {"move": Vector2.ZERO, "aim": me + Vector2(1, 0), "fire": false}
			if game.run.avatar_p.mag < 2:
				game.run.sim.avatar.reload()
			game.run.avatar_p.mag = maxi(int(game.run.avatar_p.mag), 2) if game.run.avatar_p.reloading <= 0.0 else game.run.avatar_p.mag
			game.run.sim.stock["ammo"] = 999.0
			_tlog -= dt
			if _tstate == 1 and _tlog <= 0.0:
				_tlog = 10.0
				print("NTEST kills t=", snappedf(_tt, 0.1), " kills=", game.run.sim.kills - _kills0, " awake=", game.run.sim.zombies.size(), " alerted=", stats.alerted, " woke=", stats.woke, " noise=", enabled)
			if _tt > 61.0:
				print("NTEST kills_per_min=", game.run.sim.kills - _kills0, " noise=", enabled, " alerted=", stats.alerted)
				game.get_tree().quit()
		"alert":
			if _tstate == 0:
				_tstate = 1
				_alert_table()


## Dead standing about at distances between `a` and `b` of `at` (real zombies, asleep as records when `rec`).
func _stage_dead(at: Vector2, n: int, a: float, b: float) -> void:
	var field = game.run.sim.field
	for i in n:
		var ang := rng.randf() * TAU
		var d := rng.randf_range(a, b)
		var p := _free(at + Vector2.from_angle(ang) * d)
		field.add_record(p, "walker", true)


## The numbers of the report: the chance one dead one hears a shot of each gun, at 5, 10 and 20 tiles, in the open and with one and two walls between.
func _alert_table() -> void:
	print("NTEST alert table: chance one dead one hears (and how many of a crowd of 1 per 6 tiles^2 are called, cap by heat 0)")
	for gun in [["shotgun", 16.0], ["service", 14.0], ["smg", 13.0]]:
		var row := String(gun[0]).rpad(8)
		for walls in [0, 1, 2]:
			for d in [5.0, 10.0, 20.0]:
				row += "  %s%dw d%d: %3d%%" % ["", walls, int(d), int(100.0 * hear_p(float(gun[1]), float(d), walls))]
		print("NTEST ", row)
	# a crowd of one in six square tiles round the shooter: how many are called by one shot (the cap, the chance and the radius together)
	for gun in [["shotgun", 16.0], ["service", 14.0], ["smg", 13.0]]:
		var sum := 0.0
		var T := 300
		for t in T:
			var cand := 0
			for gx in range(-20, 21, 2):
				for gy in range(-20, 21, 2):
					var d := Vector2(gx, gy).length()
					if d < float(gun[1]) and rng.randf() < hear_p(float(gun[1]), d, 0):
						cand += 1
			sum += minf(cand, float(_kind("shot").cap))
		print("NTEST ", gun[0], " called per shot (crowd 1 per 4 tiles^2, cap ", _kind("shot").cap, "): ", snappedf(sum / float(T), 0.1))
