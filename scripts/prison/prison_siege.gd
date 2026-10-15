## EXPERIMENT (prison siege): base attacks. The perimeter is cut into 14 fence segments plus the gate, each with hit points and a drawn damage state (cracked, sagging, down). Each night a
## bell rings and a wave of the dead is sent at 1 to 3 segments (more of them, and more segments, every night). The dead that stand at a segment tear at it; the tower guards shoot (each shot
## costs ammo from the stores); a segment at 0 hp becomes a gap, the dead walk through it toward the nearest person, and a crew member that one of them reaches is bitten ("X is down") and lost
## after a few seconds unless that dead one is killed first. The player (hold E at a damaged segment, 1 scrap per HP_PER_SCRAP hp) and Tomas the fence crew repair. A card sums up each night.
## Pattern: plain data (an array of segment dictionaries, an array of wave records) and one update() with a few phases, owned by prison_game.gd. A state machine node tree and an event bus were
## rejected: a segment has only a number and a state word that is a function of that number, and the game has no other listener.
## Runs only when game.phase == "managed" and the game is in the base (not a raid).
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const Base := preload("res://scripts/prison/prison_base.gd")

const TILE := GD.TILE
const SEG_HP := 120.0
const GATE_HP := 160.0
const PUSH_DPS := 0.5    # hp a second that one dead one standing at its spot takes off its segment
const AMBIENT_DPS := 0.012    # the pen's crowd leaning on the fence by day
const REPAIR_HPS := 8.0    # the player's hand
const TOMAS_HPS := 3.0
const HP_PER_SCRAP := 8.0
const GUARD_SHOT_COST := 0.25    # rounds out of the stores for one guard shot
const NIGHT_H := 21.0    # hour of the first attack (the bell is 20:30)
const DAWN_H := 6.5
const SEC_PER_HOUR := 15.0    # DAY_MIN_PER_SEC 4.0 in prison_game.gd
const GUARD_COVER := 10.0
const BITE_R := 0.9
const DOWN_SECS := 6.0

var game
var segs: Array = []    # see _add_seg
var abs_h := 8.0    # hours since the start, unwrapped
var _last_tod := 8.0
var nights_started := 0
var pending := 0
var attacking := false
var night := 0
var forced := false
var t_att := 0.0
var wave: Array = []    # {z, seg, spot, boost}
var _batches := 0
var _batch_t := 0.0
var _plan: Array = []    # [{seg, n}] per night, spawned in batches
var _bell_n := 0
var _bell_t := 0.0
var _clear_t := 0.0
var stats := {}
var _last_ammo := -1.0
var _fl := 0
var _spot_t := 0.0
var _rep_acc := 0.0
var guards_off := false
var _report_done := false
var _banner: Label
var _banner_t := 0.0
var _card: PanelContainer
var _card_label: Label
var _card_t := 0.0
var _hit_fx_t := 0.0
var _logged := -1
var _runner_p := 0.0    # ARC hook: the share of runners of this night (prison_arc.gd `wave_plan`)


func _init(g) -> void:
	game = g
	guards_off = g.args.has("noguards")
	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.82, 0.55))
	_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_banner.add_theme_constant_override("shadow_offset_x", 2)
	_banner.add_theme_constant_override("shadow_offset_y", 2)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	g.hud.add_child(_banner)
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.06, 0.92)
	sb.border_color = Color(0.85, 0.7, 0.4)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	_card.add_theme_stylebox_override("panel", sb)
	_card_label = Label.new()
	_card_label.add_theme_font_size_override("font_size", 20)
	_card_label.add_theme_color_override("font_color", Color(1, 1, 0.88))
	_card.add_child(_card_label)
	_card.visible = false
	g.hud.add_child(_card)
	_build_segments()


## The segments: [x0, x1) spans of the four sides, the gate cut out of the south side. Corners belong to the north and south sides.
func _build_segments() -> void:
	var F: Rect2i = Base.FENCE
	var xs_n := [6, 27, 48, 69, 90]
	for i in 4:
		_add_seg("north fence %d" % (i + 1), "N", _span(xs_n[i], xs_n[i + 1], F.position.y, true))
	var xs_s := [[6, 26], [26, 46], [50, 70], [70, 90]]
	for i in 4:
		_add_seg("south fence %d" % (i + 1), "S", _span(xs_s[i][0], xs_s[i][1], F.end.y - 1, true))
	_add_seg("the gate", "S", _span(Base.GATE_X, Base.GATE_X + Base.GATE_W, F.end.y - 1, true), true)
	var ys := [5, 22, 39, 55]
	for i in 3:
		_add_seg("west fence %d" % (i + 1), "W", _span(ys[i], ys[i + 1], F.position.x, false))
		_add_seg("east fence %d" % (i + 1), "E", _span(ys[i], ys[i + 1], F.end.x - 1, false))


func _span(a: int, b: int, fixed: int, horizontal: bool) -> Array:
	var out: Array = []
	for k in range(a, b):
		out.append(Vector2i(k, fixed) if horizontal else Vector2i(fixed, k))
	return out


