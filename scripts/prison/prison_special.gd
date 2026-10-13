## ROUND 12 (prison only): SPECIAL INFECTED. Four dead that are not like the others, each with its own cue so that the player learns it:
##   SCREAMER  pale, tall, jaw open. It stops when it sees a person and screams for 4 seconds (rings on the ground), then calls every dead within 30 tiles to where the person is.
##             Three hit points: shoot it before it ends and nothing is called.
##   BLOATER   swollen, yellow-green. Slow. When it dies it bursts into a poison cloud (8 s; 2 hp a second and a slow walk inside) and, at the base, eats 40 hp of a fence segment near it.
##   HUNTER    lean, hooded, on all fours, fast. Within 10 tiles of a person it runs, crouches half a second, leaps 3 tiles in 0.3 s and PINS them for 3 s (the dead's own bite: the
##             pinned one cannot move; F shoves it off). Killing it frees them.
##   BREACHER  the brute of a night's wave, made worse: at the fence it rams (60 hp of the segment a hit, 40 a second), and a shot staggers it for a blink instead of stopping it.
## They are ordinary `Sim.Zombie`s (spawned as walker or brute, then given a kind name, hit points, speed and size) so the rules, the shooting and the kill count see nothing new; the drawing picks
## their own baked sets by kind name (`RimzFrames.SPECIALS`, tools/make_zombie_anim.py). Numbers: the `specials` block of assets/data/prison_noise.json. Owned by prison_game.gd (`special`).
## Flags: `--special=screamer|bloater|hunter|breacher` puts one 12 tiles in front of Ruth (breacher: at the first attacked fence segment); `--nospecial` turns them off.
extends RefCounted

const PN := preload("res://scripts/prison/prison_noise.gd")
const TAG := {"screamer": Color(0.8, 0.85, 1.0), "bloater": Color(0.75, 0.9, 0.3), "hunter": Color(1.0, 0.4, 0.35), "breacher": Color(1.0, 0.65, 0.25)}
const LETTER := {"screamer": "S", "bloater": "B", "hunter": "H", "breacher": "R"}

var game
var rng := RandomNumberGenerator.new()
var list: Dictionary = {}    # Zombie -> info
var gas: Array = []    # {pos, t, life, r}
var enabled := true
var stats := {"spawned": 0, "screams": 0, "silenced": 0, "bursts": 0, "pins": 0, "rams": 0}
var _plan: Array = []    # [{t, kind, seg}] for the night in progress
var _old := {}    # person -> position before the step
var _pinned := {}    # person -> hunter info
var _tt := 0.0
var _ts := 0
var _gas_told := false
var _bound = null


func _init(g) -> void:
	game = g
	rng.seed = 4141
	enabled = not g.args.has("nospecial")
	PN.load_cfg()


func sc(kind: String) -> Dictionary:
	return PN.cfg.specials[kind]


# ------------------------------------------------------------------------------- making one --

## One special of `kind` at `at` (state "still" or "wander"). Returns the zombie (null when the sim has none to give).
func make(kind: String, at: Vector2, state := "wander"):
	var sim = game.run.sim
	var base := "brute" if kind == "breacher" else "walker"
	var z = sim.spawn(at.x, at.y, state, base)
	var c: Dictionary = sc(kind)
	z.kind = "brute" if kind == "breacher" else kind
	z.hp = float(c.hp)
	z.speed = float(c.speed)
	z.size = float(c.get("size", 1.4))
	z.limp = false
	z.groan_t = 3.0 + rng.randf() * 5.0
	if kind == "breacher":
		z.claw = 6.0
	list[z] = {"kind": kind, "z": z, "phase": "idle", "t": 0.0, "cool": 0.0, "seen": false, "ram": 0.0, "hp0": float(c.hp), "target": null}
	stats.spawned += 1
	return z


func kind_of(z) -> String:
	return String(list[z].kind) if list.has(z) else ""


func locked(z) -> bool:
	if not list.has(z):
		return false
	return String(list[z].phase) in ["scream", "crouch", "leap", "pin"]


# ------------------------------------------------------------------------------- spawning --