func _add_seg(nm: String, side: String, tiles: Array, is_gate := false) -> void:
	var first: Vector2 = Vector2(tiles[0]) + Vector2(0.5, 0.5)
	var last: Vector2 = Vector2(tiles[tiles.size() - 1]) + Vector2(0.5, 0.5)
	var out_v := {"N": Vector2(0, -1), "S": Vector2(0, 1), "W": Vector2(-1, 0), "E": Vector2(1, 0)}[side] as Vector2
	var along := (last - first).normalized() if tiles.size() > 1 else Vector2(1, 0)
	var center := (first + last) / 2.0
	var idxs: Array = []
	for t in tiles:
		idxs.append(int(t.y) * Base.W + int(t.x))
	var gap: Array = idxs
	if not is_gate and idxs.size() > 5:
		var m := idxs.size() / 2
		gap = idxs.slice(m - 2, m + 3)
	var hp := GATE_HP if is_gate else SEG_HP
	segs.append({"name": nm, "side": side, "tiles": idxs, "gap": gap, "hp": hp, "max": hp, "first": first, "last": last, "along": along, "out": out_v, "center": center,
		"spot": center + out_v * 1.3, "fix": center - out_v * 1.6, "gate": is_gate, "push": 0, "hit": 0.0, "open": false, "attacked": false})


## ECON hook: the fence tier sets every segment's max hp (a built tier adds the difference as hp); `patch` mends every segment to full (fence tier 1).
func apply_fence(mult: float, patch: bool) -> void:
	for s in segs:
		var base_hp := GATE_HP if s.gate else SEG_HP
		var nm: float = base_hp * mult
		s.hp = minf(nm, float(s.hp) + maxf(0.0, nm - float(s.max)))
		s.max = nm
		if patch and float(s.hp) < nm:
			_mend(s, nm - float(s.hp))


## Called by prison_game.gd each time the base is built (after a raid too): the fence is solid again in the new world, a segment that fell stays a gap.
func setup() -> void:
	wave.clear()
	_last_ammo = -1.0
	var run = game.run
	run.sim.stock = game.stores    # Ruth's rounds and the guards' rounds are the same stock
	for s in segs:
		s.open = false
		s.push = 0
		if float(s.hp) <= 0.0:
			_set_gap(s, true)
	if args_siege() > 0 and not _report_done and nights_started == 0 and not attacking:
		pending = args_siege()
		forced = true


## The tower guards at their posts (the old 17-person start counts as a full crew).
func armed_count() -> int:
	if game.crew_full():
		return int(game.Bal.d().siege.ref_armed)
	var armed := 0
	for m in game.crew.members:
		if m.def.has("stand") and not m.has("down"):
			armed += 1
	return armed


## How much of the night's dead are sent: armed guards over ref_armed, between floor and 1.
func guard_factor(armed: int) -> float:
	var sb: Dictionary = game.Bal.d().siege
	return clampf(float(armed) / float(sb.ref_armed), float(sb.floor), 1.0)


func args_siege() -> int:
	return int(game.args.get("siege", "0"))


func active() -> bool:
	return game.phase == "managed" and game.mode == "base" and game.run != null and not game.busy


# ------------------------------------------------------------------------- queries --

func state_of(s: Dictionary) -> String:
	var f := float(s.hp) / float(s.max)
	if float(s.hp) <= 0.0:
		return "down"
	if f < 0.33:
		return "sagging"
	if f < 0.66:
		return "cracked"
	return "ok"


func can_fire() -> bool:
	return game.phase == "managed" and game.mode == "base"


func guard_ok(m: Dictionary) -> bool:
	return not guards_off and not m.has("down") and float(game.stores.ammo) >= GUARD_SHOT_COST


## Where a guard shoots: the strip of ground 5 tiles outside the fence and everything inside it (the dead that got in).
func in_guard_zone(z) -> bool:
	var F: Rect2i = Base.FENCE
	var dx := maxf(maxf(float(F.position.x) - z.x, z.x - float(F.end.x)), 0.0)
	var dy := maxf(maxf(float(F.position.y) - z.y, z.y - float(F.end.y)), 0.0)
	return Vector2(dx, dy).length() <= (5.0 if attacking else 2.2)    # by day only the ones leaning on the fence are worth a round


func guard_shot(_g) -> void:
	game.stores.ammo = maxf(0.0, float(game.stores.ammo) - (GUARD_SHOT_COST if attacking else GUARD_SHOT_COST * 0.2))
	stats["shots"] = int(stats.get("shots", 0)) + 1


func in_wave(z) -> bool:
	for w in wave:
		if w.z == z:
			return true
	return false


func _alive(z) -> bool:
	return z.state != "dying" and z.state != "dead" and not z.remove


func _inside(z) -> bool:
	return z.x > 6.0 and z.x < 90.0 and z.y > 4.0 and z.y < 56.0


func _covered(s: Dictionary) -> bool:
	for m in game.crew.members:
		if m.def.has("stand") and not m.has("down") and Vector2(m.p.x, m.p.y).distance_to(s.spot) < GUARD_COVER:
			return true
	return false


func weakest() -> Dictionary:
	var best: Dictionary = segs[0]
	for s in segs:
		if float(s.hp) / float(s.max) < float(best.hp) / float(best.max):
			best = s
	return best


func hud() -> String:
	if not active_phase():
		return ""
	var w := weakest()
	var line := "Fence sound" if float(w.hp) >= float(w.max) * 0.97 else "Fence weakest: %s %d%% (%s)" % [String(w.name), int(100.0 * float(w.hp) / float(w.max)), state_of(w)]
	if attacking:
		line += "  ATTACK night %d: %d of the dead still at the walls" % [night, _alive_wave()]
	else:
		var secs := maxf(0.0, (NIGHT_H + 24.0 * float(nights_started) - abs_h) * SEC_PER_HOUR / float(game.speed))
		line += "  Next attack: night %d in %d:%02d" % [nights_started + 1, int(secs) / 60, int(secs) % 60]
	return line