## The night's special infected: none before the first night, then 1, 2 and 3 as the nights go (the table of the data).
func on_attack(n: int, picked: Array) -> void:
	_plan.clear()
	if not enabled:
		return
	var spc: Dictionary = PN.cfg.specials
	var cnt := 0
	if n >= int(spc.first_night):
		for e in spc.per_night:
			if n >= int(e[0]):
				cnt = int(e[1])
	if game.args.has("special") and not String(game.args.special).is_empty() and game.args.special != "1":
		cnt = 1
	if cnt <= 0 or picked.is_empty():
		return
	var mix: Dictionary = spc.mix
	var tot := 0.0
	for k in mix:
		tot += float(mix[k])
	for i in cnt:
		var pick := rng.randf() * tot
		var kind := "screamer"
		for k in mix:
			pick -= float(mix[k])
			if pick <= 0.0:
				kind = String(k)
				break
		if game.args.has("special") and game.args.special != "1":
			kind = String(game.args.special)
		_plan.append({"t": 9.0 + 7.0 * float(i), "kind": kind, "seg": picked[i % picked.size()]})


func _spawn_planned() -> void:
	var sg = game.siege
	for e in _plan:
		if float(sg.t_att) < float(e.t) or e.has("done"):
			continue
		e["done"] = true
		var s: Dictionary = e.seg
		var at: Vector2 = Vector2(s.spot) + Vector2(s.out) * (4.0 + rng.randf() * 3.0) + Vector2(s.along) * rng.randf_range(-5.0, 5.0)
		if s.side == "S":
			at.y = clampf(at.y, 57.0, 68.0)
		at = sg._free_near(at)
		var z = make(String(e.kind), at, "wander")
		if z == null:
			continue
		sg.wave.append({"z": z, "seg": s, "spot": sg._spot(s, 3.0)})
		game.run.sim.field._investigate(z, sg.wave[sg.wave.size() - 1].spot)
		z.wander_t = 90.0
		if game.args.has("log"):
			print("SPECIAL ", e.kind, " at ", at, " for ", s.name)
	_plan = _plan.filter(func(e): return not e.has("done"))


## A raid begins (from day 3): maybe a screamer by a big place, a hunter by a doorway, a bloater by a car, none within 25 tiles of the drop.
func on_raid_begin() -> void:
	list.clear()
	gas.clear()
	_plan.clear()
	if not enabled:
		return
	var day := int(game.econ.day) if game.econ != null else 1
	var spc: Dictionary = PN.cfg.specials
	if day < int(spc.raid_min_day) and not game.args.has("rspecial"):
		return
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var places: Array = []
	for pl in game.loot.places:
		if Vector2(pl.pos).distance_to(me) > 25.0:
			places.append(pl)
	var placed := 0
	for kind in ["screamer", "hunter", "bloater"]:
		if placed >= 2 or places.is_empty():
			break
		if rng.randf() >= float(spc.raid[kind]) and not game.args.has("rspecial"):
			continue
		var at: Vector2
		if kind == "bloater" and not game.noise.cars.is_empty():
			var cs: Array = game.noise.cars.filter(func(c): return Vector2(c.pos).distance_to(me) > 25.0)
			if cs.is_empty():
				continue
			at = Vector2(cs[rng.randi() % cs.size()].pos) + Vector2(1.8, 1.4)
		else:
			var pl: Dictionary = places[rng.randi() % places.size()]
			at = Vector2(pl.door) + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(1.0, 3.0)) if kind == "hunter" else Vector2(pl.pos) + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(2.0, 5.0))
		at = game.noise._free(at)
		make(kind, at, "still")
		placed += 1


# ------------------------------------------------------------------------------- the step --

func _persons() -> Array:
	var out: Array = []
	for p in game.run.sim.people:
		if not p.dead and not p.downed and p.away == null:
			out.append(p)
	return out


func pre() -> void:
	if game.run == null:
		return
	_old.clear()
	for p in game.run.sim.people:
		_old[p] = Vector2(p.x, p.y)


func post(dt: float) -> void:
	if game.run == null or not enabled:
		return
	var sim = game.run.sim
	var persons := _persons()
	for z in list.keys():
		var info: Dictionary = list[z]
		var st: String = z.state
		var dead: bool = st == "dying" or st == "dead" or z.remove or not sim.zombies.has(z)
		if dead:
			_died(z, info)
			list.erase(z)
			continue
		info.cool = maxf(0.0, float(info.cool) - dt)
		match String(info.kind):
			"screamer":
				_screamer(z, info, dt, persons)
			"hunter":
				_hunter(z, info, dt, persons)
			"breacher":
				_breacher(z, info, dt)
		if not bool(info.seen):
			var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
			if Vector2(z.x, z.y).distance_to(me) < 20.0:
				info.seen = true
				game.noise.toast_first(String(info.kind))
	_gas(dt, persons)
	_holds()