func active_phase() -> bool:
	return game.phase == "managed" and game.mode == "base"


func _alive_wave() -> int:
	var n := 0
	for w in wave:
		if _alive(w.z):
			n += 1
	return n


# --------------------------------------------------------------------------- update --

func update(dt: float) -> void:
	# the clock runs in a raid too, so a night that falls while she is out is not lost
	var d := fposmod(game.tod - _last_tod, 24.0)
	_last_tod = game.tod
	if d < 12.0:
		abs_h += d
	_ui(dt)
	if game.args.has("siegelog") and int(game.clock) % 5 == 0 and int(game.clock) != _logged:
		_logged = int(game.clock)
		print("siege log clock=%d frames=%d active=%s attacking=%s t_att=%.1f scrap=%.1f ammo=%.1f wave=%d hp=%s" % [_logged, game.frames, active(), attacking, t_att, float(game.stores.scrap), float(game.stores.ammo), _alive_wave(), segs.map(func(s): return int(s.hp))])
	if not active():
		return
	var run = game.run
	if not attacking and pending == 0 and abs_h >= NIGHT_H + 24.0 * float(nights_started):
		pending = nights_started + 1
	if pending > 0 and not attacking:
		var n := pending
		pending = 0
		if forced or abs_h < 24.0 * float(n - 1) + 24.0 + DAWN_H:
			_start_attack(n)
		else:
			_resolve_missed(n)
	var ammo := float(game.stores.ammo)
	if _last_ammo >= 0.0 and ammo < _last_ammo:
		stats["ammo"] = float(stats.get("ammo", 0.0)) + _last_ammo - ammo
	_last_ammo = ammo
	if attacking:
		t_att += dt
		_spawn_batches(dt)
		_bells(dt)
	_wave_work(dt)
	_ambient(dt)
	_flood(dt)
	_bites(dt)
	_repair(dt)
	_tomas(dt)
	for s in segs:
		s.hit = maxf(0.0, float(s.hit) - dt)
	if attacking:
		var over := false
		if forced:
			over = (t_att > 8.0 and _alive_wave() == 0 and _batches >= 3 and _clear_t > 6.0) or t_att > float(game.args.get("siegefor", "150"))
			_clear_t = _clear_t + dt if (_alive_wave() == 0 and _batches >= 3) else 0.0
		else:
			over = abs_h >= 24.0 * float(night - 1) + 24.0 + DAWN_H
		if over:
			_end_attack()
	if run.sim.quiet and _any_open():
		run.sim.quiet = false    # with a gap in the fence the dead inside see her


func _any_open() -> bool:
	for s in segs:
		if s.open:
			return true
	return false


# ---------------------------------------------------------------------------- attack --

func _start_attack(n: int) -> void:
	night = n
	nights_started = maxi(nights_started, n)
	attacking = true
	t_att = 0.0
	_batches = 0
	_batch_t = 0.0
	_clear_t = 0.0
	_bell_n = 3
	_bell_t = 0.0
	wave.clear()
	var hp0 := 0.0
	for s in segs:
		hp0 += float(s.hp)
		s.attacked = false
	stats = {"hp0": hp0, "killed": 0, "ammo": 0.0, "shots": 0, "lost": [], "crew": [], "n": 0}
	# which segments: night 1 only where the towers reach; later nights anywhere (and from night 3 at least one the guards cannot cover)
	var plan: Dictionary = game.arc.wave_plan(n)    # ARC hook: the night table by day (prison_story.json `nights`)
	_runner_p = float(plan.runner)
	var k := int(plan.segs)
	var pool: Array = []
	for s in segs:
		if float(s.hp) > 0.0:
			pool.append(s)
	pool.shuffle()
	if game.args.has("siegeseg"):    # test flag: segment indexes, e.g. --siegeseg=5,6
		var want := String(game.args.siegeseg).split(",")
		pool = pool.filter(func(q): return want.has(str(segs.find(q))))
	var picked: Array = []
	for s in pool:
		if picked.size() >= k:
			break
		if n <= 2 and not _covered(s) and not game.args.has("siegeseg"):
			continue
		picked.append(s)
	if n >= 3 and not picked.is_empty():
		var any_open := false
		for s in picked:
			if not _covered(s):
				any_open = true
		if not any_open:
			for s in pool:
				if not _covered(s):
					picked[picked.size() - 1] = s
					break
	if picked.is_empty() and not pool.is_empty():
		picked.append(pool[0])
	_plan.clear()
	var per := maxi(2, roundi(float(plan.per) * float(game.Bal.dm("wave")) * guard_factor(armed_count())))    # (fix round 3: the wave follows the guns on the towers)
	var names: Array = []
	for s in picked:
		s.attacked = true
		_plan.append({"seg": s, "n": per})
		stats.n = int(stats.n) + per
		var side := "gate" if s.gate else String(s.name).trim_suffix(" 1").trim_suffix(" 2").trim_suffix(" 3").trim_suffix(" 4")
		if not names.has(side):
			names.append(side)
	var txt := "Night %d: the %s" % [n, " and the ".join(names)]
	if String(plan.name) != "":
		txt = "Night %d, %s: the %s" % [n, String(plan.name), " and the ".join(names)]
	stats["where"] = txt
	print("SIEGE START ", txt, " segs=", picked.map(func(q): return q.name), " sent=", stats.n)
	game.noise.on_attack(n, picked)    # NOISE hook: a horde on some nights
	game.special.on_attack(n, picked)    # SPECIAL hook: the night's special infected
	_show_banner(txt, 6.0)
	game._say("The bell is ringing. They are coming.", 5.0)
	for m in game.crew.members:
		if m.def.has("stand"):
			m.say = "Here they come!"
	game.alarm_t = 20.0    # (the guards fire fast for 20 s; in the base Ruth is untouchable anyway, so that is her safe time)
	if game.back_t > 0.0:
		if game.args.has("log"):
			print("SIEGE back-card shown, alarm ", game.alarm_t)
		game._card("Back in the middle of the attack", "Night %d has begun while you were out. The guards are firing: join the wall." % n, 5.0)