## Pinned people do not move; the ones in a cloud walk slower. (Positions are put back after the rules' step.)
func _holds() -> void:
	for p in _pinned.keys():
		var hi: Dictionary = _pinned[p]
		if p.dead or not list.has(hi.z):
			_pinned.erase(p)
			continue
		if _old.has(p):
			p.x = _old[p].x
			p.y = _old[p].y
			p.moving = false


# ------------------------------------------------------------------------------- the screamer --

func _screamer(z, info: Dictionary, dt: float, persons: Array) -> void:
	var c: Dictionary = sc("screamer")
	var ph := String(info.phase)
	if ph == "idle":
		if float(info.cool) > 0.0:
			return
		var zp := Vector2(z.x, z.y)
		var best = null
		var bd := float(c.see_r)
		for p in persons:
			var d := zp.distance_to(Vector2(p.x, p.y))
			if d < bd and game.run.sim.clear_shot(zp, Vector2(p.x, p.y), 0.15):
				bd = d
				best = p
		if best != null:
			info.phase = "scream"
			info.t = 0.0
			info.target = Vector2(best.x, best.y)
			info.prey = best
			z.state = "still"
			z.path = []
			z.moving = false
			z.groan_t = 99.0
			game.noise.sting("screamer", zp)
			game.noise.toast_first("screamer")
			stats.screams += 1
	elif ph == "scream":
		z.state = "still"
		z.moving = false
		info.t = float(info.t) + dt
		z.pause = 1.0    # (it stands: the dead's walk does not drag it)
		if float(info.t) >= float(c.scream_s):
			var tgt: Vector2 = info.target
			if info.has("prey") and info.prey != null and not info.prey.dead:
				tgt = Vector2(info.prey.x, info.prey.y)
			var n := PN.emit(Vector2(z.x, z.y), float(c.loud), "scream", tgt)
			if n > 0:
				game.board.toast("The scream called %d of the dead." % n, Color(1.0, 0.5, 0.4))
			info.phase = "done"
			info.t = 0.0
			info.big = 1.4    # (the last ring: the whole radius)
			z.pause = 0.0
			z.groan_t = 3.0
			if info.get("prey") != null and not info.prey.dead:
				game.run.sim.start_chase(z, info.prey)
	elif ph == "done":
		info.t = float(info.t) + dt
		if float(info.t) > 6.0:
			info.phase = "idle"
			info.cool = 12.0


# ------------------------------------------------------------------------------- the bloater --

func _died(z, info: Dictionary) -> void:
	var kind := String(info.kind)
	if kind == "screamer" and String(info.phase) == "scream":
		stats.silenced += 1
		game.board.toast("Silenced in time.", Color(0.6, 1.0, 0.7))
	elif kind == "hunter":
		for p in _pinned.keys():
			if _pinned[p].z == z:
				_pinned.erase(p)
	elif kind == "bloater" and not bool(info.get("burst", false)):
		info["burst"] = true
		_burst(Vector2(z.x, z.y))


func _burst(at: Vector2) -> void:
	var c: Dictionary = sc("bloater")
	gas.append({"pos": at, "t": 0.0, "life": float(c.gas_s), "r": float(c.gas_r)})
	stats.bursts += 1
	game.noise.sting("bloater_burst", at)
	game.noise.emit(at, 9.0, "glass")
	game.fx.hit_material(at.x, at.y, "metal")
	if game.mode == "base" and game.siege != null:
		for s in game.siege.segs:
			if float(s.hp) > 0.0 and game.siege._dist_to_span(at, s) < float(c.acid_r):
				game.siege._damage(s, float(c.acid))
				s["acid"] = 20.0
				game._say("Acid eats the %s." % String(s.name), 3.0)
				break


func _gas(dt: float, persons: Array) -> void:
	var c: Dictionary = sc("bloater")
	for g in gas:
		g.t = float(g.t) + dt
		for p in persons:
			var pp := Vector2(p.x, p.y)
			if pp.distance_to(g.pos) < float(g.r):
				_hurt(p, float(c.gas_dps) * dt)
				if _old.has(p) and not _pinned.has(p):
					var back: Vector2 = _old[p]
					p.x = lerpf(back.x, p.x, float(c.gas_slow))
					p.y = lerpf(back.y, p.y, float(c.gas_slow))
				if p == game.run.avatar_p and not _gas_told:
					_gas_told = true
					game._say("Poison gas! Get out of the cloud.", 3.0)
	gas = gas.filter(func(g): return float(g.t) < float(g.life))
	if game.siege != null:
		for s in game.siege.segs:
			if s.has("acid"):
				s.acid = float(s.acid) - dt
				if float(s.acid) <= 0.0:
					s.erase("acid")


## Damage to a person: a companion or an ally keeps its own hit points (the squad and the crew copy them to the person every step).
func _hurt(p, dmg: float) -> void:
	for grp in [game.squad.members if game.squad != null else [], game.crew.members if game.crew != null else []]:
		for m in grp:
			if m.get("p") == p and m.has("hp"):
				m.hp = float(m.hp) - dmg
				return
	p.hp = maxf(0.0, float(p.hp) - dmg)
	if p.hp <= 0.0 and not p.downed:
		game.run.sim.medical.on_downed(p, "bite")


# ------------------------------------------------------------------------------- the hunter --

func _hunter(z, info: Dictionary, dt: float, persons: Array) -> void:
	var c: Dictionary = sc("hunter")
	var ph := String(info.phase)
	var zp := Vector2(z.x, z.y)
	if ph == "idle":
		if float(info.cool) > 0.0:
			return
		var best = null
		var bd := float(c.spot_r)
		for p in persons:
			if _pinned.has(p):
				continue
			var d := zp.distance_to(Vector2(p.x, p.y))
			if d < bd and game.run.sim.clear_shot(zp, Vector2(p.x, p.y), 0.15):
				bd = d
				best = p
		if best == null:
			return
		info.prey = best
		if bd > float(c.leap_r):
			if z.state != "chase" or String(z.hunt_id) != String(best.id):
				game.run.sim.start_chase(z, best)
				if not bool(info.get("sting", false)):
					info["sting"] = true
					game.noise.sting("hunter", zp)
		else:
			info.phase = "crouch"
			info.t = 0.0
			z.state = "still"
			z.path = []
			z.moving = false
			z.press = 0.0
			z.attack_t = 0.2
	elif ph == "crouch":
		var p = info.prey
		if p == null or p.dead or p.downed:
			info.phase = "idle"
			return
		z.state = "still"
		z.moving = false
		z.head = (Vector2(p.x, p.y) - zp).angle()
		z.want = z.head
		info.t = float(info.t) + dt
		if float(info.t) >= float(c.crouch_s):
			info.phase = "leap"
			info.t = 0.0
			info.from = zp
			var to := Vector2(p.x, p.y)
			info.to = to - (to - zp).normalized() * 0.55
			game.noise.sting("hunter_leap", zp)
	elif ph == "leap":
		info.t = float(info.t) + dt
		var u := clampf(float(info.t) / float(c.leap_s), 0.0, 1.0)
		var q: Vector2 = (info.from as Vector2).lerp(info.to, u)
		z.x = q.x
		z.y = q.y
		z.moving = true
		z.walk_phase += dt * 14.0
		if u >= 1.0:
			var p = info.prey
			if p != null and not p.dead and not p.downed and Vector2(p.x, p.y).distance_to(zp) < 1.4:
				info.phase = "pin"
				info.t = 0.0
				_pinned[p] = info
				stats.pins += 1
				z.state = "chase"
				z.hunt_id = String(p.id)
				z.attack_t = 0.3
				if p == game.run.avatar_p:
					game._say("PINNED! Press F to shove it off, or kill it.", 3.0)
			else:
				info.phase = "idle"
				info.cool = float(c.cool_s)
				z.state = "wander"
	elif ph == "pin":
		var p = info.prey
		info.t = float(info.t) + dt
		if p == null or p.dead or p.downed or float(info.t) >= float(c.pin_s):
			release(info)
			return
		z.x = p.x + 0.5
		z.y = p.y
		z.state = "chase"
		z.hunt_id = String(p.id)