## A night that was over before she got home (a raid that came back after dawn): the guards fought it alone. A small model with the arc lab's night numbers
## (prison_story.json lab.night): the wave and the horde the guards would have met, their fire against it, the fence taking the rest, a crew roll for each gap. A morning card says so.
func _resolve_missed(n: int) -> void:
	nights_started = maxi(nights_started, n)
	night = n
	var lb: Dictionary = game.arc.cfg.lab.night
	var plan: Dictionary = game.arc.wave_plan(n)
	var armed := armed_count()
	var f := guard_factor(armed)
	var live: Array = segs.filter(func(s): return float(s.hp) > 0.0)
	live.shuffle()
	var k := mini(int(plan.segs), live.size())
	if k == 0:
		return
	var sent: int = maxi(2, roundi(float(plan.per) * f)) * k + int(game.noise.base_horde_size(n, f))
	var fire := float(armed) * float(lb.guard_kills)
	var need := float(sent) * float(lb.ammo_per_kill)
	var have := float(game.stores.ammo)
	if have < need:
		fire *= have / maxf(need, 1.0)
	var used := minf(have, need)
	game.stores.ammo = have - used
	var killed: int = mini(sent, int(fire))
	var leak := float(sent - killed)
	var dmg_each := (leak * float(lb.hp_per_dead) + float(sent) * float(lb.wear)) / float(k)
	var hp0 := 0.0
	for s in segs:
		hp0 += float(s.hp)
	var lost: Array = []
	for s in live.slice(0, k):
		s.hp = maxf(0.0, float(s.hp) - dmg_each)
		if float(s.hp) <= 0.0:
			_set_gap(s, true)
			lost.append(String(s.name))
	var crew_lost: Array = []
	for g in lost.size():
		for c in game.econ.crew():
			if randf() < float(lb.casualty_p) and not crew_lost.has(String(c.name)):
				game.arc.kill(String(c.name), "night")
				crew_lost.append(String(c.name))
	var hp1 := 0.0
	for s in segs:
		hp1 += float(s.hp)
	stats = {"hp0": hp0, "killed": killed, "ammo": used, "shots": 0, "lost": lost, "crew": crew_lost, "n": sent, "where": "Night %d (you were out)" % n}
	var txt := "MORNING.  Night %d came while you were out.\nThe guards held it alone.\n\n" % n
	txt += "Fence lost:   %s\n" % (", ".join(lost) if not lost.is_empty() else "none")
	txt += "Fence damage: %d hp\n" % maxi(0, int(hp0 - hp1))
	txt += "Dead killed:  %d of %d sent\n" % [killed, sent]
	txt += "Ammo used:    %d rounds\n" % int(used)
	txt += "Crew lost:    %s" % (", ".join(crew_lost.map(game.arc.events.label)) if not crew_lost.is_empty() else "nobody")    # (TRAITS, as the night's own card)
	for nm in crew_lost:
		if game.arc.events.bio_of(String(nm)) != "":
			txt += "\n  %s" % game.arc.events.bio_of(String(nm))
	_card_label.text = txt
	_card.visible = true
	_card_t = 16.0
	print("SIEGE MISSED night=%d sent=%d killed=%d ammo=%.1f lost=%s crew_lost=%s hp0=%.0f hp1=%.0f" % [n, sent, killed, used, lost, crew_lost, hp0, hp1])
	game.arc.night_over(n, stats)    # ARC hook


func _bells(dt: float) -> void:
	if _bell_n <= 0:
		return
	_bell_t -= dt
	if _bell_t <= 0.0:
		_bell_t = 1.6
		_bell_n -= 1
		game.sound.play("bell", 0.9, 0.0)
		game.noise.bell()    # NOISE hook


func _spawn_batches(dt: float) -> void:
	if _batches >= 3 or t_att < 3.0:
		return
	_batch_t -= dt
	if _batch_t > 0.0:
		return
	_batch_t = 7.0
	_batches += 1
	var field = game.run.field
	for pl in _plan:
		var s: Dictionary = pl.seg
		var cnt := int(pl.n) / 3 + (int(pl.n) % 3 if _batches == 3 else 0)
		for i in cnt:
			var spot := _spot(s, 0.0)
			var behind := 1.0 + randf() * 5.0 + float(_batches)
			var at: Vector2 = spot + s.out * behind + s.along * randf_range(-7.0, 7.0)
			if s.side == "S":
				at.y = clampf(at.y, 57.0, 68.0)
			at = _free_near(at)
			var kind := "runner" if randf() < _runner_p else "walker"
			var rec: int = field.add_record(at, kind, false)
			var z = field._wake(rec)
			if z == null:
				continue
			z.speed *= 2.0    # a wave is driven: faster than the pen's shufflers
			wave.append({"z": z, "seg": s, "spot": _spot(s, 3.0)})
			field._investigate(z, wave[wave.size() - 1].spot)
			z.wander_t = 90.0


func _spot(s: Dictionary, spread: float) -> Vector2:
	var v: Vector2 = s.spot + s.along * randf_range(-spread, spread)
	var half: float = (Vector2(s.last) - Vector2(s.first)).length() / 2.0
	var off: float = clampf((v - Vector2(s.center)).dot(s.along), -half, half)
	return Vector2(s.center) + Vector2(s.along) * off + Vector2(s.out) * 1.3


func _free_near(at: Vector2) -> Vector2:
	var w = game.world
	var a := Vector2(clampf(at.x, 2.5, float(Base.W) - 2.5), clampf(at.y, 2.5, float(Base.H) - 2.5))
	for k in 12:
		if not w.is_solid(w.solid_z, a.x, a.y):
			return a
		a = at + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		a = Vector2(clampf(a.x, 2.5, float(Base.W) - 2.5), clampf(a.y, 2.5, float(Base.H) - 2.5))
	return Vector2(48.0, 60.0)


## The dead that were sent: walk to their spot, stand there and tear at their segment. Counts the ones that die.
func _wave_work(dt: float) -> void:
	for s in segs:
		s.push = 0
	_spot_t -= dt
	var repath := _spot_t <= 0.0
	if repath:
		_spot_t = 1.2
	for w in wave:
		var z = w.z
		if w.has("done"):
			continue
		if game.special.locked(z):    # SPECIAL hook: a screamer that screams or a hunter that leaps is not sent anywhere
			continue
		if not _alive(z) or not game.run.sim.zombies.has(z):
			w["done"] = true
			stats.killed = int(stats.killed) + 1
			continue
		var s: Dictionary = w.seg
		if float(s.hp) <= 0.0:
			continue    # their way in is open: _flood takes over
		var dist := Vector2(z.x, z.y).distance_to(w.spot)
		if z.state == "chase":
			continue
		if dist < 1.1:
			z.state = "still"    # at the fence: stand and tear
			z.moving = false
			z.press = 1.0    # (ZMOVE: it leans on the wire facing it and reaches through it)
			z.aim = (-Vector2(s.out)).angle()
			s.push = int(s.push) + 1
		elif repath and (z.state == "wander" or z.state == "still"):
			game.run.field._investigate(z, w.spot)
			z.wander_t = 90.0
	for s in segs:
		if int(s.push) > 0 and float(s.hp) > 0.0:
			_damage(s, float(s.push) * PUSH_DPS * dt)
			s.hit = 0.6
			_hit_fx_t -= dt
			if _hit_fx_t <= 0.0 and game.fx != null:
				_hit_fx_t = 0.35
				var c: Vector2 = Vector2(s.center) + Vector2(s.along) * randf_range(-6.0, 6.0)
				game.fx.hit_material(c.x, c.y, "metal")
	# dead that were killed are forgotten after counting
	wave = wave.filter(func(w): return not w.has("done"))


func _ambient(dt: float) -> void:
	for z in game.run.sim.zombies:
		if not _alive(z) or z.y < 55.5 or z.y > 58.0 or z.x < 6.0 or z.x > 90.0:
			continue
		var gx := floori(z.x)
		for s in segs:
			if s.side == "S" and gx >= int(s.tiles[0]) % Base.W and gx <= int(s.tiles[s.tiles.size() - 1]) % Base.W and float(s.hp) > 0.0 and int(s.push) == 0:
				_damage(s, AMBIENT_DPS * dt)
				break


func _damage(s: Dictionary, amount: float) -> void:
	var before := state_of(s)
	s.hp = maxf(0.0, float(s.hp) - amount)
	if float(s.hp) <= 0.0 and not s.open:
		_set_gap(s, true)
		game.sound.play("crash")
		game._say("BREACH: %s is down!" % String(s.name), 6.0)
		_show_banner("BREACH  %s" % String(s.name).to_upper(), 4.0)
		(stats.lost as Array).append(String(s.name))
	elif before != state_of(s) and game.fx != null:
		game.sound.play("crash", 0.5)


func _set_gap(s: Dictionary, open: bool) -> void:
	var sim = game.run.sim
	game.world.set_walkable(s.gap, open)
	for i in s.gap:
		sim.path_z.set_solid(int(i), not open)
		sim.path_p.set_solid(int(i), not open)
	s.open = open


## With a gap open: the dead near it (and all that are inside) walk to the nearest person. The pathfinder is asked a few at a time.
func _flood(dt: float) -> void:
	var gaps: Array = []
	for s in segs:
		if s.open:
			gaps.append(s)
	if gaps.is_empty():
		return
	var targets: Array = []
	for m in game.crew.members:
		if not m.has("down"):
			targets.append(Vector2(m.p.x, m.p.y))
	targets.append(Vector2(game.run.avatar_p.x, game.run.avatar_p.y))
	var zs: Array = game.run.sim.zombies
	var n := zs.size()
	var done := 0
	for k in n:
		_fl = (_fl + 1) % n
		var z = zs[_fl]
		if not _alive(z) or z.state == "chase":
			continue
		var near := _inside(z)
		if not near:
			for s in gaps:
				if Vector2(z.x, z.y).distance_to(s.center) < 14.0:
					near = true
					break
		if not near:
			continue
		if z.state == "still" or z.state == "wander":
			var zp := Vector2(z.x, z.y)
			var best: Vector2 = targets[0]
			for t in targets:
				if zp.distance_to(t) < zp.distance_to(best):
					best = t
			if z.path.is_empty() or z.path_i >= z.path.size() or z.wander_t > 85.0 or z.state == "still":
				game.run.field._investigate(z, best)
				z.wander_t = 80.0
				done += 1
				if done >= 5:
					break