func release(info: Dictionary) -> void:
	var c: Dictionary = sc("hunter")
	var p = info.get("prey")
	if p != null:
		_pinned.erase(p)
	info.phase = "idle"
	info.cool = float(c.cool_s)
	var z = info.z
	z.state = "chase"
	if p != null:
		z.x += 1.4 * signf(z.x - p.x if absf(z.x - p.x) > 0.01 else 1.0)
	z.stagger = 1.2


## F while pinned: the hunter is shoved off. True when it was used.
func free_pin() -> bool:
	var p = game.run.avatar_p
	if not _pinned.has(p):
		return false
	var info: Dictionary = _pinned[p]
	var z = info.z
	var away := (Vector2(z.x, z.y) - Vector2(p.x, p.y)).normalized()
	z.x += away.x * float(sc("hunter").free_dist)
	z.y += away.y * float(sc("hunter").free_dist)
	release(info)
	z.stagger = 1.5
	game._say("You shove it off.", 2.0)
	return true


# ------------------------------------------------------------------------------- the breacher --

func _breacher(z, info: Dictionary, dt: float) -> void:
	var c: Dictionary = sc("breacher")
	if z.stagger > float(c.stagger):
		z.stagger = float(c.stagger)    # (a shot makes it stagger for a blink: it does not stop)
	if game.siege == null:
		return
	for w in game.siege.wave:
		if w.z != z:
			continue
		var s: Dictionary = w.seg
		if z.state == "still" and z.press > 0.0 and float(s.hp) > 0.0:
			info.ram = float(info.ram) - dt
			if float(info.ram) <= 0.0:
				info.ram = float(c.ram_every)
				game.siege._damage(s, float(c.ram_dps) * float(c.ram_every))
				s.hit = 0.8
				z.attack_t = 0.05
				stats.rams += 1
				game.sound.play("crash", 0.7)
				game.noise.emit(Vector2(z.x, z.y), 10.0, "glass")
				game.fx.hit_material(z.x, z.y, "metal")
				if not bool(info.get("sting", false)):
					info["sting"] = true
					game.noise.sting("breacher", Vector2(z.x, z.y))
		return


# ------------------------------------------------------------------------------- frame --

func update(dt: float) -> void:
	if game.run == null or not enabled:
		return
	if game.mode == "base" and game.siege != null and game.siege.attacking:
		_spawn_planned()
	if game.args.has("special"):
		_test(dt)


func paint(c: CanvasItem) -> void:
	var T: float = game.TILE
	var font := ThemeDB.fallback_font
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	for g in gas:
		var u := float(g.t) / float(g.life)
		var a := (1.0 - pow(u, 3.0)) * 0.5
		for i in 9:
			var ang: float = float(i) * 2.4 + float(game.clock) * 0.4
			var off: Vector2 = Vector2.from_angle(ang) * float(g.r) * 0.45 * (0.6 + 0.4 * sin(game.clock * 0.9 + float(i)))
			c.draw_circle((Vector2(g.pos) + off) * T, float(g.r) * T * (0.42 + 0.06 * sin(game.clock + float(i))), Color(0.55, 0.85, 0.15, a * 0.28))
		c.draw_arc(Vector2(g.pos) * T, float(g.r) * T, 0.0, TAU, 36, Color(0.7, 1.0, 0.3, a * 0.5), 2.0)
	if game.siege != null:
		for s in game.siege.segs:
			if s.has("acid"):
				c.draw_line(Vector2(s.first) * T, Vector2(s.last) * T, Color(0.5, 0.9, 0.1, 0.35 + 0.15 * sin(game.clock * 3.0)), 7.0)
	for z in list:
		var info: Dictionary = list[z]
		var kind := String(info.kind)
		var zp := Vector2(z.x, z.y)
		if zp.distance_to(me) < 26.0:
			c.draw_string(font, zp * T + Vector2(-60, -1.55 * T), kind.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, TAG[kind])
		if kind == "screamer" and String(info.phase) == "scream":
			for k in 3:
				var u := fposmod(float(info.t) * 1.2 + float(k) / 3.0, 1.0)
				c.draw_arc(zp * T + Vector2(0, -0.9 * T), (0.6 + 5.0 * u) * T, 0.0, TAU, 40, Color(1.0, 0.9, 0.95, 0.7 * (1.0 - u)), 3.5)
			var t_left := float(sc("screamer").scream_s) - float(info.t)
			c.draw_string(font, zp * T + Vector2(-60, -2.0 * T), "%.1f" % maxf(0.0, t_left), HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1, 0.8, 0.8))
		elif kind == "screamer" and info.has("big") and float(info.big) > 0.0:
			info.big = float(info.big) - 0.016
			var u2 := 1.0 - float(info.big) / 1.4
			c.draw_arc(zp * T, 30.0 * T * u2, 0.0, TAU, 72, Color(1.0, 0.85, 0.9, 0.6 * (1.0 - u2)), 5.0)
		elif kind == "hunter" and String(info.phase) == "crouch":
			c.draw_arc(zp * T, 0.9 * T, 0.0, TAU, 20, Color(1.0, 0.2, 0.2, 0.8), 3.0)
		elif kind == "hunter" and String(info.phase) == "pin":
			c.draw_string(font, zp * T + Vector2(-80, -2.2 * T), "PINNED  F: shove", HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color(1, 0.5, 0.4))


func mini(bars: CanvasItem, o: Vector2, scl: float) -> void:
	var font := ThemeDB.fallback_font
	for z in list:
		var kind := String(list[z].kind)
		var q: Vector2 = o + Vector2(z.x, z.y) * scl
		bars.draw_circle(q, 4.0, Color(0, 0, 0, 0.7))
		bars.draw_circle(q, 3.0, TAG[kind])
		bars.draw_string(font, q + Vector2(-3.5, 3.6), String(LETTER[kind]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0))
	for g in gas:
		bars.draw_circle(o + Vector2(g.pos) * scl, float(g.r) * scl, Color(0.6, 0.9, 0.2, 0.4))


# ------------------------------------------------------------------------------- the check --

## --special=KIND: one 12 tiles in front of Ruth (in a siege: the breacher at the first attacked segment). Prints SPTEST lines.
func _test(dt: float) -> void:
	_tt += dt
	var kind := String(game.args.special)
	if not TAG.has(kind):
		return
	var p = game.run.avatar_p
	var me := Vector2(p.x, p.y)
	game.run.invulnerable = true
	if _ts == 0 and _tt > 0.6 and (game.mode == "raid" or kind != "breacher"):
		_ts = 1
		var ahead := Vector2.from_angle(float(p.aim) if absf(float(p.aim)) > 0.001 else 0.0)
		var at: Vector2 = game.noise._free(me + ahead * 12.0)
		var z = make(kind, at, "still" if kind == "screamer" else "wander")
		game.zoom_px = 26.0
		game.play_zoom = 26.0
		print("SPTEST spawned ", kind, " at ", at.snapped(Vector2(0.1, 0.1)), " me ", me.snapped(Vector2(0.1, 0.1)))
		if kind in ["hunter", "bloater"]:
			game.run.sim.start_chase(z, p)
			z.speed = float(sc(kind).speed)
	for z in list:
		var info: Dictionary = list[z]
		if int(_tt * 10.0) % 10 == 0 and int(_tt * 60.0) % 6 == 0:
			print("SPTEST t=", snappedf(_tt, 0.1), " ", info.kind, " phase=", info.phase, " dist=", snappedf(Vector2(z.x, z.y).distance_to(me), 0.1), " hp=", z.hp, " state=", z.state, " gas=", gas.size(), " pinned=", _pinned.size(), " ", stats)
		if kind == "bloater" and Vector2(z.x, z.y).distance_to(me) < 5.0 and z.hp > 0.0 and z.state != "dying":
			game.run.sim._hurt_zombie(z, 99.0, 0.0, null)
	if kind == "breacher" and game.mode == "base" and _ts == 0 and game.siege.attacking and game.siege.t_att > 2.0:
		_ts = 1
		var s: Dictionary = game.siege.wave[0].seg if not game.siege.wave.is_empty() else game.siege.segs[0]
		var at2: Vector2 = Vector2(s.spot) + Vector2(s.out) * 5.0
		var z2 = make("breacher", game.siege._free_near(at2), "wander")
		game.siege.wave.append({"z": z2, "seg": s, "spot": game.siege._spot(s, 1.0)})
		game.run.sim.field._investigate(z2, game.siege.wave[game.siege.wave.size() - 1].spot)
		z2.wander_t = 90.0
		print("SPTEST breacher sent at ", s.name, " hp ", s.hp)