func _bites(dt: float) -> void:
	var zs: Array = game.run.sim.zombies
	var crew = game.crew
	for m in crew.members.duplicate():
		var p = m.p
		if m.has("down"):
			var info: Dictionary = m.down
			info.t = float(info.t) - dt
			p.downed = true
			if not _alive(info.z) or not zs.has(info.z):
				p.downed = false
				m.erase("down")
				m.state = String(m.get("prev", "wait"))
				m.say = "shaken"
				game._say("%s is hurt, but alive." % String(m.def.name), 4.0)
			elif float(info.t) <= 0.0:
				crew.members.erase(m)
				if m.def.has("ex_ally"):
					game.allies_alive.erase(String(m.def.id))    # (else the next base build brings them back)
				game.people.forget(String(m.def.name))    # RAIDS hook: a recruit is not brought back
				game.keep_corpse(m)    # ROUND 11: it falls and lies there (freed with --nohanim)
				if stats.has("crew"):    # (none before the first night: a dead one inside by day)
					(stats.crew as Array).append(String(m.def.name))
				game._say("%s is gone." % String(m.def.name), 6.0)
			continue
		for z in zs:
			if not _alive(z) or not _inside(z):
				continue
			if Vector2(z.x, z.y).distance_to(Vector2(p.x, p.y)) < BITE_R:
				m["down"] = {"t": DOWN_SECS, "z": z}
				m["prev"] = m.state
				if not m.def.has("stand") and m.def.has("route"):    # (allies and kids have no route: they keep their state)
					m.state = "down"    # a guard keeps "post" (the crew code has no route for it)
				p.downed = true
				p.work = ""
				m.say = "is down"
				game.sound.play("bite")
				game._say("%s is down! Kill the one that bit them!" % String(m.def.name), 6.0)
				break


# ---------------------------------------------------------------------------- repair --

func _dist_to_span(pt: Vector2, s: Dictionary) -> float:
	var a: Vector2 = Vector2(s.first) - Vector2(s.along) * 0.5
	var b: Vector2 = Vector2(s.last) + Vector2(s.along) * 0.5
	var ab := b - a
	var t := clampf((pt - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return pt.distance_to(a + ab * t)


func _can_close(s: Dictionary) -> bool:
	for z in game.run.sim.zombies:
		if _alive(z) and Vector2(z.x, z.y).distance_to(s.center) < float(s.gap.size()) * 0.5 + 1.2:
			return false
	return true


func _mend(s: Dictionary, hp: float) -> float:
	var healed := minf(hp, float(s.max) - float(s.hp))
	s.hp = float(s.hp) + healed
	if s.open and float(s.hp) >= float(s.max) * 0.25 and _can_close(s):
		_set_gap(s, false)
	elif s.open and float(s.hp) >= float(s.max) * 0.25:
		s.hp = float(s.max) * 0.25 - 0.01    # the dead stand in the gap: it cannot be shut yet
	return healed


func _repair(dt: float) -> void:
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var best = null
	var bd := 3.2
	for s in segs:
		if float(s.hp) >= float(s.max):
			continue
		var d := _dist_to_span(me, s)
		if d < bd and (me - Vector2(s.center)).dot(s.out) < 0.8:
			bd = d
			best = s
	if best == null:
		_rep_acc = 0.0
		return
	var pct := int(100.0 * float(best.hp) / float(best.max))
	var holding: bool = (Input.is_key_pressed(KEY_E) or game.args.has("autorepair")) and not game.busy
	var have := float(game.stores.scrap) >= 1.0
	if not have:
		game._prompt = {"kind": "repair", "label": "%s %d%%: no scrap in the stores" % [String(best.name).capitalize(), pct]}
		return
	game._prompt = {"kind": "repair", "label": "Hold E: repair %s (%d%%), 1 scrap per %d hp" % [String(best.name), pct, int(HP_PER_SCRAP)]}
	if holding:
		_rep_acc += _mend(best, REPAIR_HPS * dt)
		while _rep_acc >= HP_PER_SCRAP and float(game.stores.scrap) >= 1.0:
			_rep_acc -= HP_PER_SCRAP
			game.stores.scrap = float(game.stores.scrap) - 1.0
		game.run.sim.avatar.set_input(Vector2.ZERO, Vector2(best.center), false)
	else:
		_rep_acc = 0.0


## Tomas takes the weakest segment as his next stop (the crew code's "eat" slot is a one-off stop), and while he works there the segment mends.
func _tomas(dt: float) -> void:
	for m in game.crew.members:
		if String(m.def.id) != "tomas" or m.has("down"):
			continue
		if m.state == "wait" and not m.has("eat"):
			var w := weakest()
			if float(w.hp) < float(w.max) * 0.85 and float(game.stores.scrap) >= 1.0:
				m["eat"] = {"at": Vector2(w.fix), "secs": 9.0, "work": "mend", "face": "N", "say": "mending %s" % String(w.name), "repair": w}
		elif m.state == "work" and m.has("eat") and (m.eat as Dictionary).has("repair"):
			var s: Dictionary = m.eat.repair
			if float(s.hp) < float(s.max) and float(game.stores.scrap) >= 1.0:
				_rep_acc_t += _mend(s, TOMAS_HPS * dt)
				if _rep_acc_t >= HP_PER_SCRAP:
					_rep_acc_t -= HP_PER_SCRAP
					game.stores.scrap = float(game.stores.scrap) - 1.0


var _rep_acc_t := 0.0


# ------------------------------------------------------------------------------- ui --

func _show_banner(text: String, secs: float) -> void:
	_banner.text = text
	_banner_t = secs
	_banner.modulate.a = 1.0


func _end_attack() -> void:
	attacking = false
	var hp1 := 0.0
	for s in segs:
		hp1 += float(s.hp)
	var lost: Array = stats.lost
	var crew_lost: Array = stats.crew
	var txt := "MORNING.  %s\n\n" % String(stats.where)
	txt += "Fence lost:   %s\n" % (", ".join(lost) if not lost.is_empty() else "none")
	txt += "Fence damage: %d hp\n" % maxi(0, int(float(stats.hp0) - hp1))
	txt += "Dead killed:  %d of %d sent\n" % [int(stats.killed), int(stats.n)]
	txt += "Ammo used:    %d rounds (guards fired %d shots)\n" % [int(float(stats.ammo)), int(stats.shots)]
	txt += "Crew lost:    %s\n\n" % (", ".join(crew_lost.map(game.arc.events.label)) if not crew_lost.is_empty() else "nobody")    # (TRAITS: "Cole (Steady, Veteran)" and who they were, one line each)
	txt = txt.trim_suffix("\n\n") + "\n"
	for nm in crew_lost:
		if game.arc.events.bio_of(String(nm)) != "":
			txt += "  %s\n" % game.arc.events.bio_of(String(nm))
	txt += "\n"
	txt += "Weakest now:  %s %d%%     Scrap %d" % [String(weakest().name), int(100.0 * float(weakest().hp) / float(weakest().max)), int(game.stores.scrap)]
	_card_label.text = txt
	_card.visible = true
	_card_t = 16.0
	game.sound.play("bell", 0.7, 0.0)
	print("SIEGE RESULT night=%d where='%s' lost=%s killed=%d/%d ammo=%.1f shots=%d crew_lost=%s hp0=%.0f hp1=%.0f t=%.0f guards_off=%s" % [night, String(stats.where), lost, int(stats.killed), int(stats.n), float(stats.ammo), int(stats.shots), crew_lost, float(stats.hp0), hp1, t_att, guards_off])
	_report_done = true
	forced = false
	game.arc.night_over(night, stats)    # ARC hook
	if game.args.has("siegefor"):
		game.get_tree().quit()


func _ui(dt: float) -> void:
	var v: Vector2 = game._vp()
	_banner.size = Vector2(v.x, 50)
	_banner.position = Vector2(0, v.y * 0.2)
	if _banner_t > 0.0:
		_banner_t -= dt
		_banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
	_card.position = Vector2(v.x * 0.5 - _card.size.x * 0.5, v.y * 0.5 - _card.size.y * 0.5 - 40.0)
	if _card.visible:
		_card_t -= dt
		if _card_t <= 0.0 or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER):
			_card.visible = false


# ------------------------------------------------------------------------------ draw --

func _p(v: Vector2) -> Vector2:
	return v * TILE


## Drawn into the game's overlay (world pixels): cracks, a sag, or the gap with rubble. Plus a bar and a red pulse at a segment that is being torn at.
func paint(c: CanvasItem) -> void:
	var pulse := 0.5 + 0.5 * sin(game.clock * 7.0)
	for s in segs:
		var st := state_of(s)
		var al: Vector2 = s.along
		var nrm: Vector2 = s.out
		var a: Vector2 = Vector2(s.first) - al * 0.5
		var b: Vector2 = Vector2(s.last) + al * 0.5
		var len := (b - a).length()
		var seed_v := int(a.x * 31.0 + a.y * 17.0)
		if st != "ok":
			var marks := int(len / 2.2)
			for k in marks:
				var h := float((seed_v + k * 7919) % 97) / 97.0
				var t := (float(k) + 0.2 + 0.6 * h) / float(marks)
				var pt: Vector2 = a + (b - a) * t
				if st == "down" and absf((pt - Vector2(s.center)).dot(al)) < float(s.gap.size()) * 0.5:
					continue
				var crack: PackedVector2Array = PackedVector2Array([_p(pt - nrm * 0.35), _p(pt + nrm * 0.1 + al * 0.25), _p(pt - nrm * 0.05 - al * 0.15), _p(pt + nrm * 0.4 + al * 0.1)])
				c.draw_polyline(crack, Color(0.07, 0.05, 0.04, 0.9), 2.0)
			if st == "sagging" or st == "down":
				# bent posts and a drooping wire
				var posts := int(len / 3.0)
				var prev := Vector2.ZERO
				for k in posts + 1:
					var t2 := float(k) / float(maxi(posts, 1))
					var pt2: Vector2 = a + (b - a) * t2
					if st == "down" and absf((pt2 - Vector2(s.center)).dot(al)) < float(s.gap.size()) * 0.5 + 0.2:
						continue
					var lean := (0.25 + 0.2 * float((seed_v + k * 13) % 5) / 5.0) * (1.0 if k % 2 == 0 else -0.6)
					var top := pt2 - nrm * 0.1 + al * lean - Vector2(0, 0.75)
					c.draw_line(_p(pt2), _p(top), Color(0.22, 0.16, 0.1), 4.0)
					if k > 0 and prev != Vector2.ZERO:
						var mid := (prev + top) / 2.0 + Vector2(0, 0.35)
						c.draw_polyline(PackedVector2Array([_p(prev), _p(mid), _p(top)]), Color(0.45, 0.42, 0.38, 0.9), 1.5)
					prev = top
		if st == "down":
			var half := float(s.gap.size()) * 0.5
			var g0: Vector2 = Vector2(s.center) - al * half
			var rect_pos := Vector2(minf(g0.x, g0.x + al.x * half * 2.0), minf(g0.y, g0.y + al.y * half * 2.0)) - Vector2(0.0, 0.0)
			var rs := Vector2(absf(al.x) * half * 2.0 + absf(nrm.x) * 1.0, absf(al.y) * half * 2.0 + absf(nrm.y) * 1.0)
			rect_pos = Vector2(s.center) - rs / 2.0
			var dirt := Color(0.42, 0.34, 0.24) if s.side != "S" or not s.gate else Color(0.3, 0.3, 0.32)
			c.draw_rect(Rect2(_p(rect_pos - Vector2(0.0, 0.8)), _p(rs + Vector2(0.0, 0.8))), dirt)
			for k in 9:
				var h2 := float((seed_v + k * 4421) % 89) / 89.0
				var rp: Vector2 = Vector2(s.center) + al * (h2 - 0.5) * half * 1.8 + nrm * (float((seed_v + k * 31) % 7) / 7.0 - 0.45) * 0.7
				c.draw_rect(Rect2(_p(rp), Vector2(7 + k % 4 * 3, 5 + k % 3 * 3)), Color(0.2, 0.17, 0.14))
			var e0: Vector2 = Vector2(s.center) - al * half
			var e1: Vector2 = Vector2(s.center) + al * half
			c.draw_line(_p(e0), _p(e0 - Vector2(0, 0.8) + al * 0.3), Color(0.22, 0.16, 0.1), 4.0)
			c.draw_line(_p(e1), _p(e1 - Vector2(0, 0.8) - al * 0.4), Color(0.22, 0.16, 0.1), 4.0)
			c.draw_polyline(PackedVector2Array([_p(e0 + al * 0.6), _p(e0 + al * 1.2 + nrm * 0.4), _p(e0 + al * 1.8 - nrm * 0.1), _p(e0 + al * 2.6 + nrm * 0.35)]), Color(0.5, 0.48, 0.44), 1.5)
		if float(s.hit) > 0.0 or (attacking and s.attacked and float(s.hp) > 0.0):
			var col := Color(1.0, 0.25, 0.2, 0.35 + 0.35 * pulse) if float(s.hit) > 0.0 else Color(1.0, 0.6, 0.2, 0.25)
			c.draw_line(_p(a - nrm * 0.1), _p(b - nrm * 0.1), col, 5.0)
		if float(s.hp) < float(s.max) or float(s.hit) > 0.0:
			var f := float(s.hp) / float(s.max)
			var bc: Vector2 = _p(Vector2(s.center) - nrm * 1.1)
			var wpx := 70.0
			c.draw_rect(Rect2(bc - Vector2(wpx / 2.0, 5), Vector2(wpx, 10)), Color(0, 0, 0, 0.7))
			c.draw_rect(Rect2(bc - Vector2(wpx / 2.0, 5), Vector2(wpx * f, 10)), Color(0.85, 0.25, 0.2).lerp(Color(0.5, 0.85, 0.35), f))
	# the guards' dead
	var font := ThemeDB.fallback_font
	for m in game.crew.members:
		if m.has("down"):
			var at := Vector2(m.p.x, m.p.y - 2.1) * TILE
			c.draw_string(font, at - Vector2(80, 0), "%s is down!" % String(m.def.name), HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color(1, 0.3, 0.25))


func mini(bars: Control, o: Vector2, sc: float) -> void:
	for s in segs:
		var st := state_of(s)
		var a: Vector2 = Vector2(s.first) - Vector2(s.along) * 0.5
		var b: Vector2 = Vector2(s.last) + Vector2(s.along) * 0.5
		var col := Color(0, 0, 0, 0)
		match st:
			"cracked":
				col = Color(0.95, 0.8, 0.3)
			"sagging":
				col = Color(1.0, 0.5, 0.2)
			"down":
				col = Color(1.0, 0.1, 0.1)
		if attacking and s.attacked and st != "down":
			col = Color(1, 0.3, 0.25) if sin(game.clock * 7.0) > 0.0 else Color(1, 0.7, 0.4)
		if col.a > 0.0:
			bars.draw_line(o + a * sc, o + b * sc, col, 3.0)


## SAVE hook (prison_save.gd): the fence and the count of nights (saved only in the calm base, never in an attack).
func to_dict() -> Dictionary:
	var fence := {}
	for s in segs:
		fence[String(s.name)] = {"hp": float(s.hp), "max": float(s.max)}
	return {"fence": fence, "nights_started": nights_started, "night": night, "abs_h": abs_h, "report_done": _report_done}


## Puts the saved fence back (before the base is built: `setup` opens the gap of a segment with no hp left).
func from_dict(d: Dictionary) -> void:
	var fence: Dictionary = d.get("fence", {})
	for s in segs:
		if fence.has(String(s.name)):
			s.max = float(fence[String(s.name)].max)
			s.hp = clampf(float(fence[String(s.name)].hp), 0.0, float(s.max))
	nights_started = int(d.get("nights_started", 0))
	night = int(d.get("night", 0))
	abs_h = float(d.get("abs_h", abs_h))
	_last_tod = float(game.tod)
	_report_done = bool(d.get("report_done", false))
	attacking = false
	pending = 0
	forced = false
